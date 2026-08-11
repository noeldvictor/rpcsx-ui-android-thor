# A three-way audit of the hot files

This document compares three copies of the same source files. The three trees
are:

* **ours** — `app/src/main/cpp/rpcsx/rpcs3/`, branch `master`.
* **upstream** — `RPCS3/rpcs3` master, fetched from `raw.githubusercontent.com`
  on 2026-08-10.
* **ARMSX3** — `ARMSX2/ARMSX3` master, fetched the same way.

The method comes from the SPU checksum defect of 2026-08-10. That defect was in
upstream and in our fork, and ARMSX3 had fixed it. A reader who opens one tree
cannot see a defect of that shape. A reader who diffs three trees can.
[`armsx3-comparison.md`](armsx3-comparison.md) records the first result of the
method. This document records the second pass.

## Scope

The audit reads only the files that the gameplay profile makes hot. The profile
is Eternal Sonata gameplay, 119,662 samples, in
[`jit-emitted-code.md`](jit-emitted-code.md). It puts 47.88% of cycles in
JIT-generated code, 20.13% in `spu_thread::process_mfc_cmd`, and 6.2% in
`vm::writer_lock` plus `vm::passive_lock`.

The audit therefore reads these files in all three trees:

| file | our lines | upstream lines | ARMSX3 lines |
| --- | --- | --- | --- |
| `Emu/Cell/SPULLVMRecompiler.cpp` | 10,000 | 10,303 | 10,396 |
| `Emu/Cell/SPUCommonRecompiler.cpp` | 9,640 | 10,024 | 10,103 |
| `Emu/Cell/SPUThread.cpp` | 9,552 | 7,561 | 7,568 |
| `Emu/Cell/PPUTranslator.cpp` | 6,011 | 5,620 | 5,620 |
| `Emu/Memory/vm.cpp` | 2,668 | 2,497 | 2,497 |
| `Emu/CPU/CPUTranslator.h` / `.cpp` | 4,450 / 787 | 4,722 / 734 | 4,654 / 734 |
| `Emu/Memory/vm_reservation.h` | present | present | present |

## Two facts about paths, before any absence is read as evidence

**`util/asm.hpp` is not missing from our tree. It moved.** Our copy is
`rx/include/rx/asm.hpp`. A path lookup against the upstream layout returns
nothing and looks like a deletion.

**`util/simd.hpp` is not truncated in our tree. It split.** Our
`rpcs3/util/simd.hpp` holds 1,015 lines and keeps only the asmjit emitter, which
the SPU asmjit recompiler uses and the ARM64 build does not. The `gv_*`
operations moved to `rx/include/rx/simd.hpp`, which holds 2,236 lines. That file
carries the same set of AArch64 arms as upstream's `util/simd.hpp`: a
function-name comparison of every `ARCH_ARM64` guard finds no function with an
ARM arm upstream that has no ARM arm here.

**Our base is older than upstream master.** `rpcs3_version.cpp:31` reads
`version{0, 0, 36, alpha, 1}`; upstream master is past 0.0.41. Some differences
below are version drift and not decisions. The document says which.

## Verdict table

| # | item | ours | upstream | ARMSX3 | verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | SPU ubertrampoline, instruction cache | no maintenance | no maintenance | flushes before publication | **CORRECTNESS RISK** |
| 2 | PPU `FCTIW`/`FCTIWZ`/`FCTID`/`FCTIDZ` | AArch64 form, NaN fixup | x86 correction on AArch64 | x86 correction on AArch64 | **CORRECTNESS RISK in the other two** |
| 3 | SPU `CFLTS`/`CFLTU` | `fptosi_sat`/`fptoui_sat` | x86 correction, no ARM arm | x86 correction, no ARM arm | **CORRECTNESS RISK in the other two** |
| 4 | `vm::writer_lock` range scan | ~~no read-only skip~~ **ported 2026-08-10** | skips read-only locks | same as upstream | **PORTED, UNMEASURED** |
| 5 | reservation waiter array | ~~8 bytes, unpadded~~ **64-byte padded 2026-08-10** | 128-byte padded | same as upstream | **PORTED, UNMEASURED** |
| 6 | SPU compile deduplication | absent | absent | present | NOT A PROBLEM for gameplay |
| 7 | SPU block checksum | sums the pairs | folds with `UABD` | sums the pairs | fixed here on 2026-08-10 |
| 8 | `cmp_rdata` MLA fold | exact | exact | exact | NOT A PROBLEM |
| 9 | `scan16_rdata` UMAXP mask | exact | scalar loop | scalar loop | NOT A PROBLEM |
| 10 | SPU short-block verify, `udot` | exact | exact | exact | NOT A PROBLEM |
| 11 | `m_use_fma` / `m_use_avx` / `m_use_ssse3` | set by architecture | set by CPU name | set by CPU name | ours is better |
| 12 | SVE lowerings | absent | present | present | correct absence |
| 13 | TSX asmjit builders | `brk` stub | `brk` stub | `brk` stub | NOT A PROBLEM |
| 14 | PPU `VCFUX` | plain `uitofp` | ARM arm plus x86 workaround | same as upstream | NOT A PROBLEM |
| 15 | SPU `CLZ` | plain `ctlz` | ARM arm plus x86 workaround | same as upstream | NOT A PROBLEM |

