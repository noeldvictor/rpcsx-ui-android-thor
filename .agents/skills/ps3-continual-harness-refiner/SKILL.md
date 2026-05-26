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
If that post-load-complete repair reaches field but the extra `Cross` opens the
in-field `Save game` prompt before the movement screenshot, classify it as a
save-prompt route miss, not moving gameplay. Remove the extra post-field
`Cross` and rerun the plain Down160 load-target-gated direct-left route.
If that plain Down160 direct-left rerun removes the save-prompt `Cross` but
stays on `Now Loading...` through late screenshots despite
`PATH_TO_TENUTO_PRESENT`, classify it as persistent loading, not a speed/FPS
proof. Do not fall back to generic state-aware routes and do not repeat the
save-prompt-opening repair. Run a Down160 no-movement load-stability diagnostic
that observes the post-confirm state with no field-side `Cross` or movement.
If that no-movement load-stability diagnostic passes `PATH_TO_TENUTO_PRESENT`
but stays on the Load UI with the `Load complete` banner through late
checkpoints, classify it as `titleload-down160-load-complete-waits-for-dismiss`.
Do not fall back to generic state-aware routes and do not add movement. Send
exactly one delayed post-load-complete `Cross`, then capture no-movement field
proof before any direct-left, first-battle, HLE, RSX, GPU, or speed work.
If that delayed single-dismiss no-movement proof reaches clean Path-to-Tenuto
field with `PATH_TO_TENUTO_PRESENT` and no save prompt, classify it as
`titleload-down160-late-dismiss-field-clean`. Keep the same late-dismiss base
and add exactly one direct-left movement pulse next. Do not fall back to generic
state-aware, old loader-control, first-battle, HLE, RSX, GPU, or speed work
until that movement boundary is proven.
If that late-dismiss direct-left pulse reaches field and stays clean after
`ls_left:200`, classify it as
`titleload-down160-late-dismiss-directleft-field-clean`. Keep the same
late-dismiss base and run only the left-only first-battle movement isolation
next (`ls_left:2600` without the down-left branch). Do not fall back to generic
state-aware, old loader-control, full battle, HLE, RSX, GPU, or speed work until
that larger left-only branch is classified.
If the left-only isolation aborts before slot `Cross` because the classifier
latched onto damaged/debug-like upper rows while a lower Path-to-Tenuto row is
visible, classify it as load-list cursor/classifier drift, not a wrong-save
target. Do not restore the already-matching checkpoint or fall back to generic
state-aware macros. Run a load-list cursor diagnostic or selected-row classifier
repair first. If a blind pre-gate `Up` normalization variant only produces
black-overlay gate screenshots, classify that variant as harness noise and do
not repeat it.
If that load-list cursor diagnostic proves title `Down:160` selects `LOAD` but
all intended load-list cursor screenshots are still the `Checking save files...`
progress dialog, classify it as `titleload-down160-loadlist-diagnostic-save-check-stall`.
Do not infer cursor behavior, do not fall back to generic state-aware macros,
and do not start speed/HLE/RSX/GPU work. Extend the diagnostic so it waits
through the save-check transition before sending `Up` or `Down`.
If the extended cursor diagnostic instead selects `LOAD` and then shows only
black/perf-overlay frames through the longer wait and cursor taps, classify it
as `titleload-down160-loadlist-diagnostic-black-transition`. Do not extend the
cursor diagnostic again. Re-prove the Down160 load-target gate with no cursor
input before another cursor, left-only, first-battle, HLE, RSX, GPU, or speed
step.
If that no-cursor Down160 load-target reproof has only 9 macro tokens, do not
classify it as a truncated launch. It is intentionally short. If it proves
`PATH_TO_TENUTO_PRESENT`, classify it as
`titleload-down160-loadtarget-reproof-passed`: route target repaired, still no
field/menu/battle proof, not speed, and not GPU migration. Resume only the
late-dismiss left-only first-battle movement isolation next.

If a latest `loader-control-left200x2-diag200` run passes field triage after
the `left200x2` boundary is re-proven, do not suggest the identical diagonal
command again. Bank it as route tooling only, still not speed and not GPU
migration, then pivot to a different proof axis such as Options/menu proof,
first-battle route repair, or focused SPU kernel HLE/codegen/verifier analysis.

