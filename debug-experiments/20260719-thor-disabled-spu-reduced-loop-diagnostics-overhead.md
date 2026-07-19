# 2026-07-19 Thor disabled SPU reduced-loop diagnostics overhead

## Result

Bank as host-verified `stackable-cpu-pressure` for SPU cache startup.

Normal Android now omits the retired reduced-loop detect-only scanner from the
production core. The detector remains available only in an explicit diagnostic
build through either `-PrpcsxThorSpuReducedLoopDiagnostics=true` or
`RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS_BUILD=true`.

Unsafe Android reduced-loop emission remains unconditionally disabled. This
change does not reactivate, repair, or alter the emitter, SPU execution, cache
identity, scheduler semantics, or generated guest code. Desktop behavior is
unchanged. No APK was assembled, installed, or launched, and no ADB command ran.

## Why this slice

Fresh-cache Thor U4 and U2/no-reuse routes both corrupted Eternal Sonata at
`CellSpursKernel0` SPU PC `0x330f0`, reading unmapped `0x8d230480`. That excludes
unroll count, invariant-result reuse, and stale cache as the common cause. The
vendored Android emitter is permanently retired until the complete modern
upstream analyzer/emitter contract can be ported and correctness-proven.

Detect-only mode remained useful for explicit host-guided diagnosis, but it was
runtime-disabled by default. Even in a normal Android build,
`spu_recompiler_base::analyse` still:

- queried `debug.rpcsx.thor.spu_reduced_loop_detect` for every analysis;
- constructed candidate and pattern maps;
- retained scanner lambdas and detect logging in the binary;
- called an empty candidate-map destructor on the default-off path.

Historical startup evidence reconstructed 1,163 SPU programs in about 32.5
seconds after interpreter creation. Removing a property syscall and empty map
lifetime from each analysis is aligned with lower startup CPU pressure and heat,
although this host-only slice does not measure a thermal delta.

## Implementation

- Added default-off Gradle/CMake gate
  `RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS`.
- Normal Android preprocesses out the detect property helper, candidate type,
  candidate/pattern maps, scanner lambdas, scan loop, detect log, and reduced-loop
  emitter-registration block.
- Explicit diagnostic Android builds retain the property and full detect-only
  scanner.
- Desktop retains its existing `RPCSX_SPU_REDUCED_LOOP_DETECT` behavior.
- `spu_reduced_loop_emit_enabled()` still returns false unconditionally on
  Android, including diagnostic builds.
- Existing `ReducedLoop` route control remains available for an intentionally
  built diagnostic core.
- Added `tools/test_thor_spu_reduced_loop_diagnostics_build_gate.ps1`.

## ARM64 proof

RelWithDebInfo artifacts:

- baseline CMake hash `5b405h58`: `1,305,010,608` bytes;
- candidate CMake hash `1w3q4u6x`: `1,304,810,512` bytes;
- whole-library delta: `-200,096` bytes, supporting evidence only.

The LTO input object for `SPUCommonRecompiler.cpp` changed:

- baseline: `5,169,388` bytes;
- candidate: `4,881,696` bytes;
- delta: `-287,692` bytes, supporting evidence only.

Those whole-artifact deltas include removal of debug information for the
preprocessed scanner island; they are not runtime-speed estimates.

Direct runtime-path evidence:

| Inventory | Baseline | Candidate |
| --- | ---: | ---: |
| `spu_recompiler_base::analyse` text | 49,760 B | 48,840 B |
| Detect property calls in `analyse` | 1 | 0 |
| Candidate-map destructor calls in `analyse` | 1 | 0 |
| Selected detect-only symbols | 1 | 0 |
| Android detect property strings | 1 | 0 |
| Detect-only log format strings | 1 | 0 |
| Reduced-loop reuse property strings | 1 | 1 |
| Dynamic-MFC property strings | 1 | 1 |
| Active frame-poll wait symbols | 13 | 13 |

An intermediate constexpr-only build removed the property and log string but
still retained the empty candidate-map destructor. The final source gate omits
the entire isolated scanner block and removes both default-path references.
Keeping the reuse and dynamic-MFC strings proves those separate experiments
were not silently bundled into this change.

## Verification

- `tools/test_thor_spu_reduced_loop_diagnostics_build_gate.ps1`: pass.
- PowerShell AST parse for the new contract: pass.
- Full isolated-child-process `tools/test_thor_*.ps1` suite: `49/49` pass.
- `git diff --check`: pass.
- Initial full ARM64 configuration/link completed for CMake hash `1w3q4u6x`.
- Final incremental ARM64 `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in
  `1m 05s`.
- The final SPU translation unit reports 70 existing deprecation warnings and
  no new unused-function warning.
- Candidate CMake cache confirms reduced-loop diagnostics, busy-wait, RSX
  auditor/experiments, syscall stats, SPURS/draw probes, semaphore superpath,
  and Eternal Sonata PPU/SPU experiments are all `OFF`.
- No ADB, install, launch, screenshot, thermal query, or gameplay route ran.

## Decision

Keep this cleanup in the accumulated Thor candidate. A permanently retired
emitter should not leave a default-off detector property syscall and empty map
lifetime in every SPU analysis during cache reconstruction.

Do not infer an FPS, frame-time, temperature, flicker, gameplay, or stability
win from the binary proof. The next runtime proof remains one independently
cool, hard-temperature-guarded Thor A/B of the accumulated production build
after the user explicitly says the device is cool and ready.

The next host-only SPU startup audit should examine the separate reduced-loop
reuse and dynamic-MFC property checks. They remain in this candidate and receive
no removal credit from this slice.
