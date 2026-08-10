# Every busy_wait site, and what it actually costs on this chip

`rx::get_tsc()` is `mrs cntvct_el0` — verified in `rx/tsc.hpp:18`, not assumed —
and `CNTFRQ_EL0` on this device is **19.2 MHz**. `rx::busy_wait(n)` spins until the
counter advances by `n`, so **every call site's duration is `n / 19.2` µs and can
be computed without running anything.** That is the whole method here: one measured
hardware constant turns a code sweep into a table of microseconds.

The x86 hardware these counts were written for has a ~3 GHz TSC, so the same
literal is **156× shorter** there.

| µs on Thor | call | site | verdict |
| --- | --- | --- | --- |
| 260.4 | `busy_wait(5000)` | `Emu/Memory/vm.cpp:675` | deliberate, config-gated on `ppu_reservation_priority_over_spu`; the duration *is* the feature |
| **156.2 ×10 = 1.56 ms** | `busy_wait()` | `rx/SharedMutex.cpp:28, 94, 133` | **same defect as lv2, one layer down — see below** |
| 156.2 | `busy_wait()` | `util/Thread.cpp:2232` | inside `#ifdef __APPLE__`. **Dead on Android.** |
| 156.2 | `rx::busy_wait()` | `Emu/RSX/VK/VKGSRender.cpp:3050` | exceptional path; logs `[Performance warning] Unexpected ZCULL read caused a hard sync` each time, so it is self-reporting and rare |
| 156.2 | `rx::busy_wait(3000)` | `kernel/cellos/src/sys_spu.cpp:1814` | a lambda literally named `short_sleep`, commented "a small period of sleep". It is 156 µs. Thread-group termination only, so rare |
| **26.0 ×N** | `rx::busy_wait(500)` | nine lv2 wait loops | **fixed** — [`lv2-ppu-spin.md`](lv2-ppu-spin.md) |
| 15.6 | `rx::busy_wait(300)` | `sys_mutex.cpp:150` | adaptive: 3 or 10 iterations depending on `has_ppus_in_running_state()`, with a `try_lock` and an early break between each. Reasonable as written |
| 10.4 | `rx::busy_wait(200)` | `sys_ppu_thread.cpp:152` | unbounded drain loop waiting for vm writers; no sleep fallback, but it runs on thread exit |
| 5.2 | `rx::busy_wait(100)` | `util/Thread.cpp:2635`, `RSXThread.cpp:2840` | **the emulator's finest timing quantum** — see below |

## The note in `asm.hpp` is true of some sites and cannot be true of others

`rx::busy_wait` carries a long comment explaining that upstream's timer scaling is
deliberately **not** applied here because "every hot call site was retuned by hand
against Thor's real 19.2 MHz timer (see the 100/200/300/500 arguments…)". That is
accurate, and it is the reason the scaling must stay off — re-dividing would
recreate the 1-FPS lock convoy it describes.

But six sites **pass no argument at all** and therefore take the x86 default of
3000. They cannot have been part of that retune, because a retune leaves a number
behind. The comment enumerates the arguments it fixed and reads, on a quick pass,
as though it covers the whole file. It covers the sites with numbers.

## `shared_mutex` is the lv2 defect one layer down

All three slow paths in `SharedMutex.cpp` have the identical shape:

```cpp
for (int i = 0; i < 10; i++) {
    busy_wait();          // 156 us each -> 1.56 ms total
    ...try to acquire...
}
// falls through to m_value.wait(old) -- a real futex
```

Same structure as the lv2 loops, in front of a sleep that already works, and
**worse per site**: 1.56 ms against the lv2 layer's 1.3 ms.

It is now behind `debug.rpcsx.thor.host_mutex_spin`, **default 10 — unchanged**.
Nothing about its behaviour has shipped. The gate exists so the measurement costs
one property instead of a five-minute build, because the device is in use.

**Do not assume this repeats the lv2 win.** The evidence is weaker in both
directions:

* `shared_mutex::imp_lock` was **1.17%** of the Folklore profile, not 47%.
* That was a light scene, and the one hard lesson from the lv2 work is that a
  wait's share of CPU moves by an order of magnitude between scenes — 67.6% on a
  title screen, 6.1% on gameplay. It could move either way here.
* `shared_mutex` is a **host** lock protecting real critical sections, not a guest
  primitive waiting on an event that may be milliseconds away. A spin in front of
  a short critical section is often the correct design, and 1.56 ms is only
  obviously wrong if the sections are short — which is exactly the thing that has
  not been checked.

## The experiment, ready to run

One boot, gameplay, alternating arms, frame-time percentiles from
`dumpsys SurfaceFlinger --latency` on the `(BLAST)` layer:

