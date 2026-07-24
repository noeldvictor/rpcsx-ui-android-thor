# Thor Android SPU MFC-scheduler relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in normal SPU MFC
command scheduling. Thor was not contacted.

## Baseline

The MFC scheduler uses three independent atomic configuration scalars:

- `mfc_transfers_shuffling`: non-dynamic, default `0`;
- `mfc_transfers_timeout`: dynamic, default `0`; and
- `mfc_shuffling_in_steps`: dynamic, default `false`.

They select scheduling policy; they do not publish MFC queue entries, barrier
or fence masks, timestamps, DMA payload, reservation state, or interrupts.

The generic ordered conversions emitted six acquire loads:

| Function | Size | All `LDAR`/`LDARB` sites | Target sites |
|---|---:|---:|---:|
| `spu_thread::cpu_work` | `0x274` | 7 | 2 |
| `spu_thread::do_mfc` | `0x244` | 3 | 2 |
| `spu_thread::process_mfc_cmd` | `0x17c0` | 46 | 2 |
| Total | | 56 | 6 |

`cpu_work()` also read the timeout before checking the shuffling limit. With
the Thor title profile's default shuffling limit of zero, that timeout value
could not be used.

The predecessor artifact was APK
`62F663A58DE80F316ACC85AADFAE7762A1C0A1EE7E9AD8DE6C7DB48825B4B5F4`,
72,836,492 bytes; merged core
`A5A7509C37E041427ECBB8B6C4FA704097AF08909CDB3B789A22301952D4BE4C`,
1,304,322,544 bytes; and packaged core
`439F6176B16EC7515294181B5BAAC539C7B2001459DE329799523E30427D491C`,
62,988,792 bytes.

## Change

`cfg::uint` now exposes the same explicit relaxed `observe()` primitive as the
other atomic scalar config types. Three local helpers use relaxed observations
on Android and retain ordered `get()` reads on desktop.

All four shuffling-limit reads, the timeout read, and the in-steps read use the
helpers. `cpu_work()` checks the non-dynamic shuffling limit first and observes
the dynamic timeout only when shuffling is enabled. Dynamic timeout and
in-steps changes therefore remain live in the only paths where they matter.

MFC queue publication, command removal, barrier/fence masks, timestamps,
interrupt checks, DMA/list execution, pending-state transitions, and command
ordering are unchanged.

Official RPCS3 `origin/master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` retains the ordered conversions
and unconditional timeout read. This is a local Android code-generation and
default-path refinement.

## Exact ARM64 proof

The successor uses six direct relaxed loads:

```text
36ca704  LDR  w9,  [x8,  #0xe54]  cpu_work shuffling limit
36ca70c  LDR  w19, [x8,  #0xe9c]  cpu_work timeout
36ca954  LDR  w8,  [x26, #0xe54]  do_mfc shuffling limit
36caab0  LDRB w8,  [x26, #0xee4]  do_mfc in-steps
36d2b68  LDR  w8,  [x28, #0xe54]  process_mfc_cmd shuffling limit
36d2ca4  LDR  w9,  [x28, #0xe54]  process_mfc_cmd shuffling limit
```

At `0x36ca708`, `cpu_work()` branches around the timeout load when the
shuffling limit is zero. The default path therefore eliminates the previously
unconditional timeout atomic load entirely.

The targeted acquire count falls by exactly six:

| Function | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| `cpu_work` | `0x274` | unchanged | `7 -> 5` |
| `do_mfc` | `0x23c` | -8 bytes | `3 -> 1` |
| `process_mfc_cmd` | `0x17b4` | -12 bytes | `46 -> 44` |
| Total | | -20 bytes | `56 -> 50` |

All 50 non-target acquire instructions remain. No matching Android execution
counter exists for these exact sites, so no dynamic barrier total is claimed.

## Verification

Passed:

- focused source contract proving config mutability/defaults, relaxed Android
  and ordered desktop reads, the default timeout bypass, and MFC ordering
  anchors;
- full Android ARM64 RelWithDebInfo native rebuild;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `76/76` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `093E077A4B267DF24FCC688E59629CA47F711A6FDC24F12C8DE1311888396235`,
  72,836,504 bytes.
- Merged ARM64 core:
  `B6183DB29AB9A01C550360C635778E13D59424F2D2517D9DFD4ACC2E7FF8E016`,
  1,304,323,752 bytes.
- Packaged ARM64 core:
  `7EE500BDB2246DF9936ADCAD831626537F9F5276F7C1FEAB8B880FF21032CDAE`,
  62,988,744 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The affected linked functions shrink 20 bytes and the complete packaged
runtime core shrinks 48 bytes. The debug-bearing merged core grows 1,208 bytes
and the APK container grows 12 bytes due relink/debug/package layout; neither
is counted as runtime credit.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.
