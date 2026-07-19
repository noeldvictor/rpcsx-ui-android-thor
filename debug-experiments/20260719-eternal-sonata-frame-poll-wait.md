# Eternal Sonata VBlank-assisted frame-poll wait

Date: 2026-07-19

## Outcome

The Eternal Sonata BLUS30161 main PPU loop at CIA `0x002a8300` spends a
large amount of host time issuing 100 us timer sleeps while waiting for a
VBlank-driven guest counter. An opt-in, title- and call-site-gated wait now
blocks on a portable 32-bit guest VBlank-handler completion generation for at
most 1 ms. After a real handler completion it allows a bounded 0-500 us grace
for the guest counter update, then falls back to the original timer behavior
whenever the expected progress is not observed.

This is a host-verified reduction in wakeups and CPU work. It is not yet a
Thor temperature result because the handheld was deliberately left idle
after the user reported it was hot.

## Evidence that identifies the wait

Ghidra disassembly of the legally owned BLUS30161 executable:

```text
002a82d8  lbz   r11,0x260(r31)
002a82e4  divw  r0,r0,r11
002a82e8  lwz   r9,0(r28)
002a82ec  cmplw cr7,r0,r9
002a82f0  ble   cr7,0x002a8318
002a82f8  li    r3,0x64
002a82fc  li    r11,0x8d
002a8300  sc
002a8304  lbz   r29,0x260(r31)
002a8308  lwz   r0,0(r28)
002a830c  divw  r29,r30,r29
002a8314  bgt   cr7,0x002a82f8
```

The stock post-syscall profiler at the 60 FPS title screen recorded:

- 433,029 calls by 54.933 s, or about 7,883 calls/s.
- 2,831 decisive `post_ready` samples.
- 2,821 of 2,831 decisive samples (99.65%) were associated with the current
  VBlank or a delayed guest callback after it.
- Average post-VBlank callback lag was 480 us; the rare maximum was 17.16 ms.

An alternate flip-status wait was rejected and removed: the forced HLE path
observed zero waiting states across 2,700 calls, so it was not the controlling
wait for this route.

## Safety and portability contract

The optimized branch requires all of the following:

- explicit opt-in;
- title ID `BLUS30161`;
- main PPU ID `0x01000000`;
- CIA `0x002a8300`;
- exactly a 100 us requested sleep;
- `r31 == r28 + 4`;
- valid counter/config memory;
- frame divisor exactly 30 or 60;
- counter below its derived threshold.

The wait uses a dedicated 32-bit `vblank_wait_token`, not
`futex_waitv`. The existing 64-bit `vblank_count` remains diagnostic.
`vblank_waiters` prevents callback-completion markers when nobody is waiting.
Each main wait is bounded to 1,000 us. The optional post-handler grace is
bounded to 500 us and defaults to the measured 500 us candidate. VBlank or
counter mismatch re-enters the original 100 us timer path, and any counter
progress rearms the next VBlank wait. The feature defaults off.

Enable controls:

- Windows host lab: `-EternalSonataFramePollWait Wait`
- Android sprint property: `debug.rpcsx.thor.es_frame_wait=wait`
- Android grace property: `debug.rpcsx.thor.es_frame_wait_grace_us=0..500`
- Android/host environment: `RPCSX_THOR_ES_FRAME_POLL_WAIT=wait` or
  `RPCS3_ES_FRAME_POLL_WAIT=wait`
- Grace environment: `RPCSX_THOR_ES_FRAME_POLL_HANDLER_GRACE_US=0..500` or
  `RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US=0..500`

## Host measurements

| Route | Version | Frame loop | Calls | Calls/s | Fallback sleeps | FPS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Title | Stock post profiler | threshold 1 | 433,029 at 54.933 s | 7,883 | n/a | 60 |
| Title | First bounded-wait candidate | threshold 1 | 93,798 at 54.497 s | 1,721 | 63,225 | 60.02-60.06 |
| Title | Counter-progress refinement | threshold 1 | 82,877 at 52.246 s | 1,586 | 52,801 | 59.98-60.00 |
| Title | Handler completion, 0 us matched control | threshold 1 | 87,700 at 52.336 s | 1,676 | 58,032 | 59.98 |
| Title | Handler completion + 500 us grace | threshold 1 | 83,655 at 52.529 s | 1,593 | 54,027 | 59.99-60.05 |
| First battle | First bounded-wait candidate | threshold 2 | 360,433 at 154.735 s | 2,329 | 273,878 | about 30 |
| First battle | Counter-progress refinement | threshold 2 | 272,633 at 152.079 s | 1,793 | 179,422 | 29.97-30.03 |
| First battle | Handler completion + 500 us grace | threshold 2 | 228,187 at 154.268 s | 1,479 | 147,658 | 29.97-30.02 |

