# The spin investigation: where the CPU time goes and why

Measured: **16.9% of busy CPU time is spin, and 93% of that is the SPU
`GETLLAR` wait.** This is how that was established, what was tried against it,
and the one lever still untested.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## What the hot retry loops actually cost

Read in depth, because "SPU is at 38% during a cutscene" is a power question and
the answer is in these loops rather than in any opcode.

The SPU `GETLLAR` wait is the hottest. One retry iteration is:

    ntime = vm::reservation_acquire(addr)   // LDAR
    mov_rdata(rdata, data)                  // 128-byte copy
    atomic_fence_acquire()                  // DMB ISHLD
    time0 = vm::reservation_acquire(addr)   // LDAR, validate
    cmp_rdata(rdata, data)                  // 128-byte compare
    busy_wait(300)                          // spin

**The spin dominates everything else by two orders of magnitude.**
`busy_wait(300)` counts 300 ticks of `CNTVCT_EL0`, which runs at **19.2 MHz** on
this device, so it is **~15.6 microseconds**, not the fraction of a microsecond
the same constant would mean against an x86 TSC. At ~2 GHz that is roughly
31,000 cycles of a core held at full clock, running `mrs cntvct_el0` in a tight
loop. The retry limit is 24, so a single contention event can burn on the order
of **374 microseconds of core time** before the thread yields to the OS.

And the spin body cannot save power, because `pause()` emits **`yield`** on
AArch64, which is an SMT hint. On a non-SMT core it retires and does nothing:
no clock drop, no park, no power reduction. x86's `PAUSE` at least idles the
pipeline; `YIELD` here is closer to a `NOP`.

So the SPU utilisation seen during quiet scenes is not work. It is threads
spinning on `CNTVCT_EL0` waiting for a reservation, at full clock, in a loop
whose only "backoff" instruction does nothing on this hardware.

Checked and cleared while reading these loops, so the work is not repeated:

- `thor_es_getllar_retry_spin_limit()` and `thor_es_getllar_retry_cycles()` call
  `Emu.GetTitleID()`, a `std::string` comparison, on **every iteration**. That
  would be serious in a hot loop, but those versions are inside
  `RPCSX_THOR_ES_SPU_EXPERIMENTS`, which is off by default; the shipped build
  compiles `constexpr` versions instead.
- `get_tsc()` is a bare `mrs cntvct_el0` with no `ISB`, which is the cheap form.
  Adding a barrier to "fix" its ordering would make the spin considerably worse.
- The `atomic_fence_acquire()` added for the seqlock emits `dmb ishld`, a
  load-load barrier, not a full `dmb ish`. It was a fair suspect for added spin
  cost and is not one.

This is the case for the `WFE` work in the next section, and it also explains why
that work is hard to evaluate: the fix is not "spin more cheaply" but "stop
spinning", and its benefit is power at constant frame rate, which no frame
counter will show.

## The power-optimized wait, which ARM has and this fork does not use

The most valuable unexploited hardware feature found in this sweep, and the one
that fits this device's actual constraint, which is heat rather than throughput.

The SPU `GETLLAR` spin has an x86-only fast path. When a thread is waiting for a
reservation line to change, x86 does not spin:

- **`MONITORX` + `MWAITX`** arms a cache line and parks the core in a low-power
  C-state until *that line is written* or a timer expires. The comment in
  `SPUThread.cpp` is right that it "fits reservations almost perfectly".
- **`TPAUSE`** (waitpkg) does the timed half without the address monitor.

Both sit inside `#if defined(ARCH_X64)`. ARM has no counterpart there, so it
falls back to `busy_wait()`, which spins on `yield`. A spinning core on a
passively cooled handheld is heat, and heat is the budget this whole fork is
managed against.

**AArch64 has the same capability**, and has since Armv8.0:

    ldxr  wzr, [cline]      // arm the exclusive monitor on the reservation line
    // re-check the condition here
    wfe                     // park until the monitor is cleared or an event arrives

`WFE` parks the core; a write to the monitored line clears the exclusive monitor
and generates the wake. That is `MONITORX`/`MWAITX` with the operands in a
different order.

**Measured on device, and the numbers change the design.** `ID_AA64ISAR2_EL1`
reads `0`, so **FEAT_WFxT is absent**: there is no `WFET`, and therefore no way
to bound a `WFE` with a timeout. `MWAITX` *does* take a timer, `min(spin, 17) *
500` cycles, so on x86 a missed wake costs microseconds. On AArch64 the only
fallback wake is the generic timer event stream, and that was timed directly:

| sequence | latency |
| --- | --- |
| `sevl; wfe` (event already pending) | 0.007 us |
| `sevl; wfe; wfe` (second one really waits) | **95.06 us** |
| `ldxr; sevl; wfe; wfe; clrex` | **97.33 us** |

So `WFE` genuinely parks — the first naive probe suggested 10ns and was wrong,
because its loop never actually consumed the pending event. Confirming that took
`SEVL` to set the event register deliberately, then timing the *second* `WFE`.
**When a probe reports a number that would be physically surprising, the probe is
usually what is broken.**

The consequence is a real asymmetry. The exclusive monitor granule is one cache
line, 64 bytes, while a reservation is 128. A writer touching only the second
line may not clear a monitor armed on the first, and the waiter then eats the
full ~95us instead of the microseconds `MWAITX` would cost. That is why the
implementation only parks once `getllar_spin_count >= 8`: spinning through the
early iterations keeps a 95us worst case off short waits, where it would
dominate, and confines it to waits already long enough not to care.

Also confirmed while probing: `CNTFRQ_EL0` is `19200000`, cross-checking the
19.2MHz generic timer that `asm.hpp` documents and that the busy-wait tuning
depends on.

The safe shape matters and is worth writing down, because the unsafe shape
deadlocks. Arm the monitor, **re-check the condition after arming**, then `WFE`,
all inside the existing retry loop. A spurious wake then costs one extra
iteration instead of a hang, and a missed event cannot wedge the thread because
Linux/arm64 enables the generic timer **event stream**, which delivers a
periodic event (order 100us) that wakes `WFE` regardless. Without that event
stream a plain `WFE` with no timeout is a hang waiting to happen.

**Run on device, and the result is: safe, thermally neutral, performance
unmeasured.** The experiment is worth recording mainly for how it failed.

What it established:

- **No hang.** This was the real risk. A lost wakeup would park an SPU thread
  until an unrelated event, and the failure would look like a freeze rather than
  a slowdown. The WFE build booted Eternal Sonata, reached gameplay, rendered
  correctly and stayed alive. The arm/re-check/park ordering holds in practice.
- **Thermally neutral.** Peak over a matched 120 s window: 64.6 C silicon /
  74.7 C junction without WFE, 65.4 / 75.9 with. That is inside run-to-run noise.

