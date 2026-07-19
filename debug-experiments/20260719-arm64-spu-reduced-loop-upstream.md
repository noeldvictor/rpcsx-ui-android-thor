# ARM64 SPU Reduced Loop Upstream Alignment

Date: 2026-07-19

## Scope

Audit the Android fork against the latest official RPCS3 SPU LLVM work and
import only missing changes that are narrow, architecture-correct, and useful
for Thor stability. This round was host-only because the Thor was thermally
resting.

Official RPCS3 master was locally synchronized through commit
`a7d90852dd02efcceb539968667201dbc9799cb0`. Existing fork code already carried
the recent SPU FMA select, LS mirror, and related PPU/vector changes. Two July
17 Reduced Loop fixes were missing:

- `b35e4434a`: check `spu_thread::state` before another optimized Reduced Loop
  iteration; and
- `21d533675`: do not reuse the x64-only not-NaN ruling on ARM64.

Upstream history:
<https://github.com/RPCS3/rpcs3/commits/master/>

## Adaptation

`SPURecompiler.h` now returns `false` from `is_gpr_not_NaN_hint` outside x64.
The local bounds check remains on x64.

`SPULLVMRecompiler.cpp` now folds `spu_thread::state == 0` into the condition
that re-enters an optimized Reduced Loop when no branch-specific verification
path is active. Upstream's member-pointer helper is not present in this fork,
so the equivalent local typed offset form is used:

`spu_ptr<u32>(OFFSET_OF(spu_thread, state))`.

The state load remains SPU-context attributed, matching the surrounding LLVM
IR construction.

## Why this is retained

The state check prevents an optimized loop from continuing after the SPU
thread has been asked to stop. Disabling the unsupported ARM64 NaN hint avoids
an architecture-invalid optimizer assumption. These are correctness and
stability alignments; any reduction in wasted work is secondary.

They do not establish a battle FPS or temperature improvement and are not
being counted as one.

## Host verification

- `tools/test_thor_spu_reduced_loop_upstream.ps1`: pass;
- ARM64 `:app:buildCMakeRelWithDebInfo[arm64-v8a]`: pass after adapting the
  state pointer to the fork's helper surface;
- no APK install, launch, ADB query, or Thor telemetry operation occurred.

## Device boundary

Keep normal behavior as the only path; these fixes do not add a property or
experimental toggle. A later independently cool Thor run still needs to prove
title, field, first-battle, and menu correctness. Temperature or speed credit
requires matched device evidence from the same artifact and route.
