# The RSX boot hang: a deterministic repro, and what it is not

Eternal Sonata does not reach gameplay on the current build. It hangs, hard, about
eight and a half seconds into emulation, and it does so the same way every time.

This is written up separately from [`spin.md`](spin.md) because it is a different
kind of problem. Every spin in that document is a *cost*: the emulator does the
right thing and burns power doing it. This one never finishes.

## The symptom

The screen keeps whatever frame RSX last presented — during these runs, the
`Building SPU Cache... module 1186 of 1187` overlay — and never updates again. It
reads as "stuck compiling the last SPU module". It is not. The cache build had
essentially finished; the frame is stale because the thread that would replace it
is wedged.

What is actually happening:

| observation | value |
| --- | --- |
| last emulator log event | five runs, `0:00:08.31`–`0:00:08.54`, then nothing |
| `rsx::thread` CPU | 100–107%, continuously, indefinitely |
| `SPU[0x0000200]` CPU | 100%, the same, for the whole sample window |
| thread state | `R` (running), `wchan=0` — not blocked |
| system vs user time | `dSys/dUser = 5.8` — ~85% in the kernel |
| forward progress | none in 18+ minutes; zero files written to the cache |
| process health | alive; Performance Sensor still logs every 10 s, RAM flat |

Note the first row carefully: the emulator's clock is **not** frozen — the
Performance Sensor keeps timestamping every ten seconds. What stops is the
appearance of any new *event*. Reading "the last non-PERF line stopped advancing"
as "the clock stopped" would be a different and much more alarming claim.

Process-wide CPU sat at 26.0% (2.08 of 8 cores) and did not vary. One core pegged,
in the kernel, forever.

An 85% kernel share rules out the userspace `rx::pause()` spin loops on sight: a
`while (...) { rx::pause(); }` loop burns *user* time. This is a tight ioctl poll —
a syscall that returns immediately and is immediately reissued.

## The repro

Deterministic, four for four, and it costs ten seconds rather than a play session
to the first combat encounter:

```
adb shell am force-stop net.rpcsx.easy
adb shell input keyevent KEYCODE_WAKEUP
adb shell "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity \
    --es path '<iso>' --es titleId BLUS30161 --es thorDebugBootRequestId r1 \
    --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true"
```

Then watch the emulator's own clock stop advancing:

```
adb shell "grep -v 'Performance Sensor' <files>/cache/RPCSX.log | tail -1"
```

**This repro is the most valuable thing in this document.** The open crash this
was chasing — the guest faults at `0x15` and `0x3f80000c` — needed a human to play
into a combat encounter. This needs one command and ten seconds.

## Where it stops

The last four log lines before the wedge are the same every run, with the same RSX
program counters and the same addresses:

```
RSX [0x00032ec]  [descriptor_manager::register] Now monitoring 3 descriptor sets
RSX [0x00037bc]  Cache miss at address 0xC1EB4100. This is gonna hurt...
RSX [0x0003b10]  Cache miss at address 0xC1EB8180. This is gonna hurt...
RSX [0x0003ec0]  Cache miss at address 0xC1EB4100. This is gonna hurt...
```

The command-buffer PC advances normally — `0x1374 → 0x18c4 → 0x32ec → 0x37bc →
0x3b10 → 0x3ec0` — and then stops. Nothing after that line is from RSX. The
remaining log traffic is the audio thread finishing its own init, which it does
because it does not depend on RSX.

`Cache miss ... This is gonna hurt` is `texture_cache_utils.h:1624`, in
`on_miss()`. The path it leads into synchronises with the GPU.

## It is not RSX. RSX is the symptom.

The name of this document is wrong and is kept only because the symptom is what
you see first.

Static reading of the code produced a confident and completely incorrect
hypothesis, which is recorded here because it was wrong in an instructive way. The
reasoning went: the wedge follows a texture cache miss; `on_miss` leads into
`imp_flush`; `imp_flush` calls a GPU wait; `sync.cpp` has two waits that poll
without any upper bound when `timeout == 0`; those are `vkGet*Status` ioctls, which
would explain 85% kernel time. Three call sites take that zero default
(`VKPresent.cpp:199`, `commands.cpp:77`, `VKGSRenderTypes.hpp:358`). Every step of
that is true. The conclusion was still wrong.

`simpleperf` on a debuggable build, 16,876 samples, none lost:

| thread | share | samples |
| --- | --- | --- |
| `SPU[0x0000200]` | 47.48% | 8013 |
| `rsx::thread` | 47.48% | 8013 |
| `PPU[0x1000004]` | 3.80% | 641 |

**Two threads pegged, not one**, at exactly 100% each for the full window. And the
hot path in both is `sched_yield`, reached through `std::this_thread::yield` — not
a `vkGet*Status` ioctl and not `rx::pause()`. The 85% kernel share was the
scheduler, not the GPU driver.

Symbolized against the unstripped library, the two stacks are:

```
SPU   exec_mfc_cmd<false>   SPULLVMRecompiler.cpp:4708
      process_mfc_cmd       SPUThread.cpp:6212      <- the GETLLAR retry loop
      operator()            SPUThread.cpp:6244      <- its slow-yield branch
      check_state           CPUThread.cpp:976
      std::this_thread::yield -> sched_yield

RSX   cpu_task              RSXThread.cpp:903
      on_task               RSXThread.cpp:1209
      run_FIFO              RSXFIFO.cpp:675
      read                  RSXFIFO.cpp:375
```

RSX is spinning on an **empty FIFO**. It is not stuck on the GPU; it is waiting for
the guest to hand it commands that never arrive, because the guest is stalled
behind the SPU. Every minute spent on `sync.cpp` was spent on a thread that was
merely idle in an expensive way.

## Where it actually stops

`SPUThread.cpp:6212` is the `GETLLAR` reservation retry loop — the same site this
project already measured as 93% of all emulator spin:

```cpp
for (u64 i = 0; i != umax; [&]()
    {
        ...
        if (i < thor_es_getllar_retry_spin_limit()) [[likely]]
        {
            i++;
            thor_wait::profiled_busy_wait(thor_wait::site::spu_getllar_retry, ...);
        }
        else
        {
            getllar_slow_yield = true;
            state += cpu_flag::wait + cpu_flag::temp;
            std::this_thread::yield();          // <- line 6244, where it lives now
            static_cast<void>(check_state());
        }
    }())
```

The SPU has long since exhausted its spin limit — 24 by default — and is in the
slow-yield branch permanently. The loop only exits when the reservation at `addr`
becomes readable and stable. It never does.

That means a reservation is taken and never released, or is being republished
faster than this thread can ever observe it settled. This is a **guest-visible
deadlock in the reservation path**, and it is worth noting that the reservation
path is also where the two earlier guest faults appeared, and where the two
reverted rewrites lived.

Two adjacent Eternal-Sonata-specific hooks sit directly in this loop and were
checked rather than assumed: `thor_es_getllar_skip_rsx_lock` (line 6207) is gated
behind a non-default `getllar_mode` and returns false here, and
`thor_es_getllar_retry_spin_limit` only changes 24 to 8. Neither is active in this
configuration.

## The unbounded GPU waits are still real, and still not this

`sync.cpp`'s `wait_for_fence` polls with no upper bound when `timeout == 0`, and
`wait_for_event` is worse — its deadline check sits *inside* `if (timeout)`, so
passing zero does not mean "no timeout", it means the check is never evaluated:

```cpp
if (timeout)
{
    ...
    if ((now > start) && (now - start) > timeout)
    {
        rsx_log.error("[vulkan] vk::wait_for_event has timed out!");
        return VK_TIMEOUT;
    }
}

rx::pause();
```

That is a genuine defect and worth fixing on its own merits. It is **not** the
cause of this hang, and fixing it would not have moved this hang by one
millisecond. Keeping those two facts apart is the whole point of the measurement.

## What was ruled out, and how

Each of these was a real hypothesis, tested, not merely dismissed:

| hypothesis | verdict | evidence |
| --- | --- | --- |
| Screen asleep, surface not consumed | **no** | `mWakefulness=Awake`, `RPCSXActivity` focused, SurfaceView + BLAST layers live |
| Xenia contending for the GPU | **no** | Xenia alive but `0.0%` CPU, every thread idle, 95 MB RSS |
| GPU fault or driver hang | **no** | no KGSL/adreno fault in logcat or dmesg; the KGSL lines present are SELinux `min_pwrlevel` denials from an unrelated power service |
| `Write Color Buffers` readback | **no** | booted with it `false`; hung at the same PCs, same addresses, same point |
| Config drift from the boot harness | **no** | every Video key identical to the last known-good backup of 2026-08-05 |
| My two RSX commits | **no** | `e58182dc0` adds a counter and a comment, loop unchanged, and compiles out without the profiler flag; `c0eabeb0f` touches an auditor that is compiled out when idle |
| Still compiling SPU module 1187 | **no** | zero files written under the title cache in 40 minutes |
| Stale Vulkan pipeline cache | **untested** | the `mv` that would have cleared it failed silently — see below |

## Two methodology notes, because both nearly produced a wrong answer