What it failed to establish, and why: **the scene would not hold still.** Both
arms boot into the opening cutscene, which advances on its own schedule, so the
two runs were sampling different content. The control landed in a forest scene
frame-capped at 29.99 fps; the WFE arm was in a character close-up at 23.19. CPU
figures diverged accordingly, and the two measurement methods disagreed about
the direction: the in-game overlay showed WFE using *more* CPU (58.3% vs 47.0%
total) while process CPU time showed it using far less (1.47 vs 4.09 cores
busy). **When two instruments disagree on the sign, the experiment is measuring
the scene, not the change.**

So the flag stays off. Not because it failed, but because nothing was learned
about the thing it exists to improve.

Savestates were tried as the fixed-scene fix and do not currently work from the
debug-boot path: booting a `.SAVESTAT.zst` directly fails with "Disc directory
not found. Savestate cannot be loaded", because that path bypasses the game-list
registration a savestate needs to resolve its disc. Making that work is emulator
plumbing rather than an ARM64 question, and it is the single thing standing
between this fork and a repeatable A/B.

For whoever runs it properly: the boot-into-cutscene route cannot work, because
frame-capped and uncapped scenes are not comparable and the content is not
reproducible. Use a save state loaded at a fixed point, or a static menu, and
compare process CPU time over a long window at matched frame rates. Measure
sustained temperature and clock residency rather than FPS; a change that lowers
power at constant frame rate is the win here and is invisible on a frame counter.

**Implemented behind `RPCSX_THOR_ARM64_WFE_WAIT`, default off.**
`-PrpcsxThorArm64WfeWait=1` turns it on. Both configurations build.

Default-off is not hedging, it is the measurement rule. The entire justification
is power and thermal behaviour; the effect on frame time could easily be zero or
slightly negative, because parking a core adds wake latency to the reservation
handoff. A change whose only argument is "this should run cooler" cannot be
switched on by a fork that does not measure, because there is nothing to check
the claim against. It also sits in the hottest SPU path, where the spin counts
were arrived at empirically. So the code is written, reviewed and compiled,
and the decision to enable it is left to whoever can put a thermometer on it.

The emitted sequence was verified rather than assumed:

    ldxr  w8, [x0]           arm the monitor
    bl needs_wait / tbz      re-check AFTER arming
    wfe                      park
    clrex                    release the reservation

Both halves of that order matter. Re-checking *before* arming lets the writer
land in the gap, and the wake it generated is already gone — a lost wakeup, with
the thread sleeping until something unrelated pokes it. `CLREX` must come after
the park, not before, or the reservation is dropped while it is still needed;
leaving a stray monitor armed can also make an unrelated `STXR` fail spuriously.

When measurement becomes possible, the thing to measure is **sustained
temperature and clock residency, not FPS**. A change that lowers power at
constant frame rate is a win on this device and would look like a no-op on a
benchmark chart.

Pinned by `tools/test_thor_arm64_wfe_wait.ps1`, which checks the arm/check/park/
clear order, that both build systems default it off, that the plain busy-wait
fallback still exists, and that the x86 path was not touched.

## The WFE A/B, attempt two: better instrument, same verdict

With a probe whose idle noise floor is 0.002 W, the `WFE` question looked
settleable at last. It is not, and the reason is worth recording precisely,
because it is not the reason that was expected.

Both arms booted Eternal Sonata through `THOR_DEBUG_BOOT`, identical settle time
of 100 s, identical 90 s measurement window:

| | cores busy | power (floor, USB attached) |
| --- | --- | --- |
| `WFE` off (shipped default) | `4.974` | `6.901 W` |
| `WFE` on | `5.024` | `4.905 W` |

Read alone that is a 29% power reduction for identical CPU work, which would be a
remarkable result. It is also internally contradictory: **`cores_busy` is
unchanged, so the CPU is doing the same work at the same clocks, and there is no
mechanism by which that draws two watts less.** When the two metrics disagree,
neither is evidence.

The control settles it. Three consecutive 60 s windows, **same build, same game
session, nothing changed between them**:

| window | power | cores busy |
| --- | --- | --- |
| 1 | `1.429 W` | `2.279` |
| 2 | `5.712 W` | `4.304` |
| 3 | not derivable | `2.286` |

Within-arm spread is **4.3 W and 2.0 cores**. The entire between-arm difference
fits inside it several times over. The A/B measured nothing.

**So the blocker was never the instrument.** The earlier attempt failed because
its two arms sampled different cutscene content and its two readouts disagreed on
the sign. That diagnosis was right, and this attempt shows the problem is worse
than "the arms differed": the workload varies by a factor of two *within a single
arm*, minute to minute, because the title advances through its opening on its own
schedule. No amount of instrument precision fixes a workload that will not hold
still. A 0.002 W noise floor against a 4.3 W workload swing is a very sharp ruler
held against a moving object.

`RPCSX_THOR_ARM64_WFE_WAIT` therefore stays default off, for the third time and
now for a well-understood reason. What it needs is not a better probe but a
**reproducible workload**, and that is the savestate boot path this document
already identifies as broken: booting a `.SAVESTAT.zst` directly fails with
"Disc directory not found", because that path bypasses the game-list registration
a savestate needs to resolve its disc. That is emulator plumbing, not an ARM64
question, and it is now the single highest-value thing standing between this fork
and any power measurement at all.

A static in-game menu would also serve, if one can be reached deterministically.

**The generalizable part.** Improving an instrument is satisfying and was the
obvious move, and it was not the constraint. Before sharpening a measurement,
check whether the thing being measured is stable enough for the precision you
already had. The within-arm control that established this took three minutes and
would have been worth running before either WFE experiment.

## A second power-optimized wait, in a subsystem the sweep never scanned

The ledger records that `lv2`, the HLE modules, `Audio` and `Io` are
architecture-neutral, on the strength of a grep for `ARCH_X64`, `_mm_`, `__m128`
and `__asm__` that "matches **zero files**".

**Two of those four paths do not exist in this fork.** There is no
`Emu/Cell/lv2` and no `Emu/Cell/Modules`; the syscall layer lives in
`kernel/cellos/`, 117 source files. `Audio` (23 files) and `Io` (73 files) are
real and are genuinely clean, so half the claim held. The other half was a grep
against nothing, reporting the answer it was hoping for.

This is the same failure as the APK gate that defaulted to
`app/build/outputs/apk/release/`, a variant nobody builds, and passed for months
without inspecting an artifact. **A search that finds nothing and a search that
searches nothing are indistinguishable in the output.** When a sweep reports zero
hits, confirm the path exists before recording the result.

Scanning `kernel/cellos/` properly returns one file, and what is in it matters.

