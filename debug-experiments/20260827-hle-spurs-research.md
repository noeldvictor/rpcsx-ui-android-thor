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

## 13. The all-or-nothing lift, tried - it fails at the kernel stage

If a real policy module cannot run under an HLE kernel, the implied test is to
lift both together. Both pieces exist here: debug.rpcsx.thor.real_spu_kernel
stages the real SPURS kernel from libsre, and real_taskset_pm stages the real
taskset policy module. They had never been enabled at the same time.

    real_spu_kernel=1 real_taskset_pm=1 hle_spurs_kernel=1  ready=false draws=0
    real_spu_kernel=1 real_taskset_pm=1 hle_spurs_kernel=0  ready=false draws=0

The real kernel installs correctly:

    Thor KERNEL: real SPURS kernel1 installed (entry 0x818, 1920 bytes at
                 0x22b0000 -> LS 0x100)

1920 bytes matches the 0x780 PT_LOAD measured in the kernel extracted from
dec_04.elf, so the right image is going to the right place. And the title still
produces ZERO frames - it fails at the kernel stage, before the policy module
matters.

### The approach space, exhausted

    HLE stub + 3 firmware-verified fixes   ~1000 quads, p5=0   (shipped default)
    real taskset PM + HLE kernel           0 frames
    real kernel     + HLE taskset          0 frames
    real kernel     + real taskset PM      0 frames

Every combination available in this tree has been measured. The stub renders
the UI and no geometry; every path that introduces real firmware produces
nothing at all.

That is not a small gap to close. Making the real kernel work means the whole
SPU-side environment it expects has to be right - the kernel context it is
handed, the workload records it walks, the channel and DMA conventions, the
addresses it hands control back through. RPCS3 never finished that, ps3recomp
concluded a C stub cannot express it and lifted the firmware statically
instead, and this fork's real-kernel path does not boot the title.

## Conclusion for this effort

HLE SPURS does not render this title, or Eternal Sonata, in any configuration
reachable from this tree. The work that stands is:

  - two contention leaks fixed (shipped ON, took the title from parked at 0 fps
    to a running main loop at 30)
  - three firmware-verified taskset fixes (shipped ON, correct, none renders)
  - a test that cannot lie: p5 > 0, with a verified measurement procedure
  - the real taskset policy module identified, extracted and partly disassembled
  - a mislabeled signature corrected: sig_b is the taskset PM, not a job chain
    variant, which explains the recorded "Module B halted all SPUs"
  - an LLE-capable policy-module capture built from nothing
  - five configurations and both hybrids eliminated with measurements

For playing this title: use LLE. It renders.

## 14. WHY the real kernel produces zero frames - sentinels it cannot read

Diagnosed rather than assumed. Under real_spu_kernel=1 there are NO SPU faults
at all, and the PPU call histogram stops dead after taskset creation:

    3x cellSpursWorkloadAttributeInitialize   2x cellSpursCreateTasksetWithAttribute
    2x cellSpursWakeUp                        2x cellSpursSendWorkloadSignal
    (no cellSpursCreateTask, no queue push)

Earlier than the HLE stub gets, and without faulting. The cause is structural:

    SPURS_IMG_ADDR_SYS_SRV_WORKLOAD = 0x100
    SPURS_IMG_ADDR_TASKSET_PM       = 0x200
    SPURS_IMG_ADDR_JOBCHAIN_PM      = 0x300

These are SENTINELS. cellSpursSpu.cpp switches on them and substitutes an HLE
entry instead of loading an image. The REAL kernel knows nothing about that
convention - it treats wklInfo->addr as a guest address and DMAs the policy
module from it. create_spurs sets the sys-service workload image to the 0x100
sentinel (cellSpurs.cpp:1405), so the real kernel loads its housekeeping module
from guest address 0x100 and runs whatever is there.

That is why the real-kernel path produces zero frames and no fault: it is
executing garbage in the workload SPURS runs most.

### What this changes

"The lift does not work" was too strong. It is not that real firmware and this
emulator are incompatible - it is that the lift was PARTIAL in a way that
cannot work: every remaining sentinel is an address the real kernel will
happily read as a module.

A complete lift needs all three images real, with no sentinel left:

    sys service   NOT captured yet - this is the missing piece
    taskset PM    HAVE IT (real_taskset_pm.bin, identified by its 0xA70 entry)
    job chain PM  HAVE IT (thor_jobchain_pm_image, sig_a/b/c already in tree)

So the gap is one module. The capture facility built in section 6 can get it -
it samples LS 0xA00 on every 32nd DMA under LLE and writes each distinct
module once - but the sys-service workload has not appeared in a capture yet.
It is workload id 0x20, so a capture keyed on wklCurrentId==0x20 would isolate
it.

That is a bounded, concrete next step, and it is the first time in this
document that the real-firmware path has had one.

## Research, additional sources

RPCS3's actual working arrangement is PPU-side cellSpurs HLE plus real SPU-side
code from libsre - not the all-HLE path this effort has been building. The
description that matches everything measured here is that SPURS "is deeply
stateful, uses SPU mailboxes as semaphores, relies on precise timing between
the PPU and SPU scheduling loops, and uses Cell-specific atomic primitives with
no direct x86 equivalent", and that before it worked "any game leaning heavily
on SPURS would hang at startup or make it to gameplay and then crash in ways
that were essentially impossible to debug from the outside".

Sony's patents (US 7979680, 7647483, 8589943, 9870252) remain the only
specification-grade source. No arXiv paper covers SPURS scheduling; the
academic Cell literature is about SPE scheduling generally, not Sony's runtime.

_research_aps3e/ is an empty checkout (README and gradle.properties only), so
it offers no second implementation to compare against.

## 15. QUALIFYING section 14 - the sys-service sentinel story is NOT confirmed

Section 14 explained the real kernel's zero frames as: it DMAs the sys-service
policy module from the 0x100 sentinel and executes garbage. That mechanism is
NOT established, and the attempt to close the gap argues against it.

Hunted the sys-service module with the LLE capture at 4x the sampling rate
(every 8 DMAs) over 70 seconds:

    first16=4306dc024322b682  wklCurrentId=1   (taskset PM)
    first16=4363de0243d9da82  wklCurrentId=2

Still only two modules. No capture with wklCurrentId=0x20 (32), the sys-service
workload, ever appears - so under LLE the sys service does NOT load a separate
policy module into LS 0xA00 at all.

If it never loads one, the real kernel is not DMAing a module from 0x100 for
it, and the "executes garbage from address 0x100" mechanism is wrong. A more
likely reading is that 0x100 is meaningful to the real kernel - the kernel
itself is resident at LS 0x100 - and the sys service is handled inside the
kernel image rather than as a loadable module. That is a hypothesis too, and it
is not tested here.

What remains true from section 14 is only the measurement: under
real_spu_kernel=1 there are no SPU faults and the PPU stops after taskset
creation without ever calling cellSpursCreateTask. WHY it stops is still not
established.

The honest state of the real-firmware path: it fails, the failure is silent,
and the mechanism is unknown. It should not be described as "one module away".

## 16. Final configuration matrix, and no reference exists

One more combination, shaped like upstream's arrangement (upstream registers no
SPU-side HLE entries - both RegisterHleFunction calls are commented out there -
and always runs real images through the default branch):

    PPU HLE + real taskset module + NO SPU stubs (hle_spurs_kernel=0)
      -> ready=false, draw_calls=0

Complete matrix, every configuration reachable from this tree, all measured:

    HLE stub + 3 firmware-verified fixes        ~900-1250 quads, p5=0   SHIPPED
    real taskset PM + HLE kernel                 0 frames
    real kernel     + HLE taskset                0 frames
    real kernel     + real taskset PM            0 frames
    real taskset PM + no SPU stubs               0 draws
    real_spu_kernel both variants                0 draws
    lfq_any2any                                  p5=0
    task_attr_fix                                heap growth REGRESSES
    spurs_always_notify                          p5=0
    libspurs_jq added to hle_libs                p5=0

Default restored and verified after the sweep: ready=true, 913 quads.

### No working reference exists to copy

Searched for any emulator with functional HLE SPURS. There is none. aPS3e is an
RPCS3 port and inherits RPCS3's disabled implementation; RPCSX is a separate
Android fork with no claim to it; ps3recomp explicitly abandoned the HLE stub
approach for static firmware lifting. RPCS3 itself registers no SPU-side HLE
entries at all and runs real images.

This fork ENABLED those SPU-side HLE entries. That is the divergence from every
other project, and it is the thing that does not work.

## Closing state

HLE SPURS does not render Transformers (BLUS30357) or Eternal Sonata in any
configuration reachable from this tree. p5=0 throughout; LLE renders both.

Shipped and verified:
  - two contention leaks (0 fps and parked -> running main loop at 30 fps)
  - three firmware-verified taskset fixes: syscall_dma_wait, exit_destroy_fix,
    yield_poll_always

Built:
  - the p5 > 0 test and its measurement procedure (set props via adb, read back
    with getprop, draw_census=1)
  - an LLE-capable policy module capture (do_dma_transfer, pm_capture)
  - the taskset PM identified, extracted, disassembled; sig_b corrected from
    "job chain variant" to "taskset PM", which explains the recorded
    "Module B halted all SPUs"
  - a working Ghidra pipeline for SPU images, with the two traps written down
    (text dump not .bin; PowerShell exit 1 is cosmetic)

Unknown:
  - why the real-firmware path fails silently. No SPU fault, PPU stops after
    taskset creation. Mechanism not established - see section 15 for a
    hypothesis that was proposed and then argued against.

## 17. THE STRUCTURAL DIVERGENCE - HLE builds one more workload than LLE

Dumped the CellSpurs instance the PPU side builds, from do_dma_transfer so it
fires in BOTH modes, and diffed. Same instance address (0x1e97a80) both ways,
479 of 512 bytes identical - and the workload table is not:

    wklReadyCount1        LLE  00 01 00 ...    HLE  00 00 01 00 ...
    wklCurrentContention  LLE  00 01 00 ...    HLE  00 00 01 00 ...
    wklMinContention      LLE  01 08 00 ...    HLE  08 01 08 00 ...
    wklMaxContention      LLE  01 08 00 ...    HLE  08 05 01 00 ...
    wklStatus1            LLE  02 02 00 ...    HLE  02 02 02 00 ...
    wklEvent1             LLE  3f 3f 00 ...    HLE  3f 3f 3f 00 ...
    wklState2             LLE  c0 00 ff ff c0  HLE  e0 00 ff ff e0
    wklMskA               LLE  00 02           HLE  00 00

Read wklStatus1 and wklEvent1 as occupancy: LLE has TWO live workloads, HLE has
THREE. And wklMinContention is the giveaway - the LLE array 01 08 appears in
the HLE array shifted right, with an extra 08 prepended:

    LLE   [01] [08]
    HLE   [08] [01] [08]

So HLE inserts a workload at index 0 that LLE does not have, and every
workload the title creates afterwards lands at a DIFFERENT INDEX than it does
on the real runtime. The selector probes have been showing wkl0..wkl3 under HLE
against the two workloads LLE actually uses, and that was visible the whole
time without being recognised.

wklMskA differing (0x0002 vs 0x0000) is consistent: it is a workload bitmask,
and the bit set under LLE is for a workload that sits elsewhere under HLE.

### Why this matters more than anything else found

Every workload-indexed array in the SPURS instance - contention, priority,
ready counts, status, events - is addressed by workload id. If our ids are
offset by one relative to what the title's own data expects, then contention
accounting, priority selection and signalling are all operating on the wrong
slots, and no amount of correcting the taskset syscall path can fix that.

It also explains why three firmware-verified syscall fixes changed nothing:
they were correct, and they were being applied to a workload table that does
not line up with the title's.

### Not yet established

WHY the extra workload exists. Candidates: the sys-service workload being given
a normal slot under HLE when the real runtime keeps it out of band, or
cellSpursAddWorkload allocating from a different base. That is the next thing to
read, and it is a PPU-side question in cellSpurs.cpp, not an SPU one.

Structures kept in _research/spurs/spurs_structs/.

## 18. CORRECTION to section 17 - HLE builds FEWER workloads, not more

Section 17 concluded that HLE inserts an extra workload at index 0 and shifts
the title's workloads. That is WRONG, and the error was methodological: the
dump fired once, at the first capture opportunity, which is not the same moment
in an LLE run and an HLE run. It compared phases, not behaviour.

Re-dumped as a periodic late snapshot so both are at a comparable phase:

    wklStatus1  LLE  02 02 02 02 02 02 02 02 02 02      10 live workloads
                HLE  02 02 02                            3 live workloads

    wklMinContention  LLE  01 08 01 08 01 01 08 01 08 08
                      HLE  08 01 08

    wklMaxContention  LLE  01 08 05 01 06 06 06 05 01 01
                      HLE  08 05 01

The title's SPURS work is TEN workloads under the real runtime. HLE reaches
THREE and stops. The three it has line up with LLE's entries 1..3, so it is not
building a different table - it is building the same table and never getting
past the third entry.

### What this is and is not

It is a CONSEQUENCE, not a cause: the title stalls, so it never adds the
remaining seven workloads. It does not explain the stall.

But it is a far better progress metric than p5. p5 is binary - 0 or 73 - and
was insensitive to every fix tried. Workload count is GRADED: 3 of 10 says how
far the title gets, and any change that moves it to 4 or 5 is measurable
progress that p5 would not show at all. That is the first graded metric this
effort has had.

Both structures kept in _research/spurs/spurs_structs/ (late_lle.bin,
late_hle.bin) so the comparison can be redone without a device.

## 19. CORRECTION to section 18 - HLE adds NINE workloads, not three

Section 18 said HLE reaches three workloads against LLE's ten. That is also
wrong, and for the same class of reason: it was read from a SNAPSHOT. The
periodic dump overwrites one file, so once the title stalls the DMA traffic
that drives it stops and the file left behind is stale, not final.

Measured properly, by logging the event instead of sampling the state - a probe
in _spurs::add_workload prints every attempt:

    ADDWKL #0  wnum=0  pm=0x200      size=0x1e40  minC=8 maxC=8
    ADDWKL #1  wnum=1  pm=0x2347200  size=0x4000  minC=1 maxC=5
    ADDWKL #2  wnum=2  pm=0x200      size=0x1e40  minC=8 maxC=1
    ADDWKL #3  wnum=3  pm=0x2390000  size=0x4000  minC=1 maxC=6
    ADDWKL #4  wnum=4  pm=0x2390000  size=0x4000  minC=1 maxC=6
    ADDWKL #5  wnum=5  pm=0x200      size=0x1e40  minC=8 maxC=6
    ADDWKL #6  wnum=6  pm=0x2390000  size=0x4000  minC=1 maxC=5
    ADDWKL #7  wnum=7  pm=0x200      size=0x1e40  minC=8 maxC=1
    ADDWKL #8  wnum=8  pm=0x200      size=0x1e40  minC=8 maxC=1

NINE workloads, none refused, against LLE's ten live. Workload creation is NOT
the divergence, and both section 17 ("HLE builds one extra") and section 18
("HLE builds only three") are withdrawn.

### What the log does show

The split is legible: pm=0x200 is the TASKSET sentinel and pm=0x2347200 /
0x2390000 with size 0x4000 are real JOB CHAIN modules. So this title runs

    5 taskset workloads   (all sentinel-backed, all HLE-stubbed)
    4 job chain workloads (all real modules, loaded through the default branch)

That is worth knowing on its own: four of the nine workloads already run REAL
firmware today, through the default branch that copies the image into LS. Only
the taskset ones are stubbed.

### Methodological note, because this is the second one

Two consecutive conclusions were drawn from snapshots of shared state and both
were wrong. State sampling here is unreliable in a specific way: the sampler is
driven by DMA traffic, which stops exactly when the thing being investigated
goes wrong, so the last sample is systematically from before the failure. Event
logging does not have that failure mode. Prefer it.

## 20. Real modules DO run under the HLE kernel - correcting section 12

Section 12 concluded that a real policy module cannot run under an HLE kernel,
because staging the real taskset module gave zero frames. That reasoning was
wrong, and the ADDWKL log disproves it directly:

    ADDWKL #1 pm=0x2347200 size=0x4000     job chain, REAL module
    ADDWKL #3 pm=0x2390000 size=0x4000     job chain, REAL module
    ADDWKL #4 pm=0x2390000 size=0x4000     job chain, REAL module
    ADDWKL #6 pm=0x2390000 size=0x4000     job chain, REAL module

FOUR of this title's nine workloads already run real firmware under our HLE
kernel, every run, through the default branch that copies the image into local
store. Real modules and the HLE kernel are not incompatible. Section 12's
"mixing cannot work unless the interfaces match exactly, and they evidently do
not" is withdrawn - the interfaces evidently DO match for job chains.

### With real_taskset_pm=1 the real module executes, and gets further

Verified it is actually running rather than shadowed by the stub:

    ADDWKL taskset workloads now pm=0x2320000  (was the 0x200 sentinel)
    SYSCALL CENSUS: ABSENT                     (the HLE stub is not executing)

And the PPU reaches further than it does with the real KERNEL enabled:

    1x cellSpursCreateTask            2x cellSpursQueuePushBody
    2x cellSpursCreateTaskWithAttribute   4x cellSpursSendWorkloadSignal
    2x cellSpursCreateTasksetWithAttribute  6x cellSpursWakeUp

Tasks are created and the queue is pushed - neither happens on the real-kernel
path - and there are no SPU faults. But frames=0, against ~1000 quads for the
stub, so the RSX never flips at all. Something in the render path stalls before
the first flip.

