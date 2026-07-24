# Thor VBlank registration advisory loads

Date: 2026-07-23

## Outcome

Android VBlank production now treats the Eternal Sonata single-waiter
registration flag as the advisory work gate it is. The two live producer gates
use relaxed byte loads instead of acquire byte loads, and the queued guest
handler-completion callback no longer reloads the flag before notifying the
single waiter. Desktop retains its prior sequentially consistent flag reads.

The completion token remains a release atomic increment, the main PPU retains
acquire token loads, `notify_one()` remains single-waiter scoped, and the
one-millisecond wait bound, title/main-PPU/call-site/object gates, grace,
continuous rearm, and original timer fallback are unchanged.

This is host-verified `stackable-cpu-pressure` work. It is not a measured FPS,
temperature, power, flicker, gameplay, stability, or end-to-end speed result.

## Why the relaxed flag reads are safe

`vblank_waiter_registered` does not publish guest-handler data. It only tells
the RSX/VBlank producer whether optional completion-marker and wake work is
currently useful. Guest-handler writes are published by the release
`vblank_wait_token` increment and observed by the main PPU's acquire token
loads before it checks counter progress.

The complete race cases remain bounded:

- A current `true` observation queues or performs the completion work.
- A stale `false` skips optional work for that edge. The main PPU's atomic wait
  still expires after at most 1 ms, records the timeout, checks token/counter
  progress, and preserves the existing fallback/rearm behavior.
- A stale `true` can only queue an extra marker or notify. The token increment
  is atomic, and `notify_one()` is harmless when no waiter is live.
- The queued callback is created only after a registration observation. It now
  always notifies after its release token increment. If the original waiter
  timed out, there is either no waiter (a no-op) or a newer single waiter that
  can use the completed token. No second cross-core flag read is required.

The callback already incremented the completion token unconditionally once it
was queued; removing its flag recheck changes only whether `notify_one()` is
called. It cannot suppress or reorder guest-handler execution.

## Dynamic relevance

Saved correctness-clean continuous-rearm routes contain:

- title: 2,703 VBlank edges and 34,542 bounded event waits;
- first battle: 8,719 VBlank edges and 105,145 bounded event waits;
- Options: 2,704 VBlank edges and 33,484 bounded event waits.

Before this change, an HLE VBlank that observed a waiter issued one acquire
flag load when choosing the command list and another in the queued completion
callback. The successor issues one relaxed flag load at the producer gate and
none in the callback. The no-handler/non-HLE fallback gate is relaxed as well.

## Exact ARM64 proof

Predecessor merged core
`C354674DA1213F5F5D660BF48B99440529EF3B901712A99EAD164D305EC94B66`
emitted acquire byte loads at both `post_vblank_event` gates and in the queued
callback. The callback was `0x68` bytes.

Exact successor merged core
`69797EA423B9DA7B00CD6908165D30EDC48236E9D4DE15198FC3C62C6075A99E`
emits two plain registration loads in `post_vblank_event`:

```text
38359c8: ldrb  w9, [x20, #0x974]
3835a0c: ldrb  w8, [x20, #0x974]
```

There is no registration `LDARB` in that function. The queued callback shrinks
from `0x68` to `0x58` bytes and contains no registration load or conditional
branch. Its completion publication and wake remain adjacent:

```text
383fbe4: ldaddl w8, w8, [x0]
383fbe8: bl     0x15a3fc0 <atomic_wait_engine::notify_one(void const*)>
```

The exact main function remains `0x118` bytes. The release completion
increment, one-waiter notification target, release VBlank edge, and existing
PPU token acquire loads remain intact.

## Verification

- Focused frame-poll wait contract: passed.
- Android ARM64 RelWithDebInfo native build: passed.
- ThorTest ARM64-only APK build: passed.
- Exact merged-core disassembly: two registration `LDRB`, zero registration
  `LDARB`, `0x58` callback, and retained `LDADDL + notify_one`.
- Exact candidate artifact/APK-entry identity contract: passed.
- All `70/70` `tools/test_thor_*.ps1` host contracts: passed.
- `git diff --check`: passed before documentation.

Exact host-only successor:

- APK: `17C74C6B450413F3AD45377C71C6CE1D354F74706E3DA6EAB166CB7959A195FD`,
  72,837,732 bytes.
- merged ARM64 core:
  `69797EA423B9DA7B00CD6908165D30EDC48236E9D4DE15198FC3C62C6075A99E`,
  1,304,307,160 bytes.
- packaged ARM64 core:
  `49F32203DF5DD37F1B182251C24B88D3E57190298731C91B8009EC0B26F11502`,
  62,988,856 bytes.

No ADB query, install, launch, temperature poll, wait, or other Thor contact
occurred. The APK is host-built and device-unmeasured.
