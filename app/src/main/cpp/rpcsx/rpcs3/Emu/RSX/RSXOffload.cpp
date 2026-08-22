#include "stdafx.h"

#include "Emu/Memory/vm.h"
#include "Common/BufferUtils.h"
#include "Core/RSXReservationLock.hpp"
#include "Host/MM.h"
#include "RSXOffload.h"
#include "RSXThread.h"

#include "util/lockless.h"

#include <thread>
#include "rx/asm.hpp"

namespace rsx
{
#ifdef __ANDROID__
	extern std::function<bool(u32 addr, bool is_writing)> g_access_violation_handler;

	// The ART signal chain cannot host the full RSX texture-cache path. A protected
	// guest range can fault inside memcpy(), enter VKGSRender::on_access_violation(),
	// and fault a second time while the kernel still blocks SIGSEGV. The second fault
	// kills the process, and it kills it silently: a guard page is not emulator
	// memory, so ART's FaultManager takes the signal and Android records only
	// "SIGNALED status=11".
	//
	// Resolve the protected pages from normal thread context first. The mirror in
	// Host/MM.cpp answers the common case without a call, so this costs one atomic
	// load for each page when nothing is protected.
	//
	// Ported from sashkinbro/EmuCoreC e67d18b7, 77c30684 and 77dc85d0.
	static atomic_t<u64> g_preflight_handler_calls = 0;

	static bool prepare_guest_access(u32 address, u32 length, bool is_writing)
	{
		if (!address || !length || !g_access_violation_handler)
		{
			return false;
		}

		const u32 last = rx::add_saturate<u32>(address, length - 1);
		const u8 required_permission = is_writing ? vm::page_writable : vm::page_readable;

		// Leave at once when there is nothing to find.
		//
		// The walk below runs one 4 KiB page at a time over the WHOLE range, and each
		// step costs a vm::check_addr and an atomic load. A texture upload hands this
		// function a whole surface: 2560x720 is 1,800 steps, on the RSX thread, for
		// every upload. The comment above used to say "one atomic load for each page",
		// which undercounted it by half and priced it as if the ranges were small.
		//
		// A per-region test answers "can this range hold a protected page" 256 times
		// more cheaply than the walk answers it: one counter for a 16 KiB DMA, eight
		// for a 7 MiB surface. A global "is anything protected" flag would not work,
		// because the texture cache keeps pages protected through most of gameplay.
		//
		// When the answer is no, this is the behaviour from before 21493f1e1. When it
		// is yes, the exact per-page walk below still runs.
		// Reach, reported. This tree has shipped several levers whose cost or benefit
		// was argued and never counted, and this walk is one of them. The counters say
		// how often the fast path fires and how many pages the slow path really walks,
		// so the next person does not have to infer it.
		//
		// rsx_log.error, because rsx_log.always does not reach logcat on this device.
		{
			static atomic_t<u64> s_fast = 0, s_slow = 0, s_pages = 0, s_reported = 0;

			const bool fast = !mm_range_has_protection(address, length) &&
				vm::check_addr(address, required_permission, length);

			(fast ? s_fast : s_slow)++;
			if (!fast)
			{
				s_pages += (last / 4096) - (address / 4096) + 1;
			}

			const u64 total = s_fast + s_slow;
			if ((total % 100000) == 0 && s_reported.exchange(total) != total)
			{
				rsx_log.error("guest page preflight: fast=%llu slow=%llu pages_walked=%llu handler_calls=%llu",
					+s_fast, +s_slow, +s_pages, +g_preflight_handler_calls);
			}

			if (fast)
			{
				return false;
			}
		}

		u32 current = address;
		bool handled = false;

		for (;;)
		{
			if (!vm::check_addr(current, required_permission) || !mm_is_accessible(current, is_writing))
			{
				// Count these. The handler invalidates the texture cache, so it is orders of
				// magnitude dearer than the probe, and the page count alone cannot say whether
				// the cost is the walk or the handler.
				g_preflight_handler_calls++;
				handled |= g_access_violation_handler(current, is_writing);
			}

			if (current / 4096 == last / 4096)
			{
				break;
			}

			current = (current & ~4095u) + 4096u;
		}

		return handled;
	}

	bool prepare_guest_read(u32 address, u32 length)
	{
		return prepare_guest_access(address, length, false);
	}

	bool prepare_guest_write(u32 address, u32 length)
	{
		return prepare_guest_access(address, length, true);
	}
#endif

	struct dma_manager::offload_thread
	{
		lf_queue<transport_packet> m_work_queue;
		atomic_t<u64> m_enqueued_count = 0;
		atomic_t<u64> m_processed_count = 0;
		transport_packet* m_current_job = nullptr;

		thread_base* current_thread_ = nullptr;

