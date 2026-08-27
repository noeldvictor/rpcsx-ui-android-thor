# HLE SPURS: what the outside world knows

Date: 2026-08-27
Companion to 20260827-hle-spurs-pending-contention-leak.md, which is the
measurement log. This file is the research.

## 1. Upstream RPCS3 has never made HLE cellSpurs work

- The SPURS taskset and event-flag submodules are INCOMPLETE and were
  deliberately DISABLED upstream to prevent regressions. The cellSpurs kernel
  is disabled.
- RPCS3's own guidance is that `libsre.sprx` and `libspurs_jq.sprx` must be
  LLE for every title.
- "Working HLE CellSpurs implementation" exists upstream only as a feature
  request (issue #9063), opened by elad335 with NO description.
- Issue #1294 ("Improve and implement more cellSpurs* functions") is a request,
  not an analysis: it names no functions and gives no blockers.

Implication: there is no upstream reference implementation to diff against,
and no upstream account of what is missing. Everything here is first-party.

## 2. An independent project concluded HLE stubs CANNOT do this

sp00nznet/ps3recomp (static recompilation of PS3 titles) reports:

  - The real SPURS kernel dispatches through OPD function pointers, TOC
    references and vtable-style dispatch. These "don't translate cleanly to C
    function stubs" because the kernel READS OPDs FROM MEMORY to invoke policy
    modules and job payloads, which needs pointer-following semantics an HLE
    stub cannot reproduce faithfully.
  - Multiple SPU images (kernel, policy, job) COEXIST AT OVERLAPPING LOCAL
    STORE ADDRESSES and communicate by channel operations.
  - Their fix was NOT to finish the HLE. It was "static firmware LLE":
    relocate a decrypted PRX and lift the real libsre module into native code,
    so kernel entry, workload dispatch and completion signalling are all real
    code with real pointer semantics.
  - Even there, the LLE libsre SPU-kernel path "currently only comes up in
    Debug builds".

This is the most decision-relevant finding in this document. A second team hit
the same wall and judged HLE-ing the SPURS kernel to be the wrong shape of
solution, not merely unfinished.

It also matches what is measured here: under HLE, LS 0xA00 (the policy module)
is entirely zero and LS 0x100 holds 64 nonzero bytes against LLE's 659. The SPU
has no kernel and no policy code resident - only data - so every address a task
or kernel branches to must be individually intercepted.

## 3. Sony's own patents are a real specification source

  US 7979680, US 7647483  "Multi-threaded parallel processor methods and
                           apparatus"
  US 8589943, US 9870252  "Multi-threaded processing with reduced context
                           switching"

They describe, in prose rather than pseudocode:
  - The kernel is ~2 KB of the 256 KB local store, matching the 0x780/0x790
    PT_LOAD sizes measured in the real kernels extracted from dec_04.elf.
  - Gang-scheduled (constant-size) vs individually scheduled (variable-size)
    thread groups.
  - A yield that skips the context save when the thread can finish, save what
    it needs, or drop a mutex within its wait-time attribute TW; otherwise
    forced preemption WITH a context save.
  - Preemption notification by callback carrying TW, then a timer.
  - Context save = registers + program counter + OS data, and the observation
    that applications often keep their state in main memory already, which
    makes the OS-level save redundant.

No explicit policy-module state machine is given, so these bound the design
without settling the exit path.

## 4. What our interception already does correctly

  0x818 / 0x848  kernel entry (CELL_SPURS_KERNEL1/2_ENTRY_ADDR)
  0x808          exitToKernelAddr
  0x290          selectWorkloadAddr
  0xA00          policy module entry - sys service / taskset / job chain
  0xA70          CELL_SPURS_TASKSET_PM_SYSCALL_ADDR, the address tasks BRANCH
                 TO for a syscall

The 0xA70 registration was a prior fix here: without it the SPU executes zeros
about 20 ms after the taskset first dispatches. The non-sentinel branch
unregisters 0xA00 and copies the real module in, because a stale registration
from a previous workload otherwise shadows a real image.

So the trap mechanism is in place and is not the gap.

## 5. AArch64 / AYN Thor angle

Already established in this tree and unchanged by this research:
  - The reservation path used on ARM64 does `res -= 1` on the declined path;
    the missing decrement is in the x86 TSX path, which never executes here.
  - ARMSX3 a7ec28f7a removes an upstream optimisation that suppresses
    reservation wakeups at pc 0x11e4 on the SPURS control line. We already
    carry that behind debug.rpcsx.thor.spurs_always_notify. Tested this session
    under HLE: p8=1242, p5=0 - no effect on geometry.

## Sources

  https://github.com/RPCS3/rpcs3/issues/9063
  https://github.com/RPCS3/rpcs3/issues/1294
  https://github.com/RPCS3/rpcs3/pull/1001/files
  https://github.com/sp00nznet/ps3recomp
  https://github.com/sp00nznet/flow
  https://patents.google.com/patent/US8589943B2/en
  https://forums.rpcs3.net/archive/index.php/thread-176433.html

## 6. Solving the capture problem: PM capture that runs under LLE

The blocker named at the end of the measurement log was that the taskset policy
module cannot be captured, because every dump facility in this tree lives in
the HLE syscall path and does not execute under LLE.

`do_dma_transfer` in SPUThread.cpp runs for every MFC transfer in BOTH
configurations, so the capture belongs there. Added behind
`debug.rpcsx.thor.pm_capture=1`: sample LS 0xA00 every 32 DMAs, hash the first
16 bytes, and write the whole local store once per distinct module.

It works. Under LLE it captured TWO distinct resident policy modules:

    sig=c1238aa09808cb38  first16=4306dc024322b682   = sig_b, jobchain B
    sig=d8a3c3fb5c262dde  first16=4363de0243d9da82   = NEW, not in the table

The second matches none of the three signatures in thor_jobchain_pm_image
(sig_a 42377002, sig_b 4306dc02, sig_c 436e8402). Its prologue has the same
shape as the others - four `ila`-form constants - so it is a policy module.

### It is NOT confirmed to be the taskset PM

The obvious test failed. CELL_SPURS_TASKSET_PM_SYSCALL_ADDR is 0xA70, so the
taskset PM must have its syscall entry there. Disassembled, the candidate's
0xA70 is a DMA setup and tag wait:

    wrch r13,ch18 / r12,ch19 / r11,ch20 / r10,ch21 / r6,ch22 / r4,ch23
    rdch r2,ch24 ; sync 0x2

MFC_EAL / Size / TagID / Cmd / WrTagMask / WrTagUpdate then RdTagStat - a DMA
and a wait, not a syscall dispatch. So the candidate is a third policy module of
some kind, not identified.

Extent could not be settled either: walking forward from 0xA00 to a zero run
gives 0xa700, which is task code and data past the module, not the module size.
Module size has to come from the workload's declared pm_size, which the capture
does not record.

### What the capture facility still needs

Record the workload's pm_size and image address alongside the bytes, so a
capture is self-identifying instead of needing to be recognised afterwards.
That is a small change to the same hook and it is the difference between "we
have some modules" and "we have the taskset PM".

Captures kept in _research/spurs/pm_captures/.

## 7. THE TASKSET POLICY MODULE, IDENTIFIED

Making the capture self-identifying settled it. The kernel context names the
workload it is running (0x1D0 wklCurrentAddr, 0x1D8 wklCurrentUniqueId,
0x1DC wklCurrentId), so recording those with the bytes gives:

    4306dc024322b682   wklCurrentAddr=0x022b3680  wklId=1  spu=4
    4363de0243d9da82   wklCurrentAddr=0x02317200  wklId=2  spu=3

Two workloads, two distinct policy modules. The decisive test is
CELL_SPURS_TASKSET_PM_SYSCALL_ADDR = 0xA70: the taskset PM MUST have its
syscall entry there, at module offset 0x70.

    4363de02 at 0xA70:  wrch ch18/19/20/21/22/23, rdch ch24, sync
                        - a DMA and a tag wait. NOT a syscall entry.

    4306dc02 at 0xA70:  stqa sp,0x2c90
                        stqa r80,0x2ca0
                        stqa r81,0x2cb0
                        stqa r82..r92 -> 0x2cc0..0x2d60

A register-save sequence writing sp and the callee-saved registers into
0x2c90+, which is inside the taskset management area (SpursTasksetContext at
0x2700, fields through 0x2FD4) and OUTSIDE the module image itself (0xA00 +
0x1E40 = 0x2840). Saving the task's context before entering policy logic is
exactly what a taskset syscall entry does, and nothing else would write there.

**4306dc02 is the taskset policy module.** Extracted at its declared pm_size:

    _research/spurs/real_taskset_pm.bin              0x1E40 bytes
    _research/spurs/real_taskset_pm_syscall.disasm.txt

### This corrects the signature table in the tree

thor_jobchain_pm_image lists sig_b = 43 06 dc 02 43 22 b6 82 as a JOB CHAIN
policy module candidate. It is not - it is the taskset PM. That explains the
measurement already recorded in the log: "Module B: halted all SPUs (HLGTI at
pc=0x00f00)". Feeding the taskset PM to a job chain workload would do exactly
that. Variant B should be removed from that table, not merely left unselected.

