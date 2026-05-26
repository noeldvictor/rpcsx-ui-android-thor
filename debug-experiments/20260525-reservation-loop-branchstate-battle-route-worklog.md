# 2026-05-25 Reservation Loop Branch-State Battle Route Worklog

Goal:

- Test the post-RSX pivot suggested by the refiner: a CPU4-affinity
  `ReservationLoop Verify` run on the TopSlot BattleRoute.
- Determine whether reservation-loop branch-state counters can be promoted into
  the next SPU/PPU/codegen lane.
- Keep this Windows-only on screen 1. No Android, ADB, or Thor work was run.

Run:

- `debug-captures\windows-lab\20260525-224813-cpu4-reservation-loop-branchstate-verify-battle-topslot-battleroute-windows`

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-reservation-loop-branchstate-verify-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

Visual and host evidence:

- Visual gate: `FIELD_LIKE_PRESENT`, but gate result `failed`.
- First field-like screenshot: `screenshot-0117s.png` at `117s`, `2.50 MB`.
- Manual screenshot review confirmed clean Path to Tenuto field gameplay on
  screen 1.
- Required field by `160s`: passed.
- Required field at or after `220s`: failed.
- Required field-like screenshot count `2`: failed, found `1`.
- Required battle-like at or after `200s`: failed, found `0`.
- The game window/process was gone before the next proof point:
  screenshot skipped at `169s`, `230s`, and `290s` because the game window was
  not found and the process had exited.
- Process exit was recorded before the `330s` max.
- Host contention: `ExternalFail` stayed clean across prelaunch, postlaunch,
  and postrun snapshots.
- Window-title FPS sample at the only screenshot was `32.54 FPS`.
- Fatal-marker scan found no real access violation, assertion, Vulkan
  validation error, `VK_ERROR`, `SIGSEGV`, or `SIGBUS`; the broad text scan only
  hit ppu_loader symbol names containing `ExceptionEventHandler`.

Probe counters:

- GPU probe records: `846`.
- Total observed DMA bytes: `1,048.32 MB`.
- Offload fit: `spu-kernel-hle=505`, `too-small=341`.
- Hot PCs:
  - `0x25cc`: `339` records, `533.92 MB`, top group
    `CellSpursKernelGroup`.
  - `0x451c`: `507` records, `514.39 MB`, top group
    `TCX_CellSpursKernelGroup`.
- Top candidate: `0x451c` / `TCX_CellSpursKernel0`, `16.74 MB`, with
  `2.29 MB` GET, `6.53 MB` PUT, and `7.92 MB` list GET.
- MFC dynamic records: `846`; dynamic MFC hits `114,827`, bytes
  `255.12 MB`, total timing `82.885 ms`.
- MFC list-transfer calls: `42,887`, total timing `33.470 ms`.
- MFC wait reads: `5,242,116`, all fast, `0` blocking reads.
- Reservation loop command records: `938`.
- Reservation loop command exact-PC records: `25,277`.
- Reservation loop verify records: `3,199`.
- Reservation loop RDCH join records: `3`.
- Reservation loop lane-join records: `3`.
- Reservation loop raw-lane records: `8`.
- PUTLLC16 analyzer records: `43`.
- Promoted CPU/SPU -> GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-window-lost-after-field`.
- Useful SPU/reservation-loop profiling evidence, but not a valid route proof.
- Not a speed win.
- Not `windows-micro-win`.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.
- Do not start lane-2 HLE/GPU fast mode from this run's clean counters. Visual,
  menu/Options, and first-battle proof is missing.

Refiner outcome:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` correctly classifies the newest
  run as `failed-window-lost-after-field`.
- The next action has been reduced from another battle route to a smaller
  field-only state-aware movement repair:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

Next:

- Run the one-step `CleanAfterField` command before any broader battle-route
  reservation-loop proof.
- Keep broad SPU Vulkan compute parked: this trace still shows `0 B` RSX-local
  traffic and `0 B` indirect RSX overlap.