## 1. The SPU ubertrampoline reaches other cores without cache maintenance

**Verdict: CORRECTNESS RISK.**

`spu_runtime::rebuild_ubertrampoline` writes AArch64 instructions byte by byte
into memory that `jit_runtime::alloc` returns. It then publishes the address
with an atomic compare-and-swap. Another core can branch into that address
immediately.

AArch64 does not keep the data caches coherent with the instruction caches. This
device reports `CTR_EL0.DIC=0`, so the instruction cache needs an explicit
invalidate. Our tree performs no maintenance at this site. Upstream performs
none either. ARMSX3 performs it.

Our tree, `Emu/Cell/SPUCommonRecompiler.cpp:2553-2560`:

```cpp
result = reinterpret_cast<spu_function_t>(reinterpret_cast<u64>(wxptr));

std::string fname;
fmt::append(fname, "__ub%u", m_flat_list.size());
jit_announce(wxptr, raw - wxptr, fname);
}

if (auto _old = stuff_it->trampoline.compare_and_swap(nullptr, result))
```

Upstream, `Emu/Cell/SPUCommonRecompiler.cpp:1970-1977`: the same eight lines,
character for character.

ARMSX3, `Emu/Cell/SPUCommonRecompiler.cpp:2024-2030`:

```cpp
jit_announce(wxptr, raw - wxptr, fname);

#if defined(ARCH_ARM64)
// Flush the freshly written ubertrampoline BEFORE publishing it via the CAS
// below; other cores may branch into it immediately.
asmjit::VirtMem::flushInstructionCache(wxptr, raw - wxptr);
#endif
```

`jit_announce` cannot supply the maintenance. `util/JITASM.cpp:73` shows that the
function writes a `perf` map line and nothing else. It is also off by default,
behind `debug.rpcsx.thor.jit_perf_map`. `jit_runtime::alloc`
(`util/JITASM.cpp:327`) only advances a pointer in a write-execute region.

Our tree already fixed the three sibling sites. `SPUCommonRecompiler.cpp:2702`,
`:2782` and `:2935` call `__builtin___clear_cache` over the exact range that was
written, and each carries a comment about the reversed barriers that came
before. A fourth site, `SPUCommonRecompiler.cpp:2841` in `dispatch()`, keeps
`__asm__ volatile("dsb ish\n\tisb" ::: "memory")` because the LLVM output ranges
are handled in `JITLLVM`. The ubertrampoline is the one writer with no
maintenance at all.

**Reach.** The ubertrampoline is the SPU dispatcher. Every SPU block entry passes
through it, and the runtime rebuilds it whenever it adds a function. The profile
counts that code inside the 47.88% JIT bucket, which no symbolizer names.

**What this document does not claim.** No stale fetch was observed on this
device. The claim is that the architecture permits one and that two of the three
trees do nothing to prevent it.

## 2. The PPU convert-to-integer family applies an x86 correction on AArch64

**Verdict: CORRECTNESS RISK in upstream and in ARMSX3. Our tree is correct.**

x86 `CVTSD2SI` returns `0x80000000` for any value it cannot represent. PowerPC
`FCTIW` returns `0x7FFFFFFF` for a large positive value. Upstream therefore
computes a mask and XORs the result.

AArch64 `FCVTNS` saturates by itself. It already returns `0x7FFFFFFF`. The XOR
then turns a correct value into `0x80000000`.

