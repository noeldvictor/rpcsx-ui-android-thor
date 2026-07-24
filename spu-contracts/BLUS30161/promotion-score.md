# SPU Contract Promotion Score

- Generated: `2026-07-24T17:23:13.5881581-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260724-171442-cpu4-loadlist-stable-path-gate-field-resloop-verify-windows`
- Classification: `analysis`, `contract-promotion-score`, `not-speed`, not `gpu-migration-credit`.
- Score scale: `0..10; higher means better next implementation target, not measured speed`

| Contract | PC | Classes | Hits | CPU/HLE | Host SIMD | Vulkan/GPU | Readback | RSX dest | Recommendation |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` | `0x025cc` | `dynamic-mfc-shape,dma-window,spurs-kernel` | 80 | 10 | 9 | 4 | `high` | `none-observed` | `verify-only-cpu-hle-or-codegen` |
| `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` | `0x0451c` | `dynamic-mfc-shape,dma-window,spurs-kernel` | 80 | 9 | 7 | 4 | `high` | `none-observed` | `verify-only-cpu-hle-or-codegen` |

## Conclusions
- Prioritize CPU/SPU HLE or codegen when reservation/SPURS semantics and zero RSX-local evidence dominate.
- Prioritize host SIMD when the contract is a stable bulk DMA/window body with bounded buffers.
- Keep Vulkan compute parked unless the contract has bulk work, low readback risk, and RSX destination evidence.

Next action: implement or run verify-only counters for the highest CPU/HLE ranked contract before any bodyfast, codegen-fast, or Vulkan compute mode.
