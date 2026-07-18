# 2026-07-18 Thor Startup Cache Phase Pacing

## Result

- The installed ARM64 SPU SHUFB candidate did not reach title or gameplay.
- Classify the device run as `failed-thermal-guard` and `not-comparable`.
- No speed, FPS, flicker, title, gameplay, stability, or temperature-improvement
  credit is granted.
- Host-only source now has a default-off Android experiment that serializes
  bounded SPU cache preload and RSX pipeline compilation. Native ARM64 and the
  optimized ARM64-only ThorTest APK both build.
- No APK install or second device launch ran after the thermal failure.

## Device evidence

Strict no-launch gate:

- Capture:
  `debug-captures/android-speed-sprint/20260718-003035-thor-input-arm64-spu-shufb-thortest-runtime-cool-gate`
- Silicon samples: `33.1 -> 32.3 -> 32.7 C`
- Net trend: `-0.4 C`
- RPCSX PID absent.

Only guarded runtime:

- Capture:
  `debug-captures/android-speed-sprint/20260718-003245-thor-input-arm64-spu-shufb-bounded-title-proof`
- Inner preflight: `32.7 -> 32.3 -> 32.3 C`
- PID `11473` established at `00:32:58.332`.
- First runtime poll: `62.6 C` at `00:33:01.019`.
- Confirmation: `69.1 C` at `00:33:01.607`.
- Process establishment to confirmation: about `3.275 s`.
- The 68 C early guard force-stopped RPCSX below the 72 C hard ceiling.
- Immediate post-stop silicon was `47.8 C`.
- Failure occurred before Start/title, so no visual or performance sample exists.
- The direct invocation omitted `-PostSnapshot`; the harness now captures a
  standard failure snapshot for every `BootGame` failure even when that switch
  is omitted.

Matched prior control:

- Capture:
  `debug-captures/android-speed-sprint/20260717-185725-thor-input-parallel-rsx-warm-checkpoint-bounded-title-proof`
- Same managed power policy and cache configuration: RSX workers auto
  (`load=2, compile=2`), RSX preload `256`, SPU preload `64`, Vulkan
  pipeline cache on.
- Process establishment to 68 C was about `6.083 s`.
- The current `3.275 s` guard arrival is a thermal-regression signal, not a
  speed result.

## Startup overlap found in the matched full log

- Vulkan cache creation: about `0.895 s`, seeded with `4,899,180` bytes.
- RSX cache bound: `256/939` around `0.908 s`.
- Two RSX load/compile workers start around `1.040 s`.
- PPU analysis runs around `1.50-1.66 s`.
- Cached PPU modules load around `1.80-2.24 s`.
- Bounded SPU preload starts around `2.247 s`.
- The SPU interpreter is built around `2.390 s`.
- Two SPU workers compile 64 programs around `2.390-2.820 s`.
- Runtime PPU modules continue around `2.827-2.949 s`.

RSX pipeline creation, PPU object loading, and SPU compilation therefore stack
inside the same hottest first three seconds.

## Research translated into this candidate

- FUSE reports that independently acting mobile CPU, GPU, and memory governors
  can miss substantially better same-energy operating points. The applicable
  emulator lesson is to coordinate phases rather than maximize all startup
  workers at once: <https://arxiv.org/abs/2507.02135>
- CPU/GPU co-scheduling research likewise treats scheduling, resource
  partitioning, and power limits as one system-wide optimization problem:
  <https://arxiv.org/abs/2405.03831>
- Recent sustained mobile measurements show peak throughput can collapse once
  thermals dominate, so promotion must use sustained guarded performance rather
  than a cold-start peak: <https://arxiv.org/abs/2603.23640>
- GPU energy sweet spots are workload- and architecture-dependent, and
  frequency reduction can beat blunt power caps. Any Thor operating-point work
  therefore needs measured per-scene A/B evidence:
  <https://arxiv.org/abs/2607.00819>
- JIT code-cache work shows that reusing compiled code can reduce compilation
  time and memory pressure. This supports preserving bounded PPU/SPU/RSX and
  Vulkan caches rather than recompiling everything at boot:
  <https://arxiv.org/abs/1810.09555>

## Host implementation

- `Emu/cache_phase_pacing.h` publishes generation-tagged SPU preload started
  and complete atomics.
- `spu_cache::initialize` publishes started state and uses an RAII completion
  guard, so every return path releases the same emulation generation.
- On Android Vulkan only, `rsx_cache` can wait for that generation's SPU
  preload completion before starting RSX pipeline compilation.
- The wait is opt-in through
  `debug.rpcsx.thor.cache_phase_pacing=on` or
  `RPCSX_THOR_CACHE_PHASE_PACING=on`, defaults off, sleeps in 5 ms slices, and
  times out after five seconds.
- The route and Eternal Sonata sprint wrappers expose default-off controls,
  record requested/effective state, and reset the property before and after all
  success/failure paths.

This is intended to lower peak concurrent power. It may increase time to title,
and it does not reduce total work by itself.

## Host verification

- `tools/test_thor_cache_phase_pacing.ps1`: pass.
- RSX cache preload contract: pass.
- SPU cache preload contract: pass.
- multi-sensor thermal guard contract: pass.
- PowerShell AST parse for both route scripts and the new contract: pass.
- `git diff --check`: pass.
- ARM64 RelWithDebInfo native build: pass.
- ARM64-only optimized ThorTest assembly: pass.
- ThorTest APK ABI contract: pass.
- optimized test-hook contract: pass.
- core export/relocation contract: pass (34 dynamic exports, 583 explicit
  relocations, 44,219 encoded relocation bytes).

Exact host-only ARM64 ThorTest artifact:

- APK:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`
- APK size: `73,575,342` bytes.
- APK SHA-256:
  `F42042F1B0645ECD6AFCFA763AF023322D89958D696D272EDFB26CDEE668D0FE`
- Merged ARM64 core size: `1,305,606,856` bytes.
- Merged ARM64 core SHA-256:
  `24B41068DAA9DB47D5EE8062F8E38B63CF5D9C759D59076DDC8A0960B6F553BC`
- Packaged stripped core size: `62,846,632` bytes.
- Packaged stripped core SHA-256:
  `29308D8E57E40C0A82C718415E105BB68E9EE4300AB48594330712B94C09BE02`

The artifact is not installed and remains `device-unmeasured`.

## Next lower-temperature lane

Android's current ADPF guidance recommends Thermal Headroom and Performance Hint
sessions for sustainable game performance:
<https://developer.android.com/games/optimize/adpf/thermal> and
<https://developer.android.com/games/optimize/adpf>.

The next host design should:

1. capability-gate `AThermal_getThermalHeadroom` and treat NaN/zero-only data
   as unsupported;
2. sample headroom no more than once per ten seconds;
3. adapt only optional background compiler/preload worker budgets or loading
   phases, never guest correctness or emulation fidelity;
4. keep raw multi-sensor ADB guards authoritative until Thor proves useful ADPF
   headroom;
5. consider Android 15 Power Efficiency Mode only when the OS/API supports it.

Only a later independently cool round may install the exact APK without launch.
A different independently cool round may run one guarded pacing-on proof. Require
activation logs, time-to-title, visual proof, temperature slope, and matched
configuration. Reject the candidate if it merely delays the same guard trip.
