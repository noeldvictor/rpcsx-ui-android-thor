# The instruments, and what each one can and cannot answer

Every wrong conclusion in this work came from a measurement that was correct
about something other than the question. This is what each tool measures, what
it does not, and the mistakes made building them.

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

## The metric that finally makes the WFE A/B possible

Two WFE experiments failed here, both because the workload will not hold still.
The third attempt starts by fixing the *metric* rather than the instrument, and
the fix comes from reading how the flag is wired rather than from measuring
harder.

`SPUThread.cpp` has **two** profiled sites in the reservation wait, and only one
of them is behind the flag:

| site | line | inside `RPCSX_THOR_ARM64_WFE_WAIT`? |
| --- | --- | --- |
| `spu_getllar` | 6064 | **yes** — it is the `else` of `if (getllar_spin_count >= 8)`, so WFE replaces it with a park |
| `spu_getllar_retry` | 6210 | **no** — a separate outer retry loop the flag never touches |

So the outer retry count is an **independent measure of how much reservation
contention the workload is actually generating**, unaffected by the change under
test. That is exactly the denominator this experiment needed:

    inner GETLLAR spin ticks / outer retry calls

Validated on two control windows chosen because they differ wildly in load:

| window | cores spinning | ticks per retry |
| --- | --- | --- |
| 8.8 s window | `0.814` | **263.7** |
| 20.6 s window | `1.295` | **260.7** |
| spread | **59%** | **1.1%** |

**The absolute spin rate varied by 59% between two windows of the same build, and
the normalized ratio varied by 1.1%.** That is the difference between an
experiment that can detect a change and the two that could not.

Control baseline for the WFE arm: **~262 ticks per retry**.

The general lesson is worth more than the number. Both earlier attempts tried to
stabilise the *workload* — matched settle times, matched window lengths,
savestates for a fixed scene. None of that was necessary. **The workload was
allowed to vary as long as the metric divided by something that varied with it.**
Look for a quantity the change under test provably does not touch, and normalise
by it; here the code structure handed one over for free, and reading which branch
the flag sat in was worth more than any amount of measurement discipline.

## "Needs hardware this device lacks" was two claims, and only one is true

The watts question has been recorded here as blocked because the device exposes
no CPU-isolated power rail. That is true, and it has been used to imply something
false — that absolute power cannot be measured at all. Two separate claims got
merged:

**Attributing watts to the CPU specifically: genuinely not available.** There is
no per-rail sensor separating CPU from GPU, display, memory and radio. So "the
0.81 cores of spin were worth *N* watts" cannot be answered directly on this
part, and a spin reduction cannot be converted into a wattage without assuming a
model.

**Measuring total system power: available, and exact.** `charge_counter` is
cumulative in microamp-hours; differenced across a window it gives mean current,
and the probe reports **0.002 W spread across four idle runs**. The only
requirement is that the battery be *discharging*, because while charging the
charger supplies an unknown share and the battery figure is a floor. The probe
already distinguishes these, printing `on battery, exact` versus
`FLOOR, USB attached`.

**So the blocker is a USB cable, not a missing sensor.** Unplug the device and
drive it over the wireless adb endpoint that is already configured
(`192.168.1.33:5555`, alongside the USB serial `c3ca0370`), and system power
becomes exact.

That matters because it is the user's actual question. "I could have sworn we
used a watt less this morning" is about **system draw**, which is measurable,
not about CPU-attributed draw, which is not. Every reading in this document
carrying a `FLOOR` tag — 6.9 W, 8.5 W, 10.5 W — is a floor solely because the
cable was in.

**Recorded as a correction to this document's own framing.** Saying "blocked on
hardware" when the truth is "blocked on unplugging it" is the difference between
an item nobody can act on and one that needs thirty seconds of physical access.
This is the third time in this work that re-reading a self-declared blocker found
it partly self-inflicted: the RawSPU decoder was blocked on integration rather
than on analysis, the range-lock fix was blocked on a proposal that was wrong
rather than on risk, and this one was blocked on a cable.

## The post-fix ranking is arithmetic, not a measurement

This document has repeatedly deferred to "a fresh spin ranking, since
`passive_lock` dropping 68% will have reshuffled the list". It will not reshuffle
it, and the inputs to say so were already measured.

Pre-fix shares: `GETLLAR` family 82.5%, `vm_passive_lock` 17.5%, everything else
under 1%. The backoff ladder cut `vm_passive_lock` by 68.3% at that site and left
the others untouched, so:

| site | before | after | share of new total |
| --- | --- | --- | --- |
| `GETLLAR` family | 82.5% | 82.5% | **92.8%** |
| `vm_passive_lock` | 17.5% | 5.5% | 6.2% |
| mutex and rest | 0.9% | 0.9% | 1.0% |

Total spin is now **88.2%** of what it was, and `GETLLAR` goes from 82.5% to
**93%** of what remains. **The ranking does not change; it concentrates.** The
only question a fresh ranking could have answered — what to attack next — was
already answered by the numbers that produced it.

**That closes the priority question and opens a harder one.** `GETLLAR` is the
target and both obvious levers on it are spent:

- the **backoff** is correctly sized — spins that reach it have already passed a
  gate at `spin_count == 4`, so 300 ticks is not overshoot;
- the **park** is correctly gated — break-even is depth 6.1 and the threshold is
  8 — and structurally capped, because 95.5% of spins are shallower than the
  95 us it costs to park at all without `FEAT_WFxT`.

So the remaining lever on 93% of emulator spin is not *waiting more cheaply*. It
is **not needing to wait**: reducing how often SPU threads collide on the same
reservation line in the first place. That is a scheduling and workload question
rather than an instruction-selection one, it is the first item in this document
that ARM64 knowledge does not obviously help with, and nothing here has
investigated it.

Worth separating clearly, because "the biggest remaining target has no known fix"
is a different and more useful statement than "we need another measurement to
know where to look".

## Open: the RSX auditor's `enabled()` gate rejects while cached says enabled

Unresolved after five instrumented boots. Written down in full because the
evidence is self-contradictory and the next person should not re-derive it.

**Symptom.** With `debug.rpcsx.thor.rsx_auditor=1` set before launch and Folklore
holding 60 fps, the auditor emits nothing — including its own original
`Thor RSX Auditor: frames=` report, so this is not something the staging or
`LOAD_OP_CLEAR` counters introduced.

**What was ruled out, each by measurement rather than reading:**

* not compiled out — the `RPCSX_THOR_RSX_EXPERIMENTS` guard at 794 closes at 825;
  `on_frame_end` is at 857
* it *is* called — a one-shot probe fired immediately, and a counting probe
  reached **~3,750 calls**
* not a rare-call problem — 3,750 calls against `interval=60` should report ~60×
* the interval gate is never reached — a probe inside its reject branch (923)
  never fired
* the `enabled()` gate at 893 is what rejects — its probe (902) fires every call
* `rsx_log.warning` reaches the log; other RSX warnings appear in the same boot
* the installed APK is the instrumented one (`lastUpdateTime` after the build)

**The contradiction.** The probe at 902, inside `if (!enabled())`, prints:

```
on_frame_end call #1 (enabled=1 interval=60)
ENABLED GATE REJECT #1 cached=2 poll=1
```

`cached=2` is the *enabled* value, and `enabled()` ends in `return cached == 2`.
Worse, `poll=1` says only **one** `enabled()` call has happened this iteration,
when the call probe on the line above makes one of its own — so the two
observations cannot both be of the same state.

**Next step, and it is not more reading.** Two candidates worth one probe each:

1. `enabled()` takes its `poll_enabled_property()` path whenever
   `(poll & 0xfff) == 0`, and **`poll` is the pre-increment value, so this is
   true on the very first call**. If that re-read returns false the gate rejects
   while a later `cached` read still shows 2. Log the return value of
   `poll_enabled_property()` directly.
2. These are `inline` variables in a header. If the header is compiled into more
   than one shared object, each gets its own `g_cached_enabled` and
   `g_property_poll_counter`, and probes in different objects would disagree
   exactly like this. Log `&detail::g_cached_enabled` from both sites and
   compare the addresses.

Candidate 2 explains the `poll=1` anomaly and candidate 1 does not, so start
there.

### Candidate 2 is refuted, and the puzzle got sharper

Logging `&detail::g_cached_enabled` from both sites:

```
on_frame_end call #1 (enabled=1 interval=60)      cached@00000075e1fe9350
ENABLED GATE REJECT #1 cached=2 poll=1            cached@00000075e1fe9350
```

**Same address.** One instance, not duplicated inline state across shared
objects. Candidate 2 is dead.

The poll counter now says something sharper. `poll` is read after the gate's
`enabled()` call, and it reads **1** on the first iteration and **2** on the
second — exactly **one** `enabled()` call per `on_frame_end`, when the source
plainly contains two (the call probe's, then the gate's). Each call does an
unconditional `fetch_add`, so two calls cannot produce one increment.