```
debug.rpcsx.thor.host_mutex_spin = 10   (default)
debug.rpcsx.thor.host_mutex_spin = 0
```

Report p50/p95/p99 and `utime+stime` from `/proc/<pid>/stat`, exactly as in
`lv2-ppu-spin.md`. **Falsified if p95 rises** — a host mutex is far more likely
than a guest event queue to be protecting something short, where removing the spin
trades a cheap spin for an expensive futex round trip on every contention.


## The finest timing quantum in the emulator is 5.2 µs here, 33 ns on x86

`Thread.cpp:2635` and `RSXThread.cpp:2840` are the same code twice — the tail of a
precise-sleep loop:

```cpp
// TODO: Determine best value for yield delay
else if (usec >= host_min_quantum / 2) { std::this_thread::yield(); }
else                                   { rx::busy_wait(100); }
```

This is the branch taken for the shortest waits, the one that exists precisely
because `yield()` is too coarse. `busy_wait(100)` is 100 TSC ticks — **33 ns** on a
3 GHz x86 — and 100 generic-timer ticks, **5.2 µs**, here. The mechanism intended
to provide sub-quantum precision has a quantum 157× coarser than designed, and
both copies carry a `TODO` saying the value was never determined.

**Recorded, not acted on.** A 5.2 µs overshoot against a 16.67 ms frame is 0.03%,
so the expected effect on frame pacing is negligible and a change here would fail
the "predicted magnitude" test in the ledger before it was written. It matters only
if something wants genuine microsecond timing — `sys_timer_usleep` is the candidate,
and it showed up at 3.7% in the profile already sleeping correctly on a futex. Worth
knowing, not worth changing on this evidence.

## What this sweep cost, and the one that got away

Computing the table took a grep and a division, because
`get_tsc() == cntvct_el0 @ 19.2 MHz` was already established. **Nine of the twenty
sites are decided by arithmetic alone** — dead on Android, config-gated, or too
rare to matter — leaving three worth an experiment.

And it caught a miss in work already shipped. The lv2 fix was driven by a grep for
`i < 50`, which matched eight sites. `sys_mutex.cpp` writes the identical loop as
`i < 40` and was silently left spinning — in `sys_mutex_lock`, the most fundamental
guest mutex there is. It is gated now, and
`tools/test_thor_lv2_spin_sites.py` matches the **shape with any literal** rather
than the number, so the same near-miss cannot recur. Grepping for a constant when
the invariant is a structure is the same mistake as grepping a channel that emits
nothing: both return a confident, wrong, empty answer.

---

# Correction: the file I gated was not the one that runs

`rx/src/SharedMutex.cpp` is **not linked into the emulator.** `rx` is added with
`EXCLUDE_FROM_ALL` (`rpcsx/CMakeLists.txt:255`), and the `shared_mutex` the
profile saw is a **second implementation** at `rpcs3/util/mutex.cpp`. The gate
went into the dead copy, was reverted, and now sits on the live one.

The substance of the finding survives — `util/mutex.cpp` has the same three
acquire loops, ten iterations each, in front of the same `m_value.wait()` futex —
but it is reached through the wait profiler rather than a bare call:

```cpp
thor_wait::profiled_busy_wait(thor_wait::site::mutex_shared);   // cycles = 3000
```

`profiled_busy_wait(site, usz cycles = 3000)` defaults to 3000, so each is still
**156 µs**, ten of them still **1.56 ms**. A fourth loop, `imp_lock_unlock`, runs
30 iterations at 1500 cycles — **2.34 ms** — and is left alone: it polls for the
waiter count to drop rather than trying to acquire.

**How the inventory missed it.** The sweep regex was `busy_wait\((\d*)\)` — it
required the argument to be digits or empty. Every `profiled_busy_wait(site)` call
has a non-numeric first argument, so **the entire profiled call-site family was
silently excluded**, which is most of the spin sites in the emulator. That is the
third time in this one piece of work that a pattern written around a literal
missed the sites that spell it differently: `i < 50` missed `i < 40`, `-DANDROID`
missed the `rx` target, and now a numeric-argument regex missed every profiled
site. **When the invariant is a structure, do not match on its arguments.**

## The experiment ran, and the answer is "not resolvable"

| run | `host_mutex_spin` | p50 | p95 | p99 | CPU |
| --- | --- | --- | --- | --- | --- |
| A (invalid — see below) | 10 | 33.72 | 50.59 | 50.60 | 3.737 |
| A (invalid) | 0 | 33.72 | 50.59 | 50.60 | 2.366 |
| B | 10 | 33.73 | 33.74 | 50.60 | 3.096 |
| B | 0 | 33.73 | 33.74 | 50.59 | **3.953** |

