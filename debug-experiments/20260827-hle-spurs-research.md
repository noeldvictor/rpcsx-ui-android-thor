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
