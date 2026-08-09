#ifdef ANDROID
#include <sys/system_properties.h>
#endif
#include "util/types.hpp"
#include "util/sysinfo.hpp"
#include "util/Thread.h"
#include "JIT.h"
#include "StrFmt.h"
#include "File.h"
#include "util/logs.hpp"
#include "mutex.h"
#include "util/vm.hpp"
#include "rx/asm.hpp"
#include "rx/align.hpp"
#include "Crypto/sha1.h"
#include "Crypto/unzip.h"

#include <atomic>
#include <charconv>

#if defined(__APPLE__)
#include <pthread.h>
#endif

LOG_CHANNEL(jit_log, "JIT");

#ifdef LLVM_AVAILABLE

#include <unordered_map>
#include <vector>

#ifdef _MSC_VER
#pragma warning(push, 0)
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall"
#pragma GCC diagnostic ignored "-Wextra"
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#pragma GCC diagnostic ignored "-Wredundant-decls"
#pragma GCC diagnostic ignored "-Weffc++"
#pragma GCC diagnostic ignored "-Wmissing-noreturn"
#endif
#include <llvm/Support/CodeGen.h>
#include <llvm/Config/llvm-config.h>
#include <llvm/Bitcode/BitcodeWriter.h>
#include "llvm/Support/TargetSelect.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/ExecutionEngine/ExecutionEngine.h"
#include "llvm/ExecutionEngine/RTDyldMemoryManager.h"
#include "llvm/ExecutionEngine/ObjectCache.h"
#include "llvm/ExecutionEngine/JITEventListener.h"
#include "llvm/Object/ObjectFile.h"
#include "llvm/Object/SymbolSize.h"
#ifdef _MSC_VER
#pragma warning(pop)
#else
#pragma GCC diagnostic pop
#endif

#ifdef ARCH_ARM64
#include "Emu/CPU/Backends/AArch64/AArch64Common.h"
#endif

namespace
{
	thread_local std::string* g_llvm_fatal_message = nullptr;

	template <typename F>
	bool run_recoverable_llvm(F&& func, std::string& error)
	{
		error.clear();

		// Run LLVM codegen in a disposable thread. If LLVM invokes the fatal
		// handler, only this helper thread exits.
		named_thread worker("LLVM JIT", [&]()
		{
#if defined(__APPLE__)
			pthread_jit_write_protect_np(false);
#endif
			g_llvm_fatal_message = &error;

			std::forward<F>(func)();

			g_llvm_fatal_message = nullptr;
#if defined(__APPLE__)
			pthread_jit_write_protect_np(true);
#endif
		});

		worker();
		const bool result = static_cast<thread_state>(worker) == thread_state::finished;

		if (!result && error.empty())
		{
			error = "LLVM crash recovery invoked";
		}

		return result;
	}
}

struct jit_object_cache::impl
{
	llvm::object::OwningBinary<llvm::object::ObjectFile> binary;

	impl(std::unique_ptr<llvm::object::ObjectFile> object_file, std::unique_ptr<llvm::MemoryBuffer> buffer)
		: binary(std::move(object_file), std::move(buffer))
	{
	}
};

jit_object_cache::jit_object_cache() noexcept = default;
jit_object_cache::~jit_object_cache() = default;
jit_object_cache::jit_object_cache(jit_object_cache&&) noexcept = default;
jit_object_cache& jit_object_cache::operator=(jit_object_cache&&) noexcept = default;

jit_object_cache::jit_object_cache(std::unique_ptr<impl> cache) noexcept
	: m_impl(std::move(cache))
{
}

jit_object_cache::operator bool() const noexcept
{
	return !!m_impl;
}

void jit_object_cache::reset() noexcept
{
	m_impl.reset();
}

#if defined(ARCH_ARM64) && defined(ANDROID)
static bool android_arm64_cpu_enables_sve_by_default(const std::string& cpu)
{
	return cpu == "cortex-a510" ||
		cpu == "cortex-a520" ||
		cpu == "cortex-a520ae" ||
		cpu == "cortex-a710" ||
		cpu == "cortex-a715" ||
		cpu == "cortex-a720" ||
		cpu == "cortex-a720ae" ||
		cpu == "cortex-a725" ||
		cpu == "cortex-x2" ||
		cpu == "cortex-x3" ||
		cpu == "cortex-x4" ||
		cpu == "cortex-x925" ||
		cpu == "neoverse-n2" ||
		cpu == "neoverse-n3" ||
		cpu == "neoverse-v2" ||
		cpu == "neoverse-v3" ||
		cpu == "neoverse-v3ae";
}

static std::string sanitize_android_arm64_llvm_cpu(std::string cpu)
{
	std::transform(cpu.begin(), cpu.end(), cpu.begin(), ::tolower);

	if (!utils::has_sve() && android_arm64_cpu_enables_sve_by_default(cpu))
	{
		// Keep the real core name when asked.
		//
		// cortex-a78 is not a core in this device, and -mcpu selects the scheduling
		// model for all JIT output. Verified off-device that the substitution is not
		// load-bearing: cortex-a715+nosve yields "-sve -sve2" while keeping +dotprod
		// and +i8mm, and this JIT already passes -sve,-sve2 in its feature string, so
		// SVE is suppressed twice over. See docs/arm64/codegen.md.
		//
		// Off by default until the A/B says the scheduling model is worth anything --
		// nine predictions of this shape have been refuted on this project.
		{
			char value[PROP_VALUE_MAX]{};
			const int length = __system_property_get("debug.rpcsx.thor.jit_cpu_native", value);
			if (length > 0 && value[0] != '0' && value[0] != 'n' && value[0] != 'f')
			{
				jit_log.warning("LLVM CPU '%s' kept; SVE suppressed by the feature string.", cpu);
				return cpu;
			}
		}

		jit_log.warning("LLVM CPU '%s' enables SVE in bundled LLVM, but Android HWCAP does not report SVE. Using cortex-a78 for Thor-safe JIT code.", cpu);
		return "cortex-a78";
	}

	return cpu;
}
#endif

