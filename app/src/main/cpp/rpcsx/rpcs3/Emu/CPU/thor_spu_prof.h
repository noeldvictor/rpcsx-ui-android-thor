#pragma once

// Runtime override for the SPU profiler, so it can be armed without editing the
// per-title config.
//
// WHY A PROPERTY. The debug-boot path applies a managed profile that REWRITES
// the per-title yml, so a key added between runs does not survive the boot.
// A property is read after the profile is applied.
//
// WHY THE PROFILER IS WORTH ARMING HERE. A per-thread census of 3D combat put
// SPU0 at about twice the load of every other SPU, and every /diag sample shows
// SPU0 at pc=0x0f3c4 - the counted delay loop in the SPURS kernel. CPU time is
// not the same as useful work, and this profiler reports per thread "% idle" and
// "% reservation", which separates the two.
//
//   debug.rpcsx.thor.spu_prof = 1
//
// Unset means "use the config", so a device with it unset is unchanged.
//
// NOTE: this changes SPU CODEGEN - the recompiler emits sampling hooks - so the
// SPU cache is invalidated and the first boot after arming it recompiles.

#include "util/types.hpp"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#include <cstdlib>

namespace thor
{
	inline bool spu_prof_override(bool cfg_value) noexcept
	{
		static const int s_override = []() -> int
		{
#if defined(__ANDROID__)
			char value[PROP_VALUE_MAX]{};

			if (__system_property_get("debug.rpcsx.thor.spu_prof", value) > 0 && value[0])
			{
				return (value[0] == '0' || value[0] == 'f' || value[0] == 'n') ? 0 : 1;
			}
#endif
			return -1;
		}();

		return s_override < 0 ? cfg_value : s_override != 0;
	}
} // namespace thor
