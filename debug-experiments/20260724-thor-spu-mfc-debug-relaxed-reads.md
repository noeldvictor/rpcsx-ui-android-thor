# Thor Android SPU MFC-debug relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in the SPU MFC command
lane. Thor was not contacted.

## Baseline

`g_cfg.core.mfc_debug` is a non-dynamic `cfg::_bool`, default false. It controls
only diagnostic history allocation and recording; it does not publish DMA
payload, reservation, range-lock, RSX, fence, or notification state.

The generic ordered boolean conversion emitted fourteen acquire byte loads
across the two SPU constructors and three MFC functions:

| Function | Size | All `LDAR`/`LDARB` sites | MFC-debug sites |
|---|---:|---:|---:|
| normal `spu_thread` constructor | `0x8c8` | 11 | 1 |
| savestate `spu_thread` constructor | `0xff8` | 25 | 1 |
| `spu_thread::do_dma_transfer` | `0x1880` | 43 | 5 |
| `spu_thread::do_list_transfer` | `0x1be0` | 13 | 1 |
| `spu_thread::process_mfc_cmd` | `0x17d4` | 52 | 6 |
| Total | | 144 | 14 |

The predecessor artifact was APK
`87237F66362E9B35CCE6AA32CD91837759A7AFFE2976FDC8B221926F68DFD4F6`,
72,837,220 bytes; merged core
`5296091F1940BE6598A3B9FB4CC0029BB80F7013504A9FB3FD25D540BC1FD337`,
1,304,327,520 bytes; and packaged core
`B651E5C7E2D93E461EE8CCDC39FDC59457EFAB3CFD842BB68817D3BFD54D4126`,
62,988,888 bytes.

## Change

The local `get_mfc_debug_for_runtime()` helper uses `cfg::_bool::observe()` on
Android and retains ordered `get()` reads on desktop. All fourteen active
MFC-debug decisions use the helper. The value remains an atomic read, and the
setting is non-dynamic during emulation.

Diagnostic history allocation and recording remain intact. DMA copies,
accurate-DMA selection, reservations, range locks, RSX reservation locks,
fences, and notifications are unchanged. Their ordering does not depend on
publication through the independent diagnostic byte.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.
This is a local Android code-generation refinement.

## Exact ARM64 proof

The successor uses fourteen direct relaxed byte loads at config offset
`#0x65c`:

```text
36cbbfc  LDRB w8,  [x22, #0x65c]  normal constructor
36ccb30  LDRB w8,  [x21, #0x65c]  savestate constructor
36cdb70  LDRB wzr, [x25, #0x65c]  do_dma_transfer
36cdf80  LDRB w8,  [x25, #0x65c]  do_dma_transfer
36ce66c  LDRB w8,  [x25, #0x65c]  do_dma_transfer
36ce9d8  LDRB w8,  [x25, #0x65c]  do_dma_transfer
36cf274  LDRB w8,  [x19, #0x65c]  do_dma_transfer
36cfbbc  LDRB w9,  [x10, #0x65c]  do_list_transfer
36d2dbc  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
36d2f84  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
36d3018  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
36d3318  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
36d3690  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
36d3d18  LDRB w8,  [x28, #0x65c]  process_mfc_cmd
```

Each former `ADD base, #0x65c` plus `LDARB` pair becomes one immediate-offset
`LDRB`. The targeted acquire count falls by exactly fourteen:

| Function | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| normal constructor | `0x8c8` | unchanged | `11 -> 10` |
| savestate constructor | `0xff8` | unchanged | `25 -> 24` |
| `do_dma_transfer` | `0x1854` | -44 bytes | `43 -> 38` |
| `do_list_transfer` | `0x1be0` | unchanged | `13 -> 12` |
| `process_mfc_cmd` | `0x17c0` | -20 bytes | `52 -> 46` |
| Total | | -64 bytes | `144 -> 130` |

All 130 non-target acquire instructions remain. Fourteen address-forming
instructions are removed; linked block layout makes the visible affected-symbol
reduction 64 bytes.

No matching Android execution counter exists for these exact sites, so this
round claims no dynamic barrier total.

## Verification

Passed:

- focused source contract proving the flag stays non-dynamic, all fourteen
  active diagnostic gates are relaxed only on Android, desktop remains ordered,
  and history paths remain;
- full Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `74/74` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `B11499155FE25A3392864E11A4EE61CE443FB9DA222C4BB1F720B70FFD67908C`,
  72,836,792 bytes.
- Merged ARM64 core:
  `7EE8E150A9F136396F747E20C30487014ED339C5707788007632DF963580EBFA`,
  1,304,325,664 bytes.
- Packaged ARM64 core:
  `D01CD6CB5014FC557179B25D41DD975F0D765081F56EA14223C83E75454DD4D8`,
  62,988,824 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The runtime packaged core shrinks exactly 64 bytes. The merged debug-bearing
core shrinks 1,856 bytes and the APK container shrinks 428 bytes; those
container/debug changes are not counted as runtime credit.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.
