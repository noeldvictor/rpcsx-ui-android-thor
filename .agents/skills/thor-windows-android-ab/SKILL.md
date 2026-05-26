---
name: thor-windows-android-ab
description: Run normalized Windows RPCS3 lab versus AYN Thor Android comparisons for Eternal Sonata speed experiments in this repo. Use when Codex needs same-scene A/B testing, host-contention grading, Windows route or RenderDoc proof, Thor truth captures, core/cache/config identity, and cross-platform speed claims.
---

# Thor Windows Android AB

## Scope

Use this repo-only skill for measurement, not for inventing the optimization. It answers whether a change moved the same scene on Windows, Thor, or both.

For GPU/CPU-to-GPU work, compose with `ps3-speed-proof-gate` before any Android step. The current promotion rule is Windows-only until a stable 200% moving-gameplay improvement survives field, menu, and first-battle visuals.

## Workflow

1. Classify the run:
   - `shared-core-win`
   - `windows-lab`
   - `android-thor`
   - `adreno-thor`
   - `failed`
2. Normalize host state for Windows. If Vita3K or another emulator is active, label the run `contended-host`.
3. Capture the same scene and note whether caches are cold or warm.
4. Record:
   - core SHA or label;
   - driver;
   - config/custom config;
   - logging mode;
   - screenshots;
   - FPS/frame-time notes;
   - hot threads and memory.
5. Hand off final recording to `thor-experiment-ledger`.

## Commands

Read `references/matrix.md` for exact command patterns.

Windows field:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -MaxSeconds 130
```

Thor field:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action AndroidRouteScene -Scene field -Driver stock-qualcomm -Core LABEL -AndroidSceneSeconds 12 -NoPerfetto
```

## Acceptance

Do not compare FPS across different scene positions, drivers, logging modes, host-contention grades, display targets, or cache states unless the difference is the explicit variable under test. For Windows runs, keep RPCS3 on the second screen with `-WindowsGameScreen 1`.