- Treat `0x25cc` and `0x451c` as SPU HLE/codegen/reservation-loop candidates,
  not GPU-dispatch candidates, unless a later verified trace proves
  GPU-resident batch consumption.

## 2026-05-25 State-Aware Damaged-Save Route Repair

Goal:

- Stop the reservation-loop field repair from replaying a bad route.
- Distinguish prompt-stuck and save-prompt field output from real moving
  gameplay before any HLE/GPU promotion.
- Keep this Windows-only on screen 1. No Android, ADB, or Thor work was run.

Failed default one-step run:

- `debug-captures\windows-lab\20260525-232051-cpu4-stateaware-one-step-visualgate-windows-windows`
- Command used the default field macro with `ReservationLoop Verify`,
  `CleanAfterField`, CPU affinity `0x0F`, and screen 1.
- Visual gate: `NO_FIELD_LIKE_SCREENSHOT`, primary class
  `wrong-window-or-other-small-png`.
- Manual image review showed the damaged-save load confirmation prompt, not a
  wrong desktop window.
- Counters are invalid for promotion: `835` records, `864.46 MB` observed DMA,
  hot PCs `0x25cc` and `0x451c`, and GPU port scoreboard still `0 B` in every
  bucket.
- Classification: `failed-visual-gate`, `route-tooling`, `load-confirm-prompt-stuck`.

Repaired damaged-confirm run:

- `debug-captures\windows-lab\20260525-233009-cpu4-stateaware-damaged-confirm-left200-visualgate-windows-windows`
- The macro added an extra post-prompt `cross:120`, delayed screenshots, then
  attempted one `ls_left:200` field step.
- Visual gate was regenerated after the wrapper timeout and passed:
  `FIELD_LIKE_PRESENT`, first field-like `screenshot-0133s.png` at `133s`,
  `8` field-like screenshots, `0` invalid screenshots after first field-like,
  and field by `160s` passed.
- Manual screenshots `screenshot-0133s.png` and `screenshot-0175s.png` show
  clean Path to Tenuto rendering, but the `Save game` / `Don't save game`
  prompt is still open, so this is not moving gameplay.
- Window-title FPS samples during the prompt ranged from `21.54` to `33.35`,
  but they are route-state samples, not a speed comparison.
- Fatal scan was clean after filtering false `ExceptionEventHandler` symbol
  hits.

Counters from the repaired run:

- GPU probe records: `1,264`.
- Total observed DMA bytes: `1,822.96 MB`.
- Offload fit: `spu-kernel-hle=889`, `too-small=375`.
- Hot PCs:
  - `0x25cc`: `622` records, `1,003.91 MB`.
  - `0x451c`: `642` records, `819.05 MB`.
- Dynamic MFC hits: `190,787`, `447.59 MB`, `244.207 ms`.
- MFC list-transfer calls: `69,806`, `60.396 ms`.
- Reservation loop verify records: `4,710`.
- Reservation loop command exact-PC records: `36,737`.
- Lane 2 stayed clean: `6941/6941/6941/0/0`.
- Promoted CPU/SPU -> GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `valid-field-triage-but-save-prompt`.
- Useful route repair and SPU/reservation-loop target sizing only.
- Not moving gameplay.
- Not a speed win.
- Not `windows-micro-win`.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/refiner outcome:

- `tools\ps3_harness_refiner.ps1` now recognizes both prompt states:
  `stateaware-load-confirm-prompt-stuck` and
  `stateaware-save-prompt-field-not-moving`.
- The suggested command is now the damaged-confirm dismiss-save macro:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-damaged-confirm-dismiss-save-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;cross:120;wait:15000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 185 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8
```

Next:

- Run the dismiss-save field command before any broader battle-route
  reservation-loop proof.
- Keep lane-2 HLE/GPU fast modes blocked until field, menu/Options, and
  first-battle visuals are valid in the same stack.

## 2026-05-26 Dismiss-Save Route Rejection

Goal:

- Test the refiner's damaged-confirm dismiss-save route after the previous run
  reached field rendering but parked on the save-point prompt.
- Keep this Windows-only on screen 1. No Android, ADB, or Thor work was run.

Run:

- `debug-captures\windows-lab\20260525-235739-cpu4-stateaware-damaged-confirm-dismiss-save-left200-visualgate-windows-windows`

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-damaged-confirm-dismiss-save-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;cross:120;wait:15000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 185 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8
```

