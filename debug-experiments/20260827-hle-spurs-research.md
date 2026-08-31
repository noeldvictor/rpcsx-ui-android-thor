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
PC `0x1360c` for event flag `0x01f7d580`. It then entered the SPURS system
service at PC `0x00808`. Later analysis showed that this path parks the task in
`WAIT_SIGNAL`. Thus, task creation works, but the Bink task does not receive
its first event.

The render producer stopped after queue push 1,088. It then created the Bink
taskset, mapped RSX I/O addresses `0x500000` and `0x600000`, and set event bits
`0xffff`. The HLE function logged the call before its permission check, then
rejected it. The event bits stayed clear. The producer did not record a later
queue push in the bounded window.

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

## 58. The PPU event setter rejects the Bink flag in the wrong direction

The exact Bink local-store capture is 262,144 bytes and has this SHA-256:

    F74407A529BD036D30D25D6D7E809A0702D01C32BB6A14F2491FA58E66AA7356

A headless Ghidra import used the `SPU:BE:128:default` processor at base 0.
The function at PC `0x13210` issues GETLLAR at `0x13384` and PUTLLC at
`0x1360c`. If the requested event is present, the branch at `0x13618` returns
0. Otherwise, the call at `0x13670` selects SPURS task system call 2,
`WAIT_SIGNAL`. The device trace returned to the SPURS system service after
PUTLLC. Therefore, the task took the wait path.

The Bink event flag has direction 2, `CELL_SPURS_EVENT_FLAG_PPU2SPU`. The PPU
called `cellSpursEventFlagSet` with bits `0xffff` before the task waited. The
function permitted only `CELL_SPURS_EVENT_FLAG_SPU2PPU` and
`CELL_SPURS_EVENT_FLAG_ANY2ANY`. It returned `CELL_SPURS_TASK_ERROR_PERM`
before its reservation operation, so it did not set the event bits. Its Thor
diagnostic was before the permission check and hid this return.

Official RPCS3 master commit
`98906eb0357823aa84997a1ce06406a66fde3722` from August 28, 2026 has the same
direction check. The local repair permits `PPU2SPU` and `ANY2ANY` in the
PPU-side Set function. It does not change the PPU-side Wait direction. The
Thor event diagnostic now runs after the permission check and records the
accepted direction.

The SPURS event-flag contract checks both allowed Set directions and rejects
the old direction expression. The event-flag contract, Transformers HLE route
contract, and Git whitespace check pass. Correct 3D output and sustained 30
FPS with correct output still require one guarded device run.

## 59. The real taskset module makes every request atomic

The Thor passed the install gates for APK
`502BC47D3B0AA115218C125F42F9E312E452229ECA5F4D2106187C89112730E1`.
One bounded route used the PPU event-set repair and is in:

    20260828-180956-thor-input-custom

The Bink event flag accepted PPU sets. The task performed its event wait twice,
and `_cellSpursSendSignal` signalled task 0 in workload 7. Queue pushes then
resumed, and RSX recorded two primitive 8 draws. The title did not produce
correct 3D output or a verified 30 FPS result.

After the second event, workload 7 entered a dispatch storm. Its dispatch
counter reached 1,251,136 in approximately 1.8 seconds. The taskset entry
counter reached 1,249,280. Only four task resume records occurred in the full
run, all before the Bink task started. Thus, the hot loop was repeated taskset
entry with no task resume. The thermal guard stopped the route at a silicon
sample of 63 C, below the 72 C hard limit. RPCSX was force-stopped.

The taskset policy image has this SHA-256:

    4AAB9A10A61D71B6CE8A51C7327D779067011C56D87398802260C096A249AF68

Headless Ghidra used `SPU:BE:128:default` at base 0. The dispatcher at
`0x1778` calls request 5 at `0x179c`. If no task is selected, the branch at
`0x17a8` goes to `0x1c50`, which calls the module-exit path at `0x13b0`.
This behavior agrees with the HLE no-task exit.

The request handler at `0x0e40` uses GETLLAR for the 128-byte taskset line at
`0x0e90`. It applies the selected request, uses PUTLLC at `0x1238`, and retries
from `0x1240` when the reservation fails. The syscall arms for request -1
`POLL_SIGNAL` and request 2 `WAIT_SIGNAL` both use this handler. The same
handler covers all eight taskset requests.

The HLE repair previously used a reservation only for `SELECT_TASK`. Other
requests wrote the taskset fields separately. A PPU signal could race
`WAIT_SIGNAL` and leave the task bitmaps or ready count inconsistent. The new
guarded candidate uses one reservation transaction for all eight request
types. It copies the committed taskset line back to local store. A bounded
exception probe records the full first bitmap words and contention values if
the scheduler has a nonzero ready count but cannot select a task. The route
property stays off by default. The atomic taskset request contract, event-flag
contract, HLE route contract, and Git whitespace check pass.

The Android ARM64 build passed. The exact diagnostic APK is 116,134,309 bytes
and has this SHA-256:

    743D48A47B17238EF1FEDCC01EE5EDAA15BE288E6A799DEA16A68D7D51E2378E

The ARM64 APK contract passed. Two independent strict gates refused device
work before installation or title launch. Their captures are:

    20260828-183112-thor-input-strict-cool-gate
    20260828-183552-thor-input-strict-cool-gate

The first gate read 38.5 C at its first silicon sample. The second gate read
38.9 C and then 40.1 C after the stop. The 35 C launch limit therefore remains
in force. RPCSX stayed stopped. The candidate needs a later strict cool gate,
an exact no-launch install, a post-install cool gate, and one bounded route.

## 60. Atomic taskset requests remove the dispatch storm

The Thor later passed the strict cool gate in:

    20260828-184620-thor-input-strict-cool-gate

The exact APK was installed without a launch in:

    20260828-184642-transformers-atomic-requests-install

The installed APK hash matched
`743D48A47B17238EF1FEDCC01EE5EDAA15BE288E6A799DEA16A68D7D51E2378E`.
The device then passed the post-install strict cool gate in:

    20260828-184657-thor-input-strict-cool-gate

One bounded Transformers route is in:

    20260828-184719-thor-input-custom

The all-request atomic repair removed the taskset dispatch storm. The prior
route recorded 1,251,136 workload-dispatch entries and 1,249,280 taskset
entries. This route recorded one workload-dispatch line at counter 0 and four
taskset-entry lines. It recorded no `TASKSET IDLE-READY` exception, invalid
taskset state, fatal error, signal 11, or native crash.

The Bink task completed its second event reservation. The existing Ghidra
listing for the exact Bink local-store image shows that PC `0x13720` writes the
GETLLAR command and PC `0x13774` writes the PUTLLC command. The trace reached
both PCs after the second accepted event set and signal. Queue pushes then
advanced through sampled counter 832. RSX recorded two primitive 8 draws.

This result does not prove correct 3D output. The route recorded 25 performance
frames in 10 seconds, or 2.50 FPS. It did not record the expected primitive 5
draw or the `0x70000000` mapping. The thermal guard stopped the route before the
screenshot. The final confirmed package-silicon sample was 63.8 C. The highest
CPU-junction sample was 74.3 C. Both were below their 72 C and 95 C hard limits.
RPCSX was force-stopped, and its PID was absent.

The next route enables the bounded PPU PC census and takes the screenshot before
the thread snapshot. It runs while the observed package-silicon temperature is
below 70 C. It keeps the 72 C hard limit and the 95 C junction limit. The route
contract, atomic taskset contract, event-flag contract, and Git whitespace
check pass. The next device run must start with a new strict cool gate.

## 61. Ghidra identifies the real task context descriptor

The first task-pattern interpretation was wrong. It treated the start of the
attribute buffer as the caller pattern. Captures
`20260828-193016-thor-input-custom` and
`20260828-194030-thor-input-custom` rejected patterns with the wrong block
counts and reproduced the Bink task fault. Packing the saved local-store
blocks did not correct the source address.

A raw Ghidra import of the decrypted BLUS30357 PPU executable used the guest
address minus `0x10000` as the file address. The RenderingThread caller sets
only registers r3 through r8 for `_cellSpursTaskAttributeInitialize`. Registers
r9 and r10 are stale. The caller builds the local-store pattern at r18 and
stores a 12-byte descriptor at r7:

    offset 0: context effective address
    offset 4: context size
    offset 8: local-store pattern effective address

The HLE initializer now reads the third descriptor field. It accepts the
pattern only when the address is aligned and readable, the set-bit count
matches the allocated context blocks, and no SPURS management bit is set. The
fallback stays behind `debug.rpcsx.thor.task_attr_fix`. The task-attribute
pattern, task-context layout, and Transformers HLE route contracts pass.

## 62. The caller pattern removes the Bink resume fault

The corrected task descriptor ran in:

    20260828-201235-thor-input-custom

The Bink task used this exact three-block pattern:

    00000000000001800000000000000001

It selects local-store blocks 55, 56, and 127. The capture recorded no access
violation, no old PC `0x32a8` occurrence, and no zero-address PUTLLC fault. The
renderer was still waiting in its short Bink producer poll, and the bounded
window recorded no RSX draw. Thus, this capture removes the old context-resume
fault but does not by itself prove frame output.

## 63. The corrected task reaches the RSX draw path

A bounded SPURS trace ran in:

    20260828-202011-thor-input-custom

The Bink task started with the exact caller pattern. RSX draws began and
reached 154 by guest time 23.49 seconds. The capture recorded no access
violation, old PC `0x32a8` loop, or zero-address PUTLLC fault. Its 3.90 FPS
sample includes startup and active diagnostic work, so it is not a speed
result.

A less verbose route ran in:

    20260828-202244-thor-input-custom

The active-draw screenshot reported 29.26 FPS. It was black, and the route did
not prove a geometry draw or an RSX mapping at `0x70000000`. The Bink taskset
shut down and was created again with the same correct pattern. No prior memory
fault returned.

An extended route in `20260828-202635-thor-input-custom` stopped at 71.9 C
before its first draw. The guard stopped RPCSX below the 72 C hard limit. That
capture has no render credit.

## 64. Live Bink planes reach the renderer

The bounded RSX input sampler was built in exact ARM64 APK:

    F73E46D978AA0BE928AD2496EBA1AE92276844E52958B9E880F61A3286AE7227

The ARM64 APK contract and the focused HLE contracts pass. The exact APK was
installed without a launch, its on-device hash matched, and the RPCSX PID was
absent after installation.

The texture proof is in:

    20260828-203517-thor-input-custom

The first 16 quad draws used 48 mapped texture planes. Every strided plane
sample had 64 nonzero bytes out of 64. The 1280 by 720 Y planes started with
`0x10`, and the two 640 by 360 chroma planes started with `0x80`. More
importantly, the sample hashes changed across later frames and across the two
buffer sets. The decode output is therefore live data, not an empty Bink
queue or an unmapped texture.

The draw census reached 154 quads. The second screenshot showed the visible
Transformers loading emblem at 28.98 FPS. The capture recorded no access
violation, old PC `0x32a8` loop, or zero-address PUTLLC fault. The runtime guard
stopped RPCSX at 70.3 C, below the 72 C hard limit. This result proves that the
HLE task produces live Bink planes, the RSX consumes them, and the title
advances to visible loading output.

## 65. The lean HLE boundary reaches the 30 FPS cap

The normal route now leaves the draw, SPU-PC, SPU-event, and PPU-PC censuses
off. `RuntimeCensus=on` can enable them for a bounded diagnosis. The lean route
ran in:

    20260828-203910-thor-input-custom

The second screenshot reported 30.01 FPS, with 12.1% PPU, 8.3% SPU, 4.0% RSX,
and 24.3% total CPU use. That screenshot was a black transition frame, so it
does not prove correct 3D output. The route recorded no access violation and
no enabled census output.

The device started at 40.9 C. Stored startup heat still reached the 70.3 C
runtime stop during the extra downstream wait. RPCSX stopped below the 72 C
hard limit, and the post-stop sample was 53.8 C. Removing solved census work
therefore reduces log volume but does not remove the startup thermal limit.

The standard proof route now ends after the 12-second active-draw boundary.
HLE task creation, event delivery, task resume, live Bink texture production,
visible loading output, and an instantaneous 30 FPS result are proved. Correct
3D output and sustained 30 FPS are not proved. The next work must reduce
startup CPU heat or reach the first map with a shorter state-gated route.

## 66. The thermal guard now runs on the Thor

The route now installs a fixed-sensor guard on the device before title launch.
It reads the 15 CPU-subsystem, GPU-subsystem, DDR, SoC, and crystal zones, the
14 CPU-junction zones, the battery zone, and the hardware skin sensor every two
seconds. The host preflight first proves that the device list matches the full
sensor source set. Runtime checks no longer use repeated host ADB walks.

The silicon early-stop value is 70 C. The silicon hard limit is 72 C, and the
CPU-junction hard limit is 95 C. The standalone cold-start gate now takes one
sample. A silicon value below 70 C passes, and a value at or above 70 C fails.
The exact no-launch installer accepts the same one-sample gate. Host contracts
cover 69.9 C as a pass and 70.0 C as a failure.

The long bounded route in `20260828-211905-thor-input-custom` started at
46.2 C silicon. Short resume and pause windows stayed below the launch limit
until the last window. The device guard stopped RPCSX at 71.1 C, below the
72 C hard limit. The route did not reach a correct 3D frame.

## 67. Pausing now stops the HLE SPURS service loops

Before the repair, a paused title left five HLE SPURS system-service callbacks
near one full host core each. The guest was paused, but each callback remained
inside a host C++ loop and did not return to the normal SPU state check.

The two system-service loops now call `spu.check_state()` and return when the
thread state requests a pause. Exact APK
`DF621EAE0FCE69428288118EA220CB23F1DA9BD8F74D73672052FDFE32AD9C4A`
proved the repair in `20260828-211745-thor-input-custom`. All 78 threads were
sleeping after the pause. The process used 0.020 host cores, and silicon was
46.6 C. This makes pause-and-inspect routes thermally bounded. It does not
prove gameplay output.

## 68. A zero LS pattern wastes the startup window

The route in `20260828-213831-thor-input-custom` used exact diagnostic APK
`4E9DA3495861F5BA5D12202F6B00F1B5598EED7DE9249D6FBF2DF9063DB95BB5`.
The APK is 116,136,811 bytes. The no-launch install and on-device hash proof are
in `20260828-213808-transformers-savectx-pattern-install`.

The diagnostic identified a separate task before Bink. It had 122 allocated
local-store save blocks but an all-zero LS pattern. Its context save failed
because stack block 127 was not selected. The task retried the failed save more
than 12,288 times in the bounded window. The Bink task was created later and
kept its correct caller pattern:

    00000000000001800000000000000001

Thus, the Bink bit order is not the failure. The earlier zero-pattern task is a
separate source of wasted CPU time.

One successor route enabled the existing bounded attribute fallback. Capture
`20260828-214025-thor-input-custom` synthesized the full 122-block task-area
pattern for the earlier task:

    03ffffffffffffffffffffffffffffff

It still kept the exact three-block Bink caller pattern. No `SAVECTX FAIL`,
unknown STOP, access violation, native fatal, or signal 11 occurred. The device
guard stopped RPCSX at 71.5 C while the second screenshot was being checked;
the missing PID was therefore a guard stop, not a native crash.

The fallback-off black boundary reported 25.20 FPS and 50.7% total CPU in
`20260828-213831-thor-input-custom`. The fallback-on black boundary reported
27.84 FPS and 48.7% total CPU in `20260828-214025-thor-input-custom`. The cache
progress frames differed, so these two instantaneous values are directional
evidence, not a sustained speed comparison. Removing the repeated save failure
is structural evidence. The Transformers HLE route now enables the fallback by
default. Correct 3D output and sustained 30 FPS are still not proved.

## 69. The cached PPU reservation time caused exact 128 failures

The HLE route in `20260828-222314-thor-input-custom` enabled the SPURS yield
fast path. The last 10-second sample recorded 281,608 conditional-store
failures with an exact stale difference of 128. It recorded only eight other
failures. This ratio identified a reservation-time error, not normal access
contention.

ARMSX3 commit `ca3b755fd` keeps the cached reservation time after a successful
conditional store. The RPCSX code already added 128 after a successful store,
but the next cached reservation subtracted 128. The next store therefore used
the old reservation generation and failed when no other thread changed the
line.

The new Android property is:

    debug.rpcsx.thor.ppu_cached_rtime_fix=1

The property keeps the generation that the successful store recorded. The
change is off by default in the core and on by default in the Transformers HLE
route. Exact APK
`45495E4027789740D3D47BAAED48BE60C4BE2E5EDCE1E49A08B12106AD014F03`
ran in `20260828-223303-thor-input-custom`. All reported stale-128 and other
conditional-store failure counts stayed at zero. The log reached Bink setup.
It had no save-context failure, access violation, native fatal error, or signal
fault.

The first screenshot was still at SPU cache module 63 of 64. The second
screenshot was a black transition frame at 26.82 FPS. The route started at
45.8 C silicon and reached 68.7 C before the macro stopped RPCSX. The device
guard did not have to stop the process. This run proves the reservation-time
repair. It does not prove correct 3D output or sustained 30 FPS.

## 70. The fixed HLE route shows the legal frame near 30 FPS

The paused route in `20260828-223626-thor-input-custom` used the cached PPU
reservation repair and the SPURS yield fast path. Short resume windows produced
correct Unreal, PhysX, and legal screens. Two visible frames reported 29.98 FPS
and 29.36 FPS. The final counter had 11 exact stale-128 failures and 20 other
failures. These small counts have the normal contention ratio. The old exact
128 failure storm did not return.

The route did not advance past the legal movie during the bounded resume
windows. Thus, the yield fast path does not have a title-advance proof. The HLE
route keeps this experiment off by default. It can still be enabled with
`-YieldFastPath on`. The route also resets its property after the run.

The comparison route `20260828-224150-thor-input-custom` used the normal yield
path. A 10-second continuous resume window caused the device guard to stop
RPCSX. The stop occurred before 72 C. The post-stop launcher screenshot has no
visual credit. Correct gameplay and sustained 30 FPS are still not proved.

## 71. Cooled slices keep the HLE route below 72 C

Ghidra mapped the paused main-thread PC `0x00349364` to a timebase wait helper.
The helper has 17 direct callers. The live sample was taken while RPCSX was
paused, so this address is not evidence of a new HLE deadlock. The focused
PowerPC call finder is in `tools/ghidra_scripts/FindPowerPcCalls.java`.

The no-input control is in `20260828-230613-thor-input-custom`. It used eight
4-second resume windows with 8-second cooling pauses. The legal frame stayed
valid. Live transition readouts ranged from 30.29 to 31.59 FPS. Fixed silicon
peaked at 68.7 C, and the normal macro stop ended the run. The conditional-
store counter ended at five exact stale-128 failures and nine other failures.
The old exact-128 failure storm did not return.

The input macro now accepts `resume`, so a bounded route can pause, cool, and
resume without an external manual call. The Transformers route uses zero
runtime stop headroom. Its device guard therefore stops at the documented
72 C silicon limit. The launch gate is unchanged: one valid sample below 70 C
can start, and a sample at or above 70 C cannot start.

The no-input route did not leave the legal frame. A single START press after a
visually checked legal frame is the next correctness test. Correct gameplay and
sustained 30 FPS are still not proved.

## 72. The comparison route disabled the proved HLE repair stack

The HLE/LLE comparison used exact APK
`45495E4027789740D3D47BAAED48BE60C4BE2E5EDCE1E49A08B12106AD014F03`.
The HLE capture is in:

    20260828-232440-thor-input-custom

Its effective startup profile set these four required HLE routes to zero:

    debug.rpcsx.thor.lfq_any2any=0
    debug.rpcsx.thor.spurs_sel_cond_fix=0
    debug.rpcsx.thor.spurs_signal_fix=0
    debug.rpcsx.thor.taskset_select_atomic=0
    debug.rpcsx.thor.edge_event_interp=0

The loader request then reproduced the boundary from sections 39 through 56.
Its pending count stayed at one. The active IO completion word stayed at one,
and the AsyncIOSystem thread stayed in the active-list sleep path. The LLE
control in `20260828-232750-thor-input-custom` began with the same request. It
retired that request between guest seconds 37 and 47 and moved to the idle IO
wait. This is not evidence of a new loader defect. The comparison accidentally
restored the old incomplete HLE configuration.

The proved HLE captures used value one for all four repair groups. Capture
`20260828-203517-thor-input-custom` produced live Bink texture planes and a
visible Transformers loading frame at 28.98 FPS. Capture
`20260828-203910-thor-input-custom` reached the 30 FPS cap. Both effective
profiles record the LFQueue route, paired selector repairs, atomic task-set
requests, and exact edge event handoff as enabled.

The Transformers render route now enables this proved HLE repair stack by
default. An explicit `off` value can still run a regression control. LLE mode
forces the LFQueue, selector, task-set, and edge event routes off so the LLE
control cannot use the title-specific SPU handoff.

The route contract, PowerShell parse, and Git whitespace check pass. This is a
host route correction. It does not change the APK. The next hardware action is
one default HLE route with the installed exact APK. The cold-start gate permits
one fixed-silicon sample below 70 C and refuses a sample at or above 70 C. The
runtime guard still stops before 72 C silicon or 95 C junction.

## 73. Normal suspend state must not enter the HLE pause path

Commit `fc700406a` made both long HLE SPURS service loops call
`cpu_thread::check_state()` for every nonzero thread state. A nonzero state is
not limited to a user pause or a stop. It also includes normal scheduler
signals, suspend state, pending work, memory work, yield, and preemption.

The all-repair HLE capture `20260828-233804-thor-input-custom` and its cached-
reservation-off control `20260828-234247-thor-input-custom` both created the
Bink task and set event flag `0x1f7d580`. Neither capture dispatched workload
7, and both kept the RSX draw count at zero. Thus, the PPU reservation repair
was not the cause of this scheduler boundary.

Exact APK
`B01DA8912F501A926E10F74FA06BF8A233DB8F32F2DD402F11C1299AE96759F9`
limited the service-loop check to the existing `is_paused` and `is_stopped`
helpers plus the internal pause bit. Capture
`20260828-235228-thor-input-custom` still did not dispatch workload 7. The
remaining `suspend` and internal pause bits are also used during normal RPCSX
coordination.

Exact APK
`AAA0A8F34F3E4ED91E590D5F08DC75B3D7F0D4BC7EB78AA3DCF08988313CACD9`
checks only stop state, `dbg_global_pause`, and `dbg_pause`. Android Pause sets
`dbg_global_pause` on all PPU and SPU threads. The change therefore keeps the
device pause action without sending normal SPURS scheduler state through the
full CPU state machine.

Capture `20260828-235658-thor-input-custom` proves the repaired boundary.
Workload 7 dispatched at guest time 11.376 seconds, the Bink task started, and
the event flag arrived at 11.380 seconds. After the route resumed, workload 7
dispatched again. Two RSX draws used mapped nonzero Y, Cr, and Cb planes. The
first paused screenshot reported 1.4 percent total CPU, so the HLE loops still
honor the global pause.

This is a scheduler repair, not a complete render proof. Only two draws were
recorded after resume, both screenshots were black, and no later draw census
sample was available before the second pause. The next run must keep the route
uninterrupted through the first Bink draw sequence. It must also compare the
cached PPU reservation repair off because that change followed the last known
good HLE build.

## 74. Active SPURS scheduling must not read the pause state

The reservation-off capture `20260829-000242-thor-input-custom` reached the
Bink task with the scheduler repair from section 73. It did not produce a draw
before guest second 16, and its final performance sample recorded 281,638
exact stale-128 conditional-store failures and nine other failures. This
reproduces the old reservation failure storm. The cached PPU reservation repair
is necessary and stays enabled.

The remaining pause check still loaded the SPU thread state on every pass
through the active HLE system-service loop. The successor removes that load
from active scheduling. It checks debug pause and stop only in the idle
no-work branch, immediately before the existing 1 ms sleep. Active work returns
to the normal SPU dispatcher, which already processes thread state.

Exact APK
`A39E7A9C835E4C2EBE65F54FAC7D69DAB25F5C31CE3CB03F7DB406970C81C1E6`
proves that the active-loop load affected the event chain. The uninterrupted
capture `20260829-000733-thor-input-custom` dispatched Bink workload 7 at
11.826 seconds and again at 18.300 seconds. Event flag `0x1f7d580` arrived for
both dispatches. Two mapped Bink texture draws followed at 18.381 and 18.413
seconds. The cached reservation counter ended at five stale-128 failures and
13 other failures, not the failed off-route storm. No save-context failure,
access violation, signal fault, or native fatal error occurred.

The device guard stopped that run at 72.7 C fixed silicon before a screenshot.
The cooled capture `20260829-000850-thor-input-custom` proves that the new idle
check still pauses RPCSX: 10-second paused performance samples were 0.5 and 0.2
percent total CPU. Its fixed-silicon peak was 67.8 C. However, the first pause
occurred just after the first Bink event and before workload 7 won an SPU. That
changed the scheduler race, so the route did not produce a draw.

The live-frame retry `20260829-001101-thor-input-custom` started at 47.0 C and
was stopped by the guard at 74.7 C during cold compilation, before its first
screenshot. The next proof must keep the active-loop repair and cached PPU
reservation repair. It must disable optional runtime census overhead and take
live screenshots without an intermediate pause.

## 75. A workload signal notification reached Bink once

Commit `5f0b6e74c` adds the same `vm::light_op<true>` notification that the
upstream signal route uses. The first exact-APK run is in
`20260829-004628-thor-input-custom`. Workload 7 dispatched soon after its PPU
signal. The route showed the Unreal, PhysX, and legal frames. A paused legal
frame reported 27.88 FPS. Fixed silicon peaked at 67.8 C.

The repeat in `20260829-005019-thor-input-custom` did not give the same result.
All five available SPUs took workload 6. Workload 7 did not get an SPU. The
notification repair is necessary, but it does not reserve an SPU for Bink.

## 76. Transformers keeps one SPU free for Bink

Commit `57dbf4061` adds a BLUS30357-only workload-6 contention cap. The first
version also matched a policy-module address. That address changed between
runs. Commit `21ecbf983` removes the unstable address check. The final match is
BLUS30357, workload 6, module size `0x4000`, minimum contention 1, and requested
maximum contention 5. It changes only that maximum from 5 to 4.

The first corrected-device run is in
`20260829-010428-thor-input-custom`. It matched a policy module at
`0x02370000`. Three SPUs took workload 6 before the short run ended. Later
attempts were stopped by the 72 C guard before they could prove workload 7.

## 77. The Android route can stop before guest execution

Commit `6c24ff9ff` adds `debug.rpcsx.thor.start_paused`. A start-paused boot
loads the title into the Ready state and does not start guest threads. The
first resume completes startup. A later resume starts guest execution. Normal
launches do not use this gate.

Exact APK
`F7A9933936D321A3F2DD75EBC6209899C46AE57D4B9E060D7C71DC27684F0B9B`
proved the gate. Capture `20260829-012258-thor-input-custom` stayed between
41.7 and 48.6 C for 19 fixed-silicon samples while it was Ready. Capture
`20260829-013043-thor-input-custom` separated the startup transition from the
first SPURS workloads. The first transition took about 6.8 seconds. The next
short resume created workloads 0 through 2 and then paused.

The Android native build, APK build, route contract, pause contract, selector
contract, PowerShell parse, and Git whitespace checks passed. The device had
the exact APK before these runs.

## 78. One preloaded SPU program is too few

Commit `f38646c59` made the Transformers SPU preload limit selectable and first
used a default of one. Capture `20260829-013837-thor-input-custom` built one
startup object and left 877 objects for normal on-demand LLVM compilation.
The first 2.5-second guest slice reached only workloads 0 through 2. A later
slice reached workloads 3 and 4. The guard stopped the second slice at 73.5 C.

The paused screenshot after the first slice reported 30.34 FPS, but the frame
was black. It has no 3D or sustained-FPS credit. The one-program limit also
delayed workload creation when compared with the 64-program route. Commit
`c0ac70dc5` therefore restores 64 as the default and keeps the new override.

## 79. The workload-6 cap holds four SPUs

Capture `20260829-014229-thor-input-custom` used the 64-program preload and one
short guest slice. It reached workloads 3 and 4. The macro stopped RPCSX at an
observed fixed-silicon peak of 61.4 C.

Capture `20260829-014457-thor-input-custom` extended the slice by 0.5 seconds.
It created workloads 5 and 6. The log contains the exact reserve marker:

    Thor Transformers SPU reserve: workload 6 max contention changed from 5 to 4

Exactly four SPUs then dispatched the real workload-6 image. This is direct
live evidence that the title gate and contention cap work. The macro stopped
RPCSX at an observed fixed-silicon peak of 63.4 C. The final paused frame was
black and reported 10.10 FPS. It has no render or sustained-FPS credit.

Workload 7 was not created before that pause. The next boundary is about 0.2
seconds later. A first retry in `20260829-014639-thor-input-custom` started
while the device still had heat from the prior run. The 72 C guard stopped it
at 73.1 C during startup and before the guest slice. The device process is
stopped. The next run must use the same 64-program route after a longer passive
cooldown.

## 80. A host pause can lose the startup race

Capture `20260829-015022-thor-input-custom` started below 70 C and used the
first start-paused implementation. The control pause arrived while the
emulator was still in the Starting state. The main SPURS service thread then
entered workload 7 after the pause request. Silicon reached 72.3 C, and the
guard stopped RPCSX before the planned guest slice.

This result proves that host polling cannot close the startup race. A pause
request during Starting must not depend on a later state change.

## 81. Startup now applies the pause before it releases guest threads

Commit `6f711245f` adds a one-use startup pause request to `Emulator`. The
Android Ready gate arms this request before it starts the emulator. The normal
`FinalizeRunRequest` pause path then adds `dbg_global_pause` before it changes
the emulator to Running. Boot, kill, and shutdown clear the request.

The Transformers route contract, SPURS pause contract, Git whitespace check,
and full ARM64 native build passed. Exact ARM64-only debug APK
`25815E0FE22B2F28BB1EF561A52B0CD04942085694D1E496B9E96F48BE717F87`
is 116,136,072 bytes. The exact no-launch installation is in:

    20260829-015917-thor-input-strict-cool-gate
    20260829-015932-transformers-startup-handoff-install

The install gate read 44.1 C. The host and installed APK hashes matched, and
RPCSX was not active after installation.

## 82. The startup handoff stays idle while it is paused

Capture `20260829-020015-thor-input-custom` reached the new handoff marker and
entered the Paused state. It recorded zero SPURS `ADDWKL` and `WKLOAD` rows.
The host route first classified the run as a failure because the pause request
returned `ok=false, paused=true`. The core did not change state because it was
already paused. Commit `8676b4646` makes the host accept the reported Paused
state. The device thermal guard and route contracts pass.

The completed repeat is in `20260829-020201-thor-input-custom`. It held the
startup handoff for 30 seconds. It recorded one handoff marker and zero SPURS
workload rows. A three-sample thread snapshot found the PPU, SPU, RSX, and
other RPCSX threads asleep. The final `top` sample reported 0.0 percent for
all listed RPCSX threads. Fixed silicon had a 59.0 C startup peak and then
stayed near 45 C during the paused hold. The screenshot shows the RPCSX pause
overlay. It is not a rendered-game proof.

## 83. The reserved SPU takes Transformers workload 7

Capture `20260829-020351-thor-input-custom` used one 2.65-second guest slice.
It reached workload 6, applied the maximum-contention change from five to
four, and dispatched workload 6 on three SPUs. It paused before workload 7.
Fixed silicon peaked at 69.1 C, and RPCSX stopped normally.

Capture `20260829-020548-thor-input-custom` did not execute the planned guest
slice. Its first resume arrived before the Ready gate was armed. The second
resume performed startup. This is a route timing error, not an HLE result.

Capture `20260829-020727-thor-input-custom` added an explicit Ready checkpoint
and used a 3.3-second guest slice. The exact workload-6 reserve marker appeared.
Exactly four SPUs dispatched the real workload-6 image. Workload 7 was created
0.806 seconds later and dispatched immediately on the reserved SPU 5. The Bink
shader setup path then started. Fixed silicon peaked at 66.6 C. The maximum
reported CPU-junction value was 93.2 C, below the 95 C stop limit. RPCSX
stopped normally. There was no access violation, signal fault, or native fatal
error.

This result proves the HLE scheduler boundary. It does not yet prove a visible
Bink frame, gameplay, or sustained 30 FPS. The next route must keep the same
startup handoff and SPU reserve, use cooled guest slices, and inspect each
screenshot before it sends any game input.

## 84. Two reserved SPUs let the Bink frame reach RSX

The four-SPU route in `20260829-021023-thor-input-custom` dispatched workload
6 on SPUs 1, 2, 3, and 5. Workload 7 then used SPU 4. The edge wake arrived,
but the workload-0 taskset had lost its earlier SPU 2 residency. No draw
followed. The older draw-producing route had used three SPUs for workload 6
and had kept the workload-0 taskset resident.

Commit `dfe5c4425` therefore changes the exact BLUS30357 workload-6 cap from
four SPUs to three. This keeps capacity for the Bink taskset and its downstream
edge taskset. The source contract and full ARM64 native build passed. Exact
ARM64-only debug APK
`D54274E95D65DCA2E15431F256BD01B35C6F54BE84E7FA3EF7D2B453C4CA8748`
is 116,136,856 bytes. It passed the ARM64 APK contract. The exact no-launch
installation is in:

    20260829-022219-thor-input-strict-cool-gate
    20260829-022234-transformers-two-spu-reserve-install

The install gate read 42.9 C. The host and installed APK hashes matched, and
RPCSX was not active after installation.

Capture `20260829-022309-thor-input-custom` proves the new scheduler boundary.
Workload 6 dispatched on exactly SPUs 1, 2, and 3. The second workload-7
dispatch used SPU 4. Its event produced the workload-0 edge wake. RSX then
issued two draws with mapped, nonzero 1280-by-720 Y and 640-by-360 Cr and Cb
textures. The first luma samples were `0x10`, and both chroma samples were
`0x80`. This is a valid black video frame, and the saved screen remained
visually black.

This is the first deterministic HLE route from workload creation through Bink
decode and into RSX draws. It is not yet a visible-frame or FPS proof. The
device guard stopped the route when a CPU junction reached 95.2 C. Fixed
silicon peaked at 68.7 C. No native fault appeared. The next run must disable
the runtime census and use shorter active slices to reach a later video frame
without reaching the junction limit.

## 85. The common SPURS poll path now honors pause

Capture `20260829-024426-thor-input-custom` showed that Android Pause set
`dbg_global_pause` on all six SPURS workers, but each worker stayed active at
PC `0x00a00`. The rate-limited state check was at the top of
`spursSysServiceMain`. The idle-handler path used `goto poll`, so it could run
without returning to that check.

Commit `69b9dbe18` moves the same one-in-256 state check to the common `poll`
label. It does not add state loads to the other 255 scheduling passes. The
source contract, diagnostic-token contract, ARM64-only APK contract, and full
debug APK build passed. Exact APK
`93D7E701B59B2EA7464FFC9E310A9E96F9E8C484077A998907997446742857A5`
is 116,136,043 bytes. The exact no-launch installation is in:

    20260829-024831-thor-input-strict-cool-gate
    20260829-024842-transformers-common-poll-pause-install

Capture `20260829-025043-thor-input-custom` proves the repair with active
workers. Before pause, all six SPURS workers were active. Five were at PC
`0x00a00`, and one was in the workload-6 image. After pause, all six reported
state `0x8004`. Three Linux thread samples then found every SPU worker asleep
in `futex_wait_queue_me` at 0.0 percent CPU. Total emulator CPU while paused
was 0.5 percent. Fixed silicon peaked at 65.0 C and then fell to 49.0 C.

The pause route is now safe for short active slices. This result does not add
visible-frame or sustained-FPS credit. The next HLE run must use these pause
windows to pass the first black Bink frame and capture a later video frame.

## 86. The cooled HLE route now produces a visible Bink frame

Capture `20260829-025327-thor-input-custom` was a route error. The generic
input macro reset `debug.rpcsx.thor.transformers_spu_reserve` to zero. Workload
6 took five SPUs, workload 7 did not dispatch, and every guest screenshot was
black. Do not use the generic macro alone for this proof.

Capture `20260829-025751-thor-input-custom` used the dedicated Transformers HLE
probe with the reserve, edge-event interpreter, and task-attribute repair on.
It used the exact APK from section 85. The route kept the guest active for short
slices and used the repaired pause path for cooling between slices.

The workload-6 maximum changed from five to three. Exactly three SPUs then took
workload 6. Workload 7 dispatched on SPU 4, and its event woke the workload-0
edge taskset. The screenshots at 3.6 and 6.6 seconds were black. The screenshots
at 9.6 and 12.6 seconds showed the Unreal and PhysX legal frame. The frame check
classified both later screenshots as `DRAWN`, with 4,566 and 4,796 distinct
colors. The 9.6-second overlay reported 30.23 FPS.

This is the first deterministic visible HLE result with the two-SPU reserve. It
proves that HLE SPURS now reaches visible Bink output. It does not yet prove a
sustained 30 FPS interval because every saved frame was taken after a pause.
Fixed silicon peaked at 71.1 C and fell to 52.6 C in the next sample. RPCSX
stopped normally, with no access violation or native fault.

The next run must capture the same visible sequence while it is active. It must
measure an uninterrupted FPS interval before it gives sustained-FPS credit.

## 87. The yield fast path fails this repaired route

Capture `20260829-030501-thor-input-custom` changed only
`debug.rpcsx.thor.yield_fast_path` from zero to one and added two cooled slices.
It did not repeat the visible result. SPU 0 reported an access violation at PC
`0x048e0` while it read unmapped address `0xfff00000`. Workload 7 did not
dispatch after the fault, and all seven screenshots were black.

Two screenshots reported about 29 FPS, but the pause overlay remained visible
and total CPU was 0.3 percent. These samples show the paused presenter and have
no FPS credit. Fixed silicon peaked at 70.7 C, and RPCSX stopped normally.

The yield fast path is not correct for the current HLE repair stack. Keep it off.
The exact visible route in section 86 remains the last known-good route.

## 88. An atomic claim enforces the workload-6 limit

Capture `20260829-030952-thor-input-custom` reproduced the remaining scheduler
race with the yield fast path off. The title changed workload 6 maximum
contention from five to three, but five SPUs dispatched the workload at the
same timestamp. Workload 7 was not created. SPU 0 then reported an access
violation at PC `0x048e0` while it read unmapped address `0xfff3c400`.

The selector read contention before it changed the shared counter. Several
SPUs could read the same old value, select the same workload, and then perform
separate atomic increments. Commit `e264114ae` makes the limit check and slot
claim one atomic operation. A failed claimant stays in the system service and
does not consume the workload signal. A source contract, the related SPURS
contracts, the full ARM64 debug build, and the ARM64 APK contract passed.

Exact APK
`3159577C302446D9BF90887A3B207FEB81013C5DD68D15531017EDD590467A2F`
is 116,134,313 bytes. The exact no-launch installation is in:

    20260829-032020-thor-input-strict-cool-gate
    20260829-032038-transformers-atomic-contention-install

The install gate read 42.9 C. The host and installed hashes matched, and RPCSX
was not active after installation.

Capture `20260829-032102-thor-input-custom` proves the atomic limit. Exactly
SPUs 5, 1, and 4 dispatched workload 6. Workload 7 was created 0.56 seconds
later and dispatched on reserved SPU 3. No access violation or native fault
appeared. The legal screen became recognizable in the last three images.
Fixed silicon peaked at 69.5 C, and RPCSX stopped normally.

The strict frame check still classifies these dark images as blank, with 382
to 449 distinct colors and 89.9 to 91.2 percent near-black pixels. The images
labeled active at 9.6 and 12.6 seconds still contain the pause overlay. Their
30.93 and 29.67 FPS readings have no speed credit. System logs confirm each
resume interval, so the next test must force a fresh presentation while the
emulator is running or wait for a later game flip before it measures FPS.

## 89. Idle dispatch no longer releases active task contention

Commit `52c9224bb` requests a native UI flip after Resume. The source contract,
full Android debug build, and ARM64 APK contract passed. This change removes the
pause overlay after the guest has time to present a new frame. It does not make
a black guest frame valid.

Capture `20260829-032946-thor-input-custom` then found a separate workload-7
loop. SPU 5 executed task 0 while SPU 3 entered the same taskset. The taskset
had one running task and maximum contention 1. The idle SPU reduced the shared
contention count from 1 to 0 before it cleared its local record. This opened the
gate, and SPU 3 entered workload 7 about 4.6 million times.

Commit `eac664f4d` counts the running tasks before an idle taskset exit. It
reduces shared contention only when the shared count is greater than the
running-task count. It always clears the idle SPU local record. This keeps the
shared count for an active task and still removes extra idle slots. A focused
source contract, the related SPURS contracts, the full Android debug build,
and the ARM64 APK contract passed.

Exact APK
`266405B4B4EF6632377CE3FB0E7C873A0C615BFDDF568BD1D3E7F7C9F69F45B7`
is 116,135,311 bytes. The exact no-launch installation is in:

    20260829-034112-thor-input-strict-cool-gate
    20260829-034131-transformers-idle-contention-install

The install gate read 42.5 C. The host and installed hashes matched, and RPCSX
was not active after installation.

Capture `20260829-034203-thor-input-custom` proves the contention repair. SPU 2
started workload 7 task 0. SPU 3 then found no selectable task while the running
bitmap contained task 0. Its diagnostic row read `shared=1`, `local=1`, and
`runningTaskCount=1`. It cleared only its local record and returned to the
system service. The complete saved log contains one idle-ready row and no
redispatch storm. Later workload-7 dispatches ran the task on SPU 4. No access
violation, verification failure, or native fatal error occurred.

The two active screenshots are still black. The frame check found 152 and 139
distinct colors with 98.5 percent near-black pixels. It rejects the displayed
29.99 and 3.79 FPS values. The fixed-silicon start was 42.9 C, and the maximum
runtime sample was 71.1 C. RPCSX stopped normally. This is a scheduler
correctness result, not a visible-frame or speed result. The next cooled proof
must use enough short guest slices to pass the first Bink frames before it
measures FPS.

## 90. The repaired contention route reaches an active legal frame

Capture `20260829-034741-thor-input-custom` repeated the four-slice cadence
from section 86. Each screenshot request came before its pause request. The
first two images were black. The third image still contained the pause toast.
The fourth image showed the Unreal and PhysX legal screen with no pause toast.
Its overlay reported 13.69 FPS. This is the first active, visible frame after
the atomic contention and idle-release repairs.

The strict frame check rejected the dark legal frame because 91.2 percent of
its pixels were near black. Visual inspection confirms the two logos and the
copyright text. The image had 382 distinct colors and a size of 156,081 bytes.
This is a valid render proof, but one frame at 13.69 FPS is not a sustained
speed proof.

The complete log contains three idle-ready rows. All three belong to workload
0 during startup. Their shared contention values decreased from 4 to 3 to 2
while one task remained active. Workload 7 has no idle redispatch storm. Four
workload-7 event sets occurred, and RSX registered three descriptor sets. The
four guest diagnostics show active SPURS PCs. No access violation,
verification failure, or native fatal error occurred.

The fixed-silicon start was 42.9 C, and the maximum runtime sample was 69.9 C.
The runtime guard did not fire, and RPCSX stopped normally. The log contains
981 `cellSpursQueuePushBody` warning rows during 12.6 seconds of guest time.
The next change must remove this hot-path warning cost before another active
FPS measurement.

## 91. The HLE legal frame reaches the 30 FPS cap

Commit `f0331ae8a` changes the per-call `cellSpursQueuePushBody` record from
warning level to trace level. A focused source contract prevents the hot call
from returning to warning level. The contention-claim, idle-contention, and
pause contracts passed. The full Android debug build and the ARM64 APK contract
also passed.

Exact APK
`4A176356229D56C8BF3A73EA1C7FFF08428386112D35A80FC5E59C4F0998BD22`
is 116,135,330 bytes. The exact no-launch installation is in:

    20260829-035620-thor-input-strict-cool-gate
    20260829-035636-transformers-queue-log-budget-install

The install gate read 43.7 C. The host and installed APK hashes matched, and
RPCSX was not active after installation.

Capture `20260829-035705-thor-input-custom` repeated the exact four-slice
cadence from section 90. The first two active screenshots were black. The third
active screenshot showed the complete Unreal and PhysX legal screen with no
pause toast. Its overlay reported 29.98 FPS. The previous equivalent active
legal frame reported 13.69 FPS. The fourth screenshot contained the pause toast
and has no speed credit.

The complete log contains no per-call queue-push warning rows. It contains 19
sampled queue-ring rows and eight workload-7 event sets. The two workload-7
idle rows kept shared contention at 1 while one task was running. There was no
redispatch storm. No access violation, verification failure, or native fatal
error occurred.

The probe started at 44.5 C. Fixed silicon reached 68.2 C and stayed below the
72 C runtime stop limit. RPCSX stopped normally. This proves an active visible
HLE frame at the 30 FPS cap. It does not yet prove a sustained 30 FPS interval.
The next proof must take two or more active FPS samples from one visible
interval.

## 92. The HLE legal screen holds 29.97 FPS

Capture `20260829-040140-thor-input-custom` tried to remove the earlier
screenshot delays. This also removed guest-active time. Its first measurement
was still black at 0.86 FPS. The device guard stopped RPCSX during the second
screenshot when fixed silicon reached 74.3 C. There was no emulator fault. The
capture has no speed credit.

Capture `20260829-040452-thor-input-custom` moved the remaining decode work
into four short active slices with cooling pauses. A fifth short interval took
two screenshots without a pause between them. The captures occurred at
04:07:25.358 and 04:07:26.862. Both show the complete Unreal and PhysX legal
screen with no pause toast, and both report 29.97 FPS. Their common SHA-256 is
`129CD78B8CDBCDE669EF6E64BF59DE4CE346FC47728D4ED6EBFC7317343212BF`.

The two captures are 1.50 seconds apart in one uninterrupted active interval.
They prove that the static legal screen holds the 30 FPS cap. The complete log
contains eight workload-7 event sets, no per-call queue-push warning rows, and
no redispatch storm. No access violation, verification failure, or native
fatal error occurred.

The strict gate read 45.3 C. The probe started at 52.6 C, reached 69.5 C, and
stopped normally. HLE SPURS now produces stable, full-speed startup output.
The result does not prove title-menu or gameplay speed. The next run must move
past the legal screen and verify the next interactive state.

## 93. Direct Start moves past the legal screen

Online research confirmed two useful controls. The RPCS3 compatibility list
classifies BLUS30357 as playable. A public PS3 boot report says that Start can
skip the opening credits. The first local tests used Android virtual gamepad
input. The input macro already warns that this route can drop a button while a
title is visibly ready.

Commit `b6a68b5be` makes the dedicated Transformers probe use the app-owned
direct pad route by default. The LFQueue-route, device-guard, contention-claim,
idle-contention, and pause contracts passed. This is a host probe change and
does not change the installed APK.

Capture `20260829-041456-thor-input-custom` stopped before any Start input. A
first 3.6-second slice raised fixed silicon to 72.3 C, and the device guard
stopped RPCSX. No emulator fault occurred. Later routes divide the same work
into 2-second slices.

Capture `20260829-042354-thor-input-custom` used six 2-second startup slices
and one `direct:start` action. The final frame was different from the legal
screen. It was a dark transition at 29.83 FPS. Its SHA-256 is
`8C67AFEF81E09CDABAD8315311157CDD896950F3CA771EAB155D7742FAD4DF7F`.
Fixed silicon reached 71.1 C. RPCSX stopped normally, with no access violation,
verification failure, or native fatal error.

Capture `20260829-042945-thor-input-custom` added four post-Start work slices.
The final image was still black and kept the old pause toast. Its 29.65 FPS
value has no speed credit. The active-time total is close to the earlier
23.49-second loading-output boundary from section 64. The next route must add
one cooled work slice before it captures the post-Start state.

## 94. The event-flag setter no longer stops the rendering thread

Capture `20260829-045342-thor-input-custom` added the next cooled work slice.
It reached the loading emblem, but the rendering thread stopped at guest time
6:22.725. The host `ensure` in `cellSpursEventFlagSet` rejected a nonzero
result from `_cellSpursSendSignal`. The image FPS value was stale after the
thread stopped, so it has no speed credit.

Ghidra analysis used the decrypted Sony `libsre` ELF with SHA-256
`74A023767AAE35838F26EF1A846806CAAD438A041A06BA16B1165050AA403E8`.
The module log maps export `cellSpursEventFlagSet` to module offset `0x16010`.
Its firmware control flow maps `0x80410902` (`INVAL`) and `0x8041090f`
(`STAT`) to `0x80410914` (`FATAL`). It sends every other signal result to its
diagnostic helper and then returns `CELL_OK`. The saved decompile is in:

    20260829-045342-thor-input-custom/libsre-event-set-decompile.txt

The same function also confirmed a wait-slot mirror error in the inherited
HLE code. The low pending bit selects wait slot 15. The old code saved the
event mask in slot 0 and later read slot 15. Commit `6ed0f9831` saves the mask
in the selected wait slot. A focused source contract covers this mapping.

Commit `d87fa3089` removes the host-killing assertion. It keeps the firmware
`INVAL` and `STAT` to `FATAL` mapping. Other nonzero results now use a bounded
diagnostic and continue to the firmware `CELL_OK` return. The event-flag,
selector, activation, queue-log, and Transformers HLE route contracts passed.
The full Android debug build and the ARM64 APK contract also passed.

Exact APK
`5E91D9FC175415828411B0B707A036C950C0797A80FC34EE97C170E28F5E320D`
is 116,135,772 bytes. The exact no-launch installation is in:

    20260829-050743-thor-input-strict-cool-gate
    20260829-050755-transformers-event-result-install

The install gate read 42.9 C. The host and installed APK hashes matched, and
RPCSX was not active after installation.

Capture `20260829-050820-thor-input-custom` repeated the same direct-Start
route. The log contains eight sampled event-flag Set calls. The rendering
thread was still active at guest time 6:24.922, more than two seconds past the
old fatal boundary. The log has no verification failure, fatal thread stop,
access violation, or native crash. RPCSX stopped only at the macro stop.

Visual inspection confirms a complete Unreal and PhysX legal frame. Its
overlay reports 28.82 FPS, and its SHA-256 is
`BA8D246D5BA25AB963CCE0B9E83C842D8C48AFEE92CC0C2DC70C96E192E88116`.
All six HLE SPURS workers were active in the final diagnostic. The queue also
continued to drain after guest time 6:22. The final frame is valid HLE output,
but one 28.82 FPS image is not a sustained 30 FPS proof.

The launch sample was 44.1 C. Fixed silicon reached 65.4 C and stayed below
the 72 C stop limit. The direct Start action did not reach the loading frame
in this repeat. The next proof must make the Start transition deterministic,
then take two active samples after the transition.

## 95. The firmware diagnostic path exposes a task-state stall

Commit `a7f89c09c` makes direct pad input fail closed. The debug receiver now
returns an explicit acceptance result. The macro saves this result and stops
if the active app does not accept the pulse. The macro also accepts a bounded
duration in a token such as `direct:start:240`. The focused input contract,
the HLE route contract, and the thermal guard contract passed.

Exact APK
`F0DDA4250A1FE1842F8B12259BA79E60D70BB9D0EABF44A3C688549F3E953415`
is 116,135,772 bytes. The exact no-launch installation is in:

    20260829-052052-thor-input-strict-cool-gate
    20260829-052104-transformers-direct-pad-ack-install

Capture `20260829-052134-thor-input-custom` used three 240 ms Start pulses.
All three receiver results were `result=-1, data="accepted"`. The route reached
the loading screen. At guest time 5:24.890, `cellSpursEventFlagSet` tried to
signal task 0 in taskset `0x1f73f00`. `_cellSpursSendSignal` returned
`0x80410905` (`SRCH`). The firmware-matched diagnostic logged the result, and
the rendering thread did not terminate.

This result removes the host fatal, but it does not remove the guest stall.
No rendering-thread work appears after that signal result. The final core
sample records zero new frames in the active interval. Two screenshots taken
2.81 seconds apart show the loading emblem and report 29.75 FPS, but their
common SHA-256 is
`59E070CC78DB69C4FA140E48F0E53B6598D6E3D732121B551F729D20FA64A22A`.
The byte-identical images and zero core frames make that overlay value stale.
They have no speed credit. Fixed silicon reached 67.8 C, and RPCSX stopped at
the macro stop.

Commit `f9ffdadb8` adds the six task bitmaps to the bounded event-signal
diagnostic. The event-flag, selector, activation, queue-log, and HLE route
contracts passed. The full Android debug build and the ARM64 APK contract
passed. Exact APK
`E23065E7C39AE08EFB5406E611793CD3AE9FDB42A8CB67F217FBD176D016CB37`
is 116,136,399 bytes.

The exact no-launch installation is in:

    20260829-053211-thor-input-strict-cool-gate
    20260829-053225-transformers-event-state-install

Capture `20260829-053243-thor-input-custom` stopped about 0.15 guest seconds
before the event result appeared. It contains no event-state diagnostic. The
last taskset rows before the stop are valid: task 0 has running, ready, and
enabled set to `0x80000000`; pending-ready, waiting, and signaled are clear.
Fixed silicon reached 69.9 C, and RPCSX stopped normally. The next cooled probe
must add one more two-second post-Start slice and stop after it records the
event-state line.

## 96. The event result is not the stable post-Start boundary

Capture `20260829-054047-thor-input-custom` used the exact diagnostic APK and
added the planned post-Start slice. The cold sample was 45.3 C. The maximum
fixed-silicon sample was 67.4 C, and RPCSX stopped normally. All three direct
Start pulses returned `result=-1, data="accepted"`.

This run did not call the event setter at the prior failure point. It did
record the known queue signal result many times. The queue is bound to taskset
`0x10364100`, which has only task 0 enabled. When task 0 is running and is not
waiting, the queue code falls back to the caller value, task 1, and
`_cellSpursSendSignal` returns `SRCH`. The separate pending-contention record
already proves that this queue does not own the two event waiters. Therefore,
this result is not the loading blocker and the queue must not remap a caller
argument without new firmware evidence.

Capture `20260829-055132-thor-input-custom` enabled the bounded runtime census
and added post-Start slices 10 and 12. The cold sample was 45.3 C. The maximum
fixed-silicon sample was 67.4 C, and RPCSX stopped normally. All three Start
pulses were accepted. The event setter ran many times and recorded no event
signal error. Thus, the earlier event `SRCH` is not a stable failure boundary.

The two inspected screenshots prove live progress. Slice 10 shows the Unreal
and PhysX legal screen. Slice 12 is a black transition frame. Their SHA-256
values are, respectively:

    FF2BA481340A8388581796996A70CDBF96C6EB5957978B4A4DD801A94DC9BAB3
    CD831EA741FC94046C08CA416E6E91870257EB452D0EACA1D03BEE73EFC2AD61

During paused intervals, the rendering thread is in `sys_ppu_thread_sleep` at
guest address `0x009e4ba4` with link register `0x00106f60`. In the last active
sample, it is inside `cellSpursQueuePushBody`. The thread therefore wakes and
continues to submit work. This is progress, not a dead renderer.

The 2 to 4 FPS screenshot values have no speed credit because the runtime
census was enabled and each active interval was only two seconds. The next
proof must disable the census, continue beyond the black transition, inspect
the next visible screen, and measure an unpaused active interval.

## 97. The first edge-Zlib batch completes

Capture `20260829-063618-thor-input-custom` used the exact APK with SHA-256
`AF5AB723AAE104579FEB5E3903EBA10C74E100186CBBA86FF3058DABA9835642`.
It enabled the bounded SPURS atomic census. It kept the runtime census off and
used ten cooled post-Start slices. All three direct Start pulses were accepted.

The first LFQueue notification woke workload 0 and task 0 in taskset
`0x101b4e80`. SPU 3 then performed two atomic pairs on queue `0x101b1f80`.
The edge event interpreter completed five calls. The pool thread advanced the
queue pop count from zero to five. These rows prove that the first loader batch
now completes.

The next queue push changed the pop state to `pop{5,0,0422,5}`. It issued the
second LFQueue notification. The event path set the task signal bit and the
workload signal. The gate row reported state 2, current contention 0, pending
contention 0, and maximum contention 8. No later atomic pair on queue
`0x101b1f80` appears in the capture. Thus, the second workload or task selection
is the current boundary. The old event-signal `SRCH` is not this boundary. It
occurs later when the title removes a separate Bink taskset.

Visual inspection of `01-post-start-20.png` shows the Transformers loading
emblem. Its SHA-256 is
`2AFB8A93E06AB4DD2FBA5A471156FA03A49B5966D97E81FFCD80C540B5BA09FD`.
The image includes a pause notice, and its FPS value has no speed credit. The
capture contains no access violation, verification failure, native crash, or
fatal thread stop. The launch sample was 44.1 C. Fixed silicon reached 66.2 C,
and the maximum junction sample was 83.5 C. RPCSX stopped normally.

The next APK adds two bounded records. One record shows each selector that sees
or selects workload 0. The other record shows the task state after each atomic
selection for workload 0. This will show whether the second signal is lost at
the workload gate or whether the taskset returns no selectable task.

## 98. The HLE callback boundary can lose an edge task signal

Capture `20260829-065235-thor-input-custom` used exact APK
`C08B69C5F18A03A06DF23619550A3BEF787E71EF7EF41A66AFBE2D30B5DCE097`.
It enabled the bounded edge-task census. All three direct Start actions were
accepted. Workload 0 consumed the signal, selected task 0, and entered the edge
event interpreter. This sequence repeated. The bounded log reached eight edge
wakes, 32 edge task selections, 16 edge event-interpreter entries, 24 queue-ring
records, and 16 queue notifications. The queue pop count reached at least 23.

The main thread continued and created FMOD workload 9 at guest time 4:28. The
last active slice ended when it entered `cellSpursEventFlagWait` for the new
workload. This is progress and is not proof of an FMOD stall. Visual inspection
of `01-edge-task-boundary.png` shows the Transformers loading emblem and a pause
notice. The image has SHA-256
`659D9AA08DDC5E6E263663C73062B379BD45AF798E16A8BB2D2F22024CC9F13F`.
Its FPS value has no speed credit. Fixed silicon reached 70.3 C and stayed below
the 72 C runtime stop limit.

Capture `20260829-070300-thor-input-custom` used the same APK with the edge-task
census off. It added five post-Start work slices. The pool thread completed only
one queue-ring operation and one workload wake at guest time 2:29.895. The main
thread did not progress after that point. The rendering thread stayed active,
but it later searched for a task in a disabled Bink taskset. The final loading
image has SHA-256
`B1041E8B4388F0470D9A5484477BF28471F184B326206899931C73B4E69662D7`.
It includes a pause notice, and its FPS value has no speed credit. Fixed silicon
reached 67.8 C. There was no access violation, verification failure, native
crash, or fatal thread stop in either capture.

This A/B corrects the conclusion in section 97. The second edge wake and task
selection can complete. The diagnostic changes scheduling enough to cross the
failure boundary. The host runs `RunHleFunction`, returns to the SPU CPU loop,
and checks pause state before it invokes the next registered HLE address. The
kernel selector previously consumed the workload signal and set `pc` to the HLE
policy entry in the first callback. A lifecycle pause can occur before the next
callback. If resume loses that entry PC, no workload signal remains to select
the taskset again.

Commit `f2555a2a9` makes this handoff pause-safe. The selector keeps the signal
for an HLE taskset or job-chain policy module. It still issues the atomic
reservation notification. The dispatch path also keeps the signal. The HLE
policy entry consumes it as its first operation. A real SPU policy module keeps
the existing dispatch-time signal consumption. The kernel 1 and kernel 2 paths
use the same rule. A focused source contract covers both selectors, the dispatch
guard, and both HLE policy entries. The selector-signal, contention-claim,
LFQueue-route, and SPURS probe-build contracts also passed.

The full Android debug build passed. Candidate APK
`F5540C9C05DF14989A8A5839805361BFEDD7CDB22FB29A9D9140B0256B5A48EC`
is 116,139,883 bytes. The next device run must keep the edge-task census off and
repeat the exact long post-Start route. Success requires repeated queue-ring
work and main-thread progress after the first cooled pause.

## 99. The HLE entry handoff crosses the old pause boundary

The strict one-sample gate is capture
`20260829-072347-thor-input-strict-cool-gate`. Fixed silicon was 43.7 C. The
exact no-launch installation is capture
`20260829-072401-transformers-hle-entry-signal-install`. The host and installed
APK hashes matched, and RPCSX was not active after installation.

Capture `20260829-072430-thor-input-custom` repeated the section 98 route with
the edge-task census and the general atomic census off. All three direct Start
actions were accepted. The first queue push and workload wake occurred at
2:03.281, immediately before a cooled pause. After resume at 2:57.505, the edge
event interpreter completed seven calls. The queue produced nine ring records,
six notifications, and six workload wakes. The queue pop state advanced from
zero to eight. The main thread resumed its staged memory work and allocated
through address `0x10ea0000` after the first pause.

This result satisfies the planned repair gate. The same no-census route without
the repair stopped after one ring record and one wake in section 98. The HLE
entry signal handoff now crosses that host callback and pause boundary without
diagnostic timing help.

The capture does not prove full HLE startup. Ring record 8 has
`pop{8,0,18c6,8}`. It has no following queue notification, workload wake, or
edge event-interpreter entry. The pool thread then waits on event flag
`0x1e54800`. The edge task can consume an unnotified item only if it stays
active and polls the queue. The last record can therefore be a queue-notification
race, but this is not yet proved.

The rendering thread continued to run the workload-7 Bink taskset. One active
interval produced 44 frames in 10 seconds. The main thread produced no later
log record after 2:58.342. The final screenshot is black with a pause notice and
reports 1.60 FPS. Its SHA-256 is
`6DC9C7F3A7FC52AA5F75F6562B3B0B7AD32486E2BB837815B9B1A1BCFE458192`.
It has no speed credit. There was no access violation, verification failure,
native crash, or fatal thread stop.

The launch sample was 44.5 C. Fixed silicon reached 67.8 C, the maximum junction
sample was 83.1 C, and the last fixed-silicon sample was 61.8 C. The device
guard stopped only after the package stopped normally. The next software probe
must record why LFQueue ring record 8 suppresses its notification and whether
the edge task is running, waiting, or between those states at that write.

## 100. The atomic demand claim exposes the selector return boundary

Later source inspection corrects the pause theory in sections 98 and 99.
`cpu_thread::check_state` blocks a paused SPU thread and resumes it at the same
PC. A lifecycle pause does not lose the HLE entry PC. Also, ring record 8 in
section 99 correctly did not send a notification. Its notification head and
tail were equal. The HLE entry signal handoff changed scheduling and crossed
the old boundary, but it did not repair the stated pause mechanism.

Commit `cf2edd0a7` replaces that handoff with one reservation operation on the
first 128-byte `CellSpurs` line. The operation rechecks demand and contention,
increments current contention, and consumes the selected signal or flag as one
atomic claim. The selector and dispatch paths do not clear the same signal a
second time. The atomic-demand, contention-claim, selector-signal, LFQueue-route,
and SPURS probe-build contracts passed. The full Android debug build passed.
Exact APK
`E7609694169E16C3A2FC66EC62F428C11290667D3202D6D1A5A7F4F6221DA8EF`
is 116,140,573 bytes.

The strict one-sample gate is capture
`20260829-074823-thor-input-strict-cool-gate`. Fixed silicon was 44.1 C. The
exact no-launch installation is capture
`20260829-074846-transformers-atomic-workload-claim-install`. The expected,
host, and installed hashes matched. RPCSX was not active after installation.

Capture `20260829-074922-thor-input-custom` repeated the long direct-Start route
with the edge-task and atomic censuses off. The atomic claim removed the prior
multi-SPU workload-0 fanout. The first LFQueue notification at guest time
2:03.993 woke workload 0 and dispatched it on SPU 5. After resume, two edge
event-interpreter calls completed. Ring record 2 sent the second notification
at 2:58.571. The task was waiting and was signalled. The gate then showed
current contention 0 and maximum contention 8. However, no later workload-0
dispatch occurred. The next workload records were system service and workload
7. The pool thread waited on event flag `0x1e54800`.

The capture has three ring records, two notifications, two workload wakes, and
two edge event-interpreter entries and exits. It has no access violation,
verification failure, fatal thread stop, or native crash. Visual inspection of
`01-atomic-demand-boundary.png` shows the Transformers loading emblem. Its
SHA-256 is
`FCCC11E8A4CEB77C99C0995DFB653974BDE029E69B5EB700849269670D55806B`.
The image includes a pause notice, so its 29.64 FPS value has no speed credit.
Fixed silicon reached 68.7 C, maximum junction reached 87.9 C, and the last
fixed-silicon sample was 53.4 C. RPCSX stopped normally.

## 101. The HLE selector now returns through the SPU link register

`spu_thread::RunHleFunction` calls a registered host function and continues the
SPU CPU loop. It does not change the PC. The SPURS kernel registers the kernel 1
selector at local-store address `0x290`. The HLE selector returns its result in
register 3, but it previously left the PC at `0x290`. A guest call to this
address could consume the workload signal and then call the same HLE selector
again instead of returning to the kernel dispatch code.

Headless Ghidra analysis of the genuine LLE kernel dump proves the required
control flow. The selector ends at `0x6bc` with `bi lr`. Its workload-exit
caller sets the stack at `0x808`, calls selector `0x290` with `brsl lr` at
`0x810`, and continues at `0x814`, where it calls dispatch `0x6c0`. The saved
Ghidra windows are:

    debug-captures/ghidra-spurs-selector-return-20260829/spu-hot-window-ghidra.txt
    debug-captures/ghidra-spurs-selector-tail-20260829/spu-hot-window-ghidra.txt

Commit `d2a55df7c` makes both kernel selectors emulate `bi lr` when the SPU
entered at the registered selector address. It sets the PC from SPU link
register 0. A guard keeps direct host calls unchanged. The new selector-return
contract and the five related SPURS contracts passed. The full Android debug
build passed. Candidate APK
`A8BBB5EABAB8A73C7DDA4D7CCB48A4AF242137E3C14334310785164C6408FC6B`
is 116,139,585 bytes. The next cooled Thor run must verify that the second wake
now returns to dispatch and produces more than three LFQueue ring records.

## 102. The selector crosses the edge gate but needs HLE dispatch

The strict one-sample gate is capture
`20260829-080821-thor-input-strict-cool-gate`. Fixed silicon was 43.3 C. The
exact no-launch installation is capture
`20260829-080834-transformers-selector-return-install`. The expected, host, and
installed APK hashes matched. RPCSX was not active after installation.

Capture `20260829-080902-thor-input-custom` used the candidate from section 101
and repeated the no-census direct-Start route. The selector return crossed the
planned gate. Ring record 2 sent wake 1 at guest time 2:04.274. SPU 1 dispatched
workload 0 in the next 10 microseconds. The bounded log then reached 24 ring
records, 16 notifications, eight edge wakes, and 16 edge event-interpreter
entries and exits. Workload 0 was dispatched again after later wakes. The main
thread continued to create the FMOD taskset and its status thread at 2:59.206.

This candidate is not stable. Two workers entered the real guest dispatch at
`0x6c0` and reported access violations that read main-memory address `0x100`.
Their captured link register was `0x814`, which confirms the section 101 return
path. Ghidra shows that the real selector and dispatcher use local-store DMA
metadata. The HLE selector updates the HLE context but does not reproduce all
of that real-selector local-store state. Therefore, returning to guest dispatch
can use the system-service image sentinel `0x100` as a main-memory DMA source.
The continued loading progress does not make these violations acceptable.

Visual inspection of `01-selector-return-boundary.png` shows the Transformers
loading emblem. Its SHA-256 is
`FFFAF088F00CEF391512709502A9EB9DA08DFC70AEBB791BCA6BB03521385A33`.
The image includes a pause notice, so its 30.94 FPS value has no speed credit.
The route started at 43.7 C. Fixed silicon reached 68.7 C, maximum junction
reached 92.8 C, and the last fixed-silicon sample was 53.4 C. The macro stopped
RPCSX normally.

Commit `49e5b271e` completes registered selector callbacks with
`spursKernelDispatchWorkload` instead of guest dispatch. This keeps the selected
workload and poll status but uses the existing HLE workload-information copy,
image handling, register setup, and policy-module entry. Direct host selector
calls keep their existing control flow. The selector-dispatch contract and the
five related SPURS contracts passed. The full Android debug build passed.
Candidate APK
`5854545F1E179D87B01244002599923E1B2F76A20F5081F67CF3CB20459674A9`
is 116,139,488 bytes. The next cooled validation must retain the 24-ring
progress and contain no access violation.

## 103. The selector HLE dispatch is stable, but taskset join is missing

The strict one-sample gate is capture
`20260829-082253-thor-input-strict-cool-gate`. Fixed silicon was 43.7 C. The
exact no-launch installation is capture
`20260829-082306-transformers-selector-hle-dispatch-install`. The expected,
host, and installed APK hashes matched. RPCSX was not active after installation.

Capture `20260829-082330-thor-input-custom` repeated the no-census direct-Start
route. It retained 24 LFQueue ring records, 16 notifications, eight edge wakes,
and 16 edge event-interpreter entries and exits. All six SPU threads remained
active. The capture has no access violation, verification failure, native crash,
or fatal thread stop. This clears the selector HLE dispatch stability gate.

Visual inspection of `01-selector-hle-dispatch.png` shows the Transformers
loading emblem. Its SHA-256 is
`E66EC058CF5A41248AB101D30D2EFBED16AA5C9B59AB8FD59C65B5806D15368D`.
The image includes a pause notice, so its 30.94 FPS value has no speed credit.
Fixed silicon reached 68.7 C, maximum junction reached 83.9 C, and the last
fixed-silicon sample was 56.2 C. RPCSX stopped normally.

The log exposes the next HLE defect. The rendering thread calls
`cellSpursShutdownTaskset` and `cellSpursJoinTaskset` for taskset `0x1f73f00` at
guest time 4:00.711. Join is an unimplemented stub that returns success. The
thread creates another taskset at the same address at 4:25.986. The later event
signal sees task 0 waiting while its enabled bit is clear and returns
`CELL_SPURS_TASK_ERROR_SRCH`. The old workload still refers to the reused
taskset memory because join did not remove it.

The saved Sony `libsre` resolves the required lifecycle. Export NID
`0x9f72add3` maps to code address `0x15404`. Headless Ghidra shows that this
function validates the taskset, waits for workload shutdown, removes the
workload, and sets the taskset workload ID to `0x20`. The existing implemented
job-chain join uses the same order.

Commit `50f93a231` implements this taskset lifecycle and converts core invalid
and state errors to task errors. A focused source contract covers validation,
error conversion, call order, and workload-ID invalidation. The selector,
contention, queue, task-context, and probe-build contracts passed. The full
Android debug build passed. Candidate APK
`E0B528064B91ABBA6AF3D863F89DCC4E425D954B1FFD78754DC397150C200F76`
is 116,142,291 bytes. The next cooled Thor run must prove that join removes the
old taskset workload before the address is reused.

## 104. Taskset join stops stale reuse and exposes the missing notification

The strict one-sample gate is capture
`20260829-085535-thor-input-strict-cool-gate`. The fixed-silicon sample was
42.5 C, so it passed the less-than-70 C start rule. The exact no-launch
installation is capture
`20260829-085554-transformers-taskset-join-install`. The expected, host, and
installed APK hashes matched. RPCSX was not active after installation.

Capture `20260829-085618-thor-input-custom` repeated the dedicated HLE route.
The rendering thread called `cellSpursJoinTaskset` at guest time 4:26.707 and
waited for workload 7 to shut down. The game did not create a second taskset at
address `0x1f73f00`. The new join function therefore prevents the stale taskset
reuse from section 103.

The run produced 24 LFQueue ring records, eight edge wakes, and at least 60
bounded workload-dispatch records. It had no access violation, verification
failure, native crash, or fatal thread stop. The main thread continued its
staged allocations through guest time 4:27.850. It did not produce frames after
the later pause and resume.

Visual inspection of `01-taskset-join.png` shows a black field and a pause
notice. Its SHA-256 is
`98AF109D6A09C9075B610A356CEC63FA5FB480536AEEAAF8291D32E023296711`.
The reported 29.80 FPS has no speed credit. Fixed silicon reached 68.7 C,
maximum junction reached 81.9 C, and the last fixed-silicon sample was 53.8 C.
RPCSX stopped normally.

Source inspection found the exact reason that join did not return. The SPURS
system service changes a shutting-down workload to removable and makes a
shutdown-notification mask. However, its SPU event send was still a TODO. The
HLE initialization path also kept the event queue but did not create the
`SpursHdlr1` event-helper thread. The existing helper entry receives this mask
and posts the per-workload semaphore that releases join.

Commit `4b4d5f82b` sends the shutdown mask through the real SPU event path. It
also registers the existing event-helper entry and starts a normal joinable PPU
thread for it. The helper now exits through the PPU thread syscall. The new
shutdown-completion contract and 12 related SPURS contracts passed. The full
Android debug build passed. Candidate APK
`6D35D17466B099B668D3B9366BD46AD98153D30D30DBDA78C6255248EDF1F21D`
is 116,140,076 bytes.

This successor has host verification only. The hardware batch ended after the
taskset-join run. The next less-than-70 C Thor run must show the event-helper
entry, a shutdown-completion mask, join return, old-workload removal, and safe
taskset creation at the reused address. Rendering progress after that boundary
is the required result.

## 105. The event helper starts, but the hard guard stops before shutdown

The strict one-sample gate is capture
`20260829-091613-thor-input-strict-cool-gate`. Fixed silicon was 42.1 C, so it
passed the less-than-70 C start rule. The exact no-launch installation is
capture `20260829-091646-transformers-spurs-shutdown-completion-install`. The
expected, host, and installed APK hashes matched
`6D35D17466B099B668D3B9366BD46AD98153D30D30DBDA78C6255248EDF1F21D`.
RPCSX was not active after installation.

This run used `tools/thor_mcp/call.py` and kept profile replacement off. It used
the explicit HLE property stack with the selector, contention, taskset, queue,
task-attribute, edge-event, and two-SPU-reserve repairs on. The yield fast path
and queue publication experiment stayed off. The run used the installed SPU
object cache and enabled the draw, PUT, and PPU-PC censuses.

The run proved the first half of commit `4b4d5f82b` on Thor. The main thread
created and started `SpursHdlr1` at guest time 23.163 seconds. The helper entered
`event_helper_entry` at once and waited on event queue `0x8d005200`, SPU port
16. The log has no helper-creation error, fatal error, access violation,
verification failure, or native crash.

The short active window reached workload 7, queue ring record 576, and bounded
workload-dispatch record 1408. The draw census reached 840 flips and 13 draws.
The main thread continued memory allocation through guest time 26.763 seconds.
This is startup progress only. No screenshot was taken and no FPS value has
credit.

The run did not reach taskset shutdown. It has no shutdown-completion mask,
`cellSpursJoinTaskset` call, join return, workload removal, or second taskset
creation. Therefore, shutdown delivery and the complete join repair remain
unproved.

The external fixed-silicon guard read 74.7 C on its first runtime sample and
force-stopped RPCSX at the 72 C hard limit. The stopped-run capture is
`20260829-092025-transformers-shutdown-helper-thermal-stop`. The maintained
internal guard also reported a 91 C CPU-junction sample, but the junction domain
does not decide the fixed-silicon gate. The controlled stop left no PID. The
harness stop found zero RPCSX rows in `top`, and CPU junction then read 51 C.
All `debug.rpcsx.thor` properties were cleared after the run.

This attempt is `thermal-stop-before-shutdown`, `not-comparable`, and
`route-tooling`. It has no render, FPS, gameplay, or full-HLE credit.

The attempt also found two harness defects. PowerShell removed JSON key quotes
from the caller's native argument. Commit `b7451cef3` adds the
`THOR_CALL_ARGS` environment path, changes the cold gate to fixed silicon, and
adds a two-second 72 C guard to ready waits and CPU samples. Commit `0534106e9`
adds guarded input, bounded 0.1-to-5-second guest slices, and paused cooling.
Each slice starts only below 70 C, polls fixed silicon every 0.25 seconds, stops
at 72 C, and ends paused. Source contracts, Python syntax, and mocked safe-slice,
hard-stop, cool-wait, and input state-machine tests passed.

Do not run another continuous HLE wait. The next independently cool Thor round
must boot with profile replacement off and use the guarded pause/slice/cool
loop. It must accumulate enough guest time to reach shutdown while every active
slice starts below 70 C and stays below 72 C. The required proof remains the
shutdown mask, helper wake, join return, workload removal, safe taskset reuse,
and later rendering progress.

## 106. The dedicated probe now preserves the Transformers profile

The dedicated render probe used `tools/thor_input_macro.ps1`. That generic
macro forced the managed profile and replaced the custom title profile in its
debug-boot command. Therefore, the dedicated route did not preserve the same
BLUS30357 configuration as the maintained route from section 105.

The generic macro now has explicit `RequireManagedProfile` and
`ReplaceCustomProfile` switches. Both switches default to `on`, so existing
Eternal Sonata and generic callers keep their current behavior. The capture
README records both effective choices. The debug-boot command converts each
choice to an Android Boolean extra instead of using fixed `true` values.

`invoke_thor_transformers_hle_render_probe.ps1` passes `off` for both switches.
The next Transformers run can now preserve the current title profile and keep
the dedicated exact-APK, thermal, property-cleanup, and capture controls.

The Transformers route, PPU FTZ/NJ, display-pacing, multi-sensor thermal,
strict cool-gate, MCP fixed-silicon guard, and mocked guarded-slice contracts
passed. The PPU contract also now accepts later cache-version flags after
`uses_hardware_ftz`; it still requires that the hardware-FTZ flag is inside the
cache-identity enum and is set from the configuration.

This is host-route proof only. It does not change the device result from
section 105 and gives no HLE, render, FPS, or gameplay credit.

## 107. Guarded slices stop before the shutdown boundary

The strict gate is capture
`20260829-093930-thor-input-strict-cool-gate`. Fixed silicon was 42.1 C, so the
gate passed the less-than-70 C rule. The exact no-launch installation is
capture `20260829-093957-transformers-spurs-shutdown-completion-install`. The
expected, host, and installed APK hashes matched
`6D35D17466B099B668D3B9366BD46AD98153D30D30DBDA78C6255248EDF1F21D`.
RPCSX was not active after installation.

The MCP boot preserved the current title profile and used the explicit HLE
property stack. It started in the `Ready` state at 44.1 C fixed silicon. The
first slice found that a start-paused boot uses state 6, not state 4. It also
found that the first pause request can race core startup. Later slices ended
paused. The largest recorded slice sample was 71.9 C fixed silicon.

The stopped-run capture is
`20260829-094904-transformers-guarded-slices-process-exit`. It proves that
`SpursHdlr1` started and entered `event_helper_entry` on event queue
`0x8d005200`, SPU port 16. The rendering thread created taskset `0x1f73f00`
once and created its first task. Queue activity reached ring record 896.
Workload dispatch reached record 320. The draw census reached 54 records and
ended at 6,480 flips with two draw calls. This is early black-screen progress
only.

The run did not reach `cellSpursShutdownTaskset`, a shutdown-completion mask,
`cellSpursJoinTaskset`, workload removal, or a second taskset creation. It
therefore does not prove commit `4b4d5f82b` after the helper-entry boundary.
It has no screenshot or FPS credit.

A paused cooldown call remained active in a second host process while the main
host process sent the final slice. The cooldown call detected the hard thermal
condition and used the verified stop loop. Android records the external
force-stop of PID 12828 and its signal-9 exit. The capture has no access
violation, verification failure, emulator fatal error, OOM event, or
low-memory kill. The host did not retain the exact fixed-silicon trigger value.
The final stop check found no PID and zero RPCSX rows in `top`. Fixed silicon
was 48.2 C. All nonempty debug properties were cleared.

This attempt is `thermal-stop-before-shutdown`, `not-comparable`, and
`route-tooling`. It has no render, FPS, gameplay, shutdown, join, or full-HLE
credit.

The MCP harness now treats start-paused `Ready` and `Paused` as held states. A
bounded slice retries a raced pause and uses the verified stop if it cannot
restore a held state. The new `thor_slice_loop` tool owns slice, paused
cooldown, exact shutdown-marker checks, fatal checks, and hard stops in one
host process. A slice now sends pause before the slow ADB PID check. It does not
fetch device and diagnostic state inside each active slice. The paused cooldown
result also keeps the decisive fixed-silicon sample separate from the
response-time sample.

The mocked state-machine test covers the `Ready` state, a raced pause, compact
slices, marker detection on the second slice, and a fatal verified stop. The
fixed-silicon source contract, Python syntax, thermal contracts, strict cool
gate, and HLE pause contract passed.

The next independently cool Thor round must use only `thor_slice_loop`. It must
accumulate guest time until the shutdown-completion marker while each slice
starts below 70 C and the hard limit stays 72 C. The next required proof is the
helper wake, join return, workload removal, safe taskset reuse, and later
rendering progress.

## 108. Taskset join reaches the shared-state race

- Status: failed
- Scope: config-driver
- Hypothesis: The event-helper repair will deliver the shutdown notification
  and let the rendering thread complete taskset join.
- Changed files/settings: The installed candidate was unchanged at commit
  `02b5866b2`. It used HLE `libsre`, the HLE SPURS kernel, profile preservation,
  the current SPURS repair stack, and start-paused guarded slices. The yield
  fast path and queue-publication experiment stayed off.
- Rollback: No device state change remains. RPCSX was stopped and all 52
  nonempty `debug.rpcsx.thor.*` properties were cleared.
- Windows result: Not run. The failure boundary is in the Android HLE route.
- Thor result: The helper entered. The rendering taskset reached
  `cellSpursShutdownTaskset` and `cellSpursJoinTaskset` at guest time 1:46.715.
  No shutdown-completion mask or workload removal followed. The rendering
  thread remained in the workload-shutdown semaphore wait. The caller exceeded
  its 1,800-second host timeout, and the verified stop left no PID.
- Visual correctness: Not proved. No screenshot was taken. Draw calls stopped
  at 154 while flips continued to 51,720.
- FPS/frame-time: No credit. The result is not comparable and does not prove
  frame delivery.
- Capture paths: `20260829-100509-thor-input-strict-cool-gate` and
  `20260829-103802-transformers-slice-loop-host-timeout`.
- Decision: Source inspection indicates a race in the shared 128-byte workload
  state line. Concurrent SPU read-modify-write operations can restore a cleared
  status bit. This can prevent the final transition to removable and suppress
  the shutdown event. Commit `ecf235d67` puts the request, status, state, and
  shutdown-event updates under the guest reservation. This is a host-only
  successor, not a proved fix. Commit `a2cfd2c09` makes the cold-start decision
  use one fixed-silicon sample: below 70 C starts immediately, and 70 C or more
  refuses. Commit `f644623ae` bounds the slice loop to 420 host seconds and
  requests a verified stop if the caller itself times out.
- Next: In one later independent hardware round, install exact debug APK
  `756978BFFD348CA7553A38BB690BC4A28880EE19C5C984BF6568CDD91748CB2B`,
  size 116,142,297 bytes. Start when fixed silicon is below 70 C. Stop at 72 C.
  Require the shutdown mask, helper wake, join return, workload removal, safe
  taskset reuse, later real frames, and a correct 30 FPS scene before any HLE
  or performance claim.

## 109. Atomic shutdown state lets taskset join return

- Status: android-pass
- Scope: config-driver
- Hypothesis: One guest reservation for each shared SPURS workload-state update
  will prevent a concurrent SPU operation from restoring a cleared status bit.
  The shutdown helper will then signal the event, taskset join will remove the
  workload, and the game can reuse the taskset storage.
- Changed files/settings: Candidate APK SHA-256
  `756978BFFD348CA7553A38BB690BC4A28880EE19C5C984BF6568CDD91748CB2B`,
  size 116,142,297 bytes, contains commit `ecf235d67`. It uses one typed
  128-byte reservation operation for request processing, workload activation,
  and shutdown-completion updates. The run used HLE `libsre`, the HLE SPURS
  kernel, profile preservation, and the current SPURS repair stack. The yield
  fast path and queue-publication experiment stayed off.
- Rollback: RPCSX is stopped. `pidof` was empty, `top` had zero RPCSX rows, and
  the final fixed-silicon temperature was 49.4 C. All 59 nonempty
  `debug.rpcsx.thor.*` properties were cleared. The first cleanup command had a
  host quoting fault. A readback audit found 53 intended values and six known
  generic controls set to `off`. The corrected command left zero nonempty
  properties. Commit `3712524eb` adds one stopped-run cleanup tool with a final
  audit.
- Windows result: Not run. This test validates the Android HLE lifecycle.
- Thor result: The exact no-launch install matched the expected, host, and
  installed APK hashes. The fixed-silicon install gate passed at 43.3 C. Boot
  started at 41.7 C. Eight guarded slices reached the shutdown-completion mask
  at guest time 1:17.452. The slice starts were 44.9, 49.8, 52.2, 53.4, 56.2,
  55.8, 56.6, and 56.2 C. The maximum fixed-silicon value was 70.3 C. The
  rendering thread called shutdown and join at 1:17.116, and it created the
  same taskset address `0x1f73f00` again at 1:17.483. The join implementation
  waits for shutdown, removes the workload, invalidates the workload ID, and
  only then returns. Safe same-address creation therefore proves that join and
  removal completed. No task error, access violation, verification failure,
  fatal error, or out-of-memory error was observed.
- Visual correctness: Partial only. The first paused image shows a black
  Transformers loading screen with the Decepticon emblem. A second set of
  eight slices started at 50.2, 55.0, 57.4, 57.0, 57.8, 58.6, 57.8, and 60.6 C.
  It stayed below the 72 C hard stop and reached a 71.9 C maximum. The second
  paused image shows the Autobot loading emblem. Neither image shows correct
  3D or gameplay output.
- FPS/frame-time: No credit. The paused overlays showed 31.09 and 29.65, which
  are not measurements. The loading route is not comparable. Draw calls stayed
  at 202 for a long interval, then increased through 226, 288, 366, 450, 504,
  558, 631, 713, 779, 832, and 880 before they stopped again. A new taskset with
  attribute address `0x1158d800` appeared at guest time 3:11.530 before that
  burst. No valid 30 FPS scene exists.
- Capture paths: `20260829-105748-thor-input-strict-cool-gate`,
  `20260829-105805-transformers-spurs-atomic-shutdown-install`,
  `20260829-1058-transformers-atomic-shutdown-runtime`, and
  `20260829-110539-transformers-atomic-shutdown-reuse`. The last collector
  directory lost the runtime log because it did not select an ADB serial. The
  in-run controller queries and the two images supply the result evidence.
- Decision: Accept the narrow lifecycle hypothesis. The atomic shutdown repair
  fixes the observed join stall. Do not claim full HLE, gameplay, or a speed
  improvement. The route now stops later, after taskset reuse and a second
  loading-taskset draw burst. Commit `3712524eb` adds fatal and out-of-memory
  stops, audited property cleanup, and explicit collector device selection.
- Next: Keep the atomic repair. In the next independent cool Thor round, start
  below 70 C and stop at 72 C. Save the full log with serial `c3ca0370` while
  the guest is paused. Correlate the last PPU PCs, SPURS task state, queue-ring
  counters, PUT census, and draw census after taskset `0x1158d800` starts. Make
  no new source repair until that evidence identifies the blocked contract.

## 110. The short reuse run exposes a SPURS call-log flood

- Status: failed
- Scope: config-driver
- Hypothesis: A bounded slice run will pass the safe taskset-reuse boundary and
  identify the next blocked SPURS contract.
- Changed files/settings: The run used candidate APK SHA-256
  `756978BFFD348CA7553A38BB690BC4A28880EE19C5C984BF6568CDD91748CB2B`,
  size 116,142,297 bytes. It used the same 53-property HLE repair stack as
  section 109. The exact no-launch install and all property readbacks passed.
  Host successor commit `fb5ebb8fd` changes six hot SPURS call records from
  warning to trace and adds a source contract for their log levels. It does not
  change HLE behavior.
- Rollback: RPCSX was stopped. The stop check found no PID and no RPCSX row.
  Fixed silicon was 50.6 C after the stop. All 59 nonempty
  `debug.rpcsx.thor.*` properties were cleared, and the audit found zero values.
- Windows result: Six focused source contracts passed. They cover the new hot
  call log budget, event-flag wait, queue logging, workload signalling, taskset
  join, and shutdown completion. `git diff --check` passed. The normal Android
  debug build passed. Candidate APK SHA-256
  `C6936A68948E019D407BEB8BE1C76A3EA64EA611D109F29ECDC29F014E328897`
  is 116,142,103 bytes.
- Thor result: The fixed-silicon gate passed at 42.9 C. Boot started at 42.1 C.
  The host invocation did not retain the long-running controller session. The
  controller stopped after about 30 host seconds, and the guest stayed paused.
  A later state read found fixed silicon at 72.3 C, above the 72 C hard limit.
  RPCSX was stopped at once. This is a host-orchestration and thermal failure.
  It is not a comparable emulator result.
- HLE evidence: The rendering taskset at `0x1f73f00` shut down and joined. The
  shutdown-completion mask was delivered, and the same address was created
  again after workload removal. This reconfirms section 109. The log ended at
  about 1:18 guest time, before taskset `0x1158d800` appeared. Draws increased
  from zero to 387 and were still increasing when the run stopped. The target
  late boundary was not reached.
- Visual correctness: Not proved. No screenshot was taken in this run. The log
  shows loading-route progress only.
- FPS/frame-time: No credit. A state query reported 16.8 FPS while the guest was
  paused and the thermal guard was active. This is not a valid scene or window.
- Capture paths: `20260829-111529-thor-input-strict-cool-gate`,
  `20260829-111549-transformers-post-reuse-stall-install`, and
  `20260829-111951-transformers-post-reuse-stall-thermal-stop`.
- Log-flood evidence: `cellSpursWakeUp` wrote 8,322 records,
  `cellSpursEventFlagWait` wrote 748, `_cellSpursLFQueuePushBody` wrote 747,
  and `cellSpursLookUpTasksetAddress` wrote 653. These four records account for
  10,470 lines. The first three alone use about 1.39 MB of the 2.13 MB log.
  Their call-entry records are diagnostic data, not errors. The successor moves
  them and the paired try-wait and LFQueue-pop records to trace level.
- Decision: Keep the atomic shutdown repair. Accept only the log-level cleanup
  as the offline successor. Do not claim full HLE, gameplay, or a speed gain.
- Next: In a later independently cool round, install the exact successor APK.
  Start below 70 C and stop at 72 C. Keep the controller process attached.
  Require the `0x1158d800` boundary, later draw and PUT progress, a correct 3D
  image, and a comparable 30 FPS scene before any full-HLE or performance
  claim.

## 111. The SPURS log cleanup works, but slow telemetry extends slices

- Status: failed
- Scope: config-driver
- Hypothesis: Removing the measured hot SPURS call records will reduce default
  log pressure enough for an attached bounded-slice run to reach taskset
  `0x1158d800` under the 72 C hard stop.
- Changed files/settings: Candidate APK SHA-256
  `C6936A68948E019D407BEB8BE1C76A3EA64EA611D109F29ECDC29F014E328897`,
  size 116,142,103 bytes, contains commit `fb5ebb8fd`. The run used the same 53
  HLE properties as section 110 and six explicit generic controls. All 59
  readbacks matched. The exact no-launch install matched the expected, host,
  and installed APK hashes. RPCSX was absent after installation.
- Rollback: The controller force-stopped RPCSX. `pidof` was empty, `top` had
  zero RPCSX rows, and the stopped-run fixed-silicon sample was 49.0 C. The
  cleanup cleared all 59 nonempty `debug.rpcsx.thor.*` properties. Its audit
  found zero remaining values.
- Windows result: Not run. This test validates the Android HLE route and the
  Android controller.
- Thor result: Strict gate capture
  `20260829-113023-thor-input-strict-cool-gate` passed at 42.5 C fixed silicon.
  Boot started at 41.3 C. Six complete slices started at 46.2, 51.8, 53.0,
  54.6, 55.0, and 55.8 C. Their recorded maxima were 61.0, 64.2, 67.4, 66.2,
  67.4, and 71.5 C. Slice 7 started after a 60.6 C cooldown sample, reached
  73.1 C, and used the verified stop. This exceeds the 72 C hard limit and is
  a thermal failure.
- HLE evidence: The log ended at guest time 1:08.770. It reached three initial
  tasksets, 720 flips, two draw calls, PUT census 2,000, and bounded workload
  dispatch record 960. It did not create the rendering taskset, reach shutdown
  or join, or create taskset `0x1158d800`. It therefore adds no lifecycle or
  late-HLE proof. The log has no SPURS task error, access violation,
  verification failure, fatal error, or out-of-memory error.
- Visual correctness: Not proved. No screenshot was taken. The counters show
  early loading only.
- FPS/frame-time: No credit. The last sensor record reports 21 frames in ten
  seconds while the loading route and thermal stop were active. This is not a
  correct or comparable gameplay scene.
- Capture paths: `20260829-113023-thor-input-strict-cool-gate`,
  `20260829-113056-transformers-spurs-hot-log-install`, and
  `20260829-113424-transformers-spurs-hot-log-thermal-stop`.
- Log result: The four records measured in section 110 are absent. The complete
  log is 405,856 bytes, compared with 2,134,369 bytes for the similar 78-second
  section-110 capture. This proves log-volume reduction only. It does not prove
  a speed or thermal improvement. The next visible hot pair is the underlying
  cellSync LFQueue push and pop entry. Push wrote 224 records and 39,424 bytes.
  The successor moves both call-entry records from warning to trace.
- Controller result: Each slice requested one second, but recorded 1.250 to
  2.968 host seconds. A fixed-silicon ADB read can block beyond the requested
  deadline, so the same controller thread cannot send pause on time. The
  successor starts an independent deadline timer that sends pause through the
  in-process control API. The main controller thread continues to sample fixed
  silicon and still uses the verified stop at 72 C. Slice results now retain
  the time at which the deadline pause was requested.
- Host verification: Python syntax, the mocked guarded-slice state machine, the
  two-second blocked-telemetry deadline-pause case, the fixed-silicon source
  contract, the cellSync LFQueue log budget, and both SPURS log-budget contracts
  passed. `git diff --check` passed. The normal Android debug build passed.
  Candidate APK SHA-256
  `0843DE9B58717B0F8F4648FB1A7CF995A49236BE43F77AA411639C56845911AB`
  is 116,142,104 bytes.
- Upstream research: The read-only RPCS3 comparison checkout was fetched to
  `origin/master` commit `eb61fc1fb`. The current `cellSpursJoinTaskset` still
  returns success from an unimplemented stub. SPURS task-attribute creation,
  LFQueue bodies, and queue bodies also remain unimplemented. Current
  `armsx3/master` has no different SPURS or cellSync implementation. The latest
  relevant upstream SPURS change is `d7ed328f4`, which adds PPU wait state around
  reservation operations. This branch already carries that exact file-level
  port in commit `47cff93031`. There is no new upstream HLE body to import.
- Decision: Accept the SPURS log cleanup as a log-volume result. Reject the run
  for HLE and speed proof. Keep the hard stop. Do not run the Thor again in this
  hardware round.
- Next: In a later independently cool round, install the exact successor APK,
  start below 70 C, stop at 72 C, and require the controller to report a pause
  request near each requested slice deadline. Continue to taskset `0x1158d800`
  only if that timing contract holds. Require a correct 3D image and a
  comparable 30 FPS gameplay window before any full-HLE or performance claim.

## 112. Deadline pauses work and expose a later stream wait

- Status: failed
- Scope: config-driver
- Hypothesis: An independent deadline timer will pause each one-second guest
  slice on time despite a slow fixed-silicon read. The guarded route can then
  reach taskset marker `0x1158d800` without a telemetry overrun.
- Changed files/settings: The run used candidate APK SHA-256
  `0843DE9B58717B0F8F4648FB1A7CF995A49236BE43F77AA411639C56845911AB`,
  size 116,142,104 bytes. It contains commit `79a144d0a`. The exact no-launch
  install passed. All 59 HLE and generic property readbacks matched.
- Rollback: The slice controller force-stopped RPCSX at the hard limit.
  `pidof` was empty, `top` had zero RPCSX rows, and the process was quiet. The
  cleanup cleared all 59 nonempty `debug.rpcsx.thor.*` properties. Its audit
  found zero remaining values. The final fixed-silicon sample was 51.8 C.
- Windows result: The successor load-wait probe contract and
  `git diff --check` passed. The normal Android debug build passed in 1 minute
  13 seconds. Successor APK SHA-256
  `7485031E3F00399F6133A09727B167EE9C5825D902B4CE9B4F0AC99E41D2AD32`
  is 116,142,628 bytes and contains commit `204c2bac8`.
- Thor result: The one-sample gate passed at 42.9 C fixed silicon. Boot started
  at 42.1 C. The controller produced 58 complete timed slices. Every complete
  slice requested pause at 1.000 to 1.016 seconds. Slice 59 reached 72.3 C
  fixed silicon and used the verified stop. The host duration was 251.531
  seconds. This is a thermal stop, but the deadline-timer hypothesis passes.
- HLE evidence: The rendering taskset at `0x1f73f00` shut down and joined. The
  shutdown-completion mask arrived, and the title safely created the same
  taskset address again. The log ended after 5,880 flips, 475 draw calls,
  queue-push record 4,672, and workload-dispatch record 2,560. It did not reach
  marker `0x1158d800`. Draw calls paused at 426, increased to 447 and then 475,
  and stopped increasing before the thermal stop. No SPURS task error, access
  violation, verification failure, fatal error, or out-of-memory error was
  observed.
- Ghidra result: The late PPU census repeatedly put `main_thread` in the common
  sleep wrapper with link register `0x00523690`. A focused read-only Ghidra pass
  on the verified BLUS30357 ELF shows that this call is in a stream-read loop.
  The loop sleeps while the second pending-read count at stream offset `0xc4`
  is not zero. At the same time, `AsyncIOSystem` used link register
  `0x0051aea4`. Ghidra maps that call to the sleep arm used when the IO worker
  has an active entry. This evidence identifies a late active IO request. It
  does not yet show whether its backend completion word is stuck or whether a
  later SPURS handoff does not complete.
- Visual correctness: Not proved. The marker did not appear, so the controller
  did not take a paused screenshot. The counters show loading-route progress,
  not correct gameplay.
- FPS/frame-time: No credit. A sensor row reported 28 frames in ten seconds,
  but the window included repeated global pauses and is not a comparable
  gameplay sample.
- Capture paths: `20260829-114701-thor-input-strict-cool-gate`,
  `20260829-114719-transformers-deadline-pause-install`, and
  `20260829-115314-transformers-deadline-pause-thermal-stop`. The focused Ghidra
  output is `ghidra-transformers-current-main-wait-20260829.txt`.
- Decision: Keep the deadline timer and the atomic taskset lifecycle repair.
  Reject this run for full HLE, gameplay, and speed proof. Commit `204c2bac8`
  adds a bounded diagnostic for the exact late stream wait. It records both
  pending counts, request ranges, the first active IO entry, and its completion
  word. It does not change guest state.
- Next: In a later independently cool Thor round, install exact successor APK
  `7485031E3F00399F6133A09727B167EE9C5825D902B4CE9B4F0AC99E41D2AD32`.
  Start immediately below 70 C and stop at 72 C. Require two stable late-load
  samples. Use the completion word and active-entry fields to select the next
  semantic repair. Do not claim full HLE or 30 FPS until a correct moving 3D
  scene and a comparable sustained measurement both pass.

## 113. The late loader completion stays at one

- Status: failed
- Scope: config-driver
- Hypothesis: The late-load probe will show whether the active IO worker waits
  on a backend completion word or on a later stream-state update.
- Changed files/settings: The run used candidate APK SHA-256
  `7485031E3F00399F6133A09727B167EE9C5825D902B4CE9B4F0AC99E41D2AD32`,
  size 116,142,628 bytes. It contains commit `204c2bac8`. The exact no-launch
  install passed. The run used HLE `libsre`, the HLE SPURS kernel, the firmware
  LFQueue path, atomic task selection, the edge event interpreter, the task
  attribute repair, the Transformers SPU reserve, the cached PPU time repair,
  and all bounded censuses. The guest started paused.
- Rollback: One first wrapper call failed before launch because a
  device-telemetry macro did not have a stop token. The cleanup cleared 49
  properties and found zero remaining values. After the successful run, RPCSX
  was stopped. `pidof` was empty, `top` had zero RPCSX rows, and the process
  was quiet. The cleanup cleared 50 properties and found zero remaining
  values. The final fixed-silicon sample was 50.2 C.
- Windows result: The LFQueue route contract, the late-load contract, and
  `git diff --check` passed. The normal Android debug build passed. Successor
  APK SHA-256 `700CBA11F366281AD3992ADE081C0F8DDB1CA1C5A29DE80447E14DAD544AC041`
  is 116,142,809 bytes and is built from commit `05939113d`.
- Thor result: The one-sample gate passed at 43.3 C fixed silicon. The initial
  paused state was 51.4 C. The controller completed 19 one-second slices and
  reached the second late completion sample. Every deadline pause request was
  at 1.000 to 1.016 seconds. The maximum fixed-silicon value was 71.1 C, and
  the final paused value was 59.4 C. The host duration was 80.125 seconds.
  No thermal stop occurred.
- HLE evidence: Four samples over 30 seconds kept the same active IO entry and
  the same first completion item. The active list had four completion items.
  The first state word stayed mapped at `0x11301d10` with value `1`. The stream
  stayed at request `9212500+1018348`; its second cache was pending, and the
  worker queue was empty. The edgeZlib task processed earlier LFQueue jobs and
  returned 32 recorded event results. At the late boundary, the taskset state
  was `running=ready=signalled=0x80000000`, with one running task and shared
  contention one. A second SPU selected task ID 128 because task 0 was already
  running. This state does not yet prove whether the running task is stuck in
  guest code or whether its completion store is missing.
- Ghidra result: Existing verified BLUS30357 analysis shows that the active IO
  worker removes a completion item only when its state word becomes zero. The
  loader creates one state word per chunk, sets it to one, and passes it in the
  backend job record. Forcing the word to zero would bypass real work and is
  not an acceptable repair.
- Probe result: The enabled edgeZlib PC census wrote no samples because it used
  its 64-sample quota during startup. The monitor ticks every 0.5 second, so
  the old code stopped after 32 seconds. The title loaded the edgeZlib task at
  about 46.4 seconds. Commit `05939113d` now increments the quota only after
  the edgeZlib local-store signature matches. The probe remains bounded to 64
  matching samples and does not change guest state.
- Visual correctness: Partial only. The paused image shows the PhysX and Unreal
  startup legal screen. Draw calls stopped at four. It does not show correct
  gameplay or moving 3D output.
- FPS/frame-time: No credit. The paused overlay showed 29.71 FPS. The guest was
  paused on a startup screen, so this number is not a gameplay measurement.
- Capture paths: `20260829-120954-thor-input-strict-cool-gate`,
  `20260829-121016-transformers-late-load-completion-install`,
  `20260829-121124-thor-input-custom`, and
  `20260829-121507-transformers-late-load-completion-marker`.
- Decision: Keep the late-load probe and the current semantic repair stack.
  Do not change the completion word. Reject this run for full HLE, gameplay,
  and speed proof. Accept only the corrected PC census as the offline
  successor.
- Next: In a later independently cool Thor round, install exact successor APK
  `700CBA11F366281AD3992ADE081C0F8DDB1CA1C5A29DE80447E14DAD544AC041`.
  Start immediately below 70 C and stop at 72 C. Require stable late-load
  completion samples and matching `Thor EDGE PC` samples. Map the stable guest
  PC in the saved legal edgeZlib image before a semantic repair. Do not claim
  full HLE or 30 FPS until a correct moving 3D scene and a comparable sustained
  measurement both pass.

## 114. The edge task does not have one stable blocked PC

- Status: failed
- Scope: config-driver
- Hypothesis: The corrected edgeZlib PC census will find one stable guest PC
  while the late loader completion word stays at one.
- Changed files/settings: The run used candidate APK SHA-256
  `700CBA11F366281AD3992ADE081C0F8DDB1CA1C5A29DE80447E14DAD544AC041`,
  size 116,142,809 bytes. It contains commit `05939113d`. The exact no-launch
  install passed. The semantic HLE settings matched experiment 113. The guest
  started paused. The controller used one-second slices and stopped when the
  second late completion sample appeared.
- Rollback: RPCSX was stopped after the capture. `pidof` was empty, and `top`
  had zero RPCSX rows. The cleanup cleared all 50 nonempty
  `debug.rpcsx.thor.*` properties and found zero remaining values. The fixed
  silicon value after the stop was 49.8 C.
- Windows result: The successor ANY2ANY LFQueue contract and hot-log budget
  contract pass. `git diff --check` passes. The normal Android debug build
  passes. Successor APK SHA-256
  `A000C7FC292737D05F44AE780C86A1D393126863B2C6EB90D32681C28EE7FEDB`
  is 116,143,185 bytes.
- Thor result: The strict cool gate passed at 43.3 C fixed silicon. The route
  reached the second late completion sample after 19 one-second slices and
  about 80 seconds of host time. All pause requests occurred at 1.000 to 1.016
  seconds. The maximum fixed-silicon value was 71.9 C, below the 72 C hard
  stop.
- HLE evidence: The exact edge queue is `0x101b1f80`. Its buffer is
  `0x101b2000`, its item size is 32 bytes, and its depth is 16. The task
  processed queue items, ran decompression work, sent event notifications, and
  returned zero from the recorded event operations. Four late samples kept the
  first completion state at `0x1111dff0` equal to one. The worker queue was
  empty, and the active list had ten completion items. No fatal error, access
  violation, or native signal occurred.
- Ghidra result: A headless Ghidra 12.0.4 pass used the saved legal 256 KiB
  edgeZlib local-store image with language `SPU:BE:128:default`. The sampled
  PCs map to callback, queue, DMA, decompression, atomic, and event-notification
  paths. PC `0x08d54` is an indirect callback return. PCs `0x094fc` and
  `0x09940` are queue and atomic paths. PCs `0x042e0`, `0x050e8`, `0x06774`,
  `0x066d0`, `0x05e34`, and `0x048bc` are helper or data paths. PC `0x088d8`
  is an event-flag atomic helper. The task enters the mailbox helper at
  `0x0a4d8` and returns at `0x08ca8`. This is normal task progress, not one
  stable blocked PC.
- Research result: Public Sony material confirms that EDGE zlib used SPUs and
  that its source was supplied with the PS3 SDK. No public queue-item ABI source
  was found. Current public RPCS3 sources do not supply this missing item
  contract. Do not use proprietary SDK leaks as a source.
- Visual correctness: Not proved. The paused image shows the black Transformers
  loading screen and its Autobot loading icon. It does not show gameplay.
- FPS/frame-time: No credit. The paused overlay showed 31.02 FPS. This is a
  paused loading screen, not a sustained moving gameplay sample.
- Capture paths: `20260829-123125-thor-input-strict-cool-gate`,
  `20260829-123141-transformers-edge-pc-census-install`, and
  `20260829-123308-thor-input-custom`. The Ghidra output is
  `ghidra-edge-zlib-pc-census-20260829/edge-pc-census-ghidra.txt`.
- Decision: Reject the stable-PC hypothesis. Keep the current semantic HLE
  repairs. Do not force the completion word to zero, and do not classify the
  task ID 128 selection on a second SPU as a scheduler failure. The successor
  adds a bounded, read-only census for the first 128 items on the exact
  32-byte edgeZlib LFQueue. It records each item after the producer copy and
  before publication.
- Next: Commit and push the successor. In a later independently cool Thor
  round, install the exact successor without launch. Start immediately below
  70 C and stop at 72 C. Run one late-load route. Match the persistent
  completion-state address against the eight words in each `Thor EDGE LFQ ITEM`
  row. Identify the item field and the guest or HLE owner of its zero store
  before any semantic repair. Require correct moving 3D output and a comparable
  sustained 30 FPS measurement before a full-HLE or performance claim.

## 115. Boot jobs exhausted the first-item trace

- Status: failed
- Scope: config-driver
- Hypothesis: The first 128 edgeZlib queue items will include the late loader
  completion address.
- Changed files/settings: The run used exact APK SHA-256
  `A000C7FC292737D05F44AE780C86A1D393126863B2C6EB90D32681C28EE7FEDB`,
  size 116,143,185 bytes. The HLE settings matched experiment 114. The guest
  started paused. The controller used one-second slices and searched for the
  second late-load completion sample.
- Rollback: The fixed-silicon guard stopped RPCSX when slice 29 sampled 72.3 C.
  The verified stop found no PID and zero RPCSX rows in `top`. The host then
  pulled the unchanged guest log. The cleanup cleared all 50 nonempty
  `debug.rpcsx.thor.*` properties and found zero remaining values. The final
  fixed-silicon value was 48.6 C. Do not launch the Thor again in this hardware
  round.
- Thor result: The strict gate passed at 42.5 C fixed silicon. The exact
  no-launch install passed. The route completed 28 one-second slices before
  the hard-stop sample during slice 29. Host elapsed time was 144.625 seconds.
  The late-load boundary did not occur. This result is
  `thermal-stop-before-late-boundary`, `failed`, and `not-comparable`.
- Queue evidence: The log contains all 128 bounded `Thor EDGE LFQ ITEM` rows.
  Word 4 is `0x00000001` in every row. The trace contains no
  `0x1111dff0` value and no other counter-backed item. These rows are the early
  event-backed boot jobs. They do not contain the late completion request.
- Atomic evidence: The table has 87 new entries and stops at slot 86. It did
  not saturate. It contains no EDGE completion GETLLAR or PUTLLC at PCs
  `0x0a1f0`, `0x0a22c`, `0x0a2b0`, or `0x0a2ec`. The run therefore does not
  show a counter-backed completion operation.
- Ghidra result: The legal PPU image shows that function `0x00a88564` stores
  the completion address and low mode bit at item offset `0x10`. The legal
  edgeZlib image loads the second item quadword at `0x031fc`, clears the low
  bit at `0x03200`, and calls the decrement helper at `0x0322c` when the
  masked value is nonzero. A raw word-4 value of one selects the event-backed
  path. Therefore, a counter-backed-only trace is sufficient and more precise.
- Visual correctness: Not proved. The guard stopped the process before the
  requested late-load screenshot.
- FPS/frame-time: No credit. No moving gameplay measurement exists.
- Capture paths: `20260829-130157-thor-input-strict-cool-gate`,
  `20260829-130209-transformers-edge-lfq-item-install`, and
  `20260829-130239-thor-input-custom/RPCSX.log`.
- Decision: Reject the first-128 strategy. The successor counts all exact-queue
  jobs but spends its bounded log quota only when `(word4 & ~1) != 0`. It logs
  the total item number, the raw word, and the masked completion address. The
  atomic census now prints periodic rows every 4096 hits, as its comment
  specifies, instead of every 64 hits. New triples and the first eight hits
  remain visible.
- Windows result: The ANY2ANY LFQueue, Transformers HLE route, LFQueue log
  budget, and late-load wait contracts pass. `git diff --check` passes. The
  normal Android debug build passes. Successor APK SHA-256
  `E27DD6841EC555A721DA6469DD66D7EA8627217B4D80B09F383B605BA1DFFDB6`
  is 116,143,403 bytes.
- Next: Commit the successor. In a later independently cool Thor round, install
  the exact successor without launch. Start immediately below 70 C and stop at
  72 C. Stop the slice loop on `Thor EDGE LFQ COUNTER ITEM #0`. Match its
  completion address with the EDGE LL/SC rows and the late-loader state before
  a semantic repair. Require correct moving 3D output and a comparable sustained
  30 FPS measurement before a full-HLE or performance claim.

## 116. The direct EDGE submit paths are event-backed

- Status: inconclusive
- Scope: static-analysis
- Hypothesis: A direct caller of the EDGE item producer will show where the
  late counter-backed request enters the queue.
- Ghidra result: The saved legal PPU image has one direct call to producer
  `0x00a88564`. It is at `0x00a88810` in wrapper `0x00a887e0`. The wrapper has
  two direct callers, at `0x009e3368` and `0x009e3558`. Their functions start
  at `0x009e3200` and `0x009e33f8`. Both functions pass zero as the completion
  pointer. One passes low mode bit one, and the other passes low mode bit zero.
  These direct paths cannot create a counter-backed item.
- Tool result: `FindPowerPcCalls.java` now skips initialized ranges that are
  outside the default address space. It also decodes relative and absolute
  direct calls. A headless Ghidra 12.0.4 read-only run completed without the
  prior address-space error. The complete direct-call scan found only the
  three calls above. A byte scan found no stored producer or wrapper address
  in the PPU image.
- Runtime relation: The result agrees with the 128 early Thor items whose raw
  completion word was one. It does not prove that the late completion state
  belongs to this EDGE queue. An indirect or runtime-linked path is still
  possible, and the late state can also belong to a different work system.
- Decision: Do not add a completion repair from the static result. Keep the
  counter-backed-only runtime trace. It can prove whether the late request
  enters this exact queue without a high-rate boot trace.
- Next: In the next independently cool Thor round, install exact APK
  `E27DD6841EC555A721DA6469DD66D7EA8627217B4D80B09F383B605BA1DFFDB6`.
  Start immediately below 70 C and stop at 72 C. Stop on the first
  `Thor EDGE LFQ COUNTER ITEM` row or the second late completion sample. If the
  late state appears without a counter-backed item, reject this EDGE queue as
  its owner and move the HLE repair to the work system that owns the state.

## 117. The loader waits after event-backed EDGE jobs

- Status: inconclusive
- Scope: config-driver, static-analysis
- Hypothesis: The late loader completion state will appear in a counter-backed
  item on the exact edgeZlib queue.
- Changed files/settings: The run used exact APK SHA-256
  `E27DD6841EC555A721DA6469DD66D7EA8627217B4D80B09F383B605BA1DFFDB6`,
  size 116,143,403 bytes. The HLE settings matched experiment 116. The guest
  started paused. The controller used one-second slices and stopped when the
  second late-load completion sample appeared.
- Rollback: RPCSX was stopped after the capture. The cleanup cleared the
  experiment properties. The final fixed-silicon value was 49.0 C. Do not
  launch the Thor again in this hardware round.
- Thor result: The strict cool gate passed at 42.9 C fixed silicon. The exact
  no-launch install passed. The route completed 19 one-second slices. All
  pause requests occurred at 1.000 to 1.016 seconds. The maximum fixed-silicon
  value was 71.1 C. No thermal stop occurred.
- HLE evidence: The run recorded 16 successful EDGE event operations on port
  17 and event queue `0x8d005600`. The direct jobs use shared event flag
  `0x01e54800`. At the second late sample, the active loader list had 14
  completion items. Its first mapped state was `0x111e4370`, and its value
  stayed at one. No counter-backed EDGE item appeared. No access violation,
  verification failure, fatal error, or out-of-memory error appeared.
- Causal correction: The decision in experiment 116 to reject this EDGE queue
  as the owner is too strong and is superseded here. The asynchronous loader
  counter is separate from the event-backed EDGE queue item. The observed path
  is asynchronous IO, event-backed EDGE zlib work, the wait wrapper at
  `0x009e35e4`, slot release, and loader finalization. A queue item does not
  need to contain the loader counter for the EDGE wait to control that
  finalization.
- Ghidra result: A read-only Ghidra 12.0.4 pass used the saved legal edgeZlib
  image and function `0x000088d8`. The SPU helper uses GETLLAR to read the full
  128-byte event flag. It writes the control state and the selected
  `pendingRecvTaskEvents` slot in local store. It then uses PUTLLC to write the
  full flag and calls the LV2 event helper at `0x0000a4d8` when the wake
  condition succeeds. This result rules out a missing SPU result-slot store.
  The PPU wrapper requests one event bit with AND mode, so the mode is valid.
- Diagnostic successor: The title-gated property
  `debug.rpcsx.thor.edge_event_wait_trace=1` now records at most 64 waits on
  exact event flag `0x01e54800`. It records the requested mask, the armed wait
  slot, the SPU result slot, the returned mask, the receive state, and the
  control state. It does not change guest state. The probe wrapper exposes the
  property and clears it during cleanup.
- Windows result: The SPURS event-flag wait, Transformers HLE LFQueue route,
  late-load wait, ANY2ANY LFQueue firmware, and LFQueue log-budget contracts
  pass. `git diff --check` passes. The normal Android debug build passes.
  Successor APK SHA-256
  `3944A8C1C7984E86206208922B837C4BA516F81911F67397C06E6DCE76E5AC01`
  is 116,143,340 bytes.
- Visual correctness: Not proved. The paused image shows the black loading
  screen. It does not show gameplay.
- FPS/frame-time: No credit. The paused overlay showed 29.62 FPS and API 8.2.
  This is not a sustained moving gameplay measurement.
- Capture paths: `20260829-132346-thor-input-strict-cool-gate`,
  `20260829-132400-transformers-edge-counter-item-install`, and
  `20260829-132429-thor-input-custom`. The focused Ghidra output is
  `ghidra-edge-event-flag-function-20260829.txt`.
- Decision: Keep the current semantic repair stack. Reject the counter-backed
  item hypothesis. Do not force the loader counter or the event result. The
  next run must correlate the requested bit, the armed slot, the SPU wake
  result, and the returned mask before a semantic repair.
- Next: In a later independently cool Thor round, install exact successor APK
  `3944A8C1C7984E86206208922B837C4BA516F81911F67397C06E6DCE76E5AC01`
  without launch. Start immediately below 70 C and stop at 72 C. Enable only
  the bounded event-wait trace with the required HLE settings. Stop on the
  second late completion sample. Require correct moving 3D output and a
  comparable sustained 30 FPS measurement before a full-HLE or performance
  claim.

## 118. The sampled EDGE event waits complete correctly

- Status: failed, not-comparable
- Scope: config-driver, static-analysis
- Hypothesis: An EDGE event-flag wait will stay armed after the late loader
  completion state appears.
- Changed files/settings: The run used exact APK SHA-256
  `3944A8C1C7984E86206208922B837C4BA516F81911F67397C06E6DCE76E5AC01`,
  size 116,143,340 bytes. The HLE settings matched experiment 117. The guest
  started paused. The controller requested one-second slices.
- Rollback: The external thermal guard stopped RPCSX. The process was absent
  after the run. The experiment-specific event-wait trace property was zero.
  The post-stop fixed-silicon value was 56.2 C. Do not launch the Thor again in
  this hardware round.
- Thor result: The strict cool gate passed at 42.5 C fixed silicon, and the
  post-gate value was 43.3 C. The exact no-launch install passed. The run ended
  during the eleventh slice before the requested late boundary. The external
  guard recorded fixed-silicon values of 48.2, 46.2, 53.0, 55.0, 56.6, 69.1,
  68.2, 70.7, 70.3, and 74.7 C. The last sample exceeded the 72.0 C hard
  limit, so the guard killed RPCSX. The input wrapper then reported a missing
  process. The guard log identifies this result as a thermal stop, not as
  evidence of a native crash.
- Event-wait evidence: The trace contains 64 ARM rows, 64 WAKE rows, and 64
  RETURN rows. It contains no BUSY row and no mismatch. Every sampled call
  used flag `0x01e54800`, request `0x0001`, AND mode, slot zero, SPU result
  `0x0001`, and return result `0x0001`. Each call returned success and cleared
  the PPU receive state. The first sampled wait armed at guest time 18.100
  seconds and woke at 22.652 seconds. The other sampled waits completed by
  guest time 23.751 seconds. Therefore, the first-64 quota measured boot work
  and did not reach the late-loader state.
- Ghidra result: The saved legal PPU image shows the following chain. Function
  `0x00519ce0` allocates and initializes each asynchronous loader completion
  counter. Function `0x0051708c` queues a separate child request. The worker
  around `0x0051aea4` polls the child completion list through `0x013bcce0` and
  decrements the child counter only after that list becomes empty. The EDGE
  backend at `0x00a08798` submits event-backed work through `0x009e33f8` and
  waits through `0x009e35e4`. The wait wrapper allocates one bit from pool
  `0x019de3b0`, waits on flag `0x01e54800`, and then releases the bit. Thus, a
  successful event wait is necessary but is not sufficient to prove loader
  finalization.
- Visual correctness: Not proved. The guard stopped the run before the late
  screenshot boundary.
- FPS/frame-time: No credit. No moving gameplay measurement exists.
- Capture paths: `20260829-134828-thor-input-strict-cool-gate`,
  `20260829-134845-transformers-edge-event-wait-install`, and
  `20260829-134956-thor-input-custom`. The focused Ghidra outputs are
  `ghidra-transformers-edge-backend-decompile-20260829.txt`,
  `ghidra-transformers-edge-submit-functions-decompile-20260829.txt`, and
  `ghidra-transformers-loader-owners-decompile-20260829.txt`.
- Decision: Reject the first-64 hot-path log. Do not repair the event result or
  the loader counter from this evidence. Keep the current semantic stack. The
  successor stores the current event-wait state in low-overhead atomics. It
  logs only the first four calls, each 128th call through call 2048, and every
  mismatch. The existing late PPU census reads the live state and reports an
  active age and a wake latency at the late-loader boundary.
- Windows result: The SPURS event-flag wait, Transformers HLE route, late-load
  wait, ANY2ANY LFQueue firmware, and LFQueue log-budget contracts pass.
  `git diff --check` passes. The normal Android debug build passes. Successor
  APK SHA-256
  `C3BF97865700E7B35E407321A4B01BEAEC93AC796483A8964633E0ECE6479C04`
  is 116,141,896 bytes.
- Next: Commit the successor. In a later independently cool Thor round, install
  the exact successor without launch. Enable the event-wait trace and runtime
  census with the required HLE settings. Start immediately below 70 C, use
  one-second paused slices, and stop at 72 C or the second late sample. Inspect
  `Thor EDGE EFWAIT STATE` before a semantic repair. Require correct moving 3D
  output and a comparable sustained 30 FPS measurement before a full-HLE or
  performance claim.

## 119. Heat stopped the live wait probe before the late boundary

- Status: failed, not-comparable
- Scope: config-driver, static-analysis
- Hypothesis: The live event-wait state will identify the late EDGE wait before
  the thermal guard stops the run.
- Changed files/settings: The run used exact APK SHA-256
  `C3BF97865700E7B35E407321A4B01BEAEC93AC796483A8964633E0ECE6479C04`,
  size 116,141,896 bytes. The HLE settings matched experiment 118. The event
  wait trace and runtime census were on. The guest started paused, and the
  controller requested one-second slices.
- Rollback: The external thermal guard stopped RPCSX. Android ActivityManager
  killed PID 18530 after an external `am force-stop` request. No fatal signal,
  tombstone, access violation, or native crash appears. The process was absent
  after the run. Do not launch the Thor again in this hardware round.
- Thor result: The strict gate passed at 43.3 C fixed silicon. The post-gate
  value was 44.1 C, and the no-launch install left the process absent. The
  device guard recorded 49.8, 55.0, 53.8, 57.4, 64.2, 67.8, 69.5, 68.7, and
  73.9 C. The last sample exceeded the 72.0 C hard limit. The run ended during
  the tenth pause before the late-loader completion sample.
- Event-wait evidence: The log contains only `Thor EDGE EFWAIT ARM #0`. It
  armed guest flag `0x01e54800`, mask one, AND mode, slot zero, queue
  `0x8d005600`, and port 17 at guest time 19.150 seconds. The guard stopped the
  process at about guest time 22.44 seconds. The observed active interval was
  only about 3.3 seconds. The first known-good wait in experiment 118 took
  about 4.55 seconds. Therefore, the missing wake in this run does not identify
  a stuck wait.
- SPU evidence: Sampled edgeZlib PCs changed through `0x09514`, `0x03140`,
  `0x03aa0`, `0x050e8`, `0x07168`, `0x07c00`, and `0x06050` while compiled
  block counts increased. The SPU did not stay at one stable PC.
- Visual correctness: Not proved. The guard stopped the process before the
  requested screenshot.
- FPS/frame-time: No credit. No moving gameplay measurement exists.
- Capture paths: `20260829-140933-thor-input-strict-cool-gate`,
  `20260829-140952-transformers-edge-wait-live-install`, and
  `20260829-141032-thor-input-custom`.
- Decision: Do not repair the event result or loader state from this run. The
  stronger experiment 117 evidence still shows the PoolThread in the event
  wait wrapper for at least 30 seconds while the loader completion value stays
  at one. Correlate that PPU wait with the exact SPU event-send count. Do not
  repeat the full runtime census because its observation load heats the Thor.
- Next: Count every exact edgeZlib event send in low-overhead atomics. Snapshot
  the count when the PPU arms its wait, and report the delta while the PPU is
  still blocked. Let the wait-trace property enable only the low-rate PPU
  sampler. In a later independently cool round, use one direct unpaused run and
  the external 72 C guard. Do not enable the SPU PC or draw censuses.
- Windows result: The SPURS event-flag wait, Transformers HLE load-wait,
  Transformers HLE LFQueue route, ANY2ANY LFQueue firmware, and LFQueue log
  budget contracts pass. `git diff --check` passes. The normal Android debug
  build passes. Successor APK SHA-256
  `37F5270E115874155DDE678410D6C3BE34A2687174B1D9E5725D0999BD550005`
  is 116,143,256 bytes.
- Successor: The exact edgeZlib SPU event-send path now keeps a monotonic count,
  the last result, port, queue, and timestamp. The PPU wait snapshots the count
  at arm time. A correlated event row appears when a send occurs after one
  second of active wait. The low-rate PPU census reports the dispatch delta up
  to eight times while the exact wait wrapper is active. The wait-trace property
  enables this PPU census without the full SPU PC and draw censuses.

## 120. Runtime SPU compilation ends the cool window before the EDGE result

- Status: failed, not-comparable
- Scope: config-driver, static-analysis
- Hypothesis: Removing the full SPU PC and draw censuses will keep the device
  cool long enough to correlate the first active EDGE wait with an event send.
- Changed files/settings: The run used exact APK SHA-256
  `37F5270E115874155DDE678410D6C3BE34A2687174B1D9E5725D0999BD550005`,
  size 116,143,256 bytes. The wait trace was on. The full runtime census was
  off, and the guest started unpaused. The power state matched the prior run:
  performance mode two, fan mode four, quick performance/fan on, battery saver
  off, and GPU maximum 680 MHz.
- Rollback: The external device guard stopped RPCSX at its hard limit. The
  failure path force-stopped PID 28833 and pulled the guest log. The final
  fixed-silicon sample after stop was 46.2 C. Do not launch the Thor again in
  this hardware round.
- Thor result: The fresh strict gate passed at 42.1 C and ended at 43.7 C. The
  exact no-launch install left the process absent. The route gate passed again
  at 43.3 C. Runtime fixed-silicon samples were 48.2, 58.2, 53.4, 57.4, 65.4,
  69.1, 70.3, and 72.3 C. The last sample exceeded the 72.0 C hard limit.
- Event-wait evidence: The PoolThread armed exact flag `0x01e54800`, mask one,
  AND mode, slot zero, queue `0x8d005600`, and port 17 at guest time 17.435
  seconds. The pulled log ends at 18.747 seconds. No event, census, wake, or
  return row appears. The active interval was only about 1.31 seconds. This is
  much shorter than the known-good 4.55-second boot wait, so it cannot identify
  a missing notification.
- Compile evidence: Startup loaded only 64 of 879 oldest SPU programs. It left
  815 programs for the ordinary uncached runtime-miss path. At the last complete
  performance sample, RPCSX used 88.5% total CPU and produced five frames in ten
  seconds, or 0.50 FPS. The exact edgeZlib SPU had only reached PC `0x09514`.
  The low-overhead trace therefore did not remove the dominant boot pressure.
- Visual correctness: Not proved. The guard stopped the process before the
  requested screenshot.
- FPS/frame-time: No credit. The 0.50 FPS value is a loading and compile window,
  not moving gameplay.
- Capture paths: `20260829-142433-thor-input-strict-cool-gate`,
  `20260829-142452-transformers-edge-event-correlation-install`, and
  `20260829-142523-thor-input-custom`.
- Decision: Keep the event correlation probe. Do not change event-flag or
  loader semantics. Extend the existing exact final-IR native-object cache to
  Android ARM64 runtime LLVM misses. A cold miss must populate the same
  corruption-checked, target-keyed cache, and a warm miss must load it. Keep
  other runtime targets unchanged.
- Next: Build and verify the runtime-cache successor. A later cool run can
  populate missing runtime objects. A separate warm cool run must show native
  object loads, a longer pre-72 C window, and the event dispatch delta before
  any HLE semantic repair.
- Windows result: The native-object cache, bounded preload, ARM64 interpreter
  skip, SPURS event-flag wait, Transformers HLE load-wait, Transformers HLE
  LFQueue route, and Transformers PPU PC contracts pass. `git diff --check`
  passes. The normal Android debug build passes. Successor APK SHA-256
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`
  is 116,143,682 bytes.
- Successor: Android ARM64 runtime SPU thread compilers, optimization workers,
  dispatch retries, and worker retries now opt in to the same exact native
  object cache as startup compilation. Other runtime targets keep the existing
  uncached compiler construction. The object key and corruption checks are
  unchanged. The next Thor run must prove actual warm object loads and a longer
  useful window before the thermal limit. No performance credit applies yet.

## 121. The first runtime-cache run populates cold Android SPU objects

- Status: failed, not-comparable
- Scope: config-driver, performance
- Hypothesis: Runtime SPU misses will use the exact native-object cache. Existing
  objects will load, and cold objects will persist for a later warm run.
- Changed files/settings: The run used exact APK SHA-256
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  size 116,143,682 bytes. The HLE settings matched experiment 120. The wait
  trace was on, the full runtime census was off, and the guest started
  unpaused. The SPU preload limit was 64, and the native-object cache was on.
- Rollback: The external device guard stopped RPCSX at its hard limit. The
  failure path force-stopped PID 6035. The process was absent after the run.
  No fatal signal, tombstone, access violation, or native crash appears. Do not
  launch the Thor again in this hardware round.
- Thor result: The independent strict gate passed at 43.3 C fixed silicon and
  ended at 43.7 C. The exact no-launch install left the process absent. The
  route pre-run value was 43.7 C. Runtime fixed-silicon samples were 52.2,
  56.6, 57.0, 59.8, 68.7, 70.7, and 72.7 C. The last sample exceeded the
  72.0 C hard limit. The post-stop value was 45.3 C.
- Cache evidence: Startup loaded 64 exact native objects and built the bounded
  64-program set. One more exact object loaded at guest time 12.026 seconds,
  after startup compilation ended at 7.883 seconds. The title PPU cache tree
  increased from 437,554 KiB in experiment 120 to 438,682 KiB, an increase of
  1,128 KiB. The post-startup load proves the runtime compiler received the
  cache. The size increase is consistent with cold runtime objects that were
  persisted for the next run.
- Event-wait evidence: No `Thor EDGE EFWAIT` row appears. The pulled log ends at
  guest time 17.260 seconds. The prior run armed the first wait at 17.435
  seconds. The guard therefore stopped this run before the event-correlation
  boundary. This result does not identify an event-flag fault.
- Visual correctness: Not proved. The guard stopped the process before the
  requested screenshot.
- FPS/frame-time: No credit. At guest time 17.260 seconds, RPCSX used 83.5%
  total CPU and produced 42 frames in ten seconds, or 4.20 FPS. Experiment 120
  produced 0.50 FPS at the same guest-time sample. Both samples are from
  loading and compilation, not moving gameplay, so they are not comparable
  performance proof.
- Capture paths: `20260829-143631-thor-input-strict-cool-gate`,
  `20260829-143647-transformers-runtime-spu-object-cache-install`, and
  `20260829-143705-thor-input-custom`.
- Decision: Keep the runtime native-object cache. It reached a post-startup warm
  hit and populated more title-cache data without a native failure. Do not
  change event-flag or loader semantics from this run.
- Next: In a separate independently cool round, use the exact same APK and HLE
  settings. Require more than 65 total `LLVM: Loaded module` rows and passage
  through the first EDGE wait before the 72 C stop. Correlate the dispatch
  delta if the later PoolThread wait remains active. Do not claim gameplay or
  sustained 30 FPS until moving 3D output is visible and measured.

## 122. The warm runtime cache reaches the EDGE wait sooner

- Status: failed, not-comparable
- Scope: config-driver, performance
- Hypothesis: The populated runtime SPU object cache will load more than 65
  native objects and give the title enough useful time to pass the first EDGE
  wait before the thermal stop.
- Changed files/settings: The run used the same exact APK as experiment 121.
  Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The HLE settings matched experiments 120
  and 121. The wait trace was on, the full runtime census was off, and the
  guest started unpaused. The SPU preload limit was 64, and the native-object
  cache was on.
- Rollback: The external device guard stopped RPCSX at its hard limit. The
  process was absent after the run, and the Android launcher was on top. No
  fatal signal, tombstone, access violation, or native crash appears. Do not
  launch the Thor again in this hardware round.
- Thor result: The independent strict gate passed at 42.9 C fixed silicon. The
  route pre-run value was 44.1 C. Runtime fixed-silicon samples were 48.6,
  59.8, 54.2, 57.0, 64.6, 69.9, and 73.5 C. The last sample exceeded the
  72.0 C hard limit. The CPU junction peaked at 87.9 C, below its separate
  95.0 C limit. The post-stop fixed-silicon value was 45.3 C.
- Cache evidence: The log contains 125 `LLVM: Loaded module` rows. The first
  64 rows are startup loads, and 61 rows are post-startup runtime loads. This
  passes the required total of more than 65. The title PPU cache tree increased
  from 438,682 KiB to 439,766 KiB, an increase of 1,084 KiB. This is consistent
  with more persisted runtime objects.
- Event-wait evidence: The PoolThread armed exact flag `0x01e54800`, mask one,
  AND mode, slot zero, queue `0x8d005600`, and port 17 at guest time 13.686
  seconds. Experiment 120 armed the same wait at 17.435 seconds. The warm-cache
  run reached the boundary about 3.749 guest seconds sooner. A preceding
  `Thor EDGE WAKE #0` row shows task set `0x101b4e80`, task zero, after the LFQ
  notification and gate succeeded.
- Wait result: No `Thor EDGE EFWAIT EVENT`, census, wake, or return row appears
  after the arm row. The pulled log ends at guest time 14.752 seconds, about
  1.065 seconds after the wait armed. The known-good first wait in experiment
  118 took about 4.55 seconds. The missing wake therefore does not identify a
  notification fault.
- Visual correctness: Not proved. The guard stopped the process before the
  requested screenshot.
- FPS/frame-time: No credit. The run did not produce a valid moving-gameplay
  sample. The internal thermal guard reported a junction limit near the end,
  but that loading-window report is not comparable performance evidence.
- Capture paths: `20260829-144210-thor-input-strict-cool-gate` and
  `20260829-144228-thor-input-custom`.
- Decision: Keep the runtime native-object cache and the exact event
  correlation probe. Do not change event-flag or loader semantics. The warm
  cache works, but an unpaused boot still heat-soaks before the known wait
  latency can expire. Another identical unpaused run would repeat the same
  invalid test.
- Next: Use the proved paused-slice controller with one-second active slices.
  Cool the device while RPCSX is paused, keep the full runtime census off, and
  stop on the exact `Thor EDGE EFWAIT EVENT` marker or at 72 C fixed silicon.
  Correlate the PPU wait with the exact SPU event-send delta before a semantic
  repair. Require correct moving 3D output and a comparable sustained 30 FPS
  measurement before a full-HLE or performance claim.
- Online source check: Current upstream RPCS3 arms the SPURS wait state and
  then blocks on the attached event queue. It reads the pending event bits and
  clears `ppuPendingRecv` only after the queue wakes. This matches the local
  control flow and gives no basis for a synthetic wake. See the upstream
  [`cellSpurs.cpp`](https://github.com/RPCS3/rpcs3/blob/master/rpcs3/Emu/Cell/Modules/cellSpurs.cpp).
- Event-send check: Current upstream RPCS3 sends the SPU user event to the
  selected queue. It restores the outbound mailbox and retries only for
  `CELL_EAGAIN`; it reports other failures such as `CELL_ENOTCONN`. The local
  event marker records this exact result before the same retry decision. See
  the upstream
  [`SPUThread.cpp`](https://github.com/RPCS3/rpcs3/blob/master/rpcs3/Emu/Cell/SPUThread.cpp).
- AArch64 comparison: An open upstream AArch64 report correlates
  `CELL_ENOTCONN` with one SPURS deadlock signature on another game and device.
  It does not provide a fix, but it makes the event result a required part of
  this test. See [RPCS3 issue 18828](https://github.com/RPCS3/rpcs3/issues/18828).
- Paper check: The IBM Cell SDK documentation covers SPU events, mailboxes,
  DMA ordering, and runtime management. The arXiv Cell papers found in this
  search discuss task and data scheduling, not SPURS event-flag queue
  semantics. They do not support an emulator change at this boundary. See the
  [IBM Cell SDK index](https://public.dhe.ibm.com/linux/cellsdk/docs/) and the
  [representative arXiv scheduling paper](https://arxiv.org/abs/0910.2324).

## 123. The first warm-cache slice exposes a startup control gap

- Status: route-tooling, failed, not-comparable
- Scope: config-driver
- Hypothesis: One-second paused slices will keep fixed silicon below 72 C long
  enough to observe the exact EDGE event-send result.
- Changed files/settings: The run used the same exact installed APK as
  experiments 121 and 122. Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The HLE settings matched experiment 122.
  The guest started paused, the full runtime census was off, and the controller
  requested one-second slices. The stop marker was
  `Thor EDGE EFWAIT EVENT`.
- Rollback: The slice controller force-stopped RPCSX after it could not restore
  a held emulator state. Its stop result had no PID, zero RPCSX rows in `top`,
  and `quiet=true`. The wrapper stop confirmed the same result. Property
  cleanup cleared 56 values and found zero remaining
  `debug.rpcsx.thor.*` values. The final fixed-silicon value was 47.4 C. Do not
  launch the Thor again in this hardware round.
- Thor result: The one-sample gate passed at 43.7 C fixed silicon. The exact APK
  identity matched. The first slice cooled to 46.2 C before release. Resume
  succeeded, but each normal pause call returned `ok=false,paused=false`.
  The controller stopped after one incomplete slice. Its host duration was
  28.719 seconds, and its maximum fixed-silicon value was 70.7 C. This value is
  below the 72 C hard stop. The emulator junction guard engaged at 86 C; this
  was below its separate 95 C hard limit.
- Control-path evidence: The start-paused gate became ready at guest time 1.025
  seconds and was released at guest time 8.626 seconds. Source inspection shows
  that this first release changes the emulator from `ready` to `starting` and
  already requests pause after startup. A normal `Emulator::Pause()` accepts
  only `running`; it correctly refuses `starting`. The controller treated that
  expected startup transition as an eight-second pause failure. This is a host
  control-path defect, not an HLE event result.
- HLE evidence: No `Thor EDGE EFWAIT EVENT` row appears. The run stopped during
  early PPU and SPU startup work, before the prior event boundary. It provides
  no evidence for an event-flag, notification, or loader change.
- Visual correctness: Not proved. The controller stopped RPCSX before the
  boundary screenshot.
- FPS/frame-time: No credit. No moving gameplay sample exists.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-145616-thor-input-custom`.
- Wrapper defect: The process was already stopped when the route wrapper called
  `Get-ThorEvidenceBody`. That helper is private to `thor_input_macro.ps1`, so
  the wrapper failed during post-processing. The successor reads the recorded
  PID evidence directly and does not call the private helper.
- Decision: Keep the exact APK and HLE semantic stack unchanged. The host
  controller now recognizes the first `ready` to `starting` handoff. It waits
  for the already requested startup pause for at most 120 seconds while it
  continues to poll fixed silicon and force-stops at 72 C. Later slices keep
  the normal eight-second pause timeout. The result now records initial state,
  final state, pause request time, pause settle time, and the startup-handoff
  flag.
- Windows result: The simulated guarded-slice state machine, the fixed-silicon
  contract, the device thermal guard, the Transformers HLE route contract,
  Python compilation, PowerShell parsing, and `git diff --check` pass. This is
  a host-only successor and does not need a new APK.
- Next: In a separate independently cool hardware round, use the same exact APK
  and the repaired host route. Start immediately below 70 C and stop at 72 C.
  Require the first startup handoff to settle into a held state, then continue
  one-second slices to the exact EDGE event marker. Do not change HLE semantics
  until the event result is recorded. Require correct moving 3D output and a
  comparable sustained 30 FPS measurement before a full-HLE or performance
  claim.

## 124. A blocked host sensor read defeats the startup wait guard

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The extended startup-handoff wait will let startup compilation
  finish while the host controller continues to enforce the 72 C fixed-silicon
  hard stop.
- Changed files/settings: The run used the same exact installed APK, HLE stack,
  cache settings, and event marker as experiment 123. Its APK SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`.
  The host included commit `98fe8bed7`.
- Rollback: The controller force-stopped RPCSX when its fixed-silicon read
  returned. Its stop result had no PID, zero RPCSX rows in `top`, and
  `quiet=true`. The wrapper stop confirmed the same result. Property cleanup
  cleared 56 values and found zero remaining `debug.rpcsx.thor.*` values. The
  final fixed-silicon values were 48.2 C after the wrapper stop and 48.6 C after
  property cleanup. Do not launch the Thor again in this hardware round.
- Thor result: The strict gate passed at 42.5 C fixed silicon. The first slice
  cooled to 47.0 C before release. The controller correctly identified initial
  state 6 (`ready`), final state 7 (`starting`), and the startup-handoff flag.
  It did not apply the old eight-second state failure. However, the first host
  fixed-silicon read did not return while the device was saturated. It returned
  after 28.281 seconds with 79.9 C, above both the 72 C repository limit and the
  user's 75 C ceiling. The controller then force-stopped the process. The
  emulator junction guard engaged at 85 C during this interval.
- Guard failure: The input macro ended its own thermal guard before the wrapper
  started `thor_slice_loop`. The slice loop then depended on synchronous host
  ADB temperature reads. This left no independent device-side stop while the
  first read was blocked. Extending the startup wait therefore exposed a second
  harness defect; it did not test the EDGE event path.
- HLE evidence: No `Thor EDGE EFWAIT` or exact event-result row appears. The run
  stopped during startup compilation. It provides no evidence for an HLE
  semantic change.
- Visual correctness: Not proved. No boundary screenshot exists.
- FPS/frame-time: No credit. No moving gameplay sample exists.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-150719-thor-input-custom`.
- Decision: Do not wait for startup compilation with only an emulator pause.
  `Emulator::Pause()` cannot stop `system_state::starting`. The successor sends
  process-level `SIGSTOP` at the one-second deadline and `SIGCONT` for the next
  slice. This stops startup compiler threads as well as guest threads. The
  controller records whether each held state is an emulator pause or a process
  hold. It reads the guest log through `run-as` while the control server is
  stopped.
- Thermal successor: The wrapper now starts the existing guard on the device
  before the slice controller. A ready-file handshake proves that the guard has
  validated all sensors before the first resume. It requests an early stop at
  70 C, keeps 72 C as the hard limit, and keeps the separate 95 C junction
  limit. The guard stays active until the verified package stop. Thus, a blocked
  host ADB read cannot remove the device-side stop again.
- Windows result: The simulated guarded-slice state machine, repeated
  process-held startup slices, fixed-silicon contract, device guard contract,
  Transformers route contract, Python compilation, PowerShell parsing, and
  `git diff --check` pass. This successor is host-only and does not need a new
  APK.
- Android source check: AOSP `run-as` accepts only a debuggable package, changes
  to that application's UID and SELinux context, and then executes the requested
  command. AOSP Toybox `kill` accepts a named signal. These sources support the
  same-UID `kill -STOP` and `kill -CONT` route, but the next Thor round must
  still prove the commands on this exact build. See the AOSP
  [`run-as.cpp`](https://android.googlesource.com/platform/system/core/+/refs/heads/android14-qpr3-s12-release/run-as/run-as.cpp)
  and Toybox
  [`kill` help](https://android.googlesource.com/platform/external/toybox/+/90937f6e7e180bc1c54e6e7e9e287f1fada9c203/android/mac/generated/help.h#663).
- Next: In a later independently cool hardware round, use the same exact APK.
  First prove that `run-as` can stop and continue the app process and that the
  device guard is ready before resume. Require every active startup slice to
  settle near one second and stay below the device-side early stop. Continue to
  the exact EDGE event marker only if those safety gates pass. Do not change HLE
  semantics until the event result is recorded. Require correct moving 3D output
  and a comparable sustained 30 FPS measurement before a full-HLE or
  performance claim.

## 125. Process holds work, but the API-first deadline can still overrun

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: Process-level startup slices and the independent device watchdog
  will keep every active window near one second and below the 72 C fixed-silicon
  hard limit.
- Changed files/settings: The run used the same exact installed APK, HLE stack,
  cache settings, and event marker as experiment 124. Its APK SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`.
  The host included commits `98fe8bed7`, `7c97f921a`, and `2fac446f5`.
- Rollback: The controller force-stopped RPCSX at its thermal observation. Its
  result had no PID, zero RPCSX rows in `top`, and `quiet=true`. The wrapper
  stop confirmed the same result. Property cleanup cleared 56 values and found
  zero remaining `debug.rpcsx.thor.*` values. The final fixed-silicon value was
  49.0 C. Do not launch the Thor again in this hardware round.
- Thor result: The route pre-run value was 44.1 C fixed silicon. The ready-file
  handshake proved that the independent guard validated its sensor set before
  the first resume. Eight process-held slices completed. Their active times
  were 1.094 to 1.235 seconds, and their recorded maxima were 52.6 to 68.7 C.
  This proves that same-UID `SIGSTOP` and `SIGCONT` work on this exact Thor
  build.
- Deadline failure: Slice nine started after a 53.0 C held sample. The host
  thermal read returned after 1.672 seconds at 73.1 C and force-stopped the
  package. This is below the user's 75 C ceiling but above the repository's
  72 C hard limit. The deadline thread still called the in-process pause API
  before `SIGSTOP`. That API blocked during the high-load startup phase, so the
  proved process hold did not run at the one-second deadline.
- Device-guard evidence: The device watchdog's last live sample was 68.2 C
  fixed silicon and 83.9 C CPU junction. Its next row reports that the package
  was already stopped. A two-second watchdog interval cannot cover the observed
  fast fixed-silicon rise. The watchdog did remain alive for the full slice-loop
  lifetime, so its ready and lifetime handshake are proved.
- HLE evidence: No `Thor EDGE EFWAIT EVENT` row appears. The log ends during SPU
  startup compilation and reports zero frames. This run provides no evidence
  for an event-flag, notification, or loader change.
- Visual correctness: Not proved. No boundary screenshot exists.
- FPS/frame-time: No credit. No moving gameplay sample exists.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-151828-thor-input-custom`.
- Decision: Keep process-level startup holds. The successor sends `SIGSTOP`
  before any pause API call at a startup deadline. A continued process-held
  slice also sends a bounded resume request so that a completed startup pause
  can advance into guest execution. The slice watchdog now polls every 0.25
  seconds and stops early at 68 C while it retains the 72 C hard limit. The
  exclusive cold-start gate stays at 70 C.
- Next: In a separate independently cool hardware round, use the same exact
  APK. Require every startup hold to settle at the requested deadline and stay
  below 72 C. Continue only to the exact EDGE event-result marker. Correlate its
  result with the matching SPU dispatch delta before any HLE semantic change.
  Require correct moving 3D output and a comparable sustained 30 FPS
  measurement before a full-HLE or performance claim.

## 126. Half-second process slices stay below 70 C and reach SPU startup

- Status: failed, route-tooling, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: An API-free startup deadline and half-second slices will keep
  fixed silicon below 70 C while the title advances toward the EDGE event
  boundary.
- Changed files/settings: The run used the same exact installed APK and HLE
  stack as experiment 125. Its APK SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`.
  The host included commit `65bde5138`. The slice duration was 0.5 seconds. The
  independent watchdog polled every 0.25 seconds and had a 68 C early-stop
  threshold and a 72 C hard limit.
- Rollback: The device watchdog force-stopped RPCSX at its early threshold. The
  wrapper stop result had no PID, zero RPCSX rows in `top`, and `quiet=true`.
  Property cleanup cleared 56 values and found zero remaining
  `debug.rpcsx.thor.*` values. The final fixed-silicon value was 50.6 C. Do not
  launch the Thor again in this hardware round.
- Thor result: The cold-start gate passed at 44.1 C fixed silicon. Twenty
  process-held slices completed. Their total active time was 11.816 seconds.
  Every deadline settled in 0.563 to 0.640 seconds. The controller maximum was
  61.8 C. The independent device watchdog sampled 141 times and stopped at
  69.9 C, below both 70 C and the 72 C hard limit. Its CPU-junction maximum was
  below the separate 95 C limit.
- Startup evidence: The title completed PPU function and block analysis, reused
  225 warm-cache PPU objects, reused one later PPU object, and entered the ARM64
  SPU runtime. The last row records the first SPU GETLLAR pattern at local-store
  address `0x00d18`. This is useful forward progress and is not a repeated
  controller state.
- HLE evidence: No `Thor EDGE EFWAIT EVENT` row appears. The process stopped at
  the start of SPU compilation, before the event-correlation boundary. This run
  provides no evidence for an event-flag, notification, or loader change.
- Visual correctness: Not proved. No boundary screenshot exists.
- FPS/frame-time: No credit. The log reports zero frames during startup.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-152544-thor-input-custom`.
- Decision: Keep the API-free process deadline and half-second or smaller
  slices. Do not discard accumulated startup work at the early thermal margin.
  The successor gives the slice route a hold action: the device watchdog sends
  `SIGSTOP` at 68 C, the controller adopts the stopped process, and later slices
  resume only below 60 C. A 72 C sample still force-stops the package. General
  non-slice routes keep their existing early force-stop behavior.
- Next: In a separate independently cool hardware round, use 0.25-second active
  slices with the same exact APK. Preserve the process through early thermal
  holds and continue to `Thor EDGE EFWAIT EVENT`. Correlate the exact result and
  SPU dispatch delta before an HLE semantic repair. Do not claim gameplay or
  sustained 30 FPS until correct moving 3D output is visible and measured.

## 127. Thermal holds preserve startup until a resume-status race

- Status: route-tooling, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The independent watchdog can hold RPCSX at its early thermal
  margin, let the controller cool the same process, and continue startup without
  repeating PPU analysis.
- Changed files/settings: The run used the same exact installed APK and HLE
  stack as experiment 126. Its APK SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`.
  The host included commits `b92efa7a3` and `53a505073`. The slice duration was
  0.25 seconds. The first-start ceiling was 70 C, the later resume target was
  60 C, the device early-hold threshold was 68 C, and the hard limit was 72 C.
- Rollback: The controller force-stopped RPCSX after it misclassified the final
  continue attempt. The wrapper stop result had no PID, zero RPCSX rows in
  `top`, and `quiet=true`. Property cleanup cleared 56 values and found zero
  remaining `debug.rpcsx.thor.*` values. Final fixed-silicon values were 50.6 C
  after stop and 52.2 C after cleanup. Do not launch the Thor again in this
  hardware round.
- Thor result: The cold-start gate passed at 43.7 C fixed silicon. Seventy-three
  complete process-held slices accumulated 25.778 active seconds. Their active
  windows were 0.312 to 0.422 seconds. The controller maximum was 65.0 C. The
  device watchdog took 534 samples and reached 69.5 C. It never reached 70 C or
  the 72 C hard limit.
- Preserve-progress evidence: The watchdog held the same PID at 69.1, 69.5, and
  68.2 C. The controller later continued that PID after each cooldown. The log
  continued from PPU warm-cache reuse into many SPU worker modules and GETLLAR
  pattern entries. This proves that the early thermal hold preserves startup
  work instead of forcing a new boot.
- Cache evidence: The `BLUS30357` title cache stayed at 439,777 KiB, and its
  `spu_progs` directory stayed at 24 KiB. The full cache increased by only
  12 KiB. Do not expect a measurably warmer next boot from this run.
- Controller failure: On slice 74, `kill -CONT` returned, but the following
  process-status read did not finish before the 0.25-second deadline stopped the
  process again. The read therefore reported state `T`. The controller treated
  that correct deadline race as a failed continue and stopped the package. This
  is a host control defect, not an HLE failure.
- HLE evidence: No `Thor EDGE EFWAIT EVENT` row appears. The run remained in SPU
  startup compilation and produced zero frames. It provides no evidence for an
  event-flag, notification, or loader change.
- Visual correctness: Not proved. No boundary screenshot exists.
- FPS/frame-time: No credit. No moving gameplay sample exists.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-153619-thor-input-custom`.
- Decision: Keep the thermal hold, 60 C later-resume target, and 0.25-second
  slices. The successor requires an explicit remote-shell acknowledgment from
  `kill -CONT`. A stopped state from the later status read is recorded as a
  deadline race, not a signal failure, because the independent deadline can
  correctly reapply `SIGSTOP` while that read is in flight.
- Next: In a separate independently cool hardware round, use the same exact APK
  and route. Continue the preserved process to `Thor EDGE EFWAIT EVENT` or the
  bounded host deadline. Correlate the exact event result and dispatch delta
  before an HLE semantic repair. Do not claim gameplay or sustained 30 FPS until
  correct moving 3D output is visible and measured.

## 128. One cool sample permits a later hard-limit spike

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The acknowledged-continue repair can keep the startup-slice loop
  active until the exact EDGE event marker.
- Changed files/settings: The run used exact installed APK
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`
  and host commits through `ed76e2ef1`. It used the experiment 127 HLE stack,
  0.25-second slices, a 60 C later-resume target, a 68 C device hold, and a
  72 C hard stop.
- Thor result: The cold-start gate passed at 45.3 C fixed silicon. Sixty-three
  complete slices accumulated 22.141 active seconds in 262.672 host seconds.
  Active windows were 0.328 to 0.422 seconds. The controller maximum was
  65.0 C. The controller did not repeat the experiment 127 continue-status
  failure.
- Independent guard: The device guard recorded 438 temperature samples. It
  first held PID 2038 at 70.3 C and preserved it during cooldown. It later
  detected the controller release. The final fixed-silicon sample jumped from
  59.8 to 72.3 C, so the guard applied the required hard stop. Its maximum CPU
  junction value was 87.9 C, below the separate 95 C limit.
- Route failure: Later cooldowns accepted one sample below 60 C. Most records
  have `waitedS=0`. This allowed repeated resumes while subsystem heat remained
  unstable. The independent guard then removed the process at the hard limit,
  and the controller correctly reported `emulator is not running`.
- HLE evidence: No `Thor EDGE EFWAIT EVENT`, fatal error, access violation, or
  out-of-memory row appears. The log reached SPU runtime compilation, GETLLAR
  patterns, and unmatched `spu_fi` reports, but produced zero frames. The
  `BLUS30357` cache stayed at 439,777 KiB, and `spu_progs` stayed at 24 KiB.
- Visual correctness: Not proved. The route did not reach the marker and did
  not capture a boundary image.
- FPS/frame-time: No credit. No moving gameplay sample exists.
- Cleanup: The verified stop found no PID and zero RPCSX `top` rows. Property
  cleanup cleared 56 values and found zero remaining `debug.rpcsx.thor.*`
  values. Its final fixed-silicon sample was 54.2 C.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-154830-thor-input-custom`.
- Decision: Do not change HLE semantics. Keep the cold-start rule unchanged:
  start immediately below 70 C. The host successor requires three consecutive
  later-resume samples below 60 C at one-second intervals, lowers the device
  early hold to 66 C, raises the bounded slice count to 256, and raises the
  bounded host ceiling to 600 seconds. The 72 C hard stop remains unchanged.
- Verification: Python compilation, the guarded slice state-machine test, the
  fixed-silicon contract, the device thermal contract, the Transformers HLE
  route contract, and `git diff --check` pass. A separate shell syntax rerun
  could not start because the Windows Bash service returned access denied; the
  device shell guard file was not changed.
- Next: In a separate independently cool hardware round, use the same exact APK
  and HLE settings with 0.25-second slices, at most 192 slices, a 600-second
  host limit, and the three-sample resume gate. Continue to
  `Thor EDGE EFWAIT EVENT` or the bounded host deadline. Do not make an HLE
  semantic repair until the exact event result and SPU dispatch delta exist.

## 129. Current upstream and arXiv do not replace the runtime gate

- Status: research, not-comparable
- Scope: upstream-audit, event-delivery
- Upstream refresh: A read-only fetch moved RPCS3 `origin/master` to
  `010bf1753ea1cd0f35fc0d30fd63cb58c05a199c`. ARMSX3 `master` stayed at
  `a74a0f3e045f064515a5fa48643e66ab386577d3`.
- Relevant history: RPCS3 has no later change to `cellSpurs.cpp` or
  `SPUThread.cpp` after `d7ed328f4` on 2026-08-02. That writer-lock repair is
  already present in this branch. The upstream and ARMSX3
  `sys_spu_thread_throw_event` paths still send to the connected LV2 queue and
  retry only `CELL_EAGAIN`; they provide no new event result or loader repair.
- ARMSX3 result: Its related `a7ec28f7a` change always notifies reservation
  waiters after a successful store. This tree already carries that behavior
  behind `debug.rpcsx.thor.spurs_always_notify`. Earlier Transformers HLE
  evidence showed no geometry effect, so do not retest it as an EDGE event fix.
- Literature result: Targeted arXiv searches found Cell workload and performance
  papers, but no SPURS event-flag ABI, LV2 user-event protocol, or compatible HLE
  implementation. IBM Cell SDK documentation and the Cell Broadband Engine
  Programming Handbook define hardware SPE event channels. They do not define
  Sony's SPURS event-flag queue attachment and wake contract used here.
- Decision: No import or semantic edit is justified. Keep the exact runtime
  correlation gate. The first useful new fact remains the result, queue, port,
  and dispatch delta in `Thor EDGE EFWAIT EVENT`.
- Primary sources:
  `https://github.com/RPCS3/rpcs3`, `https://github.com/ARMSX2/ARMSX3`, and
  `https://public.dhe.ibm.com/linux/cellsdk/docs/`.

## 130. Stable resumes expose an expired SPU cache profile

- Status: route-tooling, not-comparable
- Scope: config-driver, thermal-safety, performance
- Hypothesis: Three stable cooldown samples and a 66 C device hold will keep
  one preserved startup process below the 72 C hard limit until it reaches the
  exact EDGE event marker.
- Changed files/settings: The run used exact installed APK
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  size 116,143,682 bytes, and host commits through `7c2f04166`. It used the
  experiment 129 HLE stack, 0.25-second slices, a 70 C cold-start ceiling, a
  three-sample later-resume gate below 60 C, a 66 C device hold, and a 72 C
  hard stop. The maximum host time was 600 seconds. The EDGE event-wait trace
  was on, and the full runtime census was off.
- Thor result: The route completed its bounded controller path. It completed
  75 slices and accumulated 26.879 active seconds in 603.266 host seconds.
  Active windows were 0.313 to 0.422 seconds. Cooldown waits totaled 159
  seconds. The controller maximum was 64.2 C. It ended at the host deadline
  with the same PID held and paused.
- Independent guard: The guard recorded 1,049 temperature samples for PID
  17540. It held and released the same process four times. Fixed silicon
  peaked at 71.1 C, below the 72 C hard limit, and CPU junction peaked at
  85.1 C, below its separate 95 C limit. No hard stop occurred. This proves
  the stable-resume repair and the preserved-process thermal route.
- Startup evidence: PPU function analysis ended after about 2 minutes 6
  seconds. Block analysis ended after about 2 minutes 30 seconds. The title
  reused 225 PPU objects and later reused one more object. It entered the SPU
  runtime after about 5 minutes 15 seconds, recorded 17 GETLLAR pattern rows,
  and continued compiling SPU blocks until the host deadline.
- HLE evidence: No `Thor EDGE EFWAIT ARM` or `Thor EDGE EFWAIT EVENT` row
  appears. No fatal error, access violation, out-of-memory report, or
  verification failure appears. The title produced zero frames. The result
  provides no event-delivery or HLE semantic evidence.
- Visual correctness: Not proved. The marker did not appear, so the route did
  not capture a boundary image or reach moving 3D output.
- FPS/frame-time: No credit. The title produced zero frames during startup.
- Cache diagnosis: The requested property readback recorded
  `debug.rpcsx.thor.spu_native_object_cache=on` before launch. The inner input
  macro then set that property to `off` at 16:03:23, when its empty macro
  returned. Slow paused startup did not call `spu_cache::initialize` until
  about five minutes later. The log therefore has no native-object activation
  row, no bounded preload row, and no native SPU object-load row. The
  `BLUS30357` cache stayed at 439,777 KiB. Earlier runs with the same exact APK
  prove that the core contains this cache and can load it. This is a property
  lifetime defect in the slice route, not a missing APK feature.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 56 values and found zero remaining
  `debug.rpcsx.thor.*` values. Its final fixed-silicon value was 53.0 C. Do not
  launch the Thor again in this hardware round.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-160316-thor-input-custom`.
- Decision: Keep the 70 C one-sample cold-start gate, the stable later-resume
  gate, and the independent device guard. Do not change HLE semantics. The
  host successor reapplies the complete slice-loop profile after the inner
  launcher clears its properties. It reads back every value into
  `slice-loop-profile-effective.txt` and force-stops the app on any mismatch.
  The outer cleanup path still clears all properties after the controller.
- Windows result: Both changed PowerShell files parse. The Transformers HLE
  route, native SPU object-cache, guarded slice state machine, and strict
  70 C cold-start contracts pass. `git diff --check` passes. This is a host
  route change and does not need a new APK.
- Next: In a separate independently cool hardware round, use the same exact
  APK and route. Require exact slice-loop property readback, the native-object
  activation row, bounded preload, and native SPU object loads before the
  first runtime compile. Continue to `Thor EDGE EFWAIT EVENT` or the bounded
  host deadline. Correlate the event result and SPU dispatch delta before an
  HLE semantic change. Require correct moving 3D output and a comparable
  sustained 30 FPS measurement before a full-HLE or performance claim.

## 131. The first delayed EDGE event dispatch is correct

- Status: android-pass, route-tooling, not-comparable
- Scope: config-driver, event-delivery, thermal-safety
- Hypothesis: The preserved slice-loop profile will restore native SPU object
  loads and let one thermally held process reach the exact correlated EDGE
  event result.
- Changed files/settings: The run used the same exact installed APK as
  experiment 130. Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The host included commit `08054ee91`.
  The route used the experiment 130 HLE stack, 0.25-second slices, one cold
  sample below 70 C, three later-resume samples below 60 C, a 66 C device
  hold, and a 72 C hard stop. The EDGE wait trace was on, and the full runtime
  census was off.
- Route readback: `slice-loop-profile-effective.txt` proves that the delayed
  profile was active after launcher cleanup. It includes HLE `libsre.sprx`,
  the HLE SPURS kernel, the EDGE trace and interpreter, atomic task selection,
  the task attribute repair, the Transformers SPU reserve, native SPU object
  cache `on`, preload limit 64, compile budget 50 ms, and cache affinity 7.
- Thor result: The one-sample cold-start gate passed at 44.9 C fixed silicon.
  The controller completed 69 slices and accumulated 24.543 active seconds in
  557.313 host seconds. Active windows were 0.328 to 0.453 seconds. Cooldown
  waits totaled 145 seconds. The controller maximum was 64.2 C. It stopped on
  the exact event marker with the same PID held and paused.
- Cache evidence: Startup logged the native-object activation and the bounded
  64-of-879 preload. The log contains 205 native SPU object loads. The title
  cache increased from 439,777 to 440,341 KiB. This proves that the route
  property-lifetime repair works on the device.
- Event evidence: The PoolThread armed flag `0x01e54800`, request bit one, AND
  mode, slot zero, queue `0x8d005600`, and port 17. The exact edgeZlib helper
  entered at PC `0x0a4d8`, wrote interrupt mailbox value `0x51000000` at PC
  `0x0a514`, and dispatched one event after the arm. The event returned
  `0x00000000` on port 17 and queue `0x8d005600`. The PPU received bit
  `0x0001`, returned success, cleared its pending receive state, and armed the
  next wait. Dispatch delta was exactly one. This rules out a missing event,
  wrong queue connection, or failed first wait at this boundary.
- Loader evidence: Before the event, the main thread was in the staged loader
  wait with an active IO entry and one pending cache range. The first
  completion value was one. The successful event is necessary for this
  request, but the route stopped before loader finalization. It does not yet
  prove that the later completion state clears.
- Visual correctness: Not proved. The boundary image is black except for the
  performance overlay. It reports 0.06 FPS and has no visible 3D output.
- FPS/frame-time: No credit. A prior sensor interval contained only four
  frames in 112 seconds. This is a paused startup and loading route, not a
  moving gameplay measurement.
- Thermal result: The independent guard recorded 970 temperature samples. It
  held the same PID three times. Fixed silicon peaked at 66.6 C, and CPU
  junction peaked at 85.9 C. Neither hard limit fired. The boundary screenshot
  was taken at 61.4 C fixed silicon.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed-silicon values were 52.2 C after
  stop and 53.8 C after cleanup. Do not launch the Thor again in this hardware
  round.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-162309-thor-input-custom`.
- Decision: Keep the event path and the current HLE repair stack. Do not add a
  notification, queue, event-result, or first-wait repair. Keep the
  property-lifetime and thermal-controller repairs. The next proof boundary is
  the second late-loader completion sample, not the first EDGE event.
- Next: In a later independently cool hardware round, use the same exact APK.
  Use 0.5-second preserved slices and stop on
  `Thor LATE LOAD IO COMPLETION: sample=2`. Require two stable late-loader
  samples and correlate their completion value with the live EDGE wait state.
  Do not force a completion value. Require correct moving 3D output and a
  comparable sustained 30 FPS measurement before a full-HLE or performance
  claim.

## 132. The later loader wait misses EDGE sequence 318

- Status: android-pass, diagnostic, not-comparable
- Scope: event-delivery, asynchronous-loader, thermal-safety, visual-output
- Hypothesis: Two late-loader samples will show whether the active completion
  state retires after the first proved EDGE event.
- Changed files/settings: The run used the same exact installed APK as
  experiment 131. Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The host included commit `fd0920eca`.
  The route used the experiment 131 HLE stack, 0.5-second slices, one cold
  sample below 70 C, three later-resume samples below 60 C, a 66 C device
  hold, and a 72 C hard stop. It stopped on the second late-loader completion
  sample.
- Thor result: The cold-start gate passed immediately at 45.8 C fixed silicon.
  The controller completed 47 slices and accumulated 29.629 active seconds in
  411.609 host seconds. Active windows were 0.578 to 0.813 seconds. Cooldown
  waits totaled 103 seconds. The controller maximum was 65.4 C. It reached the
  exact requested marker with the same process paused and held.
- Loader evidence: Both samples identify the same active entry, item, mapped
  completion address, storage address, request range, and pending cache range.
  The mapped completion value stayed `0x00000001`. Sample 1 occurred at
  emulated time 5:05.248, and sample 2 occurred at 6:59.248. The main thread
  stayed in the staged loader wait at LR `0x00523690`, and the AsyncIOSystem
  thread stayed in its active-list poll at LR `0x0051aea4`. The active item did
  not retire.
- Event evidence: The earlier path completed requests 1 through 317. For the
  later request, both samples report total and sequence 318, request bit one,
  phase one, received value zero, and one active wait. Dispatch stayed at
  317-at-arm and 317-current, with delta zero. The active wait age increased
  from 17.829523 to 131.829592 seconds. This proves that the later loader wait
  lacks a new SPU event dispatch. It does not show a failed PPU wake or a
  completion-word visibility fault.
- Cache evidence: The delayed profile stayed active. Startup logged native SPU
  cache activation, the bounded 64-of-879 preload, and 266 native SPU object
  loads. The `BLUS30357` title cache increased from 440,341 to 440,509 KiB.
- Visual correctness: Partial boot output is proved. The boundary image shows
  the Unreal Technology and PhysX legal splash with a correctly visible
  performance overlay. It reports 28.80 FPS at that paused boundary. This is
  not moving 3D gameplay and does not prove full visual correctness.
- FPS/frame-time: No sustained-performance credit. The paused sensor intervals
  include 90 frames in 88.97 seconds and 14 frames in 114.00 seconds. The
  overlay value is one boundary observation, not a comparable moving-gameplay
  measurement.
- Thermal result: The independent guard recorded 682 samples and 11 early-hold
  samples. Fixed silicon peaked at 69.1 C, below the 72 C hard limit. CPU
  junction peaked at 82.3 C, below its separate 95 C limit. The boundary image
  was captured at 55.0 C fixed silicon. No hard stop occurred.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed-silicon values were 52.6 C after
  stop and 52.2 C after cleanup. Do not launch the Thor again in this hardware
  round.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-163924-thor-input-custom`.
- Decision: Keep the existing PPU event-flag wait, queue connection, port, and
  completion-state semantics. Do not force the completion word to zero. The
  next proof boundary is the SPU task state that should produce event sequence
  318. Add a bounded task or SPU PC census before another device run.
- Next: Correlate the live taskset, task ID, SPU PC, and event-output mailbox
  state for sequence 318. Use Ghidra to map that PC to the EDGE helper or task
  control path. Make a semantic repair only after this producer-side state is
  proved. Require correct moving 3D output and a comparable sustained 30 FPS
  measurement before a full-HLE or performance claim.

## 133. A pre-paused-state race refuses the producer census

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The existing start-paused gate will place the new process in a
  state that the slice-loop controller can own before the first slice.
- Changed files/settings: The run used the experiment 132 APK and HLE stack.
  It requested the bounded edgeZlib SPU PC census and SPURS atomic census. The
  slice-loop property readback proves that both values were one. It used the
  0.5-second route and the second late-loader completion marker.
- Thor result: The one-sample cold-start gate passed at 46.6 C fixed silicon.
  RPCSX logged that the Thor start-paused gate was ready. The outer controller
  then observed a state before `Ready` or `Paused` and refused with
  `the emulator must be paused before a slice loop`. The old refusal did not
  retain the numeric state. RPCSX can be `Loading` or `Starting` at this
  boundary. The route completed zero slices and produced no SPU PC or atomic
  samples.
- HLE and visual evidence: None. The route stopped during startup and did not
  reach the HLE diagnostic boundary. No boundary image exists. Give no FPS or
  visual-correctness credit.
- Thermal result: The independent guard recorded 15 samples. Fixed silicon
  peaked at 53.4 C, and CPU junction peaked at 69.1 C. No hold or hard stop
  occurred.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed-silicon values were 47.8 C after
  stop and 49.4 C after cleanup.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-165241-thor-input-custom`.
- Decision: This is a host startup-handoff race, not an HLE result. Keep the
  cold-start rule and HLE stack. The slice controller now accepts `Loading` or
  `Starting` only when the caller explicitly sets `allowStarting`. It
  immediately process-holds that PID before cooldown and keeps the default
  path fail-closed. Future refusals record the exact state. The guarded
  controller test covers the loading case and the default refusal.
- Next: In a separate independently cool hardware round, repeat the producer
  census with the repaired startup handoff. Stop at the second late-loader
  completion sample and map the live edgeZlib PC with Ghidra.

## 134. The startup permission omitted the loading state

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: Allowing the `Starting` emulator state will remove the
  experiment 133 slice-loop refusal.
- Changed files/settings: The run used the same APK, HLE stack, PC census,
  atomic census, and loader marker as experiment 133. The host included commit
  `6f50b389e`, which allowed only state `Starting` in the explicit startup
  handoff.
- Thor result: The one-sample cold-start gate passed at 44.9 C fixed silicon.
  The controller again refused before a slice because the earlier boot state
  was not observed as `Paused`, `Ready`, or `Starting`. The native log proves
  that RPCSX reached its start-paused `Ready` gate, so a transient control API
  status failure is also possible. The route completed zero slices and
  produced no HLE, PC, visual, or performance evidence.
- Thermal result: The independent guard recorded 16 samples. Fixed silicon
  peaked at 52.6 C, and CPU junction peaked at 68.2 C. No hold or hard stop
  occurred.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed silicon was 47.4 C after both stop
  and cleanup.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-165711-thor-input-custom`.
- Decision: Keep the HLE stack unchanged. When the caller explicitly permits a
  startup handoff and the PID is live, the slice controller now process-holds
  `Loading`, `Running`, `Starting`, or a transient unavailable status before
  the first cooldown. It still refuses `Stopped`, `Stopping`, and `Frozen`,
  and the default call still requires `Paused` or `Ready`. A future refusal
  records its numeric initial state, process-hold state, and permission value.
- Next: Repeat the producer census in a separate cool round. Do not give this
  zero-slice route any HLE or FPS credit.

## 135. An early process hold traps the native ready gate

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The explicit startup handoff will let the SPU PC and atomic
  censuses reach the second late-loader completion sample.
- Changed files/settings: The run used the same exact experiment 134 APK and
  HLE stack. Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The host included commit `1b5691d89`.
  The route enabled the bounded SPU PC census, SPURS atomic census, and EDGE
  event-wait trace. It requested 0.5-second slices and the second late-loader
  completion marker.
- Thor result: The one-sample cold-start gate passed immediately at 45.3 C
  fixed silicon. The slice loop took an initial process hold in state `T`.
  It completed 80 process windows in 602.422 host seconds and reached the host
  deadline without the marker. The windows reported 48.071 active seconds,
  from 0.578 to 0.703 seconds each. Cooldown waits totaled 158 seconds. These
  windows do not show guest work.
- Startup evidence: The native log reached
  `Thor start-paused gate is ready` at 1.030 seconds. It never logged that the
  gate was released. Every performance interval reported zero frames and zero
  busy cores. The run produced no native SPU object load, SPU PC census,
  atomic census, EDGE wait, or late-loader line. The initial `SIGSTOP` held a
  process that was already at the native Ready gate. The 0.5-second deadline
  then stopped each continued process before its in-process resume request
  could release that gate.
- Visual correctness: None. The route did not reach a game frame or save a
  boundary image.
- FPS/frame-time: No FPS credit. The log reported zero frames throughout, and
  the paused process windows are not a performance workload.
- Thermal result: The controller maximum was 59.8 C fixed silicon, and its
  final live read was 60.2 C fixed silicon and 73.0 C junction. The independent
  device guard recorded 1,071 samples, with a 59.0 C fixed-silicon maximum and
  a 76.3 C junction maximum. It recorded no 66 C hold and no hard stop.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed-silicon values were 52.2 C after
  stop and 53.0 C after cleanup.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-170209-thor-input-custom`.
- Decision: This is a controller failure, not an HLE result. Keep the HLE
  stack unchanged. An explicitly allowed startup handoff now sends a bounded
  `/pause` request while the process is live. A confirmed `Ready` or `Paused`
  state enters the slice loop without an initial process hold. An unconfirmed
  state still uses the existing process-hold fallback. The default route stays
  fail-closed.
- Next: In a separate independently cool round, repeat the producer census.
  Require a confirmed initial pause, the native gate-release line, and active
  guest work before the result can describe HLE. Stop at the second late-loader
  completion sample, then map the live edgeZlib PC with Ghidra.

## 136. The slice controller lacks its own port forward

- Status: route-tooling, failed, not-comparable
- Scope: config-driver, thermal-safety
- Hypothesis: The bounded live `/pause` handshake will confirm the native Ready
  gate and avoid the experiment 135 process hold.
- Changed files/settings: The run used the same exact installed APK and HLE
  stack as experiment 135. Its SHA-256 was
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  and its size was 116,143,682 bytes. The host included commit `1e4cfad17`.
  The route enabled the bounded SPU PC census, SPURS atomic census, and EDGE
  event-wait trace. It requested 0.5-second slices and the second late-loader
  completion marker.
- Thor result: The one-sample cold-start gate passed immediately at 44.5 C
  fixed silicon. All eight live `/pause` probes timed out, and the paired status
  remained unavailable. The controller then took an initial process hold in
  state `T`. It completed 80 process windows in 600.266 host seconds and reached
  the host deadline without the marker. The windows reported 48.072 active
  seconds, from 0.578 to 0.688 seconds each. Cooldown waits totaled 158 seconds.
  These windows do not show guest work.
- Startup evidence: The native log reached
  `Thor start-paused gate is ready` once and never logged that the gate was
  released. Every performance interval reported zero frames and zero busy
  cores. The enabled properties were read back as one, but the run produced no
  native SPU object load, SPU PC census, atomic census, EDGE wait, or late-loader
  line. The slice-loop controller runs in a new process and did not establish
  `adb forward tcp:8099 tcp:8099` before its first control request. It depended
  on a forward that an earlier tool might leave behind. Experiment 132 had that
  accidental state; experiments 135 and 136 did not.
- Visual correctness: None. The route did not reach a game frame or save a
  boundary image.
- FPS/frame-time: No FPS credit. The log reported zero frames throughout, and
  the process windows are not a performance workload.
- Thermal result: The controller maximum was 59.4 C fixed silicon, and its
  final live read was 58.2 C fixed silicon and 64.0 C junction. The independent
  device guard recorded 1,102 samples, with a 58.6 C fixed-silicon maximum and
  a 76.7 C junction maximum. It recorded no 66 C hold and no hard stop.
- Rollback: The wrapper stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Fixed silicon was 52.6 C after both stop and
  cleanup.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-172214-thor-input-custom`.
- Decision: This is a second controller failure, not an HLE result. Keep the
  HLE stack unchanged. The slice loop now establishes its own control-port
  forward before it reads status. Each startup `/pause` and `/status` request
  has a 0.5-second timeout. If all eight pairs are unreachable, the route uses
  the verified stop path instead of entering a process hold. A reachable but
  transient startup state still keeps the process-hold fallback.
- Next: After a separate independently cool interval, repeat the producer
  census once. Require a confirmed control handshake, the native gate-release
  line, and active guest work. Stop at the second late-loader completion sample,
  then map the live edgeZlib PC with Ghidra.

## 137. A running bit strands the later EDGE task

- Status: android-pass, diagnostic, not-comparable
- Scope: HLE-SPURS, event-delivery, asynchronous-loader, thermal-safety
- Hypothesis: The repaired slice control will reach the later loader marker and
  place the missing EDGE producer at a live SPU PC or a taskset state.
- Changed files/settings: The run used exact installed APK
  `C1A97D78A44035190004056639A066BD0F45F28BCC4515EC57FE6F3D4A190EFE`,
  size 116,143,682 bytes, and host commit `8918c4ead`. It used the experiment
  136 HLE stack, the bounded SPU PC and atomic censuses, the EDGE event-wait
  trace, 0.5-second slices, one cold sample below 70 C, three later-resume
  samples below 60 C, a 66 C device hold, and 72 C and 95 C hard limits.
- Thor result: The cold-start gate passed at 44.5 C fixed silicon. The native
  Ready gate was confirmed through the repaired control forward and released
  once. The controller completed 70 slices and reached its 600-second host
  limit without the requested second late-loader marker. It accumulated
  44.279 active seconds. Active windows were 0.578 to 0.750 seconds. Cooldown
  waits totaled 146 seconds. This proves active HLE execution and correct
  startup control, but it does not prove loader completion.
- Event evidence: The task dispatched correct events through sequence 281.
  The PoolThread then armed request sequence 283, but the event-dispatch count
  stayed at 281. Three samples aged the same active wait from 44.096100 to
  241.450353 seconds with a zero dispatch delta. This is the same missing-
  producer class as experiment 132, with a different sequence because boot
  timing changed.
- Taskset evidence: Workload 0 owns edgeZlib taskset `0x101b4e80`, task 0,
  queue `0x101b1f80`, and event flag `0x01e54800`. Its last logged workload
  dispatch was on SPU 1 at 4:14.181. At 4:50.299, SPU 5 entered the taskset but
  selected no task. The state was `running=80000000`, `ready=80000000`,
  `signalled=80000000`, `waiting=00000000`, and ready count one. Shared and
  local contention were both one. The new task signal was present, but the
  running bit excluded task 0 from `readyButNotRunning`, so the dispatcher
  exited without running the producer.
- SPU PC evidence: Six bounded edgeZlib samples landed at PCs `0x05c3c`,
  `0x07168`, `0x044f0`, `0x06a88`, `0x08be8`, and `0x07c00` before the stall.
  No edgeZlib PC was resident at any later performance sample while sequence
  283 waited. This is evidence that the task was absent at those sample times,
  not that it spun at one guest PC.
- Static evidence: A read-only Ghidra pass over the exact captured edgeZlib
  local store mapped the six live PCs. Five are normal task or decompression
  control paths. PC `0x08be8` writes MFC channel 21 and then reads channel 27
  in the proved event-flag reservation path. It continues to the event helper
  at `0x0a4d8`. None of the six anchors is a persistent wait loop. Do not patch
  the guest task body from these samples.
- Visual correctness: Not proved. The route did not reach the screenshot
  marker. No moving gameplay output exists.
- FPS/frame-time: No sustained-performance credit. Paused-slice intervals
  reported 0.70, 1.05, 0.00, and 0.14 FPS. They are not a comparable moving-
  gameplay measurement.
- Thermal result: The controller maximum was 64.6 C fixed silicon. The
  independent device guard recorded 1,036 temperature rows, with a 69.9 C
  fixed-silicon maximum and an 85.1 C junction maximum. It recorded no hold
  state and no hard stop. The final live values were 60.2 C fixed silicon and
  77.0 C junction.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed-silicon values were 52.2 C after
  stop and 53.0 C after cleanup.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-173756-thor-input-custom` and
  `debug-captures/ghidra-edge-zlib-pc-census-20260829/live-pcs-173756-ghidra.txt`.
- Decision: Keep the event flag, completion word, and guest task code
  unchanged. The next repair boundary is the HLE taskset running-owner
  invariant. Add a bounded owner census before any recovery. Do not clear a
  running bit until the HLE path proves that no SPU owns that task.
- Next: Record the taskset address, task ID, SPU, HLE task state, and running
  bitmap at task start, task syscall, taskset exit, and idle-ready selection.
  Use that evidence to repair the exact lost-owner transition. Require moving
  3D output and a comparable sustained 30 FPS measurement before a full-HLE
  or performance claim.

## 138. The WAIT_SIGNAL race repair passes the old EDGE stall

- Status: android-pass, HLE-progress, not-comparable
- Scope: HLE-SPURS, task-syscall, event-delivery, asynchronous-loader,
  thermal-safety
- Hypothesis: A signal can arrive after the task polls its signal bit and
  before it submits the atomic `WAIT_SIGNAL` request. The firmware returns one
  in this case. The HLE path returned zero, so the caller dispatched again and
  stranded the task with its running bit set.
- Ownership evidence: Capture
  `debug-captures/android-speed-sprint/20260829-180945-thor-input-custom`
  recorded the failure on SPU 3. Task selection 23 resumed edgeZlib task 0
  from `waiting=80000000` and consumed its signal. A new signal arrived before
  the next selection. Selection 24 then saw the same task as both running and
  ready. The taskset recorded `running=80000000`, `ready=80000000`, and
  `signalled=80000000`. The same SPU had returned to taskset dispatch. No
  different live SPU owned the task.
- Static evidence: The real taskset program first calls `POLL_SIGNAL` at
  runtime address `0x1d80`. It saves the task context, calls `WAIT_SIGNAL` at
  `0x1dac`, and uses a zero result for the dispatch path. The Ghidra raw-image
  base correction maps runtime address `0x0fd8` to file offset `0x05d8`. The
  firmware request-2 handler tests the current signal bit, returns one when
  the bit is set, and does not park the task. This proves that the HLE zero
  result was wrong. The read-only output is in
  `debug-captures/ghidra-taskset-wait-race-20260829/`.
- Changed files/settings: Commit `c9c0f9495` sets the `WAIT_SIGNAL` return
  code from the current signal bit in both the atomic and legacy request
  paths. It parks the task only when that result is zero. The guarded source
  test checks both paths. `test_thor_taskset_select_atomic.ps1`,
  `test_thor_transformers_hle_lfq_route.ps1`, `git diff --check`, the ARM64
  native build, and debug APK packaging passed. The exact installed APK
  SHA-256 was
  `1851434A95AFCB695BBF5F2AF9D357A1D1BF2C72FEEABD1B8162DD8039B6DB36`.
- Thor result: Capture
  `debug-captures/android-speed-sprint/20260829-183029-thor-input-custom`
  passed the one-sample cold-start gate at 44.5 C fixed silicon. The
  controller completed 70 half-second slices in 603.469 host seconds. It
  accumulated 43.395 active seconds, with active windows from 0.578 to 0.734
  seconds and 148 seconds of cooldown waits. It reached the host deadline
  before the requested second late-loader completion sample.
- Event evidence: The old boundary is gone. Experiment 137 stopped with EDGE
  sequence 283 and dispatch 281. This run produced event sequences 1, 79, and
  608. Its later census reported sequence 722 and dispatch 721/720. The title
  also reached late-load I/O completion sample 1 with 15 entries. One
  `TASKSET IDLE-READY` line occurred at sequence 79, but event delivery
  continued through sequence 722. It is not the old persistent stall.
- New boundary: After late-load completion sample 1, the main thread created
  the FMOD taskset and audio port. At emulator times 8:10 and 9:44, the main
  thread stayed at the HLE event-flag wait address `0x02003c54` with link
  register `0x00e2bab4`. The final two performance intervals reported 0.42
  FPS and then 0.00 FPS. This is the next boundary to trace. The current
  evidence does not yet identify whether the missing action is an FMOD task
  event, an event-flag wake, or an earlier task failure.
- Visual correctness: Not proved. The route did not reach the second marker,
  so it did not save a boundary image. No moving gameplay output exists.
- FPS/frame-time: No sustained-performance credit. The final performance
  interval was 0.00 FPS, and paused slices are not a comparable gameplay
  measurement.
- Thermal result: The controller maximum was 65.4 C fixed silicon. The
  independent device guard recorded 1,027 temperature samples. Fixed silicon
  peaked at 69.9 C, and CPU junction peaked at 81.5 C. It recorded 16 early
  holds at or above 66 C. It recorded no 72 C fixed-silicon hard stop and no
  95 C junction hard stop.
- Rollback: The verified stop found no RPCSX PID and zero RPCSX rows in
  `top`. Property cleanup cleared 57 values and found zero remaining
  `debug.rpcsx.thor.*` values. Final fixed silicon was 51.8 C.
- Decision: Keep the firmware-matching `WAIT_SIGNAL` return repair. It passes
  the old EDGE stall and permits substantially later title startup. Do not
  call this full HLE, moving gameplay, or a speed result. Keep the taskset
  event and completion semantics unchanged until the FMOD wait has a precise
  producer-side trace.
- Next: Map the main-thread call site at `0x00e2bab4` and the FMOD SPU task
  path. Add a bounded FMOD task and event-flag trace before another device
  run. Require moving 3D output and a comparable sustained 30 FPS measurement
  before a full-HLE or performance claim.

## 139. The FMOD task reaches the event-send helper

- Status: android-pass, boundary-capture, not-comparable
- Scope: HLE-SPURS, FMOD, event-delivery, thermal-safety
- Hypothesis: The main thread waits because the FMOD SPU task does not send
  its event to the HLE event flag.
- Changed files/settings: Commit `67b802bd0` adds the bounded, default-off
  `debug.rpcsx.thor.fmod_event_wait_trace` probe. The probe identifies the
  BLUS30357 main-thread wait by link register `0x00e2bab4`. It records the
  event flag, taskset, queue, port, task state, matching SPU PC, and one local
  store image. The run used exact installed APK
  `656AC6ADEFF0645B588C28E899D30A381E038232AA05F14F53316A422154BCCA`,
  size 116,148,476 bytes. The route used HLE, the EDGE task census, the EDGE
  event-wait trace, the FMOD event-wait trace, 0.5-second slices, and the
  second FMOD census sample as its stop marker.
- Thor result: The one-sample cold-start gate passed immediately at 42.9 C
  fixed silicon. The controller reached its marker after 46 slices and
  381.875 host seconds. Its maximum fixed-silicon value was 65.4 C. The
  main thread armed event flag `0x01f20600` for request `0x0001`. The flag
  used taskset `0x1144c200`, queue `0x8d008f00`, and port 21. Task 0 was
  enabled, ready, and running.
- SPU evidence: The first matching sample put FMOD task 0 on SPU 3 at PC
  `0x03010`. The second sample put the same task at PC `0x14008`, with link
  register `0x12150`, port 21 in register 3, zero in registers 4 and 5, and
  event-flag address `0x01f20600` in the last MFC address. The probe wrote
  one 262,144-byte local store image. Its SHA-256 was
  `30227856AB27F0AE7F84329059C0E6374E332633A2C13FE9048CBEEF33F642F2`.
- Static evidence: A read-only Ghidra 12.0.4 pass over the exact local store
  proves that PC `0x14008` is the SPU user-event send helper. The caller at
  `0x1214c` passes port 21, data zero, and event bits zero. The helper writes
  data to channel 28 at `0x14030`. It then writes interrupt value
  `0x55000000` to channel 30 at `0x14044`. The RPCSX decoder maps this value
  to SPU port 21 and sends the event to its queue. The earlier function uses
  GETLLAR at `0x11e24` and PUTLLC at `0x1207c` before it calls this helper.
- Boundary correction: The route stopped when PC was `0x14008`. It stopped
  before the channel writes at `0x14030` and `0x14044`. Zero dispatch at that
  sample does not prove a failed event. It proves that the route stopped one
  instruction before the event-send helper started its work.
- Visual correctness: Not proved. The boundary image is black except for the
  emulator overlay. It does not show the title or moving 3D output.
- FPS/frame-time: No performance credit. The saved overlay reports 0.13 FPS,
  PPU 0 percent, SPU 1.1 percent, and RSX 0 percent. A paused boundary image
  is not a comparable performance sample.
- Thermal result: The independent device guard recorded 15 holds at or above
  66 C. Fixed silicon reached 69.1 C, and CPU junction reached 85.1 C. It
  recorded no 72 C fixed-silicon hard stop and no 95 C junction hard stop.
- Rollback: The verified stop found no PID and zero RPCSX rows in `top`. It
  reported
  `quiet=true`. Final fixed silicon was 53.4 C. The local-store property was
  reset to value `0`. The wrapper now uses value `0` for all property reset
  paths because its mandatory value parameter rejects an empty string.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-190732-thor-input-custom`.
- Decision: Keep the WAIT_SIGNAL repair and the FMOD probe. Do not change
  event semantics from this capture. When the FMOD trace is enabled without
  an explicit stop marker, the route now stops at
  `Thor FMOD EFWAIT RETURN #0`. This prevents another stop before dispatch.
- Next: In one later independently cool round, continue through the SPU event
  line and the PPU wake and return lines. If the event appears but the PPU
  does not return, repair that exact event-flag boundary. If the return
  appears, continue to the next startup boundary. Require moving 3D output
  and a comparable sustained 30 FPS measurement before a full-HLE or speed
  claim.

## 140. The FMOD event probe records wrong queue states

- Status: proposed, route-tooling, not-comparable
- Scope: HLE-SPURS, FMOD, event-delivery
- Hypothesis: A missing or wrong SPU port connection can prevent the FMOD
  event from reaching the PPU queue.
- Changed files/settings: The default-off FMOD probe now identifies the send
  by the live taskset and port. It records the send result and both the actual
  and expected queue IDs. It also records a null queue as ID zero. This makes
  a failed connection visible instead of filtering it out.
- Rollback: Set `debug.rpcsx.thor.fmod_event_wait_trace` to `0`. The normal
  event path is unchanged when the probe is off.
- Windows result: Not run. This is an Android route diagnostic.
- Thor result: Not run. The Thor stayed stopped after experiment 139.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused Transformers HLE route contract and
  `git diff --check` passed. The full ARM64 debug APK build passed in 1 minute
  16 seconds. The host APK is 116,147,159 bytes. Its SHA-256 is
  `73DA69ADC0359F54C270CBD7ABE166C2728074FAFE5F9FF9FBB7E5182A824927`.
- Decision: Keep the wider diagnostic match. It changes only default-off
  logging and makes the next device run conclusive for queue connection.
- Next: In a separate cool round, install the exact APK and run one bounded
  HLE route. Stop at `Thor FMOD EFWAIT RETURN #0`. If the return marker does
  not appear, use the send result and queue IDs to repair the exact boundary.

## 141. The FMOD task stays at a cold LLVM block entry

- Status: android-pass, boundary-capture, not-comparable
- Scope: HLE-SPURS, FMOD, SPU-dispatch, thermal-safety
- Hypothesis: A missing or wrong SPU port connection prevents the FMOD event
  from reaching the PPU event queue.
- Changed files/settings: The run used the exact experiment 140 APK. Its
  installed SHA-256 was
  `73DA69ADC0359F54C270CBD7ABE166C2728074FAFE5F9FF9FBB7E5182A824927`,
  and its size was 116,147,159 bytes. The route used HLE, the FMOD event-wait
  trace, 0.5-second slices, and `Thor FMOD EFWAIT RETURN #0` as its stop
  marker. The EDGE task and event traces and the general SPU censuses were
  off.
- Thor result: The one-sample cold-start gate passed immediately at 44.5 C
  fixed silicon. The controller completed 69 slices in 599.437 host seconds
  and reached its host limit without the stop marker. It accumulated 42.241
  active seconds. Active windows were 0.578 to 0.672 seconds. Cooldown waits
  totaled 153 seconds.
- Event evidence: The main thread armed request `0x0001` on event flag
  `0x01f20600`. The flag used taskset `0x1144e580`, queue `0x8d009000`, and
  port 21. The trace recorded no `Thor FMOD EVENT`, wake, or return line. This
  proves that the task did not execute an event-send attempt. It does not show
  a missing or wrong port connection.
- SPU evidence: Sixteen samples from wait age 10.056 to 85.634 seconds put the
  same FMOD task 0 on SPU 1 at PC `0x14008`. Every sample had opcode
  `0x5e0fc188`, link register `0x12150`, port 21 in register 3, zero in
  registers 4 and 5, and zero outbound, interrupt, and inbound channels. The
  task stayed at the first instruction of the exact user-event helper. The
  startup native-object log loaded modules through `0x11d80`, but it did not
  load or compile an object for `0x14008`.
- Static evidence: The experiment 139 Ghidra result proves that `0x14008` to
  `0x1404c` is straight-line user-event helper code. It writes data to channel
  28 and interrupt value `0x55000000` to channel 30, then returns. Therefore,
  the repeated entry PC is a cold LLVM dispatch boundary, not a guest wait
  loop.
- Visual correctness: Not proved. The route did not reach its marker and did
  not save a boundary image. No moving 3D output exists.
- FPS/frame-time: No performance credit. The final interval reported 18
  frames in 104.00 seconds, or 0.17 FPS. Paused slices are not a comparable
  gameplay measurement.
- Thermal result: The controller maximum was 65.4 C fixed silicon. The
  independent guard recorded 1,017 temperature samples and 19 early holds.
  Fixed silicon peaked at 70.7 C, and CPU junction peaked at 85.1 C. It
  recorded no 72 C fixed-silicon hard stop and no 95 C junction hard stop.
  The final live values were 61.0 C fixed silicon and 67 C junction.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Final fixed silicon was 53.0 C. Property cleanup reset the
  FMOD trace and local-store controls.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-192850-thor-input-custom`.
- Decision: Reject the missing-port hypothesis for this run. Keep the
  firmware-matching `WAIT_SIGNAL` repair and the event semantics. The next
  candidate must execute the exact guest helper instead of creating a host
  event directly.
- Next: Use a default-off, title-state-gated interpreter handoff for the exact
  helper range. In one later independently cool round, require the helper
  enter and leave lines, the real SPU event line, the PPU wake, and the PPU
  return before the result can pass this boundary.

## 142. Interpret the exact FMOD user-event helper

- Status: proposed, host-pass, not-comparable
- Scope: HLE-SPURS, FMOD, SPU-dispatch
- Hypothesis: The cold LLVM dispatch boundary at `0x14008` prevents the FMOD
  SPU task from sending the event that releases the main thread.
- Changed files/settings: The default-off
  `debug.rpcsx.thor.fmod_event_interp` gate now hands PC `0x14008` to the old
  SPU interpreter before a cold LLVM compile. The gate also requires an active
  FMOD PPU wait, a nonzero wait taskset, the same taskset at local-store offset
  `0x27b8`, and the exact 16-byte helper signature. It interprets only
  `0x14008` through `0x1404f`. The experimental HLE route enables the gate and
  resets it after the run. It does not inject an event or change event-flag
  state.
- Rollback: Set `debug.rpcsx.thor.fmod_event_interp` to `0`. The normal LLVM
  dispatcher and event path are unchanged when the gate is off.
- Windows result: Not run. This is an Android ARM64 dispatch candidate.
- Thor result: Not run. Experiment 141 used the one allowed launch for this
  independently cool round, and the Thor remains stopped.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused Transformers HLE route contract, PowerShell
  parser checks for all changed scripts, and `git diff --check` passed. The
  complete Android debug APK build passed in 1 minute 15 seconds. The host APK
  is 116,146,165 bytes. Its SHA-256 is
  `CB0806B23C9101D7A591A284888C5B9911655855630DAA437EED15D5974A8FAA`.
- Decision: Keep this candidate for one device test. It follows the existing
  exact-range ARM64 interpreter pattern and executes the real guest helper.
- Next: In a separate independently cool round, install the exact APK and run
  one bounded HLE route. Stop at `Thor FMOD EFWAIT RETURN #0`. Require the
  interpreter enter and leave lines, event delivery, wake, and return. If the
  PPU returns, continue to the next proved startup boundary. Require moving
  3D output and a comparable sustained 30 FPS measurement before a full-HLE
  or speed claim.

## 143. The exact FMOD helper releases the main thread

- Status: android-pass, HLE-progress, not-comparable
- Scope: HLE-SPURS, FMOD, SPU-dispatch, event-delivery, thermal-safety
- Hypothesis: The cold LLVM dispatch boundary at `0x14008` prevents the FMOD
  SPU task from sending the event that releases the main thread.
- Changed files/settings: The run used exact experiment 142 APK
  `CB0806B23C9101D7A591A284888C5B9911655855630DAA437EED15D5974A8FAA`,
  size 116,146,165 bytes, and host commit `66ed84fa6`. It used HLE, the FMOD
  event-wait trace, the exact FMOD interpreter handoff, 0.5-second slices,
  and `Thor FMOD EFWAIT RETURN #0` as its stop marker. The general SPU
  censuses and EDGE task and event traces were off.
- Thor result: The one-sample cold-start gate passed immediately at 44.1 C
  fixed silicon. The controller reached its stop marker after 46 slices and
  397.906 host seconds. It accumulated 29.065 active seconds. Active windows
  were 0.593 to 0.781 seconds. Cooldown waits totaled 95 seconds.
- Event proof: The main thread armed request `0x0001` on event flag
  `0x01f20600`, taskset `0x11d89400`, queue `0x8d009000`, and port 21. At
  emulator time 6:45.027, the handoff entered at PC `0x14008`. The real guest
  helper sent the event at PC `0x14044`, with result zero and matching actual
  and expected queue IDs. It left at PC `0x12150`. The PPU then woke with
  event `0x0001` and returned success. The event occurred 90,476 microseconds
  after the wait armed. This proves the complete SPU-to-PPU event path through
  the PPU return.
- Boundary comparison: Experiment 141 sampled the same task at `0x14008`
  sixteen times through an 85.634-second wait and recorded no event attempt.
  This run executed the helper once and returned the PPU wait about 90 ms
  after it armed. Keep the interpreter candidate.
- Visual correctness: The paused boundary image shows the title loading
  screen and its loading indicator. It is no longer the black overlay-only
  frame from experiment 139. The overlay shows 25.14 FPS, PPU 13.0 percent,
  SPU 49.4 percent, RSX 6.2 percent, and total CPU 68.6 percent. This is a
  static loading boundary, not moving 3D gameplay.
- FPS/frame-time: No sustained-performance credit. The last complete log
  interval before the marker reported 115 frames in 105.55 seconds, or 1.09
  FPS. The paused screenshot's instantaneous 25.14 FPS is not a comparable
  gameplay measurement.
- Thermal result: The controller maximum was 65.4 C fixed silicon. The
  independent guard recorded 696 temperature samples and 11 early holds.
  Fixed silicon peaked at 70.7 C, and CPU junction peaked at 86.3 C. It
  recorded no 72 C fixed-silicon hard stop and no 95 C junction hard stop.
  The final live values were 58.6 C fixed silicon and 75 C junction.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Final fixed silicon was 52.2 C after stop and 53.4 C after
  property cleanup. Cleanup cleared all 60 listed properties and found zero
  remaining `debug.rpcsx.thor.*` values.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-195105-thor-input-custom`.
- Decision: Keep the exact helper interpreter handoff. It repairs the proved
  FMOD cold-dispatch boundary without injecting an event or changing the HLE
  event-flag rules. Do not call this full HLE or 30 FPS. The title has reached
  a real loading frame, but moving gameplay is not yet proved.
- Next: In a separate independently cool round, continue past this return and
  stop at the next deterministic loading or visual boundary. Record the next
  persistent PPU or SPU wait if loading does not complete. Require moving 3D
  output and a comparable sustained 30 FPS measurement before a full-HLE or
  speed claim.

## 144. The late-load route lacks its marker producer

- Status: thermal-stop, route-tooling, not-comparable
- Scope: HLE-SPURS, loading, PPU-census, thermal-safety
- Hypothesis: After the repaired FMOD return, the title will reach the second
  late-load completion sample or expose the next persistent HLE boundary.
- Changed files/settings: The run used the exact experiment 143 APK and HLE
  stack. Its installed SHA-256 was
  `CB0806B23C9101D7A591A284888C5B9911655855630DAA437EED15D5974A8FAA`,
  and its size was 116,146,165 bytes. It used 0.5-second slices and requested
  `Thor LATE LOAD IO COMPLETION: sample=2` as its stop marker. The full runtime
  census, PPU PC census, general SPU census, and EDGE traces were off.
- Thor result: The one-sample cold-start gate passed immediately at 45.8 C
  fixed silicon. The controller completed 64 slices in 582.609 host seconds.
  It accumulated 41.207 active seconds. Active windows were 0.593 to 0.782
  seconds. Cooldown waits totaled 145 seconds. The independent guard then
  stopped the package at the 72 C fixed-silicon hard limit.
- FMOD proof: The repaired path repeated. The helper entered at PC `0x14008`,
  sent the real guest event at PC `0x14044` with result zero and matching queue
  IDs, left at PC `0x12150`, woke the PPU, and returned request `0x0001`
  successfully. The event occurred 8.147 seconds after the wait armed because
  the sliced route paused the task before it reached the helper.
- Forward evidence: After the FMOD return, one complete performance interval
  reported 112 frames in 88.38 seconds, or 1.27 FPS. The title shut down its
  loading taskset, searched its loading-video fallback paths, and started its
  audio path. The next interval reported zero frames in 111.78 seconds. This
  shows later startup work, but it does not identify the final zero-frame
  state.
- Marker failure: The requested late-load marker is emitted only inside the
  PPU PC census. This run disabled that census, so the marker could not exist.
  The marker result cannot classify the guest path. The route must not be
  repeated without its marker producer.
- Visual correctness: Not measured. The marker did not occur, so the route did
  not save a boundary image.
- FPS/frame-time: No performance credit. The route used paused slices, ended
  in a zero-frame interval, and hit a thermal hard stop.
- Thermal result: The controller maximum was 67.0 C fixed silicon. The
  independent guard recorded 977 temperature samples and 23 early holds.
  Fixed silicon peaked at 72.3 C, and CPU junction peaked at 87.5 C. The hard
  stop was required and worked as designed.
- Rollback: After the hard stop, the verified stop found no PID, zero RPCSX
  rows in `top`, and `quiet=true`. Property cleanup cleared all 60 listed
  properties and found zero remaining `debug.rpcsx.thor.*` values. Final fixed
  silicon was 54.2 C.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-200239-thor-input-custom`.
- Decision: Keep the FMOD repair. Do not infer a new HLE defect from this
  run. Classify the late result as route-tooling evidence because the stop
  marker had no enabled producer and the thermal guard ended the process.
- Next: Add a PPU-only census switch. Fail closed when a late-load marker is
  requested without the PPU or full runtime census. Use the PPU-only switch in
  one later independently cool route to reduce observation load.

## 145. Give late-load markers a PPU-only route

- Status: route-tooling, host-pass, not-comparable
- Scope: config-driver, PPU-census, thermal-safety
- Hypothesis: A PPU-only census can produce the late-load marker and boundary
  PCs without the draw and SPU-event load of the full runtime census.
- Changed files/settings: The Transformers HLE wrapper now exposes default-off
  `-PpuPcCensus`. It enables `debug.rpcsx.thor.ppu_pc_census` alone unless the
  caller also requests other censuses. A sliced route that requests a
  `Thor LATE LOAD` marker now fails before any ADB or device action unless the
  PPU-only or full runtime census is on.
- Rollback: Leave `-PpuPcCensus off`. The property remains default-off and the
  wrapper resets it after every run.
- Windows result: Not run. This is Android route control.
- Thor result: Not run. Experiment 144 used the one allowed launch for this
  independently cool round, and the Thor remains stopped.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused Transformers HLE route contract, a direct
  fail-closed invocation, PowerShell parsing, and `git diff --check` passed.
  The scripts do not change the APK or native core.
- Decision: Keep the PPU-only route. It prevents an impossible stop marker and
  limits the next diagnostic to the census that produces the requested
  evidence.
- Next: In a separate independently cool round, use the exact installed APK,
  keep the full runtime census off, enable the PPU-only census, and stop at
  late-load completion sample 2. If the marker does not occur, use the final
  PPU PCs and bounded loading state to name the next repair boundary. Require
  moving 3D output and a comparable sustained 30 FPS measurement before a
  full-HLE or speed claim.

## 146. Bound observation after the FMOD return

- Status: route-tooling, host-pass, not-comparable
- Scope: config-driver, PPU-census, thermal-safety
- Hypothesis: A fixed post-FMOD slice window will capture the next PPU state
  even when the repaired path bypasses late-load completion sample 2.
- Changed files/settings: The Thor slice controller now accepts an optional
  arm log match and zero to 64 post-arm slices. It records the exact arm line,
  arm slice, requested window, completed window, and whether the stop came
  from the ordinary marker or the post-arm bound. The Transformers wrapper
  exposes these fields, writes them to the capture README, and rejects a
  positive post-arm count without an arm marker.
- Rollback: Leave the arm marker empty and the post-arm slice count at zero.
  Existing slice-loop behavior is unchanged.
- Windows result: Not run. This is Android route control.
- Thor result: Not run. The APK and native core are unchanged.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The guarded controller test proves that an arm on slice 2 and
  a two-slice post-arm window stop on slice 4 with the exact arm evidence. The
  Transformers route contract, PowerShell parsing, Python bytecode compile, a
  direct fail-closed invocation, and `git diff --check` passed.
- Decision: Keep the bounded post-arm window. It prevents a repaired boundary
  from turning the next probe into another full thermal-duration run.
- Next: In one independently cool route, enable the PPU-only census, keep
  late-load completion sample 2 as an earlier stop, arm on the proved FMOD
  return, and stop after eight additional slices. Use the resulting PPU state
  and image to select the next HLE repair. Require moving 3D output and a
  comparable sustained 30 FPS measurement before a full-HLE or speed claim.

## 147. The control pause times out during startup

- Status: route-tooling, failed, not-comparable
- Scope: controller, loading, PPU-census, thermal-safety
- Hypothesis: Eight slices after the repaired FMOD return will identify the
  next persistent loading boundary.
- Changed files/settings: The route used the exact experiment 143 APK. Its
  installed SHA-256 was
  `CB0806B23C9101D7A591A284888C5B9911655855630DAA437EED15D5974A8FAA`.
  The route enabled the PPU-only census and armed on
  `Thor FMOD EFWAIT RETURN #0`. It requested eight later half-second slices.
- Thor result: The one-sample cold-start gate passed at 45.3 C fixed silicon.
  The route completed 39 slices. It did not reach the FMOD return or arm the
  later window. The last requested half-second slice took 50.688 host seconds.
  Its pause request started at 0.500 seconds, but the local control request
  timed out. The controller could not prove a held state and used its verified
  package stop. This is a controller failure, not an HLE result.
- Guest evidence: The final PPU sample put `main_thread` at `0x01016e3c`,
  `RenderingThread` at `0x009e4ba4`, and the pool and I/O threads at
  `0x00a02218`. These are pre-FMOD startup states. They do not prove a new HLE
  boundary.
- Visual correctness: Not measured. The route did not reach its marker, so it
  did not save a boundary image.
- FPS/frame-time: No performance credit. The diagnostic interval reported 85
  frames in 93.26 seconds, or 0.91 FPS. Paused startup slices are not a
  gameplay measurement.
- Thermal result: The independent guard recorded 629 samples. Fixed silicon
  peaked at 68.2 C, and CPU junction peaked at 83.9 C. It recorded four early
  holds and no hard stop.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared all 60 listed properties and found
  zero remaining `debug.rpcsx.thor.*` values. The final fixed-silicon sample
  was 52.2 C.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-202142-thor-input-custom`.
- Decision: Keep the HLE repair and the bounded post-FMOD route. Do not use
  this run to select an emulator repair.
- Next: Make a timed-out pause request use a verified process hold. Do not run
  the Thor again in this work round.

## 148. Fall back to a verified process hold

- Status: route-tooling, host-pass, not-comparable
- Scope: controller, pause, process-liveness, thermal-safety
- Hypothesis: A bounded control timeout and a verified process hold will keep
  a slow pause response from ending the next loading route.
- Changed files/settings: A normal slice now gives its deadline pause request
  at most one second. If that request fails, the controller sends `SIGSTOP` to
  the same live PID and verifies the stopped process state. The process-hold
  helper checks the current PID before and after the signal. It refuses a
  stale or replaced PID.
- Rollback: Revert this controller change. The APK and native core are
  unchanged.
- Windows result: Not run. This is Android route control.
- Thor result: Not run. Experiment 147 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The guarded controller test proves that a timed-out pause
  request completes with `holdMode=process`. It also proves that a stale PID
  receives no signal. Python bytecode compilation and `git diff --check` pass.
- Decision: Keep the process-hold fallback. It removes the 50-second control
  failure that ended experiment 147.
- Next: In one later independently cool route, use the PPU-only census. Stop at
  late-load completion sample 2, or arm on the proved FMOD return and stop
  after eight more slices. Use the final PPU state and image to select the next
  HLE repair.

## 149. The bounded route reaches the post-FMOD loading UI

- Status: android-pass, boundary-capture, not-comparable
- Scope: HLE, FMOD, loading, PPU-census, thermal-safety
- Hypothesis: The process-hold fallback will let the route reach the repaired
  FMOD return and capture the next persistent PPU state.
- Changed files/settings: The route used the exact experiment 143 APK. Its
  installed SHA-256 was
  `CB0806B23C9101D7A591A284888C5B9911655855630DAA437EED15D5974A8FAA`.
  It enabled the FMOD event interpreter and trace, enabled the PPU-only census,
  armed on `Thor FMOD EFWAIT RETURN #0`, and requested eight later half-second
  slices. The full runtime census remained off.
- Thor result: The one-sample cold-start gate passed at 45.3 C fixed silicon.
  The route completed 50 slices and armed on slice 42. It then completed all
  eight requested post-arm slices and stopped with `markerKind=post-arm`.
  Total host time was 454.516 seconds. The 50 active windows totaled 37.558
  seconds and ranged from 0.672 to 0.906 seconds. Every slice ended in a
  verified process hold. The pause failure from experiment 147 did not recur.
- FMOD evidence: SPU 2 entered at PC `0x14008`, received the expected event at
  PC `0x14044` from queue `0x8d009000`, left at PC `0x12150`, and woke the PPU
  with request bit `0x1`. The route then created the audio notification queue
  and the FMOD audio-receive and stream threads. This repeats the repaired FMOD
  return with real queue delivery.
- New PPU boundary: `main_thread` was in HLE code at `0x022254ec` with link
  register `0x00e28c5c`. `RenderingThread` was at `0x009e4ba4`. The pool and
  asynchronous I/O threads were at `0x00a02218`. Later SPU dispatches continued,
  so this is not a global process stop.
- Static analysis: Ghidra shows that the wrapper at `0x00e28c40` calls import
  stub `0x0160c8c4` with a zero timeout and returns at `0x00e28c5c`. The PS3
  import table maps function-table entry `0x0193b8e8` to `sysPrxForUser` NID
  `0x1573dc3f`, which is `sys_lwmutex_lock`. The main PPU thread is therefore
  waiting for a lightweight mutex. It is not waiting for a semaphore.
- Visual correctness: The boundary image shows the real Transformers loading
  emblem in the lower-right corner. Its SHA-256 is
  `345E21D3794F50ED277479ECEE5799998ACC9B845A2AA10CA292F731045A61EC`.
  The image gate classifies it as black because 98.0 percent of pixels are near
  black. This is valid loading UI, not moving 3D output.
- FPS/frame-time: No performance credit. The paused diagnostic reported 128
  frames in 81.45 seconds, or 1.57 FPS. It is not a gameplay measurement.
- Thermal result: The controller maximum was 67.0 C fixed silicon. The
  independent guard recorded 781 samples and 19 early process holds. Fixed
  silicon peaked at 71.5 C, and CPU junction peaked at 88.7 C. Neither hard
  limit was reached.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared all listed properties and found zero
  remaining `debug.rpcsx.thor.*` values. The final independent fixed-silicon
  sample was 57.8 C. A later direct check measured 52.2 C.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-203553-thor-input-custom`.
- Decision: Keep the FMOD repair, PPU-only census, bounded post-arm route, and
  process-hold fallback. Do not force the lightweight mutex open. First record
  its owner and matching unlock path.
- Next: Add a default-off, title-gated trace for this one mutex call site. In a
  later independently cool run, record the dynamic mutex address, owner,
  waiter count, sleep queue, and matching unlock thread.

## 150. Trace the exact lightweight-mutex boundary

- Status: instrumentation, host-pass, not-comparable
- Scope: Ghidra, sysPrxForUser, lightweight-mutex, config-driver
- Hypothesis: A bounded trace of the exact main-thread mutex will show whether
  its owner fails to unlock, unlocks a different object, or only needs more
  startup work.
- Changed files/settings: `sys_lwmutex_.cpp` now has the default-off property
  `debug.rpcsx.thor.transformers_lwmutex_trace`. It can arm only for BLUS30357,
  `main_thread`, and link register `0x00e28c5c`. After it records the dynamic
  mutex address, it logs only that object's lock, kernel sleep, wake, and unlock
  states. Each line includes the PPU ID and name, owner, waiter count,
  attributes, recursive count, sleep queue, and result. The quota is 128 lines.
  The trace does not change mutex memory or scheduler state. The Transformers
  wrapper exposes `-LwmutexTrace on` and clears the property after the run.
- Online source check: The current Ps3GhidraScripts import parser confirms the
  0x2c-byte PPU import descriptor layout and the parallel NID and function
  address tables. The current local RPCSX NID map independently names
  `0x1573dc3f` as `sys_lwmutex_lock`.
- Rollback: Leave `-LwmutexTrace off`, which is the default. Revert the trace
  and wrapper changes to remove the diagnostic code.
- Windows result: Not run. This is Android native code.
- Android build result: `:app:assembleDebug --no-configuration-cache` passed in
  1 minute 43 seconds. The modified `sys_lwmutex_.cpp` compiled and linked.
- Thor result: Not run. Experiment 149 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused Transformers route contract, PowerShell parser,
  and `git diff --check` passed. The native Android debug build passed.
- Decision: Keep the bounded mutex trace. It observes the proved boundary and
  does not invent a mutex release.
- Next: In one later independently cool run, use the exact built APK, enable
  the mutex trace, arm on `Thor TWC LWM ARM`, and keep a bounded post-arm
  window. Use the recorded owner and unlock evidence to select the next repair.

## 151. Map the Transformers lightweight-mutex wrappers

- Status: instrumentation, host-pass, not-comparable
- Scope: Ghidra, sysPrxForUser, lightweight-mutex, call-site trace
- Hypothesis: The game-level caller will distinguish the three static lock
  families and identify the code that blocks the main thread.
- Static result: Ghidra shows that wrapper `0x00e28c38` calls import stub
  `0x0160c8c4`, which maps to `sys_lwmutex_lock`. Wrapper `0x00e28bf8` calls
  import stub `0x0160c8e4`, which maps to `sys_lwmutex_unlock`. The FMOD audio
  receive loop locks the objects at global offsets `0x10b0` and `0x10ac`, does
  its update work, and unlocks the same objects in reverse order. The other
  static callers use a list lock at offset `0x10b4` and a worker-list lock.
- Upstream source check: Current RPCS3 uses the same non-HLE lightweight-mutex
  algorithm as this RPCSX tree. The June 2024 `SYS_SYNC_RETRY` signaled-bit
  correction is already present in the local kernel implementation. There is
  no missing upstream lightweight-mutex repair to copy for this boundary.
- Changed files/settings: The existing default-off trace now reads the saved
  link register at stack offset `0x80` only when the game is inside its known
  lock or unlock wrapper. Each bounded trace line includes the stack pointer
  and game-level caller. The trace still does not change mutex or scheduler
  state.
- Rollback: Leave `-LwmutexTrace off`, which is the default. Revert the added
  caller fields to remove the extra diagnostic read.
- Windows result: Not run. This is Android native code.
- Android build result: `:app:assembleDebug --no-configuration-cache` passed in
  1 minute 5 seconds. The modified native file compiled and linked. The APK
  SHA-256 is
  `CDF0F94FDA7792BD65F809FA6C40A54DCC65C30BDA943D1B05B071DA790AF908`.
- Thor result: Not run. Experiment 149 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused route contract, PowerShell parser, native Android
  build, and `git diff --check` passed.
- Decision: Keep the caller field. It identifies the game code that owns or
  waits for the target mutex without changing guest state.
- Next: In one later independently cool run, arm on the exact main-thread lock.
  Match its caller and owner to the lock and unlock families above. Do not
  force the mutex open without that evidence.

## 152. The wrapper trace does not observe the kernel wait

- Status: instrumentation-failed, android-boundary, not-comparable
- Scope: HLE, FMOD, lightweight-mutex, thermal-safety
- Hypothesis: The wrapper trace will arm at the proved main-thread lock and
  identify the thread that owns or releases the mutex.
- Changed files/settings: The route installed the experiment 151 APK. Its
  installed SHA-256 was
  `CDF0F94FDA7792BD65F809FA6C40A54DCC65C30BDA943D1B05B071DA790AF908`.
  It enabled the FMOD repair and trace, the wrapper mutex trace, and the
  PPU-only census. It requested half-second slices with a bounded post-arm
  window.
- Thor result: The one-sample cold-start gate passed at 46.0 C fixed silicon.
  The route completed 72 slices in 604.172 host seconds. The active windows
  totaled 52.610 seconds and ranged from 0.640 to 0.906 seconds. Every slice
  ended in a verified process hold. The host deadline stopped the route.
- Guest evidence: SPU 2 received the expected FMOD event at PC `0x14044` from
  queue `0x8d009000`, woke the PPU, and returned with success. The main PPU
  thread was again in HLE code at `0x022254ec` with link register
  `0x00e28c5c`. This state occurred at approximately 6 minutes 25 seconds,
  7 minutes 58 seconds, and 9 minutes 19 seconds. Later SPU dispatches also
  continued.
- Instrumentation result: The property readback was exactly `1`, and the APK
  contained the `Thor TWC LWM ARM` string. The log contained no wrapper mutex
  rows. This is an observation-point failure. It does not prove that the game
  did not call or wait on the mutex.
- Visual correctness: Not measured. The route did not reach the marker, so it
  did not save an image.
- FPS/frame-time: No performance credit. The diagnostic interval reported 47
  frames in 93.30 seconds, or 0.50 FPS. This was paused loading, not gameplay.
- Thermal result: The controller maximum was 65.8 C fixed silicon. The
  independent guard recorded 1,048 samples and 21 early holds. Fixed silicon
  peaked at 71.1 C, and CPU junction peaked at 85.1 C. It recorded no hard
  stop.
- Rollback: The final stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared all 61 listed properties and found
  zero remaining `debug.rpcsx.thor.*` values. The final independent
  fixed-silicon sample was 51.0 C, and the cleanup sample was 51.8 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-211329-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-211345-transformers-lwmutex-install`,
  and
  `debug-captures/android-speed-sprint/20260829-211426-thor-input-custom`.
- Decision: Do not repeat the wrapper trace and do not force the mutex open.
  Move the trace into `_sys_lwmutex_lock`, where the PPU census proves that the
  thread sleeps.
- Next: Record the kernel mutex ID, guest control state, queue head, and the
  exact unlock handoff in a later independently cool run.

## 153. Trace the Transformers kernel mutex queue

- Status: instrumentation, host-pass, not-comparable
- Scope: LV2, lightweight-mutex, PPU scheduler, config-driver
- Hypothesis: A bounded trace inside the kernel mutex implementation will
  record the sleep and matching handoff that the wrapper trace missed.
- Changed files/settings: `kernel/cellos/src/sys_lwmutex.cpp` now uses the same
  default-off Android property as the wrapper trace. It can arm only for
  BLUS30357, main PPU ID `0x01000000`, link register `0x00e28c5c`, and the
  first matching kernel mutex ID. It records the guest control address, owner,
  waiter count, attribute, sleep queue, kernel signal state, queue-head PPU,
  wake target, and result. The 128-line quota covers lock sleep, wake, return,
  normal unlock, and unlock2. The trace does not change guest memory, queue
  order, wake policy, or scheduler state.
- Rollback: Leave `-LwmutexTrace off`, which is the default. Revert the kernel
  trace to remove the diagnostic code.
- Windows result: Not run. This is Android native code.
- Android build result: `:app:assembleDebug --no-configuration-cache` passed
  in 1 minute 18 seconds after explicit conversions for two guest-endian log
  fields. The modified kernel file compiled and linked. The APK SHA-256 is
  `874D1C25CBC29AB559B1898168735E7B336B6B4D4700D8760B75E153706B1041`.
- Thor result: Not run. Experiment 152 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Verification: The focused route contract, PowerShell parser, native Android
  build, and `git diff --check` passed. The trace marker is present in the
  unstripped, merged, and stripped Android native libraries.
- Decision: Keep the kernel trace. It observes the queue that contains the
  proved main-thread wait and does not invent a signal or handoff.
- Next: In one later independently cool run, install the exact APK, arm on
  `Thor TWC LV2 ARM`, and stop after the bounded post-arm window. Use the
  recorded owner and unlock handoff to make the narrow HLE repair.

## 154. The kernel trace identifies the FMOD mutex owner

- Status: android-boundary, owner-identified, not-comparable
- Scope: HLE, FMOD, LV2 lightweight-mutex, thermal-safety
- Hypothesis: The kernel trace will identify the thread that owns the mutex
  that blocks the main PPU thread after the repaired FMOD event wait.
- Changed files/settings: The route installed the experiment 153 APK. Its
  installed SHA-256 was
  `874D1C25CBC29AB559B1898168735E7B336B6B4D4700D8760B75E153706B1041`.
  It enabled the FMOD event interpreter and trace, the kernel lightweight-mutex
  trace, and the PPU-only census. It requested half-second slices, armed on
  `Thor TWC LV2 ARM`, and requested eight later slices.
- Thor result: The one-sample cold-start gate passed at 48.0 C fixed silicon.
  The route completed 36 slices in 291.313 host seconds. The active windows
  totaled 25.218 seconds. Every slice ended in a verified process hold.
- Route limitation: The wrapper replaced the default late-load stop with
  `Thor FMOD EFWAIT RETURN #0` because FMOD tracing was on. The same slice
  contained the later kernel-arm marker, but the controller stopped before it
  completed the requested post-arm window. This run identifies the owner. It
  does not show the matching unlock or prove a persistent deadlock.
- FMOD evidence: SPU 3 received the expected event at PC `0x14044` from queue
  `0x8d008f00`, woke the main PPU thread, and returned with success. The game
  then created audio notification queue key `0x80004d494f323221` and created
  the `FMOD libAudio event receive thread` as PPU `0x0100000c`.
- Mutex evidence: At emulator time 4 minutes 58.015 seconds, the main PPU
  thread entered kernel mutex ID `0x95008b00`. Its guest control address was
  `0x1132f640`, its owner was PPU `0x0100000c`, and its waiter count was one.
  The kernel then queued the main thread. The owner is the FMOD audio event
  receive thread. The queue is not an unknown SPURS or renderer lock.
- Visual correctness: The boundary image is black except for the RPCSX
  performance overlay. Its SHA-256 is
  `AC2E0D496E74D7C6202D1AA54696A03F15746409F44C230FA44FFF01DC16DD7D`.
  It is not moving gameplay.
- FPS/frame-time: No performance credit. The paused diagnostic showed 0.63
  FPS. This is a loading and trace sample, not a gameplay measurement.
- Thermal result: The independent guard recorded 527 samples. Fixed silicon
  peaked at 68.7 C, and CPU junction peaked at 79.5 C. Eight samples reached
  the 66 C early-hold range. No fixed-silicon sample reached 70 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared all 61 listed properties and found
  zero remaining `debug.rpcsx.thor.*` values. The cleanup fixed-silicon sample
  was 50.6 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-214300-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-214329-transformers-kernel-lwmutex-install`,
  and
  `debug-captures/android-speed-sprint/20260829-214356-thor-input-custom`.
- Decision: Keep the kernel trace. Do not force the mutex open. Record the
  audio event send and the owner-thread unlock in the next hardware round.
- Next: Prevent the FMOD default stop from replacing an armed late-load route.
  Add bounded audio notification and saved-caller fields before that run.

## 155. Map the FMOD audio event owner

- Status: static-analysis, host-pass, not-comparable
- Scope: Ghidra, FMOD, cellAudio, event queue, lightweight-mutex
- Hypothesis: The owner-thread callback and current audio notification source
  will show what must happen before the owner releases the mutex.
- Static result: Ghidra maps PPU `0x0100000c` to the shared worker trampoline
  at `0x00e31738`. The create helper at `0x00e314ec` waits for the child start
  flag before it returns. The FMOD audio callback at `0x00e2b3e0` locks two
  FMOD mutexes, receives an audio event, and unlocks the mutexes in reverse
  order at `0x00e2b460` and `0x00e2b470`. The receive is therefore inside the
  protected region.
- Local source result: `cell_audio_thread::advance` collects registered audio
  queues under the audio mutex, releases that mutex, and sends
  `CELL_AUDIO_EVENT_MIX` to each selected LV2 queue. The local comparison
  checkout at commit `8ffd7be082515009ba73b3cf3c85d1c9a0a0323c` uses the same
  registration and send path. Its other audio changes do not repair this
  event handoff.
- Online source result: Current official RPCS3 source uses the same
  `CELL_AUDIO_EVENT_MIX` send after `cell_audio_thread::advance` releases the
  audio mutex. RPCS3 issue 2860 also records an FMOD libAudio event receive
  thread directly after the audio notification queue setup. This confirms
  that the thread type and setup order are normal. It does not prove that the
  Transformers event was sent or received in this run.
- Sources:
  `https://github.com/RPCS3/rpcs3/blob/master/rpcs3/Emu/Cell/Modules/cellAudio.cpp`
  and `https://github.com/RPCS3/rpcs3/issues/2860`.
- Ghidra reports:
  `debug-captures/ghidra-transformers-ppu-20260828-224900/focused-project/BLUS30357-fmod-owner-thread.txt`,
  `BLUS30357-fmod-thread-create.txt`,
  `BLUS30357-fmod-thread-create-case3.txt`, and
  `BLUS30357-fmod-receive-branches.txt`.
- Decision: Do not add a speculative mutex release. First trace the registered
  queue, audio send result, saved main-thread caller, and normal owner unlock.
- Next: Add default-off, BLUS30357-only fields for that one boundary. Then use
  one bounded post-arm Thor run after a new cold-start gate.

## 156. Preserve an explicit post-arm stop

- Status: route-tooling, host-pass, not-comparable
- Scope: controller, FMOD trace, post-arm capture
- Hypothesis: An armed route must keep its late-load stop so that it can record
  the mutex owner after the FMOD return marker.
- Changed files/settings: The Transformers wrapper now selects the FMOD return
  as its implicit stop only when `SliceArmMatch` is empty. An explicit arm
  keeps the requested stop and post-arm slice contract.
- Rollback: Revert the added arm check.
- Windows result: The focused route contract and PowerShell parser pass.
- Thor result: Not run. Experiment 154 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the route correction. It prevents the early stop that limited
  experiment 154.
- Next: Add the bounded audio and caller trace, build it, and use it in the
  next independently cool hardware round.

## 157. Trace the Transformers audio event handoff

- Status: instrumentation, host-pass, not-comparable
- Scope: cellAudio, LV2 lightweight-mutex, call-site trace, config-driver
- Hypothesis: The next bounded run must show whether `cellAudio` sends the
  notification that lets the FMOD owner release the main-thread mutex.
- Changed files/settings: The existing default-off property now enables a
  BLUS30357-only audio trace. It records the queue ID, IPC key, source, flags,
  and start period when the game registers its audio notification queue. It
  then records the first 63 send periods and `CellError` results. The kernel
  mutex trace also reads the saved game link register at stack offset `0x80`
  for the proved main-thread wrapper. It adds this caller to the arm and queue
  rows. The trace does not change event data, queue order, mutex state, or
  scheduler state.
- Rollback: Leave `-LwmutexTrace off`, which is the default. Revert the audio
  and saved-caller trace to remove the diagnostic code.
- Windows result: Not run. This is Android native code.
- Android build result: The first build compiled both changed native files but
  did not link because the log passed the anonymous `CELL_AUDIO_EVENT_MIX`
  enum to the formatter. An explicit `u32` log conversion corrected it. The
  final `:app:assembleDebug --no-configuration-cache` build passed in 1 minute
  17 seconds with 42 tasks.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,149,758 bytes, and its SHA-256 is
  `5A30FB172BF2CB89A290F68420248E71E8B8440B3E88E659F6B804CA883F8EF7`.
- Verification: The focused route contract, PowerShell parser, and
  `git diff --check` pass. Both audio markers and the caller field are present
  in the unstripped, merged, and stripped Android native libraries.
- Thor result: Not run. Experiment 154 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the bounded trace. It distinguishes a missing audio send,
  queue backpressure, and a normal mutex handoff without inventing a release.
- Next: After a new strict cold-start gate below 70 C, install this exact APK.
  Arm on `Thor TWC LV2 ARM`, keep the late-load stop, and collect eight later
  half-second slices.

## 158. Trace the exact Transformers audio queue

- Status: instrumentation, host-pass, not-comparable
- Scope: LV2 event queue, cellAudio, FMOD, config-driver
- Hypothesis: A trace of IPC key `0x80004d494f323221` will distinguish a
  missing audio heartbeat from a rejected, stored, or delivered notification.
- Prior dynamic evidence: Experiment 149 created the audio queue and FMOD
  receive worker at emulator time 6 minutes 18.505 seconds. At 6 minutes
  27.243 seconds, PPU `0x0100000c` was still in the HLE receive call with game
  return address `0x00e2b454`. The main PPU thread was still in the proved
  lightweight-mutex wait. This 8.7-second state is much longer than the
  expected audio heartbeat, but the old capture did not record an event send.
- Changed files/settings: The existing default-off, BLUS30357-only property
  now traces only the exact audio IPC queue. Its 64-line quota records receive
  entry, receive wait, ready events, stored sends, full-queue errors, and the
  PPU that a send wakes. Each row includes queue depth, event fields, and the
  result. It does not change queue contents, wake order, or scheduler state.
- Rollback: Leave `-LwmutexTrace off`, which is the default. Revert the queue
  trace to remove this diagnostic code.
- Windows result: Not run. This is Android native code.
- Android build result: `:app:assembleDebug --no-configuration-cache` passed
  in 59 seconds with 42 tasks. The modified `sys_event.cpp` compiled and
  linked.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,152,755 bytes, and its SHA-256 is
  `44447813C6BF5CCB8D3CCA7DD9533DA5FDFA6B5A08070A32D47BF4A73C6DA12C`.
- Verification: The focused route contract and `git diff --check` pass. The
  audio queue marker is present in the unstripped, merged, and stripped
  Android native libraries.
- Thor result: Not run. Experiment 154 used the one allowed launch for this
  independently cool work round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the exact queue trace. The next bounded run now has enough
  evidence to select either an audio-heartbeat repair or an event wake repair.
- Next: In the next independently cool hardware round, install this exact APK.
  Use the corrected post-arm route and collect the audio, queue, mutex owner,
  saved caller, unlock, and late-load evidence together.

## 159. The audio send does not complete the selected PPU wake

- Status: android-boundary, deferred-wake-identified, visual-invalid,
  not-comparable
- Scope: HLE, FMOD, LV2 event queue, PPU scheduler, thermal-safety
- Hypothesis: The exact audio queue trace will show whether the FMOD receive
  worker gets an event and returns to release the mutex that blocks the main
  PPU thread.
- Changed files/settings: The route installed the experiment 158 APK. Its
  installed SHA-256 was
  `44447813C6BF5CCB8D3CCA7DD9533DA5FDFA6B5A08070A32D47BF4A73C6DA12C`.
  It enabled the FMOD event interpreter, the exact audio queue trace, the
  kernel lightweight-mutex trace, and the PPU census. It armed on the kernel
  mutex row and kept a bounded post-arm window.
- Thor result: The one-sample cold-start gate passed at 50.0 C fixed silicon.
  The route completed 49 slices in 407.265 host seconds. The active windows
  totaled 35.866 seconds. Every slice ended in a verified process hold.
- Event result: The game registered queue `0x8d009200` with IPC key
  `0x80004d494f323221`. PPU `0x0100000c`, the FMOD libAudio event receive
  thread, entered an empty receive and waited. Audio period 32 selected and
  woke that PPU. Period 33 stored one event. The worker consumed it and
  entered another receive. Period 34 again selected the worker. Periods 35
  and 36 stored two events. Period 37 and later sends returned a full-queue
  error through the trace quota.
- Scheduler result: The selected worker did not return to game code. Its later
  state was `0x224`, which is `wait + suspend + memory` and has no `signal`.
  The main PPU thread entered the mutex wait 0.501 milliseconds after the
  second selected send. The saved game caller was `0x00dd6264`. Ghidra maps
  this call to the lock at global offset `0x10ac`. The FMOD worker owns that
  lock and can release it only after the event receive returns at
  `0x00e2b454`.
- Cause: `lv2_obj::awake` placed the worker in a running scheduler slot, but
  `schedule_all` did not complete the state wake while the global suspend
  barrier was nonzero. A plain atomic notification cannot repair this state
  because the worker has no signal and still has suspend.
- Online source result: Current official RPCS3 source uses the same event
  queue `awake(&ppu)` call and the same `!g_pending && g_scheduler_ready`
  scheduler gate. It does not contain a ready title-specific repair for this
  boundary.
- Sources:
  `https://raw.githubusercontent.com/RPCS3/rpcs3/master/rpcs3/Emu/Cell/lv2/sys_event.cpp`,
  `https://raw.githubusercontent.com/RPCS3/rpcs3/master/rpcs3/Emu/Cell/lv2/lv2.cpp`,
  and
  `https://raw.githubusercontent.com/RPCS3/rpcs3/master/rpcs3/Emu/Cell/lv2/sys_sync.h`.
- Visual correctness: Invalid. The saved image shows the Android
  anti-image-retention pixel refresh, not the game or a loading screen. Its
  SHA-256 is
  `2228D977D1D1A30A5C4D0DBFCD8CBD62752E0DC5E3CB322723316757CF3BB0DE`.
- FPS/frame-time: No performance credit. The paused diagnostic reported 152
  frames in 88.25 seconds, or 1.72 FPS. This is not moving gameplay.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Thermal result: The fixed-silicon maximum was 67.8 C, and the CPU-junction
  maximum was 82.7 C. Six samples reached the 66 C early-hold range. No fixed
  silicon sample reached 70 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Property cleanup cleared all 61 listed properties and found
  zero remaining `debug.rpcsx.thor.*` values. The final fixed-silicon sample
  was 51.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-221340-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-221354-transformers-audio-queue-install`,
  and
  `debug-captures/android-speed-sprint/20260829-221421-thor-input-custom`.
- Decision: Repair only the proved deferred scheduler transition. Do not
  fabricate an audio event and do not release the game mutex.
- Next: Add a default-off property for the exact title and queue. Complete the
  selected worker wake only when the scheduler barrier and thread state match
  this capture.

## 160. Complete the deferred Transformers audio wake

- Status: HLE-repair, host-pass, unmeasured
- Scope: LV2 event queue, PPU scheduler, BLUS30357, config-driver
- Hypothesis: The FMOD worker will return and release its mutex if the exact
  audio send completes the scheduler transition that already selected it.
- Changed files/settings: The new Android property
  `debug.rpcsx.thor.transformers_audio_wake_fix` is off by default in the
  emulator. The HLE Transformers route enables it by default and clears it at
  the end. The repair can run only for title `BLUS30357`, event queue key
  `0x80004d494f323221`, a ready scheduler, a nonzero suspend barrier, and a
  target that is already in a running scheduler slot. The target must have
  `wait + suspend` and no `signal`.
- Repair: The helper completes the same target-state transition as the normal
  scheduler. It adds `signal`, removes `suspend`, removes applicable yield or
  preempt state, resets the start time, and notifies the target. It does not
  change the barrier count, select a different thread, fabricate an event, or
  release a game mutex.
- Tradeoff: The selected worker can run before another PPU thread acknowledges
  the global suspend barrier. The exact title, queue, property, slot, barrier,
  and state gates limit this behavior to the measured Transformers boundary.
- Rollback: Run the HLE route with `-FmodAudioWakeFix off`, or leave the
  property unset. Revert the helper and event-queue call to remove the repair.
- Android build result: The final
  `:app:assembleDebug --no-configuration-cache` build passed in 1 minute 8
  seconds with 42 tasks. The changed native code compiled and linked.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,153,475 bytes, and its SHA-256 is
  `D1B43D1E3AC969B5B545090A63A7BB254A879355CF91661D5BCD17E3FA24F0F3`.
- Verification: The focused HLE route contract, the three PowerShell parser
  checks, and `git diff --check` pass. The `Thor TWC AUDIO WAKE FIX` marker is
  present in the unstripped, merged, and stripped Android native libraries.
- Thor result: Not run. Experiment 159 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the narrow repair for one device decision run. It tests the
  direct cause that experiment 159 identified and has an explicit rollback.
- Next: In one later independently cool run, install this exact APK. Require a
  cold-start fixed-silicon sample below 70 C. Stop after the repair marker and
  a bounded post-marker window. Credit performance only if the result shows
  correct moving gameplay.

## 161. The event wake completes before the owner is suspended again

- Status: android-counterproof, owner-resuspend-identified, not-comparable
- Scope: HLE, FMOD, LV2 event queue, PPU scheduler, thermal-safety
- Hypothesis: The event-side helper will complete the deferred state transition
  and let the FMOD receive worker release the main-thread mutex.
- Installed artifact: The strict no-boot gate passed at 51.0 C fixed silicon.
  The no-launch installer then proved that the host and installed APK SHA-256
  values were both
  `D1B43D1E3AC969B5B545090A63A7BB254A879355CF91661D5BCD17E3FA24F0F3`.
  The RPCSX PID was absent before and after installation.
- Route: The HLE property readback included
  `debug.rpcsx.thor.transformers_audio_wake_fix=1`. The route requested 80
  half-second slices, a 600-second host limit, an arm on the event-side repair
  marker, and 12 later slices.
- Event result: The audio queue send selected FMOD PPU `0x0100000c` and changed
  its state from `0x224` to `0x304`. This is a normal scheduler transition from
  `wait + suspend + memory` to `wait + signal + memory`. `awake` returned true,
  and the event-side deferred helper correctly returned zero because no
  deferred suspend remained at that instant.
- Counterproof: The worker did not return to game address `0x00e2b454`. The main
  PPU thread entered its proved mutex sleep 9.101 milliseconds after the event
  transition. The queue stored two later audio events and then remained full.
  Later PPU samples again showed both the main thread and the FMOD worker in
  state `0x224`. The worker had consumed its signal and was suspended again
  before it could return and release the mutex.
- Route result: The event-side repair marker did not occur. The route reached
  its host deadline after 72 slices. Active windows totaled 52.612 seconds,
  and host time was 600.875 seconds. Every slice ended in a process hold.
- Visual correctness: Not measured. The marker did not occur, so the route did
  not save a boundary image.
- FPS/frame-time: No performance credit. Paused diagnostics fell from 128
  frames in 76 seconds to zero frames in the last 85-second interval. This is
  a stalled loading route, not moving gameplay.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Thermal result: The independent guard recorded 1,042 samples and 15 early
  holds. Fixed silicon peaked at 68.7 C, and CPU junction peaked at 82.7 C. No
  fixed-silicon sample reached 70 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup cleared all 62 listed properties and found zero
  remaining `debug.rpcsx.thor.*` values. The final fixed-silicon sample was
  54.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-224240-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-224305-transformers-audio-wake-fix-install`,
  and
  `debug-captures/android-speed-sprint/20260829-224334-thor-input-custom`.
- Decision: Keep the event-side helper for the previously measured deferred
  mode, but do not treat it as sufficient. Complete the owner wake after the
  main thread has entered the mutex sleep and released a scheduler slot.
- Next: Add one exact owner-handoff repair at the proved BLUS30357 caller. It
  must use the real mutex owner and must not release the mutex itself.

## 162. Complete the audio-owner wake after the main thread sleeps

- Status: HLE-repair, host-pass, unmeasured
- Scope: LV2 lightweight-mutex, PPU scheduler, BLUS30357
- Hypothesis: The FMOD worker can return if its wake is completed after the
  main PPU thread enters the exact mutex sleep and releases its scheduler slot.
- Changed files/settings: The existing default-off audio-wake property now also
  gates a repair at the exact main PPU, wrapper link register `0x00e28c5c`,
  saved caller `0x00dd6264`, and real lightweight-mutex owner. It resolves that
  owner through the PPU ID manager only after the main wait is queued.
- Repair: If the owner still has a deferred selected wake, the existing helper
  completes it. If the owner already has `wait + signal`, the repair sends a
  direct state notification. It logs the owner ID, state transition, returned
  deferred-barrier value, and notification result. It does not fabricate an
  event, change the mutex owner, signal the mutex, or release the mutex.
- Rollback: Run with `-FmodAudioWakeFix off`, or leave the Android property
  unset. Revert the owner-handoff helper call to remove this successor.
- Android build result: The first incremental build found one const bit-set
  accessor error. A local non-const snapshot corrected it. The final
  `:app:assembleDebug --no-configuration-cache` build passed in 1 minute 2
  seconds with 42 tasks.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,152,883 bytes, and its SHA-256 is
  `DB8E342445766828C0C50AA27D09E9BAD0B6574AE382DCE274BF026A7196CB08`.
- Verification: The focused HLE route contract and `git diff --check` pass.
  The `Thor TWC AUDIO OWNER WAKE` marker is present in the unstripped, merged,
  and stripped Android native libraries.
- Thor result: Not run. Experiment 161 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep this successor for one device decision run. It acts at the
  later state that experiment 161 proved and retains an explicit rollback.
- Next: In one later independently cool round, install this exact APK. Arm on
  `Thor TWC AUDIO OWNER WAKE`, keep a bounded post-arm window, and require an
  owner return or mutex handoff before any performance claim.

## 163. The generic owner wake rejects the zero-pending handoff

- Status: android-counterproof, post-wait-state-identified, not-comparable
- Scope: HLE, FMOD, LV2 lightweight-mutex, PPU scheduler, thermal-safety
- Hypothesis: The generic deferred-wake helper will complete the FMOD owner
  wake after the main PPU thread enters the exact mutex sleep.
- Installed artifact: The one-sample cold-start gate passed at 55.0 C fixed
  silicon. The no-launch installer proved that the host and installed APK
  SHA-256 values were both
  `DB8E342445766828C0C50AA27D09E9BAD0B6574AE382DCE274BF026A7196CB08`.
  The RPCSX PID was absent before and after installation.
- Route: The HLE route enabled the exact event, mutex, owner-wake, and PPU
  census controls. It requested 96 half-second slices with a 600-second host
  limit. It armed on `Thor TWC AUDIO OWNER WAKE` and collected 12 later
  slices.
- Counterproof: The exact handoff occurred at emulator time 5 minutes 51.738
  seconds. Main PPU `0x01000000` had saved caller `0x00dd6264` and slept on
  mutex `0x95008c00`, whose real owner was FMOD PPU `0x0100000c`. The owner
  state was `0x224`, or `wait + suspend + memory`. The generic helper returned
  zero and left the state at `0x224` because the global pending count was
  already zero. It sent no notification. The main thread stayed queued, the
  owner did not return, two audio events filled the queue, and later sends
  returned `CELL_EBUSY`.
- Route result: The post-arm route completed 54 slices in 447.734 host
  seconds. Active windows totaled 38.466 seconds. It armed at slice 42 and
  completed all 12 requested later slices.
- Visual correctness: The saved image is a real Transformers loading screen,
  not the Android pixel-refresh display. The loading symbol and overlay are
  visible, but no moving gameplay is proved. Its SHA-256 is
  `5E4D22910B592AC241D89B941C87AA43FE922843EB24C9DAA967BD3C147EE506`.
- FPS/frame-time: No performance credit. The saved overlay shows 25.88 FPS on
  the loading screen. A later paused diagnostic reports 97 frames in 83
  seconds, or 1.17 FPS. Neither value is correct moving gameplay.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Thermal result: The independent guard recorded 793 normal samples and eight
  early holds. Fixed silicon peaked at 69.9 C, and CPU junction peaked at
  84.7 C. No fixed-silicon sample reached 70 C. The slice controller recorded
  a 65.8 C maximum at its boundaries.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup cleared all 62 listed properties and found zero
  remaining `debug.rpcsx.thor.*` values. The final fixed-silicon and CPU-
  junction samples were 56.0 C and 54.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-230319-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-230340-transformers-audio-owner-wake-install`,
  and
  `debug-captures/android-speed-sprint/20260829-230405-thor-input-custom`.
- Decision: The generic selected-thread repair is the wrong gate at the later
  owner handoff. Keep it for the earlier event boundary, but use a separate
  exact post-wait owner wake for this measured priority inversion.
- Next: Wake only the real owner at this exact title, main PPU, wrapper, saved
  caller, and mutex handoff. Require `0x224 -> 0x304`, an owner return, and a
  mutex handoff before any speed claim.

## 164. Force the exact owner wake after the waiter leaves the schedule

- Status: HLE-repair, host-pass, unmeasured
- Scope: LV2 lightweight-mutex, PPU scheduler, BLUS30357
- Hypothesis: The FMOD owner can finish its delivered event and release the
  mutex if it receives the missing run signal after the main waiter leaves the
  schedule.
- Changed files/settings: The existing default-off audio-wake property still
  gates the exact BLUS30357 main PPU, wrapper link register `0x00e28c5c`, saved
  caller `0x00dd6264`, and real mutex owner. The call occurs only after the main
  wait is queued. A new scheduler helper requires a ready scheduler and owner
  state `wait + suspend` with no `signal`.
- Repair: The helper adds `signal`, removes `suspend` and applicable yield or
  preempt state, resets the owner start time, consumes a paired suspend
  acknowledgement if one exists, and notifies the owner. It does not depend on
  a nonzero global pending count or prior slot selection because experiment
  163 proved that both conditions have ended at this exact handoff.
- Tradeoff: This title-local repair can run the proved mutex owner outside the
  normal selected set after the main waiter releases a slot. The exact title,
  property, PPU, wrapper, saved caller, real-owner, timing, and state gates
  limit that behavior. It does not fabricate an event, change the mutex owner,
  signal the mutex, or release the mutex.
- Rollback: Run with `-FmodAudioWakeFix off`, or leave the Android property
  unset. Revert the post-wait helper and call to remove this successor.
- Android build result: `:app:assembleDebug` passed in 2 minutes 41 seconds
  with 42 tasks. The changed native code compiled and linked.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,153,584 bytes, and its SHA-256 is
  `5979BEC509A873C1EF387065E327903675AA1AFBCE73A537036F7A84C9B82682`.
- Native identity: The unstripped and merged core SHA-256 is
  `BDB05E8097C8505DE77EE1A5290B635B0F59B5AD6828FF7E44159F28C86DDD62`.
  The stripped and packaged core SHA-256 is
  `4C86DEBF01C8071B892A0C4E87D17B69435679EA0F8904CC9B745AEA6169FA49`.
- Verification: The focused HLE route, PPU PC, and load-wait contracts plus
  `git diff --check` pass.
  The `Thor TWC AUDIO OWNER WAKE` marker is present in the unstripped, merged,
  and stripped Android native libraries. The packaged core hash matches the
  stripped core.
- Thor result: Not run. Experiment 163 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep this successor for one device decision run. It tests the
  exact state and timing that experiment 163 proved and retains an explicit
  rollback.
- Next: In one later independently cool round, install this exact APK after a
  fixed-silicon cold sample below 70 C. Arm on an owner transition from `0x224`
  to `0x304`. Require the FMOD return, mutex handoff, correct moving gameplay,
  and a sustained 30 FPS result before performance credit.

## 165. Apply only the cold-start rule to the no-launch gate

- Status: controller-fix, host-pass, android-boundary-pass
- Scope: strict cold-start gate, thermal safety
- Problem: The strict no-launch gate took its required fixed-silicon sample at
  56.0 C, then applied the runtime near-limit guard at `post-run`. That guard
  uses 56 C as the start of a sustained-load probe. It rejected a cold device
  even though the cold-start rule permits every fixed-silicon value below
  70 C. The capture is
  `debug-captures/android-speed-sprint/20260829-232944-thor-input-strict-cool-gate`.
  It did not launch the emulator and it force-stopped the package.
- Change: The strict no-launch profile now ends after its one cold-start
  sample. Booted routes still use the runtime guard. Other no-boot routes keep
  the ordinary hard-limit check. This change does not weaken a booted run or
  change the 72 C hard limit.
- Verification: The strict-gate and multi-sensor thermal tests pass.
  `git diff --check` passes.
- Thor result: The corrected strict gate passed at 56.0 C. It used one
  fixed-silicon sample, did not launch the emulator, and force-stopped the
  package. The capture is
  `debug-captures/android-speed-sprint/20260829-233055-thor-input-strict-cool-gate`.
- Decision: Keep the correction. It implements the stated cold-start rule:
  a fixed-silicon value that is strictly below 70 C can run.

## 166. The exact audio-owner wake completes the mutex handoff

- Status: android-boundary-pass, next-mutex-stall-identified, not-comparable
- Scope: HLE, FMOD, LV2 lightweight mutex, PPU scheduler, thermal safety
- Hypothesis: The forced owner wake will let the FMOD event worker release the
  mutex that blocks the main PPU thread.
- Installed artifact: The no-launch installer proved that the host and device
  APK SHA-256 values were both
  `5979BEC509A873C1EF387065E327903675AA1AFBCE73A537036F7A84C9B82682`.
  The PID was absent before and after installation. The capture is
  `debug-captures/android-speed-sprint/20260829-233105-transformers-forced-audio-owner-wake-install`.
- Route: The fresh HLE process enabled the exact FMOD event, audio-queue,
  lightweight-mutex, owner-wake, and PPU census controls. It requested 120
  half-second slices, a 600-second host limit, an arm on the owner-wake row,
  and 40 later slices.
- Scheduler result: At emulator time 6 minutes 4.195603 seconds, the exact
  helper changed FMOD PPU `0x0100000c` from `0x224` to `0x304` and reported
  `forced=1`. In the next 0.118 milliseconds, the owner entered the unlock and
  handed mutex `0x95008c00` to main PPU `0x01000000`. The main PPU returned
  from the lock at 6 minutes 4.195915 seconds. It released the mutex back to
  the FMOD worker 6.452 milliseconds later. This is the required full mutex
  handoff, not only a scheduler-state change.
- Audio result: The FMOD worker returned to the event receive path and consumed
  one stored audio event. This proves that the original audio-owner deadlock is
  fixed. The small queue could still fill while the diagnostic route paused
  the process between execution slices.
- Next boundary: Later PPU samples at 6 minutes 21 seconds, 7 minutes 44
  seconds, and 9 minutes 9 seconds show the main PPU in the same generic FMOD
  lock wrapper with state `0x224`, but at stack pointer `0xd003fa40` instead of
  `0xd003fc30`. The first mutex trace had completed and was pinned to its first
  ID. It recorded no second entry. Therefore, the later wait is a different
  lightweight mutex and its caller and owner are not yet proved.
- Route result: The route completed 65 slices and 47.518 active seconds. It
  armed at slice 43 and completed 22 later slices. Host time was 653.781
  seconds because the final paused cooldown timed out while the fixed-silicon
  value remained exactly 60.0 C. The late-load marker did not occur.
- Visual correctness: Not measured. The incomplete post-arm window did not
  save a boundary image. No correct moving gameplay is proved.
- FPS/frame-time: No performance credit.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Thermal result: The controller maximum was 65.8 C fixed silicon. The device
  guard recorded 1,161 normal samples and 18 early holds. Its fixed-silicon
  maximum was 69.1 C and its CPU-junction maximum was 82.7 C. No fixed-silicon
  sample reached 70 C, and no junction sample reached 95 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup cleared all 62 listed properties and found zero
  remaining `debug.rpcsx.thor.*` values. The final fixed-silicon sample was
  60.0 C.
- Capture path:
  `debug-captures/android-speed-sprint/20260829-233128-thor-input-custom`.
- Decision: Keep the exact first-mutex repair. Do not extend the wake to a new
  mutex until its caller, real owner, and owner state are measured.
- Next: Record the first non-matching main-thread FMOD mutex sleep after the
  proved repair. Include its mutex ID, saved caller, real owner, and owner
  state. Use that row to select the next HLE repair or reject it.

## 167. Trace the next post-repair FMOD mutex owner

- Status: instrumentation, host-pass, unmeasured
- Scope: BLUS30357, LV2 lightweight mutex, FMOD, config contract
- Hypothesis: The first non-matching main-thread FMOD mutex sleep after the
  proved owner wake will identify the caller and owner of the next HLE stall.
- Change: After the exact `0x00dd6264` owner wake succeeds once, the same
  default-off, title-scoped property can record up to 64 later main-thread
  sleeps in the generic FMOD lock wrapper. Each candidate row includes the
  saved caller, mutex ID, real owner, owner state, and control address. The
  candidate path returns without changing a thread state, mutex, event, or
  scheduler value.
- Rollback: Run with `-FmodAudioWakeFix off`, leave the Android property unset,
  or revert the candidate log.
- Android build result: `:app:assembleDebug --no-configuration-cache` passed
  in 1 minute 10 seconds with 42 tasks. The modified native file compiled and
  linked.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,156,098 bytes, and its SHA-256 is
  `DFD93D983230EFE48057DCFAC37193C6B33639EE6157C57BBD702F4811F40505`.
- Native identity: The unstripped and merged core SHA-256 is
  `0D324DCDE77D6AA373CF84150ADA79A389BA0BBA6436D78714FC435D2B0F3F6F`.
  The stripped core SHA-256 is
  `3A2FD826A1FD0F3F33AF7654EBFC01A784C7379F44C04A9E96ED452BBF0A7B26`.
- Verification: The focused HLE route, PPU PC, load-wait, strict cold-gate,
  and multi-sensor thermal contracts pass. `git diff --check` passes. The
  `Thor TWC AUDIO OWNER CANDIDATE` marker is present in the unstripped,
  merged, and stripped Android native libraries.
- Thor result: Not run. Experiment 166 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the bounded diagnostic for one later device decision run.
- Next: After a new strict cold-start sample below 70 C, install this exact
  APK. Arm on `Thor TWC AUDIO OWNER CANDIDATE` and stop after a short bounded
  window. Do not wake the candidate until its identity and state are proved.

## 168. The exact 60 C resume boundary blocks the candidate run

- Status: controller-counterproof, android-no-result, not-comparable
- Scope: paused slice controller, thermal safety, HLE candidate trace
- Installed artifact: The strict cold-start gate passed at 60.0 C. The
  no-launch installer proved that the host and device APK SHA-256 values were
  both
  `DFD93D983230EFE48057DCFAC37193C6B33639EE6157C57BBD702F4811F40505`.
  The PID was absent after installation.
- Route result: The route completed only its first 0.657-second slice. It then
  waited 120 seconds for three readings that were strictly below 60 C. Fixed
  silicon stayed at 60.0 or 61.0 C, so the cooldown timed out. The route did
  not reach the first owner wake or the candidate marker.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup cleared all 62 properties and found zero remaining
  `debug.rpcsx.thor.*` values. The final fixed-silicon sample was 61.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-235032-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-235040-transformers-next-audio-owner-candidate-install`,
  and
  `debug-captures/android-speed-sprint/20260829-235101-thor-input-custom`.
- Decision: Do not interpret this run as an HLE result. Correct the exact
  resume-target comparison and keep all runtime upper limits.

## 169. Permit the exact paused-slice resume target

- Status: controller-fix, host-pass, unmeasured
- Scope: local Thor controller, thermal documentation, host contracts
- Problem: `t_wait_cool_paused` required `silicon < target`. The route and its
  report call 60 C the resume target, but a stable value of exactly 60.0 C
  could never satisfy that target. This caused experiment 168 to stop after
  one safe slice.
- Change: A paused process can now resume after the required number of
  consecutive fixed-silicon readings at or below the configured resume
  target. The default remains three samples at 60 C with one second between
  samples. The 66 C device-watchdog hold and the 72 C hard stop do not change.
- Verification: The guarded slice test now proves that three exact 60.0 C
  samples pass in two seconds. The fixed-silicon, strict cold-gate, and
  multi-sensor thermal contracts pass. `git diff --check` passes.
- Thor result: Not run. Experiment 168 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the inclusive target. A target is an allowed boundary, not a
  forbidden value.
- Next: In a new independently cool round, reuse the exact experiment 167 APK.
  Arm on the first owner-candidate row and keep the eight-slice post-marker
  limit.

## 170. The fixed-silicon floor remains above the old resume target

- Status: controller-counterproof, android-no-result, not-comparable
- Scope: paused slice controller, thermal safety, HLE candidate trace
- Cold gate: A new one-sample gate passed at 61.0 C, which is below the 70 C
  launch limit. The exact experiment 167 APK was installed with no launch and
  no remaining PID.
- Route result: The inclusive comparison worked, but fixed silicon stayed at
  61.0 or 62.0 C while the package was held. The route completed one
  0.703-second slice, then reached the 120-second cooldown timeout. It did not
  reach the first owner wake or candidate marker.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Stability: The log contains no fatal error, access violation, out-of-memory
  error, or assertion failure.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup cleared all 62 properties and found zero remaining
  `debug.rpcsx.thor.*` values. The final fixed-silicon sample was 62.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260829-235810-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260829-235819-transformers-next-owner-candidate-retry-install`,
  and
  `debug-captures/android-speed-sprint/20260829-235834-thor-input-custom`.
- Decision: The old 60 C inter-slice target cannot work when the fixed SoC
  sensor has a stable 61-62 C floor. Do not treat the result as HLE evidence.

## 171. Raise the Transformers slice resume target to 65 C

- Status: controller-fix, host-pass, unmeasured
- Scope: Transformers HLE route, thermal documentation, route contract
- Change: The Transformers paused-slice route now requires three consecutive
  fixed-silicon readings at or below 65 C before a later slice. The device
  watchdog still holds the package at 66 C. The hard stop remains 72 C.
- Safety: A later slice lasts 0.5 seconds. The 65 C resume target leaves one
  degree before the independent hold and seven degrees before the hard stop.
  The device watchdog continues to sample every 0.25 seconds. The cold-start
  launch rule remains strictly below 70 C.
- Verification: The focused HLE route, guarded-slice logic, and fixed-silicon
  contracts pass. `git diff --check` passes.
- Thor result: Not run. Experiment 170 used the one allowed launch for this
  independently cool hardware round.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Decision: Keep the 65 C target for the bounded Transformers route. It is
  below every runtime stop and above the measured idle sensor floor.
- Next: In a new independently cool round, reuse the exact experiment 167 APK
  and stop on the first owner-candidate row plus eight later slices.

## 172. The repaired HLE route reaches an RSX dead FIFO

- Status: blocker-found, android-pass-to-new-fatal, not-comparable
- Scope: BLUS30357, HLE SPURS, audio-owner repair, RSX FIFO
- Cold gate and install: A new one-sample gate passed below 70 C. The
  no-launch installer proved the experiment 167 APK SHA-256 on the host and
  device. No PID remained after installation.
- Route result: The controller completed 70 slices, 52.827 seconds of active
  time, and 601.312 seconds of host time. The first audio-owner wake completed
  the main-thread and FMOD mutex handoff. The game then created its PPU PhysX
  thread and reached more title work. No later generic FMOD mutex candidate
  occurred, so that candidate is not the next blocker.
- New blocker: At emulated time 7:56.455, the RSX thread stopped with `Dead
  FIFO commands queue state has been detected`. The active settings were `RSX
  FIFO Accuracy: Atomic`, `Driver Wake-Up Delay: 0`, and `Stub PPU Traps: 0`.
  This is not a result after an SPU trap. The fatal message recommends `Ordered
  & Atomic` or a larger driver wake-up delay.
- Source and upstream check: The local RPCSX recovery code matches the current
  RPCS3 recovery logic. A current RPCS3 report also finds `Ordered & Atomic`
  more stable for a dead FIFO, but it does not prove a general fix:
  <https://github.com/RPCS3/rpcs3/issues/19003>.
- Visual correctness: Not measured. The route had no armed boundary image,
  and the RSX thread stopped. No correct moving gameplay is proved.
- FPS/frame-time: No performance credit.
- Thermal result: The route controller maximum was 66.2 C fixed silicon. The
  device guard recorded 1,044 normal samples and 27 early holds. Its
  fixed-silicon maximum was 69.5 C and its CPU-junction maximum was 86.3 C.
  No fixed-silicon sample reached 70 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup found zero remaining `debug.rpcsx.thor.*` values. The
  final fixed-silicon sample was 65.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-000459-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-000507-transformers-next-owner-candidate-65c-install`,
  and
  `debug-captures/android-speed-sprint/20260830-000522-thor-input-custom`.
- Decision: Keep the proved audio-owner repair. Replace the obsolete next-owner
  experiment with a title-scoped `Ordered & Atomic` FIFO decision run. Do not
  suppress the fatal error.

## 173. Use ordered FIFO for the Transformers HLE route

- Status: host-pass, device-pending
- Scope: BLUS30357, Android property route, RSX FIFO configuration
- Hypothesis: `Ordered & Atomic` can keep the RSX consumer ordered after the
  repaired HLE path reaches PhysX and submits more work.
- Change: The HLE render route now sets
  `debug.rpcsx.thor.transformers_fifo_ordered=1` by default. The core accepts
  it only for BLUS30357 and selects the canonical `Ordered & Atomic` setting
  before RSX starts. LLE sets zero. `-RsxFifoOrdered off`, an unset property,
  or another title keeps its configured FIFO mode. Cleanup clears the property.
- Verification: The focused HLE route, PPU PC, load-wait, strict cold-gate,
  and multi-sensor thermal contracts pass. `git diff --check` passes. The
  Android build completed in 1 minute 36 seconds with 42 tasks. The property
  and result marker are present in the unstripped, merged, and stripped native
  libraries.
- Artifact: The APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,152,126 bytes, and its SHA-256 is
  `89F08AF1E455F98A3B94A711FA8413B5D83F70ED97E4042FF75B6DA93E1DD332`.
- Native identity: The unstripped and merged core size is 1,306,922,096 bytes,
  and its SHA-256 is
  `19958430C9B9949D38EE3C1E24A5CF08734EA9A31ED103A1225B7DE1A04B1C13`.
  The stripped core size is 63,237,304 bytes, and its SHA-256 is
  `53D0CB4145DB597AC469800B0AA81622BF2C4A03AC04855D0113E116A6AE72A0`.
- Thor result: Not run yet.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Next: Commit the exact host result. In a new cool hardware round, prove the
  property readback, the effective FIFO mode, survival past emulated time
  7:56, and a boundary image after the audio-owner repair.

## 174. The 65 C resume target blocks the ordered-FIFO proof

- Status: controller-counterproof, android-no-result, not-comparable
- Scope: paused slice controller, ordered-FIFO decision run, thermal safety
- Cold gate and install: A new strict gate passed at 65.0 C. The no-launch
  installer proved the expected, host, and device APK SHA-256 as
  `89F08AF1E455F98A3B94A711FA8413B5D83F70ED97E4042FF75B6DA93E1DD332`.
  No PID remained after installation.
- Configuration proof: Both property readbacks reported
  `debug.rpcsx.thor.transformers_fifo_ordered=1`. The core reported
  `Transformers RSX FIFO accuracy forced to Ordered & Atomic`, and the
  effective configuration reported `RSX FIFO Accuracy: "Ordered & Atomic"`.
- Route result: The controller completed 25 slices and 18.560 seconds of
  active time. It reached emulated time 3:28. It then used the full 120-second
  cooldown while the fixed SoC sensor stayed at 66 C. The route stopped before
  the audio-owner wake, PhysX creation, or the prior dead-FIFO time.
- Visual correctness: Not measured. The arm marker did not occur, so the route
  did not save a boundary image.
- FPS/frame-time: No performance credit.
- Stability: No dead FIFO, fatal error, access violation, out-of-memory error,
  or assertion occurred before the controller stopped the run. This does not
  prove ordered-FIFO stability because the route did not reach the old fault.
- Thermal result: The controller maximum was 66.0 C fixed silicon. The device
  guard recorded 805 normal samples and one early hold. Its fixed-silicon
  maximum was 67.4 C and its CPU-junction maximum was 81.5 C. No fixed-silicon
  sample reached 70 C.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup found zero remaining `debug.rpcsx.thor.*` values. The
  final fixed-silicon sample was 66.0 C.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-002721-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-002734-transformers-ordered-fifo-install`,
  and
  `debug-captures/android-speed-sprint/20260830-002801-thor-input-custom`.
- Decision: Do not accept or reject ordered FIFO from this run. Raise the
  controller resume target, but keep the independent device watchdog and the
  72 C hard stop.

## 175. Raise the Transformers slice resume target to 68 C

- Status: controller-fix, host-pass, unmeasured
- Scope: Transformers HLE route, thermal documentation, route contract
- Change: The Transformers paused-slice controller now requires three stable
  fixed-silicon readings at or below 68 C. This permits a later slice when the
  fixed SoC sensor has a stable 66 C floor. The independent device watchdog
  still holds the app at 66 C, and the hard stop remains 72 C.
- Safety: The target remains below the exclusive 70 C launch limit. The
  independent watchdog continues to sample every 0.25 seconds. A new hardware
  run still requires a new strict fixed-silicon sample below 70 C.
- Rollback: Change the route target back to 65 C. No APK or core change is
  required.
- Thor result: Not run yet.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Next: Run the exact experiment 173 APK after a new strict gate. Arm on the
  repaired audio-owner marker and keep 20 later slices for the old dead-FIFO
  boundary and screenshot.

## 176. The instrumented 68 C route reaches the hard limit first

- Status: thermal-stop, android-no-result, not-comparable
- Scope: paused slice controller, ordered-FIFO decision run, thermal safety
- Cold gate and install: A new strict gate passed at 67.0 C. The no-launch
  installer again proved the exact experiment 173 APK and left no PID.
- Route result: The controller completed 28 slices and 20.687 seconds of active
  time. It advanced to emulated time 4:07, which is later than experiment 174.
  The fixed SoC sensor then rose from 69 C to 72 C while the process was held.
  The controller force-stopped the package at its 72 C hard limit. It did not
  reach the audio-owner wake or the old dead-FIFO time.
- Configuration proof: The ordered-FIFO property and effective configuration
  were correct. No dead FIFO or other fatal error occurred before the thermal
  stop. This does not prove ordered-FIFO stability.
- Visual correctness: Not measured. The arm marker did not occur.
- FPS/frame-time: No performance credit.
- Thermal result: The slice controller maximum was 72.0 C fixed silicon. Its
  hard limit stopped the run. The independent device guard uses the CPU
  subsystem sensor and recorded 698 normal samples, one early hold, a 67.4 C
  fixed-silicon maximum, and an 83.9 C CPU-junction maximum.
- Rollback: The verified stop found no PID, zero RPCSX rows in `top`, and
  `quiet=true`. Cleanup found zero remaining `debug.rpcsx.thor.*` values.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-003805-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-003815-transformers-ordered-fifo-68c-install`,
  and
  `debug-captures/android-speed-sprint/20260830-003830-thor-input-custom`.
- Decision: Keep the 68 C controller target. Remove the no-longer-needed FMOD
  event trace, lightweight-mutex trace, local-store dump, and PPU PC census
  from the next decision run. The audio-owner repair still emits its exact
  marker without those probes. This reduces work and gives ordered FIFO a
  cleaner speed and thermal test.

## 177. Remove battery state of charge from the thermal gate

- Status: controller-fix, host-pass, device-evidence
- Scope: strict cold gate, paused-slice controller, device watchdog, sensor
  classification
- Problem: `thermal_zone82` has type `socd` and reports a bare state value.
  The generic classifier matched `soc` in its name and treated this state as
  Celsius. It therefore held or stopped the emulator when the state reached
  70 or 72, even though the real CPU, GPU, DDR, and XO temperature sensors were
  near 35-36 C.
- Device evidence: After experiment 176 stopped, `socd` stayed at the bare
  value 72 while `cpuss-*`, `gpuss-*`, DDR, and XO reported 34.6-36.5 C in
  millidegrees. No emulator PID was present.
- Source evidence: Qualcomm's kernel documentation defines
  `qcom,msm-bcl-soc` as a battery state-of-charge driver. Its driver registers
  the value as a thermal-framework sensor and reads a battery capacity value.
  It is not a SoC die temperature:
  <https://android.googlesource.com/kernel/msm/+/85a10b57b5c50f68a9592cbc9ba9d115a78b0342%5E2..85a10b57b5c50f68a9592cbc9ba9d115a78b0342/>.
- Change: The PowerShell classifier now assigns `socd` to the non-guarded
  `other` domain. The local slice controller and on-device watchdog omit it
  from the fixed-silicon set. The watchdog now requires the 14 real fixed
  temperature zones instead of 15 entries.
- Safety: The change does not remove a temperature guard. CPU subsystem, GPU
  subsystem, DDR, XO, battery temperature, skin temperature, and all 14 CPU
  junction sensors remain guarded. The exclusive 70 C launch rule and 72 C
  hard fixed-silicon limit do not change.
- Verification: The multi-sensor thermal, on-device watchdog, local controller,
  guarded-slice logic, strict cold-gate, and focused Transformers HLE contracts
  pass. `git diff --check` passes.
- Rollback: Restore `socd` to the fixed-silicon lists and remove its explicit
  non-temperature classification.
- Thor result: Not run yet.
- FPS/frame-time: No performance credit.
- Next: Run all focused thermal contracts. Then take a new strict sample and
  run the exact experiment 173 APK with the diagnostic probes disabled.

## 178. The clean ordered route reaches a guest GCM heap assertion

- Status: new-blocker, android-guest-exit, not-comparable
- Scope: BLUS30357, HLE SPURS, ordered RSX FIFO, low-instrumentation route
- Cold gate and install: The corrected strict gate passed at 35.7 C across 14
  real fixed-temperature sensors. It recorded `socd=72` only in the `other`
  domain. The no-launch installer proved the exact experiment 173 APK and left
  no PID.
- Route configuration: Ordered FIFO was on. FMOD event trace, lightweight-
  mutex trace, SPU local-store dump, SPU PC census, runtime census, and PPU PC
  census were off. Both property readbacks and the effective FIFO configuration
  were correct.
- Route result: The controller completed 21 slices and 15.156 seconds of active
  time. At emulated time 3:01.515, the title's FlipPump thread reported
  `gcmx_cmd.h:55 GCMXIsHeapBlockAllocated(Block) -- assertion failed`. The
  guest abort stack started at `0x01022ea4`, then included `0x00fde064`,
  `0x00fe48d8`, `0x00fdd968`, `0x00fde384`, `0x009e05b0`, and `0x009f265c`.
  The guest requested process exit with status 1.
- Fatal classification: The later `Verification failed (object: 0x0)` at
  `cellSpurs.cpp:910` occurred while the HLE SPURS handler was unwinding the
  stopped process. It is shutdown fallout. The title's GCM heap assertion is
  the initiating fault.
- Visual correctness: Not measured. The audio-owner arm marker did not occur.
- FPS/frame-time: No performance credit.
- Thermal result: The slice-controller maximum was 61.4 C fixed silicon. The
  device guard recorded 317 normal samples, no holds, a 64.6 C fixed-silicon
  maximum, and an 81.1 C CPU-junction maximum. No fixed-silicon sample reached
  70 C.
- Rollback: The title exited on its own. The verified stop found no PID, zero
  RPCSX rows in `top`, and `quiet=true`. Cleanup found zero remaining
  `debug.rpcsx.thor.*` values.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-005425-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-005439-transformers-ordered-fifo-clean-install`,
  and
  `debug-captures/android-speed-sprint/20260830-005458-thor-input-custom`.
- Decision: Do not keep ordered FIFO as an HLE default yet. Run the same clean
  route with `-RsxFifoOrdered off`. If Atomic survives this exact boundary,
  ordered FIFO causes the guest heap-lifetime assertion. If Atomic also fails,
  the new blocker is independent of FIFO mode.

## 179. The Atomic control rejects ordered FIFO and exposes a later stall

- Status: controller-proof, ordered-rejected, new-stall, not-comparable
- Scope: BLUS30357, HLE SPURS, Atomic RSX FIFO, low-instrumentation route
- Cold gate and install: A new strict gate passed at 43.3 C. The no-launch
  installer proved APK SHA-256
  `89F08AF1E455F98A3B94A711FA8413B5D83F70ED97E4042FF75B6DA93E1DD332`
  on the host and device. No PID remained after installation.
- Route configuration: `debug.rpcsx.thor.transformers_fifo_ordered=0`, and the
  effective configuration reported `RSX FIFO Accuracy: Atomic`. FMOD event
  trace, lightweight-mutex trace, SPU local-store dump, SPU PC census, runtime
  census, and PPU PC census were off. This changed only the FIFO arm from
  experiment 178.
- Route result: The controller completed 70 slices and 52.764 seconds of active
  time across 598.672 host seconds. The process remained alive through
  emulated time 9:23 and reached the host deadline. It passed the ordered
  arm's 3:01.515 assertion boundary. It reported no GCM heap assertion, dead
  FIFO, fatal error, or verification failure.
- A/B decision: Atomic passed the exact boundary where ordered FIFO aborted.
  Ordered FIFO therefore caused the observed guest GCM heap-lifetime
  assertion. The Transformers HLE route now defaults to Atomic again. The
  ordered property remains as an explicit diagnostic switch.
- New blocker: The frame counter advanced through emulated time 6:31 and then
  stopped. It reported zero frames for the intervals ending at 7:57 and 9:23.
  The final thread snapshot showed the PPU, SPU, and RSX threads stopped by the
  slice controller, so it cannot identify the guest wait. The last meaningful
  work included FMOD task creation, rendering-taskset shutdown and join, and
  later SPU kernel resumes. A PPU PC census is required to identify the live
  wait before another fix.
- Visual correctness: Not measured. The audio-owner arm marker did not occur,
  so the controller did not save a boundary image.
- FPS/frame-time: No performance credit. Paused-slice frame counters are not a
  continuous gameplay measurement, and the route stopped producing frames.
- Thermal result: The slice-controller maximum was 65.8 C fixed silicon. The
  device watchdog recorded no hold or stop action and completed when the
  package stopped. No fixed-silicon sample reached 70 C.
- Rollback: The host deadline stopped the package. The verified stop found no
  PID, zero RPCSX rows in `top`, and `quiet=true`. Cleanup cleared 63 properties
  and found zero remaining `debug.rpcsx.thor.*` values.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-010016-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-010026-transformers-atomic-clean-control-install`,
  and
  `debug-captures/android-speed-sprint/20260830-010043-thor-input-custom`.
- Next: Keep Atomic. Run one bounded, independently cool PPU PC census with the
  other heavy probes off. Stop after the frame counter has been flat long
  enough to capture the blocked PPU program counters. Map the dominant guest
  PC in Ghidra before changing HLE synchronization again.

## 180. The first Atomic PPU census stops before the zero-frame phase

- Status: diagnostic-boundary, android-clean, not-comparable
- Scope: BLUS30357, HLE SPURS, Atomic RSX FIFO, PPU PC census
- Cold gate: A new strict gate passed at 41.7 C across the 14 fixed-temperature
  sensors. It recorded `socd=92` only in the non-temperature domain.
- Route configuration: Atomic FIFO and the PPU PC census were on. Runtime
  census, SPU PC census, FMOD event trace, and lightweight-mutex trace were
  off. The installed APK matched SHA-256
  `89F08AF1E455F98A3B94A711FA8413B5D83F70ED97E4042FF75B6DA93E1DD332`.
- Route result: The controller completed 42 slices and 35.968 seconds of active
  time across 501.094 host seconds. At emulated time 3:46 the main thread was
  in the known loader sleep at `0x009e4ba4`, with return address `0x005a3350`.
  At 6:08 it was executing at `0x00553b64`, with return address `0x013d80c0`.
  The frame counter still advanced in that interval. The run therefore ended
  before the prior control's first confirmed zero-frame interval at 7:57.
- Ghidra result: The existing decrypted BLUS30357 EBOOT project maps
  `0x00553b64` to a small object-table lookup. It reads an eight-bit table index
  from object offset `0x18`, then returns a 32-bit pointer from the table at
  `0x01e23fc4`. The return address follows a call at `0x013d80bc` inside an
  object comparator. This is normal transient work, not a wait loop.
- Rendering thread: At 6:08 it was in the generic sleep wrapper, returning to
  `0x009e0524`. Ghidra maps that caller to a loop which runs
  `0x009e02d4`, waits, and retries while the return value is nonzero. This is a
  useful secondary address, but the route had not reached the flat-frame phase.
- Stability: No dead FIFO, GCM heap assertion, fatal error, or verification
  failure occurred. The process stayed alive to the host deadline.
- Visual correctness: Not measured. No boundary image was saved.
- FPS/frame-time: No performance credit. This was a paused diagnostic route,
  and it did not reach gameplay.
- Thermal result: The slice-controller maximum was 64.2 C. The device watchdog
  maximum was 67.4 C. It recorded no hold or stop action and completed when the
  package stopped. No fixed-silicon sample reached 70 C.
- Rollback: The host deadline stopped the package. The verified stop found no
  PID, zero RPCSX rows in `top`, and `quiet=true`. Cleanup cleared 63 properties
  and found zero remaining `debug.rpcsx.thor.*` values.
- Evidence:
  `debug-captures/android-speed-sprint/20260830-011619-thor-input-strict-cool-gate`,
  `debug-captures/android-speed-sprint/20260830-011644-thor-input-custom`,
  `debug-captures/ghidra-transformers-ppu-20260828-224900/BLUS30357-late-main-00553b64.txt`,
  and
  `debug-captures/ghidra-transformers-ppu-20260828-224900/BLUS30357-late-main-callsite-013d80bc.txt`.
- Instrumentation change: The PPU census now records a bounded stack for each
  new main-thread PC and LR pair, up to eight pairs. The old one-shot stack was
  consumed during the initial loader sleep and could not describe a later
  phase. The property remains default off.
- Verification: The focused PPU PC and HLE route contracts pass. The ARM64
  RelWithDebInfo native build passed in 1 minute 50 seconds. The final
  `:app:assembleDebug --no-configuration-cache` build passed in 17 seconds with
  42 tasks. The ARM64 APK contract and `git diff --check` pass.
- Host artifact: The new, uninstalled APK is
  `app/build/outputs/apk/debug/rpcsx-thor-experiment-debug.apk`. Its size is
  116,153,271 bytes, and its SHA-256 is
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  The merged core is 1,306,923,600 bytes with SHA-256
  `F546B9399AB9CDFE431C2FB44556247A9461A7A72D6ACFFC063FD9AB8E1B904D`.
  The stripped core is 63,237,368 bytes with SHA-256
  `EA7EAC2949BBAC213D7312AD55564E548BB780B9840EC6CC81382318F89F9E42`.
  This artifact has no device, stability, visual, or performance credit.
- Next: In a later independently cool round, install this exact APK without
  launching. Then,
  after a separate new strict gate, keep Atomic and run through at least the
  first confirmed zero-frame interval. Use the final PC and stack for the next
  HLE change.

## 181. Install the bounded PPU stack census without a launch

- Status: installed-exact-no-launch, route-tooling, unmeasured
- Scope: BLUS30357 diagnostic APK, exact identity, thermal gate
- Cold gate: A new strict gate passed at 36.1 C across 14 fixed-temperature
  sensors. The battery was 24.0 C, and the skin sensor was 30.0 C.
- Install result: The no-launch installer proved expected, host, and device APK
  SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  The package PID was absent before and after installation. The emulator did
  not launch.
- Thermal result: The post-install fixed-silicon value was 36.9 C. Installation
  did not spend a runtime thermal window.
- Visual correctness: Not measured.
- FPS/frame-time: No performance credit.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-014023-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-014037-transformers-multistack-ppu-install`.
- Next: Do not launch in this install round. After a separate new strict gate,
  run Atomic with the PPU PC census through the first confirmed zero-frame
  interval. Map the final main-thread PC and stack before changing HLE code.

## 182. The late Atomic route is progressing, not deadlocked

- Status: progress-proof, controller-counterproof, not-comparable
- Scope: BLUS30357, HLE SPURS, Atomic RSX FIFO, bounded PPU stacks
- Cold gate and identity: A separate strict gate passed at 36.9 C. The route
  proved the installed APK SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  Atomic FIFO and PPU PC census were on. The other heavy probes were off.
- Route result: The controller completed 33 slices across 606.359 host seconds.
  It reached emulated time 10:38. The frame counter advanced by 66 frames from
  8:18 through 10:28. Zero-frame ten-second samples alternated with nonzero
  samples up to 12 frames. The main thread changed PC and stack throughout the
  window. `FlipPump` continued to push its queue and reached signal sample
  1,792. The title was therefore progressing and was not in the previously
  reported dead stall.
- Correction: Experiment 179 called two long zero-frame samples a stall. The
  paused-slice controller made those samples non-continuous, and this longer
  census disproves the stall classification. Treat them only as missing work
  during held windows. Do not design an HLE wake fix from them.
- PPU result: The bounded census captured eight distinct main-thread PC and LR
  pairs between 7:28 and 9:38. No pair dominated. The samples included LV2,
  the known `0x00fdcf60` polling function, memory allocation and free paths,
  file-system work, and module loading. This is active initialization, not one
  blocked wait.
- Controller limitation: The first 21 process-held slices report 22.969 active
  seconds. The later emulator-held slices omit `activeElapsedS`, so the total
  active time is not exact. The 66 frames and logged FPS values are invalid for
  speed credit. The pauses also explain why a zero-frame wall-time sample does
  not prove a guest stall.
- Stability: No dead FIFO, GCM heap assertion, fatal error, or verification
  failure occurred. Atomic remained alive to the host deadline.
- Visual correctness: Not measured. The controller did not save a boundary
  image because the explicit never-match marker did not occur.
- FPS/frame-time: No performance credit. This was a paused diagnostic route.
- Thermal result: The slice controller and device watchdog both reached a
  43.7 C fixed-silicon maximum. The watchdog junction maximum was 45.3 C. It
  recorded no hold or stop action and completed when the package stopped. No
  fixed-silicon sample reached 70 C.
- Rollback: The host deadline stopped the package. The verified stop found no
  PID, zero RPCSX rows in `top`, and `quiet=true`. Cleanup cleared 63 properties
  and found zero remaining `debug.rpcsx.thor.*` values.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-014132-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-014155-thor-input-custom`.
- Decision: Keep Atomic and the audio-owner repair. Stop treating this boundary
  as an HLE deadlock. The next round must use a guarded continuous route with a
  screenshot. It must first identify the visible scene, then measure continuous
  frame presentation. A paused route cannot answer the speed question.

## 183. The continuous Atomic route reaches active title initialization

- Status: visual-boundary, android-clean, not-comparable
- Scope: BLUS30357, HLE SPURS, Atomic RSX FIFO, continuous unpaused boot
- Cold gate and identity: A separate strict gate passed at 36.9 C. The route
  proved the installed APK SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  Atomic FIFO was on. PPU PC census, runtime census, SPU PC census, FMOD event
  trace, and lightweight-mutex trace were off.
- Route result: The title ran continuously. The first image at 15 seconds
  showed `Analyzing PPU Executable`. The second image at 30 seconds showed
  `Applying PPU Code` at module 225 of 225. The log then showed normal title
  initialization, file access, module loads, and FlipPump work. This is not an
  HLE stall.
- PPU cache result: The log reported `Reusing 225 validated warm-cache
  objects`. The remaining visible delay is analysis and link or apply work. It
  is not a cold PPU compile miss.
- Frame result: Later ten-second log samples reported 3.9, 2.2, 10.2, 10.3,
  and 8.1 FPS. These values do not have performance credit because both saved
  images still showed the PPU compilation overlay. The correct game scene was
  not visible.
- Stability: No dead FIFO, GCM heap assertion, fatal error, verification
  failure, or process restart occurred.
- Thermal result: The device watchdog recorded 27 normal samples. Fixed
  silicon reached 42.9 C, and CPU junction reached 45.3 C. It recorded no hold
  or thermal stop action.
- Rollback: The macro stopped the package. The verified post-run state had no
  PID and no RPCSX thread row. The package stop completed normally.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-015736-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-015755-thor-input-custom`.
- Decision: Keep Atomic HLE. In the next independently cool round, use
  `gate:ppu-ready` before the first image. Do not measure speed until an image
  proves that the compilation overlay is absent.

## 184. HLE renders the correct Transformers startup sequence

- Status: visual-progress, gate-mismatch, android-clean, not-comparable
- Scope: BLUS30357, HLE SPURS, Atomic RSX FIFO, continuous unpaused boot
- Cold gate and identity: A separate strict gate passed at 37.3 C. The route
  proved the installed APK SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  Atomic FIFO was on, and the heavy probes were off.
- Visual result: The readiness sampler captured correct Unreal and PhysX legal
  screens. It then captured the animated Transformers loading screen. The PPU
  compilation overlay was absent from these images. This is the first
  continuous visual proof that the current HLE repair stack advances through
  normal Transformers startup.
- Gate result: `gate:ppu-ready` timed out after 150 seconds because its
  implementation requires the Eternal Sonata title selector in two images.
  That recognition rule cannot pass on Transformers. The timeout is a route
  mismatch, not an HLE failure.
- Frame result: The final three complete ten-second samples reported 20.5,
  20.8, and 19.1 FPS while the animated Transformers loading screen was
  visible. These values describe startup only. They do not have gameplay or
  30 FPS credit.
- HLE queue result: The queue consumer continued to drain the ring. Near the
  end, the head normally caught the tail, and the used count ranged from zero
  to small transient values. The route did not reproduce the old full-ring
  deadlock.
- Stability: No dead FIFO, GCM heap assertion, fatal error, verification
  failure, access violation, or process restart occurred.
- Thermal result: The device watchdog recorded 43 normal samples. Fixed
  silicon reached 42.9 C, and CPU junction reached 45.3 C. It recorded no hold
  or thermal stop action.
- Rollback: The fail-closed route stopped the package. The failure capture has
  no remaining process.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-020236-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-020303-thor-input-custom`.
- Decision: HLE startup works. Do not use the Eternal Sonata readiness gate for
  this title. Use fixed, identical continuous windows and explicit images for
  the first yield-redispatch A/B.

## 185. Add a bounded yield-redispatch interval control

- Status: route-tooling, host-verified, unmeasured
- Scope: Transformers HLE speed experiment, SPURS task yield redispatch
- Reason: The required redispatch currently saves and restores almost all of a
  256 KB SPU local store on every task yield. The zero-copy yield fast path is
  not valid on this repair stack; experiment 87 recorded an SPU access
  violation. The core already supports redispatch on every Nth yield with a
  separate counter for each host SPU thread.
- Change: The dedicated Transformers HLE route now accepts
  `-YieldRedispatchEvery` values 1, 2, 4, 8, 16, 32, or 64. It writes the value
  to `debug.rpcsx.thor.yield_redispatch_fix`. The default remains 1, so the
  shipped route behavior does not change.
- Verification: The focused Transformers HLE LFQueue route contract passes.
  PowerShell syntax parsing and `git diff --check` pass.
- APK result: No APK or native code changed. The installed exact APK remains
  valid for this property A/B.
- FPS/frame-time: Not measured.
- Next: Use the same unpaused startup macro for control value 1 and candidate
  value 4. Require the legal and loading images, normal queue draining, and no
  SPU access violation before comparing continuous frame samples.

## 186. The every-yield control holds about 21 FPS on the loading screen

- Status: control, visual-progress, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS, `yield_redispatch_fix=1`, continuous unpaused
  startup
- Cold gate and identity: A separate strict gate passed at 36.1 C. The route
  proved the installed APK SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  The macro used fixed images at 120 and 140 seconds.
- Visual result: Both images showed the animated Transformers loading screen.
  The first image showed a Decepticon symbol, and the second showed an Autobot
  symbol. The screen therefore changed and the loading animation was active.
- Frame result: The complete ten-second samples ending at 2:03, 2:13, and
  2:23 reported 21.0, 21.1, and 20.7 FPS. Their mean is 20.93 FPS. The image
  overlays reported 22.23 and 24.21 FPS. These are startup loading values, not
  gameplay values.
- Stability: No dead FIFO, GCM heap assertion, fatal error, verification
  failure, access violation, or process restart occurred.
- Thermal result: The device watchdog recorded 42 normal samples. Fixed
  silicon reached 43.3 C, and CPU junction reached 45.7 C. It recorded no hold
  or thermal stop action.
- Rollback: The macro stopped the package. The verified post-run state had no
  PID.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-021203-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-021225-thor-input-custom`.
- Tooling: The input macro now includes
  `debug.rpcsx.thor.yield_redispatch_fix` in the startup property readback. The
  candidate capture will therefore prove the exact value directly.
- Next: After a new strict gate, run the identical macro with
  `-YieldRedispatchEvery 4`. Reject it on any wrong visual, SPU access
  violation, stopped queue, or lower matching-window frame rate.

## 187. Every fourth yield is slower and delays loading progress

- Status: rejected, visual-progress, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS, `yield_redispatch_fix=4`, continuous unpaused
  startup
- Cold gate and identity: A separate strict gate passed at 38.9 C. The route
  proved the installed APK SHA-256 as
  `C23A8DD9E9B0EAC054F91C23CD382542FA80A4A9D2B9521AF0B46A35F6E0670F`.
  The startup property readback proved
  `debug.rpcsx.thor.yield_redispatch_fix=4`. The macro was identical to the
  control except for this property.
- Visual result: Both images showed the animated Transformers loading screen,
  but both remained on the Decepticon phase. The control changed from the
  Decepticon phase at 120 seconds to the Autobot phase at 140 seconds. The
  candidate therefore did not show faster loading progress.
- Frame result: The complete ten-second samples ending at 2:04, 2:14, and
  2:24 reported 20.3, 21.2, and 20.3 FPS. Their mean is 20.60 FPS. The control
  mean was 20.93 FPS. The candidate is 1.6 percent lower. The image overlays
  also fell from 22.23 and 24.21 FPS in the control to 14.45 and 15.13 FPS in
  the candidate.
- Stability: No dead FIFO, GCM heap assertion, fatal error, verification
  failure, access violation, or process restart occurred. Correctness alone
  does not authorize a slower speed route.
- Thermal result: The device watchdog recorded 42 normal samples. Fixed
  silicon reached 43.7 C, and CPU junction reached 45.3 C. It recorded no hold
  or thermal stop action.
- Rollback: The macro stopped the package. The verified post-run state had no
  PID.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-021627-thor-input-strict-cool-gate`
  and
  `debug-captures/android-speed-sprint/20260830-021650-thor-input-custom`.
- Decision: Reject value 4 and keep the default value 1. Do not test larger
  intervals because this smaller reduction already delays progress. The next
  diagnostic must use the PPU profiler on the proven every-yield route.

## 188. Add a bounded PPU profiler route control

- Status: route-tooling, host-verified, unmeasured
- Scope: Transformers HLE PPU wait diagnosis
- Reason: The loading route uses only about 20 to 33 percent total CPU while
  it presents about 21 FPS. Reducing SPURS yield redispatch work did not
  increase frames. The existing title research identifies the PPU wait chain
  as the remaining unprofiled participant.
- Change: The dedicated Transformers HLE route now accepts `-PpuProfiler on`.
  It sets `debug.rpcsx.thor.ppu_prof=1` before launch, includes the value in the
  startup property readback, and clears it after the route. The default is off.
- Verification: The focused Transformers HLE LFQueue route contract passes.
  Both PowerShell files pass syntax parsing. `git diff --check` passes.
- APK result: No APK or native code changed. The installed exact APK already
  contains the Android PPU profiler override.
- FPS/frame-time: Not measured.
- Next: Keep `yield_redispatch_fix=1`. Run one independently cool, unpaused
  loading capture with the PPU profiler on. Use the profiler report to select
  a named wait path before another code change.

## 189. The PPU profile names a render barrier, not a compute limit

- Status: diagnostic-result, host-mapped, startup-only
- Scope: BLUS30357, HLE SPURS, PPU profiler and bounded PPU call trace
- Profiler result: The main PPU thread spends most of its sampled time at
  guest address `0x00102b98`. A focused Ghidra import maps this address to a
  render barrier. The barrier is a valid game wait and not an unknown HLE
  function.
- Render-thread result: The RenderingThread calls `sys_timer_usleep(400)` at
  guest CIA `0x0152efc0`. This is the matching producer poll. It is the only
  short wait on this path that has a safe title and address gate.
- Decision: Do not remove the main-thread wait. Test the 400 microsecond render
  poll with one bounded property. Keep all other HLE controls unchanged.

## 190. A 50 microsecond render poll is slower

- Status: rejected, startup-only, android-clean
- Scope: BLUS30357, HLE SPURS, RenderingThread poll interval
- Change: Exact APK
  `D6CCE13A7076497A5C541245CA085B98960723EFDC9742413BE336B87EC6C72B`
  added
  `debug.rpcsx.thor.tf_render_poll_us`. The control keeps 400 microseconds. The
  candidate uses 50 microseconds only at CIA `0x0152efc0` for BLUS30357.
- Result: The 50 microsecond arm did more host wake work and did not advance
  the loading sequence faster. Its matching continuous frame samples were
  lower than the 400 microsecond control.
- Decision: Reject 50 microseconds. Keep 400 microseconds. A shorter sleep does
  not remove the serial handoff that limits this startup sequence.
- Capture paths:
  `debug-captures/android-speed-sprint/20260830-031111-thor-input-custom` and
  `debug-captures/android-speed-sprint/20260830-031326-thor-input-custom`.

## 191. Ghidra maps the intermittent fault to the render consumer DMA

- Status: static-analysis, fault-path-mapped
- Scope: BLUS30357, exact SPU local-store image, HLE SPURS resume fault
- Fault: Some HLE boots stop in `CellSpursKernel0` at SPU PC `0x048e0` while
  reading `0xfff00000` or `0xfff10000`.
- Ghidra result: The exact render consumer is taskset `0x10364100`, with ELF
  address `0x0177ec80`. The call path is `0x0c9b0` to `0x0b348` to `0x099a8`.
  It remaps a page and then issues a 4 KiB GET. An unmapped page sentinel makes
  the final `0xfffxxxxx` address.
- Artifact: The exact local-store image is
  `_research/spurs/task_ls_10364100.bin`. The focused Ghidra report is
  `debug-captures/ghidra-transformers-spu-callers/spu-hot-window-ghidra.txt`.
- Decision: Do not hide the access violation. Preserve queue publication order
  so the consumer cannot read a slot before the producer fills it.

## 192. Queue publication must happen after slot ownership

- Status: correctness-fix, host-verified
- Scope: BLUS30357, HLE SPURS queue push
- Old defect: The first queue-order experiment copied data to a guessed slot
  before it owned that slot. Two producers could guess the same slot. The path
  could also copy one entry two times.
- Change: The corrected path claims `tail % depth` inside the reservation. It
  copies the entry while it owns the reservation. It publishes the new tail
  only after the copy. BLUS30357 uses this path by default. An explicit zero is
  the rollback.
- Verification: The queue contract rejects a copy to a guessed slot. It
  requires the reservation, copy, and tail update in that order.
- Commit: `82709c139 Publish Transformers queue entries safely`.

## 193. The safe queue path is stable but is not a loading speed win

- Status: correctness-pass, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS, safe queue publication
- Identity: Exact APK
  `575535293823D0D27E9D08A7042FA2E86EB08E5D46B07BA3FACBC76CC372ACEF`
  ran in `20260830-034608-thor-input-custom`.
- Stability: The route had no SPU access violation, dead FIFO, GCM assertion,
  verification failure, or process restart. The queue and SPURS hot diagnostic
  rows were absent.
- Frame result: Complete loading samples stayed near 20 to 22 FPS. The images
  showed the animated Transformers loading sequence. This is not a speed win
  and is not gameplay credit.
- Decision: Keep the safe publication order because it removes an invalid
  producer action and keeps the HLE route stable.

## 194. Coalesced task context copies reach the legal screen

- Status: visual-progress, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS task yield and resume
- Cause: The hot task uses local-store pattern
  `03ffffffffffffffffffffffffffffff`. The old save and restore loops issued up
  to 122 separate 2 KiB copies in each direction on every yield.
- Change: Consecutive selected local-store blocks now use one copy for each
  run. Sparse patterns keep the same compact context layout. The context layout
  contract checks both directions.
- Identity: Exact APK
  `E8F92B228DDC8FE88F4412B42AF535C23F8A2315CC0507C26309F776EB62F2F7`
  ran in `20260830-035239-thor-input-custom`.
- Visual result: The route reached the correct Unreal, PhysX, and Hasbro legal
  frame. It had no SPU access violation, dead FIFO, GCM assertion, or
  verification failure. Fixed silicon stayed below 43 C.
- Performance: Legal-screen images reported about 13 to 15 FPS. This scene is
  an intro movie and is not a gameplay speed result.
- Commit: `86415f69e Coalesce SPURS task context copies`.

## 195. START advances HLE into the Transformers loading sequence

- Status: input-progress, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS, direct pad input
- Route: Capture `20260830-035730-thor-input-custom` saved the legal frame at
  60 seconds. One direct START press moved the title into the Transformers
  loading sequence. Later images changed from a Decepticon symbol to an
  Autobot symbol. Direct input and normal title progress therefore work.
- Frame result: The last complete ten-second sample reported 21.1 FPS. The
  image overlays ranged from about 12 to 17 FPS during the changing startup
  phases. These values are not gameplay credit.
- Stability: The route had no access violation, dead FIFO, GCM assertion,
  verification failure, process restart, or thermal stop. Fixed silicon peaked
  at 43.3 C. The macro stopped RPCSX and the final PID was absent.
- Decision: HLE now reaches normal startup after legal screens. The next valid
  speed target is the first title menu or moving 3D gameplay, not the intro
  movie.

## 196. Normal Android now omits inactive SPURS diagnostics

- Status: host-verified, installed-exact, device-speed-pending
- Scope: LFQueue, event flag, and Transformers render-poll hot paths
- Change: Normal Android builds now fold out the inactive LFQueue ring counter,
  LFQueue notify counter, SPURS event-set counter, event-set error dump, and
  render-poll hit counter. Explicit SPURS-probe builds keep all diagnostics.
- Verification: Five focused contracts pass. The normal ARM64 APK build passes
  and contains only `arm64-v8a` native libraries.
- Identity: Exact APK
  `7E73F2D06D13A8CD6BA4F1654647CDCE7E1D234C69B45873A43886558BF7961C`
  is 116,152,780 bytes. The no-launch install in
  `20260830-040923-transformers-no-diagnostics-install` proved the same device
  hash and left no PID.
- First-run result: Capture `20260830-040950-thor-input-custom` was not a speed
  test. The log reused 225 validated PPU cache objects and reported 20.2 FPS in
  its only complete ten-second frame sample. Total CPU was 81.5 percent during
  that startup burst. The hard guard stopped RPCSX when fixed silicon reached
  72.7 C. The route saved no game image and has no speed credit. Do not infer
  the cause of the different startup timing from this one stopped run.
- Commit: `a537d9e21 Remove inactive SPURS diagnostics`.
- Next: Wait for the device to cool below 70 C. Then repeat the exact legal,
  START, and loading macro with the warm cache. Reject this change as a speed
  lever if matching frame windows do not improve.

## 197. Inactive diagnostic removal is a speed-null cleanup

- Status: android-clean, startup-only, speed-null
- Scope: BLUS30357, HLE SPURS, normal Android diagnostics
- Identity: Exact APK
  `7E73F2D06D13A8CD6BA4F1654647CDCE7E1D234C69B45873A43886558BF7961C`
  ran in `20260830-041510-thor-input-custom` after a strict start gate below
  70 C.
- Route: The exact legal, START, and loading macro matched capture
  `20260830-035730-thor-input-custom`. The new run reached the legal frame and
  the animated Transformers loading sequence. Direct START and CROSS input
  continued to work.
- Diagnostic result: The LFQueue ring, LFQueue notify, event-set, and render
  poll rows were absent. The route had no access violation, dead FIFO, GCM
  assertion, verification failure, fatal error, `SIGSEGV`, or `SIGBUS`.
- Frame result: The last matching complete ten-second sample was 18.9 FPS.
  The old exact route reported 21.1 FPS. Intermediate samples were mixed as
  the loading symbols and phases changed. This result does not show a speed
  gain.
- Thermal result: Fixed silicon peaked at 42.9 C. Junction temperature peaked
  at 44.9 C. The macro stopped RPCSX and the final PID was absent.
- Decision: Keep the cleanup because normal builds do not need inactive hot
  diagnostics and explicit probe builds retain them. Give it no speed credit.
  Trace the loading dependency before the next device experiment.

## 198. HLE reaches an intermittent zero-flip transition

- Status: visual-progress, transition-stall, android-clean, startup-only
- Scope: BLUS30357, HLE SPURS, six-minute continuous startup route
- Identity: Exact APK
  `7E73F2D06D13A8CD6BA4F1654647CDCE7E1D234C69B45873A43886558BF7961C`
  ran in `20260830-042122-thor-input-custom` after the independent strict gate
  in `20260830-042104-thor-input-strict-cool-gate`.
- Route: The macro saved fixed images at 60-second intervals. It sent START at
  60, 120, 180, and 240 seconds. It sent CROSS after the 300-second image and
  stopped after the 360-second image.
- Visual result: Images through 240 seconds showed the valid animated loading
  screen. The 300-second image showed a wide static band instead of the normal
  loading image. The 360-second image returned to the animated loading screen
  after CROSS. This run alone does not prove that input caused the recovery.
  This is not a correct menu or gameplay frame.
- Frame result: The continuous loading interval was usually about 20 to 22 FPS.
  Frame production then stopped completely. Five consecutive ten-second
  samples ending at emulator times 4:47 through 5:27 reported 0 FPS while total
  CPU stayed between 26.8 and 35.7 percent. CROSS coincided with the end of the
  transition. The next samples reported 15.2, 20.9, 21.6, and 19.6 FPS.
- Stability: The route had no access violation, dead FIFO, GCM heap assertion,
  verification failure, fatal error, `SIGSEGV`, or `SIGBUS`. The conditional
  store counters stopped changing after startup at `stale128=425` and
  `other_fail=705`.
- Thermal result: Fixed silicon peaked at 69.9 C and did not reach the 72 C
  stop limit. The highest junction sample was 79.5 C during the startup spike.
  The device guard did not stop the process. The macro stopped RPCSX and the
  final PID was absent.
- Decision: HLE is not stuck in the first loading animation. It reaches an
  intermittent zero-flip transition, but correct gameplay and 30 FPS are not
  proved. A longer route must determine whether input causes progress or only
  coincides with automatic recovery.

## 199. Nine minutes of input do not leave the loading loop

- Status: blocker-confirmed, android-clean, not-gameplay
- Scope: BLUS30357, HLE SPURS, nine-minute continuous input route
- Identity: Exact APK
  `7E73F2D06D13A8CD6BA4F1654647CDCE7E1D234C69B45873A43886558BF7961C`
  ran in `20260830-042946-thor-input-custom` after the independent strict gate
  in `20260830-042931-thor-input-strict-cool-gate`.
- Route: The macro sent START four times before 300 seconds. It then sent
  CROSS, CROSS, START, and CROSS at one-minute intervals. It saved nine fixed
  images and stopped after 540 seconds.
- Visual result: The first image showed the correct Unreal, PhysX, and Hasbro
  legal frame. All eight later images showed the animated Transformers loading
  screen. The last image still showed loading at 23.70 FPS. Repeated direct
  input did not expose a correct menu or gameplay frame.
- Transition result: Frame rate fell to 8.4 FPS at emulator time 3:23. Four
  consecutive ten-second samples from 3:33 through 4:03 then reported 0 FPS.
  The route recovered to 4.8 FPS at 4:13 and 22.0 FPS at 4:23. This recovery
  happened before the first CROSS after the 300-second image. Input therefore
  did not prove the recovery in experiment 198.
- Steady result: Outside the intermittent transition, later complete samples
  were usually about 20 to 22 FPS. Total CPU was usually about 24 to 33 percent.
  This is a serial wait limit and not full Thor CPU use.
- Stability: The route had no access violation, dead FIFO, GCM heap assertion,
  verification failure, fatal error, `SIGSEGV`, or `SIGBUS`. Fixed silicon
  peaked at 46.6 C and junction temperature peaked at 49.3 C. The macro stopped
  RPCSX and the final PID was absent.
- Decision: Stop blind input runs. The loading loop does not complete after
  nine minutes. Profile and repair the producer for the known main-thread
  render barrier. Do not give loading-screen FPS or intermittent recovery any
  gameplay credit.

## 200. The first main task-fence route stops at the thermal limit

- Status: device-inconclusive, diagnostic-only, thermal-stop
- Scope: BLUS30357, main PPU task fence at guest address `0x00102b98`
- Ghidra basis: The wait at `0x00102b00` loops while the value at the address
  in register 28 is greater than the target in register 29. Address
  `0x00102b98` is immediately after the helper call in this loop. Its caller
  publishes one item to the title task ring and then waits for completion.
- Change: The existing PPU PC census now records the live counter address and
  value, the target, the wait argument, and the raw words in the task ring at
  `0x01d2ffb0`. It records at most 16 samples, only for the main PPU thread at
  the exact wait address, and only when the manual census property is on.
  Normal runs do not enter this path.
- Verification: The focused PPU probe contract and `git diff --check` pass.
  The optimized ARM64 Debug build completed in 2 minutes 3 seconds. The exact
  APK is `E6C8DB6A1FE95162C08EEC2281022EB9435D7B9348555916796D1C8622C28FFE`,
  is 116,154,664 bytes, and passes the ARM64-only APK contract.
- Device result: The no-launch install in
  `20260830-045039-transformers-main-fence-probe-install` proved the same
  device hash and left no PID. The independent start gate measured 39.7 C.
  Capture `20260830-045122-thor-input-custom` stopped when fixed silicon
  reached 72.3 C. The post-stop sample measured 40.5 C and the PID was absent.
- Probe result: The route stopped before the title reached the main fence. It
  saved no image and emitted no main-fence row. It has no visual or speed
  credit. Do not repeat this long route without a new build and a new gate.

## 201. The main and render queues continue to advance

- Status: device-confirmed, theory-rejected, startup-only
- Scope: BLUS30357, main task fence and RenderingThread command wait
- Outer ring: The main caller at `0x00102e44` increments a stack counter,
  publishes an 8-byte record to the task ring at `0x01d2ffb0`, and waits for
  the counter to reach zero. The record method at `0x010f7ff0` decrements the
  counter. The RenderingThread must consume the record before the main thread
  can continue.
- Inner ring theory: Saved PPU census data puts the RenderingThread at
  `0x0152efc0`. Ghidra shows that this address is the wait loop in a separate
  title command-ring reader. A timeout of -1 waits until the published and
  consumed sequence values differ. This made a two-ring wait a testable theory.
- Change: The main-fence probe now also accepts the helper link register
  `0x00102b98`. This matches the saved live samples. A second bounded probe
  records the command-ring base, lane, timeout, mask, sequence values, and one
  RenderingThread call stack at `0x0152efc0`. Both probes require the manual
  PPU census property. Each probe records at most 16 samples.
- Verification: The focused PPU probe contract and `git diff --check` pass.
  The optimized ARM64 Debug build completed in 1 minute 16 seconds. The exact
  APK is `AAA38EA51EACD7E018C34B5C66513E2B74EE563B344CEF02A1C01DFE6AE4CAD3`,
  is 116,154,675 bytes, and passes the ARM64-only APK contract.
- Identity: The no-launch install in
  `20260830-050440-transformers-render-command-wait-install` proved the same
  device hash and left no PID. Capture
  `20260830-050749-thor-input-custom` ran after a separate strict gate.
- Outer-ring result: At emulator time 43.310, the main counter was one with a
  target of zero. The task ring contained pending work. Ten seconds later, the
  main thread was in the staged loader. The fence was transient.
- Inner-ring result: The command sequences advanced from 2/2 to 88/88 and then
  to 342/340. The RenderingThread continued to consume commands. Register 27
  held a loop scratch address after the first sleep, not the original timeout.
  The probe now reads the saved timeout from stack address `SP - 0x28`.
- Visual result: The 60-second image showed the correct legal screen. The
  90-second image showed the animated Transformers loading screen. This is not
  gameplay or speed credit.
- Stability and thermal result: The route had no access violation, dead FIFO,
  GCM assertion, verification failure, fatal error, `SIGSEGV`, or `SIGBUS`.
  Fixed silicon peaked at 44.5 C. The macro stopped RPCSX and the final PID was
  absent.
- Decision: Reject the two-ring deadlock theory. Do not bypass either wait.
  Use the existing staged-loader probe during a continuous late-loading window
  to find the request that does not complete.

## 202. Correct the saved render timeout probe

- Status: host-verified, diagnostic-only, device-pending
- Scope: BLUS30357, RenderingThread command wait
- Cause: Register 27 holds the timeout only before the first sleep. The command
  reader reuses it as an address register after the sleep. The first device
  probe therefore reported the command-ring base as the timeout.
- Change: The bounded probe now reads the original timeout from its saved stack
  slot at `SP - 0x28`. It also records the live register 27 value as scratch
  data. No HLE behavior changes.
- Verification: The focused PPU probe contract, the ARM64-only APK contract,
  and `git diff --check` pass. The optimized ARM64 Debug build completed in
  1 minute 16 seconds. The exact APK is
  `E5953CEBDF5869C37CDC0016DCACC2C50E0CCE6B2F589F1C47D4D77466C3ED30`
  and is 116,155,393 bytes.
- Next: Install this exact APK without a launch. After a separate strict gate,
  run through a continuous late-loading window. Use the staged-loader state,
  not the healthy render wait, to select the next repair.

## 203. The first PhysX task does not send its startup reply

- Status: device-confirmed, HLE blocker, not-gameplay
- Scope: BLUS30357, first PhysX SPU task and its PPU startup queue
- Identity: Exact APK
  `2DCD8C0E4FF10CE5835138A21E6BC71D57DCD2A91999F559DE1011B0D4674A38`
  ran in `20260830-090117-thor-input-custom` after a separate strict gate.
- Result: The PPU PhysX thread created task 0 in taskset `0x01ec4700` from
  ELF `0x018c1000`. The SPU received queue `0x01eccb80` in its task argument.
  The nonblocking PPU pop did not receive the startup reply after 5,000,120
  microseconds. It returned `8041090A`. Teardown then caused a dead FIFO.
- Thermal result: The route reached the exact marker after 454.968 host
  seconds. Fixed silicon peaked at 48.2 C. The final process was absent.
- Decision: A longer queue timeout is not a repair. The first PhysX task must
  run and publish the reply before the queue pop can succeed.

## 204. A warm restart can stop before PhysX

- Status: control-result, earlier-blocker, not-gameplay
- Scope: BLUS30357, warm cache control with the same exact APK as experiment
  203
- Identity: Capture `20260830-091611-thor-input-custom` used APK
  `2DCD8C0E4FF10CE5835138A21E6BC71D57DCD2A91999F559DE1011B0D4674A38`.
- Result: The route ran for 613.109 host seconds and completed 22 guest
  slices. It did not reach the PhysX startup marker. Frame production stayed
  at zero for many guest minutes while the main PPU thread remained active.
- Thermal result: Fixed silicon peaked at 47.0 C. The final process was
  absent.
- Decision: A device run must identify the earlier PPU wait before it can use
  the PhysX SPU census. Do not interpret a missing PhysX row as an SPU result.

## 205. The earlier blocker is an FMOD lwmutex chain

- Status: device-confirmed, HLE blocker, not-gameplay
- Scope: BLUS30357, bounded PPU census and exact PhysX SPU census
- Identity: Exact APK
  `B6F670C147C4078C176853E94D175C3CE634C858FCADCD80A8575EF5EDBB6E28`
  ran in `20260830-094232-thor-input-custom` after a separate strict gate.
- Visual result: The strict legal-screen test passed. START was accepted in
  the same process. Early samples reached 9.1 and 7.1 FPS. This is startup
  evidence and not gameplay speed credit.
- Lock result: At emulator time 6:26, the existing title fix woke owner
  `0x0100000c` for lwmutex `0x95008c00`. The main thread advanced in 45
  milliseconds to lwmutex `0x95008e00`, which had the same owner. The main
  thread and the FMOD libAudio event receive thread then remained at HLE PC
  `0x022254ec` with link register `0x00e28c5c`.
- Route result: The run completed 24 slices in 601.156 host seconds. It did
  not create the first PhysX task and did not reach the PhysX marker. Fixed
  silicon peaked at 46.2 C. The final process was absent.
- Decision: Repair the FMOD scheduler dependency before more PhysX work. This
  boundary maps directly to `_sys_lwmutex_lock`; Ghidra is not required for
  this HLE PC.

## 206. Add a bounded FMOD dependency wake

- Status: host-verified, device-pending, title-specific
- Scope: BLUS30357, exact main-thread lock site and exact FMOD event receiver
- Change: The HLE lock route now records the lwmutex owner that blocks the
  FMOD event receiver. It requests one scheduler wake for that owner. The
  main-thread route retries this saved dependency after the initial wake and
  after a later lock candidate. It refuses a wake when the saved owner is the
  main thread, the FMOD waiter, or the current primary owner.
- Safety: The route requires the existing Transformers audio fix, the exact
  title, the exact link register, and the exact FMOD thread name. It changes
  no guest lock control word. Logs stop after 16 dependency rows.
- Verification: The focused HLE LFQueue route contract, `git diff --check`,
  and the optimized ARM64 native build pass. Commit `b26c8f35c` contains the
  change. The exact ARM64 APK is
  `51F7935D3AA332255813BBB483DB058C5F59FEE031103DAB69EAFDC0EC258B0D`,
  is 116,152,443 bytes, and passes the ARM64-only APK contract.
- Next: Install this exact APK without a launch. Use a new strict gate. Prove
  whether the saved owner wakes and whether the route reaches the first PhysX
  task. Give no speed credit until a correct moving gameplay frame is visible.

## 207. The post-sleep dependency recorder runs too late

- Status: device-confirmed, HLE blocker, not-gameplay
- Scope: BLUS30357, first FMOD dependency-wake proof
- Identity: Exact APK
  `51F7935D3AA332255813BBB483DB058C5F59FEE031103DAB69EAFDC0EC258B0D`
  ran in `20260830-100731-thor-input-custom` after a separate strict gate.
- Visual result: The exact legal-screen check passed on guest slice 6. START
  was accepted in the same process.
- Wake result: At emulator time 6:30, the main-thread owner wake changed FMOD
  receiver state from `0x224` to `0x304`. The immediate dependency retry had
  no saved lwmutex or owner and made no change. The main thread then advanced
  to the user lwmutex wrapper with `r3=0x95008e00`.
- Block result: The FMOD event receiver remained in `_sys_lwmutex_lock`. The
  bounded PPU census showed the same kernel PC and link register through the
  remainder of the run. Frame production stayed at 0 FPS. The first PhysX task
  was not created.
- Cause: The dependency recorder ran only after `mutex.sleep()`. The blocked
  FMOD receiver did not reach this post-sleep point. The route therefore could
  not save the owner that FMOD was waiting for.
- Control result: The after-START route completed 23 slices in 622.0 host
  seconds. Fixed silicon peaked at 46.2 C. The stop check found no PID and no
  RPCSX row in top. Post-stop fixed silicon was 41.3 C.
- Decision: Record the FMOD lwmutex and owner on lock entry. Keep the actual
  scheduler wake in the guarded main-thread route.

## 208. Record the FMOD dependency before sleep

- Status: host-verified, device-pending, title-specific
- Change: The exact FMOD receiver now records its lwmutex, control address,
  owner, and owner state at `LOCK-ENTER`. This point is before any signal,
  ownership, or sleep operation. The recorder does not change scheduler or
  guest state. The main-thread route uses the saved owner through the existing
  guarded wake helper.
- Safety: The recorder requires the Transformers audio fix, BLUS30357, the
  exact lwmutex link register, and the exact FMOD receiver name. The main wake
  still rejects the main thread, the current primary owner, and a missing PPU
  owner.
- Verification: The focused route contract now proves that dependency capture
  occurs before `mutex.sleep()`. The contract, `git diff --check`, and the
  optimized ARM64 native build pass. Commit `03665e7d1` contains the change.
  The exact ARM64 APK is
  `B69F0EBC5BC382B808E8792E4C6B6D2B70A0ECBE95F0A1D0138617503284ADA5`,
  is 116,157,454 bytes, and passes the ARM64-only APK contract.
- Next: Install this exact APK without a launch. Use a new strict gate. Stop
  after the dependency and chain-wake rows. Continue to PhysX only if the main
  thread advances from the FMOD lock chain.

## 209. The FMOD lock-entry recorder does not observe the wait

- Status: device-confirmed, HLE blocker, not-gameplay
- Scope: BLUS30357, FMOD pre-sleep dependency proof
- Identity: Exact APK
  `B69F0EBC5BC382B808E8792E4C6B6D2B70A0ECBE95F0A1D0138617503284ADA5`
  ran in `20260830-102835-thor-input-custom` after a separate strict gate.
- Timing result: RPCSX published BLUS30357 at emulator time 0:04. The FMOD
  event receiver was created at 6:30.531. The main owner wake ran 38
  milliseconds later at 6:30.569. The title gate was already valid.
- Dependency result: No pre-sleep dependency row appeared. The main wake again
  changed FMOD state from `0x224` to `0x304`, but its chain retry had no saved
  lwmutex or owner. The main thread moved to the user wrapper for lwmutex
  `0x95008e00`. FMOD stayed in `_sys_lwmutex_lock`, and frames stayed at zero.
- Control result: The exact chain marker was reached. Eight post-marker slices
  completed. The route completed 13 after-START slices in 344.906 host seconds.
  Fixed silicon peaked at 46.2 C. The stop check found no PID and no RPCSX row
  in top. Post-stop fixed silicon was 41.7 C.
- Decision: Do not depend on the short FMOD lock-entry window. At the proven
  main wake point, scan the live lwmutex sleep queues for FMOD and read the
  owner from the matching object.

## 210. Find the live FMOD lwmutex sleep queue

- Status: host-verified, device-pending, title-specific
- Change: The main owner-wake route now scans the live `lv2_lwmutex` objects
  while it holds the ID-manager reader lock. It finds the queue that contains
  PPU `0x0100000c` with the exact FMOD receiver name. It records that lwmutex,
  its guest control address, its owner, and the owner state. A bounded row also
  reports a scan miss. The existing guarded helper performs the only wake.
- Safety: The scan runs only in the exact BLUS30357 main-thread wake route.
  It uses the unlocked ID-manager selector because the caller already holds
  the reader lock. The scan does not change a queue, scheduler state, or guest
  control word.
- Verification: The focused route contract, `git diff --check`, and the
  optimized ARM64 native build pass. Commit `ea653d70b` contains the change.
  The exact ARM64 APK is
  `05D9B37599B418F15A4B25B5E1CC64AD9AC1228DF6ABBA5D4DF93151BB2521EE`,
  is 116,156,275 bytes, and passes the ARM64-only APK contract.
- Next: Install this exact APK without a launch. Use a new strict gate. Stop
  at the queue-scan dependency row. Use its owner and forced-wake result to
  select the next HLE change.

## 211. The FMOD queue scan misses, but the direct wake reaches PhysX

- Status: device-confirmed, partial HLE progress, not-gameplay
- Identity: Exact APK
  `05D9B37599B418F15A4B25B5E1CC64AD9AC1228DF6ABBA5D4DF93151BB2521EE`
  ran in `20260830-104647-thor-input-custom` after a separate strict gate.
- Queue result: The bounded live-object scan did not find an lwmutex sleep
  queue that contained PPU `0x0100000c`. It reported `queue-scan-miss`. The
  existing direct wake changed the FMOD receiver state from `0x224` to
  `0x304`. The receiver then reached its event loop.
- PhysX result: The game created task 0 in taskset `0x01ec4700` from ELF
  `0x018c1000`. Sixteen samples showed the task advancing through PCs
  `0x03050`, `0x06930`, `0x04b88`, `0x03d90`, `0x05320`, and `0x03128`.
  The task did not publish its queue reply in five seconds. The title then
  removed modules and reached the known dead-FIFO teardown.
- Thermal result: Fixed silicon peaked at 44.9 C. The process was absent after
  the forced stop.
- Decision: The queue scan is not the repair. Keep the exact direct wake. The
  first PhysX task is the next measured boundary.

## 212. Capture the exact PhysX SPU local store

- Status: device-confirmed diagnostic, not-gameplay
- Identity: Exact APK
  `DD33EE3977F03BDF977C82FE1739C120C86D9F91882A36325F6409AEC7B3FD00`
  ran in `20260830-113135-thor-input-custom` after strict gate
  `20260830-113110-thor-input-strict-cool-gate`.
- Route result: The legal frame check passed. START was sent to the same PID.
  Five uninterrupted 15-second slices reached the FMOD wake. It changed the
  receiver state from `0x224` to `0x304`. Twenty-six 2.5-second slices then
  reached the exact PhysX task.
- Dump result: RPCSX wrote the full 262,144-byte local store from
  `CellSpursKernel2` at PC `0x06930`. The file SHA-256 is
  `13C78B97D2E975FE7533579B058F34BBCE4D589A0A60AF4E2858119DCA4EC726`.
  The captured taskset is `0x01ec4700`, and the ELF is `0x018c1000`.
- Measurement limit: The controller paused the emulator 201 milliseconds
  after task creation. The five-second HLE queue clock continued while the
  emulator was paused. This timeout is valid diagnostic evidence, but it is
  not an uninterrupted speed result.
- Thermal result: Fixed silicon peaked at 47.4 C. The clean stop found no PID
  and no RPCSX row in top.

## 213. Ghidra maps the PhysX cold-compile chain

- Status: host-confirmed cause candidate, device control in progress
- Evidence: `spu_cfg.py` reached 4,449 instructions from the six observed PCs.
  It found 21 reachable halt instructions and no DMA argument assert. Ghidra
  imported the exact local store as `SPU:BE:128:default` at base zero.
- Startup chain: Function `0x06800` calls `0x04b88`, `0x03d90`, `0x05320`,
  and `0x03128` in order. Function `0x06878` calls this chain before it enters
  the reservation and queue path. PC `0x06ac4` is the logged GETLLAR pattern.
- Compile timing: The earlier uninterrupted run loaded `0x04b88` in about
  0.51 seconds and `0x03d90` in about 2.48 seconds. The five-second HLE window
  ended before `0x05320` or `0x03128` loaded. The SPU continued through several
  startup PCs; it did not remain in one reservation loop.
- Decision: Do not extend the five-second wait. First run one uninterrupted
  warm control with the exact cached objects. If that control replies, repair
  cold compilation at this exact task boundary. If it does not reply, inspect
  the reservation path next.

## 214. The audio reserved owner is a valid baton pass

- Status: device-confirmed correction, not-gameplay
- Identity: Exact APK
  `81C711BD3ED6ABB69ABABBAAF294509DB6326729D5D3A4407FBE8CD3B8E0168C`
  ran in `20260830-133028-thor-input-custom` after strict gate
  `20260830-133009-thor-input-strict-cool-gate`.
- Trace result: The first exact FMOD wake occurred at emulator time 7:04.935.
  The owner changed from the FMOD receiver to `lwmutex_reserved`. The main
  thread received the mutex. The main thread then gave the mutex to the FMOD
  receiver, and the receiver gave it back to the main thread. All handoffs
  completed in about 12 milliseconds.
- Correction: `lwmutex_reserved` is not a stuck owner in this route. It is the
  normal intermediate value for the owner handoff. The reserved-owner replay
  did not run because the second main-thread call used a different stack
  pointer. Remove this unproved replay.

## 215. The later HLE blocker is a main-thread busy loop

- Status: device-confirmed blocker, not-gameplay
- Run result: After the valid audio handoff, SPU compilation continued for
  about 10 seconds. Frame output decreased from 4.60 FPS to 0 FPS. No PhysX
  task or queue marker appeared during the next 300 uninterrupted seconds.
- Thread result: The final host snapshot showed the main PPU at 82.9 percent
  of one core. RSX and the six SPURS workers were mainly idle. The control API
  reported 0 FPS, 0.9 busy cores, no RSX FIFO idle polls, and no SPU self-loop
  parks. This result identifies a guest PPU busy loop before PhysX task
  creation.
- Thermal result: Fixed silicon peaked at 46.6 C. The clean stop found no PID
  and no RPCSX row in top.
- Decision: Enable the existing low-rate PPU PC and stack census. Use a short
  post-audio window to identify the exact guest loop. Do not change PhysX or
  RSX code until this PC is known.

## 216. Ghidra defines the first PhysX queue operation

- Status: static-analysis, host-verified, device-pending
- Scope: BLUS30357, exact captured PhysX local store
- Evidence: Ghidra identified the queue function from `0x06960` through its
  return at `0x06e50`. It issues GETLLAR at `0x06ac4`, prepares PUTLLC at
  `0x06cd0`, issues it at `0x06cf0`, reads its status at `0x06cf4`, and retries
  from `0x06cf8` to `0x06a9c`. The next helper starts at `0x06e58`.
- Change: The exact title, task, age, and code-signature gate now interprets
  the first queue operation through `0x06e54`. It leaves helper `0x06e58` and
  all later PhysX work on LLVM.
- Verification: The focused route contract, `git diff --check`, and the
  optimized ARM64 native build pass. Commit `f630598ca` contains the change.
- Decision: This boundary is the minimum test of the captured reservation
  operation. It does not replace PhysX and does not give gameplay credit.

## 217. The PhysX queue interpreter did not run

- Status: device-inconclusive, earlier-blocker, not-gameplay
- Identity: Capture `20260830-153928-thor-input-custom` used the extended
  PhysX queue interpreter.
- Result: The legal START gate passed. The initial audio wake completed. The
  route then completed 50 post-START slices in about 602 host seconds. It did
  not create the PhysX task, so the new interpreter did not execute.
- Thermal result: Fixed silicon peaked at 62.6 C. No thermal stop, native
  crash, or dead FIFO occurred. The process was absent after the clean stop.
- Decision: Diagnose the earlier PPU boundary. Do not change the PhysX
  interpreter from a run that did not reach it.

## 218. An explicit PPU census must start before audio

- Status: host-verified, diagnostic-correction
- Cause: The explicit `debug.rpcsx.thor.ppu_pc_census=1` control still waited
  for the audio gate. It could not report a blocker that occurred before that
  gate.
- Change: An explicit PPU census now samples immediately. The implicit census
  used by PPU call and event tracing stays behind the audio gate.
- Verification: The focused route contract and optimized ARM64 native build
  pass. Commit `2f1c5c7ef` contains the change.
- Decision: An explicit diagnostic must not inherit an unrelated late-start
  gate.

## 219. The main PPU is in HLE lwmutex unlock

- Status: device-confirmed correction, HLE blocker, not-gameplay
- Identity: Capture `20260830-161130-thor-input-custom` used the corrected
  explicit PPU census.
- Result: After the audio owner wake, repeated samples showed main PPU
  `0x01000000` at HLE PC `0x02224ffc`, link register `0x00e28c18`, stack
  `0xd003f740`, and `r3=0x95008d00`. This maps to `_sys_lwmutex_unlock`.
- Correction: Experiment 215 did not identify a guest busy loop. The stable
  high host use occurred while the PPU was inside an HLE unlock call.
- Thermal result: Fixed silicon peaked at 65.4 C. The final stop showed no
  process. Post-stop fixed silicon was 38.1 C.
- Decision: Trace each internal unlock stage. Do not force the reserved guest
  owner because experiment 214 proves that it is a valid handoff value.

## 220. The targeted unlock did not reproduce

- Status: device-inconclusive, route-progress, not-gameplay
- Change: Commit `57005aa8c` adds an eight-call, title, PPU, link-register,
  and mutex-gated trace around ID lookup, the internal queue lock, waiter
  selection, wake, and notification cleanup. The optimized ARM64 core SHA-256
  is `690B1AD0D8B185F28DA413984221810378DA24B0E25FF4633B8324DD53E2816C`.
- Identity: Capture `20260830-162623-thor-input-custom` ran this core with the
  low-level lwmutex trace enabled.
- Result: The exact main-thread unlock of `0x95008d00` did not occur. The run
  created the PhysX workload at emulator time 2:52. It later completed the
  FMOD handoff. One performance interval reported 77 frames in 10 seconds,
  or 7.7 FPS. Later intervals reported zero frames. The PhysX task and its
  startup queue operation did not start.
- Thermal result: Fixed silicon peaked at 63.4 C. The final stop found no PID
  and no RPCSX row. All 68 debug properties were clear, and fixed silicon was
  36.1 C.
- Decision: The `0x95008d00` symptom is timing-dependent. Keep the targeted
  trace, but use the PPU census to identify the route when the symptom is
  absent. The 7.7 FPS interval is startup evidence and not gameplay credit.

## 221. The render-consumer DMA fault recurs

- Status: device-confirmed fault, prior-stability-claim-corrected
- Identity: Capture `20260830-164042-thor-input-custom` combined the explicit
  PPU census with the targeted lwmutex trace.
- Fault: Before the legal START frame, `CellSpursKernel0` stopped at SPU PC
  `0x048e0` while it issued a 4 KiB GET from unmapped guest address
  `0xfff30000`. The caller link register was `0x09b14`.
- Ghidra correlation: This is the render consumer from experiment 191. Its
  exact taskset is `0x10364100`, its ELF is `0x0177ec80`, and its mapped call
  chain is `0x0c9b0` to `0x0b348` to `0x099a8` to `0x048e0`.
- Correction: The safe queue publication order from experiments 192 and 193
  was enabled. It did not prevent this recurrence. The earlier stability
  result therefore proves one clean run, not a complete repair.
- Thermal result: Fixed silicon peaked at 54.6 C. The failure cleanup found no
  PID or RPCSX row. All 68 properties were clear, and fixed silicon was 34.5
  C.
- Decision: Do not suppress the access violation. Use the existing bounded
  queue payload and work-item diagnostic to identify the packet that produces
  the unmapped page sentinel.

## 222. The paused route makes the PhysX timeout invalid

- Status: device-confirmed route error, HLE progress, not-gameplay
- Identity: Capture `20260830-173509-thor-input-custom` used commit
  `f43637c4d` and dev-core SHA-256
  `16AED62AD86F1060EC1629E696C6474187DF0966D3D5FCA94B9739DD53CAB09F`.
- Unlock result: The exact `0x95008d00` unlock did not occur. Therefore, the
  new waiter-link trace did not run. The route did complete the exact audio
  owner wake at emulator time 3:53.417.
- PhysX result: The title created the PPU PhysX thread at 4:20.159. It created
  the exact PhysX task at 4:32.137. The SPU entered the startup interpreter at
  4:32.213. The PPU queue wait timed out five seconds later. The interpreter
  left at 4:43.409 after 11.196 seconds.
- Measurement error: The route used two-second active slices. The five-second
  queue timer continued while RPCSX was paused. The timeout does not prove
  that the PhysX task needs more than five uninterrupted seconds.
- Guest result: The title printed `SPURS PPU queue pop wasn't successful:
  8041090A` and started module teardown. A later dead FIFO occurred during
  this teardown. It is not the first fault.
- FPS result: The frame counter reported 8.40, 5.10, 2.10, 3.70, 6.10, and
  3.40 FPS in the startup intervals before teardown. It then reported zero
  FPS. These values are not gameplay credit.
- Thermal and fan result: The controller maximum was 66.2 C fixed silicon.
  The device guard recorded 436 samples, a 67.0 C fixed-silicon maximum, and
  an 86.3 C junction maximum. Every sample reported Smart fan mode `4`. The
  process was absent after the stop. The saved `fan_speed=100` value remained
  an inactive Custom-mode slider value.
- Decision: Do not extend the five-second HLE wait. Give the existing wait one
  valid uninterrupted window before a synchronization change.

## 223. Start the continuous PhysX window before task creation

- Status: controller correction, host-pass, device-pending
- Cause: The old default kept two-second slices until the PhysX queue result.
  This made the queue timer include controller pause time.
- Change: The Transformers route now pauses when it first sees the PPU PhysX
  thread creation row. It then uses one 30-second continuous window. The
  measured run put this row about 12 seconds before the exact PhysX task, so
  the continuous window starts before the five-second queue timer.
- Safety: The Smart fan check and the independent device thermal guard stay
  active during the continuous window. The controller still stops the package
  after the bounded window.
- Verification: The focused Transformers HLE route contract and
  `git diff --check` pass.
- Thor result: Not run. Experiment 222 used the one hardware run for this cool
  round.
- Next: In a new cool round, stop first on `Thread "PPU PhysX thread"
  created`. Then require either the queue `ready after` row or the queue
  `timed out after` row from the uninterrupted 30-second window.

## 224. Current RPCS3 has no SPURS queue implementation to import

- Status: online-source-confirmed, no-port-candidate
- Source result: Current RPCS3 master lists `cellSpursQueuePopBody` and the
  other SPURS queue functions only as commented declarations. It does not
  register `cellSpursQueuePopBody` as an HLE function. Therefore, there is no
  current upstream queue implementation to import into this branch.
- ARM context: RPCS3 issue 18769 reports that some ARM systems can advance
  past cold SPU compilation hangs after repeated boots save more cache data.
  This result supports persistent cache use. It does not prove the cause of
  the Transformers queue timeout.
- Related context: RPCS3 issue 18828 reports nondeterministic SPURS and RSX
  stalls on AArch64 with Adreno. Its SPURS fault is an event disconnect. It is
  not the same as the Transformers PhysX queue result.
- Sources:
  - https://github.com/RPCS3/rpcs3/blob/master/rpcs3/Emu/Cell/Modules/cellSpurs.cpp
  - https://github.com/RPCS3/rpcs3/issues/18769
  - https://github.com/RPCS3/rpcs3/issues/18828
- Decision: Keep the SPU cache and run one valid continuous queue handshake.
  Do not copy an unrelated upstream workaround or extend the guest timeout.

## 225. The new round stops after the audio-owner wake

- Status: device-confirmed pre-PhysX stall, HLE queue result not reached
- Identity: Strict gate `20260830-175214-thor-input-strict-cool-gate`
  passed at 34.9 C fixed silicon. Capture
  `20260830-175248-thor-input-custom` used the corrected continuous PhysX
  route with the low-level lwmutex trace disabled.
- Progress: The run completed the FMOD event interpreter and the exact audio
  owner wake at emulator time 3:57.422. Startup frame intervals then fell
  from 2.30, 5.20, 6.10, and 6.20 FPS to zero.
- Failure: The PPU PhysX thread did not start before the 360-second host
  deadline. The controller completed 30 two-second slices and stopped at a
  paused boundary. Therefore, the continuous queue window did not start and
  this run gives no PhysX queue result.
- Scope: This route shape is consistent with the earlier post-audio lwmutex
  stall. The exact lwmutex trace was off, so this capture does not prove the
  internal stop point. Do not claim a queue cycle or a 128-bit atomic fault
  from this run.
- Thermal and fan result: The device watchdog recorded 419 valid samples and
  a final completion row. Every sample reported Smart fan mode `4`. Fixed
  silicon peaked at 69.9 C. Cleanup stopped the package and reported no RPCSX
  process in the process table.
- Decision: Do not run the Thor again in this cool round. In a new cool round,
  enable the bounded lwmutex trace and the PPU census. Require an internal
  `POST AUDIO REOWN` row before any queue repair.

## 226. The arXiv atomic literature does not identify this fault

- Status: online-research-complete, no-code-change
- Research: Recent work on multi-word compare-and-swap describes contention,
  repeated helping, cache invalidation, and ABA as general failure risks.
  Earlier work also explains that CAS performance can fall under contention.
- Scope: These papers do not analyze RPCSX, its 16-byte `lv2_control`, or the
  separate `next_cpu` links. The current capture also has no internal reown
  rows. Therefore, the papers do not distinguish a linked-list cycle from a
  compare-and-swap retry loop in this emulator.
- Sources:
  - https://arxiv.org/abs/2607.06034
  - https://arxiv.org/abs/1305.5800
- Decision: Do not add backoff, version fields, or a queue reset from the
  literature alone. Get the exact `PRE-SCHEDULE`, `POST-SCHEDULE`, and
  `POST-FETCH` sequence first.

## 227. Bound the exact reown queue scan

- Status: host-pass, device-pending, diagnostic-only
- Change: The exact Transformers post-audio reown trace now scans at most 64
  waiter links before it calls the normal scheduler. It reports the depth,
  repeated node, cycle state, and depth-limit state. If the scan finds a cycle
  or reaches the limit, it does not enter the unbounded scheduler.
- Scope: This path still requires the Android trace property, title
  `BLUS30357`, main PPU `0x01000000`, unlock link register `0x00e28c18`, and
  lwmutex ID `0x95008d00`. Normal runs do not use it. It records a fault and
  does not repair or reset the queue.
- Verification: The focused Transformers route contract, the Thor thermal
  contract, and `git diff --check` pass. The Android ARM64 RelWithDebInfo build
  passes. The stripped core is 63,249,032 bytes, with SHA-256
  `A4127B1E0B64AB6D6C73C918C49776673A70E174D4F70B197FC48C72B159EDC4`.
  The core export and relocation surface test passes.
- Thor result: No-launch push
  `20260830-181215-transformers-reown-scan-dev-core-push` installed the exact
  core in the app-private dev-core path. The remote SHA-256 matches. The
  package PID was absent after the push, and the device remained in Smart fan
  mode `4`. The saved `fan_speed=100` Custom slider was inactive. This push is
  not runtime evidence.
- Next: In a new cool round, enable the lwmutex trace and the PPU census. If
  `PRE-SCHEDULE-SCAN` reports a valid finite list but `POST-FETCH` is absent,
  investigate the 16-byte atomic retry. If it reports a cycle, trace the
  repeated PPU link back to its earlier queue insertion.

## 228. The 16-byte compare-exchange still uses an exclusive retry

- Status: host-confirmed code path, fault not proved
- Source result: The AArch64 16-byte load, store, and release paths use the
  LSE2 straight-line implementation. The 16-byte compare-exchange path does
  not. It uses an `LDAXP` and `STLXP` loop. The `fetch_op` helper can also
  retry the complete compare-exchange when another update wins.
- Binary result: The linked Android core contains this exclusive loop in the
  exact traced `lv2_control.fetch_op` path. This result confirms that the
  source path is active in the device binary.
- Compiler probe: Android NDK Clang 18 emits one `CASPAL` instruction for an
  equivalent 16-byte sequentially consistent compare-exchange when the target
  is Armv8.4-A. The temporary probe source was removed after the assembly
  check.
- Scope: This result identifies a possible replacement if the device trace
  stops after `PRE-SCHEDULE-SCAN`. It does not prove that the exclusive loop
  caused the current stall. A waiter-list cycle would make this change
  unrelated.
- Decision: Do not change the generic atomic helper yet. Run the bounded exact
  trace first. If the scan reports a finite list and `POST-FETCH` is absent,
  test a `CASPAL` compare-exchange implementation as a separate experiment.

## 229. The diagnostic handoff misses the valid PhysX route

- Status: device-confirmed route error, HLE progress, not-gameplay
- Identity: Strict gate
  `20260830-181728-thor-input-strict-cool-gate` passed at 34.1 C fixed
  silicon. Capture `20260830-181757-thor-input-custom` used the bounded
  lwmutex trace and the PPU census.
- Lwmutex result: The exact `0x95008d00` unlock and its
  `PRE-SCHEDULE-SCAN` row did not occur. The related `0x95008c00` audio
  handoff completed. This run gives no waiter-list or compare-exchange result.
- PhysX progress: The title created the PPU PhysX thread at emulator time
  3:56.693. The SPU entered the exact PhysX startup interpreter at 4:07.771.
  The guest queue wait reported a five-second timeout, and the interpreter
  left after 10.389 seconds.
- Measurement error: The route waited for `PRE-SCHEDULE-SCAN` before it could
  start a continuous window. It kept using two-second slices after the PPU
  PhysX thread started. The guest timer continued while RPCSX was paused.
  Therefore, the queue timeout is invalid for the same reason as experiment
  222.
- Later state: The main thread stayed at `0x00b56de0`, and the PPU PhysX
  thread stayed at `0x00fdcf90`. Frame intervals reached 5.8 FPS during
  startup and then fell to zero after the invalid queue timeout. These values
  are not gameplay credit.
- Thermal and fan result: The controller peak was 63.8 C fixed silicon. The
  device watchdog recorded 411 valid samples and a 65.4 C fixed-silicon
  peak. Every sample reported Smart fan mode `4`. Cleanup stopped the package,
  and a direct check found no RPCSX PID. The final fan mode was Smart.
- Decision: Do not run a second device route in this cool round. The next
  controller change must accept either the diagnostic scan or the PPU PhysX
  thread as the first handoff. It must use a short diagnostic step after the
  scan and a continuous queue window after the PhysX marker.

## 230. Select the first valid post-START handoff

- Status: controller correction, host-pass, device-pending
- Change: The guarded slice controller now accepts a bounded list of stop
  markers and reports the marker that ended the loop. The Transformers route
  waits for either `PRE-SCHEDULE-SCAN` or the PPU PhysX thread creation row.
- Diagnostic branch: If the lwmutex scan occurs first, the route runs one
  normal slice and requires `POST-FETCH`. This branch does not start a long
  continuous window.
- PhysX branch: If the PPU PhysX thread occurs first, the route starts the
  existing 30-second continuous queue window. This keeps the five-second
  guest timer valid.
- Safety: Both branches keep the independent device watchdog, Smart fan mode,
  the 70 C start rule, and the 72 C hard stop.
- Verification: Python syntax, the guarded slice logic, the Transformers HLE
  route contract, both Thor thermal contracts, and `git diff --check` pass.
- Next: In a new cool round, run this route with the lwmutex trace and PPU
  census enabled. Require either an exact `POST-FETCH` diagnostic result or a
  queue result from the uninterrupted PhysX window.

## 231. The late main-thread PC is a downstream condition wait

- Status: Ghidra-confirmed guest path, no-code-change
- Runtime source: Capture `20260830-181757-thor-input-custom` kept the main
  thread at CIA `0x00b56de0` with LR `0x00ae0da8` after the invalid PhysX
  queue timeout. The complete thread context identifies `sys_cond_wait`,
  condition ID `0x8600bb00`, timeout value `-1`, and object address
  `0x10f9864c`.
- Ghidra source: The retained BLUS30357 EBOOT project maps LR call site
  `0x00ae0da4` to function `0x00b56d44`. The function locks the mutex ID at
  object offset 8 with syscall `0x66`. It checks the byte at offset 0. When
  that byte is zero and the timeout is `-1`, it waits without a timeout on
  the condition ID at offset 4 with syscall `0x6b`. It then unlocks the mutex
  with syscall `0x68`.
- Timing: The thread-context dump reports that this condition wait began about
  0.059 seconds before the dump. It occurs after the PhysX queue reported its
  timeout and after the title printed the failed queue-pop result.
- Scope: The same wait wrapper also appears on the PPU PhysX thread before the
  interpreter starts. The wrapper is a normal title synchronization helper.
  The late main-thread instance is downstream of the invalid sliced timeout.
  It does not identify the HLE queue fault.
- Decision: Do not patch or wake this condition. Preserve the dual-marker
  route and get the first valid uninterrupted PhysX queue result.

## 232. The post-audio waiter has a one-node self-cycle

- Status: device-confirmed queue fault, repair host-pending
- Identity: Strict gate
  `20260830-183922-thor-input-strict-cool-gate` passed at 34.1 C fixed
  silicon. Capture `20260830-183943-thor-input-custom` selected the exact
  post-audio diagnostic marker before the PPU PhysX marker.
- Queue result: Lwmutex `0x95008d00` contained PPU `0x0100000c` as its head.
  The same PPU was also its own `next_cpu` link. The bounded scan reported
  depth 1, a cycle, and repeated node 0. This is an invalid one-node queue.
- Atomic result: The enclosing 16-byte `lv2_control.fetch_op` completed in
  one attempt and returned no waiter. The exclusive compare-exchange loop is
  not the observed stop in this capture.
- Source correlation: The FMOD PPU was not present in an lwmutex queue when
  the initial audio-owner wake scanned the queues. After the wake, it entered
  the `0x95008b00` handoff and then waited on the post-audio mutex. The
  one-node self-cycle appeared before the main PPU tried to release that
  mutex. The evidence supports a duplicate insertion after the forced wake.
- Thermal and fan result: The watchdog recorded 194 valid samples. Every
  sample reported Smart fan mode `4`. Fixed silicon peaked at 69.9 C. Cleanup
  stopped the package, found no RPCSX PID, and left Smart fan mode active.
- Decision: Repair only this exact one-node self-cycle. Require title
  `BLUS30357`, the trace property, the audio-wake property, lwmutex
  `0x95008d00`, PPU `0x0100000c`, and the exact FMOD thread name. Convert the
  queue to a valid empty head inside the atomic control update, then clear
  the selected waiter's link and use the normal wake path. Do not change the
  generic queue or atomic implementation.

## 233. Repair only the exact post-audio self-cycle

- Status: host-pass, device-pending
- Change: The exact post-audio reown path now recognizes only a depth-one
  self-cycle for PPU `0x0100000c` with the exact FMOD thread name. It also
  requires the existing Transformers title, trace, audio-wake, main-PPU,
  unlock-link, and lwmutex gates.
- Atomic safety: The repair selects the known waiter and changes the copied
  atomic queue head to null. It does not change `next_cpu` inside a callback
  that the compare-exchange can repeat. After the atomic update succeeds, the
  existing reown completion clears the selected link and the normal unlock
  path wakes the waiter.
- Scope: Other cycles and depth-limit faults still fail closed. The generic
  lwmutex queue, scheduler, and 16-byte atomic implementation are unchanged.
- Verification: The focused Transformers HLE route contract, both thermal
  contracts, `git diff --check`, and the Android ARM64 RelWithDebInfo build
  pass. The stripped dev core is 63,250,232 bytes with SHA-256
  `25E0696D25E1D2A1E63E5C05DB373F7DAAB19FD4EB24861E0800C9D061326755`.
  Its export and relocation surface passes.
- Next: Commit the source and push this exact core without a launch. After a
  new strict cool gate, run one guarded Transformers route. Require the
  `REPAIR-SELF-CYCLE` row, a normal waiter handoff, and either a continuous
  PhysX queue result or a later bounded stop marker.

## 234. The 70 C early hold leaves too little burst margin

- Status: device-confirmed thermal stop, HLE repair not reached
- Identity: No-launch gate
  `20260830-185451-thor-input-strict-cool-gate` passed at 34.5 C fixed
  silicon. The exact dev core SHA-256
  `25E0696D25E1D2A1E63E5C05DB373F7DAAB19FD4EB24861E0800C9D061326755`
  matched after the push. Runtime gate
  `20260830-185540-thor-input-strict-cool-gate` also passed. Capture
  `20260830-185551-thor-input-custom` used that core.
- Route result: Four bounded pre-START slices completed at controlled pauses.
  The fifth slice found that the watchdog had stopped the package. The title
  did not reach the legal START frame, the repair marker, or the PPU PhysX
  marker. This run gives no HLE result.
- Thermal result: Every one of 86 watchdog samples reported Smart fan mode
  `4`. Fixed silicon was 69.5 C on sample 85, below the 70 C early-hold
  threshold. It reached 75.1 C on sample 86, above the 72 C hard limit, and
  the watchdog force-stopped the package. The process table was empty after
  cleanup. Later stopped-state reads were hotter because sensor cooling lags
  process termination.
- Cause: A 70 C early-hold threshold has no useful margin below the 72 C hard
  limit. A workload burst can cross both thresholds between 250 ms samples.
- Change: Lower only the independent Transformers device-watchdog early hold
  to 68 C. Keep the 72 C hard stop, 250 ms polling, Smart fan enforcement,
  and the below-70 C cold launch gate. Set every guest-slice start ceiling to
  68 C as well. This includes the repeated one-slice visual gates, which each
  otherwise treated their first slice as a new 70 C cold start. The controller
  can resume the held process only after its paused cooldown.
- Decision: Do not run the Thor again in this thermal round. Verify the route
  and thermal contracts on the host. A later cool device run must prove that
  the 68 C hold occurs before the hard limit before it can test the HLE repair.

## 235. Current RPCS3 has no duplicate lwmutex waiter fix

- Status: upstream-check-complete, no-code-change
- Source: The read-only RPCS3 comparison checkout fetched official
  `origin/master` at commit
  `d267b420f8736a8580cea6e16b9927ddc0df715d` from 2026-08-31.
- Result: Current `lv2_lwmutex::try_own` still assigns the old queue head to
  `cpu->next_cpu` and then makes that CPU the new head. It has no duplicate
  membership or self-link check. No new commit in the fetched range changes
  `sys_lwmutex.h` or `sys_lwmutex.cpp`.
- Scope: This does not make a broad queue change safe. The local fault follows
  a title-specific forced owner wake that official RPCS3 does not have.
- Decision: Keep the exact Transformers self-cycle repair for the next device
  proof. Do not add a generic duplicate-waiter rule without a reproducible
  upstream case or a separate queue-invariant test.

## 236. Another foreground app owns the hot Thor

- Status: device unavailable for a valid emulator run
- Observation: RPCSX remained absent, and Smart fan mode `4` remained active.
  Fixed silicon then stayed near 85 to 86 C instead of cooling.
- Attribution: Two consecutive thread-level process samples identified
  `com.reblue` at about three CPU cores. Android reported
  `com.reblue/.ReblueActivity` as the top resumed activity. The package was
  updated at 19:04:55, after the RPCSX watchdog stop.
- Scope: This heat is not an RPCSX orphan. A new emulator run would overlap an
  unrelated foreground workload and would be thermally invalid. Force-stopping
  that app is outside this experiment's authority.
- Decision: Do not contact or launch RPCSX again while `com.reblue` is active.
  Wait for the user to release the shared Thor and for fixed silicon to fall
  below the strict launch gate. Then use one new guarded run with the 68 C
  slice ceiling and early hold.

## 237. Discard the forced owner signal before a new lwmutex wait

- Status: host-pass, device-pending
- Cause: The forced FMOD owner wake adds `cpu_flag::signal`. The target PPU can
  start a new lwmutex wait before the earlier wait consumes that signal. The
  new wait then queues the PPU, consumes the old signal, and returns without a
  normal queue selection. A later wait can insert the same PPU again and make
  its shared `next_cpu` link point to itself. This sequence agrees with the
  measured queue-scan miss, the forced owner wake, and the later one-node cycle.
- Change: The exact initial owner wake now sets a one-shot pending marker before
  it notifies the selected PPU. At the start of the next lwmutex call, only
  BLUS30357 PPU `0x0100000c` with the exact FMOD thread name can consume this
  marker. The call discards a remaining `cpu_flag::signal` before it enters the
  new wait. It records the lwmutex ID, state transition, and discard result.
- Race control: The scheduler helper sets the marker only after its state
  update succeeds and before it notifies the PPU. If the earlier wait already
  consumed the signal, the next call consumes the marker and changes no state.
- Scope: Only the exact initial FMOD owner wake passes the marker. Dependency
  wakes and all other callers use the unchanged default behavior. The generic
  lwmutex insertion code is unchanged. The exact one-node repair remains as a
  fail-safe.
- Verification: The focused Transformers HLE route contract, both thermal
  contracts, `git diff --check`, and the Android ARM64 RelWithDebInfo build
  pass. The stripped dev core is 63,250,664 bytes with SHA-256
  `DBB76F0EC7BB375A4451420EE968BA1FBA13D8AEBCFCDC6E67652D3FC4EF35F5`.
  It contains the `Thor TWC AUDIO OWNER SIGNAL` marker. Its export and
  relocation surface passes with 40 defined dynamic symbols, 596 explicit
  relocations, 392 jump slots, and 44,437 encoded relocation bytes.
- Device result: Not run. The build and checks did not contact the occupied
  Thor.
- Next: After a read-only check proves that the other foreground workload is
  gone and the device is cool, push this exact core without a launch. Then run
  one guarded route. Require the owner-signal row, no self-cycle, a normal
  post-audio handoff, and later HLE progress before any speed credit.

## 238. The Thor is still occupied near the launch limit

- Status: device-unavailable, read-only-check
- Observation: A single read-only check found no RPCSX PID. It found
  `com.reblue` PID `31983` and reported `com.reblue/.ReblueActivity` as the top
  resumed activity and focused app.
- Thermal result: The four CPU-subsystem sensors reported 69.9, 67.4, 67.8,
  and 67.8 C. The maximum is below 70 C, but it is above the 68 C active-slice
  ceiling and has no safe load margin while another workload is active.
- Fan result: The read-only setting values were `fan_mode=4` and
  `fan_speed=100`. Smart mode `4` is active. The second value remains the saved
  inactive Custom slider. No setting was changed.
- Decision: Do not push or launch RPCSX. Do not stop the unrelated foreground
  app. Wait until that app is absent and fixed silicon is below the guarded
  start point. Then use the exact core from experiment 237.

## 239. Apply the 68 C ceiling to the START handoff

- Status: controller-fix, host-pass, device-blocked
- Device check: RPCSX remained stopped. `com.reblue` PID `4101` remained the
  top resumed activity. Smart fan mode `4` remained active. The four CPU-
  subsystem sensors reported 75.1, 72.7, 77.5, and 75.1 C. No device setting
  changed, and RPCSX did not launch.
- Safety mismatch: The main slice controller used the 68 C start ceiling, but
  its 150 ms START handoff still used 70 C. The handoff executes guest code, so
  it must use the same 68 C ceiling. The separate cold process launch rule
  remains strictly below 70 C.
- Change: The START handoff now uses `maxStartC=68`. Both route contracts reject
  any remaining `maxStartC=70` value. The after-START controller also watches
  for `stage=REPAIR-SELF-CYCLE` and fails immediately if the fallback repair
  runs. A valid source-repair proof must continue without that fallback.
- Verification: The focused Transformers HLE route contract, the device
  thermal-guard contract, the multi-sensor thermal tests, and
  `git diff --check` pass.
- Next: Keep the device idle while the unrelated workload is active. In a later
  cool check, require fixed silicon below 68 C before every guest execution
  slice. Push the exact experiment 237 core without a launch, then run one
  guarded source-repair proof.

## 240. The third availability check remains blocked by the foreground app

- Status: external-device-blocker, third-consecutive-check
- Observation: RPCSX remained stopped. `com.reblue` PID `5314` remained the
  top resumed activity and focused app. Smart fan mode `4` remained active.
- Thermal result: The four CPU-subsystem sensors reported 84.7, 82.7, 84.3,
  and 82.3 C. These values are above both the 68 C slice ceiling and the 72 C
  hard stop.
- Scope: The exact source-repair core and guarded route are ready. More host
  changes without a device result would be speculative and would not prove HLE
  progress or 30 FPS. Stopping the unrelated foreground app is outside this
  experiment's authority.
- Decision: Stop the active device goal as externally blocked. Resume only
  after the user closes `com.reblue` and fixed silicon falls below 68 C. Then
  push core
  `DBB76F0EC7BB375A4451420EE968BA1FBA13D8AEBCFCDC6E67652D3FC4EF35F5`
  without a launch and run the guarded source-repair proof.

## 241. The guarded source-repair route stops in taskset join

- Status: device-confirmed HLE blocker, not-gameplay
- Identity: Capture `20260830-194059-thor-input-custom` used exact stripped
  core SHA-256
  `DBB76F0EC7BB375A4451420EE968BA1FBA13D8AEBCFCDC6E67652D3FC4EF35F5`.
  The legal screen and the direct START input both passed.
- Route result: The controller completed 27 two-second slices after START.
  This is 54 seconds of active guest time over 362.969 seconds of host time.
  The run did not reach the FMOD or PhysX markers. It had no targeted fatal
  error. The source owner-signal repair did not get a chance to run.
- Exact wait: The rendering thread called `cellSpursShutdownTaskset` and then
  `cellSpursJoinTaskset` for taskset `0x1f73f00`, which is workload 7. Join did
  not return. The log has no shutdown-completion mask. The main thread then
  stayed in a guest fence wait with counter 1 and target 0.
- Comparison: Capture `20260830-051545-thor-input-custom` completed the same
  taskset shutdown. Its shutdown-completion mask arrived about 0.030 seconds
  after join started. This confirms that the missing completion is an
  intermittent boundary in the HLE route.
- Thermal and fan result: Every guest slice started from 44.5 to 48.2 C fixed
  silicon. The controller peak was 63.0 C. Cleanup stopped RPCSX, found no
  package PID, and left Smart fan mode `4` active. Do not report the saved
  Custom slider as a measured fan speed.
- Decision: Do not give HLE, gameplay, PhysX, FPS, speed, or stability credit.
  Do not run a second device route in this cool round. Diagnose the missing
  workload-7 shutdown acknowledgement on the host.

## 242. Reconcile the stale workload-7 acknowledgement before join

- Status: host-pass, device-pending
- Source result: A workload status bit records that one SPU has the workload
  in its local runnable snapshot. Shutdown becomes complete only after every
  SPU clears its bit. The HLE system service can clear a bit only after a real
  policy module polls or exits. The stopped run kept one SPU in the GCM policy
  module at PC `0x13dcc`. This gives a source path for an unrelated workload-7
  status bit to remain set. It does not prove which bit was stale in that run.
- Change: Before the workload-shutdown semaphore is armed, the HLE
  Transformers route reads each matching SPU current workload ID twice. It
  keeps a status bit for workload-7 owners, unknown SPUs, and SPUs whose ID
  changes during the read. It clears only stable non-owner bits under the
  existing guest reservation. It restores a missing bit for a known active
  owner. If no bit remains, it makes the workload removable and uses the
  normal completion event path.
- Scope: The repair requires the HLE SPURS kernel, title `BLUS30357`, and
  workload 7. LLE SPURS, other titles, other workloads, and unknown SPUs keep
  the existing path. The repair logs the before and after masks, the known and
  active masks, all current workload IDs, and all sampled SPU PCs.
- Build correction: A signed queue-address literal from an earlier diagnostic
  failed when the complete source file rebuilt. The literal now has the same
  unsigned 64-bit value. This changes no queue address or queue behavior.
- Verification: The new reconciliation contract, the existing shutdown
  completion contract, the existing taskset join contract, and
  `git diff --check` pass. The Android ARM64 RelWithDebInfo build and the
  stripped-symbol task pass. The stripped core is 63,252,552 bytes with
  SHA-256
  `4CE3E002F67CD59CB8CCAF651C1F02062CA36FE161E77F98340C6276E5A591F8`.
  Its export surface passes with 40 defined dynamic symbols, 596 explicit
  relocations, 392 jump slots, and 44,445 encoded relocation bytes.
- Device result: Not run. No ADB command contacted the Thor in this host work.
- Next: In a later cool round, push the exact stripped core without a launch.
  Run one guarded Transformers route. Require the shutdown-reconcile row,
  taskset join return, workload removal, and later FMOD or PhysX progress.

## 243. The valid continuous PhysX window misses the reply boundary

- Status: device-confirmed HLE progress, exact startup blocker, not-gameplay
- Identity: Capture `20260830-202650-thor-input-custom` used stripped core
  SHA-256
  `4CE3E002F67CD59CB8CCAF651C1F02062CA36FE161E77F98340C6276E5A591F8`
  and installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
- Shutdown result: Workload 7 completed its shutdown event about 15
  milliseconds after `cellSpursJoinTaskset` started. The rendering thread then
  continued, and the title created the same taskset again. The new shutdown
  reconciliation row did not appear, so this run did not exercise that repair.
- HLE progress: The title created the FMOD threads and then created the PPU
  PhysX thread at emulator time 3:58.526. It created PhysX task 0 from ELF
  `0x018c1000` and started the uninterrupted queue window at 4:19.457.
- Queue result: The PPU started its bounded pop at 4:19.457818 and reported
  `BUSY` at 4:24.457951. The exact SPU interpreter entered at 4:19.549768 and
  reached helper `0x06e58` at 4:24.458110. The SPU boundary was therefore 159
  microseconds after the PPU timeout. The uninterrupted 30-second slice peaked
  at 67.0 C fixed silicon.
- Ghidra result: A fresh headless import of the retained legal PhysX local
  store used `SPU:BE:128:default`. Function `0x06878` repeats queue function
  `0x06960` only while it returns `BUSY` or `AGAIN`. It calls helper `0x06e58`
  only after the queue function returns another result. Function `0x06960`
  contains the queue reservation and the MFC payload write. This proves a
  terminal queue-push result at the measured boundary. The old log did not
  record the result register, so it does not yet prove that the result was
  success.
- Frame result: The boundary screenshot is a valid Transformers loading screen
  with a 30.00 FPS overlay. Ten-second emulator samples during startup ranged
  from 0 to 6.70 FPS and ended at 3.20 FPS. This is not a gameplay or 30 FPS
  result.
- Thermal and fan result: The independent watchdog recorded 233 valid thermal
  samples and completed after the package stopped. Fixed silicon peaked at
  68.2 C, below the 72 C hard stop. Every watchdog sample reported Smart fan
  mode `4`. A direct cleanup check found no RPCSX PID and confirmed Smart fan
  mode `4`.
- Decision: Keep the broad interpreter boundary for this control. A narrow
  `0x06960` hook would restore the four cold LLVM compiles that previously took
  5.73 seconds. Extend only this exact startup wait by one second and record
  the SPU return value before a larger HLE change.

## 244. Give the exact PhysX startup push one more second

- Status: wait host-pass, old diagnostic superseded, device-pending
- Change: The title, call-site, queue-shape, taskset, and ELF-gated PPU wait is
  now six seconds instead of five seconds. No other nonblocking queue pop
  changes. The wait still consumes only real queue data.
- Diagnostic: The first leave row tried to record `r3` at `0x06e58`. Later
  focused disassembly proved that `0x06924` replaces the queue result in `r3`
  with the queue pointer before that boundary. Section 246 supersedes this
  diagnostic. The six-second wait itself is unchanged.
- Scope: This does not HLE the PhysX workload, fabricate its response, or give
  gameplay credit. It only prevents the measured 159-microsecond startup race.
- Host result: The ARM64 RelWithDebInfo build and the Thortest symbol-strip task
  passed. The stripped core is 63,252,552 bytes and has SHA-256
  `D194EA9B101C1A7C2690D935999B87CA37392399AE7F8E35C979889383E58BE5`.
  The export-surface check passed with 40 defined dynamic symbols, 596 explicit
  relocations, 392 jump slots, and 44,445 encoded relocation bytes.

## 245. The first six-second validation stopped before the reply boundary

- Status: route-budget-insufficient, device result unknown
- Identity: Capture `20260830-205111-thor-input-custom` used stripped core
  SHA-256
  `D194EA9B101C1A7C2690D935999B87CA37392399AE7F8E35C979889383E58BE5`.
  The installed APK matched expected SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
- Progress: The PPU PhysX thread appeared at emulator time 4:05.691455. The
  exact task from ELF `0x018c1000` called the queue pop at 4:24.826654, and the
  exact SPU interpreter entered at 4:24.851096.
- Route limit: The one 30-second host slice ended after the log reached about
  emulator time 4:26.735. The prior run needed about 4.91 seconds inside the
  interpreter. This run therefore stopped about three emulator seconds before
  the expected reply. It produced no `r3`, `ready after`, timeout, or title
  queue-failure row. It does not accept or reject the six-second change.
- Thermal and fan result: The independent watchdog recorded 233 valid samples
  and completed because the package stopped. Fixed silicon ranged from 34.1 C
  to 68.7 C. Junction peaked at 83.1 C. Every sample reported Smart fan mode
  `4`. The launch sample was 33.3 C. The route and a direct cleanup check both
  found no remaining RPCSX process.
- Next: Do not reuse the same core because its leave row cannot report the
  queue result. Build the corrected Section 246 diagnostic. In a later cool
  round, allow two cooled 30-second after-handoff slices. Require queue result
  `0`, a real `ready after` queue row, no queue-failure row, and progress after
  PhysX startup.

## 246. Stop before the queue result register is overwritten

- Status: host-pass, device-pending
- Ghidra result: Focused SPU disassembly of `0x06874..0x06974` shows that
  `0x068f4` calls the queue reservation function. Instructions
  `0x068fc..0x0691c` retry only for `AGAIN` or `BUSY`. On a terminal result,
  execution reaches `0x06920` with the queue result still in `r3`. Instruction
  `0x06924` then replaces `r3` with the local queue pointer before it calls
  helper `0x06e58`.
- Change: The exact interpreter range now ends at `0x06920`, before the
  overwrite. The leave row names the value `queue_rc`. All four cold
  initialization helpers and the complete queue reservation operation remain
  inside the interpreted range.
- Acceptance: The next run must report `pc=0x06920 queue_rc=0x00000000` and a
  real PPU `ready after` row. `AGAIN` and `BUSY` cannot reach this boundary.
  Any other queue result rejects the startup path.
- Host result: The focused route contract, ARM64 RelWithDebInfo build, Thortest
  symbol-strip task, binary marker check, and export-surface check passed. The
  stripped core is 63,252,552 bytes and has SHA-256
  `AD86E50B6AA30818997683C4743CCFFFB40B28C5F42C478160AE99130CD4D749`.

## 247. The corrected PhysX route stops in the earlier taskset join

- Status: device-confirmed intermittent shutdown blocker, not-PhysX,
  not-gameplay
- Identity: Capture `20260830-210910-thor-input-custom` used exact corrected
  core SHA-256
  `AD86E50B6AA30818997683C4743CCFFFB40B28C5F42C478160AE99130CD4D749`
  and installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
- Route result: The after-START controller completed 26 two-second slices over
  369.093 host seconds. It did not reach its PPU PhysX handoff marker. The
  requested 30-second after-handoff slices did not run.
- Exact wait: At emulator time 4:13.032337, the rendering thread shut down
  taskset `0x1f73f00`, which is workload 7. It entered
  `cellSpursJoinTaskset` 168 microseconds later. The nested PPU call then stayed
  at HLE address `0x02003ee4` until the route stopped. No shutdown completion,
  reconciliation, FMOD, or PhysX row followed.
- Race evidence: The last task SPU JIT block loaded about 15 milliseconds after
  join started. The reconciliation runs once before the semaphore is armed. At
  that instant, it can correctly keep the workload bit because the SPU still
  reports workload 7. The function then uses an unlimited semaphore wait, so
  it cannot repeat the reconciliation after the SPU leaves.
- Frame and fatal result: The final diagnostic reported 210 frames and 0.00
  FPS. The targeted VM, native, Vulkan, LLVM, verification, and signal-fault
  scan had zero matches. This is a wait, not a crash.
- Thermal and fan result: The independent watchdog recorded 482 valid samples.
  Fixed silicon ranged from 34.1 to 65.4 C, and junction temperature peaked at
  81.9 C. Every sample reported Smart fan mode `4`. The watchdog completed
  because the package stopped. Final cleanup found no PID or `top` row at 40.1
  C fixed silicon and 41.0 C junction temperature. The saved Custom slider
  value is not a measured or active fan speed.
- Decision: The corrected queue-result diagnostic did not execute. It remains
  device-pending. Do not give queue, HLE, gameplay, FPS, or stability credit,
  and do not run a second route in this device round.

## 248. Retry the narrow shutdown reconciliation after the task exits

- Status: host-pass, device-pending
- Upstream check: The current official RPCS3 `master` source still arms the
  workload event and then calls `sys_semaphore_wait` with an unlimited timeout.
  It has no late reconciliation because the official SPURS kernel supplies the
  completion. The fork needs a narrow retry only for its HLE policy-module
  boundary.
- Change: Only the HLE SPURS route for title `BLUS30357` and workload 7 now
  waits for 20 milliseconds at a time. A timeout runs the existing fail-closed
  reconciliation again. The loop ends on the real completion semaphore. All
  other titles, workloads, and SPURS modes keep the original unlimited wait.
- Safety: Each retry reads every matching SPU current workload ID twice. It
  keeps the status bit for an active SPU, an unknown SPU, a context mismatch,
  or an ID that changes during the read. It clears only a stable non-owner bit
  after shutdown made workload 7 non-runnable. The first timeout writes one
  bounded `Thor TWC SHUTDOWN WAIT RETRY` row. A state change writes the existing
  full reconciliation row.
- Verification: The shutdown-reconciliation contract, the Transformers HLE
  route contract, `git diff --check`, and the Android ARM64 RelWithDebInfo build
  pass. The Thortest symbol-strip task passes. The stripped core is 63,252,856
  bytes and has SHA-256
  `2E1725D761D12C568AF85B5A87FC61D944E6E96C92E03ECDBB92AF2071263CDF`.
  It contains the new retry marker. Its export surface passes with 40 defined
  dynamic symbols, 596 explicit relocations, 392 jump slots, and 44,445 encoded
  relocation bytes.
- Device result: Not run. No device command followed this host repair.
- Next: In a later cool device round, push this exact stripped core without a
  launch. Run one guarded route. Require the timed-retry row, a full
  reconciliation row, workload removal, and later FMOD or PhysX progress. If
  the route reaches PhysX, also require `pc=0x06920 queue_rc=0x00000000` and a
  real PPU `ready after` row before it gets HLE progress credit.

## 249. The timed retry runs but cannot change workload 7

- Status: device-confirmed shutdown blocker, diagnostic successor host-pending,
  not-PhysX, not-gameplay.
- Identity: Capture `20260830-213516-thor-input-custom` used exact stripped
  core SHA-256
  `2E1725D761D12C568AF85B5A87FC61D944E6E96C92E03ECDBB92AF2071263CDF`.
  The source-repair push matched this hash before launch.
- Retry result: The rendering thread shut down taskset `0x1f73f00` and entered
  `cellSpursJoinTaskset` at emulator time 3:41.159. The new 20-millisecond
  timeout wrote `Thor TWC SHUTDOWN WAIT RETRY` at 3:41.179. No full shutdown
  reconciliation, completion event, workload removal, or taskset reuse
  followed. The rendering thread stayed at HLE address `0x02003ee4`.
- Corrected boundary: FMOD taskset `0x11574a80` was created at 3:40.801. Its
  SPU task started at 3:40.901, and its event interpreter ran at 3:41.033.
  These events are before workload-7 join. FMOD presence does not prove that
  the later join returned. The prior inference that the retry passed join was
  incorrect.
- Route result: The after-START controller reported 13 completed slices. Its
  final bounded slice requested a pause after 2.016 seconds, but the control
  API became unreachable. The slice returned after 55.719 seconds without a
  held emulator state. The route rejected itself after 208.781 host seconds.
  It did not reach the PPU PhysX handoff marker or run the requested 30-second
  PhysX slices. The targeted fatal scan had zero matches.
- Thermal and fan result: The independent watchdog recorded 291 valid samples.
  Fixed silicon ranged from 34.5 to 68.2 C, and junction temperature ranged
  from 36.1 to 82.3 C. The watchdog held the process at the 68 C early limit
  and completed after the package stopped. Every sample reported Smart fan
  mode `4`. Direct cleanup found no PID or `top` row and confirmed Smart fan
  mode `4`. The saved Custom slider value is not an active fan speed.
- Decision: The timed loop works, but the fail-closed helper sees no state that
  it can change. Do not clear an active or unknown SPU status bit. Add one
  bounded first-retry snapshot with the workload state, status, event, SPU
  current IDs and PCs, and taskset running, ready, pending, waiting, enabled,
  and signalled masks. This successor does not change shutdown behavior.
- Host successor: The shutdown-reconciliation, shutdown-completion, taskset-
  join, and Transformers route contracts pass. `git diff --check`, the Android
  ARM64 RelWithDebInfo build, and the Thortest symbol-strip task pass. The
  stripped core is 63,254,552 bytes with SHA-256
  `9877BAB6392043E53110D5E0E1486866A159D45BCAD94843EB546B3F49CDA8B9`.
  It contains the new no-change marker. Its export surface passes with 40
  defined dynamic symbols, 596 explicit relocations, 392 jump slots, and
  44,453 encoded relocation bytes. The successor has no device result.
- Acceptance: The next independently cool route must contain the new
  `Thor TWC SHUTDOWN RECONCILE NO CHANGE` row if the retry cannot repair the
  state. If the taskset has no running task and only a stale SPU owner remains,
  use that exact evidence for a narrow idle-owner repair. If a task is active,
  implement or invoke workload preemption before removal. Do not give HLE,
  PhysX, gameplay, FPS, speed, or stability credit yet.

## 250. Real-kernel preemption research does not support a forced join repair

- Status: host research complete, device snapshot still pending.
- Ghidra input: A headless Ghidra 12.0.4 import used processor
  `SPU:BE:128:default` and loaded
  `_research/spurs/spurs_kernel1.spu.bin` at address `0x100`. The 2,048-byte
  input has SHA-256
  `A6382C356D528AFCD9BFD7713174489EC4E21EDDB59FEA2A3B58E30BEAFA7B85`.
  The matching 2,100-byte ELF has SHA-256
  `5B62B86C8979609C33633D53CB0074D1B31A519D5222DEC892F5A19DA00DFB38`.
  The ignored disassembly output is
  `debug-captures/ghidra-kernel1-preemption-20260830/kernel1-full.txt`.
- Kernel result: The selector at `0x310` handles a policy-module poll and a
  kernel selection as separate operations. A poll that selects another
  workload records pending contention. The kernel path commits the selected
  workload and dispatches its policy module. The real kernel contains no write
  to the `CellSpurs::sysSrvPreemptWklId` array.
- Source comparison: `spursSysServiceCleanupAfterSystemWorkload` only consumes
  a victim ID that another path already recorded. It does not select a victim.
  `spursSysServiceEntry` still has the same preempted-workload TODO in this tree
  and in current RPCS3. The public preemption-victim-hints function is a
  separate unimplemented API. These facts do not support writing a victim ID
  or clearing an active task from the PPU join waiter. Current RPCS3 source:
  <https://raw.githubusercontent.com/RPCS3/rpcs3/master/rpcs3/Emu/Cell/Modules/cellSpurs.cpp>.
- Online research: No arXiv result defines this SPURS shutdown transition.
  Sony task-manager material describes task switching through a yield and
  context-switch path. It does not define a PPU join operation that deletes an
  active SPU task. Primary sources:
  <https://patents.google.com/patent/EP1934739A1/en> and
  <https://patents.google.com/patent/EP2312441A2/en>.
- Capture result: The saved route proves that workload-7 task zero started on
  SPU 4 at emulator time 2:48.024. The same SPU started FMOD workload-8 task
  zero at 3:40.901. This proves that SPU 4 left workload 7, but it does not
  prove that task zero did not resume on another SPU before the join at
  3:41.159. The saved trace has no later task mask or complete SPU workload-ID
  census.
- Decision: Keep commit `99338ebd6` unchanged. Do not add a speculative forced
  preemption. The next independently cool device route must collect the bounded
  no-change snapshot. If it shows no running task and a stale owner, repair only
  that idle owner. If it shows an active task, repair the policy-module yield or
  preemption path first.
- Device and fan result: No device command followed this research. The last
  verified cleanup from experiment 249 found no RPCSX process and reported
  Smart fan mode `4`. The Custom slider value `100` is not an active fan-speed
  reading.

## 251. The shutdown snapshot exposes a failed SPU lookup

- Status: device-confirmed lookup failure, host successor passed, not-HLE,
  not-PhysX, not-gameplay.
- Identity: Capture `20260830-221350-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `9877BAB6392043E53110D5E0E1486866A159D45BCAD94843EB546B3F49CDA8B9`.
  The device-side core hash matched after cleanup.
- Route result: The legal START frame passed on slice 7. The bounded after-START
  route reached `stage=PRE-SCHEDULE-SCAN` and then
  `stage=POST-FETCH attempts=1 result=0x0`. The route did not create the PPU
  PhysX thread. It had no PhysX queue, `queue_rc`, or `ready after` row. The
  targeted fatal scan had zero matches.
- Shutdown result: The rendering thread entered `cellSpursJoinTaskset` for
  taskset `0x1f73f00` at emulator time 3:51.026999. The retry ran 20
  milliseconds later. The no-change row reported state `3`, status `0x24`,
  event `0x10`, update and message masks `0xe4`, ready count `1`, contention
  `1`, and taskset workload ID `7`. Task zero had running, ready, and enabled
  mask `0x80000000`; pending, waiting, and signalled were zero.
- Interpretation: Running and ready can both name a selected task in the
  taskset contract, so the mask does not prove a stale task. The decisive value
  is `known=0x00`. Every current workload ID and PC was unknown. The helper used
  direct ID lookup through `CellSpurs::spus`, but the Android status path later
  enumerated six live SPU objects at SPURS address `0x01e97a80`. The helper
  preserved status `0x24` because every owner was unknown. This is the correct
  fail-closed result for a failed observation path.
- Thermal and fan result: The independent watchdog recorded 207 valid samples.
  Fixed silicon ranged from 34.1 to 67.8 C, and junction temperature ranged
  from 35.5 to 87.1 C. Every sample reported Smart fan mode `4`. The controller
  saw one fixed-silicon sample at 68.7 C before it re-paused the process; the
  72 C hard stop was not reached. Final cleanup found no PID or `top` row at
  40.5 C fixed silicon. All Thor debug properties were empty. The saved Custom
  slider value is not an active fan speed.
- Host successor: The reconciliation now enumerates live SPU objects, as the
  working Android status path does. It accepts an object only when the host
  SPURS address and local-store context both match. It keeps a status bit for
  an active, changing, or unknown owner. It can clear only a stable non-owner
  bit after shutdown. It does not clear a task or force preemption.
- Verification: The shutdown-reconciliation, shutdown-completion, taskset-join,
  and Transformers route contracts pass. `git diff --check`, Android ARM64
  RelWithDebInfo, and the Thortest strip task pass. The stripped core is
  63,254,248 bytes with SHA-256
  `BCEBB365BC0CEE564FCA7EC3B5BF61F6FCFEE49D93FD05E387B1323D23100C68`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It has no device result.
- Next: In a later independently cool round, push this exact core without a
  launch. Require a nonzero known-SPU mask, full shutdown reconciliation,
  taskset join return, workload removal, and safe taskset reuse. If it reaches
  PhysX, also require `pc=0x06920 queue_rc=0x00000000` and a real PPU
  `ready after` row. Do not claim HLE, gameplay, FPS, speed, or stability yet.

## 252. The live scan clears shutdown and exposes a false PhysX boundary

- Status: shutdown repair device-confirmed, PhysX boundary successor host-pass,
  failed, not-gameplay, not-comparable for FPS.
- Identity: Capture `20260830-223448-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `BCEBB365BC0CEE564FCA7EC3B5BF61F6FCFEE49D93FD05E387B1323D23100C68`.
  The legal START frame passed on slice 7.
- Shutdown result: The rendering thread entered the workload-7 taskset join at
  emulator time 4:13.361594. The live scan reported `known=0x3f` and reduced
  status `0x1f` to the real active mask `0x10`. The 20-millisecond retry kept
  SPU 4 as the active owner. The SPURS handler emitted the shutdown-completion
  event at 4:13.430050. The rendering thread returned and recreated the same
  taskset address with a new workload ID 7 at 4:13.517326. This proves join,
  workload removal, and safe taskset reuse.
- PhysX result: The title created the PPU PhysX thread, initialized six queues,
  and created task zero from ELF `0x018c1000` in taskset `0x1ec4700`. The
  interpreter entered at PC `0x06800` and left at PC `0x06960` after 190
  microseconds. The PPU queue pop timed out after 6,000,012 microseconds and
  returned `0x8041090A`. It had no `ready after` row. The error path later
  produced one RSX dead-FIFO fatal.
- Static result: Ghidra shows that PC `0x068f4` calls the queue function at
  `0x06960`. The configured fallback end was `0x06920`. The interpreter
  therefore stopped at the callee entry before it executed the queue function.
  The logged `queue_rc=0` was not a queue result. A simple range cannot include
  the higher-address callee and stop at the lower-address caller continuation.
- Host successor: The SPU fallback now has an exact stop PC. The PhysX route
  interprets through `0x06e50` with range `0x030a8..0x06e54`, then stops when
  control returns to PC `0x06920`. Register `r3` still contains the terminal
  queue result at this point. The field resets on normal interpreter exit and
  on JIT-gateway escape.
- Verification: The Transformers route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. `git diff --check`, the
  Android ARM64 RelWithDebInfo build, the Thortest strip task, the binary marker
  check, and the export-surface check pass. The new stripped core is 63,253,192
  bytes with SHA-256
  `6C54F49715A4A18180BD6CF7722A32E1B7FE8C64C08393D812467A3F24F514AC`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It has no device result.
- Thermal and fan result: The watchdog recorded 268 valid samples. Fixed
  silicon ranged from 34.5 to 68.2 C, and junction temperature ranged from
  35.1 to 84.3 C. Every sample reported Smart fan mode `4`. Final cleanup found
  no PID or RPCSX `top` row at 37.7 C fixed silicon. The saved Custom slider
  value is not an active fan speed.
- Next: In a later independently cool route, push the exact successor without
  a launch. Require `pc=0x06920 queue_rc=0x00000000`, a real PPU `ready after`
  row, no queue-failure row, no fatal error, and progress beyond PhysX startup.
  Do not claim HLE, gameplay, FPS, speed, or stability before these gates pass.

## 253. The exact-stop run stops in the earlier FMOD owner route

- Status: device-confirmed earlier blocker, host successor passes, not-PhysX,
  not-gameplay, not-comparable for FPS.
- Identity: Capture `20260830-225248-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `6C54F49715A4A18180BD6CF7722A32E1B7FE8C64C08393D812467A3F24F514AC`.
  The legal START frame passed on slice 6.
- Route result: The after-START handoff completed 30 two-second slices in
  359.968 host seconds. It did not create the PPU PhysX thread. Therefore, the
  exact PhysX stop PC did not run and this capture gives no PhysX queue result.
- Shutdown result: At emulator time 3:19.455, workload 7 reported
  `known=0x3f`, status `0x3b->0x10`, and active mask `0x10`. The SPURS handler
  emitted the completion event at 3:19.468. The rendering thread returned from
  the join and recreated taskset `0x1f73f00` as workload 7 at 3:19.525. This
  result reconfirms shutdown, join return, workload removal, and safe reuse.
- Audio result: The audio queue woke PPU `0x0100000c`. The main thread returned
  from mutex `0x95008b00`, then waited on mutex `0x95008d00` with the same PPU
  as owner. The candidate row reported owner state zero. It did not emit a
  `DEFERRED SCAN` row and fell through to a dependency wake with no saved
  dependency. Later census rows still contained the FMOD PPU. The main thread
  and the FMOD receiver stayed at HLE PC `0x022254ec` with link register
  `0x00e28c5c`. The capture had no targeted fatal error.
- Cause: The direct PPU ID lookup and name predicate did not give the deferred
  candidate route a usable owner at the exact second-lock boundary. The live
  PPU census still found this thread. The host successor now selects the PPU
  by ID from the live PPU table. It uses this path for the primary owner, a
  discovered dependency owner, and a dependency retry. The existing title,
  thread, link-register, and mutex gates remain. The change does not modify a
  guest mutex word or queue.
- Verification: The Transformers route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. `git diff --check`, the
  Android ARM64 RelWithDebInfo build, the Thortest strip task, the binary marker
  check, and the export-surface check pass. The new stripped core is 63,253,448
  bytes with SHA-256
  `3023A5C5EB24EDA5D32E6F94B643FDE791E8E1D641AC3194BF88C53D0BD8F5B9`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It has no device result.
- Thermal and fan result: The watchdog recorded 409 valid samples. Fixed
  silicon ranged from 34.1 to 67.8 C, and junction temperature ranged from
  35.1 to 77.5 C. Every sample reported Smart fan mode `4`. Final cleanup found
  no PID or RPCSX `top` row at 40.1 C fixed silicon. The saved Custom slider
  value is not an active fan speed.
- Next: In a later independently cool route, require `owner_live=1` for mutex
  `0x95008d00`, a `DEFERRED SCAN` row, and progress beyond the FMOD lock chain.
  If the route reaches PhysX, also require
  `pc=0x06920 queue_rc=0x00000000`, a real PPU `ready after` row, no
  queue-failure row, and no fatal error. Do not claim HLE, gameplay, FPS, speed,
  or stability before these gates pass.

## 254. A reserved owner caused a false route stop

- Status: route-tooling correction, host successor passed, not-PhysX,
  not-gameplay, not-comparable for FPS.
- Identity: Capture `20260830-231942-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `3023A5C5EB24EDA5D32E6F94B643FDE791E8E1D641AC3194BF88C53D0BD8F5B9`.
  The legal START frame passed on slice 6.
- False-stop result: The after-START controller completed one two-second slice
  and matched custom text `owner_live=0 owner_state=0x0`. The full row named
  owner `0xfffffffd`. This is `lwmutex_reserved`, not a PPU ID. Experiment 214
  already proves that this value is the normal guest baton during a handoff.
  The controller stopped on a legal value and incorrectly reported a stale
  signal repair failure.
- Audio result: The first FMOD mutex was `0x95008c00`. Its live owner was PPU
  `0x0100000c`. The owner wake changed state `0x224->0x4`. The main PPU then
  returned, unlocked the mutex, and woke the FMOD receiver. The receiver
  consumed queued events and continued its receive loop. The later candidate
  mutex was `0x95008e00` with the reserved owner. The audio sender later filled
  its two-entry queue because the route stopped before this new boundary could
  be classified.
- Mutex-ID correction: The prior run used first and second IDs `0x95008b00`
  and `0x95008d00`. This run used `0x95008c00` and `0x95008e00`. The fixed
  second ID was boot-dependent. The host successor now gates the deferred scan
  on the exact live FMOD PPU ID and thread name. It records the observed mutex
  ID for the later unlock trace. It does not act on a reserved owner.
- Controller correction: The route keeps the self-cycle failure marker and now
  adds exact dead-owner marker `owner=0x100000c owner_live=0`. It rejects a
  broad dead-owner marker that does not name the FMOD PPU. This prevents a
  normal reserved-owner handoff from ending the route.
- Route result: The route did not create the PPU PhysX thread. It had no PhysX
  queue result and no targeted fatal error. Startup samples of 3.80 and 5.90
  FPS are not comparable gameplay data and get no speed credit.
- Thermal and fan result: The independent watchdog recorded 161 valid samples.
  Fixed silicon ranged from 34.1 to 64.6 C, and junction temperature ranged
  from 35.1 to 76.7 C. Every sample reported Smart fan mode `4`. Cleanup found
  no RPCSX PID. The saved Custom slider value `100` was inactive and is not a
  fan-speed measurement.
- Verification: The Transformers route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. The broad-marker
  rejection test and PowerShell parsing pass. `git diff --check`, Android ARM64
  RelWithDebInfo, the Thortest strip task, the binary marker check, and the
  export-surface check pass. The stripped core is 63,253,448 bytes with
  SHA-256
  `0B578A88B419D7B5D3CF580F3D728F62A91FA3E1E72A673EC770E41DA665F206`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes.
- Next: Push this exact core without a launch in a later independently cool
  round. Do not require a fixed mutex ID. Let a reserved-owner handoff continue.
  If a live FMOD owner appears, require a `DEFERRED SCAN` row for its observed
  ID. Then require progress into PhysX, exact stop
  `pc=0x06920 queue_rc=0x00000000`, a real PPU `ready after` row, no queue
  failure, and no fatal error before any HLE or gameplay claim.

## 255. The live FMOD route uses a composed PPU name

- Status: device-confirmed cause, host successor passed, not-PhysX,
  not-gameplay, not-comparable for FPS.
- Identity: Capture `20260830-234043-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `0B578A88B419D7B5D3CF580F3D728F62A91FA3E1E72A673EC770E41DA665F206`.
  The legal START frame passed on slice 7.
- Audio result: At emulator time 4:09.245, the main PPU found live FMOD PPU
  `0x0100000c` as owner of runtime lwmutex `0x95008e00`. The owner state was
  `0x4`. The row reported `owner_live=1`, but no `DEFERRED SCAN` row followed.
  The code used the plain `candidate` chain action. The audio queue then filled
  its two entries and returned `0x8001000a` on later sends.
- Persistent state: From emulator time 4:11 through 8:11, repeated PPU samples
  put the main PPU and the FMOD receiver at HLE PC `0x022254ec` with link
  register `0x00e28c5c`. The title did not create the PPU PhysX thread. No
  targeted fatal error occurred.
- Cause: `ppu_thread::thread_name_t::operator std::string()` builds the name as
  `PPU[0x<id>] <guest-name>`. Four audio-owner checks compared this composed
  name with only `FMOD libAudio event receive thread`. These checks could not
  match. This disabled the deferred candidate scan, the live dependency scan,
  the stale-signal cleanup, and the guarded self-cycle repair.
- Host successor: One helper now requires PPU ID `0x0100000c` and the exact
  composed name
  `PPU[0x100000c] FMOD libAudio event receive thread`. All four paths use this
  helper. The title gate and all existing state checks remain. The change does
  not change a guest mutex word or queue directly.
- Route result: The controller completed 20 two-second after-START slices. Its
  last pause request timed out when the control API became unavailable, and it
  stopped the package. This controller stop is not a core fatal error.
- Thermal and fan result: The watchdog recorded 381 valid samples. Fixed
  silicon ranged from 34.1 to 68.2 C, and junction temperature ranged from
  35.5 to 85.5 C. Every sample reported Smart fan mode `4`. Cleanup found no
  RPCSX PID. Final fixed silicon was 38.1 C.
- Verification: The Transformers route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. PowerShell parsing,
  `git diff --check`, the Android ARM64 RelWithDebInfo build, the Thortest strip
  task, and the export-surface check pass. The stripped core is 63,253,848
  bytes with SHA-256
  `88B8F528E6154F832473B020B74AC80F5A979938D5F5872769C3C6D8571950E8`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes.
- Next: Push this exact core without a launch. In a later independently cool
  route, require the live candidate and a `DEFERRED SCAN` row for its observed
  mutex ID. Then require progress beyond the FMOD lock chain. If the title
  reaches PhysX, require `pc=0x06920 queue_rc=0x00000000`, a real PPU
  `ready after` row, no queue failure, and no fatal error. Do not claim HLE,
  gameplay, FPS, speed, or stability before these gates pass.

## 256. The PPU timeout ends just before the PhysX producer

- Status: device-confirmed PhysX boundary, host successor passed, not-gameplay,
  not-comparable for FPS.
- Identity: Capture `20260831-000215-thor-input-custom` used installed APK
  SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and exact stripped core SHA-256
  `88B8F528E6154F832473B020B74AC80F5A979938D5F5872769C3C6D8571950E8`.
  The legal START frame passed on slice 7.
- Audio result: Runtime mutex `0x95008b00` completed its handoff. The direct
  owner wake changed PPU `0x0100000c` from state `0x224` to `0x304`. The FMOD
  receiver unlocked the mutex, consumed audio events, and continued its receive
  loop. The run used the normal dependency-scan miss path. It did not enter the
  deferred candidate path. Therefore, this run does not test the composed-name
  repair.
- PhysX result: The title created the PPU PhysX thread at emulator time
  4:29.795. It created six queues and taskset `0x1ec4700`. It created task 0
  from ELF `0x018c1000` at 4:49.879. SPU 3 entered the exact startup
  interpreter at PC `0x06800` at 4:49.905.
- Exact boundary: The PPU queue wait on `0x1eccb80` reported a timeout at
  5:31.853203 after 41,973,741 us. The SPU interpreter reached the exact stop
  PC `0x06920` at 5:31.853390, only 187 us later. Register 3 contained success
  value `0x00000000`. The exact SPU path took 41,948,057 us. The title then
  reported queue-pop failure `0x8041090A` and started teardown. This is not a
  gameplay or full-HLE result.
- Cause: The PPU did not run its polling loop while the cold SPU interpreter
  used the host. When the PPU ran again, its normal deadline had passed. It
  returned BUSY immediately before the real producer made the queue result
  visible. The exact timing and the successful SPU queue return support this
  scheduling cause.
- Host successor: The exact Transformers PhysX interpreter now publishes an
  active-producer flag. The PPU keeps its normal 6,000,000 us wait. It can wait
  longer only while this exact producer is active, and it has an absolute
  60,000,000 us limit. A release store after the interpreter and an acquire
  load in the PPU order the real queue result. The path does not fabricate data.
  A contract rejects use of this flag in the generic SPU interpreter fallback.
- Verification: The Transformers route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. `git diff --check`, the
  Android ARM64 RelWithDebInfo build, the Thortest strip task, and the
  export-surface check pass. The new stripped core is 63,253,912 bytes with
  SHA-256
  `08E9E8448D520F8F307E8F5D4AFF4D601B84F010CE361C670780D4BF193ABE25`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It has no device result.
- Thermal and fan result: The controller recorded a peak fixed-silicon
  temperature of 69.5 C. The independent watchdog recorded 285 valid samples.
  Fixed silicon ranged from 34.5 to 69.1 C, and junction temperature ranged
  from 35.9 to 85.9 C. Every watchdog sample reported Smart fan mode `4`.
  Cleanup found no RPCSX PID or `top` row. Final fixed silicon was 38.9 C.
- Next: In the next independently cool route, push this exact core without a
  launch, then run one guarded route. Require a real `ready after` row, no queue
  failure, no fatal error, and progress beyond PhysX startup. Require correct
  gameplay before any HLE claim. Require a matched sustained gameplay result
  before a 30 FPS claim.

## 257. The PhysX proof window ended before the producer

- Status: route-tooling correction, exact core still under test, not-gameplay,
  not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-002609-thor-input-strict-cool-gate` verified installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
  Fixed silicon was 32.9 C, battery was 22.0 C, and skin was 30.0 C. The gate
  force-stopped the package and did not launch it.
- Core identity: Push capture
  `20260831-002700-transformers-physx-producer-aware-dev-core-push` copied the
  63,253,912-byte stripped core from commit `a2ca70f81` without a launch. The
  local, manifest, staged, and app-internal core SHA-256 is
  `08E9E8448D520F8F307E8F5D4AFF4D601B84F010CE361C670780D4BF193ABE25`.
  A direct app-internal `sha256sum` matched. RPCSX had no PID before launch, and
  fan mode was Smart `4`.
- Route identity: Capture `20260831-002801-thor-input-custom` used that APK and
  core. The legal START frame passed on slice 6. Visual inspection shows the
  correct Unreal and PhysX legal screen with no visible corruption. Its 22.25
  FPS overlay is startup data, not a gameplay measurement.
- Route progress: The FMOD mutex on runtime ID `0x95008c00` completed the
  dependency-scan-miss and direct-owner-wake route. The title created the PPU
  PhysX thread at emulator time 3:44.905. It created all six queues and task 0
  from ELF `0x018c1000`. SPU 5 entered the exact startup interpreter at PC
  `0x06800` at 4:04.331.
- Under-budget result: The after-handoff controller allowed two 30-second
  slices. The first part of this window included 19.426 seconds of PhysX PPU
  setup before the SPU interpreter started. The controller paused at 4:43.380,
  when the interpreter had run for 39.047 seconds. The prior exact producer
  needed 41.948 seconds. The proof window ended about 2.901 seconds too early.
- Emulator result: At the final sample, the PhysX PPU still waited in
  `cellSpursQueuePopBody` at HLE PC `0x02003e6c`, and the exact SPU interpreter
  was still active. The log has no interpreter-leave row, no queue `ready after`
  row, no queue timeout, no `0x8041090A` queue failure, and no targeted fatal
  error. Therefore, this run does not pass or reject the producer-aware core.
- Harness repair: The route now requires at least 90 active seconds when it
  targets the exact PhysX handoff and queue marker. This maximum includes the
  observed PPU setup and the producer's 60-second safety limit. An under-budget
  route now fails on the host before ADB contact. The contract executes and
  rejects the former two-by-30-second shape.
- Thermal and fan result: The controller maximum was 68.7 C fixed silicon. The
  independent watchdog recorded 253 valid samples. Fixed silicon ranged from
  34.5 to 69.1 C, and junction temperature ranged from 36.3 to 83.9 C. Every
  sample reported Smart fan mode `4`. The saved Custom slider value `100` was
  inactive and is not a fan-speed measurement. Cleanup found no PID or RPCSX
  `top` row at 38.5 C fixed silicon, and all debug properties were cleared.
- Next: Do not launch again in this cool round. In the next independently cool
  round, use three 30-second after-handoff slices. The marker can stop the route
  early. Require the interpreter-leave row, a real queue `ready after` row, no
  `0x8041090A`, no fatal error, and progress beyond PhysX startup. Require
  correct gameplay before an HLE claim and matched sustained gameplay before a
  30 FPS claim.

## 258. A late process hold caused a false route failure

- Status: route-controller cause fixed, exact core still under test,
  not-gameplay, not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-004104-thor-input-strict-cool-gate` passed at 34.5 C fixed silicon.
  It verified installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`,
  force-stopped the package, and did not launch it. A direct app-internal hash
  then matched exact stripped core SHA-256
  `08E9E8448D520F8F307E8F5D4AFF4D601B84F010CE361C670780D4BF193ABE25`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-004150-thor-input-custom` used that APK and
  core. The legal START frame passed on slice 6. Visual inspection shows the
  correct Unreal and PhysX legal screen with no visible corruption. Its 28.34
  FPS overlay is startup data, not a gameplay measurement.
- Emulator result: Shutdown reconciliation changed work item 7 from status
  `0x24` to `0x04`, and the shutdown completion event fired. The FMOD receiver
  signaled runtime mutex `0x95008e00`. The main PPU then waited on the related
  FMOD lock path. The title did not create the PPU PhysX thread. Therefore, the
  three-slice PhysX proof window did not start, and this run does not test the
  producer-aware core. No targeted core fatal error occurred.
- Controller failure: The first six after-START slices ended in a controlled
  pause. On slice 7, the emulator accepted pause mark 7. Its control response
  took about 11.3 seconds. The one-second request timed out and started the
  process-hold fallback. The main controller read the fallback result before
  the deadline thread published it. It then sent a duplicate pause, which
  produced mark 8, and waited on the in-process API while the fallback owned
  the process. The route stopped the package after 56.844 host seconds. This is
  a controller race, not a proven core failure.
- Host repair: Commit `df99a3f4d` reads the shared process-hold result again at
  each control boundary. A completed late hold now ends the slice as a valid
  process-held pause. The controller also does not send a second pause while
  the deadline request or its process fallback is pending. The Python
  state-machine test models a hold that completes after the first join.
- Verification: The Python guarded-slice state-machine test, the PowerShell
  fixed-silicon contract, Python compilation, and `git diff --check` pass.
- Thermal and fan result: The controller maximum was 67.4 C fixed silicon. The
  independent watchdog recorded 248 valid samples. Fixed silicon ranged from
  34.5 to 69.5 C, and junction temperature ranged from 36.3 to 82.7 C. Every
  watchdog sample reported Smart fan mode `4`. Cleanup found no PID or RPCSX
  `top` row at 38.1 C fixed silicon, and all debug properties were cleared. The
  saved Custom slider value `100` is not a current fan-speed measurement.
- Next: Do not launch again in this cool round. In the next independently cool
  round, verify the same APK and core identities. Run the corrected route with
  three 30-second after-handoff slices. Require the interpreter-leave row, a
  real queue `ready after` row, no `0x8041090A`, no fatal error, and progress
  beyond PhysX startup. Require correct gameplay before an HLE claim and a
  matched sustained gameplay result before a 30 FPS claim.

## 259. The PhysX safety clock included process holds

- Status: device-confirmed timeout cause, host successor passed, not-HLE,
  not-gameplay, not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-005739-thor-input-strict-cool-gate` passed at 33.3 C fixed silicon.
  It verified installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`,
  force-stopped the package, and did not launch it. A direct app-internal hash
  matched exact stripped core SHA-256
  `08E9E8448D520F8F307E8F5D4AFF4D601B84F010CE361C670780D4BF193ABE25`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-005831-thor-input-custom` used that APK and
  core. The legal START frame passed on slice 7. Visual inspection shows the
  correct Unreal and PhysX legal screen at 27.52 FPS. This is startup data, not
  a gameplay measurement. The on-device late-hold controller repair passed:
  the old false slice-7 stop did not return.
- PhysX result: The title created the PPU PhysX thread, all six queues, and task
  0 from ELF `0x018c1000`. SPU 5 entered the exact interpreter at PC `0x06800`
  at emulator time 4:55.062066. The PPU reported a timeout at 6:16.369805 after
  81,357,814 us while the exact producer flag was still active. The SPU reached
  PC `0x06920` at 6:16.379459, only 9,654 us later, with real queue result
  `0x00000000`. Its logged wall time was 81,317,394 us. The title then reported
  queue failure `0x8041090A` and entered teardown.
- Visual boundary: The saved boundary frame shows the Transformers loading
  screen. Its 0.10 FPS overlay includes the long paused interval and is not a
  gameplay measurement. The queue failure rejects this route despite the
  later visual. It is not correct gameplay or HLE.
- Cause: All three long slices ended in a controlled process hold. The
  60-second producer safety limit used the host wall clock, so process-held
  thermal and cooldown intervals consumed it while neither the PPU nor SPU
  could run. On resume, the PPU saw the expired wall-clock limit before the SPU
  got its next host time. The 9.654 ms gap proves the same final scheduling race
  at a pause-inflated wall time.
- Route evidence bug: The old route matched the shared
  `Thor Transformers PhysX queue startup wait:` prefix. It accepted the timeout
  row as its requested marker before it classified `0x8041090A`. This was a
  false route success, not an emulator success.
- Host successor: Commit `ce7138c89` keeps the normal 6-second wall-clock wait.
  While the exact, title-gated producer remains active, it applies a limit of
  600,000 completed 100 us poll waits. A stopped process cannot consume this
  budget. The wait still ends when the exact producer becomes inactive, and it
  does not fabricate queue data. The route now has separate `startup ready`
  and `startup timeout` markers. It rejects the timeout marker and
  `0x8041090A`.
- Verification: The focused HLE route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. PowerShell parsing,
  `git diff --check`, the ARM64 RelWithDebInfo build, the Thortest strip task,
  the binary marker check, and the export-surface check pass. The next stripped
  core is 63,254,088 bytes with SHA-256
  `2A9CB8AB9EE09F6C9DBA91E66680976220287A1D1A2DB62FA54AFF3F66FE47B1`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It has no device result.
- Thermal and fan result: The controller maximum was 68.7 C fixed silicon. The
  independent watchdog recorded 325 valid samples. Fixed silicon ranged from
  34.5 to 69.1 C, and junction temperature ranged from 35.5 to 85.5 C. Every
  watchdog sample reported Smart fan mode `4`. Cleanup found no PID or RPCSX
  `top` row at 38.9 C fixed silicon, and all debug properties were cleared. The
  saved Custom slider value `100` is not a current fan-speed measurement.
- Next: Do not launch again in this cool round. In the next independently cool
  round, push exact core `2A9CB8AB...FE47B1` without a launch and verify its
  app-internal hash. Run one guarded route. Require the new `startup ready`
  row, exact `pc=0x06920 queue_rc=0x00000000`, no timeout, no `0x8041090A`, no
  fatal error, and progress beyond PhysX startup. Require correct gameplay
  before an HLE claim and a matched sustained gameplay result before a 30 FPS
  claim.

## 260. Queue readiness now wins over the timeout

- Status: final host successor passed, no device result, not-HLE, not-gameplay,
  not-comparable for FPS.
- Ordering repair: Commit `1b12997d1` checks the real PhysX queue state before
  it makes the timeout decision. Therefore, an item that the SPU has published
  always produces the `startup ready` row, even if the exact producer flag has
  just become inactive. The code does not create or change queue data.
- Contract repair: The focused route contract requires the queue readiness
  check to occur before the timeout decision. This prevents a later edit from
  restoring the rejection race.
- Verification: The focused HLE route, shutdown-reconciliation,
  shutdown-completion, and taskset-join contracts pass. `git diff --check`, the
  ARM64 RelWithDebInfo build, the Thortest strip task, the binary marker check,
  and the export-surface check pass.
- Binary identity: The final stripped successor is 63,254,024 bytes with
  SHA-256
  `6DBD8E8F1975A95842E9C30D408CADCF043F8CDB4F52F7F249B458CC434189B6`.
  It has both the `startup ready` and `startup timeout` markers. Its export
  surface has 40 defined dynamic symbols, 596 explicit relocations, 392 jump
  slots, and 44,453 encoded relocation bytes. The earlier
  `2A9CB8AB...FE47B1` build is obsolete.
- Next: Do not launch again in the previous cool round. In the next
  independently cool round, push exact core `6DBD8E8F...189B6` without a
  launch and verify its app-internal hash. Run one guarded route. Require the
  `startup ready` row, exact `pc=0x06920 queue_rc=0x00000000`, no timeout, no
  `0x8041090A`, no fatal error, and progress beyond PhysX startup. Require
  correct gameplay before an HLE claim and a matched sustained gameplay result
  before a 30 FPS claim.

## 261. The watchdog hold still counted as active slice time

- Status: core timeout repair passed its boundary, route accounting repaired,
  not-HLE, not-gameplay, not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-012342-thor-input-strict-cool-gate` passed at 32.9 C fixed silicon.
  Battery temperature was 22.0 C, and skin temperature was 30.0 C. The gate
  force-stopped RPCSX and did not launch it.
- Artifact identity: Push capture
  `20260831-012430-transformers-physx-poll-budget-dev-core-push` copied the
  63,254,024-byte stripped core without a launch. Its local, staged, manifest,
  and app-internal SHA-256 is
  `6DBD8E8F1975A95842E9C30D408CADCF043F8CDB4F52F7F249B458CC434189B6`.
  Installed APK SHA-256 is
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-012556-thor-input-custom` used those exact
  artifacts. The legal START frame passed on slice 7. Visual inspection shows
  the correct Unreal and PhysX legal screen without visible corruption. Its
  29.58 FPS overlay is startup data, not a gameplay measurement.
- PhysX result: The PPU PhysX thread was created at emulator time 4:40.013587.
  The title created all six queues and task 0 from ELF `0x018c1000`. SPU 4
  entered the exact interpreter at PC `0x06800` at 5:00.446227. At the last
  performance sample at 6:26.234596, the PPU still waited on queue `0x1eccb80`
  and the SPU producer had not left the interpreter.
- Core boundary: The log has no `startup ready` row, no `startup timeout` row,
  no `0x8041090A` queue failure, and no targeted fatal error. The final core
  does not repeat the pause-inflated timeout. The missing producer completion
  still rejects HLE and gameplay.
- Route cause: The three nominal 30-second slices each ended in a process hold.
  The independent watchdog held RPCSX three times. The controller released two
  holds at the start of later slices, and the third hold stayed active until
  cleanup. It incorrectly reported about 93 seconds as active because its
  deadline continued while the watchdog owned `SIGSTOP`.
- Host repair: Commit `3a08a9c89` adopts an independent watchdog hold when the
  same fixed-silicon domain approaches the slice ceiling. It cancels the old
  deadline, ends the current slice, cools while stopped, and resumes in a new
  slice. It does not call the stopped in-process pause API. Normal slices now
  also report active and host elapsed time.
- Verification: The guarded-slice state-machine test models the independent
  hold and stale-deadline cancellation. It passes with Python compilation, the
  fixed-silicon guard contract, the device thermal-guard contract, the focused
  Transformers HLE route contract, and `git diff --check`.
- Thermal and fan result: The route maximum was 68.7 C fixed silicon. The
  independent watchdog recorded 327 valid samples. Fixed silicon ranged from
  34.5 to 68.7 C, and junction temperature ranged from 35.9 to 86.7 C. Every
  sample reported Smart fan mode `4`. No hard thermal stop occurred. Cleanup
  found no PID or RPCSX `top` row at 38.5 C fixed silicon, and all debug
  properties were cleared at 37.7 C. The saved Custom slider value `100` is not
  a current fan-speed measurement.
- Next: Do not launch again in this cool round. In the next independently cool
  round, verify the same installed APK and core identities. Use the corrected
  controller and the default 32 after-handoff slices; do not restore the
  three-slice override. Keep the 240-second host limit. Require `startup ready`,
  exact `pc=0x06920 queue_rc=0x00000000`, no timeout, no `0x8041090A`, no fatal
  error, and progress beyond PhysX startup. Require correct gameplay before an
  HLE claim and matched sustained gameplay before a 30 FPS claim.

## 262. The PhysX proof now uses measured active time

- Status: host controller correction passed, installed core unchanged, no new
  device result, not-HLE, not-gameplay, not-comparable for FPS.
- Active budget: Commit `4ce150e0a` adds the measured active time from each
  completed slice. The exact PhysX route stops after 90 seconds of measured
  runnable time if the queue marker does not arrive. Watchdog-held cooldown
  time does not consume this budget. The result records active and host elapsed
  totals.
- Slice budget: The route now requires at least 32 after-handoff slices before
  ADB contact. It rejects the old three-slice override. A thermal hold can end
  a nominal slice early, so the larger count lets the controller cool and
  resume until the marker or active-time limit. The host limit stays 240
  seconds.
- Verification: The guarded-slice state-machine test covers the active budget
  and passes with Python compilation, the fixed-silicon guard contract, the
  focused Transformers HLE route contract, and `git diff --check`.
- Artifact state: This is a host-only change. The installed core remains exact
  SHA-256
  `6DBD8E8F1975A95842E9C30D408CADCF043F8CDB4F52F7F249B458CC434189B6`.
  It needs no rebuild or push.
- Next: Do not launch again in the previous cool round. In the next
  independently cool round, verify the installed APK and core identities. Use
  the corrected route without `-SliceAfterHandoffMaxSlices 3`; the default is
  32. Require `startup ready`, exact `pc=0x06920 queue_rc=0x00000000`, no
  timeout, no `0x8041090A`, no fatal error, and progress beyond PhysX startup.
  Require correct gameplay before an HLE claim and matched sustained gameplay
  before a 30 FPS claim.

## 263. Measured active time proves a PhysX SPU producer stall

- Status: device-confirmed producer stall, host diagnostic successor passed,
  not-HLE, not-gameplay, not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-014518-thor-input-strict-cool-gate` passed at 33.3 C fixed silicon.
  Battery temperature was 22.0 C, and skin temperature was 30.0 C. The gate
  force-stopped RPCSX and did not launch it. A direct check then verified
  installed APK SHA-256
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`
  and app-internal core SHA-256
  `6DBD8E8F1975A95842E9C30D408CADCF043F8CDB4F52F7F249B458CC434189B6`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-014653-thor-input-custom` used those exact
  artifacts. The legal START frame passed on slice 7. Visual inspection shows
  the correct Unreal and PhysX legal screen without visible corruption. Its
  29.15 FPS overlay is startup data, not a gameplay measurement.
- PhysX result: The PPU PhysX thread was created at emulator time 4:13.142665.
  The title created all six queues and task 0 from ELF `0x018c1000`. SPU 0
  entered the exact startup interpreter at PC `0x06800` at 4:31.814552. The PPU
  then remained in `cellSpursQueuePopBody` on queue `0x1eccb80` through the
  final sample at 7:44.239728.
- Active-time result: Fourteen after-handoff slices supplied 91.533 seconds of
  measured active time over 208.547 seconds of host time. The result stopped
  on the 90-second active budget. It did not stop on the 240-second host limit
  or the 32-slice limit. The log has no interpreter-leave row, no `startup
  ready` row, no `startup timeout` row, no `0x8041090A` queue failure, and no
  targeted fatal error. This proves a real SPU producer stall. It is not a
  route-accounting failure.
- Diagnostic gap: This route enabled the PPU PC census, but it did not enable
  the SPU PC census. The retained Ghidra result defines the interpreted startup
  chain and queue reservation path, but it cannot identify the live loop
  without the missing PC. Do not change queue semantics from this run.
- Host successor: Commit `c6af30864` makes the exact title-gated startup
  interpreter activate its existing SPU PC census without a second property.
  The census records up to 192 half-second samples, including the opcode,
  registers, MFC state, and an exact-interpreter flag. It observes state only.
  It does not change the queue, reservation, task, or scheduler.
- Verification: The focused Transformers HLE route, shutdown reconciliation,
  shutdown completion, and taskset-join contracts pass. `git diff --check`,
  the ARM64 RelWithDebInfo build, the Thortest strip task, the binary marker
  check, and the export-surface check pass. The host-only stripped core is
  63,254,024 bytes with SHA-256
  `F51241CDF9EF6841F529540B35811AD38436810742CD027E8306068512D799FA`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It is not installed.
- Thermal and fan result: The slice controller recorded a 71.5 C maximum. The
  independent watchdog recorded 387 valid samples, 14 holds, 13 releases, a
  70.3 C sampled maximum, and no hard stop. Every sample reported Smart fan
  mode `4`. Cleanup found no PID or RPCSX `top` row at 40.1 C fixed silicon,
  and all 69 debug properties were cleared at 40.5 C. The saved Custom slider
  value `100` is not a current fan-speed measurement.
- Next: Do not launch again in this cool round. In a later independently cool
  round, push exact core `F51241CD...799FA` without a launch and verify its
  app-internal hash. Run the same guarded route once. If the queue does not
  become ready, use its persistent `Thor PHYSX PC` rows to select the exact
  Ghidra function and make one semantic repair. If it becomes ready, require
  exact `pc=0x06920 queue_rc=0x00000000`, no timeout, no `0x8041090A`, no fatal
  error, and progress beyond PhysX startup. Require correct gameplay before an
  HLE claim and a matched sustained gameplay result before a 30 FPS claim.

## 264. The PhysX startup wait held the PPU memory lock

- Status: exact device lock cycle and host semantic repair, not-HLE,
  not-gameplay, not-comparable for FPS.
- Cold gate: No-boot capture
  `20260831-020900-thor-input-strict-cool-gate` passed at 33.3 C fixed silicon.
  Battery temperature was 22.0 C, and skin temperature was 30.0 C. The gate
  force-stopped RPCSX and did not launch it.
- Artifact identity: Push capture
  `20260831-020940-transformers-physx-pc-census-dev-core-push` installed the
  63,254,024-byte diagnostic core without a launch. Its app-internal SHA-256
  was
  `F51241CDF9EF6841F529540B35811AD38436810742CD027E8306068512D799FA`.
  Installed APK SHA-256 was
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-021045-thor-input-custom` used those exact
  artifacts. The legal START frame passed on slice 7. The PPU PhysX thread was
  created at emulator time 4:36.440282. At 4:57.289506, it initialized queue
  `0x01eccb80`. It created task 0 from ELF `0x018c1000` at 4:57.289553. SPU 2
  entered the exact startup interpreter at PC `0x06800` at 4:57.312965.
- PC census: The automatic census recorded 131 samples from 4:57.737111 through
  8:47.238054. Every sample was at PC `0x06cf0`, opcode `0x21a00abe`, with MFC
  command `0xb4` and EA `0x01eccb80`. The register state, mailboxes, task, and
  interpreter state did not change. The PPU stayed in
  `cellSpursQueuePopBody` on the same queue.
- Route result: The controller supplied 85.499 active seconds over 243.844 host
  seconds and stopped on the 240-second host limit. The log has no `startup
  ready`, no `startup timeout`, no `0x8041090A`, no interpreter leave, and no
  targeted fatal error. This is not HLE, gameplay, or a 30 FPS result.
- Ghidra result: Ghidra imported the retained 262,144-byte local store with
  language `SPU:BE:128:default`. Its SHA-256 is
  `13C78B97D2E975FE7533579B058F34BBCE4D589A0A60AF4E2858119DCA4EC726`.
  The result in
  `debug-captures/ghidra-physx-putllc-20260831-0221/physx-putllc-window.txt`
  proves that PC `0x06cf0` is `wrch r62,ch21`. PC `0x06cd0` loads `r62` with
  `0xb4`, and PC `0x06cf4` reads the atomic status. The guest never reached
  that read.
- Root cause: The title-gated HLE startup wait used a raw
  `thread_ctrl::wait_for` loop while the PPU waited for this SPU to change the
  queue. It did not first release its PPU memory lock. Accurate SPU
  reservations were enabled. The SPU `PUTLLC` therefore waited in the VM
  writer-lock path for the PPU, while the PPU waited for the SPU.
- Host repair: Commit `8678fb220` calls
  `lv2_obj::prepare_for_sleep(ppu)` before the startup poll loop. This is the
  existing emulator path for a PPU that waits. It releases the PPU memory lock
  and removes the inactive CPU from the counter. The repair does not fabricate
  queue data, change `PUTLLC`, or bypass the guest retry.
- Verification: The focused Transformers HLE route, shutdown reconciliation,
  shutdown completion, and taskset-join contracts pass. `git diff --check`,
  the ARM64 RelWithDebInfo build, the Thortest strip task, three binary marker
  checks, and the export-surface check pass. The host-only stripped repair core
  is 63,254,056 bytes with SHA-256
  `1326F83D79578B62CDDA530B05BCD2997558CACB3564128E38416DD1BE388BF9`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It is not installed.
- Thermal and fan result: The controller maximum was 70.7 C. The independent
  watchdog recorded 429 valid samples, 15 holds, 14 releases, a 69.9 C sampled
  maximum, and no hard stop. Every sample reported Smart fan mode `4`.
  Cleanup found no PID or RPCSX `top` row at 40.5 C fixed silicon, and all
  debug properties were cleared at 40.9 C. The saved Custom slider value `100`
  is not a current fan-speed measurement.
- Next: Do not launch again in the previous cool round. In the next
  independently cool round, push exact core `1326F83D...388BF9` without a
  launch and verify its app-internal hash. Run one guarded route. Require the
  SPU to leave PC `0x06cf0`, exact `pc=0x06920 queue_rc=0x00000000`, `startup
  ready`, no timeout, no `0x8041090A`, no fatal error, and progress beyond
  PhysX startup. Require correct gameplay before an HLE claim. Require a
  matched sustained gameplay result before a 30 FPS claim.

## 265. The first two PhysX reply queues became ready

- Status: the PPU lock repair passed on the device, but a later reply queue
  returned `0x8041090A`. This is not HLE, gameplay, or a comparable FPS result.
- Cold gate: No-boot capture
  `20260831-083422-thor-input-strict-cool-gate` passed at 30.9 C fixed silicon.
  Battery temperature was 21.0 C, and skin temperature was 30.0 C. The gate
  force-stopped RPCSX and did not launch it.
- Artifact identity: Push capture
  `20260831-083509-transformers-physx-ppu-lock-repair-dev-core-push` installed
  the 63,254,056-byte repair core without a launch. The local, staged, and
  app-internal SHA-256 values were
  `1326F83D79578B62CDDA530B05BCD2997558CACB3564128E38416DD1BE388BF9`.
  Installed APK SHA-256 was
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Route identity: Capture `20260831-083747-thor-input-custom` used those exact
  artifacts. The legal Unreal and PhysX frame passed on slice 6. The PPU PhysX
  thread was created at emulator time 4:35.657729.
- Lock-repair proof: The PPU called `cellSpursQueuePopBody` on queue
  `0x01eccb80` at 4:58.649893. SPU 4 entered the exact interpreter at PC
  `0x06800` at 4:58.674705. It left 212 microseconds later at PC `0x06920` with
  `queue_rc=0x00000000`. The PPU recorded `startup ready` after 25,025
  microseconds. This proves that commit `8678fb220` removed the measured
  `PUTLLC` lock cycle.
- Downstream progress: Reply queue `0x01ed2100` also became ready after
  1,641,212 microseconds. The PPU then created a task from ELF `0x0181ec80` and
  called the nonblocking pop on queue `0x01ed0480`. That pop returned BUSY, and
  the title printed `SPURS PPU queue pop wasn't successful: 8041090A`.
- Failure order: The first RSX FIFO desynchronization row followed 25.367
  milliseconds after the queue error. The RSX thread reported `Dead FIFO
  commands queue state` 66.645 milliseconds after the queue error. The queue
  error therefore remains the first proven failure. Do not change RSX FIFO
  accuracy from this route alone.
- Root cause: The old helper used one global waited-queue address. Each matching
  queue initialization reset that address. Queue `0x01ed2100` claimed the one
  wait after the last initialization, so the later first pop on initialized
  queue `0x01ed0480` did not wait for its cold producer.
- Host repair: Commit `2bb0a2b3c` keeps a title-gated set of queue addresses.
  Each matching queue initialization rearms its own address. The first empty
  pop on that queue can use the existing bounded wait. Later empty pops on the
  same queue keep the normal BUSY result. The repair does not fabricate queue
  data. Commit `a8605c924` also makes the proof reject a captured startup
  timeout, `0x8041090A`, or fatal thread termination after a ready marker.
  Commit `2a9e39f43` accepts post-marker completion only when the controller
  reports the matching arm marker and the full requested slice count.
- Verification: The focused Transformers HLE route, guarded slice, device
  thermal guard, shutdown reconciliation, shutdown completion, and taskset
  join contracts pass. `git diff --check`, the ARM64 RelWithDebInfo build, the
  Thortest strip task, three binary marker checks, and the export-surface check
  pass. The host-only stripped successor core is 63,254,232 bytes with SHA-256
  `8756DE497FDFAAF65A3D6567E00719F876F5CD3FD4BAB4EB851990312AF55CAF`.
  Its export surface has 40 defined dynamic symbols, 596 explicit relocations,
  392 jump slots, and 44,453 encoded relocation bytes. It is not installed.
- Visual result: `slice-loop-boundary.png` shows only the Decepticon loading
  screen. The overlay reads 31.22 FPS at that instant. This is not gameplay and
  is not a sustained 30 FPS result.
- Thermal and fan result: The controller maximum was 67.8 C. The independent
  watchdog recorded 245 valid samples, a 68.2 C sampled maximum, no hold, and
  no hard stop. Every sample reported Smart fan mode `4`. Cleanup found no PID
  or RPCSX `top` row at 38.5 C fixed silicon. All 69 debug properties were
  cleared at 38.1 C.
- Next: Do not launch again in this cool round. In a later independently cool
  round, push exact core `8756DE49...55CAF` without a launch and verify its
  app-internal hash. Use post-marker slices so the proof continues after the
  first ready queue. Require every cold PhysX reply queue to become ready, no
  timeout, no `0x8041090A`, no fatal error, and visible progress beyond the
  loading screen. Require correct gameplay before an HLE claim. Require a
  matched sustained gameplay result before a 30 FPS claim.

## 266. The extended per-queue proof was stopped for PC shutdown

- Status: user-requested cancellation with verified cleanup, not a device
  result for the per-queue repair.
- Cold gate: No-boot capture
  `20260831-090805-thor-input-strict-cool-gate` passed at 33.7 C fixed silicon.
  Battery temperature was 21.0 C, and skin temperature was 30.0 C.
- Artifact identity: Push capture
  `20260831-090834-transformers-physx-per-queue-wait-dev-core-push` installed
  exact 63,254,232-byte core
  `8756DE497FDFAAF65A3D6567E00719F876F5CD3FD4BAB4EB851990312AF55CAF`
  without a launch. Local, staged, and app-internal hashes matched. Installed
  APK SHA-256 was
  `CB840615A6BC1A4B58AC379CE6745091251F53B95FCD9C745965269A0BFC6004`.
  RPCSX had no PID, and fan mode was Smart `4`.
- Partial route: Capture `20260831-091041-thor-input-custom` passed the legal
  frame on slice 6 and pressed START. It reached the PPU PhysX thread at
  emulator time 3:39.724502 after 10.251 active seconds in three handoff
  slices. The handoff controller maximum was 60.6 C.
- Cancellation boundary: The user requested PC shutdown while the extended
  after-handoff controller was active. The route has no
  `slice-loop-after-start.json` and no pulled runtime log. It cannot prove or
  disprove the per-queue repair. Do not infer a ready queue, queue error,
  gameplay, or FPS result from this capture.
- Thermal and cleanup result: The independent watchdog recorded 174 valid
  samples, a 63.0 C maximum, no hold, no hard stop, and Smart fan mode `4` in
  every sample. Normal cancellation cleanup found no PID or RPCSX `top` row at
  38.1 C fixed silicon. It cleared all 69 route properties and recorded 37.7 C
  fixed silicon. The exact dev core remains installed.
- Next: After the PC and device are available, start with a fresh no-boot cool
  gate. Reverify the app-internal core and APK hashes. Run the same extended,
  fail-closed post-marker route once. Require all reply queues, no timeout, no
  `0x8041090A`, no fatal error, and correct gameplay before an HLE claim.
