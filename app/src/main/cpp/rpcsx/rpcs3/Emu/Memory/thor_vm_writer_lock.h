#pragma once

// Tuning for the spin inside vm::writer_lock's constructor.
//
// WHY THIS SITE. A 25 s simpleperf capture of restored Eternal Sonata gameplay,
// 85,615 samples and 0 lost, puts `vm::writer_lock::writer_lock` at **8.60% of
// all cycles**, second only to `spu_thread::process_mfc_cmd` at 12.69%. Adding
// `vm::passive_lock` and the two `shared_mutex` entries makes VM range locking
// about **12.7% of everything**, and all six SPU threads feed it roughly equally.
//
// It comes from `do_putlluc`. `g_use_rtm` is false on ARM64, so with the upstream
// default `Accurate SPU Reservations: true` every reservation store takes the hard
// path and lands in this constructor.
//
// The loop it controls spins `busy_wait(cycles)` up to `spins` times before its
// first `std::this_thread::yield()`. Six SPU threads doing that against one
// range-lock bitmap is where the 8.60% goes.
//
//   debug.rpcsx.thor.vm_writer_lock_spins  = <n>   spins before yielding
//   debug.rpcsx.thor.vm_writer_lock_cycles = <n>   busy_wait length per spin
//
// Both default to the values that shipped, 100 and 200, so an unset device is
// bit-identical to before this file existed.
//
// ## Read at load, not in the loop
//
// These are namespace-scope `inline const`, initialized during dynamic
// initialization, so reading one is a plain load. They are deliberately NOT
// function-local statics: those carry a guard-variable acquire load and a branch
// on every call. thor_rsx_fifo_park.h records that exact mistake costing about
// +46% of a thread when the guarded paths were all disabled, and this loop is
// hotter than that one.
//
// ## Which direction is worth trying
//
// `sched_yield` is only 0.76% of the whole process in that profile, so yielding
// EARLIER is cheap here. Spinning is not: `rx::busy_wait` on ARM64 issues `YIELD`,
// which docs/arm64/bench-results.md measures at 0.36 ns, the same as a `NOP`, so a
// spinning thread holds its core at full issue rate and burns power for nothing.
// The RSX FIFO pause ladder already failed for exactly that reason. Fewer, shorter
// spins is therefore the direction to measure first.

#include "util/types.hpp"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include <cstdlib>

namespace thor::vm_writer_lock
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

	inline const u32 g_spins = read_u32_property("debug.rpcsx.thor.vm_writer_lock_spins", 100);
	inline const u32 g_cycles = read_u32_property("debug.rpcsx.thor.vm_writer_lock_cycles", 200);

	// Spins before the first yield. 0 yields immediately.
	inline u32 spins() noexcept { return g_spins; }

	// Length of one busy_wait between checks.
	inline u32 cycles() noexcept { return g_cycles; }
} // namespace thor::vm_writer_lock
