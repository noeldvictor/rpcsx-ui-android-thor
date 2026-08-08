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

## Method note

Two of the checks in this pass came back "already handled" (`MFCR`, the
non-temporal stores) and one came back "cold" (the SPU interpreter). Only AES was
both live and unexploited. That ratio is the argument for asking *is this
executed* before asking *is this optimal* — the reverse order produces a long
list of correct, useless changes.
