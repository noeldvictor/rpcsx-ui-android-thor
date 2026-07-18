# 2026-07-18 Thor SPU Native-object Cache

- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `host-only stackable-cpu-pressure candidate`
- Device state: not queried, installed, launched, or otherwise contacted
- Result: optimized ARM64 build, exact APK packaging, and all host contracts
  pass; runtime benefit remains unmeasured

## Problem

The normal SPU disk cache stores guest program identity/data, then analyses,
optimizes, lowers, and links every selected warm program again on each launch.
The bounded Thor profile currently selects 64 oldest boot programs, so repeated
LLVM backend emission still overlaps the pre-title RSX and PPU startup lanes.

Both the vendored core and current official RPCS3 `origin/master`
`a7d90852dd02efcceb539968667201dbc9799cb0` use LLVM's object writer only when
`SPU Debug` is enabled. Normal production compilation calls the uncached
`m_jit.add(std::move(_module))` path. There is no upstream production SPU
native-object reuse to adapt.

Loading a native object directly from the guest-program hash is unsafe. SPU IR
construction registers current-launch helper mappings through
`cpu_translator::call`, binds `spu_dispatcher`, and creates per-launch branch
patchpoints. The generated IR can also contain launch-specific absolute
constants such as the timebase-offset address. A guest-only filename would not
bind translator/config/backend identity and could reuse an incompatible object
under Android ASLR.

## Implementation

The new control is default-off and active only for `BLUS30161` LLVM startup
preload:

- Android: `debug.rpcsx.thor.spu_native_object_cache=on|off`
- environment fallback: `RPCSX_THOR_SPU_NATIVE_OBJECT_CACHE`

Behavior:

1. Startup workers still analyse the exact guest program, construct LLVM IR,
   register every current-launch helper/patchpoint mapping, run the existing
   translator transforms, and run the existing optimization passes.
2. After those passes, the cache key hashes schema `thor-spu-native-v1`, LLVM
   version, CPU, target triple, target attributes/features, compiler flags,
   data layout, and a streaming print of the final module IR.
3. ASLR-sensitive absolute IR constants therefore change the key and fail to
   hit. Translator/config IR changes, ARM feature modes, LLVM target changes,
   and data-layout changes also produce a different key.
4. On an exact warm hit, MCJIT loads and links the relocatable object against
   the mappings rebuilt in step 1, skipping only backend machine-code emission.
5. On a miss, the normal backend runs and Android atomically persists the raw
   object through the existing lower-CPU JIT object writer.
6. A candidate object is parsed before MCJIT receives it. Damaged raw and gzip
   forms are removed and compilation falls back normally.
7. Only the bounded startup preload compiler receives the cache capability.
   The interpreter, gameplay/runtime compiler, and background optimization
   worker retain their original uncached behavior, so runtime misses add no new
   disk I/O.
8. `SPU Debug` retains precedence and its existing `llvm/` output. Production
   objects use isolated `spu-native-v1/` storage.

The route wrapper captures requested/effective state and resets the property
before launch, after failure, and after success. The Eternal Sonata sprint
forwards the control, and the no-launch installer records it.

## Scope And Expected Benefit

This is intentionally not direct machine-code persistence. Analysis, IR
construction, current-launch symbol rebinding, and optimization remain because
they are the correctness boundary. An exact hit removes the LLVM backend object
emission step only. It may reduce warm-start CPU energy and peak thermal
pressure, but it can also be too small relative to RSX pipeline creation and
the retained frontend work.

No startup-time, FPS, temperature, flicker, field, menu, battle, or stability
claim follows from host compilation.

## Host Verification

No ADB or device action ran.

- `tools/test_thor_spu_native_object_cache.ps1`: pass.
- All 27 `tools/test_thor_*.ps1` contracts: pass.
- Optimized ARM64 native target: pass.
- ARM64-only optimized ThorTest assembly: `BUILD SUCCESSFUL` in 36 seconds.
- Exact ThorTest ABI/package contract: pass.
- Optimized variant contract: pass.
- Embedded APK core exactly matches the stripped ARM64 core.
- Packaged core contains the property, environment fallback, schema,
  activation row, and damaged-object cleanup row.
- Export surface: 34 defined dynamic symbols, 587 explicit relocations, 391
  jump slots, and 44,245 encoded relocation bytes.
- `git diff --check`: pass.

Exact host-only artifacts:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,586,438` bytes
- APK SHA-256:
  `3F81D857CAB64048A1373B4B10AB5B4C8175BB27127DCC758D02BF4CC48DB395`
- merged ARM64 core size: `1,305,948,344` bytes
- merged ARM64 core SHA-256:
  `53BC27471653C922F38A45CA5C6A60D870FC93AA700511068054D147F06EBDD5`
- stripped/packaged core size: `62,868,760` bytes
- stripped/packaged core SHA-256:
  `A72245DEA6BA6CC449F77DE4183261013D4C66E8D15544487E735650112990E2`

## Device Boundary

The candidate is uninstalled and `device-unmeasured`. The Thor remains
untouched after the prior rapid thermal trips. Do not combine installation,
cold object seeding, and warm proof in one round.

A future proof, only after independent cooldown, requires separate steps:

1. strict no-launch install and exact on-device APK identity;
2. in a later cool round, one bounded seed attempt with SPU preload limit 64,
   native-object cache on, other new startup controls off, and the existing
   early thermal stop;
3. after another independent cooldown, one identical warm attempt requiring
   exact `LLVM: Loaded module:` rows before comparing time/temperature; and
4. only if startup survives, later field/menu/first-battle correctness and
   sustained thermal proof.

Rollback is immediate: leave or set
`debug.rpcsx.thor.spu_native_object_cache=off`.
