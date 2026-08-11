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

**Correction, from the compiler check below: the count is 6, not 4.** The
compiled sequence is 8 instructions and the lane extract is 2. The halfword pair
is 9 against 2. The section below gives both sequences.

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

---

# The candidate passes check 1: LLVM keeps the lane extract

The section above lists two checks that must pass before anybody writes code.
This section answers check 1 and it does not change the recompiler. It also
answers the semantics question, which outranks the instruction count.

**Verdict: the candidate is ALIVE.** LLVM does not fold the lane extract back
into a movemask. The two spellings compute the same predicate for every input
the guard permits. The reach is still unknown, and check 2 stays open.

## What I compiled, and with what

I wrote the two spellings as LLVM IR. I copied the shape from
`SPULLVMRecompiler.cpp`: `BIZ` at `:9356`, `BINZ` at `:9417`, `BIHZ` at `:9449`,
`BRZ` at `:9684`. The guard is
`match_expr(c, sext<VT>(match<bool[N]>()))`, so the register holds a
sign-extended lane mask. The IR therefore holds the producer, which is an `icmp`
and a `sext`. The IR also stores the register, because the block end writes every
SPU register back to the state.

Two toolchains compiled the same file:

| toolchain | clang | why |
| --- | --- | --- |
| NDK `28.2.13676358` | 19.0.1 | nearest to the LLVM the JIT links |
| NDK `29.0.14206865` | 21.0.0 | the current NDK |

The JIT links LLVM **19.1.7** — `3rdparty/llvm/llvm`, commit `cd708029e0b2`.
The target flags are
`-target aarch64-linux-android21 -mcpu=cortex-a78+sha3+dotprod+i8mm`, which is
the JIT line `cpu=cortex-a78 attrs=+sha3,+dotprod,+i8mm,-sve,-sve2`.
`cortex-a78` carries no SVE, so the two negatives add nothing.

**The JIT runs no InstCombine.** Its pipeline is EarlyCSE, SimplifyCFG, DSE,
LICM and ADCE (`SPULLVMRecompiler.cpp:3547-3553`), plus the fork's own transform
passes (`CPUTranslator.cpp:592`). The codegen level is `Aggressive`
(`util/JITLLVM.cpp:1163`). So each file compiled twice: once at full `-O3`, and
once with `-Xclang -disable-llvm-passes`, which keeps codegen at `-O3` and
removes the IR pipeline. The second run is the faithful one.

## The two sequences, read from the assembly

All four combinations — two clang versions by two pipelines — give the same two
sequences. The `cmgt` and the `str q0` belong to the producer and to the
register write, so both forms carry them.

**The movemask spelling, which the recompiler emits today:**

```
adrp   x8, .LCPI0_0
cmgt   v0.4s, v0.4s, v1.4s          ; the producer
ldr    q1, [x8, :lo12:.LCPI0_0]     ; the weight vector 01 02 04 08 ... 80
str    q0, [x0]                     ; the register write
and    v0.16b, v0.16b, v1.16b
ext    v1.16b, v0.16b, v0.16b, #8
zip1   v0.16b, v0.16b, v1.16b
addv   h0, v0.8h
fmov   w8, s0
tbnz   w8, #15, .LBB0_2
```

**The lane-extract spelling, which the same function already carries as its
fallback:**

```
cmgt   v0.4s, v0.4s, v1.4s          ; the producer
mov    w8, v0.s[3]                  ; the UMOV alias
str    q0, [x0]                     ; the register write
cbz    w8, .LBB1_2
```

Count the work that belongs to the branch, and leave out the producer and the
register write:

| form | instructions | which |
| --- | --- | --- |
| movemask, word | **8** | `adrp`, `ldr q`, `and`, `ext`, `zip1`, `addv`, `fmov`, `tbnz` |
| lane extract, word | **2** | `umov`, `cbz` |
| movemask, halfword | **9** | the same, then `tst w, #0x3000` and `b.eq` |
| lane extract, halfword | **2** | `umov w, v.h[6]`, `cbz` |

The published disassembly starts at `ldr q2, [x9]`, so the on-device cache
shares the `adrp` between sites. The saving is therefore **6 instructions** for
the word pair and **7** for the halfword pair, or 5 and 6 if the `adrp` stays.

`ext` + `zip1` builds the mask because `trunc<bool[16]>` reads **bit 0** of each
byte, not bit 7. LLVM never selects the `SHRN` trick here.

