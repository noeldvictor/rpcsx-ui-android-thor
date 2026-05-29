# 2026-05-29 SPU Contract Pipeline Round

## 2026-05-28 23:38:00-04:00 Reproof + Pipeline Sync

## Run Stamp
- Timestamp: `2026-05-28T23:38:00-04:00` (local)
- Branch: `master`
- Route pressure state: refiner had blocked repeat extension after fatal/invalid route evidence; we executed one non-duplicative Windows-only `loader-control-left200x2` clean-boundary reproof and then re-ran contract sync.
- Refiner decision from prior run: `Latest run had fatal/crash log evidence; do not extend it. Re-prove the newest clean loader-control-left200x2 boundary with CleanAfterField before adding movement.`

## Run Command (Windows-only, non-duplicative)
```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;shot:100;wait:1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait:10000;shot:100" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11
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
- Result: zero reservation-loop command/eat/match CSV rows; `command-correlation-data-missing` and decision `collect-missing-proof`.
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