### `lv2_obj::wait_timeout` gives x86 a low-power sleep and ARM a spin

`kernel/cellos/src/lv2.cpp` carries a second copy of the power-optimized wait
that this document already describes for the SPU reservation path — in a
different subsystem, on a different code path, and not previously noted.

`lv2_obj::wait_timeout` is the guest thread sleep, reached by `sys_timer_usleep`
and by every mutex, condvar and semaphore timeout. For waits **longer** than the
host scheduler quantum it blocks properly on `thread_ctrl::wait_on`. For waits
**shorter** than it, roughly 10 us on Linux, the tail is:

```cpp
#if defined(ARCH_X64)
      else if (utils::has_appropriate_um_wait()) {
        if (utils::has_waitpkg()) __tpause(us_in_tsc_clocks, 0x1);
        else                      __mwaitx(us_in_tsc_clocks, 0xf0);
      }
#endif
      else {
        std::this_thread::yield();
      }
```

x86 parks the core in a C-state for exactly the remaining time. **AArch64 falls
into `std::this_thread::yield()`**, which is a `sched_yield` syscall, in a loop,
until the deadline passes — kernel entry and exit per iteration, at full clock,
producing heat rather than a wait.

**And unlike the SPU case, there is no good ARM answer available on this part.**
The natural equivalent is `WFET`, wait-for-event with a timeout, which is
FEAT_WFxT — and `ID_AA64ISAR2_EL1` reads `0` on this device, so it is absent.
Plain `WFE` cannot substitute: with no `WFET` the only fallback wake is the
generic timer event stream, measured here at roughly **95 us**, which would
overshoot a sub-10 us wait by an order of magnitude.

So this is a real gap with no clean fix, which is worth stating rather than
leaving as an implied TODO. The one cheap thing that has not been tried is
replacing the `sched_yield` loop with a short `busy_wait`, trading syscall
overhead for a spin — the SPU path already made that trade. Whether it wins
depends on how often this fires and on whether yielding to other emulator threads
is worth more than the syscall costs, which is a measurement rather than an
argument.

**Now instrumented**, so it is answerable in the same run as the SPU spin
question. `thor_wait::site::lv2_short_timeout_yield` records every time AArch64
takes this fallback, and its cycle column accumulates the **microseconds still to
wait** rather than timer ticks, so it reads directly as "how much guest sleep is
being spent spinning in the scheduler". The site appears in the core summary line
as `lv2_yield=calls/us`.

The unit differs from every other site in that table, which is deliberate and
noted at the enum: the others wrap `busy_wait` and record the tick count they
were asked for, while this one is not a busy-wait at all. Recording ticks here
would have meant inventing a number.

Adding it required a stub `record()` in the profiler-disabled branch of the
header, which previously stubbed only `profiled_busy_wait` — every existing
caller went through that wrapper, and this is the first site that does not.

## The wait profiler run: 17% of CPU time is spin, and 82% of that is GETLLAR

Run on device with `-PrpcsxThorWaitProfiler=1` and
`debug.rpcsx.thor.wait_profiler=v`, booting Eternal Sonata through
`THOR_DEBUG_BOOT`, 110 s settle then a 90 s window. Rates computed from two
timestamped reports 8.803 s apart rather than from cumulative totals, so the
figures are a rate during steady gameplay and not an average that includes boot.

Concurrent power probe over the same run: **4.818 cores busy, 8.536 W** (floor,
USB attached).

| site | spin time | share of spin |
| --- | --- | --- |
| `spu_getllar_retry` | `3.147 s` | **43.9%** |
| `spu_getllar` | `2.767 s` | **38.6%** |
| `vm_passive_lock` | `1.251 s` | 17.5% |
| **`vm_writer_lock`** | **`0.000 s`** | **0.0%** |
| everything else | ~0 | ~0 |

**Headline: 7.165 core-seconds of spin in 42.41 core-seconds of busy CPU time —
16.9%.** Roughly **0.81 of the 4.82 busy cores are spinning**, producing heat and
no work. That is the first measured number this fork has had for the question the
whole `WFE` argument rests on, and it was previously assumed rather than known.

### What this settles

**The `WFE` work targets the right loop.** `spu_getllar` plus
`spu_getllar_retry` is **82.5% of all spin**. Everything else in the SPU set —
`spu_dma_reservation`, `spu_accurate_store`, both `putunc` sites, the channel
operations, `spu_eventstat` — recorded **zero calls**. The reservation wait is
not merely the largest contributor, it is very nearly the only one.

**Ledger item 3 is dead as a priority.** `vm_writer_lock` recorded **zero spin
calls** across 5.9 million total waits. The contention located earlier in this
work — `bits.bit_test_set(diff)` on the shared `g_range_lock_bits[1]`, on every
PUTLLC — **never causes a thread to wait**. `writer_lock` always acquires on its
first attempt in this workload.

That must be read precisely. The profiler instruments `busy_wait` sites, so a
zero means there is no *lock contention*: it does not measure the coherence cost
of the atomic RMW itself, which still executes on every acquisition. But an
uncontended atomic on a shared line is a cache-line transfer, not a wait, and the
redesign's entire case was that eight cores were serialising on it. They are not.
The remaining upside is bounded by the cost of one uncontended instruction, which
is far too small to justify redesigning the hottest lock in the memory subsystem.
~~Closed, on evidence, rather than left open as "the highest-value ARM work
left".~~

> **Retracted later the same session — that closure was drawn from the wrong
> site.** `vm_writer_lock` reading zero shows only that the *writer* never
> blocks. The **readers** do: `passive_lock` spins while `g_range_lock_bits[1]`
> is non-zero, the shared `writer_lock` path holds a bit in that word for its
> whole lifetime, and `vm_passive_lock` measured **17.5% of all emulator spin**.
> The paragraph above is left standing rather than deleted because the reasoning
> in it is a good example of the failure: every sentence is true, and the
> conclusion does not follow. See the correction in
> [`memory-model.md`](memory-model.md) and the re-scoped entry in
> [`ledger.md`](ledger.md).
>
> The site's cost was subsequently removed a different way — by fixing
> `passive_lock`'s backoff, not by redesigning the lock — so the practical
> conclusion happened to survive its own broken justification.

**The `lv2` sub-quantum sleep is cold for this title.** `lv2_yield` recorded zero
calls. The x86-only `TPAUSE`/`MWAITX` path found in `kernel/cellos/src/lv2.cpp`
is a real gap, and it does not fire in Eternal Sonata. Worth knowing before
anyone spends effort on it; worth keeping the instrumentation for a title that
does hit it.

**`vm_passive_lock` is the surprise second place** at 17.5%, well ahead of every
mutex site combined. It had not been considered at all. Whether that is
addressable is a separate question, but it is now the obvious place to look after
`GETLLAR`.