**The `dequeueBuffer` timeouts are real but they are not the current loop.** At the
moment the hang set in, logcat carried a burst of
`vulkan: dequeueBuffer timed out: Connection timed out (-110)` from the exact tid
that is now pegged. It is extremely tempting to call that the answer. Clearing
logcat and counting over a fresh 12-second window gave **zero**. The burst marks
the *onset*; the thread then settled into a silent loop. This project has already
recorded one wrong conclusion from attaching a `dequeueBuffer` count to the wrong
moment, and this was the second opportunity.

**A shell command that fails silently reads exactly like one that succeeded.** The
run labelled "shader cache cleared" had cleared nothing: `mv` into
`files/cache/cache/...` failed because that directory is `drwxr-s---` and gives the
group no write permission, while `config/custom_configs` is `drwxrws---` and does.
The `&&`-guarded `echo MOVED_OK` never printed, and that was not noticed until the
directory was listed afterwards. The run was still a valid fourth reproduction; it
was simply not the experiment it was labelled as. Verify the precondition after the
command, not before.

## How to get here again

`tools/thor_diagnose_rsx_hang.ps1` boots the title, waits for the hang, confirms
the thread is actually spinning before attributing anything, and samples it.

It needs a **debuggable** build. On the release variant `run-as` refuses the
package and `/proc/<tid>/syscall` is `Permission denied`, which is what made this
unanswerable for the first several hours:

```
./gradlew assembleThortest -PrpcsxThorDebuggable=1
```

That property deliberately does not touch the CMake arguments, so it reuses the
cached native objects — the build that produced the numbers above took 3m 46s with
14 of 42 tasks executed. It also leaves the default off, because `thortest` is the
*measurement* variant and `android:debuggable` changes ART's behaviour; a power or
spin number taken from this build would be on the wrong footing.

Two instrument notes worth keeping:

- **`/proc/<tid>/syscall` is useless for a thread that never blocks.** It returned
  `running` on all ten samples. The kernel will not snapshot the registers of a
  task currently on a CPU, so the one file that names a syscall directly is
  structurally blind to exactly the case being investigated. `simpleperf` is the
  instrument, not `/proc`.
- **`perf_event_open` is blocked by default.** `security.perf_harden` must be set
  to 0, and even then `perf_event_paranoid=1` refuses a cross-uid profile, so
  `simpleperf record -t <tid>` fails with `Permission denied`. The form that works
  without root is `simpleperf record --app <package>`, which re-execs inside the
  app's own context.

## Correction: it is not one title. It is SPURS, at one instruction

Folklore (`BCUS98147`), never booted before, stalls the same way — and the stall
report makes the match exact:

| | Eternal Sonata | Folklore |
| --- | --- | --- |
| thread | `CellSpursKernel0` | `CellSpursKernel0` |
| **SPU PC** | **`0x12b0`** | **`0x12b0`** |
| `lsa` | `0x100` | `0x100` |
| retries | 24 (spin limit) | 24 |
| reservation addr | `0x9d4d80` | `0x10a60c00` |
| counter / neighbours | 4, (0, 2) | 5, (0, 2) |

**The same SPU program counter in two unrelated games.** Both load Sony's SPURS
kernel from `libsre`, so this is one instruction in one firmware module failing the
same way against two different workload descriptors. The addresses differ because
the games' memory layouts differ; everything about the *code* is identical.

That retracts the earlier section below. "One title, not the emulator" was concluded
from Odin Sphere running — but Odin Sphere only reaches a black loading screen, and
on this evidence it may simply not have driven SPURS hard enough yet. Two of the
three titles tested deadlock at the same instruction, which makes this a **general
SPURS defect, not an Eternal Sonata quirk.**

Three consequences worth stating:

- **The repro is now broader and cheaper.** Any SPURS title reaching that code path
  will do; no dependence on one game's cache state.
- **The fix is worth more than one title's boot.** SPURS is the standard SPU task
  scheduler; a defect here plausibly affects most of the library.
- **It is still not an ARM64 question.** The stalled code is guest firmware, the
  reservation word is clean, and the ARM64 atomics were measured correct. What
  differs between a working PS3 and this emulator at `pc=0x12b0` is the next thing
  to find, and the GDB stub is the tool for it.

## Superseded: it is one title, not the emulator

Odin Sphere (`BLUS31601`) boots on the same build, from a cold cache, and shows none
of the signature: the emulator clock advances continuously (`0:00:26` through
`0:06:34` and onward), no thread is pegged, and `rsx::thread` sits at **3.8%** rather
than 100%, working through `Compiling PPU Modules... module 49 of 93` with a live
progress estimate.

That last number is the interesting one. In the Eternal Sonata runs, RSX spins at
100% on an empty FIFO *while the cache overlay is still up* — before the game is
really rendering anything. Odin Sphere at the same stage leaves RSX essentially
idle. So RSX's spin is not what an idle FIFO normally looks like on this build; it
is specific to whatever state Eternal Sonata leaves the FIFO in.

Two things follow. The emulator is not globally broken, so measurement and
optimization work does not have to wait on this bug — it needs a title that runs,
which now exists. And the deadlock is a property of this title's SPURS and
reservation usage rather than of the reservation code in general, which narrows the
search considerably.

**A warning about how that was nearly got wrong.** The first Odin Sphere run only
proved the *cache build* progresses — the clock advanced because compilation logs.
Resumed with a warm cache, it reaches real emulation, and then it looks exactly like
the hang: five SPU threads and RSX all near 100%, and the last log line is
`Cubeb: Stream started`, character for character the same line Eternal Sonata stops
on. On that evidence it was written off as the same bug.

It is not. A screenshot shows the FPS overlay reading **11.12** on a black loading
screen, and two captures twenty seconds apart differ. It is running.

The lesson is that **"the log stopped" is not a hang detector.** Its own caveat is
three sections up in this document — the clock does not stop, only new *events* do —
and normal gameplay produces no events for minutes at a time. The detector that works
is the one CLAUDE.md already lists as a trap: FPS is only ever drawn, never logged, so
a screenshot is the measurement. Two screenshots and the overlay separate "hung" from
"slow" in ten seconds; the log cannot.

## Two levers that were tried on it and did nothing

**`debug.rpcsx.thor.getllar_busy_percent=0` does not touch this loop.** Setting it to
0 and rebooting left both threads pegged at 100% and the wedge in the same place. That
property feeds `evaluate_spin_optimization`, which decides whether a GETLLAR wait
spins or sleeps; the loop that hangs is the *retry ladder* above it, which spins 24
times and then yields unconditionally. They are different decision points, and the
sweep lever does not reach this one.

**`debug.rpcsx.thor.es_getllar=profile` logs nothing on Android.** The probe that
would report the reservation address, PC and retry count is inside the block guarded
at `SPUThread.cpp:382` by
`#if !defined(ANDROID) || defined(RPCSX_THOR_ES_SPU_EXPERIMENTS)`, so the device gets
`constexpr` stubs and the property is inert. Arming it needs a build with that macro,
and its output goes to **logcat**, not `RPCSX.log`.

## The wait profiler is present and still silent

A build with `-PrpcsxThorWaitProfiler=1 -PrpcsxThorDebuggable=1` is installed, and the
profiler really is compiled in — `grep -a` finds `Thor wait profiler` twice in the
shipped library plus `spu_getllar_retry`, `vm_passive_lock` and `vk_fence_poll`. Use
`grep -a`, not `strings`, which has already produced one false negative here.

It reports nothing, for two different reasons worth separating:

- **On the hung title, it structurally cannot.** `record()` is only reached through
  `profiled_busy_wait`, which the retry ladder calls for its first 24 iterations and
  never again once it falls into the yield branch. A permanently stuck GETLLAR
  contributes 24 samples and then goes quiet forever. The instrument cannot see the
  state it would be most useful in.
- **On the running title, the sites are barely hit.** Even at an interval of 5,000
  calls, Odin Sphere on its loading screen does not reach the threshold, while
  emitting 369 other `RPCS3`-tagged lines — so the tag and the build are fine, and
  reservation traffic at that stage is simply near zero.

The GETLLAR sweep therefore still needs a title in real gameplay, not merely a title
that boots.

## The third thread, and what it is waiting on

The earlier profile stopped at "two threads pegged". Profiling again with the
question *what is the other side of the reservation doing* gives a third:

| thread | share | where |
| --- | --- | --- |
| `SPU[0x0000200]` | 47.5% | `GETLLAR` retry loop, slow-yield branch |
| `rsx::thread` | 47.5% | `run_FIFO`, empty FIFO |
| `PPU[0x1000004]` | 3.8% | **`rx::get_tsc()`, `rx/tsc.hpp:19`** |

The PPU figure is small but its distribution is not: **96% of its samples land on
one adjacent instruction pair**, `+2046af4`/`+2046af8`, both symbolising to the
`mrs cntvct_el0` in `rx::get_tsc`. That is not a thread doing a little work. It is
a thread polling the clock.

So the PPU is in a **timed wait**, and — this is the part that matters — it is
waiting on *time*, not on the SPU. It holds nothing. It is not the other end of
the reservation.

