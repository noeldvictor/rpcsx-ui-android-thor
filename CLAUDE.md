# Fast AArch64 PS3 Emulation on Snapdragon 8 Gen 2

Technical notes for making this emulator fast on Thor. `AGENTS.md` is the
operating contract; this file is the hardware knowledge behind it.

## The machine

Ayn Thor, Snapdragon 8 Gen 2 (`kalama`), 8 cores in a 1+2+2+3 layout:

| MIDR | core | count | notes |
| --- | --- | --- | --- |
| `0xd4e` | Cortex-X3 | 1 | wide OoO, 4 vector pipes |
| `0xd4d` | Cortex-A715 | 2 | |
| `0xd47` | Cortex-A710 | 2 | |
| `0xd46` | Cortex-A510 | 3 | narrow, shared vector unit per pair |

`/proc/cpuinfo` Features, verified on device:

```
fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics fphp asimdhp cpuid asimdrdm
jscvt fcma lrcpc dcpop sha3 sm3 sm4 asimddp sha512 asimdfhm dit uscat ilrcpc
flagm ssbs sb paca pacg dcpodp flagm2 frint i8mm bf16 bti
```

**There is no SVE or SVE2.** Armv9 cores normally imply it, but Qualcomm does
not expose it here. This is the single biggest trap in this codebase: any LLVM
CPU name from the Armv9 family turns SVE on by default, and SVE codegen on this
device is unselectable. `sanitize_android_arm64_llvm_cpu` in
`util/JITLLVM.cpp` exists solely to catch that and fall back to `cortex-a78`.
Upstream's two SVE commits (`4a92d96cf`, `6349ea2ee`) must never be ported.

## What the JIT tells LLVM

`jit_compiler` sets `mcpu=cortex-a78` plus an explicit attribute list. On device
the line reads:

```
JIT: LLVM AArch64 target: cpu=cortex-a78 triple=aarch64-unknown-linux-android
     attrs=+sha3,+dotprod,+i8mm,-sve,-sve2
```

`cortex-a78` is Armv8.2, so `lse`, `rdm`, `crc`, `fp16` come implied. Anything
newer than v8.2 does **not**, even though the device has it: `lrcpc`, `flagm`,
`flagm2`, `frint`, `fcma`, `sha512`. Adding a feature to that list is free when
it is gated on the matching `utils::has_*()` and paired with an explicit
negative for hosts without it, which is the pattern `+sha3`/`-sha3` follows.

AOT code is built `-march=armv8.2-a -mtune=cortex-a715`. Atomics are real
inline LSE, confirmed by zero `__aarch64_cas*` / `__aarch64_ldadd*` undefined
symbols in the built objects, so there is no outline-atomics tax to remove.

## Feature to instruction to use-case

What the translators already exploit, so nobody re-derives it:

| feature | instruction | where |
| --- | --- | --- |
| `asimddp` | `SDOT`/`UDOT` | SPU `SUMB`; SPU `GB` bit-gather via a shift-and-sum constant |
| `i8mm` | `SMMLA`/`UMMLA` | SPU multiply widening |
| `sha3` | `BCAX` | SPU `EQV`, and both `SHUFB` selector paths |
| — | `TBL`/`TBX`, `TBL2`/`TBX2` | SPU `SHUFB`, `ROTQBY` family, PPU `VPERM` |
| — | `UABD` | SPU block-verification checksum |
| — | `USHL` | `inf_shl`/`inf_lshr`, dodging an LLVM poison-value pessimization |
| — | `CNT` | SPU `CNTB` via `ctpop` |
| — | `ADDV`/`ADDP` | SPU reductions |

## Measured, on this silicon

`tools/bcax_bench.c` measures a codegen change directly, without needing a game
to boot. Build it with the NDK (`--target=aarch64-linux-android29 -O2
-march=armv8.2-a+sha3 -static`), push to `/data/local/tmp`, pass a cpu index.

BCAX replacing the two-op form, best of five:

| shape | X3 | A715 | A510 |
| --- | --- | --- | --- |
| latency, serial chain | `1.96x` | `2.01x` | `2.00x` |
| throughput, 4 independent chains | `0.94x` | `1.00x` | `2.02x` |

**The two shapes disagree, and which one applies decides whether a change is
worth making.** The big cores have enough vector pipes to issue the old pair in
parallel, so a wider instruction wins nothing there and can lose slightly. It
wins when the result feeds the next instruction. Check the real lowering before
assuming: our `SHUFB` emits `bcax` immediately followed by the `tbx` that
consumes it, so the latency row is the one that describes it.

Boot on a warm cache, measured end to end: SPU cache build finishes around
`50 s` (`module 1179`), title menu follows, and holds `FPS 30.00`, the game's
PS3 target, at `24.7-33.1%` total CPU.

Thermal profile of a direct boot, sampled every 2 s (an earlier 4 s sweep
reported a `57.8 C` peak and simply missed the spike):

```
2s:56.2  4s:60.2  6s:46.2  8s:47.8  10s:44.9 ... 60s:55.0 ... 90s:56.6
```

The transient peaks `60.2 C` at `t=4s` and collapses to `46.2 C` two seconds
later, after which the run sits at `44-57 C` and drifts up slowly. Sample at
2 s or finer; a 4 s sweep aliases the spike.