**Run A is void and is the most useful measurement of the day.** Its `adb install`
failed with `device offline` — caught by grepping the on-device `.so` for the
property string, which returned 0 — so **both arms ran identical code with the
property doing nothing.** They differed by **1.37 cores, 58%.**

That is the noise floor for a CPU measurement on Eternal Sonata across boots, and
it is enormous. Run B, on the correctly installed build, then put `spin=0` *worse*
by 0.86 cores — the opposite direction from run A. Two runs, opposite signs, both
inside a 1.4-core spread.

**Conclusion: `host_mutex_spin` has no effect this method can resolve on this
title.** Default stays at 10. Not "no effect" — *not resolvable*, which is a
different and honest claim.

## What this costs the earlier gameplay result

The lv2 numbers on Eternal Sonata — 3.230/3.155 against 3.010/3.087, and
2.391/2.375 against 2.291/2.203, reported as "4.5%" and "6.1%" — are deltas of
about **0.14 cores against a between-boot spread of 1.37**. They are an order of
magnitude below the noise floor and are hereby **downgraded from measured to not
established.** Four of four within-run pairings favoured the change, which is a
sign test at p=0.06: suggestive, not significant.

**The decision to default `lv2_spin` to 0 still stands, on the other two legs:**

* **Folklore is reproducible where Eternal Sonata is not** — three baseline arms
  at 1.196, 1.200, 1.201 and two zero arms at 0.387, 0.390. A 0.81-core effect
  against a 0.005 spread. That result is untouched by any of this.
* **Frame-time percentiles were stable in every arm of every run**, including the
  void one, and never moved with the property. The no-latency-cost finding is the
  strongest thing here, because percentiles proved insensitive to exactly the
  boot-to-boot variation that wrecks the CPU numbers.

## The method rule this buys

**A CPU-time A/B on Eternal Sonata needs a paired design and repeats, or it needs
a different title.** One pair of arms cannot see anything below ~1.4 cores there.
Folklore's title screen resolves 0.005. Frame-time percentiles from SurfaceFlinger
resolve 0.01 ms on both.

And: **grep the shipped `.so` for the property string before every property A/B.**
It cost one command and caught an install that reported failure in a line that
scrolled past, which would otherwise have been written up as a 37% win.

---

# Re-run on Folklore: real, reproducible, and 100× too small to act on

The Eternal Sonata attempt failed on the title, not the hypothesis. Folklore
resolves 0.005 cores where Eternal Sonata cannot see 1.4, so the experiment was
repeated there. Property presence in the shipped `.so` checked first (returned 1).

| `host_mutex_spin` | arms | CPU | p50 / p95 / p99 |
| --- | --- | --- | --- |
| 10 (default) | 3 | 0.377, 0.377, 0.378 | 16.87 / 16.87 / 16.87 ms |
| 0 | 2 | 0.370, 0.368 | 16.87 / 16.87 / 16.87 ms |

**0.0083 cores, 2.2%, against a within-arm spread of 0.001–0.002.** So the effect
is four to eight times the noise — real — and frame time does not move at any
percentile.

One arm read **1.008 cores with p95 33.74 ms** and is excluded: its frame time
doubled, so it was in a different state. It was not dismissed on that basis alone
— a three-fold CPU reading deserved a check rather than a rule — so two further
`spin=10` arms were run, which came back at 0.377 and 0.378. The outlier was a
scene artifact, not a `spin=10` pathology.

## Default stays at 10

A 2.2% saving with no latency cost is real and it is **roughly one percent of the
lv2 win** — 0.008 cores against 0.81. Set against that:

* On Eternal Sonata the direction was **opposite** (`spin=0` worse by 0.86 cores)
  and unresolvable. There is no gameplay evidence of benefit, and weak evidence of
  harm.
* A host mutex guards short critical sections, which is the case where spinning
  is most likely to be correct. The lv2 waits were waiting on guest events
  milliseconds away; these are not the same thing.

Flipping a latency-guarding default for 0.008 cores on one light scene, against a
contrary gameplay reading, is not a trade worth making. The property stays for
anyone who wants it.

## The asymmetry is the actual finding

Same shape, same 156 µs unit, same futex underneath — and 0.81 cores at the lv2
layer against 0.008 here, a factor of a hundred. **Spinning is not the defect; the
lv2 waits were.** They spin in front of events that arrive milliseconds later, so
the spin almost never wins its race and the whole 1.3 ms is burned. `shared_mutex`
spins in front of critical sections short enough that it usually wins, which is
what a spin is for.

That distinction is worth more than either number, because it says where to look
next: **not at spin loops, but at waits whose expected wait is long.** Grepping for
`busy_wait` finds the mechanism; only knowing what is being waited *for* predicts
whether the spin pays.
