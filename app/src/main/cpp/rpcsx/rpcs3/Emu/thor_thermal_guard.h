#pragma once

// A thermal guard that covers GAMEPLAY.
//
// WHY THIS EXISTS. This project already had a thermal probe, and it covered
// exactly one moment: `rpcsx::thermal_headroom_probe::sample_before_ppu_compile`,
// called from one site in PPUThread.cpp. Nothing looked at temperature again once
// the game was running, so nothing could react to it.
//
// MEASURED 2026-08-22, Transformers: War for Cybertron (BLUS30357), uncapped,
// sampling the named thermal zones every 12 s from a 45 C idle:
//
//   idle    45 C
//   +12 s   77 C  cpu-1-9
//   +24 s   94 C  cpu-1-5      <- peak
//   +36 s   80 C  cpu-1-3      <- the SoC throttling it back by itself
//   +48 s   69 C  cpu-1-8
//
// Back to 47 C within 25 s of a force-stop, so it is emulator load and nothing
// else. `top -H` at the peak shows one SPU thread at 96.2%.
//
// The device is not being destroyed: the SoC and Android's thermal HAL throttle in
// hardware, which is what the 80 C and 69 C readings are. The point of this guard
// is that being throttled BY THE HARDWARE is the worst way to lose performance,
// because it is unpredictable and it arrives after the heat. Giving up frames
// deliberately, earlier, costs less than being clamped later.
//
// ## What it does
//
// Above `engage` degrees it imposes a frame limit. Below `release` degrees it
// removes it. The gap between the two is hysteresis: without it a guard sitting on
// its threshold oscillates, and an oscillating frame cap is worse than either
// state.
//
// It applies EVEN WHEN THE GAME IS UNCAPPED, which is the case that produced the
// 94 C reading above. A title with no frame limit will otherwise render as fast as
// the silicon allows and heat is the only thing that stops it.
//
//   debug.rpcsx.thor.thermal_guard_c       engage temperature, C (default 85, 0 = off)
//   debug.rpcsx.thor.thermal_guard_release release temperature, C (default 70)
//   debug.rpcsx.thor.thermal_guard_dwell   samples to stay engaged (default 8, ~16 s)
//   debug.rpcsx.thor.thermal_guard_fps     frame limit while engaged (default 20)
//
// ## IT DOES NOT COOL EVERY TITLE, AND HERE IS THE PROOF
//
// Measured with the guard live on Transformers, uncapped, engaging correctly:
//
//   t+180 s   87 C   19.85 FPS
//   t+200 s   95 C   19.60 FPS     <- engaged, capped, and HOTTER
//   t+220 s   93 C   19.90 FPS
//
// The cap held at 20 FPS the whole time and the package still climbed. In this
// title the heat is one SPU thread at ~96% running guest code, and that thread is
// not frame-bound: capping presentation does not idle it. `top -H` and the profile
// agree, 29.37% of all cycles in a single SPU thread's JIT code.
//
// So this guard bounds the RENDER path and nothing else. It is worth having,
// because an uncapped title will otherwise render as fast as the silicon allows
// forever, and because deliberate frame loss beats being clamped by the hardware.
// It is NOT a fix for a saturated SPU thread and must not be described as one.
//
// ## What it does NOT do
//
// It does not touch thread counts, affinity or the recompilers. Those were tried
// in this project before and are recorded as either null or a bad exchange; see
// the SPU affinity retraction and the cache pacing note in CLAUDE.md. Frame rate
// is the one lever that reliably reduces work here without changing behaviour.
//
// ## Cost
//
// Sampling opens a few small sysfs files. It is done from perf_monitor, which
// already wakes every 500 ms, and only every few ticks. The paths are discovered
// ONCE. Everything on the render path is a relaxed load of one atomic, because a
// thermal guard that costs frames to ask about would be self-defeating.

#include "util/atomic.hpp"
#include <atomic>
#include "util/types.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <dirent.h>
#include <sys/system_properties.h>
#endif

namespace thor::thermal_guard
{
	// Millicelsius of the hottest CPU zone at the last sample. 0 means "not
	// sampled yet", which reads as cold and engages nothing.
	inline atomic_t<u32> g_hottest_mc{0};

	// Set by sample(), read by the render path.
	inline atomic_t<bool> g_engaged{false};

	// Samples spent engaged, for the dwell below.
	inline atomic_t<u32> g_engaged_samples{0};

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

		if (end == value || (end && *end) || parsed > 200)
		{
			return fallback;
		}

