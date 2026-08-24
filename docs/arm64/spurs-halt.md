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

## The arm to run

`debug.rpcsx.thor.spurs_store_exclusive`, default 0.

Set it to 1 and the two fast paths take `vm::writer_lock` around the 128-byte
copy, and change nothing else. That is the ONE variable this hypothesis needs.

Do not use `Accurate SPU Reservations` as the test. It closes the same hole, but
it also changes the `PUTLLC` failure path, the `PUTLLUC` path, the LR event
handling near `spurs_addr`, and the recompiled `PUTLLC` success predicate. A
result from it cannot say WHICH of those mattered, and it costs 8.4% CPU.

Three arms on the restored 3D combat savestate, long enough for the fault rate
to separate:

| arm | `spurs_store_exclusive` | `Accurate SPU Reservations` | what a null result means |
| --- | --- | --- | --- |
| control | 0 | false | the shipped profile, and the baseline fault rate |
| narrow | 1 | false | if the halt stops here, the tear is the cause |
| wide | 0 | true | if this stops it and narrow does not, the cause is elsewhere in that setting |

**Read the caution in the code before trusting a clean narrow run.** The accurate
branch of `do_putlluc` already takes `vm::writer_lock` while holding the same
reservation lock bits, so that order is exercised. In `do_putllc` the accurate
path uses `suspend_all` instead, so the ordering the narrow arm introduces there
is NOT already exercised upstream. A stall on that line would look like a fixed
halt, which is the one way this experiment can lie.

The fault rate is the measurement, so the run has to be long enough to see one.
No boot in about 92 controlled sessions produced a halt on demand, so treat a
short clean run as no evidence rather than as a fix.

## The first tear run was VOID, and here is why

Recorded before the result below, because the mistake is more instructive than
the number and it nearly shipped as a finding.

The first three arms passed `acc=''` for Accurate SPU Reservations, intending
"leave it at the shipped default". The shipped default for this title is
`true`, since it was **reverted on 2026-08-23** because the title halts its own
SPU with it off. `AGENTS.md` still listed `false` as shipped, and that stale
line was taken at face value.

So all three arms ran the SAME configuration. Worse, both sites that
`spurs_store_exclusive` patches live inside `if (!accurate)`, so under
`accurate=true` the toggle is **dead code**. The narrow arm could not have
differed from the control no matter what the hypothesis said.

`spurs_addr` was checked for exactly this class of error and came back real. The
configuration was not checked the same way. **Verify every gate an arm depends
on, not just the one that occurs to you.**

## Result: the tear hypothesis is REFUTED

Measured on device, restored 3D combat, 2026-08-23. Three arms, then a fourth
run to remove the one artifact that could have voided them.

| arm | overlaps / plain GETs checked | within 0x80 of `spurs_addr` | fps |
| --- | --- | --- | --- |
| control, shipped profile | 8859 / 15728640 | **0** | 19.10 |
| narrow, `spurs_store_exclusive=1` | 8773 / 14680064 | **0** | 18.50 |
| wide, accurate reservations | 9058 / 14680064 | **0** | 18.80 |

**No plain MFC GET ever overlapped a SPURS control line under an active
reservation lock.** The `do_putllc` fast path applies only to addresses within
0x80 of `spurs_addr`, so if nothing reads those lines concurrently, the tear
described above cannot happen. Steps 2 to 5 of that mechanism do not occur.

The narrow arm also changed nothing, 8773 against 8859, which is noise. So the
fix built for this hypothesis fixes nothing, as expected once the near-spurs
count is zero.

### The check that stopped this being void

A count of zero had a second possible cause. The counter is guarded by
`spurs_addr`, and the same value gates the fast path. `spurs_addr` can hold
`invalid_spurs`, which is `0xffffff80`, and against that value
`addr - spurs_addr <= 0x80` reduces to `addr == 0`. Both the counter and the
fast path would then be dead code, and zero would mean nothing at all.

So the probe was changed to print the value, and a fourth run read it:

    spurs_addr=0x1e97a80 (real).  0 of 5138 within 0x80 of spurs_addr

The address is real. The comparison was live. **The zero is a result, not an
artifact.**

### What the other 8800 overlaps are, and why they say nothing

They are arm-independent by construction, and that is a flaw in the probe rather
than a finding. The probe samples the reservation lock bit, which every path
sets, fast and accurate alike. It therefore cannot tell a protected write from an
unprotected one, and the near-identical counts across three arms are what that
design guarantees. Only the near-`spurs_addr` column carries information.

Anyone reusing `spurs_tear_probe` should read only that column.

## What this leaves standing, and what it does not

Standing, because it is static and does not depend on the refuted mechanism:

