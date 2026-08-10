# What the SPU JIT actually emits

Every previous statement in this repo about JIT codegen came from reading
`SPULLVMRecompiler.cpp`. This is the first audit of the **machine code it
produces**: the whole on-device native cache for Folklore, pulled and
disassembled — **1,185 objects, 4,740 functions, 509,468 instructions.**

```sh
adb pull .../cache/BLUS30161/ppu-*/spu-native-v2
ls *.obj | xargs -n 40 llvm-objdump -d > jit-all.asm
```

`xargs -n 40` matters: a single `llvm-objdump -d *.obj` over all 1,185 files
produced **zero** instructions and silently reported every count as 0. Checking
the instruction total before reading any count is what caught it.

## The lowerings, verified in machine code rather than in source

| instruction | count | note |
| --- | --- | --- |
| `udot` | **1,661** | the video's headline optimization, in the emitted code |
| `sdot` | 31 | |
| `tbl` | 5,916 | all but one are the **1-table** form |
| `uaba` | 4,503 | |
| `addv` | 2,031 | |
| `tbx` | 1,455 | 812 two-table (`TBX2`, the `SHUFB` path) + 643 one-table |
| `uabd` | 910 | |
| `bcax` | 327 | |
| `ummla` / `smmla` | 17 / 13 | i8mm, live but rare |
| `cnt` | 6 | |
| `eor3`, `urhadd`, `sqadd`, `uqadd` | **0** | |

**`udot` at 1,661 settles a claim this repo has been making from the flag.**
CLAUDE.md said the SDOT/UDOT work was "already here", citing call sites, the
`HWCAP_ASIMDDP` gate and a log line reading `dotprod=true`. All of that proves the
path is *enabled*. This proves it is *taken*.

**The zeros are not defects.** `urhadd` (SPU `AVGB`) and `sqadd`/`uqadd`
(saturating arithmetic) are recorded elsewhere as clean lowerings, and they are —
they simply never fire, because this title's SPU code does not use those opcodes.
`sqadd` in particular belongs to VMX on the **PPU** and would never appear in an
SPU cache. A lowering that is correct and never reached is worth exactly nothing,
and only the emitted code can tell the two apart.

### A sampling mistake worth recording

The first pass disassembled the **40 largest objects** on the reasoning that they
hold most of the code. In that sample `sdot` and `udot` were **zero**, and the
draft conclusion was that the video's optimization never actually fires — a
direct contradiction of CLAUDE.md, and wrong. Corpus-wide, `udot` is 1,661.

Size is not importance. The dot-product paths live in many small objects, not the
few big ones. **Sample the whole corpus or state that the sample is biased**;
"the biggest files" is a bias, not a shortcut.

## The largest statically visible cost is stack traffic

| base register | memory ops |
| --- | --- |
| `x19` (SPU thread state) | 59,643 |
| **`sp`** | **51,474** |
| `x9` | 13,390 |
| `x20` (local store) | 10,927 |

**`sp` is the second hottest base register in the emitted code**, and those 51,474
accesses are **10.1% of every instruction the JIT emits** — 21,706 of them
128-bit `q` register spills, 12,777 scalar, 16,981 paired.

They are genuine spills, confirmed by reading the code rather than by counting:

```
290: str q3, [sp, #0x300]
294: str q3, [sp, #0x430]
2a0: ldr q3, [sp, #0x430]
```

The same register stored to two slots and reloaded. This is the
`ldsetal` trap checked for and not found: prologue and epilogue patterns
(`stp …[sp,#-N]!`, `ldp …[sp],#N`) number **zero**, so none of this is frame
setup.

**Whether it is reducible is unknown, and the structural odds are poor.** The SPU
has 128 architectural 128-bit registers and AArch64 has 32 — a 4:1 deficit that no
allocator can wish away. Worth noting in the other direction: x86-64 has 16, so
this backend starts with twice the registers the emulator was originally written
for, and still spills this much.

## The code is otherwise good

A representative block, chosen by reading rather than by metric:

```
14: ldp  q1, q3, [x9, #0x20]      // paired 128-bit local-store loads
20: uabd v1.4s, v0.4s, v1.4s
3c: uaba v1.4s, v7.4s, v8.4s      // accumulate, not a separate add
```

