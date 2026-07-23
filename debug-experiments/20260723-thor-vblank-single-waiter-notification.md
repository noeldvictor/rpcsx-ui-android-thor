# Thor VBlank single-waiter notification

Date: 2026-07-23

## Outcome

The Android Eternal Sonata VBlank-assisted frame-poll path now wakes its exact
single registered main-PPU waiter with `notify_one()` instead of broadcasting
with `notify_all()`. Desktop retains the original broadcast behavior. The
release completion increment, acquire waiter loads, title/main-PPU/call-site
and object gates, one-millisecond bound, post-handler grace, continuous rearm,
notification timing, and fallback are unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes unnecessary
hashtable scanning, handle collection, and batched wake processing from a
repeated producer operation. It is not a measured FPS, temperature, power,
flicker, gameplay, stability, or end-to-end speed result.

## Single-waiter proof

Repository-wide source inspection finds:

- one wait consumer: the exact BLUS30161 main-PPU path in
  `sys_timer_usleep`;
- one explicit registration flag: `vblank_waiter_registered`;
- two completion producers: the queued VBlank-handler callback and the
  no-handler/non-HLE fallback in `rsx::thread::post_vblank_event`.

The main PPU cannot execute two `sys_timer_usleep` calls concurrently. No other
source site waits on `vblank_wait_token`, so waking more than one waiter cannot
provide a semantic benefit. If a stale wait record has already timed out,
`notify_one` continues its slot search until it wakes a live waiter or finds
none.

Saved correctness-clean routes also show the wake path is frequent:

- title: 2,703 VBlanks and 1,962 handler wakes;
- first battle: 8,719 VBlanks and 7,227 handler wakes;
- Options: 2,704 VBlanks and 2,341 handler wakes.

## Change

`notify_vblank_waiter()` is inlined at both completion sites:

- Android calls `token.notify_one()`;
- non-Android calls `token.notify_all()`.

The producer still performs the release `LDADDL` token increment before the
wake. The consumer still observes the token with acquire loads. The helper
does not alter guest timing, completion ordering, or the one-millisecond
fail-safe.

## Exact ARM64 proof

Predecessor merged core
`85463279163412A60897DEEDFD68F6F7CB3AFB5A4C44B631499F20F79B53E3B5`
called `atomic_wait_engine::notify_all` at both completion sites:

```text
38359a8: bl 0x15a41a0 <atomic_wait_engine::notify_all>
383fb78: bl 0x15a41a0 <atomic_wait_engine::notify_all>
```

Successor merged core
`269A551BF96A112886FA50FEDCA0C6F66E8C03976D8BA0C379F5808B03506628`
calls `atomic_wait_engine::notify_one` instead:

```text
38359a4: ldaddl w8, w8, [x0]
38359a8: bl 0x15a4020 <atomic_wait_engine::notify_one>
383fb64: ldaddl w9, w9, [x0]
383fb78: bl 0x15a4020 <atomic_wait_engine::notify_one>
```

In the exact successor, `notify_one` is `0x180` bytes and reserves `0xa0`
bytes of stack. `notify_all` is `0x310` bytes and reserves `0x2b0` bytes in
two steps, including storage for up to 128 condition handles and multiple
wake/cleanup passes. The one-waiter implementation stops its slot search after
the first successful alert.

## Verification

- Focused frame-poll wait contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact merged-core call-target disassembly: passed.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `69/69` Thor host contracts: passed before documentation and repeated
  before commit.
- `git diff --check`: passed.

Exact host-only successor:

- APK: `85423E619149332D60918A4096E3418FB0CB7BB2216E6CEDCDFAB7DEA6B26163`,
  72,838,248 bytes.
- merged ARM64 core:
  `269A551BF96A112886FA50FEDCA0C6F66E8C03976D8BA0C379F5808B03506628`,
  1,304,307,696 bytes.
- packaged ARM64 core:
  `A5E8DCFB6ACF2CDF19FD1BD63DC8969632BBBB9312DAE1ED98A86D3225F3E18C`,
  62,988,904 bytes.

No ADB query, install, launch, temperature poll, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
