# Instruction selection on this core

How the AArch64 backend is actually used here: what the per-core optimization
guides say, which lowerings were rewritten, and the x86 habits that produced
the defects worth hunting.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

The hardware reference these decisions rest on — instruction latency,
throughput and pipe assignment from the vendored optimization guides — is in
[`microarchitecture.md`](microarchitecture.md).

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

## `cmp_rdata`: the clever lowering may be the slow one

The upstream ARM work devotes a chapter to *"the most optimized way to compare
data on ARM"*, and this is our version of that comparison. It is also the
function sitting immediately beside the `mov_rdata` that turned out to be
compiling to nothing, so it deserved a second look.

The ARM64 path in `SPUThread.cpp` is genuinely clever. `vceqq_u16` yields `-1`
per equal lane, `vmlaq_s16` multiplies two such masks — giving `1` only where
both halves matched — and accumulates; `vaddvq_s16(hits) == 32` then tests all
32 lanes at once. Eight `CMEQ`, four `MLA`, one `ADDV`: three instructions
shorter than an XOR/OR tree.

**Instruction count is the wrong thing to count.** From the Cortex-X3 guide
(`docs/hardware/`, p26):

| operation | latency | throughput | pipes |
| --- | --- | --- | --- |
| `CMEQ`, `CMGE`, … | 2 | 4 | **V** — all four |
| `AND`, `EOR`, `ORR`, … | 2 | 4 | **V** — all four |
| **`MLA`, `MLS`** | **4 (1)** | **2** | **V02** — two only |
| `ADDV` (8H) | 4 | 2 | V13 |

The four `MLA`s issue on **half** the vector pipes at **half** the throughput,
and they are **serially dependent** through `hits`, so the chain cannot overlap
with itself. The XOR/OR tree is all-V, full throughput, and log-depth.

`docs/hardware/README.md` states this trap in as many words:

> An instruction that saves an operation but lands on `V0` can still lose to a
> two-instruction sequence that spreads across `V`.

This is that case, in the hottest comparison in the emulator — the GETLLAR retry
loop called `cmp_rdata` **10,093,915 times in one Folklore boot**.

Both lowerings now build, selected at runtime:

    debug.rpcsx.thor.cmp_rdata = <unset>   MLA form (default, unchanged)
                               | tree      XOR/OR tree, all-V

**Not measured yet.** The table says the tree should win; the table also said
`ISB` should beat `YIELD`, and measurement showed a 23% regression because the
surrounding code was tuned around the old behaviour. Predict from the manual,
then measure — in that order, and do not skip the second step.

### Measured: no difference, and the reason matters more than the result

| lowering | Mcyc/s | cores busy | vs baseline |
| --- | --- | --- | --- |
| `mla` (default) | 5,956.0 | 2.225 | — |
| `tree` (all-V) | 5,973.6 | 2.234 | **+0.3%** |

0.3% is inside the noise this design resolves — the `pause` A/B put `yield`
against `nop` at 2% and that was already borderline. **The pipe-assignment
prediction did not translate into anything measurable.**

The likely reason is not that the manual is wrong; it is that **the workload no
longer exercises the function**. The 10,093,915 `cmp_rdata` calls that motivated
this were counted while the emulator was *deadlocked* — the GETLLAR retry loop
spinning forever on a line that could never match, because `mov_rdata` was
copying nothing. With that fixed the loop settles in a handful of iterations,
and `cmp_rdata` is no longer hot.

So this is a correct measurement of the wrong population, which is the failure
mode `adreno-tiler.md` records and this project keeps rediscovering. What it
establishes is still worth having: **on the workload that now exists, the
lowering does not matter**, so do not churn the hottest correctness-sensitive
comparison in the emulator for a table entry.

To settle it properly, count the calls first. `getllar_cc_cmp` in `SPUThread.cpp`
already counts the retry path that invokes it, but only reports from the 5-second
stall reporter, which no longer fires. A per-frame counter would answer whether
`cmp_rdata` is hot enough for its lowering to be worth an argument at all —
and if it is not, this whole section is an interesting note rather than an
optimization.

Default stays `mla`. Both paths remain switchable.

## SHUFB uses BCAX, which is single-pipe on the cluster SPU runs on

The first hot-path narrow-pipe candidate this audit has turned up, and it only
appeared after the core-guide mix-up was corrected.

