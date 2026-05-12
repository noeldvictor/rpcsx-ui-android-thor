# 2026-05-12 RPCS3 ARM64 Linux Core Rework

semantic_name: rpcs3-arm64-linux-core-rework
target: AYN Thor Base/Pro/Max, Snapdragon 8 Gen 2, Android native core
reference: RPCS3 ARM64 Linux/Rocknix behavior

## Decision

Stop treating Android PS3 forks as the core-performance reference. Keep this app's Android UI, JNI wrapper, storage handling, Thor presets, and handheld UX, but rework the vendored native core toward the upstream RPCS3 ARM64 Linux path in small buildable slices.

The reference stack is:

1. Upstream RPCS3 ARM64 Linux/Rocknix behavior.
2. Local Android/Thor runtime constraints.
3. Android PS3 forks only as secondary clues.

## Working Rule

Each import must answer four questions:

1. What upstream ARM64 behavior are we matching?
2. What Android/Thor adaptation is required?
3. How does the built app prove the path activates?
4. What cold/warm Thor benchmark or boot test checks for regressions?

## Imported Slices

### Slice 1: ARM64 Feature Gate Parity

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/util/sysinfo.hpp`
- `app/src/main/cpp/rpcsx/rpcs3/util/sysinfo.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp`
- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`

What changed:

- Added upstream-shaped `utils::has_neon()`, `utils::has_sha3()`, `utils::has_dotprod()`, `utils::has_sve()`, and `utils::has_sve2()` gates.
- Kept Android/Linux HWCAP as the source of truth on Thor.
- Routed Android JIT SVE sanitization through the shared `utils::has_sve()` gate instead of a local helper.
- Added Thor Feature Doctor output for the core's own ARM64 feature-gate view.

Why it matters:

- Dotprod, I8MM/BF16-class future work, and SVE guardrails need one shared source of truth.
- Thor reports dotprod/I8MM/BF16-class features but not SVE; the fork must avoid LLVM CPU targets that imply SVE unless Android really exposes it.

### Slice 2: AArch64 LLVM Target Attributes

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp`

What changed:

- Ported upstream-style AArch64 LLVM target attributes for `+/-sha3`, `+/-dotprod`, `+/-sve`, and `+/-sve2`.
- Kept each attribute tied to the shared `utils::has_*()` HWCAP gates from Slice 1.
- Changed the unknown Android ARM64 fallback CPU from `cortex-a34` to upstream's `cortex-a78`.

Why it matters:

- The SPU dot-product opcode import generates AArch64 dot-product IR; LLVM also needs `+dotprod` on the target machine so runtime lowering matches the host.
- Explicit `-sve`/`-sve2` attributes preserve the Thor guardrail when LLVM CPU names such as Cortex-X3/A715/A710/A510 imply SVE in bundled LLVM but Android does not expose SVE.
- The `cortex-a78` fallback keeps unknown modern ARM64 devices on a performant armv8.2-class baseline instead of silently falling back to tiny-core codegen.

### Slice 3: ARM64 JIT Telemetry

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp`
- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`

What changed:

- Added a deduped JIT notice for each unique AArch64 LLVM target setup:
  `LLVM AArch64 target: cpu=... triple=... attrs=... flags=... link-table=...`
- Added `LLVM ARM64 target attrs` to Thor Feature Doctor so the same attribute view is available from System Info.

Why it matters:

- Later SPU/PPU imports need proof that the runtime is using the intended CPU and target attributes on Thor.
- This makes `+dotprod`, `-sve`, and `-sve2` visible beside the existing HWCAP/core-gate evidence.

### Slice 4: ARM64 SPU Decoder Guardrail

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp`
- `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`
- `app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt`

What changed:

- Restored the upstream ARM64 assumption that SPU ASMJIT is not an ARM64 backend.
- On ARM64, an ASMJIT SPU decoder request now falls back to the LLVM SPU recompiler with a warning instead of trying to run the x64 ASMJIT path.
- The Thor startup profile now explicitly sets `SPU Decoder` to `Recompiler (LLVM)`.
- Thor-managed per-game recommended configs rewrite `SPU Decoder: Recompiler (ASMJIT)` to `SPU Decoder: Recompiler (LLVM)`.

