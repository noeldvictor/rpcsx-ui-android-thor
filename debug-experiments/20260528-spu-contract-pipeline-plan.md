# SPU Contract Pipeline Plan

- Date: 2026-05-28
- Title: Eternal Sonata `BLUS30161`
- Classification: `analysis`, `spu-contract-scaffold`
- Not speed, not `gpu-migration-credit`, not a 200% gate result.

## Decision

The next smart SPU lane is not manual Ghidra lookup. It is a repeatable
contract compiler:

`runtime logs -> SPU window extractor -> Ghidra headless -> contract JSON -> emulator verifier -> fast path`

SPU work stays verify-only until field, Options/menu, and first-battle visuals
are clean with zero relevant mismatches, zero descriptor overflow, and zero
fatal log hits.

## First Artifact

`tools/spu_contract_pipeline.ps1`

Current seed command:

```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir .\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000 -NoGhidra -MaxWindows 6
```

Current outputs:

- `spu-contracts\BLUS30161\latest-summary.md`
- `spu-contracts\BLUS30161\index.json`
- `spu-contracts\BLUS30161\verify-counter-plan.md`
- `spu-contracts\BLUS30161\verify-counter-plan.json`
- `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0.json`
- `spu-contracts\BLUS30161\BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0.json`

## Contract Lanes

- `0x25cc/0x9e4000`: MFC descriptor and PUT-heavy DMA family. CPU/SPU
  HLE/codegen first; GPU compute remains parked.
- `0x451c`: TCX/SPURS list-copy and descriptor pressure. Contract and verify
  before fast mode.
- SPURS/wait HLE: reduce busy-loop and scheduler pressure while preserving
  GETLLAR/PUTLLC semantics.
- Optional patch lane: reversible, title-gated, offline-only, and separate
  from emulator speed claims.

## Acceptance Gate

Before any fast path:

- Exact runtime anchor: title, image signature, PC, group, SPU name.
- Cell contract: MFC order, tags, waits, DMA alignment/size, local-store range,
  and reservation behavior preserved.
- Verify-only emulator counters exist for the contract.
- Field, Options/menu, and first-battle visuals pass.
- `output_mismatch=0`, `descriptor_overflow=0`, and `fatal_log_hits=0`.

## Next Code Step

Wire one selected contract, likely `0x25cc/0x9e4000`, into a verify-only
emulator counter keyed by title, image signature, PC, group, command shape, and
GET/PUT direction. Do not enable bodyfast/codegen until that counter survives
the full visual gate.

## 2026-05-28 Verify-Counter Plan Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits a concrete verify-counter plan in
  both JSON and Markdown.
- Priority 1: `mfc-descriptor-family-25cc-9e4000`, contract
  `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- Priority 2: `tcx-spurs-descriptor-family-451c`, contract
  `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0`.
- The priority-1 lane records 11 predicates and 22 required counters, including
  hits, bytes, GET/PUT splits, rejects, duration, command fields, hashes,
  `output_mismatches`, `descriptor_overflow`, and `fatal_log_hits`.
- The generated source anchors exist in the local `rpcs3-upstream` checkout:
  `SPUThread.cpp` and `SPULLVMRecompiler.cpp`.

Classification:

- `analysis`.
- `verify-counter-plan`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement only the priority-1 verify-only counter lane first. Keep
  `bodyfast`, `codegen-fast`, and `vulkan-compute` blocked until field,
  Options/menu, and first-battle visuals pass with zero mismatches, zero
  descriptor overflow, and zero fatal log hits.

## 2026-05-28 Source-Alignment Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\source-alignment.json` and
  `spu-contracts\BLUS30161\source-alignment.md`.
- The alignment was generated from
  `20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`.
- Windows upstream has all checked priority-1 `0x25cc/0x9e4000` predicate
  patterns present in `SPUThread.cpp`: runtime family classifier, tag check,
  size check, EA family, and existing callsite.
- Windows upstream also has the `0x451c` dynamic-list predicate and LLVM verify
  callout anchors present.
- Vendored RPCSX has the generic Thor DMA probe hooks, but the checked
  `0x25cc`/`0x451c` contract predicates are absent there.

Classification:

- `analysis`.
- `source-alignment`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Add explicit contract-id labeled verify-only counters and reject buckets in
  the Windows upstream hooks for `mfc-descriptor-family-25cc-9e4000`.
- Do not port this to vendored RPCSX or enable `bodyfast`, `codegen-fast`, or
  `vulkan-compute` until field, Options/menu, and first-battle visual gates pass
  with zero mismatches, zero descriptor overflow, and zero fatal log hits.

