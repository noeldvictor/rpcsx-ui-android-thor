# Thor frame-wait Fast-first mode encoding

Date: 2026-07-24

Scope: host-only Android ARM64 optimization for the Eternal Sonata
`BLUS30161` exact frame-poll wait. The Thor was not contacted.

## Baseline

The predecessor merged core
`6C9DA0D5F949C9BAB4568EA5AFFC2214A3F6948FE69649F0893F0711EC5F53F1`
cached main-PPU, title, and immutable process mode in one PPU byte.
Its linked steady-state exact `Fast` classification used 13 instructions:

- three to load and reject `off`;
- six for exact CIA `0x002a8300` and adjusted 100 us; and
- four for the unresolved and `Fast` decisions.

Saved clean-route call counts remain:

| Route | Exact calls |
|---|---:|
| Title | 34,612 |
| First battle | 105,181 |
| Options | 33,485 |
| Total | 173,278 |

## Change

`off` is now the zero enum value, followed by `fast`, `diagnostic`, and
`uninitialized`. The wrapper rejects zero with one `CBZ`, checks `Fast`
before any cold-state work, and uses one shared Fast implementation block.
Diagnostic, unresolved, and invalid modes remain fail-closed or cold-only.

The PPU-lifetime eligibility, exact CIA/duration gate, object/config identity,
VM validation, threshold, renderer, bounded 1 ms wait, publication acquire,
post-handler grace, completion, fallback, and diagnostic behavior are
unchanged.

## Rejected source shape

The first Fast-first source shape returned the inlined Fast specialization
from both the steady and cold paths. LLVM duplicated the large body and grew
`sys_timer_usleep` from `0x498` to `0x67c`. That link was rejected before
packaging. The retained source shares one labeled Fast block.

## Exact ARM64 proof

The retained linked gate is:

```text
16d16e4: ldrb w8, [x19, #0x9f9]   ; PPU mode
16d16ec: cbz  w8, normal_timer     ; off == 0
16d16f0: ldr  w9, [x19, #0x494]   ; CIA
16d16f4: mov  w10, #0x8300
16d16f8: cmp  x20, #0x64          ; adjusted duration
16d16fc: movk w10, #0x2a, lsl #16
16d1700: ccmp w9, w10, #0x0, eq
16d1704: b.eq exact_candidate
16d1820: cmp  w8, #0x1            ; fast
16d1824: b.eq fast_wait
```

That is 10 classification instructions, three fewer than the predecessor:

| Route | Removed linked gate instructions |
|---|---:|
| Title | 103,836 |
| First battle | 315,543 |
| Options | 100,455 |
| Total | 519,834 |

`sys_timer_usleep` grows `0x498 -> 0x4a4` (12 bytes) for the cold/defensive
dispatch. The retained candidate is a measured linked steady-state
instruction reduction, not a static-size win.

## Upstream audit

Read-only SSH verification found official RPCS3 `master` at
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531`. The recent upstream
SPU-FMA dependency-chain shortening is already represented by local commit
`65102bf31`, and the ARM64 reduced-loop safety updates are already represented
by `bcac8b97a`; no additional upstream transplant was needed for this round.

## Verification

Passed:

- focused enum/ordering/fail-closed source contract;
- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 disassembly;
- rejected duplicate-body link and retained single-body link comparison;
- ThorTest ARM64-only APK build;
- ABI, optimized-hook, APK-entry, and exact artifact identity gates;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `B825212A009766717AACDCD3CF7C51ACFFBB7E33031420A7FEF0E55F8810E006`,
  72,837,192 bytes.
- Merged ARM64 core:
  `DC6B9D3D369A27228F38F15E1312EA23D395C40EAC2BBC4F01CE7A9B2B63A6EB`,
  1,304,324,400 bytes.
- Packaged ARM64 core:
  `29350625DBE618551ED5085F1132DC652D7AC2FBD04392A27A5520B2DA762660`,
  62,989,160 bytes.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.
