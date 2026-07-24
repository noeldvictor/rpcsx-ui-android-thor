# Thor PPU command minimal handoff ordering

Date: 2026-07-23

## Outcome

Android PPU asynchronous-command queues now use the minimum ordering required
on both data handoffs:

- release-only FIFO completion pairs with acquire-only producer reservation for
  safe slot reuse;
- release-only command-head publication pairs with acquire-only head exchange
  for payload delivery.

Generic `lf_fifo` and desktop PPU behavior remain unchanged. The earlier fully
relaxed Android reservation candidate is superseded because it preserved atomic
counter uniqueness but did not establish a C++ happens-before edge before raw
tail-slot reuse. That candidate was host-only and was never installed or run on
Thor.

This is primarily a stability correction while preserving the optimized
barrier budget. Relative to generic upstream ordering, reservation still drops
its unnecessary release half, command-head publication remains a release
store, head consumption drops its unnecessary release half, FIFO position and
post-head tail reads remain relaxed, and completion remains release-only. This
is not a measured FPS, temperature, power, flicker, gameplay, stability, or
end-to-end speed result.

## Two-handoff correctness proof

### Slot reuse: completion release to reservation acquire

`cmd_pop` clears consumed command tails and has already cleared the head. Its
successful `pop_end_release` CAS is sequenced after those clears. A producer's
`push_begin_acquire` RMW acquires that completion before writing any newly
reserved slot.

All operations on the 64-bit FIFO control word are RMWs. If multiple producers
reserve after a completion, their RMWs remain in the completion's release
sequence, so an acquire reservation that reads a later producer RMW still
synchronizes with the release completion that made the storage reusable. This
establishes happens-before for the raw tail clears and subsequent raw tail
writes while preserving unique reservations and empty-queue reset behavior.

A fully relaxed reservation had atomic modification order but no synchronizes-
with edge for those non-atomic tail accesses. `__ATOMIC_ACQUIRE` is therefore
the minimum correct producer order; `__ATOMIC_RELEASE` remains unnecessary
because element publication is separate.

### Payload delivery: head release to head acquire

After reserving, a producer writes relaxed command tails and release-stores the
head last. `cmd_wait` atomically exchanges the head with zero using acquire
ordering. If it observes a command, that acquire synchronizes with publication
and covers all preceding tail writes. If it observes zero, no payload is
consumed; a racing later release publication remains visible to a later probe.

The exchange's zero write publishes no consumer data and needs no release half.
The later release completion orders that head clear and all tail clears before
slot reuse. Post-head tail loads and consumer-owned position reads can therefore
remain relaxed.

The final Android chain is:

```text
slot reuse:      CASL completion -> LDADDA reservation
payload publish: STLR head       -> SWPA head exchange
position/tails:  LDR
```

## Exact ARM64 proof

Immediate predecessor merged core
`39F1C9BF94F17A1E29F1CEC32B7DB20B1EFDA9C0464C60DA5B7ECFE62BE30143`
used a fully relaxed reservation and acquire/release head exchange:

```text
3540b10: ldadd x9, x23, [x8]
353cf00: swpal xzr, x26, [x8]
```

Successor merged core
`888767BB876410E18D669509FD4C7F67AEDF8F71BEA5E236C76EF3F3746869E9`
emits the minimal paired ordering:

```text
3540b10: ldadda x9, x23, [x8]   // acquire slot reuse
3540c0c: stlr   x9, [x8]        // release payload publication
353cf00: swpa   xzr, x26, [x8]  // acquire payload consumption
353d0d4: casl   x8, x10, [x11] // release slot completion
```

The previously verified relaxed position/tail `LDR` instructions remain, and
`ppu_thread::cpu_task` remains `0x1ec4` bytes.

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` now rejects a fully
  relaxed reservation, requires acquire-only reservation/head exchange, and
  preserves every desktop/upstream, publication, completion, position, tail,
  and notification invariant.
- ARM64 native build returned `BUILD SUCCESSFUL`.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL`.
- Exact merged ARM64 disassembly confirmed `LDADDA`, `STLR`, `SWPA`, and `CASL`
  at the intended PPU FIFO sites.
- All `69/69` non-artifact host contracts passed before repinning.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed after repinning.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `D9CFF3E8EEB622757A239E143CB079E5AEE484E309609B5B5DFC1D67B6FF7DCD`,
  `72,838,040` bytes.
- Merged core: `888767BB876410E18D669509FD4C7F67AEDF8F71BEA5E236C76EF3F3746869E9`,
  `1,304,308,416` bytes.
- Stripped/packaged core:
  `BCF54B18A477F27A5F14A2C6F55AFA62285ADF4F525EA55160955A3DD894E3A9`,
  `62,989,000` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