**The harness is not thermally free.** The same build, game, and settings run
through `thor_input_macro.ps1` climbs `59.4 -> 58.6 -> 61.0 -> 64.6 -> 70.7 C`
within about ten seconds and trips the early stop, while the direct boot above
never leaves the fifties. Its per-sample `adb shell` spawns walk roughly fifty
`thermal_zone*` sysfs entries, the sustain loop adds a poll per second exactly
when the device is hottest, and each readiness poll takes a 1080p `screencap`.
That overhead lands on a machine with no spare headroom during boot. Treat
harness temperatures as an upper bound that includes the observer, and use a
direct `THOR_DEBUG_BOOT` when the question is about the emulator rather than the
route.

## How to verify a codegen change actually landed

Three levels, cheapest first:

1. **Source contract test.** `tools/test_thor_spu_arm64_bcax_lowering.ps1` is
   the model: pin detection, the JIT attribute, the runtime gate, the fallback
   arithmetic, and every call site, so a regression fails on the host.
2. **Backend selection.** Feed the exact IR to NDK clang at the target the JIT
   uses (`-mcpu=cortex-a78+sha3`) and read the assembly. Also compile it
   *without* the feature: if it fails with `Cannot select`, the runtime gate is
   load-bearing rather than decorative.
3. **On device.** The SPU native object cache key hashes the optimized IR plus
   target identity, so a codegen change invalidates stale objects by
   construction. Boot, pull
   `.../BLUS30161/ppu-*/spu-native-v2`, and disassemble with NDK
   `llvm-objdump`. Count the instruction you expect **and** the sequence it was
   meant to replace.

When counting, match two-source `tbx v.16b, { v.16b, v.16b }` as well as
two-source `tbl`. Our `SHUFB` path emits `TBX2`; a `tbl`-only sweep reads as a
false negative and cost hours once.

## Traps that have already cost time

- **The thermal guard trips on a launch transient.** Launch reads `56.6 C` at
  `t=4s` and falls to `46.6 C` by `t=10s`. The harness samples into that spike
  and confirms on an immediate re-read, which force-stopped fifteen consecutive
  runs at `14-30 s` on heat the device never sustained. A run reporting
  `66-71 C` while the emulator overlay reads `Total : 22.7 %` is a tripped
  guard, not an emulation-bound run.
- **The panel's anti-image-retention overlay lands on top of runs.** It engages
  when the display sits static, which any cooldown guarantees, and it survives
  into the next run, so visual gates classify noise. Sleep the panel while
  waiting.
- **FPS is only drawn, never logged.** `overlay_perf_metrics.cpp` renders it
  top-left. A capture screenshot is therefore a measurement; open one before
  trusting any gate boolean.
- **Do not port an upstream ARM tuning fix without checking whether this fork
  already compensated.** Upstream's `busy_wait` scaling dropped Thor to ~1 FPS
  because every call site had already been retuned for the real `19.2 MHz`
  timer; two fixes for one problem multiply.
- **`TBL2`/`TBX2` need a retry owner.** They can trip the AArch64 register
  scavenger. The SPU block compiler has `compile_spu_llvm_with_retry`; the SPU
  interpreter builder deliberately does not, and stays on the plain path.

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
version of the list below evaporated on contact.

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

## The memory model, and the one structural gap left

x86 is total-store-ordered and ARM is weakly ordered, so this is where an
emulator written on x86 is most likely to be subtly wrong. Audited, and the
synchronization primitives hold up:

- **`atomic_t` is conservative by construction.** `load()` is `SEQ_CST`,
  `store()` is `RELEASE`, and every read-modify-write is `SEQ_CST`. On ARM those
  become `LDAR`/`STLR` and full-barrier RMWs, so the default path is safe.
- **`observe()` is the relaxed one, and it is only used for settings.** All
  thirteen uses are config reads behind `#ifdef ANDROID`, values written once at
  boot. That is the one place where relaxed is right and cheap, and it is the
  only place it appears.
- **Fences are real.** `atomic_fence_*` fall through to
  `__atomic_thread_fence`, which emits `DMB` on AArch64; the compiler-barrier
  forms are x86-only, which is correct for TSO.
- **`trigger_write_page_fault` looks alarming and is not.** The ARM64 inline-asm
  path excludes Android, but the generic fallback compiles to
  `ldset wzr, w8, [x0]`, one instruction, because `-march=armv8.2-a` supplies
  LSE. It is actually one instruction shorter than the hand-written version.

Two things that are worth knowing rather than acting on blindly:

- **The GETLLAR fast path is a seqlock, and seqlocks are the classic weak-memory
  trap.** It reads the reservation counter, compares 128 bytes, then re-reads
  the counter and re-compares. Both counter reads are `SEQ_CST`, so nothing can
  hoist above the first one. Acquire is one-way though, so in principle the data
  comparison can sink below the second counter read, which is exactly what a
  seqlock must not allow. The doubled check makes this extremely narrow rather
  than theoretical-only, and this code runs on Apple Silicon upstream, so it is
  recorded as a risk area rather than "fixed" by dropping a `DMB` into the
  hottest SPU path on a hunch. If reservation desyncs ever show up on ARM, start
  here, and make the change with a measurement attached.
