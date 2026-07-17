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

## Packaged-core isolated loader proof

### 2026-07-17 - packaged-core-isolated-loader-field-proof

- Status: failed
- Scope: windows-android-ab
- Hypothesis: limiting the Android core export/relocation surface and loading
  only the packaged core would reduce cold-start work enough to reach the title
  gate under the existing 75 C silicon guard.
- Changed files/settings: installed exact ThorTest APK
  `876480EED0BE5616F743F117B316D5122A7945B8A13F4CCFE5C605DB1CB891CE`
  without launch. Its generated BuildConfig has `DEBUG=false`,
  `THOR_DEBUG_TOOLS=true`, and `THOR_DEV_CORE_OVERRIDE=false`; MainActivity
  therefore selects the bundled `EC682ADA...5CDB` core. The reset tool now
  checks internal and staged marker removal separately so a non-debuggable
  `run-as` denial cannot be masked by later successful cleanup. A follow-up
  host APK additionally gates the debug provider itself.
- Rollback: install the preceding APK or revert `THOR_DEV_CORE_OVERRIDE` and
  the split reset assertions. The route changed no game, save, firmware,
  driver, or cache data.
- Windows result: the final provider-gated ThorTest build passed the optimized
  variant, single-open, export-surface, ARM64 APK, PowerShell AST, signature,
  and diff checks. Exact host-only APK
  `60DE891CC0D6D88E9672B5A5D83E04453A5700B3570445BD4533AED6429B0AE7`
  is `73,563,098` bytes and still packages merged core
  `EC682ADAA3EB28CBA38CEF3AA80462BE0F5886D897517EAAB18A42A5BEA55CDB`
  plus stripped core
  `11A76D5B2EEDCF411020DAADD5F6C084799BA8B0DDDAC386895BB4FEE9D53F3D`.
  It has not been installed.
- Thor result: the exact installed APK started after three cool preflight
  samples of `24/30/33.9,33.5,33.9 C`. Silicon was `63.4 C` at the first
  readiness screenshot, then `73.9`, `74.3`, `73.5`, and `75.1 C`; the guard
  force-stopped the package and the immediate post-stop sample was `53.8 C`.
  A later read-only check was `24/30/42.5 C` with `pidof` empty.
- Visual correctness: the sole visual class remained pre-title progress, with
  title false, compilation false, black false, and progress white `80.456%`.
  Against the preceding route the frame was essentially identical
  (`SSIM 0.999533`, average `PSNR 45.28 dB`). No title, Load, field, Options,
  battle, or flicker checkpoint was reached.
- FPS/frame-time: none. Process-established-to-guard time increased from about
  `6.807 s` to `12.266 s` (`+5.459 s`, about `+80.2%`), but the first-poll
  preflight-adjusted rise worsened from `27.9 C` to `29.5 C`. This supports
  only lower later thermal pressure, not faster startup or gameplay.
- Capture paths:
  `debug-captures/20260717-063455-packaged-core-isolated-thortest-apk-install`
  and
  `debug-captures/android-speed-sprint/20260717-063613-thor-input-packaged-core-isolated-loader-field-proof`.
- Decision: `failed-thermal-guard` / `not-comparable`. Preserve the loader
  metadata and packaged-core isolation work, but claim no speed, FPS, flicker,
  field, menu, battle, or stability win. The pulled log identifies the next
  dominant startup lane: `Shader cache preload workers: 2` followed by `289`
  captured `Add program` rows before stop.
- Next: no second launch in this thermal round. The guarded route now exposes
  an opt-in `RsxCacheWorkers` override, resets it before and after every run,
  and leaves the default at `0`/auto. After a separately cool preflight,
  install exact final APK `60DE...0AE7` without launch and spend one route on
  `RsxCacheWorkers=1`, measuring time-to-title and thermals under the same
  two-second 75 C guard.

## Upstream RSX cache work-sharing follow-up

### 2026-07-17 - rsx-dynamic-scheduler-loader-field-proof

- Status: failed
- Scope: rsx-vulkan
- Hypothesis: current upstream RPCS3's atomic per-entry shader-cache work
  sharing would eliminate the slow fixed-partition tail, while trace-only
  Android `Add program` logging would remove hundreds of synchronous startup
  log writes and reach the title under the 75 C guard.
- Changed files/settings: ported dynamic load/compile claims from current
  upstream `rsx_cache.h` while retaining the Android two-worker auto cap and
  bounded property override. On Android only, `Add program` moved from notice
  to trace; desktop notice behavior is unchanged. Added
  `tools/test_thor_rsx_cache_preload.ps1`. The device route used
  `RsxCacheWorkers=0`, which resolved to the normal two workers.
- Rollback: revert the two RSX source files and install exact prior APK
  `60DE891C...0AE7`. No game, save, firmware, driver, or cache content was
  changed.
- Windows result: host-only ARM64 RelWithDebInfo rebuilt successfully in
  `766.2 s`; `assembleThortest` then passed in `27 s`. The RSX preload,
  thermal-route, optimized-variant, single-open, export-surface, exact ARM64
  APK, PowerShell AST, APK v2 signature, and diff checks passed.
- Artifacts: exact installed APK
  `B76CE9F2B89AA452906D36D1D18A576BEA67F47A94D43133BB9BE9B20D532AEE`
  is `73,561,482` bytes. Merged core
  `6338257D6033E750B884BDD126BD939D95E0A024F5A1B623D73D70D0C24B5AE9`
  is `1,305,298,808` bytes; stripped packaged core
  `BBE67717700FA4AB9088531E87A1529DBBEBE7C86449BD8B89501285D06D1E03`
  is `62,822,408` bytes.
