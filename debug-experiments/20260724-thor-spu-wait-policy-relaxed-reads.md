# Thor Android SPU wait-policy relaxed reads

Date: 2026-07-24

Scope: host-only Android ARM64 CPU-pressure reduction in GETLLAR,
reservation-event, and SPURS waiting policy. Thor was not contacted.

## Baseline

Seven configuration fields choose SPU wait behavior:

- reservation busy-wait percentage: dynamic, default `0`;
- reservation busy-wait enabled: dynamic, default `false`;
- GETLLAR busy-wait percentage: dynamic, default `100`;
- GETLLAR spin optimization disabled: dynamic, default `false`;
- SPU loop detection: non-dynamic, default `false`;
- maximum SPURS threads: dynamic, default `6`; and
- accurate RSX reservation access: dynamic, default `false`.

These atomics select policy. They do not publish reservation data, event bits,
SPURS running counts, lock state, or wait notifications.

The generic ordered conversions emitted seven target acquire loads:

| Symbol | Size | All `LDAR`/`LDARB` sites | Target sites |
|---|---:|---:|---:|
| `evaluate_spin_optimization` | `0x414` | 1 | 1 |
| `spu_thread::process_mfc_cmd` | `0x17b4` | 44 | 1 |
| GETLLAR spin lambda | `0x27c` | 3 | 2 |
| `spu_thread::get_ch_value` | `0x15a0` | 59 | 3 |
| Total | | 107 | 7 |

The predecessor artifact was APK
`24AB810C1DB5EB0F7E89F2BC0B1450A36F9FFB92C59E8AECC3AD2CE246F0C2C8`,
72,836,464 bytes; merged core
`D2C52C03B12B54ABB664C8CB48BE84BFE54FA4D23F5A2077BCED896FAFA9E8A4`,
1,304,323,496 bytes; and packaged core
`78F07D312947C9209E9ABEEE3AFE7697390950A5FA90FCAC5D778F750FABEE8A`,
62,988,744 bytes.

## Change

A local templated helper observes wait-policy scalars with relaxed loads on
Android and retains ordered `get()` reads on desktop. The shared spin
evaluator now accepts a pre-observed percentage value instead of reloading a
configuration object.

Dynamic settings remain live at every existing decision point. GETLLAR
reservation acquisition, RSX reservation locking, event-channel atomics,
SPURS running-count updates, loop-yield behavior, and notification ordering
are unchanged.

Official RPCS3 `origin/master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` retains the generic ordered
conversions and shared config-object load. This is a local Android
code-generation refinement.

## Exact ARM64 proof

The successor uses eight caller-local relaxed loads:

```text
36d3948  LDRB w8, [x28, #0x9f4]  accurate RSX reservation access
36d45c4  LDRB w9, [x8,  #0x5dc]  GETLLAR spin disable, initial selection
36d4604  LDRB w8, [x8,  #0x5dc]  GETLLAR spin disable, timeout selection
36d4630  LDR  w3, [x8,  #0x594]  GETLLAR busy-wait percentage
36d50c0  LDRB w8, [x8,  #0x7fc]  SPU loop detection
36d52fc  LDRB w9, [x8,  #0x554]  reservation busy-wait enabled
36d5308  LDR  w3, [x8,  #0x50c]  reservation busy-wait percentage
36d5510  LDR  w8, [x8,  #0x83c]  maximum SPURS threads
```

There are eight policy call sites but only seven baseline acquire
instructions because both percentage callers previously shared the one
ordered load inside `evaluate_spin_optimization`.

The targeted acquire count falls by exactly seven:

| Symbol | Successor size | Size change | Acquire count |
|---|---:|---:|---:|
| `evaluate_spin_optimization` | `0x404` | -16 bytes | `1 -> 0` |
| `process_mfc_cmd` | `0x17a0` | -20 bytes | `44 -> 43` |
| GETLLAR spin lambda | `0x268` | -20 bytes | `3 -> 1` |
| `get_ch_value` | `0x1580` | -32 bytes | `59 -> 56` |
| Total | | -88 bytes | `107 -> 100` |

All 100 non-target acquire instructions remain. No matching Android execution
counter exists for these exact sites, so no dynamic barrier total is claimed.

## Verification

Passed:

- focused source contract proving scalar types/defaults/dynamic flags,
  relaxed Android and ordered desktop reads, exact call-site coverage, and
  reservation/event/SPURS synchronization anchors;
- Android ARM64 RelWithDebInfo native rebuild;
- exact predecessor/successor symbol and disassembly comparison;
- ARM64-only ThorTest APK build;
- exact APK, merged-core, stripped-core, and APK-entry identity checks;
- all `78/78` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only successor:

- APK:
  `6F1D89FF07708C59D8FEF7C136C564E4C5CE2BB6012BB0A11DB4B1A21A4224A1`,
  72,836,788 bytes.
- Merged ARM64 core:
  `83B3493A8E82FBF3117F1F661FC3B5CAC94049476C517F76A650792A999DBA26`,
  1,304,324,344 bytes.
- Packaged ARM64 core:
  `2BA69B6660256209AA69F9073AF1EA06B0C0420E0A7D8220396DF34CC457C4AE`,
  62,988,664 bytes.
- APK native entry matches the packaged-core hash and size exactly.

The affected linked symbols shrink 88 bytes and the complete packaged runtime
core shrinks 80 bytes. The debug-bearing merged core grows 848 bytes and the
APK container grows 324 bytes due relink/debug/package layout; neither is
counted as runtime credit.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, frame-time, stability, power, flicker, or temperature credit.