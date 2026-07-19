# 2026-07-19 Thor Cool-title Proof Gate

## Result

- Classification: host-verified route-duration reduction and evidence gate.
- The `ThorCoolTitle` route now force-stops immediately after its title proof
  instead of entering a redundant one-second live scene-capture pass.
- A deterministic offline analyzer grants only `title-proof-ready`; it never
  grants FPS, speed, stability, or temperature credit.
- No ADB resolution, device query, install, launch, or temperature read ran in
  this work round. Thor remained stopped and cooling.

## Shorter Live Route

The reviewed macro is now:

`gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop`

After the title-ready gate succeeds, the route:

1. saves a dedicated title screenshot;
2. reclassifies that exact image as the Eternal Sonata title menu;
3. scans the current guest-log tail for fatal evidence; and
4. force-stops RPCSX inside the macro.

`Invoke-AndroidRouteScene` then resolves the just-created input capture, runs
the offline proof analyzer, and returns. It no longer calls
`Invoke-AndroidSceneCapture` for this profile. This removes the extra live
one-second interval plus its pre-capture, per-second, pre-proof, and post-proof
guard work, final screenshot, thread snapshots, and graphics-info queries.
Normal route profiles retain the existing scene-capture behavior.

This is a code-path reduction, not a measured thermal improvement. The dominant
startup cost remains guest compilation and cache load, and only a future cool
device proof can quantify temperature or time.

## Exact Activation Evidence

`thor_input_macro.ps1` now records `startup-profile-effective.txt` with one
combined pre-boot ADB shell command. It captures 26 properties at the same
instant without paying for 26 additional ADB round trips:

- RSX workers, RSX/SPU preload limits, compile budgets, and SPU native objects;
- cache-worker affinity, Vulkan cache/hit-only mode, ADPF, and phase pacing;
- quiet logcat/syscall/reduced-loop/SPURS controls;
- disabled semaphore, DMA, blit, auditor, and PRX experiments;
- frame wait, grace, and continuous rearm; and
- Android `RPCS3` / `RPCSX-UI` log priorities.

The analyzer also checks the existing individual effective-value captures and
the input-macro README, so a partial, stale, or hand-assembled profile cannot
silently qualify.

## Fail-closed Analyzer

`tools/analyze_thor_cool_title_capture.ps1` requires all of the following:

- exact cool-title property values;
- the exact five-token macro sequence, `macro-stop.txt`, and a stopped post-proof PID;
- two consecutive title-ready classifications from the PPU-ready gate;
- a final `*-title-proof.png` that independently classifies as the title menu;
- no macro failure, thermal `status=failed`, guest fatal, or activation fallback;
- runtime rows proving RSX/SPU bounds `256/64`, two RSX workers, three SPU
  workers, exact `0x07` affinity, warm Vulkan hit-only preload, and phase pacing.

Its statuses distinguish thermal stop, fatal, missing/invalid title evidence,
incomplete activation, and a valid title proof. Even the valid state sets
`speed_credit=false`; it authorizes only a later correctness-locked A/B.

Replaying the rejected capture
`debug-captures/android-speed-sprint/20260719-163325-thor-input-custom`
produces:

- `status=thermal-stop-before-title`;
- `ready_for_comparison=false`;
- `speed_credit=false`;
- maximum observed silicon `68.7 C`; and
- explicit mismatches for the old zero-valued RSX worker/preload, SPU preload,
  affinity, and Vulkan hit-only controls.

## Verification

Passed host-only:

- PowerShell AST parsing for all changed and added scripts;
- ready, activation-mismatch, still-running, thermal-stop, and fatal synthetic fixtures;
- `-RequireReady` fail-closed behavior;
- replay classification of the rejected hot capture;
- exact profile dry-run and unsafe-override contracts;
- all `58/58` `tools/test_thor_*.ps1` contracts; and
- `git diff --check`.

The proof-tooling changes alone needed no native rebuild. A later SPU worker-pool
cap refreshed the exact combined APK to `5C3911D0...682CC6`; that current
candidate remains uninstalled and still requires a separate strict cool
no-launch install round before any later title proof.
