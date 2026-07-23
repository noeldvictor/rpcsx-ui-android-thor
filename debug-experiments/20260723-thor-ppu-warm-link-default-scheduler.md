# 2026-07-23 Thor PPU Warm-Link Default Scheduler

## Result

- Classification: device counterproof followed by a host-verified successor.
- Device capture: `debug-captures/android-speed-sprint/20260723-145352-thor-input-custom`.
- Installed APK during the capture:
  `3DFB5F5560775C843210BC80B16943DE20C9887D0DD250DF666B2F9AC2A34A78`.
- New host-only successor APK:
  `87761DADD176CDC7FFC0C3E99E8D2C9CD39694A717F55F06F681374111B083CC`.
- No title, FPS, gameplay, flicker, stability, or thermal-win credit is granted.

## Guarded Device Counterproof

The single approved `ThorCoolTitle` route passed its strict three-sample
preflight at `33.3 -> 33.1 -> 33.9 C` (maximum `33.9 C`, rise `0.6 C`). It
then accepted the exact debug boot and reused eight SPU native objects against
the seven-object continuity floor.

The route never reached title. Thermal telemetry recorded:

- `55.0 C` at the first PPU-ready screenshot;
- `45.8 C` at the first one-second wait poll;
- `65.0 C` at the next poll, above the `64 C` hard ceiling;
- `48.6 C` immediately after force-stop.

RPCSX was force-stopped automatically. The saved `failure-pid.txt` proves the
process absent and all failure-reset properties passed. No retry ran.

## Decisive PPU Timing

The capture contains six ordered fully-warm PPU link markers. The largest
event reused 41 objects at emulator timestamp `1.399200 s`; the next module
started at `3.314319 s`, an interval of `1915.119 ms`.

Matched older default-scheduler captures measured `364.325 ms` and
`363.002 ms` (mean `363.6635 ms`). The earlier full-affinity counterproof was
`1946.229 ms`. Moving affinity restoration before `jit->fin()` recovered only
`31.110 ms` (`1.60%`) and remained `5.27x` slower than the matched baseline.
This isolates the remaining temporary `0x7` affinity around warm-object
admission itself as the regression; finalization was not the main cause.

## Code Correction

Android fully-warm PPU object admission, `jit->fin()`, symbol resolution, and
runtime work now remain on the caller's default scheduler. The scoped `0x7`
affinity for actual cold PPU LLVM compile workers is unchanged. RSX and SPU
bounded preload-worker affinity is also unchanged.

The runtime marker is now:

`Thor PPU warm-cache link using default scheduler: objects=N.`

The title analyzer measures both archived affinity markers and new
default-scheduler markers, but treats any archived warm-link affinity marker
as an activation fallback. New comparison-ready evidence requires the
default-scheduler marker and ordered positive warm-link timing.

## Host Verification

Passed:

- ARM64 `buildCMakeRelWithDebInfo`;
- optimized ARM64-only `assembleThortest`;
- exact APK, merged-core, stripped-core, APK-entry, ABI, and variant gates;
- all `66/66` `tools/test_thor_*.ps1` contracts;
- `git diff --check`.

Exact host successor:

- APK: `87761DADD176CDC7FFC0C3E99E8D2C9CD39694A717F55F06F681374111B083CC`,
  `72,835,124` bytes;
- merged core:
  `4EEE302CA508B7D6F23FCA3F4C27AB9C82B23DDB1D996AB23C562D151B274C90`,
  `1,304,256,792` bytes;
- packaged core:
  `6E7F3251E9A2443DB7819C6769B065D56C52662F7F9E915E94DA54991FAD0E2C`,
  `62,985,064` bytes;
- the APK's `lib/arm64-v8a/librpcsx-android.so` entry matches the packaged core
  exactly.

## Device Boundary

The new successor is not installed and has no device performance or thermal
credit. The Thor remains stopped on `3DFB5F55...A34A78`. A future device round
must first use a separate strict no-launch install. Only a later independently
cool round may spend one self-stopping title proof. Do not retry in the same
hot round.

At `2026-07-23T15:21:43-04:00`, strict no-launch install preflight
`20260723-152143-thor-input-strict-cool-gate` refused on its first sample:
silicon was `48.6 C`, above the `<35 C` install threshold. The guard
force-stopped RPCSX, recorded `46.6 C` after stop, and did not run either of
the remaining preflight samples or `adb install`. The successor therefore
remains host-only and the installed APK remains `3DFB5F55...A34A78`. Do not
retry this device round.

## Installed Successor Runtime Proof

The later exact installed candidate
`490418F9A43B287C376CB9D121C5C3BC93E1AFDEA51ED618BA6AB5882D95BF63`
contains the default-scheduler correction plus the independent upstream LLVM
KnownBits safety slice. Its one permitted route is
`20260723-164343-thor-input-custom`.

Strict preflight passed at `32.1 -> 33.3 -> 32.9 C`. Debug boot was accepted
in `753 ms`, exact installed identity matched, and the guest emitted the new
default-scheduler marker. The largest fully warm PPU event began with 41
objects at emulator time `1.397486 s`; the next one-object module began at
`1.768753 s`, an interval of `371.267 ms`.

This recovers `1543.852 ms` versus the preceding installed counterproof's
`1915.119 ms`: an `80.61%` reduction or `5.158x` faster stage. It is only
`2.09%` above the matched older default-scheduler mean of `363.6635 ms`.
Therefore the warm-object affinity removal is dynamically proven to have
removed the measured PPU link regression.

The route is not an end-to-end win. It attempted `18/64` RSX pipelines, loaded
only `6/7` required SPU native objects, never reached title, and hit `67.0 C`
at the first readiness poll, above the `64 C` hard ceiling. The harness
force-stopped immediately; post-stop silicon was `47.4 C`, PID was absent,
transient properties reset safely, and no targeted fatal occurred.

Classification: device-proven PPU startup-stage speed recovery plus
`thermal-stop-before-title` / `not-comparable`. Grant no title, gameplay, FPS,
flicker, stability, or end-to-end thermal/speed credit. Do not retry this
round; the title capture enforces device-free cooldown until
`2026-07-23T17:14:05.4848450-04:00`.
