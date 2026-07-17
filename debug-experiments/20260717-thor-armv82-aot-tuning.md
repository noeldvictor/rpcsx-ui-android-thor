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