- Thor result: guarded no-launch install moved battery/skin/silicon from
  `25/30/33.1 C` to `25/30/44.5 C`; after idle cooling it returned to
  `25/30/33.9 C` with the package stopped. Route preflight was
  `25/30/34.3,33.9,33.7 C`. Silicon reached `57.4 C` at the first screenshot,
  then `72.7`, `73.9`, and `77.1 C`; the guard force-stopped RPCSX. Immediate
  post-stop was `54.2 C`; a later read-only sample was `25/30/42.1 C`,
  `pidof` was empty, and the worker property was reset to `0`.
- Visual correctness: only the same pre-title progress class rendered:
  title false, compilation false, black false, and progress white `80.456%`.
  The animated-frame comparison against the prior route was `SSIM 0.946772`
  and average `PSNR 21.99 dB`. No title, Load, field, Options, battle, or
  flicker checkpoint was reached.
- FPS/frame-time: none. Process-established-to-guard time fell from
  `12.266 s` to `9.685 s`, so guard duration worsened by `2.581 s` (`21.0%`).
  The first-poll adjusted rise improved from `29.5 C` to `23.7 C` (`5.8 C`),
  but this is conflicting thermal evidence and not a speed win.
- Logging result: the new pulled log contains `0` notice-level `Add program`
  rows versus `289` before. It still contains `411` RSX worker decompiler
  errors versus `410` before, so the dominant pipeline work remains.
- Capture paths:
  `debug-captures/20260717-072007-rsx-dynamic-scheduler-thortest-apk-install`
  and
  `debug-captures/android-speed-sprint/20260717-072156-thor-input-rsx-dynamic-scheduler-loader-field-proof`.
- Decision: `failed-thermal-guard` / `not-comparable`. Keep the upstream
  work-sharing implementation and quieter Android diagnostics as a
  correctness-preserving code update, but give them no startup, FPS, flicker,
  field, menu, battle, or stability credit.
- Next: no second route in this thermal round. Exact candidate `B76CE9...32AEE`
  is already installed and stopped. After a separately cool preflight, spend
  one route on `RsxCacheWorkers=1`; require time-to-title and visual proof
  under the same two-second 75 C guard before changing the default.

## Deferred shader preload device result and retirement

### 2026-07-17 - deferred-preload-loader-field-proof

- Status: failed and retired
- Scope: rsx-vulkan
- Hypothesis: skip the concentrated full disk-cache preload while switching
  Vulkan from `Async Shader Recompiler` to `Async with Shader Interpreter`, so
  asynchronous pipeline misses retain visible fallback draws without flicker.
- Exact installed ThorTest APK:
  `658F826DFC5494B50E23E3A0BC2AFF1EDF983C63FE053164CB485603AB69333C`,
  `73,561,058` bytes. It packages merged core
  `9D9C70E087F994D14272E6C95A48115158A88CF58951E0D286815A9E69CA847F`
  and stripped core
  `13672E01A50CA5310B0BCBF1AA81B14DA09E839F1DDC00560D7878E514DD84BD`.
- Guarded install did not launch RPCSX. The separately cooled route used
  `RsxCachePreload=defer`, `RsxCacheWorkers=0`, direct input, three preflight
  samples, two-second runtime polling, and limits `34/40/75 C`.
- Configuration proof: the effective property capture says `defer`; the pulled
  RPCSX log contains both `Android shader cache preload defer enabled` and
  `Shader cache preload deferred on Android`. No full preload worker notice
  appears, so the experiment activated correctly.
- Thermal result: preflight silicon was `33.5, 33.5, 33.9 C`. It rose to
  `59.0 C` at the first screenshot, then `73.5 C`, then `77.1 C`, where the
  guard force-stopped RPCSX. First-poll adjusted rise was `25.1 C`, `1.4 C`
  worse than the prior dynamic-scheduler route. Process establishment at
  `08:00:02.195` to guard sample at `08:00:09.112` was `6.917 s`, `2.768 s`
  shorter than the prior `9.685 s`.
- Visual result: the only frame was neither title nor a valid preload frame.
  It showed a black upper region, a flat gray lower region, and a horizontal
  static/noise band at their boundary. Classifier evidence was title false,
  PPU compilation false, black false, dark `79.915%`, and progress white `0`.
  No title, Load, field, movement, Options, battle, or FPS checkpoint was
  reached.
- Device postcondition: the guard force-stopped the package; later `pidof`
  remained empty. The route failure reset restored
  `debug.rpcsx.thor.rsx_cache_preload=preload`, and the worker property remains
  `0`. Cache files were preserved.
- Capture:
  `debug-captures/android-speed-sprint/20260717-075950-thor-input-deferred-preload-loader-field-proof`.
- Decision: `failed-visual-gate` and `failed-thermal-guard`. This is not a speed
  or stability improvement. Retire the defer/interpreter implementation and
  route controls; preserve the earlier upstream atomic RSX work-sharing and
  trace-only Android diagnostics.
- Next: no second launch in this thermal round. Investigate Vulkan pipeline
  cache reuse and pipeline-construction cost on the host. Keep a one-worker
  normal-preload route parked for a later separately cool comparison, but do
  not promote it without title/field correctness and acceptable wall time.

## Persistent Vulkan driver pipeline cache host candidate

### 2026-07-17 - android-core-pipeline-cache

- Status: host candidate; device-unmeasured
- Scope: rsx-vulkan
- Hypothesis: seeding normal Vulkan graphics and compute pipeline creation from
  a title-local core VkPipelineCache can reduce repeated Adreno pipeline
  construction during later warm starts without changing shader semantics.
