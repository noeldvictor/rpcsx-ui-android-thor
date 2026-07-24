# Thor Android SPU RSX-lock config relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in the SPU DMA/list
paths' RSX reservation-lock selection. Thor was not contacted.

## Baseline

`spu_thread::do_dma_transfer()` and `spu_thread::do_list_transfer()` decide
whether PUT traffic needs an RSX reservation lock from:

- `strict_rendering_mode`: non-dynamic, default `false`;
- `rsx_fifo_accuracy`: non-dynamic, default `fast`; and
- the already-relaxed accurate-DMA selector plus the existing transfer/address
  gates.

The first two settings select a lock policy. They do not publish DMA payload,
reservation state, queue entries, barriers, fences, timestamps, or
notifications.

The generic ordered conversions emitted four target acquire loads:

| Function | Size | All `LDAR`/`LDARB` sites | Target sites |
|---|---:|---:|---:|
| `spu_thread::do_dma_transfer` | `0x1854` | 38 | 2 |
| `spu_thread::do_list_transfer` | `0x1be0` | 12 | 2 |
| Total | | 50 | 4 |

The predecessor artifact was APK
`093E077A4B267DF24FCC688E59629CA47F711A6FDC24F12C8DE1311888396235`,
72,836,504 bytes; merged core
`B6183DB29AB9A01C550360C635778E13D59424F2D2517D9DFD4ACC2E7FF8E016`,
1,304,323,752 bytes; and packaged core
`7EE500BDB2246DF9936ADCAD831626537F9F5276F7C1FEAB8B880FF21032CDAE`,
62,988,744 bytes.

## Change

Two local helpers observe strict-rendering and FIFO-accuracy atomics with
relaxed loads on Android. Desktop retains ordered `get()` reads. Both SPU
transfer paths use the helpers only in their existing reservation-lock
expressions.

The lock predicate, PUT/GET classification, accurate-DMA check, local-memory
address gate, RSX reservation lock itself, DMA/list payload handling, and all
reservation synchronization remain unchanged.

Official RPCS3 `origin/master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` retains the generic ordered
conversions. This is a local Android code-generation refinement.

## Exact ARM64 proof

The successor uses four relaxed loads:

```text
36cdd28  LDRB w8, [x25, x8]       do_dma_transfer strict rendering
36cddb0  LDR  w8, [x25, #0xd0c]  do_dma_transfer FIFO accuracy
36d1308  LDRB w8, [x10, x8]       do_list_transfer strict rendering
36d14a4  LDR  w8, [x10, #0xd0c]  do_list_transfer FIFO accuracy
```

The targeted acquire count falls by exactly four:

| Function | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| `do_dma_transfer` | `0x1854` | unchanged | `38 -> 36` |
| `do_list_transfer` | `0x1bc8` | -24 bytes | `12 -> 10` |
| Total | | -24 bytes | `50 -> 46` |

All 46 non-target acquire instructions remain. No matching Android execution
counter exists for these exact sites, so no dynamic barrier total is claimed.

## Verification

Passed:

- focused source contract proving config mutability/defaults, relaxed Android
  and ordered desktop reads, both exact call sites, and reservation/DMA
  ordering anchors;
- Android ARM64 RelWithDebInfo native rebuild;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `77/77` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `24AB810C1DB5EB0F7E89F2BC0B1450A36F9FFB92C59E8AECC3AD2CE246F0C2C8`,
  72,836,464 bytes.
- Merged ARM64 core:
  `D2C52C03B12B54ABB664C8CB48BE84BFE54FA4D23F5A2077BCED896FAFA9E8A4`,
  1,304,323,496 bytes.
- Packaged ARM64 core:
  `78F07D312947C9209E9ABEEE3AFE7697390950A5FA90FCAC5D778F750FABEE8A`,
  62,988,744 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The affected linked functions shrink 24 bytes. The debug-bearing merged core
shrinks 256 bytes and the APK container shrinks 40 bytes; the complete
packaged runtime core is size-neutral because of section alignment. None of
those container/layout deltas is counted as runtime credit.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.