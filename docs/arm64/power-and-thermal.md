# Power, thermal behaviour and the measurements around them

The device is passively cooled and the emulator already hits its frame cap on
the title that matters, so power is the budget this fork is managed against.
This is also where the worst measurement mistakes happened.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## Measured, on this silicon

`tools/bcax_bench.c` measures a codegen change directly, without needing a game
to boot. Build it with the NDK (`--target=aarch64-linux-android29 -O2
-march=armv8.2-a+sha3 -static`), push to `/data/local/tmp`, pass a cpu index.

BCAX replacing the two-op form, best of five:

| shape | X3 | A715 | A510 |
| --- | --- | --- | --- |
| latency, serial chain | `1.96x` | `2.01x` | `2.00x` |
| throughput, 4 independent chains | `0.94x` | `1.00x` | `2.02x` |

**The two shapes disagree, and which one applies decides whether a change is
worth making.** The big cores have enough vector pipes to issue the old pair in
parallel, so a wider instruction wins nothing there and can lose slightly. It
wins when the result feeds the next instruction. Check the real lowering before
assuming: our `SHUFB` emits `bcax` immediately followed by the `tbx` that
consumes it, so the latency row is the one that describes it.

Boot on a warm cache, measured end to end: SPU cache build finishes around
`50 s` (`module 1179`), title menu follows, and holds `FPS 30.00`, the game's
PS3 target, at `24.7-33.1%` total CPU.

Thermal profile of a direct boot, sampled every 2 s (an earlier 4 s sweep
reported a `57.8 C` peak and simply missed the spike):

```
2s:56.2  4s:60.2  6s:46.2  8s:47.8  10s:44.9 ... 60s:55.0 ... 90s:56.6
```

The transient peaks `60.2 C` at `t=4s` and collapses to `46.2 C` two seconds
later, after which the run sits at `44-57 C` and drifts up slowly. Sample at
2 s or finer; a 4 s sweep aliases the spike.

**The harness is not thermally free.** The same build, game, and settings run
through `thor_input_macro.ps1` climbs `59.4 -> 58.6 -> 61.0 -> 64.6 -> 70.7 C`
within about ten seconds and trips the early stop, while the direct boot above
never leaves the fifties. Its per-sample `adb shell` spawns walk roughly fifty
`thermal_zone*` sysfs entries, the sustain loop adds a poll per second exactly
when the device is hottest, and each readiness poll takes a 1080p `screencap`.
That overhead lands on a machine with no spare headroom during boot. Treat
harness temperatures as an upper bound that includes the observer, and use a
direct `THOR_DEBUG_BOOT` when the question is about the emulator rather than the
route.

## The guard measures junction maxima against a package-shaped limit

Following the sensor mistake below to its source found the same error in the
project's own tooling, and it explains a decision that was made on it.

`thor_debug_common.ps1` classifies any zone whose name matches
`cpu|gpu|soc|apss|cluster|silver|gold|prime|cpuss|ddr|memory|modem|pmic|xo` as
domain `silicon`, then reports `silicon_temperature_c` as the **maximum** of
that set. On this device that set includes `cpu-1-0` through `cpu-1-10`, which
are **per-core junction sensors**. Measured directly on the same zone:

    cpu-1-9  during unthrottled compile   90.7 C
    cpu-1-9  idle, minutes later          55.0 C

A ~35 C swing with load is the signature of a junction sensor. The subsystem
sensors beside it behave quite differently: `cpuss-0` reads 49.4 C idle, and the
`gpuss-*` group sits at 43-46 C.

This device also exposes **no `skin`-domain zone at all** — nothing matches
`skin|case|shell|quiet` — so the guard has no package sensor to fall back to and
rests entirely on that junction maximum, compared against
`MaxSiliconTemperatureC = 72.0`.

