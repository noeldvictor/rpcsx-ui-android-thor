# Sweeping the remaining x86 intrinsics, and why most of them do not matter

A pass over every `_mm_*` / `__m128i` use outside `3rdparty`, asking one question
per site: is this on a path this device actually executes?

The answer for most of them is no, and that is the useful result — it redirects
effort rather than adding to a to-do list.

## Where the intrinsics are

Seventeen files match. Excluding `sse2neon.h` itself and vendored code, the live
ones are:

| file | what | verdict |
| --- | --- | --- |
| `Crypto/aes.cpp`, `Crypto/aesni.cpp` | AES-NI | **fixed** — see [`aes.md`](aes.md) |
| `Emu/Cell/SPUInterpreter.cpp` | `GB`/`GBH`/`GBB` bit-gather, `MPYA` family | cold, see below |
| `Emu/Cell/PPUInterpreter.cpp` | `MFCR` | already `#if defined(ARCH_X64)` with an ARM64 fallback |
| `Emu/RSX/Common/buffer_stream.hpp` | `_mm_stream_si128` | correct — reaches a real `stnp` |
| `Emu/Cell/SPULLVMRecompiler.cpp`, `Emu/RSX/*`, `util/*` | assorted | not swept in depth yet |

## The interpreters are not the hot path here

Both decoders are LLVM in the shipped profile, and this is enforced rather than
assumed: `tools/test_thor_eternal_sonata_firmware_cache_prepare.ps1` asserts the
managed profile refuses to prepare a cache unless
`ppu_decoder == llvm_legacy` and `spu_decoder == llvm`.

So guest code runs through `PPUTranslator` and `SPULLVMRecompiler`, and the
interpreter bodies are reached only on fallback paths. `SPUInterpreter.cpp`
carries exactly **three** `ARCH_*` guards in the whole file and its `GB`, `GBH`
and `GBB` implementations go through `sse2neon`'s `_mm_movemask_*` unguarded —
which is a genuine x86-ism, on a genuinely cold path.

That is worth stating plainly because the opposite conclusion is the natural one.
A file full of unguarded SSE intrinsics *looks* like the biggest remaining
target. Rewriting it would be a lot of careful, verifiable, measurable work with
approximately no effect on a running game.

`movemask` has no NEON equivalent at all — sse2neon synthesises it from shifts and
a horizontal reduction where x86 has one instruction — so where it *is* hot it is
worth real attention. The recompiler already knows this: the feature table in
CLAUDE.md records SPU `GB` being lowered through a shift-and-sum constant with
`SDOT`, which is the fast path. The interpreter simply never got the same
treatment, and does not need it.

## What this leaves

The honest ranking of remaining x86-derived work, hot first:

1. **`SPULLVMRecompiler.cpp` and `PPUTranslator`** — these *are* the hot path, and
   they emit IR rather than intrinsics, so the question there is not "which
   intrinsic" but "which lowering", which is what
   [`codegen.md`](codegen.md) tracks.
2. **RSX vertex and texture paths** (`RSXThread.cpp`, `ProgramStateCache.cpp`,
   `Host/MM.cpp`) — per-frame work, not yet swept instruction by instruction.
3. **`util/atomic.cpp`, `util/fence.hpp`** — small, but on every reservation.
4. Interpreters — cold; leave them.

## `util/atomic.cpp` and the LSE2 path: checked, and it is live

Next on the ranked list, and it comes back clean — but only after checking, because
two pieces of stale documentation pointed the other way.

`atomic.cpp`'s `_mm_load_si128`/`_mm_store_si128` look like an unported x86-ism.
They are inside `#ifdef _MSC_VER` and never reach clang at all.

The real question is the 128-bit path in `atomic.hpp`, which is on **every**
reservation read. Aligned 16-byte access is single-copy atomic only with
FEAT_LSE2; without it the code falls back to an `LDAXP`/`STLXP` loop, and as the
comment at `atomic.hpp:1051` puts it, that costs an exclusive monitor, a retry,
and *write intent* — so a pure reader invalidates every other core's copy of the
line. On the hottest 16-byte atomic in an emulator whose top spin site is a
reservation loop, that would be a serious find.

It is not live as a problem, because the fast path is enabled. Verified from the
build rather than the source:

```
RPCSX_ANDROID_ARM_ARCH:STRING=armv8.4-a
RPCSX_ANDROID_ARM_LSE2:BOOL=ON
RPCSX_ANDROID_ARM_ARCH_SUPPORTED:INTERNAL=1
```

— identical across all three configured build directories. `CMakeLists.txt:122`
defines `ARM_FEATURE_LSE2=1`, and refuses to do so on a baseline below Armv8.4-A
rather than assuming it, which is the right shape: an aligned `LDP` that is not
architecturally atomic would be a bug that only appears under contention.

Two documentation corrections fall out. CLAUDE.md described the AOT baseline as
`armv8.2-a` (it is `armv8.4-a`), and indexed `memory-model.md` as covering "the
dead LSE2 macro". The macro is not dead; this fork set it, which is exactly what
`atomic.hpp:1049` says happened. Reading either line without checking the build
would have led straight to re-fixing something already fixed.

## The translators: a first look, and it argues the other way

`PPUTranslator` and `SPULLVMRecompiler` are the hot path and the subsystem this
sweep has barely touched. One probe into it, chosen because AltiVec is full of
saturating arithmetic and saturation is where hand-written SIMD usually goes
wrong.