- **The SPU atomic fast path is x86-only, and that is the largest remaining
  structural gap.** `utils::has_rtm()` is hard-coded `false` on AArch64, so
  `g_use_rtm` is always false and ARM takes the pre-TSX fallback on all eight
  branches that test it. For a 128-byte atomic store that means
  `vm::writer_lock`: a CAS loop on one shared 64-bit bitmask, plus
  `cpu_thread::suspend_all` on some paths, where x86 uses a hardware
  transaction. Every SPU atomic therefore contends on a single cache line across
  eight cores.

  **Armv8.5 does define transactional memory, FEAT_TME, and this chip does not
  have it.** Decoded from the `ID_AA64ISAR0_EL1` captured on device,
  `0x0021111110212120`: TME is bits [27:24], which read `0`. (Cross-check: bits
  [23:20] read `2`, the FEAT_LSE field, matching what the probe reported.) So
  the "port TSX to ARM transactions" idea is closed, not merely unexplored, and
  nobody needs to re-investigate it on this hardware.

  What remains is therefore a redesign rather than a port: something ARM-shaped,
  such as finer-grained per-reservation locking using LSE. That is a real design
  change with real risk, and it is the highest-value ARM work left here.

  One part of the cost has already come down, though, and it is worth not
  double-counting. The heavyweight path's own bookkeeping runs on 16-byte
  atomics, and those no longer take a cache line exclusive merely to be read
  (see the LSE2 section). The lock is still shared and still contended; it is
  the *reads around it* that got cheaper.

  Related and also closed: the HLE variants in `shared_mutex`
  (`compare_exchange_hle_acq`, `fetch_add_hle_rel`) are x86 lock-elision
  primitives, and they degrade correctly rather than silently. `s_hle_ack` and
  `s_hle_rel` fall back to plain `__ATOMIC_SEQ_CST` when
  `__ATOMIC_HLE_ACQUIRE`/`_RELEASE` are undefined, and clang defines neither on
  aarch64 (verified with `-dM -E`). So those are ordinary seq_cst RMWs on ARM:
  no elision, but no correctness gap and nothing to port.

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

## Open opportunities, ranked

Items 1 to 4 of the original list are resolved: `SQRDMLAH` measured and
declined, the float conversions fixed, `FLAGM` found unreachable, and `eor3`
deleted. What is left:

1. ~~Re-evaluate the A510 cache-worker default.~~ **Done, and it stays.**
   Re-measured after the guard artifact was understood, using
   `SPU Runtime: Built %u functions.` as the completion marker and direct
   `THOR_DEBUG_BOOT` rather than the harness. Both arms launched from `33.9 C`:

   | cache workers | SPU cache build, 1179 functions | peak |
   | --- | --- | --- |
   | A510 cluster, the default | completes at `0:00:52.3` | `53.0 C` |
   | ordinary scheduler | never completes | `70 C` at wall `t=6s`, `71.5 C` |

   The original justification was wrong, but the conclusion holds for a better
   reason. Letting the build run on all eight cores puts it on the X3 at full
   clock and takes the device from `33.9` to `70 C` in six seconds, so it cannot
   finish inside the `72 C` bound at all. Pinned to the A510s it completes the
   whole build with `19 C` of headroom to spare. The unmeasured question is
   wall-clock: the ordinary scheduler might finish sooner if allowed to run hot,
   but it would be throttling by then, so that comparison needs a run that is
   allowed past the bound and is not obviously worth taking.
2. **Advertise the features the device actually has.** The JIT sends
   `+sha3,+dotprod,+i8mm,-sve,-sve2` on top of `cortex-a78`, so everything past
   Armv8.2 is invisible to LLVM: `lrcpc`, `flagm`, `flagm2`, `frint`, `fcma`.
   Adding them costs nothing when each is gated on its own `utils::has_*()` with
   an explicit negative, and it lets the backend choose instructions we have not
   had to think about. `frint` turned out unnecessary for the conversions, but
   the general point stands.
   The AOT half of this is now done, as a side effect of needing LSE2. Moving
   `-march` from `armv8.2-a` to `armv8.4-a` also makes clang define
   `__ARM_FEATURE_CRC32`, `__ARM_FEATURE_DOTPROD`, `__ARM_FEATURE_FMA` and
   `__ARM_FEATURE_QRDMX` for the whole core. `__ARM_FEATURE_MATMUL_INT8` and the
   crypto family still need explicit `+i8mm` / `+crypto`, and were left off on
   purpose: their only AOT consumers are `gv_dotu8s8x4` and `gv_dotu8x4`, whose
   callers are the PPU interpreter and the rpcsx PPU semantic tree, both cold
   under the LLVM decoder. Widening the baseline for a one-instruction win on a
   path that does not execute is not worth the SIGILL surface.
3. ~~Revisit `mcpu`.~~ **Question answered; change deliberately not made.**
   The open worry was whether negative attributes reliably clear the SVE that a
   real Armv9 scheduling model turns on. They do. Measured with clang at `-O3`
   on identical IR, counting SVE instructions emitted:

   | `-mcpu` | SVE instructions | total |
   | --- | --- | --- |
   | `cortex-a78` | 0 | 46 |
   | `cortex-a710` | 7 | 54 |
   | `cortex-a715` | 7 | 54 |
   | `cortex-x3` | 7 | 54 |
   | `cortex-x3` + `-target-feature -sve -sve2` | **0** | 46 |

   So every scheduling model that actually matches Thor's silicon (X3 + A715 +
   A710 + A510) enables SVE by default, and the JIT's existing
   `setMAttrs({"-sve","-sve2"})` is sufficient on its own to switch it back off,
   producing byte-identical instruction counts to `cortex-a78`. The `+nosve`
   spelling works too. This also confirms `sanitize_android_arm64_llvm_cpu` is
   load-bearing rather than superstition, and that keeping both mechanisms is
   correct for a failure that is an immediate SIGILL in JIT-emitted code.

   The change is still not made, and that is the honest position: moving to a
   closer scheduling model can only affect *how well* code is scheduled, never
   whether it is correct, so the entire case for it is a performance claim. This
   fork cannot benchmark, so there is nothing to justify the risk against. What
   changed is that it is now a measured, safe option rather than an unknown.
   Pinned by `tools/test_thor_arm64_jit_no_sve.ps1`.
