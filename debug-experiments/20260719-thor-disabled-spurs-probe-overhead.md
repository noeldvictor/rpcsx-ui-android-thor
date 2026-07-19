# Thor Disabled SPURS Probe Overhead

- Date: 2026-07-19
- Target: AYN Thor Android ARM64 production core
- Title focus: Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`
- Device state: untouched; no ADB, install, launch, temperature read, or game run

## Problem

The runtime SPURS diagnostic was off by default, but normal Android binaries
still retained its hooks and state:

- PPU event, semaphore, and timer paths made 7 calls into the probe helper.
- SPU reservation/MFC paths made 4 calls into the wait-probe helper.
- The PPU enable gate executed `get_system_time`, atomic load/CAS, and a
  periodic Android property read even while disabled.
- The SPU helper called `__system_property_get` on every probe event before it
  could return disabled.
- The binary retained atomic counters, logging logic, report strings, and the
  `debug.rpcsx.thor.spurs_probe` property string.

The hot SPURS family is already measured in Eternal Sonata, so even a small
per-event disabled-path cost is undesirable on a thermally constrained phone.

## Change

Normal Android builds now compile the diagnostic surface out:

- CMake option `RPCSX_THOR_SPURS_PROBE` defaults to `OFF`.
- Gradle opt-in `-PrpcsxThorSpursProbe=true` or environment opt-in
  `RPCSX_THOR_SPURS_PROBE_BUILD=true` restores the diagnostic build.
- PPU call sites see an always-inline empty `thor_spurs_probe_log_ppu_wait`.
- Internal PPU SPURS start/join diagnostics compile to an empty inline hook.
- SPU reservation/MFC paths see an always-inline empty
  `thor_spurs_wait_probe_log`.
- Desktop keeps the existing environment-controlled probe behavior.

The guest-visible SPURS, syscall, timer, reservation, MFC, semaphore, and event
behavior is unchanged. Only diagnostic observation code is removed.

## ARM64 Evidence

Baseline artifact:

- path hash: `40224w3e`
- bytes: `1,306,154,880`
- selected `thor_spurs` symbols: 8
- PPU probe call sites: 7
- SPU probe call sites: 4
- property/report strings: 5

Default-off candidate artifact:

- path hash: `4m6e1u3q`
- bytes: `1,306,096,448` (`-58,432`, supporting evidence only)
- `RPCSX_THOR_SPURS_PROBE:BOOL=OFF`
- selected `thor_spurs` symbols: 0
- PPU probe call sites: 0
- SPU probe call sites: 0
- property/report strings: 0

The six affected hot symbols total `26,940 -> 26,508` bytes (`-432`):

| Function | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
| `sys_event_queue_receive` | 2,296 | 2,200 | -96 |
| `sys_semaphore_wait` | 3,676 | 3,700 | +24 |
| `sys_semaphore_post` | 3,828 | 3,720 | -108 |
| `sys_timer_usleep` | 1,796 | 1,728 | -68 |
| `spu_thread::process_mfc_cmd` | 9,540 | 9,432 | -108 |
| `spu_thread::get_ch_value` | 5,804 | 5,728 | -76 |

The small isolated `sys_semaphore_wait` size increase is compiler layout noise;
the hook call is absent and the combined affected code shrinks.

## Verification

- `tools/test_thor_spurs_probe_build_gate.ps1`: pass
- full `tools/test_thor_*.ps1` suite: `42/42` pass
- PowerShell AST parse: pass
- `git diff --check`: pass
- ARM64 RelWithDebInfo build: pass in `13m 49s`
- default-off CMake cache: wait profiler, RSX auditor, syscall stats, and SPURS
  probe all `OFF`

## Research Cross-check

The 2026 upstream/research refresh does not justify a broader speculative
change in this round:

- Official RPCS3 release history continues to emphasize targeted SPURS,
  ARM64, and Vulkan changes rather than a wholesale mobile scheduler rewrite:
  <https://github.com/RPCS3/rpcs3/releases>.
- The race-to-idle matrix-multiplication result demonstrates energy wins for
  large accelerator-friendly batches, not tiny synchronized SPURS events:
  <https://arxiv.org/abs/2507.20063>.
- GPU execution-idle research is datacenter-focused and supports measuring
  idle exposure, but does not validate a phone/emulator fast path:
  <https://arxiv.org/abs/2604.04745>.
- Elevator's static x86-64-to-AArch64 translation trades substantial code-size
  growth for ahead-of-time determinism; that does not map directly to RPCSX's
  dynamic PS3 PPU/SPU JIT workload: <https://arxiv.org/abs/2605.08419>.

Decision: keep GPU offload limited to large verified no-readback jobs, keep
broad scheduler/spin changes parked, and remove known disabled diagnostic work
from the measured SPURS path now.

## Decision

Bank as host-verified `stackable-cpu-pressure`. It is not a measured speed,
FPS, temperature, flicker, gameplay, or stability win. The next runtime proof
remains one independently cool, hard-temperature-guarded Thor A/B across field,
Options/menu, and first battle; do not heat-soak or immediately repeat it.
