# 2026-05-29 SPU Contract Pipeline Round



## 2026-05-29 04:50:49-04:00 Loader-Control Left200x2 Tiny-Pulse Re-proof

## Run Stamp
- Timestamp: `2026-05-29T04:50:49-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control-left200x2-diag200 field proof is clean and verifier/hash/native-contract are refreshed; prove direction-split 0x25cc counters next.`
- Route pressure state: clean field triage on the diagonal replay of `left200x2`; no movement proof or speed promotion beyond route tooling.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;combo:ls_left+ls_down:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## Run Dir
- `debug-captures\windows-lab\20260529-045051-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-045051-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`
- Classification: `FIELD_LIKE_PRESENT`.
- Screenshot status: `18` field-like large-PNG frames, no invalid-after-field.
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`).
- Host contention: clean (`7` snapshots); postrun clean.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-045051-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\RPCS3.log`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`.
- Targeted fatal/log scan: only `Show fatal error hints: false` in `RPCS3.log`; no VM access violation, `SPU: Unknown STOP`, device-lost, or assertion crashes.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-045051-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`
- `Classification: failed-counterproof` (`0` 25cc shadow descriptor/ verifier rows; no 25cc mismatch signal due missing contract-row emission).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-045051-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`
- Reservation-loop summary: `collect-missing-proof` due missing command/pair/kernel CSVs (`command-correlation-data-missing`).

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\latest-summary.md` and related verify scaffolding unchanged this cycle.
- Contract set remains `2`:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-counterproof`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep route/tooling as clean boundary evidence only.
- Run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` next and execute a direction-split 0x25cc counter-proving run on a clean route as suggested by the refiner.

## 2026-05-29 04:20:33-04:00 Loader-Control Left200x2 Tiny Pulse Re-proof (Route Tooling)

## Run Stamp
- Timestamp: `2026-05-29T04:20:33-04:00` (local)
- Branch: `master`
- Refiner decision: `Extend the newest valid loader-control-left200 route by exactly one more tiny state-aware left pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked.`
- Route pressure state: lane remains route-tooling only; no movement/battle proof and no fast-path claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## Run Dir
- `debug-captures\windows-lab\20260529-042038-cpu4-loader-control-left200x2-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-042038-cpu4-loader-control-left200x2-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT`
- Screenshot status: `16` field-like large PNG frames.
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`).
- Invalid screenshots after first field-like: `0`.
- Gate result: `passed-for-triage`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-042038-cpu4-loader-control-left200x2-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`.
- Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1` (`no contract verifier rows found`).
- Targeted fatal scan: only `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-042038-cpu4-loader-control-left200x2-visualgate-windows-windows`
- `Classification: failed-counterproof` (`25cc shadow verifier` and `25cc descriptor` counts `0`).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-042038-cpu4-loader-control-left200x2-visualgate-windows-windows`
- Reservation-loop summary: `collect-missing-proof` (missing kernel-capsule/pair-verifier evidence).
- Host contention: `moderate-postrun` due a non-run process sample.

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` unchanged.
- Contract set remains `2`:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- No `spu_contract_pipeline.ps1` rerun on this checkpoint.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `failed-counterproof`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Keep this as a clean route-boundary field update; next action is to run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` and continue one non-duplicative Windows route/tooling move if still unblocked.


## 2026-05-29 03:50:21-04:00 Loader-Control Field Reproof (Verify Off)

## Run Stamp
- Timestamp: `2026-05-29T03:50:21-04:00` (local)
- Branch: `master`
- Refiner decision: `Add or use black-overlay route control before any movement or lane-2 HLE/GPU dry-run.`
- Route pressure state: repeated black-overlay/fatal blockers remain; this is a clean field-boundary control rerun with no battle/options/fast-path claims.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

