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

### 2026-07-22 - packaged-spu-prewarm-artifact-proof

- Status: proposed
- Scope: spu-codegen
- Hypothesis: reject a stale or incorrectly packaged Thor candidate before any
  device action by proving the stripped core contains the entire stopped-SPU
  prewarm lifecycle and property contract.
- Changed files/settings:
  `tools/test_thor_cool_title_candidate_artifact.ps1` now scans the packaged
  core once for all required PPU/SPU markers instead of reopening and rereading
  the 62,983,832-byte ELF once per marker. It requires SPU activation and
  completion, native-cache enablement, preload limit, compile budget, cache
  affinity, all three Android properties, and the v2 cache namespace/key.
- Rollback: revert this test-only slice. Emulator runtime behavior is unchanged.
- Windows result: host-only artifact, native-cache, firmware-preparation, route,
  optimized-variant, and exact ARM64 APK contracts pass.
- Thor result: not run. Cooldown status reported `device_contact=False`,
  source `install`, and `cache_cooldown_ready=False`.
- Visual correctness: not exercised.
- FPS/frame-time: unmeasured; this is artifact identity evidence only.
- Capture paths: none.
- Decision: retain as fail-closed `route-tooling`. Exact APK
  `8F1C9838...C01D1C25` and packaged core `863AB71F...33D552` pass the expanded
  marker contract. Grant no speed, FPS, thermal, gameplay, flicker, or stability
  credit.
- Next: wait until the install cooldown expires, require one fresh strict cool
  gate, and run at most one stopped-emulator cache preparation. Do not boot the
  game in that round.

### 2026-07-23 - first-stopped-spu-seed-evidence-failure

- Status: failed
- Scope: spu-codegen
- Hypothesis: reuse the complete PPU cache and seed bounded SPU native objects
  off-boot without heating the device or entering gameplay.
- Changed files/settings: the run requested SPU native objects `on`, oldest
  preload `64`, and a `100 ms` compile budget. The controller had not applied
  `debug.rpcsx.thor.cache_worker_affinity_mask=7`, so the SPU pool used the
  default scheduler. The successor controller now applies/verifies `7`, limits
  the pool proof to three workers, and resets/readbacks `0`; Android native-cache
  activation is promoted to the durable `Always` log level.
- Rollback: the failed run force-stopped RPCSX and read back native cache
  `off`, preload `0`, and budget `0`; PID was absent. The successor retains the
  same finally-path cleanup and adds affinity reset to `0`.
- Windows result: not applicable. All focused host contracts pass after repair.
- Thor result: strict no-boot gate passed at `32.7 -> 32.1 -> 32.9 C`.
  Cache preflight passed at `32.5 -> 32.7 -> 33.5 C`. PPU preparation reused
  `209` validated modules, completed all `142/142` firmware files, and reached
  `64/64` module progress. The SPU phase found `1,165` unique programs and
  workers built `6/64` within the `100 ms` budget. Runtime peak was `36.3 C`;
  post-stop was `33.9 C`; no native fatal or process death occurred.
- Visual correctness: not exercised; game boot was `no`.
- FPS/frame-time: unmeasured.
- Capture paths:
  `debug-captures/android-speed-sprint/20260723-000042-thor-input-strict-cool-gate`;
  `debug-captures/android-speed-sprint/20260723-000120-firmware-ppu-prewarm`.
- Decision: `failed-evidence-gate` / `not-comparable`. The callback and both
  native phases completed, but exact native-cache enablement and three-worker
  affinity were not proven. The six compiled programs are useful side-effect
  evidence, not a verified cache seed or speed/thermal win. Grant no FPS,
  startup-speed, gameplay, flicker, stability, or end-to-end temperature credit.
- Next: build an exact successor with durable native-cache evidence, install it
  only after a new cooldown and strict no-launch gate, then reserve any seed
  rerun for a still later independently cool round. Do not contact Thor again
  in this round.

### 2026-07-23 - affinity-proof-successor-host-artifact

- Status: proposed
- Scope: spu-codegen
- Hypothesis: make the stopped-emulator SPU native-object seed fail closed
  unless its workers are proven on the three-core `0x7` affinity set and
  native-cache activation remains visible under quiet Android logging.
