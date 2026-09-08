#pragma once

// Per-flip frame INTERVALS for the Transformers frame-pacing question.
//
// WHY. Restored 3D combat in BLUS30357 averages about 20 FPS against the
// title's own 30 FPS cap. An average cannot say which of two very different
// situations produced it:
//
//   * every frame takes ~50 ms         -> the title is locked to every third
//                                          vblank and misses 33 ms by an
//                                          UNKNOWN margin; a small saving could
//                                          jump it to 30
//   * frames spread from 35 to 70 ms   -> a real throughput gap of ~40%
//
// `dumpsys SurfaceFlinger --latency` cannot answer this here: it reported a
// frozen layer for a session whose own overlay read 25.74 FPS, and its ring is
// a fixed 126 entries. So the interval is taken at the emulator's own flip, the
// same event the "Frames:" counter uses.
//
// COST. One atomic exchange, one store and one increment per flip. There is no
// property for it because it changes no behaviour and the frame rate here is
// tens of hertz.
//
// OUTPUT. perf_monitor appends to its existing "Frames:" line every report:
//
//   FT(ms) p50=50.1 p95=50.4 p99=66.9 n=201 |<20:0 20-30:0 30-36:3 36-45:2 45-55:190 55-70:6 >70:0
//
// Percentiles and buckets cover the frames since the previous report, so a
// 10 s window at 20 FPS holds about 200 intervals. A gap longer than 5 s is a
// pause or a savestate restore, not a frame, and is not recorded.

#include "util/atomic.hpp"
#include "util/types.hpp"
#include "util/StrFmt.h"

#include <algorithm>
#include <array>
#include <string>

namespace thor::frametime
{
	inline constexpr u32 ring_size = 2048;

	// Bucket upper edges in microseconds. The bucket after the last edge is
	// "longer than 70 ms".
	inline constexpr std::array<u32, 6> bucket_edges_us{20000, 30000, 36000, 45000, 55000, 70000};

	inline std::array<atomic_t<u32>, ring_size> g_ring{};
	inline std::array<atomic_t<u32>, bucket_edges_us.size() + 1> g_buckets{};
	inline atomic_t<u32> g_written{0};
	inline atomic_t<u64> g_last_flip_us{0};
	inline atomic_t<u64> g_total{0};

	inline void on_flip(u64 now_us) noexcept
	{
		const u64 last = g_last_flip_us.exchange(now_us);

		if (!last || now_us <= last)
		{
			return;
		}

		const u64 delta = now_us - last;

		if (delta > 5'000'000)
		{
			// Pause, restore or boot gap. Not a frame.
			return;
		}

		const u32 delta_us = static_cast<u32>(delta);
		const u32 index = g_written++;

		if (index < ring_size)
		{
			g_ring[index].store(delta_us);
		}

		u32 bucket = 0;

		while (bucket < bucket_edges_us.size() && delta_us >= bucket_edges_us[bucket])
		{
			bucket++;
		}

		g_buckets[bucket]++;
		g_total++;
	}

	// Append the distribution since the previous call and reset the window.
	inline void report(std::string& out)
	{
		const u32 written = g_written.load();
		const u32 count = std::min<u32>(written, ring_size);

		if (!count)
		{
			return;
		}

		std::array<u32, ring_size> sorted{};

		for (u32 i = 0; i < count; i++)
		{
			sorted[i] = g_ring[i].load();
		}

		std::sort(sorted.begin(), sorted.begin() + count);

		const auto percentile = [&](u32 p) -> f64
		{
			const u32 at = std::min<u32>(count - 1, (count * p) / 100);
			return sorted[at] / 1000.0;
		};

		std::array<u32, bucket_edges_us.size() + 1> buckets{};

		for (usz i = 0; i < buckets.size(); i++)
		{
			buckets[i] = g_buckets[i].exchange(0);
		}

		// Reset the window. A flip that lands between the load above and this
		// store is counted in neither window, which is acceptable for a
		// diagnostic that reports hundreds of frames per report.
		g_written.store(0);

		fmt::append(out, ", FT(ms) p50=%.1f p95=%.1f p99=%.1f n=%u |<20:%u 20-30:%u 30-36:%u 36-45:%u 45-55:%u 55-70:%u >70:%u",
			percentile(50), percentile(95), percentile(99), count,
			buckets[0], buckets[1], buckets[2], buckets[3], buckets[4], buckets[5], buckets[6]);
	}
} // namespace thor::frametime