### What this unblocks

exit=0 - no SPURS task ever finishing, on either title, in any configuration -
now has a reference. The task-exit path is in this 0x1E40-byte image, reachable
from the syscall entry at offset 0x70, and it can be read against
spursTasksetProcessSyscall's CELL_SPURS_TASK_SYSCALL_EXIT arm instead of
inferred from HLE-side probes.

## 8. The taskset syscall handler is at 0x1c58

Reading the taskset PM from its syscall entry, the whole wrapper resolves:

    0xa70   stqa sp,0x2c90
            stqa r80..r127 -> 0x2ca0..0x2f90      full callee-saved set
    0xb50   stqd lr,0x0(sp)
            stqd sp,-0x20(sp) ; ai sp,sp,-0x20
    0xb5c   brsl lr,0x00001c58                    <-- THE SYSCALL HANDLER
    0xb60   lqa lr,0x2c80
            lqa sp,0x2c90
    0xb6c+  lqa r80..r127 <- 0x2ca0..0x2f90       restore
            return to the task

So 0xA70 is only a save/call/restore shell. The syscall itself - EXIT, YIELD,
WAIT_SIGNAL, POLL, RECV_WKL_FLAG - is implemented at **0x1c58**, module offset
0x1258. That is the direct counterpart to spursTasksetProcessSyscall in
cellSpursSpu.cpp.