		return static_cast<u32>(parsed);
#else
		static_cast<void>(name);
		return fallback;
#endif
	}

	// Read once at load, so the render path never parses a property.
	inline const u32 g_engage_c = read_u32_property("debug.rpcsx.thor.thermal_guard_c", 85);
	inline const u32 g_release_c = read_u32_property("debug.rpcsx.thor.thermal_guard_release", 70);
	// RAISED FROM 20 TO 30 on 2026-08-24, measured.
	//
	// The header above already says this guard "does not cool every title" and
	// shows Transformers climbing to 95 C while pinned at the 20 FPS cap. This is
	// the other half of that measurement: what the cap COSTS when it does not
	// cool.
	//
	// BLUS30357, restored 3D combat, eight arms across three A-B-A runs, with the
	// guard reporting engaged in 8/8 samples of every arm:
	//
	//   thermal_guard_fps = 20   18.08, 18.09, 18.20      Tend 91-95 C
	//   thermal_guard_fps = 60   18.79, 18.84, 18.86, 18.94, 18.96   Tend 91-97 C
	//
	// Every arm at 60 beat every arm at 20, and the two groups do not overlap. So
	// the cap costs about 4% of the frame rate. The temperatures are the same, so
	// it buys nothing back - exactly as the header predicts for a title whose heat
	// is a saturated SPU thread rather than presentation.
	//
	// 30 rather than 60, because the guard still has a real job on a title with NO
	// frame limit of its own, which is the case that produced the 94 C reading
	// documented above. 30 still bounds that, and it is at or above the internal
	// limit of most titles, so it stops being a silent tax on titles the cap
	// cannot help. A device that wants the old behaviour sets the property to 20.
	inline const u32 g_hot_fps = read_u32_property("debug.rpcsx.thor.thermal_guard_fps", 30);
	inline const u32 g_floor_ratio = read_u32_property("debug.rpcsx.thor.thermal_guard_floor_ratio", 0);
	inline std::atomic<double> g_last_fps{0.0};

	// Fed by device_stats::publish(), which already computes the rate. Pushed in
	// rather than pulled, because device_stats includes this header and the
	// reverse would be circular.
	inline void note_measured_fps(double fps) noexcept { g_last_fps.store(fps); }

	// Minimum samples to stay engaged once engaged, whatever the temperature does.
	//
	// MEASURED, AND THE FIRST VERSION OF THIS GUARD FLAPPED. With hysteresis alone
	// at 85 engage / 75 release it engaged and released more than twenty times in
	// three and a half minutes:
	//
	//   ENGAGED at 85 C  ->  released at 71 C, two seconds later
	//
	// Capping the frame rate idles the cores instantly, so the per-core sensor
	// falls 14 C in one sample and the guard lets go before the heat has actually
	// gone anywhere. Then it climbs straight back. A cap that switches every two
	// seconds is worse to play than either state, which is the failure the comment
	// above already predicted and the band alone did not prevent.
	//
	// Sampling is every 4th perf_monitor tick, so about 2 s; 8 samples is about
	// 16 s of dwell. Long enough that the package, not one core, has to come down.
	inline const u32 g_min_engaged_samples =
		read_u32_property("debug.rpcsx.thor.thermal_guard_dwell", 8);

	inline bool enabled() noexcept { return g_engage_c != 0 && g_hot_fps != 0; }

	// The CPU thermal zones, discovered once.
	//
	// Only zones whose `type` starts with "cpu" are kept. This device exposes a
	// great many zones, and the hottest of ALL of them is not a CPU measurement;
	// an earlier reading here took an unnamed max across every zone and could not
	// say what it had measured.
	inline const std::vector<std::string>& zone_paths() noexcept
	{
		static const std::vector<std::string> paths = []
		{
			std::vector<std::string> found;

#if defined(__ANDROID__)
			DIR* dir = ::opendir("/sys/class/thermal");

			if (!dir)
			{
				return found;
			}

			while (const dirent* entry = ::readdir(dir))
			{
				if (std::strncmp(entry->d_name, "thermal_zone", 12) != 0)
				{
					continue;
				}

				std::string base = std::string("/sys/class/thermal/") + entry->d_name;
				char type[64]{};

				if (std::FILE* f = std::fopen((base + "/type").c_str(), "re"))
				{
					const usz n = std::fread(type, 1, sizeof(type) - 1, f);
					type[n] = '\0';
					std::fclose(f);
				}

				if (std::strncmp(type, "cpu", 3) == 0)
				{
					found.push_back(base + "/temp");
				}
			}

			::closedir(dir);
#endif
			return found;
		}();

		return paths;
	}

	// Read the hottest CPU zone and update the engaged flag. Call from a periodic
	// thread, NOT from anything on the render or recompiler path.
	inline void sample() noexcept
	{
		if (!enabled())
		{
			return;
		}

		u32 hottest = 0;

		for (const std::string& path : zone_paths())
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

		if (!hottest)
		{
			return;
		}

		g_hottest_mc.release(hottest);

		const u32 celsius = hottest / 1000;

		// Hysteresis PLUS a dwell. Engage high, then stay engaged for a minimum
		// number of samples before the release threshold is even considered.
		if (!g_engaged)
		{
			if (celsius >= g_engage_c)
			{
				g_engaged.release(true);
				g_engaged_samples.release(0);
			}
		}
		else if (g_engaged_samples.observe() < g_min_engaged_samples)
		{
			g_engaged_samples.release(g_engaged_samples.observe() + 1);
		}
		else if (celsius <= g_release_c)
		{
			g_engaged.release(false);
		}
	}

	inline u32 hottest_celsius() noexcept { return g_hottest_mc.observe() / 1000; }

	// EMERGENCY STOP, above the guard.
	//
	// The frame cap is not thermal protection. It bounds the RENDER path, and
	// Transformers proved that is not where the heat is: with the guard engaged
	// and holding 20 FPS the junction still climbed to 95 C, because one SPU
	// thread was busy regardless of presentation.
	//
	// So there is a second line: if the junction stays at or above the abort
	// temperature for a few consecutive samples, PAUSE emulation outright. A
	// paused emulator measured 0.33 cores against 3.91 running, so this actually
	// stops the heat instead of asking the renderer to slow down.
	//
	//   debug.rpcsx.thor.thermal_abort_c      default 100, 0 disables
	//   debug.rpcsx.thor.thermal_abort_dwell  default 3 samples, about 6 s
	//
	// The default is deliberately ABOVE normal play. This title peaks at 94 to
	// 97 C in gameplay, so 100 C never fires in normal use and only catches a
	// runaway. An experiment should set it LOWER, because a harness left running
	// unattended is exactly how this device got held at 95 C.
	inline const u32 g_abort_c = read_u32_property("debug.rpcsx.thor.thermal_abort_c", 100);
	inline const u32 g_abort_dwell = read_u32_property("debug.rpcsx.thor.thermal_abort_dwell", 3);
	inline atomic_t<u32> g_abort_streak{0};
	inline atomic_t<bool> g_aborted{false};

	// Returns true exactly once, on the sample that trips the abort.
	inline bool check_thermal_abort() noexcept
	{
		if (g_abort_c == 0 || g_aborted.load())
		{
			return false;
		}

		const u32 now_c = hottest_celsius();

		if (now_c < g_abort_c)
		{
			g_abort_streak = 0;
			return false;
		}

		// Dwell, so a launch transient cannot trip it. This device reads 56.6 C at
		// t=4 s and 46.6 C by t=10 s, and a guard without dwell force-stopped
		// fifteen consecutive runs on heat it never sustained.
		if (++g_abort_streak < g_abort_dwell)
		{
			return false;
		}

		g_aborted = true;
		return true;
	}

	inline bool engaged() noexcept { return g_engaged.observe(); }

	// The frame limit to impose right now, or 0 for "do not interfere".
	// A CAP CANNOT COOL A GAME THAT IS ALREADY BELOW IT.
	//
	// The guard engages at 85 C and returns g_hot_fps (30). The frame limiter then
	// caps to 30. That sheds real work in the scenes this guard was built for -
	// Transformers renders its engine cutscenes at 120-133 FPS - but restored 3D
	// COMBAT runs at about 19 FPS, so the 30 cap never binds, no work is removed,
	// and the device climbs to 93-96 C with the guard "engaged" and doing nothing.
	//
	// `thermal_guard_floor_ratio` gives the guard something to do in that case: if
	// the measured rate is already under the cap, cap to a FRACTION of the
	// measured rate instead, which does bind and does shed work.
	//
	//   debug.rpcsx.thor.thermal_guard_floor_ratio = <percent>   (default 0 = off)
	//
	// 0 keeps the shipped behaviour exactly. 85 would ask a 19 FPS scene to run at
	// about 16 FPS while it is over temperature. That is a REAL trade - it buys
	// temperature with frames - so it stays opt-in until measured, and it must be
	// judged on temperature, not on frame rate.
	inline double frame_limit_or_zero() noexcept
	{
		if (!engaged())
		{
			return 0.0;
		}

		const double cap = static_cast<double>(g_hot_fps);

		if (g_floor_ratio == 0)
		{
			return cap;
		}

		const double measured = g_last_fps.load();

		if (measured > 1.0 && measured < cap)
		{
			// Already under the cap: bind to a fraction of what we actually get.
			const double floored = measured * static_cast<double>(g_floor_ratio) / 100.0;
			return floored > 1.0 ? floored : cap;
		}

		return cap;
	}
} // namespace thor::thermal_guard
