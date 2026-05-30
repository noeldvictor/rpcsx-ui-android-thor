# 2026-05-29 SPU Contract Pipeline Round

## 2026-05-29 23:52:43-04:00 SPU Verify-Only Re-Sync (Rows Present, No Field)

## Run Stamp
- Timestamp: `2026-05-29T23:52:22.4241377-04:00` / `2026-05-29T23:52:43.4370317-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate -OutJson .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\spu-contract-parse-summary.json
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T23:52:26.7281737-04:00` and remain the same 2 priority contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate:
  - `NO_FIELD_LIKE_SCREENSHOT`
  - `First field-like`: `none`
  - Gate failure: `No field-like screenshot was found`.
- Parser check (`-FailOnGate`):
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `contract_hits=1529`, `contract_bytes=25051136`
  - `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=[]`, `strict_gate_pass=true`
  - parse summary written: `debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\spu-contract-parse-summary.json`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Contract JSON inspection still indicates parseable verifier rows are emitted, but full route proof is still blocked by missing clean field/Options/first-battle visual gates.

## Classification
- `analysis`
- `failed`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-reservation-loop-summary`
- `verify-counter-plan`
- `spu-contract-scaffold`

## Next Step
- Keep movement and speed lanes blocked.
- Continue SPU verifier planning only: keep `contract-25cc-9e4000` parser instrumentation in Windows upstream, then run clean `field -> Options -> first-battle` captures with the same verify-mode before any fast-path candidate enable.

## 2026-05-29 23:32:30-04:00 SPU Verify-Only Re-Sync (No Verifier Rows)

## Run Stamp
- Timestamp: `2026-05-29T23:32:05.2165143-04:00` / `2026-05-29T23:32:30.8859969-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\\spu_contract_pipeline.ps1 -RunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\\parse_spu_contract_verify_log.ps1 -LogPath .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\\RPCS3.log
.\tools\\parse_spu_contract_verify_log.ps1 -LogPath .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T23:32:08.9385156-04:00` and retained the same two contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check (`strict false`):
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `failures=no contract verifier rows found`
  - `promotion_ready=false`
- Parser check (`-FailOnGate`):
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- SPU JSON artifacts were refreshed only for generated timestamps; contract/class fields remain unchanged, still requiring verify-only `field/options-menu/first-battle`, `output_mismatch=0`, `descriptor_overflow=0`, `fatal_log_hits=0`, and `fast_mode=blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed lanes blocked.
- Continue Windows-only SPU verification-only path: instrument/confirm counters in upstream emulator runs for
  `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` before any fast mode, route-movement repeat, or speed claim.
  Contract rows still need to appear in fresh Windows logs before any next fast-path decision.

## 2026-05-29 23:12:40-04:00 SPU Verify-Only Re-Sync (Counter Scaffold Refresh)

## Run Stamp
- Timestamp: `2026-05-29T23:12:16.2377200-04:00` / `2026-05-29T23:12:39.4366702-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T23:12:16.2377200-04:00` and retained the same 2 contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` (priority-1 lane)
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` (priority-2 lane)
- `source-alignment.json` confirms the Windows upstream already has the 25cc predicate and 451c family paths, while vendored RPCSX still has only generic DMA probe hooks.
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `failures=no contract verifier rows found`
  - Strict mode remains failing (`accepted_rows_lt_1`, `contract_hits_lt_1`) when `-FailOnGate` is applied.
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- SPU contract JSON inspection:
  - `verify-counter-schema` now requires contract-id/lane-1 fields:
    - `contract_id`, `contract_hits`, `contract_bytes`, `contract_get_hits`, `contract_put_hits`,
      `contract_reject_total`, reject buckets, `last_src_hash`, `last_dst_pre_hash`, `last_dst_post_hash`.
  - `verify-logrow-implementation` defines a new `Eternal Sonata SPU contract verifier` row keyed by `hle_mode=contract-25cc-9e4000`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed lanes blocked.
- Plan implementation work now shifts to first applying the contract verifier log-row in Windows upstream (`rpcs3-upstream`) and verify-only counters, then re-running this same clean visual field + verify pipeline under `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow`.
- Do not unblock fast paths or route movement until clean field/options/first-battle with zero `output_mismatch` and zero `desc_overflow` are confirmed.

## 2026-05-29 22:52:18-04:00 SPU Verify-Only Re-Sync (Verifier Rows + No-Field)

## Run Stamp
- Timestamp: `2026-05-29T22:52:18.8203030-04:00` / `2026-05-29T22:52:56.3575177-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:52:28.0944764-04:00`.
- Contract set is still two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `NO_FIELD_LIKE_SCREENSHOT`
  - `First field-like`: `none`
  - Gate failure: `No field-like screenshot was found`.
- Parser check:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `contract_hits=1529`, `contract_bytes=25051136`, `output_mismatch=0`, `desc_overflow=0`
  - `failures` were none (rows are all accepted)
  - `promotion_ready=false` until full field/options/battle visual chain is confirmed.
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=90997`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- `parse_spu_contract_verify_log` summary file and `summarize_eternal_sonata_spu_reservation_loop` were written to the source run directory.

## Classification
- `analysis`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Contract verifier is now emitting rows for `contract-25cc-9e4000`, but no field-like visuals and missing reservation-loop correlation evidence still block progress. Keep verify-only counter planning focused before any fast modes.

## 2026-05-29 22:33:25-04:00 SPU Verify-Only Re-Sync

## 2026-05-29 22:51:44-04:00 SPU Verify-Only Re-Sync (Re-run)

## Run Stamp
- Timestamp: `2026-05-29T22:51:44.6946606-04:00` / `2026-05-29T22:51:54.7110144-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools/parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:51:49.5910491-04:00`.
- Contract set is still two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `failures=no contract verifier rows found`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Contract JSON inspection remains unchanged: `required_visuals` include `field/options-menu/first-battle`; `required_counters` remain `output_mismatch=0`, `descriptor_overflow=0`, `fatal_log_hits=0`; `fast_mode` remains `blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Continue SPU verify planning: implement/confirm Windows upstream verify-only counters and reject buckets for priority-1 `contract-25cc-9e4000` before any fast body/codegen/Vulkan-compute mode.

## Run Stamp
- Timestamp: `2026-05-29T22:33:16.1859858-04:00` / `2026-05-29T22:33:25.4427853-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:33:19.8808748-04:00`.
- Contract set remains unchanged: two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `failures=no contract verifier rows found`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Contract JSON inspection:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` and `...pc0451c-...` retain `required_visuals` `field/options-menu/first-battle`, `required_counters` `output_mismatch=0`, `descriptor_overflow=0`, `fatal_log_hits=0`, and `fast_mode=blocked`.
- Source evidence and verify plan still point to priority-1 `0x25cc/0x9e4000` as the first verify-only counter target.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Do not enable fast-mode bodyfast/codegen/Vulkan- compute until strict `field -> options -> first-battle` verifier lanes pass.
- Next required action remains: implement/confirm Windows upstream verify-only counters/reject buckets for priority-1 `contract-25cc-9e4000` before any fast body/compute changes.

## 2026-05-29 22:31:42-04:00 SPU Verify-Only Re-Sync

## Run Stamp
- Timestamp: `2026-05-29T22:31:42.8267506-04:00` / `2026-05-29T22:31:53.3083227-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked by repeated non-field/fatal anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:31:47.0340698-04:00`.
- Contract set remains unchanged: two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `failures=no contract verifier rows found`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Log scan markers: no new `Show fatal error hints: false` only, no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Implement/confirm Windows upstream verify-only counters/reject buckets for priority-1 `0x25cc/0x9e4000` (`contract-25cc-9e4000`) before any fast modes.
- Run strict `field -> options-menu -> first-battle` verifier passes under the same schema before any fast-mode codegen/body/Vulkan-compute changes.

## 2026-05-29 22:12:43-04:00 SPU Verify-Only Re-Sync

## Run Stamp
- Timestamp: `2026-05-29T22:12:43.7147423-04:00` / `2026-05-29T22:12:52.8660118-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement blocked by repeated non-field/fatal anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:12:47.6716647-04:00`.
- Contract set is still two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `failures=no contract verifier rows found`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Log scan markers: no new `Show fatal error hints: false` only, no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Implement/confirm Windows upstream verify-only counters/reject buckets for priority-1 `0x25cc/0x9e4000` before any fast modes.
- Run strict `field -> options-menu -> first-battle` verifier passes under the same `verify-25cc-shadow` schema before any bodyfast/codegen/Vulkan-compute changes.

## Run Stamp
- Timestamp: `2026-05-29T22:12:43.7147423-04:00` / `2026-05-29T22:12:52.8660118-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement blocked by repeated non-field/fatal anti-patterns; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed at `2026-05-29T22:12:47.6716647-04:00`.
- Contract set is still two contracts on `0x25cc` / `0x451c` (`BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`, `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`).
- Visual gate:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` passed.
- Parser check:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `failures=no contract verifier rows found`
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Reservation command exact-PC rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - `PUTLLC16 pair verifier rows=0`
  - Decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Log scan markers: no new `Show fatal error hints: false` only, no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Implement/confirm Windows upstream verify-only counters/reject buckets for priority-1 `0x25cc/0x9e4000` (`contract-25cc-9e4000`) before any fast modes.
- Run strict `field -> options-menu -> first-battle` verifier passes under the same `verify-25cc-shadow` schema before any bodyfast/codegen/Vulkan-compute changes.

## 2026-05-29 21:52:00-04:00 SPU Verify-Only Refresh Sweep

## Run Stamp
- Timestamp: `2026-05-29T21:52:13.9044366-04:00` / `2026-05-29T21:52:37.7192989-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement is blocked by repeated black/visual misses and blocker anti-patterns; SPU verifier lane remains active and non-promotional.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts refreshed at `2026-05-29T21:52:21.6496370-04:00`.
- Contract set is unchanged at 2 contracts (`0x25cc` + `0x451c`) with the same `0x958dfe208b686622` anchor.
- `latest-summary.md` / `source-alignment.md` / `verify-counter-*` / `verify-logrow-implementation.md` and both contract JSONs were re-written with the new timestamp and same contract topology.
- Visual gate on the source run:
  - `FIELD_LIKE_PRESENT`
  - `First field-like`: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - no `invalid-after-field` detections from the chosen clean-field gate.
- Log parsing:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `contract_hits=0`, `contract_bytes=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - indicates verifier rows are still missing from this path, so strict verification lane is blocked.
- Route counters:
  - `Kernel capsule rows=0`, reservation/correlation rows all `0`
  - decision remains `collect-missing-proof` (`command-correlation-data-missing`).
- Log scan markers:
  - `Show fatal error hints: false` only
  - no real `VM access violation`, no `SPU unknown STOP`, no `VK_ERROR_DEVICE_LOST`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement and speed routes blocked.
- Implement/confirm Windows upstream verify-only counters/reject buckets for the `0x25cc/0x9e4000` contract row, then rerun strict `field -> options-menu -> first-battle` verifier captures before any fast-mode change.

## 2026-05-29 21:31:59-04:00 SPU Verify-Only Hold Refresh

## Run Stamp
- Timestamp: `2026-05-29T21:31:59.6654094-04:00` / `2026-05-29T21:32:13.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement remains blocked; SPU verifier lane is active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed from the same field-clean `095956` source run.
- `latest-summary` source run remained `20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`.
- Visual check:
  - `FIELD_LIKE_PRESENT`
  - First field-like screenshot: `screenshot-0118s.png` at `118s` (`2.50 MB`)
  - `RequireNoInvalidAfterFirstField` gate passed.