- Upstream review: official RPCS3 origin/master at 4309847 has no
  Emu/RSX/VK changes after the local 1269ebf base. Its normal graphics and
  compute pipeline compiler still passes a null cache; only the separate
  shader-interpreter path owns an in-memory pipeline cache. There is therefore
  no newer normal-pipeline patch to cherry-pick.
- Changed files/settings: Android now creates one shared core pipeline cache,
  validates persisted header size/version/vendor/device/UUID against the
  current physical device, rejects files outside 32 B..64 MiB, retries empty
  if a driver rejects saved seed data, and uses the cache for both graphics
  and compute creation. It stores atomically under the per-title
  shaders_cache/vulkan/driver_pipeline_cache.bin, checkpoints after pipeline
  counts 32,64,128,..., and saves once more after compiler workers stop.
  Non-Android execution retains the null-cache path.
- Rollback: set debug.rpcsx.thor.vk_pipeline_cache=off; the route and wrapper
  expose default-on VkPipelineCache / AndroidVkPipelineCache controls and
  restore the property to on before launch and after success or failure.
  Disabling the on-disk shader cache also disables this cache.
- Host correctness: PowerShell AST parsing passed for all edited harness/test
  scripts. tools/test_thor_vulkan_pipeline_cache.ps1,
  tools/test_thor_thermal_guard.ps1, and
  tools/test_thor_rsx_cache_preload.ps1 passed. The edited
  VKPipelineCompiler.cpp produced a fresh ARM64 object, and
  :app:buildCMakeRelWithDebInfo[arm64-v8a] completed successfully in the
  confirming incremental pass.
- Device result: none. No APK was assembled, installed, or launched, and the
  stopped Thor was not queried or heated during this experiment.
- FPS/frame-time: none. Core pipeline-cache support is only a plausible warm
  startup/stutter candidate; it has no speed, thermal, flicker, field, menu,
  battle, or stability credit.
- Decision: preserve as a reversible host-built candidate. Do not claim a
  speedup and do not combine it with the retired deferred-preload lane.
- Next: after a separately cool soak, build/install one exact ThorTest APK
  without launch. Use short guarded rounds to establish a compatible saved
  cache, then compare the same exact APK/config with the cache route on versus
  off on separately cool starts. Require title/field visual correctness,
  pipeline-create timing, wall time, and thermal evidence before promotion.


## Persistent Vulkan driver pipeline cache device seed result

### 2026-07-17 - vk-pipeline-cache-seed-proof

- Status: cache-seed-success; failed-thermal-guard; not-comparable for speed
- Scope: rsx-vulkan
- Exact installed ThorTest APK:
  `A3E9F49A727B991F77F641B5800CC1927E497D2F3FFA84133682574DEB7D5355`,
  `73,564,998` bytes. It contains merged core
  `916508B53029EE7BC3656E741199D16856C85903A838AA9E9C912F320A25481B`
  and packaged stripped core
  `43DEF9184ADD69A47548A0E894BBF73662E423D1710F422E40A5DAB365D5620F`.
  The ARM64 APK, optimized-variant, single-core-load, export-surface,
  pipeline-cache, thermal, zipalign, and v2 signature gates all passed.
- Install capture:
  `debug-captures/20260717-090323-vk-pipeline-cache-thortest-apk-install`.
  Installation did not launch RPCSX and confirmed that no previous
  `driver_pipeline_cache.bin` existed.
- Guarded route:
  `debug-captures/android-speed-sprint/20260717-090825-thor-input-vk-pipeline-cache-seed-proof`.
  It used the exact APK, direct input, normal two-worker/auto preload,
  `VkPipelineCache=on`, three cool-preflight samples, two-second runtime
  polling, and `34/40/75 C` limits.
- Activation proof: the guest log created the core Vulkan cache with
  `seed=0 bytes`, then atomically saved `754,355` bytes at 32 pipelines,
  `1,212,061` bytes at 64, and `2,239,716` bytes at 128. This proves the
  new normal graphics/compute cache path and force-stop-safe checkpoints
  executed on Adreno.
- Persisted artifact:
  `cache/BLUS30161/ppu-VFsK9TLbNhFcL78pncprig5JUstQ-EBOOT.BIN/shaders_cache/vulkan/driver_pipeline_cache.bin`,
  SHA256
  `76318ED124ED3B3B9710347DAD72017E092194E7AD7A6EE7E7EC3614783B26A1`,
  size `2,239,716`. Its Vulkan header is 32 bytes, version 1, Qualcomm vendor
  `0x5143`, device `0x43050A01`, UUID
  `47139E06435100000000010A05430000`.
- Thermal result: the last preflight silicon sample was `33.7 C`; the first
  runtime frame was `65.4 C`, then `73.1 C`, and the guard force-stopped
  at `75.9 C`. Process establishment to guard was about `6.951 s`; the
  first-poll adjusted rise was `31.7 C`. Immediate post-stop silicon was
  `52.6 C`, then a later read-only audit reported `48.6 C` with no PID.
- Visual/log result: the only screenshot was a non-corrupt pre-title progress
  frame with `80.293%` progress white. It was not the title and provides no
  field/menu/battle/flicker proof. Targeted fatal hits and decompiler-error rows
  were both zero.
- Decision: preserve the implementation and saved cache, but award no speed,
  FPS, thermal, flicker, field, menu, battle, or stability credit. This was a
  cold seed, not a warm-cache comparison, and it stopped before title.
- Device postcondition: package stopped; route properties restored to
  `vk_pipeline_cache=on`, normal `preload`, and worker override `0`.
  No second launch is allowed in this thermal round.
