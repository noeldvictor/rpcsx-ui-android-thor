# 2026-07-19 Thor Combined Title Thermal Stop

## Result

- Classification: guarded device rejection plus host-verified startup-log optimization.
- Target: AYN Thor Max, Eternal Sonata `BLUS30161`.
- Installed APK SHA-256:
  `7CDD38E415CCFDF7BCCE4B4EC20D9B914E65B62F571E868014927BCAAD8FE5F9`.
- The one permitted cool-start attempt was force-stopped at the early thermal
  guard. It did not reach the title screen and earns no FPS, speed, frame-poll,
  flicker, gameplay, stability, or temperature-improvement credit.
- No relaunch, retry, or post-stop device query occurred in this round.

## Thermal Evidence

Strict no-boot gate capture:

`debug-captures/android-speed-sprint/20260719-163229-thor-input-combined-candidate-title-runtime-cool-gate`

- silicon: `31.5 -> 32.3 -> 31.9 C`;
- battery: `22.0 C`;
- skin: `30.0 C`;
- gate result: pass.

Bounded runtime capture:

`debug-captures/android-speed-sprint/20260719-163325-thor-input-custom`

- inner preflight silicon: `33.1 -> 31.9 -> 31.7 C`;
- first screenshot thermal snapshot: `59.0 C` silicon;
- immediate near-limit confirmation: `68.7 C` silicon;
- early-stop threshold: `68 C`;
- hard-stop threshold: `72 C`;
- post-stop evidence captured by the guard: `44.5 C` silicon, `23.0 C`
  battery, and `30.0 C` skin.

The guard stopped the package below the hard limit. This is a rejected launch,
not a thermal win. The device stays stopped until a separately cool round.

## Visual And Runtime Evidence

The only screenshot, `01-ppu-ready-poll-01.png`, classifies as:

- black frame: false;
- PPU compilation screen: false;
- title menu: false;
- story/loading visual: true;
- field: false;
- battle: false;
- progress-bar white percent: `80.782`.

The emulator log covers only about `1.7 s`. It contains no title-menu proof and
no frame-poll activation counters. The enabled frame-wait, handler-grace,
continuous-rearm, and cache-phase controls therefore never reached their
intended title/runtime proof point.

## Actual Hot Stage

The failure log identifies an earlier startup stage than the cache-phase barrier:

- Vulkan initialization: about `0.879 s`;
- validated warm driver pipeline-cache seed: `4,899,180` bytes at `0.914138 s`;
- shader-cache preload workers: `load=2, compile=2` at `1.056052 s`;
- first RSX loader diagnostic: `1.402857 s`;
- last captured RSX loader diagnostic: `1.699136 s`.

Across that roughly `296 ms` diagnostic window, the two shader-load workers
emitted 412 decompiler error rows:

- 329 unknown/illegal instruction;
- 42 unknown source type;
- 17 bad source register;
- 12 bad scale;
- 7 break outside loop;
- 2 unimplemented call;
- 2 hanging block;
- 1 unexpected precision.

Source ordering matters: `load_shaders()` reads and decompiles cached programs,
then `wait_for_android_spu_preload_phase()` runs, and only afterward does
`compile_shaders()` create graphics pipelines. The force-stop occurred during
the first load/decompile stage. Consequently:

1. the absent cache-phase pacing log is expected; the barrier was not reached;
2. this capture does not prove the phase barrier failed; and
3. Vulkan cache-hit-only preload would affect the later pipeline compile stage,
   not eliminate this captured shader-decompiler work by itself.

## Host Code Improvement

Android Vulkan startup for `BLUS30161` now compacts only preload-worker shader
decompiler diagnostics:

- one representative row of each diagnostic kind is retained per worker;
- duplicates are counted and reported in one post-load summary;
- shader inputs, decompilation, cache identity, pipeline creation, and runtime
  compilation are unchanged;
- runtime/gameplay diagnostics are unchanged;
- non-Android builds use a constant-true diagnostic path and carry no TLS state;
- one-worker inline loading without an affinity worker keeps the prior logging
  behavior, avoiding state resets across its batched callback invocations.

Replaying the stopped capture's worker/kind distribution predicts 13 retained
representative writes and 399 suppressed duplicates: `96.8%` fewer duplicate
error writes. This is a measured log-work reduction against saved evidence,
not a measured device-temperature or time-to-title result. Decompilation itself
still runs and may remain the dominant cost.

## Verification

Host-only verification passed:

- focused preload-diagnostic compaction contract;
- all `55/55` `tools/test_thor_*.ps1` contracts;
- `git diff --check`;
- Android ARM64 RelWithDebInfo native build in `93 s`;
- resulting debug-bearing `librpcsx-android.so`: `1,304,702,360` bytes.

Thor was not queried, installed to, launched, or temperature-polled during the
code/verification phase.

## Next Independently Cool Proof

Do not repeat this launch while the device is warm. A later no-launch round may
package and install the new exact APK under the strict three-sample gate. After
independent cooling, spend at most one short guarded title attempt using the
lower-power startup controls already implemented:

- cache-worker affinity mask `0x07` (three efficiency cores);
- two RSX cache workers;
- RSX preload limit `256` and SPU preload limit `64`;
- cache-phase pacing on;
- validated Vulkan pipeline cache on;
- Vulkan preload cache-hits-only on for the later pipeline-compile stage;
- the same external `68 C` early stop and `72 C` hard stop.

Require effective affinity logs, the new compacted diagnostic summary, warm-seed
and cache-hit-only activation evidence, time-to-title, visuals, and thermal
slope. Reject the candidate if it merely delays the same thermal stop. Do not
grant sustained speed or temperature credit until field and first-battle proofs
also pass in later separately cool rounds.