Which reframes the question. The shape is not "PPU holds a reservation the SPU
wants". All three threads are waiting, one on a reservation, one on a clock, one
on a FIFO, and none of them is the owner. Either the owner has exited, or the
reservation was left in a locked state by a thread that is gone, or the wakeup
that would release the SPU was lost.

That also makes this a fifth instance of the pattern already catalogued in
[`spin.md`](spin.md) — a wait implemented as a spin. The PPU's timed wait burning
a TSC read loop is cheap here at 3.8%, but it is the same shape as the other four,
and it means the PPU cannot notice a state change any faster than its poll
interval.

### Which wait, narrowed statically

`rx::get_tsc()` has few callers, and only one class of them runs in a loop:

| caller | file | shape |
| --- | --- | --- |
| `get_system_time()` | `kernel/cellos/src/sys_time.cpp:221` | **backs the guest `sys_time_get_system_time` syscall** |
| `get_timebased_time()` | `kernel/cellos/src/sys_time.cpp:154` | backs the guest time-base read |
| atomic-wait bookkeeping | `util/Thread.cpp:2261`, `2710`, `2723` | one stamp per wait, not a loop |
| TSC calibration | `util/sysinfo.cpp:1114` | runs once at startup |

The bookkeeping and calibration sites take a stamp, not a stream of them, so a
thread sitting at 96% on the `mrs` almost certainly reaches it through
`sys_time.cpp` — i.e. **the guest is polling the clock**.

Stated as the leading candidate rather than a fact, because it has not been proven
by walking the actual callers: the frame is inlined and the unwinder did not cross
it. But if it holds, the PPU is a *victim* rather than a party to the deadlock —
PS3 titles routinely wait for SPU completion by polling `sys_time_get_system_time`
in a loop, which is exactly what a game would be doing while an SPU it is waiting
on never finishes.

That makes the SPU reservation the root and the other two threads consequences,
and it means fixing the reservation fixes all three.

### Every counter in this codebase is blind to a hang

The plan was to compile in `RPCSX_THOR_ES_SPU_EXPERIMENTS` and read the reservation
address off the probe. That was done — build clean, probe verified present in the
shipped library (`grep -a` finds `Thor GETLLAR probe` twice), property armed,
deadlock reproduced. **It logged nothing.**

The reason is structural, not a misconfiguration. `record_thor_es_getllar` is
called at `SPUThread.cpp:6311`, which is *after* the retry loop at 6212-6247 has
exited. A GETLLAR that never completes never reaches the call.

That is now three instruments with the same defect, which makes it a property of
the codebase rather than an accident:

| instrument | records at | sees a hang? |
| --- | --- | --- |
| wait profiler (`thor_wait::record`) | after `profiled_busy_wait`, so only the first 24 spins | no |
| GETLLAR probe (`record_thor_es_getllar`) | after the retry loop exits | no |
| RSX auditor (`on_frame_end`) | after a frame is presented | no |

**Every counter here is incremented on completion.** They are built to answer "how
much did this cost", which is the right question for a spin and the wrong one for a
stall. A loop that never terminates contributes nothing to any of them, so the
harder the hang, the quieter the instrumentation — and silence reads identically to
"this code never ran".

Which explains the shape of this whole investigation: three separate instrumentation
attempts produced nothing, and every fact in this document came from **sampling**
(`simpleperf`) or from **state inspection** (`/proc`, `top -H`, screenshots).

**For the next person: do not add another counter.** To see this hang you need
either a sampling profiler, or an instrument that records on *entry* and is cleared
on exit — a "currently waiting on address X since timestamp T" slot per SPU, which
a watchdog thread can read while the wait is still in progress. That is a genuinely
different design from anything the fork currently has, and it is the missing piece.

Confirming the PPU's caller wants a frame-pointer build and is worth less than that.

## The address, and what is waiting on it

The in-wait report fired on the first run:

```
·E 0:00:13.513 {SPU[0x0000200] Thread (CellSpursKernel0) [0x012b0]}
   GETLLAR stalled: addr=0x9d4d80 lsa=0x100 pc=0x12b0 retries=24 elapsed=5.0s
```

**The stalled thread is `CellSpursKernel0`** — Sony's SPU task scheduler, not game
code. `retries=24` is the spin limit exactly as predicted, confirming it entered the
yield branch and stayed there.

The surrounding boot log gives the rest:

```
sys_spu_thread_group_create(): "CellSpursKernelGroup" created (id=0x4000200)
sys_spu_thread_initialize():   "CellSpursKernel0" created (id=0x200)
_sys_ppu_thread_create():      "SpursHdlr1" (0x1000008), "SpursHdlr0" (0x1000009)
Loaded SPU image: SPU-c551925d5640eb35b80dc1281f8509336eca9765   (by SpursHdlr0)
```

So the sequence is: the game brings up SPURS, one kernel SPU thread and two PPU
handler threads are created, the kernel image loads — and then the kernel sits on
its workload reservation at `0x9d4d80` forever. The SPURS kernel polls that word to
find out whether there is work; nothing ever publishes it.

**The spinning PPU is `0x1000004`, which is neither handler** (`0x1000008` /
`0x1000009`). The two threads that would feed SPURS are not the ones burning CPU;
they are simply not making progress either.

### This title has hung on SPURS before

CLAUDE.md's Eternal Sonata profile carries, verbatim:

> Do not cap SPURS here; SPURS 4 caused a black-screen-alive load hang on Thor.

and sets `Max SPURS Threads: 6`. So a SPURS-related, black-screen-with-live-process
hang on this exact title on this exact device is **already recorded history**, and
was previously worked around by not capping the thread count. The present hang has
the same signature — process alive, screen frozen, no forward progress — and now has
an address attached to it.

That makes the next step concrete rather than exploratory: find who is supposed to
write `0x9d4d80`. It is the SPURS workload descriptor in main memory, so the writer
is either a `SpursHdlr` PPU thread or another SPURS kernel instance that was never
created. Only one kernel SPU thread exists in this boot; whether that is correct for
this title's SPURS configuration is the first thing to check.

### The most likely mechanism, and how to falsify it in one line

With the address known, the loop body reads differently. Its first exit check is:

```cpp
ntime = vm::reservation_acquire(addr);

if (ntime & vm::rsrv_unique_lock)
{
    // There's an on-going reservation store, wait
    continue;
}
```

**A leaked `rsrv_unique_lock` on `0x9d4d80` produces exactly the observed
behaviour**: `continue` forever, retries pinned at the spin limit, no exit, and
nothing for a completion-time counter to record. The lock is taken by a writer
performing a reservation store; if a writer is interrupted, exits, or takes an
error path between acquiring and releasing it, every reader of that line spins
permanently.

That is a much sharper hypothesis than "the reservation does not settle", and it
is cheap to falsify: the stall report already runs at the right moment, so add
`ntime` to it. If the top bits show `rsrv_unique_lock` set, the bug is a leaked
lock and the search narrows to writers of that line. If it is clear, the reservation
is simply never being updated and the search moves to who should be writing it.

One line in the report, one boot, and the two halves of the search separate. That
is the next thing to do.

### Answered: no leaked lock. The line is clean and simply never written again

```
GETLLAR stalled: addr=0x9d4d80 lsa=0x100 pc=0x12b0 retries=24 elapsed=5.0s
                 ntime=0x200 unique_lock=0 counter=4
```

**`unique_lock=0` kills the leaked-lock hypothesis.** And `ntime = 0x200 = 512 =
4 x 128` means the low seven bits are clear, so the reservation is neither locked
nor mid-update. The loop passes both `continue` guards cleanly every time.

What it is actually doing, then, is the plain GETLLAR polling semantic: re-read the
line and wait for the **contents** to change. They never do. `counter=4` says the
reservation generation has advanced exactly four times since boot and then stopped
for good.

So the fault is not in the reservation machinery at all — no lock is stuck, no
update is lost, the line is readable and consistent. **Nobody writes it.** The SPURS
kernel is waiting for a workload descriptor that the PPU side stops publishing after
four updates.

That relocates the bug out of `vm::reservation_*` and into the PPU-side SPURS
handshake, and it is consistent with the thread picture: `SpursHdlr0` and
`SpursHdlr1` exist but are not burning CPU, and the one busy PPU (`0x1000004`) is
polling a clock rather than doing SPURS work. Everything is waiting; nothing is
producing.

**The question is now: what were those four writes, and what should have caused a
fifth?** With `counter` in the report, a run that logs the first four writes to
`0x9d4d80` — address-watch on the PPU store path, or a breakpoint in the SPURS
syscall handlers — will say directly which side stopped.

### The writer is an atomic store, not a notify

`debug.rpcsx.thor.resv_watch=9d4d80` armed, boot reproduced, stall reported with
`counter=4` as before — and **the watch logged nothing**.

That is a result rather than a dead end, because the code comment said in advance
what silence would mean:

> If a run with the watch armed logs nothing while the counter still advances, that
> is the answer rather than a broken watch — the writer is an atomic store, not a
> notify.

