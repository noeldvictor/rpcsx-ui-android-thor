# 2026-07-18 Android ADPF RSX Power Hint

Date: 2026-07-18
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified, default-off power experiment; device-unmeasured

## Result

- Added an Android-only performance-hint session around the real RSX work
  cycle: the first eligible Vulkan draw starts the cycle and
  `VKGSRender::flip` finishes it.
- The normal path is unchanged unless
  `debug.rpcsx.thor.adpf_rsx=on` was present before process start.
- The experiment is also locked to BLUS30161.
- Only positive work windows at or below the 30 ms target are reported.
  Over-budget frames are skipped so this experiment does not ask Android to
  boost an already-struggling frame.
- Missing APIs, manager/session failure, and report failure all fail closed.
  The emulator continues without hints; report failure closes and permanently
  disables the session for that process.
- The optimized ARM64 core and ThorTest APK build, ABI/package checks, export
  checks, and focused source/route contracts pass.
- No ADB query, install, launch, thermal poll, or other Thor action ran. This
  result has no device speed, temperature, FPS, flicker, gameplay, or stability
  credit.

## Research basis

The current official
[Android NDK Performance Hint Manager reference](https://developer.android.com/ndk/reference/group/a-performance-hint)
describes the API as a way to give Android periodic workload targets and
actual cycle durations so the framework can allocate resources more
accurately and reach a steady state under the target. Frame production is its
explicit example.

The implementation follows that contract:

- a long-lived session belongs to the actual RSX thread ID from `gettid()`;
- the cycle spans first draw through the Vulkan flip boundary rather than a
  Java lifecycle callback or a synthetic frame interval;
- `std::chrono::steady_clock` supplies the required monotonic duration;
- the 30 ms target preserves about 3.3 ms of the title's 30 FPS frame budget
  for presentation and other work; and
- Android 15's optional `APerformanceHint_setPreferPowerEfficiency` is used
  when exported by the platform. Android 13/14 retain the basic session path.

This is a steady-state RSX power-allocation experiment. It is not a fix for
the already-measured pre-title compiler heat spike.

## Compatibility and safety

The app minimum remains API 29. The implementation deliberately does not
include or directly import `android/performance_hint.h` API-33 symbols.
Instead it opens process-lifetime `libandroid.so` and resolves:

- `APerformanceHint_getManager`;
- `APerformanceHint_createSession`;
- `APerformanceHint_reportActualWorkDuration`;
- `APerformanceHint_closeSession`; and
- optional `APerformanceHint_setPreferPowerEfficiency`.

An API-29-to-32 device therefore follows the unchanged path even if the
property is accidentally requested. The packaged ARM64 core has no direct
`APerformanceHint_*` symbol imports. It explicitly links `libdl.so` and retains
the existing `libandroid.so` and `liblog.so` dependencies.

The guarded Thor route exposes `AdpfRsx` / `AndroidAdpfRsx`, defaults both to
`off`, records the effective property, and resets it before launch and after
success or failure. Because the native property is cached once, the route's
existing force-stop/set/launch order is required for an opt-in run.

## Source

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/thor_adpf_rsx_hint.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKDraw.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPresent.cpp`
- `app/src/main/cpp/rpcsx/android/CMakeLists.txt`
- `tools/thor_input_macro.ps1`
- `tools/eternal_sonata_speed_sprint.ps1`
- `tools/test_thor_adpf_rsx_hint.ps1`

## Host verification

Passed without contacting Thor:

- `tools/test_thor_adpf_rsx_hint.ps1`;
- `tools/test_thor_thermal_guard.ps1`;
- `tools/test_thor_vulkan_pipeline_cache.ps1`;
- `tools/test_thor_vulkan_preload_cache_hits_only.ps1`;
- PowerShell AST parsing for both route scripts and the new contract;
- `tools/test_thor_optimized_apk_contract.ps1`;
- `tools/test_thor_arm64_apk.ps1` with exact merged-core identity;
- `tools/test_thor_core_export_surface.ps1`: 34 defined dynamic symbols, 587
  explicit relocations, 391 jump slots, and 44,237 encoded relocation bytes;
- `tools/test_thor_single_core_load.ps1`;
- optimized ARM64 RelWithDebInfo native link and
  `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a
  -PbuildBundledRpcsxCore=true`; and
- `git diff --check`.

Binary inspection additionally found the ADPF diagnostic string, required
`libdl.so`, and zero direct `APerformanceHint_*` symbol imports.

## Exact host-only candidate

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,579,450` bytes
- APK SHA-256:
  `84675D0DA1502FDA2ED88F4E81725E4FC0DC797D8DBFD027087EB1910DEEA93E`
- merged ARM64 core size: `1,305,748,704` bytes
- merged ARM64 core SHA-256:
  `691AD1682DB653405D6D42B3CA7D2FA072457E18AB73865ECC34CBFFC3CF066B`
- packaged stripped core size: `62,857,640` bytes
- packaged stripped core SHA-256:
  `775EE0EC6868DEE923A379022164ADD66D29DA4132919897F91A2D46C11364E7`

## Promotion boundary

This candidate is uninstalled and device-unmeasured. The Thor remains stopped.
Do not install or launch it merely to finish this host work round.

If a later independently cool round tests it, use matched ADPF-off/on runs on
the exact APK and identical warm cache/profile. Each run must independently
pass the strict cool preflight and existing early-stop guard. Promotion
requires title, field, and first-battle visual correctness, zero targeted
fatal/unknown-draw rows, matched capped FPS/frame-time evidence, and lower
temperature or reduced temperature rise. A neutral result parks the feature;
any regression keeps it off and removes it from the device lane.

## 2026-07-20 Feedback-contract correction

Status: host-verified diagnostic correction; default-off; device-unmeasured

### Question and primary-source result

Could the API-33 path lower sustained heat without hiding missed frames from
Android's controller?

- Current AOSP guidance creates the session with the target frame period and
  says to report actual work on every cycle / every frame:
  [Performance Hint API](https://source.android.com/docs/core/perf/performance-hint-api).
- The current stable NDK header likewise says the framework compares every
  cycle with the target to reach a steady state below the deadline:
  [AOSP performance_hint.h](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/include/android/performance_hint.h).
- Android 15 adds structured CPU/GPU work durations and explicit
  power-efficient scheduling, but the saved Thor identity is Android 13.
  Those newer controls cannot justify this device experiment.
- The April 2026 FLAME paper shows why asynchronous CPU/GPU coupling makes
  simple static frequency assumptions unreliable and instead evaluates
  deadline-aware feedback. Applying that mechanism here is an inference, not
  emulator proof: complete per-cycle deadline feedback is a sound experiment;
  a hand-authored frequency or boost policy is not:
  [FLAME, arXiv:2604.15357](https://arxiv.org/abs/2604.15357).

The previous implementation contradicted the first two sources by discarding
all cycles longer than its 30 ms target. That removed exactly the deadline-miss
samples the feedback controller needs and biased the stream toward easy
frames. It also asked a 30 FPS title to meet an unnecessarily short target.

### Change

- Use the exact integer 30 FPS period, 33,333,333 ns, as the target.
- Report every positive first-draw-to-flip cycle, including over-target cycles.
- Keep invalid nonpositive samples filtered.
- Emit the single session-activation fact through Android's durable
  Always-level path so a quiet A/B can prove the experiment actually ran.
- Preserve API-29-safe dynamic loading, BLUS30161 gating, failure shutdown,
  route cleanup, and the default-off build gate.

This remains an experiment. On Thor's Android 13, basic ADPF may lower CPU
allocation when there is headroom or raise it after a miss; lower temperature
is plausible but not assumed. Android 15's explicit power-efficiency and
structured GPU-duration modes are deliberately not treated as available.

### Host verification

- tools/test_thor_adpf_rsx_hint.ps1 passes with an explicit rejection of the
  former over-target drop.
- All 62/62 host Thor contracts pass in isolated PowerShell processes.
- PowerShell AST parsing and git diff --check pass.
- The saved optimized ARM64 diagnostic compile database rebuilt
  VKDraw.cpp and VKPresent.cpp successfully with
  RPCSX_THOR_ADPF_RSX_HINT=1.
- LLVM IR contains target 33333333, the durable every-cycle activation row,
  the dynamically resolved report symbol, a single positive-duration check,
  and the report call. There is no upper-target comparison in finish().
- The same two translation units rebuild successfully with the normal
  ThorTest flags; llvm-nm finds ADPF symbols in diagnostic objects and none
  in normal objects.

No APK was assembled, installed, or pinned. No ADB query or Thor workload ran.
The exact installed candidate remains frozen for its separately cool title
proof. This change receives no FPS, temperature, flicker, gameplay, stability,
or speed-win credit.

### Decision

Keep the normal Android gate off. After the currently installed candidate
finishes its independent proof, a future diagnostic APK may compare ADPF off
and on with the same artifact, warm caches, scene, frame cap, visual gates, and
thermal guard. Promote only a matched frame-time result with lower thermal
rise; park neutral behavior and reject any throughput or visual regression.

## 2026-07-22 Primary-source refresh and experiment ranking

Status: host-research / no source or device change

Current Android guidance still makes the existing default-off RSX experiment
the narrowest plausible sustained-thermal A/B after the frozen candidate has a
valid warm-cache baseline:

- The current NDK Performance Hint reference defines sessions for periodic
  workloads such as frame production and requires actual duration every cycle
  against a target duration. The existing first-draw-to-flip, 33,333,333 ns,
  every-positive-cycle implementation matches that API-33 contract:
  https://developer.android.com/ndk/reference/group/a-performance-hint
- Android's Thermal API guidance recommends adapting worker count, affinity,
  fidelity, or frame rate using thermal headroom, but warns that headroom must
  not be queried more often than once per 10 seconds and may return NaN. Any
  future in-process headroom probe must therefore be read-only, single-threaded,
  and no faster than 10 seconds before it can drive policy:
  https://developer.android.com/games/optimize/adpf/thermal
- Explicit `setPreferPowerEfficiency`, structured CPU/GPU work duration,
  graphics-pipeline sessions, and surface binding are newer feature-gated APIs.
  The saved Thor is Android 13, so they cannot be credited or required for the
  first A/B. Basic `reportActualWorkDuration` remains the applicable path.
- Android fixed-performance mode is a benchmark-variance tool, not a thermal
  solution; official guidance says it can still overheat. Keep it off for the
  user's normal and sustained-temperature runs:
  https://developer.android.com/games/optimize/adpf/fixed-performance-mode

Recent DBT research does not provide a safe upstream-style cherry-pick:

- Partial cross-compilation/mixed execution reports large gains by moving
  eligible functions across an emulated/native boundary, but requires a
  calling channel and function eligibility proof. That supports this repo's
  existing title/signature-gated superpath strategy; it does not justify broad
  PPU/SPU replacement without verify-only output equivalence:
  https://arxiv.org/abs/2512.00487
- Direct translation that bypasses an intermediate representation reports
  proof-of-concept gains against QEMU TCG. RPCSX's hot SPU/PPU paths already use
  specialized LLVM/JIT machinery, so applying the paper means a new backend,
  not a local optimization. Park it until a stable profile identifies a tiny,
  repeatable guest block family worth a direct verified emitter:
  https://arxiv.org/abs/2501.03427
- Baseline-JIT meta-compilation targets warm-up latency by trading peak
  optimization for faster compilation. The current frozen candidate is instead
  finishing a persistent offline cache, which removes compilation from the
  measured gameplay route without sacrificing optimized code quality:
  https://arxiv.org/abs/2502.20543

Decision order after cache completion is therefore: first obtain the exact
ADPF-off title/field/menu/battle baseline; then run one matched default-off/on
RSX Performance Hint A/B under independent cooldowns; promote only if visuals,
fatal cleanliness, FPS/frame pacing, and temperature rise all pass. Thermal
headroom instrumentation is a later read-only diagnostic. The cross-compiled
function/direct-emitter ideas remain parked behind a stable hot-signature and
byte-for-byte verify gate. No APK/core/cache/device state changed in this
research round, and it earns no speed or thermal credit.