4. ~~Audit the other x86 compensations.~~ **Done; the sweep is closed.** See
   below for what the remaining subsystems turned up.

## The power-optimized wait, which ARM has and this fork does not use

The most valuable unexploited hardware feature found in this sweep, and the one
that fits this device's actual constraint, which is heat rather than throughput.

The SPU `GETLLAR` spin has an x86-only fast path. When a thread is waiting for a
reservation line to change, x86 does not spin:

- **`MONITORX` + `MWAITX`** arms a cache line and parks the core in a low-power
  C-state until *that line is written* or a timer expires. The comment in
  `SPUThread.cpp` is right that it "fits reservations almost perfectly".
- **`TPAUSE`** (waitpkg) does the timed half without the address monitor.

Both sit inside `#if defined(ARCH_X64)`. ARM has no counterpart there, so it
falls back to `busy_wait()`, which spins on `yield`. A spinning core on a
passively cooled handheld is heat, and heat is the budget this whole fork is
managed against.

**AArch64 has the same capability**, and has since Armv8.0:

    ldxr  wzr, [cline]      // arm the exclusive monitor on the reservation line
    // re-check the condition here
    wfe                     // park until the monitor is cleared or an event arrives

`WFE` parks the core; a write to the monitored line clears the exclusive monitor
and generates the wake. That is `MONITORX`/`MWAITX` with the operands in a
different order.

**Measured on device, and the numbers change the design.** `ID_AA64ISAR2_EL1`
reads `0`, so **FEAT_WFxT is absent**: there is no `WFET`, and therefore no way
to bound a `WFE` with a timeout. `MWAITX` *does* take a timer, `min(spin, 17) *
500` cycles, so on x86 a missed wake costs microseconds. On AArch64 the only
fallback wake is the generic timer event stream, and that was timed directly:

| sequence | latency |
| --- | --- |
| `sevl; wfe` (event already pending) | 0.007 us |
| `sevl; wfe; wfe` (second one really waits) | **95.06 us** |
| `ldxr; sevl; wfe; wfe; clrex` | **97.33 us** |

So `WFE` genuinely parks — the first naive probe suggested 10ns and was wrong,
because its loop never actually consumed the pending event. Confirming that took
`SEVL` to set the event register deliberately, then timing the *second* `WFE`.
**When a probe reports a number that would be physically surprising, the probe is
usually what is broken.**

The consequence is a real asymmetry. The exclusive monitor granule is one cache
line, 64 bytes, while a reservation is 128. A writer touching only the second
line may not clear a monitor armed on the first, and the waiter then eats the
full ~95us instead of the microseconds `MWAITX` would cost. That is why the
implementation only parks once `getllar_spin_count >= 8`: spinning through the
early iterations keeps a 95us worst case off short waits, where it would
dominate, and confines it to waits already long enough not to care.

Also confirmed while probing: `CNTFRQ_EL0` is `19200000`, cross-checking the
19.2MHz generic timer that `asm.hpp` documents and that the busy-wait tuning
depends on.

The safe shape matters and is worth writing down, because the unsafe shape
deadlocks. Arm the monitor, **re-check the condition after arming**, then `WFE`,
all inside the existing retry loop. A spurious wake then costs one extra
iteration instead of a hang, and a missed event cannot wedge the thread because
Linux/arm64 enables the generic timer **event stream**, which delivers a
periodic event (order 100us) that wakes `WFE` regardless. Without that event
stream a plain `WFE` with no timeout is a hang waiting to happen.

**Implemented behind `RPCSX_THOR_ARM64_WFE_WAIT`, default off.**
`-PrpcsxThorArm64WfeWait=1` turns it on. Both configurations build.

Default-off is not hedging, it is the measurement rule. The entire justification
is power and thermal behaviour; the effect on frame time could easily be zero or
slightly negative, because parking a core adds wake latency to the reservation
handoff. A change whose only argument is "this should run cooler" cannot be
switched on by a fork that does not measure, because there is nothing to check
the claim against. It also sits in the hottest SPU path, where the spin counts
were arrived at empirically. So the code is written, reviewed and compiled,
and the decision to enable it is left to whoever can put a thermometer on it.

The emitted sequence was verified rather than assumed:

    ldxr  w8, [x0]           arm the monitor
    bl needs_wait / tbz      re-check AFTER arming
    wfe                      park
    clrex                    release the reservation

Both halves of that order matter. Re-checking *before* arming lets the writer
land in the gap, and the wake it generated is already gone — a lost wakeup, with
the thread sleeping until something unrelated pokes it. `CLREX` must come after
the park, not before, or the reservation is dropped while it is still needed;
leaving a stray monitor armed can also make an unrelated `STXR` fail spuriously.

