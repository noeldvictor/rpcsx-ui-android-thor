# Thor RSX method command release store

Date: 2026-07-23

## Outcome

The Android PPU command-ready store/wake sequence is now centralized in
`ppu_thread::notify_cmd_ready()`. The existing RSX VBlank and flip-handler
callers use it, and the two remaining RSX method producers now use the same
contract:

- `rsx::flip_command`, bound to `GCM_FLIP_COMMAND` and executed on frame flips;
- `rsx::user_command`, bound to `GCM_SET_USER_COMMAND` for guest RSX callbacks.

Android release-stores the level-triggered flag and calls `notify_one`. Desktop
retains the original sequentially consistent store followed by `notify_one`.
The cold interrupt-join and PPU-thread-start producers remain unchanged and are
outside this RSX hot-path round.

This is host-verified `stackable-cpu-pressure`. It removes two more atomic
read-modify-writes/acquire barriers and centralizes the already proven ordering
rule. It is not a measured FPS, temperature, power, flicker, gameplay,
stability, or end-to-end speed result.

## Ordering and code structure

Every converted caller first invokes `ppu_thread::cmd_list`, which now release-
publishes the authoritative command head, and only then calls
`notify_cmd_ready`. The helper:

1. release-stores `cmd_notify = 1` on Android;
2. retains `cmd_notify.store(1)` on desktop;
3. calls `cmd_notify.notify_one()` after the flag is visible.

Consumers either acquire/exchange the command head or exchange/recheck the
notification flag. Producers never use the old flag value, so an atomic swap
is unnecessary. Moving this operation onto `ppu_thread` also prevents the
RSXThread and rsx_methods implementations from drifting into different store
and wake ordering.

The focused contract proves exactly four Android helper callers: VBlank,
RSX flip handler, GCM flip command, and RSX user command. It also proves the
upstream desktop checkout retains two original RSXThread and two original
rsx_methods store/wake pairs.

## Exact ARM64 proof

Immediate predecessor merged core
`F128D577451F1A734EAFE6F26A6FAA9BAA046DE96BB4199F5FEF213E83EC5B01`
had the release-published PPU queue head but retained two method-level swaps:

```text
386cf58: bl    ppu_thread::cmd_list
386cf74: swpal w10, w8, [x8]
386cf84: bl    atomic_wait_engine::notify_one

386d0e4: bl    ppu_thread::cmd_list
386d100: swpal w10, w8, [x8]
386d110: bl    atomic_wait_engine::notify_one
```

Successor merged core
`3B61B2654F24D186998B3D8E056E866EC147A52F3D65C22D4FA13C868C8B2178`
keeps the queue-before-flag-before-wake sequence with release stores:

```text
386cf58: bl   ppu_thread::cmd_list
386cf74: stlr w8, [x0]
386cf78: bl   atomic_wait_engine::notify_one

386d0e4: bl   ppu_thread::cmd_list
386d100: stlr w8, [x0]
386d104: bl   atomic_wait_engine::notify_one
```

The prior hot-path results remain intact in the same packaged core:

```text
3540b4c: stlr x9, [x8]   // PPU command queue head
3835a10: stlr w8, [x0]   // VBlank command-ready flag
3837398: stlr w24, [x0]  // RSX flip-handler command-ready flag
```

## Verification

- Updated focused contract:
  `tools/test_thor_es_frame_poll_wait.ps1` passed, including the two new method
  producers and unchanged desktop baseline.
- Optimized ARM64 native build completed; after the first host command window
  expired during linking, the linker finished and an incremental confirmation
  returned `BUILD SUCCESSFUL` in one second.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL` in nine seconds.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `0CF815116B1F1A962FD5548365E828674887A9A15329EF1922C3AED99649763C`,
  `72,838,380` bytes.
- Merged core: `3B61B2654F24D186998B3D8E056E866EC147A52F3D65C22D4FA13C868C8B2178`,
  `1,304,308,000` bytes.
- Stripped/packaged core:
  `6D6C3C62CFA091F56441AC31A959A247BD8536FA45300512170B900B2F8790E1`,
  `62,988,904` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains necessary before any measured speed,
stability, flicker, or thermal credit.
