# Thor bounded scene capture

Date: 2026-07-17

Status: host-proven safety harness; no Thor runtime claim.

## Problem

`eternal_sonata_speed_sprint.ps1` previously ran Perfetto synchronously for the
whole capture interval. While that command was blocked, the harness did not
poll battery temperature, verify that the RPCSX process had not restarted, or
scan the guest log for fatal VM/Vulkan failures. A successful capture also left
RPCSX running, which could keep heating the Thor after the evidence was saved.

## Change

- Cap `AndroidSceneSeconds` at 30 seconds; the default remains 20 seconds.
- Poll every 5 seconds by default, configurable from 1 through 10 seconds.
- Use the same conservative 39.0 C battery ceiling as the input-route harness.
- Fail closed when battery temperature cannot be read.
- Pin the initial RPCSX PID and abort if it disappears or changes.
- Scan the latest 300 guest-log lines for shared fatal VM/Vulkan/native-crash
  patterns and unknown guest draw commands.
- Run screenrecord and Perfetto asynchronously so guards execute during them.
- Give every guard and force-stop ADB command a three-second timeout.
- Force-stop RPCSX on any guard failure.
- Retry a failed force-stop once and surface failure instead of reporting success.
- Force-stop RPCSX after a successful capture by default. The explicit
  `KeepAndroidRunningAfterCapture` switch is required to retain the old behavior.
- Forward the scene thermal ceiling into `thor_input_macro.ps1` for routed runs.
- Centralize battery-temperature parsing and guest-health matching in
  `thor_debug_common.ps1` so route and capture behavior stay aligned.

## Host-only verification

- PowerShell parser: clean for `thor_debug_common.ps1`,
  `thor_input_macro.ps1`, and `eternal_sonata_speed_sprint.ps1`.
- Mock battery input `temperature: 387`: parsed as 38.7 C.
- Missing battery input: parsed as unknown/null.
- Mock `VK_ERROR_DEVICE_LOST`: detected as fatal.
- Mock unknown draw command: detected as a correctness failure.
- Benign RSX/SPU input: no fatal match.
- Full fake-ADB 35.0 C capture completed and issued the default force-stop.
- Full fake-ADB 39.0 C capture failed at the thermal gate and issued force-stop.
- Full fake-ADB stop-failure test confirmed both retry and surfaced failure.
- Parameter binding rejects:
  - `AndroidSceneSeconds=31`
  - `AndroidThermalPollSeconds=0`
  - `AndroidMaxBatteryTemperatureC=29`
  - `AndroidRoutePostWaitSeconds=11`
- `git diff --check`: clean.

No real ADB device query, launch, capture, build, or benchmark was performed in
this round. This preserves the user's explicit cool-device constraint.

## Next device proof

Only after the Thor is cool, run one short routed scene at a time. Start with a
15-second field capture and stop. Field, first battle, and in-game menu still
need separate visual, fatal-log, timing, and thermal proof before claiming a
measured speed or stability win.
