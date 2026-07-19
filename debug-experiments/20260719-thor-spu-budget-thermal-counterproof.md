# Thor SPU-budget Thermal Counterproof and RSX-load Successor

- Date: 2026-07-19
- Title: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max `c3ca0370`
- Runtime classification: `thermal-stop-before-title` / `not-comparable`
- Runtime capture:
  `debug-captures/android-speed-sprint/20260719-190316-thor-input-custom`
- Exact installed APK during runtime: `5C3911D0...682CC6`
- Host successor: built and verified, not installed

## One guarded runtime route

This was the only device route in its independently cool round. The exact
property-only `ThorCoolTitle` successor passed the three-sample preflight:

- silicon: `34.3 -> 33.5 -> 33.9 C`;
- battery: `23.0 C`;
- skin: `30.0 C`;
- launch maximum: `34.3 C` against the `35 C` ceiling; and
- launch rise: `-0.4 C` against the `1 C` maximum.

PID `30771` was established at `19:03:31.3033461-04:00` and launched exactly
once. The first readiness poll arrived at PID plus `1.150 s`, measured
`61.8 C`, and still showed the startup progress screen at `80.782%`: no title,
black-frame, or PPU-compilation classification.

The guarded thermal sequence was:

- `61.8 C` at PID plus `1.150 s`, confirmed at `47.0 C`;
- `59.0 C` at plus `3.720 s`, confirmed at `47.4 C`;
- `67.0 C` at plus `6.165 s`; and
- immediate confirmation at `71.1 C`, plus `7.186 s`.

The `68 C` early-stop row fired on that confirmation, RPCSX was force-stopped,
and the post-stop snapshot was `51.0 C`. The guest log has zero targeted
fatal hits. No second launch, temperature query, install, or other device
route ran in this round.

## What improved and what did not

The intended same-APK controls reached native code:

- cache-phase pacing was off, removing the prior incorrect `5,003 ms` wait;
- RSX selection remained `256/939`, with `683` deferred;
- RSX load and compile used two workers and exact `0x07` affinity;
- SPU selection remained `64/1,165`, with `1,101` deferred;
- the `100 ms` SPU compile budget activated; and
- SPU workers used exact `0x07` affinity.

The SPU budget built `5/64` programs in about `0.183 s`
(`3.775 -> 3.958` emulator-log seconds); `59` identities retained the unchanged
on-demand compile path. The prior route built all `64/64` in about `1.679 s`
(`8.871 -> 10.550`). The first `libsysmodule` load consequently advanced from
about `10.555` to `3.968` emulator-log seconds, approximately `6.59 s` earlier.

That is real bounded-startup-work and startup-progress evidence, but not an
end-to-end win. This run:

- began up to `2.4 C` hotter than the prior route's `31.9 C` maximum;
- reached the same `61.8 C` first readiness temperature;
- stopped at PID plus `7.186 s` instead of plus `13.242 s`; and
- still did not reach the title.

Removing the dead wait and long SPU burst concentrated the remaining early
work rather than proving lower heat. Grant no title, FPS, flicker, gameplay,
stability, temperature-win, or end-to-end speed credit.

The installed APK also still logged `Set DAZ and FTZ: false`, as expected: it
predates the separately host-fixed managed-profile debug gate. This route was
therefore a clean isolation of property-only scheduling changes, not a proof
of the future managed profile.

## Remaining measured burst

The dominant early interval is now RSX cache disk read, pipeline unpack, and
program decompilation:

- RSX load started at emulator-log `1.055 s`;
- RSX compile began at `2.948 s`; and
- the load interval was about `1.892 s`.

The first `61.8 C` readiness sample overlapped this phase. The subsequent RSX
pipeline compile interval was only about `0.449 s` before PPU warm-object work
began at `3.396 s`. The existing RSX compile budget therefore did not bound the
measured leading cache-load burst.

## Host successor

RSX cache loading now has an Android-only budget with these invariants:

- title-gated to `BLUS30161`;
- default `0`, preserving the existing unbounded one-atomic claim loop;
- Android property `debug.rpcsx.thor.rsx_cache_load_budget_ms`;
- environment fallback `RPCSX_THOR_RSX_CACHE_LOAD_BUDGET_MS`;
- fail-closed range `0..5000 ms`;
- deadline checked before opening and unpacking the next pipeline cache file;
- already-started entries finish; and
- unclaimed cache entries remain on disk and use the existing runtime
  load/compile path.

