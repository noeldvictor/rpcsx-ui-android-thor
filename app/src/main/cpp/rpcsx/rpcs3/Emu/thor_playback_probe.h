#pragma once

// Is the guest playing a MOVIE right now?
//
// ## Why an agent needs this
//
// A screenshot does not say whether the picture is a cutscene or the game. A
// tool that drives the emulator must know, for two reasons:
//
// 1. **To skip.** A movie is skipped with START, and pressing START during
//    gameplay does something else entirely.
// 2. **To refuse to measure.** A cutscene cannot resolve an A/B here. This
//    project measured ONE configuration at 3.78 and 5.89 cores on consecutive
//    rounds because each run landed in a different scene, and the user's
//    complaint at the time was exactly "you keep testing movies".
//
// **Frame rate is not the signal.** Transformers runs its cutscene at 120 to
// 133 FPS uncapped and its title screen at 30, so a high number looks like
// speed and is really a movie. Reading the number harder does not fix that.
//
// ## What this detects, and what it does not
//
// **Pre-rendered video (FMV) is detected exactly.** The guest decodes it
// through `cellVdec`, so a decode call IS a movie playing. No heuristic.
//
// **A real-time engine cutscene is NOT detected by this.** Transformers' intro
// is rendered by the game, not decoded, so `cellVdec` never fires. Report the
// fact measured here and let the caller combine it with the picture; do not
// dress a guess up as a detection.

#include "Emu/Cell/timers.hpp"
#include "util/types.hpp"

#include <atomic>

namespace thor
{
	inline std::atomic<u64> g_vdec_units{0};
	inline std::atomic<u64> g_vdec_last_us{0};

	// Called for each access unit the guest hands to the video decoder.
	inline void vdec_tick() noexcept
	{
		g_vdec_units.fetch_add(1, std::memory_order_relaxed);
		g_vdec_last_us.store(get_system_time(), std::memory_order_relaxed);
	}

	// Microseconds since the last decoded access unit, or umax if never.
	inline u64 vdec_age_us() noexcept
	{
		const u64 last = g_vdec_last_us.load(std::memory_order_relaxed);

		if (!last)
		{
			return umax;
		}

		const u64 now = get_system_time();
		return now > last ? now - last : 0;
	}

	// A movie is playing if the guest decoded video very recently. The window is
	// generous on purpose: a 30 fps stream is one unit every 33 ms, and a decoder
	// that is briefly starved must not read as "the movie ended".
	inline bool video_playing() noexcept
	{
		return vdec_age_us() < 500'000;
	}
} // namespace thor