**A 72 C limit on a junction maximum is not a thermal bound, it is a load
detector.** Junction routinely passes 72 C on this SoC under any sustained work
and is unremarkable until roughly 95-105 C. That is why the original
cache-worker A/B recorded "71.1 C at the first runtime sample, guard stopped it
0.7 s in" for the ordinary scheduler: the arm that used the big cores tripped a
junction threshold almost immediately, and the arm pinned to the A510s did not,
because little cores have lower junction temperatures. The measurement was
faithfully recording which arm ran on faster cores.

So the A510 pinning was adopted to satisfy a limit that was measuring the wrong
quantity. Removing it, done for the independent reason that ten minutes at
51-58 C package was a bad trade, turns out to have removed a decision that rested
on an artifact.

**Fixed, without touching the safety bound.** The threshold was never the bug;
the classification was. `cpu-<cluster>-<core>` now resolves to a new `junction`
domain, leaving `silicon` to the subsystem sensors it was always meant to
describe. `MaxSiliconTemperatureC` stays at 72 C against those, and junction gets
its own `MaxJunctionTemperatureC = 95.0`, which still catches a genuine runaway
while no longer calling ordinary load an emergency.

Verified on the device at moderate load, and the numbers make the old failure
plain:

    silicon  : 64.6 C  from cpuss-2   (15 sensors, limit 72)  no violation
    junction : 71.9 C  from cpu-1-8   (14 sensors, limit 95)  no violation

Under the old classifier `silicon` was the maximum of both sets, so it would have
reported **71.9 C against a 72 C limit** — one tenth of a degree from stopping a
run, at a temperature that is entirely unremarkable. That is the mechanism behind
"stopped it 0.7 s in".

All four thermal contracts still pass.

## Read the right thermal sensor, and never mix two of them

`/sys/class/thermal/thermal_zone*/temp` on this device exposes both package-level
and **per-core junction** sensors. Taking the maximum across all of them is
wrong, and wrong in a way that manufactures alarm:

    cpu-1-9  = 90.7 C     per-core junction (Tj)
    cpu-1-10 = 83.9 C
    cpuss-0  = 68.7 C     CPU subsystem
    (AYN FanBase / on-device readout: 57-61 C, package)

Junction temperature always reads far above package. Roughly 90 C Tj under load
is ordinary for this SoC, which throttles nearer 95-105 C. The number the fan
curve uses, the number the device shows the user, and the number
`MaxSiliconTemperatureC = 72.0` bounds are all **package**, not junction.

This was found the hard way: an unthrottled compile was reported as "81.5 C,
above the 72 C gate" and nearly reversed a good change, when the device was
actually at 57 C and the reading came from a junction sensor. **A limit and a
measurement taken from different sensors cannot be compared**, and taking a
`max` over a heterogeneous sensor set silently does exactly that.

This is the same failure as the thermal wall recorded in the traps in
[`CLAUDE.md`](../../CLAUDE.md), in a
new costume. That one was sampling aliasing; this one is sensor mismatch. Both
produced a confident number that meant nothing. Use the project's own
`silicon_temperature_c` from `tools/thor_input_macro.ps1`, or the package sensor
the fan controller reads, and never a bare `sort -rn | head -1` over every zone.

With the correct sensor, the compile-throttle change reads:

| | time | package temp |
| --- | --- | --- |
| throttled (A510 x3, 2 LLVM threads) | ~10 min | 51-58 C |
| unthrottled (all cores, auto threads) | **~3 min** | **57-61 C** |

Roughly three times faster for about three degrees.

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

## An instrument that measures power without a fixed scene

Every power question in this document had the same blocker: the only readouts
were FPS, which cannot see power at all, and temperature, which lags and which
the harness itself perturbs. `tools/thor_power_probe.ps1` closes that gap.

It reads **cumulative** kernel counters — `cpufreq/stats/time_in_state` and
`cpuidle/state*/time` — so a measurement of any length costs exactly **two adb
round trips**. That is the property that matters. The FPS harness spawns a shell
per sample and walks fifty `thermal_zone` entries each time, which this document
records as being hot enough to trip the thermal guard on its own. An instrument
whose cost does not scale with the window can watch a five-minute run for the
price of a five-second one.