Paired loads, a dedicated absolute-difference-accumulate, no redundant moves
between them. This is what the SPU checksum path is supposed to look like, and it
is what the manual-driven audit predicted. That audit was right about instruction
selection; it was looking at the wrong question.

## Two candidates, and why only one is worth costing

**`TBL` → `TBX`, 5,915 sites.** The vendored Cortex-X3 guide puts 1-table `TBL` on
`V01` at throughput 2, and `TBX` on all four `V` pipes at throughput 4 — the same
latency, double the issue rate. The two differ only in out-of-range index
handling: `TBL` zeroes, `TBX` leaves the destination unchanged. Where the SPU path
masks its indices in range, they are interchangeable and `TBX` is strictly better.

**Predicted magnitude, before any work:** 5,915 of 509,468 instructions is
**1.16%** of emitted code, and halving their issue cost saves at most **~0.6% of
issue slots** — and only if that code is hot. By this repo's own checklist that
**fails the magnitude test** and should not be attempted on this evidence. It
becomes interesting only if a gameplay profile puts a `TBL`-dense block at the top.
Recorded so nobody re-derives it.

**`rev64`, 18,629 occurrences, 3.66% of all instructions.** The big-endian PS3 to
little-endian host tax, and the single most distinctive instruction in the corpus
after the arithmetic. Bigger than the `TBL` opportunity by 3x. Unexamined: no
attempt has been made here to work out how much of it is redundant — pairs that
cancel, or values swapped on load and swapped straight back on store.

## What this audit cannot answer

**Everything here is weighted by compiled bytes, not by execution.** This repo
already records that trap once, when 3,946 `ldsetal` looked alarming and turned out
to be one per function entry. A histogram of the cache says what was *compiled*
for Folklore; it cannot say what runs, and the lv2 result showed the same code can
shift by an order of magnitude between a title screen and gameplay.

The 10.1% spill figure, the 3.66% `rev64` figure and the `TBL` count are all real
and all unweighted. **The next step for any of them is a gameplay profile with
symbols**, which would say which of these 4,740 functions are hot — and that is
the one instrument this project still does not have.

---

# The gameplay profile, and what it says about all of the above

Eternal Sonata, gameplay, 150 s settle, **119,662 samples, 0 lost, 0 pauses**,
symbolized against the matching unstripped library by build ID. This is the
instrument the whole audit was missing.

**Where gameplay cycles go, by shared object:**

| | share |
| --- | --- |
| **`unknown` (JIT-generated code)** | **47.88%** |
| `librpcsx-android.so` | 34.65% |
| kernel | 11.80% |
| `libc` | 2.95% |
| Turnip (`libvulkan_freedreno`) | 2.23% |

**Almost half of gameplay CPU is in code the JIT emits at runtime**, in anonymous
executable mappings that no symbolizer can name. That single line justifies the
static audit above: a disassembly of the native cache is the *only* lens on 48%
of the workload, and it is now pointed at the right body of code even though it
is unweighted.

**Top named symbols:**

| symbol | share |
| --- | --- |
| `spu_thread::process_mfc_cmd()` | **20.13%** |
| `unknown[+7557176b20]` | 15.51% |
| kernel | 7.67% |
| `vm::writer_lock::writer_lock(...)` | 4.49% |
| `unknown[+7557176b24]` | 3.24% |
| `memcpy_opt` | 2.03% |
| `vk::wait_for_event` | 1.82% |
| `vm::passive_lock(cpu_thread&)` | 1.73% |

## Three things this settles

**1. The lv2 waits are gone.** `sys_event_queue_receive` and
`_sys_lwcond_queue_wait` were **73.9% of the title screen** and do not reach 1%
here. The workload-dependence recorded in `lv2-ppu-spin.md` is now measured from
both ends rather than inferred from a CPU delta, and it is the strongest possible
warning against quoting that 73.9% without its scene.

**2. `spu_thread::process_mfc_cmd()` is the biggest named function in the
emulator, at 20.13%** — roughly 58% of all time inside the library. It is the SPU
DMA command path. **This project has never looked at it.** Every session so far
went to reservations, spin loops, instruction lowerings and the GPU; the largest
named consumer under real load was never on the list, because the list was built
from code reading and counters rather than from a profile.