Why it matters:

- The upstream RPCS3 recommended settings database can include x64-oriented `Recompiler (ASMJIT)` SPU profiles.
- Android/Thor should keep the app shell and database feature, but ARM64 must stay on LLVM SPU codegen so dotprod and future ARM64 lowering work remains active.

### Slice 5: Android PPU Cache Preparation Export

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`

What changed:

- Exported `_rpcsx_preparePpuCache` from the Android core so the existing JNI wrapper and cache UI can detect real support.
- Reused the existing native PPU compilation flow for direct background cache preparation.
- Cache preparation now resolves a game root to its bootable `EBOOT.BIN`, refuses to run while a game is active, reports failures through the existing progress channel, and preserves the Java-provided title ID as a fallback before analysis.

Why it matters:

- The UI already had a cache preparation button, but the bundled source core did not export the native symbol, so Thor users were pushed back to cold-boot compilation.
- This makes warm-cache testing and per-slice benchmarking practical without requiring a full gameplay boot every time.

### Slice 6: Thor Native Scheduler Affinity Split

Status: implemented locally and verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/util/Thread.cpp`
- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`
- `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`

What changed:

- Thor startup defaults now enable `Thread Scheduler Mode: RPCS3 Scheduler` when Android performance-core affinity succeeds.
- The Thor affinity preset maps CPU3 as shared/general, CPU4 to PPU, CPU5-CPU6 to SPU, and CPU7 to RSX.
- Android `thread_ctrl::get_affinity_mask()` now intersects configured class masks with the thread's current runtime affinity, so the Java-side `0xF8` performance-core mask prevents CPU0-CPU2 from leaking back into PPU/SPU/RSX masks.
- Thor Feature Doctor now reports the native scheduler mode and effective PPU/SPU/RSX masks.

Why it matters:

- The previous `0xF8` process-wide pin kept existing app/native threads on performance cores, but it did not separate emulator thread classes.
- This starts moving toward RPCS3-style native scheduling on Thor: PPU, SPU, and RSX work get distinct preferred cores while still staying inside Android's permitted performance-core set.

### Slice 7: SPU Reservation Busy-Wait Gate

Status: implemented locally, verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`, installed to Thor, and confirmed by the startup profile log.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`
- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`
- `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`

What changed:

- Added upstream's hidden `SPU Reservation Busy Waiting Enabled` gate to the local core config.
- Removed the local `__linux__` hard-disable that forced `reservation_busy_waiting = false` on Android/Linux.
- Thor profile v8 enables SPU reservation busy-waiting and sets the reservation busy-wait percentage to 100.
- Thor Feature Doctor now reports whether the gate is enabled and the active percentage.
- On-device startup confirmed `changed=[..., SPU Reservation Busy Waiting, SPU Reservation Busy Waiting Percentage, ...] failed=[]`.

Why it matters:

- Eternal Sonata's logs show heavy `sys_spu_thread_group_start` / `join` churn, which points directly at SPURS/SPU reservation waits.
- Before this slice, the existing percentage setting could not help on Android because the Linux branch bypassed it completely.
- This is still a bounded upstream port: it unlocks the upstream-style configurable spin path without yet copying the larger newer upstream EventStat optimizer.

### Slice 8: SPU GETLLAR Spin Predictor Parity

Status: implemented locally, verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`, installed to Thor, and launch-smoke-tested.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`

What changed:

- Ported upstream's shared `evaluate_spin_optimization(...)` helper for SPU wait-history prediction.
- Replaced the older local four-entry GETLLAR predictor math with the shared helper.
- Added upstream `last_getllar_lsa` tracking.
- Added upstream GETLLAR validation checks so changing LSAs and likely stack-output buffers reset the spin classifier instead of forcing a busy-wait.

Why it matters:

- Slice 7 allows Thor to busy-wait SPU reservation loops again; this slice makes the GETLLAR side of that decision closer to upstream and less likely to spin on non-looping SPU code.
- It was the low-risk stepping stone for the larger `SPU_RdEventStat` event-history optimizer imported in Slice 9.

