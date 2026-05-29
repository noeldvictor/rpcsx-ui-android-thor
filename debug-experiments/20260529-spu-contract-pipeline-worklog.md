# 2026-05-29 SPU Contract Pipeline Round

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
