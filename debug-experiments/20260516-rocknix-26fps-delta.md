# Rocknix 26 FPS Delta - Eternal Sonata Field

- Created: 2026-05-16
- Target: explain how AYN Thor Rocknix/RPCS3 ARM can show about 26 FPS at 720p
  in the Eternal Sonata field while the Android RPCSX/RPCS3 fork is around
  16-21 FPS.
- Local Android snapshot:
  `debug-captures/rocknix-delta-current-android/`
- Rocknix package snapshot:
  `debug-captures/external/rocknix-distribution/`

## Current Gap

Recent Android field captures:

| Path | FPS samples | Average |
| --- | ---: | ---: |
| Stock quiet field | `16.36`, `13.89`, `17.95` | `16.07` |
| Reduced-loop u4 quiet field | `18.22`, `19.49`, `19.27` | `18.99` |
| Rocknix-correct mirror, stock Qualcomm | `18.49` | `18.49` |
| Rocknix-fast mirror, stock Qualcomm, WCB off | `19.17` | `19.17` |
| Rocknix-correct mirror, Android Turnip A7xx | `12.37` | `12.37` |
| Debug native core, 720p/u4 moving field | `13.55`, `13.67`, `13.27` | `13.50` |
| RelWithDebInfo native core, 720p/u4 short moving field | `19.68`, `28.08`, `27.35` | `25.04` |
| RelWithDebInfo native core, first battle prompt | `30.00`, `30.00` | `30.00` |
| Rocknix AYN Thor video target at 720p | about `26` | `26.00` |

Rocknix target is no longer explained by a mysterious driver-only gap. The
largest delta was self-inflicted: the dev-core hot-swap workflow was pushing
`CMAKE_BUILD_TYPE=Debug` Android native cores. Those compile commands had `-g`
and `-fno-limit-debug-info` but no `-O2`/`-DNDEBUG`. A RelWithDebInfo dev core
with `-O2 -g -DNDEBUG -flto=thin` immediately moved the same 720p/u4/WCB-on
profile from about `13.5 FPS` while moving to Rocknix-class `27-28 FPS` in the
open field, while the most occlusion-heavy tree camera still dipped to about
`19.7 FPS`. This does not finish the 30-FPS-minimum goal, but it removes the
fake 2x gap and makes remaining work a real hot-path problem again.

## Rocknix Reference

Rocknix `next` at local checkout commit `6544ff3` packages RPCS3 standalone as:

- package: `rpcs3-sa`
- upstream package site: `https://github.com/RPCS3/rpcs3-binaries-linux-arm64`
- build version: `d773a3f94e02f1ff66879899232d75f45e2bf17e`
- release label: `0.0.40-19291-d773a3f9`
- app image: `rpcs3-v0.0.40-19291-d773a3f9_linux_aarch64.AppImage`

Rocknix's AYN Thor SM8550 device page identifies the stack as mainline Linux
with Freedreno/OpenGL and Turnip/Vulkan on Snapdragon 8 Gen 2. Its RPCS3 package
uses the native Linux ARM64 AppImage rather than the Android RPCSX app shell.

Sources:

- Rocknix Thor SM8550 page: https://rocknix.org/devices/ayn/thor-sm8550/
- Rocknix PS3 system page: https://rocknix.org/systems/ps3/
- Rocknix package file:
  https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/packages/emulators/standalone/rpcs3-sa/package.mk
- RPCS3 ARM64 announcement:
  https://rpcs3.net/blog/2024/12/09/introducing-rpcs3-for-arm64/

## Highest-Probability Deltas

### 0. Android Dev-Core Build Type Was The Huge Miss

Status: `confirmed-major-win`.

The speed sprint had been hot-swapping Debug native cores:

- Script default before fix: `tools/build_push_thor_core.ps1` used
  `:app:buildCMakeDebug[arm64-v8a]`.
- Active slow core path:
  `app\build\intermediates\cxx\Debug\2g1k4s2o\obj\arm64-v8a\librpcsx-android.so`.
- CMake cache: `CMAKE_BUILD_TYPE=Debug`.
- Representative SPU/RSX compile flags: `-g`, `-fno-limit-debug-info`,
  `_DEBUG`, `-flto=thin`, but no `-O2`/`-O3`/`DNDEBUG`.

Optimized replacement:

- Build command:
  `.\tools\build_push_thor_core.ps1 -Label relwithdebinfo-speed-core -GradleTask ':app:buildCMakeRelWithDebInfo[arm64-v8a]' -NoFallbackBuild -NoStream`
