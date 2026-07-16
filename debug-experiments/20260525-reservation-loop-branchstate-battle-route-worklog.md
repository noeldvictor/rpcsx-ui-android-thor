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

## 2026-05-26 Down160 Direct-Left Field/Movement Proof

Purpose:

- Verify whether the proven `Down:160` title Load selection can press the
  Path-to-Tenuto save slot, reach accepted field, and survive a direct-left
  movement pulse without opening the obsolete Save/Create-new-file menu.

Run evidence:

- Windows run
  `20260526-031038-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`
  used PadApi, screen 1, CPU affinity `0x0F`, frame/vblank `240`,
  `ReservationLoop Verify`, and `WindowsVisualGate CleanAfterField`.
- The live load-target gate passed before save-slot `Cross`:
  `screenshot-0081s-load-target-gate.png` classified as
  `PATH_TO_TENUTO_PRESENT`.
- Visual gate status was `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0136s-accepted-field-check.png` at `136s`, with `0` invalid
  screenshots after first field-like output and the required field deadline
  passed by `175s`.
- Manual screenshot review confirmed the correct Path to Tenuto field and no
  visible menu/prompt overlay at:
  - `screenshot-0136s-accepted-field-check.png`;
  - `screenshot-0138s-left200-check.png` after `ls_left:200`;
  - `screenshot-0210s.png` late in the route.
- Host checks were clean, stderr/stdout were empty, and no RPCS3/RPCSX process
  remained after the run.
- Fatal scan found no real crash/access/Vulkan/assertion/SIGBUS/SIGSEGV hit.
- GPU probe summary: `1553` records, `2,355.39 MB` observed DMA,
  offload fit `spu-kernel-hle=1139` / `too-small=414`, hot PCs `0x25cc`
  (`1,267.91 MB`) and `0x451c` (`1,087.48 MB`), dynamic MFC
  `249,853` hits / `574.28 MB` / `257.355 ms`.
- GPU Port Scoreboard stayed `0 B` promoted CPU/SPU-to-GPU, `0 B` direct
  RSX-local scout traffic, and `0 B` indirect SPU-DMA/RSX-resource overlap.

Change:

- `tools\ps3_harness_refiner.ps1` now recognizes the latest
  `titleload-down160-pollgated-directleft200` valid-field run as a
  `titleload-down160-field-route-proven` route base.
- Added a Down160 load-target-gated first-battle command suggestion:
  `cpu4-titleload-down160-firstbattle-battleroute-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  now block the stale generic `stateaware-one-step`, old loader-control,
  old double-confirm, and old long-gate suggestions after this proof.

Classification:

- `route-tooling`, `valid-field-triage`, `down160-field-movement-base`.
- Field plus direct-left movement proof only.
- Not menu/Options proof.
- Not first-battle proof.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Use the Down160 route base for first-battle proof:
  `cpu4-titleload-down160-firstbattle-battleroute-windows`.
- Title Options remains separately required before any speed, HLE/RSX, GPU
  migration, or 200% promotion claim.

## 2026-05-26 Down160 First-Battle Extension Crash

Purpose:

- Extend the proven Down160 load-target-gated field route toward first battle
  without using the stale loader-control or old title-selection macros.

Run evidence:

- Windows run
  `20260526-032955-cpu4-titleload-down160-firstbattle-battleroute-windows-windows`
  used PadApi, screen 1, CPU affinity `0x0F`, frame/vblank `240`,
  `ReservationLoop Verify`, and `WindowsVisualGate BattleRoute`.
- The live load-target gate passed before save-slot `Cross` after three
  attempts:
  `screenshot-0085s-load-target-gate-3.png` classified as
  `PATH_TO_TENUTO_PRESENT`.
- The route reached accepted Path to Tenuto field:
  `screenshot-0140s-accepted-field-check.png` at `140s`.
- After the battle movement branch (`ls_left:2600` plus
  `combo:ls_left+ls_down:2200`), manual screenshots showed corrupt field output
  with the RPCS3 likely-crashed overlay, not battle:
  - `screenshot-0192s-battle-candidate.png`;
  - `screenshot-0253s-first-battle-check.png`;
  - `screenshot-0314s-late-battle-check.png`.
- `rpcs3.stderr.txt` reported:
  `RPCS3: PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation reading location 0x40 (unmapped memory)`.
- Visual gate status was `FIELD_LIKE_PRESENT`, but `BattleRoute` failed because
  no battle-like screenshot was found at or after `200s`.
- Host checks stayed clean across `5` snapshots and no RPCS3/RPCSX process
  remained after the wrapper stopped the run at `MaxSeconds 335`.
- GPU probe summary: `1034` records, `1,148.44 MB` observed DMA, offload fit
  `spu-kernel-hle=575` / `too-small=459`, hot PCs `0x451c`
  (`587.50 MB`) and `0x25cc` (`560.94 MB`), dynamic MFC `126,592` hits /
  `273.60 MB` / `111.494 ms`.
- GPU Port Scoreboard stayed `0 B` promoted CPU/SPU-to-GPU, `0 B` direct
  RSX-local scout traffic, and `0 B` indirect SPU-DMA/RSX-resource overlap.

Change:

- `tools\ps3_harness_refiner.ps1` now recognizes a
  `titleload-down160-firstbattle` fatal as
  `titleload-down160-firstbattle-fatal`.
- When a clean Down160 direct-left proof exists, this fatal no longer suggests
  generic loader-control. It suggests re-proving the Down160 direct-left
  boundary before shrinking or state-gating the first-battle movement leg.
- Follow-up harness refinement: after that boundary is re-proven, the refiner
  now suggests `cpu4-titleload-down160-firstbattle-leftonly-diagnostic-windows`
  instead of the original full first-battle movement branch. This isolates
  `ls_left:2600` from the crashing down-left movement.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  now carry the same rule.

Classification:

- `failed-fatal-log`, `route-tooling`, `down160-firstbattle-extension-crash`.
- Field proof survived until the movement extension.
- Not first-battle proof.
- Not menu/Options proof.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Re-prove the last clean Down160 direct-left boundary or shrink/state-gate the
  battle movement leg from the accepted field screenshot before another
  first-battle attempt.
- Do not promote speed, HLE, RSX, or GPU migration from this crashed capture.

## 2026-05-26 Down160 Battle Movement Isolation Rung

Purpose:

- Prevent the post-reproof loop where the refiner would immediately repeat the
  same full first-battle movement branch that already crashed.

Change:

- Added `New-StateAwareTitleToLoadDownHoldBattleLeftOnlyDiagnosticCommand` to
  `tools\ps3_harness_refiner.ps1`.
- The diagnostic uses the proven Down160 load-target gate, reaches accepted
  field, sends only `ls_left:2600`, and captures left-only/late screenshots
  under `CleanAfterField`.
- Added refiner state for:
  - recent Down160 first-battle fatal;
  - clean Down160 direct-left reproof after that fatal;
  - Down160 left-only pass;
  - Down160 left-only fatal.
- If the direct-left boundary is re-proven while the recent full first-battle
  crash is still in the trajectory window, the suggested command is now
  `cpu4-titleload-down160-firstbattle-leftonly-diagnostic-windows`, not the full
  crashing branch.
- If left-only passes, the refiner emits no automatic full rerun and requires a
  smaller/state-gated down-left diagnostic next. If left-only crashes, it backs
  off to the Down160 direct-left boundary.
- `AGENTS.md` and `.agents\skills\ps3-continual-harness-refiner\SKILL.md`
  now carry the same route-isolation rule.

Validation:

- `ps3_harness_refiner.ps1` parses successfully.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` still points at the clean
  Down160 direct-left reproof while the latest trajectory item is the crashed
  full first-battle branch. After that boundary is re-proven, the new
  `titleload-down160-boundary-reproved-after-battle-fatal` guard should route
  to the left-only diagnostic instead of repeating the full crashing branch.

Classification:

- `process-harness`, `route-tooling`, `battle-movement-isolation`.
- Not field proof by itself.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner, then re-prove the Down160 direct-left boundary or run
  the left-only diagnostic if the boundary is already the newest clean run.

## 2026-05-26 Down160 Direct-Left Reproof Attempt

Run:

- Invalid launch-noise folder:
  `debug-captures\windows-lab\20260526-035544-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`.
  Background PowerShell quoting truncated the intended 20-token input macro to
  only `wait:65000`, so screenshots from this folder must not count as route,
  field, speed, or GPU evidence.
- Corrected run:
  `debug-captures\windows-lab\20260526-035749-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`.

Evidence:

- The corrected run launched with the full 20-token macro, `-WindowsGameScreen 1`,
  CPU affinity `0x0F`, frame/vblank `240/240`, and clean host pre/post/postrun
  snapshots.
- Load target gate polled from `screenshot-0081s-load-target-gate.png` through
  `screenshot-0110s-load-target-gate-13.png`.
- `eternal-sonata-load-target-summary.md` classified all `13` screenshots as
  `debug-save-prologue`: `PATH_TO_TENUTO_PRESENT=0`,
  `DEBUG_SAVE_PROLOGUE_PRESENT=13`, `UNKNOWN=0`.
- Manual image review of `screenshot-0081s-load-target-gate.png` confirmed the
  Load screen selected `Debug Save` / `Prologue` with damaged-save text.
- The live gate aborted before save-slot `Cross`; visual gate reported
  `NO_FIELD_LIKE_SCREENSHOT`; no field, Options, or first-battle proof exists.
- Fatal scan stayed clean. The GPU scoreboard stayed at `0` promoted CPU/SPU to
  GPU records, `0 B` direct RSX-local, and `0 B` indirect overlap. The run still
  logged `857.57 MB` observed DMA, but those counters are route-invalid.

Harness update:

- `tools\ps3_harness_refiner.ps1` now reads `Input macro tokens` from
  `windows-rpcs3-lab.txt` and classifies a Down160 direct-left label with too
  few tokens as `failed-harness-launch`.
- The refiner also emits a `truncated-input-macro` harness-noise anti-pattern so
  the invalid `035544` folder cannot become the next clean boundary.

Classification:

- `035544`: `failed-harness-launch`, harness noise.
- `035749`: `failed-load-target-gate`, route/tooling.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Do not repeat speed/HLE/RSX work from these counters.
- Repair or restore save-target selection so the polling gate reports only
  `PATH_TO_TENUTO_PRESENT`, then re-run the Down160 direct-left boundary proof.

## 2026-05-26 Down160 Wrong-Save-Target Refiner Tightening

Purpose:

- Stop the newest corrected Down160 failure from falling through to the stale
  generic `stateaware-loadtarget-pollgated-doubleconfirm-dismisssave` command.

Change:

- `tools\ps3_harness_refiner.ps1` now detects a Down160 title/load route whose
  load-target gate aborts on `DEBUG_SAVE_PROLOGUE_PRESENT` or
  `MIXED_LOAD_TARGETS` before save-slot `Cross`.
- The refiner emits `titleload-down160-wrong-save-target` and blocks automatic
  route reruns until the Path-to-Tenuto save target is restored or repaired and
  the live gate reports `PATH_TO_TENUTO_PRESENT`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same rule.

Validation:

- `tools\ps3_harness_refiner.ps1` parses successfully.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` reports
  `titleload-down160-wrong-save-target`, classifies the newest corrected
  Down160 run as `failed-load-target-gate`, keeps the truncated launch as
  `failed-harness-launch`, and emits a commented no-rerun suggested command
  instead of the stale generic state-aware command.
- The secondary cutscene anti-pattern now points back to the newest Down160
  wrong-save-target blocker instead of saying to return to old loader-control.

Classification:

- `process-harness`, `route-tooling`, `wrong-save-target-loop-break`.
- Not field proof.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner. If it reports the expected wrong-save-target blocker,
  restore or repair the local Path-to-Tenuto save target before another Down160
  direct-left boundary proof.

## 2026-05-26 Down160 Save Restore And Load-Complete Miss

Run:

- Backup before restore:
  `debug-captures\save-backups\BLUS3016100-before-down160-path-restore-20260526-043444`.
- Restored from:
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`.
- Boundary reproof attempt:
  `debug-captures\windows-lab\20260526-043503-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`.

Evidence:

- The restored Windows RPCS3 save hashes match the known checkpoint, and
  `PARAM.SFO` advertises `Ch. 1 Raindrops Path to Tenuto South Section`.
- The run launched with the full 20-token macro, screen 1, CPU affinity `0x0F`,
  frame/vblank `240/240`, and clean host pre/post samples.
- The live load-target gate passed immediately:
  `screenshot-0081s-load-target-gate.png` classified
  `PATH_TO_TENUTO_PRESENT`.
- The route did not reach field. Manual review of
  `screenshot-0136s-accepted-field-check.png` and `screenshot-0210s.png` shows
  the Load UI with `Load complete`, not Path-to-Tenuto moving gameplay.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `NO_FIELD_LIKE_SCREENSHOT`; all 13 screenshots are
  `wrong-window-or-other-small-png`.
- `rpcs3.stderr.txt` is empty and a fatal scan of `RPCS3.log` did not find a
  VM access violation, Vulkan fatal, verification failure, or STOP hit.
- The direct sprint command timed out during the wrapper tail after stopping
  RPCS3 at `230s`, so automatic GPU summary files were not produced in that
  run directory. A later full summarizer retry also timed out on the
  `94.67 MB` log.
- Minimal `rg` counter extraction found `1684` raw GPU-candidate probe records,
  `1,663.24 MB` observed DMA, `0 B` direct RSX bytes, and hot max-DMA PCs
  `0x451c` (`1150` records) and `0x25cc` (`534` records). These counters are
  route-invalid because there was no field/movement proof.

Harness update:

- `tools\ps3_harness_refiner.ps1` now detects this shape as
  `titleload-down160-load-complete-not-dismissed`.
- The suggested command is now
  `cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows`,
  which keeps the Down160 load-target gate and adds an explicit
  post-load-complete `Cross` before field and movement screenshots.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same route-repair rule.

Validation:

- `tools\ps3_harness_refiner.ps1` parses successfully.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` now reports
  `titleload-down160-load-complete-not-dismissed` and suggests
  `cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows`,
  not the stale generic state-aware command.

Classification:

- `failed-visual-gate`, `route-tooling`,
  `down160-load-complete-not-dismissed`.
- Not field proof.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner, then run only the Down160 post-load-complete dismiss
  direct-left repair before any first-battle, HLE, RSX, or speed work.

## 2026-05-26 Down160 Multi-Row Load-Target Classifier

Run:

- Post-load-complete repair attempt:
  `debug-captures\windows-lab\20260526-045343-cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows-windows`.

Evidence:

- The run launched with the full 23-token macro, screen 1, CPU affinity `0x0F`,
  frame/vblank `240/240`, and clean host pre/post samples.
- The live load-target gate aborted before save-slot `Cross`; visual gate stayed
  `NO_FIELD_LIKE_SCREENSHOT`, with all screenshots classed as
  `wrong-window-or-other-small-png`.
- Manual review of `screenshot-0085s-load-target-gate-3.png` showed the selected
  lower row was `Save File 04` / `Path to Tenuto`, while the old fixed crop was
  reading the top damaged-save text.
- `tools\classify_eternal_sonata_load_target.ps1` now scans visible candidate
  rows (`190, 365, 535`) with `x=650`, `height=145`, and records the winning
  crop row in the summary table.
- Reclassifying the latest `045343` folder now reports
  `PATH_TO_TENUTO_PRESENT`: path-to-tenuto=`12`, debug-save-prologue=`0`,
  unknown=`2`.
- Control checks still hold: old wrong-save folder `035749` reports
  `DEBUG_SAVE_PROLOGUE_PRESENT` (`0/13/0` path/debug/unknown), and old known-good
  Path folder `031038` reports `PATH_TO_TENUTO_PRESENT` (`1/0/12`).
- GPU summary for `045343` remains route-invalid: `765` records,
  `781.61 MB` observed DMA, `0` RSX-local traffic records,
  `0` indirect RSX resource overlap records, offload fit
  `spu-kernel-hle=397`, `too-small=368`.

Harness update:

- `tools\ps3_harness_refiner.ps1` now detects a Down160 post-load route with a
  gate-failed marker but corrected `PATH_TO_TENUTO_PRESENT` classifier status as
  `titleload-down160-load-target-classifier-row-drift`.
- The refiner blocks the generic load-target failure fallback for that state and
  suggests rerunning
  `cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows`
  under the corrected multi-row classifier.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same row-drift rule.

Validation:

- `tools\classify_eternal_sonata_load_target.ps1` parses successfully.
- `tools\ps3_harness_refiner.ps1` parses successfully.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` reports
  `titleload-down160-load-target-classifier-row-drift` and suggests the Down160
  post-load-complete dismiss command, not generic state-aware or old
  loader-control macros.

Classification:

- `route-tooling`, `classifier-row-drift`, `failed-load-target-gate`.
- Not field proof.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Rerun only the Down160 post-load-complete dismiss direct-left repair under the
  corrected multi-row classifier. Do not run speed/HLE/RSX promotion until field
  movement is valid again.

## 2026-05-26 Down160 Post-Load Cross Save-Prompt Miss

Run:

- `debug-captures\windows-lab\20260526-051647-cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows-windows`.

Evidence:

- The run launched with the full 23-token macro, screen 1, CPU affinity `0x0F`,
  frame/vblank `240/240`, reservation-loop `Verify`, and clean pre/post/postrun
  host snapshots.
- The corrected multi-row load-target gate passed on attempt 1:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`0`.
- The outer Codex shell timed out during postrun/tail handling after the lab
  stopped RPCS3 at the intended `250s` wall. No lingering RPCS3/RPCSX process
  remained.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like
  `screenshot-0136s-load-complete-check.png` at `136s`, with `0` invalid
  screenshots after first field-like.
- Manual review changes the result class: `screenshot-0136s-load-complete-check.png`
  is clean Path-to-Tenuto field, but `screenshot-0151s-left200-check.png` and
  `screenshot-0220s.png` show the in-field `Save game` / `Don't save game`
  prompt blocking movement. The extra post-field `Cross` opened the save prompt
  before the direct-left movement proof.
- `rpcs3.stderr.txt` is empty, and targeted fatal scan found no
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, or unhandled exception hits.
- The full GPU summarizer timed out on the `113 MB` log, so use targeted `rg`
  extraction for this route-invalid capture:
  - GPU-candidate records: `2005`.
  - Observed DMA: `3,072.92 MB`.
  - Direct RSX bytes: `0 B`.
  - Hot PCs: `0x25cc` `1025` records / `1,675.44 MB`, `0x451c` `980` records /
    `1,397.47 MB`.
  - Dynamic MFC: `2005` records, `324,760` hits, `753.36 MB`, `289.108 ms`.
  - MFC list transfer: `955` records, `118,657` calls, `106.292 ms`.
  - Reservation commands: `2135` records, `13,203,094` command hits,
    `9,598,252` GETLLAR, `3,604,842` PUTLLC.
  - MFC wait: `2136` records, `14,921,138` reads, all fast, `0` blocking.

Harness update:

- `tools\ps3_harness_refiner.ps1` now detects a valid-field Down160
  `postloadcomplete-dismiss-directleft200` route as
  `titleload-down160-postloadcomplete-cross-opens-save-prompt`.
- The refiner blocks generic valid-field fallback for this state and suggests
  the plain Down160 load-target-gated direct-left route without the extra
  post-field `Cross`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same rule.

Classification:

- `route-tooling`, `valid-field-triage-but-save-prompt`.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only the plain Down160 load-target-gated direct-left route:
  `cpu4-titleload-down160-pollgated-directleft200-visualgate-windows`. Do not
  repeat the post-load-complete `Cross`, and do not run speed/HLE/RSX promotion
  until field movement is valid again.

## 2026-05-26 Down160 Plain Direct-Left Loading Miss

Run:

- `debug-captures\windows-lab\20260526-060436-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`.

Evidence:

- The run used the full 20-token plain Down160 macro, screen 1, PadApi, CPU
  affinity `0x0F`, frame/vblank `240/240`, reservation-loop `Verify`, and
  clean pre/post/postrun host snapshots. No RPCS3/RPCSX process remained after
  the lab stop.
- The corrected multi-row load-target gate passed on attempt 3:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`2`.
- The outer Codex shell timed out while tailing after the lab had already
  stopped RPCS3 at `230s`; this did not leave a live duplicate run.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `NO_FIELD_LIKE_SCREENSHOT`. Class counts were `loading-like-small-png=12`
  and `wrong-window-or-other-small-png=3`.
- Manual screenshot review confirms the visual gate result:
  `screenshot-0141s-accepted-field-check.png`,
  `screenshot-0143s-left200-check.png`, and `screenshot-0210s.png` all show
  Eternal Sonata `Now Loading...` at about `120 FPS`, not Path-to-Tenuto field
  and not movement.
- `rpcs3.stderr.txt` is empty, and targeted fatal scan found no
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, or unhandled exception hits.
- Targeted `rg` counter extraction:
  - GPU-candidate records: `1827`.
  - Observed DMA: `2,332.89 MB`.
  - Direct RSX bytes: `0 B`.
  - Hot PCs: `0x25cc` `1255` records / `1,923.04 MB`, `0x451c` `572`
    records / `409.84 MB`.
  - Dynamic MFC: `1827` records, `119,673` hits, `672.18 MB`, `153.733 ms`.
  - MFC list transfer: `544` records, `33,052` calls, `27.233 ms`.
  - Reservation commands: `1894` records, `5,086,348` command hits,
    `3,789,574` GETLLAR, `1,296,774` PUTLLC.
  - MFC wait: `1894` records, `5,818,878` reads, all fast, `0` blocking.

Harness update:

- `tools\ps3_harness_refiner.ps1` now treats `failed-loading-visual` plus a
  Down160 `directleft200` label plus `PATH_TO_TENUTO_PRESENT` as
  `titleload-down160-path-target-loading-only`.
- The refiner now blocks the generic state-aware fallback and the
  save-prompt-opening repair loop for this state.
- The suggested next action is a Down160 no-movement load-stability diagnostic:
  `cpu4-titleload-down160-loadstability-nocross-nomove-visualgate-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same loading-only rule.

Classification:

- `failed-loading-visual`, `route-tooling`,
  `titleload-down160-path-target-loading-only`.
- Not field proof.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner, then run only the Down160 no-movement load-stability
  diagnostic before any first-battle, HLE, RSX, GPU, or speed-stacking work.

## 2026-05-26 Down160 No-Movement Load-Complete Diagnostic

Run:

- Invalid launch-noise folder:
  `debug-captures\windows-lab\20260526-062630-cpu4-titleload-down160-loadstability-nocross-nomove-visualgate-windows-windows`.
  The wrapper quoting truncated the intended 17-token macro to only
  `wait:65000`, so this folder is harness noise and must not count as route,
  field, speed, or GPU evidence.
- Corrected run:
  `debug-captures\windows-lab\20260526-062820-cpu4-titleload-down160-loadstability-nocross-nomove-visualgate-windows-windows`.

Evidence:

- The corrected run launched with the full 17-token no-movement macro, screen
  1, PadApi, CPU affinity `0x0F`, frame/vblank `240/240`, reservation-loop
  `Verify`, and clean pre/post/postrun host snapshots. No RPCS3/RPCSX process
  remained after the lab stop.
- The load-target gate passed on attempt 1:
  `screenshot-0081s-load-target-gate.png` reported
  `PATH_TO_TENUTO_PRESENT`.
- Manual screenshots show the route state clearly:
  `screenshot-0177s-post-confirm-90s.png`,
  `screenshot-0267s-post-confirm-180s.png`, and `screenshot-0280s.png` all
  show the Load UI with the `Load complete` banner, not Path-to-Tenuto field.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `NO_FIELD_LIKE_SCREENSHOT`; all `17` screenshots are classed
  `wrong-window-or-other-small-png`.
- `rpcs3.stderr.txt` is empty, and targeted fatal scan found no
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, or unhandled exception hits.
- Targeted `rg` counter extraction:
  - GPU-candidate records: `2107`.
  - Observed DMA: `2,168.88 MB`.
  - Direct RSX bytes: `0 B`.
  - Hot PCs: `0x25cc` `699` records / `1,094.37 MB`, `0x451c` `1408`
    records / `1,074.50 MB`.
  - Dynamic MFC: `2107` records, `230,670` hits, `525.36 MB`, `331.039 ms`.
  - MFC list transfer: `1328` records, `86,569` calls, `104.263 ms`.
  - Reservation commands: `2401` records, `12,823,696` command hits,
    `9,528,795` GETLLAR, `3,294,901` PUTLLC.
  - MFC wait: `2401` records, `14,091,248` reads, all fast, `0` blocking.

Harness update:

- `tools\ps3_harness_refiner.ps1` now treats any `titleload-down160` route
  label with too few input macro tokens as `failed-harness-launch`, so the
  malformed `062630` folder cannot become route evidence.
- `tools\ps3_harness_refiner.ps1` now treats a Down160 no-movement
  load-stability run with `PATH_TO_TENUTO_PRESENT` and no field as
  `titleload-down160-load-complete-waits-for-dismiss`.
- The refiner now blocks the generic state-aware fallback for this state.
- The suggested next action is a delayed single post-load-complete `Cross`
  with no movement:
  `cpu4-titleload-down160-lateloadcomplete-dismiss-nomove-visualgate-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same load-complete-waits-for-dismiss rule.

Classification:

- `failed-visual-gate`, `route-tooling`,
  `titleload-down160-load-complete-waits-for-dismiss`.
- Not field proof.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner, then run only the delayed single-dismiss no-movement
  proof before any direct-left movement, first-battle, HLE, RSX, GPU, or
  speed-stacking work.

## 2026-05-26 Down160 Late Load-Complete Dismiss Field Proof

Runs:

- Wrong-save-target attempt:
  `debug-captures\windows-lab\20260526-064710-cpu4-titleload-down160-lateloadcomplete-dismiss-nomove-visualgate-windows-windows`.
- Restored-save rerun:
  `debug-captures\windows-lab\20260526-065427-cpu4-titleload-down160-lateloadcomplete-dismiss-nomove-visualgate-windows-windows`.

Evidence:

- The first run aborted before slot `Cross` because the live gate selected
  `DEBUG_SAVE_PROLOGUE_PRESENT` (`0` Path, `11` Debug, `0` unknown). The local
  save target was backed up to
  `debug-captures\save-backups\BLUS3016100-before-lateloadcomplete-restore-20260526-065409`
  and restored from
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`.
- The rerun used the full 18-token late-dismiss no-movement macro, screen 1,
  PadApi, CPU affinity `0x0F`, frame/vblank `240/240`, and reservation-loop
  `Verify`.
- The load-target gate passed on attempt 4:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`3`.
- Manual screenshots show the repaired route state:
  `screenshot-0183s-load-complete-90s.png` is still the Load UI with the
  `Load complete` banner; after exactly one delayed `Cross`,
  `screenshot-0201s-post-load-complete-dismiss-18s.png` and
  `screenshot-0247s-post-dismiss-63s.png` show clean Path-to-Tenuto field with
  no save prompt.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `FIELD_LIKE_PRESENT`, first field-like at
  `screenshot-0201s-post-load-complete-dismiss-18s.png` (`201s`), and `0`
  invalid screenshots after first field-like.
- `rpcs3.stderr.txt` is empty, host checks are clean, and targeted fatal scan
  found no `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification
  failure, unknown STOP, or unhandled exception hits.
- Targeted `rg` counter extraction for the restored rerun:
  - GPU-candidate records: `2101`.
  - Observed DMA: `2,904.03 MB`.
  - Direct RSX bytes: `0 B`.
  - Hot PCs: `0x25cc` `979` records / `1,581.88 MB`, `0x451c` `1122`
    records / `1,322.14 MB`.
  - Dynamic MFC: `2101` records, `300,702` hits, `714.46 MB`, `281.302 ms`.
  - MFC list transfer: `1073` records, `110,199` calls, `93.506 ms`.
  - Reservation commands: `2272` records, `13,288,323` command hits,
    `9,710,230` GETLLAR, `3,578,093` PUTLLC.
  - MFC wait: `2272` records, `14,927,748` reads, all fast, `0` blocking.

Harness update:

- `tools\ps3_harness_refiner.ps1` now treats a Down160
  `lateloadcomplete-dismiss-nomove` run with `PATH_TO_TENUTO_PRESENT` and field
  triage as `titleload-down160-late-dismiss-field-clean`.
- The refiner now blocks the generic state-aware fallback for this state.
- The suggested next action is the same late-dismiss base plus one direct-left
  pulse:
  `cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same late-dismiss field-clean rule.

Classification:

- `valid-field-triage`, `route-tooling`,
  `titleload-down160-late-dismiss-field-clean`.
- Not moving gameplay.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner, then run only the late-dismiss direct-left movement
  boundary before any first-battle, HLE, RSX, GPU, or speed-stacking work.

## 2026-05-26 Down160 Late-Dismiss Direct-Left Movement Boundary

Run:

- `debug-captures\windows-lab\20260526-072403-cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows-windows`.

Evidence:

- The run used the full 21-token late-dismiss direct-left macro, screen 1,
  PadApi, CPU affinity `0x0F`, frame/vblank `240/240`, and reservation-loop
  `Verify`.
- The load-target gate passed on attempt 3:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`2`.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `FIELD_LIKE_PRESENT`, first field-like at
  `screenshot-0199s-post-load-complete-dismiss-18s.png` (`199s`), required
  field-like before `240s` passed, and `0` invalid screenshots after first
  field-like.
- Manual screenshots confirm the boundary:
  `screenshot-0199s-post-load-complete-dismiss-18s.png` is clean
  Path-to-Tenuto field, `screenshot-0202s-left200-check.png` is clean after the
  `ls_left:200` pulse, and `screenshot-0260s.png` remains clean field. No save
  prompt, crash overlay, or corrupt field visuals were visible.
- `rpcs3.stderr.txt` is empty, host checks are clean, no RPCS3/RPCSX process
  remained afterward, and targeted fatal scan found no `VM: Access violation`,
  `FATAL`, `SIG`, Vulkan fatal, verification failure, unknown STOP, or
  unhandled exception hits.
- Window-title samples are route telemetry only, not speed proof:
  `23.78 FPS` at field, `26.50 FPS` after left200, `28.48 FPS` at `260s`.
- GPU summary:
  - Records: `1840`.
  - Observed DMA: `2,424.44 MB`.
  - GPU Port Scoreboard: promoted CPU/SPU->GPU replacement `0 B`, direct
    RSX-local scout traffic `0 B`, indirect SPU-DMA/RSX overlap `0 B`.
  - Offload fit: `spu-kernel-hle=1200`, `too-small=640`.
  - Hot PCs: `0x25cc` `847` records / `1,361.25 MB`, `0x451c` `993` records /
    `1,063.18 MB`.
  - Dynamic MFC: `241,794` hits, `597.91 MB`, `399.638 ms`.
  - MFC list transfer: `87,880` calls, `137.570 ms`.
  - Reservation-loop peak command hits: `229,282`, with GETLLAR/PUTLLC
    `177,885` / `51,397`.
  - Lane 2 verifier row stayed clean: `11375/11375/11375/0/0`.

Harness update:

- `tools\ps3_harness_refiner.ps1` now treats a Down160
  `lateloadcomplete-dismiss-directleft200` run with `PATH_TO_TENUTO_PRESENT`
  and field triage as
  `titleload-down160-late-dismiss-directleft-field-clean`.
- The refiner now blocks the generic state-aware fallback for this state.
- The suggested next action is the same late-dismiss base plus left-only
  first-battle movement isolation:
  `cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same late-dismiss direct-left rule.

Classification:

- `valid-field-triage`, `route-tooling`,
  `titleload-down160-late-dismiss-directleft-field-clean`.
- Not a speed win.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.
- Menu/Options and first battle are still missing.

Next:

- Validate the refiner, then run only the late-dismiss left-only first-battle
  movement isolation before full battle, HLE, RSX, GPU, or speed-stacking work.

## 2026-05-26 Down160 Left-Only Load-List Cursor Blocker

Runs:

- Classifier/cursor drift:
  `debug-captures\windows-lab\20260526-074648-cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows`.
- Blind load-top-normalize repair:
  `debug-captures\windows-lab\20260526-075615-cpu4-titleload-down160-loadtopnormalize-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows`.

Evidence:

- The first run used the full 21-token late-dismiss left-only isolation macro,
  screen 1, PadApi, CPU affinity `0x0F`, frame/vblank `240/240`, and
  reservation-loop `Verify`.
- It aborted before slot `Cross` because the load-target gate reported
  `DEBUG_SAVE_PROLOGUE_PRESENT` across all polling screenshots.
- Manual review of `screenshot-0081s-load-target-gate.png` showed damaged rows
  above a visible lower `Save File 05` / `Path to Tenuto` row. The local
  checkpoint hashes already matched
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`, so this
  is load-list cursor/classifier drift, not a save-restore problem.
- The blind `loadtopnormalize` attempt added pre-gate `Up` taps, then captured
  only black-overlay load-target frames and timed out as `UNKNOWN_LOAD_TARGET`.
  Manual review of `screenshot-0084s-load-target-gate.png` confirms this was a
  black-frame/transition miss, not a load-list proof.
- Both runs had clean host checks, no lingering RPCS3/RPCSX process, empty
  stderr, and targeted fatal scans found no `VM: Access violation`, `FATAL`,
  `SIG`, Vulkan fatal, verification failure, unknown STOP, or unhandled
  exception hits.
- GPU summaries are invalid for speed or migration because neither run reached
  field:
  - Drift run: `809` records, `828.57 MB` observed DMA, `0 B` direct
    RSX-local, promoted CPU/SPU->GPU replacement `0 B`, offload fit
    `spu-kernel-hle=439` / `too-small=370`, hot PCs `0x25cc` `282` records /
    `438.46 MB` and `0x451c` `527` records / `390.10 MB`.
  - Blind-normalize run: `446` records, `473.71 MB` observed DMA, `0 B` direct
    RSX-local, promoted CPU/SPU->GPU replacement `0 B`, offload fit
    `spu-kernel-hle=302` / `too-small=144`, hot PCs `0x25cc` `303` records /
    `473.67 MB` and `0x451c` `143` records / `40.0 KB`.

Harness update:

- `tools\ps3_harness_refiner.ps1` now treats the first shape as
  `titleload-down160-leftonly-load-list-cursor-drift`.
- It treats the blind Up-normalize shape as
  `titleload-down160-loadtopnormalize-black-gate`.
- The generic state-aware fallback is blocked for both.
- The suggested next action is a load-list cursor diagnostic:
  `cpu4-titleload-down160-loadlist-cursor-diagnostic-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same rule.

Classification:

- `failed-load-target-gate`, `route-tooling`,
  `load-list-cursor-classifier-drift`.
- The blind-normalize run is `harness-noise`.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner. The next run must be the load-list cursor diagnostic
  before another left-only isolation, first-battle route, HLE, RSX, GPU, or
  speed-stacking attempt.

## 2026-05-26 Down160 Load-List Cursor Diagnostic Timing Miss

Run:

- `debug-captures\windows-lab\20260526-081622-cpu4-titleload-down160-loadlist-cursor-diagnostic-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadlist-cursor-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:14000;shot:load-list-initial;wait:4000;shot:load-list-stable;up:120;wait:900;shot:load-list-after-up1;up:120;wait:900;shot:load-list-after-up2;down:120;wait:900;shot:load-list-after-down1" -MaxSeconds 130 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0
```

Evidence:

- The title screenshots confirm the title route itself: `screenshot-0068s-title-settle.png`
  is the title menu, and `screenshot-0069s-title-after-down160.png` has `LOAD`
  selected after `Down:160`.
- Manual screenshot review shows every intended load-list cursor checkpoint was
  still the `Checking save files...` progress dialog, not the Load list:
  `screenshot-0084s-load-list-initial.png`,
  `screenshot-0089s-load-list-stable.png`,
  `screenshot-0090s-load-list-after-up1.png`,
  `screenshot-0092s-load-list-after-up2.png`, and
  `screenshot-0093s-load-list-after-down1.png`.
- `tools\classify_eternal_sonata_load_target.ps1` reported
  `UNKNOWN_LOAD_TARGET` for all seven screenshots, which is correct for this
  diagnostic because no Load-list row was visible.
- Host checks were clean, `rpcs3.stderr.txt` was empty, no RPCS3/RPCSX process
  remained after the lab stop, and targeted fatal scan found no
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, or unhandled exception hits.
- Window-title samples are save-check/menu telemetry only, not speed proof:
  `44.96`, `47.79`, `57.23`, `58.60`, and `43.53 FPS` across the supposed
  load-list shots.
- GPU summary is route-invalid for speed or migration: `844` records,
  `824.24 MB` observed DMA, direct RSX-local scout traffic `0 B`, indirect
  SPU-DMA/RSX overlap `0 B`, promoted CPU/SPU-to-GPU replacement `0 B`,
  offload fit `too-small=434` / `spu-kernel-hle=410`, dynamic MFC `93,026`
  hits, and reservation-loop peak command hits `138,916`.

Harness update:

- `tools\ps3_harness_refiner.ps1` now classifies this latest shape as
  `titleload-down160-loadlist-diagnostic-save-check-stall`.
- The cursor diagnostic macro now takes snapshots at 14s, 30s, and 45s after
  title `Cross`, then sends controlled `Up`/`Down` inputs only after the longer
  wait.
- The refiner now blocks the stale generic `stateaware-one-step` fallback for
  this state and suggests the extended cursor diagnostic again.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Classification:

- `route-tooling`, `titleload-down160-loadlist-diagnostic-save-check-stall`.
- Not cursor/classifier drift proof yet.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner. The next run must be the extended load-list cursor
  diagnostic before another left-only isolation, first-battle route, HLE, RSX,
  GPU, or speed-stacking attempt.

## 2026-05-26 Extended Down160 Cursor Diagnostic Black Transition

Run:

- `debug-captures\windows-lab\20260526-083255-cpu4-titleload-down160-loadlist-cursor-diagnostic-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadlist-cursor-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:14000;shot:save-check-14s;wait:16000;shot:load-list-probe-30s;wait:15000;shot:load-list-stable-45s;up:120;wait:900;shot:load-list-after-up1;up:120;wait:900;shot:load-list-after-up2;down:120;wait:900;shot:load-list-after-down1" -MaxSeconds 170 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0
```

Evidence:

- The wrapper command timed out in Codex after the lab had already stopped
  RPCS3 at the `170s` wall-time limit. The run folder is complete enough for
  classification: `windows-rpcs3-lab.txt` records `Exit code: exited`, host
  checks clean, and no RPCS3/RPCSX process remained afterward.
- `screenshot-0069s-title-after-down160.png` again proves title `Down:160`
  selects `LOAD`.
- Manual screenshot review shows all post-title checkpoints are black/perf
  overlay only: `screenshot-0084s-save-check-14s.png`,
  `screenshot-0101s-load-list-probe-30s.png`,
  `screenshot-0116s-load-list-stable-45s.png`,
  `screenshot-0118s-load-list-after-up1.png`,
  `screenshot-0119s-load-list-after-up2.png`, and
  `screenshot-0121s-load-list-after-down1.png`. No `Checking save files`
  dialog, Load list, or save row was visible.
- `tools\classify_eternal_sonata_load_target.ps1` reported
  `UNKNOWN_LOAD_TARGET` for all `8` screenshots.
- `rpcs3.stderr.txt` is empty and targeted fatal scan found no
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, unhandled exception, or likely-crashed hits.
- The full GPU summarizer timed out on the large log, so a targeted streaming
  extraction was used for route-invalid counters: `1,316` GPU-candidate records,
  `1,308.23 MB` observed DMA, `0 B` RSX bytes, top PCs `0x451c`
  `734,414,496 B` and `0x25cc` `637,368,992 B`, dynamic MFC `1,316` records /
  `147,486` hits / `315.41 MB`, MFC list transfer `910` records / `56,092`
  calls, reservation command `1,367` records / `8,717,441` hits with
  `6,558,419` GETLLAR and `2,159,022` PUTLLC commands.

Harness update:

- `tools\ps3_harness_refiner.ps1` now separates the prior
  `titleload-down160-loadlist-diagnostic-save-check-stall` from this new
  `titleload-down160-loadlist-diagnostic-black-transition`.
- The refiner now suggests a no-cursor Down160 load-target reproof:
  `cpu4-titleload-down160-loadtarget-reproof-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same black-transition rule.

Classification:

- `route-tooling`, `titleload-down160-loadlist-diagnostic-black-transition`.
- Not field proof.
- Not cursor/classifier proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner. The next run must be the no-cursor Down160 load-target
  reproof before another cursor diagnostic, left-only isolation, first-battle
  route, HLE, RSX, GPU, or speed-stacking attempt.

## 2026-05-26 Down160 No-Cursor Load-Target Reproof Passed

Run:

- `debug-captures\windows-lab\20260526-090340-cpu4-titleload-down160-loadtarget-reproof-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadtarget-reproof-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:12000;shot:post-title-cross-down160;gate_load_target:45000" -MaxSeconds 145 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0
```

Evidence:

- The Codex shell timed out while waiting for process output, but the lab had
  already stopped RPCS3 at the `145s` limit and `windows-rpcs3-lab.txt`
  records `Exit code: exited`.
- No RPCS3/RPCSX process remained after the run. Host checks were clean across
  prelaunch, postlaunch, samples, and postrun. `rpcs3.stderr.txt` is `0` bytes.
- Targeted fatal scan found no `VM: Access violation`, `FATAL`, `SIG`, Vulkan
  fatal, verification failure, unknown STOP, unhandled exception, or
  likely-crashed evidence.
- Manual screenshots:
  - `screenshot-0070s-title-after-down160.png` proves title `Down:160`
    selects `LOAD`.
  - `screenshot-0082s-post-title-cross-down160.png` is still
    `Checking save files...`.
  - `screenshot-0098s-load-target-gate-6.png` shows `Save File 01` /
    `Path to Tenuto` / `South Section` / `Ch. 1 Raindrops`.
- `tools\classify_eternal_sonata_load_target.ps1` reports
  `PATH_TO_TENUTO_PRESENT`: path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`8`; the live gate passed on attempt 6.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reports
  `NO_FIELD_LIKE_SCREENSHOT`, with `2` title/cutscene-sized frames and `7`
  small load/UI frames. There is no field, Options/menu, or battle proof.
- The full GPU summarizer timed out on the `52.47 MB` log, so targeted
  streaming extraction was used for route-invalid counters: `930`
  GPU-candidate records, `986.63 MB` observed DMA, `0 B` RSX bytes, offload fit
  `spu-kernel-hle=518` / `too-small=412`, hot PCs `0x25cc`
  `565,296,192 B` and `0x451c` `469,257,760 B`, dynamic MFC `930` records /
  `97,666` hits / `245.12 MB` / `96.784 ms`, MFC list transfer `557` records /
  `35,945` calls / `48.171 ms`, reservation command `1,023` records /
  `5,239,530` hits with `3,933,972` GETLLAR and `1,305,558` PUTLLC commands.
- `tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir`
  found no command CSV sidecars and classified that sub-summary as
  `collect-missing-proof`; the targeted log extraction above is the usable
  counter note for this route-only run.

Harness update:

- `tools\ps3_harness_refiner.ps1` no longer treats
  `cpu4-titleload-down160-loadtarget-reproof-windows` as truncated just because
  it has only `9` macro tokens. This diagnostic is intentionally short.
- The refiner now classifies this shape as
  `titleload-down160-loadtarget-reproof-passed` when the load-target summary is
  `PATH_TO_TENUTO_PRESENT`.
- The suggested next action is back to the late-dismiss left-only first-battle
  movement isolation:
  `cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Classification:

- `route-tooling`, `titleload-down160-loadtarget-reproof-passed`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Validate the refiner. The next run must be only the late-dismiss left-only
  first-battle movement isolation before full battle, HLE, RSX, GPU, or
  speed-stacking work.

## 2026-05-26 Down160 Late-Dismiss Field Reached, Window Lost Before Movement

Run:

- `debug-captures\windows-lab\20260526-132810-cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:2600;wait:45000;shot:left2600-check;wait:60000;shot:left2600-late-check" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10
```

Evidence:

- No RPCS3/RPCSX or harness process was active before the run, and the branch
  was clean.
- Host checks were clean prelaunch, postlaunch, and postrun. `rpcs3.stderr.txt`
  is `0` bytes. A targeted fatal scan found no `VM: Access violation`, `FATAL`,
  `SIG`, Vulkan fatal, verification failure, unknown STOP, unhandled exception,
  likely-crashed marker, or access-violation evidence.
- The load-target gate passed on the first attempt:
  `screenshot-0082s-load-target-gate.png` showed `Save File 01` /
  `Path to Tenuto` / `South Section` / `Ch. 1 Raindrops`, and
  `tools\classify_eternal_sonata_load_target.ps1` reported
  `PATH_TO_TENUTO_PRESENT`.
- `screenshot-0177s-load-complete-90s.png` still showed the load screen with
  the `Load complete.` prompt.
- `screenshot-0195s-post-load-complete-dismiss-18s.png` showed the correct
  Path-to-Tenuto field after dismissing the load-complete prompt. The window
  title sample at that checkpoint was `33.32 FPS`, Vulkan, `ETERNAL SONATA
  [BLUS30161]`.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reported
  `FIELD_LIKE_PRESENT`, with first field-like screenshot
  `screenshot-0195s-post-load-complete-dismiss-18s.png` at `195s` (`2.50 MB`)
  and `0` invalid screenshots after first field-like output.
- After the `ls_left:2600` input, both movement checkpoints were skipped:
  `left2600-check` at `243s` and `left2600-late-check` at `304s` because the
  game window was no longer found. The lab recorded `Process exited at 304s
  before max 330s` with exit code `exited`.
- The generated GPU summary reported `1,455` GPU-candidate records,
  `1,663.41 MB` observed DMA, `0 B` RSX-local traffic, offload fit
  `spu-kernel-hle=832` / `too-small=623`, hot PCs `0x451c` (`872.92 MB`) and
  `0x25cc` (`790.49 MB`), dynamic MFC `187,670` hits / `395.07 MB` /
  `155.380 ms`, MFC list transfer `71,242` calls / `68.290 ms`, and reservation
  command peak `156,597` hits (`120,500` GETLLAR / `36,097` PUTLLC).
- GPU scoreboard still reports promoted CPU/SPU-to-GPU replacement as `0 B`
  and `0.000%`.

Harness/refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` classified this capture as
  `failed-window-lost-after-field`: valid field route, no fatal markers, no
  movement proof after left input.
- The refiner's next action is to add or use black-overlay route control before
  movement or lane-2 HLE/GPU dry-runs. Suggested next run:
  `cpu4-loader-control-visualgate-windows`, a no-movement
  `CleanAfterField` loader/control proof.

Classification:

- `route-tooling`, `titleload-down160-lateloadcomplete-field-reached-window-lost`.
- Field route restored from the correct `Path to Tenuto` load target.
- Not post-left movement proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run the no-movement loader/control visual gate before adding movement, battle,
  lane-2 HLE, RSX, GPU, or speed-stacking work. The goal is to separate route
  stability/window lifetime from the left-movement input itself.

## 2026-05-26 Loader-Control Field Stable Through 190s

Run:

- `debug-captures\windows-lab\20260526-134726-cpu4-loader-control-visualgate-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

## 2026-05-28 Loader-Control Left200 Movement Proof

Question:

- After the clean no-movement loader/control, add exactly one tiny
  state-aware `left200` pulse and require `CleanAfterField`.

Artifact:

- `debug-captures\windows-lab\20260528-050402-cpu4-loader-control-left200-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  a single `ls_left:200` pulse, `-MaxSeconds 205`, screenshots every `10s`,
  and screenshots starting at `110s`.
- The lab wrapper again reported RPCS3 moved to `\\.\DISPLAY2` while launched
  with `--game-screen 1`; captured screenshots were valid RPCS3 gameplay.
- Visual gate passed `FIELD_LIKE_PRESENT`: first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), `14` field-like large PNGs,
  `0` invalid screenshots after first field-like, and required field-like at
  or before `160s` passed.
- Manual review of `screenshot-0117s.png`, post-movement
  `screenshot-0135s.png`, and late `screenshot-0200s.png` confirmed clean
  Path-to-Tenuto field visuals with the character moved left, no crash overlay,
  no corrupt field, no load/menu state, and no wrong-window capture.
- Window-title samples during capture ranged from `29.31` to `39.93 FPS`;
  this is diagnostic only because the run is route/movement triage, not a
  matched speed proof.
- In-run host samples were clean at `146s`, `150s`, and `180s`; aggregate host
  summary was moderate only because postrun Codex CPU was `17.6%`.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled during postrun log analysis after RPCS3 had exited and
  paths were written. The wrapper PowerShell was killed, then
  `tools\check_eternal_sonata_windows_visual_gate.ps1` and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were run manually against the
  finished artifact. No RPCS3/RPCSX process remained active.

Counters:

- Reservation-loop candidate probe records: `1597`.
- Reservation-loop dynamic probe records: `1597`.
- Reservation-loop wait probe records: `1733`.
- Reservation-loop wait-PC probe records: `90899`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `807`.
- Max reads observed: `200369`.
- No GPU probe/offload-credit counters were produced for this route proof.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-left200-field-clean`.
- Small movement route proof only.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects exactly one more tiny
  state-aware left pulse from this route: `loader-control-left200x2` with
  `CleanAfterField`. Lane-2 HLE/GPU dry-runs remain blocked.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## 2026-05-28 Loader-Control Reproof After Left1275 Fatal

Question:

- After the `left1275` fatal/corrupt-field retry, re-prove a no-movement
  loader/control with `CleanAfterField` before adding movement again.

Artifact:

- `debug-captures\windows-lab\20260528-044508-cpu4-loader-control-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  `-MaxSeconds 190`, screenshots every `10s`, starting at `120s`.
- The lab wrapper reported RPCS3 was moved to `\\.\DISPLAY2` while still
  launching with `--game-screen 1`; screenshots were valid RPCS3 gameplay
  captures, not wrong-window output.
- The visual gate passed `FIELD_LIKE_PRESENT`: first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), `10` field-like large PNGs,
  and `0` invalid screenshots after the first field-like output. The required
  field-like-at-or-before-`160s` check passed.
- Manual review of `screenshot-0117s.png` and `screenshot-0190s.png`
  confirmed clean Path-to-Tenuto field visuals with no crash overlay,
  corruption, load menu, black overlay, or wrong-window capture.
- Window title samples during capture ranged from `25.02` to `36.29 FPS`; this
  is diagnostic only because the run is a loader/control, not speed proof.
- In-run host samples were clean at `133s`, `150s`, and `180s`; the aggregate
  host summary was moderate because postrun Codex CPU was `18.8%`.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, or fatal-error hit. Only the
  normal `Show fatal error hints: false` config line matched the fatal string.
- The wrapper stalled during its postrun log-analysis phase after RPCS3 had
  exited and paths were written. The wrapper PowerShell was killed, then
  `tools\check_eternal_sonata_windows_visual_gate.ps1` and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were run manually against the
  finished artifact. No RPCS3/RPCSX process remained active.

Counters:

- Reservation-loop candidate probe records: `1477`.
- Reservation-loop dynamic probe records: `1477`.
- Reservation-loop wait probe records: `1606`.
- Reservation-loop wait-PC probe records: `83740`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `318`.
- Max reads observed: `160085`.
- No GPU probe/offload-credit counters were produced for this loader-control
  run.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-field-clean`.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects the newest valid
  loader-control as the route base, then one small state-aware `left200`
  movement step with `CleanAfterField`. Lane-2 HLE/GPU dry-runs remain blocked.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

Evidence:

- The Codex shell hit its outer timeout after the lab had already stopped
  RPCS3 at the `190s` wall-time limit. The run folder is complete enough for
  classification: `windows-rpcs3-lab.txt` records `Process exceeded 190s total
  wall time; stopping PID 9352`, host checks clean, `Exit code: exited`, and no
  RPCS3/RPCSX process remained afterward.
- `rpcs3.stderr.txt` is `0` bytes. A targeted fatal scan found no real
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, unhandled exception, likely-crashed marker, or access-violation
  evidence. The only `fatal` hit was the config line `Show fatal error hints:
  false`.
- Manual screenshots showed the Path-to-Tenuto field from the first captured
  frame through the final one:
  - `screenshot-0117s.png` shows clean field at `117s`.
  - `screenshot-0190s.png` shows the same clean field still alive at `190s`.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reported
  `FIELD_LIKE_PRESENT`, first field-like screenshot `screenshot-0117s.png` at
  `117s` (`2.50 MB`), `10` field-like screenshots, and `0` invalid screenshots
  after first field-like output.
- `window-title-samples.csv` stayed on `ETERNAL SONATA [BLUS30161]`, Vulkan,
  with field-route title FPS samples from `26.27` to `36.87` FPS. These are
  route-health samples only, not a matched speed claim.
- The full GPU summarizer timed out on the `83.88 MB` log, so a targeted
  streaming extraction was used for route-control counters: `1,452`
  GPU-candidate records, `2,204.69 MB` observed DMA, `0 B` RSX bytes, largest
  job `13.17 MB`, hot PCs `0x25cc=1,159.68 MB` and `0x451c=1,045.00 MB`,
  dynamic MFC `1,452` records / `240,330` hits / `534.01 MB` / `224.923 ms`,
  MFC list transfer `720` records / `89,079` calls / `88.424 ms`, and
  reservation command `1,606` records with peak `164,027` hits
  (`125,916` GETLLAR / `38,111` PUTLLC).
- Promoted CPU/SPU-to-GPU replacement remains `0 B` / `0.000%`.

Harness/refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` classified this newest capture as
  `valid-field-triage`.
- The refiner marked the previous black-overlay route-control blocker as
  resolved by this newest loader-control run, but kept lane-2 HLE/GPU dry-runs
  blocked because newer proof still lacks field/menu/battle coverage and
  repeated counters show zero RSX-local traffic.
- Suggested next command is a single small state-aware movement step from this
  route base:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

Classification:

- `route-tooling`, `valid-field-triage`.
- No-movement loader/control route held stable field visuals through the
  planned 190s stop.
- Not post-left movement proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only the suggested small `left200` movement-control proof before any
  larger left-only leg, first battle, HLE, RSX, GPU, or speed-stacking work.

## 2026-05-26 Loader-Control Left200 Movement Passed

Run:

- `debug-captures\windows-lab\20260526-140709-cpu4-loader-control-left200-visualgate-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

Evidence:

- Host pre/post/sample checks stayed clean, the harness kept RPCS3 on screen 1,
  CPU affinity `0x0F` was applied, and the lab stopped RPCS3 at the planned
  `205s` wall-time limit. No RPCS3/RPCSX process remained afterward.
- `rpcs3.stderr.txt` is `0` bytes. A targeted fatal scan found no real
  `VM: Access violation`, `FATAL`, `SIG`, Vulkan fatal, verification failure,
  unknown STOP, unhandled exception, likely-crashed marker, or access-violation
  evidence. The only `fatal` hit was the config line `Show fatal error hints:
  false`.
- Manual screenshots showed clean Path-to-Tenuto field visuals before and after
  the left movement pulse:
  - `screenshot-0133s.png` shows the clean field before movement, with the
    player still near the save point.
  - `screenshot-0135s.png` shows the player visibly left of the save point after
    `ls_left:200`.
  - `screenshot-0200s.png` shows the clean field still alive at the final
    captured frame.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reported
  `FIELD_LIKE_PRESENT`, first field-like screenshot `screenshot-0117s.png` at
  `117s`, `14` field-like screenshots, `0` invalid screenshots after first
  field-like output, and a passed `CleanAfterField` triage gate.
- GPU profiler summary recorded `1,602` candidate records, `2,594.33 MB`
  observed DMA, `1,602` dynamic MFC records, `806` MFC list transfer records,
  `1,739` reservation-loop command records, `6,091` reservation-loop verify
  records, and offload-fit mix `spu-kernel-hle=1218, too-small=384`.
- Dynamic MFC fallback was `299,027` hits / `615.96 MB` / `273.367 ms`, with
  PC mix `0x25cc=24,757` hits and `0x451c=274,270` hits. List transfer was
  `112,098` calls / `1.75 MB` descriptors / `87.011 ms`.
- Hot PC DMA stayed concentrated at `0x451c` (`1,342.83 MB`) and `0x25cc`
  (`1,251.49 MB`), matching the current CPU/SPU-kernel/HLE direction.
- Promoted CPU/SPU-to-GPU replacement remains `0 B` / `0.000%`. Direct
  RSX-local scout traffic remains `0 B`, and indirect SPU-DMA/RSX-resource
  overlap remains `0 B`.

Harness/refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` classified this newest capture as
  `valid-field-triage`.
- The refiner resolved the newest route base to
  `cpu4-loader-control-left200-visualgate-windows`, kept lane-2 HLE/GPU
  dry-runs blocked, and warned that wrong-window/small-image captures and
  zero-RSX-local repeats still prevent any GPU promotion claim.
- Suggested next command is exactly one more tiny state-aware left pulse from
  this proof base:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

Classification:

- `route-tooling`, `valid-field-triage`, `loader-control-left200-field-clean`.
- The stable loader/control route now has one verified small left-movement
  pulse with clean field visuals.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only the suggested `left200x2` movement-control proof, then require the
  same screenshot/log/counter classification before increasing route distance,
  attempting first battle, or reopening HLE/GPU/speed-stacking work.

## 2026-05-26 Loader-Control Left200x2 Movement Passed

Run:

- `debug-captures\windows-lab\20260526-142353-cpu4-loader-control-left200x2-visualgate-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

Evidence:

- Host checks were clean across `7` snapshots, RPCS3 stayed on screen 1 /
  `\\.\DISPLAY2`, CPU affinity `0x0F` was applied, and the harness stopped
  RPCS3 at the planned `215s` wall-time limit. No RPCS3/RPCSX process remained
  afterward.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are both `0` bytes. A targeted
  fatal scan found no real `VM: Access violation`, `FATAL`, `SIG`, Vulkan
  fatal, verification failure, unknown STOP, unhandled exception,
  likely-crashed marker, or access-violation evidence. The only `fatal` hit was
  the config line `Show fatal error hints: false`.
- Manual screenshot checks showed clean Path-to-Tenuto field visuals throughout:
  - `screenshot-0133s.png` shows the pre-movement field near the save point.
  - `screenshot-0136s.png` shows the first `ls_left:200` pulse moved the player
    left of the save point.
  - `screenshot-0138s.png` shows the second `ls_left:200` pulse still clean and
    farther from the save point.
  - `screenshot-0210s.png` shows the same clean field alive at the final
    captured frame.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reported
  `FIELD_LIKE_PRESENT`, first field-like screenshot `screenshot-0117s.png` at
  `117s` (`2.49 MB`), `16` field-like screenshots, `0` invalid screenshots
  after first field-like output, and a passed triage gate.
- Window-title samples stayed on `ETERNAL SONATA [BLUS30161]`, Vulkan, with
  route-health FPS samples from `27.27` to `42.38`. These are not a matched
  speed claim.
- GPU profiler summary recorded `1,594` candidate records, `2,621.03 MB`
  observed DMA, `1,594` dynamic MFC records, `768` MFC list-transfer records,
  `1,710` reservation-loop command records, `6,031` reservation-loop verify
  records, and offload-fit mix `spu-kernel-hle=1231, too-small=363`.
- Hot PC DMA remained concentrated at `0x451c` (`1,326.58 MB`) and `0x25cc`
  (`1,294.45 MB`). Dynamic MFC fallback was `301,245` hits / `627.93 MB` /
  `316.959 ms`, with PC mix `0x25cc=25,637` hits and `0x451c=275,608` hits.
  List transfer was `112,760` calls / `1.75 MB` descriptors / `159.799 ms`.
- Reservation-loop command peak rose to `233,244` hits, with `175,795` GETLLAR,
  `57,449` PUTLLC, and top exact PCs `0xa70`, `0xad4`, `0x340`, and `0x660`.
- Promoted CPU/SPU-to-GPU replacement remains `0 B` / `0.000%`. Direct
  RSX-local scout traffic remains `0 B`, and indirect SPU-DMA/RSX-resource
  overlap remains `0 B`.

Harness/refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` classified this newest capture as
  `valid-field-triage`.
- The refiner resolved the newest route base to
  `cpu4-loader-control-left200x2-visualgate-windows`, kept lane-2 HLE/GPU
  dry-runs blocked, and continued to treat repeated zero-RSX-local evidence as
  a direction away from broad SPU-to-Vulkan compute.
- Suggested next command is exactly one tiny diagonal micro-pulse from this
  proof base:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## 2026-05-28 Reservation-Loop TopSlot Left-Only Route Miss

Question:

- After the state-aware field reproof passed, isolate TopSlot post-field
  movement with a left-only diagnostic before another full `BattleRoute` retry.

Artifact:

- `debug-captures\windows-lab\20260528-072448-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`, host
  contention gate `ExternalFail`, `-WindowsVisualGate CleanAfterField`,
  `-WindowsVisualGateFieldSeconds 160`, and the TopSlot macro with
  `ls_left:2600`.
- Host checks were clean at prelaunch, postlaunch, `211s`, and `240s`.
  Postrun host check was moderate because Codex was sampled as a hot non-run
  process after RPCS3 stopped; host gate wrote
  `host-contention-gate-failed.txt`. This is not speed evidence either way.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: `10` screenshots were
  captured, with no field-like screenshot at or before `160s`, none at or
  after `220s`, and `0` field-like screenshots total.
- Manual review of `screenshot-0117s-accepted-field-check.png` showed a
  close-up/cutscene-like frame, not the Path-to-Tenuto field. Manual review of
  `screenshot-0165s-left2600-check.png` showed blue/starry non-field frames.
  Late screenshots stayed in the same small blue/starry class.
- Window-title samples were live RPCS3 output (`27.36` at `117s`, then
  `32.44` for later samples), but these are invalid for speed claims because
  the visual route was wrong.
- The harness stopped RPCS3 at the `240s` wall-time limit. The wrapper then
  stalled after postrun artifact paths were written. No RPCS3/RPCSX process
  remained active; only the wrapper PowerShell was killed, then visual gate,
  fatal scan, counters, and refiner were checked manually.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted fatal scan
  found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.

Counters:

- Reservation-loop candidate probe records: `2018`.
- Reservation-loop dynamic probe records: `2018`.
- Reservation-loop wait probe records: `2105`.
- Reservation-loop wait-PC probe records: `120402`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `535`.
- Max reads observed: `185854`.
- Counters are not promotion evidence because the visual gate failed.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `cutscene-or-nonfield-frames`.
- `reservation-loop-topslot-leftonly-route-miss`.
- Not valid field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now recommends backing off from
  the latest non-field/cutscene route and re-proving
  `cpu4-loader-control-left200x2-confirm-visualgate-windows`.

## 2026-05-28 Reservation-Loop State-Aware Field Reproof

Question:

- After the TopSlot battle proof lost the window after field, run the refiner's
  state-aware `CleanAfterField` field reproof and prevent another duplicate
  field-only loop if it passes.

Artifact:

- `debug-captures\windows-lab\20260528-070432-cpu4-stateaware-one-step-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, and `-WindowsVisualGateFieldSeconds
  160`. The wrapper defaulted to `MaxSeconds 120`, screenshots every `15s`,
  screenshots starting at `15s`, and `ScreenshotMaxCount 6`.
- Host checks were clean at prelaunch, postlaunch, and the `133s` sample. The
  postrun host check was moderate only because Codex was sampled as a hot
  non-run process after RPCS3 stopped.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- The visual gate passed `FIELD_LIKE_PRESENT`: `3` screenshots were captured,
  first field-like screenshot was `screenshot-0117s.png` at `117s` (`2.50
  MB`), and the `133s` screenshots remained field-like. Manual review confirmed
  correct Path-to-Tenuto field output at `117s` and `133s`.
- Window-title samples were `31.48`, `29.20`, `30.57`, and `27.99` FPS. These
  are route diagnostics only and not speed evidence.
- The harness stopped RPCS3 at the `120s` wall-time limit. The wrapper then
  stalled after postrun artifact paths were written. No RPCS3/RPCSX process
  remained active; only the wrapper PowerShell was killed, then visual gate,
  fatal scan, counters, and refiner were checked manually.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted fatal scan
  found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.

Counters:

- Reservation-loop candidate probe records: `1007`.
- Reservation-loop dynamic probe records: `1007`.
- Reservation-loop wait probe records: `1105`.
- Reservation-loop wait-PC probe records: `55359`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `242`.
- Max reads observed: `178440`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `reservation-loop-stateaware-field-clean-after-battle-window-loss`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/refiner change:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact post-battle
  state-aware field reproof as a resolved control after the TopSlot battle
  window-loss. It no longer recommends the same field command again.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now recommends isolating TopSlot
  post-field movement with a left-only diagnostic before another full
  `BattleRoute` retry.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-reservation-loop-topslot-leftonly-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsHostContentionGate ExternalFail -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field-check;ls_left:2600;wait:45000;shot:left2600-check;wait:45000;shot:left2600-late-check" -MaxSeconds 240 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Reservation-Loop First-Battle TopSlot Window-Lost Failure

Question:

- After field and title Options were proven for the reservation-loop lane, run
  the refiner-selected TopSlot first-battle proof with `BattleRoute`.

Artifact:

- `debug-captures\windows-lab\20260528-064514-cpu4-reservation-loop-battle-topslot-route-proof-windows`.

Evidence:

- Command used `-Action WindowsScene -Scene battle`, PadApi input,
  `-WindowsGameScreen 1`, `-WindowsBattleLoadRoute TopSlot`, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  host contention gate `ExternalFail`, `-MaxSeconds 330`, screenshots every
  `20s` starting at `120s`, and `-WindowsVisualGate BattleRoute`.
- Host checks were clean at prelaunch, postlaunch, and postrun. RPCS3 was
  moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- The only captured screenshot was `screenshot-0117s.png` at `117s`
  (`2.50 MB`). Manual review showed a correct Path-to-Tenuto field frame with
  RPCS3 title sample `FPS: 39.22` and overlay FPS around `45.00`.
- RPCS3 exited before the next screenshots: the wrapper reported missing game
  window at `169s`, `230s`, and `290s`, then `Process exited at 290s before
  max 330s`.
- Manual `BattleRoute` visual gate failed: field-like present at `117s`, but
  no field-like screenshot at or after `220s`, only `1` field-like screenshot
  instead of `2`, and no battle-like screenshot at or after `200s`.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted fatal
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled after postrun artifact paths were written. No
  RPCS3/RPCSX process remained active; only the wrapper PowerShell was killed,
  then visual gate, fatal scan, counters, and refiner were checked manually.

Counters:

- Reservation-loop candidate probe records: `888`.
- Reservation-loop dynamic probe records: `888`.
- Reservation-loop wait probe records: `968`.
- Reservation-loop wait-PC probe records: `48654`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `124853`.
- Counters are not promotion evidence because late field and first-battle
  visuals failed.

Classification:

- `failed-window-lost-after-field`.
- `route-tooling`.
- `reservation-loop-battle-topslot-window-lost-after-field`.
- Not valid first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to use the newest
  valid-field run as route base and add only one small state-aware movement
  step with `CleanAfterField`.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## 2026-05-28 Loader-Control Left200x2 Diagonal Micro-Pulse

Question:

- After confirming the two-left-pulse `left200x2` boundary, add exactly one
  tiny diagonal `ls_left+ls_down:200` pulse and require `CleanAfterField`.

Artifact:

- `debug-captures\windows-lab\20260528-060335-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  two `ls_left:200` pulses, one `combo:ls_left+ls_down:200` pulse,
  `-MaxSeconds 225`, screenshots every `10s`, and screenshots starting at
  `110s`.
- Host checks were clean for all `6` snapshots: prelaunch, postlaunch, `152s`,
  `180s`, `210s`, and postrun. Host contention summary and external contention
  summary were both `clean`.
- Visual gate passed `FIELD_LIKE_PRESENT`: first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), all `18` screenshots
  classified `field-like-large-png` through `220s`, `0` invalid screenshots
  after first field-like, and field-like at-or-before `160s` passed.
- Manual review of `screenshot-0117s.png`, `screenshot-0141s.png`, and
  `screenshot-0220s.png` confirmed Path-to-Tenuto field visuals before the
  diagonal pulse, immediately after it, and at the late checkpoint.
- Window-title/FPS samples during field output ranged roughly from the mid
  `20s` to low `40s`, so this is not speed proof and not a 200% candidate.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled during postrun log analysis after RPCS3 had exited and
  paths were written. The wrapper PowerShell was killed, then
  `tools\check_eternal_sonata_windows_visual_gate.ps1` and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were run manually against the
  finished artifact. No RPCS3/RPCSX process remained active.

Counters:

- Reservation-loop candidate probe records: `1766`.
- Reservation-loop dynamic probe records: `1766`.
- Reservation-loop wait probe records: `1893`.
- Reservation-loop wait-PC probe records: `100595`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `710`.
- Max reads observed: `183214`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-left200x2-diag200-field-clean`.
- Valid tiny diagonal movement boundary proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` says the latest
  `loader-control-left200x2-diag200` field proof is clean and must not be
  repeated. Bank it as route tooling only, then pivot to Options/menu proof,
  first-battle route repair, or focused SPU kernel HLE/codegen/verifier
  analysis. Lane-2 HLE/GPU fast modes remain blocked until field/menu/battle
  visuals are valid.

Next action:

```powershell
# No automatic duplicate: latest loader-control-left200x2-diag200 already passed field triage.
# Next sprint step should pivot to Options/menu proof, first-battle route repair, or focused SPU kernel HLE/codegen/verifier analysis.
```

## 2026-05-28 Reservation-Loop Options Fast-Select Proof

Question:

- After banking the diagonal field route, prove the missing title Options/menu
  visual checkpoint for the current reservation-loop lane without rerunning
  field movement.

Artifact:

- `debug-captures\windows-lab\20260528-062448-cpu4-reservation-loop-options-fastselect-proof-windows`.

Evidence:

- Command used `-Action WindowsScene -Scene menu`, PadApi input,
  `-WindowsGameScreen 1`, CPU affinity `0x0F`, frame/vblank `240/240`,
  `-EternalSonataReservationLoop Verify`, `-WindowsVisualGate Off`, and the
  no-initial-Cross fast-select macro:
  `wait:65000;shot:title-preinput;down:160;wait:600;shot:title-after-down1;down:160;wait:600;shot:title-after-down2-fast;cross:180;wait:6000;shot:options-candidate;wait:10000;shot:options-late`.
- Manual review confirmed the route: `screenshot-0070s-title-after-down2-fast.png`
  showed title menu selection on `OPTIONS`, `screenshot-0077s-options-candidate.png`
  showed the full title Options page, and `screenshot-0130s.png` showed the
  same full Options page still stable.
- The field-only visual classifier saw `NO_FIELD_LIKE_SCREENSHOT` and
  `wrong-window-or-other-small-png` because full Options pages compress below
  the field threshold. This is expected for title Options and not window loss.
- Host checks were clean in-run at prelaunch, postlaunch, `88s`, `91s`, and
  `120s`. Aggregate host summary was moderate only because postrun Codex CPU
  was `28.4%`.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled during postrun log analysis after RPCS3 had exited and
  paths were written. The wrapper PowerShell was killed, then screenshots,
  fatal logs, reservation-loop counters, and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were checked manually. No
  RPCS3/RPCSX process remained active.
- Harness fix: `tools\ps3_harness_refiner.ps1` now recognizes
  `reservation-loop-options-fastselect-proof` as `valid-options-triage` when
  the run is fatal-clean, has no black/loading screenshots, and has repeated
  small title Options screenshots. The refiner no longer sends this lane back
  to generic field movement after a clean Options proof.

Counters:

- Reservation-loop candidate probe records: `975`.
- Reservation-loop dynamic probe records: `975`.
- Reservation-loop wait probe records: `1063`.
- Reservation-loop wait-PC probe records: `51726`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `390`.
- Max reads observed: `127294`.

Classification:

- `valid-options-triage`.
- `reservation-loop-options-clean`.
- Menu/Options proof only.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects first-battle
  proof/repair under `ReservationLoop Verify`. It explicitly says not to rerun
  field or Options.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-reservation-loop-battle-topslot-route-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Classification:

- `route-tooling`, `valid-field-triage`, `loader-control-left200x2-field-clean`.
- The stable loader/control route now has two verified small left-movement
  pulses with clean field visuals.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Run only the suggested `left200x2-diag200` field movement proof, then require
  the same screenshot/log/counter classification before increasing route
  distance, attempting first battle, or reopening HLE/GPU/speed-stacking work.

## 2026-05-26 Loader-Control Left200x2 Diag200 Movement Passed

Run:

- `debug-captures\windows-lab\20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

Evidence:

- Host checks were clean across `6` snapshots, RPCS3 stayed on screen 1 /
  `\\.\DISPLAY2`, CPU affinity `0x0F` was applied, and the harness stopped
  RPCS3 at the planned `225s` wall-time limit. No RPCS3/RPCSX process remained
  afterward.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` are both `0` bytes. A targeted
  fatal scan found no real `VM: Access violation`, `FATAL`, `SIG`, Vulkan
  fatal, verification failure, unknown STOP, unhandled exception,
  likely-crashed marker, or access-violation evidence. The only `fatal` hit was
  the config line `Show fatal error hints: false`.
- Manual screenshot checks showed clean Path-to-Tenuto field visuals through
  the historical diagonal-risk point:
  - `screenshot-0133s.png` shows the pre-movement field near the save point.
  - `screenshot-0136s.png` shows the first `ls_left:200` pulse.
  - `screenshot-0139s.png` shows the second `ls_left:200` pulse still clean.
  - `screenshot-0142s.png` shows the `combo:ls_left+ls_down:200` diagonal
    micro-pulse stayed in the same field, with no black overlay, cutscene, or
    crash overlay.
  - `screenshot-0220s.png` shows the clean field still alive at the final
    captured frame.
- `tools\check_eternal_sonata_windows_visual_gate.ps1` reported
  `FIELD_LIKE_PRESENT`, first field-like screenshot `screenshot-0117s.png` at
  `117s` (`2.50 MB`), `18` field-like screenshots, `0` invalid screenshots
  after first field-like output, and a passed triage gate.
- Window-title samples stayed on `ETERNAL SONATA [BLUS30161]`, Vulkan, with
  route-health FPS samples from `24.47` to `35.02`. These are not a matched
  speed claim.
- GPU profiler summary recorded `1,580` candidate records, `2,444.86 MB`
  observed DMA, `1,580` dynamic MFC records, `896` MFC list-transfer records,
  `1,684` reservation-loop command records, `5,864` reservation-loop verify
  records, and offload-fit mix `spu-kernel-hle=1119, too-small=461`.
- Hot PC DMA remained concentrated at `0x451c` (`1,385.49 MB`) and `0x25cc`
  (`1,059.37 MB`). Dynamic MFC fallback was `307,547` hits / `572.01 MB` /
  `206.123 ms`, with PC mix `0x25cc=20,837` hits and `0x451c=286,710` hits.
  List transfer was `116,738` calls / `1.81 MB` descriptors / `84.558 ms`.
- Reservation-loop command peak was `98,830` hits, with `65,418` GETLLAR,
  `33,412` PUTLLC, and top exact PCs `0xa70`, `0xd24`, `0x11e4`, and `0xad4`.
- Promoted CPU/SPU-to-GPU replacement remains `0 B` / `0.000%`. Direct
  RSX-local scout traffic remains `0 B`, and indirect SPU-DMA/RSX-resource
  overlap remains `0 B`.

Harness/refiner fix:

- Initial post-run refiner output still suggested the same
  `cpu4-loader-control-left200x2-diag200-visualgate-windows` command again,
  which would have restarted the loop the user warned about.
- `tools\ps3_harness_refiner.ps1` now detects a latest valid
  `loader-control-left200x2-diag200` run and emits a no-duplicate next action.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` now carries the same
  rule: a clean `left200x2-diag200` proof is banked as route tooling only, and
  the next step must pivot to another proof axis.
- Parser validation passed, and the refreshed refiner now says:
  `Latest loader-control-left200x2-diag200 field proof is clean. Do not repeat
  the same diagonal command; bank the diagonal micro-pulse as route-tooling
  only, then pivot to Options/menu proof, first-battle route repair, or focused
  SPU kernel HLE/codegen/verifier analysis.`

Classification:

- `route-tooling`, `valid-field-triage`,
  `loader-control-left200x2-diag200-field-clean`.
- The stable loader/control route now has two verified left pulses plus one
  verified tiny diagonal micro-pulse with clean field visuals.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Do not rerun the same `left200x2-diag200` command. Choose a new proof axis:
  Options/menu proof, first-battle route repair from a clean route base, or a
  focused SPU kernel HLE/codegen/verifier analysis around `0x451c` / `0x25cc`.

## 2026-05-26 SPU HLE Candidate Atlas Refresh

Command:

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 16 -Top 25 -OutPath .\debug-experiments\20260526-spu-hle-candidate-atlas.md -CsvPath .\debug-experiments\20260526-spu-hle-candidates.csv
```

Evidence:

- Workspace/process check found no active RPCS3/RPCSX/RenderDoc/Ghidra run and
  `git status` was clean before this analysis pass.
- The atlas scanned `16` recent Windows-lab run dirs, used `6` valid
  fatal-clean field runs, and excluded
  `20260526-032955-cpu4-titleload-down160-firstbattle-battleroute-windows-windows`
  because it had a real `VM: Access violation reading location 0x40`.
- Valid run set included the latest clean route proofs:
  `20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`,
  `20260526-142353-cpu4-loader-control-left200x2-visualgate-windows-windows`,
  `20260526-140709-cpu4-loader-control-left200-visualgate-windows-windows`,
  `20260526-132810-cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows-windows`,
  `20260526-072403-cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows-windows`,
  and `20260526-031038-cpu4-titleload-down160-pollgated-directleft200-visualgate-windows-windows`.
- Top stable bucket is `0x25cc`, `CellSpursKernelGroup` /
  `CellSpursKernel0`, recommendation `spu-hle-codegen-priority`,
  `4340` records, `6` valid runs, `159` pattern signatures,
  `6.86 GB` sampled DMA, `1.01 GB` GET, `5.84 GB` PUT, max job
  `6.16 MB`, and `0 B` RSX-local.
- Second stable bucket is `0x451c`, `TCX_CellSpursKernelGroup` /
  `TCX_CellSpursKernel0`, recommendation `spu-hle-codegen-priority`,
  `2397` records, `6` valid runs, `5.49 GB` sampled DMA, and `0 B`
  RSX-local.
- No candidate bucket in the valid field set had RSX-local bytes, so this pass
  gives no new CPU/SPU-to-GPU migration credit.
- The report selected `0x25cc` as the next HLE verifier target and captured the
  latest disasm window at
  `debug-captures\windows-lab\20260526-144112-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\spu-images\BLUS30161-spu-image-958dfe208b686622-entry-00818-pc-025cc-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.disasm.txt`.

Classification:

- `analysis`, `spu-hle-codegen-triage`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.
- Broad SPU-to-Vulkan compute remains parked because the repeated field-clean
  traces still show `0 B` RSX-local bytes and no RSX-consumed batch shape.

Next:

- Do not repeat the `left200x2-diag200` route proof.
- Continue on a verify-only `0x25cc` SPU HLE/codegen/body verifier from the
  atlas target, or run Options/menu proof / first-battle route repair as a
  separate visual-proof axis.
- Keep `0x451c` list-family batching second behind `0x25cc`, and do not add a
  Vulkan compute path unless a later scout proves RSX-consumed data.

## 2026-05-26 0x25cc Pattern-Family Coverage Refresh

Commands:

```powershell
.\tools\summarize_eternal_sonata_25cc_pattern_family.ps1 -MaxRuns 16 -Top 30 -OutPath .\debug-experiments\20260526-25cc-pattern-family-refresh.md -CsvPath .\debug-experiments\20260526-25cc-pattern-family.csv
.\tools\summarize_eternal_sonata_25cc_coverage.ps1 -AtlasCsvPath .\debug-experiments\20260526-spu-hle-candidates.csv -OutPath .\debug-experiments\20260526-25cc-coverage-gap.md -CsvPath .\debug-experiments\20260526-25cc-coverage-gap.csv
```

Evidence:

- Pattern-family report used the same `6` valid fatal-clean field runs as the
  atlas and excluded the first-battle access-violation route.
- Selected `0x25cc` traffic is `6.86 GB` over `2` EA buckets, with `0 B`
  RSX-local bytes.
- The broad target is `0x9e4000`: `6.86 GB`, `4340` records, `159`
  patterns, `34,782.089 ms`, max job `6.16 MB`, and `0 B` RSX-local.
- The only other EA bucket, `0x4f0b80`, is tiny: `2.95 MB` over `6`
  records.
- Top repeated `0x9e4000` pattern clusters were all classified
  `broaden-25cc-verify-ea-family`; the largest four each appeared in all
  `6` valid runs and covered `510.38 MB`, `492.05 MB`, `482.88 MB`, and
  `459.96 MB`.
- Coverage-gap report compared the old exact `0xa1c000` guarded skip against
  the refreshed atlas. The exact skip is still correctness-clean
  (`0` mismatches, `0` destination changes, `0` skip misses), but it removed
  only `5.55 MB`: `0.97%` of that run's hot `0x25cc` bytes, `6.67%` of the
  exact verifier-shape bytes, and just `0.08%` of the refreshed `6.86 GB`
  atlas bucket.

Classification:

- `analysis`, `spu-hle-25cc-pattern-family`, `spu-hle-25cc-coverage-gap`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.
- This explains why the exact guarded skip was safe but not fast enough: it
  covered the wrong tiny slice of the larger `0x9e4000` family.

Next:

- Do not rerun the exact `0xa1c000` guarded skip expecting a speed gate.
- Add or plan a verify-only broad `0x9e4000` family/body verifier for
  `0x25cc`: gate by title/image/group/SPU/PC, record command descriptors,
  source/destination hashes, touched GET/PUT ranges, and whether the stock path
  changes destination data.
- Keep fast mode and Vulkan compute off until that verifier survives field,
  title Options, and first-battle visuals with no mismatches.

## 2026-05-26 0x25cc 0x9e4000 Verifier Plan

Command:

```powershell
.\tools\summarize_eternal_sonata_25cc_verifier_plan.ps1
```

Evidence:

- Generated
  `debug-experiments/20260526-25cc-9e4000-verifier-plan.md` from the committed
  pattern-family and coverage-gap CSVs.
- The broad target remains the `0x9e4000` family: `6.86 GB`, `4340` records,
  `159` pattern rows, `47` repeated pattern rows, `34,782.089 ms`, and `0 B`
  RSX-local bytes.
- The old exact `0xa1c000` skip remains correctness-clean but covers only
  `5.55 MB`, so it is not a credible large speed lane by itself.
- Source anchor inspection of local `rpcs3-upstream` found the useful runtime
  hooks already present: family classifier, `cmd.eal == 0x9e4000` predicate,
  shadow sample counters, runtime body-copy hook, MFC command entry, LLVM
  verifier candidate, and dynamic MFC fallback signal.

Classification:

- `analysis`, `spu-hle-25cc-9e4000-verifier-plan`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement/extend the verify-only runtime `0x9e4000` family lane first:
  title/image/group/SPU/PC gate, command descriptors, source and destination
  hashes, stock-path destination-change checks, touched GET/PUT ranges, reject
  counts, and pattern signatures.
- Treat LLVM direct-copy recognition as secondary until traces prove constant
  MFC commands on this hot path.
- Keep fast/body mode and Vulkan compute off until the verifier is clean across
  field, menu/Options, and first-battle visuals.

## 2026-05-26 0x25cc 0x9e4000 Shadow Field Verifier

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-9e4000-shadow-field-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField -MinFieldPngBytes 1000000
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir .\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows
.\tools\summarize_eternal_sonata_25cc_runtime_family.ps1 -RunDir .\debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows
```

Evidence:

- Run directory:
  `debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows`.
- The shell wrapper timed out after the emulator had stopped at the configured
  `225s` wall limit, so post-run visual and GPU/SPU summaries were completed
  manually from the capture folder.
- Visual gate passed for field triage: `18` field-like screenshots, first
  `screenshot-0117s.png` at `117s`, and `0` invalid screenshots after first
  field.
- Fatal scan was clean (`rpcs3.stderr.txt` empty, no access/STOP/crash/Vulkan
  fatal hit in `RPCS3.log`), no RPCS3/RPCSX process remained, and host
  contention was clean across `6` snapshots.
- Window-title samples were context only: `21` samples, average `32.94 FPS`,
  min `23.55`, max `39.28`. This was an instrumented, unmatched run, not a
  speed measurement.
- GPU probe: `3,133.21 MB` total observed DMA, `0` RSX-local traffic records,
  `0` indirect RSX-resource overlap records, offload fit
  `spu-kernel-hle=1323` / `too-small=460`.
- `0x25cc` family verifier: `808` rows, `26013` hits, `26013/0`
  success/fail, GET/PUT `12108/13905`, `406.45 MB`, `1,034.335 ms`.
- Exact command-level buckets were not broad enough: `ea9e4000=1734`
  (`6.666%`), `exact_a1c000=1734` (`6.666%`), `ea4f0b80=1`, and
  `other_matching_ea=22544` (`86.664%`).
- `0x25cc` shadow semantics were clean for observed GETs: `12108` hits,
  `189.19 MB`, output match/mismatch `12108/0`, destination
  changed/unchanged `810/11298`, with exact command buckets
  `ea9e4000=807`, `exact_a1c000=807`, `ea4f0b80=1`, `other=10493`.
- Runtime-family pattern report found `16` repeated max-DMA `0x9e4000`
  `hle-pattern-body-candidate` groups covering `636` records and `1.03 GB`;
  the top group was pattern `0xf4175241af5df103`, `96` records,
  `161.08 MB`.
- Hash semantics for max-DMA pattern groups still have `0 B` sampled payload and
  zero LS/block hashes, so this run exposes a `hash-instrumentation-gap` for
  the broad pattern-level body design.

Classification:

- `analysis`, `valid-field-triage`,
  `spu-hle-25cc-verify-shadow-field-clean`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.
- Broad SPU-to-Vulkan compute remains parked because RSX-local and indirect
  overlap are still `0 B`.

Next:

- Correct the verifier plan: broad `0x9e4000` means max-DMA pattern/descriptor
  family, not exact command-level `eal == 0x9e4000`.
- Add pattern/descriptor-level source/destination semantics for the top
  max-DMA `0x9e4000` groups, or add payload/LS-range hashes so the top repeated
  groups can be verified without conflating them with exact command EA buckets.
- Keep fast/body promotion off until this pattern-level verifier is clean in
  field, menu/Options, and first battle.

## 2026-05-26 Harness Refiner 0x25cc Shadow Loop Fix

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Evidence:

- Before the patch, the refiner saw the clean
  `20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows` field
  run but fell through to a generic `cpu4-stateaware-one-step` field command.
- `tools\ps3_harness_refiner.ps1` now detects a latest clean `0x25cc` /
  `9e4000` shadow verifier field proof and emits the
  `hle-25cc-shadow-pattern-gap` direction anti-pattern.
- Re-run after the patch changed the next action to:
  `Latest 0x25cc shadow verifier is field-clean, but it proved exact
  command-level EA is the wrong broad predicate. Do not rerun generic movement
  or exact-EA skips; add pattern/descriptor-level payload or LS-range hashing
  for the top max-DMA groups before fast/body promotion.`
- The local `ps3-continual-harness-refiner` skill now carries the same rule so
  future heartbeat rounds do not fall back to old route movement after this
  verifier result.

Classification:

- `process-harness`, `spu-hle-25cc-shadow-pattern-gap-refiner-fix`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement or extend the runtime verifier to emit payload or LS-range hashes
  for the top repeated max-DMA `0x9e4000` pattern groups.
- Keep broad SPU-to-Vulkan compute, exact-EA fast skips, and generic movement
  reruns parked until the pattern-level verifier is clean across field,
  menu/Options, and first battle.

## 2026-05-26 0x25cc Pattern Hash Target Atlas

Command:

```powershell
.\tools\summarize_eternal_sonata_25cc_hash_targets.ps1 -Top 16
```

Evidence:

- Added `tools\summarize_eternal_sonata_25cc_hash_targets.ps1`.
- Generated:
  `debug-experiments\20260526-25cc-pattern-hash-targets.md` and
  `debug-experiments\20260526-25cc-pattern-hash-targets.csv`.
- Inputs were the multi-run `debug-experiments\20260526-25cc-pattern-family.csv`
  atlas and latest clean shadow run
  `debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows`.
- Atlas `0x9e4000` HLE candidates: `159` groups / `6.86 GB`.
- Latest shadow-run runtime candidates: `16` groups / `1.03 GB`.
- Top-16 atlas groups seen in the latest shadow run: `4` groups, `1.56 GB`
  atlas bytes, `188.60 MB` latest-run bytes.
- Current shadow verifier is GET-only for this route: `12108` hits /
  `189.19 MB`, GET/PUT `12108/0`, output match/mismatch `12108/0`.
- The matched latest-run pattern rows are strongly PUT-heavy: the repeated
  top groups seen in the latest run are about `84%` PUT bytes. That means the
  current GET-only `try_es_spu_hle_25cc_body_copy()` cannot cover the main
  `0x9e4000` byte mass even if its GET side is clean.

Classification:

- `analysis`, `spu-hle-25cc-pattern-hash-targets`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Extend the runtime `0x25cc` shadow verifier to aggregate by pattern or
  descriptor plus direction, not just exact command-level EA buckets.
- Emit separate GET and PUT shadow hash summaries: direction, LSA, EAL,
  source hash, destination-before hash, destination-after hash,
  changed/unchanged, and output-match/mismatch.
- Keep fast/body mode off until PUT-side and GET-side pattern-level semantics
  are clean in field, menu/Options, and first battle.

## 2026-05-26 0x25cc Shadow Native Contract

Command:

```powershell
.\tools\summarize_eternal_sonata_25cc_shadow_contract.ps1 -Top 8
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Evidence:

- Added `tools\summarize_eternal_sonata_25cc_shadow_contract.ps1`.
- Generated:
  `debug-experiments\20260526-25cc-shadow-native-contract.md` and
  `debug-experiments\20260526-25cc-shadow-native-contract.csv`.
- Inputs were the latest clean shadow verifier field run
  `debug-captures\windows-lab\20260526-152956-cpu4-hle-25cc-9e4000-shadow-field-windows-windows`
  plus `debug-experiments\20260526-25cc-pattern-hash-targets.csv`.
- Current shadow verifier output remains GET-only: `12108` hits /
  `189.19 MB`, GET/PUT `12108/0`, output match/mismatch `12108/0`.
- Runtime-seen target patterns are PUT-heavy: `4` groups,
  `188.60 MB` latest-run bytes, GET `29.31 MB` (`15.5%`), PUT
  `159.29 MB` (`84.5%`).
- The same runtime-seen groups represent `1.56 GB` in the multi-run atlas.
- The report records exact source anchors in the sibling Windows source tree:
  runtime family predicate, shadow begin/finish, shadow recorder, body copy,
  GPU-probe pattern signature, LLVM verifier candidate, and dynamic-MFC
  fallback signal.
- The `ps3-continual-harness-refiner` skill now blocks another planning report
  after this contract and points the next round at a verify-only C++
  instrumentation patch.

Classification:

- `analysis`, `spu-hle-25cc-shadow-native-contract`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Patch the native `SPUThread.cpp` shadow verifier so it emits aggregate rows
  by pattern or descriptor plus GET/PUT direction.
- Treat a rerun with PUT still at `0` as a verifier failure, not as a speed or
  bodyfast candidate.
- Keep broad SPU-to-Vulkan compute, exact-EA fast/body promotion, and generic
  route movement reruns parked until direction-split shadow semantics are clean.

## 2026-05-26 0x25cc PUT Shadow Finish Hook And Descriptor Parser

Command:

```powershell
git -C ..\rpcs3-upstream diff --check -- rpcs3/Emu/Cell/SPUThread.cpp rpcs3/Emu/Cell/SPUThread.h rpcs3/Emu/Cell/lv2/sys_spu.cpp
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir $env:TEMP\es-gpu-probe-desc-test-* -Top 5
```

Evidence:

- No active RPCS3/RPCSX/build process was found before starting.
- The previous `0x25cc` shadow verifier was GET-only because normal PUT DMA
  returns before the final `finish_es_spu_hle_shadow_sample(...)` hook.
- Patched the sibling Windows source tree `..\rpcs3-upstream` so the shadow
  sample is finished before the accurate/GET early return, accurate DMA return,
  and normal PUT return paths in `SPUThread.cpp`.
- Added a fixed-size `spu_hle_25cc_shadow_descs` descriptor table in
  `SPUThread.h` keyed by direction, family, raw/base command, tag, size, LSA,
  and EAL. `sys_spu.cpp` now logs `Eternal Sonata SPU HLE 25cc shadow
  descriptor:` rows with GET/PUT direction, bytes, hashes, match/mismatch, and
  overflow.
- `git diff --check` on the three patched sibling source files reports only
  line-ending warnings, no whitespace errors.
- Updated `tools\summarize_eternal_sonata_gpu_probe.ps1` to parse and export
  `eternal-sonata-spu-hle-25cc-shadow-desc-profile.csv`, then summarize
  descriptor GET/PUT totals and top command shapes.
- A synthetic one-line descriptor log parsed successfully with GET `0`, PUT
  `3`, output mismatches `0`, and pattern signature `0x222`.
- The full old field capture parse timed out at 120 seconds, so no new old-run
  descriptor evidence was claimed.

Classification:

- `source-instrumentation`, `harness-parser`, `spu-hle-25cc-shadow-put-finish`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Build or run the patched Windows RPCS3 source with `Verify25ccShadow`.
- Parse the resulting run and require nonzero `direction=PUT` descriptor rows
  plus zero output mismatches before touching bodyfast, stack, GPU, menu, or
  battle promotion.
- If the descriptor CSV still has PUT `0`, classify it as a verifier failure
  and debug the finish-hook/path coverage instead of repeating planning reports.

## 2026-05-26 0x25cc Shadow Descriptor Buildcheck Route Miss

Command:

```powershell
cmake --build ..\rpcs3-upstream\build-msvc --config Release --target rpcs3 -- /m
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-field-buildcheck -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Run:

- `debug-captures\windows-lab\20260526-162731-cpu4-hle-25cc-shadow-desc-field-buildcheck-windows`

Evidence:

- The patched `rpcs3-upstream` Release build completed and wrote
  `build-msvc\bin\rpcs3.exe`. Link warning was the pre-existing
  `LNK4098` defaultlib warning; no compile failure.
- The run used the rebuilt executable, `Verify25ccShadow`, GPU probe profile,
  CPU affinity `0x0F`, 240/240 frame/vblank, and `-WindowsGameScreen 1`.
  RPCS3 moved to `\\.\DISPLAY2`.
- Host contention was clean for all `6` host snapshots.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`; all `18` screenshots were
  classified as `wrong-window-or-other-small-png`.
- Manual screenshot check of `screenshot-0160s.png` shows the Load menu with
  `Path to Tenuto` visible but `File does not exist`, not field gameplay.
- No RPCS3 process was left running after the harness stopped the run at
  `225s`.
- The patched shadow aggregate now sees PUTs:
  `20868` 25cc shadow hits / `326.06 MB`, GET `9918`, PUT `10950`,
  output match/mismatch `20868/0`, destination changed `3404`.
- The new descriptor CSV exists:
  `eternal-sonata-spu-hle-25cc-shadow-desc-profile.csv`.
  Direction groups show GET `9918` hits and PUT `754` descriptor hits,
  output mismatches `0`, unique pattern signatures `33`.
- Top PUT descriptor rows hit the expected `0x9e4000` family, for example
  direction `2`, family `1`, raw/base cmd `0x20/0x20`, tag `31`, size
  `16384`, LSA `0x3000`, EAL `0x9e4000`, hashes matching post output.
- Descriptor overflow reached `56`, so the current 16-slot descriptor table is
  too small for complete pattern accounting even though the PUT finish hook is
  proven to fire.

Classification:

- `source-instrumentation-validated`, `route-tooling`, `failed-visual-gate`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Do not rerun this old `down:20`/`up` macro. It is route-stale for the
  current save list and sticks on the Load menu.
- Either widen the 25cc descriptor table before the next accounting run, or
  accept that descriptor overflow prevents full descriptor coverage.
- Rerun `Verify25ccShadow` with the current Down160 late-dismiss direct-left
  field route, then require clean field visuals, nonzero PUT descriptor rows,
  zero mismatches, and no descriptor overflow before any bodyfast, stack, GPU,
  menu, or battle promotion.

## 2026-05-26 0x25cc Descriptor Capacity Widen Build

Command:

```powershell
git -C ..\rpcs3-upstream diff --check -- rpcs3/Emu/Cell/SPUThread.h rpcs3/Emu/Cell/SPUThread.cpp rpcs3/Emu/Cell/lv2/sys_spu.cpp
cmake --build ..\rpcs3-upstream\build-msvc --config Release --target rpcs3 -- /m
```

Evidence:

- No active RPCS3/RPCSX/gameplay run was present before this step. Leftover
  MSBuild node-reuse workers were stopped after the build completed.
- The previous descriptor buildcheck proved the PUT finish hook but reported
  descriptor overflow `56`, so the 16-slot descriptor table could not provide
  complete accounting.
- Patched the sibling Windows source tree `..\rpcs3-upstream` by widening
  `SPUThread.h` `spu_hle_25cc_shadow_descs` from `16` to `128` entries.
- `git diff --check` on the touched sibling SPU files reported only
  line-ending warnings, no whitespace errors.
- The patched Release `rpcs3.exe` rebuilt successfully. The only notable link
  warning was the pre-existing `LNK4098` defaultlib warning.
- No gameplay route, screenshot gate, or FPS comparison was run in this step.
- Patched `tools\ps3_harness_refiner.ps1` so this exact buildcheck route miss
  no longer falls through to generic `stateaware-one-step` or old
  loader-control movement. It now emits
  `hle-25cc-shadow-desc-buildcheck-route-miss` and suggests the widened-table
  Down160 late-dismiss direct-left `Verify25ccShadow` command.
- Re-ran `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8`; the generated next
  action now points at `cpu4-hle-25cc-shadow-desc-down160-latedismiss-directleft-field`
  with `-EternalSonataSpuHleVerify Verify25ccShadow`, not the stale route.

Classification:

- `source-instrumentation`, `harness-accounting-capacity`, `build-pass`,
  `process-harness-refiner-fix`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Rerun `Verify25ccShadow` with the current Down160 late-dismiss direct-left
  field route, not the stale `down:20`/`up` macro.
- Require clean field visuals, nonzero PUT descriptor rows, zero mismatches,
  and descriptor overflow `0` before any bodyfast, stack, GPU, menu, or battle
  promotion.

## 2026-05-26 0x25cc Descriptor Down160 Field Proof

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-down160-latedismiss-directleft-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:200;wait:1200;shot:left200-check;wait:10000;shot:late-check" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Run:

- `debug-captures\windows-lab\20260526-165517-cpu4-hle-25cc-shadow-desc-down160-latedismiss-directleft-field-windows`

Evidence:

- No active emulator/build process was present before the run.
- The run used the rebuilt widened-table `rpcs3.exe`, screen 1 /
  `\\.\DISPLAY2`, CPU affinity `0x0F`, 240/240 frame/vblank,
  `-EternalSonataGpuProbe Profile`, and `Verify25ccShadow`.
- Load-target gate passed as `PATH_TO_TENUTO_PRESENT`.
- Visuals were field-clean through `260s`. Manual checks:
  `screenshot-0195s-post-load-complete-dismiss-18s.png`,
  `screenshot-0197s-left200-check.png`, and `screenshot-0260s.png` show clean
  Path-to-Tenuto field with no save prompt, crash overlay, or corrupt field.
- Host checks were clean for all `6` snapshots. Focused fatal scan over
  `RPCS3.log` and `rpcs3.stderr.txt` found no fatal/access/assert/Vulkan/device
  lost hit.
- The wrapper full post-pass hung after the harness stopped RPCS3 at `260s`;
  it was stopped only after raw targeted counter extraction.
- Raw descriptor extraction from `RPCS3.log`:
  - verifier rows `836`
  - shadow hits `26748`, GET `12528`, PUT `14220`
  - shadow bytes `438.24 MB`
  - output match/mismatch `26748/0`
  - descriptor direction rows/hits: GET `12528/12528`, PUT `12540/14220`
  - descriptor PUT mismatches `0`
  - unique pattern signatures `74`
  - max descriptor overflow `0`
- Top PUT descriptor rows include the expected max-DMA family: direction `2`,
  raw/base command `0x20`, tag `31`, size `16384`, with zero mismatch/overflow.
- Field title-sample FPS averaged about `36.11 FPS` after field, but this is
  instrumentation context only, not a matched speed proof.

Classification:

- `valid-field-triage`, `source-instrumentation-validated`,
  `hle-25cc-shadow-desc-down160-field-clean`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the clean descriptor Down160
  field proof and emits `hle-25cc-shadow-desc-down160-field-clean`.
- It no longer falls through to the old generic `hle-25cc-shadow-pattern-gap`
  advice for this exact descriptor proof.
- Suggested command is now a title Options/menu `Verify25ccShadow` proof:
  `cpu4-hle-25cc-shadow-desc-options-proof`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  now carry the same standing rule.

Next:

- Do not rerun the 0x25cc descriptor field proof.
- Prove title Options/menu with `Verify25ccShadow`.
- Then prove first battle before bodyfast, stack, GPU, or speed promotion.

## 2026-05-26 0x25cc Descriptor Options Route Misses

Commands:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 90 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-nocross-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-preinput;down:220;wait:1000;shot:title-after-down1;down:220;wait:16000;shot:title-after-down2;cross:180;wait:8000;shot:options-candidate;wait:12000;shot:options-late" -MaxSeconds 155 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Artifacts:

- `debug-captures\windows-lab\20260526-171358-cpu4-hle-25cc-shadow-desc-options-proof-windows`
- `debug-captures\windows-lab\20260526-172754-cpu4-hle-25cc-shadow-desc-options-nocross-proof-windows`

Verification:

- Both runs were controlled Windows-only RPCS3 runs on screen 1 / `\\.\DISPLAY2`
  with CPU affinity `0x0F`, PadApi, GPU probe profile, and
  `Verify25ccShadow`.
- No active RPCS3/RPCSX process remained after the no-cross run.
- Fatal scan found no fatal/crash/access/Vulkan/assertion hits in either run.
- Host samples were clean: `7` snapshots for the initial Options run and `6`
  snapshots for the no-cross repair.
- Manual screenshots from the initial Options run show story/cutscene or
  intro-field frames, not the full title Options page. The route selected New
  Game/story instead of Options.
- Manual screenshots from the no-cross run show:
  - `screenshot-0068s-title-preinput.png`: title menu with `NEW GAME`, `LOAD`,
    and `OPTIONS`; selection at `NEW GAME`.
  - `screenshot-0070s-title-after-down1.png`: title menu with `LOAD` selected.
  - `screenshot-0086s-title-after-down2.png`: story/cutscene text, proving the
    long second wait drifted into the intro/title loop.
  - `screenshot-0095s-options-candidate.png` and
    `screenshot-0108s-options-late.png`: title-menu frames, still not full
    Options.

Counters:

- Initial Options route:
  - GPU probe records `1519`; SPU HLE verifier/shadow rows `1519`.
  - 0x25cc shadow hits `30948`, GET/PUT `14853/16095`, bytes `483.56 MB`,
    output match/mismatch `30948/0`.
  - Descriptor hits `30948`, GET/PUT `14853/16095`, bytes `483.56 MB`,
    output match/mismatch `30948/0`, unique pattern signatures `147`,
    descriptor overflow `0`.
  - Total observed DMA `2432.83 MB`; RSX-local `0`; GPU Port Scoreboard
    promoted CPU/SPU-to-GPU `0 B`, direct RSX-local `0 B`, indirect overlap
    `0 B`.
- No-cross route:
  - GPU probe records `1117`; SPU HLE verifier/shadow rows `1117`.
  - 0x25cc shadow hits `17658`, GET/PUT `8253/9405`, bytes `275.91 MB`,
    output match/mismatch `17658/0`.
  - Descriptor hits `17658`, GET/PUT `8253/9405`, bytes `275.91 MB`,
    output match/mismatch `17658/0`, unique pattern signatures `120`,
    descriptor overflow `0`.
  - 0x25cc family timing total `863.274 ms`, average `48.889 us`, max
    `16821 us`.
  - Total observed DMA `1831.69 MB`; RSX-local `0`; offload fit
    `spu-kernel-hle=803` / `too-small=314`; GPU Port Scoreboard promoted
    CPU/SPU-to-GPU `0 B`, direct RSX-local `0 B`, indirect overlap `0 B`.

Classification:

- `failed-cutscene-or-nonfield-visual`.
- `route-tooling`.
- Initial run: `hle-25cc-shadow-desc-options-initial-cross-cutscene-route-miss`.
- No-cross run: `hle-25cc-shadow-desc-options-nocross-wait-drift`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now distinguishes the no-initial-Cross wait
  drift from the initial-Cross route miss.
- The refiner no longer repeats the same no-cross macro after the latest
  no-cross miss; it suggests a fast Down160 Options-select proof with short
  waits and explicit title/selection screenshots.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  now carry the same standing rule.

Next:

- Do not rerun the descriptor field proof.
- Do not fall back to old loader-control field movement.
- Do not repeat the same no-initial-Cross Options macro.
- Run the fast Down160 title Options proof with `Verify25ccShadow`, then prove
  first battle before bodyfast, stack, GPU, or speed promotion.

## 2026-05-26 0x25cc Descriptor Fast-Select Options Proof

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-fastselect-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-preinput;down:160;wait:600;shot:title-after-down1;down:160;wait:600;shot:title-after-down2-fast;cross:180;wait:6000;shot:options-candidate;wait:10000;shot:options-late" -MaxSeconds 130 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 65 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Artifact:

- `debug-captures\windows-lab\20260526-174450-cpu4-hle-25cc-shadow-desc-options-fastselect-proof-windows`

Verification:

- Windows-only RPCS3 run on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity
  `0x0F`, frame/vblank `240/240`, GPU probe Profile, and
  `Verify25ccShadow`.
- Host checks were clean across `6` snapshots, and no active RPCS3/RPCSX
  process remained after the run.
- Fatal scan was clean; no access violation, VM access, Vulkan, validation,
  assertion, or likely-crashed evidence was present.
- Manual screenshots verified the exact title route:
  - `screenshot-0068s-title-preinput.png`: title menu, `NEW GAME` selected.
  - `screenshot-0069s-title-after-down1.png`: title menu, `LOAD` selected.
  - `screenshot-0070s-title-after-down2-fast.png`: title menu, `OPTIONS`
    selected.
  - `screenshot-0077s-options-candidate.png`: full title Options page.
  - `screenshot-0088s-options-late.png`: full title Options page still stable.

Counters:

- GPU probe records `974`; SPU HLE verifier/shadow rows `974`.
- 0x25cc family records `400`; shadow descriptor records `11988`.
- Target 0x25cc shadow verifier: hits `12768`, GET/PUT `5988/6780`, bytes
  `199.50 MB`, destination changed/unchanged `2814/9954`, output
  match/mismatch `12768/0`, unique source hashes `400`, unique
  destination-post hashes `400`.
- Target 0x25cc shadow descriptors: hits `12768`, GET/PUT `5988/6780`, bytes
  `199.50 MB`, destination changed `2814`, output match/mismatch `12768/0`,
  unique pattern signatures `36`, descriptor overflow `0`.
- Total observed DMA `1154.35 MB`; RSX-local traffic records `0`; offload fit
  `spu-kernel-hle=584` / `too-small=390`.
- GPU Port Scoreboard stayed `0 B` promoted CPU/SPU-to-GPU, `0 B` direct
  RSX-local, and `0 B` indirect overlap.
- Note: the generic shadow-verifier aggregate still includes older/non-target
  shapes such as `0x451c`; the target 0x25cc shadow and descriptor rows for
  this proof stayed zero-mismatch.

Classification:

- `valid-options-triage`.
- `hle-25cc-shadow-desc-options-clean`.
- Menu/Options proof only.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the 0x25cc descriptor
  fast-select Options shape as valid Options triage instead of wrong-window or
  cutscene fallout from the field-only visual classifier.
- Older cutscene/menu-route misses no longer outrank the newest valid Options
  proof.
- Suggested command now advances to a TopSlot first-battle
  `Verify25ccShadow` proof:
  `cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  now carry the same standing rule.

Next:

- Do not rerun the descriptor field proof.
- Do not rerun title Options.
- Prove first battle with `Verify25ccShadow`.
- Only after first battle can bodyfast, stack, GPU, or speed promotion be
  reconsidered.

## 2026-05-26 0x25cc Descriptor First-Battle Fatal

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Artifact:

- `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`

Verification:

- Windows-only RPCS3 run on screen 1, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and `Verify25ccShadow`.
- The wrapper timed out after the run itself reached `MaxSeconds 330`; no
  active RPCS3/RPCSX/build process remained afterward.
- Manual screenshot checks:
  - `screenshot-0117s.png`: clean Path-to-Tenuto field, no crash overlay.
  - `screenshot-0169s.png`: first-battle/tutorial-like view with Polka
    `900/900`, but heavy corrupt/noisy side borders.
  - `screenshot-0230s.png` and `screenshot-0320s.png`: same frozen
    battle/tutorial-like frame with the same corrupt side borders.
- Fatal scan is positive:
  - `rpcs3.stderr.txt`: `PPU[0x100000c] Thread () [0x002aedd0]: VM: Access
    violation reading location 0x40 (unmapped memory)`.
  - `RPCS3.log` reports the same fatal at `0:02:00.612266`.
- Visual gate alone reported `FIELD_LIKE_PRESENT` with late battle-like
  screenshots, but the fatal log and frozen/corrupt late frames override that.

Counters:

- GPU probe records `849`; SPU HLE verifier/shadow records `849`.
- 0x25cc family records `380`; 0x25cc shadow records `380`; descriptor records
  `11388`.
- Target 0x25cc shadow verifier: GET/PUT `5688/6300`, bytes `187.31 MB`,
  destination changed/unchanged `3325/8663`, output match/mismatch `11988/0`.
- Target 0x25cc descriptors: descriptor hits `11988`, GET/PUT `5688/6300`,
  bytes `187.31 MB`, destination changed `3325`, output match/mismatch
  `11988/0`, unique pattern signatures `57`, descriptor overflow `0`.
- Total observed DMA `1,167.43 MB`; RSX-local traffic `0`; indirect
  SPU-DMA/RSX-resource overlap `0`; offload fit `spu-kernel-hle=550` /
  `too-small=299`.
- GPU Port Scoreboard stayed `0 B` promoted CPU/SPU-to-GPU replacement,
  `0 B` direct RSX-local, and `0 B` indirect overlap.

Classification:

- `failed-fatal-log`.
- `hle-25cc-shadow-desc-battle-fatal`.
- Descriptor verifier coverage only.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this 0x25cc descriptor
  first-battle fatal explicitly instead of falling through to the old generic
  loader-control fatal recovery.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  carry the same standing rule.

Next:

- Do not rerun the same TopSlot `Verify25ccShadow` battle command.
- Do not fall back to old loader-control.
- Isolate the same TopSlot battle route with `Verify25ccShadow` off, or
  repair/state-gate the battle macro before another verifier proof.

## 2026-05-26 0x25cc Descriptor Battle Stock-Control Loading Miss

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Artifact:

- `debug-captures\windows-lab\20260526-182155-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`

Verification:

- Windows-only RPCS3 run on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity
  `0x0F`, frame/vblank `240/240`, GPU probe Profile, and
  `Verify25ccShadow` off.
- No RPCS3/RPCSX/build process remained after the run.
- Host checks were clean across `6` snapshots.
- Fatal scan was clean: `rpcs3.stderr.txt` was `0` bytes, and `RPCS3.log`
  had no access violation, fatal, assertion, STOP, likely-crashed, validation,
  or device-lost hit.
- Manual screenshots:
  - `screenshot-0117s.png`: `Now Loading...`, not field.
  - `screenshot-0169s.png`: `Now Loading...`, not battle.
  - `screenshot-0320s.png`: still `Now Loading...`.
- Visual gate status `NO_FIELD_LIKE_SCREENSHOT`; all `15` screenshots were
  `loading-like-small-png`; required field, late field, and battle-like checks
  all failed.
- Window-title samples around `119.81` to `120.18 FPS` are loading-screen
  telemetry only and must not be used as speed proof.

Counters:

- GPU probe records `2944`.
- Total observed DMA `4,319.29 MB`.
- Hot PCs: `0x25cc` with `2691` records / `4,112.23 MB`, and `0x451c` with
  `253` records / `207.06 MB`.
- Offload fit `spu-kernel-hle=2783` / `too-small=161`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`.
- GPU Port Scoreboard stayed `0 B` promoted CPU/SPU-to-GPU replacement,
  `0 B` direct RSX-local, and `0 B` indirect overlap.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-loading`.
- Not field.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Reading:

- The no-verifier stock-control did not reproduce the previous verifier fatal,
  but it also did not reach field or battle. Therefore it does not prove the
  verifier alone caused the fatal. The default TopSlot battle macro is not a
  valid stock control in this state.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this stock-control loading
  miss and suggests a Down160 late-load-complete stock left-only diagnostic
  instead of falling back to generic `stateaware-one-step` or old
  loader-control.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next:

- Do not rerun the same TopSlot `Verify25ccShadow` battle command.
- Do not rerun the same no-verifier TopSlot stock-control command.
- Do not use loading-screen `120 FPS` title samples as speed evidence.
- Repair from the current Down160 late-load-complete base with stock left-only
  movement before any verifier retry:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-leftonly-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:2600;wait:45000;shot:left2600-check;wait:60000;shot:left2600-late-check" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Classifier Repair And Left2600 Exit

Question:

- The previous no-verifier TopSlot stock control stayed on `Now Loading...`.
  The refiner suggested repairing from the current Down160 late-load-complete
  base with stock left-only movement. The first Down160 stock run aborted at the
  load-target gate; manual screenshot review showed this was a classifier
  false-negative, not a bad save target.

Classifier repair:

- Patched `tools\classify_eternal_sonata_load_target.ps1` so a lower
  `Path to Tenuto` row can win over damaged rows above it when the good-vs-bad
  image margin is strong.
- The same classifier still rejects the known `Debug Save / Prologue` control.
- Reclassifying the aborted run
  `20260526-183700-cpu4-hle-25cc-shadow-desc-battle-stock-down160-leftonly-diagnostic-windows`
  now reports `PATH_TO_TENUTO_PRESENT`; the old live gate marker remains an
  artifact of the pre-fix classifier.

Rerun artifact:

- `debug-captures\windows-lab\20260526-184336-cpu4-hle-25cc-shadow-desc-battle-stock-down160-leftonly-diagnostic-rerun-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Host checks were clean across `3` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- Load-target gate passed on attempt 1:
  `screenshot-0081s-load-target-gate.png` classified
  `PATH_TO_TENUTO_PRESENT`.
- `screenshot-0176s-load-complete-90s.png` showed the Load UI with
  `Load complete`.
- `screenshot-0195s-post-load-complete-dismiss-18s.png` showed clean
  Path-to-Tenuto field. Visual gate status `FIELD_LIKE_PRESENT`; first
  field-like at `195s`; required field before `240s` passed.
- After `ls_left:2600`, screenshots at `243s` and `303s` skipped because the
  game window was not found and the process had exited.
- Fatal scan/stderr were clean: `rpcs3.stderr.txt` was `0` bytes and `RPCS3.log`
  had no access violation, fatal, assertion, STOP, likely-crashed, validation,
  or device-lost hit. The log tail contained many guest
  `unknown draw command` sys_tty lines, but not a fatal emulator signature.

Counters:

- GPU probe records `1642`.
- Total observed DMA `1,817.32 MB`.
- Hot PCs: `0x451c` with `1258` records / `1,217.61 MB`; `0x25cc` with
  `384` records / `599.71 MB`.
- Offload fit `spu-kernel-hle=852` / `too-small=790`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-leftonly-process-exit`.
- Not moving gameplay: there is no post-`ls_left:2600` field screenshot.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact stock Down160
  left-only process-exit state instead of falling through to generic
  `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command shrinks the same repaired stock base to
  `ls_left:1200` and captures an immediate post-movement screenshot:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-left1200-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Left1200 Load-Complete Stuck

Question:

- The previous stock Down160 left-only diagnostic reached field, then RPCS3
  exited after `ls_left:2600`. The refiner shrank movement to `ls_left:1200`
  with an immediate post-movement screenshot to test whether a smaller stock
  movement rung survives.

Artifact:

- `debug-captures\windows-lab\20260526-190058-cpu4-hle-25cc-shadow-desc-battle-stock-down160-left1200-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Host checks were clean across `5` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes and fatal scan found no access violation,
  fatal, assertion, STOP, likely-crashed, validation, or device-lost hit.
- Load-target gate passed on attempt 1:
  `screenshot-0081s-load-target-gate.png` classified
  `PATH_TO_TENUTO_PRESENT`.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`; first field-like screenshot
  was none and the required field before `240s` failed.
- Manual screenshot review showed the route never dismissed the Load UI:
  `screenshot-0195s-post-load-complete-dismiss-18s.png`,
  `screenshot-0209s-left1200-check.png`, and
  `screenshot-0254s-left1200-late-check.png` all remained on `Save File 03` /
  `Path to Tenuto` with the `Load complete` popup.
- Process stayed alive until the harness stopped it at the `270s` max wall time,
  so this is not the previous post-movement process-exit signature.

Counters:

- GPU probe records `2288`.
- Total observed DMA `2,262.88 MB`.
- Hot PCs: `0x451c` with `1839` records / `1,575.26 MB`; `0x25cc` with `449`
  records / `687.62 MB`.
- Offload fit `too-small=1193` / `spu-kernel-hle=1095`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-left1200-load-complete-stuck`.
- Not moving gameplay: `ls_left:1200` was sent while still on the Load UI.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact stock Down160
  left1200 load-complete-stuck state instead of falling back to generic
  `loader-control`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the repaired Down160 base, sends a stronger
  no-movement post-load-complete dismiss, and captures field/stuck evidence
  before any verifier or movement retry:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-nomove-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;wait:45000;shot:strong-dismiss-late-check" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Strong-Dismiss Field Boundary

Question:

- The previous `ls_left:1200` shrink did not dismiss `Load complete`, so the
  left input was not movement. This run tested a stronger no-movement
  post-load-complete dismiss before retrying any movement.

Artifact:

- `debug-captures\windows-lab\20260526-191724-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-nomove-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Host checks were clean across `5` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes and fatal scan found no access violation,
  fatal, assertion, STOP, likely-crashed, validation, or device-lost hit.
- Load-target gate passed on attempt 1:
  `screenshot-0081s-load-target-gate.png` classified
  `PATH_TO_TENUTO_PRESENT`.
- `screenshot-0176s-load-complete-90s.png` showed the Load UI with
  `Load complete`.
- The stronger `cross:300` dismiss reached clean Path-to-Tenuto field at
  `screenshot-0195s-post-load-complete-strong-dismiss-18s.png`; the visual gate
  reported `FIELD_LIKE_PRESENT`, first field-like at `195s`, and required field
  before `240s` passed.
- Late screenshots stayed field-like through
  `screenshot-0240s-strong-dismiss-late-check.png` and `screenshot-0270s.png`.

Counters:

- GPU probe records `2330`.
- Total observed DMA `3,228.48 MB`.
- Hot PCs: `0x451c` with `1474` records / `1,855.55 MB`; `0x25cc` with `856`
  records / `1,372.93 MB`.
- Offload fit `spu-kernel-hle=1545` / `too-small=785`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-field-clean`.
- Not moving gameplay: this run intentionally had no movement input after field.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this field-clean
  strong-dismiss route boundary instead of falling through to generic
  `hle-25cc-shadow-pattern-gap` advice.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the strong-dismiss Down160 base and adds only
  `ls_left:1200` before any verifier or first-battle retry:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Strong-Dismiss Left1200 Black Gate

Question:

- The previous strong-dismiss no-movement diagnostic reached clean
  Path-to-Tenuto field. This run added only `ls_left:1200` on that same base to
  test whether the smaller stock movement rung could be observed before any
  verifier or first-battle retry.

Artifact:

- `debug-captures\windows-lab\20260526-193211-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Host checks were clean across `3` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes and fatal scan found no access violation,
  fatal, assertion, STOP, likely-crashed, validation, or device-lost hit.
- The live load-target gate aborted before save-slot `Cross`: `13` polling
  screenshots from `screenshot-0081s-load-target-gate.png` through
  `screenshot-0111s-load-target-gate-13.png` all classified
  `black-overlay-small-png` / `UNKNOWN_LOAD_TARGET`.
- Because the slot `Cross` never fired, the run never reached field, never
  dismissed `Load complete`, and never sent `ls_left:1200`. Visual gate status
  was `NO_FIELD_LIKE_SCREENSHOT`.

Counters:

- GPU probe records `891`.
- Total observed DMA `898.94 MB`.
- Hot PCs: `0x451c` with `677` records / `569.37 MB`; `0x25cc` with `214`
  records / `329.57 MB`.
- Offload fit `spu-kernel-hle=448` / `too-small=443`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-black-gate`.
- Not field: all gate frames were black-overlay `UNKNOWN_LOAD_TARGET`.
- Not moving gameplay: slot `Cross` and `ls_left:1200` never executed.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact stock Down160
  strong-dismiss left1200 black-gate state before the generic load-target
  fallback.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the proven strong-dismiss base and only lengthens
  the pre-slot load-target gate:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Strong-Dismiss Left1200 Long-Gate Field Clean

Question:

- The previous strong-dismiss `ls_left:1200` attempt aborted before save-slot
  `Cross` on black-overlay `UNKNOWN_LOAD_TARGET` gate frames. This rerun kept
  the same strong-dismiss movement shape and only lengthened the load-target
  gate to `60000ms`.

Artifact:

- `debug-captures\windows-lab\20260526-194411-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-longgate-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Load-target gate passed on attempt 1 at
  `screenshot-0082s-load-target-gate.png` with `PATH_TO_TENUTO_PRESENT`
  (`path-to-tenuto=1`, `debug-save-prologue=0`, `unknown=0`).
- `screenshot-0177s-load-complete-90s.png` showed the Load UI with
  `Load complete`.
- The `cross:300` strong dismiss reached clean Path-to-Tenuto field at
  `screenshot-0196s-post-load-complete-strong-dismiss-18s.png`; visual gate
  status `FIELD_LIKE_PRESENT`, first field-like at `196s`, required field by
  `260s` passed, and invalid screenshots after first field-like were `0`.
- Manual screenshot checks confirm the character moved after `ls_left:1200`:
  `screenshot-0210s-left1200-check.png` shows the post-left field position,
  while `screenshot-0255s-left1200-late-check.png` and `screenshot-0290s.png`
  stayed clean Path-to-Tenuto field with no save prompt, black overlay,
  corrupt field, or crash overlay.
- Host checks were clean across `6` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes. Targeted log scan found no actionable
  access violation, assertion, validation, device-lost, or likely-crashed
  signature; the only hits were benign `ppu_loader` exception-export names and
  normal PPU thread-exit `aborted` warnings from the load path.

Counters:

- GPU probe records `2576`.
- Total observed DMA `3,802.85 MB`.
- Hot PCs: `0x451c` with `1501` records / `2,066.70 MB`; `0x25cc` with `1075`
  records / `1,736.15 MB`.
- Offload fit `spu-kernel-hle=1777` / `too-small=799`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.
- Window-title field samples ranged from `29.09 FPS` at field entry to
  `33.31 FPS` at the late screenshot, but this is route telemetry only, not a
  matched speed proof.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-field-clean`.
- Field movement boundary: `ls_left:1200` was sent after accepted field and the
  field remained clean.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the strong-dismiss
  `left1200` field-clean long-gate result instead of falling through to generic
  `hle-25cc-shadow-pattern-gap` advice.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the strong-dismiss long-gate base and tries the
  `ls_left:1800` midpoint before any verifier, battle, HLE, RSX, GPU, or speed
  promotion:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1800-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1800;wait:12000;shot:left1800-check;wait:45000;shot:left1800-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 Strong-Dismiss Left1800 Long-Gate Load Complete Stuck

Question:

- The prior strong-dismiss long-gate `ls_left:1200` diagnostic reached clean
  Path-to-Tenuto field, visibly accepted the movement pulse, and stayed
  field-clean. This run tried the next midpoint, `ls_left:1800`, on the same
  stock Down160 strong-dismiss long-gate base before any verifier, battle, HLE,
  RSX, GPU, or speed promotion.

Artifact:

- `debug-captures\windows-lab\20260526-200029-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1800-longgate-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- Load-target gate passed on attempt 1 at
  `screenshot-0081s-load-target-gate.png` with `PATH_TO_TENUTO_PRESENT`
  (`path-to-tenuto=1`, `debug-save-prologue=0`, `unknown=0`).
- The run did not reach Path-to-Tenuto field. Manual screenshot review showed
  the Load UI with the `Load complete` popup at
  `screenshot-0195s-post-load-complete-strong-dismiss-18s.png`,
  `screenshot-0209s-left1800-check.png`,
  `screenshot-0255s-left1800-late-check.png`, and `screenshot-0290s.png`.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`; all `12` screenshots were
  classified `wrong-window-or-other-small-png`.
- Host checks were clean across `6` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes. Targeted log scan found no actionable access
  violation, assertion, validation, device-lost, or likely-crashed signature;
  the matches were benign command/VFS/export/audio/bootstrap text.

Counters:

- GPU probe records `2600`.
- Total observed DMA `2,872.45 MB`.
- Hot PCs: `0x451c` with `1831` records / `1,681.79 MB`; `0x25cc` with `769`
  records / `1,190.66 MB`.
- Offload fit `spu-kernel-hle=1471` / `too-small=1129`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1800-load-complete-stuck`.
- Not movement: the `ls_left:1800` input happened while still on the Load UI.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this `left1800`
  load-complete-stuck state instead of falling through to the previous clean
  `left1200` recommendation.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the strong-dismiss long-gate base but uses one
  stronger post-load-complete `Cross` hold before re-testing the same
  `ls_left:1800` midpoint:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1800-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1800;wait:12000;shot:left1800-check;wait:45000;shot:left1800-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 0x25cc Stock Down160 StrongDismiss600 Left1800 Debug-Save Target Blocker

Question:

- The prior `ls_left:1800` long-gate diagnostic proved the Path-to-Tenuto save
  target but never dismissed the `Load complete` popup. This retry kept the
  same route shape and increased the post-load-complete hold to `cross:600` to
  see whether the stronger dismiss allowed the `ls_left:1800` midpoint to reach
  field before any verifier, battle, HLE, RSX, GPU, or speed promotion.

Artifact:

- `debug-captures\windows-lab\20260526-201603-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1800-longgate-diagnostic-windows`

Verification:

- Windows-only RPCS3 on screen 1 / `\\.\DISPLAY2`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, GPU probe Profile, and no
  `Verify25ccShadow`/body fast path.
- The live load-target gate aborted before save-slot `Cross`; the stronger
  post-load-complete hold and `ls_left:1800` input were never sent.
- Load-target classifier status was `DEBUG_SAVE_PROLOGUE_PRESENT`, with
  `path-to-tenuto=0`, `debug-save-prologue=19`, and `unknown=0`.
- Manual screenshots `screenshot-0081s-load-target-gate.png` and
  `screenshot-0139s-load-target-gate-19.png` showed `Debug Save` / `Prologue`
  with damaged-save rows. No lower Path-to-Tenuto row was visible, so this is
  a real save-target miss, not row-classifier drift.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`; all `19` screenshots were
  classified `wrong-window-or-other-small-png`.
- Host checks were clean across `3` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes. Targeted log scan found no actionable
  access violation, assertion, validation, device-lost, or likely-crashed
  signature; the matches were benign command/VFS/export/audio/bootstrap text.

Counters:

- GPU probe records `1144`.
- Total observed DMA `1,211.72 MB`.
- Hot PCs: `0x451c` with `831` records / `730.67 MB`; `0x25cc` with `313`
  records / `481.04 MB`.
- Offload fit `spu-kernel-hle=639` / `too-small=505`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1800-debug-save-target`.
- Not field.
- Not movement: the macro aborted before save-slot `Cross`.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this stronger-dismiss
  `left1800` run as a save-target blocker instead of suggesting another route
  attempt.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next action is intentionally not a runnable route command:

```powershell
# No automatic route rerun: latest strongdismiss600 left1800 gate selected DEBUG_SAVE_PROLOGUE_PRESENT. Restore or repair the Path-to-Tenuto save target, verify PATH_TO_TENUTO_PRESENT with the load-target gate, then retry the strongdismiss600 left1800 shape.
```

## 2026-05-26 StrongDismiss600 Save Restore, Target Reproof, And Left1800 Process Exit

Question:

- The previous strongdismiss600 `ls_left:1800` attempt was blocked before slot
  `Cross` because the Load list selected `Debug Save` / `Prologue`. This round
  restored the known Path-to-Tenuto checkpoint, re-proved only the load target,
  then retried the exact strongdismiss600 `ls_left:1800` route.

Restore:

- Backup before restore:
  `debug-captures\save-backups\BLUS3016100-before-strongdismiss600-target-restore-20260526-203059`.
- Restored from:
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`.
- Restored to:
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\dev_hdd0\home\00000001\savedata\BLUS3016100`.

Target reproof artifact:

- `debug-captures\windows-lab\20260526-203125-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-windows`.

Target reproof evidence:

- The macro stopped before save-slot `Cross`:
  `wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof`.
- Load-target gate passed on attempt 1:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`0`.
- Manual screenshots `screenshot-0081s-load-target-gate.png` and
  `screenshot-0082s-path-target-reproof.png` showed `Save File 01` and
  `Save File 02` as `Path to Tenuto / South Section / Ch. 1 Raindrops`.
- Host checks were clean; `rpcs3.stderr.txt` was empty; fatal scan found no
  actionable access violation, assertion, validation, device-lost, likely
  crashed, or unhandled exception hits.
- GPU probe records `1233`; total observed DMA `1,344.55 MB`; hot PCs
  remained `0x451c` and `0x25cc`; promoted CPU/SPU-to-GPU, RSX-local, and
  indirect overlap all stayed `0 B`.

Retry artifact:

- `debug-captures\windows-lab\20260526-203509-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1800-longgate-diagnostic-rerun-windows`.

Retry evidence:

- Load-target gate passed on attempt 1:
  `PATH_TO_TENUTO_PRESENT`, path-to-tenuto=`1`, debug-save-prologue=`0`,
  unknown=`0`.
- Manual screenshots:
  - `screenshot-0081s-load-target-gate.png`: correct Path-to-Tenuto row.
  - `screenshot-0176s-load-complete-90s.png`: Load UI with `Load complete`.
  - `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`: clean
    Path-to-Tenuto field after the stronger `cross:600` dismiss.
- The run then sent `ls_left:1800`, but the game window/process exited before
  `left1800-check` and `left1800-late-check`; both screenshots were skipped.
- Visual gate status was `FIELD_LIKE_PRESENT`, first field-like
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` at `195s`,
  with `0` invalid screenshots after field-like.
- Host checks were clean across `3` snapshots; no RPCS3/RPCSX/build process was
  left running afterward.
- `rpcs3.stderr.txt` was `0` bytes. Targeted log scan found no actionable
  fatal/access/assertion/validation/device-lost/likely-crashed signature; the
  only searched hits were benign PPU thread-exit `aborted` warnings during load.

Counters:

- GPU probe records `1630`.
- Total observed DMA `1,973.14 MB`.
- Hot PCs: `0x451c` with `1022` records / `1,024.36 MB`; `0x25cc` with `608`
  records / `948.78 MB`.
- Offload fit `spu-kernel-hle=1017` / `too-small=613`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- Target reproof: `route-tooling` / `target-repaired`, not field, not movement,
  not speed, not `gpu-migration-credit`, not a 200% candidate.
- Retry: `failed-window-lost-after-field`.
- Retry subsystem class:
  `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1800-process-exit`.
- Not movement proof: the only field screenshot was before the `ls_left:1800`
  pulse, and the left-check screenshots were skipped after process exit.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the restored strongdismiss600
  `left1800` process-exit state instead of falling back to generic
  `stateaware-one-step` routing.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command keeps the restored strongdismiss600 base, shrinks the
  movement midpoint to `ls_left:1500`, and captures an immediate post-movement
  screenshot:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1500;wait:1200;shot:left1500-immediate-check;wait:10800;shot:left1500-check;wait:45000;shot:left1500-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 StrongDismiss600 Left1500 RSX FP CAL Corrupt Field

Question:

- After the target-only reproof passed, this reran the same strongdismiss600
  `ls_left:1500` movement proof with an immediate screenshot to see whether the
  previous pre-gate fatal was transient or whether the movement rung itself was
  unsafe.

Artifact:

- `debug-captures\windows-lab\20260526-212009-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-longgate-diagnostic-windows`.

Evidence:

- The live load-target gate passed after attempt `1` with
  `PATH_TO_TENUTO_PRESENT`.
- `screenshot-0176s-load-complete-90s.png` showed the load-complete checkpoint.
- Manual review: `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`
  was a clean Path-to-Tenuto field screenshot before movement.
- Manual review: `screenshot-0198s-left1500-immediate-check.png`,
  `screenshot-0210s-left1500-check.png`,
  `screenshot-0255s-left1500-late-check.png`, and `screenshot-0290s.png` were
  visibly striped/corrupt and effectively frozen-looking after `ls_left:1500`.
- The byte-size visual gate reported `FIELD_LIKE_PRESENT`, first field-like at
  `195s`, `0` invalid screenshots after first field-like, and
  `passed-for-triage`; this is insufficient because the corruption is visual,
  not byte-size.
- `rpcs3.stderr.txt` was `343` bytes and reported:
  `RSX [0x026b4bc]: SIG: Thread terminated due to fatal error: Unimplemented FP CAL instruction`.
- `RPCS3.log:19920` reported the same RSX fatal at `0:03:18.476613`, aligned
  with the immediate post-left checkpoint.
- Host checks were clean across `6` snapshots.
- The lab stopped RPCS3 at `MaxSeconds 300`, but the RSX fatal had already
  happened at the post-left checkpoint.

Counters:

- GPU probe records `1,674`.
- Total observed DMA `1,950.72 MB`.
- Hot PCs: `0x451c` with `1,142` records / `1,121.32 MB`; `0x25cc` with
  `532` records / `829.40 MB`.
- Offload fit `spu-kernel-hle=963` / `too-small=711`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-fatal-log`.
- `failed-visual-corruption`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-rsx-fpcal-corrupt-field`.
- Not clean movement: the first post-left frame is corrupt and RSX-fatal.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now detects the strongdismiss600 `left1500`
  field-then-RSX-FP-CAL failure and suggests shrinking the same base to
  `ls_left:1200` with immediate screenshots.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1200;wait:1200;shot:left1200-immediate-check;wait:10800;shot:left1200-check;wait:45000;shot:left1200-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1275 Field-Clean Movement Boundary

Question:

- After the strongdismiss600 no-movement base re-proved clean field, retry the
  same repaired base with `ls_left:1275` and immediate screenshots. This checks
  whether the midpoint below the `left1350` VM40/corrupt-field failure is a
  stable movement boundary.

Artifact:

- `debug-captures\windows-lab\20260527-162159-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- The run used screen 1, PadApi, CPU affinity `0x0F`, frame/vblank `240`, GPU
  probe `Profile`, and `CleanAfterField`.
- The live load-target gate passed `PATH_TO_TENUTO_PRESENT` on attempt `1`.
- Manual load-target review showed the selected Path-to-Tenuto row, not Debug
  Save or an empty/damaged lower row.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` showed clean
  Path-to-Tenuto field before movement.
- `screenshot-0199s-left1275-immediate-check.png`,
  `screenshot-0210s-left1275-check.png`,
  `screenshot-0255s-left1275-late-check.png`, and `screenshot-0290s.png`
  showed the field stayed clean after the `ls_left:1275` movement pulse.
- Host checks were clean across prelaunch/postlaunch/postrun snapshots.
- `rpcs3.stderr.txt` and `RPCS3.log` had no actionable fatal/access/assertion,
  Vulkan, or device-lost hit after excluding the benign fatal-hints config line.
- Visual gate reported `FIELD_LIKE_PRESENT`; first accepted field was the
  post-load strongdismiss600 screenshot at `195s`, with `0` invalid screenshots
  after the first field-like frame.

Counters:

- GPU probe records `2,607`.
- Total observed DMA `3,736.60 MB`.
- Hot PCs: `0x451c` with `2,162.74 MB`; `0x25cc` with `1,573.86 MB`.
- Offload fit `spu-kernel-hle=1745` / `too-small=862`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.
- Repeated signatures remain SPU/kernel-HLE and route/codegen evidence, not GPU
  migration evidence.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-field-clean`.
- Clean movement boundary only.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Goal update:

- CPU-pressure reductions are now first-class bankable components when matched
  and clean. Use `stackable-cpu-pressure` or `windows-micro-win` for verified
  CPU-load, verifier-overhead, scheduler, or cache/residency pressure relief.
- These still do not lower the hard Windows 200% gate and must not be counted
  as speed proof, GPU migration, or gate completion without field, title
  Options/menu, and first-battle moving-gameplay visuals.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes a clean strongdismiss600
  `left1275` movement proof and no longer falls through to generic
  `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1312-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1312;wait:1200;shot:left1312-immediate-check;wait:10800;shot:left1312-check;wait:45000;shot:left1312-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Debug-Save Target Blocker

Question:

- After `left1316` was clean and `left1318` was fatal/corrupt, test the
  midpoint `ls_left:1317` without duplicating either boundary.

Artifact:

- `debug-captures\windows-lab\20260527-183942-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic-windows`.

Evidence:

- The run used screen `1`, CPU affinity `0x0F`, PadApi, a `23` token macro,
  frame/vblank `240/240`, and GPU probe `Profile`.
- Host checks were clean across `3` snapshots.
- The load-target gate aborted on attempt `1` before save-slot `Cross`.
- `eternal-sonata-load-target-summary.md` reported
  `DEBUG_SAVE_PROLOGUE_PRESENT`, with path/debug/empty/unknown counts
  `0/1/0/0`.
- Manual review of `screenshot-0081s-load-target-gate.png` showed the Load list
  selected `Save File 01`, `Debug Save`, `Prologue`, with damaged-save text.
- `eternal-sonata-windows-visual-gate-summary.md` reported
  `NO_FIELD_LIKE_SCREENSHOT`; the only screenshot was the Load UI.
- `rpcs3.stderr.txt` was `0` bytes. Fatal scan found no actionable VM/access,
  device-lost, assert, or crash line.

Counters:

- GPU probe records: `621`.
- Total observed DMA: `634.88 MB`.
- Hot PCs: `0x451c` `398.65 MB`, `0x25cc` `236.22 MB`.
- Offload fit mix: `spu-kernel-hle=312`, `too-small=309`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local scout traffic, and
  indirect SPU-DMA/RSX-resource overlap all stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-debug-save-target`.
- Not a `left1317` movement boundary: the movement pulse was never sent.
- Not field.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this specific `left1317`
  Debug Save blocker and does not fall back to generic state-aware routing.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Movement bracket remains `left1316` clean / `left1318` fatal-corrupt.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1317-debug-save -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1317-debug-save" -MaxSeconds 150 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 5 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Target Reproof Passed

Question:

- After the `left1317` midpoint aborted on `Debug Save / Prologue`, prove only
  whether the strongdismiss600 Down160 route can again select Path to Tenuto
  before retrying movement.

Artifact:

- `debug-captures\windows-lab\20260527-185940-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1317-debug-save-windows`.

Evidence:

- The run used screen `1`, CPU affinity `0x0F`, PadApi, a `7` token
  no-movement macro, frame/vblank `240/240`, GPU probe `Profile`, and visual
  gate `Off`.
- The load-target gate passed on attempt `1` with `PATH_TO_TENUTO_PRESENT`.
- `eternal-sonata-load-target-summary.md` reported path/debug/empty/unknown
  counts `1/0/0/0`, lower-row cursor markers `0`, and damaged-save markers `0`.
- Manual review of `screenshot-0081s-load-target-gate.png` showed the Load list
  on `Path to Tenuto`, `South Section`, `Ch. 1 Raindrops`, not Debug Save.
- `rpcs3.stderr.txt` was `0` bytes. Fatal scan found no actionable
  VM/access/device-lost/assert/crash line.
- Host checks were clean during route proof; the final postrun aggregate was
  `moderate` only because Codex CPU usage was sampled after the target gate had
  already passed. No timing or speed claim is made from this run.

Counters:

- GPU probe records: `1,257`.
- Total observed DMA: `1,310.05 MB`.
- Hot PCs: `0x451c` `786.14 MB`, `0x25cc` `523.91 MB`.
- Offload fit mix: `spu-kernel-hle=662`, `too-small=595`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local scout traffic, and
  indirect SPU-DMA/RSX-resource overlap all stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1317-debug-save-passed`.
- Target health only.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/standing update:

- The movement bracket remains `left1316` clean / `left1318` fatal-corrupt.
- `tools\ps3_harness_refiner.ps1` now recommends retrying `ls_left:1317` with
  immediate screenshots.
- `AGENTS.md` records the target reproof pass and keeps the next action on
  `left1317`.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1317;wait:1200;shot:left1317-immediate-check;wait:10800;shot:left1317-check;wait:45000;shot:left1317-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1318 Fatal Upper Boundary

Question:

- After `left1316` was clean and `left1321` was fatal/corrupt, test the
  `ls_left:1318` midpoint on the same Down160 strongdismiss600 base.

Artifact:

- `debug-captures\windows-lab\20260527-181934-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1318-longgate-diagnostic-windows`.

Evidence:

- The run used screen `1`, CPU affinity `0x0F`, PadApi, a `23` token macro,
  `240/240`, visual gate `CleanAfterField`, GPU probe `Profile`, and clean host
  checks across `6` snapshots.
- The load-target gate passed on attempt `1` with `PATH_TO_TENUTO_PRESENT`.
- Pre-movement field was clean at
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png`.
- Manual screenshots after `ls_left:1318` show RPCS3's likely-crashed overlay
  and corrupt/frozen field visuals:
  `screenshot-0199s-left1318-immediate-check.png`,
  `screenshot-0210s-left1318-check.png`,
  `screenshot-0255s-left1318-late-check.png`, and `screenshot-0290s.png`.
- The byte-size visual gate reported `FIELD_LIKE_PRESENT` with `0` invalid
  screenshots after first field-like, but manual screenshot review and fatal
  logs override that triage for this boundary.
- `rpcs3.stderr.txt` was `108` bytes and reported
  `PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation reading location 0x40`.
- `RPCS3.log:19168` reported the same PPU VM access violation at about
  `0:03:18.282928`.

Counters:

- GPU probe records `1,657`.
- Total observed DMA `1,901.90 MB`.
- Hot PCs: `0x451c` with `1,110.30 MB`, `0x25cc` with `791.60 MB`.
- Offload fit `spu-kernel-hle=946` / `too-small=711`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap all stayed `0 B`.

Classification:

- `failed-fatal-log`.
- `failed-visual-corruption`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1318-vm40-corrupt-field`.
- Not clean movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes `left1318` as the fatal upper
  boundary above clean `left1316`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1317;wait:1200;shot:left1317-immediate-check;wait:10800;shot:left1317-check;wait:45000;shot:left1317-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Windows Strongdismiss600 Left1321 Fatal Upper Boundary

Question:

- Does the `ls_left:1321` midpoint between clean `left1312` and fatal/corrupt
  `left1331` survive, or does it reproduce the `0x40` corrupt-field fatal?

Artifact:

- `debug-captures\windows-lab\20260527-171535-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1321-longgate-diagnostic-windows`.

Evidence:

- The run used the refiner-suggested Windows-only command on screen 1 with
  `WindowsCpuAffinityMask 0x0F`, `WindowsFrameLimit 240`, `WindowsVblankRate 240`,
  `EternalSonataGpuProbe Profile`, and `CleanAfterField`.
- The load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; the gate
  summary reported path/debug/empty/unknown counts `1/0/0/0`, no lower-row
  cursor markers, and no damaged-save text markers.
- `screenshot-0196s-post-load-complete-strongdismiss600-18s.png` was a clean
  pre-movement Path-to-Tenuto field screenshot.
- Manual screenshot review found `screenshot-0199s-left1321-immediate-check.png`,
  `screenshot-0210s-left1321-check.png`,
  `screenshot-0255s-left1321-late-check.png`, and `screenshot-0290s.png` all
  showed RPCS3's likely-crashed overlay and corrupt/frozen field visuals after
  the `ls_left:1321` pulse.
- `rpcs3.stderr.txt` and `RPCS3.log:19024` reported
  `PPU[0x100000c] Thread () [0x002aedd0]` `VM: Access violation reading
  location 0x40 (unmapped memory)` around `0:03:18.141882`.
- Visual gate still reported `FIELD_LIKE_PRESENT` and `0` invalid screenshots
  after first field-like, so manual screenshot/log review overrides byte-size
  triage for this rung.
- Host contention stayed clean across `6` snapshots.
- The run stopped at the planned `MaxSeconds 300` wall-time limit.

Counters:

- GPU probe records: `1,665`.
- Total observed DMA: `1,851.15 MB`.
- Hot PCs: `0x451c` / `1,051.07 MB`, `0x25cc` / `800.08 MB`.
- Offload fit mix: `spu-kernel-hle=923`, `too-small=742`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-fatal-log`.
- `failed-visual-corruption`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1321-vm40-corrupt-field`.
- Not clean movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the `left1321`
  VM40/corrupt-field failure, banks `left1312` as the clean lower boundary and
  `left1321` as the fatal upper boundary, and suggests `ls_left:1316`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact Windows-only action:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1316;wait:1200;shot:left1316-immediate-check;wait:10800;shot:left1316-check;wait:45000;shot:left1316-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Windows Strongdismiss600 Left1316 Clean Boundary

Question:

- Does the `ls_left:1316` midpoint between clean `left1312` and fatal/corrupt
  `left1321` survive clean field movement?

Artifact:

- `debug-captures\windows-lab\20260527-173311-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-longgate-diagnostic-windows`.

Evidence:

- The run used the refiner-suggested Windows-only command on screen 1 with
  `WindowsCpuAffinityMask 0x0F`, `WindowsFrameLimit 240`, `WindowsVblankRate 240`,
  `EternalSonataGpuProbe Profile`, and `CleanAfterField`.
- The load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; the gate
  summary reported path/debug/empty/unknown counts `1/0/0/0`, no lower-row
  cursor markers, and no damaged-save text markers.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` showed clean
  Path-to-Tenuto field before movement.
- Manual screenshot review found clean accepted field movement at
  `screenshot-0199s-left1316-immediate-check.png` and clean field visuals at
  `screenshot-0210s-left1316-check.png`,
  `screenshot-0255s-left1316-late-check.png`, and `screenshot-0290s.png`.
  There was no RPCS3 likely-crashed overlay, striped/corrupt field, or save
  prompt.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like screenshot at
  `195s`, and `0` invalid screenshots after first field-like.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found no actionable
  access/assertion/device-lost/FP-CAL/fatal log hit.
- Host contention stayed clean across `6` snapshots.
- The run stopped at the planned `MaxSeconds 300` wall-time limit.

Counters:

- GPU probe records: `2,608`.
- Total observed DMA: `3,752.06 MB`.
- Hot PCs: `0x451c` / `2,268.59 MB`, `0x25cc` / `1,483.47 MB`.
- Offload fit mix: `spu-kernel-hle=1751`, `too-small=857`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-field-clean`.
- Clean movement boundary only.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the `left1316` clean movement
  boundary, banks `left1316` as the clean lower boundary below the `left1321`
  fatal/corrupt upper boundary, and suggests `ls_left:1318`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact Windows-only action:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1318-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1318;wait:1200;shot:left1318-immediate-check;wait:10800;shot:left1318-check;wait:45000;shot:left1318-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Windows Strongdismiss600 Left1312 Movement Boundary

Question:

- Does the `ls_left:1312` midpoint below the known `left1350` VM40/corrupt
  upper boundary survive as clean field movement under the same stock Down160
  strongdismiss600 route?

Artifact:

- `debug-captures\windows-lab\20260527-163849-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1312-longgate-diagnostic-windows`.

Evidence:

- The run used the refiner-suggested Windows-only command on screen 1 with
  `WindowsCpuAffinityMask 0x0F`, `WindowsFrameLimit 240`, `WindowsVblankRate 240`,
  `EternalSonataGpuProbe Profile`, and `CleanAfterField`.
- The load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; the gate
  summary reported path/debug/empty/unknown counts `1/0/0/0`, no lower-row
  cursor markers, no damaged-save text markers, and path candidate rows
  `190,535`.
- Visual gate status was `FIELD_LIKE_PRESENT`, first field-like screenshot was
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` at `195s`,
  and invalid screenshots after first field-like were `0`.
- Manual screenshot review confirmed clean field before movement, accepted
  `ls_left:1312` displacement at
  `screenshot-0198s-left1312-immediate-check.png`, and clean field visuals at
  `screenshot-0210s-left1312-check.png`,
  `screenshot-0255s-left1312-late-check.png`, and `screenshot-0290s.png`.
- Host contention stayed clean across `6` snapshots. Fatal/log scan found no
  actionable fatal/access/assertion/Vulkan device-lost signature; the only
  matching log lines were Vulkan initialization and the benign
  `Show fatal error hints: false` setting.
- The run stopped at the planned `MaxSeconds 300` wall-time limit.

Counters:

- GPU probe records: `2,599`.
- Total observed DMA: `3,710.27 MB`.
- Hot PCs: `0x451c` / `2,159.45 MB`, `0x25cc` / `1,550.82 MB`.
- Offload fit mix: `spu-kernel-hle=1736`, `too-small=863`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1312-field-clean`.
- Clean movement boundary only.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Pattern update:

- The last-week pattern still holds: the repeatable pressure is CPU/SPU-side
  Spurs DMA around `0x451c` and `0x25cc`, not a proven RSX-local/GPU migration
  path. CPU-pressure reductions remain worth banking as `stackable-cpu-pressure`
  or `windows-micro-win` only after matched clean visuals, clean host checks,
  and no fatal/corrupt-field evidence.
- Route volatility is now the main blocker before speed stacking: several
  attempts failed on wrong save target, Load-complete stickiness, or post-left
  corruption even when raw title FPS looked high. Treat title-bar FPS from
  route-invalid or menu/loading frames as telemetry only.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the `left1312` clean boundary,
  banks it under the `left1350` fatal/corrupt upper boundary, and suggests the
  next midpoint `ls_left:1331`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact Windows-only action:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1331-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1331;wait:1200;shot:left1331-immediate-check;wait:10800;shot:left1331-check;wait:45000;shot:left1331-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Windows Strongdismiss600 Left1331 Fatal Upper Boundary

Question:

- Does the `ls_left:1331` midpoint above clean `left1312` survive, or does it
  reproduce the `0x40` corrupt-field fatal seen at `left1350`?

Artifact:

- `debug-captures\windows-lab\20260527-165816-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1331-longgate-diagnostic-windows`.

Evidence:

- The run used the refiner-suggested Windows-only command on screen 1 with
  `WindowsCpuAffinityMask 0x0F`, `WindowsFrameLimit 240`, `WindowsVblankRate 240`,
  `EternalSonataGpuProbe Profile`, and `CleanAfterField`.
- The load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; the gate
  summary reported path/debug/empty/unknown counts `1/0/0/0`, no lower-row
  cursor markers, and no damaged-save text markers.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` was a clean
  pre-movement Path-to-Tenuto field screenshot.
- Manual screenshot review found `screenshot-0198s-left1331-immediate-check.png`,
  `screenshot-0210s-left1331-check.png`,
  `screenshot-0255s-left1331-late-check.png`, and `screenshot-0290s.png` all
  showed RPCS3's likely-crashed overlay and corrupt/frozen field visuals after
  the `ls_left:1331` pulse.
- `rpcs3.stderr.txt` and `RPCS3.log:19019` reported
  `PPU[0x100000c] Thread () [0x002aedd0]` `VM: Access violation reading
  location 0x40 (unmapped memory)` around `0:03:18.002943`.
- Visual gate still reported `FIELD_LIKE_PRESENT` and `0` invalid screenshots
  after first field-like, so manual screenshot/log review overrides byte-size
  triage for this rung.
- Host contention stayed clean across `6` snapshots.
- The run stopped at the planned `MaxSeconds 300` wall-time limit.

Counters:

- GPU probe records: `1,671`.
- Total observed DMA: `1,895.15 MB`.
- Hot PCs: `0x451c` / `1,131.83 MB`, `0x25cc` / `763.32 MB`.
- Offload fit mix: `spu-kernel-hle=958`, `too-small=713`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-fatal-log`.
- `failed-visual-corruption`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1331-vm40-corrupt-field`.
- Not clean movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the `left1331`
  VM40/corrupt-field failure, banks `left1312` as the clean lower boundary and
  `left1331` as the fatal upper boundary, and suggests `ls_left:1321`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact Windows-only action:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1321-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1321;wait:1200;shot:left1321-immediate-check;wait:10800;shot:left1321-check;wait:45000;shot:left1321-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Field Clean Reproof

Question:

- After the target-only Up-repair diagnostic restored selected `Save File 01`
  / `Path to Tenuto`, prove whether the same stock Down160 strongdismiss600
  no-movement route reaches stable field before retrying `ls_left:1275`.

Artifact:

- `debug-captures\windows-lab\20260527-160714-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Command used the stock Down160 strongdismiss600 macro with no movement input:
  `gate_load_target:60000`, save-slot `Cross`, post-load `Cross:600`, then
  late field screenshots.
- Load-target gate passed on attempt `1` with `PATH_TO_TENUTO_PRESENT`.
  Classifier counts were path/debug/empty/unknown `1/0/0/0`, lower-row cursor
  markers `0`, and damaged-save markers `0`.
- Manual review of `screenshot-0081s-load-target-gate.png` and
  `screenshot-0176s-load-complete-90s.png` showed selected `Save File 01` /
  `Path to Tenuto` / `South Section` / `Ch. 1 Raindrops`; `Save File 02` also
  showed Path-to-Tenuto, while a bottom damaged-save message was still visible.
  The selected row loaded successfully, so record the damaged-row text as a
  screenshot nuance, not a blocker for this run.
- Manual review of `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`
  showed clean Path-to-Tenuto field with Polka at the save point. The late
  checks `screenshot-0241s-strongdismiss600-late-check.png` and
  `screenshot-0286s-strongdismiss600-very-late-check.png` stayed field-clean.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` at `195s`,
  required field before `260s` passed, and invalid screenshots after first
  field-like were `0`.
- Host contention was clean across `5` snapshots.
- Fatal scan of `rpcs3.stderr.txt` and `RPCS3.log` found no actionable fatal,
  access-violation, assertion, Vulkan error, or device-lost line after excluding
  the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `2,604`.
- Total observed DMA: `3,687.56 MB`.
- Hot PCs: `0x451c` `2,132.05 MB`, `0x25cc` `1,555.51 MB`.
- Offload fit: `spu-kernel-hle=1770`, `too-small=834`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`.
- Field-only/no-movement route base.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact
  strongdismiss600 single-dismiss no-movement field-clean shape instead of
  falling through to generic `cpu4-stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` carries the same
  rule: a clean single-dismiss no-movement long-gate proof resumes the same
  strongdismiss600 `ls_left:1275` midpoint with immediate screenshots.
- Verified refiner output now emits the same `left1275` command and a
  `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`
  resolved-control anti-pattern.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Latest Addendum: Save File 05 Repaired To Top Target

- Latest artifact:
  `debug-captures\windows-lab\20260527-155055-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-windows`.
- This target-only diagnostic was run after the newer Save File 05 damaged-row
  blocker. It waited for the Load list, sent five bounded `Up` pulses with
  screenshots, and did not press save-slot `Cross`.
- Result: `PATH_TO_TENUTO_PRESENT`, path/debug/empty/unknown `7/0/0/2`,
  lower-row cursor markers `0`, damaged-save markers `0`.
- Manual screenshot `screenshot-0108s-load-target-gate.png` shows selected
  `Save File 01` / `Path to Tenuto`; lower rows are only `File does not exist`.
- Host was clean across `6` snapshots. Fatal scan was clean except the benign
  `Show fatal error hints: false` config line.
- GPU probe was route-only: `1,370` records, `1,419.69 MB` observed DMA,
  hot PCs `0x451c` (`878.72 MB`) and `0x25cc` (`540.97 MB`), with promoted
  CPU/SPU-to-GPU replacement `0 B`, direct RSX-local `0 B`, and indirect
  overlap `0 B`.
- Classification: `route-tooling`,
  `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-passed`.
  Not field, not movement, not first-battle proof, not speed, not
  `gpu-migration-credit`, not 200%.
- Refiner now points to no-movement stability next:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1275 Fresh Route Revalidation

Question:

- After the latest no-movement load-stability control passed, revalidate the
  same strongdismiss600 route with `ls_left:1275`, then prevent the refiner from
  looping through older left-only midpoint proofs already present in the ledger.

Artifact:

- `debug-captures\windows-lab\20260527-221838-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 23-token macro.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; path/debug/empty/unknown counts were `1/0/0/0`.
- Manual screenshot review confirmed `screenshot-0081s-load-target-gate.png`
  on `Save File 01 / Path to Tenuto`, clean pre-movement field at
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png`, accepted
  left movement at `screenshot-0199s-left1275-immediate-check.png`, and clean
  late movement at `screenshot-0255s-left1275-late-check.png`.
- Visual summary reported `FIELD_LIKE_PRESENT`, first field-like screenshot
  at `196s`, `11` field-like screenshots, and zero invalid screenshots after
  first field-like output.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal scan matched only the
  benign `Show fatal error hints: false` config line.
- Host samples were clean during the route. The final postrun sample was
  `moderate` because `codex` was hot after the macro, so this run is not
  speed-comparable.
- Window-title samples ranged from `27.57` to `45.58` FPS, average `34.42`;
  this is route telemetry only.

Counters:

- GPU probe records: `2615`.
- Total observed DMA: `3740.25 MB`.
- Offload fit mix: `spu-kernel-hle=1753`, `too-small=862`.
- Hot PCs: `0x451c` `2196.81 MB`, `0x25cc` `1543.44 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-field-clean-after-pinned-ladder`.
- This revalidates the route and left movement only.
- Older durable evidence already contains the left-only ladder:
  `left1312` clean, `left1331` fatal, `left1321` fatal, `left1316` clean,
  `left1318` fatal, and `left1317` clean.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes fresh `left1275` clean proof
  after the historical left-only ladder is already pinned, and skips stale
  `left1312` / `left1331` / `left1321` / `left1316` / `left1318` / `left1317`
  midpoint reruns.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same anti-loop rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1316;wait:1200;shot:left1316-immediate-check;ls_down:60;wait:1200;shot:left1316-down60-immediate-check;wait:10800;shot:left1316-down60-check;wait:45000;shot:left1316-down60-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1316 Down60 Debug-Save Abort

Question:

- Does the pinned `left1316` lower boundary tolerate a smaller `down60` nudge
  after the fresh `left1275` route revalidation?

Artifact:

- `debug-captures\windows-lab\20260527-224241-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 26-token macro.
- The run aborted before save-slot `Cross`; the load-target gate failed at
  `81s` with `DEBUG_SAVE_PROLOGUE_PRESENT`.
- Manual screenshot review of
  `screenshot-0081s-load-target-gate.png` confirmed `Save File 01 /
  Debug Save / Prologue`, with lower rows showing `File does not exist` and
  `Save file has been damaged`.
- The input macro stopped before field load, so neither `left1316` nor `down60`
  movement was tested.
- Visual summary reported `NO_FIELD_LIKE_SCREENSHOT`, one screenshot, and
  primary class `wrong-window-or-other-small-png`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal scan found only Vulkan init
  lines and the benign `Show fatal error hints: false` config line.
- Host samples were clean prelaunch, postlaunch, and postrun.
- Window-title sample at the gate was `48.75` FPS; this is load-menu telemetry
  only and not comparable speed evidence.

Counters:

- GPU probe records: `624`.
- Total observed DMA: `603.31 MB`.
- Offload fit mix: `too-small=358`, `spu-kernel-hle=266`.
- Hot PCs: `0x451c` `402.47 MB`, `0x25cc` `200.83 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-debug-save-target`.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this specific
  `left1316-down60` Debug Save abort and recommends save-list inventory rather
  than the generic state-aware polling route.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same anti-loop rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-inventory;down:160;wait:900;shot:title-after-down160-inventory;cross:120;wait:60000;shot:load-list-initial-after60;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;down:120;wait:900;shot:load-list-after-down3;down:120;wait:900;shot:load-list-after-down4;down:120;wait:900;shot:load-list-after-down5;down:120;wait:900;shot:load-list-after-down6" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Save-List Inventory Black Transition

Question:

- After the `left1316-down60` gate selected `Save File 01 / Debug Save /
  Prologue`, can the no-slot inventory observe the current save-list rows and
  identify the Path-to-Tenuto cursor state?

Artifact:

- `debug-captures\windows-lab\20260527-230232-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 26-token no-slot inventory
  macro.
- Manual screenshot review confirmed the title menu at
  `screenshot-0068s-title-settle-before-inventory.png`, then `LOAD` selected at
  `screenshot-0069s-title-after-down160-inventory.png`.
- Every intended row screenshot was black-overlay only:
  `screenshot-0130s-load-list-initial-after60.png`,
  `screenshot-0132s-load-list-after-down1.png`,
  `screenshot-0133s-load-list-after-down2.png`,
  `screenshot-0135s-load-list-after-down3.png`,
  `screenshot-0136s-load-list-after-down4.png`,
  `screenshot-0138s-load-list-after-down5.png`, and
  `screenshot-0139s-load-list-after-down6.png`.
- No save slot was loaded, no field was reached, and no save-list row was
  actually observed. This invalidates any old inference that the inventory
  proved initial Path rows.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal scan found only Vulkan init
  lines and the benign `Show fatal error hints: false` config line.
- Host was clean during the useful route samples; postrun was `moderate`
  because Codex was hot after the macro.
- Window-title samples across screenshots ranged from `38.63` to `59.12` FPS;
  this is title/black-transition telemetry only and not comparable speed
  evidence.

Counters:

- GPU probe records: `1375`.
- Total observed DMA: `1321.07 MB`.
- Offload fit mix: `too-small=737`, `spu-kernel-hle=638`.
- Hot PCs: `0x451c` `868.57 MB`, `0x25cc` `452.50 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-black-overlay-visual`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-black-transition`.
- Not row inventory proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now blocks the previous false
  `save-list-inventory-initial-path-rows` inference when the latest inventory
  screenshots are black-overlay only.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-blackgate;down:160;wait:900;shot:title-after-down160-blackgate;cross:120;wait:12000;shot:pregate-12s;wait:18000;shot:pregate-30s;wait:15000;shot:pregate-45s;wait:15000;shot:pregate-60s;gate_load_target:60000;shot:path-target-after-pregate-black-diagnostic" -MaxSeconds 210 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Load-Stability Reproof

Question:

- After `left1316-down120` passed `PATH_TO_TENUTO_PRESENT` but stayed on
  `Now Loading...`, determine whether the same strongdismiss600 base can still
  reach clean Path-to-Tenuto field with no movement.

Artifact:

- `debug-captures\windows-lab\20260527-215837-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 20-token macro.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; path/debug/empty/unknown counts were `1/0/0/0`.
- Manual screenshot review confirmed `screenshot-0081s-load-target-gate.png`
  on the Path-to-Tenuto save row, `screenshot-0176s-load-complete-90s.png`
  with the `Load complete` prompt, clean field at
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`, and clean
  late field at `screenshot-0286s-strongdismiss600-very-late-check.png`.
- Visual summary reported `FIELD_LIKE_PRESENT`, first field-like screenshot
  at `195s`, `10` field-like screenshots, and zero invalid screenshots after
  first field-like output.
- Host contention was clean across `5` snapshots.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal scan matched only the
  benign `Show fatal error hints: false` config line.
- Window-title samples ranged from `26.89` to `45.89` FPS, average `35.39`,
  but this is route/load telemetry only.

Counters:

- GPU probe records: `2621`.
- Total observed DMA: `3774.28 MB`.
- Offload fit mix: `spu-kernel-hle=1764`, `too-small=857`.
- Hot PCs: `0x451c` `2157.06 MB`, `0x25cc` `1617.22 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`.
- This resolves the latest no-movement load-stability control only.
- `left1316-down120` remains a loading-only failure; movement was not tested.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- No harness code change was needed. The post-run refiner recognized this as a
  resolved no-movement control and recommended the same strongdismiss600 base
  with `ls_left:1275` plus immediate screenshots.
- `AGENTS.md` now carries the same current-state rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Field Reproof After Left1317 Repair

Question:

- After save-list inventory showed the initial row is `Save File 01 / Path to
  Tenuto`, re-prove the no-movement route base before another `left1317`
  movement attempt.

Artifact:

- `debug-captures\windows-lab\20260527-195951-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Windows-only RPCS3 run on screen `1`, PadApi input, CPU affinity `0x0F`,
  frame/vblank `240/240`, and the expected 20-token no-movement macro.
- Load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; path/debug/
  empty/unknown counts were `1/0/0/0`, with no lower-row cursor or damaged-save
  markers.
- Visual gate reported `FIELD_LIKE_PRESENT`; first field-like screenshot was
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png` at `196s`.
- Manual screenshot review confirmed clean Path-to-Tenuto field at `196s`,
  `241s`, and `287s`, with no prompt, corrupt overlay, or load-menu stall.
- Host contention stayed clean across `5` snapshots.
- `rpcs3.stderr.txt` was `0` bytes. Fatal scan found only the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `2,612`.
- Total observed DMA: `3,817.59 MB`.
- Offload fit mix: `spu-kernel-hle=1757`, `too-small=855`.
- Hot PCs: `0x451c` `2,256.95 MB`, `0x25cc` `1,560.64 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean-after-left1317-repair`.
- Repaired no-movement route base only.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now distinguishes this no-movement field pass
  after the `left1317` save-list repair from the older generic no-movement path.
- The next action now stays on the current bracket and suggests `left1317`, not
  obsolete `left1275`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1317;wait:1200;shot:left1317-immediate-check;wait:10800;shot:left1317-check;wait:45000;shot:left1317-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Save File 05 Cursor Repair

Question:

- The latest no-movement strongdismiss600 proof selected a lower `Save File 05`
  Path-to-Tenuto row with damaged rows above it, then stayed in the Load UI with
  `Save data cannot be found` / `Load complete`. Determine whether this is a
  file-restore problem or selected-row/internal-slot state, then prove only the
  load target before any slot `Cross`, movement, HLE, RSX, GPU, or speed work.

Artifacts:

- `debug-captures\windows-lab\20260527-152343-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.
- `debug-captures\windows-lab\20260527-155055-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-windows`.

Evidence:

- Manual review of the latest failed no-movement gate screenshot showed
  `Save File 05` / `Path to Tenuto` selected while upper rows said
  `Save file has been damaged`.
- `tools\classify_eternal_sonata_load_target.ps1` now reports that run as
  `DAMAGED_SAVE_TARGET`: path/debug/empty/unknown `11/0/0/1`, lower-row cursor
  markers `2`, damaged-save text markers `11`.
- The live RPCS3 save bytes already matched
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100` for
  `ICON0.PNG`, `PARAM.SFO`, `PREVIEW0`, and `SAVEDATA`; hashes equal for all
  four files.
- The live PS3 savedata directory contained only `BLUS3016100`, so repeating
  the same checkpoint restore is not a useful next step.
- I updated `tools\ps3_harness_refiner.ps1`,
  `.agents\skills\ps3-continual-harness-refiner\SKILL.md`, and `AGENTS.md` so
  this condition points to a target-only stable-load-list `Up` repair diagnostic
  rather than another restore or movement route.
- The target-only diagnostic intentionally did not press save-slot `Cross`. It
  waited for the Load list, captured `screenshot-0100s-load-list-before-uprepair.png`,
  sent five bounded `Up` pulses with screenshots, then ran `gate_load_target`.
- The diagnostic passed `PATH_TO_TENUTO_PRESENT` after attempt `1`; counts were
  path/debug/empty/unknown `7/0/0/2`, lower-row cursor markers `0`, and
  damaged-save text markers `0`.
- Manual screenshot `screenshot-0108s-load-target-gate.png` shows selected
  `Save File 01` / `Path to Tenuto` / `South Section` / `Ch. 1 Raindrops`,
  with lower rows only `File does not exist`.
- Host checks were clean across `6` snapshots. Fatal scan was clean except the
  benign `Show fatal error hints: false` config line.

Counters:

- Target-only diagnostic GPU probe records: `1,370`.
- Total observed DMA: `1,419.69 MB`.
- Hot PCs: `0x451c` with `878.72 MB`, `0x25cc` with `540.97 MB`.
- Offload fit: `spu-kernel-hle=719`, `too-small=651`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-passed`.
- Target selection repaired to top-row `Save File 01` only.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now emits the stable-load-list
  `loadlist-uprepair-target-diagnostic` when the latest no-movement proof lands
  on the damaged lower Path row.
- The refiner recognizes a passed `loadlist-uprepair-target-diagnostic` as
  target-selection repair only and suggests no-movement stability next, not
  movement, HLE, RSX, GPU, or speed work.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 No-Movement Stability Re-Proved After Up-Repair

Question:

- After bounded Up-repair restored top `Save File 01 / Path to Tenuto`, rerun
  the strongdismiss600 no-movement long-gate proof before allowing any
  movement, battle, HLE, RSX, GPU, or speed work.

Artifact:

- `debug-captures\windows-lab\20260528-032238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate CleanAfterField`, and the intended 20-token no-movement
  macro.
- The load-target gate passed on attempt 1 at `81s` with
  `PATH_TO_TENUTO_PRESENT`: path-to-tenuto `1`, debug-save-prologue `0`,
  empty-load-slot `0`, unknown `0`, lower-row cursor markers `0`, and
  damaged-save text markers `0`.
- Manual review of `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`,
  `screenshot-0241s-strongdismiss600-late-check.png`, and
  `screenshot-0286s-strongdismiss600-very-late-check.png` confirmed clean
  Path-to-Tenuto field visuals with no movement branch.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like at `195s`, `10`
  field-like large screenshots, and `0` invalid screenshots after first field.
- Host contention was not clean enough for performance comparison: summary
  `high`, external summary `moderate`, with a bad GPU-engine sample at `300s`
  and postrun Codex CPU load.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `2613`.
- Total observed DMA: `3,743.33 MB`.
- Offload fit mix: `spu-kernel-hle=1741`, `too-small=872`.
- Hot PCs: `0x451c` `2,231.64 MB`, `0x25cc` `1,511.69 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`.
- This banks only the repaired no-movement field base.
- Not movement proof.
- Not first-battle proof.
- Not speed, especially because host contention was high/moderate.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects the same
  strongdismiss600 base with `ls_left:1275` and immediate/late screenshots.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Title-To-Load Pregate Path Target Repaired

Question:

- After the latest save-list inventory selected `LOAD` but row screenshots were
  black-overlay only, can a timed pre-gate diagnostic observe the Load list and
  prove the correct Path-to-Tenuto target before pressing a save slot?

Artifact:

- `debug-captures\windows-lab\20260527-232417-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 16-token pre-gate macro.
- `screenshot-0068s-title-settle-before-blackgate.png` showed the title menu.
- `screenshot-0069s-title-after-down160-blackgate.png` showed `LOAD` selected.
- `screenshot-0082s-pregate-12s.png`,
  `screenshot-0101s-pregate-30s.png`,
  `screenshot-0116s-pregate-45s.png`, and
  `screenshot-0131s-pregate-60s.png` were stable Load-list frames with the top
  selected row showing `Save File 01 / Path to Tenuto / South Section /
  Ch. 1 Raindrops`.
- `screenshot-0132s-load-target-gate.png` also showed Path to Tenuto, and the
  classifier reported `PATH_TO_TENUTO_PRESENT` with path/debug/empty/unknown
  counts `5/0/0/2`.
- The macro intentionally stopped before save-slot `Cross`, so no field,
  movement, menu, or first-battle proof was attempted.
- Host checks were clean across `7` snapshots.
- `rpcs3.stderr.txt` was `0` bytes. Targeted crash/access/device-lost/assert
  scan found no actionable hit; the only broad `fatal` match was the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `1793`.
- Total observed DMA: `1835.58 MB`.
- Offload fit mix: `spu-kernel-hle=927`, `too-small=866`.
- Hot PCs: `0x451c` `1065.56 MB`, `0x25cc` `770.01 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-path-target-passed-after-left1316-down60-debug-save`.
- Target selection is repaired for the current route.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now treats this intentional no-field
  pre-gate diagnostic as resolved route-control evidence instead of a generic
  wrong-window visual failure.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1316;wait:1200;shot:left1316-immediate-check;ls_down:60;wait:1200;shot:left1316-down60-immediate-check;wait:10800;shot:left1316-down60-check;wait:45000;shot:left1316-down60-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Lower-Row Damaged Target Reclassification

Question:

- After the save-list inventory showed initial Path-to-Tenuto rows, re-run the
  strongdismiss600 no-movement proof and determine whether the gate was loading
  a real Path save or another damaged/missing selected row.

Artifact:

- `debug-captures\windows-lab\20260527-152343-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- The run stayed Windows-only on `-WindowsGameScreen 1`, PadApi, CPU affinity
  `0x0F`, frame/vblank `240/240`, and `-EternalSonataGpuProbe Profile`.
- The original load-target gate accepted `PATH_TO_TENUTO_PRESENT` on attempt
  `1`, but manual review showed the selected row was lower `Save File 05` with
  Path-to-Tenuto preview text while the screen also showed damaged-save rows.
- `screenshot-0176s-load-complete-90s.png` displayed
  `Error: Save data cannot be found`.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`,
  `screenshot-0241s-strongdismiss600-late-check.png`, and
  `screenshot-0286s-strongdismiss600-very-late-check.png` stayed in the Load UI
  with `Load complete.`; field never appeared.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`, with `12`
  wrong-window/other-small PNG classifications and no field-like screenshot at
  or before `260s`.
- `rpcs3.stderr.txt` was `0` bytes, host checks were clean, and fatal scan found
  only the benign `Show fatal error hints: false` config line.
- `tools\classify_eternal_sonata_load_target.ps1` now adds a non-OCR
  damaged-save text guard. Reclassifying the run reports
  `DAMAGED_SAVE_TARGET`, `11` damaged-save text marker screenshots, and one
  lower-row Path preview with cursor drift/damaged text.

Counters:

- GPU probe records `2,554`.
- Total observed DMA `2,566.28 MB`.
- Offload fit `too-small=1285` / `spu-kernel-hle=1269`.
- Hot PCs: `0x451c` with `2,013` records / `1,734.59 MB`; `0x25cc` with `541`
  records / `831.69 MB`.
- Promoted CPU/SPU-to-GPU replacement `0 B`; direct RSX-local scout traffic
  `0 B`; indirect SPU-DMA/RSX-resource overlap `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-damaged-save-target`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\classify_eternal_sonata_load_target.ps1` now detects damaged-save text
  markers in addition to multi-row Path/Debug matching and lower-row cursor
  markers.
- `tools\ps3_harness_refiner.ps1`,
  `.agents\skills\ps3-continual-harness-refiner\SKILL.md`, and `AGENTS.md`
  now treat this lower-row damaged shape as `DAMAGED_SAVE_TARGET`, not a
  `Load complete` route that should get another double-dismiss.
- `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` now blocks automatic route
  reruns and says to repair the selected Path-to-Tenuto save target, then run
  only a target-gate reproof before any no-movement, `left1275`, battle, HLE,
  RSX, GPU, or speed work.

Next allowed action:

```powershell
# No automatic route rerun: repair the selected Path-to-Tenuto save target, then run a target-only gate until DAMAGED_SAVE_TARGET becomes PATH_TO_TENUTO_PRESENT. Do not press save-slot Cross or start movement/speed work before that.
```

## 2026-05-27 StrongDismiss600 Left1275 Save-List Inventory Reproof

Question:

- After the `left1275` route drifted to `Debug Save / Prologue`, is the current
  initial Load-list row actually Path to Tenuto, and do `Down` inputs move the
  cursor into empty rows?

Artifact:

- `debug-captures\windows-lab\20260527-151442-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- The run was a no-slot-cross inventory. It selected `LOAD` from title with
  `Down:160`, waited `60s` on the Load list, then captured repeated `Down`
  screenshots without pressing the save slot.
- Manual review showed `screenshot-0068s-title-settle-before-inventory.png` on
  the title menu with `New Game` selected and
  `screenshot-0070s-title-after-down160-inventory.png` with `Load` selected.
- Manual review of `screenshot-0130s-load-list-initial-after60.png` showed
  `Save File 01` / `Path to Tenuto` / `South Section` / `Ch. 1 Raindrops`.
- `screenshot-0132s-load-list-after-down1.png` and
  `screenshot-0134s-load-list-after-down2.png` still showed the top
  Path-to-Tenuto preview, but the cursor marker moved to lower empty rows.
- `screenshot-0135s-load-list-after-down3.png` through
  `screenshot-0140s-load-list-after-down6.png` showed only `File does not
  exist` rows after scrolling down.
- `tools\classify_eternal_sonata_load_target.ps1` reported
  `DAMAGED_SAVE_TARGET` for the whole folder because it correctly detected
  lower-row cursor markers after the first `Down`, not because the initial row
  was Debug Save.
- Host checks were clean across `5` snapshots.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe recorded `1,346` rows and `1,268.28 MB` observed DMA.
- Hot PCs: `0x451c` `920.04 MB`, `0x25cc` `348.24 MB`.
- Offload fit mix: `too-small=755`, `spu-kernel-hle=591`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local scout traffic, and
  indirect SPU-DMA/RSX-resource overlap all stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-initial-path-rows`.
- The initial Load-list row is usable Path to Tenuto.
- Do not normalize with save-list `Down`/`Up`; those moves select empty rows.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now gives this inventory result an explicit
  decision string instead of the stale generic "newest valid-field route base"
  wording.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1275 Debug Save Drift

Question:

- After the double-dismiss no-movement proof reached clean Path-to-Tenuto field
  before opening the field Save prompt, can the same strongdismiss600 base resume
  into the `ls_left:1275` movement midpoint?

Artifact:

- `debug-captures\windows-lab\20260527-150629-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- The run used the stock Down160 strongdismiss600 left1275 macro with GPU probe
  profiling only; HLE, RSX, verifier, kernel capsule, and speed toggles were
  all off.
- The load-target gate aborted before save-slot `Cross` on attempt 1 at `82s`.
- `eternal-sonata-load-target-summary.md` reported
  `DEBUG_SAVE_PROLOGUE_PRESENT` with path/debug/empty/unknown counts `0/1/0/0`.
- Manual review of `screenshot-0082s-load-target-gate.png` showed
  `Save File 01` / `Debug Save` / `Prologue`; no Path-to-Tenuto row was
  selected.
- `eternal-sonata-windows-visual-gate-summary.md` reported
  `NO_FIELD_LIKE_SCREENSHOT`; the only screenshot was
  `wrong-window-or-other-small-png` by byte-size heuristic, but visually it was
  the Load list on the wrong save target.
- Host checks were clean across prelaunch, postlaunch, and postrun snapshots.
- `rpcs3.stderr.txt` was `0` bytes, and the fatal scan found only the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe recorded `619` rows and `562.44 MB` observed DMA.
- Hot PCs: `0x451c` `425.53 MB`, `0x25cc` `136.91 MB`.
- Offload fit mix: `too-small=384`, `spu-kernel-hle=235`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local scout traffic, and
  indirect SPU-DMA/RSX-resource overlap all stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-debug-save-target`.
- Not field.
- Not movement: the macro aborted before save-slot `Cross`, so `ls_left:1275`
  was never executed.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the left1275
  `DEBUG_SAVE_PROLOGUE_PRESENT` abort as selected-row route drift instead of
  generic load-target failure.
- The refiner excludes this shape from generic state-aware fallback and suggests
  the no-slot-cross save-list inventory command.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-inventory;down:160;wait:900;shot:title-after-down160-inventory;cross:120;wait:60000;shot:load-list-initial-after60;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;down:120;wait:900;shot:load-list-after-down3;down:120;wait:900;shot:load-list-after-down4;down:120;wait:900;shot:load-list-after-down5;down:120;wait:900;shot:load-list-after-down6" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Clean Boundary Pinned

Question:

- After the no-movement route base was repaired, determine whether the current
  `left1317` midpoint can pass as clean movement while the existing `left1318`
  proof remains the fatal upper bound.

Artifact:

- `debug-captures\windows-lab\20260527-202051-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic-windows`.

Evidence:

- Windows-only RPCS3 run on screen `1`, PadApi input, CPU affinity `0x0F`,
  frame/vblank `240/240`, and the expected 23-token macro.
- Load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; counts were
  path/debug/empty/unknown `1/0/0/0`, with no lower-row cursor or damaged-save
  markers.
- Visual gate reported `FIELD_LIKE_PRESENT`; first field-like screenshot was
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png` at `196s`.
- Manual screenshot review confirmed the Load list was `Save File 01 / Path to
  Tenuto / South Section / Ch. 1 Raindrops`, then clean Path-to-Tenuto field
  after strong dismiss, after `ls_left:1317`, at `210s`, `255s`, and `290s`.
- No prompt, corrupt overlay, load-menu stall, or likely-crashed overlay was
  visible in the reviewed field screenshots.
- Host checks were clean during the useful route window through the 300s sample.
  The final postrun grade was `moderate` only from `codex#21200` after the run
  was already stopped, so this is acceptable for route proof but not a speed
  comparison.
- `rpcs3.stderr.txt` contained only Qt/no-gui/media/painter warnings. Fatal scan
  found only the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `2,608`.
- Total observed DMA: `3,733.87 MB`.
- Offload fit mix: `spu-kernel-hle=1780`, `too-small=828`.
- Hot PCs: `0x451c` `2,151.72 MB`, `0x25cc` `1,582.16 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-field-clean-boundary-pinned`.
- Clean movement boundary only: `left1317` is clean, prior `left1318` remains
  fatal/corrupt.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the clean `left1317` boundary
  and no longer falls through to generic `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  record that integer left-only bisection is pinned at `left1317` clean /
  `left1318` fatal.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-down120-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1317;wait:1200;shot:left1317-immediate-check;ls_down:120;wait:1200;shot:left1317-down120-immediate-check;wait:10800;shot:left1317-down120-check;wait:45000;shot:left1317-down120-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Down120 Fatal

Question:

- After `left1317` passed once and `left1318` remained fatal, determine whether
  a small `ls_down:120` nudge after `left1317` can start an alternate
  battle-approach route.

Artifact:

- `debug-captures\windows-lab\20260527-204121-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-down120-longgate-diagnostic-windows`.

Evidence:

- Windows-only RPCS3 run on screen `1`, PadApi input, CPU affinity `0x0F`,
  frame/vblank `240/240`, and the expected 26-token macro.
- Load-target gate passed attempt `1` as `PATH_TO_TENUTO_PRESENT`; counts were
  path/debug/empty/unknown `1/0/0/0`, with no lower-row cursor or damaged-save
  markers.
- Visual gate reported `FIELD_LIKE_PRESENT`; first field-like screenshot was
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png` at `196s`.
- Manual screenshot review showed the pre-movement field was clean at `196s`.
  The immediate post-`left1317` screenshot at `199s` already showed the RPCS3
  likely-crashed banner and corrupt/frozen field, before `ls_down:120` could be
  trusted. The `201s`, `257s`, and `290s` screenshots stayed in that corrupt
  state.
- Host contention was clean across `6` snapshots.
- `rpcs3.stderr.txt` and `RPCS3.log` reported a PPU VM access violation reading
  `0x40` at roughly the immediate post-left window. This overrides byte-size
  field triage.

Counters:

- GPU probe records: `1,660`.
- Total observed DMA: `1,910.83 MB`.
- Offload fit mix: `spu-kernel-hle=936`, `too-small=724`.
- Hot PCs: `0x451c` `1,120.42 MB`, `0x25cc` `790.41 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-fatal-log`.
- `stack-regression`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-down120-vm40-corrupt-field`.
- `down120` is not proven because the crash/corruption was visible immediately
  after the `left1317` pulse.
- Not a stable `left1317` proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact
  `left1317-down120` fatal instead of falling back to generic loader-control.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  record `left1317` as mixed evidence: one clean pass, one fatal repeat under
  the down120 extension before down120 became meaningful.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-reproof-after-down120-fatal -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1317;wait:1200;shot:left1317-reproof-immediate-check;wait:10800;shot:left1317-reproof-check;wait:45000;shot:left1317-reproof-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Save-List Inventory After Left1317 Drift

Question:

- After repeated `left1317` attempts hit `Debug Save / Prologue`, inventory the
  settled Load-list rows without pressing save-slot `Cross`.

Artifact:

- `debug-captures\windows-lab\20260527-193933-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- Windows-only RPCS3 run on screen `1`, PadApi, CPU affinity `0x0F`,
  frame/vblank `240/240`, and 26-token no-slot-cross inventory macro.
- Host contention was clean across `5` snapshots.
- The run intentionally stopped at `MaxSeconds 165`.
- Manual screenshot review:
  - `screenshot-0130s-load-list-initial-after60.png`: `Save File 01 / Path to Tenuto / South Section / Ch. 1 Raindrops` selected.
  - `screenshot-0132s-load-list-after-down1.png`: cursor on `File does not exist`.
  - `screenshot-0133s-load-list-after-down2.png`: cursor on `Save File 03 / Path to Tenuto`.
  - `screenshot-0135s-load-list-after-down3.png`: cursor on `File does not exist`.
  - `screenshot-0136s-load-list-after-down4.png` through `screenshot-0140s-load-list-after-down6.png`: cursor on `Save File 05 / Path to Tenuto`.
- `rpcs3.stderr.txt` was `0` bytes. Fatal scan found only the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `1,370`.
- Total observed DMA: `1,396.13 MB`.
- Offload fit mix: `spu-kernel-hle=696`, `too-small=674`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-initial-path-rows`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- Refiner and skill wording now match the observed inventory: initial
  `Save File 01 / Path to Tenuto`, Down1 empty, Down2 `Save File 03 / Path`,
  Down3 empty, Down4+ `Save File 05 / Path`.
- `AGENTS.md` now says not to normalize the cursor with `Down`/`Up`; next proof
  is no-movement long-gate from the initial Path row before another `left1317`
  movement attempt.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Double-Dismiss Field Prompt

Question:

- After the single strongdismiss600 no-movement proof stayed on the Load UI,
  test whether a second delayed strong post-load `Cross` can prove clean field
  without adding movement.

Artifact:

- `debug-captures\windows-lab\20260527-144847-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-double-dismiss-longgate-diagnostic-windows`.

Evidence:

- The live load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; `screenshot-0081s-load-target-gate.png` selected
  the top Path-to-Tenuto row with no lower-row cursor marker.
- `screenshot-0176s-load-complete-90s.png` still showed the Load UI with
  `File does not exist` / `Load complete.`.
- Manual review confirmed `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`
  reached clean Path-to-Tenuto field with no prompt or corruption.
- The second delayed `Cross` then opened the field `Save game` prompt, visible
  from `screenshot-0215s-post-load-complete-second-strongdismiss600-18s.png`
  through `screenshot-0306s-double-strongdismiss600-very-late-check.png`.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like at `195s`, and no
  invalid screenshots after first field-like; manual review overrides this for
  the prompt-covered later frames.
- Host contention stayed clean across `5` snapshots.
- Fatal scan found only the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe recorded `2,856` rows and `4,000.26 MB` observed DMA.
- Hot PCs were `0x451c` (`2,524.03 MB`) and `0x25cc` (`1,476.23 MB`).
- Offload fit was `spu-kernel-hle=1858` / `too-small=998`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  overlap all stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-double-dismiss-field-prompt`.
- Clean no-movement field at `195s`, then prompt-covered field after the second
  delayed `Cross`.
- Not moving gameplay.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now excludes `battle-stock` route labels from
  generic 0x25cc shadow pattern-gap advice and recognizes this double-dismiss
  field-prompt state.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Load-Complete Stuck

Question:

- After the save-list inventory showed Path-to-Tenuto rows at the initial Load
  position, prove whether the strongdismiss600 no-movement long-gate route
  reaches clean field before adding movement again.

Artifact:

- `debug-captures\windows-lab\20260527-143406-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- The live load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; `screenshot-0081s-load-target-gate.png` showed the
  selected lower Path-to-Tenuto row.
- Manual review showed `screenshot-0176s-load-complete-90s.png` on
  `Error: Save data cannot be found`, then
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`,
  `screenshot-0241s-strongdismiss600-late-check.png`, and
  `screenshot-0286s-strongdismiss600-very-late-check.png` still on the Load UI
  with the `Load complete.` popup.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`, `12` wrong-window/other
  small screenshots, and failed the required field-like check by `260s`.
- Host contention stayed clean across `5` snapshots.
- Fatal scan found only the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe recorded `2,563` rows and `2,466.04 MB` observed DMA.
- Hot PCs were `0x451c` (`1,736.12 MB`) and `0x25cc` (`729.93 MB`).
- Offload fit was `spu-kernel-hle=1168` / `too-small=1395`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  overlap all stayed `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-loadcomplete-stuck`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this specific no-movement
  `Load complete` stuck state and blocks repeating the same single-dismiss
  macro.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-double-dismiss-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 300 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;cross:600;wait:18000;shot:post-load-complete-second-strongdismiss600-18s;wait:45000;shot:double-strongdismiss600-late-check;wait:45000;shot:double-strongdismiss600-very-late-check" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Cursor-Aware No-Movement Black-Gate

Question:

- After the cursor-aware load-target fix, can the same strongdismiss600
  no-movement route load Path to Tenuto cleanly before any `left1275` retry?

Artifact:

- `debug-captures\windows-lab\20260527-134709-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-cursoraware-windows`.

Evidence:

- The run intentionally used the same no-movement macro and cursor-aware
  `gate_load_target:60000` before any save-slot `Cross`.
- It aborted before pressing save-slot `Cross`; therefore no field, movement,
  or first-battle step was attempted.
- `load-target-gate-failed.txt` reported timeout at `140s` with last status
  `UNKNOWN_LOAD_TARGET`.
- `eternal-sonata-load-target-summary.md` recorded
  path/debug/unknown counts `0/0/20`; lower-row cursor markers `0`.
- Manual review of
  `screenshots\screenshot-0140s-load-target-gate-20.png` showed a black
  transition/overlay with live FPS counters, not the Load list.
- All `20` load-target gate screenshots were small black-overlay frames,
  from `screenshot-0082s-load-target-gate.png` through
  `screenshot-0140s-load-target-gate-20.png`.
- Host checks were clean across `3` snapshots.
- `rpcs3.stderr.txt` was small, and fatal scan found only the benign
  `Show fatal error hints: false` config line.

Counters:

- GPU probe records were route-invalid for speed because no save slot or field
  was reached.
- The summary still showed `0 B` promoted CPU/SPU-to-GPU replacement, direct
  RSX-local traffic, and indirect SPU-DMA/RSX-resource overlap.
- Hot repeated CPU/SPU DMA remained around `0x25cc` / `0x451c`, but this is
  analyzer evidence only and not a GPU migration result.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-cursoraware-black-gate`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this cursor-aware no-movement
  black gate as a title-to-Load timing failure, not a save restore or cursor
  normalization problem.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- The next action is a title-to-Load pre-gate timing diagnostic with explicit
  screenshots before the load-target gate, not a movement retry.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-blackgate;down:160;wait:900;shot:title-after-down160-blackgate;cross:120;wait:12000;shot:pregate-12s;wait:18000;shot:pregate-30s;wait:15000;shot:pregate-45s;wait:15000;shot:pregate-60s;gate_load_target:60000;shot:path-target-after-pregate-black-diagnostic" -MaxSeconds 210 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Title-To-Load Pre-Gate Debug Save Target

Question:

- Was the cursor-aware no-movement black-gate caused by timing, or is the
  current Load-list selection drifting away from Path to Tenuto?

Artifact:

- `debug-captures\windows-lab\20260527-140004-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic-windows`.

Evidence:

- `screenshot-0068s-title-settle-before-blackgate.png` showed the title menu.
- `screenshot-0070s-title-after-down160-blackgate.png` showed `LOAD`
  selected, so title `Down:160` still reaches the Load menu entry.
- `screenshot-0082s-pregate-12s.png`, `screenshot-0101s-pregate-30s.png`,
  `screenshot-0116s-pregate-45s.png`, and
  `screenshot-0132s-pregate-60s.png` were stable Load-list frames, not black
  transition frames.
- Manual review of `screenshot-0132s-load-target-gate.png` showed
  `Save File 01`, `Debug Save`, `Prologue`; Path to Tenuto was not selected.
- `load-target-gate-failed.txt` reported
  `DEBUG_SAVE_PROLOGUE_PRESENT` at `132s`.
- `eternal-sonata-load-target-summary.md` recorded
  path/debug/unknown counts `0/5/2`, lower-row cursor markers `0`.
- The macro aborted before save-slot `Cross`, so field, movement, and battle
  were never attempted.
- Host checks were clean across `3` snapshots.
- Fatal scan found only the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `1,069`.
- Total observed DMA: `1,131.37 MB`.
- Hot PCs: `0x451c` with `668.71 MB`; `0x25cc` with `462.66 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-debug-save-target`.
- The prior black-gate diagnosis is refined: waiting longer reaches the Load
  list, but the selected row is currently Debug Save / Prologue.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this as a save-list selection
  inventory problem instead of another black-gate timing run or save-restore
  job.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- The next action is a no-slot-cross inventory of the current save-list rows
  using repeated `Down` screenshots.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-inventory;down:160;wait:900;shot:title-after-down160-inventory;cross:120;wait:60000;shot:load-list-initial-after60;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;down:120;wait:900;shot:load-list-after-down3;down:120;wait:900;shot:load-list-after-down4;down:120;wait:900;shot:load-list-after-down5;down:120;wait:900;shot:load-list-after-down6" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Save-List Inventory After Pregate Debug Save Drift

Question:

- After the pre-gate diagnostic reported `DEBUG_SAVE_PROLOGUE_PRESENT`, inspect
  the actual Load-list rows without pressing a save slot, so the next route does
  not guess at cursor position.

Artifact:

- `debug-captures\windows-lab\20260527-141108-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- The macro stopped before save-slot `Cross`; no field, movement, or battle
  route was attempted.
- `screenshot-0068s-title-settle-before-inventory.png` showed the title menu,
  and `screenshot-0070s-title-after-down160-inventory.png` showed `LOAD`
  selected.
- Manual review of `screenshot-0131s-load-list-initial-after60.png` showed
  `Save File 01` and `Save File 02` are both `Path to Tenuto`, `South Section`,
  `Ch. 1 Raindrops`.
- `screenshot-0132s-load-list-after-down1.png` selected the second Path row.
- `screenshot-0134s-load-list-after-down2.png` and later Down screenshots moved
  the cursor onto `File does not exist` rows; no `Debug Save / Prologue` row was
  visible in the inventory run.
- The classifier was tightened after this review: empty slots now use a
  bright-text guard and are counted as `empty-load-slot` instead of being
  mistaken for the Debug Save exemplar. The inventory summary now reports
  path/debug/empty/unknown counts `4/0/3/2`.
- The full-run status remains `DAMAGED_SAVE_TARGET` only because later Down
  screenshots intentionally put the cursor on empty rows. The actionable route
  state is the initial post-Load-list screenshot: Path-to-Tenuto is already the
  usable row.
- Host external contention was clean across `5` snapshots; one host sample was
  moderate from RPCS3 CPU load only.
- `rpcs3.stderr.txt` contained only Qt/media warnings, and fatal scan found only
  the benign `Show fatal error hints: false` config line.

Counters:

- GPU probe records: `1,324`.
- Total observed DMA: `1,450.56 MB`.
- Hot PCs: `0x451c` with `787.82 MB`; `0x25cc` with `662.74 MB`.
- Offload fit `spu-kernel-hle=739` / `too-small=585`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-initial-path-rows`.
- The previous pregate Debug Save classification was not reproduced by the row
  inventory; the initial row is usable Path to Tenuto, while further `Down`
  inputs are harmful because they enter empty slots.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\classify_eternal_sonata_load_target.ps1` now has an empty-slot guard
  so empty Load-list rows do not count as `DEBUG_SAVE_PROLOGUE_PRESENT`.
- `tools\ps3_harness_refiner.ps1` now recognizes this inventory run as a
  resolved control and suggests the strongdismiss600 no-movement long-gate proof
  from the initial Path row, not generic loader-control.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1200 Clean Boundary

Question:

- After the `left1500` RSX FP CAL fatal and a title-to-Load reproof, retry the
  same strongdismiss600 base with `ls_left:1200` and immediate post-movement
  screenshots to determine whether the smaller movement is clean.

Artifact:

- `debug-captures\windows-lab\20260527-111249-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-longgate-diagnostic-windows`.

Evidence:

- `gate_load_target:60000` passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; load-target counts were path/debug/unknown `1/0/0`.
- `screenshot-0196s-post-load-complete-strongdismiss600-18s.png` reached clean
  Path-to-Tenuto field after the stronger `cross:600` load-complete dismiss.
- `screenshot-0200s-left1200-immediate-check.png` visibly moved Polka left away
  from the save point.
- `screenshot-0211s-left1200-check.png`,
  `screenshot-0257s-left1200-late-check.png`, and `screenshot-0290s.png` stayed
  field-clean by manual review.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like at `196s`, and
  `0` invalid screenshots after first field-like.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.
- Host contention summary was `moderate` / external `moderate` because one
  sample flagged `Codex#17044=15%`; this blocks any speed comparison from this
  run but does not invalidate route/visual proof.
- The lab stopped RPCS3 after `MaxSeconds 300`, expected after the requested
  late field screenshots were captured.

Counters:

- GPU probe records: `2,599`.
- Total observed DMA: `3,882.63 MB`.
- Hot PCs: `0x25cc` with `1,355` records / `2,183.96 MB`, and `0x451c` with
  `1,244` records / `1,698.67 MB`.
- Offload fit: `spu-kernel-hle=1894`, `too-small=705`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-field-clean`.
- Clean lower movement boundary after the `left1500` RSX FP CAL fatal.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this clean strongdismiss600
  `left1200` route boundary and no longer lets the stale 0x25cc shadow-pattern
  instrumentation lane outrank the newest route result.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1350-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1350;wait:1200;shot:left1350-immediate-check;wait:10800;shot:left1350-check;wait:45000;shot:left1350-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1350 Fatal Upper Boundary

Question:

- After banking `ls_left:1200` as the clean lower movement boundary, test the
  `ls_left:1350` midpoint on the same strongdismiss600 base with immediate
  post-movement screenshots.

Artifact:

- `debug-captures\windows-lab\20260527-113727-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1350-longgate-diagnostic-windows`.

Evidence:

- `gate_load_target:60000` passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; load-target counts were path/debug/unknown `1/0/0`.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` reached clean
  Path-to-Tenuto field before movement.
- `screenshot-0198s-left1350-immediate-check.png` already showed RPCS3's
  likely-crashed overlay with corrupt/frozen field visuals.
- `screenshot-0210s-left1350-check.png`,
  `screenshot-0255s-left1350-late-check.png`, and `screenshot-0290s.png`
  remained corrupt/frozen with near-zero guest CPU/RSX activity.
- Visual gate reported `FIELD_LIKE_PRESENT`, first field-like at `195s`, and
  `0` invalid screenshots after first field-like. Manual screenshot and log
  review override that byte-size triage for this rung.
- `rpcs3.stderr.txt` and `RPCS3.log:19043` reported
  `PPU[0x100000c] Thread () [0x002aedd0]` `VM: Access violation reading
  location 0x40 (unmapped memory)` at about `0:03:17.626653`.
- Host contention was clean across `6` snapshots.
- The lab stopped RPCS3 at `MaxSeconds 300` after the late corrupt screenshots
  were captured.

Counters:

- GPU probe records: `1,661`.
- Total observed DMA: `1,969.31 MB`.
- Hot PCs: `0x451c` with `1,154` records / `1,176.43 MB`, and `0x25cc` with
  `507` records / `792.88 MB`.
- Offload fit: `spu-kernel-hle=987`, `too-small=674`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-fatal-log`.
- `failed-visual-corruption`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1350-vm40-corrupt-field`.
- Fatal/corrupt upper movement boundary after the clean `left1200` proof.
- Not clean movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the strongdismiss600 `left1350`
  field-then-PPU-VM-access/corrupt screenshot failure and suggests shrinking the
  same base to `ls_left:1275` with immediate screenshots.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1275 Black-Gate Miss

Question:

- After `left1200` was clean and `left1350` was fatal/corrupt, test the
  midpoint `ls_left:1275` on the same strongdismiss600 base.

Artifact:

- `debug-captures\windows-lab\20260527-120107-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- The run never reached save-slot `Cross`, field, or the `ls_left:1275` token.
- `gate_load_target:60000` timed out as `UNKNOWN_LOAD_TARGET`.
- All `21` load-target polling screenshots from
  `screenshot-0081s-load-target-gate.png` through
  `screenshot-0141s-load-target-gate-21.png` were black-overlay frames by
  manual review and visual-gate classification.
- Load-target classifier counts were path/debug/unknown `0/0/21`.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.
- Host contention was clean across `3` snapshots.
- RPCS3 exited after the macro aborted before slot `Cross`, expected for this
  load-target gate failure.

Counters:

- GPU probe records: `1,185`.
- Total observed DMA: `1,151.32 MB`.
- Hot PCs: `0x451c` with `921` records / `745.21 MB`, and `0x25cc` with `264`
  records / `406.11 MB`.
- Offload fit: `too-small=630`, `spu-kernel-hle=555`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-black-gate`.
- Not field.
- Not movement: save-slot `Cross` and `ls_left:1275` were never sent.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this specific strongdismiss600
  `left1275` black-gate miss and no longer falls back to generic state-aware or
  old loader-control routes.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1275-blackgate" -MaxSeconds 150 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 5 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Target Reproof After Left1275 Black Gate

Question:

- The `ls_left:1275` midpoint never reached save-slot `Cross` because all
  load-target gate screenshots were black-overlay `UNKNOWN_LOAD_TARGET` frames.
  This run re-proves only the strongdismiss600 Path-to-Tenuto target before
  retrying movement.

Artifact:

- `debug-captures\windows-lab\20260527-121649-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-windows`.

Evidence:

- The macro intentionally stopped after:
  `wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1275-blackgate`.
- The live load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`.
- `eternal-sonata-load-target-summary.md` recorded path/debug/unknown
  counts `1/0/0`; the accepted crop was row `365` with Path-to-Tenuto diff
  `6.537` versus Debug Save diff `18.577`.
- Manual review of
  `screenshot-0082s-path-target-reproof-after-left1275-blackgate.png` showed
  the selected visible row as `Save File 04`, `Path to Tenuto`,
  `South Section`, `Ch. 1 Raindrops`.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.
- Host contention was clean across `7` snapshots.
- The lab stopped RPCS3 after `MaxSeconds 150`; this is expected for this
  intentionally short target proof because the target gate had already passed.

Counters:

- GPU probe records: `1,260`.
- Total observed DMA: `1,321.75 MB`.
- Hot PCs: `0x451c` with `925` records / `805.33 MB`, and `0x25cc` with `335`
  records / `516.42 MB`.
- Offload fit: `spu-kernel-hle=665`, `too-small=595`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-passed`.
- Target health repaired after the left1275 black-gate miss.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill status:

- No harness-code change was needed this round. The refiner already recognizes
  this passed target-only reproof as a resolved control.
- `AGENTS.md` now carries the same standing breadcrumb.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1275 Loading-Only Miss

Question:

- The target-only reproof after the `left1275` black-gate miss passed
  `PATH_TO_TENUTO_PRESENT`. This reran the same strongdismiss600
  `ls_left:1275` midpoint to see whether the route could reach field and
  accept the midpoint movement before any verifier, battle, HLE, RSX, GPU, or
  speed promotion.

Artifact:

- `debug-captures\windows-lab\20260527-122721-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- The load-target gate passed on attempt `1` with `PATH_TO_TENUTO_PRESENT`.
- `screenshot-0081s-load-target-gate.png` selected `Save File 01` /
  `Path to Tenuto`.
- `screenshot-0176s-load-complete-90s.png` showed the `Load complete`
  banner.
- After the strongdismiss600 post-load `Cross`, the run stayed on
  `Now Loading...` instead of field:
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`,
  `screenshot-0198s-left1275-immediate-check.png`,
  `screenshot-0210s-left1275-check.png`,
  `screenshot-0255s-left1275-late-check.png`, and `screenshot-0290s.png`.
- The `ls_left:1275` input was sent while the route was still loading, so it
  is not valid movement evidence.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; class counts included
  `loading-like-small-png=11` and `wrong-window-or-other-small-png=2`.
- Fatal scan found only the benign `Show fatal error hints: false` config
  line.
- Host contention was clean across `6` snapshots.
- Window-title FPS samples around `120 FPS` are invalid because the visible
  scene was `Now Loading...`, not field or gameplay.

Counters:

- GPU probe records: `2,627`.
- Total observed DMA: `3,401.09 MB`.
- Hot PCs: `0x25cc` with `1,637` records / `2,508.29 MB`, and `0x451c` with
  `990` records / `892.80 MB`.
- Offload fit: `spu-kernel-hle=2028`, `too-small=599`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-loading-only`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this loading-only left1275
  miss and no longer falls through to the stale generic state-aware command.
- The next action is a no-movement strongdismiss600 post-load stability reproof
  on the same base, not another `left1275` movement attempt.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 No-Movement Damaged-Save Target

Question:

- The previous `left1275` proof passed the load target but stayed off-field,
  so this run removed movement and tested whether the same strongdismiss600
  base could reach a stable Path-to-Tenuto field before another movement,
  verifier, battle, HLE, RSX, GPU, or speed attempt.

Artifact:

- `debug-captures\windows-lab\20260527-124423-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Initial live classifier output reported `PATH_TO_TENUTO_PRESENT`, but manual
  screenshot review showed this was unsafe.
- `screenshot-0081s-load-target-gate.png` selected a top-only Path-to-Tenuto
  row, `Save File 03`, with `Save file has been damaged` and
  `File does not exist` visible below it.
- `screenshot-0176s-load-complete-90s.png` showed
  `Error: Save data cannot be found`.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`,
  `screenshot-0241s-strongdismiss600-late-check.png`,
  `screenshot-0286s-strongdismiss600-very-late-check.png`, and the final
  automatic screenshots stayed in the Load UI with the damaged/missing save
  row. No field was reached.
- After the classifier repair, `eternal-sonata-load-target-summary.md` reports
  `DAMAGED_SAVE_TARGET`, with `11` top-only Path-to-Tenuto row matches and no
  adjacent lower Path row for those captures.
- The repaired classifier preserves known-good target cases: the clean
  `left1200` run still reports `PATH_TO_TENUTO_PRESENT` because it has Path
  rows at `190,365`, and the `left1275` target reproof still reports
  `PATH_TO_TENUTO_PRESENT` because the selected Path row is at `365`.
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT`; class counts were
  `wrong-window-or-other-small-png=12`.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.
- Host contention was `moderate` overall because the final sample crossed the
  host CPU estimate threshold, with external contention still clean. This run
  is not a speed claim either way.

Counters:

- GPU probe records: `2,588`.
- Total observed DMA: `2,868.77 MB`.
- Hot PCs: `0x451c` with `1,756` records / `1,590.81 MB`, and `0x25cc` with
  `832` records / `1,277.97 MB`.
- Offload fit: `spu-kernel-hle=1523`, `too-small=1065`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-damaged-save-target`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/Refiner updates:

- `tools\classify_eternal_sonata_load_target.ps1` now records all candidate
  Path/Debug rows and reports `DAMAGED_SAVE_TARGET` when Path-to-Tenuto appears
  only in the top candidate row with no adjacent lower Path row.
- `tools\windows_rpcs3_lab.ps1` now treats `DAMAGED_SAVE_TARGET` like
  `DEBUG_SAVE_PROLOGUE_PRESENT` / `MIXED_LOAD_TARGETS` and aborts before
  save-slot `Cross`.
- `tools\ps3_harness_refiner.ps1` recognizes this newest damaged-save target
  and no longer falls back to generic `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact action:

```powershell
# No automatic route rerun: restore or repair the Path-to-Tenuto save target, then run a target-only load-gate reproof under the DAMAGED_SAVE_TARGET guard before retrying no-movement stability or left1275.
```

## 2026-05-27 Damaged-Target Restore Reproof Still Damaged

Question:

- Does restoring the known Path-to-Tenuto checkpoint repair the selected
  strongdismiss600 load target enough to resume no-movement or `left1275`
  route work?

Artifacts:

- Backup before restore:
  `debug-captures\save-backups\BLUS3016100-before-damaged-target-restore-20260527-130850`.
- Restore source:
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`.
- Reproof run:
  `debug-captures\windows-lab\20260527-130917-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-damaged-target-restore-windows`.

Restore evidence:

- The live `BLUS3016100` save was backed up, then the checkpoint files
  `ICON0.PNG`, `PARAM.SFO`, `PREVIEW0`, and `SAVEDATA` were copied back to the
  RPCS3 savedata directory.
- Post-restore hashes matched the checkpoint manifest:
  - `ICON0.PNG`:
    `17A53E68FE8D4B857746235FDDA00784FC023672C43DD74E0665FC7AA34C8729`.
  - `PARAM.SFO`:
    `F9A81489223525F42B913056F9CFF26EFA4F27BB425C9FBAF84FB922816FD1A3`.
  - `PREVIEW0`:
    `D7A9E99CDB1B010AD30DDEC040B0F2A3CEEE0CE21942BE6CA9D4E2A4BAD1386E`.
  - `SAVEDATA`:
    `05F76EAC35647BD719618A94648789C511CC47667CD6A7EF6DB302438F9EA49A`.

Reproof command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-damaged-target-restore -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-damaged-target-restore" -MaxSeconds 150 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 5 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Evidence:

- The target-only reproof stayed on the Load list and aborted before save-slot
  `Cross`; the guard did not enter the damaged slot.
- `eternal-sonata-load-target-summary.md` reported `DAMAGED_SAVE_TARGET`.
- All `19` load-target screenshots matched a top-only Path-to-Tenuto row at
  `y=190`, with no adjacent lower Path row.
- Manual review of
  `screenshots\screenshot-0141s-load-target-gate-19.png` showed `Save File 01`
  / `Path to Tenuto`, but the selected row said `File does not exist`.
- Host checks were clean across `3` snapshots, `rpcs3.stderr.txt` was empty,
  and fatal scan found only the benign `Show fatal error hints: false` config
  line.

Counters:

- GPU probe records: `1,157`.
- Total observed DMA: `1,246.79 MB`.
- Hot PCs: `0x451c` with `796` records / `692.33 MB`, and `0x25cc` with
  `361` records / `554.46 MB`.
- Offload fit: `spu-kernel-hle=625`, `too-small=532`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-damaged-target-restore-still-damaged`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/Refiner updates:

- `tools\windows_rpcs3_lab.ps1` now parses load-target exception text so the
  live gate marker can preserve `DAMAGED_SAVE_TARGET` instead of degrading it
  to `UNKNOWN_LOAD_TARGET`.
- `tools\ps3_harness_refiner.ps1` now recognizes this post-restore target-only
  miss and refuses another automatic route rerun.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact action:

```powershell
# No automatic route rerun: the restored checkpoint still selects DAMAGED_SAVE_TARGET. Repair selected-row/cursor targeting or save-list layout, then run only a target gate until PATH_TO_TENUTO_PRESENT is clean.
```

## 2026-05-27 Cursor-Aware Load-Target Correction

Question:

- Is the post-restore top-only Path-to-Tenuto row truly damaged, or is the
  crop classifier confusing persistent top preview text with the actual selected
  save-list cursor?

Artifact:

- `debug-captures\windows-lab\20260527-132938-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-cursor-damaged-target-diagnostic-windows`.

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-cursor-damaged-target-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;shot:title-after-down160;cross:120;wait:12000;shot:load-list-initial;wait:5000;shot:load-list-stable;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;up:120;wait:900;shot:load-list-after-up1;up:120;wait:900;shot:load-list-after-up2" -MaxSeconds 120 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

Evidence:

- The macro did not press `Cross` on any save slot.
- Manual review:
  - `screenshot-0082s-load-list-initial.png` showed top `Save File 01` /
    `Path to Tenuto` selected.
  - `screenshot-0089s-load-list-after-down1.png` showed the cursor moved to the
    first lower `File does not exist` row while the top Path-to-Tenuto preview
    stayed visible.
  - `screenshot-0091s-load-list-after-down2.png` showed the cursor moved to the
    second lower `File does not exist` row while the top preview still stayed
    visible.
- This proves top-preview Path text can be stale relative to cursor selection.
- The classifier now records lower-row cursor markers:
  - current cursor diagnostic: `DAMAGED_SAVE_TARGET`, but only because lower
    cursor rows were detected at `365` / `535`.
  - prior target-only post-restore reproof:
    `20260527-130917-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-damaged-target-restore-windows`
    reclassifies as `PATH_TO_TENUTO_PRESENT` with `0` lower-row cursor markers.
- Host checks were clean across `5` snapshots. `rpcs3.stderr.txt` was empty,
  and fatal scan found only the benign `Show fatal error hints: false` config
  line.

Counters:

- GPU probe records: `956`.
- Total observed DMA: `1,021.11 MB`.
- Hot PCs: `0x451c` and `0x25cc`; this remains route-invalid cursor tooling.
- Offload fit: `spu-kernel-hle=520`, `too-small=436`.
- Promoted CPU/SPU-to-GPU replacement: `0 B`.
- Direct RSX-local scout traffic: `0 B`.
- Indirect SPU-DMA/RSX-resource overlap: `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-cursor-diagnostic-lower-empty-rows`.
- Supersedes the prior overbroad top-only `DAMAGED_SAVE_TARGET` read for the
  post-restore target-only reproof.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Harness/Refiner updates:

- `tools\classify_eternal_sonata_load_target.ps1` now combines Path/Debug crop
  matching with lower-row cursor-marker detection.
- `tools\ps3_harness_refiner.ps1` recognizes the cursor diagnostic and points
  back to the same strongdismiss600 no-movement proof under the cursor-aware
  gate.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 StrongDismiss600 Left1500 Pre-Gate Fatal

Question:

- The restored strongdismiss600 `ls_left:1800` retry reached clean field and
  then exited after movement. This round shrank the movement midpoint to
  `ls_left:1500` and added an immediate post-movement screenshot to see whether
  the route could survive long enough to prove movement before any verifier,
  battle, HLE, RSX, GPU, or speed promotion.

Artifact:

- `debug-captures\windows-lab\20260526-210213-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-longgate-diagnostic-windows`.

Evidence:

- The run never reached save-slot `Cross` or `ls_left:1500`.
- The live load-target gate timed out after `60000ms` with status
  `UNKNOWN_LOAD_TARGET`.
- All `21` load-target screenshots were `black-overlay-small-png`.
- Manual screenshot review of
  `screenshots\screenshot-0081s-load-target-gate.png` showed the RPCS3
  `The PS3 application has likely crashed` overlay, not a Load list or field.
- `rpcs3.stderr.txt` was `118` bytes and reported:
  `PPU[0x1000000] Thread (main_thread) [0x0007dccc]: VM: Access violation reading location 0x4 (unmapped memory)`.
- `RPCS3.log` reported the same access violation at `0:01:10.847869`.
- Host checks were clean across prelaunch, postlaunch, and postrun snapshots;
  no RPCS3/RPCSX/build process remained after the run.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`, with no field-like
  screenshot at or before `260s`.

Counters:

- GPU probe records `472`.
- Total observed DMA `476.21 MB`.
- Hot PCs: `0x451c` with `353` records / `292.09 MB`; `0x25cc` with `119`
  records / `184.12 MB`.
- Offload fit `too-small=244` / `spu-kernel-hle=228`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `failed-fatal-log`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-pregate-fatal-0x4`.
- Not save-target proof.
- Not movement: the macro aborted before save-slot `Cross`.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes this left1500 pre-gate fatal
  and no longer falls back to generic state-aware load-target routing.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- Suggested next command is a target-only health reproof, not movement:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1500-fatal -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1500-fatal" -MaxSeconds 150 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 5 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 StrongDismiss600 Target Reproof After Left1500 Fatal

Question:

- The previous `ls_left:1500` shrink crashed before save-slot `Cross`, so this
  target-only run checked whether the restored strongdismiss600 Path-to-Tenuto
  load target was still healthy before retrying movement.

Artifact:

- `debug-captures\windows-lab\20260526-211010-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1500-fatal-windows`.

Evidence:

- The macro intentionally stopped after:
  `wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1500-fatal`.
- The live load-target gate passed after attempt `1` with
  `PATH_TO_TENUTO_PRESENT`.
- `eternal-sonata-load-target-summary.md` recorded
  `path-to-tenuto=1`, `debug-save-prologue=0`, `unknown=0`.
- `screenshot-0081s-load-target-gate.png` matched the Path-to-Tenuto exemplar
  with crop diff `0.000` versus Debug Save diff `17.758`.
- `screenshot-0082s-path-target-reproof-after-left1500-fatal.png` is the final
  target-health screenshot.
- Host checks were clean across `7` snapshots.
- `rpcs3.stderr.txt` was `0` bytes, and no actionable fatal/access/assertion or
  device-lost signature was found in the stderr/log scan.
- The lab stopped RPCS3 after `MaxSeconds 150`; this is expected for this
  intentionally short target proof because the target gate had already passed.

Counters:

- GPU probe records `1,254`.
- Total observed DMA `1,279.64 MB`.
- Hot PCs: `0x451c` with `924` records / `771.78 MB`; `0x25cc` with `330`
  records / `507.86 MB`.
- Offload fit `spu-kernel-hle=633` / `too-small=621`.
- RSX-local traffic `0`; indirect SPU-DMA/RSX-resource overlap `0`;
  promoted CPU/SPU-to-GPU replacement `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1500-fatal-passed`.
- Target health repaired after the left1500 pre-gate fatal.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the passed target-only reproof
  as a resolved control and suggests the same strongdismiss600 `ls_left:1500`
  movement proof with the immediate screenshot, instead of generic
  loader-control/state-aware fallback.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same reusable rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1500-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1500;wait:1200;shot:left1500-immediate-check;wait:10800;shot:left1500-check;wait:45000;shot:left1500-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-26 StrongDismiss600 Left1200 Route Volatility

Question:

- After `ls_left:1500` reached a clean field and then hit RSX `Unimplemented
  FP CAL` with corrupt post-left visuals, shrink the same strongdismiss600 base
  to `ls_left:1200` and keep immediate screenshots. If the load target drifts,
  re-prove target health before movement.

Artifacts:

- `debug-captures\windows-lab\20260526-213735-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-longgate-diagnostic-windows`.
- `debug-captures\save-backups\BLUS3016100-before-left1200-debug-save-refresh-20260526-214454`.
- `debug-captures\windows-lab\20260526-214507-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1200-debug-save-windows`.
- `debug-captures\windows-lab\20260526-215015-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-longgate-diagnostic-rerun-after-target-reproof-windows`.

Evidence:

- The first `left1200` shrink aborted before save-slot `Cross`: all `20`
  load-target screenshots were the Load UI with `Debug Save` / `Prologue`.
  `eternal-sonata-load-target-summary.md` reported
  `DEBUG_SAVE_PROLOGUE_PRESENT`, path/debug/unknown `0/20/0`.
- Manual review of `screenshot-0081s-load-target-gate.png` confirmed the wrong
  row: `Save File 01`, `Debug Save`, `Prologue`, not Path to Tenuto.
- Visual gate status was `NO_FIELD_LIKE_SCREENSHOT`.
- `rpcs3.stderr.txt` was `0` bytes, fatal scan was clean except the benign
  `Show fatal error hints: false` config line, and host checks were clean.
- The live RPCS3 save and the checkpoint `SAVEDATA`/`PARAM.SFO` hashes matched,
  but the live UI still presented the wrong row. I still backed up the live
  save and refreshed it from
  `save-checkpoints\eternal-sonata\thor-20260515-190657\BLUS3016100`.
- The target-only reproof after the refresh passed
  `PATH_TO_TENUTO_PRESENT` on attempt `1`; classifier counts were
  path/debug/unknown `1/0/0`, `rpcs3.stderr.txt` was `0` bytes, fatal scan was
  clean, and host checks were clean across `7` snapshots.
- The immediate movement retry after target reproof did not reach the Load
  list. The gate saw story/cutscene/nonfield frames, aborted as
  `UNKNOWN_LOAD_TARGET` after `7` screenshots, and never pressed save-slot
  `Cross` or `ls_left:1200`.
- Manual review of `screenshot-0081s-load-target-gate.png` and
  `screenshot-0096s-load-target-gate-7.png` from that retry showed the Eternal
  Sonata story scene, not the Load list. The byte visual gate called early
  cutscene frames field-like, so manual review overrides byte-size triage here.
- The rerun's `rpcs3.stderr.txt` was `0` bytes, fatal scan was clean except
  `Show fatal error hints: false`, and host checks were clean.

Counters:

- First `left1200` wrong-target run: GPU probe records `1,185`, total observed
  DMA `1,274.91 MB`, hot PCs `0x451c` `762.23 MB` and `0x25cc` `512.68 MB`.
- Target-only reproof: GPU probe records `1,258`, total observed DMA
  `1,340.04 MB`, hot PCs `0x451c` `780.43 MB` and `0x25cc` `559.61 MB`.
- Movement retry route-miss: GPU probe records `769`, total observed DMA
  `1,054.90 MB`, hot PCs `0x451c` `594.93 MB` and `0x25cc` `459.97 MB`.
- In all three runs, promoted CPU/SPU-to-GPU replacement, direct RSX-local
  scout traffic, and indirect SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-debug-save-target`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1200-debug-save-passed`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-title-route-miss-after-target-reproof`.
- Not field.
- Not movement: no run pressed save-slot `Cross` into Path to Tenuto and then
  reached the `ls_left:1200` token.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the left1200 Debug Save
  blocker, the target-only reproof pass, and the follow-up title/cutscene route
  miss after target health is restored.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md`
  carry the same rule.
- The refiner now stops movement retries and suggests only the Down160
  title-to-Load diagnostic with explicit title/down/cross/pre-gate screenshots.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-title-to-load-down160-state-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:12000;shot:post-title-cross-down160;up:120;wait:200;up:120;wait:200;up:120;wait:200;up:120;wait:200;up:120;wait:600;shot:pre-load-target-gate-down160;gate_load_target:30000" -MaxSeconds 140 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0
```

## 2026-05-27 StrongDismiss600 Title-to-Load Down160 Reproof

Question:

- After the restored strongdismiss600 `ls_left:1200` movement retry entered
  story/cutscene frames before the Load-list gate, prove whether the title
  `Down:160` route still selects `Load` and reaches the Path-to-Tenuto row.

Artifact:

- `debug-captures\windows-lab\20260527-105159-cpu4-title-to-load-down160-state-diagnostic-windows-windows`.

Evidence:

- The diagnostic used explicit screenshots for title settle, after `Down:160`,
  after title `Cross`, and pre-load-target gate.
- Manual screenshots showed `screenshot-0069s-title-settle.png` on the title
  menu with `New Game` selected, `screenshot-0071s-title-after-down160.png`
  with `Load` selected, and `screenshot-0083s-post-title-cross-down160.png` /
  `screenshot-0087s-pre-load-target-gate-down160.png` on `Save File 01`,
  `Path to Tenuto`, `South Section`, `Ch. 1 Raindrops`.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`.
- `eternal-sonata-load-target-summary.md` recorded
  path/debug/unknown counts `3/0/2`; the two unknown entries were the title-menu
  screenshots before the Load list was opened.
- Host contention was clean across `6` snapshots.
- `rpcs3.stderr.txt` was `0` bytes, and fatal scan found only the benign
  `Show fatal error hints: false` config line.
- The lab stopped RPCS3 after `MaxSeconds 140`, expected for this intentionally
  short diagnostic after the target gate had passed.

Counters:

- GPU probe was intentionally off for this route-state diagnostic, so there is
  no new DMA/offload/RSX-local counter evidence.
- Window-title samples ranged from `38.33` to `53.73` FPS while on title/load UI;
  these are route telemetry only, not a speed result.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-title-to-load-down160-reproved-load`.
- Title/load-list health only.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes a passed Down160 title-to-Load
  diagnostic after the prior strongdismiss600 `left1200` route miss and resumes
  the same strongdismiss600 `ls_left:1200` movement proof instead of falling back
  to generic `titleload-down160-pollgated-directleft200`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1200-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1200;wait:1200;shot:left1200-immediate-check;wait:10800;shot:left1200-check;wait:45000;shot:left1200-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 Current Resume Note After Goal Update

- Current best recent boundary:
  `20260527-162159-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`
  is `valid-field-triage` / `route-tooling` /
  `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-field-clean`.
- It is a clean movement boundary under the same strongdismiss600 route, not
  speed, not GPU migration, not first-battle proof, and not 200%.
- Goal rule updated: matched CPU-pressure reductions are bankable as
  `stackable-cpu-pressure` or `windows-micro-win`, but they remain separate
  from the 200% moving-gameplay gate.
- Refiner validation now points at `left1312` and no longer falls back to
  generic `stateaware-one-step`.
- Next exact Windows-only action:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1312-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1312;wait:1200;shot:left1312-immediate-check;wait:10800;shot:left1312-check;wait:45000;shot:left1312-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Repeated Debug-Save After Target Reproof

Question:

- After the target-only reproof passed `PATH_TO_TENUTO_PRESENT`, determine
  whether the same strongdismiss600 `ls_left:1317` movement proof can start from
  the correct Path-to-Tenuto row.

Artifact:

- `debug-captures\windows-lab\20260527-191936-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 23-token macro.
- The load-target gate aborted before save-slot `Cross` at `81s` with
  `DEBUG_SAVE_PROLOGUE_PRESENT`.
- Manual screenshot review of `screenshot-0081s-load-target-gate.png` showed
  `Save File 01 / Debug Save / Prologue` plus damaged-save text.
- `left1317` movement was never sent.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`, as expected for a pre-slot
  abort.
- `rpcs3.stderr.txt` was `0` bytes. Fatal scan found no actionable access
  violation, device-lost, assertion, or crash line for this route failure.
- Host checks were clean before and after launch; postrun was `moderate` only
  because `codex#21200=15%` appeared after the macro had already aborted.

Counters:

- GPU probe records: `625`.
- Total observed DMA: `631.02 MB`.
- Offload fit mix: `too-small=319`, `spu-kernel-hle=306`.
- Hot PCs: `0x451c` `385.51 MB`, `0x25cc` `245.50 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-debug-save-after-target-reproof`.
- Not field.
- Not movement.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now detects repeated `left1317` Debug Save
  selection after a clean target-only reproof and stops the reproof-to-movement
  loop.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` now
  require save-list inventory / selected-row repair before another `left1317`
  movement attempt.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-inventory;down:160;wait:900;shot:title-after-down160-inventory;cross:120;wait:60000;shot:load-list-initial-after60;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;down:120;wait:900;shot:load-list-after-down3;down:120;wait:900;shot:load-list-after-down4;down:120;wait:900;shot:load-list-after-down5;down:120;wait:900;shot:load-list-after-down6" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1317 Reproof After Down120 Fatal

Question:

- After `left1317-down120` fatal/corrupt evidence, determine whether plain
  `left1317` is itself unstable or whether the extra down movement is the
  failure trigger.

Artifact:

- `debug-captures\windows-lab\20260527-210215-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-reproof-after-down120-fatal-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 23-token macro.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; path/debug/empty/unknown counts were `1/0/0/0`.
- Field was reached at `196s`.
- Manual screenshot review confirmed a valid Path-to-Tenuto load target, clean
  field at `196s`, and clean accepted `left1317` movement at `199s`, `210s`,
  `256s`, and `290s`.
- Visual summary reported `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0196s-post-load-complete-strongdismiss600-18s.png`, and zero
  invalid screenshots after first field-like output.
- Host contention was clean across `6` snapshots.
- `rpcs3.stderr.txt` contained only benign Qt/no-GUI/media/painter warnings.
  Fatal scan found no actionable access violation, device-lost, assertion, or
  crash line for this run.

Counters:

- GPU probe records: `2601`.
- Total observed DMA: `3733.62 MB`.
- Offload fit mix: `spu-kernel-hle=1737`, `too-small=864`.
- Hot PCs: `0x451c` `2164.11 MB`, `0x25cc` `1569.52 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-reproof-after-down120-fatal-passed`.
- Plain `left1317` is clean single-axis movement.
- `left1317-down120` remains failed; do not repeat that exact combo.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now recognizes the clean plain `left1317`
  reproof after the `down120` fatal and recommends the lower-bound
  `left1316-down120` diagnostic instead of generic routing or another
  `left1317-down120` retry.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down120-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1316;wait:1200;shot:left1316-immediate-check;ls_down:120;wait:1200;shot:left1316-down120-immediate-check;wait:10800;shot:left1316-down120-check;wait:45000;shot:left1316-down120-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1316 Down120 Loading-Only Failure

Question:

- After plain `left1317` was re-proven clean and `left1317-down120` remained
  failed, test whether the lower-bound `left1316-down120` route can reach field
  and accept the smaller alternate movement.

Artifact:

- `debug-captures\windows-lab\20260527-213640-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down120-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 26-token macro.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; path/debug/empty/unknown counts were `1/0/0/0`.
- Manual screenshot review showed `screenshot-0176s-load-complete-90s.png` on
  the Load UI with the `Load complete` overlay, then
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` through
  `screenshot-0290s.png` stayed on `Now Loading...`.
- The visual gate reported `NO_FIELD_LIKE_SCREENSHOT`, with `12`
  loading-like screenshots and zero field-like frames at or before `260s`.
- Host contention was clean across `6` snapshots.
- `rpcs3.stderr.txt` was empty. Fatal scan found no actionable VM access
  violation, device-lost, assertion, or crash line; matched log lines were
  benign config/export/save-load messages.

Counters:

- GPU probe records: `2650`.
- Total observed DMA: `3352.68 MB`.
- Offload fit mix: `spu-kernel-hle=1981`, `too-small=669`.
- Hot PCs: `0x25cc` `2400.80 MB`, `0x451c` `951.88 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down120-loading-only`.
- Movement was not tested because field was never reached.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now detects this specific
  `left1316-down120` loading-only failure and recommends a no-movement
  strongdismiss600 load-stability reproof instead of generic
  `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-27 StrongDismiss600 Left1316 Down60 Window Lost After Field

Question:

- After the title-to-Load target repair restored `PATH_TO_TENUTO_PRESENT`, retry
  the same `left1316-down60` diagnostic and verify whether the smaller down
  nudge can move toward the battle trigger without breaking field visuals.

Artifact:

- `debug-captures\windows-lab\20260527-234240-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 26-token macro.
- The load-target gate passed on attempt `1` with
  `PATH_TO_TENUTO_PRESENT`; path/debug/empty/unknown counts were `1/0/0/0`.
- `screenshot-0081s-load-target-gate.png` showed Path-to-Tenuto rows and no
  Debug Save or damaged-save marker.
- `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` showed clean
  Path-to-Tenuto field.
- After `ls_left:1316`, `screenshot-0199s-left1316-immediate-check.png` was a
  wrong-window browser capture, and later screenshots were skipped because the
  game window/process was gone before `down60` could be verified.
- Visual gate reported `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`.
- `rpcs3.stderr.txt` was empty. Targeted log scan found no access violation,
  device lost, assertion, crash, segfault, verification failure, or unimplemented
  line.

Counters:

- GPU probe records: `1672`.
- Total observed DMA: `1951.36 MB`.
- Offload fit mix: `spu-kernel-hle=974`, `too-small=698`.
- Hot PCs: `0x451c` `1113.92 MB`, `0x25cc` `837.44 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-window-lost-after-field`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1316-down60-window-lost-after-field`.
- Clean field was reached, but movement was not counted because the window was
  lost immediately after `ls_left:1316` and `down60` was not verified.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` now detects this exact window-loss pattern
  and recommends backing off to `left1275-down60` instead of repeating
  `left1316-down60` or falling back to generic `stateaware-one-step`.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` and `AGENTS.md` carry
  the same rule.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-down60-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;ls_down:60;wait:1200;shot:left1275-down60-immediate-check;wait:10800;shot:left1275-down60-check;wait:45000;shot:left1275-down60-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 StrongDismiss600 Left1275 Down60 Debug-Save Target

Question:

- After `left1316-down60` reached clean field but lost the window after
  `ls_left:1316`, back off to `left1275-down60` and verify whether a smaller
  left/down movement reaches field cleanly.

Artifact:

- `debug-captures\windows-lab\20260528-000227-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-down60-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 26-token macro.
- Prelaunch and postlaunch host checks were clean; postrun was moderate because
  Codex used CPU after the early abort.
- The load-target gate failed at `81s` on attempt `1` with
  `DEBUG_SAVE_PROLOGUE_PRESENT`.
- Manual screenshot review of `screenshot-0081s-load-target-gate.png` showed
  `Save File 01 / Debug Save / Prologue` and damaged-save rows. No slot `Cross`
  was sent after the gate failure.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`; there was only one
  load-target screenshot and no field/movement checkpoint.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `626`.
- Total observed DMA: `624.81 MB`.
- Offload fit mix: `too-small=323`, `spu-kernel-hle=303`.
- Hot PCs: `0x451c` `410.18 MB`, `0x25cc` `214.63 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-debug-save-target`.
- Movement was not tested because the run aborted before save-slot `Cross`.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` already detects this as
  `left1275-debug-save-target` and recommends save-list inventory with repeated
  `Down` screenshots and no slot `Cross`, instead of generic routing or save
  normalization.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-inventory;down:160;wait:900;shot:title-after-down160-inventory;cross:120;wait:60000;shot:load-list-initial-after60;down:120;wait:900;shot:load-list-after-down1;down:120;wait:900;shot:load-list-after-down2;down:120;wait:900;shot:load-list-after-down3;down:120;wait:900;shot:load-list-after-down4;down:120;wait:900;shot:load-list-after-down5;down:120;wait:900;shot:load-list-after-down6" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 StrongDismiss600 Save-List Inventory Initial Path Row

Question:

- After `left1275-down60` aborted on `Save File 01 / Debug Save / Prologue`,
  inventory the current Load-list rows without pressing a save slot so the next
  route does not blindly repeat cursor drift.

Artifact:

- `debug-captures\windows-lab\20260528-002231-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-WindowsVisualGate Off`, and the intended
  26-token no-slot macro.
- Host contention was clean across `5` snapshots.
- The run captured `9` screenshots: title settle, title after `Down160`, initial
  Load list after 60s, and six repeated `Down` row screenshots.
- Manual screenshot review of `screenshot-0130s-load-list-initial-after60.png`
  showed `Save File 01 / Path to Tenuto / South Section / Ch. 1 Raindrops`.
- Manual review of the later `Down` screenshots showed the cursor moving onto
  lower rows where the visible top Path preview can remain stale while selected
  lower rows are empty.
- `tools\classify_eternal_sonata_load_target.ps1` reported
  `DAMAGED_SAVE_TARGET` for the whole inventory: path-to-tenuto `3`,
  empty-load-slot `4`, unknown `2`, lower-row cursor markers `6`, damaged-save
  text markers `0`, and damaged-target guard `2`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1370`.
- Total observed DMA: `1415.86 MB`.
- Offload fit mix: `spu-kernel-hle=709`, `too-small=661`.
- Hot PCs: `0x451c` `889.25 MB`, `0x25cc` `526.61 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-initial-path-rows`.
- Initial Load-list row is Path-to-Tenuto; later `Down` inputs create stale
  preview/cursor drift and should not be used for normalization.
- Not field proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/Skill updates:

- `tools\ps3_harness_refiner.ps1` wording now records this as initial Path row
  plus stale preview/cursor drift, not as reliable alternate Path rows.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` carries the same
  wording.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 StrongDismiss600 No-Movement Route Reproof After Save Inventory

Question:

- After the save-list inventory showed the initial Load-list row is
  Path-to-Tenuto and save-list `Down` creates stale preview/cursor drift, rerun
  the no-movement long-gate from the initial Path row with no save-list
  normalization.

Artifact:

- `debug-captures\windows-lab\20260528-004219-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 20-token no-movement macro.
- The load-target gate passed on attempt `1` with `PATH_TO_TENUTO_PRESENT`:
  path-to-tenuto `1`, debug-save-prologue `0`, empty-load-slot `0`, unknown
  `0`, lower-row cursor markers `0`, and damaged-save text markers `0`.
- Manual review of `screenshot-0081s-load-target-gate.png` confirmed
  Path-to-Tenuto rows on the Load screen.
- Visual gate reported `FIELD_LIKE_PRESENT`; first field-like screenshot was
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` at `195s`.
- Manual review of `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`
  and `screenshot-0287s-strongdismiss600-very-late-check.png` confirmed clean
  Path-to-Tenuto field visuals.
- The visual gate saw `10` field-like large PNGs and `0` invalid screenshots
  after the first field-like frame; the required field-like frame before `260s`
  passed.
- Host contention was clean for prelaunch, postlaunch, and the in-run samples at
  `287s` and `300s`; postrun was moderate because Codex used CPU after RPCS3
  had already been stopped.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `2618`.
- Total observed DMA: `3745.25 MB`.
- Offload fit mix: `spu-kernel-hle=1787`, `too-small=831`.
- Hot PCs: `0x451c` `2065.50 MB`, `0x25cc` `1679.75 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`.
- This banks the repaired no-movement route base only.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now detects this as
  `nomove-field-clean` and recommends resuming the same strongdismiss600 base
  with `ls_left:1275` and immediate screenshots before verifier, battle, HLE,
  RSX, GPU, or speed work.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 StrongDismiss600 Left1275 Black Load-Target Gate

Question:

- After the repaired no-movement route base reached clean Path-to-Tenuto field,
  rerun the same strongdismiss600 route with `ls_left:1275` and immediate
  movement screenshots.

Artifact:

- `debug-captures\windows-lab\20260528-010220-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, and the intended 23-token movement macro.
- Host contention was clean for prelaunch, postlaunch, and postrun.
- The load-target gate never reached a readable Load list: all `16` polling
  screenshots from `81s` through `140s` were `black-overlay-small-png` and
  classified `UNKNOWN_LOAD_TARGET`.
- The gate timed out at `140s`; the macro aborted before save-slot `Cross`.
- Manual review of `screenshot-0140s-load-target-gate-16.png` confirmed a black
  overlay with the RPCS3 FPS/perf overlay still alive.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT` with `16` black-overlay frames
  and no field-like screenshot before `260s`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1190`.
- Total observed DMA: `1154.76 MB`.
- Offload fit mix: `too-small=654`, `spu-kernel-hle=536`.
- Hot PCs: `0x451c` `784.99 MB`, `0x25cc` `369.77 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-black-gate`.
- Movement was not tested because the run aborted before save-slot `Cross`.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` detects this as
  `left1275-black-gate` and recommends re-proving only the strongdismiss600
  Path-to-Tenuto target before rerunning `left1275`.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;shot:path-target-reproof-after-left1275-blackgate" -MaxSeconds 150 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 5 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 StrongDismiss600 Target Reproof Hit Debug Save

Question:

- After `left1275` aborted on black-overlay load-target gate frames, re-prove
  only the strongdismiss600 Path-to-Tenuto target before any movement, speed,
  HLE, RSX, or GPU work.

Artifact:

- `debug-captures\windows-lab\20260528-012228-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-WindowsVisualGate Off`, and the intended
  7-token target-only macro.
- Host contention was clean for prelaunch, postlaunch, and postrun.
- The load-target gate failed at `81s` with `DEBUG_SAVE_PROLOGUE_PRESENT`:
  path-to-tenuto `0`, debug-save-prologue `1`, empty-load-slot `0`, unknown
  `0`, lower-row cursor markers `0`, and damaged-save text markers `0`.
- The macro aborted before save-slot `Cross`.
- Manual review of `screenshot-0081s-load-target-gate.png` confirmed
  `Save File 01 / Debug Save / Prologue`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `626`.
- Total observed DMA: `615.20 MB`.
- Offload fit mix: `too-small=333`, `spu-kernel-hle=293`.
- Hot PCs: `0x451c` `390.86 MB`, `0x25cc` `224.34 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-debug-save`.
- Movement was not tested because the run aborted before save-slot `Cross`.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` blocks speed/HLE/RSX experiments
  and recommends a polling load-target-gated repair route that requires
  `PATH_TO_TENUTO_PRESENT` before continuing.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 215 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;up:80;wait:300;cross:120;wait:1200;cross:120;wait:35000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 155 -ScreenshotMaxCount 10
```

## 2026-05-28 Initial-Row No-Movement Reproof Black Gate

Question:

- After inventory re-proved the initial Load-list row is Path to Tenuto, rerun
  the no-movement long-gate proof from that initial row with no save-list
  normalization.

Artifact:

- `debug-captures\windows-lab\20260528-022230-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate CleanAfterField`, and the intended 20-token no-movement
  macro.
- Host contention was clean for prelaunch, postlaunch, and postrun.
- The load-target gate never reached a readable Load list: all `16` polling
  screenshots from `81s` through `140s` were `black-overlay-small-png` and
  classified `UNKNOWN_LOAD_TARGET`.
- The gate timed out at `140s`; the macro aborted before save-slot `Cross`.
- Manual review of `screenshot-0140s-load-target-gate-16.png` confirmed a black
  overlay with the RPCS3 FPS/perf overlay still alive.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`; no field-like frame existed
  before `260s`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1191`.
- Total observed DMA: `1156.19 MB`.
- Offload fit mix: `too-small=642`, `spu-kernel-hle=549`.
- Hot PCs: `0x451c` `799.33 MB`, `0x25cc` `356.86 MB`.
- PUTLLC16 analyzer records: `43`; detected PUTLLC16 patterns `8`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `nomove-initial-path-row-black-gate`.
- No save slot was pressed; field, movement, Options/menu, and battle were not
  tested.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/skill update:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact strongdismiss600
  no-movement black-gate shape and recommends the title-to-Load pre-gate black
  diagnostic instead of falling back to the stale generic state-aware polling
  macro.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` now documents that
  both cursor-aware and initial-row no-movement black gates should route to the
  timed title-to-Load diagnostic.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-blackgate;down:160;wait:900;shot:title-after-down160-blackgate;cross:120;wait:12000;shot:pregate-12s;wait:18000;shot:pregate-30s;wait:15000;shot:pregate-45s;wait:15000;shot:pregate-60s;gate_load_target:60000;shot:path-target-after-pregate-black-diagnostic" -MaxSeconds 210 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Refiner Loop Guard And Save-List Inventory Reproof

Question:

- The refiner was recommending the same state-aware polling repair that just
  failed on `DEBUG_SAVE_PROLOGUE_PRESENT`. Add a loop guard, then run a
  non-destructive save-list inventory with no save-slot `Cross`.

Code/tooling:

- `tools\ps3_harness_refiner.ps1` now detects
  `stateaware-loadtarget-pollgated` plus `DEBUG_SAVE_PROLOGUE_PRESENT` and
  recommends save-list inventory instead of the identical polling macro.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` now carries the
  same standing rule.
- Verified by rerunning `tools\ps3_harness_refiner.ps1 -MaxRuns 8`; it emitted
  `stateaware-pollgated-debug-save-repeat` and selected the inventory command.

Artifact:

- `debug-captures\windows-lab\20260528-020512-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate Off`, and the intended 26-token inventory macro.
- Host contention was clean for prelaunch, postlaunch, in-run samples at
  `140s`/`150s`, and postrun.
- The macro took title screenshots, selected Load with `down:160`/`cross:120`,
  waited `60s`, then took Load-list row screenshots while pressing `Down`.
- Manual review of `screenshot-0130s-load-list-initial-after60.png` confirmed
  the initial selected row is `Save File 01 / Path to Tenuto / South Section /
  Ch.1 Raindrops`.
- Manual review of `screenshot-0132s-load-list-after-down1.png` and
  `screenshot-0140s-load-list-after-down6.png` confirmed `Down` moves the
  cursor onto lower `File does not exist` rows while the Path-to-Tenuto preview
  can remain stale.
- The classifier reported `DAMAGED_SAVE_TARGET` because of cursor drift, not a
  Debug Save row: path-to-tenuto `3`, debug-save-prologue `0`,
  empty-load-slot `4`, unknown `2`, lower-row cursor markers `6`, damaged-save
  text markers `0`, and damaged target guard `2`.
- No save-slot `Cross` was sent. No field, movement, Options/menu, or battle
  proof was attempted.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1364`.
- Total observed DMA: `1432.11 MB`.
- Offload fit mix: `spu-kernel-hle=706`, `too-small=658`.
- Hot PCs: `0x451c` `845.03 MB`, `0x25cc` `587.08 MB`.
- PUTLLC16 analyzer records: `43`; detected PUTLLC16 patterns `8`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `save-list-inventory-initial-path-rows`.
- The repeated `Debug Save / Prologue` loop is now routed to inventory/row
  repair instead of an identical polling macro.
- Not field proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` detects the inventory as
  `save-list-inventory-initial-path-rows` and recommends resuming no-movement
  long-gate proof from the initial Path row, without save-list `Down/Up`
  normalization.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Polling Repair Still Hit Debug Save

Question:

- After the target-only reproof hit `Debug Save / Prologue`, test the
  polling load-target-gated repair route and refuse to continue unless the
  gate sees `PATH_TO_TENUTO_PRESENT`.

Artifact:

- `debug-captures\windows-lab\20260528-014240-cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, and the intended 41-token repair macro.
- Host contention was clean for prelaunch, postlaunch, and postrun.
- The load-target gate failed at `63s` with `DEBUG_SAVE_PROLOGUE_PRESENT`:
  path-to-tenuto `0`, debug-save-prologue `1`, empty-load-slot `0`, unknown
  `0`, lower-row cursor markers `0`, and damaged-save text markers `1`.
- Manual review of `screenshot-0063s-load-target-gate.png` confirmed
  `Save File 01 / Debug Save / Prologue` with damaged-save rows.
- The macro aborted before save-slot `Cross`; `ls_left:200` was never reached.
- Visual gate reported `NO_FIELD_LIKE_SCREENSHOT`; the only screenshot was the
  load-target gate frame, so no field-like frame existed before `215s`.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `440`.
- Total observed DMA: `449.05 MB`.
- Offload fit mix: `spu-kernel-hle=234`, `too-small=206`.
- Hot PCs: `0x451c` `225.39 MB`, `0x25cc` `223.66 MB`.
- Reservation-loop verify attempts/completed: `95875/26484`; success/failure
  `15233/11251`, unexpected `4662`, dirty multi-slot observations `2`.
- Lane-2 verify completed cleanly: `7614/7614`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-debug-save`.
- Movement was not tested because the run aborted before save-slot `Cross`.
- Not field proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` still blocks speed/HLE/RSX
  experiments and recommends the polling load-target-gated route until
  `PATH_TO_TENUTO_PRESENT` is observed.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 215 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;up:80;wait:300;cross:120;wait:1200;cross:120;wait:35000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 155 -ScreenshotMaxCount 10
```

## 2026-05-28 Title-Load Pre-Gate Damaged Target Diagnostic

Question:

- After the no-movement proof black-overlayed through the whole load-target
  gate, verify whether title `Down:160` enters the Load list late, enters the
  wrong title route, or settles on the wrong save row before slot `Cross`.

Artifact:

- `debug-captures\windows-lab\20260528-024313-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate Off`, and the intended 16-token timed diagnostic macro.
- Host contention was clean for prelaunch, postlaunch, and postrun.
- Manual review of `screenshot-0068s-title-settle-before-blackgate.png`
  confirmed the title menu was visible before input.
- Manual review of `screenshot-0069s-title-after-down160-blackgate.png`
  confirmed `down:160` selected `LOAD`, not `NEW GAME` or `OPTIONS`.
- Manual review of `screenshot-0082s-pregate-12s.png` and
  `screenshot-0132s-load-target-gate.png` confirmed the Load screen was stable
  by 12s and selected lower `Save File 05 / Path to Tenuto / South Section /
  Ch.1 Raindrops`, with damaged-save rows above it.
- The load-target classifier reported `DAMAGED_SAVE_TARGET`: path-to-tenuto
  `5`, debug-save-prologue `0`, empty-load-slot `0`, unknown `2`, lower-row
  cursor markers `5`, damaged-save text markers `5`, and damaged target guard
  `5`.
- The macro aborted before save-slot `Cross`; no field, movement, Options/menu,
  or battle proof was attempted.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1105`.
- Total observed DMA: `1,109.04 MB`.
- Offload fit mix: `too-small=554`, `spu-kernel-hle=551`.
- Hot PCs: `0x451c` `701.32 MB`, `0x25cc` `407.72 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-load-target-gate`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-damaged-save-target`.
- The prior black gate was not persistent black timing; this run exposed lower
  save-row selection with damaged rows above it.
- Not field proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner/skill update:

- `tools\ps3_harness_refiner.ps1` now recognizes this exact title-to-Load
  pre-gate `DAMAGED_SAVE_TARGET` shape and recommends the stable Load-list
  Up-repair target diagnostic instead of the stale generic polling movement
  macro.
- `.agents\skills\ps3-continual-harness-refiner\SKILL.md` now records the same
  standing rule.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now emits
  `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-damaged-save-target`
  and selects only the target-repair command below.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-settle-before-uprepair;down:160;wait:900;shot:title-after-down160-uprepair;cross:120;wait:30000;shot:load-list-before-uprepair;up:100;wait:700;shot:load-list-uprepair-up1;up:100;wait:700;shot:load-list-uprepair-up2;up:100;wait:700;shot:load-list-uprepair-up3;up:100;wait:700;shot:load-list-uprepair-up4;up:100;wait:700;shot:load-list-uprepair-up5;gate_load_target:30000;shot:path-target-after-uprepair" -MaxSeconds 165 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Load-List Up-Repair Target Passed

Question:

- After the title-to-Load diagnostic selected lower `Save File 05 / Path to
  Tenuto` with damaged rows above it, test whether bounded `Up` repair from a
  stable Load list restores the top `Save File 01 / Path to Tenuto` target
  before any save-slot `Cross`.

Artifact:

- `debug-captures\windows-lab\20260528-030231-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate Off`, and the intended 25-token target-only repair macro.
- Host contention was clean for prelaunch, postlaunch, in-run samples at
  `112s`/`120s`/`150s`, and postrun.
- Manual review of `screenshot-0068s-title-settle-before-uprepair.png`
  confirmed the title menu was visible before input.
- Manual review of `screenshot-0069s-title-after-down160-uprepair.png`
  confirmed `down:160` selected `LOAD`.
- Manual review of `screenshot-0107s-load-target-gate.png` confirmed selected
  top `Save File 01 / Path to Tenuto / South Section / Ch.1 Raindrops` with
  lower rows showing `File does not exist`; damaged-save rows were gone.
- The load-target classifier reported `PATH_TO_TENUTO_PRESENT` on the first
  gate attempt: path-to-tenuto `7`, debug-save-prologue `0`, empty-load-slot
  `0`, unknown `2`, lower-row cursor markers `0`, and damaged-save text
  markers `0`.
- The run intentionally did not press the save slot. No field, movement,
  Options/menu, or battle proof was attempted.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `1372`.
- Total observed DMA: `1,408.09 MB`.
- Offload fit mix: `spu-kernel-hle=707`, `too-small=665`.
- Hot PCs: `0x451c` `867.16 MB`, `0x25cc` `540.94 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `route-tooling`.
- `target-selection-repair`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-passed`.
- This restores the top Path-to-Tenuto target only.
- Not field proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects the strongdismiss600
  no-movement long-gate stability proof before any `left1275`, battle, HLE,
  RSX, GPU, or speed work.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Left1275 Loading-Only Rerun

Question:

- After the repaired no-movement base reached field again, test whether the
  same strongdismiss600 route with `ls_left:1275` still reaches field and
  produces clean immediate/late movement screenshots.

Artifact:

- `debug-captures\windows-lab\20260528-034311-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate CleanAfterField`, and the intended left1275 long-gate
  macro.
- The load-target classifier passed `PATH_TO_TENUTO_PRESENT` on attempt 1 at
  `81s`: path-to-tenuto `1`, debug-save-prologue `0`, empty-load-slot `0`,
  unknown `0`, lower-row cursor markers `0`, and damaged-save text markers
  `0`.
- Manual review of `screenshot-0255s-left1275-late-check.png` confirmed the
  late post-left frame was still `Now Loading...`, not field.
- The visual gate reported `NO_FIELD_LIKE_SCREENSHOT`: no field-like screenshot
  at or before `260s`, class counts `loading-like-small-png=11` and
  `wrong-window-or-other-small-png=2`.
- Window title samples showed about `120 FPS` on the loading screen; this is
  invalid for speed claims because the field visual gate failed.
- Host contention was clean during in-run samples at `256s`, `270s`, and
  `300s`; the overall summary was moderate due postrun Codex CPU.
- `rpcs3.stderr.txt` was `0` bytes. Targeted fatal/log scan found no access
  violation, device-lost, assertion, crash, segfault, verification failure, or
  unimplemented line.

Counters:

- GPU probe records: `2651`.
- Total observed DMA: `3,372.21 MB`.
- Offload fit mix: `spu-kernel-hle=1979`, `too-small=672`.
- Hot PCs: `0x25cc` `2,424.75 MB`, `0x451c` `947.46 MB`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `loading-only`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-loading-only`.
- Not field proof.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects the strongdismiss600
  no-movement long-gate stability proof again before any `left1275`, battle,
  HLE, RSX, GPU, or speed work.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;wait:45000;shot:strongdismiss600-late-check;wait:45000;shot:strongdismiss600-very-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Clean No-Movement Route Reproof After Left1275 Loading Failure

Question:

- After `left1275` passed the load target but stayed on `Now Loading...`,
  re-prove that the strongdismiss600 base route still reaches and holds the
  Path-to-Tenuto field without movement input.

Artifact:

- `debug-captures\windows-lab\20260528-040209-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate CleanAfterField`, and the intended no-movement long-gate
  macro.
- The load-target classifier passed `PATH_TO_TENUTO_PRESENT` on attempt 1 at
  `81s`: path-to-tenuto `1`, debug-save-prologue `0`, empty-load-slot `0`,
  unknown `0`, lower-row cursor markers `0`, damaged-save text markers `0`,
  and `Top path only=True`.
- The visual gate reported `FIELD_LIKE_PRESENT`: first field-like screenshot
  `screenshot-0195s-post-load-complete-strongdismiss600-18s.png` at `195s`
  (`2.50 MB`), field-like screenshots through `286s+`, and `0` invalid
  screenshots after first field-like output.
- Manual review of `screenshot-0195s-post-load-complete-strongdismiss600-18s.png`
  and `screenshot-0286s-strongdismiss600-very-late-check.png` confirmed clean
  Path-to-Tenuto field visuals, not loading, menu, or wrong-window output.
- Host contention summary was clean for all `5` snapshots.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Log scan found no
  access violation, device-lost crash, assertion crash, segfault, verification
  failure, or unimplemented fatal; the remaining early RSX shader diagnostics
  were non-fatal and field visuals stayed valid.

Counters:

- GPU probe records: `2619`.
- Total observed DMA: `3,740.05 MB`.
- Offload fit mix: `spu-kernel-hle=1786`, `too-small=833`.
- Hot PCs: `0x451c` `2,118.37 MB`, `0x25cc` `1,621.68 MB`.
- Largest single job: `10.97 MB` at `0x451c`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-field-clean`.
- This revalidates the route base after the loading-only `left1275` failure.
- Not movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects the same
  strongdismiss600 base with `ls_left:1275` immediate/late screenshots. This is
  route repair, not speed.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:600;wait:18000;shot:post-load-complete-strongdismiss600-18s;ls_left:1275;wait:1200;shot:left1275-immediate-check;wait:10800;shot:left1275-check;wait:45000;shot:left1275-late-check" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 9 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## 2026-05-28 Left1275 Field-Like Fatal Retry

Question:

- After a clean no-movement route-base reproof, retry the same strongdismiss600
  base with `ls_left:1275` and immediate/late screenshots.

Artifact:

- `debug-captures\windows-lab\20260528-042238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.

Evidence:

- Screen placement used `-WindowsGameScreen 1`, PadApi input, CPU affinity
  `0x0F`, frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  `-WindowsVisualGate CleanAfterField`, and the intended 23-token `left1275`
  macro.
- The load-target classifier passed `PATH_TO_TENUTO_PRESENT` on attempt 1 at
  `81s`: path-to-tenuto `1`, debug-save-prologue `0`, empty-load-slot `0`,
  unknown `0`, lower-row cursor markers `0`, damaged-save text markers `0`,
  and `Top path only=True`.
- The visual gate reported `FIELD_LIKE_PRESENT`: first field-like screenshot
  at `195s`, `11` field-like large PNGs, `0` invalid screenshots after first
  field-like output, and field-like frames through `290s`.
- Manual review of `screenshot-0199s-left1275-immediate-check.png` and
  `screenshot-0255s-left1275-late-check.png` showed the RPCS3 crash overlay
  plus corrupted field output after the movement input.
- `rpcs3.stderr.txt` was `108` bytes and reported
  `PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation reading
  location 0x40`.
- The same fatal appears in `RPCS3.log`; it overrides the field-like visual
  gate result.
- In-run host samples at `256s`, `270s`, and `300s` were clean; overall host
  summary was moderate only because postrun Codex CPU was `15.7%`.

Counters:

- GPU probe records: `1664`.
- Total observed DMA: `1,942.53 MB`.
- Offload fit mix: `spu-kernel-hle=936`, `too-small=728`.
- Hot PCs: `0x451c` `1,158.16 MB`, `0x25cc` `784.37 MB`.
- Largest single job: `21.58 MB` at `0x451c`.
- Promoted CPU/SPU-to-GPU replacement, direct RSX-local traffic, and indirect
  SPU-DMA/RSX-resource overlap stayed `0 B`.

Classification:

- `failed-fatal-log`.
- `route-tooling`.
- `crash-overlay`.
- `corrupt-field`.
- `hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-fatal-0x002aedd0`.
- Not valid movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now selects a no-movement
  loader/control with `CleanAfterField` before adding movement again.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

## 2026-05-28 Loader-Control Left200x2 Non-Field Failure

Question:

- After the clean `left200` route proof, add exactly one more tiny
  state-aware left pulse and require `CleanAfterField`.

Artifact:

- `debug-captures\windows-lab\20260528-052421-cpu4-loader-control-left200x2-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  two `ls_left:200` pulses, `-MaxSeconds 215`, screenshots every `10s`, and
  screenshots starting at `110s`.
- The lab wrapper again reported RPCS3 moved to `\\.\DISPLAY2` while launched
  with `--game-screen 1`; captured screenshots were valid RPCS3 output.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: `16` screenshots were
  classified `cutscene-or-nonfield-small-png`, first field-like was none, and
  required field-like at or before `160s` failed.
- Manual review of `screenshot-0117s.png`, `screenshot-0138s.png`, and
  `screenshot-0210s.png` showed blue/starry non-field output, not the
  Path-to-Tenuto field. There was no crash overlay and no field corruption
  evidence because the route never reached field.
- Window-title samples stayed around `29.91 FPS` after the first screenshot;
  this is diagnostic only and invalid for speed claims because the requested
  field visual gate failed.
- In-run host samples were clean at `149s`, `152s`, `180s`, and `210s`;
  aggregate host summary was moderate because postrun Codex CPU was `19.4%`.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled during postrun log analysis after RPCS3 had exited and
  paths were written. The wrapper PowerShell was killed, then
  `tools\check_eternal_sonata_windows_visual_gate.ps1` and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were run manually against the
  finished artifact. No RPCS3/RPCSX process remained active.

Counters:

- Reservation-loop candidate probe records: `1765`.
- Reservation-loop dynamic probe records: `1765`.
- Reservation-loop wait probe records: `1841`.
- Reservation-loop wait-PC probe records: `106734`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `539`.
- Max reads observed: `179619`.
- These counters are not promotion evidence because the field visual gate
  failed.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `cutscene-or-nonfield-frames`.
- `loader-control-left200x2-nonfield`.
- Not valid movement proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to back off from the
  latest non-field/cutscene route and re-prove the `loader-control-left200x2`
  boundary with `CleanAfterField` before adding diagonal movement or HLE/GPU
  fast mode.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-confirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## 2026-05-28 Loader-Control Left200x2 Confirmation

Question:

- After the previous `left200x2` run produced blue/starry non-field frames,
  re-run the exact two-pulse route and require `CleanAfterField`.

Artifact:

- `debug-captures\windows-lab\20260528-054511-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  two `ls_left:200` pulses, `-MaxSeconds 215`, screenshots every `10s`, and
  screenshots starting at `110s`.
- Host checks were clean in-run at prelaunch, postlaunch, `149s`, `152s`,
  `180s`, and `210s`. Aggregate host summary was moderate only because postrun
  Codex CPU was `20.9%`.
- Visual gate passed `FIELD_LIKE_PRESENT`: first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), all `16` screenshots
  classified `field-like-large-png` through `210s`, `0` invalid screenshots
  after first field-like, and field-like at-or-before `160s` passed.
- Manual review of `screenshot-0117s.png`, `screenshot-0138s.png`, and
  `screenshot-0210s.png` confirmed the Path-to-Tenuto field before and after
  the second left pulse. This specifically clears the prior blue/starry
  non-field failure for the same route boundary.
- Window-title/FPS samples during field output ranged roughly from the high
  `20s` to upper `30s`, so this is not a speed proof and not a 200% candidate.
- `rpcs3.stderr.txt` and `rpcs3.stdout.txt` were `0` bytes. Targeted `rg`
  scan found no `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal
  error, or assertion-failed hit. Only the normal `Show fatal error hints:
  false` config line matched the fatal string.
- The wrapper stalled during postrun log analysis after RPCS3 had exited and
  paths were written. The wrapper PowerShell was killed, then
  `tools\check_eternal_sonata_windows_visual_gate.ps1` and
  `tools\ps3_harness_refiner.ps1 -MaxRuns 8` were run manually against the
  finished artifact. No RPCS3/RPCSX process remained active.

Counters:

- Reservation-loop candidate probe records: `1573`.
- Reservation-loop dynamic probe records: `1573`.
- Reservation-loop wait probe records: `1695`.
- Reservation-loop wait-PC probe records: `88724`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `211493`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-left200x2-confirmed-field`.
- Valid small movement boundary proof for the two-pulse route.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to extend the newest
  valid `loader-control-left200x2` route by exactly one tiny diagonal
  micro-pulse with `CleanAfterField`; lane-2 HLE/GPU dry-runs remain blocked.

Next exact command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## 2026-05-28 Loader-Control Left200x2 Reproof Fatal/Black Regression

Question:

- After the TopSlot route miss, re-prove the last clean
  `loader-control-left200x2` boundary with `CleanAfterField` before extending
  movement again.

Artifact:

- `debug-captures\windows-lab\20260528-074420-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  two `ls_left:200` pulses, `-MaxSeconds 215`, screenshots every `10s`, and
  screenshots starting at `110s`.
- Host contention was clean at prelaunch, postlaunch, `149s`, `152s`,
  `180s`, `210s`, and postrun: `7` clean snapshots, external contention
  clean.
- The harness moved RPCS3 to `\\.\DISPLAY2` while launched with
  `--game-screen 1`.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: all `16` screenshots from
  `117s` through `210s` were `black-overlay-small-png`, each `34924` bytes.
  There was no field-like screenshot at or before `160s`, none at or after
  `210s`, and `0` field-like screenshots total.
- Manual review of `screenshot-0117s.png` confirmed black output with only
  the RPCS3 overlay/title visible, not the Path-to-Tenuto field.
- Window-title samples reported live RPCS3 output at `36.67 FPS`, but those
  samples are invalid for speed because the scene was black and the run hit a
  fatal device-lost log.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `790` bytes and
  reported `VK_ERROR_DEVICE_LOST` with a device fault write address and stack
  frames in `vk::wait_for_event` / `vk::die_with_error`.
- Targeted fatal scan found a real `RPCS3.log` hit at line `83874`:
  `Assertion Failed! Vulkan API call failed with unrecoverable error: Device
  lost ... (VK_ERROR_DEVICE_LOST)`. The normal `Show fatal error hints: false`
  config line was also present.
- RPCS3 was stopped at the `215s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `720`.
- MFC wait probe records: `787`.
- MFC wait-PC probe records: `38275`.
- Reservation-loop command probe records: `787`.
- Reservation-loop verify probe records: `787`.
- Reservation-loop verify lane records: `1890`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `242`.
- Max reads observed: `137694`.
- Reservation verify records included nonzero failure/read-failure/unexpected
  counts, and all counters are invalid for promotion because the visual gate
  and fatal-log gate failed.

Classification:

- `failed-fatal-log`.
- `failed-visual-gate`.
- `black-overlay-small-png`.
- `loader-control-left200x2-reproof-regression`.
- Not valid field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says the latest run had
  fatal/crash log evidence and must not be extended. It recommends re-proving
  the newest clean `loader-control-left200x2` boundary with `CleanAfterField`
  before adding another pulse.

## 2026-05-28 Loader-Control Left200x2 Reconfirm Loading-Stuck

Question:

- After the previous left200x2 reproof hit black frames plus device lost,
  reconfirm the newest clean left200x2 boundary before any extension.

Artifact:

- `debug-captures\windows-lab\20260528-080430-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  two `ls_left:200` pulses, `-MaxSeconds 215`, screenshots every `10s`, and
  screenshots starting at `110s`.
- Host contention was clean at prelaunch, postlaunch, `149s`, `152s`,
  `180s`, `210s`, and postrun: `7` clean snapshots, external contention
  clean.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: all `16` screenshots from
  `117s` through `210s` were `loading-like-small-png`, roughly `116-118 KB`.
  There was no field-like screenshot at or before `160s`, none at or after
  `210s`, and `0` field-like screenshots total.
- Manual review of `screenshot-0117s.png` confirmed `Now Loading...` with
  overlay, not the Path-to-Tenuto field. Late screenshots stayed in the same
  loading-like class.
- Window-title samples reported about `119.89-120.32 FPS`, but these are
  invalid for speed because the run never reached the field visual gate.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were `0` bytes. Targeted fatal
  scan found no real `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal, or
  assertion line. Only the normal `Show fatal error hints: false` config line
  matched the fatal string.
- RPCS3 stopped at the `215s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `1782`.
- MFC wait probe records: `1864`.
- MFC wait-PC probe records: `106541`.
- Reservation-loop command probe records: `1864`.
- Reservation-loop verify probe records: `1864`.
- Reservation-loop verify lane records: `5087`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `493`.
- Max reads observed: `110157`.
- Reservation verify records included nonzero failure/read-failure/unexpected
  counts, and all counters are invalid for promotion because the field visual
  gate failed.

Classification:

- `failed-visual-gate`.
- `loading-like-small-png`.
- `loader-control-left200x2-reconfirm-loading-stuck`.
- Not valid field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to use the newest
  valid-field run as the route base and add only one small state-aware movement
  step with `CleanAfterField`.

## 2026-05-28 State-Aware One-Step Field Reset

Question:

- After the left200x2 reconfirm stayed on loading, return to the newest
  valid-field base and run only the small state-aware one-step field reset
  before any loader-control or battle-route extension.

Artifact:

- `debug-captures\windows-lab\20260528-082422-cpu4-stateaware-one-step-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  the harness-provided state-aware macro, `-MaxSeconds 120`, screenshots every
  `15s`, screenshots starting at `15s`, and max screenshot count `6`.
- Host checks were clean at prelaunch, postlaunch, and `133s`. Postrun host
  summary was moderate only because Codex CPU was sampled at `19.8%` after
  RPCS3 had stopped.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate passed for this short reset: `3` screenshots, all
  `field-like-large-png`, first field-like screenshot
  `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like at-or-before
  `160s`, and `0` invalid screenshots after first field-like.
- Manual review of `screenshot-0117s.png` confirmed the Path-to-Tenuto field,
  not loading, black output, cutscene, or wrong-window output.
- Window-title samples were live (`33.31 FPS` at `117s`, `32.73 FPS` at
  `133s`), but this is route/field reset evidence only, not a speed proof.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were `0` bytes. Targeted fatal
  scan found no real `VM: Access`, access violation, `VK_ERROR_DEVICE_LOST`,
  device-lost, segfault, verification-failed, unimplemented syscall, fatal, or
  assertion line. Only the normal `Show fatal error hints: false` config line
  matched the fatal string.
- RPCS3 stopped at the `120s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `1025`.
- MFC wait probe records: `1104`.
- MFC wait-PC probe records: `55567`.
- Reservation-loop command probe records: `1104`.
- Reservation-loop verify probe records: `1104`.
- Reservation-loop verify lane records: `2651`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `132961`.
- Reservation verify records included nonzero failure/read-failure/unexpected
  counts, so these counters are route-triage only and not HLE/GPU promotion
  evidence.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `state-aware-one-step-field-reset`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says this clean state-aware
  field reset resolves the immediate loader-control/loading/fatal detour. Do
  not rerun the same field proof; isolate TopSlot post-field movement with a
  left-only diagnostic before another full `BattleRoute` retry.

## 2026-05-28 TopSlot Left-Only Diagnostic Fatal

Question:

- After the clean state-aware field reset, isolate TopSlot post-field movement
  with the left-only diagnostic before another full `BattleRoute` retry.

Artifact:

- `debug-captures\windows-lab\20260528-084504-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  host contention gate `ExternalFail`, `-WindowsVisualGate CleanAfterField`,
  `-WindowsVisualGateFieldSeconds 160`, the TopSlot macro with
  `ls_left:2600`, `-MaxSeconds 240`, screenshots every `20s`, screenshots
  starting at `110s`, and host samples every `30s`.
- Host checks were clean at prelaunch, postlaunch, `212s`, and `240s`.
  Postrun host gate failed only because Codex was sampled as a hot non-run
  process after RPCS3 stopped; this is not speed evidence either way.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate passed byte/color triage: `10` field-like screenshots, first
  field-like `screenshot-0117s-accepted-field-check.png` at `117s`
  (`2.50 MB`), field-like at-or-before `160s`, field-like at-or-after
  `220s`, and `0` invalid screenshots after first field-like.
- Manual review of `screenshot-0117s-accepted-field-check.png` confirmed a
  clean Path-to-Tenuto field before movement.
- Manual review of `screenshot-0166s-left2600-check.png` showed a visible
  crash overlay (`The PS3 application has likely crashed`) and a corrupted
  field after `ls_left:2600`.
- Window-title samples were live (`37.79 FPS` at `117s`, then roughly
  `29-31 FPS` after movement), but they are invalid for speed because the run
  hit a real fatal log and visual corruption after movement.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `108` bytes and
  reported `PPU[0x100000c] Thread () [0x002aedd0]: VM: Access violation
  reading location 0x40 (unmapped memory)`.
- Targeted fatal scan found the same real `RPCS3.log` hit at line `98792`.
  The normal `Show fatal error hints: false` config line was also present.
- RPCS3 stopped at the `240s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `872`.
- MFC wait probe records: `958`.
- MFC wait-PC probe records: `47650`.
- Reservation-loop command probe records: `958`.
- Reservation-loop verify probe records: `958`.
- Reservation-loop verify lane records: `2311`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `144738`.
- Reservation verify records included nonzero failure/read-failure/unexpected
  counts, and all counters are invalid for promotion because the fatal-log gate
  failed.

Classification:

- `failed-fatal-log`.
- `route-tooling`.
- `topslot-left2600-crash-overlay`.
- Not valid movement proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says the latest run had
  fatal/crash log evidence and must not be extended. It recommends a
  no-movement loader/control run with `CleanAfterField` before adding
  movement.

## 2026-05-28 Loader-Control No-Movement Reproof Clean

Question:

- After the `ls_left:2600` fatal/corrupt TopSlot diagnostic, re-prove the
  baseline loader/control route before adding any movement.

Artifact:

- `debug-captures\windows-lab\20260528-090516-cpu4-loader-control-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  `-MaxSeconds 190`, screenshots every `10s`, screenshots starting at `120s`,
  and `-ScreenshotMaxCount 8`.
- Host checks were clean at prelaunch, postlaunch, `133s`, `150s`, `180s`,
  and postrun.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate passed byte/color triage: `10` field-like screenshots, first
  field-like `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like
  at-or-before `160s`, required count `3`, and `0` invalid screenshots after
  first field-like.
- Manual review of `screenshot-0190s.png` confirmed a clean Path-to-Tenuto
  field with no crash overlay or obvious corruption. FPS overlay was roughly
  `30 FPS`; this is not a speed result.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `444` bytes and
  contained only Qt parser/media/painter warnings, not a VM access or Vulkan
  device-lost failure.
- Targeted fatal scan found no real crash/access/device-lost/assertion/
  verification failure. The only `fatal` match was the normal
  `Show fatal error hints: false` config line.
- RPCS3 stopped at the `190s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `1489`.
- MFC wait probe records: `1610`.
- MFC wait-PC probe records: `84265`.
- Reservation-loop command probe records: `1610`.
- Reservation-loop verify probe records: `1610`.
- Reservation-loop verify lane records: `3998`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `242`.
- Max reads observed: `216365`.
- Reservation verify records still included nonzero failure/read-failure/
  unexpected counts, so these counters remain route-triage only and are not
  HLE/GPU promotion evidence.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-clean-after-field`.
- Not movement proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to use this newest
  valid loader-control as the route base, then add exactly one small
  state-aware `left200` movement step with `CleanAfterField`. Lane-2 HLE/GPU
  dry-runs remain blocked.

## 2026-05-28 Loader-Control Left200 Small Movement Clean

Question:

- From the clean `20260528-090516` loader-control base, add one small
  `ls_left:200` step and verify the field stays clean afterward.

Artifact:

- `debug-captures\windows-lab\20260528-092432-cpu4-loader-control-left200-visualgate-windows-windows`.

Evidence:

- Command used PadApi input, `-WindowsGameScreen 1`, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataReservationLoop Verify`,
  `-WindowsVisualGate CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`,
  the refiner-proposed macro with `ls_left:200`, `-MaxSeconds 205`,
  screenshots every `10s`, screenshots starting at `110s`, and
  `-ScreenshotMaxCount 10`.
- Host checks were clean at prelaunch, postlaunch, `146s`, `150s`, `180s`,
  and postrun.
- RPCS3 moved to `\\.\DISPLAY2` while launched with `--game-screen 1`.
- Visual gate passed byte/color triage: `14` field-like screenshots, first
  field-like `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like
  at-or-before `160s`, field-like at-or-after `190s`, required count `8`,
  and `0` invalid screenshots after first field-like.
- Manual review of `screenshot-0135s.png` immediately after `ls_left:200`
  and `screenshot-0200s.png` at the late gate confirmed clean Path-to-Tenuto
  field visuals with no crash overlay or obvious corruption. FPS overlay was
  roughly `31-35 FPS`; this is not a speed result.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `444` bytes and
  contained only Qt parser/media/painter warnings, not a VM access or Vulkan
  device-lost failure.
- Targeted fatal scan found no real crash/access/device-lost/assertion/
  verification failure. The only `fatal` match was the normal
  `Show fatal error hints: false` config line.
- RPCS3 stopped at the `205s` wall-time limit, then wrapper post-processing
  stalled after artifact paths. No RPCS3/RPCSX process remained active; only
  the wrapper PowerShell was killed before manual visual/log/counter/refiner
  checks.

Counters:

- MFC dynamic probe records: `1619`.
- MFC wait probe records: `1745`.
- MFC wait-PC probe records: `91872`.
- Reservation-loop command probe records: `1745`.
- Reservation-loop verify probe records: `1745`.
- Reservation-loop verify lane records: `4337`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `189`.
- Max reads observed: `228488`.
- Reservation verify records still included nonzero failure/read-failure/
  unexpected counts, so these counters remain route-triage only and are not
  HLE/GPU promotion evidence.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `small-left200-movement-clean`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says not to repeat
  `loader-control-left200x2`; it failed twice in the recent window after a
  lower boundary was clean. Repair route control or switch to focused SPU
  kernel HLE/codegen/verifier analysis before another movement run.

## 2026-05-28 0x25cc Coverage Refresh

Question:

- Since the refiner blocks another `left200x2` movement repeat, refresh the
  focused SPU HLE/codegen evidence for the known `0x25cc` exact skip before
  deciding whether it is worth more work.

Artifact:

- `debug-captures\windows-lab\_eternal-sonata-25cc-coverage-latest.md`.
- `debug-captures\windows-lab\_eternal-sonata-25cc-coverage-latest.csv`.

Evidence:

- Ran `tools\summarize_eternal_sonata_25cc_coverage.ps1`.
- Inputs were the existing Windows title-CSV verify run
  `20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows`,
  skip run
  `20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows`,
  and the current `_eternal-sonata-spu-hle-candidates-latest.csv` atlas.
- No RPCS3 run was launched; there were no new screenshots or live gameplay
  counters this round. Verification was the generated Markdown/CSV plus a
  process check showing no RPCS3/RPCSX process active.
- The refreshed atlas has `3552` 0x25cc records across `6` valid field runs,
  `5.65 GB` total, and `0 B` RSX-local.
- Verify mode saw `501.28 MB` hot `0x25cc`, top EA `0x9e4000`, exact verify
  shape `72.89 MB`, `14.54%` verify share, `4.86 MB` shadow bytes, `0`
  output mismatches, `0` destination changes, and title average `116.57 FPS`.
- Skip mode saw `573.70 MB` hot `0x25cc`, top EA `0x9e4000`, exact verify
  shape `83.20 MB`, `14.50%` verify share, `5.55 MB` shadow/skip bytes, `0`
  output mismatches, `0` destination changes, `0` skip misses, and title
  average `111.33 FPS`.
- The exact skip removed only `0.97%` of that skip run's hot 0x25cc bytes,
  `6.67%` of the exact verifier-shape bytes, and `0.10%` of the refreshed
  `5.65 GB` 0x25cc atlas.

Classification:

- `analysis`.
- `spu-hle-25cc-coverage-gap`.
- Not a Windows micro-win.
- Not speed.
- Not `gpu-migration-credit`.
- Not first-battle proof.
- Not a 200% gate candidate.

Reading:

- The exact `lsa=0x3b000` / `eal=0xa1c000` guarded skip is correctness-clean
  but too small to explain or deliver a major speed gain. Do not rerun that
  exact skip expecting 200%.
- The stronger CPU-pressure path is broader verify-only coverage around the
  dynamic MFC / `0x9e4000` pattern families or SPU codegen dispatch overhead.

## 2026-05-28 0x25cc Runtime-Family Refresh

Question:

- After the exact skip proved too small, split the runtime `0x25cc` traffic by
  dynamic family and pattern groups to decide whether `0x9e4000` verifier
  breadth or codegen dispatch overhead is the next better lever.

Artifact:

- `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-summary.md`.
- `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-patterns.csv`.
- `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-buckets.csv`.
- `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-hash-semantics.csv`.

Evidence:

- Ran `tools\summarize_eternal_sonata_25cc_runtime_family.ps1 -Top 20`.
- The summarizer selected
  `20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`
  as the newest run with 25cc family and GPU-probe CSVs.
- Visual gate summary on that source run reported field-like screenshots from
  `117s`, field-like after `220s`, battle-like at `230s`, and `15`
  field-like screenshots.
- Fatal scan and stderr also found a real
  `VM: Access violation reading location 0x40` at `0x002aedd0`, so this
  analysis is sizing/target selection only and not valid proof.
- Runtime hook buckets: `380` rows, `11988` hits, success/fail `11988/0`,
  GET/PUT hits `5688/6300`, `187.31 MB`, total timing `585.853 ms`,
  average `48.870 us/hit`, max `25055 us`.
- Command-level buckets: `ea9e4000` `799` hits (`6.665%`, `12.48 MB`),
  `exact_a1c000` `799` hits (`6.665%`, `12.48 MB`), and
  `other_matching_ea` `10389` hits (`86.662%`, `162.33 MB`).
- Shadow semantics: `11988` hits, `187.31 MB`, destination changed/unchanged
  `3325/8663`, output match/mismatch `11988/0`, `380` unique source hashes,
  and `380` unique destination-post hashes.
- GPU-probe 0x25cc rows totaled `656.31 MB` with `0 B` direct RSX-local
  traffic.
- HLE pattern-body candidates: `10` repeated `0x9e4000` groups, `278`
  records, `437.30 MB`; top group pattern `0x209c1716c9de855f` had `48`
  records and `73.35 MB`.
- Hash semantics scout still has an instrumentation gap: sampled payload bytes
  were `0 B` and LS/block hashes were `0x0`.

Classification:

- `analysis`.
- `spu-hle-25cc-runtime-family-sizing`.
- Not a Windows micro-win.
- Not speed.
- Not `gpu-migration-credit`.
- Not first-battle proof.
- Not a 200% gate candidate.

Reading:

- Exact command-level EA matching remains too narrow. The broader repeated
  `0x9e4000` pattern-body groups are the better CPU-pressure candidate.
- Direct RSX-local traffic is still `0 B`, so this is CPU/SPU HLE/codegen
  sizing, not GPU migration.
- The next concrete implementation should add or repair clean-route
  pattern/descriptor verifier semantics for top `0x9e4000` groups, including
  sampled payload or LS/block hashes, before any fast body or A/B timing.

## 2026-05-28 Stock-Control TopSlot BattleRoute Device Lost

Question:

- Is the same TopSlot battle route fatal without `Verify25ccShadow`?

Artifact:

- `debug-captures\windows-lab\20260528-102538-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`.

Evidence:

- Ran the refiner-proposed stock-control route with PadApi input,
  `-WindowsGameScreen 1`, TopSlot battle load, CPU affinity `0x0F`,
  frame/vblank `240/240`, `-EternalSonataGpuProbe Profile`,
  host gate `ExternalFail`, `BattleRoute` visual gate, `330s` cap,
  screenshots every `20s`, and screenshots starting at `120s`.
- Host contention checks were clean across the run. RPCS3 stopped at the
  wall-time cap; no emulator process remained active.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: all `15` screenshots from
  `118s` through `320s` were `black-overlay-small-png` at `34954` bytes, with
  no field-like or battle-like frame.
- Manual review of `screenshot-0320s.png` showed black output with only the
  FPS overlay visible.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `1234` bytes.
  `RPCS3.log` was `1.76 MB`.
- Fatal scan found real `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event`
  (`sync.cpp:610`) / `vk::die_with_error` (`shared.cpp:205`) with fault
  `access_write` at address `0x2d0614000`.
- GPU probe summary recorded `769` rows, `792.37 MB` total observed DMA,
  largest single job `4.70 MB`, `0` RSX-local traffic records, offload fit mix
  `too-small=392` and `spu-kernel-hle=377`, hot PCs `0x451c` (`490.04 MB`)
  and `0x25cc` (`302.33 MB`), and top `0x25cc` pattern
  `0x869b21fba7608f1f` at EA `0x9e4000`.

Classification:

- `failed-fatal-log`.
- `failed-visual-gate`.
- `stock-control-topslot-device-lost`.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Reading:

- `Verify25ccShadow` is not the sole explanation for the earlier battle-route
  fatal. The same stock route/device path can lose Vulkan and render only the
  black overlay.
- Do not extend this route. Repair route/RSX device-loss behavior or re-prove
  the latest clean lower boundary before another movement or first-battle
  attempt.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says the latest run had
  fatal/crash log evidence and should not be extended. Re-prove the newest
  clean `loader-control-left200x1` boundary with `CleanAfterField` before
  adding another pulse.

## 2026-05-28 Loader-Control Left200 Boundary Reproof

Question:

- After the stock TopSlot device-loss failure, can the newest clean
  `loader-control-left200x1` lower boundary still be reproduced with
  `CleanAfterField`?

Artifact:

- `debug-captures\windows-lab\20260528-104441-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows`.

Evidence:

- Ran the refiner-proposed command with PadApi input, `-WindowsGameScreen 1`,
  CPU affinity `0x0F`, frame/vblank `240/240`,
  `-EternalSonataReservationLoop Verify`, `CleanAfterField`,
  `-WindowsVisualGateFieldSeconds 160`, the `ls_left:200` macro, `205s` cap,
  screenshots every `10s`, screenshots starting at `110s`, and
  `-ScreenshotMaxCount 10`.
- Host checks were clean at prelaunch, postlaunch, `146s`, `150s`, `180s`,
  and postrun. RPCS3 stopped at the `205s` wall-time cap.
- The wrapper stalled in postrun processing after RPCS3 exited; only the
  wrapper PowerShell was killed. No emulator process remained active.
- Manual visual gate passed: `14` screenshots, first field-like
  `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like by `160s`, `0`
  invalid screenshots after first field-like, and all screenshots through
  `screenshot-0200s.png` were `field-like-large-png`.
- Manual review of `screenshot-0135s.png` immediately after `ls_left:200` and
  `screenshot-0200s.png` confirmed clean Path-to-Tenuto field visuals with no
  crash overlay or obvious corruption.
- Window-title FPS samples ranged from `29.31` to `39.81`; this is not a speed
  result because it is a capped field route check, not a controlled perf A/B.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were both `0` bytes. `RPCS3.log`
  was `91.89 MB`.
- Targeted fatal scan found `0` `VM: Access violation`, `0`
  `VK_ERROR_DEVICE_LOST`, `0` `Assertion Failed`, `0`
  `Thread terminated due to fatal error`, and `0` `Device lost` hits.

Targeted counters:

- MFC dynamic probe records: `1620`.
- MFC list transfer probe records: `839`.
- MFC wait probe records: `1737`.
- MFC wait-PC probe records: `91658`.
- Reservation-loop command probe records: `1737`.
- Reservation-loop command-PC probe records: `47489`.
- Reservation-loop verify probe records: `1736`.
- Reservation-loop verify-lane records: `4323`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `535`.
- Max reads observed: `142285`.
- Read failures: `0`.
- Unexpected values: `0`.
- Lane mismatches: `0`.
- GPU-candidate probe records: `1620`, total observed DMA bytes
  `2653482656`, largest single job `16363104` bytes, and `0` RSX-local bytes.
- Full `summarize_eternal_sonata_gpu_probe.ps1` was stopped after several
  minutes on the dense `91.89 MB` log; the counters above are targeted
  `rg`/PowerShell extraction from the same log.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `small-left200-boundary-clean`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to extend the newest
  valid `loader-control-left200x1` route by exactly one more tiny state-aware
  left pulse with `CleanAfterField`; keep lane-2 HLE/GPU dry-runs blocked.

## 2026-05-28 Loader-Control Left200x2 Non-Field Regression

Question:

- Does the refiner-suggested `left200x2` extension from the clean
  `left200x1` boundary still reproduce a valid Path-to-Tenuto field after two
  tiny state-aware left pulses?

Artifact:

- `debug-captures\windows-lab\20260528-110434-cpu4-loader-control-left200x2-visualgate-windows-windows`.

Evidence:

- Ran the exact refiner command with PadApi input, `-WindowsGameScreen 1`, CPU
  affinity `0x0F`, frame/vblank `240/240`, `ReservationLoop Verify`,
  `CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`, two `ls_left:200`
  pulses, `215s` cap, screenshots from `110s`, and `-ScreenshotMaxCount 11`.
- RPCS3 was moved to `\\.\DISPLAY2`; host checks were clean at prelaunch,
  postlaunch, `149s`, `152s`, `180s`, `210s`, and postrun.
- RPCS3 stopped at the `215s` cap. The wrapper then stalled in postrun log
  processing after RPCS3 exited, so only the wrapper PowerShell was killed.
  No RPCS3/RPCSX process remained active.
- Manual visual gate failed: `16` screenshots, first field-like screenshot
  none, required field-like by `160s` failed, and all screenshots were
  `cutscene-or-nonfield-small-png`.
- Manual review of `screenshot-0117s.png` and `screenshot-0210s.png` showed
  the blue/starry non-field screen, not Path-to-Tenuto field.
- Window-title FPS samples were `25.71` at `117s` and `32.55` for later
  screenshots through `210s`; these are invalid for speed comparison because
  the visual gate failed.
- `rpcs3.stdout.txt` was `0` bytes. `rpcs3.stderr.txt` was `1752` bytes and
  contained libusb disconnected/descriptor warnings only. `RPCS3.log` was
  `102.87 MB`.
- Targeted fatal scan found no `VM: Access violation`, `VK_ERROR_DEVICE_LOST`,
  `Assertion Failed`, `Thread terminated due to fatal error`, `Device lost`,
  verifier failure, non-zero output mismatch, or non-zero dynamic fail hit.

Targeted counters:

- GPU-candidate probe records: `1767`.
- MFC dynamic probe records: `1767`.
- MFC list transfer probe records: `470`.
- MFC wait probe records: `1846`.
- MFC wait-PC probe records: `106759`.
- Reservation-loop command probe records: `1846`.
- Reservation-loop command-PC probe records: `51839`.
- Reservation-loop verify probe records: `6877`.
- Reservation-loop verify-lane records: `5031`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `431022`.
- Read failures: `0`.
- Unexpected values: `0`.
- Lane mismatches: `0`.
- Counters are invalid for HLE/GPU or speed promotion because visuals failed.

Classification:

- `failed-visual-gate`.
- `route-tooling`.
- `loader-control-left200x2-nonfield-regression`.
- Not movement proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to back off from the
  latest non-field/cutscene route and re-prove the last clean
  `loader-control-left200x2-confirm` boundary with `CleanAfterField` before
  diagonal, first-battle, HLE/GPU, or lane-2 fast-mode work.

## 2026-05-28 Loader-Control Left200x2 Confirm Reproof Restored

Question:

- After the blue/starry non-field `left200x2` miss, can the last clean
  `loader-control-left200x2-confirm` boundary be reproduced with
  `CleanAfterField` before any diagonal, battle, or HLE/GPU extension?

Artifact:

- `debug-captures\windows-lab\20260528-112431-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows`.

Evidence:

- Ran the exact refiner command with PadApi input, `-WindowsGameScreen 1`, CPU
  affinity `0x0F`, frame/vblank `240/240`, `ReservationLoop Verify`,
  `CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`, two `ls_left:200`
  pulses, `215s` cap, screenshots from `110s`, and `-ScreenshotMaxCount 11`.
- RPCS3 was moved to `\\.\DISPLAY2`; runtime host checks were clean at
  prelaunch, postlaunch, `149s`, `153s`, `180s`, and `210s`. The postrun
  host sample was moderate only from Codex CPU after RPCS3 stopped, so do not
  use this run as timing evidence.
- RPCS3 stopped at the `215s` cap. The wrapper then stalled in postrun log
  processing after RPCS3 exited, so only the wrapper PowerShell was killed.
  No RPCS3/RPCSX process remained active.
- Manual visual gate passed: `16` screenshots, first field-like
  `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like by `160s`, `0`
  invalid screenshots after first field-like, and all screenshots through
  `screenshot-0210s.png` were `field-like-large-png`.
- Manual review of `screenshot-0138s.png` after the second `ls_left:200` pulse
  and `screenshot-0210s.png` confirmed clean Path-to-Tenuto field visuals with
  no crash overlay or obvious corruption.
- Window-title FPS samples ranged from `22.92` to `36.31`; this is not a
  speed result because it is a capped route-boundary reproof and postrun host
  was moderate after emulator exit.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were both `0` bytes. `RPCS3.log`
  was `92.38 MB`.
- Targeted fatal scan found no `VM: Access violation`, `VK_ERROR_DEVICE_LOST`,
  `Assertion Failed`, `Thread terminated due to fatal error`, `Device lost`,
  verifier failure, non-zero output mismatch, or non-zero dynamic fail hit.

Targeted counters:

- GPU-candidate probe records: `1615`.
- MFC dynamic probe records: `1615`.
- MFC list transfer probe records: `837`.
- MFC wait probe records: `1756`.
- MFC wait-PC probe records: `91834`.
- Reservation-loop command probe records: `1755`.
- Reservation-loop command-PC probe records: `47914`.
- Reservation-loop verify probe records: `6115`.
- Reservation-loop verify-lane records: `4360`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `362`.
- Max reads observed: `155880`.
- Read failures: `0`.
- Unexpected values: `0`.
- Lane mismatches: `0`.
- GPU-candidate total observed DMA bytes: `2750496544`; largest single job
  `20628048` bytes; RSX-local bytes `0`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-left200x2-confirm-restored`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` now says to extend the newest
  valid `loader-control-left200x2` route by exactly one tiny diagonal
  micro-pulse with `CleanAfterField`; keep lane-2 HLE/GPU dry-runs blocked.

## 2026-05-28 Loader-Control Left200x2 Diagonal Reproof Restored

Question:

- After restoring the `left200x2-confirm` boundary, can one tiny diagonal
  `ls_left+ls_down:200` micro-pulse be added while retaining clean
  Path-to-Tenuto field visuals under `CleanAfterField`?

Artifact:

- `debug-captures\windows-lab\20260528-114457-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`.

Evidence:

- Ran the exact refiner command with PadApi input, `-WindowsGameScreen 1`, CPU
  affinity `0x0F`, frame/vblank `240/240`, `ReservationLoop Verify`,
  `CleanAfterField`, `-WindowsVisualGateFieldSeconds 160`, two `ls_left:200`
  pulses plus one `combo:ls_left+ls_down:200` pulse, `225s` cap,
  screenshots from `110s`, and `-ScreenshotMaxCount 12`.
- RPCS3 was moved to `\\.\DISPLAY2`; runtime host checks were clean at
  prelaunch, postlaunch, `152s`, `180s`, and `210s`. The postrun host sample
  was moderate only from Codex CPU after RPCS3 stopped, so do not use this run
  as timing evidence.
- RPCS3 stopped at the `225s` cap. The wrapper then stalled in postrun log
  processing after RPCS3 exited, so only the wrapper PowerShell was killed.
  No RPCS3/RPCSX process remained active.
- Manual visual gate passed: `18` screenshots, first field-like
  `screenshot-0117s.png` at `117s` (`2.50 MB`), field-like by `160s`, `0`
  invalid screenshots after first field-like, and all screenshots through
  `screenshot-0220s.png` were `field-like-large-png`.
- Manual review of `screenshot-0141s.png` after the diagonal pulse and
  `screenshot-0220s.png` confirmed clean Path-to-Tenuto field visuals with no
  crash overlay or obvious corruption.
- Window-title FPS samples ranged from `23.90` to `44.19`; this is not a
  speed result because it is a capped route-boundary proof and postrun host
  was moderate after emulator exit.
- `rpcs3.stdout.txt` and `rpcs3.stderr.txt` were both `0` bytes. `RPCS3.log`
  was `92.31 MB`.
- Targeted fatal scan found no `VM: Access violation`, `VK_ERROR_DEVICE_LOST`,
  `Assertion Failed`, `Thread terminated due to fatal error`, `Device lost`,
  verifier failure, non-zero output mismatch, or non-zero dynamic fail hit.

Targeted counters:

- GPU-candidate probe records: `1632`.
- MFC dynamic probe records: `1632`.
- MFC list transfer probe records: `842`.
- MFC wait probe records: `1738`.
- MFC wait-PC probe records: `92192`.
- Reservation-loop command probe records: `1737`.
- Reservation-loop command-PC probe records: `47637`.
- Reservation-loop verify probe records: `6078`.
- Reservation-loop verify-lane records: `4341`.
- Max output mismatches: `0`.
- Max dynamic fail: `0`.
- Max overflow reads: `212`.
- Max reads observed: `155740`.
- Read failures: `0`.
- Unexpected values: `0`.
- Lane mismatches: `0`.
- GPU-candidate total observed DMA bytes: `2666662736`; largest single job
  `16934592` bytes; RSX-local bytes `0`.

Classification:

- `valid-field-triage`.
- `route-tooling`.
- `loader-control-left200x2-diag200-field-clean`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Refiner result:

- `tools\ps3_harness_refiner.ps1 -MaxRuns 8` says the latest
  `loader-control-left200x2-diag200` proof is clean and must not be repeated.
  Bank it as route-tooling only, then pivot to Options/menu proof, first-battle
  route repair, or focused SPU kernel HLE/codegen/verifier analysis.

## 2026-05-28 Latest Pointer: Pivot After Diagonal Proof

Next exact command:

```powershell
# No automatic duplicate: latest loader-control-left200x2-diag200 already passed field triage.
# Bank it as route tooling and pivot to Options/menu proof, first-battle route repair,
# or focused SPU kernel HLE/codegen/verifier analysis.
```

## 2026-05-28 SPU HLE Candidate Atlas Refresh After Diagonal Proof

Question:

- After banking the clean diagonal field route, what is the next non-visual
  CPU/SPU pressure target that can move performance work without repeating the
  route proof or enabling lane-2/GPU fast modes?

Command:

```powershell
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 12 -Top 20
```

Artifact:

- `debug-captures\windows-lab\_eternal-sonata-spu-hle-candidates-latest.md`.
- `debug-captures\windows-lab\_eternal-sonata-spu-hle-candidates-latest.csv`.

Evidence:

- The atlas scanned `12` recent run directories.
- It used `2` valid field runs:
  - `20260528-040209-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.
  - `20260528-032238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows`.
- It excluded `2` field-like runs with real fatal logs:
  - `20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`.
  - `20260528-042238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows`.
- Top stable bucket remains PC `0x25cc`, `CellSpursKernelGroup` /
  `CellSpursKernel0`, image `0x958dfe208b686622`, recommendation
  `spu-hle-codegen-priority`.
- Shape: `3.06 GB` total over `1946` records, `463.93 MB` GET, `2.61 GB`
  PUT, `0 B` list GET, max job `3.06 MB`, `58` pattern signatures, and
  `0 B` RSX-local.
- Next bucket is PC `0x451c`, `TCX_CellSpursKernel0`, also
  `spu-hle-codegen-priority`, with `2.93 GB` total and `0 B` RSX-local.
- Top repeated `0x25cc` patterns across the valid runs include
  `0x30540805202a855f` (`250.61 MB`), `0x209c1716c9de855f`
  (`224.63 MB`), `0x4318b5fc803b855f` (`223.10 MB`), and
  `0xf7bf30bddad5855f` (`212.40 MB`).
- Latest valid disasm window remains
  `debug-captures\windows-lab\20260528-040209-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows\spu-images\BLUS30161-spu-image-958dfe208b686622-entry-00818-pc-025cc-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.disasm.txt`.

Classification:

- `analysis`.
- `spu-hle-codegen-triage`.
- `stackable-cpu-pressure-target-selection`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Broad SPU-to-Vulkan compute stays parked because the valid set still has
  `0 B` RSX-local evidence.
- Continue with verify-only `0x25cc` SPU HLE/codegen/verifier work or the
  missing visual gates (Options/menu and first battle). Keep lane-2/GPU fast
  modes blocked until field/menu/battle visuals are valid.

## 2026-05-28 0x25cc / 0x9e4000 Verifier Plan Refresh

Question:

- After the atlas narrowed the valid-field CPU/SPU pressure target to
  `0x25cc`, can the existing verifier plan still point to concrete code
  anchors and a broad enough family predicate without repeating field-route
  proof or enabling unsafe fast/GPU modes?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\summarize_eternal_sonata_25cc_verifier_plan.ps1
```

Artifact:

- `debug-experiments\20260526-25cc-9e4000-verifier-plan.md`.

Evidence:

- Refiner scanned `8` recent runs and again said not to repeat
  `loader-control-left200x2-diag200`; pivot to first-battle repair or focused
  SPU kernel HLE/codegen/verifier analysis.
- The verifier plan refreshed against the current
  `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` checkout.
- Source anchors moved to current upstream locations:
  - `SPUThread.cpp:2161` for `try_es_spu_hle_25cc_body_copy`.
  - `SPUThread.cpp:6774` for `process_mfc_cmd`.
  - `SPULLVMRecompiler.cpp:4401` for
    `exec_es_spu_hle_verify_candidate`.
  - `SPULLVMRecompiler.cpp:5707` for the dynamic MFC fallback signal.
- Historical `20260526-25cc-pattern-family.csv` coverage for the broad
  `0x9e4000` family remains `6.86 GB` across `4340` records, `159` pattern
  rows, and `47` repeated rows, with `0 B` RSX-local.
- The plan explicitly keeps exact `0xa1c000` as too narrow:
  `5.55 MB` skipped, `0.97%` of that run's hot `0x25cc` bytes, `6.67%` of
  exact verifier-shape bytes, `0` mismatches, and `0` destination changes.
- It requires a verify-only rollback path and command/family/hash counters
  before any fast/body/skip mode.

Classification:

- `analysis`.
- `spu-hle-25cc-9e4000-verifier-plan`.
- `stackable-cpu-pressure-target-selection`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- This refresh does not supersede the valid-field atlas. Use the atlas
  `3.06 GB` valid-field subset for proof discipline and the verifier plan's
  `6.86 GB` historical family for code-anchor and counter design.
- Next non-visual implementation step should add or confirm verify-only
  family/hash counters around PC `0x25cc` / `CellSpursKernel0`, not enable
  fast/body mode.

## 2026-05-28 Refiner Tightening And 0x25cc Hash Target Refresh

Question:

- After the verifier plan refresh, how do we stop the continual loop from
  repeating diagonal field proof or repeating the same analysis report, while
  still moving the CPU/SPU pressure lane forward?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\summarize_eternal_sonata_25cc_hash_targets.ps1
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `tools\ps3_harness_refiner.ps1`.
- `debug-experiments\20260526-25cc-pattern-hash-targets.md`.
- `debug-experiments\20260526-25cc-pattern-hash-targets.csv`.

Evidence:

- Initial refiner output still gave the broad branch: do not repeat
  `loader-control-left200x2-diag200`; pivot to Options/menu proof,
  first-battle route repair, or focused SPU HLE/codegen/verifier analysis.
- Refiner was tightened to detect fresh
  `20260526-25cc-9e4000-verifier-plan.md` and
  `20260526-25cc-pattern-hash-targets.md` report timestamps.
- After the verifier plan is fresh but hash targets are stale, the suggested
  command becomes:

```powershell
.\tools\summarize_eternal_sonata_25cc_hash_targets.ps1
```

- After both reports are fresh, the suggested command becomes a blocker
  comment, not another report rerun:

```powershell
# No automatic duplicate: diagonal field proof and 0x25cc verifier/hash reports are already refreshed.
# Implement/confirm verify-only family/hash counters around PC 0x25cc next,
# or run a non-duplicate first-battle route repair.
```

- Hash target refresh used the latest Windows run with both runtime-family
  patterns and 25cc shadow profile:
  `20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`.
  That source run is fatal, so the report is sizing/target-selection only.
- Atlas `0x9e4000` HLE candidates remain `159` groups / `6.86 GB`.
- Latest shadow-run runtime candidates are `10` groups / `437.30 MB`.
- Top-16 atlas groups seen in that shadow run are `5` groups,
  `2.09 GB` atlas bytes, and `274.17 MB` latest-run bytes.
- Shadow verifier totals: `11988` hits, `187.31 MB`, GET/PUT `5688/6300`,
  changed/unchanged `3325/8663`, match/mismatch `11988/0`.
- Exact EA buckets remain too narrow: `ea9e4000=799`,
  `exact_a1c000=799`, `other_matching_ea=10389`.
- Matched top groups are PUT-heavy at about `84%` PUT, so the current
  GET-only `0x25cc` body copy cannot cover the main bytes.

Classification:

- `analysis`.
- `harness-refiner-improvement`.
- `spu-hle-25cc-pattern-hash-targets`.
- `stackable-cpu-pressure-target-selection`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not refresh the same verifier/hash reports again until new run data or
  code changes exist.
- Next non-visual implementation step is verify-only pattern/descriptor
  counters split by MFC direction, source hash, destination pre/post hash,
  and output match/mismatch around PC `0x25cc`.
- Broad SPU-to-Vulkan remains parked because the lane still has `0 B`
  RSX-local evidence and tiny-dispatch risk.

## 2026-05-28 0x25cc Shadow Native Contract Refresh

Question:

- After the hash-target refresh, can we turn the 0x25cc analysis into a
  concrete native contract without adding another duplicate report loop?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
rg -n "record_es_spu_hle_25cc_shadow_sample|exec_es_spu_hle_verify_candidate|25cc" C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell app\src\main\cpp\rpcsx\rpcs3\Emu\Cell
.\tools\summarize_eternal_sonata_25cc_shadow_contract.ps1
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `tools\ps3_harness_refiner.ps1`.
- `tools\summarize_eternal_sonata_25cc_shadow_contract.ps1`.
- `debug-experiments\20260526-25cc-shadow-native-contract.md`.
- `debug-experiments\20260526-25cc-shadow-native-contract.csv`.

Evidence:

- No active `rpcs3` or `rpcsx` process was running at the checkpoint start.
- Current upstream comparison source already has direction-split descriptor
  instrumentation anchors around `SPUThread.cpp` 0x25cc shadow recording and
  `SPULLVMRecompiler.cpp` verifier-candidate dispatch.
- The vendored Android core was only searched for parity; no Android, ADB, or
  Thor work was run.
- The shadow-contract report now classifies the selected shadow run correctly
  as `fatal-run sizing evidence only`, not clean proof.
- Selected shadow verifier totals: `11988` hits, `187.31 MB`, GET/PUT
  `5688/6300`, changed/unchanged `3325/8663`, and match/mismatch `11988/0`.
- Runtime-seen top target groups cover `274.17 MB` in the selected run, with
  PUT `231.52 MB` (`84.4%`) and GET `42.65 MB` (`15.6%`).
- Multi-run atlas coverage for those runtime-seen groups is `2.09 GB`.
- The refiner now detects the fresh verifier plan, hash targets, and native
  contract; its suggested command is a stop-comment, not another report rerun.

Classification:

- `analysis`.
- `harness-refiner-improvement`.
- `spu-hle-25cc-shadow-native-contract`.
- `stackable-cpu-pressure-target-selection`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not generate another 0x25cc planning/hash/native-contract report until
  new run data or source changes exist.
- Next useful Windows-only step is clean-route proof of direction-split 0x25cc
  counters, or patching the active Windows source if the binary lacks the
  descriptor counters.
- The PUT-heavy direction split is target selection only. It cannot promote
  bodyfast, skip, GPU migration, or 200% without clean field, Options/menu, and
  first-battle proof.

## 2026-05-28 Verify25ccShadow Field Counterproof

Question:

- After the native contract, can the active Windows binary emit clean
  direction-split 0x25cc GET/PUT descriptor counters on a visually clean route?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows" -RequireFieldLike -RequireNoInvalidAfterFirstField -RequireFieldAtOrBeforeSeconds 160 -MinFieldPngBytes 1000000
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir "debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows"
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows`.
- `tools\summarize_eternal_sonata_25cc_counterproof.ps1`.
- `debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows\eternal-sonata-25cc-counterproof-summary.md`.
- `debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows\eternal-sonata-25cc-counterproof-direction-summary.csv`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 was launched through the Windows harness with `--game-screen 1`,
  `Verify25ccShadow`, reservation-loop verify, GPU probe profile, and body/skip
  modes off.
- The wrapper hit the planned `225s` stop, RPCS3 exited, and the wrapper then
  stalled in postrun parsing. Only the stuck wrapper process was killed; the
  emulator was already gone and artifacts were complete.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `18` field-like screenshots, `0` invalid
  screenshots after first field-like, and required field before `160s` passed.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- Host checks were clean during the run; postrun was moderate only from Codex
  CPU after RPCS3 exited.
- 25cc shadow verifier totals: `23643` hits, `369.42 MB`, GET/PUT
  `10998/12645`, match/mismatch `23643/0`, changed/unchanged `8135/15508`.
- 25cc descriptor totals: `22008` rows, `23643` hits, `369.42 MB`, GET/PUT
  hits `10998/12645`, output mismatch `0`, max descriptor overflow `0`.
- Direction split:
  - GET `0x40`: `10998` rows / `10998` hits / `171.84 MB`, mismatch `0`,
    overflow `0`, `106` patterns.
  - PUT `0x20`: `11010` rows / `12645` hits / `197.58 MB`, mismatch `0`,
    overflow `0`, `106` patterns.
- Generic non-25cc shadow verifier rows still showed `125` mismatches across
  `109` lines at PC `0x451c`. This blocks broad shadow/HLE claims, but not the
  25cc-only descriptor counterproof above.

Classification:

- `valid-field-counterproof`.
- `spu-hle-25cc-shadow-counterproof`.
- `stackable-cpu-pressure-target-selection`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The active Windows binary can emit direction-split 0x25cc GET/PUT descriptor
  counters on a visually clean field route.
- Do not repeat field counterproof or add another 0x25cc report. Next useful
  step is first-battle route repair/proof under `Verify25ccShadow`, with
  body/skip/GPU modes still off.

## 2026-05-28 Verify25ccShadow First-Battle Attempt After Field Counterproof

Question:

- After clean field counterproof, can the TopSlot BattleRoute produce valid
  first-battle visuals under `Verify25ccShadow` with body/skip/GPU modes off?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows" -RequireFieldLike -RequireBattleLikeAtOrAfterSeconds 220 -RequireFieldAtOrBeforeSeconds 160 -MinFieldPngBytes 1000000
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir "debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows"
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows`.
- `debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows\eternal-sonata-25cc-counterproof-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  `Verify25ccShadow`, GPU probe profile, and body/skip/GPU fast paths off.
- Prelaunch, postlaunch, and in-run host samples were clean. The host gate
  failed only after RPCS3 exited because Codex CPU was sampled as a hot non-run
  process.
- RPCS3 reached the planned `330s` stop and exited; the wrapper then stalled in
  postrun parsing and was killed after artifact completion.
- Visual gate failed: all `15` screenshots were `black-overlay-small-png`,
  with no field-like screenshot and no battle-like screenshot at or after
  `220s`.
- Window-title FPS samples continued through `320s`, but screenshots remained
  black overlay; therefore title FPS is not valid visual proof.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- 25cc counter summary was `partial-counterproof` only because visuals failed:
  `31263` hits / `488.48 MB`, GET/PUT `14748/16515`, match/mismatch `31263/0`,
  descriptor rows `29508`, descriptor mismatch `0`, overflow `0`.
- Generic non-25cc shadow rows still showed `350` mismatches across `311`
  lines at PC `0x451c`.
- Refiner now classifies the latest run as `failed-visual-gate` and points to
  re-proving `loader-control-left200x2` before adding movement again.

Classification:

- `failed-visual-gate`.
- `black-overlay-small-png`.
- `partial-counterproof`.
- Not field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- This run proves the first-battle TopSlot path can keep RPCS3 alive and emit
  25cc counters, but the black-overlay screenshots invalidate every gameplay
  claim.
- Do not rerun the same TopSlot Verify25ccShadow battle command unchanged.
- Next useful step is to re-prove the clean loader-control-left200x2 boundary
  with `CleanAfterField`, then rebuild battle movement from a visual-valid
  boundary.

## 2026-05-28 Loader-Control left200x2 Reconfirm After Black-Overlay Battle

Question:

- After the black-overlay battle attempt, is the last clean loader-control
  `left200x2` boundary still visually valid enough to build from?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -RequireFieldLike -RequireNoInvalidAfterFirstField -RequireFieldAtOrBeforeSeconds 160 -MinFieldPngBytes 1000000
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir "debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -Top 12
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- RPCS3 reached the planned `215s` stop and exited. The wrapper then stayed in
  the known postrun phase; after confirming no emulator process remained and
  artifacts were present, only the stuck wrapper was killed.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `16` field-like screenshots through
  `210s`, `0` invalid screenshots after first field-like, and required field
  before `160s` passed.
- Manual image review of `screenshot-0117s.png` and `screenshot-0210s.png`
  confirmed clean Path-to-Tenuto field visuals after the two left pulses.
- Host checks were clean across prelaunch, postlaunch, runtime samples, and
  postrun. `stdout`/`stderr` were empty.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- GPU probe summary extracted `1539` records, `2,283.71 MB` observed DMA,
  largest single job `9.35 MB`, `0 B` RSX-local traffic, and fit mix
  `spu-kernel-hle=1096`, `too-small=443`.
- Reservation-loop summary extracted `1639` reservation command rows,
  `44896` command exact-PC rows, `86252` command-run MFC wait exact-PC rows,
  peak snapshot hits GETLLAR/PUTLLC/Atomic/PUTLLC-fail
  `140021/109015/31006/144270/12599`, and primary command/read deltas
  GETLLAR `0`, PUTLLC `0`.
- Reservation-loop summary still reports `collect-missing-proof` because no
  kernel capsule or PUTLLC16 pair verifier rows were present. Do not change
  fast paths from this run alone.
- Refiner now classifies the newest run as `valid-field-triage` and points to
  exactly one tiny diagonal micro-pulse with `CleanAfterField`.

Classification:

- `valid-field-triage`.
- `loader-control-left200x2-reconfirmed`.
- `reservation-loop-counter-base`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The clean loader-control `left200x2` boundary is re-established after the
  black-overlay battle failure.
- Next useful step is one tiny diagonal micro-pulse from this base with
  `CleanAfterField`; lane-2 HLE/GPU dry-runs stay blocked until field,
  Options/menu, and first-battle visuals are valid.

## 2026-05-28 Loader-Control left200x2 + diag200 Reproof After Reconfirm

Question:

- Can the newly revalidated loader-control `left200x2` boundary tolerate one
  tiny diagonal micro-pulse without falling back to black/loading/non-field
  captures?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows" -RequireFieldLike -RequireNoInvalidAfterFirstField -RequireFieldAtOrBeforeSeconds 160 -MinFieldPngBytes 1000000
.\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir "debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows" -Top 12
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- RPCS3 reached the planned `225s` stop and exited. The wrapper then stayed in
  the known postrun phase; after confirming no emulator process remained and
  artifacts were present, only the stuck wrapper was killed.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s.png` at `117s`, `18` field-like screenshots through
  `220s`, `0` invalid screenshots after first field-like, and required field
  before `160s` passed.
- Manual image review of `screenshot-0117s.png`, `screenshot-0141s.png`, and
  `screenshot-0220s.png` confirmed clean Path-to-Tenuto field visuals before,
  during, and after the diagonal micro-pulse.
- Runtime host samples were clean. Postrun was moderate only because Codex CPU
  was sampled after RPCS3 exited. `stdout`/`stderr` were empty.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- GPU probe summary extracted `1743` records, `2,682.32 MB` observed DMA,
  largest single job `22.94 MB`, `0 B` RSX-local traffic, and fit mix
  `spu-kernel-hle=1255`, `too-small=488`.
- Hot PCs remained CPU/SPU HLE/codegen candidates, not GPU offload proof:
  `0x451c` had `1,422.54 MB` and `0x25cc` had `1,259.78 MB`; both had
  `0 B` RSX-local.
- Reservation-loop summary extracted `1884` reservation command rows,
  `51325` command exact-PC rows, `98353` command-run MFC wait exact-PC rows,
  peak snapshot hits GETLLAR/PUTLLC/Atomic/PUTLLC-fail
  `157113/107467/49646/160243/20776`, and primary command/read deltas
  GETLLAR `0`, PUTLLC `0`.
- Reservation-loop summary still reports `collect-missing-proof` because no
  kernel capsule or PUTLLC16 pair verifier rows were present. Do not change
  fast paths from this run alone.
- Refiner now says not to repeat field counterproof or diagonal field triage;
  next useful step is first-battle route repair/proof under
  `Verify25ccShadow` with body/skip/GPU modes off.

Classification:

- `valid-field-triage`.
- `loader-control-left200x2-diag200-reconfirmed`.
- `reservation-loop-counter-base`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The diagonal micro-pulse boundary is re-established after the black-overlay
  battle failure and after the `left200x2` reconfirm.
- Next useful step is first-battle route repair/proof under
  `Verify25ccShadow`; body/skip/GPU modes stay off until field, Options/menu,
  and first-battle visuals are valid.

## 2026-05-28 Verify25ccShadow Bridge Probe From Clean Diag Field

Question:

- Can the clean `left200x2+diag200` loader-control route tolerate one larger
  bridge step toward the first-battle route while `Verify25ccShadow` is on and
  all body/skip/GPU fast paths remain off?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field;wait:1000;ls_left:200;wait:1000;shot:left200;wait:1000;ls_left:200;wait:1000;shot:left200x2;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:diag200;wait:1000;ls_left:800;wait:1200;shot:left800-bridge;wait:8000;combo:ls_left+ls_down:600;wait:1200;shot:diag600-bridge;wait:20000;shot:bridge-late" -MaxSeconds 230 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 16 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir "debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows"
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows`.
- `debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows\eternal-sonata-25cc-counterproof-summary.md`.
- `debug-captures\windows-lab\20260528-145806-cpu4-hle-25cc-shadow-desc-battle-bridge-left800-diag600-cleanfield-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, `Verify25ccShadow`, GPU probe profile, body/skip/GPU
  fast paths off, and CPU affinity `0x0F`.
- Host checks were clean at prelaunch, postlaunch, and postrun. `stdout` and
  `stderr` were empty.
- Field route stayed valid through the known boundary: screenshots at `117s`,
  `120s`, `123s`, and `126s` were all field-like large PNGs, with the accepted
  field first at `117s`.
- The larger bridge step failed before battle proof. `screenshot-0129s-left800-bridge.png`
  was a small wrong-window capture (`60.86 KB`) showing the browser after RPCS3
  had exited; later `diag600` and `bridge-late` screenshots were skipped because
  the game window was gone.
- Visual gate status was
  `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`; this is a
  process/window-loss route-boundary failure, not a render-quality proof or a
  GPU visual failure.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- GPU probe summary extracted `865` records, `865` SPU HLE verifier records,
  `405` 0x25cc family records, `12111` 0x25cc shadow descriptor records,
  `442` 0x451c descriptor-batch records, and `0 B` RSX-local traffic.
- 25cc counterproof classified the run as `partial-counterproof`: `12858`
  0x25cc shadow verifier hits over `200.91 MB`, GET/PUT `6063/6795`,
  match/mismatch `12858/0`, and descriptor overflow `0`.
- Direction-split 25cc descriptor rows remained clean: GET `6051` hits over
  `94.55 MB`, PUT `6780` hits over `105.94 MB`, and `0` 25cc mismatches.
- Generic non-25cc shadow mismatches still appeared at `0x451c` (`59` across
  `58` lines), blocking broad shadow claims but not the 25cc-only reading.
- Reservation-loop summary extracted `931` reservation command rows, `25453`
  command exact-PC rows, `48397` command-run MFC wait exact-PC rows, peak
  snapshot hits GETLLAR/PUTLLC/Atomic/PUTLLC-fail
  `124945/95474/29471/128538/9285`, and primary command/read deltas GETLLAR
  `0`, PUTLLC `0`.
- Refiner now reports newest run decision `failed-window-lost-after-field` and
  says to use the latest valid `left200x2+diag200` field run as the route base,
  adding only one small state-aware movement step with `CleanAfterField`.

Classification:

- `failed-window-lost-after-field`.
- `partial-counterproof`.
- `route-boundary-failure`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not rerun this `left800+diag600` bridge as-is and do not promote lane-2
  HLE/GPU paths from its clean counters.
- Back off to the clean `left200x2+diag200` field route and add only one small,
  state-aware movement step under `CleanAfterField`.

## 2026-05-28 Loader-Control left200x2 + diag200 + left400 Bridge Reproof

Question:

- Can the clean `left200x2+diag200` field route survive a smaller `left400`
  bridge step after the `left800+diag600` bridge lost/exited the game window?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-left400-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field;wait:1000;ls_left:200;wait:1000;shot:left200;wait:1000;ls_left:200;wait:1000;shot:left200x2;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:diag200;wait:1000;ls_left:400;wait:1200;shot:left400-bridge;wait:12000;shot:left400-late" -MaxSeconds 235 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Visual gate passed: `FIELD_LIKE_PRESENT`, first field-like screenshot
  `screenshot-0117s-accepted-field.png` at `117s`, `19` field-like screenshots
  through `230s`, `0` invalid screenshots after first field-like, and required
  field before `160s` passed.
- Manual image review of `screenshot-0129s-left400-bridge.png` and
  `screenshot-0230s.png` confirmed clean Path-to-Tenuto field visuals after the
  `left400` bridge and at the late checkpoint.
- Runtime host samples were clean. Postrun/summary was moderate only because
  Codex CPU was sampled after RPCS3 exited. `stdout` and `stderr` were empty.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- GPU probe summary extracted `1739` records, `2,677.34 MB` observed DMA,
  largest single job `11.99 MB`, `0 B` RSX-local traffic, and fit mix
  `spu-kernel-hle=1292`, `too-small=447`.
- Reservation-loop summary extracted `1851` reservation command rows, `50783`
  command exact-PC rows, `98568` command-run MFC wait exact-PC rows, peak
  snapshot hits GETLLAR/PUTLLC/Atomic/PUTLLC-fail
  `202517/150217/52300/207465/11321`, and primary command/read deltas GETLLAR
  `0`, PUTLLC `0`.
- Reservation-loop summary still reports `collect-missing-proof` because no
  kernel capsule or PUTLLC16 pair verifier rows were present. Do not change
  fast paths from this run alone.
- Refiner now classifies the newest run as `valid-field-triage` and still says
  first-battle route repair/proof under `Verify25ccShadow` is required before
  any body/skip/GPU mode.

Classification:

- `valid-field-triage`.
- `loader-control-left200x2-diag200-left400-reconfirmed`.
- `reservation-loop-counter-base`.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The `left400` bridge recovers useful route margin after the failed `left800`
  bridge and is now the narrow valid movement boundary.
- Do not promote lane-2 HLE/GPU paths from this; next useful proof remains
  first-battle route repair under `Verify25ccShadow` with body/skip/GPU modes
  off.

## 2026-05-28 Verify25ccShadow left400 + diag400 Battle Probe

Question:

- Can the newly valid `left200x2+diag200+left400` route become a first-battle
  repair path if we add one smaller `left+down 400ms` nudge under
  `Verify25ccShadow`, with body/skip/GPU fast paths off?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field;wait:1000;ls_left:200;wait:1000;shot:left200;wait:1000;ls_left:200;wait:1000;shot:left200x2;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:diag200;wait:1000;ls_left:400;wait:1200;shot:left400-bridge;wait:1000;combo:ls_left+ls_down:400;wait:1600;shot:diag400-battleprobe;wait:60000;shot:probe-late1;wait:60000;shot:probe-late2;wait:60000;shot:probe-late3" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir "debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows"
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows`.
- `debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows\eternal-sonata-25cc-counterproof-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  `Verify25ccShadow`, GPU probe profile, body/skip/GPU fast paths off, and CPU
  affinity `0x0F`.
- Runtime and postrun host checks were clean across `5` snapshots. `stdout` and
  `stderr` were empty.
- BattleRoute visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, `20`
  screenshots, all `black-overlay-small-png`, no field-like screenshot at or
  before `160s`, no field-like screenshot at or after `220s`, and no
  battle-like screenshot at or after `200s`.
- Manual image review of `screenshot-0117s-accepted-field.png` and
  `screenshot-0314s-probe-late3.png` confirmed black/perf-overlay captures,
  not field or battle visuals. Ignore window-title FPS samples from this run.
- Targeted fatal/access/device-lost/assertion scan found `0` hits.
- GPU probe summary extracted `2670` records, `2670` SPU HLE verifier records,
  `919` 0x25cc family records, `27558` 0x25cc shadow descriptor records,
  `1718` 0x451c descriptor-batch records, and `0 B` RSX-local traffic.
- 25cc counterproof classified the run as `partial-counterproof`: `29703`
  0x25cc shadow verifier hits over `464.11 MB`, GET/PUT `13773/15930`,
  match/mismatch `29703/0`, changed/unchanged `4497/25206`, and descriptor
  overflow `0`.
- Direction-split 25cc descriptor rows remained clean: GET `13773` hits over
  `215.20 MB`, PUT `15930` hits over `248.91 MB`, and `0` 25cc mismatches.
- Generic non-25cc shadow mismatches still appeared at `0x451c` (`356` across
  `316` lines), blocking broad shadow claims but not the 25cc-only reading.
- Refiner now flags `repeated-black-overlay-pre-field` and says to re-prove the
  newest clean `loader-control-left200x2` boundary with `CleanAfterField`
  before adding movement again.

Classification:

- `failed-visual-gate`.
- `black-overlay-pre-field`.
- `partial-counterproof`.
- Not valid field proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not use this run for route, HLE, GPU, or speed promotion despite clean
  25cc counters.
- Re-prove the clean `loader-control-left200x2` boundary with `CleanAfterField`
  before adding any more movement or BattleRoute probes.

## 2026-05-28 loader-control left200x2 Reproof After Black Overlay

Question:

- After the `Verify25ccShadow` BattleRoute probe black-overlayed before field,
  can the newest clean `loader-control-left200x2` boundary still produce stable
  Path-to-Tenuto field visuals with `CleanAfterField`?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Runtime host samples were clean at `150s`, `180s`, and `210s`; postrun was
  moderate only because Codex CPU was sampled after RPCS3 exited.
- RPCS3 reached the planned `215s` timeout and stopped. The wrapper then
  stalled in postrun analysis, matching the known loader-control postrun hang;
  no emulator process remained active, so only the stuck PowerShell wrapper was
  killed before manual analysis.
- Visual gate passed: `FIELD_LIKE_PRESENT`, `16` screenshots, first field-like
  `screenshot-0117s.png` at `117s`, required field before `160s` passed, and
  invalid screenshots after first field-like `0`.
- Manual image review of `screenshot-0117s.png` and `screenshot-0210s.png`
  confirmed clean Path-to-Tenuto field visuals after the two left pulses.
- `stdout` and `stderr` were empty.
- Targeted fatal/access/device-lost/assertion/verification scan found only
  config text (`SPU Verification` and `Show fatal error hints: false`), with no
  real fatal/access/device-lost/assertion/verification hit.
- Reservation-loop summary had no command CSVs because the wrapper was killed
  after RPCS3 exit and before postrun CSV collection. It reports
  `command-correlation-data-missing` and `collect-missing-proof`; do not use
  this run for counter, HLE, GPU, or speed promotion.
- Refiner now marks the black-overlay control resolved and says to extend the
  valid `loader-control-left200x2` base by exactly one tiny `diag200`
  micro-pulse with `CleanAfterField`.

Classification:

- `valid-field-triage`.
- `loader-control-left200x2-reproved`.
- `visual-route-proof-only`.
- Not reservation-loop counter proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The black-overlay failure did not invalidate the `left200x2` visual base.
- Next non-duplicative action is the refiner-selected `left200x2+diag200`
  `CleanAfterField` reproof; keep lane-2 HLE/GPU modes blocked.

## 2026-05-28 loader-control left200x2 + diag200 Reproof

Question:

- Can the newly re-proved `left200x2` visual base survive exactly one tiny
  `left+down 200ms` diagonal micro-pulse under `CleanAfterField`, with
  reservation-loop verify on and all fast/HLE/GPU modes off?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows" -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Host grade was clean at prelaunch, postlaunch, runtime samples `152s`,
  `180s`, `210s`, and postrun.
- RPCS3 reached the planned `225s` timeout and stopped. The wrapper then
  stalled after RPCS3 exit; no emulator process remained, so only the stuck
  PowerShell wrapper was killed before manual analysis.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, `18` screenshots, first
  field-like none, required field before `160s` failed, and all screenshots
  classified `cutscene-or-nonfield-small-png`.
- Manual image review of `screenshot-0117s.png` and `screenshot-0220s.png`
  confirmed blue/starry wrong-scene sky output, not Path-to-Tenuto field.
- `stdout` and `stderr` were empty.
- Targeted fatal/access/device-lost/assertion/verification scan found only
  config text (`SPU Verification` and `Show fatal error hints: false`), with no
  real fatal/access/device-lost/assertion/verification hit.
- Reservation-loop summary had no command CSVs because the wrapper was killed
  after RPCS3 exit and before postrun CSV collection. It reports
  `command-correlation-data-missing` and `collect-missing-proof`.
- Window-title FPS samples were steady around `34.22`, but they are invalid for
  speed comparison because the visual route missed the field.
- Refiner now classifies the run as `failed-visual-gate` and says to back off
  to the last clean `loader-control-left200x2` boundary before adding any
  diagonal or HLE/GPU fast mode.

Classification:

- `failed-visual-gate`.
- `route-miss`.
- `cutscene-or-nonfield-frames`.
- Not valid field proof.
- Not reservation-loop counter proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not promote or reuse this `diag200` attempt as a valid diagonal boundary.
- Back off to the last clean `loader-control-left200x2` route and re-prove it
  with `CleanAfterField` before any diagonal movement, first-battle route, or
  HLE/GPU fast-mode work.

## 2026-05-28 loader-control left200x2 Backoff Reproof Black Overlay

Question:

- After the `left200x2+diag200` wrong-scene miss, can the last clean
  `loader-control-left200x2` boundary be re-proved with `CleanAfterField`
  before adding movement again?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-confirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows" -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Runtime host samples were clean at `149s`, `152s`, `180s`, and `210s`.
  Postrun was moderate only because Codex CPU was sampled after RPCS3 exited.
- RPCS3 reached the planned `215s` timeout and stopped. The wrapper then
  stalled after RPCS3 exit; no emulator process remained, so only the stuck
  PowerShell wrapper was killed before manual analysis.
- Visual gate failed: `NO_FIELD_LIKE_SCREENSHOT`, `16` screenshots, first
  field-like none, required field before `160s` failed, and all screenshots
  classified `black-overlay-small-png`.
- Manual image review of `screenshot-0117s.png` and `screenshot-0210s.png`
  confirmed black output with perf overlay only, not Path-to-Tenuto field.
- `stdout` and `stderr` were empty.
- Targeted fatal/access/device-lost/assertion/verification scan found only
  config text (`SPU Verification` and `Show fatal error hints: false`), with no
  real fatal/access/device-lost/assertion/verification hit.
- Reservation-loop summary had no command CSVs because the wrapper was killed
  after RPCS3 exit and before postrun CSV collection. It reports
  `command-correlation-data-missing` and `collect-missing-proof`.
- Window-title FPS samples are invalid for speed comparison because every
  screenshot was black-overlay output.
- Refiner now treats this as `failed-visual-gate` with a
  `repeated-black-overlay-pre-field` blocker and says to re-prove the newest
  clean `loader-control-left200x2` boundary before diagonal or fast-mode work.

Classification:

- `failed-visual-gate`.
- `black-overlay-pre-field`.
- `visual-route-proof-failed`.
- Not valid field proof.
- Not reservation-loop counter proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- This run did not recover the clean `left200x2` base.
- Latest valid visual base remains
  `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- Re-prove that boundary with `CleanAfterField`; do not move to diagonal,
  first-battle, HLE, or GPU fast-mode work until the black-overlay blocker is
  cleared.

## 2026-05-28 loader-control left200x2 Reproof Fatal After Field

Question:

- After the black-overlay backoff failure, can the newest clean
  `loader-control-left200x2` boundary be re-proved with `CleanAfterField`
  under `ReservationLoop Verify`?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Host checks were clean at prelaunch, postlaunch, runtime samples `149s`,
  `152s`, `180s`, `210s`, and postrun.
- RPCS3 reached the planned `215s` timeout and stopped. The wrapper then
  stalled after RPCS3 exit; no emulator process remained, so only the stuck
  PowerShell wrapper was killed before manual analysis.
- Visual gate failed:
  `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`, `16` screenshots, first
  field-like `screenshot-0138s.png` at `138s`, field before `160s` passed, but
  invalid screenshots after first field-like were `8`.
- Visual class counts were `5` field-like large PNGs, `5`
  cutscene-or-nonfield large PNGs, `3` cutscene-or-nonfield small PNGs, and
  `3` black-overlay small PNGs.
- Manual image review:
  - `screenshot-0138s.png` showed Path-to-Tenuto field.
  - `screenshot-0180s.png` showed a red/pink close-up cutscene/non-field frame.
  - `screenshot-0190s.png` showed black output with the RPCS3 likely-crashed
    overlay.
- `stderr` and `RPCS3.log` had real SPU fatal unknown STOP codes at about
  `0:03:07.77`, including TCX CellSpursKernel threads 0 through 4 with STOP
  codes `0x8a`, `0x24`, `0x24`, `0x26`, and `0x18`.
- Reservation-loop summary had no command CSVs because the wrapper was killed
  after RPCS3 exit and before postrun CSV collection. It reports
  `command-correlation-data-missing` and `collect-missing-proof`.
- Window-title FPS samples are invalid for speed comparison because the visual
  gate failed and fatal logs were present.
- Refiner classifies the run as `failed-fatal-log` and says not to extend it.

Classification:

- `failed-fatal-log`.
- `field-like-with-later-invalid-screenshots`.
- `crash-overlay-after-field`.
- Not clean field proof.
- Not reservation-loop counter proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- This run did not recover the clean `left200x2` base.
- Latest valid visual base remains
  `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- Do not extend this fatal route. Re-prove the clean boundary with
  `CleanAfterField`; if the same fatal repeats, treat `left200x2` as unstable
  under current loader-control timing and shrink/repair before adding movement.

## 2026-05-28 loader-control left200 Repair After left200x2 Fatal

Question:

- After `left200x2` failed three different ways in the recent window, does the
  lower one-pulse `left200` boundary still produce stable Path-to-Tenuto field
  visuals under `ReservationLoop Verify`?

Command:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:30000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir "debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows" -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir "debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows" -Top 12
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows`.
- `debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows\eternal-sonata-spu-reservation-loop-summary.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched through the Windows harness with `--game-screen 1`,
  reservation-loop verify, body/skip/GPU fast paths off, and CPU affinity
  `0x0F`.
- Host checks were clean at prelaunch, postlaunch, runtime samples `167s`,
  `180s`, `210s`, and postrun.
- RPCS3 reached the planned `225s` timeout and stopped. The wrapper then
  stalled after RPCS3 exit; no emulator process remained, so only the stuck
  PowerShell wrapper was killed before manual analysis.
- Visual gate passed: `FIELD_LIKE_PRESENT`, `16` screenshots, first field-like
  `screenshot-0117s.png` at `117s`, required field before `160s` passed, and
  invalid screenshots after first field-like `0`.
- All screenshots were full-size field-like PNGs. Manual review of
  `screenshot-0117s.png` and `screenshot-0220s.png` confirmed correct
  Path-to-Tenuto field visuals.
- Targeted crash scan found no real fatal/access/device-lost/assertion hit; it
  only matched the harmless config line `Show fatal error hints: false`.
- Reservation-loop summary had no command CSVs because the wrapper was killed
  after RPCS3 exit and before postrun CSV collection. It reports
  `command-correlation-data-missing` and `collect-missing-proof`.
- Refiner now marks the black-overlay control resolved at the lower boundary,
  but blocks another automatic `left200x2` rerun because that boundary has
  failed `3` times in the recent window.

Classification:

- `valid-field-triage`.
- `left200-lower-bound-repaired`.
- `visual-route-proof-only`.
- Not reservation-loop counter proof.
- Not Options/menu proof.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Lower `left200` remains clean under the current loader-control route.
- Do not repeat `loader-control-left200x2` yet; the recent failures are
  black-overlay, wrong-scene/non-field, and fatal-after-field.
- Next useful work is either route-control repair below/around the second
  pulse, or focused SPU kernel HLE/codegen/verifier analysis instead of another
  movement rerun.

## 2026-05-28 SPU verifier pivot audit after left200x2 block

Question:

- With `loader-control-left200x2` blocked by the refiner, can existing logs
  support a 25cc descriptor/counterproof claim, or are they only SPU atlas target
  selection?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\summarize_eternal_sonata_spu_hle_candidates.ps1 -MaxRuns 8
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows
```

Artifacts:

- `debug-captures\windows-lab\_ps3-harness-refiner-latest.md`.
- `debug-captures\windows-lab\_eternal-sonata-spu-hle-candidates-latest.md`.
- Ignored local counterproof summaries under the two audited run directories.

Evidence:

- Refiner again blocks automatic `loader-control-left200x2`: it failed `3`
  times in the recent 8-run window after lower `left200` stayed clean.
- HLE atlas used `3` valid field runs and excluded `2` fatal field-like runs.
  Top stable bucket is PC `0x25cc`, `CellSpursKernelGroup` /
  `CellSpursKernel0`, `3.68 GB`, `2313` records, GET `552.10 MB`, PUT
  `3.14 GB`, max job `4.35 MB`, and `0 B` RSX-local.
- `20260528-172735` stayed clean visually and had zero targeted fatal hits, but
  dedicated 25cc counterproof parsing found `0` shadow verifier hits and `0`
  descriptor rows.
- `20260528-151432` is still a valid field/atlas run, but the same parser also
  found `0` 25cc shadow verifier hits and `0` descriptor rows.
- Therefore the loader-control atlas is useful for choosing the CPU-pressure
  target, but it is not descriptor/hash proof. Future verifier work must use the
  explicit `Verify25ccShadow`/descriptor route, with `20260528-132515` as the
  clean field counterproof reference.

Classification:

- `analysis`.
- `spu-hle-codegen-verifier-target-selection`.
- `failed-counterproof` for the two audited loader-control logs.
- Not route extension.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not run another `left200x2` movement attempt until route control is
  repaired.
- Do not treat loader-control SPU atlas bytes as 25cc descriptor proof.
- Next useful work is either an explicit `Verify25ccShadow` descriptor proof
  re-run on the clean field route, or code/harness work that preserves descriptor
  rows before wrapper postrun stalls.

## 2026-05-28 25cc proof matrix audit

Question:

- Which proof surfaces currently have real 25cc descriptor rows, valid visuals,
  and clean fatal/counter state?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260526-174450-cpu4-hle-25cc-shadow-desc-options-fastselect-proof-windows
Get-Content .\debug-captures\windows-lab\20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows\eternal-sonata-25cc-counterproof-summary.md
Get-Content .\debug-captures\windows-lab\20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows\eternal-sonata-25cc-counterproof-summary.md
Get-Content .\debug-captures\windows-lab\20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows\eternal-sonata-25cc-counterproof-summary.md
```

Evidence:

- Field surface is valid: `20260528-132515` is `valid-field-counterproof`,
  visual status `FIELD_LIKE_PRESENT`, first field `117s`, targeted fatal hits
  `0`, 25cc descriptors `22008` rows / `23643` hits / `369.42 MB`, GET/PUT
  `10998/12645`, output mismatches `0`, descriptor overflow `0`.
- Options descriptor surface exists only as legacy-format evidence:
  `20260526-174450` has 25cc descriptors `11988` rows / `12768` hits /
  `199.50 MB`, GET/PUT `5988/6780`, output mismatches `0`, overflow `0`, and
  targeted fatal hits `0`, but the current counterproof parser reports visual
  status `missing` because that older run has no standard visual-gate summary.
- Current-format Options visual proof exists separately as reservation-loop
  proof `20260528-062448`; it is not the same as 25cc descriptor proof.
- First-battle descriptor attempts are counter-clean but visually invalid:
  `20260528-135315` logged `31263` 25cc hits / `488.48 MB` with zero 25cc
  mismatch/overflow, and `20260528-154248` logged `29703` hits / `464.11 MB`
  with zero 25cc mismatch/overflow. Both have visual status
  `NO_FIELD_LIKE_SCREENSHOT` / black-overlay and cannot count.

Classification:

- `analysis`.
- `proof-gap-audit`.
- Field: `valid-field-counterproof`.
- Options: `partial-counterproof` / legacy visual status missing.
- Battle: `partial-counterproof` / invalid visuals.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Do not promote 25cc body/fast/codegen from descriptor cleanliness alone.
- Next non-duplicate proof should be either current-format Options
  `Verify25ccShadow` reproof or first-battle route repair that produces valid
  visuals while retaining the 25cc descriptor rows.

## 2026-05-28 current-format 25cc Options counterproof

Question:

- Can the 25cc descriptor/shadow verifier produce a current-format title
  Options proof, closing the gap left by the legacy Options descriptor run and
  the separate reservation-loop Options visual proof?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -InputMacro "wait:65000;shot:title-preinput;down:160;wait:600;shot:title-after-down1;down:160;wait:600;shot:title-after-down2-fast;cross:180;wait:6000;shot:options-candidate;wait:10000;shot:options-late" -MaxSeconds 130 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 65 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260528-182410-cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof-windows -ManualVisualKind Options -ManualVisualEvidence "screenshot-0079s-options-candidate.png and screenshot-0089s-options-late.png show full Options page with live FPS overlay"
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-182410-cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof-windows`.
- `debug-captures\windows-lab\20260528-182410-cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof-windows\eternal-sonata-25cc-counterproof-summary.md`.
- `debug-captures\windows-lab\_ps3-harness-refiner-latest.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched with `--game-screen 1`, CPU affinity `0x0F`,
  `Verify25ccShadow`, GPU probe profile mode, and body/skip/GPU fast paths off.
- Host checks were clean at prelaunch, postlaunch, runtime samples `90s` and
  `120s`, and postrun.
- Manual screenshot review confirmed the full title Options page at
  `screenshot-0079s-options-candidate.png` and
  `screenshot-0089s-options-late.png`; both had live FPS overlays.
- Stdout/stderr were empty. Targeted fatal/access/device-lost/assertion scan
  across stderr, RPCS3 log, and lab log found `0` hits.
- 25cc verifier summary: `9498` hits / `148.41 MB`, GET/PUT `4473/5025`,
  match/mismatch `9498/0`, changed/unchanged `1958/7540`.
- 25cc descriptor summary: `8958` rows / `9498` hits / `148.41 MB`, GET/PUT
  `4473/5025`, output mismatches `0`, descriptor overflow `0`.
- Generic non-25cc shadow mismatches still appeared at PC `0x451c`, so the
  proof is limited to the 25cc descriptor lane.
- The wrapper again stalled after RPCS3 exited; no emulator process remained,
  so only the stale PowerShell wrapper was killed before manual analysis.
- `tools\summarize_eternal_sonata_25cc_counterproof.ps1` was tightened to
  accept explicit manual visual kind/evidence and classified this run as
  `valid-options-counterproof`.
- Refiner after the run says field and Options should not be rerun; first
  battle under `Verify25ccShadow` is the next proof target.

Classification:

- `valid-options-counterproof`.
- `verify-only`.
- `25cc-descriptor-clean`.
- Not speed.
- Not `gpu-migration-credit`.
- Not first-battle proof.
- Not a 200% gate candidate.

Decision:

- Current-format 25cc field and Options/menu proofs are now both clean.
- Bodyfast/codegen/stack promotion remains blocked until first-battle visuals
  are valid with the same 25cc mismatch/overflow discipline.

## 2026-05-28 first-battle Verify25ccShadow fatal isolation

Question:

- After current-format field and Options counterproofs passed, can the same
  25cc descriptor/shadow verifier survive the TopSlot first-battle route?

Commands:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireBattleLikeAtOrAfterSeconds 220 -RequireNoInvalidAfterFirstField
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows`.
- `debug-captures\windows-lab\20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-counterproof-summary.md`.
- `debug-captures\windows-lab\_ps3-harness-refiner-latest.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched with `--game-screen 1`, TopSlot BattleRoute, CPU affinity
  `0x0F`, `Verify25ccShadow`, GPU probe profile mode, and body/skip/GPU fast
  paths off.
- Host checks were clean at prelaunch, postlaunch, runtime samples `291s`,
  `300s`, `330s`, and postrun. Host contention gate `ExternalFail` passed.
- RPCS3 reached the planned `330s` timeout and stopped. The wrapper again
  stalled after RPCS3 exit; no emulator process remained, so only the stale
  PowerShell wrapper was killed.
- Targeted fatal scan found a real PPU VM access violation at `0x002aedd0`
  reading `0x40` in both stderr and `RPCS3.log`.
- Manual screenshots: `screenshot-0117s.png` is clean Path-to-Tenuto field.
  `screenshot-0169s.png`, `screenshot-0230s.png`, and `screenshot-0320s.png`
  show the RPCS3 likely-crashed overlay and corrupt/frozen field output.
- Visual gate status was `FIELD_LIKE_PRESENT` with first field at `117s`, but
  required battle-like at or after `220s` failed with `0` battle-like frames.
- 25cc verifier summary: `10833` hits / `169.27 MB`, GET/PUT `4953/5880`,
  match/mismatch `10833/0`, changed/unchanged `2939/7894`.
- 25cc descriptor summary: `9918` rows / `10833` hits / `169.27 MB`, GET/PUT
  `4953/5880`, output mismatches `0`, descriptor overflow `0`.
- Generic non-25cc shadow mismatches remained at PC `0x451c`; this still blocks
  broad shadow claims.
- Refiner after the run says not to rerun this verifier command unchanged and
  not to reset to loader-control. It recommends the same TopSlot BattleRoute
  with `Verify25ccShadow` off to isolate route fatal versus verifier fatal.

Classification:

- `failed-fatal-log`.
- `failed-visual-gate`.
- `partial-counterproof`.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- First-battle proof remains the blocker.
- The next non-duplicate step is a stock-control TopSlot BattleRoute with
  `Verify25ccShadow` off, same route/host/display settings.

## 2026-05-28 stock-control TopSlot route device-loss isolation

Question:

- Does the same TopSlot BattleRoute still fail when `Verify25ccShadow` is off,
  separating route/RSX instability from 25cc verifier instability?

Commands:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
```

Artifacts:

- `debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`.
- `debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows\eternal-sonata-windows-visual-gate-summary.md`.
- `debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows\eternal-sonata-gpu-probe-summary.md`.
- `debug-captures\windows-lab\_ps3-harness-refiner-latest.md`.

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched with `--game-screen 1`, TopSlot BattleRoute, CPU affinity
  `0x0F`, frame/vblank `240`, GPU probe profile mode, and
  `Verify25ccShadow` off.
- Host checks were clean at prelaunch, postlaunch, runtime samples `291s`,
  `300s`, `330s`, and postrun. Host contention gate `ExternalFail` passed.
- Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`: all `15` screenshots were
  `black-overlay-small-png`, each `34882` bytes. Manual review of
  `screenshot-0117s.png` confirmed black output with only the perf overlay.
- There was no field-like screenshot at or before `160s`, no field-like
  screenshot at or after `220s`, and no battle-like screenshot at or after
  `200s`.
- Targeted fatal scan found real RSX `VK_ERROR_DEVICE_LOST` / device-lost
  failure in `vk::wait_for_event` in `rpcs3.stderr.txt` and `RPCS3.log`.
- GPU probe summary logged `753` records, `724.84 MB` observed DMA, `0`
  RSX-local traffic records, `0` indirect RSX resource overlap records, and
  offload fit mix `too-small=411`, `spu-kernel-hle=342`.
- Hot PC summary: `0x451c` had `502.62 MB`; `0x25cc` had `222.22 MB`, with
  repeated `0x9e4000` patterns but still `0 B` RSX-local.
- Because `Verify25ccShadow` was off, there are no 25cc descriptor/shadow rows
  to use as counterproof.
- Refiner after the run says not to extend the latest fatal route. It
  recommends re-proving the newest clean `loader-control-left200x1` boundary
  with `CleanAfterField` before adding another pulse.

Classification:

- `failed-fatal-log`.
- `failed-visual-gate`.
- `route-rsx-device-loss-isolation`.
- Not first-battle proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- The stock-control route also fails, so the previous first-battle verifier
  fatal is not isolated to `Verify25ccShadow`.
- Do not repeat TopSlot BattleRoute or extend movement from this failure.
- Next action is the refiner command: re-prove the clean
  `left200x1` loader-control boundary, then only add route complexity after
  visuals and fatal logs are clean.

## 2026-05-28 left200x1 refiner reproof fatal

Question:

- Does the clean `left200x1` loader-control boundary still hold after the
  TopSlot stock-control failure?

Command:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

Artifacts:

- `debug-captures\windows-lab\20260528-192415-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows`

Evidence:

- No active `rpcs3` or `rpcsx` process existed before the run.
- RPCS3 launched on screen 1 with CPU affinity `0x0F`.
- Manual review: `screenshot-0136s.png` showed the correct Path-to-Tenuto
  field.
- Manual review: `screenshot-0190s.png` showed black output with RPCS3's
  likely-crashed overlay.
- Visual gate status was `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`:
  first field-like at `136s`, then invalid frames after field.
- Fatal scan found real SPU unknown STOP codes in stderr/RPCS3 log, including
  `TCX_CellSpursKernel4 [0x25a40] Unknown STOP code 0x0`,
  `TCX_CellSpursKernel0 [0x05240] Unknown STOP code 0x0`,
  `TCX_CellSpursKernel1 [0x3be40] Unknown STOP code 0x18`,
  `TCX_CellSpursKernel3 [0x09240] Unknown STOP code 0x2c`, and
  `TCX_CellSpursKernel2 [0x0f644] Unknown STOP code 0x23`.
- Host checks were clean.
- The wrapper stalled after RPCS3 exited and was killed; no emulator process
  remained active.

Classification:

- `failed-fatal-log`.
- `failed-visual-gate`.
- Not movement proof.
- Not speed.
- Not `gpu-migration-credit`.
- Not first-battle proof.
- Not a 200% gate candidate.

Decision:

- Do not keep rerunning or extending the loader-control movement ladder from
  this state.
- The next useful work is focused SPU contract/compiler analysis unless a new
  route repair is explicitly justified by the refiner.

## 2026-05-28 SPU contract compiler scaffold

Question:

- Can the repeated hot SPU evidence be converted into durable contracts before
  any new HLE/codegen fast path?

Command:

```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

Artifacts:

- `tools\spu_contract_pipeline.ps1`
- `.agents\skills\ps3-spu-contract-compiler\SKILL.md`
- `debug-experiments\20260528-spu-contract-pipeline-plan.md`
- `spu-contracts\BLUS30161\latest-summary.md`
- `spu-contracts\BLUS30161\index.json`

Evidence:

- The pipeline extracted two SPU windows from the stock-control TopSlot run:
  `0x25cc` / `CellSpursKernel0` and `0x451c` /
  `TCX_CellSpursKernel0`, both image signature
  `0x958dfe208b686622`.
- Both contracts emitted runtime log evidence, source disassembly anchors, Cell
  semantics requirements, and verify-only requirements.
- `0x25cc` sample evidence includes dynamic MFC/SPURS logging and repeated
  max-DMA `0x9e4000` records with `output_mismatches=0`.
- `0x451c` sample evidence now uses canonical PC matching, so leading-zero
  disasm filenames do not hide the actual log evidence.

Classification:

- `analysis`.
- `spu-contract-scaffold`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Decision:

- Adopt the contract compiler as the default SPU path:
  runtime logs -> SPU windows -> Ghidra headless/static tightening -> contract
  JSON -> verify-only emulator counters -> fast path.
- First implementation target remains `0x25cc/0x9e4000`; `0x451c` is tracked
  as a separate TCX/SPURS pressure lane.

## 2026-07-14 Current-Upstream First-Battle Counterproof

Question:

- Is the recurring `0x002ad588` / `0x002aedd0` draw-parser failure inherent to
  the route, or fixed by current upstream RPCS3?

Evidence:

- Official RPCS3 `0.0.41-19570-49b0306b` completed the corrected Windows route
  in
  `debug-captures/windows-lab/20260714-231021-official19570-extendedkey-first-battle-windows`.
  Visuals showed the enemy field, tutorial prompt, and active tutorial combat;
  the active battle remained clean at `30 FPS` for roughly `34s` with no unknown
  draw, access violation, or fatal hit.
- The lab keyboard injector now emits the Win32 extended-key flag for navigation
  keys. This fixed arrow input in the official binary and is required for the
  route above to be valid.
- The older instrumented Windows base permitted one CellSpurs JobChain
  `PUTLLC16` pattern even with Accurate SPU Reservations enabled. Upstream
  `e379fba` disables that hash. This explains the old Windows failure and the
  current official pass.
- Android already skipped all `PUTLLC16` emission when Accurate SPU Reservations
  is enabled, so `e379fba` is not by itself the remaining Android fix. Its fresh
  log showed no emitted `PUTLLC16` pattern; the only completed special loop was
  the `RCHCNT` loop at `0xa7c` for function hash
  `7PiXnkUPiv7ZdGvUkndsHKRu6ZNZ`.
- Ghidra maps the corrupt guest stream to producer `0x002f7540`, publish call
  `0x002f76a4`, publish helper `0x002ac618`, consumer `0x002afce0`, and parser
  `0x002acbc8`. The object owns two `0x180000`-byte command buffers at `+0x14`
  and `+0x18`, with write pointer `+0x1c` and index/flags `+0x20`. Corrupt float
  payload can decode as valid-looking opcodes before reaching the fatal handlers
  at `0x002ad588` or `0x002aedd0`, so a first-unknown-opcode parser guard was
  insufficient.

Classification:

- `valid-current-upstream-windows-battle-counterproof`.
- `android-field-clean-battle-route-missed` for the guarded `A7D5A6...` core.
- Not Android battle proof.
- Not speed promotion.

Decision:

- Keep the Android backport of upstream `7d0df30` for blocking output-mailbox
  channel loops and `42242b3` for the Giga analyzer divisor repair.
- The next Android proof must first repair the route collision/state gate, then
  use one cool-device guarded run. A screenshot filename alone is not battle
  evidence.

## 2026-07-15 Offline Command-Handoff Trace and Host Semaphore Backport

Question:

- Can the intermittent Android draw-stream corruption be explained by the
  producer reusing a command buffer while the consumer is still parsing it,
  and is there a current-upstream synchronization optimization worth taking
  without another hot-device route?

Static evidence:

- A cross-run audit found zero unknown-draw or fatal-parser hits in the valid
  current-upstream Windows controls, while Android first-battle runs remain
  intermittent: some produce float-like unknown commands only, some reach the
  `0x002ad588` / `0x002aedd0` fatal family, and the latest RCHCNT-fallback run
  remained live but still logged six unknown commands. A single live battle is
  therefore not stability proof.
- New Ghidra decompilation in
  `debug-captures/ghidra-eboot-20260714-parser/producer-coordination-decompile.txt`
  shows that producer calls `0x002ea0b8` and `0x002ea490` are ordinary render
  preparation, not locks or semaphore operations.
- The actual wrapper at `0x002f76f8` publishes through `0x002f7540`, then calls
  `0x002ac7b0` and `0x002ac808`. `0x002ac7b0` sets object flag bit 2, waits on
  the completion semaphore at object `+0x50`, then posts the consumer-work
  semaphore at object `+0x38`. `0x002ac808` waits for the consumer completion,
  restores the `+0x50` token, performs frame housekeeping, and clears bit 2.
- The consumer loop at `0x002afce0` waits on the `+0x38` work semaphore before
  parsing. Its terminator path posts `+0x50`. The producer therefore does not
  begin the next frame until the prior parse is complete, and it does not wake
  the consumer until after the new buffer is published. Buffer reuse overlap is
  ruled out by the guest protocol.
- Host `atomic_t::compare_and_swap_test` is sequentially consistent, including
  the fast semaphore wait/post path. Together with the synchronous guest
  handshake, this rejects another generic publication fence. The earlier
  Android-only acquire/release fence was correctly removed after its repeat
  fatal; do not reintroduce it.

Current-upstream backport:

- Official upstream was refreshed through `1269ebf`. Commit `537ad39`
  (`Utilities/sema.cpp: Minor optimization`) applies cleanly to the Android
  fork's host semaphore utility.
- `semaphore_base::imp_wait()` now returns `false` from its atomic update when
  a waiter is already registered and no signal is available. This skips a
  redundant no-op atomic RMW/CAS before the waiter sleeps again. Signal
  acquisition, waiter registration/removal, notification, and memory ordering
  are unchanged.
- Optimized ARM64 validation command:
  `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain`. It completed successfully in `1m 10s`.
- Host-built core SHA256:
  `A599F9BC1A6DCD2C718ED17A6DE76DE4E47F0E2347B0C9E9C38F972E48144681`.
  It was not deployed or launched. The installed Thor core and its provisional
  exact RCHCNT fallback remain unchanged. Final read-only verification found
  RPCSX stopped at `27.0 C`, battery `77%`, and thermal status `0`.

Classification:

- `offline-static-analysis`.
- `upstream-host-semaphore-overhead-backport`.
- `buffer-reuse-overlap-rejected`.
- Not Android battle proof.
- Not stability or FPS promotion.

Decision:

- Keep the small upstream host-semaphore optimization; it is generic, preserves
  ordering, and reduces useless host atomic traffic in a known high-volume wait
  path.
- Keep the exact RCHCNT fallback provisional and retain the fail-closed unknown
  draw gate. The next separately cool Thor proof must be a warm-cache repeat;
  it must stop at the first unknown draw and cannot earn speed credit unless the
  full battle route stays clean.

## 2026-07-15 RCHCNT Warm-Cache Counterproof

Question:

- Does the exact Android/BLUS30161 `0xa7c` RCHCNT-loop fallback pass its required
  fail-closed warm-cache battle repeat?

Evidence:

- Core `A599F9BC1A6DCD2C718ED17A6DE76DE4E47F0E2347B0C9E9C38F972E48144681`
  ran one guarded route in
  `debug-captures/android-speed-sprint/20260715-202904-thor-input-eternal-sonata-battle-intro-route`.
- The guest log proved the exact RCHCNT skip activated at `0:00:32.243886`.
  The field remained visually clean at `27.78 FPS`, and the first bounded
  approach reached a clean tutorial prompt at `30.00 FPS`.
- Guest time `0:02:48.709891` produced unknown draw command `30b12f20`, already
  present in the first fallback proof. The strict route gate force-stopped the
  app immediately at `battle-approach-1`. There was no fatal guest or native
  crash before the controlled stop.
- RAM peaked at `11229 MB` and fell to `9098 MB`; all thermal samples were
  `27.0 C`. No second run, recorder, Perfetto trace, or sustained profiler was
  used.

Classification:

- `failed-guest-draw-stream-gate`.
- `clean-field-and-tutorial-before-stop`.
- Not active-battle proof.
- Not speed or stability promotion.
- `max-first` / `pro-max` memory risk.

Action:

- Removed the exact Android/title/hash RCHCNT exception and restored upstream
  RCHCNT-loop analysis. The optimized ARM64 rebuild passed in `1m 1s` and was
  deployed without launching as core
  `F0B66982FDF481F42E0C82AA59F5EB8D3DAA99BD9F4F8904E1FA50CD3EBE8F3B`.
- Retained the generic upstream host-semaphore wait optimization because this
  result cannot isolate it from the already-disproven RCHCNT candidate. It has
  no measured FPS credit.
- Final state: RPCSX stopped, `27.0 C`, battery `77%`, thermal status `0`.

Decision:

- Reject the exact RCHCNT fallback. Do not repeat or reintroduce it. Keep the
  fail-closed unknown-draw gate and return to offline root-cause analysis before
  spending another Thor run.

## 2026-07-15 Offline Published-Buffer Verifier

Question:

- Can the next bounded route distinguish a command word already present when
  the producer publishes the draw stream from a mutation between semaphore
  handoff and parser execution, without another speculative ordering change?

Exact hook proof:

- Producer wrapper `0x002ac7b0` calls the one-count work post at
  `0x002ac7ec`. At the syscall, `CIA=0x0031c1bc`, `LR=0x002ac7f0`, and
  preserved `r29` is command object `+0x38`.
- Consumer loop `0x002afce0` calls the work wait at `0x002afd04`. On the
  successful syscall return, `CIA=0x0031c18c`, `LR=0x002afd08`, and preserved
  `r30` is the same object `+0x38`.
- Object fields `+0x14` / `+0x18` are the two `0x180000`-byte command buffers,
  `+0x1c` is the current write pointer, and `+0x20` contains the selector flags.
  The published buffer is the slot opposite flags bit 0, matching the parser's
  Ghidra-proven selection at `0x002acc24..0x002acc4c`.
- On an `unknown draw command` print, parser nonvolatile `r31` is the cursor
  after the fetched word and `r22` is the command object. Those registers are
  sampled only for that exact TTY string and only while the snapshot is valid.

Implementation:

- Added the off-by-default Android property
  `debug.rpcsx.thor.es_draw_stream_probe=verify` and environment gate
  `RPCSX_THOR_ES_DRAW_STREAM_PROBE=verify`. Accepted true values are explicit;
  arbitrary values fail closed.
- Before the exact producer post mutates the semaphore, copy the entire
  published buffer into one reusable host vector. This occurs while the guest
  protocol still keeps the consumer asleep.
- After the exact consumer wait succeeds, compare the complete live buffer to
  the producer snapshot before the parser call. Matching generations are
  counted; mismatches always log the first byte and aligned producer/live word.
- If the guest later prints `unknown draw command`, log the producer snapshot
  word at `r31-4`, its live value, five producer-context words, the parser and
  snapshot objects, and the preceding handoff result. This makes the next
  failure self-classifying instead of relying on the printed opcode alone.
- The verifier does not write guest memory, inject fences, change semaphore
  values, skip parser work, or modify syscall results. Allocation and the
  1.5 MiB copy/compare are verify-only. When disabled, inlined wrappers test
  the cached false gate and do not enter the large probe functions.

Offline validation:

- First compile exposed and fixed one `umax` overload ambiguity in a defensive
  object-address bounds check.
- Final optimized ARM64 command:
  `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain`.
- Result: `BUILD SUCCESSFUL in 1m 9s`; only existing deprecated enum-operator
  warnings appeared.
- Host core SHA256:
  `EB88FF4373292B400A0617E7396EC076010674CCF6FE2044875B99716C684785`.
- Binary string verification found the property name plus the handoff-mismatch
  and parser-fault records in the linked ARM64 core.
- No ADB action, deployment, launch, capture, profiler, or device sensor query
  was performed. Installed Thor core remains
  `F0B66982FDF481F42E0C82AA59F5EB8D3DAA99BD9F4F8904E1FA50CD3EBE8F3B`.

Classification:

- `offline-verify-instrumentation`.
- `producer-consumer-byte-proof`.
- Default off; not a normal benchmark mode.
- Not a speed, battle, or stability promotion.

Decision:

- Keep the verifier. The next device spend, when separately cool, should be one
  short fail-closed route with only this gate enabled. A matched handoff plus a
  matching producer/live fault word proves that the producer published the bad
  word; a mismatched handoff identifies a post-publication memory mutation. If
  the snapshot word differs while the live handoff still matches, investigate
  parser/JIT cursor state rather than guest synchronization.

## 2026-07-15 Windows SPU Contract Verifier Accounting Fix

Question:

- Can the priority `0x25cc / 0x9e4000` verifier row be trusted as a promotion
  gate before any behavior-changing compiler work?

Audit result:

- Not as previously emitted. `reject_eah` compared the recorded low effective
  address (`eal`) against zero, so every normal non-zero transfer falsely
  inflated the EAH bucket. Existing captured rows showed the symptom directly:
  for example `reject_eah=18` alongside valid `eal=0xa1c000` samples.
- The contract row also printed PC/tag/size/EAL and hashes from the last shadow
  sample across all accepted 25cc families. A valid 0x9e4000 hit could therefore
  be labeled with a later 0xa1c000 anchor while still passing the parser.
- The parser checked row shape, identity, GET/PUT split, mismatch, and overflow,
  but did not validate the fixed contract anchors, byte arithmetic, reject sum,
  or blocked fast-mode leakage.

Fix:

- In the clean Windows checkout, changed only
  `rpcs3\Emu\Cell\lv2\sys_spu.cpp`. The row now emits fixed target anchors and
  accumulates hashes/output mismatches only from family 1 at `eal=0x9e4000`.
- Left `reject_eah=0` for recorded descriptors, with an explicit source comment:
  the runtime classifier already rejects `cmd.eah != 0` before a descriptor can
  be stored. No EAH value is fabricated from EAL.
- Extended the repo-local schema/parser with exact anchor checks,
  `contract_bytes == contract_hits * 16384`, reject-bucket sum validation, and
  fast-mode rejection. Non-target accepted EAL families remain visible in
  `reject_eal_family`; they are diagnostics and are not relabeled as target hits.
- Windows source commit:
  `7bddf372c566ef5958ec9093e935f3744d8aca5e`.

Validation:

- `cmake --build build-msvc --config Release --target rpcs3 --parallel 8`
  completed successfully in `1688.7 s`, including `sys_spu.cpp` and final LTCG
  link. The resulting executable SHA256 is
  `BDCD118BB513178A72885B072840316048B5FD8DE1D144640CF5CB55ABAC47B5`.
- Strict synthetic parser matrix passed: one valid two-hit row exited `0`;
  wrong EAL, wrong byte count, wrong reject sum, `body_mode=fast`, and non-zero
  `reject_fast_mode` each exited `2` with the expected failure.
- No game was launched. No Android build, ADB query, deployment, capture, or
  Thor sensor read occurred; the handheld was not heated or disturbed.

Classification:

- `windows-offline-verifier-fix`.
- `verify-only-contract-accounting`.
- Not a runtime correctness result, FPS result, or 200% gate candidate.

Decision:

- Keep the corrected verifier and parser. The next meaningful evidence is one
  bounded Windows `verify-25cc-shadow` capture from a genuinely valid route,
  followed by the strict parser and field/menu/first-battle visual checks.
- Do not enable a 25cc body fast path or port this contract lane to Android from
  compile-only evidence.

## 2026-07-15 Windows Reservation-Priority Repair and Runtime Counterproof

Question:

- Does the corrected priority-1 `0x25cc / 0x9e4000` verifier remain clean on a
  genuinely moving field route, and is the prior draw-stream/VM failure caused
  by missing upstream SPU reservation safety rather than the verifier contract?

Source repair:

- The instrumented Windows checkout was based near RPCS3 `0.0.41` and did not
  contain upstream commit `e379fba` (`SPU/PPU: Implement PPU reservation
  priority over SPUs`). That upstream change also disables the unsafe
  CellSpurs JobChain acquire pattern hash
  `620oYSe8uQqq9eTkhWfMqoEXX0us`, matching the standing draw-stream failure
  diagnosis.
- Cherry-picked the exact upstream commit into the local Windows checkout as
  `e12beb222fea26fa5e5f86fa507ad91536fa4d60`. The tree configured as
  `0.0.41-597-e12beb22`; Release/LTCG build and link succeeded.
- Exact rebuilt `rpcs3.exe` SHA256:
  `C31622E54441A6946A9AFC6986E8F7C9193F55541E158B2959BEE95B07AA3CC9`.
- Rotated only the title-local `spu-safe-v1-tane.dat` cache before the replay;
  PPU and shader caches remained warm.

Matched Windows replay:

- Pre-fix run
  `debug-captures/windows-lab/20260715-214109-cpu4-verify25cc-corrected-contract-extendedkey-first-battle-windows`
  reached a clean field, then produced repeated `unknown draw command` lines,
  a PPU VM access violation at `0x002aedd0` reading `0x40`, and a corrupt frozen
  field/crash overlay. Its corrected contract rows were internally clean
  (`473/473` accepted, `1023` hits, mismatch/overflow `0`), so it remained a
  failed fatal/visual result.
- Post-fix run
  `debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows`
  used the same keyboard macro, CPU affinity `0x0f`, 30 FPS frame cap, 60 Hz
  vblank, Accurate SPU Reservations on, Accurate SPU DMA off, verifier on, and
  25cc body off.
- Manual frame review confirmed the correct Path-to-Tenuto field at `139s` and
  live enemy/field animation through the `185s` cutoff. Despite their scripted
  filenames, the `155s`, `161s`, and `171s` frames did not enter battle; they
  remained moving-field evidence.
- Fatal scan: unknown draw `0`, access violation `0`, unknown STOP `0`,
  `VK_ERROR` `0`, device-lost `0`, assertion `0`, crash-overlay signature `0`,
  fatal-channel rows `0`. All five host snapshots were external-clean.
- Strict contract parse passed: `732/732` rows accepted, `0` rejected,
  `1878` target hits, `30769152` target bytes, `26295` non-target contract
  rejects, output mismatch `0`, descriptor overflow `0`. Promotion remains
  false because field/menu/first-battle proof is external.

Harness fixes:

- Clean-field and BattleRoute visual gates now also fail on RPCS3 fatal/crash
  log signatures, closing the false `FIELD_LIKE_PRESENT` result seen on the
  corrupt pre-fix run.
- BattleRoute now rejects `MaxSeconds < 220` before launch because the gate
  requires late-field evidence at `220s`; scripted screenshot labels alone no
  longer justify a battle claim.
- High-frequency wait-PC and 25cc descriptor records receive direct parser
  dispatch. Logs larger than `32 MiB` defer the generic probe summary instead
  of holding the completed Windows run open for more than a minute.

Classification:

- `valid-moving-field-counterproof`.
- `upstream-reservation-stability-fix`.
- `verify-only-contract-runtime-proof`.
- Not first-battle proof, not an FPS result, not GPU migration, and not a 200%
  gate candidate.

Decision:

- Keep upstream reservation-priority commit `e379fba` in the Windows source
  line and keep the corrected verifier. The prior fatal/corrupt result is no
  longer the newest source-aligned evidence.
- Do not promote bodyfast or port this lane to Android yet. The exact rebuilt
  binary still needs Options/menu and a real first-battle capture under the
  same proof discipline before any behavior-changing specialization.
- No Android build, ADB query, deployment, launch, capture, or Thor sensor read
  occurred in this round; the handheld remained untouched.

## 2026-07-15 Exact-Binary Options Counterproof

Question:

- Does the source-aligned `e12beb22` Windows binary preserve the full title
  Options page under the corrected priority-1 contract verifier?

Run:

- `debug-captures/windows-lab/20260715-223137-cpu4-verify25cc-e379fba-options-fastselect-windows`.
- Exact binary SHA256:
  `C31622E54441A6946A9AFC6986E8F7C9193F55541E158B2959BEE95B07AA3CC9`.
- Keyboard macro:
  `wait:65000;shot:title-preinput;down:160;wait:600;shot:title-after-down1;down:160;wait:600;shot:title-after-down2-fast;cross:180;wait:6000;shot:options-candidate;wait:10000;shot:options-late`.
- Config matched the repaired field proof: CPU affinity `0x0f`, frame cap `30`,
  vblank `60`, Accurate SPU Reservations on, Accurate SPU DMA off,
  `Verify25ccShadow` on, and 25cc body off.

Evidence:

- Manual review proved the title selection sequence (`NEW GAME` -> `LOAD` ->
  `OPTIONS`) and the complete Options page at `78s`, `88s`, and `130s`.
  Battle Camera, Attack Button, Vibration, all volume controls, subtitles,
  voice, and language rendered correctly with no flicker or missing UI.
- All six host snapshots were clean/external-clean. Targeted log scan found
  unknown draw `0`, access violation `0`, unknown STOP `0`, `VK_ERROR` `0`,
  device lost `0`, assertion `0`, crash-overlay signature `0`, and fatal-channel
  rows `0`.
- Strict contract parse passed: `461/461` rows accepted, `0` rejected, `957`
  target hits, `15679488` target bytes, output mismatch `0`, descriptor overflow
  `0`.
- The new `32 MiB` synchronous-summary ceiling worked: the `45119486`-byte log
  deferred generic analysis and the wrapper completed normally in `137.7s`
  instead of hanging after RPCS3 stopped.

Classification:

- `valid-options-counterproof`.
- `verify-only-contract-runtime-proof`.
- Not speed, not first battle, not GPU migration, and not a 200% result.

Decision:

- Bank exact-binary field and title Options correctness. Do not rerun either
  capped proof. The remaining correctness gate is a genuine first battle on the
  same binary/config/proof discipline; only after that should uncapped speed A/B
  or behavior-changing 25cc specialization be considered.
- No Android, ADB, deployment, Thor launch, capture, or sensor action occurred.