## Run Dir
- `debug-captures\windows-lab\20260529-035021-cpu4-loader-control-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-035021-cpu4-loader-control-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT`.
- Screenshot status: `10` field-like large PNG frames.
- First field-like screenshot: `screenshot-0117s.png` at `117s`.
- Invalid screenshots after first field-like: `0`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-035021-cpu4-loader-control-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`.
- Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1` (`no contract verifier rows found`).
- Targeted fatal scan: only `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-035021-cpu4-loader-control-visualgate-windows-windows`
- `Classification: failed-counterproof` (no 25cc verifier rows/hits due verifier lane off in this run).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-035021-cpu4-loader-control-visualgate-windows-windows`
- Reservation-loop summary: `collect-missing-proof` (missing kernel-capsule/pair-verifier rows); no evidence for fast-path promotion.

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `failed-counterproof`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Treat this as a clean field boundary update only; it is not speed, first-battle, menu, or 200% proof.
- Re-run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` before any next movement, battle, or fast-mode/HLE/GPU step. Expect field boundary verification to remain the gate.


## 2026-05-29 03:40:42-04:00 TopSlot Battle Isolation (Verify Off)

## Run Stamp
- Timestamp: `2026-05-29T03:40:42-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest 0x25cc descriptor first-battle Verify25ccShadow run reached battle/tutorial visuals but fataled at PPU VM access. Isolate route without Verify25ccShadow and avoid counters changes.`
- Route pressure state: verify-off isolation was requested to check whether TopSlot failure is route-bound; route was not preserved long enough to reach battle visuals.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## Run Dir
- `debug-captures\windows-lab\20260529-034042-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-034042-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation-windows -RequireFieldLike -RequireBattleLikeAtOrAfterSeconds 120 -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT` (insufficient field duration + no battle-like frame).
- Screenshot status: `1` field-like frame at `117s`, no other clean field-like frame.
- Targeted battle visual scan: `0` battle-like screenshots after `120s`.
- Summary: `FIELD_LIKE_PRESENT` with gate failures for late field and first-battle criteria.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-034042-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures: accepted_rows_lt_1, contract_hits_lt_1` (`failed to emit verifier rows`).
- Targeted fatal scan: only `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-034042-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation-windows`
- `Classification: failed-counterproof`.
- 25cc counters were absent due verify disabled in this capture (`0` rows/`0` hits).
- `.\tools/summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-034042-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-isolation-windows`
- Reservation-loop summary remained `command-correlation-data-missing`; no command or pair-verifier rows for fast-path qualification.

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-counterproof`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Refiner now requires **black-overlay-safe field-boundary control** before re-adding TopSlot battle movement: rerun clean `loader-control-left200x2` field boundary with stricter overlay guard, then return to `Verify25ccShadow` first-battle under that boundary.


## 2026-05-29 03:31:12-04:00 TopSlot nocombo Repair (Verify25ccShadow)

## Run Stamp
- Timestamp: `2026-05-29T03:31:12-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest 0x25cc descriptor first-battle Verify25ccShadow run reached battle/tutorial visuals but fataled at PPU VM access 0x002aedd0; do not count as first-battle proof and run isolate step before any fast-path claims.`
- Route pressure state: same TopSlot macro with no combo removed was attempted but still produced post-field black-overlay and fatal.

