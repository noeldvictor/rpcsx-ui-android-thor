# 2026-07-17 ARM64 SPU two-splat SHUFB upstream slice

## Result

Official RPCS3's retained ARM64 `SHUFB` specialization for two constant-splat
sources is adapted to the Android fork. When both source vectors are known
splats, a permutation-only control now emits `select_by_bit4`; controls that
may request SPU encoded constants use one 16-byte lookup table and `TBL`.
This bypasses the generic two-source shuffle construction.

The change is host-verified and packaged, but uninstalled and device-unmeasured.
Grant no FPS, temperature, flicker, gameplay, or stability credit.

## Official upstream basis

The source is official RPCS3 commit
[`a7fc31f3212c55bf0b70b45875c52dfc94f6641a`](https://github.com/RPCS3/rpcs3/commit/a7fc31f3212c55bf0b70b45875c52dfc94f6641a),
`[SPU LLVM] Additional SHUFB splat/special-index fast paths (#18945)`, as
retained at surveyed official tip
`0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`.

The Android fork already contained the commit's ARM64 single-source fast path,
including constant-splat handling. It intentionally did not contain the broad
two-source `TBL2/TBX2` path because the older fork lacks upstream's complete
register-scavenger retry mechanism. This slice adds only the independent
two-constant-splat branch and keeps `TBL2/TBX2` parked.

Constant splats are their own byte-reversed representation, so the adapted
branch can use the fork's existing `a` and `b` values directly while preserving
upstream's source selection and encoded-constant table semantics. The branch
is inside `ARCH_ARM64`; generic and desktop lowering are unchanged.

## Eternal Sonata reach

Static scanning of the saved BLUS30161 first-battle SPU disassemblies under
`debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows/spu-images`
found:

- `SHUFB`: 269 rows across 106 disassembly files;
- `SELB`: 49 rows across 31 files;
- `FSM/FSMB/FSMBI`: 6/6/95 rows;
- `FRSQEST`: 0 rows; and
- `CLZ`: 0 rows.

This establishes that `SHUFB` is the strongest statically represented family
among the newly reviewed upstream candidates. It does not prove how many rows
reach the two-splat JIT branch or how often they execute dynamically.

## Research direction

Recent primary-source work reinforces work reduction and phase-specific policy
instead of sustained maximum clocks:

- [Phase Matters: Characterizing Heterogeneous Vision-Language Inference on a Mobile SoC](https://arxiv.org/abs/2606.27906)
  reports a 10.47 C lower steady temperature and 2.52x lower energy for its
  phase-aware Snapdragon 8 Elite workload. This is directional evidence, not
  an emulator temperature forecast.
- [Dissecting the Impact of Mobile DVFS Governors on LLM Inference Performance and Energy Efficiency](https://arxiv.org/abs/2507.02135)
  reports that independently acting CPU/GPU/memory governors can leave large
  energy-efficiency gaps, while coordinated phase-aware policy improved
  latency at matched energy. RPCSX should first reduce each phase's work and
  collect comparable evidence before changing global governor policy.
- [A System-Level Dynamic Binary Translator using Automatically-Learned Translation Rules](https://arxiv.org/abs/2402.09688)
  reports 1.36x average SPEC CINT2006 and 1.15x real-application gains over
  QEMU 6.1 through translation quality, coordination reduction, and code
  scheduling.
- [Partial Cross-Compilation and Mixed Execution for Accelerating Dynamic Binary Translation](https://arxiv.org/abs/2512.00487)
  reports up to 13x over existing DBT through selective native offload. For
  RPCSX this supports narrow proven HLE/native superpaths, not broad semantic
  shortcuts.

## Source changes

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp` adds the
  official two-constant-splat ARM64 `SHUFB` lowering without enabling
  `TBL2/TBX2`.
- `tools/test_thor_spu_shufb_splat_lowering.ps1` requires the guarded
  `SELECT/TBL` paths and fails if the parked two-table helpers appear.

## Host validation

Passed without contacting the Thor:

- focused SHUFB source contract and PowerShell AST parse;
- ARM64 multiply, KnownFPClass, local-store canonicalization, and SPU cache
  contracts;
- reduced-loop audit; Android emission remains disabled;
- `git diff --check`;
- ARM64 RelWithDebInfo native build in 83.1 seconds;
- ARM64-only ThorTest APK assembly in 82.2 seconds;
- exact ThorTest ARM64 APK/core hash contract;
- optimized ThorTest variant contract; and
- core export surface: 34 defined dynamic symbols, 583 explicit relocations,
  391 jump slots, and 44,219 encoded relocation bytes.

## Exact host-only artifacts

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`;
- APK size: 73,574,258 bytes;
- APK SHA-256:
  `89F374D9CAA273B44DCDCD0876CD34DECCB3ECDC2A7DDC5BA49C3A7D5EB54FE9`;
- merged ARM64 core size: 1,305,598,912 bytes;
- merged ARM64 core SHA-256:
  `46336F379E4B874ABB7609C100EFE9E744CDEA295A2B5D911F75BC65674A4402`;
- stripped ARM64 core size: 62,845,624 bytes; and
- stripped ARM64 core SHA-256:
  `16D8E877C091CF324B97DA1686E95D88D0B5A4026E4087CC2810E8D8D4513066`.

## Device and thermal boundary

No ADB query, install, launch, temperature read, or gameplay route ran for this
slice. The Thor remains stopped on exact installed APK
`8BF896E8E2F99547523E53F803111DFE6BA330DA3C00644AE7B4C0BA790C28C7`.
Only a later independently cool round may consider installing the new APK,
using three silicon samples below 35 C, no more than 1 C net rise, and PID
absence. Runtime proof must be a separate cool round with the established
68 C early stop, immediate confirmation above 60 C, two-second polling, and
72 C hard ceiling.