When measurement becomes possible, the thing to measure is **sustained
temperature and clock residency, not FPS**. A change that lowers power at
constant frame rate is a win on this device and would look like a no-op on a
benchmark chart.

Pinned by `tools/test_thor_arm64_wfe_wait.ps1`, which checks the arm/check/park/
clear order, that both build systems default it off, that the plain busy-wait
fallback still exists, and that the x86 path was not touched.

## The fault handler: ARM hands you what x86 makes you decode

`handle_access_violation` has a large `#if defined(ARCH_X64)` body and an
`#else static_cast<void>(context);`. What lives inside it is **RawSPU MMIO
emulation**: when guest code touches a RawSPU problem-state register, which is
mapped in the guest address space but backed by no memory, the store faults, and
the x86 handler decodes the faulting instruction, performs the register access
itself, then steps over it with `RIP += i_size`.

Making that work on x86 costs a **250-line instruction decoder**,
`decode_x64_reg_op`, which parses prefixes (LOCK, REP, REX, group-2), ModRM and
SIB just to recover "which register, what size, load or store".

The obvious hope is that AArch64 needs none of that, because the ESR carries a
syndrome describing the access, and this codebase **already reads the ESR** in
`AArch64Signal.cpp::_read_ESR_EL1`. The fields exist on paper:

| ESR field | bits | meaning |
| --- | --- | --- |
| `ISV` | 24 | the rest of this syndrome is valid |
| `SAS` | 23:22 | access size |
| `SSE` | 21 | sign-extend |
| `SRT` | 20:16 | which register |
| `SF` | 15 | 64-bit vs 32-bit register |
| `WnR` | 6 | write, not read |

**Measured on device, and the hope does not survive.** A probe that mmaps
`PROT_NONE`, faults deliberately, and decodes the syndrome from the handler
reports `ISV = 0` for *every* case, including the simplest ones:

    ldr  w9,  [p]   esr=0x92000007  ec=36  isv=0  wnr=0
    ldr  x11, [p]   esr=0x92000007  ec=36  isv=0  wnr=0
    str  w13, [p]   esr=0x92000047  ec=36  isv=0  wnr=1
    ldrb w15, [p]   esr=0x92000007  ec=36  isv=0  wnr=0
    stp  x17, x18   esr=0x92000047  ec=36  isv=0  wnr=1

`ISV = 1` is essentially reserved for stage-2 aborts, the virtualization case.
Ordinary stage-1 userspace translation faults do not populate the syndrome, so
`SAS`, `SRT`, `SF` and `SSE` are all zero and mean nothing. What *is* reliable
is the exception class and `WnR`, which are exactly, and only, the two fields
`decode_fault_reason` already uses. That function is not leaving information on
the table; it is using everything the hardware actually provides.

So RawSPU MMIO emulation on AArch64 **would still need an instruction decoder**,
the same as x86. It would be a far smaller one — fixed 32-bit encodings, no
prefixes, no ModRM, no SIB, so the load/store forms are a handful of mask-and-
compare tests rather than 250 lines of parser — but the "hardware tells you what
faulted" shortcut is not available.

That is on top of the reasons it is still not implemented: it runs inside a
signal handler, where a mistake turns a recoverable fault into a crash loop, and
it can only be exercised by a title using RawSPU MMIO rather than SPU thread
groups, which means running a game.

**This entry previously claimed the opposite**, that the port was less work than
the original because the CPU reports the faulting access. That was written from
the architecture manual without checking the part, and it was wrong. The
correction cost one probe. Anything in this document that says a feature "is
available" without a measurement beside it deserves the same treatment.

## Where AArch64 is the stronger architecture

Worth stating plainly, because the whole rest of this document points the other
way: **ARM's `LDAR`/`STLR` are RCsc, and that is stronger than x86 TSO for the
one reordering TSO allows.**

`vm::range_lock` is the case. Both sides publish their range, then read the
other side's state, which is Dekker and needs StoreLoad ordering:

    range_lock->store(to_store);                       // release store
    busy = for_all_range_locks(get_range_lock_bits(true), ...);  // seq_cst load

On AArch64 that is `STLR` then `LDAR`, and an `LDAR` cannot be observed before a
preceding `STLR`, so the ordering is free. On x86 a release store is a plain
`MOV` and a seq_cst load is a plain `MOV`, and **StoreLoad is precisely the
reordering x86 permits**. The exclusive side closes its own half with
`bit_test_set`, an atomic RMW and therefore a full barrier on both.

So there is nothing to fix here for ARM, and it is the one place found in this
sweep where the port is safer than the original. Left alone deliberately: the
protocol is intricate, the reader retries in a loop, and changing the hottest
lock in the memory subsystem on partial understanding is how you buy a rare
corruption bug in exchange for nothing.

**This has a sharp edge, and it is one this fork walked into.** Raising `-march`
to `armv8.4-a` for LSE2 also enables RCPC, and RCPC changes what an *explicit*
acquire load compiles to:

| | `armv8.2-a` | `armv8.4-a` |
| --- | --- | --- |
| `load()` (seq_cst) | `LDAR` | `LDAR` |
| `load(memory_order_acquire)` | `LDAR` | **`LDAPR`** |
| `store(memory_order_release)` | `STLR` | `STLR` |

`LDAPR` is RCpc: it is *not* ordered after a preceding `STLR`. Any code relying
on the RCsc property above would silently lose it, and the symptom would be a
rare mutual-exclusion failure, not a build error.