`ThorCoolTitle` requires a `500 ms` load budget. The route records requested,
effective, combined-property, README, activation, and deferred-count evidence,
and resets the property after prelaunch, failure, or success. Conflicting
explicit values fail before device resolution.

The analyzer now requires both the `500 ms` activation row and its deferred
load summary. It also fixes a classification bug exposed by this route:
ordinary successful `pre-run-N-of-M` rows no longer make a later launched
thermal stop look like a preflight refusal. Only a failed preflight row or an
explicit pre-run macro failure can select `preflight-refused-hot`.

## Exact uninstalled artifact

Optimized ARM64-only ThorTest APK:

- path:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`;
- size: `72,838,248` bytes; and
- SHA-256:
  `54CC0C3730ED07503210D46D9D0D7368E94B3DA26D9FDE023C1481BC09D82892`.

Merged debug-bearing core:

- size: `1,304,689,712` bytes; and
- SHA-256:
  `406166AC0E027651E5284E293DC3ED00AC0144412CAD2DC3351930DEC72F737E`.

Stripped packaged core and matching APK entry:

- size: `63,015,752` bytes; and
- SHA-256:
  `5F11CFD2D10C8B7825F6D99FFC5214F61D2F68F0702CFB7A1FF6D1294E07CC10`.

The candidate also packages the previously host-verified managed-profile
debug gate and native phase-wait bypass. Neither exists in the currently
installed `5C3911D0...682CC6` APK.

## Host verification

Passed without further device activity:

- focused startup-budget, cool-profile, analyzer, RSX preload, and diagnostic
  compaction contracts;
- replay of the hot refusal as `preflight-refused-hot` at `45.8 C`;
- replay of this launched run as `thermal-stop-before-title` at `71.1 C`;
- all `61/61` host PowerShell contracts;
- Android ARM64 RelWithDebInfo native build in `85 s`;
- optimized ARM64-only ThorTest assembly in `52 s`;
- ARM64 ABI, optimized variant, export surface, exact merged-core identity,
  and packaged stripped-core identity; and
- no remaining Gradle, Java, Ninja, Clang, CMake, or emulator build process.

## Next safe sequence

Do not install or launch again in this device round. After an independently
cool interval, use only the strict no-launch installer for the exact
`54CC0C37...D82892` APK and prove matching on-device hash plus absent PID.
Stop that round after installation. After another cooling interval, allow one
self-stopping `ThorCoolTitle` proof. It must confirm the `500 ms` RSX load
budget/deferred count and `Set DAZ and FTZ: true`, then compare title reach,
time-to-title or time-to-guard, thermal slope, visual state, and fatal
cleanliness before receiving any speed or temperature credit.

## Install-only gate refusal

At `19:26`, about 22 minutes after the preceding runtime stop, one strict
install-only gate was attempted for exact successor `54CC0C37...D82892`:

- capture:
  `debug-captures/android-speed-sprint/20260719-192621-thor-input-strict-cool-gate`;
- preflight sample 1 silicon: `48.2 C` against the `35 C` ceiling;
- battery: `23.0 C`;
- skin: `30.0 C`; and
- failure-post-stop silicon: `48.6 C`.

The gate force-stopped RPCSX before any install or activity launch. No retry,
temperature recheck, or other device query ran. The installed APK therefore
remains `5C3911D0...682CC6`; successor `54CC0C37...D82892` remains host-only
and uninstalled. This refusal carries no speed, thermal-win, FPS, flicker,
gameplay, or stability credit.

The saved refusal exposed a tooling gap: `ForceStop`-only/no-boot failures
stored both force-stop command records but did not save the post-stop PID
probe, and the strict wrapper's terminating error did not expose the already
created capture directory. Host-only tooling now:

- saves `failure-pid.txt` after force-stop for no-boot/no-snapshot failures;
- attaches the exact capture directory to the propagated exception; and
- reports `capture_dir=...` in strict-wrapper failure text.

This avoids a manual device follow-up query after future hot refusals. The
successful gate's one-path output, no-boot contract, force-stop behavior, and
`35 C`/three-sample/`1 C`-rise thresholds are unchanged. The strict-gate and
multi-sensor thermal contracts pass host-only. Do not attempt installation
again until a later independently cool round.
