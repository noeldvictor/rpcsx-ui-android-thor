# HLE SPURS: leaked pending contention deadlocked every workload

Date: 2026-08-27
Title: BLUS30357 Transformers War for Cybertron
Config: hle_libs=libsre.sprx, hle_spurs_kernel=1, kernel1 (K2=0)

## Symptom

Six SPUs spinning, 6.5-7.2 cores busy, 0 fps, main_thread parked on the
0x00fdcf60 fence with `done` never reaching `target`. Frames stopped in the 30s.

## The measurement that named it

    select#1 wkl2: runnable=1 prio=0 maxCont=1 cont=1 ready=1 idle=0 signal=1
                   rawCont=0x00 rawMax=0x01 curId=32 locC=0 isPoll=1

wkl2 was runnable, ready and signalled, yet every SPU declined it. `rawCont` is
the shared `wklCurrentContention` and it is **0x00**, and this SPU's `locC` is
0 - so the blocking `cont=1` was pure **pending** contention. The selector gate
is `wklMaxContention[i] > contention[i]`, i.e. `1 > 1`, false forever. All six
SPUs fell back to the system service workload (curId=32) and nothing dispatched.

## Cause

`spursKernel1SelectWorkload`, the poll branch that raises pending contention:

    for (u32 i = 0; i < CELL_SPURS_MAX_WORKLOAD; i++)
    {
        spurs->wklPendingContention[i] = pendingContention[i];
        ctxt->wklLocPendingContention[i] = 0;
    }

`wklLocPendingContention[X]` is the ONLY record that this SPU owes a decrement
on workload X. If the SPU polled X earlier and now polls a different workload,
this loop writes X's +1 straight back into the shared counter while zeroing the
local record. Nothing will ever subtract it. Permanent +1 per leaked workload,
and with maxContention = 1 that closes the gate for good.

It is also a bulk write-back of a stale snapshot over an array six SPUs share,
so it loses other SPUs' updates by construction - the same defect that was
already fixed for `wklCurrentContention` via `thor_contention_atomic_fix`.

## Fix

`debug.rpcsx.thor.pending_contention_fix` (default ON), in cellSpursSpu.cpp:

- Poll branch: release every pending slot this SPU actually holds, atomically
  and per entry, then take the one it just selected. Nothing another SPU owns
  is touched.
- The two shared `wklPendingContention[i] = pcur - ploc` writes in kernel1 are
  now `atomic_op` subtracting only this SPU's own `ploc`.

kernel2 has the same shape at the nibble-packed write-back and is NOT patched;
this title runs kernel1 (K2=0).

## Result

|                          | before                    | after                |
|--------------------------|---------------------------|----------------------|
| harness fps              | 0.0                       | 19.8                 |
| thor_wait_ready          | false                     | true                 |
| main_thread fence probe  | fires, done < target      | never fires          |
| game's own overlay       | -                         | FPS 30.03, SPU 63.9% |
| real workloads selected  | none                      | wid=0, wid=6         |
| task ELFs started        | 0                         | 2                    |

## NOT fixed - do not read the fps as success

The screenshot is a FLAT GREEN frame carrying only the game's own debug overlay.
RSX is 5.9%. It is not a 3D scene, so 19.8 fps is empty flips and means nothing.

Remaining blocker, measured: the task on taskset 0x10364100 has issued
**128,896 yields, 1 waitSignal, 0 poll, 0 recvFlag, 0 exits, 0 NOSYS**. It polls,
gets nothing, yields, forever. Only two task ELFs have ever started
(0x101b4e80 and 0x10364100) and neither has ever exited.

## Retracted along the way

- "LLE never enters the 0x00fdcf60 fence." Wrong - the probe's own comment
  records main_thread sitting there in the working LLE run too. The probe only
  fires when the wait SPINS, so LLE's absence meant it converges, not that it
  never arrives.
- "The task's queue pointer is null." Inferred from the 0x80410911
  (CELL_SPURS_TASK_ERROR_NULL_POINTER) constant in the poll prologue, then
  disproved: LS 0x36210 holds 0x1030e400, not zero. That dump also predates the
  fix. `TASK ARGS` shows taskset 0x10364100's task 0 does receive r3=0, but it
  gets tsArgs=0x01f94f10 in r4.
- The 30 fps LLE baseline used for most of this effort was the intro MOVIE
  (Bink Audio Thread running), not a 3D scene. thor_sample cannot guard it for
  this title: cellVdec never fires because the title decodes Bink on the SPUs,
  so the probe reports videoDecoding=false with reliable=false. Judge from the
  screenshot only.

## Follow-up A/B: the draws happen, the geometry does not

The consumer task was NOT stuck. `Thor QUEUE PUSH OK #4864` and
`QUEUE RING head=128 tail=128 depth=256 used=0` show the PPU pushing and the
ring draining. `POPRC` prints the poll's actual return:

    POPRC: lr=0x0f3e4 r80=0x80410901 r82=0x80410901 r3=0x1 r5=0x27c4 r86=0x3ff00

0x80410901 is CELL_SPURS_TASK_ERROR_AGAIN - "empty right now". An idle consumer
polling an empty queue is normal. 128k yields is idling, not deadlock.

Same elapsed point, screenshot-verified, LLE vs HLE:

|                    | LLE                          | HLE        |
|--------------------|------------------------------|------------|
| screen             | shaded 3D geometry on black  | flat green |
| game internal FPS  | 30.00                        | 29.96      |
| PPU                | 10.5%                        | 5.0%       |
| SPU                | 17.0%                        | 64.5%      |
| RSX                | 2.2%                         | 5.8%       |
| coresBusy          | 0.26                         | 3.98       |
| draw calls / flips | 1103 / 1440                  | 1132 / 1560|

Draw call RATE IS IDENTICAL (~1 per flip). HLE issues the same draws and shows
nothing, with RSX slightly HIGHER than LLE. So the geometry is submitted and
comes out degenerate/invisible - the SPU-produced vertex or transform data is
WRONG, not missing. HLE also burns 3.8x the SPU time to produce it.

Next: dump the vertex/transform buffer for that draw under both configs and
diff. Do not spend more time on queue plumbing - it is measured working.