### Standing state

    stub                    ready=true   ~1000 quads   p5=0
    real taskset module     ready=false  0 frames      tasks created, queue pushed

Neither renders. But the failure modes are different, and the real-module path
is the only one where the title creates tasks AND pushes its queue, which is
further into its own startup than anything else measured here.

## 21. The real-module path stalls on the SAME fence, far deeper in

With real_taskset_pm=1, main_thread parks on the 0x00fdcf60 GCM heap fence -
the same one identified at the very start of this effort - but the numbers are
completely different:

    stub                 done=0x304f920c target=0x304f9a74  delta=0x868
    real taskset module  done=0x303013a0 target=0x304f8048  delta=0x1f6ca8

The title has queued roughly 2 MB of command-buffer work and nothing drains it,
against ~2 KB queued on the stub path. So the real module lets the title get
dramatically further into its own startup - tasks created, queue pushed, 2 MB
of GCM work submitted - and then hits the same consumer stall.

That is the clearest statement of the failure this effort has produced:

    The producer works. The consumer does not.

The title fills its GCM command heap and the SPU side never consumes it, in
both configurations. The stub barely gets started before stalling; the real
module runs the whole producer side and stalls with the heap nearly full.

### What is NOT concluded

Which consumer, and why it does not drain, is not established. The selector is
still cycling (wkl0..wkl3 printing), so the SPUs are alive and not faulted. A
plausible reading is that the workload which consumes the command buffer is
never selected or never completes, but this document has been wrong four times
about mechanisms inferred from partial state, so it is left as a question.

The measurement stands on its own: delta 0x868 -> 0x1f6ca8 is a 240x increase
in queued-but-unconsumed work, and it is the largest movement any change in
this effort has produced.

## 22. THE CONSUMER IS STARVED - measured per workload, event-based

The producer fills the GCM heap and nothing drains it. The consumer is one of
the title's workloads, so count SELECTIONS per workload id in the selector -
event-based, because state sampling here is driven by DMA traffic that stops at
the failure.

Nine workloads created. Selections over a 30-second run:

    w0 = 4        w2 = 120001       w6 = 7
    w1, w3, w4, w5, w7, w8 = ZERO

Cross-referenced against what each workload IS, from the ADDWKL log:

    w0  pm=0x200      taskset (stub)       4 selections
    w1  pm=0x2347200  JOB CHAIN, real      0
    w2  pm=0x200      taskset (stub)       120001 selections
    w3  pm=0x2390000  JOB CHAIN, real      0
    w4  pm=0x2390000  JOB CHAIN, real      0
    w5  pm=0x200      taskset (stub)       0
    w6  pm=0x2390000  JOB CHAIN, real      7
    w7  pm=0x200      taskset (stub)       0
    w8  pm=0x200      taskset (stub)       0

THREE OF THE FOUR JOB CHAIN WORKLOADS ARE NEVER SELECTED, and the fourth runs
seven times in thirty seconds. One taskset takes 120,001 selections - better
than 99.99% of all scheduling - and that is the workload already known to sit
in a poll-and-yield loop consuming nothing.

Job chains are what drain a GCM command buffer. They are starved.

### Why this is the sharpest result here

It connects every earlier measurement into one mechanism instead of a list:

  - the GCM heap fills and never drains (delta 0x868 -> 0x1f6ca8)
  - because the workloads that consume it are never scheduled
  - while one polling taskset monopolises every SPU
  - which is why 138,624 yields go nowhere, why exit stays 0, and why three
    correct syscall fixes changed nothing - they were fixing the workload that
    runs, not the ones that do not

It is also the first finding that names something ACTIONABLE in our own code:
the selection gate, which this effort has already touched twice for contention.

### Not yet established

WHY they are starved. Candidates worth checking in order: the priority table
(the gate requires priority[i] != 0 per SPU, and a job chain with priority 0 on
every SPU can never be picked), the contention cap, or readyCount never being
raised for those workloads. All three are readable in the selector, and all
three are event-loggable rather than sampled.

## 23. CORRECTION to section 22 - the selector is NOT starving anything

Section 22 said the job chain workloads are starved by the selection gate. That
framing is wrong. Measured what the TITLE asks for:

    cellSpursSendWorkloadSignal  wid=0 -> 1     wid=2 -> 3686    wid=6 -> 1
    cellSpursReadyCountStore/Add -> NONE, for any workload
    signal rejections            -> 0

Against selections: w0=4, w2=120001, w6=7.

Selections track signals exactly. The workloads never selected - w1, w3, w4,
w5, w7, w8 - are the ones the title NEVER SIGNALS. Our selector is faithfully
scheduling what it is asked to schedule, and the gate is not at fault. Nothing
is being starved.

So section 22's "the consumer is starved" is withdrawn. The truth is narrower
and less convenient: the title creates four job chain workloads and then only
ever runs one of them, once.

### What that leaves

The title sets its job chains up and never dispatches work to them, which is
consistent with everything else here - it is stalled waiting on something and
never reaches the point of driving them. That makes this another CONSEQUENCE of
the stall rather than its cause, like the workload count and the GCM heap
before it.

Also worth recording: cellSpursReadyCountStore and cellSpursReadyCountAdd are
never called at all. Under LLE that cannot be compared, because the real libsre
services those calls instead of our HLE, so their absence here proves nothing
on its own.

### Where this leaves the effort

Four separate measurements - workload count, GCM heap delta, syscall census,
workload selections - have each turned out to be downstream of the stall rather
than the stall. Each looked like a cause when first measured. The pattern is
consistent enough to state plainly: this title's HLE failure presents as a
cascade, and nearly everything observable about it is an effect.

## 24. A bounded PPU call trace now targets the first divergence

The next question is earlier than SPURS selection: which `main_thread` HLE or
lv2 call differs before HLE enters the GCM fence wait. The existing
`ppu_thread::syscall_history` already records the function name, four arguments,
the return value, and the call address. It held one entry unless PPU call history
was enabled, and no diagnostic emitted it at a comparable point in both modes.

`debug.rpcsx.thor.ppu_call_trace=1` now enables the existing 2,048-entry history
on Android. The performance monitor emits it once, in oldest-to-newest order,
when the title creates `FlipPump`. This is a common milestone: the first device
capture created it at 11.073 seconds under HLE and 11.276 seconds under LLE.
The trace modes are `HLE_FLIP` and `LLE_FLIP`.

Each row starts with `Thor PPU CALL TRACE` and includes a sequence number. The
begin row records the mode, retained count, total index, and current PC. The
property also enables the existing PPU PC census, so one property is sufficient.
Normal runs retain the one-entry history and have no new per-call trace work.
The mode label comes from the effective `libsre.sprx:hle` library setting. It
does not infer the mode from the sampled PC because LLE also enters the fence
briefly and then passes it.

The monitor suspends the CPU threads only while it copies the diagnostic ring.
It writes the log after execution resumes. This prevents a concurrent ring
write from corrupting the evidence. The trace is keyed to the emulation run, so
an LLE boot and a later HLE boot in the same app process each get one trace.

Compare the two logs with this command:

    python -B tools/bench/compare_thor_ppu_call_trace.py HLE_LOG LLE_LOG

The tool requires the begin and end markers. It validates the row count and the
exact sequence-number range against the total index. This rejects a truncated
log before it can report a false divergence. It aligns the function names,
reports changed addresses, results, or arguments in the latest shared block,
and shows the first calls after that block. Its local self-test command is:

    python -B tools/bench/compare_thor_ppu_call_trace.py --self-test

ARM64 RelWithDebInfo verification passed:

    .\gradlew.bat ':app:buildCMakeRelWithDebInfo[arm64-v8a]'
    BUILD SUCCESSFUL in 42s

The first device round used exact Debug APK
`6935342F...BC59DD3B`. The no-launch install verified the same device hash. A
strictly cooled LLE boot emitted the old `LLE_BINK` trace with 2,048 rows and
total index 37,509. A separately cooled HLE boot reached a solid-green clear at
29.97 FPS, with no 3D geometry. It emitted no trace because the old exact-PC
HLE fence milestone was transient in this path. It therefore earns no speed or
correctness credit. The HLE main thread settled at `0x009e4ba4`, while both
modes created `FlipPump` at the nearly identical times above.

The first shared-event revision polled the live PPU thread list from the
performance monitor. Its exact APK `D994EA5E...A377CF7F0` passed a no-launch
device hash check. The cooled LLE boot did not emit a trace: LLE creates
`FlipPump` at 11.276 seconds and destroys it at 12.686 seconds, before the next
monitor scan. The run was stopped without an HLE arm. This is a sampling race,
not title evidence.

The tracer now emits directly inside `_sys_ppu_thread_create` when the decoded
name is exactly `FlipPump`. It records the creating main thread before that HLE
call returns, so both modes use the same event and no thread-lifetime polling.

The event revision used exact Debug APK
`147C6302...F23C`. The no-launch install verified the same hash on the Thor. A
strictly cooled LLE run recorded 275 calls at total index 275. A separately
cooled HLE run recorded 488 calls at total index 488. The captures are:

    20260827-2220-transformers-event-trace-lle/RPCSX.log
    20260827-2228-transformers-event-trace-hle/RPCSX.log

Both traces end with the same seven function names and the same final mutex
unlock. HLE reaches this event at 11.110 seconds. LLE reaches it at 11.144
seconds. Therefore, HLE has no measured wall-time loss before `FlipPump`.

The additional HLE rows are SPURS HLE calls and 30-microsecond guest waits.
For example, HLE has eight SPURS HLE calls and 74 waits between the two RSX
context writes at the end of this phase. LLE has one wait. This count is not a
performance fault because HLE still reaches the shared event first. It also
does not explain the missing 3D image, which occurs after this event.

The next common module loads are `SPUJobs.self`, `libnetctl.sprx`, and
`libnet.sprx`. HLE stops after `libnet.sprx`. LLE continues and loads
`libvoice.sprx` at 17.495 seconds. Trace property value 2 now captures the
useful boundary:

  - `HLE_STALL` records the first main-thread sleep at guest address
    `0x009e4ba4`.
  - `LLE_VOICE` records the LLE call history when `libvoice.sprx` loads.

Property value 1 continues to select the `FlipPump` trace. Each property value
emits only one trace in one run. This prevents two trace blocks in one log and
keeps truncated-log validation exact. The ARM64 RelWithDebInfo build passed in
2 minutes 59 seconds.

The first late LLE route used exact Debug APK `EF394328...DCB164`. The device
hash matched. Its three launch samples were 33.3, 33.7, and 33.7 C. Runtime
silicon stayed at or below 55.0 C. The route reached `libvoice.sprx` at 17.276
seconds, but it emitted no trace block. The capture is:

    20260827-225002-thor-input-custom/post-RPCSX.log

The device property still read `2` after the run. The APK native library also
contained `HLE_STALL` and `LLE_VOICE`. Therefore, the route and APK were
correct, but trace activation was not observable. The next revision removes
the process-lifetime property cache, logs one exact event row before the trace
guards, and records all HLE/SPURS trace properties in the guarded runner startup
profile. Do not run HLE until a cooled LLE route emits a complete block or gives
an exact skip reason.

The activation revision passed the ARM64 RelWithDebInfo build in 1 minute 35
seconds. Debug APK assembly passed in 57 seconds. The cache-route and cache-phase
pacing contract tests also passed. The exact Debug APK is
`E634031B...99B618`; its native library contains the event row and both late
trace labels.

The second cooled LLE route reached the helper at `libvoice.sprx` on
`main_thread`. The event row reported a 2,048-entry history, index 20,705,
property 2, and LLE mode. No block followed. All visible guards therefore
passed; the remaining deduplication guard compared the current emulation ID
with an atomic that started at zero. A first emulation can also have ID zero.
The capture is:

    20260827-230127-thor-input-custom/failure-RPCSX.log

The same revision logged 101,821 rejected HLE-stall events from `FlipPump` under
LLE. This logging raised the device to the guarded 57.4 C early stop. The next
revision initializes both deduplication atomics to `umax` and writes the event
row only after title, thread, trace-mode, and history eligibility checks. This
removes the zero-ID collision and the rejected-event log load.

The zero-ID revision passed the ARM64 RelWithDebInfo build in 58 seconds and
Debug APK assembly in 7 seconds. The exact APK is
`4C24C6B1...BC94E64D`; its native library contains both late trace labels and
the previous-emulation-ID event field.

### Correction: the formatted PPU name rejected the trace

The zero-ID conclusion above was premature. The activation event was written
before the thread-name guard, and it showed this value:

    thread=PPU[0x1000000] main_thread

`ppu.get_name()` returns that formatted debugger name. It does not return the
raw title name `main_thread`. Therefore, the equality guard rejected the valid
thread before the deduplication guard ran. Initializing the atomic to `umax` is
still correct for a valid zero emulation ID, but it was not the cause of the
missing block.

The exact `4C24C6B1...BC94E64D` LLE route confirmed this. Its managed profile
contained only `none:hle`, the startup property read 2, and it reached
`libvoice.sprx` at 17.049 seconds, but it wrote no event row after the name
guard. The capture is:

    20260827-232001-thor-input-custom/post-RPCSX.log

The guard now reads the raw `ppu_tname` pointer and requires that value to be
`main_thread`.

The raw-name revision passed the ARM64 RelWithDebInfo build in 57 seconds and
Debug APK assembly in 7 seconds. The exact APK is
`AF09CCD9...3C868783`.

The corrected LLE route used that exact APK and a verified device hash. Its
startup profile recorded `hle_libs=none`, `hle_spurs_kernel=0`, all other SPURS
experiment switches off, and `ppu_call_trace=2`. It emitted a complete
`LLE_VOICE` block at 17.315 seconds:

    count=2048 index=11919 sequence=9871..11918
    emulation_id=1 previous_emulation_id=18446744073709551615

The first and last retained calls are `sys_timer_usleep` at `0x009e4ba4` and
`cellPadGetInfo2` at `0x02006a74`. The package sensor peaked at 64.2 C, below
the 68 C immediate stop and 72 C hard limit. The capture is:

    20260827-233144-thor-input-custom/post-RPCSX.log

The separate HLE route used the same installed APK and verified hash. Its
startup profile recorded `hle_libs=libsre.sprx`, `hle_spurs_kernel=1`, all
other SPURS experiment switches off, and `ppu_call_trace=2`. It emitted a
complete `HLE_STALL` block at 13.110 seconds:

    count=2048 index=5724 sequence=3676..5723
    emulation_id=1 previous_emulation_id=18446744073709551615

The first and last retained calls are `sys_timer_usleep` at `0x00fdcf90` and
`sys_memory_allocate` at `0x009dc0dc`. The complete block was in the log before
the route reached the conservative 60 C sustained probe. The guard stopped the
app at a maximum package temperature of 63.4 C. This value is below the 68 C
immediate stop and the 72 C hard limit. The capture is:

    20260827-233623-thor-input-custom/failure-RPCSX.log

The HLE event was called again for each later sleep. The event row was before
the one-run guard, so the log contains 16,037 duplicate event rows. The guard
still emitted only one complete trace. The next revision puts the event row
after the one-run guard. It removes this diagnostic log load without a guest
behavior change.

The late traces do not contain a verified common boundary. A function-name
comparison found a six-call thread-start pattern near the end of both windows.
Only five call sites match, and all five rows use different results or
arguments. No complete call row matches. This repeated library pattern is not
evidence of the title divergence.

The comparator now reports function-name, call-site, and exact-call blocks
separately. It uses an exact-call block for context only when one exists. Its
self-test includes a repeated function sequence at different call sites. The
late pair reports no exact-call block. Therefore, both 2,048-entry late windows
start after the two modes have already diverged.

Both modes load `libnet.sprx` after the proven common `FlipPump` event. HLE
reaches the load at 12.060 seconds, and LLE reaches it at 11.864 seconds. A
trace at this same module-load event can bridge the known common event to the
late failure without an inferred library-thread anchor.

Property value 3 now captures this event as `HLE_NET` or `LLE_NET`. It uses one
separate run guard and emits only the active mode. Values 1 and 2 keep their
existing meanings.

The comparator self-test and `git diff --check` passed. The ARM64
RelWithDebInfo build passed in 2 minutes 51 seconds. Debug APK assembly passed
in 24 seconds. The exact Debug APK is `58D48B94...0934B3C`, and its size is
116,122,643 bytes. Its stripped ARM64 library contains both new mode labels.

The no-launch install succeeded, and the device-side APK hash matched the
exact local hash. The first property-value-3 route used LLE. Its startup
profile recorded `hle_libs=none`, `hle_spurs_kernel=0`, all other SPURS
experiment switches off, and `ppu_call_trace=3`. All three preflight silicon
samples were 33.3 C. The route emitted one complete `LLE_NET` block at 11.805
seconds:

    count=952 index=952 sequence=0..951
    emulation_id=1 previous_emulation_id=18446744073709551615

The first retained call is `sys_mutex_create` at `0x02224490`. The last call
is `_sys_prx_start_module` at `0x0223120c` for `libnetctl.sprx`. The block has
one event, one begin marker, and one end marker. Its history starts at sequence
zero, so it includes the proven `FlipPump` boundary.

The package sensor peaked at 59.8 C. The route completed below the 60 C
sustained probe, the 68 C immediate stop, and the 72 C hard limit. The runner
did not request its post snapshot. A direct ADB pull saved the unchanged remote
guest log after the verified force-stop and before any new launch. The capture
is:

    20260827-235306-thor-input-custom/post-RPCSX.log

The Thor must pass the same strict cool gate before the paired HLE route.