Checked before trusting the baseline bump. `atomic_t` is seq_cst throughout, so
every `atomic_t::load()` keeps `LDAR` and is unaffected. There are exactly two
explicit `memory_order_acquire` uses in `Emu` and `util`: one is an
`atomic_thread_fence`, which RCPC does not touch, and the other reads a config
flag for the raw object cache and participates in no protocol. Both benign.

The rule for anyone adding one later: **on this baseline, `memory_order_acquire`
buys RCpc, not RCsc.** If a StoreLoad guarantee is wanted, use a seq_cst
operation or an explicit fence, and do not assume the acquire will be an `LDAR`.

## Acquire is one-way, and a seqlock needs both

The reservation seqlock is where TSO quietly did work nobody had to write down.
GETLLAR and the MFC DMA read share a shape:

    t0 = vm::reservation_acquire(addr)        // load-acquire
    ... copy guest data ...                   // plain loads
    if (t0 != vm::reservation_acquire(addr))  // validate
        retry

The copy is only meaningful if it is observed **strictly between** the two
reservation reads. The first read is a load-acquire, so the copy cannot be
hoisted above it. That is the half everyone remembers. The other half:
**load-acquire is one-way.** It orders later accesses after itself and does
nothing to stop earlier accesses from being observed after it. So the copy can
be satisfied *after* the validating read, and a writer that bumped the counter
in between goes undetected — which is precisely the case the check exists for.

x86 never exhibits this, because TSO does not reorder loads with loads. The read
side was correct as written, for the architecture it was written for. There was
no barrier to port because there was never a barrier.

`atomic_fence_acquire()` closes it. On x86 it is a compiler barrier and costs
nothing, so this is not a trade.

The DMA path deserved the fence as much as GETLLAR despite looking better
guarded. It re-compares the copied data, but **only in the 128-byte case**;
every smaller transfer rests on the timestamp check alone.

Two things to carry forward. First, the failure mode is an SPU atomic accepting
stale reservation data, which surfaces as a desync or hang long after the fact
and never as a slow frame — so its absence proves nothing, and no measurement
would have found it. Second, and more useful for the rest of this sweep:
**a barrier that does not exist cannot be found by reading the ARM path**,
because there is no ARM path. Grep for the *shape* — a validated re-read, a
double-check, a publish-then-flag — and ask what TSO was providing for free.
Pinned by `tools/test_thor_arm64_seqlock_fences.ps1`.

## The instruction cache is not coherent, and this chip says so

x86 instruction caches are coherent with the data caches. Write code, jump to
it, done. AArch64 makes no such promise, and crucially **what it requires varies
by implementation and is advertised in `CTR_EL0`**:

    IDC = 1   data cache clean to PoU not required
    DIC = 1   instruction cache invalidation not required

Read on the Thor's Snapdragon 8 Gen 2, by running a probe on the device rather
than assuming: **`IDC=1, DIC=0`**, with 64-byte I and D min lines. So the data
cache does not need cleaning, but **the instruction cache genuinely does need
invalidating**. Apple Silicon reports `DIC=1`, which is almost certainly why
this survived upstream despite RPCS3 running on arm64 Macs: on that hardware
the missing maintenance is harmless.

Seven sites in this codebase carried:

    asm("ISB");
    asm("DSB ISH");

which is wrong three separate ways:

1. **The barriers are reversed.** `DSB` must complete before `ISB`, so the store
   is guaranteed visible before the pipeline is flushed. As written, the flush
   happens first and orders nothing.
2. **Neither is `volatile`, and neither clobbers memory.** The compiler was free
   to move them across the very writes they exist to publish, or delete them.
3. **No cache maintenance at all**, which `DIC=0` says this chip requires.

Where the written range is known it is now invalidated exactly, via
`__builtin___clear_cache`, which consults `CTR_EL0` itself and emits only the
maintenance the implementation needs. Elsewhere the barriers became a single
`__asm__ volatile("dsb ish\n\tisb" ::: "memory")`.

The larger hole was not the hand-written trampolines but **MCJIT**, which writes
far more code than they do. `llvm::SectionMemoryManager` invalidates in
`finalizeMemory`; both custom managers here override `finalizeMemory` to
`return false` and do nothing, so **nothing was invalidating anything** for
compiled PPU or SPU code. They now record each allocated code section and clear
it. Pinned by `tools/test_thor_arm64_icache_maintenance.ps1`.

Two things worth carrying forward. First, this is a correctness fix, not a
speedup, and its failure mode is a stale instruction fetch: an unreproducible
crash or wrong branch, never a slow frame. Do not expect to see it in a
measurement. Second, and more generally: **when an architecture makes a
guarantee optional, read the register that says whether this part provides it**
instead of reasoning from the architecture manual alone. `CTR_EL0` answered in
one device-side probe what no amount of source reading would have settled.

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

## A fix that cannot reach the machine is not a fix

The PPU pass pipeline was the most valuable single find of the whole sweep: the
analysis managers, `PassBuilder` and `FunctionPassManager` all sat inside
`#ifdef ARCH_X64`, and both `fpm.run()` sites were gated with a `// TODO`, so
every PPU module compiled on AArch64 reached the backend from **unoptimized IR**,
not even EarlyCSE. Removing the gate was a one-line change.

It did nothing, and would have gone on doing nothing.