- Harness follow-up: standard Thor snapshots now pull the full `RPCSX.log`
  automatically, so future thermal failures retain guest cache/fatal evidence
  without a manual ADB recovery.
- Next: after a separately cool soak, run the same exact APK/config once with
  the cache on and require the log to report
  `Created Vulkan driver pipeline cache (seed=2239716 bytes)`. Compare that
  warm-on route separately from this cold seed; only then schedule a separately
  cooled cache-off route if needed. Require title/field visuals and matched
  thermal/wall-time evidence before claiming speed.


## Cool-launch thermal preflight correction

### 2026-07-17 - strict-warm-cache-cooldown-gate

- Status: route-tooling; launch rejected; no speed comparison
- Scope: Android harness / thermal safety
- The first read-only cooldown audit after the cold cache seed was
  `debug-captures/android-speed-sprint/20260717-092745-vk-pipeline-cache-warm-cooldown-query`.
  Battery/skin stayed at `25/30 C`, but maximum silicon rose
  `45.8 -> 49.0 -> 50.6 C`. RPCSX was stopped and the persistent cache
  remained exactly `2,239,716` bytes / SHA256
  `76318ED124ED3B3B9710347DAD72017E092194E7AD7A6EE7E7EC3614783B26A1`.
- Tooling note: the first audit's per-row PID column accidentally contains the
  host PowerShell `$PID` because that automatic variable is read-only. Its
  separate native device-state query says `pid=`, and the corrected follow-up
  also reports an empty package PID. Do not interpret `13908` as RPCSX.
- Safety finding: the prior five-degree headroom rule reduced the 75 C runtime
  cutoff only to a 70 C preflight limit. It therefore labeled a clearly warm,
  rising 50.6 C device as launchable even though recent boot routes add roughly
  24-32 C within their first runtime sample.
- Harness correction: Android route launches now use the lower of runtime
  cutoff-minus-headroom and an independent `40.0 C` maximum launch-silicon
  ceiling. Three preflight samples must also rise no more than `2.0 C`.
  Both values are bounded parameters, recorded in route metadata, and forwarded
  by `eternal_sonata_speed_sprint.ps1`.
- Corrected strict audit:
  `debug-captures/android-speed-sprint/20260717-093511-vk-pipeline-cache-strict-cooldown-query`.
  Its first sample was `25/30/44.1 C` with no RPCSX PID, so the new 40 C
  ceiling rejected the route immediately. USB power was present; no emulator
  launch, install, cache mutation, or gameplay heat occurred.
- Host verification: PowerShell AST parsing passed for all four edited scripts,
  `tools/test_thor_thermal_guard.ps1` passed new ceiling/trend unit and source
  contracts, `tools/test_thor_vulkan_pipeline_cache.ps1` passed, and
  `git diff --check` passed.
- Decision: preserve the stricter fail-closed launch gate. The warm-cache route
  remains unmeasured and receives no speed, FPS, thermal, flicker, field, menu,
  battle, or stability credit.
- Next: leave RPCSX stopped. Only after a later three-sample preflight remains
  below `40.0 C`, rises no more than `2.0 C`, and reports no package PID,
  spend one short same-APK/config warm-cache-on route. Require
  `seed=2239716 bytes` before any speed claim.

## Persistent Vulkan driver pipeline cache warm-start result

### 2026-07-17 - vk-pipeline-cache-warm-proof

- Status: startup-throughput progress; failed-thermal-guard; not-comparable for FPS
- Scope: rsx-vulkan / Android thermal startup
- The exact installed ThorTest APK remained
  `A3E9F49A727B991F77F641B5800CC1927E497D2F3FFA84133682574DEB7D5355`.
  Its one separately cooled warm route is
  `debug-captures/android-speed-sprint/20260717-094931-thor-input-vk-pipeline-cache-warm-proof`.
- Preflight was genuinely cool and stable: battery/skin were `25/30 C`, and
  silicon was `33.1 -> 33.1 -> 32.9 C`. The route used direct input, automatic
  two-worker preload, the same config/APK, cache on, two-second runtime polling,
  and the `75 C` fail-stop limit.
- Activation proof: the log accepted exactly
  `Created Vulkan driver pipeline cache (seed=2239716 bytes)`. It serialized the
  unchanged `2,239,716`-byte blob at early checkpoint logs with current-session
  counters `70` and `128`, then grew it to `4,016,586` bytes at `256` and
  `4,899,180` bytes at `512` pipelines.
- Matched cold comparison: the cold route had reached only `128` pipeline
  creates by emulated `6.277 s`; the warm route reached `512` by `7.089 s`.
  Process establishment to thermal stop increased from `6.951 s` to `12.175 s`
  (`+5.223 s`, `+75.1%` time before the guard). First-poll adjusted silicon
  rise improved from `31.7 C` to `26.5 C` (`5.2 C` cooler).
- Correctness limit: the only screenshot was still the same `80.293%`
  pre-title progress frame. Its central comparison against the cold screenshot
  had `0/63,360` changed samples. Title, field, menu, battle, flicker, and FPS
  were not reached. Targeted fatal and unknown-draw scans were clean.
- Thermal result: silicon samples after launch were `59.4, 72.7, 72.3, 73.1,
  77.5 C`; the guard force-stopped RPCSX at `77.5 C`. Immediate post-stop was
  `53.0 C`, `pidof` was empty, and cache/preload/worker properties reset to
  `on/preload/0`. No second route is allowed in this cool round.
- Decision: preserve the persistent cache as real startup-throughput progress,
  but award no gameplay speed, FPS, visual, menu, battle, flicker, thermal, or
  stability credit. The driver cache advanced substantially farther before the
  thermal stop but still did not reach title.
