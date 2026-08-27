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
