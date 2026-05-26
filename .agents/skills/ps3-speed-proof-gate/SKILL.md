---
name: ps3-speed-proof-gate
description: Validate PS3 RPCS3/RPCSX speed claims in this repo. Use for Eternal Sonata BLUS30161 performance gates, Windows-only 200% promotion rules, field/menu/battle visual proof, micro-win accounting, GPU-migration-credit language, host-contention grading, and deciding whether a result is a speed win, migration credit, failed, parked, or not comparable.
---

# PS3 Speed Proof Gate

## Scope

Use this repo-only skill when a result might be called faster, promotable, or worth porting. It is an acceptance gate, not a profiling or implementation skill.

Compose it with:

- `thor-windows-android-ab` for same-scene measurements.
- `ps3-rsx-experiment-gate` for RSX/GPU migration experiments.
- `thor-spu-codegen-hotpath` for SPU/PPU/MFC/codegen work.
- `thor-experiment-ledger` for durable notes.

## Hard Rules

- For current GPU/CPU-to-GPU work, stay Windows-only until Windows proves a stable 200% or better moving-gameplay improvement with correct field, menu, and first-battle visuals.
- Do not run ADB, push Thor cores, or port Android-side code for gated GPU migration before that proof unless the user explicitly reopens Android work.
- Keep Windows RPCS3/PS3 gameplay on the second screen with `-WindowsGameScreen 1`.
- A faster run is not a pass if field, menu, or first battle has black spots, missing textures, flicker, broken lighting, menu corruption, crashes, or route mismatch.
- Do not count FPS across different scenes, cache states, config, drivers, logging modes, host-contention grades, or core labels unless that variable is the test.
- For capped/parity runs, prefer `-WindowsHostContentionGate Fail` when speed claims might follow. For uncapped `240/240` speed A/B, prefer `-WindowsHostContentionGate ExternalFail` so RPCS3's own high CPU/GPU load is allowed while competing emulators, hot non-run processes, or memory pressure still fail the run.

## Classify Results

- `speed-win`: matched route, clean visuals, clear FPS/frame-time or CPU-load improvement.
- `windows-micro-win`: clean matched Windows 1%-10% gain or CPU-load reduction, useful only when compatible with other wins.
- `gpu-migration-credit`: real CPU/SPU/PPU work or RSX-local residency moved toward GPU, correctness-clean, not necessarily faster.
- `gate-candidate`: combined Windows run plausibly near the 200% promotion gate and ready for full field/menu/battle proof.
- `failed`: visual regression, crash, mismatch, readback stall, route failure, or worse timing.
- `parked`: evidence is useful, but missing route/tooling/proof blocks promotion.
- `not-comparable`: scene/config/cache/driver/logging/host state differs too much.

## Evidence Checklist

Record:

- command and run directory;
- scene, route, input backend, display target, frame limit/vblank;
- cache and config state;
- host-contention grade for Windows;
- core/build label and changed files;
- screenshots for field, menu, and first battle, or the missing checkpoint;
- FPS/frame-time and CPU/GPU/thread counters where available;
- `window-title-samples.csv` when the Windows lab produced it, especially for uncapped A/B where manual screenshot title-bar reading is too noisy;
- rollback switch and default state;
- decision label and next action.

## Current Command Shapes

Windows field proof:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -WindowsInputBackend PadApi -WindowsGameScreen 1
```

Windows battle proof:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -WindowsInputBackend PadApi -WindowsGameScreen 1
```

Windows menu proof:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -WindowsInputBackend PadApi -WindowsGameScreen 1
```

## Acceptance

End with one of the result classes above. If the evidence is incomplete, say exactly what proof is missing and do not soften it into a speed claim.
