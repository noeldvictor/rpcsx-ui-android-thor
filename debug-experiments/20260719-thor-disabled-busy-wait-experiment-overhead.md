# 2026-07-19 Thor disabled busy-wait experiment overhead

## Result

Bank as host-verified `stackable-cpu-pressure`.

Normal Android ARM64 builds now compile directly to the existing disabled-mode
busy-wait loop. The failed light/fast/aggressive batching experiment remains
available only in an explicit diagnostic build through either
`-PrpcsxThorBusyWaitExperiment=true` or
`RPCSX_THOR_BUSY_WAIT_EXPERIMENT_BUILD=true`.

No wait duration, timer source, pause instruction, synchronization rule, or
active Eternal Sonata frame-poll behavior changed. This is not a measured FPS,
temperature, flicker, gameplay, or stability win. No APK was assembled,
installed, or launched, and no ADB command ran.

## Why this slice

The global batching experiment had already failed its Thor field A/B:

| Mode | Field FPS | Visual result |
| --- | ---: | --- |
| off | 19.35 | correct field |
| fast | 18.15 | correct field |
| light | 17.72 | correct field |

The likely failure was added synchronization latency in tight SPU/RSX wait
loops. Normal profiles therefore reset `debug.rpcsx.thor.fast_busy_wait=off`.

Despite being off, every `rx::busy_wait` still entered experiment dispatch. Its
ARM64 disassembly loaded a C++ static guard and cached mode, branched across the
four-mode tree, then selected the normal loop. First use also called guard
acquire/release and parsed the Android property. This recurring work sat on a
known hot primitive used by SPU MFC, RSX FIFO, semaphores, mutexes, VM locks,
and other synchronization paths.

## Implementation

- Added default-off Gradle/CMake gate `RPCSX_THOR_BUSY_WAIT_EXPERIMENT`.
- Normal Android ARM64 no longer includes the property/parser/mode code or its
  `<cstdlib>` and Android property headers.
- Normal Android `rx::busy_wait` retains the exact existing off-loop:
  calculate `get_tsc() + cycles`, issue `yield`, and poll `get_tsc()` until the
  stop value.
- Explicit diagnostic builds retain `disabled`, `light`, `fast`, and
  `aggressive`, the property/environment parser, and all three route-tool modes.
- Added `tools/test_thor_busy_wait_experiment_build_gate.ps1`.

## ARM64 proof

RelWithDebInfo artifacts:

- baseline CMake hash `4k1e1a74`: `1,305,060,904` bytes;
- candidate CMake hash `5b405h58`: `1,305,010,608` bytes;
- whole-library delta: `-50,296` bytes.

Selected inventory:

| Inventory | Baseline | Candidate |
| --- | ---: | ---: |
| Android fast-busy-wait property strings | 1 | 0 |
| Cached mode state | 4 bytes | 0 |
| C++ static guard state | 8 bytes | 0 |
| Parser/init text | 260 bytes | 0 |
| Out-of-line `rx::busy_wait` | 340 bytes | 0 |

The missing out-of-line wrapper is desirable: once the experiment dispatch is
absent, LTO can inline the small direct polling loop into callers.

Three major affected functions total `10,248 -> 9,752` bytes (`-496`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `semaphore_base::imp_wait` | 524 | 316 | -208 |
| `rsx::thread::run_FIFO` | 3,208 | 3,336 | +128 |
| `spu_thread::process_mfc_cmd` | 6,516 | 6,100 | -416 |

Baseline disassembly contained three C++ guard/init calls in
`semaphore_base::imp_wait`, six in `spu_thread::process_mfc_cmd`, and one
additional call to the 340-byte out-of-line wrapper. Candidate disassembly has
none of those ten references and retains direct `CNTVCT_EL0`/`yield` polling.
The RSX FIFO growth is local inlining, not added mode dispatch.

The active Eternal Sonata frame-poll wait remains independently armed:
selected frame-wait symbols are `13 -> 13`.

## Verification

- `tools/test_thor_busy_wait_experiment_build_gate.ps1`: pass.
- New PowerShell contract AST parse: pass.
- Full isolated-child-process `tools/test_thor_*.ps1` suite: `48/48` pass.
- `git diff --check`: pass.
- ARM64 `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `13m 28s`.
- Candidate CMake cache: busy-wait experiment, wait profiler, RSX auditor and
  experiments, syscall stats, SPURS/draw probes, semaphore superpath, and
  PPU/SPU experiments all `OFF`.
- No ADB, APK install, launch, screenshot, thermal query, or gameplay route ran.

## Decision

Keep this cleanup in the accumulated Thor candidate. A globally slower
experiment should not leave guard and mode dispatch on a primitive observed in
millions of waits. Its diagnostic source and route controls remain available
when intentionally building that experiment.

Do not infer an FPS or temperature delta from the binary proof. The next
runtime proof remains one independently cool, hard-temperature-guarded Thor
A/B of the accumulated production build after the user explicitly says the
device is cool and ready.
