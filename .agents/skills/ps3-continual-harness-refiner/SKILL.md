---
name: ps3-continual-harness-refiner
description: Refine the PS3 Eternal Sonata Windows speed sprint from recent trajectory evidence. Use when adapting continual-harness ideas, preventing repeated invalid captures, choosing the next safe Windows-only experiment, reading recent run summaries, detecting black/loading/wrong-window route failures, or updating repo-local skills/AGENTS/debug ledgers without using global skills.
---

# PS3 Continual Harness Refiner

## Scope

Use this repo-local skill to turn recent Windows lab trajectory into a safer next action. It adapts the useful part of continual-harness: look at the recent run window, identify repeated failures or stale assumptions, and refine the harness before repeating work.

This is not an autonomous mutation loop. Do not run Android/ADB/Thor work while the Windows 200% gate is active. Do not claim speed, GPU migration, or route proof from invalid visuals.

Compose with:

- `codex-goal-loop` for the 200% gate and resume discipline.
- `ps3-debug-knowledge` before updating durable memory.
- `ps3-speed-proof-gate` before calling anything faster.
- `ps3-rsx-experiment-gate` before CPU/SPU/PPU-to-GPU claims.

## Workflow

1. Read `AGENTS.md` and the narrowest `debug-experiments/*.md` ledger for the current blocker.
2. Run the refiner from repo root:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Use `-NoWrite` for a dry terminal-only report.