## 2026-05-28 Verify-Counter Schema Output

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\verify-counter-schema.json` and
  `spu-contracts\BLUS30161\verify-counter-schema.md`.
- The schema is for priority-1 lane
  `mfc-descriptor-family-25cc-9e4000`, contract
  `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- Required verify-only environment:
  `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow` and
  `RPCS3_ES_SPU_HLE_25CC_BODY=disabled-or-verify-only`.
- Blocked fast values include `RPCS3_ES_SPU_HLE_VERIFY=skip/fast`,
  `RPCS3_ES_SPU_HLE_25CC_BODY=fast`, `RPCS3_ES_GPU_PROBE=fast`, and any
  Vulkan compute fast path.
- Predicate/reject buckets are now explicit for title, image signature, PC,
  group, SPU name, command, list bit, tag, size, EAH/EAL family, local-store
  range, MFC shuffling, accurate DMA, and fast mode.
- Existing upstream counters were mapped to the schema: family hits/bytes,
  GET/PUT split, EA family split, shadow hashes, output match/mismatch,
  descriptor overflow, and body PUT rejects.

Classification:

- `analysis`.
- `verify-counter-schema`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement only the parseable log-label/reject-bucket row for this contract in
  the Windows upstream hooks.
- Do not change copy/body behavior, port to vendored RPCSX, or enable fast mode.

## 2026-05-28 Verify Log-Row Scaffold

Update:

- `tools\spu_contract_pipeline.ps1` now emits
  `spu-contracts\BLUS30161\verify-logrow-implementation.json` and
  `spu-contracts\BLUS30161\verify-logrow-implementation.md`.
- The scaffold targets a single additional parseable Windows upstream notice row:
  `Eternal Sonata SPU contract verifier` with
  `hle_mode=contract-25cc-9e4000` and
  `contract_id=BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0`.
- It reuses existing upstream 25cc family, shadow, descriptor, and body verifier
  rows instead of adding behavior changes.
- Required keys include contract identity, image/PC/tag/size/EAL, hits, bytes,
  GET/PUT split, reject buckets, mismatch/overflow, hashes, cause, and status.
- The upstream RPCS3 checkout is currently dirty with unrelated work, so this
  round deliberately produced a repo-local scaffold and did not edit upstream
  C++ directly.

Classification:

- `analysis`.
- `verify-logrow-implementation-scaffold`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Isolate the dirty upstream checkout, then apply only the log-only row.
- Do not modify memcpy/body behavior, port to vendored RPCSX, or enable fast
  mode before clean field, Options/menu, and first-battle verifier captures.

## 2026-05-28 Verify Log-Row Parser

Update:

- Added `tools\parse_spu_contract_verify_log.ps1` for future
  `Eternal Sonata SPU contract verifier` rows.
- The parser loads `spu-contracts\BLUS30161\verify-logrow-implementation.json`,
  filters only matching verifier rows, and validates required keys,
  `hle_mode`, full contract id, GET/PUT hit split, `output_mismatch=0`, and
  `desc_overflow=0`.
- The generated scaffold example now includes all required fields and the full
  contract id.
- Validation result: the generated example parsed as `accepted_rows=1`,
  `rejected_rows=0`; a noise line parsed as `rows=0` with
  `no contract verifier rows found`.
- The parser always emits `promotion_ready=false`; field, Options/menu,
  first-battle visuals, host grade, and fatal-log checks remain external gates.

Classification:

- `analysis`.
- `verify-logrow-parser`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- When the upstream checkout is isolated, implement only the log-only verifier
  row and run this parser on the resulting RPCS3 log before any fast/body/codegen
  path is considered.

## 2026-05-28 Strict Verify Log-Row Gate

Update:

- `tools\parse_spu_contract_verify_log.ps1` now supports strict verifier gating
  flags: `-RequireAcceptedRow`, `-RequireNoRejected`, `-MinContractHits`, and
  `-FailOnGate`.
- `spu-contracts\BLUS30161\verify-logrow-implementation.json` and `.md` now
  include the strict parser command for future RPCS3 logs:
  `.\tools\parse_spu_contract_verify_log.ps1 -LogPath <RPCS3.log> -RequireAcceptedRow -RequireNoRejected -MinContractHits 1 -FailOnGate`.
- Validated parser behavior:
  generated zero-hit example parses in non-strict mode; a synthetic one-hit row
  passes strict mode; the zero-hit example and a noise-only input both exit `2`
  under strict `-MinContractHits 1 -FailOnGate`.
- The gate is still parser/counter consistency only. It is not speed, not GPU
  migration, not first-battle proof, and not a 200% candidate.

Classification:

- `analysis`.
- `verify-logrow-strict-gate`.
- Not speed.
- Not `gpu-migration-credit`.
- Not a 200% gate candidate.

Next:

- Implement the log-only upstream row only after isolating the dirty upstream
  checkout, then require this strict parser gate before any bodyfast/codegen or
  GPU fast-path promotion discussion.