- 46 reachable halt sites against 146 from a linear scan.
- Seven of them are alignment asserts with the predicate given above.

**Not standing: the assumption that the halt which fires is one of those seven.**
That was never measured. No reproduction has been caught with the trap decoder in
place, so the halting program counter is still unknown, and **39 of the 46
reachable halts remain unclassified**. The seven were classified first because
they share an obvious idiom, not because there is evidence that one of them fires.

The next honest step is not another fix for this hypothesis. It is either to
classify the remaining 39, or to catch one reproduction and read the program
counter, which the decoder now makes diagnostic.

### And a distinction that was being blurred

There are TWO SPURS failures on this device and they are not the same fault:

| | Transformers | Eternal Sonata and Folklore |
| --- | --- | --- |
| symptom | HALT, `0xffdead00`, a guest assert | STALL, no halt |
| site | unknown program counter | `pc=0x12b0`, `lsa=0x100`, 24-retry cap |
| reservation | unknown | clean: no leaked lock, counter 4, readable |
| reproduces | no, about 92 sessions | yes, on boot |

`0x12b0` is a `WRCH`, not a halt, so the stall is not this assert firing. This
note is about the halt. The stall has its own entry in `AGENTS.md`, and it has
something this does not: **a reproduction.**

## All 46 reachable halts are now classified

`tools/spu_slice.py` recovers the predicate of each one by backward slicing
rather than by matching a shape. It starts from the register the halt tests,
walks back through reachable code, and each time an instruction writes a
register the slice still needs, records it and adds ITS sources.

    python tools/spu_slice.py debug-captures/spu_ls_CellSpursKernel0.bin         --entry 0xf3c4 --entry 0x11e4 --entry 0x12ec --entry 0x12b0

| count | class |
| --- | --- |
| 18 | boolean assert: halts unless the tested condition holds |
| 10 | halts when the value is -1, often an error return |
| 7 | DMA argument assert: address 128-byte aligned AND size a multiple |
| 6 | halts when the value is zero |
| 4 | compound boolean assert: halts unless every condition holds |
| 1 | range assert: halts when the value exceeds 0 |

**Unclassified: 0.** So if a trap ever fires, its program counter now names the
class of check that refused, instead of returning "other check".

`--at ADDR` prints the recovered algebra for one site. On the site decoded by
hand earlier it reproduces that reading exactly:

    0x13690  HEQI r15 imm=0   DMA argument assert
       0x1368c  r15 = (r16 & ~r17) | (r18 & r17)
       0x13688  r18 = 0 - r19
       0x13684  r19 = (r20 == 0) ? ~0 : 0
       0x13680  r20 = r8 & 7
       0x13678  r17 = (r21 == 0) ? ~0 : 0
       0x13674  r8 = SHLQBYI(r4)
       0x13670  r16 = 0
       0x13668  r21 = r3 & 127
       inputs not produced in this slice: r3, r4

Two limits are enforced rather than left as traps for the reader:

- **The slice stops at a flow boundary.** Past a `BI`, `IRET`, `BR` or `BRA` the
  code belongs to another block, so a register live there is an INPUT to this
  block, not something it computed. Without that stop the slice walks into the
  previous function and reports ITS `r3` as the provenance of this function's
  `r3` parameter, which is a different value entirely.
- **The labels state what the code does, not what it means.** A halt on -1 is
  labelled as a halt on -1. That -1 is usually an error return is an
  interpretation, and the tool does not assert it.

### Re-run 2026-08-24 with the configuration set explicitly

| arm | accurate | `spurs_store_exclusive` | fps | cores | tears near `spurs_addr` |
| --- | --- | --- | --- | --- | --- |
| shipped | on | 0 | 18.60 | 5.060 | **0** |
| accOff | **off** | 0 | 19.30 | 5.000 | **0** |
| accOffFix | off | 1 | 18.50 | 5.200 | **0** |

`spurs_addr=0x1e97a80 (real)` in every arm.

**Zero tears near the SPURS control block even with `accurate=off`**, which is
the configuration that actually opens the unprotected fast path. That is a real
refutation. The earlier one was void.

Two other things this run settles:

- **The -8.4% CPU win is real**: 19.30 FPS against 18.60 shipped, +3.8%. The
  reason the setting is refused is the halt, not the speed.
- **The narrow fix cannot yet be claimed to make `accurate=off` safe.** No halt
  appeared in any arm in 90 s, including `accOff`. With nothing to reproduce,
  the fix has nothing to be tested against.

That last point is the honest blocker on recovering the 8.4%. The path to it is
a reproduction of the halt under `accurate=off`, long enough to establish a
rate, not another mechanism proposed from the source.
