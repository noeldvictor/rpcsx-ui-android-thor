# 2026-07-19 Thor SPU-cap Host Candidate APK

## Result

- Classification: exact host-built, host-verified, uninstalled candidate.
- Artifact:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`.
- APK size: `72,840,516` bytes.
- APK SHA-256:
  `5C3911D0E8C5B9EC20261266647B93685984EFB7C799D0E6F32334CEFD682CC6`.
- The APK is ARM64-only and uses the optimized `thortest` variant.
- No ADB resolution, device query, install, launch, screenshot, or temperature
  read occurred. The last-known installed APK remains `7CDD38E4...E5F9`.

## Exact Native Identity

Merged debug-bearing core:

- path:
  `app/build/intermediates/merged_native_libs/thortest/mergeThortestNativeLibs/out/lib/arm64-v8a/librpcsx-android.so`;
- size: `1,304,685,608` bytes;
- SHA-256:
  `EC3B31C52921A670AE31DE49D4170A43D9BECE420B109E96FA25B48BCDC5728E`.

Stripped packaged core:

- path:
  `app/build/intermediates/stripped_native_libs/thortest/stripThortestDebugSymbols/out/lib/arm64-v8a/librpcsx-android.so`;
- size: `63,014,824` bytes;
- SHA-256:
  `75A1163382A0F5548C2A476ECD5C915F48209FB3CD7983E9B91E6B6F2C786DC9`.

The APK entry `lib/arm64-v8a/librpcsx-android.so` is also `63,014,824` bytes
with SHA-256 `75A11633...86DC9`; it matches the stripped host artifact exactly.
No non-ARM64 RPCSX native entry is present.

## Delta From Prior Candidate

Prior host candidate `504C614B...5588`:

- APK: `72,840,580` bytes;
- merged core: `1,304,683,120` bytes;
- stripped core: `63,014,472` bytes.

Refreshed delta:

- APK: `-64` bytes;
- merged core: `+2,488` bytes;
- stripped core: `+352` bytes.

The native growth is consistent with the new requested/effective SPU pool cap
and one activation log row. ZIP compression makes the final APK slightly
smaller. These are build-identity observations only; they do not provide speed
or thermal credit.

## Included Stack

The exact candidate includes the prior combined host work plus:

- compacted duplicate-heavy Android RSX preload diagnostics;
- Android-only overlay resource-path pruning;
- the fail-closed self-stopping cool-title proof and analyzer;
- exact 26-property startup evidence; and
- BLUS30161 `0x07` SPU preload pool matching (`8 -> 3` workers expected).

## Verification

Passed host-only:

- `:app:assembleThortest -PrpcsxAndroidAbis=arm64-v8a
  -PbuildBundledRpcsxCore=true` in 98.1 seconds;
- exact merged-core SHA check;
- ARM64-only APK entry contract;
- optimized ThorTest hook/variant contract;
- single-open core loader contract;
- stripped export surface: 34 defined dynamic symbols, 587 explicit
  relocations, 390 jump slots, and 44,134 encoded relocation bytes;
- APK packaged-core length and SHA identity;
- all `58/58` `tools/test_thor_*.ps1` contracts; and
- no build, Gradle, native compiler, or emulator process left active.

## Device Boundary

This candidate has no device speed, FPS, temperature, flicker, gameplay, or
runtime-stability credit. In one future independently cool round, run only the
strict no-launch installer against the exact APK/hash and confirm RPCSX PID is
absent. Do not launch in the installation round. A guarded title proof may use
the self-stopping `ThorCoolTitle` profile only after a separate cooling interval.
