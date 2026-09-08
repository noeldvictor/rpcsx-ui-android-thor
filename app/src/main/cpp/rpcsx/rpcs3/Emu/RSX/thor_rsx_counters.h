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
	// Why a render pass ended (2026-09-08). Round M counted 98 real passes a frame
	// for 1,500 draws; on a tiler every end is a GMEM store and the next begin a
	// load. Each site that calls vk::end_renderpass names its reason here.
	inline atomic_t<u32> g_rp_end_switch{0};   // begin_renderpass with a different pass or framebuffer
	inline atomic_t<u32> g_rp_end_barrier{0};  // a pipeline barrier that cannot live inside a pass
	inline atomic_t<u32> g_rp_end_texture{0};  // a texture copy, blit, upload or cache flush
	inline atomic_t<u32> g_rp_end_subpass{0};  // emit_geometry found a subpass mismatch
	inline atomic_t<u32> g_rp_end_query{0};    // occlusion query scope rules
	inline atomic_t<u32> g_rp_end_flush{0};    // flush_command_queue closing the pass
	inline atomic_t<u32> g_rp_end_compute{0};  // a compute dispatch
	inline atomic_t<u32> g_rp_end_label{0};    // a label write with unflushed texture loads
	inline atomic_t<u32> g_rp_end_layout{0};   // vk::change_image_layout while a pass was open

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
		const u32 e_sw = g_rp_end_switch.exchange(0);
		const u32 e_bar = g_rp_end_barrier.exchange(0);
		const u32 e_tex = g_rp_end_texture.exchange(0);
		const u32 e_sub = g_rp_end_subpass.exchange(0);
		const u32 e_q = g_rp_end_query.exchange(0);
		const u32 e_fl = g_rp_end_flush.exchange(0);
		const u32 e_co = g_rp_end_compute.exchange(0);
		const u32 e_lab = g_rp_end_label.exchange(0);
		const u32 e_lay = g_rp_end_layout.exchange(0);

		if (!rp && !sub && !refills && !retries && !draws)
		{
			return;
		}

		fmt::append(out, ", RSX rp=%u sub=%u fifo_refill=%u fifo_retry=%u (stalls=%u locked=%u changed=%u mismatch=%u cpu_wait=%u) draws=%u",
			rp, sub, refills, retries, stalls, locked, changed, mismatch, cpu_waits, draws);
		fmt::append(out, " rp_end(switch/barrier/layout/tex/subpass/query/flush/compute/label)=%u/%u/%u/%u/%u/%u/%u/%u/%u",
			e_sw, e_bar, e_lay, e_tex, e_sub, e_q, e_fl, e_co, e_lab);
	}
} // namespace thor::rsx_counters