**3. `vm::writer_lock` 4.49% + `vm::passive_lock` 1.73% = 6.2% in vm range
locking** — larger than everything the `busy_wait` inventory identified as
actionable, and consistent with the earlier wait-profiler note that
`vm_passive_lock` was 17.5% of *spin*.

## One observation deliberately not interpreted

`unknown[+7557176b20]` at **15.51%** and `unknown[+7557176b24]` at 3.24% are two
addresses **four bytes apart** — a single instruction pair holding 18.75% of all
gameplay cycles. That is either a very hot two-instruction loop in JIT code or a
sampling artifact concentrating skid on one PC.

It is not diagnosed here, because this repo has an explicit record of what
confident address attribution costs: ~31% of samples were once attributed to
`get_thor_pause_mode` purely because it was the nearest preceding symbol in a
partly-stripped binary. An unnamed address in an anonymous JIT mapping deserves
more suspicion, not less. Identifying it needs the JIT to emit a symbol map
(`perf-<pid>.map`), which it does not currently do.

## What the next session should do

In order, and each now justified by a number rather than a hunch:

1. **`process_mfc_cmd`** — 20.13%, never examined.
2. **A JIT symbol map** — 48% of the workload is unnameable until one exists;
   everything about JIT codegen is guesswork until then, including the two hot
   addresses above and whether the 10.1% spill figure lands in hot blocks.
3. **vm range locking** — 6.2%, and a spin site already measured at 17.5% of spin.

And the general rule this profile earns: **the title screen and gameplay share
almost no hot code.** Any conclusion here must name its workload.

---

# The 18.75% is one two-instruction spin loop, and now it has a name

The JIT symbol map exists now, so the unnamed hot addresses could be resolved.

**The mechanism was already in the tree and disabled.** `jit_announce()` is called
from both recompiler paths (`JITLLVM.cpp:352`, `JIT.h:492`) and its body was
`#ifdef __linux__` wrapped around `#if 0`. Two changes made it usable here, behind
`debug.rpcsx.thor.jit_perf_map` (off by default — it writes a line per compiled
function, and this run produced **174,453** of them):

* **Path.** `/tmp` does not exist on Android and an app cannot write
  `/data/local/tmp`, which is shell-owned. It writes to `fs::get_cache_dir()`
  instead, and shell copies it to `/data/local/tmp/perf-<pid>.map` afterwards.
* **Lifetime.** The original deleted the map in its destructor — right for a live
  `perf record`, exactly wrong when the file is read after the run.

One bug worth keeping: opening the file on first call produced a bare
`perf-<pid>.map` with **no directory**, because `fs::get_cache_dir()` is still
empty that early in boot and the app's CWD is `/`. The log line printed the path
with nothing in front of it, which is the only reason it was caught. It now opens
lazily and retries until the cache dir exists, and logs whether the open
*succeeded* rather than that it was attempted.

## The resolution

120,782 samples, 0 lost. The two hot addresses fall inside a single symbol:

```
7555f76c40 -> INSIDE __spu-cx00cc4   (start 7555f76c20, size 0x40, offset +0x20)
7555f76c44 -> INSIDE __spu-cx00cc4   (offset +0x24)
```

**A 64-byte SPU block.** Disassembling it from the cache, offsets +0x20 and +0x24
are these two instructions:

```
80:  ldr  w8, [x19, #0x14]     ; spu_thread::state
84:  cbz  w8, 0x80             ; if zero, branch back to 0x80
88:  ...                       ; else: save pc, call spu_test_state, b 0x80
```

**An unconditional two-instruction spin on `spu_thread::state`, with no `pause`,
no `yield`, no `WFE`, and no backoff of any kind** — a load and a branch, issuing
at full rate. Roughly **20% of all gameplay CPU** (16.49% + 3.34%) is these two
instructions.

The guest SPU program at `0xcc4` is itself a wait loop with an empty body, so
`check_state()` (`SPULLVMRecompiler.cpp:1124`) is all that survives optimisation:
its `state == 0` fast path becomes the back-edge, and LLVM correctly reduces the
whole guest loop to a poll. The recompiler is not doing anything wrong. It is
faithfully reproducing a guest busy-wait, on a host that has a much better
instruction for the job.