The refined title path is about 79.9% below the stock call rate. In the
threshold-2 field/battle route, recognizing partial counter progress reduced
the call rate by 23.0% and fallback-sleep rate by 33.3% versus the first
bounded-wait candidate.

A matched 2 ms title experiment was rejected. It retained 60 FPS, but reached
120,998 calls and 106,243 fallback sleeps by 52.741 s, versus 82,877 calls and
52,801 fallback sleeps by 52.246 s with the 1 ms bound. Its 49 s host CPU
sample also rose from 18.2% to 23.0%. The longer timeout reduced useful
counter-progress observations from 588 to 249 and pushed more iterations back
through the original 100 us fallback. Because 2 ms was already worse, the
planned 4 ms test was not run and the 1 ms ceiling was retained.

The refined first-battle host CPU samples were 22.6% at 120 s and 21.6% at
150 s. The prior stock synchronization-profile route measured 25.8% and
25.7% at the same checkpoints, a 14.2% reduction in the two-sample mean.
These samples support lower host work but are not direct Android power or
temperature measurements.

### Handler-completion grace result

The raw VBlank wake was moved behind the queued guest VBlank handler, with no
extra callback or notification on the stock path when there are no waiters.
A same-binary title A/B then selected 500 us over 0 us:

- call rate: 1,676/s to 1,593/s, down 5.0%;
- fallback-sleep rate: 1,109/s to 1,029/s, down 7.2%;
- futile fallback-rearm rate: 34.9/s to 13.9/s, down 60.3%;
- observed counter-progress rate: 9.4/s to 29.9/s, up 218%;
- matched title FPS remained 60 and both external-contention gates were clean;
- the single title CPU snapshot was 27.0% versus 23.1%, supportive but too
  noisy to treat as a standalone power result.

The full first-battle route with handler completion plus 500 us grace also
passed. Relative to the prior raw-VBlank counter-progress refinement, its
time-normalized call rate fell 17.5%, fallback-sleep rate fell 18.9%, and
futile rearm rate fell 66.2%. Its three late host CPU samples averaged 23.8%
versus 26.6% for the prior capture. This CPU comparison is supportive rather
than definitive because the samples are sparse and the first prior sample was
an outlier.

Correctness gates passed:

- title menu at 60 FPS;
- full title Options page at 60 FPS plus a clean ten-second hold;
- Path to Tenuto save target and load completion;
- playable Path to Tenuto field;
- first-battle prompt, active battle, live battle, and hold;
- no fatal error, access violation, unknown draw, or Vulkan device-loss
  signature;
- clean bounded process stop.

Evidence:

- `debug-captures/windows-lab/20260719-020830-es-frame-poll-progress-rearm-title`
- `debug-captures/windows-lab/20260719-021004-es-frame-poll-progress-rearm-first-battle`
- `debug-captures/windows-lab/20260719-042237-es-frame-poll-handler-grace0-title`
- `debug-captures/windows-lab/20260719-042357-es-frame-poll-handler-grace500-title`
- `debug-captures/windows-lab/20260719-042613-es-frame-poll-handler-grace500-first-battle`
- `debug-captures/windows-lab/20260719-044904-es-frame-poll-handler-grace500-options-proof-clamped`

The speed wrapper's older menu macro was repaired after it exposed two route
assumptions rather than emulator failures: cutscene-timed input could fire
before the title menu appeared, and 20 ms pulses from an old 240 FPS capture
could be lost at the current 60 FPS cap. The retained macro first gates on the
visible title menu, then uses three 120 ms Down pulses to clamp the cursor to
Options before capturing both the page and hold frames.

## Build and regression verification

- Windows RPCS3 Release target: passed after the final main-PPU gate.
- Android `arm64-v8a` RelWithDebInfo native target: passed after the final
  main-PPU gate and again after the callback-completion/grace port (135.8 s);
  no APK install or launch occurred.
- `tools/test_thor_es_frame_poll_wait.ps1`: passed.
- `tools/test_thor_es_sync_profile.ps1`: passed.
- `git diff --check`: passed for the scoped source and tool files.

## Research interpretation

- Android common kernels provide the futex base, but Android bionic's common
  seccomp policy and Thor's runtime make `futex_waitv` an unsafe dependency.
  The implementation therefore uses the emulator's existing portable
  32-bit atomic wait/notify path.
