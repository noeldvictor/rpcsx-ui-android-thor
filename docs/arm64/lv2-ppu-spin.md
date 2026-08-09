# 74% of all cycles are a nop-spin in the lv2 wait layer

This is the first finding in this project that came from a **symbolized profile of a
healthy run** rather than from reading a manual. It is also the largest. Everything
below the "Measured" heading is measurement; everything below "Predicted" is not.

## Measured

Folklore, title screen, holding 60.01 fps. `simpleperf record --app net.rpcsx.easy
-f 1000 -g --duration 25`, **31,657 samples, 0 lost**, symbolized against the
matching unstripped library (build ID `c978e671…`, verified by
`binary_cache_builder.py`, not assumed). The run was confirmed clean first:
`grep -c 'home menu|being paused'` returned **0**, so no phase mismatch.

```
Overhead  Sample  Symbol
47.82%    13189   sys_event_queue_receive(ppu_thread&, ...)
26.09%     7993   _sys_lwcond_queue_wait(ppu_thread&, ...)
 1.96%      641   [kernel.kallsyms]
 1.30%      599   memcpy_opt
 1.17%      320   shared_mutex::imp_lock(unsigned int)
```

**73.9% of all CPU cycles in two lv2 wait functions**, spread over three PPU
threads (`0x100000e` 39.7%, `0x100000c` 26.3%, `0x1000002` 8.5%).

The call graph settles what kind of time it is. `cpu-cycles` only samples a thread
while it is *running*, so a genuinely blocked thread contributes nothing. Both hot
functions report their cost as **self** time — `[hit in function]` 99.3% — and
neither reaches `atomic_wait_engine::wait`. The contrast is in the same profile:

```
 3.73%  sys_timer_usleep
        └ 75.71% lv2_obj::wait_timeout
                 └ 81.70% atomic_wait_engine::wait     <-- actually sleeps
```

`sys_timer_usleep` parks on a futex and costs 3.7%. The two hot ones never get
there. They are spinning.

## Mechanism

`kernel/cellos/src/sys_event.cpp:476`, and seven identical copies:

```cpp
for (usz i = 0; cpu_flag::signal - ppu.state && i < 50; i++) {
    rx::busy_wait(500);
}
```

Two ARM64 facts turn that into the profile above.

**`busy_wait` counts generic-timer ticks, and the timer is 19.2 MHz.**
`rx::busy_wait` spins until `get_tsc()` advances by its argument, and `get_tsc()`
reads `cntvct_el0`. `CNTFRQ_EL0` on this chip is **19.2 MHz**, so 500 ticks is
**26.0 µs**, and fifty of them is **1.3 ms of spinning per pass** through the outer
loop — before the code even looks at `timeout`. The equivalent on the x86 hardware
these counts were written for, at a ~3 GHz TSC, is about 1 µs for the whole thing.
The header comment at `busy_wait` says the call sites were "retuned by hand against
Thor's real 19.2 MHz timer", and they were — but 500 ticks is 26 µs, not the ~1 µs
the structure assumes. The retune fixed a 1-FPS lock convoy; it did not make these
waits short.

**`pause()` is `yield`, which is a nop here.** On an SMP core with no sibling
thread, `YIELD` retires doing nothing — it does not stall the pipeline, does not
drop the clock, and does not save power. So the 1.3 ms is spent issuing
instructions at full rate. This is the video's "Don't use Yield in place of Pause"
item, and `spin.md` already measured the alternatives: `ISB` costs 23% more, `nop`
is equivalent. **Neither of those is the fix** — the instruction is not the problem,
the 1.3 ms is.

## The eight sites

Every PPU blocking primitive has the same loop:

| file | line |
| --- | --- |
| `sys_cond.cpp` | 456 |
| `sys_event.cpp` | 476 |
| `sys_event_flag.cpp` | 197 |
| `sys_lwcond.cpp` | 492 |
| `sys_lwmutex.cpp` | 196 |
| `sys_rwlock.cpp` | 153, 357 |
| `sys_semaphore.cpp` | 1541 |

Nine `busy_wait(500)` call sites exist in the tree; eight of them are this loop.
The profile happens to catch the two that this title leans on, but the shape is the
whole guest synchronization layer, not one syscall.

## Why the existing spin work missed it

`spin.md` records "93% of all emulator spin is the SPU `GETLLAR` wait". That number
came from the **wait profiler**, which counts the sites it was told to instrument —
all of them SPU-side. These eight PPU sites were never instrumented, so they could
not appear, and their absence read as evidence they were not there. This is the same
failure the ledger already lists twice under a different name: *a search that finds
nothing and a search that searches nothing look identical.* A sampling profiler has
no such blind spot, which is exactly why it found this and three sessions of counter
work did not.

## Predicted — not measured

State it before touching the device, per the ledger's checklist.

