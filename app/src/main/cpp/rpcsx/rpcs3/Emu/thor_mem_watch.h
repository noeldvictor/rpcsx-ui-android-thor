#pragma once

// MEMORY WATCH (2026-09-08): who writes one guest word.
//
// WHY. The Transformers render thread spends its frame in a loop at
// 0x00fdcb88 that reads a word (0x01f94998 in the restored combat save),
// adds a size and sleeps 30 us until the sum drops under a limit: a
// ring-space wait in the GCMX segment hand-off. No PPU code in the GCMX library
// stores through that array, so the word is advanced by an SPU DMA or by an
// RSX label or report. Which one decides whether the render thread waits for
// the SPUs or for the RSX thread, and round O showed the RSX thread's time is
// not the frame's binding stage.
//
// Each hook logs the first 24 hits per source and then every 256th, with the
// value the word holds after the write. The perf monitor prints the word each
// tick.
//
//   debug.rpcsx.thor.mem_watch_ea = 0x01f94998

#include "util/types.hpp"
#include "util/atomic.hpp"
#include "util/logs.hpp"
#include "Emu/Memory/vm.h"

#include <cstdlib>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

LOG_CHANNEL(thor_memwatch_log, "MEMWATCH");

namespace thor::mem_watch
{
	inline u32 ea()
	{
		static const u32 s_ea = []() -> u32
		{
#ifdef __ANDROID__
			char value[PROP_VALUE_MAX]{};

			if (__system_property_get("debug.rpcsx.thor.mem_watch_ea", value) > 0 && value[0])
			{
				const unsigned long parsed = std::strtoul(value, nullptr, 16);

				if (parsed && parsed < 0x1'0000'0000ull)
				{
					thor_memwatch_log.error("Thor MEMWATCH: armed on 0x%08x", static_cast<u32>(parsed));
					return static_cast<u32>(parsed);
				}
			}
#endif
			return 0;
		}();

		return s_ea;
	}

	inline bool armed()
	{
		return ea() != 0;
	}

	inline u32 read_word()
	{
		const u32 addr = ea();
		return (addr && vm::check_addr(addr, 0, 4)) ? +vm::_ref<be_t<u32>>(addr) : 0;
	}

	// A write of [addr, addr + size) by `who`. Logs when it covers the watched word.
	inline void on_range(const char* who, u32 addr, u32 size, u32 thread_index = 0, u32 pc = 0)
	{
		const u32 watch = ea();

		if (!watch || addr > watch || watch >= addr + size)
		{
			return;
		}

		static atomic_t<u32> s_hits{0};
		const u32 n = ++s_hits;

		if (n <= 24 || (n & 255) == 0)
		{
			thor_memwatch_log.error("Thor MEMWATCH: %s [0x%08x+0x%x] covers 0x%08x, word now 0x%08x (thread %u pc 0x%x hit %u)",
				who, addr, size, watch, read_word(), thread_index, pc, n);
		}
	}

	// A 4-byte write of `value` to `addr` by `who`.
	inline void on_word(const char* who, u32 addr, u32 value)
	{
		const u32 watch = ea();

		if (!watch || addr != watch)
		{
			return;
		}

		static atomic_t<u32> s_hits{0};
		const u32 n = ++s_hits;

		if (n <= 24 || (n & 255) == 0)
		{
			thor_memwatch_log.error("Thor MEMWATCH: %s writes 0x%08x = 0x%08x (hit %u)", who, addr, value, n);
		}
	}
} // namespace thor::mem_watch
