# Thor Android warning-level logcat default

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

The native Android listener duplicated every RPCSX log message into Android's
system log by default because both the initial packed state and the unset
`log.tag.RPCS3` fallback used `ANDROID_LOG_VERBOSE`.

The event-driven plain `RPCSX.log` writer already retains the complete
diagnostic stream. Sending routine success, notice, and informational messages
through `__android_log_write` therefore adds avoidable application and Android
logging-service work during emulation.

## Capture evidence

The repository retains 24 Thor `RPCSX*.log` captures. Their first-line level
markers contain 87,813 native listener messages:

| RPCSX level | Android priority | Messages | Kept by WARN |
| --- | --- | ---: | --- |
| Always | INFO | 51 | no |
| Fatal | FATAL | 4 | yes |
| Error | ERROR | 4,609 | yes |
| TODO | WARN | 44 | yes |
| Success | INFO | 3,005 | no |
| Warning | WARN | 12,075 | yes |
| Notice | DEBUG | 68,025 | no |
| Trace | VERBOSE | 0 | no |
| **Total** |  | **87,813** | **16,732** |

The warning-level default therefore suppresses 71,081 of those expected
`__android_log_write` calls, or 80.946%, on an equivalent message mix.
Continuation rows are not counted as separate calls because one native message
may contain embedded newlines.

## Change

When Android logging properties are unset:

- the initial packed listener state is enabled at `ANDROID_LOG_WARN`;
- `log.tag.RPCS3` falls back to `ANDROID_LOG_WARN`;
- `debug.rpcsx.thor.logcat` remains enabled by default.

The existing live controls remain unchanged:

- Quiet disables the listener and uses SILENT;
- Normal explicitly selects INFO;
- Verbose explicitly selects VERBOSE.

The warning default preserves regular warning, TODO, error, and fatal output.
The crash handler's direct FATAL `__android_log_write` remains outside the
regular listener filter. The complete plain `RPCSX.log` remains unchanged at
all levels.

## ARM64 evidence

Committed baseline `8fbf4118c` and candidate use the same optimized
RelWithDebInfo target and `1w3q4u6x` output path.

- packed initial state: `0x80000002 -> 0x80000005`;
- unset-priority fallback instruction: `2 -> 5`;
- `LogListener::log`: `460 -> 452` bytes;
- linked core: `1,304,706,256 -> 1,304,706,248` bytes (`-8`);
- one property-area serial call remains;
- two property reads remain behind the serial-change branch;
- one regular `__android_log_write` callsite remains;
- all 13 active Eternal Sonata frame-poll symbols remain.

The small binary delta is supporting evidence only. The expected runtime gain
comes from filtering lower-priority messages before the system-log call.

## Verification

- Focused `tools/test_thor_logcat_filter.ps1`: pass.
- The contract now locks the warning default and direct fatal crash report.
- Quiet, Normal, and Verbose live-control profiles remain locked.
- Full `tools/test_thor_*.ps1` suite: `53/53` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in 1m 11s.
- Export-surface contract: 34 dynamic exports; pass.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The hot Thor remained untouched, so this round has no
measured FPS, temperature, flicker, gameplay, or runtime-stability credit.

## Decision

Keep the warning-level default. It preserves actionable early diagnostics and
explicit verbose capture modes while removing an estimated 80.946% of routine
native system-log calls on the retained capture mix. Require a later cool,
correctness-locked Thor comparison before assigning thermal or FPS credit.
