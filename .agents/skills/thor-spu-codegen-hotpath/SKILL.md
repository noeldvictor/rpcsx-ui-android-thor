---
name: thor-spu-codegen-hotpath
description: Investigate and optimize Eternal Sonata BLUS30161 SPU, PPU, MFC/DMA, LLVM, reduced-loop, scheduler, and Ghidra hot paths in this RPCSX Android repo. Use for SPU reduced-loop emission, hot SPU image hashes, DMA/list-copy probes, title-gated CPU/GPU superpaths, and correctness-verified codegen experiments.
---

# Thor SPU Codegen Hotpath

## Scope

Use this repo-only skill for Cell-side speed work. Keep scene routing in `thor-scene-route`, Vulkan barrier work in `thor-rsx-vulkan-audit`, and result bookkeeping in `thor-experiment-ledger`.

## Workflow

1. Start from a known scene and cache state.
2. Choose one gate or probe, not a mixed pile:
   - `.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -EternalSonataKernelCapsule Profile -WindowsInputBackend PadApi -WindowsGameScreen 1`
   - `.\tools\set_thor_logging.ps1 -Mode ReducedLoop`
   - `.\tools\set_thor_logging.ps1 -Mode ReducedLoopEmit`
   - `.\tools\set_thor_logging.ps1 -Mode DmaProfile`
   - `.\tools\set_thor_logging.ps1 -Mode DmaVerify`
   - `.\tools\set_thor_logging.ps1 -Mode SpursProbe`
3. Prefer verify/profile mode before fast mode.
4. Keep experimental compiler/cache paths separate so normal SPU cache is not poisoned.
5. Build/push native core through `tools/build_push_thor_core.ps1`.

## Current Targets

Read `references/candidates.md` before changing SPU, PPU, MFC, or Ghidra-probed code.

Hot files include:

- `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp`
- `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp`
- `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\lv2\sys_spu.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp`
- `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_spu.cpp`
- `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp`

## Acceptance

A hotpath patch must be title-gated or debug-property-gated until proven, must preserve normal cache behavior, and must pass field, first battle, and menu visual checks before it becomes a claimed speed win. Under the current GPU 200% gate, keep shared-core hotpath experiments in the Windows lab until `ps3-speed-proof-gate` says the proof is comparable and promotable.
