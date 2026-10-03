#pragma once

// A thermal governor for JIT compile work: compile as fast as the temperature allows.
//
// WHY. A first boot after a codegen key change compiles every PPU module on all eight cores.
// On 2026-10-03 Dragon's Crown (BLUS30767) took the CPU junction from 52 C to 95 C in about a
// minute, every time, so the compile was stopped five times before the game drew a frame. A
// fixed lower thread count would be slow when the device is cool. This holds the junction near
// a target instead, and uses as many cores as the target allows.
//
// HOW. Each compile job takes a slot (thor::compile_governor::slot) and runs only while fewer
// jobs are active than the governor allows. A monitor thread reads the cpu* thermal zones every
// 250 ms. At or above the target it takes one slot away, two when 3 C over. At target minus the
// band or lower it gives one back. A job never stops halfway: a smaller count takes effect as
// the running jobs finish.
//
//   debug.rpcsx.thor.compile_target_c   junction target, C (default 85; 0 turns the governor off)
//   debug.rpcsx.thor.compile_band_c     gives a slot back at target minus this (default 5)
//   debug.rpcsx.thor.compile_min_jobs   never fewer than this (default 1)
//
// The target is below the 87 C in-app thermal guard and the 95 C harness stop.

#include "Emu/thor_thermal_guard.h"
#include "util/atomic.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <thread>

namespace thor::compile_governor
{
	inline const u32 g_target_c = thermal_guard::read_u32_property("debug.rpcsx.thor.compile_target_c", 85);
	inline const u32 g_band_c = thermal_guard::read_u32_property("debug.rpcsx.thor.compile_band_c", 5);
	inline const u32 g_min_jobs = std::max<u32>(1, thermal_guard::read_u32_property("debug.rpcsx.thor.compile_min_jobs", 1));

	inline u32 max_jobs() noexcept
	{
		return std::max<u32>(1, std::thread::hardware_concurrency());
	}

	inline atomic_t<u32> g_allowed{0}; // 0 until the monitor starts: no limit
	inline atomic_t<u32> g_active{0};

	// Counters for the summary line the compile code logs.
	inline atomic_t<u32> g_peak_c{0};
	inline atomic_t<u32> g_lowest_allowed{0};
	inline atomic_t<u32> g_reductions{0};

	inline bool enabled() noexcept
	{
		return g_target_c != 0;
	}

	// The hottest cpu* zone now, in C, read directly: the thermal guard's value can be 2 s old,
	// and a compile moves the junction about 10 C in a few seconds.
	inline u32 read_hottest_c() noexcept
	{
		u32 hottest = 0;

		for (const std::string& path : thermal_guard::zone_paths())
		{
			std::FILE* f = std::fopen(path.c_str(), "re");

			if (!f)
			{
				continue;
			}

			char buf[32]{};
			const usz n = std::fread(buf, 1, sizeof(buf) - 1, f);
			buf[n] = '\0';
			std::fclose(f);

			const long mc = std::strtol(buf, nullptr, 10);

			if (mc > 0 && static_cast<u32>(mc) > hottest)
			{
				hottest = static_cast<u32>(mc);
			}
		}

		return hottest / 1000;
	}

	inline void start_once() noexcept
	{
		static std::once_flag s_once;

		std::call_once(s_once, []
		{
			const u32 top = max_jobs();
			g_allowed = top;
			g_lowest_allowed = top;

			std::thread([top]
			{
				while (true)
				{
					const u32 c = read_hottest_c();
					u32 allowed = g_allowed;

					if (c)
					{
						g_peak_c.fetch_op([c](u32& v) { v = std::max(v, c); });

						if (c >= g_target_c)
						{
							const u32 step = c >= g_target_c + 3 ? 2 : 1;
							const u32 next = std::max(g_min_jobs, allowed > step ? allowed - step : 1);

							if (next < allowed)
							{
								g_reductions++;
							}

							allowed = next;
						}
						else if (c + g_band_c <= g_target_c)
						{
							allowed = std::min(top, allowed + 1);
						}

						g_allowed = allowed;
						g_lowest_allowed.fetch_op([allowed](u32& v) { v = std::min(v, allowed); });
					}

					// Fast while compile work is running, slow when idle.
					std::this_thread::sleep_for(std::chrono::milliseconds(g_active ? 250 : 1000));
				}
			}).detach();
		});
	}

	// Held by one compile job for its whole length.
	class slot
	{
		bool m_held = false;

	public:
		slot() noexcept
		{
			if (!enabled())
			{
				return;
			}

			start_once();

			while (true)
			{
				const u32 active = g_active;
				const u32 allowed = g_allowed;

				if ((allowed == 0 || active < allowed) && g_active.compare_and_swap_test(active, active + 1))
				{
					m_held = true;
					return;
				}

				std::this_thread::sleep_for(std::chrono::milliseconds(20));
			}
		}

		slot(const slot&) = delete;
		slot& operator=(const slot&) = delete;

		~slot()
		{
			if (m_held)
			{
				g_active--;
			}
		}
	};
} // namespace thor::compile_governor