const bool jit_initialize = []() -> bool
{
	llvm::InitializeAllTargetInfos();
	llvm::InitializeAllTargets();
	llvm::InitializeAllTargetMCs();
	llvm::InitializeAllAsmPrinters();
	llvm::InitializeAllAsmParsers();
	LLVMLinkInMCJIT();
	return true;
}();

[[noreturn]] static void null(const char* name)
{
	fmt::throw_exception("Null function: %s", name);
}

namespace vm
{
	extern u8* const g_sudo_addr;
}

static shared_mutex null_mtx;

static std::unordered_map<std::string, u64> null_funcs;

#if defined(ARCH_ARM64)
static std::string join_jit_attributes(const std::vector<std::string>& attributes)
{
	std::string result;

	for (const std::string& attribute : attributes)
	{
		if (!result.empty())
		{
			result += ",";
		}

		result += attribute;
	}

	return result.empty() ? "none" : result;
}

static void report_aarch64_jit_target_once(const std::string& cpu, const std::string& triple, const std::vector<std::string>& attributes, u32 flags, bool uses_link_table)
{
	static shared_mutex s_reported_mutex;
	static std::vector<std::string> s_reported_keys;

	const std::string attr_text = join_jit_attributes(attributes);
	const std::string key = fmt::format("%s|%s|%s|0x%x|%u", cpu, triple, attr_text, flags, uses_link_table ? 1 : 0);

	std::lock_guard lock(s_reported_mutex);

	for (const std::string& reported_key : s_reported_keys)
	{
		if (reported_key == key)
		{
			return;
		}
	}

	s_reported_keys.emplace_back(key);
	jit_log.notice("LLVM AArch64 target: cpu=%s triple=%s attrs=%s flags=0x%x link-table=%s", cpu, triple, attr_text, flags, uses_link_table ? "yes" : "no");
}
#endif