## Windows-only Step

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -EternalSonataGpuProbe Profile -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## Run Dir
- `debug-captures\windows-lab\20260529-033112-cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-033112-cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof-windows -RequireFieldLike -RequireBattleLikeAtOrAfterSeconds 120 -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`.
- Screenshot status: `1` clean field-like frame at `117s`, `14` black-overlay-small-png frames afterward, `0` battle-like screenshots.
- Gate failure: invalid post-field screenshots + no battle-like imagery.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-033112-cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=375`, `accepted_rows=375`, `rejected_rows=0`, `total_contract_hits=809`, `total_contract_bytes=13254656`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures: none`.
- Targeted fatal scan: `VM: Access violation reading location 0x40 (unmapped memory)` at `PPU[0x100000c]`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-033112-cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof-windows`
- `Classification: partial-counterproof`.
- 25cc counters: `11238` rows / `12138` hits / `189.66 MB`, GET/PUT `5613/6525`, output mismatches `0`, max overflow `0`.
- Generic non-25cc mismatches remained on `0x451c` (`131` total across `106` lines), so broad shadow claims remain invalid.
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-033112-cpu4-hle-25cc-shadow-desc-battle-topslot-nocombo-proof-windows`
- Reservation-loop summary: `collect-missing-proof` (missing exact command/exact-PC/pair-verifier correlation).

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`

## Classification
- `analysis`
- `failed-fatal-log`
- `failed-visual-gate`
- `partial-counterproof`
- `host-contention-failed`
- `collect-missing-proof`
- `spu-reservation-loop-summary`

## Next Step
- Add or rerun clean `loader-control-left200x2` field control with explicit overlay guard, then return to `Verify25ccShadow` first-battle under that boundary.


## 2026-05-29 03:10:22-04:00 Left200x2 Diag200 Field Extension (Route Tooling)

## Run Stamp
- Timestamp: `2026-05-29T03:10:22-04:00` (local)
- Branch: `master`
- Refiner decision: `Extend the newest valid loader-control-left200x2 route by exactly one tiny diagonal micro-pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked.`
- Route pressure state: route stayed clean field for this field-only boundary with diagonal micro-pulse; no movement evidence or battle claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;combo:ls_left+ls_down:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## Run Dir
- `debug-captures\windows-lab\20260529-031022-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-031022-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT` (triage).
- Screenshot status: `18` clean field-like frames, first field-like at `117s`.
- Invalid-after-field screenshots: `0`.
- Summary: `FIELD_LIKE_PRESENT`; gate result `passed-for-triage`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-031022-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures: accepted_rows_lt_1, contract_hits_lt_1`.
- Targeted fatal scan: only `Show fatal error hints: false`; no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`.
- Failure classification: `no contract verifier rows found` (`failed to emit verifier rows`), `failed-logrow-parser`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-031022-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`
- Reservation-loop summary:
  - `Kernel capsule rows: 0`
  - `Reservation command rows: 0`
  - `Reservation command exact-PC rows: 0`
  - `Command-run MFC wait exact-PC rows: 0`
  - Total kernel/RSX bytes: `0.00 MB / 0.00 MB`
  - Decision: `collect-missing-proof` (missing kernel-capsule and command/exact-PC evidence).

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` re-inspected; unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `next_action` remains unchanged: add verify-only counters for `mfc-descriptor-family-25cc-9e4000`, then rerun field + Options/menu + first-battle with verify mode before any fast paths.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Continue: keep clean field boundary and repair missing verifier-row/counter capture plumbing (`EternalSonataSpuHleVerify`/kernel-capsule loop coverage), then continue first-battle `Verify25ccShadow` only when the same clean boundary is preserved.


## 2026-05-29 02:50:06-04:00 Left200x2 Loader-Control Reproof (Field Tooling)

## Run Stamp
- Timestamp: `2026-05-29T02:50:06-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest run had fatal/crash log evidence; do not extend it. Re-prove the newest clean loader-control-left200x2 boundary with CleanAfterField before adding another pulse.`
- Route pressure state: clean field-only boundary reproof with `EternalSonataReservationLoop Verify` and `EternalSonataSpuHleVerify Off`; no movement evidence or battle claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## Run Dir
- `debug-captures\windows-lab\20260529-025006-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-025006-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Classification: `FIELD_LIKE_PRESENT` (triage).
- Screenshot status: `FIELD_LIKE_PRESENT` with `16` clean field-like frames; first field-like at `117s`.
- Invalid-after-field screenshots: `0`.
- Summary: `FIELD_LIKE_PRESENT`; gate result `passed-for-triage`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-025006-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures: accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal scan: none beyond `Show fatal error hints: false`; no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` findings.
- Failure classification: `no contract verifier rows found` (`failed to emit verifier rows`), `failed-logrow-parser`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-025006-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`
- Reservation-loop summary:
  - `Kernel capsule rows: 0`
  - `Reservation command rows: 1667`
  - `Reservation command exact-PC rows: 45555`
  - `Command-run MFC wait exact-PC rows: 87489`
  - Total kernel/RSX bytes: `0.00 MB`
  - Peak command snapshot hits GETLLAR/PUTLLC/Atomic: `183131 / 139528 / 43603`
  - Decision: `collect-missing-proof` (no kernel-capsule/pair-verifier rows; command-read correlation incomplete).

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` re-inspected; unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `next_action` unchanged: add verify-only counters for `mfc-descriptor-family-25cc-9e4000`, then re-run field, Options/menu, and first-battle under verify mode before any fast paths.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Run refiner immediately; if it now unblocks first-battle repair under verify, execute one isolated Windows first-battle repair before any fast-path candidate.


## 2026-05-29 02:30:27-04:00 TopSlot Control Battle Isolation (Stock-Control)

## Run Stamp
- Timestamp: `2026-05-29T02:30:27-04:00` (local)
- Branch: `master`
- Route pressure state: latest refiner command executed with `EternalSonataSpuHleVerify` off and `EternalSonataGpuProbe Profile`; route still dies/fails after first field-like checkpoint.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30
```