`SPULLVMRecompiler.cpp` emits `bcax()` in three places, two of which are the
**SHUFB** lowering:

```cpp
7237:  set_vr(op.rt4, tbl2(a, b, bcax(splat<u8[16]>(0x0f), c, splat<u8[16]>(0x60))));
7248:  set_vr(op.rt4, tbx2(x, a, b, bcax(splat<u8[16]>(0x0f), c, splat<u8[16]>(0x60))));
6419:  set_vr(op.rt, bcax(get_vr<u32[4]>(op.ra), splat<u32[4]>(0xffffffff), get_vr<u32[4]>(op.rb)));  // NOR
```

`BCAX` computes `(a AND NOT c) XOR b` in one instruction instead of `BIC` + `EOR`.
Fewer instructions, which is the reason it is there. But on **A715**:

```
Crypto SHA3 ops   BCAX, EOR3, RAX1, XAR    2   1   V0
AND/BIC/EOR/ORR                            2   2   V
```

**`BCAX` is throughput 1 on a single pipe; the two-instruction form is
throughput 2 across all four.** Best case they tie at one result per cycle, and
`BCAX` loses whenever `V0` is contended — which on A715 also carries `MLA`,
16-bit `SDOT` and `SCVTF`.

This is the exact shape `docs/hardware/README.md` warns about: *an instruction
that saves an operation but lands on V0 can still lose to a two-instruction
sequence that spreads across V.*

It matters here specifically because **SPU threads are pinned to `cpu5`/`cpu6`**,
both in the A710/A715 cluster, and SHUFB is among the hottest SPU instructions —
the upstream ARM work gives it its own chapter.

### The experiment, which is already wired

`CPUTranslator.h` has `m_use_sha3`, and `bcax()` "falls back to the arithmetic
form without SHA-3" (comment at `SPULLVMRecompiler.cpp:7247`). The device log
confirms `sha3=true` is active. So the A/B needs no new code, only a way to turn
SHA-3 off independently: the existing `debug.rpcsx.thor.spu_arm_features` modes
are `native`, `no-dotprod`, `no-i8mm` and `baseline`, and **`baseline` disables
dotprod and i8mm too**, which would confound the result.

Adding a `no-sha3` mode alongside the existing two is a few lines in
`sysinfo.cpp`, and then `tools/thor_property_ab.ps1` can measure it against
Eternal Sonata, the SPU-heavy title. **Unmeasured** — and on this project's
record, the table says one thing and the device decides.

## The JIT is scheduled for a core this device does not have

`JITLLVM.cpp` picks the LLVM `-mcpu` for JIT'd code, and on Android it runs the
detected name through `sanitize_android_arm64_llvm_cpu()`:

```cpp
if (!utils::has_sve() && android_arm64_cpu_enables_sve_by_default(cpu))
{
    jit_log.warning("LLVM CPU '%s' enables SVE in bundled LLVM, but Android HWCAP "
                    "does not report SVE. Using cortex-a78 for Thor-safe JIT code.", cpu);
    return "cortex-a78";
}
```

The Thor's cores are Armv9 — Cortex-X3 and A715/A710 — so LLVM enables SVE for
them by default, HWCAP reports no SVE, and every one is downgraded to
**`cortex-a78`**. The device log confirms it: `cpu=cortex-a78`.

**`cortex-a78` is not a core in this device.** It is Armv8.2, one generation
back, with a different pipeline layout — and `-mcpu` selects LLVM's *scheduling
model*, so instruction selection and ordering for **all** JIT output are tuned
for the wrong microarchitecture. The profile puts 54% of cycles in that output.

The SVE avoidance is sound; the remedy may be heavier than needed. The same
target string already carries **explicit `-sve,-sve2`** in its feature list
(`attrs=+sha3,+dotprod,+i8mm,-sve,-sve2`), and in LLVM the feature string is
applied after the CPU's defaults. If that override is reliable, `cortex-a715`
plus `-sve,-sve2` would give the correct scheduling model with no SVE codegen,
and the downgrade is paying a real cost to solve an already-solved problem.

### Why this is not yet a change

Two things have to be established first, in this order, and the second is the
one this project keeps skipping:

1. **Does `-sve` in the feature string actually suppress SVE for
   `-mcpu=cortex-a715`?** Verifiable off-device: compile a vector-heavy function
   both ways and check the disassembly for `z` registers. If any appear, the
   downgrade is load-bearing and this ends here.
