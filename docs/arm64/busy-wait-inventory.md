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