If the latest clean run is a `0x25cc` / `9e4000` shadow verifier field proof,
do not fall through to generic state-aware movement or exact-EA skip reruns.
Treat it as HLE analysis only: exact command-level `eal == 0x9e4000` covers a
small slice of the max-DMA pattern family, and the current shadow/body path is
GET-only while the matched top pattern rows are PUT-heavy. The next step is
pattern/descriptor-level payload or LS-range hashing split by GET/PUT direction
for the top repeated groups before any fast/body promotion, Options/menu proof,
or battle proof.
After `debug-experiments/20260526-25cc-shadow-native-contract.md` exists, do
not create another 0x25cc planning report before source work. The next useful
round is a verify-only C++ instrumentation patch at the recorded `SPUThread.cpp`
anchors, then a Windows `Verify25ccShadow` rerun that emits direction-split
GET/PUT shadow rows. If PUT remains zero, classify the patch/run as a verifier
failure instead of moving to bodyfast, GPU compute, menu, or battle proof.
Once the local `rpcs3-upstream` source has the 25cc PUT finish-hook and
descriptor logger patch, do not make more native 25cc source changes or
planning ledgers until the patched Windows build/run is validated. The next
round must build or rerun `Verify25ccShadow`, then parse
`eternal-sonata-spu-hle-25cc-shadow-desc-profile.csv` and require nonzero
`direction=PUT` rows plus zero mismatches before any bodyfast, stack, GPU,
menu, or battle promotion.
If the patched buildcheck run is
`20260526-162731-cpu4-hle-25cc-shadow-desc-field-buildcheck-windows`, classify
it as source-instrumentation validated but route-invalid. It proved nonzero PUT
shadow coverage with zero mismatches, but the old `down:20`/`up` load macro
stayed on the Load menu and descriptor overflow reached `56`. Do not rerun that
macro, do not promote bodyfast, and do not start menu/battle/stack/GPU work
from it. The next 25cc proof must use the current Down160 late-dismiss
direct-left field route, and descriptor overflow must be widened or explicitly
treated as incomplete coverage.
After the sibling `rpcs3-upstream` descriptor table is widened from `16` to
`128` entries and rebuilt, treat that as instrumentation accounting only. Do
not claim speed or GPU migration from the build. The next 25cc proof must be a
fresh `Verify25ccShadow` Down160 late-dismiss direct-left field run, and it
must require clean field visuals, nonzero PUT descriptor rows, zero mismatches,
and descriptor overflow `0` before bodyfast, stack, GPU, menu, or battle
promotion. The refiner should emit
`hle-25cc-shadow-desc-buildcheck-route-miss` for the stale buildcheck and must
not suggest generic `stateaware-one-step`, old loader-control, or the old
`down:20`/`up` load macro.
If the latest
`cpu4-hle-25cc-shadow-desc-down160-latedismiss-directleft-field` proof is
clean, classify it as `valid-field-triage` and
`source-instrumentation-validated`, not speed, not GPU migration, and not a
200% gate result. Do not rerun field or fall back to the generic
`hle-25cc-shadow-pattern-gap` advice; the next 25cc rung is title Options/menu
proof with `Verify25ccShadow`, followed by first battle, before bodyfast,
stack, GPU, or speed promotion.
If that descriptor Options proof instead enters story/cutscene or field-like
intro frames, classify it as an Options route miss. Do not back off to generic
loader-control or field movement. The next command should remove the initial
title `Cross`, take a preinput screenshot, step down to Options, and open the
full title Options page with `Verify25ccShadow`.
If the no-initial-`Cross` Options proof reaches the title menu and selects
`Load` but then drifts into the intro/title loop before opening Options, do not
repeat the same route. Classify it as `options-nocross-wait-drift`; switch to a
fast Down160 title-menu route with short waits between `Down`, `Down`, and
`Cross`, keeping explicit title/selection screenshots and `Verify25ccShadow`.
If that fast Down160 Options proof reaches the full title Options page with the
0x25cc shadow/descriptor verifier clean, classify it as
`valid-options-triage` and `hle-25cc-shadow-desc-options-clean`. It is a menu
proof only: not speed, not GPU migration, and not a 200% result. Do not rerun
field or Options; the next required proof is first battle with
`Verify25ccShadow`.
If the follow-up 0x25cc descriptor first-battle `Verify25ccShadow` run reaches
field and battle/tutorial visuals but logs a PPU VM access violation at
`0x002aedd0` reading `0x40`, classify it as
`hle-25cc-shadow-desc-battle-fatal`. It is not first-battle proof, not speed,
not GPU migration, and not a 200% result, even if the visual gate sees
battle-like screenshots. Do not rerun the same TopSlot verifier command and do
not fall back to old loader-control. Isolate the same TopSlot battle route with
`Verify25ccShadow` off, or repair/state-gate the battle macro before another
verifier proof.

## Acceptance

A useful refiner pass leaves one concrete Windows-only action and prevents a
repeated invalid run. It also updates `debug-experiments/` or `AGENTS.md` when
the durable operating rule changes.