### What it does not settle

This is one title, in one scene, over nine seconds. `vm_writer_lock` could
contend in a game with heavier cross-SPU atomic traffic, and the ledger entry
should be re-checked rather than deleted if such a title ever runs here. The
measurement is also of *requested* wait duration summed per site, which is what
`busy_wait` spins for, not independently observed wall time.

But the shape is unambiguous, and it inverts the priority order this document
carried all day: the reservation **spin** is worth attacking and the reservation
**lock** is not.

## The WFE A/B, third attempt: the mechanism is proven, the power win is not

Both arms built with the profiler, `debug.rpcsx.thor.wait_profiler=v`, Eternal
Sonata booted through `THOR_DEBUG_BOOT`, rates taken between timestamped profiler
reports. Both defines verified at the compiler before spending device time —
`RPCSX_THOR_ARM64_WFE_WAIT` and `RPCSX_THOR_WAIT_PROFILER` present in
`SPUThread.cpp`'s compile flags, not merely `ON` in a CMake cache.

| arm | ticks per retry | cores busy | watts (floor) |
| --- | --- | --- | --- |
| WFE off, control A | `263.7` | `4.818` | `8.536` |
| WFE off, control B | `260.7` | `3.916` | `6.942` |
| **WFE on** | **`209.8`** | `5.453` | `10.514` |

**On the normalized metric the change is -20.0%, against a control-to-control
spread of 1.1%.** The effect is roughly eighteen times the noise floor, which is
the first time any WFE experiment here has produced a signal that clears its own
error bars.

### What that does and does not prove

**Proven: the code path is live and is displacing a fifth of the inner spin.**
Before this run, the WFE build had been shown to boot without hanging and nothing
more; whether the park ever actually fired was unverified. It fires, and it
removes 20% of the recorded inner `GETLLAR` spin per unit of reservation
contention. That the figure is 20% rather than most of it fits the design, which
only parks once `getllar_spin_count >= 8` — most waits evidently resolve before
that.

**Not proven: that this saves power.** `cores_busy` and watts both went *up* in
the WFE arm. They cannot be read as a regression, because both are absolute
measures and the control windows themselves differ by 59% and 23% on those same
quantities. They also cannot be read as a win. They simply do not resolve.

**And normalizing them the same way does not work.** Dividing cores by retry rate
gives `2.106e-4` and `1.020e-4` on the two control windows, a **69% spread**. The
retry count is a proxy for *reservation contention*, which is exactly why it
normalizes the spin metric — inner spin is caused by the thing the denominator
counts. Total CPU and power include PPU, RSX and audio work, which it does not
track at all, so it is the wrong denominator for them and behaves like one.

**The sharper caveat, which the metric cannot see.** Displaced spin is not saved
time. `WFE` parks with no timeout on this part, since FEAT_WFxT is absent, so a
missed wake costs up to the ~95 us event-stream period against the 15.6 us the
spin would have taken. Fewer recorded spin ticks is consistent with a thread that
is parked longer than it would have spun. Whether that trades throughput for
power, saves both, or costs both is exactly what these numbers do not say.

So the flag stays **default off**, for the third time, but for the first time on
a different basis. It is no longer "nothing was learned": the mechanism is
confirmed to work and is quantified. What remains unmeasured is narrower and
better defined — the power and latency consequences of parking, which need either
a CPU-isolated power rail this device does not expose, or a fixed workload where
absolute `cores_busy` becomes meaningful.

## The passive_lock backoff was ten times too long, and measuring said so

`vm_passive_lock` came out of the profiler run as the second-largest spin source
in the emulator, 17.5% of all spin. The obvious explanation was the range-lock
bitmask contention described in `memory-model.md`, and the obvious fix was the
redesign — which is a change to the hottest lock in the memory subsystem.

**One cheap measurement said it was neither.** Counting loop *entries* separately
from *backoffs* gives the mean number of backoff iterations per contended wait:

    passive_lock loop entries      61,980   (42,774/s)
      of which had to back off     25,560   (41.2%)
      backoff iterations           31,636

    MEAN ITERATIONS PER CONTENDED WAIT: 1.24

**1.24, not 10 or 50.** When `passive_lock` contends it almost always clears on
the first re-check. The lock is released long before the wait expires, so the
13.9 core-seconds this site burned was **overshoot, not contention duration** —
a backoff-tuning problem wearing a lock-contention costume.

`busy_wait(200)` is 200 ticks of a 19.2 MHz timer: **10.42 us**, against a hold
that is evidently much shorter. Replaced with a ladder — 20 ticks on the first
iteration, 50 up to the fourth, 200 thereafter — and re-measured:

| | flat 200 | graduated | change |
| --- | --- | --- | --- |
| spin per contended wait | `247.5` ticks | `37.0` ticks | **-85.1%** |
| cores spinning here | `0.227` | `0.072` | **-68.3%** |
| loop entries per second | `42,774` | `54,545` | +27% |

Roughly **0.155 of a core recovered**, about 3% of the ~4.8 busy cores, while the
site processed 27% *more* traffic.

**Why a ladder and not a smaller constant.** Dividing every busy-wait in the
emulator by a fixed factor is exactly what produced a lock convoy and about 1 FPS
before, recorded on `busy_wait` in `rx/asm.hpp`. The long tail still needs a long
wait. Only the first iterations shorten, so a wait that genuinely lasts reaches
the same 10.42 us backoff by its fifth pass and the budget before yielding is
barely changed. The contract test defends the final tier specifically, because
collapsing the ladder to its smallest value is the plausible-looking edit that
brings the convoy back with no visible symptom.

**Caveats.** Entries per second differed 27% between the arms, so the scenes were
not identical and the absolute core figure carries that uncertainty. The
robust number is spin per contended wait, which is normalised by the number of
waits and moved 85%; that one is close to what the change mechanically predicts,
which is the point. The contention rate also rose, 41.2% to 68.6%, which is
expected: a shorter first wait re-checks sooner, so more entries are recorded as
having backed off at least once. It is a property of where the counter sits, not
a regression.

**The transferable part.** The site looked like a lock-contention problem and the
fix looked like a redesign. What separated them was one counter — entries beside
backoffs — costing a single build. **Before attacking contention, measure how
long the waiters actually wait.** A backoff tuned for a different timer frequency
is far more likely than a genuine protocol problem, and vastly cheaper to fix.

## The same fix did not transfer to GETLLAR, and the measurement said so

`passive_lock` turned out to be a backoff-tuning problem rather than contention,
and the obvious next move was to try the same thing on the far bigger target:
`GETLLAR`, at 82.5% of all emulator spin.