The Thor passed that gate. The paired route used the same installed APK and
verified hash. Its startup profile recorded `hle_libs=libsre.sprx`,
`hle_spurs_kernel=1`, all other SPURS experiment switches off, and
`ppu_call_trace=3`. It emitted one complete `HLE_NET` block at 12.072 seconds:

    count=948 index=948 sequence=0..947
    emulation_id=1 previous_emulation_id=18446744073709551615

The first retained call is the same `sys_mutex_create` call at `0x02224490`.
The last call is `_sys_prx_start_module` at `0x0223120c` for
`libnetctl.sprx`. The capture is:

    20260827-235726-thor-input-custom/failure-RPCSX.log

The complete trace ended before the route reached its thermal stop. The 60 C
sustained probe requested a confirmation sample. That sample was 70.3 C, at
or above the 68 C immediate stop and below the 72 C hard limit. The guard
force-stopped the app. No second launch is necessary for this boundary.

The paired traces contain the same final 666 function names from HLE sequence
282 and LLE sequence 286 through the `libnet.sprx` event. The last exact-call
block has 13 rows. The last call-site block has 17 rows, with four rows changed
only by allocated object or module IDs. For example, the `libnetctl.sprx`
module ID is `0x23006700` in HLE and `0x23006d00` in LLE.

The earlier differences are the expected implementation split. HLE records
the `cellSpurs` API calls, while LLE records the semaphore, SPU thread group,
SPU thread, event queue, and PPU helper-thread calls inside the real SPURS
module. After this initialization split, the title main thread has no function
flow divergence before `libnet.sprx`. Therefore, this boundary does not contain
the rendering fault.

Both modes later call `sys_timer_usleep` from title address `0x009e4ba4`. HLE
stays in this wait, while LLE passes it. The next shared trace must capture the
first call at this address in both modes. This moves the comparison after
`libnet.sprx` and directly before the observed forward-progress split.

Property value 4 now captures the first call as `HLE_WAIT` or `LLE_WAIT`. It
uses a separate one-run guard. Property value 2 keeps its existing HLE-only
late-boundary behavior.

The comparator self-test and `git diff --check` passed. The ARM64
RelWithDebInfo build passed in 2 minutes 54 seconds. Debug APK assembly passed
in 8 seconds. The exact Debug APK is `F5E6C10D...47B081DE`, and its size is
116,124,144 bytes. Its stripped ARM64 library contains both wait mode labels.

The no-launch install succeeded, and the device-side APK hash matched the
exact local hash. The first property-value-4 route used LLE. Its startup
profile recorded `hle_libs=none`, `hle_spurs_kernel=0`, all other SPURS
experiment switches off, and `ppu_call_trace=4`. It emitted one complete
`LLE_WAIT` block at 12.780 seconds:

    count=2048 index=8384 sequence=6336..8383
    emulation_id=1 previous_emulation_id=18446744073709551615

The first retained call is `sys_timer_usleep` at `0x00fdcf90`. The last call
is `sys_memory_allocate` at `0x009dc0dc`. The retained window contains 2,004
`sys_timer_usleep` calls. Of these calls, 1,997 are from `0x00fdcf90` and seven
are from `0x00fdcf60`. The window therefore shows that polling replaces almost
all earlier call history before the title reaches `0x009e4ba4`.

The package sensor peaked at 64.2 C. The sustained probe did not issue a stop,
and the route completed below the 68 C immediate stop and the 72 C hard limit.
The capture is:

    20260828-000644-thor-input-custom/post-RPCSX.log

The Thor must cool and pass the strict gate before the paired HLE route.

The Thor passed that gate. The paired route used the same installed APK and
verified hash. Its startup profile recorded `hle_libs=libsre.sprx`,
`hle_spurs_kernel=1`, all other SPURS experiment switches off, and
`ppu_call_trace=4`. It emitted one complete `HLE_WAIT` block at 13.624
seconds:

    count=2048 index=5967 sequence=3919..5966
    emulation_id=1 previous_emulation_id=18446744073709551615

The first retained call is `sys_timer_usleep` at `0x00fdcf90`. The last call
is `sys_memory_allocate` at `0x009dc0dc`. The retained window contains
1,989 `sys_timer_usleep` calls. Of these calls, 1,958 are from `0x00fdcf90`
and 31 are from `0x00fdcf60`.

The complete trace ended before the conservative thermal stop. The 60 C
sustained probe requested a confirmation sample. That sample was 61.4 C,
below the 68 C immediate stop and the 72 C hard limit. The guard force-stopped
the app. The capture is:

    20260828-001149-thor-input-custom/failure-RPCSX.log

The latest shared function-name block has 15 calls. The latest shared
call-site block has 10 calls. The only exact-call block at the end is the
final `sys_memory_allocate` call. The HLE and LLE tails still perform the same
title operations: update the RSX context, join `FlipPump`, create the render
thread, wait on its start semaphore, query the NP region, probe the same
files, restore the thread priority, and allocate 0x50000 bytes. Allocated
object IDs and thread IDs differ. The HLE PRX call sites also move because HLE
does not load the same firmware modules as LLE.

The title main thread therefore reaches the same wait from the same final
operation in both modes. The HLE trace has 2,417 fewer calls before this
point, but this difference is mainly the number of 30-microsecond polling
calls. It does not identify a different title branch. The next analysis must
identify the condition around `0x009e4ba4` and the asynchronous worker or
state that supplies it.

That address interpretation was incorrect. A guarded two-second PPU Debug
boot produced a decrypted BLUS30357 EBOOT for Ghidra. The ELF is 30,367,464
bytes, and its SHA-256 is `82CBF369...53065D48`. The temporary config change
was restored to its exact original SHA-256, `514AB655...D02E905`, before the
Thor returned to sleep.

Ghidra imported the ELF as `PowerPC:BE:64:A2ALT:default`. A raw-window probe
at `0x009e4ba4` shows that this address is the `sc` instruction in a generic
sleep wrapper at `0x009e4b58`. The wrapper converts its floating-point input
to microseconds, clamps the value to at least 30, loads syscall number 0x8d,
and calls `sys_timer_usleep`. The address is not a caller condition or a title
wait loop.

A raw-window probe at `0x00fdcf20` shows the actual repeated 30-microsecond
polling function. Its first loop compares two global 32-bit counters and
sleeps until they are equal. Its second loop loads an object pointer, compares
the 32-bit values at offsets 0 and 4, and sleeps until they are equal. The
trace counts show that the second loop supplies most of the retained history
in both modes.

A static PowerPC branch scan found 573 direct calls to the generic sleep
wrapper and six direct calls to the polling function. Therefore, the syscall
CIA cannot identify which title path reached the one-shot event. Trace value
4 now records the bounded guest call stack at that event. It also records the
current CIA, LR, and stack pointer. This diagnostic change does not change
guest state.

The comparator self-test and `git diff --check` passed. The ARM64
RelWithDebInfo build passed in 3 minutes 31 seconds.

Debug APK assembly passed in 8 seconds. The exact APK is
`F9688506...A5F60CAC`, and its size is 116,123,033 bytes.

The no-launch install succeeded. The device APK SHA-256 matched
`F9688506...A5F60CAC` before each route.

The first route used HLE. Its startup profile recorded
`hle_libs=libsre.sprx`, `hle_spurs_kernel=1`, and `ppu_call_trace=4`. It
emitted one complete `HLE_WAIT` block at 12.828 seconds:

    count=2048 index=4614
    cia=0x009e4ba4 lr=0x005a3350 sp=0xd0040220
    stack_count=10

The complete stack and history ended before the conservative thermal stop.
The package sensors stayed at or below 63.4 C. The capture is:

    20260828-010131-thor-input-custom/failure-RPCSX.log

Ghidra decoded each call instruction in the HLE stack. The direct call to the
generic sleep wrapper is at `0x005a334c`. The earlier stack calls are at
`0x00566160`, `0x0057146c`, `0x00012c1c`, `0x00012f10`, `0x00013194`,
`0x000151c0`, `0x0001542c`, `0x000182a4`, and `0x00018034`.

The first strict cool gate for the paired route refused the launch at 36.1 C.
The Thor stayed idle until its package sensors were at or below 32.5 C. It
then passed the three-sample strict gate.

The paired route used LLE. Its startup profile recorded `hle_libs=none`,
`hle_spurs_kernel=0`, all other SPURS experiment switches off, and
`ppu_call_trace=4`. It emitted one complete `LLE_WAIT` block at 12.731
seconds:

    count=2048 index=8342
    cia=0x009e4ba4 lr=0x005a3350 sp=0xd0040220
    stack_count=10

The route completed normally. Its package sensors stayed at or below 62.6 C.
The capture is:

    20260828-010947-thor-input-custom/post-RPCSX.log

The HLE and LLE guest stacks are identical. All 10 caller addresses and all
10 stack pointers match. The first caller is `0x005a3350`, and the final
caller is `0x00018038`. Therefore, the first call to the generic sleep wrapper
does not contain the HLE fault boundary.

The actual repeated poll at `0x00fdcf20` compares two values before each
sleep. At `0x00fdcf60`, registers r0 and r9 contain the two global counter
values. At `0x00fdcf90`, registers r0 and r9 contain the values at object
offsets 4 and 0, and r31 contains the object address. The next trace must
record these values and the caller stack at the first real counter poll.

Property value 5 now captures that poll as `HLE_POLL` or `LLE_POLL`. The event
row records r0, r9, r30, and r31. The trace does not write guest memory. The
comparator validates the event registers and reports them with the guest
stack.

The comparator self-test, Python syntax check, and `git diff --check` passed.
The ARM64 RelWithDebInfo build passed in 3 minutes 54 seconds. Debug APK
assembly passed in 15 seconds. The exact APK is
`A69442CC...EFDADA3A`, and its size is 116,122,402 bytes. Its stripped ARM64
library contains the `HLE_POLL` mode label.

The no-launch install used a fresh strict cool gate. The device APK SHA-256
matched `A69442CC...EFDADA3A`, and RPCSX stayed stopped after the install.

The first property-value-5 route used LLE. Its startup profile recorded
`hle_libs=none`, `hle_spurs_kernel=0`, all other SPURS experiment switches
off, and `ppu_call_trace=5`. It emitted one complete `LLE_POLL` block at
11.073 seconds:

    count=265 index=265 cia=0x00fdcf60
    r0=0x303013a0 r9=0x304f8048
    r30=0x01f94980 r31=0x01fb4980
    first caller=0x009e0be8 stack_count=10

The first caller identifies the direct call at `0x009e0be4`. The package
sensors stayed at or below 61.4 C. The route completed normally. The capture
is:

    20260828-012235-thor-input-custom/post-RPCSX.log

The first paired HLE route passed the strict cool gate, but it did not reach
the poll. The package temperature reached the 68 C early-stop threshold at
10.94 seconds. The guard force-stopped RPCSX at 68.2 C, below the 72 C hard
limit. The log ends while the SPU workers load cached native objects. It has no
poll event or trace markers, so it cannot support an HLE and LLE comparison.
The capture is:

    20260828-012530-thor-input-custom/failure-RPCSX.log

One retry is necessary because the paired evidence is incomplete. It must use
the same exact APK and profile. It must also start colder than the normal
strict gate so the poll can occur before the 68 C early stop.

## 25. The real counter poll has the same HLE and LLE caller stack

Before the retry, a property audit found two stale selector experiments:

    debug.rpcsx.thor.spurs_sel_cond_fix=1
    debug.rpcsx.thor.spurs_signal_fix=1

Earlier tests rejected these experiments, and their default value is zero.
The route tool did not reset or record them. Commit `9f2086293` makes the tool
clear both properties before and after each route. It also records them in the
startup profile and in the reset evidence.

The audit also found that the route tool did not record 48 other SPURS
properties that the core reads. Therefore, earlier statements that all other
SPURS experiment switches were off are not valid. The title still uses the
measured contention, task-set, DMA-wait, and yield fixes. These fixes are part
of the current candidate stack. Commit `fb5f25041` makes the route tool record
all SPURS properties that the core reads. This change removes the evidence
gap. It does not change an emulator property value.

The Thor passed a colder three-sample gate. Its package sensors were about
33.3 C. The gate capture is:

    20260828-013300-thor-input-strict-cool-gate

The HLE retry used the same installed APK. The device APK SHA-256 matched
`A69442CC...EFDADA3A`. The profile used `hle_libs=libsre.sprx`,
`hle_spurs_kernel=1`, and `ppu_call_trace=5`. The two selector experiments
were zero. The trace emitted one complete `HLE_POLL` block at 11.518 seconds:

    count=234 index=234 cia=0x00fdcf90
    lr=0x00fdcf3c sp=0xd00405a0
    r0=0x001f0080 r9=0x001f0100
    r30=0x01f94980 r31=0x50100040
    first caller=0x009e0be8 stack_count=10

The package temperature reached 69.1 C. The guard force-stopped RPCSX below
the 72 C package limit. The highest junction sensor value was 82.7 C, below
the 95 C junction limit. The capture is:

    20260828-013412-thor-input-custom/failure-RPCSX.log

The paired LLE event was at `0x00fdcf60`, and the HLE event was at
`0x00fdcf90`. However, all 10 caller addresses and all 10 stack pointers are
identical. The shared stack is:

    0x009e0be8 sp=0xd0040630
    0x009f4870 sp=0xd0040730
    0x009f4b14 sp=0xd00407e0
    0x009df410 sp=0xd0040890
    0x009dfeec sp=0xd0040910
    0x009dff70 sp=0xd00409a0
    0x009e8da0 sp=0xd0040a10
    0x000153d0 sp=0xd0040bd0
    0x000182a8 sp=0xd0040c60
    0x00018038 sp=0xd0040d00

Ghidra shows that the direct call to the poll function is at `0x009e0be4`.
The function at `0x00fdcf20` first calls a helper at `0x00fdced0`. The helper
submits an item through `cellSpursQueuePushBody`. The poll function then waits
for the queue counters to become equal. The title caller at `0x009e09f4`
creates records, submits the queue item, and calls the poll function. The poll
is a SPURS queue submission and drain path. It is not a generic sleep path.

The HLE and LLE events have the same title call path. The first observed HLE
sleep was in the second counter loop. The first observed LLE sleep was in the
first counter loop. This is a state or timing difference, but it is not yet a
fault boundary. Earlier long traces show that both modes spend most poll time
in the second loop at `0x00fdcf90`.

The queue log also shows `CELL_SPURS_TASK_ERROR_AGAIN` from task 0. Earlier
same-run GETLLAR evidence proved that this result is the normal empty-queue
state. The consumer uses the same queue EA and keeps pace with the producer.
This result is not evidence of a failed queue.

The next probe must record a bounded series of counter transitions and the
poll exit. It must use event data, not a one-time state snapshot. No new Thor
route starts until the device is cool. RPCSX is stopped, and the Thor is
asleep.

## 26. Both modes complete the bounded counter series

Commit `a1fd0f870` adds property value 6 for the bounded title counter probe.
The probe applies only to BLUS30357 on `main_thread`. It records entry, wait,
and equal events for the first 32 calls to the function at `0x00fdcf20`. The
translator passes guest registers r0, r3, r9, r29, r30, and r31 directly to
the helper. The helper reads the two counter pairs but does not write guest
memory. A new PPU cache identity bit prevents the use of an object that was
compiled without the probe.

Commit `ed7c8bcda` adds a comparator for the bounded series. It rejects mixed
modes, mixed emulation IDs, missing invocation numbers, reversed event order,
and invalid wait totals. Its syntax check and self-test passed. Commit
`cecb42ecb` adds the exact HLE and LLE route wrapper. Commit `675036db4` makes
the wrapper collect the post-run RPCSX log.

The ARM64 RelWithDebInfo build passed in 3 minutes 38 seconds. Debug APK
assembly passed in 9 seconds. The exact APK is
`26C37EC3...AF12F70F`, and its size is 116,124,395 bytes. The stripped ARM64
library contains both `Thor Transformers COUNTER` and
`__thor_transformers_counter_probe`. The no-launch install succeeded. The
device APK SHA-256 matched the full expected value before each route:

    26C37EC33081D8A66F2F0228573AD1DA6A2D2C832314E7D807FA0589AF12F70F

The HLE route started after a strict three-sample gate at 32.5 to 32.9 C. It
used `hle_libs=libsre.sprx`, `hle_spurs_kernel=1`, and
`ppu_call_trace=6`. Both selector experiments were zero. The route collected
19 consecutive calls before its fixed stop. All 19 calls reached both equal
events. The probe recorded 283 events. The package sensor peak was 67.4 C.
The near-limit confirmation fell to 59.8 C, and the route did not reach the
68 C immediate-stop value or the 72 C hard limit. The stopped-run log was
recovered with the standard snapshot helper. The captures are:

    20260828-020244-thor-input-strict-cool-gate
    20260828-020456-thor-input-custom/post-RPCSX.log

The Thor then slept and cooled. A second strict gate passed at 34.5 C. The
LLE route used the same APK and route settings, with `hle_libs=none` and
`hle_spurs_kernel=0`. It also collected 19 consecutive calls, and all 19
calls reached both equal events. The probe recorded 175 events. The package
sensor peak was 64.2 C. The near-limit confirmation fell to 57.8 C. The
captures are:

    20260828-021040-thor-input-strict-cool-gate
    20260828-021105-thor-input-custom/post-RPCSX.log

