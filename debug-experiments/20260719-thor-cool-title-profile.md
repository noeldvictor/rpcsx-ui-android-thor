# 2026-07-19 Thor Cool-title Startup Profile

## Result

- Classification: host-verified route safety/tooling.
- New wrapper profile: `-AndroidStartupProfile ThorCoolTitle`.
- Supported actions: `AndroidProfileStatus` for a host-only dry-run and
  `AndroidRouteScene` for the future guarded device proof.
- No ADB resolution, device query, install, launch, screenshot, or temperature
  read occurred while implementing or testing this profile.
- The exact uninstalled APK remains
  `504C614B27008D83CCE3DAF232ED194BC15139E38388DC0112728005F6E35588`.

## Why This Was Needed

The rejected `20260719-163325-thor-input-custom` launch correctly enabled
cache-phase pacing but left cache-worker affinity and RSX/SPU preload limits at
their zero/default values. The intended lower-power plan was `0x07` affinity
and `256/64` bounds. A long hand-written command made that omission easy.

The named profile makes the next proof one reviewed unit and fails closed if
the caller explicitly supplies a conflicting value. It does not change normal
wrapper defaults or emulator behavior.

## Exact Resolved Profile

Host-only `AndroidProfileStatus` resolves:

- macro: `gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop`;
- direct input;
- no redundant post-route live scene capture; the title screenshot, title-state
  check, guest-health check, and force-stop all occur inside the bounded macro;
- one-second thermal polling;
- runtime early-stop headroom: `4 C` below the `72 C` hard limit;
- near-limit probe window: `16 C`;
- three preflight samples, two seconds apart;
- preflight headroom: `0 C`;
- maximum launch silicon: `35 C`;
- maximum preflight rise: `1 C`;
- battery/skin/silicon limits: `34/40/72 C`;
- RSX workers: `2`;
- RSX preload limit: `256`;
- SPU preload limit: `64`;
- cache-worker affinity mask: `7` / `0x07` efficiency cores;
- Vulkan pipeline cache: on;
- Vulkan preload cache-hit-only: on;
- cache-phase pacing: on;
- ADPF RSX hint: off;
- SPU native-object experiment: off;
- RSX/SPU compile budgets: zero;
- semaphore, DMA, GPU probe, and RSX blit experiments: off;
- frame-poll wait: `Wait`, grace `500 us`, continuous rearm on;
- quiet logging;
- Perfetto and screen recording disabled;
- runtime affinity unchanged;
- route post-wait: zero;
- force-stop retained after success or failure.

## Fail-closed Behavior

The wrapper snapshots the original script-bound arguments before applying the
profile. Any explicitly supplied value that differs from the reviewed profile
throws before serial resolution or ADB use. Host contracts prove rejection of:

- `-AndroidRsxCachePreloadLimit 0` instead of `256`;
- using the profile with a non-route action; and
- `-KeepAndroidRunningAfterCapture`.

`AndroidProfileStatus` is deliberately absent from the action list that calls
`Resolve-SpeedAndroidSerial`, so dry-run verification remains device-free.

## Verification

Passed:

- PowerShell AST parsing;
- exact host-only resolved-profile output;
- conflict, wrong-action, and keep-running rejection checks;
- ordering: profile application before device resolution and action dispatch;
- all `58/58` `tools/test_thor_*.ps1` contracts after the proof analyzer was added;
- `git diff --check`;
- no build, emulator, or device process left active.

## Device Boundary

This profile does not authorize a launch. The combined APK must first pass a
future genuinely cool, strict no-launch installation round. Only after another
independent cooling interval may `AndroidRouteScene` spend one guarded title
attempt. If the early thermal guard trips again, stop and reject; do not retry
in the same round.