`PPUTranslator::VADDSBS` and friends call `add_sat`, and `llvm_add_sat` in
`CPUTranslator.h:2226` resolves to `llvm::Intrinsic::sadd_sat` / `uadd_sat` — the
LLVM intrinsic, not a hand-rolled compare-and-select. What the AArch64 backend
does with that, verified rather than assumed:

```
sqadd v0.16b   uqadd v0.16b   sqadd v0.8h   sqadd v0.4s   sqsub v0.4s
```

One instruction at every width. Compiling the *same source* for x86-64 SSE:

```
paddsb   paddusb   paddsw   pcmpgtd; pcmpgtd; pcmpgtd ...
```

x86 has saturating add only at 8 and 16 bits. **At 32 bits it has no instruction
at all** and synthesises the result from compares. VMX's `VADDSWS` and `VSUBSWS`
are 32-bit saturating operations, so on this hardware they are *cheaper* than on
the architecture the emulator was written for.

That inverts the framing this document started from. It is also not luck: it
follows from the translators emitting **IR rather than per-ISA intrinsics**, which
lets the backend pick the best encoding for whatever it is targeting. The places
this fork has had to intervene — `BCAX`, `SDOT`, `TBL`/`TBX`, `USHL` — are exactly
the ones where no portable IR construct expresses the operation and a lowering had
to be chosen by hand.

So the review question for the translators is not "where are the x86 intrinsics",
because there are none to find. It is "which operations have no natural IR spelling,
and did the hand-written lowering pick well" — which is a much narrower search than
the file count suggests, and it is what [`codegen.md`](codegen.md) already tracks.

## Method note

Two of the checks in this pass came back "already handled" (`MFCR`, the
non-temporal stores) and one came back "cold" (the SPU interpreter). Only AES was
both live and unexploited. That ratio is the argument for asking *is this
executed* before asking *is this optimal* — the reverse order produces a long
list of correct, useless changes.

## Re-checked: x86 fast path with a slow ARM fallback

Asked directly whether the conclusion was safe, so this sweep looked for a shape
the earlier passes could not see. `tools/check_empty_arch_branches.py` finds
blocks with **no** ARM64 code. It cannot find the more likely failure: an
`ARCH_X64` fast path where ARM64 quietly lands on a generic fallback that
happens to be slow.

Two queries over the whole native tree, excluding `3rdparty` and `llvm`:

| query | result |
| --- | --- |
| `ARCH_X64` blocks with an `#else` and **no ARM64 branch** | **52** |
| ...whose fallback contains a **loop** | **0** |
| ...whose fallback is **unrolled scalar** (≥4 `._u32[N]`-style accesses) | **0** |

**None of the 52 falls back to scalar code.** They fall back to portable v128
expressions, which is the pattern `codegen.md` already documents — the
translators emit IR and the backend chooses the encoding, so there is no x86
habit to strip.

One false positive is worth recording, because it nearly became a finding.
`rx/simd.hpp:1969` (`gv_rol16`) flagged on the first attempt as "x86 fast path,
looping fallback". It is not: it has a proper `#elif defined(ARCH_ARM64)` NEON
branch, and the loop is the generic `#else` for architectures that are neither.
The detector had treated `#elif ARCH_ARM64` as part of the x86 section. Fixed by
requiring the absence of any ARM64 `#el*` line before counting the block.

**This is the fourth independent line of evidence** for the same conclusion:
twelve refuted predictions, the complete upstream ARM64 diff, the inline-assembly
audit, and now the fallback-quality sweep. The x86-to-ARM64 surface in this
codebase is clean.

## Re-checked again: runtime x86 feature dispatch

A fifth shape, and the last one I can think of that the previous sweeps could not
see. All of them look at **compile-time** structure. This looks for **runtime**
dispatch: code calling `utils::has_avx()` / `has_ssse3()` / `has_rtm()`, which
return false on ARM64 and route execution to a fallback with no `#ifdef` anywhere
in sight.

Every call site outside `sysinfo.cpp`:

| site | verdict |
| --- | --- |
| `SPUASMJITRecompiler.cpp` (8 sites) | the **x86 asmjit** SPU backend — emits `x86::` operands, never built for ARM64 |
| `PPUThread.cpp:95, 374, 381` | inside an x86 asmjit builder (`x86::rbx`, `vzeroupper`) — same |
| `PPUInterpreter.cpp:1998` (`has_ssse3`) | the interpreter, which this document already establishes is **cold**: both decoders are LLVM |
| `g_use_rtm` | TSX; false on ARM64 by construction, and the ARM64 path is the non-TSX one that is always taken |

**No runtime x86 dispatch reaches ARM64 execution.** The checks all live in code
that either is not compiled for this target or is not executed on it.

That is five independent shapes now, none of which found anything:

1. arch branches containing no code (`tools/check_empty_arch_branches.py`)
2. x86 fast paths with a looping fallback
3. x86 fast paths with an unrolled-scalar fallback
4. hand-written assembly, all 73 sites
5. runtime x86 feature dispatch

Plus the upstream ARM64 diff, which this fork already matches on every
performance commit.

The x86-to-ARM64 conversion in this codebase is done. What remains is not
translation debt — it is ordinary optimisation of code that is already native,
and twelve measured attempts say the easy wins there are gone too.
