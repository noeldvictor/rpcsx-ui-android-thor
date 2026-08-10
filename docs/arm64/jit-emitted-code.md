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
