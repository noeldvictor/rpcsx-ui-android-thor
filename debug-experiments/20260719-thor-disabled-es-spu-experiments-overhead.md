# Thor Disabled Eternal Sonata SPU Experiments Overhead

- Date: 2026-07-19
- Target: AYN Thor Android ARM64 production core
- Title focus: Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`
- Device state: untouched; no ADB, install, launch, temperature read, or game run

## Problem

Two coupled Eternal Sonata SPU experiment families were runtime-disabled by
default but still retained hooks in production Android's hottest SPU paths.

The DMA candidate probe entered from:

- every direct DMA transfer;
- every sampled DMA payload;
- list-transfer scope entry/exit and each handled list element;
- every SPU group start for image/signature initialization;
- SPU group join for reporting.

The GETLLAR experiment entered from each reservation operation to select:

- RSX-lock bypass behavior;
- retry-spin limit;
- busy-wait duration;
- optional retry profiling/reporting.

Runtime-off helper branches were small individually, but prior field telemetry
counted about `1,556,660` `spu_getllar` calls and large DMA traffic. This is a
high-frequency surface where dormant experiment selection does not belong in
the production binary.

Prior Thor evidence also counterproved the experimental behavior:

- DMA profile lowered the field overlay to about `15.33 FPS`.
- DMA verify hashing lowered it to about `11.13 FPS`; output mismatches were
  zero, but exact repeat hits remained zero, rejecting a replay cache.
- The clean reduced-loop / GETLLAR-off field result was `19.60 FPS`.
- GETLLAR `yield8` reached `18.45 FPS` and `norsx` reached `18.84 FPS` in the
  matched field scene.

## Change

Normal Android builds now compile both coupled experiment families out:

- CMake option `RPCSX_THOR_ES_SPU_EXPERIMENTS` defaults to `OFF`.
- Gradle opt-in `-PrpcsxThorEsSpuExperiments=true` or environment opt-in
  `RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD=true` restores both experiment bodies.
- `sys_spu.cpp` excludes DMA mode/state/hash/report helpers and guards group
  start/join collection.
- `SPUThread.cpp` replaces DMA record/payload/list helpers with compile-time
  no-ops.
- Normal GETLLAR helpers are compile-time constants: 24 retry spins, 300
  busy-wait cycles, normal RSX reservation locking, and no profiling.
- Desktop retains the existing environment-controlled behavior.
- Explicit diagnostic Android builds retain both property/environment
  controls and all profile/verify/speed modes.

The `spu_thread::es_gpu_probe` member remains in place even in the production
build. This intentionally preserves `spu_thread` layout and every later member
offset so persisted JIT native objects cannot inherit stale offsets across the
library change. The member is not accessed from the normal hot paths.

## ARM64 Evidence

Committed semaphore-gated baseline artifact:

- path hash: `3m6c4qaw`
- bytes: `1,305,908,312`
- selected `thor_es_dma` / `thor_es_getllar` symbols: 26
- selected global mode/guard/map/mutex/counter/bucket state: 5,260 bytes
- property/environment/report strings: 9
- named experiment references in affected disassembly: 85

Default-off candidate artifact:

- path hash: `161u3233`
- bytes: `1,305,654,632` (`-253,680`, supporting evidence only)
- `RPCSX_THOR_ES_SPU_EXPERIMENTS:BOOL=OFF`
- selected experiment symbols: 0
- selected global experiment state: 0 bytes
- property/environment/report strings: 0
- named experiment references in affected disassembly: 0

Five major affected symbols total `29,440 -> 23,488` bytes (`-5,952`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `sys_spu_thread_group_start` | 2,472 | 1,928 | -544 |
| `sys_spu_thread_group_join` | 2,900 | 1,396 | -1,504 |
| `spu_thread::do_dma_transfer` | 6,612 | 6,508 | -104 |
| `spu_thread::do_list_transfer` | 8,024 | 7,140 | -884 |
| `spu_thread::process_mfc_cmd` | 9,432 | 6,516 | -2,916 |

The whole-library delta is supporting evidence rather than a speed estimate.
The affected-function and reference deltas prove that the compiler folded the
normal no-op/constant helpers away.

## Verification

- `tools/test_thor_es_spu_experiments_build_gate.ps1`: pass
- full `tools/test_thor_*.ps1` suite with strict child exit propagation:
  `45/45` pass
- PowerShell AST parse: pass
- `git diff --check`: pass
- first ARM64 configuration attempt stopped before compilation when the host
  disk filled while unpacking LLVM
- only verified stale generated native hashes were removed; source, logs,
  protected files, submodules, Gradle caches, and baseline `3m6c4qaw` output
  were preserved
- clean ARM64 RelWithDebInfo retry: pass in `12m 30s`
- candidate CMake cache: SPU experiments, semaphore superpath, draw-stream
  probe, SPURS probe, wait profiler, RSX auditor, and syscall stats all `OFF`
- SPU thread layout storage remains present by source contract

## Decision

Bank as host-verified `stackable-cpu-pressure`. This has stronger hot-path
evidence than code-size-only cleanup because the removed selection hooks sat
inside field-hot DMA and reservation operations, but it is still not a
measured speed, FPS, temperature, flicker, gameplay, or stability win.

Do not enable the DMA or GETLLAR behavior experiments for normal play; both
have existing negative Thor evidence. Keep their explicit build/runtime opt-in
only for targeted diagnostics.

The next runtime proof remains one independently cool, hard-temperature-
guarded Thor A/B of the accumulated production build across field,
Options/menu, and first battle. Do not heat-soak or immediately repeat it.