- Active RelWithDebInfo SHA:
  `BFC15D139DFA798D8FA7C4331DF1A32A14BFE3F863D3F177BCA240E3E3E40AC7`.
- Active core source:
  `app\build\intermediates\cxx\RelWithDebInfo\724a6w64\obj\arm64-v8a\librpcsx-android.so`.
- Representative compile flags:
  `-O2 -g -DNDEBUG -flto=thin`.

Measured effect on the same 720p Rocknix-correct/u4/WCB-on profile:

| Build | Capture | FPS proof | Notes |
| --- | --- | ---: | --- |
| Debug native | `debug-captures/android-speed-sprint/20260517-131902-es-u4-720correct-moving-baseline-live-scene/scene.png` | `13.27` | moving field, `rsx::thread` near a full core, GPU about 42% busy |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-135130-thor-input-eternal-sonata-field-route/02-field-move.png` | `29.14` | route field, shader compile overlay visible |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-thor-input-custom/01-moving-left-3s.png` | `19.68` | worst short moving sample, tree/occlusion-heavy camera |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-thor-input-custom/02-field-after-short-move.png` | `28.08` | same route after short movement, visually correct field |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-es-rel-u4-720correct-moving-short-live-scene/scene.png` | `27.35` | same field, GPU at 680 MHz and about 78% busy |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-135651-thor-input-custom/02-moving-left-end.png` | `30.00` | movement macro reached first battle tutorial prompt |

Workflow fix: `tools/build_push_thor_core.ps1` now defaults to the RelWithDebInfo
task and requires `-AllowDebugFallback` before it will silently fall back to a
Debug native build. Future FPS comparisons from Debug cores must be labeled
`debug-native-core` and ignored for Rocknix-delta conclusions.

### 1. Our Android Effective Config Is Not Rocknix-Like

The pulled Android global config currently has:

- `Renderer: Vulkan`
- `Resolution: 1280x720`
- `Resolution Scale: 100`
- `Shader Precision: High`
- `Write Color Buffers: false`
- `Relaxed ZCULL Sync: false`
- `Accurate ZCULL stats: true`
- `Thread Scheduler Mode: RPCS3 Scheduler`
- `SPU Reservation Busy Waiting Percentage: 100`
- `LLVM Precompilation: false`
- `Max LLVM Compile Threads: 2`
- `Use LLVM CPU: cortex-a78`

The active `config_BLUS30161.yml` custom override then changes Eternal Sonata to:

- `Thread Scheduler Mode: Operating System`
- `SPU Reservation Busy Waiting Percentage: 0`
- `SPU Reservation Busy Waiting Enabled: false`
- `Frame limit: 30`
- `Write Color Buffers: true`
- `Accurate ZCULL stats: false`
- `Relaxed ZCULL Sync: false`
- `Shader Compiler Threads: 2`

So our effective game config is still likely:

- Vulkan
- `1280x720`
- `Resolution Scale: 100`
- shader precision `High`
- WCB `true`
- relaxed ZCULL `false`
- 3 GB VRAM cap

Rocknix's SM8550 preset starts much lighter by default:

- `Resolution: 720x480`
- `Resolution Scale: 50`
- `Shader Precision: Low`
- `Frame limit: 30`
- `Write Color Buffers: true` in base config, but the launcher overwrites this
  to `false` unless the frontend setting is explicitly `true`
- `Relaxed ZCULL Sync: true`
- `Accurate ZCULL stats: false`
- `Driver Wake-Up Delay: 1`
- VRAM allocation limit `65536`

Important correction: the video target is 720p, not the low-resolution preset
default. The low-res mirror was still useful as a diagnostic: if Android could
not approach 26 FPS even at 480p/scale-50, then the main gap is not pixel fill.

That diagnostic was tested and was not enough. A Rocknix-style Android mirror
with `720x480`, `Resolution Scale: 50`, `Shader Precision: Low`,
`Relaxed ZCULL Sync: true`, frame limit `30`, and u4 reduced-loop logging
still landed at about `18.49 FPS` with WCB on and about `19.17 FPS` with WCB
off. That strongly suggests the field scene is not dominated by pixel fill,
resolution scale, or shader precision on Android.

### 2. Write Color Buffers May Be The Speed/Correctness Split

Our current profile forces `Write Color Buffers: true` because earlier local
notes treated it as DB-critical for black texture/black spot correctness.
Rocknix's launcher can silently flip it off if the frontend option is unset or
set to off.

Tested matched field captures:

- `rocknix-fast`: WCB off, low shader precision, relaxed ZCULL, 480p/50 scale.
  Result: about `19.17 FPS`.
- `rocknix-correct`: WCB on, same low-res/low-precision baseline.
  Result: about `18.49 FPS`.

WCB off is only a small diagnostic uplift, not the missing 26 FPS path. Keep
WCB on for correctness-locked work unless a specific visual A/B proves a title
scene does not need it.

### 3. Turnip/Mainline Linux May Be Doing Real Work

Rocknix runs Turnip in a mainline Linux environment. Android stock Qualcomm
Vulkan is a different driver path with Android window/surface integration,
memory allocation behavior, sync primitives, and thermal policy. We also have
Thor-compatible Turnip driver folders on Android, but they are not equivalent to
Rocknix's system Mesa stack.

After config matching, Android Turnip A7xx was worse:

- stock Qualcomm Android driver, Rocknix-correct mirror: about `18.49 FPS`
- installed Android Turnip A7xx driver, Rocknix-correct mirror: about
  `12.37 FPS`

This does not disprove Rocknix's system Mesa/Turnip advantage. It says the
Android custom-driver drop-in is not equivalent to Rocknix's mainline Linux
graphics stack, memory path, windowing path, or scheduler environment. The next
driver comparison needs Rocknix-side logs or a direct Rocknix run, not just
another Android driver toggle.

### 4. Native RPCS3 Linux ARM64 vs Android RPCSX Fork

Rocknix's package uses the official RPCS3 Linux ARM64 AppImage around commit
`d773a3f9`. The Android app uses a vendored RPCSX/RPCS3-derived core with many
local Thor imports plus Android shell/JNI/lifecycle pieces.

Important nuance: the upstream `d773a3f9` SPU LLVM still has the same generic
dynamic `MFC_Cmd` fallback warning path. That means Rocknix probably is not
winning because upstream magically optimized the exact `0x25cc`/`0x451c`
Eternal Sonata MFC fallback. The bigger gaps are more likely config, driver, OS
scheduling, and ARM64/Linux runtime behavior.

Still worth comparing:

- AArch64 LLVM target attrs actually active on both stacks
- SPU block/reduced-loop compiler behavior
- page size / reservation notifier behavior
- RSX/Vulkan memory and barrier behavior
- log/overlay overhead

### 5. Scheduler, Governor, And Process Shape

Rocknix launches standalone RPCS3 under its emulation-focused environment. The
launcher can also set an `EMUPERF` wrapper from frontend "cores" settings. Our
Android build runs through an app process, Java/Kotlin UI, Android Surface,
Android thermal policy, app sandbox, and optional dev-core override.

The current Android global config says `RPCS3 Scheduler`, but the Eternal Sonata
custom profile overrides back to `Operating System`. Earlier Android tests found
RPCS3 scheduler variants could crawl at about 2 FPS in a non-matched route, so
do not blindly turn it back on. The better comparison is host state:

- CPU frequencies and governor while scene is active
- per-thread core placement for PPU/SPU/RSX
- thermal throttling status
- background Android services
- SurfaceFlinger/compositor overhead

## Immediate Experiment Matrix

Run each cell as field first, then battle/menu only if field is visually sane.

| ID | Config | Driver | Core props | Expected use |
| --- | --- | --- | --- | --- |
| `android-current-u4` | current NeutralCore | stock Qualcomm | `ReducedLoopEmitU4Quiet` | baseline around 19 FPS |
| `rocknix-720-correct-stock` | 720p, scale 100, low shader, WCB on, relaxed ZCULL | stock Qualcomm | `ReducedLoopEmitU4Quiet` | direct Android-vs-Rocknix-video comparison |
| `rocknix-720-fast-stock` | same but WCB off | stock Qualcomm | `ReducedLoopEmitU4Quiet` | 720p WCB diagnostic only |
| `rocknix-fast-stock` | 480p, scale 50, low shader, WCB off, relaxed ZCULL | stock Qualcomm | `ReducedLoopEmitU4Quiet` | isolate config ceiling |
| `rocknix-correct-stock` | same but WCB on | stock Qualcomm | `ReducedLoopEmitU4Quiet` | correctness-locked config test |
| `rocknix-fast-turnip` | same as fast | Android Turnip A7xx | `ReducedLoopEmitU4Quiet` | isolate Android driver delta |
| `rocknix-correct-turnip` | same as correct | Android Turnip A7xx | `ReducedLoopEmitU4Quiet` | closest Android analog to Rocknix |

Completed field results:

| ID | Capture | FPS overlay | Decision |
| --- | --- | ---: | --- |
| `rocknix-correct-stock` | `debug-captures/android-speed-sprint/20260516-220639-es-rocknixcorrect-u4-field-rsxfenceoff-scene/scene.png` | `18.49` | valid config mirror, not enough |
| `rocknix-fast-stock` | `debug-captures/android-speed-sprint/20260516-221137-es-rocknixfast-u4-field-wcboff-scene/scene.png` | `19.17` | small WCB-off uplift, not correctness win |
| `rocknix-correct-turnip` | `debug-captures/android-speed-sprint/20260516-222236-es-rocknixcorrect-u4-turnipA7-field-scene/scene.png` | `12.37` | Android Turnip A7xx path is worse |
| `rocknix-correct-stock-runtime` | `debug-captures/android-speed-sprint/20260516-223650-es-rocknixcorrect-u4-field-runtime-placement-live-scene/scene.png` | `20.35` | later live sample; CPU maxed, GPU not saturated |
| `rocknix-correct-stock-allthreads-ff` | `debug-captures/android-speed-sprint/20260516-223925-es-rocknixcorrect-u4-field-allthreads-affinity-ff-live-scene/scene.png` | `21.40` | small live affinity bump; not enough |
| `rocknix-correct-stock-rsx7` | `debug-captures/android-speed-sprint/20260516-224100-es-rocknixcorrect-u4-field-affinity-rsx7-spu0-6-ppu3-4-scene/scene.png` | `19.01` | RSX-isolated map got worse and scene was no longer identical |

One earlier `rocknix-correct` capture around `18.30 FPS` is marked invalid for
comparison because a logging-tool bug had accidentally left
`debug.rpcsx.thor.rsx_dma_fence=all` active. `tools/set_thor_logging.ps1` now
resets the RSX DMA fence property to `off` for every non-`RsxDmaHostFence`
logging mode.

Runtime placement note:

- Clean live Rocknix-correct/u4 sample showed process affinity `f8` (`3-7`),
  CPU3-6 at `2707200`, CPU7 at `3187200`, `rsx::thread` around one full core,
  five active SPUs around half a core each, and KGSL `gpubusy` about one-third
  busy in the sampled window.
- Temporarily applying `ff` to every live thread with `run-as taskset` moved the
  overlay from about `20.35` to about `21.40 FPS`, so core placement is a real
  but small lever.
- Isolating `rsx::thread`/RSX workers on CPU7, PPU on CPU3-4, and SPUs on
  CPU0-6 got worse in the sampled field. Do not promote that layout.
- Repeatable live-affinity tooling now lives at
  `tools/set_thor_runtime_affinity.ps1`.

Acceptance:

- Same field checkpoint.
- FPS overlay proof.
- Screenshot/video proof.
- Note black spots, texture holes, flicker, menu corruption.
- If WCB off is faster but visually broken, do not count it as a win.
- Because the Rocknix target is 720p, low-res/low-precision wins are diagnostic
  only. A real match needs the 720p profile unless it is explicitly labeled as
  a lower-quality compromise.

## Current Bet

Updated stack ranking after the RelWithDebInfo correction:

1. Android native build type was the major fake delta. Debug native cores are
   not valid FPS evidence.
2. Remaining 30-FPS-minimum gap is a real hot-path problem in the tree-heavy
   moving field view: RSX thread, SPU load, GPU busy, and camera/occlusion
   rendering all matter now.
3. Standalone RPCS3 Linux/Rocknix process shape, governor, and system Turnip
   stack may still explain smaller residual differences.
4. Actual emulator-core algorithm delta in the hot SPU/MFC or RSX FIFO path.
5. Resolution/precision/WCB/ZCULL mismatch.

The fastest path to Rocknix-class FPS was the optimized native core. The next
path is no longer another broad settings sweep; it is a correctness-locked pass
on the residual dips: tree-heavy moving field, first battle interaction after
the tutorial prompt, and in-game menu. Each new `AndroidScene` /
`AndroidRouteScene` capture still needs CPU/GPU frequency and thread-affinity
snapshots so we can see whether the optimized core is CPU-bound, GPU-bound, or
driver-stalled in the exact bad camera angle.

Immediate correction from the user: treat the Rocknix result as a real 720p AYN
Thor target, not a 480p preset result. Added explicit `Rocknix720Correct` and
`Rocknix720Fast` push-profile modes so future Android comparisons can target
the video conditions directly.
