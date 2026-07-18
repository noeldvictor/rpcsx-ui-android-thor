# 2026-07-18 Thor Startup Cache-Worker Affinity

## Result

- Classification: host-verified, default-off lower-power candidate.
- Target: Eternal Sonata `BLUS30161` on AYN Thor Max / Snapdragon 8 Gen 2.
- Temporary RSX and SPU startup cache workers can be restricted to an explicit
  Android CPU mask. Mask `0x07` selects the Thor's three Cortex-A510
  efficiency cores.
- Runtime PPU, SPU, RSX, audio, render, and guest threads are unchanged.
- No ADB query, install, launch, or temperature read ran in this round. The
  candidate has no device speed, temperature, FPS, flicker, gameplay, or
  stability credit.

## Why this lane

The latest bounded startup evidence reached `69.1 C` about `3.275 s` after
the process appeared, before the title screen. Its matched log put Vulkan cache
creation, two RSX cache workers, PPU object loading, and two SPU LLVM workers
inside the same first three seconds. The Thor topology already captured in this
repo is:

| CPUs | Core family | Mask |
| --- | --- | --- |
| 0-2 | Cortex-A510 efficiency | `0x07` |
| 3-4 | Cortex-A715 performance | `0x18` |
| 5-6 | Cortex-A710 performance | `0x60` |
| 7 | Cortex-X3 prime | `0x80` |

The current process mask is `0xff`, which was beneficial during gameplay but
also lets temporary compiler workers land on the hottest cores. This candidate
changes only those disposable startup workers.

Android Thermal Headroom was not used as the acute-startup control. The
official NDK documentation says it tracks slow-moving sensors such as skin
temperature, can return `NaN`, and may need multiple samples before a forecast
is available. That is useful for sustained gameplay adaptation but too delayed
to be the sole guard for the observed three-second silicon spike:

- <https://developer.android.com/ndk/reference/group/thermal>
- <https://developer.android.com/games/optimize/adpf/thermal>

The external multi-sensor thermal guard therefore remains authoritative.

## Official-upstream audit

The local official RPCS3 reference was current through
`a7d90852dd02efcceb539968667201dbc9799cb0` on 2026-07-18. All current
Thor-relevant ARM64 SPU/PPU and RSX wait/pipeline improvements found in that
audit were already adapted.

The remaining arithmetic candidate,
`33123bff044396473cedd41b6110231a5fda9da5` (`FRSQEST` exponent arithmetic),
was rejected for this title: the saved clean BLUS30161 first-battle atlas has
zero `FRSQEST` or `RSQRTE` rows across 106 SPU disassembly windows. It would
remove a lookup but does not address the captured workload.

## Implementation

Shared parser:

- property: `debug.rpcsx.thor.cache_worker_affinity_mask`
- environment fallback: `RPCSX_THOR_CACHE_WORKER_AFFINITY_MASK`
- accepts decimal or `0x` notation;
- `0`, malformed values, and values above `0xff` fail closed to default
  scheduling;
- returns zero outside Android and outside `BLUS30161`.

RSX cache:

- default-off one-worker execution retains the original inline/direct path;
- with a nonzero mask, even a one-worker request uses a temporary named worker,
  so the calling emulation/UI thread is never pinned;
- every RSX load/compile worker applies the mask before cache work;
- one activation row per phase records requested and effective masks and warns
  if the kernel did not apply the exact request.

SPU cache:

- every temporary `SPU Worker` applies the mask after low-priority setup and
  before LLVM compiler initialization, analysis, or compilation;
- one activation row records requested/effective masks;
- runtime-miss compilers and live SPU threads are untouched.

The Android route accepts `CacheWorkerAffinityMask=0..255`, captures the
effective property, and resets it on prelaunch, success, and failure. The
Eternal Sonata wrapper forwards
`AndroidCacheWorkerAffinityMask`. The no-launch installer records the control.

## Correctness and rollback

This changes only Linux scheduler eligibility for temporary host threads.
Compile inputs, LLVM features, guest program identity, SPU cache identity,
Vulkan state, renderer semantics, and generated-code correctness are unchanged.

Rollback is `CacheWorkerAffinityMask=0` or removing the property. The default
path remains off.

## Host verification

Passed:

- all 26 `tools/test_thor_*.ps1` contracts;
- focused affinity, startup compile-budget, and cache phase-pacing contracts;
- PowerShell AST parsing for route, wrapper, installer, and focused test;
- `git diff --check`;
- optimized ARM64-only ThorTest build with bundled native core:
  `BUILD SUCCESSFUL` in `1m 39s`;
- exact APK ABI and optimized-variant contracts;
- exact packaged-core identity;
- packaged binary strings for property, environment fallback, and both
  activation logs;
- export surface: 34 defined dynamic symbols, 587 explicit relocations,
  391 jump slots, and 44,245 encoded relocation bytes.

Only pre-existing enum/designator deprecation warnings were emitted.

## Exact host-only artifact

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,583,146` bytes
- APK SHA-256:
  `990701CE58AB9B7153B75BF074590778B3A6CD5EEA8D4A81AB6726152C93743B`
- merged ARM64 core size: `1,305,852,368` bytes
- merged ARM64 core SHA-256:
  `928E7036D23FC2E351D54A431542FFA019BB77A1F3DB9F5C8AB64B275A8AC5C5`
- stripped/packaged ARM64 core size: `62,863,080` bytes
- stripped/packaged ARM64 core SHA-256:
  `57103C41E28F8EF4C68B5BAF9B85EC7CAFB50196F7E418F2D65E4C78B41E3131`

The APK entry and stripped core match exactly.

## Future device gate

Do not test while the Thor is warm. A later round may spend only a strict
no-launch install gate on this exact APK. A different independently cool round
may spend one short guarded startup proof with:

- cache-worker affinity mask `7`;
- RSX workers auto/two;
- RSX preload limit `256`;
- SPU preload limit `64`;
- persistent Vulkan cache on;
- external multi-sensor early-stop guard unchanged.

Record requested/effective RSX-load, RSX-compile, and SPU masks, process-to-title
time, temperature slope, and whether the guard trips. If it only delays the same
thermal trip, reject it. Do not grant runtime credit from install or activation
logs alone.
