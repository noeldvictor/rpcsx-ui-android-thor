# 2026-05-25 BodyFast RSX Final-Stack Auditor Accounting Worklog

Goal:

- Refresh exact final-stack RSX-local accounting after the bodyfast plus RDP, vertex, and index interaction ladder passed.
- Classify the result honestly before choosing the next speed lane.

Run:

- `debug-captures\windows-lab\20260525-222842-hle-25cc-bodyfast-rsx-finalstack-auditor-battle-topslot-nopause-accounting-windows`

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-finalstack-auditor-battle-topslot-nopause-accounting -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxAuditor 60 -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Visual and host evidence:

- Visual gate: `FIELD_LIKE_PRESENT`, `passed-for-triage`.
- Field by `160s`: passed, first field-like `screenshot-0117s.png` at `117s`.
- Active first battle at or after `200s`: passed, first battle-like `screenshot-0230s.png` at `230s`.
- Late active battle: `screenshot-0320s.png` at `320s`.
- Invalid screenshots after first field-like: `0`.
- Manual screenshot spot checks: field and active battle frames render correctly, with no obvious black overlay, missing scene, menu corruption, or lost-window state.
- Fatal-marker scan: no real crash, assertion, validation, `VK_ERROR`, `SIGSEGV`, or `SIGBUS`.
- Host contention: `ExternalFail` passed, external clean across `6` snapshots, total clean.
- FPS stayed capped around `120`: sampled window titles ranged roughly `119.87` to `120.22 FPS`.

CPU/SPU/GPU scoreboard:

- Promoted CPU/SPU -> GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.
- `0x25cc bodyfast`: `3,055` records, `45,813` GET body hits, `45,840` PUT rejects, `715.83 MB`.
- This run does not prove new CPU/SPU work was offloaded to GPU.

RSX-local accounting:

- RSX auditor records: `793`, auditor frames `47,580`.
- RSX-local credit events: `17,408,746`.
- Persistent vertex fast: `8,612,782` hits, `111,068.09 MB` hit bytes.
- Persistent index fast: `8,495,219` hits, `10,229.11 MB` hit bytes.
- Fused GPU resolve/blit dispatches: `21,327`.
- Sampled-MSAA resolve/blit dispatches: `21,327`.
- Read-only depth feedback keeps: `279,197`.
- Present upload GPU byte-swap: `1` event, `3.52 MB`.
- Hard sync flushes: `105`.
- Queue submits: `47,927`.
- Remaining render-pass break debt: `7,105`, all from fused blit-source source reads.
- Debt class: `source-layout-renderpass-bound`.

Classification:

- `valid-first-battle-triage`.
- `gpu-migration-credit` only for RSX-local residency/cache accounting.
- Not a speed win.
- Not promoted CPU/SPU GPU replacement.
- Not a 200% gate candidate.

Durable updates:

- `AGENTS.md` now records the exact final-stack auditor result and the honest split between RSX-local cache/residency credit and `0 B` CPU/SPU-to-GPU replacement.
- `tools\ps3_harness_refiner.ps1` now detects the completed final-stack auditor and suggests a reservation-loop/SPU proof instead of rerunning RSX accounting.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `.agents\skills\ps3-rsx-experiment-gate\SKILL.md` now say the auditor is complete and RSX toggle stacking is closed.

Next:

- Do not rerun the final-stack auditor.
- If staying RSX, change source-read/fill architecture to attack the `7,105` source-read render-pass breaks.
- Otherwise pivot to a larger SPU/PPU/codegen lane. The refiner's next Windows-only command is a `ReservationLoop Verify` first-battle TopSlot BattleRoute proof.