static u64 make_null_function(const std::string& name)
{
	if (name.starts_with("__0x"))
	{
		u32 addr = -1;
		auto res = std::from_chars(name.c_str() + 4, name.c_str() + name.size(), addr, 16);

		if (res.ec == std::errc() && res.ptr == name.c_str() + name.size() && addr < 0x8000'0000)
		{
			fmt::throw_exception("Unhandled symbols cementing! (name='%s'", name);
		}
	}

	std::lock_guard lock(null_mtx);

	if (u64& func_ptr = null_funcs[name]) [[likely]]
	{
		// Already exists
		return func_ptr;
	}
	else
	{
		using namespace asmjit;

		// Build a "null" function that contains its name
		const auto func = build_function_asm<void (*)()>("NULL", [&](native_asm& c, auto& args)
			{
#if defined(ARCH_X64)
				Label data = c.newLabel();
				c.lea(args[0], x86::qword_ptr(data, 0));
				c.jmp(Imm(&null));
				c.align(AlignMode::kCode, 16);
				c.bind(data);

				// Copy function name bytes
				for (char ch : name)
					c.db(ch);
				c.db(0);
				c.align(AlignMode::kData, 16);
#else
				// AArch64 implementation
				Label data = c.newLabel();
				Label jump_address = c.newLabel();
				c.ldr(args[0], arm::ptr(data, 0));
				c.ldr(a64::x14, arm::ptr(jump_address, 0));
				c.br(a64::x14);

				// Data frame
				c.align(AlignMode::kCode, 16);
				c.bind(jump_address);
				c.embedUInt64(reinterpret_cast<u64>(&null));

				c.align(AlignMode::kData, 16);
				c.bind(data);
				c.embed(name.c_str(), name.size());
				c.embedUInt8(0U);
				c.align(AlignMode::kData, 16);
#endif
			});

		func_ptr = reinterpret_cast<u64>(func);
		return func_ptr;
	}
}

struct JITAnnouncer : llvm::JITEventListener
{
	void notifyObjectLoaded(u64, const llvm::object::ObjectFile& obj, const llvm::RuntimeDyld::LoadedObjectInfo& info) override
	{
		using namespace llvm;

		object::OwningBinary<object::ObjectFile> debug_obj_ = info.getObjectForDebug(obj);
		if (!debug_obj_.getBinary())
		{
#ifdef __linux__
			jit_log.error("LLVM: Failed to announce JIT events (no debug object)");
#endif
			return;
		}

		const object::ObjectFile& debug_obj = *debug_obj_.getBinary();

		for (const auto& [sym, size] : computeSymbolSizes(debug_obj))
		{
			Expected<object::SymbolRef::Type> type_ = sym.getType();
			if (!type_ || *type_ != object::SymbolRef::ST_Function)
				continue;

			Expected<StringRef> name = sym.getName();
			if (!name)
				continue;

			Expected<u64> addr = sym.getAddress();
			if (!addr)
				continue;

			jit_announce(*addr, size, {name->data(), name->size()});
		}
	}
};

// Simple memory manager
// AArch64 instruction caches are not coherent with the data caches. MCJIT writes
// code through normal stores, so unless the instruction cache is invalidated for
// those addresses the core may fetch whatever was there before.
//
// Whether that maintenance is actually required is advertised in CTR_EL0. Read
// on the AYN Thor's Snapdragon 8 Gen 2: IDC=1, DIC=0. So the data cache does not
// need cleaning to the point of unification, but the instruction cache *does*
// need invalidating. Apple Silicon reports DIC=1, which is very likely why this
// never surfaced upstream despite RPCS3 running on arm64 Macs.
//
// The stock llvm::SectionMemoryManager does this in finalizeMemory. Both
// managers here override finalizeMemory to return false and do nothing, so
// nothing was invalidating anything. __builtin___clear_cache expands to the
// architecturally correct sequence and consults CTR_EL0 itself.
using jit_code_ranges_t = std::vector<std::pair<u8*, uptr>>;

static void jit_record_code_section([[maybe_unused]] jit_code_ranges_t& ranges, [[maybe_unused]] u8* ptr, [[maybe_unused]] uptr size)
{
#ifdef ARCH_ARM64
	if (ptr && size)
	{
		ranges.emplace_back(ptr, size);
	}
#endif
}

static void jit_flush_code_sections([[maybe_unused]] jit_code_ranges_t& ranges)
{
#ifdef ARCH_ARM64
	for (const auto& [ptr, size] : ranges)
	{
		__builtin___clear_cache(reinterpret_cast<char*>(ptr), reinterpret_cast<char*>(ptr) + size);
	}

	ranges.clear();
#endif
}

struct MemoryManager1 : llvm::RTDyldMemoryManager
{
	// 256 MiB for code or data
	static constexpr u64 c_max_size = 0x1000'0000;

	// Allocation unit (2M)
	static constexpr u64 c_page_size = 2 * 1024 * 1024;

	// Reserve 256 MiB blocks
	void* m_code_mems = nullptr;
	void* m_data_ro_mems = nullptr;
	void* m_data_rw_mems = nullptr;

	u64 code_ptr = 0;
	u64 data_ro_ptr = 0;
	u64 data_rw_ptr = 0;

	// First fallback for non-existing symbols
	// May be a memory container internally
	std::function<u64(const std::string&)> m_symbols_cement;

	// Code sections written since the last finalizeMemory, pending i-cache
	// invalidation. Empty and unused where i-caches are coherent.
	jit_code_ranges_t m_code_ranges;

	MemoryManager1(std::function<u64(const std::string&)> symbols_cement = {}) noexcept
		: m_symbols_cement(std::move(symbols_cement))
	{
		auto ptr = reinterpret_cast<u8*>(utils::memory_reserve(c_max_size * 3));
		m_code_mems = ptr;
		// ptr += c_max_size;
		// m_data_ro_mems = ptr;
		ptr += c_max_size;
		m_data_rw_mems = ptr;
	}

	MemoryManager1(const MemoryManager1&) = delete;

	MemoryManager1& operator=(const MemoryManager1&) = delete;

	~MemoryManager1() override
	{
		// Hack: don't release to prevent reuse of address space, see jit_announce
		// constexpr auto how_much = [](u64 pos) { return rx::alignUp(pos, pos < c_page_size ? c_page_size / 4 : c_page_size); };
		// utils::memory_decommit(m_code_mems, how_much(code_ptr));
		// utils::memory_decommit(m_data_ro_mems, how_much(data_ro_ptr));
		// utils::memory_decommit(m_data_rw_mems, how_much(data_rw_ptr));
		utils::memory_decommit(m_code_mems, c_max_size * 3);
	}

	llvm::JITSymbol findSymbol(const std::string& name) override
	{
		u64 addr = RTDyldMemoryManager::getSymbolAddress(name);

		if (!addr && m_symbols_cement)
		{
			addr = m_symbols_cement(name);
		}

		if (!addr)
		{
			addr = make_null_function(name);

			if (!addr)
			{
				fmt::throw_exception("Failed to link '%s'", name);
			}
		}

		return {addr, llvm::JITSymbolFlags::Exported};
	}

	u8* allocate(u64& alloc_pos, void* block, uptr size, u64 align, utils::protection prot)
	{
		align = align ? align : 16;

		const u64 sizea = rx::alignUp(size, align);

		if (!size || align > c_page_size || sizea > c_max_size || sizea < size)
		{
			jit_log.fatal("Unsupported size/alignment (size=0x%x, align=0x%x)", size, align);
			return nullptr;
		}

		u64 oldp = alloc_pos;

		u64 olda = rx::alignUp(oldp, align);

		ensure(olda >= oldp);
		ensure(olda < ~sizea);

		u64 newp = olda + sizea;

		if ((newp - 1) / c_max_size != (oldp - 1) / c_max_size)
		{
			constexpr usz num_of_allocations = 1;

			if ((newp - 1) / c_max_size > num_of_allocations)
			{
				// Allocating more than one region does not work for relocations, needs more robust solution
				fmt::throw_exception("Out of memory (size=0x%x, align=0x%x)", size, align);
			}
		}

		// Update allocation counter
		alloc_pos = newp;

		constexpr usz page_quarter = c_page_size / 4;

		// Optimization: split the first allocation to 512 KiB for single-module compilers
		if (oldp < c_page_size && align < page_quarter && (std::min(newp, c_page_size) - 1) / page_quarter != (oldp - 1) / page_quarter)
		{
			const u64 pagea = rx::alignUp(oldp, page_quarter);
			const u64 psize = rx::alignUp(std::min(newp, c_page_size) - pagea, page_quarter);
			utils::memory_commit(reinterpret_cast<u8*>(block) + (pagea % c_max_size), psize, prot);

			// Advance
			oldp = pagea + psize;
		}

		if ((newp - 1) / c_page_size != (oldp - 1) / c_page_size)
		{
			// Allocate pages on demand
			const u64 pagea = rx::alignUp(oldp, c_page_size);
			const u64 psize = rx::alignUp(newp - pagea, c_page_size);
			utils::memory_commit(reinterpret_cast<u8*>(block) + (pagea % c_max_size), psize, prot);
		}

		return reinterpret_cast<u8*>(block) + (olda % c_max_size);
	}

	u8* allocateCodeSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/) override
	{
		u8* const ptr = allocate(code_ptr, m_code_mems, size, align, utils::protection::wx);
		jit_record_code_section(m_code_ranges, ptr, size);
		return ptr;
	}

	u8* allocateDataSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/, bool is_ro) override
	{
		if (is_ro)
		{
			// Disabled
			// return allocate(data_ro_ptr, m_data_ro_mems, size, align, utils::protection::rw);
		}

		return allocate(data_rw_ptr, m_data_rw_mems, size, align, utils::protection::rw);
	}

	bool finalizeMemory(std::string* = nullptr) override
	{
		// Nothing here changes protection, but code just written still has to be
		// published to instruction fetch on AArch64. See jit_flush_code_sections.
		jit_flush_code_sections(m_code_ranges);
		return false;
	}

	void registerEHFrames(u8*, u64, usz) override
	{
	}

	void deregisterEHFrames() override
	{
	}
};