The comparator reported these complete wait totals:

    invocation HLE(global,object) LLE(global,object)
             0 HLE(4,0)           LLE(1,0)
             1 HLE(0,1)           LLE(1,0)
             2 HLE(1,419)         LLE(1,174)
             3 HLE(5,225)         LLE(1,358)
             4 HLE(3,129)         LLE(1,356)
             5 HLE(1,221)         LLE(1,353)
             6 HLE(2,224)         LLE(2,357)
             7 HLE(0,111)         LLE(2,0)
             8 HLE(0,106)         LLE(1,354)
             9 HLE(2,465)         LLE(1,0)
            10 HLE(1,281)         LLE(2,0)
            11 HLE(2,219)         LLE(1,350)
            12 HLE(1,98)          LLE(1,0)
            13 HLE(1,157)         LLE(1,0)
            14 HLE(2,208)         LLE(1,354)
            15 HLE(0,397)         LLE(1,0)
            16 HLE(1,221)         LLE(1,0)
            17 HLE(1,219)         LLE(1,0)
            18 HLE(1,78)          LLE(1,345)

The wait totals differ from the first call, but both modes always make
forward progress and exit the queue drain path. Some HLE calls wait longer,
and some LLE calls wait longer. Therefore, this counter poll is a shared
timing mechanism. It is not the HLE correctness boundary. The next analysis
must follow the completed queue work to a downstream state or render result.
RPCSX is stopped, and the Thor is asleep.

## 27. The disabled hot diagnostics were still active

The HLE log from capture `20260828-020456-thor-input-custom` contained 49,622
high-rate SPURS diagnostic records. The route set
`debug.rpcsx.thor.spurs_probe=0`, but six diagnostic blocks in
`cellSpursSpu.cpp` did not read that property. These blocks added counters,
histograms, formatting work, and log writes to the SPURS selector, task
selector, dispatcher, and syscall paths. The log contained 57,238 lines and
used 14,176,775 bytes. This work was measurement overhead, not title work.

Commit `c019838aa` puts all six blocks behind one gate. A normal Android build
uses a compile-time false result. An Android diagnostic build still needs
`RPCSX_THOR_SPURS_PROBE` at build time and the `spurs_probe=1` property at run
time. Desktop behavior does not change. The build-gate test checks the source
gate and the six call sites.

The ARM64 RelWithDebInfo build passed in 55 seconds. The full debug APK build
passed in 1 minute 45 seconds. The normal ARM64 library did not contain the six
high-rate format strings. It retained the two intentional one-shot activation
and request strings. The exact APK was 116,122,881 bytes and had this SHA-256:

    DDE8FE3E747ACDDF897085A0A1669B73496C8F7CF4995281465B3FDF9572EC48

The strict gate passed at 32.1, 32.1, and 32.5 C. The no-launch installer then
verified the same SHA-256 on the device and verified that the RPCSX process was
not active. The evidence is in:

    20260828-023435-thor-input-strict-cool-gate
    20260828-023507-apk-no-launch-install

The exact A/B HLE route used the same 10-second counter wrapper as the earlier
HLE route. Its launch gate passed at 32.9, 32.1, and 32.5 C. It used
`hle_libs=libsre.sprx`, `hle_spurs_kernel=1`, `spurs_probe=0`, and
`ppu_call_trace=6`. It also kept the measured candidate stack. The capture is:

    20260828-023555-thor-input-custom/post-RPCSX.log

All 19 counter calls reached both equal events. The log contained 195 counter
events. Therefore, removal of the hot diagnostics did not stop the measured
queue work. The six high-rate marker counts fell from 49,622 to zero. The new
log contained 10,590 lines and used 1,666,432 bytes. One separate one-shot
`Thor DISPATCH_WKL` record remained.

The package sensor peak fell from 67.4 to 62.2 C. The highest junction sample
fell from 76.3 to 73.5 C. The route stayed below all thermal limits and stopped
normally. These values are one paired observation, not a general performance
result.

This change removes a large observer effect. It does not prove correct 3D
output or 30 FPS because this route did not enable the draw census or capture a
game frame. The next cooled route must set `ppu_call_trace=0`, set
`draw_census=1`, capture a frame, and measure a fixed interval after the shared
counter milestone. RPCSX is stopped, and the Thor is asleep.

## 28. HLE draws only the green loading quads

Commit `b4ec6c9ce` adds a repeatable render-boundary route. It keeps the
measured HLE candidate stack, disables the counter and PPU trace probes, and
enables only the draw census. It waits for eight seconds, takes a thread
snapshot and a screenshot, and stops RPCSX.

The exact installed APK was the same clean diagnostic build. Its SHA-256 was:

    DDE8FE3E747ACDDF897085A0A1669B73496C8F7CF4995281465B3FDF9572EC48

The launch gate passed at 32.5 C for all three samples. The route used
`hle_libs=libsre.sprx`, `hle_spurs_kernel=1`, `spurs_probe=0`,
`ppu_call_trace=0`, and the measured candidate fixes. The capture is:

    20260828-025454-thor-input-custom

The screenshot is a solid green frame. The overlay reports 29.55 FPS, 9.2%
PPU, 63.7% SPU, and 6.1% RSX. This is not a correct 30 FPS result because the
game has no 3D geometry.

The draw census gives the exact render boundary. Draw call 1 starts at 13.102
seconds. Every recorded draw is primitive 8 with four elements. The census has
no primitive 5 draw:

    14.160 seconds: flips=480  draw_calls=32   p8=32
    18.190 seconds: flips=600  draw_calls=150  p8=150
    22.251 seconds: flips=720  draw_calls=268  p8=268
    26.316 seconds: flips=840  draw_calls=388  p8=388
    30.379 seconds: flips=960  draw_calls=508  p8=508
    34.460 seconds: flips=1080 draw_calls=628  p8=628
    38.516 seconds: flips=1200 draw_calls=748  p8=748

The HLE route maps IO ranges 0x500000 and 0x600000 again at 18.244 seconds.
It does not map 0x700000 through 38.5 guest seconds. The paired LLE route maps
0x500000 again at 18.153 seconds and maps 0x700000 at 18.714 seconds. It then
maps 0x800000 and 0x900000. This is the first stable downstream boundary. HLE
does not complete the work that permits the next main-thread allocation and
RSX map stage.

The standard top snapshot shows that this is not a sleeping main thread. Guest
PPU thread `0x1000000` is runnable and uses 18.5% in the sample. Five SPU
threads each use about one full core. The rendering thread also continues to
push task 1 work at about 30 Hz. Therefore, the next probe must sample the
guest PPU program counter and identify its hot loop.

The detailed wait snapshot did not run. A Windows carriage return reached
Android `sh` and made its `case` command invalid. The surrounding standard
snapshot and RPCSX log are valid. The snapshot tool now converts its payload
to LF before ADB sends it. The next route does not need the detailed snapshot.

The long snapshot and screenshot steps extended this capture. It is not a
fixed performance sample. The thermal guard stopped the route after the
near-limit confirmation. The silicon peak was 63.8 C, and the junction peak
was 75.5 C. Both values were below their hard limits. RPCSX is stopped, and
the Thor is asleep.

## 29. The low-rate sample stops in the common sleep wrapper

Commit `339410856` adds a short PPU PC route. The route keeps the exact HLE
candidate stack, disables the draw and call-trace probes, enables the low-rate
PPU PC census, waits for eight seconds, and stops. The same commit also fixes
the Android line endings in the detailed thread snapshot tool.

The Thor passed the strict gate at 33.3 C for all three samples. The capture
is:

    20260828-030248-thor-input-strict-cool-gate

The PC route used the same installed APK. The device SHA-256 matched
`DDE8FE3E...572EC48`. The guard stopped RPCSX during the near-limit
confirmation. The silicon peak was 65.0 C, and the junction peak was 77.5 C.
Both values were below their hard limits. The failure snapshot is complete:

    20260828-030335-thor-input-custom/failure-RPCSX.log

At 16.738 seconds, `main_thread`, `AsyncIOSystem`, and `RenderingThread` all
sampled at `0x009e4ba4`. Ghidra confirms that this address is the `sc`
instruction in the common sleep wrapper at `0x009e4b58`. The wrapper converts
its input to microseconds, clamps the value to 30, and calls
`sys_timer_usleep`. This PC does not identify the title caller.

The census now records LR, SP, and r3 with each PC. It also records one bounded
12-frame main-thread stack. These records are low-rate and active only when the
manual `ppu_pc_census` property is on. The next build and cooled route must use
these records to find the caller that remains after the HLE map boundary.
RPCSX is stopped, and the Thor is asleep.

## 30. The late HLE wait follows task creation

Commit `14d40267c` extends the low-rate PPU census. Each record now contains
LR, SP, r3, and the PPU state. The probe also records one bounded 12-frame
main-thread stack. The probe is active only when the manual `ppu_pc_census`
property is on.

The ARM64 RelWithDebInfo build passed in 57 seconds. The full debug APK build
passed in 36 seconds. The exact APK was 116,122,991 bytes and had this SHA-256:

    161A0D17D652B14848E64D2BF271DC35E1359863DC9698E5889CD68CE689295E

The no-launch installer verified the same SHA-256 on the device and verified
that RPCSX was not active. The evidence is in:

    20260828-031006-apk-no-launch-install

The launch gate passed at 34.1, 33.7, and 34.1 C. The route kept the measured
HLE candidate stack, disabled the draw and call-trace probes, and enabled only
the low-rate PPU census. The thermal guard stopped the route after the
near-limit confirmation. The silicon peak was 62.2 C, and the junction peak
was 75.9 C. Both values were below their hard limits. The complete failure log
is:

    20260828-031058-thor-input-custom/failure-RPCSX.log

At 18.235 seconds, the main thread had this state:

    cia=0x00fdd2cc lr=0x00fdd2b4 sp=0xd00403f0 r3=0x1e state=0x224

The bounded stack was:

    0x00fdddbc sp=0xd0040790
    0x009dfabc sp=0xd0040840
    0x009dfd58 sp=0xd0040910
    0x009dff70 sp=0xd00409a0
    0x009e8da0 sp=0xd0040a10
    0x000153d0 sp=0xd0040bd0
    0x000182a8 sp=0xd0040c60
    0x00018038 sp=0xd0040d00

The title code at `0x00fdd2cc` reads the word at `r31 + 0x590`. If the value
is zero, it sleeps for 30 microseconds and repeats. This is a task start wait,
not the common sleep wrapper from section 29.

Immediately before the wait, the title created task-set workload 2 at
`0x10364100`. It then created one task with ELF address `0x0177ec80`, context
address `0x10370080`, and context size `0x3d400`. The task creation and start
calls returned success. `cellSpursSendWorkloadSignal` wrote bit `0x2000` for
workload 2, and its immediate readback was also `0x2000`.

All six HLE SPU threads recorded only their initial system-service dispatch:

    dispatch#1 wid=32 addr=0x100 size=0x2200

No thread recorded a second dispatch to workload 0 or workload 2 before the
stop. The earlier workload 0 signal also differed between otherwise similar
runs. Its immediate readback was zero in this run and `0x8000` in two runs
that reached the green render boundary. This difference is nondeterministic.
It is not yet proof of causation because one other completed counter route
also read zero.

The direct signal write is not a lost host store. The HLE selector can clear
workload 0 from six SPU threads when it selects system service workload 32.
The current AArch64 shift wraps `0x8000 >> 32` to bit `0x8000`. The next change
must measure or repair signal consumption and workload dispatch as one state
transition. Repeating the signal write alone cannot establish correctness.
RPCSX is stopped, and the Thor is asleep.

## 31. Workload activation no longer erases PPU signals

Ghidra decoded the captured PPU window as
`PowerPC:BE:64:A2ALT:default`. The function at `0x00fdd17c` creates the GCMX
task and then waits at `0x00fdd2cc` until the word at `r31 + 0x590` changes.
Its caller returns at `0x00fdddbc`. This confirms that the section 30 wait is
part of GCMX initialization.

The signal loss came from `spursSysServiceActivateWorkload`. Each SPU copied
the first 128 bytes of `CellSpurs` to its private local-store snapshot. The
function later copied that old line back to shared memory. The copied line
contains `wklSignal1` at offset `0x70`. It does not contain `wklState1` or
`wklStatus1`, which start at offsets `0x80` and `0x90`. Those state and status
updates already used the live shared pointer. Therefore, the whole-line
writeback did not preserve any update from this function. It could only
overwrite newer shared values, including a concurrent PPU workload signal.

Commit `5768f5bd3` removes the stale writeback and keeps the required snapshot
refresh. A source contract test prevents the writeback from returning. The
test passed. The ARM64 RelWithDebInfo build passed in 50 seconds. The full
debug APK build passed in 7 seconds. The ARM64 APK contract passed. The exact
APK was 116,122,927 bytes and had this SHA-256:

    6CC1AE2410E5104EF65EF808515E7EEF5C0967F97C1BA6513583EF3CCE1F568F

The Thor passed the strict gate at 32.5, 32.9, and 32.5 C. The no-launch
installer verified the same APK hash on the device and verified that RPCSX was
not active. The evidence is in:

    20260828-032603-thor-input-strict-cool-gate
    20260828-032625-apk-no-launch-install

The fixed HLE route used the same render-boundary profile as section 28. Its
capture is:

    20260828-032650-thor-input-custom/failure-RPCSX.log

The result proves that the removed writeback was a real correctness fault.
Workload 0 kept its `0x8000` signal and reached `dispatch#2` on SPU 2. Workload
2 kept its `0x2000` signal and reached `dispatch#2` on SPU 0. The policy module
received the correct task-set argument `0x10364100`. Five SPUs then reached
their second dispatch on real job-chain workload 6.

This change does not complete 3D rendering. The draw census still contains
only primitive 8 four-element quads:

    14.150 seconds: flips=480 draw_calls=15  p8=15
    18.187 seconds: flips=600 draw_calls=135 p8=135
    22.248 seconds: flips=720 draw_calls=251 p8=251
    26.329 seconds: flips=840 draw_calls=371 p8=371
    30.395 seconds: flips=960 draw_calls=491 p8=491

The route mapped IO ranges 0x500000 and 0x600000 again at 18.812 seconds. It
did not map 0x700000 before the guard stopped the run. The silicon peak was
62.2 C, and the junction peak was 70.7 C. Both values were below their hard
limits. RPCSX is stopped, and the Thor is asleep.

The fixed route also exposed a second observer effect. It wrote 2,252 entry
records and 2,252 success records from `cellSpursSendWorkloadSignal` in about
19 guest seconds. Commit `6dd2806a8` keeps all rejection records but limits
the entry and success records to eight calls per process. The source contract
test passed. The ARM64 RelWithDebInfo build passed in 54 seconds. This logging
change is not installed and has no device performance or correctness credit.

## 32. The selector can erase another workload signal

Commits `db42387a0`, `36e35b170`, and `76cdf2e36` extended the bounded PPU PC
route and added one staged loader record. The normal diagnostic APK passed the
ARM64 contract. Its SHA-256 was:

    4A5B75F5E36595A72A6773431585AC990E830ABDD2F736AED420A4A71B843D93

The Thor passed the strict gate at 34.5 C for all three samples. The no-launch
installer verified the same hash on the device and verified that RPCSX was not
active. The evidence is in:

    20260828-040023-thor-input-strict-cool-gate
    20260828-040047-hle-load-wait-probe-install

The first bounded route passed its launch gate at 34.9, 34.1, and 34.5 C. The
guard stopped RPCSX during the near-limit confirmation. The capture is:

    20260828-040114-thor-input-custom/failure-RPCSX.log

The main PPU thread stopped at `0x00fdd2cc` with LR `0x00fdd2b4` and r3
`0x1e`. Workload 2 was runnable. Its `0x2000` signal had an immediate `0x2000`
readback, but no SPU dispatched workload 2.

A focused Ghidra import used the legally owned BLUS30357 ELF and language
`PowerPC:BE:64:A2ALT:default`. The function at `0x00fdd17c` creates the GCMX
task set and task. It then waits in a 30-microsecond loop until the completion
word at the task-set owner plus `0x590` becomes nonzero. This confirms that the
missing workload 2 dispatch causes the late PPU wait.

Commit `235b06d4b` added a route switch for the existing SPURS selector probe.
A normal APK run could set the runtime property, but that APK did not contain
the compile-time probe. Its capture still gave useful race evidence:

    20260828-040901-thor-input-custom/failure-RPCSX.log

The route passed at 34.5, 34.1, and 34.1 C. This time the PPU set `0x2000`, but
the immediate readback was zero. Therefore, the failure was nondeterministic.
The guard stopped RPCSX during the near-limit confirmation.

A new diagnostic APK was built with `RPCSX_THOR_SPURS_PROBE=ON`. It passed the
ARM64 contract. Its SHA-256 was:

    75069634E22A1EA345BB57BA61BE5E514923A310AD1A2DBD1E325BE1C063B7B6

The strict gate and no-launch install evidence is in:

    20260828-042442-thor-input-strict-cool-gate
    20260828-042506-hle-spurs-selector-probe-install

The selector route passed its launch gate at 33.7, 32.9, and 33.3 C. The guard
stopped RPCSX at a confirmed 63.0 C package sensor value, before the 72 C hard
limit. The complete capture is:

    20260828-042527-thor-input-custom/failure-RPCSX.log

At 7.842051 guest seconds, the PPU signal call recorded `inside=0x2000` and
`readback=0x2000`. The selectors immediately before and after that record saw
workload 2 as runnable, with priority 0, maximum contention 1, contention 0,
ready count 0, and signal 0. No SPU selected workload 2. Only one real workload
selection occurred in the capture, and it selected workload 0.

Both selector implementations updated each complete 16-bit workload signal
word through a non-atomic `raw() &= mask` operation. An SPU could read zero,
the PPU could atomically set workload 2, and then the SPU could store its stale
zero. The mask did not need to target workload 2 because the stale store
replaced the complete word. This is the remaining signal race after the
activation snapshot fix.