**Mechanism.** Replace a fixed 1.3 ms of nop-spin with a WFE park on the
`ppu.state` cacheline. `rx::spin_on_cacheline_once` in `rx/asm.hpp` already
implements exactly this — `LDAXR` to arm the exclusive monitor, `WFE`, `CLREX` —
and it is already used elsewhere in this fork. WFE drops the core to a low-power
state until the monitor is cleared by the store that signals the thread, so the
wakeup path is the signal itself rather than a timer. `FEAT_WFxT` is absent on this
chip so WFE cannot carry a timeout, but this loop rechecks its own conditions on
every pass, which is the pattern `spin_on_cacheline_once` documents.

**Predicted magnitude, with the arithmetic.** Folklore holds 60.01 fps whether or
not this spin happens, so **none of it is throughput and all of it is power**. From
the reference table: Folklore title screen is 2.23 cores busy against a 0.68-core
idle floor, so ~1.55 cores of real work, of which 74% — about **1.15 cores** — is
this spin. The leaked-process measurement gives a rate to price it at: 210% CPU cost
1.88 W, so ~0.9 W per core. **Predicted saving ≈ 1.0 W**, against a ~3.5 W loaded
draw. That is roughly 30% of system power, and it is a "cooler" win, not a "faster"
one.

**What would falsify it.** If the signal usually arrives *inside* the 1.3 ms window,
the spin is buying real latency and parking will show up as worse frame pacing —
measure p95 frame time, not mean, because a capped 60 fps hides it. If WFE wakeups
are missed or delayed, the title stalls outright.

**The confound that would fake a win.** Sleeping instead of spinning may let the
scheduler migrate the PPU thread off its big core onto an A510. Cores-busy would
drop and power with it, while the emulator got slower. **Check the per-cluster
core-busy split across arms, not just the total** — the same check that caught all
three earlier fake wins.

## Status

Measured: the profile, the mechanism, the eight sites. **Not** measured: that
changing it helps. The next step is one A/B behind a property, with p95 frame time
and per-cluster cores-busy in both arms.

---

# Measured on device: the spin costs 67% of emulator CPU and buys nothing

The prediction above was ~1.15 cores of waste. Measured, on Folklore's title
screen, with the spin budget behind `debug.rpcsx.thor.lv2_spin`:

| `lv2_spin` | emulator CPU (cores) | frame rate |
| --- | --- | --- |
| **50** (default) | **1.200, 1.201, 1.196** | 62.5 |
| 16 | 0.694 | 62.5 |
| 1 | 0.419 | 62.5 |
| **0** | **0.390, 0.387** | 62.5 |

**A 67.6% reduction in emulator CPU time — 0.81 cores freed — at an identical
frame rate.** The three baseline arms and the two zero arms were taken in two
independent alternating runs and agree to within 0.005 cores, so the effect is
roughly 160 times the run-to-run spread.

**Metric.** `utime+stime` from `/proc/<pid>/stat` over a fixed 40 s window, after
a 90 s settle. This was chosen over system power for two reasons. The other Claude
session's Xenia was intermittently running on the same device, and system power
cannot tell whose watts it is measuring, while our own process's CPU time can.
And it is immune to the confound the prediction called out: **if the win were
threads migrating to A510s, CPU time would stay flat or rise — the same seconds
on slower cores — not fall by two thirds.** Battery current was logged and is
unusable, as expected with USB attached; it reads charge current, not draw.

**Parity.** Frame rate is derived from the auditor's `on_frame_end call #N` line,
quantised to 6.25 fps by its 250-frame cadence. Every arm reported above sat at
exactly 62.5. One arm did not and is **excluded as void**: `lv2_spin=4` returned
1.207 cores at **50.0 fps**, breaking monotonicity in both columns at once, which
is the signature of an arm still settling rather than a real reading. It is listed
here rather than dropped silently.

## What this does and does not establish

Established: on this title and this scene, 1.3 ms of pre-sleep spinning in the
lv2 wait layer costs two thirds of the emulator's CPU and returns no frame rate.
The curve is monotone and most of the win is already there by `lv2_spin=16`.

Not established, and the reason **the default is still 50**:

* **One title, one scene.** Folklore's title screen is not sync-heavy. The spin
  exists to catch signals that arrive quickly, and a scene with heavy PPU/SPU
  handoff is exactly where removing it could cost latency.
* **Frame rate is not frame pacing.** The parity check is quantised to 6.25 fps
  and a capped 60 fps hides p95 stutter by construction. A latency regression
  would not show in this table.
* **Power is inferred, not measured.** 0.81 cores at the ~0.9 W/core rate from the
  leaked-process measurement is ~0.7 W, but that rate came from a different
  workload and USB was attached throughout.

What would justify flipping the default: the same sweep on a second title and on a
gameplay scene rather than a title screen, reporting **p95 frame time**, on
battery with the second screen for real watts.

---

# Second title: the win collapses under load, and the headline was over-claimed

Eternal Sonata, gameplay, same harness, same alternating design:

| `lv2_spin` | emulator CPU (cores) | frame rate |
| --- | --- | --- |
| 50 (default) | 3.230, 3.155 | 31.2, 25.0 |
| 0 | 3.010, 3.087 | 31.2, 31.2 |