## Run Dir
- `debug-captures\windows-lab\20260529-023027-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-023027-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify-windows`
- Classification: `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`
- Screenshot status: `14` black-overlay-small-png after the first valid field screenshot (`screenshot-0117s.png`).
- First/only field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Gate failures:
  - Invalid small screenshot(s) after the first field-like image.
  - No field-like at/after `220s`.
  - Only `1` field-like screenshot found, minimum required `2`.
  - No battle-like screenshot at/after `200s`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-023027-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures: accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal scan hit: `VM: Access violation reading location 0x40 (unmapped memory)` (in `RPCS3.stderr.txt`/`RPCS3.log`).
- Failure classification: `no contract verifier rows found` and `failed-fatal-log`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-023027-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify-windows`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-023027-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-novo-verify-windows`
- 25cc counterproof classification: `failed-counterproof`.
- Counter detail: `0` 25cc shadow rows/hits and `1` targeted fatal in log.
- Reservation-loop summary: `command-correlation-data-missing`, decision `collect-missing-proof`.

## SPU Contract Artifacts
- `spu-contracts\BLUS30161\source-alignment.json` inspected and unchanged.
- `2` contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `next_action` unchanged: add verify-only counters for `mfc-descriptor-family-25cc-9e4000`, then re-run field/Options/first-battle under verify mode before any fast paths.

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-fatal-log`
- `failed-counterproof`
- `collect-missing-proof`
- `clean-lane-counters-with-invalid-visuals`
- `host-contention-clean`

## Next Step
- Refiner now blocks movement extension and requests re-proving the newest clean loader-control-left200x2 boundary with `CleanAfterField`.


## 2026-05-29 02:10:17-04:00 First-Battle Route Repair Under Verify25ccShadow

## Run Stamp
- Timestamp: `2026-05-29T02:10:17-04:00` (local)
- Branch: `master`
- Route pressure state: latest route-repair attempt under `Verify25ccShadow` stayed in black-overlay visuals; host contention gate failed before any visual field/battle classification.

## Refiner + Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Off -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-021017-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-021017-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows-windows -RequireFieldLike -RequireBattleLikeAtOrAfterSeconds 120 -RequireNoInvalidAfterFirstField`
- Screenshot status: `NO_FIELD_LIKE_SCREENSHOT`
- Screenshot classes: `15` total, all `black-overlay-small-png`; first field-like screenshot: none.
- Targeted visual gate failures: no field-like screenshot and no battle-like screenshot after `120s`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-021017-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=119`, `accepted_rows=119`, `rejected_rows=0`, `total_contract_hits=264`, `total_contract_bytes=4325376`, `total_output_mismatch=0`, `total_desc_overflow=0`, `strict_failures:` none.
- Fatal scan found: `VM: Access violation reading location 0x4 (unmapped memory)` in `RPCS3.log` / `RPCS3.stderr.txt`.
- Host contention gate failed with external `moderate` (`codex` process noise); run stopped by wall-time `330s`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-021017-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows-windows`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-021017-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-repair-windows-windows`
- Classification: `partial-counterproof`
- 25cc shadow descriptors: `3558` rows, `3963` hits, `61.92 MB`, GET/PUT `1773/2190`, output mismatch `0`, `max overflow 0`.
- Generic non-25cc shadow mismatches still on `0x451c`: `46` across `38` lines; this blocks broader shadow claims.
- Reservation-loop evidence unavailable for this lane (`command-correlation-data-missing`, `collect-missing-proof`).

## SPU Contract JSON / Ledger Status
- Re-checked `spu-contracts\BLUS30161\source-alignment.json`:
  - `next_action`: `Add contract-id labeled verify-only counters for mfc-descriptor-family-25cc-9e4000, then re-run field, Options/menu, and first-battle gates before any fast path.`
  - Contract count remained `2`.

## Classification
- `analysis`
- `failed-fatal-log`
- `failed-visual-gate`
- `partial-counterproof`
- `host-contention-failed`
- `collect-missing-proof`

## Next Step
- Refiner now recommends isolating the same TopSlot battle route with `-EternalSonataSpuHleVerify Off` before rerunning a first-battle `Verify25ccShadow` path.

## 2026-05-29 01:50:56-04:00 Descriptor Direction Counterproof + Pipeline Rerun

## Run Stamp
- Timestamp: `2026-05-29T01:50:56-04:00` (local)
- Branch: `master`
- Route pressure state: refiner output confirmed `Field` clean but flagged exact-EA 0x9e4000 shadowing as too narrow. This checkpoint is verify-counter only and avoids movement extension.

## Refiner + Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows
```