Commit `86bb45158` replaces both selector updates with one atomic helper. The
helper clears only the selected bit. It also preserves the measured default
system-service behavior and the signal-fix no-op arm. The new source contract,
the activation snapshot contract, and the bounded signal log contract passed.
The incremental ARM64 build passed in 50 seconds. The debug APK passed the
ARM64 contract and kept `RPCSX_THOR_SPURS_PROBE=ON`. Its SHA-256 is:

    69C5B32779AF30EF8015BD2E984E5DF99A990058A67472EDE482C8DEF9411C6B

The first validation gate refused to continue because the Thor was still at
37.7 C. RPCSX remained stopped. This APK is not installed, and the atomic fix
has no device correctness or performance credit yet. Correct 3D output and 30
FPS are still not proved.

## 33. Failed SPU block analysis causes an unbounded retry

The Thor later passed the strict gate, and the atomic selector fix received
device correctness credit. The diagnostic capture is:

    20260828-044145-thor-input-custom/failure-RPCSX.log

Workload 2 ran on SPU 0 with task-set argument `0x10364100`. Real image
workload 6 also ran. The earlier title wait at `0x00fdd2cc` did not remain as
the main-thread wait. The route mapped RSX IO ranges 0x500000 and 0x600000.
It did not map 0x700000. The main thread later waited at `0x009e4ba4` with LR
`0x005a3350`.

A focused Ghidra import shows that LR `0x005a3350` is in a resource-object
completion loop. Therefore, the atomic signal repair advances GCMX
initialization, but it does not complete the render path. The silicon peak was
62.6 C, and the junction peak was 73.5 C. Both values were below their hard
limits.

A second route used the compile-time selector probe in its off state. Its
capture is:

    20260828-045259-thor-input-custom/failure-RPCSX.log

Workload 2 and real image workload 6 ran again. The first failure started at
24.832773 guest seconds on SPU 0:

    [0xce00] Invalid code
    [0x0ce00] Compilation failed.

The two records each occurred 401,116 times before the guard stopped the run.
The silicon peak was 68.7 C, and the junction peak was 79.9 C. Both values
were below their hard limits. The route did not produce a usable screenshot,
and it did not prove correct 3D output.

The task image is `gcmxk_kernel_task.spu.elf`. Its first load segment covers
local-store address `0xce00`. A saved local-store image contains word
`0x408eba52` at that address. A focused Ghidra import used language
`PowerPC:BE:64:A2ALT:default`. It decoded `0xce00` as `il r82,0x1d74`, inside
the function that starts at `0xcd10`. The instruction is a valid fall-through
instruction. The failure is in block analysis. It is not missing or damaged
guest code.

Commit `567b3439d` adds a bounded ARM64 recovery path. It stores failed
local-store ranges, runs the existing C++ interpreter only while the PC is in
one failed range, and then returns to the normal JIT and HLE dispatch loop. It
also prevents the repeated analysis and compilation log flood. The new source
contract and the three related SPURS contracts passed. The ARM64
RelWithDebInfo build passed in 1 minute 43 seconds. This build is not installed
and has no device correctness or performance credit yet. Correct 3D output and
30 FPS are still not proved.

## 34. The first fallback APK route stopped during cache compilation

The probe-off debug APK passed the ARM64 package contract and the SPURS probe
build gate. It was 116,124,328 bytes and had this SHA-256:

    FDBE87ABA97D2E82AB47A8BA5B4128BA6B568DE697392F94C4AABF5215898E4A

The general optimized-APK source contract did not pass. It still requires the
literal text `isDebuggable = false`, but the build now uses the
`rpcsxThorDebuggable` setting. This failure is unrelated to the debug APK
package and is not a device result.

The first two strict gates refused to continue at 39.3 C and 40.1 C. RPCSX
remained stopped. The display then slept during a longer passive cooldown. The
next strict gate passed at 34.1, 34.9, and 34.5 C. The no-launch installer
verified the same APK hash on the device and verified that RPCSX was not
active. The evidence is in:

    20260828-051815-thor-input-strict-cool-gate
    20260828-051838-hle-spu-fallback-install

One guarded Transformers route then ran. The capture is:

    20260828-051902-thor-input-custom/failure-RPCSX.log

The route reused 225 PPU warm-cache objects. At 7.649588 guest seconds, the
SPU native-object cache started its startup compilation. The route stopped
during that compilation, before a SPURS workload dispatch. The draw census
contained three zero-draw samples. No screenshot was taken.

The near-limit confirmation read 73.1 C from the silicon package sensor, above
the 72 C hard limit. The junction peak was 86.7 C, below its 95 C limit. The
guard force-stopped RPCSX. The display is asleep.

The log contains zero `0xce00` analysis failures and zero compilation failures,
but this is not fallback correctness evidence because guest execution did not
reach that block. This route has no correctness, 3D, FPS, or performance
credit. Do not retry until a later strict cool gate. Correct 3D output and 30
FPS are still not proved.

## 35. A bounded route has no failed-analysis flood

After a full passive cooldown, a new strict gate passed at 32.9, 32.9, and
32.5 C. The bounded validation route then passed its own launch gate at 33.7 C
for all three samples. It limited SPU cache preload to 64 programs and the SPU
startup compile budget to 50 milliseconds. The evidence is in:

    20260828-052644-thor-input-strict-cool-gate
    20260828-052710-thor-input-custom/failure-RPCSX.log

Workload 2 dispatched once on SPU 0. Real image workload 6 dispatched on SPU 4
and SPU 5. The route mapped RSX IO ranges 0x500000 and 0x600000. It did not map
0x700000. At 17.240364 and 27.240331 guest seconds, the main thread waited at
`0x009e4ba4` with LR `0x005a3350`. The resource-object completion wait from
section 33 therefore remains.

The log continues through 33.981171 guest seconds. It contains zero `0xce00`
analysis failures, zero compilation failures, and zero other invalid-code
records. The old probe-off APK started its 401,116-record flood at 24.832773
guest seconds on a route that also dispatched workload 2 and workload 6.

This is strong retry-flood regression evidence. It is not direct fallback
execution proof because this capture contains no one-time failed-block marker.
The run can have taken a different task branch before the guard stopped it.

The early guard stopped RPCSX after an immediate 62.6 C package confirmation.
The junction peak was 73.9 C. Both values were below their hard limits. The
route did not enable the draw census or take a screenshot, so it has no 3D or
FPS credit. RPCSX is stopped, and the display is asleep. Correct 3D output and
30 FPS are still not proved.

## 36. The staged loader waits for an asynchronous stream range

A focused Ghidra pass resolved the loader object's virtual table entries. The
values `0x01963408` and `0x01963410` are PPU function descriptors. Their code
addresses are `0x005a0a18` and `0x005a3298`. The first function creates or
checks a backing stream at object offset `0x580`. It asks that stream for its
size and then requests the range that starts at zero.

Commit `98c15082f` added three bounded snapshots of the backing stream. The
source contract and related SPU and SPURS contracts passed. The probe-off ARM64
debug APK built in 1 minute 23 seconds. It was 116,125,808 bytes and had this
SHA-256:

    7CCB4DD76D6AFC22D49A083237E7965584F4DAFC37C8D35F80382650E27AC655

The strict gate passed at 32.9 C for all three samples. The no-launch installer
verified the same hash on the device and verified that RPCSX was not active. A
fresh gate then passed. The evidence is in:

    20260828-054414-thor-input-strict-cool-gate
    20260828-054457-transformers-loader-source-install
    20260828-054515-thor-input-strict-cool-gate

The bounded Transformers route passed its own launch gate at 33.7, 32.9, and
33.3 C. Its capture is:

    20260828-054545-thor-input-custom/failure-RPCSX.log

The loader snapshots at 17.236781 and 27.236779 guest seconds were identical.
The loader had completed only its setup bit. Its stage counters stayed at
zero. The backing stream stayed at `0x109cbbb0`, with virtual table
`0x01a84258`. Its size method descriptor resolved to code `0x00520040`. Its
range-read method descriptor resolved to code `0x005234d8`.

Ghidra shows that `0x00520040` returns the stream value at offset `0x98`.
Function `0x005234d8` tests whether the requested range is already in either
of two buffers. If the range is not ready and both asynchronous counts at
offsets `0xc0` and `0xc4` are zero, it submits a new read. It returns zero
until the range is ready. The first probe did not record offsets `0x94` through
`0xcc`, so it cannot yet show whether the request size, buffer limits, or
asynchronous counts are stuck.

The log contains zero invalid-code records, zero `0xce00` records, zero
compilation failures, and zero failed-block markers. The thermal guard stopped
RPCSX after the silicon value stayed at or above the 60 C probe threshold. The
last confirmation was 61.4 C, below the 72 C hard limit. The post-stop value
was 54.6 C, and the PID was absent. No second route is permitted in this
thermal round.

This result identifies the next diagnostic boundary. It does not prove that
the asynchronous stream is an emulator fault. The route did not take a
screenshot or record draw calls, so it has no 3D or FPS credit. Correct 3D
output and 30 FPS are still not proved.

Commit `5be4d51c7` extends the next bounded probe through stream offset `0xcc`.
It records the total size, requested range, both cached ranges, both buffer
pointers, both asynchronous counts, the range table, and the IO selector. The
source contract passed, and the incremental ARM64 debug APK build passed in 55
seconds. The probe-off APK is 116,125,669 bytes and has this SHA-256:

    088CB17B4D751A8497342F79776A2B4701AA43B403B80DEC8096260AC2316D54

A fresh strict gate refused the next run at 40.1 C silicon. RPCSX was
force-stopped. The range APK was not installed. Do not bypass this gate.

A second Ghidra pass traced the submission path. Function `0x00522c3c`
increments the first pending count and submits a direct read through the
title's global IO manager. Its arguments include the source object at stream
offset `0x88`, the requested file offset and size, the destination buffer, and
the pending-count address. Function `0x00522e60` does the same work for a range
table and increments the pending count once for each table entry. The
`AsyncIOSystem` thread waits in its normal idle loop when it has no active
entry. This evidence does not yet show whether the title submits a read or
whether a submitted read does not complete.

The next probe now also records the three-word source object and the first two
range-table entries. This addition makes one later bounded run sufficient to
separate a missing request from a stuck request and to identify the source
range. It also resolves the two IO-manager virtual method descriptors to code
addresses for a direct follow-up in Ghidra. The source contract, related SPU
and SPURS contracts, and the ARM64 debug APK build passed. The APK is
116,126,621 bytes and has this SHA-256:

    BA1CA9C852BA9E092A30062DB0E9C6796E777741F349743655AD89F7E2E2B2A5

The device still has the earlier exact APK.

Ghidra then found a probe error before deployment. The global at `0x019d5410`
is a 16-byte manager with a worker-array pointer at offset `4` and a worker
count at offset `8`. Constructor `0x005a40c0` sets its base virtual table to
`0x01a871d8`. The submission functions first call manager method `+8` to get
worker zero. They then call the direct-read or table-read method on that
worker. The first probe revision incorrectly resolved `+0x0c/+0x10` on the
manager itself. Those manager entries are null.

The corrected host probe reads worker zero from the manager array and resolves
the two method descriptors from the worker virtual table. The source contract
passed, and the ARM64 debug APK build passed. The corrected APK is 116,126,061
bytes and has this SHA-256:

    641E8AC83B533325CC149EA8365EEE7C8CF214FBD11ECA6B2237C7F696A429E7

The earlier `BA1C...29E7` APK is superseded and must not be installed.

After another passive interval, a new strict gate refused the run at 39.3 C
silicon. The capture is:

    20260828-061349-thor-input-strict-cool-gate

RPCSX was force-stopped. The corrected APK was not installed, and no title
launch occurred. Do not retry until the silicon temperature is below 35 C for
all three strict-gate samples.

The two `cellSpursCreateTaskWithAttribute` failures in the last run are known
control behavior. The route sets `task_attr_fix=0`. The existing repair already
rejects the two unaligned leftover-register values and makes a size-correct LS
pattern. Earlier A/B tests show that this repair reduces GCM heap growth and can
deadlock the title. Therefore, these failures are not a new lead, and the flag
must stay off until a different task-exit cause is proved.

This APK is not installed. The previous exact APK remains installed. Do not
use the Thor again until a later strict cool gate.

## 37. The loader request reaches an active IO worker entry

The Thor passed a new strict gate at 31.7, 31.7, and 31.3 C. The no-launch
installer then installed the corrected loader IO APK. The host and device
SHA-256 values both matched:

    641E8AC83B533325CC149EA8365EEE7C8CF214FBD11ECA6B2237C7F696A429E7

RPCSX was not active before or after the install. A new strict gate then
passed at 32.1 C for all three samples. The evidence is in:

    20260828-110416-thor-input-strict-cool-gate
    20260828-110443-transformers-loader-io-install
    20260828-110457-thor-input-strict-cool-gate

One bounded Transformers route ran. Its capture is:

    20260828-110518-thor-input-custom/post-RPCSX.log

The loader snapshots at 17.234533 and 27.234501 guest seconds were identical.
The stream size was 280,390 bytes. The requested range was offset 109 plus
148,299 bytes. Buffer zero covered 109 through 280,390, and its pending count
stayed at one. Buffer one and its pending count stayed at zero. The range table
stayed at `0x10540fd4`.

The corrected probe resolved worker zero to `0x1050b450`, with virtual table
`0x01bbab48`. Its direct-read method resolved through descriptor `0x01961a88`
to code `0x00518e18`. Its table-read method resolved through descriptor
`0x01961a90` to code `0x00518e54`.

A focused Ghidra raw import used the verified decrypted ELF with language
`PowerPC:BE:64:A2ALT:default` and base address `0x10000`. Both worker methods
are small wrappers around `0x00518930`. That common function adds a 0x50-byte
request to the queue at worker offset `0x4c` and signals the wake object at
offset `0x64`. The worker loop moves a request to the active list at offset
`0x58`, starts the backend operation, and polls its completion object.

At both runtime samples, `AsyncIOSystem` slept with LR `0x0051aea4`. Ghidra
shows that this sleep arm runs when the worker active-list count at offset
`0x5c` is greater than zero. Therefore, the observed boundary is not a missing
submission. The title has at least one active IO request while this stream's
pending count stays at one. The current capture does not yet match that active
entry to this exact stream request or identify the backend operation that does
not finish.

The log continues through 27.638087 guest seconds. It contains zero invalid-
code records, zero `0xce00` records, zero compilation failures, and zero old
SPU retry-flood records. The macro stopped the route. The silicon peak was
59.8 C, the junction peak was 71.1 C, the skin peak was 30 C, and the battery
peak was 22 C. The post-stop silicon value was 45.3 C, and the PID was absent.
No second route ran in this thermal round.

Commit `3930d495d` adds the next bounded probe. It records the worker queue and
active-list pointers, counts, capacities, wake object, reference and run
counts, submission sequence, and the first active 0x50-byte entry. The source
contract passed. The ARM64 build passed in 1 minute 53 seconds. Debug APK
assembly passed in 11 seconds. The ARM64 package gate and SPURS probe gate
passed. The APK is 116,141,091 bytes and has this SHA-256:

    B1751D680FBF8A2FEC641DF1314D292670EAD3E698C705061E5C3186B066993D

This new APK is not installed. The device still has exact APK
`641E8AC8...A429E7`. The route did not take a screenshot or record a draw
census, so it has no 3D or FPS credit. Correct 3D output and 30 FPS are still
not proved. Do not use the Thor again until a later strict cool gate.

## 38. Ghidra resolves the loader IO backend methods

The raw Ghidra project resolved the virtual table at `0x01bbab48`. The backend
read entry at offset `0x40` uses descriptor `0x0198c998` and code
`0x00a08798`. The release entry at offset `0x48` uses descriptor `0x0198c9a8`
and code `0x00a08c8c`. The source-validation entry at offset `0x4c` uses
descriptor `0x0198c9b0` and code `0x00a08ce4`.

Function `0x00a08798` is the data-read backend. It has a buffered direct-read
path and a path that uses the title's 16-slot asynchronous job pool. Function
`0x00a08c8c` calls the request object's release method when the object is not
null. Function `0x00a08ce4` returns true when the source object in the request
is not null. This result gives the field meaning needed to read the first
active 0x50-byte entry from the next capture.

Commit `8a269568c` adds the three backend method descriptors and code addresses
to the bounded loader probe. The source contract passed. The ARM64 native
build passed in 2 minutes 26 seconds. Debug APK assembly passed in 56 seconds.
The ARM64 package gate and the SPURS probe gate passed. The APK is 116,138,373
bytes and has this SHA-256:

    2F96D3E36F5285F1D9E7F03275E8E5FB36A1482957C26E56DBAAF9493A71FF12

This APK is not installed. The device still has exact APK
`641E8AC8...A429E7`. The next hardware step is one strict cool gate, one
no-launch install, one more strict cool gate, and one bounded Transformers HLE
route. The route must stop if the thermal guard refuses it. No 3D or FPS result
is available yet.

## 39. The active loader operation is a SPURS LFQueue job

A strict cool gate refused a later hardware run at 65.8 C silicon. The capture
is:

    20260828-132454-thor-input-strict-cool-gate

RPCSX was force-stopped. No APK was installed, and no title launch occurred.
Do not bypass the 35 C launch limit.

A focused Ghidra pass resolved the active-request completion list. The active
entry stores the list pointer at offset `0x40`, the count at offset `0x44`, and
the capacity at offset `0x48`. Each list item points to an eight-byte pair. The
first word is a completion-state pointer. The second word is a storage pointer.
The worker retires an item when the completion-state word becomes zero.

