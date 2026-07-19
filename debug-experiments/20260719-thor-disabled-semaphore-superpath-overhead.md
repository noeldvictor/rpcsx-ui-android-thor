# Thor Disabled Semaphore-superpath Overhead

- Date: 2026-07-19
- Target: AYN Thor Android ARM64 production core
- Title focus: Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`
- Device state: untouched; no ADB, install, launch, temperature read, or game run

## Problem

The Eternal Sonata semaphore superpath was runtime-disabled by default, but a
normal Android binary still carried the full experiment and entered its hooks
from every semaphore create, destroy, wait, and post:

- title, PPU-name, and guest-CIA candidate checks;
- property/environment parsing and static initialization;
- a 64-entry fast-object cache;
- destroyed-ID and cached-ESRCH tracking;
- direct wait/post and speculative ESRCH actions;
- atomic counters plus periodic report formatting.

The prior Thor field A/B already counterproved fast mode as a speed path:

- off: about `17.43 FPS`, correct visuals;
- fast: about `17.03 FPS`, correct visuals;
- roughly `98,304` fast hits by field time, including about `57,911` direct
  waits and `40,381` direct posts.

The wrapper is genuinely hot, but bypassing it did not improve field FPS. A
normal runtime-off build therefore should not retain the experiment's checks,
cache maintenance, state, or code.

## Change

Normal Android builds now compile the experiment out completely:

- CMake option `RPCSX_THOR_SEMA_SUPERPATH` defaults to `OFF`.
- Gradle opt-in `-PrpcsxThorSemaSuperpath=true` or environment opt-in
  `RPCSX_THOR_SEMA_SUPERPATH_BUILD=true` restores the experiment build.
- Global mode/stat/cache state and all parser/fast-action/logging helpers are
  protected by the build gate.
- Create, destroy, wait, and post call sites are protected by the same gate,
  leaving no normal-Android no-op calls or mode branches.
- Desktop retains the existing environment-controlled behavior.
- Explicit diagnostic Android builds retain the existing property/environment
  runtime controls and exact fast/profile behavior.

Guest semaphore behavior is unchanged in the normal build. This removes only
a disabled, title-specific experiment that prior runtime evidence did not
promote.

## ARM64 Evidence

Committed draw-stream-gated baseline artifact:

- path hash: `6y2q5wm5`
- bytes: `1,306,000,128`
- selected `thor_es_sema` symbols: 11
- selected global cache/stat/mode/guard state: 1,524 bytes
- property/environment/action/report strings: 10
- named experiment references in affected syscall disassembly: 153

Default-off candidate artifact:

- path hash: `3m6c4qaw`
- bytes: `1,305,908,312` (`-91,816`, supporting evidence only)
- `RPCSX_THOR_SEMA_SUPERPATH:BOOL=OFF`
- selected `thor_es_sema` symbols: 0
- selected global experiment state: 0 bytes
- property/environment/action/report strings: 0
- named experiment references in affected syscall disassembly: 0

The four affected syscall symbols total `8,512 -> 6,976` bytes (`-1,536`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `sys_semaphore_create` | 2,484 | 2,156 | -328 |
| `sys_semaphore_destroy` | 1,188 | 944 | -244 |
| `sys_semaphore_wait` | 2,460 | 2,008 | -452 |
| `sys_semaphore_post` | 2,380 | 1,868 | -512 |

## Verification

- `tools/test_thor_sema_superpath_build_gate.ps1`: pass
- neighboring draw-stream structural contract: pass after recognizing the new
  independent semaphore gate
- full `tools/test_thor_*.ps1` suite with strict child exit propagation:
  `44/44` pass
- PowerShell AST parse: pass
- `git diff --check`: pass
- ARM64 RelWithDebInfo build: pass in `12m 14s`
- candidate CMake cache: semaphore superpath, draw-stream probe, SPURS probe,
  wait profiler, RSX auditor, and syscall stats all `OFF`
- prior diagnostic removals remain intact in the source-contract suite

## Decision

Bank as host-verified `stackable-cpu-pressure`. It is not a measured speed,
FPS, temperature, flicker, gameplay, or stability win. Do not enable or rerun
the behavior experiment for normal play: its prior fast-mode A/B was slightly
worse. Keep the explicit build/runtime opt-in only for targeted diagnostics.

The next runtime proof remains one independently cool, hard-temperature-
guarded Thor A/B of the accumulated production build across field,
Options/menu, and first battle. Do not heat-soak or immediately repeat it.