### Slice 9: SPU RdEventStat Reservation History Optimizer

Status: implemented locally, verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`, installed to Thor, and launch-smoke-tested.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`

What changed:

- Added upstream-style `eventstat_*` state fields and a 16-entry `eventstat_wait_time` table.
- Changed `SPU_RdEventStat` from a one-shot random busy-wait decision to a history-based predictor using `evaluate_spin_optimization(...)`.
- Added the upstream timeout fallback so busy-waiting switches back to OS wait when an LR wait is not resolving quickly.
- Added a single reservation-data checking thread gate for high-thread-count cases.
- Preserved the local Android `vm::reservation_notifier_begin_wait(...)` API instead of copying upstream's newer pair-return notifier contract.

Why it matters:

- Eternal Sonata's repeated SPU thread-group start/join pattern is exactly the class of SPURS-heavy workload this upstream path targets.
- The previous local Android path either slept through reservation waits or, after Slice 7, could spin too bluntly. This slice makes the decision adaptive and time-bounded.

### Slice 10: Reservation-Time-Aware VM Notifiers Attempt

Status: attempted, crash-reproduced, and rolled back. The current stable Thor APK installed at `2026-05-12 16:47:58` restores the older address-only reservation notifier API while keeping the earlier proven ARM64/SPU performance slices.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Memory/vm_reservation.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Memory/vm.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUThread.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`
- `app/src/main/cpp/rpcsx/rpcsx/cpu/cell/ppu/include/rx/cpu/cell/ppu/PPUContext.hpp`
- `app/src/main/cpp/rpcsx/kernel/cellos/src/lv2.cpp`
- `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_spu.cpp`

What was attempted:

- Reworked VM reservation notifier buckets to include reservation time, matching the upstream idea that waiters should be grouped by address and nearby reservation epoch.
- Updated PPU, SPU, CPU-exit, lv2 sleep/awake, and SPU thread-group termination paths to pass reservation time into waiter-count and notify calls.
- Added postponed notification support for PPU/lv2 paths without falling back to the previous address-only bucket.
- Kept the Android core's local threading and kernel wrappers, but removed the old one-argument notifier API from vendored call sites.

Crash notes:

- The first build with rtime-aware notifiers plus the SPU PUTLLC/store parity attempt crashed BLUS30161 after SPU runtime build.
- The first hotfix backed out the PUTLLC/store shortcuts only, but the same crash signature persisted.
- Both captures pointed at a deterministic native `SIGBUS BUS_ADRALN` in `PPU[0x1000000]`, with PC/fault address `0xd0020d77`.
- Because the crash survived the PUTLLC-only rollback, the rtime-aware notifier integration is now the stronger suspect than the partial-store shortcut by itself.

Why it still matters:

- The earlier Android path could over-wake unrelated waiters or miss the intended reservation window when SPURS-heavy code churned reservations quickly.
- Eternal Sonata's slow path still points at SPU/SPURS scheduling, so this upstream runtime mechanic needs to be understood before more aggressive spin or recompiler work.
- This idea is still a performance-quality target, but it needs to return behind a feature gate and with logs for reservation address, rtime, waiter bucket/index, wait flag, waiter count, CPU thread, and GETLLAR/PUTLLC loop identity before wakeup behavior changes.

### Slice 11: SPU PUTLLC And 128-Byte Store Parity Attempt

Status: attempted, hotfixed out, and left out of the current stable rollback APK installed at `2026-05-12 16:47:58`.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`

What changed:

- Tried the unchanged-data PUTLLC reservation update check, single-16-byte-lane compare-exchange under the writer lock, and same-data `do_cell_atomic_128_store(...)` early exit.
- Preserved the local Android non-RTM page-fault probe in `do_putllc`; the direct upstream `rx::trigger_write_page_fault(vm::base(addr))` form currently trips a Clang sign-compare warning-as-error in this Android build context.
- After user repro, the first hotfix backed out the new single-lane compare-exchange and same-data atomic-store early exit while leaving the rtime notifier active.
- After the same crash persisted, the current rollback keeps these shortcuts out and also restores the older address-only reservation notifier API.

Crash notes:

