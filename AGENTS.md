# RPCSX Thor Agent Notes

This file is the compact operating contract. It is not an experiment ledger.
Put dated run details in `debug-experiments/`, not here.

`CLAUDE.md` holds the AArch64 hardware knowledge: what the 8 Gen 2 exposes, what
the JIT advertises, which features map to which lowering, how to verify a codegen
change at three levels, and the traps that have already cost time. Read it before
proposing a codegen optimization.

The detail behind it is split by topic, because a single file had grown past
1,600 lines and it is loaded every session:

- `docs/arm64/codegen.md` — the lowerings chosen here and the x86-habit audit
- `docs/arm64/microarchitecture.md` — latency, throughput and pipe data from the guides
- `docs/arm64/memory-model.md` — atomics, ordering, i-cache maintenance
- `docs/arm64/spin.md` — where the CPU time goes, and the one untested lever
- `docs/arm64/instruments.md` — what each measuring tool can and cannot answer
- `docs/arm64/thermal.md` — sensors and the thermal guard
- `docs/arm64/transformers-30fps.md` — where the 18.7 FPS goes, and what 30 FPS would really cost
- `docs/arm64/gpu-drivers.md` — driver swaps measured; why a GPU driver cannot help a CPU-bound scene
- `docs/arm64/spurs-halt.md` — WHICH check the SPURS kernel refuses, and why every timing injection missed it
- `docs/arm64/ledger.md` — the audit ledger and open opportunities
- `docs/hardware/` — Arm's vendored per-core optimization guides

Keep `CLAUDE.md` as the map. New detail belongs in the topic file, not in it.

## Communication

- Be concise, factual, and specific.
- State what changed, what was verified, and what remains.
- Do not use hype, filler, or long historical summaries.

## Git

- Work on `master` only for this repo.
- Remote push target: `git@github.com:noeldvictor/rpcsx-ui-android-thor.git`.
- Never use GitHub CLI (`gh`) for this repo; use plain Git over SSH.
- Commit and push completed work to `origin master`.
- Do not create feature branches, PR branches, or extra RPCSX forks unless the user explicitly asks.
- Do not commit game data, firmware, generated builds, Gradle caches, `.cxx`, runtime caches, APKs, or capture blobs.

## Source Layout

- Vendored RPCSX core: `app/src/main/cpp/rpcsx`.
- Android JNI full-core bridge: `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`.
- Lightweight loader wrapper: `app/src/main/cpp/native-lib.cpp`.
- Upstream RPCS3 comparison checkout: `C:\Users\leanerdesigner\Documents\ps3-thor\rpcs3-upstream`.
- Refresh vendored core with `tools/sync_rpcsx_core.ps1`.
- Hydrate core deps with `tools/hydrate_rpcsx_core_deps.ps1`.
- Normal debug build: `.\gradlew.bat :app:assembleDebug`.
- Fast native-core hot swap: `.\tools\build_push_thor_core.ps1 -Label NAME`.
- Reset hot swap: `.\tools\build_push_thor_core.ps1 -ResetToBundled`.

## Upstream Sources

**This repository is the PS3 project. All PS3 work goes here.** Its remote is
`git@github.com:noeldvictor/rpcsx-ui-android-thor.git`, branch `master`. No other
checkout in the parent workspace has a remote that you own.

Three upstream projects feed this one repository. Each one arrives a different
way:

| upstream | what it gives | how it arrives |
| --- | --- | --- |
| `RPCSX/rpcsx` | the vendored core in `app/src/main/cpp/rpcsx` | `tools/sync_rpcsx_core.ps1`. Plain files, not a submodule. Read `UPSTREAM.md` in that directory. |
| `RPCS3/rpcs3` | emulator core and RSX changes | by hand, one commit at a time. This fork takes rpcs3 changes directly, and it is ahead of RPCSX on them. |
| `ARMSX2/ARMSX3` | Android and AArch64 changes | by hand, one commit at a time, after you check each one against this tree. |

**Never merge an upstream branch into this repository.** The three trees have
different layouts and different histories. Content comes in as separate ports.

**Check every ARMSX3 commit against this tree before you port it.** Their device
is not always this device. Their `busy_wait` scaling dropped the Thor to about
1 FPS, because this fork had already retuned each call site for the real
19.2 MHz timer. Their RSX semaphore fallback targets Oryon, not the 8 Gen 2.
Their log-flood list held none of this tree's four largest floods. Record each
pass in `docs/arm64/armsx3-comparison.md`. Say what you rejected, and say why.

### The comparison checkout is not a build target

`C:\Users\leanerdesigner\Documents\ps3-thor\rpcs3-upstream` exists only to read
upstream work. It carries two remotes:

- `origin` is `RPCS3/rpcs3`.
- `armsx3` is `ARMSX2/ARMSX3`.

Obey these rules for it:

- Fetch it to see new upstream commits. This is its whole purpose.
- **Never push it.** You own neither remote. No fork of either one exists under
  `noeldvictor`.
- **Never build it, and never install it on the Thor.** Its `android/` directory
  builds the ARMSX3 app. That app is a different package from `net.rpcsx.easy`.
- A merge inside it gives you nothing that ships. Only a port into this
  repository reaches the device.

## PS3 Sprint Gate

- Active goal: make Eternal Sonata `BLUS30161` stable and faster on AYN Thor while preserving correct field, title Options/menu, first-battle visuals, and bounded thermals.
- The clean-current-upstream Windows 200% gate is cleared. Thor work is permitted only as one short, temperature-guarded validation per cool round; do not heat-soak or immediately repeat a route.
- Keep RPCS3 gameplay on screen 1 with `-WindowsGameScreen 1`.
- Use repo-local skills only: `codex-goal-loop`, `ps3-debug-knowledge`, `ps3-speed-proof-gate`, `ps3-rsx-experiment-gate`, `ps3-continual-harness-refiner`, `ps3-spu-contract-compiler`, and `thor-measurement-validity`.
- `thor-measurement-validity` gates any number taken off the device. Read it before you quote cores, FPS, power, or a crash rate from Thor, and before you read a `simpleperf` capture.
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

## Fork And Pull Request Watch

Watch the RPCS3 forks and the RPCS3 pull requests. Another tree often fixes an
Android fault or an ARM64 fault before we meet it. Run the survey at the start
of a sprint round, and not more than one time a week. The survey is host work.
It does not touch Thor.

- The ledger is `docs/fork-watch.md`. It holds the watch list, the API
  commands, and every survey result.
- The first tree on the list is `https://github.com/sashkinbro/EmuCoreC`. It is
  an active RPCS3 fork for Android with Adreno fixes and ARM64 compile fixes.
- Every tree on the list is GPL-2.0. A port is legal. Put the origin commit
  hash in the port commit message.
- Verify a claim against the source. Do not trust a commit title. Diff the
  added lines against the vendored core in `app/src/main/cpp/rpcsx/`.
- Check the file path before you call a file absent. The vendored core uses
  the old layout `rpcs3/util/JIT*`. Current upstream uses `Utilities/JIT*`.
- Record a survey that finds nothing. Write the date and the empty result.
- A port needs the same proof as any other change. See `Speed Claim Rules`.

### Last survey: 2026-08-22, ARMSX3 seventh pass

ARMSX3 is at `daed55c42`, release 0.9.4.2, which is 38 commits past the sixth
pass. Upstream RPCS3 is at `3aac7d776`. **Six changes are ported and none is
measured on the device.** The full account is in `CLAUDE.md`, section "ARMSX3
seventh pass".

- The largest item is ours, not theirs. The redundant vertex program check in
  `nv4097.cpp` compared two different word orders, so it never fired and each
  transform program upload marked the ucode dirty. That is a per-draw cost on the
  RSX thread. Fixed with `std::rotl<u64>(..., 32)`, from ARMSX3 `e13fc184f`.
  Upstream RPCS3 still carries the defect.
- Also ported: DP3 precision and flat shading from RPCS3, and the savestate resume
  guard and the NP Ethernet address from ARMSX3.
- The LSFG frame generation port is deferred. It is 35 new files, it is two days
  old, and it is written against their VK backend, which has diverged from ours.
- **Upstream did NOT fix Eternal Sonata.** The August fix repairs an upstream
  regression that this tree predates. Three Eternal Sonata issues stay open there.
  See the CORRECTION section in `CLAUDE.md`.

## ARM64 Upstream Perf Uplift

Tracks the upstream RPCS3 ARM64 CPU-emulation series against the vendored core.
Port status is verified by diffing added lines against
`rpcs3-upstream`, not by reading commit titles.

Primary source: Whatcookie (Malcolm Jestadt, author of the commits below),
"PS3 emulation is fast on ARM now", 2026-08-04,
`https://www.youtube.com/watch?v=-aI_XEwmKFk`. He reports 60% faster at 25%
less power across six months. Local transcript procedure: `yt-dlp` audio pull
plus `faster-whisper`. His per-change numbers are on his own ARM device
(Odin 2 class, Linux), not on Thor, so treat them as ordering hints, not
Thor predictions.

- DO NOT apply upstream's `busy_wait` timer scaling to this fork. Tried and
  reverted 2026-08-05 after it dropped Thor to about 1 FPS.
  - Upstream scales by `(cycles / 100) * arm_timer_scale` because its call
    sites pass x86-derived counts tuned for a ~3GHz timer, while ARM generic
    timers are far slower. Whatcookie reports +25% perf / -10% power for it.
  - It does not transfer here, because this fork already fixed the same problem
    the other way. Every hot spin site was hand-retuned against Thor's real
    19.2MHz timer: `busy_wait(100)`, and `profiled_busy_wait(..., 200/300/500)`
    across `vm.cpp`, `SPUThread.cpp`, `CPUThread.cpp`, `mutex.cpp`, `sema.cpp`
    and `RSXFIFO.cpp`. Those arguments are already generic-timer ticks.
  - `arm_timer_scale` resolves to 1 on Thor, since `19200000 / 30000000`
    truncates to 0 and falls back. So the scale is purely the `/100`, which
    divides already-correct values a second time and collapses a 5-26us backoff
    to 50-260ns on every contended reservation, channel and mutex. The result
    is a lock convoy, not a speedup.
  - `rx::get_tsc()` reads `cntvct_el0` directly, so the timer source is not the
    variable here. The call-site calibration is.
  - `init_arm_timer_scale()` is retained and called from `_rpcsx_initialize`
    for diagnostics only. Nothing reads `arm_timer_scale`.
  - General rule this establishes: before porting an upstream ARM tuning fix,
    check whether this fork already compensated at the call sites. Two fixes
    for one problem multiply.
- `pause()` remains `yield`, not upstream's `isb`. `isb` is probably the more
  correct throttle, but it changes the cost of every spin iteration and the
  spin counts above were tuned with `yield` in place. Reintroduce it alone,
  with a measured run, never bundled with other changes.
- The `RPCSX_THOR_BUSY_WAIT_EXPERIMENT` pause-batching path is unchanged.

- Already landed in the vendored core, do not re-port:
  - `4542020c8` SPU LLVM ARM64 `UDOT` for `SUMB`. The vendored core is ahead of
    upstream here: it has a runtime `arm64_spu_feature_mode` gate
    (`utils::use_spu_dotprod()`, `utils::has_i8mm()`) that upstream lacks.
    Keep the gate; do not replace it with upstream's unconditional
    `utils::has_dotprod()` check.
  - `7e436f9bf` SPU LLVM ARM multiply optimization.
  - `61a260482` inlined SPU decrementer via `readcyclecounter`.
- Ported 2026-08-05, `dff29a786` + `a87d17529` as one unit:
  - `tbl2`/`tbx2` helpers and the `m_use_tbl2` gate in `Emu/CPU/CPUTranslator.h`.
    With the gate cleared they lower to `TBL1`/`TBX1` pairs, so correctness does
    not depend on the register pair being available.
  - SPU `SHUFB` two-source case and PPU `VPERM` now emit native table lookups
    instead of the emulated x86 `PSHUFB` sequence.
  - Recoverable JIT: `thread_ctrl::silent_exit`, `jit_compiler::try_add` /
    `try_fin`, and `run_recoverable_llvm` in `util/JITLLVM.cpp` run codegen on a
    disposable thread so an LLVM fatal error kills only that thread.
  - `compile_spu_llvm_with_retry` in `SPUCommonRecompiler.cpp` retries a block
    without `TBL2`/`TBX2` when the error text contains
    `Cannot scavenge register without an emergency spill slot`.

- Rules for this area:
  - `TBL2`/`TBX2` must never be emitted on a path that has no retry owner.
    The SPU block compiler has one; the SPU interpreter builder does not, and is
    deliberately left on the plain `m_jit.add`/`m_jit.fin` path.
  - PPU `VPERM` emits `TBL2` with no retry, matching upstream. If PPU LLVM starts
    reporting scavenger failures, gate `m_use_tbl2` off for PPUTranslator rather
    than reverting the SPU work.
  - The retry helper takes a compiler factory. Any new call site must pass a
    factory reproducing that site's own `make_llvm_recompiler` arguments;
    upstream's hardcoded no-arg version would silently drop `magn` and
    `use_native_object_cache`.
  - Do not keep the vendored `TBL2/TBX2 is excluded` comments alive after a port.
    Stale exclusion notes caused this gap to be re-diagnosed from scratch.

- The ranked backlog from the talk is now closed. Re-audited 2026-08-05 by
  diffing the vendored files against `origin/master` blobs, not commit titles.
  All four items are present in the vendored core:
  1. SPU cache lookup checksum/compare: present, and ahead of the plain
     upstream commit. The vendored path has both the unrolled
     `checksum_parts` form and the rolled `acc_phi` loop, matching upstream
     `origin/master` rather than `35f65c224` alone.
     **Corrected 2026-08-10:** the pair lanes used `aarch64_neon_uabd`, and
     `|a - b|` is not injective, so blocks differing by a uniform delta across
     a pair checksummed identically and the verifier could select the wrong
     cached block. They now sum. Upstream RPCS3 master still has the `UABD`
     form; the fix is ARMSX3's. This item had been audited twice as "present
     and ahead" because both audits compared *against upstream* and asked
     whether the code matched, never whether the operation was right.
     See `docs/arm64/armsx3-comparison.md`.
     **Confirmed on device 2026-08-10.** Cleared `spu-native-v2` for BLUS30161,
     cold boot, re-disassembled: `uaba` `4,503 -> 0` and `uabd` `910 -> 0` out of
     `509,424` instructions, with `add` up `9,587`. The title boots, renders and
     holds 30 FPS at `3.25-3.32` cores with zero verification, fatal or
     cache-rejection rows. No speed claim; the two extra ALU ops per block were
     not isolated and `copy_data_swap_u32_neon` remains unmeasured.
     `debug.rpcsx.thor.spu_native_object_cache=1` must be set before the boot you
     intend to pull, and the cache tree needs `run-as net.rpcsx.easy` to clear.
     **Corrected again 2026-08-21, and closed.** The 2026-08-10 fix moved the
     blind spot, it did not remove it. A sum folds a pair of source words into
     one accumulator lane exactly as an absolute difference does; it is simply
     blind to a different change. `|a - b|` misses `(a + d, b + d)`, and `a + b`
     misses `(a + d, b - d)` and misses the two words swapping. Upstream reached
     the same conclusion for its own `UABD` form in RPCS3 pull request `19230`,
     which found it through missed triggers in LEGO Dimensions on Apple silicon.
     The ARM specialization is now deleted here. ARM64 runs the generic 512-bit
     checksum, which gives every word its own lane and folds nothing inside a
     block. The generic body came from upstream `origin/master`, so the rolled
     `checksum_loop` came with it. The cost is more accumulate work per byte and
     it is not measured. Nothing has booted with this change.
     See `CLAUDE.md`, section "Open pull requests and Whatcookie, sixth pass".
     Full account in `docs/arm64/jit-emitted-code.md`.
  2. `FCGT` inline-asm `bsl` selection: present and byte-identical to upstream
     inside `#if defined(ARCH_ARM64)`. The surrounding function still uses this
     fork's older `register_intrinsic` / `std::bitset` shape; that difference is
     structural, not an ARM gap.
  3. `FSM`/`FSMH`/`FSMB`/`FSMBI` idiomatic masks and the `USHL` path in
     `inf_shl`/`inf_lshr`: present. `ROTQBY` TBL helpers
     (`rotqby_reverse_base`, `pshufb_for_x86_and_tbl_for_aarch64`) are present
     at every upstream call site.
  4. SPU multiply widening: all six non-SVE `smull`/`umull` sites present. The
     only upstream sites missing are the SVE-only `sve_smullt`/`sve_umullt`
     top-half variants, which are out of scope below.
  - Out of scope for Thor: SVE. `4a92d96cf` (SVE2 FMS) and `6349ea2ee` (SVE
    multiply) are the only upstream ARM64 commits genuinely absent here, at
    `5/43` and `23/82` added lines. Both are unusable: Thor's `/proc/cpuinfo`
    Features line reports `asimddp bf16 i8mm sha3` and no `sve` or `sve2`, so
    the 8 Gen 2 exposes no SVE to userspace regardless of core generation.
    Verified on device 2026-08-05. Do not port these.
  - Measured on Thor silicon with `tools/bcax_bench.c`, best of five per core:
    on a dependency chain, which is what the real code is, `BCAX` is `1.96x` on
    the X3, `2.01x` on the A715 and `2.00x` on the A510 for the `SHUFB`
    selector, and `1.94x`/`2.00x`/`2.00x` for `EQV`. On four independent chains
    it is `0.94x` on the X3, `1.00x` on the A715 and `2.02x` on the A510, so it
    is not a free win when wide vector pipes can issue the old pair in
    parallel. This measures the sequence, not a frame.
  - Proven on device 2026-08-06, capture `20260806-025058-thor-input-custom`:
    a real BLUS30161 SPU block compiled as
    `movi v17.16b, #0xf` / `bcax v11.16b, v17.16b, v11.16b, v16.16b` /
    `tbx v4.16b, { v9.16b, v10.16b }, v11.16b`, against a pre-change object that
    spends `movi`/`eor`/`movi`/`and` on the same selector and then a
    single-source `tbx`. When auditing this, count two-source `tbx` as well as
    two-source `tbl`; this path emits `TBX2`, and a `tbl`-only sweep reads as a
    false negative.
  - Landed 2026-08-05, `8b45c9fe7`: SHA-3 `BCAX` for `EQV` and both `SHUFB`
    selector paths, past what upstream emits. `bcax()`/`eor3()` live in
    `CPUTranslator.h` behind `m_use_sha3` (`utils::has_sha3()`), and fall back
    to the arithmetic form so callers never branch. The JIT already advertises
    `+sha3`, and bundled LLVM 20.1.3 has `SHA3_pattern` for `bcaxu`/`eor3u` on
    `v2i64`, so selection is safe. Built for `arm64-v8a`; not device-measured.
    `eor3()` currently has no call site; keep it only while a use is pending.

- Audit method, learned the hard way: `rpcs3-upstream` is a SHALLOW checkout
  (`is-shallow-repository` true, 610 commits) and carries local Eternal Sonata
  commits on top. `git log --grep`, `git log -S`, and per-file history are all
  unreliable there. An early `--grep=arm` sweep missed the `busy_wait` change
  entirely and turned up nothing for `arm_timer_scale`. Audit ARM64 coverage by
  diffing added lines of a known commit against the vendored file, or by
  comparing `ARCH_ARM64` blocks directly. Do not trust commit archaeology.

- Measurement rule for this series: it changes SPU/PPU permute codegen only.
  Expect instruction-count reduction on shuffle-heavy SPU blocks, not a frame
  rate target. A run that thermal-stops before the title renders produces no
  speed credit for it, per `Speed Claim Rules`.

## HLE cellSpurs: what was fixed, and the exact next step

**2026-08-25.** The section below said HLE cellSpurs "cannot work". That was
right about the cause and wrong about it being terminal. Four bugs were fixed and
the SPU-side SPURS kernel now RUNS. It still does not render.

### Fixed

| bug | commit |
| --- | --- |
| PPU task attribute API - four UNIMPLEMENTED_FUNC stubs upstream also lacks | `2b463256d` |
| SPU HLE function dispatch - the removed RegisterHleFunction, rebuilt | `8c945f88a` |
| `cellSpursInitializeWithAttribute` returned EINVAL on an empty SPU image | `676c27535` |
| access violation - a FAILURE path running unconditionally in create_event_helper | `10d871538` |

With `hle_libs=libsre.sprx,libspurs_jq.sprx` and `hle_spurs_kernel=1`:

    Thor: HLE SPURS kernel armed on 'CellSpursKernel0'..'CellSpursKernel5'
    SPU[0x0000100] .. SPU[0x5000100]   all six threads exist and execute
    access violations 0, fatals 0, coresBusy 6.92   (was 1.08)

frames = 0. The kernel spins without producing work.

### The exact next step

Two host-entry PPU threads are still no-ops: `_spurs::create_handler` returns
CELL_OK for a thread it never creates, and `_spurs::create_event_helper` only has
its teardown skipped. Both need rebuilding against today's API - the disabled
code uses `non_task()`, which no longer exists on ppu_thread, and the old
`ppu_thread(name, prio, stack)` constructor.

The recipe, assembled from sys_ppu_thread.cpp:501 and PPUFunction.h:269:

    // 1. register the host function at global init
    ppu_function_manager::register_function<decltype(&_spurs::handler_entry),
        &_spurs::handler_entry>(BIND_FUNC(_spurs::handler_entry));

    // 2. get a guest-callable address for it
    const u32 code = g_fxo->get<ppu_function_manager>()
        .func_addr(FIND_FUNC(_spurs::handler_entry));

    // 3. build the thread - entry is a ppu_func_opd_t{addr, rtoc}, rtoc 0 is
    //    fine for an HLE stub
    const vm::addr_t stack{vm::alloc(0x4000, vm::stack, 4096)};
    const u32 tid = idm::import<named_thread<ppu_thread>>([&]() {
        ppu_thread_params p;
        p.stack_addr = stack;
        p.stack_size = 0x4000;
        p.tls_addr   = 0;
        p.entry      = ppu_func_opd_t{code, 0};
        p.arg0       = spurs.addr();
        p.arg1       = 0;
        return stx::make_shared<named_thread<ppu_thread>>(p, name, prio, 0);
    });
    // 4. spurs->ppu0 = tid;  then start it

Do the handler first: it is the only caller of `sys_spu_thread_group_start` for
the SPURS group, and the workload-ready diagnostic added in `ebc121e37` will
name the failing field the moment it runs.

## Why HLE cellSpurs Cannot Work: the dispatch mechanism is gone

**2026-08-25, definitive.** RPCS3 issue 9063 calls HLE cellSpurs "incomplete",
which reads as missing functions. It is not. The SPU-side SPURS kernel is
FULLY WRITTEN - 2114 lines in `ps3fw/cellSpursSpu.cpp` - and completely
unreachable.

Every hook that would let it run is commented out, in our tree AND upstream:

    645:  // spu.RegisterHleFunction(0xA00, spursSysServiceEntry);
    648:  // spu.RegisterHleFunction(0xA00, spursTasksetEntry);
    732:  // spu.RegisterHleFunction(..., spursKernelEntry);
    733:  // spu.RegisterHleFunction(ctxt->exitToKernelAddr, spursKernelWorkloadExit);
    1343: // spu.RegisterHleFunction(CELL_SPURS_TASKSET_PM_ENTRY_ADDR, spursTasksetEntry);

`RegisterHleFunction` does not exist on `spu_thread`. It was the mechanism that
made an SPU call a host C++ function when its PC reached a given local-store
address, and it was removed. Without it `spursKernelDispatchWorkload` reaches:

    case SPURS_IMG_ADDR_TASKSET_PM:
        // spu.RegisterHleFunction(0xA00, spursTasksetEntry);
        break;                       // <- loads NOTHING into LS
    ...
    spu.pc = 0xA00;                  // <- then jumps there anyway

so the SPU executes whatever happens to be at 0xA00. That is exactly the
observed failure: with `hle_libs=libsre.sprx`, BLUS30357 creates its taskset,
`cellSpursSendWorkloadSignal` and `cellSpursWakeUp` both fire, and then it sits
at 13.5% process CPU with 0.0% on every core and zero frames.

**So completing HLE cellSpurs is not a matter of filling in stubs.** The PPU-side
task API stubs were real and are now implemented (`2b463256d`), and they were not
the wall. The wall is that reviving this path requires reimplementing SPU
HLE-function dispatch across the interpreter and both recompilers - hooking guest
PCs to host callbacks - which is an emulator-core feature, not a module fix.

Do not estimate HLE cellSpurs as "a few TODO functions" again.

## Ghidra Is The Instrument For Slowdowns, Not Just Halts

**Promoted 2026-08-24.** Eighteen speed levers measured null on Transformers
before anything disassembled the loop they were all aimed at. Ghidra answered it
in one run. Reach for it EARLY on a slowdown, not after the profiler has been
argued with for a session.

A profiler says WHERE the time goes. It cannot say WHAT the code is doing there,
and on SPU code the difference decides whether a lever can possibly work. The
same 96.84%-of-a-thread hot block reads as "the bottleneck" to a profiler and as
"a backoff while starved" to a disassembler, and those two readings call for
opposite fixes.

### The toolchain, which is already installed

    ghidra        C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC
    SPU module    .../toolchains/GhidraSPU  -> installed as Ghidra/Processors/SPU
    language id   SPU:BE:128:default
    script        tools/ghidra_scripts/DisassembleSpuWindows.java

Ghidra has no SPU processor by default. The `GhidraSPU` module supplies it, and
it is already unpacked into the Ghidra install, so `-processor
"SPU:BE:128:default"` just works.

### Getting the image

The SPURS kernel is `libsre` and its local store is identical on every boot and
on every one of the six SPU threads, so ONE dump serves all of them. Only the PC
differs.

    adb shell setprop debug.rpcsx.thor.spu_ls_dump CellSpursKernel0
    # perf_monitor writes 262144 bytes; no SPU path pays for it
    adb pull .../files/cache/spu_ls_CellSpursKernel0.bin spurs_ls.bin

### The run

Import base-zero, because a local store IS the address space:

    "$GHIDRA/support/analyzeHeadless.bat" <projdir> spurs \
      -import spurs_ls.bin \
      -processor "SPU:BE:128:default" \
      -loader BinaryLoader -loader-baseAddr 0 \
      -scriptPath <repo>/tools/ghidra_scripts \
      -postScript DisassembleSpuWindows.java out.txt 0x120 0xf3c4

Re-use the project for follow-up windows with `-process spurs_ls.bin
-noanalysis`; re-analysing a 256 KB image every time wastes a minute per
question. Windows are centred, so `0x120` gives about 0x90 either side.

### What it bought, worked example

`chunk-0x0f3c4` is 96.84% of `CellSpursKernel0`. Disassembled:

    f3c4:  il   r4,0x0        ; i = 0
    f3c8:  il   r5,0x960      ; limit = 2400
    f3d0:  ai   r4,r4,0x1     ; i++            <- loop head
    f3d4:  rdch r3,ch8        ; ch8 = SPU_RdDec
    f3d8:  ceq  r40,r4,r5     ; i == 2400 ?
    f3dc:  brz  r40,0xf3d0

The exit condition is the COUNTER. The decrementer value is never used - it is
overwritten every iteration. So this is a calibrated delay, roughly 1.5 us on a
3.2 GHz SPU. Here every `rdch ch8` inlines an `mrs cntvct_el0` at 38.49 ns, so
it takes **92.4 us**, about 60x too long.

The caller is what matters, and only a disassembler shows it:

    f3b4:  brsl 0x13c68       ; poll
    f3bc:  brz  r3,0xf238     ; got it -> leave
    f3c4:  <the 2400 delay>   ; else back off
    f3f4:  brnz r41,0xf3a0    ; retry

and inside that poll:

    13db4..13dcc: wrch ch16..ch21   ; MFC_LSA/EAH/EAL/Size/TagID/Cmd
    13dd0:        rdch r2,ch27      ; MFC_RdAtomicStat

which is a **reservation on the SPURS work queue**, then a blocking status read.

So the hot block is a poll-with-backoff on an atomic, not compute. The SPU is
STARVED, not slow. That single reading explains why eighteen levers that all made
WORK cheaper measured null - none of them can help a processor waiting on work
that has not been published.

### The rule this establishes

**Before optimising a hot SPU block, disassemble it and read its CALLER.** A
counted loop whose exit condition is its own counter is a delay. A loop around a
`ch27` read is a wait. Neither is work, and "make it faster" is the wrong verb
for both. Record the channel numbers - `ch8` RdDec, `ch16-21` the MFC command
registers, `ch27` MFC_RdAtomicStat - because the channel is what says which of
the three it is.

## Startup Cache Worker Affinity

- Startup cache compilation is the hottest phase of a Thor boot. Measured pair
  at matched preflight, same build and route, only the mask differing: ordinary
  scheduler reads `71.1 C` at the first runtime sample and the guard stops the
  boot `0.7 s` in; the A510 cluster reads `53.8 C` at the same stage, peaks
  `67.8 C`, and survives `9.5 s`. Captures `20260806-014920` and
  `20260806-021948`.
- `get_cache_worker_affinity_mask` therefore defaults to `0x07`, matching what
  the PPU compile workers already did. An explicitly set property still wins,
  including an explicit `0`, which means ordinary scheduler and is how the A/B
  arm is reproduced.
- `thor_input_macro.ps1` must not write that property unless the caller bound
  `-CacheWorkerAffinityMask`, and its resets must clear it rather than write
  `0`. Writing `0` by default would measure the old behavior while claiming to
  measure the default, and a `0` left behind disables the default for the next
  ordinary app launch. `tools/test_thor_startup_cache_worker_affinity.ps1` pins
  both rules.
- Re-measured 2026-08-06 after the guard artifact was understood, and the
  default stays. From a matched `33.9 C` launch, pinned to the A510s the SPU
  cache build completes all 1179 functions at `0:00:52.3` peaking at `53.0 C`;
  on the ordinary scheduler it reaches `70 C` six seconds in, peaks `71.5 C`,
  and never completes inside the `72 C` bound. Use
  `SPU Runtime: Built %u functions.` as the completion marker.

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

## Thermal Guard Is Not A Steady-State Signal

- Launch produces a thermal transient. Measured 2026-08-06: `56.6 C` at `t=4s`,
  falling to `46.6 C` by `t=10s`, then `47-58 C` sustained across a `111 s` run
  that peaked at `57.8 C`. The runtime guard samples straight into that
  transient and its near-limit probe confirms on an immediate re-read, so it
  force-stopped fifteen consecutive runs at `14-30 s` on a spike the device
  never sustained.
- Before recording a run as thermally limited, check the emulator's own overlay.
  A run reporting `66-71 C` while the overlay reads `Total : 22.7 %` is not
  emulation-bound, and that combination means the guard tripped, not the
  hardware.
- Boot needs about `50 s` of headroom that the guard has never allowed: the SPU
  cache build runs to roughly `module 1179` and emits no per-module log line, so
  guest logging looks dead from `~9 s` while the screen stays black. That is
  normal startup, not a hang.
- To measure anything past boot, drive the `THOR_DEBUG_BOOT` intent directly and
  enforce the `72 C` bound with a short poll, rather than relying on the
  harness's early-stop and near-limit probe.
- The near-limit probe now has to stay hot for
  `-ThermalRuntimeProbeSustainSeconds` (default `6`) instead of confirming on an
  immediate re-read, so a transient logs `confirm-cleared` and the run
  continues. The early stop and the hard limit are unchanged and still fire
  immediately.
- The harness itself heats the device. Identical build, game and settings reach
  `70.7 C` in about ten seconds under `thor_input_macro.ps1` and stay in the
  fifties under a direct boot, because per-sample `adb shell` spawns walk ~50
  `thermal_zone*` entries, the sustain loop polls once a second, and every
  readiness poll takes a 1080p `screencap`. Harness temperatures include the
  observer; sample at 2 s or finer, since a 4 s sweep aliases the launch spike
  entirely.

## Visual Evidence Rules

- Open a capture screenshot before trusting any visual classification. On
  2026-08-06 roughly fifteen runs were misread because the Ayn panel's
  anti-image-retention overlay sat on top of the emulator, so every
  `title_menu_present=False` was the classifier reading a noise field. One
  `Read` of a PNG would have caught it immediately.
- That overlay engages when the display sits static, which a 25 to 30 minute
  cooldown guarantees, and it persists into the next run. Sleep the panel with
  `input keyevent KEYCODE_SLEEP` during the wait and let the harness wake it as
  part of launching. `global burn_in_protection=0` is already set and does not
  prevent it; `ro.settings.burn_in.protection.enable` is read-only.
- FPS is readable directly from those screenshots. The core's own overlay
  renders `FPS` plus PPU/SPU/RSX utilization in the top-left, so a capture is a
  measurement, not just a gate input.
- Screen state dominates the thermal sensors: panel asleep reads `32.3 C`,
  panel awake and idle reads `40.5-41.3 C`, which is already at the `40 C`
  launch limit. Do not attribute that baseline to load or charging without
  checking `mScreenState`.
- Cross-check the guard against utilization before calling a run
  thermally limited. Capture `20260806-091241` tripped the guard while the
  overlay read `Total : 22.7 %`, which is not an emulation-bound run.

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

- Exact repaired successor `3DFB5F55...A34A78` is now installed after one
  no-launch round. Strict gate `20260723-141331-thor-input-strict-cool-gate`
  passed `32.1 -> 31.9 -> 32.3 C` (maximum `32.3 C`, rise `+0.2 C`).
  Install capture
  `20260723-141343-ppu-warm-finalize-restore-thortest-apk-install` proves
  host/on-device hashes match, `adb install -r` succeeded, no activity
  launched, PID was absent before/after, and post-install battery/skin/silicon
  were `23.0/30.0/37.7 C`. This grants identity/safety only, not speed,
  gameplay, flicker, stability, or thermal-runtime credit. Do not contact Thor
  before `2026-07-23T14:43:50.4744930-04:00`; then spend at most one separate
  guarded title proof.

- Host-only route safety now closes the measured confirmation overshoot:
  capture `20260723-050847-thor-input-custom` sampled `63.4 C`, requested a
  confirmation, and reached `70.3 C` during the `0.98 s` telemetry read.
  `ThorCoolTitle` and `ThorCoolGameplay` now use a `64 C` hard ceiling with
  both probe and early-stop at `60 C`; replaying `63.4 C` changes
  `confirm -> stop` and removes the second telemetry sample. The installed APK
  is unchanged and no device contact accompanied this host change. The title
  analyzer and synthetic thermal-stop fixture require the same `4/64 C`
  metadata and classify an immediate `63.4 C` stop correctly.

- The separately cool title attempt
  `20260723-145352-thor-input-custom` passed preflight
  `33.3 -> 33.1 -> 33.9 C`, exact debug boot, and `8/7` SPU native-object
  continuity, but never reached title. The hard guard stopped RPCSX at
  `65.0 C`; post-stop silicon was `48.6 C`, PID was absent, and all failure
  resets passed. Its fully warm PPU `41 -> 1` interval was `1915.119 ms`, only
  `31.110 ms` better than the prior `1946.229 ms` counterproof and still
  `5.27x` the matched `363.6635 ms` baseline. Restoring before `jit->fin()`
  was therefore insufficient: warm-object admission itself must not run on
  the `0x7` efficiency-core mask. Grant no title, FPS, gameplay, flicker,
  stability, speed, or thermal-win credit.

- Host successor removes warm-link affinity entirely: fully warm PPU object
  admission, finalization, symbol resolution, and runtime remain on the
  default scheduler, while actual cold PPU compile workers and bounded RSX/SPU
  preload workers retain their scoped affinity. The analyzer accepts archived
  markers for timing but rejects them as fallback and requires the new
  default-scheduler activation marker. ARM64 native and optimized ThorTest
  builds plus all `66/66` host contracts pass. Exact host-only APK is
  `87761DAD...083CC` / `72,835,124` bytes, merged core
  `4EEE302C...B274C90` / `1,304,256,792` bytes, and packaged core
  `6E7F3251...FAD0E2C` / `62,985,064` bytes. It is not installed or
  launched and has no device performance or thermal credit.

- Strict no-launch install gate
  `20260723-152143-thor-input-strict-cool-gate` refused immediately at
  `48.6 C`, above the `<35 C` silicon threshold. RPCSX was force-stopped,
  post-stop silicon was `46.6 C`, and neither the remaining gate samples nor
  `adb install` ran. Exact successor `87761DAD...083CC` remains host-only;
  installed `3DFB5F55...A34A78` is unchanged. Do not retry this hot round.

- Fresh official RPCS3 tip `7a90d09cf` contributes the July 21 LLVM
  KnownBits repair: one-pass IR now rejects incomplete PHI ancestry, preserves
  directly provable scalar/vector OR/AND mask facts through a corrected
  fallback, and exposes bitcasted `v128` constants. The port covers two
  generic ARM64 shift and nine SPU lowering query sites statically. ARM64
  native and optimized arm64-only ThorTest builds, exact APK/core/ZIP identity,
  export surface, and all `67/67` host contracts pass. Exact host-only APK is
  `490418F9...D95BF63` / `72,838,428` bytes, merged core
  `9049E583...5AB749E` / `1,304,306,328` bytes, and packaged core
  `C0007C41...CDED102` / `62,988,824` bytes. It supersedes uninstalled
  `87761DAD...083CC`; installed `3DFB5F55...A34A78` is unchanged, no device
  contact occurred, and no speed/thermal/flicker/gameplay/stability credit
  exists. Ledger: `debug-experiments/20260723-thor-llvm-known-bits-upstream-slice.md`.

- Exact LLVM KnownBits candidate `490418F9...D95BF63` is now installed after
  one separately cool no-launch round. Strict gate
  `20260723-154824-thor-input-strict-cool-gate` passed
  `33.3 -> 32.9 -> 32.9 C` (maximum `33.3 C`, rise `-0.4 C`); install capture
  `20260723-154836-llvm-known-bits-thortest-apk-install` proves host/on-device
  hashes match, PID was absent before/after, no activity launched, controls
  were safe, and post-install battery/skin/silicon were `24.0/30.0/35.3 C`.
  Installation grants identity/safety only. Do not contact Thor before
  `2026-07-23T16:18:43.5172237-04:00`; then spend at most one separate guarded
  title proof. No speed, thermal-runtime, flicker, gameplay, or stability
  credit exists yet.

- Upstream PPU audit parks `24a157662` current-thread recycling for the
  installed proof lane. The two prerequisite locking/hash commits are already
  present, while recycling affects only cold misses, leaves two active compile
  lanes under Thor's cap, and would repurpose the foreign JNI caller into the
  little-core/low-priority scope; it cannot explain the measured all-hit warm
  link. New host contract keeps two named cold-compile workers and caller
  isolation. Current Android guidance instead favors a later default-off,
  API-29-safe Thermal Headroom probe sampled no more than every 10 seconds,
  followed by measured `1 <-> 2` startup-worker adaptation only if supported.
  No native/APK/device change occurred; installed `490418F9...D95BF63` remains
  stopped and authoritative. Ledger:
  `debug-experiments/20260723-thor-ppu-thread-reuse-thermal-headroom-audit.md`.

- Default-off Thor Thermal Headroom diagnostics are now implemented without a
  scheduling change. The API-29-safe Android path dynamically resolves the
  newer Thermal API, is property/title gated to one `BLUS30161` sample per
  process, and reports status/headroom plus the unchanged PPU worker and
  affinity selection. Diagnostic-on and final default-off ARM64 native builds,
  zero probe defines in the normal compile tree, exact candidate artifact
  identity, and all `69/69` host contracts pass. No APK rebuild, ADB query,
  install, launch, or device measurement occurred; installed
  `490418F9...D95BF63` remains stopped and has no new speed, thermal, flicker,
  gameplay, or stability credit. Ledger:
  `debug-experiments/20260723-thor-ppu-thread-reuse-thermal-headroom-audit.md`.

- Exact installed candidate `490418F9...D95BF63` completed one guarded title
  attempt in `20260723-164343-thor-input-custom`. Preflight passed
  `32.1 -> 33.3 -> 32.9 C`, debug boot was accepted in `753 ms`, and the new
  default-scheduler marker dynamically proves the 41-object warm PPU link now
  takes `371.267 ms` versus the prior installed candidate's `1915.119 ms`
  (`-80.61%`, `5.158x` faster), within `2.09%` of the older default-scheduler
  mean. This banks a PPU startup-stage speed recovery only. The route loaded
  `6/7` required SPU native objects, never reached title, and self-stopped at
  the first readiness poll at `67.0 C` against the `64 C` hard ceiling.
  Post-stop was `47.4 C`, PID was absent, failure resets were safe, and no
  targeted fatal occurred. Classify `thermal-stop-before-title` /
  `not-comparable`; grant no title, FPS, gameplay, flicker, stability, or
  end-to-end speed/thermal credit. Do not contact Thor before
  `2026-07-23T17:14:05.4848450-04:00`. Ledger:
  `debug-experiments/20260723-thor-ppu-warm-link-default-scheduler.md`.
- The next host-only successor bounds cached RSX pipeline compile submissions to
  `50 ms` in `ThorCoolTitle` only. Global defaults, `ThorCoolGameplay`, and
  cleanup remain `0` (unbounded); two RSX workers and the recovered PPU
  default-scheduler path are unchanged. The analyzer now requires exact
  property evidence, compile-budget activation, attempted/deferred fallback,
  and compile affinity, with a synthetic missing-evidence counterproof. All
  `69/69` Thor host contracts pass. No build, install, launch,
  ADB query, device measurement, or new speed/thermal credit occurred. Ledger:
  `debug-experiments/20260723-thor-rsx-compile-budget-successor.md`.
- One guarded `ThorCoolTitle` attempt for the `50 ms` RSX compile-budget
  successor stopped before launch in `20260723-171427-thor-input-custom`:
  strict preflight rose `34.5 -> 35.5 C`, violating the `<35 C` launch rule
  at sample two. Debug boot/game launch/property application never ran; RPCSX
  was stopped, PID was absent, failure cleanup reset all properties, and
  post-stop silicon was `34.9 C`. Classify `preflight-refused-hot` / not
  comparable and grant no new speed, title, thermal, FPS, flicker, gameplay,
  or stability credit; the RSX cap remains unmeasured. `AndroidRouteScene`
  now saves host-only refusal analysis from the exact exception capture before
  rethrowing, and the pinned artifact gate requires the compile-budget markers.
  All `69/69` Thor host contracts pass. No retry or further device contact
  occurred; next independent host-recorded gate is
  `2026-07-23T17:44:38.4571921-04:00`. Ledger:
  `debug-experiments/20260723-thor-rsx-compile-budget-successor.md`.

- SPU native-object continuity is now bound to the exact candidate that seeded
  it. Capture `20260723-020444-firmware-ppu-prewarm` created seven objects
  under APK `5044976A...D83E5C`, so it cannot establish a floor for installed
  `490418F9...D95BF63` or host successor `D6798739...D549F`. Status publishes
  `spu_continuity_apk_sha256`; both the capture's expected/host and installed
  hashes must match the pinned candidate before any title-route serial/ADB
  resolution. Host counterproof now reports continuity `none`, floor `0`, and
  refuses locally. A stable-prefix preload reordering was compiled then
  discarded because it cannot validate the exact final-IR object key. Exact
  host successor is APK `D6798739...D549F` / `72,838,264` bytes, merged core
  `E9DDCDA3...6F215C` / `1,304,307,080` bytes, and packaged core
  `BDBA4361...A39EE` / `62,988,824` bytes. Strict gate
  `20260723-174922-thor-input-strict-cool-gate` passed
  `30.9 -> 30.9 -> 30.5 C`; no-launch install
  `20260723-174947-spu-continuity-exact-apk-install` proves the exact APK is
  now installed, PID stayed absent, no emulator activity launched, and
  post-install silicon was `32.9 C`. Status blocks further contact until
  `2026-07-23T18:19:54.8683910-04:00`; installation grants identity/safety
  only and no performance credit. Ledger:
  `debug-experiments/20260723-thor-spu-continuity-apk-identity-gate.md`.
- Host-only `ThorCoolTitle`/`ThorCoolGameplay` SPU preload now shrinks from the
  17-program safety envelope to the exact candidate-matched stopped-prewarm
  continuity floor after device-free validation. A floor above 17 refuses
  before serial/ADB resolution. The analyzer validates the dynamic property,
  startup, README, and native activation value; a synthetic `1/1` floor is
  comparison-ready only with a one-program preload, and all `69/69` Thor
  contracts pass. Exact installed APK remains `D6798739...D549F` without an
  exact stopped-prewarm seed; no device contact or performance/thermal credit
  accompanied this change. Ledger:
  `debug-experiments/20260723-thor-spu-continuity-apk-identity-gate.md`.
- Host-only RSX startup hardening now keeps two cache-load workers but caps the
  Android `BLUS30161` compile phase to one worker whenever its opt-in budget is
  nonzero (`50 ms` in `ThorCoolTitle`). This bounds the phase to at most one
  in-flight driver compile beyond the deadline and lowers peak compile
  concurrency; zero-budget/default and desktop behavior remain unchanged. The
  exact successor is APK `47EA2152...F2F90E` / `72,838,180` bytes, merged core
  `C560E418...0E1F0A` / `1,304,308,288` bytes, and packaged/APK-entry core
  `F2EB73E4...306898` / `62,988,936` bytes. ARM64 native and APK builds, exact
  marker/identity gates, and all `69/69` Thor host contracts pass. Thor was not
  contacted; the prior installed `D6798739...D549F` remains stopped. Grant no
  new speed, FPS, flicker, gameplay, stability, or thermal credit. Ledger:
  `debug-experiments/20260723-thor-rsx-single-lane-compile-budget.md`.
- Host-only Android frame-wait hardening replaces the exact BLUS30161 main
  PPU's redundant 32-bit waiter counter with an explicit single-waiter boolean.
  Each bounded VBlank-handler wait now emits two ARM64 release byte stores
  instead of two sequentially consistent `LDADDAL` RMW operations; completion
  token acquire loads, handler ordering, the 1 ms bound, continuous rearm, and
  fallback are unchanged. The exact successor is APK
  `A0233800...55045` / `72,838,240` bytes, merged core
  `80838821...E636D` / `1,304,307,480` bytes, and packaged core
  `2EFCB6B3...7C32D` / `62,988,904` bytes. ARM64 native/APK builds, linked
  disassembly, exact artifact gates, and all `69/69` host contracts pass.
  Thor was not contacted. Classify this as host-verified
  `stackable-cpu-pressure`, not a measured speed/thermal result. Ledger:
  `debug-experiments/20260723-thor-frame-wait-single-waiter-registration.md`.
- Host-only Android VBlank completion publication now uses a release atomic
  increment at both queued-handler and fallback sites. Exact ARM64 successor
  emits `LDADDL` instead of `LDADDAL` for the completion token while waiter
  `LDAR`, atomic modification order/release sequences, notification, bounds,
  gates, and fallback remain intact; the unrelated VBlank counter stays
  `LDADDAL`. The exact successor is APK `6ED1D40A...8C8BA1` /
  `72,838,248` bytes, merged core `85463279...53E3B5` /
  `1,304,307,440` bytes, and packaged core `D3ACADBF...81FBC` /
  `62,988,904` bytes. ARM64 native/APK builds, linked disassembly, exact
  artifact gate, and all `69/69` host contracts pass. Thor was not contacted.
  Classify as host-verified `stackable-cpu-pressure`, not measured speed or
  thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-completion-release-publication.md`.
- Host-only Android VBlank completion now wakes the exact single
  title-gated main-PPU waiter with `notify_one`; desktop retains `notify_all`.
  Exact linked ARM64 calls `notify_one` after both release `LDADDL` completion
  increments. This avoids `notify_all`'s full slot scan, 128-handle batch, and
  multi-pass wake machinery while preserving acquire observation, ordering,
  bounds, gates, and fallback. The exact successor is APK
  `85423E61...B26163` / `72,838,248` bytes, merged core
  `269A551B...506628` / `1,304,307,696` bytes, and packaged core
  `A5E8DCFB...F3E18C` / `62,988,904` bytes. ARM64 native/APK builds, linked
  call-target proof, artifact gate, and all `69/69` host contracts pass. Thor
  was not contacted. Classify as host-verified `stackable-cpu-pressure`, not
  measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-single-waiter-notification.md`.
- Host-only Android frame-wait grace handling now loads the static
  0-500 us bound once per needed handler-grace sequence, while preserving zero
  accessor calls when the guest counter already advanced. Saved clean routes
  imply 1,320 redundant calls removed at title, 4,985 in first battle, and
  1,980 in Options. Exact ARM64 `sys_timer_usleep` drops its in-loop accessor
  call, shrinks `0x6f0 -> 0x6ec`, and keeps all ordering, wait, counter,
  continuous-rearm, and fallback gates. The exact successor is APK
  `9DC30B9C...879698E` / `72,838,240` bytes, merged core
  `D0A038D4...C2051C0` / `1,304,307,832` bytes, and packaged core
  `D7B9F75D...85FE02` / `62,988,904` bytes. ARM64 native/APK builds, linked
  call-count proof, artifact gate, and all `69/69` host contracts pass. Thor
  was not contacted. Classify as host-verified `stackable-cpu-pressure`, not
  measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-frame-wait-grace-bound-hoist.md`.
- Host-only Android raw VBlank edge publication now uses a release
  64-bit atomic increment; desktop retains the sequentially consistent form.
  The sole live producer consumes no data through the counter, while all
  frame-wait and PS3 flip readers remain acquire loads. Exact ARM64 changes
  the edge from `LDADDAL` to `LDADDL`; the prior release completion token,
  one-waiter notification, and cached grace bound remain intact. Saved clean
  routes contain 2,703 title, 8,719 first-battle, and 2,704 Options edges. The
  exact successor is APK `64A44CA9...ACCE39` / `72,838,240` bytes, merged core
  `4683AB54...9E7724` / `1,304,307,864` bytes, and packaged core
  `74D21D34...3F55F8C` / `62,988,904` bytes. ARM64 native/APK builds, linked
  producer/reader proof, artifact gate, and all `69/69` host contracts pass.
  Thor was not contacted. Classify as host-verified `stackable-cpu-pressure`,
  not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-edge-release-publication.md`.
- Host-only Android HLE VBlank command-ready publication now uses a
  release store; desktop retains the sequentially consistent store. The PPU
  queue head is already atomically published, consumers exchange/recheck the
  flag or command head, and the producer ignores the old flag value. Exact
  ARM64 changes `SWPAL` to `STLR`, removing one RMW/acquire barrier per active
  HLE VBlank command while preserving queue-before-store-before-wake ordering.
  The prior release edge/token increments, one-waiter wake, and cached grace
  bound remain intact. Exact successor is APK `5C949AB5...B8AE185` /
  `72,838,236` bytes, merged core `7CA9F1D9...41666A8` /
  `1,304,307,992` bytes, and packaged core `FFA11A60...F2DD099` /
  `62,988,904` bytes. ARM64 native/APK builds, linked ordering proof, artifact
  gate, and all `69/69` host contracts pass. Thor was not contacted. Classify
  as host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260723-thor-vblank-command-release-store.md`.
- Host-only Android RSX flip-handler command publication now shares the
  release-store helper used by HLE VBlank commands. Both producer paths queue,
  `STLR` the level-triggered flag, then `notify_one`; desktop retains both
  sequentially consistent stores. Exact ARM64 changes the remaining flip-site
  `SWPAL` at `0x3837398` to `STLR`, removing a second RMW/acquire barrier from
  a per-frame RSX-to-PPU path while preserving the atomic queue-head contract.
  Exact successor is APK `E8B84EAA...D867100` / `72,838,236` bytes, merged
  core `796BBF97...EAD7303` / `1,304,307,912` bytes, and packaged core
  `FB5329EF...0771FFA` / `62,988,904` bytes. ARM64 native/APK builds, linked
  two-store ordering proof, artifact gate, and all `69/69` host contracts pass.
  Thor was not contacted. Classify as host-verified `stackable-cpu-pressure`,
  not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-rsx-flip-command-release-store.md`.
- Host-only Android PPU asynchronous-command queue heads now use release stores
  in both `cmd_push` and `cmd_list`; desktop retains the sequentially consistent
  store. FIFO reservation gives each producer a unique range, relaxed tail
  writes precede the head, and the consumer still acquires with
  `exchange(cmd64{})`. Exact ARM64 changes the common `cmd_list` head at
  `0x3540b4c` from `SWPAL` to `STLR`, removing an RMW/acquire barrier from all
  asynchronous PPU command publications, including RSX VBlank/flip callbacks.
  Exact successor is APK `AB4803B7...E93614F` / `72,838,396` bytes, merged core
  `F128D577...EC5B01` / `1,304,307,280` bytes, and packaged core
  `29C2A237...85E337` / `62,988,904` bytes. ARM64 native/APK builds, focused
  queue-ordering/codegen proof, artifact gate, and all `70/70` host contracts
  pass. Thor was not contacted. Classify as host-verified
  `stackable-cpu-pressure`, not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-ppu-command-head-release-store.md`.
- Host-only Android GCM flip and RSX user-command wake flags now share
  `ppu_thread::notify_cmd_ready()` with the prior VBlank/flip-handler paths.
  All four callers queue first, `STLR` the level-triggered flag, then
  `notify_one`; desktop retains sequentially consistent stores. Exact ARM64
  changes method sites `0x386cf74` and `0x386d100` from `SWPAL` to `STLR`,
  while queue-head `0x3540b4c` and prior VBlank/flip-handler release stores
  remain intact. Exact successor is APK `0CF81511...649763C` / `72,838,380`
  bytes, merged core `3B61B265...C8B2178` / `1,304,308,000` bytes, and
  packaged core `6D6C3C62...F8790E1` / `62,988,904` bytes. ARM64 native/APK
  builds, focused four-producer/desktop-baseline proof, artifact gate, and all
  `70/70` host contracts pass. Thor was not contacted. Classify as host-
  verified `stackable-cpu-pressure`, not measured speed or thermal credit.
  Ledger: `debug-experiments/20260723-thor-rsx-method-command-release-store.md`.
- Host-only Android PPU command notification clearing now uses a release
  store after each wait; desktop retains the sequentially consistent clear.
  The flag carries no payload, every producer publishes the authoritative
  queue head before flag/wake, and `cmd_wait` immediately reacquires that head
  after clearing. Exact ARM64 changes `ppu_thread::cpu_task+0xe0` at
  `0x353cf40` from `SWPAL wzr` to `STLR wzr`; the consuming command-head
  `SWPAL` at `0x353cf64` remains unchanged. Exact successor is APK
  `98D15FF3...0AD315D` / `72,838,304` bytes, merged core
  `5EC8827E...0BD1C80` / `1,304,308,184` bytes, and packaged core
  `286FD0EB...1CCA51D` / `62,988,904` bytes. ARM64 native/APK builds, focused
  race/order/codegen proof, artifact gate, and all `70/70` host contracts pass.
  Thor was not contacted. Classify as host-verified `stackable-cpu-pressure`,
  not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-ppu-command-notify-clear-release-store.md`.
- Superseded host-only experiment: fully relaxed PPU command reservation
  (`LDADD`) preserved counter uniqueness but did not establish the required
  C++ happens-before edge for reuse of raw tail slots. It was never installed
  or run on Thor. Current code instead pairs release completion with
  acquire-only reservation; historical artifact details remain in
  debug-experiments/20260723-thor-ppu-command-relaxed-reservation.md.
- Host-only Android PPU command FIFO completion now uses a release-only
  compare/exchange in `cmd_pop`; generic and desktop `lf_fifo::pop_end`
  behavior is unchanged. Consumed tail clears must release before an empty
  queue resets and permits slot reuse, but completion consumes no producer
  payload and needs no acquire ordering. Exact merged ARM64 changes the
  completion from `LDAR` + `CASAL` to `LDR` + `CASL`; the earlier queue-position
  acquire remains. Exact successor is APK `C48FF787...CF9636B0` /
  `72,838,072` bytes, merged core `8E486141...45BD0807` /
  `1,304,306,800` bytes, and packaged core `0EFE60AF...411CB8B3` /
  `62,989,000` bytes. ARM64 native/APK builds, focused FIFO
  ordering/codegen proof, artifact gate, and all `70/70` host contracts pass.
  Thor was not contacted. Classify as host-verified
  `stackable-cpu-pressure`, not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-ppu-command-release-completion.md`.
- Host-only Android PPU command FIFO consumers now use relaxed
  position reads in `cmd_wait`, `cmd_get`, and `cmd_pop`, plus relaxed tail
  reads after the command-head acquire. Each queue has one owning consumer;
  the control word carries indices only, and the retained `SWPAL` head
  exchange acquires the producer's release-published tail data. Desktop and
  generic `lf_fifo::peek` behavior remain unchanged. Exact merged ARM64 changes
  targeted `LDAR` instructions to `LDR`, retains head `SWPAL` and completion
  `CASL`, and shrinks `ppu_thread::cpu_task` by 8 bytes. Exact successor is APK
  `D5F2E5BB...9ED4ADD0` / `72,838,084` bytes, merged core
  `39F1C9BF...2BE30143` / `1,304,308,552` bytes, and packaged core
  `59F25E23...9EB9853` / `62,989,000` bytes. ARM64 native/APK builds, focused
  single-consumer/payload-ordering/codegen proof, artifact gate, and all
  `70/70` host contracts pass. Thor was not contacted. Classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal credit.
  Ledger:
  `debug-experiments/20260723-thor-ppu-command-relaxed-consumer-reads.md`.
- Host-only Android PPU command queues now use minimal paired handoff
  ordering. Release completion `CASL` pairs with acquire reservation `LDADDA`
  for safe raw-slot reuse; release head publication `STLR` pairs with acquire
  head exchange `SWPA` for payload delivery. This supersedes the never-deployed
  fully relaxed reservation candidate, whose atomic uniqueness lacked the
  required C++ happens-before edge. Desktop/generic behavior is unchanged;
  relaxed position/tail `LDR` reads remain. Exact successor is APK
  `D9CFF3E8...B6FF7DCD` / `72,838,040` bytes, merged core
  `888767BB...46869E9` / `1,304,308,416` bytes, and packaged core
  `BCF54B18...D894E3A9` / `62,989,000` bytes. ARM64 native/APK builds, focused
  two-handoff correctness/codegen proof, artifact gate, and all `70/70` host
  contracts pass. Thor was not contacted. Classify as host-verified stability
  correction plus `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260723-thor-ppu-command-minimal-handoff-ordering.md`.
- Host-only Android PPU command notification now uses minimal ordering. The
  consumer's payload-free post-wait clear is a relaxed atomic `STR`; command
  producers in `sys_ppu_thread_start` and `lv2_int_serv::join` now share the
  existing Android release-store helper, changing both `SWPAL` exchanges to
  `STLR`. The queue head remains authoritative, producer head-before-flag
  ordering and `notify_one` remain, the separate interrupt-disestablish
  `SWPAL` is unchanged, and desktop retains sequentially consistent behavior.
  Exact successor is APK `130CDBBA...B6D6DD8` / `72,837,756` bytes, merged
  core `C354674D...5EC94B66` / `1,304,307,216` bytes, and packaged core
  `18F720A8...E8B3756` / `62,988,856` bytes. ARM64 native/APK builds, exact
  linked `STR/STLR` plus retained `LDADDA/STLR/SWPA/CASL` proof, artifact gate,
  and all `70/70` host contracts pass. Thor was not contacted. Classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal credit.
  Ledger:
  `debug-experiments/20260723-thor-ppu-command-notification-minimal-ordering.md`.
- Host-only Android VBlank waiter registration is now treated as an advisory
  work gate. The two live producer checks use relaxed `LDRB` instead of
  acquire `LDARB`, and the queued completion callback always calls
  `notify_one` after its release token increment rather than reloading the
  flag. A stale false retains the one-millisecond timeout/fallback; a stale
  true can only schedule harmless extra completion/wake work. Handler data
  still uses the release-token/acquire-reader handoff, and desktop is
  unchanged. The callback shrinks `0x68 -> 0x58`; exact successor is APK
  `17C74C6B...9A195FD` / `72,837,732` bytes, merged core
  `69797EA4...075A99E` / `1,304,307,160` bytes, and packaged core
  `49F32203...6F11502` / `62,988,856` bytes. ARM64 native/APK builds, exact
  linked `LDRB`/no-callback-`LDARB` plus retained `LDADDL + notify_one` proof,
  artifact gate, and all `70/70` host contracts pass. Thor was not contacted.
  Classify as host-verified `stackable-cpu-pressure`, not measured speed or
  thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-registration-advisory-loads.md`.
- Host-only Android frame-poll waiter registration now uses relaxed atomic
  byte stores. The flag is only an advisory producer-work hint; handler data
  still uses the release completion-token/acquire-reader handoff, every wait
  remains bounded to one millisecond, and desktop retains release stores.
  Exact ARM64 changes both hot registration `STLRB`s to `STRB`, retains the
  surrounding token `LDAR`s and wait call, and keeps `sys_timer_usleep` at
  `0x6ec`. Saved clean title/battle/Options routes imply `69,084`, `210,290`,
  and `66,968` ordering barriers removed respectively. Exact successor is APK
  `A166ACE9...C682964` / `72,837,756` bytes, merged core
  `95E55A24...D59B103` / `1,304,307,080` bytes, and packaged core
  `969328CD...F6710FD` / `62,988,856` bytes. ARM64 native/APK builds, exact
  linked `STRB/LDAR` proof, artifact gate, and all `70/70` host contracts pass.
  Thor was not contacted. Classify as host-verified `stackable-cpu-pressure`,
  not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-registration-relaxed-stores.md`.
- Host-only Android frame-poll waiter token snapshots now use relaxed loads
  for the two pre-wait control decisions. The wait engine still compares the
  expected token at futex/generic wait entry, every wait remains bounded to one
  millisecond, and the final acquire token load still publishes guest-handler
  writes before the counter read. Desktop retains its prior implicit acquire
  loads. Exact ARM64 changes the two hot pre-wait `LDAR`s to `LDR`, retains the
  post-wait `LDAR`, both registration `STRB`s, the wait call, and
  `sys_timer_usleep` size `0x6ec`. Saved clean title/battle/Options routes imply
  `69,084`, `210,290`, and `66,968` acquire barriers removed respectively.
  Exact successor is APK `71D9C0C2...DD4E977B` / `72,837,748` bytes, merged
  core `562142F3...750C0E0` / `1,304,307,320` bytes, and packaged core
  `EC383041...8897CF` / `62,988,856` bytes. ARM64 native/APK builds, exact
  linked `LDR/LDR/LDAR` proof, artifact gate, and all `70/70` host contracts
  pass. Thor was not contacted. Classify as host-verified
  `stackable-cpu-pressure`, not measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-vblank-prewait-relaxed-loads.md`.
- Host-only Android Eternal Sonata frame-poll `Fast` mode now compiles
  steady-state diagnostics out while `Wait` preserves the full counters and
  logger. Exact ARM64 retains `LDR/LDR`, registration `STRB`s, the bounded 1 ms
  wait, final publication `LDAR`, 100 us grace, completion store, and fallback;
  the Fast span has no diagnostic offsets/increments/logger calls.
  `sys_timer_usleep` shrinks `0x6ec -> 0x5b4`; full diagnostics are outlined as
  `0x3b4`. Saved clean title/battle/Options routes imply a conservative minimum
  of 541,932 load/add/store counter sequences removed. Exact successor is APK
  `528BFEE0...69754222` / `72,838,016` bytes, merged core
  `97A485B5...91C735CB` / `1,304,313,728` bytes, and packaged core
  `ED62C46D...CA7A4A8` / `62,989,896` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `70/70` host contracts pass. Thor was not
  contacted. Classify as host-verified `stackable-cpu-pressure`, not measured
  speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-frame-wait-fast-stats-free.md`.
- Host-only Android frame-poll setting caches now use constant-initialized
  atomic sentinels with direct relaxed hot loads and outlined cold parsing.
  Cheap PPU/CIA/sleep gates precede title/cache work, and fallback reuses one
  mode read. Exact ARM64 removes all three C++ guard variables, at least
  184,419 saved-route `LDARB` guard loads, 184,419 redundant value loads, and
  11,141 continuous/grace helper calls while retaining the bounded wait,
  registration stores, post-wait `LDAR`, grace, completion, and fallback.
  `sys_timer_usleep` shrinks `0x5b4 -> 0x590`. Exact successor is APK
  `9B244D20...4463F53` / `72,837,528` bytes, merged core
  `9658E657...75A3C28` / `1,304,325,056` bytes, and packaged core
  `B7150001...B5BE8F7` / `62,989,080` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `70/70` host contracts pass. Thor was not
  contacted. Classify as host-verified `stackable-cpu-pressure`, not measured
  speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-frame-wait-relaxed-setting-caches.md`.
- Host-only Android Eternal Sonata frame-poll title gating is now immutable
  for each PPU object's lifetime. Both normal and savestate constructors do
  the exact `BLUS30161` string comparison once; the hot timer wrapper and
  fallback each read one byte from the PPU instead of re-reading the emulator
  title string. This cannot leak across games because every emulation creates
  new PPU objects, and an unavailable title fails closed. Exact ARM64 replaces
  both 23-instruction string blocks with three-instruction byte gates, removes
  all title string words from `sys_timer_usleep`, and shrinks it
  `0x590 -> 0x4d4` (188 bytes / 13.2%). Saved clean title/battle/Options routes
  imply at least 3,465,560 linked title-gate instruction executions removed.
  Exact successor is APK `D65C474C...F844C3EA` / `72,837,616` bytes, merged
  core `2A61C4EA...A69E7DDD` / `1,304,324,952` bytes, and packaged core
  `405A08CA...A9CE3646` / `62,989,080` bytes. Native/APK builds, exact
  codegen, artifact identity, and all `70/70` host contracts pass. Thor was
  not contacted. Classify as host-verified `stackable-cpu-pressure`, not
  measured speed or thermal credit. Ledger:
  `debug-experiments/20260723-thor-frame-wait-ppu-title-cache.md`.
- Host-only Android Eternal Sonata frame-poll classification now survives the
  normal timer sleep as a compact four-state result. Only the two genuine
  fallback results enter post-sleep rearm observation; unrelated sleeps no
  longer repeat PPU/CIA/duration/title/mode gates. Post-sleep object/VM,
  counter, renderer, completion, and armed checks remain. Exact ARM64 replaces
  the 19-instruction repeated gate block with one result branch and shrinks
  `sys_timer_usleep` `0x4d4 -> 0x494` (64 bytes / 5.2%). Saved clean
  title/battle/Options routes contain 107 genuine fallback sleeps, implying at
  least 1,926 linked gate instruction executions removed; no unrelated-call
  count is claimed. Exact successor is APK `CD73E1E5...EC5B59F8` /
  `72,837,768` bytes, merged core `58C1A18D...A14906E` /
  `1,304,325,912` bytes, and packaged core `39989CFF...9EF99F0` /
  `62,989,144` bytes. Native/APK builds, exact codegen, artifact identity, and
  all `70/70` host contracts pass. Thor was not contacted. Classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal credit.
  Ledger:
  `debug-experiments/20260723-thor-frame-wait-result-forwarding.md`.
- Host-only Android Eternal Sonata frame-poll main-PPU, title, and immutable
  process-mode classification now collapses into one PPU-lifetime mode byte.
  Only main PPU `0x01000000` for `BLUS30161` starts unresolved; the first exact
  CIA/100 us candidate stores the already immutable process mode, while every
  other PPU/title fails closed as `off`. Exact linked ARM64 reduces a
  steady-state `Fast` call from 21 classification instructions to 13. Saved
  title/battle/Options routes therefore imply 1,386,224 gate instructions
  removed. `sys_timer_usleep` grows `0x494 -> 0x498` solely for the cold store,
  so this is a dynamic hot-path win rather than a static-size win. Exact
  successor is APK `6F57A84A...EC5C15B2` / `72,837,024` bytes, merged core
  `6C9DA0D5...EC5F53F1` / `1,304,324,744` bytes, and packaged core
  `DD392B89...209531B1` / `62,989,160` bytes. Native/APK builds, exact
  predecessor/successor codegen, artifact identity, and all `70/70` host
  contracts pass. Thor was not contacted. Classify as host-verified
  `stackable-cpu-pressure`, not measured speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-frame-wait-ppu-mode-cache.md`.
- Host-only Android Eternal Sonata frame-poll mode encoding now makes `off`
  zero and dispatches `Fast` before unresolved/cold work. A rejected first
  link duplicated the inlined Fast body and grew `sys_timer_usleep` to
  `0x67c`; the retained source shares one Fast block. Exact linked ARM64
  reduces steady exact Fast classification `13 -> 10` instructions, implying
  519,834 fewer gate instructions across saved title/battle/Options routes.
  `sys_timer_usleep` grows only `0x498 -> 0x4a4` for cold defensive dispatch.
  Exact successor is APK `B825212A...10E006` / `72,837,192` bytes, merged core
  `DC6B9D3D...B63A6EB` / `1,304,324,400` bytes, and packaged core
  `29350625...762660` / `62,989,160` bytes. Official upstream master remains
  `7a90d09cf`; its recent ARM64-relevant FMA/reduced-loop work is already
  represented locally. Native/APK builds, exact predecessor/successor
  codegen, artifact identity, and all `70/70` host contracts pass. Thor was
  not contacted. Classify as host-verified `stackable-cpu-pressure`, not
  measured speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-frame-wait-fast-first-mode.md`.
- Host-only Android `sys_timer_usleep` now skips saturating add/sub arithmetic
  when the configured usleep addend is its zero default. Exact linked ARM64
  replaces the 12-instruction default-addend selection with an addend load,
  zero branch, and mode load plus one earlier duration move. After block-layout
  effects, saved exact title/battle/Options frame-poll calls conservatively
  imply 1,212,946 fewer executed instructions; other nonzero guest sleeps are
  additional unclaimed savings. Positive/negative saturation, timer accuracy,
  frame-wait gates, fallback, and logging are unchanged. Exact successor is APK
  `C96CD570...A374DBA` / `72,837,176` bytes, merged core
  `7C40DA22...A817DD` / `1,304,324,368` bytes, and packaged core
  `28DD7506...0530A1` / `62,989,160` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `70/70` host contracts pass. Thor was not
  contacted. Classify as host-verified `stackable-cpu-pressure`, not measured
  speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-usleep-zero-addend-fast-path.md`.
- Host-only normal-Android SPURS wait hooks now use an argument-discard macro
  instead of an empty function, so diagnostic-only atomic expressions are not
  evaluated in `sys_timer_usleep`, `sys_semaphore_wait`, or
  `sys_semaphore_post`. Exact linked ARM64 removes one discarded acquire load
  and 16 bytes from each function; the complete merged core shrinks 1,104
  bytes. Saved clean title/battle/Options routes conservatively imply 994,378
  fewer acquire loads. Diagnostic/desktop builds retain all nine original
  hooks and arguments. Exact successor is APK `896E0F8F...163CDA87` /
  `72,837,436` bytes, merged core `CA4D4B93...236C42F` / `1,304,323,264`
  bytes, and packaged core `0F2EA7B8...0CB2C54DE` / `62,989,112` bytes.
  Native/APK builds, exact codegen, targeted diagnostic-on syntax checks,
  artifact identity, and all `70/70` host contracts pass. Thor was not
  contacted. Classify as host-verified `stackable-cpu-pressure`, not measured
  speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-disabled-spurs-probe-argument-elision.md`.
- Host-only Android `sys_timer_usleep` now reads the independently atomic,
  dynamically configurable usleep addend through relaxed `cfg::_int::observe()`;
  desktop retains its ordered access. Exact linked ARM64 changes only this
  setting load from `LDAR` to `LDR`, keeps later synchronization acquires, and
  shrinks the hot symbol `0x49c -> 0x494`. Saved clean title/battle/Options
  routes conservatively imply 584,319 fewer acquire barriers while preserving
  one live atomic setting read per call. Exact successor is APK
  `1BAA60FB...7857B65FA` / `72,837,424` bytes, merged core
  `22D1DDC6...42C64FB6` / `1,304,324,496` bytes, and packaged core
  `8B9A104B...C7FD0A8` / `62,989,112` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `70/70` host contracts pass. Thor was not
  contacted. Classify as host-verified `stackable-cpu-pressure`, not measured
  speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-usleep-addend-relaxed-load.md`.
- Host-only Android timer/scheduler configuration reads now use relaxed atomic
  observation for independent `sleep_timers_accuracy` and `clocks_scale`
  scalars; desktop retains ordered reads, dynamic accuracy updates remain live,
  and real state/token/queue acquires are unchanged. Exact ARM64 changes four
  targeted `LDAR`s to immediate-offset `LDR`s and shrinks
  `awake_unlocked`/`wait_timeout`/`sys_timer_usleep` by 64 bytes combined.
  Saved title/battle/Options routes prove 411,148 normal timer calls avoid the
  outer accuracy barrier; timeout-loop and scheduler savings are additional
  uncounted credit. Exact successor is APK `BAE484CC...1B92D87DE` /
  `72,837,128` bytes, merged core `AB8AE9A0...10FC48550` /
  `1,304,328,192` bytes, and packaged core `298AC1FD...21D5A1850` /
  `62,989,016` bytes. Native/APK builds, exact codegen, artifact identity, and
  all `71/71` host contracts pass. Thor was not contacted. Classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal credit.
  Ledger: `debug-experiments/20260724-thor-timer-config-relaxed-reads.md`.
- Host-only Android PPU scheduler and VM-lock code now observes the non-dynamic,
  range-bounded PPU-thread count with relaxed atomic loads; desktop retains
  ordered reads and no cross-session cache was introduced. Exact ARM64 changes
  eleven config `LDAR` sites into ten immediate-offset `LDR`s because both
  sequential writer-lock scans now reuse one count. Affected symbols shrink 80
  bytes total while 60 real synchronization acquires remain. Exact successor
  is APK `6F9C32F7...1F293FDB` / `72,837,104` bytes, merged core
  `FBAC81A5...FE790676` / `1,304,328,360` bytes, and packaged core
  `85E7B139...ACFCF2E7` / `62,988,984` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `72/72` host contracts pass. Thor was not
  contacted. No dynamic execution count exists; classify as host-verified
  `stackable-cpu-pressure`, not measured speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-ppu-thread-count-relaxed-reads.md`.
- Host-only Android SPU MFC accurate-DMA decisions now use relaxed reads of
  the independent, non-dynamic config byte; desktop retains ordered reads and
  all DMA, RSX-lock, reservation, fence, and notification ordering is
  unchanged. Exact ARM64 changes five `LDARB` sites into direct-offset `LDRB`
  loads, removes five address-forming instructions, retains all 56 non-target
  acquires, and shrinks the two linked functions eight bytes total. Exact
  successor is APK `87237F66...68DFD4F6` / `72,837,220` bytes, merged core
  `5296091F...BC1FD337` / `1,304,327,520` bytes, and packaged core
  `B651E5C7...D54D4126` / `62,988,888` bytes. Native/APK builds, exact
  codegen, artifact identity, and all `73/73` host contracts pass. Thor was
  not contacted. No exact Android execution count exists; classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260724-thor-spu-accurate-dma-relaxed-reads.md`.
- Host-only Android SPU MFC-debug gates now use relaxed reads of the
  independent, non-dynamic diagnostic byte; desktop retains ordered reads and
  diagnostic history allocation/recording remains intact. Exact ARM64 changes
  fourteen `LDARB` sites into direct-offset `LDRB` loads, removes fourteen
  address-forming instructions, retains all 130 non-target acquires, and
  shrinks the affected symbols and packaged runtime core 64 bytes. Exact
  successor is APK `B1149915...D67908C` / `72,836,792` bytes, merged core
  `7EE8E150...580EBFA` / `1,304,325,664` bytes, and packaged core
  `D01CD6CB...54DD4D8` / `62,988,824` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `74/74` host contracts pass. Thor was not
  contacted. No exact Android execution count exists; classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260724-thor-spu-mfc-debug-relaxed-reads.md`.
- Host-only Android SPU accurate-reservation decisions now use relaxed reads
  of the independent, non-dynamic/default-on selector; desktop retains ordered
  reads and all reservation atomics, locks, comparisons, events, and notifier
  ordering remain. Exact ARM64 changes six `LDARB` sites into direct-offset
  `LDRB` loads, removes six address-forming instructions, retains all 94
  non-target acquires, and shrinks affected symbols 48 bytes. Exact successor
  is APK `62F663A5...25B4B5F4` / `72,836,492` bytes, merged core
  `A5A7509C...52D4BE4C` / `1,304,322,544` bytes, and packaged core
  `439F6176...27D491C` / `62,988,792` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `75/75` host contracts pass. Thor was not
  contacted. No exact Android execution count exists; classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260724-thor-spu-accurate-reservations-relaxed-reads.md`.
- Host-only Android MFC scheduling now uses relaxed reads for four shuffling-
  limit, one timeout, and one in-steps setting observation; desktop retains
  ordered reads and MFC queue/barrier/fence/interrupt/DMA ordering remains.
  The default zero-shuffling path now branches around the previously unused
  timeout atomic load in every `cpu_work()` pass. Exact ARM64 removes six
  acquire loads, retains all 50 non-target acquires, and shrinks the affected
  symbols 20 bytes. Exact successor is APK `093E077A...88396235` /
  `72,836,504` bytes, merged core `B6183DB2...7FF8E016` /
  `1,304,323,752` bytes, and packaged core `7EE500BD...1032CDAE` /
  `62,988,744` bytes. Native/APK builds, exact codegen, artifact identity, and
  all `76/76` host contracts pass. Thor was not contacted. No exact Android
  execution count exists; classify as host-verified `stackable-cpu-pressure`,
  not measured speed or thermal credit. Ledger:
  `debug-experiments/20260724-thor-spu-mfc-scheduler-relaxed-reads.md`.
- Host-only Android SPU RSX reservation-lock selection now uses relaxed reads
  of the non-dynamic/default-off strict-rendering selector and the non-dynamic/
  default-fast FIFO-accuracy selector; desktop retains ordered reads and all
  RSX-lock, accurate-DMA, address-gate, reservation, and transfer ordering
  remains. Exact ARM64 removes four acquire loads, retains all 46 non-target
  acquires, and shrinks `do_list_transfer` 24 bytes while
  `do_dma_transfer` is size-neutral. Exact successor is APK
  `24AB810C...46F0C2C8` / `72,836,464` bytes, merged core
  `D2C52C03...AFA9E8A4` / `1,304,323,496` bytes, and packaged core
  `78F07D31...0FABEE8A` / `62,988,744` bytes. Native/APK builds, exact
  codegen, artifact identity, and all `77/77` host contracts pass. Thor was
  not contacted. No exact Android execution count exists; classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260724-thor-spu-rsx-lock-config-relaxed-reads.md`.
- Host-only Android SPU GETLLAR/event/SPURS wait-policy reads now use relaxed
  observations for spin selection, busy-wait percentages, loop detection,
  the SPURS thread cap, and the GETLLAR RSX-lock selector; desktop retains
  ordered reads and dynamic settings remain live. Exact ARM64 removes seven
  acquire loads, retains all 100 non-target acquires, shrinks four affected
  symbols 88 bytes, and shrinks the packaged runtime core 80 bytes. Exact
  successor is APK `6F1D89FF...1A4224A1` / `72,836,788` bytes, merged core
  `83B3493A...999DBA26` / `1,304,324,344` bytes, and packaged core
  `2BA69B66...457C4AE` / `62,988,664` bytes. Native/APK builds, exact codegen,
  artifact identity, and all `78/78` host contracts pass. Thor was not
  contacted. No exact Android execution count exists; classify as
  host-verified `stackable-cpu-pressure`, not measured speed or thermal
  credit. Ledger:
  `debug-experiments/20260724-thor-spu-wait-policy-relaxed-reads.md`.

## Write documentation in ASD-STE100

Use Simplified Technical English for new documentation and for commit messages.
Write short sentences. Use the active voice. Use one word for one meaning. Keep
noun clusters to three words. The full rules are in `CLAUDE.md`.

Do not rewrite old documents only to change their style. Convert a document when
you change it for another reason.


---

# Part 2: fast AArch64 PS3 emulation on Snapdragon 8 Gen 2

**Merged here on 2026-08-23.** This was `CLAUDE.md`. The two files split the
operating contract from the hardware knowledge, and a reader had to know which
half held the answer. `CLAUDE.md` is now a pointer to this file, so there is one
map and it cannot disagree with itself.

Everything above is the operating contract. Everything below is what this
project measured on the silicon.

# Fast AArch64 PS3 Emulation on Snapdragon 8 Gen 2

Technical notes for making this emulator fast on Thor. `AGENTS.md` is the
operating contract; this file is the hardware knowledge behind it.

## Read `AGENTS.md` first

**This repository is the PS3 project.** It is the one place PS3 work goes, and
its remote is `git@github.com:noeldvictor/rpcsx-ui-android-thor.git`. Work from
`RPCSX/rpcsx`, `RPCS3/rpcs3` and `ARMSX2/ARMSX3` all arrives here, one port at a
time. The sibling checkout `ps3-thor/rpcs3-upstream` is for reading upstream
only: do not push it, do not build it, and do not install it on the Thor.

`AGENTS.md`, section **Upstream Sources**, holds the rules and the reasons. Read
it before you touch an upstream tree. This paragraph is a pointer, not a second
copy, because two copies of a rule disagree.

# Write all documentation in ASD-STE100

Use Simplified Technical English (ASD-STE100) for all new documentation and all
commit messages. Write the rules into new text. Do not rewrite old text only to
change its style.

## The rules that apply here

1. **Write short sentences.** Use a maximum of 25 words in a descriptive
   sentence. Use a maximum of 20 words in an instruction.
2. **Write one instruction in one sentence.** Do not put two commands together.
3. **Use the active voice.** Write "the JIT emits a spin loop". Do not write "a
   spin loop is emitted".
4. **Use one word for one meaning.** If you call it a "park", call it a "park"
   every time. Do not also call it a "sleep", a "wait", or a "block".
5. **Use simple tenses.** Use the present, the past, or the future. Do not use
   the perfect tenses.
6. **Keep noun clusters to three words.** Write "the cache for SPU objects". Do
   not write "the SPU native object cache key".
7. **Write a maximum of six sentences in a paragraph.**
8. **Use articles.** Write "the profile shows". Do not write "profile shows".
9. **Do not use synonyms for effect.** Repeat the noun.

## What does not change

STE controls the language. It does not control the content. These rules stay:

* Give the number, and give the workload with it.
* Say what you measured. Say what you did not measure.
* Record a retraction in the same file as the claim.
* Quote the file and the line.

STE makes these easier, not harder. A short sentence in the active voice cannot
hide a weak claim behind a long clause.

## The tension, stated plainly

Much of the older text in `docs/arm64/` is discursive. It explains why an
inference failed. STE permits this, but STE needs more sentences to do it. Accept
the extra sentences. Do not compress the reasoning to save words.

**Do not convert the old documents in one pass.** A large rewrite of correct text
creates risk and gives no gain. Convert a document when you change it for another
reason.

## Read this first: the lv2 waits spin instead of sleeping, and a profile found it

A symbolized profile of a healthy 60 fps run — 31,657 samples, 0 lost, no pause —
puts **73.9% of cycles inside two lv2 wait syscalls**. Read that number with its
workload attached: it is **Folklore's title screen**, where the emulator is mostly
waiting. Under Eternal Sonata gameplay the same change is worth 4.5%, not 67%. The
spin is pure waste on both — no arm ever lost frame rate — but the size of the
prize tracks how idle the scene is. The two hot functions are
`sys_event_queue_receive` (47.8%) and `_sys_lwcond_queue_wait` (26.1%), as *self*
time that never reaches `atomic_wait_engine::wait`. They are spinning, not
sleeping: `50 × rx::busy_wait(500)`, which on a **19.2 MHz** generic timer is
**1.3 ms** of `YIELD` — a nop on this SMP core. The identical loop is at
**eight sites** across the guest synchronization layer.

**Measured, not just predicted**, with the budget behind
`debug.rpcsx.thor.lv2_spin`:

| workload | default (50) | no spin (0) | saving |
| --- | --- | --- | --- |
| Folklore, title screen | 1.200 cores | 0.390 | **67.6%** (spread 0.005) |
| Eternal Sonata, gameplay | 3.193 | 3.049 | **not established** — see below |

**Eternal Sonata CPU cannot resolve anything below ~1.4 cores.** Two arms running
*identical code* (a failed install, caught by grepping the on-device `.so`)
differed by **1.37 cores, 58%**. Every gameplay CPU delta reported here is an
order of magnitude under that, so the gameplay saving is downgraded to not
established. Folklore resolves 0.005 cores and is the title to A/B on.

Then frame-time percentiles from `dumpsys SurfaceFlinger --latency` on the BLAST
layer — four gameplay arms in both orders, ~750 frame intervals each — put
**p50/p95/p99 within 0.02 ms across every arm**, with CPU lower in every pairing.
No latency cost at any percentile.

**So the default is now `0`.** `debug.rpcsx.thor.lv2_spin=50` restores upstream
behaviour. Full account in
[`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md).

## And where gameplay time actually goes

A second profile — Eternal Sonata gameplay, **119,662 samples, 0 lost, 0 pauses** —
shares almost no hot code with the title screen above:

| | share |
| --- | --- |
| **JIT-generated code (unnamed)** | **47.88%** |
| `librpcsx-android.so` | 34.65% |
| kernel | 11.80% |

| top named symbol | share |
| --- | --- |
| `spu_thread::process_mfc_cmd()` | **20.13%** |
| `vm::writer_lock` | 4.49% |
| `vm::passive_lock` | 1.73% |

**Almost half of gameplay is code no symbolizer can name**, and the biggest named
function is the SPU DMA path, which this project had never looked at. The lv2
waits that were 73.9% of the title screen do not reach 1% here. Details and the
static disassembly of the JIT cache in
[`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md).

Two lessons outrank the finding itself:

* **Nothing in a year of manual sweeps found this, and one profile did.** Twelve
  manual-derived predictions were refuted; the audit concluded "the ARM64 code is
  clean", and at instruction level it is. The waste was never in instruction
  selection — it was in how long a wait waits. Get the profile first.
* **"93% of spin is GETLLAR" was a share of the instrumented sites only.** The wait
  profiler counts SPU sites and no PPU sites, so these eight could not appear and
  their absence read as evidence. Same failure the ledger lists twice: a search that
  finds nothing and a search that searches nothing look identical.

## The machine

Ayn Thor, Snapdragon 8 Gen 2 (`kalama`), 8 cores in a 1+2+2+3 layout:

| MIDR | core | count | notes |
| --- | --- | --- | --- |
| `0xd4e` | Cortex-X3 | 1 | wide OoO, 4 vector pipes |
| `0xd4d` | Cortex-A715 | 2 | |
| `0xd47` | Cortex-A710 | 2 | |
| `0xd46` | Cortex-A510 | 3 | narrow, shared vector unit per pair |

`/proc/cpuinfo` Features, verified on device:

```
fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm
jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 asimdfhm dit uscat ilrcpc
flagm ssbs sb paca pacg dcpodp flagm2 frint i8mm bf16 bti
```

**There is no SVE or SVE2.** Armv9 cores normally imply it, but Qualcomm does
not expose it here. This is the single biggest trap in this codebase: any LLVM
CPU name from the Armv9 family turns SVE on by default, and SVE codegen on this
device is unselectable. `sanitize_android_arm64_llvm_cpu` in
`util/JITLLVM.cpp` exists solely to catch that and fall back to `cortex-a78`.
Upstream's two SVE commits (`4a92d96cf`, `6349ea2ee`) must never be ported.

## What the JIT tells LLVM

`jit_compiler` sets `mcpu=cortex-a78` plus an explicit attribute list. On device
the line reads:

```
JIT: LLVM AArch64 target: cpu=cortex-a78 triple=aarch64-unknown-linux-android
     attrs=+sha3,+dotprod,+i8mm,-sve,-sve2
```

`cortex-a78` is Armv8.2, so `lse`, `rdm`, `crc`, `fp16` come implied. Anything
newer than v8.2 does **not**, even though the device has it: `lrcpc`, `flagm`,
`flagm2`, `frint`, `fcma`, `sha512`. Adding a feature to that list is free when
it is gated on the matching `utils::has_*()` and paired with an explicit
negative for hosts without it, which is the pattern `+sha3`/`-sha3` follows.

AOT code is built `-march=armv8.4-a -mtune=cortex-a715`. Atomics are real
inline LSE, confirmed by zero `__aarch64_cas*` / `__aarch64_ldadd*` undefined
symbols in the built objects, so there is no outline-atomics tax to remove.

That baseline expands to `+complxnum +crc +dotprod +fp-armv8 +jsconv +lse +neon
+outline-atomics +pauth +ras +rcpc +rdm +v8.1a..v8.4a` — asked of the compiler,
not read off the spec. What it does **not** include, on a chip that has all of
them, is `+aes`, `+sha2`, `+sha3`, `+i8mm`, `+fullfp16` and `+bf16`. The one that
currently costs something is `aes`: the whole AES-NI file is `#if defined(__SSE2__)`,
so every SELF, SPRX and PKG decryption on this device runs four-table software AES.
Measured on device against that exact code, ARMv8 AES decrypts **18.9x** faster on
the X3 and **21.8x** on the A710/A715 (9.0x on an A510, which shares a vector unit
per core pair), with zero mismatches over 60,000 blocks.
See [`docs/arm64/aes.md`](docs/arm64/aes.md).

## Feature to instruction to use-case

What the translators already exploit, so nobody re-derives it:

Pipe assignment for every one of these, read out of the vendored Cortex-X3 guide
rather than assumed. The *pipes* column decides more than the latency does:

| instruction | latency | throughput | pipes | note |
| --- | --- | --- | --- | --- |
| `SDOT`/`UDOT` | 3 (1) | 4 | **V** | all four pipes — the `SUMB`/`GB` choice is well placed |
| `TBX` | 2 | 4 | **V** | all four |
| `TBL` | 2 | 2 | `V01` | **half the throughput of `TBX`, and only two pipes** |
| `TBL`, 3 table regs | 4 | 1 | `V01` | |
| `CNT`, `UABD` | 2 | 4 | **V** | all four |
| `USHL`/`SSHL` | 2 | 2 | `V13` | pipe-restricted; the one to watch |

Two things fall out. **`TBX` beats `TBL` on this core** — four pipes against two,
throughput 4 against 2 — so the `SHUFB` path emitting `TBX2`, recorded below as a
correctness requirement, is also the faster form by a factor of two.
**Corrected: that row is X3 only, and it inverts on the cluster SPU runs on.** On
A715 and A710, `TBL` with 1 or 2 tables is latency 2 at throughput 2 on all `V`
pipes, and 2-table `TBX` is latency 4 at throughput 1. So `TBX2` in `SHUFB`
stays for correctness and is the *slower* form on `CPU5`/`CPU6`. See
[`x86-tricks-arm64-answers.md`](docs/arm64/x86-tricks-arm64-answers.md). And **`USHL` is
the only lowering here stuck on a two-pipe group**; it is used for `inf_shl`/`inf_lshr`
to dodge an LLVM poison-value pessimization, so it is load-bearing, but if a hot block
is shift-heavy that `V13` restriction is where it will show.

| feature | instruction | where |
| --- | --- | --- |
| `asimddp` | `SDOT`/`UDOT` | SPU `SUMB` (9 emitted); SPU `GB` bit-gather via a shift-and-sum constant (31 `sdot`); **and the block-verification accumulate, which is 1,664 of the 1,673 `udot`** |
| `i8mm` | `SMMLA`/`UMMLA` | SPU `GBH`/`GBB` bit-gather, 26 emitted |
| `sha3` | `BCAX` | SPU `EQV`, and both `SHUFB` selector paths |
| — | `TBL`/`TBX`, `TBL2`/`TBX2` | SPU `SHUFB`, `ROTQBY` family, PPU `VPERM` |
| — | `UABD` | SPU `ABSDB` only in principle. **Removed from the block-verification checksum** — `\|a - b\|` is not injective and the checksum decides block identity; see [`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md). After the fix the on-device cache contains **zero** `uabd`, so Eternal Sonata never issues `ABSDB` |
| — | `USHL` | `inf_shl`/`inf_lshr`, dodging an LLVM poison-value pessimization |
| — | `CNT` | SPU `CNTB` via `ctpop` |
| — | `ADDV`/`ADDP` | SPU reductions |

## How to verify a codegen change actually landed

Three levels, cheapest first:

1. **Source contract test.** `tools/test_thor_spu_arm64_bcax_lowering.ps1` is
   the model: pin detection, the JIT attribute, the runtime gate, the fallback
   arithmetic, and every call site, so a regression fails on the host.
2. **Backend selection.** Feed the exact IR to NDK clang at the target the JIT
   uses (`-mcpu=cortex-a78+sha3`) and read the assembly. Also compile it
   *without* the feature: if it fails with `Cannot select`, the runtime gate is
   load-bearing rather than decorative.
3. **On device.** The SPU native object cache key hashes the optimized IR plus
   target identity, so a codegen change invalidates stale objects by
   construction. Boot, pull
   `.../BLUS30161/ppu-*/spu-native-v2`, and disassemble with NDK
   `llvm-objdump`. Count the instruction you expect **and** the sequence it was
   meant to replace.

   **Set `debug.rpcsx.thor.spu_native_object_cache=1` before that boot.** It is
   **off by default** — `spu_native_object_cache_enabled()`
   (`SPUCommonRecompiler.cpp:307`) needs the property *and* title `BLUS30161` —
   so a boot without it recompiles every program and writes **nothing**. An empty
   `spu-native-v2` then looks exactly like a boot that never reached the SPU
   runtime. `SPU Runtime: Built 1188 functions.` in `RPCSX.log` tells the two
   apart. Cost one full boot on 2026-08-10.

   And disassemble the **old** cache first, before clearing it. Reproducing a
   published count on the pre-change corpus is what proves the pipeline works;
   the `xargs -n 40` failure below returns zero for every mnemonic and reads as a
   perfect result.

When counting, match two-source `tbx v.16b, { v.16b, v.16b }` as well as
two-source `tbl`. Our `SHUFB` path emits `TBX2`; a `tbl`-only sweep reads as a
false negative and cost hours once.

## Test an acceleration theory outside the app first

**Build the theory as a bespoke program, not as a change to the emulator.** The
in-app loop costs about forty minutes for one arm: a native build, an install, a
cooldown to 45 C, a boot, and a settle window. The out-of-app loop costs seconds
to minutes. Use the slow loop to confirm a result on the real workload, never to
find out whether an idea is worth having.

Four checks on 2026-08-13 took minutes each and each one decided something:

| question | what answered it | outcome |
| --- | --- | --- |
| Does our restart-index loop need ARMSX3's NEON? | `clang -S` at the JIT's target, both shapes | **No.** Ours already emits their lane algebra, unrolled twice as wide |
| Does bionic's memcpy go non-temporal for large copies? | `llvm-objdump` over the device's own libc | **No.** `stnp` appears zero times in 146,002 lines |
| Is upstream's FI rewrite bit-identical on our clamp path? | a u32 lane model, 2,005,369 pairs | **Yes.** Zero mismatches, so it was safe to take |
| Is the non-temporal copy's block-and-tail arithmetic right? | a model diffed against `memcpy`, 3,072 cases | **Yes**, and the codegen was read separately |

Three shapes, cheapest first:

1. **Read the codegen.** Feed the construct to NDK clang at the target the JIT
   uses and read the assembly. Answers "what does this compile to", which is most
   of what an instruction-selection theory claims.
2. **Model it.** Reimplement both forms as integer functions and diff them over
   the input space. Answers "are these the same", which is what a rewrite of
   correctness-sensitive code has to prove before it ships.
3. **Run it on the device, outside the emulator.** A static AArch64 binary pushed
   to `/data/local/tmp` and run over `adb`, timed with `cntvct_el0` at 19.2 MHz.
   This repo already did this twice: `CTR_EL0` was read that way, and the AES
   numbers (18.9x on the X3, 9.0x on an A510) came from a kernel run against the
   emulator's own code. No APK, no boot, no thermal gate for a short run.

**And the limits, because this project has been fooled by its own microbenchmarks.**
A bespoke program answers *what does this cost in isolation*. It cannot answer
*is this hot* or *what does it compete with*, and those are what decided nine of
the nine refuted predictions in the ledger. The `BCAX` benchmark is the specific
warning: its chain forwarded inside one region where the real code crosses two, so
the number was real and the inference was wrong. Establish reach first — the
[`fi` count of 399 against 5,794 `shufb`](docs/arm64/codegen.md) came out of the
on-device SPU cache, not out of a benchmark — then bench, then confirm in the app.

## Put the command in a script, not in the shell

**Run tools, not long inline commands.** A measurement typed straight into the
shell cannot be re-run, cannot be reviewed, and cannot be fixed once it is wrong;
the same twenty lines get retyped with one value changed and nobody can say later
which arm used which. Every A/B on 2026-08-13 was inlined that way, and two of the
results were retracted.

Anything with a loop, a retry, or more than about three commands belongs in
`tools/`, where it can carry its own refusals. The scripts here already refuse on
the things that have gone wrong before: an absent property, a device that answers
empty because it is unreachable, an arm that samples the wrong scene, a mode that
prints nothing.

`tools/thor_phase_gated_ab.sh` is the current A/B runner:

    tools/thor_phase_gated_ab.sh debug.rpcsx.thor.spu_branch_extract 0 1 3

It interleaves the arms, proves the property is in the shipped `.so`, waits for
frames rather than a fixed time, accepts an arm only when its frame count lands in
the band, and prints both temperatures.

## The phase gate, and the scatter it does not fix

**A title screen is not one workload.** Folklore has an attract movie and a menu,
and a boot lands in whichever. The identical configuration, launched twice, gave
**185 ticks over 1,750 frames** and **1,720 over 3,500**. Ticks per frame does not
rescue it: 0.106 against 0.491. Accepting only 3,500-frame windows pins the scene.

**And that is not enough.** Inside the band the spread for one fixed setting is
about **50 ticks**, several percent. Two results were claimed and retracted on this
basis within a day:

* the SPU self-loop park, reported as a 14% frame-rate regression, then withdrawn
  when a control pair with identical settings disagreed with itself;
* the SPU branch lane extract, reported as 2.8% less CPU and briefly made the
  default, then withdrawn when a control run put the two settings level with the
  sign flipping between pairs.

So: **read ranges, not means**; interleave arms rather than grouping them, because
the device drifted 12% for identical work as it warmed from 30 C to 68 C over a
session; and treat anything under about 5% as unresolved until there are many more
samples per arm, or a normaliser the change provably cannot touch — the
`spu_getllar_retry` denominator in `lv2-ppu-spin.md` took a 59% spread to 1.1%.

**Measure frames alongside CPU, always.** A CPU number on its own cannot tell a
thread that stopped spinning from an emulator that stopped working. That is what
caught the park's first reading, which looked like a 97% saving.

## Traps that have already cost time

- **The thermal guard trips on a launch transient.** Launch reads `56.6 C` at
  `t=4s` and falls to `46.6 C` by `t=10s`. The harness samples into that spike
  and confirms on an immediate re-read, which force-stopped fifteen consecutive
  runs at `14-30 s` on heat the device never sustained. A run reporting
  `66-71 C` while the emulator overlay reads `Total : 22.7 %` is a tripped
  guard, not an emulation-bound run.
- **The panel's anti-image-retention overlay lands on top of runs.** It engages
  when the display sits static, which any cooldown guarantees, and it survives
  into the next run, so visual gates classify noise. Sleep the panel while
  waiting.
- **FPS is only drawn, never logged.** `overlay_perf_metrics.cpp` renders it
  top-left. A capture screenshot is therefore a measurement; open one before
  trusting any gate boolean.
- **Do not port an upstream ARM tuning fix without checking whether this fork
  already compensated.** Upstream's `busy_wait` scaling dropped Thor to ~1 FPS
  because every call site had already been retuned for the real `19.2 MHz`
  timer; two fixes for one problem multiply.
- **`config.yml` cannot be restored with a device-side redirect, and the emulator
  rewrites it on exit.** The file is `-rw-r-----` owned by the app, so `adb shell` is
  in its group with **read only** — `cat backup > config.yml` reports success and
  changes nothing. `adb push` works, because it replaces the file rather than writing
  into it. And RPCSX re-serialises the config when it exits, so a setting changed for
  one experiment survives into the next run and into the file itself. Raising a log
  channel to Trace for a single boot and walking away leaves verbose logging on
  permanently, which then slows every measurement after it. Restore with `adb push`
  and **verify the byte count matches the backup**.
- **Confirm an instrument's output channel produces anything before trusting its
  silence.** `vm_log` writes **zero** lines to `RPCSX.log` on this device, while
  `spu_log`, `ppu_loader`, `RSX`, `sys_*` all appear in quantity. A reservation watch
  logging through `vm_log` was placed six times, produced six silences, and had five
  conclusions drawn from it — all void, because the sink was dead. Checking that the
  format string is in the `.so`, that the property is set, and that the code path
  runs is worthless if nothing flushes. One `grep -c '} vm:'` would have caught it
  before the first build.
- **Every counter in this fork is incremented on completion, so none of them can see
  a hang.** The wait profiler records after `profiled_busy_wait`, the GETLLAR probe
  after its retry loop exits, the RSX auditor after a frame is presented. All three
  were armed against the Eternal Sonata deadlock and all three logged nothing, which
  looks exactly like "this code never ran". They answer *how much did this cost*,
  which is right for a spin and useless for a stall. Every fact in
  [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) came from sampling
  (`simpleperf`) or state inspection (`/proc`, `top -H`, a screenshot) instead. Do
  not add a fourth counter; what is missing is a record-on-entry slot a watchdog can
  read while the wait is still happening.
- **`grep -e 'a\|b'` through PowerShell into `adb shell` does not survive the trip.**
  A search for the RSX auditor's output returned nothing and was briefly taken as
  "the auditor never fired" — it had fired ten times. The alternation is mangled
  somewhere between PowerShell, `adb`, and the device's `sh`. Use a single plain
  pattern per invocation on device. This is the same failure as the entry below,
  which is why it is now listed as four.
- **A search that finds nothing and a search that searches nothing look
  identical.** This has now cost five times. **The fifth, 2026-08-13:**
  `tools/test_thor_arm64_icache_maintenance.ps1` passed on every run while
  `rpcs3/util/JITASM.cpp` still held the reversed bare `asm("ISB"); asm("DSB ISH")`
  pair at two code-publication sites. The test never listed that file. ARMSX3 found
  both sites, not us, and our green test is what said there was nothing to find. The
  file is in the list now, the list asserts that each path exists, and the test was
  shown to fail against a reconstruction of the defect before it was trusted. The third was a device experiment
  labelled "shader cache cleared" that had cleared nothing: the `mv` failed because
  the cache tree is `drwxr-s---` and denies the group write, while
  `config/custom_configs/` is `drwxrws---` and allows it. The `&&`-guarded success
  `echo` never printed and nobody looked. Confirm the postcondition after the
  command, not the precondition before it. **Re-measured 2026-08-10:**
  `files/cache/cache/` itself is now `drwxrws---`, but every level below it —
  `BLUS30161/`, `ppu-*/`, `spu-native-v2/` — is still `drwxr-s---`, so `shell`
  cannot unlink an object there despite being in `ext_data_rw`. On a debuggable
  build `run-as net.rpcsx.easy` runs as the owning uid and clears it; the proof is
  a re-`ls` reading **0**, never the `rm`'s exit status. `tools/test_thor_arm64_apk.ps1` defaulted
  to `app/build/outputs/apk/release/`, a variant nobody builds, and passed for
  months while x86_64 shipped. Then the ledger recorded `lv2` and the HLE modules
  as architecture-neutral on a grep across `Emu/Cell/lv2` and `Emu/Cell/Modules`,
  **neither of which exists in this fork** — the syscall layer is
  `kernel/cellos/`, and scanning it properly turned up a second x86-only
  power-optimized wait. Before recording a zero, confirm the path exists.
- **`debuggable` used to decide the native optimization level, and nobody noticed.**
  AGP picks `CMAKE_BUILD_TYPE` from the variant's debuggable flag — debuggable gives
  `Debug`, otherwise `RelWithDebInfo`. So `-PrpcsxThorDebuggable=1` silently moved the
  emulator core from `-O2 -g -DNDEBUG` to unoptimized **with assertions enabled**,
  which is a measurement hazard first and a 1.4 GB `.so` second. Any timing taken on a
  debuggable build before this was fixed is comparable only against another build from
  the same flag set. Now pinned: `build.gradle.kts` passes
  `-DCMAKE_BUILD_TYPE=RelWithDebInfo` explicitly, because debuggability is an APK
  manifest property and has no business deciding whether the SPU recompiler is
  optimized.
- **Every distinct CMake flag combination costs 8-11 GB of disk, and nothing reaps
  them.** `app/.cxx/<buildType>/<hash>/` is keyed on the argument list, so each flag
  combination spawns a fresh tree with its own objects and unstripped library. One
  session of toggling reached ~80 GB and filled a 930 GB disk. The failure does not
  look like a disk problem — Gradle reports
  `Failed to stop service '...BuildFinishBuildService'` under a Kotlin daemon heading,
  with `There is not enough space on the disk` in a sub-clause, so the instinct is to
  debug the toolchain. Run `tools/thor_reap_build_cache.ps1` (dry run by default,
  `-Apply` to delete) and check `app/.cxx` before believing any build error.
- **The version banner in `RPCSX.log` does not prove which binary is installed.**
  It read `v20260807-88f714c` while the running build was three commits newer and
  contained code that commit does not have. The build-info string is generated by a
  task that goes up-to-date and stops regenerating. This fork has already had one
  round where the question "did the change reach the device?" mattered enough to get
  its own commit, so verify with something the new code *does* — a property it reads,
  a symbol `grep -a` finds in the shipped `.so` — never the banner.
- **A cold boot spends about 27 minutes in PPU precompile before the first PPU
  thread exists, so a short settle window measures the precompile and not the
  game.** Measured 2026-08-13 on Folklore with a parked cache: `SYS: Title:` at
  `0:00:03`, and the first `PPU[0x1000000] main_thread` line at **`0:27:01`**. An
  A/B arm with a 240 second settle therefore reported **14.6 CPU-seconds over 254
  seconds**, no `SPU Runtime` line and no PPU threads, and every other check came
  back clean — pid alive, nothing paused, device cool and uncontended.
  **The first diagnosis of that arm was wrong.** It was read as
  `launcher-ui-instead-of-title`, a failure this repo already records, when the
  boot was in fact healthy and simply 27 minutes from starting. The check written
  to catch it — refuse an arm with no `PPU[0x` lines — would have voided **every**
  cold run. `tools/thor_spu_compile_claim_ab.ps1` now separates three states: no
  log at all is an instrument fault, precompile activity with no PPU threads is a
  window that is too short, and neither is a boot that never started. Size a cold
  arm past the precompile, or run it against a warm PPU cache.
- **The vendored core is far newer than its version string says, so do not date it
  from `rpcs3_version.cpp`.** That file reads `0, 0, 36`, and upstream bumped 0.0.36
  on **2025-03-30**. Counting upstream commits from that bump gives "523 commits and
  16 months behind" for the CPU core and RSX, and **that number is wrong**. Checked
  by content instead: upstream's ARM64 change `21d533675` (2026-07-06) is present in
  `SPURecompiler.h:392`, as are `61a260482` (readcyclecounter, 2026-05-14) and
  `320e8d634` (the FCGT/BSL workaround, 2026-05-12). The base carries upstream work
  through **at least 2026-07-06**. This is the version-banner trap above in a second
  costume: date the tree by finding a known commit's code in it, never by a
  constant. And note our direct upstream `RPCSX/rpcsx` is nearly dormant — its
  master's newest commit is **2026-06-06** — so this fork is *ahead* of RPCSX on
  rpcs3 content and takes rpcs3 changes directly.
- **`TBL2`/`TBX2` need a retry owner.** They can trip the AArch64 register
  scavenger. The SPU block compiler has `compile_spu_llvm_with_retry`; the SPU
  interpreter builder deliberately does not, and stays on the plain path.

## Measuring things here, and five ways it went wrong

Every one of these cost a build and a device run, and each is written up where it
happened. They are collected because they are about *method*, not about any
subsystem, and every one of them produced a confident wrong answer first.

- **Normalize by something the change provably cannot touch.** Two WFE A/Bs
  failed on workload variance before the third worked, and the fix was not a
  steadier workload but a better denominator: `spu_getllar_retry` sits in a loop
  the flag never enters, so dividing by it took a 59% spread down to 1.1%. Read
  which branch the flag is in before designing the experiment.
- **A mean over a heavy-tailed distribution invites the wrong decision.** GETLLAR
  spin depth averaged `135.2`, which reads as "every wait is long". The histogram
  put **95.5% below 8**; one deep wait was carrying the mean. The check that
  catches it — what would a single extreme sample alone produce — is one line of
  arithmetic.
- **Instrument what you changed, not only what you hoped to improve.** A
  graduated backoff on GETLLAR measured as an exact no-op, `300.0` ticks per call
  unchanged, because the gate it keyed on had already been passed. Had it shifted
  5% it would have been kept, and the broken denominator never noticed.
- **A fix that transfers between sites is a hypothesis.** `passive_lock` and
  `GETLLAR` looked like one shape — a busy-wait whose measured wait seems shorter
  than its backoff. One spins immediately; the other only after a separate gate
  has decided the wait is durable. The gate was in the source the whole time.
- **When a shared variable is suspected of contention, instrument every party
  that reads it.** `vm_writer_lock` recorded zero spins, which was read as "this
  word is uncontended". It only showed the *writer* never blocks; the readers in
  `passive_lock` were 17.5% of all spin, in the same log line.

The pattern across all five: the measurement was correct and the *inference* was
not. When a number decides something, state what population it is over and what
it excludes, before acting on it.

## SUPERSEDED 2026-08-16: Eternal Sonata boots and reaches its title screen

**Observed on device at 21:27, 29.99 FPS at the title screen.** The overlay read
PPU 2.0%, SPU 17.4%, RSX 2.5%, Total 22.0%. The section below describes a
deterministic hang about eight and a half seconds into emulation. That did not
happen. Read the rest of this section as history, and for the SPURS analysis,
which is still the best account of what the stall was.

**Do not credit any one change for this.** The build carried five, and no control
was run:

* the SPURS `cpu_flag::wait` port (`47cff9303`)
* the Adreno fence poll (`28cd69e9e`)
* conditional rendering off on Qualcomm drivers (`489b1845e`)
* the descriptor reserve cut (`cb6a7ab6c`)
* the occlusion query yield (`60d5a5be5`)

**And the baseline is not clean.** Every earlier hang observation on this device
was taken while the app loaded the **dev-core override from 2026-07-17**, not the
core in the APK. See "Prove which binary the device is running". The bundled core
may well have booted this title before any of the five landed. Nobody has run
that arm.

**The control that would settle it:** build the bundled core at `2d7145325`, the
commit before the five, install it, verify `/proc/<pid>/maps`, and boot the same
title. Until then this is "it boots", not "we fixed it".

Two other things the same boot settled:

* **The precompile progress display already exists and is good.** The screen reads
  `Compiling PPU Modules...`, `Progress: file 78 of 78, module 44 of 76`, and a
  remaining time, over a progress bar. A QOL list built from the README claimed
  this was missing. It was wrong, as were four other items on it.
* **Precompile here was about five minutes, not twenty-seven.** Boot at 21:22:25,
  title screen by 21:27. The 27 minute figure in "A cold boot spends about 27
  minutes in PPU precompile" was a colder cache; treat it as an upper bound, not
  the normal case.

## History: the game did not boot before 2026-08-16

Eternal Sonata hangs about eight and a half seconds into emulation, deterministically,
and never recovers. The screen keeps the last frame RSX presented — usually the SPU
cache overlay — which makes it look like a stalled compile. It is not; nothing is
being written to disk.

`simpleperf` on a debuggable build puts **two** threads at exactly 100%: an SPU thread
and `rsx::thread`, both reaching `sched_yield`. The SPU one is the real stall — it sits
in the **`GETLLAR` reservation retry loop** (`SPUThread.cpp:6212`), past its 24-spin
limit, in the slow-yield branch, waiting on a reservation that never settles. RSX is
merely spinning on an **empty FIFO** behind it.

The same site is the 93%-of-spin lever below. That makes this **the** thing to
understand: a reservation path that both deadlocks at boot and produced the two earlier
guest faults. It also blocks the GETLLAR sweep, which needs the title to reach gameplay.

Reproducing it takes one command and ten seconds, against a combat encounter for the
guest crash. Write-up, the six hypotheses ruled out, and the confident wrong answer that
static reading produced first, in [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md);
`tools/thor_diagnose_rsx_hang.ps1` gets back to it.

Investigating it needs `-PrpcsxThorDebuggable=1`. The release build refuses `run-as`,
and `/proc/<tid>/syscall` is useless anyway for a thread that never blocks — it reports
`running` every time.

## The three things actually open

**Items 0 and 1 need re-testing before anyone works on them.** Eternal Sonata
reached its title screen on 2026-08-16 at 29.99 FPS, so the stall they describe
did not occur in that build. Whether the defect is fixed, or merely not reached,
is unknown: the build carried five changes and the earlier observations were all
taken against the July dev-core override. **Boot Folklore before assuming the
SPURS analysis below still describes live behaviour.** Full note at the top of
this file.

**RE-MEASURED 2026-08-23: items 0 and 1 below are HISTORY. The stall is gone.**
Eternal Sonata boots and holds **30.00 FPS**; Folklore boots and holds **60.00
FPS** with `SPU self-loop park: entries=0`. The GETLLAR stall reporter is still
armed and fired zero times in either run. Transformers ran four sessions the
same day, reached 3D combat every time, and reported `trap=0 dead=0`. So no
SPURS fault reproduces on any of the three titles right now. What remains on
Transformers is speed and heat, about 19 FPS at 92 to 95 C, which is not this
defect. Full note in `docs/arm64/rsx-boot-hang.md`.

0. **It is a SPURS defect, not one game.** Folklore stalls at the **same SPU PC
   `0x12b0`** in `CellSpursKernel0`, same `lsa=0x100`, same 24-retry cap, on a
   different reservation address. Both load Sony's SPURS kernel from `libsre`, so
   this is one instruction in one firmware module failing identically in two
   unrelated titles — two of the three tested. Fixing it is worth far more than one
   boot, and it also unblocks the GPU tiler work, which needs a title that renders.

1. **The Eternal Sonata deadlock**, above — now with an address and a culprit.
   `CellSpursKernel0` stalls on its workload reservation at **`0x9d4d80`**
   (`lsa=0x100`, `pc=0x12b0`, retries capped at 24), reported from inside the wait
   because no completion-time counter can see it. The reservation word is
   `ntime=0x200, unique_lock=0, counter=4` — **no leaked lock, line clean and
   readable, written exactly four times since boot and then never again.** So the
   reservation machinery is not at fault; the PPU side stops publishing the SPURS
   workload descriptor. SPURS has hung this title on this device before — the profile
   still carries *"SPURS 4 caused a black-screen-alive load hang on Thor"*. Next:
   log the four writes to `0x9d4d80` and find what should have caused a fifth.
2. **~~What hardware AES is worth on a cold boot.~~ Closed: nothing.** The firmware
   set is 144 files totalling **13.6 MB**, so at the measured rates the whole thing
   is 36.6 ms of software AES against 1.9 ms of hardware — about 35 ms, against a
   boot that takes minutes. The 19-22x is real and the volume is tiny; the ratio was
   never the interesting number. Still worth timing where the volume *is* large:
   PKG install and runtime EDAT/SDAT streaming. See
   [`docs/arm64/aes.md`](docs/arm64/aes.md).
3. **`SPULLVMRecompiler` and `PPUTranslator`.** The genuinely hot path, barely
   touched. One probe in so far, and it argues these are in good shape: saturating
   arithmetic goes through `llvm::Intrinsic::sadd_sat`, which AArch64 selects as a
   single `sqadd`/`uqadd` at **every** width — where x86 SSE has no 32-bit saturating
   add at all and synthesises it from `pcmpgtd`. VMX's `VADDSWS` is therefore cheaper
   here than on the architecture this emulator was written for.

   The lesson generalises: the translators emit **IR, not per-ISA intrinsics**, so
   the backend picks the encoding and there are no x86 intrinsics to find. The real
   search is narrower — *which operations have no natural IR spelling, and did the
   hand-written lowering pick well?* That is the `BCAX`/`SDOT`/`TBL`/`USHL` set, and
   [`codegen.md`](docs/arm64/codegen.md) already tracks it.

## The one thing to run next, once it boots

**93% of all emulator spin is the SPU `GETLLAR` wait, and the emulator spins there
because it is configured to, 100% of the time.**

`SPU GETLLAR Busy Waiting Percentage` decides whether that wait spins or sleeps.
Upstream defaults it to 100 — always spin — and no Thor profile overrides it,
while the analogous `SPU Reservation Busy Waiting Percentage` is explicitly set
to 0 for this device. The trade was considered once, applied to the smaller of
the two sites, and never revisited for the larger.

The alternative branch is a **real futex sleep**, woken by the actual reservation
notifier with the timeout as a fallback — which is a better-shaped mechanism than
the `WFE` park this fork spent three experiments on, because `WFE` cannot have a
timeout without `FEAT_WFxT` and this chip lacks it.

Every link is verified except the effect size:

    ./gradlew assembleThortest -PrpcsxThorWaitProfiler=1
    # unplug the Thor first, or the wattage is only a floor
    ./tools/thor_getllar_percent_sweep.ps1

Four arms, one command. It throws rather than guessing if the property did not
take, the boot failed, or the profiler is absent, and it reports p95 frame time
because the risk of sleeping is **latency**, which a capped frame rate hides.
Detail in [`docs/arm64/spin.md`](docs/arm64/spin.md).

## ARM64 review coverage, so nobody re-sweeps clean ground

What has actually been looked at for "x86 assumptions that need rethinking here",
and what the answer was. **Most candidate wins evaporated under
measurement**, which is why this table exists.

The exception is instructive. The largest real defect was not a missed
optimization — it was `mov_rdata` silently compiling to nothing, found by
counting which branch of a loop executed rather than by reading code. Noticing
something was broken mattered more than optimizing anything.

| area | status | finding |
| --- | --- | --- |
| AES / `Crypto` | **fixed** | AES-NI was `#if __SSE2__`; ARMv8 AES now wired in, 19-22x on the primitive — but worth **~35 ms** of boot, because only 13.6 MB is decrypted |
| Saturating arithmetic | clean | `llvm.sadd.sat` → one `SQADD` at every width; x86 has no 32-bit saturating add at all, so VMX is *cheaper* here |
| Float↔int with scale | clean | `fptosi.sat(x * 2^n)` folds to a single fixed-point `FCVTZS` |
| Acquire loads | clean | `cortex-a78` already emits `LDAPR`; `+rcpc` changes nothing |
| 128-bit atomics | clean | LSE2 path live and verified in the build cache, not the `LDAXP`/`STLXP` loop |
| Non-temporal stores | clean | `_mm_stream_si128` reaches a real `STNP` through the shim |
| `MFCR`, PPU interpreter | clean | already `ARCH_X64`-guarded with an ARM64 fallback |
| SPU interpreter | **cold** | unguarded `movemask`, but both decoders are LLVM — the interpreter is fallback-only |
| Rosetta techniques | n/a | its central problem (x86 TSO) does not exist; PowerPC is weakly ordered and AArch64 is stronger |
| **GPU render passes** | **open, instrumented** | unconditional `LOAD_OP_LOAD`/`STORE_OP_STORE`, `LOAD_OP_CLEAR` used zero times, ~16 MB/frame. The blocker (a title that renders) is gone; eligibility counters now at `VKGSRender.cpp:1631`, unrun |
| **`mov_rdata`** | **fixed** | the `#elif defined(ARCH_ARM64) && defined(__clang__)` branch held **only comments** after a revert, so the copy every reservation is validated against did nothing. 10,093,915 failed retries in one boot; two titles could not boot. `tools/check_empty_arch_branches.py` now guards the class |
| **UMA / BAR heap** | **open, measured** | `device.cpp` parks host-visible+device-local memory as a scarce PCIe aperture. Here it is 11441 MB — one heap, every type device-local, type 1 also `HOST_CACHED`. The staging copy's destination is its own source. Volume counter added, unrun |
| SDOT/UDOT | clean | the video's headline optimization is already here: `sdot`/`udot` at a dozen sites in `SPULLVMRecompiler.cpp`, gated on `HWCAP_ASIMDDP`, default **on**, with a `debug.rpcsx.thor.spu_arm_features` override |
| SPU/PPU translator lowerings | clean so far, 3 probes | saturating arithmetic → `SQADD` at every width; SPU `AVGB` → a single **`URHADD`**; SPU `ABSDB` → a single **`UABD`**. All from *generic IR* with no ARM-specific code. The remaining question is only the ops with **no** IR spelling — the `BCAX`/`SDOT`/`TBL`/`USHL` set in [`codegen.md`](docs/arm64/codegen.md), which already have hand-written lowerings |
| **SPU block-verification checksum** | **fixed, confirmed on device** | the ARM64 path folded half of every 96-byte block through `UABD`, and `\|a - b\|` is not injective — a uniform delta across a pair collides, so the verifier could accept the wrong cached block. Inherited from **upstream RPCS3 master**; fix (sum the pairs) taken from ARMSX3. Cleared cache, cold boot, re-disassembled 2026-08-10: `uaba` **4,503 → 0** and `uabd` **910 → 0** of **509,424** instructions, `add` +9,587. Title boots and holds 30 FPS |
| `BufferUtils.cpp` | **ported, unmeasured** | `copy_data_swap_u32` had 11 x86 gates and no ARM64 form, so it fell through to a scalar loop behind a non-inlinable function pointer with LTO off. `copy_data_swap_u32_neon` ported from ARMSX3. **No device measurement**; our profile puts the whole vertex/buffer cluster near 0.2% |
| `BufferUtils.cpp`, restart path | **clean, verified** | ARMSX3 hand-wrote NEON for the primitive-restart index upload, saying clang cannot vectorize it. True of upstream's conditional shape, false of ours: the branch-free rewrite here compiles to `rev16`/`cmeq`/`orr`/`bic`/`umin`/`umax`/`uminv`/`umaxv` — their exact lane algebra — unrolled to two `q` registers per iteration, so it is twice as wide as their kernel. Upstream's shape emits four `csel` and no vector instruction. Read at `-O2 -march=armv8.4-a -mtune=cortex-a715`, not assumed |
| RSX vertex/texture paths | clean | `RSXThread.cpp` has **no** x86 intrinsics; `ProgramStateCache.cpp` already byteswaps with `vrev16q_u8` (one `REV16` against x86's shift-or pair) and keeps its AVX-512 behind `ARCH_X64`; `buffer_stream.hpp` reaches a real `STNP` |

The pattern worth carrying: the translators emit **IR, not per-ISA intrinsics**, so
the backend picks the encoding and there are usually no x86 habits to find. Effort
belongs where no portable IR construct exists, or where the *hardware model*
differs — which is why the GPU tiler row is the one that is still open.

## Where the rest of this lives

These notes outgrew a single file. The detail is split by topic; each document
stands on its own and this file is the map.

| document | what is in it |
| --- | --- |
| [`docs/arm64/codegen.md`](docs/arm64/codegen.md) | What this fork does: the lowerings chosen here, the missing movemask, the SPU opcode audit, and the x86-habit table that produced most of the real defects. |
| [`docs/arm64/x86-tricks-arm64-answers.md`](docs/arm64/x86-tricks-arm64-answers.md) | **The seven x86 instructions RPCS3 abuses for SPU work, answered for AArch64.** None of the seven is a candidate; together they are 0.04% of emitted code. It corrects two claims in this file: **1,664 of the 1,673 `udot` are the block-verification accumulate, not `SUMB` or `GB`**, and **`TBX` does not beat `TBL` on A715/A710**. The real candidate it found is the SPU branch lowering, which builds a 16-bit movemask at 1,402 sites to test one bit. **That candidate now passes check 1: LLVM keeps the lane extract (8 instructions against 2), and the two spellings compute the same predicate. The lane extract now ships at all eight opcodes behind `debug.rpcsx.thor.spu_branch_extract`, default 0, so nothing changes by default. The reach is still unmeasured, and only 786 of the 1,402 sites are attributed.** |
| [`docs/arm64/bench-results.md`](docs/arm64/bench-results.md) | **Measured on the silicon, outside the emulator, 2026-08-13.** **And a warning about the in-app arms: every one of them is void.** A control pair with identical settings gave 185 ticks over 1,750 frames and 1,720 over 3,500, so Folklore's title screen has phases and a boot lands in one of them. Run a control pair that agrees with itself before believing any arm on a title. `YIELD` is exactly a `nop` (0.36 ns, same as a load); `ISB` is 11.42 ns, which is the arithmetic behind the +23% regression. A futex park costs **~10 us** of wake latency against 0.44 us for a spin, which sizes the SPU self-loop park at 0.06% of a frame. **`TBX2` costs 2.1x the throughput of `TBL2` on the A715 and A710** — and `SHUFB`, the most common operation in the corpus at 5,794, emits `TBX2`. The non-temporal copy is only **3.1% faster at 16 KB**. And **CPU5 and CPU7 refuse an exclusive pin while the device is idle** — Qualcomm `core_ctl` pauses them, so they read `online=1` and still reject affinity. Load the machine and the same pin succeeds, so the placement advice stands; the trap is that **a light benchmark cannot measure the prime core**. |
| [`docs/arm64/microarchitecture.md`](docs/arm64/microarchitecture.md) | What the hardware does: instruction latency, throughput and pipe assignment from the vendored per-core guides, the forwarding regions, and the chapter 4 rules. |
| [`docs/arm64/memory-model.md`](docs/arm64/memory-model.md) | Atomics and ordering: the LSE2 128-bit path (no longer dead — see below), the reservation seqlock, RCsc versus RCpc, and instruction-cache maintenance. |
| [`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md) | **The largest finding here, and the only one from a real profile.** 73.9% of all cycles are a nop-spin in two lv2 wait syscalls; the same loop appears at eight sites across the guest sync layer. |
| [`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md) | **What the SPU JIT actually emits**, disassembled from the on-device cache: 1,185 objects, 509,468 instructions. `udot` at 1,661 was read as proof the video's optimization is taken. **Corrected:** 1,664 of the 1,673 post-fix `udot` are the **block-verification accumulate**; `SUMB` emits **9**. The largest visible cost is stack traffic — `sp` is the second hottest base register, 10.1% of all instructions. |
| [`docs/arm64/armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) | **ARMSX3 diffed against upstream RPCS3**, so their work is separated from what they inherited. **The one correctness item in the first pass was ours too** — the SPU checksum's non-injective `UABD` fold, now fixed here. **Second pass, 2026-08-13, against their `e10f846`:** diff from the fork point (`652cf60bf`) instead of from master, which attributes all 210 commits exactly. **It retracts two claims:** they reverted `thread_scheduler_mode::alt` after measuring six SPU threads on four cores, and they put the GETLLAR busy-wait percentage back to upstream's 100. Four things ported: the same-item SPU compile race, two remaining JIT i-cache sites, the GETLLAR out-buffer memo and cap, and a memory budget for the PPU compile workers. One rejected after checking: their NEON index upload, because our branch-free loop already compiles to the same kernel, unrolled twice as wide. |
| [`docs/arm64/three-way-audit.md`](docs/arm64/three-way-audit.md) | **The second pass of the three-way method**, over the six files the gameplay profile makes hot. One correctness item: the SPU **ubertrampoline** reaches other cores with **no instruction cache maintenance** in our tree and in upstream, and ARMSX3 flushes it. Two defects live in the other two trees and are already fixed here: PPU `FCTIW`/`FCTID` and SPU `CFLTS`/`CFLTU` apply an **x86 saturation correction on AArch64**, which turns a correct value into the wrong one. No second non-injective fold exists, and no dead ARM branch exists in the hot files. |
| [`docs/arm64/busy-wait-inventory.md`](docs/arm64/busy-wait-inventory.md) | **Every `busy_wait` site with its real duration in µs**, computable statically because `get_tsc` is `cntvct_el0` at 19.2 MHz. Six sites pass no argument and so took the x86 default of 3000 — 156 µs each — and could not have been part of the hand-retune. `shared_mutex` spins **1.56 ms** in front of a working futex. |
| [`docs/arm64/spin.md`](docs/arm64/spin.md) | Where the CPU time goes *on the SPU side*: 93% of instrumented spin is the `GETLLAR` wait. Read `lv2-ppu-spin.md` first — that 93% is a share of the sites the wait profiler counts, and it counts no PPU sites. |
| [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) | **Resolved.** The boot hang, three wrong diagnoses, and the empty `mov_rdata` branch behind it. Folklore now reaches its title screen at 60.01 FPS. |
| [`docs/arm64/uma-bar-heap.md`](docs/arm64/uma-bar-heap.md) | Snapdragon is UMA, so the "BAR heap" the Vulkan backend parks as scarce is all 11.4 GB of it. What is measured and what is not. |
| [`docs/arm64/ppu-compile-oom.md`](docs/arm64/ppu-compile-oom.md) | A second title dies in PPU precompile with a Scudo out-of-memory, and why the 1536 MB budget bounds concurrency rather than footprint. |
| [`docs/arm64/aes.md`](docs/arm64/aes.md) | AES-NI is x86-gated, so every module decrypted at boot uses software AES on a chip with AES instructions — plus three related checks that came back negative. |
| [`docs/arm64/x86-isms-sweep.md`](docs/arm64/x86-isms-sweep.md) | Every remaining `_mm_*` site outside 3rdparty, asked "is this executed?" before "is this optimal?" — and why the interpreters, which look like the biggest target, are not. |
| [`docs/arm64/rosetta-lessons.md`](docs/arm64/rosetta-lessons.md) | What Rosetta 2 does and why its central problem — x86's TSO — does not exist here, plus the four techniques it is famous for that this codebase already has. |
| [`docs/arm64/adreno-tiler.md`](docs/arm64/adreno-tiler.md) | **The one place the code is still written for the wrong hardware.** Every render pass unresolves and resolves both attachments, and `LOAD_OP_CLEAR` is used zero times. |
| [`docs/arm64/instruments.md`](docs/arm64/instruments.md) | The measuring tools, what each can and cannot answer, and the mistakes made building them. **Frame timing: `dumpsys SurfaceFlinger --latency` on the `(BLAST)` layer gives per-frame present timestamps — a real distribution, no build flag, no code.** |
| [`docs/arm64/thermal.md`](docs/arm64/thermal.md) | Junction versus package sensors, and the guard that compared a limit against the wrong one. |
| [`docs/arm64/ledger.md`](docs/arm64/ledger.md) | The audit ledger: every `ARCH_X64` block accounted for, the open opportunities, and the subsystems that needed nothing. |
| [`docs/hardware/`](docs/hardware/) | Vendored vendor docs: Arm's Cortex-X3, A715 and A710 optimization guides, plus Qualcomm's 200-page Adreno guide — and why the GPU one opens a review axis nothing here has started. |

`AGENTS.md` is the operating contract. This file is the hardware knowledge behind
it.

## Two things that outrank everything else here

**Most of these notes are still not measured against a running game.** The
exception is the wait profiler, which has now been run on device during gameplay
and gave the first hard numbers here: **16.9% of busy CPU time is spin, 82.5% of
that in `GETLLAR`**, with `vm_passive_lock` a further 17.5%, and a normalized WFE
A/B showing the park displacing 20% of the inner spin at eighteen times the noise
floor.

Everything else — every instruction-selection change in particular — is still
argued from correctness, instruction counts or hardware capability, with no
before-and-after. And the changes most likely to matter in practice were never
about instruction selection at all: custom GPU drivers going from never-loading to
working, and i-cache maintenance that a stale fetch would have turned into an
unreproducible crash.

**The recurring failure mode is a measurement that is correct and still supports
the wrong decision.** It has happened at least four times: a junction temperature
compared against a package-shaped limit, a thermal A/B that was really detecting
which cores an arm ran on, a WFE experiment whose two arms sampled different
cutscenes, and a BCAX microbenchmark whose chain forwarded within one region
where the real code crosses two. In each case the number was real and the
inference was not. When a result decides something, check that the thing measured
is the thing that ships.

## Traps found while enumerating guest threads

**PPU thread ids are not stable across boots.** `0x1000009` was `SpursHdlr0` in one
Folklore boot and `LoadThreadMain` in the next. Ids are handed out in creation
order, so any tool that hardcodes an id-to-name map is only valid for the boot it
was written against — and `tools/thor_gdb_probe.py` did exactly that. Recover names
from `RPCSX.log`, which prints them as `PPU[0x100000c] Thread (SpursHdlr0)`.

**The GDB stub implements `qfThreadInfo` and nothing else.** No `qThreadExtraInfo`,
so it cannot tell you a thread name. Worse, it is single-shot in two ways:
connecting **pauses emulation** (`Emulation is being paused... (mark=0)`), and
disconnecting **kills the stub thread** (`GDB.cpp:241`, "Tried to read char, but no
data was available"). Budget one probe per boot and collect everything in that one
connection. `tools/thor_gdb_all_threads.py` does the full sweep.

**Git Bash rewrites device paths.** `adb pull /sdcard/...` becomes
`C:/Program Files/Git/sdcard/...` and fails with a confusing "failed to stat remote
object" naming a local path. Prefix with `MSYS_NO_PATHCONV=1`. This is separate from
the heredoc backslash problem that previously turned `.\tools\thor_x.ps1` into a
line with two literal tabs in it.

**A conclusion from one boot is a conclusion about one boot.** The SPURS descriptor
was all zero in one run and had `wklReadyCount1[7] = 1` in the next — same title,
same stall, same `pc=0x12b0`, opposite readings. Two conclusions in
`docs/arm64/rsx-boot-hang.md` were drawn from single boots and neither survived a
second. Re-run before concluding.

## Read the build warnings

`mov_rdata` compiled to a function that copied nothing on every ARM64 build from
b46198f0b (2026-08-07) until b15d105a6, because that revert left an empty
`#elif defined(ARCH_ARM64) && defined(__clang__)` branch behind. It is the copy
every SPU reservation is validated against, and it cost several sessions of
investigation across `docs/arm64/rsx-boot-hang.md`.

The compiler reported it on every single build:

    SPUThread.cpp:1301:25: warning: unused parameter '_dst'
    SPUThread.cpp:1301:50: warning: unused parameter '_src'

Unused parameters on a function whose only job is to write `_dst`. Nobody read
it because the build prints hundreds of warnings.

`./gradlew assembleThortest 2>&1 | grep -E "warning: unused (parameter|variable)"`
is cheap. An unused parameter on a function that exists to write through it is
not style: it means the body is gone.

**And when a loop will not exit, count its exits.** Four counters on the four
`continue` paths of the GETLLAR retry loop identified the failing comparison in
a single boot — after three separate wrong conclusions had been reasoned out
from static reading and single-boot dumps.

## The BAR heap is not an aperture on this device

`Emu/RSX/VK/vkutils/device.cpp` collects memory that is host-visible *and*
device-local into a "BAR heap" and parks it: `// BAR heap, currently parked for
future use`. That is right for a discrete GPU, where those bits mean the PCIe
aperture and historically 256 MB of it.

Measured on the Thor — `VkPhysicalDeviceMemoryProperties`, dumped at
`device.cpp:1186`:

    type 0: DEVICE_LOCAL HOST_VISIBLE HOST_COHERENT              11441 MB
    type 1: DEVICE_LOCAL HOST_VISIBLE HOST_COHERENT HOST_CACHED  11441 MB
    type 2: DEVICE_LOCAL HOST_VISIBLE HOST_CACHED                11441 MB
    type 3: DEVICE_LOCAL LAZILY_ALLOCATED                        11441 MB

**One heap, every type device-local.** There is no separate VRAM here, so the
staging copy on the way to "device-local" memory has a destination that is the
same physical DRAM as its source. Type 1 is device-local, host-visible, coherent
and cached at once, which is the combination a direct-write upload path needs.

Type 3 (`DEVICE_LOCAL | LAZILY_ALLOCATED`, no host visibility) is Adreno's
on-chip tile memory — the correct backing for transient depth/MSAA attachments
that are never sampled outside their pass, and a direct pairing with the
`LOAD_OP_CLEAR` work in `docs/arm64/adreno-tiler.md`.

Feasibility is settled; the win is not measured. `docs/arm64/uma-bar-heap.md`
records what still has to be shown before changing the upload path.

## The manual the video was about, and the optimization it describes

The video that set this project's direction is *"PS3 emulation is fast on ARM
now"* (2026-08-04). The manual it refers to is **not** a Qualcomm chipset
document — it is the **Arm Architecture Reference Manual**, which the RPCS3 team
describe scouring *"every page"* of, *"over 17,000 pages"*. That page count
identifies the issue exactly: **DDI 0487 M.c has 17,145 pages**. It is now
vendored in `docs/hardware/` as three ~40 MB parts, rebuilt by
`sh docs/hardware/assemble_arm_arm.sh` (SHA-256 checked). Split because 120 MB
exceeds GitHub's hard 100 MB blob limit and **LFS is refused on this repo** —
GitHub blocks LFS uploads to a public fork, as the objects bill to the upstream
owner.

Fetch the current issue from Arm's JSON index rather than guessing CDN paths:

    curl -sS "https://documentation-service.arm.com/documentation/ddi0487/latest?lang=en&baseUrl=/documentation"

`_links.resources[0].href` is a plain-`curl`-fetchable URL.

**Its headline optimization is already in this fork.** The video's specific claim
is Armv8 `SDOT`/`UDOT` used to speed up SPU emulation. Checked rather than
assumed, after `mov_rdata` taught this project what an unchecked assumption
costs:

* `SPULLVMRecompiler.cpp` uses `sdot`/`udot` at a dozen sites.
* They are gated on `m_use_dotprod` ← `utils::use_spu_dotprod()`
  (`sysinfo.cpp:548`).
* That reads `has_dotprod()`, which tests **`HWCAP_ASIMDDP`** — correct runtime
  detection, not a compile-time guess.
* The default feature mode is `native`, so it is **on**, with a runtime override
  at `debug.rpcsx.thor.spu_arm_features` (`no-dotprod`, `no-i8mm`, `baseline`)
  for A/B work.

So there is nothing to port here — the useful follow-up is measuring what those
modes are worth on this device, not implementing them.

## Guard against the empty-branch class

`python tools/check_empty_arch_branches.py` walks the native tree and fails if any
`#if`/`#elif` on `ARCH_ARM64`, `ARCH_X64`, `__aarch64__` or `__x86_64__` contains
only comments. It skips `3rdparty` and `llvm`, and handles nesting so an inner
`#else` is not mistaken for the end of the branch.

Currently: **1,489 files scanned, zero findings.** It is verified against a
reconstruction of the `mov_rdata` defect, which it flags with exit 1 — a check
that has never caught anything and has never been shown to catch anything is not
worth trusting.

Run it after any revert that removes a function body. That is precisely how the
original was introduced.

## Wireless adb, and "the process died" when it did not

The Thor answers on both a USB serial and `192.168.1.33:5555`. The USB serial
disappears without warning, and `adb devices` then lists only the network one —
so a script pinned to the USB serial fails with `device 'c3ca0370' not found`
rather than falling back. Reconnect with `adb connect 192.168.1.33:5555`.

Over Wi-Fi the link drops mid-run. That breaks the obvious liveness check:

```sh
alive=$(adb -s $S shell "pidof net.rpcsx.easy")
if [ -z "$alive" ]; then echo "DIED"; fi      # wrong
```

An unreachable device returns empty exactly like a dead process. A watcher
written this way reported `DIED` while the emulator was still running and had
been for two minutes. Probe reachability separately before believing an empty
`pidof`:

```sh
ok=$(adb -s $S shell "echo ok" 2>/dev/null | tr -d '\r ')
[ "$ok" != "ok" ] && echo "adb unreachable, liveness unknown"
```

The general shape is the one this project keeps rediscovering: **a negative
result from a channel you have not proved is working is not a negative result.**
Same class as `vm_log` emitting nothing and the `grep 'a\|b'` alternation.

## Confirmed on device: the dotprod path is live

Not inferred from source — logged by `CPUTranslator.cpp:248` on the Thor:

    LLVM: AArch64 SPU fast paths: mode=native, dotprod=true, i8mm=true, sha3=true
    JIT: LLVM AArch64 target: cpu=cortex-a78 attrs=+sha3,+dotprod,+i8mm,-sve,-sve2

So the video's SDOT/UDOT work is active here, and any A/B against it only needs
the `debug.rpcsx.thor.spu_arm_features` property, not a rebuild.

## Do not put `head -N` on a grep you are about to reason from

Searching for `on_frame_end` call sites with `| head -5` returned five hits from
`texture_cache.h`, none of them the auditor, and the conclusion drawn was "the
auditor is never called". It is called, at `VKPresent.cpp:286` — the line was
just past the cut.

`head` on an exploratory grep is fine. `head` on a grep whose *absence* of a
result you intend to treat as evidence is the same mistake as the alternation
grep, in a new costume. Count first (`grep -c`), then page.


# ARMSX3 0.8 and upstream RPCS3, third pass, 2026-08-16

ARMSX3 is at `62d8208c7`, release **0.8** of 2026-08-15. That is **27 commits**
after `e10f846`, which the second pass in
[`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) used. Upstream RPCS3 is
at `ffc50905a`.

**Nothing below is ported, and nothing below is measured on the device.** Each
item says what was checked and how.

## The `cortex-a78` pin now has a second reason

ARMSX3 vendored an LLVM patch, `3rdparty/llvm/armsx3-aarch64-ghc-emergency-spill.patch`
(`b5a715adc`). AArch64 `determineCalleeSaves` returns early for
`CallingConv::GHC`, so a GHC function never gets a scavenging frame index. That
is safe only while GHC functions have no frame. When the allocator spills, the
function gets real stack objects, `eliminateFrameIndex` needs a scratch register
to build an offset, and GHC has reserved nearly every GPR. LLVM then aborts the
whole module with `Cannot scavenge register without an emergency spill slot`.
The PPU recompiler emits `ghccc` for every guest function, so one bad function
costs the module, and its functions fall back to an interpreter loop.

Their note records the trigger set exactly. It needs `ghccc`, **and** `-O2`,
**and** a scheduling model that pushes pressure over the line. It reproduces on
`cortex-x1`, `cortex-x2`, `cortex-x3` and `cortex-a55`. It does **not** reproduce
on `cortex-a76`, `cortex-a78` or `generic`.

**This fork pins `cpu=cortex-a78`, so it is on the safe side of that list.** The
pin now carries two load-bearing reasons: SVE codegen, recorded above, and this.
Anyone who changes the LLVM CPU name inherits both. Do not port the patch while
the target stays `cortex-a78`; do read this row before changing the target.

## The event stream already bounds `WFE` here, and nothing checks it

`rx::wait_for_event()` at `rx/include/rx/asm.hpp:474` emits `sevl / wfe / wfe`,
and the comment above it records a **measured park of 72,024 ns** set by the
architected event stream at about 100 µs. So the video table's `FEAT_WFxT` row is
correct about a *programmable per-wait timeout* and wrong if anybody reads it as
"`WFE` cannot be bounded here". The event stream is the bound, and this fork
measured it.

**The premise is unchecked.** `rx/asm.hpp` states that Linux and Android arm the
stream. `HWCAP_EVTSTRM` appears **nowhere** in `rpcs3/util/sysinfo.cpp`, whose
`getauxval` family covers `ASIMD`, `SHA3`, `ASIMDDP`, `I8MM`, `SVE` and `SVE2`.
ARMSX3 added `utils::has_wfe_event_stream()` for exactly this (`5ef731c9e`), and
records that the stream is a kernel property and not an architectural guarantee.
On Thor the stream is on — `evtstrm` is in the cpuinfo list in "The machine" — so
the premise holds on this device, and it is untested on any other.

And the fork does not depend on the stream today. The one call site,
`RSXFIFO.cpp:751`, sits behind `thor_rsx_fifo_park_enabled()`
(`debug.rpcsx.thor.rsx_fifo_park`), which is **default 0 and unmeasured**.

## ARMSX3 hardened the RSX semaphore wait; ours is still the plain spin

The site is `nv406e::semaphore_acquire`. Ours calls
`rx::spin_on_cacheline_once(sema, sema.load(), 100)` at `nv406e.cpp:94`. Theirs
spins 500 iterations, then falls back to `wait_for_event()` (`002a9b274`,
hardened twice afterwards at `5ef731c9e` and `b29810d1a`).

**Check the premise before porting this.** Their stated cause is **Oryon**, the
Snapdragon 8 Elite class, where `WFE` returns immediately while the exclusive
monitor is armed. The armed wait degrades to a spin there at tens of millions of
iterations per second. **This device is 8 Gen 2, not Oryon**, and `asm.hpp:461`
already measures an armed `WFE` parking for 72 µs on it. The defect they fixed
may not exist on this chip.

This is the `busy_wait` trap in a new costume: a fix aimed at another core class,
taken without asking whether this core has the problem. Two fixes for one problem
multiply, and that one dropped Thor to about 1 FPS.

## Two upstream ARM64 commits are absent, checked by content

Dated by finding the code, never by `rpcs3_version.cpp`:

| commit | date | what it adds | evidence it is absent |
| --- | --- | --- | --- |
| `5e8ba021a` | 2026-07-26 | SPU/ARM64 RawSPU MMIO, 403 lines: `GPR(context, index)` accessors and `decode_a64_mem_inst` | our `rpcs3/util/Thread.cpp:1215-1227` defines `RIP` only, and has no `GPR` macro |
| `d7ed328f4` | 2026-08-01 | `vm::writer_lock` deadlock fix: sets `cpu_flag::wait` across the `hack_alloc` recovery paths | our `hack_alloc` at `Thread.cpp:1481` has no `added_flag` |

The file is the right one in both cases: it holds `handle_access_violation` at
1237 and `hack_alloc` at 1481. `vm::writer_lock` is **4.49%** of the gameplay
profile and one of the four spin layers, so the second row is worth reading.

**Already present, so nobody re-ports it:** `b35e4434a`, "SPU LLVM: Add
`spu_thread::state` check in Reduced Loop", is at `SPULLVMRecompiler.cpp:2779-2783`.
It is adapted to the RPCSX `spu_ptr<u32>(OFFSET_OF(...))` idiom, which is why a
search for upstream's exact text misses it.

## One of the three-way audit's defects is now closed on their side

[`three-way-audit.md`](docs/arm64/three-way-audit.md) records the x86
float-to-int saturation correction, applied on AArch64, as a defect that lives in
the other two trees and is fixed here. ARMSX3 fixed the PPU half on 2026-08-13
(`87ccdb851`). Nothing to port. Narrow that row to upstream RPCS3.

## Do not port 0.7-era renderer work

ARMSX3 shipped a new renderer in 0.7 and reverted it in 0.7.1 on the same day
(`4797ad8a9`, `8ee20d91d`). They then returned to the 0.6 path and kept only the
FIFO idle fix and ADPF (`0819f1ef1`). Read that sequence before taking any VK
commit from the 0.7 range.

## Read but not yet examined

Listed so the next pass resumes rather than restarts:

* `dbbb6fbde` — VK extended dynamic state, to collapse pipeline permutations.
* `b82432c79` — native fp16 on Adreno drivers that accept it. It **deletes** 203
  lines of `device.cpp`.
* `d069a55ac` and `614bf8b71` — a lost surface becomes recoverable, and Android
  re-delivers the Surface. These aim at the README's "launching a second game
  after closing the first can fail".
* `cce09dbb3` — SPU recovers from a failed analysis, and the log floods stop.
* `7f54855b7` — an lv2/vm read-only unlink lockup, and three log floods.

# `_rpcsx_surfaceEvent` leaks an ANativeWindow reference, and that blocks a fix

**Found by reading, on 2026-08-17, while porting ARMSX3's Surface re-delivery.
Not yet fixed, because the fix cannot be validated without the device.**

`ANativeWindow_fromSurface` **returns a reference the caller owns** and must
release. `_rpcsx_surfaceEvent` treats it as borrowed:

```cpp
auto newWindow = ANativeWindow_fromSurface(env, surface);   // ref 1, owned by us
auto prevWindow = g_native_window.exchange(newWindow);
if (newWindow != prevWindow) {
    ANativeWindow_acquire(newWindow);                        // ref 2
    if (prevWindow) ANativeWindow_release(prevWindow);       // releases prev once
}
```

Both paths leak. A **different** window ends holding two references where one is
released later, and an **identical** window skips the block entirely while the
`fromSurface` reference is never dropped at all.

Today it is bounded, because the surface changes rarely.

**It is what stops the real fix.** `SurfaceHolder.Callback::surfaceChanged` is a
one-shot: Android delivers it on create or resize and never repeats it. A single
missed delivery parks `getNativeWindow()` forever, which is a black game area at
~0% CPU for the rest of the session, and rotating the device only appears to fix
it because a configuration change forces a fresh `surfaceChanged`. ARMSX3 fixes
this by **re-delivering the surface on attach and on every window visibility
change** (`614bf8b71`), relying on the native side to no-op when the window
matches.

On this tree that no-op is the leaking path, so the fix would leak a window
reference **per delivery** instead of once per session.

**Order of work: fix the refcounting first, then port the re-delivery.** The
correct shape is to let `g_native_window` own the `fromSurface` reference, drop
the extra `acquire`, and release the incoming reference when the window is
unchanged. That is a lifetime change on the render surface, where a mistake is a
use-after-free rather than a leak, so it wants a device and a
rotate/background/resume cycle before it is trusted.

The diagnostic half is already in: the wait loop now says
`Still waiting for a Surface after N ms` every three seconds, so the silent
version of this failure cannot recur.

# The syscall log flood was the UE3 slowness, and it is measured

**449,180 RPCS3 lines in one logcat buffer**, taken while Transformers ran its
Unreal Engine 3 HD-cache install. On Android a log line is a syscall plus IPC, and
this install is thousands of file operations back to back, so the logging cost
more than the work it described.

| lines | message |
| --- | --- |
| 119,107 | `Failed to lock sudo memory` |
| 119,083 | `sys_memory_allocate` |
| 118,789 | `sys_memory_free` |
| 31,743 | `sys_fs_stat` |
| 8,846 | `sys_fs_close` |
| 8,203 | `sys_fs_open` |
| 4,434 | `sys_fs_unlink` |
| 2,191 | `sys_fs_rename` |

All demoted to trace, or reported once per session for `lock_sudo`. **Measured
after: 1,836 lines over three minutes** of boot and install on Transformers: War
for Cybertron, which reached its title screen at 24.80 FPS with no `Fatal signal`
and no Scudo OOM at 459% CPU.

**Two traps in doing this.** Allocation and free come in pairs, and so do open and
close: the first pass fixed one side of each and halved the flood rather than
stopping it. And `sys_fs_close` builds its string under `if (sys_fs.warning)` and
prints later, so the GATE has to move with the level - leaving it would pay
`fmt::format` on every close and print nothing.

**Do not port ARMSX3's flood list and stop.** Their four (`sys_fs_utime`,
`sys_fs_fcntl`, `sys_mmapper` map/unmap, `vm::lock_sudo`) contained **none** of
this tree's top four. The floods that matter here had to be counted here.

## Open: 436 `sys_memory_free` failures in three minutes

With the floods gone, the largest remaining entry is
`'sys_memory_free' failed with CELL_EINVAL`, 436 of them in three minutes.

`sys_memory_free` returns `CELL_EINVAL` when the address is not 64 KB aligned, or
when `sys_memory_address_table.addrs[addr >> 16]` holds nothing. The two internal
callers in `sys_memory.cpp` free an address they have just registered, so they
cannot be the source - this is the **guest** freeing addresses the table does not
know about.

Benign engine behaviour or a tracking bug is undecided, and it cannot be decided
from the code: it needs the addresses logged and checked against what was
allocated. Do not "fix" it before that.

# What the log-flood fix is actually worth, measured both ways

**Built the pre-flood commit (9b48b5130) and the fixed tree, installed each, and
booted Transformers: War for Cybertron from the same ISO to the same title screen,
sampling at the same offset (~t+290 s), screen awake, back to back.**

| | baseline | fixed |
| --- | --- | --- |
| RPCS3 log lines at t+290 s | **19,848** | **2,060** |
| guest CPU total | 50.7% | 50.0% |
| PPU / SPU / RSX | 10.1 / 37.2 / 3.3 | 9.9 / 36.9 / 3.2 |
| host CPU, 5 samples | 371 437 407 448 492 | 425 388 429 462 489 |
| FPS, single sample | 29.69 | 30.49 |

**The log reduction is real and large: 9.6x at the same point.** The CPU figures
are identical within noise.

**The FPS difference is NOT a result.** Three further samples of the fixed arm ten
seconds apart gave **27.23** with guest CPU at 72.6%, so that arm alone spans
27.23-30.49. The title screen animates - the planet rotates and debris moves - so
it is not a steady scene, and the 29.69 vs 30.49 gap sits inside one arm's own
range. Reporting it as +2.7% would have been the retraction pattern this file
already records twice.

**So: the fix removes 90% of the log volume at zero CPU cost, and does not move
frame rate on a post-install title screen.** That is consistent with where the
flood actually was - the 449,180-line buffer was captured during the UE3 HD-cache
INSTALL, which is thousands of file operations back to back and happens once. The
user's report of the title being unusably slow was during that phase.

**What would resolve a frame-rate claim:** Folklore, per the ledger, and the phase
gate - accept only 3,500-frame windows, interleave the arms, and read ranges
rather than single samples. A capped, animated title screen cannot answer it.

# A Thor with its screen off cannot boot a title

**Measured 2026-08-18, and it cost most of an A/B session.** A scripted boot sat
at 3.7% CPU with the renderer reporting
`Still waiting for a Surface after 534000 ms`. Nothing was wrong with the
emulator. The device had gone to sleep during a long adb session, so the window
was never laid out, and `dumpsys activity top` showed it plainly:

    net.rpcsx.GraphicsFrame{... 0,0-0,0 app:id/surfaceView}

A `SurfaceView` measured 0x0 never creates a surface, so `surfaceChanged` never
fires and `getNativeWindow()` blocks for the rest of the session.

**Before that log line existed this was indistinguishable from a hang** - black
screen, no output, and a plausible story about a missed one-shot delivery ready to
be believed. Check the display before diagnosing anything:

    adb shell dumpsys power | grep mWakefulness=
    adb shell svc power stayon true     # before any unattended arm

# Eternal Sonata's opening cutscene cannot resolve an A/B

Ten consecutive CPU samples of ONE arm, thirty seconds, no setting changed:

    503 496 518 111 159 148 151 144 185 129

That is 1.1 to 5.2 cores busy within a single arm. The cutscene has phases, and
the phase decides the number. This is the same wall the ledger already records -
"Eternal Sonata CPU cannot resolve anything below ~1.4 cores" - reached from a
different direction, and it rules the cutscene out as an A/B scene entirely.

**Use Folklore.** The ledger says it resolves 0.005 cores and is the title to A/B
on, and nothing since has contradicted that. A number taken from an Eternal Sonata
cutscene is noise wearing a result's clothes, which is how two findings were
retracted here in one day.

# Diagnosing a boot: what the log will and will not tell you

**A failed boot used to report its reason to a dialog and nowhere else.**
`RPCSXActivity` called `RPCSX.boot()` and, on failure, showed an AlertDialog and
called `finish()`. Over adb that is indistinguishable from a hang: the activity
starts, the surface is created and destroyed inside 50 ms, and the log holds three
surface events and nothing else.

That cost a session on 2026-08-17. Three titles were read as "boot accepted but
silently does nothing", and a Surface delivery bug was hunted that did not exist.
The result is logged now, success and failure both, so the first line of a capture
answers "did it boot".

**Two harness facts worth knowing before scripting a boot:**

* `THOR_DEBUG_BOOT` with `--ez thorRequireManagedProfile true` **refuses any title
  without a recommended settings profile**. Eternal Sonata has one; Transformers,
  Tales of Symphonia and BLUS30126 do not. Pass `false` for a diagnostic boot, and
  read the accept or reject line before believing anything that follows.
* `MSYS_NO_PATHCONV=1` fixes Git Bash rewriting **device** paths, and breaks
  **local** ones in the same command. `adb install` needs a Windows path for the
  APK while `adb shell` needs the guard for `/storage/...`. Scope it, do not export
  it for the whole script.

# 8.3 GB of installed data had no library entry at all

`dev_hdd0/game` on this device, 2026-08-18:

    BLUS30357  4.6 GB     BLUS30126  3.7 GB
    BLUS31172_INSTALL_TOSRATATOSK  1.5 GB     BCUS98147  30 MB

**BLUS30357 and BLUS30126 are not in `games.json`.** Their 8.3 GB is orphaned: no
library entry, and deleting a game never touched it anyway - that path removes
`game.info.path` when app managed, plus `cache/cache/<titleId>`, which is only the
compile cache.

For a disc game these are simply different places. The title writes to the virtual
hard disk while it runs; the library entry is the ISO. Drawer > **Installed game
data** lists them with sizes and deletes one on confirmation. Saves are not in
there - those are `dev_hdd0/home/<user>/savedata` - so a delete costs a reinstall
and cannot lose a save.

Not everything under that folder is a title: `$locks` is emulator bookkeeping.
Entries whose name does not begin with a title id are listed without a Delete
button. The test is a **prefix**, because `BLUS31172_INSTALL_TOSRATATOSK` is real
game data.

# The upstream texture series of 2026-08-14..17, and why almost none of it is ours

Upstream landed 16 commits on the RSX texture cache, `ffc50905a..f9f88aa9e`, 511
insertions over 12 files. It was reported as a GPU improvement. **Three commits
came here. The rest should not, and this section is why, so nobody re-derives it.**

## Taken (`bf60895ea`)

* `f9f88aa9e` — a real bug. `uvec4(floor(...))` on a **negative** float is
  undefined, and `round_to_8bit()` feeds it an `fma` result that can go negative.
  Both the fp32 and the native fp16 forms are fixed. Per fragment, and `max()` is
  free next to what surrounds it.
* `26782525f` — depth shrinks with every mip level. This tree used the base depth
  for every level, so `get_texture_size()` overstated every mipmapped 3D texture.
* `5e2d0eb76` — border texels pad the mip dimensions. **Order matters**: this was
  written on top of `26782525f`, and taking it alone against this tree's older
  base would compute the wrong size. They go together.

## Not taken: the performance half has no reach here

The performance work is host-side mipmap scanning for 3D textures (`7e35f5999`,
191 lines) and the one-line commit that enables its fast path (`107b751a4`). It
runs only for a texture that is **both 3D and mipmapped**.

`debug.rpcsx.thor.tex3d_reach` measured it. Eternal Sonata, title screen and
menus, 2,700 frames:

    total=12950  3d=0  3d_mipmapped=0  cubemap_mipmapped=0

**Not one 3D texture in 12,950 uploads.** Gameplay is still unsampled; if it
agrees, this half is inert on this title.

`970d74581` looks general from its title — "respect mip levels actually used" —
and is not. Its only call sites are `generate_cubemap_from_images` and
`generate_3d_from_2d_images`, so the same two counters cover it, and both read 0.

## Not taken: two "general fixes" repair a feature this tree does not have

`4475671bb` lets `process_framebuffer_resource_fast` take an offset. Two later
commits then fix what that broke:

* `9a4b84926` scales the offset when src and dst bpp mismatch.
* `6f5f198ac` adds a cyclic-ref check "since we now allow offsets".

This tree's call site passes **no offset at all**, and `scaled_offset` appears
zero times in its `texture_cache_helpers.h`. It also already performs the
cyclic-ref barrier those commits restore. **Predating the feature means predating
its bugs.** Porting either one would be meaningless at best.

## The porting cost, if the reach answer ever changes

A trial 3-way merge resolves to 40 conflicts over five files, which reads as
tractable and is not. A partial application failed to build with **102 errors of a
different kind**: 50 `cannot initialize object parameter of type rsx::thread`, 18
`override hides virtual member function`, 16 `vk::texture_cache is an abstract
class`. Upstream changed the texture cache's **virtual interface**, so files with
no conflicts at all stop compiling. It is a cross-cutting refactor of the VK
backend, and it collides with this fork's `can_sample_linear` logic in
`VKDraw.cpp`, where there is no side to pick.

**Conflict count does not see interface changes.** That is the lesson worth
keeping.

# `rsx_log.always()` does not reach logcat. `rsx_log.error()` does.

**Measured 2026-08-17, and it cost a build and a boot.** A new counter logged
through `rsx_log.always()` printed **nothing** across 20,750 frames, while the
property it was gated on read `1` and the string was confirmed present in the
shipped `.so`. Every static check passed and the instrument was silent.

Switching the same line to `rsx_log.error()` made it print immediately, on the
first frame.

`always` is level 0 in `util/logs.hpp`, commented "cannot be disabled", so the
header says it is the *most* visible channel. On this device's Android log sink it
is the least. Do not reason from the enum.

**Use `rsx_log.error()` for anything you intend to read back over `adb`**, which
is what `thor_rsx_auditor` already does - and that working precedent was sitting
in the tree the whole time.

This is the `vm_log` entry in a new costume, and the cost was the same shape: a
silent instrument was nearly read as a zero result. The one-shot unconditional
log is what separated them, and it should have been the first move:

    static bool s_reported_once = false;
    if (!s_reported_once) { s_reported_once = true; rsx_log.error("alive: gate=%d", gate); }

Put it OUTSIDE the gate, so a false gate cannot silence the message that reports
the gate.

# Prove which binary the device is running, before you measure anything

**The app can load a dev-core override instead of the core in the APK.**
`files/dev-core/active-core.json` names a library, and the app loads that one.
An `adb install` then changes nothing that runs.

On 2026-08-16 this cost a full boot. The override pinned a 1.35 GB library from
**2026-07-17**, built from a different working copy
(`Documents\New project 6\rpcsx-ui-android\`). A freshly built APK was installed
and verified by `lastUpdateTime`, the title was booted, and the result was read
as evidence about a change that never executed.

`lastUpdateTime` proves the APK arrived. It does not prove the core ran. Only one
thing does:

```sh
adb shell run-as net.rpcsx.easy cat /proc/<pid>/maps | grep librpcsx-android
```

The bundled core answers `/data/app/.../lib/arm64/librpcsx-android.so`. An
override answers `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`.
**Read that line before the run, not after it.**

To disable an override without destroying it, rename `active-core.path` and
`active-core.json`. `tools/build_push_thor_core.ps1 -ResetToBundled` also deletes
the library itself, which is not recoverable if the checkout that built it has
moved on.

This is the version-banner trap in a third costume. The banner lied about the
build, a property can be absent from the `.so`, and now the whole library can be
the wrong one.

# ADPF is written, gated at runtime, and compiled out

`thor_adpf_rsx_hint.h` is complete. It dlsym's the `APerformanceHint_*` family,
gives ADPF a real 30 FPS deadline for Eternal Sonata, and reports the miss signal
as well as the headroom signal. When it is compiled in it reads
`debug.rpcsx.thor.adpf_rsx` and **defaults to off**, so the property alone
decides.

It is not compiled in. `CMakeLists.txt:19` defaults `RPCSX_THOR_ADPF_RSX_HINT` to
`OFF`, and `build.gradle.kts:219` passes that default explicitly.

**That last part is the cost.** The flag is always in the CMake argument list, so
turning it on changes the argument string, which changes the `app/.cxx` hash, which
means **a fresh 8-11 GB tree and a full native rebuild** - not a re-link. Budget
for that before flipping `-PrpcsxThorAdpfRsxHint=1`, and read the disk warning in
"Every distinct CMake flag combination costs 8-11 GB" first.

Worth doing once, because after that build the experiment is one property and no
rebuild. ARMSX3 shipped ADPF and kept it through a full renderer revert, which is
weak evidence that it earns its place. Unmeasured here.

# Build the probe, do not take the number

**A number from outside this repo is a reason to test, never a result.** ARMSX3
measures on their device, upstream measures on x86, and a vendor manual measures
nothing at all. Nine of nine manual-derived predictions here were refuted.

**Write the throwaway program. It is cheap and it is allowed.** The precedent is
already in `tools/`: `bench/thor_bench.cpp`, `aes_arm64_bench.cpp`,
`bcax_bench.c`, `read_ctr_el0.c`, `rdata_equiv.c`. Results go in
[`bench-results.md`](docs/arm64/bench-results.md).

Three shapes, cheapest first, all covered in "Test an acceleration theory outside
the app first" above: read the codegen, model the two forms and diff them, or run
a static binary on the device. None of them needs an APK, a boot, or a thermal
gate.

**Two open questions that each want one small program:**

* Does `vkGetFenceStatus` really block on Turnip and Adreno 740? A commit already
  landed on ARMSX3's 14.6 ms figure. One Vulkan binary that times the call
  against an unsignalled fence settles it, and refutes the commit if they are
  wrong about this driver.
* Is SVE truly absent, or only unreported? `HWCAP` and the JIT log agree it is
  absent, and Qualcomm disabled SVE2 across this generation. A static binary that
  executes one SVE instruction under a `SIGILL` handler turns that into proof.

# The audit ledger

[`docs/arm64/audit-ledger.md`](docs/arm64/audit-ledger.md) tracks the
codebase-vs-manuals sweep: what has been checked, by what method, and what is
left in priority order. Read it before starting another pass, so the sweep is
resumed rather than restarted.

Its central finding is about method. **Sweeping the manual for slow instructions
and hunting for them does not work here** — four predictions derived that way,
four refuted by measurement (`ISB` +23%, `cmp_rdata` 0.3%, UMA upload 8.5
KB/frame, shift-form rewrite identical). **Establishing reach first does work** —
every real defect came from asking whether code runs at all and with what:
`mov_rdata` compiled to nothing, the auditor's `enabled()` is `constexpr false`,
1.88 W was a leaked process.

sse2neon is closed as a concern: `Emu/CPU/sse2neon.h` has exactly **two**
includers, `SPUInterpreter.cpp` (cold, both decoders are LLVM) and
`ProgramStateCache.cpp` (already `vrev16q_u8`).

# Use the manuals

They are vendored in `docs/hardware/` for a reason. Reasoning from memory about
what a chip does, when a 17,145-page manual describing it is sitting in the
repo, has produced wrong answers in this project more than once. Open them.

**But route the question to the right one.** Measured by counting pages that
mention power/energy/watt:

| document | pages | covers | does *not* cover |
| --- | --- | --- | --- |
| Arm ARM (DDI 0487M.c) | 17,145 | instruction semantics, encodings, system registers | timing, power — none at all |
| Cortex X3/A715/A710/A510 guides | 71-73 each | latency, throughput, **pipe assignment** | power (2 of 73 pages mention it) |
| Adreno Game Developer Guide | 200 | GPU architecture, GMEM, UBWC, **power** (28/200 pages) | CPU anything |
| Snapdragon OpenCL guide | 116 | memory hierarchy, cache line, zero-copy, **power** (24/116) | the Vulkan API surface |

The Arm core guides are timing documents. For a *power* question the Qualcomm
documents are the ones with content, which is the opposite of what I assumed.

## The Adreno guide assumes a driver we are not running

`Thor Vulkan Feature Doctor: gpu='Turnip Adreno (TM) 740'`

**Turnip** is Mesa's open-source Adreno driver, not Qualcomm's. Every proprietary
extension the Adreno guide recommends is absent on this device:

    extension: [missing] VK_QCOM_tile_memory_heap
    extension: [missing] VK_QCOM_tile_shading
    extension: [missing] VK_QCOM_tile_properties
    extension: [missing] VK_QCOM_elapsed_timer_query
    extension: [missing] VK_QCOM_queue_perf_hint

So read that guide for **what the hardware does** and discount its API advice.

**And `VK_QCOM_tile_memory_heap` is closed for a better reason than the driver:
it requires Adreno 840 or newer, and this is an Adreno 740.** Explicit GMEM
allocation is therefore unobtainable on this device by *any* driver — not another
Turnip build, not Qualcomm's proprietary one. Do not go looking; there is nothing
to find. Implicit GMEM already works (Turnip bins and tiles on A6xx/A7xx/A8xx),
and the portable substitute below needs no extension at all.

## Tile memory is available anyway, and unused

The portable route to GMEM is core Vulkan, not a QCOM extension:
`VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT` backed by a
`VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` memory type. This device offers one:

    type 3: DEVICE_LOCAL LAZILY_ALLOCATED   11441 MB

and the emulator **never uses either flag** — the only occurrence of
`LAZILY_ALLOCATED` in the whole VK backend is the diagnostic that printed that
line. Every depth and MSAA attachment is therefore backed by real DRAM even when
it is never sampled outside its pass and never needed to leave the tile.

That is an unexploited hardware capability, it is reachable without the missing
extensions, and the vendor documents it as a power win. It pairs with the
`LOAD_OP_CLEAR` work in [`docs/arm64/adreno-tiler.md`](docs/arm64/adreno-tiler.md).

## A stale process cost 1.9 W

The user reported the device drawing 1-2 W more than the day before.
`tools/thor_power_probe.ps1` with the emulator supposedly stopped:

    system power   : 3.481 W    cores busy (avg) : 3.27 of 8
      A710/A715    : 2.216 cores busy at 2803 MHz

`pidof net.rpcsx.easy` returned empty immediately after `am force-stop`, and a
`net.rpcsx.easy` process was nonetheless alive at **210% CPU** with `ETIME`
showing it had started *after* the force-stop. It respawns. After killing it:

    system power   : 1.598 W    cores busy (avg) : 0.676 of 8

**1.88 W, entirely a leaked emulator process.** Check `top` before trusting
`pidof` after a force-stop, and check power against a known-idle baseline rather
than against memory of yesterday.

# Shared device protocol

**The Thor is shared with another Claude session testing Xbox 360 emulation**
(`jp.xenia.emulator.github.debug`). Both agents install, launch and kill apps on
the same hardware.

Rules, learned by breaking them:

1. **Close the emulator before you start and after you finish.** Not only after.
   A previous session's emulator left running is indistinguishable from your own
   until you check the pid, and it costs real power — a leaked `net.rpcsx.easy`
   was measured at **210% CPU and 1.88 W** while nothing was on screen.
2. **Never force-stop the other session's package.** Xenia is not ours. Check
   what is running before assuming a busy device is your fault.
3. `pidof` is not sufficient after `am force-stop`. The process can respawn on
   its own, and an unreachable adb returns empty exactly like a dead process.
   Confirm with `top -b -n 2 -d 2` (a single `-n 1` sample reports every row as
   0.0% because there is no delta to compute).
4. Battery is shared too. Check the level before starting a long run.
5. **Read the temperature before an arm, and treat a hot device as somebody else's
   run until proved otherwise.** On 2026-08-13 a harness waited to start and watched
   the cores go **47 C to 95 C** without ever launching the emulator. The other
   session had taken the device: Xenia sat at **174-211% CPU**, relaunching on a
   cycle, its memory climbing to 1.0 GB. Any arm taken then measures throttling and
   contention. `tools/thor_spu_compile_claim_ab.ps1` now refuses on both counts, and
   `tools/thor_wait_then_compile_claim_ab.ps1` waits for the device instead of
   competing for it. **Do not force-stop their package**, and do not lower the
   thermal gate to make a run start.
6. **Installing an APK is itself a heat source.** The same device read 38.5 C before
   an install and 50.2 C right after it. That is a transient, like the launch spike
   in `thermal.md`. Poll for the cooldown; do not conclude the device is hot.

# The manual question, settled

The goal text asks for "a snapdragon gen 8 chipset manual that was huge" from
the video. **That manual is the Arm Architecture Reference Manual, not a
Qualcomm document.** The video ("PS3 emulation is fast on ARM now") describes
scouring *"every page of an ARM Architecture manual with over 17,000 pages"*,
and the page count identifies the issue exactly: **DDI 0487M.c is 17,145
pages**. It is vendored, split into three parts.

The Snapdragon SoC-level manual — the SM8550 *Hardware Register Description* —
**is not public**, confirmed from two independent directions: Qualcomm
distributes it to partners, and Lantronix states plainly that HDK schematics and
manuals are available only to purchasers through their technical portal. The
SM8550 data sheet (80-33265-1) surfaces only on Scribd behind a paywall.

What is public and vendored instead covers **every block of this chip**, which
is the useful form of the question. `docs/hardware/README.md` carries the map;
in short, the device reports `ro.soc.model=QCS8550` / `kalama`, and its
Cortex-X3 (3187 MHz), A715/A710 (2803 MHz) and A510 (2016 MHz) clusters, its
Armv9-A instruction set and its Adreno 740 each have a vendored document. The
Arm core guides are not generic material here: those cores *are* the 8 Gen 2.

Two things were found and deliberately **not** vendored. The Snapdragon 8 Gen 2
Product Brief is public, and is two pages of marketing with no technical
content. `docs.qualcomm.com` numbers briefs `87-*` and technical guides `80-*`,
which is why both Qualcomm files here are `80-*`. Padding `docs/hardware/` to
satisfy a checkbox is worse than recording that the real document is gated.

The register description would not help much even if it were public: it
documents SoC peripheral registers for driver authors, while this project writes
userspace on top of Android's drivers and Mesa Turnip. Every finding so far came
from instruction timing, instruction semantics or GPU behaviour.

# Open: the RSX auditor emits nothing

Unresolved, and worth writing down so the next session does not re-derive it.
With `debug.rpcsx.thor.rsx_auditor=1` set before launch and Folklore rendering
at 60 FPS, the auditor produces **zero** lines. Everything checked so far says
it should work:

* `on_frame_end` is at `thor_rsx_auditor.h:857`; the
  `RPCSX_THOR_RSX_EXPERIMENTS` guard at 794 closes at 825, so it is **not**
  compiled out.
* It is called from `VKPresent.cpp:286`, inside `advance_queued_frames()`,
  reached from `queue_swap_request()` at `VKPresent.cpp:1003`.
* The `skip_frame || swapchain_unavailable` mini-flip path that bypasses it
  early-returns at `VKPresent.cpp:588` and does not apply while rendering.
* `looks_disabled("1")` is false and `parse_interval("1")` yields 60, so the
  property is enabled with a 60-frame interval.
* Other `rsx_log.warning` output does reach the log, so the channel works.

The installed APK was confirmed to be the instrumented one
(`lastUpdateTime` after the build). Next step is a one-shot unconditional log at
the top of `on_frame_end` to separate "not called" from "`enabled()` false" —
which is the same technique that cracked `mov_rdata`, and should have been the
first move rather than five rounds of reading.

# The video's optimization list, checked against this fork

Pulled from the source rather than from summaries: the chapter markers of
*"PS3 emulation is fast on ARM now"* (`ytInitialPlayerResponse.videoDetails`,
via `tools/` Playwright). This is the actual list of things it claims, so it is
the actual list to check. Status is what was verified here, not what was assumed.

| # | chapter | status in this fork |
| --- | --- | --- |
| 00:55 | Busy wait shenanigans | covered at length in [`spin.md`](docs/arm64/spin.md); 93% of spin is the GETLLAR wait |
| 06:40 | **Don't use Yield in place of Pause!** | **was wrong here.** `rx::pause()` emitted `yield`, a nop on SMP. Now switchable via `debug.rpcsx.thor.pause_mode`; **unmeasured** |
| 09:32 | What was LLVM doing on ARM? | JIT attrs logged and verified on device: `cpu=cortex-a78 +sha3,+dotprod,+i8mm,-sve,-sve2` |
| 12:45 | How we optimized SHUFB | hand-written lowering already present — see [`codegen.md`](docs/arm64/codegen.md) (`TBL` set) |
| 19:04 | The rest of the instructions | swept: `SQADD`, `URHADD`, `UABD`, fixed-point `FCVTZS` all clean from generic IR |
| 29:46 | The most optimized way to compare data on ARM | `cmp_rdata`/`mov_rdata` — where the empty `#elif` was found; **re-examine the compare now that the copy is fixed** |
| 38:55 | How to play wow optimally | n/a |
| 39:28 | SVE are the *special* vector extensions | **does not apply to this device.** `has_sve()` reads `HWCAP_SVE`, and the Thor's HWCAP does not report it — the JIT log shows `-sve,-sve2` |
| 47:50 | Optimizing RPCS3 with SVE | same: no SVE on this hardware, so both chapters are inapplicable here |
| 54:24 | Optimizing via hardware wait instructions | `WFE` explored (three experiments, [`spin.md`](docs/arm64/spin.md)); `FEAT_WFxT` absent on this chip so `WFE` cannot carry a *programmable per-wait* timeout. **It is still bounded**: `rx/asm.hpp:474` measures an armed `WFE` parking **72,024 ns**, set by the architected event stream. See the third ARMSX3 pass below |
| 55:33 | Lightning round | the sweep table above covers this ground |

Two things this changed. The pause/yield item was a **real defect sitting behind
a TODO** in our own source, and it is the item the video names most explicitly.
And the two SVE chapters — a fifth of the video — are inapplicable to this
device, which is worth knowing before anyone spends a session on them.

Get the chapter list this way rather than from news coverage; the summaries
paraphrase and one of them is what led to the wrong idea that the manual was a
Qualcomm document:

```js
await p.evaluate(() => window.ytInitialPlayerResponse.videoDetails.shortDescription)
```

# Measuring power on the Thor's second screen

The AYN Thor has a secondary display that can show live power draw. That is the
instrument to trust for "is this cooler", because `tools/thor_power_probe.ps1`
degrades badly when USB is attached: adb over USB charges the device, so
`power_supply/battery/current_now` reports charge current rather than system
draw and the probe reports a **FLOOR**, not a figure. Wireless adb plus the
second screen gives a real number.

Reference loads measured this session, so a reading has something to sit against:

| workload | cores busy | probe reading |
| --- | --- | --- |
| idle, emulator stopped | 0.68 of 8 | **1.60 W** (on battery, exact) |
| idle with a leaked emulator process | 3.27 | **3.48 W** |
| Folklore, title screen, 60 fps | 2.23 | not derivable (charging) |
| **Eternal Sonata, gameplay** | **5.26** | 5.5 W floor, USB attached |

Eternal Sonata is the heavy one — 5.26 of 8 cores busy, with 3.18 of those on the
A710/A715 cluster — and a **9 W spike at the wall during it is expected**, not a
fault. Folklore at ~2.2 cores is less than half that load.

If a spike appears with nothing obviously running, check `top` before anything
else: a leaked `net.rpcsx.easy` at 210% CPU accounted for 1.88 W once already,
and `pidof` did not report it after `am force-stop`.

# Where this stands, and the one thing left to build

Everything cheap has been tried. The scoreboard:

| lead | outcome |
| --- | --- |
| lv2 wait spin | **fixed and shipped** — default `lv2_spin=0`, 67.6% CPU cut on a light scene, no latency cost at any percentile |
| `host_mutex_spin` | measured 2.2% on Folklore, ~1% of the lv2 win — **default left at 10** |
| `SPU loop detection: true` | **null** — and consistent with the profile, since the hot loop polls `state`, not a channel |
| SPU affinity widening | **null, and the config block is inert** — see the retraction below |
| ARMSX3 second pass, 2026-08-13 | **four ported, none measured** — the same-item SPU compile claim, two JIT i-cache sites, the GETLLAR out-buffer memo and cap, and a memory budget for the PPU compile workers. The APK is installed and the device was then taken by the other session. See [`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) |
| ARMSX3 third pass, 2026-08-16 | **read, none ported** — 27 commits to release 0.8. The `cortex-a78` pin dodges their LLVM GHC scavenger defect; their RSX semaphore fallback targets Oryon, not 8 Gen 2; two upstream ARM64 commits confirmed absent here. Section above |
| `PMULL` for texture swizzle | correct technique, **cold** — `calculate_z_index` absent from the profile at any threshold |
| exclusive monitor as reservation | **half-viable** — `ERG=64` measured, PS3 needs 128 |
| ARM TME, SVE | **absent from this chip** |

**BUILT 2026-08-13, default off, and unmeasured.** `debug.rpcsx.thor.spu_selfloop_park`
takes the timeout in microseconds; `0`, the default, keeps the spin. `BR` now has a
case for `target == m_pos` and calls `spu_selfloop_park`, which parks on `state`
with that timeout. The record is written **on entry** — `entries`, `last_pc`, then
`exits` — so a watchdog reading `entries - exits > 0` sees a park while it is
happening. That is the record-on-entry slot this file asks for below, and it exists
because parking turns a burning core into a quiet sleeping thread, which is what a
guest deadlock would then look like. See `Emu/Cell/thor_spu_selfloop_park.h`. The
paragraph below is the design it was built from, and it still describes the problem.

**What remains is the SPU self-loop park, and there is no shortcut left to it.**
Roughly 20% of gameplay CPU sits in two instructions — `ldr w8,[x19,#0x14]` /
`cbz w8, .-4` — that spin on `spu_thread::state` with no pause, no yield and no
backoff.

Everything needed to build it is now known:

* **Site:** `SPULLVMRecompiler.cpp:9874`, `BR`, which has no case for
  `target == m_pos`. Detection needs no dataflow analysis.
* **API:** `thread_ctrl::wait_on(state, old, timeout_ns)`, with precedent in the
  same file at `SPUThread.cpp:7907`.
* **Emitting the call:** the `call("name", +lambda, m_thread, ...)` helper, as
  `wait_spu_inbox` does at `SPULLVMRecompiler.cpp:4558`.
* **Hazards, both unresolved:** every writer of `state` must notify or the thread
  sleeps to the timeout, which is why the timeout is mandatory; and `BR`-to-self
  is also what a guest deadlock looks like, so parking makes a hang silent —
  keep a counter or log at the park.
* **Gate:** `debug.rpcsx.thor.spu_selfloop_park`, default off, A/B'd with p95 from
  `dumpsys SurfaceFlinger --latency`.

Two smaller items also remain unmeasured and need no recompiler work: **non-
temporal large DMA** (`LDNP`/`STNP` for the 16 KB transfers) and the **MFC
prefetch oracle**. Both aim at `process_mfc_cmd`, 20% of gameplay.

# Novel hardware acceleration: what is viable, measured on device

Measured, not assumed — `mrs ctr_el0` from a static binary on the Thor:

```
CTR_EL0 = 0x000000049444c004
ERG      = 64 bytes   (exclusive reservation granule)
CWG      = 64 bytes   (cache writeback granule)
DminLine = 64 bytes   IminLine = 64 bytes
```

**The exclusive monitor cannot serve as a PS3 reservation.** The idea was
attractive: `GETLLAR`/`PUTLLC` is load-linked / store-conditional over a 128-byte
line, which is *exactly* what ARM's monitor does natively, while x86 has no LL/SC
at all and forces the seqlock + `mov_rdata` + `cmp_rdata` emulation this fork
carries. It is the one place where AArch64 is structurally **better** suited to the
PS3 than the architecture the emulator was written for.

**ERG is 64 bytes and there is one monitor per core, so it covers half a
reservation.** What survives:

* **A wake source.** `WFE` wakes on monitor loss, so `LDXR` + `WFE` is an
  event-driven wait on half the line — strictly better than the spin that is there
  now, with a timeout covering the other half.
* **A fast negative check.** Monitor lost means something in that 64 bytes
  changed, so the reservation is definitely broken and the 128-byte compare can be
  skipped entirely on that path.

What does not survive: replacing the compare outright. Written down with the
number so the idea is not re-derived a fourth time.

## Two more, and one correction

**The MFC command queue is a free prefetch oracle.** Emulators rarely prefetch
because real hardware does not need to, but the SPU's MFC queue *lists the
addresses the guest is about to touch*. `PRFM` the destination of DMA *n+1* while
transfer *n* runs. Unmeasured, and it aims at `process_mfc_cmd`, which is 20% of
gameplay.

**BUILT 2026-08-13, default off, and unmeasured**, as
`debug.rpcsx.thor.dma_nontemporal = <bytes>`, the size at which the pair loop
takes over. `__movsb` on ARM64 now routes through `thor_dma_copy`, so one gate
covers all six DMA call sites. Whole 64-byte blocks go through `LDNP`/`STNP`; the
remainder goes to `memcpy`, so the tail cannot be got wrong.

**And the premise was checked, because it was wrong.** The comment in
`SPUThread.cpp` claimed bionic's memcpy "uses ldp/stp pairs and non-temporal
stores for large sizes". Read out of the device's own libc: `memcpy` is an ifunc
choosing `memmove_generic` or `memcpy_opt`, and **neither contains `stnp`, `ldnp`
or `prfm`**. `stnp` and `ldnp` appear **zero** times in the entire library, across
146,002 disassembled lines in which `ldp` appears 4,439 times and `prfm` 10 — that
last count is what makes the zero mean something. So nothing downstream was
mitigating the eviction, and the item below is real rather than already-solved.

Verified two ways, because AArch64 code cannot run on this host: the target build
emits exactly `ldnp q0,q1 / ldnp q2,q3 / stnp q0,q1 / stnp q2,q3 / add / add /
subs / b.ne`, and a model of the block-and-tail arithmetic matches `memcpy` over
3,072 cases spanning every residue mod 64 at three start offsets, including the
16 KB size the SPU jobs use.

**Large DMA should be non-temporal.** The comment at `SPUThread.cpp:1108` says
Eternal Sonata "pounds 16 KB transfers", and the bulk path is plain
`std::memcpy`. A 16 KB copy evicts most of L1 and much of L2 — including the
working set of the other five SPU threads sharing those two cores. `LDNP`/`STNP`
and `PRFM PSTL1STRM` exist for this, and `buffer_stream.hpp` already reaches a
real `STNP` elsewhere.

**Correction to the affinity advice: not the A510s.** They share one vector unit
per *pair*, which this repo already measured as AES at 18.9x on X3 against **9.0x**
on an A510. SPU emulation is vector-heavy, so A510s are the worst home for it.
Widen SPU affinity toward CPU3 (A715) and CPU7 (X3, currently running a
single-threaded RSX that costs 2.23%) — never CPU0–2.

## Confirmed dead, so nobody re-derives them

**ARM TME** would make `PUTLLC` a native transaction; it is not in this chip's
feature list. **SVE** is the natural fix for 128 SPU registers spilling onto 32
(10.1% of emitted JIT instructions are spills); this chip does not have it and
upstream's two SVE commits must never be ported. Both are the architecturally
right answer and both are unavailable.

# Every wait in this emulator spins, and only one of them parks

Four layers, found independently from two profiles, all the same shape:

| layer | bounded spin | fallback | share of gameplay |
| --- | --- | --- | --- |
| lv2 syscalls | 50 × 26 µs = **1.3 ms** | futex — a real sleep | 73.9% of a title screen, ~0 in gameplay — **fixed** |
| SPU JIT self-loop | none — bare `ldr`/`cbz` | **none** | **~20%** |
| SPU MFC reservation | 15 × 26 µs = **390 µs** | `sched_yield` forever | ~7% |
| `vm::writer_lock` | 100 × 10.4 µs = **1.04 ms** | `sched_yield` forever | 6.2%, six threads at once |

Only the first had a real sleep underneath, and it is the only one that was
fixable cheaply. The rest end in nothing or an unbounded `sched_yield`, which does
not sleep — it re-queues, keeps the thread runnable, and holds the cluster at a
high operating point regardless of work retired. **Roughly a third of gameplay CPU
is threads waiting, at full issue rate, for something that has not happened yet.**

Detail, insertion points and hazards in
[`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md). The SPU
self-loop site is exact: `SPULLVMRecompiler.cpp:9874`, `BR`, which has no case for
`target == m_pos`.

# Two config-only experiments outrank all of that

**RETRACTED: SPU threads are not pinned to two cores.** This section claimed the
`Affinity` block in `config.yml` (`CPU5: SPU`, `CPU6: SPU`) meant six SPU threads
shared two cores, and built an oversubscription argument on it. **Measured on
device, every emulator thread reports `Cpus_allowed_list: 0-7`** — all eight
cores. PPU threads are unrestricted despite `CPU4: PPU`, which proves the table is
not applied at all under `Thread Scheduler Mode: Operating System`. The Linux
scheduler places these threads; the config block is inert.

The error is the one this file warns about more than any other: **a config value
was read and assumed to take effect.** One `grep Cpus_allowed_list
/proc/<pid>/task/*/status` would have caught it before the claim was written, and
it is the same class as trusting the version banner or a property that never
reaches the binary.

Both experiments built on it came back null, as they had to:

| change | result |
| --- | --- |
| `Affinity` SPU → CPU3 as well (2 cores → 3) | 3.944 vs 3.946 cores — **identical**, and inert anyway |
| `SPU loop detection: true` | 4.029 vs 3.949 cores, frame times unchanged — no effect, and deep inside Eternal Sonata's ~1.4-core noise floor |

`SPU loop detection` failing to help is independently consistent with the profile:
the hot `0xcc4` loop polls `spu_thread::state`, not a channel, and that setting
targets channel/idle loops.

**What survives.** Thread placement is still worth investigating, but through the
**scheduler**, not this config block — and any future attempt must verify with
`Cpus_allowed_list` that the change actually landed. If affinity is ever forced,
avoid CPU0–2: the A510s share one vector unit per *pair*, measured here as 9.0x
against the X3's 18.9x on AES, and SPU emulation is vector-heavy.

The codegen work is therefore **not** obviated. Both cheap escapes are closed.

# Grep the shipped `.so` for the property before every property A/B

One command, before the arms run:

```sh
P=$(adb shell pm path net.rpcsx.easy | sed 's/package://;s/base.apk//')
adb shell "grep -ac 'debug.rpcsx.thor.<name>' ${P}lib/arm64/librpcsx-android.so"
```

It has already caught three distinct silent no-ops in one session, each of which
would have produced a confident number from two identical arms:

1. **An `adb install` that printed `device offline`** and scrolled past. Both arms
   ran the old build; they differed by **1.37 cores, 58%**, purely from
   between-boot variance. Written up unchecked, that is a 37% win.
2. **A gate on `defined(ARCH_ARM64) && defined(ANDROID)` in `rx/asm.hpp`** —
   correct for the rpcs3 translation units that use the neighbouring helpers, and
   silently false for `rx`'s own, which folded the function to a constant.
3. **A gate applied to `rx/src/SharedMutex.cpp`**, which is `EXCLUDE_FROM_ALL` and
   not linked at all; the live `shared_mutex` is `rpcs3/util/mutex.cpp`.

All three compile, link, run, and change nothing. The string in the binary is the
cheapest proof that the code you edited is the code that executes — the same rule
this file already states for the version banner, applied to properties.

# Before acting on anything a manual says

Nine manual-derived predictions were measured on this project and **nine were
refuted**. The manuals were right every time; the reasoning on top of them was
not. Full analysis in [`docs/arm64/audit-ledger.md`](docs/arm64/audit-ledger.md).
The four failure modes, as a checklist to run before writing code:

1. **Did I read the adjacent rows?** The shift rewrite assumed immediate shifts
   were wider than register shifts. Both are `V13`. One extra row would have
   killed it before any work.
2. **Am I reading the right core?** This is big.LITTLE with three guides. The
   whole narrow-pipe sweep quoted Cortex-X3 while the code runs on A715, where
   the same instructions are narrower still. Check where the thread is pinned
   (`config.yml` Affinity) before picking a guide.
3. **Is the manual actually recommending this, or am I inferring it?** A guide
   states what an instruction costs on the chip. It cannot know whether the code
   is hot, what contends for the pipe, or what was tuned around the current form.
   `ISB`: the manual was right that `YIELD` is a nop, and the swap still cost
   **23%** because the spin counts were calibrated around a cheap instruction.
   `BCAX`: `V0` throughput 1 is real and it still **wins by 5.6%** because it
   replaces two operations.
4. **Have I established reach before optimality?** `cmp_rdata` looked critical at
   10,093,915 calls; those calls existed only because of a deadlock later fixed.
   Ask "does this run, and how often, on the workload that matters" first.

And the two attribution traps that produced confident wrong answers:

* **Nearest-symbol attribution is not heat.** An `inline` function emitted into
  many translation units becomes the nearest preceding symbol over large address
  ranges in a partly-stripped binary. ~31% of samples "in"
  `get_thor_pause_mode` were an artifact.
* **A histogram of a JIT dump counts what was compiled, not what runs.** 3,946
  `ldsetal` in one module looked alarming; they are one per function entry, on a
  path guarded by a likely-branch.

**The rule:** a manual row is a hypothesis about the chip, never a conclusion
about the code. Answer the two questions the manual cannot — *is this hot* and
*what is it competing with* — then measure on device. The device has overruled
the table nine times out of nine.

# Write the hypothesis down before touching the device

Twelve optimisation attempts here were refuted or retracted. **Eleven had no
predicted effect size.** That is the single cheapest thing to fix, and it costs
nothing but a minute of thinking.

Before any experiment, state four things. If any cannot be answered, the answer
is not "run it and see" — it is that the experiment is not ready.

1. **Mechanism.** What physically gets cheaper, in one sentence.
2. **Predicted magnitude, as a number.** Not "faster" — a percentage or a
   millisecond count, with the arithmetic. Most bad experiments die here: AES
   interleaving is a real 4x on the primitive, and `aes.md` already measured the
   total volume at 13.6 MB / ~35 ms of boot, so the prize is ~26 ms. Written
   down, it is obviously not worth doing.
3. **What already bears on this in the repo.** Almost every failure below was
   answerable from something already present — a code comment, a filename, an
   existing measurement — and was not looked at.
4. **What result would falsify it**, and what confound would fake a win.

## The twelve, and the prior that would have killed each

| attempt | prior question | where the answer already was |
| --- | --- | --- |
| `ISB` for `YIELD` (+23%) | was surrounding code tuned around current behaviour? | **the comment at the site said the spin counts were hand-tuned with YIELD** |
| `cmp_rdata` tree (0.3%) | still hot after the bug I just fixed? | the profile; the 10M calls were the deadlock |
| UMA direct upload (8 KB/frame) | what is the byte volume? | one counter, no code change |
| AES 4x interleave | how many bytes total? | `aes.md`: 13.6 MB, ~35 ms |
| shift rewrite (identical) | read the adjacent table row | the same page |
| `pause()` guard (no change) | is nearest-symbol valid for an `inline` function? | it never is |
| `LOAD_OP_CLEAR` (no saving) | does Turnip already fold this? | Mesa is open source |
| cortex-a710 ×2, jit A/B (artifacts) | does changing this invalidate a cache? | **the cache filename contains the CPU name** |
| GETLLAR busy-wait (−2.9%) | 93% of *spin* — but how much of *total* is spin? | the profile |

**Retrieval was not the problem.** The right manual row was found every time.
RAG or embeddings over the manuals would have helped with exactly one of these —
reading the X3 table for work that runs on A715 — and that is a routing rule
("which core is this thread pinned to?"), not a search problem.

## The two habits that produce fake wins

* **A large result is a bug until proven otherwise.** Three "wins" of +24%, +92%
  and −24% were all phase mismatches. Verified gameplay on this title sits at
  13,352–14,624 Mcyc/s at ~5.2 cores busy; anything far outside that band is
  measuring a different program state, not a faster one.
* **Check cores-busy across arms before reading the headline number.** It caught
  all three. If the arms differ by more than a few percent there, the comparison
  is void regardless of what the summary says.

# The SPU self-loop park has no reach on Folklore's title screen

**Measured 2026-08-18, and it closes an item this file carried as "built, default
off, and unmeasured" since 2026-08-13.**

The park counters now print. `perf_monitor` appends them to its own periodic line,
which already reaches `RPCSX.log`:

    SPU self-loop park: entries=0 exits=0 parked_now=0 last_pc=0x00000

**Nine PERF lines, nine zeros**, with `debug.rpcsx.thor.spu_selfloop_park=100`, the
property read back from `getprop`, and the format string confirmed in the shipped
`.so`. The report fires and counts nothing, so the SPU never branches to itself on
this scene. The `BR target == m_pos` case is never reached.

**Before this, the counters had no reader.** `thor::g_spu_selfloop_park` was written
at `SPULLVMRecompiler.cpp:10093-10098` and read by nothing; the string "selfloop"
appeared in exactly two files in the tree. So the record-on-entry slot this file
asks for existed and could not be read, and a lever with no reach was
indistinguishable from a lever with no effect. That is the same shape as `vm_log`
emitting nothing, and it is now fixed.

**The 20% figure is Eternal Sonata gameplay, not a title screen.** Nothing here
contradicts it. It says only that Folklore's title screen cannot test it, so any
future arm on this lever needs a gameplay scene.

## The A/B that ran first, and the control that killed it

The park was A/B'd before the counter existed. Six interleaved arms, 60 s windows,
every arm at 7200 frames:

| arm | SPU ticks | process total | frames |
| --- | --- | --- | --- |
| park 0 | 576, 582, 588 | 1886, 1832, 1854 | 7200 each |
| park 100 | 556, 567, 574 | 1825, 1873, 1866 | 7200 each |

The ranges do not overlap - 576-588 against 556-574 - which reads as **-2.8% SPU
thread CPU at no frame cost**. It is not a result.

**A control pair with both arms at 0 gave 561, 575, 565, 571, 573.** That spread is
14 ticks, the same size as the 16-tick "effect", and it straddles both arms. The
counter then said `entries=0`, so there was never a mechanism.

**This is the third time this exact shape has been retracted here**, and the second
at the number 2.8% - the SPU branch lane extract was reported at 2.8%, made the
default, and withdrawn. Run the control before believing a separation under 5%.

# Measure the thread the change lives in, not the process

`tools/thor_thread_ab.sh` A/Bs one property and reports **per-thread** CPU, summed
over a thread-name prefix. `tools/thor_phase_gated_ab.sh` measures the whole
process, which is right for a change that touches every thread and wrong for one
that touches a single thread.

Folklore's title screen, in one 60 s window:

| | ticks | share |
| --- | --- | --- |
| process total | 1823-1890 | 0.30-0.35 cores |
| `SPU[0x0000100]` | 561-592 | ~31% of the process |
| `rsx::thread` | 252-323 | ~15% of the process |

The process total spread for one fixed setting is about 60 ticks. A change confined
to `rsx::thread` can therefore halve its own thread and stay inside the process
noise. Name the thread.

The tool takes a **prefix**, so `SPU[` sums every SPU thread, and it prints the
matching thread count. A boot with a different thread count is not comparable, and
the count is what says so.

# Traps found while measuring on 2026-08-18

* **The frame delta is quantized to 300.** The `tex3d_reach` probe reports every
  300 frames, so every frame count is a multiple of 300. "Exactly 3600 against
  exactly 7200" is the reporting granularity, not a deterministic result. Do not
  read the roundness as strength.
* **`tex3d_reach` is a free frame counter.** It prints `over N frames` through
  `rsx_log.error()`, which this device flushes, so an A/B needs no build flag and
  no SurfaceFlinger parsing to count frames.
* **The screen and the charger heat the device with the emulator stopped.**
  `svc power stayon true` plus USB charging held the CPU junction at 81-82 C for 40 s
  of idle, with nothing running and the battery at 26 C. It is neither a launch
  transient nor an artifact of reading the sensor.
* **Tell a hot sensor from a real throttle with `scaling_max_freq`.** At 82 C the
  A710/A715 cluster read `scaling_max_freq=2707200` against
  `cpuinfo_max_freq=2803200`, a 3.4% cap, while CPU7 stayed uncapped at 3187200.
  The frequency cap is the throttle; the temperature is only its cause.
* **A bare max over `thermal_zone*` reads the wrong sensor.** All zones gave 63400
  in the same minute that `cpu-1-*` gave 84300. Read the `cpu-1-*` junction zones.
* **Widening the frame band lets a compile arm through.** A control arm passed a
  3000-7600 band at 6000 frames while burning **6874** ticks against a normal 1850.
  It was still compiling. The tight 6800-7600 band would have rejected it.
* **The USB serial died mid-session and came back `unauthorized`.** The network
  transport kept working throughout. Set `THOR_SERIAL=192.168.1.33:5555` rather
  than restarting the session.

# The lv2 spin win, re-measured on 2026-08-18 with a second instrument

**This is the largest ARM64 performance property in the build, and it now has an
independent confirmation.** The original measurement used cores-busy and reported a
67.6% saving. This one counts scheduler ticks per thread, on a different build,
months later, with the arms interleaved.

Folklore, title screen, 60 s windows, every accepted arm at **7200 frames** and
**16 PPU threads**:

| `debug.rpcsx.thor.lv2_spin` | PPU thread ticks | process total | frames |
| --- | --- | --- | --- |
| **0** - this fork's default | **520** | **1824** | 7200 |
| 50 - upstream behaviour | 4426 | 6003 | 7200 |
| 50 - upstream behaviour | 4591 | 5937 | 7200 |

**Upstream's spin costs 8.5x the PPU thread CPU and 3.3x the process CPU for the
same 7200 frames.** The saving is **69%**, which agrees with the 67.6% already
recorded here.

**The ranges cannot be argued with.** Fifteen accepted default arms across the whole
session, over four separate experiments, put the process total between **1823 and
1890**. The two upstream arms are **5937 and 6003**. Nothing overlaps, and the
separation is 3.2x against a control spread measured the same day at 14 ticks.

**The frame count is the guard.** A CPU number alone cannot tell a thread that
stopped spinning from an emulator that stopped working. Every arm here rendered
exactly 7200 frames, so the CPU came off the spin and not off the work.

The hotter arms are the upstream ones - 64.6 C and 66.2 C against 59.0 C. That is
the consequence of burning three times the CPU, not a confound, and it pushes the
upstream arm in the direction it already lost.

# What this session did NOT establish

Said plainly, because this file records retractions beside claims:

* **No new optimization was found.** The number above is the fork's existing
  default, re-verified. It is not work done on 2026-08-18.
* **`spu_selfloop_park` gained nothing**, and now cannot on this scene - the counter
  reads `entries=0`.
* **`rsx_fifo_park` is still unresolved.** With the park on, `rsx::thread` spent
  267-285 ticks against 252 with it off, from one sample of the off arm. If
  anything that is worse, and it is not established either way. The default stays 0.
* **A mid-session claim that the park halved the frame rate was wrong and is
  withdrawn.** Two boots at park=1 read 3600 frames while twelve at park=0 read
  7200, which looked decisive. Four more boots at park=1 then read 7200 three times.
  The 3600 readings were the attract-movie phase this file already documents, and
  the phase gate is what exposed the error.

# Folklore's title screen has two steady states, and one of them starves the RSX

**Profiled on device 2026-08-18. This is the mechanism behind the phase scatter
this file has fought for weeks.**

One 60 s window, same title, same build, same settings:

| state | process ticks | frames | `rsx::thread` ticks |
| --- | --- | --- | --- |
| light | 1823-1890 | 7200 | 256-283 |
| starved | 6876-6879 | 6000-6300 | 5985 |

**The starved state costs 3.7x the CPU and delivers FEWER frames.** `rsx::thread`
sits at 5985 ticks per 60 s, which is 99.75% of one core.

A 24,208-sample profile of the starved state, 0 lost:

| | share |
| --- | --- |
| `rsx::thread` | **89.13%** of all cycles |
| kernel | 81.71% |
| `librpcsx-android.so` | 3.95% |
| `sched_yield`, self | 5.79% |

**Every single `sched_yield` sample is on `rsx::thread`** - 1,295 samples, 100%
self. That is the `FIFO_EMPTY` branch at `RSXFIFO.cpp:756` calling
`std::this_thread::yield()` while the guest fails to feed the ring. The RSX starves
and burns a whole core doing it.

The light state, 9,365 samples, is a different program:

| thread | share | | object | share |
| --- | --- | --- | --- | --- |
| `SPU[0x0000100]` | 40.35% | | JIT code (unnamed) | 42.19% |
| `PPU[0x1000000]` | 24.04% | | `librpcsx-android.so` | 25.07% |
| `rsx::thread` | 16.31% | | kernel | 17.10% |

**Read the state before reading any arm.** The 185-ticks-over-1750-frames against
1720-over-3500 pair this file records is these two states, not random scatter. The
frame count identifies which one: 7200 per 60 s is light, 6000 is starved.

# `rsx_fifo_park` is not a win, and the default stays 0

**Measured 2026-08-18 across about twenty boots.** The property replaces the
`sched_yield` spin above with eight `rx::pause()` calls and then
`rx::wait_for_event()`.

In the light state it is a small, consistent **regression**:

| `rsx_fifo_park` | `rsx::thread` ticks | frames |
| --- | --- | --- |
| 0 | 256, 257 | 7200 |
| 1 | 281, 283 | 7200 |

That is +10% on the thread, +1.4% on the process, and the ranges do not overlap.
The FIFO is rarely empty here, so the park pays its cost and buys nothing.

Under induced starvation - seven spinner processes taking the cores away from the
guest, identical in both arms - the park does bound the spin, and it also breaks:

| arm | `rsx::thread` ticks | frames |
| --- | --- | --- |
| park 0 | 3863 | 4200 |
| park 0 | 3691 | 4200 |
| park 1 | 1083 | 5100 |
| park 1 | **2200** | **2700** |

The last row is the problem. **2700 frames is the worst throughput measured in the
whole session**, and it came from the park. That is the wake latency ARMSX3
records: ouroboros420/rpcsx parked bare here (`e31ef44ef`) and reverted it
(`832c23078`) because it cost frame-time smoothness. This tree reproduced their
result independently.

**So the park trades a bounded worst case for an unbounded frame cost, and neither
side is reliable.** It stays off. A change that fixes the starve without the wake
latency has to keep short idles spinning - raise the eight-spin threshold far
enough that only sustained starvation parks - and that is unbuilt and unmeasured.

# `dma_nontemporal` is closed by arithmetic, not by an experiment

The light-state profile puts `memcpy_opt` at **5.19%** of cycles, which is the
reach this lever needs and the first time it has been measured. Then
[`bench-results.md`](docs/arm64/bench-results.md) supplies the other half: the
non-temporal copy is **3.1% faster at 16 KB**.

3.1% of 5.19% is **0.16% of cycles**. The control spread on this device is several
percent, so the experiment cannot resolve its own prediction. Do not run it.

This is the rule about writing the predicted magnitude down first, working exactly
as intended: two numbers already in the repo killed a lever in one line of
arithmetic and cost no device time.

# simpleperf needs `run-as` on this device

`perf_event_paranoid` is 1 and `setprop security.perf_harden 0` does not change it,
so `simpleperf record -p <pid>` fails with `Permission denied` on `cpu-cycles`.
Run it as the app instead, which a debuggable build allows:

    adb shell run-as net.rpcsx.easy /system/bin/simpleperf record \
      -p <pid> --duration 25 -f 1000 -g -o /data/data/net.rpcsx.easy/perf.data

The shipped `.so` is stripped, so symbols inside it come back as
`librpcsx-android.so[+offset]`. Thread, DSO and kernel attribution all work
without symbols, and that was enough to find the starve.

# The adaptive FIFO park was built, measured, and does not work either

`debug.rpcsx.thor.rsx_fifo_park_after = <polls>` parks the RSX only after that many
CONSECUTIVE empty-FIFO polls, and keeps `std::this_thread::yield()` below the
threshold. It was built on 2026-08-18 to separate the two idle shapes the bool form
cannot: a brief idle between frames, and the sustained starve that burns a core.

**It does not fix the starve.** Induced starvation, seven spinners, 45 s windows,
threshold 1024:

| arm | `rsx::thread` ticks | frames |
| --- | --- | --- |
| off | 867, 898 | 4800, 4800 |
| after=1024 | 952, **3895**, 944 | 4800, **4200**, 4500 |

One arm starved **with the park engaged** and still burned 3895 ticks, which is 86%
of a core over the window.

**That is the useful part of the result.** If the thread had reached
`rx::wait_for_event()` and parked, it could not have spent 86% of a core. So either
the event-stream wait does not sleep under this load, or the starve is not the
`FIFO_EMPTY` branch in that instance. `rx/asm.hpp:461` measures an armed `WFE`
parking 72,024 ns on an idle device; nothing has measured it on a loaded one, and
these numbers say the idle figure does not carry over.

**Do not build a fourth park before settling that.** The next step is a counter on
the park branch - taken, and time spent - so "the park ran and slept" can be told
from "the park never ran". Every park variant so far has been argued from a wait
that was never confirmed to sleep, which is the same shape as the counters that
could not be read and the log channel that produced nothing.

The property stays default 0, so nothing changes by default. It is kept for the
same reason the bool form is kept: the negative should stay reproducible.

# A real sleep parks the RSX where WFE did not, and it still trades frames for CPU

**The third park form, built and measured 2026-08-18.** `rsx_fifo_park_us` sleeps
for a bounded time instead of calling `rx::wait_for_event()`, after
`rsx_fifo_park_after` consecutive empty polls. Counters on both, printed by
`perf_monitor`.

**The sleep works where WFE did not.** At `after=1024, us=100`, under induced
starvation, `rsx::thread` fell from **839-870 ticks to 437-497** over a 45 s
window, with no overlap. The `wait_for_event()` form left one arm burning 86% of a
core. So the earlier failure was the wait, not the idea.

**And it costs frames, at every setting tried.** Seven arms each at
`after=8192, us=20`, the best configuration found:

| | `rsx::thread` ticks, sorted | frames |
| --- | --- | --- |
| off | 624, 843, 852, 857, 864, **3737, 3757** | 3900, 4200, 4800, 5100 x4 |
| parked | 631, 685, 740, 780, 1612, 1627, 1639 | **4200 x4**, 5100, 5400, 5400 |

The park bounds the tail - nothing above 1639 against two off arms near 3750 - and
it lands on 4200 frames in **four of seven** arms against one of seven. Mean frames
4757 off, 4671 parked.

**An n=3 sample of the same configuration read as a win on both axes**, at 685-740
ticks and 5400 frames. Four more repeats reversed the frame half. Three samples
were not enough, and this file now records that twice in one day.

## The conclusion, across five variants

| form | CPU | frames |
| --- | --- | --- |
| 8 x pause then WFE | +10% in the light state | 2700 against 4800 in one arm |
| yield then WFE | no change, one arm at 86% of a core | 4200 against 4800 |
| sleep 100 us after 1024 | -48% | 4200 in two of three |
| sleep 20 us after 8192 | tail bounded | 4200 in four of seven |

**Parking the RSX FIFO on this device trades frames for CPU. It does not make the
emulator faster, and every form stays off by default.**

That may still be worth having for **power** on a handheld, which is a different
question from speed and is not measured here. `tools/thor_power_probe.ps1` and the
second screen would answer it, on battery, with USB detached.

**What is not yet ruled out** is the starve itself. Bounding its cost is not the
same as preventing it. It correlates with heat - the two worst arms of the session
read 74.7 C and 71.9 C - and with contention, and its cause is unknown. That is the
open item, and it is worth more than a sixth park.

# Symbolize against the build that ran, or read the wrong function

**Two wrong symbol readings on 2026-08-18, both caught, both cheap to avoid.**

The shipped `.so` is stripped, so simpleperf reports `librpcsx-android.so[+offset]`.
The unstripped library is in
`app/build/intermediates/cxx/RelWithDebInfo/*/obj/arm64-v8a/`, and resolving the
offset against it is one `llvm-addr2line` call.

**It has to be the SAME build.** An offset from one build resolved against another
names a different function with complete confidence. `0x15e8340` read as
`shared_mutex::imp_lock_shared`, which matched a known unfixed spin in
[`busy-wait-inventory.md`](docs/arm64/busy-wait-inventory.md) and was about to be
acted on. Re-recording against the installed build moved the same hot symbol to
`0x15e8580` and named it `rx::pause()`. The host `simpleperf` says so plainly:

    isn't used because of build id mismatch: expected 0xf952fa61..., real 0xb74402e6...

`--symfs` refuses a mismatched library. `llvm-addr2line` does not, and it is the
one people reach for.

**And the corrected name is still not heat.** `rx::pause()` is `inline` and emitted
into many translation units, so it becomes the nearest preceding symbol over a
large address range in a partly stripped binary. This file already records that
exact artifact for `get_thor_pause_mode` at ~31%. A hot `inline` helper in a symbol
map is a measurement of the symbol table, not of the program.

**So a stripped profile can name a thread, a DSO and the kernel, and it cannot name
a function.** Thread and DSO attribution carried every real finding today; the
function names produced two false leads in a row.

Pulling the record needs `adb exec-out`, not `adb shell`: `adb shell cat` corrupts
the binary and the host tool then reports `invalid attr section`.

# The pause ladder is built and untested against the state it targets

`debug.rpcsx.thor.rsx_fifo_pause_ladder = <N>` spends N-1 of every N empty-ring
polls in `rx::pause()` and yields on the Nth. Default 0 keeps one yield per poll.

It exists because a build-matched 33,850-sample profile of the starved state, 0
lost, is almost entirely syscall overhead:

| symbol | share |
| --- | --- |
| `[kernel.kallsyms]`, one address | 64.84% |
| `[kernel.kallsyms]` | 8.64% |
| `sched_yield` | 5.24% |
| `[kernel.kallsyms]` | 3.89% |
| `rsx::thread::run_FIFO()` | **1.93%** |

The RSX thread's own code is 1.93%. The rest is the kernel servicing a
`sched_yield` per poll. **That reframes the starve: it is not a wait that fails to
sleep, it is a syscall storm**, and every park built before it treated the wrong
half of the problem.

**It is unmeasured against the starve**, because six arms under the stressor all
stayed healthy at 2430-2494 ticks and 4800-5100 frames. The starved state appeared
in 4 of ~14 boots earlier in the session and then stopped appearing. A/B'ing a fix
for a state that will not reproduce measures nothing, so nothing is claimed.

**The next session needs a trigger for the starve before it needs another fix.**
It correlated with heat - the two worst arms read 74.7 C and 71.9 C - and with
contention, and neither reproduces it on demand. The counters are in place to
recognise it (`idle_polls`, `parks`) and `run_FIFO` self time separates it from the
light state in one profile.

# initial-exec TLS is unreachable here, and bionic says so at load time

**Tried and reverted 2026-08-18.** A build-matched profile of Folklore's title
screen, 16,671 samples and none lost, puts **1.29% of all cycles** in
`[linker]tlsdesc_resolver_dynamic`. That is the resolver body alone, so it is a
lower bound: every dynamic TLS access also pays the call around it.

The cause is the default. A shared library gets `global-dynamic` TLS, which on
AArch64 means TLSDESC and a call into the linker on each access. The emulator core
is full of `thread_local` state - 17 in `util/Thread.cpp`, 5 in `SPUThread.cpp` -
reached from the hottest paths in the program.

`-ftls-model=initial-exec` does apply, and the relocations prove it:

| build | `R_AARCH64_TLS_TPREL64` | `R_AARCH64_TLSDESC` |
| --- | --- | --- |
| initial-exec | **132** | 3 |
| default, restored | 0 | 135 |

**And the library then does not load:**

    dlopen failed: TLS symbol "(null)" in dlopened ".../librpcsx-android.so"
    referenced from ".../librpcsx-android.so" using IE access model

bionic refuses the initial-exec access model for a library brought in by `dlopen`,
and `System.loadLibrary` is a `dlopen`. **This is a platform rule, not a budget a
smaller TLS footprint would satisfy.** The note is in `CMakeLists.txt` at the place
someone would add the flag.

**It fails loudly, which is the one good thing about it.** The app does not start,
so this cannot be mistaken for a working build or measured as a win. Compare the
`mov_rdata` class of defect, where the code compiled to nothing and ran for months.

The 1.29% is real and stays on the table. What would reach it is fewer dynamic TLS
accesses on the hot path - caching a `thread_local` load in a local across a hot
loop - not a build flag.

**Cost of finding this out: two full native rebuilds, 17 and 16 minutes.** Changing
a compile option recompiles every object. The `.cxx` tree is keyed on the CMake
ARGUMENT list, so editing `CMakeLists.txt` does not spawn a second 8-11 GB tree -
only a new `-D` flag would.

# CORRECTION: the frame count does not pin the scene

**Stated earlier in this file, and wrong.** The section above says Folklore's title
screen has two steady states and that 7200 frames per 60 s identifies the light
one. Measured across about forty boots on 2026-08-18, the process total at
**exactly 7200 frames** falls in two separate clusters:

    1823 1825 1832 1844 1845 1854 1866 1873 1873 1886 1890
    2662 2687 2703 2703 2708 2717 2717 2724 2750 2750 2809

Same title, same frame count, same 49-66 C band, same JIT target
(`cpu=cortex-a78`, read from the log, not assumed). The gap is about **46%** and
there is nothing between the clusters.

**The extra ticks are not in `rsx::thread`.** That thread reads 256-330 in BOTH
clusters. The difference is in the SPU and PPU threads, so it is the guest doing
more work, not the renderer. No change to the FIFO code can produce it, and the
one that was suspected did not: replacing three guarded statics with load-time
inline variables left the cluster exactly where it was.

**So there are at least three states, and frames identify none of them.** Use the
process total to classify an arm, not the frame count:

| state | process ticks / 60 s | frames |
| --- | --- | --- |
| light | ~1850 | 7200 |
| middle | ~2710 | 7200 |
| starved | ~6876 | 6000 |

**Every A/B in this session survives this**, because the arms were interleaved and
each run landed wholly in one cluster. That is what interleaving is for. **Absolute
numbers from different runs are not comparable**, which is the rule this file
already states for temperature drift, now with a second cause.

# ADPF is compiled, measured, and does nothing here

`-PrpcsxThorAdpfRsxHint=1` builds it; `debug.rpcsx.thor.adpf_rsx` switches it at
runtime, so **one build serves both arms**. Confirmed in the shipped `.so` by both
the property string and `APerformanceHint_createSession`.

**First run, thermal gate at 88 C - and void.** ADPF looked like a 15% cut on
`rsx::thread`, 328-381 against 316-323, with the ADPF arm far steadier. The arms
ran at 63-90 C and the process totals sat at 2799-2832, well above the 1823-1890
seen all session. Throttling inflates CPU-time ticks, so that was the thermal
drift.

**Second run, gate at 60 C, four repeats:**

| `adpf_rsx` | `rsx::thread` ticks | process total | frames |
| --- | --- | --- | --- |
| 0 | 326, 279, 331, 327 | 2662, 2724, 2703, 2717 | 7200 |
| 1 | 273, 330, 334, 329 | 2703, 2717, 2750, 2709 | 7200 |

**Everything overlaps.** No effect on this scene. The default stays off, and the
CMake option stays `OFF` so nobody pays 8-11 GB of `.cxx` for it.

ARMSX3 keeping ADPF through a renderer revert is still the reason to try it on a
scene that is GPU bound and frame limited. A 60 fps title screen is neither.

**Set the thermal gate near the idle temperature, not near the limit.** 88000 was
chosen so arms would not block, and it let a 90 C arm through. The device idles
around 40-50 C after a rest, so 60000 is reachable and 88000 measures the throttle.

# SHIPPED: `host_mutex_spin` defaults to 0, and it is the lv2 defect one layer down

**Changed 2026-08-18 after measuring it twice.** `shared_mutex::imp_lock_shared`
spun 10 times before using the futex under it, and each spin is `rx::busy_wait()`
at the x86 default of 3000 cycles. On this device's **19.2 MHz** generic timer that
is 156 µs per iteration, so the mutex burned **1.56 ms of `YIELD` - a nop on this
SMP core - in front of a futex that works**.

That is exactly the lv2 wait defect, in the same codebase, one layer down: a spin
count tuned in x86 cycles applied to a timer 170 times slower.

Folklore title screen, 60 s windows, arms interleaved, thermal gate at 60 C, every
arm at **7200 frames**:

| `host_mutex_spin` | process ticks per 60 s | range |
| --- | --- | --- |
| 10, the old default | 2650, 2681, 2684, 2703 | 2650-2703 |
| 0 | 2629, 2637, 2638, 2612 | **2612-2638** |

**The ranges do not overlap** and the saving is **1.9%**. It agrees with the
earlier measurement in
[`busy-wait-inventory.md`](docs/arm64/busy-wait-inventory.md) - 0.377, 0.377, 0.378
cores at 10 against 0.370, 0.368 at 0 - which is the same 1.9% from a different
instrument on a different build. That run also recorded **p50, p95 and p99 frame
time at 16.87 ms in BOTH arms**, so the latency this default guarded against was
measured and is not there.

**Verified after shipping, with the property unset**, which is the only thing that
proves a default: 2587, 2634, 2648, 2641, 2631, 2651, mean **2632**. Explicit `0`
means 2629; the old `10` means 2679. The shipped binary behaves like 0.

`debug.rpcsx.thor.host_mutex_spin = 10` restores the old behaviour.

**Why it was left at 10 before, and why that is now resolved.** The earlier note
called it "0.008 cores on one light scene" and kept the latency guard. The guard
costs 1.9% of all CPU on the scene where it was measured, the percentiles say it
buys no latency, and two independent measurements agree on the size. Frame count
is identical in every arm, so the CPU came off the spin and not off the work.

# The battery fuel gauge is frozen on this device, so wattage is not remote

**Measured 2026-08-18, with the USB cable detached and `USB powered: false`** -
the condition this file says is needed for a real figure rather than a floor.

    current_now    = 0          (constant)
    voltage_now    = 4270960    (constant)
    charge_counter = 4649084    (constant)
    status         = Discharging

`charge_counter` did not move over **60 s idle** or over **120 s of Folklore
rendering at 7200 frames per 60 s**. A delta of 0 uAh is not a low reading, it is
no reading: at the ~1.6 W this file records for idle, 60 s should consume about
6250 uAh.

So on this device **all three of the obvious nodes are dead**, and the earlier
warning that USB charging turns `current_now` into a charge current is the smaller
half of the problem. Detaching USB does not make the gauge report.

**The AYN Thor's second screen stays the only trusted power instrument**, and it
needs somebody to look at the device. A wattage claim cannot be produced over adb
here.

**Use CPU as the proxy, and say so.** Less CPU for the same frame count is less
energy for the same work, which is sound, but it is an inference and not a
measurement. Do not convert a tick saving into watts.

# The Adreno LOAD_OP_CLEAR fold: correct, CPU-neutral, and its win is unmeasurable here

**Measured 2026-08-18.** `debug.rpcsx.thor.loadop_clear` folds a full-surface clear
into the render pass load op instead of issuing `vkCmdClearAttachments` inside the
pass. On a tiler that is the difference between reading the whole attachment from
system memory into GMEM and then throwing it away, and **not touching memory at
all**. The Adreno guide calls the clear-after-load pattern the most-cited mobile
GPU mistake.

**Reach was already measured and is total:** 51 of 51 clears eligible on the title
screen, and 60 of 60 colour-plus-depth on the rendered scene. This is not a lever
looking for a workload.

**It renders correctly.** Folklore's title screen with the fold on: a clean frame
at **60.00 FPS**, overlay reading PPU 2.8%, SPU 1.3%, RSX 1.0%, Total 5.2%. No
corruption, and the frame is in the session capture.

**And it is CPU-neutral**, which is what it should be. Three interleaved repeats,
thermal gate at 60 C, every arm at 7200 frames:

| `loadop_clear` | `rsx::thread` ticks | process total |
| --- | --- | --- |
| 0 | 304, 331, 332 | 2608, 2639, 2631 |
| 1 | 327, 327, 277 | 2566, 2622, 2661 |

Everything overlaps. **A CPU tick counter cannot see this change**: the saving is
GPU memory traffic, not host cycles.

**Two explanations fit that result equally and this device separates neither:**
the win is real and invisible to the CPU, or Turnip already folds the
clear-after-load internally so there is nothing left to win. Deciding it needs a
GPU counter or a wattage reading, and the fuel gauge on this device does not
report.

**So it stays default 0.** It is verified correct on ONE title. The remaining work
is a power reading from the second screen with the property on against off, and a
correctness pass over more titles - not more CPU A/Bs, which have now been shown
to be the wrong instrument for it.

# RETRACTED the same day: `host_mutex_spin = 0` does not replicate

**Shipped and reverted on 2026-08-18.** The claim above - 1.9% less process CPU
with non-overlapping ranges - was real for the run that produced it and does not
survive two further tests.

| test | 10 | 0 | verdict |
| --- | --- | --- | --- |
| `busy-wait-inventory.md`, cores | 0.377, 0.377, 0.378 | 0.370, 0.368 | favours 0 |
| CPU ticks, 4 pairs | 2650-2703 | 2612-2638 | favours 0 |
| CPU ticks, **quiet device**, 3 pairs | 2614-2685 | 2584-2646 | **overlap** |
| **energy proxy**, 7200-frame arms | 48487, 48506 | 48574, 49468 | **favours 10** |

**Two for, two against, and the energy proxy is the one that matters most for a
handheld.** The default returns to 10.

**Spinning here is not dead code, which is why the sign can flip.** A spin in front
of a block avoids a futex syscall and a context switch whenever the lock is
released quickly. That is the entire reason spin-then-block exists, so 0 trades one
cost for another and the winner depends on the contention pattern. This is NOT the
lv2 case, where the spin sat in front of a wait that was already going to sleep.

**And the first two runs were contaminated.** See below: twelve orphaned stressor
processes were loading the device at ~430% CPU. Interleaving means the comparison
still stood, but it is a second reason not to trust the pair.

# Twelve orphaned stressors ran for hours, and interleaving is what saved the session

`tools/thor_rsx_starve_ab.sh` starts spinner processes on the device and kills them
at the end of each sample - **device-side**. When adb dropped mid-arm, and when the
script was killed from the host, that kill never ran.

Found by `top` while investigating why the device would not cool below 55 C with
the emulator stopped: **twelve `yes` processes owned by `shell`, about 430% CPU**,
junction at 86.7 C. They had been running for hours, through the ADPF, the
`loadop_clear` and the `host_mutex_spin` arms.

**Every comparison in that window survives, because the arms were interleaved and
both saw the same background load.** That is precisely what the interleaving rule
in this file is for, and this is the first time it has actually been needed.
**Absolute numbers from that window do not survive.**

The script now sweeps on entry and traps `EXIT INT TERM`, and the spinners are
named `yes` so `killall` can find them. The rule generalises: **a harness that
loads a shared device must clean up from the HOST side, on any exit path**, because
the device-side cleanup is exactly what a dropped link skips.

**It did not explain the bimodal totals.** Killing all twelve left the light state
at ~2600 ticks, not the ~1845 of earlier in the session, so the two clusters
recorded above remain unexplained and the correction stands: classify an arm by its
process total, and never compare absolute numbers across runs.

# Hardware acceleration: the surface is swept, and native fp16 was the last open one

**Verified on device 2026-08-18**, from the boot log rather than from source:

    RSX: GPU/driver supports float16 data types natively.
         Using native float16_t variables if possible.
    RSX: ** Using VK_KHR_shader_float16_int8

So the Adreno guide's largest shader-side power item is **already taken**. Turnip
exposes `shaderFloat16`, and `device.cpp:129` accepts it - the only force-disable
is AMD Vega on the LLVM emitter. ARMSX3's `b82432c79`, listed above as "read but
not yet examined", removes 203 lines of `device.cpp`; it is cleanup around a path
this tree already has on, not a capability this tree is missing.

The full picture, so nobody re-sweeps it:

| capability | state |
| --- | --- |
| `SDOT`/`UDOT` (asimddp) | taken, `+dotprod` in the JIT log, gated on HWCAP |
| `SMMLA`/`UMMLA` (i8mm) | taken, `+i8mm` in the JIT log |
| `BCAX` (sha3) | taken, `+sha3`, used by SPU `EQV` and both `SHUFB` paths |
| ARMv8 AES | fixed - was `#if __SSE2__`, now 19-22x on the primitive |
| LSE / LSE2 128-bit atomics | live and verified in the build cache |
| `TBL`/`TBX`, `URHADD`, `SQADD`, `FCVTZS` | emitted from generic IR, verified |
| **native fp16 shaders** | **taken - verified in the boot log, this section** |
| tiler `LOAD_OP_CLEAR` | implemented, correct, and neutral - Turnip folds it |
| **`LAZILY_ALLOCATED` tile memory** | **the one genuinely unexploited item** |
| SVE / SVE2 / TME | absent from this chip, and must never be ported |

**One item is left and this device cannot measure it.** Transient attachments
backed by `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` keep depth and MSAA in GMEM
instead of DRAM. The saving is memory bandwidth and therefore power, and **the
battery gauge here does not report**, so neither CPU ticks nor the cpufreq proxy
can see it. It needs the second screen.

# CLOSED: `LAZILY_ALLOCATED` tile memory is inapplicable, not merely unimplemented

**Checked 2026-08-18, and this removes a standing open item from the ledger.**

The idea was sound and is recorded above: `VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT`
on a `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` type keeps depth and MSAA in
Adreno's on-chip GMEM instead of DRAM. This device offers such a type - `type 3:
DEVICE_LOCAL LAZILY_ALLOCATED 11441 MB` - and the backend never uses it.

**It cannot use it.** A transient image on lazily-allocated memory may have **no
backing store at all**, so it can only ever be an attachment. Every RSX render
target in this backend is created with more than that:

    VKRenderTargets.h:233  colour  |= COLOR_ATTACHMENT | TRANSFER_DST | SAMPLED
    VKRenderTargets.h:302  depth   |= DEPTH_STENCIL_ATTACHMENT | TRANSFER_DST | SAMPLED
    VKRenderTargets.h:237/241/306   += TRANSFER_SRC, STORAGE where needed

**`SAMPLED` is not decoration, it is the emulator.** A PS3 game can read a surface
it just rendered as a texture, and the texture cache does exactly that. Remove the
readback and the emulation is wrong; keep it and the image is ineligible for
lazy allocation.

The only attachments in the backend without `SAMPLED` are the **swapchain images**
(`swapchain.cpp:10, 355`), and those must be presentable, which lazily-allocated
memory is not.

**So the one remaining unexploited hardware capability on this chip is unexploitable
without changing RSX render-target semantics.** That is a redesign of surface
lifetime, not an optimisation, and it would have to prove readback still works
before it could claim a single byte. Do not open this again on the strength of the
memory-type dump alone; the usage flags are the binding constraint.

**With this closed, the hardware-acceleration sweep is complete**: every applicable
accelerator on this silicon is in use, and the two that are not - SVE/SVE2 and TME -
are absent from the chip.

# CORRECTION: the RSX thread does not live on the prime core

**Sampled six times on 2026-08-18, two seconds apart, on a booted title:**

    rsx::thread last_cpu = 3, 4, 3, 3, 3, 6

That is the **A715/A710 mid cluster**, not CPU7. `Cpus_allowed_list` is `0-7` for
every thread, so the scheduler is choosing, and it is choosing the mid cluster.

Two places said otherwise and both were one sample. This file states "CPU7 (X3,
currently running a single-threaded RSX that costs 2.23%)", and a reading earlier
in this session found `last_cpu=7` once and nearly became an affinity experiment on
the strength of it.

**`last_cpu` is where a thread ran most recently, not where it lives.** One read of
it is worth exactly as much as one boot, which this file already warns about for
conclusions and now warns about for samples.

**So there is no big.LITTLE placement win here.** The obvious power argument -
a light renderer thread holding the prime core awake - does not apply, because it
is not on the prime core. Any future placement work must start by sampling
`last_cpu` repeatedly, not once.

# The cpufreq energy proxy is insensitive, and it was checked before it was trusted

**Built and invalidated on 2026-08-18, in that order.** With the battery gauge dead,
`tools/thor_energy_proxy_ab.sh` summed cpufreq residency times frequency per
cluster as a stand-in for energy. Then it was run against a lever whose effect is
already known to be enormous - `lv2_spin` 0 against 50, which is upstream behaviour:

| `lv2_spin` | process ticks / 60 s | energy proxy |
| --- | --- | --- |
| 0 | 2612, 2710 | 48554.8, 48582.8 |
| 50 | **6339, 6465** | 48601.7, 48759.0 |

**A 2.4x rise in CPU moved the proxy by 0.2%.** The instrument cannot see a 140%
change, so it cannot see a 2% one, and every null it produced is a silence rather
than a result.

The cause is in the counter. `time_in_state` accrues wall-clock residency at each
frequency whether the core is busy or idle, so over a fixed window the total is
nearly fixed; on a frame-capped scene the governor lands on much the same
frequencies either way. It measures the governor, not the work.

**This invalidates one leg of the `host_mutex_spin` revert.** That revert cited the
proxy as "favouring 10"; that reading is void. **The revert still stands on the
other leg**, which is CPU ticks on a quiet device: A(10) 2706-2955 against B(0)
2592-2806 over three pairs, heavily overlapping. Unresolved is unresolved, and an
unresolved default does not ship.

**The rule this session nearly broke is the one already written here**: confirm an
instrument produces output before believing its silence. `vm_log` wrote nothing,
`rsx_log.always()` reached no sink, three counters had no reader - and now a proxy
returned a number every time and still could not see a 2.4x effect. **A live number
is not a working instrument.** Validate against a known-large effect first.

# Gameplay cannot be reached over adb, which is why the big levers stay unmeasured

**Tested 2026-08-18.** Folklore boots to "Press START button" and stays there.
`adb shell input keyevent BUTTON_START` leaves the emulator running and the
workload unchanged - 852 process ticks over 20 s against 871 before the key - so
the event never reaches the emulated pad. RPCSX takes input through its own path,
not through Android key events routed into the guest.

Sending more keys is worse than useless: `BUTTON_START` then `ENTER`, `BUTTON_A`
and `DPAD_CENTER` **killed the process**, because those reach the Android UI
instead.

**This is the root blocker behind most of this session.** The levers with the
largest documented reach all live in gameplay:

| lever | reach | where |
| --- | --- | --- |
| SPU self-loop park | ~20% of CPU | gameplay - `entries=0` on a title screen |
| MFC DMA / `process_mfc_cmd` | 20.13% | gameplay profile |
| `vm::writer_lock` | 4.49% | gameplay profile |

A title screen is 0.3-0.4 cores at a 60 fps cap. Every remaining lever moves less
than the scatter there, which is why eight variants in one session all came back
unresolved or void.

## Three input paths tried, all verified, none reaches the guest

| path | delivered? | guest reacted? |
| --- | --- | --- |
| `input keyevent BUTTON_START` | yes, app stayed alive | no - 852 ticks against 871 |
| `input keyevent ENTER/BUTTON_A/DPAD_CENTER` | yes | **killed the process** - they reach the Android UI |
| `sendevent /dev/input/event9` BTN_START (0x13b) | **yes, confirmed by `getevent`** | no |
| `sendevent` BTN_SOUTH / cross (0x130) | yes | no - screenshot still reads "Press START button" |

The gamepad node is real and writable: `/dev/input/event9`, `"Odin Controller"`,
`crw-rw---- root input`, and shell is in group 1004 (`input`). A capture taken
while injecting shows the events arriving:

    [ 656955.867266] 0001 013b 00000001     <- EV_KEY BTN_START press
    [ 656956.923582] 0001 013b 00000000     <- release

**So the events reach the kernel and the emulated pad still does not see them.**
Whatever RPCSX binds to, it is not satisfied by an injected event on that node.
Do not repeat these three; the next attempt should look at how the Pad Thread
acquires its device, not at another way of faking a button.

**So an automated A/B session can measure a title screen and nothing else.** To A/B
a gameplay lever somebody has to drive the game to a save point by hand and leave
it in a steady scene. That is the highest-value tooling gap here, and it is worth
more than another lever.

# The JIT's under-declared CPU features are worth nothing, checked off device

**Checked 2026-08-18 in seconds, with no boot.** This file records that
`cpu=cortex-a78` is Armv8.2, so features this chip has are never offered to LLVM:
`lrcpc`, `flagm`, `flagm2`, `frint`, `fcma`, `sha512`. That reads like free
performance left on the table.

It is not. The shapes the translators actually emit - PPU `FCTIW`, SPU `CFLTS` and
`CFLTU`, a truncating convert, and a flag-heavy compare chain - were compiled at
three targets:

| target | accel instructions | total | assembly |
| --- | --- | --- | --- |
| `cortex-a78` | 0 | 24 | baseline |
| `cortex-a78+flagm+fp16fml+fcma` | 0 | 24 | **byte-identical** |
| `cortex-a715` (the real core) | 0 | 24 | identical |

No `frint32`, `frint64`, `rmif`, `setf`, `fcmla` or `fcadd` is selected at any
target. LLVM does not reach for these instructions from this IR, so declaring them
changes nothing, and the `cortex-a78` pin costs no codegen here.

**That is ten manual-derived predictions refuted out of ten.** The pattern holds
exactly: the manual is right that the silicon has the feature, and the inference
that the compiler will therefore use it is wrong. Read the codegen before changing
the target - it is one `clang -S` and it settles the question without a device.

**With this the accelerator surface is fully closed.** Everything applicable is in
use, the GPU items are neutral or inapplicable, and the feature list is inert.

# What `ppu_budget_mb` is worth: 21% off precompile, and why the default still stands

**Measured 2026-08-18 on the first heavy, reproducible, input-free workload found
on this device.** The property existed with its cost documented and its benefit
never measured. Now it has a number.

Folklore, PPU cache cleared before every arm so the work is identical, metric is
the emulator's own timestamp at the 15th `LLVM: Compiled module`:

| `ppu_budget_mb` | seconds to compile 15 modules | temp |
| --- | --- | --- |
| 0, the default (1536 MB) | **61.71, 60.63** | 81.1, 82.7 C |
| 4096 | **49.24, 47.49** | 94.0, 94.4 C |

**About 21% faster, and the ranges are nowhere near each other.** The raised arms
ran 12 C hotter because more cores are actually compiling; throttling pushes that
arm slower, so the saving is if anything understated.

**The default does not change, and the reason is in the source next to it.**
Raising this makes the Scudo abort MORE likely: Scudo caps each size class at
256 MB regardless of free RAM, so more concurrent compiles means more simultaneous
allocations in one class, and BLUS30126 already dies there with `SIGABRT` in
`PPUW.1.1` while 11.4 GB of 15.6 GB is free. A fifth off the load time is not worth
a title that will not boot.

**So this is an opt-in with a known price**, and it is now a quantified one:

    adb shell setprop debug.rpcsx.thor.ppu_budget_mb 4096

Worth setting for a title that already precompiles cleanly, and worth clearing the
moment one does not. Transformers (BLUS30357) is the strongest candidate - its
modules estimate at 1,677,721,600 bytes against the 1536 MB default, so it is the
title this file records as fully serialized at ~103% CPU.

# `tools/thor_precompile_ab.sh`, and why precompile is the workload to use

**This is the answer to "there is no measurable workload on this device."** A title
screen is 0.3-0.4 cores at a 60 fps cap and gameplay cannot be reached over adb.
Precompile needs no input, saturates the compile workers, and repeats **exactly**
the same work once the cache is cleared.

It also self-times: the emulator stamps `LLVM: Compiling module` and
`LLVM: Compiled module`, so the metric is its own clock and does not depend on how
often the harness polls.

The clear runs through `run-as`, because the cache tree is `drwxr-s---` and shell
cannot unlink there, and the script checks the **postcondition** - a file count of
zero - rather than the exit status of the `rm`. This repo has been fooled by an
`rm` that silently did nothing.

**Use it for any lever that plausibly touches compile throughput, allocation or
host locking.** It resolved `ppu_budget_mb` at 21% in four arms, where the title
screen could not resolve anything in eight attempts. It also closed
`host_mutex_spin` for the third time: 59.18 and 60.22 seconds at 10 against 59.64
and 66.70 at 0.

## CORRECTION, same day: the 21% does not generalise, and Transformers is the proof

The section above measured `ppu_budget_mb=4096` at 21% off Folklore's precompile and
recommended Transformers as the best candidate, because its modules estimate at
1,677,721,600 bytes and it is the title recorded here as fully serialized.

**That recommendation was wrong.** Same harness, same 15-module metric, cache
cleared before every arm, on BLUS30357:

| `ppu_budget_mb` | seconds | temp |
| --- | --- | --- |
| 0, the default | 77.40, 67.86 | 87.1, 87.9 C |
| 4096 | 73.68, **94.23** | 93.6, 94.4 C |

**The ranges overlap and the slowest arm in the set is a raised one.** No Scudo
abort appeared - zero matches in `RPCSX.log` and in logcat - so the crash did not
reproduce, but the benefit did not either.

**The mechanism is thermal.** Compile concurrency is the one thing on this device
that converts directly into heat: the raised arms ran 6-7 C hotter and hit 94 C,
where the big cluster throttles. On a passively cooled handheld, extra parallelism
in a sustained CPU-bound stage buys wall-clock only while there is thermal headroom
to spend, and Transformers' larger modules exhaust it.

**So `ppu_budget_mb` is a per-title knob with a measured benefit on exactly one
title tested and none on the other.** The default stays 1536 for the documented
Scudo reason, and the 21% should be quoted with Folklore's name attached to it,
never as a general figure.

**And the general lesson is about this device, not this property:** a change that
raises sustained CPU concurrency here has to be measured with the temperature
beside it, because the thermal ceiling can take back everything the concurrency
gained. That is a second mechanism by which a real speedup evaporates, alongside
the frames-for-CPU trade the RSX park showed.

# The real reason nothing resolved: a title screen is not a reproducible workload

**This is the conclusion of the whole 2026-08-18 session, and it supersedes the
"two states" and "three states" notes above.**

Folklore's title screen was treated all session as a fixed workload to A/B against.
It is not one, and it fails to be one on **every** axis measured:

| axis | same title, same build, same settings |
| --- | --- |
| frames per 60 s | 7200 and 6000, and later 10200, 9600, 9000 |
| process ticks per 60 s | two clusters, 1823-1890 and 2662-2809 |
| steady junction temperature | **51.0 C and 90.1 C for the SAME setting** |

That last row is the one that settles it. Two arms of `lv2_spin=0`, each cooled to
the same floor and each held 300 s to settle, differed by **39 C**. No lever moves
a device 39 C. The workload itself is different between boots.

**So every null in this session is explained without needing any lever to be
worthless.** Eight variants, four levers, two instruments - all were being asked to
resolve a few percent against a workload whose own variation is larger than the
effects. The interleaving is what kept the comparisons honest; it could not make
the scene stand still.

## What a usable workload on this device looks like

`tools/thor_precompile_ab.sh` resolved `ppu_budget_mb` at 21% in **four arms**,
after eight attempts on the title screen resolved nothing. The difference is not
the lever, it is the workload:

| property | title screen | PPU precompile |
| --- | --- | --- |
| identical work each run | **no** | yes - the cache is cleared, the modules are fixed |
| needs input | no | no |
| self-timed by the emulator | no | yes - `LLVM: Compiled module` stamps |
| loads the machine | 0.3-0.4 cores | saturates the compile workers |

**Prefer a workload with fixed, finite work over a free-running scene.** A scene
that renders forever has no natural unit; a fixed set of modules to compile has
one, and it is the emulator's own clock. This is the single most useful thing
learned here, and it is worth more than any of the levers that were tested.

**And it explains the retraction record.** Two claims were made and withdrawn in
this session on title-screen numbers - `host_mutex_spin` at 1.9%, the SPU park at
2.8% - and both would have been avoided by asking first whether the scene repeats.
Do that before the next A/B, not after it.

# Scope decision, 2026-08-18: the wattage half is dropped

The user was asked directly and chose to **drop the wattage half of the goal**,
given that no instrument on this device can measure it: the battery gauge is frozen
in all four nodes even USB-detached and discharging, the cpufreq residency proxy
moved 0.2% against a known 2.4x effect, and the thermal proxy is swamped by the
workload variance recorded above (51.0 C against 90.1 C for one setting).

**So do not open a power question here without a plan for the second screen.** It
is the only trusted instrument and it needs a person. Future work is speed, on the
precompile harness, which resolves.

On `ppu_budget_mb` the user had no preference, so the engineering call stands: the
default does not change. A setting that can stop a game booting is not worth a gain
that appeared on one title of two, when one command enables it. It is documented in
`README.md` now, with both the 21% and the two ways it can disappoint, so it is
discoverable rather than buried in a header comment.

# SHIPPED: the PPU compile budget default is 4096 MB

**Changed 2026-08-18 from `min(total/6, 1536 MB)` to `min(total/3, 4096 MB)`.**

The old cap made a single module's estimate larger than the whole budget on some
titles, so precompile serialized while seven cores idled. Measured on Folklore, PPU
cache cleared before every arm, emulator seconds to the 15th compiled module:

| budget | seconds |
| --- | --- |
| 1536 MB | 61.71, 60.63, 59.23 |
| **4096 MB** | **49.24, 47.49, 46.03** |

**Verified the way a default has to be, with the property UNSET**: 46.03 s against
59.23 s for an explicit 1536 in the same interleaved run, and the emulator's own
line reading `PPU precompile memory budget: 4096 MB (total 15255 MB)` on a boot with
nothing set.

**And verified not to break the titles that can be booted here.** Transformers
carries the heaviest modules in this library - 1,677,721,600 bytes of estimate, the
title this file recorded as fully serialized - and a cold precompile on the shipped
default reached 44 modules with **zero** matches for `Scudo`, `SIGABRT` or
`Fatal signal` in `RPCSX.log` and in logcat, process alive throughout.

**What is NOT verified, stated plainly.** BLUS30126 is the title that aborts in
precompile, and it has no bootable disc image here, so the one case this change
makes riskier is the one case that could not be tested. The revert is one command
and `README.md` names it as the first thing to undo if a game stops booting:

    adb shell setprop debug.rpcsx.thor.ppu_budget_mb 1536

**And it is not a universal win**: on Transformers the 21% did not appear, because
compile concurrency is heat and the big cluster throttles near 94 C. The gain is
real on titles with thermal headroom and absent on titles without.

`total/3` keeps the fraction binding on smaller devices, so the cap only lifts
where there is memory to lift it.

# ARMSX3 fourth pass, 2026-08-19: two ARM64 correctness fixes ported

ARMSX3 is at `4c080066c`, **41 commits** past the `62d8208c7` the third pass used.
Upstream RPCS3 is at `b78bae0b9`, 25 commits past `f9f88aa9e`, of which exactly one
touches ARM64 - `6161ecd7a`, the PPU float-to-int saturation defect that
[`three-way-audit.md`](docs/arm64/three-way-audit.md) already records as fixed here.
**So the value in this pass is entirely on the ARMSX3 side, and it is correctness,
not speed.**

## Ported: the SPU gateway scratchpad was 8192 bytes (`55a54c924`)

**This tree had the defect verbatim**, at two sites in `SPUCommonRecompiler.cpp`.
Compiled SPU functions build no frames of their own on ARM64 -
`GHC_frame_preservation_pass` runs with `use_stack_frames = false` - so every one
of them spills into a single shared reservation. ARMSX3 measured a 2401-instruction
SPURS function wanting **~21 KB**, faulting at `sp+21760`, exactly the top of the
thread's stack mapping, on the PROT_NONE guard page. Raised to **256 KB**.

**Read this next time the app dies with no explanation.** A guard page is not
emulator memory, so `is_emulator_fault()` correctly declines it, the handler
forwards to libsigchain, and ART's FaultManager reads the guest registers as an
`ArtMethod*` and kills the process. **No tombstone, no flushed emulator log, and
Android records only `SIGNALED status=11`.** Every silent death during SPU
execution in this fork's history is a candidate.

**Their second half was already present here.** ARMSX3 also raised Android threads
from bionic's 1 MB default to 8 MB; `util/Thread.cpp:2202` already does that under
`#elif defined(__APPLE__) || defined(ANDROID)`. Checked before porting.

**Verified on device:** Folklore boots and renders, 3600 frames, and zero matches
for `Fatal signal`, `SIGSEGV`, `SIGBUS` or `Compilation failed` in the log or in
logcat. The `sub sp, sp, #262144` shifted-immediate encoding is fine.

## Ported: the SPU INTERPRETER still applied x86 saturation (`884cb47dd`)

[`three-way-audit.md`](docs/arm64/three-way-audit.md) records the x86 float-to-int
correction as a defect fixed here - **in the recompiler.** The interpreter copy was
missed and was still present, unguarded, in `SPUInterpreter.cpp`.

`_mm_cvttps_epi32` is sse2neon's `vcvtq_s32_f32`, i.e. `FCVTZS`, which **already**
saturates, so the x86 fixup inverts a correct result. ARMSX3's measurements:

| input | correct | what this tree produced |
| --- | --- | --- |
| CFLTS, +3e9 | `0x7fffffff` | `0x80000000` |
| CFLTS, NaN | `0x80000000` | `0` |
| CFLTU, 3e9 | `0xb2d05e00` | `0x7fffffff` |

CFLTU is the worse one: the x86 form *relies* on `cvttps2dq` returning `0x80000000`
and ORs the remainder back in, but `0x7fffffff | v == 0x7fffffff` for every
`v < 2^31`, so **the entire upper half of the range collapsed to one value.**

**And this file was wrong to call the interpreter cold.** The ledger says "both
decoders are LLVM, the interpreter is fallback-only". `spu_interpreter_rt` is what
`spu_run_interp_fallback` executes, so it is live on ARM64 - and forcing a block to
the interpreter is the standard test for whether the recompiler emits wrong code,
which means the test itself could introduce a fault the recompiler did not have.

## Not ported yet, with the reason

* **`19d23eb69`, the SHUFB byteswap fold.** `idx_selects_single` and
  `get_swap_from_const` are present here - **3 matches** - so this tree carries
  upstream `a7fc31f32`'s two semantic changes and therefore the hang: ARMSX3 measured
  a function spinning forever inside one block, byte-identical counters across six
  thread dumps at 96% CPU. **SHUFB is the most-emitted SPU op in this fork's corpus
  at 5,794**, so this is the highest-value item left. It reverts a fold rather than
  adding one, so it wants its own pass.
* **`9b3331698`, `mov_rdata` at 16-byte granularity.** Ours is `std::memcpy`, whose
  transfer sizes are a libc detail, so a racing reader can see a line stitched from
  two versions. **Note the rationale differs from the version reverted here**: that
  one was an instruction-count argument, this one is tearing. The re-land bar this
  file already set still applies - millions of randomised 128-byte pairs diffed
  against memcpy on device - and ARMSX3 state it fixed no observable behaviour.

# Another session force-stopping the package looks exactly like your own crash

**2026-08-19, and it produced three wrong conclusions in a row before it was
caught.** While testing the SHUFB revert, Folklore started dying at 300-600 frames.
The evidence looked like a clean regression:

* the process was gone, `pidof` empty
* **zero** `Fatal signal`, `SIGSEGV`, `SIGBUS` in `RPCSX.log` AND in logcat
* no tombstone
* it reproduced on the very next boot
* the previous build had reached 3600 frames

Three conclusions were drawn and **all three were wrong**: that the SHUFB change
broke it, then - after reverting it did not help - that the scratchpad change did,
then after reverting that too the failure continued.

**The app was being force-stopped by something else.** Launched, then left
completely alone for 90 seconds with no commands issued:

    11:36:40 ActivityManager: Force stopping net.rpcsx.easy ...: from pid 25513
    11:37:01 ActivityManager: Force stopping net.rpcsx.easy ...: from pid 25648
    11:37:22 ActivityManager: Force stopping net.rpcsx.easy ...: from pid 25791
    11:37:42 ActivityManager: Force stopping net.rpcsx.easy ...: from pid 25931

A ~21 second cycle, a different device pid each time. Still running an hour later:
three more in a 60 second window.

**This is the shared-device protocol failing in a new direction.** That section
warns not to force-stop the OTHER session's package. It did not anticipate the
other session force-stopping OURS, on a timer.

## The check, before diagnosing any silent death

    adb logcat -d | grep -E "forceStopPackage|Force stopping"

A kill from `ActivityManager` names the pid that asked for it. If that pid is not
one of yours, stop debugging your own change - and note that **an external kill
leaves no crash signature at all**, so it is indistinguishable from a clean exit or
from the guard-page death recorded above unless this line is read.

**And it invalidates measurements silently.** A 60 s window that gets killed at 21 s
does not error; it returns whatever partial counters existed. Any arm whose numbers
look truncated during a contended session should be re-checked against this.

**What survived and what did not.** The `ppu_budget_mb` measurements and the
default verification completed full 60-plus-second precompiles, which a 21 second
kill cycle makes impossible, so they predate this and stand. The SHUFB revert is
**untested** - it is not in the tree, and the evidence that provoked it was void.

# Ported: the SHUFB single-source trigger (ARMSX3 `19d23eb69`)

**Landed 2026-08-19 on a quiet device, after being wrongly rejected on a contended
one.** Upstream `a7fc31f32` added `idx_selects_single`, which treats a mask whose
bit 4 is known-constant across all lanes as single-source. ARMSX3 traced a hang to
it: a SPURS function spins forever inside one block when compiled and boots when
interpreted, with block counter, loop count and retreat count byte-identical across
six thread dumps at 96% CPU. They state the miscompile lives in that flag combined
with the ARM64 tbl/tbx paths - which is exactly this fork's block.

**This tree carried only half of that commit.** The byteswap widening
(`get_swap_from_const`) is absent here and the fold is already splat-only, so the
flag was the whole exposure. The ARM64 single-source path now triggers on
`op.ra == op.rb` alone, as before `a7fc31f32`.

**Verified:** Folklore reaches 8700 frames in 75 s, the same trajectory as the build
without the change (2400 / 5700 / 8700), zero `Fatal signal`, `SIGSEGV`, `SIGBUS` or
`Compilation failed`, and a clean title screen at **60.01 FPS** with no corruption -
which is the thing to look at for a shuffle defect.

**Cost, unmeasured and stated.** Provably-single-source shuffles now take the
two-source TBL2/TBX2 path, and `bench-results.md` measures TBX2 at 2.1x the
throughput cost of TBL2 on the A715/A710 where SPU threads run. SHUFB is the
most-emitted op in this fork's corpus at 5,794. That price is accepted because a
shuffle that spins a core forever outranks a slower one, and because the reach of
the fast path was never measured either. To re-open it, restore the flag behind a
property and A/B on a **gameplay** scene.

## RETRACTED: "the SHUFB change breaks Folklore"

It does not. That conclusion came from a contended device and is void; so were the
two that followed it, blaming the SPU scratchpad and then nothing at all. All three
were the external force-stop recorded above, killing the process every ~21 seconds
with no crash signature. **Read the `forceStopPackage` line before blaming a
change** - it is one grep, and it would have saved three rebuilds and two wrong
reverts.

# Thermal behaviour against a 70 C target, measured on every sensor

**The user's requirement is junction/skin under 70 C long term and wattage mostly
under 6 W. Measured 2026-08-19.** The answer splits cleanly by phase, and only one
phase fails.

## Sustained running PASSES, with room to spare

Folklore, warm PPU cache, 280 s of continuous rendering:

| sensor | range |
| --- | --- |
| `cpu-1-*` junction | 47.0 - 58.2 C |
| `pm8550b_lite_tz` (PMIC) | 45.9 - 46.9 C |
| `video` | 45.7 - 47.7 C |
| fan controller's sensor | 45.1 - 47.8 C |
| battery | 25.0 C |

**Nothing approaches 70 C.** This is the state a game spends essentially all of its
time in, because the compile result is cached per title.

## The first-load compile stage FAILS, for about two minutes

Same title, PPU cache cleared:

| t | junction | fan/skin sensor | `video` | modules done |
| --- | --- | --- | --- | --- |
| 20-100 s | **90.7 - 95.2 C** | **80.7 - 83.7 C** | 65.9 - 72.2 C | 8 -> 43 |
| 120 s | 77.5 | 71.6 | 64.7 | 50 |
| 140-200 s | 52.2 - 54.2 | 50.7 - 52.7 | 50.9 - 54.0 | done |

**This is not a junction artifact.** The skin sensor the fan controller reads gets
to 83.7 C, so the device is genuinely hot, not just one core. It lasts about two
minutes and happens once per title.

## What does NOT reduce the peak

* **`Max LLVM Compile Threads: 4`** instead of auto: peak unchanged at 91-95 C.
* **`ppu_budget_mb` 1536 instead of 4096**: peak unchanged, in fact slightly higher
  at 95.2 C, and the hot window lasts **far longer** - still compiling at 6:00
  against 2:15 for the 4096 default.

**So the shipped 4096 default is the better of the two for this requirement**, not
the worse one. Same peak, much less time above 70 C. That was worth checking
before assuming a faster compile means a hotter device.

## And a session-long mistake this exposed

Every thermal gate in this session used `cpu-1-*` and refused arms above 55-62 C.
**Idle on this device is 41-47 C on those zones**, and the PMIC and skin sensors sit
lower still, so those gates were far stricter than intended and cost long cooldowns
and several abandoned arms. `thermal.md` already warns about junction versus
package; this is that warning being ignored for a whole session.

**For a "is the device hot" question, read the fan controller's sensor** - it is what
the hardware itself acts on, it appears in logcat as
`FanBase ... temperature = NN.N speedPercentage = NN`, and it tracks the skin. Use
`cpu-1-*` only for spotting a per-core transient.

## Wattage is still not measurable

`current_now` reads 0, `charge_counter` and `voltage_now` do not move within a
window, and `power_now` is frozen, on AC and off it. The 6 W target cannot be
checked over adb. The second screen remains the only instrument.

# SOLVED: system wattage IS measurable on this device, from the charger input

**Found 2026-08-19, after three instruments failed.** This supersedes every
"wattage cannot be measured here" note above, including the fuel-gauge and cpufreq
sections. Those remain true about the paths they describe; they were the wrong
paths.

## The working instrument

    /sys/class/power_supply/usb/voltage_now    input volts  (~8.9 V here)
    /sys/class/power_supply/usb/current_now    input amps   (tracks load)

`P = voltage_now x current_now`. `tools/thor_power_iin.sh` samples it.

**Validated against a figure this repo obtained independently**: idle measured
**1.64 W** here against the **1.60 W** recorded earlier from the second screen. It
also responds to load, which is the test the cpufreq proxy failed - 178 mA idle
against 253-291 mA with a title rendering.

**Two traps, both of which produced garbage before they were found:**

* **`usb/current_now` is NOT frozen.** An earlier note in this file calls it "the
  negotiated limit and sits frozen". That is wrong on this device: it moves with
  load, and it is the stable channel.
* **The PMIC ADC `in_current_pm8550b_iin_fb_input` is bidirectional and noisy.** It
  swings +-2 A within one window and averages NEGATIVE under load. Do not use it;
  use `usb/current_now`.
* **The arithmetic overflows the device shell.** `(v/1000) * i` is
  `8918 * 278000` = 2.48e9, past 32-bit signed, which reported **-1334 mW for a
  device drawing 2.4 W**. Divide both terms first: `(v/1000) * (i/1000) / 1000`.

**The condition that makes it valid:** the battery must not be charging. Check
`in_current_pm8550b_ichg_fb_input` is 0 and the level is not climbing, or the input
power includes whatever is going into the cell.

## What this device actually draws

| state | mean | range |
| --- | --- | --- |
| idle, emulator stopped | **1.64 W** | 1.32 - 2.52 |
| Folklore title screen, 60 fps | **4.02 W** | 2.01 - 8.25 |
| PPU compile, first load only | **9.42 W** | 7.05 - 12.95 |

And the matching thermals, from the sensor the fan controller acts on:

| state | skin sensor | `cpu-1-*` junction |
| --- | --- | --- |
| sustained rendering | 45 - 48 C | 47 - 58 C |
| PPU compile | 81 - 84 C | 91 - 95 C |

## Against the stated targets: under 70 C and mostly under 6 W

**Sustained running meets both**, and that is where a game spends essentially all
of its time, because the compile result is cached per title: 4.0 W and 45-48 C.

**The first-load compile exceeds both** - 9.4 W and 84 C for about two minutes.
**The user has ruled that acceptable**: compile-phase highs are fine, and the
targets apply to normal running. Do not trade compile speed away for them.

## What the compile budget costs, both ways

Cold cache, 55 s window, both arms started under 55 C:

| `ppu_budget_mb` | mean power | modules in the window |
| --- | --- | --- |
| 1536 | 5.92 W | 18 |
| **4096, the default** | **9.61 W** | **24** |

**So the shipped default draws 62% more power and does 33% more work.** Per module
that is 22.0 J against 18.1 J - the faster setting is **less** energy-efficient,
about 22% more energy for the same compile - while finishing the job sooner and
therefore leaving the hot window earlier (2:15 against still compiling at 6:00).

Both facts are true and they point different ways. The default stays at 4096
because the compile highs are accepted and wall-clock is what the user waits on.
**Quote the energy figure, not just the time, if this is ever revisited.**

# The compile budget trade, measured properly: 19% faster for 22% more energy

**Three interleaved samples per arm, 2026-08-19, fixed work.** Earlier attempts used
"modules compiled in a fixed 55 s window", which is NOT a usable metric - module
sizes vary, so one setting returned 18 then 10, and any energy-per-module figure
from it is noise. Fixed WORK is the comparable unit: compile the same 15 modules and
integrate power over however long that takes. `tools/thor_compile_energy.sh`.

| `ppu_budget_mb` | seconds | energy for 15 modules |
| --- | --- | --- |
| 1536 | 59, 61, 60 | 380, 372, 373 J |
| **4096, the default** | **48, 50, 48** | **465, 472, 450 J** |

**Neither range overlaps.** The default is **19% faster and uses 22% more energy for
identical work**, so race-to-idle loses here: the extra cores cost more than the
shorter run saves.

**And the absolute size is what decides it.** The delta is 90 J per 15 modules, so
about 468 J - **0.130 Wh** - extrapolated to a full ~78-module first load. Against a
22.4 Wh battery that is **0.58% of one charge**, in exchange for roughly **57
seconds** off the wait before a new game starts.

**So the default stays at 4096.** A user waits through that minute once per title and
never sees the half-percent. The trade is recorded rather than hidden, and anyone who
wants the energy back has one command:

    adb shell setprop debug.rpcsx.thor.ppu_budget_mb 1536

**2048 and 3072 are not a middle ground**, or at least not one that showed: single
runs returned 87 s and 88 s, slower than BOTH endpoints, which is incoherent as a
curve and is run-to-run variance rather than a measurement. If a sweet spot is ever
wanted, it needs the same three-sample treatment as the endpoints got, on a quiet
device.

# Against the 70 C / 6 W targets: heat passes everywhere, wattage fails under load

**Measured 2026-08-19 with the charger-input instrument.** Eternal Sonata is the
heaviest workload reachable without a controller - its opening plays unattended - so
it is the closest thing to a gameplay number this device can produce headlessly.

| workload | power (mean) | skin | junction | CPU |
| --- | --- | --- | --- | --- |
| idle, emulator stopped | **1.64 W** | ~42 C | 36 C | - |
| Folklore title screen, 60 fps | **4.02 W** | 45-48 C | 47-58 C | 0.35 cores |
| **Eternal Sonata, opening** | **5.33, 8.91, 7.37 W** | 56.9-58.0 C | 62.6 C | 1.5-2.1 cores |
| PPU compile, first load only | 9.42 W | 81-84 C | 91-95 C | - |

## Heat: PASSES

Nothing outside the compile burst approaches 70 C. The heaviest reachable scene sits
at **58 C skin and 62.6 C junction**, with the fan holding it there. Compile reaches
84 C and the user has ruled that acceptable.

## Wattage: FAILS on a real game

Three consecutive 60 s samples of the same Eternal Sonata scene gave **5.33, 8.91 and
7.37 W**, with peaks to **13.8 W**. Two of three are above the 6 W target and the mean
of means is 7.2 W.

**The spread is the scene, not the instrument.** This file already records ten
consecutive CPU samples of one Eternal Sonata arm spanning 1.1 to 5.2 cores; the power
follows it, and the CPU readings here moved 2.08 to 1.53 cores between samples.

**So the 6 W target is met at a title screen and missed during actual play.** Any
future power work should be aimed at the gameplay path, which is where the levers this
file already identifies live - the SPU self-loop park at ~20% of gameplay CPU, MFC DMA
at 20.13%, `vm::writer_lock` at 4.49%. **All three are still unmeasurable headlessly,
because gameplay cannot be reached over adb.** Now that wattage IS measurable, a game
left at a save point would let every one of them be judged on power as well as time.

# SHIPPED: the SPU self-loop park is on by default - 45% less CPU, 18% less power

**The lever this file has carried as "built, default off, and unmeasured" since
2026-08-13 is now measured, and it is the largest win in the fork after the lv2
spin.** Default is `100` microseconds.

Eternal Sonata's opening, four interleaved pairs, **every arm rendering exactly 3600
frames** in the window:

| `spu_selfloop_park` | power | CPU ticks |
| --- | --- | --- |
| 0 (the old default) | 4894, 5293, 4892, 4954 mW | 12542, 12440, 12447, 12798 |
| **100 (now default)** | **4206, 4397, 4101, 3662 mW** | **6775, 6751, 7125, 6943** |

**Neither range overlaps on either axis, and the frame count is identical.** That is
**-45% CPU and -18% power for the same output**, taking this title from about 5.0 W
to about 4.1 W - under the 6 W target the user set.

**Verified as a default must be, with the property UNSET**: the counter reads
`entries=26684 ... last_pc=0x00cc4`, so the shipped binary parks without being told to.

## Why this took six weeks and three failed attempts

**Reach, and nothing else.** On Folklore's title screen the counter reads
`entries=0` - the loop is never entered - so the A/B measured nothing, twice, and the
lever was written off as "no reach on this scene". On Eternal Sonata it reads about
**49,000 entries per 60 s window at `pc=0x00cc4`**, which is the state-poll loop this
file identified in the gameplay profile long ago.

**A lever with no reach and a lever with no effect produce the same number.** The
counter is the only thing that separates them, and it did not exist until 2026-08-18.
That is the whole lesson: instrument the mechanism, then pick the workload that
exercises it.

**And the workload was reachable the whole time.** Gameplay cannot be driven over adb
- three input paths tried, events confirmed reaching the kernel, guest sees none - but
Eternal Sonata's opening plays unattended at 1.5-2.1 cores. It is the heaviest thing
this device can be made to do headlessly, and it should be the default A/B scene for
anything on the SPU or MFC path. A title screen at 0.35 cores answers nothing.

## The hazard has not gone away

Parking turns a burning core into a quiet sleeping thread, so a guest deadlock stops
looking like one. `entries` and `last_pc` are written BEFORE the wait and `exits`
after, so `entries - exits > 0` is a park happening right now and `last_pc` says
where, and `perf_monitor` prints all three. **If a title hangs with a quiet CPU, read
that line first**, and `debug.rpcsx.thor.spu_selfloop_park=0` restores the spin.

# ARMSX3 fifth pass: the PPU rtime defect is NOT in this tree, measured

ARMSX3 is at `2e65c8b21`, 8 commits past the fourth pass. The significant one is
`ca3b755fd`, a defect in the PPU `ldarx` cached-reservation fast path: re-reserving
the line a successful `stdcx` just wrote leaves `ppu.rtime` one increment behind the
line's counter, so **every conditional store after the first on that line fails by
exactly 128**, and a retrying guest re-enters the same fast path with the same stale
value. They measured **490 million** such failures on one address and it stops
Assassin's Creed booting.

**The shapes differ, so this was measured rather than ported.** Their fast path is an
empty branch. This tree has `ppu.rtime -= 128` in `ppu_ldarx` and `ppu.rtime += 128`
on the `ppu_stcx` success path. Read naively those cancel and would reproduce the
defect - which is exactly the kind of reading that has been wrong here before.

A probe on the failure site counted stores that fail with **unchanged data and a
counter exactly 128 ahead**, against a control of every other failure. Eternal
Sonata, one window:

    stcx: stale128=207 other_fail=55

**207, not 490 million, on a title that boots and renders.** And the signature is not
even specific: a reservation line is 128 bytes, so another thread writing a
*different* part of the line advances the counter while leaving the compared 8 bytes
unchanged. That is ordinary sharing and it produces this pattern legitimately.

**So the `+128`/`-128` pairing here is correct and nothing is ported.** The naive
cancellation reading was wrong.

**The probe stays**, printed by `perf_monitor` beside its control, because a future
"conditional stores keep failing" report is answerable in one boot with it: a stale
count in the millions next to a small control is the defect, both large together is
contention, and both small is healthy. The numbers above are the healthy baseline.

## Also in that range, and not applicable

`91952ae4c` re-enables fp16 on Turnip. Their gate compared `driverVersion` against
Qualcomm's numbering (512.676.53) while Turnip reports Mesa's (25.99.99), which can
never pass, so fp16 was emulated in fp32 on every Turnip install. **This tree has no
such gate** - checked - and the boot log already says `Using native float16_t
variables if possible`, confirmed on device earlier. Nothing to take.

# The accelerations are in the EMITTED code, counted on the current build

**Verified 2026-08-19 by disassembly, not by reading flags.** The JIT log says which
features are enabled; this says which instructions the recompiler actually produced.

`debug.rpcsx.thor.spu_native_object_cache=1` with Eternal Sonata (the gate requires
`BLUS30161`), 25 objects written by the current binary, **20,020 instructions**:

| instruction | count | what it accelerates |
| --- | --- | --- |
| `udot` / `sdot` | 20 / 3 | asimddp - SPU `SUMB`, `GB`, block verification |
| `bcax` | 26 | sha3 - SPU `EQV` and the `SHUFB` selector paths |
| `tbl` / `tbx` | **240 / 47** | `SHUFB`, `ROTQBY`, PPU `VPERM` |
| `addv` | 52 | SPU reductions |
| `ushl` | 41 | `inf_shl`/`inf_lshr` |
| `fcvtzs` | 2 | float to fixed point |
| `ldp` / `stp` | 650 / 708 | paired access |

**So dot-product, sha3 and the table-lookup lowerings are all live in code that
runs**, on this build, on this device. That is the standard this file sets for a
codegen claim - count the instruction in the shipped artifact, not the feature in a
log line.

**Pull only objects the CURRENT binary wrote.** The cache held 1305 objects and most
were from 2026-08-10; a `-newermt` filter left 117 from today. Counting the stale
ones would have described a build that no longer exists, which is the version-banner
trap in yet another costume.

**And the tbl/tbx mix moved.** This file records `SHUFB` emitting `TBX2` and warns
that `TBX2` costs 2.1x the throughput of `TBL2` on the A715/A710 where SPU threads
run. After the `idx_selects_single` revert the ratio here is **240 `tbl` to 47
`tbx`** - the cheaper form dominates. That was not the goal of the revert, which was
correctness, and it is a reason to re-measure the cost noted there rather than assume
it still applies.

`i8mm` (`smmla`/`ummla`) does not appear in this 25-object sample. It is gated on
`GBH`/`GBB`, which those functions may simply not use; a larger sample would settle
it. Not evidence of absence.

# SHIPPED: GETLLAR sleeps instead of spinning - the "one thing to run next", done

**[`spin.md`](docs/arm64/spin.md) records the GETLLAR wait as 93% of all instrumented
spin, and this file has carried "sweep it" as the outstanding measurement ever since.
Swept 2026-08-19.** Upstream defaults `SPU GETLLAR Busy Waiting Percentage` to 100 -
always spin - while the analogous reservation knob is explicitly 0 on this device.
The default here is now **0**.

Eternal Sonata's opening, **seven interleaved pairs**, every arm rendering exactly
3600 frames:

| `getllar_busy_percent` | CPU ticks per 60 s |
| --- | --- |
| 100 (spin, upstream) | 7076, 7109, 7270, 7074, 7179, 7181, 7286 |
| **0 (sleep, now default)** | **6468, 6450, 6628, 6441, 6625, 6529, 6609** |

**7074-7286 against 6441-6628 - no overlap, -9% CPU at identical frame output**, and
that is *on top of* the SPU self-loop park, which is also on by default now.

**Verified with the property UNSET**, which is the only thing that proves a default:
`cpu=6592`, inside the sleep range and nowhere near the spin range.

## What is NOT verified, said plainly

**The frame-time tail.** p50 is **16.86 ms in both arms** - 60 fps exactly - and the
frame count is identical, so nothing is being dropped. But **a capped frame rate hides
latency**, which is the whole reason this file demands p95 for a sleep change, and the
`dumpsys SurfaceFlinger --latency` capture used here returned a contaminated tail:
p95 of 1348 ms and p99 of 91 seconds are stale buffer entries, not frames. The
capture needs the fix that produced clean percentiles for the lv2 spin work before
that number means anything.

The lv2 spin change is the same class - a bounded spin in front of a working wait -
and measured **no cost at any percentile**. That is the prior, not proof.

    adb shell setprop debug.rpcsx.thor.getllar_busy_percent 100

restores the spin if a title looks stuttery for it.

## Where the fork now stands on the SPU spin layers

The four-layer table in this file listed lv2 syscalls, the SPU JIT self-loop, the SPU
MFC reservation and `vm::writer_lock`. **Three of the four now sleep by default:**

| layer | share of gameplay | state |
| --- | --- | --- |
| lv2 syscalls | 73.9% of a title screen | **fixed**, `lv2_spin=0` |
| SPU JIT self-loop | ~20% | **fixed 2026-08-19**, park on, -45% CPU |
| SPU MFC reservation (GETLLAR) | ~7%, 93% of instrumented spin | **fixed 2026-08-19**, -9% CPU |
| `vm::writer_lock` | 6.2%, six threads | still an unbounded `sched_yield` |

`vm::writer_lock` is the one left.

# The speed result: +13% frame rate when the CPU is the constraint

**Measured 2026-08-19.** Every scene this device can reach headlessly renders at
**exactly 3600 frames per 60 s** - 60 fps, the panel's rate - with CPU to spare.
Folklore's title screen, Eternal Sonata's opening, even Watch_Dogs at 5.06 cores
busy. `Frame limit: Off` changes nothing, because the cap is **presentation, not the
limiter**. So on those scenes an optimisation cannot show as frame rate, only as
headroom, and this session's wins looked like CPU numbers.

**Make the CPU the constraint and the headroom becomes frames.** Eternal Sonata with
six spinner processes competing for the cores, four interleaved pairs:

| | frames per 60 s | fps |
| --- | --- | --- |
| park off + GETLLAR spin (upstream behaviour) | 3000, 3000, 3000, 3000 | **50** |
| **shipped defaults** | 3600, 3300, 3300, 3300 | **55 - 60** |

**Nothing overlaps, and the OFF arm returns exactly 3000 every time.** That is
**+10% to +20% frame rate, mean +13%**, from the two defaults shipped today.

## Why this is the honest way to state the speed win

**A capped scene hides it and an uncapped one does not exist here.** The same two
settings measured -48% CPU on the uncontended scene (13062 and 12939 ticks against
6705 and 6708) and 0% frame rate, because 60 fps was already being met. The frames
only appear once the machine cannot supply what the emulator asks for.

**That is exactly the condition real gameplay creates**, and it is the condition this
fork cannot reach directly - gameplay needs a controller and the guest pad cannot be
driven over adb. The spinners are a stand-in for it: they do not make the emulator
faster or slower, they make the CPU scarce, which is what a demanding scene does.

**So quote it as conditional, never bare.** "+13% fps when CPU-bound" is supported.
"+13% fps" is not, and on a title screen it would be flatly wrong.

## What did NOT benefit, and why that matters

Watch_Dogs shows **no difference at all** - 30295 ticks against 30306 - because the
SPU self-loop park has **no reach** there: the counter reads `entries=0`. It is a
different engine and it never branches to self. Eternal Sonata reads ~49,000 entries
per window at `pc=0x00cc4`.

**A lever that is worth 45% of CPU on one title can be worth nothing on another**, and
the counter is the only way to know which before spending a session on it.

# Open pull requests and Whatcookie, sixth pass, 2026-08-21

Surveyed `RPCS3/rpcs3` open pull requests (`54` of them) and every pull request
Whatcookie has opened (`112`, almost all merged). ARMSX3 had nothing new; its
head is still `82f21b16d` from 2026-08-20.

## The SPU verification checksum is STILL blind, and the blind spot only moved

`#19230`, "SPU LLVM: Remove unsafe ARM checksum specialization", is a draft by
Consumer-of-Souls. It removes the whole ARM64 checksum path and uses the generic
512-bit checksum on ARM64 too, `181` lines deleted and none added. The reason
given is that `UABD(a, b) == UABD(b, a)`, so swapping the paired vectors leaves
the checksum unchanged and the verifier accepts a stale cached block. They
reproduced two missed gameplay and cutscene triggers in LEGO Dimensions
(`BLES02105`) on an Apple M4 Pro, and both fire with the change.

**This tree does not have their bug, and it does have the same class of bug.**

On 2026-08-10 this fork replaced `aarch64_neon_uabd` with a plain add, because
`|a - b|` is unchanged when both sources shift by the same `d`. That fix is
real and it is confirmed on device. It is also not enough. Read the two lanes
that survive, `SPULLVMRecompiler.cpp`:

    next_acc[1] = m_ir->CreateAdd(next_acc[1], m_ir->CreateAdd(vls[1], vls[2]));

and its host mirror, which has to agree with it:

    checksum[4 + i] += words[4 + i] + words[8 + i];

A pair contributes only its SUM. So:

| Pair operation | Blind to |
| --- | --- |
| `UABD(a, b)`, upstream today | `(a + d, b + d)` |
| `a + b`, this fork since 2026-08-10 | `(a + d, b - d)`, and `(b, a)` |
| generic path, every other target | neither |

Both operations collapse two words into one number. They collapse different
directions. Only the generic path keeps every source word in its own accumulator
lane, and only it has no direction to collapse.

The swap case is the one to worry about. Two adjacent 16-byte instruction groups
exchanged between two versions of a streamed job binary is ordinary code motion,
and this fork's own comment already describes the setting: "job managers stream
near-identical job binaries through the same local-store addresses".

**DONE 2026-08-21.** The ARM specialization is deleted. ARM64 now runs the same
512-bit checksum as every other target, which gives every source word its own
accumulator lane and folds nothing inside a block. The change is `-200/+99` lines
in `SPULLVMRecompiler.cpp`, and the generic body came from upstream
`origin/master`, not from a hand rewrite, so the rolled `checksum_loop` came with
it. Without that loop the old generic body here was unrolled only, and a large
block would have emitted a long verification prologue on every entry.

The cost is real and unmeasured. The old ARM path did four accumulate operations
for each 96 bytes; this one does one for each 64 bytes, which is more work per
byte. If it ever measures badly, an ARM path can come back, but only with a pair
operation that is neither symmetric nor translation-invariant. `a + b` is both,
so it cannot come back as it stands.

**Still to do: a device round.** This changes what the verifier accepts. Nothing
has booted with it. Watch for cache-rejection rows and for a change in the SPU
program build count, which was about `1188` across eight workers on 2026-08-21.

**What to measure before believing anything here.** Nobody has shown a real
collision in this fork. The claim above is about the arithmetic, not about a
captured failure. `debug.rpcsx.thor.spu_native_object_cache=1` before the boot
you intend to pull, and the cache tree needs `run-as net.rpcsx.easy` to clear.

## Whatcookie: the merged series is already here; one closed idea is not

The ARM64 series in `AGENTS.md`, section `ARM64 Upstream Perf Uplift`, covers the
merged work: `ISB` for `pause`, `udot`/`sdot` for `SUMB`, `TBL` for `ROTQBY`,
`I8MM` for `GBH`/`GBB`, `SVE2 XAR`, native ARM shuffles, the ARM timer scaling
this fork rejected, and, on 2026-08-18, `#19259` "PPU: Stop inverting
float-to-int saturation on ARM64", which this fork already had and does better.
Nothing merged is missing.

One CLOSED, unmerged pull request holds an idea worth having: `#18422`, "Utils:
Add support for some more useful arm extensions". Besides `FEAT_LUT` and another
`I8MM` use, it adds a function to detect the SVE VECTOR LENGTH, and says why:
"We might need to guard use of SVE in SPU emulation behind a check that the SVE
length is exactly 128b."

This fork gates SVE by presence, through `arm64_spu_feature_mode` and
`utils::has_sve()`. It does not gate by length. Snapdragon 8 Gen 2 has no SVE at
all, so nothing here is broken today, but the gate is the wrong shape for a part
that has SVE at a length other than 128 bits. Fix the shape when SVE work next
comes up; do not open a session for it now.

## `#18847` will collide with the `cortex-a78` pin

`AArch64: identify Apple M2 Pro/Max and use a concrete -mcpu` adds
`aarch64::get_cpu_llvm_name()`, which maps a detected SoC to an LLVM CPU name,
and calls it from `fallback_cpu_detection()`. That is the same function this fork
overrides to pin `cortex-a78`.

Two consequences. If it merges, the next core rebase touches the exact lines the
pin lives on, so read `docs/arm64/codegen.md` before resolving it. And it is a
ready-made shape for the open item 3 in `docs/arm64/armsx3-comparison.md`,
"Revisit the JIT `-mcpu`": a table that names a real core beats a pin, as long as
the name it produces is still checked against the SVE trap that put the pin there.

## `#19013` is a rebase hazard for the work landed on 2026-08-21

kd-11's `rsx: Rework blit engine texture cache operations` moves blit target
storage out of the texture cache and into the surface cache: `+1415/-984` across
`21` files, of which `texture_cache.h` alone is `+820/-907`.

The Android protected-page preflight landed on 2026-08-21 edits `texture_cache.h`
and `nv3089.cpp`, and the lock-drop dance around `prepare_guest_read()` sits in
the direct-upload path that this rework rewrites. It is a draft asking for
testers, so nothing to do now. When it merges, port the preflight onto the new
shape by intent, not by patch: the invariant is that the fault handler must not
run while this thread holds the cache lock.

## The index upload still has one scalar path, and upstream just improved the other

`#16932`, Whatcookie, open: `BufferUtils: Optimize upload_untouched_skip_restart
with AVX-512 paths`. It is x86 only and there is nothing to take.

It is worth reading anyway, because it names the function family where this fork
has an open gap of its own. `primitive_restart_impl::upload_untouched_naive` was
written branch-free here so that AArch64 auto-vectorizes it, and the comment in
`BufferUtils.cpp` explains why. `untouched_impl::upload_untouched_naive`, the
path WITHOUT a restart index, still calls the branching `min_max()` helper, and a
conditional side effect in the loop stops it vectorizing. Same file, same idea,
five lines. EmuCoreC did not fix this one either.

# ARMSX3 seventh pass, 2026-08-22: six ports, and one confirmed defect of our own

ARMSX3 is at `daed55c42`, release **0.9.4.2**. That is **38 commits** past the
`82f21b16d` the sixth pass used. Upstream RPCS3 is at `3aac7d776`.

**Six changes are ported. None is measured on the device yet.**

## The one that matters: our redundant vertex program check never fired

`nv4097.cpp` read the source with `be_t<u64>` and the destination with a plain
`u64`. `copy_data_swap_u32` writes each word byte-swapped on its own, but
`be_t<u64>` swaps all eight bytes, so it also EXCHANGES the two words. The
comparison was therefore `(w0,w1)` against `(w1,w0)`, and it agreed only when
`w0 == w1`.

So the check was dead. Every transform program upload set
`vertex_program_ucode_dirty`. That forces a vertex program re-analysis, a program
cache hint drop and a full transform constant re-upload, **on every draw**, on the
RSX thread.

The fix is `std::rotl<u64>(..., 32)` on both reads. It is two lines.

**This is ARMSX3-original, not upstream.** Their `e13fc184f` is not in
`RPCS3/rpcs3` master, and upstream still carries the defect. They lost the hunk
once themselves, in their ROP remap merge, and restored it in `c6a0878a9`.

**The reach here is unmeasured.** The cost is per draw, so the size depends on the
title. Do not quote a number until one is taken.

## Also ported

| change | source | what it does here |
| --- | --- | --- |
| DP3 precision | rpcs3 `3aac7d776` | adds `FUNCTION::DP3_PRECISE`, an `fma` chain, used when the instruction asks for REAL precision and Shader Precision is ultra |
| Flat shading | rpcs3 `b97f4bd8d` | `NV4097_SET_SHADE_MODE` now reaches the shaders. VK gets `VK_EXT_provoking_vertex` with `provokingVertexLast`; GL already defaults to that convention |
| Savestate resume guard | ARMSX3 `a46dae38b` | `Resume()` refuses while `m_emu_state_close_pending` is set |
| NP Ethernet address | ARMSX3 `b2caae9da` | derives a locally administered MAC from Console PSID on Android |

**Two of these needed a rewrite, not a copy.**

The NP one reads `g_cfg.sys.console_psid` as one `u128` in their tree. This tree
holds two `u32` fields, `console_psid_high` and `console_psid_low`, and it has no
`derive_mac_from_psid` helper, so the composition here is local code.

The flat shading one lands on `VKPipelineCompiler`, where this fork already has
the extended dynamic state work. Their `op_flags` carries
`SEPARATE_SHADER_OBJECTS = 4`; this tree has no such flag, so
`USE_LAST_PROVOKING_VERTEX` takes the value 4 here and 8 upstream. `compiler_flags`
was `const auto` of the enum type here, so it is now a `u32` with a cast at the
call.

**The savestate guard premise holds here too, and it was checked.**
`setupCallbacks` binds `call_from_main_thread` to run its callback INLINE
(`android/src/rpcsx-android.cpp:1997`). So the kill-and-restart chain runs on the
savestate thread while the UI thread can resume underneath it, exactly as ARMSX3
describe.

## Not ported, with the reason

- **`b91c6551e` and `0262053a9`** add a runtime fence poll switch and revert it the
  same day. `git diff b91c6551e^ 0262053a9 -- rpcs3/` is **empty**. There is
  nothing to take.
- **`0a3fcc622`, the Oboe backend fix.** This tree has no Oboe backend. Android
  audio goes through `rpcsx/AudioOut.cpp` and `rpcsx/audio/`.
- **`72410638f`, cellAudio.** `rpcs3/Emu/Cell/Modules/` does not exist here. This
  file already records that the HLE modules live in `kernel/cellos/`.
- **`2f0c63ac1`, the ISO short read.** It targets `rpcs3/Loader/ISO.cpp`, which is
  absent. Our `rpcs3/dev/iso.cpp` has no such predicate. ARMSX3 also say the
  report is NOT confirmed as the cause.
- **`b9689d07f`, the pipeline cache switch.** This tree already has its own driver
  pipeline cache, `g_driver_pipeline_cache` at `VKPipelineCompiler.cpp:90`, and it
  persists to disk. Theirs is a plain env kill switch on a different
  implementation in `device.cpp`.
- **Nine commits touch only `armsx3-ui/`.** That is their Kotlin app under
  `com.armsx2` and `com.armsx3`: Flurry, the Really Slick screensavers, the
  savestate picker, the config database, the ARMv8.0 message, the frame limit row.
  Our UI is `net.rpcsx`. None of it transfers.

## Deferred: the LSFG frame generation port, 20 commits

`e05ea4d21` and the nineteen commits after it add **35 files and about 324 KB**,
plus 264 insertions across seven existing VK files. `VKPresent.cpp` takes 145 of
them, `swapchain.cpp` 61, `device.cpp` 48.

It is written against their VK backend. Ours has diverged: we call through
`VK_GET_SYMBOL()`, we keep our own pipeline cache, we carry the RSX auditor hooks,
and we hold the extended dynamic state pipeline key work.

It is also two days old. Eighteen fix-ups landed on it in one day, and one of them
reverts the single-submit restructure. Wait for it to settle.

# CORRECTION: upstream did NOT fix Eternal Sonata

**Checked 2026-08-22, because a report said the title was fixed.** It is not, and
the fix that exists repairs a defect this tree never had.

`RPCS3/rpcs3` holds **zero** commits that name Eternal Sonata. What closed on
2026-08-03 is issue "graphical glitches with flowers/grass", and PR **#19101**
closed it. That merged as `4214dff35`, "rsx: Apply alpha test for all primitive
types".

**It repairs a regression that upstream introduced.** #17862 moved the alpha test
and the alpha-to-coverage flags into the non-point-sprite branch of
`get_current_fragment_program`. #19101 moves them back out.

**This tree predates #17862 entirely.** `get_current_fragment_program` here has no
alpha test handling at all. This fork sets the alpha test in a ROP control
uniform, in `fill_fragment_state_buffer` at `RSXDrawCommands.cpp:658`, and it does
not gate that on the primitive class. So the defect cannot occur, and the fix has
nothing to attach to.

**Three Eternal Sonata issues stay OPEN upstream:** a crash on build
`0.0.42-19697-652cf60b` (2026-08-04), "Freezing and Crashing" (2026-06-09), and
"Triangle Menu Not Opening" (2026-03-20).

**So do not read "Eternal Sonata is fixed" as an upstream result.** Whether the
flowers and grass render correctly HERE is a separate question, and only the
device answers it.

# A correctness fix on a hot path needs a COST, not only a reason

**Found 2026-08-22, from a user report of about 10 FPS lost in 3D scenes.** This
is a new failure class for this file. Every entry above is about a claimed WIN
that did not survive. This one is about a claimed COST that nobody priced.

`21493f1e1` added `prepare_guest_read()` and `prepare_guest_write()` to resolve
RSX-protected pages from normal thread context. The reason is good, and the fix
stays: a protected range that faults inside `memcpy()` can fault a second time
inside the handler, and Android then kills the process with no tombstone.

`prepare_guest_access` walks the range **one 4 KiB page at a time**. Each step
costs a `vm::check_addr` **and** an atomic load. Its comment said "one atomic
load for each page", which undercounts the work by half.

**The size of the ranges is what makes it expensive, and nobody looked at the
call sites.**

| call site | what it passes |
| --- | --- |
| `texture_cache.h:2562` | a whole surface, `tex_size` |
| `VKTexture.cpp:1059` | the whole `layout.data.size()` |
| `nv3089.cpp:593` | the blit source |
| `SPUThread.cpp`, `do_dma_transfer` | **every SPU MFC put** |

A 2560x720 surface is about 1,800 steps for one upload. The SPU site is worse:
`process_mfc_cmd` is **20.13% of gameplay** in this fork's own profile, and this
file already records that Eternal Sonata "pounds 16 KB transfers".

## The fix, and the first fix which was wrong

Count the protected pages **per 1 MiB region**, and skip the walk for a region
which holds none. That reads 256 times fewer counters than the walk reads pages:
one counter for a 16 KiB DMA, eight for a 7 MiB surface. A zero region cannot
hold a protected page. A non-zero region falls back to the exact walk, so the
crash fix stays intact.

**A global "is anything protected" flag was written first, and it was useless.**
The texture cache keeps pages protected through most of gameplay, so the flag is
set nearly always and every walk would still run in full. The coarse map works
because it asks about the range, not about the process.

## The rule this adds

Before you put work on a hot path, write down the cost the same way this file
already demands for a win:

1. **Per call, in operations.** Not "cheap". Count the loads and the branches.
2. **Times the call rate.** Get the rate from the profile, not from a guess.
3. **Against the real arguments.** Open each call site and read what it passes.
   A loop priced per page is priced wrong when the caller hands it a surface.
4. **Then measure it.** A correctness fix still has to show its cost on the
   device before it ships.

The reach question this file already asks about wins — *does this run, and how
often* — applies exactly the same to costs. It was never asked here.

## And a guess that cost a round trip

I blamed flat shading first, because it was the newest change that touched a
shader key. I gated it, rebuilt, installed, and measured **14.70 FPS median**.
The gate changed nothing. The evidence for the real cause was in the call sites
the whole time, and reading them took minutes.

**Read the code before you theorise about it.** Two of the three suspects were
excluded by reading, not by running: DP3_PRECISE needs Shader Precision ultra
and this device reads High, and `copy_data_swap_u32_cmp` is the NEON form on
ARM64 rather than a scalar fallback.

## RESOLVED by a bisect: 21493f1e1 alone, 29.67 FPS against 14.84

**Eternal Sonata, one 3D route, the same clock point, 2026-08-22.**

| build | median | FPS |
| --- | --- | --- |
| `bd2c13249`, the parent | 33.70 ms | **29.67** |
| `21493f1e1`, the preflight | 67.39 ms | **14.84** |
| `21493f1e1` + a per-region skip | 50.58 ms | 19.77 |
| preflight off by default | 33.71 ms | **29.67** |

**One commit halved the frame rate.** Four builds found it. Hours of reading did
not, and produced four wrong answers on the way.

### The cost is the HANDLER, not the probes

Both earlier fixes attacked the page probes and both fell short, because the
probes are not the cost. The preflight calls `g_access_violation_handler` for
every protected page in a range BEFORE the copy, and that handler invalidates the
texture cache. A counter read **20,177 calls in two minutes**.

Natural faulting, which is what the parent commit does, enters the handler only
for a page the copy really touches. A texture upload hands the preflight a whole
surface and targets protected memory by definition, so the eager form multiplies
the invalidations. Region skipping cannot help for the same reason: an upload has
no clean regions to skip.

`debug.rpcsx.thor.guest_preflight = 1` restores it. Default 0.

**The crash it prevented is real and is now unguarded by default.** A protected
range which faults inside `memcpy()` can fault again inside the handler, and ART
kills the process with no tombstone. A correct and fast form would resolve a
whole protected RANGE with one handler call. That is not written. Do not record
the crash as covered.

## BISECT FIRST. It is four builds and it cannot lie to you.

**This is the most useful thing in this file.** The session that found the defect
above spent hours on inference and produced four confident wrong diagnoses, each
killed by a number:

| blamed | how it died |
| --- | --- |
| flat shading | gated off, rebuilt, measured 14.70 FPS. No change. |
| extended dynamic state | a boot with the property set was still slow. |
| thermals | a cooled retest was still slow, and the FASTEST arm of the day started at 84.3 C. |
| **the page walk, cleared by me** | I priced 17M probes against 115 handler calls and called it a fraction of a percent. The bisect says 15 FPS. |

The last row is the worst, because it is the same error the defect itself was:
**pricing a hot loop by reasoning instead of measuring it.** It was made in the
same session as the section above which warns against it.

A bisect over a week of commits is four builds, about ninety seconds each. Take
the known-good commit the user names, build it, measure the same route, and
halve the window. Do this BEFORE reading any code. Reading is for after the
commit is named, when it explains a fact rather than proposing one.

## A guard, because a mirror pair with no check is a trap

`tools/check_checksum_mirror.py` fails when the SPU block checksum IR and its
host mirror disagree, and when either side folds a pair with equal weight.

Both failure modes were reconstructed and the check was shown to FAIL on each
before it was trusted. A check which has never been shown to catch anything is
worth nothing, and this file already says so about five earlier searches.

## Three method errors from the same session

1. **A stripped `.so` has no function names.** Verifying a fix by grepping the
   shipped library for `mm_range_has_protection` returned zero, and so did a grep
   for `mm_is_accessible`, which certainly exists. Grep for a STRING LITERAL you
   added on purpose. Sixth entry in this file for that class.
2. **An emulator clock does not pin a scene.** `tools/thor_dynamic_state_ab.sh`
   waited for a fixed clock and compared a title MENU against a 3D scene, then
   read 29.40 against 14.84 FPS as workload variance. That produced a retraction
   of a real regression. **Pin the scene, not the timestamp.**
3. **A harness which sets a property must restore it.** The A/B left
   `vk_dynamic_state_off=1` behind, and the next measurement was nearly read as a
   default-build result.


## Why the manual is not the place to start here

The instruction to "read the ARM manuals and find places to improve" is the
method this file already records as failing. **Ten manual-derived predictions
were measured, and ten were refuted.** The manuals were right every time; the
inference on top of them was not.

What found this defect was the opposite move, and it is the one the audit ledger
already recommends: **establish reach first**. Open the call sites, read the
argument sizes, and multiply by the rate from the profile. That took minutes and
needed no device. Go to `docs/hardware/` when a specific instruction choice is
already known to be hot, never to hunt for one.

# READY TO TEST, deliberately NOT shipped: the dead call on the SPU DMA path

**Written, built, and reverted on 2026-08-22 because it has no number.** The whole
day started with changes which shipped on reasoning, so this one does not.

`do_dma_transfer` calls `rsx::prepare_guest_write(eal, args.size)` for **every SPU
MFC put**. With the preflight off by default that call does nothing but return
false. **LTO is off in this build**, so it is a real, non-inlinable call across a
translation unit, and `process_mfc_cmd` is **20.13%** of gameplay in this fork's
own profile. This file already records the same shape costing real time once:
`copy_data_swap_u32` "fell through to a scalar loop behind a non-inlinable
function pointer with LTO off".

The change is three edits and about fifteen lines:

1. `RSXOffload.cpp` gets `bool g_guest_preflight_enabled`, set once from the
   property. Namespace scope, so it is zero-initialised to false, which is the
   default, and the RSX library loads before any SPU thread exists.
2. `RSXOffload.h` gets `inline bool guest_preflight_enabled()` reading it.
3. `SPUThread.cpp` guards the call: `if (rsx::guest_preflight_enabled() && ...)`.

**Predicted magnitude: unknown, and possibly zero.** A well predicted branch on a
cached bool is cheap and the call it replaces was also cheap. Write the number
down before believing it, per the rule above.

**How to test it properly.** Not on the Eternal Sonata opening. The attempt on
2026-08-22 sampled emulator clock 4:50 against a 3:19 baseline and read 3.4 FPS
against 29.65, which looks like a catastrophic regression and is two different
scenes. Use `tools/thor_gameplay_ab.sh` on a savestate, which restores the same
frame for both arms.

# The first gameplay levers ever measured here, and a capped scene lies to you

**2026-08-22.** Two on-by-default levers were measured on a running title for the
first time in this fork. Both keep their defaults, and the way the numbers move
is the lesson.

## At the frame cap, only CPU can move

Eternal Sonata at a pinned clock runs at 29.67 FPS, which is the cap. Four
interleaved arms each:

| lever | CPU | frames |
| --- | --- | --- |
| `spu_selfloop_park` 100 against 0 | 36-38 against 46-48 | identical |
| `getllar_busy_percent` 0 against 100 | 35-37 against 39-42 | identical |

So the park is 22% less CPU and the GETLLAR sleep is 13% less, at the same
output. **Frames cannot show either.** A capped scene has no headroom to give
back, so a lever which trades CPU for latency looks free. This file already says
"a capped frame rate hides latency"; this is that, measured.

## Take the cores away and the same lever moves FRAMES

Six spinner processes, identical in both arms, `tools/thor_starve_ab.sh`:

| `spu_selfloop_park` | frames |
| --- | --- |
| 100, the default | **11.86, 11.87** |
| 0, spin | 8.48, 9.88 |

**The park is worth 20 to 40% MORE frames once the CPU is scarce**, and the arms
separate cleanly.

**The prediction was the opposite and it was wrong.** Parking costs about 10 us of
wake latency, per `bench-results.md`, so the expectation was that removing the cap
would expose that cost as lost frames. It does not. Spinning burns cores which the
RSX and PPU threads need, and under contention that is far worse than a wake.

Note the spread as well: `park=100` repeats to 0.01 FPS while `park=0` scatters
across 1.4 FPS. A spin competing for contended cores is not reproducible; a park
is.

## What this means for the next A/B

**Measure at the cap AND under starvation.** They answer different questions, and
either one alone is misleading. The cap says what a lever costs in CPU. Starvation
says what it is worth in frames when the machine is short, which is the state a
demanding scene puts it in.

Starvation is a proxy for a heavy scene, not a substitute. It makes the CPU scarce
without making the guest do more work. Treat a result from it as evidence about
CPU pressure, not about a specific game scene.

**Clean the spinners up from the HOST, on every exit path.** This file records
twelve orphaned `yes` processes running for hours at about 430% CPU after a
dropped link, contaminating a whole session. `tools/thor_starve_ab.sh` traps EXIT,
INT and TERM, and sweeps on entry as well.

# The code from 2026-08-20 to now costs nothing under load, measured build against build

**A report of "slower than last week" is a comparison between two builds, so
measure that, not a list of suspects.** Four interleaved arms, six spinners each,
installs alternating inside one session:

| build | frames |
| --- | --- |
| `bd2c13249`, 2026-08-20 | 11.86, 11.87 |
| HEAD, after twelve commits | 11.86, 11.87 |

**Identical to 0.01 FPS.** The rig is not blind: the same starvation setup
separated `spu_selfloop_park` by 20 to 40% earlier the same day. It would have
shown a regression of that size and there is none.

So the whole 08-20 to now window is exonerated for CPU-bound frame cost, and that
covers every change made today.

## Why this test beats hunting levers

Every lever tested is a hypothesis somebody thought of. This one tests everything
which changed at once, including what nobody suspected. It cost two builds and
four arms, against a day of dead hypotheses: flat shading, extended dynamic state,
thermals, the guest page walk, and both parking defaults, each killed by its own
measurement.

**Reach for it FIRST when a report is shaped as "it used to be faster".** Build
the named good commit, save both APKs, and alternate installs. If the builds
separate, bisect. If they do not, the code is not the cause and the answer is in
the scene, the settings, or the device.

## Interleave the INSTALLS, not just the arms

`tools/thor_build_ab.sh` alternates installs inside one session, because the
absolute number drifts. The same configuration measured 11.86 FPS in one session
and 9.89 in another, while repeating to 0.00 inside each. Two builds compared
across sessions would have produced a confident 20% regression which was only
drift, which is the 4:50 against 3:19 error in another costume.

# The Eternal Sonata intro cannot show a performance change, and that limits every
# negative result taken on it

**Profiled 2026-08-22: 24 samples of 10 s each, across four minutes of the intro.**

    min 29.65   max 29.67   spread 0.02 FPS

It never leaves the cap. Not once, anywhere in the sequence.

And it is not idle while it does that: 3.0 cores busy and 72.7 C at the sample
point. It is working, and it still has enough headroom to hold 30 FPS whatever
changes underneath it. This file records Eternal Sonata GAMEPLAY at **5.26 cores**,
so the intro is about 57% of the real load.

## What that costs the results measured on it

Everything measured there which came back "no difference" is a statement about a
scene with spare headroom, and says much less than it appears to about a scene
without. On 2026-08-22 that covers flat shading, extended dynamic state, the guest
page walk, both parking levers at the cap, and the build against build comparison.

The proof is in the one case where the cap was removed. Six spinners took the
cores away, and `spu_selfloop_park` immediately separated by 20 to 40% on frames,
having looked free at the cap. The cap was hiding it.

## The rule

**Before believing a negative result, show the workload could have produced a
positive one.** Two cheap checks:

1. **Is it capped?** A flat 29.6x across every sample means frames cannot move, so
   frames prove nothing. Read CPU instead, or remove the cap.
2. **Is it loaded?** Compare cores busy against the figure for real gameplay. The
   intro is 3.0 against 5.26. A workload at half load has headroom to absorb a
   regression without showing it.

`tools/thor_starve_ab.sh` removes the cap by taking the cores away. It is a proxy
for CPU scarcity, not for a specific scene, and it is the only workload on this
device so far which has ever moved frames for a lever.

**A day of clean negative results is a warning about the workload, not a verdict
on the code.**

## Load state crashed four different ways, and all four were one race

2026-08-22. `loadState()` killed the process. Fixing it took four changes,
because each fix let the teardown get further and uncovered the next fault. The
last one named the cause.

The chain, in the order it was found. Every line is from a real run:

| # | Symptom | Site |
|---|---------|------|
| 1 | `Scudo ERROR: invalid chunk state` | `llvm::Module::~Module`, from `jit_module_manager::operator=` |
| 2 | `Segfault reading location 0x8` | `fixed_typemap.hpp:360`, `info->thread_op`, `info == nullptr` |
| 3 | `Segfault reading 00cccccccccccccc` | `vk::descriptor_set::~descriptor_set` |
| 4 | `Segfault reading location 0x40` | `fixed_typemap.hpp:398`, `info == nullptr`, **on two threads at once** |

Row 4 is the one that named it. The main thread and the Emulation Join Thread
faulted at the same PC, inside `manual_typemap::clear()`. Two threads were
destroying one typemap.

### The cause: an empty stub

`qt_events_aware_op` in `android/src/rpcsx-android.cpp` was this:

```cpp
void qt_events_aware_op(int repeat_duration_ms, std::function<bool()> wrapped_op) {
  /// ?????
}
```

`Emulator::GracefulShutdown()` calls it to WAIT for `m_state` to reach
`system_state::stopped`. With no body there was no wait, so
`boot_last_savestate()` went on to `Emu.BootGame()` while the join thread was
still inside `Kill()`. Boot then ran `Emulator::Init()` -> `g_fxo->reset()` ->
`clear()` at the same time as the join thread ran its own.

`Kill()` even says what it assumed, at `System.cpp:3834`:

```
// Final termination from main thread
CallFromMainThread(...)
```

It is not on the main thread here. This port binds `call_from_main_thread` to
`cb()`, an inline call on whichever thread got there. So the "main thread only"
teardown runs on the join thread, and the guarantee that made it safe is gone.

### What this costs to find, and the cheaper route

Four build-install-measure rounds. The cheaper route was available at round one:
**two threads in the same function is a race, so look at what was supposed to
serialize them.** Rows 1, 2 and 3 all had that shape and none of them said so,
because only one thread had faulted yet.

### The rule

**When a port stubs out a synchronisation primitive, every caller that depended
on it is now unsynchronised, and none of them will say so.** The stub compiles,
returns, and the callers keep their comments about guarantees they no longer
have. Grep the port layer for empty bodies before trusting a lifecycle comment.

### The other three are still real, and still fixed

None of them are reverted, and none are redundant:

- `jit_module_manager::operator=` destroyed every JIT and left the entries in
  the map, and took no bucket lock while walking a map that `get()` and
  `remove()` both lock. Now clears under the lock.
- `manual_typemap::clear()` and `save()` sized their loops from the `m_init`
  flags and walked the `m_info` array. `reset()` fronts that array with a null
  sentinel, and `iterator::operator++` already treats that null as the end.
  Counting the entries cannot overrun. `clear()` is the measured one; `save()`
  had the same shape and was fixed with it.
- `descriptor_set::~descriptor_set` reached `g_fxo->get<T>()`, which is
  documented "may be uninitialized memory" and does not check `m_init`. Now
  guarded on `is_init<T>()`.

## Savestates: the register context was never being written

2026-08-22, after the crash chain above was fixed. The process survived a load
and the savestate restored its objects, threads and file descriptors. Then every
restored PPU thread came back with `cia=0x0` and zeroed registers, and all 13
faulted within two milliseconds:

```
PPU: Loading PPU Thread [0x1000000: main_thread]: cia=0x0, ...
VM: Access violation reading location 0x0 (unmapped memory)   x13
```

The read is `vm::read32(ppu.cia)` in the savestate command queued by the
`ppu_thread(utils::serial&)` constructor. With `cia` zero it fetches the
instruction at address 0.

The cause, in `ppu_thread::serialize_common`:

```cpp
// ar(gpr, fpr, cr, fpscr.bits, lr, ctr, vrsave, cia, xer, sat, nj, prio.raw().all);
```

**The line that serializes the whole register context was commented out.** A
savestate kept no gpr, no fpr, no cr, no lr, no ctr and no cia. Upstream RPCS3
has the line live. It arrived commented out with the RPCSX core vendoring, and
the reason it stopped compiling is visible in the code: the RPCSX restructure
moved the registers into `PPUContext` and flattened upstream's `xer` struct into
`xer_so`, `xer_ov`, `xer_ca` and `xer_cnt`. Naming those four restores it, and
the contents match one for one.

After the fix, restored threads carry real addresses (`0x31c188` for the
semaphore waiters, `0xd0f17c` for `_fs_aio_thread`, `0xca833c` for
`_gcm_intr_thread`), which are the same addresses the live session was at. No
access violation, no verification failure, and `loadState()` returns true.

### RESOLVED: the restore did not resume, and it was a self-deadlock

The savestate loaded and the correct frame was on screen, but nothing advanced.
`rsx::thread` sat at 0% and the SurfaceFlinger timestamp never moved.

The chain, from instrumented runs:

```
lv2_obj::sleep()             -> lock_guard{g_mutex}          lv2.cpp:1710
  sleep_unlocked()           -> "Final Thread"
    CallFromMainThread(...)  -> runs INLINE on this thread
      FinalizeRunRequest()
        make_scheduler_ready() -> awake_all() -> awake() -> lock_guard(g_mutex)
```

`g_mutex` is a `shared_mutex` and does not nest, so the thread deadlocked while
holding it. `FinalizeRunRequest` logged its entry and never reached its
`compare_and_swap_test(starting, running)`, so the state stayed `starting`. RSX
waits on `IsPausedOrReady()`, which is `m_state >= paused`, and `starting` is 7
while `paused` is 4, so that is true for `starting` too. RSX span for ever:

```
Thor resume: rsx still waiting, spins=52000 running=1 paused_or_ready=1 dma=0x40100000
```

The call site carried the warning already: *"It uses lv2_obj::g_mutex, run it on
main thread"*. Upstream earns that, because its `CallFromMainThread` queues onto
the Qt main thread and runs after `sleep()` drops the lock. This port binds
`call_from_main_thread` to a direct `cb()`, so the queueing that made the comment
true is gone. **Same root cause as the load-state crash chain, in a second
place.**

Fixed by running the finalize from a detached thread, which blocks on `g_mutex`
until `sleep()` releases it and so keeps upstream's ordering.

After the fix, a savestate restores into live 3D gameplay: 25.7 to 25.9 FPS,
`rsx::thread` burning 5.5 s of CPU per 10 s wall, the process at 3.1 cores.

### Do not trust SurfaceFlinger --latency alone for liveness

The last check said FROZEN while the game was demonstrably running at 25.74 FPS
on its own overlay. The scene was a dialogue box, so the presented image barely
changed and the latency buffer did not move the way the parse expected. **Read
CPU time from `/proc/<pid>/task/<tid>/stat` instead**: `rsx::thread` going from
2129 to 2682 jiffies in ten seconds is not ambiguous.

### Back up the savestate before capturing one

A capture overwrites `$TITLE_1_0.SAVESTAT.zst` in place. There is no second slot
and no `.bak`. A capture taken to test the load path **destroyed the existing
savestate for that title**, and nothing on the device kept a copy. Copy the file
somewhere else first.

### Two method notes from this hunt

1. **Check the path before blaming the data.** "Firmware is not installed" was
   taken at face value and written into this file as fact. One `find` for
   `dev_flash` would have shown it sitting in `config/`.
2. **Instrument before fixing an accounting bug.** The overlay showed a short
   count on three separate runs, which is strong evidence for a lost update. The
   counters were correct every time. One log line settled what three screenshots
   could not.

# There is now a repeatable gameplay workload, and it is BELOW the cap

2026-08-22. Every warning above about capped scenes was written because the only
workloads reachable here were the Eternal Sonata intro and a title screen, both
pinned at 29.6x with frames that cannot move. Savestate load now works, so that
constraint is gone.

**Capture once, then restore the same frame for every arm.** Both halves are
reachable over adb without touching the device:

```sh
# capture (overwrites the single slot for that title - back it up first)
adb shell am broadcast -a net.rpcsx.THOR_DEBUG_SAVESTATE     -n net.rpcsx.easy/net.rpcsx.utils.ThorDebugSaveStateReceiver

# restore, into a session already running that disc
adb shell am broadcast -a net.rpcsx.THOR_DEBUG_LOADSTATE     -n net.rpcsx.easy/net.rpcsx.utils.ThorDebugLoadStateReceiver
```

The restored Eternal Sonata scene measures **25.7 to 25.9 FPS at 3.1 cores**.
Below 30. That is the whole point: a lever which costs frames can no longer hide
behind the cap, and the two cheap checks in the rule above ("is it capped?", "is
it loaded?") now both pass on a workload that takes one command to reproduce.

## Read liveness from /proc, not from SurfaceFlinger

`dumpsys SurfaceFlinger --latency <layer>` reported FROZEN for a session which
its own overlay showed running at 25.74 FPS. The scene was a dialogue box, so the
presented image barely changed and the latency buffer did not advance the way the
parse assumed. It also returns a fixed 126-entry buffer, so a stale read looks
exactly like a real measurement.

**Use thread CPU time instead.** Fields 14 and 15 of
`/proc/<pid>/task/<tid>/stat` are utime and stime in jiffies:

```sh
# rsx::thread went 2129 -> 2682 jiffies in ten seconds. Not ambiguous.
```

For the whole process, `/proc/<pid>/stat` delta over a fixed window gives cores
directly: 3119 jiffies over 10 s is 3.1 cores. That is the discriminator this
file has been asking for, and it does not care whether the picture changed.

## The A/B that measured nothing, twice, and what caught it

Two separate ways to measure nothing showed up in one session on the new
savestate harness. Both produced clean, plausible, self-consistent numbers.

**1. The lever was never applied.** `apply_arm` fed the spec into a loop like:

```sh
printf '%s' "$1" | tr ';' '
' | while read -r kv; do ...; done   # WRONG
```

`printf '%s'` writes no trailing newline, so `read` hits EOF on the only line and
**the loop body never runs**. Every arm ran with the property unset. The two arms
then agreed beautifully, because they were the same configuration:

```
default          cores 3.097, 3.215, 3.259     fps 27.62 - 27.78
ladder=64        (identical, because it was never set)
```

What caught it was the RSX FIFO counter line being ABSENT from the log. With the
lever genuinely on, the same scene reads `idle_polls=10076786` and climbing by
about 500k per 10 s report. A lever with no reach and a lever with no effect look
identical; only the counter separates them, which is why perf_monitor now prints
that line when EITHER the park or the ladder is on.

Two rules from it:

- **Read the property back off the device and print it with every arm.** The
  harness does this now. A silent no-op must not be able to pass as a result.
- **Never edit a script while it is running.** bash reads a script incrementally,
  so editing the file mid-run made it die with `unexpected EOF` at a line that had
  no syntax error. Run measurements from a frozen copy.

**2. The accidental null A/B is the useful part.** Because both arms were the same
configuration, that broken run measured this harness's own noise floor:

| metric | spread over 3 samples of ONE configuration |
| --- | --- |
| whole-process cores | 3.097 to 3.259, about **+/-5%** |
| FPS | 27.62 to 27.78, about **+/-0.6%** |

**+/-5% on cores is the bar any CPU claim has to clear here.** That number also
says to measure the THREAD a lever targets, not the process: `rsx::thread` is 0.51
of 2.90 cores, so a lever saving 30% of that thread moves the process total by 5%
and vanishes into the noise. Measured on the thread itself the same saving is 30%.
The harness now reports both, and `THREAD_MATCH` selects which thread.

**Run a null pair before believing any arm.** This file already said that about
Folklore's title screen. It is now measured for the savestate workload too.

## The RSX FIFO pause ladder: no benefit, and a warning about the power probe

`debug.rpcsx.thor.rsx_fifo_pause_ladder=64` keeps one `sched_yield` per 64 empty
FIFO polls and spends the other 63 in `rx::pause()`. It has enormous REACH on the
restored savestate scene: `idle_polls=10076786`, climbing about 500k per 10 s, so
the ring really is empty that often and the lever really does run.

Two interleaved rounds on that scene:

| arm | FPS | cores | range | power samples |
| --- | --- | --- | --- | --- |
| default | 27.64 | 3.234 | 3.178 - 3.290 | 7545, 7016 mW |
| ladder=64 | 27.64 | 3.295 | 3.243 - 3.346 | 10351, 6593 mW |

**No CPU benefit.** The ladder is 1.9% worse on cores, which is inside the +/-5%
noise floor, and the ranges overlap. Frames are identical. Not shipped.

There is a mechanical reason to expect no win: `rx::pause()` on ARM64 is `YIELD`,
which `docs/arm64/bench-results.md` measures at 0.36 ns, the same as a `NOP`. The
ladder therefore trades a syscall that lets the core deschedule for spinning at
full issue rate. It moves time from kernel to user, not off the CPU.

### The power probe is NOT usable while the charger is attached

The first ladder sample read 10351 mW against 7545 mW for default, which looked
like a 37% power regression and was reported as one. **The second sample of the
same arm read 6593 mW, below both default samples.** One arm, one configuration,
6593 to 10351 mW.

`ichg_fb` was checked on every sample and never exceeded the charging threshold,
so the guard did not fire, and the spread is still larger than any effect worth
measuring. Do not quote power from this rig while it is plugged in.

**Establish a power noise floor with a null pair before quoting a power number,
exactly as was already required for cores.** Until then CPU at fixed frames is
the discriminator here, because that one has a measured noise floor.

# The first symbol-level profile of real gameplay on this device

2026-08-22. `simpleperf`, 25 s, 85,615 samples, 0 lost, on the restored Eternal
Sonata savestate during its active window. This is a RelWithDebInfo core: the
`debuggable` flag no longer drags `CMAKE_BUILD_TYPE` to Debug, so the profile
describes the build that ships.

Recipe, because `perf_event_paranoid` blocks the direct form:

```sh
adb shell run-as net.rpcsx.easy /system/bin/simpleperf record     -p <pid> --duration 25 -f 1000 -g -o /data/data/net.rpcsx.easy/perf.data
```

Symbols come from a symfs tree mirroring the on-device path and holding the
UNSTRIPPED `librpcsx-android.so` out of
`app/build/intermediates/cxx/RelWithDebInfo/*/obj/arm64-v8a/`. The host
`simpleperf.exe` ships in the NDK under `simpleperf/bin/windows/x86_64/`.

## Where the cycles are

| by thread | share |
| --- | --- |
| `rsx::thread` | 14.51% |
| six SPU threads | 65.49% total, 10.4 to 11.8% each |
| PPU (three threads) | 17.03% |

| by object | share |
| --- | --- |
| `unknown` (JIT-generated guest code) | 38.10% |
| `librpcsx-android.so` | 37.31% |
| `[kernel.kallsyms]` | 15.93% |
| Turnip driver | 3.94% |
| libc | 3.92% |

| top symbols | share of ALL cycles |
| --- | --- |
| `spu_thread::process_mfc_cmd()` | **12.69%** |
| kernel, one address | 8.73% |
| `vm::writer_lock::writer_lock(...)` | **8.60%** |
| `vm::passive_lock(cpu_thread&)` | 3.13% |
| `memcpy_opt` | 2.78% |
| `vk::wait_for_event` | 2.12% |
| `rsx::thread::run_FIFO()` | 1.03% |
| `sched_yield` | 0.76% |
| `shared_mutex::imp_lock` + `imp_lock_shared` | 0.98% |

**VM range locking is 12.7% of everything**, counting `writer_lock`,
`passive_lock` and the two `shared_mutex` entries. That rivals the MFC command
handler itself, and all six SPU threads contribute to it about equally.

## Two things this kills

**The RSX is not spin-bound, it is GPU-bound.** Inside `rsx::thread`:
`vk::wait_for_event` 14.61%, `memcpy_opt` 11.85%, Turnip 14.76%,
`run_FIFO` 7.13%. `sched_yield` is 0.76% of the whole process. That is why the
FIFO pause ladder changed nothing: it optimizes a spin that is not where the time
goes. **Do not spend more arms on RSX idle-poll levers.**

**The SPU cost is reservations and DMA, not the interpreter.** `process_mfc_cmd`
plus VM locking is about a quarter of all cycles.

## Where the writer lock comes from

`do_putlluc` in `SPUThread.cpp`. `g_use_rtm` is false on ARM64, so with
**`Accurate SPU Reservations: true`** (the upstream default, and what this device
runs) every reservation store takes the hard path:

```cpp
vm::writer_lock lock(addr, spu ? spu->range_lock : nullptr);
```

The constructor spins `busy_wait(200)` up to 100 times before its first
`std::this_thread::yield()`. Six SPU threads doing that against one range-lock
bitmap is the 8.60%.

Line 5541 of that function shows the escape: when accurate reservations are OFF
the lock is skipped entirely. That is a correctness setting, not a free switch, so
it needs measuring against a title that actually stresses reservations rather than
being flipped on faith. **Unmeasured. It is the highest-value open lever here, and
the spin count inside the constructor is the safer thing to try first.**

# Transformers: War for Cybertron, and why one FPS number is worthless here

2026-08-22, BLUS30357, measured on device. This title was reported as "so slow".
The frame rate swings so widely by scene that any single measurement of it is
meaningless, and the first one taken was badly misleading:

| scene | frame rate | cost |
| --- | --- | --- |
| engine cutscene, uncapped | 120-133 FPS | 3.74 cores |
| engine cutscene, 30 cap | 29.8-30.0 FPS | 2.81 cores |
| 3D gameplay, uncapped | 40.4 FPS | 85.9% total CPU |
| while a shader compiles | **2.0 FPS** | overlay reads "Compiling shaders" |

The first profile taken here landed on a cutscene, read 133 FPS, and produced the
conclusion "this title is not slow, it only has a cold-compile problem". **That was
wrong**, and the thing that disproved it was letting a second run continue into
actual gameplay, where the same build reads 2.0 FPS mid-shader and 40 FPS after.
A profile of a cutscene is not a profile of a game.

## It gets to 94 C, and nothing stops it

Uncapped 3D gameplay at 85.9% CPU took the CPU thermal zones to **88-94 C**:

```
94C cpu-1-3   93C cpu-1-9   92C cpu-1-5   91C cpu-1-7   89C cpu-1-8
```

They fell to 53 C within 25 s of force-stopping, so that is emulator load and
nothing else. The SoC and Android's thermal HAL still throttle in hardware, so
this is not a device about to be destroyed; it IS a device spending gameplay in
thermal throttling, which makes the game worse as well as hotter.

**The 72 C guard this file refers to elsewhere does NOT cover gameplay.**
`thermal_headroom_probe` is sampled at exactly one site,
`sample_before_ppu_compile` in PPUThread.cpp, so it bounds the PPU compile phase
only. There is no thermal feedback of any kind on the running game. That is a real
gap and it is why nothing intervened at 94 C.

## What the profile says, and how different it is from Eternal Sonata

25 s, 91,176 samples, 0 lost, on the 133 FPS cutscene:

| symbol | Transformers | Eternal Sonata |
| --- | --- | --- |
| guest JIT code, one SPU thread | **29.37%** | - |
| `rsx::thread::run_FIFO()` | **10.71%** | 1.03% |
| `vm::writer_lock::writer_lock` | 1.24% | **8.60%** |
| `spu_thread::process_mfc_cmd()` | 1.05% | **12.69%** |

**There is no shared lever.** Eternal Sonata is reservation and VM-lock bound;
Transformers is doing real guest SPU work and RSX FIFO processing. Do not copy
one title's Core tuning to the other, and do not expect the `vm_writer_lock`
spin knob to do anything here.

## The ten minute first boot is real, and it is one-time

Cold, this title compiles PPU LLVM modules of 4,000 to 9,500 functions each
across six workers at 100% CPU and does not render a frame for **585 seconds**.
The cache is reused: the second boot reached a frame in **30 seconds**. So it is
the size of this EBOOT, not a misconfiguration, and `Max LLVM Compile Threads`
is already 0 (auto).

## The profile that ships

`GameSettingsDatabase` now carries BLUS30357: `Frame limit: 30` and
`Shader Mode: Async with Shader Interpreter`.

The cap is **for heat, not for speed**. The interpreter is for the 2.0 FPS stall:
the default Async Shader Recompiler stalls the frame until a shader is ready,
while the interpreter draws immediately and compiles behind it.

**NOT VERIFIED:** whether uncapped frames mean the SIMULATION runs fast. Frame
rate and game speed are different things, and only frame rate was measured. Do
not repeat the claim that this title "runs at 4.3x speed" uncapped; it was an
inference, it was challenged, and it was never tested.

## The thermal shape, measured properly

The first thermal reading here took the max across every zone without naming it,
which is not a measurement. Named, sampled every 12 s from a 45 C idle:

| t | hottest zone |
| --- | --- |
| idle | 45 C |
| +12 s | 77 C `cpu-1-9` |
| **+24 s** | **94 C `cpu-1-5`** |
| +36 s | 80 C `cpu-1-3` |
| +48 s | 69 C `cpu-1-8` |

**It peaks at 94 C and the SoC then throttles it back to 69-80 C on its own.** So
the device is not being destroyed, and saying so would be alarmist. What it IS
doing is spending gameplay in thermal throttling, which costs the frame rate the
throttling was supposed to protect. Back to 47 C within 25 s of a force-stop.

The source is not the compiler. That run logged zero `LLVM: Compiling module`
lines. `top -H` at the peak shows **one SPU thread at 96.2%** with five more at
15-33%, which is the same shape as the profile: 29.37% of all cycles in guest SPU
code in a single thread. This is real emulation work, not spin and not overhead.

### After a guest fault it keeps burning

One run hit `VM: Access violation reading location 0xfff3...` in
`SPU[0x0000100] CellSpursKernel0` at 0:00:34 and then sat at **87-88 C for four
more minutes at 0.00 FPS**. The SPU threads keep spinning after a fatal guest
error. Nothing renders, nothing progresses, and the device stays hot until the
user notices. That is worth fixing on its own and it is not title-specific.

## A gameplay thermal guard now exists, and it does not fix Transformers

`Emu/thor_thermal_guard.h`. perf_monitor samples the CPU thermal zones every 4th
tick, about 2 s, and above 85 C the RSX flip limiter imposes 20 FPS. It applies
even when the title has no frame limit, which was the case that reached 94 C.
Off with `debug.rpcsx.thor.thermal_guard_c=0`.

**It flapped on the first attempt.** Hysteresis alone, 85 engage and 75 release,
gave more than twenty transitions in three and a half minutes:

```
ENGAGED at 85 C  ->  released at 71 C, two seconds later
```

Capping the frame rate idles the cores instantly, so the per-core sensor drops
14 C in one sample and the guard lets go before the heat has gone anywhere. Adding
a dwell, a minimum of 8 samples engaged before release is even considered, took it
to 9 transitions with engaged periods of 34 and 52 s.

**And it does not cool this title.** With the guard live and holding 20 FPS:

| t | temp | FPS |
| --- | --- | --- |
| +180 s | 87 C | 19.85 |
| **+200 s** | **95 C** | **19.60** |
| +220 s | 93 C | 19.90 |

Capped the whole time and still climbing. The heat is one SPU thread at ~96%
running guest code, and that thread is not frame-bound. The guard bounds the
render path; it cannot idle an SPU thread that spins regardless of presentation.

**The open question is that SPU thread**, not the frame rate. 29.37% of all cycles
in one thread's JIT code, and `spu_selfloop_park` is already on and already has
reach elsewhere. Whatever it is spinning on is not the self-loop the park catches.

# The first lever that actually moves Eternal Sonata's measured bottleneck

`debug.rpcsx.thor.spu_accurate_reservations` overrides the config setting of the
same name. -1/unset uses the config, 0 and 1 force it. Read once into a
namespace-scope inline const, because the caller is FORCE_INLINE on the MFC path.

The profile said VM range locking is 12.7% of all cycles, arriving through
`do_putlluc`: `g_use_rtm` is false on ARM64, so with accurate reservations ON
every reservation store takes the hard `vm::writer_lock`. Turning it off skips
that branch entirely.

Two interleaved rounds on the restored savestate, `THREAD_MATCH='SPU['`:

| arm | FPS | cores | range | SPU threads |
| --- | --- | --- | --- | --- |
| accurate=1 (default) | 27.41 | 3.348 | 3.345 - 3.351 | 1.782 |
| accurate=0 | 27.30 | 2.994 | 2.951 - 3.037 | 1.617 |

**-10.6% total CPU and -9.3% on the SPU threads at identical frame output, and
the ranges do not overlap.** That is the first lever tried here that clears the
+/-5% noise floor. The FIFO pause ladder and the writer-lock spin count both did
not, and both were rejected for it.

## Why it is NOT a default yet

It is a CORRECTNESS setting. Upstream defaults it on, and turning it off relaxes
the atomicity SPU reservations depend on. What has actually been observed:

- both A/B arms, 50 s each, no faults
- about three minutes of restored gameplay, no faults, no visual corruption
- the title then returns to its attract screen, so the tail of that soak is a
  light load and proves less than it looks

That is not enough evidence to relax atomicity for everyone by default. Subtle
reservation bugs show up as save corruption or a hang much later than three
minutes, which is exactly the failure mode a short soak cannot see.

**To try it:** `adb shell setprop debug.rpcsx.thor.spu_accurate_reservations 0`,
then play normally. If a long session is clean it belongs in the BLUS30161
profile as `Accurate SPU Reservations: false`, which is the same -10.6% without a
property.

# Transformers was not slow. It was hanging, and then cooking the device.

The whole "why is Transformers so slow" investigation had the wrong subject.

`RSX FIFO Accuracy` defaults to `Fast`. With it, the RSX thread dies about 35 s
into this title:

```
SIG: Thread terminated due to fatal error:
     Dead FIFO commands queue state has been detected!
```

**And the emulator does not stop.** After the RSX thread is gone, one SPU thread
keeps spinning at ~90% of the whole process, 0.00 FPS, 87-94 C, indefinitely.
That is the "it gets super hot" report: not a heavy game, a hung one.

Setting `RSX FIFO Accuracy: Atomic` with `Driver Wake-Up Delay: 20`, which is
exactly what the exception text tells you to do, gives 280 s with zero fatal
errors, 30.00 FPS held, and the title screen reached for the first time.

## The trap this laid, and it nearly worked

A 20 s profile taken during the hung state reads:

```
SPU[0x0000100]   90.79%   of all cycles
unknown[+...]    90.28%   "one address"
```

That looks exactly like a single hot loop worth attacking, and it was written up
here as one. **Both halves were wrong.** `unknown[+base]` is the JIT arena, which
simpleperf cannot symbolize, so ALL recompiled SPU code collapses onto one
"symbol" and one `vaddr_in_file` - it is not one address and it never was. And
the thread was not busy, it was spinning after the RSX had already died.

Two rules from it:

1. **Check for a fatal error in the log before believing any profile.** The FPS
   line read `Frames: 0 in 10.00s` for the entire recording and that was visible
   the whole time.
2. **`unknown[+X]` in a JIT process is a region, not a symbol.** Neither
   `--sort symbol` nor `--sort vaddr_in_file` nor `report-sample` can see inside
   it. Do not quote a percentage against it as if it were a function.

## What the profile is worth once the title actually runs

Reaching the title screen: 68.6% total CPU, SPU 50.5%, PPU 15.0%, RSX 3.1%, and
5.11 cores measured from /proc. That is a genuinely heavy title, and the thermal
guard engages on it at 86 C. The bottleneck there has NOT been characterised yet,
because every profile taken so far was of a hang.

# Transformers: the measured bottleneck, and the harness mistake that hid it

## Pressing through cutscenes is not a workload

The first Transformers A/B advanced by pressing A and START and measured whatever
it landed in. The same configuration gave **3.78 cores in one round and 5.89 in
the next**, because each run lands in a different scene. It measured scene
variance and nothing else, and the user said so before the numbers did.

**Use a state reachable identically every time.** For this title that is the
TITLE SCREEN, which needs no input at all and is already heavy: 70.7% CPU with
SPU at 56.1%, hot enough that the thermal guard caps it. Measured there, the
spread of one configuration is +/-0.2%, against +/-5% on the savestate harness and
something like +/-50% on the cutscene approach.

## The bottleneck

A verified gameplay profile, 243,663 samples at 18-20 FPS with `fatal=0` checked
across the whole window:

| symbol | share of all cycles |
| --- | --- |
| `vm::range_lock_internal` | **15.37%** |
| `[kernel.kallsyms]` | 13.48% |
| `vm::writer_lock::writer_lock` | **10.69%** |
| `rsx::thread::on_notify_pre_memory_unmapped` | 4.29% |
| `spu_thread::process_mfc_cmd` | 3.43% |
| `vm::passive_lock` | **3.07%** |
| `iso_dev::read_dir` | 1.78% |

**VM range locking is 29.1% of everything**, more than double Eternal Sonata's
12.7%. The earlier claim that this title is "not reservation-bound" came from a
profile of a cutscene and was wrong.

## What shipped

`Accurate SPU Reservations: false` in both game profiles.

| title | FPS | cores on | cores off | delta |
| --- | --- | --- | --- | --- |
| Eternal Sonata | 27.4 both | 3.348 [3.345..3.351] | 2.994 [2.951..3.037] | **-10.6%** |
| Transformers | 30.0 both | 2.81 [2.81..2.81] | 2.575 [2.57..2.58] | **-8.4%** |

Neither pair overlaps. End-to-end check of the shipped Transformers profile:
2.59 cores at 71 C against 2.81 at 73 C.

It relaxes reservation atomicity and upstream ships it on, so if either title
corrupts a save or hangs, set it back to `true` in the profile first.

## The ISO directory cache

`open_entry` resolves a path one component at a time and calls `read_dir` for
every component, and `read_dir` read blocks off the disc image each time. A UE3
title opening `.../UnrealEngine3/TransGame/CookedPS3/<file>` therefore re-read six
directories from the ISO on every open, which is the 1.78% above, during play,
long after loading.

Now cached by first-extent LBA. The image is read-only so a listing cannot go
stale and no invalidation is needed. The cache lives behind a `shared_ptr`: a
`shared_mutex` member is neither copyable nor movable, and `iso_dev` is returned
by value and stored in a `std::optional`, so putting the mutex inline deleted
those operations and broke every caller.

## Still open

Transformers crashed once more during these runs even with `RSX FIFO Accuracy:
Atomic` (`fatal=1` on one arm). The FIFO fix made it far more stable, not stable.

## What the reservations fix actually did, re-profiled

Transformers re-profiled with the shipped profile applied, 104,290 samples,
`fatal=0`, frames verified >0 across the window:

| | before | after |
| --- | --- | --- |
| `vm::range_lock_internal` | 15.37% | not in the top list |
| `vm::writer_lock::writer_lock` | 10.69% | **0.63%** |
| `[kernel.kallsyms]` | 20.76% | **4.38%** |
| `librpcsx-android.so` total | 46.30% | **8.26%** |
| JIT guest code | 27.51% | **85.35%** |

**VM range locking went from 29.1% of all cycles to under 1%**, and kernel time
fell with it, which is what a lock that was contending should do when it stops
contending. `iso_dev::read_dir` also left the top list once the directory cache
landed.

The emulator is now mostly RUNNING THE GAME rather than fighting itself: 85% of
cycles are recompiled guest code. Going faster from here means either less guest
work or better code generation, not more lock tuning.

## The title screen is heavy, and that is itself a clue

Eternal Sonata's title screen costs 5.7% CPU. Transformers' costs about 70%, with
SPU at 56.1%, on a menu with a rotating planet. A twelve-fold difference for a
comparable scene says its SPU threads are busy when the game is not, and the
self-loop park reads `entries=0` for this title against 93,713 for Eternal Sonata,
so whatever they are doing is not a branch-to-self the park can catch.

## A fixed sleep is not a deterministic workload

The title-screen A/B for reservations landed all four arms at 30 FPS and gave
+/-0.2%. The next one, same fixed 80 s wait, produced arms at 0.00 and 20.00 FPS
alongside arms at 30, because boot time varies by tens of seconds. Averaging those
would have invented a result.

`tools/thor_title_ab.sh` now GATES: it waits for two consecutive frame reports at
the title screen's rate, re-checks after sampling, and prints INVALID rather than
contributing a number it cannot stand behind.

## Rejected for Transformers: SPU loop detection

`SPU loop detection: true` makes this title HOTTER, reproducibly.

| arm | result |
| --- | --- |
| `false`, round 1 | 30.00 FPS at 70 C, 2.605 cores |
| `true`, round 1 | never reached 30, pinned at 20.00 FPS |
| `false`, round 2 | 29.94 FPS at 70 C, 2.778 cores |
| `true`, round 2 | never reached 30, pinned at 20.00 FPS |

20.00 is exactly the thermal guard's cap, so both `true` arms were at or above
85 C while both `false` arms sat at 70 C. Two out of two each way.

The setting only affects `SPU_RdDec`, where it adds `state += cpu_flag::wait` and
a `std::this_thread::yield()` when the guest polls the decrementer. On a title
that polls it often that is a syscall per poll, which is the same trade the RSX
FIFO pause ladder lost on: moving work from userspace to the kernel does not make
the CPU do less, and here it made it do more.

**The gate is what made this readable.** Both `true` arms would otherwise have
contributed a 20.00 FPS number to an average and shown up as "slower but similar",
instead of "never got there at all".

## Rejected for Transformers: SPU Block Size Mega

`SPU Block Size: Mega` against the shipped `Safe`:

| arm | result |
| --- | --- |
| `Safe`, round 1 | 29.92 FPS at 67 C, 2.640 cores |
| `Mega`, round 1 | fell to **0.70 FPS** mid-sample |
| `Safe`, round 2 | 29.95 FPS at 68 C, 2.592 cores |
| `Mega`, round 2 | fell to **1.68 FPS** mid-sample |

It was worth trying, because after the reservations fix 85% of cycles are
recompiled guest code and block size is the setting that governs how well that
code is generated. It does not survive contact: bigger blocks mean recompiling
more at once, and this title falls off a cliff doing it. Two out of two.

`Safe` stays.

# What actually kills Transformers: the GAME halts its own SPU

The Dead FIFO error is a symptom, not the cause. The full sequence:

```
0:00:37.42  {SPU[0x0000100] CellSpursKernel0}
            VM: Access violation writing location 0xffdead00 (unmapped)
0:00:38.77  {RSX} Dead FIFO commands queue state has been detected!
```

The SPU faults FIRST and the RSX dies 1.3 s later because nothing is feeding the
ring any more. Raising `RSX FIFO Accuracy` to Atomic treats the symptom, which is
why it survives much longer but still fails sometimes.

**`0xffdead00` is an emulator trap, not a wild pointer.** SPULLVMRecompiler.cpp
`make_halt()` deliberately access-violates at that address and stores a tag:

```cpp
const auto ptr = _ptr<u32>(m_memptr, 0xffdead00);
m_ir->CreateStore(m_ir->getInt32("HALT"_u32), ptr);
```

`make_halt` is emitted for the SPU HALT family, `HGT`, `HLGT`, `HEQ` and friends.
So the guest executed a conditional halt: **Transformers' own SPURS kernel checked
something, did not like the answer, and halted itself.** It is a guest assertion
firing, which means the emulator handed SPURS something it did not expect.

The tag written says which trap fired, and they are all distinct:

| address | tag | meaning |
| --- | --- | --- |
| `0xffdead00` | `HALT` | guest executed a halt instruction |
| `0xffdead04` | `TAG` | illegal MFC tag update |
| `0xffdead20` | `BIJT` | external tail call in a true function |
| `0xffdeadf0` | - | invalid MFC slot |

**When an SPU faults at 0xffdeadXX, read the tag before calling it a crash.** It
is the emulator reporting a specific illegal condition, and each one points
somewhere different.

This is a SPURS emulation bug and it is NOT fixed. It is the thing standing
between this title and being reliable, and it is a much deeper fix than any
setting.

**The halt has now been identified.** Recursive-descent disassembly of a
captured `CellSpursKernel0` local store finds 46 reachable halt sites, against
146 that a linear scan reports. Seven of them are one cluster of DMA helpers,
and each asserts the same thing:

> halt unless the effective address in `r3` is aligned to 128 bytes, and the
> size in `r4` is a multiple of 4, 8 or 16.

**That is a data check, not a timing check.** It refuses a POINTER. This matters
because the ten mechanisms excluded before it were all perturbations of
scheduling, and four of those were FORCED by injection with no halt: 3840
dropped notifications, a 3x wait scale, `max_run` clamped to 1 for 16896
applications, and 8080 checksum mutations per row. None of those can make a
pointer misaligned, so **those four null results do not bound this failure.**

The lead that follows is `Accurate SPU Reservations`, which this profile SHIPS
as false for -8.4% CPU. `GETLLAR` publishes a 128-byte line and the SPURS kernel
reads its pointers out of it, so a line that the guest can observe part-written
gives a mixed pointer, a misaligned pointer, and this halt. **Not yet measured.**

**The follow-on tear hypothesis was tested on device and REFUTED.** Three arms
on restored 3D combat measured 0 plain GETs overlapping a SPURS control line
under an active reservation lock, in every arm, with `spurs_addr=0x1e97a80`
confirmed real rather than `invalid_spurs`. The narrow fix built for it
changed nothing, 8773 against 8859. **And the assumption that the halt which
fires is one of the seven asserts was never measured: 39 of the 46 reachable
halts are still unclassified and the halting program counter is unknown.**

Full account, including two wrong turns this analysis made first, in
[`docs/arm64/spurs-halt.md`](docs/arm64/spurs-halt.md). The tool is
`tools/spu_cfg.py`.

# Transformers: the full lever sweep

Everything tried against the gated title-screen workload, which repeats to
about +/-0.2%:

| lever | result |
| --- | --- |
| `Accurate SPU Reservations: false` | **-8.4% CPU**, measured and still valid. **NO LONGER SHIPPED: reverted 2026-08-23.** The title halts its own SPU inside `CellSpursKernel0` with this off, and -8.4% CPU does not pay for a freeze. The profile now sets it `true`. Re-measured 2026-08-24: off gives 19.30 FPS against 18.60 shipped, so the win is real and the reason for refusing it is the halt, not the speed. |
| `RSX FIFO Accuracy: Atomic` | survives the FIFO symptom, shipped |
| `Shader Mode: Async with Shader Interpreter` | removes the compile stall, shipped |
| `Frame limit: 30` | -25% CPU against uncapped, shipped |
| `SPU loop detection: true` | REJECTED, hotter, 2/2 arms pinned at the guard cap |
| `SPU Block Size: Mega` | REJECTED, collapsed to 0.70 and 1.68 FPS |
| `Preferred SPU Threads: 2` | null, 2.614 against 2.617 cores |

Net measured effect on the title screen: **2.81 cores at 73 C down to about 2.6
cores at 67-70 C**, at the same 30 FPS, plus a title that reaches its menus at all.

# Researching upstream beat guessing locally

Three local lever sweeps found one win. Twenty minutes of reading upstream found
the stability fix and killed a documented open question. Do this first.

## The crash fix came from the community, not from us

RPCS3 lists BLUS30357 as **Playable** (0.0.25-14483, Dec 2022), which by itself
says the SPU halt is OUR problem, not the title's. The RPCS3 forum thread for the
sibling title, Fall of Cybertron, same studio and same engine, says: set the
**driver wake-up delay to 50 us and enable atomic FIFO**, and if it still crashes
try 150 to 200.

We shipped Atomic FIFO but only 20 us. At 50 us: **0 of 7 boots crashed**.

### CORRECTION: the "2 in 5 at 20 us" figure was not a measurement

It pooled boots across DIFFERENT configurations. The four crashes actually seen
were: two with the stock `RSX FIFO Accuracy: Fast`, one with
`Accurate SPU Reservations: true`, and one with it false, spread over roughly ten
boots that differed in more than the delay.

A controlled retest, five boots at Atomic + delay 20 + accurate=false, the only
difference from the shipped profile being the delay, produced **0 halts in 4
completed boots**.

So the honest position is:

| | boots | halts |
| --- | --- | --- |
| delay 20, controlled | 4 | 0 |
| delay 50, controlled | 7 | 0 |

**Delay 50 has not been shown to fix anything**, because the delay-20 arm did not
fail either. The fault is rarer than the pooled number implied, and separating a
roughly 1-in-10 event needs tens of boots per arm, not a handful. 50 us is kept
because it is what upstream recommends for this engine and it measured free
(0.4%, overlapping ranges), NOT because it is proven to fix the halt.

A rate quoted from boots that differed in several settings at once is not a rate.

## And the cost was measured, not assumed

RPCS3 issue 12295 says raising this delay causes a *severe* performance
regression, 60 FPS down to 20 on God of War, and recommends reverting to 1 us
with Atomic FIFO instead. That is a direct argument against what the forum
advises, so it was measured here rather than picked:

| delay | FPS | cores |
| --- | --- | --- |
| 20 us | 29.95 | 2.557 [2.549..2.565] |
| 50 us | 29.95 | 2.568 [2.554..2.582] |

0.4% apart with overlapping ranges. **The regression that issue describes does not
bite this title on this device**, so the stability is effectively free. Two
credible upstream sources disagreed and the device settled it.

## The SHUFB TBL2 candidate: answered, and the answer is no

`thor_shufb_tbl2_or.h` has carried an explicit open question since it was written:
the transform is proven equivalent over all 256 selector bytes, but "**Not
measured: that the replacement is faster.**" This is the SIMD-asymmetry idea the
DBT literature keeps returning to, applied to the most common op in the corpus,
5,794 `SHUFB` against 2,203 `fm`.

`thor_bench shufb` on device answers it:

| | ns |
| --- | --- |
| `tbl2_tp` isolated | 0.085 |
| `tbx2_tp` isolated | 0.339 |
| `seq_tbx2_current` | 0.239 |
| `seq_tbl2_orr_candidate` | 0.235 |

**The 4x isolated throughput gap collapses to 1.7% in the real sequence**, because
the replacement trades one TBX2 for a TBL2 *plus an ORR*, and the sequence is not
throughput-bound on that instruction anyway. 1.7% of the SHUFB sequences alone is
far below the +/-5% this project can measure in-app.

Keep `debug.rpcsx.thor.shufb_tbl2_or` at 0. The open question in that header is
now closed with numbers, and the general lesson is worth more than the result:
**an isolated instruction-throughput ratio is not a program speedup.** The
surrounding sequence decides.

Note the bench pins its own affinity and always reports `cpu=7`; `taskset` does
not override it, so these are prime-core numbers.

# The SPURS halt, and why `Accurate SPU Reservations: false` was reverted

## What the fault is

The guest's own SPURS kernel executes a conditional HALT. `0xffdead00` with the
tag `HALT` is `make_halt()` in SPULLVMRecompiler.cpp, emitted for `HGT`, `HLGT`
and `HEQ`. So the game checked an invariant on the SPURS block, found it wrong,
and stopped itself. The Dead FIFO error 1.3 s later is the RSX starving after it.

## What was ruled out

**Our SPURS HLE is not the bug.** `cellSpurs.cpp`, `cellSpursSpu.cpp` and
`cellSpursJq.cpp` diff against upstream RPCS3 to include paths
(`Emu/Cell/lv2/` -> `cellos/`, `util/asm.hpp` -> `rx/asm.hpp`), a
`-Wunused-parameter` pragma, and clang-format churn. **Zero semantic difference.**

**We do have upstream's SPURS limiter.** `spurs_addr`, `spurs_entered_wait`,
`spurs_average_task_duration`, `spurs_wait_duration_last` and the
`CellSpursKernelGroup` detection are all present. A first grep suggested they were
missing; that grep was truncated by `head -12` and showed only Thor's own probe
code sitting above them. **Check whether a grep was truncated before concluding
something is absent.**

**No upstream patch exists for it.** The only published patch for BLUS30357 is an
FPS unlock.

## Why the reservations setting went back to true

Two independent pieces of evidence, neither of them a guess:

1. Upstream documents that disabling accurate SPU reservations **"can break games
   like InFamous, which freezes right after the intro"**. This title halts its SPU
   shortly after its intro.

2. `SPUThread.cpp` has a branch entered ONLY when the setting is false, and only
   for reservations inside the SPURS block:

   ```cpp
   if (raddr - spurs_addr <= 0x80 && !accurate_reservations && mask1 == SPU_EVENT_LR)
   ```

   Its own comment says this works because "we have notifications for **nearly
   all** writes". Nearly all is not all. A missed notification leaves the SPURS
   kernel reading stale state, and stale state is precisely what it asserts on.

Eternal Sonata's profile had `Accurate SPU Reservations: true` set **explicitly**
before this session. That was a decision, and flipping it on the strength of a CPU
number was overriding it.

**The measurements stand and are not withdrawn**: -10.6% on Eternal Sonata and
-8.4% on Transformers, both with non-overlapping ranges. The setting is still
reachable per session:

```
adb shell setprop debug.rpcsx.thor.spu_accurate_reservations 0
```

It is no longer a default, because an 8 to 10% CPU saving is not worth a freeze on
a title that already halts, and because the mechanism connecting the two is
written in the emulator's own source.

**A measured win is not automatically a correct default.**

## The wake-up delay does nothing for the halt. Controlled, and finished.

The delay-20 arm completed. Both arms differ only in the delay, both are passive
boots to the title screen from under 62 C:

| arm | boots | halts |
| --- | --- | --- |
| delay 20 us | 12 | **0** |
| delay 50 us | 15 | **0** |

**27 consecutive clean boots.** So:

- The original "about 2 boots in 5 crashed at 20 us" was wrong by a wide margin,
  and the correction already published understated how wrong. The fault is rarer
  than 1 in 27 under these conditions.
- `Driver Wake-Up Delay: 50` is kept ONLY because upstream recommends it for this
  engine and it measured free (0.4%, overlapping ranges). It has no demonstrated
  effect on the halt. Do not describe it as the crash fix.

### What the four historical faults actually had in common

They are not explained by the delay. Reviewing the conditions of each:

- two ran with the stock `RSX FIFO Accuracy: Fast`;
- one ran with the thermal guard disabled, on a hot device;
- one ran during a managed-profile verification straight after an install.

The 27 clean boots all ran with `Atomic`, the guard on, and a cooldown below
62 C before each boot. **The candidate that survives is `RSX FIFO Accuracy`, not
the delay**, and heat is a second candidate that has not been separated from it.

### What would actually settle it

A controlled `Fast` against `Atomic` arm, same everything else, about 25 boots
each. That is roughly two hours of device time and it is the honest next
experiment. Nothing shorter can separate a fault this rare, which is the same
lesson as the pooled rate: **a rare event needs a denominator, not an anecdote.**

# The SPURS halt: two more candidates are eliminated, and the fault now names itself

**2026-08-23.** The goal was to fix the halt. It is not fixed, and this section
says exactly what is now known, because a rare fault needs a denominator.

## `RSX FIFO Accuracy` is not the cause

The previous pass said the candidate that survived was FIFO accuracy, not the
wake-up delay. A controlled arm removes it:

| arm | boots | faults |
| --- | --- | --- |
| Atomic | 27 | 0 |
| Fast | 10 | 0 |

**37 consecutive clean boots.** No setting-level hypothesis is left.

## The GETLLAR sleep cannot leave a SPURS waiter stale

This looked like a real Thor-specific mechanism, and it is wrong. `do_putllc`
SUPPRESSES the reservation notification for a SPURS kernel store: at
`SPUThread.cpp:5461` it notifies only when `raddr != spurs_addr || pc != 0x11e4`,
or when the thread went from running to idle. Upstream can suppress it because
upstream waiters SPIN, and this fork ships `getllar_busy_percent=0`, so our
waiters SLEEP.

**The sleep is bounded.** `SPUThread.cpp:6510` waits with
`atomic_wait_timeout{100'000}` and the loop then re-reads the line. A missed
wake costs 100 us of latency, and it cannot produce a stale read.

Read the timeout before you build a theory on a wait.

## What shipped: the fault is self-diagnosing

`handle_access_violation` in `rpcs3/util/Thread.cpp` now decodes the trap. It
gives the tag name, the thread, the program counter, the SPURS address, the
reservation address, and the SPURS limiter state: the group, `max_run`,
`spurs_running`, the idle mask, and the task timing.

**It reads the local store and the thread group only.** A read of guest main
memory can fault a second time inside the handler, and Android then stops the
process with no log at all. `_ref` masks the address with `% SPU_LS_SIZE`, so it
cannot fault.

## Heat is the one correlate never controlled

Every clean arm cooled below 62 C first. One historical fault ran on a hot
device, and the SPURS limiter is timing-driven: `spurs_average_task_duration`
sets a wait clamped between 10 ms and 100 ms. A throttled device changes that
timing.

An arm of back-to-back boots with no cooldown is running. The thermal guard
stays ON, because the device is shared and the guard does not stop this title
reaching 90 C anyway.

# A game workup suite, because every new title started from nothing

**Written 2026-08-23 after Transformers cost a week.** This repo had 18 skills.
Nearly all of them were for one title or one subsystem, and they answered
"is this number valid". None of them answered "what do I do next for this game".

| Artifact | What it is |
| --- | --- |
| `tools/thor_game_workup.sh` | one unattended command: preflight, boot, name the failure, then measure |
| `.agents/skills/thor-game-workup/SKILL.md` | the procedure, the trap tags, and a profile-to-lever table |
| `docs/arm64/title-recipes.md` | per title: the signature, what shipped, what it refused, what is open |

**Triage gates speed, and that is not a preference.** This project measured
Transformers for a week as a slow title. It was a hanging title, and every
number from that week described a dead emulator.

The tool knows eleven failures by name, and it refuses rather than guesses: an
unreachable device, a battery below 20%, an active dev-core override, and a
sleeping screen. It restores a config by moving an on-device backup, never by
rebuilding the text, because a harness that rebuilt a config with `printf` into
`while read` dropped the only line and ran every arm unset.

**It proposes. It does not write a game profile.** A measured win is not
automatically a correct default: `Accurate SPU Reservations: false` measured
-10.6% and -8.4% and is still not shipped.

# What you can know before you boot a title

`thor-ghidra-static-lane` now covers two jobs that need no runtime evidence.

**The SPURS halt map.** The SPURS kernel comes from `libsre` and its image is
the same on every boot. Capture the local store of `CellSpursKernel0` once,
disassemble it, and record every `HGT`, `HLGT` and `HEQ` with its condition. A
future trap then resolves in one lookup instead of a session. The disassembler
is already in this tree at `Emu/Cell/SPUDisAsm.cpp`. **The trigger is built and
verified on the device**: `debug.rpcsx.thor.spu_ls_dump=<name substring>`
writes 262144 bytes from `perf_monitor`, so no SPU path pays for it.

A first scan of the Transformers image found **146 halt-shaped words, 142 of
them real**. Almost all are `HEQI ra, -1` or `HEQI ra, 0`, which is a guest
that asserts on an error return or a null handle. **A flat scan cannot tell
code from data**: four hits are constants, and one of them is the `ELF`
magic. Filter on the operand.

**The static title fingerprint.** `PARAM.SFO`, the engine strings, the imported
PRX list, the count of embedded SPU images, and the module size estimate all
read off the disc image. They say whether a title can reach our SPURS defects at
all, and they predict the precompile time and the Scudo risk.

**A fingerprint says which failures are possible. It does not say which one
happened.** The workup tool still decides that.

# "Never rendered" is usually the harness, not the lever

**2026-08-25.** Three arms in a row reported `SKIP (never rendered)` -
`spu_backoff_div=32`, `spu_backoff_div=4`, and `getllar_busy_percent=25` - and a
conclusion was drawn from all three. One of them was innocent.

Every failing arm shared two properties that had nothing to do with its lever:

  * it CLEARED the SPU cache first, so ~3147 functions had to be recompiled
  * it booted from **86-88 C**, while every control that rendered booted from
    **59-62 C**

The render wait was 420 s. AGENTS.md already records that a cold cache build on a
hot device never completes inside the thermal bound. So "never rendered" meant
"did not finish compiling in time", and the lever was blamed for the harness.

Retested from a cold device, one at a time:

    getllar_busy_percent=25   RENDERED at t+30 s, 3147 functions, 0 fatals
    spu_backoff_div=4         process DEAD by t+60 s, temp 69 C then flat 32 C

So one was a harness artifact and the other was a real crash. They are
indistinguishable from the arm's output alone.

**Rules this earns:**

1. A lever that does not change generated code does NOT need the SPU cache
   cleared. Clearing it anyway buys a ten-minute recompile and a false negative.
   Only clear it for a lever that rewrites analysed instructions.
2. Cool BEFORE the boot, with the app already stopped, in every arm - not only
   the first. An A-B-A whose later arms start 30 C hotter is not a controlled
   comparison.
3. Before believing `never rendered`, distinguish the three causes: still
   compiling (`SPU Runtime: Built` count rising), thermally paused (`THERMAL
   ABORT` in the log), or dead (control API returns nothing and `pidof` is
   empty). The output looks identical and the meanings are opposite.

# A cooldown gate that runs BEFORE the force-stop cooks the device

**2026-08-23, and it is the worst harness defect written here.** A reproduction
arm held the Thor at **94 to 95 C for many minutes** and could not escape.

The loop looked correct:

    for each boot:
        while temp >= 70: sleep        # cool first
        am force-stop ...              # then restart the title
        am start ...

**The emulator from the PREVIOUS boot is still running during that wait.** So
the harness waited for a temperature that its own workload made impossible, and
the wait never ended. The device does not cool while the thing heating it runs.

**Force-stop first. Cool second.** The order is the whole bug:

    am force-stop ...
    while temp >= 70: sleep
    am start ...

## And TaskStop did not kill it

Stopping the background task reported success, and the script kept running: the
spinners came back and the emulator restarted. Only `ps` found it, a `bash` at
PID 32031 with an `adb` child and a `sleep`.

**Confirm the DEVICE is quiet, not that the task is stopped.** The three checks
that told the truth were `pidof`, `pgrep -c yes`, and `top`, which read
`800%cpu ... 757%idle` once the host process was really dead. A stop that is not
confirmed on the device is not a stop, which is the same rule this file already
gives for `rm` and for an empty `pidof`.

**The battery never passed 25 C.** The SoC ran hot, the cell did not. Read both
before deciding how alarmed to be.

# The SPU object cache is hard-gated to one title

`spu_native_object_cache_enabled()` at `SPUCommonRecompiler.cpp:349` opens with:

    if (Emu.GetTitleID() != "BLUS30161") { return false; }

So **every other title recompiles its SPU programs on every boot**, and Eternal
Sonata does too unless `debug.rpcsx.thor.spu_native_object_cache` is set, which
it is not by default. That is the `SPU Runtime: Built NNNN functions` line on
each load.

Even when it is on, the log says it covers startup objects only: runtime misses
stay uncached.

This looks like an experiment that nobody generalised. It is the clearest open
lead on load time, and unlike the SPURS halt it is reproducible on every boot.
**Do not just delete the title check.** The cache key hashes the optimised IR
and the target identity, and the SPU block verification checksum changed on
2026-08-22, so stale objects must be shown to invalidate before this ships.

# The SPU trap now stops the emulator instead of cooking the device

**The halt is still not fixed. This fixes what the halt COSTS.**

When the guest halts its own SPU, `util/Thread.cpp` pauses only the faulting
thread. Everything else keeps running, the RSX starves 1.3 s later, and the
remaining SPU threads spin at about 90% of the process at 87 to 94 C with a
frozen picture. One run stayed that way for four minutes.

`Emu/Cell/thor_spu_trap_stop.h` stores the trap address, and `perf_monitor`
pauses emulation on its next tick. **The handler must not pause the emulator
itself**: it runs in signal context and `Emu.Pause()` takes locks, and this fork
has already self-deadlocked once by running lock-taking work inline where
upstream queued it.

It acts ONLY on the `0xffdeadXX` range, where the guest asked to stop. An
ordinary access violation keeps upstream behaviour.

    debug.rpcsx.thor.spu_trap_stop = 0        keep the old behaviour
    debug.rpcsx.thor.spu_trap_stop_test = 1   raise a fake trap, to test the stop

**VERIFIED ON THE DEVICE, and the measurement is the CPU, not the log line.**
Transformers rendering, the fake trap injected, the same process sampled
before and after:

| | cores | temperature |
| --- | --- | --- |
| before the trap | 3.63 | 69 C |
| after the trap | **0.09** | **45 C** |

**A 97.5% drop.** `Emu.Pause()` does reach an SPU thread spinning inside a JIT
loop, which was the open question. The four minute burn at 87 to 94 C after a
guest halt is gone.

# The starvation arm did not run

Two boots completed before the cooldown defect above stopped it, both clean.
**Two boots is not a result.** The idea still stands and is untested: the SPURS
limiter is timing-driven, it computes a wait from `spurs_average_task_duration`
clamped to 10 to 100 ms, and every one of the 52 clean boots ran with the CPU
free, so the timeout branch was rarely taken. Taking the cores away perturbs
exactly that. Re-run it with the force-stop before the cooldown.

# The control API: drive the emulator from a tool

**Working since 2026-08-23, pad injection included.** `ThorControlServer.kt`
runs a small HTTP server in the app. It binds to **127.0.0.1 only** and runs in
debug builds only, gated on `BuildConfig.THOR_DEBUG_TOOLS`. The Thor is shared
and on a real network, so an open control port would let anything drive it.

    adb forward tcp:8099 tcp:8099
    curl 127.0.0.1:8099/            # every endpoint and every button name

| call | what it does |
| --- | --- |
| `GET /status` | state, title id, build version |
| `POST /pad/press?buttons=CROSS,START&ms=120` | press, hold, release |
| `POST /pad?d1=&d2=&lx=&ly=&rx=&ry=` | raw pad state, sticks 0..255, centre 128 |
| `POST /pad/release` | clear the buttons, centre the sticks |
| `POST /savestate` | capture. ONE slot, and it overwrites |
| `POST /loadstate` | restore |
| `POST /resume`, `POST /kill` | emulation control |
| `GET` or `POST /setting?path=&value=` | read or write one config value |

Buttons: `UP DOWN LEFT RIGHT CROSS CIRCLE SQUARE TRIANGLE L1 L2 L3 R1 R2 R3
START SELECT PS`.

## Why it exists

**The emulated pad cannot be driven from outside the app.** This file records
three attempts that all failed: `input keyevent BUTTON_START` left the workload
unchanged, `ENTER` and `BUTTON_A` reached the Android UI and killed the process,
and `sendevent` on the real gamepad node was confirmed arriving in the kernel
with `getevent` while the guest saw nothing.

So no tool could pass a title screen, and every large lever in this fork lives
in gameplay: the SPU self-loop park is about 20% of gameplay CPU,
`process_mfc_cmd` is 20.13%, `vm::writer_lock` is 4.49%. A title screen is 0.35
cores behind a frame cap and can show none of them.

**It works now.** Transformers goes from its title screen to the main menu on an
injected `START`.

## Press when the screen is ready, not on a timer

**This cost a wrong conclusion.** The first attempts were written up as "pad
injection does not reach the guest". They reached it. The presses landed during
the intro, before the game asked for input, so the game correctly ignored them.

The frame rate went 122.50 to 29.83 across that attempt, which read exactly like
the button working. It was the intro ending by itself. **The screenshot settled
it**: the screen still read `Press START button`. A frame rate change is not
evidence that input arrived.

So the loop is: screenshot, decide what the screen asks for, then press.

    adb exec-out screencap -p > shot.png
    curl -X POST '127.0.0.1:8099/pad/press?buttons=START&ms=150'

## The probe, when input seems not to arrive

`debug.rpcsx.thor.pad_probe=1` prints both sides:

    WRITE: pad=0x7434915cd8 d1=0x0008 player=0
    GUEST: port=0 pad=0x7434915cd8 d1=0x0008 (was 0x0000) status=0x1

The same pointer means the guest reads the pad we write. A changing `d1` with a
clean press and release edge means the guest saw the button. That separates "our
write is lost" from "the guest reads another pad", which no screenshot can.

**`ok:true` from the API is NOT "the guest pressed the button".** It means
`_rpcsx_overlayPadData` found the pad and wrote the bits.

## Not implemented

`/pause`. `RPCSX` exposes `resume`, `kill` and `getState`, and no pause
external. The intended loop is pause, screenshot, decide, resume, press, which
removes the race against animation.

# Never open a file for writing before the content is built

**2026-08-23, and it destroyed this file for a minute.** A rewrite did:

    open(p, 'wb').write(build_content())

Python opens and TRUNCATES first, then evaluates the argument. `build_content()`
raised, so the file was left at zero bytes with nothing written.

Build the bytes, THEN open:

    body = build_content()
    open(p, 'wb').write(body)

It cost nothing because the file was committed one step earlier. **Commit before
a large mechanical rewrite**, so the recovery is `git checkout --` and not a
reconstruction.

# Is it a movie or the game? Ask, do not guess from the frame rate

**Built 2026-08-23.** `GET /scene` answers it, and `/status` carries the same
field. Pair it with your screenshot: a picture does not say whether it is a
cutscene or the game.

    curl 127.0.0.1:8099/scene
    {"videoDecoding":true,"vdecUnits":812,"vdecAgeMs":16,"advice":"movie", ...}

## Why it exists

**Two things go wrong without it.**

A movie is skipped with START, and START during gameplay does something else.
A tool that drives the emulator has to know which it is looking at.

And **a cutscene cannot resolve a measurement**. This repo measured ONE
configuration at 3.78 and 5.89 cores on consecutive rounds because each run
landed in a different scene, and the complaint at the time was exactly "you keep
testing movies". A workup must refuse to measure while a movie plays.

**The frame rate is the worst possible signal.** Transformers renders its
cutscene at 120 to 133 FPS uncapped and its title screen at 30, so a HIGH number
means a movie and not speed. Reading the number harder does not fix that, which
is why this is a separate probe and not an FPS threshold.

## What it detects exactly, and what it does not

**Pre-rendered video is exact.** The guest hands access units to `cellVdec`, so
`thor::vdec_tick()` in `cellVdecDecodeAu` counts real decodes. There is no
heuristic in `videoDecoding`.

**A real-time engine cutscene is NOT detected.** Transformers' intro is rendered
by the game rather than decoded, so `cellVdec` never fires and `videoDecoding`
is false during it. The endpoint says `not-a-movie-or-engine-cutscene` rather
than claiming the game is running. **Judge that case from the screenshot**, and
do not dress the guess up as a detection.

`vdecAgeMs` is -1 when nothing was ever decoded. The playing window is 500 ms,
which is generous on purpose: a 30 fps stream is one unit every 33 ms, and a
briefly starved decoder must not read as "the movie ended".

# The SPU object cache is on external storage, and counting it wrong reads as zero

**2026-08-23.** An A/B of the SPU native object cache reported `objects=0` in
every arm, which reads exactly like a cache that does not work. It held **3149**
objects.

The count used `run-as <pkg> ls cache/cache/<title>/...`, a path relative to the
app's PRIVATE directory. The cache is on EXTERNAL storage:

    /storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/cache/<TITLE>/ppu-*/spu-native-v2/

`run-as` still owns the clear, because the tree denies group write, but it needs
the ABSOLUTE path for an external directory. **Confirm the postcondition**: the
clear is trusted because a re-count read 3149 then 0, never because `rm`
returned success.

This is the fifth entry in this file for one class: a search that finds nothing
and a search that searches nothing look identical.

# `/device`: heat, throttling, power, speed, and lever REACH

**Added 2026-08-23.** Poll one endpoint instead of grepping a log.

    curl 127.0.0.1:8099/device

It carries `cpuJunctionC`, `thermalGuardEngaged`, `thermalGuardCapFps`, `fps`,
`coresBusy`, `frames`, `ramMb`, `inputPowerMw`, `batteryPercent`, `batteryC`,
plus the reach counters: `spuSelfLoopPark` (entries, exits, parkedNow, lastPc),
`rsxFifo` (idlePolls, parks) and `spuTrap`.

**Read `thermalGuardEngaged` before believing a slow arm.** An arm pinned at
exactly the guard's cap is a TRIPPED GUARD, not a slow configuration. Two `SPU
loop detection` arms read 20.00 FPS for that reason.

**Read the counters before believing a null.** A lever with no reach and a lever
with no effect give the same number. The SPU self-loop park was written off
twice on a scene where its counter reads `entries=0`.

**Frames come with the CPU number on purpose.** A CPU number alone cannot tell a
thread that stopped spinning from an emulator that stopped working.

Two caveats are in the payload itself. `cpuJunctionC` is a `cpu-1-*` junction
zone and is up to about 2 s old, because the guard samples every fourth
`perf_monitor` tick and nothing on the render path can afford to read sysfs.
`inputPowerMw` is CHARGER INPUT and is valid only while the battery is not
charging: the fuel gauge on this device is frozen in all four nodes, so the
charger is the only working instrument.

# A savestate vault, so an experiment can restore the same scene

`tools/thor_savestate_vault.sh` keeps savestates in `debug-captures/`, which is
NOT tracked. A savestate holds game memory and does not belong in a public
repository.

    tools/thor_savestate_vault.sh list
    tools/thor_savestate_vault.sh save    BLUS30161   # backup, capture, pull
    tools/thor_savestate_vault.sh restore BLUS30161   # push, then load

**The device keeps ONE slot per title and a capture OVERWRITES it.** A capture
taken here to test the load path destroyed the only savestate for a title, and
nothing kept a copy. `save` therefore pulls the existing slot into the vault
FIRST, and the vault stamps every version and never overwrites.

`push` uses `adb push`, because a device-side redirect cannot replace that file:
it is owned by the app and shell has only group read. The tool compares byte
counts afterwards and refuses to load on a mismatch, because this project has
been fooled by a copy that reported success and changed nothing.

## Why a savestate is the workload that matters

A title screen is 0.35 cores behind a frame cap and can show nothing. A restored
savestate runs real gameplay BELOW the cap, at 25.7 to 25.9 FPS and 3.1 cores,
so a lever that costs frames can no longer hide behind the cap.

# What else is worth pushing through the API

In rough order of what would have saved the most time here:

| candidate | what it would end |
| --- | --- |
| **compile progress** (PPU modules done/total, SPU functions built) | fixed sleeps. "A fixed sleep is not a deterministic workload", and a cold boot can take ten minutes |
| **applied config readback** | an arm that never applied its lever. A harness once ran EVERY arm unset and the two arms agreed perfectly |
| **per-thread CPU** (`rsx::thread` against the SPU threads) | measuring the process when the lever touches one thread. `rsx::thread` is 0.51 of 2.90 cores, so a 30% saving there hides in process noise |
| **SPURS state** (`spurs_running`, `max_run`, idle mask) | reading the SPURS limiter only after a fault. It is the open bug |
| **error and fatal log tail** | grepping the log over adb for every check |
| **RSX counters** (draws, texture uploads, flips) | guessing whether a GPU change had reach |

Each is a small read of state the emulator already holds. The pattern is fixed:
a counter or accessor, a `_rpcsx_*` export, a `native-lib.cpp` binding, a Kotlin
`external fun`, and one endpoint.

# `/diag`, `/threads`, `/log`: the rest of the state a tool needs

**Added 2026-08-23.** Each one ends a specific way this project wasted time.

## `/diag` - compile progress, the config IN EFFECT, and live SPURS

    curl 127.0.0.1:8099/diag

**Progress ends fixed sleeps.** `filesDone/filesTotal`, `modulesDone/modulesTotal`
and the dialog `text`. A fixed sleep is not a deterministic workload: boot time
varies by tens of seconds, a cold PPU precompile can take ten minutes, and an
arm that samples into a compile measures the compile. One arm reported 14.6
CPU-seconds over 254 seconds and every other check looked clean, because the
title was 27 minutes from starting.

**Config ends an arm that never applied its lever.** It reports
`rsxFifoAccuracy`, `accurateSpuReservations`, `spuBlockSize`, `spuDecoder`,
`frameLimit`, `shaderMode` and `driverWakeUpDelay` as the emulator has them, not
as a file says. A harness here fed its spec into `printf | while read`, which
drops a line with no trailing newline, so EVERY arm ran unset and the two arms
agreed perfectly.

**SPURS is the open bug.** For each SPU thread in a SPURS group it gives
`index`, `pc`, `spursAddr`, `group`, `maxNum`, `maxRun`, `spursRunning`,
`waited` and `enteredWait`. The limiter's state used to be readable only after a
fault, and only from a log line.

## `/threads?match=SPU` - per-thread CPU

Measure the THREAD a lever targets, not the process. `rsx::thread` is 0.51 of
2.90 cores, so a lever saving 30% of that thread moves the process total by 5%
and hides in the noise.

Jiffies are cumulative, so **sample twice and difference them**. The endpoint
does not compute a rate on purpose: a rate computed inside would pick its own
window instead of the one the caller measured over.

The app reads its own `/proc/self/task`, so this needs no JNI and no root.

## `/log?match=fatal&n=40` - the tail of RPCSX.log

**Read the log for a fatal error BEFORE believing any profile.** One capture
here read 90.79% in a single SPU thread and was written up as a hot loop. The
RSX had died 35 seconds earlier and `Frames: 0 in 10.00s` was in the log the
whole time.

# The `thor` MCP server: typed tools instead of a hand-written harness

**Built 2026-08-23.** `tools/thor_mcp/server.py`, wired in `.mcp.json`. Ten
tools: `thor_state`, `thor_cooldown`, `thor_boot`, `thor_wait_ready`,
`thor_press`, `thor_screenshot`, `thor_sample`, `thor_log`, `thor_setprop`,
`thor_stop`.

**It exists because the LOOP was the defect, not the primitives.** Every harness
failure in one day was the same bash logic retyped:

* a cooldown placed BEFORE the force-stop, which waited for a temperature the
  still running emulator prevented, and held the device at 95 C;
* a cache count using a path relative to the app's private directory when the
  cache is on external storage, reporting 0 objects while 3149 existed;
* `printf | while read`, which drops a line with no trailing newline, so every
  arm ran unset and both arms agreed perfectly.

None of those is an emulator bug. They vanish when the loop lives in one tested
place.

## The refusals are the product

`thor_sample` returns `void: true` and a reason when the window cannot be
measured:

* **a movie is playing** - a cutscene cannot resolve a measurement, and one
  configuration measured 3.78 and 5.89 cores on consecutive rounds;
* **the thermal guard is engaged** - the arm then measures the guard's frame
  cap, which is how two arms read exactly 20.00 FPS.

**A `void` is a RESULT.** Do not average it and do not retry until it passes.

`thor_setprop` reads the property BACK, `thor_cooldown` stops the emulator
before it waits, `thor_boot` turns the SPU object cache off for a diagnosis, and
`thor_stop` reports the device is quiet rather than that a task was stopped.

**No tool writes a game profile or an engine default.** Propose only.

The procedure lives in the `thor-game-workup` skill. This server is the
mechanism; the skill is the policy.

# SHIPPED: the SPU object cache is ON by default

**Changed 2026-08-23.** Unset now means enabled, so a title stops rebuilding its
SPU programs on every boot.

Measured on Transformers, to the same `SPU Runtime: Built 3118 functions`
milestone:

| cache | seconds |
| --- | --- |
| off | 23.2, 24.0 |
| on, cold (writes 3149 objects) | 25.1 |
| **on, warm (reads them)** | **12.0** |

Cold slightly slower and warm about half is the shape a working cache must have,
and the off baseline repeats to 0.8 s.

## TURN IT OFF WHILE DIAGNOSING A GAME

**It changes WHICH CODE RUNS.** A cached object replaces a compile, so a fault
or a fix can be an artifact of a stale object rather than a property of the
change. `tools/thor_game_workup.sh` forces it off for the run and restores it on
exit, and `thor_boot` takes `freshCompile` for the same reason.

    adb shell setprop debug.rpcsx.thor.spu_native_object_cache 0

**What is NOT established.** This is one measurement on one title. Nobody has
soaked it across many cold boots, and it changes what the verifier accepts. If a
title starts misbehaving after this, clear the property FIRST and say so.

# The SPURS starvation arm: no reproduction, and the count is now 63 boots

**Run 2026-08-23 with the fixed harness.** The idea was mechanical rather than a
guess: the SPURS limiter computes its wait from `spurs_average_task_duration`,
clamped between 10 and 100 ms, and takes a TIMEOUT branch when tasks run long.
Every clean boot before this ran with the CPU free, so that branch was rarely
entered. Five spinner processes were started 25 s into each boot, once the title
was already doing SPURS work.

    12 boots, 0 SPU traps, 0 dead FIFO, 0 fatal errors

## The running total, counted once each

| arm | boots | faults |
| --- | --- | --- |
| `RSX FIFO Accuracy: Atomic` (this IS the delay 20 and delay 50 pair, 12 + 15) | 27 | 0 |
| `RSX FIFO Accuracy: Fast` | 10 | 0 |
| hot device, no cooldown, 94 to 97 C | 15 | 0 |
| CPU starvation, 5 spinners | 12 | 0 |
| **total** | **64** | **0** |

**64 controlled boots and not one reproduction.** Every setting-level
hypothesis is eliminated, and so are heat and CPU scarcity.

**The delay arms are NOT a separate 27.** They are the same boots as the
Atomic arm, and listing both double counts the denominator. This file already
records a rate quoted from pooled boots that was not a rate; the same care
applies to a denominator.

## What the arm DID show

Starvation degrades this title badly without ever tripping the halt. Frame rate
across the eleven boots: 17.6, 15.1, 20.0, 15.2, 20.0, 15.0, 14.0, 13.1, **2.0**,
16.2, **0.0**. The two worst are a real observation and not a fault: the title
survives, keeps its RSX queue, and simply cannot keep up.

The 20.00 readings are the thermal guard's cap, not a measurement.

## What this closes, and what is left

**Stop doing passive boots.** Sixty-three of them across five different
conditions have produced nothing, and each one costs about two minutes of device
time. A rare event needs a denominator, and this denominator says the fault is
rarer than 1 in 63 under every condition tried.

**The honest next step is real gameplay, which is now reachable.** Every boot so
far ended at a title screen, because the guest pad could not be driven. It can
be now: Transformers goes from its title screen to the main menu on an injected
`START`. A run that reaches actual gameplay and holds it exercises SPURS job
dispatch, which a title screen barely touches, and the trap decoder plus the
SPURS state in `/diag` make the next occurrence self-explaining.

# PAUSE BY DEFAULT, or the observation is about a scene that already ended

**Added 2026-08-23, after measuring a movie.** The emulator does not wait while
a tool thinks. A screenshot taken live is stale before it is read, and the
button pressed afterwards lands on a scene nobody looked at.

`POST /pause` and `POST /resume` exist now, and the MCP tools pause by default:
`thor_screenshot` pauses and STAYS paused, `thor_state` pauses before reading,
`thor_press` resumes and re-pauses because a paused guest cannot see a button,
and `thor_sample` REFUSES while paused.

**Verified on the device: 3.91 cores running, 0.33 cores paused.**

That last refusal matters. A sample taken while paused reads about 0.3 cores
against 3.9 running, so it is not a small error, it is a number about nothing.

# CORRECTED: cellVdec alone cannot see a movie

**The first movie probe watched `cellVdec` only, and it was wrong.**
Transformers plays `FMV_intro.bik`. The probe reported `videoDecoding: false`
through the whole intro, that was written up as "not a movie", and a
measurement was taken of a movie.

**Many PS3 games ship Bink and decode it in their own SPU code**, so Sony's
decoder is never called and `vdecUnits` stays 0 for the entire run. A zero there
says the title does not use `cellVdec`. It says NOTHING about what is on screen.

`/scene` now has two sources and reports which one fired:

| source | meaning |
| --- | --- |
| `cellVdec` | decoding through Sony's decoder |
| `open-video-file` | the guest holds a container open, e.g. `.bik` |
| `none` | neither, and NOT proof the game is running |

The container hook is in `sys_fs_open` and `sys_fs_close`, because a title holds
the file open for the length of playback. Measured on Transformers: the probe
reads not-a-movie through boot, then `movie` for the whole intro, with
`vdecUnits` still 0.

**An engine cutscene is detected by neither.** Judge it from a PAUSED
screenshot.

# Transformers heat: the profile IS the fix, and it does apply

**Measured 2026-08-23 through `/device`.**

| | no profile applied | shipped profile |
| --- | --- | --- |
| frame rate | 126 | **30.0** |
| CPU junction | 77 C | **67 C** |
| charger input | 8206 to 9089 mW | **7408 mW** |
| cores busy | 3.74 to 3.91 | **3.04** |

**A boot without the profile renders an intro at 126 FPS on a handheld**, which
is where the heat came from. The shipped profile caps it at 30 and takes 10 C
and about 1.5 W off.

**Read the `/diag` config before believing any heat number.** The unprofiled
boots above came from `--ez thorReplaceCustomProfile false`, a debug-boot flag
and not what a user gets. The config readback is what exposed it: `frameLimit:
Off` and `rsxFifoAccuracy: Fast` where the profile says 30 and Atomic.

# FIRST MEASUREMENT OF TRANSFORMERS GAMEPLAY, and it is not the title screen

**2026-08-23.** Every earlier number for this title came from a title screen or
an intro, because the guest pad could not be driven. It can be now, so the game
was driven into a real level: intro skipped with START, then Solo Campaign,
then into the Decepticon Campaign.

| | title screen | REAL GAMEPLAY |
| --- | --- | --- |
| frame rate | 30.0 | **17 to 18** |
| CPU junction | 67 C | **85 to 96 C** |
| charger input | 7408 mW | **8300 to 13800 mW** |
| cores busy | 3.04 | **4.9 to 6.1** |
| SPURS threads | - | 6, running 2 to 6 |

**It cannot reach its own 30 FPS cap.** The thermal guard is engaged the whole
time and caps at 20, and the game sits at 17 to 18, so it is under BOTH caps.
This is CPU bound, not cap bound, and the title screen showed none of it.

## The gameplay hot path, named for the first time

A build-matched profile of that state, **147,559 samples, 0 lost, and a fatal
check run first**:

| offset | resolves to | share |
| --- | --- | --- |
| `+3773dc0`, `+dc4`, `+dc8`, `+dcc` | `vm::writer_lock::writer_lock` (`vm.cpp:712`) | **~13% combined** |
| `+37737dc` | `vm::range_lock_internal` (`vm.cpp:416`) | 2.85% |
| `+3861800` | `rsx::FIFO::FIFO_control::fetch_u32` | 1.60% |
| `+36df360` | `spu_thread::process_mfc_cmd` | 1.39% |
| - | `memcpy_opt` | 1.97% |

**VM range locking dominates gameplay**, which is the same signature this file
records for Transformers before `Accurate SPU Reservations: false` was measured
at -8.4% and then REVERTED on correctness grounds. The config readback confirms
`accurateSpuReservations: true` is what ran.

## A free win that was NOT free, checked before shipping

The second chain resolved to `perf_stat::push` inside `~perf_meter` inside
`range_lock_internal`, which reads as emulator instrumentation costing 2.85% in
the hottest function of the game.

**It is not.** `vm.cpp:312` constructs `perf_meter<"RHW_LOCK">` with the `(int)`
overload, which ZEROES the timestamps, so the destructor returns at its first
check long before the `perf_report` gate. The attribution is the DWARF line
table mapping a function epilogue to the last inlined thing.

That is this file's own "nearest-symbol attribution is not heat" trap, in an
inline-chain costume. The cost is `range_lock_internal` itself. **Nothing was
shipped for it.**

# A Transformers GAMEPLAY savestate exists now

`debug-captures/savestates/BLUS30357/`, 126.7 MB, captured in the Decepticon
Campaign level. Not tracked, because a savestate holds game memory.

    tools/thor_savestate_vault.sh restore BLUS30357

**This replaces six minutes of menu navigation with one command**, and it is the
first reproducible GAMEPLAY workload this project has had for this title. Every
lever that was unmeasurable on a title screen can now be measured on it.

## The route, recorded so it can be repeated

1. Boot with `thorRequireManagedProfile true` and `thorReplaceCustomProfile
   true`, or the profile does NOT apply and the intro renders at 126 FPS.
2. Poll `/scene`. While `advice` is `movie`, press `START` to skip.
3. `START` to leave the title screen.
4. `CROSS` on Solo Campaign, `CROSS`, `CROSS`.
5. Wait about 90 s for the level to load.

**Pause between steps.** The game does not wait while a screenshot is read.

# `am force-stop` LOSES TO THE RESPAWN, and that is how the device gets roasted

**2026-08-23. This is the most dangerous operational defect found here.**

A run was stopped, `pidof` answered empty, `top` showed no rows for the package,
and the temperature was reported as falling. Then it climbed: **56 C, 79 C,
95 C**, with nothing believed to be running.

The app was back at **542% CPU**. `am force-stop` had returned, the process had
respawned, and `pidof` had read empty a moment earlier purely by timing. One
force-stop and one `pidof` are not a stop.

**What actually stops it:**

    for i in 1..5: am force-stop <pkg>; kill -9 $(pidof <pkg>); sleep 2
    top -b -n 2 -d 2 | grep -c <pkg>      # confirm with TOP, not pidof

`thor_stop` does exactly that now and reports `quiet` only when `top` agrees.

## Temperature rides on EVERY tool response

The temperature used to be something to remember to check, and it was checked
after the damage. Every MCP tool now returns `cpuJunctionC`, including tools
that never touch the device, plus a `THERMAL` line at 70, 80 and 90 C saying
what to do.

`thor_boot` REFUSES above 70 C: booting a hot device measures the throttle and
cooks the handheld.

**A number nobody asked for is the only kind that gets seen in time.**

## And adb must be resolvable by the process that calls it

The MCP server defaulted to the repo's MSYS path, `/c/Users/.../adb`. Windows
Python cannot spawn that shape: it fails with `WinError 2, cannot find the file
specified`, which reads exactly like adb being absent. The server now converts
the MSYS shape, tries the SDK location, and falls back to PATH.

**A tool that cannot reach the device reports the same silence as a device that
is idle.** That is the same class as an unreachable adb answering empty like a
dead process.

# Transformers gameplay is inherently about 94 C, and that bounds every arm

Measured repeatedly: real gameplay in this title sits at **85 to 96 C** and
**4.9 to 6.1 cores**, whatever the harness does. The thermal guard is engaged
throughout and caps at 20 FPS, and the game still only reaches 17 to 18.

So an arm that runs gameplay back to back WILL hold the device near its ceiling.
Any SPURS hunt on this workload must either use short windows with real
cooldowns, or lower `thermal_guard_c` so the guard caps earlier and the heat
budget lasts longer.

**Do not run long unattended gameplay arms on this title.** The device belongs
to somebody.

# RULED OUT BY EXPERIMENT: a missed SPURS reservation notification

**2026-08-23.** The halt would not reproduce in 64 controlled boots, so instead
of waiting for the rare timing window the emulator was made to CREATE one.

`debug.rpcsx.thor.spurs_drop_notify = N` drops one reservation notification in N
for reservations INSIDE THE SPURS BLOCK, at both notify sites in `do_putllc`.
Default 0, and it announces itself in the log because it breaks a guarantee on
purpose.

**Run at 1 in 8, the most aggressive rate tried:**

    dropped 3840 of 30713 notifications   (CellSpursKernel2)
    dropped 4096 of 32761 notifications   (CellSpursKernel3)

**No halt. No SPU trap. No dead FIFO.** The title kept rendering at 27.33 FPS
through thousands of deliberately lost notifications.

## Why this is a real result and not a shrug

It confirms a code reading with an experiment. `SPUThread.cpp:6510` waits with
`atomic_wait_timeout{100'000}` and the loop then RE-READS the line, so a lost
notification costs at most 100 us of latency and cannot leave a stale read. The
theory deserved a test rather than a paragraph, and it failed the test.

**So the halt is not a reservation-visibility problem.** That removes the
mechanism this file has suspected longest, including the one behind the concern
about `Accurate SPU Reservations: false`, whose own comment says it works
because "we have notifications for nearly all writes".

## What that leaves

The guest refuses the CONTENT of the SPURS state, not its freshness. The next
injection targets are the limiter's own accounting rather than visibility:
`group->spurs_running`, `max_run`, and the timeout branch that fires when
`spurs_average_task_duration` grows.

Keep the injector. A negative that is reproducible is worth as much as a win,
and this one is one property away from being re-run.

# ALSO RULED OUT: the limiter sleeping too long

**2026-08-23, second injection.** `debug.rpcsx.thor.spurs_wait_scale` scales the
SPURS limiter's wait in percent; 100 is a no-op, 300 makes every SPURS thread
sleep three times too long. Default 100.

**Run at 300%, proven active in the log:**

    wait now 30000 us, applied 7680 times   (CellSpursKernel2)
    wait now 30000 us, applied 8192 times   (CellSpursKernel3)

The title degraded badly, 7.5 FPS then 0.71, which is what a scheduler
perturbation of that size should do. **No halt, no SPU trap, no dead FIFO.**

At 1000% the title stopped rendering entirely and still did not halt.

## Two mechanisms are now excluded by experiment

| injected | dose | result |
| --- | --- | --- |
| missed SPURS reservation notification | 3840 of 30713 dropped | no halt |
| limiter sleeps too long | 7680+ applications at 3x | no halt |

So the guest is not refusing stale state, and it is not refusing a workload that
merely ran late. **It refuses a VALUE.** The halt map says how: almost every site
is `HEQI rX, -1` or `HEQI rX, 0`, which is a guest checking a return code or a
handle and finding an error.

## What that points at next

A wrong VALUE reaching the guest has two plausible sources left:

1. **The SPURS structure content** written by the PPU-side HLE. Diffed against
   upstream with no semantic difference, so this needs a field-level check
   rather than another diff.
2. **Wrong code executing.** If the SPU block verifier accepts a block that is
   not the one in local store, the guest runs the wrong function and computes a
   wrong value, which is exactly the shape of these halts. The ARM64 checksum
   folds 24 words into 16 lanes, so it is LOSSY where the generic path is not.

The second is testable without reproducing the fault, because the generic
512-bit checksum is strictly more discriminating than the ARM fold. Measure what
it costs; if it is cheap, the safer verifier is the better default.

## The harness lesson from these two arms

**Boot spikes to 91 to 95 C during PPU compile and that is expected**, so a
thermal ceiling must not apply until the title renders. An earlier arm aborted
at 15 seconds and learned nothing because the injector had not run yet.

And a grep with a variable containing spaces, quoted with nested double quotes,
silently reported `inj=0` while the injection was firing thousands of times. The
first arm's phase-2 counts were a harness bug, not evidence.

# THE STRONGEST SPURS LEAD YET: the ARM64 block verifier cannot tell blocks apart

**Measured 2026-08-23 on the real dumped SPURS kernel image, no device needed.**

The ARM64 SPU block-verification checksum folds 96 bytes into 16 lanes by adding
pairs as `w + 2*w`, so 24 words go into 16 accumulators. The generic path keeps
64 bytes in 16 lanes, one word per lane, and folds nothing.

Over 1186 non-empty 384-byte windows of the live image:

| | count |
| --- | --- |
| DISTINCT-content pairs the ARM fold cannot tell apart | 25 |
| of those, the generic checksum also cannot | 8 |
| **pairs the generic WOULD have caught, the ARM fold does not** | **17** |

`0x150c0` against `0x15120` differ in **58 bytes** and produce the same ARM
checksum. A constructed pair confirms the invariance directly: add 2 to one word
and subtract 1 from its partner and the fold cannot see it, while the generic
checksum can.

**This is the shape the halt needs.** Accept the wrong block, run the wrong
code, compute a wrong value, and the guest refuses it. The halt map says almost
every site is `HEQI rX, -1` or `HEQI rX, 0`, a guest checking a return code.

## The fix, and why it satisfies "do not fix one game and break another"

`debug.rpcsx.thor.spu_strict_checksum = 1` makes ARM64 use the one-to-one form.

It cannot break a title by accepting something wrong, because it accepts
strictly FEWER blocks than today. The only risk is the opposite, rejecting
blocks it should accept, which shows up immediately as endless recompilation.

**Verified on the device:** `SPU Runtime: Built 3118 functions`, the same count
as the folded path, and the title renders at 29.60 FPS. No false rejections.

**Default OFF** until the throughput cost is measured. Strict covers 64 bytes an
iteration against 96, and a correctness fix on a hot path still has to show its
price.

## The mistake that proves the risk is real

The first attempt patched the LOOP path and the host mirror and left the TAIL
path folding. IR and mirror then disagreed, every block failed verification, and
the run spent **210 seconds with no `SPU Runtime: Built` line at 0.00 FPS**,
recompiling for ever.

That is exactly the failure the file warns about, produced by a one-sided edit.
Both emit sites and the mirror must change together, and
`tools/check_checksum_mirror.py` is the check that they agree.

# An emergency thermal stop, because a frame cap is not thermal protection

**The guard bounds the RENDER path and the heat is not there.** With the guard
engaged and holding 20 FPS, Transformers still climbed to 95 C, because one SPU
thread is busy regardless of presentation.

So there is a second line. If the junction stays at or above the abort
temperature for a few consecutive samples, `perf_monitor` PAUSES emulation. A
paused emulator measures 0.33 cores against 3.91 running, so this stops the heat
instead of asking the renderer to slow down.

    debug.rpcsx.thor.thermal_abort_c      default 100, 0 disables
    debug.rpcsx.thor.thermal_abort_dwell  default 3 samples, about 6 s

**The default is deliberately above normal play.** This title peaks at 94 to
97 C in gameplay, so 100 never fires in normal use and only catches a runaway.

**Do NOT set it below the PPU compile peak.** Compile legitimately reaches 91 to
95 C, so an abort at 90 fires on every cold boot. Measured: at 90 it tripped
during compile, exactly as configured.

An experiment SHOULD set it lower than the default, because a harness left
running unattended is how this device was held at 95 C in the first place.

# NOT ESTABLISHED: shortening the vm::writer_lock spin on Transformers gameplay

**2026-08-23.** The arithmetic was good and the target was chosen from a real
profile, and the result is still not a result.

`vm::writer_lock` spins up to 100 times at `busy_wait(200)`. The generic timer
here is 19.2 MHz, so each spin is about 10.4 us and the lock can burn **1.04 ms**
before it yields. That is an x86-derived spin count on a timer 170 times slower,
which is the one defect class that has paid off twice here: the lv2 spin at
1.3 ms was worth 69%, and `host_mutex_spin` was 1.56 ms.

The gameplay profile resolves INTO that loop: `vm::writer_lock` at about 13% and
`rx::prefetch_write`, which is `vm.cpp:712-713` inside the spin.

**Measured on the 3D scene, arms interleaved:**

| arm | cores | fps | n |
| --- | --- | --- | --- |
| default, 100 spins | 5.765 [5.755..5.776] | 19.55 | 2 |
| 8 spins | 5.735 | 19.63 | **1** |

**The treatment arm is n=1, so this is not a result.** This file forbids quoting
n=1 for good reason: one arm once read 10351 mW against 7545 and was written up
as a +37% regression, and the second arm of the same configuration came in below
both controls.

The fourth arm was correctly REFUSED by the gate, at `fps=0.00`, rather than
averaged in.

## What it suggests, and what would settle it

Cutting the spin from 100 to 8 did not move CPU or frames. That points at the
lock being TAKEN OFTEN rather than spun on for too long: with six SPU threads
contending, a shorter spin just reaches the `yield` sooner and pays a syscall
instead of a wait.

So the lever for this 13% is not the spin length. It is how often the lock is
taken, which is `Accurate SPU Reservations`, measured at -8.4% on the title
screen and reverted on correctness grounds.

**And one correctness objection to that revert is now weaker.** Its own comment
rests on having "notifications for nearly all writes", and dropping 3840 of
30713 SPURS-block notifications on purpose produced no fault at all. That does
not clear the setting, because upstream also reports it breaking InFamous, but
it removes the mechanism this file suspected.

To settle the spin question properly: three valid arms per side on the 3D scene,
which is about 40 minutes of device time at 90 C. It is not worth that until the
reservations question is answered, because that lever is an order of magnitude
larger.

# RETRACTED, same day: the ARM checksum is NOT the SPURS halt

**The measurement was right and the inference was wrong, which is the failure
this file records more than any other.**

The claim was that the ARM64 block checksum cannot tell blocks apart, from 25
pairs in the real SPURS image that collide under the fold while the generic form
separates 17 of them, one differing in 58 bytes. Every number there is correct.

**Those pairs are UNRELATED 384-byte windows, and the verifier never compares
unrelated windows.** It compares a block against the current content AT ITS OWN
ADDRESS. So the test measured something the verifier does not do.

## Tested the way the verifier is actually used

Take a real block and mutate it the way ANOTHER BUILD of a streamed job binary
would, then ask whether the checksum still matches. 8080 trials a row:

| edit | ARM fold missed | generic missed |
| --- | --- | --- |
| 1 instruction | 0 / 8080 | 0 / 8080 |
| 2 instructions | **17 / 8080** | **40 / 8080** |
| 3 instructions | 0 / 8080 | 0 / 8080 |
| 4 instructions | 0 / 8080 | 1 / 8080 |
| 8 instructions | 0 / 8080 | 0 / 8080 |

**The fold is not worse than the generic form on realistic edits, and at two
edits it is better.** It is blind only to a contrived paired change, add 2 to one
word and subtract 1 from its partner, which a compiler does not emit.

## So the default is reverted

The strict form still measures free, 2.708 cores against 2.740 with overlapping
ranges. **Free is not a reason.** A default change with no demonstrated benefit
carries risk and buys nothing, and this file already says a measured win is not
automatically a correct default. The property stays:

    debug.rpcsx.thor.spu_strict_checksum=1

## What this costs the SPURS hunt

The strongest remaining lead is gone. Three mechanisms have now been excluded:

| mechanism | how | result |
| --- | --- | --- |
| missed SPURS reservation notification | dropped 3840 of 30713 | no halt |
| limiter sleeping too long | 7680+ applications at 3x | no halt |
| block verifier accepting a wrong block | 8080 realistic mutations a row | fold is not the weaker one |

**Write the test the code actually performs, not the one that is easy to
write.** Comparing unrelated windows was easy and it answered nothing. Comparing
a block to a mutated copy of itself is the verifier's real question, and it took
the same twenty minutes.

# DRIVING A GAME: pause, screenshot, LOOK, decide, press. Never a blind sequence.

**This is not a preference. A blind press sequence corrupts the run.**

The failed way, and it failed on this title today: skip the intro, then fire
`START`, `CROSS`, `CROSS`, `CROSS` on a timer and assume the menus advanced. The
arm came back `INVALID (no 3D scene: fps=0.00 cores=1.100)` and the game was
sitting on the **Hasbro logo**, because the presses had landed on whatever
happened to be on screen.

## Why a timer cannot work here

**Transformers plays SEVERAL intro movies back to back**: Activision, Hasbro, a
developer logo, then the FMV. A fixed sequence desynchronises the moment any one
of them runs long or short.

**And `/scene` alone is not enough to skip them.** It reports `videoDecoding`
from an open `.bik`, so it goes FALSE in the GAP BETWEEN two movies. A skip loop
that breaks on the first "not a movie" exits mid-intro and then presses blind.
Measured: the probe read `source: none` while the Hasbro logo was on screen.

## The loop that works

    POST /pause          the game stops. It does not advance while you think.
    adb exec-out screencap -p > shot.png
    READ THE SCREENSHOT  decide what this screen is asking for
    POST /pad/press?...  thor_press resumes, presses, and re-pauses
    POST /pause          look again, confirm what changed

`thor_press` already resumes and re-pauses on its own, because a paused guest
cannot see a button.

**Pausing is the part that makes it correct**, not the part that makes it
tidy. Without it the screenshot is stale before it is read, and the button lands
on a scene nobody looked at. Verified: 3.91 cores running, 0.33 paused.

## What a script may and may not do

A script MAY: boot, cool, wait for frames, sample, and REFUSE an arm whose gate
does not pass.

A script MAY NOT: decide which button to press. That needs eyes on the picture.
So an experiment that requires navigation is driven by hand to the scene, and
then a savestate is captured so the scene is reproducible without navigating
again.

**Capture the savestate the FIRST time you reach the scene.** Reaching the
Decepticon Campaign by hand cost six minutes; restoring it costs one command.

# SPURS under REAL JOB DISPATCH: still no halt, and that closes the hypotheses

**2026-08-23, six runs of restored 3D combat.** Every earlier boot ended at a
title screen or an intro, where SPURS IDLES: `/diag` shows the group asleep and
the self-loop park counter reads `entries=0`. This arm ran the failing subsystem
under load.

| run | cores | fps | spursRunning | fault |
| --- | --- | --- | --- | --- |
| 1 | 5.632 | 18.33 | 3 | none |
| 2 | 5.560 | 18.33 | 2 | none |
| 3 | 5.580 | 18.31 | 2 | none |
| 4 | 5.340 | 17.79 | 2 | none |
| 5 | 5.060 | 17.79 | **6** | none |
| 6 | 5.200 | 18.00 | 3 | none |

**0 faults in 6 valid combat runs, 0 void.** No button presses were involved:
the savestate restores the scene directly, so nothing was pressed blind.

## The hypothesis list is now empty

| mechanism | how it was tested | result |
| --- | --- | --- |
| RSX FIFO accuracy | 27 Atomic, 10 Fast boots | no halt |
| driver wake-up delay | 12 at 20, 15 at 50 | no halt |
| heat | 15 boots at 94 to 97 C | no halt |
| CPU starvation | 12 boots, 5 spinners | no halt |
| missed SPURS notification | forced 3840 of 30713 drops | no halt |
| limiter sleeping too long | 7680+ applications at 3x | no halt |
| block verifier accepting a wrong block | 8080 realistic mutations a row | fold is not weaker |
| uninitialised SPURS state | source audit, `cellSpurs.cpp:1127` memsets it | ruled out |
| **SPURS under real job dispatch** | **6 combat runs, spursRunning 2 to 6** | **no halt** |

**About 90 controlled sessions and not one reproduction.** The fault is not a
function of a setting, of heat, of CPU scarcity, of notification loss, of
limiter timing, of block verification, of uninitialised state, or of SPURS being
busy.

## So stop trying to reproduce it

Each attempt costs two to five minutes and roughly 90 C on a handheld somebody
owns. Ninety of them have produced nothing. **The next occurrence has to be
caught in the wild, and it is now worth catching**: the handler decodes the halt
instruction, names the register and prints its value, prints the SPURS limiter
state, and dumps the four instruction words before the halt. One occurrence is a
diagnosis rather than a notification.

**What this arm DID deliver** is the workload this project lacked for two years:
a restored 3D combat scene, one command, 18 FPS at 5.5 cores, reproducible to
0.5 FPS across six runs. Every performance lever that was unmeasurable on a
title screen can now be measured on the scene that actually matters.

# FOURTH mechanism excluded: serialising SPURS does not cause the halt

**2026-08-23.** `debug.rpcsx.thor.spurs_max_run_clamp = N` clamps the limiter's
`max_run` at BOTH reads, so the SPURS group runs N threads at a time while the
guest still believes it has six. Default 0.

**Run at 1, the most extreme value, in restored 3D combat:**

    max_run clamp ACTIVE: 1, group asked 6, applied 16896 times

The game degraded as it should: 18.3 FPS to 14.6, 5.5 cores to 4.1. **No halt,
no SPU trap, no dead FIFO** across two minutes of fully serialised SPURS.

The guest cannot read `spurs_running` directly, but it CAN observe how many of
its threads progress, through its idle mask and its workload counters. If a
disagreement between the emulator's scheduling and the guest's expectation
caused the assertion, serialising six threads to one is the way to provoke it.
It does not.

## Ten mechanisms, none of them it

| mechanism | how | result |
| --- | --- | --- |
| RSX FIFO accuracy | 27 Atomic, 10 Fast | no halt |
| wake-up delay | 12 at 20, 15 at 50 | no halt |
| heat | 15 boots at 94 to 97 C | no halt |
| CPU starvation | 12 boots, 5 spinners | no halt |
| SPURS under job dispatch | 6 combat runs | no halt |
| missed SPURS notification | 3840 of 30713 dropped | no halt |
| limiter sleeping too long | 7680+ at 3x | no halt |
| **limiter scheduling, serialised** | **16896 clamps to 1** | **no halt** |
| block verifier | 8080 realistic mutations a row | fold not weaker |
| uninitialised SPURS state | `cellSpurs.cpp:1127` memsets it | ruled out |

**Four of those were FORCED, not waited for.** The injectors make the emulator
create the failure mode on demand, at doses far past anything a real run would
see, and the guest tolerated every one.

## What that means

The halt is not caused by anything this project can construct from the emulator
side: not a setting, not the machine's state, and not any perturbation of the
SPURS contract that has been thought of. Either it needs a guest state no arm
has reached, or its cause is outside the mechanisms enumerated here.

**Reproduction has cost about 92 controlled sessions.** The injectors stay,
because a negative that is reproducible is worth keeping, and each is one
property away from being re-run against a new idea.

# BUG CLASS: Shift By A Variable That Can Reach The Register Width

Found 2026-08-25 in `cellSpursSpu.cpp`, and it had hidden HLE SPURS for weeks.

```cpp
spurs->wklSignal1.raw() &= ~(0x8000 >> wklSelectedId);   // wklSelectedId can be 32
```

C says a shift by >= the promoted operand's width is UNDEFINED. What ARM64
actually does is worse than a trap, because it looks like it works:

- **A64 `LSR`/`LSL`/`ASR` take the shift amount MODULO the register width** -
  bits[4:0] for the 32-bit form, bits[5:0] for the 64-bit form.
- So `0x8000 >> 32` is assembled as a 32-bit shift by `32 & 31` = **0**, and
  evaluates to `0x8000` rather than the 0 the author assumed.

The line therefore became `wklSignal1 &= ~0x8000`, silently clearing workload 0's
signal - the ONE term that can start a taskset workload, since `wklFlag` reads
0xFFFFFFFF and `readyCount` is 0. Its guard is
`!isPoll || wklSelectedId == ctxt->wklCurrentId`, both 32 once an SPU parks in the
system service, so **six SPUs erased that bit on every poll**. Being stuck in the
system service was what triggered the clear that prevented ever leaving it.

x86 has the same modulo behaviour (`SHR` masks the count to 5 or 6 bits), so this
is not ARM-specific in principle - but it bites here because this is where HLE
SPURS actually runs, and because `wklSelectedId == 32` is the NORMAL state on
this path rather than an edge case.

## How to find the rest

The dangerous shape is a shift by an **id that has a sentinel value at or above
the register width**. In SPURS that sentinel is
`CELL_SPURS_SYS_SERVICE_WORKLOAD_ID = 32` against 32-bit masks:

```sh
grep -nE '(<<|>>) *(wklSelectedId|wklCurrentId)' ps3fw/cellSpursSpu.cpp
```

Audited the whole selector after the fix: every OTHER use of `wklSelectedId`
guards the sentinel explicitly -

```cpp
if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID) contention[wklSelectedId]++;
if (wklSelectedId != CELL_SPURS_SYS_SERVICE_WORKLOAD_ID) ctxt->wklLocContention[wklSelectedId] = 1;
```

which matters twice over: it confirms the signal clear was the unique unguarded
site, and it shows the array writes are NOT out of bounds even though
`contention[]` and `wklLocContention[]` hold only 16 entries. I checked that
before claiming a second bug, and there isn't one.

`wid`-indexed shifts elsewhere in `cellSpurs.cpp` are safe: every one is behind a
`wid >= CELL_SPURS_MAX_WORKLOAD2` validation, so the count stays <= 31.

## The lesson that generalises beyond shifts

Two "fixes" to the WRITE side - `vm::light_op` to a direct `atomic_op` - both
read back 0 and both looked like failures. **Neither write was ever broken.** A
reader elsewhere was erasing the value microseconds later. What separated the two
explanations was logging INSIDE the atomic operation as well as after it:

```
inside=<what the op saw>   readback=<same field, one line later>
```

When a store "does not stick", prove whether it happened before you go looking at
addressing, endianness or memory ordering.


## RETRACTION: the shift guard is correct about the UB and REGRESSES HLE

Measured 2026-08-25, one binary, four interleaved arms, 150 s settle:

```
fix=1  armed=0  emu stalls at 0:00:04   (2 of 2)
fix=0  armed=6  emu reaches 0:00:17     (2 of 2)
```

**The clear is load-bearing.** The undefined shift is real - `0x8000 >> 32` is UB,
AArch64 evaluates it as `>> 0`, and the PPU can be seen writing wklSignal1 and
reading 0x0 back one line later - but the SPURS state machine DEPENDS on the
signal being cleared. Leave it standing and `cellSpursModulePollStatus` reports
"selected workload differs from current" on every call, so the SPU exits to the
kernel and re-selects forever. Emulation livelocks before SPURS arms.

So `c6e6079b2` is not a fix on its own and is now **default off**, switchable via
`debug.rpcsx.thor.spurs_signal_fix`. The real repair is a consume-on-dispatch that
clears the signal for the workload the SPU actually runs, instead of relying on a
shift that only clears the right bit by accident.

**A correct statement about one line is not a correct change to a system.** The
shift analysis was right and the conclusion drawn from it was wrong, and only the
A/B separated them. Two earlier attributions this session failed the same way - a
"different CellSpurs" theory and a harness collision misread as a regression -
which is why this one was gated behind a property instead of asserted.

# THE HLE SPURS BLOCKER IS A SMALL-OBJECT LEAK, NOT SPURS LOGIC

Measured 2026-08-25, BLUS30357, same build, same device:

```
LLE control   peak 6714 MB   scudo OOM: 0    reaches emu 0:02:10, renders 30 fps
HLE forced    peak 6728 MB   scudo OOM in size classes 144 / 176 / 192
                             Process exited due to signal 9 (Killed)
                             forcing=2  create_handler=0  handler_entry=0
```

**Peak memory is the same to within 0.2%.** HLE does not use more memory - it
exhausts SPECIFIC small-object size classes while total usage matches the healthy
path. Scudo caps each size class at 256 MB, and 256 MB / ~176 B is about **1.5
million live objects**. That is an unbounded container or a leak on the HLE path,
not compiler pressure.

It is killed by SIGKILL **before `create_handler`**, i.e. before SPURS
initialisation begins at all.

## This retro-explains the entire day of HLE failures

- deaths at 4 s, 13 s and 17 s: one failure, caught at different points in the
  allocation ramp
- processes vanishing with NO crash record: SIGKILL leaves none, which is why
  `logcat -b crash` kept coming back empty
- the earlier `scudo::reportInvalidChunkState` abort: the same allocator, stressed
- BOTH selector probes reading zero: the code never ran, because the process died
  before SPURS
- and therefore why four "repair" A/Bs were worthless - they were measuring an
  OOM, not a signal change

## What NOT to do next

`spu_cache_worker_limit` / `spu_cache_preload_limit` / `compile_budget_ms` were
tried and made it die EARLIER. They bound SPU cache preload, and `create_handler=0`
proves death happens before SPURS work starts, so they cannot be the lever.

## What to do next

Find the container. Scudo size classes 144-192 B, ~1.5 M objects, on a path taken
only when `hle_libs` forces libsre.sprx to HLE. Candidates worth checking before
guessing: the per-SPU HLE function map (`RegisterHleFunction`, which this fork
made thread_local), anything per-workload or per-task allocated during HLE module
load, and any queue that the LLE path drains but the HLE path does not.

Total RAM is NOT the signal - it is normal. Watch the size-class OOM lines.

## CORRECTION: the signal fix is not inert - it crashes a SPURS kernel SPU thread

Reversed-order A/B settles what four earlier rounds could not:

```
fix=1  FAILED 12/12   (both orderings, with retries)
fix=0  passed  4/4
```

The property does control the outcome, so the "it is run order" retraction was
wrong in the other direction. What it controls is not a hang:

```
Emu Thread Name: 'SPU[0x2000100] CellSpursKernel2'
SIG: Thread time: 0.029795s   Faults: 0 [rsx:0, spu:0]
CPU Thread 'SPU[0x2000100] CellSpursKernel2' terminated abnormally!
Zygote: exited due to signal 11 (Segmentation fault)
```

**A SPURS kernel SPU thread segfaults about 30 ms into execution.**

### Absence of a log line is NOT absence of execution

This is the trap that cost the most time here. The selector probes read zero in
failing boots and I took that as proof the code never ran. RPCS3 installs its own
SIGSEGV handler and writes the register dump SYNCHRONOUSLY, while ordinary log
lines are buffered and lost when the process dies. Android produces no tombstone
for the same reason, which is why `logcat -b crash` kept coming back empty.

**On a crashing run, trust only synchronous output.** Everything buffered is
missing, not absent.

### The coherent reading

The fix works. The signal survives, the selector picks a real workload instead of
re-selecting wid=32, dispatch registers `spursTasksetEntry` at 0xA00, and the SPU
executes taskset policy-module code this HLE implementation does not fully
provide - and faults. Breaking the deadlock moves the failure from "never
dispatches" to "dispatches into unimplemented code", which is the expected next
frontier rather than a regression.

**NOT PROVEN:** the faulting PC was never captured - the log rotated before it
could be read. Copy RPCSX.log off the device immediately after the crash, before
the next boot recreates it. Then disassemble the taskset policy module at
`SPURS_IMG_ADDR_TASKSET_PM` (0x200) with Ghidra to see what `spursTasksetEntry`
must implement.

# HLE SPURS BREAKTHROUGH: the taskset workload dispatches for the first time

2026-08-25, with `debug.rpcsx.thor.spurs_signal_fix=1`:

```
Thor SPU1 dispatch#1: wid=32 addr=0x100     <- system service, as always
Thor SPU2 dispatch#2: wid=0  addr=0x200     <- SPURS_IMG_ADDR_TASKSET_PM
Thor SPU0 dispatch#2: wid=32 addr=0x100
...
CPU Thread 'SPU[0x0000100] CellSpursKernel0' terminated abnormally!   signal 11
```

**`wid=0 addr=0x200` is the taskset policy module.** Every previous run on this
branch dispatched `wid=32 addr=0x100` once per SPU and never moved. This is the
first time an SPU has left the system service.

So the shift fix is correct and it works:

  `0x8000 >> wklSelectedId` with wklSelectedId == 32 is undefined, AArch64
  evaluates it as `>> 0`, and it cleared workload 0's signal on every poll -
  the only live term in the selection gate. Guarding the sentinel lets the
  signal survive, selection picks the real workload, and dispatch registers
  `spursTasksetEntry` at 0xA00.

## And it reframes every "failed" A/B in this session

fix=1 failed 12/12 and I read that as a regression, then as run order, then as an
allocator leak. It was none of those: **the arm crashes BECAUSE it makes
progress.** It dispatches into taskset code this HLE implementation does not
fully provide, and faults ~20 ms later. A harness that scores "did it boot" marks
that as worse than a deadlock that boots cleanly forever.

**Scoring a repair by whether the boot survives will always prefer the deadlock.**
Score by how far the state machine gets - here, by whether a `wid != 32` dispatch
appears.

## Next, and this is where Ghidra returns

The fault is in taskset policy-module code. In HLE, 0x200 is only a MARKER -
there is no guest code to read - but the real implementation exists as SPU code
inside `libsre.sprx` (114,254 bytes, present in dev_flash), and in LLE the SPU
loads it into local store at **0xA00**.

Dump that LS window during live LLE combat and disassemble it, exactly as
`chunk-0x0f3c4` was proven to be 96.84% of `CellSpursKernel0`:

```
tools/ghidra_scripts/DumpMemoryRange.java        capture LS 0xA00
tools/ghidra_scripts/DisassembleSpuWindows.java  disassemble the window
```

That gives the reference implementation `spursTasksetEntry` must match, which is
the difference between guessing at the crash and reading what the code is
supposed to do.

# GHIDRA: the taskset policy module, disassembled

HLE now dispatches `wid=0 addr=0x200` (SPURS_IMG_ADDR_TASKSET_PM) and then faults
about 20 ms later. In HLE, 0x200 is only a MARKER - dispatch registers
`spursTasksetEntry` and no guest code is loaded - so there is nothing to read
there. The real module ships in `libsre.sprx` and LLE loads it into SPU local
store at **0xA00**.

Dumped LS during live LLE combat and disassembled it. Artifacts in
`debug-captures/spu-ls/`:

```
spu_ls_CellSpursKernel0.bin   262144 bytes, 50.6% non-zero
  0xA00 region: 486 / 512 bytes non-zero   <- real code, not padding
ls_A00.txt                    window around the entry
taskset_pm_full.txt           entry + both init routines
```

## The entry, which is what spursTasksetEntry stands in for

```
00000a00: ila r2,0x20db8         module identity constants
00000a10: il  sp,0x2c50          stack pointer for the policy module
00000a18: lqr r17,0x76a          load taskset state from LS 0x757..0x77a
00000a54: stqr r8,0x757          write it back
00000a64: brsl lr,0x00001ec8     init call #1
00000a68: brsl lr,0x00001778     init call #2
00000a70: stqa lr,0x2c80         ---- task CONTEXT SAVE AREA ----
00000a74: stqa sp,0x2c90
00000a7c: stqa r80,0x2ca0  ...  r92,0x2d60
```

The register-save block is the important part: this module implements **task
context switching**, saving callee-saved registers r80+ into a context area at
0x2c80. An HLE stand-in that does not maintain that area is exactly the shape of
thing that faults shortly after the first dispatch.

## Init routine at 0x1778

```
0000177c: il sp,0x2c30           its own stack
00001780: il r3,0x2c70
0000178c: stqa r3,0x2c30         publishes a pointer at 0x2c30
00001794: stqa r80,0x2c70        zeroes the structure at 0x2c70
00001798: il r3,0x5
0000179c: brsl lr,0x00000e40     call with arg 5
000017a0: lqd r4,0x20(sp)
000017a4: clgti r2,r4,0x7f       bounds check against 0x7f
000017a8: brnz r2,0x00001c50     -> error path if > 127
```

So the module builds state at 0x2c30 / 0x2c70 and bounds-checks a count against
127 - a taskset holds up to 128 tasks, so that is the task-id range check.

**Read this before writing more HLE taskset code.** The LS addresses it touches
(0x757-0x77a, 0x2c30, 0x2c70, 0x2c80-0x2d60) are the contract; an HLE
implementation that does not honour them will corrupt state the guest later reads.

## HLE boot instability: the SPU object cache is implicated, but clearing it is not a fix

The HLE path boot-loops. Cleared the SPU native object cache - 25,824 files,
246 MB, accumulated across every build and setting tried in one session - and
re-ran:

```
t+60s   emu=0:01:04   <- first boot on the fresh cache, 9x further than before
t+90s   emu=0:00:04   <- then progressively worse as the cache refills
t+270s  emu=0:00:07
```

Before clearing, HLE died at emu 0:00:07 on 5 of 5 attempts. The first boot after
clearing reached 0:01:04. So cache size is IMPLICATED - it matches the scudo
failure signature, size classes 144/176/192 exhausted at 256 MB each (~1.5M small
objects) while total RAM stays normal at 6.7 GB, the same as a healthy LLE boot.
Tens of thousands of small objects loaded at boot is how that distribution
arises.

**But clearing it did not fix HLE.** It still never arms, and it still loops.

Note the earlier mitigation attempt was aimed wrong: `spu_cache_worker_limit` and
`spu_cache_preload_limit` bound compile CONCURRENCY, not the NUMBER of cached
objects loaded, and they made it die sooner.

`rm -rf` on that directory silently does nothing from the shell - it is
`drwxr-s---` owned by the app. Use `run-as net.rpcsx.easy rm -rf <dir>` on a
debuggable build. The same permission shape blocks `config/patches/`.

### State of HLE at the end of this session

Two real bugs found and fixed, both AArch64-specific, both confirmed by Ghidra:

1. `0x8000 >> 32` is undefined; AArch64 evaluates it as `>> 0`, erasing workload
   0's signal every poll - the only live term in the selection gate. FIXED and
   VERIFIED: produced the first `wid=0 addr=0x200` taskset dispatch on this branch.
2. The taskset syscall entry at 0xA70 was never registered, so the SPU branched
   there and executed zeros. FIXED, NOT VERIFIED - no boot has reached it.

What blocks verification is boot instability, not either fix. An LLE control on
the same binary reaches emu 0:02:10 and renders at 19.19 fps.

**Next: make the HLE boot survive.** Until it does, no HLE change can be judged.

## RETRACTED: "the HLE boot is SIGKILLed by the allocator"

Every HLE boot failure this session was scored as "died early" or "boot loop".
That framing was wrong and it cost rounds, because it invited theories about
emulator state - a deadlock, a bad jump, the object cache - when the emulator
was never the thing making the decision.

The emulator's own log simply STOPS mid-boot, around 0:00:02 emulated. There is
no `terminated abnormally`, no assertion, no fatal line. RPCS3 writes crash
dumps synchronously, so their absence is evidence. `logcat -b crash` is EMPTY
and `/data/tombstones` gains nothing: **Android emits no tombstone for SIGKILL**.

logcat names the killer:

    scudo: Scudo OOM: The process has exhausted 256M for size class 144.
    scudo: Scudo OOM: The process has exhausted 256M for size class 176.
    scudo: Scudo OOM: The process has exhausted 256M for size class 192.
    ActivityManager: Process net.rpcsx.easy (pid 8497) has died: fg TOP
    Zygote: Process 15396 exited due to signal 9 (Killed)

Scudo caps EACH size class at 256 MB independently. Three adjacent small-object
classes fill within ~8 seconds of process start - roughly 1.8 M live objects per
class - while emulated time has advanced only ~2 s. The process is over no
total-RAM limit; a healthy LLE boot reaches the same RSS. It dies because one
allocation SHAPE runs away, not because memory runs out.

### Why the earlier "symptom, not cause" verdict was wrong

Disabling `spu_native_object_cache` produced `scudoOOM=0` while boots still
failed, and that was read as clearing scudo of involvement. It does not: it
shows the cache is *a* contributor to those classes, not that the classes are
innocent. The OOM reappears with the cache on, and the kill signature is
unambiguous. Treat `Scudo OOM` in logcat as the primary boot-failure signal.

### Two allocation sites already excluded

- **`RegisterHleFunction`** - `g_thor_spu_hle_functions` is a
  `std::map<u32, bool(*)(spu_thread&)>`. Assigning an existing key allocates
  nothing, and a node is ~48 B. Wrong size class, wrong behaviour. Re-registering
  the taskset syscall entry on every `spursTasksetEntry` is not a leak.
- **Thor probe logging** - every probe on this path is one-shot guarded
  (`thor_hle_once`, or `s_seen[spu.index].fetch_add(1) < 2`). Note this vector is
  real though: commit 36cb52ca1 boot-looped the branch with per-dispatch logging,
  which is the same failure by a different producer. Never add an unguarded log
  to the SPURS kernel, selector, or dispatch path.

### How to find the site without root

`am dumpheap -n` and `libc.debug.malloc.options backtrace` both need `adb root`,
and the Thor is a production build - `adbd cannot run as root`. So the allocation
site has to be bisected from inside the build. Both HLE fixes are now
property-gated for exactly this:

    debug.rpcsx.thor.spurs_signal_fix      0/1
    debug.rpcsx.thor.taskset_syscall_fix   0/1

One binary, four cells (baseline HLE / signal only / both / LLE control), reading
only whether `Scudo OOM` appears. That separates "my fixes allocate" from "the
HLE path always did".

## Check the device model before every device run

A full diagnostic round - install, boot, logcat capture - was executed against a
**Quest 2**. Two devices are attached:

    1WMHH830AY1165   Oculus Quest 2
    192.168.1.3:5555 AYN Thor

The captured log was full of `VrApi`, `boltlib`, and Oculus auth errors, which is
the only reason it was caught. Every harness now opens with a guard, and any new
one must too:

    MODEL=$($A shell getprop ro.product.model | tr -d '\r')
    [ "$MODEL" != "AYN Thor" ] && { echo "WRONG DEVICE: '$MODEL'"; exit 1; }

## The game boots by intent, not by launching the activity

A harness that only runs `monkey -p net.rpcsx.easy` lands in the UI and boots
nothing. The app then sits at 0 fps forever and looks like a hang. The real boot
is an intent carrying the ISO:

    am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity \
      --es path '<ISO>' --es titleId BLUS30357 --es thorDebugBootRequestId <tag> \
      --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true

## The retraction, measured: scudo OOM is NOT the HLE boot killer

The section above was written from a single HLE boot's logcat and is wrong. A
four-cell bisect on ONE binary, using the new property gates, settles it:

    cell                 scudoOOM  deaths  armed  emu
    A baseline HLE          3        0       6    0:00:18
    B signal fix           21        6       0    0:00:18
    C both fixes           21        6       0    0:00:18
    D LLE control           3        0       0    0:02:10

**The LLE control emits the same three `Scudo OOM` lines and runs fine.** Three
OOM messages - one per size class - is what a NORMAL boot on this device prints.
The 21 in B/C is 6 restarts x ~3 per boot: the count scales WITH the deaths, so
it is a consequence of restarting, not a cause. Reading "Scudo OOM in logcat" as
the failure signal is a mistake; it is background noise on this hardware.

What the bisect actually proves:

- **`spurs_signal_fix=1` is what breaks the boot.** B and C both restart 6 times
  in 120 s. This reproduces exactly what the in-code comment already recorded
  ("fix=1 armed=0 twice, against fix=0 armed=6 twice"). `armed=0` there is a
  SAMPLING ARTIFACT, not a claim that arming never happens - the log is read at
  the end of the window, and the last restart is only seconds old.
- **`taskset_syscall_fix` is neutral.** B and C are identical in every column, so
  registering 0xA70 neither helps nor harms. Every earlier suspicion that it
  caused the regression was wrong.
- **Baseline HLE arms 6 kernels and survives** - but emulated time sticks at
  0:00:18 while LLE reaches 0:02:10. That is the weeks-old deadlock, alive but
  frozen, and it renders NOTHING. HLE has never produced a frame to measure.

## The vise, and why the shift guard is not the way out

    clear at selection (baseline)  -> 0x8000 >> 32 eats workload 0's signal
                                      -> six SPUs park on wid=32 -> DEADLOCK
    do not clear (signal fix)      -> "selected differs from current" forever
                                      -> restart loop -> LIVELOCK

Both ends fail, so the defect is not at the clear site.

## Ghidra: what the REAL kernel does at 0x290

Disassembled `CELL_SPURS_KERNEL1_SELECT_WORKLOAD_ADDR` (0x290) out of
`debug-captures/spu-ls/spu_ls_CellSpursKernel0.bin` with the SPU language
(`analyzeHeadless ... -processor SPU:BE:128:default -postScript
DisassembleSpuWindows.java out.txt 0x300 0x290 0x818 0x808 -noanalysis`):

    00000298: ila  r8,0x8000        ; mask base
    000002c4: rotqbyi r20,r10,0xc   ; r20 = selected workload id
    000002d8: ceqi r7,r20,0x20      ; EXPLICIT test: id == 32 (system service)
    000002dc: sfi  r9,r20,0x0       ; r9 = -id
    000002e0: sfi  r5,r7,0x0        ; r5 = -(id == 32)
    000002e4: rotm r6,r8,r9         ; r6 = 0x8000 >> id
    000002e8: or   r3,r29,r5        ; folds "id == 32" INTO THE RESULT
    000002f4: fsmb r32,r6           ; mask -> byte mask
    00000380: andc r17,r21,r32      ; candidates &= ~mask

Two findings, both load-bearing:

1. **SPU `rotm` shifts in zeros and gives 0 for any count >= 32.** So on real
   hardware `0x8000 >> 32` is ZERO and clears nothing. The AArch64
   shift-modulo-32 that turns it into 0x8000 is a genuine port bug, and
   "clear nothing" is hardware-correct. The guard is right about the semantics.
2. **The hardware kernel uses that mask to EXCLUDE the selected workload from the
   candidate set (`fsmb` + `andc`), not to clear a signal word in memory**, and it
   separately folds `id == 32` into the returned value. The HLE port instead
   writes `wklSignal1/2` in memory. That structural difference - not the shift -
   is the remaining gap, and it explains why fixing only the shift livelocks: the
   clear becomes correct while the selector's result stays wrong.

Checked and cleared while looking (do not re-investigate):

- `wklSignal2 &= ~(0x80000000u >> id)` looks wrong for a `be_t<u16>` but is not:
  for wids 16..31 it produces exactly `0x8000 >> (id-16)`, and for 0..15 it
  truncates to a no-op. Only `id == 32` is broken.
- `std::memcpy(ctxt, spurs, 128)` at the end of the selector cannot clobber the
  selection: `tempArea[0x80]` is the first 128 bytes and `wklCurrentId` sits at
  struct offset 0xDC.

## XFloat Accuracy: the biggest measured lever so far, +16.2%

The shipped default is `Approximate` (`system_config.h`). `Inaccurate` is faster
by a wide margin on this title, and unlike every other candidate this session it
REPRODUCED ACROSS ROUNDS.

Eight arms, two independent rounds, interleaved approx/inacc so drift cannot
favour one side, each arm restoring the SAME savestate and gated on
`coresBusy > 4.5` so only restored 3D combat counts:

    Approximate  16.67  16.08  16.45  15.70   mean 16.23
    Inaccurate   18.92  18.82  18.89  18.76   mean 18.85

Non-overlapping ranges, and `Inaccurate` is the TIGHTER distribution - 0.85%
spread against 6%. Compare with the SPU Block Size "+16.5%" that collapsed to
+3.2% once a better-controlled round ran: that one never reproduced, this one
did, twice.

Verified visually, because the mode is LOSSY and a frame rate means nothing if
the picture is wrong. The same restored scene captured under both settings
(`scratchpad/xf_approx.png`, `xf_inacc.png`) is pixel-plausible identical:
same camera, same geometry, same effects, no corruption. Those two screenshots
also served as the scene fingerprint, which mattered because:

**The draw-count fingerprint DOES NOT EXIST on `hle-spurs-wip`.** `drawsLastFrame`
and `drawActivity` live on `master` only, so `/scene` on this branch returns
`videoDecoding/source/videoFile/advice` and nothing else. Every arm printed
`draws/frame=0 scenePolls=0`. Do not trust that field on this branch; either
cherry-pick it from master or control the scene by construction (same savestate,
same `coresBusy` gate) and confirm with a screenshot.

Recorded rather than buried: the in-game overlay at the two capture instants read
20.32 (approx) against 20.78 (inacc), much closer than the windowed averages. A
single instantaneous sample is noise against a 6-sample 60 s window, and the
windowed ranges do not overlap, so the averages are what is trusted - but the
discrepancy is real and someone should watch for it.

Scoped to BLUS30357 only. `Inaccurate` is lossy, upstream defaults to
`Approximate` deliberately, and nothing measured here licenses it for other
titles.

### The harness bug that hid the fingerprint for a whole round

`xfloat_ab.sh` computed the fingerprint with escaped quotes inside `awk`:

    awk -v s=\"${ds:-0}\" -v k=\"$n\" 'BEGIN{print s/k}'

awk received literal quote characters, so every arm was a division by zero and
printed `draws/frame=0`. The check that exists specifically to catch
incomparable scenes silently did nothing. It now also prints `scenePolls`, so a
missing field is distinguishable from a genuine zero, and resets that counter per
arm rather than accumulating across the round.

## THE DEADLOCK IS BROKEN: an SPU selected a real workload

First time in this branch's history. With `spurs_signal_fix=1` and
`spurs_sel_cond_fix=1`:

    Thor SPU5 SELECTED REAL WORKLOAD wid=0 (isPoll=1)
    Thor SPU0 SELECTED REAL WORKLOAD wid=2 (isPoll=1)
    select#1 wkl0: runnable=1 prio=1 maxCont=8 cont=0 ready=0 signal=1

All four gate terms pass. For weeks the answer was six SPUs on `wid=32` forever.

### What the Ghidra read bought

The selector's branch, from the real kernel at LS 0x290:

    00000290: ceqi r30,r3,0x0      ; r30 = (arg0 == 0)      -> !isPoll
    00000294: lqr  r10,-0x31       ; PC-rel: 0x294 - 0xc4 = LS 0x1d0
    000002c4: rotqbyi r20,r10,0xc  ; bytes 12..15 of 0x1d0 = 0x1dc
    000002d8: ceqi r7,r20,0x20     ; r7  = (wklCurrentId == 32)
    000002e8: or   r3,r29,r5       ; !isPoll || wklCurrentId == 32

LS 0x1dc is `SpursKernelContext::wklCurrentId`. Hardware asks "am I running the
SYSTEM SERVICE"; the port asked "did the selection change". Parked in the system
service, `currentId` is 32, a selected workload 0 fails `0 != 32` and is routed
to the context-switch path, which exits and re-selects forever. That one wrong
comparison is the livelock, and fixing it also fixed the boot loop:
`sig=1` alone armed 0 of 4 boots, `sig=1 + selcond=1` arms 6 and survives.

### The defect the fix itself introduced, and the repair

Both selections carry `isPoll=1` - they come from `cellSpursModulePollStatus`,
which only asks "should I yield?". A widened commit condition made the POLL
consume the signal: it cleared `wklSignal1`, so when the kernel then selected for
real (`isPoll=0`) the signal was gone, it picked 32, and dispatched the system
service again. The same deadlock, displaced by one step.

The original condition could not hit this - during a poll it only fired when
nothing changed. **Widening the commit requires narrowing the clear.** A poll now
reports its selection and consumes nothing (`consumeSignal = !selcond || !isPoll`).

### Probe discipline: every one-shot probe on this path fired too early

`select#1` printed `runnable=0 prio=0 maxCont=0` for days and was read as a stuck
gate. It was not - the probe fires at FIRST selector entry, which is before the
PPU creates and activates the workload. Timeline from one run:

    12.169976  select#1 probe    (200th call)   signal=0
    12.175456  cellSpursSendWorkloadSignal(wid=0)  readback=0x8000

Even the 200th call lost the race. Probes on this path must fire on the
CONDITION (`wklSignal1 != 0`), not on a count. `debug.rpcsx.thor.sel_probe_nth`
exists but is the weaker tool.

Three theories died to this, all retracted: a stale LS snapshot (the selector uses
`ctxt->spurs.get_ptr()`, live memory), a workload-ID mismatch (the `wid=1` signal
came from a differently-configured run; with the job queue left as LLE the game
correctly signals `wid=0`), and scudo OOM as the killer (the LLE control emits the
same three lines and runs fine).

### Harness note

`armed == 6` is the WRONG validity test. `armed=12` means the SPURS group armed
twice, which is a further-along boot, not an invalid one. Test `armed >= 6`.

## HLE SPURS RUNS: taskset dispatched and executing, no halt

    Thor SPU1 dispatch#2: wid=0 addr=0x200 size=0x1e40
    Thor SPU2 dispatch#2: wid=0 addr=0x200 size=0x1e40
    Invalid taskset state: 0    Halt at 0x00a00: 0    segfaults: 0
    process alive, coresBusy=4.059

`addr=0x200` is SPURS_IMG_ADDR_TASKSET_PM. For weeks this was six SPUs parked on
`wid=32`. Four fixes were needed, in this order, and each only makes sense with
the ones before it:

1. **`spurs_signal_fix`** - `0x8000 >> 32` is UB and AArch64 evaluates it as
   `>> 0`, erasing workload 0's signal. Ghidra: hardware uses `rotm`, which
   shifts in zeros and yields 0 for any count >= 32, so hardware clears NOTHING.
2. **`spurs_sel_cond_fix`** - the selector's commit branch. Hardware at LS 0x290
   asks `!isPoll || wklCurrentId == 32`; the port asked
   `!isPoll || wklSelectedId == wklCurrentId`. Parked in the system service,
   `currentId` is 32, so a selected workload 0 failed `0 != 32` and was routed to
   the context-switch path forever. This ALSO cured the boot loop: `sig=1` alone
   armed 0 of 4 boots, `sig=1 + selcond=1` arms and survives.
3. **poll must not consume the signal** - widening the commit meant a POLL
   (`cellSpursModulePollStatus`, "should I yield?") was clearing `wklSignal1`, so
   the kernel's real selection found nothing and dispatched the system service
   again. Widening the commit REQUIRES narrowing the clear.
4. **`taskset_enabled_fix`** - see below.

### The task-id allocator wrote into the wrong half of the bitset

`CellSpursTaskset::enabled` is `atomic_be_t<u32> values[4]`, addressed everywhere
by `get_bit(b) = values[b/32] & ((1u<<31) >> (b%32))`. `pending_ready`, `get_bit`
and the SPU-side validity check all use that word layout. The allocator in
`cellSpursCreateTask` instead reinterpreted the field as one `be_t<v128>` and
allocated from `_u64[0]` - but converting a 128-bit big-endian value REVERSES ALL
SIXTEEN BYTES, which swaps the two u64 halves as well as the bytes within them.
`_u64[0]` is therefore not `values[0]`, so the same task landed in a different
half depending on which writer touched it:

    Thor INVALID TASKSET STATE: tasksetAddr=0x101b4e80
      en     = 8000000000000000 0000000000000000
      pready = 0000000000000000 8000000000000000

The taskset policy module then fails its own check - pending-ready but not
enabled - logs "Invalid taskset state", halts, and the process dies. The code's
own comment named the correct behaviour and then deviated from it: "Realfw
processes this using 4 32-bits atomic loops / But here its processed within a
single 128-bit atomic op". Doing the four 32-bit loops fixes it.

This is an UPSTREAM RPCS3 bug, not Thor-specific, but it only bites when
`cellSpurs` is HLE'd, so the shipped LLE path is unaffected.

### Read logcat, not RPCSX.log, for anything near a crash

RPCSX.log loses its buffered tail when the process dies, and a taskset halt kills
the process. An entire round was scored `armed=0 activate=0 real=0` from
RPCSX.log while logcat held `dispatch#2 wid=0 addr=0x200` for the same boot.
logcat's android sink is synchronous. This trap was already recorded once and was
walked into again.

## Where HLE SPURS actually stands: runs deep, renders nothing

After the four fixes, the chain runs end to end:

    kernel arms -> selector picks a REAL workload -> taskset dispatches at
    addr=0x200 -> taskset PM passes its own validity check -> the TASK's ELF
    executes at PC 0x04a00

That is far past the wall this branch sat behind for weeks. It still produces
**zero frames**, and two runs bound the failure:

    spu_trap_stop=1 (pause on halt)   300s: frames=0, cores FLAT at 4.059,
                                      35C -> 84C, process died at t+320s
    spu_trap_stop=0 (keep running)    220s: frames=0, cores ~5.96 (all six SPUs
                                      pinned), halts=0, 47C -> 92C

The guest task executes a conditional HALT (`HEQ`/`HGT` -> `make_halt` ->
the `0xffdead00` store in SPULLVMRecompiler). With the trap guard on, Thor pauses
and the flat 4.059 core reading is paused-but-spinning. With it off, there is no
halt recorded at all and all six SPUs spin at full tilt with no frame ever
presented - a LIVELOCK, not a crash.

So the remaining defect is not in workload selection or taskset validation. It is
in what the task does once it runs: either the arguments handed to it by
`spursTasksetStartTask` (gpr[3] = taskArgs, gpr[4] = taskset args / spurs addr)
are wrong, or a syscall it makes returns something it will not accept.

**HLE has contributed no frames. The shipped frame rate is 18.85 fps and comes
entirely from XFloat Accuracy: Inaccurate.** Do not let the depth of the SPURS
progress imply otherwise in any report.

### Heat, measured while doing this

HLE livelock puts six SPUs at 100% and takes the device from 47C to 92C in under
four minutes while rendering nothing. Any HLE soak must cap runtime and cool
between arms, or it cooks the Thor for no data.

## SPU Block Size Mega: +2.2% FPS and -5.6% CPU, and why it never applied before

    safe  18.90  18.83   mean 18.87   cores 5.61
    mega  19.36  19.19   mean 19.28   cores 5.30

Interleaved safe/mega/safe/mega, same savestate, gated on coresBusy > 4.5,
measured ON TOP OF XFloat Accuracy: Inaccurate - so the two compose. Ranges do
not overlap. The CPU drop is the more valuable half on a device that sits in the
nineties Celsius.

**It had never actually been applied on this branch.** Two independent reasons,
both silent:

1. `debug.rpcsx.thor.spu_block_size` passed the lowercase word to
   `from_string`, whose canonical spelling is `"Mega"`. The call failed, the
   value stayed `Safe`, and the code still logged "forced to mega". Every
   `/diag` in this session reported `spuBlockSize "Safe"`, including during runs
   believed to be testing Mega. Fixed: canonicalise, check the return, log the
   value actually in effect. Same trap as XFloat's `"Inaccurate"`.
2. `sanitizeThorManagedConfig` on THIS branch only rewrites ASMJIT -> LLVM. The
   "inject Mega when the profile is silent" logic lives on `master`, like the
   draw-count scene API. Do not assume master's adaptation-layer behaviour exists
   here.

Engagement proof, and use one every time a setting claims to be applied: the SPU
object cache grew 3794 -> 4556 on the first mega arm. A setting that changes the
recompiled IR MUST produce new objects; an arm where the count does not move did
not engage.

## Driver Wake-Up Delay 0: +2.8%, and it was boot-tested before shipping

    delay 50   19.41  19.36   mean 19.39
    delay 0    20.05  19.81   mean 19.93

Interleaved, on top of XFloat Inaccurate and SPU Block Size Mega, same
savestate, `coresBusy > 4.5`, non-overlapping ranges.

The profile had 50 us **for stability, not speed**: an earlier note recorded that
at 20 us this title crashed roughly two boots in five with an SPU halt in
CellSpursKernel0, against 0 of 4 at 50 us. A 2.8% gain is not worth a 40% crash
rate, so 0 was boot-tested rather than benchmarked and shipped:

    delay 0    0 crash / 5 boots
    delay 50   0 crash / 5 boots

A 2-in-5 rate would have shown in ~87% of samples this size. What this does NOT
prove: five boots cannot establish equality, and 20 us was never retested - 0 and
20 are different points on that curve. If random SPU halts in CellSpursKernel0
come back, this is the first line to revert.

## Running total on BLUS30357, all measured in restored 3D combat

    shipped at session start        16.23   (Approximate + Safe + delay 50)
    XFloat Accuracy: Inaccurate     18.85   +16.2%
    + SPU Block Size: Mega          19.28   +2.2%,  -5.6% CPU
    + Driver Wake-Up Delay: 0       19.93   +2.8%

**+22.8% total.** Two of the three had never actually been applied: `from_string`
matches the enum's canonical capitalisation, so the lowercase property values
failed silently while the log claimed success.

30 FPS needs +50% from 19.93. Every config knob on this path has now been swept -
xfloat, block size, wake-up delay, reservations, loop detection, verification,
affinity (big-core pinning measures 15.32 against 19.07 default, so the A510s
carry real work). None of the remainder is worth more than low single digits.
The only lever sized for the gap is HLE SPURS, which now runs into the task's own
ELF and livelocks with six SPUs pinned and zero frames.

## The taskset syscall entry used to THROW, and that invalidates one earlier verdict

`spursTasksetSyscallEntry` contained, immediately after handling the syscall:

    fmt::throw_exception("Broken (TODO)");
    // if (spu.m_is_branch == false) {
    //     spursTasksetResumeTask(spu);
    // }

That is why upstream left the `0xA70` registration commented out. **It also
retracts the bisect verdict that `taskset_syscall_fix` was "exactly neutral".**
It was not neutral - nothing had ever reached a task, so no task ever made a
syscall, so the throw was never hit. B and C matched because the code under test
was unreachable, not because it did nothing.

`spu.m_is_branch` was removed along with `custom_task`. The test it stood for is
observable: a syscall that switches context MOVES pc (`cellSpursModuleExit` sets
`pc = ctxt->exitToKernelAddr`). So snapshot pc, run the syscall, and resume the
task only if pc is untouched. Verified: 0 `Broken (TODO)` throws in a 480 s run
where tasks dispatch and run.

### Still blocked: the task halts on its own assertion

    480s: frames=0, cores FROZEN at 5.040, tasksetDispatch=1, task halts=2,
          37C -> 89C, thermal guard engaged (cap 30, never binds at 0 fps)

The task executes a conditional HALT (`HEQ`/`HGT`). No throw, no invalid taskset
state, no segfault - the guest itself decides its inputs are wrong. So the next
question is what `spursTasksetStartTask` hands it:

    gpr[2] = 0
    gpr[3] = taskArgs (128-bit)
    gpr[4] = { spurs address, taskset->args }
    gpr[5..127] = 0
    pc = ctxt->savedContextLr._u32[3]

Ghidra note for whoever picks this up: the real policy module CLEARS local store
0x3000..0x3d000 before starting a task (`il r38,0x3000` / `ila r39,0x3d000` and a
computed `bi r5` into an unrolled `stqd` run at 0x18b0-0x18ec). The HLE
`spursTasksetStartTask` does no such clear. That is a concrete, testable
difference and the obvious next thing to try.

## The task's assertion, named by the trap decoder, and fixed

The SPU trap decoder in this tree does the work that a bare pc cannot:

    SPU trap 0xffdead00: HALT ... thread='CellSpursKernel0' pc=0x04a00
    SPU trap decoded: HEQI (halt if equal to immediate) at pc=0x04a00.
      r55 = 0x00000000 (0), immediate = 0. The guest refused this value.
    SPU trap arg r4 = 00000000 00000000 00000000 00000000

`r4` is exactly what `spursTasksetStartTask` loads with the SPURS address and the
taskset args. It was zero, so the task refused it.

**Cause: the taskset snapshot at LS 0x2700 is never filled.**
`SpursTasksetContext` opens with `tempAreaTaskset[0x80]` at 0x2700 - scratch meant
to hold a DMA'd copy of the taskset head - and `CellSpursTaskset` keeps `spurs` at
0x60 and `args` at 0x68, both inside it. That is why the code reads
`spu._ptr<CellSpursTaskset>(0x2700)`. But `spursTasksetEntry` memsets the whole
context, and the only other write is

    std::memcpy(spu._ptr<void>(0x2700), spu._ptr<void>(0x100), 128); // Copy data

at the end of `spursTasksetProcessRequest`, which copies the KERNEL's `CellSpurs`
head from LS 0x100 - the wrong structure - and runs BEFORE
`spursTasksetStartTask` reads it.

Identical to the defect the idle handler already documents in this file
("REFRESH THE SNAPSHOT BEFORE READING IT"), and the identical repair: copy the
live taskset in before reading. Exactly 128 bytes, so it lands in
`tempAreaTaskset` and cannot touch context fields starting at 0x2780.

RESULT, measured: `halts` goes 2 -> **0**, and `coresBusy` rises 5.02 -> 6.38 -
the SPUs are doing real work instead of sitting halted.

**Still frames=0.** Tasks now run without asserting and the title still does not
render in 240 s. Whatever remains is downstream of task entry.

## Running score, so nobody has to re-derive it

Seven HLE defects fixed, in the order each became visible:

    1. 0x8000 >> 32 UB erasing workload 0's signal   (Ghidra: rotm gives 0)
    2. selector commit branch tested the wrong operand (Ghidra: LS 0x290)
    3. a POLL consumed the signal                     (side effect of 2)
    4. task-id allocator wrote the wrong bitset half  (upstream be_t<v128> bug)
    5. syscall entry threw "Broken (TODO)"            (also retracts the
                                                       "syscall fix is neutral"
                                                       verdict - it was
                                                       UNREACHABLE, not inert)
    6. task LS clear ran to 0x40000, hardware stops at 0x3d000 (Ghidra)
    7. taskset snapshot at LS 0x2700 never refreshed  (trap decoder: r4 = 0)

Shipped frame rate is 19.93 fps and comes entirely from config
(XFloat Inaccurate, SPU Block Size Mega, Driver Wake-Up Delay 0).
**HLE has contributed zero frames.**

## WHY HLE SPURS CANNOT RENDER THIS TITLE: the queue API is not implemented

This closes the question. Seven defects were found and fixed, the taskset
dispatches, the task runs without asserting - and the game still freezes at
emulated 0:00:09. The last thing the PPU does:

    cellSpurs TODO: cellSpursQueuePushBody()
    cellSpurs TODO: cellSpursQueuePushBody()

Every SPURS queue function in `cellSpurs.cpp` is a bare stub. They do not even
declare parameters:

    s32 cellSpursQueuePushBody()
    {
        UNIMPLEMENTED_FUNC(cellSpurs);
        return CELL_OK;
    }

Eleven of them: `_cellSpursQueueInitialize`, `PopBody`, `PushBody`,
`AttachLv2EventQueue`, `DetachLv2EventQueue`, `GetTasksetAddress`, `Clear`,
`Depth`, `GetEntrySize`, `Size`, `GetDirection`. The LFQueue variants are stubbed
too (`_cellSpursLFQueueInitialize`, `cellSpursLFQueueAttachLv2EventQueue`).

The title pushes work onto a SPURS queue, gets `CELL_OK`, and nothing is queued.
The consuming task never receives work and the game waits forever. That is the
whole of the "tasks run, six SPUs busy, frames=0" signature - not a bug left to
find.

**So HLE SPURS for this title is blocked on IMPLEMENTING the queue API, not on
debugging.** That is real work: the SPURS queue is a ring buffer in shared memory
with SPU-side consumers, and it needs correct DMA and reservation semantics on
both sides. Nothing in the seven fixes is wasted - they are all prerequisites -
but none of them can produce a frame while the push is a no-op.

Do not restart HLE frame-rate attempts for BLUS30357 until the queue API exists.
Verify with one boot: if `cellSpursQueuePushBody` still logs TODO, the run cannot
render and the result is known in advance.

## Both HLE configurations are dead ends for this title. Measured, not assumed.

The queue-API blocker is PPU-side, so the obvious escape is to keep `libsre.sprx`
as LLE (real firmware queue) and arm ONLY the SPU-side HLE kernel, which is where
the time is. That was written into a bisect plan hours earlier and never run.
It has now been run, interleaved against LLE controls:

    lleA      hk=0  armed=0  fps=20.08  cores=4.540  95C
    hlekern   hk=1  armed=6  NO FRAMES
    lleB      hk=0  armed=0  fps=20.01  cores=4.600  95C

So:

    HLE libsre + HLE kernel  ->  cellSpursQueuePushBody is a stub, freeze at 0:00:09
    LLE libsre + HLE kernel  ->  arms 6 kernels, renders nothing

The second is the important one. The HLE SPU kernel arms cleanly against the REAL
firmware and the title still never presents a frame, so the HLE kernel does not
interoperate with the genuine LLE policy modules either. **There is no
configuration in which HLE SPURS produces a frame for BLUS30357.**

The LLE controls in that same round read 20.08 and 20.01, which agrees with the
shipped 19.87-19.93 and confirms the harness was measuring real gameplay.

### What would actually be required

1. Implement the SPURS queue API - eleven stubs, and `CellSpursQueue` is not even
   defined in this tree, so its ABI has to be recovered from `libsre` first.
2. Make the HLE kernel interoperate with real policy modules, or HLE those too.

Neither is a debugging task. Do not spend device time on HLE frame-rate runs for
this title until (1) exists; the outcome is predictable from one `TODO` line.

## The queue gap is UPSTREAM RPCS3, not a Thor fork regression

Checked against `rpcs3-upstream/rpcs3/Emu/Cell/Modules/cellSpurs.cpp`:

    s32 cellSpursQueuePushBody()
    {
        UNIMPLEMENTED_FUNC(cellSpurs);
        return CELL_OK;
    }

Byte-identical stubs, and `CellSpursQueue` is not defined upstream either - the
header has only `using CellSpursLFQueue = CellSyncLFQueue`. **No RPCS3 version
implements the SPURS queue API.** So this is not something to fix by syncing with
upstream or by finding the fork's mistake; the functionality has never existed.

That is the final word on HLE SPURS for BLUS30357. It is blocked on writing code
that does not exist anywhere, starting with recovering the `CellSpursQueue` ABI
from `libsre`.

### Recovering the queue ABI: libsre.sprx on device is ENCRYPTED

    /storage/emulated/0/Android/data/net.rpcsx.easy/files/config/dev_flash/sys/external/libsre.sprx
    114254 bytes, magic 53434500 = "SCE\0"

It is an SCE SELF, not an ELF - RPCS3 decrypts it in memory at load with its
built-in keys, so the on-disk copy cannot be fed to Ghidra directly. Recovering
the PPU-side queue ABI needs an unself pass first (`Utilities/unself.cpp`
upstream), and there is no built RPCS3 host binary in this workspace.

What IS already available for this: `debug-captures/spu-ls/spu_ls_CellSpursKernel0.bin`
is a decrypted 256 KB SPU local store containing the real kernel and taskset
policy module, dumped via `debug.rpcsx.thor.spu_ls_dump`. It gives the SPU side of
any structure the queue touches. The PPU side still has to come from an unself'd
libsre.

### Proof that the queue stubs are the HLE blocker, from the WORKING boot

A default boot (no `hle_libs`) shows the game loading the real firmware module
itself, at runtime:

    sys_prx: _sys_prx_load_module(path="/dev_flash/sys/external/libsre.sprx")
    sys_prx: Loaded module: "/dev_flash/sys/external/libsre.sprx" (id=0x23001100)
    ... [libsre: 0x02297c8c] sys_spu: sys_spu_thread_group_create(num=6, prio=127)

and **`cellSpursQueue` appears ZERO times in that log**. The real libsre
implements the queue, so the stubs are never reached. Forcing
`hle_libs='libsre.sprx'` substitutes RPCS3's `UNIMPLEMENTED_FUNC` versions and
the title freezes at 0:00:09. That is the blocker, confirmed from both sides.

It also means the HLE-kernel-only arm (LLE libsre, `hle_spurs_kernel=1`) had a
working queue and STILL rendered nothing - so that failure is the HLE kernel not
interoperating with the real policy modules, which is a separate problem from the
queue.

### If you add a decrypted-module dump, hook the RIGHT path

`debug.rpcsx.thor.dump_decrypted_modules` was added to the `load_libs` loop in
PPUModule.cpp, which only handles STATICALLY listed LLE libraries - the log shows
just `liblv2.sprx` there. libsre arrives through `sys_prx_load_module` at runtime,
so the hook never fires for it. Hook the dynamic path instead.

## UNLOCKED: the decrypted firmware, and every queue FNID located

The queue ABI is recoverable after all. `debug.rpcsx.thor.dump_decrypted_modules=1`
now hooks `decrypt_self` in `Crypto/unself.cpp` - EVERY decryption path funnels
through there, including the dynamic `_sys_prx_load_module` the game itself uses,
which a hook in PPUModule.cpp's static `load_libs` loop never sees.

    Thor: dumped decrypted module #4 ... (239344 bytes)   <- libsre
    Thor: dumped decrypted module #7 ... (74864 bytes)    <- libspurs_jq

`decrypted_04.elf` is **ELF 64-bit big-endian, e_machine=0x15 (PPC64)** and
contains `CellSpursKernel`, `CellSpursTaskset`, `SPURSTASK`, `SpursHdlr0`.
That is Sony's SPURS runtime, disassemblable in Ghidra with the PowerPC 64 BE
language.

FNIDs are `le_u32(sha1(name + suffix)[:4])` with the 16-byte suffix in
`ppu_generate_id` (PPUModule.cpp:90). All eleven queue exports are present in
libsre, in its FNID table at file offsets 0x1e02c-0x1e25c:

    _cellSpursQueueInitialize          0x082bfb09   @0x1e034
    cellSpursQueuePopBody              0x91066667   @0x1e188
    cellSpursQueuePushBody             0x92cff6ed   @0x1e190
    cellSpursQueueAttachLv2EventQueue  0xe5443be7   @0x1e24c
    cellSpursQueueDetachLv2EventQueue  0x039d70b7   @0x1e02c
    cellSpursQueueGetTasksetAddress    0x2093252b   @0x1e06c
    cellSpursQueueClear                0x247414d0   @0x1e074
    cellSpursQueueDepth                0x35f02287   @0x1e0a0
    cellSpursQueueGetEntrySize         0x369fe03d   @0x1e0a4
    cellSpursQueueSize                 0x54876603   @0x1e0e8
    cellSpursQueueGetDirection         0xec68442c   @0x1e25c

### Next step, concretely

1. `adb shell setprop debug.rpcsx.thor.dump_decrypted_modules 1`, boot the title,
   pull `files/cache/decrypted_04.elf`.
2. Parse the PRX export descriptor to pair the FNID table with its `faddrs`
   array - the loader logs the shape:
   `** Exported module '<name>' (fnids=0x..., faddrs=0x..., ...)`.
   `cellSpursQueueGetEntrySize`, `Depth` and `Size` are the cheapest to read and
   they reveal the structure's field offsets immediately.
3. Recover `CellSpursQueue` from those accessors, then implement Push/Pop.

**The firmware dumps are NOT committed.** They are Sony's copyrighted code; this
repo has a GitHub remote. Regenerate them with the property above - it takes one
boot. Keep them local.

## CellSpursQueue ABI, recovered from libsre with Ghidra

`decrypted_04.elf` imported as **PowerPC:BE:64:default**, disassembled at the
export addresses resolved above. The trivial accessors give the layout directly -
each is "validate, load one field, store to out-param":

    cellSpursQueueGetEntrySize      lwz r0,0x8(r11)    -> u32 @ 0x08
    cellSpursQueueDepth             lwz r0,0xc(r11)    -> u32 @ 0x0C
    cellSpursQueueGetDirection      lwz r0,0x1c(r11)   -> u32 @ 0x1C
    cellSpursQueueGetTasksetAddress ld  r0,0x60(r11)   -> u64 @ 0x60

`_cellSpursQueueInitialize` (0x164c0) then writes EVERY field through r5, which
completes the layout - an initialiser is the best possible source for a struct:

    stw r31,0x00(r5)   stw r31,0x04(r5)   ; two counters, both zeroed
    stw r7, 0x08(r5)   ; entry size   (arg)
    stw r8, 0x0C(r5)   ; depth        (arg)
    std r0, 0x10(r5)   ; buffer       (u64)
    stw r9, 0x18(r5)
    stw r10,0x1C(r5)   ; direction    (arg)
    std r11,0x60(r5)   ; taskset      (u64)
    std r3, 0x68(r5)   ; spurs        (u64)

    struct CellSpursQueue
    {
        be_t<u32> head;          // 0x00  zeroed at init, ring counter
        be_t<u32> tail;          // 0x04  zeroed at init, ring counter
        be_t<u32> entry_size;    // 0x08
        be_t<u32> depth;         // 0x0C  capacity; Size() wraps against it
        vm::bptr<void, u64> buffer; // 0x10
        be_t<u32> x18;           // 0x18
        be_t<u32> direction;     // 0x1C
        u8 unk20[0x40];          // 0x20
        vm::bptr<CellSpursTaskset, u64> taskset; // 0x60
        vm::bptr<CellSpurs, u64> spurs;          // 0x68
    };

Which counter is head and which is tail is not yet proven - `cellSpursQueueSize`
reads 0x0C and does signed wrap arithmetic over the pair, so stepping that
function settles it. Note also `lbz r0,0xe(r11)` elsewhere, a byte read inside the
0x0C word: depth is probably packed rather than a plain u32.

**Validation contract**, identical in every entry point:

    cmpwi r11,0x0                      -> if queue == nullptr, return 0x80410911
    rlwinm r0,r11,0x0,0x19,0x1f        -> r11 & 0x7F
    bne   ...                          -> if not 128-byte aligned, return 0x80410910
    cmpwi r4,0x0                       -> if out-param == nullptr, return 0x80410911

(`lis r3,-0x7fbf` + `ori r3,r3,0x91x` builds 0x8041091x.) So the HLE versions must
take `vm::ptr<CellSpursQueue>`, reject null and non-128-byte-aligned pointers with
those exact codes, and write results through an out-pointer - NOT return them.

`cellSpursQueueSize` at 0x168fc is the interesting one for semantics: it reads
depth at 0x0C and does signed wrap arithmetic over two counters
(`subf`/`add`/`nor` around 0x16940-0x16984), which is the ring-buffer
head/tail distance. Those two counter fields are the next thing to pin down.

`cellSpursQueuePushBody` at 0x169d0 is a real function - 0xC0 stack frame, saves
r28-r31, takes (r3=queue, r4=buffer, r5=?) - and calls into sync primitives. It is
the last piece, not the first; do the counters and Initialize first.

### Reproducing this

    adb shell setprop debug.rpcsx.thor.dump_decrypted_modules 1
    # boot the title once, then
    adb pull .../files/cache/decrypted_04.elf
    analyzeHeadless <proj> p -import decrypted_04.elf \
        -processor PowerPC:BE:64:default \
        -postScript DisassembleSpuWindows.java out.txt 0x60 <code_va...> -noanalysis

Export addresses come from pairing the FNID table (file 0x1e024, vaddr 0x1df24)
with the faddrs table (file 0x1e2f8, vaddr 0x1e1f8), 181 entries; each faddr
points at an OPD entry whose first word is the real code address.

## cellSpursQueuePushBody: the protocol, read off the firmware

`0x169d0`, after the shared null/alignment validation:

    lwz   r0,0x1c(r29)   ; direction
    cmpwi r0,0x2         ; MUST be 2 to push, else return 0x80410909
    addi  r9,r9,0x4      ; &queue->tail
    lwarx r11,0,r28      ; load-and-RESERVE the counter at 0x04
    sync  0x1            ; lwsync
    lwz   r0,0x0(r29)    ; head  @0x00
    lwz   r8,0xc(r29)    ; depth @0x0C
    subf/add ...         ; wrap arithmetic -> free space
    bl 0x0001309c        ; taken when the queue is FULL (blocking helper)
    bl 0x0001d8f8        ; taken after the entry is written (notify helper)

So it is a **PowerPC reservation-based lock-free ring**: `lwarx`/`stwcx.` on the
tail at 0x04, head at 0x00, capacity at 0x0C, entries of `entry_size` (0x08) in
the buffer at 0x10. That settles the open question from the layout note - the
counter at **0x04 is the one PUSH advances**, so 0x00 is head and 0x04 is tail.

This is implementable in HLE: the PPU-side function can do the same protocol with
`vm::` atomics against the same guest memory, which is what the SPU-side consumer
reserves against. Two things still need reading before writing code:

- **0x0001309c** - what it waits on when full. Determines whether the HLE version
  must block on an lv2 event queue or can spin.
- **0x0001d8f8** - the notify path. Determines what the consumer is woken by;
  getting this wrong is a silent hang, not an error.

`direction == 2` for push is worth noting on its own: the current stubs accept
anything, so a title pushing on a pop-direction queue currently gets CELL_OK where
hardware returns 0x80410909.

## The block/notify mechanism is ordinary lv2 - so the queue IS implementable

`0x1309c` (full path) and `0x1d8f8` (notify path) are import stubs - `r12 = 0x30000`,
`lwz r12,-0x1fc4(r12)`, `bctr` through a descriptor. Scanning libsre for candidate
FNIDs names what it imports and exports:

    sys_lwmutex_lock      0x1573dc3f      sys_lwmutex_unlock   0x1bc200f4
    sys_lwcond_wait       0x2a6d9d51      sys_lwcond_signal    0xef87a695
    cellSyncQueuePush     0x5ae841e5      cellSyncQueueTryPush 0x705985cd
    cellSyncMutexLock     0x1bb675c2      _cellSyncLFQueuePushBody 0xba5961ca
    _cellSyncLFQueueGetPushPointer      0xe9bf2110
    _cellSyncLFQueueCompletePushPointer 0x4e88c68d
    cellSpursSendWorkloadSignal 0x1d2bca4b   cellSpursWakeUp 0x7e4ea023

**No exotic primitive.** The blocking wait is `sys_lwmutex` + `sys_lwcond`, both
already fully implemented in this tree, and the SPU-side wake is
`cellSpursSendWorkloadSignal` / `cellSpursWakeUp`, which are also already
implemented (they are what the seven HLE fixes above were exercising). The
cellSync LFQueue helpers are present too, so the ring maths has a working
reference in `cellSync.cpp`.

That closes the specification. Implementing `cellSpursQueuePushBody` needs:

1. Signature `(vm::ptr<CellSpursQueue>, vm::cptr<void> buffer, u32 mode)` - the
   stubs take NO parameters today, which is why nothing can work.
2. Validate: null -> 0x80410911, `addr & 0x7F` -> 0x80410910,
   `direction != 2` -> 0x80410909.
3. Reserve/advance the tail at 0x04 against head at 0x00 and depth at 0x0C, copy
   `entry_size` (0x08) bytes into `buffer` (0x10).
4. Block on lwmutex/lwcond when full; wake the consumer after the write.

Everything in steps 2-4 has a working implementation elsewhere in this tree. This
is no longer research - it is a bounded port against a recovered spec.

## The SPURS queue is IMPLEMENTED, and the title moves past the freeze

`_cellSpursQueueInitialize`, `cellSpursQueuePushBody` and `cellSpursQueuePopBody`
are no longer `UNIMPLEMENTED_FUNC` stubs. They are written from the recovered
firmware layout and protocol, with the exact error codes libsre returns
(0x80410911 null, 0x80410910 align, 0x80410909 wrong direction - all three
already existed as CELL_SPURS_TASK_ERROR_NULL_POINTER / _ALIGN / _PERM, which
independently confirms the disassembly was read correctly).

MEASURED: `TODO: cellSpursQueue` count drops to **0**, Initialize is called, and
the title executes code it had never reached - `cellSpursTaskExitCodeGet` and
`_spurs::task_start`. Every previous HLE run froze at the push.

`head`/`tail` are declared `atomic_be_t<u32>` because the firmware reserves them
with `lwarx`/`stwcx.`; the compiler rejecting `compare_and_swap_test` on `be_t`
is what surfaced that.

### The wake was a guess, and guessing there is memory corruption

The first version called `cellSpursWakeUp(queue->spurs)`. That produced

    Verification failed (object: 0x0)  in _spurs::task_start

because Initialize had stored the SAME pointer in taskset (0x60) and spurs (0x68)
while the firmware writes two DIFFERENT registers (`std r11,0x60`, `std r3,0x68`)
and only r3 is the argument. `cellSpursWakeUp` WRITES through the structure it is
handed, so a taskset pointer there corrupts the taskset. Removed; `spurs` is now
left NULL rather than aliased, because a null fails loudly and a wrong pointer
corrupts silently. **Resolve the notify import at libsre 0x1d8f8 before adding a
wake back.**

### Where it now stops

Removing the wake did NOT clear the fatal - it is the GAME's own path:
`cellSpursCreateTask` -> `_spurs::task_start` -> `cellSpursWakeUp` fails because
`taskset->spurs` reads null. So the next defect is in taskset initialisation, on a
path nothing could reach before the queue existed. That is the thread to pull.

**This code only runs when cellSpurs is HLE'd.** The shipped configuration loads
the real libsre via `sys_prx_load_module`, so the shipped 19.87 fps path never
touches any of it.

## HLE SPURS RENDERS. 31 frames, no crash, no halt.

    frames=31   fatal=0   halts=0   tasksetDispatch=2   emu 0:00:10

First frames ever produced with `hle_libs='libsre.sprx'` and the HLE SPURS
kernel. The blocker was a memory corruption in the queue implementation, found by
reading the firmware's argument validation instead of reasoning by analogy.

### The signature was wrong, and it zeroed the taskset

`_cellSpursQueueInitialize` was written with the shape of
`_cellSpursLFQueueInitialize` - queue as argument 2. The firmware prologue at
libsre 0x164c0 says otherwise, because it validates each argument distinctively:

    lwz r0,0x74(r4)            ; r4->0x74 = CellSpursTaskset::wid
    ld  r3,0x60(r4)            ; r4->0x60 = CellSpursTaskset::spurs  -> r4 IS the taskset
    rlwinm r0,r5,0,0x19,0x1f   ; r5 & 0x7f -> r5 is the QUEUE (128-byte aligned)
    rlwinm r0,r6,0,0x1c,0x1f   ; r6 & 0x0f -> r6 is the buffer (16-byte aligned)
    cmplwi r7,0x4000           ; r7 = size, capped at 0x4000
    or r10,r9,r9 ... stw r10,0x1c(r5)  ; r9 = direction

PPC64 passes args in r3..r10, so the real signature is

    _cellSpursQueueInitialize(spurs, taskset, queue, buffer, size, depth, direction)

Writing 0x70 bytes through argument 2 therefore landed on the TASKSET and zeroed
`spurs` at 0x60 - exactly the null that produced
`Verification failed (object: 0x0)` in `_spurs::task_start`.

**Both of this session's queue bugs came from reasoning by analogy rather than
reading the disassembly**: the aliased spurs/taskset pointers, and this argument
order. Both were memory corruption, not clean failures. The firmware answers these
questions directly - ask it.

### Where it stops now: 31 frames, then a stall

No fatal, no halt, cores at ~6.9, frames frozen at 31. That matches the known
simplification: the ring returns `CELL_SPURS_TASK_ERROR_BUSY` when full instead of
blocking on lwmutex/lwcond, and the notify was removed. Once the queue fills, the
push fails and the title stops advancing.

`queue->spurs` now holds the REAL spurs pointer (`taskset->spurs`, per
`ld r3,0x60(r4)` then `std r3,0x68(r5)`), so re-adding the wake is no longer the
corrupting guess it was - that is the next thing to try.

### The wake does NOT fix the stall - hypothesis rejected

Re-adding `cellSpursWakeUp` with the now-correct spurs pointer changed nothing:

    without wake   frames=31   fatal=0   emu 0:00:10
    with wake      frames=27   fatal=0   emu 0:00:10

27 against 31 is noise, and both stall at the same emulated time with cores near
7.0 and no fatal. So the stall is **not** the ring filling up, and "the queue
returns BUSY instead of blocking" is NOT the current blocker. That hypothesis is
rejected rather than left hanging.

The wake is kept because it is what the firmware does (it stores `taskset->spurs`
at queue+0x68 and notifies through its import), but it buys nothing measurable
today and must not be cited as a fix.

What the numbers actually say: the title renders roughly 30 frames - the early
boot/logo output - reaches emulated 0:00:10, and then stops advancing while all
six SPUs stay busy. Emulated time freezing at the same point in every run, with no
halt and no fatal, is a wait, not a crash. The next question is what the PPU is
blocked on at 0:00:10, which `/threads` at the stall will answer.

**Do not re-run HLE frame tests without a hypothesis.** Each cycle is ~10 minutes
with the device at 85-89 C, and two consecutive changes here were guesses that
cost a round each.

## The stall, diagnosed: the render pump waits on SPURS completion

Ran the stall to completion and interrogated it instead of guessing again:

    stalled at frames=31
    {PPU[0x1000005] Thread (FlipPump)} cellSpursWakeUp(spurs=*0x1e97a80)
    ... repeated every ~265 us, indefinitely

**FlipPump - the frame-presentation thread - spins on `cellSpursWakeUp` at about
3,800 calls per second**, waiting for SPU work that never completes. At the same
moment `/diag` shows all six SPUs at `pc=0x00a00` with `spursRunning=6`: busy, not
waiting, and not finishing the job FlipPump needs.

So the remaining defect is in **work completion**, not in dispatch, selection,
the taskset, or the queue. Those all now function - the title boots through SPURS
and presents ~30 frames. Something the task should signal on completion never
reaches the PPU, and the renderer blocks forever.

Also visible and probably unrelated: `sys_fs_opendir` on
`/dev_hdd0/game/BLUS30357/USRDIR/UnrealEngine3/TransGame/PS3Cache` fails
CELL_ENOENT twice just before the spin begins.

### Instrumentation caveat, so nobody misreads the same line

The run printed `QueuePush trace: 0`. That is NOT evidence that
`cellSpursQueuePushBody` was never called - it logs at `trace` level, which is
filtered by default, while `_cellSpursQueueInitialize` logs at `warning` and did
appear. Raise the push log to `warning` before drawing any conclusion from it.

### Next step

Find what signals task completion back to the PPU. FlipPump is looping on
`cellSpursWakeUp` from `HLE:0x02003f74`, so the caller is a game routine polling
for a SPURS result. The candidates are the taskset's task-exit path
(`cellSpursTaskExitCodeGet` appears in these logs) and the event-flag machinery,
both of which are HLE'd here.

### Snapshot refresh added to the syscall handler - correct, but not the cure

`spursTasksetProcessSyscall` had the same stale-snapshot defect as
`spursTasksetStartTask` and `spursTasksetDispatch`: it reads
`spu._ptr<CellSpursTaskset>(0x2700)`, the scratch nothing fills. Its
`CELL_SPURS_TASK_SYSCALL_EXIT` case reads `taskset->x78` from that to find the
task-exit callback, which is the completion path FlipPump waits on, so it was a
well-motivated suspect.

Fixed for consistency - all three sites now refresh before reading. Measured:

    before   frames=31/27   tasksetDispatch=1..2
    after    frames=32      tasksetDispatch=3

Dispatches went up, frames did not, and the stall is unchanged at emulated
0:00:10 with 299 `cellSpursWakeUp` calls logged. **So this was not the cure**, and
it must not be described as one. The completion signal is still not reaching the
PPU.

Remaining candidates, none yet tested:

- `spursTasksetOnTaskExit` - what it actually does with the callback address, and
  whether the PPU-side handler ever runs.
- The event-flag path (`cellSpursEventFlag*`), which is how a PPU thread normally
  blocks on SPURS work rather than by spinning on `cellSpursWakeUp`.
- Whether the task ever reaches the EXIT syscall at all: put a one-shot
  `warning`-level probe in each `case` of `spursTasksetProcessSyscall` and read
  which syscalls the task actually issues. That is the cheapest next measurement
  and it needs one boot.

## THE STALL, FULLY EXPLAINED: the queue's NOTIFICATION half is the stub

One boot with the queue calls raised to `warning` (they were at `trace`, which the
default filter drops - that is what produced a misleading "QueuePush: 0" earlier):

    _cellSpursQueueInitialize(spurs=*0x0, taskset=*0x10364100, queue=*0x1030e400)
    cellSpurs TODO: cellSpursQueueAttachLv2EventQueue()     <- STILL A STUB
    PushBody:  479359 calls
    PopBody:   0
    Thor TASK SYSCALL #2 (WAIT_SIGNAL) args=0xa taskId=0
    Thor TASK SYSCALL #1 (YIELD)

The whole deadlock, end to end:

1. The task issues **WAIT_SIGNAL** - it is blocked waiting to be signalled, then
   yields.
2. **`cellSpursQueueAttachLv2EventQueue` is an unimplemented stub**, and that is
   the mechanism that delivers the signal.
3. Nothing ever wakes the consumer, so **PopBody is never called - 0 times**.
4. The ring fills, `PushBody` returns `CELL_SPURS_TASK_ERROR_BUSY`, and the title
   retries: **479,359 pushes**. That retry loop is what pins seven cores at 90 C
   while frames sit at 28-32.

So the data path works and the NOTIFY path does not. Note also that Initialize is
called with `spurs = 0` and a valid taskset, which is exactly the
"taskset OR spurs" branch at libsre 0x1654c - the implementation already handles
it by taking `taskset->spurs`.

### What remains, concretely

- Implement `cellSpursQueueAttachLv2EventQueue` (and `Detach`), which binds the
  lv2 event queue the consumer waits on.
- Signal the waiting task when a push succeeds. `_cellSpursSendSignal(taskset,
  taskId)` exists and is the obvious primitive; which task to signal must come
  from the queue structure, so resolve what lives in the unmapped bytes at 0x20..0x5F
  and at 0x18 before wiring it - **do not guess this**, two guesses tonight were
  memory corruption.
- Only then does BUSY-instead-of-blocking matter.

## cellSpursQueueAttachLv2EventQueue: the contract, from libsre 0x16778

    lwz r0,0x1c(r3)          ; direction != 0        else 0x80410909 PERM
    lwz r0,0x18(r3)          ; MUST already be -1    else 0x8041090f STAT
    ld  r0,0x68(r3)          ; spurs != 0            else 0x80410902 INVAL
    addi r4,r1,0x74 / addi r5,r1,0x70 / li r6,0x1
    ... delegates with (spurs, &out, &out, 1)

Two things fall out:

1. **Field 0x18 is the "no event queue attached" sentinel and its value is -1.**
   `_cellSpursQueueInitialize` must set it to 0xFFFFFFFF; setting it to 0 (as the
   first implementation did, now fixed) makes every attach fail with STAT before
   it does anything.
2. The attach **delegates to `cellSpursAttachLv2EventQueue`**, which this tree
   ALREADY IMPLEMENTS. So the notify half is not another from-scratch job - it is
   a wrapper: validate, call the existing function, store the resulting queue id
   in 0x18.

That makes the remaining work small and specific, and it is the last thing between
HLE and continuous frames: the consumer waits on that event queue
(TASK SYSCALL #2 WAIT_SIGNAL), and nothing signals it today, which is why
PopBody is called 0 times against 479,359 pushes.

## Implementing the notify half moved emulated time 0:00:10 -> 0:03:12

`cellSpursQueueAttachLv2EventQueue` and `Detach` are implemented - validation in
the firmware's exact order, then a delegate to `cellSpursAttachLv2EventQueue`
(already in this tree via `_spurs::attach_lv2_eq`) with `isDynamic = 1`, storing
the returned port in 0x18 and restoring the -1 sentinel on detach.

    Initialize: 1   Attach: 1   Push: 481958   Pop: 0
    emu 0:03:12     fatals: 0   frames: 27

**Emulated time advanced past the wall by a factor of about 19.** Every previous
HLE run froze at 0:00:10; the title now runs for over three minutes of emulated
time. The attach is called once and succeeds, so the PPU is no longer blocked
where it was.

What has NOT changed: `PopBody` is still 0, frames still sit at 27, and the push
retry loop still runs (481,958). So the consumer is still not being woken - the
attach binds the event queue but nothing yet SIGNALS through it on a successful
push.

### Next, and the evidence for it

The task blocks with `CELL_SPURS_TASK_SYSCALL_WAIT_SIGNAL` (census: syscall #2,
`args=0xa`). The signal side is `_cellSpursSendSignal(taskset, taskId)`, which
exists. The open question is still WHICH task to signal on a push - do not guess
it; it should come from the queue structure's unmapped bytes (0x20..0x5F) or from
`args=0xa` in that WAIT_SIGNAL census line, which looks like a task id or mask.
Read `cellSpursQueuePushBody`'s tail at libsre 0x16b60/0x16bc8 (the two `bl`
targets) to see exactly what it notifies.

## Reading PushBody's tail: one correction, and the struct is bigger than 0x70

### `bl 0x1d8f8` is MEMCPY, not a notify

Earlier notes called it the notify import. It is not. Its call site:

    lwz   r3,0x8(r29)    ; entry_size
    ld    r0,0x10(r29)   ; buffer
    mullw r3,r3,r6       ; entry_size * slot
    add   r3,r3,r0       ; dest = buffer + slot*entry_size
    rldicl r4,r30,0,0x20 ; src  = the caller's buffer argument
    rldicl r5,r3,0,0x20  ; size
    bl 0x0001d8f8        ; memcpy(dest, src, size)

That is the data copy, and it CONFIRMS the addressing in the implemented
`cellSpursQueuePushBody` - `buffer + slot * entry_size` is exactly what the
firmware computes.

### The real notify is a RAW SYSCALL, and the struct extends past 0x70

    lwz r3,0x74(r29)   ; a field at 0x74
    addi r4,r1,0x78
    li  r5,0x0
    li  r11,0x82       ; lv2 syscall number in r11
    sc  0x0
    ...
    ld  r6,0x60(r29)   ; taskset
    bl  0x0001309c

Two consequences:

1. **`CellSpursQueue` is LARGER than 0x70.** `lwz r3,0x74(r29)` reads a field
   beyond the current definition, and the `CHECK_SIZE(CellSpursQueue, 0x70)` in
   cellSpurs.h is therefore wrong. The guest allocates this memory so nothing has
   crashed, but the definition needs extending once 0x70..0x77+ are identified.
   The value at 0x74 is passed as the FIRST argument to that syscall, so it is an
   id of some kind - very likely the lv2 event queue or port id.
2. The notify is a direct `sc`, not an exported call, which is why scanning for
   FNIDs never found it.

**Do not guess the syscall number from a hand-built table.** An attempt to index
`kernel/cellos/src/lv2.cpp` recovered only 732 of ~1024 slots, so the mapping was
unreliable and is not recorded here. Read it properly, or set a breakpoint/log on
`sc` from this address range instead.

## The notify syscall, read not guessed: 0x82 = sys_event_queue_receive

The syscall table annotates every entry with its number, so this needs no
counting (an earlier attempt to index it by position recovered 732 of ~1024 slots
and was correctly discarded):

    kernel/cellos/src/lv2.cpp:345
    BIND_SYSC(sys_event_queue_receive),   // 130 (0x082)

So the full-ring path in `cellSpursQueuePushBody` is

    lwz  r3,0x74(r29)   ; lv2 event queue id
    addi r4,r1,0x78     ; &event
    li   r5,0x0         ; timeout 0 = infinite
    li   r11,0x82       ; sys_event_queue_receive
    sc   0x0

**It blocks on an event queue whose id lives at 0x74** - past where the struct
definition ended. Three defects in code written this session, all caught by the
firmware and none visible any other way:

    wrong argument order in Initialize   -> wrote 0x70 bytes over the taskset
    0x18 initialised to 0 instead of -1  -> every attach would fail STAT
    no field at 0x74 at all              -> blocking path had nothing to wait on

`CellSpursQueue` is now 0x78 with `event_queue_id` at 0x74; Attach writes both it
and the port at 0x18, Detach clears both, Initialize zeroes them.

    Init: 1  Attach: 1  Push: 536152  Pop: 0
    emu 0:03:33   fatals: 0   frames: 32

Emulated time is now 0:03:33 against 0:00:10 before any of this, and the run is
crash-free. `Pop` is still 0.

### The next thread: the LF variant is stubbed too

    cellSpurs TODO: cellSpursLFQueueAttachLv2EventQueue()

Called immediately BEFORE the CellSpursQueue attach, from a different game site.
This title uses BOTH queue types and only `CellSpursQueue` has been implemented.
`CellSpursLFQueue` is `CellSyncLFQueue`, which is already defined and has working
`cellSync` helpers (`_cellSyncLFQueueGetPushPointer`,
`_cellSyncLFQueueCompletePushPointer`), so that one is a wiring job rather than an
ABI recovery. Do it before touching anything else - the consumer may be waiting on
the LF queue, not on this one, which would explain `Pop: 0` entirely.

## The push notify, implemented - and a correction about what "Pop: 0" means

`cellSpursQueuePushBody`'s third argument is **a task id, not a blocking flag**.
libsre keeps it in r31 and the tail masks it to 8 bits to signal the consumer:

    ld     r0,0x60(r29)      ; taskset
    rldicl r31,r31,0x0,0x38  ; 3rd arg & 0xFF = task id
    or     r4,r31,r31
    bl     0x000125d8        ; _cellSpursSendSignal(taskset, taskId)
    xoris  r0,r3,0x8041 ; cmpwi r0,0x902   ; INVAL -> 0x80410914 FATAL

Implemented, including the firmware's INVAL->FATAL mapping. The title calls it
with `taskId=1`, so the signal now goes where libsre would send it.

### `Pop: 0` IS NOT THE SUCCESS SIGNAL - that reading was wrong

`cellSpursQueuePopBody` is the **PPU-side** API. The consumer for this queue is an
**SPU task**, which reads the ring straight out of memory and never calls a PPU
export. So `Pop: 0` is expected and always was; it says nothing about whether the
consumer is draining. Several rounds were scored against it as if it did.

A correct drain check needs one of:

- the ring's own counters - read `queue->head` (0x00) over time; if head advances,
  something IS consuming;
- or an SPU-side probe where the task reads the ring.

**Do that before any further queue work.** The current state may already be
correct on the data path, with the remaining stall somewhere else entirely.

### State at the end of this session

    Push: 479264   Pop: 0 (meaningless, see above)
    emu 0:03:11    fatals: 0    frames: 31    cores ~7.0

## The ring probe found the real deadlock, and it was self-inflicted

Sampling the ring's own counters (head at 0x00, tail at 0x04) is the ONLY valid
drain check - `Pop: 0` never was one, see above:

    RING #0:      head=0   tail=0    used=0
    RING #16384:  head=42  tail=298  used=256   <- FULL
    RING #32768+: head=42  tail=298  used=256   <- frozen thereafter

**head advanced 0 -> 42, so the SPU consumer DOES read the ring.** The data path
works. Then the ring filled and `cellSpursQueuePushBody` returned BUSY
immediately, the caller retried in a tight loop, and the PPU thread never yielded
- starving the very SPU task that had to drain it. ~480,000 pushes, seven cores
pinned, head frozen.

That was the "known simplification" flagged when the queue was first written and
twice dismissed as not the blocker. It was the blocker.

Fixed: the full path never busy-returns. It blocks on the event queue when one is
bound (`sys_event_queue_receive`, which is what libsre's `li r11,0x82 ; sc 0x0`
does), otherwise yields explicitly, bounded at 1024 attempts so a genuinely stuck
consumer still surfaces BUSY rather than hanging.

    pushes  481204 -> 65912   (7.3x less spinning)
    head    37 -> 52
    emu 0:03:07   fatals 0   frames 29

### Still open: eq=0x0 at push time, and it is a self-defeating guard

The probe now prints the event queue id and it reads **0**, so the blocking branch
never runs and only the yield fallback does. Two candidate causes, not yet
separated:

1. **The guard is defeated by its own function.** `_cellSpursQueueInitialize` sets
   `x18 = 0xFFFFFFFF` (the correct sentinel) and the preservation check is
   `if (event_queue_id == 0 || x18 == 0xFFFFFFFF) event_queue_id = 0;` - which is
   ALWAYS true by then. Reorder or drop that check.
2. **Attach and Push may be on different queue objects.** The title calls Attach
   at 0:00:09.449 and Initialize at 0:00:09.561 - attach BEFORE initialise, which
   is odd enough to suspect two queues. Log both addresses and compare before
   assuming (1).

Resolve which before touching it again.

## Attach takes ONE argument, and the full-ring wait must be BOUNDED

### The eq=0x0 mystery: a phantom parameter

Logging all three call sites settled it without another guess - same queue object
throughout, so the "two queues" theory was wrong:

    Initialize: queue=0x1030e400  taskset=0x10364100
    Attach:     queue=0x1030e400  eventQueueId=0x10364100   <- the TASKSET address
    Push:       queue=0x1030e400

`cellSpursQueueAttachLv2EventQueue` had been given a SECOND PARAMETER that does
not exist. RPCS3 duly passed it r4, which merely happened to hold the taskset
pointer, and that was stored as an event queue id - hence `eq=0x0` downstream.

The firmware validates ONLY r3 and derives the rest: `ld r0,0x68(r3)` for spurs,
then `(spurs, &out, &out, 1)` - two OUTPUT pointers, so it CREATES the queue and
receives id and port. That is `_spurs::create_lv2_eq(ppu, spurs, &id, &port, 1,
attr)`, already in this tree. Rewritten to one argument, and now `eq=0x8d006100`.

Also removed a guard of mine that was pure theatre: it tested `x18` for an
existing binding, but Initialize sets `x18` to the sentinel a few lines earlier,
so the condition was always true.

### timeout=0 means WAIT FOREVER

All three behaviours measured on this one path:

    return BUSY at once     481204 pushes   emu 0:03:07   spinning, 7 cores pinned
    block, timeout 0           292 pushes   emu 0:00:10   HUNG
    bounded wait, 200 us       455 pushes   emu 0:03:04   neither

A 200 us wait yields the CPU - which is what lets the SPU consumer drain - without
betting the thread on a signal that may never arrive, bounded at 4096 attempts so
a stuck consumer surfaces BUSY instead of hanging. **~1000x fewer pushes than the
original spin, and no hang.**

### State at the end of this session

    emu 0:03:04   fatals 0   frames 29   pushes 455   eq bound
    consumer confirmed reading the ring (head reached 52 in an earlier arm)

Frames still stop at ~29. The queue is no longer the bottleneck: it binds, it
does not spin, it does not hang, and the SPU side reads it. Whatever holds the
renderer is downstream of that.

**Five defects in this session's own code were caught by the firmware and by
nothing else**: wrong argument order, wrong sentinel value, a missing field, a
mislabelled parameter, and a parameter that does not exist. Every one silent.

## The renderer is no longer stalled - it is SLOW. And the wait is not the limit.

`FlipPump` now pushes render work on a steady cadence with emulated time advancing
alongside it - no deadlock, no spin, no hang:

    0:01:04.79  FlipPump  cellSpursQueuePushBody(taskId=1)
    0:01:05.90  FlipPump  cellSpursQueuePushBody(taskId=1)
    0:01:06.99  ...

That was ~1 push per emulated second, which matched the wait arithmetic exactly
(200 us x up to 4096 retries is ~0.8 s per push once the ring is full, and nothing
signals the queue so every retry burns its full timeout). So the timeout was
tested directly:

    timeout 200 us   pushes 455   emu 0:03:04   frames 29
    timeout  20 us   pushes 654   emu 0:03:04   frames 28

**Ten times shorter, identical emulated progress.** The wait was never the limit -
the SPU consumer's drain rate is. That closes the tuning avenue; do not spend
another cycle on the timeout.

### Where HLE SPURS actually stands at the end of this session

    emu 0:03:04    fatals 0    frames ~28    pushes ~650    eq bound
    queue: binds, does not spin, does not hang, consumer confirmed reading it
    (head reached 52 in a probed arm)

The queue is healthy and is NOT the bottleneck. The title runs three minutes of
emulated time and presents ~28 frames, so the remaining problem is how slowly the
SPU side consumes - a throughput question, not a correctness one, and a much
better problem than the deadlock this started as.

**Shipped frame rate remains 19.87 fps and comes entirely from config**
(XFloat Inaccurate, SPU Block Size Mega, Driver Wake-Up Delay 0). HLE has still
never been the fast path, and nothing here changes that.

## THE LAST LINK: a push only re-dispatches the workload if `waiting` is set

`_cellSpursSendSignal(taskset, taskId)` does not unconditionally wake anything:

    signal = !!(~signalled & waiting & mask);   // 1 ONLY if the task is WAITING
    ...
    case 1:
        cellSpursSendWorkloadSignal(spurs, taskset->wid);   // re-dispatch workload
        cellSpursWakeUp(spurs);

So a queue push wakes the consumer **only when that task's `waiting` bit is set in
the taskset structure in main memory**. Otherwise `signal = 0` and nothing is
dispatched. The `waiting` bit is set SPU-side by
`SPURS_TASKSET_REQUEST_WAIT_SIGNAL` in `spursTasksetProcessRequest`.

The counts line up exactly:

    cellSpursSendWorkloadSignal: 2      real workload dispatches: 2
    system-service dispatches:   8      readyCount APIs: 0 (title never calls them)

The workload is signalled twice, dispatches twice, and is then never scheduled
again - so the task that drains the ring stops running. **That is the drain-rate
limit**, and it is the last link in the chain.

### Where to look

`SPURS_TASKSET_REQUEST_WAIT_SIGNAL` in `spursTasksetProcessRequest` - does it
actually set the `waiting` bit at the address the PPU reads? That function reads
the taskset through `ctxt->taskset.addr()` (main memory, correct) but this whole
file has a history of the SPU side updating a local snapshot instead of the shared
structure - the same class of defect fixed three times already this session.

### Logging trap, hit twice - check the level before believing a zero

`_cellSpursSendSignal` logs at **trace**, which the default filter drops, so a
count of 0 for it means NOTHING. The same mistake produced a misleading
`QueuePush: 0` earlier. Before treating any zero count as evidence, confirm the
call site logs at `warning` or above.

### RULED OUT: the WAIT_SIGNAL handler sets the waiting bit correctly

    case SPURS_TASKSET_REQUEST_WAIT_SIGNAL:
        if (!(signalled0._u & ctxtTaskIdMask))
        {
            numNewlyReadyTasks--;
            running._u  &= ~ctxtTaskIdMask;
            waiting._u  |=  ctxtTaskIdMask;   // <- set correctly
            signalled0._u &= ~ctxtTaskIdMask;
            ready0._u   &= ~ctxtTaskIdMask;
        }

and those locals ARE written back to the shared structure at the end of
`spursTasksetProcessRequest` via
`vm::_ref<v128>(ctxt->taskset.addr() + OFFSET_OF(CellSpursTaskset, waiting))`.
So this is NOT another local-snapshot defect - do not re-investigate it.

Note the guard: the bit is only set when the task is NOT already signalled. If a
signal is already pending the task consumes it and does not wait, which is
correct.

So the remaining question is narrower than "is the bit set": it is **how often the
task re-enters WAIT_SIGNAL**. The syscall census logs one line per syscall number
(one-shot), so it cannot answer that. Make that probe COUNT instead - a per-number
counter printed periodically - and compare the WAIT_SIGNAL count against the
`cellSpursSendWorkloadSignal` count of 2. If the task waits many times but only
two workload signals fire, the loss is on the PPU side; if it waits twice, the
task itself is exiting its consume loop.

## THE CONSUMER DRAINS: signal the WAITING task, not the caller's argument

The queue's consumer had been stuck because every push signalled the wrong task.
Reading the taskset bitmaps at signal time settled it in one run:

    ts=0x10364100 enabled=80000000 waiting=80000000 signalled=00000000
    SIGNAL taskId=1 rc=0x80410905 (SRCH)

`enabled=80000000` is MSB-first, so **only task 0 exists** - the title creates two
tasksets (0x101b4e80 and 0x10364100) with one task each - and task 0 is the one
WAITING. Passing the caller's third argument (1) as a task id could only ever
return SRCH, set no signalled bit, and leave the consumer asleep.

So the third argument is NOT a task id, or r31 is reloaded across the ~0x280 bytes
between the prologue and the call at 0x16c80 that were never disassembled. Either
way the taskset itself carries the answer: scan the `waiting` bitmap and signal
that task. Layout is `(1u << 31) >> id`, so `countl_zero` gives the id.

RESULT, measured:

    before   rc=0x80410905  head frozen at ~41 while tail ran to 302, ring full
    after    rc=0x0         head TRACKS tail (128/129, 192/193), ring stays empty
             frames 32 -> 50, and fps read 5.00 at t+20s (every prior run: 0.00)

**This is the first HLE run to report a non-zero frame rate.**

### Ruled out in the same round

`wklCurrentContention` was the leading suspicion for blocked re-selection and it
is WRONG: the periodic gate probe reads `runnable=1 prio=1 maxCont=8 cont=0`
throughout, so contention is not stuck. The failing term is `signal=0` on wkl0 -
and since there are two tasksets, the queue's taskset may simply be a different
workload id than the one the probe prints. Check `taskset->wid` before assuming a
gate defect.

### Probe discipline, third instance

A one-shot probe cannot show a RE-entry failure. `select#1` was one-shot and had
to be made periodic to see the gate at all. Same for the syscall census
(one-shot -> counted, which is how the YIELD spin and the taskId=0/1 mismatch
became visible). Default to counting, not first-hit.

## The queue's taskset is WORKLOAD 2, and the gate probe was reading wkl0/wkl1

Several rounds of "the gate shows signal=0" were about the wrong workloads. The
PPU log names the right one:

    Thor signal wid=2: inside=0x2000 readback=0x2000 ... ready=255
    (0x2000 == 0x8000 >> 2)

333 of 334 workload signals go to **wid=2**. The `select#1` probe printed only
k=0 and k=1, so it never showed the workload that matters. Extended to k<4.

### wkl2's real gate terms: maxContention blocks it

    select#1 wkl2: runnable=1 prio=15 maxCont=1 cont=1 ready=1 signal=1

`runnable`, `ready` and `signal` all PASS. The failing term is
`maxContention > contention` with **maxCont=1 and cont=1**. Workload 2 admits
exactly one SPU and contention already reads 1, so it can never be selected
again - and with maxCont=1 there is no headroom to absorb any accounting error.

This is the same contention defect that showed as `cont=253` on wkl0, which is
still present in the STORED counter (the clamp added earlier saturates the read,
it does not stop the value accumulating). Contention is decremented only when an
SPU re-enters the selector and subtracts its own `wklLocContention`; an SPU parked
in the taskset PM yielding (measured: 5,440 YIELDs against 1 WAIT_SIGNAL) never
does that, so its contribution is never released.

**That is the next thing to fix**, and it is the last gate term still failing.

### Run-to-run variance is large - do not trust single runs

Frame counts across otherwise identical builds this round: 31, 32, 34, 50, 52,
126. Only probe code changed between some of those. Any claim about a frame-count
improvement needs at least two runs per arm; this session has repeatedly been
misled by single samples.

### Eliminated this round

- **Bit-convention mismatch between PPU and SPU task bitmaps** - `SELECT_TASK`
  prints `ready0=00000000000000008000000000000000`, whose `_u64[1]` MSB is bit 127
  of the u128, exactly what `u128{1} << (~0 & 127)` tests. The conventions agree
  and SELECT_TASK does find task 0.
- **Re-signalling the workload on every push** - implemented and measured, no
  change (head still froze). Kept because it matches firmware behaviour, but it is
  not the fix.

## The consumer IS scheduled and IS the queue's task. It polls without consuming.

    CENSUS n=5568: exit=0 yield=5568 waitSig=1 poll=0 recvFlag=0
                   (taskId=0 taskset=0x10364100 spu=0)

`0x10364100` is the taskset the queue is bound to. So the spinning task is the
QUEUE'S OWN CONSUMER, running on SPU 0, and it holds wkl2's single contention slot
legitimately - `cont=1` against `maxCont=1` is correct occupancy, not a leak.

This kills two theories at once:

- **contention leak** - no leak; the slot is held by the task that should hold it.
- **wrong taskset spinning** - it is the right taskset.

What it leaves: the consumer runs, yields 5,568 times, waits for a signal exactly
once, and never drains the ring past ~43 entries even though `tail` runs to 257+.
It polls and does not see the data.

### Note on pc=0x00a00 - it is ambiguous, do not read it as "idle"

`spursSysServiceEntry` and `spursTasksetEntry` are BOTH registered at 0xA00
(dispatch picks by image address: 0x100 -> sys service, 0x200 -> taskset PM). So
`/diag` reporting every SPU at `pc=0x00a00` does NOT mean they are idling in the
system service - SPU 0 was inside the taskset PM the whole time. An earlier
conclusion that "nobody is running workload 2, so contention=1 is stale" was
wrong for this reason.

### wkl2's gate, full distribution

    439427 x  runnable=1 prio=0  maxCont=1 cont=1 ready=1 signal=1
     89855 x  runnable=1 prio=15 maxCont=1 cont=1 ready=1 signal=1
       158 x  runnable=0 prio=0  maxCont=0 cont=0 ready=0 signal=0   (early boot)

Two separate failing conditions, and `prio=0` dominates. Priority comes from
`wklInfo1[i].priority[spuNum]`, so workload 2 has a priority on only some SPUs -
the ACTIVATE probe reads `spu=0: wkl2=0`. Whether that is correct for a
maxContention=1 workload is the next thing to establish.

### Next

The remaining question is why the guest task polls and does not see queue data
that is demonstrably present in main memory. That needs SPU-side visibility into
what the task reads - the HLE layer cannot see it, because the task is guest code.
`debug.rpcsx.thor.spu_ls_dump` plus the task's ELF is the route.

## Ring indices are MODULO DEPTH, and the starvation is intermittent

`cellSpursQueueSize` (libsre 0x168fc) computes the used count as

    if (head <= tail) used = tail - head
    else              used = tail + depth - head

    lwz r3,0xc(r29) ; cmpw cr7,r9,r0 ; subf r11,r9,r0
    ... subf r9,r3,r9 ; add r0,r0,r3 ; subf r11,r9,r0

so head and tail are INDICES MODULO DEPTH. The implementation had monotonic
counters, which made `used` meaningless to the guest consumer once tail passed
depth. Push and pop now wrap, one slot reserved so `tail == head` still means
empty.

### What the fix did, and what it did NOT do

The best run went from **0 dispatches of the queue's workload** to **45 of 46
sampled**, with frames 29 -> 68. But it does not reproduce:

    run A   frames 68   wid=2 dispatches 45
    run B   frames 36   wid=2 dispatches  6
    run C   frames 31   wid=2 dispatches  0

Same build, three runs. **So the starvation is NOT fixed - it is intermittent.**
Do not cite the 68/45 run as a result.

That spread is itself diagnostic: whether the queue's workload is ever selectable
is a race. It has `maxContention = 1`, and the contention counter has been
measured running away to 253, so a single accounting error permanently closes its
gate. Sometimes the SPU wins the race and the workload runs; usually it does not.

**The contention accounting is the remaining defect**, and it is now the only
thing between here and a consumer that drains reliably.

### Head normalisation is a REGRESSION - do not re-add it

Reducing head mod depth before the comparison looks harmless and produces the same
used count for the observed values, but measured it collapsed dispatch activity
from 46 sampled to 1 and frames from 68 to 42. Use the firmware's comparison on
the raw values.

## 30 FPS REACHED on the HLE path, and the harness left the device broken

    t+40s  fps=30.00 frames=822
    t+160s fps=30.00 frames=5322      (140 s sustained at the profile's 30 cap)

The last defect was raw `-=` on u8 counters in the workload-preemption path:

    spurs->wklCurrentContention[wklId & 0x0F] -= 0x01;
    spurs->wklIdleSpuCountOrReadyCount2[wklId & 0x0F].raw() -= 1;

Decrementing a counter already at 0 wraps to 255. The queue's taskset has
`maxContention = 1`, so `maxContention > contention` could never hold again and
its gate closed permanently. All four decrements now saturate at 0. Evidence:
max contention on that workload went 253/255 -> 1-2 in every run afterwards.

**It is NOT reliable: 30 fps in 1 boot of 3.** The other two stall, and a stalled
HLE boot presents as a BLACK SCREEN.

### The harness must clear its properties, and it did not

Killing a run mid-flight left these set on the device:

    hle_libs=libsre.sprx  hle_spurs_kernel=1  spurs_signal_fix=1 ...

so the next NORMAL launch from the UI booted straight into the experimental HLE
path and black-screened. The user hit this. `trap EXIT` does not fire on kill -
this is the same lesson recorded earlier for `setprop` leakage and it cost a user
session this time.

**Before handing the device back, always:**

    for p in hle_libs hle_spurs_kernel spurs_signal_fix spurs_sel_cond_fix \
             taskset_snapshot_fix task_ls_clear_fix taskset_syscall_fix \
             taskset_enabled_fix contention_atomic_fix spu_xfloat spu_block_size \
             driver_wakeup_delay spu_getllar_busy max_spurs_threads \
             thermal_abort_c spu_trap_stop sel_probe_nth; do
      adb shell setprop debug.rpcsx.thor.$p ''
    done
    adb shell am force-stop net.rpcsx.easy

### Do NOT put the HLE properties in the game profile

They are experimental and fail two boots in three. Only the three measured config
settings belong there: XFloat Accuracy Inaccurate, SPU Block Size Mega, Driver
Wake-Up Delay 0.

## The JIT was compiling everything for cortex-a78. Fixed, and it is worth +0.46%.

    JIT: LLVM AArch64 target: cpu=cortex-a78 attrs=+sha3,+dotprod,+i8mm,-sve,-sve2

Every SPU and PPU block was compiled for an ARMv8.2 core from 2020 while the
device runs Cortex-X3 + A715 (ARMv9). `-mcpu` selects LLVM's scheduling and
issue-width model, so vector code was scheduled for a much narrower machine.

The substitution existed only to suppress SVE, and the feature string already
passes `-sve,-sve2`, so it was suppressed twice over. `debug.rpcsx.thor.jit_cpu_native`
was added by an earlier session and never measured - the comment said so
explicitly. Measured now, interleaved, in restored 3D combat, with a separate warm
cache per arm because changing `-mcpu` changes the generated code:

    cortex-a78   20.39  20.40   mean 20.395
    native core  20.51  20.47   mean 20.490

**+0.46%, non-overlapping.** Now the default.

### The important reading is the NEGATIVE one

SPU threads are 71% of cycles, and giving LLVM the correct microarchitecture
bought 0.5%. **So SPU code is not limited by instruction scheduling or NEON
quality.** It is limited by synchronisation - the 29% of cycles in VM locking
(range_lock_internal 15.37%, writer_lock 10.69%, passive_lock 3.07%).

That closes codegen tuning as a path to 30 fps and puts everything back on the
serialised PPU->SPU->RSX chain. Do not spend more effort on -mcpu, -mattr, or
NEON intrinsic quality for this title.

## HLE reliability: measured, and it is ~1 boot in 6

    release_idle_taskset=1   1/5 then 0/6
    release_idle_taskset=0   0/6

Same build, so the idle-release change is NOT the regression - the success rate is
simply low, and the earlier "1 in 3" was a small-sample illusion. Releasing the
contention slot when a taskset has no runnable task is kept (it is correct) but it
does not move reliability.

**Do not attempt further reliability fixes by reasoning.** Every fix that worked
this session came from a measurement; both that came from reasoning alone (head
normalisation, idle release) were neutral or harmful. The next step is a
comparative one: capture the full RPCSX log from a GOOD boot and a STALLED boot
and diff them. The harness has the hook for this; the pull path needs fixing.

# BUG CLASS: Computing The New State And Committing The Old One

Found 2026-08-26 in `spursTasksetProcessRequest`, by reading rather than
measuring. **The source-level defect below is proven; whether it is THE cause
of the black screen is a separate question, measured separately.**

Every arm of the request switch mutates `signalled0` and `ready0`:

```cpp
v128 signalled0 = (signalled & (ready | pready));
v128 ready0     = (signalled | ready | pready);
...
case SPURS_TASKSET_REQUEST_WAIT_SIGNAL:
    signalled0._u &= ~ctxtTaskIdMask;      // the update
    ready0._u     &= ~ctxtTaskIdMask;
```

and the writeback committed the words it had READ:

```cpp
... OFFSET_OF(CellSpursTaskset, ready))     = ready;       // not ready0
... OFFSET_OF(CellSpursTaskset, signalled)) = signalled;   // not signalled0
```

So POLL_SIGNAL, WAIT_SIGNAL and DESTROY_TASK each computed a state transition
and threw it away. `waiting`, `running` and `enabled` were committed correctly,
which is why the taskset looked half-alive rather than dead.

## Why it is a transcription bug, not a design choice

Upstream RPCS3 has this **entire writeback commented out**
(`rpcs3/Emu/Cell/Modules/cellSpursSpu.cpp`), stale variable names and all. It
was never exercised by a running system there. Uncommenting the block on this
branch brought the wrong names along with it. Checking upstream for the
*intent* of a block is not enough when upstream never ran it.

## What it costs

`_cellSpursSendSignal` raises the workload signal only when
`~signalled & waiting & mask` is 1. If `signalled` can never be cleared it
latches on the first push, the workload stops being signalled, and the only
thing that could clear it is the task running - which needs the signal. The
measured fixed point is exactly that:

    waiting=80000000  signalled=80000000     (set, never consumed)
    gate: wkl0 signal=0, wkl1 signal=0

The "re-signal the workload on every push" workaround in `cellSpursQueuePushBody`
was built to fight this and was recorded as "no change" - it treats the symptom
from the PPU side while the SPU side keeps discarding the consumption.

DESTROY_TASK is worse than a stall: it clears `enabled` but commits the old
`ready`/`signalled`, leaving state bits set for a task that is no longer
enabled. The invariant check at the top of the same function halts the SPU on
exactly that condition, so the old writeback could turn a task exit into an
`Invalid taskset state` halt.

## The invariant still holds with the fix

Entry requires `running|ready|pready|signalled|waiting` to be a subset of
`enabled`. Both new words are subsets of old ones that already satisfied it -
`ready0 = signalled|ready|pready` and `signalled0 = signalled & (ready|pready)` -
so committing them cannot violate it, in any arm.

    debug.rpcsx.thor.taskset_writeback_fix = 0   restore the discarding writeback

# The HLE Stall, Measured: The SPU Is Captured Inside The Taskset

Measured 2026-08-26 with `taskset_writeback_fix=1` (verified live on device),
combat savestate, frame-gated harness.

    LLE control    DRAWN fps=19.47  n=6  black=0  cores=5.260
    HLE WB_ON      SAVESTATE NEVER LOADED (stalled boot), 33 frames, 6.34 cores

From the live log of the stalled run:

    dispatches: 1        select: 1        pushes: ~32,000   push-ok: ~300
    CENSUS n=3200: exit=0 yield=3200 waitSig=1 poll=0 recvFlag=0
                   (taskId=0 taskset=0x10364100 spu=0)
    RING head=42 tail=41 depth=256          (255 used, ring genuinely full)

## SELECT_TASK runs exactly once in the whole run

`spursTasksetProcessSyscall` only re-dispatches at the bottom of the function:

```cpp
if (incident)
{
    if (spursTasksetPollStatus(spu)) spursTasksetExit(spu);
    else                             spursTasksetDispatch(spu);
}
```

and the YIELD arm sets `incident` **only inside** its
`if (spursTasksetPollStatus(spu) || ..._POLL)` branch. For this taskset both are
permanently 0:

- `POLL` computes `readyButNotRunning = gv_andn(running, ready0)`. This taskset
  has ONE enabled task (`enabled=80000000`) and it is the task doing the
  polling, so the set is always empty.
- `spursTasksetPollStatus` returns 1 only when the workload selector picks a
  DIFFERENT workload, which it does not here.

So every yield is a no-op with `incident = 0`, no dispatch follows, the syscall
returns, the guest resumes and yields again - 3,200 times and counting. The SPU
never returns to the kernel, so the workload can never be re-selected. The one
dispatch that did happen came from the single `WAIT_SIGNAL` (`waitSig=1`).

**This makes the stall structural, not a race.** Whatever else is wrong, once
the guest task enters a yield loop the SPU is captured and nothing can recover
it.

## What this retracts

The starvation was previously attributed to a lost or unconsumed signal. The
signal path is now instrumented and works: pushes reach `_cellSpursSendSignal`
with the right task, and `taskset_writeback_fix` makes consumption commit. It
does not help, because the code that would consume runs once.

`taskset_writeback_fix` is still correct and is KEPT - `POLL_SIGNAL`,
`WAIT_SIGNAL` and `DESTROY_TASK` were all discarding their updates, and
DESTROY_TASK could leave state bits set for a disabled task, which the
invariant check halts on. It is simply not the thing that unblocks rendering.

## Still open, and why they are not the next thing

- **Non-atomic taskset read-modify-write.** The `vm::reservation_op` wrapper
  around the whole block is commented out (in upstream too), so the SPU's
  read/modify/write of the bitmaps races the PPU's atomic `_cellSpursSendSignal`.
  Only `signalled` has two writers, so the fix is narrow: clear exactly
  `signalled & ~signalled0` instead of storing the word. Worth doing, but it
  cannot explain a path that executes once.
- **0x2700 aliasing.** `spu._ptr<SpursTasksetContext>(0x2700)` and
  `spu._ptr<CellSpursTaskset>(0x2700)` are the SAME local store address read as
  two different structs. The bitmaps said `running=00000000 waiting=80000000`
  while the census showed that same task executing thousands of yields, so the
  taskset's recorded state and what is actually running disagree.

## Measurement note

`pushes` and `push-ok` in the counts above are LOG LINES, each printed every 64
calls - multiply by 64 for call counts. The ring probe's `used` was a raw
`tail - head` and printed 4294967295 once tail wrapped; it now uses the
firmware's wrapped formula (`spurs_ring_used`). That number was never
corruption, only a bad subtraction in a print.

# HLE SPURS, Measured 2026-08-26: Two Blockers Down, One Left

All arms: combat savestate, frame-gated harness, AYN Thor, `taskset_writeback_fix=1`.

## What the two fixes actually did

| signal | baseline | +yield_redispatch | +queue_monotonic |
|---|---|---|---|
| dispatches / select | 1 / 1 | 403 / 403 | 278 / 278 |
| ring `head` | frozen at 42 | advancing to 257 | advancing to 89 |
| `used=42949...` underflow lines | present | present | **0** |
| push calls | ~32k | ~8.3M (flood) | **~37k** |
| `used` at a full ring | 4294967295 | 4294967295 | **256, exact** |
| producer blocks when full | never | never | **yes** (`tail` holds) |

Both are mechanical wins and both are deterministic - unlike frame count, which
on this branch has measured 31, 32, 34, 44, 50, 52, 126 and 208 across builds
that differed only in probe code. **Do not A/B this work on frame count.** Use
the ring and dispatch counters; they do not lie and they do not vary.

## The remaining stall is consumer-side, and is NOT the queue

With the ring proven correct and backpressure working, the consumer still
stops:

    head=89  tail=345  depth=256  used=256      (full, producer correctly blocked)
    CENSUS n=4032: exit=0 yield=4032 waitSig=1 poll=0 recvFlag=0

256 entries are sitting in the ring and the task will not take them. It is
yield-spinning, having called WAIT_SIGNAL exactly once. So it is waiting on
something that is **not** queue data - the queue is full, visible, and correctly
accounted.

The freeze point moves with the build (42, then 89), which is what a race or a
missing completion looks like, not a fixed arithmetic bound.

### Where to look next, in order

1. **`spursDmaWaitForCompletion` is commented out** in several places on this
   path (`// spursDmaWaitForCompletion(spu, 1 << ctxt->dmaTagId);`), including
   both halves of the task context save/restore. If the guest issues a DMA and
   waits on its tag group, nothing completes it and the task spins exactly like
   this.
2. **The non-atomic taskset read-modify-write.** The `vm::reservation_op`
   wrapper is commented out, so the SPU's read/modify/write races the PPU's
   atomic `_cellSpursSendSignal`. Only `signalled` has two writers, so the fix
   is narrow: clear `signalled & ~signalled0` rather than storing the word.
3. **0x2700 aliasing** - `SpursTasksetContext` and `CellSpursTaskset` are read
   from the same local store address.

## Cost to watch

`yield_redispatch_fix` forces a full context save per yield: 0x380 bytes plus up
to 122 2KB LS blocks, ~244KB each way, at thousands of yields per second. The
arm measured fps=1.40. If frames ever flow, throttle re-dispatch to every Nth
yield before reading anything into the frame rate.

# HLE SPURS: The Queue Is Fixed. The Title Still Does Not Draw.

Measured 2026-08-26, build with taskset_writeback + yield_redispatch +
queue_monotonic (2*depth) + signal_atomic, all confirmed live on device.

## The queue path now works, end to end

    QUEUE RING #7360: head=192 tail=192 depth=256 used=0
    QUEUE RING #7424: head=256 tail=256 depth=256 used=0

`head == tail`, `used = 0`, held across ~475,000 push calls. The consumer keeps
perfect pace. Compare the start of this work: `head` frozen at 42 with the
producer jammed on a full ring.

    frames      33 (hard stall)  ->  2,945+ and climbing
    fps         0.00             ->  ~29.5 sustained
    dispatches  1                ->  hundreds, continuous

## Two of my own inferences, corrected

**"The consumer task is never started."** WRONG, and it was an artifact of a
sampled probe. The dispatch probe printed every 16th call, so a distribution of
"724 isWaiting=1 against 1 isWaiting=0" said nothing about the FIRST dispatch.
Logging every start unconditionally settles it:

    Thor TASK START #0 (dispatch #0): taskId=0 taskset=0x101b4e80
    Thor TASK START #1 (dispatch #1): taskId=0 taskset=0x10364100

Both tasks start. **A sampled probe cannot answer a question about a first
occurrence** - log the occurrence itself, not every Nth of it.

**The frame checker had a false negative.** It required a low colour count AND a
high near-black fraction, so a flat GREEN frame passed as DRAWN: 29 fps over
2,945 frames, `distinct=148`, `near_black=0.0%`. The clear colour is not always
black, so darkness was the wrong axis. It now reports BLANK for any flat frame
and keeps BLACK only as a label for which kind of blank it is. Re-validated
against six captures.

## What is actually left

The title renders a flat clear at ~29 fps with `RSX 5.8%` and the consumer task
yielding 273,152 times. The SPURS plumbing is healthy; the task is spinning
rather than producing draw work, and `/loadstate` never succeeds, so the run
never leaves early boot.

So the remaining problem is NOT the queue, NOT the taskset scheduler, and NOT
the signal path - all three are now instrumented and behaving. It is whatever
the started task is waiting on inside its own code.

**Cost to account for first.** `yield_redispatch_fix` forces a full context
save/restore per yield - 0x380 bytes plus up to 122 2KB LS blocks, ~244KB each
way - and the task yields 273,152 times. That is on the order of 130 GB of
memcpy. Before reading anything into "the task spins", throttle re-dispatch to
every Nth yield and re-measure: the spin may be an artifact of making every
yield enormously expensive.

## Throttling the yield re-dispatch: measured WORSE, hypothesis closed

`yield_redispatch_fix` now takes a count - 0 off, 1 every yield, N every Nth -
so the ~244KB-each-way context save could be amortised. Measured:

    N = 1    2,945 frames at ~29.5 fps (one lucky boot), flat green, RSX 5.8%
    N = 64   28 frames, BLACK, stalled

So the expensive every-yield re-dispatch is doing real work, and the task's
273,152 yields are NOT an artifact of making each one costly. **That hypothesis
is closed.** Keep N=1.

## And the good run does not reproduce

The 2,945-frame run was a lucky boot, not a result: a repeat at the same N=1
settings stalled at 32 frames. This path still boots successfully about 1 in 6
times, and even the successful boot drew nothing. Two arms is not enough to
call anything here - see the run-to-run variance section - and a single good
run is exactly the trap this file already warns about twice.

# The Consumer Says EMPTY. Read From Its Own Disassembly.

2026-08-26. Ghidra headless, SPU:BE:128:default, on a local-store dump taken
from the SPU running the queue's taskset (`thor_ls_10364100.bin`).

## The wait loop, exactly

    0000f3a0  lr    r4,r86
    0000f3b4  brsl  lr,0x00013c68     ; SPU-side queue pop, result in r3
    0000f3b8  lr    r80,r3
    0000f3bc  brz   r3,0x0000f238     ; success -> leave the wait
    0000f3c0  brsl  lr,0x0000a4a0     ; cellSpursYield  (our syscall 1)
    0000f3d0  ai    r4,r4,0x1         ;+ backoff, 0x960 = 2400 iterations
    0000f3d4  rdch  r3,ch8            ;| read SPU_RdDec, result DISCARDED
    0000f3dc  brz   r40,0x0000f3d0    ;+
    0000f3e8  ceq   r41,r80,r82
    0000f3f4  brnz  r41,0x0000f3a0    ; loop WHILE result == r82

and r82 is built in the prologue:

    0000f208  ilhu r82,-0x7fbf
    0000f22c  iohl r82,0x901          ; r82 = 0x80410901

**0x80410901 is CELL_SPURS_TASK_ERROR_AGAIN.** The task spins for as long as
the pop keeps returning AGAIN.

## AGAIN means EMPTY, and that is provable from the registers

    ceqi r66,r86,0x0    ; arg4 == 0            -> r66 = -1
    sfi  r8,r66,0x0     ; r8  = 1
    ceqi r64,r68,0x0    ; r68 = used           -> r64 = -1 iff used == 0
    sfi  r60,r64,0x0    ; r60 = 1 iff used == 0
    and  r52,r8,r60
    brnz r52,0x00014118 ; -> return 0x80410901

## The consumer's own used() confirms the 2*depth ring

    sf   r80,r11,r2         ; tail - head
    a    r3,r2,r59          ; tail + depth
    sf   r78,r8,r3          ; tail - head + 2*depth
    selb r68,r78,r80,r79    ; used = head<=tail ? tail-head : tail-head+2*depth

Independent confirmation of `queue_monotonic_fix`, from the guest itself.

## And it reads the queue with GETLLAR

    wrch r49,ch16  ; MFC_LSA  = 0x80
    wrch r50,ch18  ; MFC_EAL  = queue
    wrch r49,ch19  ; MFC_Size = 0x80
    wrch r47,ch21  ; MFC_Cmd  = 0xd0     GETLLAR
    rdch r2,ch27   ; MFC_RdAtomicStat

head (0x00) and tail (0x04) are in one reservation granule, which is why the
producer now claims its slot through `vm::reservation_op` on the same line
(`queue_reserve_fix`) instead of a bare CAS. That change is measured and real:
push calls collapsed from ~475,000 to ~700 because a full ring no longer writes
the line at all. It did not, on its own, unstick the consumer.

## THE OPEN CONTRADICTION - state it plainly

Our side reports `head=40 tail=296 depth=256 used=256`. The consumer computes
`used == 0` from its GETLLAR of the same structure. Both cannot be true of the
same 128 bytes, and only ONE CellSpursQueue exists (0x1030e400, all 690 pushes
go to it). So one of these is false and none has been checked:

1. The EA in the consumer's GETLLAR is not 0x1030e400. Its queue pointer comes
   from `lqr r39,-0x6465` - a pointer sitting in task local store - not from
   anything this code hands it.
2. The GETLLAR is not returning the bytes we wrote.
3. head/tail are not at the offsets assumed on one of the two sides.

**The next experiment is to log the EA of the consumer's GETLLAR and compare it
with the queue address we push to.** That is one measurement and it eliminates
two of the three. Do not patch anything else until it is taken - the last three
changes were made against symptoms and none of them moved this.

## Also unimplemented, and never accounted for

    ·U _cellSpursLFQueueInitialize(pQueue=*0x101b1f80, size=0x20, depth=0x10, direction=3)
    ·U cellSpursLFQueueAttachLv2EventQueue()

A SECOND queue, lock-free, direction 3, both stubbed. It has been dismissed
before on the grounds that this title never calls the LF push/pop, but the
INITIALIZE and ATTACH are called, and nothing has checked whether the renderer
waits on that one.

# RESOLVED: The SPURS Queue Works. The AGAIN Loop Was Never A Bug.

Measured 2026-08-26, sustained run of 3 minutes 29 seconds, ~954,000 push calls.

## Retract the "contradiction"

The previous section recorded that the producer reported the ring FULL
(`used=256`) while the consumer computed `used == 0`, and called it a
contradiction that had to be resolved. **It was not a contradiction. It was two
readings from two DIFFERENT boots**, compared as if they were one.

Two measurements settle it, both taken in the same run:

    consumer's GETLLAR (logged EA):  addr=0x1030e400  lsa=0x80  size=0x80
    the queue we push to:            queue=*0x1030e400

so the consumer reserves OUR queue, and the local-store dump taken at the same
moment shows it read our structure at our offsets:

    LS 0x80: head=164 tail=164 entry_size=16 depth=256
             buffer=0x1030e480 direction=2

`entry_size`, `depth`, `buffer` and `direction` all match `Initialize` exactly.
head == tail because the consumer HAD DRAINED THE QUEUE.

## The ring is healthy, and the numbers are unambiguous

Distribution of `used` across 234 samples spanning ~954,000 push calls:

    used=0   147 samples
    used=1    68
    used=2    16
    used=4     1
    used=6     1
    used=256   1        (a single transient)

The consumer keeps pace with the producer. `head` tracks `tail` continuously
(64/64, 127/128, 191/192, 63/64) for the whole run.

**So `CELL_SPURS_TASK_ERROR_AGAIN` in the poll loop is CORRECT BEHAVIOUR.** A
consumer that finds its queue empty returns AGAIN, yields, backs off 2400
cycles and retries. That is what a working SPURS consumer does. Days were spent
treating normal empty-queue polling as the stall.

## What the SPURS work actually achieved

    dispatches / select     1 / 1        ->  continuous
    ring head               frozen at 42 ->  tracks tail for 3.5 minutes
    frames                  33 (stall)   ->  3,741 and climbing
    fps                     0.00         ->  29-30 sustained
    push calls              475,000 flood ->  paced, ring near-empty

## What is still wrong, stated precisely

The title renders a FLAT GREEN FRAME at 29.89 fps with `RSX : 06.3 %` and
`SPU : 69.0 %`. Frames are presented, SPURS is healthy, and no geometry reaches
the GPU.

That is NOT a SPURS queue problem and must stop being chased as one. The queue
is instrumented, measured and behaving. The next question is why the title
submits no draws, and the candidates are elsewhere:

- `_cellSpursLFQueueInitialize` and `cellSpursLFQueueAttachLv2EventQueue` are
  both UNIMPLEMENTED (`·U`), on a second queue at 0x101b1f80, depth 0x10,
  direction 3. A different SPU was measured reserving exactly that address
  (`GETLLAR EA #0: addr=0x101b1f80`), so something IS polling it.
- The green is a clear colour with nothing drawn over it.

## Probe artifact to fix

`max head=4294967232` (0xFFFFFFC0) appears once in the probe output. The ring
arithmetic is sound in the samples either side of it, so this is a torn read in
the PROBE - it loads head and tail non-atomically - not a real ring state. Do
not chase it; make the probe read both under one reservation if it matters.

# Two Leads Killed By Measurement, Not By Implementation

2026-08-26, after the SPURS queue was confirmed working.

## The LF queue is not on the data path

It was the leading suspect - `_cellSpursLFQueueInitialize` and
`cellSpursLFQueueAttachLv2EventQueue` are both `UNIMPLEMENTED_FUNC`, and an SPU
was measured reserving the LF queue's address (`GETLLAR EA #0: addr=0x101b1f80`).

Counted over the whole 3m29s run:

    _cellSpursLFQueuePushBody   1
    _cellSpursLFQueuePopBody    0
    LFQueueAttach               1
    LFQueueInitialize           2

**One push, zero pops.** It is set up and then essentially unused. Implementing
it would have been a day spent on a queue that carries no traffic.

## cellOvis is not the problem either

The HLE path calls `cellOvisGetOverlayTableSize` 22 times and the LLE path -
same title, same scene, verified DRAWN at 30 fps - calls it ZERO times. Our stub
returns 0 ("no overlay table needed") and `cellOvisFixSpuSegments` does nothing,
so the worry was that HLE loads incomplete SPU task code.

Probed the actual images instead of assuming:

    Thor OVIS #1: phnum=3  PT_LOAD[0] vaddr=0x03000 filesz=0x1eca0
                           PT_LOAD[1] vaddr=0x21d00 filesz=0x1d0
                  PT_LOAD=2 shared-vaddr=0

All four sampled ELFs: two PT_LOAD segments at DISTINCT virtual addresses,
`shared-vaddr=0`. **These SPU images carry no overlays**, so returning 0 is
correct and the empty FixSpuSegments is harmless. The 22-vs-0 call difference is
a consequence of the two paths reaching different code, not a cause of anything.

Note in passing: the task ELFs load at vaddr 0x3000 - `CELL_SPURS_TASK_TOP` -
and the largest reaches ~0x21ed0, comfortably inside the 0x3d000 bound that
`task_ls_clear_fix` uses. That fix is consistent with these images.

## What that leaves

Still: HLE presents a flat green frame at 29.89 fps, `RSX 6.3%`, `SPU 69.0%`,
frames flowing, SPURS queue healthy. LLE on the same scene is DRAWN, 41,042
distinct colours, 30 fps.

Both cheap leads are gone. The next one that is worth a build is a DIFFERENTIAL
against the LLE control, because that path demonstrably works: the LLE run
reaches code that calls cellVoice 17 times and HLE never does, which says the
two runs diverge somewhere earlier than the renderer. Find the divergence point
in the PPU call stream before touching the RSX side.

# The Title Never Finishes Loading Under HLE. It Is Not A Render Bug.

2026-08-26. Differential against the LLE control, which renders the same scene
DRAWN at 30 fps with 41,042 distinct colours.

## Module-call profile, same title, same point

                     LLE (renders)   HLE (flat green)
    sys_memory            767              79
    sys_fs                551             347
    cellAudio              64               0
    sys_spu                40              23

The HLE run does a TENTH the allocation and never reaches cellAudio at all. The
green frame is a LOADING screen, not a broken renderer.

## Where it stops

All non-SPURS activity ends at t=17.17s (last calls are RSX iomap), and
`main_thread`'s final log line is at **t=12.01s**. For the next three minutes
the only threads logging anything are the SPU kernels and RenderingThread.

`main_thread`'s last SPURS sequence, which repeats and then stops:

    cellSpursQueuePushBody(queue=*0x1030e400, buffer=*0xd00402f0, taskId=1)
    cellSpursWakeUp(spurs=*0x1e97a80)
    cellSpursSendWorkloadSignal(spurs=*0x1e97a80, wid=2)
    cellSpursWakeUp(spurs=*0x1e97a80)      <- last line ever

## It is SPINNING, not deadlocked - and that killed a wrong fix

`cellSpursWakeUp` has exactly one blocking path,
`_spurs::signal_to_handler_thread`, which does
`sys_lwmutex_lock(spurs->mutex, 0)` - timeout 0, wait forever. That looked
conclusive, and it is WRONG.

Per-thread CPU over 10 s (100 jiffies = one full core):

    rsx::thread        974      ~97% of a core
    SPU[0..5]          ~900 each
    PPU[0x1000000]     161      main_thread - RUNNING, not blocked
    PPU[0x1000005]     173      FlipPump

**main_thread is executing guest code at ~16% of a core.** It is busy-waiting
inside the title's own code, which is why it emits no further HLE calls. A
deadlock fix would have been aimed at a deadlock that does not exist.

The lwcond handshake is in fact sound: `sys_lwcond_wait` releases the mutex
while waiting, so the handler thread does not hold it.

## What this reframes

Everything is spinning - RSX at 97%, six SPUs at ~90%, main_thread and FlipPump
alive - and all of them are waiting on something none of them will receive. The
SPURS queue is measured healthy and is NOT the thing to look at again.

The question is now: **what is main_thread busy-waiting on at ~t=12s?** Its last
known PC is `[0x009dc0dc]` (game code, from the log's own bracket annotation).
Sampling `main_thread`'s PPU `cia` while it spins and disassembling that address
against the PPU ELF (PowerPC:BE:64) names the loop and what it polls. That is
one probe and one Ghidra pass, and it is the next thing to do - not another fix.

DO NOT patch anything from the list already eliminated: the SPURS queue, the LF
queue, cellOvis, the taskset writeback, the yield capture, the ring convention,
and the handler-thread mutex are all measured and accounted for.

# ROOT CAUSE: The Job Chain Policy Module Does Not Exist

Found 2026-08-26. This is why HLE SPURS does not render, and it means most of
the SPURS work in this branch, while correct, was aimed at the wrong half of
SPURS.

## The chain of evidence

`main_thread` parks at 0x00fdcf60, which disassembles to a spin comparing two
words and sleeping 30 us between attempts. Printing them:

    Thor FENCE: base=0x01fb4980 done=0x304f8348 target=0x304f93e8

Both are POINTERS, not counters - 0x10A0 apart, frozen at those exact values for
the whole run. Something must advance `done` toward `target` and nothing does.

The title calls `cellSpursCreateJobChainWithAttribute` **three times**. UE3 on
PS3 drives rendering through SPURS JOB CHAINS, not tasksets.

And the job chain policy module is this:

```cpp
bool spursJobChainEntry(spu_thread& spu)
{
    // TODO
    return false;
}
```

**It is worse than a stub: it has no call site at all.** The taskset module is
wired into the SPU kernel explicitly -

    spu.RegisterHleFunction(CELL_SPURS_TASKSET_PM_ENTRY_ADDR, spursTasksetEntry);

- and there is NO equivalent registration for the job chain module. A selected
job chain workload dispatches to an unregistered local store address.

## What this explains, all at once

- Six SPUs at ~90% and RSX at ~97%, with no draws: the kernel keeps selecting
  job chain workloads that do nothing.
- `main_thread`, `AsyncIOSystem` and `RenderingThread` all parked on the same
  fence: they wait on job chain output that is never produced.
- The title never finishing load - a tenth the sys_memory calls, cellAudio never
  reached.
- Why the SPURS QUEUE being measurably healthy changed nothing: the queue feeds
  the taskset, and rendering does not go through the taskset.

## Honest accounting of this branch

The six defects fixed here are real and stay fixed - the discarded taskset
writeback, the yield capture, the 2*depth ring, the GETLLAR reservation, the
uninitialised queue header, the underflowing probe. The taskset path went from
`dispatches: 1` and a frozen ring to a consumer that keeps pace across ~954,000
pushes.

None of it could ever have produced a rendered frame, because the rendering
work never travels that path. That was knowable earlier: the title creates
three job chains at t=11.4s, in the same log that was read a dozen times for
queue state.

## Scale, stated plainly

Implementing the job chain policy module is comparable in size to the taskset
policy module - job descriptor DMA, the urgent command queue (the one piece
that DOES exist here, `spursJobchainPopUrgentCommand`), job code loading, and
the kernel-side registration. It is the other half of SPURS, not a patch.

**Do not resume by editing the taskset path.** The next work is
`spursJobChainEntry` and its registration, or the honest conclusion that HLE
SPURS for this title is a project of that size.

## Correction, and the proof

An earlier note here said the job chain module "has no call site, so a selected
job chain dispatches to an unregistered address". The mechanism was wrong in a
way worth recording, because the real one is worse.

The kernel's workload dispatch is:

```cpp
switch (wklInfo->addr.addr())
{
case SPURS_IMG_ADDR_SYS_SRV_WORKLOAD: RegisterHleFunction(0xA00, spursSysServiceEntry); break;
case SPURS_IMG_ADDR_TASKSET_PM:       RegisterHleFunction(0xA00, spursTasksetEntry);    break;
default: std::memcpy(spu._ptr<void>(0xA00), wklInfo->addr.get_ptr(), wklInfo->size);    break;
}
...
spu.pc = 0xA00;
```

and `_spurs::create_job_chain` passed **`vm::null` with size 0** as the workload
image. So a job chain took the `default` arm, did `memcpy(LS 0xA00, nullptr, 0)`
- copying NOTHING - and then ran whatever the PREVIOUS policy module had left at
0xA00. Not garbage in the abstract: the taskset module's code, executed as if it
were a job chain.

Upstream avoids this only because it never registers the SPU-side HLE entries at
all (both RegisterHleFunction calls are commented out there) and always runs real
guest policy-module binaries. This branch enabled SPU-side HLE, so job chains
needed the same sentinel treatment tasksets got.

Fixed: `SPURS_IMG_ADDR_JOBCHAIN_PM = 0x300`, passed by `create_job_chain`,
dispatched to `spursJobChainEntry`, which now EXITS the workload back to the
kernel and says so instead of `return false` (which left the SPU running on
stale local store).

**Measured, and this is the proof the diagnosis is right:**

    Thor JOBCHAIN #0: policy module UNIMPLEMENTED - exiting workload
                      (jobChain=0x0 arg=0x1eca280)

The job chain workload is selected, reaches the SPU, and finds nothing to run.
That is now an observation rather than an inference.

# HLE SPURS For This Title: The Two Remaining Paths, And Their Real Cost

2026-08-26, after the job chain root cause was proven by dispatch.

## Why "just use the real policy module" does not work

The kernel dispatch's `default` arm runs REAL guest policy-module binaries, so
the obvious move is to point job chains at the genuine image instead of writing
one. Measured, that is impossible as things stand:

    HLE:  sys_prx: Ignored module: "/dev_flash/sys/external/libsre.sprx"
    LLE:  sys_prx: Loaded module:  "/dev_flash/sys/external/libsre.sprx"

`debug.rpcsx.thor.hle_libs` routes through `should_load_hle`, and returning true
means the PRX is **never mapped**. The job chain policy module lives inside
libsre.sprx, so under HLE that binary is not in memory at all.

## The two paths, sized honestly

1. **Write the job chain policy module.** Job descriptor fetch, honouring
   `sizeJobDescriptor` and `maxGrabbedJob`, jobbin2 code and data DMA, the
   `linkRegister` walk, `urgentCmds` service, `isHalted` and the job guard.
   `SpursJobChainContext` in the header is still `// TODO` - the structure is not
   even mapped out. This is the size of the taskset policy module, which is what
   this entire session amounted to.

2. **Load libsre but HLE its exports**, then find the embedded PM image and pass
   its address. That means reworking PRX loading and export resolution -
   `should_load_hle` is a binary load/don't-load decision today - and then
   locating the image inside the PRX.

Neither is a patch.

## The part that should decide whether to spend that

**There is no measurement anywhere in this file showing HLE SPURS is faster than
LLE for this title.** The "HLE deletes the guest SPU loop" argument was recorded
as a mechanism, and the retraction above states plainly that every number once
offered as evidence for it was a blank frame. So the honest position is:

    LLE, frame-verified, in combat        19.47 fps  (6/6 frames DRAWN)
    HLE, if the job chain module existed  UNKNOWN - never measured on a drawn frame

Spending a taskset-sized effort to reach an unmeasured payoff is a decision that
belongs to whoever is paying for the time, and it should be made with that
sentence in front of them.

## Where the measured evidence actually points for 30 fps

From the profiling already in this file, on the path that DOES render:

- ~29% of cycles in VM locking (`range_lock_internal` 15.37%,
  `writer_lock` 10.69%, `passive_lock` 3.07%)
- ~55% of cycles in JIT-compiled guest SPU code
- 73% total CPU with 2.6 cores idle - a dependency chain, not saturation

Those are measured on drawn frames, on the path the user can actually play. The
SPU recompiler and the VM lock are where a 19.47 -> 30 fps attempt has evidence
behind it.

# Starting The Job Chain Module: What Is In Hand, And The One Blocker Left

2026-08-26. Work toward implementing the job chain policy module.

## libsre is decrypted and its SPU images are extracted

`debug.rpcsx.thor.dump_decrypted_modules` had already produced decrypted ELFs in
`files/cache/decrypted_NN.elf` on a previous boot (it does NOT re-fire, because
RPCSX caches decrypted modules - a fresh dump needs the cache cleared first).

    decrypted_04.elf   239,344 bytes   4 embedded SPU ELF headers, markers: spurs SPURS JobChain
                                       -> this is libsre.sprx decrypted
    decrypted_00.elf   30 MB           45 embedded SPU images -> the game EBOOT

Of libsre's four ELF-header hits, two are real SPU images and two are false
positives in data:

    spu_pm_1.bin  2048 bytes  entry=0x818  PT_LOAD vaddr=0x100 size=0x780
    spu_pm_2.bin  2064 bytes  entry=0x848  PT_LOAD vaddr=0x100 size=0x790

Both load at **vaddr 0x100**, which is the SPURS KERNEL entry area - these are
kernel1 and kernel2, not policy modules. Kept as
`_research/spurs/spurs_kernel{1,2}.spu.bin`.

**The policy modules are NOT standalone ELFs in libsre.** They load at 0xA00 and
are considerably larger than 2 KB, so they are stored some other way - raw
blobs, or relocated at load. Finding them in the PRX is unfinished.

## The direct route to the job chain module, and why it did not fire

The real module is resident in SPU local store at 0xA00 during an LLE run, and
this tree already has `thor::spu_ls_dump_tick()` for exactly that:

    setprop debug.rpcsx.thor.spu_ls_dump <substring of SPU thread name>
    -> /data/data/net.rpcsx.easy/cache/spu_ls_<name>.bin

Tried with `CellSpursKernel1` on an LLE boot and no file was produced. The gate
is `#ifdef ANDROID` (which IS defined in this build - the cellSpursSpu.cpp gates
use the same spelling and respond to props), so the likely cause is the NAME
FILTER: SPU thread names under LLE were never checked, and the census only ever
printed `SPU[0x1000100]`-style ids, not names.

**Next step is one cheap check, not a build:** list the SPU thread names under
LLE, then re-run the dump with a substring that actually matches, and read what
sits at 0xA00. A capture taken while a job chain workload is loaded IS the job
chain policy module, and it can be disassembled the same way the taskset module
was (Ghidra, SPU:BE:128:default).

## Reminder of what this is for

Two paths remain and both are large; this is progress on path 1. Nothing here
changes the standing measurement: LLE renders at 19.47 fps frame-verified, and
HLE's speed benefit for this title has never been measured on a drawn frame.

# The Job Chain Policy Module Is Captured. Identified, 9,168 Bytes.

2026-08-26. The source material for porting it now exists.

## How it was captured

`thor::spu_ls_dump_tick()` works and the earlier "it did not fire" was MY error:
the doc comment in `thor_spu_ls_dump.h` says the file lands in
`/data/data/net.rpcsx.easy/cache/`, but `fs::get_cache_dir()` on this build
resolves to **`files/cache/`** - the same directory the decrypted modules go to.
The file was there the whole time. Fix the comment before it costs someone else
an hour.

    setprop debug.rpcsx.thor.spu_ls_dump CellSpursKernel1     # LLE boot
    -> /storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/spu_ls_CellSpursKernel1.bin

The thread name is the SAME under LLE and HLE (`CellSpursKernel0..5`), which was
also worth knowing - it was checked against the LLE log rather than assumed.

## What is in it

A policy module occupies LS **0xA00 .. ~0x2dcc**, about 9 KB of real guest code,
in an LLE boot where the title renders. Extracted to
`_research/spurs/jobchain_pm.spu.bin` (9,168 bytes).

## Why it is the JOB CHAIN module and not the taskset one

Two independent checks against the taskset module's documented signatures:

    word at 0xa70 = 0x04002803  (lr r3,r80)
      - the taskset PM's 0xA70 is its syscall entry and begins `stqa lr,0x2c80`
    'ila r39,0x3d000' - the taskset PM's LS-clear bound, disassembled earlier in
      this file at 0x18b8 - encodes to 0x41e80027 and appears NOWHERE in the
      module region.

Its entry does what a policy module should: sets up the stack at 0x3ffd0,
branches on an argument byte, and immediately performs a GETLLAR
(`il r16,0xd0` -> `wrch r16,ch21`) over a structure at r80, which is the job
chain the workload argument points at.

## What porting it needs, in order

1. Disassemble `jobchain_pm.spu.bin` at load address 0xA00
   (Ghidra, SPU:BE:128:default) - the same route that cracked the taskset module.
2. Map `SpursJobChainContext` properly. It is `// TODO` in the header today, and
   the module's own accesses off r80 and 0x4a00 will name the fields.
3. Implement `spursJobChainEntry` against it: descriptor fetch honouring
   `sizeJobDescriptor` and `maxGrabbedJob`, jobbin2 code and data DMA, the
   `linkRegister` walk, `urgentCmds` (the existing
   `spursJobchainPopUrgentCommand` already models this), `isHalted`, job guard.

The dispatch wiring is already in place from the previous commit
(`SPURS_IMG_ADDR_JOBCHAIN_PM`), so an implementation has somewhere to land and
is measurable the moment it does anything - the `Thor JOBCHAIN #n` line fires
whenever the workload is selected.

# Staging The REAL Job Chain Module Instead Of Porting It

2026-08-26. This works, and it changes the shape of the remaining problem.

## The idea

The SPU kernel's workload dispatch already runs real policy modules - its
`default` arm is `memcpy(LS 0xA00, wklInfo->addr, wklInfo->size)`. So the job
chain module never had to be reimplemented; it had to be FOUND and STAGED.

## The measurements that make it possible

From an LLE boot where the title renders, local store holds the module at
0xA00..0x2C00 - exactly **0x2200 bytes** - and those bytes appear **verbatim** in
decrypted libsre at offset 0x21580. No relocation is applied at load, so a
straight copy is correct. A 32-byte signature from its entry is unique in the
file, so it is searched for rather than trusting a fixed offset across firmware
versions.

(The earlier extraction said 9,168 bytes; that over-read into zeroed local store
past the module. The real size is 0x2200.)

## What was implemented

`thor_jobchain_pm_image()` in cellSpurs.cpp: open
`/dev_flash/sys/external/libsre.sprx` through the VFS, `decrypt_self` it, search
for the signature, `vm::alloc` 0x2200 bytes and copy the module in. Cached, so it
happens once. `_spurs::create_job_chain` then passes that address and size as the
workload image instead of `vm::null`, falling back to the sentinel (clean exit,
loud) when the module cannot be found.

**It works:**

    Thor JOBCHAIN: staged the real policy module at 0x2330000
                   (8704 bytes, found in libsre at 0x21580)

and the SPU threads are then observed executing AT the module entry:

    SPU[0x3000100] Thread (CellSpursKernel3) [0x00a00]

with **no SPU halts, no faults, no access violations** in the whole run. The
genuine module loads and runs under the HLE kernel.

## What is still wrong

The title still does not advance - 19 frames, black. So the module runs but does
not do useful work, and the most likely reason is the one this approach implies:

**a real policy module expects the SPURS KERNEL CONTEXT at local store 0x100 to
be bit-compatible with what the REAL kernel maintains**, and ours is an HLE
kernel that keeps `SpursKernelContext` to its own satisfaction. Any field the
real module reads that the HLE kernel does not maintain identically - or lays
out differently - makes it read nonsense without ever faulting, which is exactly
the symptom.

That is now the whole remaining question, and it is far narrower than porting a
module with 15 subroutines and 41 DMA sites. The way to answer it is a
differential on local store 0x100..0x200 between an LLE boot and an HLE boot at
the moment a job chain workload is dispatched - both captures are already
possible with `debug.rpcsx.thor.spu_ls_dump`.

## The kernel-context diff, and what it does NOT show

Both local stores are kept as
`_research/spurs/ls_{lle,hle}_CellSpursKernel1.bin` so this is re-checkable.

`SpursKernelContext` at LS 0x100..0x200, LLE against HLE:

    0x100..0x17F   differs     -> tempArea[0x80]. SCRATCH. Meaningless, and I
                                  first misread a "one byte shift" here.
    0x180, 0x190   identical   -> wklLocContention, wklLocPendingContention
    0x1A0          differs     -> priority[0x10], HLE[i] == LLE[i+1]
    0x1B0          identical
    0x1C0          identical   -> spurs pointer 0x1e97a80, spuNum, dmaTagId
    0x1D0          differs     -> wklCurrentAddr: LLE 0x022b1480 (a real module),
                                  HLE 0x00000100 (the SYS_SRV sentinel). Different
                                  workload current at dump time, not a defect.
    0x1E0          differs     -> only wklRunnable1, 0xfc00 vs 0xf800. Which
                                  workloads are runnable right now.

**exitToKernelAddr (0x808) and selectWorkloadAddr (0x290) MATCH EXACTLY.** The
kernel-entry contract the real policy module depends on is correct, which is
consistent with the module running without faulting.

The `priority[]` difference is NOT an off-by-one in the fill loop
(`ctxt->priority[i] = 0x10 - wklInfo1[i].priority[spuNum]`). The array is indexed
by WORKLOAD, so a shift means the workloads occupy different slots in the two
runs - a creation-order difference, not corruption. Both runs do request the
system workload (`cellSpursAttributeEnableSystemWorkload` is called once under
HLE) and both have a `SpursHdlr0`.

So this diff did not find the defect. What it did do is rule out the kernel
contract and the contention arrays, which is worth having written down before
someone re-runs it.

# The Job Chain Module Gets The RIGHT Argument And Bails Anyway

2026-08-26. Reports and diagrams for this project go in the repo, not to a cloud
artifact - see `_research/spurs/spurs-dispatch.html` for the dispatch graph.

## The workload argument is correct

    Thor WKLOAD #16: wid=6 addr=0x2330000 size=0x2200 arg=0x1eca280
                     kind=REAL-IMAGE spu=3

and the title created its job chains at:

    jobChain=*0x1e76500   jobChain=*0x1e97880   jobChain=*0x1eca280

`arg` matches the third one exactly. The kernel passes `wklInfo->arg` to the
module in r4, so the module receives a valid `CellSpursJobChain` pointer. For
contrast the taskset workloads carry `arg=0x101b4e80`, their taskset - the same
mechanism, and it is right in both cases.

**"The module gets a null or wrong job chain" is eliminated.**

## Where it exits

    Thor JCEXIT #0: module image 0x2330000 wid=6 exits from lr=0x00808
                    sp=0x3ffb0 r3=0x00000100 r4=0x00000000 r5=0x00000002

`lr = 0x808` is `exitToKernelAddr` itself - the value the KERNEL puts in r0
before jumping to 0xA00 - so this says the module tail-returned without ever
calling anything, and it does NOT locate the branch. r4 = 0 at exit is likewise
worthless as evidence: the module clobbers r4 before leaving. Do not read either
as the input state.

Its entry, from the disassembly, takes the expected path:

    00a1c  ai   r6,r3,0xdc     ; r3 = 0x100, so r6 = 0x1DC = ctxt->wklCurrentId
    00a30  lqd  r9,0x0(r6)
    00a38  ceqi r2,r8,0x20     ; is this the system workload (32)?
    00a3c  brz  r2,0x00000a4c  ; ours is wid=6 -> non-system path, correct

## Eliminated so far, on the job chain specifically

- the module is missing              -> staged from libsre, loads verbatim
- the module is not dispatched       -> `kind=REAL-IMAGE` on two SPUs
- the kernel contract differs        -> exitToKernel 0x808, selectWorkload 0x290 identical
- the workload argument is wrong     -> arg = 0x1eca280, the real job chain
- it faults or halts                 -> no halt, no fault, no access violation

## What is left

The module has the right code, the right kernel contract and the right job chain
pointer, and still decides there is nothing to do. That points at the CONTENTS
of the job chain it DMAs in - `pc`, `sizeJobDescriptor`, `maxGrabbedJob`,
`isHalted` - i.e. at the PPU side that fills `CellSpursJobChain`, not at the SPU
side.

**Next probe: dump the 0x80 bytes at 0x1eca280 when the workload is dispatched,
and compare against the same structure in an LLE boot.** If `pc` is null or
`isHalted` is set, the defect is in `_spurs::create_job_chain` or in the
Run/Kick path - and note that `cellSpursRunJobChain` and `cellSpursKickJobChain`
log at TRACE level, so their absence from any log so far proves nothing.

# Two Dropped Field Assignments In _spurs::create_job_chain

2026-08-26. Found by auditing the function against its own signature, and
confirmed in the structure the policy module actually reads.

## The audit

    parameters:  ppu spurs jobChain jobChainEntry sizeJob maxGrabbedJob prio
                 maxContention autoReadyCount tag1 tag2 HaltOnError name ...

    fields written: spurs jmVer val2F tag1 tag2 isHalted maxGrabbedJob pc
                    cause error workloadId

`sizeJob` and `autoReadyCount` arrive as parameters and were never stored.
Measured, decoding `CellSpursJobChain` at the moment the workload is dispatched:

    before:  sizeJobDescriptor=0    autoReadyCount=0
    after:   sizeJobDescriptor=128  autoReadyCount=1

`sizeJobDescriptor` is the STRIDE of a job descriptor. At zero the module cannot
fetch a single job - the DMA it would issue has zero length - so it returns to
the kernel immediately having done nothing. That is precisely the observed
behaviour, and it is worth keeping in mind as a lesson: the module was doing
exactly the right thing with the data it was given.

## Everything else in that structure is now valid

    jc=0x1eca280 pc=0x01eca480 isHalted=0 maxGrabbedJob=16
    sizeJobDescriptor=128 autoReadyCount=1 workloadId=6 spurs=0x01e97a80

pc points at the descriptor list, the workload id and spurs pointer are right,
nothing is halted.

## And it STILL exits immediately

Job chain loads = 1, exits = 1, screen black. So these two were real defects and
were not the last one. Remaining zeros in the structure, in the order worth
checking:

    initSpuCount = 0     - set by cellSpursCreateJobChainWithAttribute from
                           attr->initSpuCount, so the attribute may be the source
    val2C        = 0x00  - packed isFixedMemAlloc<<7 | ((maxSizeJobDescriptor-0x100)/128 & 7)<<4
    lr0          = 0     - linkRegister[0]
    urgent0      = 0     - urgentCmds[0]

`val2C = 0` implies `maxSizeJobDescriptor = 0x100` and `isFixedMemAlloc = 0`,
which is worth verifying against what the title actually passed, since the same
class of bug (an attribute field never reaching the structure) would look
exactly like this.

# The Job Chain Structure Is Now Fully Correct. It Still Bails.

2026-08-26, final state of this session's job chain work.

## The title's own attribute values, logged at last

`_cellSpursJobChainAttributeInitialize` and the Run/Kick entries log at TRACE,
which is why they read as "never called" for most of this session. Raised to
error, they say:

    chain 1: sizeJobDescriptor=0x100 maxSizeJobDescriptor=0x100 isFixedMemAlloc=false initialRequestSpuCount=0
    chain 2: sizeJobDescriptor=0x100 maxSizeJobDescriptor=0x100 isFixedMemAlloc=false initialRequestSpuCount=0
    chain 3: sizeJobDescriptor=0x80  maxSizeJobDescriptor=0x100 isFixedMemAlloc=false initialRequestSpuCount=0

    jmRevsion=0x3 sdkRevision=0x300000 maxGrabbedJob=0x10 maxContention=6
    autoRequestSpuCount=true tag1=0x0 tag2=0x1

    cellSpursRunJobChain(jobChain=*0x1eca280)     <- called once, on chain 3
    cellSpursKickJobChain                          <- never called

## Which reconciles everything and clears two false suspects

    structure at dispatch:  jc=0x1eca280 sizeJobDescriptor=128 = 0x80  <- MATCHES chain 3
    initSpuCount = 0     <- CORRECT: the title passes initialRequestSpuCount=0
    val2C        = 0x00  <- CORRECT: isFixedMemAlloc=false and
                            (maxSizeJobDescriptor - 0x100)/128 = 0

Both were listed as suspicious zeros. Both are the title's own values. Do not
"fix" them.

So `CellSpursJobChain` is now fully valid at the moment the module reads it:
`pc=0x01eca480`, `sizeJobDescriptor=128`, `autoReadyCount=1`, `maxGrabbedJob=16`,
`isHalted=0`, `workloadId=6`, `spurs=0x01e97a80`.

## And the module still exits at once

Loads = 1, exits = 1, screen black.

## The circular dependency worth naming

`cellSpursRunJobChain` signals the workload and wakes SPURS - it does NOT set a
ready count. `cellSpursKickJobChain`, which takes `numReadyCount`, is never
called, because the title passes `autoRequestSpuCount=true`: with auto request,
the POLICY MODULE is what raises its own ready count as it grabs jobs. The
module cannot do that because it exits first, and it exits for a reason that is
not any field checked so far.

That is the shape of the remaining problem. It cannot be resolved by another
field audit - every field the structure carries has now been verified against
the value the title passed. It needs the module's own execution traced from
0xA00 until the branch that leaves, under HLE, against the same trace under LLE.

# The Module Calls The Kernel's Services With BISL. We Treat One As Termination.

2026-08-26. Static trace of the real job chain module, Ghidra SPU:BE:128, from
its entry at 0xA00 down the path a non-system workload takes.

## The path for wid != 32

    00a1c  ai   r6,r3,0xdc      ; r3 = 0x100 -> r6 = 0x1DC = wklCurrentId
    00a38  ceqi r2,r8,0x20      ; is it the system workload?
    00a3c  brz  r2,0x00000a4c   ; ours is wid=6 -> take 0xa4c
    00a4c  brsl lr,0x000021a8
    00a50  brsl lr,0x00002850

## And 0x2850 is where it goes

    02850  lqa  r2,0x1e0        ; quadword at LS 0x1E0
    02860  bisl lr,r2           ; CALL the address in the preferred slot
    02868  lqa  r4,0x1e0
    02884  rotqbyi r2,r4,0x4    ; the second word, LS 0x1E4
    02888  bisl lr,r2           ; CALL that too

In `SpursKernelContext`, 0x1E0 is **exitToKernelAddr** and 0x1E4 is
**selectWorkloadAddr**. `bisl` is branch-indirect-AND-SET-LINK: the module is
CALLING these as kernel services and expects them to RETURN.

Our HLE registers `spursKernelWorkloadExit` at exitToKernelAddr and treats the
SPU arriving there as "this workload is done" - it switches the SPU to another
workload and never returns to the caller.

**That is a complete explanation of the observed behaviour**: the module is
entered, walks a few instructions, calls what it believes is a kernel service,
and from our side that call IS the workload ending. No fault, no halt, exits
immediately, loads=1 exits=1. It also explains why every field audit came back
clean - nothing is wrong with the data, the control-flow contract is wrong.

## What this predicts, and how to check it cheaply

If true, the JCEXIT probe should show the exit arriving from inside 0x2850
rather than from the module's top level. It reported `lr=0x00808`, which is the
value the KERNEL put in r0 - consistent, but not proof, because `bisl` writes
the return address into lr and our handler reads r0 after that write.

The check: log `spu.gpr[0]` at entry to `spursKernelWorkloadExit` AND compare it
against 0x808. A `bisl` from 0x2860 leaves lr = 0x2864, not 0x808. If lr is
0x2864 the module is calling a service and this is confirmed outright.

## If confirmed

`spursKernelWorkloadExit` cannot be a single "workload over" handler. The real
kernel exposes routines at these addresses that a policy module calls and
returns from; only some paths terminate the workload. Getting that contract
right is what the remaining work is - and it is a control-flow question about
the HLE kernel, not another missing field.

# A Stale HLE Stub Was Shadowing Every Real Policy Module

2026-08-26. Found by reading register state instead of trusting a hypothesis.

## Retract the bisl theory

The previous section argued the module CALLS exitToKernelAddr with `bisl` as a
kernel service and that our handler wrongly treats that as termination. **That
is wrong**, and the data to disprove it was already in hand.

The kernel enters a module with a known register state:

    spu.gpr[0] = ctxt->exitToKernelAddr    // 0x808
    spu.gpr[1] = 0x3FFB0                   // sp
    spu.gpr[3] = 0x100
    spu.gpr[5] = pollStatus

and the job chain module was observed leaving with

    lr=0x00808  sp=0x3ffb0  r3=0x00000100  r5=0x00000002

**Every register still at its entry value**, sp included - and the module's own
prologue sets `ila sp,0x3ffd0` at 0xa20. It never executed a single instruction
of its own. A `bisl` from 0x2860 would have left lr=0x2864 and sp lower still.

## What was actually happening

The workload dispatch installs an HLE function AT local store 0xA00 for the two
sentinel images:

    case SPURS_IMG_ADDR_SYS_SRV_WORKLOAD: RegisterHleFunction(0xA00, spursSysServiceEntry);
    case SPURS_IMG_ADDR_TASKSET_PM:       RegisterHleFunction(0xA00, spursTasksetEntry);
    default:                              memcpy(LS 0xA00, wklInfo->addr, wklInfo->size);

A registration made for ONE workload is still live when a DIFFERENT workload is
loaded. So the real module was copied into local store and then never run: the
SPU reached 0xA00, found the previous workload's stub registered there, and
executed that instead.

Upstream never hits this because it registers no SPU-side HLE entries at all -
both RegisterHleFunction calls are commented out there and every workload goes
through `default` with a real image. Enabling the SPU-side HLE on this branch
made unregistering mandatory, and the calls that would do it were sitting
commented out in `spursTasksetInit` and `spursKernelEntry`:

    // spu.UnregisterHleFunctions(CELL_SPURS_TASKSET_PM_ENTRY_ADDR, 0x40000);
    // spu.UnregisterHleFunctions(0, 0x40000);

## The fix and its measured effect

`spu.UnregisterHleFunction(0xA00)` before the memcpy in `default`.

    job chain workload loads      1  ->  6
    exits through our handler     1  ->  0

The module is no longer bounced back to the kernel on entry; it runs. Screen is
still black at 28 frames, so this is not the last defect - but it is the first
time the genuine policy module has actually executed under HLE.

# The Module Asserts On A Consumed Signal In The Entry Poll Status

2026-08-26, immediately after the UnregisterHleFunction fix let the real module
run for the first time.

## What it did once it could run

    ·F {SPU[0x3000100] CellSpursKernel3 [0x02228]}
       Thread terminated due to fatal error: Unknown STOP code: 0x3fff

0x2228 is a `stopd` in the module's own entry checks:

    021fc  brz  r2,0x00002204   ; wklCurrentId == 32 -> assert (we pass, wid=6)
    02204  ai   r10,r84,0xcc    ; r10 = 0x1CC = dmaTagId
    02218  brsl lr,0x000028d0   ; write a trace packet
    0221c  lqd  r3,0x20(sp)     ; the word holding the pollStatus ARGUMENT
    02220  andi r11,r3,0x2      ; CELL_SPURS_MODULE_POLL_STATUS_SIGNAL
    02224  brz  r11,0x0000222c  ; clear -> carry on
    02228  stopd                ; SET -> assert

Note 0x28d0 is NOT a status helper - it is `cellSpursModulePutTrace`. It
early-returns through `biz r75,lr` when tracing is off, otherwise reads
`traceBuffer` at LS 0x210 and DMAs a packet. Its return value is never tested;
`r3` at 0x221c is reloaded FROM THE STACK, where the pollStatus argument was
stashed at 0x21f8. Reading that call as the source of the tested value is a
mistake worth not repeating.

## Why our kernel set the bit

The selection loop consumes the workload's signal on the way to picking it -
`wklSignal1 &= ~(0x8000 >> wid)` - and then still reported
`CELL_SPURS_MODULE_POLL_STATUS_SIGNAL` in the entry poll status. That describes
a condition which no longer exists by the time the module reads it.

`cellSpursRunJobChain` signals the workload, so EVERY job chain start hit this.
Measured entry state was `r5 = 0x00000002` - exactly this bit and nothing else.

## Fix and effect

Mask SIGNAL out of the poll status passed at workload entry
(`entry_pollstatus_fix`, ON by default, `= 0` restores the raw value).

    before:  SPU dies at 0x2228, "Unknown STOP code: 0x3fff"
    after:   no STOP code, no fatal error anywhere in the run

The module clears its entry checks and keeps running. Screen is still black at
22 frames, so this is not the last defect either - but the SPU no longer dies,
which it did on every job chain dispatch before this.

## Where the module goes now, and what it needs from us

With the assertion cleared it takes the no-ready-count branch:

    0222c  andi r14,r3,0x1      ; POLL_STATUS_READYCOUNT
    02238  brhnz r12,0x000025a0 ; bit clear -> 0x25a0

    025a0  ai   r3,sp,0x20
    025a4  brsl lr,0x00002868   ; -> 0x2868 loads LS 0x1E0, takes the SECOND word
                                ;    (0x1E4 = selectWorkloadAddr) and `bisl`s it
    025a8  brz  r3,0x0000221c   ; result 0 -> loop back and re-poll
    025f8  wrch r84,ch22        ; SPU_WrEventMask = 1 << dmaTagId
    025fc  wrch r83,ch23        ; SPU_WrEventAck
    02600  rdch r2,ch24         ; SPU_RdEventStat - BLOCKS until an event
    0262c  bi lr

That is correct SPURS idle behaviour, not a defect: no ready count, so poll,
and if still nothing, arm the MFC tag-group event and sleep.

**But it makes `selectWorkloadAddr` a CALLABLE SUBROUTINE.** The module `bisl`s
it and reads a result out of r3. We register
`spursKernel1SelectWorkload`/`spursKernel2SelectWorkload` there, and whether
those behave as subroutines that return a value to a GUEST caller - rather than
as kernel-internal entry points - has never been checked. It is the same shape
as the bug that was just fixed at 0xA00: an HLE function standing where guest
code expects a specific contract.

Note this also shows `cellSpursModulePollStatus` is exactly what 0x2868 is: set
r3 = 1, call the select-workload routine, return its status. Our HLE has that
function already; the guest reaches the same behaviour through the LS address.

## Ready count is the other half

`cellSpursRunJobChain` signals and wakes but sets NO ready count, and
`cellSpursKickJobChain` is never called because the title passes
`autoRequestSpuCount=true`. So the module is entered with READYCOUNT clear every
time and always takes the idle path. Whether the real kernel raises a ready
count on RunJobChain for an auto-request chain is the next thing to establish -
if it does, that is likely the remaining gap.

# Seeding The Ready Count Puts The Module On Its WORK Path

2026-08-26.

## The circular dependency, and the seed that breaks it

The module branches at entry on POLL_STATUS_READYCOUNT and idles when it is
clear. Nothing ever raised a job chain's ready count: `cellSpursRunJobChain`
signals and wakes but sets none, and `cellSpursKickJobChain` - the API that takes
a numReadyCount - is never called, because this title passes
`autoRequestSpuCount = true`, under which the MODULE grows its own ready count
as it grabs jobs. It cannot, while it is idling.

Matching upstream proves nothing here: upstream's HLE cellSpurs is a partial port
with the whole SPU side disabled, so its `cellSpursRunJobChain` has never had to
make a real module run. Ours matched it exactly and was still wrong for this.

`thor_jobchain_readycount` (default 1) stores a ready count on the workload
before the signal in `cellSpursRunJobChain`.

## Measured effect: the failure MOVED

    before:  SPU dies at 0x02228  - the entry assertion on poll status
    after:   SPU dies at 0x02af4  - SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE

Different address, different failure, much further in. The module left the idle
path at 0x25a0 and went down the work path.

# The Next Blocker: sys_spu_thread_switch_system_module Does Not Exist

The module reaches 0x2af4 and issues an SPU stop with code
`SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE`. In this tree that is:

```cpp
case SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE:
    fmt::throw_exception("SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE (op=0x%x, Out_MBox=%s)", ...);
```

An unconditional throw, which is what kills the SPU. The only other reference in
the tree is a name formatter in `kernel/cellos/src/sys_spu.cpp` mapping the code
to the string `sys_spu_thread_switch_system_module`. There is no implementation
anywhere, and upstream RPCS3 has none either.

This is a real lv2 service: an SPU asks the system to switch the module loaded
in its local store, passing parameters through the out mailbox. SPURS job chains
use it, which is why nothing in the emulator has ever needed it - HLE SPURS has
never got this far before.

**Next step is to implement it**, and the out-mailbox contents at the stop are
the specification: log them (the throw already formats `ch_out_mbox`) and decode
what the module is asking for before writing anything.

# Implemented sys_spu_thread_switch_system_module

2026-08-26. It did not exist here or in upstream RPCS3 - the case in
`spu_thread::stop_and_signal` was an unconditional `fmt::throw_exception`, and
the only other reference in the tree is a name formatter. Nothing had ever
needed it, because no SPURS policy module had run far enough to ask. The real
job chain module reaches it as soon as its ready count is seeded.

## The contract, read off the module's own code

    02adc  wrch r9,ch22    ; SPU_WrEventMask = -1
    02ae4  wrch r3,ch23    ; SPU_WrEventAck = 2
    02aec  rdch r2,ch24    ; SPU_RdEventStat
    02af0  wrch r6,ch28    ; the REQUEST
    02af4  stop 0x120      ; SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE
    02af8  rdch r4,ch29    ; expects a REPLY
    02afc  ceq  r10,r4,r5  ; r5 = 0x8001000A = CELL_EBUSY
    02b00  brnz r10,0x2af0 ; reply == EBUSY -> RETRY the whole sequence
    02b04  br   0x2aa8     ; anything else  -> carry on

So a reply is MANDATORY, and it must not be EBUSY or the guest spins on that
retry branch forever.

## What we do

Under HLE SPURS the emulator already owns policy-module loading - the kernel's
workload dispatch copies the image into local store itself - so there is no
switch left for lv2 to perform. Acknowledge with CELL_OK and let the module
continue.

    Thor SWITCH_SYSTEM_MODULE #0: request=0x00000000 -> CELL_OK
    Thor SWITCH_SYSTEM_MODULE #1: request=0x00000000 -> CELL_OK

and no STOP code or fatal error anywhere in the run - the SPU used to die here
on every job chain that got this far.

**Caveat worth recording:** `request` reads 0 because the value is taken from
`ch_out_mbox`, and the module writes channel 28. If the request payload ever
matters, that is the first thing to correct - the reply is what unblocks the
guest, and the reply is right.

## Running total on the job chain path

    module never executed        -> executes            (unregister stale HLE stub at 0xA00)
    died at entry assertion      -> passes entry checks (mask consumed SIGNAL from poll status)
    idled forever                -> runs its work path  (seed the ready count on RunJobChain)
    died on an unimplemented stop-> continues           (implement switch_system_module)

Still black. Each of these was a real defect and each moved the failure; none of
them was the last one.

# The Descriptors Are Real And The Chain Still Does Not Advance

2026-08-26.

## pc never moves

Across four dispatches, on four different SPUs, in one run:

    jc=0x1eca280  pc=0x01eca480  isHalted=0  autoReadyCount=1   (identical x4)

The workload is selected repeatedly, the module runs, no job is consumed.

## And there ARE jobs

    Thor JOBDESC @0x1eca480: 00000000 01eca10f  00000000 01eca086
                             00000000 00000002  00000000 01eca400
    Thor JOBDESC +0x20:      00000000 01eca483  00000000 00000000 ...

64-bit entries with plausible addresses in the title's own data. The descriptor
list is intact, so "the chain is empty" is eliminated.

## The suspicion this raises about the switch_system_module reply

The module issues SYS_SPU_THREAD_STOP_SWITCH_SYSTEM_MODULE twice per run and we
answer CELL_OK without doing anything. That was justified on the grounds that
HLE SPURS owns policy-module loading - but if the module uses that service to
have JOB CODE loaded, answering "done" while loading nothing means it proceeds
against a local store that does not contain what it asked for.

Two facts make this worth checking before anything else:

- `request` reads 0 in our handler because it is taken from `ch_out_mbox`, and
  the module writes CHANNEL 28. We are replying without ever seeing what was
  asked. Fix the channel first - the request payload is the specification.
- The count is small and fixed (2), which fits "asked twice, got a useless
  answer, gave up" better than it fits a working service.

**Next step: read the actual request payload from the correct channel.** Until
that is known, any further change to the job path is guesswork.

## The switch request really is 0 - suspicion cleared

The previous section suspected we were replying to `switch_system_module`
without ever reading the request, because `request` came back 0 and the handler
used `get_count() ? pop() : 0` rather than the `try_read` idiom every other stop
handler uses. Corrected to `try_read`:

    Thor SWITCH_SYSTEM_MODULE #0: request=0x00000000 (present=1)
                                  in_mbox_count=0 pc=0x02af4 -> CELL_OK

**present=1** - the mailbox did hold a value and the request genuinely IS zero.
The reply is not being made blind, and CELL_OK is a reasonable answer to it.
That suspicion is eliminated, not acted on.

(The read idiom is still worth having fixed: `try_read` is what the rest of the
file uses and it now reports whether a value was actually present.)

The chain still does not advance - `pc=0x01eca480` unchanged.