The evidence looked strong. Instrumenting GETLLAR wait **episodes** — one per
`0 -> 1` transition of `getllar_spin_count` — against the busy-waits actually
executed gave **0.834 spins per episode**, apparently an even shorter wait than
`passive_lock`'s 1.24. It also seemed to explain the WFE result: if the mean
episode is under one spin, the park at `getllar_spin_count >= 8` would almost
never engage, which fits parking having displaced only 20%.

A graduated ladder went in, keyed on `getllar_spin_count`, and measured as an
**exact no-op**: 300.0 ticks per call, unchanged to the decimal.

**The reasoning was wrong, and the tick count caught it.** This busy-wait is only
reached once `getllar_busy_waiting_switch` is 1, and that switch is decided at
`getllar_spin_count == 4`. Every call therefore sees a count of at least 4, a
ladder keyed on that count can never select its short tiers, and the change could
not have done anything.

**The 0.834 figure conflates two populations.** Episodes count every wait that
*starts*; only the minority surviving four iterations ever reach the spin. Spins
per episode is not spins per *spinning* wait, and says nothing about whether 300
ticks overshoots. The waits that reach this line have already demonstrated they
are not short.

Reverted, with the reasoning recorded at the site so the next person does not
repeat it. Anything tried here has to be keyed on a counter that starts when the
spin path starts.

**Two things worth carrying.**

A no-op is a *result*, and a cheap one. The change cost one build and one run, and
"300.0 ticks per call, unchanged" is unambiguous in a way that a small
improvement would not have been — had the ladder produced a 5% shift, it would
have been tempting to keep it and never notice the denominator was wrong.
**Instrument the thing you changed, not only the thing you hoped to improve.**

And the more general one: **a fix that transfers from one site to another is a
hypothesis, not a conclusion.** `passive_lock` and `GETLLAR` looked like the same
shape at the level of "a busy-wait whose measured wait seems shorter than its
backoff". They are not the same shape, because one spins immediately and the
other spins only after a separate gate has already decided the wait is durable.
The gate was visible in the source the whole time.

### Asking the GETLLAR question properly: mean spin depth 135, and heavy-tailed

The episode counter could not answer whether GETLLAR's 300-tick backoff
overshoots, because it was keyed to the *wait* and the spin path only begins once
`getllar_busy_waiting_switch` is set at `getllar_spin_count == 4`. The fix is a
counter keyed to the spin path: record the **value** of `getllar_spin_count` at
every busy-wait, so `cycles/calls` is the mean depth a spinning wait reaches.

Measured: **9,934 spins, sum of depths 1,342,867, mean 135.2.**

That is the opposite of `passive_lock`, and it settles the tuning question in the
opposite direction:

| site | mean depth at wait | reading |
| --- | --- | --- |
| `vm::passive_lock` | `1.24` iterations | backoff overshoots a released lock — **shortened, -68% spin** |
| `spu_getllar` | `135.2` | the wait genuinely persists — **shortening would only poll a shared line harder** |

**But the mean is heavy-tailed, and saying so matters more than the number.** A
single wait reaching depth `D` contributes `D` spins and a sum of about `D^2/2`.
The observed sum is close to what **one** wait of depth ~1600 produces on its
own. So a few very deep waits dominate both columns and the **median** spin depth
is probably far below 135.

What that does and does not license:

- **Established:** GETLLAR spinning includes genuinely long waits, so the backoff
  is not obviously oversized and the `passive_lock` fix does not transfer. This
  was the question asked, and it is answered.
- **Not established:** where the typical spin sits, and therefore whether WFE's
  park threshold of 8 is well placed. The mean cannot say. A **histogram** of
  spin depth is the instrument for that, and it is the natural next step if
  anyone returns to the WFE threshold.

The reason to write the caveat down rather than round the mean off: 135.2 read
naively says "every wait is long, park them all", and the arithmetic above says
that conclusion is unsupported by this statistic. **A mean over a heavy-tailed
distribution is a number that invites exactly the wrong decision**, and the check
that catches it — what would one extreme sample alone produce — costs a line of
arithmetic.

### The histogram: 95.5% of GETLLAR spins are too shallow to park, and the gate is right

The mean spin depth of 135.2 was heavy-tailed and could not locate the typical
spin. Bucketing it can, with the first boundary placed at the WFE park threshold:

| depth | spins | share |
| --- | --- | --- |
| **`< 8`** — the park never reaches these | `7,083` | **95.5%** |
| `8-31` | `277` | 3.7% |
| `32-127` | `57` | 0.8% |
| `>= 128` | `0` | 0.0% |

**The median is below 8.** The mean of 135 was a small number of very deep waits
dragging the average; the typical GETLLAR spin is shallow, and **95.5% of spins
are ones the park can never catch.**

That sounds like an argument for lowering the threshold. It is the opposite,
because the wake floor decides it:

    one GETLLAR backoff    15.62 us   (300 ticks at 19.2 MHz)
    WFE park wake floor    95.06 us   (measured; FEAT_WFxT absent, so no timeout)

| depth | cost of continuing to spin | cost of parking | parking is |
| --- | --- | --- | --- |
| 1 | `15.6 us` | `95.1 us` | **worse** |
| 2 | `31.2 us` | `95.1 us` | **worse** |
| 4 | `62.5 us` | `95.1 us` | **worse** |
| 8 | `125.0 us` | `95.1 us` | better |
| 16 | `250.0 us` | `95.1 us` | better |

**Break-even is depth 6.1. The threshold is 8.** The gate sits almost exactly
where parking begins to pay, and it was not derived from this measurement — it
was set from the reasoning about the 95 us event-stream period recorded when the
WFE path was written. The histogram confirms it independently.

### So the WFE thread closes, and not on "unmeasured"

Three runs and three instruments later, the picture is coherent:

- The park **works** — it displaces recorded inner spin at eighteen times the
  noise floor.
- It is **correctly gated** — break-even 6.1, threshold 8.
- And it is **structurally capped on this device**, because 95.5% of GETLLAR
  spins are shorter than the 95 us it costs to park at all. That ceiling is not a
  tuning failure; it is FEAT_WFxT being absent. With `WFET` the wake would be
  bounded in microseconds and the threshold could drop to 1, putting essentially
  all of that 82.5% in reach.

The honest summary is therefore not "WFE is unmeasured" but **"WFE is worth
roughly the few percent of GETLLAR spin that is deep enough to park, and no more,
on hardware without `WFET`."** That is a much smaller prize than the 82.5% figure
suggested at the start, and knowing its size is worth more than the flag.

It stays default off. Not because nothing was learned, but because what was
learned is that the ceiling is low and the remaining question — whether parking a
genuinely deep wait saves measurable power — applies to under 5% of the spin.

## The lever on 93% of spin is a config value nobody re-derived

