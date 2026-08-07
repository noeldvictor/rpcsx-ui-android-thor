# Instruction selection on this core

How the AArch64 backend is actually used here: what the per-core optimization
guides say, which lowerings were rewritten, and the x86 habits that produced
the defects worth hunting.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## The core optimization guides, and the column that decides borderline cases

`docs/hardware/` vendors Arm's Non-Confidential Software Optimization Guides for
the Cortex-X3 (prime) and Cortex-A710 (older mid cluster). They carry the three
numbers no amount of source reading produces: **execution latency, execution
throughput, and utilized pipelines**.

The third column is the one that is easy to skip and often decides the answer:

    V    FP/ASIMD 0/1/2/3   all four pipes
    V01  FP/ASIMD 0/1       two
    V13  FP/ASIMD 1/3       two
    V0   FP/ASIMD 0         one

X3 figures for every instruction this fork's codegen work actually selected:

| instruction | latency | throughput | pipes | used by |
| --- | --- | --- | --- | --- |
| `EOR`/`BIC`/`AND`/`ORR`/`ORN`/`MVN` | 2 | 4 | `V` | `ANDC`, `ORC`, `NOR`, `NAND` |
| **`BCAX`/`EOR3`** | 2 | **1** | **`V0`** | `SHUFB` selector, `EQV` |
| `SQADD`/`UQADD`/`URHADD` | 2 | 4 | `V` | `VMSUMSHS`, `AVGB` |
| `UMAXP`/`UMAX`/`UMIN` | 2 | 4 | `V` | `scan16_rdata` |
| `UMAXV`/`UMINV` (reduce) | 2 | 2 | `V13` | reduction toolkit |
| `CNT`/`CLZ`/`CLS` | 2 | 4 | `V` | `CNTB`, `CLZ` |
| `UABD` | 2 | 4 | `V` | `ABSDB`, block checksum |
| `XTN` | 2 | 4 | `V` | plain narrow |
| **`SQXTN`/`UQXTN`** | **4** | **2** | **`V13`** | `VSUMSWS`, `VPKUHUS` |
| `TBL`, 1-2 table regs | 2 | 2 | `V01` | `VPERM` |
| **`TBX`, 2 table regs** | **4** | **2** | `V` | `SHUFB` |

Most of the sweep's choices are confirmed cheap: `SQADD`, `UMAXP`, `CNT` and
`UABD` are all latency 2 at full rate on all four pipes, so `VMSUMSHS` and
`scan16_rdata` are landing on the best instructions available.

**`BCAX` is the exception, and the guide explains a measurement this document
had already recorded without accounting for it.** `BCAX` replaces a dependent
`BIC` then `EOR`. Read the table:

| | latency | throughput |
| --- | --- | --- |
| `BIC` then `EOR`, dependent | 2 + 2 = **4** | 4/cycle, spread across `V` |
| `BCAX` | **2** | **1/cycle, `V0` only** |

So the guide predicts a **2.00x latency win and a throughput loss**. Against the
`bcax_bench` result recorded in
[`power-and-thermal.md`](power-and-thermal.md), run before any of this was read:

| shape | predicted | X3 measured | A715 | A510 |
| --- | --- | --- | --- | --- |
| latency, serial chain | **2.00x** | `1.96x` | `2.01x` | `2.00x` |
| throughput, independent chains | **below 1.0** | `0.94x` | `1.00x` | `2.02x` |

The latency row matches the published figure to within measurement noise on all
three core types, which is a strong check on the bench itself.

**The throughput row is where it gets interesting, because the two big core types
disagree and the guides say exactly why.** The A710 guide gives BCAX the same
latency 2, throughput 1, `V0`-only treatment as X3 — but **A710 has only two
FP/ASIMD pipes where X3 has four**, so its `EOR`/`BIC` are throughput 2, not 4:

| | X3 (4 V pipes) | A710/A715 (2 V pipes) |
| --- | --- | --- |
| `BIC` + `EOR`, independent | 2 ops at 4/cyc = **0.5 cyc** | 2 ops at 2/cyc = **1 cyc** |
| `BCAX` | 1 op at 1/cyc on `V0` = **1 cyc** | 1 op at 1/cyc on `V0` = **1 cyc** |
| predicted ratio | **0.5x** | **1.0x** |
| measured | `0.94x` | **`1.00x`** |

A715 lands on the predicted `1.0x` exactly. X3 does not reach its predicted
`0.5x` floor, which means four independent chains do not saturate a single pipe;
a wider bench would look worse. So the prediction is a bound on X3 and an
equality on A715, and the measurement is consistent with both.

The mechanism is now precise: **the wider the core, the worse BCAX's single-pipe
restriction looks**, because the pair it replaces has more pipes to spread across
while BCAX stays pinned to `V0`. That is why the prime core is the one that
loses. The earlier explanation here — "the big cores have enough vector pipes to
issue the old pair in parallel" — was directionally right and now has a
mechanism, a pipe count, and two numbers that agree with it.

A510 has no published guide, but its `2.02x` on *both* shapes fits a narrow core
with a vector unit shared between core pairs, where halving the operation count
dominates whatever pipe it issues on.

The general rule is now explicit, and it is the reason to keep these PDFs: **an
instruction that saves an operation can still lose if it issues on one pipe where
the sequence it replaces issues on four.** Instruction count is not the metric;
latency, throughput and pipe are, and only the per-core guide has them.

### Forwarding regions, and why the BCAX bench measured the wrong shape

Section 4.7 then takes a cycle back, and it is the sharpest thing in the guide:

> The effective latency of FP and ASIMD instructions as described in section 3 is
> increased by one cycle if the producer and consumer instructions are not part
> of the same forwarding region.

The regions are listed in Table 4-1. Two matter here:

- **Region 1** — ASIMD ALU, shift, insert/move, abs/cmp/max/min, **and the ASIMD
  miscellaneous instructions in Table 3-18**.
- **Region 3** — ASIMD Crypto and SHA1/SHA256.

`TBL`/`TBX` live in Table 3-18, so they are region 1. `BCAX` lives in Table 3-21,
the Cryptography extensions, so it is region 3. **Our `SHUFB` emits `bcax`
immediately followed by the `tbx2` that consumes it, which is a region 3 to
region 1 forward, and therefore pays the extra cycle.** The sequence it replaced
does not: `BIC` and `EOR` are region 1 and so is `TBX`, so that chain forwards
within one region throughout.

