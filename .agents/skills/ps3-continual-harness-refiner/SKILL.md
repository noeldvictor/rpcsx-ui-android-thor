---
name: ps3-continual-harness-refiner
description: Break circular PS3 Eternal Sonata Windows speed-sprint loops by reading the newest trajectory evidence first, classifying route/visual/log/stack failures, and choosing the next single harness repair or bisect step before any new optimization run.
---

# PS3 Continual Harness Refiner

## Purpose

Use this repo-local skill when the sprint starts looping, a newest run failed,
or a stack/refiner recommendation may be stale.

This adapts the useful continual-harness pattern only: keep a recent trajectory
window, use an oracle, mutate the harness/plan after failures, and preserve the
best known valid state. It is not an autonomous mutation loop and it does not
override the Windows-only 200% gate.

## Hard Stops

- No Android, ADB, or Thor work while the Windows 200% gate is active.
- A newest failure outranks an older success. Do not recommend the older
  success path again until the failure is classified and the refiner/ledger is
  updated.
- Invalid visuals, lost windows, route misses, process exits, host-gate failures,
  and fatal logs block speed claims even when counters look good.
- Stacking is allowed only after each component is individually clean on the same
  route and no newer combined-stack failure exists.
- If a combined stack fails, stop stacking and bisect from the last known-good
  proof. Do not add another candidate.

## Workflow

1. Confirm no active RPCS3/RPCSX/build run is still useful.
2. Run the deterministic refiner from repo root:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

3. Read the report in this order:
   - newest run decision;
   - blocker anti-patterns;
   - suggested command;
   - older opportunities.
4. Choose exactly one next action:
   - route/window repair if the latest proof missed a checkpoint;
   - stack bisect if a combined stack failed;
   - component repeat only if host/noise invalidated an otherwise useful result;
   - new experiment only when the newest run is clean and no blocker outranks it.
5. Update the narrowest ledger before another run.

## Result Classes

- `valid-field-triage`: field-like screenshots exist; not speed proof.
- `valid-options-triage`: Options/menu proof only.
- `valid-first-battle-proof`: field plus active first battle survived.
- `failed-window-lost-after-field`: field appeared, then window/process was gone.
- `failed-visual-gate`: required checkpoint missing or invalid.
- `failed-fatal-log`: crash/assertion/Vulkan/access evidence.
- `route-miss`: screenshots are clean but not the requested state.
- `stack-regression`: a combined stack fails where components previously passed.
- `not-comparable`: scene/config/cache/host state differs too much.

## Current Standing Rule

`0x25cc bodyfast` is a stackable CPU-pressure component only. It is not an FPS
win and not GPU migration. The full bodyfast plus RSX geometry/locality stack
failed after field/tutorial and lost the window before active battle, but both
component halves survived field and active first battle: geometry-only
vertex/index caches, and resolve/depth/present-only. Do not resurrect the
failed full stack. The first recombine step, resolve/depth/present plus
`VertexSuperset Fast`, also survived field and active first battle. Treat the
remaining failure as a narrower interaction with persistent vertex and/or index
cache. Next add `VertexPersistent Fast` while keeping index persistent off.

## Acceptance

A useful refiner pass leaves one concrete Windows-only action and prevents a
repeated invalid run. It also updates `debug-experiments/` or `AGENTS.md` when
the durable operating rule changes.
