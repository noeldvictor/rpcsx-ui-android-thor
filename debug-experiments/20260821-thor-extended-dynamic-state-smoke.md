# 20260821-thor-extended-dynamic-state-smoke

- Status: `closed`
- Classification: `not-comparable`
- Title ID: BLUS30161
- Game: Eternal Sonata
- Platform scope: `android-thor`
- Owner: leanerdesigner
- Created: 2026-08-21
- Last updated: 2026-08-21

## What This Round Did

It put the ports of 2026-08-20 and 2026-08-21 on the device for the first time
and asked one question: does the build run, and does extended dynamic state
switch on?

The answer to both is yes. Nothing else was measured.

## Artifact

- APK: `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`
- SHA256: `3464870CF824A26BC2CDAAE928C3B2E8C1B3C69342CDF806557B84EBAFFC2853`
- The same hash was read back from the device at
  `/data/app/~~JLi-kJb_2YPr9sHGA6yRVw==/net.rpcsx.easy-G9AVCKBs0M5kE2SK7IFb1w==/base.apk`,
  so the running artifact is the built one.
- Commits in the build: `bd2c13249`, `21493f1e1`, `e520d0e9b`, `d91dba53f`.
- The log header reads `RPCSX-ps3-android v20260820-1d34ec9 Draft`. That string
  is stale. CMake has not reconfigured since 2026-08-20, and the string comes
  from configure time. Do not read it as the build identity. The APK hash is the
  identity.
- No dev-core override was active. `dev-core-staging/` holds a `librpcsx-android.so`
  from 2026-07-17, but neither `active-core.path` nor `active-core.json` exists,
  so the app used the core inside the APK.

## The Run Was Not Gated, And Why

The strict cool gate refused twice. The gating sensor is `thermal_zone82`, type
`socd`, which reads whole degrees, not millidegrees. It read `43.7 C` at 14:52
and `37.0 C` at 14:57 against a `35 C` limit. Battery was `22.0 C` and skin was
`30.0 C` the whole time; the device was idle with no other user.

The device is on USB power and cannot be unplugged from here. Charging puts a
floor under `socd`. The user chose a functional smoke test outside the speed
gate instead of waiting.

So this run is `not-comparable`. It carries no speed number, and none should be
read into it later.

## Route

1. `adb install -r`, no launch.
2. `am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity`
   with `--es titleId BLUS30161`, the ISO path, and
   `--ez thorRequireManagedProfile true`.
3. Poll the silicon zones every 3 s and stop at `72 C`.

## What The Device Said

- `15:01:00` boot accepted: `Thor debug boot accepted: request=... titleId=BLUS30161`.
- `0:00:00.863` GPU: `Turnip Adreno (TM) 740`, driver `26.2.99`, API `1.4.358`,
  driver_id `18`. This is Turnip, not the proprietary Qualcomm driver.
- `0:00:00.867` **`RSX: vk: Extended dynamic state is live. The draw path owns
  the topology, the cull mode, the front face and the depth state.`**
  The six entry points resolved and the feature is on.
- `0:00:00.990` driver pipeline cache seeded with `512` pipelines.
- `0:00:02.995` driver pipeline cache saved with `575` pipelines.
- `0:00:09` SPU runtime built about `1188` programs across eight workers.
- The run reached `0:03:03` of emulated time and was still working: the last log
  lines are RSX texture-cache traffic, and the performance sensor read
  `Total: 40.0%` CPU with `194742` SPU self-loop park entries and the same
  number of exits.
- No `FATAL`, no `SIGSEGV`, no `SIGABRT`, no Scudo message, and no Vulkan
  validation or dynamic-state error anywhere in `16431` log lines.

## Thermals

Start `37.0 C`, above the gate. The climb tracks the cache build, not a fault:

    15:01:15  45.8 C     15:02:52  56.6 C
    15:01:41  51.4 C     15:03:24  68.2 C
    15:02:21  56.6 C     15:03:59  72.3 C  <- bound, run stopped

The `72 C` stop is my poll doing its job, not a crash and not the runtime guard.
Hottest zone was `cpuss-2` throughout.

## What This Does Not Show

- No FPS. No frame counter was read, and the run never reached a fixed route.
- No pipeline-count comparison. `debug.rpcsx.thor.vk_dynamic_state_off = 1`
  exists for exactly that A/B, but the device was already at `72 C` and
  AGENTS.md forbids repeating a route into a hot part. `575` pipelines after
  `0:00:03` is the number to compare against on a later cool round.
- **No screenshot.** The run was force-stopped at the thermal bound without one.
  That is my error against the Visual Evidence Rules, not a property of the
  build. Capture the screen before the stop next time.

## Next

1. On a cool round, with the cable out: gate, then run the same route twice,
   once with `debug.rpcsx.thor.vk_dynamic_state_off = 1` and once without.
   Compare the saved pipeline count and the frame rate.
2. Reconfigure CMake so the version string stops lying.