- Changed files/settings: the cache controller now applies and verifies
  `debug.rpcsx.thor.cache_worker_affinity_mask=7`, requires
  `requested=3, workers=3, mask=0x7`, and resets/readbacks affinity `0` after
  force-stop. The Android native-cache activation row now uses durable
  `Always` logging; desktop keeps its existing notice level. Exact artifact
  gates require both behaviors in the packaged core and controller.
- Rollback: reinstall the preceding exact APK through the strict no-launch
  gate. Runtime defaults remain native cache `off`, preload `0`, compile budget
  `0`, and cache-worker affinity `0`.
- Windows result: not applicable. Optimized ARM64 native build passed in
  `1m 8s`; incremental ARM64-only ThorTest packaging passed in `12s`.
  All `66/66` Thor host contracts, exact ARM64 APK identity, optimized-variant,
  cool-title profile, cache-preparation route, native-object cache, affinity,
  and artifact gates pass.
- Thor result: not run. No ADB, install, launch, or device query occurred.
- Visual correctness: not exercised.
- FPS/frame-time: unmeasured.
- Exact host artifact:
  - APK: `72,834,432` bytes,
    `D6584048525CFDFF5342D39F350391B44A366038BCE11A24B9F8E3363F4E77CE`
  - merged ARM64 core: `1,304,246,096` bytes,
    `BC9D58E5298C60A36AA4106D104648871CA210DA3440F623FC4AB736F0DE8CF1`
  - stripped/packaged core: `62,983,800` bytes,
    `74B7EC4DC43C8ED7BD13B6135C19B90CE31EB196811C25623554074A56678C0C`
- Decision: `host-verified-successor` / `uninstalled` / `not-comparable`.
  This closes the two evidence gaps exposed by the first seed but grants no
  speed, startup, FPS, thermal-win, gameplay, flicker, or stability credit.
- Next: after a new independent cooldown, install this exact APK under one
  strict no-launch round. Reserve the stopped-emulator seed for a different
  cool round, and require exact three-worker plus durable native-cache evidence
  before any later warm title/gameplay comparison.

### 2026-07-23 - exact-affinity-proof-successor-no-launch-install

- Status: android-pass
- Scope: spu-codegen
- Hypothesis: install the exact affinity/evidence successor without starting
  RPCSX, preserving a clean identity and thermal boundary for a later stopped
  SPU seed.
- Changed files/settings: installed exact APK
  `D6584048525CFDFF5342D39F350391B44A366038BCE11A24B9F8E3363F4E77CE`.
  No emulator setting changed and no activity launched. Startup controls were
  observed at safe defaults, including SPU native cache `off`, preload/budget
  `0/0`, and cache-worker affinity `0`.
- Rollback: reinstall the preceding exact APK through the same strict
  no-launch procedure. RPCSX remained stopped throughout this installation.
- Windows result: not applicable.
- Thor result: strict no-boot gate
  `20260723-003158-thor-input-strict-cool-gate` passed silicon
  `31.9 -> 32.1 -> 32.3 C` (maximum `32.3 C`, rise `+0.4 C`) with
  battery/skin `23.0/30.0 C`. Install capture
  `20260723-003221-affinity-proof-spu-prewarm-successor-thortest-apk-install`
  proves expected, host, and installed hashes match; PID was absent before and
  after; post-install silicon was `36.1 C`.
- Visual correctness: not exercised; emulator launch was `no`.
- FPS/frame-time: unmeasured.
- Decision: `installed-exact-no-launch` / `route-tooling` /
  `not-comparable`. Grant no speed, FPS, thermal-win, cache-seed, gameplay,
  flicker, or stability credit.
- Next: no Thor contact before
  `2026-07-23T01:02:28.4844422-04:00`. After that independent interval and a
  fresh strict cool gate, run at most one stopped-emulator SPU seed. Require
  durable native-cache activation, `requested=3, workers=3, mask=0x7`, exact
  property cleanup, final PID absence, and no game boot. Reserve title and
  gameplay proof for later cool rounds.

### 2026-07-23 - cumulative-spu-native-object-continuity-floor

- Status: proposed
- Scope: spu-codegen
- Hypothesis: a repeated stopped-emulator seed is useful only if it proves
  prior native objects persisted instead of recompiling the same prefix.
