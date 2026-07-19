# Thor Disabled Eternal Sonata PPU Experiments Overhead

- Date: 2026-07-19
- Target: AYN Thor Android ARM64 production core
- Title focus: Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`
- Device state: untouched; no ADB, install, launch, temperature read, or game run

## Problem

The Eternal Sonata PPU command-isolation, dispatch-provenance, and async-draw
experiments were runtime-disabled by default but remained compiled into normal
Android builds.

The retained implementation included:

- command interpreter range selection and ten diagnostic resolver hooks;
- command 9/60/61, template, publish, and dispatch provenance rings;
- async target verification, hashing, and post-drain reporting;
- property parsing and large report formats;
- four disabled range detectors called for every PPU function while creating
  the PPU object-cache key.

The behavior experiments also have negative or diagnostic-only evidence. The
command-interpreter route produced about `21.14 FPS` on both tested modes
against a comparable `27.12 FPS` route, roughly 22% slower, without fixing the
corruption. Settled-target async write-back caused severe black/green
corruption and a guest fault and was retired. Async verification and
provenance are useful diagnostics but have no normal-play performance credit.

## Change

Normal Android builds now compile the entire PPU experiment suite out:

- CMake option `RPCSX_THOR_ES_PPU_EXPERIMENTS` defaults to `OFF`.
- Gradle opt-in `-PrpcsxThorEsPpuExperiments=true` or environment opt-in
  `RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD=true` restores the diagnostic suite.
- Desktop retains the existing property-controlled behavior.
- Normal Android removes all ten diagnostic resolver entries and all PPU
  object-cache range scans/settings additions.
- Three range helpers referenced from `PPUTranslator.cpp` remain source-level
  constant-false stubs in normal Android; LTO eliminates them from the final
  library and folds away their translator branches.
- Existing PPU settings enum values/cache bits remain reserved so explicitly
  diagnostic objects keep their distinct identity.
- The active Eternal Sonata frame-poll wait path is outside the build gate and
  remains unchanged.

## ARM64 Evidence

Committed SPU-experiment-gated baseline artifact:

- path hash: `161u3233`
- bytes: `1,305,654,632`
- selected PPU diagnostic symbols: 70
- selected diagnostic data/state: 637,126 bytes across 53 symbols
- selected diagnostic text: 14,720 bytes across 17 symbols
- selected property/report strings: 8
- diagnostic calls in `PPUTranslator::Translate`: 3
- active frame-poll wait symbols: 13

Default-off candidate artifact:

- path hash: `2q3p4q3l`
- bytes: `1,305,382,384` (`-272,248`, supporting evidence only)
- `RPCSX_THOR_ES_PPU_EXPERIMENTS:BOOL=OFF`
- selected PPU diagnostic symbols: 0
- selected diagnostic data/state: 0 bytes
- selected diagnostic text: 0 bytes
- selected property/report strings: 0
- diagnostic calls in `PPUTranslator::Translate`: 0
- active frame-poll wait symbols: 13

Two directly affected functions total `34,428 -> 26,760` bytes (`-7,668`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `PPUTranslator::Translate` | 10,112 | 2,988 | -7,124 |
| `ppu_initialize(..., concurent_memory_limit&)` | 24,316 | 23,772 | -544 |

The translator's three prior calls to command-interpreter, dispatch-probe, and
async-barrier range detectors are absent from candidate ARM64 disassembly.
The whole-library delta is supporting evidence rather than a speed estimate;
the function, symbol, state, string, and disassembly deltas prove the normal
diagnostic work was folded away.

## Verification

- `tools/test_thor_es_ppu_experiments_build_gate.ps1`: pass
- full `tools/test_thor_*.ps1` suite with isolated child-process exit status:
  `46/46` pass
- PowerShell AST parse: pass
- `git diff --check`: pass
- first ARM64 RelWithDebInfo build compiled successfully but exposed three
  cross-translation-unit range references at link time
- normal-Android constant-false stubs added for those exact references;
  focused contract pass and incremental ARM64 build pass in `55.7s`
- candidate CMake cache: PPU experiments, SPU experiments, semaphore
  superpath, draw-stream probe, SPURS probe, wait profiler, RSX auditor, and
  syscall stats all `OFF`
- active frame-poll wait symbols remain `13 -> 13`

## Decision

Bank as host-verified `stackable-cpu-pressure`. This removes disabled range
checks from PPU translation/cache preparation and drops a large diagnostic
state footprint, so its evidence is stronger than code-size-only cleanup. It
is still not a measured FPS, temperature, flicker, gameplay, or stability win.

Keep the command isolation, dispatch provenance, and async verifier behind the
explicit diagnostic build opt-in. Do not restore them for normal play; their
behavior has either negative Thor evidence or diagnostic-only value.

The next runtime proof remains one independently cool, hard-temperature-
guarded Thor A/B of the accumulated production build across field,
Options/menu, and first battle. Do not heat-soak or immediately repeat it.
