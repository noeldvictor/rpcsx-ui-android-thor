# Thor disabled PRX-dump overhead

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

The Android PRX loader checked `debug.rpcsx.thor.dump_prx` after every
successfully decrypted PRX, even in normal builds where the diagnostic was
off. Each check constructed a string and entered the case-insensitive target
parser. The linked core also retained the diagnostic output-path formatter and
success/failure reporting.

This is startup/module-load pressure, not a steady-state gameplay hot path. It
cannot by itself establish an FPS or thermal win, but it is unnecessary work
during the same pre-title phase that has previously tripped the Thor thermal
guard.

## Change

Normal Android builds now:

- compile `thor_dump_prx` to `constexpr false`;
- exclude the Android property include and lookup;
- exclude target parsing, path construction, and diagnostic reports;
- retain the existing `g_cfg.core.ppu_debug` byte capture and
  `dump_executable` path.

The diagnostic remains source-restorable in explicit Android PPU-diagnostics
builds through either:

- `-PrpcsxThorEsPpuExperiments=true`; or
- `RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD=true`.

Desktop behavior remains unchanged. The Ghidra PRX probe now tells users that
its property hook requires that explicit diagnostic build.

## ARM64 Evidence

Committed baseline at `0308124f6`:

- artifact path hash: `1w3q4u6x`
- merged core: `1,304,776,752` bytes
- `prx_load_module`: `5,624` bytes
- `thor_prx_dump_path`: `1,584` bytes
- Android property calls in `prx_load_module`: `1`
- `dump_executable` calls in `prx_load_module`: `1`
- `thor_prx_dump_path` calls in `prx_load_module`: `1`
- selected PRX property/report strings: `3`
- active frame-poll wait symbols: `13`

Default-off candidate from the same build path:

- merged core: `1,304,718,544` bytes (`-58,208`, supporting evidence only)
- `prx_load_module`: `3,956` bytes (`-1,668`)
- `thor_prx_dump_path`: absent (`-1,584`)
- Android property calls in `prx_load_module`: `0`
- `dump_executable` calls in `prx_load_module`: `1`
- `thor_prx_dump_path` calls in `prx_load_module`: `0`
- selected PRX property/report strings: `0`
- active frame-poll wait symbols: `13`

Selected retained strings changed as follows:

| String | Baseline | Candidate |
| --- | ---: | ---: |
| `debug.rpcsx.thor.dump_prx` | 1 | 0 |
| `Thor PRX dump:` | 1 | 0 |
| `Thor PRX dump failed` | 1 | 0 |

The direct function and call deltas prove normal PRX loading no longer enters
the disabled diagnostic rather than merely losing its strings. The unchanged
`dump_executable` call proves normal PPU-debug dumping remains available.
Whole-artifact size includes debug-information effects and is supporting
evidence only.

## Verification

- `tools/test_thor_es_ppu_experiments_build_gate.ps1`: pass, including the
  PRX helper/selection/report gates, constant-false normal Android path,
  preserved PPU-debug dump, property uniqueness, and Ghidra-tool contract.
- Explicit `RPCSX_THOR_ES_PPU_EXPERIMENTS=1` syntax-only ARM64 compile of
  `sys_prx.cpp`: pass.
- Full `tools/test_thor_*.ps1` suite: `49/49` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m06s`.
- Candidate CMake cache confirms PPU/SPU experiments, semaphore superpath,
  draw-stream probe, SPURS probe, wait profiler, RSX auditor, and syscall
  statistics are all `OFF`.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The Thor receives no speed, temperature, FPS, flicker,
gameplay, or stability credit from this host-only round.

## Decision

Keep the compile gate. PRX dumping is an explicit forensic operation and
should not tax production Android module loading. Classify this as
`stackable-cpu-pressure`; require a later independently cool, correctness-
locked Thor route before attributing any runtime or thermal improvement.
