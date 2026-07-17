# Thor ARMv8.2-A native tuning

Date: 2026-07-17

## Scope and thermal policy

- Target: AYN Thor Max, Snapdragon 8 Gen 2, Android ARM64.
- Workload: RPCSX/RPCS3 host code used by Eternal Sonata `BLUS30161`.
- Classification: `build-proven`, `device-unmeasured`.
- This round was host-only. No ADB query, install, launch, gameplay route, or
  temperature query was performed after the preceding route observed an
  `87.1 C` silicon sensor.

## Evidence for the change

The existing ARM64 RelWithDebInfo compile database used `-O2`, `-DNDEBUG`, and
ThinLTO on the core, but no `-march`, `-mcpu`, or `-mtune` flag. The Android
toolchain therefore targeted generic ARMv8-A even though every Thor CPU is at
least ARMv8.2-A.

The connected proof device has this captured topology:

- 3 Cortex-A510 efficiency cores;
- 2 Cortex-A715 performance cores;
- 2 Cortex-A710 performance cores;
- 1 Cortex-X3 prime core.

A compiler probe of an acquire-release atomic add demonstrated the practical
gap:

- generic ARMv8-A emitted a call to `__aarch64_ldadd8_acq_rel`;
- `-march=armv8.2-a` emitted one inline `ldaddal` instruction.

This matters to synchronization-heavy PPU, SPU, RSX, and scheduler code. It is
not an FPS measurement by itself.

## Implementation

ARM64 native builds now default to:

```text
-march=armv8.2-a -mtune=cortex-a715
```

Gradle passes the values through `rpcsxAndroidArmArch` and
`rpcsxAndroidArmTune`; the equivalent environment variables are
`RPCSX_ANDROID_ARM_ARCH` and `RPCSX_ANDROID_ARM_TUNE`. Empty values disable a
flag for diagnostic builds. CMake checks compiler support and fails at
configuration time for an unsupported value.

The flags are guarded by an AArch64 processor check, so x86_64 builds are
unchanged. `-mtune` retains the generic target CPU and ARMv8.2-A feature set; it
changes instruction scheduling only. Runtime LLVM/JIT feature detection and
the existing dot-product/I8MM gates are unchanged.

## Host validation

Command:

```powershell
.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon --console=plain --offline
```

Result:

- `BUILD SUCCESSFUL` after a full native rebuild in `785.7 s`.
- The generated compile database contains both flags on all `1,385 / 1,385`
  AArch64 compile commands.
- Confirmed hot files include `PPUTranslator.cpp`, `SPUAnalyser.cpp`,
  `SPUThread.cpp`, `RSXThread.cpp`, `VKGSRender.cpp`, `Thread.cpp`, and
  `rpcsx-android.cpp`.
- The rebuilt non-LTO `Thread.cpp.o` contains `67` native LSE atomic
  instructions and zero outline-atomic helper relocations. The prior generic
  object contained zero native LSE instructions and `67` helper relocations.
- `git diff --check`: passed.

Artifact:

- Path:
  `app/build/intermediates/cxx/RelWithDebInfo/2t5h1l52/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,347,347,440` bytes, `3,685,704` bytes smaller than the prior core.
- SHA-256:
  `744CB3F2BE77F0DFCA255FE27EA5D7AF6E200E6BFC22D912F67CCCE6563CE839`

The official RPCS3 changes after the previously audited upstream point were
AVX-512 PPU LLVM NaN/denormal optimizations, so they do not apply to Thor's
AArch64 host. No upstream patch was forced into this round.

## Promotion gate

This change receives no Thor FPS, flicker, menu, battle, or stability credit
until a cooled device can run one no-repeat, thermally guarded matched scene.
The first proof should compare the known generic core with this exact candidate
under the same saved field route, then stop. A silicon temperature above the
configured limit must prevent launch and force-stop an already-running guest.

## First guarded device attempt

The exact candidate was pushed without rebuilding or launching:

- push evidence:
  `debug-captures/20260717-031834-armv82-aot-744cb3f2-dev-core-push`;
