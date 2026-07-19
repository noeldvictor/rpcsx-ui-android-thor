# Eternal Sonata SPU Runtime Heat Profile

- Date: 2026-07-18
- Title: Eternal Sonata `BLUS30161`
- Subsystem: SPU LLVM runtime profiling
- Decision: `reject-selective-spu-hle; pivot-to-ppu-rsx`
- Device state: host-only; no ADB, install, launch, or temperature read

## Goal

Replace static opcode-family counts with bounded dynamic evidence from the
first battle. A title-specific native SPU fast path is worth implementing only
when a function or block is both materially hot and resident long enough that
guest/native transition overhead cannot consume the saving.

## Profiler Design

The Windows RPCS3 source now has an independent `ES SPU Heat Profiler`
thread with these constraints:

- requires both the dedicated `RPCS3_ES_SPU_HEAT_PROFILE=compact` process
  switch and the transient `SPU Profiler: true` run config;
- activates only after `Emu.GetTitleID() == "BLUS30161"`;
- samples active SPU `block_hash` values every 250 microseconds;
- stores no more than 8,192 hashes;
- counts active, zero-hash, and capacity-dropped samples;
- counts observed entries whenever a sampled SPU changes hash;
- emits cumulative top-32 snapshots every 30 seconds and a final snapshot
  when shutdown is graceful.

The entry counter is sampling evidence, not an exact branch counter. It is
still sufficient for the gating question: a block seen only once per sampled
entry has very short observed residency and is a poor cross-boundary HLE
candidate.

The sprint/lab plumbing makes this opt-in, restores the transient config and
process environment after the run, extracts the compact sampler lines to
`spu-heat-summary.txt`, and invokes
`tools/summarize_eternal_sonata_spu_heat.ps1`. The analyzer reports
cumulative-snapshot deltas, samples per observed entry, zero/dropped deltas,
and whether active sampling plateaued. Snapshot block rows are explicitly
limited to the logged top 32.

## Warm-Cache Lifecycle Finding

The first profiler version started behind:

```text
while (!registered && thread_ctrl::state() != thread_state::aborting)
```

With a warmed SPU cache, no new compiler registration was required, so the
profiler thread was never created. Moving the independent sampler before that
wait fixed activation without changing the existing compiler-priority
`SPU LLVM Profiler` behavior.

The contract test now requires the heat-profiler construction to precede the
warmed-cache wait. This is a repeated lifecycle guard, not merely a string
presence check.

## Rejected and Diagnostic Runs

- `20260718-215800-es-spu-heat-compact250us-first-battle-windows`
  completed the old timing-only route but emitted no sampler rows because the
  profiler was behind the warmed-cache wait.
- `20260718-220942-es-spu-heat-compact250us-first-battle-retry2-windows`
  reproduced the same no-output failure.
- `20260718-221858-es-spu-heat-activation-check-windows` proved that dynamic
  title rechecking alone was insufficient while construction remained behind
  the wait.
- `20260718-222639-es-spu-heat-activation-check2-windows` proved the lifecycle
  fix: its first snapshot contained 18,789 active samples, 349 zero samples,
  zero dropped samples, and 1,188 unique hashes.
- `20260718-222811-es-spu-heat-final-first-battle-windows` produced nine
  snapshots, but active samples stopped changing after snapshot 5. The
  analyzer correctly marked the late interval as a plateau. The obsolete
  legacy route did not prove battle state, so this run is invalid for
  candidate selection.

The gray legacy screenshots are not classified as an emulator flicker
regression. They came from an unreliable Windows capture/route combination
and have no device relevance.

## Valid State-Aware First-Battle Run

Run:

`debug-captures/windows-lab/20260718-224053-es-spu-heat-stateaware-first-battle-windows`

The promoted state-aware route used visual/log gates instead of fixed waits:

- title and load targets were detected;
- the field gate completed at approximately 73 seconds;
- the first-battle prompt was captured at approximately 88 seconds;
- active battle was captured at approximately 93 seconds;
- live battle was captured at approximately 104 seconds;
- the held battle frame was captured at approximately 114 seconds;
- the host-contention gate remained clean for all six snapshots;
- the title stayed near the configured 30 FPS cap during field/battle;
- no targeted fatal or unknown-draw evidence was present.

Sampler snapshots:

| Snapshot | Time | Active | Zero hash | Dropped | Unique blocks |
|---:|---:|---:|---:|---:|---:|
| 1 | 31.918 s | 18,354 | 363 | 0 | 1,238 |
| 2 | 61.919 s | 42,963 | 921 | 0 | 1,534 |
| 3 | 91.920 s | 77,949 | 1,435 | 0 | 1,961 |
| 4 | 121.921 s | 110,260 | 1,890 | 0 | 2,123 |
| 5 | 151.922 s | 143,039 | 2,377 | 0 | 2,199 |

The default snapshot-2-to-5 delta was 100,076 active samples, 1,456 zero
samples, zero drops, and no plateau. Snapshot 4 to 5 is fully after the
active-battle gate and is the candidate-selection window:

- active delta: 32,779;
- zero-hash delta: 487;
- dropped delta: 0;
- plateau: false.

Graceful window close was not accepted by RPCS3 within ten seconds, so the lab
used its force-stop fallback. Periodic snapshots preserved the bounded result;
there is no final snapshot for this run.

## Battle-Only Candidate Ranking

Top snapshot-4-to-5 rows:

