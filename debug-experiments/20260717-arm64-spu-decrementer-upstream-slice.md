# ARM64 SPU Decrementer Upstream Slice

Date: 2026-07-17
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified upstream performance candidate; device-unmeasured

## Upstream trigger

The official RPCS3 checkout contains:

- commit: `61a2604824b01382bf57651b85f87b811306c2de`
- subject: `SPU LLVM: Inline reading/writing the decrementer for ARM too`
- surveyed official tip: `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`

The Android fork still restricted its inline SPU decrementer timebase to x86
and used the x86-only `llvm.x86.rdtsc` intrinsic. On ARM64, every eligible
dynamic RdDec called `spu_read_decrementer`, while WrDec called
`get_timebased_time` to establish its timestamp. Official upstream replaces
the architecture-specific intrinsic with LLVM `readcyclecounter` and admits
ARM64 under the same existing safety guard.

A history search from the introducing commit through the surveyed official tip
found no later modification or revert of `readcyclecounter` in the SPU LLVM
recompiler. The current official tip retains both adapted sites.

## Adaptation

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`

Both decrementer timebase paths now compile for `ARCH_X64 || ARCH_ARM64` and
use `llvm::Intrinsic::readcyclecounter`. The fast path remains conditional on:

- a nonzero architectural counter frequency
- `SPU loop detection: false`
- `Clocks scale: 100`

The RdDec `spu_read_decrementer` fallback and WrDec `get_timebased_time`
fallback remain unchanged for unsupported architectures, unavailable counter
frequency, loop detection, or non-100 clock scaling. WrDec also retains its
event update before timestamp handling.

Added `tools/test_thor_spu_arm64_decrementer_inline.ps1` to require both ARM64
guards and cycle-counter intrinsics, retain the configuration guard and generic
fallbacks, reject the x86-only intrinsic, and require the ARM64 `CNTFRQ_EL0`
frequency source.

## Title relevance

The latest actual Thor runtime capture before this host-only round,
`debug-captures/android-speed-sprint/20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof/failure-RPCSX.log`,
contains 16 distinct notices for compiled functions that read `SPU_RdDec`.
Those functions appeared between emulated timestamps 2.509745 and 4.835406
seconds. The same log records `SPU loop detection: false` and `Clocks scale:
100`, so the new fast-path guard matches the observed managed configuration.

The clean saved first-battle SPU image capture at
`debug-captures/windows-lab/20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows/spu-images`
contains four static `SPU_RdDec` rows across four disassembly files.

The notices prove compiled-function coverage and the disassemblies prove static
first-battle presence. Neither measures how often the guest executes those
instructions, so neither is credited as a dynamic speed or power result.

## ARM64 lowering proof

A minimal LLVM IR function calling `llvm.readcyclecounter` was compiled with
Android NDK 29 clang 20.0.0 for `aarch64-linux-android29`. Its optimized
assembly was:

```asm
mrs x0, CNTVCT_EL0
ret
```

The repository also already initializes `utils::get_tsc_freq()` from
`CNTFRQ_EL0` on ARM64, matching the architectural counter selected by LLVM.
This proof used temporary host files that were removed after inspection.

## Host validation

Passed without contacting the Thor:

- `tools/test_thor_spu_arm64_decrementer_inline.ps1`
- ARM64 RelWithDebInfo compile/link of `SPULLVMRecompiler.cpp`
- prior ARM64 multiply, KnownFPClass, LQX/STQX, and SPU cache contracts
- reduced-loop audit safety gates; Android emission remains disabled
- optimized ThorTest APK contract
- ARM64-only APK/core hash contract
- native export surface: 34 defined dynamic symbols, 583 explicit relocations, 391 jump slots, 44,219 encoded relocation bytes
- PowerShell AST parsing and `git diff --check`

## Exact host-only candidate

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK SHA-256: `443EF1440CDE53DA8F0D5964591C07E7A27338757885FDFF66014569057828BD`
- APK size: `73,574,086` bytes
- merged ARM64 core SHA-256: `1D1232C380D9104A6BD0B8FA7525F4EADFC7AC911BB20E1176F18130DF8B85D8`
- merged ARM64 core size: `1,305,612,624` bytes
- stripped ARM64 core SHA-256: `C9B59C67E717AFDADB4FD0BC5D2B7389D9A279B93975E717537022149930F861`
- stripped ARM64 core size: `62,846,264` bytes

No ADB query, install, launch, or thermal poll ran in this host-only round. The
Thor remains stopped on installed APK `24F3F267...F87F`. Candidate
`443EF144...28BD` is uninstalled and has no device speed, temperature, flicker,
gameplay, or stability credit. A later install must first pass the strict
independently cool three-sample gate; runtime proof belongs to a different cool
round.