- Contract parser output:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`-FailOnGate` fails)
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - Decision: `collect-missing-proof` (`command-correlation-data-missing` / no command CSVs)
- Log scan:
  - `Show fatal error hints: false` only
  - no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` signatures.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep movement/route changes blocked for now; no 200% gate proof yet.
- Implement or confirm verify-only counters for the `0x25cc/0x9e4000` lane in Windows upstream, then rerun strict `field -> options -> first-battle` with the same verify schema before any fast/body/codegen/GPU toggles.

## 2026-05-29 21:12:56-04:00 SPU Verify-Only Hold Refresh

## Run Stamp
- Timestamp: `2026-05-29T21:12:56.1314749-04:00` / `2026-05-29T21:13:00.589` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement blocked; route remains at SPU verifier lane.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline artifacts were refreshed from the same valid `095956` field evidence.
- `latest-summary` source run now points to `20260529-095956`; inferred classes include `dynamic-mfc-shape` for both contracts.
- Visual verification:
  - `FIELD_LIKE_PRESENT`
  - First field-like screenshot: `screenshot-0118s.png` (`2.50 MB`)
  - No invalid-after-field screenshots.
- Parser output on this run:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `contract_hits=0`, `contract_bytes=0`, `output_mismatch=0`, `desc_overflow=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (strict gate failed)
- Reservation-loop summary:
  - `Kernel capsule rows=0`
  - `Reservation command rows=0`
  - `Command-run MFC wait exact-PC rows=0`
  - Decision: `collect-missing-proof` (no correlation data available)
- Host contention checks were `clean` prelaunch and postrun.
- `RPCS3.log` had no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST`; only `Show fatal error hints: false`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Keep the lane on verify-only planning until correlation/contract rows are emitted in a comparable field/options/battle path.
- Continue with source-side counter wiring in Windows upstream using `0x25cc/0x9e4000` lane guidance, then rerun `field -> options -> first-battle` under the same verify schema before any fast-body/codegen/GPU toggles.

## 2026-05-29 20:32:34-04:00 SPU Verify-Planning Refresh

## Run Stamp
- Timestamp: `2026-05-29T20:32:17.3380090-04:00` / `2026-05-29T20:32:34.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement remains blocked; lane-2 SPU verifier work remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- SPU pipeline outputs were refreshed from the same clean 095956 field evidence.
- `latest-summary` source run now points to `20260529-095956` and contract classes are `dynamic-mfc-shape,dma-window,spurs-kernel` for both `0x025cc`/`0x0451c`.
- Visual verification:
  - `FIELD_LIKE_PRESENT`
  - First field-like screenshot: `screenshot-0118s.png` (`2.50 MB`)
  - No invalid screenshot after first field-like.
- Contract parser result on this evidence:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (strict gate failed)
- SPU reservation-loop summarize on the source run:
  - Kernel capsule rows: `0`
  - Command rows: `0`
  - Exact command-PC rows: `0`
  - MFC wait rows: `0`
  - Decision: `collect-missing-proof` (correlation data missing)
- No new real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` signatures in this run; only startup/standard `Show fatal error hints: false`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed`
- `spu-contract-scaffold`
- `verify-counter-plan`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `verify-logrow-parser`

## Next Step
- Keep this lane in verify-only planning.
- `inspect spu-contracts\BLUS30161` for schema/anchor updates (already refreshed), then add/port contract-id verify counters in `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` and rerun strict `field -> Options -> first-battle` under the same verify schema before any fast-path toggle.

## 2026-05-29 20:52:13-04:00 SPU Verify-Only Contract Re-sync on Non-Field Evidence

## Run Stamp
- Timestamp: `2026-05-29T20:51:38.9142842-04:00` / `2026-05-29T20:52:13.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement stays blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU pipeline outputs were refreshed from `175303` evidence and source run updated accordingly.
- `latest-summary` now points to this source run and contracts remain `2`:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Contract inference classes were adjusted to `dma-window,spurs-kernel` for both contracts.
- Visual gate result:
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - `first field-like screenshot`: `none` (`8` screenshots, `cutscene-or-nonfield` classes `1 large + 7 small`)
  - Gate failed (classifies as invalid route-equivalent evidence).
- Contract parser result on same run:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - `strict_gate_pass=true`
  - No strict failures (parser itself passes on this log).
- Reservation-loop summary:
  - Kernel capsule rows: `0`
  - Reservation command rows: `0`
  - Reservation command exact-PC rows: `0`
  - MFC wait rows: `0` (command-run exact-PC rows `90997`)
  - Decision: `collect-missing-proof` (command-correlation data missing).
- `RPCS3.log` check: only `Show fatal error hints: false`; no new VM access violation/SPU unknown STOP/Vulkan device-lost hits.

## Classification
- `analysis`
- `failed`
- `failed-visual-gate`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `verify-counter-plan`
- `verify-logrow-parser`
- `collect-missing-proof`

## Next Step
- Continue in verify-only planning.
- Inspect updated `spu-contracts\BLUS30161` JSON/schema outputs and implement `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream` verify-only contract counters for priority-1 `0x25cc/0x9e4000` next, then rerun strict `field -> Options -> first-battle` captures for promotion gates.

## 2026-05-29 20:12:05-04:00 SPU Pipeline Re-sync on Non-Field Evidence

## Run Stamp
- Timestamp: `2026-05-29T20:11:51.2719351-04:00` / `2026-05-29T20:12:05.8951011-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement remains blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU artifacts were refreshed from the `175303` evidence run and source alignment now points to that run.
- Contract IDs stayed the same; runtime classes on `latest-summary` now read `dma-window,spurs-kernel` for both PCs (same two contracts, same hot log hit count).
- Visual gate result: `NO_FIELD_LIKE_SCREENSHOT` (first field-like screenshot: `none`; one large + seven small cutscene/non-field screenshots).
- Parser result on the same run:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`, `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - `strict_failures` = none (strict gate pass).
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `PUTLLC16 pair verifier rows=0`, `Reservation command rows=0`, `Command-run MFC wait exact-PC rows=90997`
  - Decision: `collect-missing-proof` (missing kernel-capsule/command correlation artifacts).
- `RPCS3.log` had only `Show fatal error hints: false`; no VM access violations, SPU unknown STOPs, or Vulkan device-lost patterns.

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold this lane in verify-only planning.
- Do not count this run as route/field/options/battle proof or speed/migration credit.
- Next action: continue with source-side verify-only instrumentation in Windows upstream and rerun field + Options + first-battle under that verify schema before any fast mode.

## 2026-05-29 19:52:13-04:00 SPU Pipeline Refresh on Non-Field Movement Evidence

## Run Stamp
- Timestamp: `2026-05-29T19:51:43.7596511-04:00` / `2026-05-29T19:52:13.3736401-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows
```

## Verification

- SPU artifacts were refreshed from the `100836` evidence and timestamps/`source_run` now point to that run.
- `0x25cc`/`0x451c` contract IDs are unchanged.
- Visual gate: `NO_FIELD_LIKE_SCREENSHOT` (`first field-like: none`).
- Parser:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`.
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `Reservation command rows=1767`, `Reservation command exact-PC rows=49648`
  - `Command-run MFC wait exact-PC rows=100813`
  - `command-correlation-data=whole-loop-recognizer-preflight`
  - Decision: `collect-missing-proof`.
- `RPCS3.log` had no VM access violation, SPU unknown STOP, or Vulkan device-lost signatures.

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep the lane in SPU verify-only planning. Do not advance any fast/body/codegen path from this run because visuals were invalid and no contract verifier rows were emitted.
- Re-run the source evidence under a visual/route-comparable capture (`field/options/battle`) before attempting implementation work.

## 2026-05-29 19:32:56-04:00 SPU Scaffold Refresh and Verification Hold

## Run Stamp
- Timestamp: `2026-05-29T19:32:09.1362708-04:00` / `2026-05-29T19:32:56.6033608-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement remains blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU artifacts were refreshed from the `175303` evidence and source timestamps were bumped across all contract outputs (`index`, `latest-summary`, `source-alignment`, verify plan/schema, and log-row scaffold).
- Contract IDs are unchanged.
- Visual gate on the source run still fails:
  - `NO_FIELD_LIKE_SCREENSHOT` (`first field-like screenshot: none`)
  - `screenshot-0118s` classified as `cutscene-or-nonfield-large-png`, plus seven small non-field clips.
- Parser result for the source run:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - strict mode passed.
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `Reservation command rows=0`, `Command-run MFC wait exact-PC rows=90997`
  - `command-correlation-data-missing`
  - Decision: `collect-missing-proof`.
- Log quick scan (`RPCS3.log`): no `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` signatures.

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep lane locked to verify-only planning and implement the priority-1 `mfc-descriptor-family-25cc-9e4000` verifier-only row in the Windows upstream checkout when route visuals are first-clean.
- Do not switch to bodyfast/codegen/GPU fast mode until clean `field -> options -> first-battle` captures under `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` exist.

## 2026-05-29 19:12:13-04:00 SPU Verify-Lane Hold and Counter-Plan Refresh

## Run Stamp
- Timestamp: `2026-05-29T19:12:03.6052870-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement remains blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- SPU artifacts were refreshed from the `175303` evidence and remain:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Contract IDs are unchanged:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate result on source run:
  - `NO_FIELD_LIKE_SCREENSHOT` (`first field-like screenshot: none`)
  - route is not clean-comparable.
- Parser result:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - strict mode passed.
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `Reservation command rows=0`, `Command-run MFC wait exact-PC rows=0`
  - `No reservation-loop command/exact-PC/pair verifier rows were available.`
  - Decision: `collect-missing-proof`
- Log quick scan (`RPCS3.log`): no `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` signatures.

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep the lane on verify-only implementation planning only.
- Implement the priority-1 `mfc-descriptor-family-25cc-9e4000` contract row in the Windows upstream checkout, then re-run strict `field -> options -> first-battle` captures under `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` before any fast mode.

## 2026-05-29 18:52:42-04:00 SPU Verify-Lane Hold and Contract-Index Refresh

## Run Stamp
- Timestamp: `2026-05-29T18:52:42.0943116-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement remains blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- Refiner output remains blocking movement and points back to route-state repair or SPU verifier analysis.
- SPU artifacts refreshed from the `095956` evidence:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Contract IDs in `spu-contracts/BLUS30161/index.json` remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `spu-contracts/BLUS30161/index.json` now reflects source run `20260529-095956...` and includes `dynamic-mfc-shape` in both contracts.
- Visual gate result:
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`, `2.50 MB`)
  - No later invalid-after-field screenshots reported.
- Parser result:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`
  - `total_contract_hits=0`, `total_contract_bytes=0`, `total_output_mismatch=0`, `total_desc_overflow=0`
  - `strict_failures: accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `reservation-command rows=0`, `command-correlation-data-missing`
  - Decision: `collect-missing-proof`
- Log quick scan (`RPCS3.log`): only `Show fatal error hints: false`; no `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` signatures.

## Classification
- `analysis`
- `valid-field-triage`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep the lane in SPU verify-only planning mode.
- Keep contract IDs as current selection and complete parser/counter emit in Windows upstream (`RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow`), then rerun strict `field -> options -> first-battle` captures before any fast-mode proposal.

## 2026-05-29 18:32:40-04:00 SPU Verify-Lane Refresh and Hold

## Run Stamp
- Timestamp: `2026-05-29T18:32:19.1977541-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement.`
- Route pressure state: movement reruns remain blocked; SPU verifier lane remains active.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- Refiner output still blocks movement and points at route-state repair or SPU verifier analysis.
- SPU artifacts updated from the `175303` evidence:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Contract IDs in `spu-contracts/BLUS30161/index.json` remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate result:
  - `NO_FIELD_LIKE_SCREENSHOT` (`first field-like screenshot: none`).
  - This run is route-compare invalid.
- Parser result:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - `strict_failures`: none
- Reservation summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `Command-run MFC wait exact-PC rows=90997`
  - `command-correlation-data-missing`
  - Decision: `collect-missing-proof`
- Log quick scan:
  - no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` lines.
  - only `Show fatal error hints: false` was present.

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep SPU lane locked to verify-only work: ensure clean `field -> options -> first-battle` captures under `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` before any fast-mode discussion.
- Continue to treat the contract parser as scaffold only until route visuals are clean; no bodyfast/codegen/GPU changes yet.

