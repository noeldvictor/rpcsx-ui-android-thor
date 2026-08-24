#include "stdafx.h"
#include "perf_monitor.hpp"

#include "Emu/System.h"
#include "Emu/IdManager.h"
#include "Emu/RSX/RSXThread.h"
#include "Emu/Cell/timers.hpp"
#include "Emu/Cell/thor_spu_selfloop_park.h"
#include "Emu/Cell/thor_spu_ls_dump.h"
#include "Emu/Cell/thor_spu_trap_stop.h"
#include "Emu/RSX/thor_rsx_fifo_park.h"
#include "Emu/thor_thermal_guard.h"
#include "Emu/thor_device_stats.h"
#include "util/cpu_stats.hpp"
#include "util/sysinfo.hpp"
#include "util/Thread.h"

LOG_CHANNEL(perf_log, "PERF");

void perf_monitor::operator()()
{
	constexpr u64 update_interval_us = 500000;      // Update every half second
	constexpr u64 log_interval_us_max = 10000000;   // Log at least every 10 seconds
	constexpr u64 log_interval_us_min = 500000;     // Log up to every half second when RAM is climbing
	constexpr u64 log_mem_increase = 50 * 1024 * 1024;
	u64 elapsed_us = 0;

	utils::cpu_stats stats;
	stats.init_cpu_query();

	u32 logged_pause = 0;
	u64 last_pause_time = umax;
	u64 max_memory_usage = 0;

	std::vector<double> per_core_usage;
	std::string msg;

	// Guest frame accounting, so an A/B can read frames out of this log.
	u64 last_flip_index = 0;
	u64 last_flip_time = umax;

	u64 thermal_tick = 0;
	bool thermal_engaged_logged = false;

	for (u64 sleep_until = get_system_time();;)
	{
		thread_ctrl::wait_until(&sleep_until, update_interval_us);
		elapsed_us += update_interval_us;

		// Sample temperature for the gameplay thermal guard.
		//
		// Here because this thread already wakes on a timer and nothing on the
		// render path can afford to read sysfs. Every fourth tick, so about 2 s:
		// silicon temperature does not move faster than that, and the guard has
		// hysteresis to absorb what it does miss.
		if (++thermal_tick % 4 == 0)
		{
			thor::thermal_guard::sample();

			// Write one SPU local store, if somebody asked for one. It returns
			// at once when the property is unset, which is the default, and it
			// writes at most one file for each run. It lives here so that no SPU
			// path pays for it.
			thor::spu_ls_dump_tick();

			// Stop the emulator if the guest halted its own SPU.
			thor::spu_trap_stop_tick();

			// Emergency thermal stop. The frame cap bounds the renderer; this stops
			// the emulator. Same reason the trap stop lives here: pausing takes
			// locks, so it must not happen on a sampling or signal path.
			if (thor::thermal_guard::check_thermal_abort())
			{
				perf_log.error("THERMAL ABORT at %u C, sustained for %u samples. Pausing "
					"emulation to protect the device. A frame cap does not stop this: the "
					"heat is SPU work, not presentation. Raise or clear "
					"debug.rpcsx.thor.thermal_abort_c to continue.",
					thor::thermal_guard::hottest_celsius(), thor::thermal_guard::g_abort_dwell);

				Emu.Pause();
			}

			// Log the EDGES only. A line every 2 s would bury the log, and the
			// interesting facts are when it engaged, how hot it was, and when it
			// let go again.
			if (const bool now_engaged = thor::thermal_guard::engaged(); now_engaged != thermal_engaged_logged)
			{
				thermal_engaged_logged = now_engaged;

				if (now_engaged)
				{
					perf_log.warning("Thermal guard ENGAGED at %u C, limiting to %u FPS",
						thor::thermal_guard::hottest_celsius(), thor::thermal_guard::g_hot_fps);
				}
				else
				{
					perf_log.notice("Thermal guard released at %u C",
						thor::thermal_guard::hottest_celsius());
				}
			}
		}

		double total_usage = 0.0;

		stats.get_per_core_usage(per_core_usage, total_usage);

		const u64 current_mem_use = utils::get_memory_usage().second;
		const u64 mem_use_increase = current_mem_use >= max_memory_usage ? current_mem_use - max_memory_usage : 0;
		const u64 log_interval = mem_use_increase >= log_mem_increase ? log_interval_us_min : log_interval_us_max;

		if (elapsed_us >= log_interval || thread_ctrl::state() == thread_state::aborting)
		{
			max_memory_usage = std::max<u64>(current_mem_use, max_memory_usage);
			elapsed_us = 0;

			const bool is_paused = Emu.IsPaused();
			const u64 pause_time = Emu.GetPauseTime();

			if (!is_paused || last_pause_time != pause_time)
			{
				// Resumed or not paused since last check
				logged_pause = 0;
				last_pause_time = pause_time;
			}

			if (is_paused)
			{
				if (logged_pause >= 2)
				{
					// Let's not spam the log when emulation is paused
					// But still emit the message two times so even paused state can be debugged and inspected
					continue;
				}

				logged_pause++;
			}

			msg.clear();
			fmt::append(msg, "CPU Usage: Total: %.1f%%", total_usage);

			if (!per_core_usage.empty())
			{
				fmt::append(msg, ", Cores:");
			}

			for (usz i = 0; i < per_core_usage.size(); i++)
			{
				fmt::append(msg, "%s %.1f%%", i > 0 ? "," : "", per_core_usage[i]);
			}

			if (max_memory_usage)
			{
				fmt::append(msg, ", RAM Usage: %lluMB (Peak: %lluMB)",
					current_mem_use / (1024 * 1024), max_memory_usage / (1024 * 1024));
			}

			// Frames rendered since the previous report.
			//
			// The guest's own flip counter, NOT the host compositor. `dumpsys
			// SurfaceFlinger --latency` is not usable for this: it reported a frozen
			// layer for a session whose own overlay read 25.74 FPS, because the scene
			// was a dialogue box and the presented image barely changed. Its buffer is
			// also a fixed 126 entries, so a stale read is indistinguishable from a
			// real measurement. int_flip_index does not care whether the picture
			// changed.
			//
			// The window is measured rather than assumed, because the log interval
			// drops from 10 s to 0.5 s whenever RAM is climbing.
			if (const auto rsx_thr = g_fxo->try_get<rsx::thread>())
			{
				const u64 flips = rsx_thr->int_flip_index;
				const u64 now = get_system_time();

				if (last_flip_time != umax && now > last_flip_time)
				{
					const u64 window_us = now - last_flip_time;
					const u64 frames = flips >= last_flip_index ? flips - last_flip_index : 0;

					fmt::append(msg, ", Frames: %llu in %.2fs (%.2f FPS)", frames,
						window_us / 1000000.0, frames * 1000000.0 / window_us);

					// Publish for the control API, so a tool can read speed, heat and
					// power without grepping the log. Frames go with the CPU number on
					// purpose: CPU alone cannot tell a thread that stopped spinning
					// from an emulator that stopped working.
					thor::device_stats::publish(frames * 1000000.0 / window_us,
						total_usage / 100.0 * utils::get_thread_count(), flips,
						current_mem_use / (1024 * 1024));
				}

				last_flip_index = flips;
				last_flip_time = now;
			}

			// The SPU self-loop park writes entries/last_pc BEFORE the wait and exits
			// after it, so `parked_now` is the number of SPU threads parked at this
			// instant and `last_pc` says where. Nothing in the tree read those three
			// words until now, which made a null A/B unreadable: a lever with no reach
			// and a lever with no effect both produce "no change".
			//
			// Printed only when the park is on, because the call is only emitted into
			// the JIT when the timeout is non-zero. entries=0 with the park ON is
			// therefore a real result - it says this scene never branches to self.
			//
			// perf_log.notice() is used because this thread's output is already in
			// RPCSX.log. rsx_log.always() does NOT reach the Android sink; that cost a
			// build and a boot on 2026-08-17.
			if (thor::spu_selfloop_park_enabled())
			{
				const u64 entries = thor::g_spu_selfloop_park.entries.load();
				const u64 exits = thor::g_spu_selfloop_park.exits.load();

				fmt::append(msg, ", SPU self-loop park: entries=%llu exits=%llu parked_now=%llu last_pc=0x%05x",
					entries, exits, entries - exits, thor::g_spu_selfloop_park.last_pc.load());
			}

			// Reported only when the RSX park is on. parks=0 with it enabled is a
			// real result: it says the ring never stayed empty long enough.
			// Printed when EITHER the park or the pause ladder is on. The ladder also
			// increments idle_polls, and gating this on enabled() alone made the
			// ladder's reach invisible: with it on and the park off, nothing printed,
			// so "the ring is never empty" and "the lever is not running" looked the
			// same. That is the exact failure this file's counters exist to prevent.
			if (thor::rsx_fifo::enabled() || thor::rsx_fifo::pause_ladder())
			{
				fmt::append(msg, ", RSX FIFO park: idle_polls=%llu parks=%llu slept_ms=%llu",
					thor::rsx_fifo::g_idle_polls.load(), thor::rsx_fifo::g_parks.load(),
					thor::rsx_fifo::g_park_us_total.load() / 1000);
			}

			// The stcx stale-128 probe. Printed unconditionally while the question is
			// open, because a zero here is the RESULT - it says this tree does not have
			// ARMSX3's ldarx defect - and a zero must be distinguishable from a probe
			// that never ran, which is why the other-failure control prints beside it.
			{
				extern atomic_t<u64> g_ppu_stcx_stale_128;
				extern atomic_t<u64> g_ppu_stcx_other_fail;

				fmt::append(msg, ", stcx: stale128=%llu other_fail=%llu",
					g_ppu_stcx_stale_128.load(), g_ppu_stcx_other_fail.load());
			}

			perf_log.notice("%s", msg);

			if (thread_ctrl::state() == thread_state::aborting)
			{
				break;
			}
		}
	}
}

perf_monitor::~perf_monitor()
{
}
