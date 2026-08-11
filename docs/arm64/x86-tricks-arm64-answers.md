# Seven x86 tricks, and what this fork emits on AArch64

RPCS3 accelerates some SPU operations with unusual x86 instructions. Whatcookie
lists seven of them in *"Abusing x86 instructions to optimize PS3 emulation"*
(YouTube `40tyEVx_umY`, 985 s). This document answers one question for each:
**what does our AArch64 path emit, and is that the best AArch64 answer?**

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md). The hardware rows
come from the vendored per-core guides in [`docs/hardware/`](../hardware/). The
emitted-code counts come from the post-fix `spu-native-v2` disassembly recorded
in [`jit-emitted-code.md`](jit-emitted-code.md): **1,188 objects, 4,752
functions, 509,424 instructions**, Eternal Sonata `BLUS30161`.

**Quote the A715 guide, not the X3 guide.** `config.yml` puts SPU threads on
`CPU5` and `CPU6`, which are the A710/A715 cluster. The A710 and A715 rows agree
with each other and differ from the X3 rows on four of the instructions below.

## The verdict table

| # | video chapter | SPU opcode | our AArch64 output | emitted count | verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | `PSADBW` | `ABSDB` | `UABD` | **0** | NOT REACHED BY THIS TITLE |
| 2 | SPU `SUMB` | `SUMB` | 2 × `UDOT` + `UZP1` | **9** | ALREADY OPTIMAL |
| 3 | `VPDPBUSD` | `SUMB` | the same `UDOT` | **9** | ALREADY OPTIMAL |
| 4 | `VDBPSADBW` | `SUMB` | the same `UDOT` | **9** | NO ARM EQUIVALENT |
| 5 | `GF2P8AFFINEQB` | `SHUFB` mask, `GB`/`GBH`/`GBB` | `USHR`+`TBL`; `SDOT`/`UMMLA` | 5,859 `tbl`, 57 | NO ARM EQUIVALENT |
| 6 | SPU `GBB` | `GBB` | `AND`+`UMMLA`+lane move | **26** (`smmla` 11, `ummla` 15) | ALREADY OPTIMAL |
| 7 | SPU `FCGT` | `FCGT` | 7 ops around an inline-asm `BSL` | **117** | ALREADY OPTIMAL |

**No item on this list is a candidate.** Together the seven lowerings account
for about 210 of 509,424 emitted instructions, which is 0.04%. The audit still
produced one large finding and two corrections, and they are below.

## The correction that matters: 1,664 of the 1,673 `udot` are not the video's optimization

`CLAUDE.md` and `jit-emitted-code.md` both say the 1,661 `udot` (1,673 after the
checksum fix) prove the video's dot-product work is *taken*. The instruction is
taken. The **operation is not the one the video describes**.

Every `udot` in the corpus was classified by the instruction that defines each of
its two vector sources, inside the same function:

| source pair | count | what it is |
| --- | --- | --- |
| `cmeq`, `cmeq` | 1,338 | SPU block verification, `SPULLVMRecompiler.cpp:2172` |
| `cmeq`, `movi` (all-ones) | 326 | the same, odd-count tail at `:2201` |
| `cnt`/`tbl`/`movi`, `movi #0x1` | **9** | SPU `SUMB`, `SPULLVMRecompiler.cpp:6476` |

The verification path pairs two 16-byte compare masks and accumulates them with
`UDOT`. It runs once per compiled block, and it is not an SPU opcode at all. The
control is the reduction beside it: `addv s, v.4s` appears **615** times, one per
verification site, and 615 sites × 2.7 pairs gives the 1,664.

So the video's own optimization — dot product for `SUMB` and for the `GB` family
— is present and correct and fires **66 times** in 509,424 instructions:

| lowering | instruction | count |
| --- | --- | --- |
| `SUMB` | `udot` | 9 |
| `GB` | `sdot` | 31 |
| `GBH`, `GBB` | `smmla` / `ummla` | 11 / 15 |

