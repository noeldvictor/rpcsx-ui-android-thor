# Thor VBlank completion release publication

Date: 2026-07-23

## Outcome

The Android Eternal Sonata VBlank-assisted frame-poll path now publishes each
handler-completion token with a release atomic increment instead of a
sequentially consistent increment. The waiter's acquire token loads, exact
title/main-PPU/call-site/object gates, one-millisecond bound, post-handler
grace, single-waiter registration, continuous rearm, notification, and
fallback are unchanged.

This is host-verified `stackable-cpu-pressure` work. It removes an unnecessary
acquire barrier from a repeated producer operation. It is not a measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed result.

## Why this is dynamically relevant

Saved correctness-clean continuous-rearm captures show that the completion
publication is not a cold-path operation:

- title route: 2,703 VBlanks and 1,962 handler wakes;
- first battle: 8,719 VBlanks and 7,227 handler wakes;
- Options: 2,704 VBlanks and 2,341 handler wakes.

Each handler wake can publish the token once. The fallback path can also
publish when no queued guest handler is used.

## Change and ordering argument

- Android calls `publish_vblank_wait_completion` at both completion sites.
- The helper uses `__atomic_fetch_add(..., __ATOMIC_RELEASE)` on Android.
- Desktop keeps the original `atomic_t` sequentially consistent increment.
- The producer publishes preceding guest-handler writes but consumes no data
  through the token, so producer acquire ordering is unnecessary.
- The RMW remains atomic. This preserves a single modification order and
  release sequences if the queued-handler and fallback producers overlap.
- `sys_timer_usleep` retains acquire token loads before it checks counter
  progress, preserving visibility of the completed guest handler's writes.

A non-atomic load/store increment was explicitly rejected because the queued
handler callback and fallback producer can overlap if handler state changes.

## ARM64 code-generation proof

In exact predecessor merged core
`8083882174649FC66F828C9DBD8AEBCEB26F1D3288BF16AC4B48FFF5F58E636D`,
both completion-token sites emitted `LDADDAL`:

- `rsx::thread::post_vblank_event`: `0x38359a4`;
- queued handler callback: `0x383fb64`.

In exact successor merged core
`85463279163412A60897DEEDFD68F6F7CB3AFB5A4C44B631499F20F79B53E3B5`,
the same sites emit release-only `LDADDL`:

```text
38359a4: ldaddl w8, w8, [x0]
383fb64: ldaddl w9, w9, [x0]
```

The unrelated 64-bit `vblank_count` increment remains `LDADDAL` at
`0x3835934`. `sys_timer_usleep` remains `0x6f0` bytes and retains its acquire
completion-token loads, including `LDAR` at `0x16d1a50`, `0x16d1a58`, and
`0x16d1a78`.

## Verification

- `tools/test_thor_es_frame_poll_wait.ps1`: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest APK build: passed.
- Exact merged-core disassembly: two completion `LDADDL`; waiter `LDAR` intact.
- Exact candidate artifact contract: passed.
- All `69/69` `tools/test_thor_*.ps1` host contracts: passed.
- `git diff --check`: passed before ledger creation and repeated before commit.

Exact host-only successor:

- APK: `6ED1D40A351DDE1290B2FFBEBDCF186B5C32B47A4EF3D1880A0F792A298C8BA1`,
  72,838,248 bytes.
- merged ARM64 core:
  `85463279163412A60897DEEDFD68F6F7CB3AFB5A4C44B631499F20F79B53E3B5`,
  1,304,307,440 bytes.
- packaged ARM64 core:
  `D3ACADBF80E776579876A8A9632521C861B76B64A13D8E8969086DE43BA81FBC`,
  62,988,904 bytes.

No ADB query, install, launch, or temperature poll occurred. The APK is
host-built and device-unmeasured.
