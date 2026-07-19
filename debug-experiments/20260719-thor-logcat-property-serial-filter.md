# Thor logcat property-serial filter

Date: 2026-07-19

Status: host-verified `stackable-cpu-pressure`; device-unmeasured

## Problem

The static Android `LogListener` receives every native RPCSX log message. Its
logcat filter called `get_system_time()` for every message, including when
`debug.rpcsx.thor.logcat=0`. Once per second, one caller also reread both the
custom enable property and `log.tag.RPCS3`.

This kept live logging controls responsive, but imposed a clock query and
separate configuration atomics on a repeated path. Saved startup routes have
produced thousands of native log rows before title, so removing per-message
work is relevant to pre-title CPU pressure. It is not by itself an FPS or
temperature result.

## Change

The filter now uses Android's property-area serial as its change detector:

- every message reads the cheap global property serial instead of monotonic
  time;
- the two property values are reread only when that serial changes;
- enable state and minimum priority publish together in one packed atomic;
- default fallbacks remain logcat enabled and `ANDROID_LOG_VERBOSE`;
- `debug.rpcsx.thor.logcat` and `log.tag.RPCS3` remain live controls;
- Quiet/Normal/Verbose tooling remains `0/S`, `1/I`, and `1/V`;
- log-level mapping and `__android_log_write` are unchanged.

The NDK `system_properties.h` contract explicitly describes
`__system_property_area_serial()` as the beginning of a cache cycle used to
predict whether cached properties or a previously failed property lookup may
have changed. This matches the filter's use and supports properties that were
absent at process start.

Publication order is config first, then property serial with release
semantics. A reader that observes the matching serial with acquire semantics
therefore observes the corresponding packed config. Concurrent refreshers may
duplicate rare property reads, but a stale writer publishes its older serial,
so the next message detects and corrects it rather than retaining stale state.

## ARM64 Evidence

Committed baseline at `ec931b8d6`:

- merged core: `1,304,718,544` bytes
- `LogListener::log`: `464` bytes
- per-message `get_system_time` calls: `1`
- property-area-serial calls: `0`
- property-get callsites in the refresh branch: `2`
- `__android_log_write` calls: `1`
- filter state: 13 bytes (`next_check` 8, `enabled` 1, priority 4)
- selected property strings: `2`
- active frame-poll wait symbols: `13`

Candidate from the same `1w3q4u6x` path:

- merged core: `1,304,720,248` bytes (`+1,704`, supporting evidence only)
- `LogListener::log`: `460` bytes (`-4`)
- per-message `get_system_time` calls: `0`
- property-area-serial calls: `1`
- property-get callsites in the change-only branch: `2`
- `__android_log_write` calls: `1`
- filter state: 8 bytes (two packed `u32` atomics, `-5`)
- selected property strings: `2`
- active frame-poll wait symbols: `13`

The linked-library increase is supporting/debug-information-heavy and not a
hot-path metric. Direct disassembly is the relevant evidence: the clock call
is absent, both property reads move behind serial change detection, and the
actual logcat write remains. The candidate also reduces configuration state
and slightly shrinks the listener function.

## Verification

- New `tools/test_thor_logcat_filter.ps1`: pass. It locks the property-serial,
  packed-publication, fallback, no-clock, filter-before-write, and dynamic
  Quiet/Normal/Verbose contracts.
- Full `tools/test_thor_*.ps1` suite: `50/50` pass.
- Incremental `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass in `1m10s`.
- ARM64 linked disassembly: expected call inventory above.
- Export-surface contract: 34 dynamic exports; pass.
- `git diff --check`: pass.

No APK was assembled or installed. No ADB command, device query, launch, or
gameplay route ran. The Thor receives no measured speed, temperature, FPS,
flicker, gameplay, or stability credit from this host-only round.

## Decision

Keep the property-serial filter. It preserves the dynamic diagnostic controls
while removing a known per-message clock query from both enabled and disabled
logcat modes. Classify it as `stackable-cpu-pressure`; require a later
independently cool, correctness-locked Thor run before attributing a runtime or
thermal improvement.
