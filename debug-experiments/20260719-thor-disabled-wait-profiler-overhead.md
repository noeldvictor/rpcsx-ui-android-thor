# Android disabled wait-profiler overhead removal

## Goal

Remove bookkeeping calls from Android busy-wait hot paths when the Thor wait profiler is disabled, while preserving the exact wait operation and an explicit diagnostics build path.

## Scope and safety

- Host-only implementation and verification on 2026-07-19.
- No ADB, APK install, emulator launch, thermal query, or gameplay run was performed.
- This is a code-generation/CPU-pressure candidate, not yet a measured Thor FPS or temperature result.
- Classification: `stackable-cpu-pressure`.

## Pre-change evidence

- `thor_wait::profiled_busy_wait()` always made an out-of-line call into profiler code before executing `rx::busy_wait(cycles)`, even when the runtime Android property left profiling disabled.
- There are 29 source call sites plus the function definition across the vendored RPCS3 tree.
- The prior ARM64 `util/sema.cpp.o` contained ten `R_AARCH64_CALL26` relocations to `thor_wait::profiled_busy_wait` inside the ten-iteration spin in `semaphore_base::imp_wait()`.
- The prior merged Android library retained a local `thor_wait::profiled_busy_wait` symbol.

## Change

- Android release/debug builds now default `RPCSX_THOR_WAIT_PROFILER=OFF`.
- In that default build, `profiled_busy_wait(site, cycles)` is a `FORCE_INLINE` wrapper containing only `rx::busy_wait(cycles)`.
- Diagnostic instrumentation remains available through `-PrpcsxThorWaitProfiler=true` or `RPCSX_THOR_WAIT_PROFILER_BUILD=true` at build time.
- Non-Android builds retain the existing full profiler implementation.

## Behavior contract

- Busy-wait cycles and all caller control flow remain unchanged.
- With the runtime profiler off, the removed executed work is the out-of-line profiler call plus its one-time interval/property initialization and repeated zero-interval check.
- Profiler counters, logging code/data, and the property string are also absent from the artifact; those paths were dormant rather than executing when the old runtime profiler was off.
- No title-specific or timing-sensitive behavior was added.

## Verification

- `tools/test_thor_wait_profiler_build_gate.ps1`: PASS.
- `tools/test_thor_es_frame_poll_wait.ps1`: PASS.
- `tools/test_thor_thermal_guard.ps1`: PASS.
- New PowerShell contract AST parse: PASS.
- `git diff --check`: PASS.
- ARM64 RelWithDebInfo native build: PASS (`BUILD SUCCESSFUL in 13m 12s`). The configured cache records `RPCSX_THOR_WAIT_PROFILER:BOOL=OFF`.
- New `util/sema.cpp.o` relocation/symbol/disassembly audit: PASS. Direct profiler `CALL26` relocations fell from 10 to 0, the profiler symbol is absent, and `imp_wait()` contains the inlined counter/timer/yield busy-wait loop. The RelWithDebInfo object shrank from 126,416 to 84,216 bytes; this size delta includes debug/object metadata and is supporting evidence rather than a runtime metric.
- Merged `librpcsx-android.so` symbol/string audit: PASS. Seven profiler symbols and the `debug.rpcsx.thor.wait_profiler` property string in the prior artifact fell to zero in the new artifact. The unstripped library is 24,944 bytes smaller; treat size as supporting code-removal evidence, not a performance measurement.
- Thor A/B and thermal proof: pending a separate cool-device session.

## Rollback / diagnostics

Build with `-PrpcsxThorWaitProfiler=true` to restore the profiler implementation for a diagnostic APK. Revert the three build/header changes to remove this build gate entirely.