Validated against `/proc/stat` over the same window rather than trusted:
`cpuidle` reported 0.444 cores busy where `/proc/stat` reported 0.376, and the
raw idle sum, 75.73 seconds across 8 cores in 10 seconds of wall time, agrees
with both.

### What it measures, and the two mistakes made building it

| metric | meaning |
| --- | --- |
| `residency_mcycles` | cycles the core was *clocked* for. **Not work.** |
| `busy_ratio` | fraction of wall time outside cpuidle. The cleanest WFE signal. |
| `work_mcycles` | `residency * busy_ratio`, the honest estimate of retired cycles |
| `mean_mhz` | frequency residency, which matters because power rises faster than linearly with clock |

**`time_in_state` counts all wall time, including idle at the parked frequency.**
It is frequency residency, not work. Reading it as work overstated an idle device
by more than tenfold on this probe's first run. The jiffy unit was then verified
on device rather than assumed: per-step deltas sum to 1001 over a 10 s window and
the running total matches uptime in seconds times 100.

**There is no measured USB input current on this device.** The first attempt at
absolute watts computed `usb_in - battery_charge`, so that power could be read
without unplugging. It returned a **negative wattage**, which is the tell.
`usb/current_now` sat frozen at 447000 across three seconds while
`battery/current_now` swung from -1130521 to -770160: it is the negotiated input
limit, and the `ucsi` source node reports 0. So there is nothing to subtract and
the identity had no basis.

**And an instantaneous battery reading is noise.** The second attempt sampled
`current_now * voltage_now` once per snapshot. Measured five times on an idle
device that gave **0.300, 0.588, 1.447, 1.914 and 1.961 W** — a spread of
**1.66 W**, larger than the effect the instrument exists to detect. Over the same
five runs `cores_busy` held between 0.473 and 0.487. The CPU metrics were solid
and only the wattage was junk, because `current_now` is a spot reading of a
supply that fluctuates hard under charging.

The fix is the same trick that made the CPU counters work: **`charge_counter` is
cumulative**, in microamp-hours. Differencing it across the window gives the mean
current over that window rather than a sample from one instant. Re-measured four
times on an idle device: **0.627, 0.629, 0.629, 0.628 W**, a spread of
**0.002 W**. That is roughly 800x tighter, and comfortably enough to resolve the
one-watt question that prompted this.

**Use a cumulative counter wherever one exists.** Every metric in this probe that
works is a difference of two cumulative readings; every one that had to be
rewritten started as an instantaneous sample.

That is the same lesson as the `WFE` latency probe and the ESR `ISV` decode,
for the third time: **when a probe returns a physically impossible number, the
probe is what is broken.** Negative power, like a 10 ns `WFE`, is not a surprising
result to be explained. It is a bug.

### The first numbers, and a retracted one

Idle, USB attached, so the wattage is a floor:

| | cores busy | power |
| --- | --- | --- |
| device idle, emulator not running | `0.48` | `0.628 W` |

**A previously recorded attribution of ~1.78 W to the emulator is withdrawn.**
It compared a "running" against a "stopped" arm, and the stop was
`am force-stop net.rpcsx.thortest`. That package does not exist: the APK is named
for its build variant, `thortest`, while the `applicationId` is
**`net.rpcsx.easy`**. The force-stop silently did nothing, so both arms were the
same configuration and the difference between them was whatever the device
happened to be doing. The wattage in that comparison was also the instantaneous
kind described above, with a 1.66 W noise floor around a claimed 1.78 W effect.

Two independent errors, either of which was enough to invalidate it. Worth
stating plainly rather than quietly recomputing, because the failure is a general
one: **a negative control that does nothing looks exactly like a negative control
that works.** `am force-stop` on a package that is not installed exits zero and
prints nothing. Check that the thing you turned off actually went off - here,
`pidof` against the real package name.

That makes this the instrument the `WFE` question always needed. The earlier
experiment failed because its two arms sampled different cutscene content and its
two readouts disagreed on the sign. `busy_ratio` does not care what is on screen:
a parked core is parked.

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

