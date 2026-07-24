# Thor zero-addend usleep fast path

Date: 2026-07-24

Scope: host-only Android ARM64 optimization for the default guest
`sys_timer_usleep` path, including Eternal Sonata `BLUS30161`. Thor was not
contacted.

## Baseline

`g_cfg.core.usleep_addend` defaults to zero. The three saved correctness routes
also record `Usleep Time Addend: 0`, but the predecessor linked ARM64 core still
executed its full saturating positive/negative adjustment sequence on every
nonzero guest micro-sleep.

The predecessor merged core was
`DC6B9D3D369A27228F38F15E1312EA23D395C40EAC2BBC4F01CE7A9B2B63A6EB`.
Its default-addend prefix executed:

```text
16d16bc: ldar  w8, [x8]       ; addend
16d16c0: sxtw  x9, w8
16d16c4: neg   x10, x9
16d16c8: subs  x10, x1, x10
16d16cc: csel  x10, xzr, x10, lo
16d16d0: cmp   x10, #0x1
16d16d4: csinc x10, x10, xzr, hi
16d16d8: adds  x9, x1, x9
16d16dc: csinv x9, x9, xzr, lo
16d16e0: tst   w8, #0x80000000
16d16e4: ldrb  w8, [x19, #0x9f9]
16d16e8: csel  x20, x10, x9, ne
```

## Change

An explicit `add_time != 0` gate skips the saturating adjustment when the
configured addend is zero. Positive addends still use `add_saturate`; negative
addends still use `max(1, sub_saturate(...))`. Sleep-zero yield behavior,
adjusted duration, timer accuracy, frame-wait eligibility, fallback, and
logging are unchanged.

Official RPCS3 `master`
`7a90d09cfe3c31bf95c3cb63c6301c5c0824c531` still executes the unconditional
saturating selection for the zero default. This is a local code-generation
improvement, not an upstream transplant.

## Exact ARM64 proof

The successor default-addend path is:

```text
16d1688: mov   x20, x1        ; preserve requested duration
16d16c0: ldar  w8, [x8]      ; addend
16d16c4: cbz   w8, 0x16d16dc
16d16dc: ldrb  w8, [x19, #0x9f9]
```

Including the earlier register move, this removes eight executed instructions
from the default-addend prefix. The linked exact Fast classification is one
instruction longer after block relayout, so exact Eternal Sonata frame-poll
calls net seven fewer instructions:

| Route | Exact calls | Net removed instructions |
|---|---:|---:|
| Title | 34,612 | 242,284 |
| First battle | 105,181 | 736,267 |
| Options | 33,485 | 234,395 |
| Total | 173,278 | 1,212,946 |

This is conservative: it excludes all other nonzero guest micro-sleeps, which
retain the full eight-instruction default-addend reduction. The linked
`sys_timer_usleep` grows `0x4a4 -> 0x4ac` for cold nonzero-addend handling,
while the complete merged core shrinks by 32 bytes.

## Verification

Passed:

- focused source contract for zero, positive, and negative addend paths;
- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 disassembly;
- ThorTest ARM64-only APK build;
- ABI, optimized-hook, APK-entry, and exact artifact identity gates;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `C96CD5702CFAA7D6C033BCAE82CA6CCC626A69D1912B8632483F8048AA374DBA`,
  72,837,176 bytes.
- Merged ARM64 core:
  `7C40DA22E05904DF8197C89304B93E799D49A4FFC6B280205BEB9EAF37A817DD`,
  1,304,324,368 bytes.
- Packaged ARM64 core:
  `28DD75066334BD18013F6D32D9188A811A0B379820D0F2C1509D12ADE80530A1`,
  62,989,160 bytes.

This is host-verified `stackable-cpu-pressure` reduction. It is not measured
FPS, stability, power, flicker, or temperature credit.