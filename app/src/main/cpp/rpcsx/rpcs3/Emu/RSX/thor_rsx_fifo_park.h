#pragma once

// Park the RSX when its command ring stays empty, instead of spinning on it.
//
// Folklore's title screen has two steady states, measured on device 2026-08-18:
//
//   light    1823-1890 process ticks / 60 s, 7200 frames, rsx::thread 256
//   starved  6876 process ticks / 60 s, 6000 frames, rsx::thread 5985
//
// The starved state costs 3.7x the CPU and renders FEWER frames. A 24,208-sample
// profile of it puts 89.13% of all cycles on rsx::thread, and every one of the
// 1,295 sched_yield samples lands on that single thread. It is the FIFO_EMPTY
// branch spinning while the guest fails to feed the ring.
//
// ## Why this is the third attempt
//
// Two earlier forms failed, and both are recorded in CLAUDE.md:
//
//   rsx_fifo_park=1        eight rx::pause() then rx::wait_for_event(). Costs +10%
//                          of this thread in the light state, because a FIFO that
//                          is rarely empty still pays the wake latency. One arm
//                          under load returned 2700 frames against 4800.
//   rsx_fifo_park_after=N  yield below N consecutive empty polls, wait_for_event
//                          above it. One arm starved WITH the park engaged and
//                          still burned 86% of a core.
//
// That last number is the reason for this file. A thread that reaches
// wait_for_event() and sleeps cannot spend 86% of a core. rx/asm.hpp measures an
// armed WFE parking 72,024 ns on an IDLE device; nothing measured it on a loaded
// one, and the arm above says the idle figure does not carry over.
//
// So this form does not use WFE. It sleeps for a bounded time, which is a wait
// this project can verify actually sleeps.
//
//   debug.rpcsx.thor.rsx_fifo_park_after = <polls>  consecutive empty polls first
//   debug.rpcsx.thor.rsx_fifo_park_us    = <us>     how long one park sleeps
//
// Both default to 0, which keeps std::this_thread::yield() and changes nothing.
//
// ## The counters exist because three instruments before them could not be read
//
// g_parks counts the sleeps and g_idle_polls counts every empty poll, so
// "the park ran and slept" can be told from "the park never ran". The SPU
// self-loop park shipped with counters no code read, and a null result could not
// be told from no reach. perf_monitor prints these on its own periodic line.

#include <cstdlib>

#include "util/atomic.hpp"
#include "util/types.hpp"

#if defined(ANDROID)
#include <sys/system_properties.h>
#endif

namespace thor::rsx_fifo
{
	// Written by the RSX thread only, read by perf_monitor.
	inline atomic_t<u64> g_idle_polls{0};
	inline atomic_t<u64> g_parks{0};
	inline atomic_t<u64> g_park_us_total{0};

	inline u32 read_u32_property(const char* name) noexcept
	{
#if defined(ANDROID)
		char value[PROP_VALUE_MAX]{};

		if (__system_property_get(name, value) <= 0)
		{
			return 0;
		}

		const unsigned long parsed = std::strtoul(value, nullptr, 10);

		return parsed > 0xffffffffUL ? 0xffffffffU : static_cast<u32>(parsed);
#else
		static_cast<void>(name);
		return 0;
#endif
	}

	// Read ONCE at load, into namespace-scope inline variables.
	//
	// These were function-local `static const` and that cost measurable time. A
	// function-local static carries a guard-variable acquire load and a branch on
	// EVERY call, and all three are called on every poll of an empty FIFO, which is
	// one of the hottest loops in the emulator. Folklore's light state went from
	// 1823-1890 process ticks per 60 s to 2662-2750 - about +46% - with all three
	// properties unset and every code path they guard disabled.
	//
	// CLAUDE.md already records this exact trap for get_thor_pause_mode, where a
	// runtime property put a guarded static in the SPU reservation spin. A namespace
	// scope inline variable is initialized during dynamic initialization instead, so
	// reading it is a plain load.
	inline const u32 g_park_after = read_u32_property("debug.rpcsx.thor.rsx_fifo_park_after");
	inline const u32 g_park_us = read_u32_property("debug.rpcsx.thor.rsx_fifo_park_us");
	inline const u32 g_pause_ladder = read_u32_property("debug.rpcsx.thor.rsx_fifo_pause_ladder");

	// Consecutive empty polls before the RSX sleeps. 0 keeps the yield.
	inline u32 park_after() noexcept { return g_park_after; }

	// How long one park sleeps, in microseconds. 0 keeps the yield.
	inline u32 park_us() noexcept { return g_park_us; }

	// Pauses burned between two sched_yield calls on an empty ring. 0 keeps the
	// current behaviour, which is one yield per poll.
	//
	// This is the measurement that produced it. A build-matched, 33,850-sample
	// profile of the starved state, 0 lost:
	//
	//   64.84%  [kernel.kallsyms] one address
	//    8.64%  [kernel.kallsyms]
	//    5.24%  sched_yield
	//    3.89%  [kernel.kallsyms]
	//    1.93%  rsx::thread::run_FIFO()
	//
	// The RSX thread's OWN code is 1.93%. Everything above it is the kernel
	// servicing sched_yield, which this loop calls once per poll on an empty ring.
	// That is syscall overhead, not work, and it is why the starved state costs
	// 3.7x the CPU of the light one while rendering FEWER frames.
	//
	// A yield is not needed for progress here: this device has 8 cores and the
	// emulator runs far fewer busy threads than that. The ladder keeps one yield
	// per N polls so a loaded machine can still preempt, and spends the rest in
	// userspace where a poll costs no syscall.
	inline u32 pause_ladder() noexcept { return g_pause_ladder; }

	inline bool enabled() noexcept
	{
		return park_after() != 0 && park_us() != 0;
	}
}
