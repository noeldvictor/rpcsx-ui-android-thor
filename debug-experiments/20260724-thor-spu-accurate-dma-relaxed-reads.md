# Thor Android SPU accurate-DMA relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in the measured SPU MFC
transfer lane. Thor was not contacted.

## Baseline

`g_cfg.core.spu_accurate_dma` is a non-dynamic `cfg::_bool`, default false.
It independently selects the accurate transfer implementation; it does not
publish DMA payload, reservation, range-lock, or RSX state.

The generic ordered boolean conversion emitted five acquire byte loads across
the two MFC transfer functions:

```text
36cdde8  LDARB w8, [x8]  do_dma_transfer RSX-lock gate
36cde20  LDARB w8, [x8]  do_dma_transfer accurate-path gate
36ce618  LDARB w8, [x8]  do_dma_transfer accurate-store gate
36cfbf8  LDARB w9, [x9]  do_list_transfer optimization gate
36d1528  LDARB w8, [x8]  do_list_transfer RSX-lock gate
```

Baseline linked symbols:

| Function | Size | All `LDAR`/`LDARB` sites |
|---|---:|---:|
| `spu_thread::do_dma_transfer` | `0x1884` | 46 |
| `spu_thread::do_list_transfer` | `0x1be4` | 15 |

The predecessor artifact was APK
`6F9C32F70FDDF949554F8BE147E755CDD5966A7B578AEF95C06CBDCF1F293FDB`,
72,837,104 bytes; merged core
`FBAC81A595F5A97668168AA8803B788DB4AC8DC13CFF6DBED7CB6E7DFE790676`,
1,304,328,360 bytes; and packaged core
`85E7B139AB5ADFE775A6A8F6C4BA7BC637034D39F60FA179FD1931F3ACFCF2E7`,
62,988,984 bytes.

## Change

`cfg::_bool` now exposes the same relaxed `observe()` operation already
available on integer and enum config entries. The local
`get_spu_accurate_dma_for_mfc()` helper uses that operation only on Android;
desktop keeps the prior ordered `get()` read.

All five accurate-DMA decisions in `do_dma_transfer()` and
`do_list_transfer()` use the helper. The value remains an atomic live read,
and the setting is non-dynamic during emulation. No session-global cache or
title gate was added.

DMA copies, accurate-store behavior, reservation timestamps, range locks, RSX
reservation locks, fences, and notification paths are unchanged. Their
ordering does not depend on publication through the independent config byte.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` remains the upstream reference.
It has neither `cfg::_bool::observe()` nor this Android MFC specialization, so
this is a local Android code-generation refinement.

## Exact ARM64 proof

The successor uses five direct relaxed byte loads:

```text
36cdde4  LDRB w8, [x25, #0x934]
36cde18  LDRB w8, [x25, #0x934]
36ce614  LDRB w8, [x25, #0x934]
36cfbd4  LDRB w9, [x10, #0x934]
36d1504  LDRB w8, [x10, #0x934]
```

Each former `ADD base, #0x934` plus `LDARB` pair becomes one immediate-offset
`LDRB`. The targeted acquire count falls by exactly five:

| Function | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| `spu_thread::do_dma_transfer` | `0x1880` | -4 bytes | `46 -> 43` |
| `spu_thread::do_list_transfer` | `0x1be0` | -4 bytes | `15 -> 13` |
| Total | | -8 bytes | `61 -> 56` |

All 56 non-target acquire instructions remain. Five address-forming
instructions are removed, while linked block layout and padding make the
visible two-symbol reduction eight bytes.

Saved profiling proves this MFC lane is heavily exercised, but no matching
Android execution counter exists for these exact five sites. Therefore this
round claims no dynamic barrier total.

## Verification

Passed:

- focused source contract proving the flag stays non-dynamic, the relaxed
  primitive exists, all five MFC sites use it only on Android, desktop remains
  ordered, and DMA/RSX/reservation structures remain;
- full Android ARM64 RelWithDebInfo rebuild and explicit incremental success;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `73/73` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `87237F66362E9B35CCE6AA32CD91837759A7AFFE2976FDC8B221926F68DFD4F6`,
  72,837,220 bytes.
- Merged ARM64 core:
  `5296091F1940BE6598A3B9FB4CC0029BB80F7013504A9FB3FD25D540BC1FD337`,
  1,304,327,520 bytes.
- Packaged ARM64 core:
  `B651E5C7E2D93E461EE8CCDC39FDC59457EFAB3CFD842BB68817D3BFD54D4126`,
  62,988,888 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The merged core shrinks 840 bytes and the runtime packaged core shrinks 96
bytes. The APK container grows 116 bytes due packaging/version metadata, so
APK size is not counted as runtime credit.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.