The watch sits in `reservation_update()`, the path taken when something wants to
poke a reservation *without* performing a reservation store. `PUTLLC` and `stwcx.`
complete their stores on their own paths and bump the counter there. Four bumps
happened, none through `reservation_update`, so **all four writes to `0x9d4d80`
were atomic reservation stores** — a guest `PUTLLC` from an SPU or `stwcx.` from
the PPU.

Which is what SPURS should look like. The workload descriptor is a lock-free
structure updated with reservation stores by both sides; that is the whole point of
`lwarx`/`stwcx.` and `GETLLAR`/`PUTLLC`. So nothing here is malformed — a
legitimate writer performed four legitimate atomic updates and then stopped.

**Next, and it is a two-line move:** the same watch belongs on the atomic store
completion paths, where the counter is incremented directly. `SPUThread.cpp` and
`PPUThread.cpp` between them hold about a dozen `reservation_notifier_notify` call
sites, and the ones adjacent to a successful `PUTLLC`/`stwcx.` are where the four
writes went through. Logging the writer's thread name and PC there names the
producer, and then the question becomes why that producer stopped after four
iterations — which is a question about SPURS scheduling, not about memory ordering.

Worth stating plainly: **this rules out the emulator's reservation implementation
for the second time**, by a different route. First the reservation word was clean
and unlocked; now the writes that did happen went through the correct atomic path.
Whatever is broken is above `vm::`, in what SPURS decides to do.

### Moving the watch to the notifier changed nothing, and that is unresolved

The watch was moved from `reservation_update()` into
`reservation_notifier_notify()` — the function every completed reservation store
was believed to pass through, whatever path performed it. Rebuilt, rearmed, boot
reproduced. **Still zero hits.**

Preconditions verified this time rather than assumed, because the previous silence
was only meaningful *because* it had been predicted:

| check | result |
| --- | --- |
| `debug.rpcsx.thor.resv_watch` | `9d4d80` |
| process alive | yes |
| log written | 989 lines |
| deadlock reproduced | yes — stall line present, `counter=4` |
| `resv_watch` in shipped `.so` | 3 occurrences (`grep -a`) |

So the instrument is in the binary, armed, and the run did what it was supposed to
do. And the counter still says four bumps happened.

**Two explanations remain and this run cannot separate them:**

1. **The reservation counter is incremented on a path that never notifies.** If
   true, that is a finding in its own right and a more interesting one than the
   original question — an SPU parked in a notifier wait on such an address would
   never be woken. Ours survives only because it is in a yield-spin loop that
   re-polls regardless.
2. **The watch has a defect** — the property read, the `& -128` masking, the
   comparison, or `vm_log.error` routing — that has not been found.

Distinguishing them needs one thing that was not done: **arm the watch on an
address known to be written constantly and confirm it fires at all.** Until a
positive control passes, this instrument's silence proves nothing, and the earlier
conclusion drawn from its silence — "the writer is an atomic store, not a notify" —
rests on the same unverified assumption and should be treated as provisional too.

That is the correct state to leave this in. A watch that has never been seen firing
is not evidence about anything, and the session's recurring failure has been exactly
this shape: a search that finds nothing looking identical to a search that searches
nothing, four times over.

### Resolved by the positive control: the watch was in the wrong place

The control logs the first five notifies of *any* address whenever a watch is
armed, so a run can distinguish "the watched line is never notified" from "this
hook is never reached". It produced **nothing**, with every precondition verified:

| check | result |
| --- | --- |
| deadlock reproduced | yes, stall line present |
| `debug.rpcsx.thor.resv_watch` | `9d4d80` |
| property string in shipped `.so` | present — so the `#ifdef ANDROID` block compiled |
| `debug.rpcsx.thor.rsx_auditor` in `.so` | absent — correct, this build omits that flag (working negative control) |

So the property read is live, the value is set, and `reservation_watch_note` is
called **zero times for any address across an entire boot**.

That is the resolution: **`reservation_notifier_notify()` is essentially never
called.** The notify sites are guarded on a waiter being registered, and the
stalled SPU is in a *yield-spin*, not a notifier wait — it never registers, so
nothing ever notifies. The hook could not have observed a write no matter how many
occurred.

Two corrections follow, and both are mine:

1. **The earlier conclusion "the writer is an atomic store, not a notify" is
   withdrawn.** It was drawn from the first silence, and that silence had the same
   cause as this one — the hook is unreachable. It was never evidence about the
   writer.
2. **The watch belongs on the counter increment, not the notify.** The bump is
   `res.compare_and_swap_test(rtime, rtime + 128)` in `try_reservation_update`,
   plus the equivalent increments on the `PUTLLC` and `stwcx.` completion paths.
   Those execute whether or not anyone is waiting.

The instrument and its control stay in the tree. The control is the part worth
keeping: it converted two meaningless silences into a definite answer about the
instrument itself, which is what the previous four instances of this trap lacked.

### Where the watch actually belongs, located

The counter is a `u64` advanced in steps of 128. Grepping for that increment across
the reservation code gives the complete set of writers:

| site | what it is | watched? |
| --- | --- | --- |
| `Memory/vm.cpp:198` | the CAS in `try_reservation_update` | yes — never fires |
| **`Memory/vm_reservation.h:248`** | `res += 128` in the reservation store template | **no** |
| **`Memory/vm_reservation.h:262`** | `res += 128` in the reservation store template | **no** |
| **`Cell/SPUThread.cpp:3819`** | `res += 128` on an SPU path | **no** |

The two in `vm_reservation.h` are the templates that `PUTLLC` and `stwcx.` complete
through, and they bump the counter **directly** rather than by calling
`try_reservation_update`. That is why both watch placements missed all four writes:
one watched the CAS that these bypass, the other watched a notifier that is only
reached when a waiter is registered.

**And that table is wrong, which is worth leaving visible.** Checking the two
`vm_reservation.h` sites before instrumenting them:

```
219:  #if defined(ARCH_X64)
220:      if (g_use_rtm)
248:              res += 128;
262:                  res += 128;
399:  #endif /* ARCH_X64 */
```

Both live inside a 180-line `ARCH_X64` block, further gated on `g_use_rtm` — they
are the **Intel TSX** fast path, `__asm__ volatile("xend;")` and all. On AArch64
that code does not exist. The two sites singled out as "where the writes went" are
compiled out of the binary entirely.

So the corrected position is narrower than the table suggests: of the four
increments a grep finds, `vm.cpp:198` is watched and silent, two are x86-only, and
only `SPUThread.cpp:3819` remains a candidate — and its own architecture guard has
not been checked either. **The ARM64 path is somewhere past `#endif` at line 399,
and has not been found yet.**

Which is the same mistake a third time in one evening, one layer up: a grep produced
a list, and the list was called "specified rather than guessed" without checking the
hits were reachable on this architecture. CLAUDE.md already records the identical
failure from the audit ledger — `Emu/Cell/lv2` and `Emu/Cell/Modules` recorded clean
by grepping paths that do not exist in this fork.

**The rule this keeps demanding: a grep hit is a candidate, not a finding. Confirm
the architecture guard and the reachability before writing it down, and carry a
positive control into any instrument built on it.**

### Found, and the reason four searches missed it

Reading the preprocessor structure instead of grepping again:

```
219:  #if defined(ARCH_X64)
397:  #else
398:      static_cast<void>(cpu);
399:  #endif /* ARCH_X64 */
402:      reservation_shared_lock_internal(res);
...
409:      res += 127;
```

The generic branch is two lines, and the counter write is **`res += 127`, not
128**. `reservation_shared_lock_internal` has already added 1 to take the lock, so
`1 + 127 = 128` completes the increment *and* releases the lock in one store.

That is why every search failed. The pattern searched for was `+ 128`, which exists
only on the x86 and TSX paths; the path this device actually executes never writes
that constant. Four instrument placements and three greps, all defeated by an
off-by-one in the search term rather than by anything about the code.

The verified ARM64-reachable writers, all past the `#endif` at 399:

| site | note |
| --- | --- |
| `vm_reservation.h:409` | reservation op, void result |
| `vm_reservation.h:424` | reservation op, non-void result |
| `vm_reservation.h:521`, `:531` | light-op variants |
| `vm.cpp:867` | |
| `Cell/SPUThread.cpp:3947` | the generic counterpart of the `+= 128` at 3819, which is the TSX path |

`SPUThread.cpp:3819` is therefore also x86-only, completing the correction: of the
four sites the original grep produced, **three were unreachable on this hardware and
the fourth was already watched.**

**This is where the watch goes**, with the positive control carried in from the
first build. And the general lesson, which cost more than the specific one: when a
search for a constant comes back empty on a platform where the behaviour plainly
occurs, suspect the constant before suspecting the behaviour.

### The run that followed, and why its negative does not count

Four of those sites were hooked — `vm_reservation.h:410, 426, 524, 535`, each
immediately after its `res += 127` and all past the `#endif` at 399. Built clean,
armed, deadlock reproduced. **No control lines, no hits.**

Which would say those paths never execute — except the run does not support that,
because **only four of the six identified sites were instrumented.** The insertion
script targeted `vm_reservation.h` alone; `vm.cpp:867` and `Cell/SPUThread.cpp:3947`
were on the verified list and were skipped. A negative from a partial instrument is
not a negative.

