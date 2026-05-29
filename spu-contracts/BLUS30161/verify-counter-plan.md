# SPU Verify Counter Plan

- Generated: `2026-05-29T15:51:55.5970986-04:00`
- Title: `BLUS30161`
- Source run: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android\debug-captures\windows-lab\20260529-095956-cpu4-loader-control-visualgate-windows-v15-windows`
- Classification: `analysis`, `verify-counter-plan`, not speed, not `gpu-migration-credit`, not a 200% gate candidate.

| Priority | Lane | Contract | PC | Fast modes |
| ---: | --- | --- | --- | --- |
| 1 | `mfc-descriptor-family-25cc-9e4000` | `BLUS30161-958dfe208b686622-pc025cc-CellSpursKernel0` | `0x025cc` | `bodyfast, codegen-fast, vulkan-compute` |
| 2 | `tcx-spurs-descriptor-family-451c` | `BLUS30161-958dfe208b686622-pc0451c-TCX_CellSpursKernel0` | `0x0451c` | `bodyfast, codegen-fast, vulkan-compute` |

Priority-1 implementation target: add verify-only counters for the `0x25cc/0x9e4000` MFC descriptor family. Keep bodyfast, codegen-fast, and Vulkan compute blocked until field, Options/menu, and first-battle visuals all pass with zero mismatches, zero descriptor overflow, and zero fatal log hits.

Source anchors to inspect first:
- `runtime family classifier`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:656`
- `0x9e4000 family predicate`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:683`
- `shadow sample counters`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:1989`
- `runtime body-copy hook`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:2161`
- `MFC command entry`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp:6774`
- `LLVM verifier candidate`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:4401`
- `dynamic MFC fallback signal`: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp:5707`
