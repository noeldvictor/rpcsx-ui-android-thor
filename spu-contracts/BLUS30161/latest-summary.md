# SPU Contract Pipeline Summary

- Generated: `2026-07-24T17:23:13.5881581-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260724-171442-cpu4-loadlist-stable-path-gate-field-resloop-verify-windows`
- Target PCs: `0x25cc, 0x451c`
- Target EAs: `0x9e4000`
- Ghidra headless: `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat`
- Contracts: `2`

| Contract | PC | Image | Classes | Hot log hits |
| --- | --- | --- | --- | ---: |
| `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` | `0x025cc` | `0x958dfe208b686622` | `dynamic-mfc-shape,dma-window,spurs-kernel` | 80 |
| `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` | `0x0451c` | `0x958dfe208b686622` | `dynamic-mfc-shape,dma-window,spurs-kernel` | 80 |

Classification: `analysis`, `spu-contract-scaffold`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.
Next: wire the selected contract into a verify-only emulator counter before any fast path.
Source alignment: `source-alignment.md`.
Verify counter schema: `verify-counter-schema.md`.
Verify log-row scaffold: `verify-logrow-implementation.md`.
