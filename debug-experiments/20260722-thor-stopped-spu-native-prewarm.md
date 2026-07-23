# Thor Stopped-Emulator SPU Native-Object Prewarm

### 2026-07-22 - stopped-spu-native-prewarm

- Status: proposed
- Scope: spu-codegen
- Hypothesis: the pre-title CPU thermal burst can be reduced by compiling exact
  SPU native objects during the already bounded stopped-emulator preparation
  action, so a later game boot can reuse backend objects instead of emitting
  them while RSX/PPU startup is also active.
- Changed files/settings: `CompilationQueue::compile` now invokes the existing
  SPU cache initializer only after exact BLUS30161 PPU/firmware preparation,
  only with the explicit native-object property and LLVM SPU decoder. The
  controller selects at most 64 oldest boot programs, applies the existing
  100 ms compile budget and `0x7` cache-worker affinity, proves ordered native
  evidence, and resets every property after force-stop.
- Rollback: revert this slice, or leave
  `debug.rpcsx.thor.spu_native_object_cache=off`; normal game boot and runtime
  SPU misses remain unchanged and uncached.
- Windows result: not applicable; host Android ARM64 native build and optimized
  ARM64-only ThorTest APK assembly passed.
- Thor result: not run. No ADB or device action occurred, and the successor APK
  is not installed.
- Visual correctness: unmeasured.
- FPS/frame-time: unmeasured.
- Capture paths: none.
- Decision: retain as the next exact host candidate. This is a preparation-path
  optimization and grants no speed, FPS, thermal, flicker, gameplay, or
  stability credit until independently cool device proof.
- Next: in one future cool round, perform only a strict no-launch install and
  verify exact APK identity. In a later cool round, run one guarded cache
  preparation requiring the SPU activation/completion, bounded preload, exact
  affinity, object load/build counts, property reset, and final PID absence.
  Only after another cooldown should a matched title/gameplay proof run.

## Implementation Boundary

The native preparation path now rejects a managed profile unless both the PPU
and SPU decoders match the expected LLVM variants. PPU/firmware completion is
logged first, then the title-gated SPU native-object phase is bracketed by
separate activation and completion markers. `spu_cache::initialize()` reuses
the existing exact final-IR v2 object-cache machinery, oldest-program ordering,
worker cap, compile deadline, corruption checks, and atomic writes. It does not
create a new JIT tier or change runtime-miss behavior.

The host controller explicitly applies and verifies:

- `debug.rpcsx.thor.spu_native_object_cache=on`
- `debug.rpcsx.thor.spu_cache_preload_limit=64`
- `debug.rpcsx.thor.spu_cache_compile_budget_ms=100`

Successful evidence requires the native cache enabled row, the `64`-program
bound, `100 ms` budget, cache-worker affinity
`requested=0x7,effective=0x7`, and ordered SPU completion after PPU completion.
It records exact warm-object loads and worker-built program counts. Its
`finally` path force-stops first, resets the three properties to `off/0/0`,
reads them back, and rejects an otherwise successful run if cleanup is not
exact.

## Host Verification

No Thor contact occurred.

- `tools/test_thor_spu_native_object_cache.ps1`: pass.
- `tools/test_thor_eternal_sonata_firmware_cache_prepare.ps1`: pass.
- `tools/test_thor_cache_prepare_route.ps1`: pass.
- `tools/invoke_thor_cache_prepare.ps1 -Action Status`: pass with
  `device_contact=False`.
- `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: `BUILD SUCCESSFUL`.
- `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a
  -PbuildBundledRpcsxCore=true`: `BUILD SUCCESSFUL` in 14 seconds.
- `tools/test_thor_arm64_apk.ps1`: pass.
- `tools/test_thor_optimized_apk_contract.ps1`: pass.
- `tools/test_thor_cool_title_candidate_artifact.ps1`: pass.
- `tools/test_thor_cool_title_profile.ps1`: pass.
- `git diff --check`: pass.

Exact host-only successor artifacts:

- APK size: `72,834,668` bytes
- APK SHA-256:
  `8F1C9838EFC428AB5E4DDBFF2E433A4BDA1A79BD41FB086CEF820653C01D1C25`
- merged ARM64 core size: `1,304,246,344` bytes
- merged ARM64 core SHA-256:
  `5C1CFB306E28BAA2286907884918F4CC1B2AC16F866D4DBE8646AD2929959AE3`
- stripped/packaged core size: `62,983,832` bytes
- stripped/packaged core SHA-256:
  `863AB71FA18F91B7663F26F023D357887C069C72EAD792F815D724DA2331D552`

The installed Thor APK remains the prior
`A7216402BDBFE9F14762D9C2C2F2E5A2B857D828D327E2D9A6E50C8C6433D15C`
candidate. The new manifest therefore makes any premature preparation action
fail exact installed-APK identity before the SPU properties are applied.

### 2026-07-22 - exact-no-launch-install

- Status: android-pass
- Scope: spu-codegen
- Hypothesis: install the exact SPU-prewarm successor without launching RPCSX,
  preserving a cool device and a clean identity boundary for a later
  stopped-emulator seed.
- Changed files/settings: installed exact APK
  `8F1C9838EFC428AB5E4DDBFF2E433A4BDA1A79BD41FB086CEF820653C01D1C25`.
  No emulator setting was changed. The cache controller now treats the newest
  exact no-launch install as a cooldown source as well as the newest cache run.
- Rollback: reinstall the prior exact APK through the same strict no-launch
  procedure. No RPCSX process or new cache phase was started.
- Windows result: not applicable.
- Thor result: strict no-boot gate passed at
  `33.3 -> 33.9 -> 33.3 C` (maximum `33.9 C`, rise `0.0 C`) with
  battery/skin `23.0/30.0 C`. Expected, host, and installed APK hashes match.
  PID was absent before and after installation. Post-install silicon was
  `34.9 C`.
- Visual correctness: not exercised; no activity launched.
- FPS/frame-time: not measured.
- Capture paths:
  `debug-captures/android-speed-sprint/20260722-232951-thor-input-strict-cool-gate`;
  `debug-captures/android-speed-sprint/20260722-233018-stopped-spu-prewarm-successor-thortest-apk-install`.
- Decision: `installed-exact-no-launch` / `route-tooling` /
  `not-comparable`. Installation grants identity only, with no speed, FPS,
  temperature-win, flicker, gameplay, cache-seed, or stability credit.
- Next: no Thor contact before
  `2026-07-23T00:00:25.9542488-04:00`. After that independent interval and a
  fresh strict cool gate, run at most one stopped-emulator cache preparation.
  Reserve title and gameplay proof for another independently cool round.

## Post-Install Cooldown Enforcement

The cache controller previously considered only the latest
`firmware-ppu-prewarm` capture. That could permit cache compilation immediately
after a new APK install when the older cache timestamp was already mature.
Host-only logic now validates the latest `*-apk-install` README as no-launch
evidence, parses its creation time, and selects the newer of install or cache
as the 30-minute cooldown source. Reuse continuity still comes only from the
latest cache README.

After the install, host-only status reports:

- cooldown source kind: `install`
- cooldown source:
  `20260722-233018-stopped-spu-prewarm-successor-thortest-apk-install`
- ready: `False`
- ready at: `2026-07-23T00:00:25.9542488-04:00`

The focused route contract covers install-newer, cache-newer, and no-history
selection. The cooldown decision remains before ADB resolution, malformed
install evidence fails closed, and `git diff --check` passes. No follow-up ADB
query or emulator action ran after the installer completed.