// Simple memory manager
struct MemoryManager2 : llvm::RTDyldMemoryManager
{
	// First fallback for non-existing symbols
	// May be a memory container internally
	std::function<u64(const std::string&)> m_symbols_cement;

	// Code sections written since the last finalizeMemory, pending i-cache
	// invalidation. Empty and unused where i-caches are coherent.
	jit_code_ranges_t m_code_ranges;

	MemoryManager2(std::function<u64(const std::string&)> symbols_cement = {}) noexcept
		: m_symbols_cement(std::move(symbols_cement))
	{
	}

	~MemoryManager2() override
	{
	}

	llvm::JITSymbol findSymbol(const std::string& name) override
	{
		u64 addr = RTDyldMemoryManager::getSymbolAddress(name);

		if (!addr && m_symbols_cement)
		{
			addr = m_symbols_cement(name);
		}

		if (!addr)
		{
			addr = make_null_function(name);

			if (!addr)
			{
				fmt::throw_exception("Failed to link '%s' (MM2)", name);
			}
		}

		return {addr, llvm::JITSymbolFlags::Exported};
	}

	u8* allocateCodeSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/) override
	{
		u8* const ptr = jit_runtime::alloc(size, align, true);
		jit_record_code_section(m_code_ranges, ptr, size);
		return ptr;
	}

	u8* allocateDataSection(uptr size, uint align, uint /*sec_id*/, llvm::StringRef /*sec_name*/, bool /*is_ro*/) override
	{
		return jit_runtime::alloc(size, align, false);
	}

	bool finalizeMemory(std::string* = nullptr) override
	{
		// Nothing here changes protection, but code just written still has to be
		// published to instruction fetch on AArch64. See jit_flush_code_sections.
		jit_flush_code_sections(m_code_ranges);
		return false;
	}

	void registerEHFrames(u8*, u64, usz) override
	{
	}

	void deregisterEHFrames() override
	{
	}
};

class vector_memory_buffer final : public llvm::MemoryBuffer
{
	std::vector<u8> m_data;

public:
	explicit vector_memory_buffer(std::vector<u8> data)
		: m_data(std::move(data))
	{
		m_data.push_back(0);
		const auto* begin = reinterpret_cast<const char*>(m_data.data());
		init(begin, begin + m_data.size() - 1, true);
	}

	BufferKind getBufferKind() const override
	{
		return MemoryBuffer_Malloc;
	}
};

class sha1_raw_ostream final : public llvm::raw_ostream
{
	sha1_context& m_context;
	u64 m_position = 0;

	void write_impl(const char* data, std::size_t size) override
	{
		sha1_update(&m_context, reinterpret_cast<const u8*>(data), size);
		m_position += size;
	}

	u64 current_pos() const override
	{
		return m_position;
	}

public:
	explicit sha1_raw_ostream(sha1_context& context)
		: m_context(context)
	{
		SetUnbuffered();
	}
};

#ifdef __ANDROID__
static std::atomic_bool g_materialize_raw_object_cache{false};
static std::atomic<usz> g_raw_object_cache_budget{0};
#endif

// Helper class
class ObjectCache final : public llvm::ObjectCache
{
	const std::string& m_path;
	const std::add_pointer_t<jit_compiler> m_compiler = nullptr;

public:
	ObjectCache(const std::string& path, jit_compiler* compiler = nullptr)
		: m_path(path), m_compiler(compiler)
	{
	}

	~ObjectCache() override = default;

	void notifyObjectCompiled(const llvm::Module* _module, llvm::MemoryBufferRef obj) override
	{
		std::string name = m_path;

		name.append(_module->getName());
		// Raw objects trade modest storage for lower boot CPU pressure on Android.
		// Desktop retains RPCS3's compressed cache format.
#ifndef __ANDROID__
		name.append(".gz");
#endif

		if (!obj.getBufferSize())
		{
			jit_log.error("LLVM: Nothing to write: %s", name);
			return;
		}

		ensure(m_compiler);

		fs::pending_file module_file;

		if (!module_file.open((name)))
		{
			jit_log.error("LLVM: Failed to create module file: %s (%s)", name, fs::g_tls_error);
			return;
		}

		// Bold assumption about upper limit of space consumption for compression.
		// Android raw objects reserve exactly their final payload size.
#ifdef __ANDROID__
		const usz max_size = obj.getBufferSize();
#else
		const usz max_size = obj.getBufferSize() * 4;
#endif

		if (!m_compiler->add_sub_disk_space(0 - max_size))
		{
			jit_log.error("LLVM: Failed to create module file: %s (not enough disk space left)", name);
			return;
		}

#ifdef __ANDROID__
		if (module_file.file.write(obj.getBufferStart(), obj.getBufferSize()) != obj.getBufferSize())
		{
			jit_log.error("LLVM: Failed to write raw module: %s", std::string(_module->getName()));
			return;
		}
#else
		if (!zip(obj.getBufferStart(), obj.getBufferSize(), module_file.file))
		{
			jit_log.error("LLVM: Failed to compress module: %s", std::string(_module->getName()));
			return;
		}
#endif

		jit_log.trace("LLVM: Created module: %s", std::string(_module->getName()));

		// Restore space that was overestimated
		ensure(m_compiler->add_sub_disk_space(max_size - module_file.file.size()));

		if (!module_file.commit())
		{
			jit_log.error("LLVM: Failed to commit module file: %s (%s)", name, fs::g_tls_error);
			return;
		}

#ifdef __ANDROID__
		// A committed raw object is authoritative. Removing the legacy sidecar
		// prevents duplicate storage and guarantees the raw-first load path.
		fs::remove_file(name + ".gz");
#endif
	}