## 2026-05-29 18:12:47-04:00 Refiner-Blocked SPU Verify Hold

## Run Stamp
- Timestamp: `2026-05-29T18:12:13.9167567-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement is still blocked by pre-field black-overlay and non-field-cutscene evidence; stay on SPU verifier lane and avoid movement reruns.`
- Route pressure state: anti-patterns remain active; parser now shows log rows only on stock capture, but no clean field visual proof for that capture.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-175303-eternal-sonata-field-stock-qualcomm-windows
```

## Verification

- Refiner still blocks loader-control movement: repeated `repeated-black-overlay-pre-field`, `cutscene-or-nonfield-frames`, `fatal-log-hit` and `single-next-loader-control-failure` remain in recency band.
- SPU artifacts refreshed from source run `20260529-175303`:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Contract IDs in `spu-contracts/BLUS30161/index.json` remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate result:
  - `NO_FIELD_LIKE_SCREENSHOT` (`first field-like screenshot: none`)
  - This run is not route/menu/battle comparable.
- Parser result:
  - `rows=763`, `accepted_rows=763`, `rejected_rows=0`
  - `total_contract_hits=1529`, `total_contract_bytes=25051136`
  - `total_output_mismatch=0`, `total_desc_overflow=0`
  - `strict_failures` none.
- Reservation summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `command-correlation-data-missing`
  - Decision: `collect-missing-proof`
- Log quick-scan: no real `VM access violation`, `SPU unknown STOP`, or `VK_ERROR_DEVICE_LOST` lines in this run (`Show fatal error hints: false` only).

## Classification
- `analysis`
- `failed-visual-gate`
- `verify-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Plan for verify-only emulator counters under `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` only; keep this on clean field proof run first, then Options/menu and first-battle in the same schema.
- Continue to postpone any bodyfast/codegen/GPU fast modes until all three gates (field, Options/menu, first-battle) are clean with zero rejects/mismatches/overflow.

## 2026-05-29 18:04:15-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T18:04:02.3981667-04:00` (local)
- Branch: `master`
- Refiner decision: `Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis.`
- Route pressure state: movement blocked by fresh anti-patterns (`repeated-black-overlay-pre-field`, `cutscene-or-nonfield-frames`, `fatal-log-hit`, `clean-lane-counters-with-invalid-visuals`); SPU verifier lane remains active on base run `20260529-095956`.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows
```

## Verification

- Refiner now reports the same movement-blocking anti-patterns and no action to rerun loader-control.
- SPU artifacts were refreshed from source run `20260529-095956`; contract IDs in `spu-contracts/BLUS30161/index.json` remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Visual gate:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 ...`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`, `2.50 MB`)
- Strict parser:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `command-correlation-data-missing`
  - Decision remains `collect-missing-proof`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement parseable `contract-25cc-9e4000` verifier-row behavior in Windows upstream (reject buckets only), then run verify-only counters on `field`, then `options`, then `first-battle` under the same schema before any fast-path proposal.

## 2026-05-29 17:51:52-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T17:51:39.8424037-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: movement blocked by recent anti-patterns; SPU verifier lane remains the clean lane on base run `20260529-095956`.

## Action Taken

```powershell
.\\tools\\ps3_harness_refiner.ps1 -MaxRuns 8
.\\tools\\spu_contract_pipeline.ps1 -RunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner still blocks movement: repeated `single-next-loader-control-failure`, `repeated-black-overlay-pre-field`, `fatal-log-hit`, and `clean-lane-counters-with-invalid-visuals`.
- SPU artifacts refreshed:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Visual check:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`, `2.50 MB`)
- Strict parser:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `total_contract_hits=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, `command-correlation-data-missing`, decision `collect-missing-proof`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement parseable `contract-25cc-9e4000` verifier-row behavior in Windows upstream (log-only, reject buckets only), then run verify-only counters for field, then Options/menu, then first-battle under the same schema before any fast-mode proposal.

## 2026-05-29 17:31:51-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T17:31:36.4578761-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or run focused SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: movement reruns remain blocked; SPU verifier lane remains the clean choice from clean base `20260529-095956`.

## Action Taken

```powershell
.\\tools\\ps3_harness_refiner.ps1 -MaxRuns 8
.\\tools\\spu_contract_pipeline.ps1 -RunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner output continues to block movement: `single-next-loader-control-failure`, `repeated-black-overlay-pre-field`, and `fatal-log-hit`.
- Contract artifacts refreshed:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`
- Visual gate:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`, `2.50 MB`)
- JSON inspection:
  - `spu-contracts/BLUS30161/index.json`
  - Two contracts detected, IDs:
    - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
    - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
  - Both show `hot_log_hits=80` for source run `095956`.
- Strict parser:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `total_contract_hits=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir ...\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `decision=collect-missing-proof`, `Kernel capsule rows=0`, `command-correlation-data-missing`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Insert the parseable `contract-25cc-9e4000` verifier row in Windows upstream (reject buckets only), then run strict parser + verify-only `field` + `options` + `first-battle` captures with this schema before any fast-mode proposals.

## 2026-05-29 17:12:21-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T17:12:21.0414981-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: movement reruns remain blocked; latest clean base remains `20260529-095956` and SPU verifier lane remains the clean lane.

## Action Taken

```powershell
.\\tools\\ps3_harness_refiner.ps1 -MaxRuns 8
.\\tools\\spu_contract_pipeline.ps1 -RunDir .\\debug-captures\\windows-lab\\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner continues to block movement with `single-next-loader-control-failure`, `repeated-black-overlay-pre-field`, and `fatal-log-hit` anti-patterns.
- Visual gate on SPU evidence base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`, `2.50 MB`)
- Strict SPU parser:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`
  - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- SPU reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `kernel rows 0`, `exact-PC rows 0`, `correlation rows 0`, `decision=collect-missing-proof`
- SPU artifacts regenerated (timestamps only):
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/source-alignment.*`
  - `spu-contracts/BLUS30161/verify-counter-plan.*`
  - `spu-contracts/BLUS30161/verify-counter-schema.*`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.*`

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Apply log-only parseable contract-row in Windows upstream with reject buckets only, then run verify-only counters with field + options + first-battle captures under this schema.

## 2026-05-29 16:51:39-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T16:51:36.8995906-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: no new movement window yet; SPU verifier lane still blocked on missing contract-row emission.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary continues to block movement from anti-patterns (`single-next-loader-control-failure`, `repeated-black-overlay-pre-field`, `fatal-log-hit`).
- Visual gate check on latest clean base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`)
- Parser strict check:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, decision `collect-missing-proof`.
- SPU JSON artifacts refreshed timestamps from this run:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.md`/`.json`
  - `spu-contracts/BLUS30161/verify-counter-plan.md`/`.json`
  - `spu-contracts/BLUS30161/verify-counter-schema.md`/`.json`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.md`/`.json`
- Contract set unchanged:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
  - Lane `mfc-descriptor-family-25cc-9e4000`, mode `contract-25cc-9e4000`

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Apply log-only parseable contract row in Windows upstream (no behavior changes), then run strict parser + verified `field` + `options-menu` + `first-battle` with same schema before any fast-mode proposal.

## 2026-05-29 16:31:39-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T16:31:34.5368610-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: movement reruns remain blocked; verify lane remains active on clean base `20260529-095956`.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary still blocks movement rerun from anti-patterns `single-next-loader-control-failure`, `repeated-black-overlay-pre-field`, and `fatal-log-hit`.
- Visual check:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT` (`screenshot-0118s.png` at `118s`)
- Parser strict checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - No correlation CSVs; `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, decision `collect-missing-proof`.
- SPU artifacts updated from source run `20260529-095956`:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/source-alignment.md` and `.json`
  - `spu-contracts/BLUS30161/verify-counter-plan.md` and `.json`
  - `spu-contracts/BLUS30161/verify-counter-schema.md` and `.json`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.md` and `.json`
- Contract set and lane remain unchanged:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
  - verify lane: `mfc-descriptor-family-25cc-9e4000`
  - hle mode: `contract-25cc-9e4000`

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/apply log-only parseable contract row in Windows upstream next (no behavior changes), then rerun strict parser + verified `field` + `options-menu` + `first-battle` captures under this schema before any fast-path proposal.

## 2026-05-29 16:13:35-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T16:13:26.4097893-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: repeated movement/final-battle blockers remain; latest clean base still `20260529-095956`. No Windows movement or battle proof added this round.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary: `single-next-loader-control-failure` + `fatal-log-hit` + `clean-lane-counters-with-invalid-visuals`; lane remains SPU verifier-only.
- Visual check on latest clean base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s` (`2.50 MB`)
- Parser strict checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - No correlation CSVs; `Kernel capsule rows=0`, `MFC wait exact-PC rows=0`, decision `collect-missing-proof`.
- SPU JSON/ledger artifacts refreshed from source run `20260529-095956`:
  - `spu-contracts/BLUS30161/latest-summary.md`
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/source-alignment.md` and `.json`
  - `spu-contracts/BLUS30161/verify-counter-plan.md` and `.json`
  - `spu-contracts/BLUS30161/verify-counter-schema.md` and `.json`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.md` and `.json`

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Apply log-only parseable row in Windows upstream only (no behavior changes), then rerun strict parser + verified `field` + `options-menu` + `first-battle` captures under this schema before any fast-mode proposals.

## 2026-05-29 16:11:54-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T16:11:54.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: refiner remains blocked on movement; latest clean base still `20260529-095956` and no movement/final battle counterproof exists.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary: route/movement reruns remain blocked; SPU verifier analysis remains the only clean lane.
- Visual check on clean base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
    - `FIELD_LIKE_PRESENT`
    - First field-like: `screenshot-0118s.png` at `118s`
- Parser strict checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - no reservation-loop correlation CSVs, decision `collect-missing-proof`.
- Artifact inspection:
  - `spu-contracts/BLUS30161/latest-summary.md` regenerated at `2026-05-29T16:11:41.8769009-04:00`.
  - `spu-contracts/BLUS30161/index.json` sourced from `20260529-095956`.
  - `spu-contracts/BLUS30161/source-alignment.md`, `verify-counter-plan.md`, `verify-counter-schema.md`, and `verify-logrow-implementation.md` refreshed with no behavior delta.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/align Windows-upstream `hle_mode=contract-25cc-9e4000` parseable row with reject buckets only (no behavior changes), then rerun strict parser + verified `field` + `options-menu` + `first-battle` with same schema before any fast-path proposal.

## 2026-05-29 15:52:28-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T15:52:28.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200.`
- Route pressure state: refiner remains blocked on movement; latest clean base remains `20260529-095956` and no movement/final battle counterproof exists.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary: route/movement reruns remain blocked; SPU verifier lane remains the valid next step.
- Visual gate on clean base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Strict parser checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - missing command/exact-PC/wait CSVs; decision `collect-missing-proof`.
- Artifact inspection:
  - `spu-contracts/BLUS30161/latest-summary.md` regenerated at `2026-05-29T15:51:55.5970986-04:00`.
  - `spu-contracts/BLUS30161/index.json` sourced from `20260529-095956`.
  - `spu-contracts/BLUS30161/source-alignment.md`, `verify-counter-plan.md`, `verify-counter-schema.md`, and `verify-logrow-implementation.md` refreshed with no behavioral delta.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/align Windows-upstream `hle_mode=contract-25cc-9e4000` parseable row with reject buckets only (no behavior changes), then rerun strict parser + verified `field` + `options-menu` + `first-battle` with same schema before any fast-path proposal.