Also unchecked in the same pass: `res.release(...)`, `.store(...)` and
`.fetch_add(...)` forms across the SPU and PPU reservation paths turned up exactly
one hit, `vm_reservation.h:291`'s `res.fetch_add(1)` — the lock acquire, not a
counter completion. So the write form is still not fully enumerated.

**State to resume from, stated honestly:** the writer of `0x9d4d80` is still not
identified. Five instrument placements have produced five silences, and of those,
four are now explained (wrong path, wrong path, x86-only, x86-only) and the fifth —
this one — is simply incomplete. The next attempt should hook **all six** sites in
one build, not four, and should confirm the control fires before reading anything
into a missing hit.

That is five rounds of the same error in one evening. The instrument was never the
hard part; knowing which lines this device executes was, and every shortcut around
that question has cost a build and a device run.

### And the sixth round invalidates the other five: the log channel is silent

All six sites hooked, built clean, deadlock reproduced — still no control lines. At
which point the one precondition never checked:

```
lines tagged "} vm:"   :  0
lines tagged "} SPU:"  : 37
channels present       :  ppu_loader 75, RSX 73, PPU 39, SPU 37,
                          sys_prx 36, sys_fs 30, SYS 30, sys_spu 24
```

**`reservation_watch_note` logs through `vm_log`, and not one `vm_log` line appears
in the entire file.** The stall reporter — the single instrument that has worked all
evening — uses `spu_log`.

So the placement may have been right for one or more of the last three attempts, and
every negative drawn from them is void. Five silences were read as evidence about
*where the code writes*; at least some of them were evidence about *which logger gets
flushed*.

This is the same failure a sixth time and the worst instance, because it invalidates
the other five at once. The checklist that would have caught it is one line long:
**before trusting an instrument's silence, confirm its output channel produces
anything at all.** Verifying the string is in the binary (done), the property is set
(done), and the code path executes (attempted five times) is all worthless if the
sink is dead.

**The fix is one word** — log through a channel known to reach the file. The
`GETLLAR stalled` line proves `spu_log.error` arrives; `vm_log` does not. Until that
change is made and a control line appears, **nothing in this section about writer
locations should be treated as established.**

### The first real negative, and it kills the premise

The watch was rerouted to `__android_log_print` — logcat, which cannot be muted by
an RPCS3 channel setting — and rerun. For the first time all three preconditions
hold at once:

| precondition | evidence |
| --- | --- |
| deadlock reproduced | stall line present |
| sink works | **247 `RPCS3`-tagged logcat lines** in the same run |
| instrument in binary | `resv_watch CONTROL` found by `grep -a` in the shipped `.so` |
| property armed | `9d4d80` |
| placement | all six ARM64-reachable `+= 127` completions |

**Zero control lines.** `reservation_watch_note` is never called. None of the six
counter-completion sites execute during this boot.

That is finally a real negative, and it does not narrow the search — it invalidates
the question. **The premise was that `counter=4` means four guest writes occurred.**
With every completion path verified unreached, that no longer follows. The `0x200`
in the reservation word has some other origin: initialisation, a shared or aliased
slot, or a path that sets the word without going through the `+= 127`/`+= 128`
completions at all.

So the thing to check next is not *who wrote it* but *whether it was written*:

- Read `reservation_acquire(0x9d4d80)` once at boot, before the SPURS group is
  created, and see whether it is already `0x200`.
- Confirm the slot is not aliased — that `reservation_acquire` maps distinct
  128-byte lines to distinct words on this configuration.

If the word is already `0x200` before the game touches it, then the SPU is polling a
line that was **never written by anyone**, and the deadlock is that SPURS is waiting
on a descriptor the emulator never populates — a different bug entirely from
"a producer stopped after four iterations", and one that the last several hours of
writer-hunting could not have found because there was no writer to hunt.

### Differential answer: the writes are real, and the writer is JIT-emitted code

The neighbour lines settle it in one line of output:

```
GETLLAR stall neighbours: prev(0x9d4d00)=0  cur=4  next(0x9d4e00)=2
```

Three distinct values. The counters are **not** uniformly initialised and **not**
aliased — one line untouched, one written four times, one written twice. So
`counter=4` does mean four writes, and the premise stands after all.

Which leaves a contradiction with a single clean resolution. The writes are real,
and **none of the six C++ completion paths executed** (verified: working sink, 247
logcat lines in the same run, instrument confirmed in the binary). So the writer is
not C++ at all.

**It is the recompiler's emitted code.** RPCS3's SPU JIT inlines the reservation
store for `PUTLLC` rather than calling a helper — `SPULLVMRecompiler.cpp` builds the
compare-and-swap into the generated block. Guest atomics therefore bump the
reservation counter from JIT-generated machine code that no C++ hook can observe, by
construction. That is why six placements across every C++ path produced six
silences, and the last one was a true negative rather than another instrument fault.

**This closes the writer question as far as source instrumentation can take it.**
To watch these writes you need one of:

- instrumentation emitted *by* the recompiler, gated the same way the JIT's other
  debug paths are;
- a hardware watchpoint on the line, which needs a debuggable build and either
  `lldb` or a `ptrace` helper — the address is known and stable at `0x9d4d80`;
- or the guest-side view: single-step the SPURS kernel at `pc=0x12b0` in RPCS3's own
  GDB server, which the profile already shows running as a thread.

The last is probably cheapest and is the natural next move: the SPU code polling that
line is Sony's SPURS kernel, its PC is known, and the emulator ships a GDB stub.

### The GDB entry point, verified live during the hang

Not assumed — checked while the deadlock was active:

```
config.yml            GDB Server: 127.0.0.1:2345
/proc/net/tcp         0100007F:0929  ...  0A  ...  10158
                      (127.0.0.1:2345, state 0A = LISTEN, uid = the app)
```

So the stub is up and accepting connections **while the SPU is stalled**, which is
the only moment that matters. To reach it:

```
adb forward tcp:2345 tcp:2345
<gdb-client> -ex "target remote :2345"
```

What to ask it, in order, since the surrounding facts are already pinned down:

1. Which SPU thread the stub exposes as `CellSpursKernel0`, and confirm its PC is
   `0x12b0` — matching the stall report, so the two views agree before anything is
   inferred from either.
2. Read local store around `lsa=0x100`, the buffer this `GETLLAR` targets. That is
   the guest's own copy of the workload descriptor, and comparing it against main
   memory at `0x9d4d80` says whether the SPU is seeing stale data or correct data
   it considers unfinished.
3. Step the kernel and watch which branch it takes out of the poll — SPURS spins on
   a workload bitmap, so the failing predicate identifies which field never
   changes.

This is the first tool in the chain that observes the **guest** rather than the
emulator, which is the right level: everything below it — reservation machinery,
notifier, counters, memory ordering — has now been measured and cleared.

### Connected, and the plan above needs amending: the stub is PPU-only

Spoke the remote protocol to it directly during a live deadlock. It works, once the
`+` acknowledgement is sent after each reply — without that the server answers
`qSupported` and then stalls, which looks like a broken stub and is not:

```
-> qSupported    <= +$PacketSize=1200#f3
-> ?             <= +$S05#b8                  (stopped, SIGTRAP)
-> qfThreadInfo  <= +$m0000000001000000,...,000000000100000a l
-> Hg0 / g       <= +$OK / full register dump
```

Eleven threads, `0x01000000` through `0x0100000a`. **Every one is a PPU thread.**
The stalled `CellSpursKernel0` is SPU id `0x200` and does not appear, so
**RPCSX's GDB server does not expose SPU threads** and cannot single-step
`pc=0x12b0`. Step 3 of the plan above is not available through this route.

What it *can* do is still worth having, and is arguably the better question anyway:
those eleven PPU threads include `SpursHdlr0` (`0x1000009`) and `SpursHdlr1`
(`0x1000008`), the two threads that feed SPURS work to the SPU. The deadlock is a
producer that stopped; **the producer is a PPU thread, and the stub can read its
registers and step it.** So:

- `Hg` to `0x1000009`, then `g`, and see where `SpursHdlr0` is parked.
- Same for `0x1000008`.
- The one busy PPU (`0x1000004`, polling the clock) is also in range.

That is a more direct line to "why did the producer stop" than watching the consumer
spin would have been. For the SPU side, the options remain recompiler-emitted
instrumentation or the in-wait reporter that already works.

### The producer, read out of its registers: it is waiting on the consumer

`Hg` to each handler, then `g`, during a live deadlock (`tools/thor_gdb_probe.py`):

```
SpursHdlr0 (0x1000009)  r0=ffffffff00000000 r1=00000000d007fec0
                        r2=0000000000cfbab0 r3=0000000004000200
SpursHdlr1 (0x1000008)  r0=0000000000a3000c r1=00000000d0079d60
                        r2=0000000000cfbab0 r3=0000000000000000
busy-PPU   (0x1000004)  r0=0000000000000000 r1=00000000d004dec0
                        r2=0000000000cb88d0 r3=0000000000000000
```

**`SpursHdlr0` holds `0x4000200` in r3**, and the boot log says:

```
sys_spu_thread_group_create(): Thread group "CellSpursKernelGroup" created (id=0x4000200)
```

r3 is the first argument in the PPC ABI, so the SPURS PPU handler is parked in a call
**on the very SPU thread group it exists to feed** — a group join, an event-queue
receive, or equivalent. Proven: the register holds the group id. Inferred, and
strongly: it is blocked in a group call rather than merely holding a stale value,
since r1 and r2 are a live stack pointer and TOC.

Which closes the loop into a circular wait:

- `CellSpursKernel0` (SPU) spins in `GETLLAR` at `pc=0x12b0` waiting for the PPU to
  publish a workload descriptor.
- `SpursHdlr0` (PPU) is parked on the SPU thread group, waiting for the SPU.
- `SpursHdlr1` is idle with `r3=0`, and the one busy PPU is polling a clock.

Nobody is going to move. The remaining question is which side is wrong: either the
SPU should have found work already published, or the PPU should not be waiting on the
group at this point in SPURS startup. **That is answerable by identifying the syscall
`SpursHdlr0` is blocked in** — its LR and PC sit further into the `g` response than
this probe decoded, and RPCS3's own `sys_spu`/`sys_event` logging will name it
directly on the next run with those channels raised.

### Decoded: both producers are parked inside `libsre`

The `g` response is 556 bytes; 32 GPRs and 32 FPRs account for 512, so the specials
start at nybble 1024. Decoding that tail:

| thread | first special (PC) | entry `func` from the boot log |
| --- | --- | --- |
| `SpursHdlr0` | **`0x00cc948c`** | `0xcc930c` |
| `SpursHdlr1` | **`0x00ccb604`** | `0xccb504` |

Both PCs sit a short distance inside their own entry functions, so the first special
is the program counter and the values are live rather than stale. And `0x00cc948c`
is **28 bytes past `0x00cc9470`** — the exact `libsre` offset the log records for the
SPU image load:

```
{PPU[0x1000009] Thread (SpursHdlr0) [libsre: 0x00cc9470]} SPU: Loaded SPU image: SPU-c551925d...
```

So `SpursHdlr0` loaded the SPURS kernel image, advanced a handful of instructions,
and stopped. It is parked in `libsre` immediately after handing the SPU its kernel —
which is exactly where a handler would block waiting for that kernel to report
readiness, and exactly the wait the SPU never satisfies because it is spinning on a
descriptor nobody published.

**The deadlock is now specified end to end in guest terms:**

```
SpursHdlr0  PPU  libsre 0x00cc948c   blocked, holding group 0x4000200 in r3
                                     (28 bytes after loading the SPU kernel image)
CellSpursKernel0  SPU  pc 0x12b0     spinning in GETLLAR on the workload descriptor
                                     (same PC in Eternal Sonata and Folklore)
```

What remains is a single lookup rather than an investigation: **disassemble `libsre`
around `0x00cc948c`** to name the call, or raise `sys_spu`/`sys_event` to Trace and
read it off the next boot. Both are cheap, and either names the syscall whose
emulation is not completing.

### Named — and it corrects the framing

`Log: { sys_spu: Trace }` in `config.yml`, one boot, no rebuild:

```
·T {PPU[0x1000009] SpursHdlr0 [libsre: 0x00cc9470]} sys_spu_thread_group_start(id=0x4000200)
·! {PPU[0x1000009] SpursHdlr0 [libsre: 0x00cc9470]} SPU: Loaded SPU image: SPU-c551925d...
·T {PPU[0x1000009] SpursHdlr0 [libsre: 0x00cc948c]} sys_spu_thread_group_join(id=0x4000200, ...)
```

`libsre: 0x00cc948c` is the exact PC decoded from the GDB register dump — two
independent methods agreeing, which is the first time in this investigation that has
happened.

**And it means `SpursHdlr0` is not the missing producer.**
`sys_spu_thread_group_join` blocks until the group terminates; that is what a handler
thread is *for*. It starts the SPURS kernel group, loads the image, and joins. Nothing
is wrong with it, and the earlier characterisation of "a producer that stopped after
four updates" does not describe this thread.

So the deadlock's shape changes again, and narrows:

- `SpursHdlr0` — correctly blocked in `join`, waiting for the SPU group to end.
- `CellSpursKernel0` — correctly spinning in `GETLLAR`, waiting for a workload.
- **Neither is the bug.** Both are doing what SPURS designs them to do.

The missing party is whoever should be *submitting a workload* — a game thread calling
into the SPURS API (`cellSpursAddWorkload`, taskset creation, or similar). The four or
five writes to the descriptor happened and then stopped, so submission started and did
not continue.

**Next, and now precisely scoped:** trace the `cellSpurs*` HLE calls rather than
`sys_spu`, and find which game thread last called in and what it is doing now. The
busy PPU polling a clock (`0x1000004`) is the obvious suspect and is reachable through
the same GDB stub with the register-decode already working.

### That route is closed: SPURS here is LLE, not HLE

`Log: { cellSpurs: Trace }`, one boot. Four lines, and **none of them is a function
call**:

```
** Imported module 'cellSpurs' (ver=0x1, attr=0x9, ...)          ppu_loader
** Exported module 'cellSpurs' (vnids=0x1c000002, vstubs=0x90034, ...)   x2
```

*Exported* is the operative word. The title supplies its own `cellSpurs`
implementation out of `libsre`, so RPCS3's HLE module is bypassed and **there are no
HLE SPURS calls to trace, by design.** That is consistent with everything else seen:
the SPU kernel is Sony's real image, and both handler threads execute real `libsre`
PPC code.

So the whole SPURS stack — scheduler, workload submission, handler threads — is guest
code running on the emulator's CPUs. The emulator's only involvement is the **lv2
syscalls `libsre` calls into**, and those *are* HLE.

**That redirects the search precisely, and narrows it a lot.** The bug must be in one
of the lv2 primitives SPURS is built on:

- `sys_event_queue_receive` / `sys_event_port_send` — the SPURS event path, already
  visible in the boot log around the kernel group setup
- `sys_lwmutex_*` / `sys_lwcond_*` — the lightweight primitives libsre uses for the
  workload structures
- `sys_spu_thread_group_*` — already traced; `start` and `join` both behaved

Raise those channels rather than `cellSpurs`, and compare the call sequence against
what a correct SPURS handshake requires. This is the first point in the investigation
where the suspect list is short, entirely inside the emulator, and made of functions
that can be read side by side with the PS3 documentation.

### The complete deadlock, all four threads

`Log: { sys_event: Trace, sys_lwmutex: Trace, sys_lwcond: Trace }`. The last
SPURS-side call in the whole log:

```
·T 0:00:10.882 {PPU[0x1000000] main_thread [libsre: 0x00cd5e5c]}
   sys_event_queue_receive(equeue_id=0x8d007d00, *0xd00204f0, timeout=0x0)
```

**`timeout=0` is an infinite wait**, and the main thread never returns from it. That
is the missing producer — the thread that would submit a SPURS workload is parked
inside `libsre` waiting for an event.

| thread | state | verdict |
| --- | --- | --- |
| `main_thread` (`0x1000000`) | `sys_event_queue_receive(0x8d007d00, timeout=0)` in `libsre` | **the missing producer** |
| `SpursHdlr0` (`0x1000009`) | `sys_spu_thread_group_join(0x4000200)` | correct — that is its job |
| `CellSpursKernel0` (SPU) | `GETLLAR` spin at `pc=0x12b0` | correct — waiting for work |
| `_gcm_intr_thread` (`0x1000004`) | VBlank `sys_event_queue_receive` loop, ~60 Hz | **normal**, and not a suspect |

That last row corrects an earlier guess: `0x1000004` was described as "a PPU polling a
clock" and treated as suspicious. It is `libgcm_sys`'s RSX interrupt thread doing
exactly what it should, and emulation is still alive at `0:00:49` with VBlank events
flowing — **only SPURS is stuck**, not the machine.

So the cycle closes:

```
main_thread  --waits on event queue 0x8d007d00-->  (something that never sends)
SPU kernel   --waits on workload descriptor----->  main_thread
```

The SPURS startup handshake requires the SPU kernel to signal readiness through an
event port after `sys_spu_thread_group_start`, at which point the PPU submits work.
The SPU never sends because it is already spinning for a descriptor; the PPU never
writes the descriptor because it is waiting for the signal.

**The question is now a two-sided one with a documented answer**: in the real SPURS
protocol, which side moves first — and does this emulator deliver the SPU's readiness
event to queue `0x8d007d00`? That is a specific claim about `sys_event_port_send` from
SPU context, testable by grepping the trace for any send to that queue id, which this
run shows there is none of.

### Answered: the queue is connected to the SPU group and never receives anything

Every reference to `0x8d007d00` in a full traced boot — exactly two:

```
·W {main_thread [libsre: 0x00ccb04c]}
   sys_spu_thread_group_connect_event_all_threads(id=0x4000200, eq=0x8d007d00, req=0xffffffff...)
·T {main_thread [libsre: 0x00cd5e5c]}
   sys_event_queue_receive(equeue_id=0x8d007d00, timeout=0)
```

