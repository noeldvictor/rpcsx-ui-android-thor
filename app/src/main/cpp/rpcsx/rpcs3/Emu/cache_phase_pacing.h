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

	// Shader-cache preload can encounter the same malformed instruction many
	// times while walking cached programs. Keep one representative diagnostic
	// of each kind per worker and summarize the duplicates after the load phase.
	// Outside the explicitly scoped preload workers every diagnostic is emitted.
	enum class rsx_preload_diagnostic : u8
	{
		bad_scale,
		unexpected_precision,
		nested_indexed_loop,
		indexed_control_override,
		bad_source_register,
		unknown_source_type,
		break_outside_loop,
		unimplemented_call,
		unknown_instruction,
		hanging_block,
	};

#ifdef __ANDROID__
	inline thread_local bool rsx_preload_diagnostic_summary_active = false;
	inline thread_local u32 rsx_preload_diagnostic_seen_mask = 0;
	inline thread_local u32 rsx_preload_diagnostics_suppressed = 0;

	inline void begin_rsx_preload_diagnostic_summary() noexcept
	{
		rsx_preload_diagnostic_seen_mask = 0;
		rsx_preload_diagnostics_suppressed = 0;
		rsx_preload_diagnostic_summary_active = true;
	}

	inline u32 end_rsx_preload_diagnostic_summary() noexcept
	{
		const u32 result = rsx_preload_diagnostics_suppressed;
		rsx_preload_diagnostic_summary_active = false;
		rsx_preload_diagnostic_seen_mask = 0;
		rsx_preload_diagnostics_suppressed = 0;
		return result;
	}

	inline bool should_emit_rsx_preload_diagnostic(rsx_preload_diagnostic diagnostic) noexcept
	{
		if (!rsx_preload_diagnostic_summary_active)
		{
			return true;
		}

		const u32 bit = 1u << static_cast<u8>(diagnostic);
		if (!(rsx_preload_diagnostic_seen_mask & bit))
		{
			rsx_preload_diagnostic_seen_mask |= bit;
			return true;
		}

		++rsx_preload_diagnostics_suppressed;
		return false;
	}
#else
	inline void begin_rsx_preload_diagnostic_summary() noexcept
	{
	}

	inline u32 end_rsx_preload_diagnostic_summary() noexcept
	{
		return 0;
	}

	inline bool should_emit_rsx_preload_diagnostic(rsx_preload_diagnostic) noexcept
	{
		return true;
	}
#endif

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