The previous section concluded that the remaining lever on `GETLLAR` is "not
needing to wait", and called that a scheduling question outside this work's
scope. That was wrong in the same way the other blockers were: it stopped one
question short.

The emulator does not spin on `GETLLAR` because it must. It spins because it is
**configured to, 100% of the time**:

| tunable | upstream default | Thor profile |
| --- | --- | --- |
| `SPU Reservation Busy Waiting Percentage` | 0 | explicitly **0**, and "Enabled: false" |
| `SPU GETLLAR Busy Waiting Percentage` | **100** | **not overridden** |

The percentage feeds `evaluate_spin_optimization`, whose decision reduces to:

```cpp
const u32 busy_waiting_switch = ((evaluate_time >> 8) % 100 + add_count < percent) ? 1 : 0;
```

At `percent == 100` that is true for every value the left side can take, so the
adaptive policy runs its history analysis and is then told to busy-wait
regardless. The alternative branch is a **system wait** — the thread sleeps
instead of spinning.

**The asymmetry is the finding.** Someone deliberately turned reservation
busy-waiting off for this device, writing both the percentage and the enable flag
into `ThorPerformanceProfile` and `GameSettingsDatabase`. The `GETLLAR` knob sits
untouched at an upstream default, and `GETLLAR` is now **93% of all emulator
spin** and 82.5% before the `passive_lock` fix. The trade was considered once,
applied to the smaller of the two sites, and never revisited for the larger.

**Why this is the right shape of lever for this device.** Spinning buys wake
latency at the cost of burning a core; sleeping buys power at the cost of wake
latency. The measured situation is that the title **already holds its 30 fps
cap** with total CPU in the twenties to thirties of a percent, so latency
headroom exists, while the machine is passively cooled and the whole fork is
managed against heat. That is the exact case where trading some latency for power
is favourable, and it is a **config change rather than a redesign of the hottest
lock in the memory subsystem.**

**What has to be measured before changing it, and it is now measurable.** Lower
percentages mean more system waits, which have real wake cost — the reason this
is not simply set to 0 on sight is that a reservation handoff that sleeps can
lengthen the critical path between SPU threads, and frame pacing is what would
suffer. The instruments to settle it exist: `spu_getllar` call counts and cycles
from the wait profiler for the spin side, and `thor_power_probe.ps1` on an
**unplugged** device for exact system watts. Sweep the percentage across, say,
100 / 50 / 25 / 0 and read both.

This is the first candidate in this document that is simultaneously large (93% of
spin), cheap (a settings value), and untested. It is also, notably, not an ARM64
instruction-selection question at all — it is an x86-era default that nobody
re-derived for a passively cooled handheld.

### The alternative branch is a real futex sleep, which changes the WFE verdict

Before recommending a sweep of that percentage, the obvious check is whether the
"system wait" branch is actually cheaper — `lv2_obj::wait_timeout` degenerates to
a `sched_yield` loop on AArch64 for sub-quantum waits, so a config knob that
merely relocates the spin would be worthless.

It does not. When the switch is 0 the path is:

```cpp
state += cpu_flag::wait;
utils::bless<atomic_t<u32>>(&wait_var->raw().wait_flag)->wait(1, atomic_wait_timeout{100'000});
```

A futex wait with a bounded timeout. **The thread blocks in the kernel and the
core is released** — which is the entire thing spinning fails to do, and the
reason a spinning core shows up as heat.

**This partially reframes the WFE conclusion recorded above.** That analysis found
parking structurally capped, because 95.5% of `GETLLAR` spins are shallower than
the ~95 us it costs to wake from `WFE` with `FEAT_WFxT` absent. That reasoning is
correct *about WFE*, and it does not transfer here, because the two mechanisms
have different failure modes:

| | wake on the real event | fallback if the event is missed |
| --- | --- | --- |
| `WFE` on this part | fast, but the monitor granule is 64 bytes against a 128-byte reservation | the generic timer event stream, **~95 us, unbounded by anything else** |
| futex wait | fast, and it is woken by the actual reservation notifier | **its own timeout**, an explicit bound |

So the emulator already contains a bounded-timeout sleep — precisely what `WFE`
could not offer on hardware without `WFET` — and it is sitting behind a config
value set to "always spin". **The mechanism WFE was written to provide already
exists in a better form, one branch away.**

That makes the percentage sweep more interesting than a power tweak. If lowering
it recovers a meaningful share of that 93%, it does so through a path with a real
timeout and a real notifier, which is strictly the shape `WFE` was reaching for
and could not achieve here.

### The sleep is properly notified, so the lever is sound end to end

The last thing that could have made the percentage worthless: if nothing woke the
futex, every system wait would cost its full timeout and lowering the percentage
would trade a spinning core for a stalled one. Traced, and it does not:

```cpp
if (auto wait_var = vm::reservation_notifier_begin_wait(addr, rtime))   // register
{
    cache_line_waiter_index = register_cache_line_waiter(addr);
    utils::bless<atomic_t<u32>>(&wait_var->raw().wait_flag)
        ->wait(1, atomic_wait_timeout{100'000});                        // sleep
    vm::reservation_notifier_end_wait(*wait_var);                       // deregister
}
```

and the writing side calls `reservation_notifier_notify(addr)` (`vm.cpp:132`). So
a waiter registers against the specific reservation address, blocks, and is woken
by whichever thread actually changes that reservation. **The 100 us timeout is a
fallback, not the expected wake.** A second site at `:7520` follows the same
pattern with a 200 us bound.

That completes the chain, and every link of it was checkable without hardware:

| link | verified |
| --- | --- |
| the percentage decides spin versus sleep | `busy_waiting_switch` reduces to `... < percent`, always true at 100 |
| Thor leaves it at the upstream 100 | no override in `ThorPerformanceProfile` or `GameSettingsDatabase`, unlike the reservation knob which is explicitly 0 |
| the alternative is a real sleep | `cpu_flag::wait` plus a futex wait, not a `sched_yield` loop |
| the sleep is woken by the real event | `reservation_notifier_begin_wait` / `notify` / `end_wait` |
| `GETLLAR` is worth attacking | 93% of remaining spin, derived from measured shares |

**What is left is purely empirical and cannot be reasoned out:** how much power a
lower percentage actually saves, and whether frame pacing suffers when a
reservation handoff sleeps instead of spinning. Both are one sweep — 100 / 50 /
25 / 0, reading `spu_getllar` counts from the wait profiler and exact system
watts from `thor_power_probe.ps1` on an **unplugged** device.

Recording the boundary explicitly, because "needs a measurement" has been used
loosely in these notes and was wrong four times. Here it is precise: the
mechanism is fully verified, the target is quantified, and the only unknown is
the size of an effect and the cost of its side effect.

