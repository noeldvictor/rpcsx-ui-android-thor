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