## Why this is the largest lead in the project

It is the same defect as the lv2 waits — a spin in front of something that arrives
much later — but this one **survives into gameplay**, which is exactly where the
lv2 finding evaporated. And it is a better WFE candidate than anything examined so
far: the loop waits on **one word in memory, written by another thread**, which is
precisely what `LDAXR` + `WFE` is for. `rx::spin_on_cacheline_once()` in
`rx/asm.hpp` already implements that sequence and is already used elsewhere here.

**Predicted magnitude:** up to ~20% of gameplay CPU and a proportional power
saving, with no frame-rate cost, because the thread is doing no work while it
spins. That is an order of magnitude larger than anything else found.

**What would falsify it:** if `state` changes often enough that the loop is a
short poll rather than a park, WFE adds wakeup latency for no saving — the sample
distribution argues against that (the samples sit almost entirely on the two spin
instructions and not on the `spu_test_state` path below them, so the loop rarely
exits), but that is an inference, not a measurement.

**Not attempted here.** It is a codegen change to `check_state`, the recompiler
would need to know the loop body is empty, and the correct shape is not obvious.
It deserves its own session with the profile re-run either side.

## One correction

The static audit above says "the native cache for Folklore". It is **Eternal
Sonata** — `BLUS30161` is Eternal Sonata's title ID, not Folklore's, which is
`BCUS98147`. The disassembly and the gameplay profile are therefore the same
title, which makes them directly comparable; the label was wrong, not the data.

---

# `process_mfc_cmd` is 20% of gameplay, and half of it is `sched_yield`

The biggest named function in the emulator, never examined by this project.
Breaking its subtree down from the same profile (23,412 samples in it alone):

```
33.53% children / 20.46% self   spu_thread::process_mfc_cmd()   [SPU thread 0x3000100]
  |--17.39%-- sched_yield
  |            --93.81%-- [kernel scheduler]
  |--16.91%-- spu_thread::do_putllc(spu_mfc_cmd const&)
```

**Roughly a third of it is `sched_yield`, and 94% of that cost is inside the
kernel** — this is a syscall storm, not user-space work. The other third is
`do_putllc`, the SPU reservation *write*. Together they say the hot path is
**reservation contention**, resolved by yielding to the OS.

## The shape, at every reservation site

`SPUThread.cpp:5268` and `:5285` (PUTLLUC), `:3709` (DMA reservation), and
siblings all share it:

```cpp
else if (k < 15) { thor_wait::profiled_busy_wait(site, 500); }  // 15 x 26 us = 390 us
else             { std::this_thread::yield(); }                 // then forever
```

A bounded spin — ~390 µs on this chip's 19.2 MHz timer — followed by an
**unbounded `std::this_thread::yield()` loop with no sleep and no backoff.** Once
the retry count is exceeded the thread calls `sched_yield` on every iteration for
as long as contention lasts.

Three costs, all of which the profile shows:

* **A syscall per iteration.** 94% of the measured `sched_yield` cost is kernel
  time, not the call itself.
* **The thread stays runnable.** `sched_yield` does not sleep — it re-queues. The
  scheduler keeps the thread resident and the cluster clocked up, which is the
  opposite of what is wanted on a handheld.
* **No notifier.** Nothing wakes this thread when the reservation actually
  clears; it discovers it by asking again.

## Why this is the same defect in a third costume

This project has now found the identical shape three times, at three layers:

| layer | wait | share |
| --- | --- | --- |
| lv2 syscalls | 50 x `busy_wait(500)` then futex | 73.9% of a title screen, ~0 in gameplay |
| SPU JIT | `ldr`/`cbz` with no pause at all | ~20% of gameplay |
| SPU MFC | 15 x `busy_wait(500)` then `sched_yield` forever | ~7% of gameplay |

Each spins in front of something that arrives much later. The lv2 one was fixed
because it had a working futex underneath it. **This one has no sleep to fall
through to at all** — the fallback is an unbounded yield, which is a spin wearing
a syscall.

## Not changed, and what it would take

Unmeasured, and the fix is not a one-line swap. A correct version needs a real
wait with a notifier on the reservation address — the machinery
`vm::reservation_notifier` already provides and the lv2 path already uses. The
falsification is the same as always: reservation waits are latency-critical, so
p95 frame time decides it, and `dumpsys SurfaceFlinger --latency` now measures
that reliably.

