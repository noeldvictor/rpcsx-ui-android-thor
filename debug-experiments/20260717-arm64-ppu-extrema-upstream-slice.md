# 2026-07-17 ARM64 PPU extrema upstream slice

## Result

Current official RPCS3 ARM64 lowering for PPU `VMAXFP` and `VMINFP` is
adapted to the Android fork. On ARM64, each guest operation now emits one
direct LLVM `fmax` or `fmin` expression instead of two extrema operations,
two bitcasts, and an integer AND/OR. The non-ARM64 path is unchanged.

This is host-verified and packaged, but it has not been installed or run on
the AYN Thor. Grant no FPS, temperature, flicker, gameplay, or stability
credit.

## Official upstream basis

The source is official RPCS3 commit
[`e36b820974d0f1864da0813211fb4faf223b4645`](https://github.com/RPCS3/rpcs3/commit/e36b820974d0f1864da0813211fb4faf223b4645),
`PPU LLVM: Use arm fmax/fmin for vmaxfp/vminfp`, as retained at the current
official tip `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`.

ARM64 `fmax` and `fmin` have the required AltiVec NaN selection behavior.
The fork's existing `vec_handle_result(..., true)` argument remains, so
`VMAXFP` and `VMINFP` continue to receive explicit manual denormal
handling even when Eternal Sonata's title profile enables hardware FTZ.

The prior fork lowering remains intact for non-ARM64 targets:

- `VMAXFP`: `fmax(a, b) & fmax(b, a)` after bitcasting;
- `VMINFP`: `fmin(a, b) | fmin(b, a)` after bitcasting.

The selected ARM64 branch removes one extrema operation plus the bitcast and
boolean-combine sequence from every translated instance. This is a generated
work reduction, not a promise that Eternal Sonata dynamically executes enough
of these opcodes for a large FPS change.

## Research direction

The latest useful primary-source signal favors reducing work per phase rather
than forcing sustained clocks or broad affinity changes:

- [Phase Matters: Characterizing Heterogeneous Vision-Language Inference on a Mobile SoC](https://arxiv.org/abs/2606.27906)
  reports phase-dependent accelerator benefits on Snapdragon 8 Elite, with
  `10.47 C` lower steady-state temperature and `2.52x` lower energy in its
  mobile VLM workload. This supports phase-aware placement and work reduction;
  it is not a PS3-emulator temperature forecast.
- [A System-Level Dynamic Binary Translator using Automatically-Learned Translation Rules](https://arxiv.org/abs/2402.09688)
  reports `1.36x` average speedup over QEMU 6.1 on SPEC CINT2006 and
  `1.15x` on real applications by reducing coordination and improving
  translated-code scheduling.
- [Partial Cross-Compilation and Mixed Execution for Accelerating Dynamic Binary Translation](https://arxiv.org/abs/2512.00487)
  reports up to `13x` over existing DBT through selective native function
  offload. For RPCSX this supports narrowly proven title/HLE superpaths, not
  broad semantic shortcuts.

The practical Thor policy remains: eliminate redundant CPU/SPU/PPU/RSX work,
keep title-specific phases independently selectable, and prove temperature on
silicon under a hard thermal guard.

## Candidates deliberately excluded

- SVE/SVE2 optimizations are inapplicable. Saved Thor JIT feature logs report
  `-sve,-sve2`; do not assume those extensions.
- Official ARM64 FMA enablement is already active in the fork because Android
  uses the Cortex-A78 LLVM CPU string.
- Official replacement of ARM `yield` with `isb` was not included. It
  deliberately slows spin loops, while prior Eternal Sonata Thor evidence
  shows global busy-wait batching and added synchronization latency reduced
  FPS. A wait-loop change needs its own callsite-specific experiment.
- No CPU mask, clock, scheduler, Vulkan-driver, or Android performance-hint
  policy changed.

## Source changes

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUTranslator.cpp`
  adds the direct official ARM64 branches for `VMAXFP` and `VMINFP`.
- `tools/test_thor_ppu_ftz_nj.ps1` now requires both direct ARM64 extrema
  lowerings while retaining its four sensitive-operation manual-flush
  contract.

## Host validation

Passed:

- `tools/test_thor_ppu_ftz_nj.ps1`;
- `git diff --check`;
- `:app:buildCMakeRelWithDebInfo[arm64-v8a]` in `85.1 s`;
- universal `:app:assembleThortest`, compiling both ARM64 and x86_64 paths;
- ARM64-only `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true`
  in `16.3 s`;
- `tools/test_thor_arm64_apk.ps1`; and
- `tools/test_thor_optimized_apk_contract.ps1`.

The universal build was validation only and was superseded by the smaller
ARM64-only package before any installation.

## Exact host-only artifacts

- ARM64-only ThorTest APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`;
- APK size: `73,573,710` bytes;
- APK SHA-256:
  `582F07B5D2EC14B36CE7D95D48D3B7C7898C55E02B7315FBD709D6B19467B2A0`;
- merged ARM64 `librpcsx-android.so`: `1,305,594,576` bytes, SHA-256
  `DBFF56BAAA7414A74A3C54101274FEF8177BD5F3D5833FA282DE441C7844F1D5`;
- stripped ARM64 `librpcsx-android.so`: `62,845,000` bytes, SHA-256
  `A87545D7A95B920E869B99F894956D9DDEAD0DEE65520ABA95656714F6017AC5`.

## Device and thermal boundary

No ADB query, install, launch, temperature read, or gameplay route ran for
this slice. The Thor remains on the exact previously installed canonicalized
local-store candidate:

- APK SHA-256
  `8BF896E8E2F99547523E53F803111DFE6BA330DA3C00644AE7B4C0BA790C28C7`;
- install-only capture
  `debug-captures/android-speed-sprint/20260717-231200-thor-input-spu-ls-canonicalization-thortest-install-cool-gate`;
- PID absent before and after installation; no launch occurred.

Only a later independently cool round may consider installing
`582F07B5...67B2A0`, using three silicon samples below `35 C`, net rise no
greater than `1 C`, and PID absent. Runtime proof must remain a different
independently cool round with the existing `68 C` early stop and `72 C`
hard ceiling.
