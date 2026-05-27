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