Commit `17e18681c` adds a bounded runtime sample of this nested completion
state. The source contract passed. The ARM64 native build passed in 44 seconds.
Debug APK assembly passed in 9 seconds. The ARM64 package gate, the SPURS probe
gate, and the Transformers probe contract passed. The APK is 116,137,742 bytes
and has this SHA-256:

    F91FFAAD4E1EBCBD67A7D8F649DD862C7272D07D7F87BC380E8EC374120BFEC2

This APK is not installed. The device still has exact APK
`641E8AC8...A429E7`.

The earlier Thor log and the Ghidra import trace identify the operation behind
this wait. The title builds a 32-byte edgeZlib control job and calls
`_cellSpursLFQueuePushBody` with return address `0x00a886a4`. Its queue is
`0x101b1f80`. The queue has 0x20-byte entries, depth 0x10, and direction 3,
which is ANY2ANY. The associated edgeZlib task set is `0x101b4e80`, and its
signal address is `0x01e97a81`. The PoolThread then waits on event flag
`0x01e54800`.

The HLE calls `_cellSyncLFQueueGetPushPointer2` and
`_cellSyncLFQueueCompletePushPointer2` on this path. The existing ANY2ANY
implementation is behind `debug.rpcsx.thor.lfq_any2any` and is off by default.
The default route therefore leaves this loader job unpublished. Earlier tests
show that enabling the route wakes edgeZlib task 0, but those tests did not have
the exact loader-completion probe and did not produce correct 3D output.

Commit `3971c7bd6` adds explicit control and evidence for the LFQueue property
to the Thor runner. It resets the property after success or failure. The
PowerShell parser, the new route contract, the loader probe contract, and the
Git whitespace check passed.

The next hardware test must install the exact `F91F...EC2` APK after a strict
cool gate. It must then run one bounded route with `lfq_any2any=on`. The test
must show whether the completion state becomes zero and whether the active
entry retires. It has no 3D or FPS credit unless a screenshot and draw evidence
show correct output. Correct 3D output and 30 FPS are still not proved.

## 40. Firmware replaces the incorrect LFQueue shortcut

A later strict cool gate refused the hardware run at 42.5 C silicon. The
capture is:

    20260828-135158-thor-input-strict-cool-gate
    20260828-140515-thor-input-strict-cool-gate

RPCSX was force-stopped. No APK was installed, and no title launch occurred.
The 35 C launch limit stays in effect.

The cooldown made a firmware comparison possible. The encrypted `libsre.sprx`
on the Thor has SHA-256
`FD0F6E06A623C4C43F978CB75610243D620E04108F8075566FA8FEFC34918E84`.
The existing decrypted firmware ELF has SHA-256
`74A023767AAE35838F26EF1A846806CAAD438A041A06BA16B1165050AA403E8`.
These files are research inputs. They are not in Git.

Ghidra resolved these firmware functions:

    _cellSyncLFQueueGetPushPointer2        code 0x000030b8
    _cellSyncLFQueueCompletePushPointer2   code 0x000035c8
    _cellSyncLFQueuePushBody               code 0x000016b4
    _cellSpursLFQueuePushBody              code 0x000171b8
    SPURS LFQueue notifier                 code 0x000127cc
    LFQueue notification delivery helper   code 0x0000439c

The result invalidates the old shortcut. The old HLE used `push1.m_h5` as both
the reserve counter and the publish counter. Sony reserves with `push1.m_h8`.
It copies the entry, records completion in the 16-bit `push1.m_h6` bitmap, and
only then advances `push1.m_h5` across contiguous completed entries.

The raw queue state from the earlier Thor run also contains one pending pop
notification. `pop1.m_h3` is `0x0001`. Sony consumes the token from
`m_hs1[0]`, advances the packed notification head, and sends that token through
the notifier. The old direct waiter scan sent a signal but did not retire this
queue state.

The SPURS notifier contract is exact. If the low nibble of `eaSignal` is 1,
the base address is a SPURS instance. The token stores the workload ID above
the low task-ID byte. The notifier calls `cellSpursLookUpTasksetAddress` and
then `_cellSpursSendSignal`. Other signal tags name a task set directly.

The new default-off route implements this measured fast path. It reserves with
`m_h8`, publishes with `m_h5/m_h6`, consumes `pop1.m_h3/m_hs1`, and uses the
firmware SPURS token decoder. The event-queue contention slow path remains out
of scope for this experiment. A follow-up removes the old task-set registry and
direct waiter scan. The firmware token decoder is now the only SPURS LFQueue
notification path.

Online source research found no implementation to copy. Current RPCS3 and the
ARMSX3 branch still return success from TODO stubs for both ANY2ANY functions.
An arXiv search found no PS3 or SPURS paper. The SCQ and wCQ papers confirm the
general need for separate MPMC reservation and publication, but they do not
specify the Sony data layout:

    https://arxiv.org/abs/1908.04511
    https://arxiv.org/abs/2201.02179

The LFQueue route contract, loader logging contract, firmware contract, and Git
whitespace check passed. The final Android debug rebuild passed in 53 seconds.
The APK is 116,128,657 bytes and has this SHA-256:

    3BF21BB4A4D440F81FE2184D8F4C8E468A5E7080B6AB0304B64866C41BF140FE

This APK is not installed. It supersedes the `F91F...EC2` probe APK. The device
still has exact APK `641E8AC8...A429E7`. The next hardware run must use one
strict cool gate, one no-launch install, a second strict cool gate, and one
bounded `lfq_any2any=on` route. Correct 3D output and 30 FPS are still not
proved.

The cooldown audit found no software load. The device was asleep, had no wake
locks, and reported 793 percent idle across eight CPUs. RPCSX was absent. The
battery service reported USB power and a maximum charge current of 900 mA.
USB charging is the remaining cooldown source. Disconnect the cable while the
device cools, then reconnect it before the next strict gate. Do not lower the
35 C launch limit.

## 41. The firmware LFQueue path reaches the SPURS selector

The Thor passed the first strict gate at 34.1, 34.9, and 34.5 C. The no-launch
installer verified the new APK on the device and kept RPCSX stopped. The exact
SHA-256 was:

    3BF21BB4A4D440F81FE2184D8F4C8E468A5E7080B6AB0304B64866C41BF140FE

The second strict gate passed at 34.1, 34.1, and 34.5 C. The evidence is in:

    20260828-141251-thor-input-strict-cool-gate
    20260828-141324-transformers-lfq-firmware-install
    20260828-141348-thor-input-strict-cool-gate

One bounded route used `lfq_any2any=1`. Its capture is:

    20260828-141452-thor-input-transformers-lfq-firmware/failure-RPCSX.log

The firmware LFQueue path ran. The queue had one pending pop notification in
`pop1.m_h3`. The path consumed token zero, resolved workload zero to edgeZlib
task set `0x101b4e80`, signaled task zero, and called `cellSpursWakeUp`. The
next SPU 3 dispatch was still system service workload 32. No SPU dispatched
edgeZlib workload zero after the notification. The PoolThread then waited on
event flag `0x01e54800`.

This result moves the boundary past LFQueue publication and token delivery. It
does not complete the edgeZlib task. The route did not map RSX IO range
`0x700000`, open the target movie, or prove correct 3D output. The 10-second
frame samples were 21.40 and 29.50 FPS, but the earlier stalled route had the
same 29.50 FPS presentation rate. These values have zero full-speed credit.
The thermal guard stopped RPCSX during the 15-second wait. Silicon reached
61.4 C, the highest recorded junction value was 72.7 C, and the PID was absent
after the stop. The screenshot token did not run before the thermal stop.

The next verified boundary is the SPURS selector. The route tool forced
`spurs_sel_cond_fix=0` and `spurs_signal_fix=0`. In that mode the selector
preserves the measured AArch64 result of shifting the workload mask by the
system service ID. That operation clears workload zero. Existing Ghidra work
shows that the selector condition and signal guard must be tested as one pair.
The route tool now exposes one paired switch and records its effective values.
It does not permit a hidden stale property to control the result.

Do not run a second hardware route until the Thor passes a new strict cool
gate. The next route must use the same exact APK with `lfq_any2any=on` and the
paired selector repair on. It must capture a screenshot before its short stop.

## 42. The paired selector route reaches the edgeZlib task set

The Thor refused two strict gates before it cooled. The first gate measured
39.3 C. The second gate measured 35.3 C. The third strict gate passed. The
evidence is in:

    20260828-142543-thor-input-strict-cool-gate
    20260828-142827-thor-input-strict-cool-gate
    20260828-142952-thor-input-strict-cool-gate

One bounded route used the installed APK with this exact SHA-256:

    3BF21BB4A4D440F81FE2184D8F4C8E468A5E7080B6AB0304B64866C41BF140FE

The route enabled `lfq_any2any`, `spurs_sel_cond_fix`, and
`spurs_signal_fix`. Its capture is:

    20260828-143020-thor-input-custom

The firmware LFQueue publication and notification path completed. It consumed
token zero, sent a signal to task zero in edgeZlib task set `0x101b4e80`, and
called `cellSpursWakeUp`. SPU 4 then selected workload zero at dispatch 31.
SPU 1 also selected workload zero at dispatch 32 and returned to system
service at dispatch 33. This result proves that the signal, wake-up, selector,
and workload-selection paths now reach the edgeZlib task set.

The edgeZlib task did not complete the load operation. The PoolThread still
waited on event flag `0x01e54800`, and no event-flag set occurred. The route did
not map RSX IO range `0x700000`. It mapped only `0x500000` and `0x600000`.
Draw census samples at flips 120 and 240 had zero draws. The sample at flip
360 had 23 primitive-8 draws. The sample at flip 480 had 143 primitive-8
draws. These are loading-screen quads, not correct 3D output.

The thermal guard stopped the process during the 8-second wait after silicon
held at 63.0 C near the limit. The PID was absent after the stop. The route did
not capture a screenshot. No second route ran in this thermal round.

Ghidra located the embedded edgeZlib SPU ELF at guest address `0x0175c700` in
the decrypted Transformers executable. The ELF entry at local-store address
`0x3050` initializes the task and calls worker `0x8840`. That worker calls the
loop at `0x30a8`. The loop calls queue helpers `0x8e98` and `0x8d80`, task-state
helpers `0x88b8`, `0x8870`, and `0x88d8`, and the task-exit wrapper `0xa318`.
This result sets the current boundary at task dispatch or task completion.

Ghidra also resolved the real firmware task-set request function at
local-store address `0x0e40`. The policy module gets the first 128-byte taskset
line with GETLLAR command `0xd0`, changes the task state in local store, and
publishes it with PUTLLC command `0xb4`. It retries when the reservation fails.
The EXIT, YIELD, WAIT, and POLL syscall paths call this function. This is direct
evidence that task-state selection must be one atomic transaction.

The live route had two SPUs select workload zero after one task signal. This is
consistent with duplicate task selection, but it is not proof. Current RPCS3
master and the current ARMSX3 master still have the task-set reservation and
writeback code disabled. They do not contain an implementation to port. The
arXiv SCQ and wCQ papers describe separate reservation and publication for
concurrent queues, but they do not specify the Sony ABI:

    https://arxiv.org/abs/1908.04511
    https://arxiv.org/abs/2201.02179

A new default-off route property is now available:

    debug.rpcsx.thor.taskset_select_atomic

When this property is on, SELECT_TASK reads and publishes the six task bitmaps
and `last_scheduled_task` in one 128-byte reservation transaction. It copies
the committed line to local-store address `0x2700`, as the firmware does. It
also writes a bounded selection trace. Other request types still use the old
path. The route, firmware-contract, selector-contract, and new atomic-selection
tests passed. The Android debug build passed.

The new APK is 116,132,150 bytes and has this SHA-256:

    01AA0B23412EE0BC5431D48770C83BDE6525E0D74B7E82F28B86B462668463D6

This APK is not installed. Correct 3D output and sustained 30 FPS are still not
proved. After the Thor passes a new strict cool gate, install this exact APK
without a title launch. Run a second strict gate. Then run one bounded route
with the firmware LFQueue path, the paired selector repairs, and atomic task
selection on. Do not run a second route in the same thermal round.

## 43. The first atomic route found a bitmap-endian defect

The Thor refused strict gates at 39.3 C and 35.3 C. It then passed a strict
gate. The no-launch installer verified APK
`01AA0B23412EE0BC5431D48770C83BDE6525E0D74B7E82F28B86B462668463D6` and
kept RPCSX stopped. The second gate failed on its third sample at 35.3 C. A
later full gate passed. The evidence is in:

    20260828-145658-thor-input-strict-cool-gate
    20260828-145818-thor-input-strict-cool-gate
    20260828-145921-thor-input-strict-cool-gate
    20260828-145942-transformers-taskset-atomic-install
    20260828-145953-thor-input-strict-cool-gate
    20260828-150111-thor-input-strict-cool-gate

One bounded route enabled the firmware LFQueue path, both selector repairs,
and atomic task selection. Its capture is:

    20260828-150132-thor-input-custom

The process crashed during task-set startup, before the later LFQueue signal.
The first atomic selection log reported task ID 120 for task set `0x101b4e80`.
Its state changed from running word `0x00000000` to `0x80000000`. The next two
SPUs correctly found no second task, but the selected task ID was wrong.
`spursTaskLoadElf` failed, the SPU executed address zero, and Android reported
signal 11. The process guard detected that PID 19496 became PID 20067 and
force-stopped the restarted process.

This is not an unknown Android restart. The reservation callback treated the
four big-endian bitmap words as a raw host `v128`. On AArch64, the task-zero
byte then appears as numeric bit 7. The selection loop maps bit 7 to task 120.
The normal `vm::_ref<v128>` path converts the full 16-byte value through
`be_t<v128>`, where task zero is numeric bit 127.

The route showed zero draws at flips 120 and 240. It did not prove 3D output or
30 FPS. The highest guarded silicon sample was 52.6 C. A separate CPU junction
sensor reached 72.7 C before the process died. No second route ran in this
thermal round.

The atomic callback now loads and stores each bitmap through `be_t<v128>`.
This makes its numeric bit convention equal to the existing task-selection
path while the reservation still covers the complete 128-byte line. The route
contracts and the Android debug build passed.

The corrected APK is 116,132,240 bytes and has this SHA-256:

    248AED06A2E0CA3D98759C911A259C011E4ED9D626A8A2341B09F134D67C9FA3

This APK is not installed. The next hardware work must start in a new cool
round. It must use a strict gate, a no-launch install, a second strict gate,
and one bounded atomic route. Correct 3D output and sustained 30 FPS are still
not proved.

## 44. Correct atomic selection leaves one edgeZlib task active

The Thor refused strict gates at 38.1 C and 38.5 C. It then passed a strict
gate. The no-launch installer verified the corrected APK and kept RPCSX
stopped. The second strict gate failed on its third sample at 35.3 C. A later
full gate passed. The evidence is in:

    20260828-150711-thor-input-strict-cool-gate
    20260828-150842-thor-input-strict-cool-gate
    20260828-151051-thor-input-strict-cool-gate
    20260828-151110-transformers-taskset-endian-install
    20260828-151121-thor-input-strict-cool-gate
    20260828-151240-thor-input-strict-cool-gate

The installer verified this exact SHA-256 on the device:

    248AED06A2E0CA3D98759C911A259C011E4ED9D626A8A2341B09F134D67C9FA3

One bounded route enabled the firmware LFQueue path, both selector repairs,
and corrected atomic task selection. Its capture is:

    20260828-151323-thor-input-custom

The endian repair worked. The first atomic selection for edgeZlib task set
`0x101b4e80` selected task zero and changed its running word from zero to
`0x80000000`. Two other SPUs then returned task ID 128 while the same running
bit stayed set. Task zero received its valid queue arguments and returned to
system service after its first wait.

The later firmware LFQueue push found one pending pop notification. It
consumed token zero, resolved workload zero to edgeZlib task set
`0x101b4e80`, sent the task signal, and woke SPURS. Exactly one SPU then
selected workload zero. No second SPU selected this workload after that
signal. This result proves that atomic selection prevents the duplicate
edgeZlib dispatch seen in the previous route.

The selected SPU did not return to system service before the thermal stop. It
did not call the task-set event-flag set path. The PoolThread stayed blocked on
event flag `0x01e54800`. The route did not map RSX IO range `0x700000`; it
mapped only `0x50000000` and `0x50100000`.

Draw samples at flips 120 and 240 had zero draws. The flip-360 sample had 27
primitive-8 draws. The flip-480 sample had 147 primitive-8 draws. These are
loading-screen quads, not correct 3D output. No crash, task ELF load failure,
or fatal error occurred.

The thermal guard stopped RPCSX after package silicon held at 65.4 C in the
near-limit probe. The PID was absent after the stop. The screenshot token did
not run, and no second route ran in this thermal round.

The remaining boundary is inside the resumed edgeZlib task or its SPU-side
LFQueue pop. The next bounded route enables the existing SPU atomic census.
This census records each guest GETLLAR and PUTLLC with its live local-store PC
and effective address. It can show whether the resumed task reaches the Ghidra
queue helpers at `0x8e98` and `0x8d80` without changing emulation behavior.
Correct 3D output and sustained 30 FPS are still not proved.

## 45. The edgeZlib queue pop completes before the remaining delay

The Thor refused the first strict gate at 39.3 C. The second gate measured
34.9, 34.9, and 36.1 C, so it also refused the launch. A later strict gate
passed. The evidence is in:

    20260828-151911-thor-input-strict-cool-gate
    20260828-152110-thor-input-strict-cool-gate
    20260828-152432-thor-input-strict-cool-gate

