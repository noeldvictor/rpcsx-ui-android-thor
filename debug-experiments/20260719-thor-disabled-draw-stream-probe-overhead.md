# Thor Disabled Draw-stream Probe Overhead

- Date: 2026-07-19
- Target: AYN Thor Android ARM64 production core
- Title focus: Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`
- Device state: untouched; no ADB, install, launch, temperature read, or game run

## Problem

The Eternal Sonata draw-stream diagnostic was runtime-disabled by default, but
normal Android binaries still retained its entire semaphore/TTY observation
surface:

- two snapshot-vector slots capable of holding 1.5 MiB each during diagnostics,
  plus 448 bytes of always-linked global state;
- draw-stream layout parsing, snapshot comparison, and fault-word scans;
- selector repair/restore code whose broad write-back predecessor was already
  counterproven by severe visual corruption and a renderer fault;
- three wait-path hooks, one post-path hook, and one TTY hook;
- static property/env initialization and extensive report formatting.

Even with the runtime mode off, the linked semaphore wait/post functions still
contained 13 references to draw-stream helpers or initialization paths.

## Change

Normal Android builds now compile this diagnostic body out:

- CMake option `RPCSX_THOR_DRAW_STREAM_PROBE` defaults to `OFF`.
- Gradle opt-in `-PrpcsxThorDrawStreamProbe=true` or environment opt-in
  `RPCSX_THOR_DRAW_STREAM_PROBE_BUILD=true` restores the diagnostic build.
- The three wait call sites and one post call site see empty inline helpers.
- The TTY call site sees an empty inline helper from the public probe header.
- Desktop keeps the existing environment-controlled probe behavior.
- The independent Eternal Sonata semaphore superpath remains outside this gate.

Guest semaphore, TTY, event, timer, draw parsing, and renderer behavior is
unchanged in the normal build. Only optional diagnostic and repair observation
code is absent.

## ARM64 Evidence

Committed SPURS-gated baseline artifact:

- path hash: `4m6e1u3q`
- bytes: `1,306,096,448`
- selected `thor_es_draw_stream` symbols: 17
- draw-stream property/env/report strings: 11
- draw-stream references inside semaphore wait/post: 13

Default-off candidate artifact:

- path hash: `6y2q5wm5`
- bytes: `1,306,000,128` (`-96,320`, supporting evidence only)
- `RPCSX_THOR_DRAW_STREAM_PROBE:BOOL=OFF`
- selected `thor_es_draw_stream` symbols: 0
- draw-stream property/env/report strings: 0
- draw-stream references inside semaphore wait/post/TTY: 0

The three affected hot symbols total `10,088 -> 7,276` bytes (`-2,812`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `sys_semaphore_wait` | 3,700 | 2,460 | -1,240 |
| `sys_semaphore_post` | 3,720 | 2,380 | -1,340 |
| `sys_tty_write` | 2,668 | 2,436 | -232 |

## Verification

- `tools/test_thor_draw_stream_probe_build_gate.ps1`: pass
- full `tools/test_thor_*.ps1` suite: `43/43` pass
- PowerShell AST parse: pass
- `git diff --check`: pass
- ARM64 RelWithDebInfo build: pass in `14m 29s`
- default-off CMake cache: draw-stream probe, SPURS probe, wait profiler, RSX
  auditor, and syscall stats all `OFF`
- prior SPURS removal remains intact in the source-contract suite

## Decision

Bank as host-verified `stackable-cpu-pressure`. It is not a measured speed,
FPS, temperature, flicker, gameplay, or stability win. The diagnostic remains
available only in an explicit diagnostic build; do not carry its inactive
semaphore/TTY cost in production.

The next runtime proof remains one independently cool, hard-temperature-
guarded Thor A/B across field, Options/menu, and first battle. Do not
heat-soak or immediately repeat it.
