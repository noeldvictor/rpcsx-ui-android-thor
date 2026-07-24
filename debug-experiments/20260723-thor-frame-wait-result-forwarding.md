# Thor frame-wait fallback result forwarding

## Status

Host-verified `stackable-cpu-pressure`; device-unmeasured. No ADB query,
install, launch, temperature poll, wait, or other Thor contact occurred.

## Motivation

The Eternal Sonata frame-poll wrapper already classified the exact main PPU,
CIA, adjusted 100 us duration, title, mode, object, divisor, counter, and
renderer before choosing either the bounded event wait or the normal timer.
After every normal nonzero `sys_timer_usleep`, the inlined fallback observer
repeated the PPU, CIA, duration, title, and mode gates before it could inspect
the saved counter.

Saved continuous-rearm routes contain 173,278 exact frame-poll calls:

| Route | Calls | Event waits | Genuine fallback sleeps |
|---|---:|---:|---:|
| Title | 34,612 | 34,542 | 70 |
| First battle | 105,181 | 105,145 | 36 |
| Options | 33,485 | 33,484 | 1 |
| Total | 173,278 | 173,171 | 107 |

Only those 107 exact calls needed post-sleep counter observation.

## Change

`try_thor_es_frame_poll_wait` now returns a compact result:

- `not_candidate`;
- `normal_sleep_fast`;
- `normal_sleep_diagnostic`; or
- `waited`.

The result is carried across the normal sleep. A `waited` result still returns
immediately. `not_candidate` skips fallback observation with one byte-result
branch. Only the two `normal_sleep_*` results enter the fallback observer, and
the diagnostic variant alone increments `fallback_rearms`.

The fallback retains its post-sleep PPU/object identity, VM mapping, counter,
renderer, completion-VBlank, and armed-state checks. Those checks cannot be
hoisted because guest memory or renderer state can change while the normal
timer sleeps. Process-lifetime mode and PPU-lifetime title decisions are safe
to forward and are no longer reloaded.

## Exact ARM64 proof

The predecessor `sys_timer_usleep` was `0x4d4` bytes. Its post-sleep path
repeated 19 linked gate instructions across `0x16d18cc..0x16d1914` before
entering fallback state checks: PPU ID, CIA, adjusted duration, cached title,
and cached mode.

The successor is `0x494` bytes, 64 bytes smaller (5.2%). After
`wait_timeout`, it contains:

```text
16d18c8: cbz  w22, normal_exit
```

The remaining fallback begins directly with state PPU/object/VM validation.
There is exactly one title-byte load in the whole function, at the initial
wrapper gate:

```text
16d1714: ldrb w8, [x19, #0x9f9]
16d1718: cmp  w8, #0x1
16d171c: b.ne normal_timer_path
```

For the 107 saved exact fallback calls, 19 repeated gates become one result
branch, conservatively removing 1,926 linked gate instruction executions.
Ordinary unrelated nonzero sleeps also avoid their former post-sleep gate
chain, but no dynamic credit is assigned without a call count.

## Verification

Passed:

- focused result-forwarding and frame-poll source contract;
- Android ARM64 RelWithDebInfo native build;
- exact linked function size and single-title-load inspection;
- ThorTest ARM64-only APK build;
- exact candidate artifact/APK-entry identity contract;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK: `CD73E1E5BFB85B409A3965691E3127535E78F2966E6FA190982618D4EC5B59F8`,
  72,837,768 bytes.
- Merged ARM64 core:
  `58C1A18D7B362FB061B6BAC446675053CD6F67A1257AE2D64097F2B7CA14906E`,
  1,304,325,912 bytes.
- Packaged ARM64 core:
  `39989CFF0155373FF0FF235706593A9ADA67317E9B779950F813DBC2F9EF99F0`,
  62,989,144 bytes.

This is a host-verified reduction in timer hot-path work, not measured FPS,
stability, power, or temperature credit.