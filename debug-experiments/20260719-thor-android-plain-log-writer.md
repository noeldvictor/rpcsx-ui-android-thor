# Thor Android plain log writer

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

Android constructed the same upstream-style file writer used by desktop. Every
buffer flush therefore wrote both the plain `RPCSX.log` and a live
`RPCSX.log.gz` stream. The duplicate used zlib level 9 with memory level 9
and ran continuously on the background Log Writer thread.

This is unnecessary work on the thermally constrained Thor:

- the Android launcher rotates and creates the plain `RPCSX.log`;
- live debug streaming, speed-sprint routes, input tooling, OODA triage, and
  standard snapshots all read or pull the plain log;
- only the broad collector listed the gzip file, and it already pulled the
  complete plain log beside it;
- the local official RPCS3 checkout at
  `8bd628a43c7b6b8e535796a2f96d92489131fd82` still has the generic dual
  writer, so there was no narrower upstream Android fix to adapt.

The cost is workload-dependent and was not measured on the hot device. It is
therefore not an FPS or temperature result.

## Change

Normal Android builds now compile out only the compressed duplicate:

- `<zlib.h>`, `m_fout2`, and `m_zs` are absent from the Android writer;
- gzip open/initialization, live deflate, finalization, permission restoration,
  sync, and close paths are absent;
- the 32 MiB ring buffer, background writer, maximum-size handling, plain file
  open/write/sync/close, formatting, levels, and listener behavior remain;
- desktop retains the original `.gz`, level-9 initialization,
  `Z_NO_FLUSH`, `Z_FINISH`, and `deflateEnd` behavior exactly;
- `collect_thor_debug.ps1` no longer records an expected failure for an
  Android gzip file that is deliberately not produced.

This is a platform policy, not a runtime experiment flag. The plain log keeps
the full diagnostic record, so Android loses no supported evidence path.

## ARM64 Evidence

Committed baseline at `a126d44bb` and candidate use the same optimized
RelWithDebInfo target and `1w3q4u6x` output path.

| Selected function | Baseline bytes | Candidate bytes | Delta |
| --- | ---: | ---: | ---: |
| `file_writer::file_writer` | 904 | 412 | -492 |
| `file_writer::~file_writer` | 428 | 216 | -212 |
| `file_writer::flush` | 448 | 276 | -172 |
| `file_writer::log` | 468 | 460 | -8 |
| `file_writer::close_prematurely` | 468 | 228 | -240 |
| **Selected total** | **2,716** | **1,592** | **-1,124** |

Measurement correction: the first draft converted hexadecimal size `0x114`
as 228 rather than the correct 276 bytes. This table now records the correct
decimal value; the binary, compression-call inventory, tests, and decision
are unchanged.

Direct ARM64 call inventories changed as expected:

- constructor: calls `27 -> 15`, indirect calls `6 -> 2`,
  `deflateInit2 1 -> 0`;
- destructor: calls `13 -> 5`, indirect calls `5 -> 2`,
  `deflate/deflateEnd/fchmod 1/1/1 -> 0/0/0`;
- flush: calls `9 -> 4`, indirect calls `4 -> 2`,
  `deflate/deflateEnd 1/1 -> 0/0`;
- log enqueue: calls `5 -> 5`; ring-buffer behavior remains;
- premature close: calls `12 -> 4`, indirect calls `5 -> 2`,
  `deflate/deflateEnd/fchmod 1/1/1 -> 0/0/0`.

The two remaining indirect calls in `flush` preserve the plain file validity
check/write path; the removed pair belonged to the compressed output.

Artifact support:

- merged core: `1,304,720,248 -> 1,304,708,376` bytes
  (`-11,872`, supporting/debug-information-heavy);
- cumulative merged-core delta from the earlier `1,305,010,608` reference:
  `-302,232` bytes, supporting only;
- compressed-log open-error string: `1 -> 0`;
- candidate plain-log open-error string: `1`;
- candidate exact `RPCSX.log` string: `1`;
- active Eternal Sonata frame-poll symbols: `13 -> 13`.

## Verification

- New `tools/test_thor_android_plain_log_writer.ps1`: pass. It proves every
  gzip-only source line is desktop-gated, the Android plain writer remains,
  desktop compression remains intact, and Android collectors use plain logs.
- Full `tools/test_thor_*.ps1` suite: `51/51` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m`.
- ARM64 linked disassembly: selected compression/lifecycle calls are all zero;
  plain flush calls remain.
- Export-surface contract: 34 dynamic exports; pass.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The Thor receives no measured speed, temperature, FPS,
flicker, gameplay, or stability credit from this host-only round.

## Decision

Keep the Android plain-log-only writer. It removes continuous high-level gzip
compression and duplicate file traffic without weakening supported debugging.
Classify it as `stackable-cpu-pressure`; require one independently cool,
correctness-locked Thor comparison before assigning runtime or thermal credit.
