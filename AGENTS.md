# RPCSX Thor Agent Notes

This file is the compact operating contract. It is not an experiment ledger.
Put dated run details in `debug-experiments/`, not here.

## Communication

- Be concise, factual, and specific.
- State what changed, what was verified, and what remains.
- Do not use hype, filler, or long historical summaries.

## Git

- Work on `master` only for this repo.
- Remote push target: `git@github.com:noeldvictor/rpcsx-ui-android-thor.git`.
- Commit and push completed work to `origin master`.
- Do not create feature branches, PR branches, or extra RPCSX forks unless the user explicitly asks.
- Do not commit game data, firmware, generated builds, Gradle caches, `.cxx`, runtime caches, APKs, or capture blobs.

## Source Layout

- Vendored RPCSX core: `app/src/main/cpp/rpcsx`.
- Android JNI full-core bridge: `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`.
- Lightweight loader wrapper: `app/src/main/cpp/native-lib.cpp`.
- Upstream RPCS3 comparison checkout: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Refresh vendored core with `tools/sync_rpcsx_core.ps1`.
- Hydrate core deps with `tools/hydrate_rpcsx_core_deps.ps1`.
- Normal debug build: `.\gradlew.bat :app:assembleDebug`.
- Fast native-core hot swap: `.\tools\build_push_thor_core.ps1 -Label NAME`.
- Reset hot swap: `.\tools\build_push_thor_core.ps1 -ResetToBundled`.

## PS3 Sprint Gate

- Active goal: make Eternal Sonata `BLUS30161` stable and faster on AYN Thor while preserving correct field, title Options/menu, first-battle visuals, and bounded thermals.
- The clean-current-upstream Windows 200% gate is cleared. Thor work is permitted only as one short, temperature-guarded validation per cool round; do not heat-soak or immediately repeat a route.
- Keep RPCS3 gameplay on screen 1 with `-WindowsGameScreen 1`.
- Use repo-local skills only: `codex-goal-loop`, `ps3-debug-knowledge`, `ps3-speed-proof-gate`, `ps3-rsx-experiment-gate`, `ps3-continual-harness-refiner`, and `ps3-spu-contract-compiler`.
- Always start by checking for an active meaningful run/edit. Do not duplicate live work.
- Newest failed visual/log/window/route evidence overrides older opportunities.

## Sprint Workflow