`main_thread` **connects the SPURS kernel SPU thread group to this queue** — with
`req=0xffffffff…`, i.e. all event classes — and then blocks on it forever. **No send
to that queue ever appears**, from the SPU or anywhere else.

So the handshake is fully mapped, and the gap is exactly one edge:

```
SPU group 0x4000200  --connected to-->  queue 0x8d007d00  --received by-->  main_thread
                     \______ the event that should traverse this never does ______/
```

That makes the remaining question a narrow one about **emulator** code, not guest
code: SPURS kernels signal the PPU by writing the SPU's outbound interrupt mailbox
(`SPU_WrOutIntrMbox`), which lv2 routes to whatever queue the group was connected to.
Two candidates, and they are distinguishable:

1. **The SPU never writes the mailbox**, because it is already spinning in `GETLLAR`
   — in which case the guest is waiting on itself and the real fault is earlier, in
   why the kernel entered its poll before signalling.
2. **The SPU writes it and the emulator drops it** — a defect in the
   `SPU_WrOutIntrMbox` channel handler or in the
   `sys_spu_thread_group_connect_event_all_threads` routing.

**Distinguishing them is one more trace**: log SPU channel writes, or add a counter to
the `SPU_WrOutIntrMbox` handler, and see whether the SPU attempts a send at all. If it
does, case 2 is the bug and it is entirely inside `SPUThread.cpp` plus the lv2 SPU
group event path. If it does not, the fault is upstream of the poll.

That is the smallest well-posed question this investigation has produced, and it is
two files wide.

### `SPU: Trace` does not answer it, and says why — plus one hard new fact

`Log: { SPU: Trace }`, 36,927 lines. Two results, one useful and one a warning.

**The useful one.** Exactly *one* DMAC line exists in the whole run:

```
·T 0:00:10.758 {SPU[0x0000200] CellSpursKernel0 [0x012b0]}
   SPU: DMAC: (GETLLAR  #00 0x00100:0x009d4d80 0x80)
```

LSA `0x100`, EA `0x9d4d80`, 128 bytes — independently confirming every number in the
stall report from a different code path. And it is the **only** MFC command the SPURS
kernel ever issues. It makes one `GETLLAR` and never advances to another, which means
it is stuck on its *first* memory operation after the kernel image starts. A kernel
that has not completed its first `GETLLAR` has plainly not reached any later point at
which it would signal readiness.

**The warning.** `WrOutIntrMbox` appears zero times — and so does `get_ch_count`, and
so does `set_ch_value`. **Channel operations are not logged at this level at all**, so
the zero proves nothing about whether the SPU attempted a mailbox write. That is the
seventh time in this investigation that an absence has looked like evidence, and it is
recorded rather than acted on.

So the two candidates stand undistinguished by *logging*, but the DMAC fact leans
hard toward the first: the SPU is stuck at its first MFC command, so it is unlikely to
have reached a signalling point. Confirming that needs a counter in the
`SPU_WrOutIntrMbox` handler at `SPUThread.cpp:7748` — reported through a channel
proven to reach the log, which on this device means `spu_log`, not `vm_log`.

The handler itself is present and substantial, roughly two hundred lines with a
raw-SPU branch and an HLE dispatch path, and notably it resets `last_getllar_addr` on
entry — so whoever wrote it already knew the mailbox and `GETLLAR` state interact.
That is the file to read next, with the SPURS startup protocol beside it.

### Answered: the SPU never signals. The event is not being dropped.

A one-shot report was added at the top of the `SPU_WrOutIntrMbox` handler
(`SPUThread.cpp:7748`), going through `spu_log` — the channel proven to reach the
file — rather than counting, and rather than relying on channel tracing that does not
exist.

Result: **the line never appears, while the `GETLLAR` stall does.**

Unlike the six silences before it, this negative is trustworthy, and the preconditions
were checked before it was believed:

| precondition | evidence |
| --- | --- |
| instrument in the shipped binary | `grep -a "first write by"` → 1 |
| sink reaches the log | the `GETLLAR stalled` lines use `spu_log` and appear |
| code path exercised | stall reproduced in the same run |

**So candidate 2 is eliminated. The emulator is not dropping a mailbox event — the
SPU never sends one.** The SPURS kernel issues exactly one `GETLLAR`, never advances
to a second MFC command, and never signals the PPU.

Which turns the question inside out one last time. The PPU *did* write the descriptor
— `counter=4`, with neighbours at 0 and 2 proving those are real per-line writes. So
the sequence is:

1. `main_thread` sets up the descriptor and connects the SPU group to queue `0x8d007d00`.
2. `main_thread` blocks on that queue, waiting for the kernel to report in.
3. The kernel starts, issues one `GETLLAR` on the descriptor, and **does not accept
   what it reads** — it spins instead of signalling.

The descriptor was written and the SPU can read it, so this is no longer a
delivery, ordering or coherence problem. **The kernel is reading a value it considers
invalid.** The remaining question is what it expects there — a magic number, a
version, a ready flag — and why the emulator's setup path leaves it different from
what real hardware would.

That is answerable by dumping the 128 bytes at `0x9d4d80` at the moment of the stall
and comparing against the SPURS descriptor layout. The stall reporter already runs at
exactly that point and already has the address.

### The descriptor, dumped: the polled half is all zero

```
0x9d4d80       0000000000000000 x8            <- the half the kernel reads
0x9d4dc0 +64   0000000000000008 0000000000000000
               0000000000000001 0000000000000000
               0000000000000000 ffffffff00000000
               ff01008000ff0080 0000000000000000
```

**The first 64 bytes are entirely zero; the second 64 carry real structure.** The
`GETLLAR` targets `lsa=0x100` for `0x80` bytes, so the kernel pulls the whole line and
reads a workload area that contains nothing.

That corrects the previous section, which said the kernel "is reading a value it
considers invalid". It is not. **It is reading zeros and correctly concluding there is
no work to run** — which is precisely what a scheduler should do with an empty
workload bitmap. The SPU is exonerated for the third time, alongside the reservation
machinery and the notifier.

So every participant is now individually correct and the system is still deadlocked:

| party | doing | correct? |
| --- | --- | --- |
| SPU kernel | polling an empty workload area | **yes** |
| `SpursHdlr0` | `sys_spu_thread_group_join` | **yes** |
| `main_thread` | `sys_event_queue_receive`, waiting to be told the kernel is up | **yes**, if that is the protocol |
| descriptor | zero in the polled half | consistent — nobody added a workload |

Which isolates the fault to the **startup ordering**. On real hardware SPURS must be
able to bootstrap from exactly this state: kernel running, no workloads yet. Something
has to break the symmetry — the kernel signalling readiness without work, or the PPU
proceeding without waiting. This emulator produces a state where neither happens.

**The remaining question is documentary, not diagnostic:** what does the SPURS
initialisation sequence specify at this point, and which side does the real hardware
unblock first? Everything measurable has been measured. The next step is reading the
protocol, and the data to read it against is now in this file.

### The protocol is in this repo, and it corrects the diagnosis again

RPCS3 ships its own **HLE** SPURS in `ps3fw/cellSpurs.cpp`, written from the
reverse-engineered protocol. This title runs SPURS LLE, but the HLE code is a
reference for what the sequence is *supposed* to be — and it matches the observed
threads exactly:

```
714:  ensure(sys_spu_thread_group_start(ppu, spurs->spuTG) == 0);
716:  const s32 rc = sys_spu_thread_group_join(ppu, spurs->spuTG, ...);
```

That is `SpursHdlr0`, confirmed: start the group, then join it. Structurally correct.

But the event-queue receive is somewhere else entirely — `cellSpurs.cpp:825`:

```cpp
void _spurs::event_helper_entry(ppu_thread& ppu, vm::ptr<CellSpurs> spurs)
{
    while (true)
    {
        ensure(sys_event_queue_receive(ppu, spurs->eventQueue, vm::null, 0) == 0);
        ...
        if (event_src == SYS_SPU_THREAD_EVENT_EXCEPTION_KEY) { spurs->exception = 1; ... }
    }
}
```

**That receive is an event *helper* loop, not a startup handshake.** It is a service
thread whose entire job is to block indefinitely waiting for SPU exceptions and
similar events. Blocking there forever is its correct steady state.

Which corrects the earlier diagnosis a second time. `main_thread` was called "the
missing producer" on the strength of being parked in `sys_event_queue_receive`. It is
not producing anything and was never going to — it is running libsre's equivalent of
`event_helper_entry`, and that call is **supposed** never to return.

So the tally of exonerated parties is now complete:

| party | verdict |
| --- | --- |
| reservation machinery / notifier / ARM64 atomics | correct, measured three ways |
| SPU kernel polling an empty workload area | correct |
| `SpursHdlr0` in `sys_spu_thread_group_join` | correct, matches HLE reference line 716 |
| `main_thread` in `sys_event_queue_receive` | correct — it is the event helper |

**Nothing observed so far is misbehaving.** Which means the fault is in something not
yet observed: whichever thread should have called the workload-submission path never
did, and it is not any of the four threads examined. The next move is to find what the
game's remaining PPU threads are doing — the GDB stub lists eleven, and only four have
been accounted for.