**Predicted magnitude:** `sched_yield` is 17.39% of a function that is 20.13% of
gameplay, so ~3.5% of all cycles are in the syscall path, plus its share of the
11.80% total kernel time. Smaller than the SPU spin loop above, larger than
anything the `busy_wait` inventory found, and it is **power-shaped rather than
throughput-shaped**: a thread kept runnable holds the cluster at a high operating
point whether or not it retires useful work.

---

# `vm::writer_lock`: six threads, 1.04 ms each, then yield forever

`vm::writer_lock` is 4.49% of total gameplay cycles, but the per-thread view is
what matters: **six SPU threads are inside it at once**, each spending 15–19% of
its own time there, and **~95% of that is self time** — spinning in acquisition,
not in callees.

```
19.20% children / 18.21% self   SPU[0x3000100]
18.69% / 17.44%                 SPU[0x1000100]
17.77% / 17.56%                 SPU[0x4000100]
16.91% / 16.50%                 SPU[0x0000100]
15.97% / 14.96%                 SPU[0x0000200]
15.90% / 15.34%                 SPU[0x2000100]
```

`vm.cpp:698`:

```cpp
if (i < 100) { ...prefetch...; profiled_busy_wait(vm_writer_lock, 200); }
else         { std::this_thread::yield(); }
```

**100 iterations at 200 ticks — 10.4 µs each, 1.04 ms total — then an unbounded
yield loop.** Six threads doing that simultaneously against one range-lock bitmap
is real contention, not a rare slow path.

# The synthesis: every wait in this emulator spins, and none of them park

Four layers, found independently, all the same shape:

| layer | bounded spin | fallback | share of gameplay |
| --- | --- | --- | --- |
| lv2 syscalls | 50 x 26 µs = **1.3 ms** | futex (a real sleep) | 73.9% of a title screen, ~0 in gameplay — **fixed** |
| SPU JIT wait | none — bare `ldr`/`cbz` | **none** | **~20%** |
| SPU MFC reservation | 15 x 26 µs = **390 µs** | `sched_yield` forever | ~7% |
| `vm::writer_lock` | 100 x 10.4 µs = **1.04 ms** | `sched_yield` forever | 6.2%, six threads |

**Only one of the four has a real sleep underneath it, and that is the one that
was fixable.** The other three end in either nothing or an unbounded
`sched_yield`, which does not sleep — it re-queues, keeps the thread runnable, and
holds the cluster at a high operating point regardless of whether any work is
retired. On a plugged-in desktop that is close to free. On a handheld it is the
dominant power behaviour.

That is the answer to "why is this emulator hot" at a level no instruction table
could reach: **roughly a third of gameplay CPU is threads waiting, at full issue
rate, for something that has not happened yet.**

## Why the manual sweep could never have found this

Twelve predictions from the vendored manuals, twelve refuted. The manuals describe
what an instruction costs. Every finding above is about **how long a wait waits**
and **what it does while waiting** — neither of which is an instruction property,
and both of which are invisible to any amount of reading. Two profiles, a title
screen and a gameplay scene, found all four.

The instruction-level audit was not wasted: it confirmed the lowerings, closed
sse2neon, and turned up the empty `mov_rdata` branch that made two titles
unbootable. But it answered "is this code well-formed" when the question that
mattered was "is this code doing anything".

## Order of attack, by measured size

1. **SPU JIT spin, ~20%** — no pause at all, and the cleanest `WFE` candidate in
   the codebase. Needs a codegen change in `check_state`.
2. **SPU MFC reservation, ~7%** — needs a real wait on the reservation notifier
   `vm::` already provides.
3. **`vm::writer_lock`, 6.2%** — same, and the six-way contention suggests the
   lock granularity is worth questioning before the wait shape is.

All three are latency-critical, so p95 frame time decides each, and
`dumpsys SurfaceFlinger --latency` measures that reliably now.

---

# Handover: the fix for the 20% loop may already exist and be missing this block

Before writing any codegen, one thing has to be checked, because it would change
the whole approach.

