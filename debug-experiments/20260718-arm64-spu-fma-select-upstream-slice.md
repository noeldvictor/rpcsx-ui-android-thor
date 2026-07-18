# 2026-07-18 ARM64 SPU FMA Select Upstream Slice

Date: 2026-07-18
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified upstream performance candidate; device-unmeasured

## Result

- Adapted the newest official RPCS3 SPU LLVM performance change over the
  Android fork's existing `KnownFPClass` work.
- Approximate-xfloat FMA now computes the normal FMA independently, then
  selects that result or the addend. It no longer masks a multiplicand before
  the FMA and serializes the arithmetic behind the zero/denormal predicate.
- ARM64 native compilation, ARM64-only ThorTest packaging, and all focused
  optimization/safety contracts pass.
- No ADB query, install, launch, thermal poll, or device workload ran.
- This is not yet a Thor FPS, temperature, title, flicker, gameplay, or
  stability result.

## Official upstream basis

The fresh official RPCS3 fetch advanced `origin/master` to
`a7d90852dd02efcceb539968667201dbc9799cb0`. Its performance commit is:

- [`9b3a916af02fc23a5ccd44db8b0c668710a86cc9`](https://github.com/RPCS3/rpcs3/commit/9b3a916af02fc23a5ccd44db8b0c668710a86cc9)
- subject: `[SPU LLVM] Use select in FMA to shorten its dependency chain (#19052)`
- official commit time: 2026-07-18 08:18:10 UTC

Upstream explains that SPU approximate-xfloat FMA must return the addend when
either multiplicand is zero/denormal. The old lowering zeroed a multiplicand
before FMA, placing the FMA behind the compare and mask. The official lowering
computes normal FMA independently and selects normal FMA versus the addend.

The upstream AVX-512-only `vfixupimmps` branch is irrelevant to Thor. The
portable select lowering is adapted exactly to this older fork's three-operand
intrinsic and existing `KnownFPClass` values. Accurate and relaxed xfloat
paths, FMS, FNMS, and generic non-ARM64 behavior are unchanged.

## Eternal Sonata reach

Static inspection used the saved clean first-battle SPU windows at:

`debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows/spu-images`

The 171 disassembly files contain:

- 10 FMA rows across 4 files;
- 8 unique FMA instruction addresses;
- 21 FMS rows across 3 files; and
- 3 FNMS rows across 3 files.

Only the FMA rows are directly covered by this upstream slice. Static presence
is title relevance, not dynamic execution frequency or a speed measurement.

## AArch64 dependency check

NDK 29 clang/LLVM 20.0.0 compiled minimal old/new LLVM-IR shapes for
`aarch64-linux-android29` directly from stdin.

For the one-known-not-NaN branch, the old shape lowered to:

`fcmeq -> bic -> fmla`

The new shape scheduled normal FMA independently of the predicate:

`mov/fmla` in parallel with `fcmeq`, followed by `bsl`.

For the both-unknown branch, the old FMA depended on two compares and two
`bic` masks. The new normal FMA is independent and the final `bsl` consumes
the combined predicate. The generated instruction count is similar (and one
synthetic both-unknown case was one instruction longer), so the credible claim
is a shorter dependency chain and more instruction-level parallelism, not
fewer instructions.

## Research decision

- [Phase Matters](https://arxiv.org/abs/2606.27906) reports phase-dependent
  gains and lower sustained temperature/energy on a Snapdragon mobile SoC.
  This supports reducing work in specific emulator phases instead of applying
  another blanket CPU or governor rule; it is not a Thor temperature forecast.
- [A System-Level Dynamic Binary Translator using Automatically-Learned
  Translation Rules](https://arxiv.org/abs/2402.09688) reports DBT gains from
  coordination reduction and generated-code scheduling. The applicable lesson
  is to improve the hot generated dependency graph while preserving guest
  semantics.
- The direct primary source for this change is the official RPCS3 commit from
  the same day. That is stronger implementation evidence than extrapolating a
  general paper into an emulator-specific shortcut.

## Source and contract

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`
- `tools/test_thor_spu_fma_select_lowering.ps1`

The focused contract isolates the `spu_fma` intrinsic, requires all three
select forms, requires exactly three normal-FMA definitions, and rejects the
legacy mask-before-FMA fragments. The existing `KnownFPClass` contract remains
the semantic companion gate.

## Host verification

Passed without contacting Thor:

- focused SPU FMA select-lowering contract and PowerShell AST parse;
- SPU `KnownFPClass` contract;
- ARM64 widening-multiply contract;
- ARM64 decrementer-inline contract;
- LQX/STQX canonical-address contract;
- ARM64 SHUFB splat contract;
- bounded SPU cache contract;
- reduced-loop safety audit; Android emission remains retired;
- parsed PPU JIT object handoff and zero-copy buffer contracts;
- startup cache-phase pacing contract;
- RSX preload and Vulkan pipeline-cache contracts;
- ARM64 RelWithDebInfo native build;
- ARM64-only optimized ThorTest assembly and ABI contract;
- optimized ThorTest variant contract;
- core export surface: 34 defined dynamic symbols, 583 explicit relocations,
  391 jump slots, and 44,219 encoded relocation bytes;
- strengthened thermal guard contract: 56 C confirmed probe, 68 C early stop,
  and 72 C hard ceiling; and
- `git diff --check` before the ledger update.

## Exact host-only candidate

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,574,026` bytes
- APK SHA-256:
  `A38B8B6FC14DD6F41F1F1298CD199F4B4A5D25B8E2F4B5A1A56B99C7CE18AA0B`
- merged ARM64 core size: `1,305,640,336` bytes
- merged ARM64 core SHA-256:
  `45363D0FFF2D7DEDE1FD3651DF998EF330977CC3E66DDCB20829E72F204D267A`
- packaged stripped core size: `62,848,808` bytes
- packaged stripped core SHA-256:
  `7E1886A9BB25CDD215148559447B2C0D56CBBAFCDED094973D23731EE465A17B`

This exact APK also contains the validated parsed-object PPU JIT handoff. It
supersedes the earlier uninstalled host-only handoff APK
`39EE3277C6CE1657129B199A6BF9BF21ADB307CFF8ECAF80C84CB4123EDD0D81`.

## Device boundary

The candidate is uninstalled and `device-unmeasured`. The Thor remains stopped
on the earlier exact zero-copy APK
`E69D671D2B6F74BAC6DEAF2A3A08D7DC98877B0F8654E7C89AC2A0BA68B6C509`.

The preceding runtime reached `78.3 C` before title. Do not touch the device in
this work round. A later independently cool round may perform only a strict
no-launch install of this exact APK. Runtime proof belongs to another
independently cool round and must reach title/menu, field, and first battle
under the repaired thermal guard before any speed or stability promotion.