Redo the comparison for the code that actually exists:

| chain | region path | effective latency |
| --- | --- | --- |
| `BIC` -> `EOR` -> `TBX` | 1 -> 1 -> 1 | 2 + 2 = **4** |
| `BCAX` -> `TBX` | **3 -> 1**, cross-region | 2 + 1 = **3** |

So BCAX still wins, and the change stays. But it wins by **1.33x, not the 2.00x**
recorded above, and the reason the bench said 2.00x is that **the bench measured a
serial chain of BCAX feeding BCAX** — region 3 into region 3, same region, no
penalty. That shape does not occur anywhere in this codebase.

This is worth more than the cycle it costs. The bench was well built, ran on the
real device, agreed with the published latency figures to two decimal places, and
still described something the emulator never executes. **A microbenchmark
inherits the forwarding behaviour of its own chain, not of the code it is standing
in for**, and on this core that is worth a cycle in either direction. When
benchmarking a lowering, the consumer has to be the real consumer.

The same caveat applies to `EQV`, the other `bcax()` caller, and cannot be
resolved from the source alone: its result feeds whatever the guest program does
next, so the penalty applies whenever that is an ordinary ASIMD op and vanishes
when it is another crypto-class one. Situational rather than settled.

**This holds on the mid cluster too, and checking that turned up an erratum in
Arm's own document.** The A710 guide defines the same five forwarding regions
with the same membership, so `BCAX` feeding `TBX` crosses regions on A710 and
A715 as well as on X3 — the finding is not specific to the prime core.

But the cross-reference does not survive. **A710's section 4.7 places "the ASIMD
miscellaneous instructions in table 3-18" in region 1, and A710's Table 3-18 is
`AArch64 Tag store instructions`.** The A710 guide covers AArch32 as well, so its
tables are numbered differently throughout: its ASIMD miscellaneous table is
**3-33** and its Cryptography extensions table is **3-39**. The number 3-18 is
the one the *X3* guide uses for ASIMD miscellaneous, so the sentence appears to
have been carried across revisions without renumbering.

Resolved by content rather than by number: `TBL`/`TBX` are listed under "ASIMD
table lookup" inside A710's Table 3-33, ASIMD miscellaneous, which is what region
1 names. `BCAX` is under "Crypto SHA3 ops" in Table 3-39, Cryptography
extensions, which is region 3.

Worth writing down for two reasons. Anyone following that cross-reference lands
on tag stores and concludes the section is incoherent. And more generally:
**when two guides for related cores disagree, check whether the tables are
numbered the same before assuming the content differs.** Here the content is
identical and only the numbering moved.

Two further consequences worth carrying, since neither is obvious from reading
instruction tables in isolation:

- **`SQXTN` is excluded from region 1 as a producer** (Table 4-1, note 2, and the
  bullet list under it). It is already latency 4 at half rate on two pipes, so a
  consumer outside its region makes an expensive instruction more expensive. It
  still beats the 9-instruction emulated clamp in `VSUMSWS` by a wide margin;
  this is a reason not to reach for it casually, not a reason to revisit that.
- **ASIMD reductions are in no region at all**, along with FP divide/sqrt and
  ASIMD integer multiply. So the `ADDV`/`UMAXV` tail of the `scan16_rdata`
  rewrite pays the extra cycle on whatever consumes it. That rewrite went from 65
  instructions to 42 with seven fewer vector-to-GPR transfers, so one cycle does
  not threaten it, but it does mean the reduction toolkit in the movemask section
  should not be assumed free at its published latency.

Note also that `SQXTN` is not free — latency 4 and half rate on two pipes, versus
2 and full rate on four for plain `XTN`. It still wins enormously where it was
adopted, since `VSUMSWS` went from a 9-instruction emulated clamp to it, but do
not reach for it as though it were an ordinary narrow.

The A510 column is where BCAX wins on both shapes, which fits a narrow core with
a vector unit shared between core pairs: there, halving the operation count
matters more than which pipe it lands on.

### Chapter 4, checked against this codebase

The guides' "Special considerations" chapter is the non-obvious half. Three of
its rules touch code here, and all three come back clean, which is worth
recording so the checks are not repeated:

- **4.4 Load/Store alignment.** X3 penalizes quad-word loads that are not 4-byte
  aligned and **stores that cross a 32-byte boundary**. An `STP q, q` is exactly
  32 bytes, so a base that is 16-byte but not 32-byte aligned would penalize
  every store in the 128-byte reservation copy — the hottest copy in the
  emulator. It does not happen: `spu_thread::rdata` is `alignas(64)`, so all four
  32-byte sub-blocks start on a 32-byte boundary, and the guest side is a
  128-byte reservation granule. Both rules already satisfied.
- **4.5 Store-to-load forwarding** requires the load to start at the start or
  middle of the older store, and a load over 8 bytes can forward from at most two
  stores. The reservation seqlock re-reads a counter rather than the copied data,
  so it does not depend on forwarding a 128-byte copy.
- **4.11 Instruction fusion.** `CMP`/`CMN`/`TST` + `B.cond` fuse when adjacent
  and not shifted or extended. This is a compiler concern, not something to
  hand-write, and clang already emits the fusible forms.

**And one thing the guide does not say, recorded because the temptation was
real.** `busy_wait()` spins on `MRS CNTVCT_EL0`, and section 4.10 explains that
non-renamed special-purpose register accesses can be forced non-speculative,
in-order, or flush-inducing — which would make that spin far worse than a plain
loop. But `CNTVCT_EL0` **is not in Table 4-2**, which lists only `APSR`, `DAIF`,
`FPCR`/`FPSR`, `NZCV`, `SP` and similar. The guide therefore says nothing about
the timer read, and inferring a penalty from the surrounding prose would be the
same mistake as the ESR `ISV` entry in [`ledger.md`](ledger.md): reading a
manual's general statement
as though it covered a specific case it does not list. The 15.6 us figure for
`busy_wait(300)` stands on the device measurement alone, which is enough.

### The guides say nothing about atomics, and that closes off one line of enquiry

Searched both guides for the AArch64 atomic instruction family. The result is a
clean zero:

| searched | X3 | A710 |
| --- | --- | --- |
| `CAS` | 0 real hits | 0 real hits |
| `LDADD` / `LDSET` / `SWP` | 0 | 0 |
| `LDXR` / `STXR` / `LDAXR` | 0 | 0 |
| "atomic" / "exclusive" | 0 | 0 |