Two things follow immediately.

The save area is 0x2c80..0x2f90, which sits between SpursTasksetContext (0x2700)
and its x2FC0/x2FD4 fields. Our HLE never writes that region, and does not need
to: a C++ handler does not clobber the task's SPU registers the way a real
module does. So the absence of that save in HLE is correct, not a defect - one
more thing that does not need investigating.

The handler being a single function at a fixed offset means the exit path is
now a bounded read: 0x1c58 against spursTasksetProcessSyscall's
CELL_SPURS_TASK_SYSCALL_EXIT arm, with exit=0 as the thing to explain.

Saved as _research/spurs/real_taskset_pm_wrapper.disasm.txt.

## 9. The syscall dispatch, read - and one real discrepancy found

The handler at 0x1c58 is a jump table:

    00001c78: brz  r2,0x00001c84      ; version flag decides
    00001c7c: andi r5,r3,0xf          ; syscallNum & 0xF  - same mask we use
    00001c84: il   r4,-0x1
    00001c88: il   r3,0x2
    00001c8c: wrch r4,ch22            ; MFC_WrTagMask  = -1
    00001c90: wrch r3,ch23            ; MFC_WrTagUpdate = 2
    00001c94: rdch r2,ch24            ; MFC_RdTagStat - WAIT FOR ALL DMA
    00001c98: shli r10,r5,0x2
    00001c9c: ila  r11,0x1cc4         ; jump table base
    00001ca0: clgti r5,r5,0x4         ; > 4 -> error
    00001cb0: iohl r6,0x903           ; 0x80410903, the NOSYS code
    00001cc0: bi   r2

    table @ 0x1cc4:  0x1cd8 EXIT   0x1d34 YIELD   0x1d80 WAIT_SIGNAL
                     0x1db8 POLL   ...  RECV_WKL_FLAG

