# Thor ARMv8.2-A native tuning

Date: 2026-07-17

## Scope and thermal policy

- Target: AYN Thor Max, Snapdragon 8 Gen 2, Android ARM64.
- Workload: RPCSX/RPCS3 host code used by Eternal Sonata `BLUS30161`.
- Classification: `build-proven`, `device-unmeasured`.
- This round was host-only. No ADB query, install, launch, gameplay route, or
  temperature query was performed after the preceding route observed an
  `87.1 C` silicon sensor.

## Evidence for the change

The existing ARM64 RelWithDebInfo compile database used `-O2`, `-DNDEBUG`, and
ThinLTO on the core, but no `-march`, `-mcpu`, or `-mtune` flag. The Android
toolchain therefore targeted generic ARMv8-A even though every Thor CPU is at
least ARMv8.2-A.

The connected proof device has this captured topology:

- 3 Cortex-A510 efficiency cores;
- 2 Cortex-A715 performance cores;
- 2 Cortex-A710 performance cores;
- 1 Cortex-X3 prime core.

A compiler probe of an acquire-release atomic add demonstrated the practical
gap:

- generic ARMv8-A emitted a call to `__aarch64_ldadd8_acq_rel`;
- `-march=armv8.2-a` emitted one inline `ldaddal` instruction.

This matters to synchronization-heavy PPU, SPU, RSX, and scheduler code. It is
not an FPS measurement by itself.

## Implementation

ARM64 native builds now default to:

```text
-march=armv8.2-a -mtune=cortex-a715
```

Gradle passes the values through `rpcsxAndroidArmArch` and
`rpcsxAndroidArmTune`; the equivalent environment variables are
`RPCSX_ANDROID_ARM_ARCH` and `RPCSX_ANDROID_ARM_TUNE`. Empty values disable a
flag for diagnostic builds. CMake checks compiler support and fails at
configuration time for an unsupported value.

The flags are guarded by an AArch64 processor check, so x86_64 builds are
unchanged. `-mtune` retains the generic target CPU and ARMv8.2-A feature set; it
changes instruction scheduling only. Runtime LLVM/JIT feature detection and
the existing dot-product/I8MM gates are unchanged.

## Host validation

Command:

```powershell
.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon --console=plain --offline
```

Result:

- `BUILD SUCCESSFUL` after a full native rebuild in `785.7 s`.
- The generated compile database contains both flags on all `1,385 / 1,385`
  AArch64 compile commands.
- Confirmed hot files include `PPUTranslator.cpp`, `SPUAnalyser.cpp`,
  `SPUThread.cpp`, `RSXThread.cpp`, `VKGSRender.cpp`, `Thread.cpp`, and
  `rpcsx-android.cpp`.
- The rebuilt non-LTO `Thread.cpp.o` contains `67` native LSE atomic
  instructions and zero outline-atomic helper relocations. The prior generic
  object contained zero native LSE instructions and `67` helper relocations.
- `git diff --check`: passed.

Artifact:

- Path:
  `app/build/intermediates/cxx/RelWithDebInfo/2t5h1l52/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,347,347,440` bytes, `3,685,704` bytes smaller than the prior core.
- SHA-256:
  `744CB3F2BE77F0DFCA255FE27EA5D7AF6E200E6BFC22D912F67CCCE6563CE839`

The official RPCS3 changes after the previously audited upstream point were
AVX-512 PPU LLVM NaN/denormal optimizations, so they do not apply to Thor's
AArch64 host. No upstream patch was forced into this round.

## Promotion gate

This change receives no Thor FPS, flicker, menu, battle, or stability credit
until a cooled device can run one no-repeat, thermally guarded matched scene.
The first proof should compare the known generic core with this exact candidate
under the same saved field route, then stop. A silicon temperature above the
configured limit must prevent launch and force-stop an already-running guest.

## First guarded device attempt

The exact candidate was pushed without rebuilding or launching:

- push evidence:
  `debug-captures/20260717-031834-armv82-aot-744cb3f2-dev-core-push`;
- active SHA-256:
  `744CB3F2BE77F0DFCA255FE27EA5D7AF6E200E6BFC22D912F67CCCE6563CE839`;
- package remained stopped after deployment.

A stopped-device cool-soak at
`debug-captures/android-speed-sprint/20260717-031655-thor-input-custom`
recorded battery `25.0 C`, skin `30.0 C`, and hottest silicon
`33.1/33.3/34.7 C`, so one guarded field attempt was allowed. A second ADB
target initially exposed an unpinned-wrapper bug before launch; the actual
attempt was then explicitly pinned to Thor serial `c3ca0370`.

