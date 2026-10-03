#pragma once

// A thermal governor for JIT and shader compile work: compile as fast as the temperature allows.
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
// THE FLOOR IS 0 JOBS: COMPILE PAUSES. Measured 2026-10-03, Tales of Symphonia Chronicles
// (BLUS31172), first boot: with one job left the junction still reached 95 to 96 C, because
// the boot runs more than the compile. At 0 jobs a new job waits until the junction is at
// target minus the band. When no compile has run for compile_max_wait_s, one job runs anyway,
// so heat from another source (a charger, another app) cannot hang a compile.
//
// Governed: PPU module compile, SPU cache compile, the RSX shader cache compile at boot, and
// deferred Vulkan pipeline compile. Not governed: an inline pipeline compile, because the
// render thread waits for it, and an SPU compile at run time, because a guest thread waits.
//
//   debug.rpcsx.thor.compile_target_c    junction target, C (default 85; 0 turns the governor off)
//   debug.rpcsx.thor.compile_band_c      gives a slot back at target minus this (default 5)
//   debug.rpcsx.thor.compile_min_jobs    never fewer than this (default 0: compile can pause)
//   debug.rpcsx.thor.compile_max_wait_s  longest wait for a slot at 0 jobs (default 30)
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
	inline const u32 g_min_jobs = thermal_guard::read_u32_property("debug.rpcsx.thor.compile_min_jobs", 0);
	inline const u32 g_max_wait_s = thermal_guard::read_u32_property("debug.rpcsx.thor.compile_max_wait_s", 30);

	inline u32 max_jobs() noexcept
	{
		return std::max<u32>(1, std::thread::hardware_concurrency());
	}

	inline atomic_t<u32> g_allowed{0};
	inline atomic_t<u32> g_active{0};

	// Counters for the summary line the compile code logs.
	inline atomic_t<u32> g_peak_c{0};
	inline atomic_t<u32> g_lowest_allowed{0};
	inline atomic_t<u32> g_reductions{0};
	inline atomic_t<u32> g_pauses{0};      // times the allowed count reached 0
	inline atomic_t<u64> g_paused_ms{0};   // time spent at 0 allowed
	inline atomic_t<u32> g_forced{0};      // jobs that ran after compile_max_wait_s at 0 allowed

	inline u64 now_ms() noexcept
	{
		return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
	}

	// When a job last started or ended. The longest wait counts from here, for all jobs
	// together, so a forced job always follows compile_max_wait_s with no compile running.
	// Counted per job, the jobs that waited longest ran one after another as soon as the slot
	// was free, and the floor was 1 job again (Folklore BCUS98114, 2026-10-03: 17 forced jobs,
	// peak 95 C).
	inline atomic_t<u64> g_last_busy_ms{0};

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
				auto last = std::chrono::steady_clock::now();

				while (true)
				{
					const u32 c = read_hottest_c();
					u32 allowed = g_allowed;
					const auto now = std::chrono::steady_clock::now();

					if (allowed == 0)
					{
						g_paused_ms += std::chrono::duration_cast<std::chrono::milliseconds>(now - last).count();
					}

					last = now;

					if (c)
					{
						g_peak_c.fetch_op([c](u32& v) { v = std::max(v, c); });

						if (c >= g_target_c)
						{
							const u32 step = c >= g_target_c + 3 ? 2 : 1;
							const u32 next = std::max(g_min_jobs, allowed > step ? allowed - step : 0);

							if (next < allowed)
							{
								g_reductions++;

								if (next == 0)
								{
									g_pauses++;
								}
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
					else if (allowed == 0)
					{
						// No sensor reading: never stay paused on a value we cannot see.
						g_allowed = 1;
					}

					// Fast while compile work is running or waiting, slow when idle.
					std::this_thread::sleep_for(std::chrono::milliseconds(g_active || allowed == 0 ? 250 : 1000));
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

			const u64 max_wait_ms = u64{g_max_wait_s} * 1000;

			while (true)
			{
				const u32 active = g_active;
				const u32 allowed = g_allowed;

				if (active < allowed && g_active.compare_and_swap_test(active, active + 1))
				{
					g_last_busy_ms = now_ms();
					m_held = true;
					return;
				}

				// No compile has run for the longest wait: run one job, so the compile always ends.
				if (allowed == 0 && active == 0 && now_ms() - g_last_busy_ms >= max_wait_ms &&
					g_active.compare_and_swap_test(0, 1))
				{
					g_last_busy_ms = now_ms();
					g_forced++;
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
				g_last_busy_ms = now_ms();
				g_active--;
			}
		}
	};
} // namespace thor::compile_governor