3. Treat the report as a guardrail:
   - repeated black-overlay or loading-like screenshots mean route/tooling first, no extra movement;
   - clean lane counters with invalid visuals are blocked evidence;
   - repeated zero RSX-local traffic parks broad SPU-to-Vulkan compute until a new scout proves RSX-consumed data;
   - a newest valid-field run can be used only for one small state-aware next step.
   - if a specific movement branch already produced cutscene/non-field visuals, do not suggest that same branch again just because a later base-confirm run passed; either try a different smaller movement or repair route control.
   - fatal/crash/access/Vulkan/assertion log hits invalidate the trajectory even when screenshots are byte-size field-like; back off to the newest clean boundary before adding movement.
   - if the latest run is itself a loader-control reconfirm and it black-overlayed before accepted field, do not loop that same reconfirm command; back off one movement pulse or repair route control first.
   - if the first `loader-control-left200` step has already failed after a clean no-movement boundary, do not auto-rerun that same movement just because the no-movement boundary re-passed; add/use black-overlay route control, shrink/change the pulse, or switch to SPU kernel HLE/codegen/verifier analysis.
   - if a failed movement branch shows small blue/starry screenshots after the clean no-movement boundary, treat it as a cutscene/nonfield route miss rather than a black-overlay failure; do not auto-rerun the same movement.
   - if a later next loader-control movement count has already failed twice in the recent window, do not auto-rerun it just because the lower boundary re-passed; repair route control, strengthen the accepted-field state gate, or switch to SPU kernel HLE/codegen/verifier analysis.
   - if the latest run is the failed next movement count, still look back to the newest valid lower boundary before deciding. A latest black-overlay failure after a valid lower boundary should block that same next count when it has failed twice recently.
   - if the latest run is an HLE/SPU `0x451c` size-16 candidate capture and it black-overlayed, do not let older loader-control movement failures choose the next action. Treat its counters as smoke-only, confirm no active RPCS3/RPCSX process, then re-prove the no-movement HLE `Verify` route with `CleanAfterField` before designing or enabling a batch body.
   - if the latest HLE/SPU `0x451c` size-16 candidate capture is field-clean and fatal-clean, treat it as the current HLE/codegen baseline. Do not switch back to loader-control movement; move to the bounded preserve-order inline-GET batch copier/verifier design.
   - if a `0x451c` size-16 body-on run black-overlayed and a later body-off `Verify` reproof is field-clean, keep the body opt-in/off by default. Do not rerun the body path until the copy semantics are repaired or narrowed and explicitly requested.
   - if a repaired or narrowed `0x451c` size-16 body-on run is field-clean and fatal-clean, treat it only as field-correctness proof. Keep the body opt-in and require menu/Options plus first-battle visuals before speed A/B, promotion, GPU migration credit, or 200% claims.
   - if an opt-in `0x451c` size-16 body menu/Options attempt renders clean intro/cutscene frames but misses the title Options target, do not switch back to loader-control movement. Keep the body opt-in, repair or state-gate the Windows menu route, and rerun menu proof before first-battle or A/B timing.
   - if an opt-in `0x451c` size-16 body menu run opens the full title Options page cleanly, do not treat the expected small Options-page screenshots as wrong-window captures. Keep the body opt-in and move to first-battle visual/fatal proof before speed A/B or promotion.
   - if an opt-in `0x25cc` body title Options run opens the full Options page cleanly, do not treat the expected small Options-page screenshots as wrong-window captures. If a later `0x25cc` first-battle attempt opens that Options page instead of battle, classify it as a battle route miss and do not rerun the same battle command unchanged. Use the top-slot-normalized battle load route plus the `BattleRoute` visual gate before trusting a new first-battle proof.
   - if a `BattleRoute` A/B attempt passes field-like byte triage but manual screenshots show a paused Path to Tenuto field, classify it as `not-comparable-route-miss-paused-field`. Do not use its title FPS as stock or body battle baseline. Tighten/use a battle-like late-frame gate and still require manual first-battle visuals before speed A/B.
   - if the newest `0x25cc` no-pause `BattleRoute` stock/body A/B already reached valid field and first-battle visuals and the narrow A/B summary classifies the body as `not-speed-win`, do not fall back to generic loader-control movement or rerun the same A/B. Switch to body/family timing inspection, verifier-overhead removal, or a narrower `0x25cc` body design before the next comparison.
   - if a later `0x25cc` `bodyfast` BattleRoute removes verifier/family/shadow overhead, keeps clean field and first-battle visuals, and holds capped FPS, classify the FPS gain separately from CPU-load evidence. A postrun host-gate failure from Codex noise means the CPU-load reduction is directional, not banked; repeat one clean bodyfast or fresh stock/bodyfast pair before calling it a CPU-load micro-win. Do not return to verifier-overhead removal after this point.
   - if a clean `0x25cc` `bodyfast` BattleRoute repeat confirms lower RPCS3 process CPU with clean external host samples, bank it only as a stackable CPU-pressure component. It is not an FPS win and not GPU migration. The next useful action is a combined Windows proof with an already verified compatible stack, such as the RSX geometry/locality credit stack, rather than rerunning bodyfast alone.
   - if an opt-in `0x451c` size-16 body first-battle run black-overlays after field and Options were clean, do not call it a generic size-16 candidate failure or return to loader-control movement. Keep the body opt-in/off, reprove the same battle route with the body off, then inspect or narrow the body semantics before another body-on battle.
   - if a body-off first-battle reproof only reaches a field screenshot and later screenshots are skipped because the game window was not found, do not call it a clean body-off proof. Treat it as route/window-loss, distinguish process exit from empty window-handle loss, repair or state-gate the battle route, and keep body semantics work blocked.
   - if the body-off battle left-only diagnostic also exits after the field screenshot, do not rerun that same left-only route. Run a no-post-field-movement diagnostic next to separate route/timer exit from movement-triggered guest exit.
   - if a preserve-body-off battle diagnostic parks on the damaged save/load menu, repair the load route by normalizing the save slot before selecting the save. If the repaired top-slot diagnostic reaches accepted field cleanly, treat it only as route-control repair, not preserve-body opt-in proof, then isolate the left-only movement branch with preserve-body still Off.
   - if the top-slot-normalized preserve-body-off no-post route stayed alive but the top-slot left-only diagnostic exits RPCS3 after accepted field, do not fall back to the older non-top-slot no-post route. Shrink or repair the left-only branch before any diagonal movement or preserve-body-on battle proof.
   - if top-slot preserve-body-off `left800` survives cleanly after full `left2600` exited RPCS3, treat `left800` as the lower movement boundary and binary-search the left branch (for example `left1600`) before diagonal movement or preserve-body-on battle proof.
   - if a top-slot preserve-body-off midpoint such as `left1600` produces fatal RSX/shader evidence or visibly corrupt field output after a clean `left800`, do not loop `left1600` or fall back to generic no-movement. Re-prove `left800`, then try the smaller midpoint such as `left1200`.
   - if `left1200` survives cleanly after `left1600` produced fatal RSX/shader evidence, treat `left1200` as the new lower boundary and try `left1400` before diagonal movement or preserve-body-on battle proof.
   - if `left1400` exits RPCS3 after accepted field while `left1200` survived cleanly, treat `left1400` as above the clean boundary and try `left1300` before diagonal movement or preserve-body-on battle proof.
   - if `left1300` never reaches accepted field and captures only loading-like screenshots after `left1400` exited and `left1200` survived, do not treat `left1300` as a boundary and do not switch to generic field movement. Re-prove `left1200` with the same top-slot macro before trying another midpoint or route repair.
   - if `left1200` is re-proven clean after the `left1300` loading-only miss, keep `left1200` as the lower boundary but do not loop back to `left1400` or `left1300`. Repair or state-gate the accepted-field route before another midpoint.
   - if the route-state gate after `left1200` reproof stays field-clean through repeated accepted-field screenshots, do not fall back to full left-only or rerun `left1300`. Try a smaller state-gated `left1250` diagnostic next.
   - if the state-gated `left1250` diagnostic black-overlays at the accepted-field and pre-movement checkpoints, do not call it a left1250 boundary and do not shrink movement yet. Reconfirm or repair the accepted-field route-state gate before any further midpoint.
