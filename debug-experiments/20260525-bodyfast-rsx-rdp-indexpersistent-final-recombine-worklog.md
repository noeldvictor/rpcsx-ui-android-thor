# 2026-05-25 BodyFast RSX RDP IndexPersistent Final Recombine Worklog

Goal:

- Continue the Windows-only Eternal Sonata speed sprint toward the 200% moving-gameplay gate.
- Close the RSX interaction ladder by adding only `IndexPersistent Fast` to the last clean bodyfast plus RDP plus vertex-persistent subset.

Run:

- `debug-captures\windows-lab\20260525-220938-hle-25cc-bodyfast-rsx-rdp-indexpersistent-battle-topslot-nopause-interaction-windows`

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-indexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Evidence:

- Visual gate: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- Field by `160s`: passed, first field-like `screenshot-0117s.png`.
- Battle-like at or after `200s`: passed, first `screenshot-0230s.png`.
- Late active battle: `screenshot-0320s.png`.
- Invalid screenshots after first field-like: `0`.
- Fatal-marker scan: no real crash, assertion, validation, `VK_ERROR`, `SIGSEGV`, or `SIGBUS`.
- Host contention: `ExternalFail` passed, external clean across `6` snapshots, total clean.
- FPS remained capped around `120`: `119.45`, `120.01`, `120.04`, `119.96`, `119.95`.
- `0x25cc bodyfast`: `45693` GET body hits, `45720` PUT rejects, `713.95 MB`.
- GPU scoreboard: promoted CPU/SPU -> GPU `0 B`; direct RSX-local scout `0 B`; indirect overlap `0 B`.

Classification:

- `resolved-interaction-bisect`, `valid-first-battle-triage`.
- Not a speed win.
- Not new `gpu-migration-credit`.
- Not a 200% gate candidate.

Durable updates:

- `tools\ps3_harness_refiner.ps1` detects the final `rdp-indexpersistent` pass and suggests exact-stack auditor/accounting only if needed.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `.agents\skills\ps3-rsx-experiment-gate\SKILL.md` now close the RSX interaction ladder after this pass.
- `AGENTS.md` records the final recombine as superseding the earlier full-stack window-loss blocker.

Next:

- For RSX accounting only, run the exact final stack with `-WindowsRsxAuditor 60`.
- For actual speed, pivot away from RSX toggle stacking and into a larger SPU/PPU/codegen lane with field/menu/battle proof.