	static std::unique_ptr<llvm::MemoryBuffer> load_compressed(const std::string& path)
	{
		if (fs::file cached{path + ".gz", fs::read})
		{
			const std::vector<u8> cached_data = cached.to_vector<u8>();

			if (cached_data.empty()) [[unlikely]]
			{
				return nullptr;
			}

			auto out = unzip(cached_data);

			if (out.empty())
			{
				jit_log.error("LLVM: Failed to unzip module: '%s'", path);
				return nullptr;
			}

			return std::make_unique<vector_memory_buffer>(std::move(out));
		}

		return nullptr;
	}

	static std::unique_ptr<llvm::MemoryBuffer> load_raw(const std::string& path)
	{
		if (fs::file cached{path, fs::read})
		{
			if (cached.size() == 0) [[unlikely]]
			{
				return nullptr;
			}

			auto buf = llvm::WritableMemoryBuffer::getNewUninitMemBuffer(cached.size());
			cached.read(buf->getBufferStart(), buf->getBufferSize());
			return buf;
		}

		return nullptr;
	}

	static std::unique_ptr<llvm::MemoryBuffer> load(const std::string& path, bool* loaded_compressed = nullptr)
	{
		if (loaded_compressed)
		{
			*loaded_compressed = false;
		}

#ifdef __ANDROID__
		if (auto raw = load_raw(path))
		{
			return raw;
		}

		if (auto compressed = load_compressed(path))
		{
			if (loaded_compressed)
			{
				*loaded_compressed = true;
			}
			return compressed;
		}
#else
		if (auto compressed = load_compressed(path))
		{
			if (loaded_compressed)
			{
				*loaded_compressed = true;
			}
			return compressed;
		}

		if (auto raw = load_raw(path))
		{
			return raw;
		}
#endif

		return nullptr;
	}

#ifdef __ANDROID__
	static bool materialize_raw(const std::string& path, const llvm::MemoryBuffer& buffer)
	{
		const usz size = buffer.getBufferSize();
		usz remaining = g_raw_object_cache_budget.load(std::memory_order_relaxed);
		bool reserved = false;

		while (size && remaining >= size)
		{
			if (g_raw_object_cache_budget.compare_exchange_weak(remaining, remaining - size, std::memory_order_relaxed))
			{
				reserved = true;
				break;
			}
		}

		if (!reserved)
		{
			jit_log.warning("ObjectCache: Keeping compressed module (raw-cache budget exhausted): %s", path);
			return false;
		}

		fs::pending_file raw_file;
		if (!raw_file.open(path))
		{
			jit_log.warning("ObjectCache: Failed to create raw module: %s (%s)", path, fs::g_tls_error);
			g_raw_object_cache_budget.fetch_add(size, std::memory_order_relaxed);
			return false;
		}

		if (raw_file.file.write(buffer.getBufferStart(), size) != size || !raw_file.commit())
		{
			jit_log.warning("ObjectCache: Failed to materialize raw module: %s (%s)", path, fs::g_tls_error);
			g_raw_object_cache_budget.fetch_add(size, std::memory_order_relaxed);
			return false;
		}

		if (!fs::remove_file(path + ".gz"))
		{
			jit_log.warning("ObjectCache: Raw module committed but legacy sidecar remains: %s", path);
		}

		jit_log.notice("ObjectCache: Materialized validated raw Android module: %s", path);
		return true;
	}
#endif

	std::unique_ptr<llvm::MemoryBuffer> getObject(const llvm::Module* _module) override
	{
		std::string path = m_path;
		path.append(_module->getName().data());

		if (auto buf = load(path))
		{
			// A damaged warm object must fall back to normal code generation rather
			// than entering MCJIT's fatal object-loading path.
			if (llvm::object::ObjectFile::createObjectFile(*buf))
			{
				jit_log.notice("LLVM: Loaded module: %s", _module->getName().data());
				return buf;
			}

			const bool removed_raw = fs::remove_file(path);
			const bool removed_compressed = fs::remove_file(path + ".gz");
			if (removed_raw || removed_compressed)
			{
				jit_log.error("ObjectCache: Removed damaged compile object: %s", path);
			}
		}

		return nullptr;
	}
};

