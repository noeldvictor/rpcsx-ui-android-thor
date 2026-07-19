# 2026-07-18 Thor SPU Native-object Cache

- Target: AYN Thor / Thor Max, Eternal Sonata `BLUS30161`
- Classification: `host-only stackable-cpu-pressure candidate`
- Device state: not queried, installed, launched, or otherwise contacted
- Result: optimized ARM64 build, exact APK packaging, and all host contracts
  pass; the successor also covers the always-built LLVM SPU interpreter and
  hashes exact final IR through versioned binary bitcode serialization;
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

A more aggressive follow-up that would load the interpreter object before IR
construction was rejected. Helper mappings are registered lazily while
lowering calls, so skipping the frontend would also skip the current-process
addresses required to link that object safely. Recovering them would require a
complete versioned helper manifest plus exact runtime build/base identity; the
current code has neither, so the existing frontend/mapping boundary remains.

## Implementation

The new control is default-off and active only for `BLUS30161` LLVM startup
interpreter and cached-program preload:

- Android: `debug.rpcsx.thor.spu_native_object_cache=on|off`
- environment fallback: `RPCSX_THOR_SPU_NATIVE_OBJECT_CACHE`

Behavior:

1. Startup workers still analyse the exact guest program, construct LLVM IR,
   register every current-launch helper/patchpoint mapping, run the existing
   translator transforms, and run the existing optimization passes.
2. After those passes, cached programs use schema `thor-spu-native-v2` and
   the interpreter uses separate schema `thor-spu-interpreter-native-v2`.
   Both keys hash LLVM version, CPU, target triple, target
   attributes/features, compiler flags, data layout, and a streaming LLVM
   bitcode serialization of the final module IR. Use-list order is preserved,
   keeping the key structurally exact without paying textual IR formatting and
   escaping cost.
3. Static audit found the interpreter's direct launch-address dependency in
   the two decrementer-read lowerings: both embedded `&g_timebase_offs`.
   When the cache is opted in, those sites now load named external
   `spu_timebase_offs`, which MCJIT maps to the current launch. The
   default/off path retains its exact original absolute lowering. Any other
   ASLR-sensitive IR constant would still change the key and fail to hit.
   Translator/config IR changes, ARM feature modes, LLVM target changes, and
   data-layout changes also produce a different key.
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
   objects use isolated `spu-native-v2/` storage. The directory and both
   schemas were bumped together, so no v1 object can be interpreted under the
   new serialization contract.

The route wrapper captures requested/effective state and resets the property
before launch, after failure, and after success. The Eternal Sonata sprint
forwards the control, and the no-launch installer records it.

## Scope And Expected Benefit

This is intentionally not guest-hash-only machine-code persistence. Analysis,
IR construction, current-launch symbol rebinding, and optimization remain
because they are the correctness boundary. An exact hit removes the LLVM
backend object-emission step only. The interpreter extension covers one
otherwise-unconditional backend emission before cached programs run. Removing
its known ASLR-dependent timebase constant makes an exact cross-launch object
hit realistic instead of merely safe. The v2 writer also removes textual
formatting from every opted-in program/interpreter key computation. These may
reduce warm-start CPU energy and peak thermal pressure, but can still be too
small relative to RSX pipeline creation and the retained frontend work.

No startup-time, FPS, temperature, flicker, field, menu, battle, or stability
claim follows from host compilation.

## Host Verification

No ADB or device action ran.

- `tools/test_thor_spu_native_object_cache.ps1`: pass.
- All 27 `tools/test_thor_*.ps1` contracts: pass.
- Optimized ARM64 native target with LLVM bitcode writer linkage: pass in 65.1
  seconds.
- ARM64-only optimized ThorTest assembly: `BUILD SUCCESSFUL` in 12 seconds.
- Exact ThorTest ABI/package contract: pass.
- Optimized variant contract: pass.
- Embedded APK core exactly matches the stripped ARM64 core.
- Packaged core contains the property, environment fallback, both v2 program
  and interpreter schemas, v2 directory, interpreter module name, relocatable
  timebase symbol, activation row, and damaged-object cleanup row; all three v1
  strings are absent.
- Export surface: 34 defined dynamic symbols, 587 explicit relocations, 391
  jump slots, and 44,253 encoded relocation bytes.
- `git diff --check`: pass.

Exact host-only artifacts:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,696,098` bytes
- APK SHA-256:
  `0ABDD8A3ECD847DD4B0692D0954C66697D90ABB21CAABE6E8B1E419ADCDA5FAB`
- merged ARM64 core size: `1,306,276,256` bytes
- merged ARM64 core SHA-256:
  `6548B7BADE97817C290524718AC444DCB591768200294D4A5FDC79F844D4C150`
- stripped/packaged core size: `63,136,648` bytes
- stripped/packaged core SHA-256:
  `38167894CC913845996CD13807C73191BAC34F0CC23913B36683F964FD5C2AAA`

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
