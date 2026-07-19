# Thor Cool-title Thermal Counterproof

- Date: 2026-07-19
- Title: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max `c3ca0370`
- Classification: `failed-thermal-guard` / `not-comparable`
- Capture: `debug-captures/android-speed-sprint/20260719-183040-thor-input-custom`
- Exact installed APK: `5C3911D0...682CC6`

## One guarded route

This was the only device route in its independently cool round. The exact
`ThorCoolTitle` profile passed the three-sample launch gate:

- silicon: `31.9 -> 31.7 -> 31.5 C`;
- battery: `22.0 C`;
- skin: `30.0 C`;
- launch maximum: `31.9 C`; and
- launch rise: `-0.4 C`.

RPCSX PID `20425` was established at `18:30:55.4537144-04:00`. The first
readiness image was the same non-title startup progress screen, with the
classifier reporting `progress_bar_white_percent=80.456`, no title selector,
no PPU compilation screen, and no black frame.

The thermal guard then recorded:

- first readiness snapshot: `61.8 C`;
- immediate confirmation: `44.5 C`;
- later samples: `44.9, 45.3, 46.6, 53.8, 40.9, 64.2 C`;
- near-limit confirmation: `72.7 C`; and
- failure-post-stop: `49.4 C`.

The hard-limit confirmation occurred `13.242 s` after PID establishment.
RPCSX was force-stopped. No second launch or follow-up device query ran.

## Runtime activation and bottleneck

The capture proves the intended warm/bounded controls reached native code:

- Vulkan seed: `4,899,180` bytes;
- warm Vulkan first checkpoint: `512` pipelines;
- cache-hit-only Vulkan preload: enabled;
- RSX preload: `256 of 939`, with `683` deferred to runtime;
- RSX workers: `load=2, compile=2`;
- RSX load/compile affinity: exact `0x07`;
- SPU preload: `64 of 1,165`, with `1,101` deferred to runtime; and
- SPU affinity: exact `0x07`.

Two runtime counterproofs replace the host assumptions:

1. Phase pacing waited `5,003 ms`, but the SPU-start generation was still `0`
   while the run expected generation `1`. The PPU main thread began SPU cache
   preload only after this timeout. The wait therefore cannot establish the
   intended SPU-before-RSX order in the current boot sequence.
2. The managed Thor profile sets `Max LLVM Compile Threads=2`. The SPU pool
   consequently logged `requested=2, workers=2, mask=0x7`, not the host-assumed
   `8 -> 3` cap. Both workers then built all `64` programs in about `1.679 s`
   (`8.871 -> 10.550` emulator-log seconds), immediately before the hottest
   startup interval.

The guest log contains zero targeted VM-access, unknown-draw, Vulkan
device-loss, verification, LLVM, assertion, or segmentation-fault hits. This
is a thermal/startup-work failure, not a guest correctness failure.

## Host successor

The next profile is a property-only successor compatible with the exact
already-installed APK, so it does not require another install round:

- cache phase pacing: `off`;
- SPU eager compile budget: `100 ms`;
- SPU preload selection remains oldest-first `64`;
- RSX preload remains `256` with two workers;
- Vulkan cache/hit-only remains on;
- cache-worker affinity remains `0x07`; and
- all thermal, visual, self-stop, quiet-log, and experiment-off gates remain.

The 100 ms budget is checked only between LLVM jobs. Up to two already-running
jobs can finish; every omitted identity remains registered and compiles through
the unchanged runtime-miss path. This targets the observed concentrated SPU
burst without changing SPU semantics or disk-cache identity.

Native phase-pacing code now also fails open immediately when the current SPU
generation has not started, rather than burning the full five-second timeout.
The successor profile disables the experiment, so the currently installed APK
already takes the no-wait path through its `off` property.

The capture analyzer now:

- recognizes macro-failure temperature text even when the thermal log lacks a
  separate `status=failed` row;
- requires the real two-worker activation row;
- requires the 100 ms SPU budget activation row; and
- requires phase pacing to be off.

## Decision

Grant no title, FPS, flicker, gameplay, stability, speed, or temperature-win
credit. Do not retry this device round. After a separate cooling interval,
run exactly one same-APK `ThorCoolTitle` proof with the host successor and
compare time-to-title or time-to-guard, temperature slope, budget-built count,
visual state, and fatal cleanliness against this capture.

## Host verification

- All `59/59` Thor PowerShell contract tests pass.
- Replaying the actual capture through the analyzer deterministically reports
  `status=thermal-stop-before-title`, `max_temperature_c=72.7`, and
  `speed_credit=false`.
- The incremental Android ARM64 native build passed in `98.5 s`.
- The resulting host-only `librpcsx-android.so` is `1,304,687,448` bytes with
  SHA-256
  `69E52332FA995E3FFA09E3C681E44CB0C1F56FF268A28A92AE2ECD3653B1DA80`.
- No APK was assembled or installed in this successor step. The installed APK
  already supports the property-only `100 ms`/phase-off profile.