std::string jit_compiler::cpu(const std::string& _cpu)
{
	std::string m_cpu = _cpu;

	if (m_cpu.empty())
	{
		m_cpu = llvm::sys::getHostCPUName().str();

		if (m_cpu == "generic")
		{
			// Try to detect a best match based on other criteria
			m_cpu = fallback_cpu_detection();
		}

		if (m_cpu == "sandybridge" ||
			m_cpu == "ivybridge" ||
			m_cpu == "haswell" ||
			m_cpu == "broadwell" ||
			m_cpu == "skylake" ||
			m_cpu == "skylake-avx512" ||
			m_cpu == "cascadelake" ||
			m_cpu == "cooperlake" ||
			m_cpu == "cannonlake" ||
			m_cpu == "icelake" ||
			m_cpu == "icelake-client" ||
			m_cpu == "icelake-server" ||
			m_cpu == "tigerlake" ||
			m_cpu == "rocketlake" ||
			m_cpu == "alderlake" ||
			m_cpu == "raptorlake" ||
			m_cpu == "meteorlake")
		{
			// Downgrade if AVX is not supported by some chips
			if (!utils::has_avx())
			{
				m_cpu = "nehalem";
			}
		}

		if (m_cpu == "skylake-avx512" ||
			m_cpu == "cascadelake" ||
			m_cpu == "cooperlake" ||
			m_cpu == "cannonlake" ||
			m_cpu == "icelake" ||
			m_cpu == "icelake-client" ||
			m_cpu == "icelake-server" ||
			m_cpu == "tigerlake" ||
			m_cpu == "rocketlake")
		{
			// Downgrade if AVX-512 is disabled or not supported
			if (!utils::has_avx512())
			{
				m_cpu = "skylake";
			}
		}

		if (m_cpu == "znver1" && utils::has_clwb())
		{
			// Upgrade
			m_cpu = "znver2";
		}

		if ((m_cpu == "znver3" || m_cpu == "goldmont" || m_cpu == "alderlake" || m_cpu == "raptorlake" || m_cpu == "meteorlake") && utils::has_avx512_icl())
		{
			// Upgrade
			m_cpu = "icelake-client";
		}

		if (m_cpu == "goldmont" && utils::has_avx2())
		{
			// Upgrade
			m_cpu = "alderlake";
		}
	}

#if defined(ARCH_ARM64) && defined(ANDROID)
	m_cpu = sanitize_android_arm64_llvm_cpu(m_cpu);
#endif

	return m_cpu;
}

std::string jit_compiler::triple1()
{
#if defined(_WIN32)
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#elif defined(__APPLE__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif (defined(__ANDROID__) || defined(__APPLE__)) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-android"); // Set environment to android to reserve x18
#elif defined(__ANDROID__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-android");
#else
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#endif
}

std::string jit_compiler::triple2()
{
#if defined(_WIN32) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif defined(_WIN32) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-gnu");
#elif defined(__APPLE__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-gnu");
#elif (defined(__ANDROID__) || defined(__APPLE__)) && defined(ARCH_ARM64)
	return llvm::Triple::normalize("aarch64-unknown-linux-android"); // Set environment to android to reserve x18
#elif defined(__ANDROID__) && defined(ARCH_X64)
	return llvm::Triple::normalize("x86_64-unknown-linux-android"); // Set environment to android to reserve x18
#else
	return llvm::Triple::normalize(llvm::sys::getProcessTriple());
#endif
}

bool jit_compiler::add_sub_disk_space(ssz space)
{
	if (space >= 0)
	{
		ensure(m_disk_space.fetch_add(space) < ~static_cast<usz>(space));
		return true;
	}

	return m_disk_space.fetch_op([sub_size = static_cast<usz>(0 - space)](usz& val)
						   {
							   if (val >= sub_size)
							   {
								   val -= sub_size;
								   return true;
							   }

							   return false;
						   })
	    .second;
}

