# Thor frame-wait stats-free Fast mode

Date: 2026-07-23

## Outcome

The Android Eternal Sonata frame-poll waiter now has two explicit enabled modes:

- `Fast` runs the existing bounded wait state machine without per-event diagnostic counters or logging.
- `Wait` retains the full counters and sampled diagnostic logger for investigation.

The managed `ThorCoolTitle` and `ThorCoolGameplay` profiles now select `Fast`.
`Off` and the existing `Wait` spelling retain their prior meanings. This is
host-verified `stackable-cpu-pressure` work. It is not measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed credit.

## Correctness boundary

`try_thor_es_frame_poll_wait_impl<TrackStats>` owns one functional state
machine. `Fast` instantiates it with `TrackStats=false`; `Wait` calls an
outlined `TrackStats=true` diagnostic specialization. The functional state is
unchanged:

- `ppu_id` and `object_addr` retain identity/reset behavior;
- `normal_pre_counter`, `completed_vblank`, and `armed` retain fallback/rearm behavior;
- exact title, main-PPU, CIA, sleep-duration, object, divisor, threshold, renderer, and registration gates remain;
- the one-millisecond token wait, relaxed registration stores, final acquire publication read, cached 0-500 us grace, continuous rearm, and original timer fallback remain.

Only `calls`, event/wake/timeout/progress counters, fallback/rearm counters,
`last_log_us`, and their logger probes are compiled out of `Fast`. The state is
still bulk-zeroed when PPU/object identity changes, but the Fast steady-state
path performs no diagnostic-field counter update or logger call.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes recorded:

| Route | Calls | Event waits | Grace waits | Progress after grace | Fallback sleeps |
|---|---:|---:|---:|---:|---:|
| Title | 34,612 | 34,542 | 2,456 | 1,136 | 70 |
| First battle | 105,181 | 105,145 | 9,580 | 4,595 | 36 |
| Options | 33,485 | 33,484 | 3,209 | 1,229 | 1 |
| Total | 173,278 | 173,171 | 15,245 | 6,960 | 107 |

Every event wait records exactly one handler wake or timeout in diagnostic
mode. Across the three saved routes, Fast therefore removes a known minimum of
541,932 diagnostic increment sequences: 173,278 calls, 173,171 event waits,
173,171 wake/timeout outcomes, 15,245 grace iterations, 6,960 post-grace
progress events, and 107 fallback sleeps. This excludes additional VBlank,
continuous-rearm, and post-event progress counters, so it is a conservative
host-side relevance count. Each linked increment is a load/add/store sequence.

## Exact ARM64 proof

Exact final merged core
`97A485B5428ABD32E8DC41069017D0C4E4A3104A435E849FA15B94CF91C735CB`
emits `sys_timer_usleep` as `0x5b4` bytes, down from the predecessor's `0x6ec`.
The full `Wait` diagnostic specialization is outlined as a separate `0x3b4`
function. The mode branch is at `0x16d1a90`; the steady-state Fast span is
`0x16d1b90..0x16d1c8c`.

```text
16d1bec: ldr   w20, [x8]
16d1bf0: strb  w9,  [x12, x21]
16d1bf4: ldr   w9,  [x8]
...
16d1c08: mov   w2,  #0x3e8
16d1c14: bl    thread_ctrl::wait_on(..., 1000)
16d1c20: strb  wzr, [x12, x21]
16d1c24: ldar  w9,  [x8]
...
16d1c50: mov   w0,  #0x64
16d1c58: bl    thread_ctrl::wait_for(...)
...
16d1c88: str   x8,  [x9, #0x568]
```

An exact disassembly assertion confirmed that this Fast steady-state span
contains none of the diagnostic state offsets, counter increment patterns, or
`log_thor_es_frame_poll_wait` calls. The outlined Wait function retains both
diagnostic increment sequences and logger calls.

## Verification

Passed:

- Android ARM64 RelWithDebInfo native build;
- ThorTest ARM64-only APK build;
- source contract proving all 13 diagnostic increments are within 12 `if constexpr (TrackStats)` scopes and fallback rearm is diagnostic-only;
- exact ARM64 Fast/Wait codegen assertion;
- cool-title profile and capture analyzer contracts;
- exact ARM64 APK and merged-core identity contract;
- exact candidate artifact/APK-entry identity contract; and
- all `70/70` `tools/test_thor_*.ps1` host contracts.

Exact host-only artifact:

- APK: `528BFEE0015C78FC4C0E2460449A34E34DB765581308D187FAF10CF869754222`, 72,838,016 bytes.
- merged ARM64 core: `97A485B5428ABD32E8DC41069017D0C4E4A3104A435E849FA15B94CF91C735CB`, 1,304,313,728 bytes.
- packaged ARM64 core: `ED62C46D9AF72B6375837124C29E3ED57C692A7C16448B29A8D0FAB34CA7A4A8`, 62,989,896 bytes.

No ADB query, install, launch, temperature poll, wait, or other Thor contact
occurred. The APK is host-built and device-unmeasured.