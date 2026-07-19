# Android disabled PPU syscall-statistics overhead removal

## Goal

Remove default-off diagnostic timing, atomic work, and the statistics thread from every normal Android PPU syscall while preserving syscall behavior and an explicit diagnostics build.

## Scope and safety

- Host-only implementation and verification on 2026-07-19.
- No ADB, APK install, emulator launch, thermal query, or gameplay run was performed.
- This is a code-generation/CPU-pressure candidate, not yet a measured Thor FPS or temperature result.
- Classification: `stackable-cpu-pressure`.

## Pre-change evidence

- Every valid PPU syscall called `ppu_syscall_stats_enabled()` before table dispatch even when `debug.rpcsx.thor.syscall_stats` was unset/off.
- Baseline ARM64 dispatcher `ppu_execute_syscall(ppu_thread&, u64)` was 504 bytes and executed `get_system_time()`, loaded the next-check atomic, attempted an atomic compare/exchange once per interval, loaded the enabled flag, and could read the Android property. Enabled diagnostics also performed an atomic counter increment.
- Baseline build hash `4f342u1t` retained 15 selected dispatcher/statistics/type-registration symbol lines and three statistics property/report/thread strings.
- Template registration retained the statistics thread and its 1024-counter scan/report implementation even after the dispatcher accounting branch was first folded away, so the final gate excludes the entire type registration rather than only its hot call site.

## Change

- Normal Android builds now default `RPCSX_THOR_SYSCALL_STATS=OFF`.
- In that build, `record_ppu_syscall(code)` is an always-inline empty function and disappears from the dispatcher.
- The `ppu_syscall_usage` class, named-thread registration, 1024 counters, scan/report loop, and property polling state are excluded from the normal Android artifact.
- Android diagnostics can opt the full implementation back in with `-PrpcsxThorSyscallStats=true` or `RPCSX_THOR_SYSCALL_STATS_BUILD=true` at build time, then use the existing runtime property.
- Non-Android builds retain their existing always-on syscall accounting behavior.

## Behavior contract

- No guest syscall result, argument, dispatch-table selection, invalid-code handling, logging, Apple JIT protection, wait, wake, synchronization, or timing behavior changed.
- The LLVM-legacy syscall-code selection and normal function-table call remain unchanged.
- Only optional diagnostic accounting and reporting are absent from normal Android builds.

## Verification

- `tools/test_thor_syscall_stats_build_gate.ps1`: PASS.
- Complete host-only `tools/test_thor_*.ps1` regression suite: 41/41 PASS.
- New PowerShell contract AST parse and `git diff --check`: PASS.
- Clean ARM64 RelWithDebInfo native build: PASS (`BUILD SUCCESSFUL in 12m 48s`); final incremental link: PASS (`BUILD SUCCESSFUL in 48s`).
- CMake cache records `RPCSX_THOR_SYSCALL_STATS:BOOL=OFF` alongside the prior wait-profiler and RSX-auditor gates.
- Dispatcher size fell from 504 to 316 bytes. Its linked instruction range now contains zero `get_system_time`, `__system_property_get`, `CAS`, or `LDADD` references.
- Selected dispatcher/statistics/type-registration symbols fell 15 -> 2, leaving only the two real `ppu_execute_syscall` entry points.
- Statistics property/report/thread strings fell 3 -> 0.
- The unstripped library is 67,656 bytes smaller (`1,306,222,536` -> `1,306,154,880`). This is supporting code-removal evidence, not a runtime metric.
- Thor A/B and thermal proof: pending a separate cool-device session.

## Rollback / diagnostics

Build with `-PrpcsxThorSyscallStats=true` to restore Android property-gated counting and reports. Revert the Gradle, CMake, LV2, and contract changes to remove this build gate entirely.
