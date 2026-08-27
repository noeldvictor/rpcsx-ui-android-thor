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

## The LFQueue is a control path, not the data path

With lfq_any2any=1 the ring probe fires exactly ONCE per run:

    LFQRING #0: pop3{h1=0 h2=0} push3{h5=0 h6=0}
                raw0=00000000 raw4=00010000 raw8=00000000 rawC=00000000

One GetPushPointer2 call in the whole run. So the producer is not looping and
the push3/pop3 field choice is not what limits it - the title pushes a single
control entry, the consumer is woken once (rc=0) and then runs its own loop.
That closes the "is the ring layout right" question: it does not matter yet.

Screenshot with the wake enabled: still flat green, internal FPS 30.00,
SPU 67.7%, RSX 6.5%, frames advancing past 1821. The task is awake and the
scene is still not drawn.

## All four combinations, measured

    attr_fix=0 lfq=0   ready=true   ~880 quads, 0 triangles   (shipped default)
    attr_fix=0 lfq=1   ready=true   ~126 quads, 0 triangles
    attr_fix=1 lfq=0   ready varies 0 draws, deadlocks
    attr_fix=1 lfq=1   ready=false  0 draws, 3 tasksets start, no wake

Both fixes are individually correct and each unblocks a different half of the
chain - attr_fix creates the third taskset, lfq delivers the wake - but neither
alone nor both together produce a triangle draw. Both ship OFF.

## What the green screen probably is