- Changed files/settings: host-only cache progress parsing now derives the next
  SPU native-object reuse floor from the latest safe completed phase:
  `loaded + built`, capped at the selected `64`. The prior capture contributes
  `0 + 6`, so device-free Status now reports
  `minimum_required_spu_native_objects=6`. A completed seed fails closed below
  that floor. Partial rows, missing completion/cleanup, native fatal, process
  death, or game boot evidence are rejected.
- Rollback: revert the host controller/progress/test slice. Installed APK,
  native core, runtime defaults, and cached object bytes are unchanged.
- Windows result: not applicable. Focused cache-route replay and all `66/66`
  Thor host contracts pass; PowerShell AST parsing and `git diff --check` pass.
- Thor result: not run. No ADB, install, launch, or device query occurred after
  the completed no-launch install round.
- Visual correctness: not exercised.
- FPS/frame-time: unmeasured.
- Decision: retain as fail-closed `route-tooling`. This proves cache
  accumulation on the next seed but grants no speed, FPS, thermal-win,
  gameplay, flicker, or stability credit.
- Next: keep the installed exact APK frozen and honor the existing cooldown.
  After `2026-07-23T01:02:28.4844422-04:00`, one strict cool stopped-emulator
  seed must load at least six native objects, prove the exact three-worker
  affinity pool, build any new objects inside the `100 ms` budget, clean up all
  properties, leave PID absent, and never boot the game.

### 2026-07-23 - stopped-spu-native-cache-path-counterproof

- Status: failed
- Scope: spu-codegen
- Capture: `20260723-010252-firmware-ppu-prewarm`
- Exact candidate: installed APK
  `D6584048525CFDFF5342D39F350391B44A366038BCE11A24B9F8E3363F4E77CE`
  matched the pinned host artifact.
- Thermal result: strict preflight passed at
  `31.7 -> 32.3 -> 31.5 C`; the bounded action finished in `1.544 s`, its
  single runtime sample was `35.9 C`, post-stop was `32.9 C`, and PID was
  absent. No thermal threshold fired.
- PPU result: `209` validated objects reused, firmware `142/142`, current
  module workload `64/64`, callback finished, no compile workers required.
- SPU result: activation/completion, preload `64/1165`, `100 ms` budget, and
  affinity `requested=0x7,effective=0x7` appeared. The pool was only `2/2`,
  native cache enablement was absent, zero native objects loaded, and the same
  six programs rebuilt. Properties reset; no fatal, process death, or game
  boot occurred.
- Root cause: `spu_runtime` was constructed before the stopped route called
  `ConfigurePPUCache()`, so its cached path remained empty and
  `enable_native_object_cache()` returned false. Separately, the title's
  normal `Max LLVM Compile Threads: 2` capped the pool because the controller's
  intended three-worker limit was never passed into the core.
- Decision: retain as `failed-evidence-gate` / `safe-counterproof` /
  `not-comparable`. It grants no speed, FPS, gameplay, flicker, stability, or
  thermal-win credit. Do not retry or contact Thor again in this device round.

### 2026-07-23 - lazy-native-cache-path-and-explicit-worker-successor

- Status: proposed
- Scope: spu-codegen
- Hypothesis: resolving the cache path at opt-in time and explicitly overriding
  only the stopped-prewarm worker pool will allow exact native objects to be
  written without changing normal title runtime scheduling.
- Changed files/settings: `enable_native_object_cache()` now refreshes an empty
  cache path after cache configuration. A BLUS30161/property-gated worker limit
  overrides the normal two-thread cap only when bounded preload plus compile
  budget are active. The host controller sets/verifies/resets the limit at `3`;
  the no-launch installer captures its default state. Failed or incomplete
  native-cache captures cannot establish a reuse floor, and historical scanning
  selects only the newest successful safe continuity capture.
- Exact host artifact:
  - APK: `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`
    / `72,835,952` bytes.
  - merged core:
    `9A22B5B29BCD5B9F959AA523B550BCC0E86F9BD31EA372A8B40EB439042E1065`
    / `1,304,256,560` bytes.
  - packaged core:
    `294723803F285762162B56158CEEB3F832444A4CC01E988A72B79E240AF6EDDF`
    / `62,984,952` bytes.