Upstream, `Emu/Cell/PPUTranslator.cpp:4763-4769`:

```cpp
const auto xormask = m_ir->CreateSExt(m_ir->CreateFCmpOGE(b, ConstantFP::get(GetType<f64>(), std::exp2l(31.))), GetType<s32>());
...
#elif defined(ARCH_ARM64)
SetFpr(op.frd, m_ir->CreateXor(xormask, Call(GetType<s32>(), "llvm.aarch64.neon.fcvtns.i32.f64", b)));
```

ARMSX3 carries the identical lines at `Emu/Cell/PPUTranslator.cpp:4769`. The
whole file diffs clean between upstream and ARMSX3, with zero hunks.

Our tree, `Emu/Cell/PPUTranslator.cpp:5134-5140`:

```cpp
// FCVTNS saturates to 0x7fffffff by itself, which is already the PowerPC
// result, so the x86 correction would flip a correct value to 0x80000000.
const auto conv = Call(GetType<s32>(), "llvm.aarch64.neon.fcvtns.i32.f64", b);
SetFpr(op.frd, m_ir->CreateSelect(m_ir->CreateFCmpUNO(b, b), m_ir->getInt32(0x8000'0000u), conv));
```

The same difference appears at four opcodes:

| opcode | ours | upstream | ARMSX3 |
| --- | --- | --- | --- |
| `FCTIW` | `PPUTranslator.cpp:5138` | `:4769` | `:4769` |
| `FCTIWZ` | `PPUTranslator.cpp:5161` | `:4789` | `:4789` |
| `FCTID` | `PPUTranslator.cpp:5451` | `:5071` | `:5071` |
| `FCTIDZ` | `PPUTranslator.cpp:5474` | `:5092` | `:5092` |

`codegen.md` already records our fix. What is new is the three-way status: both
other trees still ship the inverted correction.

## 3. The SPU float-to-integer opcodes are the same class

**Verdict: CORRECTNESS RISK in upstream and in ARMSX3. Our tree is correct.**

Upstream has no ARM arm at all in `CFLTS` and `CFLTU`. It runs the x86
correction on every architecture.

Upstream, `Emu/Cell/SPULLVMRecompiler.cpp:9036-9037`:

```cpp
r.value = m_ir->CreateFPToSI(a.value, get_type<s32[4]>());
set_vr(op.rt, r ^ sext<s32[4]>(fcmp_ord(a >= fsplat<f64[4]>(std::exp2(31.f)))));
```

ARMSX3 carries the identical lines at `Emu/Cell/SPULLVMRecompiler.cpp:9129`.

Our tree, `Emu/Cell/SPULLVMRecompiler.cpp:8711-8714`:

```cpp
#ifdef ARCH_ARM64
// FCVTZS saturates to 0x7fffffff on overflow, so the x86 correction
// below would flip an already-correct result to 0x80000000.
set_vr(op.rt, fptosi_sat<s32[4]>(a));
```

Four sites again: ours at `:8714`, `:8734`, `:8798` and `:8826`; upstream at
`:9036`, `:9051`, `:9110` and `:9134`; ARMSX3 at `:9129`, `:9144`, `:9203` and
`:9227`. One further `CreateFPToUI` in our tree, at `:8820`, sits behind
`m_use_avx512`, which is false on this device.

## 4. Our `vm::writer_lock` scans read-only range locks

**Verdict: DEGRADED vs UPSTREAM. This is version drift, and it is not
architecture-specific.**

**Ported on 2026-08-10. Read the section at the end of this document.** The
line numbers below describe the tree before the port. The section at the end
also corrects this one: the upstream change touches `SPUThread.cpp` as well,
and the `vm.cpp` half alone does nothing.

Upstream added an early exit to the range-lock scan inside the writer lock. The
scan skips a lock that only marks a range readable.

Upstream, `Emu/Memory/vm.cpp:542-549`:

```cpp
to_clear = for_all_range_locks(to_clear & ~get_range_lock_bits(true), [&](u64 addr2, u32 size2)
{
    constexpr u32 range_size_loc = vm::range_pos - 32;

    if ((size2 >> range_size_loc) == (vm::range_readable >> vm::range_pos))
    {
        return 0;
    }
```

