# Eternal Sonata VBlank-assisted frame-poll wait

Date: 2026-07-19

## Outcome

The Eternal Sonata BLUS30161 main PPU loop at CIA `0x002a8300` spends a
large amount of host time issuing 100 us timer sleeps while waiting for a
VBlank-driven guest counter. An opt-in, title- and call-site-gated wait now
blocks on a portable 32-bit VBlank generation for at most 1 ms, then falls
back to the original timer behavior whenever the expected guest counter
progress is not observed.

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
`vblank_waiters` prevents notifications when nobody is waiting. Each wait is
bounded to 1,000 us. VBlank or counter mismatch re-enters the original 100 us
timer path, and any counter progress rearms the next VBlank wait. The feature
defaults off.

Enable controls:

- Windows host lab: `-EternalSonataFramePollWait Wait`
- Android sprint property: `debug.rpcsx.thor.es_frame_wait=wait`
- Android/host environment: `RPCSX_THOR_ES_FRAME_POLL_WAIT=wait` or
  `RPCS3_ES_FRAME_POLL_WAIT=wait`

## Host measurements

| Route | Version | Frame loop | Calls | Calls/s | Fallback sleeps | FPS |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Title | Stock post profiler | threshold 1 | 433,029 at 54.933 s | 7,883 | n/a | 60 |
| Title | First bounded-wait candidate | threshold 1 | 93,798 at 54.497 s | 1,721 | 63,225 | 60.02-60.06 |
| Title | Counter-progress refinement | threshold 1 | 82,877 at 52.246 s | 1,586 | 52,801 | 59.98-60.00 |
| First battle | First bounded-wait candidate | threshold 2 | 360,433 at 154.735 s | 2,329 | 273,878 | about 30 |
| First battle | Counter-progress refinement | threshold 2 | 272,633 at 152.079 s | 1,793 | 179,422 | 29.97-30.03 |

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

Correctness gates passed:

- title menu at 60 FPS;
- Path to Tenuto save target and load completion;
- playable Path to Tenuto field;
- first-battle prompt, active battle, live battle, and hold;
- no fatal error, access violation, unknown draw, or Vulkan device-loss
  signature;
- clean bounded process stop.

Evidence:

- `debug-captures/windows-lab/20260719-020830-es-frame-poll-progress-rearm-title`
- `debug-captures/windows-lab/20260719-021004-es-frame-poll-progress-rearm-first-battle`

## Build and regression verification

- Windows RPCS3 Release target: passed after the final main-PPU gate.
- Android `arm64-v8a` RelWithDebInfo native target: passed after the final
  main-PPU gate; no APK install or launch occurred.
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

## Cool-device validation still required

When the Thor has cooled, validate with one short A/B route and the existing
thermal guard:

1. Record preflight battery, skin, silicon, fan, and performance mode.
2. Run the stock mode for a bounded first-battle window, then force-stop and
   cool fully.
3. Run `-EternalSonataFramePollWait Wait` for the same route.
4. Compare steady FPS, frame-poll counters, CPU/GPU clocks, energy proxy, and
   temperature rise versus time.
5. Stop immediately on the existing near-limit or hard thermal guard.

Until that measurement passes, keep the feature opt-in and do not claim a
Thor temperature reduction.
