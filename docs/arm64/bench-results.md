# Bespoke benchmark results, 2026-08-13

First run of `tools/bench/thor_bench`, outside the emulator. Device quiet, our
emulator stopped, the other session idle, **30.9 C before and 30.1 C after**, so
no arm here is a throttled core reported as a result.

Every number is `ns` measured against `cntvct_el0`, whose frequency was **read,
not assumed**: `timer_hz=19200000`, one tick 52.083 ns. The clusters run at
2803 MHz (A715, A710), 2016 MHz (A510) and 3187 MHz (X3).

**What this document is not.** These are isolated costs. They do not say what is
hot, and they do not say what any of it is worth in a frame. The ledger records
nine manual predictions refuted on exactly that gap.

## The core map, and a correction to the affinity advice

| CPU | core | capacity | MHz | single-core pin |
| --- | --- | --- | --- | --- |
| 0-2 | Cortex-A510 | 280 | 2016 | yes |
| 3-4 | Cortex-A715 | 855 | 2803 | yes |
| 5 | Cortex-A710 | 855 | 2803 | **refused** |
| 6 | Cortex-A710 | 855 | 2803 | yes |
| 7 | **Cortex-X3** | 1024 | 3187 | **refused** |

`CTR_EL0 = 0x49444c004` on every core that could be pinned, which matches the
ERG and CWG of 64 bytes already recorded.

**CPU5 and CPU7 refuse an exclusive affinity *when the device is idle*, and it is
not this program's bug.** `taskset 0x20` and `taskset 0x80` both fail with
`Invalid argument`, while `taskset 0x8` and `taskset 0x40` succeed and report
`Cpus_allowed_list: 3` and `6`. Both cores are online, `/sys/devices/system/cpu/online`
reads `0-7`, and the process's own `Cpus_allowed_list` reads `0-7`. Deterministic
over three runs.

### CORRECTED, same day: it is idleness, not permission

The first reading of this was that the X3 could not be targeted, and that
CLAUDE.md's advice to widen SPU affinity toward CPU7 could not be carried out.
**That was wrong.** The cause is Qualcomm `core_ctl` **pausing** a core: it stays
online but leaves the scheduler's active mask, and an affinity request naming
only paused CPUs is rejected.

Shown by loading the machine and repeating the identical command:

| state | `taskset 0x20` (CPU5) | `taskset 0x80` (CPU7) |
| --- | --- | --- |
| idle | `Invalid argument` | `Invalid argument` |
| eight busy loops running | **`Cpus_allowed_list: 5`** | **`Cpus_allowed_list: 7`** |

No cpuset explains it either: `top-app` is `cpus=[0-7]`, and so are `foreground`,
`restricted`, `camera-daemon` and the root set. Only `background`,
`system-background` (`0-2`) and `audio-app` (`1-2`) are narrower, and none of them
is what the emulator runs in.

**So the placement advice stands.** During emulation the machine is loaded, every
core is unpaused, and CPU7 is targetable.

**The methodological trap is the real finding: a light benchmark cannot measure
the prime core.** The benchmark is not heavy enough to bring the core back, the
pin fails, and the failure looks like a permission problem rather than an idle
one. `pin_to()` now loads the machine, retries, and re-checks that the pin
survives the load going away.

## SHUFB: our lowering uses the slower instruction, and it costs 2x

`shufb` is the most common operation in this title's compiled SPU corpus: **5,794**
of them, against 2,203 `fm` and 399 `fi`. The lowering emits `TBX2`.

`ns_per_op`, four independent operations per iteration for throughput, and a
serial chain that feeds each result back as the next index for latency:

| test | A715 (cpu3) | A710 (cpu6) | A510 (cpu0) |
| --- | --- | --- | --- |
| `tbl1_tp` | 0.179 | 0.179 | 0.503 |
| `tbl2_tp` | **0.178** | **0.183** | 1.300 |
| `tbx1_tp` | 0.186 | 0.178 | 1.255 |
| `tbx2_tp` | **0.377** | **0.388** | 2.517 |
| `tbl2_lat` | 1.427 | 1.432 | 5.577 |
| `tbx2_lat` | **2.165** | **2.158** | 7.553 |

**The claim taken from the vendor guide is confirmed, on the cluster that matters.**
On the A715 and the A710, where the SPU threads run, `TBX2` costs **2.1x the
throughput** and **1.5x the latency** of `TBL2`. At 2803 MHz that is about one
operation per cycle for `TBX2` against two for `TBL2`, which is the pipe
assignment the guide gives.

