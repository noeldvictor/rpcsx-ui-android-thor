# RPCSX for AYN Thor Experiment Agent Notes

## Repo And Git

- Work directly on `master` only for this repo. Do not create or switch to feature branches for this fork.
- Remote push target is SSH: `git@github.com:noeldvictor/rpcsx-ui-android-thor.git`.
- Commit completed work to `master` and push only `origin master`.
- Commit and push frequently during Thor core work. Make a checkpoint after each buildable native/APK slice, after each on-device install/smoke pass, and before starting risky upstream ports such as SPU reduced-loop or reservation-notifier rewrites.
- Do not fork extra RPCSX repos for this project; keep Android-side and native/core experiment work in this repo unless the user asks otherwise.
- Public positioning: this is a personal-use, AI-assisted/vibe-coded AYN Thor experiment. Do not present it as official RPCSX, official AYN, stable, or support-backed.

## Vendored RPCSX Core Source

- The RPCSX core source is checked into this repo as plain files at `app/src/main/cpp/rpcsx`.
- It is not a Git submodule. Edit the vendored core files directly for Thor experiments.
- The custom Thor core is in this repo as source, not only on the device and not only in a downloaded APK. Core changes under `app/src/main/cpp/rpcsx` are real repo changes; the debug APK packages them into `lib/arm64-v8a/librpcsx-android.so`.
- The upstream core's third-party source dependencies are pinned as root repo submodules under `app/src/main/cpp/rpcsx/3rdparty` and `app/src/main/cpp/rpcsx/rpcs3/3rdparty`.
- These dependency submodules use upstream SSH URLs and exact SHAs from the vendored RPCSX commit. They are source pins, not extra forks in this GitHub account.
- Initial vendored upstream commit: `e27926d6296e2ce4bd5b0775cb4e4423d9e7cdb6` from `git@github.com:RPCSX/rpcsx.git`.
- The vendored tree has its own `UPSTREAM.md` with the upstream commit and sync notes.
- Refresh the core source with `tools/sync_rpcsx_core.ps1` from the Android repo root; keep local Thor experiment changes in this repo.
- Hydrate core dependencies with `tools/hydrate_rpcsx_core_deps.ps1`. On Windows, keep `git config core.longpaths true` because SPIRV-Cross and LLVM contain long test/reference paths.
- Do not commit generated native build output, downloaded prebuilt tarballs, APKs, `.cxx`, Gradle caches, or runtime PPU/SPU/shader caches.
- The default Gradle app build uses `app/src/main/cpp/CMakeLists.txt` for the Android JNI wrapper and now bundles the vendored full core by default. The full core Android build entry is `app/src/main/cpp/rpcsx/android/CMakeLists.txt`.
- Java loads the wrapper as `librpcsx-ui-jni.so`. A source-built/bundled core should package as `librpcsx-android.so`, and `MainActivity` will use it when no custom/downloaded core path is configured.
- In this fork, `MainActivity` treats a valid bundled `librpcsx-android.so` as authoritative and rewrites `rpcsx_library` to the APK native-lib path on startup. This keeps stale saved `/data/app/...` paths or old updater cores from hiding local source-core changes or triggering install prompts on Thor.
- Build source-core packaging with the normal `.\gradlew.bat :app:assembleDebug` after dependency hydration. For fast UI-only iteration, opt out with `-PbuildBundledRpcsxCore=false` or `RPCSX_BUILD_BUNDLED_CORE=0`.
- For native/core-only iteration, prefer the dev-core hot-swap path before reinstalling a whole APK: `.\tools\build_push_thor_core.ps1 -Label GAME_OR_FIX`. It builds the ARM64 native core, finds the newest `librpcsx-android.so`, stages it under `/storage/emulated/0/Android/data/net.rpcsx.easy/files/dev-core-staging/`, copies it into app-internal `/data/data/net.rpcsx.easy/files/dev-core/` with `run-as`, writes `active-core.path` / `active-core.json`, force-stops/relaunches the app, and can start an OODA stream without `adb install`.
- Debug APKs include `ThorDevCoreOverrideProvider`, a debug-only startup hook that reads app-internal `files/dev-core/active-core.path` and reasserts `rpcsx_library` to that pushed `.so`. Release behavior should remain bundled-core authoritative; do not move this provider into `main`. Android may refuse to load native code directly from external storage, so the active core must live in internal app storage; external storage is only staging.
- Reset Thor back to the bundled APK core with `.\tools\build_push_thor_core.ps1 -ResetToBundled`. This removes the dev-core markers and relaunches, letting MainActivity rewrite `rpcsx_library` back to the bundled native-lib path.
- Use full `.\gradlew.bat :app:assembleDebug` plus `adb install -r` when Java/UI/resources/manifest changed, when the debug provider changed, or when native packaging itself needs validation. Use dev-core hot-swap for SPU/PPU/RSX/runtime C++ experiments where only `librpcsx-android.so` changed.
- Current source-core status on 2026-05-10: `.\gradlew.bat ':app:configureCMakeDebug[arm64-v8a]'` succeeds, and `.\gradlew.bat :app:assembleDebug` succeeds after dependency hydration. The bundled debug APK includes `lib/arm64-v8a/librpcsx-android.so` plus `librpcsx-ui-jni.so`; the source-core build is slow and noisy with upstream warnings.
- Treat core changes as first-class repo changes: edit the vendored files directly, test where possible, then commit and push on `master`.

## Upstream RPCS3 Arm64 Mining

