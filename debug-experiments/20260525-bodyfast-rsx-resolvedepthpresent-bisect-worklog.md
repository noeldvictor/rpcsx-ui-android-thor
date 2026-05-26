# 2026-05-25 BodyFast RSX Resolve/Depth/Present Bisection Worklog

## Goal

Complete the complementary RSX bisection after the full `0x25cc bodyfast +
RSX geometry/locality` stack lost the RPCS3 window and the geometry-only half
passed. This round tested only resolve/depth/present toggles on top of
`0x25cc bodyfast`.

## Command

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-resolvedepthpresent-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Evidence

- Run directory:
  `debug-captures\windows-lab\20260525-211419-hle-25cc-bodyfast-rsx-resolvedepthpresent-battle-topslot-nopause-bisect-windows`
- Visual gate: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- Required route checks all passed: field by `160s`, field after `220s`,
  and battle-like after `200s`.
- Manual screenshots:
  - `screenshot-0117s.png`: clean Path to Tenuto field, `119.90 FPS`;
  - `screenshot-0169s.png`: clean first-battle tutorial prompt, `119.84 FPS`;
  - `screenshot-0230s.png`: clean active first battle, `120.09 FPS`;
  - `screenshot-0320s.png`: clean late active first battle, `119.94 FPS`.
- Host: external-clean across `6` snapshots; one total snapshot was `moderate`
  from GPU engine sum, so this is not a timing comparison run.
- `0x25cc bodyfast`: `3058` records, `45858` hits, `716.53 MB`,
  `0.000 ms` timing.
- GPU migration: `0 B`, `0` RSX-local rows, `0` indirect overlap rows.

## Classification

`resolved-bisect`, `valid-first-battle-triage`.

This is not a speed win, not `gpu-migration-credit`, and not a 200% gate
candidate. It proves the resolve/depth/present half can coexist with bodyfast
on this route. Since geometry-only also passed and the full stack failed, the
current blocker is a cross-family interaction.

## Harness Update

`tools\ps3_harness_refiner.ps1` now detects the exact state:

- newest resolve/depth/present-only pass;
- recent geometry-only pass;
- recent full-stack window-loss failure.

It now suggests an interaction ladder instead of the stale full stack:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexsuperset-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Next

Run the interaction command above. If it passes, add exactly one more geometry
family. If it fails, split `VertexSuperset Fast` against the
resolve/depth/present subset before testing persistent vertex or index caches.