- [Partial Cross-Compilation and Mixed Execution](https://arxiv.org/abs/2512.00487)
  supports selective native handling when guest/host boundary costs are
  carefully bounded; this change targets one measured call site instead of
  broad syscall substitution.
- [Learned translation rules for dynamic binary translation](https://arxiv.org/abs/2402.09688)
  reinforces profiling and narrow rule selection rather than speculative
  whole-program shortcuts.
- [Mobile CPU-GPU co-execution](https://arxiv.org/abs/2510.21081) is relevant
  to large parallel workloads, but a tiny synchronization loop is a poor GPU
  offload candidate because transfer and dispatch costs dominate.
- [Android ADPF](https://developer.android.com/games/optimize/adpf) can request
  performance resources, which may increase heat. For this objective, removing
  needless wakeups is preferable to requesting a higher sustained performance
  state.
- Current Android Thermal API guidance says not to query thermal headroom more
  than once every 10 seconds and warns that unsupported or over-polled devices
  can return NaN. Thor's saved failure rose from about 32.3 C to 69.1 C by
  3.275 s while PPU analysis, cached-module loading, and two SPU compilers
  overlapped. Thermal headroom remains useful for slow sustained adaptation,
  but it is too slow to prevent this measured startup spike. Startup work
  budgeting and wakeup removal remain the primary path.
- The 2025 direct-translation and partial-cross-compilation papers reinforce
  two future lanes: reduce repeated guest/host coordination in already-hot
  translated blocks, and only native-offload stable functions whose boundary
  cost is amortized. Neither supports broad unsafe HLE substitution.

## Cool-device validation still required

When the Thor has cooled, validate with one short A/B route and the existing
thermal guard:

1. Record preflight battery, skin, silicon, fan, and performance mode.
2. Run the stock mode for a bounded first-battle window, then force-stop and
   cool fully.
3. With one APK, run `-EternalSonataFramePollWait Wait` with
   `-EternalSonataFramePollHandlerGraceUs 0`, cool fully, then repeat with
   `-EternalSonataFramePollHandlerGraceUs 500`.
4. Compare steady FPS, frame-poll counters, CPU/GPU clocks, energy proxy, and
   temperature rise versus time.
5. Stop immediately on the existing near-limit or hard thermal guard.

Until that measurement passes, keep the feature opt-in and do not claim a
Thor temperature reduction.

## Android presentation and panel-power follow-up

Saved Thor logs make the display path a concrete follow-up rather than a
rendering guess:

- repeated captures report `Swapchain: present mode 1 in use` while the
  effective config reports `Force FIFO present mode: false`;
- Vulkan defines mode 1 as MAILBOX and mode 2 as FIFO;
- the May 16 live observation reported panel flicker, while screenshots and
  10 FPS extraction did not expose a black or missing-texture frame;
- later still screenshots were clean but cannot prove temporal absence.

Current upstream RPCS3 was audited again at `origin/master` `a7d90852d`. The
March 2026 tri-state VSync commit `e690e7e45` replaces the old force-FIFO
setting but does not add Android frame-rate requests. Full VSync still maps to
FIFO. No newer official ARM64/RSX change was found that supersedes the fork's
already-adapted wait, checksum, worker-recycling, or Vulkan fixes.

Android's February 2026 power guidance says a display rate above the game's
target has no gameplay benefit and increases panel power. Its refresh-rate
guide recommends `setFrameRate()` at game-window initialization and warns that
requesting a rate above attainable FPS wastes power and raises temperature.
The Surface API accepts a 30 FPS request even when the display only exposes a
60 Hz mode, allowing Android to select a compatible multiple.

Implemented candidate, scoped to `BLUS30161` on a detected AYN/Thor target:

- request 30 FPS on the gameplay `Surface` before boot;
- allow only seamless display-mode changes on API 31+;
- use fixed-source compatibility through Android 15 and game/default
  compatibility on Android 16+;
- set the managed Eternal Sonata Vulkan profile to FIFO;
- retain system defaults for every other title and non-Thor device;
- expose `-ThorDisplayPacing on|off` and `-ForceFifoPresent On|Off` so a
  single installed APK can run a short combined A/B without reinstall churn.

Host verification:

- `ThorDisplayPacingTest`: passed title, path-normalization, non-Thor,
  other-title, and explicit-off gates;
- `tools/test_thor_display_pacing.ps1`: passed API, title gate, FIFO, A/B
  plumbing, and PowerShell parser contracts;
- Thor-test APK packaged successfully without install, launch, or ADB access;
- artifact:
  `app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk`;
- size: 73,710,702 bytes (ARM64-only);
- SHA-256:
  `52549D7C26CA3A70DF99EA8765AE91317764472BE36052FC8E97C180C5E75D13`;
- APK contents verified for the manifest, DEX, ARM64 core, and JNI library.
- ARM64-only APK, optimized test-hook, multi-sensor thermal-guard, and v2
  signing contracts passed.

Research:

- https://developer.android.com/games/optimize/power
- https://developer.android.com/games/optimize/display-refresh-rate-change
- https://developer.android.com/reference/android/view/Surface
- https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html

This is not yet a measured Thor speed, flicker, power, or temperature win.
When the device is explicitly cool, use one bounded historical-baseline versus
combined-candidate comparison, with the existing preflight and runtime thermal
stops. Do not run a four-cell decomposition unless the combined candidate
regresses or the result is ambiguous.