## Run Dir
- `debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid-after-field screenshots: none
- Targeted fatal scan: `0` hits

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=824`, `accepted_rows=824`, `rejected_rows=0`, `total_contract_hits=1782`, `total_contract_bytes=29196288`, `total_output_mismatch=0`, `total_desc_overflow=0`
- `strict_failures`: none
- `promotion_ready`: `false` (field proof only; Options/menu and first-battle verify gates still required for fast-path eligibility)

## Counter Verification
- `.\tools\summarize_eternal_sonata_25cc_counterproof.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows`
- Classification: `valid-field-counterproof`
- 25cc shadow descriptors: `24708` rows, `26733` hits, `417.70 MB`, GET/PUT hits `12363/14370`, output mismatches `0`, max descriptor overflow `0`
- Direction summary:
  - GET (`0x40`): `12348` rows, `12363` hits, `193.17 MB`, `changed/unchanged 827/11536`
  - PUT (`0x20`): `12360` rows, `14370` hits, `224.53 MB`, `changed/unchanged 8612/5758`
- Generic non-25cc shadow mismatches remained in 0x451c (`142` total across `122` lines) and do not invalidate this 25cc counterproof path.

## SPU Contract Pipeline Sync + JSON inspection
- Refreshed contract artifacts with the same source run as above:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\index.json`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.json`
  - `spu-contracts\BLUS30161\source-alignment.json`
  - `spu-contracts\BLUS30161\verify-counter-schema.json`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.json`
- `spu-contracts\BLUS30161\verify-counter-schema.json` confirms priority lane `mfc-descriptor-family-25cc-9e4000` requires:
  - contract-level counters (`contract_hits`, `contract_bytes`, `contract_get_hits`, `contract_put_hits`, `contract_reject_total`)
  - reject buckets (`reject_title`, `reject_image_sig`, `reject_pc`, `reject_group`, `reject_cmd`, `reject_list`, `reject_tag`, `reject_size`, `reject_eal_family`, etc.)
  - row hash fields (`last_src_hash`, `last_dst_pre_hash`, `last_dst_post_hash`)
  - and `spu_hle_25cc_shadow_output_mismatch == 0` / `desc_overflow == 0` for promotion gating.
- `spu-contracts\BLUS30161\source-alignment.json` remains at:
  - `2` contracts total
  - `next_action`: implement verify-only counters/reject buckets for priority-1 lane before any fast/body/codegen path.

## Classification
- `analysis`
- `valid-field-counterproof`
- `verify-counterproof`
- `spu-contract-scaffold`
- `spu-contract-inspection`

## Next Step
- Keep `WindowsScene field` on hold for movement extension.
- Implement only verify-only counters/reject buckets in upstream and rerun field + Options/menu + first-battle in verify mode before any fast/body/codegen/Vulkan movement.


## 2026-05-29 01:34:31-04:00 Field Counterproof + Pipeline Refresh

## Run Stamp
- Timestamp: `2026-05-29T01:34:34-04:00` (local)
- Branch: `master`
- Route pressure state: refiner output showed field-clean 0x25cc shadow verifier evidence; verify-only counter row now emits clean acceptance. Latest anti-pattern remains route-movement replay risk.

## Refiner + Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## Run Dir
- `debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid-after-field screenshots: none
- Host contention: postrun `moderate` (known codex host noise), clean prelaunch/launch/postlaunch snapshots.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=824`, `accepted_rows=824`, `rejected_rows=0`, `total_contract_hits=1782`, `total_contract_bytes=29196288`, `total_output_mismatch=0`, `total_desc_overflow=0`
- `strict_failures`: none
- Log fatal scan: only `Show fatal error hints: false` found; no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows`
- `collect-missing-proof` (no reservation-loop command/PC CSVs; kernel capsule and pair-verifier rows unavailable)