Two things worth noting beyond the headline. A second table is **free** for `TBL`
on the big cores: `tbl1_tp` and `tbl2_tp` are the same 0.178 ns. And the A510 is
not merely slower, it is differently slow: there a second table **triples** the
`TBL` cost, 0.503 to 1.300.

**This is an opportunity, not a defect.** `codegen.md` keeps `TBX2` because it is
correct: `TBX` leaves the destination byte alone where `TBL` writes zero, which is
what the SPU `SHUFB` selector semantics need. The measurement says what that
correctness costs, and it is 2x on the most common operation in the corpus. The
question it raises: at how many of the 5,794 sites is the selector known to be in
range, so `TBL2` would be correct? **Not yet answered, and sites are not
executions.**

## What a wait costs, and what it costs to be woken

| shape | ns per iteration |
| --- | --- |
| `yield` | **0.36** |
| `nop` | 0.36 |
| bare load | 0.36 |
| `isb` | **11.42** |
| armed `wfe` | **72,024** |

**`YIELD` is exactly a `nop` on this core**, measured rather than inferred: both
0.36 ns, and a bare load is the same. This project has asserted that for months
from the architecture manual; here it is on the silicon.

**`ISB` costs 11.42 ns, which is 32 times a `yield`.** That is the arithmetic
behind the **+23%** regression already recorded when `ISB` replaced `YIELD`: the
spin counts were hand-tuned around an instruction that costs nothing, and
substituting one that costs 32x more changed the shape of every tuned wait.

**An armed `WFE` parks for about 72 microseconds.** It is a real park, not a nop,
because this chip advertises `evtstrm` and the event stream wakes it. It is also
far too coarse to use as a general wait, and `FEAT_WFxT` is absent so it cannot
carry a timeout. That is why the futex path exists.

Wake latency, from the writer's store to the waiter observing it:

| delay before the wake | spin | futex |
| --- | --- | --- |
| 0 us | 448 ns | 11,965 ns |
| 50 us | 432 ns | 10,783 ns |
| 200 us | 424 ns | 9,413 ns |
| 1000 us | 474 ns | 12,521 ns |

**Parking through a futex costs about 10 microseconds of extra wake latency**
against roughly 0.44 microseconds for a spin, and it is flat across the delays
tested.

### What that says about the SPU self-loop park

The park built on 2026-08-13 turns a `BR`-to-self spin into a wait on `state`.
The spin costs 0.36 ns for each iteration and holds a core at full issue rate;
the profile puts about 20% of gameplay CPU in exactly those two instructions.

The trade is now sized: **about 10 us of added wake latency**. Against a 16.7 ms
frame at 60 fps that is **0.06% of a frame**, and it buys back a core that is
currently spinning. The park's default timeout should therefore be set well above
10 us, because a timeout near the wake cost pays the syscall repeatedly for
nothing.

**Still not measured:** how often that path wakes in a real title, which decides
whether 10 us happens once a frame or a thousand times.

## Non-temporal DMA: the copy itself gains about 3%

A710, `memcpy` against the `LDNP`/`STNP` kernel from `SPUThread.cpp`, with a
second thread thrashing 8 MB on another core:

| bytes | memcpy ns | NT ns | NT gain | with thrasher |
| --- | --- | --- | --- | --- |
| 1,024 | 18.3 | 16.9 | **+8.3%** | +7.6% |
| 4,096 | 58.5 | 54.7 | +7.0% | +1.0% |
| **16,384** | **215.2** | **208.7** | **+3.1%** | **+3.5%** |
| 65,536 | 1,291.1 | 1,303.8 | **-1.0%** | -1.9% |
| 262,144 | 7,977.1 | 7,683.7 | +3.8% | +0.8% |

At 16 KB, the size the comment at `SPUThread.cpp` names for Eternal Sonata's hot
SPU jobs, the non-temporal loop is **3.1% faster**, and 3.5% with a co-runner. At
64 KB it is slightly **slower**.

**This bounds the direct win and nothing more.** The theory behind the change was
never mainly about copy throughput; it was that a 16 KB copy evicts the working
set of the other five SPU threads. This benchmark measures the copy, not the
damage to the neighbours, so **the eviction benefit is still unmeasured**. What
the table does say is that nobody should expect the copy itself to be worth much.

## Both candidates were measured, and both came back null

Run later the same day, once the device came back. **Neither prepared change is
justified by its own experiment**, and one of them refutes an arithmetic
prediction made here from the isolated instruction costs above.