4. Execute at most one concrete next experiment or harness edit.
5. Record durable changes in the narrowest ledger. Update `AGENTS.md` only for standing rules or repeated gotchas.

## Output Classes

- `valid-field-triage`: field-like screenshots survived byte-size triage. Still needs real visual proof before speed claims.
- `valid-options-triage`: a labeled title menu/Options body proof produced clean menu screenshots with no black/loading classes. Still needs first-battle proof and speed A/B before any win claim.
- `route-miss-options-not-battle`: a battle-labeled body proof produced clean title Options-page screenshots instead of first-battle visuals. Treat as route repair work, not a battle proof or speed result.
- `failed-black-overlay-visual`: black/perf-overlay screenshots, usually around 31-33 KB in current captures.
- `failed-loading-visual`: loading-like screenshots, currently around 109-116 KB.
- `failed-cutscene-or-nonfield-visual`: large blue/red/dark non-field screenshots or small blue/starry non-field screenshots that can fool byte-size-only triage.
- `failed-wrong-window-or-other-visual`: small screenshot outside the known loading/black bands.
- `failed-window-lost-after-field`: a field-like screenshot appeared, but later required screenshots were skipped because the game window disappeared or the process exited early. Treat as incomplete route/window control, not scene proof.
- `failed-fatal-log`: RPCS3 stdout/stderr/log had crash, access violation, Vulkan, assertion, or likely-crashed evidence. Treat as invalid even if visual triage passed.
- `failed-visual-gate`: the helper summary explicitly reports `Gate result: failed`, even if byte-size field-like screenshots exist. Treat as blocked route/tooling evidence until the specific failed visual requirement is repaired.
- `not-comparable-no-screenshots`: no visual evidence.

## Acceptance

A refiner pass is useful when it leaves one concrete Windows-only action and prevents a repeated invalid run. It is not a speed result, not GPU migration credit, and not a 200% gate candidate by itself.