- BLUS30161 crashed repeatedly after the attempted slice, each time in `PPU[0x1000000]`.
- Tombstone/logcat showed `SIGBUS`, `BUS_ADRALN`, and PC/fault address `0xd0020d77`.
- RPCSX log reached SPU runtime build completion, then the PPU thread jumped to the same unaligned address.
- Since the same signature persisted after the PUTLLC/store-only hotfix, this shortcut is not proven as the sole cause. Re-test it later only after the notifier path has dedicated instrumentation.

Why it still matters:

- PUTLLC/GETLLAR loops are a core SPU synchronization path. The previous imports improved the wait decision; a safe version of this slice should reduce avoidable heavyweight writes and narrow some contended writeback cases.
- This must come back only with instrumentation: log the address, reservation time, lane index, old/new hashes, and whether the line is SPURS/lv2-sensitive before allowing any partial-line shortcut on Android.

### SPU Recompiler Parity Notes

The first pass through `SPULLVMRecompiler.cpp` found only a few safe isolated opcode/codegen hunks after the dotprod port. Slice 12 landed the compatible pieces; the rest is still broader analyzer work:

- `ROTQBY`, `ROTQMBY`, and `SHLQBY` already match upstream's ARM64-safe shape.
- `AArch64ASM`, `AArch64JIT`, and `AArch64Signal` are mostly formatting/path-local differences in this checkout.
- The remaining `SPUCommonRecompiler.cpp` / `SPULLVMRecompiler.cpp` differences are broad analyzer, reduced-loop, helper, and LLVM-API changes. Treat them as a dedicated slice, not as a blind copy job.

### Slice 12: Refreshed Upstream SPU/RSX Safe Parity Pass

Status: implemented locally, verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`, installed to Thor, and launcher-smoke-tested. Thor package `net.rpcsx.easy` last updated at `2026-05-12 17:23:24`.

Upstream checkpoint:

- Refreshed `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` from `cd7cb1c` to `origin/master` at `021f16f`.
- New commits since the prior checkpoint did not include direct ARM64/SPU/JIT work, but did include a small RSX decoder correctness fix.

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_decode.h`

What changed:

- Ported upstream SPU LLVM address reuse for `LQX` / `STQX`, reducing redundant address work in generated SPU code where the local structure allowed it.
- Ported compatible `CEQI` / `CEQHI` compare-negation peepholes. The subpattern that depends on upstream's newer reduced-loop block-wide store elimination remains default-disabled until the full reduced-loop migration lands.
- Ported SPU channel wait/occupy bit separation and stopped-wait cleanup so waiters do not share the same bit for two states.
- Removed RCHCNT loop handling for `SPU_WrOutMbox` and `SPU_WrOutIntrMbox`, matching the later upstream cleanup after the write-channel looping fix.
- Ported upstream `NV309E_SET_FORMAT` width/height decode fix for RSX correctness.

Why it matters:

- These are small, buildable upstream parity pieces that touch SPU generated-code quality and synchronization correctness without reopening the crashy reservation-time notifier path.
- They will not magically fix Eternal Sonata alone. The next large performance candidate is still upstream's SPU reduced-loop analyzer/emitter series.

Reduced-loop note:

- Direct application of upstream reduced-loop commits failed against this vendored core because they require coordinated changes across `SPUAnalyser.h`, `SPUOpcodes.h`, `SPURecompiler.h`, `SPUCommonRecompiler.cpp`, `SPULLVMRecompiler.cpp`, `SPUThread.cpp`, and `CPUTranslator.h`.
- Treat reduced-loop as the next dedicated slice, gated and tested incrementally. Relevant upstream commits include `a863e94`, `2e4ee9c`, `37a07ae`, `619fe7b`, `02eb549`, plus the later analyzer fixes.

### Slice 13: LLVM Bitcast Reuse And SPU Alias Metadata

Status: implemented locally, verified with `:app:externalNativeBuildDebug` and `:app:assembleDebug`, installed to Thor, and launcher-smoke-tested. Thor package `net.rpcsx.easy` last updated at `2026-05-12 17:43:51`.

Upstream references:

- `9a0a5a1` (`LLVM: Try to reuse BitCasts`)
- `fb19424` (`fix LLVM assert in use_begin`)
- `619fe7b` (`SPU LLVM: Classify SPU memory and context memory instructions`)

Files:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`

What changed:

- `cpu_translator::bitcast(...)` now returns the original value when the type already matches, walks back through existing bitcasts to the source value, and reuses an existing same-block bitcast when one already has the requested type.
- `cpu_translator::erase_stores(...)` now follows upstream's safer use-list iteration shape, including the LLVM 21+ `hasUseList()` guards for future toolchain movement.
- SPU LLVM now attaches separate alias/noalias metadata to SPU local-storage memory operations and SPU thread-context register loads/stores.
- SPU context register stores now use the shared `bitcast(...)` helper instead of always emitting a fresh raw LLVM bitcast.

Why it matters:

- This reduces redundant LLVM IR and gives optimization passes clearer facts about SPU LS memory versus emulator context memory.
- It is a performance/codegen-quality import rather than a compatibility hammer, so Eternal Sonata should be tested after clearing SPU cache and letting the title rebuild its SPU modules.

### PPU AArch64 Gateway Notes

The first PPU pass also does not justify a blind upstream copy:

- Local `PPUTranslator.cpp` already installs the AArch64 `GHC_frame_preservation_pass` for PPU functions.
- Local `PPUThread.cpp` has an Android/RPCSX-adapted AArch64 gateway and packed exec-entry format that stores the segment in the high bits of the call target instead of using upstream's older separate segment table shape.
- The diff is dominated by local ABI/layout, cache-memory pressure, and LLVM-version adaptations. Any future PPU port needs a focused design around exec-table format, far-jump patching, and Thor memory limits.

## Next Port Slices

1. SPU reduced-loop analyzer/LLVM port:
   - `Emu/Cell/SPUAnalyser.h`
   - `Emu/Cell/SPUOpcodes.h`
   - `Emu/Cell/SPURecompiler.h`
   - `Emu/Cell/SPUCommonRecompiler.cpp`
   - `Emu/Cell/SPULLVMRecompiler.cpp`
   - `Emu/Cell/SPUThread.cpp`
   - `Emu/CPU/CPUTranslator.h`
   - Focus on the upstream reduced-loop series, not a blind whole-file copy. Add a config/telemetry gate if the emitter compiles but needs gameplay validation on Eternal Sonata.

2. AArch64 backend parity audit:
   - `Emu/CPU/Backends/AArch64/AArch64ASM.*`
   - `Emu/CPU/Backends/AArch64/AArch64Common.*`
   - `Emu/CPU/Backends/AArch64/AArch64JIT.*`
   - `Emu/CPU/Backends/AArch64/AArch64Signal.*`
   - First quick diff: `AArch64ASM`, `AArch64JIT`, and `AArch64Signal` are mostly formatting/path-local differences. `AArch64Common` is intentionally ahead locally for more CPU IDs, including Thor-relevant A510/A715/X3 names with blank feature strings so the Android SVE guard can keep LLVM on a safe fallback.

3. PPU LLVM/GHC frame preservation audit:
   - `Emu/Cell/PPUTranslator.cpp`
   - `Emu/Cell/PPUThread.cpp`
   - AArch64 gateway/tail-call behavior

4. RSX non-x86 fallback audit:
   - `Emu/RSX/Common/BufferUtils.cpp`
   - `Emu/RSX/RSXTexture.cpp`
   - `Emu/RSX/Program/ProgramStateCache.cpp`

5. Cache/runtime parity:
   - Cache versioning must include core/JIT feature gates.
   - Warm-cache tests should compare Android RPCSX against RPCS3 ARM64 Linux/Rocknix on the same Thor where possible.

## Thor Validation Checklist

- System Info shows `Core ARM64 gates: NEON=yes ... DOTPROD=yes ... SVE=no ...` on Snapdragon 8 Gen 2 Thor if Android exposes those HWCAP bits.
- Logcat shows `AArch64 dot-product SPU fast paths enabled.` when DOTPROD activates.
- First boot does not reintroduce full PPU precompile OOM behavior.
- Warm-cache SPU-heavy titles are compared before/after each imported slice.
