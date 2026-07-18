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