The title opens /dev_bdvd/PS3_GAME/USRDIR/TransGame/Movies/TF_LoadingScreen.bik
and decodes Bink on the SPUs (cellVdec is never called, which is why
thor_sample's movie guard is blind here). Under LLE the geometry burst is 73
draws / 1.31M vertices ONCE at flips 600-720 and then a single blit quad per
flip forever - consistent with a loading screen that is rendered once and then
presented. Under HLE that burst never happens and the screen stays at the clear
colour.

So the missing work is most likely the SPU task that decodes/loads the loading
screen, and the title does not advance past it. That is consistent with every
measurement here: SPU ~65% busy producing nothing, RSX ~6%, main loop at a
locked 30, and a draw stream that contains only the blit.

## CORRECTION: the burst is not a 1.31M-vertex mesh

The per-primitive histogram accumulates `get_elements_count()`, and for indexed
draws that sum is not a vertex count. Logging the burst itself:

    GEOM prim=5 elems=45 vtxbase=0x0 cmd=3 idx=0 c0=[0 0 3f7fbe77 3f800000]
    GEOM prim=5 elems=21 ...  elems=21, 30, 30, 12, 30, 36 ...

They are 73 SMALL INDEXED triangle draws (cmd=3), a dozen to a few dozen
elements each - ordinary scene geometry, not one enormous mesh. The
"1,310,328 vertices" figure quoted in the earlier entries is an accumulator
artefact and should not be used.

## Where the title actually stops - it never reaches the movie

thor_sample refused a measurement under LLE with "a movie is playing", which
contradicted the advice string this title normally shows
("unknown-this-title-never-calls-cellVdec"). That advice is about cellVdec; the
probe also detects an OPEN video file, and under LLE:

    LLE   videoDecoding=true  videoFilesOpen=1  source=open-video-file
          videoFile=/dev_bdvd/PS3_GAME/USRDIR/TransGame/Movies/FMV_intro.bik

    HLE   videoDecoding=false videoFilesOpen=0  source=none  videoFile=""

LLE is playing the intro FMV. HLE never opens any video file at all, so it is
stuck EARLIER than the loading screen hypothesis assumed - before the intro.

With lfq_any2any=1 the title does get further into that sequence: it starts
probing the localised movie variants, which it does not do otherwise -

    TF_InitialStartup.bik, _INT, _PS3, _PS3_INT, _PS3_int, _int
    TF_LoadingScreen_INT, _PS3, _PS3_INT, _PS3_int, _int

- but still opens none of them. So the wake advances the state machine and does
not complete it.

The right success metric from here is NOT the quad count. It is whether the
title opens a video file, which is a single unambiguous bit and is what
separates the two configurations.

## Two hybrid modes tried and eliminated - do not re-attempt

`debug.rpcsx.thor.real_spu_kernel=1` loads the REAL SPURS SPU kernel image
while the PPU side stays HLE. It was the obvious untried lever: if the genuine
SPU kernel drives the taskset, the geometry should follow.

    hle_libs=libsre.sprx hle_spurs_kernel=1 real_spu_kernel=1
      -> ready=false, fps 0.0, draw_calls=0, no video file

    hle_libs=libsre.sprx hle_spurs_kernel=0 real_spu_kernel=1
      -> ready=false, fps 0.0, flips reach 5640, draw_calls=0, no video file

The second is notable: the RSX flips thousands of times while issuing ZERO
draws, so the loop runs and nothing is ever submitted. Neither hybrid is closer
than the shipped default and both are eliminated.

Baseline restored and verified after the experiments: ready=true, 883 quads.

## Standing summary of the shipped state

Shipped ON (measured, keep):
  pending_contention_fix     the poll branch's pending leak
  contention_orphan_fix      slots orphaned across a wklCurrentId change

Shipped OFF (correct in isolation, each regresses something):
  task_attr_fix              unaligned ls_pattern/argument rejected, pattern
                             synthesised to fit the context. Creates the third
                             taskset; deadlocks.
  lfq_any2any                ANY2ANY LFQueue push + SPURS wake. Wakes the task
                             that was dead all session (rc=0, waitSig 1 -> 656)
                             and advances the movie state machine; draws fall.

Eliminated: real_spu_kernel (both variants), and every counter-leak theory for
the cont=1/holders=0x01 signature.

## Cross-title reference: attempted, INCONCLUSIVE

A title that renders under HLE SPURS would give something to diff against
instead of deriving everything from scratch. Eleven other ISOs are on the
device. Dragon's Crown was tried with the same HLE config:

    thor_boot -> booted=true, then pid=null, no RPCSX.log written at all

The emulator never began emulation, so this says nothing about HLE SPURS - the
boot path here (THOR_DEBUG_BOOT with an iso path) is tuned for BLUS30357 and
other titles most likely need their game data installed first. Recorded as
INCONCLUSIVE, not as evidence either way.

## The sharpest single statement of the failure

Across every configuration tried, in the taskset syscall census:

    [0]exit=0

No SPURS task EVER exits. Not once, in any run, under any combination of
flags. A task exits when its work item completes, so nothing any task is asked
to do ever finishes - they poll, they yield, they wait for a signal, and they
are still doing that when the run is killed. That is one line and it covers
every symptom in this document: SPU ~65% busy producing nothing, RSX ~6%, no
triangle draw, no video file opened.

Anything that makes `exit` non-zero is progress. Anything that does not is not.

## THE TITLE SAYS WHAT IS WRONG - GCM heap assertion

Diffing the log message histogram (whole file, Thor probes excluded) between
the two configurations surfaced something no amount of SPURS probing did: under
HLE the title writes to sys_tty, and under LLE it does not. What it writes is
its own assertion:

    gcmx_cmd.h:55 GCMXIsHeapBlockAllocated(Block) -- assertion failed
    abort() is called from 0x1022ea4
                      from 0x00fde064
                      from 0x00a83ff8
                      from 0x00fdd908
                      from 0x00fde384
                      from 0x009e05b0
                      from 0x009f265c

Control: LLE has ZERO occurrences of GCMXIsHeapBlockAllocated and zero
occurrences of "assertion failed". HLE repeats this one continuously.

The title aborts because a GCM heap block is not allocated. Its graphics memory
allocator fails, so the draw is never issued - which is precisely the missing
triangle burst, and it is the title's own diagnosis rather than an inference
from counters.

### This closes the loop back to the fence

0x00fde064, 0x00fdd908 and 0x00fde384 sit immediately around 0x00fdcf60 - the
address the ppu_pc_census probe identified at the very start of this effort as
the two-counter spin main_thread sits in:

    lwz r29,-0x638c(r31); lwz r0,-0x6390(r31); cmpw cr7,r29,r0; bne cr7,-0x18

So that fence is not some unrelated wait: it is the GCM heap's wait for the RSX
to consume, inside the same allocator that then asserts. `done` never reaching
`target` and "heap block not allocated" are the same failure seen from two
sides. Blocks are never released, the heap exhausts, the allocation fails, and
the assert fires.

### Why this is the best handle yet

It is observable (a string in the log), it has a control (absent under LLE), it
has a PPU callstack, and it converts "no triangles are drawn" into "this
specific allocator call fails". Anything that removes this assertion is
progress; the draw census only reports the consequence.

## QUALIFICATION: the assertion is INTERMITTENT, and so is everything else

The GCMX assertion is real and its LLE control holds - LLE has never produced
one. But it does NOT fire on every HLE run. Immediately after finding it:

    lfq_any2any=0   ready=true  GCMX asserts=0  draw_calls=0
    lfq_any2any=1   ready=true  GCMX asserts=1  draw_calls=0

Zero and one, where an earlier HLE run repeated the assertion continuously -
and draw_calls=0 in both, from a configuration that produced 880 quads twenty
minutes earlier. So the previous entry overstated it: the assertion is the
title's diagnosis when it fires, not a constant.

### This is the real obstacle now

Run-to-run variance, at n=1, exceeds the effect size of every change measured
in this document:

    same build, same flags, boot to boot
      ready        true / false
      draw_calls   0 / 126 / 434 / 880 / 1121
      GCMX asserts 0 / 1 / many
      task starts  2 / 3 / 12
      tasksets     2 / 3

Every A/B in this file is n=1 or n=2 against that spread. The two contention
fixes are safe - they were confirmed by a state signature (rawCont/locC), not
by a count - but every conclusion drawn from a draw count or an assertion count
across single runs is weaker than it reads, including the four-way flag matrix.

The honest next objective is therefore NOT another fix. It is determinism:
until the same build and flags produce the same outcome, no experiment can
distinguish a real improvement from a lucky boot, and effort spent on fixes is
spent blind. A cheap first step is n>=5 per configuration on the two metrics
that are unambiguous - does it open a video file, does the assertion fire - and
recording the distribution rather than a single value.

## CORRECTION AGAIN: the baseline IS reproducible - the variance was mine

The previous entry called run-to-run variance the real obstacle. That was
substantially wrong, and the cause was my own measurement.

`thor_setprop` with an empty value does NOT clear a property here. Reading the
device back:

    hle_libs = 'libsre.sprx'      <- after "clearing" it
    hle_spurs_kernel = '1'

So several runs I labelled LLE were HLE, and some A/B pairs differed by less
than I thought. Clearing has to go through adb directly:

    setprop debug.rpcsx.thor.hle_libs ""

With the two configurations set EXPLICITLY and verified by reading the props
back, the contrast is exact and stable:

    HLE   p8=1003 / 1033 / 1007      p5=0   (three consecutive runs)
    LLE   p8=1013  p6=1              p5=73

The quad count is the SAME in both, ~1000. The entire difference between a
rendering emulator and a green screen is the 73 p5 draws. Nothing else in the
draw stream differs.

### The test to use from here

    Under HLE, does p5 exceed 0?

One number, reproducible over three runs, with a control that always shows 73.
It needs `debug.rpcsx.thor.draw_census=1` and it needs the props verified with
getprop, not assumed. Draw totals, quad counts, fps and assertion counts are
all worse tests: they move for reasons unrelated to the geometry.

(The e= sums beside p5 are still not vertex counts - 73 indexed draws of 12-45
elements cannot sum to 1310328. Use the draw COUNT, not the element sum.)

## THE GCM HEAP STOPS GROWING - measured, with both configs verified

Using the p5 test and reading the props back on every run:

    LLE   18 sys_rsx_context_iomap   p5=73
    HLE   10 sys_rsx_context_iomap   p5=0

The title maps its GCM heap into RSX IO space one 1 MB block at a time, and the
sequences diverge at a single point:

    LLE   io=0x300000 0x400000 0x500000 0x600000 0x700000 0x800000
          0x900000 0xa00000 0xb00000 0xc00000     (ea 0x40000000..0x40900000)

    HLE   io=0x300000 0x400000 0x500000 0x600000  (ea 0x40000000..0x40300000)
          then nothing - only repeat remaps of 0x500000/0x600000

HLE's heap stops growing after FOUR blocks; LLE grows to TEN. Both share the
identical first four and the identical io=0x0/0xe000000 maps, so this is not a
different layout - it is the same allocator stopping early.

That IS "GCMXIsHeapBlockAllocated(Block) -- assertion failed": the heap runs out
of blocks, the next allocation has nothing to hand back, and the geometry draw
that needed the block is skipped. Quads keep working because they are already
resident; only new geometry needs a fresh block.

The repeated "RSX is not idle while mapping io" warnings appear in BOTH configs,
so they are not the discriminator.

### What this does and does not establish

It is the tightest causal link found so far, and it connects three previously
separate observations into one: the fence at 0x00fdcf60 (the heap waiting for
the RSX), the GCMX assertion (the heap failing to allocate), and p5=0 (the draw
that needed the block).

It does NOT yet say WHY the heap stops. Blocks are freed when the RSX finishes
with them, so a heap that stops growing is consistent with blocks never being
returned - which points back at completion signalling, where exit=0 already
says no SPURS task ever finishes its work item. The next question is narrow and
concrete: what frees a GCM heap block, and is that path reached under HLE?

## Both flagged fixes RE-TESTED on the p5 metric - neither helps, one hurts

Every earlier flag comparison used thor_setprop with empty values, which does
not clear a property, so those A/Bs are unreliable. Re-run with props set via
adb and read back, scored on iomaps and p5:

    baseline        ready=true   iomaps=10   p8~1000   p5=0
    task_attr_fix=1 ready=false  iomaps=6    (no draws)
    lfq_any2any=1   ready=true   iomaps=10   p8=1110   p5=0
    both            ready=false  iomaps=6    (no draws)

lfq_any2any changes NOTHING on the metric that matters - same 10 iomaps, same
p5=0. task_attr_fix makes it WORSE: the heap reaches 6 maps instead of 10.

So the earlier characterisation of these two as "each correct, each unblocking
half the chain" does not survive measurement. They are:

  - task_attr_fix   a genuine argument-validation bug fix that REGRESSES this
                    title's heap growth. Keep the code, keep it OFF, and do not
                    describe it as progress.
  - lfq_any2any     implements a real unimplemented firmware path and wakes a
                    task that was otherwise dead, but has NO effect on heap
                    growth or geometry. Interesting, not useful here.

The only changes in this effort that survive scrutiny are the two contention
fixes, which were confirmed by a state signature rather than a count.

## SECOND TITLE: HLE SPURS fails systemically, not per-title

Eternal Sonata (USA), same build, props verified both ways:

    LLE         p1=128  p6=17682  p8=688     iomaps=2    renders
    HLE SPURS   0 draws                      iomaps=0    nothing

It boots under HLE (pid alive, 120 flips) and draws NOTHING - not even the
quads BLUS30357 still manages. So HLE SPURS is not failing on a Transformers
-specific path; it fails on an unrelated title just as completely, and worse.

That reframes twelve rounds of this document. The contention leaks, the task
attribute validation, the ANY2ANY LFQueue - all real bugs, none of them the
reason HLE does not render, because the failure is not title-specific.

(Dragon's Crown would not boot at all - it needs game data installed - so it
remains inconclusive. Eternal Sonata is the usable second data point.)

## What upstream says, and it matches

RPCS3 has no working HLE cellSpurs. The taskset and event-flag submodules are
incomplete and were DISABLED upstream to prevent regressions, the SPURS kernel
is disabled, and the project's own guidance is that libsre and libspurs_jq must
be LLE for every title. "Working HLE CellSpurs implementation" exists upstream
only as a feature request (RPCS3 issue #9063), opened with no description.

So "fix HLE SPURS for BLUS30357" is really "finish an HLE cellSpurs that
upstream has never finished". That is the honest scope, and it explains the
shape of this entire document - every fix exposed another missing behaviour
because most of the behaviour is missing.

## Upstream sync, 2026-08-27

    RPCS3   27 new commits, NONE touching cellSpurs / cellSync / cellGcm
    RPCSX   0 new commits
    ARMSX3  60 new commits; one relevant:
            a7ec28f7a "SPU: always notify reservation waiters after a
            successful store" - removes the pc==0x11e4 / byte-0x73 suppression
            because those constants assume one SPURS kernel build.

We already carry that behaviour behind `debug.rpcsx.thor.spurs_always_notify`,
default off, from a 2026-08-24 investigation. Tested it here under HLE:

    spurs_always_notify=1   ready=true   p8=1242   p5=0   iomaps=9

No effect on the geometry. Eliminated for this failure.

## Two more configurations eliminated, and what the firmware actually contains

    hle_libs="libsre.sprx,libspurs_jq.sprx"   ready=true  p8=1133  p5=0  iomaps=8
    spurs_always_notify=1                     ready=true  p8=1242  p5=0  iomaps=9

Neither produces a triangle. Adding the job-queue module does not help and
slightly reduces heap growth.

### What is inside the decrypted libsre (dec_04.elf, 239344 bytes)

Container is PPC64. It embeds exactly TWO SPU ELF images:

    off=0x020480  SPU  entry=0x00818  PT_LOAD vaddr=0x100 size=0x780
    off=0x020d00  SPU  entry=0x00848  PT_LOAD vaddr=0x100 size=0x790

These are the SPURS KERNELS - kernel1 and kernel2 - and they confirm the
constants this effort has been using: they load at LS 0x100 and their entries
sit beside exitToKernelAddr=0x808. Extracted as real_spu_kernel1.elf and
real_spu_kernel2.elf for disassembly.

The TASKSET POLICY MODULE is NOT in this file. A heuristic scan of everything
after the kernels for SPU instruction density found nothing above noise, so the
0x1E40-byte taskset PM that `_spurs::create_taskset` stages at
SPURS_IMG_ADDR_TASKSET_PM comes from somewhere else - another module, or a
compressed section. Finding it is the prerequisite for comparing our HLE
taskset against the real one, which is where `exit=0` (no task ever finishes)
would finally have a reference to be checked against.
