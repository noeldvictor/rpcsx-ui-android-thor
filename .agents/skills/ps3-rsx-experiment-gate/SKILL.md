---
name: ps3-rsx-experiment-gate
description: Gate and validate PS3 RPCS3/RPCSX RSX/Vulkan and CPU-to-GPU migration experiments. Use for Eternal Sonata BLUS30161 Windows-only GPU-residency work, RSX-local render/resolve/depth-feedback changes, SPU/PPU-to-Vulkan superpath proposals, 200% Windows promotion gates, field/menu/battle visual validation, rollback switches, and deciding whether a GPU idea is evidence-backed or just wishful offload.
---

# PS3 RSX Experiment Gate

## Overview

Use this repo-local skill before changing RSX/Vulkan code or proposing a CPU/SPU/PPU-to-GPU path. It turns "use the GPU more" into a gated experiment with Windows proof, visual checkpoints, counters, and rollback.

## Hard Gate

Work on Windows only until the Windows lab proves a stable 200% or better moving-gameplay improvement with correct Eternal Sonata field, in-game menu/Options, and first-battle visuals.

Do not run ADB, push a Thor core, or port Android-side code for these experiments before that bar is met unless the user explicitly reopens Android work.

Always keep RPCS3/PS3 gameplay on the second screen for Windows runs with `-WindowsGameScreen 1`.

## Experiment Ladder

1. State the candidate precisely: RSX-local residency, renderpass-local resolve/blit, texture/depth feedback, SPU/PPU data-parallel job, or GPU-resident cache.
2. Prove the work belongs on GPU:
   - RSX-local resource flow, render-target/texture/resolve traffic, or repeated GPU-consumed data is a good sign.
   - Zero RSX-local traffic, tiny SPURS control loops, immediate CPU readback, or one-dispatch-per-event behavior is a bad sign.
3. Add profile or verify mode first. Fast mode comes only after repeated clean verification.
4. Use title/signature gates for Eternal Sonata work: title ID, SPU image hash, PC/block hash, DMA shape, resource format/size/base, or exact Vulkan resource role.
5. Keep a rollback switch or env/config gate. Defaults stay stock unless the path is fully accepted.
6. Run field, menu/Options, and first-battle visual checks with screenshots before claiming the experiment survived correctness.
7. Classify the result:
   - `gpu-migration-credit`: real GPU residency or CPU-work movement, correctness-clean, not necessarily faster.
   - `windows-micro-win`: measured 1%-10% Windows speed or CPU-load reduction under matched host conditions.
   - `gate-candidate`: combined Windows run plausibly approaching the 200% promotion gate.
   - `failed`: visual regression, route failure, validation mismatch, crash, or no meaningful work moved.
   - `parked`: useful idea blocked by missing route, tooling, or required architecture.

## Stack Discipline

- Do not treat "more GPU toggles" as progress. A combined stack must preserve
  the same visual route that each component proved alone.
- If a combined RSX stack loses the game window, misses late field/battle, or
  exits after tutorial prompt, stop and bisect. First test the smallest
  compatible subset against the known-good non-RSX control, then add one RSX
  family at a time.
- For bodyfast plus RSX work, bodyfast is a CPU-pressure component, not GPU
  migration. If the full RSX geometry/locality stack fails, the next valid RSX
  step is a geometry-only or resolve/depth/present-only bisect, not another
  full-stack run.
- If geometry-only passes after a full-stack failure, do not jump back to the
  full stack. Test resolve/depth/present-only next; if that also passes, treat
  the bug as an interaction before combining again.
- Keep `RSX auditor` off for timing unless the experiment is specifically a
  counter/auditor proof.

## Windows Commands

Read `references/eternal-sonata-windows-gate.md` before running or modifying the current RSX-local stack.

Combined RSX-local proof stack:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene field `
  -WindowsInputBackend PadApi `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve Fast `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxAuditor 60 `
  -WindowsGameScreen 1
```

Summarize RSX auditor output:

```powershell
.\tools\summarize_eternal_sonata_rsx_auditor.ps1 -RunDir RUN_DIR
```

Search old proof before inventing a new gate:

```powershell
.\.agents\skills\ps3-debug-knowledge\scripts\ps3_debug_knowledge.ps1 -Query "DepthReadOnly Fast KeepReadOnly"
```

## Acceptance

An RSX/GPU experiment is complete only when the durable note records:

- exact command and run directory;
- scene, route, input backend, display target, frame limit/vblank, and host contention grade;
- visual result for field, menu/Options, and first battle, or the exact missing checkpoint;
- counters for migrated work, RSX-local credit, dispatches, barriers, hard syncs, and readbacks where available;
- FPS/CPU-load result only from matched host-grade runs;
- rollback switch and default state;
- decision class and next action.

Do not describe a neutral GPU-residency credit as a speed win. Do not describe stock RSX rendering through Vulkan as newly ported CPU/SPU work.