### SHUFB: TBL2 plus an OR is not faster than TBX2

The full sequences, `ns_per_shufb`, four independent chains:

| | `seq_tbx2_current` | `seq_tbl2_orr_candidate` |
| --- | --- | --- |
| A715 (cpu3) | 0.555 | **0.555** |
| A710 (cpu6) | 0.556 | **0.560** |
| A715, repeat | 0.559 | **0.555** |

**Identical, twice, in both directions of the noise.** And this ran in the same
invocation that measured `tbl2_tp` at 0.185 and `tbx2_tp` at 0.371, so the 2x gap
between the instructions is real *in the same run* that shows the sequence does
not care.

The prediction here was about 20% faster, from 0.179 + 0.377 against
0.179 + 0.178 + an ORR assumed to cost about 0.089. **That was wrong**, and it is
the `BCAX` failure again in a new costume: an isolated instruction cost that does
not survive being put in a sequence. Whatever the sequence is limited by, it is
not the TBX2's second table.

`debug.rpcsx.thor.shufb_tbl2_or` therefore stays **0**, and it should stay 0. The
equivalence proof remains valid and worth keeping; the reason to use it does not
exist.

### Non-temporal DMA: no measurable cost to a neighbour, so nothing to recover

The victim's retained rate at a 256 KB working set, one core copying 16 KB
repeatedly while another walks the set:

| run | victim / copier | beside `memcpy` | beside `LDNP`/`STNP` |
| --- | --- | --- | --- |
| first | 3 / 6 | **0.875** | 0.977 |
| reversed | 6 / 3 | 1.007 | 1.010 |
| repeat 1 | 3 / 6 | 0.994 | 0.999 |
| repeat 2 | 3 / 6 | 1.000 | 1.003 |

**The 0.875 did not reproduce.** It was written up here as a 10-point win before
the repeat was run, and three subsequent runs — one with the cores reversed and
two in the original orientation — put `memcpy` at 0.994 to 1.007. So `memcpy`
costs a cross-core neighbour nothing measurable, and the non-temporal copy has no
eviction to recover.

At a 4 MB working set the non-temporal arm was slightly **worse**, 0.946 against
0.960, which is the same size of wobble.

**What this does not test, and it is the case that matters.** The theory is about
six SPU threads sharing *fewer cores than there are threads*. This benchmark puts
the copier and the victim on **different** cores, which have private L1 and L2, so
only the shared level is exposed. Same-core contention, where a 16 KB copy really
does evict a co-tenant's lines out of the same L1, is **not measured here**.

So `debug.rpcsx.thor.dma_nontemporal` keeps its default of 0. What survives is the
3.1% on the copy itself, which is small and real, and an untested hypothesis about
same-core tenancy.

## RETRACTED: the park measurement below is void, and so is every arm on this scene

**A control run destroys it.** The same configuration, launched twice in a row
with nothing changed between them:

| run | ticks | frames | fps | ticks per frame |
| --- | --- | --- | --- | --- |
| control A | **185** | 1,750 | 29.2 | 0.106 |
| control B | **1,720** | 3,500 | 58.3 | 0.491 |

Nine times the CPU and twice the frames, from an identical config. Normalising to
ticks per frame does not save it either: 0.106 against 0.491 is still 4.6x.

Folklore's title screen is **not a stable workload**. It has phases — an attract
movie and a menu are not the same load — and a boot lands in whichever one it
lands in. Every arm below sampled a phase, not a setting.

**So the 14% frame-rate regression attributed to the park is withdrawn.** The
pairs that looked reproducible to 0.3% were two arms happening to catch the same
phase. The tell was there and was misread: the frame counts came in three
distinct clusters — 1,750, 3,000 and 3,500 — which is a workload changing, not a
setting changing.

The same voids the `movsb_threshold` arm run beside it, which landed on 6,817
ticks and 3,000 frames, indistinguishable from the park arms and for the same
reason.

**What a usable version of this needs**, before any arm on a title is believed
again: a scene whose content is fixed for the whole window, or a normaliser the
change provably cannot touch — the approach `lv2-ppu-spin.md` used when it
divided by `spu_getllar_retry` and took a 59% spread down to 1.1%. A control pair
with identical settings must be run first, and it must agree with itself.

## The SPU self-loop park makes it worse, on a real title, reproducibly