Visual/log proof:

- Visual gate: `NO_FIELD_LIKE_SCREENSHOT`.
- All `9` screenshots were `wrong-window-or-other-small-png` by the
  field-only classifier.
- Manual screenshots show the Load screen and `Load data from this file.
  Proceed?` prompt at `screenshot-0133s.png`, then the Load list through
  `screenshot-0185s.png`.
- Host contention stayed clean across `6` snapshots.
- Fatal-marker scan was clean after excluding known non-fatal symbol text.
- Title-bar FPS samples ranged from `31.88` to `56.11`, but these are Load UI
  samples, not field or moving-gameplay speed evidence.

Counters:

- GPU probe records: `1,243`.
- Total observed DMA bytes: `1,279.18 MB`.
- Offload fit: `spu-kernel-hle=671`, `too-small=572`.
- Hot PCs:
  - `0x25cc`: `439` records, `675.88 MB`.
  - `0x451c`: `804` records, `603.30 MB`.
- Dynamic MFC hits: `130,418`, `315.38 MB`, `122.073 ms`.
- MFC list-transfer calls: `48,710`, `26.522 ms`.
- Reservation loop verify records: `4,903`.
- Reservation loop command exact-PC records: `39,000`.
- Lane 2 stayed clean: `8299/8299/8299/0/0`.
- Promoted CPU/SPU -> GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-visual-gate`, `route-tooling`, `load-menu-miss`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `windows-micro-win`.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/refiner outcome:

- `tools\ps3_harness_refiner.ps1` now recognizes
  `stateaware-dismiss-save-load-menu-miss`.
- It blocks the old default field macro and the dismiss-save macro after this
  state, and suggests the late load-confirm repair:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-late-load-confirm-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 175 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;up:80;wait:300;cross:120;wait:35000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8
```

Next:

- Run the late load-confirm repair before any save-prompt dismissal, broader
  battle route, or fast-mode promotion.

## 2026-05-26 Late Load-Confirm And Double-Confirm Rejection

Goal:

- Repair the state-aware field route after the dismiss-save macro stayed in the
  Load/Proceed screen.
- Keep this Windows-only on screen 1. No Android, ADB, or Thor work was run.

Late load-confirm run:

- `debug-captures\windows-lab\20260526-001938-cpu4-stateaware-late-load-confirm-left200-visualgate-windows-windows`
- Visual gate: `NO_FIELD_LIKE_SCREENSHOT`; no field-like screenshot at or
  before `175s`.
- Manual screenshots show the `Load data from this file. Proceed?` prompt with
  `Yes` highlighted from `screenshot-0154s.png` through `screenshot-0205s.png`.
- Diagnosis: the macro opened the prompt but did not send the second `Cross`
  needed to accept it.
- Host and fatal scans were clean after excluding known `ExceptionEventHandler`
  symbol text.
- Classification: `failed-visual-gate`, `route-tooling`,
  `late-load-confirm-needs-second-cross`.

Corrected double-confirm run:

- `debug-captures\windows-lab\20260526-003206-cpu4-stateaware-late-load-doubleconfirm-dismisssave-left200-visualgate-windows-windows`
- Visual gate: `NO_FIELD_LIKE_SCREENSHOT`; no field-like screenshot at or
  before `185s`.
- Manual screenshots show the Load list selected `Debug Save` / `Prologue`, not
  the known Path to Tenuto save target. Later `down` input moved the cursor to
  a `File does not exist` row because the run never reached field/save prompt.
- Host and fatal scans were clean.

Corrected-run counters:

- GPU probe records: `1,458`.
- Total observed DMA bytes: `1,547.96 MB`.
- Offload fit: `spu-kernel-hle=816`, `too-small=642`.
- Hot PCs:
  - `0x25cc`: `547` records, `849.44 MB`.
  - `0x451c`: `911` records, `698.52 MB`.