The apparent `CAS` matches are the substring inside "cases" and "broadcast", and
A710's lone `SWP` is `VSWP`, an ASIMD register swap. **There is no latency,
throughput or pipeline data for a single atomic instruction in either document.**

This matters because it bounds what the manuals can settle. The largest open item
in `ledger.md` is replacing the x86 TSX reservation path with **per-reservation
LSE locking**, and the obvious next step was to look up what `CAS` and `LDSET`
cost on these cores. They are not there, and no amount of further reading will
produce them.

The omission is coherent rather than an oversight, and the reason points at where
the win would actually come from. An atomic's cost on a multi-core part is
dominated by the **coherence state of the line it touches** — whether it is
already held exclusively, how many other cores have a copy, how far away the
point of coherence is. None of that is a property of one core's pipeline, so a
per-core optimization guide has nothing useful to say about it.

Which is exactly the shape of the LSE proposal. The current fallback contends on
`g_range_lock_bits[0]`, **a single 64-bit word**, so every SPU atomic in the
emulator serialises on one cache line across all eight cores regardless of which
guest address it is updating. Moving the lock into the per-reservation word
gives each 128-byte guest line its own 64-byte reservation entry, and therefore
its own cache line, so unrelated addresses stop interfering. The benefit is
entirely in the coherence traffic, not in the instruction selected.

So that item cannot be advanced by reading. It needs a contended measurement on
hardware, which currently needs the fixed-scene workload that is still missing.

**What these guides are not.** The Arm Architecture Reference Manual (`aarch64.pdf`,
~14,000 pages) is a different document and answers a different question. It gives
instruction *semantics* and *encodings* and contains no timing data whatsoever,
because timing is per-implementation. It is the right reference for the RawSPU
MMIO decoder in the ledger, which needs load/store encodings, and the wrong one
for any performance question. This document has already recorded one error made
by reasoning from it without checking the part — the ESR `ISV` fields, which the
architecture defines and this silicon reports as zero. Get it for encodings when
that work starts; do not consult it about speed.

## There is no movemask, and it shapes more code than it looks like

The most consequential missing x86 instruction on AArch64 is not an arithmetic
one. It is `PMOVMSKB`/`PTEST`: the ability to collapse a vector into flags or a
scalar bitmask for free. NEON has no equivalent, and every crossing from the
vector unit to a general-purpose register is an `FMOV`/`UMOV` with real latency.

This inverts a habit. On x86, "reduce each vector to a bool and combine the
bools" is idiomatic and cheap. On AArch64 it is the expensive spelling, and the
cheap one is to keep the whole computation in vector registers and cross over
exactly once, at the end.

`scan16_rdata` is the clean example. Eight `v128 != v128` compares look like
eight cheap tests; on AArch64 they are eight `SQXTN`/`FMOV`/`CSET` triples, 65
instructions with eight transfers on the critical path. `UMAXP` folds lane pairs
while preserving their order, so two rounds collapse eight 4-lane blocks into
eight lanes, one per block, each nonzero exactly when its block differs.
Weighting those lanes and adding across produces the identical bitmask in 42
instructions with a single transfer.

The reduction toolkit worth knowing, since it replaces movemask idioms:

| want | AArch64 |
| --- | --- |
| any lane nonzero | `UMAXV` / `ADDV`, then one move |
| per-block nonzero, order kept | `UMAXP` folds, no move until the end |
| bitmask of lane predicates | `AND` with a weight vector, then `ADDV` |
| all lanes equal | compare, then `UMINV` |

The counter-example matters just as much. `cmp_rdata`, immediately above
`scan16_rdata`, also looks wrong: its ARM path is a serial chain of four
`vmlaq_s16`. It is not worth touching. The multiplied values are `0`/`-1` masks,
so clang strength-reduces the multiply into `and`/`sub`, giving 29 instructions
against 28 for an XOR/OR reduction tree at comparable dependency depth. **Check
what the compiler actually emitted before rewriting the ugly-looking one.**

Correctness for this class is cheap to establish by execution and should be.
The `scan16_rdata` change was verified on the device across all 256 patterns of
which blocks differ, 64 randomised byte positions each, plus 200000 random
pairs: 216384 cases, zero mismatches. Pinned by
`tools/test_thor_arm64_scan16_rdata.ps1`.

## NEON has no 64-bit lane min/max, and two AltiVec ops pay for it

`VSUMSWS` and `VSUM2SWS` clamp a 64-bit accumulator into 32-bit range and keep
it in 64-bit lanes:

    r = min(max(sum, -0x80000000), 0x7fffffff)   // s64[2]

**NEON has no `SMIN`/`SMAX` for 64-bit lanes**, only 8, 16 and 32. So that clamp
is emulated. Measured at `-O2 -mcpu=cortex-a78` on the same IR:

| form | instructions |
| --- | --- |
| clamp kept in 64-bit lanes | **9** — `dup`/`mov` to build the constants, then `cmgt`+`bif` twice |
| clamp followed by `trunc` to 32-bit lanes | **2** — `sqxtn` does clamp and narrow together |

`SQXTN` is exactly this operation, and x86 has no 64-to-32 saturating pack to
match it, so this is ARM-favourable work being left on the floor.