- Do not treat RPCS3's lack of official Android/iOS support as a reason to ignore its arm64 work. Treat upstream RPCS3 arm64 as a playbook to mine, then adapt the ideas to Android lifecycle, JNI/export boundaries, memory pressure, AYN Thor thermals, and Adreno/Vulkan driver reality.
- Current core rework direction: use RPCS3 ARM64 on Linux/Rocknix as the critical behavioral/performance reference, not generic Android PS3 forks. Keep the Android app shell and Thor UX, but make the native core converge toward the proven upstream ARM64 Linux path in small buildable slices.
- Primary project goal is not merely "make it boot." Boot stability is the baseline; the active goal is better performance, compatibility, and visual/audio quality on AYN Thor. Keep mining upstream RPCS3 for real CPU/GPU/runtime wins, but land them in measured slices with a fast rollback path when a speed import corrupts guest state or regresses boot.
- Do not abandon a promising upstream performance idea just because the first direct port crashes. First restore a known-good APK, document the failure signature, then retry the idea with instrumentation, feature gates, or a narrower implementation.
- Local upstream comparison checkout: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`. At the last inspection it had `origin/master` at `021f16f` (`rsx: Fix swapped width/height in NV309E_SET_FORMAT decoder`). The Android vendored RPCSX repo was at `e309e1e` (`Remove risky Eternal Sonata boot settings`).
- Before inventing Thor-specific native optimizations, diff the vendored core against upstream RPCS3 for `rpcs3/Emu/CPU/Backends/AArch64/*`, `rpcs3/Emu/CPU/CPUTranslator.*`, `rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`, `rpcs3/Emu/Cell/SPUCommonRecompiler.cpp`, `rpcs3/Emu/RSX/*`, `rpcs3/util/sysinfo.*`, and VM/page-size code.
- Imported dotprod target: upstream RPCS3's `m_use_dotprod` / `utils::has_dotprod()` paths for AArch64 `sdot`/`udot` in SPU `GB`, `GBH`, `GBB`, and `SUMB` are now the local reference. Keep the Android HWCAP gate and JIT target attributes in sync so Thor's Snapdragon 8 Gen 2 can actually lower those paths when Android reports `HWCAP_ASIMDDP`.
- Imported slice 2026-05-12: shared ARM64 feature gates in `util/sysinfo.*` now cover `NEON`, `SHA3`, `DOTPROD`, `SVE`, and `SVE2`; Android JIT SVE sanitization should use those shared core gates instead of local one-off HWCAP checks.
- Imported slice 2026-05-12: `JITLLVM` now passes upstream-style AArch64 target attributes (`+/-sha3`, `+/-dotprod`, `+/-sve`, `+/-sve2`) into LLVM and uses `cortex-a78` instead of `cortex-a34` as the unknown Android ARM64 fallback. Do not remove this without replacing it with a better Thor/Rocknix-aware CPU selection path.
- Imported slice 2026-05-12: ARM64 JIT telemetry now logs each unique LLVM engine target as `LLVM AArch64 target: cpu=... triple=... attrs=...`, and Thor Feature Doctor shows `LLVM ARM64 target attrs`. Use this before/after SPU or PPU imports to prove the intended CPU/features are active on device.
- Imported slice 2026-05-12: SPU worker setup follows the upstream ARM64 rule that ASMJIT is not an ARM64 SPU backend. On ARM64, ASMJIT requests fall back to LLVM with a warning, and Thor-managed per-game configs rewrite `SPU Decoder: Recompiler (ASMJIT)` to `Recompiler (LLVM)`.
- Imported slice 2026-05-12: the Android core now exports `_rpcsx_preparePpuCache`, backed by the existing PPU compilation path, so the UI cache-warm button can actually prebuild PPU cache for a stopped/ready title instead of only telling the user to boot once.
- Imported slice 2026-05-12: Thor now enables the native RPCS3 scheduler when the Android performance-core mask applies, with CPU3 shared/general, CPU4 PPU, CPU5-6 SPU, and CPU7 RSX. Android `thread_ctrl::get_affinity_mask()` intersects class masks with the thread's current runtime affinity so configured low cores do not leak back into PPU/SPU/RSX masks after the Java-side `0xF8` pin.
- Imported slice 2026-05-12: Android/Linux SPU reservation waits now honor the upstream-style `SPU Reservation Busy Waiting Enabled` gate instead of hard-disabling busy waits under `__linux__`. Thor profile v8 enables it at 100% and Feature Doctor reports the active gate/percentage. Watch thermals and SPURS-heavy games such as Eternal Sonata when tuning this.
- Imported slice 2026-05-12: SPU GETLLAR spin prediction now uses upstream's shared `evaluate_spin_optimization(...)` helper, tracks `last_getllar_lsa`, and avoids classifying stack-output GETLLAR patterns as tight wait loops. This keeps the new busy-wait path less reckless on SPU code that is not actually spinning.
- Imported slice 2026-05-12: `SPU_RdEventStat` now carries upstream-style reservation wait history (`eventstat_*`, 16-entry wait history, timed busy-wait fallback) while preserving the local Android reservation-notifier API. This is the main SPURS/Eternal Sonata-facing scheduler import; validate boot/gameplay and thermals before raising related percentages further.
- Imported slice 2026-05-12: latest safe SPU/RSX parity pass from refreshed upstream `021f16f`. Ported SPU LLVM LQX/STQX address reuse, CEQHI/CEQI compare-negation peepholes where compatible, SPU channel wait/occupy bit separation and stopped-wait cleanup, removal of RCHCNT loop handling for `SPU_WrOutMbox` / `SPU_WrOutIntrMbox`, and the NV309E RSX width/height decoder fix. Built native/APK and installed on Thor at `2026-05-12 17:23:24`.
- Imported slice 2026-05-12: upstream LLVM/SPU optimizer cleanup. `CPUTranslator::bitcast(...)` now reuses compatible existing bitcasts and carries the later upstream use-list guard in `erase_stores(...)`; SPU LLVM now marks SPU local-storage loads/stores and SPU thread-context loads/stores with separate alias/noalias metadata. This is a compile/codegen quality import for ARM64 SPU LLVM, built native/APK and installed on Thor at `2026-05-12 17:43:51`.
- Imported slice 2026-05-12: ISO streaming now handles upstream-style multi-extent directory entries and reads direct ISO files across extent boundaries instead of treating large payloads as one broken/whole-file read. Keep this as the baseline for Eternal Sonata's multi-GB archive files.
- Imported slice 2026-05-12: Android RAM pressure telemetry is now in the native core. `utils::get_memory_usage()` reads Android/Linux `/proc/meminfo`, PERF logs include used/free/peak RAM, emergency exits annotate low-memory conditions, and Android fatal reports include RAM totals. Use this before guessing at OOM/LMK behavior.
- Imported slice 2026-05-12: Vulkan scratch-buffer and DMA-barrier parity pass from upstream RSX fixes. Scratch allocations now carry explicit destination stage/access, texture flush DMA has a post-transfer barrier, tiling compute/transfer access masks match the producer, and unsafe GPU zero-copy skips userptr sources. This is an Adreno correctness/perf foundation, not an Eternal Sonata FPS cure by itself.
- Imported slice 2026-05-12: Vulkan shader interpreter can use the existing deferred pipeline compiler for experimental preload work, avoids duplicating interpreter uniform tables per variant, and logs interpreter cache misses over 1000 ms with the compiler option mask. The representative interpreter pipeline preload is disabled by default on Thor because the first APK felt dramatically slower; do not re-enable it for FPS testing without a narrow opt-in and timing logs.
- Deferred upstream slice: full async interpreter variant recompilation from RPCS3 commits `d519571`, `d93f5f9`, and `4e16032` is only partially portable until the local interpreter cache is refactored from raw `glsl::program*` / `unique_ptr` ownership to the upstream shared program cache, shader-object split, pipeline flags, and variant metadata. Do that ownership refactor before trying to replace live interpreter programs from worker callbacks.
- Deferred upstream slice: Vulkan data-heap/window UBO work is not directly portable yet because this fork lacks upstream's newer `VkDescriptorBufferInfoEx`, `address_range64`, `ex.h`, and `rsx::data_heap` plumbing. Revisit after the descriptor-buffer/data-heap refactor, not as a blind cherry-pick.
- Imported slice 2026-05-12: SPU reduced-loop work has started with detection-only instrumentation. `debug.rpcsx.thor.spu_reduced_loop_detect=1` scans analyser basic-block topology for upstream-style reduced-loop candidates and logs `Reduced Loop Candidate (detect-only)` with loop PC/end, block/instruction counts, and function hash. Eternal Sonata confirmed hundreds of candidates, including >300-instruction loops; use `.\tools\set_thor_logging.ps1 -Mode ReducedLoop` only for short captures, then return to `Quiet` because verbose SPU logging can stall loading.
- Active gated slice 2026-05-12: first SPU reduced-loop LLVM emission port is guarded by `debug.rpcsx.thor.spu_reduced_loop_emit=1` / `.\tools\set_thor_logging.ps1 -Mode ReducedLoopEmit`. This is not for normal FPS sweeps until it survives Eternal Sonata boot; the initial scope is simple no-supplemental-condition loops with a fast property rollback to `Quiet`.
- Remaining major Eternal Sonata target: upstream SPU reduced-loop detection/emission series (`a863e94`, `2e4ee9c`, `37a07ae`, `619fe7b`, `02eb549`, later analyzer fixes). Direct patch application fails against the vendored core because it needs analyzer/opcode/recompiler-struct migration; port as a dedicated gated slice with build checkpoints and a fast rollback.
- Attempted slice 2026-05-12: VM reservation notifiers were direct-ported toward upstream-style reservation-time buckets, then rolled back. The current stable Thor APK uses the older address-only notifier API again; do not treat rtime-aware notifier calls as active local behavior.
- Rolled-back slice 2026-05-12: the first rtime-aware reservation notifier and SPU PUTLLC / 128-byte store parity attempts caused deterministic `SIGBUS BUS_ADRALN` crashes in `PPU[0x1000000]` at PC/fault `0xd0020d77` on BLUS30161 after SPU runtime build. Revisit these as performance-quality targets, but only behind instrumentation/feature gates that log reservation address, rtime, waiter bucket/index, old/new hashes, and GETLLAR/PUTLLC loop identity before changing wakeup or partial-line store behavior.
- Keep using the existing Thor Feature Doctor output in `_rpcsx_systemInfo()` to verify HWCAP/HWCAP2 before enabling imported Arm64 fast paths. The important feature flag for the dot-product SPU work is `ASIMDDP/dotprod`; `I8MM` and `BF16` are also worth recording, but do not imply SVE.
- Upstream arm64 lessons to mine include LLVM tail-call/JIT gateway handling, AArch64 signal/exception decoding, 16K page-size and dirty-page tracking behavior, non-x86 RSX fallback fixes, and Linux/macOS/Windows-on-ARM build/runtime fixes. Android may need different wrappers, but the emulator-side ideas are still relevant.
- Avoid framing this work as "RPCS3 for Android exists." The correct framing is: this fork borrows proven upstream RPCS3 arm64 compiler/runtime techniques and ports/adapts them into a personal AYN Thor Android experiment.
- If an upstream arm64 idea depends on platform APIs unavailable on Android, document the missing API and build an Android-specific substitute where practical. Do not discard the idea until the emulator-level mechanism has been understood.

## North Star: Full-Speed PS3 On AYN Thor

- North-star goal: make demanding PS3 games run full speed, or as close to full speed as the hardware allows, on AYN Thor Base/Pro/Max. Eternal Sonata `BLUS30161` is the first serious canary because it is already booting but far too slow on Android.
- The active physical proof device is the user's AYN Thor Max. Use the Max for fastest iteration and large-cache experiments, but do not let 16 GB RAM hide behavior that would fail on Base or Pro. Any optimization that needs Max-only memory headroom must be labeled `max-only` until proven otherwise.
- Base and Pro still matter. Shared CPU/GPU wins should target all Snapdragon 8 Gen 2 / Adreno 740 Thor variants; memory-heavy cache, shader preload, or logging experiments need separate Base/Pro risk notes.
- Windows RPCS3 is the fast hypothesis lab. It is where we route scenes, capture RenderDoc/RSX behavior, test core patches quickly, and reject bad ideas early. Android Thor is the truth test for FPS, thermals, memory pressure, input latency, and Adreno driver behavior.
- The connected Thor reports `QCS8550`, board/platform `kalama`, and `Adreno (TM) 740`. Reconfirm with ADB before making GPU assumptions; public Thor naming can be confusing and Thor Lite is a different class of device.
- Drastic speed wins should come from emulator-core behavior: SPU/PPU scheduling, JIT/codegen quality, RSX/Vulkan synchronization, render target traffic, shader/pipeline churn, cache behavior, and Adreno-specific driver paths. UI polish is useful only when it helps measure or deploy those wins.

## Windows PC vs AYN Thor Mental Model

- Current Windows lab PC: Dell XPS 8940, Windows 11 Pro 64-bit build `26200`, Intel Core i7-11700 with 8 cores / 16 threads, 32 GB RAM, NVIDIA GeForce RTX 3060, Intel UHD Graphics 750, and Vulkan instance `1.4.321`.
- Current Windows Vulkan proof device is the RTX 3060 unless a run says otherwise: `NVIDIA GeForce RTX 3060`, proprietary NVIDIA Vulkan driver `591.86`, API `1.4.325`. The Intel UHD 750 is also visible as a Vulkan device but should not be treated as the default RPCS3 lab GPU.
- Current Thor proof device: AYN Thor Max, Android, `QCS8550`, `kalama`, Adreno 740, about 15.6 GB RAM reported by `/proc/meminfo`, and Qualcomm GLES driver `V@0676.53` dated `2023-12-27` in SurfaceFlinger.
- Thor CPU reality: 8 ARM cores split across Cortex-A510/A715/A710/X3 with the heavy mask `0xF8`; Windows CPU reality is x86-64 Intel Rocket Lake. Windows cannot validate ARM64 LLVM/JIT codegen quality, Android affinity, HWCAP gates, or Thor scheduler behavior.
- Windows is excellent for fast iteration: route finding, official RPCS3 config parity, popup-free boot automation, RenderDoc frame/event inspection, RSX/Vulkan resource lifetime reasoning, shader/pipeline identity, filesystem/ISO behavior, and shared-core changes that are CPU-architecture neutral.
- Windows is not performance truth for Thor. Do not carry over FPS, frame-time magnitude, shader compile cost, barrier cost, render-target bandwidth cost, memory pressure, or thermal behavior from RTX/NVIDIA to Adreno/Android without a Thor proof pass.
- Treat RTX/NVIDIA RenderDoc captures as an explanation engine, not a verdict. A Windows capture can say "this pass writes/readbacks color buffers often" or "this barrier chain looks suspicious"; only Thor AGI/Perfetto/`dumpsys`/screenshots can say whether that is the actual Adreno bottleneck.
- Desktop NVIDIA is an immediate-mode, high-bandwidth discrete GPU with a mature desktop driver. Thor Adreno is a mobile tile-based GPU sharing memory and power budget with the CPU. Prioritize Thor hypotheses around attachment load/store, render-target preservation, tile memory round-trips, narrow barriers, texture flushes, shader variants, driver-specific layouts, and thermal/frame pacing.
- Windows lab FPS also depends on host cleanliness. If Vita3K, another emulator, video encoding, a build, or a heavy browser/GPU workload is active on the same PC, label that run `contended-host` and do not use it as clean speed-win proof. It can still be useful for route validation, visual correctness, log-hit counts, and rough hypothesis triage.
- When a Windows experiment wins, classify the win before porting:
  - `shared-core-win`: logic improvement expected to transfer, such as reducing redundant SPU/PPU/RSX work.
  - `desktop-only-win`: NVIDIA/Windows behavior that is useful for diagnosis but not expected to speed Thor directly.
  - `thor-hypothesis`: Windows evidence suggests an Adreno test, but Android proof is still pending.
- A result is publishable for this project only after it says what happened on both machines: Windows lab observation plus Thor Max truth run. If Base/Pro risk exists because Max has more memory headroom, label it `pro-max` or `max-only` until checked.

## Windows Lab / Thor Proof Speed Workflow

- Adopt the Vita3K-Thor style of proof-driven experimentation, adapted for RPCSX/RPCS3 performance work: Windows is the fast lab, AYN Thor Android is the truth test, and the final record must say what happened on both platforms.
- Do not create another RPCSX checkout just to share core work. Treat shared emulator changes as a patch series and experiment record that can be proven in `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` or `rpcsx-core-src`, then ported into this repo's vendored core at `app/src/main/cpp/rpcsx`.
- The physical Android source of truth remains this repo. If a Windows-lab change wins, port the smallest relevant core slice into the vendored Android tree, build it, and test it on Thor with the existing OODA/dev-core tools.
- Classify every performance or bug-fix experiment as one of:
  - `shared-core`: SPU/PPU/RSX/compiler/runtime logic expected to apply to both Windows and Android.
  - `windows-lab`: desktop-only tracing, correctness harnesses, rapid debugging helpers, or temporary proof code.
  - `android-thor`: affinity, HWCAP gates, Adreno/Vulkan behavior, thermal/RSS pressure, Android lifecycle, or device properties.
  - `experimental-gated`: risky speed paths controlled by a debug property or config gate until proven.
- A speed fix is not real until it has an explicit Windows reasoning pass and an Android Thor proof pass. Windows FPS is useful context but never final proof for Snapdragon/Adreno performance.
- For each serious experiment, record an ID such as `20260515-spu-superpath-hotblock`, the hypothesis, touched files, expected win, rollback switch, Windows result, Android result, and final status: `proposed`, `windows-pass`, `android-pass`, `failed`, or `parked`.
- Track speed experiments in `debug-experiments/`. Keep local repro failures and raw captures in `debug-issues/` / ignored `debug-captures/`, but the experiment ledger is the durable map of hypotheses, gates, platform results, and regressions.
- Keep local Windows test games, disc dumps, extracted `PS3_GAME` folders, and loose ISO files under repo-root `iso/` only. This directory is ignored by Git and is for legally owned local test content; never commit game data, firmware dumps, decrypted PRX artifacts, save data with personal info, or cache-heavy runtime assets.
- Use `tools/windows_rpcs3_lab.ps1` for Windows RPCS3 launches. It searches repo-root `iso/` by default, resolves game roots/`PS3_GAME` folders/`USRDIR\EBOOT.BIN`/matching loose ISO files into boot targets, can install local PS3 firmware with `-Action InstallFirmware`, sets Qt/Vulkan paths, and writes captures under `debug-captures/windows-lab/`.
- The Windows lab pulls RPCS3's official config database from `https://api.rpcs3.net/config/?api=v1` into `rpcs3-upstream\build-msvc\bin\GuiConfigs\config_database.dat` when missing/stale or when `-RefreshConfigDb` is passed. No-GUI boots then apply DB config automatically when no custom per-game config overrides it. For Eternal Sonata `BLUS30161`, the current DB config is `Video: Frame limit: PS3 Native` and `Write Color Buffers: true`; this matters for black texture/black spot regressions.
- Windows lab launches must force visible FPS telemetry in the app config: performance overlay enabled, framerate/frametime graphs enabled, and window title format `FPS: %F | %R | %V | %T [%t]`. Keep this on for route discovery and visible Windows checks so screenshots/window titles show speed immediately.
- Windows lab launches must record normalized host contention by default. `tools/windows_rpcs3_lab.ps1` writes `host-system/*.json` snapshots plus `clean` / `moderate` / `high` lines in `run.md`; another active emulator such as Vita3K makes the run high-contention even if RPCS3 itself looks fine. Compare `Off` vs `Fast`/superpath results only when the host-contention grade matches, or rerun under a clean host before claiming a speed win.
- Always launch Windows RPCS3 route/performance work through `tools/windows_rpcs3_lab.ps1`, not by double-clicking `rpcs3.exe`. The lab script keeps games windowed, moves the visible RPCS3 game window to the second monitor when one is attached, and leaves the primary monitor free for Codex/control tools.
- Visual QA is part of every serious speed experiment. Use `-ScreenshotEverySeconds N -ScreenshotStartSeconds N -ScreenshotMaxCount N` on `tools/windows_rpcs3_lab.ps1` to capture window PNGs under the run's `screenshots/` folder. For known texture defects, capture before/after images at the same route point and record whether black spots, missing textures, flicker, or resolution-scaling changes improved or regressed.
- Default Windows game captures should use `-Mode NoGui`; use `-Mode Gui -Visible` only when the game window itself needs manual visual checks or input automation. If the RPCS3 GUI appears unexpectedly, stop it and rerun through the lab script with explicit `NoGui`.
- For Codex-driven scene routing, run `tools/windows_rpcs3_lab.ps1 -Mode NoGui -InputMacro "start:150;wait:800;cross:150"` style captures. The lab script writes a deterministic Player 1 keyboard pad profile for the active title before each run, so agent input does not depend on whatever physical controller profile the GUI last saved. Use `-SkipAgentInputProfile` only when intentionally testing a real controller profile.
- Macro names use PS3 labels mapped through the lab keyboard pad: `cross`/X, `circle`/C, `square`/Z, `triangle`/V, `start`/Enter, `select`/Space, `ps`/Backspace, d-pad arrows, left stick WASD, right stick Home/Delete/End/PageDown, shoulders Q/R/E/T/F/G, plus lab controls `focus`, `move2`/`secondary`, and `shot`/`screenshot`. Macro durations are milliseconds. Input-macro runs intentionally keep the game window visible/focusable but still suppress the main RPCS3 GUI and fatal-dialog popups.
- Use `.agents/skills/thor-game-controller` whenever input/control is the blocker. That skill owns Direct/Virtual/OdinRaw Thor input, Windows lab focus/window macros, before/after screenshots, and recovery from ignored input, GUI/fatal popups, title resets, or black transitions. Keep it separate from scene-route and perf skills so controller failures do not get mixed into speed conclusions.
- Prefer Markdown experiment entries for now; if this grows into many experiments, add a SQLite knowledge base like Vita3K-Thor so results can be queried by title ID, platform, subsystem, and experiment ID.
- Keep failed attempts valuable. Record why they failed, crash signatures, bad settings, and captures so the project does not keep rediscovering the same trap.
- Performance captures must name the game/title ID, platform, build/core identity, driver, cache state, config file used, logging mode, scene, duration, FPS/frame pacing, CPU hot threads, RSS/memory pressure, thermals when available, and whether the result is cold-cache or warm-cache.
- Use `Quiet` logging for FPS sweeps. Use `ReducedLoop`, `ReducedLoopEmit`, `SpursProbe`, syscall stats, and verbose logs only for short diagnostic windows because instrumentation can become the bottleneck.
- Faster Thor workflow rule: keep the app/game resident whenever possible. For native C++ changes, use `tools/build_push_thor_core.ps1` to hot-swap only `librpcsx-android.so`; for scene measurement, use warm saves/checkpoints plus `tools/eternal_sonata_speed_sprint.ps1 -Action AndroidScene` instead of a full build/install/OODA cycle.
- Debug APKs now include a direct Codex pad bridge: `tools/thor_input_macro.ps1 -InputMode Direct` sends debug-only `net.rpcsx.THOR_DEBUG_PAD` broadcasts into `RPCSXActivity` and calls the emulator overlay pad path directly. Prefer Direct mode for automated Thor routing because Android virtual key events and raw Odin `/dev/input/event9` injection are useful fallbacks but not as deterministic.
- Current Direct-mode Eternal Sonata boot route from title to first controllable field: `wait:90000;cross;wait:20000;start;wait:3000;cross;wait:1000;cross;wait:100000;shot:field;stick:left:left:1000;wait:1000;shot:field-move;threads:field-route`. The extra skip timing matters; a shorter wait stops on the story `Pause / Skip?` prompt instead of reaching the field. Direct stick syntax uses `stick:left:up:1000`, `stick:left:left:1000`, etc.
- Use a three-tier capture loop so profiling overhead does not become the benchmark:
  - Tier 0 fast truth: warm checkpoint, FPS overlay, `AndroidScene` screenshot/video, top threads, mem/thermal/gfxinfo. Use this for most before/after speed checks.
  - Tier 1 timing proof: `AndroidScene` with Perfetto-lite enabled, plus screenrecord, when CPU scheduling/frame pacing/memory pressure needs proof.
  - Tier 2 deep GPU proof: AGI/gapit frame or system traces, RenderDoc on Windows, Vulkan validation, or Snapdragon Profiler when available. Use these only for targeted Vulkan/RSX questions because they perturb runtime.
- Current Thor stock build profiling caveat: `/system/bin/perfetto`, `/system/bin/simpleperf`, and `/system/bin/screenrecord` exist, but the device reports `ro.debuggable=0`, `ro.build.type=user`, and `security.perf_harden=1`. Treat AGI GPU counters/simpleperf as potentially restricted on stock firmware; prefer Perfetto-lite plus screenshots for repeated runs, then use AGI frame traces selectively.

### Vulkan / Adreno 740 Speed Workstream

- Treat dramatic Vulkan work as a first-class speed program, not a random settings hunt. The likely win areas are RSX render-target traffic, attachment load/store behavior, image-layout transitions, pipeline barriers, descriptor/pipeline churn, shader compile/cache behavior, occlusion/depth/stencil paths, texture upload/flush synchronization, and mobile tiler bandwidth.
- Classify Vulkan experiments as:
  - `vulkan-shared`: RSX-to-Vulkan logic expected to apply on Windows and Android, such as render target invalidation, barriers, descriptor lifetime, pipeline cache behavior, shader translation, async texture upload, and WCB/RCB/WDB/RDB correctness.
  - `adreno-thor`: Android/Adreno 740 specific behavior, including tile-based bandwidth, UBWC/format behavior, Qualcomm driver quirks, Turnip vs stock driver, GPU memory pressure, thermal throttling, and queue/frame pacing.
  - `visual-correctness`: black spots, missing textures, flicker, broken lighting, wrong resolution scaling, or WCB/RCB regressions. Speed does not count if the frame is wrong.
  - `settings-db`: official RPCS3 database parity, per-game config, and proof that a custom config did not override required correctness flags.
- Prove Vulkan ideas in layers: first settings DB parity and visual baseline; then Windows RSX/Vulkan trace or RenderDoc-style frame capture; then Android Thor proof with FPS, screenshots, logcat, memory/thermal notes, and GPU-counter tooling when available; then a guarded patch with a rollback switch.
- Preserve correctness flags such as `Write Color Buffers` unless a same-scene screenshot proves the replacement path is visually correct. Never trade black textures or broken lighting for FPS and call it a win.
- Speed wins are correctness-locked. A faster build is not a pass unless Eternal Sonata's first playable field, battle, and menu still render correctly, with no new black spots, missing textures, flicker, broken lighting, or menu corruption.
- Use Windows tools for fast diagnosis: RenderDoc when capture-compatible, RPCS3 RSX/Vulkan logs, validation layers for correctness hunts, FPS overlay/window title, and automated screenshots from `tools/windows_rpcs3_lab.ps1`.
- Use Android tools for truth: `adb logcat`, screenshots/screenrecord, `dumpsys SurfaceFlinger`, `dumpsys gfxinfo`, Perfetto or Android GPU Inspector for Adreno counters, and Snapdragon Profiler / Adreno Offline Compiler if available. Capture at least one sustained run when testing thermals because short bursts can lie.
- Approved profiling/tooling stack for this project: install and use RenderDoc, Android GPU Inspector, Snapdragon Profiler, Perfetto, Vulkan validation layers, and Adreno Offline Compiler where available. Prefer official download sources and record tool versions in experiment notes when they affect results.
- Approved GPU driver experiments: test stock Qualcomm drivers, Turnip/Kimchi A6xx/A7xx packages, and other Thor-compatible Adreno 740 driver builds when useful. Every driver test needs an easy rollback to `Default`, the driver/package name, version/date, screenshots, FPS/frame-time notes, and a clear label if a result is driver-specific.
- Vulkan/Adreno paper-delta rule: tile memory is a first-class hypothesis, but only if the driver exposes the right path. Stock Qualcomm has so far shown `VK_QCOM_tile_properties` but not `VK_QCOM_tile_shading`, `VK_QCOM_tile_memory_heap`, `VK_QCOM_elapsed_timer_query`, or `VK_QCOM_queue_perf_hint`; retest this after every stock/Turnip driver swap with the Thor Vulkan Feature Doctor before designing tile-local work.
- Tiny Vulkan compute dispatches are presumed bad until proven otherwise. Any GPU superpath must batch by frame, SPU image family, RSX resource family, or another coarse unit; keep descriptor/buffer state persistent; avoid CPU readback on the critical path; and log dispatch, barrier, and submit timing. Do not build one-dispatch-per-SPURS-event, semaphore, or PPU-call paths.
- Compute/graphics overlap must be measured on Thor before relying on it. Vulkan queue-family support is only a possibility signal; use timestamps plus AGI/Perfetto counters to prove whether Adreno overlaps graphics and compute or serializes them, and schedule GPU work in known RSX gaps if overlap is fake or harmful.
- Frame-to-frame/tile coherence is a valid RSX research track. Start with verify-only detectors for repeated texture uploads, unchanged render targets, repeated resolves, repeated postprocess inputs, and static field/menu UI regions. Do not skip uploads/resolves until screenshots and hash checks prove unchanged output.
- Frame pacing is its own acceptance metric. For every serious Vulkan/driver/scheduler win, record sustained FPS plus 1% low or worst-frame notes, present cadence/jitter when available, audio underruns, and visible smoothness. A higher average FPS with worse pacing is not a win.
- Current Vulkan priority for Eternal Sonata: explain the cost and correctness role of `Write Color Buffers`, locate any render-target readback/writeback hot path, identify barrier or texture flush stalls, and determine whether black spots are a missing correctness path, a driver issue, or a settings/cache problem.
- CPU-to-GPU offload is an approved research track, but only as title/signature-gated superpaths, not a wholesale "SPU emulator on GPU" rewrite. First targets should be `BLUS30161` SPU jobs or PPU/RSX helper work that are bulk, data-parallel, stable by SPU image hash/DMA pattern, and either consumed by RSX/GPU or large enough to amortize Vulkan compute dispatch, barriers, and readback. Tiny SPURS control loops, semaphore choreography, and immediate PPU sync are bad GPU-offload candidates unless a trace proves otherwise.
- GPU superpath experiments must have verification mode first: run the normal CPU/SPU path and candidate GPU path together, compare outputs across repeated frames/jobs, log mismatches, and keep fast mode disabled until verification is clean. Field, first battle, and in-game menu must all pass visual correctness before a GPU offload path can count as promising.
- Thor Max-first GPU offload is allowed. If a path uses memory/cache/descriptor buffering that may not fit Base/Pro, label it `max-only` or `pro-max` in the experiment name and notes instead of blocking the investigation. Do not promote it to a shared Thor default until Base/Pro risk is measured.
- GPU candidate discovery in Windows RPCS3 is now controlled by `RPCS3_ES_GPU_PROBE=profile`, surfaced as `tools/windows_rpcs3_lab.ps1 -EternalSonataGpuProbe Profile` and the sprint wrapper. It logs Eternal Sonata SPU image signatures, DMA totals, list DMA, RSX-local traffic, max DMA PC/EA, and the max-DMA block hash when available. Probe runs also set `RPCS3_ES_GPU_PROBE_DUMP_DIR` to the run's ignored `spu-images/` folder, where the emulator writes one 256 KB SPU LS image plus RPCS3-disassembled hot-PC windows. Use `tools/summarize_eternal_sonata_gpu_probe.ps1 -RunDir RUN_DIR` to rank candidates, and treat zero RSX-local traffic as a sign to prioritize SPU-kernel/NEON/verified CPU superpaths before Vulkan compute.
- Use `tools/install_speed_sprint_tools.ps1 -Install` to install/verify RenderDoc and Android GPU Inspector into the local Windows toolchain. Snapdragon Profiler may require Qualcomm login; if unavailable, record it as blocked and use AGI/Perfetto/`dumpsys` first.
- Use `tools/eternal_sonata_speed_sprint.ps1` for repeatable sprint actions: `ToolStatus`, `DeviceSnapshot`, `WindowsScene`, `AndroidStart`, `AndroidScene`, `AndroidRouteScene`, `AndroidCapture`, and `AndroidStop`. Keep scene labels as `field`, `battle`, or `menu` and include driver/core identity in every Android run. `AndroidRouteScene` boots/routes through `tools/thor_input_macro.ps1`, sets Eternal Sonata debug gates, then captures the scene; `AndroidScene` is the preferred fast warm-cache scene check when the game is already positioned. Both capture screenshot/video, Perfetto-lite unless disabled, hot threads, mem/thermal, and gfxinfo without rebuilding.
- Windows RenderDoc captures can be launched with `tools/eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -RenderDoc -InputMacro "wait:45000;f12:120"`. The Windows lab injects RenderDoc into the running RPCS3 PID and stores `.rdc` captures under that run's `renderdoc/` folder; use `f12` in the macro or press F12 manually after reaching the target scene.

### First Speed Canary: Eternal Sonata

- Primary speed target: Eternal Sonata `BLUS30161` on AYN Thor Base/Pro/Max. The current problem is not just booting; it is being painfully slow on Android Thor, with prior live captures around 10-13 FPS and SPURS/RSX/SPU contention.
- Treat Eternal Sonata as the first benchmark for drastic performance work. The goal is major speed improvement with correctness intact, not tiny UI polish or a one-off setting that hides the real bottleneck.
- The first promising shared-core directions are SPU reduced-loop/superpath work, SPU hot-block profiling, AArch64/NEON/dotprod lowering quality, SPURS scheduling/wait behavior, RSX pipeline/worker stalls, and title-gated GPU compute superpaths for bulk SPU/RSX-adjacent jobs. Each must be gated or instrumented before it is allowed into normal FPS testing.
- Before trusting any Eternal Sonata result, verify `config/custom_configs/config_BLUS30161.yml`, current cache state, selected GPU driver, logging mode, and whether the dev-core override or bundled APK core is active.
- Do not reapply the previous managed `Max SPURS Threads: 4` idea as a normal profile. It caused a black-screen-alive load hang and needs a separate instrumented experiment before being reconsidered.
- Do not use the earlier `SafeSpeed` CPU profile as the default for Eternal Sonata. The 2026-05-16 Thor Max direct-route A/B dropped the opening route into low single digits with `RPCS3 Scheduler` + SPU reservation busy-wait, while neutral OS scheduling reached the first controllable field around 16-18 FPS.
- Do not use `RsxThreaded` as a default for Eternal Sonata. The 2026-05-16 Thor Max `Multithreaded RSX=true` A/B reached the same field with correct-looking visuals but dropped to about 12.7 FPS and introduced a hot `RSX Offloader` thread; NeutralCore stayed around 16-18 FPS.
- The Android Eternal Sonata semaphore superpath is a useful gated probe, not a speed win yet. It is controlled by `debug.rpcsx.thor.es_sema_superpath=off|profile|fast` and `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataSemaphoreSuperPath Off|Profile|Fast`; it hit about 98k fast semaphore operations in the field route with correct visuals, but FPS stayed roughly flat versus Off. Keep it off by default and use it as evidence that the next target is deeper SPU/MFC/RSX work, not wrapper syscalls.
- Android DMA/MFC profiling now confirms the Windows SPU hot-map on real Thor. `debug.rpcsx.thor.es_dma_superpath=profile|verify` / `tools\set_thor_logging.ps1 -Mode DmaProfile|DmaVerify` logs Eternal Sonata SPU image signatures, DMA/list traffic, payload hashes, and repeat/mismatch counters. Field profile on 2026-05-16 again found image `0x958dfe208b686622`, hot PCs `0x25cc`/`0x451c`, roughly 4.29 GB sampled DMA, and zero RSX-local traffic. Verify mode saw no output mismatches, but also no exact repeatable `(pattern,get_hash,put_hash)` hits, so a simple job-output replay cache is not the big win.
- The first MFC/list-copy fast path for aligned six-element list GETs is correctness-safe but not meaningful speed yet. Dev-core `es-mfc-list-fast` reached the field with correct visuals at about `17.59 FPS` on stock Qualcomm/NeutralCore, essentially the same `16-18 FPS` band as baseline. Keep the patch as a small shared-core copy-path cleanup, but do not treat it as the Eternal Sonata breakthrough.
- Extra scheduler testing on 2026-05-16 reinforced the baseline rule: keep `Thread Scheduler Mode: Operating System` for Eternal Sonata on Thor. `OldNeutral` and `AltNeutral` RPCS3 scheduler profiles, even without SPU reservation busy-wait, crawled around `2.2 FPS` in the story/tree route with `rsx::thread` near saturated and did not reach a comparable first-field sample.
- First positive speed signal: gated SPU reduced-loop emission now has a cache-safe Thor variant. Dev-core `es-reduced-loop-cache-key` (`CE15F5A95F636CAB3BCDFB347D9D3FE280B29924432652C37A0FC4225D1A69E9`) writes `spu-safe-thor-rl-v1-tane.dat` when `debug.rpcsx.thor.spu_reduced_loop_emit=1`, while normal mode keeps `spu-safe-v1-tane.dat`. After restoring the normal cache, reduced-loop field captures hit about `19.86 FPS` cold and `19.61 FPS` warm with correct-looking field visuals; pause/menu overlay hit about `20.18 FPS`. This is a real but still modest field/menu win, not yet the 20%+ target and not battle-validated.
- 2026-05-16 reduced-loop unroll follow-up: dev-core `es-reduced-loop-unroll` (`880C8B172817EB575C5201DED837905E3785960E70C4ACD609BC4025497A63AE`) adds `debug.rpcsx.thor.spu_reduced_loop_unroll` and cache keys `spu-...-thor-rl-uN-v1-tane.dat`. Matched field route: u2 `18.65 FPS`, u4 `19.81 FPS`, u8 `19.29 FPS`, with correct-looking field visuals. u4 menu route hit `20.22 FPS` with correct pause overlay, and an 8-frame menu burst showed no obvious black spots/menu corruption. Treat u4 as the current promising reduced-loop setting, but still not a full win until first battle is validated.
- Battle route status: first try from the field with `stick:left:right:5000` did not reach battle. It hit Polka's boundary dialogue, "Let's go back to Tenuto.", in `debug-captures/android-speed-sprint/20260516-074912-thor-input-custom/02-battle-candidate.png` and the follow-up scene capture. Do not reuse that right-walk macro as a battle proof; tune a different direction/checkpoint or find a save closer to the first fight.
- Do not blindly re-port rtime-keyed reservation notifier work. The first attempt caused deterministic `SIGBUS BUS_ADRALN`; revisit only with narrower logging, alignment checks, rollback gates, and a direct comparison against upstream behavior.
- A good Eternal Sonata speed experiment should produce three artifacts: a Windows/shared-core observation explaining why the change should help, an Android Thor capture proving FPS/frame-time/CPU behavior changed, and a note explaining regressions or correctness risk.
- Required Eternal Sonata visual checkpoints for speed work: first playable field, first battle, and in-game menu. Use the same route/save state/checkpoint where possible so before/after screenshots are comparable.
- For visual validation, record whether `Write Color Buffers`, driver selection, cache state, and render resolution match the baseline. If a speed path changes any of those variables, call it out in the experiment entry before comparing FPS.
- Current Windows field route uses the Thor/Windows save `BLUS3016100`: from title wait about 45s, tap `ls_down` once to `LOAD`, select Save File 01, move confirmation from `No` to `Yes` with `ls_up`, load, press `start` during the story scene, and `cross` the `Skip? Yes` prompt. `tools/eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field` now supplies this macro by default when `-InputMacro` is omitted; override only when testing a different checkpoint.
- 2026-05-15 Windows route proof: `debug-captures/windows-lab/20260515-203026-eternal-sonata-field-menu-proof/` reaches the Path to Tenuto field render around 97s with FPS overlay and no RPCS3 GUI overlay. The route is controllable enough for visual/FPS field baselines, but the next checkpoint work still needs a later save or additional skip presses to reach fully player-controlled movement and the in-game menu cleanly.
- 2026-05-16 Thor Max route proof: Direct-mode macro reached first controllable field and pause overlay with correct-looking rendering. NeutralCore field screenshots show about 16.4-18.0 FPS; hot threads are `rsx::thread`, five active SPU threads, and active PPU threads; `dumpsys meminfo` reported about 4.45 GB RSS with about 1.9 GB graphics memory.
- 2026-05-16 dev-core workflow fix: `tools/build_push_thor_core.ps1` must `cd /data/data/net.rpcsx.easy` inside `run-as` before copying staged dev cores. On this Thor, `run-as` starts in `/`, so relative `files/dev-core/...` paths silently fail without the explicit app-data cwd.

## Local Build Environment

- Repo path: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android`
- Java: `C:\Users\leanerdesigner\.codex\jdks\jdk-17`
- Android SDK: `C:\Users\leanerdesigner\AppData\Local\Android\Sdk`
- ADB: `C:\Users\leanerdesigner\AppData\Local\Android\Sdk\platform-tools\adb.exe`

Use these environment variables for Gradle commands in PowerShell:

```powershell
$env:JAVA_HOME='C:\Users\leanerdesigner\.codex\jdks\jdk-17'
$env:ANDROID_HOME='C:\Users\leanerdesigner\AppData\Local\Android\Sdk'
```

Useful verification commands:

```powershell
.\gradlew.bat :app:testDebugUnitTest
.\gradlew.bat :app:assembleDebug
.\tools\hydrate_rpcsx_core_deps.ps1
.\gradlew.bat :app:assembleDebug -PbuildBundledRpcsxCore=false
```

## PowerShell / ADB Quoting Rules

- This repo is driven from Windows PowerShell. Treat `adb shell` quoting as a high-risk area, especially for `run-as`, `sh -c`, `&&`, pipes, redirects, globs, or paths containing `/storage/emulated/0/...`.
- For compound remote shell commands, pass the entire remote command as one argument to `adb shell`. Good pattern:

```powershell
& $Adb shell "run-as net.rpcsx.easy sh -c 'mkdir -p files/dev-core && ls -ld files/dev-core'"
```

- Avoid tokenized `run-as ... sh -c` calls from PowerShell for compound commands. This bad pattern can strip the quotes before Android sees them, causing errors like `mkdir: Needs 1 argument`:

```powershell
& $Adb shell run-as net.rpcsx.easy sh -c "mkdir -p files/dev-core && ls -ld files/dev-core"
```

- For simple `run-as` commands that do not need shell operators, direct tokenized calls are fine:

```powershell
& $Adb shell run-as net.rpcsx.easy ls -ld files/dev-core
```

- In scripts, prefer a tiny helper for compound `run-as` commands that emits one remote command string, then check `$LASTEXITCODE`. Keep paths/arguments simple enough to avoid nested quote escaping where possible.
- `adb push` writes progress to stderr on some hosts. Do not let PowerShell native-stderr behavior turn successful pushes into `NativeCommandError`; capture `2>&1`, set native command error action off inside wrappers when available, and decide success from `$LASTEXITCODE`.
- Never name custom PowerShell parameters `$Args`; it collides with the automatic `$args` variable and has already caused broken git/adb invocations. Use names like `$GitArgs`, `$AdbArgs`, or `$HelperArgs`.

## Thor Debug Capture Workflow

- For black screens, crashes, or weird per-game boot behavior, use the Thor debug tools before guessing.
- Default to the game-agnostic OODA wrapper first: `.\tools\thor_ooda.ps1 -Action Auto -Profile default -Label GAME_OR_SYMPTOM`. It creates a local markdown/JSON issue, builds the latest debug APK, installs it on Thor, toggles the requested logging mode, starts the capture stream, and records device/repo/APK metadata.
- Per-game debug profiles are opt-in overlays under `debug-profiles/*.json`, not the default mental model. Use `default` for unknown titles and create or select a special profile only when a game has known probes, title IDs, guest modules, Ghidra addresses, or logging modes. `eternal-sonata` is the current SPURS/Ghidra example.
- Agent workflow should be automatic unless the user says to pause: build/install latest APK, set ADB logging props from the profile, capture or stop the stream, write `debug-issues/<timestamp-label>/issue.md` plus `issue.json`, auto-run Ghidra when the profile or logs identify `module:0xaddress`, then patch narrowly and rerun the same profile.
- Fast live loop: start once with `.\tools\thor_ooda.ps1 -Action Auto -Profile PROFILE -Label GAME`, run `.\tools\thor_ooda.ps1 -Action Summarize -Profile PROFILE -Label GAME -NoIssueCommit` while the user is reproducing, then finalize with `.\tools\thor_ooda.ps1 -Action Stop -Profile PROFILE -Label GAME`. `Stop` writes the final issue and resets noisy logging modes to `Quiet` unless `-KeepLogging` is passed.
- Fast core loop after the debug APK is already installed: edit C++ core, run `.\tools\build_push_thor_core.ps1 -Label GAME_OR_FIX -Profile PROFILE`, let the script push only `librpcsx-android.so` and relaunch, then use OODA summarize/capture/stop around the user's repro. This is the preferred tight loop for Eternal Sonata SPU/PPU/RSX performance work.
- One-shot loop: use `.\tools\thor_ooda.ps1 -Action Capture -Profile PROFILE -Label GAME` when the bad state is already visible. The wrapper now adds a small `triage.md` quick read to the issue folder and resets logging to the profile's `capture.postMode`.
- Profile `capture.logcatLines`, `capture.summaryTailLines`, `capture.postMode`, and `stream.pollSeconds` are the first knobs to tune before editing scripts. Keep default captures lighter than deep crash pulls so repeated loops are fast; override with CLI flags only when the current repro needs deeper history.
- If `Summarize` reads an old `debug-captures/latest-stream.txt`, do not trust the quick read as current device state. Start a fresh `Auto` stream for the active repro, or explicitly stop/archive the stale stream first. Old live tails can make the agent chase yesterday's compile logs.
- Stopping a stale live stream on Windows can upset the Codex process runner if an old ADB child is wedged; a observed failure mode is every new shell/Node launch immediately returning `0xc0000142`. If that happens, stop issuing shell commands, record the blocker, and resume cleanup/commit/push only after the host runner is healthy again.
- Before committing OODA workflow changes, delete smoke-only local issue folders such as `debug-issues/*ooda-smoke*` and `debug-issues/*ooda-summary-smoke*`; keep only reusable docs/profiles/scripts plus real repro issues. Raw smoke captures under ignored `debug-captures/` may be removed as cleanup but must not be committed.
- Commit and push each completed OODA slice on `master`. Raw logs, streams, tombstones, pulled configs, and Ghidra projects stay ignored in `debug-captures/`; the durable trail is the committed local markdown/JSON issue under `debug-issues/`.
- Do not create GitHub issues for this project. Use local markdown issues only unless the user explicitly asks for a GitHub issue.
- Ghidra/static analysis is now a required lane after a runtime hot path is found. Use the repo-local `thor-ghidra-static-lane` skill for PPU PRX/ELF, SPU local-store, Ps3GhidraScripts, and GhidraSPU work. Keep it anchored to runtime evidence and write findings into `debug-experiments/`; do not drift into whole-game decompilation or external decryption tooling.
- Current clean Ghidra tooling: local Ghidra 12.0.4, built-in big-endian `PowerPC:BE:64:64-32addr` / PowerISA-Altivec-64-32addr for PPU, `Ps3GhidraScripts` for PS3 imports/exports/NIDs/syscalls, and experimental `GhidraSPU` only for ignored SPU local-store captures. Existing repo hooks are `tools/run_thor_ghidra_prx_probe.ps1`, `tools/ghidra_scripts/DecompileAddresses.java`, OODA Ghidra auto-probes, PPU `dump_executable(...)`, and SPU `capture_memory_as_elf(...)`.
- Eternal Sonata's next Ghidra target is the measured SPU `GETLLAR`/reservation retry hot loop. First log top SPU image hash, PC, block hash, reservation address, and thread/group name; then inspect only that SPU window and convert the finding into a gated emulator-side optimization.
- Control device logging with `.\tools\set_thor_logging.ps1 -Mode Quiet|Normal|Verbose|ReducedLoop|ReducedLoopEmit|SpursProbe|SemaProfile|SemaFast|DmaProfile|DmaVerify|RsxAuditor|RsxDmaHostFence|Status`. Use `Quiet` for FPS/performance sweeps, `Normal` for ordinary crash/boot repros, `ReducedLoop` only for short SPU compiler captures, `ReducedLoopEmit` only to test the gated reduced-loop LLVM path, `SpursProbe` only for short SPURS/loading-hang captures, `SemaProfile`/`SemaFast` only for the gated Eternal Sonata semaphore probe, `DmaProfile`/`DmaVerify` only for short Eternal Sonata SPU DMA/MFC candidate runs, `RsxAuditor` only for short RSX/Vulkan barrier/pipeline/tiling captures, `RsxDmaHostFence` only for short correctness/FPS tests of the experimental RSX DMA host-read fence, and `Verbose` only for short targeted syscall captures because it enables PPU syscall usage stats.
- The logging tool sets Android properties over ADB: `debug.rpcsx.thor.logcat`, `debug.rpcsx.thor.syscall_stats`, `debug.rpcsx.thor.spu_reduced_loop_detect`, `debug.rpcsx.thor.spu_reduced_loop_emit`, `debug.rpcsx.thor.spurs_probe`, `debug.rpcsx.thor.es_sema_superpath`, `debug.rpcsx.thor.es_dma_superpath`, `debug.rpcsx.thor.rsx_auditor`, `debug.rpcsx.thor.rsx_dma_fence`, `debug.rpcsx.thor.dump_prx`, `log.tag.RPCS3`, and `log.tag.RPCSX-UI`. The bundled core polls/logging properties at runtime where supported, so Codex can turn logcat/syscall-stat pressure on or off without rebuilding after this APK is installed.
- `Quiet`, `Normal`, `Verbose`, `ReducedLoop`, `ReducedLoopEmit`, and `SpursProbe` all clear `debug.rpcsx.thor.dump_prx=0` and reset `debug.rpcsx.thor.es_sema_superpath=off`; use the dedicated Ghidra PRX workflow when a decrypted module dump is needed.
- Do not leave `debug.rpcsx.thor.syscall_stats=1` during FPS testing. Eternal Sonata can hit hundreds of thousands of timer/semaphore/SPU-group syscalls in a few minutes, and stats/logging can become its own benchmark poison.
- Live debug loop while the user plays: `.\tools\start_thor_debug_stream.ps1 -ClearLogcat -Launch -Label GAME`, then repeatedly run `.\tools\summarize_thor_debug_stream.ps1 -Latest` from Codex while the user reproduces the issue, then `.\tools\stop_thor_debug_stream.ps1 -Latest`.
- Live streams write to ignored `debug-captures/*-stream/` folders. Watch `summary-latest.md`, `logcat-live.txt`, `rpcsx-live-tail.txt`, and `live-summary/now-*.txt`.
- Newer live streams also write `memory-live.txt`; use it to catch RSS/swap growth before Android's low-memory killer takes the app down.
- Clean repro flow: `.\tools\collect_thor_debug.ps1 -Prepare -Launch -Label GAME`, reproduce on Thor, then `.\tools\collect_thor_debug.ps1 -Label GAME`.
- Do not run `-Prepare` after a crash; it clears logcat and destroys the freshest evidence.
- Captures are written under ignored `debug-captures/` folders. Start analysis with `logcat-interesting.txt`, `device-files/cache/RPCSX.log`, `rpcsx-log-errors.txt`, `activity.txt`, and `cache-summary.txt`.
- Classify the failure before changing code: native/app crash, black screen while app is alive, or regression after settings/core/cache/driver/cheat changes.
- For black screen while alive, check whether the title is still compiling, installing game data under `dev_hdd0/game`, waiting on a PS3 dialog, or producing audio without RSX frames.
- Reusable Ghidra pattern for game-specific hangs: first capture logs/probes until they name a guest module and address, then dump/decompile that exact decrypted PRX instead of guessing from raw firmware files. Raw `*.sprx` files are often encrypted `SCE\0` containers and are usually the wrong input.
- Use `.\tools\run_thor_ghidra_prx_probe.ps1 -Module NAME -Addresses 0xADDR1,0xADDR2 -WaitSeconds N` when a log points at code such as `libsre:0x00cc948c`. The helper sets `debug.rpcsx.thor.dump_prx=NAME`, waits for the core-side decrypted `prog.prx` dump under the app cache, imports it into a timestamped Ghidra project, and writes decompile output under `debug-captures/ghidra-NAME-*`.
- Treat Ghidra output as a map for the next instrumented build, not as proof by itself. Convert findings into narrow probes around the specific syscall, SPURS state, reservation address, mailbox/channel, or guest loop that the decompile exposes; then rebuild/install and verify on Thor.
- Use Ghidra primarily for guest-code questions such as "what is this hot SPURS handler doing?" or "what condition keeps this loading loop alive?" For Android/native tombstones in `librpcsx-android.so`, start with tombstone/logcat/addr2line-style native symbol work first, then use Ghidra only if the crash is tied back to a guest PRX/module address.
- After each Ghidra-assisted investigation, add a dated AGENTS note with the capture folder, module, addresses, observed guest behavior, and the next probe target. This keeps the thread from repeating the same expensive dump/decompile loop.
- If a live stream is active, do not leave it running forever after the repro. Stop it, inspect the final pull, then commit fixes or notes.
- A 2026-05-12 Eternal Sonata live stream at roughly 10-13 FPS showed no OOM/crash, but did show `rsx::thread` plus six SPU threads hot, heavy `sys_timer_usleep`, `sys_semaphore_wait/post`, `sys_event_queue_receive`, and repeated `sys_spu_thread_group_start/join`. Treat this as a SPURS/RSX contention profile first, not a basic boot failure.
- A 2026-05-12 Eternal Sonata `Now Loading` hang after reduced-loop capture was app-alive, not an Android crash: no ANR/tombstone, about 118% process CPU, about 2.2 GB PSS, with `rsx::thread`, `SPU[0x0000200]`, and multiple PPU threads hot. If this repeats, switch to `Quiet`, sample `top -H`/meminfo, then force-stop; do not leave `ReducedLoop` logging on during load/FPS testing.
- A later 2026-05-12 stuck `Now Loading` capture in `Quiet` showed active loading-screen animation, no crash, stable memory, and a repeating SPURS workload churn: in 10 seconds roughly 102k `sys_timer_usleep`, 4.2k `sys_event_queue_receive`, 3.7k semaphore waits/posts, and 1.6k `sys_spu_thread_group_start/join`. Use the gated `SpursProbe` mode to identify the exact SPU group/name/cause/status plus SPU-side LR/notifier/PUTLLC wait counters before changing SPURS scheduling or reservation waits. Code inspection found upstream RPCS3 waits on generation-specific reservation notifier values, while the Android fork still waits on a constant waiter flag in this path; treat that as a prime suspect, but do not re-port the rtime notifier blindly because the first attempt caused a deterministic SIGBUS.
- A 2026-05-12 `SpursProbe` capture on the rebuilt wait-probe APK at Eternal Sonata `Now Loading` showed 23 `Thor SPURS probe` group-join samples and **zero** `Thor SPURS wait probe` samples. The hot loop is `PPU[0x1000009] SpursHdlr0` at `libsre:0x00cc948c` repeatedly starting/joining single-SPU `CellSpursKernelGroup` `0x4000200` (`max_num=1`, `max_run=1`, `cause=0x1`, `status=0`, about 94 joins/sec), while syscall stats still show heavy `sys_timer_usleep`, event-queue receives, semaphore wait/post, and SPU group start/join. Next probe should move to PPU-side event/semaphore/SPURS workload state or group args/exit context; do not assume the hang is an SPU LR/notifier/PUTLLC wait.
- Imported probe slice 2026-05-13: `SpursProbe` now also logs `Thor SPURS PPU wait probe` once per second from PPU-side `sys_event_queue_receive`, `sys_semaphore_wait/post`, and `sys_timer_usleep`. It reports cumulative counts plus PPU id/name, CIA/LR, object id, timeout, details, and result. This is read-only instrumentation for the Eternal Sonata SPURS churn; use it to decide whether the hot `libsre` handler is primarily sleeping, waiting on a specific queue/semaphore, or bouncing through ready events before changing scheduler behavior.
- Ghidra path for static analysis is `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC`; the local headless helper is `.\tools\run_thor_ghidra_prx_probe.ps1`. For the Eternal Sonata loading hang, set/dump `libsre` and decompile `0x00cc948c` / `0x00cc945c`. Raw firmware `libsre.sprx` is an `SCE\0` container and does not import directly into Ghidra; use the gated core property `debug.rpcsx.thor.dump_prx=libsre` so the emulator dumps the decrypted PRX after `decrypt_self`, then pull/run Ghidra from `debug-captures/`.
- For decrypted `libsre` Ghidra imports, do not assume the logged guest address is the raw Ghidra import address. The 2026-05-15 probe showed the useful text bytes at a `0x100` skew in the import, and the Eternal Sonata `SpursHdlr0` run appeared to use a module base near `0x00cc0000`: logged `libsre:0x00cc930c` mapped to Ghidra `0x0000940c`, and logged `libsre:0x00cc948c` mapped to Ghidra `0x0000958c`. If Ghidra reports bad instruction data, recalculate `guest_address - module_base + import_skew` before trusting the miss.
- Game-specific "super speed" paths are allowed only as emulator-side, correctness-locked, title/signature-gated experiments. For Eternal Sonata, the first candidate is a `BLUS30161` SPURS handler superpath around the `libsre` `SpursHdlr0` loop that repeatedly starts/joins single-SPU `CellSpursKernelGroup` work (`max_num=1`, `max_run=1`, `cause=0x1`, `status=0`). Keep it behind a debug property until field/battle/menu visual checks and Thor FPS prove it.
- Windows lab superpath slice 2026-05-15: `rpcs3-upstream` now has a gated Eternal Sonata SPURS detector/cache path in `sys_spu` controlled by `RPCS3_ES_SPURS_SUPERPATH=detect|cache`, exposed through `tools/windows_rpcs3_lab.ps1 -EternalSonataSuperPath Detect|Cache` and the sprint wrapper. It matches `BLUS30161`, `SpursHdlr0`/`TCX_SpursHdlr0`, `CellSpursKernelGroup`, `max_num=1`, `max_run=1`; cache mode materializes 1,920 bytes of SPU image segments after normal deploy proves no patches applied, then reuses those bytes on later starts. It does not skip SPU execution, `cpu_init()`, or join cause/status.
- Windows result for that slice: detect/cache runs under `debug-captures/windows-lab/20260515-192807-eternal-sonata-superpath-detect/`, `20260515-192925-eternal-sonata-superpath-cache/`, and `20260515-194147-eternal-sonata-superpath-cache-final/` confirmed about 94 start/join cycles/sec, one cache build followed by thousands of hits, and no title/preload visual corruption. The deploy/init cost is tiny on Windows; cumulative join/work wait dominates, so this cache path is a safe probe but probably not the dramatic FPS cure by itself.
- Windows GPU-candidate probe slice 2026-05-15: `rpcs3-upstream` now has `RPCS3_ES_GPU_PROBE=profile`, exposed through `tools/windows_rpcs3_lab.ps1 -EternalSonataGpuProbe Profile` and summarized by `tools/summarize_eternal_sonata_gpu_probe.ps1`. Field route run `debug-captures/windows-lab/20260515-230825-eternal-sonata-gpu-probe-field-sampled-windows/` reached 3D gameplay with FPS overlay and no obvious field visual corruption, but host contention was `high` because Vita3K was active. The sampled probe found 1,157 records, about 1.35 GB observed DMA, top image `0x958dfe208b686622`, hot PCs `0x25cc` and `0x451c`, and zero RSX-local traffic. Later smoke `debug-captures/windows-lab/20260515-232647-eternal-sonata-gpu-probe-disasm-smoke-windows/` also dumped `spu-images/BLUS30161-spu-image-958dfe208b686622-entry-00818-...ls.bin` plus hot-PC disassembly sidecars. `0x25cc` and `0x451c` both sit in MFC/DMA command issue/wait code, so the first drastic candidate is a verified SPU DMA-loop/job-HLE, reduced-loop/codegen, or scheduler/copy superpath, not a blind Vulkan compute offload, until battle/menu or RenderDoc/AGI proves GPU-resident output.
- Optional Windows/Android probe `RPCS3_ES_SPURS_JOIN_SPIN=N` / `-EternalSonataJoinSpin N` exists but defaults off. The Windows spin run `debug-captures/windows-lab/20260515-193614-eternal-sonata-superpath-cache-spin/` had zero spin hits and all misses, slightly worsening join timing. Do not enable it for FPS sweeps unless a Thor trace shows Android-specific scheduler latency short enough to catch.
- The latest SPURS state probe logs `Thor SPURS state probe` once per second for `CellSpursKernelGroup` joins. Use it with `SpursProbe` to capture the SPURS control block/workload state alongside the existing join loop before changing SPURS scheduling or event/semaphore semantics.
- Before trusting an Eternal Sonata FPS result, inspect `config/custom_configs/config_BLUS30161.yml`. A stale full custom config can override Thor defaults, but the attempted managed `Max SPURS Threads: 4` profile caused a black-screen-alive load hang on 2026-05-12. Use `.\tools\push_eternal_sonata_thor_profile.ps1` only as a safe boot rollback; do not reapply SPURS 4 for this game without a separate instrumented test build.
- A live Thor repro on 2026-05-11 caught `BLUS31386` crashing in PPU LLVM precompile with `memory_commit(... errno=12=Out of memory)` and an LLVM `report_bad_alloc_error` tombstone. Treat first-boot full PPU precompilation as risky on Thor; the fork defaults should prefer `LLVM Precompilation=false` and low compile-thread pressure unless a guarded cache-builder mode is being tested.
- A later 2026-05-11 repro showed Android LMK killing `net.rpcsx.easy` near 6 GB RSS while a direct ISO game opened multi-GB `/dev_bdvd/PS3_GAME/USRDIR/archives/*.files` payloads. The vendored ISO device must stream file reads; do not reintroduce whole-file ISO reads or whole-file ISO extraction copies for large game data.

## Device Testing

- Target handheld: AYN Thor Base/Pro/Max.
- Known ADB model string: `AYN_Thor`.
- Debug APK path after assemble: `app\build\outputs\apk\debug\rpcsx-thor-experiment-debug.apk`.
- Android package: `net.rpcsx.easy`.
- Launcher label: `RPCSX for AYN Thor Experiment`.
- Launcher activity: `net.rpcsx.MainActivity`.
- This fork sets `BuildConfig.FORK_BUILD=true`; automatic upstream UI/core update prompts should stay disabled.
- Folder import is intentionally conservative: only loose `.pkg` and `.edat` files are sent to the native installer. Loose `.iso` files under Android external-storage documents are added as direct library entries instead of extracted, because the current core can abort while extracting some ISO directory entries.
- External ISO entries parse `PS3_GAME/PARAM.SFO` and `PS3_GAME/ICON0.PNG` directly from the ISO to populate title IDs, names, cheat matching, and cached cover art.
- The README is source-first: no big public APK download button, no support queue positioning.
- In-game Back is handled by `RPCSXActivity`; it opens the native RPCSX Home Menu on a background thread and then acts as menu back/resume while the menu is up.
- Gameplay Back behavior is hardcoded for Thor/fork builds: Android Back / Thor Back opens the native Home Menu, the core forces pause-during-Home-Menu on, and another Back press injects the native menu back/cancel action so nested pages back up and the root menu resumes gameplay.
- Gameplay-only physical hotkeys are hardcoded for Thor controls: `Select + R1` toggles Fast Forward 2x, `Select + right stick down` quick-saves, and `Select + right stick up` quick-loads the latest per-game savestate. Select is delayed and sent as a normal tap only when no hotkey combo is completed.

Install and launch:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" devices -l
& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r app\build\outputs\apk\debug\rpcsx-thor-experiment-debug.apk
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell pm grant net.rpcsx.easy android.permission.POST_NOTIFICATIONS
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell monkey -p net.rpcsx.easy 1
```

If the launcher or another foreground app steals focus, launch the main activity directly:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell am start -n net.rpcsx.easy/net.rpcsx.MainActivity
```

If the app does not appear, verify the installed package:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell pm list packages net.rpcsx.easy
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell cmd package resolve-activity --brief net.rpcsx.easy
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell dumpsys activity activities | Select-String -Pattern 'topResumedActivity|net.rpcsx.easy'
& "$env:ANDROID_HOME\platform-tools\adb.exe" shell pidof net.rpcsx.easy
```

## Native Home Menu / OSD Work

- Android already shows the native RPCSX in-game `Home Menu` over gameplay. Do not build a separate Android/Compose OSD unless the user explicitly asks for a replacement.
- The Android wrapper currently opens that menu through `_rpcsx_openHomeMenu`, surfaced as `RPCSX.instance.openHomeMenu()`. `RPCSXActivity` treats Android/Thor Back as the Home Menu toggle/back control; do not remap controller Circle/B to this Android-only action.
- Adding first-class menu rows such as `Cheats` or `Show FPS` belongs in the native/core Home Menu implementation, or behind a deliberate exported C ABI hook that the Android app can call. Android layout files cannot directly add rows to the existing menu.
- Native Home Menu source now lives in this repo under `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/HomeMenu/`.
- The Android-side native export surface for the full core lives at `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`; the lightweight dynamic-loader wrapper lives at `app/src/main/cpp/native-lib.cpp`.
- Localized Home Menu IDs live in `app/src/main/cpp/rpcsx/rpcs3/Emu/localized_string_id.h`.
- FPS/performance overlay rendering/reset code lives around `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/overlay_perf_metrics.cpp`.
- The vendored Home Menu now has a `Cheats` page source at `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/HomeMenu/overlay_home_menu_cheats.cpp`, plus top-level `Fast Forward 2x` and `Show FPS` toggles after Resume/Cheats.
- These vendored Home Menu changes require the source-built/bundled core APK or another core build that includes these files. The default lightweight-wrapper build alone cannot change the native Home Menu.
- The current Home Menu on this fork should include `Resume Game`, `Cheats`, `Fast Forward 2x`, `Show FPS`, `Settings`, `Trophies`, `Take Screenshot`, `Start/Stop Recording`, `SaveState`, `Restart Game`, and `Exit Game`.
- FPS display is already represented in the RPCSX config file under `Video -> Performance Overlay -> Enabled`. Through the Android settings bridge this should be treated as `Video@@Performance Overlay@@Enabled`.
- If only a simple FPS toggle is requested, prefer toggling `Performance Overlay.Enabled` first. Avoid enabling debug overlays or graph-heavy performance views unless the user asks for more metrics.
- Fast Forward 2x is a runtime guest-time speedhack: `_rpcsx_setFastForwardEnabled` changes `Core -> Clocks scale` to `200` and restores the previous value when disabled. It is not a frame-limit uncap, and it may break timing-sensitive games.
- Hotkey save/load uses `_rpcsx_saveState` and `_rpcsx_loadState`; quick-save forces continuous savestate mode so gameplay resumes instead of saving-and-exiting.
- Cheat toggles in the Home Menu should show only the currently running game's cheats, one row per cheat, with controller-friendly toggle behavior.
- Cheat state is persisted in `config/patch_config.yml`; generated patch definitions live under `config/patches/TITLEID_patch.yml`.
- For live cheat toggling, use the existing optional native hook `RPCSX.setPatchEnabled(hash, description, enabled)` when the current core exports it. If the hook is missing or the patch cannot apply live, the menu must clearly say the toggle takes effect after restart.
- Keep OSD wording user-facing: say `Cheats`, `Show FPS`, `Restart needed`, or `Needs first boot`; avoid database/internal words in the menu.

## Cheat Work

- Support offline single-player cheats only.
- Do not help bypass DRM, anti-cheat, or online/multiplayer protections.
- Bundled Aldos/Artemis source lives under `app/src/main/assets/cheats`.
- Bundled SQLite cheat database lives at `app/src/main/assets/cheats/cheats.db`; regenerate it with `python tools/build_cheat_db.py` after changing bundled NCL/imported patch assets.
- Chidreams/RPCS3-ready imported patches live under `app/src/main/assets/cheats/chidreams` and are stored in `cheats.db` as `rpcs3_patch` entries.
- Converted test fixtures live under `app/src/test/resources/cheats/converted`.
- RPCSX/RPCS3 patches require a learned PPU hash; boot a game once, close it, then install fixed-write cheats.
- RPCS3-ready `rpcs3_patch` entries already include PPU hashes and can be installed without the Artemis conversion step.
- AoB cheats are parsed and counted as risky, but should not be installed until native byte validation/scanning exists.

## Recommended Game Settings

- Bundled database: `app/src/main/assets/config/config_database.dat`.
- Current source endpoint: `https://api.rpcs3.net/config/?api=v1`.
- The snapshot is RPCS3-style JSON: `games[TITLEID].config` contains a YAML config snippet.
- Android-side manager: `app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt`.
- The app seeds and reads a writable local cache at `config/GuiConfigs/config_database.dat` under the RPCSX root so a future/core-side config database reader can find the familiar upstream location.
- Preserve a valid local cache when it is newer than or equal to the bundled APK snapshot; do not stomp refreshed cache data during app startup.
- The game detail card has a refresh icon that downloads `https://api.rpcs3.net/config/?api=v1` into the local cache. Startup should stay offline-friendly and only seed/fallback to the bundled snapshot.
- The game detail screen shows this as `Recommended Settings`, not as database jargon.
- Managed per-game configs are written to `config/custom_configs/config_TITLEID.yml` with the `# RPCSX_THOR_AUTO_SETTINGS` header.
- Never overwrite an existing custom config unless it has the managed header. User-created custom configs win.
- Boot flow applies the recommended config before launch only when the game has a title-ID match and the user has not turned the switch off for that game.

## Per-Game Cache Workflow

- Android-side cache status lives at `app/src/main/java/net/rpcsx/performance/GameCacheRepository.kt`.
- Game detail reads `cache/cache/TITLEID` under `RPCSX.rootDirectory`, counts PPU/SPU/shader entries, shows cache size, and exposes refresh/clear controls.
- RPCSX/RPCS3 stores RSX shader cache below the PPU cache path (`.../ppu-*/shaders_cache/`), so the same per-game compiled-cache root must cover PPU, SPU, and shaders.
- Compiled-cache storage selection lives at `app/src/main/java/net/rpcsx/performance/CacheStorageManager.kt` and is exposed from Settings as `Compiled Cache Storage`.
- The core still expects `RPCSX.rootDirectory/cache/cache`; SD-card selection redirects that app-owned compiled-cache path with a symlink to the selected app-owned external-files directory, covering PPU/SPU/shader cache together.
- Do not offer arbitrary SAF folders for emulator cache until the native core supports URI/document access or a stable cache-directory setting. App-owned storage roots are the safe selectable locations.
- Switching compiled-cache storage can migrate existing cache data and should warn users that SD card cache may be slower and large moves can take minutes.
- The native wrapper has an optional `_rpcsx_preparePpuCache` hook surfaced as `RPCSX.supportsPpuCachePreparation()` and `RPCSX.preparePpuCache(...)`.
- The bundled source-built Thor core exposes `_rpcsx_preparePpuCache`; downloaded/older external cores may still lack it, so keep `supportsPpuCachePreparation()` as the UI gate.
- Do not call private C++ internals like `Emulator::BootGame` or `ppu_precompile` across the wrapper boundary unless the core intentionally exports a stable C ABI.
- Library delete now clears title-ID cache when a title ID is known; keep ISO/file-name fallback for entries without metadata.

## Thor Variant Notes

The active device is Thor Max, but Base, Pro, and Max share the same CPU/GPU performance target:

| Variant | CPU/GPU | RAM | Storage | App strategy |
| --- | --- | ---: | ---: | --- |
| Base | Snapdragon 8 Gen 2 / Adreno 740 | 8 GB LPDDR5X | 128 GB UFS 4.0 | Same CPU/GPU presets, smaller cache budget, avoid memory-hungry global views. |
| Pro | Snapdragon 8 Gen 2 / Adreno 740 | 12 GB LPDDR5X | 256 GB UFS 4.0 | Default comfort target for testing. |
| Max | Snapdragon 8 Gen 2 / Adreno 740 | 16 GB LPDDR5X | 1 TB UFS 4.0 | Active proof device; more cache/library/logging headroom; do not assume faster PPU compile or make Max-only memory behavior the default. |

- Treat Base as the memory floor for public presets, Pro as the comfort target, and Max as the fastest lab/truth device for this project. If a cache, preload, shader, or logging experiment is expected to exceed Base headroom, mark it `max-only` or `pro-max` in the experiment record before testing.
- Thor Lite is Snapdragon 865 / Adreno 650 and is not the PS3 performance target for this fork. Do not apply Snapdragon 8 Gen 2 affinity masks to Lite.

## Thor CPU Notes

The connected AYN Thor reports board/platform `kalama` and this CPU part layout:

- CPUs `0-2`: Cortex-A510, part `0xd46`, mask `0x07`
- CPUs `3-4`: Cortex-A715, part `0xd4d`, mask `0x18`
- CPUs `5-6`: Cortex-A710, part `0xd47`, mask `0x60`
- CPU `7`: Cortex-X3, part `0xd4e`, mask `0x80`
- Heavy work mask for performance plus prime cores: CPUs `3-7`, mask `0xF8`

Use detected topology for presets. Do not assume every Snapdragon 8 Gen 2 device orders logical CPUs the same way.

## Thor Optimization Notes

- Already cleaned up Android-side hotspots: folder scan queues use `ArrayDeque`, URI file copy uses a larger stream buffer, ISO metadata avoids duplicate directory parsing, patch status file checks are cached, and `games.json` saves are debounced.
- Current Thor compile preset lives at `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`.
- The preset is applied on AYN/Thor/kalama targets: `Max LLVM Compile Threads=2`, `LLVM Precompilation=false`, `SPU Cache=true`, `SPU Decoder=Recompiler (LLVM)`, `Use LLVM CPU=cortex-a78`, native scheduler enabled when affinity succeeds, and on-disk shader cache enabled.
- Do not reintroduce an Android startup override that writes `Use LLVM CPU = cortex-a34`; that silently downgrades Thor JIT codegen and can undo the profile on later launches. Do not let this vendored LLVM use `cortex-a510`, `cortex-a710`, `cortex-a715`, or `cortex-x3` on Thor unless Android reports SVE: those Armv9 CPU definitions enable SVE/SVE2 in LLVM while Snapdragon 8 Gen 2 reports dotprod/i8mm/bf16 but not SVE.
- Do not allow Thor per-game recommended configs to select `SPU Decoder: Recompiler (ASMJIT)`. ASMJIT is an x64 SPU backend; ARM64 should use the LLVM SPU recompiler.
- Native wrapper affinity helper: `RPCSX.setProcessAffinityMask(0xF8)` pins current app/native threads to Thor CPUs `3-7` where Android permits it. MainActivity applies it before core initialization so early native threads can inherit the performance-core mask. This is a first-pass compile relief, not a replacement for native PPU/SPU/RSX per-class affinity.
- The first `Thor Feature Doctor` slice lives in `_rpcsx_systemInfo()` inside `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`; the existing System Info dialog now reports configured LLVM CPU, fallback CPU, AArch64 per-core names, and Android HWCAP/HWCAP2 feature flags.
- Custom GPU driver UI lives at `app/src/main/java/net/rpcsx/ui/drivers/GpuDriversScreen.kt`.
- Curated GPU driver channels live in `app/src/main/java/net/rpcsx/ui/channels/UpdateChannelsScreen.kt`; keep K11MCH1/Kimchi first, StevenMXZ experimental, and CI builds clearly marked risky.
- Thor Base/Pro/Max are Adreno 740. Prefer A6xx/A7xx Turnip packages when testing custom drivers, keep `Default` as fallback, and label A8xx/Gen8 packages as not for Thor.
- On-screen controls preference lives in `ControllerOverlayPrefs`; Thor/AYN/kalama targets default hidden, non-Thor devices default visible.
- Sixaxis motion preference lives in `SixaxisMotionPrefs`, Android sensor capture lives in `SixaxisMotionController`, and the JNI wrapper looks for `_rpcsx_overlayPadMotionData`. Current downloaded cores may not export it; keep the matching core patch in `core-patches/` until core builds include it.
- Next low-risk Android work: cache cheat badge lookups per game title ID, add stale-cache/core-version labeling, and keep heavy global cheat expansion off Base unless requested.
- Next native/core work: benchmark/iterate the Thor PPU/SPU/RSX affinity split, add authoritative cache status, and continue SPU common recompiler parity. UI-only changes cannot truly pin native compile threads.
- Default PPU compile experiment for Base/Pro/Max: Max LLVM compile threads `2`, full PPU precompile off, heavy mask `0xF8`; benchmark higher worker counts only as an opt-in cache-builder experiment with memory logs running.
- 2026-05-12 crash note: the rtime-keyed reservation notifier port from `d638a9ec2` was backed out after Eternal Sonata hit a native `SIGBUS BUS_ADRALN` in `PPU[0x1000000]` with PC/LR `0xd0020d77` and repeated `MemoryRead: PC is 0x0` logs. Capture lives at `debug-captures/20260512-233228-game-crash`. Prefs confirmed the APK bundled core was loaded, not the stale `files/librpcsx-android_armv8-a_v20251011-e27926d.so`. Re-port this area in smaller gates, starting with detection/logging before changing wait/notify behavior again.

## Current Cheat/Test Fixture

- Odin Sphere Leifthrasir BLUS31601 has a conversion fixture.
- Fixture source: `app/src/main/assets/cheats/ncl/1417_Odin Sphere Leifthrasir BLUS31601 v01.01 av01.00.ncl`
- Converted output:
  - `app/src/test/resources/cheats/converted/odin_sphere_leifthrasir_blus31601_patch.yml`
  - `app/src/test/resources/cheats/converted/odin_sphere_leifthrasir_blus31601_patch_config.yml`
