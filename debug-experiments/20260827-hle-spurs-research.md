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