jit_compiler::jit_compiler(const std::unordered_map<std::string, u64>& _link, const std::string& _cpu, u32 flags, std::function<u64(const std::string&)> symbols_cement) noexcept
	: m_context(new llvm::LLVMContext, [](llvm::LLVMContext* context)
		  {
			  delete context;
		  }),
	  m_cpu(cpu(_cpu))
{
	[[maybe_unused]] static const bool s_install_llvm_error_handler = []()
	{
		llvm::remove_fatal_error_handler();
		llvm::install_fatal_error_handler([](void*, const char* msg, bool)
			{
				const std::string_view out = msg ? msg : "";

				if (g_llvm_fatal_message)
				{
					*g_llvm_fatal_message = out;
					thread_ctrl::silent_exit();
				}

				fmt::throw_exception("LLVM Emergency Exit Invoked: '%s'", out);
			},
			nullptr);

		return true;
	}();

	std::string result;

	auto null_mod = std::make_unique<llvm::Module>("null_", *m_context);
	null_mod->setTargetTriple(jit_compiler::triple1());

	std::unique_ptr<llvm::RTDyldMemoryManager> mem;

	if (_link.empty())
	{
		// Auxiliary JIT (does not use custom memory manager, only writes the objects)
		if (flags & 0x1)
		{
			mem = std::make_unique<MemoryManager1>(std::move(symbols_cement));
		}
		else
		{
			mem = std::make_unique<MemoryManager2>(std::move(symbols_cement));
			null_mod->setTargetTriple(jit_compiler::triple2());
		}
	}
	else
	{
		mem = std::make_unique<MemoryManager1>(std::move(symbols_cement));
	}

	const std::string target_triple = null_mod->getTargetTriple();

	std::vector<std::string> attributes;

#if defined(ARCH_ARM64)
	const bool is_spu_codegen = (flags & jit_compiler::spu_codegen_flag) != 0;
	const bool use_dotprod = !is_spu_codegen ? utils::has_dotprod() : utils::use_spu_dotprod();
	const bool use_i8mm = !is_spu_codegen ? utils::has_i8mm() : utils::use_spu_i8mm();

	if (utils::has_sha3())
		attributes.push_back("+sha3");
	else
		attributes.push_back("-sha3");

	if (use_dotprod)
		attributes.push_back("+dotprod");
	else
		attributes.push_back("-dotprod");

	// The SPU recompilers emit UMMLA/SMMLA intrinsics when I8MM is present.
	// Advertise the feature explicitly because the Android cortex-a78 fallback
	// CPU does not imply it even though Snapdragon 8 Gen 2 supports it.
	if (use_i8mm)
		attributes.push_back("+i8mm");
	else
		attributes.push_back("-i8mm");

	if (is_spu_codegen && utils::get_arm64_spu_feature_mode() != utils::arm64_spu_feature_mode::native)
	{
		jit_log.notice("AArch64 SPU JIT feature isolation mode: %s (dotprod=%s, i8mm=%s).",
			utils::get_arm64_spu_feature_mode_name(), use_dotprod, use_i8mm);
	}

	if (utils::has_sve())
		attributes.push_back("+sve");
	else
		attributes.push_back("-sve");

	if (utils::has_sve2())
		attributes.push_back("+sve2");
	else
		attributes.push_back("-sve2");
#endif

	{

		m_engine = std::unique_ptr<llvm::ExecutionEngine, void (*)(llvm::ExecutionEngine*)>{
			llvm::EngineBuilder(std::move(null_mod))
				.setErrorStr(&result)
				.setEngineKind(llvm::EngineKind::JIT)
				.setMCJITMemoryManager(std::move(mem))
				.setOptLevel(llvm::CodeGenOptLevel::Aggressive)
				.setCodeModel(flags & 0x2 ? llvm::CodeModel::Large : llvm::CodeModel::Small)
#ifdef __APPLE__
		//.setCodeModel(llvm::CodeModel::Large)
#endif
				.setRelocationModel(llvm::Reloc::Model::PIC_)
				.setMAttrs(attributes)
				.setMCPU(m_cpu)
				.create(),
			[](llvm::ExecutionEngine* engine)
			{
				delete engine;
			},
		};
	}

	if (!_link.empty())
	{
		for (auto&& [name, addr] : _link)
		{
			m_engine->updateGlobalMapping(name, addr);
		}
	}

	if (!_link.empty() || !(flags & 0x1))
	{
#ifdef ARCH_X64
		m_engine->RegisterJITEventListener(llvm::JITEventListener::createIntelJITEventListener());
#endif
		m_engine->RegisterJITEventListener(new JITAnnouncer);
	}

	if (!m_engine)
	{
		fmt::throw_exception("LLVM: Failed to create ExecutionEngine: %s", result);
	}

	std::string attribute_identity;
	for (const std::string& attribute : attributes)
	{
		if (!attribute_identity.empty())
		{
			attribute_identity += ',';
		}

		attribute_identity += attribute;
	}

	m_object_cache_identity = fmt::format("llvm=%s|cpu=%s|triple=%s|attrs=%s|flags=0x%x|layout=%s",
		LLVM_VERSION_STRING, m_cpu, target_triple, attribute_identity,
		flags, m_engine->getTargetMachine()->createDataLayout().getStringRepresentation());

#if defined(ARCH_ARM64)
	report_aarch64_jit_target_once(m_cpu, target_triple, attributes, flags, !_link.empty());
#endif

	fs::device_stat stats{};

	if (fs::statfs(fs::get_cache_dir(), stats))
	{
		m_disk_space = stats.avail_free / 4;
	}
}

jit_compiler& jit_compiler::operator=(thread_state s) noexcept
{
	if (s == thread_state::destroying_context)
	{
		// Release resources explicitly
		m_engine.reset();
		m_context.reset();
	}

	return *this;
}

jit_compiler::~jit_compiler() noexcept
{
}

void jit_compiler::add(std::unique_ptr<llvm::Module> _module, const std::string& path)
{
	ObjectCache cache{path, this};
	m_engine->setObjectCache(&cache);

	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));
	m_engine->generateCodeForModule(ptr);
	m_engine->setObjectCache(nullptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}
}

bool jit_compiler::try_add(std::unique_ptr<llvm::Module> _module, const std::string& path, std::string& error)
{
	ObjectCache cache{path, this};
	m_engine->setObjectCache(&cache);

	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));

	if (!run_recoverable_llvm([&]()
	{
		m_engine->generateCodeForModule(ptr);
	}, error))
	{
		return false;
	}

	m_engine->setObjectCache(nullptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}

	return true;
}

void jit_compiler::add(std::unique_ptr<llvm::Module> _module)
{
	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));
	m_engine->generateCodeForModule(ptr);

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}
}

bool jit_compiler::try_add(std::unique_ptr<llvm::Module> _module, std::string& error)
{
	const auto ptr = _module.get();
	m_engine->addModule(std::move(_module));

	if (!run_recoverable_llvm([&]()
	{
		m_engine->generateCodeForModule(ptr);
	}, error))
	{
		return false;
	}

	for (auto& func : ptr->functions())
	{
		// Delete IR to lower memory consumption
		func.deleteBody();
	}

	return true;
}

bool jit_compiler::add(const std::string& path, jit_object_cache cache)
{
	if (cache)
	{
		m_engine->addObjectFile(std::move(cache.m_impl->binary));
		jit_log.trace("ObjectCache: Successfully added validated %s", path);
		return true;
	}

	auto owned_cache = ObjectCache::load(path);

	if (!owned_cache)
	{
		jit_log.error("ObjectCache: Failed to read file. (path='%s', error=%s)", path, fs::g_tls_error);
		return false;
	}

	if (auto object_file = llvm::object::ObjectFile::createObjectFile(*owned_cache))
	{
		m_engine->addObjectFile(llvm::object::OwningBinary<llvm::object::ObjectFile>(std::move(*object_file), std::move(owned_cache)));
		jit_log.trace("ObjectCache: Successfully added %s", path);
		return true;
	}
	else
	{
		jit_log.error("ObjectCache: Adding failed: %s", path);
		return false;
	}
}

