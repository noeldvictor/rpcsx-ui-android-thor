# Thor PPU command release-only FIFO completion

Date: 2026-07-23

## Outcome

Android PPU asynchronous-command consumption now completes FIFO ranges with a
release-only compare/exchange. Generic `lf_fifo::pop_end` and all desktop
callers retain the original sequentially consistent atomic operation; only
`ppu_thread::cmd_pop` routes through the new Android-only completion method.

This is host-verified `stackable-cpu-pressure`. It removes the unnecessary
acquire load and acquire half of the completion CAS from every processed PPU
command range while preserving the release ordering required before an empty
queue can reset and reuse its slots. It is not a measured FPS, temperature,
power, flicker, gameplay, stability, or end-to-end speed result.

## FIFO correctness proof

The PPU command queue separates payload synchronization from position
accounting:

1. a producer atomically reserves a unique position range;
2. it writes relaxed command tails and release-publishes the command head;
3. the consumer acquires and clears the command head with
   `exchange(cmd64{})` before processing it;
4. `cmd_pop` clears the consumed tail slots;
5. completion advances the FIFO pop counter and may reset equal push/pop
   counters to zero.

The completion RMW does not consume producer payload, so it does not need
acquire ordering. It must retain release ordering: when completion resets an
empty queue to zero, a producer may immediately reuse slot zero, and all old
tail clears must be visible before that reuse. `pop_end_release` therefore uses
a relaxed initial control-word load, a strong release compare/exchange, and a
relaxed failure order.

Concurrent reservation cannot be lost because both operations share the same
64-bit atomic modification order. A reservation that wins before the CAS makes
the CAS fail and retry with the updated control word; a reservation that wins
after the CAS increments the committed state. Counter wrapping and empty-queue
reset remain identical to generic `pop_end`.

The Android method is exposed only under `#ifdef __ANDROID__`, and a local PPU
helper preserves `queue.pop_end(count)` on desktop. The focused contract locks
the exact success/failure memory orders, the tail-clear-before-completion
sequence, one PPU completion call, the generic implementation, and the
unchanged upstream baseline.

## Exact ARM64 proof

Immediate predecessor merged core
`865A0B358DC3B141EEBD9D5CEB91894D494367760004A5EE84B5B0C2A72C5F44`
used an acquire load and acquire/release CAS in standalone
`ppu_thread::cmd_pop`:

```text
353eb8c: ldar  x10, [x22]
...
353ebac: casal x9, x11, [x22]
```

Successor merged core
`8E486141D81AE27EFB7110A7DD0EF019EB4CF23410C0173FBB44A8E845BD0807`
inlines the completion into `ppu_thread::cpu_task`; a representative command
route is:

```text
353d0cc: ldar xzr, [x8]      // existing queue-position acquire remains
353d0d0: ldr  x10, [x19, #0x970]
...
353d0f0: casl x9, x11, [x8]
```

Other inlined `cmd_pop` routes use the same `LDR` plus `CASL` sequence. The
existing acquire that reads the command position remains, while the second
acquire load and the completion CAS acquire half are removed.

## Verification

- Focused `tools/test_thor_ppu_command_publication.ps1` reservation,
  publication, completion, clear, tail-ordering, and desktop-baseline contract
  passed.
- ARM64 native build returned `BUILD SUCCESSFUL`.
- ARM64-only Thor APK packaging returned `BUILD SUCCESSFUL`.
- Exact merged ARM64 disassembly confirmed `LDR` plus release-only `CASL` at
  the PPU FIFO completion sites.
- All `70/70` `tools/test_thor_*.ps1` host contracts passed.
- Candidate artifact identity contract passed, including the packaged APK
  entry hash.

Exact host artifacts:

- APK: `C48FF787A7CA15DDB65EFD4BC5FD3505B102DC732CBF2132595C3DFFCF9636B0`,
  `72,838,072` bytes.
- Merged core: `8E486141D81AE27EFB7110A7DD0EF019EB4CF23410C0173FBB44A8E845BD0807`,
  `1,304,306,800` bytes.
- Stripped/packaged core:
  `0EFE60AFB5FF2B25A6D3BB2739FF192CE2C40B2D7800FC13D71D17AF411CB8B3`,
  `62,989,000` bytes.

## Device status

Thor was not contacted: no ADB query, install, launch, temperature poll, wait,
or device load occurred. A later explicitly authorized, independently cool
field/menu/battle comparison remains required before any measured speed,
stability, flicker, or thermal credit.