PPU objects are cached as `v7-kusa-<hash>-<settings>-<cpu>.obj`. The `settings`
field carries guest-visible options; it does not describe the host pass
pipeline. So enabling the passes changed the emitted code and changed **nothing
in the key**. Any machine that had already booted a game kept loading its v7
objects, and loading a cached object skips compilation entirely, which is
precisely where the passes live. The measurable effect on a warm cache was zero.

Bumping to `v8` is what makes it real. The cost is one recompilation per module
on the next boot, which the A510-pinned startup cache workers absorb well inside
the thermal bound.

Generalize this, because it is the same shape as the dead LSE2 macro one section
down. **Three distinct ways a change can be perfectly correct and still have no
effect**, all of which look identical to "the optimization did not help":

1. the code is guarded by a macro nothing defines (`ARM_FEATURE_LSE2`),
2. the code is behind an architecture gate that excludes the target (the pass
   pipeline before the fix),
3. the code is live, but a cache keyed on something that did not change serves a
   stale artifact instead (the pass pipeline after the fix),
4. the code is live and correct, but a dependency it needs at runtime was never
   packaged (the adrenotools hooks, below).

The fourth is worth its own note because it cost a whole feature. Custom GPU
driver loading had never worked in this build. `adrenotools_open_libvulkan`
dlopens `libhook_impl.so` and `libmain_hook.so` out of `nativeLibraryDir` and
returns null the instant either is missing, and the APK contained neither:
Gradle's `externalNativeBuild` restricted the CMake target list to
`rpcsx-ui-jni` and `rpcsx-android`, so the four hook libraries were never built.
Every Turnip package failed at load with a bare "failed to load selected
driver". The source was right, the library was vendored, CMake could build it,
and none of that mattered.

What kept it hidden was the absence of a readout. The app reported failures and
said nothing at all on success, so there was no way to tell a working driver
from a silently ignored one. The fix that found the bug was adding one:
load the package, create a throwaway Vulkan instance through it, and print what
the driver says it is. That turned an unfalsifiable feature into a checkable
one, and confirmed the repair — `Adreno (TM) 740, turnip, Mesa 26.0.0-devel,
Vulkan 1.4.335`, where previously there was nothing.

**A feature with no feedback channel cannot be observed to be broken.** If a
subsystem can only report failure, assume it may have been failing the whole
time.

The third is the nastiest because the source looks right, the build looks right,
and a disassembly of freshly compiled code even shows the improvement. Only the
warm-cache path is wrong. When changing codegen, ask what is keyed on it before
concluding anything from a measurement.

The SPU side needed no bump, and the reason is worth recording so it is not
"fixed" later: its native-object cache is default-off, so SPU code is recompiled
every run and the BCAX, `CFLTS` and DMA-stride lowerings were live all along.
That is also why the on-device BCAX verification worked at all.

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

## The dead macro that cost every 16-byte atomic

The single largest find of the sweep, and it was not a missing instruction but a
macro that could never be true.

`util/atomic.hpp` has LSE2 fast paths for `atomic_t<u128>` guarded on
`ARM_FEATURE_LSE2`. There is no ACLE feature macro for FEAT_LSE2, so
`rx/types.hpp` inferred it from `__ARM_ARCH_8_4__`, `__ARM_ARCH_8_5__`,
`__ARM_ARCH_8_6__` or `__ARM_ARCH_9__`. **Clang on AArch64 defines none of
those, at any `-march`.** Verified directly: at `armv8.2-a`, `armv8.4-a` and
`armv9-a` the only things that appear are `__ARM_ARCH 8` or `9` and the
`__ARM_FEATURE_*` family. The comment above the probe even calls itself a hack
because `__ARM_ARCH` "isn't universally defined"; the replacement doesn't work
either. So the macro was never set, and every LSE2 path was dead code.

What the fallback actually does:

| operation | with LSE2 | what we were running |
| --- | --- | --- |
| `load` | `ldp` + `dmb ish` | `ldaxp` / `stlxp` / `cbnz` retry loop |
| `store` | `dmb` + `stp` + `dmb` | falls through to `exchange`, same loop |
| `release` | `dmb` + `stp` | falls through to `exchange`, same loop |

The instruction count is the least of it. `STLXP` takes the cache line in
**exclusive** state, so a thread that only wants to *read* a reservation
acquires it for writing and invalidates every other core's copy. The structure
this happens on is `vm::g_reservations`, shared by every SPU thread, which is
the worst possible place in the emulator to force write-intent onto readers.
This sits directly underneath the contention described in the memory-model
section below.

**The blast radius is wider than the reservation path**, which is worth knowing
because it is easy to read the above and conclude this only mattered for
`GETLLAR`. Every 16-byte `atomic_t` in the emulator went through that loop:

| site | what it is |
| --- | --- |
| `vm::g_reservations` (two sites) | SPU reservation stamps, the case already described |
| `spu_channel_4_t::values` | **SPU mailboxes.** `sync_var_t` is `alignas(16)` and exactly 16 bytes (`u8`+`u8`+`u16`+3×`u32`), so count and all three queued values are one 128-bit atomic. Every `try_pop`, `try_read` and `push` on a channel-4 hits it |
| `s_cpu_bits` | the **global CPU-thread bitmask**, touched by `suspend_all` and by thread state changes, so shared by every thread in the process |
| RSX label store | one `release`, cold by comparison |

