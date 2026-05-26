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
