# 2026-07-19 Thor SPU-cap No-launch Install

## Result

- Classification: exact APK installed, emulator not launched.
- Installed APK SHA-256:
  `5C3911D0E8C5B9EC20261266647B93685984EFB7C799D0E6F32334CEFD682CC6`.
- Host and on-device `base.apk` hashes match exactly.
- RPCSX PID was absent before and after installation.
- No activity start, debug boot, monkey command, screenshot, or game launch ran.
- This round grants installation identity only, not speed or thermal credit.

## Strict Cool Gate

Capture:

`debug-captures/android-speed-sprint/20260719-181421-thor-input-custom`

Required metadata:

- device serial: `c3ca0370`;
- package: `net.rpcsx.easy`;
- `BootGame: False`;
- `ForceStop: True`;
- maximum launch silicon: `35 C`;
- three samples, two seconds apart;
- maximum allowed rise: `1 C`.

Observed:

| Sample | Silicon | Battery | Skin |
|---:|---:|---:|---:|
| 1 | `31.7 C` | `22.0 C` | `30.0 C` |
| 2 | `31.5 C` | `22.0 C` | `30.0 C` |
| 3 | `31.1 C` | `22.0 C` | `30.0 C` |

- maximum silicon: `31.7 C`;
- silicon rise: `-0.6 C`;
- gate result: pass.

The installer validated the gate at age `0.58` minutes, below its 15-minute
staleness limit.

## Install Evidence

Capture:

`debug-captures/android-speed-sprint/20260719-181508-spu-cap-thortest-apk-install`

Verified:

- host APK size: `72,840,516` bytes;
- expected/host SHA-256: `5C3911D0...682CC6`;
- installed `base.apk` SHA-256: `5C3911D0...682CC6`;
- `adb install -r` result: success;
- PID before: absent;
- PID after: absent;
- emulator launch: no;
- installer failure: none.

The post-install property snapshot showed neutral controls:

- RSX workers/limit/budget: `0/0/0`;
- SPU limit/budget: `0/0`;
- SPU native object cache: off;
- cache-worker affinity: `0`;
- Vulkan cache: on;
- Vulkan cache-hit-only preload: off;
- PPU interpreter, dispatch probe, async draw: off.

Post-install temperature:

- silicon: `34.5 C`;
- battery: `22.0 C`;
- skin: `30.0 C`.

## Boundary

Stop this device round after installation. The APK is installed but has no
runtime proof. Do not poll, launch, or retry now. After a separate independent
cooling interval, one `ThorCoolTitle` run may launch only if its three-sample
preflight remains below `35 C` with at most `1 C` rise. It must use the exact
`256/64` cache bounds, two RSX workers, three SPU affinity-matched workers,
`0x07` mask, Vulkan hit-only preload, phase pacing, quiet logs, self-stop, and
the `68/72 C` early/hard guard. Any thermal or activation failure ends that
future round without retry.
