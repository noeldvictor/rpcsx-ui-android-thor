#pragma once

// Per-window RSX counters for the Transformers 30 FPS programme.
//
// WHY. Every lever from here on changes one part of the RSX thread's per-draw
// path, and a frame rate alone cannot say whether the lever engaged. Each
// counter below names the thing a change is meant to move. perf_monitor appends
// them to its Frames line every report, and resets them, so the reader divides
// by the frame count in the same line for a per-frame figure.
//
//   RSX rp=<render passes> sub=<queue submits> fifo_refill=<cache refills>
//       fifo_retry=<tear retries in the Atomic fetch> draws=<draw calls>
//
// COST. One relaxed increment per event. No property: the counters change no
// behaviour.

#include "util/atomic.hpp"
#include "util/types.hpp"
#include "util/StrFmt.h"

#include <string>

namespace thor::rsx_counters
{
	inline atomic_t<u32> g_render_passes{0};
	inline atomic_t<u32> g_submits{0};
	inline atomic_t<u32> g_fifo_refills{0};
	inline atomic_t<u32> g_fifo_retries{0};
	// Retry causes (2026-09-08): the trim fix moved none of the 400 retries per
	// frame, so the spin is not the PUT line. Split by what the loop saw.
	inline atomic_t<u32> g_fifo_stalls{0};          // refills that failed at least once
	inline atomic_t<u32> g_fifo_retry_locked{0};    // reservation word had lock bits set
	inline atomic_t<u32> g_fifo_retry_changed{0};   // reservation timestamp moved during the copy
	inline atomic_t<u32> g_fifo_retry_mismatch{0};  // the two reads of the line differed
	inline atomic_t<u32> g_fifo_cpu_waits{0};       // retries that fell through to cpu_wait
	inline atomic_t<u32> g_draws{0};

	inline void report(std::string& out)
	{
		const u32 rp = g_render_passes.exchange(0);
		const u32 sub = g_submits.exchange(0);
		const u32 refills = g_fifo_refills.exchange(0);
		const u32 retries = g_fifo_retries.exchange(0);
		const u32 stalls = g_fifo_stalls.exchange(0);
		const u32 locked = g_fifo_retry_locked.exchange(0);
		const u32 changed = g_fifo_retry_changed.exchange(0);
		const u32 mismatch = g_fifo_retry_mismatch.exchange(0);
		const u32 cpu_waits = g_fifo_cpu_waits.exchange(0);
		const u32 draws = g_draws.exchange(0);

		if (!rp && !sub && !refills && !retries && !draws)
		{
			return;
		}

		fmt::append(out, ", RSX rp=%u sub=%u fifo_refill=%u fifo_retry=%u (stalls=%u locked=%u changed=%u mismatch=%u cpu_wait=%u) draws=%u",
			rp, sub, refills, retries, stalls, locked, changed, mismatch, cpu_waits, draws);
	}
} // namespace thor::rsx_counters
