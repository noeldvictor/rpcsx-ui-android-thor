#include "stdafx.h"
#include "MM.h"
#include <Emu/RSX/Common/simple_array.hpp>
#include <Emu/RSX/RSXOffload.h>

#include <Emu/Memory/vm.h>
#include <Emu/IdManager.h>
#include <Emu/system_config.h>
#include <util/address_range.h>
#include <util/mutex.h>

#ifdef __ANDROID__
#include <array>
#include <atomic>
#include <algorithm>
#endif

namespace rsx
{
	rsx::simple_array<MM_block> g_deferred_mprotect_queue;
	shared_mutex g_mprotect_queue_lock;

#ifdef __ANDROID__
	// RSX protections are independent of the vm::page_* flags, so vm::check_addr
	// cannot answer "will this read fault?". Keep a compact mirror of what RSX
	// protected. One byte for each 4 KiB guest page covers the whole 32-bit guest
	// address space in 1 MiB.
	//
	// The mirror exists so that Android code can ask the question cheaply. A miss
	// in one direction is safe: a page that the mirror calls accessible, but which
	// is really protected, only returns the old behaviour, which is a fault. A page
	// that the mirror calls protected, but which is really open, only costs one
	// extra call to the violation handler.
	//
	// utils::protection::rw is 0, so the zero-initialised mirror starts as "open",
	// which is correct for memory that RSX never touched.
	static constexpr usz s_guest_page_count = 0x1'0000'0000ull / 4096;
	std::array<std::atomic<u8>, s_guest_page_count> g_guest_page_protection{};

	// How many protected pages each 1 MiB region holds.
	//
	// The mirror above answers "is THIS page protected", for one page. The callers
	// that matter ask about a whole range, and they walked it one 4 KiB page at a
	// time: a 2560x720 surface is 1,800 steps of a vm::check_addr plus an atomic
	// load, on the RSX thread, for one upload. The SPU MFC put path asks for every
	// DMA, and process_mfc_cmd is 20% of gameplay.
	//
	// A single global "is anything protected" flag does NOT help. The texture cache
	// protects pages as a matter of course, so that flag is set for most of
	// gameplay and every walk would still run in full.
	//
	// So count per region instead. A region is 1 MiB, which is 256 pages, so a
	// range test reads 256 times fewer counters than the walk reads pages: one
	// counter for a 16 KiB DMA, eight for a 7 MiB surface. A zero region cannot
	// hold a protected page, so the walk can skip it, and a non-zero region falls
	// back to the exact per-page walk. The test is conservative in the safe
	// direction: it never claims a protected page is open.
	static constexpr u32 s_region_shift = 20; // 1 MiB
	static constexpr usz s_region_count = 0x1'0000'0000ull >> s_region_shift;
	static std::array<std::atomic<u32>, s_region_count> g_protected_region_pages{};

	static void mm_track_protection(u64 start, u64 length, utils::protection prot)
	{
		if (!length)
		{
			return;
		}

		const u64 guest_base = reinterpret_cast<u64>(vm::base(0));
		if (start < guest_base || start >= guest_base + 0x1'0000'0000ull)
		{
			return;
		}

		const u64 first = (start - guest_base) / 4096;
		const u64 end = std::min<u64>(start - guest_base + length, 0x1'0000'0000ull);
		const u64 last = (end - 1) / 4096;
		const u8 value = static_cast<u8>(prot);

		const bool now_protected = value != static_cast<u8>(utils::protection::rw);

		for (u64 page = first; page <= last; page++)
		{
			const u8 previous = g_guest_page_protection[page].exchange(value, std::memory_order_acq_rel);
			const bool was_protected = previous != static_cast<u8>(utils::protection::rw);

			if (was_protected != now_protected)
			{
				// This path runs when a protection changes, which is rare. The read
				// path runs for each texture upload and each SPU DMA, which is not.
				auto& region = g_protected_region_pages[(page * 4096) >> s_region_shift];

				if (now_protected)
				{
					region.fetch_add(1, std::memory_order_release);
				}
				else
				{
					region.fetch_sub(1, std::memory_order_release);
				}
			}
		}
	}

