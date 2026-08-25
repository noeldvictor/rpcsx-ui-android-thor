#pragma once

// Tuning for the backoff inside vm::range_lock_internal.
//
// WHY THIS SITE. A verified gameplay profile of this device's Transformers
// combat reads `vm::range_lock_internal` at **15.37%** of all cycles, with
// `vm::writer_lock` at 10.69% and `vm::passive_lock` at 3.07`%`: about **29% of
// everything** inside VM range locking. Ghidra reached the same place from the
// other side - `chunk-0x0f3c4` is 96.84% of `CellSpursKernel0` and disassembles
// to a poll-with-backoff on a reservation - so both the guest SPU and the host
// PPU are queued on the same object.
//
//   debug.rpcsx.thor.vm_range_lock_cycles = <n>   busy_wait length per retry
//   debug.rpcsx.thor.vm_range_lock_wfe    = 0|1   park on the bitmap instead
//
// Both default to the shipped behaviour, 200 and off, so an unset device is
// bit-identical to before this file existed.
//
// ## What 200 actually costs here
//
// `rx::busy_wait(n)` is `stop = get_tsc() + n; do pause(); while (get_tsc() <
// stop);` and `get_tsc()` on ARM64 is `mrs cntvct_el0`, which this device clocks
// at **19.2 MHz - 52.08 ns per tick**. So 200 is not 200 cycles, it is
// **10.4 us**, and tools/bench measured the counter read itself at 38.49 ns, so
// one backoff is roughly 270 system-register reads. `pause()` lowers to `YIELD`,
// which docs/arm64/bench-results.md measures at 0.36 ns - the same as a NOP - so
// the core stays at full issue rate for the whole 10.4 us.
//
// ## MEASURED 2026-08-25, AND THIS SITE IS NOT WORTH OPTIMISING FOR SPEED
//
// The sentence that used to end the paragraph above - "that is the frame time
// and the 88 C in one mechanism" - was written before anything measured it, and
// a wait-site census of restored combat says it is WRONG:
//
//   vm_range   2,907 calls/s   30,280 us/s   3.0% of ONE core
//
// Against `coresBusy` 5.36 that is **0.56% of busy CPU**. The whole busy-wait
// inventory across every site is 7.7% of busy CPU, so this emulator is
// COMPUTE-bound rather than wait-bound and no backoff change here can be worth
// more than a fraction of a frame. See the AGENTS.md section of that name.
//
// The lever below is kept because it is cheap and gated off, and because it
// answers a POWER question - a core spinning at full issue rate for 10.4 us
// burns a handheld's battery - but it must NOT be sold as a frame-rate fix.
//
// ## Do NOT re-run "fewer, shorter spins" here
//
// thor_vm_writer_lock.h records that arm at the sibling site, measured
// 2026-08-24 on THIS title in restored 3D combat, and it is a **NULL**:
//
//   controlA  100/200   18.70 fps      spins=8    8/200   18.66 fps
//   controlB  100/200   18.60 fps      cycles=50  100/50  18.77 fps
//                                      both       8/50    18.74 fps
//
// Every arm sits inside the control pair's own 18.60-18.77 spread. The reason is
// that the hold is genuinely long: shortening the backoff does not shorten the
// wait, it only polls it more often. `vm_range_lock_cycles` exists here to make
// the same statement measurable at THIS site rather than assumed from that one,
// and the expectation is that it is null too.
//
// ## Which direction is actually worth trying
//
// Not "spin less". **Spin differently.** AArch64 can park a core on a cacheline:
// `ldaxr` arms the exclusive monitor, `wfe` sleeps until another core writes the
// line or the event stream fires. `rx::spin_on_cacheline_once` already
// implements it and this path never used it. Against a 10.4 us hot poll that
// should be strictly better on wake latency - a writer releasing at t+1us wakes
// us at t+1us instead of t+10.4us - and it stops burning a core at full issue
// rate while waiting, which is the heat complaint.
//
// ## Why this is a THRESHOLD and not a boolean
//
// Parking on the FIRST retry would be a regression, and SPUThread.cpp already
// knows why. Its GETLLAR path parks on the same kind of cacheline and records
// the cost in the comment above the call:
//
//     // waiter eats the full ~95us
//     if (getllar_spin_count >= 8)
//         __arm64_monitor_wait<check_wait_t>(...);
//
// When nothing writes the watched line, the wake falls back to the ARM event
// stream, and on this device that period is about **95 us** - nine times the
// 10.4 us spin it would replace. So the guest side spins through the early
// iterations to keep that penalty off short waits and parks only once a wait is
// already long enough for 95 us not to matter. This site takes the same shape
// rather than rediscovering it: the property IS the number of spins before the
// first park.
//
//   0 (default)  never park, shipped behaviour, bit-identical to before
//   8            the threshold the GETLLAR path settled on
//
// FEAT_WFxT - `WFET`, a WFE with an architectural timeout - would remove the
// event-stream risk entirely, and tools/bench/thor_idle_primitives.c reports it
// **absent** on this chip. So the event stream is the only backstop available.

#include "util/types.hpp"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include <cstdlib>

namespace thor::vm_range_lock
{
	inline u32 read_u32_property(const char* name, u32 fallback) noexcept
	{
#if defined(__ANDROID__)
		char value[PROP_VALUE_MAX]{};

		if (__system_property_get(name, value) <= 0)
		{
			return fallback;
		}

		char* end = nullptr;
		const unsigned long parsed = std::strtoul(value, &end, 10);

		// A malformed value keeps the SHIPPED default. Do not guess, and do not
		// silently pick an extreme either: a typo must not look like a measured
		// choice.
		if (end == value || (end && *end) || parsed > 100000ul)
		{
			return fallback;
		}

		return static_cast<u32>(parsed);
#else
		static_cast<void>(name);
		return fallback;
#endif
	}

	// Namespace-scope `inline const`, initialized during dynamic initialization,
	// so reading one is a plain load. Deliberately NOT function-local statics:
	// those carry a guard-variable acquire load and a branch on every call, and
	// thor_rsx_fifo_park.h records that mistake costing about +46% of a thread.
	// This loop is hotter than that one.
	inline const u32 g_cycles = read_u32_property("debug.rpcsx.thor.vm_range_lock_cycles", 200);
	inline const u32 g_wfe_after = read_u32_property("debug.rpcsx.thor.vm_range_lock_wfe", 0);

	// Length of one busy_wait between checks.
	inline u32 cycles() noexcept { return g_cycles; }

	// Spins to take before the first LDAXR/WFE park. 0 disables parking entirely.
	inline u32 wfe_after() noexcept { return g_wfe_after; }
} // namespace thor::vm_range_lock
