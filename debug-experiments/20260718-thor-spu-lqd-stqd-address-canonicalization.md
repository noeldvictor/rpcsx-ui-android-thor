# Thor SPU LQD/STQD Address Canonicalization

Date: 2026-07-18

Status: host-verified, uninstalled, device-unmeasured

Classification: upstream ARM64 codegen micro-candidate

## Goal

Reduce steady-state SPU address-generation and alias-analysis overhead on the
AYN Thor without adding threads, logging, disk traffic, GPU readbacks, or a
title-specific semantic shortcut. The Thor was deliberately not contacted.

## Current-Upstream Finding

Fresh official RPCS3 origin/master at
a7d90852dd02efcceb539968667201dbc9799cb0 contains commit
9bf67f031288b3197ed07d2305da273a6ebe65bc,
SPU LLVM: Discourage memory mirrors use on LQD/STQD.

The Android fork already carried the retained aligned LQX/STQX portion, but its
LQD/STQD lowering still used only the generic address expression. The missing
upstream path recognizes:

1. the base register value as an addition of two vector expressions;
2. either commuted operand as a compile-time constant;
3. the constant's scalar address lane as 16-byte aligned.

For that proven case, an out-of-range constant is sign-extended through
make_negative_LS_offset() so LLVM sees one canonical local-store mirror. The
other operand keeps the normal 0x3fff0 alignment mask and the signed
instruction displacement is unchanged.

Every unrecognized or non-aligned expression retains the original generic
extract(a, 3) masked fallback. The earlier officially reverted non-aligned
LQX/STQX remainder rewrite was not restored.

## Eternal Sonata Coverage

The latest clean first-battle verifier-off log,
debug-captures/windows-lab/20260718-173347-allcore-padapi8-bodyfast-compact1hz-verifieroff-first-battle/RPCS3.log,
contains:

- 470 static lqd disassembly rows;
- 300 static stqd disassembly rows.

This proves title-family coverage only. It does not prove how many rows satisfy
the constant-expression predicate or how often they execute.

## Change

SPULLVMRecompiler.cpp now adapts the current upstream aligned-constant
specialization for both STQD and LQD. It reuses the existing negative-LS-offset
helper and keeps the generic fallback immediately below the specialized path.

The older LQX/STQX contract was scoped to only its own source region so the two
address families cannot accidentally satisfy each other's checks. New
tools/test_thor_spu_lqd_stqd_address_canonicalization.ps1 requires:

- both commuted add-expression matches;
- both current-position constant probes;
- two canonical negative-mirror addends;
- two alignment guards;
- two specialized canonical addresses;
- both generic masked fallbacks;
- absence of the obsolete position-offset probes and masked positive constant.

Rollback is the single source/test commit. There is no property, cache schema,
or persistent state to migrate.

## Research Triage

Recent JIT/DBT research supports keeping future experiments narrow:

- The learned-rule system DBT prototype reports an average 1.36x over QEMU 6.1
  on SPEC CINT2006 and 1.15x on real applications, but it changes the
  translation architecture and coordination model rather than offering a
  drop-in SPU lowering: https://arxiv.org/abs/2402.09688
- The 2SOM multi-tier JIT reports 15% better warm-up with 5% lower peak
  performance. Moving SPU work into a weaker gameplay tier is therefore not an
  automatic thermal win for this emulator: https://arxiv.org/abs/2504.17460
- Druid's generated baseline frontend reaches 2x its interpreter but only 0.7x
  the long-maintained handwritten JIT. That does not justify replacing RPCS3's
  mature handwritten SPU LLVM compiler: https://arxiv.org/abs/2502.20543
- The race-to-idle GPU result is a dense matrix-multiplication study. It cannot
  be generalized to SPU local-store loads/stores, and the saved Eternal Sonata
  field/battle contracts still show that GPU migration would add synchronization
  and readback cost: https://arxiv.org/abs/2507.20063

The practical decision is to keep transplanting measured, architecture-native
upstream lowerings and to park learned translation, a new multi-tier compiler,
and Vulkan compute offload until a matched profile proves a suitable hot lane.

## Host Verification

No ADB query, install, launch, temperature read, or other Thor action ran.

- Focused LQD/STQD contract: pass.
- Independently scoped LQX/STQX contract: pass.
- All 29 tools/test_thor_*.ps1 contracts: pass.
- Optimized ARM64 native compile/link: BUILD SUCCESSFUL in 66 seconds.
- ARM64-only optimized ThorTest APK: BUILD SUCCESSFUL in 12 seconds.
- Exact APK/ABI/merged-core contract: pass.
- Packaged ARM64 core exactly matches the stripped ARM64 core.
- Export surface: 34 defined dynamic symbols, 587 explicit relocations,
  391 jump slots, and 44,253 encoded relocation bytes.
- git diff --check: pass before documentation finalization.

Exact host-only artifacts:

- APK:
  app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk
- APK size: 73,696,482 bytes
- APK SHA-256:
  80EE210BE0388198918995B854DA4FEC88F1C185F904C48A20E1859176F3E144
- merged ARM64 core size: 1,306,301,680 bytes
- merged ARM64 core SHA-256:
  5E81CF4B2C3C52214A1E6D1B6EFE3B98D9B0E471373B7FF91777762CA77F7620
- stripped/packaged core size: 63,138,296 bytes
- stripped/packaged core SHA-256:
  01A9B4A11DE8C1B8A9140D90674AEC1A052E7F6C0CC9C6CBF9E66FD924DD5CFF

## Claim Boundary

This is a structurally covered and host-verified micro-candidate. It is not a
measured speed or temperature win. The benefit depends on runtime SPU programs
matching the aligned constant-base predicate, and no Thor FPS, frame-time,
temperature, flicker, field, menu, battle, or stability credit is allowed
without a later independently cool device proof.
