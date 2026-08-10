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