## 2026-05-29 15:31:51-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T15:31:51.2624494-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200.`
- Route pressure state: refiner remains blocked on movement; latest run with clean no-movement boundary still `20260529-095956` and no movement/final battle counterproof exists.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary: continue to block loader-control repeats; SPU verifier analysis remains the only valid next lane.
- Visual gate on clean base:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Strict parser (clean base log):
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1` (`no contract verifier rows found`)
- Reservation-loop summary:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - missing command/exact-PC/wait CSVs; decision `collect-missing-proof`.
- JSON inspection:
  - `spu-contracts/BLUS30161/index.json` now sourced from `20260529-095956`.
  - Both contracts present (`pc025cc` and `pc0451c`) with 80 hot hits each.
  - `verifier.required_visuals`: `field`, `options-menu`, `first-battle`; `fast_mode` remains blocked.

## Artifact Inspection
- `spu-contracts/BLUS30161/latest-summary.md` regenerated; contracts unchanged.
- `spu-contracts/BLUS30161/source-alignment.md` and verify artifacts (`verify-counter-plan.md`, `verify-counter-schema.md`, `verify-logrow-implementation.md`) remain consistent with previous lane rule: implement log-only verify counters/reject buckets before any fast-mode behavior.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/align Windows-upstream `hle_mode=contract-25cc-9e4000` parseable row with reject buckets only (no behavior changes), then rerun strict parser + verified `field` + `options-menu` + `first-battle` with same schema before any fast-path proposal.

## 2026-05-29 15:12:31-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T15:12:31.7925116-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200.`
- Route pressure state: repeated `NO_FIELD_LIKE_SCREENSHOT` on the latest left200 attempt (`20260529-100836`) keeps movement blocked; clean no-movement boundary remains `20260529-095956`.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Refiner summary: route/movement reruns remain blocked; SPU contract verifier lane is now the preferred step.
- Strict parser checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - missing command/exact-PC/wait CSVs; decision `collect-missing-proof`.

## Artifact Inspection
- `spu-contracts/BLUS30161/latest-summary.md` regenerated at `2026-05-29T15:12:09.0406848-04:00` and still shows 2 contracts.
- `spu-contracts/BLUS30161/source-alignment.md` still confirms Windows upstream has 25cc family and 451c list predicates already present; vendored core remains generic-only.
- `spu-contracts/BLUS30161/verify-counter-schema.md` and `verify-logrow-implementation.md` still require an explicit Windows-upstream verify-only row (`hle_mode=contract-25cc-9e4000`) plus reject buckets before any fast-path behavior change.

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/align Windows-upstream `hle_mode=contract-25cc-9e4000` log-only row and reject buckets (no fast/body changes), then rerun strict parser + field + Options + first-battle captures before any promotion.

## 2026-05-29 14:52:06-04:00 Refiner-Blocked SPU Verify Gate Hold

## Run Stamp
- Timestamp: `2026-05-29T14:52:06.0611791-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200.`
- Route pressure state: movement remains blocked (`20260529-100836` is still invalid field), so we stayed on SPU contract analysis only.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Visual gate:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
    - `FIELD_LIKE_PRESENT`
    - First field-like: `screenshot-0118s.png` at `118s`
- Parser strict check (field log):
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Parser strict check (movement log):
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- SPU reservation loop summaries:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
    - missing cmd/exact-PC/wait CSVs, decision `collect-missing-proof`
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
    - `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`, decision `collect-missing-proof`

## Artifact Inspection
- `spu-contracts/BLUS30161/latest-summary.md` regenerated at `2026-05-29T14:51:37.8095997-04:00`.
- Contract JSON + verify artifacts (12 files) were refreshed by the pipeline run; no behavior code changes yet.
- `verify-counter-plan.md` / `verify-counter-schema.md` unchanged in substance: priority lane remains `mfc-descriptor-family-25cc-9e4000`, all fast modes blocked pending field+Options+first-battle proof with zero mismatches/overflow/fatals.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Implement/align `hle_mode=contract-25cc-9e4000` log row + reject bucket emit in Windows upstream next, then run strict parser and Field + Options + first-battle captures before any fast route.

## 2026-05-29 14:50:00-04:00 SPU Contract Rebuild + Verify-Only Evidence Check

## Run Stamp
- Timestamp: `2026-05-29T14:50:00.5801006-04:00` (local)
- Branch: `master`
- Refiner decision (re-read): `Do not auto-rerun loader-control-left200.`
- Route pressure state: unchanged; movement remains blocked by `NO_FIELD_LIKE_SCREENSHOT` on `20260529-100836`.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Visual check (clean base):
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
    - `FIELD_LIKE_PRESENT`
    - First field-like: `screenshot-0118s.png` at `118s`
- Parser strict checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- SPU reservation loop summaries:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
    - missing cmd/exact-PC/wait CSVs, `Decision: collect-missing-proof`
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
    - `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`, `Decision: collect-missing-proof`

## Artifact Inspection
- `spu-contracts/BLUS30161/latest-summary.md` regenerated at `2026-05-29T14:49:31.4538480-04:00`.
- Contracts remain:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `verify-counter-plan.md` and `verify-counter-schema.md` still indicate priority-1 lane is `mfc-descriptor-family-25cc-9e4000` with all fast modes blocked pending clean field/Options/first-battle proof.
- `source-alignment.md` confirms Windows upstream has predicate at `rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:656` / `:683`; vendored Android core still lacks the same predicate lane.
- `spu-contracts/.../verify-logrow-implementation.*` still scaffold-only; no fast-mode behavior change executed.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep verify-only lane: implement/align the Windows upstream `hle_mode=contract-25cc-9e4000` parse row and reject buckets first, then rerun strict parser and field + options + first-battle captures together with clean visuals before considering any fast mode or bodyfast/GPU path.

## 2026-05-29 14:24:10-04:00 Verify-Only Counter-Row Planning Pass

## Run Stamp
- Timestamp: `2026-05-29T14:24:10.0000000-04:00` (local)
- Branch: `master`
- Refiner decision (re-read): `Do not auto-rerun loader-control-left200.`
- Route pressure state: unchanged; movement remains blocked, no fresh field+Options+battle proof since earlier runs.

## Action Taken

- Re-opened and inspected updated SPU contract artifacts:
  - `spu-contracts/BLUS30161/index.json`
  - `spu-contracts/BLUS30161/BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0.json`
  - `spu-contracts/BLUS30161/BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0.json`
  - `spu-contracts/BLUS30161/verify-counter-plan.md`
  - `spu-contracts/BLUS30161/verify-counter-schema.md`
  - `spu-contracts/BLUS30161/verify-logrow-implementation.md`
  - `spu-contracts/BLUS30161/source-alignment.md`

## Contract/Schema Inspection Summary
- Target lane remains priority `mfc-descriptor-family-25cc-9e4000` on contract `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- Fast mode remains `blocked`.
- Required visuals remain `field`, `options-menu`, `first-battle`.
- Verify row scaffold is concrete and still parser-ready:
  - Required row keys include `contract_id`, `contract_hits`, `contract_bytes`, `reject_*` buckets, `desc_overflow`, `output_mismatch`, and source hash fields.
  - Example row in `verify-logrow-implementation.md` uses `reject_fast_mode` and `contract_hits == get + put` checks.
- Source alignment confirms:
  - Priority-1 25cc runtime-family predicate is present in `rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`.
  - Vendored RPCSX core still lacks the 25cc/451c contract predicate lane and should not be treated as ready for fast-path promotion.

## Next Step (Verified and Logged)
- No movement/fast-mode change this checkpoint.
- Do an upstream Windows log-only patch for the `contract-25cc-9e4000` row + reject buckets (no behavior change), then rerun field/Options/first-battle captures under strict parser gates.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `verify-counter-plan`

## 2026-05-29 14:11:54-04:00 SPU Verify-Only Hold + Pipeline Refresh

## Run Stamp
- Timestamp: `2026-05-29T14:11:54.0000000-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: movement remains blocked; latest clean field proof is `20260529-095956`, latest movement visual-fail is `20260529-100836`.

## Action Taken

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Verification

- Visual checks:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
    - `FIELD_LIKE_PRESENT`
    - First field-like: `screenshot-0118s.png` at `118s`
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
    - `NO_FIELD_LIKE_SCREENSHOT`
- Log checks:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`
    - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
    - `rows=0`, `accepted_rows=0`, `contract_hits=0`
    - `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Counter checks:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
    - Missing loop CSVs, decision `collect-missing-proof`
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
    - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
    - Decision `collect-missing-proof`

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` refreshed from `20260529-095956` at `2026-05-29T14:11:18-04:00`.
- Contracts stayed the same (`0x025cc` and `0x0451c`) with image signature `0x958dfe208b686622`.
- `latest-summary.md`, `source-alignment.*`, `verify-counter-plan.*`, `verify-counter-schema.*`, `verify-logrow-implementation.*` refreshed for timestamps; `fast_mode` remains `blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Continue verify-only lane:
  - do not change fast paths on this evidence yet;
  - wire/align Windows upstream log-row+reject-bucket counters for `hle_mode=contract-25cc-9e4000`;
  - then rerun strict parser and field + Options + first-battle with the same verify schema before any `verify`→`fast` promotion.

## 2026-05-29 13:50:32-04:00 Refiner-Blocked SPU Verification Hold

## Run Stamp
- Timestamp: `2026-05-29T13:50:32.3584417-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: movement blocked by `NO_FIELD_LIKE_SCREENSHOT` on `20260529-100836`; clean boundary `20260529-095956` still route-triage only.

## Action Taken

Per refiner block, we stayed on verify-only SPU contract lane and refreshed the same evidence:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - Gate: failed

## Log Verification
- Strict parse on clean field log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `total_contract_bytes=0`, `failures=no contract verifier rows found`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Strict parse on movement log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `total_contract_bytes=0`, `failures=no contract verifier rows found`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal scans stayed clean for route-critical fatal classes in both logs.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `command-correlation-data-missing`, `collect-missing-proof`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - `collect-missing-proof` (no capsule/pair-verifier rows)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` regenerated at `2026-05-29T13:50:36.5333670-04:00` from `RunDir 20260529-095956...`.
- Contracts unchanged (`0x025cc` and `0x0451c`) with image sig `0x958dfe208b686622`; generated timestamps in `latest-summary.md`, `source-alignment.md/json`, and verify scaffolds refreshed to `13:50:36.x`.
- `latest-summary.md`, `verify-counter-plan.md`, `verify-counter-schema.md`, `verify-logrow-implementation.md` remain verify-only, with `fast_mode=blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Continue verify-only SPU contract lane.
- Implement/align Windows upstream `hle_mode=contract-25cc-9e4000` row+reject buckets in one pass, then rerun strict parser + field, Options/menu, and first-battle under the same verify gate before any fast mode.

## 2026-05-29 13:31:23-04:00 Refiner-Blocked SPU Verification Hold

## Run Stamp
- Timestamp: `2026-05-29T13:31:23.9963532-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: movement remains blocked by `NO_FIELD_LIKE_SCREENSHOT` on `20260529-100836`; clean boundary `20260529-095956` remains field-like.

## Action Taken

Per refiner block, we remained in verify-only SPU mode and refreshed the same 25cc/451c evidence:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - Gate: failed

