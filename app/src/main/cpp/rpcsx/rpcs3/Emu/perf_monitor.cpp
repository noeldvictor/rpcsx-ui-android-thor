#include "stdafx.h"
#include "perf_monitor.hpp"

#include "Emu/System.h"
#include "Emu/Cell/timers.hpp"
#include "Emu/Cell/thor_spu_selfloop_park.h"
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

	for (u64 sleep_until = get_system_time();;)
	{
		thread_ctrl::wait_until(&sleep_until, update_interval_us);
		elapsed_us += update_interval_us;

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
