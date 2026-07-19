# Thor Debug Managed-profile Gate

- Date: 2026-07-19
- Title: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max `c3ca0370`
- Device result: `preflight-refused-hot` / `not-comparable`
- Capture: `debug-captures/android-speed-sprint/20260719-184713-thor-input-custom`
- Source result: host-verified route correctness and future CPU-pressure enablement

## One guarded device attempt

The only device attempt in this round stopped at preflight sample 1:

- silicon: `44.9 C` against the `35 C` launch ceiling;
- battery: `23.0 C` against the `34 C` ceiling;
- skin: `30.0 C` against the `40 C` ceiling;
- failure-post-stop silicon snapshot: `45.8 C`; and
- `failure-pid.txt`: no RPCSX PID (`exit=1`).

No activity was launched, no guest code ran, and no retry or later device query
ran. The capture analyzer now distinguishes this state as
`preflight-refused-hot`, with `ready_for_comparison=false`,
`speed_credit=false`, and `process_absent_at_failure=true`. It is not a runtime
thermal failure and grants no title, FPS, temperature, flicker, gameplay, or
stability credit.

## Configuration-path counterproof

The earlier launched capture
`20260719-183040-thor-input-custom/failure-RPCSX.log` recorded:

- `Set DAZ and FTZ: false`; and
- `PPU LLVM Java Mode Handling: true`.

This contradicts the intended managed BLUS30161 profile in
`GameSettingsDatabase.kt`, which has enabled `Set DAZ and FTZ: true` since the
host-proven official `e9f833a2` adaptation. That matched Windows first-battle
A/B retained the 120 FPS cap and reduced sampled RPCS3 CPU by about 21.4%.

Source tracing found that ordinary UI launch calls
`GameSettingsDatabase.applyRecommendedConfig`, but the debug route did not.
`THOR_DEBUG_BOOT` directly opened `RPCSXActivity`, and on a cold start its
title lookup could also race asynchronous `GameRepository.load()`. Therefore
the benchmark route could silently boot with a stale/default per-title config,
including hardware FTZ disabled, despite the source profile being correct.

## Host fix

The future packaged debug route now:

1. passes explicit, validated title ID `BLUS30161` in the debug-boot intent;
2. applies the managed profile directly by canonical title ID before creating
   `RPCSXActivity`, without depending on asynchronous game-list discovery;
3. requires the resulting managed profile to report `enabled=true` and `applied=true`; and
4. fails closed before native boot when the title is missing, recommendations
   are disabled, the profile is stale/unavailable, or an existing user custom
   config is preserved instead of overwritten.

Normal UI behavior and custom-config preservation are unchanged. The default
debug-boot action remains unavailable in production builds. The title ID and
managed-profile requirement are also written into route input/evidence.

The cool-title analyzer separately recognizes a hot preflight refusal only
when the capture has a `pre-run-N-of-M` refusal and saved PID evidence proves
the package was absent. A launched thermal stop remains
`thermal-stop-before-title`.

## Current upstream audit

A fresh official RPCS3 fetch left `origin/master` at `357b7d446`. The current
Android core already contains the applicable recent ARM64/SPU efficiency and
safety work: I8MM, dot-product/UABA checks, TBL byte rotates, USHL masked
shifts, SHUFB splat paths, FMA select lowering, reduced-loop NaN/state guards,
and the Android thread-identity/race fix. The newer remaining changes are
desktop-specific, refactors, warnings, input, or VFS work; no additional
high-confidence Thor hot-path slice was selected.

## Verification

Host-only verification passed:

- all `59/59` Thor PowerShell contracts;
- focused PPU FTZ, display-pacing, cool-title-profile, and capture-analyzer
  contracts;
- replay of the actual refusal as `preflight-refused-hot`, maximum captured
  silicon `45.8 C`, and no speed credit; and
- `:app:compileThortestKotlin` in `33.8 s`.

No native build or APK was needed for this Kotlin/tooling correction. The
exact installed APK remains `5C3911D0...682CC6`; it does not contain this
future fail-closed debug route. It does support the property-only 100 ms SPU
budget successor and remains the correct isolation candidate for one later
independently cool same-APK proof.

## Decision and next sequence

Do not retry until a new independently cool round. First, run exactly one
same-APK 100 ms SPU-budget proof to isolate its startup/thermal effect against
the previous false-FTZ baseline. Only after that measurement should a new APK
package the managed-profile debug gate plus the native phase-wait bypass. Its
install must be no-launch in one cool round, followed by a separate guarded
runtime proof that explicitly confirms `Set DAZ and FTZ: true` before any
device CPU, temperature, or speed claim.