Baseline mean **3.193**, zero mean **3.049** — a **4.5% reduction, 0.14 cores**,
against a within-arm spread of ~0.076. The delta is about twice the spread, which
is suggestive and not decisive. Frame rate is unchanged, except one baseline arm
that read 25.0 where every other arm read 31.2; its CPU was in line with the other
baseline, so it is reported rather than dropped.

**This corrects the framing of everything above.** The profile that started this
was taken on Folklore's *title screen*, and 73.9% of cycles were in lv2 waits
because on that workload the emulator is mostly waiting. Under real gameplay load
the same threads have actual work to do, they enter those waits far less, and the
spin falls from two thirds of CPU to a twentieth of it.

So the honest summary is:

* The spin is **always pure waste** — no arm on either title lost frame rate by
  removing it, on any run.
* **How much waste depends entirely on how idle the workload is.** Light scene:
  0.81 cores. Gameplay: 0.14 cores.
* **"74% of all cycles" is true of a title screen, not of the emulator.** Quoting
  it without the workload attached is exactly the error this project's ledger
  keeps recording — a measurement that is correct over a population narrower than
  the claim built on it.

Which does not make it worthless. 0.14 cores is free, and menus, title screens,
loading and 2D titles are a real share of hand-held play, where the saving is the
large one and battery is the thing the user notices. But it is not a 67% win for
the emulator, and this document said so for one commit.

## Where that leaves the default

Still `50`. The gameplay evidence is weak (2x spread), the fps parity check is
quantised too coarsely to see p95 stutter, and the case for changing a default
that guards latency across every lv2 primitive needs better than that. What is
worth doing next is the sweep on gameplay with **frame-time percentiles** rather
than a frame counter, and on battery with the second screen so the power claim
stops being inferred.

---

# Frame-time percentiles settle it, and the default is now 0

The previous section kept the default at 50 because the frame counter was
quantised to 6.25 fps and could not see p95 stutter. That was a real objection with
a cheap answer: `dumpsys SurfaceFlinger --latency` on the app's BLAST layer returns
per-frame present timestamps, so the whole distribution is available with no
rebuild and no instrumentation.

Eternal Sonata, gameplay, four arms in **both orders** to cancel drift, ~750 frame
intervals each:

| order | `lv2_spin` | n | p50 | p95 | p99 | worst | CPU |
| --- | --- | --- | --- | --- | --- | --- | --- |
| run 1 | 50 | 753 | 33.73 ms | 50.60 | 50.61 | 67.5 | 2.391 |
| run 1 | 0 | 752 | 33.74 ms | 50.61 | 50.62 | 50.6 | 2.291 |
| run 2 | 0 | 753 | 33.74 ms | 50.60 | 50.62 | 67.5 | 2.203 |
| run 2 | 50 | 752 | 33.73 ms | 50.60 | 50.61 | 67.5 | 2.375 |

**p50, p95 and p99 agree across all four arms to within 0.02 ms.** Removing the
spin costs nothing at any percentile, not just on average. CPU is lower in every
pairing — 2.383 mean spinning against 2.247 not spinning, 5.7% — and combined with
the earlier gameplay run that is **four baseline arms and four zero arms, with
every baseline higher than the zero arm taken in the same run.**

The layer to query is the BLAST one:

```sh
adb shell dumpsys SurfaceFlinger --list | grep BLAST | grep RPCSXActivity
adb shell dumpsys SurfaceFlinger --latency '<that layer>'
```

`SurfaceView[...]#N` without `(BLAST)` returns all-zero rows, and the layer's
numeric suffix changes every boot, so resolve it per arm rather than hardcoding it.
This is a better frame instrument than anything else in this repo — it needs no
build flag, no property and no code, and it reports the distribution rather than a
mean. It should have been the first thing reached for.

## Decision

**Default flipped from 50 to 0.** `debug.rpcsx.thor.lv2_spin=50` restores upstream
behaviour instantly if a title ever needs it.

The case: no measured latency cost at any percentile on the heavy title, in both
arm orders; consistently lower CPU on both titles tested; and the mechanism is
understood rather than empirical — a 1.3 ms nop-spin in front of a futex sleep that
already works. Shipping the configuration that was actually measured, rather than a
hedge value that was not, is the point: `lv2_spin=4` was never measured cleanly, so
it would have been a guess dressed as caution.

What is still not measured: titles beyond these two, and watts. The power claim
remains inferred from cores freed, because USB stayed attached throughout and
`current_now` reports charge current. That needs the second screen on battery.

## Shipped default verified on device

Not inferred from the source change — measured with the property **unset**, which
is the path a user gets, against an explicit `50` on the same build:

| `debug.rpcsx.thor.lv2_spin` | n | p50 | p95 | p99 | CPU |
| --- | --- | --- | --- | --- | --- |
| unset (shipped default) | 750 | 33.72 ms | 50.59 | 50.60 | **2.294 cores** |
| `50` (upstream behaviour) | 751 | 33.73 ms | 50.60 | 50.61 | 2.443 cores |

**6.1% less CPU on gameplay with frame-time percentiles matching to 0.01 ms.** The
default path is the measured path, and the escape hatch works.