## The 64-bit and halfword variants behave the same way

`VT` can be `s64[2]`, and `BIHZ` also accepts `s8[16]` and `s16[8]`. Every one
gives the same movemask sequence. The halfword form keeps `tst w, #0x3000` at
every lane width, so LLVM does not reduce the two-bit test to one bit even when
the producer makes the two bits equal.

## One case where the lane extract costs 3, not 2

At full `-O3`, and only when the SPU register is dead after the branch, LLVM
folds `extract(sext(cmp), 3)` into `xtn v0.4h, v0.4s` plus `umov w8, v0.h[3]`
plus `tbz w8, #0`. That is 3 instructions, still against 8. InstCombine performs
that fold, and the JIT does not run InstCombine, so the JIT gets 2.

## The hardware rows, for A715 and A710

`config.yml` puts the SPU threads on `CPU5` and `CPU6`, which are the A710 and
A715 cluster. The rows come from the vendored guides in
[`docs/hardware/`](../hardware/).

| instruction | A715 lat | A715 thr | A715 pipes | A710 lat | A710 thr | A710 pipes |
| --- | --- | --- | --- | --- | --- | --- |
| `LDR` vector, unsigned immed | 6 | 3 | `L` | 6 | 3 | `L` |
| `AND` vector | 2 | 2 | `V` | 2 | 2 | `V` |
| `EXT` | 2 | 2 | `V` | 2 | 2 | `V` |
| `ZIP1` | 2 | 2 | `V` | 2 | 2 | `V` |
| **`ADDV` 8B/8H** | **5** | **1** | **`V1`, `V`** | **4** | **1** | **`V1`, `V`** |
| **`FMOV`, vec to gen reg** | **4** | **2** | `V` | **2** | **1** | `V` |
| `UMOV`/`SMOV`, element to gen reg | 2 | 1 | `V` | 2 | 1 | `V` |

The two cores disagree on two rows. A715 pays 5 for `ADDV` 8H and 4 for `FMOV`;
A710 pays 4 and 2. The A715 table earlier in this document gives the A715
numbers, and they stand.

The dependency chain from the producer to the branch is the number that moves
most. The movemask form chains `and` 2, `ext` 2, `zip1` 2, `addv` 5, `fmov` 4,
which is **15 cycles on A715** and 12 on A710. The lane-extract form chains one
`umov`, which is **2 cycles** on both. `ADDV` also sits on `V1`, the pipe that
carries every vector shift, and `UMOV` runs on all `V` pipes.

## The semantics: the two spellings agree, and the guard is why

`trunc<bool[16]>` reads bit 0 of each byte. `bitcast<s16>` then puts byte *i* at
bit *i*, because AArch64 is little-endian. Byte 15 holds the top byte of word 3,
so bit 15 of the mask is bit 24 of the preferred slot. The guard forces every
lane to `0x00...0` or `0xff...f`, so bit 24 of word 3 is zero exactly when word 3
is zero. `extract(get_vr(op.rt), 3) == 0` reads word 3, because `get_vr` defaults
to `u32[4]` (`SPULLVMRecompiler.cpp:799`).

I did not stop at the argument. I compiled the four predicates as LLVM IR and ran
them on the host, which is also little-endian:

| population | patterns | mismatches |
| --- | --- | --- |
| word forms, every lane 0 or -1 | 16, exhaustive | **0** |
| halfword forms, every byte 0 or -1 | 65,536, exhaustive | **0** |
| word forms, arbitrary bytes | 200,000 random | 100,127 |
| halfword forms, arbitrary bytes | 200,000 random | 50,227 |

**The two spellings are equivalent for every input the guard permits, and for
nothing else.** The last two rows matter as much as the first two. They show the
`sext` guard is load-bearing, so a change must keep the guard or must delete the
fast path and fall through. The eight fallbacks already carry the correct
predicate: `extract(get_vr(op.rt), 3)` for the four word opcodes, and
`extract(get_vr<u16[8]>(op.rt), 6)` for the four halfword opcodes.

## Check 2 is open, and no artifact in this repo can close it

The 1,402 count weighs compiled bytes. It says nothing about execution. This repo
holds the proof that the two differ by orders of magnitude: **two instructions in
one 64-byte SPU block are about 20% of gameplay cycles**, and those two
instructions are 0.0004% of the corpus
([`jit-emitted-code.md`](jit-emitted-code.md)). A compiled-byte share therefore
bounds nothing in either direction.

