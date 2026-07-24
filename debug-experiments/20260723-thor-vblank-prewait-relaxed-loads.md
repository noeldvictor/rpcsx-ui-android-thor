# Thor VBlank pre-wait relaxed token loads

Date: 2026-07-23

## Outcome

The Android Eternal Sonata frame-poll waiter now observes its completion token
with relaxed loads for the two pre-wait control decisions. Non-Android builds
retain the prior implicit acquire loads. The final post-wait acquire load,
release-published completion token, relaxed single-waiter registration stores,
one-millisecond bound, handler grace, continuous rearm, notification, exact
title/main-PPU/call-site/object gates, and original timer fallback are
unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes two acquire
barriers from every bounded event wait. It is not a measured FPS, temperature,
power, flicker, gameplay, stability, or end-to-end speed result.

## Why only the pre-wait loads are relaxed

The first token snapshot and the immediate recheck only decide whether the
main PPU should enter a bounded wait. Neither load is used to consume guest
handler data. Android therefore uses `atomic_t<u32>::observe()` at those two
sites.

The wait engine receives the snapshot as its expected value. The Linux/Android
futex path compares the live word with that value at wait entry and returns on
a mismatch; the generic path checks the same condition through `ptr_cmp`.
Consequently:

- a changed relaxed recheck skips the wait;
- a stale relaxed recheck can enter `wait_on`, whose expected-value check
  returns when the token has already changed;
- the existing one-millisecond timeout remains the final backstop if the
  advisory producer work or notification is missed.

Acquire ordering is still required after the wait. The final implicit atomic
load remains immediately before the guest counter read. When it observes the
producer's release token increment, it publishes the queued guest handler's
writes to the main PPU before counter progress is examined. If it does not
observe progress, the existing grace/rearm/fallback path remains authoritative.

The implementation is localized in `sys_timer.cpp` through
`observe_thor_es_vblank_wait_token`: Android returns `wait_token.observe()`,
while desktop returns the prior implicit atomic load.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes reached:

- title: 34,542 bounded event waits, or 69,084 pre-wait acquire barriers;
- first battle: 105,145 waits, or 210,290 barriers;
- Options: 33,484 waits, or 66,968 barriers.

The three saved routes therefore contain 173,171 waits and 346,342 targeted
acquire barriers. No device route was rerun for this host-only successor.

## Exact ARM64 proof

The exact predecessor merged core
`95E55A24ACCE4B79A6CF619BD5D2FCA74BD022AFA23E7DBB451BED344D59B103`
emitted three adjacent completion-token `LDAR` instructions. Exact successor
merged core
`562142F36E6B9BB3901192705B5E2633F34ED84CE2F4F8941FA98B02C750C0E0`
emits:

```text
16d19b0: ldr   w22, [x20]
16d19b4: strb  w8,  [x23, x24]
16d19b8: ldr   w8,  [x20]
...
16d19d0: bl    thread_ctrl::wait_on(..., 1000)
16d19d4: strb  wzr, [x23, x24]
16d19d8: ldar  w9,  [x20]
16d19dc: ldr   w8,  [x26, x28]
```

The two intended pre-wait loads change from `LDAR` to `LDR`. The final token
load remains `LDAR` before the guest counter load, both registration stores
remain `STRB`, the wait call retains its 1,000 us bound, and
`sys_timer_usleep` remains `0x6ec` bytes.

## Verification

- Focused frame-poll wait contract: passed, including exactly two relaxed
  pre-wait reads and an unchanged acquire post-wait source read.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact merged-core disassembly: intended `LDR`, `LDR`, wait, `LDAR` sequence;
  retained registration stores and 1 ms wait.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `70/70` `tools/test_thor_*.ps1` host contracts: passed.
- `git diff --check`: passed before documentation.

Exact host-only successor:

- APK: `71D9C0C20B3EC7DAD26D63DD62CB15DBA1E7C3F36AE472D1DE869618DD4E977B`,
  72,837,748 bytes.
- merged ARM64 core:
  `562142F36E6B9BB3901192705B5E2633F34ED84CE2F4F8941FA98B02C750C0E0`,
  1,304,307,320 bytes.
- packaged ARM64 core:
  `EC383041E65311476D2FD64EB1565995F1E4CDF3E4B360460EBD6577FF8897CF`,
  62,988,856 bytes.

No ADB query, install, launch, temperature poll, wait, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