- Dynamic MFC hits: `152,217`, `385.90 MB`, `155.355 ms`.
- MFC list-transfer calls: `56,079`, `41.624 ms`.
- Reservation loop verify records: `5,451`.
- Reservation loop command exact-PC records: `43,279`.
- Lane 2 stayed clean: `10464/10464/10464/0/0`.
- Promoted CPU/SPU -> GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- Both runs are `failed-visual-gate` / `route-tooling`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `windows-micro-win`.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/refiner outcome:

- `tools\ps3_harness_refiner.ps1` now recognizes
  `stateaware-late-load-confirm-needs-second-cross` and suggests the
  double-confirm route after the one-cross prompt miss.
- It also recognizes
  `stateaware-late-doubleconfirm-wrong-save-target` and stops automatic
  state-aware reruns when the double-confirm route selects `Debug Save` /
  `Prologue` instead of Path to Tenuto.

Next:

- Repair save-target selection or add route-state/OCR gating that proves Path
  to Tenuto is selected before pressing `Cross`.
- Keep lane-2 HLE/GPU fast modes blocked until field, menu/Options, and
  first-battle visuals are valid in the same stack.

## 2026-05-26 Load Target Classifier Gate

Purpose:

- Replace manual-only Load-list inspection with a deterministic local route
  state gate before another state-aware macro can press `Cross`.
- Keep Load UI counters from polluting speed, HLE/GPU, or 200% gate claims.

Change:

- Added `tools\classify_eternal_sonata_load_target.ps1`.
- The script compares a stable Load-list crop against the known good Path to
  Tenuto exemplar from
  `20260526-001938-cpu4-stateaware-late-load-confirm-left200-visualgate-windows-windows`
  and the known bad Debug Save / Prologue exemplar from
  `20260526-003206-cpu4-stateaware-late-load-doubleconfirm-dismisssave-left200-visualgate-windows-windows`.
- It writes `eternal-sonata-load-target-summary.md` in the run directory and
  can enforce `-RequirePathToTenuto`.

Validation:

- Good run:
  `.\tools\classify_eternal_sonata_load_target.ps1 -RunDir 'debug-captures\windows-lab\20260526-001938-cpu4-stateaware-late-load-confirm-left200-visualgate-windows-windows' -RequirePathToTenuto`
  reported `PATH_TO_TENUTO_PRESENT`, with `12` Path-to-Tenuto rows, `0`
  Debug-Save rows, and `0` unknown rows.
- Bad run:
  `.\tools\classify_eternal_sonata_load_target.ps1 -RunDir 'debug-captures\windows-lab\20260526-003206-cpu4-stateaware-late-load-doubleconfirm-dismisssave-left200-visualgate-windows-windows'`
  reported `DEBUG_SAVE_PROLOGUE_PRESENT`, with `13` Debug-Save rows, `0`
  Path-to-Tenuto rows, and `0` unknown rows.
- Parser validation passed for the classifier.

Classification:

- `process-harness`, `route-tooling`, `load-target-gate`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Do not run another automatic state-aware route from the wrong-save-target
  state until the candidate Load-list capture gates as only
  `PATH_TO_TENUTO_PRESENT`.
- If the classifier reports `DEBUG_SAVE_PROLOGUE_PRESENT`,
  `MIXED_LOAD_TARGETS`, or `UNKNOWN_LOAD_TARGET`, repair save-target selection
  before pressing `Cross`.

## 2026-05-26 Live Load Target Macro Gate

Purpose:

- Prevent another blind Load-list `Cross` after the route drifted from Path to
  Tenuto to Debug Save / Prologue.
- Turn the offline load-target classifier into a live Windows macro guard.

Change:

- Added `gate_load_target`, `assert_load_target`, and `load_target_gate` tokens
  to `tools\windows_rpcs3_lab.ps1`.
