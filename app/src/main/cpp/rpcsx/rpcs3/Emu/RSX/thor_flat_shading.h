#pragma once

// Flat shading, off by default on Thor.
//
// RPCS3 b97f4bd8d makes NV4097_SET_SHADE_MODE reach the shaders. It is correct, and it
// costs something this fork works hard to avoid: the shade mode joins the vertex program
// control word and the pipeline key, so a title that uses both shade modes now compiles two
// variants of each affected program and each affected pipeline. This device is where
// pipeline permutations show as stutter, which is the whole reason the extended dynamic
// state work exists.
//
// It also gives NV4097_SET_SHADE_MODE a dirty signal. That register cost nothing before. A
// title that writes it often now re-evaluates the vertex AND fragment program each time.
//
// So it is a property, and the default keeps the old behaviour exactly. With the gate off
// the control bit is never set, the shaders are byte for byte what they were, and the
// pipeline flag is never raised.
//
//   debug.rpcsx.thor.flat_shading = 1   (default 0)
//
// Turn it on only with an A/B on a scene that repeats. Eternal Sonata regressed from about
// 30 FPS to about 17 FPS on the build that shipped this on by default, and that build also
// carried five other ports, so the attribution is not yet proven.

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

namespace rsx
{
	inline bool thor_flat_shading_enabled()
	{
#ifdef ANDROID
		static const bool value = []()
		{
			char buffer[PROP_VALUE_MAX]{};
			const int length = __system_property_get("debug.rpcsx.thor.flat_shading", buffer);
			return length > 0 && (buffer[0] == '1' || buffer[0] == 'y' || buffer[0] == 'Y' || buffer[0] == 't' || buffer[0] == 'T');
		}();

		return value;
#else
		return true;
#endif
	}
}
