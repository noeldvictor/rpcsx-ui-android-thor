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
	inline const u32 g_hot_fps = read_u32_property("debug.rpcsx.thor.thermal_guard_fps", 20);

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

	inline bool engaged() noexcept { return g_engaged.observe(); }

	// The frame limit to impose right now, or 0 for "do not interfere".
	inline double frame_limit_or_zero() noexcept
	{
		return engaged() ? static_cast<double>(g_hot_fps) : 0.0;
	}
} // namespace thor::thermal_guard
