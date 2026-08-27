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

## Past SPURS: why no triangle draw is ever issued

Exact per-primitive census (counters, not sampling), same point in the boot:

    LLE   p5=73(e=1310328)  p6=1(e=4)  p8=973(e=3892)
    HLE   p5=0              p6=0       p8=914(e=3656)

p5 is TRIANGLES. LLE renders the scene in ONE burst of 73 draws / 1.31M
vertices between flips 600 and 720, then only blits ~1 quad per flip. HLE never
issues that burst, which is the whole of the missing picture.

The chain, each link measured, with a clean LLE control that hits none of it:

1. `cellSpursCreateTaskWithAttribute` fails with 0x80410902 (INVAL).
2. So the worker task is never created.
3. The title falls back to an ANY2ANY LFQueue at 0x101b1f80, whose PPU push
   functions `_cellSyncLFQueueGetPushPointer2` and
   `_cellSyncLFQueueCompletePushPointer2` are `todo` stubs returning CELL_OK.
   They never write *pointer and never call fpSendSignal.
4. So the task parked in WAIT_SIGNAL on taskset 0x101b4e80 is never woken -
   zero non-queue `_cellSpursSendSignal` calls in an entire run - and the
   geometry stage never runs.

### Why create_task rejected it

`_cellSpursTaskAttributeInitialize` is a Thor-local implementation; upstream
RPCS3 has it as an argument-less stub, so the layout was inferred. The raw ABI
registers say:

    r3=0xd00aa370 r4=0x1 r5=0x310000 r6=0x1765800
    r7=0xd00aa358 r8=0x0 r9=0x1098933f r10=0x1098933e

r9 and r10 are readable but NOT 16-byte aligned, and both `CellSpursTaskLsPattern`
and `CellSpursTaskArgument` are 16 bytes. The old code checked readability only,
so it read 16 bytes from an unaligned address and stored a garbage pattern -
which then failed create_task's `ls_blocks > alloc_ls_blocks` and
`pattern & 0xFC000000` (SPURS management area) checks.

Two consecutive descending odd addresses are leftover registers, not arguments.

### thor_task_attr_fix - correct, but DEFAULT OFF

Rejecting an unaligned pointer as absent makes create_task succeed, and the
third task is finally created and started on taskset 0x1f73f00. The ANY2ANY
LFQueue stubs stop being hit entirely. But that task then deadlocks the
instance:

    task_attr_fix=0   ready=true  ready=true   draws 434, 300 (all quads)
    task_attr_fix=1   ready=false ready=false  draws 0, hangs at ~47 frames

Neither renders the scene. 30 fps with the UI drawing is closer to working than
a dead instance, so the fix ships OFF behind
`debug.rpcsx.thor.task_attr_fix=1`, which is the switch for working on the
deadlock it exposes.

RETRACTED while doing this: "sizeContext == 0 means no context". r8 is 0, but
r7 points at a {context,size} pair reading {0x10989380, 0x1c00} - 128-byte
aligned, sane size - so the context is real. Dropping it took draws from 914 to
0 while task starts went 2 -> 3.

## task_attr_fix, second pass: the pattern must be sized, not zeroed

Zeroing the absent ls_pattern passes create_task and then KILLS the title:

    SPU[0x0000100] (CellSpursKernel0) [0x31c44] SIG: Thread terminated due to
    fatal error: Unknown STOP code: 0x0 (op=0x0, Out_MBox=empty)

op=0x0 is an all-zero instruction - the SPU is executing cleared local store. A
zero pattern saves NO local store, so a task resumed on a different SPU than it
ran on gets that SPU's stale LS and branches into nothing. The control run with
the fix off shows no such error, so this one was ours.

spursTasksetDispatch names the right value itself: it skips reloading the ELF
only when the pattern is exactly

    v128::from64r(0x03FFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF)

which is blocks 6..127 - the whole task area with the six SPURS management
blocks masked off, 122 blocks, exactly alloc_ls_blocks for a 0x3d400 context.

Bit mapping, verified against that constant: block i < 64 is bit (63 - i) of
_u64[0]; block i >= 64 is bit (127 - i) of _u64[1].

This title uses THREE context sizes: one 0x3d400 (122 blocks) and two 0x1c00
(3 blocks). Asking for 122 where only 3 fit fails create_task, so the pattern
is synthesised to fit: full pattern when it fits, otherwise the TOP alloc
blocks, since dispatch reloads the ELF when the pattern is not the magic value
and what cannot be reconstructed is the mutable state - the task stack, which
sits at the top of LS (sp=0x3fe70 on the observed callsite).

    synthesised for 3 blocks (context size 0x1c00) -> ...0007

Measured progress with task_attr_fix=1:

    fatal errors      1  -> 0
    create_task fails 3  -> 1 -> 0
    task starts       2  -> 3 -> 12
    tasksets running  2  -> 3   (0x101b4e80, 0x10364100, 0x1f73f00)