One bounded route used the installed APK with this exact SHA-256:

    248AED06A2E0CA3D98759C911A259C011E4ED9D626A8A2341B09F134D67C9FA3

The route enabled the firmware LFQueue path, both selector repairs, corrected
atomic task selection, and the SPURS atomic census. Its capture is:

    20260828-152504-thor-input-custom

The startup selection remained correct. One SPU selected task zero in edgeZlib
task set `0x101b4e80`. Two other SPUs returned task ID 128. After the LFQueue
notification, exactly one SPU entered workload zero. The PoolThread then
waited on event flag `0x01e54800`.

The resumed task completed two reservation transactions on queue effective
address `0x101b1f80`:

    GETLLAR  PC 0x0954c -> PUTLLC PC 0x098b8
    GETLLAR  PC 0x099b8 -> PUTLLC PC 0x09f0c

Both PUTLLC operations succeeded. The task did not issue another atomic
operation or a task-set syscall before the stop. This result moves the current
boundary past task selection, task wake-up, and the SPU-side queue pop.

Ghidra analyzed the 262,144-byte local-store image that the earlier run saved
for this exact task set. The image SHA-256 is:

    F65F111BDA08922A74CA6A131E4087E905EE7A511A6A3863F29E240412932A28

The disassembly confirms the live trace. PC `0x0954c` writes GETLLAR command
`0xd0`, and PC `0x098b8` writes PUTLLC command `0xb4`. PC `0x099b8` writes the
second GETLLAR, and PC `0x09f0c` writes the second PUTLLC. The second function
retries at `0x099a0` when PUTLLC fails. After success, it calls helper
`0x0a030` at `0x09f2c`.

Helper `0x0a030` iterates the entries that the queue operation produced. It
calls callback `0x092e0` for each normal entry. Callback `0x092e0` validates
the entry fields and can call helpers `0x09060` and `0x09110`. Helper `0x09110`
contains another complete GETLLAR and PUTLLC transaction. The live census did
not record that transaction. Therefore, the captured execution did not reach
that atomic path before the stop. A zero callback-entry count or work in the
main edgeZlib loop can explain this result. A live SPU PC sample is required to
separate these cases.

The route did not set event flag `0x01e54800` and did not map RSX IO range
`0x700000`. It mapped only `0x50000000` and `0x50100000`. Draw samples at flips
120 and 240 had zero draws. The flip-360 sample had 47 primitive-8 draws. The
flip-480 sample had 163 primitive-8 draws. These are loading-screen quads, not
correct 3D output.

The near-limit guard stopped the process after package silicon held at 61.4 C.
The PID was absent after the stop. No crash, signal 11, task ELF load failure,
or fatal marker occurred. No second route ran in this thermal round.

The next diagnostic must sample each SPU guest PC from the timer thread while
the route is active. It must be default-off and bounded. Run it only after a
new strict cool gate. Correct 3D output and sustained 30 FPS are still not
proved.

The default-off diagnostic is now available as:

    debug.rpcsx.thor.spu_pc_census=1

It runs from the 500 ms monitor timer. It matches the exact 16-byte edgeZlib
code signature at local-store address `0x3000`. It records the guest PC, base
PC, link register, stack pointer, and last MFC command for each matching SPU.
It stops after 64 samples. It adds no work to the SPU execution path.

The route contract, Android debug build, and ARM64 APK contract passed. The APK
is 116,130,197 bytes and has this SHA-256:

    326A5E50CBB6F483BF958D0545F1E6FA6BBC14766300827D53CA36C636435FB2

This APK is not installed. The next device work must start with a strict cool
gate. Install this exact APK without a title launch. Run another strict cool
gate before one bounded route. Do not run a second route in the same thermal
round.

## 46. The edgeZlib task reaches the SPURS event-flag notification

The Thor refused strict gates at 38.9 C and 35.3 C. A later gate passed. The
no-launch installer verified the PC-census APK and kept RPCSX stopped. The
second strict gate also passed. The evidence is in:

    20260828-154020-thor-input-strict-cool-gate
    20260828-154203-thor-input-strict-cool-gate
    20260828-154330-thor-input-strict-cool-gate
    20260828-154350-apk-no-launch-install
    20260828-154401-thor-input-strict-cool-gate

The installer verified this exact SHA-256 on the device:

    326A5E50CBB6F483BF958D0545F1E6FA6BBC14766300827D53CA36C636435FB2

One bounded route enabled the firmware LFQueue path, both selector repairs,
corrected atomic task selection, the SPURS atomic census, and the SPU PC
census. Its capture is:

    20260828-154424-thor-input-custom

The PC census found one active edgeZlib task. The first six samples showed the
task move through queue and decompression code at PCs `0x09940`, `0x05c10`,
`0x0538c`, `0x04530`, `0x06fc0`, and `0x088d8`. The task then updated event
flag `0x01e54800`. Its GETLLAR at PC `0x08990` and PUTLLC at PC `0x08be8` both
completed. The next nine samples all had PC `0x0a4d8`, link register
`0x08ca8`, last MFC command `0xb4`, and effective address `0x01e54800`.

Ghidra mapped PC `0x0a4d8` in the valid live local-store image. This helper
checks that its port is at most 63. It writes the payload to outbound mailbox
channel 28. It then writes command `0x40 | port` to interrupt mailbox channel
30. Caller PC `0x08ca4` gives the helper the event-flag port and returns at PC
`0x08ca8`. This is the SPU event-throw path that notifies the waiting PPU
thread. The repeated PC samples show that the guest did not complete this
notification before the stop.

The HLE event-flag wait code had a separate definite correctness defect. After
a blocking queue receive, it copied `pendingRecvTaskEvents[i]` to the output
mask. It then replaced that mask with an uninitialized `receivedEvents` local.
The August 22 RPCS3 comparison checkout has the same defect. The local fix now
copies `pendingRecvTaskEvents[i]` to `receivedEvents` and uses the existing
final output assignment. A source contract test prevents the old assignment
from returning.

The route did not map RSX IO range `0x700000`. It mapped only `0x50000000` and
`0x50100000`. Draw samples at flips 120 and 240 had zero draws. The flip-360
sample had 31 primitive-8 draws. The flip-480 sample had 150 primitive-8
draws. These are loading-screen quads, not correct 3D output. No crash, signal
11, task ELF load failure, or fatal marker occurred.

The near-limit guard stopped RPCSX after package silicon held at 62.2 C. The
highest package sample was 62.6 C. The PID was absent after the stop. No second
route ran in this thermal round.

The event-flag wait contract, LFQueue route contract, Android debug build, and
ARM64 APK contract passed. The corrected APK is 116,130,185 bytes and has this
SHA-256:

    C7939244A4F5BC8C9B996E714ABC5996FDB22EA8E9C793DEE55CE2C297DBFB00

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate before one bounded route. Correct 3D output and sustained 30 FPS are
still not proved.

## 47. The event-mask fix does not release the SPU notification

The Thor refused a strict gate at 36.5 C. A later gate passed. The no-launch
installer verified the event-mask APK and kept RPCSX stopped. The second gate
failed at 35.3 C, then a later gate passed. The USB ADB transport disappeared
before the route set its first property, so the route did not launch. The same
Thor remained online through its Wi-Fi ADB transport. Wi-Fi gates refused at
46.2 C and 35.3 C before a full gate passed. The evidence is in:

    20260828-155518-thor-input-strict-cool-gate
    20260828-155717-thor-input-strict-cool-gate
    20260828-155819-transformers-event-flag-mask-install
    20260828-155838-thor-input-strict-cool-gate
    20260828-155952-thor-input-strict-cool-gate
    20260828-160059-thor-input-strict-cool-gate
    20260828-160322-thor-input-strict-cool-gate
    20260828-160440-thor-input-strict-cool-gate

The installer and route verified this exact APK SHA-256:

    C7939244A4F5BC8C9B996E714ABC5996FDB22EA8E9C793DEE55CE2C297DBFB00

One bounded route used the firmware LFQueue path, both selector repairs,
corrected atomic task selection, the event-mask fix, and both existing
censuses. Its capture is:

    20260828-160507-thor-input-custom

The event-mask fix did not move the boundary. One edgeZlib task completed both
queue reservations, ran decompression code, and updated event flag
`0x01e54800`. Its GETLLAR at PC `0x08990` and PUTLLC at PC `0x08be8` both
succeeded. The next seven samples all had PC `0x0a4d8`, link register
`0x08ca8`, last MFC command `0xb4`, and effective address `0x01e54800`.
PoolThread did not log a later HLE call. This means that the current blocker is
in the SPU event notification before the fixed PPU event-flag wait can return.
The mask repair is valid, but it is not the current stall repair.

The route did not map RSX IO range `0x700000`. It mapped only `0x50000000` and
`0x50100000`. Draw samples at flips 120 and 240 had zero draws. The flip-360
sample had 42 primitive-8 draws. The flip-480 sample had 158 primitive-8
draws. These are loading-screen quads, not correct 3D output. No crash, signal
11, task ELF load failure, or fatal marker occurred.

The near-limit guard stopped RPCSX after package silicon held at 65.4 C. The
highest package sample was 66.2 C. The PID was absent after the stop. No second
route ran in this thermal round.

A new default-off event census now records the SPU event notification result:

    debug.rpcsx.thor.spu_event_census=1

It records at most 32 events. Each record includes the event port, payload,
result code, queue ID, queue depth, PPU waiter state, mailbox counts, and SPU
state. It takes the queue lock only after the normal send operation returns.
It does not change mailbox or queue behavior.

The LFQueue route contract, Android debug build, and ARM64 APK contract passed.
The diagnostic APK is 116,130,605 bytes and has this SHA-256:

    CA1C628D1AC1D65BE6F499BB99F18C443358F51A0441607C10616B8DA371F045

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate before one bounded route. Correct 3D output and sustained 30 FPS are
still not proved.

## 48. The event-result probe is after the current boundary

The Thor refused strict gates at 36.1 C and 35.3 C. A later strict gate passed.
The no-launch installer used the Wi-Fi ADB transport because the USB transport
was not present. It verified this exact APK SHA-256 on the device:

    CA1C628D1AC1D65BE6F499BB99F18C443358F51A0441607C10616B8DA371F045

The post-install strict gate also passed. The evidence is in:

    20260828-161315-thor-input-strict-cool-gate
    20260828-161416-thor-input-strict-cool-gate
    20260828-161525-thor-input-strict-cool-gate
    20260828-161545-transformers-spu-event-census-install
    20260828-161602-thor-input-strict-cool-gate

One bounded route used the firmware LFQueue path, both selector repairs,
corrected atomic task selection, the event-mask fix, and all three censuses.
Its capture is:

    20260828-161630-thor-input-custom

The effective startup profile proves that
`debug.rpcsx.thor.spu_event_census=1` was active. The route did not record one
`Thor SPU EVENT` result. The result probe runs after the event queue send
returns. Therefore, this zero does not give the queue result. It proves that
the selected edgeZlib SPU did not reach that point.

The edgeZlib PC samples first moved through queue and decompression code at
PCs `0x093f8`, `0x04ef8`, `0x06780`, `0x05e34`, and `0x048c8`. The task then
updated event flag `0x01e54800`. Its GETLLAR at PC `0x08990` and PUTLLC at PC
`0x08be8` both completed. The next seven samples all had PC `0x0a4d8`, link
register `0x08ca8`, last MFC command `0xb4`, and effective address
`0x01e54800`.

Ghidra shows two writes in helper `0x0a4d8`. The first write sends the payload
to outbound mailbox channel 28. The second write sends the event command to
interrupt mailbox channel 30. A PC sample cannot separate these instructions
because both are in one translated block. The remaining boundary is now one
of these cases:

1. The outbound mailbox is full, so the first write waits.
2. The second write enters the event handler, but its queue send does not
   return.

The route did not map RSX IO range `0x700000`. It mapped only `0x50000000` and
`0x50100000`. Draw samples at flips 120 and 240 had zero draws. The flip-360
sample had 47 primitive-8 draws. The flip-480 sample had 163 primitive-8
draws. These are loading-screen quads, not correct 3D output. No crash, signal
11, task ELF load failure, or fatal marker occurred.

The near-limit guard stopped RPCSX after package silicon reached 65.4 C. The
PID was absent after the stop. No second route ran in this thermal round.

The bounded PC census now also records registers `r3`, `r4`, and `r5`, all
three mailbox counts, and the SPU state. The event census records entry into
each mailbox write only when edgeZlib is at PC `0x0a4d8`. These new records
run before any wait or event send. They do not change mailbox or event-queue
behavior.

The LFQueue route contract, Android debug build, and ARM64 APK contract passed.
The new diagnostic APK is 116,129,650 bytes and has this SHA-256:

    BCD331EC2978F129698F919972BFFDD33A800420F962186CBB25ACAF22AC008A

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate before one bounded route. Correct 3D output and sustained 30 FPS are
still not proved.

## 49. The edge task does not enter the mailbox handlers

A strict cool gate passed with package samples of 33.7 C, 33.7 C, and 34.1 C.
The installer then verified this exact APK SHA-256 on the device:

    BCD331EC2978F129698F919972BFFDD33A800420F962186CBB25ACAF22AC008A

The post-install strict cool gate passed with package samples of 34.1 C,
33.7 C, and 33.7 C. The evidence is in:

    20260828-162414-thor-input-strict-cool-gate
    20260828-162440-transformers-edge-mailbox-entry-install
    20260828-162455-thor-input-strict-cool-gate

One bounded route used the firmware LFQueue path, both selector repairs,
corrected atomic task selection, the event-mask fix, and all three censuses.
Its capture is:

    20260828-162516-thor-input-custom

The PoolThread called `cellSpursEventFlagWait` for event flag `0x01e54800`.
The edgeZlib PC census then moved through PCs `0x09f40`, `0x03940`, `0x04f5c`,
`0x066d0`, `0x05e34`, and `0x057ac`. Samples 27 through 41 all had PC
`0x0a4d8`, link register `0x08ca8`, `r3=0x00000011`, `r4=0`, and `r5=0`.
All of these samples had outbound, interrupt, and inbound mailbox counts of
zero.

The route did not record `Thor EDGE EVENT out-entry`, `Thor EDGE EVENT
intr-entry`, or `Thor SPU EVENT`. The first record is before the guest write
to outbound mailbox channel 28. Therefore, the outbound mailbox is not full,
and the event queue send is not the current wait point. The SPU does not enter
the first guest mailbox write handler. The current boundary is before guest
instruction `0x0a500` in the translated `0x0a4d8` block, or the SPU is
suspended at this block boundary.

The route did not map RSX IO range `0x700000`. It mapped only `0x50000000` and
`0x50100000`. Draw samples at flips 120 and 240 had zero draws. The flip-360
sample had 45 primitive-8 draws. The flip-480 sample had 161 primitive-8
draws, and the flip-600 sample had 281 primitive-8 draws. These are loading
quads, not correct 3D output. No crash, signal 11, task ELF load failure, or
fatal marker occurred.

The near-limit guard stopped RPCSX when package silicon reached 63.8 C. The
PID was absent after the stop. No second route ran in this thermal round.

The old SPU state field used an invalid format and argument type. Do not use
its recorded value. The census now reads the state through `toUnderlying()`.
It also records the SPU group state, the SPURS running count, JIT block count,
recovery count, failure count, block hash, and interpreter fallback state.
These fields will separate a scheduler suspension from a translated-block
stall. The mailbox entry and event-result records use the corrected state
format too.

The LFQueue route contract, Android debug build, and ARM64 APK contract passed.
The new diagnostic APK is 116,128,907 bytes and has this SHA-256:

    804EAA625B503F43D261BF4D3BF641180D1EDB2FAAB6A13E1220E9FC0EBE7366

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate before one bounded route. Correct 3D output and sustained 30 FPS are
still not proved.

## 50. Correction: the mailbox-entry filter used the block entry

Do not use section 49 to conclude that the edgeZlib task did not enter either
mailbox handler. The probe filter was wrong.

The LLVM WRCH emitter calls `update_pc()` before it calls `set_ch_value()`.
Therefore, the channel handler sees the address of the WRCH instruction, not
the entry address of its translated block. Ghidra puts the edgeZlib outbound
mailbox WRCH at PC `0x0a500` and its interrupt mailbox WRCH at PC `0x0a514`.
The old filter required PC `0x0a4d8`. It could not match either call. The zero
entry count does not show whether the guest entered these handlers.

The corrected probe requires the exact edgeZlib local-store signature. It
records the outbound handler only at PC `0x0a500` and the interrupt handler
only at PC `0x0a514`. The PC census still records the corrected SPU state,
group state, SPURS running count, JIT block counters, block hash, and
interpreter fallback state.

A strict cool gate refused the next device round at 40.9 C. Its capture is:

    20260828-163532-thor-input-strict-cool-gate

RPCSX was force-stopped, the display was put to sleep, and no APK was
installed. The LFQueue route contract, Android debug build, ARM64 APK
contract, and Git whitespace check passed. The corrected APK is 116,128,657
bytes and has this SHA-256:

    87E7C460241994B39C7268904C13ABCDED60FA23279B2D58DAF232FD53D29912

The next device work must start with a new strict cool gate. Install this exact
APK without a title launch. Run another strict cool gate before one bounded
route. The route must determine which exact mailbox handler is reached and use
the corrected state fields to distinguish a scheduler suspension from a JIT
stall. Correct 3D output and sustained 30 FPS are still not proved.

## 51. The edge event result has its own quota

