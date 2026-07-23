# Thor RSX Compile-Budget Successor

Date: 2026-07-23

## Scope

Prepare one reversible, title-only successor to the exact installed AYN Thor candidate without rebuilding, installing, launching, polling, or otherwise contacting the device.

The exact installed candidate remains:

- APK: `490418F9A43B287C376CB9D121C5C3BC93E1AFDEA51ED618BA6AB5882D95BF63`
- merged core: `9049E58356F013413230F339BBDCEADC09DD5B44A1835CA5A229824185AB749E`
- packaged core: `C0007C413932FC65C3CD01CDE70507987D335B0156A2A014508356A57CDED102`

## Evidence Behind The Successor

The single permitted capture `20260723-164343-thor-input-custom` proved that removing warm PPU link affinity recovered the 41-object link from `1915.119 ms` to `371.267 ms`. It also stopped at the first readiness poll at `67.0 C`, loaded only `6/7` required SPU native objects, and never reached title.

The surviving startup log orders the remaining concurrent work as follows:

- `0.772813 s`: RSX preload limited to `64/939` pipelines.
- `0.901832 s`: two RSX load and two RSX compile workers selected.
- `0.901853 s`: the existing `200 ms` RSX load budget activated.
- `1.123963 s`: load attempted `18/64`; `46` pipelines were deferred.
- `1.124182 s`: RSX compilation began with its budget still `0` (unbounded).
- `1.397486 s`: the recovered 41-object PPU warm link began.
- `1.768753 s`: the next one-object warm module began, giving the `371.267 ms` interval.
- `1.778347 s`: SPU preload selected `17/1165` programs.
- `1.778393 s`: the existing `50 ms` SPU compile budget activated.

RSX loading is therefore bounded, while cached-pipeline compilation remains the optional unbounded startup burst overlapping the recovered PPU link and SPU startup.

## Change

`ThorCoolTitle` now sets `debug.rpcsx.thor.rsx_cache_compile_budget_ms=50`. The core already implements this property and requires no APK rebuild. A zero value preserves the original unbounded loop; a nonzero value stops submitting new cached pipelines at the deadline, allows already in-flight submissions to finish, and leaves untouched pipelines for normal on-demand compilation.

The change intentionally preserves:

- two RSX load/compile workers;
- the recovered default-scheduler PPU warm-link path;
- the `200 ms` RSX load budget;
- the `50 ms` SPU compile budget;
- global defaults and `ThorCoolGameplay` at `0` (unbounded);
- post-stop cleanup at `0`.

Using `50 ms` isolates submission time with less startup heat exposure than the older untested `250 ms` proposal. It may move work into later runtime pipeline compilation and cause stutter, so it is not eligible for promotion without gameplay proof.

## Fail-Closed Contracts

The title analyzer now requires all of the following before a capture can be comparison-ready:

- effective and startup property evidence equal to `50`;
- `Android shader cache compile budget enabled for BLUS30161: 50 ms`;
- the attempted/deferred compile summary proving on-demand fallback;
- compile-worker affinity `requested=0x7, effective=0x7`;
- cleanup evidence reset to `0`.

The route profile rejects an explicit title override back to `0`. A dedicated synthetic negative fixture removes the activation and deferred-fallback messages and must classify the capture as `activation-incomplete`.

## Host Verification

Passed without device contact:

- PowerShell parse checks for all four modified scripts;
- `tools/test_thor_cool_title_profile.ps1`;
- `tools/test_thor_cool_title_capture_analyzer.ps1`;
- `tools/test_thor_startup_compile_budget.ps1`;
- `tools/test_thor_cool_title_candidate_artifact.ps1`;
- `git diff --check`;
- all `69/69` `tools/test_thor_*.ps1` host contracts.

No native source or packaged artifact changed, so no native/APK rebuild or install is required.

## Measurement Boundary

This is a host-validated successor configuration only. It has no new title, FPS, gameplay, flicker, stability, speed, or thermal credit.

A future independently cool, single self-stopping title route must prove the 50 ms activation and deferred summary, preserve the approximately `371 ms` warm-link recovery, load the full required SPU native-object floor, reach and hold title, remain within thermal limits, and reset properties safely. Promotion still requires separate field, menu, and battle correctness evidence. Do not retry in the same hot round.

## Guarded Device Attempt

The one permitted `ThorCoolTitle` route produced capture `20260723-171427-thor-input-custom`. The strict preflight sampled `34.5 C` and then `35.5 C`; because launch requires every silicon sample to remain below `35 C`, it refused at sample two before debug boot, game launch, or application of the `50 ms` RSX compile property.

RPCSX was force-stopped, the failure PID proof was absent, failure cleanup reset all startup properties, and failure post-stop silicon was `34.9 C`. Host-only analysis classifies the capture as `preflight-refused-hot`, `ready_for_comparison=False`, `speed_credit=False`, with `0/7` SPU native objects and no title evidence. The `50 ms` successor therefore remains device-unmeasured. No retry occurred in this thermal round; the host-only cooldown record moved the next independent gate to `2026-07-23T17:44:38.4571921-04:00`.

## Refusal Analysis Hardening

`AndroidRouteScene` now catches a failed `ThorCoolTitle` macro, resolves the exact capture directory carried in the exception (with a profile-specific timestamp fallback), runs the host-only analyzer without `RequireReady`, saves `cool-title-analysis.json`, and then propagates the original failure. Successful title proofs still require comparison-ready analysis. The pinned-artifact contract now also requires the title-gated RSX compile-budget activation, attempted/deferred summary, and property-name markers from the exact installed core.

PowerShell parsing, the focused profile and exact-artifact contracts, `git diff --check`, and all `69/69` `tools/test_thor_*.ps1` host contracts pass. This PowerShell/test/documentation follow-up made no APK/core change and performed no additional device contact.