- The token captures a tagged screenshot, runs
  `tools\classify_eternal_sonata_load_target.ps1 -RequirePathToTenuto`, writes
  `eternal-sonata-load-target-summary.md`, and aborts the macro before pressing
  `Cross` if the selected Load-list target is not only
  `PATH_TO_TENUTO_PRESENT`.
- `tools\ps3_harness_refiner.ps1` now inserts `gate_load_target` before the
  first Load-list `Cross` in the state-aware double-confirm repair command and
  changes the newest wrong-save-target state from a blind retry blocker into a
  load-target-gated diagnostic.

Validation:

- Parser validation passed for `tools\windows_rpcs3_lab.ps1` and
  `tools\ps3_harness_refiner.ps1`.
- The refiner now emits the gated command label
  `cpu4-stateaware-loadtarget-gated-doubleconfirm-dismisssave-left200-visualgate-windows`.
- Local save inspection found the current RPCS3 `BLUS3016100\PARAM.SFO` and
  existing backup/checkpoint folders still advertise `Ch. 1 Raindrops Path to
  Tenuto South Section`, so no save mutation was performed in this round.

Classification:

- `process-harness`, `route-tooling`, `load-target-gate`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run the refiner-emitted gated diagnostic only if no newer run is active. If
  `gate_load_target` aborts on Debug Save / Prologue, restore or repair the
  Path-to-Tenuto save source before continuing route or speed work.

## 2026-05-26 Polling Load Target Gate And Direct-Left Refiner

Purpose:

- Stop the state-aware route loop from using stale one-shot Load-list proof.
- Separate three states that were previously collapsed as `UNKNOWN_LOAD_TARGET`:
  transient save-file checking, real wrong-save target, and black-screen route
  timeout.

Changes:

- `tools\windows_rpcs3_lab.ps1` now treats `gate_load_target`,
  `assert_load_target`, and `load_target_gate` as polling guards. The token
  duration is the poll timeout; it screenshots repeatedly until
  `PATH_TO_TENUTO_PRESENT`, fails immediately on `DEBUG_SAVE_PROLOGUE_PRESENT`
  or `MIXED_LOAD_TARGETS`, and writes `load-target-gate-failed.txt` on timeout.
- `tools\ps3_harness_refiner.ps1` now reads
  `eternal-sonata-load-target-summary.md` plus
  `load-target-gate-failed.txt`, emits `failed-load-target-gate`, and shows a
  Load target column in the recent-run table.
- The refiner now blocks the obsolete post-load dismiss-save sequence after it
  proves it opens the Save/Create-new-file menu, and suggests only
  `cpu4-stateaware-loadtarget-pollgated-directleft200-longgate-visualgate-windows`
  after a direct-left black/unknown gate timeout.

Run evidence:

- `20260526-011701-cpu4-stateaware-loadtarget-gated-doubleconfirm-dismisssave-left200-visualgate-windows-windows`
  aborted before slot `Cross` with `DEBUG_SAVE_PROLOGUE_PRESENT`. Manual
  screenshot showed Debug Save / Prologue and a damaged-save message. Host and
  fatal scans were clean. GPU scoreboard stayed `0 B` promoted CPU/SPU to GPU,
  `0 B` direct RSX-local, and `0 B` indirect overlap.