## Two dead ends on the spin, and the instrument that was already built

The retry loop is the right thing to attack — 15.6 us per `busy_wait(300)` against
roughly 50 cycles of real work per iteration — but the two obvious attacks are
both closed, and one of them was proposed in this session before checking.

**Retuning the busy-wait constants is the documented catastrophe.** The comment
on `busy_wait` in `rx/asm.hpp` is explicit: upstream scales the count by the
generic-timer frequency because its call sites carry x86-derived numbers tuned
for a ~3 GHz timer, and **this fork already solved it the other way**, by
retuning every hot call site by hand against the real 19.2 MHz timer. The
100/200/300/500 arguments in `vm.cpp`, `SPUThread.cpp`, `CPUThread.cpp`,
`mutex.cpp` and `RSXFIFO.cpp` are those retuned values. Applying the scale on top
divides them a second time, collapsing a 5-26 us backoff to 50-260 ns, which
produces a lock convoy on every contended reservation, channel and mutex.
Measured on Thor as a drop to **about 1 FPS**.

So `busy_wait(300)` meaning 15.6 us is deliberate, not an unconverted x86 number.
This was proposed here as "the cheapest real win" and it is the exact trap the
traps list already warns about: *do not port an upstream ARM tuning fix without
checking whether this fork already compensated.* Reading the comment above the
function would have cost thirty seconds.

**Batching the polls was tried and failed.** The spin body is
`do pause(); while (get_tsc() < stop);`, and `pause()` is `YIELD`, which retires
doing nothing on a non-SMT core, so each iteration is effectively one
`MRS CNTVCT_EL0`. Reading the timer fewer times looks free, since the wait
duration is unchanged and only the work done while waiting falls. There is a
complete implementation of exactly that, batching 2 to 32 `pause()` calls per
timer read, behind `RPCSX_THOR_BUSY_WAIT_EXPERIMENT` — and the CMake option
describing it reads *"Build the failed Android ARM64 busy-wait batching
experiment"*. Already explored, already negative.

### What has not been used: the wait profiler

`util/thor_wait_profiler.h` instruments **24 wait sites** with atomic call and
cycle counters, including `spu_getllar`, `spu_getllar_retry`,
`spu_dma_reservation`, `vm_writer_lock`, `vm_reservation_lock` and the mutex
family. Every `busy_wait` in the SPU path already goes through
`thor_wait::profiled_busy_wait(site, n)` rather than calling `busy_wait`
directly, so the instrumentation is in place at every site that matters.

It is off by default and appears not to have been run recently:

    ./gradlew assembleThortest -PrpcsxThorWaitProfiler=1
    adb shell setprop debug.rpcsx.thor.wait_profiler <interval>
    # per-site calls and cycles are printed to logcat under the RPCS3 tag

**This is the missing measurement, and it does not need a fixed scene.** The
counters are cumulative, which is the same property that makes the clock and
charge counters in `thor_power_probe.ps1` usable while a workload varies. The
WFE A/B failed because the emulator's workload swings by a factor of two within
a single arm; a cumulative count of *how many cycles were spent spinning, at
which site* does not care what is on screen.

What it should settle, in one run:

- what fraction of SPU time is spin rather than work, which is the number the
  whole `WFE` argument rests on and which has never been measured here;
- which site dominates, so the effort goes to the right loop — `spu_getllar_retry`
  is the assumed answer and it is an assumption;
- whether `vm_writer_lock` and `vm_reservation_lock` show the contention the
  per-reservation LSE redesign is meant to remove, which is currently the only
  argument for that redesign and is entirely theoretical.

That last one matters most. The optimization guides document no atomics at all,
so the LSE item cannot be justified by reading; this profiler is the one
available instrument that could justify or kill it.

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

`thor_wait_profiler` does not currently instrument this site. Adding one would
make it answerable in the same run that answers the SPU spin question, and it is
a strictly additive change.