**Taken, and the blocker turned out to be avoidable.** The obstacle was the line
underneath:

    set_sat(bitcast<u64[2]>(r + 0x8000'0000) >> 32);

`r` has already been clamped into `[-2^31, 2^31-1]`, so `r + 2^31` lies in
`[0, 2^32-1]` and the `>> 32` yields **zero unconditionally**. `set_sat` ORs its
argument into VSCR, so these two opcodes have never set the saturation bit.

The first instinct was to derive the flag correctly from the narrowed value, and
that is what made this look like a blocked change: it would make the bit start
working, a guest-visible difference in an op that has apparently never had it.

But correcting it is not required to take the ARM win. An expression that
provably evaluates to zero can simply be **removed**, which changes nothing
observable and frees the accumulator to be narrowed. So the clamp now truncates
to 32-bit lanes, contracts to `SQXTN`, and the dead `set_sat` is gone with a
comment recording why. The semantics question stays open on its own terms rather
than being bundled into a performance change.

Equivalence checked on device, since this rewrites result construction: 15 edge
values including both 32-bit boundaries, the 64-bit extremes and values either
side of the clamp, all pairs, plus 2,000,000 randomised pairs, comparing the
full 4-lane output of both opcodes. 4,000,450 cases, zero mismatches.

The general lesson is worth more than the two opcodes. **When a correctness
question blocks a performance change, check whether the code being removed
actually does anything.** Dead code can be deleted without answering the
question it appears to raise.

## The SPU opcode lowering audit

The recompiler expresses most opcodes as portable IR and trusts the backend. That
trust is mostly warranted, but "mostly" is not a review, so every high-frequency
SPU opcode was compiled and its AArch64 output counted. Recorded here so the
next person does not repeat it.

| SPU op | IR shape | AArch64 output | verdict |
| --- | --- | --- | --- |
| `ANDC` | `a & ~b` | `bic` | 1 instruction, optimal |
| `ORC` | `a \| ~b` | `orn` | 1 instruction, optimal |
| `SELB` | `(a & ~c) \| (b & c)` | `bit` | 1 instruction, optimal |
| `NOR` | `~(a \| b)` | `orr` + `mvn` | 2, unavoidable |
| `NAND` | `~(a & b)` | `and` + `mvn` | 2, unavoidable |
| `AVGB` | widen, `+`, `+1`, `>>1`, trunc | `urhadd` | 1 instruction, optimal |
| `ABSDB` | `umax - umin` | `uabd` | 1 instruction, optimal |
| `CNTB` | `ctpop` | `cnt` | 1 instruction, optimal |
| `CLZ` | `ctlz` | `clz` | 1 instruction, optimal |
| `XSBH`/`XSHW`/`XSWD` | `x << n >> n` | `shl` + `sshr` | 2, unavoidable |
| `SUMB` | dot with ones | `udot` | already ARM-specific |
| `SHUFB` | table lookup | `tbx2` + `bcax` | already ARM-specific |
| `CFLTS`/`CFLTU` | saturating convert | `fcvtzs`/`fcvtzu` | fixed earlier; was *wrong*, not just slow |

The three "unavoidable" entries are genuinely so. NEON has no vector NOR or
NAND, so both need an `MVN`; and there is no in-lane sign extend, because `SXTL`
widens lanes rather than extending within them. SHA-3 does not rescue `NOR` or
`NAND` either: `BCAX` computes `a ^ (b & ~c)`, and reaching `~(a & b)` from it
would require already having `~b`.

The useful conclusion is the shape of the remaining risk. **Where the IR is
portable, LLVM gets it right; where the IR encodes an x86 workaround, it does
not.** Every defect found in this codebase was in the second category —
`CFLTS`'s inverted correction, the `VPKUHUS` pre-clamp, the `llvm.bswap.i128`
spelling, `mov_rdata`'s dropped non-temporal intent. None was LLVM failing to
pick a good instruction from a clean description. So opcode-level auditing has
low yield, and auditing *corrections* has high yield.

That prediction was then tested by acting on it, and it held. Searching
`PPUTranslator.cpp` for correction shapes rather than reading opcodes in order —
`^ sext(...)` beside an operation, a `select` next to a conversion, a literal
saturation limit — turned up exactly one live instance, `VMSUMSHS`, whose tail
was a 32-bit signed saturating add written longhand because SSE has no 32-bit
packed form. `SQADD` does it in one. 12 instructions became 5, or **2 when the
module never reads VSCR**, since `set_sat` then emits nothing and only the
`SQADD` survives; the hand-rolled version could never collapse that way because
it needed the overflow mask to select its own result.

The tell was not the instruction count. It was that `VADDSWS` and `VSUBSWS`
directly beside it already delegate to `add_sat`/`sub_sat`. **An operation
hand-rolling what its immediate siblings delegate is worth a second look**, and
that heuristic is cheaper to apply than reading every opcode.

## When LLVM already does it, and when it does not

Measure the baseline before writing a lowering. LLVM's AArch64 backend is
better at this than it looks, and three of the four opportunities on the first
version of that list evaporated on contact.

- **It forms `BCAX` and `EOR3` by itself** from `a ^ (b & ~c)` and `a ^ b ^ c`
  whenever `+sha3` is advertised, on **value** operands.
- **Constant operands defeat it.** With a constant mask, instcombine folds the
  `NOT` away first (`c & ~0x60` becomes `c & 0x9f`), so the pattern never
  matches and you get `movi`/`and`/`movi`/`eor`. This is exactly why the
  `SHUFB` selector and `EQV` emit `bcax()` by hand and why there is no `eor3()`
  helper: no site needs one.
- **It already fuses the AltiVec multiply-highs.** `VMHRADDSHS` lowers to
  `smlal`/`smlal2`/`ssra`/`sshr`/`saddw2`/`sqxtn`, 11 instructions, and 13 with
  the SAT indicator. An exact `SQRDMULH` rewrite measured 12. One instruction
  saved is not worth the risk, so it was not taken. The 1-instruction
  `sqrdmlah` form only exists if you give up the SAT flag and the
  `a == b == INT16_MIN` case, where PowerPC does not saturate the intermediate
  and the true value `32769` cannot be held in a 16-bit lane.
- **`FLAGM` is unreachable.** LLVM 20.1.3 exposes no `RMIF`/`SETF8`/`SETF16`/
  `AXFLAG` intrinsics, and PPU condition emulation is value-based
  (`CreateICmp` into CR fields) rather than host-flag based, so there is
  nothing to map even with inline asm.

## The x86-habit audit

The most productive review of this codebase is not "where can we add an ARM
instruction" but "where does portable code encode an x86 assumption". Three of
those found so far, and two were wrong rather than merely slow. The pattern to
hunt is a decision that is *correct reasoning on x86* applied unconditionally.

| site | the x86 assumption | what it does on ARM |
| --- | --- | --- |
| PPU pass pipeline | none; the gate was just never revisited | **no IR optimization at all**, not even EarlyCSE |
| PPU `FCTIW`/`FCTIWZ`/`FCTID`/`FCTIDZ` | `CVTSD2SI` yields INT_MIN on overflow, so XOR-correct it | `FCVTNS`/`FCVTZS` saturate, so the correction *inverts* the result, four times over, plus NaN |
| SPU `CFLTS` | `CVTTPS2DQ` yields `0x80000000` on overflow, so XOR-correct it | `FCVTZS` already saturates, so the correction *produces* the wrong value |
| `m_use_fma` | FMA is optional; allowlist CPU names | FMA is mandatory, so the allowlist can only fail to enable it |
| MFC DMA width | AVX aligned moves want a 32-byte aligned constant address | `LDP`/`STP` pair at any alignment, so the gate only halves throughput |
| `VPKUHUS`/`VPKUWUS` | `PACKUSWB` narrows signed to unsigned, so pre-clamp each half | blocks `UQXTN`; the sibling shape gets it in two instructions |
| `mov_rdata_nt` | streaming stores are an x86 intrinsic, so everyone else gets `memcpy` | the non-temporal intent is silently dropped; `STNP` restores it for free |
| `scan16_rdata` | `PTEST` sets flags directly, so eight separate vector compares are nearly free | `gv_testz` narrows and moves to a GPR, so it is eight `SQXTN`/`FMOV`/`CSET` triples with the transfers on the critical path |
| `VMSUMSHS` | SSE saturates at 8 and 16 bits only, so a 32-bit saturating add must be written out longhand | `SQADD` does it in one, and the hand-rolled overflow mask blocks `set_sat` from vanishing when the module never reads VSCR: 12 instructions where 2 suffice |
| PPU 128-bit guest access | `llvm.bswap.iN` is the portable spelling, and on x86 a 16-byte reverse is a shuffle anyway | forces the value through GPRs: `ldp`, two `rev`, `fmov`, `mov Vd.d[1]`, versus `ldr q`/`rev64`/`ext` |

That last one is the widest-reaching of the set. PS3 memory is big-endian, so
**every** VMX load and store is byte-reversed, and expressing it as an integer
byteswap gives the backend no way to keep the value in the vector unit. Six
instructions with two GPR-to-SIMD transfers become three that never leave SIMD.
Only the 128-bit case needs the special case; narrower accesses already lower to
a single `REV`.

Two traps while verifying this class:

- **The build uses LTO, so the `.o` files are bitcode.** `llvm-objdump` reports
  "not recognized as a valid object file" and any instruction count taken from
  them reads zero, which looks exactly like "my change did nothing". Check
  codegen with a standalone compile of the same shape, or against the linked
  `.so`.
- **Loop-idiom recognition undoes non-temporal stores.** A tidy loop of
  `__builtin_nontemporal_store` gets rewritten back into `memcpy` with the
  metadata dropped. Write those out.

The PPU interpreter is a useful oracle here. It implements the same conversions
and already did the right thing on ARM, saturating and mapping NaN to the
minimum, while the recompiler inverted them. When a shared lowering looks
suspicious, check whether the interpreter agrees before assuming the semantics.

Verified on device from five freshly compiled SPU blocks, identified by diffing
the `spu-native-v2` listing across a boot rather than by clearing the cache,
which scoped storage does not permit from a shell: `bcax` present, `fcvtzs`
standing alone with no XOR correction beside it, `fmla` confirming fused
multiply-add is live, and dense `ldp`/`stp` pairing.

**An x86-only SIMD fast path is not automatically an ARM gap.** RSX builds
`copy_data_swap_u32` and the index-buffer `upload_untouched` as hand-written
asmjit SIMD kernels under `#if defined(ARCH_X64)`, leaving everyone else on
functions named `_naive`. That reads like ARM running a scalar loop over
megabytes of vertex data per frame. It is not: clang vectorizes both. The swap
loop compiles to `rev32` over `ldp`/`stp`, and the index loop to `umin`/`umax`
with `uminv`/`umaxv` reductions and `rev16`, with scalar code only in the tail.

The reason the asmjit machinery exists is that SSSE3 and AVX are *optional* on
x86, so the fast path has to be selected at runtime. NEON is mandatory on
AArch64, so the compiler can just emit it at build time. That whole apparatus is
solving an x86 problem. Check the generated code before hand-writing NEON to
"fix" a `_naive` fallback.

## sse2neon, and which callers of it matter

`Emu/CPU/sse2neon.h` is a compatibility shim that implements SSE intrinsics on
NEON, and three files run through it on ARM. The instinct is to rewrite all of
them; the useful question is which are hot.

| caller | SSE uses | verdict |
| --- | --- | --- |
| `Emu/Cell/SPUInterpreter.cpp` | 248 | cold here. `spu_decoder` defaults to `llvm`, so this C++ interpreter is only reached in interpreter decoder modes. The SPU LLVM path builds its own interpreter through `compile_interpreter`, which is generated IR, not this file. |
| `Emu/RSX/Program/ProgramStateCache.cpp` | 11 | hot, and fixed. Fragment-constant byteswap now uses `REV16` instead of the shift/shift/or idiom. The AVX-512 routines beside it are `#ifdef ARCH_X64` and never reach ARM. |
| `Emu/RSX/Common/buffer_stream.hpp` | 4 | fine. `_mm_set_epi32`, `_mm_loadu_si128` and `_mm_stream_si128` all map cleanly. |

One caveat worth knowing rather than acting on: sse2neon routes
`_mm_stream_si128` through `__builtin_nontemporal_store`, which preserves the
non-temporal intent but, for an isolated 16-byte value, lowers to a D-register
split and `STNP d0, d1`, three instructions where a plain `STR Q` is one. Paired
32-byte stores get the good form, `STNP q0, q1`. Whether the cache benefit pays
for the extra instructions in the vertex streaming path is a measurement, not a
guess.

Checked and cleared, so nobody repeats the work:

- **Floating-point mode.** No `MXCSR`, `FPCR`, `DAZ` or `FTZ` anywhere. Denormal
  flushing is explicit in software (`ppu_flush_denormal`), so there is no host
  FP-mode assumption to port.
- **Fences.** `atomic_fence_*` fall through to `__atomic_thread_fence`, which
  emits real `DMB` on AArch64. Only the MSVC/x86 branches are compiler-barrier
  only, which is correct for TSO.
- **Bit gather.** `GB`, `GBH` and `GBB` all have ARM paths via `SDOT` and
  `SMMLA`/`UMMLA`; the `m_use_gfni` branches are x86-only and fall through.
- **AltiVec float to fixed.** `VCTSXS` and `VCTUXS` clamp *before* converting
  rather than correcting afterwards, so they are architecture-neutral. This is
  the shape `CFLTS` should have had.
- **Dead x86 branches.** The 256-bit checksum loads and the VNNI `SUMB` path sit
  inside `#ifndef ARCH_ARM64`, so `m_use_avx` and `m_use_vnni` cost nothing
  there. `m_use_avx` remains live in exactly two places, and only the DMA one
  mattered.
- **Atomics.** AOT builds emit inline LSE. Verified at the compiler rather than
  assumed: a `compare_exchange_strong` and a `fetch_add` compile to `casal` and
  `ldaddal` with no `bl __aarch64_*`, and identically at `armv8.2-a`,
  `armv8.4-a`, and with `-mno-outline-atomics`, so nothing here depends on that
  switch.

  Worth knowing before someone repeats the check and thinks otherwise: the
  unstripped core **does define** `__aarch64_cas4_acq_rel`,
  `__aarch64_ldadd4_acq_rel` and `__aarch64_have_lse_atomics`, so a bare `nm`
  looks like outline atomics are in use. They are not ours. Nothing in the build
  references them undefined (`nm --undefined-only` counts zero), they arrive
  inside prebuilt third-party objects, and they do not survive into the shipped
  stripped library. `__aarch64_have_lse_atomics` in particular is compiler-rt's
  runtime dispatch flag, and its presence is what makes this look alarming; the
  emulator's own atomic operations never consult it.

## Where the wins actually were

`fptosi`/`fptoui` are **poison** on overflow, so shared code bolts a correction
on by hand, and that correction is written for x86. AArch64 saturates in
hardware, which makes the correction wrong rather than merely redundant:

- **SPU `CFLTS` was incorrect on ARM64.** `CVTTPS2DQ` returns `0x80000000` on
  overflow so the x86 path XORs it to `0x7fffffff`; `FCVTZS` already gives
  `0x7fffffff`, and the same XOR turns it into `0x80000000`. Any value at or
  above `2^31` produced the wrong result, upstream included.
- **SPU `CFLTU` was correct but redundant.** `FCVTZU` already clamps negatives
  to zero and saturates at `2^32`, so the select and sign mask were dead work.

`llvm.fptosi.sat` / `llvm.fptoui.sat` lower to a single `FCVTZS` / `FCVTZU`,
fixing the first and shortening both from four instructions to one. The x86
paths keep their corrections; only the ARM64 branches changed. Pinned by
`tools/test_thor_spu_arm64_float_convert.ps1`.

The general lesson: on a target whose hardware semantics are *stronger* than
the IR's, a portable correction can be worse than nothing. Grep for the other
places shared code compensates for x86 quirks before assuming they are neutral.

## Host capability answered by x86 model name

`cpu_translator::initialize` decides what the host can do with a run of string
comparisons against x86 CPU model names. That is reasonable on x86. On AArch64
those same flags still gate real lowerings, so a CPU string matching nothing
useful selects a fallback written for 2006 hardware.

Two instances, both now closed:

| flag | was decided by | what it actually gates on ARM |
| --- | --- | --- |
| `m_use_fma` | `cpu == "cyclone" \|\| cpu.contains("cortex")` | FMA, which is *mandatory* on AArch64, so the allowlist could only fail to enable it |
| `m_use_ssse3` | an allowlist of old x86 parts, including `"generic"` | the `x86_pshufb` lowering, which on ARM is `AND 0x8F` then `TBL` |

The second is the more alarming one, because the fallback is not a slightly
slower shuffle. It is a **16-iteration scalar loop** of
`extractelement`/`insertelement`, and `pshufb` backs `VPERM`, `LVLX`, `LVRX`,
`STVLX`, `STVRX`, `ROTQBY` and `SHUFB`. One unlucky CPU string would have
degraded every byte permute in both recompilers simultaneously.

It was not firing: `getTargetCPU()` returns the sanitized `cortex-a78`, and the
Android `fallback_cpu_detection()` returns a real core name or `cortex-a78`,
never `"generic"`. This was removing a possibility rather than fixing an
observed failure, which is worth saying plainly instead of claiming a win.

Worth knowing for its own sake: the ARM lowering is exactly right, and subtle.
x86 `PSHUFB` zeroes a lane when the index's **high bit** is set; ARM `TBL`
zeroes when the index is **≥ 16**. Masking with `0x8F` keeps the high bit and
the low four bits, so indices below 128 wrap to `0..15` and indices with the
high bit set land in `128..143`, which `TBL` zeroes. Two different zeroing rules
reconciled by one constant. Do not "simplify" that mask to `0x0F`.

The general rule: **a host-capability flag should be answered by the
architecture or a runtime probe, never by a model-name allowlist**, and any
allowlist that predates the port should be assumed to be x86-only. Pinned by
`tools/test_thor_arm64_feature_flags_not_x86_names.ps1`.

## Branch offsets do not mean the same thing

x86 `JMP rel32` is relative to the **end** of the instruction. AArch64 `B` is
relative to the **address of the branch itself**. Any hand-written code
generator ported across will be wrong by exactly one instruction, and it will
be wrong in the quietest possible way: it jumps to a valid instruction, four
bytes early.

This is sitting in the PPU symbol trampoline. x86 builds a 16-byte stub per
symbol, `mov edx, func_addr` then a jump to shared code. An AArch64 equivalent
exists directly beneath it, `MOVZ`/`MOVK`/`B` in 12 bytes, but it is behind
`#elif 0`, so ARM falls through to `build_function_asm` and emits the *whole*
dispatch sequence per symbol instead of a stub. The disabled code computed

    full_sample - (code + 4)

which is exactly right for x86 and wrong here, because `write_le` takes `code`
by reference and has already advanced it to the address the `B` will occupy.
The result branches to `full_sample - 4`.

Verified against the assembler rather than argued, which is the cheap way to
settle any encoding question: a reference `B` at `0x8` targeting `0x14` encodes
`0x14000003`, so imm26 is `(0x14 - 0x8) / 4`, self-relative. The same
disassembly confirms the block's `MOVZ`/`MOVK` encodings are already correct
(`mov w15, #0x1234` is `0x5282468f`, which is `0x5280000F | 0x1234 << 5`).

**The offset is fixed; the block is still disabled**, and that is deliberate.
Correct arithmetic is not the same as a working code generator. Enabling it
needs three integration facts this fork cannot currently establish without
booting a game: that `x19`/`x20` hold what the stub assumes at the call site,
that `jit_runtime::alloc`'d memory gets the i-cache maintenance AArch64 requires
before executing freshly written instructions, and that `full_sample` reliably
lands inside `B`'s +-128MB range. Fixing the bug now means whoever enables it is
debugging one thing instead of two.

Note the third point is itself an ARM concern with no x86 analogue. x86 has
coherent instruction caches; AArch64 does not, so **any** self-modifying or
JIT-written code needs explicit cache maintenance. Worth checking whenever
hand-written codegen appears.

## Building a vector from 32-bit scalars is cheap on x86 and stalls on A710

The A710 guide carries three sections the X3 guide does not, and two of them
describe the same hazard from different angles. This matters because A710 and
A715 are four of Thor's eight cores.

**Section 4.2, dispatch stall:**

> In the event of a V-pipeline µOP containing more than 1 quad-word register
> source, a portion or all of which was previously written as one or multiple
> single words, that µOP will stall in dispatch for **three cycles**.

**Section 4.11, register forwarding hazards**, gives the conditions precisely:

- the producer writes an **S-register**, *not* a `D[x]` scalar
- the consumer reads an overlapping **Q-register**
- the consumer is an FP/ASIMD µOP, *not* a store or MOV

So the shape to avoid is: assemble a vector out of 32-bit pieces, then feed it
into a multi-source vector operation.

**That is exactly what `_mm_set_epi32` means**, and on x86 it is an unremarkable
way to build a constant or pack four values. Verified at `-O2 -mcpu=cortex-a710`
that clang produces the hazard verbatim:

```
fmov  s1, w0                 <- S-register write        (4.11 producer)
mov   v1.s[1], w1            <- single-word lane writes (4.2)
mov   v1.s[2], w2
mov   v1.s[3], w3
add   v0.4s, v1.4s, v0.4s    <- two quad-word sources, FP/ASIMD consumer
```

All three of 4.11's conditions hold, and 4.2's three-cycle stall applies on top.

**The obvious workaround does not work.** Writing the four values to a stack
array and loading the vector back compiles to *byte-identical* code: clang folds
the memory round-trip away and rebuilds it lane by lane.

**The guide's own mitigation does work.** Section 4.11 exempts `D[x]` scalar
writes, so packing the values into 64-bit halves first gives:

```
fmov  d1, x8                 <- D-register write, exempt
mov   v1.d[1], x9            <- D[x] scalar write, exempt
add   v0.4s, v0.4s, v1.4s
```

Two extra GPR `orr`s buy the removal of a three-cycle dispatch stall and the
forwarding hazard, on half the cores in this machine.

**Audited, and this codebase does not currently hit it.** The pattern appears in
five files; none is a live ARM hot path:

| site | uses | verdict |
| --- | --- | --- |
| `Emu/CPU/sse2neon.h` | 64 | the shim's own implementations, not call sites |
| `Emu/Cell/SPUInterpreter.cpp` | 46 | cold. `spu_decoder` defaults to `llvm`, so this C++ interpreter is not reached |
| `Emu/RSX/Program/ProgramStateCache.cpp` | 2 | `_mm_set1_epi32` of a **constant**, which lowers to `MOVI`, not lane writes |
| `Emu/RSX/Common/buffer_stream.hpp` | 1 | consumer is `_mm_stream_si128`, a **store**, which 4.11 explicitly excludes |
| `Emu/CPU/CPUTranslator.cpp` | 1 | a comment |

So this is a rule for new code rather than a defect to repair, and it is written
down here because the check is not obvious: a constant splat and a four-scalar
pack look alike in source and are completely different instructions.

**The generalizable form**, which is the reason this belongs in the x86-habit
family: on x86 the cost of materialising a vector is roughly independent of how
you spell it. On A710 the *width of the writes* that produced a register changes
what the next instruction costs. Prefer 64-bit lane writes when populating a
vector that an ASIMD instruction will consume, and reserve `_mm_set_epi32`-shaped
construction for values that go straight to memory.

## What "use the non-writeback forms" actually costs, in pipes

Section 4.3 tells you to write a copy with non-writeback `LDP`/`STP` and does not
say why. The instruction tables do. Every writeback form is identical in latency
and throughput to its immediate-offset twin and differs in exactly one way: it
additionally occupies an **Integer pipe**, for the base-register update.

Q-form, which is what a 128-bit vector copy uses:

| form | latency | throughput | pipes |
| --- | --- | --- | --- |
| `LDP`/`LDNP` Q, immed offset | 6 | 3/2 | `L` |
| `LDP` Q, immed post-index | 6 | 3/2 | **`L, I`** |
| `LDP` Q, immed pre-index | 6 | 3/2 | **`L, I`** |
| `STP`/`STNP` Q, immed offset | 2 | **1** | `L01, V01` |
| `STP` Q, immed post-index | 2 | **1** | **`I, L01, V01`** |

The same pattern holds for the general-purpose forms, `LDP` X-form going from `L`
to `L, I` and `STP` from `L01, D` to `L01, D, I`.

So the writeback saving of one `ADD` per iteration is not free: it converts an
explicit integer instruction into an integer µOP attached to every access. For
`mov_rdata`'s eight accesses that is eight integer µOPs added to a routine whose
own address arithmetic is zero, since all four offsets are compile-time
constants. Writing the offsets out is strictly better here, and Arm's advice and
the tables agree.

**Two further things fall out of these rows, both about `STP` Q-form.**

Its **throughput is 1**, where the S-form and D-form both manage 2. So 32-byte
stores issue one per cycle, and the four stores in a 128-byte copy are a 4-cycle
floor that the loads, at 3/2, comfortably hide behind. The copy is store-bound,
which is the right thing to know before trying to make it faster: shaving loads
would achieve nothing.

And `STNP` shares the row with `STP` at identical cost, which retires a question
this document had left open. The non-temporal variant is not paying for its
cache-bypass hint in latency, throughput or pipes; the earlier worry about
`mov_rdata_nt` was only ever about the **D-register split** that a 16-byte
non-temporal store lowers to, never about `STNP` itself. With 32-byte chunks,
which is what that function uses, the paired form costs exactly what a plain
`STP` costs.

### `LD1`/`ST1` and `LDP`/`STP` are the same instruction as far as the core cares

While choosing the shape for `mov_rdata`, the NEON `vld1q_u8_x2` spelling was
rejected in favour of plain vector loads because it emitted `LD1`/`ST1` rather
than `LDP`/`STP`. **That reasoning was wrong, even though the conclusion was
right.** The tables put the two-register Q-form of each in exactly the same
place:

| instruction | latency | throughput | pipes |
| --- | --- | --- | --- |
| `LDP`/`LDNP` Q, immed offset | 6 | 3/2 | `L` |
| `LD1`, 1 element, multiple, **2 reg**, Q-form | 6 | 3/2 | `L` |
| `STP`/`STNP` Q, immed offset | 2 | 1 | `L01, V01` |
| `ST1`, 1 element, multiple, **2 reg**, Q-form | 2 | 1 | `L01, V01` |

Identical in all three columns, both directions. Arm's section 4.3 example is
written with `LDP`/`STP`, but nothing in the timing data prefers them.

**The variable that actually mattered was the addressing mode.** `vld1q_u8_x2`
compiled to the *writeback* form, `ld1 {v0.16b, v1.16b}, [x8], #32`, which adds
the `I` pipe per the rows above, while the plain vector loads produced
non-writeback `LDP` at fixed offsets. So the win came from dropping the
base-register update, not from the mnemonic.

Worth recording because the mistake is an easy one to repeat in either direction:
seeing `LD1` where the guide's example says `LDP` looks like a miss, and it is
not. Read the addressing mode, not the instruction name.

## Floating point: multiply-accumulate is cheap, conversion is not

The SPU is float-heavy, so Table 3-16 is worth having to hand. The shape of it is
that ordinary arithmetic is as cheap as integer work and runs on all four vector
pipes, while **anything that changes representation is restricted to `V02`, two
pipes, and is slower than it looks**.

| operation | latency | throughput | pipes |
| --- | --- | --- | --- |
| `FADD`/`FSUB`/`FADDP` | 2 | 4 | `V` |
| `FMAX`/`FMIN`/`FMAXNM`/`FMINNM` | 2 | 4 | `V` |
| `FABS`/`FABD`, `FNEG` | 2 | 4 | `V` |
| FP compare (`FCMEQ`, `FCMGE`, ...) | 2 | 4 | `V` |
| `FMUL`/`FMULX` | 3 | 4 | `V` |
| **`FMLA`/`FMLS`** | **4, accumulator 2** | **4** | `V` |
| FP convert, D-form F32 / Q-form F64 | 3 | 2 | `V02` |
| **FP convert, D-form F16 / Q-form F32** | **4** | **1** | `V02` |
| `FCVTL`/`FCVTN` (F16 to/from F32) | 4 | 1 | `V02` |
| `FDIV` Q-form F32 | 7 to 10 | 2/9 to 2/7 | `V02` |

Three things follow.

**`FMLA` is the best instruction in the table and the fork is already using it.**
Latency 4, but only **2 through the accumulator**, at full rate on all four
pipes. So a dependent chain of multiply-accumulates advances every two cycles.
The on-device disassembly already confirmed `fmla` present in compiled SPU
blocks; this says that was worth having.

**`FCVTZS` on a full vector of floats is the expensive case, and that is exactly
the SPU's case.** The row that applies to `CFLTS`, `CFLTU`, `CSFLT` and `CUFLT`
is Q-form F32: **latency 4, throughput 1, two pipes**. On top of that, section 4.7
lists "FP convert and rounding instructions that do not write to general purpose
registers" as belonging to **no forwarding region at all**, so a further cycle is
added before whatever consumes the result. Call it 5 effective.

That does not reopen the conversion fix. Replacing a four-instruction x86-style
correction that was also *wrong* with one correct instruction is still the right
change by a wide margin. What it does say is that conversions are not free
padding: an approach that adds float-to-int round trips to save an integer
operation is very unlikely to pay, because it moves work from four pipes onto
two, at a quarter of the rate, outside the forwarding network.

**`FDIV` should be treated as unavailable in hot code.** Q-form F32 is latency 7
to 10 at a throughput between 2/9 and 2/7 per cycle, on two pipes, and also
outside every forwarding region. Roughly thirty times the cost of `FMUL`. Any SPU
reciprocal path that reaches a real divide rather than an estimate instruction is
worth looking at for that reason alone.

## The pipe map, which explains every restriction above

Table 2-1 is the single most useful page in the X3 guide, because it says what
each of the four vector pipes can *do*, and every `V01`/`V02`/`V13`/`V0` code in
the instruction tables follows from it:

| pipe | ASIMD shift | FP convert, ASIMD integer multiply, FP divide/sqrt | ASIMD ALU, ASIMD misc, FP add, FP multiply | store data |
| --- | --- | --- | --- | --- |
| FP/ASIMD-0 | — | **yes** | yes | yes |
| FP/ASIMD-1 | **yes** | — | yes | yes |
| FP/ASIMD-2 | — | **yes** | yes | — |
| FP/ASIMD-3 | **yes** | — | yes | — |

**The two specialisations are disjoint.** Shifts live on pipes 1 and 3, which is
where `V13` comes from. Conversions, integer multiplies and divides live on pipes
0 and 2, which is `V02`. Only the general work — ALU, miscellaneous, floating
point add and multiply — reaches all four.

Two practical consequences.

**A loop made entirely of vector shifts is capped at half the machine**, at
throughput 2 rather than 4, no matter how independent the work is. That applies
directly to the SPU, which shifts constantly: the `ROTQBY` family, `inf_shl` and
`inf_lshr` through `USHL`, and the `XSBH`/`XSHW`/`XSWD` sign-extends that the
opcode audit records as `SHL` plus `SSHR`. That pair is two `V13` µOPs with a
dependency between them, so it is not just two instructions, it is two
instructions contending for two pipes. The audit called it "unavoidable", which
remains true — NEON has no in-lane sign extend — but the cost is higher than the
instruction count suggests.

**Conversely, mixing shifts with conversions is free parallelism**, because the
two classes cannot contend. A loop alternating `USHL` and `FCVTZS` can saturate
all four pipes where either alone saturates two.

**One caveat, because Table 2-1 will otherwise appear to contradict the
instruction tables.** It lists "crypto µOPs" under *all four* pipes, yet the
Cryptography table gives `BCAX` and `EOR3` as `V0`, one pipe. Both are correct:
Table 2-1 is a coarse capability map for a whole instruction class, and different
crypto instructions land on different pipes within it. **The per-instruction row
is the authoritative one.** Do not use Table 2-1 to argue that a specific
instruction has more pipes than its own row says.
