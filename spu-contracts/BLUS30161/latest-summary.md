# SPU Contract Pipeline Summary

- Generated: `2026-05-28T22:36:22.9448331-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows`
- Target PCs: `0x25cc, 0x451c`
- Target EAs: `0x9e4000`
- Ghidra headless: `missing-or-skipped`
- Contracts: `2`

| Contract | PC | Image | Classes | Hot log hits |
| --- | --- | --- | --- | ---: |
| `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` | `0x025cc` | `0x958dfe208b686622` | `dma-window,spurs-kernel` | 80 |
| `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` | `0x0451c` | `0x958dfe208b686622` | `dma-window,spurs-kernel` | 80 |

Classification: `analysis`, `spu-contract-scaffold`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.
Next: wire the selected contract into a verify-only emulator counter before any fast path.
Source alignment: `source-alignment.md`.
Verify counter schema: `verify-counter-schema.md`.
Verify log-row scaffold: `verify-logrow-implementation.md`.