**This is the same class of error the repo already records five times.** The
count was correct and the attribution was not. `jit-emitted-code.md` asked "is
this instruction present" and never "which lowering emitted it".

## The hardware rows these answers rest on

A715 is the cluster that runs SPU threads. X3 is one core and takes the least
work. The two disagree on `TBL`/`TBX`, on `SHRN` and on `FMOV`.

| instruction | A715 lat | A715 thr | A715 pipes | X3 lat | X3 thr | X3 pipes |
| --- | --- | --- | --- | --- | --- | --- |
| `SDOT`/`UDOT`, 8-bit | 3 (1) | 2 | `V` | 3 (1) | 4 | `V` |
| `SMMLA`/`UMMLA` | 3 (1) | 2 | `V` | 3 (1) | 4 | `V` |
| `TBL`, 1 or 2 tables | 2 | 2 | `V` | 2 | 2 | `V01` |
| **`TBX`, 2 tables** | **4** | **1** | `V` | 4 | 2 | `V` |
| `SHRN` (shift by immed, basic) | 2 | **1** | **`V1`** | 2 | 2 | `V13` |
| `XTN` | 2 | 2 | `V` | 2 | 4 | `V` |
| `ADDV` 8H | **5** | **1** | `V1`, `V` | 4 | 2 | `V13` |
| `ADDV` 4S | 3 | 1 | `V1` | 2 | 2 | `V13` |
| `UMOV`/`SMOV`, element to gen reg | 2 | 1 | `V` | 2 | 1 | `V01` |
| `FMOV`, vec to gen reg | **4** | 2 | `V` | 2 | 1 | `V01` |
| `CMEQ`/`CMGE`/`CMGT`/`CMLT` | 2 | 2 | `V` | 2 | 4 | `V` |
| `AND`/`BIC`/`EOR`/`ORR` | 2 | 2 | `V` | 2 | 4 | `V` |
| `BIF`/`BIT`/`BSL` | 2 | 2 | `V` | 2 | 4 | `V` |
| `UABD` | 2 | 2 | `V` | 2 | 4 | `V` |
| **`UABA`** | 4 (1) | **1** | **`V1`** | 4 (1) | 2 | `V13` |
| `CNT` | 2 | 2 | `V` | 2 | 4 | `V` |
| `UZP1`/`UZP2` | 2 | 2 | `V` | 2 | 4 | `V` |
| `PMULL`, 64x64 crypto | 2 | **1** | **`V0`** | 2 | 2 | `V23` |
| `PMUL`/`PMULL`, 8x8 polynomial | 3 | 1 | `V0` | — | — | — |

**Second correction: `TBX` does not beat `TBL` on the cluster that runs SPU
code.** `CLAUDE.md` says *"`TBX` beats `TBL` on this core — four pipes against
two, throughput 4 against 2"*. That is the X3 row, and it is inverted on A715
and A710: `TBL` with 1 or 2 tables is latency 2 at throughput 2 on all `V`
pipes, and 2-table `TBX` is latency 4 at throughput 1. The `SHUFB` path emits
`TBX2` because the out-of-range lanes must keep the value the zero table
produced, so the choice stays. It is a **correctness** requirement on this
cluster, not also a speed win. The A710 guide gives the same numbers.

---

## 1. `PSADBW` (0:45) — sum of absolute differences

**RPCS3 does not use it.** A search of this fork and of the upstream RPCS3
checkout finds `psadbw` only inside the vendored asmjit test files, OpenCV
headers and `sse2neon.h`. No emitter selects it. The video presents `PSADBW` as
the idea that leads to `VDBPSADBW` in item 4: `PSADBW` against zero sums 8 bytes
per 64-bit half, and `SUMB` needs 4 bytes per word.

**The one SPU opcode that is a real absolute difference is `ABSDB`**
(`SPULLVMRecompiler.cpp:5373`), written as `absd(a, b)` and lowered to a single
`UABD`.

