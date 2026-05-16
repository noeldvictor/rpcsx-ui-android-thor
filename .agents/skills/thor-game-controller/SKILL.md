---
name: thor-game-controller
description: Deterministic controller/input automation for RPCSX/RPCS3 Eternal Sonata on AYN Thor and the Windows lab. Use when Codex needs to verify a controller works, drive Direct/Virtual/OdinRaw input macros, recover from stuck GUI/fatal popup/title/menu states, focus or move the Windows RPCS3 game window, capture before/after route screenshots, or debug why buttons/sticks are not reaching the game.
---

# Thor Game Controller

## Scope

Use this repo-only skill for control-path reliability. It owns controller delivery, emulator focus, route macro hygiene, screenshots, and stuck-state recovery. It does not own performance code, visual correctness analysis, or experiment bookkeeping; hand those to `thor-rsx-vulkan-audit`, `thor-spu-codegen-hotpath`, `thor-scene-route`, or `thor-experiment-ledger`.

## Workflow

1. Classify the target:
   - Thor debug app: use Direct input first.
   - Thor fallback: use Android Virtual input, then OdinRaw only when Direct is unavailable.
   - Windows lab: use `tools/windows_rpcs3_lab.ps1` macros, never ad hoc GUI clicking for benchmarks.
   - Physical controller: test separately from agent macros and label results manual.
2. Prove input delivery with before/after screenshots before extending a route.
3. Keep macros short while debugging. Add one movement or button cluster at a time.
4. Use `shot:NAME` at every branch point and `threads:NAME` around suspected loads, black screens, or hangs.
5. If input appears ignored, run the recovery ladder before changing performance code.

## Thor Commands

Read `references/thor-input.md` before changing Android macros or diagnosing Thor input failure.

Fast Direct sanity check:

```powershell
.\tools\thor_input_macro.ps1 -InputMode Direct -Profile custom -Macro "shot:before;cross;wait:800;shot:after" -PostSnapshot
```

Known field route:

```powershell
.\tools\thor_input_macro.ps1 -InputMode Direct -BootGame -ForceStop -Profile eternal-sonata-field-route -PostSnapshot
```

## Windows Commands

Read `references/windows-input.md` before changing Windows lab macros or handling focus/window placement.

Basic Windows macro proof:

```powershell
.\tools\windows_rpcs3_lab.ps1 -Mode NoGui -Visible -InputMacro "move2;focus;wait:3000;cross:150;wait:800;shot" -ScreenshotEverySeconds 0
```

## Recovery Ladder

1. Check whether the target is the game window, title screen, menu, fatal dialog, black transition, or Android launcher.
2. Capture the current state with a screenshot and log path.
3. Thor: try Direct input, then `virtual:KEY`, then `raw:KEY` only if the debug receiver is unavailable.
4. Windows: use `focus` and `move2`, then restart through `tools/windows_rpcs3_lab.ps1`.
5. If a fatal popup or GUI steals control, stop the app/process and relaunch through the scripted path.
6. If a route returns to title or a boundary dialogue, mark the route failed. Do not reuse that macro for perf.

## Acceptance

Input work is complete only when the capture folder contains:

- `README.md` or `run.md` with macro text and input mode;
- before/after screenshot proof;
- the target platform, core/config identity, and route label;
- a clear classification: delivered, ignored, wrong state, popup/fatal, title reset, black transition, or manual-only.
