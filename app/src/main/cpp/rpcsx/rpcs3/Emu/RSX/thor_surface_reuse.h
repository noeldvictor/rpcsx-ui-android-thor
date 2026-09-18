#pragma once

// Reuse a discarded render target when a surface split needs a new one.
//
// Port of RPCS3 a65980547 (pull request 19500, Yahfz with kd-11, merged
// 2026-09-16). A surface split happens when a game writes a smaller or offset
// surface into memory that a live render target covers. The split clones a
// render target for each leftover region. Before the change, each clone
// created a new image and the old one went to the discard list. Upstream
// found that the create path is a bottleneck on NVIDIA drivers. Reuse of a
// discarded image with the same size, format, usage and sample count gave
// +20 to +30 percent in Red Dead Redemption, Gran Turismo 5 and the Saints Row
// titles on NVIDIA GPUs, and no change on AMD.
//
// On the Thor the create path is Turnip on Adreno 740. Its cost is not the
// NVIDIA cost, and nobody has measured it. The port is on by default, at the
// owner's decision of 2026-09-17, before any device measurement. The switch is
// the Video setting "Reuse Discarded Render Targets" (Advanced settings in the
// app). It is dynamic, so a change applies at once, without a restart. Two
// counters on the perf_monitor Frames line say whether the path fires at all
// in a scene:
//
//   surf_clone = clones the split path made with no sink (each one creates an
//                image unless reuse serves it)
//   surf_reuse = clones served from the discard list (only with the gate on)
//
// A scene with surf_clone=0 cannot move, and no device time should go to it.
//
// A property overrides the setting, for A/B runs driven by adb:
//
//   debug.rpcsx.thor.rsx_surface_reuse = 0   forces off
//   debug.rpcsx.thor.rsx_surface_reuse = 1   forces on
//   unset                                     follows the setting
//
// The property is read once, on first use. The setting is read on each call.

#include "Emu/system_config.h"

#include <cstdlib>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace thor {
inline bool rsx_surface_reuse() {
  // -1: no override, follow the setting. 0: forced off. 1: forced on.
  static const int override_value = []() -> int {
#if defined(__ANDROID__)
    char value[PROP_VALUE_MAX]{};
    const int length =
        __system_property_get("debug.rpcsx.thor.rsx_surface_reuse", value);

    const char *v =
        length > 0 ? value : std::getenv("RPCSX_THOR_RSX_SURFACE_REUSE");
#else
    const char *v = std::getenv("RPCSX_THOR_RSX_SURFACE_REUSE");
#endif
    if (!v || !v[0]) {
      return -1;
    }

    return (v[0] == '0' || v[0] == 'n' || v[0] == 'N' || v[0] == 'f' ||
            v[0] == 'F')
               ? 0
               : 1;
  }();

  if (override_value >= 0) {
    return override_value != 0;
  }

  return g_cfg.video.reuse_discarded_render_targets.get();
}
} // namespace thor