**The recompiler already turns channel-poll loops into blocking waits.**
`SPULLVMRecompiler.cpp:4534` handles `inst_attr::rchcnt_loop` by emitting
`wait_rchcnt(...)` / `wait_spu_inbox` — real blocking waits — instead of a poll,
for `SPU_WrOutMbox`, `SPU_WrOutIntrMbox`, `SPU_RdSigNotify1/2` and `SPU_RdInMbox`.
That attribute is produced by a large, careful analysis in
`SPUCommonRecompiler.cpp` (`rchcnt_loop_t`, ~15 rejection causes, applied at
`:8477`).

So the mechanism that fixes exactly this class of spin **is present and live**.
The hot block at `0xcc4` is not getting it. Two possibilities, and they lead to
very different work:

1. **The pattern matcher rejected it.** There is a diagnostic for precisely this,
   already in the tree: `spu_pattern_diagnostics_enabled()` logs
   `"Channel Loop Pattern Detected!"` on success and `"Channel loop error!"` on
   failure, with `read_pc`, `branch_pc` and the function hash. If `0xcc4` shows up
   as a rejected candidate, the fix is in the matcher — far smaller and safer than
   new codegen.
2. **It is not a channel poll at all**, in which case it is a different wait
   (a `state` poll with an empty body) and needs its own handling.

**Run the diagnostic before writing anything.** This project's own record is that
the expensive mistakes came from building before establishing reach — and it has
now twice found the needed mechanism already present and simply not reached
(`mov_rdata`'s empty branch, `jit_announce`'s `#if 0`). A third instance is more
likely than not.

## What is done and what is not

Done and shipped: the lv2 spin default, the `busy_wait` inventory, the JIT perf
map, the emitted-code audit, and the profiles that located all of it.

**Not done, and deliberately not started:** the three fixes above — the SPU JIT
spin park (~20%), the MFC reservation wait (~7%), and `vm::writer_lock` (6.2%).
Each is a real change to a latency-critical path, each needs its own A/B with p95
frame time, and starting three of them at once is how unverified changes get
shipped. They are fully specified here: mechanism, measured size, predicted
magnitude, falsification, and the confound to check.

The one on `vm::writer_lock` should begin by questioning **lock granularity**, not
wait shape — six SPU threads contending on one range-lock bitmap is a design
signal, and making the wait cheaper would hide it rather than fix it.

## Diagnostic run: `0xcc4` is not a channel poll

`spu_pattern_diagnostics_enabled()` is gated on `g_cfg.core.spu_debug` on Android,
so this needed a `config.yml` edit rather than a property. Enabled, booted Eternal
Sonata, restored the config and verified the byte count matched (8012) — the file
is rewritten on exit, and leaving `SPU Debug: true` would have slowed every
subsequent run.

Result:

```
Channel Loop Pattern Detected! (read_pc=0xa7c, branch_pc=0xa80, branch_target=0xa7c)
detected: 1     errors: 0     mentions of 0xcc4: 0
```

**One pattern detected, no rejections, and `0xcc4` never appears.** So the hot
block was never a channel-loop candidate — it is not a `RDCH`/`RCHCNT` poll, and
the matcher has not rejected it either. Possibility 1 is eliminated: **there is no
matcher tweak that covers this.**

That settles the shape of the work. The `0xcc4` loop waits on `spu_thread::state`
with an empty body, which is a different idiom from a channel poll, and it needs
its own handling — a real codegen change, as originally feared, not a cheap fix.

Worth noting the cost of *not* checking: the existing `rchcnt_loop` machinery is
elaborate enough that assuming it applied would have sent a session into the
matcher for nothing. One boot and no build ruled it out.

## The insertion point, located

`SPULLVMRecompiler.cpp:9874`, `BR`:

```cpp
const u32 target = spu_branch_target(m_pos, op.i16);

if (target != m_pos + 4)
{
    m_block->block_end = m_ir->GetInsertBlock();
    m_ir->CreateBr(add_block(target));
}
```

There is **no case for `target == m_pos`** — a branch to itself. That is exactly
the `0xcc4` block: the guest pc never changes (the emitted code computes
`w20 = pc & 0x3fffc` once, outside the loop), so it is an unconditional infinite
loop whose only body is the `check_state` LLVM leaves behind.

