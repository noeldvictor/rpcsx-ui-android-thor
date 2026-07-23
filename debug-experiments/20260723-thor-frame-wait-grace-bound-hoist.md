# Thor frame-wait grace-bound hoist

Date: 2026-07-23

## Outcome

The Android Eternal Sonata VBlank-assisted frame-poll consumer now loads its
static 0-500 us post-handler grace bound once per needed grace sequence instead
of calling the accessor again after every 100 us wait iteration. If the guest
counter already advanced, the conditional expression still makes zero
accessor calls.

The title/main-PPU/call-site/object gates, release completion token, acquire
observation, single-waiter registration/wake, one-millisecond event bound,
100 us grace steps, counter checks, continuous rearm, notification timing, and
fallback are unchanged.

This is host-verified `stackable-cpu-pressure` work. It is not a measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed result.

## Dynamic relevance

The saved correctness-clean continuous-rearm routes recorded both grace wait
iterations and sequences that ended in counter progress. The previous loop
called the accessor after every iteration whose counter still had not changed.
Hoisting therefore removes exactly `handler_grace_waits -
counter_progress_after_grace` repeated calls:

- title: `2,456 - 1,136 = 1,320` calls removed;
- first battle: `9,580 - 4,595 = 4,985` calls removed;
- Options: `3,209 - 1,229 = 1,980` calls removed.

The remaining one call per needed sequence loads the same process-static,
clamped property value. A sequence where the counter is already different
retains the old short-circuit behavior and makes no call.

## Change

Before:

```cpp
for (u64 waited_us = 0;
     after_counter == counter &&
     waited_us < get_thor_es_frame_poll_handler_grace_us();
     waited_us += 100) {
```

After:

```cpp
const u64 handler_grace_us =
    after_counter == counter ? get_thor_es_frame_poll_handler_grace_us() : 0;
for (u64 waited_us = 0;
     after_counter == counter && waited_us < handler_grace_us;
     waited_us += 100) {
```

The focused contract locks the conditional hoist and rejects a future accessor
call in the loop condition.

## Exact ARM64 proof

Predecessor merged core
`269A551BF96A112886FA50FEDCA0C6F66E8C03976D8BA0C379F5808B03506628`
compiled `sys_timer_usleep` to `0x6f0` bytes and emitted two accessor call
sites:

```text
16d1cd0: bl 0x16d26a0 <get_thor_es_frame_poll_handler_grace_us>
...
16d1d08: bl 0x16d26a0 <get_thor_es_frame_poll_handler_grace_us>
```

Successor merged core
`D0A038D4E681CC97CF76E4E021D377854D0AC1CD1054A0966BAFB32B3C2051C0`
compiles the function to `0x6ec` bytes and retains only the first call:

```text
16d1cd0: bl   0x16d26a0 <get_thor_es_frame_poll_handler_grace_us>
16d1d0c: b.lo 0x16d1ce4
```

The loop-back target is after the accessor call, so repeated 100 us grace waits
reuse the register-held bound. The function shrank by four bytes.

## Verification

- Focused frame-poll wait contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact packaged-core accessor-call count: one.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `69/69` Thor host contracts: passed before documentation and repeated
  before commit.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `9DC30B9CBCF930899B7F9147ACF553AC41424F38E2341C5B92BF062EF879698E`,
  72,838,240 bytes.
- merged ARM64 core:
  `D0A038D4E681CC97CF76E4E021D377854D0AC1CD1054A0966BAFB32B3C2051C0`,
  1,304,307,832 bytes.
- packaged ARM64 core:
  `D7B9F75D065E7A9C9EBCF06641DCF329DA7F293F1FBAF16D5327B00A6885FE02`,
  62,988,904 bytes.

No ADB query, install, launch, temperature poll, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