- Host follow-up: warm-seed initialization now defers its first crash-safe
  checkpoint to `256` creates, removing the two observed redundant early
  rewrites; cold caches retain `32/64/128/...`. A driver-rejected seed is
  correctly treated as empty and keeps the cold schedule. Source-contract,
  thermal, preload, AST, and diff checks pass. ARM64 RelWithDebInfo builds in
  `56 s`; core SHA256 is
  `FB5C9FFE05D43702063EA8FB0C2F359F4FD7ED0CD6016CACC371B1C96C26225E`,
  size `1,304,279,064` bytes.
- Exact packaged ThorTest APK is
  `D3048BE18065C692500C35320740731CBFA22733E7EDC967E9089BE20B130DBA`,
  `73,563,042` bytes, with stripped core
  `18A55F04467EB5B3828564915E88CFA3F4D0DA06A04EF0EA07E412DBE66B7387`,
  `62,827,928` bytes. ARM64 ABI/core identity, optimized test-hook, export and
  relocation, single-open, Vulkan cache, RSX preload, thermal, and visual-route
  contracts pass. It is not installed or device-proven.
- Next: keep Thor stopped and do not install while it is still hot. After a
  separately cool soak, install the exact APK without launch, then use one
  short guarded route only. Require title visual proof before any FPS claim;
  the existing one-worker preload control remains a later single-variable
  thermal experiment.

## Bounded oldest-first RSX pipeline preload candidate

### 2026-07-17 - host-only-rsx-preload-limit

- Status: host-verified candidate; not installed; device proof pending
- Scope: rsx-vulkan / Android thermal startup
- Evidence for the lane: the last genuinely cool warm-cache route reached the
  same `80.293%` pre-title frame before the 75 C guard. The normal cache-miss
  path in `ProgramStateCache.h` builds a missing pipeline when first requested,
  so startup does not need to compile every disk descriptor before title.
- Change: `debug.rpcsx.thor.rsx_cache_preload_limit` and environment fallback
  `RPCSX_THOR_RSX_CACHE_PRELOAD_LIMIT` accept `0..4096`. `0`/unset preserves the
  full preload. A positive value below the descriptor count sorts cache entries
  by oldest mtime, then name, and preloads only the requested prefix. Omitted
  files are neither deleted nor interpreted; runtime retains the configured
  async/recompiler miss behavior. The failed deferred/interpreter lane remains
  absent.
- Harness: `RsxCachePreloadLimit` and `AndroidRsxCachePreloadLimit` are bounded,
  recorded, forwarded, set only for the boot route, and reset to `0` before
  launch and after both successful and failed routes. Default routes therefore
  remain unchanged.
- Host verification: `tools/test_thor_rsx_cache_preload.ps1`, thermal, Vulkan
  cache, visual-route, single-open, optimized-variant, ARM64 APK/core identity,
  export/relocation, PowerShell AST, and `git diff --check` gates pass. ARM64
  RelWithDebInfo completed in `66 s`; exact merged core is
  `588788A579E0A1EA9777EE6DFEC5177EFBC1C0BD7062696125DD008ED2BFA670`,
  `1,304,401,872` bytes.
- Exact packaged ThorTest APK is
  `26A843E2A5C6DFA4408C2D6ACC2FBA3F384AB4DBCC7589E3B8EBBB0D96B198EB`,
  `73,571,146` bytes. Its packaged stripped core is
  `2758A909A3F5D7450EE9061CA5F754B945CD433C727137041C7477F872754B5B`,
  `62,838,440` bytes. It is not installed; the device still has exact APK
  `A3E9F49A727B991F77F641B5800CC1927E497D2F3FFA84133682574DEB7D5355`.
- Decision: keep the control opt-in and award no startup, thermal, FPS, flicker,
  title, field, menu, battle, or stability credit from host evidence.
- Next: leave RPCSX stopped. After a later three-sample sub-40 C stable
  preflight, install this exact APK without launch, then run one short guarded
  direct-input route with normal two workers, Vulkan cache on, and
  `RsxCachePreloadLimit=256`. Require the exact activation log, title visual
  proof, targeted-fatal cleanliness, and thermal timing before promotion.

### 2026-07-17 - bounded-preload guarded no-launch install

- Status: exact APK installed; no emulator launch; runtime proof still pending
- The corrected install preflight capture is
  `debug-captures/android-speed-sprint/20260717-102911-bounded-preload-install-preflight`.
  RPCSX PID was absent and the three samples were `25/30/35.9`,
  `25/30/33.7`, and `25/30/34.7 C` for battery/skin/silicon. Silicon fell
  `1.2 C` across the sample window, so the independent sub-40 C ceiling and
  maximum `2 C` rise gate passed.
- Exact APK
  `26A843E2A5C6DFA4408C2D6ACC2FBA3F384AB4DBCC7589E3B8EBBB0D96B198EB`,
  `73,571,146` bytes, was installed with `adb install -r` and not launched.
  The installed `/data/app/.../base.apk` independently hashed to the same
  SHA256. Capture:
  `debug-captures/20260717-103010-bounded-preload-thortest-apk-install`.
- Post-install state: PID absent; battery/skin/silicon `25/30/37.7 C`;
  `rsx_cache_workers=0`, `rsx_cache_preload_limit=0`, legacy preload mode
  `preload`, and Vulkan driver cache `on`. The install did not spend an
  emulator route.
- Decision: the candidate is deployment-proven only. It still receives no
  startup, thermal-runtime, FPS, title, flicker, field, menu, battle, or
  stability credit. Do not launch in this install round.