So the change is narrow and its trigger is trivially detectable — `target ==
m_pos` in `BR`, no dataflow analysis needed, unlike the `rchcnt_loop` matcher.

**Design.** Emit a call to a blocking helper instead of the back-edge:

```cpp
// guest is in an unconditional self-loop; nothing can change except state
static void spu_wait_state(spu_thread* _spu)
{
    while (!_spu->state)
        thread_ctrl::wait_on(_spu->state, 0, timeout_ns);
}
```

**Two hazards that decide whether this is safe, and neither is settled:**

1. **Every writer of `state` must notify.** If any path sets a `cpu_flag` without
   a notify, the thread sleeps until the timeout instead of waking promptly. A
   bounded timeout makes that a latency bug rather than a hang, which is why the
   timeout is not optional.
2. **`BR` to self is also how a guest deadlock looks.** Today it burns a core and
   is visible in a profile; parked, it becomes silent. That is better behaviour and
   worse diagnostics, and this project has spent whole sessions on hangs. Whatever
   ships should keep a counter or a log at the park.

**Gate it** (`debug.rpcsx.thor.spu_selfloop_park`), default off, and A/B with p95
frame time either side — the park changes wakeup latency for any SPU thread that
uses a self-loop as a short wait rather than a long one.

**Not implemented.** The analysis is done and the site is exact, but writing this,
proving `state` notification is complete, building and running the A/B is more
than remains in this session, and a half-written codegen change to the SPU
recompiler is precisely the thing this repo has the most scar tissue about. The
same applies to the MFC reservation wait, whose sites are already named at
`SPUThread.cpp:5268`, `:5285` and `:3709`.

---

# Six SPU threads are pinned to two cores

The gameplay profile shows **six concurrent SPU threads** — `SPU[0x0000100]`,
`[0x0000200]`, `[0x1000100]`, `[0x2000100]`, `[0x3000100]`, `[0x4000100]` — which
matches `Max SPURS Threads: 6` in the profile config.

The affinity in that same config:

```
CPU0: General   CPU1: General   CPU2: General   CPU3: General
CPU4: PPU
CPU5: SPU       CPU6: SPU
CPU7: RSX
```

**Six SPU threads, two cores.** A 3:1 oversubscription, and CPU5/CPU6 are the
A710 pair at 2707 MHz — not the X3, which is handed to RSX while
`Multithreaded RSX: false` and the entire Turnip driver measures 2.23% of CPU.

## This reframes all three spin findings

Spinning is wasteful on an idle core. **On an oversubscribed core it is
actively serialising.** A thread spinning 1.04 ms in `vm::writer_lock` while
occupying one of only two SPU cores may be denying the core to the very thread
that would release the lock — a textbook convoy. The same applies to the 390 µs
MFC spin and to the `0xcc4` loop that burns a core doing nothing.

That would explain, without any of the codegen work, why `sched_yield` is a third
of `process_mfc_cmd` and why all six threads pile into `vm::writer_lock`
simultaneously: they are not just contending for a lock, they are contending for
**two cores**.

**This is testable without writing any code**, which makes it the cheapest
outstanding experiment by a wide margin. Change `Affinity` to give SPU more cores
(CPU3–CPU6, or include CPU7 given RSX is single-threaded and cheap) and re-run the
same p95 + CPU harness.

## And `SPU loop detection: false`

The same config carries `SPU loop detection: false`. Upstream uses that setting to
recognise SPU idle loops and yield instead of spinning — which is, on the face of
it, aimed at exactly the `0xcc4` behaviour. It has never been tried here.

Two config-only experiments, both zero-build:

| change | hypothesis |
| --- | --- |
| `Affinity` SPU → CPU3–6 (or +CPU7) | the spins are convoying on 2 cores, not merely wasting them |
| `SPU loop detection: true` | the 20% self-loop is already handled upstream by a setting we have off |

**Both must be run the same way as everything else here:** p95 frame time from
`dumpsys SurfaceFlinger --latency`, CPU from `/proc/<pid>/stat`, alternating arms,
and `config.yml` restored with a verified byte count afterwards — it is rewritten
on exit.

Neither is measured yet. They are recorded here because they cost one boot each
and could make a codegen change unnecessary, which is the order this project keeps
learning to work in: establish what is reachable and configurable before writing
anything.
