# Thor VBlank registration relaxed stores

Date: 2026-07-23

## Outcome

The Android Eternal Sonata frame-poll waiter now registers and clears its
single-waiter advisory flag with relaxed atomic byte stores instead of release
stores. Non-Android builds retain the prior release-store behavior. The flag
type, exact title/main-PPU/call-site/object gates, acquire completion-token
loads, one-millisecond bound, handler grace, continuous rearm, notification,
and original timer fallback are unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes two ordering
barriers from every bounded event wait. It is not a measured FPS, temperature,
power, flicker, gameplay, stability, or end-to-end speed result.

## Why relaxed stores are sufficient

`vblank_waiter_registered` is an advisory work hint. It does not publish guest
handler data or protect the completion token. The RSX/VBlank producer already
uses relaxed flag observations, while guest-handler writes are published by
the release `vblank_wait_token` increment and consumed through the main PPU's
acquire token loads.

The registration sequence remains:

1. acquire-load the current completion token;
2. atomically store registration `true`;
3. acquire-recheck the token;
4. wait only while the token is unchanged, for at most 1 ms;
5. atomically clear registration;
6. acquire-load the post-wait token before checking guest counter progress.

The complete races remain bounded:

- If VBlank completion advances between the first token load and the recheck,
  a changed recheck skips the wait. If that load still sees the old value, the
  atomic wait rechecks the token on entry and returns on mismatch, with the
  existing 1 ms timeout as the final backstop.
- If the producer misses a newly stored `true`, it skips optional completion
  work for that edge and the waiter follows the existing 1 ms timeout plus
  token/counter/fallback path. There is no unbounded wait.
- If the producer observes a stale `true` after clear, it can only issue an
  extra atomic completion marker or `notify_one`; both are already safe when no
  waiter is live.
- Store-release ordering cannot publish useful data here because the producer
  consumes no data through this flag. The completion token remains the sole
  guest-handler data handoff.

The implementation is localized in `sys_timer.cpp`. Android uses
`__atomic_store_n(..., __ATOMIC_RELAXED)` on the existing one-byte atomic
storage; desktop keeps `registered.release(value)`.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes reached:

- title: 34,542 bounded event waits, or 69,084 registration stores;
- first battle: 105,145 waits, or 210,290 stores;
- Options: 33,484 waits, or 66,968 stores.

The three saved routes therefore contain 346,342 registration stores. This is
substantially hotter than the per-VBlank producer gates optimized immediately
before it.

## Exact ARM64 proof

The exact predecessor used `atomic_t<bool>::release` for both registration
edges; the established ARM64 form for those source sites was `STLRB`. Exact
successor merged core
`95E55A24ACCE4B79A6CF619BD5D2FCA74BD022AFA23E7DBB451BED344D59B103`
emits plain atomic byte stores in `sys_timer_usleep`:

```text
16d19b0: ldar  w22, [x20]
16d19b4: strb  w8,  [x23, x24]
16d19b8: ldar  w8,  [x20]
...
16d19d0: bl    thread_ctrl::wait_on(..., 1000)
16d19d4: strb  wzr, [x23, x24]
16d19d8: ldar  w9,  [x20]
```

There is no registration `STLRB` in the linked function. The three adjacent
completion-token loads remain `LDAR`, the wait call retains its 1,000 us bound,
and `sys_timer_usleep` remains `0x6ec` bytes.

## Verification

- Focused frame-poll wait contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact merged-core disassembly: two intended registration `STRB`, zero
  registration `STLRB`, retained `LDAR` token sequence and 1 ms wait.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `70/70` `tools/test_thor_*.ps1` host contracts: passed.
- `git diff --check`: passed before documentation.

Exact host-only successor:

- APK: `A166ACE9728ADAEDEE21B045D37058ABA86B0A9403FE8D3C8B90DDB06C682964`,
  72,837,756 bytes.
- merged ARM64 core:
  `95E55A24ACCE4B79A6CF619BD5D2FCA74BD022AFA23E7DBB451BED344D59B103`,
  1,304,307,080 bytes.
- packaged ARM64 core:
  `969328CD78FFCBA9B2A91B353939C7CF7A562152CE070EA51BB8300D2F6710FD`,
  62,988,856 bytes.

No ADB query, install, launch, temperature poll, wait, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
