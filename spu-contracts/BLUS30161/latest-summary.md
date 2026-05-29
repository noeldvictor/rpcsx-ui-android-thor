# SPU Contract Pipeline Summary

- Generated: `2026-05-29T01:41:50.8990048-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260529-013434-cpu4-hle-25cc-shadow-desc-field-loader-control-left200x2-diag200-freshcounterproof-windows`
- Target PCs: `0x25cc, 0x451c`
- Target EAs: `0x9e4000`
- Ghidra headless: `missing-or-skipped`
- Contracts: `2`

| Contract | PC | Image | Classes | Hot log hits |
| --- | --- | --- | --- | ---: |
| `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` | `0x025cc` | `0x958dfe208b686622` | `dma-window,spurs-kernel` | 80 |
| `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` | `0x0451c` | `0x958dfe208b686622` | `dynamic-mfc-shape,dma-window,spurs-kernel` | 80 |

Classification: `analysis`, `spu-contract-scaffold`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.
Next: wire the selected contract into a verify-only emulator counter before any fast path.
Source alignment: `source-alignment.md`.
Verify counter schema: `verify-counter-schema.md`.
Verify log-row scaffold: `verify-logrow-implementation.md`.
