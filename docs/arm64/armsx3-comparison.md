# ARMSX3 compared, and what it says about our fork

[ARMSX3](https://github.com/ARMSX2/ARMSX3) is a proof-of-concept RPCS3 port for
Android from the ARMSX2 team, public since ~2026-08-09, advertising "ARM64-focused
optimizations". Same lineage as this fork, same target silicon — their Skate 3
figure of ~20–30 fps is on a Snapdragon 8 Gen 2, the Thor's exact chip.

> **Read the second pass first.** This document has two dated parts. The part below
> compares their tree of 2026-08-10. [The second pass](#second-pass-2026-08-13)
> compares their tree of 2026-08-12, and **it retracts two claims made here**: they
> reverted the thread scheduler mode and the GETLLAR busy-wait percentage that this
> page cites as their advantage. Their own measurements caused both reverts.
> [The third pass](#third-pass-2026-08-20) compares their tree of 2026-08-20. It
> records what was ported, and it shows this tree ahead of upstream on the ARM64
> float-to-int saturation fix.

**Method matters here.** The comparison downloaded the ARMSX3 tree *and* upstream
`RPCS3/rpcs3` master and diffed them: **only 133 files differ.** That diff is what
separates what ARMSX3 wrote from what they inherited, and without it every
"they have X" claim would be unattributable. Every absence below is verified
against a local snapshot, not a failed path lookup.

## Scoreboard

| area | ARMSX3 | us |
| --- | --- | --- |
| lv2 wait spin loops | 9 sites, N=50 (N=40 in `sys_mutex`), **byte-identical to upstream** | **fixed** — `lv2_spin=0` default |
| SPU reservation `sched_yield` | stock upstream, no sleep or notifier | unfixed |
| `pause()` on AArch64 | `isb` (inherited) | `yield`, chosen after measuring `isb` at **+23%** here |
| WFE parking | exists in `util/asm.hpp` (upstream), wired to **4 GPU call sites only** | wired into the GETLLAR wait via `__arm64_monitor_wait` |
| DMA copy threshold | upstream `umax` → memcpy branch **dead** | `1024` → **13.8% faster** (measured) |
| SPU checksum `UABA` collision | **fixed** — pairs sum | **fixed 2026-08-10, was present** (inherited from upstream) |
| `BufferUtils.cpp` NEON | `copy_data_swap_u32_neon`, theirs | **ported 2026-08-10**, unmeasured |
| ARM AES | none anywhere | wired, 19–22x on the primitive |
| LLVM JIT CPU | host-detected (was pinned to `cortex-a34`) | pinned `cortex-a78` |
| big.LITTLE affinity | `cpu_capacity` sysfs + `thread_scheduler_mode::alt` | affinity table **inert** under OS scheduler mode |

## Where we are ahead

**The wait/spin problem is untouched in their tree.** Items 1, 5 and 6 are stock
upstream — the eight lv2 files diff clean against RPCS3, and the SPU reservation
retries still end in unbounded `std::this_thread::yield()`. The WFE machinery they
ship is upstream's `spin_on_cacheline_once`, wired only to `GLGSRender.h`,
`nv406e.cpp` and two sites in `VKGSRenderTypes.hpp` — **zero uses in lv2, SPU or
PPU.** So the thing measured here as roughly a third of gameplay CPU is as
unparked in ARMSX3 as in stock RPCS3.

**The DMA threshold is a real 13.8% we hold over both of them** — see the
correction in [`busy-wait-inventory.md`](busy-wait-inventory.md). Upstream's
`umax` makes the `memcpy` branch dead code.

**ARM AES.** They have none; `vaese` and `__ARM_FEATURE_AES` appear nowhere in
their `Crypto/`.

## The one correctness bug in the diff, and we had it

**The ARM64 SPU block-verification checksum folded pairs of vectors with `UABD`,
and an absolute difference is not injective.** This is not an ARMSX3 defect they
introduced — it is **upstream RPCS3 master**, which every ARM64 fork inherited,
and ARMSX3 is so far the only one that has fixed it. Verified by fetching all
three copies of `SPULLVMRecompiler.cpp` rather than by reading one:

| tree | `aarch64_neon_uabd` in the checksum | pair lanes |
| --- | --- | --- |
| `RPCS3/rpcs3` master | 4 call sites (2010–2160) | `\|a - b\|` |
| ours, before this change | 4 call sites (1987–2059) | `\|a - b\|` |
| ARMSX3 | **none** | `a + b` |

### What the code actually computed

The ARM path checksums **96 bytes — 24 words — per step into 16 accumulator
lanes**, in four NEON vectors:

```
vls[0]          -> checksum[0..3]   += words[0..3]         (add)
vls[1], vls[2]  -> checksum[4..7]   += |words[4..7]  - words[8..11]|    (UABA)
vls[3]          -> checksum[8..11]  += words[12..15]       (add)
vls[4], vls[5]  -> checksum[12..15] += |words[16..19] - words[20..23]|  (UABA)
```

The host side at `SPULLVMRecompiler.cpp:1937/1939` computed the same absolute
difference in C++ so the two would agree, then the emitted code XORs the runtime
accumulators against those constants, ORs the lanes and branches on non-zero.
So it **is** an equality test — but of a *checksum*, not of the data. Half the
words in every block reached that comparison only through `|a - b|`.

That distinguishes it from the other absolute-difference instructions in the
emitted code. `docs/arm64/jit-emitted-code.md` counts `uaba` 4,503 times and
`uabd` 910 times; the 910 were assumed to include SPU `ABSDB`, which is a genuine
absolute-difference *opcode* and correct. **Both counts went to zero after the
fix**, so all 5,413 were this checksum and `ABSDB` never fires in this title.
The `< 192` byte path in the same function (`SPULLVMRecompiler.cpp:2101` onward)
is the other shape — `icmp eq` against constants, reduced through `udot` — and
is exact. Reading only that branch is how "the ARM64 code is clean" survives.

### Why the collision class is reachable

`|a - b|` is unchanged when the **same constant is added to both** sources, and
unchanged when the two are **swapped**. Summation is invariant only under an
anti-correlated change (`a + Δ`, `b − Δ`), which real code does not produce by
accident. The uniform-delta case does: SPU job managers stream near-identical
job binaries through the *same* local-store addresses, and a relocation that
shifts two paired words by the same amount is exactly the invariant. When it
collides, verification passes and **one job's cached compiled block runs against
another job's code**.

Both forms remain lossy — the x86 path sums many words into one lane too, and
that is the design. The point is that the `UABD` form adds a structured
collision class on top, for the sake of one ALU op per pair.

### The fix

Ours now matches ARMSX3: `checksum[4 + i] += words[4 + i] + words[8 + i]`, and
the four emitted `aarch64_neon_uabd` calls become `CreateAdd`. Cost is **two
extra ALU ops per 96-byte block** (the `UABA` accumulate becomes `ADD` + `ADD`);
`uaba` should disappear from a re-disassembled SPU cache and the object-cache key
invalidates the old objects by construction, so that count is the cheap way to
confirm the change reached the device.

**Confirmed on device 2026-08-10.** The cache was cleared, Eternal Sonata was
booted from cold, and the regenerated `spu-native-v2` disassembles to **`uaba` 0
and `uabd` 0 out of 509,424 instructions**, against **4,503 and 910 out of
509,468** in the cache that this same pipeline read immediately before. Details,
including the `add` count that absorbs them, in
[`jit-emitted-code.md`](jit-emitted-code.md).

The one thing that reading predicted wrong: `uabd` was expected to survive as SPU
`ABSDB`, and it did not. All 5,413 absolute-difference instructions in this
title's cache were the checksum.

## Where they are ahead, and it is worth taking

**`copy_data_swap_u32_neon` in `BufferUtils.cpp`.** `vrev32q_u8` over
`vld1q_u32`, with the compare variant accumulating via `veorq_u32`/`vorrq_u32` and
reducing once through `vmaxvq_u32`. We have zero NEON in that file. Our profile
puts the whole vertex cluster at ~0.2%, so it is small *here* — but their note is
worth reading: on ARM64 the path previously fell through to a scalar loop reached
through a **non-inlinable function pointer with LTO disabled project-wide**, which
is a bigger penalty than the scalar arithmetic alone. They also replaced
triangle-fan and quad index expansion with static tables plus `memcpy`.

## Two of their changes that directly challenge our configuration

**They un-pinned the LLVM CPU.** `rpcsx-android.cpp` equivalent sets
`llvm_cpu.from_string("")` for host detection, and their comment says it had been
pinned to `cortex-a34` — an in-order ARMv8.0 little core — so every block was
scheduled for the wrong machine. **We pin `cortex-a78`.** That is far closer to
the truth than `cortex-a34`, and it exists for a real reason: host detection on an
Armv9 core name turns SVE on, and this chip has no SVE, which is why
`sanitize_android_arm64_llvm_cpu` exists. But `cortex-a78` is still not an X3, an
A715 or an A710. The earlier `jit_cpu_native` A/B here was discarded as a phase
mismatch, so this is **genuinely unmeasured**, and the right experiment is an
explicit `-mcpu` per cluster with SVE forced off, not blind host detection.

**RETRACTED 2026-08-13: their affinity no longer applies, because they removed it.**
Commit `5f346b5e2` (2026-08-11) puts the thread scheduler back to the operating
system. They read the masks that the threads carry, and they found that the
big.LITTLE mask held **six SPU threads on four cores**, where Android grants all
eight. Their note says the one-thread-per-core reasoning "breaks down at six". The
paragraph below therefore does not describe their tree any more, and the
demonstration that it claims does not exist. What survives is the rule this fork
already has: confirm the placement with `Cpus_allowed_list` before you measure.

**Their affinity actually applies.** They read `/sys/devices/system/cpu/cpuN/cpu_capacity`,
add an `arm_big_little` arrangement, pin SPU/RSX to cores within 25% of peak
capacity, and — crucially — enable `thread_scheduler_mode::alt` on Android,
noting the affinity path had been compiled out there. **Ours is `Operating System`
mode, under which the entire `Affinity` block is inert** — measured, every thread
reports `Cpus_allowed_list: 0-7`. So the affinity experiment that came back null
here was testing a setting that does nothing, and ARMSX3 demonstrates the mode
that makes it live.

## What to do with this

0. **~~Take the `UABD` checksum fix.~~ Done, 2026-08-10.** It was the only
   correctness item in the whole diff and it outranked everything else here.
1. **~~Port `copy_data_swap_u32_neon`.~~ Done, 2026-08-10, and UNMEASURED.**
   `BufferUtils.cpp` now has `copy_data_swap_u32_neon` in the anonymous namespace
   under `#if defined(ARCH_ARM64)`, dispatched by an `#elif defined(ARCH_ARM64)`
   arm on the `DECLARE` block. Same kernel as theirs — `vrev32q_u8` over
   `vld1q_u32`, compare accumulating with `veorq_u32`/`vorrq_u32` and reducing once
   through `vmaxvq_u32` — with a scalar tail, which `count` carrying no
   multiple-of-four guarantee makes a correctness requirement rather than an
   optimization. Two deliberate differences from their file: it takes
   `<arm_neon.h>` directly rather than pulling in `Emu/CPU/sse2neon.h` (this fork
   keeps that header down to its two existing includers, see
   [`codegen.md`](codegen.md)), and it does not need their
   `-Wstrict-aliasing` suppression, which existed for sse2neon.

   **What is claimed and what is not.** Claimed: the ARM64 path is no longer a
   scalar loop behind a non-inlinable function pointer with LTO off. Not claimed:
   any frame-rate or CPU number. Their headline is Sonic '06 on the same silicon
   and it is *theirs*; our own gameplay profile puts the entire vertex/buffer
   cluster near **0.2%**, so the honest expectation here is small. Nothing was run
   on device. Re-check reach on a vertex-heavy title before spending a measurement
   slot on it.
2. **Re-run the affinity experiment under `thread_scheduler_mode::alt`.** The null
   result here is void — it tested an inert setting. Verify with
   `Cpus_allowed_list` that placement actually changed before measuring anything.
3. **Revisit the JIT `-mcpu`.** `cortex-a78` is a safe default chosen to dodge SVE,
   not a measured one. Test explicit `cortex-x3` / `cortex-a715` with SVE off.
4. **Do not port their `busy_wait`.** Theirs applies `arm_timer_scale` division;
   this fork deliberately does not, because every hot call site was retuned by hand
   against the 19.2 MHz timer. Dividing twice is the change that dropped Thor to
   ~1 FPS.

## The honest summary

Both forks are RPCS3 with an Android layer. **Their ARM64 work is in JIT targeting,
thread placement, compile deduplication and one NEON kernel; ours is in the wait
paths, AES and the DMA copy.** The two barely overlap, which means most of each
side's work is portable to the other — and it also means neither project has yet
touched the SPU self-loop that this fork measures at ~20% of gameplay CPU.

# Second pass, 2026-08-13

Their tree moved a long way in three days. This pass reads their master at
`e10f846` (2026-08-12) instead of their tree of 2026-08-10.

## The method changed, and it is better

The first pass diffed their tree against `RPCS3/rpcs3` **master** and counted 133
different files. That number mixes their work with the drift between two different
base commits. This pass adds their repository as a remote of the local
`rpcs3-upstream` checkout and asks Git for the fork point:

```sh
git remote add armsx3 https://github.com/ARMSX2/ARMSX3.git
git fetch --no-tags --no-recurse-submodules armsx3 master
git merge-base armsx3/master origin/master   # 652cf60bf, 2026-08-04
git log --no-merges 652cf60bf..armsx3/master
```

**210 commits, and every one of them is theirs.** Nothing is attributed by
guesswork, and the commit message says why each change exists. The first pass had
to infer intent from a file diff. Use the fork point from now on.

About 120 of the 210 commits are later than the first pass. Most are their Android
UI, their Vulkan loader and their save-state work, which this fork cannot use,
because RPCSX supplies that layer here.

## They retracted two of the things the first pass envied

Both retractions come from their own measurements, and both delete an advantage
that the scoreboard above gives them.

| their commit | date | what it undoes |
| --- | --- | --- |
| `5f346b5e2` | 2026-08-11 | The thread scheduler goes back to `Operating System`. The big.LITTLE mask held six SPU threads on four cores. |
| `cb3670e2d` | 2026-08-11 | The GETLLAR busy-wait percentage goes back to upstream's 100. They had used 20. |

The second one carries a result worth keeping. They tested 100 against 20 in game
and measured **no difference**, with 34% of eight cores busy and five cores idle.
Their reading is that the wait is not on the critical path, so the way it waits does
not matter. **That is their machine and their title, not ours.** This fork measures
GETLLAR as 82.5% of instrumented spin, and the sweep in [`spin.md`](spin.md) is
still the experiment to run here. Their null result is a warning about the size of
the prize, not a substitute for the measurement.

## What this pass took

| # | their commit | what it is | state here |
| --- | --- | --- | --- |
| 1 | `1847433eb` | Serialize the LLVM compilation of identical SPU programs | **ported** |
| 2 | `c2b5f0c40` | Instruction cache maintenance for the JIT | **partly ported**, two sites remained |
| 3 | `88f416288`, `e8c499056`, `ba5e4ebd6` | The GETLLAR out-buffer check: memoise it, then stop believing it | **ported** |
| 4 | `903220790`, `e7606bda0` | Budget the PPU compile workers against free memory | **ported, adapted** |
| 5 | `2df75aa60` | NEON for the primitive-restart index upload | **rejected: we already emit it** |
| 6 | `20aebe951` | Accurate SPU DMA plus Accurate Cache Line Stores livelock | **not applicable** |

### 1. The same SPU program compiled by five threads at once

`spu_runtime::add_empty()` gives back an existing item when the caller registers an
identical program, and it does not say that it did not insert. The entry-point check
in `spu_llvm_recompiler::compile()` then passes, because the entry point is also
the same. Each thread that arrives compiles the same program again, with its own
LLVM instance. The threads race the publication of `compiled` and the rebuild of the
ubertrampoline.

**Their symptom has the shape of the stall this fork already resolved.** They report
SPURS kernels parked on **zeroed workload state**, the PPU main thread blocked
forever in `sys_event_queue_receive` on a queue that no SPU will signal, and the
title never reaching the menu. This fork reported `CellSpursKernel0` parked at
`pc=0x12b0` in two unrelated titles. **That one is closed**, and the cause was the
empty `mov_rdata` branch, not a compile race: see the resolution and the two-title
verification at the end of [`rsx-boot-hang.md`](rsx-boot-hang.md).

**So do not read this port as a fix for an open bug here.** It removes a real race
that our tree still has, in the same shape as theirs. It is not evidence about
`pc=0x12b0`, which has a different and proven cause.

What the port is worth here is cold-boot work. They measured up to five concurrent
compilations of one item, about 790 collisions per boot, and **about two thirds of
all cold compilation work as duplicates**, with cold-boot SPU compilation falling
from about 12,900 blocks to 3,900. Their bug only appears on a cold cache, because a
cached program is compiled before SPU execution starts. That fits this fork:
`spu_native_object_cache_enabled()` is **off by default**, so nearly every boot here
is a cold boot.

The port keeps their design. `spu_item` gets `llvm_compile_state`, the first
compiler claims the item, and later arrivals wait and take the published result. A
scope guard marks the item failed on each early exit, so no waiter is stranded. The
wait for a relocated duplicate now also reads the failure state, with a bounded
timeout, because `spu_fast` can publish that result without touching the LLVM state.

**Nothing here is measured on this device.** Predicted: fewer SPU blocks compiled on
a cold boot, and a shorter first boot. **What falsifies it:** a cold boot whose
`SPU Runtime: Built N functions.` line does not fall. That line is already the way
this fork tells a real cold boot from a boot that wrote nothing, so the measurement
costs one boot and no new instrument.

### 2. Instruction cache maintenance: we had four of the six sites

The audit in [`three-way-audit.md`](three-way-audit.md) found the SPU ubertrampoline
and fixed it. The LLVM memory managers were already fixed here, and with a better
primitive than theirs: `__builtin___clear_cache` reads `CTR_EL0` and skips the
maintenance on cores that advertise IDC and DIC, where `asmjit::VirtMem::
flushInstructionCache` does not.

Their commit found **two sites that this fork still had**, both in
`rpcs3/util/JITASM.cpp`:

* `jit_runtime_base::_add()` copies asmjit output into executable memory and did
  **no** cache maintenance.
* `jit_runtime::finalize()` rewrites an executable snapshot in place when the
  emulator restarts. It had the `asm("ISB"); asm("DSB ISH")` pair, which cleans
  nothing, orders the two barriers the wrong way round, and is not `asm volatile`
  with a memory clobber.

**Both are reachable on ARM64.** `build_function_asm` reaches `_add` for
`ppu_gateway` (`PPUThread.cpp:317`), for `tr_dispatch` (`SPUCommonRecompiler.cpp:525`)
and for the thread entry in `Thread.cpp:2436`. The check matters, because this
codebase has recorded a search that searched nothing four times.

Neither site is a measurement. A missing i-cache flush shows up as an
unreproducible crash, never as a number.

### 3. The GETLLAR out-buffer check cost more than it decided

The spin detector asks whether the LSA points at a caller's OUT buffer, which is
"unlikely to be a loop". It answered with `dump_callstack_list()`, which walks the
whole stack and calls `is_exec_code` for each candidate, and that allocates a
`vector<bool>` and scans for branch targets. **They profiled that call at 19.6% of
all process CPU** on a title whose SPU code spins on GETLLAR with an LSA in the top
64K of local store.

Two changes, both taken:

* **Memoise it.** Only the innermost frame is used, and it is a function of `pc`,
  the stack pointer and the link register. Recompute it only when one of the three
  moves. Their first attempt keyed on `getllar_spin_count`, which several other
  paths reset, so the callstack was still rebuilt constantly; the key must be the
  values that the answer depends on.
* **Stop believing the verdict.** "Not a loop" resets the spin count and leaves the
  switch at `umax`. The caller then skips `busy_wait`, skips the sleep path, and
  returns at once, so the SPU runs GETLLAR again at full rate **with no backoff at
  all**. The spin count never reaches 4, so the spin optimisation is never
  evaluated, and the 400 ms fallback that forces a sleep is never reached. The same
  site with the same stack, 32 times, is itself the evidence that it is a loop.

**The cap is gated here, and their default is kept.**
`debug.rpcsx.thor.getllar_outbuf_cap` sets the count; `0` restores the current
behaviour, which never stops believing the verdict. The value 32 is theirs, measured
on their title. **Whether either change reaches anything on this device is
unmeasured.** The check only costs something when the LSA sits in the top 64K of
local store, and no profile here has named `dump_callstack_list`. The cheap first
test is a wait-profiler boot with the cap at `0` and at `32`.

### 4. The PPU compile workers had no memory budget at all

[`ppu-compile-oom.md`](ppu-compile-oom.md) records Odin Sphere dying in PPU
precompile with `Scudo ERROR: internal map failure (NO MEMORY)` inside RuntimeDyld
relocation processing. Its "Next" section names the worker count as one of the two
levers. `jit_core_allocator::limit()` here was upstream's: the thread count, and
nothing else. **Eight LLVM workers, with no reference to memory.**

They hit the same allocator failure twice, on two titles, and fixed it twice. The
port takes their second set of numbers: reserve 2 GB for the emulator, then 1.5 GB
for each worker, against `MemAvailable` rather than installed memory. A single large
PPU module can take more than a gigabyte through MCJIT, and the reading is taken
before the emulator maps the PS3 address space.

Two deliberate differences from their patch. It reuses `utils::get_memory_usage()`,
which already parses `MemAvailable` in this tree, instead of adding their
`utils::get_avail_memory`. And it is `#ifdef ANDROID`, so the Windows build keeps
the upstream count.

**This lowers the default compile parallelism on this device**, which makes a cold
precompile slower. That is the intended trade: the run that finishes beats the run
that aborts. `Max LLVM Compile Threads` still overrides it.

### 5. Rejected, because this fork already emits that code

`2df75aa60` hand-writes NEON for the primitive-restart index upload. Their commit
message says clang cannot vectorize the loop, because the min and max updates are
conditional on the restart compare.

**That is true of the upstream shape and false of ours.** This fork already rewrote
`primitive_restart_impl::upload_untouched_naive` branch-free, so that the reductions
take a neutral value for restart entries and stop carrying a conditional side
effect. Verified rather than trusted, by compiling both shapes at the target this
build uses:

```sh
clang++ --target=aarch64-linux-android24 -O2 -march=armv8.4-a -mtune=cortex-a715 -S
```

| shape | emitted |
| --- | --- |
| ours, branch-free | `rev16`, `cmeq`, `orr`, `bic`, `umin`, `umax`, `uminv`, `umaxv` |
| upstream's, conditional | four `csel`, **no vector instruction** |

Our loop compiles to **the same lane algebra that their intrinsics spell by hand**,
and clang unrolls it to two `q` registers for each iteration, so it reads 16 `u16`
where their kernel reads 8. Porting their intrinsics would replace a wider kernel
with a narrower one and would arch-gate a file that does not need it.

This is the "check whether this fork already compensated" rule paying for itself,
and it is the second time this exact rule has applied to their tree.

### 6. Not applicable

`20aebe951` fixes a livelock from Accurate SPU DMA and Accurate Cache Line Stores
being on together. The defect was in their own Kotlin defaults. Both settings are
`false` in `Emu/system_config.h` here, as they are upstream.

## What is still theirs and still open

Read, and not acted on in this pass:

* **`431b6d092`, `954337866`, `8c707648c`, `38424a59b`** — a module that LLVM
  cannot compile falls back to the interpreter, and a recovered LLVM fatal error no
  longer wedges the SPU JIT. Their note is that bionic does not unwind C++ frames on
  `pthread_exit`, so the MCJIT lock stays held by a thread that no longer exists.
  This fork runs `run_recoverable_llvm` as well. Worth a read before the next boot
  failure that looks like a hang in compilation.
* **`703d98ae9`, `fa97d01b0`, `cf2481fc1`** — conditional rendering is turned off on
  Turnip as well as on Adreno, and open occlusion queries are closed before the
  render pass ends. **This device runs Turnip.** These belong with the render-pass
  work in [`adreno-tiler.md`](adreno-tiler.md).
* **`42e3d3b26`, then `6e15b1694` which reverts it** — they cleared at pass begin
  instead of reading the framebuffer back, and then they took it out again. The
  `LOAD_OP_CLEAR` item in [`adreno-tiler.md`](adreno-tiler.md) should read both
  commits before spending a device slot.
* **`0b5a43c60`** — a stuck `vm::writer_lock` reports who it waits on. This fork
  measures `writer_lock` plus `passive_lock` at 6.2% of gameplay.
* **`ccbcbce36`, `5636c9f3f`, `1c371cfad`** — FIFO fetched in 4 KB blocks, and the
  per-packet costs taken out of the FIFO loop. Their profile puts 82.5% of their RSX
  thread in FIFO decode. **Ours does not**, so read the profile here before porting
  any of it.

## The honest summary of the second pass

Their tree is now mostly an Android application, a Vulkan loader and a GPU profiler,
and this fork can use almost none of that. The overlap is where it was: the SPU, the
JIT and the memory budget.

**The most valuable thing in this pass is not code.** It is that they measured, and
then reverted, both configuration changes that the first pass held up as their
advantage. A comparison against a moving fork has a shelf life of about three days.

## Third pass (2026-08-20)

Both trees were fetched again. `RPCS3/rpcs3` master is `243d7db5b`.
`ARMSX2/ARMSX3` master is `82f21b16d`, which is 166 commits later than the second
pass. 49 of those are theirs. 117 are upstream RPCS3 that they inherited.

Five changes were ported. The dated detail is in
`debug-experiments/20260820-armsx3-upstream-selective-port.md`.

**The one real find is the compute group size.** `a2f005955` gives Adreno its own
case at 64 lanes. This tree still had the old single `QUALCOMM` case at 32, with
the upstream comment "TODO: Actually bench this". Adreno waves are 64 lanes wide,
so a 32-lane group does not pack with its neighbour: the GPU takes a whole wave
and masks half of it off. These kernels use no shared memory and no barriers, so
the group size is only a scheduling hint. `cbee3cd44` came with it, so
`RPCSX_THOR_CS_GROUP_SIZE` can compare 32 against 64 on one build.

**The log-level work is the second find.** `ab58fb087` and `d9a0481dc` move hot
diagnostics to trace. Three of their eleven demotions were refused here, because
the analyzers in `tools/` read those exact lines and fail closed. `Trampoline
simplified` was the valuable one: it sat at error level and they counted it about
1500 times in a 15 minute session.

### Where this tree is now ahead

**`6161ecd7a` is the clearest case yet.** Upstream stopped inverting float-to-int
saturation on ARM64, which this tree fixed earlier. This tree also gives NaN the
PowerPC result of `0x80000000`; `fcvtns` produces 0. Upstream still has that
wrong. Porting their commit would have been a regression, and only reading both
implementations showed it.

`82164a54c`, the SELB XFloat normalization, is already present at both call
sites.

### Still theirs, still open

* **`5d71742da`** — the driver pipeline cache persists across runs. This is the
  most valuable thing left in their tree, because cold start is the problem here.
  It depends on their `vk_android_loader`, which this tree does not have, so it
  is 224 lines and an adaptation, not a port.
* **`ac897144b`, `07a24cf71`** — PPU compile out-of-memory. This tree has its own
  Scudo handling; see [`ppu-compile-oom.md`](ppu-compile-oom.md). Read both
  before touching either.
* The Turnip conditional-rendering items from the second pass are unchanged.

### What is not worth reading

They added frame generation across 17 commits and then reverted the whole line in
`187654eae`. The rest of their 49 is the Play-store build, RPCN, input, and save
data: their application, not their core.

## Seventh pass, 2026-08-22, against `daed55c42` (release 0.9.4.2)

38 commits past `82f21b16d`. **Six changes ported, none measured on the device.**
The full account, with the rejected items and their reasons, is in
[`../../CLAUDE.md`](../../CLAUDE.md), section "ARMSX3 seventh pass". Only the
summary is here, so the two do not disagree.

Ported: the `nv4097` redundant vertex program check (`e13fc184f`, and **this tree
had the defect**), the savestate resume guard (`a46dae38b`), the NP Ethernet
address (`b2caae9da`), and from upstream RPCS3 the DP3 precision fix
(`3aac7d776`) and flat shading (`b97f4bd8d`).

Rejected: the fence poll switch and its same-day revert (net zero), the Oboe
backend fix (no Oboe here), cellAudio (no `Emu/Cell/Modules` here), the ISO short
read (no `Loader/ISO.cpp` here, and unconfirmed by them), the pipeline cache kill
switch (this tree has its own persisted cache), and nine commits that touch only
their Kotlin UI.

### Frame generation, second attempt, deferred again

They shipped LSFG frame generation across 20 commits, `e05ea4d21` onward. That is
35 new files and about 324 KB, plus 264 insertions across seven existing VK files.

**Note the history above: they already added frame generation across 17 commits
and reverted the whole line in `187654eae`.** This is the second attempt. It is
two days old, it took 18 fix-ups in one day, and one of those reverts its own
single-submit restructure. It is also written against their VK backend, and ours
now calls through `VK_GET_SYMBOL()`, keeps its own pipeline cache, carries the RSX
auditor hooks, and holds the extended dynamic state pipeline key work.

Wait for it to settle before reading it again.