- active SHA-256:
  `744CB3F2BE77F0DFCA255FE27EA5D7AF6E200E6BFC22D912F67CCCE6563CE839`;
- package remained stopped after deployment.

A stopped-device cool-soak at
`debug-captures/android-speed-sprint/20260717-031655-thor-input-custom`
recorded battery `25.0 C`, skin `30.0 C`, and hottest silicon
`33.1/33.3/34.7 C`, so one guarded field attempt was allowed. A second ADB
target initially exposed an unpinned-wrapper bug before launch; the actual
attempt was then explicitly pinned to Thor serial `c3ca0370`.

The route
`debug-captures/android-speed-sprint/20260717-032039-thor-input-eternal-sonata-field-route`
started at silicon `34.1/33.9/33.9 C`. The legacy field profile entered a blind
`wait:90000`; the first five-second runtime poll found hottest silicon at
`77.1 C`, above the tightened `75 C` ceiling. The guard force-stopped RPCSX
before any route input, screenshot, or FPS sample. The post-stop snapshot one
second later was `51.8 C`.

Classification: `failed-thermal-guard` / `not-comparable`. This provides no FPS,
flicker, field, menu, battle, or stability credit for the ARMv8.2 candidate.
There was no second launch in this thermal round.

Host-side follow-up removes the `90/100 s` blind waits from the field,
field-direct, and menu profiles, reuses the stable title/Load/field visual
gates, pins the selected Android serial across nested ADB helpers, and changes
route runtime polling from a hard-coded five seconds to a two-second default.
The next separately cooled round may run one state-gated field attempt; it must
still abort rather than exceed the configured silicon ceiling.

## Warm-cache startup follow-up

The thermal abort happened during startup, so the next round stayed host-only:
no ADB query, deployment, launch, or device temperature read was performed.
Captured cache summaries from the failed route and two prior successful routes
show the same `BLUS30161` cache size (`26,210 KiB`) and the same EBOOT cache
directory (`26,207 KiB`). Prior guest logs report `LLVM: Loaded module` rather
than compiling a replacement object. This rules out a missing or wholesale
invalidated PPU cache as the main warm-start problem.

The source trace found two redundant scans in the normal Thor configuration:

1. `ppu_initialize()` performed a complete check-only hash/cache pass over the
   main PPU executable. Its result is used only to enqueue related directories
   when `LLVM Precompilation` is enabled, but the Thor profile explicitly sets
   that option to `false`. The real initialization then repeated the executable
   partitioning, hashing, and cache checks immediately afterward.
2. Each PPU initialization decoded every instruction looking for `MFVSCR`, even
   when `PPU Set Saturation Bit` was disabled. The result affects code generation
   and the cache key only when that option is enabled. Eternal Sonata Android
   captures and the default configuration both record it as `false`.

The warm-start candidate now:

- runs the check-only main-module pass only when LLVM precompilation is enabled;
- runs the MFVSCR instruction scan only when accurate SAT handling is enabled.

Behavior remains unchanged for both enabled modes. PPU code generation, cache
keys, the real load pass, and the existing cache objects are unchanged for the
Thor configuration.

Host validation:

- `tools/test_ppu_warm_cache_startup.ps1`: passed;
- PowerShell parser validation: passed;
- `git diff --check`: passed;
- `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: `BUILD SUCCESSFUL` in `67.4 s`;
- PPU compile flags remain
  `-march=armv8.2-a -mtune=cortex-a715`.

New host artifact:

- path:
  `app/build/intermediates/cxx/RelWithDebInfo/2t5h1l52/obj/arm64-v8a/librpcsx-android.so`;
- size: `1,347,345,712` bytes;
- SHA-256:
  `70B1D39414A5A60F34311B3836FED2E8580D4934BE9E73DFBD81B5C8B1933601`.

This candidate has not been deployed or launched. The device still has
`744CB3F2...E839`, and no startup-time, temperature, FPS, flicker, menu, battle,
or stability improvement may be claimed until one later separately cooled,
state-gated run.
