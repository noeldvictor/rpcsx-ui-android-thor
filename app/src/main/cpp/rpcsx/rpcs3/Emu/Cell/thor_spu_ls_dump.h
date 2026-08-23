#pragma once

// Write the local store of one SPU thread to a file, one time.
//
// ## Why this exists
//
// A guest that halts its own SPU stops at `0xffdead00`, and the access
// violation handler prints the SPU program counter. A program counter does not
// name the assertion that failed. To name it you must read the guest code at
// that address, and the emulator never writes that code anywhere.
//
// Transformers halts in `CellSpursKernel0`, and Folklore stalls at SPU
// `pc=0x12b0` in a thread of the same name. Both load Sony's SPURS kernel from
// `libsre`, so ONE image explains both.
//
// The image is the same on every boot. So you can build the map from program
// counter to halt instruction IN ADVANCE, from a boot that does not fail. That
// matters here: the halt is rarer than 1 in 37 controlled boots, so waiting for
// it to happen with a debugger attached is not a plan.
//
// ## How to use it
//
//   adb shell setprop debug.rpcsx.thor.spu_ls_dump CellSpursKernel0
//   # boot the title, wait for it to render, then:
//   adb exec-out run-as net.rpcsx.easy cat \
//       /data/data/net.rpcsx.easy/cache/spu_ls_CellSpursKernel0.bin > ls.bin
//
// The value is a SUBSTRING of the SPU thread name. An empty value is off, which
// is the default, so this costs nothing unless you ask for it.
//
// Then disassemble `ls.bin` as SPU code at load address 0 and record every
// `HGT`, `HLGT` and `HEQ` with its condition. `Emu/Cell/SPUDisAsm.cpp` in this
// tree is a working SPU disassembler, and the `thor-ghidra-static-lane` skill
// carries the Ghidra route.
//
// ## Where it runs, and why that is safe
//
// It runs from `perf_monitor`, on that thread's own timer, NOT on any SPU path.
// The SPU hot path pays nothing at all: `process_mfc_cmd` is 12.69% of gameplay
// cycles in this fork's own profile, and this project has already shipped one
// correctness fix that cost half the frame rate by adding work to a hot loop.
//
// The read is not synchronised with the running SPU thread, so a DATA area of
// the image can tear. That is acceptable and it is the point: the CODE of a
// loaded SPU program does not change after the guest copies it in, and the code
// is what a halt map needs. Do not use this dump to reason about SPU data.

#include "Emu/Cell/SPUThread.h"
#include "Emu/IdManager.h"
#include "util/File.h"
#include "util/logs.hpp"
#include "util/types.hpp"

#include <atomic>
#include <cctype>
#include <cstdlib>
#include <string>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace thor
{
	// Keep a file name safe. A guest thread name is guest data and can hold
	// anything, including a path separator.
	inline std::string spu_ls_dump_sanitize(const std::string& name)
	{
		std::string out;
		out.reserve(name.size());

		for (const char c : name)
		{
			out += (std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-') ? c : '_';
		}

		return out.empty() ? std::string("spu") : out;
	}

	// Call from a monitor thread. It does nothing unless the property is set,
	// and it writes at most one file for each emulator run.
	inline void spu_ls_dump_tick()
	{
		static std::atomic<bool> s_done{false};

		if (s_done.load(std::memory_order_relaxed))
		{
			return;
		}

		std::string want;

#ifdef ANDROID
		char value[PROP_VALUE_MAX]{};

		if (__system_property_get("debug.rpcsx.thor.spu_ls_dump", value) > 0)
		{
			want = value;
		}
#endif

		if (want.empty())
		{
			if (const char* env = std::getenv("RPCSX_THOR_SPU_LS_DUMP"))
			{
				want = env;
			}
		}

		if (want.empty())
		{
			return;
		}

		idm::select<named_thread<spu_thread>>([&](u32, named_thread<spu_thread>& spu)
			{
				if (s_done.load(std::memory_order_relaxed))
				{
					return;
				}

				const auto tname = spu.spu_tname.load();

				if (!tname || tname->find(want) == std::string::npos)
				{
					return;
				}

				const std::string path = fs::get_cache_dir() + "spu_ls_" + spu_ls_dump_sanitize(*tname) + ".bin";

				fs::file out(path, fs::rewrite);

				if (!out)
				{
					// Report it once. A dump that silently writes nothing reads
					// exactly like a thread that never matched, and this repo has
					// been fooled by that shape more than once.
					s_done.store(true, std::memory_order_relaxed);
					spu_log.error("Thor SPU LS dump: cannot write '%s'", path);
					return;
				}

				out.write(spu._ptr<u8>(0), static_cast<usz>(SPU_LS_SIZE));
				out.close();

				s_done.store(true, std::memory_order_relaxed);

				spu_log.warning("Thor SPU LS dump: wrote '%s' (%u bytes) thread='%s' pc=0x%05x. "
								"Disassemble as SPU code at load address 0.",
					path, static_cast<u32>(SPU_LS_SIZE), *tname, spu.pc);
			});
	}
} // namespace thor
