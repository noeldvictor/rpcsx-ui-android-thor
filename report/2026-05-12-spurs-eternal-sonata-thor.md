# SPURS Performance Report: Eternal Sonata on AYN Thor

Date: 2026-05-12
Target: AYN Thor, Snapdragon 8 Gen 2 / Adreno 740, RPCSX Android source-built core
Game focus: Eternal Sonata `BLUS30161`

## Executive Summary

The current Eternal Sonata bottleneck is not a boot blocker or an Android low-memory kill. The 2026-05-12 live capture showed a classic SPURS/RSX contention profile: `rsx::thread` was hot, six SPU threads were also hot, and the PPU was hammering timer/semaphore/event/SPU-group syscalls while gameplay sat around 10-13 FPS.

The first fix should be to reduce avoidable overhead before a risky compiler rewrite:

- Stop hot-path warning spam from `cellSysutilGetSystemParamInt`.
- Disable PPU syscall usage stats by default on Android and only enable them for short diagnostic captures.
- Give Codex an ADB logging switch so FPS tests run quiet and crash captures run verbose.
- Cap Thor SPURS execution to 4 active SPURS threads by default and in the Eternal Sonata Thor profile, because our current affinity split mostly gives SPU work two cores while the game can expose six runnable SPU workers.

The bigger upstream port remains RPCS3's SPU reduced-loop series. That is the real next major SPURS compiler win, but it is not a clean cherry-pick: it moves analyzer/recompiler data structures and must be landed as a gated, buildable slice.

## Live Capture Evidence

Capture folder:

`debug-captures/20260512-174918-eternal-sonata-10fps-stream`

Observed app state:

- App remained alive in `RPCSXActivity`.
- No obvious crash, tombstone, OOM, or Android low-memory kill during the sample.
- Memory was high but not fatal for the sample: roughly 2.5 GB RSS, graphics around 1.33 GB, native heap around 580 MB, 92 threads.

Hot thread sample:

- `rsx::thread`: about 67.6% CPU
- `SPU[0x4000100]`: about 50.0%
- `SPU[0x3000100]`: about 44.1%
- `SPU[0x2000100]`: about 44.1%
- `SPU[0x1000100]`: about 38.2%
- `SPU[0x0000100]`: about 32.3%
- `SPU[0x0000200]`: about 32.3%
- PPU threads also active, with the highest PPU around 20.5%.

Syscall pressure from the RPCSX log:

- `sys_timer_usleep`: 515,582
- `sys_semaphore_wait`: 91,642
- `sys_semaphore_post`: 91,639
- `sys_event_queue_receive`: 45,706
- `sys_spu_thread_group_start`: 20,528
- `sys_spu_thread_group_join`: 20,528
- `_sys_lwmutex_lock`: 18,259
- `_sys_lwmutex_unlock`: 18,251
- `_sys_lwcond_signal`: 18,251
- `_sys_lwcond_queue_wait`: 18,003

There was also repeated warning-level spam:

- `cellSysutilGetSystemParamInt(id=0x112(ID_ENTER_BUTTON_ASSIGN), value=...)`

That call is normal game polling, not actionable warning signal. Warning-level logging here is pure overhead during gameplay.

## What SPURS Is Doing Here

SPURS is Sony's SPU task/runtime system. Games use it to keep several SPU workers available, park idle workers, launch SPU thread groups, and synchronize task transitions through SPU local store state, MFC atomics, event status, semaphores, event queues, and PPU-side waits.

On desktop RPCS3, SPURS can burn a lot of host CPU but there are usually enough big cores and enough thermal headroom to hide some of the waste. On Thor:

- The Java/native profile pins the process to the Snapdragon performance cores.
- The native scheduler currently splits CPU3 as general/shared, CPU4 as PPU, CPU5-6 as SPU, and CPU7 as RSX.
- Eternal Sonata can expose six hot SPU workers, but the scheduler mostly gives SPU work two cores.
- RSX also wants a very fast core, so letting SPURS run as if the host has spare desktop-class cores can starve RSX and PPU progress.

That makes `Max SPURS Threads` a serious handheld setting, not a cosmetic compatibility slider.

## Current Local Core Status

Already imported into this fork:

