#pragma once

// Stop the emulator when the guest halts its own SPU.
//
// ## The defect this fixes
//
// An SPU fault at `0xffdeadXX` is an emulator trap. `make_halt()` emits it when
// the guest runs `HGT`, `HLGT` or `HEQ`, so the guest checked an invariant,
// did not like the answer, and stopped itself. There is no recovery: the guest
// asked to stop.
//
// The handler in `util/Thread.cpp` pauses ONLY the faulting thread:
//
//     cpu->state += cpu_flag::dbg_pause;
//
// Everything else keeps running. Measured on Transformers, that is not a quiet
// failure. The RSX starves 1.3 s later and reports a dead FIFO queue, and the
// remaining SPU threads then spin at about 90% of the whole process, at 0.00
// FPS, at 87 to 94 C, until somebody notices.
//
// One run stayed in that state for FOUR MINUTES. The picture is frozen, so a
// user sees a hung game and a hot device, and the emulator holds the cores at a
// high operating point for as long as it is left alive.
//
// ## What this does
//
// The handler stores the trap address here. `perf_monitor` reads it on its next
// tick and pauses emulation. That stops the spin, stops the heat, and keeps the
// state for inspection.
//
// **The handler must not pause the emulator itself.** It runs in signal
// context, and `Emu.Pause()` takes locks. This fork has already deadlocked once
// by running lock-taking work inline where upstream queued it: the savestate
// resume ran `FinalizeRunRequest` under `lv2_obj::g_mutex` and self-deadlocked,
// because this port binds `CallFromMainThread` to a direct call. A store to an
// atomic is all the handler does.
//
// ## Scope, deliberately narrow
//
// This acts ONLY on the `0xffdeadXX` trap range, where the guest asked to stop.
// An ordinary access violation keeps upstream's behaviour, because a guest
// memory fault can be recoverable and this is not the place to change that.
//
//   debug.rpcsx.thor.spu_trap_stop = 0   keep the old behaviour
//
// It does NOT fix the halt. The guest still stops itself, and why it does is
// unresolved. It removes the cost of the halt: a frozen picture and a hot
// device become a stopped emulator with a reason in the log.

#include "Emu/Cell/SPUThread.h"
#include "Emu/System.h"
#include "util/types.hpp"

#include <atomic>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace thor
{
	// Written by the access violation handler in signal context. Zero means no
	// trap has happened.
	inline std::atomic<u32> g_spu_trap_addr{0};

	inline bool spu_trap_stop_enabled()
	{
		static const bool s_enabled = []
		{
#ifdef ANDROID
			char value[PROP_VALUE_MAX]{};

			if (__system_property_get("debug.rpcsx.thor.spu_trap_stop", value) > 0 && value[0] == '0')
			{
				return false;
			}
#endif
			return true;
		}();

		return s_enabled;
	}

	// Raise a fake trap, so the stop path can be tested without waiting for the
	// real halt. The real halt is rarer than 1 in 52 controlled boots, and an
	// untested path on a fatal handler is worth nothing.
	//
	//   adb shell setprop debug.rpcsx.thor.spu_trap_stop_test 1
	//
	// This tests the monitor half: the flag, the log and the pause. It does NOT
	// test the store in the access violation handler, which is one line.
	inline void spu_trap_stop_test_tick()
	{
#ifdef ANDROID
		static bool s_fired = false;

		if (s_fired)
		{
			return;
		}

		char value[PROP_VALUE_MAX]{};

		if (__system_property_get("debug.rpcsx.thor.spu_trap_stop_test", value) > 0 && value[0] && value[0] != '0')
		{
			s_fired = true;
			g_spu_trap_addr.store(0xffdead00, std::memory_order_relaxed);
		}
#endif
	}

	// Call from a monitor thread. It acts one time.
	inline void spu_trap_stop_tick()
	{
		spu_trap_stop_test_tick();

		const u32 addr = g_spu_trap_addr.load(std::memory_order_relaxed);

		if (!addr)
		{
			return;
		}

		// Clear first, so a failure to pause cannot spin this every tick.
		g_spu_trap_addr.store(0, std::memory_order_relaxed);

		if (!spu_trap_stop_enabled())
		{
			return;
		}

		if (Emu.IsStopped() || Emu.IsPaused())
		{
			return;
		}

		spu_log.error("SPU trap 0x%08x: the guest stopped its own SPU. Pausing emulation. "
					  "Without this the SPU threads spin at about 90%% CPU and 90 C with a frozen "
					  "picture. Set debug.rpcsx.thor.spu_trap_stop=0 to keep running instead.",
			addr);

		Emu.Pause();
	}
} // namespace thor
