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

## Method note

Two of the checks in this pass came back "already handled" (`MFCR`, the
non-temporal stores) and one came back "cold" (the SPU interpreter). Only AES was
both live and unexploited. That ratio is the argument for asking *is this
executed* before asking *is this optimal* — the reverse order produces a long
list of correct, useless changes.
