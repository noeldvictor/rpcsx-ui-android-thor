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
| emulator clock | frozen, four runs, `0:00:08.31`–`0:00:08.54` |
| `rsx::thread` CPU | 100–107%, continuously, indefinitely |
| thread state | `R` (running), `wchan=0` — not blocked |
| system vs user time | `dSys/dUser = 5.8` — ~85% in the kernel |
| forward progress | none in 18+ minutes; zero files written to the cache |
| process health | alive; Performance Sensor still logs every 10 s, RAM flat |

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

## The two unbounded waits it could be in

Both live in `Emu/RSX/VK/vkutils/sync.cpp`, and both have the same defect: when
`timeout == 0` they poll forever with no upper bound at all.

`wait_for_fence` polls `vkGetFenceStatus` in a bare loop. `wait_for_event` is
worse — the timeout check is *inside* `if (timeout)`, so passing zero does not
mean "no timeout", it means the deadline branch is never even evaluated:

```cpp
if (timeout)
{
    const auto now = freq ? rx::get_tsc() : get_system_time();
    ...
    if ((now > start) && (now - start) > timeout)
    {
        rsx_log.error("[vulkan] vk::wait_for_event has timed out!");
        return VK_TIMEOUT;
    }
}

rx::pause();
```

Both are `vkGet*Status` calls into the KGSL driver, which matches the 85% kernel
share. Which of the two is the live one is **not yet established** — see the open
question below. Saying "it is the fence poll" would be the inference this project
has gotten wrong repeatedly.

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

## The open question, and the instrument that answers it

**Is this a regression, and which of the two waits is it in?**

Neither is answerable with the build currently installed. It is a release build:
`run-as` refuses it (`package not debuggable`), the device has no root, and so
`/proc/<tid>/syscall` is `Permission denied` and `debuggerd -b` is unavailable.
`/proc/<tid>/stat` *is* readable, which is where the user/system split above came
from, and that is the limit of what this build will give up.

What breaks it open is a debuggable build, at which point:

- `/proc/<tid>/syscall` names the exact syscall and its arguments, which separates
  `vkGetFenceStatus` from `vkGetEventStatus` immediately;
- `simpleperf` will sample the loop directly;
- the wait profiler can go in the same build, so the GETLLAR percentage sweep and
  this question get answered by one install.

For the regression question, the repro is cheap enough that a bisect is now
practical — which it was not when reproducing meant playing to a combat encounter.

Note that fixing the unbounded wait is **not** the same as fixing the hang. Giving
these waits a real timeout converts an unrecoverable freeze into a logged error and
a chance to recover, which is worth doing on its own merits. It does not explain
why the GPU work never completes, and shipping it first would remove the symptom
that makes the root cause findable.
