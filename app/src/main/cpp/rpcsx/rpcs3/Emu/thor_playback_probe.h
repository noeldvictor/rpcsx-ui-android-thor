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
// TWO sources, because one is not enough.
//
// 1. **`cellVdec`** catches titles that use SONY'S decoder. Exact when it
//    fires, and silent otherwise.
// 2. **An open video container** catches the rest. Many PS3 games ship Bink
//    and decode it in their own SPU code, so `cellVdec` NEVER fires for them.
//
// **This was got wrong once and it matters.** Transformers plays
// `FMV_intro.bik`. The probe reported `videoDecoding: false` for the whole
// intro, that was written up as "not a movie", and a measurement was taken
// of a movie. A `vdecUnits` of 0 across a run means the title never calls
// cellVdec at all, which says NOTHING about what is on screen.
//
// **A real-time engine cutscene is still not detected by either source**, as
// it neither decodes nor opens a container. Judge that from the screenshot,
// and pause first so the picture and the decision do not race the scene.

#include "Emu/Cell/timers.hpp"
#include "util/types.hpp"

#include <atomic>
#include <cctype>
#include <string>
#include <string_view>
#include "util/atomic.hpp"
#include "util/shared_ptr.hpp"

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

	// ---------------------------------------------------------------------
	// Video the guest decodes ITSELF, on the SPUs.
	//
	// `cellVdec` catches only titles that use Sony's decoder. Many PS3 games
	// ship Bink (RAD) and decode it in their own SPU code, so `cellVdec` never
	// fires and a `vdecUnits` of 0 says NOTHING about whether a movie is on
	// screen.
	//
	// Transformers is one of them. Its intro is `FMV_intro.bik`, the probe read
	// `videoDecoding: false` throughout, and a measurement was taken of a movie.
	//
	// So watch what the guest OPENS. A title holds the container open for the
	// length of playback, which makes "a video file is open" a solid signal and
	// a much better one than any frame rate.
	// ---------------------------------------------------------------------
	inline std::atomic<u32> g_video_files_open{0};

	// DRAW CALLS IN THE LAST COMPLETED FRAME.
	//
	// `path_is_video` and cellVdec both MISS this device's most important title.
	// BLUS30357 is Unreal Engine 3: its Bink video is packed inside archives, so
	// no `.bik` path is ever opened, and it decodes on the SPUs, so cellVdec never
	// fires. `/scene` correctly reported "unknown-this-title-never-calls-cellVdec"
	// and could say nothing more, which left `coresBusy > 4.5` carrying an entire
	// 3D gate on its own.
	//
	// Draw count does not care how the video arrives. A movie is a fullscreen
	// quad - a handful of draws a frame - while this title's 3D combat submits
	// hundreds. That separation is large, and it is engine-independent, so it
	// works for titles whose movies no probe can otherwise see.
	//
	// Written once per flip from `m_frame_stats.draw_calls` just before RSXThread
	// resets it, so it is the LAST COMPLETE frame rather than one being built.
	inline std::atomic<u32> g_last_frame_draws{0};

	inline void frame_completed(u32 draw_calls) noexcept
	{
		g_last_frame_draws.store(draw_calls, std::memory_order_relaxed);
	}

	// Deliberately wide. The point is to separate "a few quads" from "a scene",
	// not to name a genre, and a threshold that tries to be precise here would be
	// tuned to one title and wrong on the next.
	inline const char* draw_activity(u32 draws) noexcept
	{
		if (draws == 0) return "no-draws";
		if (draws <= 8) return "fullscreen-quad-like";
		if (draws <= 40) return "menu-or-simple";
		return "scene";
	}
	inline std::atomic<u64> g_video_opened_us{0};
	inline atomic_ptr<std::string> g_video_name{};

	inline bool path_is_video(std::string_view path) noexcept
	{
		// Lowercase the tail only; a guest path can be any case.
		const usz dot = path.find_last_of('.');

		if (dot == umax || dot + 1 >= path.size())
		{
			return false;
		}

		std::string ext(path.substr(dot + 1));

		for (char& c : ext)
		{
			c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
		}

		return ext == "bik" || ext == "bk2" || ext == "pam" || ext == "pss" ||
			   ext == "m2v" || ext == "sfd" || ext == "mp4" || ext == "mpg" ||
			   ext == "m4v" || ext == "avi" || ext == "wmv";
	}

	inline void video_file_opened(std::string_view path) noexcept
	{
		g_video_files_open.fetch_add(1, std::memory_order_relaxed);
		g_video_opened_us.store(get_system_time(), std::memory_order_relaxed);
		g_video_name = stx::make_single<std::string>(std::string(path));
	}

	inline void video_file_closed() noexcept
	{
		u32 n = g_video_files_open.load(std::memory_order_relaxed);

		while (n != 0 && !g_video_files_open.compare_exchange_weak(n, n - 1))
		{
		}
	}

	// A movie is playing if the guest decoded video very recently, OR it is
	// holding a video container open. The decode window is generous on purpose:
	// a 30 fps stream is one unit every 33 ms, and a decoder that is briefly
	// starved must not read as "the movie ended".
	inline bool video_playing() noexcept
	{
		return vdec_age_us() < 500'000 || g_video_files_open.load(std::memory_order_relaxed) != 0;
	}
} // namespace thor
