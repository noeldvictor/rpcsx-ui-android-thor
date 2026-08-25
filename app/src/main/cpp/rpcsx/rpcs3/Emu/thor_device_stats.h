#pragma once

// Device state for a tool driving the emulator: heat, throttling, power, speed.
//
// ## Why it belongs in the API
//
// A tool that runs experiments on this handheld has to know the state of the
// machine, and every one of these has already decided a result here:
//
// * **Heat.** A hot device is a throttled device, and a throttled arm measures
//   the throttle rather than the change. One session watched cores go 47 C to
//   95 C and every number taken in it was void.
// * **The thermal guard.** An arm pinned at exactly the guard's frame cap is a
//   tripped guard, not a slow configuration. Two `SPU loop detection` arms read
//   20.00 FPS for that reason, and without the guard state that reads as "the
//   lever is slower".
// * **Power.** The battery fuel gauge on this device is frozen in all four
//   nodes, so wattage comes from the CHARGER INPUT instead.
// * **Speed.** Frames and CPU together, because a CPU number alone cannot tell
//   a thread that stopped spinning from an emulator that stopped working.
//
// ## The traps, all of them already paid for here
//
// **Read the `cpu-1-*` junction zones, not a bare max over every zone.** All
// zones read 63400 in the same minute `cpu-1-*` read 84300. The thermal guard
// already does this, so this file asks the guard rather than re-reading sysfs.
//
// **The temperature is up to about 2 seconds old**, because the guard samples
// every fourth `perf_monitor` tick. That is deliberate: nothing on the render
// path can afford to read sysfs.
//
// **Do the power arithmetic in the right order.** `(v/1000) * i` overflows
// 32-bit and reported -1334 mW for a device drawing 2.4 W. Divide both terms
// first.
//
// **Wattage is only valid while the battery is NOT charging**, or the input
// power includes whatever goes into the cell.

#include "util/types.hpp"
#include "Emu/thor_thermal_guard.h"

#include <atomic>
#include <cstdio>
#include <string>

namespace thor::device_stats
{
	// Written by perf_monitor on its own timer. Fixed point, so they stay atomic
	// and lock free without a double.
	inline std::atomic<u32> g_fps_milli{0};   // frames per second x1000
	inline std::atomic<u32> g_cores_milli{0}; // cores busy x1000
	inline std::atomic<u64> g_frames{0};      // guest flips since boot
	inline std::atomic<u64> g_ram_mb{0};

	inline void publish(double fps, double cores, u64 frames, u64 ram_mb) noexcept
	{
		g_fps_milli.store(static_cast<u32>(fps * 1000.0), std::memory_order_relaxed);
		// Let the thermal guard bind below its own cap: a 30 fps cap sheds nothing
		// from a 19 fps scene. See thor_thermal_guard.h.
		thermal_guard::note_measured_fps(fps);
		g_cores_milli.store(static_cast<u32>(cores * 1000.0), std::memory_order_relaxed);
		g_frames.store(frames, std::memory_order_relaxed);
		g_ram_mb.store(ram_mb, std::memory_order_relaxed);
	}

	inline s64 read_s64(const char* path) noexcept
	{
		std::FILE* f = std::fopen(path, "re");

		if (!f)
		{
			return -1;
		}

		long long v = -1;

		if (std::fscanf(f, "%lld", &v) != 1)
		{
			v = -1;
		}

		std::fclose(f);
		return static_cast<s64>(v);
	}

	// Charger input power in mW, or -1 when it cannot be read. The battery fuel
	// gauge is frozen on this device, so this is the only working instrument.
	inline s64 input_power_mw() noexcept
	{
		const s64 uv = read_s64("/sys/class/power_supply/usb/voltage_now");
		const s64 ua = read_s64("/sys/class/power_supply/usb/current_now");

		if (uv <= 0 || ua <= 0)
		{
			return -1;
		}

		// Divide FIRST. (uv/1000) * ua overflows 32-bit and once reported a
		// negative wattage for a device drawing 2.4 W.
		return (uv / 1000) * (ua / 1000) / 1000;
	}

	inline std::string to_json()
	{
		const s64 mw = input_power_mw();
		const s64 charging = read_s64("/sys/class/power_supply/battery/current_now");
		const s64 batt_pct = read_s64("/sys/class/power_supply/battery/capacity");
		const s64 batt_dc = read_s64("/sys/class/power_supply/battery/temp");

		char buf[768];
		std::snprintf(buf, sizeof(buf),
			"{\"cpuJunctionC\":%u,\"thermalGuardEngaged\":%s,\"thermalGuardCapFps\":%u,"
			"\"fps\":%.2f,\"coresBusy\":%.3f,\"frames\":%llu,\"ramMb\":%llu,"
			"\"inputPowerMw\":%lld,\"batteryPercent\":%lld,\"batteryC\":%.1f,"
			"\"note\":\"cpuJunctionC is a cpu-1-* zone and up to ~2s old; "
			"inputPowerMw is charger input and is only valid while NOT charging\"}",
			thermal_guard::hottest_celsius(),
			thermal_guard::engaged() ? "true" : "false",
			thermal_guard::engaged() ? thermal_guard::g_hot_fps : 0u,
			g_fps_milli.load() / 1000.0,
			g_cores_milli.load() / 1000.0,
			static_cast<unsigned long long>(g_frames.load()),
			static_cast<unsigned long long>(g_ram_mb.load()),
			static_cast<long long>(mw),
			static_cast<long long>(batt_pct),
			batt_dc > 0 ? batt_dc / 10.0 : -1.0);

		static_cast<void>(charging);
		return std::string(buf);
	}
} // namespace thor::device_stats
