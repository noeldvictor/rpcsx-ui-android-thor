# 2026-07-19 Thor Combined Host Candidate APK

## Result

- Classification: exact host-built, host-verified, uninstalled candidate.
- Target: AYN Thor Max, Eternal Sonata `BLUS30161`.
- Source head: `e00d78964` (`perf: skip desktop overlay probes on Android`).
- Included preceding optimization: `6920348b8` (`perf: compact Thor RSX preload diagnostics`).
- Base normal-build gate: `07f7738b0` (`perf: compile out idle Android ADPF hint`).
- No ADB query, install, launch, PID check, screenshot, or temperature read ran.
  The previously installed `7CDD38E4...E5F9` APK is unchanged and RPCSX stays
  stopped.

## Exact APK

Path:

`app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`

- bytes: `72,840,580`;
- SHA-256:
  `504C614B27008D83CCE3DAF232ED194BC15139E38388DC0112728005F6E35588`;
- ABI: ARM64-only for RPCSX native libraries;
- `lib/arm64-v8a/librpcsx-android.so`: `60.1 MiB` stripped entry;
- `lib/arm64-v8a/librpcsx-ui-jni.so`: `0.34 MiB` stripped entry;
- no RPCSX core or JNI entry for another ABI.

Merged debug-bearing ARM64 core:

- bytes: `1,304,683,120`;
- SHA-256:
  `3AF46260EDF4E2D74DF35C306094B980E7C900A37B281173F2BEA81158CECE7B`.

Stripped ARM64 core:

- bytes: `63,014,472`;
- SHA-256:
  `ABB14ECC051BD18B7154EF365A26621A0F71ACAD1776755D299B1D7A538E8D5B`.

The APK core entry was hashed directly from its ZIP stream and matches the
stripped build output exactly.

## Included Startup Reductions

1. BLUS30161 Android Vulkan shader-load workers retain one representative
   fragment-decompiler diagnostic per kind and worker, then aggregate
   duplicates. Saved-capture replay predicts `399/412` duplicate writes
   removed (`96.8%`) without changing shader or runtime behavior.
2. Android native overlay lookup checks the supported config directory only,
   avoiding 45 desktop-path opens, 15 `/proc/self/exe` reads, and 59 of 60
   missing-icon log broadcasts when all 15 icons are absent.
3. Normal Android keeps the unproven ADPF RSX hint compiled out of the draw
   and present hot paths.

These are host-evidence and code-path claims. They are not device speed,
temperature, title, FPS, flicker, gameplay, or stability results.

## Verification

Passed:

- `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a -PbuildBundledRpcsxCore=true`
  in `100.9 s`;
- ARM64 APK contract with exact merged-core identity;
- optimized ThorTest variant contract;
- direct APK-entry/stripped-core SHA-256 equality;
- all `56/56` `tools/test_thor_*.ps1` contracts;
- Gradle daemon stopped afterward;
- no build or emulator process left active.

## Device Boundary

Do not install merely because the host artifact exists. In a later genuinely
cool round, run the strict three-sample no-boot gate, install this exact APK,
verify the on-device `base.apk` hash, prove PID absent, reset all experiment
controls, and stop. Do not launch in the install round.

Only after independent cooling may one guarded title proof use affinity mask
`0x07`, RSX/SPU preload limits `256/64`, cache-phase pacing, and Vulkan
cache-hit-only under the existing `68 C` early stop and `72 C` hard stop.