### Making the sweep cheap: a runtime override for the percentage

One obstacle stood between "the lever is verified" and "the sweep is one
command": `get_spu_wait_policy_for_runtime` is just `setting.observe()`, so the
percentage comes from config with no runtime path. Sweeping four values would
have meant **four full rebuilds**, because `config.yml` is not writable from a
shell under scoped storage.

Added `debug.rpcsx.thor.getllar_busy_percent`, following the convention already
used for the wait profiler, the cache-worker affinity mask and the Eternal Sonata
experiments:

    adb shell setprop debug.rpcsx.thor.getllar_busy_percent 25

Four boots instead of four builds, on a device whose availability is the scarce
resource.

**Inert by construction**, which the contract test enforces: an absent property
returns the configured value, a malformed one does too rather than defaulting to
something, and values above 100 are rejected — that last because the comparison
it feeds is against a modulo-100 quantity, so a larger number would silently mean
"always spin" while reading like a deliberate choice. It is read **once and
cached**, since the call site is inside the GETLLAR retry path and a property
read per iteration would perturb exactly the measurement it exists to enable —
the same mistake as the FPS harness whose per-sample `adb` spawns tripped the
thermal guard.

The test also asserts that **no Thor profile pins the percentage**. Changing that
default before measuring is the specific mistake worth preventing: it is a
plausible-looking edit, it would look like applying a finding, and the finding is
that the value is *untested*, not that it is wrong.

Verified by mutation — weakening the range check so an out-of-range value would
be accepted turns the test red, and restoring it turns it green.

### The sweep is scripted, because the methodology is what kept failing

`tools/thor_getllar_percent_sweep.ps1` runs the arms end to end. It is a script
rather than a checklist because **none of the three failed experiments in this
document failed for lack of care at the keyboard** — each failed on methodology
that must be identical across arms and is easy to get subtly wrong by hand:

- two WFE A/Bs compared **absolute** `cores_busy` across arms whose scenes
  differed by a factor of two, and the two readouts disagreed on the sign;
- a running-versus-stopped power comparison force-stopped **a package name that
  does not exist**, so both arms were the same configuration;
- a backoff comparison used windows that did not align with the profiler's own
  report boundaries.

Each of those is now a guard rather than a thing to remember:

| failure | what the script does |
| --- | --- |
| absolute metrics across differing scenes | headline is `spu_getllar` ticks per `spu_getllar_retry` call — a ratio whose denominator the change provably does not touch |
| a setting that silently did not apply | reads the property back and **throws** if it differs from what was set |
| a wrong package name | fails if `pidof` is empty after boot |
| unaligned windows | differences two profiler reports and uses **their** timestamps, not the wall clock |
| profiler build not actually used | throws if no profiler line appears |
| floor-only wattage reported as exact | warns when USB is attached, and tags the column |
| the device left on a swept value | clears both properties at the end |

It also prints the caveat with the result rather than leaving it to be recalled:
the spin ratio is the robust number, a watts delta means nothing unless the
device was unplugged, and **frame pacing has to be checked separately** — the
risk of sleeping instead of spinning is latency, not throughput, and this sweep
cannot see it.

Parses clean; not yet run, because it needs the device.

## The reverted reservation rewrites are functionally correct

After Eternal Sonata faulted in combat on `0x3f80000c` — a float bit pattern used
as a pointer — `mov_rdata` and `cmp_rdata` were reverted precautionarily, since
both had been rewritten that day and both sit in the path the fault implicates.

Precaution is not diagnosis, so the rewrites were then tested against the forms
they replaced. `tools/rdata_equiv.c` builds standalone for the device, the same
pattern as `bcax_bench.c`:

| coverage | cases |
| --- | --- |
| every single-bit difference across the 128 bytes | 1,024 |
| every single-byte difference, flipping the high bit | 128 |
| all-zero, all-ones, and patterns that sum to the accumulator's success value | 4 |
| randomised pairs, 75% of them near-misses with one byte perturbed | 4,000,000 |
| **total** | **4,002,180** |

**Zero mismatches**, on both functions.

The comparison is three-way rather than two-way, which matters: each result is
checked against the old implementation **and** against `memcmp`. Agreement
between two implementations proves nothing if both are wrong, and the old
`cmp_rdata` is itself a non-obvious construction — a multiply-accumulate over
0/-1 masks whose success value is the constant 32.

**What this establishes and what it does not.** The rewrites compute the same
answers as the code they replaced, over a space that includes every single-bit
perturbation. They are not wrong in the way a copy or compare is usually wrong.

It does **not** test them as the emulator uses them: single-threaded, in
isolation, and against a standalone build rather than the inlined forms in the
shipped library. A defect in memory ordering, or one that only appears when
several SPU threads race on the same reservation, would pass this cleanly.

**So the sequence from here is the informative one.** The reverted build is
installed. If the crash recurs without these changes, they are exonerated and the
cause is elsewhere — which this test already makes the more likely reading. If it
stops recurring, then something about them matters that a functional equivalence
test cannot see, and that is a far more interesting finding than a wrong lane
index would have been.

## The present path busy-spins too, on a 2017 desktop-driver workaround

Chasing an anomaly left unexplained in the crash logs — `dequeueBuffer timed out:
Connection timed out (-110)`, which appeared before the first freeze — found a
spin loop in the RSX present path that nothing in this work had looked at.

**24,459 timeout messages in 655 ms**, from 20:34:44.757 to 20:34:45.412. That is
roughly **37,000 iterations per second**, which is not a stall waiting on
something; it is a tight retry loop. It also flooded the log buffer hard enough
to evict everything before it, so **the failure mode destroyed its own diagnostic
context** — the reason the earlier freeze could not be traced further back.

The loop is in `VKPresent.cpp`:

```cpp
u64 timeout = m_swapchain->get_swap_image_count() <= VK_MAX_ASYNC_FRAMES ? 0ull :
#ifdef ANDROID
                                                    1000ull       // 1 us
#else
                                                    100000000ull  // 100 ms
#endif
;
while (VkResult status = m_swapchain->acquire_next_swapchain_image(..., timeout, ...))
{
    case VK_TIMEOUT:
    case VK_NOT_READY:
    {
        // ... "Found on AMD Crimson 17.7.2" ...
        // Whatever returned from status, this is now a spin
        timeout = 0ull;
        check_present_status();
        continue;
    }
```

Two things stack here.

**Android already gets a timeout 100,000 times shorter than desktop** — 1 us
against 100 ms — so it reaches the `VK_TIMEOUT` case far more readily.

**And that case then sets the timeout to zero and spins.** The comment justifying
it describes a fullscreen-switch quirk in *AMD Crimson 17.7.2*, a 2017 desktop
driver. On Android the acquire goes through a `BufferQueue`, and a zero timeout
turns "wait for a buffer" into "ask for a buffer as fast as the CPU allows",
which is what produces 37,000 log lines a second and burns a core in the flip
path.