		void operator()()
		{
			if (!g_cfg.video.multithreaded_rsx)
			{
				// Abort if disabled
				return;
			}

			current_thread_ = thread_ctrl::get_current();
			ensure(current_thread_);

			if (g_cfg.core.thread_scheduler != thread_scheduler_mode::os)
			{
				thread_ctrl::set_thread_affinity_mask(thread_ctrl::get_affinity_mask(thread_class::rsx));
			}

			while (thread_ctrl::state() != thread_state::aborting)
			{
				for (auto&& job : m_work_queue.pop_all())
				{
					m_current_job = &job;

					switch (job.type)
					{
					case raw_copy:
					{
						const u32 vm_addr = vm::try_get_addr(job.src).first;
#ifdef __ANDROID__
						prepare_guest_read(vm_addr, job.length);
#endif
						rsx::reservation_lock<true, 1> rsx_lock(vm_addr, job.length, g_cfg.video.strict_rendering_mode && vm_addr);
						std::memcpy(job.dst, job.src, job.length);
						break;
					}
					case vector_copy:
					{
						std::memcpy(job.dst, job.opt_storage.data(), job.length);
						break;
					}
					case index_emulate:
					{
						write_index_array_for_non_indexed_non_native_primitive_to_buffer(static_cast<char*>(job.dst), static_cast<rsx::primitive_type>(job.aux_param0), job.length);
						break;
					}
					case callback:
					{
						rsx::get_current_renderer()->renderctl(job.aux_param0, job.src);
						break;
					}
					default: fmt::throw_exception("Unreachable");
					}

					m_processed_count.release(m_processed_count + 1);
				}

				m_current_job = nullptr;

				if (m_enqueued_count.load() == m_processed_count.load())
				{
					m_processed_count.notify_all();
					std::this_thread::yield();
				}
			}

			m_processed_count = -1;
			m_processed_count.notify_all();
		}

		static constexpr auto thread_name = "RSX Offloader"sv;
	};

	// initialization
	void dma_manager::init()
	{
		m_thread = std::make_shared<named_thread<offload_thread>>();
	}

	// General transport
	void dma_manager::copy(void* dst, std::vector<u8>& src, u32 length) const
	{
		if (length <= max_immediate_transfer_size || !g_cfg.video.multithreaded_rsx)
		{
			std::memcpy(dst, src.data(), length);
		}
		else
		{
			m_thread->m_enqueued_count++;
			m_thread->m_work_queue.push(dst, src, length);
		}
	}

	void dma_manager::copy(void* dst, void* src, u32 length) const
	{
		if (length <= max_immediate_transfer_size || !g_cfg.video.multithreaded_rsx)
		{
			const u32 vm_addr = vm::try_get_addr(src).first;
#ifdef __ANDROID__
			prepare_guest_read(vm_addr, length);
#endif
			rsx::reservation_lock<true, 1> rsx_lock(vm_addr, length, g_cfg.video.strict_rendering_mode && vm_addr);
			std::memcpy(dst, src, length);
		}
		else
		{
			m_thread->m_enqueued_count++;
			m_thread->m_work_queue.push(dst, src, length);
		}
	}

	// Vertex utilities
	void dma_manager::emulate_as_indexed(void* dst, rsx::primitive_type primitive, u32 count)
	{
		if (!g_cfg.video.multithreaded_rsx)
		{
			write_index_array_for_non_indexed_non_native_primitive_to_buffer(
				static_cast<char*>(dst), primitive, count);
		}
		else
		{
			m_thread->m_enqueued_count++;
			m_thread->m_work_queue.push(dst, primitive, count);
		}
	}

	// Backend callback
	void dma_manager::backend_ctrl(u32 request_code, void* args)
	{
		ensure(g_cfg.video.multithreaded_rsx);

		m_thread->m_enqueued_count++;
		m_thread->m_work_queue.push(request_code, args);
	}

	// Synchronization
	bool dma_manager::is_current_thread() const
	{
		if (auto cpu = thread_ctrl::get_current())
		{
			return m_thread->current_thread_ == cpu;
		}

		return false;
	}

	bool dma_manager::sync() const
	{
		auto& _thr = *m_thread;

		if (_thr.m_enqueued_count.load() <= _thr.m_processed_count.load()) [[likely]]
		{
			// Nothing to do
			return true;
		}

		if (auto rsxthr = get_current_renderer(); rsxthr->is_current_thread())
		{
			if (m_mem_fault_flag)
			{
				// Abort if offloader is in recovery mode
				return false;
			}

			while (_thr.m_enqueued_count.load() > _thr.m_processed_count.load())
			{
				rsxthr->on_semaphore_acquire_wait();
				rx::pause();
			}
		}
		else
		{
			while (_thr.m_enqueued_count.load() > _thr.m_processed_count.load())
				rx::pause();
		}

		return true;
	}

	void dma_manager::join()
	{
		sync();
		*m_thread = thread_state::aborting;
	}

	void dma_manager::set_mem_fault_flag()
	{
		ensure(is_current_thread()); // "Access denied"
		m_mem_fault_flag.release(true);
	}

	void dma_manager::clear_mem_fault_flag()
	{
		ensure(is_current_thread()); // "Access denied"
		m_mem_fault_flag.release(false);
	}

	// Fault recovery
	utils::address_range dma_manager::get_fault_range(bool writing) const
	{
		const auto m_current_job = ensure(m_thread->m_current_job);

		void* address = nullptr;
		u32 range = m_current_job->length;

		switch (m_current_job->type)
		{
		case raw_copy:
			address = (writing) ? m_current_job->dst : m_current_job->src;
			break;
		case vector_copy:
			ensure(writing);
			address = m_current_job->dst;
			break;
		case index_emulate:
			ensure(writing);
			address = m_current_job->dst;
			range = get_index_count(static_cast<rsx::primitive_type>(m_current_job->aux_param0), m_current_job->length);
			break;
		default:
			fmt::throw_exception("Unreachable");
		}

		return utils::address_range::start_length(vm::get_addr(address), range);
	}
} // namespace rsx