2. **Does the correct scheduling model measurably help?** A/B with
   `tools/thor_property_ab.ps1` on Eternal Sonata. Per the checklist in
   `CLAUDE.md`, "the model is wrong" is a fact about the compiler, not a
   prediction about this code — nine such predictions have been refuted, and the
   scheduling model may matter less than it sounds for code dominated by loads,
   stores and branches, which the instruction histogram shows it is.

This is the largest remaining lever precisely because it applies to all JIT
output at once, and for the same reason it is the one most likely to be a
regression if taken on faith.

### Check 1 passed: the downgrade is not load-bearing

Verified off-device with the NDK clang that ships with this build, so no device
time and no rebuild:

```
$ clang --target=aarch64-linux-android29 -mcpu=<cpu> -### -c x.c
cortex-a78                +dotprod
cortex-a715               +dotprod +i8mm +sve +sve2
cortex-x3                 +dotprod +i8mm +sve +sve2
cortex-a715+nosve         +dotprod +i8mm -sve -sve2
```

Two results, and the second was not expected.

**The premise of the downgrade is real** — `cortex-a715` and `cortex-x3` do
enable `+sve +sve2` by default in this LLVM, exactly as the warning in
`sanitize_android_arm64_llvm_cpu()` says.

**And an explicit negation overrides it.** `cortex-a715+nosve` yields
`-sve -sve2` while keeping `+dotprod +i8mm`. The JIT already passes
`-sve,-sve2` in its feature string, so the SVE hazard is handled *twice*, and
the fallback to `cortex-a78` is not load-bearing.

It also costs more than the scheduling model. `cortex-a78` supplies only
`+dotprod`; **`+i8mm` is not among its defaults.** The JIT survives that by
re-adding i8mm explicitly, which is why `use_spu_i8mm()` works at all — but it
means the downgrade is discarding CPU defaults and hand-patching them back.

So the change is: let `sanitize_android_arm64_llvm_cpu()` keep the real CPU name
when the caller guarantees `-sve,-sve2` in the feature string, rather than
substituting a core the device does not contain.

**Check 2 — does it measurably help — is still open**, and it is the one that
decides. Nine predictions of this shape have been refuted. Put it behind a
property, A/B it on Eternal Sonata with `tools/thor_property_ab.ps1`, and expect
the histogram's answer: JIT output is dominated by loads, stores and branches,
where a scheduling model matters less than it does for tight arithmetic.

### Check 2 refuted the premise: that code path never runs

The property-gated override was built, installed and enabled — and the log still
said `cpu=cortex-a78`. Neither the original SVE warning nor the new one fired.

**`sanitize_android_arm64_llvm_cpu()` never reaches its SVE branch.** The JIT
gets `cortex-a78` from the hardcoded default at `JITLLVM.cpp:1492`, taken when
`aarch64::get_cpu_name()` returns empty — which it does, because
`/proc/cpuinfo` on this device exposes no `CPU part` line. The comment two lines
below has said so all along: *"ARM CPU registers are not accessible from
usermode."*

So the preceding two sections analysed a downgrade that does not happen. The SVE
substitution is real code and it is dead here. **This is checklist item 4 —
establish reach before optimality — violated in the same session the checklist
was written.** Reading a function and reasoning about its logic is not evidence
that it runs.

**But the real cause is fixable, and better than what was proposed.** MIDR *is*
readable through sysfs:

```
/sys/devices/system/cpu/cpu0/regs/identification/midr_el1  0x00000000411fd461  part 0xd46  Cortex-A510
/sys/devices/system/cpu/cpu5/regs/identification/midr_el1  0x00000000412fd470  part 0xd47  Cortex-A710
/sys/devices/system/cpu/cpu7/regs/identification/midr_el1  0x00000000411fd4e0  part 0xd4e  Cortex-X3
```

Every core identifies itself precisely. `get_cpu_name()` returns empty only
because it does not look here.

The correct change is therefore **not** relaxing the SVE substitution but
teaching CPU detection to read `midr_el1`, which also answers a question the
substitution never could: **the cores differ per cluster.** A single `-mcpu` is
wrong for a big.LITTLE target no matter which one is chosen — SPU threads are
pinned to A710/A715 while RSX runs on the X3, and a JIT could reasonably pick
its target per thread class.