- Restored the known checkpoint from
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100` after
  backing up the current RPCS3 save to
  `debug-captures\save-backups\BLUS3016100-before-live-gate-restore-20260526-012048`.
  `PARAM.SFO` again advertised `Ch. 1 Raindrops Path to Tenuto South Section`.
- `20260526-013113-cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows-windows`
  proved the polling gate: first screenshot was transient
  `Checking save files...`, second screenshot
  `screenshot-0065s-load-target-gate-2.png` classified
  `PATH_TO_TENUTO_PRESENT`, and field appeared at `screenshot-0120s.png`
  (`120s`). The route still failed `CleanAfterField` because later screenshots
  stayed on Save/Create-new-file UI after the obsolete field-side dismiss-save
  presses. Classify as route-tooling, not moving gameplay and not speed.
- `20260526-014524-cpu4-stateaware-loadtarget-pollgated-directleft200-visualgate-windows-windows`
  tested direct-left without the obsolete Save-menu presses, but the 30s gate
  never reached a classifiable Load slot. All gate screenshots were black
  `UNKNOWN_LOAD_TARGET`; the macro aborted before slot `Cross`. Host and fatal
  scans were clean. GPU summary is route-invalid: `663` records,
  `649.96 MB` observed DMA, offload fit `too-small=347` /
  `spu-kernel-hle=316`, lane 2 `6713/6713/6713/0/0`, and GPU Port Scoreboard
  `0 B` promoted CPU/SPU to GPU, `0 B` direct RSX-local, `0 B` indirect
  overlap.

Validation:

- Parser validation passed for `tools\windows_rpcs3_lab.ps1` and
  `tools\ps3_harness_refiner.ps1`.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` now reports newest decision:
  direct-left route timed out with black/`UNKNOWN_LOAD_TARGET` gate captures
  and suggests the long-gate direct-left command only.
- No lingering RPCS3/RPCSX process remained after the runs.

Classification:

- `process-harness`, `route-tooling`, `load-target-gate`, `directleft-gate-timeout`.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only the long-gate direct-left proof. Do not fall back to the old
  dismiss-save macro, because it already proved field then opened the Save menu.
- Keep HLE/RSX speed stacking blocked until the same route proves correct field,
  menu/Options, and first-battle visuals.

## 2026-05-26 Long-Gate Direct-Left Cutscene Route Miss

Purpose:

- Test whether the direct-left `UNKNOWN_LOAD_TARGET` failure was only a short
  30s gate timeout, or whether the route was entering the wrong game state.
- Stop the refiner from asking for the same route again when screenshots prove
  it missed the Load list.

Run evidence:

- Windows run
  `20260526-020147-cpu4-stateaware-loadtarget-pollgated-directleft200-longgate-visualgate-windows-windows`
  used PadApi, screen 1, CPU affinity `0x0F`, `ReservationLoop Verify`,
  `CleanAfterField`, and a `gate_load_target:60000` guard before slot `Cross`.
- The load-target gate timed out with classifier status
  `UNKNOWN_LOAD_TARGET` and aborted before pressing slot `Cross`.
- Manual screenshot review rejected the visual byte-size heuristic:
  `screenshot-0079s-load-target-gate-9.png` showed a story/cutscene tree scene,
  and `screenshot-0122s-load-target-gate-25.png` showed a story/cutscene star
  scene with the subtitle `Emilia.`. These are not the Load list, not Path to
  Tenuto field gameplay, and not moving-gameplay proof.
- Host contention was clean, stderr was empty, no lingering RPCS3/RPCSX process
  remained, and fatal scan found no crash/access/Vulkan/assertion hit.
- GPU summary is route-invalid only: `863` records, `1,288.98 MB` observed DMA,
  offload fit `spu-kernel-hle=639` / `too-small=224`, hot PCs `0x25cc`
  (`679.52 MB`) and `0x451c` (`609.47 MB`), dynamic MFC `142,984` hits /
  `323.36 MB` / `189.669 ms`, list-transfer `52,930` calls / `59.812 ms`, lane
  2 `11717/11717/11717/0/0`, and GPU Port Scoreboard `0 B` promoted CPU/SPU to
  GPU, `0 B` direct RSX-local, `0 B` indirect overlap.

Change:

- `tools\ps3_harness_refiner.ps1` now separates the old black
  direct-left timeout from the newer long-gate cutscene route miss.
- The refiner emits `directleft-longgate-entered-cutscene` and no automatic
  rerun command when a long-gate direct-left capture is
  `UNKNOWN_LOAD_TARGET` with story/cutscene or other non-field screenshots.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same operating rule.

Classification:

- `process-harness`, `route-tooling`,
  `directleft-longgate-entered-cutscene`, `load-target-gate`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Do not run another direct-left long-gate retry from this state.
- Repair the title-to-Load input timing or add a title/menu/load-list state gate
  before pressing slot `Cross`.
- Keep speed stacking and HLE/RSX promotion blocked until correct field,
  menu/Options, and first-battle visuals are proven again.

