# SPU LQX/STQX Address-Reuse Upstream Revert

Date: 2026-07-17
Title: Eternal Sonata, BLUS30161
Target: AYN Thor / Android ARM64
Classification: host-verified upstream correctness alignment; device-unmeasured

## Upstream trigger

Fresh official RPCS3 fetch advanced `origin/master` to:

- commit: `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`
- subject: `SPU: Revert 49abd6d8e56256a7d49fdc3fbd8c17efa6faf419`
- reverted subject: `SPU LLVM: Allow the reuse of address from LQX/STQX`

The Android fork still contained the code removed by this official revert. For
constant operands that were not 16-byte aligned, it rewrote the effective
address by subtracting the constant remainder and adding it to the variable
operand before masking. Official upstream now keeps only the aligned constant
specialization and sends all non-aligned cases through the generic masked
address calculation.

## Adaptation

Changed:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp`

The two non-aligned STQX/LQX specializations were removed. These paths remain:

1. A constant-address reuse path only when `remainder == 0`.
2. The generic `(a + b) & 0x3fff0` fallback for every other case.

Added `tools/test_thor_spu_lqx_stqx_address_reuse.ps1` to require both aligned
specializations and both generic fallbacks while forbidding the reverted
non-aligned fragments.

This change is not credited as a speed optimization. It follows the newest
official safety decision and reduces the risk of an incorrect specialized
address on the older Android fork.

## Harness repair

`tools/ps3_harness_refiner.ps1` previously required the newest run in the
eight-run window to be the clean current-upstream Options proof. Newer FTZ and
upstream-analysis battle runs therefore hid the already-cleared all-core gate
and produced an obsolete CPU4 recommendation.

The selector now scans the recent window for any qualifying clean-upstream
Options proof and requires an exact matching build-token first-battle proof.
After the repair, `-MaxRuns 8 -NoWrite` reports that all-core 240/240 field,
first-battle, and Options evidence is complete and blocks CPU4 reruns.

## Host validation

Official Windows checkout:

- official tip: `0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861`
- local merge: `a18afa4037b25af1b285cdf109e1d6250b478234`
- Release executable SHA-256: `3FF4D86CD05017C73308D34086E625F10611A4D372BFBB315D453C60A9515A4D`
- executable size: `64,781,312` bytes

Correctness route:

- capture: `debug-captures/windows-lab/20260717-221500-upstream0fcb15a-ftz-on-warm-allcore-uncap240-first-battle-windows`
- all host cores, frame limit 240, VBlank 240
- hardware FTZ on
- Accurate SPU Reservations on; Accurate SPU DMA off
- WCB forced on
- exact 34-token state-gated title/load/field/first-battle route
- title passed at 48 seconds
- correct Path-to-Tenuto field at 57/59 seconds
- first-battle prompt at 72 seconds; live battle at 80 seconds
- route survived through the 150-second bound
- external host-contention grade clean
- targeted fatal/access-violation/device-lost/segfault/assertion/unhandled scan: zero

Twelve periodic battle samples averaged `120.016 FPS` with minimum `119.74`
and maximum `120.25`. Host samples at 91/120/150 seconds averaged RPCS3 CPU
`41.37%`, total CPU `46.7%`, and GPU `27.6%`. This run is a correctness
counterproof, not a controlled performance comparison with the earlier FTZ A/B.

Android host gates passed:

- ARM64 RelWithDebInfo native compile/link
- SPU LQX/STQX address-reuse contract
- SPU LLVM KnownFPClass contract
- bounded SPU cache/miss-path/diagnostics contract
- reduced-loop audit safety gates; Android emission remains disabled
- optimized ThorTest build contract
- ARM64-only APK contract
- native export surface: 34 defined symbols, 583 explicit relocations, 391 jump slots, 44,219 encoded relocation bytes
- `git diff --check`

## Exact host-only candidate

- APK: `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK SHA-256: `0ADC1B077814D04AEA2F6D19B7CB26296C408CEFEE13275575E30DA9EB9D794C`
- APK size: `73,573,094` bytes
- merged ARM64 core SHA-256: `3E960AF2271D003C90EA621A52F87DB57E88FBA673CAFC2F19DBB2422AC302A9`
- stripped ARM64 core SHA-256: `A49427FF03E0848152E341BC8CFD5241A25130B38E66B01F0738BF8CCBA7AA6E`

No ADB query, install, launch, or thermal poll ran in this host-only round. The
Thor remains stopped on installed APK `24F3F267...F87F`. Candidate
`0ADC1B07...D794C` has no device speed, temperature, flicker, gameplay, or
stability credit. Any later install must first pass the strict independently
cool three-sample gate; runtime proof belongs to a different cool round.
