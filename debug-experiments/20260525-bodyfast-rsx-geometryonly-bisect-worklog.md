# 2026-05-25 BodyFast RSX Geometry-Only Bisection Worklog

## Goal

Break the stale full-stack loop and test the smallest useful RSX subset after
`bodyfast + RSX geometry/locality` lost the RPCS3 window.

## Result

Run:

- `debug-captures\windows-lab\20260525-204625-hle-25cc-bodyfast-rsx-geometryonly-battle-topslot-nopause-bisect-windows`

Outcome:

- Field proof passed at `117s`.
- First-battle tutorial prompt was clean at `169s`.
- Active first-battle proof survived at `230s` and `320s`.
- Host contention stayed clean across `6` snapshots.
- FPS stayed capped around `120`, so this is not a speed win.
- GPU migration remained `0 B` / `0%`.
- `0x25cc bodyfast` still fired: `3057` records, `45843` hits, `716.30 MB`.

Classification:

- `resolved-bisect`
- `valid-first-battle-triage`
- not `windows-micro-win`
- not `gpu-migration-credit`
- not a 200% gate candidate

## Harness Fix

The refiner initially fell back to the stale full-stack recommendation after
this passing subset. That would have repeated the loop. It now detects the
sequence:

1. full `bodyfast + RSX geometry/locality` failed by window loss;
2. `bodyfast + geometry-only` passed;
3. next action must be the complementary resolve/depth/present-only bisection.

## Next Command

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-resolvedepthpresent-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```
