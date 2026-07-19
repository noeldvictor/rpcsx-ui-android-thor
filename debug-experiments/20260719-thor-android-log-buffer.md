# Thor Android log-buffer memory reduction

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure` / stability-memory credit;
device-unmeasured

## Problem

Android creates one native file listener for `RPCSX.log`. Even after its live
gzip output was removed, the generic desktop writer still allocated and
value-initialized:

- a 32 MiB pending-record ring; and
- the now-dead 64 KiB gzip output array.

The optimized ARM64 constructor proved both costs directly: one
33,554,432-byte allocation/memset plus a 65,540-byte member memset containing
the four-byte event-wait flag and 65,536-byte scratch array. Touching those
pages adds startup CPU and resident-memory pressure before emulation begins.

## Capture Evidence

The repository retains 24 Thor `RPCSX*.log` route captures:

- largest complete saved log: `1,606,357` bytes;
- 95th-percentile saved log: `799,344` bytes;
- total across all 24 captures: `16,788,130` bytes.

A 4 MiB ring is `2.611x` the largest entire saved log. The ring stores only
records waiting for the background writer, not the complete output file, so
this is a conservative pending-data allowance. The on-disk maximum remains
one quarter of free storage.

## Change

Normal Android builds now use:

- a 4 MiB power-of-two pending-record ring;
- the unchanged 32 KiB per-write chunk;
- no `m_zout` member or scratch initialization.

Desktop retains the 32 MiB ring, 64 KiB gzip output array, and all compressed
logging behavior.

The ring arithmetic remains size-generic: quotient tracks committed push
position and remainder tracks in-progress bytes. Existing power-of-two and
overflow assertions remain, with a new assertion that the write chunk is
smaller than the ring.

## Memory and Startup Credit

For the single Android listener:

| Allocation/touch | Baseline | Candidate | Removed |
| --- | ---: | ---: | ---: |
| Pending ring | 33,554,432 | 4,194,304 | 29,360,128 |
| Gzip scratch | 65,536 | 0 | 65,536 |
| **Total** | **33,619,968** | **4,194,304** | **29,425,664** |

That is `28.0625 MiB`, or `7,184` 4 KiB pages, no longer allocated and
zeroed at startup.

ARM64 disassembly confirms:

- ring allocation argument: `33,554,432 -> 4,194,304`;
- ring memset length: `33,554,432 -> 4,194,304`;
- 65,540-byte member memset: `1 -> 0`;
- event-wait state remains as one explicit four-byte zero store;
- aligned listener allocation: `65,792 -> 256` bytes.

## ARM64 Supporting Evidence

Committed baseline at `b2cc74611` and candidate use the same optimized
RelWithDebInfo target and `1w3q4u6x` output path.

| Selected symbol | Baseline bytes | Candidate bytes | Delta |
| --- | ---: | ---: | ---: |
| `file_writer::file_writer` | 416 | 396 | -20 |
| `file_writer::~file_writer` | 240 | 240 | 0 |
| `file_writer::flush` | 276 | 272 | -4 |
| `file_writer::log` | 496 | 500 | +4 |
| Log Writer thread proxy | 348 | 348 | 0 |
| `make_file_listener` | 88 | 80 | -8 |

Artifact support:

- merged core: `1,304,707,984 -> 1,304,706,256` bytes
  (`-1,728`, supporting/debug-information-heavy);
- cumulative merged-core delta from the earlier `1,305,010,608` reference:
  `-304,352` bytes, supporting only;
- active Eternal Sonata frame-poll symbols: `13 -> 13`.

## Verification

- New `tools/test_thor_android_log_buffer.ps1`: pass. It locks the 4 MiB
  Android / 32 MiB desktop split, 32 KiB write chunk, generic ring encoding,
  one Android listener, unchanged file maximum, and exact memory saving.
- Strengthened `tools/test_thor_android_plain_log_writer.ps1`: pass. It now
  proves `m_zout` and all uses remain desktop-only.
- Event-driven Android writer contract: pass.
- Full `tools/test_thor_*.ps1` suite: `53/53` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m`.
- ARM64 linked disassembly: expected allocation/memset constants above.
- Export-surface contract: 34 dynamic exports; pass.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The Thor receives no measured FPS, temperature, flicker,
gameplay, or runtime-stability credit from this host-only round.

## Decision

Keep the reduced Android ring and removed scratch storage. This is a direct
28.0625 MiB resident/startup-memory reduction with more capacity than any full
saved Thor log and no supported diagnostic loss. Classify it as
`stackable-cpu-pressure` plus host-proven stability-memory credit; require one
independently cool, correctness-locked Thor comparison before assigning
runtime or thermal credit.