**This is the same shape as everything else in this document**, arrived at from a
different direction: a wait implemented as a spin because a timeout was tuned for
different hardware. `GETLLAR` spins because a percentage defaults to 100.
`passive_lock` spun ten times too long because a backoff was sized for a 3 GHz
timer. This spins because a workaround for a 2017 AMD desktop driver was left
unconditional.

**Deliberately not changed yet.** The obvious fix is to keep a small nonzero
timeout on Android so the driver blocks instead of the emulator spinning — the
same trade as everywhere else here. But this is the middle of an unresolved crash
investigation, two reservation-path changes were just reverted, and adding an
untested change to the present path while the cause of a guest fault is unknown
would make the next result unattributable. Recorded now, changed after the crash
question is settled.

### Why the Android branch reaches that spin, in numbers

The ternary above only selects the platform timeout when the swapchain has more
images than `VK_MAX_ASYNC_FRAMES`, so it is worth confirming Android takes it at
all:

    VK_MAX_ASYNC_FRAMES                 2
    swapchain requests   max(minImageCount + 2, 3)  -> typically 3
    3 > 2, so the platform branch applies

Android therefore waits **1000 ns** before falling into the `timeout = 0` spin.
Against a display:

| | |
| --- | --- |
| Android acquire timeout | `0.001 ms` |
| desktop acquire timeout | `100.000 ms` — **100,000x longer** |
| one vsync interval at 60 Hz | `16.667 ms` |

**Android's wait is 16,667 times shorter than a single frame interval.** A
compositor paced to vsync cannot release a buffer inside a microsecond except by
coincidence, so whenever no buffer is already free the code goes directly to the
spin and stays there until one is — potentially a full frame.

The asymmetry is the whole finding. Desktop's 100 ms is a **genuine blocking
wait**: the driver parks the thread and no CPU is burned while the compositor
does its work. Android's 1 us is effectively *do not wait*, which converts the
same situation into a busy-spin.

**Provenance: this is inherited, not a Thor decision.** Both the 1 us constant and
the spin arrived with the vendored RPCSX core (`3bdb3223a`), so it is upstream
code rather than something this fork chose — which is exactly the category the
rest of this document keeps finding: a value that is correct on the hardware it
was written for and wrong here, carried across unexamined.

The fix is one constant, and it is the same trade taken everywhere else in this
work: give Android a timeout long enough for the driver to block — a vsync period
would do — so the wait is a sleep rather than a spin. Still not applied, for the
reason recorded above: an unresolved crash investigation is the wrong moment to
add an untested change to the present path.

## A fifth spin, and this one waits on the GPU

Sweeping deliberately for the pattern — rather than stumbling on instances — found
`vk::wait_for_fence`, whose **default is to poll**:

```cpp
VkResult wait_for_fence(fence* pFence, u64 timeout)   // timeout defaults to 0
{
    pFence->wait_flush();
    if (timeout)
    {
        return vkWaitForFences(..., timeout * 1000ull);   // blocks in the driver
    }
    else
    {
        while (auto status = vkGetFenceStatus(...))       // polls
        {
        case VK_NOT_READY:
            rx::pause();
            continue;
        }
    }
}
```

Two things make the polling branch worse here than it looks.

**It waits on the GPU.** A fence signals when submitted work completes, which is a
millisecond-scale event, not a microsecond one. Spinning across it is spinning for
a very long time by CPU standards.

**And `rx::pause()` does nothing on this core.** It emits `YIELD`, an SMT hint that
retires without effect on a non-SMT core — no clock drop, no park, no power
saving. So the backoff inside the poll is not a backoff at all; this is a bare
retry loop at full clock.

Three callers, and the split is instructive:

| site | timeout | behaviour |
| --- | --- | --- |
| `VKTextureCache.cpp:1359` | `GENERAL_WAIT_TIMEOUT` | **blocks** — correct |
| `VKPresent.cpp:199` | none | polls, but only on swapchain resize |
| **`vkutils/commands.cpp:77`** | none | **polls, in `command_buffer::begin()`** |

The third is the one that matters. `command_buffer::begin()` polls whenever the
buffer it is about to reuse is still pending — that is, whenever the GPU has not
yet finished the work submitted on it. With `VK_MAX_ASYNC_FRAMES` at 2 there are
few buffers to cycle, so under any GPU-bound condition this is a CPU thread
burning a core waiting for the GPU to catch up.

**Not asserted as hot without measurement**, and the wait profiler does not
instrument it, so its real cost here is unknown. What is certain is the shape: a
blocking primitive was available, the call sites that pass a timeout get it, and
the ones that omit the argument silently get a spin instead. **A default value
that changes a wait into a poll is a bad default**, whatever its frequency.

That makes five, all the same shape, none of them instruction selection:

| site | spins because |
| --- | --- |
| `GETLLAR` | a percentage defaults to 100 |
| `passive_lock` | a backoff was sized for a 3 GHz timer |
| `lv2` sub-quantum sleep | x86 gets `TPAUSE`, AArch64 falls to `sched_yield` |
| present acquire | 1 us timeout where desktop gets 100 ms |
| **GPU fence wait** | **the timeout parameter defaults to zero** |

Unchanged for now, for the reason the previous entries record: a crash
investigation is open and untested changes would make its result unattributable.

### The GPU fence poll is now instrumented, so its cost stops being a guess

Of the five spins, four have measured or derivable costs. The GPU fence poll was
the exception — recorded as "not asserted as hot without measurement", which is
honest but leaves the one open question about it unanswered.

`thor_wait::site::vk_fence_poll` closes that. It counts entries into the polling
branch and accumulates the iterations spent there, so `cycles/calls` is the mean
number of times a GPU wait was spun through.

Two details, both learned from earlier mistakes in this document:

**Only waits that actually spun are recorded.** A fence that is already signalled
takes zero iterations, and counting those would bury the interesting cases under
a mass of zeros — exactly what made the `GETLLAR` episode counter unusable for
tuning, where the denominator counted every wait that started rather than every
wait that spun.

**Instrumentation only; the behaviour is untouched.** The polling branch still
polls. Adding the counter and changing the wait in one step would leave any
subsequent measurement unattributable, and there is an open crash investigation
that makes that worse.

Built and verified in both configurations, profiler on and off. **Deliberately
not installed**: the device is running the reverted build under test, and
replacing it would destroy the one experiment that can say whether the reverted
reservation changes were implicated in the guest fault.

When that question resolves, this arrives with the sweep — one profiler build
answers both what the GETLLAR percentage is worth and whether the fence poll
deserves a fix.