std::string jit_compiler::make_object_cache_key(const llvm::Module& module, std::string_view schema) const
{
	sha1_context context;
	u8 output[20];
	sha1_starts(&context);
	sha1_update(&context, reinterpret_cast<const u8*>(schema.data()), schema.size());
	const u8 separator = 0;
	sha1_update(&context, &separator, 1);
	sha1_update(&context, reinterpret_cast<const u8*>(m_object_cache_identity.data()), m_object_cache_identity.size());
	sha1_update(&context, &separator, 1);

	// Serialize after the SPU transform/optimization pipeline so the key captures
	// every IR decision, including launch-specific absolute constants. Bitcode
	// avoids the formatting and escaping cost of textual IR, while preserving
	// use-list order keeps the key an exact structural identity.
	sha1_raw_ostream stream(context);
	llvm::WriteBitcodeToFile(module, stream, true);
	stream.flush();
	sha1_finish(&context, output);
	return fmt::format("%s", fmt::base57(output));
}

jit_object_cache jit_compiler::check(const std::string& path)
{
	bool loaded_compressed = false;
	if (auto cache = ObjectCache::load(path, &loaded_compressed))
	{
		if (auto object_file = llvm::object::ObjectFile::createObjectFile(*cache))
		{
#ifdef __ANDROID__
			if (loaded_compressed && g_materialize_raw_object_cache.load(std::memory_order_acquire))
			{
				ObjectCache::materialize_raw(path, *cache);
			}
#endif
			return jit_object_cache{std::make_unique<jit_object_cache::impl>(std::move(*object_file), std::move(cache))};
		}

		const bool removed_raw = fs::remove_file(path);
		const bool removed_compressed = fs::remove_file(path + ".gz");
		if (removed_raw || removed_compressed)
		{
			jit_log.error("ObjectCache: Removed damaged cache entry: %s", path);
		}
	}

	return {};
}

void jit_compiler::set_raw_cache_materialization(bool enabled) noexcept
{
#ifdef __ANDROID__
	if (enabled)
	{
		fs::device_stat stats{};
		const usz budget = fs::statfs(fs::get_cache_dir(), stats) ? stats.avail_free / 4 : 0;
		g_raw_object_cache_budget.store(budget, std::memory_order_relaxed);
		g_materialize_raw_object_cache.store(true, std::memory_order_release);
	}
	else
	{
		g_materialize_raw_object_cache.store(false, std::memory_order_release);
		g_raw_object_cache_budget.store(0, std::memory_order_relaxed);
	}
#else
	static_cast<void>(enabled);
#endif
}

void jit_compiler::update_global_mapping(const std::string& name, u64 addr)
{
	m_engine->updateGlobalMapping(name, addr);
}

void jit_compiler::fin()
{
	m_engine->finalizeObject();
}

bool jit_compiler::try_fin(std::string& error)
{
	return run_recoverable_llvm([&]()
	{
		m_engine->finalizeObject();
	}, error);
}

u64 jit_compiler::get(const std::string& name)
{
	return m_engine->getGlobalValueAddress(name);
}

const char* fallback_cpu_detection()
{
#if defined(ARCH_X64)
	// If we got here we either have a very old and outdated CPU or a new CPU that has not been seen by LLVM yet.
	const std::string brand = utils::get_cpu_brand();
	const auto family = utils::get_cpu_family();
	const auto model = utils::get_cpu_model();

	jit_log.error("CPU wasn't identified by LLVM, brand = %s, family = 0x%x, model = 0x%x", brand, family, model);

	if (brand.starts_with("AMD"))
	{
		switch (family)
		{
		case 0x10:
		case 0x12: // Unimplemented in LLVM
			return "amdfam10";
		case 0x15:
			// Bulldozer class, includes piledriver, excavator, steamroller, etc
			return utils::has_avx2() ? "bdver4" : "bdver1";
		case 0x17:
		case 0x18:
			// No major differences between znver1 and znver2, return the lesser
			return "znver1";
		case 0x19:
			// Models 0-Fh are zen3 as are 20h-60h. The rest we can assume are zen4
			return ((model >= 0x20 && model <= 0x60) || model < 0x10) ? "znver3" : "znver4";
		case 0x1a:
			// Only one generation in family 1a so far, zen5, which we do not support yet.
			// Return zen4 as a workaround until the next LLVM upgrade.
			return "znver4";
		default:
			// Safest guesses
			return utils::has_avx512() ? "znver4" :
			       utils::has_avx2()   ? "znver1" :
			       utils::has_avx()    ? "bdver1" :
			                             "nehalem";
		}
	}
	else if (brand.find("Intel") != std::string::npos)
	{
		if (!utils::has_avx())
		{
			return "nehalem";
		}
		if (!utils::has_avx2())
		{
			return "ivybridge";
		}
		if (!utils::has_avx512())
		{
			return "skylake";
		}
		if (utils::has_avx512_icl())
		{
			return "cannonlake";
		}
		return "icelake-client";
	}
	else if (brand.starts_with("VirtualApple"))
	{
		// No AVX. This will change in MacOS 15+, at which point we may revise this.
		return utils::has_avx() ? "haswell" : "nehalem";
	}

#elif defined(ARCH_ARM64)
#ifdef ANDROID
	static std::string s_result = []() -> std::string
	{
		std::string result = aarch64::get_cpu_name();
		if (result.empty())
		{
			return "cortex-a78";
		}

		std::transform(result.begin(), result.end(), result.begin(), ::tolower);
		return result;
	}();

	return s_result.c_str();
#else
	// TODO: Read the data from /proc/cpuinfo. ARM CPU registers are not accessible from usermode.
	// This will be a pain when supporting snapdragon on windows but we'll cross that bridge when we get there.
	// Require at least armv8-2a. Older chips are going to be useless anyway.
	return "cortex-a78";
#endif
#endif

	// Failed to guess, use generic fallback
	return "generic";
}

#endif // LLVM_AVAILABLE
