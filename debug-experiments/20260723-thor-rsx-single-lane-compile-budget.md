# Thor RSX Single-Lane Compile Budget

Date: 2026-07-23

## Outcome

The Android-only, `BLUS30161` startup pipeline-cache compile phase now uses one worker whenever its opt-in time budget is nonzero. `ThorCoolTitle` already supplies a `50 ms` budget. Cache loading remains on two workers, desktop behavior is unchanged, and Android/default paths with a zero compile budget retain the existing shared worker count.

This is a host-verified reduction in peak startup compile concurrency, not an on-device speed or temperature result.

## Evidence and Design

Saved title-startup captures show the RSX preload lane using two load and two compile workers. In the most recent surviving capture, `20260723-164343-thor-input-custom`, the `200 ms` load budget attempted 18 of 64 pipelines, while cached-pipeline compilation began unbounded and overlapped the recovered PPU warm link and SPU startup.

The later `50 ms` title-only compile budget bounds new submissions, but it cannot cancel a driver call already in flight. With two compile workers, two Vulkan driver submissions could therefore remain in flight beyond the deadline. The successor keeps two workers for loading and selects one compile worker only when the Android compile budget is active. This limits the bounded phase to at most one in-flight driver compile and reduces its peak CPU concurrency. Untouched pipelines remain available for ordinary on-demand compilation.

The tradeoff is deliberate: fewer cached pipelines may complete inside the startup budget, potentially moving stutter into later gameplay. Field, menu, and battle proof are still required before promotion.

## Upstream Audit

Official RPCS3 `master` was fetched over SSH at `7a90d09cfe3c31bf95c3cb63c6301c5c0824c531`. No newer RSX/Vulkan performance change applied to this startup path. The relevant July 21 KnownBits work (`d75543a5`, `85c59207`, and `2aeb08f9`) is already represented in the local lane; `8b05c8cc` affects the CPU translator rather than RSX pipeline startup.

## Fail-Closed Evidence

The runtime emits both:

- `Shader cache preload workers: load=2, compile=1`
- `Android shader cache compile worker cap enabled for BLUS30161: workers=1.`

The cool-title analyzer requires the explicit worker-cap activation marker. Source contracts preserve the default shared-worker path, the single budgeted worker, phase ordering, Android durable logging, and desktop Notice behavior. The exact packaged core gate requires the new marker in the stripped native binary.

## Host Verification

Passed without ADB or device contact:

- focused RSX preload, compile-budget, Android logging, phase-pacing, and analyzer contracts;
- ARM64 `RelWithDebInfo` native build;
- ARM64-only `assembleThortest` packaging;
- ARM64 ABI, optimized test-hook, export-surface, and pinned candidate artifact checks;
- all `69/69` `tools/test_thor_*.ps1` contracts.

Pinned host successor:

- package: `net.rpcsx.easy`
- APK: `47EA2152DF6DA1B6C5FA3087C05ADCB1124E6F0071D5FC98BCB79A25E1F2F90E`, `72,838,180` bytes
- merged core: `C560E41824F90985C823595772FB25938D8831D8E981D2F2C96F1B4A120E1F0A`, `1,304,308,288` bytes
- packaged core: `F2EB73E4FADE0B32BFBD50CBA58C48B7AA3B690AFC824BEF7018F74F4C306898`, `62,988,936` bytes
- APK core entry SHA-256: `F2EB73E4FADE0B32BFBD50CBA58C48B7AA3B690AFC824BEF7018F74F4C306898`

The exact installed Thor candidate remains the prior stopped APK `D6798739F7BC06E8CFDBEEFFD9AFA0369F361CA90A625E98BEA7C1E8908D549F`. The new successor was not installed or launched. No temperature polling, waiting, device measurement, speed, FPS, flicker, gameplay, stability, or thermal-runtime credit occurred in this round.

## Measurement Boundary

A future independent cool-device run may test this exact successor once the user explicitly resumes device work. It must prove the worker-cap marker, bounded compile summary, exact APK/core identity, title reach, full continuity floor, thermal safety, and cleanup. Until then, the only banked measured speed result remains the earlier PPU warm-link recovery (`371.267 ms` versus `1915.119 ms`, `5.158x` faster for that startup stage only).
