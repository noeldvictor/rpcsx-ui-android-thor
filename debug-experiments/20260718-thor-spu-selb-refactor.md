# Thor SPU SELB Compiler Refactor

Date: 2026-07-18

Status: host-verified, uninstalled, device-unmeasured

Classification: current-upstream SPU compiler micro-candidate

## Goal

Reduce CPU work while LLVM compiles SPU programs used by Eternal Sonata on the
AYN Thor. This slice changes SPU expression matching and constant-mask
classification; it does not add threads, GPU work, logging, disk traffic, or a
title-specific semantic shortcut. The Thor was deliberately not contacted.

## Current-Upstream Finding

Fresh official RPCS3 origin/master at
a7d90852dd02efcceb539968667201dbc9799cb0 contains commit
700ca262f44fda57ba260283c3f0a4772db8a573,
[SPU LLVM] Refactor SELB.

The Android fork still had the older SELB lowering. Its comparison-derived
select path put the adjusted-division matcher behind six nested conditions, and
its constant-mask path independently scanned four u32 elements, eight u16
elements, and sixteen u8 elements.

Current upstream instead:

1. exits comparison matching immediately when the select pattern is absent;
2. gives the division-correction operands explicit names and checks their
   independent predicates before the direct IEEE division replacement;
3. classifies constant-mask byte granularity with one sixteen-byte pass;
4. dispatches typed float or byte selection from that classification.

The vendored rx::v128 storage member is named data rather than current
upstream's m_data. The adapted loop uses mask._u8.data; all algorithmic behavior
matches the upstream change.

## Eternal Sonata Coverage

The latest clean first-battle verifier-off log,
debug-captures/windows-lab/20260718-173347-allcore-padapi8-bodyfast-compact1hz-verifieroff-first-battle/RPCS3.log,
contains:

- 144 static SELB disassembly rows;
- 90 unique static SELB PCs.

This proves title-family coverage only. It does not measure dynamic execution,
constant-mask hits, division-correction hits, compile-time reduction, FPS, or
temperature.

## Change

SPULLVMRecompiler.cpp now carries the current-upstream SELB refactor. The
following semantic paths remain explicit:

- f64[2], f64[4], and f32[4] typed selections;
- exact adjusted-division recognition before direct division;
- FSMB/FSM/FSMH protection;
- unpredictable-mask xfloat preservation through conv_xfloat_mask();
- the final fully generic bitwise SELB fallback.

tools/test_thor_spu_selb_refactor.ps1 isolates only SELB and requires the flat
matcher, the complete division predicate, one byte-mask scan, float typing, FSM
protection, xfloat handling, and the generic fallback. It rejects all three
legacy mask loops, the old nested matcher, and the raw float-one constant.

Rollback is the single source/test/documentation commit. There is no property,
cache schema, persistent state, or title profile to migrate.

## Candidate Triage

- ARM64 CLZ already keeps LLVM ctlz; the recent saturation-subtract change is
  guarded to non-ARM64 targets and was rejected for Thor.
- The current ARM64 verifier already contains the multiply-accumulate lowering,
  so no duplicate transplant was made.
- SVE/SVE2 remains unavailable on Snapdragon 8 Gen 2.
- Reduced-loop execution remains disabled because prior proof found
  deterministic corruption.
- Broad Vulkan compute offload remains rejected for the covered title
  superpaths because the captures do not prove an RSX-local producer/consumer
  lane and synchronization/readback can cost more power than the SPU work.

## Host Verification

No ADB query, install, launch, temperature read, or other Thor action ran.

- Focused SELB source contract: pass.
- All 30 tools/test_thor_*.ps1 contracts: pass.
- The first ARM64 compile correctly exposed the vendored data/m_data API
  difference; the adapted source then compiled successfully.
- Optimized ARM64 native compile/link: BUILD SUCCESSFUL in 61 seconds.
- ARM64-only optimized ThorTest APK: BUILD SUCCESSFUL in 20 seconds.
- Exact APK/ABI/merged-core contract: pass.
- Packaged ARM64 core exactly matches the stripped ARM64 core.
- Export surface: 34 defined dynamic symbols, 587 explicit relocations,
  391 jump slots, and 44,253 encoded relocation bytes.
- git diff --check: pass before documentation finalization.

Exact host-only artifacts:

- APK:
  app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk
- APK size: 73,696,394 bytes
- APK SHA-256:
  CBBAD89994071CC1209ACE45B8A2B17FA65894968A2085FB081D12FE64BB52E5
- merged ARM64 core size: 1,306,295,904 bytes
- merged ARM64 core SHA-256:
  3CBB492C34C97A5CFD6630D02CCA615DA5CC8C8248B1B9A2693FA5FEEB4C769C
- stripped/packaged core size: 63,136,328 bytes
- stripped/packaged core SHA-256:
  C6E4652D01A62B2CD4AF87DBC5426323D324D5BB24C019D24E11228D123532AC

## Claim Boundary

This is a structurally covered and host-verified SPU compile-time candidate. It
may reduce startup or runtime-stutter CPU work when SPU modules are compiled,
but it does not claim faster generated SELB execution. No Thor FPS, frame-time,
temperature, flicker, field, menu, battle, or stability credit is allowed
without a later independently cool, matched device A/B proof.