## 2026-05-26 Load-Target Wrong-State Early Abort

Purpose:

- Convert the manually reviewed long-gate cutscene miss into live harness
  behavior so future `gate_load_target` runs do not wait the full timeout while
  already in story/cutscene.
- Preserve the good behavior that lets black/loading/save-check transients poll
  until a real Load-list target appears.

Change:

- `tools\windows_rpcs3_lab.ps1` now returns the saved PNG path from
  `Save-LabScreenshot`.
- `Invoke-LabLoadTargetGate` classifies each polling screenshot with lightweight
  color/size rules mirroring the refiner's non-field detector.
- When the load-target classifier remains `UNKNOWN_LOAD_TARGET` and the gate
  sees repeated obvious `cutscene-or-nonfield-*` screenshots, it writes a
  `wrong-state/cutscene` marker and aborts early before slot `Cross`.
- Black/loading/other unknown screenshots still reset the wrong-state streak and
  continue polling until the normal timeout.
- `tools\ps3_harness_refiner.ps1` also recognizes a
  `wrong-state/cutscene` load-target marker as equivalent to the manually
  reviewed long-gate route miss, so it emits no automatic direct-left rerun.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` were
  updated with the standing rule.

Validation:

- Parser validation passed for `tools\windows_rpcs3_lab.ps1` and
  `tools\ps3_harness_refiner.ps1`.
- `git diff --check` had only the repo's normal CRLF warnings.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` still reports the latest
  long-gate direct-left cutscene route miss and emits no automatic rerun.

Classification:

- `process-harness`, `route-tooling`, `load-target-gate`,
  `wrong-state-early-abort`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Repair the title-to-Load route timing or add a specific title/menu/load-list
  state gate. Do not start HLE/RSX stacking from invalid route counters.

## 2026-05-26 Title-To-Load Diagnostic Command

Purpose:

- Replace the inert "no automatic rerun" refiner output with one bounded
  Windows-only diagnostic that captures the missing title/menu/load-list state.
- Keep the safety property that no save-slot `Cross` is sent unless the live
  `gate_load_target` classifier proves `PATH_TO_TENUTO_PRESENT`.

Change:

- Added `New-StateAwareTitleToLoadDiagnosticCommand` to
  `tools\ps3_harness_refiner.ps1`.
- When the newest evidence is `directleft-longgate-entered-cutscene`, the
  refiner now suggests
  `cpu4-title-to-load-state-diagnostic-windows` instead of a comment or another
  long-gate retry.
- The diagnostic uses PadApi on Windows screen 1, CPU affinity `0x0F`,
  frame/vblank `240`, `ReservationLoop Verify`, and `WindowsVisualGate Off`.
  Its macro screenshots title settle, after title `Down`, after title `Cross`,
  and pre-load-target gate, then runs `gate_load_target:25000` without pressing
  the save slot.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same operating rule.

Classification:

- `process-harness`, `route-tooling`, `title-to-load-diagnostic`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run the title-to-Load diagnostic, inspect the named screenshots and
  `load-target-gate-failed.txt`, then repair only the title/menu/load-list
  transition before any movement or speed stacking.

## 2026-05-26 Title-To-Load Short-Down Miss

Purpose:

- Execute the title-to-Load diagnostic and determine whether the route reaches
  the Load list before any save-slot `Cross`.

Run evidence:

- Windows run
  `20260526-023814-cpu4-title-to-load-state-diagnostic-windows-windows` used
  PadApi, screen 1, CPU affinity `0x0F`, frame/vblank `240`,
  `ReservationLoop Verify`, and `WindowsVisualGate Off`.
- The diagnostic captured the title/menu transition and aborted before any
  save-slot `Cross`.
- Manual screenshot review:
  - `screenshot-0068s-title-settle.png` showed the title menu.
  - `screenshot-0069s-title-after-down.png` still showed the title menu after
    the short `Down:20` press.
  - `screenshot-0081s-post-title-cross.png` entered New Game/story cutscene,
    proving the short Down did not select Load.
  - `screenshot-0084s-pre-load-target-gate.png` and
    `screenshot-0087s-load-target-gate-2.png` were story/cutscene frames, not
    Load list and not field.
