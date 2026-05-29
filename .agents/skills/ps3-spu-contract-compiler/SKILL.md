---
name: ps3-spu-contract-compiler
description: Use for the PS3 Eternal Sonata SPU contract pipeline: turn runtime hot SPU evidence into Ghidra/headless static windows, contract JSON, verify-only emulator checks, and only then title-gated fast/HLE/codegen paths.
---

# PS3 SPU Contract Compiler

## Purpose

Use this repo-local skill when SPU work should move from manual debugging to a
repeatable contract pipeline:

`runtime logs -> SPU window extractor -> Ghidra headless -> contract JSON -> emulator verifier -> fast path`

This is the default lane for `0x25cc`, `0x451c`, MFC descriptor builders,
GETLLAR/PUTLLC reservation loops, and repeated SPURS/SPU kernels.

## Rules

- Start from measured runtime evidence, not a broad game import.
- Treat GhidraSPU as useful but work-in-progress; validate against RPCS3 SPU
  disassembly and runtime counters.
- Preserve Cell semantics: MFC command order, tags, waits, size/alignment,
  local-store ranges, and reservation behavior.
- Emit contracts before code changes. Fast mode stays disabled until field,
  Options/menu, and first-battle verifier runs are clean.
- Keep GPU compute parked unless contracts prove stable batching, low readback
  pressure, and repeated RSX-consumed data.

## Workflow

1. Run or reuse a Windows capture with SPU image dumps and hot counters.
2. Generate contracts:

```powershell
.\tools\spu_contract_pipeline.ps1 -RunDir <run-dir> -TitleId BLUS30161 -Pc 0x25cc,0x451c -Ea 0x9e4000
```

3. Inspect `spu-contracts\BLUS30161\*.json` for:
   - image hash, group, SPU name, PC, and source run;
   - inferred kernel class;
   - MFC/DMA/reservation evidence;
   - required verifier checks.
4. Inspect `spu-contracts\BLUS30161\verify-counter-plan.md` for the next
   verify-only source anchors, predicates, and counters.
5. Inspect `spu-contracts\BLUS30161\source-alignment.md` before code edits:
   confirm whether the target predicate already exists in Windows upstream and
   whether vendored RPCSX only has generic probes.
6. Inspect `spu-contracts\BLUS30161\verify-counter-schema.md` for the exact
   verify environment, blocked fast modes, predicate fields, reject buckets, and
   parser acceptance rules.
7. Inspect `spu-contracts\BLUS30161\verify-logrow-implementation.md` for the
   concrete log-only row, existing upstream rows to reuse, derived fields,
   implementation order, and acceptance checks.
8. Use Ghidra/headless output to tighten the contract, not to skip verification.
9. Add emulator verify-only counters for the contract. Promote only after clean
   field, Options/menu, and first-battle visuals and zero mismatches.

## First Lanes

- `0x25cc/0x9e4000`: MFC descriptor and PUT-heavy DMA family; CPU/SPU
  HLE/codegen first, not GPU. Windows upstream already has the family
  predicate; add contract-id counters/reject buckets before changing fast mode.
- `0x451c`: SPURS/kernel descriptor/list-copy pressure; contract before fast
  mode.
- Reservation loops: GETLLAR/PUTLLC wait/retry HLE; preserve linked state and
  branch outcomes.
- Optional patch lane: title-gated, reversible, offline-only patches remain
  separate from emulator speed claims.
