#pragma once

#include "util/atomic.hpp"
#include "util/types.hpp"

#include <cstdlib>
#include <string_view>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace rpcsx::startup_cache_phase
{
	// Emulation identifiers make the hand-off safe across in-process restarts.
	// RSX only waits when an explicit Android experiment enables phase pacing.
	inline atomic_t<u64> spu_preload_started{};
	inline atomic_t<u64> spu_preload_complete{};

	// Keep this control scoped to temporary startup workers. Runtime PPU, SPU,
	// RSX, audio, and render threads retain their ordinary affinity policy.
	inline u64 get_cache_worker_affinity_mask(std::string_view title_id) noexcept
	{
#ifdef __ANDROID__
		if (title_id != "BLUS30161")
		{
			return 0;
		}

		const auto parse_mask = [](const char* value) -> u64
		{
			if (!value || !*value)
			{
				return 0;
			}

			char* end = nullptr;
			const unsigned long long parsed = std::strtoull(value, &end, 0);
			if (end == value || *end || !parsed || parsed > 0xff)
			{
				return 0;
			}

			return static_cast<u64>(parsed);
		};

		char value[PROP_VALUE_MAX]{};
		const int length = __system_property_get("debug.rpcsx.thor.cache_worker_affinity_mask", value);
		if (length > 0)
		{
			return parse_mask(value);
		}

		return parse_mask(std::getenv("RPCSX_THOR_CACHE_WORKER_AFFINITY_MASK"));
#else
		(void)title_id;
		return 0;
#endif
	}
}