1. Read this file, the relevant `.agents/skills/*/SKILL.md`, and the narrowest `debug-experiments/` ledger.
2. Run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8`.
3. Take one concrete step: route repair, boundary bisection, harness fix, contract extraction, analysis, or one thermally gated experiment.
4. Verify screenshots, fatal logs, host grade, and counters.
5. Classify honestly: `speed-win`, `windows-micro-win`, `stackable-cpu-pressure`, `gpu-migration-credit`, `valid-field-triage`, `valid-options-counterproof`, `route-tooling`, `failed`, `stack-regression`, `parked`, or `not-comparable`.
6. Update the narrowest ledger before stopping.
7. Commit and push after each completed work round.

## Current PS3 State

- Exact installed APK `59D5658E...91BD02` ran once under the pinned serial and
  strict cool gate in `20260720-145444-thor-input-custom`. Preflight was
  `33.9 -> 33.9 -> 33.9 C`, silicon peaked at `50.6 C`, post-stop was `40.5 C`,
  the installed hash matched, checkpoint `1` was durable, and PID was absent
  after the controlled stop. Visual replay proves frames 02-04 are the RPCSX
  game library, not Eternal Sonata: current classification is
  `launcher_ui_present=True`, `title_menu_present=False`, and the three-frame
  readiness replay is not stable. The old `18.913/24.310 s` candidate timings
  are invalid. Capture `20260720-134641-thor-input-custom` contains the same
  launcher pixels (`11.4%` magenta, `58.306%` white row), so its former
  `18.620/24.361 s` title claim is also superseded. Classify both as
  `launcher-ui-instead-of-title` / `failed-visual-gate` / `not-comparable`,
  with no speed, FPS, thermal-win, flicker, gameplay, or stability credit.

- The launcher-aware successor still accepts a known real Eternal Sonata
  title at 1.792% white row and rejects both saved RPCSX launcher captures
  at 58.306%. Exact installed APK 85DB41BB...E5C52 then ran once under
  pinned serial c3ca0370 and the strict cool gate in
  20260720-202356-thor-input-custom. Its device-side hash matched and
  preflight stayed 31.3 -> 31.5 -> 31.7 C, but the nonce-bound handshake
  rejected in 712 ms before game boot because the existing BLUS30161 YAML
  was custom=true / enabled=false / applied=false. The route force-stopped
  before the PPU/title poll or any screenshot; PID was absent and the
  failure-post-stop silicon snapshot was 38.1 C. Classify this as
  managed-profile-custom-config-refusal / failed / not-comparable, with no
  speed, FPS, flicker, gameplay, stability, or thermal-win credit.

- The host repair now requests the debug-only custom-to-managed transition
  explicitly. It reuses the existing supported replacement path, which
  backs up the user YAML before writing the managed Thor profile; normal
  release launches and non-replacement callers are unchanged. All 63/63
  Thor host contracts pass, :app:compileThortestKotlin completed in 9 s,
  and the explicit ARM64-only :app:assembleThortest build completed in
  14 s. New exact host APK 089655E2...6F00EF is 72,829,872 bytes; its
  DEX contains the request extra and title-ID replacement method. Merged
  core CB06FE9C...C5BBF2 / 1,304,043,704 bytes and packaged core
  5F7938BB...6F6CA6 / 62,978,792 bytes are unchanged. The exact APK is now
  installed after strict no-boot gate 20260720-210930 passed silicon
  `32.1 -> 32.1 -> 31.9 C` with battery/skin `22.0/30.0 C`. Install capture
  20260720-210942 proves expected, host, and installed hashes all match,
  RPCSX PID was absent before and after, no activity launched, and post-install
  silicon was 33.7 C. Classify this as `installed-exact-no-launch` /
  `route-tooling`, with no speed, FPS, gameplay, stability, flicker, or thermal
  credit. Its later self-stopping proof is classified below.
- Exact installed APK `089655E2...6F00EF` ran once in
  `20260720-211548-thor-input-custom`. The pinned hash matched, strict
  preflight was `31.7 -> 32.3 -> 31.7 C`, and the nonce-bound debug boot was
  accepted in `689 ms`, but the first frame was still pre-title. Silicon rose
  from `47.0 C` to `69.5 C` before the ten-second wait completed, so the
  `68 C` early guard force-stopped below the `72 C` hard limit. Post-stop was
  `47.4 C`, PID was absent, and targeted fatal hits were zero. The saved log
  proves the managed profile still used `Max LLVM Compile Threads: 2`, multiple
  PPU compile rows were being processed, RSS was about `5,658 MB`, and the
  heat spike was CPU-side while GPU frequency stayed low. Classify the run
  `thermal-stop-before-title` / `failed` / `not-comparable`, with no speed,
  FPS, gameplay, stability, flicker, or thermal-win credit.
- The host successor serializes only BLUS30161 cold PPU LLVM compilation with
  `Max LLVM Compile Threads: 1`; the global Thor default remains two workers.
  Exact ARM64-only APK `A3FC89F7...37DDDF` is `72,829,996` bytes and retains
  merged core `CB06FE9C...C5BBF2` / `1,304,043,704` bytes plus packaged core
  `5F7938BB...6F6CA6` / `62,978,792` bytes. All `64/64` Thor host contracts,
  the 12-row activation analyzer, packaged DEX marker, and exact artifact
  identity pass. It remained uninstalled and device-unmeasured, and is now
  superseded by the efficiency-core-affinity successor below. It received no
  measured speed or temperature credit. Detailed ledger:
  `debug-experiments/20260720-thor-title-proof-log-liveness.md`.
- Install-only gate `20260720-214440-thor-input-strict-cool-gate` refused the
  exact `A3FC89F7...37DDDF` candidate at its first sample: silicon was
  `47.4 C` against the strict below-`35 C` ceiling. Failure post-stop was
  `45.3 C` with battery/skin `23.0/30.0 C`, and PID was absent. The installer
  never ran; installed APK `089655E2...6F00EF` remains unchanged. No retry,
  launch, or follow-up device query ran. Wait for a later independently cool
  install-only round; grant no speed, FPS, stability, or thermal-win credit.
- Exact host successor EDDC3DF...2A7039 keeps the BLUS30161 one-thread PPU
  compile cap and now applies the existing startup cache-worker mask 0x07
  only while cold PPU LLVM objects compile. It captures the current thread's
  affinity first, refuses to change it if capture fails, restores it on scope
  exit, and leaves runtime PPU/SPU/RSX/render threads plus desktop and other
  titles unchanged. The analyzer requires exact requested=0x7,
  effective=0x7 evidence and fails closed on omission or mismatch. ARM64
  native compilation took 114.1 s, optimized packaging took 53 s, and all
  64/64 Thor host contracts pass. The exact APK is 72,829,932 bytes;
  merged core FF170281...EB5627 is 1,304,045,272 bytes and packaged core
  60BA2474...90AC49 is 62,979,016 bytes. It supersedes uninstalled
  A3FC89F7...37DDDF. It is now the exact installed APK after strict no-boot
  gate 20260720-222048 passed silicon 31.5 -> 31.7 -> 31.9 C (maximum 31.9 C,
  rise +0.4 C), with battery/skin 22.0/30.0 C. Install capture
  20260720-222101 proves expected, host, and installed hashes all match, PID
  was absent before and after, no activity launched, and post-install silicon
  was 33.3 C. This grants installed identity only, with no speed, temperature,
  FPS, flicker, gameplay, or stability credit. Stop this device round. After a
  separate independently cool interval, run at most one self-stopping
  ThorCoolTitle proof; do not query or launch again first. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Exact installed EDDC3DF...2A7039 then completed one bounded
  `ThorCoolTitle` counterproof in capture
  `20260720-222640-thor-input-custom`. The strict preflight passed at
  `31.7 -> 32.3 -> 31.7 C`, the debug boot was accepted in `136 ms`, and
  runtime evidence confirmed `Max LLVM Compile Threads: 1` plus exact PPU
  compile affinity `requested=0x7,effective=0x7` for every started module.
  Cold compile peaked at `53.0 C` and then stayed mostly `38.9-45.8 C`, a
  substantial pre-title heat reduction from the prior unpinned two-worker
  route's `69.5 C` early stop. The tradeoff is unacceptable cold-start speed:
  12 modules completed serially, module 13 was still compiling when the
  90-second title gate expired, and no title or gameplay scene was reached.
  The route self-stopped with PID absent and zero targeted fatal hits. Classify
  this `route-failed-before-title` / thermal-progress / not-comparable; grant
  no startup-speed, FPS, gameplay, flicker, stability, or end-to-end thermal
  win. Do not contact Thor again in this device round. A later independently
  cool, single bounded warm-cache continuation may determine whether the newly
  populated objects make title startup practical before changing worker count.
  Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Successor B5B5DB6B...B4074522 restores two BLUS30161 cold PPU LLVM
  workers for throughput while making `0x07` the title's normal Android PPU
  compile mask, even when the diagnostic startup-worker property is off. A
  nonzero property value can still override the compile mask for experiments;
  desktop, other titles, and runtime PPU/SPU/RSX/render scheduling remain
  unchanged, and each compile thread restores its prior affinity on exit. The
  analyzer and artifact gates now require `Max LLVM Compile Threads: 2` plus
  exact `requested=0x7,effective=0x7` runtime evidence. Optimized ARM64 native
  compilation passed in 88 s, corrected ARM64-only packaging passed in 24 s,
  and all 64/64 Thor host contracts pass. Exact APK is 72,829,976 bytes;
  merged core 1F3671B9...333C00 is 1,304,047,216 bytes and packaged core
  EA4451EA...81E615 is 62,979,016 bytes. It is now the exact installed APK
  after strict no-boot gate 20260720-230635 passed silicon
  `33.5 -> 34.1 -> 34.1 C` (maximum `34.1 C`, rise `+0.6 C`), with
  battery/skin `23.0/30.0 C`. Install capture
  20260720-230647 proves expected, host, and installed hashes all match, PID
  was absent before and after, no activity launched, and post-install silicon
  was `35.9 C`. This grants installed identity only, with no speed,
  temperature, FPS, flicker, gameplay, or stability credit. Stop this device
  round. After a separate independently cool interval, run at most one
  self-stopping ThorCoolTitle proof requiring two-thread plus exact PPU `0x07`
  activation; do not query or launch again first. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Exact installed B5B5DB6B...B4074522 completed one bounded ThorCoolTitle
  counterproof in capture `20260721-105440-thor-input-custom`. Exact device
  identity matched, strict preflight was `30.5 -> 30.1 -> 30.1 C`, and debug
  boot was accepted in `698 ms`. Runtime evidence proved
  `Max LLVM Compile Threads: 2`, managed `Set DAZ and FTZ: true`, both PPU
  compile lanes active, and all 18 affinity rows at exact
  `requested=0x7,effective=0x7`. The warmed cache produced 17 object hits;
  21 variants started, 19 completed, and two remained active at emulator time
  `91.946 s`. The prior one-worker run completed 12, but cache state and module
  mix differ, so this is compilation-progress evidence only. Five saved frames
  remained pre-title while the progress metric rose `2.932% -> 23.453%`.
  Silicon peaked at `47.4 C`, no thermal guard fired, zero targeted fatal hits
  were found, and the failure path left PID absent. Classify
  `route-failed-before-title` / thermal-progress / not-comparable; grant no
  startup-speed, FPS, thermal-win, flicker, gameplay, or stability credit. Do
  not contact Thor again in this device round. Next work is host-only analysis
  of the pre-title firmware-PRX compile breadth before another cool proof.
  Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Host successor 3B6ACA6D...C76404 moves the measured firmware-PRX cold work
  into the stopped-emulator Prepare Cache action for BLUS30161. It loads only
  the managed title YAML, mirrors boot's LLVM compatibility fixups, requires
  the exact two-worker/hardware-FTZ cache identity, scans sys/external through
  RPCS3's existing LLE/HLE filter, restores the prior global config, and
  removes duplicate directory enumeration. Custom/stale profiles and missing
  firmware fail closed. Optimized ARM64 native and ARM64-only APK builds plus
  all 65/65 host contracts pass. Exact APK is 72,828,756 bytes; merged core
  4D1B95CE...9AA849 is 1,304,106,936 bytes and packaged core
  00721AA0...159F8 is 62,975,080 bytes. It is host-only and uninstalled; no
  ADB/device/cache action ran, so it earns no startup, FPS, thermal, flicker,
  gameplay, or stability credit. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Exact successor 3B6ACA6D...C76404 is now installed after strict no-boot gate
  20260722-144216 passed silicon 33.1 -> 33.1 -> 32.5 C (maximum 33.1 C,
  rise -0.6 C), with battery/skin 23.0/30.0 C. Install capture
  20260722-144228 proves expected, host, and installed hashes match, PID was
  absent before and after, no activity launched, and post-install silicon was
  36.5 C. This grants installed identity only, with no speed, temperature,
  FPS, flicker, gameplay, or stability credit. Stop this device round; run
  stopped-emulator Prepare Cache only after another independent cooldown.
  Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Host successor 1DCDBBEB...6F4885 adds a debug-only, nonce-bound BLUS30161
  cache-preparation intent that consumes rejected requests, requires the
  managed profile, never starts RPCSXActivity, and records accepted, native
  activated/completed, and callback-finished evidence. Its host controller
  pins serial/APK/path/title, requires three sub-35 C samples with at most
  +1 C rise, stops on sustained 56 C or immediately at 68 C, caps runtime at
  150 seconds, force-stops at both boundaries, and requires final PID absence.
  Optimized ARM64 native/APK builds, Kotlin compilation, artifact identity,
  and all 66/66 Thor contracts pass. Exact APK is 72,831,772 bytes; merged
  core A1BB2700...9D728 is 1,304,111,840 bytes and packaged core
  34D0401E...61A1F is 62,975,480 bytes. It is now the exact installed APK
  after strict no-boot gate 20260722-151931 passed silicon
  34.7 -> 32.7 -> 33.5 C (maximum 34.7 C, rise -1.2 C), with battery/skin
  23.0/30.0 C. Install capture 20260722-151943 proves expected, host, and
  installed hashes match, PID was absent before and after, no activity
  launched, and post-install silicon was 35.1 C. This grants installed identity
  only, with no speed, temperature, FPS, flicker, gameplay, or stability
  credit. Stop this device round; prepare cache and prove title only in two
  additional separate independently cool rounds. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- First deterministic prewarm attempt
  20260722-152936-firmware-ppu-prewarm passed exact installed identity and the
  strict gate at 33.5 -> 32.7 -> 33.1 C, but `adb shell` reparsed the unquoted
  ISO path and failed on `(` before MainActivity started. Runtime was zero
  seconds, post-stop silicon was 33.9 C, PID was absent at both boundaries,
  and no cache preparation or game boot occurred. The host harness now carries
  the path through a tested POSIX single-quoted literal and does not attach a
  stale remote RPCSX log when the current request never reaches app logcat;
  66/66 Thor contracts pass. No APK/core change or retry occurred. Wait for another independently
  cool round before one cache-preparation retry, then reserve title proof for a
  still later round. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.
- The active frame-poll diagnostic logger checks its call counter before
  reading the monotonic clock. Saved matched title evidence has `93,786` calls
  in `47.022 s` (`1,994.5/s`); one initial probe plus one per `1,024` calls
  reduces representative outlined-logger and clock probes to `92` (`>99.9%`)
  while preserving the first activation row and five-second throttle. ARM64
  disassembly proves the call-site branch bypasses both the outlined logger
  and `get_system_time()`. The host successor now emits only the 11 bounded
  activation/failure facts at Always on Android, preserves desktop Notice
  behavior, and keeps Android fatal/error rows durable even when channels are
  silenced; the independent property-driven logcat filter remains intact.
  Exact host-only APK `59D5658E...91BD02` is `72,828,856` bytes; merged core
  `CB06FE9C...C5BBF2` is `1,304,043,704` bytes; stripped/package core
  `5F7938BB...6F6CA6` is `62,978,792` bytes. Optimized ARM64 native/APK builds,
  all `62/62` host contracts, 11/11 packaged activation strings, exact
  artifact identity, and the 35-export surface pass. Prior APK
  59D5658E...91BD02 was installed under no-launch gate 20260720-142534:
  silicon stayed `34.3 -> 34.3 -> 34.3 C`, the installed `base.apk` hash
  matched, PID was absent before/after, and post-install battery/skin/silicon
  were `25.0/30.0/35.9 C`. No activity launched, so this grants identity only,
  not speed or thermal credit; it is superseded by installed candidate
  85DB41BB...E5C52. Reserve one self-stopping title proof for a separate
  independently cool round. Detailed ledger:
  `debug-experiments/20260720-thor-title-proof-log-liveness.md`.

- The default-off ADPF RSX diagnostic now follows the current Android feedback
  contract: BLUS30161 uses its exact 30 FPS period (33,333,333 ns) and reports
  every positive first-draw-to-flip cycle, including deadline misses, instead
  of biasing feedback by dropping over-target frames. Its single activation
  fact uses Android's durable Always path. Thor is Android 13, so API-35
  power-efficiency/structured GPU duration controls remain unavailable; the
  basic API-33 path is only a future matched thermal/frame-time experiment.
  Both explicit-diagnostic and normal ARM64 VKDraw/VKPresent compiles pass;
  LLVM IR proves the target/report contract, and normal objects retain no ADPF
  symbols. The normal build gate remains compile-time off. No APK, ADB, device,
  FPS, or temperature credit exists, and the installed candidate remains
  frozen for its separate cool proof. Detailed ledger:
  debug-experiments/20260718-android-adpf-rsx-power-hint.md.

- Android PPU JIT cache writes now keep raw LLVM objects instead of spending
  CPU on gzip, while desktop writes stay compressed and Android reads retain
  legacy `.gz` fallback. The explicit stopped-emulator Prepare Cache action
  materializes only exact live objects after LLVM validation; normal launch
  never performs directory-wide migration. Corrupt validation removes both
  raw and compressed forms. The saved BLUS30161 Windows cache measured 84
  objects / 18,465,084 compressed bytes versus 82,230,196 raw bytes (4.45x,
  +60.81 MiB). Exact host-only APK `4BCB8D9C...B08816` packages merged core
  `B1B989D2...C07164` / stripped core `900720F0...EC5680`; ARM64 native/APK,
  export, raw-cache, handoff, zero-copy, thermal, and 22 broader contracts
  pass. It is uninstalled/device-unmeasured and no device action ran. Detailed
  ledger: `debug-experiments/20260718-thor-android-raw-ppu-object-cache.md`.
- Fresh official RPCS3 commit `9b3a916af` is adapted so approximate-xfloat
  SPU FMA computes normal FMA independently and selects it or the addend,
  shortening the old compare/mask/FMA dependency chain. Saved first-battle
  SPU windows contain 10 FMA rows / 8 unique addresses. Exact host-only APK
  `A38B8B6F...8AA0B` packages merged core `45363D0F...D267A` / stripped core
  `7E1886A9...5A17B`; ARM64 native/APK and all focused contracts pass. It is
  uninstalled/device-unmeasured, and no device action ran. Detailed ledger:
  `debug-experiments/20260718-arm64-spu-fma-select-upstream-slice.md`.
- The same candidate includes the host successor that makes every fully warm
  PPU object read/inflate/parse once by handing the parsed object plus owning
  buffer directly into linking. Any miss releases retained objects before
  compilation. The earlier exact host-only APK `39EE3277...D0D81` is
  superseded uninstalled by `A38B8B6F...8AA0B`; ABI, export, zero-copy,
  handoff, and strengthened thermal contracts pass. No device action ran
  after the 78.3 C failure. Detailed ledger:
  `debug-experiments/20260718-thor-jit-object-cache-warm-handoff.md`.
- Exact zero-copy APK `E69D671D2...6C509` later ran once after outer
  `31.7 -> 31.7 -> 31.5 C` and inner `31.3 -> 31.1 -> 32.3 C` gates.
  Cached-module timing improved modestly (first-to-final `-53.286 ms`), but
  silicon went `59.4 C` at PID+`2.668 s` to `78.3 C` at +`5.658 s`;
  the hard guard stopped it before Start/title. Classify
  `20260718-123726-thor-input-jit-object-cache-zero-copy-bounded-title-proof`
  as `failed-thermal-guard` / `not-comparable`, with no speed/FPS/flicker/
  gameplay/stability credit. Host guard now probes at 56 C and stops when the
  immediate confirmation remains near-limit; no second device launch ran.
- Current route base: Down160 title route, `PATH_TO_TENUTO_PRESENT` gate, strong post-load dismiss, Path-to-Tenuto field.
- Current movement bracket: `left1317` is clean single-axis movement, `left1318` is fatal/corrupt, and `left1317-down120` is failed.
- Latest refreshed lower proof: `20260527-221838-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` re-proved the route and left movement clean after the no-movement load-stability control.
- Historical left-only ladder already includes clean `left1312`, fatal `left1331`, fatal `left1321`, clean `left1316`, fatal `left1318`, and clean `left1317`; do not loop back through those midpoint proofs from a fresh `left1275`.
- Clean lower proof: `20260527-202051-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic-windows`.
- Fatal upper proof: `20260527-181934-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1318-longgate-diagnostic-windows`.
- `20260527-210215-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-reproof-after-down120-fatal-windows` re-proved plain `left1317` as clean after the `down120` fatal.
- `left1317` remains route/movement evidence only. It is not first-battle proof, speed proof, GPU migration, or 200%.
- `left1318` has VM/access/corrupt-field evidence. Treat it as failed even if byte-size visual triage looks field-like.
- Latest no-movement load-stability reproof `20260528-004219-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, and stayed field-like through very-late checks.
- `left1316-down120` remains a loading-only failure. Movement was not tested; do not repeat that combo.
- `left1316-down60` first aborted on `Save File 01 / Debug Save / Prologue`; the title-to-Load repair then restored `PATH_TO_TENUTO_PRESENT`.
- Latest repaired `left1316-down60` reached clean Path-to-Tenuto field, but RPCS3 lost the window/process after `ls_left:1316`; `down60` was not verified.
- Backed-off `left1275-down60` then aborted before slot load on `Save File 01 / Debug Save / Prologue`; movement was not tested.
- Latest save-list inventory shows the initial Load-list row is `Save File 01 / Path to Tenuto`; later `Down` inputs move the cursor onto lower rows where the Path preview can stay stale over empty slots.
- The repaired no-movement route base is `valid-field-triage` only, not movement, speed, GPU migration, first-battle, or 200% evidence. Next expected action is the same strongdismiss600 base with `ls_left:1275` and immediate/late screenshots.
- Latest `left1275` rerun `20260528-010220-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` aborted before slot `Cross`: all `16` load-target gate frames were black-overlay `UNKNOWN_LOAD_TARGET`; movement was not tested. Next expected action is a target-only Path-to-Tenuto reproof before any movement or speed work.
- Latest target-only reproof `20260528-012228-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-windows` aborted before slot `Cross` on `DEBUG_SAVE_PROLOGUE_PRESENT`; next expected action is a polling load-target-gated route repair that requires `PATH_TO_TENUTO_PRESENT` before continuing.
- Latest polling repair `20260528-014240-cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows-windows` also aborted before slot `Cross` on `DEBUG_SAVE_PROLOGUE_PRESENT`, now with damaged-save markers; movement was not tested. Continue route repair only.
- Latest save-list inventory `20260528-020512-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows` re-proved the initial Load-list row is `Save File 01 / Path to Tenuto`; `Down` moves the cursor onto lower empty rows while the Path preview remains stale. Next expected action is no-movement long-gate proof from the initial row, without save-list normalization.
- Latest no-movement reproof `20260528-022230-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` aborted before slot `Cross`: all `16` load-target frames were black-overlay `UNKNOWN_LOAD_TARGET`; no slot, field, or movement was tested. Next expected action is the title-to-Load pre-gate black diagnostic with timed screenshots.
- Latest title-to-Load pre-gate diagnostic `20260528-024313-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic-windows` selected `LOAD`, then settled on lower `Save File 05 / Path to Tenuto` with damaged-save rows above it. The gate reported `DAMAGED_SAVE_TARGET`; no slot, field, movement, speed, or GPU credit exists. Next expected action is only the stable Load-list Up-repair target diagnostic.
- Latest Load-list Up-repair target diagnostic `20260528-030231-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-windows` restored top-row `Save File 01 / Path to Tenuto`; gate passed `PATH_TO_TENUTO_PRESENT` with zero lower-row cursor and damaged-save markers. This is target repair only; next action is no-movement stability before any movement, battle, HLE, RSX, GPU, or speed work.
- Latest no-movement stability proof `20260528-032238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, and stayed field-like through `286s`; host contention was high/moderate, so it is route proof only.
- Latest `left1275` rerun `20260528-034311-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT` but stayed on `Now Loading...` through immediate, late, and `260s+` screenshots. Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`; fatal/log scan was clean; no movement, speed, GPU, first-battle, or 200% credit exists.
- Latest no-movement reproof `20260528-040209-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, stayed field-like through `286s`, and had clean host contention. It is route-base proof only.
- Latest `left1275` retry `20260528-042238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` reached field and took immediate/late screenshots, but RPCS3 reported a fatal VM access violation at `0x002aedd0` reading `0x40`; screenshots show crash overlay/corrupt field. It is `failed-fatal-log`, not movement, speed, GPU, first-battle, or 200%.
- Latest loader-control `20260528-044508-cpu4-loader-control-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `10` screenshots field-like through `190s`, `0` invalid after first field-like, empty stderr/stdout, and no targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1477` candidate/dynamic records, `1606` wait records, `83740` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `318`. Treat it as `valid-field-triage` and route-tooling only.
- The loader-control wrapper stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200` route proof `20260528-050402-cpu4-loader-control-left200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `14` screenshots field-like through `200s`, `0` invalid after first field-like, manual pre/post-movement field screenshots clean, empty stderr/stdout, and no targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1597` candidate/dynamic records, `1733` wait records, `90899` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `807`. Treat it as `valid-field-triage` plus small movement route-tooling only.
- The `left200` wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200x2` attempt `20260528-052421-cpu4-loader-control-left200x2-visualgate-windows-windows` failed `CleanAfterField`: `16` screenshots were `cutscene-or-nonfield-small-png`, first field-like was none, manual frames showed blue/starry non-field output, and no Path-to-Tenuto field appeared. Stderr/stdout were empty and targeted fatal scan found no real crash/access/device-lost/assertion/verification hit. Reservation-loop verify logged `1765` candidate/dynamic records, `1841` wait records, `106734` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `539`; counters are invalid for promotion because visuals failed.
- The `left200x2` wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200x2` confirmation `20260528-054511-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `16` screenshots field-like through `210s`, `0` invalid after first field-like, manual pre/post-second-pulse field screenshots clean, empty stderr/stdout, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1573` candidate/dynamic records, `1695` wait records, `88724` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `212`. Treat it as `valid-field-triage` plus route/movement tooling only.
- The `left200x2` confirmation wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest diagonal micro-pulse proof `20260528-060335-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `18` screenshots field-like through `220s`, `0` invalid after first field-like, manual pre/diag/post-diag field screenshots clean, empty stderr/stdout, clean host summary, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1766` candidate/dynamic records, `1893` wait records, `100595` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `710`. Treat it as `valid-field-triage` plus route/movement tooling only.
- The diagonal micro-pulse wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest reservation-loop Options proof `20260528-062448-cpu4-reservation-loop-options-fastselect-proof-windows` reached the full title Options page with `screenshot-0077s-options-candidate.png`, stayed there through `screenshot-0130s.png`, had empty stderr/stdout, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `975` candidate/dynamic records, `1063` wait records, `51726` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `390`. Treat it as `valid-options-triage` only.
- The Options proof wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then screenshots, logs, counters, and refiner were checked manually. No emulator process remained active.
- `tools/ps3_harness_refiner.ps1` now recognizes `reservation-loop-options-fastselect-proof` as valid Options proof instead of wrong-window noise and points the next action to first-battle proof/repair under `ReservationLoop Verify`.
- Latest reservation-loop first-battle attempt `20260528-064514-cpu4-reservation-loop-battle-topslot-route-proof-windows` reached a valid Path-to-Tenuto field screenshot at `117s`, then RPCS3 exited before the `169s+` screenshots. Manual `BattleRoute` gate failed because there was no late field or battle-like visual. Fatal scan was clean except the harmless `Show fatal error hints: false` config line; stderr/stdout were empty.
- Treat the latest battle attempt as `failed-window-lost-after-field`, not first-battle proof, speed, GPU migration, or 200% evidence. Its clean reservation-loop counters are route/tooling evidence only because visuals failed after field.
- Latest state-aware field reproof `20260528-070432-cpu4-stateaware-one-step-visualgate-windows-windows` passed `CleanAfterField`: field screenshots at `117s` and `133s`, empty stdout/stderr, no real targeted fatal/access/device-lost/assertion/verification log hit, and reservation-loop counters clean. Treat it as `valid-field-triage` only.
- Latest TopSlot left-only diagnostic `20260528-072448-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows` failed visual gate: the `117s` accepted-field screenshot was cutscene-like, the `165s+` left2600 frames were blue/starry non-field frames, stdout/stderr were empty, and fatal scan was clean. Host gate failed only on postrun Codex CPU, but visuals already invalidate the run.
- Latest left200x2 reproof `20260528-074420-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` failed: all `16` screenshots were black-overlay frames, manual `0117s` review confirmed black output with overlay only, and `RPCS3.log`/stderr reported `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event`. Host contention was clean, but the fatal/visual failure invalidates all counters and FPS samples.
- Latest left200x2 reconfirm `20260528-080430-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` failed visual gate without fatal logs: all `16` screenshots were `Now Loading...`/loading-like small PNGs through `210s`; manual `0117s` review confirmed loading, not Path-to-Tenuto field. Host contention was clean, but FPS/counters are invalid because visuals failed.
- Latest state-aware reset `20260528-082422-cpu4-stateaware-one-step-visualgate-windows-windows` passed `CleanAfterField`: field-like screenshots at `117s` and `133s`, manual `0117s` review confirmed Path-to-Tenuto field, stdout/stderr were empty, and fatal scan was clean. Postrun host summary was moderate only because Codex CPU was sampled after RPCS3 stopped.
- Latest TopSlot left-only diagnostic `20260528-084504-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows` reached a clean accepted-field screenshot, then `ls_left:2600` produced a crash overlay/corrupt field and a real `VM: Access violation reading location 0x40` at `0x002aedd0`. Treat it as `failed-fatal-log`, not movement, speed, GPU, first-battle, or 200% evidence.
- Latest no-movement loader-control reproof `20260528-090516-cpu4-loader-control-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `10` screenshots field-like through `190s`, manual final-field review was clean, stderr had only Qt warnings, host checks were clean, and no real targeted fatal/access/device-lost/assertion/verification log hit appeared. Reservation-loop verify logged `1489` MFC dynamic records, `1610` wait records, `84265` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `242`. Treat it as `valid-field-triage` and route-tooling only.
- Latest small movement proof `20260528-092432-cpu4-loader-control-left200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `14` screenshots field-like through `200s`, manual immediate-post-left and final-field reviews were clean, stderr had only Qt warnings, host checks were clean, and no real targeted fatal/access/device-lost/assertion/verification log hit appeared. Reservation-loop verify logged `1619` MFC dynamic records, `1745` wait records, `91872` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `189`. Treat it as `valid-field-triage` plus small route/movement tooling only.
- Latest 0x25cc coverage refresh `debug-captures\windows-lab\_eternal-sonata-25cc-coverage-latest.md` shows the clean exact `0xa1c000` skip removes only `5.55 MB`, `0.97%` of that run's hot 0x25cc bytes, and `0.10%` of the refreshed `5.65 GB` 0x25cc atlas; do not rerun the exact skip expecting speed. The useful CPU-pressure path is broader verify-only coverage around dynamic MFC / `0x9e4000` families or SPU codegen dispatch overhead.
- Latest 0x25cc runtime-family refresh `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-summary.md` found `10` repeated `0x9e4000` HLE pattern-body candidate groups covering `437.30 MB` of `0x25cc` traffic with `0 B` RSX-local and zero shadow mismatches, but the source run has a real `VM: Access violation reading location 0x40`; use this as sizing/target selection only, not proof.
- Latest stock-control TopSlot battle-route isolation `20260528-102538-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows` also failed without `Verify25ccShadow`: `15` black-overlay screenshots through `320s`, no field/battle visuals, clean host checks, and a real `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event` with fault address `0x2d0614000`. Treat as route/RSX-device-loss evidence only.
- Latest `left200x1` reproof `20260528-104441-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `14` field-like screenshots through `200s`, manual immediate/late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion hits, and clean host checks. Treat it as `valid-field-triage` plus route/movement tooling only.
- Latest `left200x2` rerun `20260528-110434-cpu4-loader-control-left200x2-visualgate-windows-windows` failed `CleanAfterField`: `16` screenshots were `cutscene-or-nonfield-small-png`, manual frames were blue/starry non-field output, stdout was empty, stderr had only libusb device warnings, host checks were clean, and targeted fatal/access/device-lost/assertion/verification scan was clean. Reservation-loop counters were clean (`0` mismatches, max overflow reads `212`) but invalid for promotion because visuals failed.
- Latest `left200x2-confirm` reproof `20260528-112431-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual post-second-pulse and late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. Postrun host was moderate only from Codex CPU after RPCS3 exited; do not use this as speed evidence.
- Latest `left200x2-diag200` proof `20260528-114457-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: `18` field-like screenshots through `220s`, first field-like at `117s`, manual post-diagonal and late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. It is route-tooling only, not speed, first-battle, Options/menu, GPU migration, or 200%.
- Latest SPU HLE atlas refresh `debug-captures\windows-lab\_eternal-sonata-spu-hle-candidates-latest.md` scanned `12` recent runs, used `2` valid field runs, excluded `2` fatal field-like runs, and selected PC `0x25cc` / `CellSpursKernel0` as top verify-gated CPU/SPU HLE/codegen target: `3.06 GB` over `1946` records, `58` patterns, max job `3.06 MB`, `0 B` RSX-local. Broad SPU-to-Vulkan remains parked.
- Latest `0x25cc / 0x9e4000` verifier-plan refresh `debug-experiments\20260526-25cc-9e4000-verifier-plan.md` updated current `rpcs3-upstream` source anchors and keeps the historical broad family at `6.86 GB`, `4340` records, `159` pattern rows, and `0 B` RSX-local. It is analysis only; next code work is verify-only family/hash counters before any fast/body mode.
- Latest `0x25cc` pattern-hash target refresh `debug-experiments\20260526-25cc-pattern-hash-targets.md` shows `10` runtime groups, `437.30 MB`, top-16 atlas overlap `5` groups / `274.17 MB`, shadow verifier `11988` hits / `187.31 MB`, GET/PUT `5688/6300`, and match/mismatch `11988/0`. The matched groups are PUT-heavy, so GET-only bodyfast cannot cover the main bytes.
- Latest `0x25cc` native-contract refresh `debug-experiments\20260526-25cc-shadow-native-contract.md` classifies the selected shadow verifier data as fatal-run sizing only: `11988` hits / `187.31 MB`, GET/PUT `5688/6300`, match/mismatch `11988/0`, and runtime-seen top groups `274.17 MB` with `84.4%` PUT. Upstream `rpcs3-upstream` already has direction-split descriptor anchors; the vendored Android core was not run.
- Latest `0x25cc` field counterproof `20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows` passed visual triage: `18` field-like screenshots, first field at `117s`, no invalid-after-field frames, and `0` targeted fatal/access/device-lost/assertion hits. 25cc descriptors had `22008` rows / `23643` hits / `369.42 MB`, GET/PUT `10998/12645`, mismatch `0`, overflow `0`. Generic non-25cc shadow rows at PC `0x451c` still had mismatches, so this is 25cc-only field counterproof.
- Latest `Verify25ccShadow` first-battle attempt `20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows` failed visual gate: all `15` screenshots were black-overlay small PNGs, no field-like or battle-like screenshot appeared, targeted fatal scan was clean, and 25cc counters were partial-only despite zero 25cc mismatch/overflow. Treat window-title FPS samples as invalid when screenshots are black.
- Latest loader-control `left200x2` reconfirm `20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual `0117s`/`0210s` review confirmed clean Path-to-Tenuto field after movement, stdout/stderr empty, host clean, and no targeted fatal/access/device-lost/assertion hits. Extracted counters: `1539` GPU-probe records, `2.28 GB` observed DMA, `0 B` RSX-local, reservation-loop rows `1639`, command exact-PC rows `44896`, wait exact-PC rows `86252`. Treat as `valid-field-triage` and route/counter base only.
- Latest loader-control `left200x2-diag200` repro `20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: `18` field-like screenshots through `220s`, first field-like at `117s`, manual `0117s`/`0141s`/`0220s` review confirmed clean Path-to-Tenuto field after diagonal movement, stdout/stderr empty, and no targeted fatal/access/device-lost/assertion hits. Runtime host samples were clean; postrun was moderate only from Codex CPU after RPCS3 exited. Extracted counters: `1743` GPU-probe records, `2.68 GB` observed DMA, `0 B` RSX-local, reservation-loop rows `1884`, command exact-PC rows `51325`, wait exact-PC rows `98353`. Treat as `valid-field-triage` and route/counter base only.
- Latest loader-control `left200x2-diag200-left400` repro `20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows` passed `CleanAfterField`: `19` field-like screenshots through `230s`, first field-like at `117s`, manual `0129s`/`0230s` review confirmed clean field visuals after the `left400` bridge, stdout/stderr empty, no targeted fatal/access/device-lost/assertion hits, and `0 B` RSX-local. Treat as `valid-field-triage`; not first-battle proof, speed, GPU migration, or 200%.
- Latest `Verify25ccShadow` first-battle repair probe `20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows` failed BattleRoute visual gate: all `20` screenshots were black-overlay small PNGs, no field-like or battle-like screenshots appeared, stdout/stderr empty, targeted fatal/access/device-lost/assertion hits `0`, and 25cc descriptor counters were clean but partial-only. Ignore title FPS samples when screenshots are black.
- Latest loader-control `left200x2` reproof `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual `0117s`/`0210s` review confirmed clean Path-to-Tenuto field after two left pulses, stdout/stderr empty, no real targeted fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. The wrapper stalled after RPCS3 exited and was killed; reservation-loop CSVs were missing, so treat this as visual route proof only.
- Latest loader-control `left200x2-diag200` repro `20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` failed `CleanAfterField`: all `18` screenshots were blue/starry non-field frames, first field-like was none, manual `0117s`/`0220s` review confirmed wrong-scene sky output, stdout/stderr empty, and no real fatal/access/device-lost/assertion/verification hits. Runtime/postrun host grade was clean, but visuals invalidate all FPS/counter use.
- Latest loader-control `left200x2` backoff reproof `20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` failed `CleanAfterField`: all `16` screenshots were black-overlay frames, first field-like was none, manual `0117s`/`0210s` review confirmed black output with perf overlay only, stdout/stderr empty, and no real fatal/access/device-lost/assertion/verification hits. Runtime host samples were clean; postrun was moderate only after RPCS3 exited. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing, so no counter or speed claim exists.
- Latest loader-control `left200x2` reproof `20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` reached a field-like screenshot at `138s` but failed `CleanAfterField`: later invalid cutscene/non-field frames appeared, `0190s+` screenshots showed the RPCS3 crash overlay on black output, and `stderr`/`RPCS3.log` had real SPU fatal unknown STOP codes at about `187s`. Host checks were clean, but visuals/logs invalidate all FPS/counter use. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing.
- Latest lower-bound repair `20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots from `117s` through `220s`, manual first/last review confirmed correct Path-to-Tenuto field visuals, runtime/postrun host checks were clean, and targeted crash scan found no real fatal/access/device-lost/assertion hit. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing, so it is visual route proof only.
- Current refiner next action: do not repeat `loader-control-left200x2`; it has failed `3` times in the recent window after lower `left200` stayed clean. Repair route control or switch to focused SPU kernel HLE/codegen/verifier analysis before another movement run. Latest valid lower bound is `20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows`; latest valid `left200x2` base remains `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- Latest SPU verifier pivot audit refreshed the 8-run HLE atlas: PC `0x25cc` / `CellSpursKernel0` is still the top CPU-pressure target at `3.68 GB` over `3` valid field runs, `0 B` RSX-local. Dedicated `25cc-counterproof` parsing of the latest clean `left200` repair and latest tracked `left200x2` loader-control base found `0` shadow descriptor rows/hits in both logs, so loader-control atlas data is target selection only, not counterproof. Use the dedicated `Verify25ccShadow`/descriptor route for future proof; do not cite loader-control logs as 25cc descriptor proof.
- Latest current-format `Verify25ccShadow` Options counterproof `20260528-182410-cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof-windows` reached the full title Options page (`screenshot-0079s-options-candidate.png`, `screenshot-0089s-options-late.png`), had clean host/fatal checks, and summarized as `valid-options-counterproof`: 25cc descriptors `8958` rows / `9498` hits / `148.41 MB`, GET/PUT `4473/5025`, output mismatches `0`, overflow `0`. Refiner says do not rerun field or Options; next proof target is first battle under `Verify25ccShadow`.
- Latest first-battle `Verify25ccShadow` attempt `20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows` failed: it reached clean field at `117s`, then hit a real PPU VM access violation at `0x002aedd0` reading `0x40`; `169s+` screenshots show the likely-crashed overlay/corrupt frozen field and no battle-like frame. 25cc descriptors stayed mismatch/overflow clean (`9918` rows / `10833` hits / `169.27 MB`), but this is `failed-fatal-log`, not first-battle proof. Refiner next action is the same TopSlot battle route with `Verify25ccShadow` off to isolate route-vs-verifier fatal.
- Latest stock-control TopSlot isolation `20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows` also failed with `Verify25ccShadow` off: all `15` screenshots were black-overlay frames, visual gate found no field or battle visuals, host checks were clean, and stderr/RPCS3 log hit real RSX `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event`. GPU probe saw `724.84 MB` DMA, hot PCs `0x451c`/`0x25cc`, and `0 B` RSX-local. Treat as route/RSX-device-loss evidence only; refiner next action is to re-prove the clean `left200x1` loader-control boundary before extending movement or battle routing.
- Latest `left200x1` refiner reproof `20260528-192415-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows` reached correct Path-to-Tenuto field at `136s`, then later invalid/crash-overlay screenshots appeared; visual gate reported `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`, and stderr/RPCS3 log had real SPU unknown STOP fatals. Treat it as `failed-fatal-log` / `failed-visual-gate`, not movement, speed, GPU, first-battle, or 200% proof.
- Current route lesson: do not keep extending or rerunning the loader-control movement ladder from the latest fatal. Prefer focused SPU contract/compiler analysis until a new route repair is justified.
- Source-aligned Windows repair `e12beb222fea26fa5e5f86fa507ad91536fa4d60` now includes upstream RPCS3 reservation-priority fix `e379fba` and disables the unsafe CellSpurs JobChain acquire hash. Exact rebuilt binary `0.0.41-597-e12beb22` / SHA256 `C31622E54441A6946A9AFC6986E8F7C9193F55541E158B2959BEE95B07AA3CC9` removed the prior unknown-draw/VM-access corruption on the same bounded route.
- Latest corrected-contract field proof `20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows` is a valid moving-field counterproof: correct field/animation through `185s`, five external-clean host snapshots, zero targeted fatal/draw/access/Vulkan/device-lost/assertion hits, and strict verifier `732/732` accepted with `1878` hits and mismatch/overflow `0`. Scripted screenshot labels did not make it a battle.
- Exact repaired-binary Options proof `20260715-223137-cpu4-verify25cc-e379fba-options-fastselect-windows` reached and held the complete title Options page through `130s`, had six external-clean host snapshots and zero targeted fatal signatures, and passed the strict verifier `461/461` with `957` hits and mismatch/overflow `0`. Do not rerun capped field or Options; genuine first battle is the only remaining correctness checkpoint.

## Banked Findings

- Promoted workflow: Thor dev-core speed pushes use RelWithDebInfo as the official baseline. Debug native cores are invalid for FPS/Rocknix comparisons and `tools/build_push_thor_core.ps1` now blocks Debug tasks or newest-Debug-library pushes unless `-AllowDebugFallback` is explicit. This is workflow promotion only; reduced-loop u4, `0x25cc bodyfast`, and HLE/GPU fast paths remain gated until field, Options/menu, and first-battle proof all pass.
- Ghidra/static analysis has been used for SPURS/semaphore and SPU-window understanding, and current 25cc work has source/disasm anchors. There is no promoted fusion superpath from Ghidra. Existing fused RSX paths are experimental/parked, and `0x25cc/0x9e4000` remains a CPU/SPU HLE/codegen candidate, not a GPU-resident fused path.
- Default SPU speed lane is now the contract compiler: runtime logs -> SPU windows -> Ghidra headless/static tightening -> `spu-contracts\BLUS30161` JSON -> verify-only emulator counters -> fast path. Start with `0x25cc/0x9e4000` and `0x451c`; GPU compute stays parked until contracts prove stable batching, low readback pressure, and RSX-consumed data.
- Current source alignment says Windows has the priority-1 `0x25cc/0x9e4000` predicate, corrected verify-only contract counters/reject buckets, the `0x451c` dynamic-list helper, and upstream reservation-priority fix `e379fba`; vendored RPCSX still has only the generic Thor DMA probe. Do not port to Android or enable fast mode yet.
- Current verify-counter schema requires `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow`, blocks fast/body/GPU fast values, and defines reject buckets for title/image/PC/group/SPU/cmd/list/tag/size/EA/LS/risky-config/fast-mode before any behavior change.
- Current verify log row is implemented and runtime-proven on a moving field with `hle_mode=contract-25cc-9e4000`; it remains log/shadow-only and body behavior stays off.
- Current verify log-row parser: `tools/parse_spu_contract_verify_log.ps1`. It validates exact contract anchors, hit/byte arithmetic, reject sums, fast-mode leakage, mismatch, and overflow, supports strict `-FailOnGate` checks, and always reports `promotion_ready=false` because visuals/fatal-log gates are external.
- `0x25cc bodyfast` is banked only as stackable CPU-pressure reduction: RPCS3 process CPU `42.60%` to `37.10%` (`-5.50 pp`, `-12.91%`) on clean capped BattleRoute repeat. It is not an FPS win, GPU migration, or 200% candidate.
- Final bodyfast plus RSX-local stack is visually compatible on the capped TopSlot BattleRoute, but it remains around `120 FPS` and reports `0 B` promoted CPU/SPU-to-GPU replacement. Do not keep stacking RSX toggles or rerun the auditor.
- RSX-local accounting is useful but separate from CPU/SPU-to-GPU migration. Current promoted CPU/SPU-to-GPU credit remains `0 B`.
- 0x25cc descriptor/shadow verifier now has exact source-aligned clean moving-field and full title Options counterproofs with zero 25cc mismatches and overflow `0`. It has not yet entered battle on that binary. Treat this as verifier coverage only, not bodyfast/codegen promotion.
- Loader-control runs can have useful SPU atlas bytes while still having no 25cc descriptor rows. Counterproof requires explicit `Verify25ccShadow`/descriptor logs.
- Exact `0xa1c000` 0x25cc skip is correctness-clean but too small for a speed path: latest refresh says `5.55 MB` skipped versus `5.65 GB` observed 0x25cc atlas (`0.10%`).
- Broader `0x9e4000` 0x25cc pattern groups are the better CPU-pressure candidate. Current sizing is `3.06 GB` in valid field atlas data, `6.86 GB` in the wider historical verifier-plan CSV, and `437.30 MB` in the latest shadow-run runtime family, still with `0 B` RSX-local; treat as verify/codegen CPU-pressure work, not GPU offload proof.
- Direction-split PUT-heavy `0x25cc` evidence now has clean field and Options/menu counterproofs with zero 25cc descriptor mismatches/overflow. It is still not promotion until first-battle visuals are clean under the same proof discipline.
- Broad SPU-to-GPU compute offload remains parked unless a candidate has stable batching, low readback pressure, and explicit correctness gates.

## Speed Claim Rules

- Never claim speed from a route miss, wrong scene, black/corrupt visuals, crash overlay, fatal log, lost window, mismatched host grade, or different config/cache state.
- CPU-pressure reductions are useful and bankable, but they do not satisfy the 200% gate.
- `gpu-migration-credit` requires real CPU/SPU/PPU work moved toward GPU or kept GPU-resident, clean visuals, rollback, and counters.
- Do not add small wins arithmetically. Only a measured combined run can be called an aggregate win.
- Field proof, Options/menu proof, and first-battle proof are all required before promotion.

## Windows Lab

- Use `tools/windows_rpcs3_lab.ps1` and `tools/eternal_sonata_speed_sprint.ps1`; do not launch RPCS3 manually.
- Keep screenshots enabled for serious route/perf work.
- Use host contention output. Compare performance only across matching host grades.
- `iso/` is ignored and is the only local place for legally owned test content.
- Official config DB cache path: `rpcs3-upstream\build-msvc\bin\GuiConfigs\config_database.dat`.

## Android And Thor

- Android/Thor work is active because the Windows 200% gate is cleared and the user reopened it. Keep device work to one short guarded route per cool round, then stop the package and finish analysis/build work on the host.
- Active proof device: AYN Thor, device `c3ca0370`, Snapdragon 8 Gen 2 / Adreno 740-class `QCS8550` platform.
- Base/Pro/Max share the target CPU/GPU behavior; mark memory-heavy experiments `pro-max` or `max-only`.
- Thor Lite is Snapdragon 865 / Adreno 650 and is not the PS3 performance target.
- Heavy Thor affinity mask is CPUs `3-7`, mask `0xF8`.
- Do not use ARM64 ASMJIT SPU. ARM64 SPU should use LLVM.
- Do not reintroduce `Use LLVM CPU = cortex-a34`.
- Use `cortex-a78` fallback unless a proven better ARM64 target exists.
- Do not assume SVE on Snapdragon 8 Gen 2. Gate NEON, DOTPROD, I8MM, BF16, SVE, and SVE2 from actual feature reports.

## Native Home Menu

- Android already opens the native RPCSX Home Menu through `_rpcsx_openHomeMenu`.
- Do not build a separate Compose OSD unless explicitly requested.
- Home Menu source: `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/HomeMenu/`.
- Localized IDs: `app/src/main/cpp/rpcsx/rpcs3/Emu/localized_string_id.h`.
- Perf overlay: `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/overlay_perf_metrics.cpp`.
- Current menu should include Resume, Cheats, Fast Forward 2x, Show FPS, Settings, Trophies, Screenshot, Recording, SaveState, Restart, and Exit.
- Fast Forward 2x changes `Core -> Clocks scale` to `200`; it is not a frame-limit uncap.

## Cheats

- Offline single-player cheats only.
- Do not bypass DRM, anti-cheat, or online protections.
- Bundled cheat assets: `app/src/main/assets/cheats`.
- SQLite DB: `app/src/main/assets/cheats/cheats.db`.
- Rebuild DB after cheat asset changes: `python tools/build_cheat_db.py`.
- RPCS3 patch entries can install when they include PPU hashes.
- AoB cheats are risky until native byte validation/scanning exists.
- Current fixture: Odin Sphere Leifthrasir `BLUS31601`.

## Recommended Settings And Cache

- Bundled config DB: `app/src/main/assets/config/config_database.dat`.
- Source endpoint: `https://api.rpcs3.net/config/?api=v1`.
- Android manager: `app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt`.
- Managed per-game configs use `config/custom_configs/config_TITLEID.yml` with `# RPCSX_THOR_AUTO_SETTINGS`.
- Never overwrite user custom configs without the managed header.
- Cache status: `app/src/main/java/net/rpcsx/performance/GameCacheRepository.kt`.
- Cache storage: `app/src/main/java/net/rpcsx/performance/CacheStorageManager.kt`.
- Core cache root remains `RPCSX.rootDirectory/cache/cache`; SD-card selection uses an app-owned symlink.
- PPU cache hook: `_rpcsx_preparePpuCache`, surfaced through `RPCSX.supportsPpuCachePreparation()` and `RPCSX.preparePpuCache(...)`.

## Durable Memory

- Current detailed sprint ledger: `debug-experiments/20260525-reservation-loop-branchstate-battle-route-worklog.md`.
- Current SPU contract plan: `debug-experiments/20260528-spu-contract-pipeline-plan.md`.
- Current SPU contract tool: `tools/spu_contract_pipeline.ps1`.
- Current SPU contract outputs: `spu-contracts/BLUS30161/latest-summary.md`.
- Current SPU verify-counter plan: `spu-contracts/BLUS30161/verify-counter-plan.md`.
- Current SPU source alignment: `spu-contracts/BLUS30161/source-alignment.md`.
- Current SPU verify-counter schema: `spu-contracts/BLUS30161/verify-counter-schema.md`.
- Current SPU verify log-row scaffold: `spu-contracts/BLUS30161/verify-logrow-implementation.md`.
- Current SPU verify log-row parser: `tools/parse_spu_contract_verify_log.ps1`.
- Current refiner: `tools/ps3_harness_refiner.ps1`.
- Current refiner skill: `.agents/skills/ps3-continual-harness-refiner/SKILL.md`.
- Current SPU contract skill: `.agents/skills/ps3-spu-contract-compiler/SKILL.md`.
- Current safe Windows runtime base is current upstream RPCS3 `1269ebff` on local branch `codex/clean-upstream-20260715`, plus local MSVC zlib commit `c433cc7` and preserved curl/wolfSSL integration fix `6311394472`. Exact `rpcs3.exe` SHA256 is `7A9E5E0CA3465359E8E6339D14B29359A9847CBAD9450C8AC087218B404AEC28`.
- Do not use the older monolithic instrumented fork for promotion runs. Preserve it for forensic comparison only; it has produced native/JIT and movement failures even with probes disabled.
- CPU affinity `0x0f` is now a known invalid promotion condition for the long diagonal/left first-battle route: both custom and clean current-upstream builds can hit guest PPU `0x002aedd0` reading `0x40`. Treat four-core route failures as stress evidence, not normal-scheduler regressions.
- Current-upstream normal-scheduler speed proof is `20260715-230705-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-first-battle-speed-windows`: exact Path-to-Tenuto field at `57s`, real tutorial prompt at `69s`, correct battle through the `150s` cutoff, zero actionable fatal hits, external-clean host evidence, and 30 gameplay samples averaging `120.002 FPS` (`119.85` to `120.38`). This is a stable 400% Windows gameplay proof.
- Matching exact-build/config Options proof is `20260715-231132-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-options-speed-windows`: correct full Options page through `70s`, zero actionable fatal hits, external-clean host evidence, and six Options samples averaging `240.072 FPS` (`239.88` to `240.40`). Together these runs clear the Windows 200% field/menu/first-battle gate.
- High-vblank Windows routes must scale input pulses by emulated frames: the title needs `down:20` at 240 Hz; `down:80` and `down:300` repeat into Options. Use `gate_title_menu`, `gate_load_target`, `gate_load_complete`, `gate_field`, and `gate_first_battle_prompt` instead of fixed route delays. The load-target gate classifies only its latest screenshot to avoid rescanning the full run.
- First guarded Thor battle capture is `20260715-233619-thor-input-eternal-sonata-battle-intro-route`: it reached correct active battle at `30 FPS`, but temporal frame `03` was fully black and the route then logged unknown draw word `0x3f800000` followed by PPU VM access violation at `0x002ad588` reading `0x3f80000c`. This is flicker/crash evidence, not a stable speed proof.
- That capture stayed at `23-24 C`, force-stopped PID `28190`, and left the package stopped with the verifier property off. Do not spend another device run in the same round.
- The corrected verifier core `2715F3B42169A5496FE7A2B63DB6F02CB9249EA74A9D630A9C829728CF097F3F` was deployed without launch in `20260715-235542-draw-stream-verifier-2715-dev-core-push`, then exercised by exactly one guarded route: `20260715-235626-thor-input-eternal-sonata-battle-intro-route`.
- That route produced 3,654 consecutive full `0x180000`-byte producer/consumer matches. Generation `3655` then logged `consumer-layout-mismatch` immediately before unknown draw `0x00200000`; generation `3785` did the same immediately before unknown draw `0x3f800000`. Fault-word counts were identical in the saved and live buffers. Treat this as a consumer buffer-selector/generation failure, not simple post-handoff byte mutation.
- Thor battle routes now fail closed when any sampled battle frame is at least `95%` near-black or lacks the expected HUD. The actual bad frame classifies `dark_percent=100`, while adjacent battle frames classify cleanly.
- The `235626` sample reached a clean first-battle tutorial frame at `29.97 FPS` with no VM access violation before the wrapper failed closed on the first unknown draw. It stayed at `24 C`; a later read-only check was `25 C`, thermal status `0`, package stopped, and verifier property off. Do not spend another device run in the same round.
- The dual-buffer/sequence verifier core `BA0E53338FB098E9BDF1BCCCB21629748386CE7D6D966BC828443CAB62A870D7` was deployed without launch, then used for exactly one guarded route: `20260716-002723-thor-input-eternal-sonata-battle-intro-route`.
- That route logged eight immediate-previous-generation selections with exact work/completion counter ordering and zero sequence anomalies. Each old buffer was already modified at byte `0x1452` or `0x1453`; 17 unknown draw commands included later current-generation faults after byte-perfect handoffs. Treat later faults as potentially cascading parser desynchronization, not a second proven publication defect.
- The sampled tutorial prompt was clean at `30.00 FPS`; the route stayed at `24 C` and ended with PID `12569` stopped and the verifier property off. It is failure classification, not a stable/speed result. No second route may be charged to that cool-device round.
- Candidate `4A3302EC6DAACFD73C6CD9684F9E372BF7540E9EBF8BE9550839B80E87B59160` was deployed without launch, then used for exactly one guarded repair-mode route: `20260716-005341-thor-input-eternal-sonata-battle-intro-route`. It reached a clean tutorial prompt at `30.00 FPS`, then the first active-battle sample was fully black. Three selector rewrites were followed by unknown draw words at generations `4063` and `4144`; this is a failed stability counterproof, not speed evidence.
- The route stayed at `24-25 C`, ended stopped with the repair property off, and had zero VM/native/device-loss faults before controlled stop. No second route may be charged to that cool-device round. The final log had to be pulled after the stop because the visual gate preceded the next guest-health token; visual failures now capture the guest log before throwing.
- Scoped-restore candidate `52622C41A876B52CD7A26B4A4D35587FDA55CBA0DE5A6084DEEB59334E0A2F58` ran once in `20260716-011921-thor-input-eternal-sonata-battle-intro-route`. It rendered clean field/tutorial/active battle at `27.99/30.16/30.01 FPS`, with no black frame or unknown draw. Five masks had five restores and zero failures/pending state, but consumer PPU `0x100000c` then faulted at `0x002ad588` reading `0x3f80000c`. This is failed stability evidence, not a speed result.
- That route stayed at `24 C` and ended at `25 C`, thermal status `0`, package stopped, and repair property off. No second route may be charged to that thermal round.
- Selector-bit-only candidate `C6CE9D11852803F68795249E615F715C27EF42E7198D924734A7830E74B09B47` ran once in `20260716-014034-thor-input-eternal-sonata-battle-intro-route`. Unknown draw `0x3f800000` occurred at generation `3827` before the first selector repair (`repairs=0`, current publication selected, work post/wait both `3827`, zero sequence anomalies). Two later masks/restores preserved the `+0x1c` write pointer and ended `2/2` with zero failures/pending state, so the narrow repair behaves as designed but is not the root fix.
- That route showed a clean field/tutorial at `28.08/29.39 FPS`, stayed at `24 C`, ended stopped with repair off and thermal status `0`, and did not receive a second run. Treat the entire draw-selector repair lane as disproven for the primary corruption; reservation priority also remains off.
- Exact SPU-isolation core `7EFB0A13382B229F616948B08153D0C46898E7A63170D5D786BC5B94BFF72379` was deployed without launch and exercised once with only `debug.rpcsx.thor.spu_arm_features=baseline` in `20260716-020707-thor-input-eternal-sonata-battle-intro-route`. Logs proved both JIT and LLVM had `dotprod=false`, `i8mm=false` and used isolated cache `spu-safe-thor-arm-baseline-v1-tane.dat`.
- That baseline route rendered a correct field/tutorial at `27.88/30.00 FPS`, then unknown draw `0x3f800000` appeared at emulated `0:02:53.926433`, followed later by a fault-word burst. No VM/native/device-loss fault preceded controlled stop. The device stayed at `24 C`, thermal status `0`, ended stopped with both experiment properties off, and received no second route. Reject DOTPROD/I8MM SPU codegen as the primary corruption source; this is not stability or speed proof.
- Host-only core `884FD8B36AB257CFDDDB910E683D185A6B2DFA02C4C5753DF7AA0FD64D9D3DF8` backports the current-upstream accurate-`PUTLLC` publication contract: unchanged data is checked twice, and a reservation update changing exactly one 16-byte block is committed with an atomic 128-bit compare-exchange instead of a torn 128-byte copy. This directly targets SPU-produced records read without the RSX reservation lock and reduces write traffic for the common one-block case. ARM64 RelWithDebInfo builds successfully; size is `1,349,576,840` bytes. It has not been deployed or launched.
- Exact atomic-`PUTLLC` core `884F...D3DF8` was deployed without rebuilding and exercised once in `20260716-022914-thor-input-eternal-sonata-battle-intro-route`. It rendered the correct field/tutorial at `27.12/28.88 FPS` with no captured black frame, then failed closed on unknown word `0x30b12f20`; the familiar later five-word corrupt burst also returned. No VM/native/Vulkan/LLVM fatal preceded the controlled stop. The run stayed at `24 C`, thermal status `0`, ended stopped, and received no second route. Keep the atomic publication fix for upstream alignment/correctness, but give it no stability or speed credit.
- Candidate `D33AC093C9516653687F8ED512931AB1B77D03B5E9B7B6A74BA9C271FDF1BC21` adds a default-off, BLUS30161-only PPU LLVM isolation switch for Ghidra-proven publisher `[0x002ac618,0x002ac65c)` and parser `[0x002acbc8,0x002afce0)` ranges. `debug.rpcsx.thor.es_ppu_command_interp` accepts `publisher`, `parser`, or `both`; each selection has independent PPU object-cache bits. ARM64 RelWithDebInfo size is `1,349,614,432` bytes. It was deployed exactly in `20260716-031748-es-ppu-interp-both-d33a-dev-core-push`.
- The first `both` attempt `20260716-031822-thor-input-eternal-sonata-battle-intro-route` is route-tooling only: the mode/ranges logged correctly, but the fixed 75-second boot wait ended while the cold cache was still compiling module 60 of 62 with about 24 seconds remaining. The visual gate force-stopped before any route input, so this is neither a stability counterproof nor FPS evidence. No draw/VM/native/Vulkan/LLVM fatal appeared. Every thermal sample was `23 C`, thermal status `0`, and cleanup left the package stopped with the property off.
- The second `both` attempt `20260716-033309-thor-input-eternal-sonata-battle-intro-route` stayed fatal-clean but is route-tooling only. The first readiness poll still showed SPU cache construction; the second was a fully black post-compile frame that the old gate incorrectly accepted. The title input therefore arrived early, the supposed Load/field/battle screenshots were title and opening-story frames at `28.21-30.01 FPS`, and no comparable gameplay proof exists. Exact mode/ranges activated, RAM peaked at `10475 MB`, temperature rose only `23-24 C`, thermal status stayed `0`, and cleanup left the package stopped/property off with no second route.
- `gate:ppu-ready:90000` now requires the title menu's normalized center magenta selector in two consecutive frames, `2.5s` apart, after compilation/black frames clear; the battle profile immediately rechecks that title-specific gate before any key. Host replay recognizes both title selector positions and rejects compilation, black transition, Load-list, story, and field frames. A bounded battle-approach miss now also pulls full `RPCSX.log` before force-stop. Do not run the Thor again in this cool round. In one later round, keep exact installed `D33A...BC21` and use one guarded `-EsPpuCommandInterp both` route without rebuilding or redeploying.
- The accepted `both` route `20260716-035422-thor-input-eternal-sonata-battle-intro-route` reached the correct title, save, field, and first-battle tutorial prompt. Field/tutorial overlay samples were `21.14/28.83 FPS`; the field result is about `22%` below the comparable atomic-control field sample (`27.12 FPS`). Unknown draw `0x30b12f20` recurred first at emulated `0:02:51.327840`, identical to the atomic-control first word, so reject PPU LLVM execution of both mapped ranges as the primary corruption cause and do not split publisher/parser. This is a failed stability/speed counterproof, not active-battle proof.
- That accepted route had no VM/native/restart/Vulkan/LLVM fatal before controlled stop, stayed at `23 C` until the final `24 C` sample, thermal status `0`, and ended with the package stopped and interpreter property `off`. No second launch may be charged to that cool-device round.
- Exact dispatch-probe core `662BDBB1CCC28102F2605B823BA4C5FDFDE89D4838930E88D9B254A8B7965BE3` was deployed without rebuilding and exercised once in `20260716-043242-thor-input-eternal-sonata-battle-intro-route`. It rendered correct field/tutorial frames at `28.95/30.00 FPS`, then failed closed before active battle. Two stable invalid words came from alternating selected buffers at common dispatch load `0x002acc54`; the current write pointer was in the opposite buffer. The first `0x3f800000` followed valid command `0x60` plus its one argument at an exact record boundary. No VM/native/Vulkan/LLVM fatal preceded stop; temperature stayed `23-24 C`, thermal status `0`, the package ended stopped/properties off, and no second route ran.
- Saved-project Ghidra mapping proves command `0x60` has length one/handler `0x002aedb8`, and publisher store `0x002ac620` writes a zero terminator before the slot flip. New `tools/ghidra_scripts/FindInstructionImmediate.java` found seven relevant command-`0x60` stores: `0x002caa38`, `0x002cb810`, `0x002e1340`, `0x002e8050`, `0x002e8a04`, `0x002e8ab0`, and `0x002ee0c8`.
- Host-only core `47BC2679B9DFE9DC1E1BDC099887CB297AF6E07A1586E2C9E87BCDFBA63BC007` extends the same default-off/title-gated probe with bounded atomic breadcrumbs after the seven command stores and publisher terminator. Fault-only logging reports the matching emitter CIA and whether the invalid word is inside, at, or past the last published end; it does not allocate, lock, mutate guest state, or recover the command. ARM64 RelWithDebInfo builds successfully; size is `1,349,690,912` bytes. It has not been deployed or launched. In one later cool round, deploy exact `47BC...C007`, leave every other experiment off, run one guarded route, stop, and use producer/published-end provenance before changing behavior.
- Exact `47BC...C007` ran once in `20260716-050823-thor-input-eternal-sonata-battle-intro-route`. It reached correct field/tutorial frames at `28.11/30.00 FPS`, then failed closed before active battle. The second stable `0x3f800000` boundary fault matched emitter `0x002ee0c8`, but publisher data was absent. No VM/native/Vulkan/LLVM/FP-CAL fatal preceded stop; every thermal sample was `23 C`, thermal status `0`, the package ended stopped/properties off, and no second route ran. This is producer triage, not stability or speed proof.
- The missing publisher breadcrumb was caused by stale probe-on PPU object reuse: `47BC...C007` loaded `JxcXFik2c7V32hQub9w8MZ-000e18`, which `662B...5BE3` had compiled before publisher/emitter breadcrumbs existed. New high cache bit `thor_es_dispatch_provenance_v1` marks only BLUS30161 probe-enabled objects containing publisher/emitter sites while preserving existing bits and normal/off keys. Host-only ARM64 core `55B01CB3CDF84D0F7B43F9AB2005FD3CA55E15FA5AA0B9DC663648ECA471B0DD`, size `1,349,692,016`, builds successfully and has not been deployed or launched.
- Saved-project Ghidra ties emitter `0x002ee0c8` to async descriptor builder `0x002b07c8`; it reserves generated stream space, publishes an `0x80`-byte job through indexes `+0x111188/+0x111190`, and wakes a worker. Guest `0x00309160` is an explicit sentinel/wait/drain path that copies producer to consumer after completion. Do not add a speculative drain yet. In one later cool round, deploy exact `55B0...B0DD`, run one probe-only guarded route, stop, and require corrected `inside`/`at_end`/`past_end` publisher evidence before changing behavior.
- Exact corrected-provenance core `55B0...B0DD` ran once in `20260716-052959-thor-input-eternal-sonata-battle-intro-route`. It rendered correct field/first-battle tutorial visuals at `27.25/30.01 FPS`, then failed closed on stable `0x3f800000`. The fault matched emitter `0x002ee0c8` and was `inside` the latest publication: offset `0x2fab0` versus published-end `0x33e78`, publisher age zero. No VM/native/Vulkan/LLVM/FP-CAL fatal preceded stop; temperature stayed `24 C`, thermal status `0`, the package ended stopped/probe off, and no second route ran. This is failed stability evidence, not speed proof.
- The provenance cache repair is dynamically proven: `JxcXFik2c7V32hQub9w8MZ` compiled under new key `001u0i`. Static order is publish through `0x002ac618`, async drain `0x00309160` at `0x002f7710`, then consumer signal at `0x002f7720`. The narrow target is a generated header still invalid when the existing drain returns; reject terminator repair, parser masking, a blanket per-job drain, and broad semaphore/reservation rewrites.
- Exact async-guard v1 core `A83E3DE0EC068D6698271A93303EFF3382F13B2E7FE4E3E40A2E0D3ABCFFF53B` ran once in `20260716-060015-thor-input-eternal-sonata-battle-intro-route`. Correct field/tutorial frames rendered at `27.89/30.00 FPS`, then an inside-published unknown-word burst failed closed. The log contained zero async post-drain runtime records: the barrier callback never executed and the target hook had no independent hit counter, so this route did not test the repair. No VM/native/Vulkan/LLVM fatal preceded stop; every thermal sample was `23 C`, status `0`, the package ended stopped/properties off, and no second route ran.
- Exact v2 core `E4344930EF65FC698D5AE40E9696648CFF03B7E0AE69EDB2B49061074586E520` ran once in `20260716-063003-thor-input-eternal-sonata-battle-intro-route`. Correct field/tutorial frames rendered at `28.38/30.00 FPS`, then two stable unknown words failed closed. Both were inside exact async target `0x32dfd1d0+0x7a0`, at offsets `+0x3d4/+0x3d8`, proving the descriptor hook. The post-drain callback still had zero runtime hits because `PPUTranslator::B` tail-calls and returns before post-instruction instrumentation. No targeted fatal occurred; temperature stayed `23-24 C`, status `0`, package stopped/properties off, and no second route ran.
- Exact v3 core `399F7C2F33FEF5E5FA5CAD31BCCD1EDB42A4D5776D9079497DCE739B3C334E3A` ran once in `20260716-065629-thor-input-eternal-sonata-battle-intro-route`. Correct field/tutorial visuals rendered at `27.66/29.92 FPS`, then five stable unknown words failed closed. Three faults matched exact async targets whose captured initial first words were already the same invalid `0x00200000` or `0x3f800000`; two `0x30b12f20` faults were outside the retained async ring. There were zero v3 barrier callbacks despite fresh EBOOT key `00CzxA`. The pulled object proves `__0x2f7714` contains the barrier relocation at host offset `0x60bd4`; runtime return dispatch bypasses that continuation symbol. No targeted fatal occurred, temperature stayed `23-24 C`, and cleanup left the package stopped/properties off with no second route.
- Exact v4 core `C2B048BBCC7E2EBD4C082674E9E64D2EE752883B9601EA52C1ED438EDC012AF5` ran once in `20260716-071609-thor-input-eternal-sonata-battle-intro-route`. The real consumer-entry callback is dynamically proven through hit `3072`: its last logged batch had `114` readable targets / `256,368` bytes, a `64 us` grace, zero endpoint-invalid targets, timeout, or overflow. The route still produced stable `0x3e21bf94/0xbf7a924b` inside exact target `0x32dfc7d0+0x7a0` at `+0x3d4/+0x3d8`, followed by guest PPU fatal at `0x002aedd0` reading `0x40`; the tutorial candidate had edge corruption/crash overlay. Treat v4 as failed stability evidence that disproves endpoint-only readiness, not the consumer-entry boundary.
- Saved Ghidra proves command `0x3a` has length two and handler `0x002ae3e4`; it consumes `0x02000000/0x3e058dc8`, making the float pair the exact next-command boundary. Host-only v5 core `7335FD767934879872E7108217AF715F3D97062AE87EC8C709FC7C61D7BCDC1B`, size `1,349,750,392`, fingerprints each bounded async target at capture, pre-grace, post-grace, and matching fault time. It builds and has not been deployed/launched. Keep the Thor stopped this thermal round; one later cool route may classify stable data versus a post-barrier overwrite before any behavioral fix.
- Saved-project Ghidra now also resolves first target command `0x1a` to fixed length two/handler `0x002ad3d4`, and confirms the descriptor ring is submitted to SPURS while `0x00309160` waits then acknowledges it before parser wakeup. Treat the target as SPU-produced output; do not patch the `0x1a`/`0x3a` length table or add another broad PPU drain.
- Host-only v6 core `03B12C56644E3B3AF5F6D1BEA0E63726EA95D73560345B2573D8FD0CCCA6B799`, size `1,349,755,776`, makes repair mode require two consecutive whole-batch fingerprint matches, catches interior late writes missed by endpoint validation, and hashes aligned 64-bit blocks instead of individual bytes. It remains default-off and BLUS30161/property-gated. ARM64 RelWithDebInfo builds; it has not been deployed or launched. Do not spend another Thor route in this thermal round.
- Exact v6 ran once in `20260716-080248-thor-input-eternal-sonata-battle-intro-route`. Hit `3072` stabilized all `112` targets / `253,648` bytes in two snapshots (`550 us` total wait), with identical before/after batch hash, zero hash changes, timeout, or overflow. About 15 seconds later, valid command `0x61` reached handler `0x002aedd0` with args `0x4/0x48/0`, and its callee faulted reading `arg0+0x3c = 0x40`. Reject more barrier delay as the primary fix; this is a stably malformed payload, not an unknown opcode.
- The v6 route's field was clean at `27.86 FPS`; the tutorial candidate showed `29.70 FPS` with edge corruption and the guest-crash overlay. It stayed at `23 C`, force-stopped, reset experiment properties, and received no second route. This is failed stability evidence, not speed proof.
- Host-only v7 core `72EAFCDFC19E670AC0F98CDDDA6DC1AD00300E4F99D00C5928BD66456C1C5386`, size `1,349,779,768`, adds diagnostic-only breadcrumbs for the six Ghidra-proven command-`0x61` emitters and reports exact producer/publication/async-target provenance only when handler arg0 is unreadable or below `0x10000`. Cache bit `thor_es_dispatch_provenance_v2` prevents stale probe objects. ARM64 RelWithDebInfo builds; it has not been deployed or launched. Do not skip/mask command `0x61` before provenance identifies the bad producer.
- Do not deploy v7: its emitter callback followed the opcode store but preceded the three payload stores, adding a diagnostic scheduling window inside a record. Host-only v8 core `55FF239146AEFF870F8A5407CB12C3D798C3CEE1ED3910A1CB8DA79880FC45D2`, size `1,349,802,568`, moves all six hooks after the final payload store and sequence-validates a snapshot of source pointer plus emitted args. An anomaly now reports `stable_since_emit` versus `changed_since_emit`; cache bit `thor_es_dispatch_provenance_v3` rejects v7 objects. ARM64 RelWithDebInfo builds; it has not been deployed or launched.
- Exact v8 was deployed without launch in `20260716-083114-es-command61-v8-55ff-dev-core-push`. The first attempted route `20260716-083140-thor-input-eternal-sonata-battle-intro-route` is tooling-only: the host command timeout killed the wrapper during its initial fixed `wait:60000`, before any readiness gate or route input. Manual cleanup immediately force-stopped PID `21078`, reset interpreter/probe/barrier properties, and confirmed `23 C`. Do not count this as the one v8 gameplay route or retry in the same thermal round.
- The battle profile now starts `gate:ppu-ready:150000` immediately instead of waiting 60 seconds first. The gate already rejects compilation/black frames and requires two title-selector frames, so warm-cache routes can begin earlier while cold-cache maximum readiness time remains 150 seconds.
- Exact v8 ran once in `20260716-083705-thor-input-eternal-sonata-battle-intro-route`. The immediate readiness gate reached the real title after cold compilation, then the route rendered a clean field at `27.53 FPS` and the real first-battle tutorial prompt at `30.00 FPS`. It failed closed on eight stable unknown words with zero VM/native/Vulkan/LLVM fatal hits. Every thermal sample was `24 C`; cleanup stopped the package and reset interpreter/probe/barrier properties. Do not run another Thor route in this thermal round.
- V8's hit-3072 batch stabilized `109` targets / `249,568` bytes in `242 us`, with identical before/after hash and zero changes/timeouts/overflow. A later five-word fault burst was inside settled target `0x32dfd310+0x7a0`; its current hash differed from the equal pre/post-barrier hash, producing five `after_barrier_changed` rows. This proves a post-barrier overwrite for that burst. The recurring `0x30b12f20` boundary remains outside retained async targets and is a separate unresolved lane.
- Host-only v9 core `BE8CD29E62C9DCA35EE11B7F7FA322CA1838E16A8AE86405161F629619A80016`, size `1,349,846,040`, snapshots successfully settled async targets only in repair mode. Immediately before dispatch loads `0x002acc54/0x002acc9c`, it restores a 64-byte window only when the current bytes differ from the sequence-validated snapshot. Storage is lazy (4 MiB), event publication is ordered, slot reuse drains readers under a repair-only writer guard, the common target lookup is cached, non-async/stable regions are untouched, and normal/probe-off execution is unchanged. ARM64 RelWithDebInfo and the 10-second no-op confirmation pass; it has not been deployed or launched.
- Supersede the v9 repair contract: exact V11 `47B27527E0826BDB56DE91C99A9D6DABCE1B294F85CF61466A990E60DDFCD43F` ran once in `20260716-100003-thor-input-eternal-sonata-battle-intro-route` and disproved settled-target write-back. It performed at least 1,024 changed-window restores / 65,536 guest bytes, produced severe black/green field corruption, then faulted at guest `0x002ff84c` reading `0x0` about 1.5 seconds after the first restore. All eight V11 ownership rows were `template_event_missing`; the recurring `0x30b12f20` template boundary did not occur before this earlier repair-caused fatal. The run stayed at `23 C`, ended stopped with properties off and thermal status `0`, and received no second launch.
- Never restore settled async-target bytes. Host-only V12 `816D6D7917C8EDFBD0749ECFFB4126D8AB5072F6A9E9F74DD7AAE43FFD4BEBE7`, size `1,349,863,856`, removes the rollback store, settling wait, guest-memory writes, and hot parser consume hooks. Legacy `repair/on/true/1` requests normalize to read-only `verify`; the route tool records requested/effective mode, and cache bit `thor_es_async_draw_barrier_v8` prevents reuse of v7 hook-bearing objects. ARM64 RelWithDebInfo passes; V12 is host-only and must wait for a later cool round.
- Saved Ghidra corrects the V11 fatal interpretation: `0x002ff84c` is the return NOP after renderer helper `0x00306330`, which appends a 16-byte vector to a bounded 32-entry queue. Saved `r2/r7` are valid; record only a downstream zero read after the rollback storm, not a proven null global or an independent guest bug.
- Host-only V13 `514702755F6241758257CB93F80807D50F3D8C927935325192A31DA66BD12D26`, size `1,349,864,864`, keeps the eight-row general provenance cap but reserves two exact `0x30b12f20` boundary rows even after hit eight. It uses one command comparison, cache bit `thor_es_dispatch_provenance_v6`, and adds no scan/mutation/normal probe-off work. ARM64 RelWithDebInfo plus no-op passes; V13 is undeployed. In the next later cool round, run one fail-closed V13 route with dispatch probe on and both interpreter and async barrier off; the boundary is outside async targets, so verifier hashing is unrelated overhead.
- Before any Thor route, reject stale non-daemon ADB clients. The v4 round found and stopped an old logcat stream plus RPCSX-log and memory pollers running every three seconds; cleanup ended at `24 C`, thermal status `0`, package stopped, experiment properties off, and no second route.
- Official Android upstream since the local base contains only UI preference dependency/source changes, and current RPCSX core since the vendored base contains only a missing-include compatibility commit. Do not merge either into the performance lane as a presumed speed fix.
- Exact V13 `514702755F6241758257CB93F80807D50F3D8C927935325192A31DA66BD12D26` was deployed without rebuilding or launching in `20260717-005004-es-dispatch-v13-51470275-dev-core-push`. One guarded probe-only route ran in `20260717-005041-thor-input-eternal-sonata-battle-intro-route`, but it is route-tooling evidence only: the invocation accidentally used Android `Virtual` input instead of the known-good `Direct` path, the supposed Load-list frame was still the title menu, and later accepted input started New Game. The three battle approaches therefore sampled the opening story scene and produced no dispatch-provenance row, comparable gameplay FPS, or stability credit.
- That V13 tooling route stayed at `24-25 C`, thermal status `0`, then force-stopped and reset interpreter/probe/barrier properties to `off`; no second launch may be charged to the round. V13 remains the exact installed development core but still needs one valid later cool route.
- The Eternal Sonata battle profile now promotes any non-`Direct` input request to the app-owned direct pad path and records requested/effective mode. It fails closed unless both the Load-list and Load-complete frames pass the parchment-menu classifier, then rejects title/load/story/battle/black frames at the loaded-field checkpoint before movement. Across the saved Thor corpus, the `60%` Load threshold accepts 33 real Load frames and rejects all field/title/first-battle frames; the `3%` upper-right story-watermark threshold rejects the V13 wrong-route frames while all 70 first-battle samples remain at zero. Use these gates to stop dropped-input routes early instead of heating the device.
- Never enable reduced-loop emission on Thor. Fresh-cache U2/no-reuse and U4 runs deterministically fault `CellSpursKernel0` at SPU PC `0x330f0` reading unmapped `0x8d230480`; unroll, reuse, and stale cache are excluded. Android ignores the emit property at the native gate, public emit profiles are removed, and detect-only remains available. The fail-safe source is included in exact installed ARMv8.2 candidate `744CB3F2BE77F0DFCA255FE27EA5D7AF6E200E6BFC22D912F67CCCE6563CE839`. Its first field attempt `20260717-032039-thor-input-eternal-sonata-field-route` was force-stopped at `77.1 C` during the legacy blind startup wait, before any screenshot or FPS sample. Do not retry in the same thermal round; the next separately cool route must use the repaired state-gated field profile and two-second runtime thermal polling.
- Host-only warm-cache follow-up candidate `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`, size `1,347,345,712`, avoids the redundant main-module check/hash pass when LLVM precompilation is off and skips the MFVSCR instruction scan when accurate SAT is off. Both settings are off in the Thor/Eternal Sonata profile. ARM64 RelWithDebInfo builds and the source-contract test passes; it has not been deployed or launched, so it has no startup-time, thermal, FPS, flicker, or stability credit. The installed device core remains `744CB3...E839`.
- Supersede the preceding host-only state: warm-cache core `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601` was deployed without build or launch in `20260717-035648-warm-cache-scan-skip-dev-core-push` and is the current installed development core.
- Its only guarded route, `20260717-035740-thor-input-warm-cache-scan-skip-field-proof`, began after a clean `25.0/30.0/35.5 C` battery/skin/silicon preflight. Silicon reached `73.1 C` at the first readiness frame and `75.9 C` two seconds later, so the 75 C guard force-stopped RPCSX before title or gameplay; the post-stop sample was `52.2 C` and `pidof` was empty. Classify it as `failed-thermal-guard` / `not-comparable`, with no startup, FPS, flicker, field, menu, battle, or stability credit. No second route may be charged to this round; keep the package stopped and investigate the pre-title host startup path before another separately cooled device proof.
- Host-only Android wrapper candidate removes two redundant `RTLD_NOW` validation loads at cold start: MainActivity selects readable bundled/dev files without `getLibraryVersion`, while the one active JNI open checks the version export on the same handle before activation and preserves bundled fallback. `tools/test_thor_single_core_load.ps1`, Debug Kotlin compile, and incremental ARM64 RelWithDebInfo native build pass; core `70B1...3601` is unchanged. The bounded Debug APK build timed out after `304 s` and its orphaned host compilers were stopped, so the installed APK does not contain this fix and no device credit is allowed. Finish the APK host-side before any later separately cooled, one-route proof.
- Supersede the pending APK state: exact debug-signed release-test APK `FD754ED4896920F4F725404D9BEA2E589F247021ECD0649EDEC9CF496C366015` now packages core `70B1...3601` and the single-open JNI wrapper through `-PrpcsxAndroidAbis=arm64-v8a`. Host build and APK contract checks pass, but it is not installed or launched, so no performance, thermal, flicker, field, menu, battle, or stability credit is allowed.
- Do not use `android.injected.build.abi` for a deliverable Thor APK: it can refresh only `app/build/intermediates/apk` while leaving `app/build/outputs/apk` stale. Use `rpcsxAndroidAbis=arm64-v8a` and verify `app/build/outputs/apk/release/rpcsx-thor-experiment-release.apk` with `tools/test_thor_arm64_apk.ps1`.
- The normal release APK cannot drive the guarded Thor route because its debug-only boot, direct-pad, and dev-core components are absent. Use the non-debuggable `thortest` build type, which inherits only release native settings while explicitly enabling `THOR_DEBUG_TOOLS` and the debug harness source set.
- Never put `debug` in the optimized test variant name. The rejected `reldebug` variant selected the CMake Debug core (`4677177E...F9`) despite release initialization. `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true` correctly uses RelWithDebInfo; verify the exact merged-core hash with `tools/test_thor_arm64_apk.ps1` and the variant contract with `tools/test_thor_optimized_apk_contract.ps1`.
- Exact installed ThorTest APK is `9F3379180FDCA4116A8B7F74657AC31C548398C0C2C944F6FE52F98ADD732D3E`, containing exact merged core `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601` and the single-open wrapper. Its only route, `20260717-051446-thor-input-single-open-thortest-field-proof`, lowered the first-poll absolute silicon temperature from `73.1 C` to `61.8 C` and the last-preflight-adjusted rise from `37.6 C` to `27.9 C`, but still hit `76.3 C` before title and was force-stopped. Treat this only as startup thermal-pressure improvement: no FPS, flicker, field, menu, battle, or stability credit exists.
- The package was stopped after that guard trip (`pidof` empty; post-stop `49.4 C`). No second launch may be charged to this thermal round. Inspect and reduce packaged ELF load/relocation cost on the host before another separately cooled device proof.
- Host-only loader candidate APK `70988DDF...6252` packages merged core `EC682ADA...5CDB` and stripped core `11A76D5B...F3D`; it is not installed. The Thor remains stopped on APK `9F337918...D3E` / core `70B1D394...3601`, so the new candidate has no device speed, thermal, visual, or stability credit.
- Android export localization reduces the packaged core from `81,168` defined dynamic symbols to the exact `34` `_rpcsx_*` API exports, explicit relocations from `200,205` to `583`, encoded relocation bytes from `4,804,920` to `44,219`, and stripped size from `96,438,728` to `62,823,496` bytes. Keep `tools/test_thor_core_export_surface.ps1` as the regression gate.
- The app minimum is API 29, so packed RELR must use `--use-android-relr-tags`; official `DT_RELR` tags alone require API 30. Keep `BIND_NOW`; the optimization is the much smaller relocation/export surface.
- Restrict AGP external-native targets to `rpcsx-ui-jni` plus bundled `rpcsx-android`. Without that list, Thor APK builds try to link unrelated curl/fusion/SPIRV example programs and waste host build time.
- Supersede the old loader-candidate state: exact installed ThorTest APK is `876480EED0BE5616F743F117B316D5122A7945B8A13F4CCFE5C605DB1CB891CE`, and MainActivity selects bundled merged core `EC682ADAA3EB28CBA38CEF3AA80462BE0F5886D897517EAAB18A42A5BEA55CDB` because `THOR_DEV_CORE_OVERRIDE=false`. Its inherited debug provider still observed a stale marker before MainActivity corrected the selection; do not treat the provider log as the loaded-core decision.
- Its only route, `20260717-063613-thor-input-packaged-core-isolated-loader-field-proof`, increased process-established-to-75-C-guard time from about `6.807 s` to `12.266 s` (`+80.2%`) but still showed the same `80.456%` pre-title progress frame and no title/gameplay. The first-poll adjusted rise was `29.5 C`, `1.6 C` worse than the preceding route. This is later thermal-pressure improvement only, not speed, FPS, flicker, field, menu, battle, or stability proof.
- The package is stopped. Immediate post-stop silicon was `53.8 C`; a later read-only check was `42.5 C` with `pidof` empty. No second launch may be charged to this thermal round.
- Exact final host-only ThorTest APK `60DE891CC0D6D88E9672B5A5D83E04453A5700B3570445BD4533AED6429B0AE7` additionally gates `ThorDevCoreOverrideProvider` on `THOR_DEV_CORE_OVERRIDE`; stale dev-core markers can no longer touch thortest preferences or logs. It packages the same exact merged/stripped cores and is not installed.
- The current pre-title hotspot is two-worker RSX shader-pipeline cache preload: the pulled log says `Shader cache preload workers: 2` and contains `289` captured `Add program` rows before the guard stop. The route tools now expose bounded `RsxCacheWorkers` / `AndroidRsxCacheWorkers`, default `0`/auto, and reset the property before launch and after success/failure.
- Next device work, only after a separately cool preflight, is one exact-APK `60DE...0AE7` route with `RsxCacheWorkers=1` under the existing two-second 75 C guard. Treat it as a thermal-completion experiment: it may reduce peak heat while increasing wall time, so require time-to-title plus visual proof before promotion.
- `tools/build_push_thor_core.ps1 -ResetToBundled` now asserts internal and staged cleanup separately. A non-debuggable `run-as` failure must fail closed and cannot be hidden by a later successful external cleanup.
- Supersede the prior installed-APK state: exact installed ThorTest APK is now `B76CE9F2B89AA452906D36D1D18A576BEA67F47A94D43133BB9BE9B20D532AEE`, with merged core `6338257D6033E750B884BDD126BD939D95E0A024F5A1B623D73D70D0C24B5AE9` and stripped core `BBE67717700FA4AB9088531E87A1529DBBEBE7C86449BD8B89501285D06D1E03`.
- Current upstream RSX cache work sharing is ported: load and compile workers atomically claim entries instead of using fixed halves. The Android auto cap remains two, and `Add program` is trace-only on Android while desktop notice logging is preserved. Keep `tools/test_thor_rsx_cache_preload.ps1` as its source contract.
- Its only route, `20260717-072156-thor-input-rsx-dynamic-scheduler-loader-field-proof`, still failed before title at the 75 C guard. First-poll adjusted rise improved by `5.8 C`, but process-established-to-guard duration worsened from `12.266 s` to `9.685 s`; this is conflicting thermal evidence and no speed, FPS, flicker, field, menu, battle, or stability proof.
- Android notice-level `Add program` rows fell from `289` to `0`; RSX worker decompiler errors remained essentially unchanged at `411` versus `410`. Pipeline creation remains the dominant pre-title lane.
- The package is stopped, `debug.rpcsx.thor.rsx_cache_workers=0`, and the later read-only temperature was `25/30/42.1 C`. No second route may be charged to this thermal round.
- Exact installed ThorTest APK is now `658F826DFC5494B50E23E3A0BC2AFF1EDF983C63FE053164CB485603AB69333C`; it is the deferred-preload test build. The package is stopped, the effective preload property was reset to `preload`, and the worker override remains `0`.
- Its only route, `20260717-075950-thor-input-deferred-preload-loader-field-proof`, confirmed both defer/fallback notices but failed before title. Process-established-to-guard time was `6.917 s` versus `9.685 s`, and first-poll adjusted silicon rise was `25.1 C` versus `23.7 C`.
- The only frame was visually corrupt: black upper region, flat gray lower region, and a noisy horizontal boundary. This is `failed-visual-gate` plus `failed-thermal-guard`, with no speed, FPS, flicker, field, menu, battle, or stability credit.
- The deferred-preload/interpreter path is retired from source and route controls. Keep normal preload plus the upstream atomic work-sharing change; do not rerun defer on Thor.
- Next work is host-only investigation of Vulkan pipeline-cache reuse and bounded preload cost. The one-worker normal-preload route remains parked for a later separately cool round, not approved as a default.
- Host-only Android core pipeline-cache candidate now validates the Vulkan header against vendor/device/UUID, caps persisted data at 64 MiB, seeds both normal graphics and compute pipeline creation, atomically checkpoints at 32,64,128,... creates, and saves after compiler-worker shutdown. debug.rpcsx.thor.vk_pipeline_cache=off is the rollback; route controls default/reset to on.
- tools/test_thor_vulkan_pipeline_cache.ps1, the thermal/route contract, the RSX preload contract, PowerShell AST parsing, and ARM64 RelWithDebInfo native build pass. No APK was assembled, installed, or launched, so this candidate has no speed, thermal, FPS, flicker, field, menu, battle, or stability credit.
- Official RPCS3 origin/master at 4309847 has no newer normal RSX/Vulkan pipeline-cache change after local base 1269ebf; its normal compiler still passes a null cache. Preserve the local candidate for a later separately cool saved-cache on versus off proof.
- Supersede the host-only pipeline-cache state: exact installed ThorTest APK is now `A3E9F49A727B991F77F641B5800CC1927E497D2F3FFA84133682574DEB7D5355`, containing merged core `916508B53029EE7BC3656E741199D16856C85903A838AA9E9C912F320A25481B` and packaged stripped core `43DEF9184ADD69A47548A0E894BBF73662E423D1710F422E40A5DAB365D5620F`.
- Its one guarded cold-seed route, `20260717-090825-thor-input-vk-pipeline-cache-seed-proof`, created an empty Vulkan cache and checkpointed `754,355`, `1,212,061`, then `2,239,716` bytes at 32/64/128 pipelines. The final artifact SHA256 is `76318ED124ED3B3B9710347DAD72017E092194E7AD7A6EE7E7EC3614783B26A1` with a valid Qualcomm `0x5143` / device `0x43050A01` / UUID-matched header.
- The cold-seed route still hit the 75 C guard at `75.9 C` about `6.951 s` after process establishment, before title. Its only frame was a non-corrupt `80.293%` pre-title progress frame; targeted fatal hits and decompiler errors were zero. This proves cache activation/persistence only, with no speed, FPS, thermal, flicker, field, menu, battle, or stability credit.
- The package is stopped; later read-only silicon was `48.6 C`, `pidof` was empty, and route properties are restored to cache `on`, normal `preload`, worker override `0`. No second launch may be charged to this thermal round.
- Standard Thor snapshots now pull the full `RPCSX.log`; keep this fail-stop evidence contract so a heat trip cannot discard guest cache/fatal details.
- Next device work, only after a separately cool soak, is one same-APK/config warm-cache-on route. Require `seed=2239716 bytes`, title/field visual proof, matched wall time, and thermal evidence before claiming speed; any cache-off comparison belongs to another separately cool round.
- Thor route preflight now has an independent `40.0 C` silicon launch ceiling and rejects a greater-than-`2.0 C` rise across the required three samples; this is stricter than the runtime cutoff-minus-headroom rule and is forwarded by the speed-sprint wrapper.
- Latest corrected cooldown capture `20260717-093511-vk-pipeline-cache-strict-cooldown-query` reported `25/30/44.1 C` with no RPCSX PID, so the new gate rejected launch. No emulator route ran and the `2,239,716`-byte Vulkan cache remains intact.
- The earlier `20260717-092745` ad hoc audit's `13908` PID column is host PowerShell `$PID` tooling noise; authoritative device-state and the corrected query both show RPCSX absent.
- Do not attempt the warm-cache proof until three later samples stay below `40.0 C` with rise no greater than `2.0 C`; then use the same APK/config and require `seed=2239716 bytes`.
- The same exact installed APK later accepted the `2,239,716`-byte seed in `20260717-094931-thor-input-vk-pipeline-cache-warm-proof`. It reached `512` pipeline creates by emulated `7.089 s` versus cold `128` by `6.277 s`, and process-to-guard time increased from `6.951 s` to `12.175 s`; this is startup-throughput progress only.
- That warm route still showed the identical `80.293%` pre-title frame and hit the thermal guard at `77.5 C`. No title/gameplay/FPS/stability credit exists. RPCSX is stopped, immediate post-stop was `53.0 C`, and no second route may be charged to this cool round.
- Host successor defers a validated warm cache's first checkpoint to `256` pipeline creates, avoiding the two observed unchanged `2,239,716`-byte early rewrites; empty/rejected seeds keep cold `32/64/128/...` checkpoints. Exact host-built ThorTest APK `D3048BE1...30DBA` packages merged core `FB5C9FFE...225E` / stripped core `18A55F04...7387` and passes all APK/runtime contracts; it is not installed or device-proven.
- A new host-only bounded RSX preload control keeps the normal full preload at `debug.rpcsx.thor.rsx_cache_preload_limit=0`; positive values select that many oldest pipeline descriptors (mtime, then name) and leave every omitted descriptor intact for the configured runtime cache-miss path. It does not enable the retired interpreter/deferred mode. The guarded route and wrapper expose/reset `RsxCachePreloadLimit` / `AndroidRsxCachePreloadLimit` before launch and after success or failure.
- Exact bounded-preload ThorTest APK `26A843E2A5C6DFA4408C2D6ACC2FBA3F384AB4DBCC7589E3B8EBBB0D96B198EB` packages merged core `588788A579E0A1EA9777EE6DFEC5177EFBC1C0BD7062696125DD008ED2BFA670` and stripped core `2758A909A3F5D7450EE9061CA5F754B945CD433C727137041C7477F872754B5B`. All host gates pass. It is now the exact installed APK after a guarded no-launch install; RPCSX remains stopped and no runtime credit exists.
- The no-launch install passed `35.9 -> 33.7 -> 34.7 C` preflight samples and ended at `37.7 C` with PID absent and cache/preload controls reset. Do not launch in that install round. Only after another later stable three-sample sub-40 C preflight, spend one short guarded route with `RsxCachePreloadLimit=256`, normal two-worker preload, and Vulkan cache on. Require the limit activation log plus title visual proof; do not promote the limit or claim FPS/flicker/stability from host checks.
- That one bounded-RSX route is now `20260717-103430-thor-input-bounded-preload-title-proof`. It loaded `256 of 939` RSX pipelines and moved matched startup stages about `5.95-5.99 s` earlier: PPU OPD `1.584417` versus `7.534762`, SPU runtime `2.450193` versus `8.410648`, and matching SPU warnings about six seconds earlier. This is real startup-stage progress only.
- The same route hit the `75 C` guard at `75.5 C` about `6.923 s` after process establishment while the two SPU workers were rebuilding the existing SPU cache. It did not reach title, so it receives no title/FPS/flicker/gameplay/stability credit. RPCSX is stopped and no second route may be charged to that thermal round.
- Historical evidence identifies the new startup bottleneck: full SPU cache reconstruction built `1,163` programs and took about `32.5 s` after interpreter creation. The host successor adds opt-in `debug.rpcsx.thor.spu_cache_preload_limit` / `RPCSX_THOR_SPU_CACHE_PRELOAD_LIMIT` (`0..4096`, zero means all). A positive limit registers every on-disk program identity as cached, eagerly compiles only the oldest-discovered unique prefix, preserves normal LLVM runtime misses for omitted programs, and suppresses duplicate disk appends. Oldest-first is intentional: the cache appends successful runtime JIT discoveries, and the cold-cache `20260714-233735` title route confirms early boot functions occupy the old end while later field/battle programs occupy the new end.
- Exact bounded-SPU APK `41A289BBAAD42E1B5A9FAF630A6A0F57D5BB275F6F94538F38B96FB2C94483E6`, with merged core `6775972D06E8582E8F0BAB6F2618B68DE6A63AC1738706E6423BD403F3C5E223` and stripped core `FD5A6DDA5E7C10EEE7C65AF3AB15A7203077E6863B8F82999190C248FE856AD5`, is now installed after a separately cool no-launch round. Preflight was `34.9 -> 35.5 -> 34.7 C`; on-device `base.apk` matched exactly. Capture `20260717-110738-bounded-spu-thortest-apk-install` ended PID-absent at `38.9 C` with RSX workers/RSX limit/SPU limit `0/0/0`, legacy preload, and Vulkan cache on. Do not launch in this install round; no runtime credit exists.
- Exact oldest-first APK `C44E69DE6EFA9BF214B37B246F757D989F579DCE6B87CB0FA7CF70C4135885A0` packages merged core `D3478CFA53B308664BDEF4C9C6DE8DD749E0DBF3550BB8AAEA600DCAD99C593A` and stripped core `A6DF1856624D7E595A824ABEA306E4BFA2200EA662CE9E186243C76F472E45BA`. It supersedes the newest-first candidate and is now installed after a stable `33.9 -> 33.9 -> 33.9 C` no-launch preflight; on-device `base.apk` matches exactly. Capture `20260717-113150-oldest-spu-thortest-apk-install` ended PID-absent at `34.3 C`, controls `0/0/0`, and Vulkan cache on. Do not launch in that install round; runtime proof is still pending.
- Guarded runtime capture `20260717-113647-thor-input-oldest-spu-bounded-title-proof` activated RSX `256/939` and SPU `64/1,165`; the SPU workers finished the bound in `0.385 s`. Process-to-`75.1 C` guard time expanded from `6.923 s` to `73.449 s` with PID-safe force-stop and zero targeted fatal/access-violation/unknown-draw hits. Polls remained pre-title/black, so this earns startup thermal-window progress only, not title/FPS/flicker/gameplay/stability credit. A requested retry was rejected at `47.0 -> 44.5 -> 41.3 C`; wait for three sub-`35 C` samples, then use one Start press after a guarded `12 s` wait to skip the sustained black startup sequence. Keep the `75 C` runtime ceiling.
- Supersede that pending retry: `20260717-140952-thor-input-oldest-spu-bounded-title-start-skip` passed a strict `34.1 -> 34.7 -> 34.7 C` silicon preflight and reproduced the same RSX `256/939`, SPU `64/1,165`, two-worker, Vulkan-cache activation; the SPU bound still finished in `0.423 s`. Despite equivalent startup timing, silicon jumped to `65.8 C` and then `76.3 C`, tripping the guard only `5.737 s` after process establishment and before the planned Start press. RPCSX is stopped, post-stop was `51.8 C`, and targeted fatal/access-violation/unknown-draw scans are zero. This is thermal-variance evidence, not a cache regression or speed/title/FPS/flicker/stability result. Do not launch again in this round; capture AYN performance/fan and CPU policy state before any later separately cool route.
- The route harness now writes one read-only `prelaunch-power-state.txt` before thermal preflight with AYN `performance_mode`, `fan_mode`, quick-mode setting, battery saver, CPU governors/maxima, and GPU governor/maximum. It does not change power policy. Use this evidence to reject unmatched thermal comparisons.
- Runtime thermal snapshots now collect battery, hardware skin, and all thermal-zone data in one lossless ADB shell round trip instead of three serial calls. Keep the section markers and source-contract test; this reduces guard latency without changing the two-second poll policy or any device setting.
- `llvm-readelf` before LLVM 20 expands `.relr.dyn`; `tools/test_thor_core_export_surface.ps1` must exclude that section when counting explicit relocations. Both NDK 27 and NDK 29 now report the same `34` defined exports, `583` explicit relocations, `391` jump slots, and `44,219` encoded relocation bytes.
- One-worker follow-up `20260717-145831-thor-input-oldest-spu-bounded-early-start-rsx1` reached SPU completion `0.299 s` later than the matched two-worker retry and did not reach title despite two early Start presses. It was force-stopped at `72.3 C` after `82.291 s` of established process time, with PID absent and zero targeted fatal/access/unknown-draw hits. Reject one RSX preload worker as a speed setting; do not infer a thermal win across different cool rounds.
- Host successor makes SPU function disassembly lazy and suppresses full decrementer-read dumps on Android when `SPU Debug=false`, retaining a concise notice plus full desktop/debug diagnostics. The preceding capture had 16 full dumps in a `529,579`-byte log. Exact ThorTest APK `853098D6...FB22`, with merged core `95B02FF4...0A0A` / stripped core `BE37AE11...68E4`, is now installed after a separately cool `32.7 -> 32.3 -> 32.7 C` no-launch preflight; the on-device `base.apk` matches exactly, post-install silicon was `33.1 C`, and RPCSX remains stopped. Do not launch in that install round and grant no runtime credit. Only in a different independently cool round, spend one guarded bounded route with RSX limit `256`, SPU limit `64`, normal two-worker/auto scheduling, and Vulkan cache on.
- The attempted lazy-SPU proof `20260717-155546-thor-input-lazy-spu-bounded-title-proof` was rejected before debug boot: the route preflight rose `32.5 -> 33.5 -> 33.9 C`, exceeding the strict `1 C` rise limit. RPCSX never launched and was force-stopped; no runtime credit exists and no retry is allowed in that round.
- Host successor also compiles out successful per-symbol PPU import/export logging on Android while retaining module summaries, all linkage failures, and full desktop diagnostics. The preceding log had `1,460` such rows / `267,555` bytes (`50.52%`). Exact ThorTest APK `11648B07...9B98B` packages merged core `A2C16F88...554C7` / stripped core `6D4F70BA...D048` and passes APK/source contracts. It is now installed exactly after a separately cool `31.9 -> 31.9 -> 31.7 C` no-launch preflight; on-device `base.apk` matches, post-install silicon was `33.1 C`, and RPCSX remains stopped. Grant no runtime credit and do not launch in this install round. Only a different independently cool round may spend one guarded bounded proof.
- Guarded proof `20260717-162053-thor-input-ppu-log-pruned-bounded-title-proof` dynamically removed all `1,462` successful per-symbol linkage rows and cut the captured log from `529,579` / `6,482` to `145,305` bytes / `1,402` lines while retaining `44` module summaries and zero targeted fatal hits. It still reached `77.1 C` only `5.681 s` after process establishment, essentially matching the preceding two-worker `5.737 s` guard window, and was stopped before Start/title. This is `failed-thermal-guard`, not speed/flicker/stability credit. RPCSX is stopped; do not retry this round. Next work is host-only split RSX preload scheduling: two load workers but one hot compile worker in Android auto mode, with explicit overrides preserved.
- Host successor now splits Android automatic RSX preload work: two dynamic workers remain for cached-pipeline file loading/unpacking, while one worker performs hot Vulkan pipeline compilation. Positive worker overrides and explicit shader-thread configuration still win, and desktop behavior is unchanged. Exact ThorTest APK `3C572601...CC1282` packages merged core `B955729B...3CAC` / stripped core `BFAE054B...934EB4` and passes optimized ARM64/APK/cache/preload/logging/thermal contracts. It is now installed exactly after the no-launch capture `20260717-170146-split-rsx-thortest-apk-install`: preserved raw telemetry normalized host-side to `33.9 -> 33.9 -> 33.3 C`, on-device `base.apk` matches, PID stayed absent, and post-install silicon was `35.1 C`. Controls are reset to `0/0/0`, Vulkan cache `on`, and Eternal Sonata experiment switches `off`. This is install proof only; grant no speed, thermal-runtime, title, FPS, flicker, gameplay, or stability credit.
- Runtime Thor routes now default to a `72 C` hard silicon ceiling, request an immediate confirmation snapshot once silicon reaches `60 C`, and force-stop at the initial or confirmed `68 C` early threshold. Normal cool polling remains two seconds and the strict three-sample preflight is unchanged. This is host-verified safety tooling only; the newest `64.2 -> 77.1 C` trace replays as `confirm -> stop`, but no live route has proven the confirmation timing. Do not launch in the completed install round. Only a different independently cool round may spend one guarded bounded proof of the installed split-worker APK.
- Guarded route `20260717-171312-thor-input-split-rsx-workers-bounded-title-proof` passed outer `33.5 -> 32.7 -> 33.5 C` and inner `33.9 -> 33.1 -> 33.9 C` gates, but logged `load=2, compile=2`: property value `0` was rejected instead of selecting auto, so the managed two-thread game setting won and the intended split was not tested. The live thermal successor requested confirmation at `65.4 C`, confirmed `68.7 C` after `0.609 s`, and force-stopped below the `72 C` hard ceiling before Start/title. PID ended absent; no fatal/unknown-draw hit exists. Classify as `failed-thermal-guard`, `split-worker-not-activated`, with no speed/FPS/flicker/stability credit.
- Host successor accepts `debug.rpcsx.thor.rsx_cache_workers=0` as real auto mode, keeps positive overrides authoritative, migrates Thor startup and managed Eternal Sonata shader-thread settings to `0` with profile version `14`, and defaults the manual profile tool to auto. Exact host-only ThorTest APK `D463FED6...24F8` packages merged core `B1920245...9F1A` / stripped core `992921FC...CEB9`; all relevant source, thermal, Kotlin, optimized APK, ARM64, and export contracts pass. It is not installed. Use one later separately cool no-launch install, then a different independently cool guarded proof; grant no device runtime credit yet.
- Supersede that pending state: exact ThorTest APK `D463FED6...24F8` is now installed after the no-boot cool gate `20260717-175708-thor-input-corrected-rsx-auto-worker-install-cool-gate` passed `33.5 -> 32.7 -> 33.5 C`. Capture `20260717-175947-corrected-rsx-auto-worker-thortest-apk-install` proves streamed install success, exact on-device `base.apk` hash, PID absent before/after, controls reset to `0/0/0` with Vulkan cache `on` and experiment switches `off`, and post-install silicon `34.7 C`. This is install proof only; grant no runtime/speed/FPS/flicker/stability credit and do not launch this round. Only a different independently cool round may spend one guarded bounded proof, requiring `load=2, compile=1` activation before any result.
- Corrected guarded route `20260717-180556-thor-input-corrected-split-rsx-workers-bounded-title-proof` proved `load=2, compile=1`, RSX `256/939`, SPU `64/1,165`, and the `4,899,180`-byte Vulkan seed after outer `32.7 -> 33.5 -> 33.5 C` and inner `33.5 -> 33.5 -> 33.5 C` gates. It reached `68.2 C` only `2.720395 s` after PID and force-stopped before Start/title; post-stop was `46.2 C`, PID absent, and targeted fatal hits zero. Matched startup stages were about `0.12-0.19 s` slower than two compile workers, with no observed thermal relief. Reject the split as `failed-thermal-guard` / `split-worker-rejected`; grant no title/FPS/flicker/gameplay/stability credit and do not launch again this round.
- Host successor restores the same capped dynamic worker count for RSX load and compile (`load=2, compile=2` in Android auto mode) and moves only Android's validated-warm Vulkan cache checkpoint from 256 to 512 creates, avoiding the observed synchronous unchanged `4,899,180`-byte rewrite at the bounded 256-pipeline startup edge. Cold checkpoints, desktop behavior, final persistence, and runtime miss paths remain intact. Exact host-only ThorTest APK `24F3F267...F87F` packages merged core `2B62F62E...DBA` / stripped core `BD2BB622...6C4E`; source, optimized ARM64/APK, ABI, export, thermal, and visual contracts pass. It is not installed or device-proven. Use one later separately cool no-launch install, then a different independently cool guarded proof.
- No-boot install gate `20260717-184037-thor-input-parallel-rsx-warm-checkpoint-install-cool-gate` rejected exact candidate `24F3F267...F87F` at `33.9 -> 33.9 -> 35.1 C`; sample three exceeded the strict sub-35 C ceiling and the net rise was `+1.2 C`. No install or launch ran; do not retry this round. The host harness now routes preflight exceptions through standard ForceStop/failure/thermal/PID/snapshot evidence cleanup; thermal/visual contracts and AST parsing pass, with no APK/core change. A later independently cool round must repeat install-only gating.
- Supersede that pending state: later no-boot gate `20260717-184845-thor-input-parallel-rsx-warm-checkpoint-install-cool-gate-retry` passed `33.1 -> 33.1 -> 33.1 C` with PID absent. Capture `20260717-185027-parallel-rsx-warm-checkpoint-apk-install` proves streamed install of exact APK `24F3F267...F87F`, matching on-device `base.apk` SHA-256, PID absent before/after, controls reset to `0/0/0`, Vulkan cache `on`, experiment switches `off`, and post-install silicon `35.1 C`. This is install proof only: runtime remains unmeasured, so grant no speed/title/FPS/flicker/gameplay/stability credit and do not launch this round. Only a different independently cool round may spend one bounded guarded proof requiring `load=2, compile=2` before comparison.
- Supersede the pending parallel proof: route `20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof` activated `load=2, compile=2`, RSX `256/939`, SPU `64/1,165`, and warm first checkpoint `512` with no synchronous save at 256. Matched startup stages stayed within about `0.03 s`, but process-to-68 C widened from about `3.267 s` to `6.083 s`. It still force-stopped before Start/title, post-stop was `51.4 C`, PID absent, and targeted fatal/access/device-lost/unknown-draw hits were zero. Classify `failed-thermal-guard` with startup thermal-window evidence only; grant no title/FPS/flicker/gameplay/stability credit and do not touch the device again this round.
- Host successor prunes compiler-only SPU diagnostics on Android when `SPU Debug=false` while preserving analysis, emitted code, statistics, desktop behavior, and Android debug diagnostics. Exact host-only ThorTest APK `D6204DA2...2747` packages merged core `2C2691F0...C71E` / stripped core `0834EF20...BDB7`; both changed native objects compile and all nine host contracts pass. It is not installed or device-measured. Only a later separately cool install-only round may install it, with runtime proof reserved for another independently cool round.
- Supersede host-only `D6204DA2...2747` before installation: saved route evidence with `PPU Debug=false` still had 135 verbose PPU-loader/SPU-discovery success rows / 18,521 characters (35 roaming-SPU discoveries, 23 segments, 31 sections, 10 loaded ranges, 36 special exports). Android non-debug now skips only their symbol lookup, formatting, and log I/O; guest loader/discovery work, module summaries, hashes, all failures, desktop logs, and Android PPU-debug logs are unchanged. Exact host-only ThorTest APK `3798B975...5AA1` packages merged core `47791529...D4BE6` / stripped core `49A2AD0E...D66E`; PPUModule ARM64 compile, optimized native link, ARM64-only assembly, and all ten host contracts pass. It is `device-unmeasured` and not a speed/stability claim. No device action ran; only a later separately cool install-only round may install this exact APK, with runtime proof reserved for another independently cool round.
- Install-only gate `20260717-200043-thor-input-ppu-spu-log-pruned-thortest-install-cool-gate` rejected exact candidate `3798B975...5AA1` at `31.9 -> 32.5 -> 33.1 C`: every sample was below `35 C`, but the net `+1.2 C` rise exceeded the strict `+1 C` trend limit. The harness failed closed, force-stopped RPCSX, recorded PID absent and failure-post-stop silicon `33.1 C`. No install, launch, follow-up device query, or retry ran; installed APK `24F3F267...F87F` remains unchanged. Candidate `3798B975...5AA1` stays host-verified, uninstalled, and device-unmeasured. A later independently cool round must repeat the strict install-only gate; grant no speed/FPS/flicker/stability credit.
- Fresh official RPCS3 upstream SPU LLVM `KnownFPClass` work was adapted to the older fork so clamp, multiply/equality, and FMA-family code can omit proven-unnecessary NaN/infinity/zero handling. All eleven host contracts plus ARM64 native/ThorTest builds pass. Exact host-only APK `8DAFBB2F...A1DF` packages merged core `287CF483...DC85` / stripped core `59960428...E891`; it is uninstalled and device-unmeasured, while the Thor remains on `24F3F267...F87F`. Grant no speed or temperature credit and perform no device action until a later independently cool install-only round.
- Official RPCS3 PPU LLVM hardware-FTZ optimization `e9f833a2` is adapted with a distinct PPU object-cache bit and manual denormal flushing retained for VEXPTEFP, VLOGEFP, VMAXFP, and VMINFP. A matched clean-upstream Windows BLUS30161 first-battle A/B held essentially identical FPS (`119.998` off versus `119.964` on) while sampled RPCS3 CPU fell `47.83% -> 37.60%` (`-21.4%`) and total CPU fell `54.8% -> 42.4%` (`-22.6%`). Promote `Set DAZ and FTZ: true` only in Eternal Sonata's managed/title-specific profiles; global default remains off. Exact host-only ThorTest APK `021C99D3...4344B` packages merged ARM64 core `F27ABAB2...1376B` / stripped core `341E1097...E8B2`; source contracts, ARM64 native, Kotlin, and APK builds pass. It is uninstalled/device-unmeasured, installed APK remains `24F3F267...F87F`, and no Thor temperature/speed credit exists until separately cool install/runtime rounds. Detailed ledger: `debug-experiments/20260717-arm64-ppu-ftz-upstream-slice.md`.
- Official RPCS3 `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861` reverted unsafe non-16-byte-aligned constant-address reuse for SPU LQX/STQX; the Android fork now matches it while retaining the aligned specialization and generic masked fallback. A full Windows BLUS30161 first-battle route on the rebuilt official tip stayed fatal-clean at `120.016 FPS` average, so this is correctness/stability alignment rather than a speed claim. Exact host-only ThorTest APK `0ADC1B07...D794C` packages merged core `3E960AF2...02A9` / stripped core `A49427FF...AA6E`; ARM64 native/APK, KnownFPClass, cache, reduced-loop fail-safe, ABI, optimized-variant, and export-surface contracts pass. It is uninstalled/device-unmeasured; installed APK remains `24F3F267...F87F`, and no Thor query/install/launch ran. Detailed ledger: `debug-experiments/20260717-spu-lqx-stqx-address-reuse-revert.md`.
- `tools/ps3_harness_refiner.ps1` now preserves the cleared Windows all-core promotion gate by finding a recent clean current-upstream Options proof and an exact matching build-token first-battle proof anywhere in its eight-run window. Newer analysis runs no longer send the sprint back to obsolete CPU4 routes; the next device step remains one strict thermally gated action in a separately cool round.
- Official RPCS3 commit `7e436f9bf136ad00321a97c09fb371fbd4eafe6b` is adapted so Android ARM64 lowers SPU MPY, MPYS, MPYU, MPYI, MPYUI, and MPYA through native AArch64 SMULL/UMULL intrinsics while retaining generic non-ARM64 fallbacks. Static Eternal Sonata first-battle SPU images contain 18 covered multiply sites across 10 files, but this is not a dynamic speed count. Exact host-only ThorTest APK `68A4993C...9235` packages merged core `6164DC99...9B30` / stripped core `6ACC482F...7CAC`; ARM64 native/APK and all focused contracts pass. It is uninstalled/device-unmeasured, installed APK remains `24F3F267...F87F`, no ADB/device action ran, and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260717-arm64-spu-widening-multiply-upstream-slice.md`.
- Official RPCS3 commit `61a2604824b01382bf57651b85f87b811306c2de` is adapted so guarded ARM64 SPU decrementer reads/writes use LLVM `readcyclecounter` instead of helper calls; NDK LLVM 20 lowers it to `MRS CNTVCT_EL0`, and generic fallbacks remain. The latest Thor startup log compiled 16 distinct decrementer-reading functions with loop detection off / clocks 100, while saved first-battle images contain four static RdDec rows; neither is a dynamic speed count. Exact host-only ThorTest APK `443EF144...28BD` packages merged core `1D1232C3...85D8` / stripped core `C9B59C67...F861`; ARM64 native/APK and focused contracts pass. It is uninstalled/device-unmeasured, installed APK remains `24F3F267...F87F`, no ADB/device action ran, and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260717-arm64-spu-decrementer-upstream-slice.md`.
- Official RPCS3 `9bf67f031288b3197ed07d2305da273a6ebe65bc` local-store canonicalization is adapted exactly as retained at current tip `0fcb15ab`: aligned constant LQX/STQX offsets use one negative LS mirror so LLVM does not see unrelated aliases, while the later-disabled STQD/LQD specialization is omitted and non-aligned operands retain the generic masked fallback. Saved Eternal Sonata first-battle images contain 146 covered rows across 57 files (94 LQX, 52 STQX), but this is static coverage only. Exact host-only ThorTest APK `8BF896E8...28C7` packages merged core `4DB962F7...8F83` / stripped core `12489393...D154`; ARM64 native/APK and focused contracts pass. It is uninstalled/device-unmeasured, installed APK remains `24F3F267...F87F`, no ADB/device action ran, and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260717-spu-ls-address-canonicalization-upstream-slice.md`.
- Supersede the pending canonicalization state: exact APK `8BF896E8...28C7` was installed without launch after the strict gate `20260717-231200-thor-input-spu-ls-canonicalization-thortest-install-cool-gate` passed `32.7 -> 32.3 -> 31.9 C`. On-device `base.apk` matched, PID was absent before/after, controls were reset, and no runtime action ran. This is install proof only; grant no speed/FPS/flicker/gameplay/stability credit.
- Current official RPCS3 ARM64 `VMAXFP/VMINFP` lowering is adapted so each PPU opcode emits one direct `fmax/fmin` instead of two extrema plus bitcasts and AND/OR, while explicit manual denormal flushing and the non-ARM64 path remain unchanged. Exact host-only ARM64 ThorTest APK `582F07B5...67B2A0` packages merged core `DBFF56BA...4F1D5` / stripped core `A87545D7...17AC5`; focused FTZ, ARM64 native/APK, optimized-variant, and diff contracts pass. It is uninstalled/device-unmeasured, the Thor remains on `8BF896E8...28C7`, no ADB/device action ran, and no Thor speed or temperature credit exists. SVE/SVE2 remains inapplicable, ARM FMA was already enabled, and the broad `yield -> isb` spin change remains excluded because prior global wait-loop experiments reduced Eternal Sonata FPS. Detailed ledger: `debug-experiments/20260717-arm64-ppu-extrema-upstream-slice.md`.
- Official RPCS3 `a7fc31f3212c55bf0b70b45875c52dfc94f6641a` is adapted so Android ARM64 SPU `SHUFB` with two constant-splat sources uses one `select_by_bit4` or single-table `TBL` path instead of the generic two-source shuffle; the older fork's unsafe `TBL2/TBX2` path remains parked. Saved Eternal Sonata first-battle images contain 269 `SHUFB` rows across 106 files, but this is family coverage rather than branch or execution frequency. Exact host-only ThorTest APK `89F374D9...54FE9` packages merged core `46336F37...A4402` / stripped core `16D8E877...13066`; ARM64 native/APK, focused SPU, reduced-loop fail-safe, optimized-variant, and export-surface contracts pass. It is uninstalled/device-unmeasured, the Thor remains stopped on `8BF896E8...28C7`, no ADB/device action ran, and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260717-arm64-spu-shufb-splat-upstream-slice.md`.
- Supersede that pending state: exact SHUFB APK `89F374D9...54FE9` is installed without launch after strict gate `20260718-001225-thor-input-arm64-spu-shufb-splat-thortest-install-cool-gate` passed `31.7 -> 32.3 -> 32.3 C` with only `+0.6 C` rise. Capture `20260718-002325-arm64-spu-shufb-splat-thortest-apk-install` proves streamed install success, exact on-device `base.apk` hash, PID absent before/after, controls `0/0/0`, Vulkan cache `on`, experiment switches `off`, and post-install silicon `34.1 C`. The reusable installer now fails closed unless its three-sample no-boot gate is fresh and safe and contains no activity-launch path. This is install proof only; grant no runtime speed/FPS/temperature/flicker/gameplay/stability credit. RPCSX is stopped, and only a separate independently cool round may run one guarded proof.
- That one guarded SHUFB runtime round passed outer `33.1 -> 32.3 -> 32.7 C` and inner `32.7 -> 32.3 -> 32.3 C` gates but reached `62.6 C` at the first poll and confirmed `69.1 C` about `3.275 s` after PID, so it force-stopped before Start/title. Classify `20260718-003245-thor-input-arm64-spu-shufb-bounded-title-proof` as `failed-thermal-guard` / `not-comparable`; no speed, FPS, flicker, gameplay, stability, or temperature-improvement credit exists. Host-only default-off startup cache phase pacing now generation-orders bounded SPU preload before RSX pipeline compilation, and boot failures always receive a standard snapshot. Exact ARM64-only ThorTest APK `F42042F1...D0FE` packages merged core `24B41068...53BC` / stripped core `29308D8E...BE02`; ARM64 native/APK and focused contracts pass, but it is uninstalled/device-unmeasured. No more device action ran. Detailed ledger: `debug-experiments/20260718-thor-startup-cache-phase-pacing.md`.
- Host-only default-off Vulkan cache-hit-only preload now uses Khronos pipeline cache control only for validated warm graphics-pipeline preload entries, defers `VK_PIPELINE_COMPILE_REQUIRED` misses to the unchanged runtime path, and falls back to exact normal preload when the feature/cache/property gate is absent. Exact ARM64-only ThorTest APK `C8ED84B8...F38522` packages merged core `C84683A6...1A52C9` / stripped core `37C83673...C574C`; all 23 Thor contracts, native/APK builds, export surface, binary-string, and packaged-core identity checks pass. It is uninstalled/device-unmeasured; RPCSX remains stopped and no ADB/device action ran. Grant no speed/temperature/FPS/flicker/gameplay/stability credit. Detailed ledger: `debug-experiments/20260718-thor-vulkan-cache-hit-only-preload.md`.
- Windows all-core compact 25cc verifier proof is `20260718-165758-allcore-padapi5-verify25cc-compact-first-battle` on exact RPCS3 SHA-256 `3F050FD5C4C0D167E7415E85A50E0E67E81E53234012A563165779430698BBCF`: correct title/load/field/tutorial/active battle through 150s at the 30 FPS cap, zero unknown draw/fatal rows, and strict contract `803/803` accepted with 1,607 hits, 26,329,088 bytes, zero mismatch/overflow. This is correctness proof, not speed credit.
- Compact `verify-25cc-shadow` logging reduced `RPCS3.log` from 65,986,967 to 2,134,596 bytes (`-96.765%`) while preserving strict contract rows. `RPCS3_ES_SPU_HLE_VERIFY_VERBOSE=1` restores deep GPU/MFC/shadow/descriptor diagnostics. The matched verifier-off control `20260718-164415-allcore-padapi4-verifier-off-f677-first-battle` also passed through 150s with zero fatal rows.
- The Windows field gate now requires three consecutive fatal-looking frames, and the live Windows log gate fails closed on `unknown draw command`. Keep both checks: the first avoids transient black-load false aborts; the second preserves the zero-unknown-draw promotion rule.
- Compact body-fast verifier run `20260718-171415-allcore-padapi6-verify25cc-compact-bodyfast-first-battle` stayed visually/fatal clean, but its apparent CPU drop was verifier-hashing bias. Final verifier-off isolation `20260718-173347-allcore-padapi8-bodyfast-compact1hz-verifieroff-first-battle` on SHA-256 `482C641C...C8150` also stayed correct/fatal-clean, reduced body-profiler output to 145 rows / a 1,455,245-byte log, and averaged 16.85% late RPCS3 CPU versus 17.0% control (`-0.9%`, noise). Only 15 GETs / 245,760 bytes hit while 15 PUTs fell back, so park the current 25cc body.
- No ADB/device/install/launch/read ran during the 20260718 compact-verifier/body-fast round. The Thor remains stopped and receives no new speed, temperature, FPS, flicker, gameplay, or stability credit. Profile a materially hotter host execution family before another title-gated body; Android promotion remains forbidden without verify-mode correctness proof. Detailed ledger: `debug-experiments/20260718-25cc-verifier-first-battle.md`.
- Host-only default-off Android ADPF RSX hint now measures BLUS30161 Vulkan work from first draw to flip, reports only positive cycles at or below a 30 ms target, dynamically resolves API-33 symbols for the API-29 minimum, and optionally requests Android 15 power-efficient scheduling. Exact ARM64-only ThorTest APK `84675D0D...EA93E` packages merged core `691AD168...F066B` / stripped core `775EE0EC...64E7`; optimized build, ABI, route, thermal, Vulkan, export, and no-direct-import contracts pass. It is uninstalled/device-unmeasured, Thor was not contacted, and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-android-adpf-rsx-power-hint.md`.
- Host-only default-off BLUS30161 startup compile budgets now stop issuing new optional RSX and SPU eager compilation after independent millisecond slices; in-flight calls finish, untouched entries retain normal runtime compilation, and the zero-budget RSX path preserves its original one-atomic loop. Exact ARM64-only ThorTest APK `73C44350...F91660` packages merged core `2B8898DB...04E1C` / stripped core `4796C5A7...F50D3`; optimized build, all 25 Thor source contracts, exact ABI/package identity, and export-surface checks pass. It is uninstalled/device-unmeasured, Thor was not contacted, and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-startup-compile-budgets.md`.
- Host-only default-off BLUS30161 cache-worker affinity can now move only temporary RSX load/compile and SPU preload workers onto an explicit Android mask; `0x07` selects the Thor's three Cortex-A510 cores while runtime PPU/SPU/RSX/audio/render threads remain unchanged. Single-worker RSX keeps the exact inline path when off and uses a temporary named worker when affinity is active, so the caller is never pinned. Exact ARM64-only ThorTest APK `990701CE...C93743B` packages merged core `928E7036...8AC5C5` / stripped core `57103C41...1E3131`; all 26 Thor contracts, optimized build, exact package identity, activation strings, and export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/thermal/FPS/flicker/gameplay/stability credit exists. The remaining upstream `FRSQEST` slice was rejected because the clean BLUS30161 first-battle atlas has zero matching rows. Detailed ledger: `debug-experiments/20260718-thor-startup-cache-worker-affinity.md`.
- Host-only default-off BLUS30161 SPU native-object reuse now covers the always-built LLVM interpreter plus bounded cached-program preload while retaining startup analysis, final transformed/optimized IR, current-launch helper/patchpoint mappings, and normal uncached runtime misses. V2 program/interpreter keys hash final IR through binary LLVM bitcode with preserved use-list order instead of textual formatting; schemas and `spu-native-v2/` storage were bumped together. Both decrementer-read sites retain current-launch `g_timebase_offs` relocation under the opt-in cache, while default/off lowering is unchanged. Direct pre-IR object loading remains rejected because it would skip lazily registered current-process helper mappings. Exact ARM64-only ThorTest APK `0ABDD8A3...DA5FAB` packages merged core `6548B7BA...4C150` / stripped core `38167894...C2AAA`; all 27 Thor contracts, optimized native/APK builds, exact package identity, v2/no-v1 strings, and export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/thermal/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-spu-native-object-cache.md`.
- Supersede the ARM64 interpreter portion of that state: static repository-wide and current-upstream audit proves ARM64 LLVM SPU threads always own the regular LLVM recompiler, normal LLVM instruction fallback calls C++ handlers directly, the only direct generated-interpreter caller is the `jit == nullptr` runtime branch, and the exported interpreter table is consumed only by x86-only `spu_fast`. ARM64 LLVM startup therefore skips the otherwise unconditional all-opcode interpreter JIT while Dynamic and non-ARM64 LLVM behavior remain unchanged. Exact host-only ThorTest APK `A63EEBC0...52F94` packages merged core `52F69AC0...96096` / stripped core `251EA11B...7D9C`; all 28 Thor contracts, optimized ARM64 native/APK builds, exact package identity, activation string, and export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/thermal/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-arm64-unused-spu-interpreter.md`.
- Supersede the prior LQD/STQD omission: current official RPCS3 origin/master `a7d90852` contains `9bf67f031`, whose aligned constant-base LQD/STQD specialization canonicalizes out-of-range offsets to one negative local-store mirror while preserving the generic masked fallback for non-aligned or unrecognized expressions. The latest clean Eternal Sonata first-battle log contains 470 static LQD and 300 static STQD rows, but predicate hits and execution frequency remain unmeasured. Exact host-only ThorTest APK `80EE210B...3E144` packages merged core `5E81CF4B...F7620` / stripped core `01A9B4A1...5CFF`; all 29 Thor contracts, optimized ARM64 native/APK builds, exact package identity, and export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-spu-lqd-stqd-address-canonicalization.md`.
- Current official RPCS3 `700ca262f44fda57ba260283c3f0a4772db8a573` SELB refactoring is adapted to the older vector-storage API: comparison/division matching is flattened and three constant-mask scans become one byte-granularity pass while float typing, FSMB/FSM/FSMH protection, xfloat handling, and the generic bitwise fallback remain. The latest clean Eternal Sonata first-battle log contains 144 static SELB rows across 90 unique PCs, but dynamic hits and compile-time savings remain unmeasured. Exact host-only ThorTest APK `CBBAD899...BB52E5` packages merged core `3CBB492C...4C769C` / stripped core `C6E4652D...3532AC`; all 30 Thor contracts, optimized ARM64 native/APK builds, exact package identity, and export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-spu-selb-refactor.md`.
- Current official RPCS3 `4e49c5319` / `5d62ee4b4` thread-identity fixes are adapted while preserving this fork's Android 8 MiB pthread stack: pthread_create writes to a local native handle, parent/child publication uses atomic compare/exchange, and Android kernel TIDs are resolved once per thread and reused by logging/wait ownership. Exact host-only ThorTest APK `05DDE070...817E60` packages merged core `C30FB8E7...14EC9F` / stripped core `178B010A...D81EF7`; all 31 Thor contracts, optimized ARM64 native/APK builds, exact package identity, and the 34-export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-android-thread-identity-race-fix.md`.
- Current official RPCS3 `8cc37e036` local-store mirror extension is adapted because the already-ported canonical LQD/STQD address path can reach `[-270336,532447]`, outside the old three-copy range `[-262144,524287]`. SPU LS now reserves seven regions, maps five aliases at `-2..+2`, unmaps/releases symmetrically, and fails closed on mapping-address/error mismatches. Exact host-only ThorTest APK `B87299DF...2BF03` packages merged core `1BB8ED2D...49BEC` / stripped core `6A02E15A...BB4EA`; all 32 Thor contracts, optimized ARM64 native/APK builds, exact package identity, and the 34-export surface pass. It is uninstalled/device-unmeasured; no ADB/device action ran and no speed/temperature/FPS/flicker/gameplay/stability credit exists. Detailed ledger: `debug-experiments/20260718-thor-spu-ls-mirror-coverage.md`.
- The 2026-07-18 primary-research refresh reinforces selective native offload only for dynamically hot, low-transition functions and GPU race-to-idle only for large batches without critical CPU readback. Continue compact SPU function/block profiling and contract-verified native ARM64 HLE; keep the current 0x25cc body, broad 0x25cc/0x451c Vulkan offload, and global scheduler/worker changes parked. Report: `debug-experiments/20260718-ps3-emulation-research-refresh.md`.
- Valid host-only state-aware first-battle profile `20260718-224053-es-spu-heat-stateaware-first-battle-windows` captured 32,779 active SPU samples with zero drops in the battle-only snapshot-4-to-5 window. The hottest hash `086607ca5c330290` / PC `0x00a40` held 28.4% of samples but averaged only 1.304 samples per observed entry (about 326 us at the 250 us interval); all other leaders were effectively one sample per entry. Reject a selective SPU HLE body because transitions are too frequent and pivot to compact PPU/RSX dynamic attribution. Use the promoted `StateAware` Windows battle route; the legacy timing-only route produced a false plateau and is invalid for battle claims. No ADB/device action ran and no speed/temperature/FPS/flicker credit exists. Detailed ledger: `debug-experiments/20260718-eternal-sonata-spu-heat-profile.md`.
- Normal Android builds now compile the disabled Thor wait profiler down to a direct inlined `rx::busy_wait`; diagnostics can opt the full profiler back in with `-PrpcsxThorWaitProfiler=true` or `RPCSX_THOR_WAIT_PROFILER_BUILD=true`. Host ARM64 proof removed all ten profiler calls from `semaphore_base::imp_wait()`, all seven profiler symbols and its property string from the merged library, while focused wait/frame/thermal contracts and the native build pass. This is host-verified CPU-pressure/code-removal only: no ADB/device action ran and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260719-thor-disabled-wait-profiler-overhead.md`.
- Normal Android builds now compile the default-off RSX diagnostic recorder to an always-inline false gate; diagnostics can opt it back in with `-PrpcsxThorRsxAuditor=true` or `RPCSX_THOR_RSX_AUDITOR_BUILD=true`. The independent DMA-fence, depth-feedback, texture-barrier, and blit-resolve behavior properties remain runtime-configurable. Host ARM64 proof removed all retained recorder symbols, accounting state, hot barrier atomics/property reads, and only the auditor property string; focused contracts and the native build pass. This is host-verified CPU-pressure/code-removal only: no ADB/device action ran and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260719-thor-disabled-rsx-auditor-overhead.md`.
- Normal Android builds now compile the default-off PPU syscall-statistics hook to an empty inline call and exclude its named thread, counters, reports, and property state; diagnostics can opt it back in with `-PrpcsxThorSyscallStats=true` or `RPCSX_THOR_SYSCALL_STATS_BUILD=true`, while desktop accounting is unchanged. Host ARM64 proof reduced the dispatcher from 504 to 316 bytes, removed all timer/property/CAS/LDADD statistics work, cut selected symbols 15 -> 2, and passed all 41 Thor contracts plus the native build. This is host-verified CPU-pressure/code-removal only: no ADB/device action ran and no Thor speed or temperature credit exists. Detailed ledger: `debug-experiments/20260719-thor-disabled-syscall-stats-overhead.md`.
- Normal Android builds now compile the default-off SPURS probe to empty inline
  hooks across PPU event/semaphore/timer syscalls and SPU reservation/wait
  paths; diagnostics can opt it back in with
  `-PrpcsxThorSpursProbe=true` or `RPCSX_THOR_SPURS_PROBE_BUILD=true`, while
  desktop probing is unchanged. Host ARM64 proof removed 7 PPU and 4 SPU
  probe calls, all 8 selected symbols, and all 5 property/report strings;
  the six affected hot functions shrink by 432 bytes and all 42 Thor
  contracts plus the native build pass. This is host-verified
  `stackable-cpu-pressure` only: no ADB/device action ran and no Thor speed or
  temperature credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-disabled-spurs-probe-overhead.md`.
- Normal Android builds now wholly exclude the default-off Eternal Sonata
  draw-stream snapshot/selector-repair/fault diagnostic and compile its three
  semaphore plus TTY entry surfaces to empty inline hooks. Diagnostics can
  opt it back in with `-PrpcsxThorDrawStreamProbe=true` or
  `RPCSX_THOR_DRAW_STREAM_PROBE_BUILD=true`; desktop behavior is unchanged.
  Host ARM64 proof removed all 17 selected symbols, all 11 property/report
  strings, and 13 hot semaphore/TTY references; `sys_semaphore_wait`,
  `sys_semaphore_post`, and `sys_tty_write` total 10,088 -> 7,276 bytes.
  All 43 Thor contracts and the native build pass. This is host-verified
  `stackable-cpu-pressure` only: no ADB/device action ran and no Thor speed or
  temperature credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-disabled-draw-stream-probe-overhead.md`.
- Normal Android builds now wholly exclude the default-off Eternal Sonata
  semaphore-superpath experiment: its mode parser, title/CIA checks, fast
  cache, ESRCH tracking, logging, and create/destroy/wait/post hooks are built
  only for desktop or explicit diagnostics. Opt in with
  `-PrpcsxThorSemaSuperpath=true` or
  `RPCSX_THOR_SEMA_SUPERPATH_BUILD=true`. The earlier Thor fast-mode A/B was
  slightly worse (`17.43 -> 17.03 FPS`) despite roughly 98k hits, so keep the
  behavior experiment off. Host ARM64 proof removed 11 selected symbols, 10
  property/report strings, 1,524 bytes of global state, and all 153 named
  experiment references in the four affected syscall disassemblies; their
  combined size fell 8,512 -> 6,976 bytes. All 44 Thor contracts and the
  native build pass. This is host-verified `stackable-cpu-pressure` only: no
  ADB/device action ran and no Thor speed or temperature credit exists.
  Detailed ledger:
  `debug-experiments/20260719-thor-disabled-semaphore-superpath-overhead.md`.
- Normal Android builds now compile the coupled default-off Eternal Sonata DMA
  probe and GETLLAR profiling/speed experiments to no-op/constant SPU helpers;
  kernel start/join collection and reporting are wholly excluded. Diagnostics
  can opt both families back in with
  `-PrpcsxThorEsSpuExperiments=true` or
  `RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD=true`; desktop behavior is unchanged.
  Normal GETLLAR semantics remain exactly 24 retry spins, 300 busy-wait cycles,
  normal RSX reservation locking, and no profiling. Preserve the existing
  `spu_thread::es_gpu_probe` storage/layout so persisted JIT object offsets are
  not invalidated. Prior Thor evidence rejects these as play defaults: DMA
  profile/verify fell to about 15.33/11.13 FPS with zero exact repeats, while
  the clean GETLLAR-off field result was 19.60 FPS versus 18.45 `yield8` and
  18.84 `norsx`. Host ARM64 proof removed 26 selected symbols, 9 strings,
  5,260 bytes of selected global state, and all 85 named experiment references
  in the affected disassemblies; five major functions total
  29,440 -> 23,488 bytes. All 45 Thor contracts and the native build pass.
  This is host-verified `stackable-cpu-pressure` only: no ADB/device action ran
  and no Thor speed or temperature credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-disabled-es-spu-experiments-overhead.md`.
- Normal Android builds now wholly exclude the default-off Eternal Sonata PPU
  command-isolation, dispatch-provenance, and async-draw diagnostics, including
  all ten resolver hooks and the four disabled range scans formerly run across
  each PPU function during object-cache key creation. Diagnostics can opt the
  suite back in with `-PrpcsxThorEsPpuExperiments=true` or
  `RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD=true`; desktop behavior and diagnostic
  cache-bit identity are unchanged. Three cross-translation-unit range helpers
  become constant-false normal-Android stubs and are removed by LTO. Prior Thor
  evidence rejects these as play defaults: command-interpreter modes were about
  21.14 FPS versus a comparable 27.12 FPS route without fixing corruption, and
  async settled-target write-back caused severe corruption plus a guest fault.
  Host ARM64 proof removed all 70 selected diagnostic symbols, 637,126 bytes of
  selected state, all 8 selected strings, and all 3 diagnostic calls from
  `PPUTranslator::Translate`; that function shrank 10,112 -> 2,988 bytes while
  all 13 active frame-poll wait symbols remain. All 46 Thor contracts and the
  native build pass. This is host-verified `stackable-cpu-pressure` only: no
  ADB/device action ran and no Thor speed or temperature credit exists.
  Detailed ledger:
  `debug-experiments/20260719-thor-disabled-es-ppu-experiments-overhead.md`.
- Normal Android builds now compile out the four parked RSX behavior controls
  for DMA-fence scope, depth-feedback persistence, texture-barrier skipping,
  and blit-source resolve fusion. Stock play semantics are constant-folded:
  all-command DMA fencing, normal depth feedback and texture barriers, and no
  fused/verify resolve. Desktop behavior is unchanged, and explicit Android
  diagnostics can opt back in with `-PrpcsxThorRsxExperiments=true` or
  `RPCSX_THOR_RSX_EXPERIMENTS_BUILD=true`. The experiment-only compute-resolve
  task, maps, implementation, and cleanup are also absent from normal Android.
  Host ARM64 proof reduced the core by 321,480 bytes, removed all four selected
  property strings, all ten selected mode symbols, 48 bytes of mode state, and
  all 15 selected resolve-helper symbols (5,164 text bytes, 108 RTTI/vtable
  bytes, and 80 bytes of container state). Five affected hot functions lost ten
  combined atomic/property/poll references and total 20,868 -> 19,804 bytes;
  candidate disassembly has no selected RSX-auditor or Android-property call.
  All 47 Thor contracts and the ARM64 RelWithDebInfo build pass. This is
  host-verified `stackable-cpu-pressure` only: no ADB/device action ran and no
  Thor speed, temperature, FPS, flicker, gameplay, or stability credit exists.
  Detailed ledger:
  `debug-experiments/20260719-thor-disabled-rsx-experiments-overhead.md`.
- Normal Android builds now compile out the failed global ARM64 busy-wait
  batching experiment and execute the existing direct timer/yield polling loop.
  Explicit diagnostics retain light/fast/aggressive modes through
  `-PrpcsxThorBusyWaitExperiment=true` or
  `RPCSX_THOR_BUSY_WAIT_EXPERIMENT_BUILD=true`. Prior matched Thor field A/B
  rejected batching: `19.35 FPS` off versus `18.15` fast and `17.72` light,
  with correct visuals but worse throughput. Host ARM64 proof removes the
  property string, 12 bytes of mode/guard state, 260 bytes of parser/init text,
  and the 340-byte out-of-line `rx::busy_wait` wrapper; LTO inlines the direct
  loop instead. The core shrinks by 50,296 bytes. `semaphore_base::imp_wait`,
  `rsx::thread::run_FIFO`, and `spu_thread::process_mfc_cmd` total
  10,248 -> 9,752 bytes, with nine guard/mode calls plus one wrapper call gone.
  All 13 active frame-poll wait symbols remain, all 48 Thor contracts and the
  ARM64 RelWithDebInfo build pass. This is host-verified
  `stackable-cpu-pressure` only: no ADB/device action ran and no Thor speed,
  temperature, FPS, flicker, gameplay, or stability credit exists. Detailed
  ledger:
  `debug-experiments/20260719-thor-disabled-busy-wait-experiment-overhead.md`.
- Normal Android builds now compile out the retired SPU reduced-loop
  detect-only scanner, including its property lookup, candidate/pattern maps,
  scan lambdas, logging, and emitter registration. Explicit diagnostics retain
  detector-only mode through `-PrpcsxThorSpuReducedLoopDiagnostics=true` or
  `RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS_BUILD=true`; desktop is unchanged,
  and unsafe Android emission remains unconditionally disabled. This removes
  default-off work from `spu_recompiler_base::analyse`, which matters during
  the historical 1,163-program / 32.5-second full SPU cache reconstruction.
  Host ARM64 proof reduced that function 49,760 -> 48,840 bytes, removed its
  Android property call and empty candidate-map destructor call, and removed
  the detect property/log strings. The whole core shrank by 200,096 bytes and
  the LTO input object by 287,692 bytes; those whole-artifact deltas include
  debug-information removal and are supporting evidence only. Reduced-loop
  reuse and dynamic-MFC experiment strings deliberately remain, all 13 active
  frame-poll wait symbols remain, all 49 Thor contracts pass, and the final
  incremental ARM64 RelWithDebInfo build passes. This is host-verified
  `stackable-cpu-pressure` only: no ADB/device action ran and no Thor speed,
  temperature, FPS, flicker, gameplay, or stability credit exists. Detailed
  ledger:
  `debug-experiments/20260719-thor-disabled-spu-reduced-loop-diagnostics-overhead.md`.
- Normal Android builds now compile reduced-loop result reuse and dynamic-MFC
  lowering to constant false under the existing default-off Eternal Sonata SPU
  experiment gate. Explicit diagnostics retain both property-controlled paths
  through `-PrpcsxThorEsSpuExperiments=true` or
  `RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD=true`; desktop is unchanged. This is
  baseline behavior: reuse cannot be reached while unsafe Android reduced-loop
  emission is clamped off, and dynamic-MFC lowering had no promoted speed or
  correctness result. Host ARM64 proof removed both property strings, 336
  bytes of parser text, 9 bytes of reuse guard/state, all selected helper/state
  symbols, and the dynamic-MFC IR stub name. `spu_llvm_recompiler::compile`
  shrank 47,776 -> 46,520 bytes, `WRCH` 10,768 -> 10,740 bytes, and
  `spu_cache::initialize` 14,268 -> 14,152 bytes. Their selected default-path
  experiment references fell `2 -> 0`, `2 -> 0`, and `4 -> 3`; the remaining
  cache property calls are active independent controls. The core shrank by
  33,760 bytes, all 13 active frame-poll wait symbols remain, all 49 Thor
  contracts pass, and ARM64 RelWithDebInfo passes. This is host-verified
  `stackable-cpu-pressure` only: no ADB/device action ran and no Thor speed,
  temperature, FPS, flicker, gameplay, or stability credit exists. Detailed
  ledger:
  `debug-experiments/20260719-thor-disabled-spu-compiler-experiments-overhead.md`.
- Normal Android builds now compile the forensic PRX-dump hook to constant
  false under the existing Eternal Sonata PPU-diagnostics gate. The Android
  property lookup, target parser, output-path formatter, and success/failure
  reports are absent, while normal `PPU Debug` executable dumping and desktop
  behavior remain unchanged. Explicit diagnostics retain the hook through
  `-PrpcsxThorEsPpuExperiments=true` or
  `RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD=true`. Host ARM64 proof reduced
  `prx_load_module` 5,624 -> 3,956 bytes, removed the 1,584-byte dump-path
  helper, changed its selected property/path calls `1/1 -> 0/0`, removed all
  three selected property/report strings, and preserved the one
  `dump_executable` call. The linked core shrank by 58,208 bytes, all 13 active
  frame-poll symbols remain, all 49 Thor contracts pass, the explicit
  diagnostic branch passes an ARM64 syntax compile, and ARM64 RelWithDebInfo
  passes. This is host-verified `stackable-cpu-pressure` only: no APK, ADB,
  device, FPS, temperature, flicker, gameplay, or stability credit exists.
  Detailed ledger:
  `debug-experiments/20260719-thor-disabled-prx-dump-overhead.md`.
- Android's native logcat listener now uses the system-property area serial to
  refresh live logging controls only when properties change, rather than
  calling `get_system_time()` for every native log message and polling once
  per second. Enable and minimum priority publish in one packed atomic;
  default behavior, `debug.rpcsx.thor.logcat`, `log.tag.RPCS3`, level mapping,
  actual logcat writes, and Quiet/Normal/Verbose switching remain unchanged.
  Host ARM64 proof removes the selected clock call `1 -> 0`, adds one cheap
  property-area-serial check, keeps both property-get callsites behind the
  change branch, keeps `__android_log_write` `1 -> 1`, shrinks
  `LogListener::log` 464 -> 460 bytes, and reduces filter state 13 -> 8 bytes.
  All 50 Thor contracts and ARM64 RelWithDebInfo pass. This is host-verified
  `stackable-cpu-pressure` only: no APK, ADB, device, FPS, temperature,
  flicker, gameplay, or stability credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-logcat-property-serial-filter.md`.
- Normal Android runtime logging now keeps the complete 32 MiB-buffered plain
  `RPCSX.log` but omits the continuously compressed level-9 `.gz` duplicate;
  desktop dual-output behavior is unchanged. Host ARM64 proof removes every
  selected `deflateInit2`/`deflate`/`deflateEnd`/`fchmod` call from logger
  construction, flush, shutdown, and premature close while preserving the
  plain-file write path. Five selected functions total 2,716 -> 1,592 bytes,
  the linked core shrinks by 11,872 bytes, all 13 active frame-poll symbols
  remain, all 51 Thor contracts pass, and ARM64 RelWithDebInfo passes. This is
  host-verified `stackable-cpu-pressure` only: no APK, ADB, device, FPS,
  temperature, flicker, gameplay, or stability credit exists. Detailed
  ledger:
  `debug-experiments/20260719-thor-android-plain-log-writer.md`.
- Android's plain Log Writer now blocks on an armed 32-bit atomic when empty
  instead of scheduling a 10 ms poll for the entire emulator lifetime.
  Producers notify only after committing ring-buffer bytes and only when the
  writer is armed; shutdown uses the same wake before joining, and desktop
  keeps its original timer policy. Host ARM64 proof changes the writer proxy
  from `sleep_for 1 -> 0` to `atomic_wait_engine::wait 0 -> 1`; the normal
  producer path adds one load/branch, the rare armed path performs the
  exchange/notify, and the linked core shrinks by 392 supporting bytes. All
  13 active frame-poll symbols remain, all 52 Thor contracts pass, and ARM64
  RelWithDebInfo passes. This is host-verified `stackable-cpu-pressure` only:
  no APK, ADB, device, FPS, temperature, flicker, gameplay, or stability
  credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-android-event-log-writer.md`.
- Android's single plain-log listener now uses a 4 MiB pending ring instead
  of the desktop 32 MiB ring and no longer carries the dead 64 KiB gzip
  scratch array. Across 24 saved Thor logs, the largest complete route log is
  1,606,357 bytes, so the pending ring remains 2.611x larger than the largest
  entire capture while the on-disk maximum and 32 KiB write chunk are
  unchanged. Host ARM64 proof changes the ring allocation/memset
  33,554,432 -> 4,194,304 bytes, removes the 65,540-byte member memset, and
  reduces aligned listener storage 65,792 -> 256 bytes. That avoids
  29,425,664 bytes (28.0625 MiB / 7,184 pages) of allocation and startup
  zeroing. All 13 active frame-poll symbols remain, all 53 Thor contracts and
  ARM64 RelWithDebInfo pass. This is host-proven stability-memory and
  `stackable-cpu-pressure` credit only: no APK, ADB, device, FPS, temperature,
  flicker, gameplay, or runtime-stability credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-android-log-buffer.md`.
- Android's native logcat listener now defaults to warning rather than
  verbose when `debug.rpcsx.thor.logcat` and `log.tag.RPCS3` are unset. The
  complete plain `RPCSX.log` still retains all levels; warning, TODO, error,
  and fatal system-log output remains, and the direct fatal crash report still
  bypasses the regular filter. Quiet, Normal, and Verbose profiles retain
  explicit live overrides. Across 24 retained Thor logs, 87,813 level-marked
  listener messages were observed; WARN preserves 16,732 and suppresses an
  expected 71,081 (80.946%) system-log calls on the same mix. Host ARM64 proof
  changes the packed initial state `0x80000002 -> 0x80000005`, changes the
  unset-priority fallback `2 -> 5`, shrinks `LogListener::log`
  `460 -> 452` bytes, and shrinks the core
  `1,304,706,256 -> 1,304,706,248` bytes (`-8`). The property-area check,
  dynamic property reads, one regular logcat callsite, 34 exports, and all 13
  active frame-poll symbols remain; all 53 Thor contracts and ARM64
  RelWithDebInfo pass. This is host-verified `stackable-cpu-pressure` only:
  no APK, ADB, device, FPS, temperature, flicker, gameplay, or runtime credit
  exists. Detailed ledger:
  `debug-experiments/20260719-thor-android-logcat-warn-default.md`.
- On 2026-07-19, routine Android compile-log pruning made cached PPU module
  successes PPU-Debug-only, compiled generic successful RSX pipeline rows out
  of Android, and collapsed two per-translator ARM64 feature notices into one
  process-level summary. Across 24 saved captures this targets 2,170 of 2,194
  calls (98.906%) and 219.866 KiB of historical records while retaining every
  failure, RSX trace identity, pipeline notification, opt-in PPU detail, and
  desktop behavior. All 54 Thor contracts and Android ARM64 RelWithDebInfo pass;
  the selected CPU text shrinks 4 bytes, `ppu_initialize` grows 32 bytes, and
  the full debug-bearing core grows 2,440 bytes. Exact 72,842,472-byte ThorTest
  APK `7CDD38E4...E5F9` is installed after strict no-boot gate
  `20260719-154756-thor-input-compile-log-batch-install-cool-gate` passed
  31.9 -> 32.3 -> 31.7 C. Capture
  `20260719-154833-compile-log-batch-thortest-apk-install` proves matching
  on-device hash, PID absent, controls reset, and 37.7 C post-install silicon.
  No launch occurred; grant no runtime speed, temperature, flicker, gameplay,
  or stability credit. Detailed ledger:
  `debug-experiments/20260719-thor-android-compile-log-pruning.md`.
- Normal Android now compiles the unproven ADPF RSX performance-hint
  experiment to a constant-false/no-op gate; explicit diagnostics can restore
  it with `-PrpcsxThorAdpfRsxHint=true` or
  `RPCSX_THOR_ADPF_RSX_HINT_BUILD=true`. This removes the selection path from
  every Vulkan draw and present: `VKGSRender::begin` shrinks `1,000 -> 164`
  bytes and `flip` `10,224 -> 9,416`, while the core shrinks 17,304 bytes and
  all selected ADPF symbols/strings disappear. Both explicit-diagnostic and
  final normal ARM64 builds pass, along with all 54 Thor contracts and the 13
  active frame-poll symbols. This is host-verified `stackable-cpu-pressure`
  only: the installed `7CDD38E4...E5F9` APK remains force-stopped and no ADB,
  APK, FPS, temperature, flicker, gameplay, or runtime credit exists. Detailed
  ledger: `debug-experiments/20260719-thor-adpf-normal-build-gate.md`.
- The 2026-07-19 combined title attempt passed a strict no-boot gate at
  `31.5 -> 32.3 -> 31.9 C` but was force-stopped at the early thermal guard:
  the first visual snapshot was `59.0 C`, immediate confirmation was `68.7 C`,
  and the title was not reached. The log stopped during RSX shader-cache load,
  before cache-phase pacing or Vulkan pipeline compilation, so neither path
  gets runtime credit. Do not retry until an independently cool round. The
  loader emitted 412 duplicate-heavy fragment-decompiler errors in roughly
  296 ms; Android Vulkan BLUS30161 preload workers now retain one diagnostic
  per kind and worker and emit one aggregate count after load. Saved-log replay
  predicts 13 representative writes and 399 suppressed duplicates (96.8%).
  Runtime diagnostics, shader semantics, and non-Android behavior are
  unchanged. All 55 Thor contracts and ARM64 RelWithDebInfo pass. The next
  cool proof should package/install without launch in its own gate, then use
  efficiency-core cache-worker affinity `0x07`, RSX/SPU preload limits
  `256/64`, cache-phase pacing, and Vulkan cache-hit-only under the same
  `68/72 C` guard. No device speed or temperature improvement is claimed.
  Detailed ledger:
  `debug-experiments/20260719-thor-combined-title-thermal-stop.md`.
- Android native overlay startup no longer runs the desktop/Linux relative,
  executable-share, or executable-local icon fallbacks. Capture
  `20260719-163325-thor-input-custom` showed 60 failed opens/error broadcasts
  for 15 absent icons, including 45 impossible desktop-path opens and 15
  `/proc/self/exe` reads. Android now preserves one config-directory probe per
  icon and emits one aggregate warning; desktop lookup and ordinary image
  errors are unchanged. All 56 Thor contracts and ARM64 RelWithDebInfo pass;
  the debug-bearing core shrinks `1,304,702,360 -> 1,304,683,120` bytes
  (`-19,240`). This is host-verified startup-I/O reduction only and should ride
  the next planned APK, not trigger an extra device run. Detailed ledger:
  `debug-experiments/20260719-thor-android-overlay-resource-lookup.md`.
- Exact combined host candidate APK `504C614B...5588` is ARM64-only and
  uninstalled. It packages merged core `3AF46260...E7B` (`1,304,683,120`
  bytes) as stripped core `ABB14ECC...D5B` (`63,014,472` bytes); the APK ZIP
  entry matches the stripped hash exactly. ARM64 ABI, optimized ThorTest,
  direct entry identity, and all 56 Thor contracts pass. The installed APK
  remains `7CDD38E4...E5F9`, RPCSX remains stopped, and no device query ran.
  A later genuinely cool round may only install `504C614B...5588` under the
  strict no-boot gate and must not launch; one guarded title proof requires a
  separate cooling round. Detailed ledger:
  `debug-experiments/20260719-thor-combined-host-candidate-apk.md`.
- Use `-AndroidStartupProfile ThorCoolTitle` for the next guarded title proof,
  not a hand-assembled control list. Host-only `-Action AndroidProfileStatus`
  proves the exact resolution without ADB. The profile requires the PPU-ready
  title macro, `35 C` launch ceiling, `68/72 C` early/hard stop, three-sample
  preflight, RSX/SPU limits `256/64`, two RSX workers, cache-worker affinity
  `0x07`, Vulkan cache plus hit-only preload, cache-phase pacing, quiet logs,
  no Perfetto/video, and force-stop. Conflicting explicit arguments, wrong
  actions, and keep-running requests fail before serial resolution. All 57
  Thor contracts pass. Normal wrapper defaults are unchanged. The exact
  `504C614B...5588` APK still requires a separate cool no-launch install round
  before this profile may launch in another cooling round. Detailed ledger:
  `debug-experiments/20260719-thor-cool-title-profile.md`.
- The `ThorCoolTitle` route now validates its saved title screenshot and guest
  log, executes `stop` inside the macro, and returns without the old redundant
  one-second `Invoke-AndroidSceneCapture` interval. One combined pre-boot ADB
  shell snapshot records all 26 exact cache, affinity, quiet-log, disabled
  experiment, and frame-wait properties without adding 26 round trips.
  `tools/analyze_thor_cool_title_capture.ps1` fails closed unless those values,
  eight runtime activation rows, two-frame title stabilization, the final title
  image, fatal cleanliness, thermal cleanliness, and force-stop evidence all
  agree. The rejected `20260719-163325-thor-input-custom` capture classifies as
  `thermal-stop-before-title` at `68.7 C`, with the old zero-valued controls
  reported and no speed credit. All 58 Thor contracts pass. This is host-only
  route-duration and evidence-hardening work: no ADB/device action or runtime
  speed/temperature/flicker/stability credit exists. Detailed ledger:
  `debug-experiments/20260719-thor-cool-title-proof-gate.md`.
- BLUS30161 Android startup SPU preload now matches its worker pool to the
  opt-in cache-affinity mask before constructing LLVM workers. With the
  `ThorCoolTitle` `0x07` mask on the eight-thread Thor, the bounded 64-program
  preload requests up to eight workers but creates three for the three A510
  cores, avoiding five oversubscribed compiler threads/contexts. Mask-off
  Android, other titles, desktop, SPU semantics, cache identity, and runtime
  misses are unchanged. The route analyzer now requires the `workers=3,
  mask=0x7` activation row. All 58 Thor contracts and incremental ARM64
  RelWithDebInfo pass; the build took 66.6 seconds. This is host-verified
  startup contention/memory-pressure reduction only: no APK/ADB/device action
  or runtime speed/temperature/flicker/stability credit exists. Detailed
  ledger:
  `debug-experiments/20260719-thor-spu-affinity-worker-cap.md`.
- Exact refreshed ARM64-only ThorTest candidate APK
  `5C3911D0...682CC6` (`72,840,516` bytes) supersedes the uninstalled
  `504C614B...5588` artifact by stacking the three-worker SPU affinity cap.
  It packages merged core `EC3B31C5...5728E` (`1,304,685,608` bytes) as
  stripped core `75A11633...86DC9` (`63,014,824` bytes), and the APK ZIP
  entry matches the stripped length/hash exactly. Relative to the prior
  host candidate, merged/stripped cores are `+2,488/+352` bytes while the
  compressed APK is 64 bytes smaller; these are supporting build deltas, not
  speed evidence. The 98.1-second optimized build, ARM64 ABI, ThorTest variant,
  single-open loader, 34-export surface, eight activation gates, packaged-core
  identity, and all 58 Thor contracts pass. It is uninstalled, the last-known
  installed APK remains `7CDD38E4...E5F9`, no device query ran, and RPCSX
  remains stopped. A future independently cool round may only install this
  exact APK through the strict no-launch gate; do not launch in that round.
  Detailed ledger:
  `debug-experiments/20260719-thor-spu-cap-host-candidate-apk.md`.
- Exact APK `5C3911D0...682CC6` is now installed on Thor under the strict
  no-launch boundary. Fresh gate
  `20260719-181421-thor-input-custom` passed `31.7 -> 31.5 -> 31.1 C`
  silicon (maximum `31.7 C`, rise `-0.6 C`), battery `22.0 C`, skin `30.0 C`,
  with `BootGame=False` and `ForceStop=True`. Install capture
  `20260719-181508-spu-cap-thortest-apk-install` proves host/on-device hashes
  match, PID was absent before/after, controls are reset, no activity launch
  occurred, and post-install temperature was `34.5 C` silicon / `22.0 C`
  battery / `30.0 C` skin. Stop this device round here: do not query or launch
  again. After a separate cooling interval, the only allowed runtime step is
  one self-stopping `ThorCoolTitle` proof under the `35 C` launch and
  `68/72 C` early/hard thermal gates. Installation grants no speed, FPS,
  temperature, flicker, gameplay, or stability credit. Detailed ledger:
  `debug-experiments/20260719-thor-spu-cap-no-launch-install.md`.
- The install-only thermal gate now has an explicit empty
  `strict-cool-gate` input profile plus
  `tools/invoke_thor_strict_cool_gate.ps1`. Its default `Status` action is
  host-only; explicit `Run` supplies the exact no-boot/force-stop thermal
  contract and returns one machine-readable validated capture directory.
  The profile rejects boot or mismatched limits before ADB resolution. This
  removes unsupported-profile and host-stream path scraping from future
  installs without weakening the gate. All 59 Thor contracts pass; no ADB or
  device action ran, so this is route-tooling only. Detailed ledger:
  `debug-experiments/20260719-thor-strict-cool-gate-wrapper.md`.
- The one exact-APK cool-title route
  `20260719-183040-thor-input-custom` passed `31.9 -> 31.7 -> 31.5 C`
  preflight, then hard-stopped at `72.7 C` before title, `13.242 s` after PID;
  post-stop was `49.4 C` and targeted fatal hits were zero. It receives no
  speed/FPS/flicker/gameplay/stability/temperature-win credit and no second
  launch ran.
- Runtime disproved two host assumptions: cache phase pacing waited `5,003 ms`
  before SPU generation `1` had started, and managed `Max LLVM Compile
  Threads=2` produced `requested=2, workers=2, mask=0x7`, not `8 -> 3`. Those
  two workers built all 64 bounded programs in about `1.679 s` immediately
  before the hottest interval.
- The next same-APK cool-title profile disables the impossible phase wait and
  sets the existing SPU eager-compile budget to `100 ms`; RSX/SPU selections
  remain `256/64`, Vulkan warm hit-only stays on, affinity stays `0x07`, and
  all fail-stop/visual gates remain. Native phase pacing also bypasses its
  timeout if the current SPU generation has not started. The analyzer expects
  two SPU workers, budget activation, phase pacing off, and classifies thermal
  macro failures even without a separate `status=failed` row. Do not install:
  exact installed APK `5C3911D0...682CC6` already supports these property
  controls. Only after another separate cooling interval may one self-stopping
  `ThorCoolTitle` proof run. Detailed ledger:
  `debug-experiments/20260719-thor-cool-title-thermal-counterproof.md`.
- The next cool-title attempt `20260719-184713-thor-input-custom` found Thor at
  `44.9 C` on preflight sample 1 against the `35 C` launch ceiling and refused
  boot. Failure evidence had no PID; the post-stop snapshot was `45.8 C`, and
  no retry/device query ran. The analyzer classifies it separately as
  `preflight-refused-hot`, not a launched thermal stop, with no speed credit.
- Source tracing then found Thor debug boot bypassed
  `GameSettingsDatabase.applyRecommendedConfig` and could race the async game
  list, explaining why the prior launched log still had `Set DAZ and FTZ:
  false` despite the BLUS30161 managed profile requiring true. Future packaged
  debug boots pass explicit `BLUS30161`, apply by title ID, and fail closed
  before native boot unless the managed profile is current/applied; user custom
  configs are never overwritten. All 59 Thor contracts and ThorTest Kotlin
  compile pass. Installed APK `5C3911D0...682CC6` is unchanged and does not
  contain this Kotlin gate. After an independently cool interval, first run
  only its same-APK 100 ms SPU-budget proof for isolation; package/install the
  managed-profile/native successor later under separate no-launch and runtime
  rounds. Detailed ledger:
  `debug-experiments/20260719-thor-debug-managed-profile-gate.md`.
- The one same-APK SPU-budget route
  `20260719-190316-thor-input-custom` passed its strict preflight at
  `34.3 -> 33.5 -> 33.9 C`, launched PID `30771` once, and force-stopped at
  `71.1 C`, `7.186 s` after PID, before the title. The 100 ms SPU budget did
  activate: `5/64` programs were built in about `0.183 s` and `59` retained
  the normal on-demand path, versus `64/64` in about `1.679 s` previously.
  The first sysmodule load advanced from about `10.555` to `3.968` emulator
  seconds (`~6.59 s`), but this is startup-progress evidence only. The run
  began up to `2.4 C` hotter, reached the same `61.8 C` first readiness sample,
  and hit the guard sooner, so grant no title/FPS/flicker/gameplay/stability,
  thermal-win, or end-to-end speed credit. Do not retry this device round.
- The remaining measured early burst was RSX cache read/unpack/decompile:
  about `1.892 s` from load start to compile start. A new Android-only,
  BLUS30161-only, default-off `rsx_cache_load_budget_ms` stops claiming new
  cache entries after `500 ms`; already-started entries finish and untouched
  pipelines retain the unchanged on-demand load/compile path. The
  `ThorCoolTitle` profile now requires `500 ms`, records exact property and
  runtime activation evidence, and resets it on every exit. The analyzer also
  correctly distinguishes normal preflight rows in a launched capture from a
  real preflight refusal when the post-stop PID probe fails.
- Exact uninstalled ARM64-only ThorTest successor
  `54CC0C37...D82892` (`72,838,248` bytes) packages merged core
  `406166AC...2F737E` (`1,304,689,712` bytes) as stripped core
  `5F11CFD2...7CC10` (`63,015,752` bytes); the APK entry matches the stripped
  hash and length. It also includes the managed-profile debug gate and native
  phase-wait bypass absent from installed APK `5C3911D0...682CC6`. All `61/61`
  host contracts and both ARM64 builds pass; no build worker remains. Install
  only in a future cool no-launch round, then wait for another independently
  cool round before one self-stopping runtime proof. Detailed ledger:
  `debug-experiments/20260719-thor-spu-budget-thermal-counterproof.md`.
- The first install-only attempt for successor `54CC0C37...D82892` was
  refused by strict gate `20260719-192621-thor-input-strict-cool-gate` at
  preflight sample 1: silicon was `48.2 C` against the `35 C` ceiling, then
  `48.6 C` after force-stop; battery/skin were `23.0/30.0 C`. No install or
  activity launch occurred, the installed APK remains `5C3911D0...682CC6`,
  and no retry or follow-up device query may run in this round. The refusal
  exposed that no-boot failures lacked saved PID evidence and their wrapper
  errors omitted the capture directory. Future failures save post-stop
  `failure-pid.txt`, propagate `ThorCaptureDirectory`, and report
  `capture_dir=...`; successful gate output and all safety thresholds remain
  unchanged. Exact successor `54CC0C37...D82892` remains uninstalled and must
  wait for a later independently cool install-only round. Detailed ledger:
  `debug-experiments/20260719-thor-spu-budget-thermal-counterproof.md`.
- Supersede uninstalled ThorTest `54CC0C37...D82892` before installation.
  Cold managed-profile boot had parsed the `292,581`-byte settings database
  up to three full times: bundled and local during export, then local again
  at the fail-closed debug gate. It now reads only the trusted bundled header
  for its timestamp, falls back to a full bundled parse if that fast path
  cannot validate, caches the selected local snapshot, and reuses it. The
  managed YAML is also read and its expected body built once rather than
  reread/rebuilt after a successful no-op or write. Existing custom configs
  remain untouched, exact content/timestamp staleness still fails closed, and
  write failures still recheck disk state. All `59/59` `test_thor_*.ps1`
  contracts, ThorTest Kotlin compile, optimized ARM64-only packaging, ABI,
  variant, merged-core, and APK-entry identity checks pass. Exact host-only
  successor `24FCC44E...736FE2` is `72,839,316` bytes and retains merged core
  `406166AC...2F737E` / stripped entry `5F11CFD2...7CC10` byte-for-byte. It is
  uninstalled/device-unmeasured; installed APK remains `5C3911D0...682CC6`,
  no ADB/device action ran, and no speed or thermal credit exists. Only a
  later independently cool no-launch round may install `24FCC44E...736FE2`;
  runtime proof remains reserved for another cool round. Detailed ledger:
  `debug-experiments/20260719-thor-spu-budget-thermal-counterproof.md`.
- Exact APK `24FCC44E...736FE2` is now installed on Thor after strict no-boot
  gate `20260719-195049-thor-input-strict-cool-gate` passed silicon
  `30.7 -> 30.5 -> 31.1 C` (maximum `31.1 C`, rise `+0.4 C`), with battery
  `23.0 C` and skin `30.0 C`. Install capture
  `20260719-195101-managed-profile-startup-thortest-apk-install` proves the
  host and on-device `base.apk` hashes match exactly, `adb install -r`
  succeeded, RPCSX PID was absent before and after, force-stop ran at both
  boundaries, no activity launched, and post-install silicon was `33.1 C`.
  The installed candidate includes the BLUS30161 managed-profile gate,
  hardware FTZ profile, phase-wait bypass, `500 ms` RSX load budget support,
  and settings-database/YAML startup compaction. Installation grants no
  runtime speed, temperature, FPS, flicker, gameplay, or stability credit.
  Stop this device round here: do not query or launch again. After a separate
  independently cool interval, the only allowed device action is one
  self-stopping `ThorCoolTitle` proof that confirms `Set DAZ and FTZ: true`,
  the RSX load-budget activation/deferred count, title reach, thermal behavior,
  visuals, and fatal cleanliness. Detailed ledger:
  `debug-experiments/20260719-thor-spu-budget-thermal-counterproof.md`.
- The next `ThorCoolTitle` proof is now pinned fail-closed to installed APK
  `24FCC44E...736FE2` for package `net.rpcsx.easy`, with merged core
  `406166AC...2F737E` and packaged core `5F11CFD2...7CC10` recorded in
  `tools/thor_cool_title_candidate.psd1`. Before any thermal sample or boot,
  the route resolves the single installed `base.apk`, hashes it on-device,
  saves exact identity evidence, and refuses a mismatch. Because all three
  strict thermal samples follow the hash, the gate includes that check's
  small heat cost. The profile rejects conflicting APK overrides, and the
  analyzer requires the exact identity plus managed-profile
  `Set DAZ and FTZ: true` activation. Synthetic wrong-hash and missing-FTZ
  captures fail `activation-incomplete`; all `59/59` host contracts pass.
  This host-only hardening made no APK/core change, did not contact Thor, and
  grants no runtime speed, temperature, FPS, flicker, gameplay, or stability
  credit. Installed APK remains exact `24FCC44E...736FE2` with RPCSX stopped.
  Wait for a separate independently cool interval before the one
  self-stopping runtime proof. Detailed ledger:
  `debug-experiments/20260719-thor-spu-budget-thermal-counterproof.md`.
- Exact installed APK `24FCC44E...736FE2` completed the single 2026-07-20
  `ThorCoolTitle` route. Capture `20260720-104152-thor-input-custom` passed
  exact on-device APK identity and preflight at `32.3 -> 31.9 -> 31.9 C`,
  established PID `13727`, first detected the title at `19.295 s`, held it
  for the required second sample at `24.710 s`, saved exact title image
  `F0D03AC6...5B73`, and self-stopped. Silicon peaked at `48.2 C`, title
  proof was `45.8 C`, post-stop was `40.9 C`, and no thermal guard fired.
  This is a large title/thermal-progress signal versus the two preceding
  `71.1/72.7 C` stops before title, but not a comparison-ready speed or
  temperature win: the saved `RPCSX.log` was only `2,671` bytes and stopped
  at emulator time `0.010546 s`, so all 11 native activation rows and full
  fatal cleanliness are unproven. Classify it
  `title-proof-log-incomplete` / `not-comparable`; grant no FPS, field,
  battle, menu, flicker, gameplay, or stability credit. No second device
  route ran.
- The Android event-driven Log Writer now retains notification as its fast
  path but wakes at most once per second as a liveness fallback, preventing a
  small final batch from remaining memory-only until Android force-stop. This
  is still about `100/s -> <=1/s` idle wakeups versus the original desktop
  10 ms polling policy. The analyzer now diagnoses a stable title with a
  sub-one-second runtime log as `title-proof-log-incomplete`. All `59/59`
  host contracts, optimized ARM64 native build, export/optimized-variant
  checks, and ARM64-only APK identity pass. Exact uninstalled successor APK
  `E69ABCB0...8073` (`72,839,336` bytes) packages merged core
  `857B0A5A...877E` (`1,304,689,776` bytes) as stripped entry
  `CC2FF22E...A3CA` (`63,015,752` bytes). Installed APK remains
  `24FCC44E...736FE2`; use a later independently cool install-only round,
  then reserve another cool round for one self-stopping proof. Detailed
  ledger: `debug-experiments/20260720-thor-title-proof-log-liveness.md`.
- Add new dated facts to the ledger. Update this file only for standing rules, current state, or repeated gotchas.
- The 2026-07-22 bounded cache-preparation retry is a wrong-input-root
  counterproof, not a speed result. Capture
  20260722-154128-firmware-ppu-prewarm accepted BLUS30161 but the old native
  route treated the ISO as EBOOT, failed it, scanned the whole PS3 ROM parent,
  and timed out at 150.11 s with native completion absent. Silicon peaked at
  55.4 C, post-stop was 38.6 C, PID was absent, and no game boot occurred.
  The successor resolves the selected ISO through a unique read-only virtual
  device, validates exact PS3_GAME/PARAM.SFO title BLUS30161, constrains
  scanning to that ISO's PS3_GAME, and removes the virtual device afterward.
  All 66/66 host contracts, ARM64 native compile, optimized ARM64-only
  package, candidate identity, and APK-entry checks pass. Exact uninstalled
  successor APK BBAD241D...550B89 (72,834,260 bytes) packages merged core
  E1B05DC9...99C6 as stripped core 83EB9B07...8B28. Installed APK remains
  1DCDBBEB...6F4885; no device action ran after the failed capture. A later
  cool round may install the exact successor without launch, then a different
  cool round may run one bounded prewarm. Grant no speed, temperature, FPS,
  flicker, field, menu, battle, gameplay, or stability credit yet. Detailed
  ledger: debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Strict cool gate 20260722-160903 passed at 32.7 -> 33.1 -> 32.9 C
  (post-run 33.9 C), but the outer host composition refused before installation
  because a child PowerShell process surfaced both the nested Write-Host line
  and machine-readable capture path. No adb install, launch, retry, or
  follow-up query ran. invoke_thor_strict_cool_gate.ps1 now suppresses the
  nested information stream with 6>$null; its contract passes. Exact successor
  BBAD241D...550B89 remains uninstalled and installed APK logically remains
  1DCDBBEB...6F4885. Wait for a separate cool install-only round. This is
  route-tooling only and grants no performance or stability credit. Detailed
  ledger: debug-experiments/20260720-thor-title-proof-log-liveness.md.
- Exact bounded-ISO-root successor BBAD241D...550B89 is now installed after
  strict no-boot gate 20260722-162508 passed silicon 32.9 -> 32.9 -> 33.5 C
  (maximum 33.5 C, rise +0.6 C), with battery/skin 23.0/30.0 C. Install capture
  20260722-162521 proves expected, host, and installed hashes match, RPCSX PID
  was absent before and after, no activity launched, and post-install silicon
  was 35.1 C. This grants installed identity only, with no speed, temperature,
  FPS, flicker, gameplay, or stability credit. Stop this device round. After a
  separate independently cool interval, run one bounded cache preparation;
  reserve title/field/menu/battle proof for a later round. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.

- The installed BBAD241D...550B89 cache-preparation route then resolved the
  exact BLUS30161 ISO PS3_GAME root and analyzed the main PPU, but crashed at
  emulator time about 1.294 s because caller-participating ppu_initialize
  renamed a raw Kotlin/JNI thread with no thread_ctrl current object. Capture
  20260722-164057-firmware-ppu-prewarm stayed cool at
  33.9 -> 32.9 -> 33.1 C preflight, 34.7 C peak, and 33.5 C post-stop; no game
  boot occurred and final PID was absent. The old harness then waited its full
  bound despite the dead process. Host successor 95DF7F6C...ED6D36 follows
  current upstream by keeping both configured PPU compile lanes in a full
  named_thread_group and making the foreign JNI caller wait only. Logcat
  target-process death now ends the harness within the next poll. Optimized
  ARM64 native/APK builds, all 66/66 Thor contracts, ABI, exact artifact,
  packaged-core, and 35-export gates pass. Exact APK is 72,834,216 bytes;
  merged core 15353CF1...7E6996 is 1,304,250,032 bytes; packaged core
  32B0BD6D...04A0E2 is 62,983,368 bytes. The successor is uninstalled and
  device-unmeasured: classify failed / host-fixed / successor-uninstalled /
  not-comparable with no speed, FPS, thermal-win, flicker, gameplay, or
  stability credit. Install only after a separate strict cool no-launch round,
  then reserve cache preparation for a different cool round. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.

- Exact named-worker successor 95DF7F6C...ED6D36 is now installed after
  strict no-boot gate 20260722-170704 passed silicon
  33.1 -> 33.3 -> 33.1 C (maximum 33.3 C, rise 0.0 C), with battery/skin
  23.0/30.0 C. Install capture 20260722-170716 proves expected, host, and
  installed hashes match, RPCSX PID was absent before and after, no activity
  launched, and post-install silicon was 35.3 C. This grants installed
  identity only, with no speed, temperature, FPS, flicker, cache-completion,
  gameplay, or stability credit. Stop this device round. After a separate
  independently cool interval, run one bounded cache preparation; reserve
  title/field/menu/battle proof for later rounds. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.

- One independently cool cache-preparation round on exact installed
  95DF7F6C...ED6D36 reached module 16/41 and compiled 16 objects without the
  prior raw-JNI-thread crash. Capture 20260722-172750 passed preflight at
  32.1 -> 31.9 -> 31.9 C, peaked at 55.4 C, ended at 36.1 C with PID absent,
  and contained exact ISO/title/root, named-worker affinity 0x7, no fatal, and
  no game boot. It timed out at 152.514 s before native/callback completion,
  so classify stable-native-thread-fix / bounded-progress / not-comparable,
  with no FPS, startup-speed, gameplay, flicker, or thermal-win credit.
  Upstream RPCS3 d8710c431 fixes a separate vendored named_thread_group index
  and naming defect exposed by the full worker pool. The exact port plus a
  90-second resumable checkpoint harness is built host-only as APK
  A7216402...3D15C; all completed cache objects are atomically committed. Do
  not install it until a later strict cool no-launch round, then run at most
  one checkpoint in another cool round. Detailed ledger:
  debug-experiments/20260720-thor-title-proof-log-liveness.md.

- Exact resumable-cache successor A7216402...3D15C is now installed after
  strict no-boot gate 20260722-180609 passed silicon
  30.5 -> 30.9 -> 31.5 C (maximum 31.5 C, rise +1.0 C), with battery/skin
  23.0/30.0 C. Install capture 20260722-180621 proves expected, host, and
  installed hashes match; RPCSX PID was absent before and after, no activity
  launched, and post-install silicon was 33.5 C. This grants installed
  identity only, with no cache-completion, speed, temperature-win, FPS,
  flicker, field, menu, battle, gameplay, or runtime-stability credit. Stop
  this device round. After a separate independent cooldown, run at most one
  90-second cache checkpoint; reserve title/gameplay proof for later rounds.

- The post-install cache controller now accepts a bounded timeout only when
  the current log proves both durable validated reuse (`Module exists` or
  `Loaded module` > 0) and new
  progress (`Compiled module` > 0), plus two distinct `PPUW` worker names.
  The saved pre-fix 20260722-172750 capture correctly replays as reuse=false,
  worker-count=1, so it cannot satisfy the successor checkpoint contract.
  All 66/66 Thor host contracts pass. No device contact followed installation;
  after an independent cooldown, run one 90-second checkpoint and stop.

- Exact installed A7216402...3D15C completed one independently cool 90-second
  cache checkpoint in capture 20260722-183628-firmware-ppu-prewarm. Exact APK,
  ISO/root/title, affinity 0x7, and distinct PPUW.1.1/PPUW.1.2 workers passed;
  16 prior objects were validated as LLVM: Module exists and 10 new objects
  compiled, leaving 15 of the 25-module continuation workload. Preflight was
  30.9 -> 30.7 -> 30.9 C, runtime averaged 38.10 C and peaked at 40.2 C with
  zero samples at or above 50 C, post-stop was 34.9 C, PID was absent, and no
  fatal, process death, or game boot occurred. The original host result was a
  false rejection because stopped-emulator preparation reports validated reuse
  as Module exists, not Loaded module; the corrected parser replays this as
  reuse=16 / compiled=10 / workers=2 and therefore a clean progress checkpoint.
  No retry or follow-up ADB action ran. Classify cache-progress-checkpoint /
  native-worker-correctness / thermal-progress / not-comparable, with no FPS,
  startup-speed, gameplay, flicker, or controlled thermal-win credit. After a
  separate later cooldown, run at most one more checkpoint; require complete
  cache preparation before title/field/menu/battle proof.

- The next independently cool checkpoint
  `20260722-190850-firmware-ppu-prewarm` again matched exact installed APK
  A7216402...3D15C, ISO/root/title, two distinct PPU workers, and affinity
  requested/effective `0x7`. It validated all 26 durable prior objects,
  compiled 10 more, and reached `10/15`, leaving only 5 modules. Preflight was
  `31.5 -> 31.3 -> 31.1 C`; the 90-second runtime averaged `37.84 C`, peaked
  at `39.0 C`, and post-stop was `35.5 C`. No fatal, process death, callback,
  game boot, or residual PID occurred. Classify `cache-progress-checkpoint` /
  `thermal-progress` / `not-comparable`, with no FPS, startup-speed, gameplay,
  flicker, or controlled thermal-win credit. Do not contact Thor again in this
  round. After a separate cooldown, one final 90-second checkpoint should
  finish the five remaining modules; require native completion and the
  callback before title proof.

- The cool-title analyzer now exposes first-title, stable-title, and stability
  window milliseconds from the bounded PPU-ready gate. Comparison-ready proof
  requires those timings in addition to current frame-replay title validity;
  the saved launcher false positive returns null timings, and a synthetic real
  title without elapsed timing fails proof-sequence-incomplete. All 66/66
  Thor host contracts pass. This is host-only route hardening: exact installed
  APK A7216402...3D15C and its core are unchanged, no device contact occurred,
  and no startup-speed or FPS credit exists. Use the metrics only after the
  final five cache modules complete in a separately cool round.

- The third independently cool cache checkpoint
  `20260722-194141-firmware-ppu-prewarm` matched exact installed APK
  A7216402...3D15C and completed the five-module initial EBOOT workload by
  emulator time 62.05 s. It then entered the firmware SPRX scan, reached file
  `70/142`, and completed `8/11` modules discovered so far; three known modules
  remained and two `libhttp` objects were in flight at the bounded stop. The
  run reused 114 validated objects and compiled eight new objects. Preflight
  was `30.7 -> 30.7 -> 30.7 C`; 25 runtime samples averaged `37.42 C`, peaked
  once at `48.6 C`, and had zero samples at or above `50 C`; post-stop was
  `33.7 C`. No native fatal, unplanned process death, game boot, or residual
  PID occurred. The old host parser skipped file-prefixed progress rows and
  therefore misreported stale `4/5`; its phase-aware replay now reports EBOOT
  `5/5`, file `70/142`, and discovered module `8/11`, and the focused route
  contract passes. Classify `cache-progress-checkpoint` /
  `initial-eboot-complete` / `firmware-scan-progress` / `thermal-progress` /
  `not-comparable`; there is still no startup-speed, FPS, gameplay, flicker,
  stability, or controlled thermal-win credit. Do not assume one final module
  or one final round: later independently cool checkpoints must finish the
  growing firmware scan and produce native plus callback completion before
  the separately cooled title proof.

- The resumable cache controller now probes at `50 C`, stops at `55 C`, and
  retains a `60 C` hard silicon ceiling instead of the generic `56/68/72 C`
  runtime envelope. Its strict below-`35 C` launch gate, three-sample trend,
  90-second bound, atomic cache commits, forced stop, and absent-PID proof are
  unchanged. Device-free Status reports the exact `50/55/60 C` contract and
  the focused cache route test passes. This is host-only safety hardening: the
  frozen APK/core and Thor state are unchanged, and no performance or thermal
  win is claimed. Use this stricter controller for the next independently
  cooled firmware-cache continuation.

- The next independently cool checkpoint
  `20260722-201353-firmware-ppu-prewarm` matched exact installed APK
  A7216402...3D15C, reused 122 validated objects, compiled 16 new firmware
  modules, and advanced the growing scan from file `70/142`, module `8/11` to
  file `83/142`, module `16/21`. Preflight was `30.5 -> 29.9 -> 30.3 C`;
  26 runtime samples averaged `38.10 C`, peaked once at `49.4 C`, and never
  reached the new `50 C` confirmation threshold. Post-stop was `34.5 C`.
  Native completion and callback remain absent, but no native fatal, process
  death, game boot, or residual PID occurred. A warm EBOOT emits no standalone
  module-progress row; the host parser now treats firmware-scan entry as proof
  that the EBOOT phase returned successfully without mislabeling firmware
  `0/1` as EBOOT progress. Classify `cache-progress-checkpoint` /
  `warm-eboot-complete` / `firmware-scan-progress` / `thermal-progress` /
  `not-comparable`. Do not contact Thor again in this round. Continue only
  after another independent cooldown; require native plus callback completion
  before the separate title/gameplay proof.

- Future cache-checkpoint READMEs now summarize every runtime silicon sample:
  count, average, minimum, peak, samples at/above `45 C`, and samples at/above
  the `50 C` confirmation threshold. Confirmatory samples are included, empty
  or preflight-refused runs report deterministically, and a pure host fixture
  locks the arithmetic. This is device-free evidence hardening; it changes no
  APK/core/cache bytes and grants no performance or thermal-win credit.

- Cache preparation now enforces a 30-minute independent interval from the
  latest completed `firmware-ppu-prewarm` README before resolving ADB. Its
  device-free Status reports the latest capture, completion/ready timestamps,
  readiness, and remaining seconds; missing or malformed latest evidence fails
  closed. The strict temperature gate remains a second, independent check.

- After the enforced interval, checkpoint
  `20260722-204551-firmware-ppu-prewarm` passed exact APK/source/affinity and
  strict preflight at `30.9 -> 30.9 -> 30.5 C`. It reused 138 validated objects,
  compiled 15 new firmware modules, and advanced to file `92/142`, current
  discovered workload `15/19` with four known modules remaining. The new
  summary recorded 25 runtime samples averaging `38.3 C`, minimum `35.1 C`,
  peak `48.2 C`, two at/above `45 C`, zero at/above `50 C`, and post-stop
  `34.3 C`. Native completion/callback remain absent; no fatal, process death,
  game boot, or residual PID occurred. Classify `cache-progress-checkpoint` /
  `warm-eboot-complete` / `firmware-scan-progress` / `thermal-progress` /
  `not-comparable`. Do not compare growing per-run module totals as cumulative
  progress; file position and committed-object reuse are the continuity proof.
  No more Thor contact before the new 30-minute gate passes.

- The next independently cool round
  `20260722-211758-firmware-ppu-prewarm` passed exact identity/source/affinity
  and preflight `31.3 -> 31.5 -> 30.1 C`, reused 153 objects, compiled 16, and
  advanced to firmware file `104/142` with 38 files remaining. At `77.817 s`,
  after 21 samples no higher than `39.0 C`, sample 22 reached `55.4 C`; the
  controller immediately force-stopped at its `55 C` early threshold below the
  `60 C` hard ceiling. Post-stop was `35.5 C`, PID was absent, and there was no
  fatal, process death, callback, native completion, or game boot. Classify
  `thermal-stop-with-durable-cache-progress` / `safety-pass` /
  `not-comparable`; the next cool run must prove the 16 atomic objects persisted
  by reusing at least 169 before credit. No more Thor contact before
  `2026-07-22T21:49:31.1302428-04:00` and a fresh strict cool gate.

- After the late `55.4 C` cache stop, the host controller now defaults to a
  `70 s` bound instead of `90 s`, checks elapsed time immediately after each
  thermal decision before log collection, and caps its final sleep to the
  exact remaining bound. The latest and prior dangerous spikes arrived about
  `76.3 s` and `73.3 s` after their first runtime samples, while completed
  objects had already been atomically committed. This is host-only safety
  hardening: exact installed APK/core/cache identity is unchanged. The host
  now derives `minimum_required_reused_modules=169` from that thermal-stop
  README and refuses checkpoint credit below the floor. The next independently
  cool run must still prove continuity by reusing at least 169
  objects, and no title/gameplay proof may run until native plus callback
  completion.

- The next independently cool cache round
  `20260722-215019-firmware-ppu-prewarm` proved the thermal-stop continuity
  floor exactly: it reused 169 validated objects, compiled 16 more, and
  advanced the firmware scan from file `104/142` to `118/142`, leaving 24
  files. Strict preflight was `30.9 -> 30.1 -> 30.3 C`; the new 70-second
  bound recorded 20 runtime samples averaging `38.0 C`, peaking at `48.2 C`,
  with zero at/above `50 C`, and post-stop silicon `34.1 C`. Native completion
  and callback remain absent, but no fatal, unplanned process death, game boot,
  or residual PID occurred. The live loop now polls only the newest 500 logcat
  rows and latches request markers, while the complete final logcat remains
  saved. Classify `cache-progress-checkpoint` / `continuity-pass` /
  `safety-pass` / `not-comparable`, with no speed, FPS, flicker, gameplay,
  stability, or controlled thermal-win credit. Do not contact Thor again
  before `2026-07-22T22:21:44.5031527-04:00` and a fresh strict cool gate;
  require native plus callback completion before title/gameplay proof.

- Cache continuity is cumulative after both thermal stops and normal progress
  checkpoints. The latest checkpoint's 169 reused plus 16 compiled objects set
  `minimum_required_reused_modules=185` for the next run; the prior reset to one
  after a normal checkpoint is retired. Malformed continuity evidence fails
  closed. This is host-only evidence hardening with frozen APK/core/cache bytes
  unchanged and no device contact. The next cool continuation must reuse at
  least 185 objects before checkpoint credit.

- Exact installed A7216402...3D15C completed stopped-emulator cache preparation
  in `20260722-222211-firmware-ppu-prewarm`. It reused the required 185
  validated objects, compiled 24 new objects, finished firmware file `142/142`
  and module `24/24`, and produced both native-completed and callback-finished
  evidence in 59.58 seconds. Strict preflight was
  `31.1 -> 30.5 -> 30.1 C`; 17 runtime samples averaged `37.8 C`, peaked at
  `46.6 C`, and never reached `50 C`; post-stop was `33.3 C`. Exact APK,
  ISO/root/title, affinity `requested=0x7,effective=0x7`, no fatal/process
  death/game boot, and absent PID before/after all passed. Classify
  `cache-prepared-exact-no-game-boot` / `continuity-pass` / `safety-pass` /
  `not-comparable`, with no speed, FPS, flicker, gameplay, stability, or
  controlled thermal-win credit. Do not contact Thor again before a separate
  independent cooldown; the next device action is one self-stopping exact-APK
  `ThorCoolTitle` baseline, followed only in later cool rounds by field/menu/
  first-battle correctness and matched performance proof.
- The first post-cache exact-APK title baseline
  `20260722-225338-thor-input-custom` passed strict preflight at
  `31.3 -> 30.9 -> 30.9 C` and exact installed identity, but the only frame at
  `1.243 s` was still pre-title. Silicon rose through `50.6` and `65.0 C`, then
  confirmed `69.9 C`; the `68 C` early guard force-stopped below the `72 C`
  hard limit. Post-stop was `44.1 C`, PID was absent, thermal status was zero,
  and the saved log reached only emulator time `4.077166 s`. Managed FTZ,
  Vulkan seed/hits-only, RSX `load=2,compile=2` plus `500 ms` budget, and SPU
  two-worker affinity plus `5/64` budgeted preload activated; no PPU compile
  affinity row appeared before stop. The hottest saved GPU sensor was only
  `35.2 C`, so classify the burst CPU-side. This is
  `thermal-stop-before-title` / `failed` / `not-comparable`, with no speed,
  FPS, thermal-win, flicker, gameplay, or stability credit. Do not contact Thor
  again in this round. The host-only `ThorCoolTitle` successor uses a stricter
  `64/68 C` early/hard guard (`52 C` probe); keep the exact APK/cache frozen
  and investigate the CPU/SPU startup burst before another independently cool
  one-shot proof.
- Host-only successor
  `8F1C9838EFC428AB5E4DDBFF2E433A4BDA1A79BD41FB086CEF820653C01D1C25`
  moves bounded SPU native-object compilation out of the simultaneous title
  startup burst and into the stopped-emulator cache-preparation action. It is
  BLUS30161/LLVM/property gated, selects at most 64 oldest programs, retains
  the 100 ms compile budget and exact `0x7` cache-worker affinity, and requires
  ordered native evidence plus verified `off/0/0` property cleanup. ARM64
  native and optimized ARM64-only APK builds, exact packaging, and focused
  host contracts pass. Thor was not contacted, the successor is not installed,
  and no speed/thermal/gameplay credit exists. Keep no-launch install, stopped
  SPU seeding, and warm title proof in separate independently cool rounds; see
  `debug-experiments/20260722-thor-stopped-spu-native-prewarm.md`.
- Exact successor
  `8F1C9838EFC428AB5E4DDBFF2E433A4BDA1A79BD41FB086CEF820653C01D1C25`
  is now installed after strict no-boot gate
  `20260722-232951-thor-input-strict-cool-gate` passed silicon
  `33.3 -> 33.9 -> 33.3 C` (maximum `33.9 C`, rise `0.0 C`) with
  battery/skin `23.0/30.0 C`. Install capture
  `20260722-233018-stopped-spu-prewarm-successor-thortest-apk-install`
  proves expected/host/installed hashes match, PID absent before/after, no
  activity launch, safe experiment controls, and post-install silicon
  `34.9 C`. This grants installed identity only and no performance, thermal,
  gameplay, or stability credit. The cache controller now selects the newer
  of the latest cache or no-launch install as its 30-minute cooldown source;
  host-only status refuses this install until
  `2026-07-23T00:00:25.9542488-04:00` before resolving ADB. Do not contact Thor
  again before then and a fresh strict cool gate; run only one stopped-emulator
  SPU seed in that later round.
- Exact installed `8F1C9838...C01D1C25` then ran one stopped-emulator seed in
  `20260723-000120-firmware-ppu-prewarm` after strict gate
  `20260723-000042-thor-input-strict-cool-gate` passed at
  `32.7 -> 32.1 -> 32.9 C`. The callback and PPU/SPU phases completed, `209`
  PPU modules were reused, all `142/142` firmware files completed, and SPU
  workers built `6/64` of `1,165` unique programs under the `100 ms` budget.
  Peak silicon was only `36.3 C`, post-stop was `33.9 C`, PID was absent, and
  properties reset. Classify it `failed-evidence-gate` / `not-comparable`
  because the controller had not applied cache-worker mask `0x7` and the
  native-cache enabled row was not durable. Grant no speed, FPS, gameplay,
  stability, or thermal-win credit. Exact host successor
  `D6584048525CFDFF5342D39F350391B44A366038BCE11A24B9F8E3363F4E77CE`
  applies/verifies/reset-readbacks affinity `7/0`, requires a three-worker pool,
  and emits native-cache enablement at Android `Always`. Optimized ARM64 native
  and APK builds, exact package/core identity, and all `66/66` Thor host
  contracts pass. The APK is `72,834,432` bytes; merged core
  `BC9D58E5...E8CF1` is `1,304,246,096` bytes and packaged core
  `74B7EC4D...78C0C` is `62,983,800` bytes. It is uninstalled and
  device-unmeasured. Do not contact Thor again before a new cooldown,
  no-launch install round, and later separately cool seed round.

- Exact successor `D6584048...E77CE` is now installed after strict no-boot gate
  `20260723-003158-thor-input-strict-cool-gate` passed silicon
  `31.9 -> 32.1 -> 32.3 C` (maximum `32.3 C`, rise `+0.4 C`) with battery/skin
  `23.0/30.0 C`. Install capture
  `20260723-003221-affinity-proof-spu-prewarm-successor-thortest-apk-install`
  proves expected/host/installed hashes match, PID was absent before and after,
  every startup experiment control remained at its safe default, no activity
  launched, and post-install silicon was `36.1 C`. This grants installed
  identity only, with no speed, temperature-win, FPS, flicker, gameplay, cache
  seed, or stability credit. Stop this device round. Do not contact Thor before
  `2026-07-23T01:02:28.4844422-04:00`; after that independent interval, run at
  most one stopped-emulator seed and reserve title/gameplay proof for later
  cool rounds.

- The host cache controller now turns the prior safe seed's `0` loaded plus
  `6` built SPU objects into a cumulative native-object continuity floor.
  Device-free Status reports `minimum_required_spu_native_objects=6`; the next
  completed seed cannot pass unless at least six exact v2 objects load before
  newly built objects are counted. Each later safe completed seed raises the
  floor by loaded plus built objects, capped at the selected `64`. Missing,
  partial, unsafe, fatal, process-death, unclean-property, or game-boot evidence
  fails closed. All `66/66` Thor host contracts pass. Installed APK/core and
  device state are unchanged; no ADB contact followed the no-launch install.

- Exact installed `D6584048...E77CE` completed one independently cool
  stopped-emulator seed in `20260723-010252-firmware-ppu-prewarm`. Exact APK
  identity passed; preflight was `31.7 -> 32.3 -> 31.5 C`, runtime was
  `1.544 s` with one `35.9 C` sample, and post-stop was `32.9 C`. The PPU
  phase reused `209` objects and completed firmware `142/142`; the SPU phase
  built `6/64` under the `100 ms` budget with affinity `0x7`, but it loaded
  zero native objects, reported native cache disabled, and used only `2/2`
  workers. PID was absent, properties reset, and there was no fatal or game
  boot. Classify `failed-evidence-gate` / `safe-counterproof` /
  `not-comparable`, with no speed, FPS, gameplay, stability, flicker, or
  thermal-win credit. Root cause: the SPU runtime captured an empty cache path
  before the stopped route configured the PPU cache, and the controller never
  supplied its intended three-worker override.

- Exact host successor
  `5044976A53036961883A3723ECE8C54811B6AEB45D4EB1116ACD802D40D83E5C`
  lazily refreshes the SPU native-cache path, adds a title-gated stopped-prewarm
  worker limit, and makes the controller set/verify/reset that limit at `3`.
  Only successful native-cache evidence can establish a continuity floor, so
  both failed six-build captures correctly produce `spu_continuity_capture=none`
  and `minimum_required_spu_native_objects=0`. ARM64 native and APK builds,
  exact artifact/optimized/ABI gates, and all `66/66` Thor host contracts pass.
  The APK is `72,835,952` bytes; merged core `9A22B5B2...2E1065` is
  `1,304,256,560` bytes and packaged core `29472380...6EDDF` is `62,984,952`
  bytes. It is uninstalled and device-unmeasured. Do not install before a
  separate independently cool no-launch round; reserve the seed and title/
  gameplay proofs for later cool rounds.

- Exact successor `5044976A...D83E5C` is now installed after strict no-boot gate
  `20260723-013345-thor-input-strict-cool-gate` passed silicon
  `30.9 -> 31.3 -> 31.1 C` (maximum `31.3 C`, rise `+0.2 C`) with
  battery/skin `23.0/30.0 C`. Install capture
  `20260723-013419-lazy-native-cache-path-spu-prewarm-successor-thortest-apk-install`
  proves expected/host/installed hashes match, PID was absent before and after,
  no activity launched, startup controls were safe, and post-install silicon
  was `32.7 C`. This grants installed identity only, with no native-cache
  persistence, speed, temperature-win, FPS, gameplay, flicker, or stability
  credit. Stop this device round. Device-free Status selects this install as
  the cooldown source and refuses cache preparation before
  `2026-07-23T02:04:26.6355691-04:00`; run at most one stopped seed in a later
  independently cool round.

- Host-only title-route repair now makes the exact `ThorCoolTitle` profile
  consume the durable SPU native objects produced by stopped prewarm. Global
  and normal-route defaults remain `off`; only this pinned BLUS30161 proof
  profile requires native cache `on`. Its analyzer requires both captured
  effective state and startup property `on`, the dry-run reports
  `spu_native_object_cache=on`, explicit `off` conflicts fail closed, and all
  `66/66` Thor host contracts pass. No APK/core rebuild, install, launch, ADB,
  or device query occurred. This is route-tooling only and grants no speed,
  FPS, thermal-win, gameplay, flicker, or stability credit. Keep exact
  installed APK `5044976A...D83E5C` frozen; first prove one stopped native-cache
  seed after the independent cooldown, then use a later cool round for title.

- The host title analyzer now also refuses comparison readiness unless the
  guest log proves both `Thor SPU native-object cache enabled...` and at least
  one exact `LLVM: Loaded module: ...obj` row. Property-on without activation
  or reuse is `activation-incomplete`. Synthetic omission tests and all
  `66/66` Thor host contracts pass. No APK/core/device action occurred; this is
  proof-hardening only and grants no performance or correctness credit.

- The same host analyzer now expects the profile's current `68 C` hard ceiling
  instead of stale `72 C` README/thermal fixtures. Synthetic ready, thermal
  stop, and preflight-refusal captures plus all `66/66` contracts pass. This is
  host-only route repair; no device contact or performance credit.

- Exact installed successor `5044976A...D83E5C` completed one stopped-emulator
  seed in `20260723-020444-firmware-ppu-prewarm`. Strict preflight was
  `30.9 -> 31.1 -> 31.3 C`; bounded runtime was `1.535 s` with one `35.1 C`
  sample; post-stop was `32.5 C`. PPU reused `209` validated objects and
  completed firmware/workload `142/142` and `64/64`. SPU native cache enabled,
  preload/budget were `64/100 ms`, exact pool/affinity were `3/3` and `0x7`,
  and seven native objects were built. Properties reset, PID was absent,
  callback finished, and no fatal/process death/game boot occurred. Local
  continuity floor is now `7`; no device contact before
  `2026-07-23T02:35:03.3577951-04:00`. This proves a safe durable seed only,
  not speed/FPS/gameplay/flicker/stability/thermal-win. In one later cool round,
  run the native-cache-on title proof requiring actual activation and at least
  one loaded `.obj`; do not seed or launch again in this round.

- `ThorCoolTitle` now checks the device-free cache-preparation Status before
  serial/ADB resolution. It requires matching package/title/APK identity, a
  successful continuity capture, native cache `on`, at least one durable SPU
  object, `device_contact=False`, and the 30-minute cooldown ready. During the
  new cooldown, a route using invalid serial `must-not-be-resolved` failed
  locally with `remaining=1488s`; no ADB/device command ran. Profile dry-run,
  AST parsing, and all `66/66` host contracts pass. Other profiles/actions are
  unchanged. This is host-only thermal safety, not performance credit.

- The cooldown gate now passes its exact successful seed floor into the title
  analyzer. For current capture `20260723-020444...`, title readiness requires
  all `7/7` native objects loaded, not merely one. Loads are counted only after
  the SPU native-cache activation marker and before the worker summary, avoiding
  unrelated PPU/JIT rows. A synthetic `1/2` capture fails
  `activation-incomplete`; default `1/1`, JSON persistence, AST parsing, and all
  `66/66` host contracts pass. No APK/core/device action occurred. This is
  proof-hardening only and grants no performance or correctness credit.
- Host-only title cleanup proof now records one batched post-stop readback of
  all 21 transient RSX/SPU/Vulkan/ADPF/affinity/experiment properties,
  including the six title-only frame-wait/superpath controls. A title
  capture is comparison-ready only when force-stop evidence, absent PID, and
  every safe reset value agree. Missing evidence and a synthetic leaked
  `spu_native_object_cache=on` both fail `proof-sequence-incomplete`; AST
  parsing, the focused analyzer contract, and all `66/66` Thor host contracts
  pass. No APK/core build, ADB, launch, install, or device query occurred.
  Exact installed `5044976A...D83E5C` remains frozen, and no speed, FPS,
  gameplay, flicker, stability, or thermal-win credit is granted before the
  independently cool `7/7` title proof.
- Exact installed candidate `5044976A...D83E5C` attempted one independently
  cool title proof in `20260723-023526-thor-input-custom`. Exact APK identity
  and debug boot passed after preflight `32.5 -> 32.1 -> 32.1 C`. The guest
  reused all required `7/7` SPU native objects, but the old startup profile
  also attempted `41/256` RSX pipelines within `500 ms` and built 10 more SPU
  programs under `100 ms`. Silicon rose to `52.6 C`, confirmed at `63.0 C`
  0.6 seconds later, and the early thermal guard force-stopped before title;
  post-stop was `44.9 C` and PID was absent. There was no retry or later device
  contact. Classify `thermal-stop-before-title` / `safe-counterproof` /
  `not-comparable`; grant no speed, FPS, gameplay, flicker, stability, or
  thermal-win credit.

- Host-only cooler successor makes every valid title attempt a cache/install/
  title cooldown source, so the failed capture above enforces a new 30-minute
  device-free interval. It reduces the next title-only startup envelope to 64
  RSX pipelines / `200 ms` and 17 SPU programs / `25 ms`, preserving two
  efficiency-core workers, Vulkan hit-only preload, exact `7/7` native-object
  reuse, and the existing hard thermal gates. Future failure cleanup adds one
  batched 21-property reset readback. No APK/core build, install, launch, ADB,
  or device query accompanied these host changes; the exact installed candidate
  remains frozen pending a later independently cool proof.

- The title analyzer now validates the failure path's batched 21-property
  reset readback independently from normal successful cleanup. It reports
  `failure_cleanup_ready` only when failure PID is absent and every transient
  property is at its safe value while preserving the primary thermal/fatal/
  preflight classification. The prior `20260723-023526...` capture predates
  readback and therefore reports all 21 facts missing, not a false cleanup
  pass. Synthetic complete/leaked-reset cases and all `66/66` host contracts
  pass. No APK/core build or device contact occurred; installed
  `5044976A...D83E5C` remains frozen until the title-sourced cooldown opens at
  `2026-07-23T03:05:48.9964640-04:00`.

- Cooldown completion for title captures now comes from the newest timestamp
  recorded in ADB evidence/thermal logs, not the mutable directory mtime.
  Writing `cool-title-analysis.json` had falsely moved readiness to `03:25:27`
  despite `device_contact=False`; the repaired parser restores the real
  completion/readiness to `02:35:48.915` / `03:05:48.915`, ignores later host
  analysis files, and fails closed when recorded evidence is absent. Synthetic
  and real-capture checks plus all `66/66` host contracts pass. No device
  command ran and the original safety interval remains intact.

- The one allowed cooler-title action after that interval produced capture
  `20260723-030615-thor-input-custom` but did not launch: first preflight was
  `35.5 C` against the strict below-`35 C` ceiling. PID was absent, all 21
  failure-reset properties matched safe values, maximum silicon stayed
  `35.5 C`, and no retry ran. Its pulled `failure-RPCSX.log` was byte-identical
  to the prior launched capture, proving it stale. The collector now omits
  guest logs when no debug-boot request was issued, and the analyzer trusts
  guest activation/fatal/native-object evidence only after an accepted
  handshake. Reanalysis is `preflight-refused-hot`,
  `guest_log_trusted=False`, and `0/7` objects; all `66/66` host contracts
  pass. No speed or correctness credit exists. Do not contact Thor before
  `2026-07-23T03:36:27.5707936-04:00`.

- Pre-boot refusal cleanup is now minimal: after the already-recorded
  post-stop thermal sample it performs one PID query and the batched 21-property
  reset proof, instead of the full activity/window/memory/frequency/cache
  snapshot that occupied the remainder of the `16.7 s` no-launch command.
  Actual booted failures still collect the full postmortem. All `66/66` host
  contracts pass; no device remeasurement occurred. A fresh official upstream
  audit found July 21 LLVM known-bit/constant-analysis patches, but warm PPU
  object reuse bypasses them, while the vendored core already has the relevant
  July 1 PPU worker/concurrency and ARM64 SPU compare work. Nothing unrelated
  was imported.

- The one guarded cooler-profile runtime attempt is
  `20260723-033645-thor-input-custom`. Exact APK and power state matched;
  preflight was `32.1 -> 32.3 -> 31.9 C`; RSX attempted `18/64`; PPU warm
  reuse began about `348 ms` earlier and the SPU phase finished about `444 ms`
  earlier than the prior `256/64` attempt. It still stopped before title at
  `61.8 C` confirmation, post-stop was `46.2 C`, PID was absent, all `21/21`
  failure resets matched, and no fatal hit exists. The `25 ms` SPU budget
  loaded only `6/7` durable native objects, so comparison correctly failed.
  The host successor retains the 17-program prefix and raises only that budget
  to `50 ms`, the midpoint below the old `100 ms` envelope. Grant no speed,
  FPS, thermal-win, gameplay, flicker, or stability credit. Do not contact Thor
  before `2026-07-23T04:07:07.7409903-04:00`; then allow at most one guarded
  `7/7` title proof in a later independently cool round.

- The next single guarded `17 SPU / 50 ms` action produced
  `20260723-040730-thor-input-custom` and refused before boot: preflight was
  `34.5 -> 34.5 -> 35.1 C`, so sample three crossed the strict below-`35 C`
  ceiling. No debug-boot request, guest log, screenshot, game frame, or retry
  occurred; PID was absent and all `21/21` failure resets matched. Classify
  `preflight-refused-hot` / `not-comparable`; grant no speed, FPS, gameplay,
  flicker, stability, or thermal-win credit. Its recorded cooldown forbids
  device contact before `2026-07-23T04:37:45.1904512-04:00`.

- Host-only successor `81BAF133...D54BC2` temporarily applies the existing
  BLUS30161 `0x7` startup affinity only while a fully warm PPU cache is linked,
  then restores the caller's exact mask. Cold compilation, runtime PPU
  execution, desktop, and other titles are unchanged. ARM64 native and
  optimized `thortest` builds pass; merged core
  `5E90A68D...51EBE6BC` / `1,304,260,536` bytes and packaged core
  `5A1C89DF...D793D53A` / `62,985,608` bytes match the APK exactly, artifact
  gates pass, and all `66/66` Thor host contracts pass. This candidate is not
  installed or launched. Installed `5044976A...D83E5C` remains frozen, and
  the successor earns no performance or correctness credit until a separate
  independently cool no-launch install and later title/field/menu/battle proof.

- Supersede that uninstalled host candidate. Audit showed LLVM's actual
  `finalizeObject()` occurs in `jit->fin()` after the original temporary
  affinity scope. Corrected APK `351C6748...A1181E` covers warm object
  admission and finalization, explicitly restores the prior mask before symbol
  resolution, and retains destructor restoration on every early return.
  Optimized ARM64 build, exact APK/core gates, the ordering contract, and all
  `66/66` Thor host contracts pass. Merged core
  `5319D739...AA0CE0B6` / `1,304,271,400` bytes and packaged core
  `C550C011...84DB09AA` / `62,985,816` bytes match the APK exactly.

- Exact candidate `351C6748...A1181E` is now installed after one no-launch
  round. Strict gate `20260723-043753-thor-input-strict-cool-gate` passed
  `32.3 -> 31.9 -> 31.7 C`; install capture
  `20260723-043805-ppu-warm-finalize-affinity-thortest-apk-install` proves
  host/on-device hashes match, PID was absent before/after, no activity
  launched, transient controls were safe, and post-install silicon was
  `33.7 C`. Host-only cooldown status now treats any structurally valid prior
  exact-hash title route as thermal evidence without mistaking it for the new
  candidate; the newer install is authoritative and forbids device contact
  before `2026-07-23T05:08:12.6406001-04:00`. Installation grants no speed,
  FPS, thermal-runtime, flicker, gameplay, or stability credit.

- Host-only title analysis now deduplicates timestamped warm-affinity markers,
  selects the largest-object PPU event, and reports its start-to-next-module
  interval. Comparison-ready requires at least two ordered events and a
  positive interval, so log truncation cannot erase the optimization
  measurement. Synthetic `41 -> 1` events prove an exact `306 ms` interval and
  all `66/66` Thor contracts pass. No device contact or APK change occurred.
- Exact installed candidate `351C6748...A1181E` produced decisive counterproof
  `20260723-050847-thor-input-custom`: strict preflight passed
  `32.3 -> 32.1 -> 32.1 C`, debug boot and `8/7` native-object reuse passed,
  but the route never reached title and the hard guard stopped at confirmed
  `70.3 C`. PID was absent after stop and all `21/21` transient properties
  were safe. Its fully warm PPU `41 -> 1` interval was `1946.229 ms` versus
  `364.325/363.002 ms` in the two matched older captures, about `5.36x`
  slower. Do not grant speed, FPS, gameplay, flicker, stability, or thermal
  credit.

- Host successor restores the caller affinity before `jit->fin()`, symbol
  resolution, and runtime work while retaining the existing temporary `0x7`
  gate for BLUS30161 warm-object admission and destructor cleanup for early
  exits. Optimized ARM64-only `assembleThortest` passes. Exact successor is
  APK `3DFB5F55...A34A78` / `72,835,176` bytes, merged core
  `A21A5095...FC1DBA` / `1,304,269,848` bytes, and packaged core
  `05085F21...22F909` / `62,985,688` bytes. Exact artifact gates and all
  `66/66` Thor host contracts pass; it is not installed. New
  `ThorCoolGameplay` field/menu/battle routes inherit the strict thermal gate,
  always verify force-stop after a macro, and become cooldown sources. Install
  only in a later separate cool no-launch round; title must pass in another
  cool round before any gameplay route.