- ARM64 LLVM target attributes for SHA3/DOTPROD/SVE/SVE2 gating.
- ARM64 fallback CPU target improved from `cortex-a34` to `cortex-a78`.
- SPU ASMJIT requests rewritten/fallbacked to SPU LLVM on ARM64.
- Native scheduler/affinity import for Thor performance cores.
- SPU reservation busy-wait gate enabled on Thor.
- Upstream-style GETLLAR spin prediction.
- SPU `RdEventStat` wait history and timed busy-wait fallback.
- Safe SPU/RSX parity slice through upstream `021f16f`, including LQX/STQX address reuse, CEQI/CEQHI peepholes, channel wait/occupy cleanup, RCHCNT loop removal for write mailbox channels, and NV309E RSX decoder fix.
- CPUTranslator bitcast reuse/use-list guard and SPU alias metadata.

Not safely imported yet:

- RPCS3 SPU reduced-loop detection/emission.
- Upstream rtime-aware reservation notifier rewrite.
- PUTLLC / partial reservation-store parity work that previously caused deterministic SIGBUS on Eternal Sonata.

## Fix Slice Landed From This Report

This slice makes the Thor runtime less self-sabotaging during FPS testing:

- `cellSysutilGetSystemParamInt` logging is demoted from warning to trace.
- Android PPU syscall stats are disabled by default and gated by `debug.rpcsx.thor.syscall_stats`.
- Android RPCS3 logcat output is gated by `debug.rpcsx.thor.logcat` and `log.tag.RPCS3`.
- Added `tools/set_thor_logging.ps1`:
  - `Quiet`: logcat off, syscall stats off, `log.tag.RPCS3=S`
  - `Normal`: logcat info, syscall stats off
  - `Verbose`: logcat verbose, syscall stats on
  - `Status`: print current props
- Thor compile profile bumped to v9 and now sets `Core -> Max SPURS Threads = 4`.
- Eternal Sonata `BLUS30161` Thor override now sets:
  - `Core -> Max SPURS Threads = 4`
  - `Core -> SPU Reservation Busy Waiting Enabled = true`
  - `Core -> SPU Reservation Busy Waiting Percentage = 100`
  - `Core -> Accurate SPU Reservations = false`
  - `Core -> SPU Verification = false`
  - `Core -> Sleep Timers Accuracy = As Host`
  - `Video -> Frame limit = 30`
  - `Video -> Accurate ZCULL stats = false`
  - `Video -> Relaxed ZCULL Sync = true`
  - `Video -> Multithreaded RSX = true`

## Follow-Up: Stale Per-Game Config Found

The first retest still showed 10-13 FPS because the active device file `config/custom_configs/config_BLUS30161.yml` was an old full custom config, not the managed override. It masked the new Thor/global profile with slow values:

- `Thread Scheduler Mode: Operating System`
- `SPU Reservation Busy Waiting Percentage: 0`
- `Max SPURS Threads: 6`
- `Accurate SPU Reservations: true`
- `SPU Verification: true`
- `Accurate ZCULL stats: true`
- `Multithreaded RSX: false`

This means the first retest did not actually measure the intended SPURS 4 / busy-wait / reduced-accuracy profile. Replace that stale custom config with `tools/push_eternal_sonata_thor_profile.ps1`, relaunch the game, then retest FPS.

## Why Cap SPURS At 4 First

This is a controlled first step:

- 6 active SPURS threads are too many for the current Thor SPU affinity mask.
- 4 keeps multiple SPU workers available but reduces oversubscription and wakeup churn.
- The setting already exists upstream and is exposed in the Home Menu, so the behavior is not a new custom scheduler invention.
- Many RPCS3 game profiles already use `Max SPURS Threads: 3` or `4` for problematic titles.

If 4 improves frame pacing but still leaves RSX starved, test 3. If 4 causes task starvation, audio crackle, or soft hangs, test 5.

## ADB Logging Workflow

For FPS tests:

```powershell
.\tools\set_thor_logging.ps1 -Mode Quiet
```

For ordinary crash/boot repro:

```powershell
.\tools\set_thor_logging.ps1 -Mode Normal
```

For short syscall-heavy diagnostic windows:

