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