Confirms three things our HLE already does: the & 0xF mask, the >4 bound with
an error return, and five implemented syscalls.

### The discrepancy

The firmware DRAINS ALL OUTSTANDING DMA before dispatching. Our copy has the
identical structure - the `(syscallNum & 0x10) == 0` guard is the same version
test - but the call inside it was left commented out:

    if ((syscallNum & 0x10) == 0)
    {
        // spursDmaWaitForCompletion(spu, 0xFFFFFFFF);
    }

So a syscall was serviced while the task's DMA could still be in flight.
Enabled behind debug.rpcsx.thor.syscall_dma_wait, default ON, because it is
firmware-verified behaviour rather than a guess.

### It does NOT fix rendering

    syscall_dma_wait=1   ready=true  p8=1237  p5=0  exit=0  yield=132416

Identical to baseline on every metric that matters. A real correctness fix, and
not the cause. Kept on because it matches the firmware and costs nothing
measurable; recorded here so nobody re-derives it as a candidate.

The exit path itself is at 0x1cd8 and has not been read yet.

## 10. The EXIT arm, read - a real bug, and why it cannot be the cause

EXIT is jump-table entry 0, at 0x1cd8:

    00001cd8: lqr  r12,0x4be   -> 0x1cd8 + 0x4be*4 = 0x2FD0, word 1 = x2FD4
    00001ce0: ceqi r6,r7,0x4   ; x2FD4 == 4 - the same test our HLE uses
    00001ce4: brz  r6,0x1cfc
    00001cfc: il r3,0 / il r4,0 / fsmbi r5,0
    00001d08: brsl lr,0x00000e40    ; DESTROY - guarded by nothing
    00001d0c: lqr  r6,0x4ad   -> 0x1d0c + 0x4ad*4 = 0x2FC0, i.e. x2FC0
    00001d18: brz  r14,0x1e40      ; x2FC0 == 0 -> skip callback, END
    00001d2c: brsl lr,0x00001438   ; onTaskExit

The firmware destroys the task whenever x2FD4 != 4, and only then asks whether
an exit callback exists. Ours wrapped both in one gate:

    if (x2FD4 == 4 || x2FC0 != 0) { if (x2FD4 != 4) destroy; onTaskExit(); }

so a task exiting with x2FD4 != 4 AND x2FC0 == 0 was never destroyed - it stays
set in the taskset's running/enabled bitmaps and its slot is never reusable.
Fixed behind debug.rpcsx.thor.exit_destroy_fix, default ON.

### It is dormant, and that matters more than the fix

    exit=0  yield=138624  waitSig=1  poll=0     p8=1243  p5=0

exit is still ZERO. The EXIT arm never executes, so this fix cannot currently
change anything, and it did not: p5=0, unchanged. (Task starts read 11 against
an earlier 2, but attributing that to a code path that never runs would be
wrong - it is run variance or the DMA-wait change from the previous commit.)

### Reconsidering exit=0

This log has treated exit=0 as the smoking gun. Reading the firmware weakens
that. The task on taskset 0x10364100 is a queue consumer that polls and yields;
a service task that runs for the lifetime of the taskset never calls EXIT, and
its exit count being zero is then NORMAL rather than diagnostic. Nothing
measured here establishes that this title's tasks are supposed to exit.

So "make exit non-zero" should be retired as the success metric. p5 > 0 remains
the only one that is grounded.

## 11. YIELD and WAIT_SIGNAL, read - a live discrepancy, still no geometry

YIELD is table entry 1, at 0x1d34:

    00001d34: brsl lr,0x00001350   ; poll status          -> r80
    00001d44: il   r3,0x3
    00001d48: brsl lr,0x00000e40   ; ProcessRequest(POLL) -> r3
    00001d4c: andi r15,r80,0xff
    00001d50: or   r80,r15,r3      ; combine BOTH
    00001d54: brz  r80,0x00001e9c  ; neither wants the SPU -> fast return
    00001d58: brsl lr,0x000014d0   ; save task context
    00001d60: brnz r3,0x00001eb0   ; save failed -> error
    00001d64: il   r3,0x1
    00001d70: brsl lr,0x00000e40   ; ProcessRequest(YIELD_TASK)

