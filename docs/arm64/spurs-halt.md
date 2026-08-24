# The SPURS halt: what the guest actually refuses

Part of the notes indexed from [`AGENTS.md`](../../AGENTS.md).

Transformers and Folklore both stop with an SPU access violation at
`0xffdead00`. That address is an emulator trap from `make_halt()`, so the guest
executed a halt instruction. The SPURS kernel checked a value, did not accept
it, and stopped itself. Background is in the Transformers section of
`AGENTS.md`.

This note records WHICH check refuses, and what that tells you about where to
look. It replaces guessing with a read of the code that halts.

## The result

**Seven halt sites in the SPURS kernel are argument asserts on a DMA or atomic
call. They halt when a pointer is not aligned to 128 bytes.**

An assert on alignment refuses a POINTER. It cannot be made to fire by a change
of schedule. This is the most useful fact in this note, and the next section
says why.

## Why this closes a long dead end

Ten mechanisms were excluded before this analysis, across about 92 controlled
sessions with no reproduction. Four of them were not merely observed but
FORCED, by fault injection that made the suspected condition happen on purpose:

| forced mechanism | injected | result |
| --- | --- | --- |
| missed SPURS notification | 3840 of 30713 notifications dropped | no halt |
| limiter over-sleep | wait scale 3x, 7680+ applications | no halt |
| limiter serialised | `max_run` clamped to 1, applied 16896 times | no halt |
| block verifier collision | 8080 two-edit mutations per row | no halt |

Every one of those perturbs TIMING or SCHEDULING. None of them can make a
pointer misaligned. So those four null results do not bound this failure at all.
They were the wrong class of fault, run for a long time.

Read that as a correction, not as a loss. The instrument was sound; it was
pointed at the wrong quantity.

## How the halt sites were found

A linear scan cannot answer this. The SPU opcode space is dense, so nearly every
word of a local store decodes as a valid instruction, and a scan of the captured
256 KB image reports **146** halt-shaped words with no way to tell code from
data.

Recursive descent from an address that really executed does answer it. The walk
uses the decode table of the emulator itself, `Emu/Cell/SPUOpcodes.h`, so it
cannot disagree with what the recompiler decodes.

    python tools/spu_cfg.py debug-captures/spu_ls_CellSpursKernel0.bin \
        --entry 0xf3c4 --entry 0x11e4 --entry 0x12ec --entry 0x12b0

The entry points are program counters that were observed on the device: the
program counter recorded in the local store dump, and the SPURS thread program
counters from `/diag`. Starting at address 0 finds nothing, because address 0
holds `STOP` in a thread that runs.

Result: **5665 instructions reachable, 22660 bytes, and 46 halt sites.** So a
linear scan over-reports by a factor of three.

Two checks that the walk is not following invented code:

- **No branch target wrapped** the 256 KB address space. A wrapped target is how
  a mis-decode seeds a false region.
- **The opcode histogram is compiler output.** The most common are `WRCH`, `IL`,
  `LQD`, `NOP`, `LQR`, `STQD`, `ORI`, `AI`, `A`, `ANDI`. That is DMA setup and
  quadword traffic, which is what SPU code is. Rare opcodes are 0.86%.

## The idiom

Seven of the 46 reachable halts share one shape. They are a cluster of DMA
helpers from `0x133c0` to `0x137d0`. Each is a `BRSL` target, so each is a
function entry, called one to three times from `0x8a7c` to `0xa2d4`:

    ANDI    r17, r3, 127     is the effective address aligned to 128 bytes
    SHLQBYI r16, r4, 4
    ANDI    r15, r16, 7      is the size a multiple of 4, 8 or 16
    CEQI    r8, r17, 0
    CEQI    r13, r15, 0
    SFI     r7, r13, 0
    SELB    r10, r12, r7, r8
    HEQI    r10, 0           halt unless BOTH conditions hold

`SELB rt, ra, rb, rc` is `(ra AND NOT rc) OR (rb AND rc)`, and `r12` is zero, so
`r10` is one only when the address and the size are both acceptable. `HEQI`
halts when `r10` is zero. The guard is therefore:

> halt unless `(r3 AND 127) == 0` and `(size AND mask) == 0`

`r3` and `r4` are the first two arguments in the SPU ABI. All seven asserts
resolve to `r3` as the address.

The other 39 reachable halts are different checks. One, at `0x011ec`, is an
unconditional panic stub reached from a `BRNZ` at `0x00f9c`. The rest are not
yet classified, and `tools/spu_cfg.py` reports them as "other check" rather than
forcing them into this shape.

### Two errors that this analysis made first

Both are recorded because each was convincing while it lasted.

**Halts were classified by proximity to a channel read.** Fifteen halts appeared
to be guarded by `MFC_RdAtomicStat` or `MFC_RdTagStat`, which pointed straight
at the reservation path. That was wrong. Disassembly of the whole block shows the
channel read sits before a `BI r0`, so it belongs to the PREVIOUS function; the
assert block is the next function and begins at a `BRSL` target. Proximity is not
data flow.

