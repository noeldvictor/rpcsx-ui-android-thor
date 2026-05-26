# 2026-05-25 Continual Harness Skill Audit

## Trigger

The user called out that the sprint was going in circles. The immediate symptom
was real: after the full `bodyfast + RSX geometry/locality` stack failed, the
refiner still recommended the same full stack because an older opportunity rule
outranked the newest failed run.

## Continual-Harness Adaptation

Source idea: `https://github.com/sethkarten/continual-harness`.

Useful parts for this repo:

- keep a recent trajectory window;
- use a clear oracle, here visual/log/host/counter gates;
- mutate the harness or plan after a failure;
- preserve the best known valid state;
- do not keep sampling the same failed path.

Rejected parts for this repo:

- no open-ended autonomous mutation loop;
- no unbounded experiment generation;
- no Android/ADB/Thor action while the Windows 200% gate is active;
- no speed or GPU claims from invalid visual states.

## Skill Audit

No skill folders were deleted in this pass. Deleting the named PS3 skills would
make the heartbeat prompt point at missing skills and create a new loop. Instead
the active skills were tightened and Android/ADB skills were marked dormant for
the current Windows-only gate.

Active Windows sprint skills:

- `codex-goal-loop`: now stops experimentation and repairs the plan when the
  user says the loop is circular or the newest run invalidates the current plan.
- `ps3-debug-knowledge`: now requires checking the newest failed run before
  following older next-action notes.
- `ps3-speed-proof-gate`: now has explicit stacking and stack-regression rules.
- `ps3-rsx-experiment-gate`: now blocks "more GPU toggles" after combined-stack
  failure and requires bisection.
- `ps3-continual-harness-refiner`: replaced with a shorter loop-breaker
  protocol centered on newest evidence, blockers, and bisection.
- `thor-game-controller`, `thor-spu-codegen-hotpath`,
  `thor-windows-android-ab`, and `windows-powershell-operator`: still useful as
  focused support skills.

Dormant until the Windows gate reopens Android work:

- `thor-adb-operator`;
- `thor-scene-route`;
- `thor-screenshot-burst`;
- Android-facing parts of `thor-windows-android-ab`.

## Tooling Fix

`tools\ps3_harness_refiner.ps1` now recognizes:

- latest run decision: `failed-window-lost-after-field`;
- label family: `bodyfast + rsx-geomstack + battle`;
- blocker: `hle-25cc-bodyfast-rsx-geomstack-window-lost`;
- correct next command: bodyfast plus geometry-only vertex/index cache bisection.

The refiner should no longer recommend the same full combined stack after that
failure.

## New Operating Rule

Newest failure outranks older opportunity.

If the latest run failed a route/window/visual/log gate:

1. classify it;
2. update the refiner or ledger;
3. repair or bisect;
4. only then run another experiment.

If a combined stack fails:

1. do not rerun the same full stack;
2. do not add another candidate;
3. bisect from the last known-good component.

## Immediate Plan

The next experiment, if resumed, is not another full stack. It is the smaller
bodyfast plus geometry-only bisection:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-geometryonly-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

This is a bisection run, not a 200% gate attempt.