- `load-target-gate-failed.txt` reports:
  `wrong-state/cutscene while waiting for Load list`.
- Load-target summary status was `UNKNOWN_LOAD_TARGET`, with all six
  screenshots classified unknown by crop comparison.
- Host checks were clean, stderr was empty, and no RPCS3/RPCSX process remained
  after the run. The command wrapper timed out after the run output, but the lab
  log records RPCS3 exited at `89s` before `MaxSeconds 125`.

Change:

- `tools\ps3_harness_refiner.ps1` now recognizes a failed
  `title-to-load-state-diagnostic` cutscene/wrong-state result as
  `title-to-load-diagnostic-entered-newgame`.
- Added `New-StateAwareTitleToLoadDownHoldDiagnosticCommand`, which uses a
  longer title `Down:160` hold, named screenshots, and a
  `gate_load_target:30000` guard without pressing the save slot.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same rule.

Classification:

- `route-tooling`, `title-to-load-diagnostic-entered-newgame`,
  `load-target-gate`, `wrong-state/cutscene`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only `cpu4-title-to-load-down160-state-diagnostic-windows`.
- Do not fall back to double-confirm, direct-left long-gate, speed stacking, or
  HLE/RSX promotion until the Load selection is proven before slot `Cross`.

## 2026-05-26 Title Down160 Load-Target Proof

Purpose:

- Test whether a longer title `Down` press selects Load and reaches the known
  Path to Tenuto save target before any save-slot `Cross`.

Run evidence:

- Windows run
  `20260526-025935-cpu4-title-to-load-down160-state-diagnostic-windows-windows`
  used PadApi, screen 1, CPU affinity `0x0F`, frame/vblank `240`,
  `ReservationLoop Verify`, and `WindowsVisualGate Off`.
- Manual screenshot review:
  - `screenshot-0069s-title-after-down160.png` showed `Load` selected on the
    title menu.
  - `screenshot-0082s-post-title-cross-down160.png` showed the expected
    `Checking save files...` Load screen.
  - `screenshot-0092s-load-target-gate-4.png` showed `Save File 01`, `Polka`,
    `Path to Tenuto South Section`, and `Ch. 1 Raindrops`.
- The load-target classifier reported `PATH_TO_TENUTO_PRESENT` after attempt
  4. Earlier attempts were transient Load UI / save-check frames.
- Host checks were clean, no RPCS3/RPCSX process remained, and the run was
  stopped by `MaxSeconds 140` after the diagnostic intentionally ended without
  pressing the save slot.
- GPU/counter output remains route-diagnostic only: `946` candidate rows,
  `948.60 MB` observed DMA, offload fit `spu-kernel-hle=475` /
  `too-small=471`, hot PCs `0x451c` (`539.05 MB`) and `0x25cc`
  (`409.55 MB`), and GPU Port Scoreboard `0 B` promoted CPU/SPU-to-GPU,
  `0 B` direct RSX-local, `0 B` indirect overlap.

Change:

- `tools\ps3_harness_refiner.ps1` now recognizes a down160 title-to-Load
  diagnostic with `PATH_TO_TENUTO_PRESENT` as a route checkpoint, not a generic
  wrong-window failure.
- Added `New-StateAwareTitleToLoadDownHoldDirectLeftCommand`, which repeats the
  proven `Down:160` title route, gates `PATH_TO_TENUTO_PRESENT`, then presses
  the save slot and attempts the direct-left movement proof under
  `CleanAfterField`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same next-step rule.

Classification:

- `route-tooling`, `title-down160-load-target-proof`.
- Not field.
- Not moving gameplay.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only
  `cpu4-titleload-down160-pollgated-directleft200-visualgate-windows`.
- Do not run generic loader-control, old double-confirm, old long-gate, speed
  stacking, HLE, or RSX promotion until field plus movement is valid from the
  Down160 route.