- Next: after another later three-sample stable sub-40 C preflight, run exactly
  one short guarded direct-input route with `RsxCachePreloadLimit=256`, normal
  two workers, Vulkan cache on, and the existing 75 C fail-stop. Require the
  activation log, title visual proof, and fatal/thermal evidence.

## Bounded RSX preload guarded startup result

### 2026-07-17 - bounded-preload-title-proof

- Status: real startup-stage progress; failed thermal guard; no title/FPS proof
- Scope: RSX preload / persistent Vulkan cache / SPU startup handoff
- The exact installed APK remained
  `26A843E2A5C6DFA4408C2D6ACC2FBA3F384AB4DBCC7589E3B8EBBB0D96B198EB`.
  Its one separately cool route is
  `debug-captures/android-speed-sprint/20260717-103430-thor-input-bounded-preload-title-proof`.
- Strict preflight passed at battery/skin/silicon `25/30/33.7`,
  `25/30/34.7`, and `25/30/35.1 C`; silicon rose `1.4 C`, below the `2 C`
  trend limit and the independent `40 C` launch ceiling.
- Exact activation was logged: Vulkan driver cache seed `4,899,180` bytes,
  first warm checkpoint `256`, and `Android shader cache preload limit: 256
  of 939 oldest pipelines; 683 will compile on demand`. The normal two RSX
  workers remained active.
- Matched startup stages moved materially earlier than the full-RSX-preload
  warm route: PPU OPD `1.584417` versus `7.534762` (`5.950345 s` earlier),
  SPU runtime built `2.450193` versus `8.410648` (`5.960455 s` earlier),
  matching `mpy32` `3.497942` versus `9.491129` (`5.993187 s` earlier), and
  matching MFC warning `5.917972` versus `11.894869` (`5.976897 s` earlier).
- The route reached later SPU compilation work but hit the thermal guard at
  `75.5 C` about `6.923 s` after process establishment. Immediate post-stop
  silicon was `51.4 C`; PID was absent and route properties reset.
- The single screenshot was a non-black, materially changed `80.456%`
  pre-title frame. Targeted fatal and unknown-draw scans were zero, but title
  was not reached. Award startup-stage progress only: no FPS, gameplay,
  flicker, title, menu, battle, or stability credit.
- Bottleneck conclusion: the RSX bound removed roughly six seconds of eager
  pipeline work and exposed full SPU cache reconstruction as the concentrated
  thermal lane. Historical completed evidence built `1,163` SPU programs,
  taking about `32.5 s` after interpreter construction.

## Bounded oldest-first SPU cached-program preload candidate

### 2026-07-17 - host-only-spu-preload-limit

- Status: host-verified candidate; not installed; device proof pending
- Scope: SPU LLVM startup / Android thermal load shaping
- Cache audit: the SPU `.dat` file stores guest program bytes, not generated
  ARM64 objects. Full startup reads and recompiles the complete file. Runtime
  compilation appends a program only after successful LLVM JIT completion.
- Change: `debug.rpcsx.thor.spu_cache_preload_limit` and environment fallback
  `RPCSX_THOR_SPU_CACHE_PRELOAD_LIMIT` accept `0..4096`; zero/unset preserves
  the full existing preload. A positive value registers all cached program
  identities as already on disk, deduplicates by the existing runtime identity
  rule, and eagerly compiles only the oldest-discovered unique prefix. Omitted
  programs keep the normal configured LLVM runtime miss path and cannot append
  duplicate disk records solely because they were omitted from eager compilation.
- Harness: `SpuCachePreloadLimit` and `AndroidSpuCachePreloadLimit` are bounded,
  recorded, forwarded, set immediately before boot, and reset to zero before
  launch and after both successful and failed routes. Default behavior is
  unchanged.
- New source contract `tools/test_thor_spu_cache_preload.ps1` checks property
  and environment parsing, all-identity registration before limiting, oldest
  unique queue construction, normal LLVM fallback, and duplicate-write guard.
  Thermal-route and PowerShell AST contracts also pass.
- ARM64 RelWithDebInfo native build passed in `59 s`; optimized ThorTest
  packaging passed in `47 s`. Exact artifacts:
  - APK `41A289BBAAD42E1B5A9FAF630A6A0F57D5BB275F6F94538F38B96FB2C94483E6`,
    `73,572,526` bytes;
  - merged core
    `6775972D06E8582E8F0BAB6F2618B68DE6A63AC1738706E6423BD403F3C5E223`,
    `1,304,464,952` bytes;
  - packaged stripped core
    `FD5A6DDA5E7C10EEE7C65AF3AB15A7203077E6863B8F82999190C248FE856AD5`,
    `62,843,320` bytes.
- All host gates pass: ARM64 APK/core identity, optimized test hooks,
  single-open loader, Vulkan cache, bounded RSX preload, bounded SPU preload,
  thermal fail-stop, visual route, PowerShell AST, and diff checks. Export
  surface is `34` defined dynamic symbols, `583` explicit relocations, `391`
  jump slots, and `44,219` encoded relocation bytes.
- Verifier correction: LLVM 18 expands packed `.relr.dyn` entries while LLVM
  20 does not. The export test now excludes that section from explicit counts;
  NDK 27 and NDK 29 both pass with identical metrics.
- Decision: keep the SPU bound opt-in. Host evidence earns no runtime speed,
  thermal, title, FPS, gameplay, flicker, or stability credit. Do not install
  or launch in the just-spent hot round.
- Next: after a separately cool stable sub-40 C preflight, install this exact
  APK without launch. In a later separately cool route, use one conservative
  SPU limit with `RsxCachePreloadLimit=256`, Vulkan cache on, and the existing
  thermal fail-stop. Require activation counts, title visual proof, comparable
  timing, and fatal cleanliness before promotion.