The route
`debug-captures/android-speed-sprint/20260717-032039-thor-input-eternal-sonata-field-route`
started at silicon `34.1/33.9/33.9 C`. The legacy field profile entered a blind
`wait:90000`; the first five-second runtime poll found hottest silicon at
`77.1 C`, above the tightened `75 C` ceiling. The guard force-stopped RPCSX
before any route input, screenshot, or FPS sample. The post-stop snapshot one
second later was `51.8 C`.

Classification: `failed-thermal-guard` / `not-comparable`. This provides no FPS,
flicker, field, menu, battle, or stability credit for the ARMv8.2 candidate.
There was no second launch in this thermal round.

Host-side follow-up removes the `90/100 s` blind waits from the field,
field-direct, and menu profiles, reuses the stable title/Load/field visual
gates, pins the selected Android serial across nested ADB helpers, and changes
route runtime polling from a hard-coded five seconds to a two-second default.
The next separately cooled round may run one state-gated field attempt; it must
still abort rather than exceed the configured silicon ceiling.

## Warm-cache startup follow-up

The thermal abort happened during startup, so the next round stayed host-only:
no ADB query, deployment, launch, or device temperature read was performed.
Captured cache summaries from the failed route and two prior successful routes
show the same `BLUS30161` cache size (`26,210 KiB`) and the same EBOOT cache
directory (`26,207 KiB`). Prior guest logs report `LLVM: Loaded module` rather
than compiling a replacement object. This rules out a missing or wholesale
invalidated PPU cache as the main warm-start problem.

The source trace found two redundant scans in the normal Thor configuration:

1. `ppu_initialize()` performed a complete check-only hash/cache pass over the
   main PPU executable. Its result is used only to enqueue related directories
   when `LLVM Precompilation` is enabled, but the Thor profile explicitly sets
   that option to `false`. The real initialization then repeated the executable
   partitioning, hashing, and cache checks immediately afterward.
2. Each PPU initialization decoded every instruction looking for `MFVSCR`, even
   when `PPU Set Saturation Bit` was disabled. The result affects code generation
   and the cache key only when that option is enabled. Eternal Sonata Android
   captures and the default configuration both record it as `false`.

The warm-start candidate now:

- runs the check-only main-module pass only when LLVM precompilation is enabled;
- runs the MFVSCR instruction scan only when accurate SAT handling is enabled.

Behavior remains unchanged for both enabled modes. PPU code generation, cache
keys, the real load pass, and the existing cache objects are unchanged for the
Thor configuration.

Host validation:

- `tools/test_ppu_warm_cache_startup.ps1`: passed;
- PowerShell parser validation: passed;
- `git diff --check`: passed;
- `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: `BUILD SUCCESSFUL` in `67.4 s`;
- PPU compile flags remain
  `-march=armv8.2-a -mtune=cortex-a715`.

New host artifact:

- path:
  `app/build/intermediates/cxx/RelWithDebInfo/2t5h1l52/obj/arm64-v8a/librpcsx-android.so`;
- size: `1,347,345,712` bytes;
- SHA-256:
  `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`.

## First warm-cache device proof

### 2026-07-17 - warm-cache-scan-skip-field-proof

- Status: failed
- Scope: scene-route
- Hypothesis: skipping the redundant disabled-feature PPU scans would reduce
  warm-start CPU time enough to reach the title and field inside the Thor's
  guarded thermal window.
- Changed files/settings: exact ARM64 RelWithDebInfo core
  `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`;
  Direct input; state-gated field route; three-sample cool preflight; two-second
  runtime polling; battery/skin/silicon ceilings `34/40/75 C`; explicit stop.
- Rollback: redeploy the prior exact core `744CB3F2...E839`, or use
  `tools/build_push_thor_core.ps1 -Serial c3ca0370 -ResetToBundled -NoLaunch`.
- Windows result: host source-contract test and ARM64 RelWithDebInfo build passed
  before deployment; this round did not rerun Windows gameplay.
- Thor result: a stopped-device preflight recorded battery `25.0 C`, skin
  `30.0 C`, and silicon `35.5/35.5/36.3 C`. The exact core was then pushed with
  no build, launch, or stream. The route's own preflight recorded silicon
  `35.9/36.3/35.5 C`. After launch, the first readiness sample was `73.1 C` and
  the next two-second sample was `75.9 C`, so the guard force-stopped RPCSX.
  The immediate post-stop sample fell to `52.2 C`, and `pidof` confirmed the
  package was stopped.
- Visual correctness: the only readiness frame was neither the title menu nor
  a PPU compilation screen. No title, Load, field, Options, battle, or flicker
  checkpoint was reached.
- FPS/frame-time: none; no gameplay frame was reached.
- Capture paths:
  `debug-captures/20260717-035648-warm-cache-scan-skip-dev-core-push`,
  `debug-captures/android-speed-sprint/20260717-035553-thor-input-custom`, and
  `debug-captures/android-speed-sprint/20260717-035740-thor-input-warm-cache-scan-skip-field-proof`.
- Decision: `failed-thermal-guard` / `not-comparable`. The patch remains
  host-correct but receives no startup-time, temperature, FPS, flicker, menu,
  battle, or stability credit.
- Next: no second launch in this thermal round. Keep RPCSX stopped and inspect
  the pre-title native startup path on the host before preparing a materially
  different candidate for a later separately cooled proof.

## Android single-open wrapper follow-up

### 2026-07-17 - single-open-core-startup

- Status: proposed
- Scope: config-driver
- Hypothesis: MainActivity was needlessly loading and relocating the bundled
  core and development core for version validation, closing both handles, then
  loading the selected core again. Removing the two validation opens should
  materially reduce cold-start CPU work before RPCSX reaches its title gate.
- Changed files/settings: MainActivity now uses file metadata for cheap
  candidate selection and relies on the active `RPCSX.openLibrary` attempt;
  the JNI loader verifies the version export on that already-open handle before
  activation, preserving the bundled fallback without another `dlopen`.
- Rollback: revert `MainActivity.kt` and `native-lib.cpp`; no device setting,
  cache, core, or save data changed in this host-only round.
- Windows result: `tools/test_thor_single_core_load.ps1` and its PowerShell AST
  passed; `:app:compileDebugKotlin` passed in `53.8 s`; incremental ARM64
  RelWithDebInfo native build passed in `13 s`; `git diff --check` passed.
  The optimized core stayed byte-identical at `70B1...3601`.
- Thor result: not deployed or launched. A full Debug APK packaging attempt was
  stopped after the bounded `304 s` host timeout, and all orphaned Gradle,
  Ninja, and Clang processes from that attempt were terminated. The installed
  APK therefore does not contain this wrapper change yet.
- Visual correctness: unmeasured; no device launch was allowed after the earlier
  thermal abort.
- FPS/frame-time: none.
- Capture paths: prior thermal evidence remains
  `debug-captures/android-speed-sprint/20260717-035740-thor-input-warm-cache-scan-skip-field-proof`;
  this host-only follow-up created no new device capture.
- Decision: build-proven, device-unmeasured. Preserve the single-open change,
  but claim no startup, thermal, FPS, flicker, menu, battle, or stability win.
- Next: finish a fresh Debug APK in a separate host build window. In a later
  separately cooled round, install it without launch, confirm the package is
  stopped, then allow at most one identical state-gated field proof under the
  same two-second 75 C thermal guard.

## Reproducible ARM64 APK packaging follow-up

### 2026-07-17 - single-open-arm64-release-package

- Status: passed
- Scope: config-driver
- Hypothesis: the already-validated RelWithDebInfo core and JNI wrapper can be
  packaged without finishing the much larger Debug-native compile, while a
  normal Gradle ABI property avoids Android Studio's injected-ABI intermediate
  output and stale top-level APK redirect.
- Changed files/settings: `app/build.gradle.kts` now accepts
  `rpcsxAndroidAbis` / `RPCSX_ANDROID_ABIS`; the default remains
  `arm64-v8a,x86_64`, while Thor packaging uses
  `-PrpcsxAndroidAbis=arm64-v8a`. Added
  `tools/test_thor_arm64_apk.ps1` to require the arm64 core/wrapper and reject
  RPCSX core libraries for other ABIs.
- Rollback: remove the ABI property and restore the literal two-ABI filter.
  The generated APK is ignored build output; no device, save, cache, or config
  state changed.
- Windows result: standard `:app:assembleRelease
  -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true` passed in `87.8 s`.
  CMake reused the validated RelWithDebInfo output; no Clang, Ninja, or CMake
  process remained afterward. `tools/test_thor_single_core_load.ps1`,
  `tools/test_thor_arm64_apk.ps1`, PowerShell AST validation, and
  `git diff --check` passed.
- Artifact:
  `app/build/outputs/apk/release/rpcsx-thor-experiment-release.apk`;
  `57,393,944` bytes (`54.74 MiB`); SHA-256
  `FD754ED4896920F4F725404D9BEA2E589F247021ECD0649EDEC9CF496C366015`.
  Android `apksigner` verifies the APK with v2 signing and the debug certificate.
- Native contents: source core remains exact
  `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`;
  source JNI wrapper is
  `F9BAC7C31B1C43F4B44A1A466AFE573283346C812D8DA289C82722D8E3A5B774`.
  Their packaged stripped hashes are
  `C9999340E869810D79022BC2D094CA28D41557132E5FF333E2ADF95BE91676A0`
  and
  `ABD527164E4A01EC1AFF82514F819479B54E17BBEACA7E68572E14BBA4245F1A`.
- Packaging gotcha: `-Pandroid.injected.build.abi=arm64-v8a` created a valid
  fresh APK under `app/build/intermediates/apk/release`, but left the old
  `app/build/outputs/apk/release` file untouched. Use `rpcsxAndroidAbis` for
  reproducible command-line Thor artifacts.
- Thor result: not installed or launched. The old installed APK still lacks the
  single-open wrapper, while its development core remains exact `70B1...3601`.
- Visual correctness: unmeasured.
- FPS/frame-time: none.
- Capture paths: none; this was host-only packaging.
- Decision: host-ready, device-unmeasured, and not comparable. The APK is ready
  for a later cooled install/proof, but receives no startup, thermal, FPS,
  flicker, field, menu, battle, or stability credit.
- Next: only after a separately cool preflight, install this exact APK without
  launching, keep the package stopped, then allow one state-gated field proof
  with two-second silicon polling and the same 75 C stop guard.

## Optimized Thor test-package proof

### 2026-07-17 - single-open-thortest-field-proof

- Status: failed
- Scope: windows-android-ab
- Hypothesis: packaging the single-open wrapper and exact optimized
  RelWithDebInfo core in an installable APK would remove the redundant native
  loader work seen before the title gate and materially reduce startup heat.
- Changed files/settings: added the non-debuggable `thortest` build type, based
  only on `release`, with `THOR_DEBUG_TOOLS=true` and the debug-only boot/pad/
  dev-core source set. MainActivity and RPCSXActivity now gate those local test
  hooks on `THOR_DEBUG_TOOLS` instead of `BuildConfig.DEBUG`. The APK verifier
  can also require the exact merged native-core hash.
- Rollback: install the preceding APK or revert the `thortest` build type and
  `THOR_DEBUG_TOOLS` gates. No game, save, cache, firmware, or driver data was
  changed.
- Windows result: a first custom variant named `reldebug` was rejected before
  deployment because its name selected the CMake `Debug` native output. Its
  APK SHA-256 was `3AB793F997D3FFDCF5025AFBAC58A9736423A9A57BC595B4F0349E2FDA212264`
  and its wrong Debug core SHA-256 was
  `4677177E6B4484079D1874963EC94E5460DAAED750B8B5B414BE90053A2F03F9`.
  Renaming the variant to `thortest` and allowing only the release fallback
  produced a `BUILD SUCCESSFUL` result in `2m23s` with RelWithDebInfo native
  tasks. Exact APK
  `9F3379180FDCA4116A8B7F74657AC31C548398C0C2C944F6FE52F98ADD732D3E`
  packages merged core
  `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`.
  Generated BuildConfig has `DEBUG=false`, `BUILD_TYPE=thortest`, and
  `THOR_DEBUG_TOOLS=true`; the merged manifest contains the guarded boot, pad,
  and dev-core components. APK v2 signature verification passed.
- Thor result: the exact APK installed successfully without launch in
  `debug-captures/20260717-051304-single-open-thortest-apk-install`. The package
  was stopped before and after installation; battery/skin/silicon moved from
  `25.0/30.0/33.1 C` to `25.0/30.0/44.9 C` with no install guard violation.
  The one allowed route started from `25.0/30.0/33.5,32.9,33.9 C`. At the first
  readiness screenshot (`1348 ms`) silicon was `61.8 C`, then `71.9 C`, then
  `76.3 C`; the 75 C guard force-stopped the package. Post-stop silicon was
  `49.4 C`, and `pidof` was empty.
- Visual correctness: the only captured frame was the same pre-title progress
  class as the earlier route: title false, compilation false, black false, and
  progress-bar white `80.456%`. No title, Load, field, Options, battle, or
  flicker checkpoint was reached.
- FPS/frame-time: none. The first readiness poll was `11.3 C` cooler than the
  preceding single-open-missing APK route (`61.8` versus `73.1 C`) at nearly
  the same elapsed time (`1348` versus `1284 ms`). Relative to the last
  preflight sample, the rise improved by `9.7 C` (`27.9` versus `37.6 C`).
  This is reduced startup thermal pressure only, not FPS or stability credit.
- Capture paths:
  `debug-captures/20260717-051304-single-open-thortest-apk-install` and
  `debug-captures/android-speed-sprint/20260717-051446-thor-input-single-open-thortest-field-proof`.
- Decision: `failed-thermal-guard` / `not-comparable`. Keep the single-open
  wrapper and optimized packaging because the normalized startup temperature
  rise improved, but do not claim a game-speed win. The unchanged first frame
  and later thermal trip show substantial pre-title native/core work remains.
- Next: no second launch in this thermal round. Keep the package stopped and
  profile the packaged ELF dynamic table, relocation count, symbol visibility,
  and loader flags on the host. Prepare another device candidate only if a
  host-verifiable change materially reduces one-time native load work.

## Localized Android core export/relocation follow-up

### 2026-07-17 - localized-core-loader-metadata

- Status: passed
- Scope: windows-android-ab
- Hypothesis: the bundled core eager `BIND_NOW` load was spending avoidable
  cold-start CPU time scanning a huge public symbol table and applying dynamic
  relocations that are not part of the stable Android `_rpcsx_*` API.
- Changed files/settings: the Android core now defaults
  `RPCSX_ANDROID_LIMIT_DYNAMIC_EXPORTS=ON`, uses a version script plus
  `--exclude-libs,ALL`, and packs relocations with `android+relr` using the
  Android RELR tags required by the API-29 app minimum. The Gradle native
  target list is also limited to `rpcsx-ui-jni` and, when bundled,
  `rpcsx-android`, instead of building unrelated dependency examples.
- Rollback: configure `-DRPCSX_ANDROID_LIMIT_DYNAMIC_EXPORTS=OFF` or revert the
  Android CMake version-script/link options. Revert the Gradle `targets` list
  only if an additional native deliverable must be packaged.
- Windows result: baseline packaged core had `81,659` dynamic-table entries,
  `81,168` defined entries, `5,967,088` bytes of `.dynstr`, `200,205` explicit
  relocations, `26,846` JUMP_SLOT relocations, and `4,804,920` encoded
  relocation bytes. The new core has `456` dynamic-table entries, exactly `34`
  defined `_rpcsx_*` exports, `5,668` bytes of `.dynstr`, `583` explicit
  relocations, `391` JUMP_SLOT relocations, and `44,219` encoded relocation
  bytes. Explicit relocation rows fell `99.71%` and encoded relocation data
  fell `99.08%`; `BIND_NOW` remains enabled.
- Build result: targeted RelWithDebInfo native builds passed in `69 s` and
  `62 s`; final `:app:assembleThortest` passed in `53 s`. The export-surface,
  single-open, optimized-variant, ARM64 APK, PowerShell AST, APK v2 signature,
  and `git diff --check` validations passed.
- Artifacts: exact APK
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk` is
  `73,563,026` bytes with SHA-256
  `70988DDF4133D6EF5781BE323ED4BF7925DB1D9BCFDBEBE7B33C69B72F436252`.
  Its merged core is `1,304,252,368` bytes with SHA-256
  `EC682ADAA3EB28CBA38CEF3AA80462BE0F5886D897517EAAB18A42A5BEA55CDB`;
  its stripped packaged core is `62,823,496` bytes with SHA-256
  `11A76D5B2EEDCF411020DAADD5F6C084799BA8B0DDDAC386895BB4FEE9D53F3D`.
  The preceding stripped core was `96,438,728` bytes, so packaged native size
  fell by `33,615,232` bytes (`34.86%`).
- Thor result: not installed or launched. The device remains stopped on exact
  installed APK `9F3379...D3E` and merged core `70B1...3601`.
- Visual correctness: unmeasured; no Thor frame was rendered.
- FPS/frame-time: none. Loader metadata reduction is host evidence only.
- Capture paths: none; this follow-up was intentionally host-only.
- Decision: strong host candidate, device-unmeasured. Preserve the linker and
  target-selection changes, but claim no startup-time, temperature, FPS,
  flicker, field, menu, battle, or stability win yet.
- Next: do not spend another launch in this thermal round. After a separately
  cool preflight, install this exact APK without launch and allow only one
  state-gated proof with the existing two-second `75 C` stop guard.