Sequence for whoever picks this up: read MIDR, map part numbers to LLVM CPU
names, keep the `-sve,-sve2` feature negation (verified sufficient above), and
only then A/B. The measurement remains the arbiter — this section has already
been wrong once.

### Corrected again: MIDR detection is not blocked, and it targets the weakest core

The previous section said `get_cpu_name()` returns empty because
`/proc/cpuinfo` has no `CPU part`. That was wrong twice over, and the checks are
cheap enough that there was no excuse:

* **`get_cpu_name()` does not use `/proc/cpuinfo`.** It reads
  `midr_el1` per core already (`AArch64Common.cpp:259`).
* **The app can read it.** Verified through `run-as net.rpcsx.easy`, not just an
  adb shell — the file is `-r--r--r--`, world readable, and returns
  `0x00000000411fd4e0` for cpu7. My earlier sysfs check was run as *shell*, which
  proves nothing about the app; that is the "positive control on the wrong
  channel" trap this project has now hit three times.
* **The part table already knows these cores**: `0xd46` A510, `0xd47` A710,
  `0xd4d` A715, `0xd4e` X3 are all present.

So detection has every input it needs. What it then does is the interesting part:

```cpp
const cpu_entry_t* lowest_part_info = nullptr;
for (const auto& [midr, count] : core_layout)   // ordered by MIDR
```

**It selects the *lowest* part number present — the weakest core.** On this
device that is the Cortex-A510. That is a defensible conservative choice for
correctness (never emit an instruction some core lacks), and it is the wrong
choice for scheduling, because the mid cluster does the most work and the little
cores the least.

**Still unexplained:** the log reports `cpu=cortex-a78`, and neither the SVE
warning nor the added one fires. If detection returned `cortex-a510`, one of
those paths should be visible. Something between `get_cpu_name()` and the
reported target is not doing what reading it suggests — and *reading it* is
exactly what has been wrong three times in a row here.

**Next step is a print, not an argument:** log the value `get_cpu_name()`
actually returns, next to what `sanitize_android_arm64_llvm_cpu()` does with it.
One line, one boot, and it ends the speculation. Do that before touching
anything.

### Resolved: the JIT asks LLVM, not this project's own detection

The probe settled it by *not* printing. `aarch64::get_cpu_name()` is never
called on the JIT path at all. `JITLLVM.cpp:930`:

```cpp
m_cpu = llvm::sys::getHostCPUName().str();
if (m_cpu == "generic") { ... m_cpu = fallback_cpu_detection(); }
```

**The JIT takes its target from LLVM's host detection**, which on AArch64 parses
`/proc/cpuinfo` — the file this device does not populate with `CPU part`. So it
returns `generic`, the fallback runs, and the result is `cortex-a78`.

Meanwhile `AArch64Common.cpp` contains a working MIDR reader with a part table
that already knows `0xd46` A510, `0xd47` A710, `0xd4d` A715 and `0xd4e` X3, and
the app can read `midr_el1` (verified through `run-as`). **The project has
correct CPU detection and the JIT never asks it.**

So the fix is one line of plumbing rather than any of the three things the
preceding sections proposed: have the JIT consult `aarch64::get_cpu_name()`
before falling back. The SVE substitution then becomes reachable and relevant,
and the verification above applies — `cortex-a715+nosve` keeps `+dotprod +i8mm`
and drops `-sve -sve2`, and the JIT already passes those negations.

Two caveats before anyone does it:

* `get_cpu_name()` picks the **lowest** part present, which on this device is the
  A510. Safe for correctness, wrong for scheduling. Selecting per thread class —
  SPU is pinned to A710/A715, RSX to the X3 — is the better shape.
* It is still unmeasured whether the scheduling model is worth anything. Ten
  predictions of this kind have been refuted here.

### What this thread cost, and what it teaches

Four wrong answers in a row about one code path: it returns empty because of
`/proc/cpuinfo` (wrong, it reads MIDR); the app cannot read MIDR (wrong,
verified via `run-as`); the part table lacks Armv9 cores (wrong, all present);
the SVE substitution downgrades it (wrong, never reached). Every one came from
reading code and reasoning about it.

The single `jit_log.error` that resolved it took one line and one boot, and
would have been cheaper than any of the four. **When a question is "what does
this code actually do at runtime", print it — the answer is never in the
source, it is in the log.**