	bool mm_range_has_protection(u32 vm_address, u32 length)
	{
		if (!length)
		{
			return false;
		}

		const u64 last = std::min<u64>(u64{vm_address} + length - 1, 0xFFFF'FFFFull);

		for (u64 region = vm_address >> s_region_shift; region <= (last >> s_region_shift); region++)
		{
			if (g_protected_region_pages[region].load(std::memory_order_acquire) != 0)
			{
				return true;
			}
		}

		return false;
	}

	bool mm_is_accessible(u32 vm_address, bool is_writing)
	{
		const auto prot = static_cast<utils::protection>(
			g_guest_page_protection[vm_address / 4096].load(std::memory_order_acquire));
		return is_writing ? prot == utils::protection::rw : prot != utils::protection::no;
	}
#else
	static void mm_track_protection(u64, u64, utils::protection)
	{
	}

	bool mm_is_accessible(u32, bool)
	{
		return true;
	}

	bool mm_range_has_protection(u32, u32)
	{
		return false;
	}
#endif

	void mm_flush_mprotect_queue_internal()
	{
		for (const auto& block : g_deferred_mprotect_queue)
		{
			utils::memory_protect(reinterpret_cast<void*>(block.start), block.length, block.prot);
			mm_track_protection(block.start, block.length, block.prot);
		}

		g_deferred_mprotect_queue.clear();
	}

	void mm_defer_mprotect_internal(u64 start, u64 length, utils::protection prot)
	{
		// We could stack and merge requests here, but that is more trouble than it is truly worth.
		// A fresh call to memory_protect only takes a few nanoseconds of setup overhead, it is not worth the risk of hanging because of conflicts.
		g_deferred_mprotect_queue.push_back({start, length, prot});
	}

	void mm_protect(void* ptr, u64 length, utils::protection prot)
	{
		if (g_cfg.video.disable_async_host_memory_manager)
		{
			utils::memory_protect(ptr, length, prot);
			mm_track_protection(reinterpret_cast<u64>(ptr), length, prot);
			return;
		}

		// Naive merge. Eventually it makes more sense to do conflict resolution, but it's not as important.
		const auto start = reinterpret_cast<u64>(ptr);
		const auto end = start + length;

		std::lock_guard lock(g_mprotect_queue_lock);

		if (prot == utils::protection::rw || prot == utils::protection::wx)
		{
			// Basically an unlock op. Flush if any overlap is detected
			for (const auto& block : g_deferred_mprotect_queue)
			{
				if (block.overlaps(start, end))
				{
					mm_flush_mprotect_queue_internal();
					break;
				}
			}

			utils::memory_protect(ptr, length, prot);
			mm_track_protection(start, length, prot);
			return;
		}

		// No, Ro, etc.
		mm_defer_mprotect_internal(start, length, prot);
		// Show the scheduled restrictive protection at once. A preflight which sees
		// it sends the page through the normal violation handler, and that handler
		// flushes the queue before anything reads the memory.
		mm_track_protection(start, length, prot);
	}

	void mm_protect_immediate(void* ptr, u64 length, utils::protection prot)
	{
#ifdef __ANDROID__
		const auto start = reinterpret_cast<u64>(ptr);
		const auto end = start + length;

		std::lock_guard lock(g_mprotect_queue_lock);

		for (const auto& block : g_deferred_mprotect_queue)
		{
			if (block.overlaps(start, end))
			{
				mm_flush_mprotect_queue_internal();
				break;
			}
		}

		utils::memory_protect(ptr, length, prot);
		mm_track_protection(start, length, prot);
#else
		utils::memory_protect(ptr, length, prot);
#endif
	}

	void mm_flush()
	{
		std::lock_guard lock(g_mprotect_queue_lock);
		mm_flush_mprotect_queue_internal();
	}

	void mm_flush(u32 vm_address)
	{
		std::lock_guard lock(g_mprotect_queue_lock);
		if (g_deferred_mprotect_queue.empty())
		{
			return;
		}

		const auto addr = reinterpret_cast<u64>(vm::base(vm_address));
		for (const auto& block : g_deferred_mprotect_queue)
		{
			if (block.overlaps(addr))
			{
				mm_flush_mprotect_queue_internal();
				return;
			}
		}
	}

	void mm_flush_lazy()
	{
		if (!g_cfg.video.multithreaded_rsx)
		{
			mm_flush();
			return;
		}

		std::lock_guard lock(g_mprotect_queue_lock);
		if (g_deferred_mprotect_queue.empty())
		{
			return;
		}

		auto& rsxdma = g_fxo->get<rsx::dma_manager>();
		rsxdma.backend_ctrl(mm_backend_ctrl::cmd_mm_flush, nullptr);
	}
} // namespace rsx