## Log Verification
- Strict parse on clean field log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `total_contract_bytes=0`, `failures=no contract verifier rows found`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Strict parse on movement log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `total_contract_bytes=0`, `failures=no contract verifier rows found`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal scans stayed clean for route-critical fatal classes in both logs.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `command-correlation-data-missing`, `collect-missing-proof`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - `collect-missing-proof` (no capsule/pair-verifier rows)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` regenerated at `2026-05-29T13:31:27.8611815-04:00` from `RunDir 20260529-095956...`.
- Contracts unchanged (`0x025cc` and `0x0451c`), `image_sig` `0x958dfe208b686622`, generated timestamps refreshed to `2026-05-29T13:31:27.x/13:31:27.x`.
- `latest-summary.md`, `source-alignment.json`, `source-alignment.md`, `verify-counter-plan.md`, `verify-counter-schema.json/md`, `verify-logrow-implementation.json/md` remain verify-only, with `fast_mode=blocked` and same verify-counter reject shape.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold on verify-only SPU contract lane.
- Implement/align Windows upstream `hle_mode=contract-25cc-9e4000` row+reject buckets in one pass, then rerun strict parser + visual checks for clean field, Options/menu, and first-battle before any fast-mode attempt.

## 2026-05-29 13:10:21-04:00 Refiner-Blocked SPU Pipeline Re-Bind (Verify-Only Hold)

## Run Stamp
- Timestamp: `2026-05-29T13:10:21.7353294-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: movement remains blocked (`left200` `NO_FIELD_LIKE_SCREENSHOT` on `20260529-100836`); `20260529-095956` remains clean field-only.

## Action Taken

Per refiner block, we continued SPU contract verification and refreshed artifacts:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - Gate: failed

## Log Verification
- Strict parse on clean field log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Strict parse on movement log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - same (`rows=0`, `accepted_rows=0`, `contract_hits=0`)
- Targeted fatal scans stayed clean for route-critical fatal markers in both logs.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `command-correlation-data-missing`, `collect-missing-proof`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - `collect-missing-proof` (no capsule/pair-verifier rows)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` regenerated at `2026-05-29T13:10:26.7010098-04:00` from `RunDir 20260529-095956...`.
- Contracts unchanged (`0x025cc` and `0x0451c`) with generated timestamps refreshed to `2026-05-29T13:10:13.x/13:10:14.x` range.
- `latest-summary.md`, `source-alignment.json`, `source-alignment.md`, `verify-counter-plan.md`, `verify-counter-schema.json`, `verify-counter-schema.md`, `verify-logrow-implementation.json`, `verify-logrow-implementation.md` remain verify-only, with `fast_mode=blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Keep to verify-only SPU lanes only.
- Add/complete Windows upstream `hle_mode=contract-25cc-9e4000` contract-id and reject accounting in a dedicated path, then rerun strict parser plus field/Options/first-battle gated checks.

## 2026-05-29 12:50:57-04:00 Refiner-Blocked SPU Verification Hold

## Run Stamp
- Timestamp: `2026-05-29T12:50:57.5384136-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: `left200` remains `NO_FIELD_LIKE_SCREENSHOT` on movement (`100836`) while `095956` stays `FIELD_LIKE_PRESENT`; no field+Options+first-battle proof.

## Action Taken

Per refiner block, we stayed on SPU contract verification and re-ran artifact refresh:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - Gate: failed

## Log Verification
- Strict parse on clean field log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Strict parse on movement log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - same result (`rows=0`, `accepted_rows=0`, `contract_hits=0`)
- Targeted fatal scans for both logs remained clean for route-critical fatal classes (no VM access, SPU STOP, Vulkan device loss, assertion, segfault markers).

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `command-correlation-data-missing`, `collect-missing-proof`
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - `collect-missing-proof` (no capsule/pair verifier rows)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` refreshed and regenerated at `2026-05-29T12:50:14.1218718-04:00` from the same source run.
- `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0.json` and `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0.json` refreshed timestamps only.
- `source-alignment`, `verify-counter-plan`, `verify-counter-schema`, and `verify-logrow-implementation` remain `fast_mode=blocked` and unchanged in structure.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Continue verify-only SPU contract lane: keep Windows route control closed, finish `hle_mode=contract-25cc-9e4000` row emit/counter reject plumbing in an isolated path, then rerun strict parser + field/options/first-battle triage before any fast path.

## 2026-05-29 12:31:18-04:00 Refiner-Blocked SPU Pipeline Re-Bind (No New Evidence)

## Run Stamp
- Timestamp: `2026-05-29T12:31:18-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: route movement remains blocked by `NO_FIELD_LIKE_SCREENSHOT` (`100836`) while `095956` remains clean field-only.

## Action Taken

Per refiner block, we re-ran the non-duplicative SPU-only lane:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- Base field run remained valid:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Movement rerun remained invalid:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- Strict parser on clean field log:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`
- Strict parser on movement log:
  - same strict failures, no accepted rows.
- Targeted fatal scan in both logs: only `Show fatal error hints: false`; no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `command-correlation-data-missing` / `collect-missing-proof` (no command / exact-PC / MFC wait CSVs)
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - `collect-missing-proof` (no capsule/pair-verifier rows yet)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` refreshed against the same clean source run.
- Contracts unchanged (`2`): `0x025cc` and `0x0451c` (`image_sig 0x958dfe208b686622`), with generated timestamps re-synced.
- `source alignment`, `verify-counter-plan`, `verify-counter-schema`, and `verify-logrow-implementation` remain verify-only (`fast_mode=blocked`) on `mfc-descriptor-family-25cc-9e4000`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Stay on verify-only SPU contract work only.
- Implement/align Windows upstream `hle_mode=contract-25cc-9e4000` log-row and counter reject buckets, then rerun strict parser + visual checks for clean field, Options, and first battle before any fast-path attempts.

## 2026-05-29 11:50:35-04:00 Refiner-Blocked SPU Verification Lane Hold

## Run Stamp
- Timestamp: `2026-05-29T11:50:35-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: clean base stays `FIELD_LIKE_PRESENT` (`095956`) while `100836` remains route-invalid; no movement, route, or promotion headway this cycle.

## Action Taken

Per refiner block, we took the non-duplicative SPU analysis step only:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`

## Visual Verification
- Base-route proof remained field-clean:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Movement rerun remained invalid:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- Strict parser checks remained empty of contract rows on both logs:
  - Base log: `rows=0`, `accepted_rows=0`, `contract_hits=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`
  - Movement log: same strict failures, no accepted rows.
- Targeted fatal scan:
  - Both `RPCS3.log` files had no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault` markers.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - No command/PC/mfc wait CSVs available.
  - Decision: `collect-missing-proof` (`command-correlation-data-missing`).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`.
  - No capsule/pair-verifier rows -> `collect-missing-proof`.

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` was regenerated from `RunDir 20260529-100836...`.
- Generated contracts unchanged (`2`): `0x025cc` and `0x0451c` with `image_sig 0x958dfe208b686622`; source alignment still marks Windows upstream as implementation target and vendored core as lacking 25cc/451c contract predicates.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold on verify-only SPU contract counter instrumentation only. Add/align the 25cc contract log-row in Windows upstream, then rerun strict parser checks on clean field + Options + first-battle runs.

## 2026-05-29 12:09:43-04:00 Refiner-Blocked SPU Pipeline Re-Bind to Clean Field Evidence

## Run Stamp
- Timestamp: `2026-05-29T12:09:43-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: no movement progress; base run remains clean field route, with 100836 still no-field route miss.

## Action Taken

Per refiner block, we executed a non-duplicative SPU lane refresh on the clean base field evidence:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- Clean-field route evidence stayed valid:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- `100836` route remained invalid under the same command family:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- Strict parser checks remained empty of contract rows:
  - `20260529-095956`: `rows=0`, `accepted_rows=0`, `contract_hits=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`.
  - `20260529-100836`: same strict failures, no accepted rows.
- Targeted fatal scan:
  - No `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault` markers in either log.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - Still missing command/PC/mfc-wait CSVs.
  - Decision: `collect-missing-proof` (`command-correlation-data-missing`).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - No capsule/pair-verifier rows available; decision `collect-missing-proof`.

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` source run is now `20260529-095956`.
- Contracts remain `2` (`0x025cc` and `0x0451c`) with `image_sig 0x958dfe208b686622`; schema/plan/source alignment JSON/MD files updated from this fresh source binding.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Continue verify-only SPU lane: add/align Windows upstream contract-row/log labeling + reject buckets for `mfc-descriptor-family-25cc-9e4000`, then rerun strict parser + visual checks for field + Options + first-battle before any fast-mode path.

## 2026-05-29 11:28:39-04:00 Refiner-Blocked SPU Re-Validation + Parser/Counter Hold

## Run Stamp
- Timestamp: `2026-05-29T11:28:39-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: route movement remains blocked; base remains `FIELD_LIKE_PRESENT` (`095956`) while `100836` remains no-field movement miss.

## Action Taken

Per repeated refiner block, we re-ran the SPU pipeline only:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- Base run stayed field-clean:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Movement rerun remained invalid:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- Strict parser checks remained empty of contract rows on both checked logs:
  - Base log strict:
    - `rows=0`, `accepted_rows=0`, `total_contract_hits=0`
    - strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`
  - Movement log strict:
    - same strict failures, no accepted rows.

- Targeted fatal scan:
  - `Show fatal error hints: false` only; no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault`.

## Counter Verification
- Base run command/PC/mfc exact data are still missing:
  - `command-correlation-data-missing` (`collect-missing-proof`)
- Movement run still has no kernel capsule/pair-verifier rows:
  - `Kernel capsule rows: 0`
  - `Reservation command rows: 1767`
  - `Reservation command exact-PC rows: 49648`
  - `Command-run MFC wait exact-PC rows: 100813`
  - Decision: `collect-missing-proof`

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` regenerated with:
  - `generated_at: 2026-05-29T11:28:37.4758459-04:00`
  - unchanged two-contract set (`0x025cc`, `0x0451c` at `image_sig 0x958dfe208b686622`).

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold until Windows upstream emits `hle_mode=contract-25cc-9e4000` contract rows and kernel-capsule + pair-verifier correlation data under clean route/tooling; then re-run strict field + Options + first-battle verify sequence before any fast mode.


## 2026-05-29 11:09:48-04:00 Refiner-Blocked SPU Refresh + Verify-Only Readiness Recheck

## Run Stamp
- Timestamp: `2026-05-29T11:09:48-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: newest base is clean field-only (`095956`) and newest movement attempt still `NO_FIELD_LIKE_SCREENSHOT` (`100836`); no route progress this cycle.

## Action Taken

Per refiner block, we refreshed the SPU contract artifacts and re-verified the same evidence with no new movement rerun:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `20260529-095956` base run remained field-clean:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Movement rerun remained blocked by no field capture:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- Strict SPU contract parser check failed on both checked logs:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`
- Same strict output on movement run:
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`
- Fatal log scan:
  - Both checked `RPCS3.log` files contain only `Show fatal error hints: false`; no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - Command/exact-PC/mfc exact-PC CSVs missing.
  - Decision: `collect-missing-proof` (`command-correlation-data-missing`)
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - Decision: `collect-missing-proof` (missing kernel-capsule / pair-verifier rows for narrow fast-path claims)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` now points to `source_run = ...\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`.
- Regenerated contract artifacts remain `2` contracts:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` (`hle_mode=contract-25cc-9e4000`)
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `verify-counter-plan.md` and `verify-counter-schema.md` remain locked to priority-1 `mfc-descriptor-family-25cc-9e4000` with `verify-only`/`fast_mode=blocked` and required `field/options/first-battle`.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Stay in verify-only SPU planning mode.
- Plan and implement `hle_mode=contract-25cc-9e4000` verify counters/reject buckets in Windows upstream next, then rerun clean field + Options + first-battle with strict parser gates before any fast-path switch.


## 2026-05-29 10:48:54-04:00 Refiner-Blocked SPU Refresh + Missing Verifier Rows

## Run Stamp
- Timestamp: `2026-05-29T10:48:54-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: latest valid base (`095956`) still only field-triage and movement lane remains blocked by `NO_FIELD_LIKE_SCREENSHOT` on `100836`.

## Action Taken