### The class of bug this belongs to

Worth recording because it is already in the tree, commented out. In the newer
rpcsx PPU interpreter, `rpcsx/cpu/cell/ppu/semantic/ppu.cpp:3496`:

```cpp
void SEMANTIC(STW)(PPUContext &context, Instruction inst) {
  ...
  // Insomniac engine v3 & v4 (newer R&C, Fuse, Resitance 3)
  // if (value == 0xAAAAAAAA) [[unlikely]] {
  //   vm::reservation_update(vm::cast(addr));
  // }
}
```

A plain `STW` used by guest code as an SPU wakeup, needing an explicit reservation
bump because an ordinary store does not make one. This exact code is **not** the
cause here — the shipped profile uses `ppu_decoder = llvm_legacy`, which runs
`PPUTranslator` rather than this interpreter — but it documents the failure mode:
*PPU signals through a plain store, SPU waits on a reservation, nothing connects
them*. If the `ntime` check above comes back clear, this is the shape to look for.

## What is still open

**Is this a regression?** Not established. The repro costs ten seconds, so a bisect
is now practical, which it was not when reproducing meant playing to a combat
encounter.

**Why does the reservation never settle?** That is the actual question now. The SPU
is waiting on a reservation at a fixed address; something either holds it or
republishes it forever. The next step is to instrument what the other side of that
reservation is doing, rather than what this thread is doing while it waits.

## Full thread census, and the descriptor that was not zero

Four threads had been examined by hand. The GDB stub knows about twelve, so this
round enumerated all of them (`tools/thor_gdb_all_threads.py`) against a fresh
Folklore boot that a watchdog independently confirmed stalled — log static for
30 s with the process alive, and all eight cores at 0.0% *before* anything
attached.

Three properties of the stub, all learned by tripping over them:

* it implements `qfThreadInfo` and **nothing else** — no `qThreadExtraInfo`, so
  thread names cannot come from GDB. They come from `RPCSX.log`, which prints
  `PPU[0x100000c] Thread (SpursHdlr0)`.
* **connecting pauses emulation** (`Emulation is being paused... (mark=0)`).
  Fine for state inspection, but it is not a live view.
* **disconnecting kills the stub**: `Thread terminated due to fatal error: Tried
  to read char, but no data was available` (`GDB.cpp:241`). One probe per boot.

### Thread ids are not stable across boots

`0x1000009` was `SpursHdlr0` in the earlier boot and is `LoadThreadMain` in this
one. The original probe hardcoded that id-to-name mapping, which means any
attribution made through it is only as good as the boot it was taken from. Ids
are assigned in creation order; recover them from the log, never from memory.

| tid | name | pc | |
| --- | --- | --- | --- |
| 0x1000000 | main_thread | 2a9ac0 | |
| 0x1000001 | _cfg_evt_hndlr | 586bd4 | |
| 0x1000002 | _gcm_intr_thread | 7f833c | |
| 0x1000003 | FlipThreadMain | — | **absent: exited** |
| 0x1000004 | thread_sys_cache | 15191c | |
| 0x1000005-7 | _fs_aio_thread ×3 | 8df17c | all three identical, as they should be |
| 0x1000008 | AioThread | 12161c | |
| 0x1000009 | LoadThreadMain | — | **absent: exited** |
| 0x100000a | LogoThreadMainFast | 1d9564 | |
| 0x100000b | SpursHdlr1 | 81b604 | the event helper: blocks forever by design |
| 0x100000c | SpursHdlr0 | 81948c | r3=0x4000100, the group join |

The three `_fs_aio_thread`s sharing one pc is the check that the ordering
assumption holds. `main_thread`'s last log line is at 0:00:06.913, in the middle
of SPURS init, and the log then runs for two more minutes without it.

### The descriptor is not all zero

The previous boot's polled line was all zero, and this file concluded the SPU was
"correctly concluding there is no work to run". **That does not generalise.**
Same title, same `pc=0x12b0`, different boot:

```
descriptor 0x10a60c00:     0000000000000001 0000000000000000 x7
descriptor 0x10a60c40 +64: 0000000000000001 0000000000000000 0000000000000001 0000000000000000
                           0000000000000000 ffffffff00000000 ff01008000ff0000 0000000000000000
```

Decoded against `CellSpurs` (`ps3fw/include/rpcsx/fw/ps3/cellSpurs.h:665`), big-endian:

| offset | field | value |
| --- | --- | --- |
| 0x00 | `wklReadyCount1[7]` | **1** |
| 0x20 | `wklCurrentContention[7]` | **0** |
| 0x40 | `wklMinContention[7]` | 1 |
| 0x50 | `wklMaxContention[7]` | 1 |

Workload 7 is ready, asks for one SPU, is allowed one, and has none. The SPU
kernel re-reads that line and does not take the work.

### The test that separates the two remaining explanations

The dump above reads current memory through `get_super_ptr`. The SPU program does
not read that — it reads what `GETLLAR` left in local store. Those can disagree,
and which way they disagree decides which half of the emulator is at fault:

* **ls != mem** — the SPU polls a stale line. A coherency fault, and on ARM64,
  with weaker ordering than the x86 this code was written against, a live
  possibility rather than a theoretical one.
* **ls == mem** — the SPU holds the current value and declines to schedule. The
  fault is guest-side.

`SPUThread.cpp` now prints `ls==mem`, `snapshot==mem` and `ls==snapshot` alongside
the stall report. Both previous conclusions in this file were drawn from a single
boot and neither survived a second one, so this one gets measured.

## Resolved: `mov_rdata` copied nothing on ARM64

The bug was in the emulator, one `#elif` away from the code every other
investigation in this file circled. `SPUThread.cpp:1331`:

```cpp
#elif defined(ARCH_ARM64) && defined(__clang__)
    // 22 lines of comment about a reverted LDP/STP implementation
#else
    std::memcpy(_dst, _src, 128);
#endif
```

An earlier LDP/STP version was reverted after a guest crash, and the `#elif`
was left behind holding nothing but its own postmortem. Every ARM64 + clang
build since compiled `mov_rdata` into a function that copies nothing.

**The compiler had been reporting it the entire time**, in a line that scrolls
past on every build:

```
SPUThread.cpp:1301:25: warning: unused parameter '_dst'
SPUThread.cpp:1301:50: warning: unused parameter '_src'
```

Unused parameters on the function whose only job is to write `_dst`.

### How it produced this hang

`mov_rdata` is the copy every reservation is validated against:

```
rdata never refreshed from memory
  -> cmp_rdata(rdata, data) can never match
  -> the GETLLAR retry loop can never settle
  -> any SPU whose reservation line changed under it spins forever
```

Instrumenting all four `continue` paths in the retry loop settled it in one
boot:

```
continue-path counts: unique_lock=0 tsx_unavailable=0 counter_moved=0
                      unstable_copy=10093915
```

Ten million failures of the one comparison that depends on the copy, and zero
on everything else.

### The guest was innocent the whole way through

Every party this file accused and then exonerated really was correct. Workload 0
had `wklReadyCount1=1`, `min=1`, `max=1`, `wklCurrentContention=0` and
`wklState1=02 RUNNABLE` — every gate in `spursKernel1SelectWorkload` passed. The
SPU never acted on it because the emulator never handed it the bytes.

**Result: Folklore boots to its title screen at 60.01 FPS**, PPU 9.5%, SPU 1.2%,
RSX 1.4%. It had previously never rendered a frame.

### What this cost, and the lesson

This file contains three earlier conclusions that were wrong: a Vulkan fence
hypothesis, "the writer is an atomic store, not a notify", and "the SPU reads
zeros and is correctly concluding there is no work". Each was reasoned from
static reading or a single boot. The bug was found by counting which branch
actually executed.

Two habits would have found it in minutes rather than across several sessions:

* **Read the build warnings.** The compiler names this defect precisely and
  says it on every build.
* **When a loop will not exit, count its exits.** Four counters and one boot
  beat every amount of reading the surrounding code.

An audit of all 625 files under `Emu/` and `util/` for `#if`/`#elif` ARM64
branches containing only comments found this as the only one.

### Scope of the regression

`git log -S` dates it exactly. The `#elif defined(ARCH_ARM64) && defined(__clang__)`
arrived with `772f8f92b`, `dbddfaf92` put the LDP/STP body in it, and
**`b46198f0b` (2026-08-07 20:44) removed the body and left the branch** — the
state that broke the copy. So the empty branch existed for roughly one day, and
this fix explains hangs observed after that point.

It does **not** retroactively explain everything in this file. The earlier
Eternal Sonata boot deadlock predates `b46198f0b` and had some other cause; do
not fold it into this one without re-measuring.

Worth noting for its own sake: that revert was made *precautionarily*, to
protect the most correctness-sensitive copy in the emulator from an unproven
change — and it produced a far worse defect than the one it was guarding
against. The lesson is not that the revert was wrong. It is that removing a
function body is a code change like any other, and wants the same check that
adding one does: a build, and a look at what the compiler says about it.