ARMSX3 matches upstream. `Emu/Memory/vm.cpp` diffs clean between the two, with
zero hunks.

Our tree, `Emu/Memory/vm.cpp:751-754`, goes straight to the 64K page loop with no
such test. The whole `writer_lock` constructor is ours at `vm.cpp:643` and
upstream at `vm.cpp:450`.

The profile puts `vm::writer_lock` at 4.49% of gameplay cycles. This document
gives no number for the skip, because nobody measured it here. The change is
portable and small.

## 5. Our reservation waiter array is not padded

**Verdict: DEGRADED vs UPSTREAM. Version drift again, and again not
architecture-specific.**

**The padding is ported on 2026-08-10, at 64 bytes. Read the section at the end
of this document.** The line numbers below describe the tree before the port.
The index redesign is separable from the padding, and it stays out.

Our tree, `Emu/Cell/SPUThread.cpp:1642`:

```cpp
std::array<atomic_t<reservation_waiter_t>, 1024> g_resrv_waiters_count{};
```

Upstream, `Emu/Cell/SPUThread.cpp:521`, and ARMSX3, `Emu/Cell/SPUThread.cpp:521`:

```cpp
std::array<atomic_t<reservation_waiter_t, 128>, 1024> g_resrv_waiters_count{};
```

Our `reservation_waiter_t` (`Emu/Memory/vm_reservation.h:39`) holds eight bytes,
so eight waiters share one 64-byte cache line. Upstream redesigned the index in
`vm_reservation.h:43-53` at the same time, so this is not a one-word change.

**Do not copy the 128 if this is ported.** This device has a 64-byte cache line,
which `CTR_EL0` confirms. The value 128 is an x86 choice, because Intel pairs two
64-byte lines in its adjacent-line prefetch. The same caution applies to the
range lock, where upstream now writes `atomic_t<u64, 128>` (`vm.cpp:76`) and our
tree writes `atomic_t<u64, 64>` (`vm.cpp:102`). Our value is the right one for
this chip.

## 6. ARMSX3 deduplicates SPU compilation, and we do not

**Verdict: NOT A PROBLEM for the measured workload. Ranked low.**

ARMSX3 adds an `llvm_compile_state` claim to `spu_item`, so a second thread
waits for the owner instead of compiling the same program again
(`Emu/Cell/SPULLVMRecompiler.cpp:1658-1737`). It also refuses to compile on a
poisoned engine (`:1636`), and it falls back to the SPU interpreter when a block
cannot compile (`Emu/Cell/SPUCommonRecompiler.cpp:2266-2300`).

These changes act during compilation. The profile is a warm-cache gameplay run,
so it does not cover them. They are worth reading again if a cold boot becomes
the subject, because our tree does hang during SPURS bring-up.

## Items checked and cleared

Each row below was read in all three trees. The audit reports them so that no
later pass repeats the work.

**The SPU block checksum is fixed here.** Our tree sums the pairs
(`SPULLVMRecompiler.cpp:1952-1957`, and the emitted form at `:2004` and
`:2074`). ARMSX3 sums them (`SPULLVMRecompiler.cpp:2110-2115`). Upstream still
folds with `UABD` (`SPULLVMRecompiler.cpp:2029` and `:2031`). Upstream also gained a loop form of the x86
checksum that our older base does not have; that form does not touch ARM64.

**`cmp_rdata` is exact.** `cmp16_pair_accum_arm64` multiplies two compare masks
and accumulates (`SPUThread.cpp:1204-1210` here, `:257-266` upstream, `:257-266`
in ARMSX3). Each lane pair contributes 1 only when both lanes match, the total
maximum is 32, and the test is `vaddvq_s16(hits) == 32`. Nothing saturates and
nothing wraps. Our tree adds a runtime switch to an XOR-OR tree
(`SPUThread.cpp:1255`) that the other two trees do not have.

**`scan16_rdata` is exact.** Our AArch64 form
(`SPUThread.cpp:1291-1324`) reduces eight XOR vectors with `UMAXP` twice, then
weights the lanes and adds across. An unsigned maximum is zero only when every
input is zero, and the lane weights are distinct bits, so the sum equals the
bitmask that the scalar loop builds. Upstream and ARMSX3 keep the scalar loop
(`SPUThread.cpp:338`).

