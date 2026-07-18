# ARM64 SPU Widening-Multiply Upstream Slice

Date: 2026-07-17
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified upstream performance candidate; device-unmeasured

## Upstream trigger

The official RPCS3 checkout contains:

- commit: `7e436f9bf136ad00321a97c09fb371fbd4eafe6b`
- subject: `SPU LLVM: Optimize SPU multiplies for ARM`
- surveyed official tip: `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`

The Android fork lacked this slice. Official upstream adds AArch64 LLVM wrappers
for signed and unsigned widening multiplies and uses them for six SPU opcodes.
A history search from the introducing commit through the surveyed official tip
found no later modification or revert of either intrinsic helper.

## Adaptation

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.h`
- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`

The ARM64 translator now exposes LLVM's `aarch64_neon_smull` and
`aarch64_neon_umull` intrinsics. Under `ARCH_ARM64`, MPY, MPYS, MPYU, MPYI,
MPYUI, and MPYA select the low 16-bit lanes and emit a native widening
multiply. Every generic lowering remains under `#else`, so desktop and other
architectures retain the previous implementation.

Added `tools/test_thor_spu_arm64_multiply_lowering.ps1` to require both
intrinsics, all six native lowering sites, their architecture guards, and the
generic fallbacks.

## Title relevance

The clean first-battle SPU image capture at
`debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows/spu-images`
contains 171 disassembly files. Static inspection found 18 covered multiply
instructions across 10 files:

- MPYA: 10
- MPYU: 7
- MPYUI: 1

This proves the optimized instruction family exists in Eternal Sonata's saved
first-battle SPU code. It is not a dynamic execution count and does not prove
an FPS, power, or temperature improvement.

## Cache correctness

The normal `spu-...-v1-tane.dat` cache contains guest SPU program identities
and data, not persisted ARM machine code. With `SPU Debug=false`, the LLVM JIT
rebuilds the generated code in memory on launch/preload. Therefore this
code-generation-only change does not require an SPU guest-program cache version
bump; changing that version would only discard the useful preload list.

Rollback is the retained generic non-ARM64 branch or a local revert of this
upstream slice. No speculative title-specific switch was introduced.

## Host validation

Passed without contacting the Thor:

- `tools/test_thor_spu_arm64_multiply_lowering.ps1`
- `tools/test_thor_spu_known_fp_class.ps1`
- `tools/test_thor_spu_lqx_stqx_address_reuse.ps1`
- `tools/test_thor_spu_cache_preload.ps1`
- `tools/audit_spu_reduced_loop_alignment.ps1`; Android reduced-loop emission remains disabled
- ARM64 RelWithDebInfo compile/link of the changed translator and SPU LLVM recompiler
- optimized ThorTest APK contract
- ARM64-only APK/core hash contract
- native export surface: 34 defined dynamic symbols, 583 explicit relocations, 391 jump slots, 44,219 encoded relocation bytes
- PowerShell AST parsing and `git diff --check`

## Exact host-only candidate

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK SHA-256: `68A4993C5A67D08ED9C68C7BD013C4B4217AD74B9BFD34130EFD4F5D60A69235`
- APK size: `73,573,890` bytes
- merged ARM64 core SHA-256: `6164DC995CB38C38D08079643AE142CF29837A3874A325A2FBC5602EB3CB9B30`
- merged ARM64 core size: `1,305,590,360` bytes
- stripped ARM64 core SHA-256: `6ACC482FC83A3DADC128B72C68D0F826E58AC28EB4988F67C5D211F1866D7CAC`
- stripped ARM64 core size: `62,843,832` bytes

No ADB query, install, launch, or thermal poll ran in this host-only round. The
Thor remains stopped on installed APK `24F3F267...F87F`. Candidate
`68A4993C...9235` is uninstalled and has no device speed, temperature, flicker,
gameplay, or stability credit. A later install must first pass the strict
independently cool three-sample gate; runtime proof belongs to a different cool
round.