Per refiner block, reran the SPU pipeline and did not execute any additional Windows movement route:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- Base field run remained clean:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `FIELD_LIKE_PRESENT`
  - First field-like: `screenshot-0118s.png` at `118s`
- Movement rerun remained a gate miss:
  - `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`

## Log Verification
- `parse_spu_contract_verify_log` on base run (strict):
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, failures `accepted_rows_lt_1`, `contract_hits_lt_1` (`no contract verifier rows found`)
- Same strict result on movement run (`100836`):
  - `rows=0`, `accepted_rows=0`, `contract_hits=0`, failures `accepted_rows_lt_1`, `contract_hits_lt_1`
- Fatal-string scan on both checked logs found only `Show fatal error hints: false`; no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault`.

## Counter Verification
- Base run still lacked command/exact-PC/mfc exact-PC captures:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `collect-missing-proof` (`command-correlation-data-missing`)
- Movement run:
  - `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Reservation command exact-PC rows: 49648`, `Command-run MFC wait exact-PC rows: 100813`
  - Decision: `collect-missing-proof` (still missing kernel capsule/pair verifier rows for narrow fast-path claims).

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json` refreshed with source run timestamp `2026-05-29T10:48:46.3177066-04:00`.
- Contracts unchanged: the same two contracts for PCs `0x025cc` and `0x0451c`; no source-run scope changes.
- `verify-counter-plan.md` still keeps `mfc-descriptor-family-25cc-9e4000` as priority-1 with `verify-only` gating.

## Classification
- `analysis`
- `valid-field-triage`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold in verify-planning only. No route progress and no fast-path change until Windows upstream emits verify-only contract rows for priority-1 `hle_mode=contract-25cc-9e4000` and field/options/first-battle are revalidated under that row.

## 2026-05-29 10:30:22-04:00 Refiner Block + SPU Verify-Only Collect-Missing Check

## Run Stamp
- Timestamp: `2026-05-29T10:30:22-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run.`
- Route pressure state: latest route proof remains blocked by visual-fail (`NO_FIELD_LIKE_SCREENSHOT` on `100836...`) and repeated overlay/noise; this checkpoint stays verify-only.

## Action Taken

Per refiner block, we ran the SPU contract refresh against the newest clean 0x25cc/0x451c/0x9e4000 evidence and did not run additional Windows movement:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0118s.png` at `118s`

- Latest route-check rerun (`100836...`) against movement lane remained:
  `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
  - Status: `NO_FIELD_LIKE_SCREENSHOT`
  - Class: `loading-like-small-png: 14`

## Log Verification
- Parse check on the clean base run had zero verifier rows:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Rows: `0`, Accepted: `0`, Contract hits: `0`, Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - Strict result: `failed` (`no contract verifier rows found`)
- Same strict parse failure on movement attempt:
  - `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Rows: `0`, Accepted: `0`, Contract hits: `0`, Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal/invalid-hit grep on both checked logs returned no `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or `Segmentation fault` hits; only `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - Missing command/exact-PC/mfc exact-PC artifacts -> `collect-missing-proof` (`command-correlation-data-missing`).
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `MFC wait exact-PC rows: 100813`
  - Decision: `collect-missing-proof` (missing kernel capsule/pair verifier rows for narrow fast-path claims).

## SPU Contract Artifact Inspection
- Pipeline now points `spu-contracts/BLUS30161` to source run `20260529-095956...`.
- Contracts remain `2`:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- `spu-contracts/BLUS30161/verify-counter-plan.md` and `verify-logrow-implementation.md` still indicate priority-1: `mfc-descriptor-family-25cc-9e4000` and still `verify-only-required` with zero-overflow/zero-fatal preconditions.

## Classification
- `analysis`
- `failed-visual-gate`
- `valid-field-triage`
- `failed-logrow-parser`
- `spu-contract-scaffold`
- `spu-reservation-loop-summary`
- `collect-missing-proof`

## Next Step
- Hold at verify planning: implement emitters/counters in Windows upstream for priority-1 `hle_mode=contract-25cc-9e4000` and re-run field + Options + first-battle under same verify row gating before any fast-mode claim.

## 2026-05-29 10:20:58-04:00 SPU Contract Refresh + Visual/Parser Recheck (Refiner-Blocked Window Step)

## Run Stamp
- Timestamp: `2026-05-29T10:20:58-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Do not auto-rerun loader-control-left200. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or run focused SPU kernel HLE/codegen/verifier analysis next.`
- Route pressure state: the latest route proof was invalid (`NO_FIELD_LIKE_SCREENSHOT` on `20260529-100836...`), so movement was blocked by anti-patterns; this round stayed in SPU analysis lane.

## Action Taken

Per refiner block, we skipped a duplicate Windows movement rerun and updated the SPU contract pipeline using the cleanest available base run:

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0118s.png` at `118s` (`2.50 MB`)
- Class counts: `field-like-large-png: 10`
- Invalid screenshots after first field-like: `0`

- Latest attempted rerun (for route-pressure check): `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `NO_FIELD_LIKE_SCREENSHOT`
- Class counts: `loading-like-small-png: 14`
- Invalid screenshots after first field-like: `0` (never reached)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Rows: `0`
  - Accepted: `0`
  - Contract hits: `0`
  - Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - Strict parser result: failed (`no contract verifier rows found`)

- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
  - Rows: `0`
  - Accepted: `0`
  - Contract hits: `0`
  - Strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - Strict parser result: failed (`no contract verifier rows found`)

Targeted fatal scan on `20260529-100836` (`VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, `Segmentation fault`) returned `0` hits each.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
  - `Kernel capsule rows: 0`, `MFC wait exact-PC rows: 0`, `Command-run MFC wait exact-PC rows: 0`
  - Decision: `collect-missing-proof` (no kernel exact-PC correlation files in this run)

- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -Top 12`
  - `Kernel capsule rows: 0`, `Reservation command rows: 1767`, `Command-run MFC wait exact-PC rows: 100813`
  - Decision: `collect-missing-proof` (missing kernel capsule and pair verifier rows for narrow fast-path proof)

## SPU Contract Artifact Inspection
- `spu-contracts/BLUS30161/index.json`: source run now set to `20260529-095956`, contracts `pc025cc` + `pc0451c`, both `hot_log_hits=80`.
- `spu-contracts/BLUS30161/source-alignment.md`: Windows upstream still has priority-1 `0x25cc/0x9e4000` and priority-2 `0x451c` predicates; vendored RPCSX still lacks contract predicates.
- `spu-contracts/BLUS30161/verify-counter-plan.md`: priority-1 lane remains `mfc-descriptor-family-25cc-9e4000`; `fast_mode=blocked`; required verifier environment remains `verify-only-required` with required visuals (`field`, `options-menu`, `first-battle`) plus zero mismatch/overflow/fatal.
- `spu-contracts/BLUS30161/verify-counter-schema.md`: verify-only counter schema confirms required `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` and explicit reject buckets.
- `spu-contracts/BLUS30161/verify-logrow-implementation.md`: scaffold still points to parseable row `Eternal Sonata SPU contract verifier` with `hle_mode=contract-25cc-9e4000`.

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-logrow-parser`
- `spu-contract-pipeline`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`
- `route-tooling`

## Next Step
- Keep this as route-tooling/evidence-only; no speed, first-battle, or `gpu-migration-credit` claim.
- Next required action is implementation work for priority-1 verify-only counter/reject buckets in Windows upstream before any fast-mode change:
  - emit log row with `contract_id=mfc-descriptor-family-25cc-9e4000`
  - add reject-bucket counters
  - re-run `check_eternal_sonata_windows_visual_gate.ps1` for field + Options + first-battle under clean conditions
  - only then evaluate a fast-path candidate.

## 2026-05-29 10:08:36-04:00 Loader-Control Left200 Visual-Fail + Contract Pipeline Refresh

## Run Stamp
- Timestamp: `2026-05-29T10:08:36-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Use newest valid loader-control as route base, then add one small state-aware movement step with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked.`
- Route pressure state: clean host, but loader-control step still blocked by no field-like capture.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10
```

