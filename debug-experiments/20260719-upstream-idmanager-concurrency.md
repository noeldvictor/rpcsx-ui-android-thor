# Upstream IdManager concurrency backport

Date: 2026-07-19

## Outcome

Backported upstream RPCS3 commit `2cacaa2da4b4d0c489a06528bd02368d0bf8ba84`
(`IDM: Optimize IDs for concurrency`) into the Thor Android tree and the local
upstream worktree. The `remove`, `remove_verify`, and `withdraw` paths now
decode and validate an object ID before acquiring the global IdManager lock,
then use the already-computed index while locked.

This shortens global-lock hold time and prevents invalid IDs from taking the
lock at all. It is a safe general concurrency optimization, but it is not yet
a measured Thor FPS, power, or temperature improvement.

## Upstream screen

The 157 commits between the local upstream reference and official
`origin/master` were screened for ARM64, PPU, SPU, RSX, Vulkan, scheduling,
and synchronization changes.

- The headline ARM64 improvements, including I8MM GBH/GBB, JIT feature
  isolation, TBL ROTQBY, PPU FTZ/NJ handling, and SPU floating-point
  selection, were already present in the Thor tree.
- The RSX wait/cacheline changes and PPU JIT thread-recycling fixes were also
  already present.
- The newer mip-zero resolution-scale fix is semantically covered by the
  Thor tree's older global scaling model and was not force-applied across the
  incompatible configuration layouts.
- Newer overlay-calibration and `sys_rsx` mapping changes target different
  data layouts or validation models and were rejected for this backport.
- The IdManager change was the strongest missing, narrow, architecture-neutral
  optimization with a small correctness surface.

## Lock-scope change

For each affected removal path:

1. Compute `get_index<Get>(id)` before taking `id_manager::g_mutex`.
2. Return immediately when the index is outside the configured ID range.
3. Acquire the original lock.
4. Resolve with `find_index<T, Get>(index, id)` instead of recomputing the
   index through `find_id` while holding the lock.

Object exchange, slot clearing, type validation, and destruction semantics
remain unchanged.

## Verification

- Windows RPCS3 Release target: full rebuild passed.
- Android `arm64-v8a` RelWithDebInfo native target: full build passed; a
  follow-up up-to-date build passed in 1 s.
- `tools/test_thor_id_manager_concurrency.ps1`: passed for both Android and
  Windows sources. It verifies all three paths validate before the lock, use
  `find_index` after the lock, and no longer call `find_id` in the changed
  segments.
- `tools/test_thor_es_frame_poll_wait.ps1`: passed, confirming the earlier
  Eternal Sonata bounded-wait contract remains intact.
- Scoped `git diff --check`: passed.
- Bounded Windows title smoke:
  `debug-captures/windows-lab/20260719-025356-upstream-idmanager-title-smoke`.
  The title gate passed at 48 s, reported 60.02, 59.93, and 59.98 FPS, and
  stopped cleanly at 55 s with exit code 0. No fatal error, Vulkan device
  loss, access violation, assertion, or deadlock signature was found, and no
  emulator process remained.

The smoke confirms stability, not a statistically attributable IdManager
speedup. This optimization affects short, contention-sensitive object-removal
paths rather than the title screen's dominant steady-state frame loop.

## Thermal status

No ADB query, install, launch, or device workload was performed. The Thor was
deliberately left idle after the user reported it was hot. A short, guarded
on-device A/B remains required after the user explicitly says the handheld is
cool and ready before making any temperature or battery claim.
