# 2026-05-25 BodyFast RSX RDP VertexSuperset Interaction Worklog

## Goal

Test the first recombine step after both RSX halves passed separately and the
full `0x25cc bodyfast + RSX geometry/locality` stack lost the game window.
This run added only `VertexSuperset Fast` to the clean bodyfast plus
resolve/depth/present subset.

## Command

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexsuperset-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Evidence

- Run directory:
  `debug-captures\windows-lab\20260525-213312-hle-25cc-bodyfast-rsx-rdp-vertexsuperset-battle-topslot-nopause-interaction-windows`
- Visual gate: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- Route checks passed: field by `160s`, field after `220s`, battle-like after
  `200s`, `0` invalid screenshots after first field-like.
- Manual screenshots:
  - `screenshot-0118s.png`: clean field, `120.11 FPS`;
  - `screenshot-0169s.png`: clean first-battle tutorial prompt, `119.92 FPS`;
  - `screenshot-0231s.png`: clean active first battle, `119.93 FPS`;
  - `screenshot-0320s.png`: clean late active first battle, `120.12 FPS`.
- Fatal scan: clean.
- Host gate: external-clean across `6` snapshots; total grade was `moderate`
  because two GPU-engine snapshots exceeded `60%`.
- `0x25cc bodyfast`: `3052` records, `45768` hits, `715.13 MB`,
  `0.000 ms` timing.
- New promoted CPU/SPU-to-GPU replacement: `0 B`; direct RSX-local scout rows:
  `0`; indirect overlap rows: `0`.

## Classification

`resolved-interaction-bisect`, `valid-first-battle-triage`.

This is not a speed win and not a 200% gate candidate. It also is not a new
GPU-migration measurement because the RSX auditor was off. It proves the
already-known `VertexSuperset Fast` RSX residency component can coexist with
bodyfast plus resolve/depth/present on this route.

## Harness Update

`tools\ps3_harness_refiner.ps1` now detects this passing interaction step and
keeps the next action on the RSX ladder instead of falling back to generic field
movement.

Next command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Next

Run the command above. If it passes, the final isolated recombine step is adding
`IndexPersistent Fast`. If it fails, split persistent vertex before touching
index persistent.