This is the item CLAUDE.md calls "the one thing left to build", worth about 20% of
gameplay CPU. It was measured on Folklore, booted to its title screen from a warm
PPU cache, letting the run settle 20 seconds after the first frame and then
sampling a 60-second window. CPU is `utime + stime` from `/proc/<pid>/stat`;
frames come from the RSX auditor's own `on_frame_end call #N` counter, so both
numbers are the emulator's, not a sampler's.

| `debug.rpcsx.thor.spu_selfloop_park` | cores | frames in 60 s | fps |
| --- | --- | --- | --- |
| **0 (spin, the default)** | **0.278** | 3,500 | **58.3** |
| 0, repeat | 0.283 | 3,500 | 58.3 |
| **100 us** | **1.135** | 3,000 | **50.0** |
| 100 us, repeat | 1.136 | 3,000 | 50.0 |
| 1000 us | 1.135 | 3,000 | 50.0 |

**The park costs four times the CPU and 14% of the frame rate.** Both arms repeat
to within 0.3%, and raising the timeout tenfold changes nothing, so the cost is
per-entry rather than per-wait. The `BR`-to-self blocks are evidently entered far
more often than "an idle loop" suggests, and each entry now pays a futex syscall
where it used to pay the 0.36 ns that a `yield` costs on this core.

**So the gate stays 0, and the design is wrong rather than the timeout.** A park
that is entered this often cannot be made to pay by tuning how long it sleeps. If
this is revisited, the question to answer first is how often that site is reached
per frame — the counters in `thor_spu_selfloop_park.h` are written on entry
precisely so that can be read.

### And the first two readings of this were both wrong

The first pair sampled too early, before SPU compilation had finished: 1.134
cores for the spin arm and 0.031 for the park arm, which reads as a **97%
saving**. It was written up as one here for a few minutes. The settled method,
which waits for frames and then lets the run stabilise, inverts the sign entirely.

Neither reading was noise in the arms; both were noise in *when* the arms were
sampled. `frames in 60 s` is what caught it, because a CPU number alone cannot
tell a thread that stopped spinning from an emulator that stopped working.

## The memory hierarchy, so future theories have numbers

A710 (cpu6), shuffled pointer chase, so the prefetcher cannot flatter it:

| working set | latency | reading |
| --- | --- | --- |
| 16 KB, 32 KB | 1.43 ns | L1 |
| 64 KB - 256 KB | 4.16 - 4.56 ns | L2 |
| 512 KB - 4 MB | 5.49 - 6.04 ns | L2 into L3 |
| 8 MB | 12.71 ns | L3 |
| 16 MB | 48.99 ns | DRAM |

**The number that matters for the DMA argument: a 16 KB transfer touches 32 KB
across source and destination, which is exactly the size at which latency leaves
the 1.43 ns level.** So a single 16 KB DMA does turn over L1 entirely. The
eviction the non-temporal change targets is real; what remains unmeasured is what
it costs the threads that lose their lines.

## What to do next

1. ~~**Ask whether the app can pin where a shell process cannot.**~~ **Answered
   the same day, and the premise was wrong.** It is `core_ctl` pausing an idle
   core, not a permission boundary; load the machine and the pin succeeds. See the
   correction above.
2. **The `SHUFB` fallback now has a replacement to measure, not just a cost.**
   `TBX2(x, a, b, idx)` and `TBL2(a, b, idx) | x` were proved identical over all
   256 selector bytes, for both index forms. It ships behind
   `debug.rpcsx.thor.shufb_tbl2_or`, **default 0**, because trading one `TBX2` for
   a `TBL2` plus an `ORR` only wins if the `ORR` costs less than the 0.199 ns that
   `TBX2` adds. `thor_bench shufb` times both full sequences as
   `seq_tbx2_current` and `seq_tbl2_orr_candidate`. **Run those two first.**
3. **Set the self-loop park timeout from the 10 us wake cost**, then measure how
   often it parks in a real title. A timeout near the wake cost pays the syscall
   repeatedly for nothing.
4. **`thor_bench evict` now measures the eviction rather than the copy.** A victim
   thread's pointer-chase rate is the metric, across three arms: alone, beside
   `memcpy`, beside `LDNP`/`STNP`, at a 256 KB working set and a 4 MB one. If the
   non-temporal hint is worth anything to neighbours, the third arm retains more
   of the baseline. **Unrun.**
5. **Reach, for both candidates.** 5,794 `SHUFB` and 399 `FI` are compiled sites,
   not executions, and `TBX2` is only the fallback path rather than every `SHUFB`.
   Nothing here says how often either runs.