**Reach: zero.** The corpus contains **0** `uabd` and **0** `uaba`. The 5,413
that were deleted were the block-verification checksum, which folded pairs of
words through `|a - b|` — a non-injective operation that decided block identity.
That fix is in [`jit-emitted-code.md`](jit-emitted-code.md). This audit adds one
number to it: on A715 `UABA` is latency 4, **throughput 1, pipe `V1`**, the
single narrowest pipe, while the `ADD` that replaced it is 2/2/`V`. The
correctness fix also moved 4,503 instructions off `V1`.

**Verdict: NOT REACHED BY THIS TITLE.** `UABD` is the correct one-instruction
lowering for `ABSDB` and Eternal Sonata never issues `ABSDB`.

## 2. SPU `SUMB` (1:54)

`SPULLVMRecompiler.cpp:6447`. `SUMB` adds the four bytes of each word and packs
the eight results as 16-bit lanes.

Our AArch64 branch is at `:6473-6477`:

```cpp
const auto [a, b] = get_vrs<u8[16]>(op.ra, op.rb);
const auto ones = splat<u8[16]>(0x01);
const auto ax = bitcast<u16[8]>(udot(zeroes, a, ones));
const auto bx = bitcast<u16[8]>(udot(zeroes, b, ones));
```

`UDOT` with an all-ones multiplier is exactly a per-word byte sum. The emitted
form is `movi v.16b, #0x1`, two `udot`, and a `shuffle2` that LLVM lowers to
`uzp1`. The portable fallback at `:6488` needs six operations.

**Reach: 9 `udot` in 3 functions.** Three of the nine take their input from a
`cnt`, which is SPU `CNTB` followed by `SUMB` — the guest's population count.
`cnt` itself appears only 6 times.

**Is anything better?** No. `UADDLP` twice (`u8`→`u16`→`u32`) also gives per-word
byte sums, but that is two instructions at 2/2/`V` against one at 3(1)/2/`V`, and
it lands the result in the wrong lane width. `UDOT` is one instruction on all
four `V` pipes with an accumulator latency of 1.

**Verdict: ALREADY OPTIMAL.**

## 3. `VPDPBUSD` (3:14) — AVX512-VNNI byte dot product

`SPULLVMRecompiler.cpp:6481`, inside the `#else` arm of the same `SUMB`
function. `vpdpbusd(zeroes, a, ones)` and `udot(zeroes, a, ones)` are the same
operation: a byte-by-byte dot product accumulated into 32-bit lanes.

**The prediction that `VPDPBUSD` maps to `UDOT` is correct, and the code already
does it.** The two arms sit in the same `#ifdef`, `m_use_dotprod` on AArch64 and
`m_use_vnni` on x86. `codegen.md` already records that the VNNI arm is inside
`#ifndef ARCH_ARM64` and costs nothing here.

**Reach: the same 9 instructions as item 2.**

**Verdict: ALREADY OPTIMAL.**

## 4. `VDBPSADBW` (4:25) — AVX512 double block packed SAD

`SPULLVMRecompiler.cpp:6456` and `:6460`, under `m_use_avx512`. This is the best
x86 form for `SUMB`: `vdbpsadbw(a, 0, 0)` gives the four per-word byte sums in
one instruction, and when `op.ra == op.rb` the whole opcode is one instruction.

**AArch64 has no double-block SAD.** There is no instruction that sums 4-byte
blocks and writes 16-bit lanes in one step. The closest tool is the `UDOT` we
already use, which costs one extra `UZP1` to interleave the two operands.

So our sequence is 3 vector operations plus a `movi`, against AVX512's 1 to 3.
On A715 all four are latency 2 or 3 at throughput 2 on all `V` pipes. The gap is
one instruction on an opcode that appears 9 times.

**Verdict: NO ARM EQUIVALENT.** The gap is real and it is worth nothing here.

## 5. `GF2P8AFFINEQB` (8:02) — GFNI 8x8 bit-matrix multiply over GF(2)

RPCS3 uses this instruction for **two** different operations.