- Host result: optimized ARM64 native build and ARM64-only APK packaging pass;
  exact artifact, optimized variant, ABI, focused route/native-cache contracts,
  and all `66/66` Thor host contracts pass. Device-free Status reports
  `spu_continuity_capture=none`, floor `0`, and worker limit `3`.
- Thor result: not run. The successor is uninstalled and device-unmeasured.
- Decision: retain as host-only `route-tooling`. No speed, FPS, gameplay,
  flicker, stability, or thermal-win credit.
- Next: honor the failed seed's independent cooldown. In one later strict cool
  round, install this exact APK without launching it. In a still later cool
  round, one stopped seed must prove native-cache enabled, exact three-worker
  affinity, durable builds, cleanup, no fatal/game boot, and PID absence.

### 2026-07-23 - lazy-native-cache-successor-installed-no-launch

- Status: installed-exact-no-launch
- Scope: route-tooling
- Strict gate:
  `20260723-013345-thor-input-strict-cool-gate` passed at
  `30.9 -> 31.3 -> 31.1 C` (maximum `31.3 C`, net rise `+0.2 C`) with
  battery/skin `23.0/30.0 C`.
- Install capture:
  `20260723-013419-lazy-native-cache-path-spu-prewarm-successor-thortest-apk-install`.
- Exact identity: expected, host, and installed APK hashes all equal
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`;
  size is `72,835,952` bytes.
- Safety: PID absent before/after, emulator launch `no`, post-install silicon
  `32.7 C`, battery/skin `23.0/30.0 C`. Startup properties were safe:
  RSX/SPU limits and budgets zero, stopped-prewarm worker limit unset,
  SPU native cache off, cache affinity zero, and experimental runtime paths
  off.
- Decision: retain as exact installed identity only. No native-cache
  persistence, speed, FPS, gameplay, flicker, stability, or thermal-win credit.
- Next: stop this device round. Device-free Status selects this install as the
  30-minute cooldown source and refuses a seed before
  `2026-07-23T02:04:26.6355691-04:00`. In a later independently cool round,
  run at most one stopped seed and require native-cache enabled, three workers
  on affinity `0x7`, property cleanup, no fatal/game boot, and PID absence.

### 2026-07-23 - cool-title-consumes-stopped-spu-native-objects

- Status: proposed
- Scope: route-tooling
- Hypothesis: the stopped prewarm cannot reduce title-start work unless the
  exact later title route opts into the same durable SPU native-object cache.
- Root cause: `ThorCoolTitle` explicitly forced SPU native cache `off`, so it
  would ignore the objects created by a successful stopped seed even though
  the global default-off control and forwarding path were correct.
- Changed files/settings: only the pinned `ThorCoolTitle` profile now requires
  `AndroidSpuNativeObjectCache=on`. Global and ordinary-route defaults remain
  `off`. The profile summary reports the state, the capture analyzer requires
  both effective-property and startup-property `on`, and explicit attempts to
  turn it off fail closed.
- Rollback: revert this host-only profile/analyzer/test slice. Installed APK,
  native core, cached objects, and runtime defaults are unchanged.
- Host result: PowerShell AST parsing passed for all five changed scripts;
  focused profile, analyzer, and native-cache contracts pass; device-free
  `AndroidProfileStatus` pins APK
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`,
  packaged core
  `294723803F285762162B56158CEEB3F832444A4CC01E988A72B79E240AF6EDDF`,
  and reports `spu_native_object_cache=on`; all `66/66` Thor host contracts
  pass; `git diff --check` passes.
- Thor result: not run. No build, install, launch, ADB, or device query
  occurred, so the exact installed successor remains frozen and cooling.
- Visual correctness: not exercised.
- FPS/frame-time: unmeasured.
- Decision: retain as fail-closed `route-tooling`. This closes the
  cache-consumption gap but grants no speed, startup, FPS, thermal-win,
  gameplay, flicker, or stability credit.
- Next: after the independent cooldown, run one stopped seed requiring durable
  native-cache enablement, requested/workers `3/3`, affinity `0x7`, safe
  cleanup, final PID absence, and no game boot. Reserve the native-cache-on
  title proof and field/menu/first-battle comparisons for later cool rounds.

