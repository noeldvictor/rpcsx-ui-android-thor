# Thor frame-wait PPU mode cache

Date: 2026-07-24

## Status

Host-verified `stackable-cpu-pressure`; device-unmeasured. No ADB query,
install, launch, temperature poll, wait, or other Thor contact occurred.

## Motivation

The exact Eternal Sonata frame-poll call already had three immutable
classifiers:

- main PPU ID `0x01000000`;
- title ID `BLUS30161`; and
- the process-lifetime frame-wait mode.

The predecessor reloaded and branched on all three for every exact call. Saved
continuous-rearm routes contain 173,278 exact frame-poll calls:

| Route | Calls |
|---|---:|
| Title | 34,612 |
| First battle | 105,181 |
| Options | 33,485 |
| Total | 173,278 |

## Change

Each PPU now owns one `thor_es_frame_poll_wait_mode` byte:

- only main PPU `0x01000000` for `BLUS30161` starts `uninitialized`;
- every other PPU/title starts `off`;
- the first exact CIA/100 us candidate resolves the existing immutable
  process setting and stores it in that PPU byte; and
- subsequent calls use the PPU byte directly.

The exact CIA `0x002a8300` and adjusted 100 us gates remain on every candidate.
Object/config identity, address validation, divisor, counter threshold,
renderer, bounded wait, publication acquire, grace, completion, fallback, and
diagnostic behavior are unchanged.

The PPU ID is const, both normal and savestate constructors recompute
eligibility after base construction, and each game creates new PPU objects.
The byte is only resolved by the owning PPU on its first exact candidate, so
no inter-thread publication is added.

## Exact ARM64 proof

Predecessor merged core
`58C1A18D7B362FB061B6BAC446675053CD6F67A1257AE2D64097F2B7CA14906E`
used 21 linked classification instructions on a steady-state exact `Fast`
call: four for PPU ID, six for CIA/duration, three for title, and eight for
the global mode/cold/fast decisions.

Successor merged core
`6C9DA0D5F949C9BAB4568EA5AFFC2214A3F6948FE69649F0893F0711EC5F53F1`
uses 13:

```text
16d16c0: ldrb w0, [x19, #0x9f9]   ; PPU mode
...
16d16ec: cmp  w0, #0x1            ; off
16d16f0: b.eq normal_timer_path
16d16f4: ldr  w8, [x19, #0x494]   ; CIA
...
16d1708: b.eq exact_candidate
...
16d1824: cbz  w0, cold_resolve
16d1828: and  w8, w0, #0xff
16d182c: cmp  w8, #0x3            ; fast
16d1830: b.ne diagnostic
```

That is eight fewer linked gate instructions per saved exact call:

| Route | Removed gate instructions |
|---|---:|
| Title | 276,896 |
| First battle | 841,448 |
| Options | 267,880 |
| Total | 1,386,224 |

`sys_timer_usleep` grows `0x494 -> 0x498` (4 bytes) because it now contains the
one-time cold PPU-byte store. This is not a static-size win; the retained
candidate is the measured linked steady-state instruction reduction. Normal
and savestate constructor symbols grow `0x520 -> 0x52c` and
`0xcd4 -> 0xcf4`; those are cold-path costs and receive no speed credit.

## Verification

Passed:

- focused PPU-mode/cache ordering contract;
- Android ARM64 RelWithDebInfo native build;
- exact predecessor/successor linked ARM64 disassembly;
- ThorTest ARM64-only APK build;
- exact candidate artifact/APK-entry identity contract;
- all `70/70` `tools/test_thor_*.ps1` host contracts; and
- `git diff --check`.

Exact host-only artifact:

- APK:
  `6F57A84ACC0F3719AC2F165812AFF7CF8A6BA6DB004224E360BDD21CEC5C15B2`,
  72,837,024 bytes.
- Merged ARM64 core:
  `6C9DA0D5F949C9BAB4568EA5AFFC2214A3F6948FE69649F0893F0711EC5F53F1`,
  1,304,324,744 bytes.
- Packaged ARM64 core:
  `DD392B897A84A5FC4C7971D8E295D0C6C2F9BBC1AA7FA08C4CA9A158209531B1`,
  62,989,160 bytes.

This is a host-verified reduction in timer hot-path work, not measured FPS,
stability, power, flicker, or temperature credit.
