# 2026-07-18 Thor SPU Native-object Cache

- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `host-only stackable-cpu-pressure candidate`
- Device state: not queried, installed, launched, or otherwise contacted
- Result: optimized ARM64 build, exact APK packaging, and all host contracts
  pass; the successor also covers the always-built LLVM SPU interpreter;
  runtime benefit remains unmeasured

## Problem

The normal SPU disk cache stores guest program identity/data, then analyses,
optimizes, lowers, and links every selected warm program again on each launch.
The bounded Thor profile currently selects 64 oldest boot programs, so repeated
LLVM backend emission still overlaps the pre-title RSX and PPU startup lanes.
Before any of those programs can run, RPCSX also constructs and lowers the
large LLVM SPU interpreter on every launch.

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

## Research Decision

Recent primary work supports tiered execution as the broad warm-up direction:

- Druid generates a baseline tier to trade some peak optimization for better
  warm-up: <https://arxiv.org/abs/2502.20543>.
- Deegen combines an interpreter, baseline JIT, and optimizing JIT:
  <https://arxiv.org/abs/2411.11469>.
- 2SOM similarly uses lightweight execution before hot-code optimization:
  <https://arxiv.org/abs/2504.17460>.
- Partial cross-compilation selectively replaces DBT functions with native
  ones, but assumes eligible source/ABI boundaries that arbitrary PS3 guest
  functions do not provide: <https://arxiv.org/abs/2512.00487>.

That direction is not yet safe to implement directly here. RPCSX's
`spu_fast` tier is explicitly x86-64-only, and its background replacement
patch writes an x86 `jmp rel32`. Reusing that path on ARM64 would corrupt
generated code. A new ARM64 baseline emitter and atomic AArch64 patchpoint
contract would be a separate large project.

Android's current guidance also recommends Thermal API headroom and ADPF power
efficiency for sustainable workloads:
<https://developer.android.com/games/optimize/adpf> and
<https://developer.android.com/ndk/reference/group/thermal>. RPCSX already has
a default-off ADPF RSX experiment. Thermal headroom is based on slow-moving
skin sensors, is useful at roughly one-hertz polling, and can return no forecast
for its first samples; it is not a reliable replacement for the existing
sub-second silicon guard during the measured pre-title burst.

The safe immediate slice is therefore exact object reuse for the existing LLVM
tiers, including the interpreter that current official upstream still emits
uncached.

## Implementation

The new control is default-off and active only for `BLUS30161` LLVM startup
interpreter and cached-program preload:

- Android: `debug.rpcsx.thor.spu_native_object_cache=on|off`
- environment fallback: `RPCSX_THOR_SPU_NATIVE_OBJECT_CACHE`

Behavior:

1. Startup workers still analyse the exact guest program, construct LLVM IR,
   register every current-launch helper/patchpoint mapping, run the existing
   translator transforms, and run the existing optimization passes.
2. After those passes, cached programs use schema `thor-spu-native-v1` and
   the interpreter uses separate schema `thor-spu-interpreter-native-v1`.
   Both keys hash LLVM version, CPU, target triple, target
   attributes/features, compiler flags, data layout, and a streaming print of
   the final module IR.
3. ASLR-sensitive absolute IR constants therefore change the key and fail to
   hit. Translator/config IR changes, ARM feature modes, LLVM target changes,
   and data-layout changes also produce a different key.
4. On an exact warm hit, MCJIT loads and links the relocatable object against
   the mappings rebuilt in step 1, skipping only backend machine-code emission.
5. On a miss, the normal backend runs and Android atomically persists the raw
   object through the existing lower-CPU JIT object writer.
6. A candidate object is parsed before MCJIT receives it. Damaged raw and gzip
   forms are removed and compilation falls back normally.
7. The startup interpreter and bounded preload compilers receive the cache
   capability. An empty guest-program cache can therefore seed the interpreter
   object on the first opted-in launch. Gameplay/runtime compilation and the
   background optimization worker retain their original uncached behavior, so
   runtime misses add no new disk I/O.
8. `SPU Debug` retains precedence and its existing `llvm/` output. Production
   objects use isolated `spu-native-v1/` storage.

The route wrapper captures requested/effective state and resets the property
before launch, after failure, and after success. The Eternal Sonata sprint
forwards the control, and the no-launch installer records it.

## Scope And Expected Benefit

This is intentionally not guest-hash-only machine-code persistence. Analysis,
IR construction, current-launch symbol rebinding, and optimization remain
because they are the correctness boundary. An exact hit removes the LLVM
backend object-emission step only. The interpreter extension covers one
otherwise-unconditional backend emission before cached programs run. It may
reduce warm-start CPU energy and peak thermal pressure, but it can still be too
small relative to RSX pipeline creation and the retained frontend work.

No startup-time, FPS, temperature, flicker, field, menu, battle, or stability
claim follows from host compilation.

## Host Verification

No ADB or device action ran.

- `tools/test_thor_spu_native_object_cache.ps1`: pass.
- All 27 `tools/test_thor_*.ps1` contracts: pass.
- Optimized ARM64 native target: pass in 75.6 seconds.
- ARM64-only optimized ThorTest assembly: `BUILD SUCCESSFUL` in 16 seconds.
- Exact ThorTest ABI/package contract: pass.
- Optimized variant contract: pass.
- Embedded APK core exactly matches the stripped ARM64 core.
- Packaged core contains the property, environment fallback, both program and
  interpreter schemas, interpreter module name, activation row, and
  damaged-object cleanup row.
- Export surface: 34 defined dynamic symbols, 587 explicit relocations, 391
  jump slots, and 44,245 encoded relocation bytes.
- `git diff --check`: pass.

Exact host-only artifacts:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,584,666` bytes
- APK SHA-256:
  `370B78F4670D046E355F04F5A43479A2BE24F064B75AB3C42BC4BA4AAFCFE484`
- merged ARM64 core size: `1,305,955,328` bytes
- merged ARM64 core SHA-256:
  `8AD2D904940F222D08B40891FC4CE84A67572238F5F044E828AF03C7376BA345`
- stripped/packaged core size: `62,869,416` bytes
- stripped/packaged core SHA-256:
  `23EFCAF83CA72467B64A995328A1B5390178D394462013E4AE11E617245CE189`

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
   an exact `LLVM: Loaded module: spu-interpreter-` row plus program-object
   load rows before comparing time/temperature; and
4. only if startup survives, later field/menu/first-battle correctness and
   sustained thermal proof.

Rollback is immediate: leave or set
`debug.rpcsx.thor.spu_native_object_cache=off`.