## SPU Contract Pipeline Sync
- Re-ran contract compiler on this clean source run:
```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```
- Refreshed outputs:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\index.json`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.json`
  - `spu-contracts\BLUS30161\source-alignment.json`
  - `spu-contracts\BLUS30161\verify-counter-schema.json`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.json`
- Contract set remains `2` contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`

## Classification
- `analysis`
- `valid-field-triage`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`

## Next Step
- Do not rerun generic movement/route now; lane still points to verify-only lane expansion.
- Implement and run verify-only contract counters/reject buckets for `mfc-descriptor-family-25cc-9e4000` in Windows upstream first, then re-run field, Options/menu, and first-battle under the same verify row gating before any fast mode.

## 2026-05-29 00:48:47-04:00 Tiny Diagonal Micro-Pulse + Field Clean Re-Verify

## Run Stamp
- Timestamp: `2026-05-29T00:48:51-04:00` (local)
- Branch: `master`
- Route pressure state: refiner accepted one more tiny movement extension after valid boundary proof and requested `combo:ls_left+ls_down` micro-pulse.

## Refiner + Windows-only Step
```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## Run Dir
- `debug-captures\windows-lab\20260529-004851-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-004851-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid-after-field screenshots: none
- Host contention: clean (`6` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-004851-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- RPCS3 log search for route blockers: only `Show fatal error hints: false`; no real VM access violation/SPU STOP/Vulkan device-lost evidence.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-004851-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows`
- `Kernel capsule rows=0`, `Reservation command rows=1904`, `Reservation command exact-PC rows=52155`, `Command-run MFC wait exact-PC rows=101024`
- Decision: `collect-missing-proof` (missing kernel-capsule/pair verifier rows for narrow fast-path decisions)

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `spu-reservation-loop-summary`

## 2026-05-29 00:35:12-04:00 Load-Boundary Reproof + Clean Visuals

