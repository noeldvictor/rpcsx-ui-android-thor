# 2026-05-25 BodyFast RSX RDP VertexPersistent Interaction Worklog

## Goal

Continue the bodyfast plus RSX interaction ladder after the full
geometry/locality stack lost the RPCS3 window, but the smaller RSX halves and
the first RDP plus `VertexSuperset Fast` recombine step passed. This run added
only `VertexPersistent Fast`, leaving `IndexPersistent Fast` off.

## Command

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Evidence

- Run directory:
  `debug-captures\windows-lab\20260525-215019-hle-25cc-bodyfast-rsx-rdp-vertexpersistent-battle-topslot-nopause-interaction-windows`
- Visual gate: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- Route checks passed: field by `160s`, field after `220s`, battle-like after
  `200s`, `0` invalid screenshots after first field-like.
- Manual screenshots:
  - `screenshot-0117s.png`: clean field, `119.98 FPS`;
  - `screenshot-0169s.png`: clean first-battle tutorial prompt, `119.99 FPS`;
  - `screenshot-0230s.png`: clean active first battle, `120.10 FPS`;
  - `screenshot-0320s.png`: clean late active first battle, `119.94 FPS`.
- Fatal-marker scan: clean for access violation, likely-crashed, assertion,
  Vulkan validation, `VK_ERROR`, `SIGSEGV`, and `SIGBUS`.
- Host gate: external-clean across `6` snapshots; total grade was `moderate`
  because RPCS3/GPU-engine load crossed the total-load threshold.
- `0x25cc bodyfast`: `3055` records, `45813` hits, `715.83 MB`,
  `0.000 ms` timing.
- New promoted CPU/SPU-to-GPU replacement: `0 B`; direct RSX-local scout rows:
  `0`; indirect overlap rows: `0`.

## Classification

`resolved-interaction-bisect`, `valid-first-battle-triage`.

This is not a speed win and not a 200% gate candidate. It also is not a new
GPU-migration measurement because the RSX auditor was off. It proves
`VertexPersistent Fast` can coexist with bodyfast plus resolve/depth/present
plus `VertexSuperset Fast` on the TopSlot BattleRoute.

## Harness Update

`tools\ps3_harness_refiner.ps1` now detects this passing interaction step and
keeps the next action on the RSX ladder instead of falling back to generic field
movement.

Next command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-indexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Next

Run the command above. If it passes, the original full-stack window loss was
likely route/transient or ordering-sensitive and the stack can be retested under
a timed/audited proof. If it fails, keep `IndexPersistent Fast` out of stacked
speed/GPU trials and classify it as the remaining interaction suspect.