The Thor passed a strict cool gate. The no-launch installer then verified APK
`87E7C460241994B39C7268904C13ABCDED60FA23279B2D58DAF232FD53D29912` and
kept RPCSX stopped. The evidence is in:

    20260828-164302-thor-input-strict-cool-gate
    20260828-164333-transformers-edge-wrch-corrected-install

The post-install strict gate refused at 35.3 C. A later gate refused at
36.5 C. RPCSX was force-stopped and no title route ran. The captures are:

    20260828-164357-thor-input-strict-cool-gate
    20260828-164436-thor-input-strict-cool-gate

The general event-result census can consume its 32-record quota on unrelated
SPU events. A separate bounded record now reports the result of the exact
edgeZlib interrupt mailbox handler at PC `0x0a514`. It does not depend on the
general quota. If its interrupt entry appears without its result, the event
queue send did not return. If both appear, the result code and queue ID are
available directly.

The LFQueue route contract, Android debug build, ARM64 APK contract, and Git
whitespace check passed. The new APK is 116,133,035 bytes and has this
SHA-256:

    5CC3FE43E189B42C044A8E0ED96C45FB654F7ED007EA0A114195C1C7AC67E058

This APK is not installed. It supersedes the installed `87E7...9912` APK.
The next device work must start with a new strict cool gate. Install this exact
APK without a title launch. Run another strict cool gate before one bounded
route. Correct 3D output and sustained 30 FPS are still not proved.

## 52. The scheduler is running when edgeZlib stops

Charging through the USB data cable kept the idle package near 40 C. The AYN
charging-separation setting was 0. It was set to 1 for this thermal round. This
changed the battery state from charging to discharging and let the Thor cool.
The first strict gate, no-launch install, and post-install strict gate passed.
The evidence is in:

    20260828-170108-thor-input-strict-cool-gate
    20260828-170133-transformers-edge-event-result-install
    20260828-170152-thor-input-strict-cool-gate

The installer verified this exact APK SHA-256 on the device:

    5CC3FE43E189B42C044A8E0ED96C45FB654F7ED007EA0A114195C1C7AC67E058

One bounded route used the firmware LFQueue path, both selector repairs,
atomic task selection, and all three censuses. Its capture is:

    20260828-170233-thor-input-custom

The PoolThread called `cellSpursEventFlagWait` for event flag `0x01e54800`.
SPU 5 then completed the event-flag GETLLAR at PC `0x08990` and PUTLLC at PC
`0x08be8`. Samples 22 through 27 show normal progress. The JIT block count
moved from 4 to 1714. Sample 28 reached PC `0x0a4d8` with link register
`0x08ca8`, `r3=0x00000011`, `r4=0`, and `r5=0`.

Samples 28 through 42 then stayed identical. The SPU state was 0, the thread
group state was 6, and the SPURS running count was 6. The block count and
recovery count both stayed at 1775. The failure count stayed at 20. The
interpreter fallback state stayed off. All three mailbox counts stayed at 0.

The exact event-entry counts were also zero:

    Thor EDGE EVENT out-entry=0
    Thor EDGE EVENT intr-entry=0
    Thor EDGE EVENT result=0
    Thor SPU EVENT=0

The corrected entry filters use WRCH PCs `0x0a500` and `0x0a514`. Therefore,
these zeros are valid. The task is runnable and its group is running, but no
new translated-module entry or mailbox handler occurs. This rules out a SPURS
scheduler suspension at this boundary. The active boundary is inside the
cached LLVM module with entry `0x08840`, before the event helper reaches its
first WRCH.

The route mapped RSX addresses `0x50000000` and `0x50100000`. It did not map
`0x70000000`. Draw samples had 0 calls at flips 120 and 240, 25 calls at flip
360, 145 calls at flip 480, and 261 calls at flip 600. All calls used primitive
8. These are loading quads, not correct 3D output. No fatal, signal 11, task
ELF load failure, or crash marker occurred.

The route started with three package samples of 34.9 C. The near-limit guard
stopped it at a package sample of 64.6 C. The highest junction sample was
74.3 C, below the 95 C junction limit. The PID was absent after the stop. No
second route ran in this thermal round.

After the round, RPCSX was force-stopped, the display was put to sleep, and
charging separation was restored to its original value of 0.

## 53. An exact event-helper interpreter handoff is ready

A new default-off diagnostic can bypass only the event helper at LS range
`0x0a4d8` through `0x0a51c`:

    debug.rpcsx.thor.edge_event_interp=1

The ARM64 compiler requires five exact guest opcodes. They include the helper
entry, branch, both WRCH instructions, and the return. A match saves all live
LLVM register values to the SPU context, starts the existing legacy
interpreter at `0x0a4d8`, and stops the fallback after PC leaves `0x0a520`.
The normal JIT gateway then resumes at the guest link register. The handoff
does not enable the global interpreter and does not interpret the edgeZlib
worker loop.

The gate changes emitted IR. The existing native-object key hashes the final
IR, so an object made with the gate off cannot satisfy a run with the gate on.
Entry and exit records show whether the exact helper ran and where it returned.
The route resets the property after success or failure.

The LFQueue route contract, Android debug build, ARM64 APK contract, and Git
whitespace check passed. The new diagnostic APK is 116,129,697 bytes and has
this SHA-256:

    033CCDA94908D9553ECF405E888E150CC0720DF719B3EB69E982F8B6A8ABCFBD

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate, then run one bounded route with `EdgeEventInterp=on`. The route must
show both WRCH entries, the event result, the interpreter exit at `0x08ca8`,
and progress past the current event-flag wait. Correct 3D output and sustained
30 FPS are still not proved.

## 54. The edge event fallback needs a runtime task-image guard

The Thor passed a strict cool gate. The no-launch installer then verified APK
`033CCDA94908D9553ECF405E888E150CC0720DF719B3EB69E982F8B6A8ABCFBD` and
kept RPCSX stopped. The post-install strict gate also passed. The evidence is
in:

    20260828-171827-thor-input-strict-cool-gate
    20260828-171848-transformers-edge-event-interp-install
    20260828-171904-thor-input-strict-cool-gate

The first route preflight refused to start at 35.3 C. No title process ran.
A later strict gate passed, and one bounded route ran with the event-helper
interpreter handoff enabled. The captures are:

    20260828-171936-thor-input-custom
    20260828-172006-thor-input-strict-cool-gate
    20260828-172033-thor-input-custom

The route recorded 16 interpreter entries and 16 exits. All entries came from
SPU 0 in `CellSpursKernel0`. Most exits were at PC `0x0a62c`, and one exit was
at PC `0x0a520`. None came from edgeZlib. The SPURS kernel contains enough of
the same instructions at the same addresses to satisfy the five-opcode
compile-time test. Therefore, this test is not a valid task guard.

The real edgeZlib task ran on SPU 2. It progressed through sample 24. Samples
25 through 34 then stayed at PC `0x0a4d8`, link register `0x08ca8`,
`r3=0x00000011`, `r4=0`, and `r5=0`. Its SPU state was 0, its thread group
state was 6, and its SPURS running count was 6. The block count stayed at
1801. The failure count stayed at 19. Its mailbox and interpreter counts all
stayed at 0. The exact event counts were also zero:

    Thor EDGE EVENT out-entry=0
    Thor EDGE EVENT intr-entry=0
    Thor EDGE EVENT result=0
    Thor SPU EVENT=0

The fallback mechanism can enter and leave the legacy interpreter on ARM64.
The broad guard selected the wrong SPU program, so this run did not test the
edgeZlib helper behavior.

Draw samples had 0 calls at flips 120 and 240, 58 calls at flip 360, and 174
calls at flip 480. All calls used primitive 8. The route mapped RSX addresses
`0x50000000` and `0x50100000`. It did not map `0x70000000`. No fatal, signal
11, task ELF load failure, LLVM verification failure, compilation failure, or
crash marker occurred. Correct 3D output was absent.

The thermal guard stopped the route at a package sample of 62.6 C. The highest
junction sample was 72.3 C. Both values were below their hard limits. The PID
was absent after the stop. Charging separation was restored to its original
value of 0, and the display was put to sleep.

The corrected compiler now tests the exact edgeZlib task image at runtime. At
PC `0x0a4d8`, it compares the 16 local-store bytes at `0x03000` with the live
edgeZlib signature. Only a match enters the interpreter handoff. The native
path continues unchanged for the SPURS kernel and all other SPU programs. This
runtime test also remains valid when a cached LLVM module serves more than one
SPU program.

The LFQueue route contract, Android debug build, ARM64 APK contract, and Git
whitespace check passed. The corrected APK is 116,130,961 bytes and has this
SHA-256:

    636329905E6011C515C217F30B6FF9834F67E2EBCF28F83BC07C77ECB2E09D7A

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate, then run one bounded route with `EdgeEventInterp=on`. The route must
show no interpreter entries from `CellSpursKernel0`, an edgeZlib entry with
link register `0x08ca8`, and progress through both WRCH operations. Correct 3D
output and sustained 30 FPS are still not proved.

## 55. The cached edge module does not contain the new guard

The Thor passed a strict cool gate. The no-launch installer verified APK
`636329905E6011C515C217F30B6FF9834F67E2EBCF28F83BC07C77ECB2E09D7A` and
kept RPCSX stopped. The post-install strict gate also passed. The evidence is
in:

    20260828-172812-thor-input-strict-cool-gate
    20260828-172832-transformers-edge-event-runtime-install
    20260828-172852-thor-input-strict-cool-gate

One bounded route then used the firmware LFQueue path, both selector repairs,
atomic task selection, and the event-helper gate. Its capture is:

    20260828-172929-thor-input-custom

The route loaded this native object for the edgeZlib worker module:

    __spu-0x08840-CbaEkA2fhvGi5ZwZxXemp3AdpxXu-KxMSFEwK0U1M54tfsa4f3AbhPg9t.obj

Both earlier routes loaded the same object name. The object key did not change
because the analyser did not emit the indirect target at PC `0x0a4d8` into
this module. Therefore, the LLVM-level guard is absent from the object. The
edge event interpreter, PC census, mailbox entries, and event results all had
zero records in this run. The edgeZlib image was not resident during a timer
sample, and the route did not test the helper fallback.

The edgeZlib task did run briefly on SPU 0. It completed GETLLAR at PC
`0x0954c` and PUTLLC at PC `0x098b8`, then returned to the SPURS kernel before
the first PC census tick. This differs from the prior runs where the task
continued to PC `0x0a4d8`. Treat the longer progress as scheduler timing, not
as proof that the LLVM guard fixed the helper.

The frame counter stayed close to the title cap after startup. Four consecutive
10-second samples reported 29.5, 29.4, 29.4, and 29.5 FPS. The draw census
reached 1,680 flips and 1,342 draw calls. All calls used primitive 8. The
captured frame was a flat green image with the performance overlay, not correct
3D output. The displayed instantaneous rate was 28.89 FPS. No
`0x70000000` RSX map, fatal, signal 11, LLVM verification failure, compilation
failure, or crash marker occurred.

The thermal guard stopped the route at a silicon sample of 67.4 C, below the
72 C hard limit. The highest junction sample was 76.3 C, below the 95 C
junction limit. RPCSX was force-stopped. Charging separation was restored to
its original value of 0, and the display was put to sleep.

The next diagnostic catches PC `0x0a4d8` in the shared ARM64 dispatcher before
native-object lookup. It requires the same exact 16-byte edgeZlib task-image
signature. It then runs only the event helper through the legacy interpreter
and returns to the JIT at the guest link register. It does not invalidate the
global SPU native-object cache.

The LFQueue route contract, Android debug build, ARM64 APK contract, and Git
whitespace check passed. The dispatcher diagnostic APK is 116,131,666 bytes
and has this SHA-256:

    7BAA5BEB53392A2E998C830DBE8C62490AC9AD7B51E63D2E6457F210C454A2B4

This APK is not installed. The next device work must start with a new strict
cool gate. Install this exact APK without a title launch. Run another strict
cool gate, then run one bounded route with `EdgeEventInterp=on`. The route must
show a dispatcher interpreter entry from edgeZlib, both WRCH operations, and
an event result. Correct 3D output and sustained 30 FPS with correct output are
still not proved.

## 56. The exact edge event helper now returns

The Thor passed a strict cool gate. The no-launch installer verified APK
`7BAA5BEB53392A2E998C830DBE8C62490AC9AD7B51E63D2E6457F210C454A2B4` and
kept RPCSX stopped. The post-install strict gate also passed. The evidence is
in:

    20260828-173805-thor-input-strict-cool-gate
    20260828-173827-transformers-edge-event-dispatch-install
    20260828-173845-thor-input-strict-cool-gate

One bounded route then used the firmware LFQueue path, both selector repairs,
atomic task selection, and the dispatcher event-helper handoff. Its capture is:

    20260828-173914-thor-input-custom

The exact edgeZlib task-image guard matched four times. Each helper entry had
PC `0x0a4d8`, link register `0x08ca8`, `r3=0x11`, `r4=0`, and `r5=0`. Each
run wrote outbound mailbox value 0 at PC `0x0a500`, wrote interrupt mailbox
value `0x51000000` at PC `0x0a514`, and sent event port 17 to queue
`0x8d005600`. Each event returned 0. Each interpreter handoff then left at PC
`0x08ca8` with `r3=0`.

The PoolThread entered `cellSpursEventFlagWait` again after each event. The
edgeZlib worker later reached PC `0x0324c` with a block count of 1,781. Thus,
the helper is no longer frozen at PC `0x0a4d8`: the event is sent, the helper
returns, and the task continues.

After startup, five consecutive 10-second samples reported 29.6, 29.4, 29.4,
29.5, and 29.6 FPS. The draw census reached 1,920 flips and 1,589 draw calls.
All calls used primitive 8. The captured frame was still flat green, with an
instantaneous rate of 29.21 FPS. The route did not produce a primitive 5 draw
or an RSX map at `0x70000000`. Therefore, the measured event helper works and
the title runs at its frame-rate cap, but correct 3D output is not proved.

The route also showed the next stable boundary. The title failed two attempts
to create the `0x01765800` Bink/render task because the supplied local-store
pattern used the SPURS management area. The existing default-off task
attribute repair can create this task, but its old tests predate the selector,
task-selection, failed-block, LFQueue, and event-helper repairs. The render
route now has a default-off `TaskAttrFix` switch so this exact combination can
be tested without a new APK.

The thermal guard stopped the route at a silicon sample of 66.2 C, below the
72 C hard limit. The highest junction sample was 77.1 C, below the 95 C
junction limit. No fatal, signal 11, task ELF load failure, LLVM verification
failure, compilation failure, or crash marker occurred. RPCSX was force-
stopped. Charging separation was restored to its original value of 0, and the
display was put to sleep.

## 57. The attribute repair creates the Bink task and enters a slow state

Two route preflights refused to start because one silicon sample was 35.3 C.
No title process ran in these attempts. Their captures are:

    20260828-174542-thor-input-custom
    20260828-174645-thor-input-custom

The Thor then cooled without a workload. One bounded route used the firmware
LFQueue path, both selector repairs, atomic task selection, the dispatcher
event-helper handoff, and the task attribute repair. Its capture is:

    20260828-174825-thor-input-custom

The route used APK
`7BAA5BEB53392A2E998C830DBE8C62490AC9AD7B51E63D2E6457F210C454A2B4`.
The active profile recorded `task_attr_fix=1` and
`edge_event_interp=1`.

The attribute repair resolved context `0x1094ba00`, with size `0x1c00`. It
synthesized this three-block local-store save pattern:

    00000000000000000000000000000007

`cellSpursCreateTaskWithAttribute` then created the task from image
`0x01765800`, with size `0x191e8`. Workload 7 and taskset `0x01f73f00`
dispatched on SPU 1. The task completed GETLLAR at PC `0x13384` and PUTLLC at
PC `0x1360c` for event flag `0x01f7d580`. It then returned to the SPURS system
service at PC `0x00808`. Thus, task creation works, and the Bink task does not
stay in its first atomic operation.

The render producer stopped after queue push 1,088. It then created the Bink
taskset, mapped RSX I/O addresses `0x500000` and `0x600000`, and set event bits
`0xffff`. The Bink task consumed that event. The producer did not record a
later queue push in the bounded window.

The GCMX task continued its queue polling loop at PC `0x13dcc`, for effective
address `0x1030e400`. It reached 23,552 GETLLAR operations by 19.32 seconds.
This loop is not new. The repair-off baseline reached 26,176 operations at the
same PC by 19.98 seconds and later sustained the title frame cap. The new
boundary is the render producer after Bink task setup, not the GCMX GETLLAR
instruction.

The route recorded 34 frames in one 10-second sample, or 3.40 FPS. Draw
samples at flips 120 and 240 both had zero calls. The route did not record a
primitive 5 draw, a primitive 8 draw, an RSX map at `0x70000000`, or an edge
event-helper call before the stop. No screenshot was taken because the
thermal guard stopped the route during its wait stage. Correct 3D output is
not proved.

The thermal guard stopped the route after a sustained near-limit check.
Silicon samples in the check were 62.2 C, 63.0 C, 65.0 C, and 64.6 C. They
were below the 72 C hard limit. The highest junction sample was 76.7 C, below
the 95 C junction limit. RPCSX was force-stopped, and its PID was absent.
Direct device checks showed that the task attribute, event-helper, draw,
SPU-PC, and SPU-event properties were all reset to 0. The display was put to
sleep and reported `Dozing`.

The task attribute repair stays off by default. The next diagnostic must find
the RenderingThread call after the event flag set and must record the Bink
task request state. A new Thor run is not useful until this bounded probe is
ready and the device passes a new strict cool gate.