So all three of these hold simultaneously and cannot:

1. `cached == 2`, and `enabled()` ends in `return cached == 2`
2. the `!enabled()` branch is the one executing
3. only one of the two written `enabled()` calls is incrementing the counter

Point 3 is the thread to pull. An `fetch_add` cannot be elided, so either one
call is not the function I think it is, or one of the two log sites is not where
I believe it is despite the line numbers agreeing. The next probe should print
`&calls` and `&offs` — the two probe-local statics — alongside a value captured
into a local *before* the branch, so the branch condition and the printed value
are provably the same evaluation rather than two separate calls.

### Solved: there are two `enabled()` functions

Hoisting both calls into locals so the branch and the print share one
evaluation gave it away immediately:

```
call #1    (enabled=1 interval=60) cached@...358 poll_here=1
REJECT #1  cached=2 poll=1         cached@...358 en_gate=0
```

`poll_here=1` after the probe's call, and `poll` still **1** after the gate's —
the gate's call never touched the counter. Two different functions:

```cpp
#if !defined(ANDROID) || defined(RPCSX_THOR_RSX_AUDITOR)
    FORCE_INLINE bool enabled() { return detail::enabled(); }
#else
    // remove the default-off recorder's atomic/property polling from Android
    FORCE_INLINE constexpr bool enabled() noexcept { return false; }
#endif
```

**On Android without `RPCSX_THOR_RSX_AUDITOR`, `enabled()` is `constexpr
false`.** My probes called `detail::enabled()` — the real one, which
reads the property and returns true. Every gate in the file calls the
*unqualified* `enabled()`, which the preprocessor had already reduced to `false`.

So `debug.rpcsx.thor.rsx_auditor` could never have worked in a normal build, and
the whole investigation was chasing a runtime explanation for a compile-time
fact.

**What made this expensive.** I did check whether `on_frame_end` sat inside the
`RPCSX_THOR_RSX_EXPERIMENTS` guard — it does not, and I recorded that as
"not compiled out" and moved on. I never checked the guard on the *function it
calls*. Verifying that a function is compiled in says nothing about the
predicates inside it.

The general form, and it is the same shape as `mov_rdata`: **a preprocessor
guard can neutralise code without removing it.** `mov_rdata` had a body deleted
and the `#elif` left behind; here a predicate is `constexpr false` on this
platform. Both look like ordinary code and neither shows up as absent.

**The build flag is the fix**, not a code change:

    ./gradlew assembleThortest -PrpcsxThorRsxAuditor=1

which sets `-DRPCSX_THOR_RSX_AUDITOR=ON` (`app/build.gradle.kts:211`). This is a
different CMake configuration, so it builds its own `.cxx` tree — budget ~14
minutes and ~8 GB.

**Correction, and it cost a whole build cycle.** The first attempt used
`-PrpcsxThorRsxExperiments=1`, because I read the guard off the *neighbouring*
`#if`s at lines 467 and 794, which really are `RPCSX_THOR_RSX_EXPERIMENTS`, and
assumed the one on `enabled()` matched. It does not: there are two independent
options, `RPCSX_THOR_RSX_AUDITOR` and `RPCSX_THOR_RSX_EXPERIMENTS`, and the
recorder is behind the first. The experiments build compiled, installed, and
still logged `en_gate=0` — which is what caught it.

That is the third time in this investigation that reading a nearby line instead
of the exact line produced a confident wrong answer.

## The home menu sometimes opens ~12 s into a boot and pauses emulation

**Corrected: this does not happen on every launch.** It was written up that way
after three occurrences in a row; two clean boots immediately afterwards did not
reproduce it, and both produced valid profiles. The trigger is still unidentified,
so treat it as intermittent and check for it rather than expecting it.

What it looks like when it does happen:

```
0:00:11.911  rpcn: Loading RPCN config
0:00:11.912  RSX: Friends list hidden in home menu. RPCN is not configured.
0:00:11.916  {Overlay Input Thread} SetIntercepted: pads=1, keyboards=1, mice=1
0:00:11.916  SYS: Emulation is being paused... (mark=0)
0:00:11.916  Input: opened home menu with result 0
```

An input event reaches the overlay ~12 s after launch, opens the PS3 home menu,
and **pauses emulation**. `getevent -p` shows an `Odin Controller` and an
`ODIN Station Virtual Mouse` attached, so the likely source is a controller
button — or the overlay's input loop interpreting one — rather than the device
being touched.

