# Thor Android Raw PPU Object Cache

- Date: 2026-07-18
- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `stackable-cpu-pressure`, host-only
- Device status: stopped; no query, install, launch, or runtime action

## Objective

Reduce Android boot CPU work and its associated thermal pressure after PPU
cache preparation. Preserve LLVM object validation, atomic cache writes,
low-space failure behavior, desktop compatibility, legacy Android cache
compatibility, and the existing parsed-object warm handoff.

This is startup work reduction, not an FPS claim. Thor remains the authority
for frame rate, frame pacing, sustained temperature, flicker, and gameplay
correctness.

## Baseline Path

`ObjectCache::notifyObjectCompiled` always appended `.gz` and compressed
each LLVM object. `ObjectCache::load` preferred that compressed file, read it
into memory, inflated it, then passed the owning buffer to LLVM.

The preceding zero-copy and parsed-object handoff work already eliminated a
second post-inflate allocation/copy and a second warm read/inflate/parse. It
could not eliminate the remaining gzip inflate itself.

The loader already supported RPCS3's raw object form at the exact path without
the `.gz` suffix, making a backward-compatible Android-only policy possible.

## Measured Storage/Decode Proxy

Source:

`C:/Users/leanerdesigner/Documents/New project 6/rpcs3-upstream/build-msvc/bin/cache/BLUS30161`

The saved first-battle Windows cache contained:

| Metric | Value |
| --- | ---: |
| LLVM object files | 84 |
| Compressed bytes | 18,465,084 |
| Expanded bytes | 82,230,196 |
| Expansion | 4.45x |
| Additional raw storage | 63,765,112 bytes / 60.81 MiB |

A three-pass PowerShell/.NET `GZipStream` proxy decoded the same set in
`1816.0 ms` cold and `663.9-783.4 ms` on cached passes
(`100.1-118.1 MiB/s`). This is a direction and sizing measurement only:
it is not NDK zlib timing, Thor UFS timing, an Android startup delta, or a
temperature prediction.

## Implementation

Files:

- `app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp`
- `app/src/main/cpp/rpcsx/rpcs3/util/JIT.h`
- `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`
- `tools/test_thor_jit_object_cache_android_raw.ps1`

Behavior:

1. Android JIT object writes use the existing raw object filename and skip
   gzip. Desktop builds retain the current compressed writer.
2. Android loads raw first, then accepts legacy `.gz`; desktop retains gzip
   first, then raw fallback.
3. Raw writes still use `fs::pending_file`, exact byte-count checks, atomic
   commit, and the compiler's disk budget. Only after raw commit does the
   writer remove an obsolete compressed sidecar.
4. The existing explicit Prepare Cache action enables migration for its
   duration. `ppu_initialize` and `ppu_precompile` validate the exact live
   objects the title requests; only successfully parsed compressed objects
   are atomically materialized raw.
5. Ordinary boot does not scan or convert a directory. If Prepare Cache has
   not migrated a legacy object, normal boot retains the old compressed path.
6. Migration keeps the compressed object if free space is insufficient,
   opening/writing/committing raw fails, or the object fails LLVM validation.
7. A damaged cache validation removes both the raw path and `.gz` sidecar,
   fixing the old repeated-failure case where only the suffix-free path was
   removed after a damaged compressed load.
8. The existing all-hit parsed-object handoff remains: validation, migration,
   and linking share the same owning buffer rather than reading or parsing the
   object again.

The stopped-emulator migration uses one atomic budget shared by all PPU
precompile workers and capped at one quarter of free cache storage. Failed
writes refund their reservation. Production SPU LLVM compilation remains
uncached when `SPU Debug=false`, so the raw-write policy primarily affects
PPU objects in the normal Thor profile.

## Host Verification

Passed without contacting Thor:

- new Android raw-cache source contract;
- previous JIT decompression zero-copy contract;
- previous validated parsed-object handoff contract;
- PPU warm-cache startup contract;
- SPU FMA, KnownFPClass, ARM64 multiply, ARM64 decrementer, LQX/STQX, SHUFB,
  bounded SPU cache, and reduced-loop safety contracts;
- PPU FTZ/NJ and Android loader-log contracts;
- startup phase pacing, RSX preload, Vulkan pipeline cache, visual route, and
  strengthened thermal-guard contracts;
- no-launch installer and single-core-load contracts;
- final ARM64 RelWithDebInfo native build in 59 seconds (initial full build 128 seconds);
- final ARM64-only ThorTest rebuild in 17 seconds (initial full build 108.7 seconds);
- optimized variant and exact ARM64 APK/core hash contract;
- core export surface: 34 defined dynamic symbols, 583 explicit relocations,
  391 jump slots, and 44,219 encoded relocation bytes;
- binary strings in the stripped ARM64 core for raw write, validated
  materialization, low-space fallback, and damaged-entry cleanup; and
- `git diff --check`.

## Exact Host-only Candidate

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,575,378` bytes
- APK SHA-256:
  `4BCB8D9C528860F9AD633DD2AF3507D4ABF01299967520E0A1D288570EB08816`
- merged ARM64 core size: `1,305,707,488` bytes
- merged ARM64 core SHA-256:
  `B1B989D25F759540A11EECBD117F5B547A1B66B51446BCAE0FD5C4843AC07164`
- packaged stripped core size: `62,851,672` bytes
- packaged stripped core SHA-256:
  `900720F0817040D2291D75463131F811C88015EE36A96CE7D6DEF77132EC5680`

This candidate includes the upstream-derived SPU FMA dependency-chain
shortening plus the zero-copy and parsed-object PPU warm-cache handoff.

## Device Boundary And Next Proof

The APK is uninstalled and device-unmeasured. The Thor remains stopped on
exact APK `E69D671D2B6F74BAC6DEAF2A3A08D7DC98877B0F8654E7C89AC2A0BA68B6C509`.
The preceding route reached `78.3 C` before title, so no device action is
authorized in this host round.

A later separately cool sequence should be:

1. strict install-only gate and exact on-device APK hash;
2. no launch in the install round;
3. in a different independently cool round, run Prepare Cache while RPCSX is
   stopped, confirm validated raw-materialization rows and raw-over-gzip cache
   state, then stop and cool again;
4. only in another cool round, spend one guarded title/gameplay proof; and
5. classify speed or temperature only after matching field, first-battle, and
   menu correctness survives with comparable power/fan/cache state.