No profile artifact is stored in this repo. `debug-profiles/` holds emulator
configuration, not samples. `debug-captures/` holds power JSON and wait-profiler
lines. So no existing file can weight this candidate.

One published number does bound it from one side. The symbolized gameplay
profile — 120,782 samples — resolved the largest JIT cost to `__spu-cx00cc4`, a
poll loop with no branch lowering in it. It holds about 20% of gameplay cycles,
and this change cannot touch it. An earlier gameplay profile — 119,662 samples,
a different run — puts all JIT code at 47.88%. The candidate competes for what
is left, and the two profiles are not the same run.

**The run that would weight it.** One boot, on the same title and the same
gameplay scene as the corpus:

1. Set `debug.rpcsx.thor.jit_perf_map=1` and
   `debug.rpcsx.thor.spu_native_object_cache=1` before the boot.
2. Record with `simpleperf` for the same duration as the 120,782-sample profile.
3. Pull `perf-<pid>.map` and pull the `spu-native-v2` cache from the same boot.
4. Disassemble the cache and record the offset of every `addv h, v.8h` that a
   `zip1` feeds.
5. Join the sample addresses to `(symbol, offset)` through the map, and sum the
   samples that land on those 7-instruction runs.

The result is the honest weight: the share of gameplay cycles that the sequence
holds. Do not run this on a device another session is using.

## An attribution gap that must close first

The section above counts 1,402 `addv h, v.8h` fed by a `zip1`. Only **786** of
them carry a terminator these eight opcodes produce: 748 `tbnz`/`tbz` on bit
`#0xf`, and 38 `tst w, #0x3000`. The other **616** are not attributed.

I tested the obvious explanation and it failed. A halfword site whose producer
has 16-bit or wider lanes makes mask bits 12 and 13 equal, so LLVM could test one
bit. It does not: every lane width still emits `tst w, #0x3000`.

So the 1.1% figure covers at most 786 confirmed sites until somebody attributes
the other 616. This is the same failure this document already records once: the
count was right and the attribution was not. The disassembly needed to close it
is the same artifact the run above pulls.

## What this section establishes, and what it does not

* **Compiled and read:** both assembly sequences, at two clang versions and two
  pipelines, at the JIT's target.
* **Compiled and run:** the equivalence of the two predicates, exhaustively over
  the guarded population.
* **Reasoned, not measured:** the cycle counts of the two dependency chains. They
  come from the vendored guides, not from the device.
* **Not established:** what fraction of gameplay time the sequence holds, and how
  many of the 1,402 sites are these eight opcodes.

---

# The change is implemented, behind a gate, and the gate is off

This section records what the code does now. **It records no measurement.** No
agent has run the A/B on the device. The default is `0`, so a normal build emits
the movemask and nothing changes.

## The gate

`app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/thor_spu_branch_extract.h` holds one
runtime gate:

    debug.rpcsx.thor.spu_branch_extract = 1     (default 0)

`thor::spu_branch_extract()` reads the property into a function-local static. The
helper also accepts the environment variable `RPCSX_THOR_SPU_BRANCH_EXTRACT`, for
a host run. An absent value gives `false`.

The `#if` guard is `__aarch64__`, which the compiler predefines. It cannot go
missing from one CMake target, unlike `ANDROID`. On any other architecture the
helper is a constant `false`, because the movemask is the correct x86 form.
`thor_host_mutex_spin_iters` lost its property branch to a missing `-DANDROID`
once, and the A/B would have reported no effect with both arms identical.

## The read is hoisted

`spu_llvm_recompiler` copies the result into `m_thor_spu_branch_extract` at
construction (`SPULLVMRecompiler.cpp:101`). The eight opcode handlers read the
member. They never call the accessor.

A function-local static costs a guard-variable acquire load on every call. The
handlers run once per compiled branch, inside the compile loop. This fork already
put a static in a hot path once, with `get_thor_pause_mode`; the comment on
`pause()` in `rx/asm.hpp` records what that cost.

## The eight sites

Each site selects between the two spellings **inside** the guarded block:

```cpp
const auto cond = m_thor_spu_branch_extract
    ? eval(extract(get_vr(op.rt), 3) == 0)
    : eval(bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) >= 0);
```