```powershell
.\tools\set_thor_logging.ps1 -Mode Verbose
```

Check state:

```powershell
.\tools\set_thor_logging.ps1 -Mode Status
```

Do not leave `Verbose` on while judging FPS. In this game, syscall-stat accounting and warning/logcat spam can become part of the measured slowdown.

## Upstream Reduced-Loop Port Target

Local upstream reference checkout:

`C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`

Fetched reference:

`origin/master = 021f16f`

Important upstream SPU reduced-loop commits:

- `a863e94` - `SPU: Detect reduced loop`
- `2e4ee9c` - `SPU LLVM: Implement reduced loop`
- `37a07ae` - `SPU LLVM: Optimize FM, FMA and FCGT in Reduced Loop`
- `619fe7b` - `SPU LLVM: Classify SPU memory and context memory instructions`
- `02eb549` - `SPU LLVM: Fix register updates in second block of Reduced Loop`
- `13de823` - `SPU Analyzer: Fix register origin for Reduced Loop`
- `a03a78d` - `SPU: Verify SPU Reduced loop completability`
- `80f972c` - `SPU Analyzer: Acknowledge unknown targets`
- `7d0df30` - `SPU LLVM: Fix RCHCNT write channel looping`

This is the highest-value SPURS compiler port because reduced-loop detection targets SPU wait/task loops directly. The first commit alone is large: upstream changed `SPUCommonRecompiler.cpp` by roughly 1,396 insertions and 148 deletions. Direct patching failed earlier because our vendored RPCSX tree does not have the exact same analyzer/recompiler structure.

## Reduced-Loop Port Plan

Port in four checkpoints:

1. Analyzer data model
   - Add the upstream reduced-loop descriptors and detection state.
   - Keep it compile-only and gated off until detection can be logged safely.

2. Detection-only instrumentation
   - Detect candidate reduced loops.
   - Log one-line summaries only when `debug.rpcsx.thor.spu_reduced_loop_log=1` or an equivalent config gate is added.
   - Do not change generated code yet.

3. LLVM emission
   - Port the reduced-loop LLVM lowering from `2e4ee9c`.
   - Keep a runtime kill switch so Eternal Sonata can boot with detection on but emission off if generated code miscompiles.

4. Correctness fixes
   - Add `37a07ae`, `02eb549`, `13de823`, `a03a78d`, and `80f972c`.
   - Validate register updates, unknown targets, completability checks, and SPU memory/context alias classification before enabling by default.

## Validation Matrix

After this slice:

1. Build and install APK.
2. Set logging to Quiet.
3. Boot Eternal Sonata and wait until gameplay.
4. Capture FPS, hot threads, memory, and syscall distribution.
5. Compare against the 10-13 FPS capture.
6. Test `Max SPURS Threads = 3`, `4`, and `5` if 4 is inconclusive.

Commands:

```powershell
.\gradlew.bat :app:assembleDebug
& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r app\build\outputs\apk\debug\rpcsx-thor-experiment-debug.apk
.\tools\set_thor_logging.ps1 -Mode Quiet
.\tools\start_thor_debug_stream.ps1 -Label eternal-sonata-spurs4 -PollSeconds 3
.\tools\summarize_thor_debug_stream.ps1 -Latest
.\tools\stop_thor_debug_stream.ps1 -Latest
```

## Risks

- `Max SPURS Threads = 4` can improve host scheduling but may expose game-specific timing if a title expects more SPU workers to make progress quickly.
- `Sleep Timers Accuracy = As Host` can reduce wakeup precision; keep it per-game or Thor-specific, not blindly universal for every title.
- Disabling logcat/syscall stats can hide evidence during crash repros. Use `Normal` or short `Verbose` captures when diagnosing correctness.
- Reduced-loop emission can miscompile SPU control flow if the analyzer port is incomplete. It must be feature-gated until Eternal Sonata and at least one other SPURS-heavy game survive boot and gameplay.

## Next Recommendation

Ship this cheap SPURS/logging slice first and measure. If FPS remains near 10-13 with `Max SPURS Threads = 4`, immediately start the reduced-loop port as a dedicated branchless checkpoint on `master`, with detection-only landing before LLVM emission.