**The short-block SPU verification is exact.** The `udot` path accumulates
`0xff * 0xff` for each byte position where both compares match
(`SPULLVMRecompiler.cpp:2167-2212`). The expected constant is
`expected_hits * 16 * 0xff * 0xff`. Any single mismatch changes the total by
65,025, and the block size caps the count far below the wrap point. All three
trees agree here.

**`m_use_fma`, `m_use_avx` and `m_use_ssse3` are better here.** Upstream and
ARMSX3 set them from a default inside `#ifdef ARCH_ARM64`
(`CPUTranslator.h:3215-3237`). Our tree sets them from the architecture in
`CPUTranslator.cpp:220-234` and explains why a CPU-name allowlist is the wrong
instrument. The end state matches: all three enable FMA and the wide checksum
stride on AArch64.

**The SVE lowerings are absent here on purpose.** Upstream and ARMSX3 carry
`sve_smullb`, `sve_umullt`, `sve_fnmls`, `sve_xar` and a `m_use_sve_128` flag.
This chip has no SVE. Their absence is correct and must stay.

**The TSX builders are stubs on ARM64 in all three trees.** `spu_putllc_tx`,
`spu_putlluc_tx` and `spu_getllar_tx` emit `c.brk(Imm(0x42))` outside
`ARCH_X64` (`SPUThread.cpp:2096`, `:2222`, `:2357` here). The
runtime never calls them without RTM.

**PPU `VCFUX` and SPU `CLZ` are equivalent.** Upstream guards an AArch64 arm and
puts an x86 workaround in the `#else`. Our older base has only the direct form,
which is what the upstream ARM arm does. `PPUTranslator.cpp:1326-1330` here
against `:1135-1156` upstream; `SPULLVMRecompiler.cpp:6496-6499` here against
`:6719-6745` upstream.

**Our `s_rep_movsb_threshold` macro is deliberate.** `SPUThread.cpp:1159`
redefines the name as a call to `thor_rep_movsb_threshold()`, default 1024.
Upstream defines it as `umax` (`SPUThread.cpp:201`), which makes the `memcpy`
branch dead. ARMSX3 matches upstream. The 1024 is a measured 13.8% win; see
[`busy-wait-inventory.md`](busy-wait-inventory.md).

## What the audit did not find

**No second non-injective fold.** The audit read every AArch64 arm in the six hot
files and checked each reduction for injectivity. The checksum was the only one
of that shape, and it is fixed.

**No dead AArch64 branch.** A script walked every `#if`, `#elif` and `#else` on
`ARCH_X64`, `ARCH_ARM64`, `__x86_64__` and `__aarch64__` in the hot files, to the
matching `#endif`, including nesting. Every x86-only block in the hot files is
either an x86 helper definition that the ARM build never calls, or has an `#else`
that this document accounts for above.

**No unused hardware worth proposing.** The chip offers `aes`, `pmull`, `sha512`,
`crc32`, `bf16`, `flagm`, `flagm2`, `frint`, `rcpc` and `jscvt` beyond what the
JIT enables. None of them replaces code in the hot list. `EOR3` is available and
unused as a helper, and `CPUTranslator.h:3877` states the reason: with `+sha3`
advertised, LLVM forms `EOR3` from `a ^ b ^ c` by itself.

## What to do next, in order

1. **Take the ubertrampoline flush.** It is the only correctness item in this
   pass. Copy the shape our tree already uses at the three sibling sites:
   `__builtin___clear_cache` over `[wxptr, raw)`, before the compare-and-swap.
2. **Report items 2 and 3 upstream.** Both are live defects in `RPCS3/rpcs3`
   master and in ARMSX3, and our fix is small.
3. ~~**Consider the `writer_lock` skip.**~~ **Done on 2026-08-10.** See the
   section below.
4. ~~**Leave item 5 alone for now.**~~ **Done on 2026-08-10, as the padding
   only.** The index redesign stays out. See the section below.

---

# Fixed: the ubertrampoline now flushes the instruction cache

Finding 1 is fixed in `Emu/Cell/SPUCommonRecompiler.cpp`. The function writes
AArch64 instructions through a data mapping. It then publishes the pointer with a
compare-and-swap. Another core can branch into the code at once.

`CTR_EL0.DIC` reads 0 on this chip. The hardware therefore does not keep the data
cache and the instruction cache coherent. The new code can sit in the data cache
while instruction fetch reads a stale line.