| Hash | PC | Delta samples | Delta entries | Samples/entry |
|---|---:|---:|---:|---:|
| `086607ca5c330290` | `0x00a40` | 9,308 | 7,139 | 1.304 |
| `b8cb6b3de8660331` | `0x00cc4` | 1,652 | 1,624 | 1.017 |
| `9f32313d574e02f3` | `0x00bcc` | 1,423 | 1,364 | 1.043 |
| `cc3db71918801127` | `0x0449c` | 1,239 | 1,206 | 1.027 |
| `6e98c7523ce30180` | `0x00600` | 858 | 841 | 1.020 |

Hash `086607ca5c330290` is genuinely hot: it accounts for 28.4% of all
battle-window active samples. It is not low-transition. The profiler observed
about 238 entries per second across the sampled SPUs, and 1.304 samples per
entry corresponds to only about 326 microseconds of sampled residency at the
250-microsecond interval. Every other leader is effectively one sample per
entry.

## Decision

Do not implement a title-gated native SPU HLE body from this ranking. The only
materially hot block crosses too frequently, and the other blocks offer even
less residency. A helper/HLE boundary would be likely to trade JIT work for
transition, state-marshalling, and validation overhead rather than reduce
power.

The next dynamic lane is PPU/RSX attribution during the same state-aware
battle window. Prefer compact function residency or frame-stage timing that
can distinguish CPU submission, PPU work, and GPU/driver wait. Do not return
to a speculative SPU body without new evidence that aggregates multiple hot
blocks behind one low-frequency boundary.

## Verification

- Release `rpcs3.exe` build passed after the final source change.
- Windows artifact:
  - bytes: `65,048,064`
  - SHA-256: `C805F19BB1428F2B8D725B78967A56B9C11B7FE4D2699DA3D72074677F85BF29`
  - timestamp: `2026-07-18T22:54:07.3041110-04:00`
- `tools/test_thor_spu_heat_profile.ps1` passes.
- The analyzer's Markdown interpolation defect was fixed and its source
  contract now protects the format expression.

## Classification

This round improves profiling correctness and selects the next optimization
lane. It is not an FPS speedup, temperature reduction, flicker fix, or device
runtime result. No Thor interaction occurred.

## Follow-up: Bounded PPU/RSX Attribution

The Android fork now restores the upstream `PPU Profiler` configuration,
thread registration, direct-call CIA publication, and profiler flushing. A
separate opt-in `RPCS3_ES_PPU_RSX_PROFILE=compact` mode is title-gated to
`BLUS30161` and emits ten-second top-16 guest PPU summaries. The same gate
enables existing Vulkan frame-stage counters and emits setup, vertex upload,
texture upload, draw, flip, draw-call, and submit summaries. Normal gameplay
keeps the mode disabled.

The first compact trace exposed an instrumentation error: RPCS3 synthetic HLE
addresses were ranked as guest PPU blocks, which made savedata and audio waits
look hot. The compact sampler now uses `ppu_function_manager::is_func()` to
separate exact HLE samples from guest samples. It does not use a guessed address
range. The filtered Windows mirror compiled and linked successfully.

### Bounded Windows Evidence

- `20260718-232325-es-ppu-rsx-stateaware-first-battle-profile-windows`
  produced 149 summary lines but missed the first-battle prompt. It is field-only
  evidence. The heaviest field interval accounted for approximately 2.30 ms of
  RSX work per frame: setup 847 us, vertex upload 368 us, texture upload 618 us,
  draw 102 us, and flip 362 us. The leading guest PPU addresses were highly
  transition-heavy.
- `20260718-233618-es-ppu-rsx-hlefiltered-repeatmove-first-battle-profile-windows`
  verified exact HLE separation, then aborted at the load-target gate because a
  lost title-menu Down pulse selected New Game and entered the black opening
  sequence. This was not an emulator crash.
- `20260718-234106-es-ppu-rsx-hlefiltered-hardened-first-battle-profile-windows`
  used normalized title selection and reached the Path to Tenuto field. The
  live fatal gate then correctly rejected repeated guest `unknown draw command`
  output before battle. Its last accepted ten-second interval reported 733
  guest-active PPU samples across 291 blocks, with the top three blocks at only
  56/47, 44/42, and 40/38 samples/entries. Accounted RSX work was approximately
  2.46 ms per frame: setup 759 us, vertex upload 318 us, texture upload 684 us,
  draw 91 us, and flip 607 us.

The state-aware route now normalizes the title cursor to OPTIONS and steps back
to LOAD, preventing a lost single Down pulse from launching New Game. The
unvalidated repeated field movement was removed after it entered the guest
draw-command corruption path; the previously validated single movement path is
retained.

### PPU/RSX Decision

Do not promote an RSX optimization from these traces. Even in the heaviest
accepted interval, measured RSX stage work is below 2.5 ms per frame, far below
the approximately 33.3 ms budget at the observed 30 FPS cap. Texture upload and
setup are the largest RSX components, but neither explains the frame limit.

Do not promote a guest PPU superpath from this trace. The hot guest blocks are
short and transition-heavy, and the exact HLE filter removed the only apparent
long-residency savedata/audio candidates. Together with the battle-only SPU
ranking above, the evidence points toward synchronization, scheduling, or
cross-domain stalls rather than a single long PPU, SPU, or RSX body.

### Follow-up Verification

- Windows artifact:
  - SHA-256: `3C58487906EF6B46FE3B9696BD01821773367C286B9ED1EAF8121A82D3ABB35B`
  - timestamp: `2026-07-18T23:33:52.3746944-04:00`
- Both PowerShell tools parse successfully.
- All 33 `tools/test_thor*.ps1` host contracts pass in fresh PowerShell
  processes.
- No ADB, APK deployment, device launch, or Thor telemetry query occurred.

This follow-up improves attribution and route reliability. It still earns no
FPS, temperature, flicker, or device-runtime credit.