WAIT_SIGNAL is entry 2, at 0x1d80: ProcessRequest(-1 = POLL_SIGNAL), then
save context, then ProcessRequest(2 = WAIT_SIGNAL) - the same order our HLE
uses.

Two things this confirms about our HLE: the fast return when neither the
workload nor another task wants the SPU is REAL firmware behaviour, not a Thor
invention (thor_yield_fast_path was right), and the WAIT_SIGNAL ordering is
correct.

### The discrepancy

There is no branch between 0x1d34 and 0x1d48. The firmware issues
ProcessRequest(POLL) every time, whatever the poll status returned. Ours
short-circuited it:

    const bool taskWantsSpu = wklWantsSpu ? false
        : spursTasksetProcessRequest(spu, SPURS_TASKSET_REQUEST_POLL, ...) != 0;

so whenever wklWantsSpu was true the request was never made - and
spursTasksetProcessRequest is not a pure query, it ends by writing the taskset
bitmaps back. A dropped write-back, on a path taken 138,624 times per run.

Fixed behind debug.rpcsx.thor.yield_poll_always, default ON.

### Result

    ready=true  p8=1245  p5=0  exit=0  yield=131456  waitSig=1

No change. Third firmware-verified fix in a row that is correct and does not
render.

### Standing tally of firmware-derived fixes

    syscall_dma_wait     drain DMA before dispatch        no effect on p5
    exit_destroy_fix     unconditional destroy on EXIT    dormant (exit=0)
    yield_poll_always    always issue ProcessRequest      no effect on p5

All three are real, all three match the firmware, none produces geometry. The
implication is that the taskset syscall path is not where the missing geometry
is lost - three of its five arms now match the reference and the picture is
unchanged.

## 12. Running the REAL taskset module under the HLE kernel - it does not mix

The three firmware-verified corrections to the stub all matched the reference
and none rendered, which argued the stub is not where the geometry is lost. The
test that follows from that, and from ps3recomp's conclusion, is to stop
stubbing the taskset and run the real module.

That is now possible because the module is identified. Implemented as
`thor_taskset_pm_image()`: open /dev_flash/sys/external/libsre.sprx, decrypt,
search for the taskset signature, stage 0x1E40 bytes with vm::alloc, and pass
that address to _cellSpursWorkloadAttributeInitialize instead of the
SPURS_IMG_ADDR_TASKSET_PM sentinel. cellSpursSpu.cpp then takes its default
branch, unregisters the 0xA00 stub and copies the image in.

It stages correctly:

    TASKSETPM: staged the REAL taskset policy module at 0x2310000
               (7744 bytes, found in libsre at 0x23780...)
    TASKSETPM: taskset 0x101b4e80 will run the REAL policy module at 0x2310000
    TASKSETPM: taskset 0x10364100 will run the REAL policy module at 0x2310000

And it does not work:

    ready=false   frames=0   coresBusy=6.12   draw_calls=0   no fatal error

Zero frames - worse than the stub, which at least reaches ~1000 quads. The SPUs
spin without faulting.

### Why this is informative rather than just a failure

A real policy module expects the REAL kernel's conventions - what is in which
register at entry, what exitToKernelAddr and selectWorkloadAddr point at, how
the kernel hands off and takes back control. Ours is an HLE kernel providing
Thor's conventions. Mixing one real image with an HLE kernel cannot work unless
those interfaces match exactly, and they evidently do not.

That is precisely ps3recomp's finding, reached here independently and by
measurement: lifting must be all-or-nothing. Their static firmware LLE lifts
the kernel AND the policy modules together, and even there the LLE SPU-kernel
path only comes up in Debug builds.

Kept behind debug.rpcsx.thor.real_taskset_pm, DEFAULT OFF, because it is a
strictly worse state than the stub. It is committed rather than discarded so
the next attempt starts from a working staging path instead of rebuilding it.