STILL DEFAULT OFF: draws are 0 and the instance deadlocks at ~52 frames, where
with the fix off it renders the UI at 30 fps. Neither state renders the scene.

## The remaining blocker

    [0]exit=0 [1]yield=369791 [2]waitSig=2 [3]poll=0 [4]recvFlag=0

Two tasks are parked in WAIT_SIGNAL and nothing wakes them. cellSpursQueuePush
is the only caller of _cellSpursSendSignal in the whole run, and its wake scan
reads the waiting bitmap of the QUEUE'S taskset only:

    for w in 0..3: word = ts->waiting[w]; if word: wake = w*32 + clz(word)

The one queue (0x1030e400) is bound to 0x10364100, which has no waiter, so
`wake` keeps its initial value and signals taskId=1 - a task that does not
exist there, returning SRCH (0x80410905) every time. The actual waiters are on
0x101b4e80 and 0x1f73f00.

So the wake mechanism those two tasks are waiting on is not
cellSpursSendSignal, not cellSpursEventFlagSet (zero calls), and not this
queue. Finding it is the next step.

## The contention slot is NOT leaked - retiring a whole hypothesis class

`cont=1 maxCont=1 rawCont=0x01 curId=32 locC=0` on every SPU that prints looks
identical whether a real holder is busy inside a task (and so never reaches the
selector to print) or the slot leaked with no holder at all. The printed lines
cannot separate those, because the SPU inside a task is exactly the one that
does not appear.

So the holder is now recorded as the counter moves - `g_thor_wkl_holders[wid]`,
bit n meaning SPU n believes it holds that workload - and printed in the select
probe. Measured:

    wkl2: maxCont=1 cont=1 rawCont=0x01 curId=32 locC=0 holders=0x01

Bit 0 set: SPU0 genuinely holds it, and maxContention=1 correctly excludes the
other five. The accounting is right and this signature is NOT a leak.

That retires the leak hypothesis for this state. It does not undo the two
contention fixes already committed - those were confirmed by their own
measurements (rawCont=0x00 with locC=0 for pending, and a slot orphaned across
a wklCurrentId change for current) - but it does mean the remaining hang is not
another counter bug and should not be chased as one.

With task_attr_fix off, boots are stable: three consecutive runs ready=true at
803, 1065 and 1095 frames, ~29.5 fps, holders=0x01 each time. The intermittent
early hangs seen earlier belong to the task_attr_fix=1 path.

## The wake target, found - and the ANY2ANY push implemented

Captured at queue creation, which every run reaches (the push stubs are reached
only on some):

    LFQINIT: queue=0x101b1f80 buffer=0x101b2000 size=32 depth=16 dir=3
             eaSignal=0x1e97a81

dir=3 is CELL_SYNC_QUEUE_ANY2ANY. eaSignal 0x1e97a81 is the SPURS instance
0x1e97a80 - the value the TASK ARGS probe reports - with bit 0 set, the tag
meaning "signal through SPURS". That is the wake the parked task needs, and it
is why nothing in HLE delivered it: _cellSpursSendSignal is only ever called
from cellSpursQueuePush, which scans a different taskset entirely.

eaSignal names the instance but not which taskset waits on it, so tasksets are
now recorded as they are created (Thor TSREG) and the wake scans them for one
with a non-zero `waiting` bitmap.

`_cellSyncLFQueueGetPushPointer2` and `_cellSyncLFQueueCompletePushPointer2`
are implemented against the ring convention used throughout this codebase -
counters mod 2*depth, buffer index = counter mod depth, producer index in
push3.m_h5 and consumer index in pop3.m_h1 (push1/push3 and pop1/pop3 are
unions over the same words). The old stubs returned CELL_OK without writing
*pointer, so PushBody memcpy'd every entry into slot 0 and completed a push
that signalled nothing.

It works, and the signal is accepted:

    LFQWAKE #0: spurs=0x1e97a80 taskset=0x101b4e80 taskId=0 rc=0x0

rc=0 is CELL_OK. The task that had been parked since boot is woken for the
first time, and its behaviour changes completely:

    lfq_any2any=0   yield=102784  waitSig=1    poll=0     draws 890 quads
    lfq_any2any=1   yield=15441   waitSig=656  poll=672   draws 126 quads

waitSig 1 -> 656 and poll 0 -> 672: it goes from parking once and never
returning to actively cycling. That task was dead for this entire effort.

DEFAULT OFF anyway: visible draws fall from ~890 to ~126 and the frame counter
stalls, so shipping it on would be shipping a regression. Neither setting
renders the scene. Default-off verified: ready=true, 880 quads.

`debug.rpcsx.thor.lfq_any2any=1` is the frontier. What is not yet right is that
only ONE push ever completes, so the consumer is woken once and then waits
again - the producer either stops or blocks. Whether the SPU side agrees with
the push3/pop3 field choice is the open question, and it is answerable: the
consumer is real guest SPU code, so if it advances pop3.m_h1 the choice is
right, and if it advances something else the ring layout needs correcting.