**(a) The bit gather**, at `:5623` (`GB`), `:5679` (`GBH`) and `:5865` (`GBB`).
A constant matrix with one bit set extracts one selected bit from each byte.

**(b) The `SHUFB` selector mask**, at `:7283`, `:7313`, `:7363`, `:7381` and
`:7395`. `gf2p8affineqb(c, <0x40,0x20,...>, 0x7f)` maps each selector byte to
`0x00`, `0xff` or `0x80` from its top two bits, which is the constant-lane
contribution `SHUFB` must OR in.

**What we do instead.** Operation (a) uses `SDOT` and `UMMLA`; see item 6.
Operation (b) uses a 16-entry table:

```cpp
const auto zero_lut = build<u8[16]>(0,0,0,0,0,0,0,0,0,0,0,0, 0xff,0xff,0x80,0x80);
const auto x = tbl(zero_lut, (c >> 4));                     // :7231, :7259
set_vr(op.rt4, tbx2(x, a, b, bcax(splat<u8[16]>(0x0f), c, splat<u8[16]>(0x60))));
```

That is `USHR` plus `TBL`, two instructions, against GFNI's one affine multiply
plus two `select`s. **Our form is already shorter than the x86 form it
replaces.** `tbl` appears 5,859 times in the corpus and almost all are the
1-table form, so this path is live.

**Would `PMULL` beat it?** No, for two reasons.

* **`PMULL` cannot express the operation.** Carry-less multiply applies a
  Toeplitz matrix over GF(2). `GF2P8AFFINEQB` applies an arbitrary 8x8 matrix
  per byte. Only shift-shaped and rotate-shaped matrices are reachable through
  `PMULL`, and RPCS3's two matrices are neither.
* **`PMULL` is a one-pipe instruction on this cluster.** A715 puts the 64x64
  crypto form at throughput 1 on `V0` and the 8x8 polynomial form at throughput
  1 on `V0`. That is the same single pipe that already carries `BCAX`, which
  `microarchitecture.md` records as the one narrow choice in the `SHUFB` path.

**Would `TBL` beat it?** `TBL` reads at most 4 tables, which is 64 entries, so a
general byte-to-byte map needing 256 entries does not fit. It does not have to:
both RPCS3 uses have a constant matrix, and for use (b) only the top nibble of
the selector matters, so 16 entries are enough. That is what we emit.

**Verdict: NO ARM EQUIVALENT** for the instruction, and no gap in the code. Both
operations RPCS3 spends it on already have an AArch64 form that is equal or
better.

## 6. SPU `GBB` (11:19) — gather bits from bytes

`SPULLVMRecompiler.cpp:5774`. `GBB` takes bit 0 of each of the 16 bytes and
writes the 16-bit result into the preferred slot.

**The order of the branches decides what runs.** The i8mm test comes first, and
Thor reports `i8mm=true`, so `GBB` and `GBH` always take `SMMLA`/`UMMLA` and
never reach the `SDOT`/`UDOT` plus `ADDP` branch below them. The emitted code
confirms this: `addp` appears **0** times in the corpus. `GB` has no i8mm branch
and takes `SDOT`.

Emitted, from the disassembly:

```
and    v4.16b, v4.16b, v12.16b      ; mask bit 0
movi   v6.2d,  #0                   ; zero accumulator
ummla  v6.4s,  v4.16b, v5.16b       ; v5 = the weight matrix, from the pool
```

Three vector operations plus a lane move. On A715 `UMMLA` is latency 3,
accumulator latency 1, throughput 2, on all four `V` pipes.

**Now the `SHRN` trick.** The well-known AArch64 answer to a missing `PMOVMSKB`
is `shrn v0.8b, v0.8h, #4`, which narrows 16 byte lanes to a 64-bit value
holding 4 bits per lane. It is the right tool for a **branch**, and it is the
wrong tool here. Compare the two:

| | our `UMMLA` form | the `SHRN` form |
| --- | --- | --- |
| build all-ones lane masks | not needed | `SHL #7` + `CMLT #0` |
| gather | `MOVI` + `AND` + `UMMLA` | `SHRN` |
| leave the vector unit | no | `FMOV x, d` |
| 4 bits per lane to 1 bit per lane | not needed | `AND` mask + 64-bit `MUL` + `LSR` |
| return to the vector unit | not needed | `FMOV`/`INS` + zero the other lanes |
| total | **4** | **8 to 9** |
| domain crossings | **0** | **2** |
| narrowest pipe used | `V`, throughput 2 | `SHRN` is `V1`, throughput 1 |

Three separate things make the `SHRN` trick lose on this core.

1. **`SHRN` is throughput 1 on pipe `V1` on A715**, the same single pipe as every
   vector shift and every `ADDV`. `UMMLA` is throughput 2 on all four `V` pipes.
2. **`SHRN` gives 4 bits per lane, and `GBB` needs 1.** Compressing nibbles to
   bits needs a 64-bit multiply and a shift in a general-purpose register.
3. **The result must end in a vector register.** SPU registers live in the vector
   file, so the `SHRN` route pays `FMOV` out and `FMOV`/`INS` back. On A715 that
   is latency 4 out and latency 5 in, at throughput 1 for the write.
   `codegen.md` opens with exactly this rule: keep the computation in vector
   registers and cross over once, at the end.

**Reach: 26 instructions**, 11 `smmla` and 15 `ummla`, in 509,424.

**Verdict: ALREADY OPTIMAL.** The `SHRN` trick answers a different question —
"give me a bitmask in a general-purpose register so I can branch on it" — and
that question **does** occur in this codebase, at 1,402 sites. See the candidate
section below.

## 7. SPU `FCGT` (14:49)

`SPULLVMRecompiler.cpp:7640`. The general path compares two SPU floats as
integers, because the SPU has no NaN and no infinity, and x86 `CMPPS` therefore
cannot be used. The AArch64 branch is at `:7705-7714` and it carries upstream's
inline-assembly `BSL`, which works around LLVM issue 197360.

The emitted sequence, read from the disassembly at 117 sites:

```
and    v3.16b, v0.16b, v17.16b      ; ai & bi
cmgt   v1.4s,  v0.4s,  v17.4s       ; ai > bi
cmgt   v2.4s,  v17.4s, v0.4s        ; ai < bi
cmge   v3.4s,  v3.4s,  #0           ; (ai & bi) >= 0
bsl    v3.16b, v1.16b, v2.16b       ; the select
fcmeq  v1.4s,  v0.4s,  v17.4s       ; a == b, ordered
bic    v1.16b, v3.16b, v1.16b       ; drop the equal case
```

Seven operations. Every one is latency 2 at throughput 2 on all four `V` pipes
of A715. The dependency chain is four deep.

**Reach: 117 sites**, found by tracing every `bsl` whose three sources come from
a `cmge` and two `cmgt`. That makes `FCGT` the most-emitted of the seven, and it
is still 0.023% of the corpus.

**A shorter form exists and it is not safe.** When `ai != bi`, `(ai < bi)` is the
complement of `(ai > bi)`, so the select collapses to an exclusive-or:

```
and + cmlt #0 + cmgt + eor + fcmeq + bic      = 6 operations
```

That drops one operation and removes the inline assembly. It is **wrong for one
input**: a negative NaN compared against itself. There `ai == bi`, `fcmp une` is
true, and the exclusive-or form returns true where the select form returns
false. The SPU has no NaN, but approximate xfloat mode runs host `f32`
arithmetic, which can produce one. Recorded here so nobody rediscovers the form
without the caveat.

**Verdict: ALREADY OPTIMAL.** The seven-operation form matches upstream, it is
minimal for exact semantics, and it lands entirely on the wide pipes.

---

# The candidate this audit did produce, and it is not on the list

Item 6 says the `SHRN` movemask trick answers a question `GBB` does not ask.
**The SPU branch lowering asks it, 1,402 times, and gets a worse answer.**

`SPULLVMRecompiler.cpp:9348`:

```cpp
// Check sign bit instead (optimization)
...
const auto a = get_vr<s8[16]>(op.rt);
const auto cond = eval(bitcast<s16>(trunc<bool[16]>(a)) >= 0);
```

Eight sites carry this shape — `:9356`, `:9417`, `:9449`, `:9481`, `:9684`,
`:9759`, `:9803`, `:9847` — which are `BIZ`, `BINZ`, `BIHZ`, `BIHNZ`, `BRZ`,
`BRNZ`, `BRHZ` and `BRHNZ`. When the branch register holds a comparison result,
the code collapses all 16 bytes to a 16-bit mask and tests one bit of it. On x86
that is `PMOVMSKB` plus `TEST`, two instructions, and it is cheaper than
extracting one lane. **On AArch64 there is no movemask**, so LLVM builds one:

```
ldr    q2, [x9]                     ; the weight vector, from the pool
and    v1.16b, v1.16b, v2.16b
ext    v2.16b, v1.16b, v1.16b, #0x8
zip1   v1.16b, v1.16b, v2.16b
addv   h1, v1.8h
fmov   w8, s1
tbnz   w8, #0xf, ...
```

The direct AArch64 spelling is the fallback the code skips over, at `:9369`:
`extract(get_vr(op.rt), 3) == 0`, which is `umov w8, v1.s[3]` plus `cbz` — **two
instructions**.

**Measured in the corpus, not predicted:**

| | count |
| --- | --- |
| `addv h, v.8h` whose source is a `zip1` | **1,402** |
| of those, followed by `fmov w` then `tbnz`/`tbz` | **1,190** |
| `tbnz`/`tbz` on bit `#0xf` | 748 |
| `tst w, #0x3000` (the `BIHZ`/`BRHZ` halfword pair) | 38 |
| `umov w, v.s[3]` already emitted elsewhere | 7,875 |

So the pattern is **1,402 sites**, against 615 for the block verification and 322
for `bcax`. Removing four instructions from each is roughly **5,600
instructions, or 1.1% of the compiled corpus** — about fifty times the whole
seven-item list.

**And it moves work off the worst pipe on this cluster.** On A715 `ADDV` 8H is
latency 5 at throughput 1 on `V1`, the pipe that also carries every vector
shift. `FMOV` from vector to general register is latency 4. `UMOV` of one
element is latency 2 at throughput 1 on all `V` pipes.

**The change is a guard, not new codegen.** Put the eight `bitcast<s16>(trunc<
bool[16]>(...))` blocks behind `#ifndef ARCH_ARM64` and let each function fall
through to the `extract(..., 3)` path it already has.

**What would falsify it.** Two things, in order.

1. **LLVM may already fold the extract back into a movemask.** Compile both
   spellings at `-mcpu=cortex-a78 +dotprod +i8mm` and read the assembly before
   changing anything. This is verification level 2 in `CLAUDE.md`.
2. **The count is weighted by compiled bytes, not by execution.** 1,402 sites is
   what the JIT emitted, not what runs. The gameplay profile puts 47.88% of
   cycles in JIT code but cannot yet say which blocks. The `perf` map now exists,
   so a symbolized profile can answer it.

**Predicted magnitude: 4 instructions removed at up to 1,402 sites, 1.1% of
compiled code.** No speed figure is given, and none should be, until the profile
weights it.

## What this document does not establish

* **Nothing here is measured on the device.** Every count comes from the
  disassembly of the on-device cache, which says what the JIT **compiled** for
  one title. It does not say what **runs**.
* **The corpus is one title in one scene.** `BLUS30161`, Eternal Sonata. A title
  whose SPU code uses `ABSDB` or `AVGB` would move the item 1 row.
* **The `udot` attribution rests on a backward scan** inside each function for
  the instruction that defines each source register. It cannot follow a value
  across a basic block. The control is the `addv s, v.4s` count of 615, which is
  one per verification site and agrees with 1,664 divided by 2.7 pairs per site.
