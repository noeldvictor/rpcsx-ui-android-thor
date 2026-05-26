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
- A launch with a truncated input macro is harness noise. Do not let screenshots
  from that run become a route boundary or field proof.
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
win and not GPU migration. The original full bodyfast plus RSX
geometry/locality stack lost the window after field/tutorial, but the repaired
interaction ladder has now passed through geometry-only, resolve/depth/present
only, RDP plus `VertexSuperset Fast`, RDP plus `VertexSuperset Fast` plus
`VertexPersistent Fast`, and the final RDP plus `VertexSuperset Fast` plus
`VertexPersistent Fast` plus `IndexPersistent Fast` recombine. Treat the full
stack as visually compatible on the TopSlot BattleRoute, but capped around
`120 FPS`, not new CPU/SPU GPU migration, and not a 200% gate candidate. The
follow-up exact-stack `-WindowsRsxAuditor 60` accounting pass also reached clean
field and active battle visuals, proving large RSX-local residency/cache credit
with `0 B` promoted CPU/SPU-to-GPU replacement. Do not rerun that auditor and do
not keep stacking RSX toggles. Next, pivot to a larger SPU/PPU/codegen speed
lane, or change RSX source-read/fill architecture if staying RSX.

The first reservation-loop branch-state BattleRoute pivot
`20260525-224813-cpu4-reservation-loop-branchstate-verify-battle-topslot-battleroute-windows`
reached a clean field screenshot, then lost the window/process before late field
or first battle. Treat it as `failed-window-lost-after-field`, not a speed win,
not `gpu-migration-credit`, and not a 200% candidate. Its `0x25cc` / `0x451c`
counters are SPU HLE/codegen profiling evidence only. The next action should be
a smaller field-only `ReservationLoop Verify` route before any broader battle
proof or fast-mode promotion. The default state-aware one-step route then stuck
on the damaged-save load confirmation, and the damaged-confirm repair reached
field but parked on the save-point prompt. Treat that as route/tooling only,
not moving gameplay. The refiner must suggest the damaged-confirm dismiss-save
macro before any speed, HLE/GPU, or first-battle promotion. If that dismiss-save
route stays in the Load UI, classify it as `load-menu-miss`, block both old
macros, and suggest a late load-confirm Yes repair before any save-prompt
dismissal or movement proof. If the late load-confirm route opens the Proceed
prompt but does not send the second `Cross`, block that one-cross macro and
suggest the double-confirm repair. If the double-confirm route still stays in
the Load list and manual screenshots show `Debug Save` / `Prologue` instead of
the Path to Tenuto save target, stop automatic state-aware macro retries. Run
`tools/classify_eternal_sonata_load_target.ps1` on the capture, or use the
`gate_load_target` macro token in `tools/windows_rpcs3_lab.ps1`, and do not
press `Cross` in a new route until that gate reports only
`PATH_TO_TENUTO_PRESENT`. Repair save-target selection for
`DEBUG_SAVE_PROLOGUE_PRESENT`, `MIXED_LOAD_TARGETS`, or
`UNKNOWN_LOAD_TARGET`. The live macro gate now polls instead of using a single
screenshot: transient `Checking save files...` frames are allowed to become
`PATH_TO_TENUTO_PRESENT`, but `DEBUG_SAVE_PROLOGUE_PRESENT` or timeout still
aborts before slot `Cross`. If a polling-gated route reaches field and then the
old dismiss-save sequence opens the Save/Create-new-file menu, block that
sequence and suggest a direct-left movement proof. If direct-left times out on
black/`UNKNOWN_LOAD_TARGET` gate screenshots, suggest only the direct-left
long-gate variant, not the old dismiss-save macro. If that long-gate variant
still reports `UNKNOWN_LOAD_TARGET` while screenshots are story/cutscene or
other non-field frames, stop lengthening the gate. Treat it as a title-to-Load
route miss; run the title-to-Load diagnostic that screenshots title settle,
after title `Down`, after title `Cross`, and before `gate_load_target`, then
aborts before slot `Cross` unless `PATH_TO_TENUTO_PRESENT` is true. The live
`gate_load_target` guard now also classifies each polling screenshot and aborts
early after repeated obvious story/cutscene or non-field frames, while still
allowing black/loading transients to keep polling.
If the title-to-Load diagnostic still enters New Game/story cutscene after the
short `Down:20`, do not fall back to the old double-confirm or long-gate
routes. Use the `Down:160` title-selection diagnostic next so the Load menu
selection is proven before any save-slot `Cross`. If `Down:160` proves
`PATH_TO_TENUTO_PRESENT`, continue only with the `Down:160` load-target-gated
direct-left route. It may press slot `Cross` only after the gate passes, then
must prove field/movement before any speed, HLE, or RSX promotion. If that
direct-left route proves accepted Path to Tenuto field plus movement, treat it
as the current route base. Do not fall back to generic `stateaware-one-step`,
old loader-control, old double-confirm, or old long-gate macros. The next
route proof should use the `Down:160` load-target-gated base for first battle,
while title Options remains a separate required proof before any 200% or speed
promotion. If that first-battle extension crashes after accepted field or shows
the RPCS3 likely-crashed overlay/corrupt field visuals, re-prove the last clean
Down160 direct-left boundary and then shrink or state-gate the battle movement
leg. Do not fall back to generic loader-control or speed/HLE/RSX promotion from
the crashed battle capture. After that boundary is re-proven, isolate the
battle movement by running a Down160 left-only diagnostic (`ls_left:2600`
without the down-left branch) before trying another first-battle route. If
left-only is clean, the next rung is a smaller/state-gated down-left leg, not
the original full `combo:ls_left+ls_down:2200` branch. If left-only crashes,
shrink the left movement from the clean Down160 direct-left boundary.

If any `Down:160` title/load route aborts before slot `Cross` because the
load-target gate reports `DEBUG_SAVE_PROLOGUE_PRESENT` or
`MIXED_LOAD_TARGETS`, classify it as a wrong-save-target blocker. Do not
suggest generic state-aware, old loader-control, old double-confirm, or
Down160 movement reruns. Restore or repair the Path-to-Tenuto save target,
verify `PATH_TO_TENUTO_PRESENT`, then re-run the Down160 direct-left boundary.
If a Down160 post-load route has a live gate-failed marker but the corrected
multi-row classifier reports `PATH_TO_TENUTO_PRESENT` on a lower selected row,
classify it as load-target classifier row drift. Do not suggest the generic
state-aware or old loader-control macro. Re-run the same Down160
post-load-complete dismiss route under the multi-row classifier.
If the Down160 direct-left route passes `PATH_TO_TENUTO_PRESENT` but stays in
the Load UI on the `Load complete` popup instead of reaching field, keep the
Down160 route and add an explicit post-load-complete `Cross` before movement
screenshots. Do not fall back to generic state-aware or old loader-control
macros from that state.

## Acceptance

A useful refiner pass leaves one concrete Windows-only action and prevents a
repeated invalid run. It also updates `debug-experiments/` or `AGENTS.md` when
the durable operating rule changes.
