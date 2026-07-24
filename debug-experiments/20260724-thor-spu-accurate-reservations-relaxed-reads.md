# Thor Android SPU accurate-reservations relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in SPU reservation
handling. Thor was not contacted.

## Baseline

`g_cfg.core.spu_accurate_reservations` is a non-dynamic `cfg::_bool`, default
true. It selects reservation behavior; it does not publish reservation data,
timestamps, locks, event bits, or notifications.

The generic ordered boolean conversion emitted six acquire byte loads in the
runtime PUTLLC/PUTLLUC and reservation-wait paths:

| Function | Size | All `LDAR`/`LDARB` sites | Selector sites |
|---|---:|---:|---:|
| `spu_thread::do_putllc` | `0xc30` | 24 | 3 |
| `do_cell_atomic_128_store` | `0x5d8` | 10 | 1 |
| `spu_thread::do_putlluc` | `0x1b4` | 6 | 1 |
| `spu_thread::get_ch_value` | `0x15a0` | 60 | 1 |
| Total | | 100 | 6 |

The predecessor artifact was APK
`B11499155FE25A3392864E11A4EE61CE443FB9DA222C4BB1F720B70FFD67908C`,
72,836,792 bytes; merged core
`7EE8E150A9F136396F747E20C30487014ED339C5707788007632DF963580EBFA`,
1,304,325,664 bytes; and packaged core
`D01CD6CB5014FC557179B25D41DD975F0D765081F56EA14223C83E75454DD4D8`,
62,988,824 bytes.

## Change

The local `get_spu_accurate_reservations_for_runtime()` helper uses
`cfg::_bool::observe()` on Android and retains ordered `get()` reads on
desktop. All six runtime decisions use the helper. The value remains an atomic
read, and the setting is non-dynamic during emulation.

Reservation acquisition and timestamps, RSX reservation locks, RTM paths,
writer locks, compare/exchange operations, data comparisons, LR event
handling, notifier begin/end/notify calls, and fallback behavior are unchanged.
Their ordering does not depend on publication through the independent config
byte.

Official RPCS3 `origin/master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` retains these ordered reads. The
local upstream lab head `8bd628a43c7b6b8e535796a2f96d92489131fd82`
also retains them; its extra commit concerns the Eternal Sonata frame-poll
wait. This is a local Android code-generation refinement.

## Exact ARM64 proof

The successor uses six direct relaxed byte loads at config offset `#0x974`:

```text
36d18a4  LDRB w8, [x26, #0x974]  do_putllc
36d1960  LDRB w8, [x26, #0x974]  do_putllc
36d1b3c  LDRB w9, [x26, #0x974]  do_putllc
36cf55c  LDRB w8, [x25, #0x974]  do_cell_atomic_128_store
36d2438  LDRB w9, [x22, #0x974]  do_putlluc
36d5a10  LDRB w8, [x8, #0x974]   get_ch_value
```

Each former `ADD base, #0x974` plus `LDARB` pair becomes one immediate-offset
`LDRB`. The targeted acquire count falls by exactly six:

| Function | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| `do_putllc` | `0xc04` | -44 bytes | `24 -> 21` |
| `do_cell_atomic_128_store` | `0x5d8` | unchanged | `10 -> 9` |
| `do_putlluc` | `0x1b0` | -4 bytes | `6 -> 5` |
| `get_ch_value` | `0x15a0` | unchanged | `60 -> 59` |
| Total | | -48 bytes | `100 -> 94` |

All 94 non-target acquire instructions remain. Six address-forming
instructions are removed; linked block layout makes the visible affected-symbol
reduction 48 bytes.

Saved reservation counters prove this subsystem is exercised, but no matching
Android execution counter exists for these exact six sites. This round
therefore claims no dynamic barrier total.

## Verification

Passed:

- focused source contract proving the selector stays non-dynamic/default-on,
  all six runtime reads are relaxed only on Android, desktop remains ordered,
  and reservation synchronization/data-path anchors remain;
- full Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `75/75` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `62F663A58DE80F316ACC85AADFAE7762A1C0A1EE7E9AD8DE6C7DB48825B4B5F4`,
  72,836,492 bytes.
- Merged ARM64 core:
  `A5A7509C37E041427ECBB8B6C4FA704097AF08909CDB3B789A22301952D4BE4C`,
  1,304,322,544 bytes.
- Packaged ARM64 core:
  `439F6176B16EC7515294181B5BAAC539C7B2001459DE329799523E30427D491C`,
  62,988,792 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The affected linked functions shrink 48 bytes. The complete packaged runtime
core shrinks 32 bytes, the merged debug-bearing core shrinks 3,120 bytes, and
the APK container shrinks 300 bytes. Only the linked-function and packaged-core
reductions are runtime code-size evidence.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.
