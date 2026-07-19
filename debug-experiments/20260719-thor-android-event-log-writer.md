# Thor Android event-driven log writer

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

After the compressed Android log duplicate was removed, the remaining plain
Log Writer thread still used the generic desktop idle policy:

```text
empty buffer -> sleep 10 ms -> check again
```

That schedules about 100 idle polls per second for the entire emulator
lifetime, including menus and quiet gameplay periods. The local official RPCS3
implementation retains this generic policy. On a thermally constrained Android
handheld, repeated timer wakeups are a credible background CPU/heat source even
though they are not an emulation hot path.

This round did not measure scheduler wakeups or temperature on the hot Thor, so
it is not an FPS or thermal result.

## Change

Normal Android builds now use the existing 32-bit `atomic_t` wait/notify
engine for the Log Writer's empty state:

- the writer sets `m_writer_waiting=1` before its final buffer/shutdown
  recheck;
- if work appeared before arming, the recheck continues without sleeping;
- after a producer finishes copying and atomically commits ring-buffer bytes,
  it wakes the writer only when the waiting flag is armed;
- shutdown sets `m_out=-1`, wakes an armed writer, and only then joins it;
- Android has no fixed-duration idle sleep;
- desktop retains the original `sleep_for(10ms)` behavior exactly.

The normal producer path adds one waiting-state load and branch. The exchange
and notification run only when the writer is actually armed.

## Lost-Wake Safety

The ordering covers each publication window:

1. A producer that commits before the writer arms changes `m_buf`; the
   post-arm recheck observes it and does not wait.
2. A producer that commits after arming clears the flag and notifies.
3. A producer between the recheck and wait clears the flag first; waiting on
   the old value returns immediately even if the notification arrived early.
4. Shutdown follows the same clear-and-notify protocol and the writer rechecks
   `m_out` after arming.
5. Notification occurs only after the ring-buffer commit, so the writer cannot
   consume a partially copied record.

Spurious wakes are safe: the writer clears the flag and repeats the normal
buffer check.

## ARM64 Evidence

Committed baseline at `7820e8f12` and candidate use the same optimized
RelWithDebInfo target and `1w3q4u6x` output path.

| Selected function | Baseline bytes | Candidate bytes | Delta |
| --- | ---: | ---: | ---: |
| `file_writer::file_writer` | 412 | 416 | +4 |
| `file_writer::~file_writer` | 216 | 240 | +24 |
| `file_writer::flush` | 276 | 276 | 0 |
| `file_writer::log` | 460 | 496 | +36 |
| `file_writer::close_prematurely` | 228 | 228 | 0 |
| Log Writer thread proxy | 276 | 348 | +72 |
| **Selected total** | **1,868** | **2,004** | **+136** |

The intentional protocol code is small and direct:

- writer proxy: `sleep_for 1 -> 0`, `atomic_wait_engine::wait 0 -> 1`;
- normal producer wake check: one `ldar` plus one not-waiting branch;
- armed producer path: one `swpal`, a zero check, and one tail branch to
  `atomic_wait_engine::notify_one`;
- destructor notification references: `0 -> 1`;
- out-of-line `wake_writer` symbols: `0` because LTO inlines it;
- existing writer `sched_yield` for an in-progress producer remains `1`;
- plain `flush` and premature-close function sizes are unchanged.

Artifact support:

- scheduled empty-buffer timer polls: approximately `100/s -> 0/s` in
  normal Android source behavior;
- merged core: `1,304,708,376 -> 1,304,707,984` bytes
  (`-392`, supporting/debug-information-heavy);
- cumulative merged-core delta from the earlier `1,305,010,608` reference:
  `-302,624` bytes, supporting only;
- active Eternal Sonata frame-poll symbols: `13 -> 13`.

## Verification

- New `tools/test_thor_android_event_log_writer.ps1`: pass. It locks
  post-commit wake ordering, arm-before-recheck, shutdown-before-join,
  Android-only event state, and desktop-only timed polling.
- Existing Android plain-log writer contract: pass.
- Full `tools/test_thor_*.ps1` suite: `52/52` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m5s`.
- ARM64 linked disassembly: expected wait/wake inventory above.
- Export-surface contract: 34 dynamic exports; pass.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The Thor receives no measured speed, temperature, FPS,
flicker, gameplay, or stability credit from this host-only round.

## Measurement Correction

The preceding plain-log-only ledger initially converted hexadecimal symbol
size `0x114` as 228 instead of the correct 276 bytes. Its table and AGENTS
summary are corrected in this round: the five-function change was
`2,716 -> 1,592` bytes (`-1,124`), not `2,716 -> 1,544`
(`-1,172`). Compression-call removal, linked-core size, tests, and the
implementation decision were unaffected.

## Decision

Keep the event-driven Android writer. It replaces a permanent 10 ms polling
cadence with immediate, race-safe notifications while preserving log content,
flush ordering, shutdown, and desktop behavior. Classify it as
`stackable-cpu-pressure`; require one independently cool, correctness-locked
Thor comparison before assigning runtime or thermal credit.