**The address register was read from the nearest mask of 127.** A block can hold
two: the address check, and a later one on a derived value that never reaches the
halt. Block `0x133c0` has `ANDI r17, r3, 127` and then `ANDI r14, r16, 127`.
Taking the nearest names `r16` on four of the seven asserts, and `r16` is a
scratch register, not the pointer that was refused. The address check is always
the earlier one.

## Where to look now

The guest halts on a pointer that it read out of a SPURS structure in main
memory. So the question is who wrote that pointer, and whether the guest can
observe it in a torn state.

**`Accurate SPU Reservations: false` is in the shipped profile**, taken for
-8.4% CPU. See the lever sweep in `AGENTS.md`. That setting governs the exact
path the guest uses to read these structures: `GETLLAR` publishes a 128-byte
reservation line, and the SPURS kernel reads its pointers out of that line.

### The mechanism, read out of the source

On this device `g_use_rtm` is false, because AArch64 has no TSX. Under that
condition the setting decides how a 128-byte reservation store excludes everyone
else:

| path, ARM64 with no RTM | `accurate = true` | `accurate = false` |
| --- | --- | --- |
| `do_putllc`, address within 0x80 of `spurs_addr` | `cpu_thread::suspend_all<+3>` around the copy | bare `mov_rdata`, then `res += 64` |
| `do_putlluc` | `vm::writer_lock` held across the copy | bare `mov_rdata`, then `res += 32` |

`SPUThread.cpp:5424` and `SPUThread.cpp:5735`. Both accurate paths exclude every
concurrent guest memory access. Neither of the fast paths excludes anything.

**The reservation seqlock is still correct in the fast paths.** Both take the
lock before the copy and release it after, and both arrive at 128, so the counter
advances by one line and the low 7 bits clear:

- `do_putlluc` sets `rsrv_unique_lock | rsrv_putunc_flag`, which is 64 + 32 = 96,
  and releases with `+= 32`.
- `do_putllc` sets `rsrv_unique_lock`, which is 64, and releases with `+= 64`.

Any reader that follows the reservation protocol therefore retries and never
tears. **A `GETLLAR` from another SPU is safe.**

The exposure is to readers that do NOT consult the reservation, and there is
one: **plain MFC DMA**. `do_dma_transfer` takes only `vm::range_lock`
(`SPUThread.cpp:4335` and 4427 to 4443). `vm::writer_lock` is exactly the thing
that excludes range-lock holders, and the fast paths do not take it.

So:

1. SPU A does `PUTLLC` or `PUTLLUC` on a SPURS control line. With accurate off,
   it copies 128 bytes with no exclusion.
2. SPU B does an ordinary MFC `GET` of that same line. Its DMA takes a range
   lock, which `writer_lock` would have excluded, and which now excludes nothing.
3. SPU B reads the line part written, so a pointer inside it is a mix of the old
   and the new value.
4. The mixed pointer is not aligned to 128 bytes.
5. SPU B calls one of the seven DMA helpers, the `HEQI` fires, and the SPU halts
   at `0xffdead00`.

SPURS kernels DMA the control blocks of each other with plain `GET`, so step 2 is
not a contrived case. It is what SPURS does.

This also explains the shape of the failure: it needs a narrow race, so it is
rare and not deterministic; it is a data fault, so no timing injection reproduces
it; and it needs several SPUs sharing control lines, so it appears in SPURS and
not elsewhere.

It fits what has been seen. It is rare and it is not deterministic, because it
needs a race window. It survives every timing injection tried so far, because
timing injection does not corrupt data. And it explains why the two affected
titles both load the SPURS kernel of Sony from `libsre` and stop at the same
kind of program counter.

**The unprotected write is verified in source. The causal link to the halt is
not yet measured.** The decisive test is to run the restored 3D combat savestate
with `Accurate SPU Reservations` true and false, long enough for the fault rate
to separate. Until that runs, steps 3 to 5 above are inference.

Note what does NOT follow from this. It does not follow that the setting should
be turned back on: it costs 8.4% CPU on a device that is already thermally
bound, and a fix that protects only the SPURS control lines would cost far less.
Measure first, then choose the narrow fix.

## What the trap now prints

`util/Thread.cpp` decodes the halt in the access violation handler. It already
named the halt form, the program counter and the compared value. It now also
recognises this idiom and prints the pointer that was refused:

    SPU trap is an ALIGNMENT ASSERT: candidate effective address in
    r3 = 0x..., is NOT 128-byte aligned. Size mask checked = 7. This halt
    refuses a MISALIGNED DMA or atomic argument, so look for who wrote this
    pointer, not for a scheduling race.

It prints `r3` to `r6` as whole quadwords, because the assert reads word 1 of the
size register and the preferred slot alone hides it. If the idiom is absent, it
says so rather than inventing an interpretation.

The value of this is that the FIRST reproduction is now diagnostic. Before, a
trap gave a program counter and a value. Now it gives the bad pointer, which is
the fact needed to find the writer.