## Run Stamp
- Timestamp: `2026-05-29T00:35:18-04:00` (local)
- Branch: `master`
- Route pressure state: refiner blocked from movement extension after repeated non-field/route misses and requested a clean `left200x2` boundary reproof.

## Refiner + Windows-only Step
```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reproof-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## Run Dir
- `debug-captures\windows-lab\20260529-003518-cpu4-loader-control-left200x2-reproof-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-003518-cpu4-loader-control-left200x2-reproof-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid-after-field screenshots: none
- Host contention samples: clean throughout (`7` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-003518-cpu4-loader-control-left200x2-reproof-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- RPCS3 log search for route blockers: only `Show fatal error hints: false`; no real VM access violation/SPU STOP/Vulkan device-lost evidence.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-003518-cpu4-loader-control-left200x2-reproof-visualgate-windows-windows`
- `Kernel capsule rows=0`, `Reservation command rows=1826`, `Reservation command exact-PC rows=49995`, `Command-run MFC wait exact-PC rows=96623`
- Decision: `collect-missing-proof` (missing kernel-capsule/pair verifier rows for narrow fast-mode changes)

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `spu-reservation-loop-summary`

## 2026-05-29 00:27:10-04:00 Verify-Mode Step + Failure

## Run Stamp
- Timestamp: `2026-05-29T00:27:10-04:00` (local)
- Branch: `master`
- Route pressure state: refiner kept the route in field-probe mode and requested one small state-aware step.
- Newest state-aware Windows step (`cpu4-stateaware-one-step-visualgate-windows`) did not produce field visuals (`NO_FIELD_LIKE_SCREENSHOT`), so it is not route or speed proof.
- SPU contract pipeline artifacts were regenerated earlier against latest 0x25cc/0x451c evidence and remain active for verify-only planning.

## Refiner + Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 240 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-002139-cpu4-stateaware-one-step-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `NO_FIELD_LIKE_SCREENSHOT`
- First field-like screenshot: none
- Host contention: `clean` throughout run samples.

## Log Verification
- Target log check: `debug-captures\windows-lab\20260529-002139-cpu4-stateaware-one-step-visualgate-windows-windows\RPCS3.log`
- Target parse check: `.\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- No contract row was emitted (verify-only counters are not yet wired/instrumented in this run path).

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-002139-cpu4-stateaware-one-step-visualgate-windows-windows`
- Result: no reservation-loop command/exact-PC/match CSVs; `command-correlation-data-missing` and decision `collect-missing-proof`.

## SPU Contract Pipeline Sync
- Re-ran command against latest noisy 0x25cc/0x451c evidence run:
```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-000216-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```
- Regenerated and/or refreshed: `spu-contracts\BLUS30161\latest-summary.md`, `spu-contracts\BLUS30161\verify-counter-plan.md`, `spu-contracts\BLUS30161\verify-counter-schema.md`, `spu-contracts\BLUS30161\verify-logrow-implementation.md`, `spu-contracts\BLUS30161\source-alignment.md`, `spu-contracts\BLUS30161\index.json` and contract JSON rows.

## Classification
- `analysis`
- `failed`
- `route-tooling`
- `verify-counter-plan`
- `spu-contract-scaffold`

## 2026-05-28 23:38:00-04:00 Reproof + Pipeline Sync

## Run Stamp
- Timestamp: `2026-05-28T23:38:00-04:00` (local)
- Branch: `master`
- Route pressure state: refiner had blocked repeat extension after fatal/invalid route evidence; we executed one non-duplicative Windows-only `loader-control-left200x2` clean-boundary reproof and then re-ran contract sync.
- Refiner decision from prior run: `Latest run had fatal/crash log evidence; do not extend it. Re-prove the newest clean loader-control-left200x2 boundary with CleanAfterField before adding movement.`

## Run Command (Windows-only, non-duplicative)
```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;shot:100;wait:1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
```

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260528-233236-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Screenshot status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`)
- Invalid-after-field screenshots: none

