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
