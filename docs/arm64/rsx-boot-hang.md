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

## It is one title, not the emulator

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

**Next diagnostic:** establish who last touched the reservation address the SPU is
stuck on. That needs the `RPCSX_THOR_ES_SPU_EXPERIMENTS` probe compiled in, since
it logs the address, PC, LSA and retry count and is otherwise a `constexpr` stub on
Android. Confirming the PPU caller wants a frame-pointer build or a breakpoint,
and is worth less than the probe.

## What is still open

**Is this a regression?** Not established. The repro costs ten seconds, so a bisect
is now practical, which it was not when reproducing meant playing to a combat
encounter.

**Why does the reservation never settle?** That is the actual question now. The SPU
is waiting on a reservation at a fixed address; something either holds it or
republishes it forever. The next step is to instrument what the other side of that
reservation is doing, rather than what this thread is doing while it waits.
