# Thor PPU command notification clear release store

Date: 2026-07-23

## Outcome

Android now clears `ppu_thread::cmd_notify` after a command wait with a one-way
release store instead of a sequentially consistent atomic exchange. Desktop
retains the original `cmd_notify = 0` behavior.

This completes the host-side producer/consumer notification cleanup as a
separate, bisectable round. It is host-verified `stackable-cpu-pressure`: one
read-modify-write and acquire barrier is removed after every PPU command wait.
It is not a measured FPS, temperature, power, flicker, gameplay, stability, or
end-to-end speed result.

## Race and ordering proof

The notification flag carries no payload. Every producer queues a command first
and only then publishes `cmd_notify = 1` and wakes the waiter. The queue head is
the authoritative payload publication:

- producers release-publish the command head after any relaxed tail writes;
- `cmd_wait` consumes that head with `exchange(cmd64{})`;
- after a wait and flag clear, the loop immediately retries the same acquiring
  head exchange.

Clearing the level flag therefore does not need the old flag value or acquire
ordering. `notify.release(0)` remains an atomic modification and preserves the
same flag modification order without a read-modify-write.

The potential overlap cases remain safe:

- If a producer stores `1` before the consumer clears, the clear may win, but
  the already-published command head is found on the immediate loop retry.
- If a producer stores `1` after the clear, the retry sees either the command
  head or a nonzero flag before sleeping.
- If multiple producers reserve queue positions out of completion order, the
  consumer cannot pass an unpublished zero head; the producer that publishes
  the older head also stores/wakes after publication.
- `atomic_wait_engine::wait` returns to the clear and retry path, while the
  consuming queue-head `SWPAL` remains unchanged.

The focused host contract locks the queue-head acquire, wait, one-way clear,
loop order, exact single clear call, unchanged desktop baseline, and absence of
the direct Android sequentially consistent clear.

## Exact ARM64 proof

Immediate predecessor merged core
`3B61B2654F24D186998B3D8E056E866EC147A52F3D65C22D4FA13C868C8B2178`
cleared the notification flag with an atomic swap:

```text
353cf40: swpal wzr, w8, [x28]
353cf44: add   x8, x19, #0x970
353cf64: swpal xzr, x8, [x8]  // consuming command-head exchange
```

Successor merged core
`5EC8827E20697A4941798E5FEC1FE64E9D8CE64C22D1920ACF112D48F0BD1C80`
uses a release store for the flag clear while retaining the consuming exchange:

```text
353cf40: stlr  wzr, [x28]
353cf44: add   x8, x19, #0x970
353cf64: swpal xzr, x8, [x8]  // unchanged consuming command-head exchange
```

The wait engine still returns directly to the clear/retry path:

```text
353d0fc: bl atomic_wait_engine::wait
353d100: b  0x353cf40
```

The prior producer release stores at GCM flip `0x386cf74` and RSX user command
`0x386d100` also remain intact.

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` publication/clear
  contract passed.
- Optimized ARM64 native build returned `BUILD SUCCESSFUL` in 58 seconds.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL` in nine seconds.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `98D15FF39E311F9D75042A30332D3842DBD5286B2BB8DA37E289E22D30AD315D`,
  `72,838,304` bytes.
- Merged core: `5EC8827E20697A4941798E5FEC1FE64E9D8CE64C22D1920ACF112D48F0BD1C80`,
  `1,304,308,184` bytes.
- Stripped/packaged core:
  `286FD0EB4901F326CF31F2D26CF38D5F104A11C1256376D4B9BA890651CCA51D`,
  `62,988,904` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