### 2026-07-17 - bounded-SPU guarded no-launch install

- Status: exact APK installed; no emulator launch; runtime proof pending
- A read-only strict preflight reported PID absent and battery/skin/silicon
  `25/30/34.9`, `25/30/35.5`, and `25/30/34.7 C`. Silicon ended `0.2 C`
  below the first sample, satisfying the independent sub-40 C ceiling and
  maximum `2 C` rise rule. The first ad hoc query failed closed because its
  shell quoting did not produce parseable silicon telemetry; it performed no
  install or launch. The corrected timeout-safe query produced all three
  valid samples before deployment.
- Exact APK
  `41A289BBAAD42E1B5A9FAF630A6A0F57D5BB275F6F94538F38B96FB2C94483E6`,
  `73,572,526` bytes, was installed with `adb install -r` and not launched.
  On-device `/data/app/.../base.apk` independently matched the same SHA256.
  Capture: `debug-captures/20260717-110738-bounded-spu-thortest-apk-install`.
- Post-install state: PID absent; battery/skin/silicon `25/30/38.9 C`;
  `rsx_cache_workers=0`, `rsx_cache_preload_limit=0`,
  `spu_cache_preload_limit=0`, legacy RSX preload mode `preload`, and Vulkan
  driver cache `on`.
- Decision: this proves only exact deployment and safe cleanup. Award no
  startup, runtime thermal, title, FPS, gameplay, flicker, field, menu, battle,
  or stability credit. Do not launch in this install round.
- Next: after another separately cool stable preflight, spend one short route
  with `RsxCachePreloadLimit=256`, `SpuCachePreloadLimit=64`, normal two RSX
  workers, Vulkan cache on, and the existing 75 C fail-stop. Require the SPU
  activation count, title visual proof, matched stage timing, and fatal
  cleanliness; stop on the first thermal or visual failure and do not retry in
  that round.

### 2026-07-17 - SPU cache order audit and boot-prefix correction

- The active Thor cache was inspected read-only while RPCSX remained stopped.
  `spu-safe-v1-tane.dat` is `391,252` bytes and parses completely as `1,165`
  records with `1,165` unique SHA1 identities; there are no duplicate records.
- Historical Android capture `20260714-233735` is the authoritative cold-cache
  ordering witness: it reports `SPU Runtime: Workers built 0 programs`, reaches
  the title through normal runtime LLVM misses, and then continues to field and
  battle. Since successful runtime JITs append to the file, disk order is first
  discovery order.
- Matching logged identities confirm the relationship. Programs observed near
  emulated `62-77 s` occupy oldest indices `759-773`; later observations around
  `78-144 s` extend through oldest index `1,027`. Reversing this order would
  spend a small preload budget on later discoveries rather than boot work.
- Corrective host change: bounded preload now walks `spu_cache::get()` in
  reverse, selecting the oldest unique prefix while still registering every
  cached identity and preserving the LLVM miss path. The default zero/unset
  full-preload behavior remains unchanged.
- This audit does not prove that `64` entries cover title; evidence instead
  shows the title working set is much larger. The purpose of `64` is to remove
  a small amount of early JIT stutter without recreating the thermally costly
  `1,165`-program startup rebuild. Runtime and thermal credit remain pending.
- ARM64 RelWithDebInfo rebuilt successfully in `88.5 s`; optimized ThorTest
  packaging then passed in `91.4 s`. Exact corrected artifacts:
  - APK
    `C44E69DE6EFA9BF214B37B246F757D989F579DCE6B87CB0FA7CF70C4135885A0`,
    `73,572,566` bytes;
  - merged core
    `D3478CFA53B308664BDEF4C9C6DE8DD749E0DBF3550BB8AAEA600DCAD99C593A`,
    `1,304,468,360` bytes;
  - packaged stripped core
    `A6DF1856624D7E595A824ABEA306E4BFA2200EA662CE9E186243C76F472E45BA`,
    `62,843,320` bytes.
- All host gates pass: ARM64 APK/core identity, optimized test hooks,
  single-open loader, Vulkan cache, bounded oldest-first RSX and SPU preload,
  thermal fail-stop, visual route, export surface, and diff checks. This exact
  APK is not yet installed and receives no device/runtime credit.

### 2026-07-17 - oldest-first bounded-SPU guarded no-launch install

- Status: exact corrected APK installed; no emulator launch; runtime proof
  pending.
- A strict read-only preflight found RPCSX absent and reported identical
  battery/skin/silicon samples of `25/30/33.9 C` three times. Silicon rise was
  `0.0 C`, satisfying the independent sub-`40 C` ceiling and maximum `2 C`
  rise rule.
- Exact APK
  `C44E69DE6EFA9BF214B37B246F757D989F579DCE6B87CB0FA7CF70C4135885A0`,
  `73,572,566` bytes, was installed with `adb install -r` and not launched.
  On-device `/data/app/.../base.apk` independently matched the same SHA256.
  Capture: `debug-captures/20260717-113150-oldest-spu-thortest-apk-install`.
- The evidence script reached the installed hash check, then collided with
  PowerShell's reserved `$PID` variable during the final audit. The continuation
  did not reinstall or launch; it only completed the PID/property/temperature
  reads using a non-reserved variable.
- Final state: PID absent; battery/skin/silicon `25/30/34.3 C`;
  `rsx_cache_workers=0`, `rsx_cache_preload_limit=0`,
  `spu_cache_preload_limit=0`, and Vulkan driver cache `on`.
