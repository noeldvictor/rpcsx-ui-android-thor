# Microarchitecture reference: what the per-core guides actually say

Reference data extracted from the Cortex-X3 and Cortex-A710 Software Optimization
Guides vendored in [`docs/hardware/`](../hardware/): instruction latency,
throughput, pipe assignment, and the chapter 4 rules that follow from none of
them.

This is the hardware's side. What this fork does with it — which lowerings were
chosen, and which x86 habits produced defects — is in
[`codegen.md`](codegen.md). Part of the notes indexed from
[`CLAUDE.md`](../../CLAUDE.md).

**Read the pipe column.** It decides borderline cases and is the easiest to skip:

    V    FP/ASIMD 0/1/2/3   all four pipes
    V01  FP/ASIMD 0/1       two
    V02  FP/ASIMD 0/2       two
    V13  FP/ASIMD 1/3       two
    V0   FP/ASIMD 0         one

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

## Reductions cost double at full width, which is why folding first wins

The movemask-replacement toolkit leans on reductions, and their cost is not flat.
Width changes both columns:

| reduce | latency | throughput | pipes |
| --- | --- | --- | --- |
| `ADDV`/`SADDLV`/`UADDLV`, **4H/4S** | **2** | **2** | `V13` |
| `ADDV`/`SADDLV`/`UADDLV`, 8B/8H | 4 | 2 | `V13, V` |
| `ADDV`/`SADDLV`/`UADDLV`, **16B** | **4** | **1** | `V13` |
| `UMAXV`/`UMINV`/`SMAXV`/`SMINV`, **4H/4S** | **2** | **2** | `V13` |
| `UMAXV`/`UMINV`/`SMAXV`/`SMINV`, 8B/8H | 4 | 2 | `V13, V` |
| `UMAXV`/`UMINV`/`SMAXV`/`SMINV`, **16B** | **4** | **1** | `V13` |

A 16-byte reduction is **twice the latency and half the throughput** of a 4-lane
one, and every form is stuck on `V13`, the same two pipes as every vector shift.
Section 4.7 adds a further cycle on top, because ASIMD reductions belong to no
forwarding region at all, so whatever consumes the result — invariably a move to
a general-purpose register — waits one more.

**This is the real reason the `scan16_rdata` rewrite works**, and it is a better
justification than the instruction count that was recorded for it. The obvious
way to collapse eight 16-byte comparisons is eight full-width reductions. That
would be eight `V13` µOPs at throughput 1, latency 4, on the narrowest pipe pair
in the machine, each followed by a cross-region penalty.

What it does instead is fold with `UMAXP` first. Pairwise max is `ASIMD max/min,
basic and pair-wise`: latency 2, throughput 4, **all four pipes**. So the folding
happens on the wide, unrestricted part of the machine, and only the final small
reduction touches `V13`. The 65-to-42 instruction count understates it — the
change also moved the bulk of the work off the contended pipe pair.

**The generalizable rule for this toolkit: narrow the data with pairwise
operations on `V`, then reduce once, as narrow as possible.** Reaching for
`ADDV`/`UMAXV` on a full 16-byte vector is the expensive spelling of a reduction,
not the natural one.

## Level 3 for the reservation copy: the shape is in the shipped binary

This document's verification scheme has three levels — source contract test,
backend selection at the compiler, and disassembly of what actually shipped. The
`mov_rdata` rewrite had levels 1 and 2 and was left at that, because a first
attempt at level 3 found nothing and the search was abandoned rather than fixed.
That is the wrong place to stop: **a fix that cannot be shown to reach the
machine is indistinguishable from one that did not.**

Done properly. Scanning the shipped `librpcsx-android.so` instruction stream for
the exact signature — eight consecutive q-register pair operations alternating
load and store at offsets `0`, `0x20`, `0x40`, `0x60`:

    exact interleaved 128B copy ladder                 6
    batched ldp,ldp,stp,stp (the shape memcpy produced)  318

**Six inlined instances**, which is what a `FORCE_INLINE` function with several
call sites should produce. The 318 batched sequences elsewhere in the binary are
the control: the scanner is discriminating between the two shapes rather than
matching every pair of vector loads, and the shape `memcpy` used to emit here is
still present in the places that legitimately use it.

So the Arm section 4.3 form — non-writeback, interleaved, every store 32-byte
aligned — is in the machine code that runs, not only in a compiler experiment.

**Both failed attempts at this check failed the same way, and it is worth naming.**
The first level-3 attempt searched for `strings` output and found zero, because
GNU `strings` skips sections that `grep -a` reads. The second searched
disassembly for `#-?[0-9]+` offsets and found zero, because `llvm-objdump` prints
them in **hex** — the pattern matched `#-0` and stopped at the `x`. Neither was a
fact about the binary; both were facts about the tool's output format, and both
read exactly like a change that had not landed.

**When a verification returns zero, check the format of what you searched before
concluding anything about what you searched for.** That is the same lesson as the
empty-directory sweep in `ledger.md`, arriving from a different direction: a
search that cannot match and a search that finds nothing produce identical
output.

### And the same for the reservation compare

`cmp_rdata` had the same gap: rewritten from a serial accumulator to a tree,
verified at the compiler, never checked in the shipped binary. Applying the same
sequence scan — and deliberately *not* the aggregate counts, which cannot
separate this function from the recompiler's own vector output:

| shape | instances |
| --- | --- |
| tree: `>=6 eor .16b` + `>=4 orr .16b`, then `umaxv s, .4s` | **17** |
| serial: `>=3 sub .8h`, then `addv h, .8h` | **0** |

Seventeen inlined copies, and the old accumulator form **entirely absent**. That
second number is the one that matters: it shows the rewrite replaced the previous
shape rather than being added alongside it somewhere, which a count of the new
form alone would not establish.

The first attempt at this used aggregate opcode counts — `addv h` 27, `mla .8h`
190, `cmeq .8h` 38 — and they say nothing, because the SPU recompiler emits all
of those constantly for unrelated reasons. **A hot function inlined into a large
binary is invisible to a census and obvious to a sequence match**, which is worth
knowing before concluding from totals that a change did or did not land.

Both hot-path rewrites are now verified at all three levels: contract test,
compiler codegen, and disassembly of what shipped.
