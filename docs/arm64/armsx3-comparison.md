# ARMSX3 compared, and what it says about our fork

[ARMSX3](https://github.com/ARMSX2/ARMSX3) is a proof-of-concept RPCS3 port for
Android from the ARMSX2 team, public since ~2026-08-09, advertising "ARM64-focused
optimizations". Same lineage as this fork, same target silicon — their Skate 3
figure of ~20–30 fps is on a Snapdragon 8 Gen 2, the Thor's exact chip.

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
`uabd` 910 times; the 910 include SPU `ABSDB`, which is a genuine
absolute-difference *opcode* and correct. The 4,503 `uaba` are this checksum.
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

**Not measured.** No device run was made for this change. It is argued from the
algebra and from three-way source agreement, not from a boot.

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