The fix adds one call before the compare-and-swap:

```cpp
__builtin___clear_cache(reinterpret_cast<char*>(wxptr), reinterpret_cast<char*>(raw));
```

The same file already does this at three other patch sites. This site did not.
Our tree and upstream RPCS3 both miss it. ARMSX3 found it first.

**Not measured, and it cannot be.** This defect is silent and intermittent. A
stale instruction fetch produces a wrong branch, not a log line. The argument is
the architecture, not a benchmark:

* The chip reports `DIC=0`, so software must invalidate.
* Three sibling sites in the same file already invalidate.
* A sibling fork invalidates here.

The build passes with no errors and no new warnings. The device was not touched.

**What a test cannot check.** A grep can confirm the call is present. A grep
cannot confirm that every future write to executable memory adds one. The class
is the same as `mov_rdata`: correct code, one missing line, and no symptom until
a rare timing window opens.

---

# Ported: the read-only skip in the writer lock range scan

Finding 4 is ported on 2026-08-10. The source is upstream RPCS3 commit
`1250e428a75c227a8c929b5b51babba6414a8029`, "SPU: Exclude reservation_check
address receptacle from writer_lock", dated 2025-10-31.

## The commit changes two files, and the audit above quoted only one

The `vm.cpp` half alone does nothing. It tests a flag that no reader ever sets.
`spu_thread::reservation_check` must stamp its range lock slot with
`vm::range_readable` first. The scan then reads that flag and skips the slot.
This document records the full shape, because a port of the quoted half is a
silent no-op.

Our tree, `Emu/Cell/SPUThread.cpp:7073` and `Emu/Cell/SPUThread.cpp:7157`:

```cpp
range_lock->store(u64{128} << 32 | addr | vm::range_readable);
```

Upstream, `Emu/Cell/SPUThread.cpp:5022` and `:5103`: the same line. The line
before the change reads `range_lock->store(u64{128} << 32 | addr);` in both
trees.

Our tree, `Emu/Memory/vm.cpp:767-770`:

```cpp
constexpr u32 range_size_loc = vm::range_pos - 32;

if ((size2 >> range_size_loc) == (vm::range_readable >> vm::range_pos))
{
    return 0;
}
```

Upstream, `Emu/Memory/vm.cpp:544-549`: the same five lines. The flag constants
match in both trees. `vm_locking.h:17-28` here and `vm_locking.h:17-28` upstream
give `range_readable = 2ull << 61` and `range_pos = 61`.

## One deviation from upstream, and the reason for it

The stamp puts the flag bits in the top three bits of the size half of the lock
word. Three functions scan range lock slots:

| function | our line | what it scans |
| --- | --- | --- |
| `range_lock_internal` | `vm.cpp:324` | the exclusive slots |
| `_lock_main_range_lock` | `vm.cpp:487` | the reader slots |
| `writer_lock::writer_lock` | `vm.cpp:758` | the reader slots |

`range_lock_internal` already strips the flags with
`size_exec = (size_exec << range_bits) >> range_bits;`. `writer_lock` now skips
the readable slot before it uses the size. `_lock_main_range_lock` does neither,
in our tree and in upstream, so after the stamp it reads the size as
`0x40000080` — one gigabyte and 128 bytes.

That value is wrong in two directions. It usually reports an overlap that does
not exist, which makes a page protection change wait longer than it must. It
can also wrap the end address above `0xBFFF'FF80`, and a wrapped range reports
**no** overlap where a real one exists. The second direction is a correctness
loss, and it is narrow: it needs a reservation on an address above
`0xC000'0000` at the same time as a map, unmap or protect of the same page.

So this port adds one line that upstream does not have,
`Emu/Memory/vm.cpp:494`:

```cpp
size2 = (size2 << range_bits) >> range_bits;
```

The line restores the exact behaviour that `_lock_main_range_lock` has today.
It is the smallest change at that site, not an optimization. Report the missing
strip upstream together with items 2 and 3.

## Reach, and what is not claimed

The profile puts `vm::writer_lock` at 4.49% of gameplay cycles, with six SPU
threads inside it at the same time. `spu_thread::do_putllc` is 16.91% of the
20.13% that `spu_thread::process_mfc_cmd` holds. The skip removes the 64K page
loop for every reservation check that a writer scans.