The movemask arm is the code that was there before. It is unchanged.

| opcode | guard line | gate line | extract arm | movemask arm |
| --- | --- | --- | --- | --- |
| `BIZ` | 9361 | 9366 | `extract(get_vr(op.rt), 3) == 0` | `... >= 0` |
| `BINZ` | 9426 | 9431 | `extract(get_vr(op.rt), 3) != 0` | `... < 0` |
| `BIHZ` | 9462 | 9467 | `extract(get_vr<u16[8]>(op.rt), 6) == 0` | `... & 0x3000) == 0` |
| `BIHNZ` | 9498 | 9503 | `extract(get_vr<u16[8]>(op.rt), 6) != 0` | `... & 0x3000) != 0` |
| `BRZ` | 9702 | 9710 | `extract(get_vr(op.rt), 3) == 0` | `... >= 0` |
| `BRNZ` | 9781 | 9789 | `extract(get_vr(op.rt), 3) != 0` | `... < 0` |
| `BRHZ` | 9829 | 9837 | `extract(get_vr<u16[8]>(op.rt), 6) == 0` | `... & 0x3000) == 0` |
| `BRHNZ` | 9877 | 9885 | `extract(get_vr<u16[8]>(op.rt), 6) != 0` | `... & 0x3000) != 0` |

## The guard holds at all eight sites, and I checked before I changed them

The equivalence of the two spellings depends on the `sext` guard. A site that
reaches the lane extract without the guard is a **wrong** branch. A faster and
wrong branch lowering is the worst result available here.

Every one of the eight sits inside
`if (auto [ok, x] = match_expr(c, sext<VT>(match<bool[std::extent_v<VT>]>())); ok)`.
`llvm_sext::match` (`CPUTranslator.h:2001`) accepts the register value only when
it is an `llvm::Instruction::SExt` cast, when the destination type is exactly
`VT`, and when the source matches `bool[N]`. A sign extension from `i1` writes
all-zeros or all-ones into every lane, by definition. So no gated site can see a
mixed lane.

| opcode | `match_vr` types the guard admits | fallback the extract arm copies |
| --- | --- | --- |
| `BIZ`, `BINZ`, `BRZ`, `BRNZ` | `s32[4]`, `s64[2]` | `extract(get_vr(op.rt), 3)` |
| `BIHZ`, `BIHNZ`, `BRHZ`, `BRHNZ` | `s8[16]`, `s16[8]`, `s32[4]`, `s64[2]` | `extract(get_vr<u16[8]>(op.rt), 6)` |

Two further checks came back clean:

* **The interpreter path cannot reach the gate.** `match_vr` returns an empty
  match when `m_block` is null, and `m_block` is null under `m_interp_magn`. So
  the interpreter builder keeps the fallback it always used.
* **The extract arm is the fallback each function already carries**, not new
  arithmetic. `BIZ` falls through to `extract(get_vr(op.rt), 3) == 0` at
  `:9381`, and `BIHZ` to `extract(get_vr<u16[8]>(op.rt), 6) == 0` at `:9482`.

**I changed all eight. I left none on the movemask path.**

One movemask remains in the file and it is not a branch. `GBB`'s portable
fallback at `:5881` writes the mask into a register as a value. The gate does not
touch it.

## The source contract test, and the proof it can fail

`tools/test_thor_spu_branch_extract.py` asserts four things: the gate exists, the
default is `0`, all eight sites are gated with the correct lane and polarity, and
the property read is hoisted into the member. It also asserts that the `sext`
guard sits above every gated site, and that no movemask branch predicate escapes
the gate.

A check nobody has shown can catch anything is not trusted here. I rebuilt five
regressions on a scratch copy of the two files. The test exits `1` on every one,
and exits `0` again after the restore:

| regression | what the test reported |
| --- | --- |
| `BRHNZ` loses its gate | `BRHNZ has 0 gated branch lowering(s)`, plus an ungated movemask |
| the default flips to on | `an absent property does not default to off` |
| one site calls the accessor | `2 call(s) to thor::spu_branch_extract(), expected 1` |
| `BIHZ` loses the `sext` guard | `reaches the lane extract with no sext guard above it` |
| `BRHZ` extracts lane 7 | `extract arm is ... 7) == 0, expected ... 6) == 0` |

## The gate reaches the shipped library