## Log Verification
- Target log check: `debug-captures\windows-lab\20260528-233236-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows\RPCS3.log`
- Target parse check: `.\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (expected while verifier row is not yet emitted)
- Fatal/blocker scan: no new `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` in this capture; only startup/capability RSX noise plus save-load init errors consistent with earlier field tooling.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260528-233236-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`
- Result: zero reservation-loop command/exact-PC/match CSV rows; `command-correlation-data-missing` and decision `collect-missing-proof`.
- No claim of counter-based speed/route gain from this run.

## SPU Contract Pipeline Sync
- Re-ran command to refresh artifacts:
```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```
- Regenerated files:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\index.json`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `verify-counter-plan`
- `spu-contract-scaffold`

## Next Step
- Keep this strictly in `verify-only` planning mode.
- Next required action remains: implement/port the contract verifier parseable row and counters in Windows upstream (no copy/body behavior yet), then rerun route field + Options + first-battle under verify schema.

## 2026-05-29 02:09:44-04:00 Prior Checkpoint

## Run Stamp
- Timestamp: `2026-05-29T02:09:44-04:00` (local)
- Branch: `master`
- Route pressure state: still blocked by movement/route instability and fatals; no new clean movement or battle visual proof this round.
- Refiner decision: `latest run had fatal/crash log evidence; do not extend it. Re-prove clean left200x1 boundary`.
- Fallback action chosen: SPU contract pipeline refresh (no emulator movement run).

## SPU Contract Command Executed
```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Result
- Contracts regenerated: `2`
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Generated and refreshed:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\index.json`

## Verification Status
- Parser check on latest battle log:
  - `\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Parsed rows: `0`
  - Accepted rows: `0`
  - Contract hits: `0`
  - Strict gate: **FAIL** (`accepted_rows_lt_1`, `contract_hits_lt_1`)
- Conclusion: contract verification rows are not yet emitted in the current log path; no verify gate yet.

## Classification
- `analysis`
- `spu-contract-scaffold`
- `verify-counter-plan`

## Next Step
- Keep speed lane in `verify-only` planning mode.
- No movement, speed, or GPU-migration counter claims this round.
- Next required action: implement/port the verify-only row in the Windows upstream checkout and rerun field + Options + first-battle captures under the same verify schema.

## 2026-05-28 22:36:27-04:00 Re-run Checkpoint

## Run Stamp
- Timestamp: `2026-05-28T22:36:27-04:00` (local)
- Branch: `master`
- Route pressure state: still blocked on field/first-battle visual integrity after movement; refiner asked to repair the latest clean `left200x1` boundary before extra pulses.
- Refiner command run: `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8`  
- Refiner decision: `Latest run had fatal/crash log evidence; do not extend it. Re-prove the newest clean loader-control-left200x1 boundary with CleanAfterField before adding another pulse.`

## SPU Contract Command Executed
```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Result
- Pipeline re-run refreshed the same 2 contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Refreshed files:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\index.json`
  - `spu-contracts\BLUS30161\verify-counter-plan.json` / `.md`
  - `spu-contracts\BLUS30161\source-alignment.json` / `.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.json` / `.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.json` / `.md`
- Parser gate on latest battle log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath <latest-run>/RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Parsed rows: `0`
  - Accepted rows: `0`
  - Contract hits: `0`
  - Strict gate: **FAIL** (`accepted_rows_lt_1`, `contract_hits_lt_1`)
- Conclusion remains: verify row is not emitted by current run path; contract lane remains scaffold-only.

## Classification
- `analysis`
- `spu-contract-scaffold`
- `spu-contract-pipeline`
- `verify-logrow-parser`

## Next Step
- Keep route blocked until `left200x1` boundary is re-proven in clean visual state.
- Implement/port only the contract verifier log-row in an isolated Windows upstream checkout, then rerun strict parser + visual triage gates.