**Not measured.** The device was not touched for this change. This document
gives no number for the saving, and none should be quoted until an A/B on
Folklore or Eternal Sonata produces one.

**Not ported: the `busy_wait` timer scaling.** Upstream scales its `busy_wait`
arguments for the timer frequency. Every call site in this fork is already
retuned for the real 19.2 MHz timer, and two fixes for one problem multiply.
The last attempt dropped Thor to about 1 FPS. `CLAUDE.md` records it.

**Kept: the two local changes in this function.** The config-gated
`busy_wait(5000)` head start stays at `vm.cpp:682`. The
`thor_wait::profiled_busy_wait` wrapper stays at `vm.cpp:716`.

---

# Ported: padding on the reservation waiter array

Finding 5 is ported on 2026-08-10, as the padding only.

## What changed

Our tree, `Emu/Cell/SPUThread.cpp:1644`:

```cpp
std::array<atomic_t<reservation_waiter_t, reservation_waiter_align>, 1024> g_resrv_waiters_count{};
```

`reservation_waiter_align` is `64` and it lives at
`Emu/Memory/vm_reservation.h:58`. Upstream writes the same array as
`std::array<atomic_t<reservation_waiter_t, 128>, 1024>`
(`Emu/Cell/SPUThread.cpp:521`), and ARMSX3 matches upstream.

**The 128 is not copied.** This chip has a 64-byte cache line and a 64-byte
CWG, both read from `CTR_EL0`. The 128 is an x86 choice, because Intel pairs
two 64-byte lines in its adjacent-line prefetch. Our range lock already writes
`atomic_t<u64, 64>` where upstream writes `atomic_t<u64, 128>`, so 64 keeps the
fork consistent.

## The memory cost

`reservation_waiter_t` holds eight bytes. The array holds 1024 slots.

| | bytes for each slot | slots | total |
| --- | --- | --- | --- |
| before | 8 | 1024 | 8,192 |
| after | 64 | 1024 | 65,536 |

The array grows by 57,344 bytes. It is one static object in
`librpcsx-android.so`.

## Why the padding can matter here

`reservation_notifier` (`vm_reservation.h:60-70`) gives eight slots to each
address group. A waiter parks on slot `waiters_index % 8` of its group. The
notifier writes `waiters_index` in slot 0 of the same group. Eight slots of
eight bytes fit in one 64-byte line, so every notify invalidates the line that
every waiter of the group reads. The profile puts six SPU threads in
`vm::writer_lock` at the same time, each spending 15-19% of its own time there,
about 95% of it self time.

## What is not ported, and why

Upstream also redesigned the index. Upstream keys the slot on the address
**and** the reservation time, drops `waiters_index`, changes
`reservation_waiter_t` to two `u32` fields, and gives `wait_flag` an
odd-or-even meaning for notification deduplication
(`Emu/Memory/vm_reservation.h:37-104` upstream). That redesign changes the
notify protocol and the signature of five functions. Our `lv2.cpp:1690`,
`lv2.cpp:1735` and `PPUThread.cpp:3675` read the index that the redesign
removes.

The padding is separable from the redesign, and only the padding is here. The
redesign stays out until somebody measures a reason for it.

## Every user of the array was checked before the stride changed

A half-updated stride boots and corrupts rarely, so this list is the guard.

| site | what it does | state |
| --- | --- | --- |
| `SPUThread.cpp:1644` | defines the array | updated |
| `vm_reservation.h:62` | declares the array | updated |
| `vm_reservation.h:67-69` | indexes by slot number | unchanged, correct |
| `vm_reservation.h:76` | takes a pointer difference | unchanged, correct |
| `vm_reservation.h:85`, `:96`, `:98` | name the element type | updated |
| `vm_reservation.h:156` | pointer difference to a `u8` index | unchanged, correct |

Nothing computes `sizeof` of the array. Nothing memsets it. Nothing walks it
with a byte stride. All the call sites in `SPUThread.cpp`, `PPUThread.cpp` and
`lv2.cpp` take the pointer through `auto`, so the type change reaches them
without an edit.

## Not measured

The device was not touched. Both ports are unmeasured. The build reports zero
errors, and the three contract tests pass:
`tools/test_thor_spu_checksum_fold.py`, `tools/test_thor_lv2_spin_sites.py` and
`tools/check_empty_arch_branches.py`.
