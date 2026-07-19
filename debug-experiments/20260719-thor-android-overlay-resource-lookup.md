# 2026-07-19 Thor Android Overlay Resource Lookup

## Result

- Classification: host-verified Android startup-I/O and logging reduction.
- Scope: RPCS3 native overlay UI resource discovery on Android.
- Android now checks only the supported config-directory override for each of
  the 15 standard overlay PNGs. It no longer tries three desktop/Linux paths
  or reads `/proc/self/exe` once per missing icon.
- Missing Android icons produce one aggregate warning instead of four error
  broadcasts per icon.
- Desktop resource search, ordinary `image_info` failure logging, config
  overrides, decoding, rendering, and overlay resource indices are unchanged.
- No APK, ADB, launch, temperature read, or other Thor action ran in this round.
  No device speed, temperature, FPS, flicker, gameplay, or stability credit is
  claimed.

## Captured Evidence

The guarded failure capture
`debug-captures/android-speed-sprint/20260719-163325-thor-input-custom/failure-RPCSX.log`
contains exactly 60 missing-image error rows for 15 unique standard UI icons.
For every icon, Android tried:

1. `/storage/emulated/0/Android/data/net.rpcsx.easy/files/config/Icons/ui/...`;
2. the relative `Icons/ui/...` path;
3. `/system/bin/../share/rpcs3/Icons/ui/...`; and
4. `/system/bin/Icons/ui/...`.

The first row was at `0.914953 s` and the last at `0.915291 s`. These probes
are not the dominant cause of the later thermal stop, but they are entirely
avoidable work on every Android launch. The app contains no bundled
`app/src/main/assets/Icons/ui` tree, and the captured `/system/bin` fallbacks
are desktop installation conventions rather than Android app resources.

The current official RPCS3 reference retains the same generic config,
DATADIR, relative, executable-share, and executable-local search. It has no
Android-specific resource path to cherry-pick.

## Implementation

`image_info` now accepts a default-true `log_failure` argument. All existing
callers retain the exact prior error behavior. Only the Android config probe in
`resource_config::load_files()` passes `false`, counts missing icons, and emits:

`Android overlay UI resources: <missing> of 15 unavailable in the config directory; skipped desktop fallback paths.`

The Android path therefore performs:

- 15 config-file opens instead of 60 total opens;
- zero desktop relative/share/executable-local opens instead of 45;
- zero `/proc/self/exe` reads instead of 15; and
- one aggregate warning instead of 60 error broadcasts when all resources are
  absent.

If a user supplies one or more resources in the config directory, each present
file is still decoded and used. The aggregate count reports only those that
remain absent. This patch does not synthesize icons or change how missing
textures render, so it does not claim an overlay visual fix.

## Verification

Passed host-only:

- focused Android overlay resource lookup contract;
- all `56/56` `tools/test_thor_*.ps1` contracts;
- `git diff --check`;
- incremental Android ARM64 RelWithDebInfo native build in `124.4 s`;
- ARM64 binary contains the aggregate warning exactly once;
- ARM64 binary omits the desktop `../share/rpcs3/Icons/ui` path;
- no Gradle, Java, CMake, Ninja, Clang, or emulator process remained afterward.

Debug-bearing ARM64 core:

- bytes: `1,304,683,120`;
- prior same-configuration core: `1,304,702,360`;
- delta: `-19,240` bytes;
- SHA-256:
  `3AF46260EDF4E2D74DF35C306094B980E7C900A37B281173F2BEA81158CECE7B`.

## Device Boundary

This change can ride the next already-planned exact APK packaging and
no-launch install gate. It does not justify an extra Thor launch or thermal
sample. Validate its one aggregate warning opportunistically during the next
independently cool, early-stop-protected title attempt.
