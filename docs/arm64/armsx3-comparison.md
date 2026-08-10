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
| `BufferUtils.cpp` NEON | **`copy_data_swap_u32_neon`, theirs** | 11 x86 gates, **0 NEON** |
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

1. **Port `copy_data_swap_u32_neon`.** Small, self-contained, already written and
   working in a sibling fork. Re-check reach on a vertex-heavy title first.
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