**This has been corrupting measurements all along.** A paused emulator does
almost no work, which is exactly the signature behind:

* a profile that captured **627 samples in 25 s** instead of the ~40,000 a busy
  run produces
* the `jit_cpu_native` arm at **2.762 cores** against a 5.2 gameplay norm
* the `cortex-a710` arm previously written off as "still compiling"

All three were read as phase mismatches. They were pauses.

**Why it matters beyond measurement:** if the home menu opens twelve seconds into
every launch, it does so for a person playing, not just for a benchmark. That is
a functional bug worth chasing on its own, and it is upstream of any performance
work — no A/B on this device is trustworthy until it is fixed or suppressed.

**Ruled out: a hardware key.** `getevent -lt` across a full 30 s boot captured
**zero input events** — only the eleven device-enumeration lines. No `KEY_BACK`, no
`BTN_MODE`, no PS button. Nothing physical was pressed, and the Odin Controller and
its virtual mouse emitted nothing.

That leaves three code paths, now mapped:

1. `_rpcsx_surfaceEvent(event=2)` — surface destroyed — at
   `rpcsx-android.cpp:2523` calls `open_home_menu()` and then `Emu.Pause()`. This
   one already logs (`ANDROID: surface event <ptr>, 2`), and in the clean boots
   only events `0` and `1` appeared, at t=0.6 s.
2. The PS button in the pad data, `rpcsx-android.cpp:2236`.
3. `handleOsdBack()` in `RPCSXActivity.kt`, reached from `onKeyDown` for
   `KEYCODE_BACK` or `KEYCODE_BUTTON_MODE`, or from `onBackPressed()`.

Path 3 logged nothing at all, which is why the trigger could not be identified from
the logs on hand; it now logs its reason, the originating device name and the input
source, and `_rpcsx_openHomeMenu` logs the JNI hop. With those in place one
occurrence names the culprit.

A fourth path is dead: `pad::g_home_menu_requested` is read at `pad_thread.cpp:472`
and **never written anywhere in the tree**, so it can never fire.

Worth fixing regardless of the trigger: `_rpcsx_surfaceEvent` opens the home menu on
surface *destroy* but the create branch only calls `Emu.Resume()` — it never closes
the menu. Backgrounding and returning therefore resumes the game with the home menu
overlay still up and input still intercepted, and the PS button cannot dismiss it
because `m_home_menu_open` is already `true`.

## The frame instrument that was here all along: SurfaceFlinger latency

This repo spent a long time asserting that **FPS is only drawn, never logged**, and
built gates around screenshots and a frame counter because of it. That was true of
the emulator's own overlay and false of the platform. Android hands out per-frame
present timestamps for any layer:

```sh
adb shell dumpsys SurfaceFlinger --list | grep BLAST | grep RPCSXActivity
adb shell dumpsys SurfaceFlinger --latency '<that layer>'
```

Each call returns up to 128 rows of `desiredPresent actualPresent frameReady` in
nanoseconds. Differencing column two gives the frame-interval distribution, so
**p50/p95/p99 are available with no build flag, no property, no instrumentation and
no rebuild**. Poll it every 5 s and union the rows to cover a longer window; the
rows overlap, so deduplicate on the timestamp rather than concatenating.

Two traps, both hit on the first attempt:

* **Query the `(BLAST)` layer.** `SurfaceView[net.rpcsx.easy/...]#N` without
  `(BLAST)` exists, accepts the command, and returns nothing but `0 0 0` rows —
  a silent empty result, the exact failure mode this file keeps cataloguing.
* **The layer's numeric suffix changes every boot.** Resolve it per arm. A
  hardcoded `#13719` will match nothing on the next launch and, again, return
  zero rows rather than an error.

Why it matters more than the counter it replaces: a frame counter derived from a
log line that fires every 250 frames is quantised to 6.25 fps over a 40 s window,
which is enough to check two arms are in the same state and nowhere near enough to
see a latency regression. **A capped 60 fps hides stutter by construction** — the
mean is pinned by the cap and only the tail moves. Every A/B here that could plausibly
trade latency for throughput should report percentiles from this source. The lv2
spin decision in [`lv2-ppu-spin.md`](lv2-ppu-spin.md) turned on exactly that: the
frame counter said "unchanged" and could not have said anything else, while the
percentiles said unchanged to within 0.02 ms across four arms and actually meant it.