- Decision: this proves exact deployment and safe cleanup only. Award no
  startup, runtime thermal, title, FPS, gameplay, flicker, field, menu, battle,
  or stability credit. Do not launch in this install round. After another
  separately cool preflight, spend one guarded route with RSX `256`, SPU `64`,
  Vulkan cache on, and the existing `75 C` fail-stop.
- Host-only sizing of the pulled cache supports that conservative bound. All
  `1,165` records contain `95,483` SPU words (`381,932` program bytes); the
  oldest `64` contain `3,310` words (`13,240` bytes), only `3.467%` of the
  instruction volume. Their median is `13` words and maximum is `939` words.
  This is a workload proxy, not a timing result, but it is consistent with
  roughly `1-2 s` of eager work rather than the observed `32.5 s` full rebuild.

### 2026-07-17 - oldest-first bounded-SPU guarded title route

- Capture:
  `debug-captures/android-speed-sprint/20260717-113647-thor-input-oldest-spu-bounded-title-proof`.
  A preceding wrapper invocation timed out during host-side preflight with PID
  absent; it did not launch RPCSX and is not a charged device route.
- The charged route passed its own strict preflight at battery/skin/silicon
  `25/30/34.3`, `25/30/33.9`, and `25/30/34.7 C`. Exact controls activated:
  Vulkan driver cache seed `4,899,180` bytes, first checkpoint `256`, RSX
  oldest preload `256 of 939`, two RSX workers, and SPU oldest preload
  `64 of 1,165` with `1,101` retained for on-demand LLVM compilation.
- SPU interpreter construction completed at emulated `2.432128 s`; the two
  workers completed all `64` eager programs at `2.816912 s`, a `0.385 s`
  bounded rebuild. Runtime SPU execution followed immediately.
- Process identity was established at `11:36:59.475583`; the `75.1 C` guard
  fired at `11:38:12.925080`, `73.449 s` later. The prior full-SPU-cache
  bounded-RSX route survived only `6.923 s`, so the useful guarded window
  expanded by `66.526 s` or about `10.6x`. Immediate post-stop silicon was
  `59.0 C`; PID was absent and all route properties were reset.
- Visual evidence did not reach title. Poll 1 retained the `80.456%` pre-title
  progress bar; polls 2-5 were `100%` dark; poll 6 was `99.31%` dark. The
  route was only a few seconds short of the historical approximately `75.8 s`
  title screenshot, but no title credit may be inferred.
- Targeted scans found zero fatal signals, SIGSEGVs, access violations,
  abnormal termination, aborts, and unknown draws. This proves startup-stage
  and thermal-window progress only: no title, FPS, gameplay, flicker, field,
  menu, battle, or stability credit.
- The user requested one retry. A stricter cooldown check rejected launch at
  silicon `47.0 -> 44.5 -> 41.3 C` despite the downward trend; PID remained
  absent. Do not retry until three samples are below `35 C` with rise no more
  than `1 C`. Then keep RSX `256`, SPU `64`, and the `75 C` fail-stop, but
  issue one guarded Start press after `12 s` to skip the sustained black
  startup sequence before resuming the title visual gate.

### 2026-07-17 - bounded-SPU Start-skip retry thermal variance

- Capture:
  `debug-captures/android-speed-sprint/20260717-140952-thor-input-oldest-spu-bounded-title-start-skip`.
  A preceding wrapper attempt rejected its own `35.1 C` first preflight sample
  and did not launch. The charged retry later passed battery/skin/silicon
  `24/30/34.1`, `24/30/34.7`, and `24/30/34.7 C` with rise at or below `1 C`.
- Exact controls reproduced the prior route: Vulkan driver cache seed
  `4,899,180` bytes, first checkpoint `256`, RSX oldest preload `256 of 939`,
  two automatic workers, and SPU oldest preload `64 of 1,165` with `1,101`
  retained for normal on-demand LLVM compilation.
- The startup log is timing-equivalent to the prior bounded route. SPU limit
  activation was at emulated `2.177738 s`, interpreter construction at
  `2.316938 s`, and the workers finished all `64` programs at `2.740202 s`, a
  `0.423 s` bounded rebuild. Runtime SPU misses followed near `3.097 s`.
- Process identity was established at `14:10:04.992602`; silicon was `65.8 C`
  at `14:10:07.756397` and reached `76.3 C` at `14:10:10.730028`. The `75 C`
  guard therefore force-stopped the process after only `5.737 s`, before the
  macro's `12 s` wait completed or its Start press executed. Immediate
  post-stop silicon was `51.8 C`; PID was absent and route controls reset.
- Targeted scans found zero fatal signals, SIGSEGVs, access violations,
  abnormal termination, aborts, and unknown draws. There is no screenshot,
  title, FPS, gameplay, flicker, menu, battle, or stability result.
- The same cache configuration previously survived `73.449 s` while this retry
  survived `5.737 s`, despite near-identical early emulator timing. Treat the
  difference as unmatched device power/cooling variance, not an SPU/RSX cache
  regression. A later read-only stopped-device audit found AYN
  `performance_mode=0`, `fan_mode=4`, battery saver off, normal Qualcomm
  `walt` governors, no Android GameManager intervention for RPCSX, and silicon
  still `48.2 C`; it cannot reconstruct the missing prelaunch state.
- Host safety/tooling follow-up records one read-only
  `prelaunch-power-state.txt` before the three-sample thermal preflight. It
  captures AYN performance/fan settings plus CPU/GPU governor and maximum
  frequencies without changing policy. No more device route is allowed in
  this thermal round. A future separately cool route must match this state and
  should send the bounded Start input earlier than `12 s` if input readiness is
  independently justified.
