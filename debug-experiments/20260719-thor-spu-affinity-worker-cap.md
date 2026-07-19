# 2026-07-19 Thor SPU Affinity Worker Cap

## Result

- Classification: host-verified startup contention and memory-pressure
  reduction candidate.
- Under the existing BLUS30161 Android cache-worker affinity opt-in, SPU
  preload workers are capped to the population count of the requested mask.
- The reviewed `0x07` mask has three bits, so the Thor cool-title profile creates
  three SPU preload workers rather than up to eight workers pinned onto the same
  three Cortex-A510 efficiency cores.
- No APK, ADB, device query, launch, or temperature read ran in this round.

## Problem

`spu_cache::initialize` selected:

`min(get_max_threads(), cached_program_count)`

before applying the optional startup affinity mask inside each worker. The AYN
Thor exposes eight CPU threads. The cool-title profile bounds SPU preload to 64
programs and selects mask `0x07`, but the old path could still construct eight
LLVM workers and then pin all eight onto only three A510 cores.

Those workers atomically claim CPU-bound compile jobs. More runnable compiler
threads than eligible cores do not add cores; they add scheduling contention,
LLVM compiler instances, stacks, and temporary state during the hottest startup
phase.

## Change

For Android only, when the existing title-gated affinity helper returns a
nonzero mask and the SPU preload pool is nonempty:

1. retain the scheduler-selected worker count as diagnostic evidence;
2. count the requested mask bits with `std::popcount`;
3. cap `worker_count` to that bit count before `named_thread_group` is created;
4. emit one activation row containing requested workers, effective workers,
   and the mask; and
5. keep each created worker's existing exact-affinity verification.

For the reviewed route the expected row is:

`Thor SPU cache-worker pool matched to affinity: requested=8, workers=3, mask=0x7.`

`analyze_thor_cool_title_capture.ps1` now requires `workers=3, mask=0x7` before
it can produce `title-proof-ready`. A missing row or different worker count is
`activation-incomplete` and cannot receive comparison credit.

## Boundaries

Unchanged:

- mask `0` Android behavior;
- non-BLUS30161 behavior, because the shared helper returns zero;
- desktop behavior, because the cap is under `__ANDROID__`;
- RSX worker selection;
- SPU program selection, transforms, LLVM output, cache keys, and disk format;
- atomic work claiming and on-demand runtime misses; and
- the existing exact applied-affinity warning/fallback evidence.

This should reduce oversubscription and per-worker memory during bounded SPU
preload. It does not prove a wall-time or thermal improvement. A future cool,
guarded title run must record the activation row, temperature trace, and title
proof before any runtime credit.

## Verification

Passed host-only:

- startup cache-worker affinity source/order contract;
- cool-title capture analyzer ready/mismatch/still-running/thermal/fatal fixtures;
- all `58/58` `tools/test_thor_*.ps1` contracts;
- incremental Android ARM64 RelWithDebInfo build in 66.6 seconds;
- PowerShell AST parsing; and
- `git diff --check`.

No APK was assembled because the combined candidate already needs one later
host rebuild before installation; this change should stack into that build
without spending a separate device round.

## Runtime correction

The later exact-APK route
`20260719-183040-thor-input-custom` supersedes the assumed `8 -> 3` activation
for the managed Thor profile. `Core@@Max LLVM Compile Threads=2` limits
`get_max_threads()` before the affinity cap, so native runtime logged:

`Thor SPU cache-worker pool matched to affinity: requested=2, workers=2, mask=0x7.`

The cap remains a safety bound for configurations requesting more workers, but
it did not reduce this route's pool. The analyzer now requires the real
two-worker row. No runtime speed or thermal-reduction credit belongs to the
worker-cap change.