This fork has shipped three gates that compiled, linked and did nothing. So the
build was checked against the binary, not against the source.

`./gradlew assembleThortest -PrpcsxThorDebuggable=1` gives **0 errors**, and 0
`unused parameter` or `unused variable` warnings. Then, in the stripped
`librpcsx-android.so` that the APK packages:

| check | result |
| --- | --- |
| `debug.rpcsx.thor.spu_branch_extract` in the stripped `.so` | **1** |
| the same string inside `lib/arm64-v8a/` of the APK | **1** |
| `RPCSX_THOR_SPU_BRANCH_EXTRACT` in the stripped `.so` | 1 |
| `debug.rpcsx.thor.lv2_spin`, a control that works | 1 |

The string alone proves little, so the code was read as well. `llvm-nm` on the
unstripped library finds `thor::spu_branch_extract()::enabled`, its guard
variable, and the lambda. `llvm-objdump` on the lambda shows an `adrp`/`add` to
`0x15c9a8`, a `bl __system_property_get`, and a `getenv` fallback. The two
addresses hold `debug.rpcsx.thor.spu_branch_extract` and
`RPCSX_THOR_SPU_BRANCH_EXTRACT`. So the property read is real.

## How to measure it

The device is shared. Do not run this while another session holds the Thor.

The A/B needs a cache clear, because the SPU native object cache key hashes the
optimized IR. A cached object from the movemask arm stays valid until you clear
it. `adb shell` **cannot** unlink under `files/cache/cache/`: that directory is
`drwxrws---`, but `BLUS30161/`, `ppu-*/` and `spu-native-v2/` below it are
`drwxr-s---`. Use `run-as`, which needs a debuggable build.

1. Disassemble the **old** cache first, before you clear it. Reproduce the
   published `addv h` count of 1,402 on the pre-change corpus. That step proves
   the pipeline works. A broken pipeline returns zero for every mnemonic and
   reads as a perfect result.
2. Set `debug.rpcsx.thor.spu_native_object_cache=1`. The cache is off by default,
   and a boot without it writes nothing.
3. Clear the cache with
   `adb shell run-as net.rpcsx.easy rm -rf files/cache/cache/BLUS30161`.
4. Confirm the clear with a re-`ls` that reads **0**. Never trust the exit status
   of the `rm`.
5. Boot the title with the property at `0`. Record `p95` frame time from
   `dumpsys SurfaceFlinger --latency` on the `(BLAST)` layer. Record CPU.
6. Repeat step 3, step 4 and step 5 with
   `debug.rpcsx.thor.spu_branch_extract=1`.
7. Pull `spu-native-v2` from both boots. Disassemble both with NDK
   `llvm-objdump`. Count `addv h, v.8h` fed by a `zip1` in both.

The counts decide whether the change landed. The `addv h` count must fall in the
second arm, and the `umov w, v.s[3]` count must rise. `SPU Runtime: Built 1188
functions.` in `RPCSX.log` tells a real boot from a boot that never reached the
SPU runtime.

Alternate the arms and repeat them. A conclusion from one boot is a conclusion
about one boot.

**Two cautions on the frame-time and CPU arms.** Eternal Sonata CPU cannot
resolve anything below about 1.4 cores, so a small CPU delta means nothing on
that title. And `-PrpcsxThorDebuggable=1` only changes the APK manifest now;
`build.gradle.kts` pins `-DCMAKE_BUILD_TYPE=RelWithDebInfo`, so the native
optimization level matches a release build.

## The reach question is still open, and it is bigger than a rounding error

**Only 786 of the 1,402 `addv h`←`zip1` sites are attributable to these eight
opcodes.** 748 carry a `tbnz`/`tbz` on bit `#0xf`, and 38 carry a
`tst w, #0x3000`. The other **616 are unexplained**.

So the gate can improve at most 786 sites, until somebody attributes the
remaining 616. Whatever emits those 616 is a different lowering, and this gate
does not reach it. The disassembly in step 7 above is the artifact that closes
the gap: classify every unattributed `addv h` by the instruction that follows the
`fmov`.

And the site count weighs compiled bytes, not execution. This repo holds the
proof that the two differ by orders of magnitude: two instructions in one 64-byte
SPU block hold about 20% of gameplay cycles, and they are 0.0004% of the corpus.
A compiled-byte share bounds nothing in either direction.
