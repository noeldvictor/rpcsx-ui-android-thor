#pragma once

#include "util/atomic.hpp"
#include "util/types.hpp"

namespace rpcsx::startup_cache_phase
{
	// Emulation identifiers make the hand-off safe across in-process restarts.
	// RSX only waits when an explicit Android experiment enables phase pacing.
	inline atomic_t<u64> spu_preload_started{};
	inline atomic_t<u64> spu_preload_complete{};
}
