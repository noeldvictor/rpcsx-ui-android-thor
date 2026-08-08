# What Rosetta 2 does, and why most of it does not apply here

Rosetta 2 is the best-documented x86-to-AArch64 translator in existence, so it is
the obvious place to look for technique. The conclusion of looking is that its
central problem **does not exist in this emulator**, and its secondary techniques
are already implemented — several of them in a stronger form.

Worth writing down precisely because "steal from Rosetta" sounds obviously right.

## The big one: Rosetta's hardest problem is not our problem

Rosetta translates **x86-64, which has Total Store Ordering**, to AArch64, which
does not. Every x86 load is acquire-like and every store is release-like *by
architecture*. Reproducing that on ARM means either inserting barriers on
essentially every memory operation, or having hardware help.

Apple chose hardware: Apple Silicon has a proprietary per-thread TSO mode that
Rosetta enables. **Snapdragon 8 Gen 2 has no such bit**, so the Rosetta approach
is not merely unavailable, it is unbuyable.

None of which matters, because **this emulator is not translating x86.** The PS3's
PPU is PowerPC and the SPU is its own thing, and PowerPC is *weakly* ordered — in
places weaker than AArch64. The mapping runs the easy direction:

| PowerPC | AArch64 | note |
| --- | --- | --- |
| `lwarx` / `stwcx.` | `ldaxr` / `stlxr` | load-linked/store-conditional, same shape |
| `lwsync` | `dmb ishld` | |
| `sync` | `dmb ish` | |
| `isync` | `isb` | |

And AArch64 is *stronger* than PowerPC in one architectural respect that matters:
since Armv8 it guarantees **multi-copy atomicity**, which PowerPC does not. Any
ordering a correct PPC program relies on is therefore already provided. The
translator never has to manufacture ordering the target lacks — the position
Rosetta is permanently in.

This is the single most useful thing the Rosetta comparison yields, and it is a
negative: **do not go looking for a TSO problem here, and do not add barriers
defensively.** The direction of translation is favourable.

## Lazy flags: already done, and by a better mechanism

Rosetta's best-known software technique is refusing to materialise x86 `EFLAGS`
unless something reads them. Flag computation is otherwise pure waste, since most
arithmetic results are never tested.

The PowerPC analogue is the condition register. `PPUTranslator` handles it at two
levels:

- CR fields are only written when the instruction's record bit is set — see the
  `if (op.oe)` guard on every `VCMP*`.
- When they are written, `SetCrField` goes through `SetCrb`, and CR bits live in
  **SSA locals** via `RegLoad`/`RegStore`, flushed by `FlushRegisters()` only when
  something can observe them.

The second point is the interesting one. Because the bits are SSA values inside a
function, **LLVM's dead code elimination does the laziness**, and does it better
than a hand-written scheme: a CR field computed and then overwritten before any
branch reads it disappears entirely, including transitively across inlined blocks.
Rosetta has to implement that analysis; here it falls out of emitting IR.

## The rest of the checklist

| Rosetta technique | status here |
| --- | --- |
| Hardware TSO | not applicable — PPC is weakly ordered, and the SoC has no such bit |
| Lazy flag materialisation | done, via SSA locals + LLVM DCE |
| AOT translation with an on-disk cache | done — the PPU and SPU native caches |
| Guest-to-host register pinning | done, by LLVM's allocator over SSA values |
| Indirect-branch dispatch table | done — block linking and the dispatch table |
| FP denormal/rounding mode fixup | done — Thor's profile sets DAZ and FTZ |
| Self-modifying code / cache invalidation | done — i-cache maintenance, see `codegen.md` |

## What is actually left, viewed through this lens

Rosetta's remaining edge is not a technique this codebase lacks; it is that Apple
controls the silicon. What that leaves is unglamorous and specific:

- The JIT targets `cortex-a78`, which is Armv8.2. Verified earlier that this
  already implies `rcpc`, so acquire loads are fine — but it omits `v8.3a`/`v8.4a`
  and therefore `flagm`. `RMIF`/`SETF8`/`SETF16` would be the natural way to move
  PPC condition bits into and out of NZCV. **It is unclear that this is reachable
  from LLVM IR at all**, since portable IR has no "set the flags" operation and the
  backend synthesises flags from `icmp`. Worth an experiment, not an assumption.
- The SPU's `CFLTS`/`CFLTU` and VMX's `VCTSXS` convert float to int *with a scale
  exponent and saturation*, which AArch64 does in one fixed-point `FCVTZS
  v0.4s, v1.4s, #n`. Whether the current lowering reaches that instruction is
  **not yet checked** and is the most concrete open item from this pass.

## The pattern, again

Four Rosetta techniques checked, four already present. The one genuine difference
— TSO — is a problem this emulator does not have, because PowerPC and AArch64 are
both weakly ordered and AArch64 is the stronger of the two.

That is the same result as [`x86-isms-sweep.md`](x86-isms-sweep.md) and
[`aes.md`](aes.md): the interesting question is almost never "is there a better
instruction", it is "is this code executed, and how much data goes through it".
