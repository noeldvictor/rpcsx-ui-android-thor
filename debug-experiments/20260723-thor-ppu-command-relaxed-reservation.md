# Thor PPU command relaxed FIFO reservation

Date: 2026-07-23

## Outcome

Android PPU asynchronous-command producers now reserve FIFO positions with a
relaxed atomic fetch-add. The generic `lf_fifo::push_begin` and all desktop
callers retain the original sequentially consistent behavior; only
`ppu_thread::cmd_push` and `ppu_thread::cmd_list` route through the new
Android-only reservation.

This is host-verified `stackable-cpu-pressure`. It removes the acquire and
release barriers from the reservation RMW for every asynchronous PPU command
while retaining atomic uniqueness. It is not a measured FPS, temperature,
power, flicker, gameplay, stability, or end-to-end speed result.

## FIFO correctness proof

`lf_fifo` explicitly has no `push_end`: each element signals readiness on its
own. The PPU queue follows that contract:

1. `push_begin_relaxed` atomically reserves a unique counter range;
2. `cmd_list` writes command tails through relaxed element stores;
3. the command head is release-published last;
4. the consumer acquires and clears the head with `exchange(cmd64{})`;
5. the separate notification flag only controls sleeping and waking.

The reservation counter therefore does not publish element data and does not
need acquire/release ordering. Atomic modification order is sufficient for
unique positions and for its interaction with `pop_end`:

- if `pop_end` reads a control value before a concurrent reservation, its CAS
  either commits before the fetch-add or fails and retries after it;
- if `pop_end` clears equal push/pop counters to zero, a concurrent fetch-add
  occurs wholly before or after that atomic update and cannot be lost;
- 32-bit counter wrap and high-half pop updates remain one 64-bit atomic
  modification order;
- dynamic `lf_array` block publication uses its own pointer CAS/acquire path;
- `cmd_queue.size()` is diagnostic only and is not an element-ready test.

The Android method is exposed only under `#ifdef __ANDROID__`, and a local PPU
helper preserves the original `queue.push_begin(count)` on desktop. The focused
contract locks exactly two PPU relaxed-reservation calls, the generic default,
`pop_end` atomic update, separate head publication/consumer exchange, and the
unchanged upstream baseline.

## Exact ARM64 proof

Immediate predecessor merged core
`5EC8827E20697A4941798E5FEC1FE64E9D8CE64C22D1920ACF112D48F0BD1C80`
reserved `cmd_list` positions with acquire/release ordering:

```text
3540a4c: mov     w9, w20
3540a50: ldaddal x9, x23, [x8]
```

Successor merged core
`865A0B358DC3B141EEBD9D5CEB91894D494367760004A5EE84B5B0C2A72C5F44`
retains the atomic fetch-add and returned old position without barriers:

```text
3540a4c: mov   w9, w20
3540a50: ldadd x9, x23, [x8]
```

The authoritative synchronization points remain intact:

```text
3540b4c: stlr  x9, [x8]       // command-head publication
353cf40: stlr  wzr, [x28]     // notification clear
353cf64: swpal xzr, x8, [x8]  // consuming command-head exchange
```

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` reservation,
  publication, clear, pop/wrap, and desktop-baseline contract passed.
- The generic-header ARM64 build completed after the first host command window
  expired; an incremental confirmation returned `BUILD SUCCESSFUL` in one
  second.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL` in ten seconds.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `0B9B26FB6ABF7A8AEAAA83748FC1568AC23A06174A9C070BE9504F889290598B`,
  `72,838,104` bytes.
- Merged core: `865A0B358DC3B141EEBD9D5CEB91894D494367760004A5EE84B5B0C2A72C5F44`,
  `1,304,308,920` bytes.
- Stripped/packaged core:
  `EAC6FBC69FA5E957CB2D55BFE1DCAC74A50042379365E5075838E4ADD6E42FDD`,
  `62,988,904` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
