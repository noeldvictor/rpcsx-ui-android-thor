# Eternal Sonata Synchronization Attribution

Date: 2026-07-19

Status: host-profiled; synchronization shortcuts rejected

## Scope and safety

This round tested whether PPU synchronization, SPURS group joins, or timer
sleep handling supplied a safe Eternal Sonata speed/heat target. It was
Windows-only. Thor was not queried, installed to, launched, or temperature
polled.

The probe is opt-in through `RPCS3_ES_SYNC_PROFILE=compact`, hard-gated to
`BLUS30161`, and observational. It does not shorten waits, spin, change
scheduling, or alter guest memory. Aggregate reports are rate-limited to five
seconds. Detailed reports are limited to the first 64 waits of at least one
second.

## Implementation and verification

- Upstream RPCS3 now records actual elapsed wall time for:
  - immediate and blocked event-queue receives;
  - immediate and blocked semaphore waits;
  - timer sleeps and their requested duration;
  - Eternal Sonata's one-SPU `CellSpursKernelGroup` start and join calls.
- The refined probe splits PPU waits into `main_thread`, `SpursHdlr0`, and
  other PPU threads and identifies bounded long-wait owners by PPU ID, CIA, LR,
  and name.
- `tools/windows_rpcs3_lab.ps1` and
  `tools/eternal_sonata_speed_sprint.ps1` expose
  `-EternalSonataSyncProfile Profile`, restore the process environment after
  launch, request a graceful profiler stop, and save `sync-profile.txt`.
- `tools/test_thor_es_sync_profile.ps1` validates the title gate, bounded
  logger, immediate/blocked split, SPURS filter, environment restoration, and
  PowerShell parsing.
- MSVC Release compilation, LTCG linking, and Qt deployment completed.

## Correctness-gated traces

Aggregate trace:

`debug-captures/windows-lab/20260719-000346-es-sync-profile-first-battle-r2-windows`

Thread-class trace:

`debug-captures/windows-lab/20260719-001406-es-sync-profile-thread-classes-windows`

Both state-aware routes reached the Path to Tenuto field and the first-battle
tutorial. Field and battle stayed near the title's 30 FPS cap. The second run
had clean host and external-contention summaries. No targeted unknown-draw,
fatal, assertion, or device-loss evidence appeared.

## Results

Final cumulative thread-class snapshot at about 162 seconds:

| Site/class | Calls | Elapsed | Mean |
|---|---:|---:|---:|
| event wait / main | 6,603 | 1.035 s | 157 us |
| event wait / other | 23,754 | 167.639 s | 7.06 ms |
| semaphore wait / main | 67 | 45.787 ms | 683 us |
| semaphore wait / other | 10,378 | 445.638 s | 42.9 ms |
| timer / main | 1,369,486 | 137.714 s | 100.6 us |
| timer / other | 156,533 | 139.530 s | 891 us |
| SPURS group join | 14,474 | 12.791 s | 884 us |

Battle-route deltas over 40 seconds:

| Site/class | Calls | Elapsed | Mean |
|---|---:|---:|---:|
| event wait / main | 1,200 | 188.1 ms | 157 us |
| event wait / other | 6,150 | 43.459 s | 7.07 ms |
| semaphore wait / main | 8 | 4.5 ms | 559 us |
| semaphore wait / other | 1,358 | 123.567 s | 91.0 ms |
| timer / main | 352,048 | 35.363 s | 100.4 us |
| timer / other | 40,252 | 35.819 s | 890 us |
| SPURS group join | 3,750 | 3.402 s | 907 us |

The aggregate semaphore maximum of approximately 20.17 seconds initially
looked actionable. The refined trace disproved that interpretation. Every
wait over one second came from the same two unnamed background PPU workers:

- PPU `0x1000001`, syscall CIA `0x0031c188`, LR `0x002b4d8c`;
- PPU `0x1000002`, syscall CIA `0x0031c188`, LR `0x002b60f8`.

They woke in symmetric pairs after roughly 4-20 seconds. None of the long
waits belonged to `main_thread` or `SpursHdlr0`. Their overlapping blocked
time is therefore background queue residency, not serial frame time.

No event, semaphore, or timer calls were attributed to the `SpursHdlr0`
thread itself. The handler's start/join cadence remained about 94 cycles per
second, but each join averaged less than one millisecond. Start setup was only
about six microseconds per call. The join duration reflects completion of the
SPU work rather than expensive wrapper setup.

The main thread makes about 8.8 thousand approximately 100-microsecond timer
calls per second. This is the already-known title polling loop around
`0x002a8300`. Earlier yield, skip, clamp, busy-wait, scheduler, and join-spin
experiments did not improve the title and some regressed timing or power.
This trace gives no evidence that changing its guest-visible timing is safe.

## Decision

Do not promote a synchronization fast path from these traces:

- do not bypass the two long background semaphore waits;
- do not shorten event waits;
- do not spin on SPURS joins;
- do not replace the main polling sleeps with yield/skip/clamp behavior;
- do not claim FPS, thermal, or flicker improvement from the profiler.

The useful result is a bounded counterproof: the largest aggregate waits are
parallel background residency, while main-thread semaphore and event costs are
small and SPURS wrapper cost is not dominant. Future work should return to
CPU execution/transition cost or reduce timer syscall overhead only if elapsed
sleep semantics remain identical and a cool Android power trace proves a gain.