### 2026-07-23 - cool-title-native-object-reuse-proof-gate

- Status: proposed
- Scope: route-tooling
- Hypothesis: a title capture must prove actual native-object activation and
  reuse, not merely a requested/effective Android property, before it can
  authorize any later speed comparison.
- Changed files/settings: the host-only title analyzer now requires the core's
  durable native-cache activation row and at least one exact
  `LLVM: Loaded module: ...obj` row, matching the stopped-prewarm controller's
  existing object-load pattern. Synthetic captures independently remove the
  activation and load rows and must classify `activation-incomplete`.
- Rollback: revert the analyzer/test/evidence-count slice. No runtime setting,
  APK, core, or device cache changed.
- Host result: changed PowerShell scripts parse; focused analyzer and evidence
  logging contracts pass; all `66/66` Thor host contracts and
  `git diff --check` pass.
- Thor result: not run. No build, install, launch, ADB, or device query
  occurred.
- Decision: retain as fail-closed proof hardening. Grant no speed, FPS,
  thermal-win, gameplay, flicker, or stability credit.
- Next: keep the exact installed APK frozen. After cooldown, prove one stopped
  seed; in a later title round require both native-cache activation and at
  least one loaded native object before comparison readiness.

### 2026-07-23 - cool-title-analyzer-68c-alignment

- Status: proposed
- Scope: route-tooling
- Root cause: `ThorCoolTitle` correctly lowered the hard silicon ceiling to
  `68 C`, but its capture analyzer and synthetic README/thermal evidence still
  required the superseded `72 C` value. A real safe route would therefore fail
  analysis despite applying the stricter profile.
- Changed files/settings: host analyzer and synthetic ready/thermal/preflight
  fixtures now require and exercise `68 C`. Runtime profile remains unchanged.
- Host result: both scripts parse; focused analyzer replay and all `66/66`
  Thor host contracts pass; `git diff --check` passes.
- Thor result: not run. No build, install, launch, ADB, or device query.
- Decision: retain as host-only route repair. Grant no speed, FPS,
  thermal-win, gameplay, flicker, or stability credit.
- Next: keep the exact installed APK frozen and honor the independent cooldown
  before the single stopped-prewarm seed.

### 2026-07-23 - durable-spu-native-object-seed-success

- Status: android-pass
- Scope: spu-codegen
- Capture: `20260723-020444-firmware-ppu-prewarm`
- Exact identity: expected, host, and installed APK hashes all matched
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`.
- Thermal result: strict preflight passed at
  `30.9 -> 31.1 -> 31.3 C`; runtime completed in `1.535 s` with one
  `35.1 C` sample and zero samples at or above `45 C`; post-stop silicon was
  `32.5 C`, battery/skin `23.0/30.0 C`.
- PPU result: `209` validated objects reused; firmware scan `142/142`; current
  workload `64/64`; no PPU compile worker was needed.
- SPU result: preparation activated/completed; native cache enabled; bounded
  preload/budget `64/100 ms`; exact worker pool requested/workers `3/3`;
  affinity requested/effective `0x7/0x7`; zero prior native objects loaded on
  this first valid seed; seven new native programs built and persisted.
- Safety result: all SPU properties reset (`off/0/0/0/0`), callback finished,
  PID absent before/after, native fatal/process-death false, and no game boot.
- Host continuation: device-free Status selects this successful capture,
  raises `minimum_required_spu_native_objects` from `0` to `7`, and starts the
  next cooldown until `2026-07-23T02:35:03.3577951-04:00`.
- Decision: retain as `cache-prepared-exact-no-game-boot` / `android-pass`.
  This proves safe persistent SPU native-object creation, but grants no speed,
  startup, FPS, gameplay, flicker, stability, or thermal-win credit because no
  title or gameplay scene ran.
- Next: no more device contact this round. In one later independently cool
  round, run the pinned native-cache-on `ThorCoolTitle` proof. Require at least
  one `LLVM: Loaded module: ...obj`, activation marker, exact property/runtime
  gates, title visuals, no fatal/flicker, `68 C` ceiling, and final PID absence.
