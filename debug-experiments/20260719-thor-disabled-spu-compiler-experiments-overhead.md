# 2026-07-19 Thor disabled SPU compiler experiments overhead

## Result

Bank as host-verified `stackable-cpu-pressure` for SPU cache compilation.

Normal Android now compiles reduced-loop invariant-result reuse and dynamic-MFC
lowering to constant false. Both experiments remain available through the
existing explicit Eternal Sonata SPU experiment build opt-in:
`-PrpcsxThorEsSpuExperiments=true` or
`RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD=true`.

Desktop behavior is unchanged. Normal Android retains its exact prior default
semantics: no reduced-loop result reuse and the stock dynamic MFC fallback. No
APK was assembled, installed, or launched, and no ADB command ran.

## Why this slice

The preceding detector cleanup deliberately left these two separate property
paths intact so they could be audited independently.

Reduced-loop result reuse was queried at the start of every LLVM SPU compile.
The property value was cached after first use, but every compile still entered a
C++ static-guard path and retained reuse bookkeeping branches. On Android the
reduced-loop emitter is permanently clamped off after deterministic fresh-cache
U2/U4 corruption, so a normal production core cannot produce a reduced-loop
pattern on which reuse could operate.

Dynamic-MFC selection was not cached. `spu_llvm_recompiler::WRCH` retained two
calls to `spu_dynamic_mfc_fast_enabled()`, whose Android implementation queried
`debug.rpcsx.thor.spu_dynamic_mfc_fast` each time. Cache initialization also
queried the property to select a separate cache suffix. The fast lowering has
no promoted standalone Thor speed or correctness result and every accepted
control resets it off.

Historical startup evidence reconstructed 1,163 SPU programs in about 32.5
seconds. Removing selection and bookkeeping for unavailable/unpromoted compiler
experiments is aligned with lower startup CPU pressure and heat, but this
host-only slice does not measure either outcome.

## Implementation

- Broadened the existing `RPCSX_THOR_ES_SPU_EXPERIMENTS` description to cover
  all Eternal Sonata SPU experiments, not only DMA and GETLLAR.
- Normal Android receives inline constexpr-false helpers from
  `SPURecompiler.h` for reduced-loop reuse and dynamic-MFC lowering.
- Their property/environment parsers in `SPUCommonRecompiler.cpp` compile only
  for desktop or an explicit Android SPU-experiment build.
- LLVM callsites remain source-identical and restorable. Normal Android folds
  away reuse bookkeeping and the dynamic-MFC branch at compile time.
- Explicit diagnostic builds retain the two Thor properties, desktop
  environment controls, cache isolation suffixes, and dynamic MFC IR call.
- The existing `tools/test_thor_es_spu_experiments_build_gate.ps1` now covers
  these compiler paths in addition to DMA/GETLLAR and thread-layout contracts.

## ARM64 proof

RelWithDebInfo artifacts on CMake hash `1w3q4u6x`:

- committed detector-gated baseline: `1,304,810,512` bytes;
- compiler-experiment-gated candidate: `1,304,776,752` bytes;
- whole-library delta: `-33,760` bytes, supporting evidence only.

Direct function evidence:

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `spu_llvm_recompiler::compile` | 47,776 B | 46,520 B | -1,256 B |
| `spu_llvm_recompiler::WRCH` | 10,768 B | 10,740 B | -28 B |
| `spu_cache::initialize` | 14,268 B | 14,152 B | -116 B |
| **Total** | **72,812 B** | **71,412 B** | **-1,400 B** |

Selected inventory:

| Inventory | Baseline | Candidate |
| --- | ---: | ---: |
| Reuse/dynamic helper and state symbols | 4 | 0 |
| Helper parser text | 336 B | 0 B |
| Reuse guard plus cached state | 9 B | 0 B |
| Reuse/dynamic Android property strings | 2 | 0 |
| Dynamic-MFC cache log strings | 1 | 0 |
| Dynamic-MFC IR stub-name strings | 1 | 0 |
| Selected refs in LLVM `compile` | 2 | 0 |
| Selected refs in LLVM `WRCH` | 2 | 0 |
| Android property calls in cache initialize | 4 | 3 |
| Active frame-poll wait symbols | 13 | 13 |

The three remaining cache-initialize property calls belong to independent
active startup controls and were intentionally preserved. The reference and
function deltas prove the normal path no longer pays experiment selection or
reuse bookkeeping rather than merely hiding the property strings.

## Verification

- Updated `tools/test_thor_es_spu_experiments_build_gate.ps1`: pass.
- `tools/test_thor_spu_reduced_loop_diagnostics_build_gate.ps1`: pass.
- Full isolated-child-process `tools/test_thor_*.ps1` suite: `49/49` pass.
- PowerShell AST parse: pass.
- `git diff --check`: pass.
- ARM64 `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m 37s`.
- Candidate cache confirms all Thor experiment gates are `OFF`.
- Native build stderr log is empty.
- No ADB, install, launch, screenshot, thermal query, or gameplay route ran.

## Decision

Keep this cleanup in the accumulated Thor candidate. Unavailable reduced-loop
reuse and unpromoted dynamic-MFC lowering should not leave selection and
bookkeeping in every production SPU compilation.

Do not infer an FPS, frame-time, temperature, flicker, gameplay, or stability
win from the binary proof. The next runtime proof remains one independently
cool, hard-temperature-guarded Thor A/B of the accumulated production build
after the user explicitly says the device is cool and ready.