## Run Dir
- `debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -RequireFieldLike -RequireFieldAtOrBeforeSeconds 160 -RequireNoInvalidAfterFirstField`
- Status: `NO_FIELD_LIKE_SCREENSHOT`
- First field-like screenshot: `none`
- Class counts: `loading-like-small-png: 14`
- Host contention summary: clean (`6` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, assert, or hard crash hit found; only startup `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-100836-cpu4-loader-control-left200-visualgate-windows-windows -Top 12`
- Kernel capsule rows: `0`
- MFC wait exact-PC rows: `0`
- Reservation command rows: `1767`
- Reservation command exact-PC rows: `49648`
- Command-run MFC wait exact-PC rows: `100813`
- Decision: `collect-missing-proof` (no kernel-capsule or exact-PC command pair evidence for narrow fast-path proof)

## SPU Contract Pipeline Sync
- `.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000`
- Refreshed `spu-contracts\BLUS30161` artifacts and kept priority-1 / priority-2 rows:
  - `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
- Lane-1 counter plan stays `mfc-descriptor-family-25cc-9e4000`, with `fast_mode=blocked` and `verifier.mode=verify-only-required`.
- `spu-contracts\BLUS30161\source-alignment.md` continues to show Windows upstream predicate presence for `0x025cc`/`0x9e4000` and missing vendored predicates.

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-logrow-parser`
- `route-tooling`
- `spu-contract-pipeline`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep this as route-tooling evidence only; no speed, first-battle, or `gpu-migration-credit` claim.
- Do not rerun the same `cpu4-loader-control-left200-visualgate-windows` command sequence.
- Next required action remains: implement/port verify-only contract row and reject buckets for `mfc-descriptor-family-25cc-9e4000` in Windows upstream, then rerun field + Options/menu + first-battle under strict visual and parser gates.

## 2026-05-29 10:06:41-04:00 Field-Recovered Loader-Control Route Repair (v15)

## Run Stamp
- Timestamp: `2026-05-29T10:06:41-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Add or use black-overlay route control before any movement or lane-2 HLE/GPU dry-run.`
- Route pressure state: `repeated-black-overlay-pre-field` was still active before this run; this step is route-tooling only.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows-v15 -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

## Run Dir
- `debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0118s.png` at `118s` (`2.50 MB`)
- Class counts: `field-like-large-png: 10`
- Invalid screenshots after first field-like: `0`
- Host contention summary: clean (`6` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, assert, or hard crash hit found; only startup `Show fatal error hints: false`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
- No reservation-loop CSVs were available (`command`, `command exact-PC`, `MFC-wait`), so no counter attribution is possible.
- Decision: `collect-missing-proof`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep this as route-tooling evidence only. Do not claim speed, first-battle, `gpu-migration-credit`, or 200% progress.
- Next required action remains priority-1 verify-only counter instrumentation for `0x25cc/0x9e4000` after a field + Options + first-battle cleanup sequence with same non-blocking route base.

## 2026-05-29 09:20:43-04:00 Black-Overlay Loader Control Reproof + Pipeline Refresh (Non-duplicate v9)

## Run Stamp
- Timestamp: `2026-05-29T09:20:43-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Add or use black-overlay route control before any movement or lane-2 HLE/GPU dry-run.`
- Route pressure state: route-control repeat blocker is active (`repeated-black-overlay-pre-field`); this step is route-tooling only and non-promotional.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8
```

## Run Dir
- `debug-captures\windows-lab\20260529-090732-cpu4-loader-control-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-090732-cpu4-loader-control-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `NO_FIELD_LIKE_SCREENSHOT`
- First field-like screenshot: `none`
- Class counts: `black-overlay-small-png: 10`
- Invalid screenshots after first field-like: `0` (none reached)
- Host contention summary: clean (`6` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-090732-cpu4-loader-control-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, assert, or hard crash hit found in this artifact.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-090732-cpu4-loader-control-visualgate-windows-windows`
- No reservation-loop CSVs were available (`command`, `command exact-PC`, `MFC-wait`), so no counter attribution is possible.
- Decision: `collect-missing-proof`

## SPU Contract Pipeline Sync
- `.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-090031-cpu4-stateaware-one-step-visualgate-v8-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6`
- Refreshed: `spu-contracts\BLUS30161\latest-summary.md`, `index.json`, `verify-counter-plan.md/json`, `source-alignment.md/json`, `verify-counter-schema.md/json`, `verify-logrow-implementation.md/json`, and per-PC JSON rows.
- Priority-1 contract remains `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`; priority-2 remains `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`.
- `fast_mode=blocked` and `verifier.mode=verify-only-required` remain unchanged.

## Classification
- `analysis`
- `failed`
- `failed-visual-gate`
- `failed-logrow-parser`
- `route-tooling`
- `spu-contract-scaffold`
- `spu-contract-pipeline`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep this as route-tooling evidence only. Do not claim speed, first-battle, `gpu-migration-credit`, or 200% progress.
- Next action remains priority-1 verify-only counter instrumentation only for `0x25cc/0x9e4000`; do not enable lane-2 HLE/GPU fast modes until field + Options + first-battle visuals are clean with zero mismatch/overflow/fatal logs.

## 2026-05-29 08:45:23-04:00 Stateaware One-Step Visual Gate + Missing Verifier Rows (Non-duplicate v7)

## Run Stamp
- Timestamp: `2026-05-29T08:45:23-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling; clean field triage only. This run is still clean on visuals with 8/8 field-like frames, but contract rows are still absent, so no verified counters available for promotion.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-v7-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 180 -ScreenshotEverySeconds 12 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 10
```

## Run Dir
- `debug-captures\windows-lab\20260529-084523-cpu4-stateaware-one-step-visualgate-v7-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-084523-cpu4-stateaware-one-step-visualgate-v7-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Class counts: `field-like-large-png: 8`
- Invalid screenshots after first field-like: `0`
- Host contention summary: clean (`6` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-084523-cpu4-stateaware-one-step-visualgate-v7-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking VM access violation, SPU unknown STOP, VK_ERROR_DEVICE_LOST, assert, or hard crash hit.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-084523-cpu4-stateaware-one-step-visualgate-v7-windows-windows`
- All reservation-loop CSVs missing in this run (`command`, `command exact-PC`, `MFC-wait`), so no kernel/counter attribution is possible.
- Decision: `collect-missing-proof`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep this as route-tooling evidence only. Do not claim speed, first-battle, `gpu-migration-credit`, or 200% progress.
- Next action is again to add `EternalSonataKernelCapsule` + `EternalSonataPutllc16Pair` coverage on a representative field-clean run, then rerun parser counters before any fast-path or promotion claim.

## 2026-05-29 08:27:35-04:00 Stateaware One-Step Visual Regression + Pipeline Retune

## Run Stamp
- Timestamp: `2026-05-29T08:27:35-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: latest route proof is invalid on visuals (`black-overlay-small-png`), so this cycle remains route-tooling and contract-scaffold only; no field/Options/battle movement proof.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-v5-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 240 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14
```

## Run Dir
- `debug-captures\windows-lab\20260529-081926-cpu4-stateaware-one-step-visualgate-v5-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-081926-cpu4-stateaware-one-step-visualgate-v5-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `NO_FIELD_LIKE_SCREENSHOT`
- First field-like screenshot: `none`
- Class counts: `black-overlay-small-png: 16`
- Invalid-after-field screenshots: `0` (none reached)
- Host contention summary: clean (`8` samples)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-081926-cpu4-stateaware-one-step-visualgate-v5-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking VM access violation, SPU unknown STOP, VK_ERROR_DEVICE_LOST, assert, or hard crash log hit; only startup/config export lines (e.g., `Show fatal error hints: false`, `_sys_panic` in loader table).

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-081926-cpu4-stateaware-one-step-visualgate-v5-windows-windows`
- Reservation command rows: `0`
- Reservation command exact-PC rows: `0`
- Command-run MFC wait exact-PC rows: `0`
- Command/read decision: `command-correlation-data-missing`
- Decision: `collect-missing-proof`

## SPU Contract Pipeline Sync
- `.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-073954-cpu4-stateaware-one-step-visualgate-v4-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6`
- JSON/MD inspection shows:
  - priority-1 contract: `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`
  - priority-2 contract: `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`
  - both `inferred_classes`: `dynamic-mfc-shape,dma-window,spurs-kernel`
  - both `verifier.mode`: `verify-only-required`
  - `required_visuals`: `field`, `options-menu`, `first-battle`
  - both `fast_mode = blocked`
  - required counters unchanged: `output_mismatch=0`, `descriptor_overflow=0`, `fatal_log_hits=0`

## Classification
- `analysis`
- `failed-visual-gate`
- `failed-logrow-parser`
- `route-tooling`
- `spu-contract-scaffold`
- `spu-contract-pipeline`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Do not claim speed, `gpu-migration-credit`, or 200% progress from this run.
- Next action is verify-only counter and route repair work: add/validate `0x25cc/0x9e4000` verify-only counters from `verify-counter-plan.md`, then rerun clean Field + Options + first-battle under strict `-FailOnGate` before any fast-mode experiments.

## 2026-05-29 07:39:54-04:00 Stateaware One-Step Visual Retry + Missing Verifier Rows

## Run Stamp
- Timestamp: `2026-05-29T07:39:54-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: visual route-tooling. The new state-aware pass is field-clean; verifier rows are still absent, so SPU fast paths remain verify-only and non-promotional.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-v4-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-073954-cpu4-stateaware-one-step-visualgate-v4-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-073954-cpu4-stateaware-one-step-visualgate-v4-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Class counts: `3` `field-like-large-png`
- Invalid-after-field screenshots: `0`
- Host contention samples: `clean` (`4` snapshots)

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-073954-cpu4-stateaware-one-step-visualgate-v4-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
- strict_failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
- Targeted fatal scan: no route-blocking `VM access violation`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, or hard crash hit; only startup/config log lines (`Show fatal error hints: false`, `_sys_panic` in loader export table).

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-073954-cpu4-stateaware-one-step-visualgate-v4-windows-windows`
- Reservation command rows: `1097`
- Reservation command exact-PC rows: `29762`
- Command-run MFC wait exact-PC rows: `55453`
- Command/read decision: `whole-loop-recognizer-preflight`
- Primary peaks remain GETLLAR/PUTLLC split across `TCX_CellSpursKernel0/1` with `PUTLLC16 pair verifier rows` unavailable.
- Decision: `collect-missing-proof`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## 2026-05-29 07:31:11-04:00 Stateaware One-Step Visual Miss + Pipeline Refresh

## Run Stamp
- Timestamp: `2026-05-29T07:24:25-04:00` (local)
- Branch: `master`
- Refiner decision (from immediate pre-pass): `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling; latest run missed visual gate, forcing SPU verify-lane refresh.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-v3-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-072425-cpu4-stateaware-one-step-visualgate-v3-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-072425-cpu4-stateaware-one-step-visualgate-v3-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `NO_FIELD_LIKE_SCREENSHOT`
- First field-like screenshot: `none`
- `loading-like-small-png`: `3`
- Invalid-after-first-field screenshots: `0` (none reached)
- Host contention: `prelaunch/postlaunch/runtime/postrun all clean`; external no-emulator contention.

## Log Verification
- `parse_spu_contract_verify_log` result:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
  - strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - failure reason: `no contract verifier rows found`
- Targeted fatal scan (`VM access`, `SPU unknown STOP`, `VK_ERROR_DEVICE_LOST`, `assert`, `fatal config hints`) found no blocking crash signatures in `RPCS3.log`/`rpcs3.stderr.txt`.

## Counter Verification
- `summarize_eternal_sonata_spu_reservation_loop.ps1` result:
  - `Kernel capsule rows: 0`
  - `MFC wait exact-PC rows: 0`
  - `PUTLLC16 pair verifier rows: 0`
  - `Reservation command rows: 1126`
  - `Reservation command exact-PC rows: 31023`
  - `Command-run MFC wait exact-PC rows: 60316`
  - `Command/read decision: whole-loop-recognizer-preflight`
  - Decision: `collect-missing-proof`

## SPU Contract Pipeline Sync
- `.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-071401-cpu4-stateaware-one-step-visualgate-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6`
- Refreshed:
  - `spu-contracts\BLUS30161\index.json`
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0.json`
  - `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0.json`
- Inspecting JSON confirms priority-1 lane is `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` and priority-2 lane is `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`.
- Both contracts remain `inferred_classes=[dynamic-mfc-shape,dma-window,spurs-kernel]`, `verifier.mode=verify-only-required`, and `fast_mode=blocked`.
- `source-alignment` and `verify-counter-plan` still indicate `0x25cc/0x9e4000` verify-only counter work only; no verifier rows yet.

## Classification
- `analysis`
- `failed-visual-gate`
- `route-tooling`
- `collect-missing-proof`
- `spu-contract-scaffold`
- `spu-contract-pipeline`
- `spu-reservation-loop-summary`
- `host-contention-clean`

## Next Step
- Do not claim speed, `gpu-migration-credit`, or 200% progress from this run.
- Keep route in repair mode while waiting for field + Options + first-battle visual proof.
- Before any fast-path candidate, implement/verify priority-1 `0x25cc`/`0x9e4000` verify-only counters and reject buckets (`contract_id`, `contract_hits`, `reject_*`, etc.), then rerun clean Field, menu, and first-battle under the same strict verify gate.

## 2026-05-29 07:14:01-04:00 Stateaware One-Step Visual Gate (Field + Missing-SPU Evidence)

## Run Stamp
- Timestamp: `2026-05-29T07:14:01-04:00` (local)
- Branch: `master`
- Refiner decision (from prior run): `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling; clean field triage only with one left pulse after accepted route; no verified movement-only boundary, Options/menu, battle, or 200% evidence.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 220 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 10
```

## Run Dir
- `debug-captures\windows-lab\20260529-071401-cpu4-stateaware-one-step-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-071401-cpu4-stateaware-one-step-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid screenshots after first field-like: `0`
- Host contention: prelaunch/postlaunch/runtime samples `clean`, postrun `clean`; no external emulator/process contention.

## Log Verification
- `parse_spu_contract_verify_log` result:
  - `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`
  - strict failures: `accepted_rows_lt_1`, `contract_hits_lt_1`
  - failure reason: `no contract verifier rows found` (SPU verifier instrumentation not enabled in this run)
  - no targeted fatal signatures in `RPCS3.log` / stdout / stderr.

## Counter Verification
- `summarize_eternal_sonata_spu_reservation_loop.ps1` result:
  - `Kernel capsule rows: 0`
  - `MFC wait exact-PC rows: 0`
  - `PUTLLC16 pair verifier rows: 0`
  - `Reservation command rows: 0`
  - `Reservation command exact-PC rows: 0`
  - `Command-run MFC wait exact-PC rows: 0`
  - `command-correlation-evidence`: missing
  - Decision: `collect-missing-proof`

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-contract-no-evidence`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Keep run in route/tooling mode and follow current instruction lane; do not claim speed, `gpu-migration-credit`, or 200%.
- Keep `spu-contract-pipeline` in verify-only gating until command-correlation / kernel-capsule / pair-verifier evidence exists alongside clean Field + Options + first-battle visual routes.

## 2026-05-29 07:02:07-04:00 Stateaware One-Step Verify + Contract Instrumentation (Field + SPU Rows)

## Run Stamp
- Timestamp: `2026-05-29T07:02:07-04:00` (local)
- Branch: `master`
- Refiner decision: `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling with contract-instrumented movement; no verified movement, Options/menu, battle, or 200% proof.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-verifypipe-cleanrun-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -EternalSonataKernelCapsule Profile -EternalSonataPutllc16Pair Verify -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "...wait 30 tokens..." -MaxSeconds 220 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 10
```

## Run Dir
- `debug-captures\windows-lab\20260529-070207-cpu4-stateaware-one-step-verifypipe-cleanrun-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir ...\20260529-070207-cpu4-stateaware-one-step-verifypipe-cleanrun-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like: `screenshot-0117s.png` at `117s` (`2.50 MB`)
- Invalid screenshots after first field-like: `0`
- Host contention: clean prelaunch/postlaunch/runtime samples, then `moderate` postrun (`codex` hot external process; no emulator contention).

## Log Verification
- `parse_spu_contract_verify_log` result:
  - `rows=837`, `accepted_rows=837`, `rejected_rows=0`, `total_contract_hits=1881`, `total_contract_bytes=30,818,304`
  - `strict_failures`: none
  - No VM/SPU/graphics/assertion fatal signatures; only `Show fatal error hints: false`.

## Counter Verification
- `summarize_eternal_sonata_spu_reservation_loop.ps1` result:
  - `Kernel capsule rows: 0`
  - `MFC wait exact-PC rows: 0`
  - `PUTLLC16 pair verifier rows: 0`
  - `Command-run rows: 0`
  - `Command-correlation evidence missing for narrow fast-path decisions`.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `spu-contract-verifier`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Keep contract counters in verify mode and collect kernel-capsule/pair/correlation profiles before changing any SPU fast-path mode.
- Do not claim speed, `gpu-migration-credit`, or 200% from this run.

## 2026-05-29 06:55:48-04:00 Stateaware One-Step Verification Pass (No Contract Rows)

## Run Stamp
- Timestamp: `2026-05-29T06:44:32-04:00` (local)
- Branch: `master`
- Refiner decision: `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling with clean field triage only; no movement, Options/menu, battle, or 200% claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-064432-cpu4-stateaware-one-step-movement-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField
.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-064432-cpu4-stateaware-one-step-movement-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate
.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-064432-cpu4-stateaware-one-step-movement-visualgate-windows-windows
```

## Run Dir
- `debug-captures\windows-lab\20260529-064432-cpu4-stateaware-one-step-movement-visualgate-windows-windows`

## Visual Verification
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`, `117s`)
- Invalid screenshots after first field-like: `0`
- Host contention: clean prelaunch/postlaunch/runtime samples, then `moderate` postrun (`host-system/postrun.json`: `external=moderate`, hot external process `codex#21200=15%`).

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath ...\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal/log scan: only `Show fatal error hints: false` in `RPCS3.log`; no VM access violation, SPU unknown STOP, VK device-loss, or assertion signatures in `RPCS3.log`, `rpcs3.stdout.txt`, or `rpcs3.stderr.txt`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir ...\20260529-064432-cpu4-stateaware-one-step-movement-visualgate-windows-windows`
- `Kernel capsule rows: 0`, `MFC wait exact-PC rows: 0`, `Command rows: 0`, `Reservation command exact-PC rows: 0`, `Command-run MFC wait exact-PC rows: 0`
- `PUTLLC16 pair verifier rows: 0`
- Decision: `collect-missing-proof` (missing kernel-capsule/pair-verifier and command-correlation evidence for fast-path decisions).

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Do not claim any speed, `gpu-migration-credit`, or 200% progress from this run.
- Keep the state-aware one-step Windows movement lane and collect kernel-capsule + reservation loop pair/correlation rows under verify instrumentation before any fast-mode work.

## 2026-05-29 06:24:39-04:00 Stateaware One-Step Reproof (Clean Field)

## Run Stamp
- Timestamp: `2026-05-29T06:24:39-04:00` (local)
- Branch: `master`
- Refiner decision: `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling with clean field triage only; no movement, Options/menu, battle, or 200% claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-062441-cpu4-stateaware-one-step-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-062441-cpu4-stateaware-one-step-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`, `117s`)
- Invalid screenshots after first field-like: `0`
- Host contention samples were clean across prelaunch, postlaunch, runtime sample, and postrun (`4` snapshots).

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-062441-cpu4-stateaware-one-step-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal/log scan: no VM access violation, SPU unknown STOP, VK device-loss, or assertion signatures in `RPCS3.log`, `rpcs3.stdout.txt`, or `rpcs3.stderr.txt`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-062441-cpu4-stateaware-one-step-visualgate-windows-windows`
- `Kernel capsule rows: 0`, `Command rows: 1108`, `exact-PC rows: 29931`, `MFC wait exact-PC rows: 55688`
- Decision: `collect-missing-proof` (`missing kernel-capsule, wait-exact-PC, and pair-verifier rows for fast-path decisions`).

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Do not claim any speed, `gpu-migration-credit`, or 200% progress from this cycle.
- Next required action remains route/tooling + verify-gap collection: re-run the boundary with kernel-capsule + wait-exact-PC + pair-verifier emission before any fast-mode work.

## 2026-05-29 06:04:44-04:00 Stateaware One-Step Reproof

## Run Stamp
- Timestamp: `2026-05-29T06:04:44-04:00` (local)
- Branch: `master`
- Refiner decision: `Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling with clean field triage only; no movement, Options/menu, battle, or 200% claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-060444-cpu4-stateaware-one-step-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-060444-cpu4-stateaware-one-step-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`, `117s`)
- Invalid screenshots after first field-like: `0`
- Host contention samples were clean before postrun, then `moderate` at postrun (`4` snapshots; external codex process).

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-060444-cpu4-stateaware-one-step-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal/log scan: no VM access violation, SPU unknown STOP, VK device-loss, or assertion signatures in `RPCS3.log`, `rpcs3.stdout.txt`, or `rpcs3.stderr.txt`.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-060444-cpu4-stateaware-one-step-visualgate-windows-windows`
- `Kernel capsule rows: 0`, `Command rows: 1114`, `exact-PC rows: 30141`, `MFC wait exact-PC rows: 56110`
- Decision: `collect-missing-proof` (`missing kernel-capsule / wait-exact-PC evidence for narrow fast-path decisions`).

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-moderate-postrun`

## Next Step
- Do not claim any speed, `gpu-migration-credit`, or 200% progress from this cycle.
- Next required action remains route/tooling + verify-gap collection: run one boundary pass that emits kernel-capsule + wait exact-PC evidence before any fast mode.

## 2026-05-29 05:49:12-04:00 Stateaware Repair + Pipeline Sync

## Run Stamp
- Timestamp: `2026-05-29T05:49:12-04:00` (local)
- Branch: `master`
- Refiner decision: `Use the newest valid-field run as the route base, then add one small state-aware movement step with CleanAfterField.`
- Route pressure state: route-tooling with clean field triage only; no verified movement, Options/menu, battle, or 200% route claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160
```

## Run Dir
- `debug-captures\windows-lab\20260529-054912-cpu4-stateaware-one-step-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-054912-cpu4-stateaware-one-step-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`, `117s`)
- Invalid screenshots after first field-like: `0`
- Host contention samples were clean across prelaunch, postlaunch, host-sample, and postrun.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-054912-cpu4-stateaware-one-step-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `strict_failures=accepted_rows_lt_1, contract_hits_lt_1`
- Targeted fatal/log scan: no VM access violation, SPU unknown STOP, VK device-loss, or assertion signatures in this run.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-054912-cpu4-stateaware-one-step-visualgate-windows-windows`
- Decision: `collect-missing-proof` (`command/read/pair correlation evidence absent`).
- Reservation-loop evidence remained missing (`rows=0` for kernel-capsule, command/exact-PC, and MFC wait exact-PC).

## SPU Contract Pipeline Sync
- `.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260529-053934-cpu4-loader-control-left200x3-visualgate-windows-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6`
- Pipeline refresh regenerated:
  - `spu-contracts\BLUS30161\latest-summary.md`
  - `spu-contracts\BLUS30161\verify-counter-plan.md`
  - `spu-contracts\BLUS30161\verify-counter-schema.md`
  - `spu-contracts\BLUS30161\verify-logrow-implementation.md`
  - `spu-contracts\BLUS30161\source-alignment.md`
  - `spu-contracts\BLUS30161\index.json`
  - both `BLUS30161-958dfe208b686622-...-CellSpursKernel...` JSON contracts
- Both contracts still report `inferred_classes=["no-log"]`, `verifier.mode="verify-only-required"`, required counters `output_mismatch=0`, `descriptor_overflow=0`, `fatal_log_hits=0`, and `fast_mode=blocked`.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `spu-contract-scaffold`
- `verify-counter-plan`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Do not claim any speed, `gpu-migration-credit`, or 200% progress from this cycle.
- Next required action: run verify-only counter collection for the `0x25cc/0x9e4000` contract lane in an instrumented Windows run that emits kernel-capsule command rows, then re-verify field + Options + first-battle in the same verify schema before any fast-mode work.

## 2026-05-29 05:39:34-04:00 Loader-Control Left200x3 Micro-Pulse Extension

## Run Stamp
- Timestamp: `2026-05-29T05:39:34-04:00` (local)
- Branch: `master`
- Refiner decision: `Do not repeat rejected diag200 route; extend clean left200x2 boundary by one extra micro pulse.`
- Route pressure state: field triage only; no movement route proof, Options/menu, battle, or speed/FPS claim.

## Windows-only Step

```powershell
.\tools\ps3_harness_refiner.ps1 -MaxRuns 8
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x3-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=1000;ls_left:200;wait=1000;shot:100;wait=10000;shot:100" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12
```

## Run Dir
- `debug-captures\windows-lab\20260529-053934-cpu4-loader-control-left200x3-visualgate-windows-windows`

## Visual Verification
- `.\tools\check_eternal_sonata_windows_visual_gate.ps1 -RunDir .\debug-captures\windows-lab\20260529-053934-cpu4-loader-control-left200x3-visualgate-windows-windows -RequireFieldLike -RequireNoInvalidAfterFirstField`
- Status: `FIELD_LIKE_PRESENT`
- First field-like screenshot: `screenshot-0117s.png` (`2.50 MB`, `117s`)
- Invalid-after-field screenshots: `0`
- Host contention samples: clean at `prelaunch`, `postlaunch`, `sample-0138s`, and `sample-0150s`.

## Log Verification
- `.\tools\parse_spu_contract_verify_log.ps1 -LogPath .\debug-captures\windows-lab\20260529-053934-cpu4-loader-control-left200x3-visualgate-windows-windows\RPCS3.log -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`
- `RPCS3.log` was not present in the run folder; parser executed against captured stdout lines only.
- Parse output: `rows=0`, `accepted_rows=0`, `rejected_rows=0`, `total_contract_hits=0`, `total_contract_bytes=0`, strict failures `accepted_rows_lt_1`, `contract_hits_lt_1`.
- Targeted fatal/log scan on `rpcs3.stdout.txt`/`rpcs3.stderr.txt`: no VM access violation, SPU STOP, `VK_ERROR_DEVICE_LOST`, or assertion entries.

## Counter Verification
- `.\tools\summarize_eternal_sonata_spu_reservation_loop.ps1 -CommandRunDir .\debug-captures\windows-lab\20260529-053934-cpu4-loader-control-left200x3-visualgate-windows-windows`
- Reservation-loop evidence was missing (`command rows=0`, `exact-PC rows=0`, `MFC wait exact-PC rows=0`).
- Decision: `collect-missing-proof` (missing command/correlation evidence).

## SPU Contract Artifacts
- No `tools\spu_contract_pipeline.ps1` rerun on this checkpoint.
- Contract set remains `2`.

## Classification
- `analysis`
- `valid-field-triage`
- `route-tooling`
- `failed-logrow-parser`
- `spu-reservation-loop-summary`
- `collect-missing-proof`
- `host-contention-clean`

## Next Step
- Run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8` next and execute the recommended non-duplicative Windows-only step.

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