The mailbox one is the sharpest. `try_read` is a pure peek, and before this fix
peeking at a mailbox took the cache line **exclusive**, on a structure written by
one thread and read by another. That is the ping-pong described above, on the
SPU/PPU communication path rather than on reservations.

The fix is not to write new NEON but to make the build state what it knows.
`-march` moves to `armv8.4-a`, the lowest baseline that architecturally
guarantees FEAT_LSE2, and CMake defines `ARM_FEATURE_LSE2` explicitly, gated on
that baseline. Deliberately **not** `armv9-a`: Armv9 mandates SVE2 and this
device advertises no SVE, the same constraint `sanitize_android_arm64_llvm_cpu`
exists to enforce on the JIT side.

Two things had to be checked before trusting it, and both hold. An aligned
16-byte `LDP` is only single-copy atomic *with* LSE2, so on a lower baseline
this change would be a data race rather than a slow path — hence the
configure-time guard that refuses the combination. And the alignment has to be
real: `atomic_t<u128>` gets `alignas(16)` from `Align = sizeof(T)`, and
`g_reservations` is `alignas(4096)` with every index a multiple of 16.

Pinned by `tools/test_thor_arm64_lse2_atomics.ps1`, which checks the macro, the
baseline, the Gradle/CMake agreement, the guard, and that the fast paths are
still plain `LDP`/`STP`.

The lesson generalizes past this one macro: **a feature probe that cannot fire
is indistinguishable from a feature the hardware lacks.** Grep for `#if
defined(SOME_FEATURE)` where nothing defines `SOME_FEATURE`, and check the
`-dM -E` output rather than trusting the comment above the probe.

## The rest of the codebase, and why it needed nothing

The sweep that found the eight items in the x86-habit table was carried to the
end. The last three subsystem groups produced no changes, and the reasons are
worth keeping so the ground is not re-covered.

**lv2, HLE modules, Audio and Io are architecture-neutral.** Not "mostly": a
grep for `ARCH_X64`, `_mm_`, `__m128` and `__asm__` across
`Emu/Cell/lv2`, `Emu/Cell/Modules`, `Emu/Audio` and `Emu/Io` matches **zero
files**. These are syscall and device emulation written in portable C++, and
there is no host-architecture assumption in them to port.

**The audio loops already compile to the good form.** They are the one hot-loop
class in that group, and they are written as plain scalar loops, which is the
shape that usually means a missed vectorization. It is not one here.
`convert_to_s16` and `apply_volume_static` both vectorize to eight floats per
iteration, `fmul v.4s` and `fcvtzs v.4s` over `ldp q`/`stp q` with only a
scalar tail. Better still, the `std::clamp` folds *into* the saturating
`fcvtzs` and costs nothing — the same hardware property that made the hand-written
corrections in SPU `CFLTS` and PPU `FCTIW` actively wrong. Written naively, the
clamp is free; written as an x86-style correction, it was a bug.

**Six `gv_` helpers in `rx/simd.hpp` have x86 paths and no ARM path**, out of
179. They are `gv_dots16x2`, `gv_dots_s16x2`, `gv_mul_even_s16`,
`gv_mul_odds_s16`, `gv_exp2_approxfs` and `gv_log2_approxfs`, and ARM has the
instructions to implement all of them: `SDOT`/`SMLAL` for the dot products,
`SMULL`/`SMULL2` for the even and odd multiplies. They are still not worth
writing, because every caller is `Emu/Cell/PPUInterpreter.cpp` and
`ppu_decoder` defaults to `llvm_legacy`. Same conclusion as the SPU interpreter
and for the same reason: **an unported SIMD helper only matters if a default
configuration reaches it.** Establish the caller before writing the NEON.

**Over half the shipped APK was x86_64 code.** Not a codegen habit but the same
reflex one level up: `rpcsxAndroidAbis` defaulted to `arm64-v8a,x86_64`, so
every build carried a second full copy of the core for an architecture this
fork's only target cannot run. In a 96 MiB APK that was 26 MiB compressed and
65 MiB uncompressed, and it doubled the native compile. Defaulting to
`arm64-v8a` took the APK to 70 MiB, a 27% cut, with the property and
`RPCSX_ANDROID_ABIS` override kept for anyone who wants x86_64 back.

The reason it survived so long is worth more than the fix. There *was* a gate
for it, `tools/test_thor_arm64_apk.ps1`, and it *did* check for foreign-ABI
libraries. It defaulted to `app/build/outputs/apk/release/`, and nobody builds
`release`; the variant that goes on the device is `thortest`. The gate passed by
never looking at a real artifact. It now defaults to the most recently built
APK, which is what caught this. **A contract test pointed at a path that is
never produced is worse than no test, because it reports success.**

**`utils::lfence()` is correct on ARM64 despite its `TODO`.** It emits
`isb`, which is an instruction-synchronization barrier and orders no memory
access at all, so it reads like an obvious bug. All three call sites are
`(utils::lfence(), rx::get_tsc())`, serializing before a timestamp read, and
`ISB` before reading `CNTVCT_EL0` is exactly what AArch64 requires to stop the
counter read being reordered. The x86 spelling is `LFENCE` before `RDTSC` for
the same purpose. The code is right; the name and the `TODO` are what mislead.
Worth knowing before "fixing" it into a `DMB ISHLD`, which would be slower and
would not serialize the counter. If a genuine load fence is ever needed, it
needs a differently-named helper rather than a change here.
