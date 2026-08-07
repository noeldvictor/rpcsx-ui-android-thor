# The audit ledger: what was swept, what is left, and why

The static search space is finite. This records the whole of it, so nobody
re-covers ground or mistakes a closed question for an open one.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## Dimensions audited, and the one that is not code

The sweep was organised by *dimension* rather than by file, because a file-by-file
read misses anything TSO provided for free. Each of these was taken to
completion:

| dimension | outcome |
| --- | --- |
| `#if defined(ARCH_X64)` blocks | enumerated; every unpaired one accounted for in the ledger below |
| corrections written for x86 quirks | `CFLTS`, `FCTIW` family, `VPKUHUS`, `bswap.i128`, `mov_rdata`, `VMSUMSHS`, `VSUMSWS`/`VSUM2SWS` |
| memory ordering shapes | SPU reservation seqlock (fixed), PPU command publish (already correct), `range_lock` (ARM stronger), RSX (already correct) |
| feature probes that cannot fire | `ARM_FEATURE_LSE2` (fixed), HWCAP macros (verified present) |
| host capability by CPU model name | `m_use_fma`, `m_use_ssse3` |
| opcode lowering quality | whole hot SPU table verified against the backend |
| code publication to instruction fetch | i-cache maintenance, MCJIT `finalizeMemory` |
| build and packaging | ABI list, adrenotools hooks, `-march`, LSE2 define, PPU cache version |
| hardware claims in this document | `CTR_EL0`, `ID_AA64ISAR0/2`, `ID_AA64MMFR2`, `ID_AA64PFR0`, `DCZID`, ESR `ISV`, `WFE` latency |

Two dimensions were examined and deliberately not pursued, both because they are
architecture-neutral rather than ARM concerns: `-fstack-protector-strong` and
`_FORTIFY_SOURCE=2` cost something in hot code, but FORTIFY reaches only 15 call
sites here, and disabling hardening is a security trade that has nothing to do
with porting. Symbol visibility needed no work either: the shipped core exports
458 dynamic symbols with LTO on, so intra-library calls are already direct.

**The honest closing state.** The static search space is exhausted; what remains
is not undiscovered code but four decisions blocked on capabilities this fork
does not have, listed under the ledger. Full contract suite at the end: 96 pass,
1 fail, and that failure is `test_thor_cool_title_candidate_artifact.ps1`
refusing to match a rebuilt APK against a recorded proof-run candidate, which is
the behaviour it is supposed to have.

**One measured result worth stating plainly, because it was observed and then
underplayed.** During the control run, Eternal Sonata reached gameplay and read
**29.99 fps** — the 30 fps cap — with CPU utilisation at PPU 12.7%, SPU 38.2%,
RSX 4.3%. The emulator is running this title at full speed with every change in
this document applied, and rendering correctly: characters, foliage, lighting and
text all intact across several scenes. That is not a speed claim, since there is
no before-figure to compare against, but it does establish that none of the SPU
and PPU opcode rewrites, the LSE2 atomics, the seqlock fences or the i-cache
changes broke a real workload.

**The caveat that used to outrank all of it, now partly lifted.** For most of
this work nothing had been measured against a running game: every claim was about
correctness, instruction counts, or hardware capability.

That is no longer wholly true. The wait profiler has since been run on device
during gameplay and produced the first real numbers here — **16.9% of busy CPU
time is spin, 82.5% of it in `GETLLAR`, and `vm_passive_lock` a further 17.5%** —
and a normalized WFE A/B showed the park displacing 20% of the inner spin at
eighteen times the noise floor. See
[`power-and-thermal.md`](power-and-thermal.md).

What remains unmeasured is narrower and should be stated as such: **whether any
of it makes a title run faster, or draw less power.** The instruction-selection
work in particular still has no before-and-after. And the changes most likely to
matter in practice are still the ones that were never about instruction selection
at all: custom GPU drivers going from never-loading to working, and i-cache
maintenance that a stale fetch would have turned into an unreproducible crash.

## The x86-block ledger: what is left, and why each one stays

The sweep is finite, so here is the whole of it. Every `#if defined(ARCH_X64)`
block in `Emu/` and `util/` was classified as ARM-paired, `#else`-paired, or
unpaired, and each unpaired one is accounted for below. Nothing in this list is
an unexamined gap.

| site | what it is | why it stays |
| --- | --- | --- |
| `ProgramStateCache.cpp` ×3 | AVX-512 ICL shader hash and compare, plus their runtime dispatch | AVX-512 has no ARM counterpart. The generic path is what ARM runs, and its hot byteswap was already moved to `REV16` |
| `ProgramStateCache.cpp`, `CPUThread.cpp` | `#include <emmintrin.h>` | a header include, no code |
| `BufferUtils.cpp` ×3 | asmjit SIMD kernels for vertex swap and index upload | exists because SSSE3/AVX are *optional on x86* and need runtime selection. NEON is mandatory, so clang emits it at build time; the `_naive` names are misleading and were verified to vectorize |
| `JITASM.cpp`, `JIT.h` | `simd_builder` | the abstraction those asmjit kernels are written against; unused on ARM for the same reason |
| `JITLLVM.cpp` | `IntelJITEventListener` | an Intel VTune profiling hook |
| `PPUThread.cpp` | TSX `asmjit` path for `STCX` | no ARM equivalent; FEAT_TME confirmed absent on this chip |
| `PPUThread.cpp` | 16-byte symbol trampoline | an AArch64 version exists directly below it behind `#elif 0`, with its branch-offset bug now fixed; enabling it needs integration checks a game run would provide |
| `SPULLVMRecompiler.cpp` | `!m_use_ssse3` fallback in `ROTQBY` | already inside `ARCH_X64`; ARM uses `pshufb_for_x86_and_tbl_for_aarch64` |

Two things that look unpaired to a naive grep and are not: `SPU_RdDec` in the
SPU recompiler and `SYS_futex_waitv` in `util/sync.h` both use
`#if defined(ARCH_X64) || defined(ARCH_ARM64)`, so ARM is included. A classifier
keyed on `#elif defined(ARCH_ARM64)` reports them as x86-only. Worth knowing
before trusting any such count, including the ones quoted above.

So the block-level sweep is **complete**. What remains is not undiscovered code
but four decisions already made and recorded, each blocked on something this
fork cannot do rather than on analysis:

1. **`WFE` power-optimized wait** — implemented, default off, needs a thermometer.
2. **RawSPU MMIO fault emulation** — needs an AArch64 load/store decoder, since
   `ISV=0` here, and can only be exercised by a RawSPU title.
3. **The range-lock bitmask.** *(Re-scoped twice; read the whole entry before
   acting on it.)* **First re-scope: the original premise was wrong.** Reservation locking is *already* per-address —
   `vm::reservation_lock` takes the 128-byte line's own word, and `g_reservations`
   gives each one its own cache line. The contention is a single instruction
   elsewhere: `bits.bit_test_set(diff)` on `g_range_lock_bits[1]`, one shared
   word, executed on every `vm::writer_lock` and therefore on every PUTLLC via
   `SPUThread.cpp:5109`. Each thread sets a different bit, but an atomic RMW takes
   the line exclusively anyway. LSE was never the missing piece — the cost is
   which line is touched, not how the atomic is spelled. See the contention
   section in [`memory-model.md`](memory-model.md) for the candidate fix, which is
   to drop a redundant presence bitmask rather than to introduce a new lock.

   **Then closed on evidence, and that closure was also wrong.** The wait profiler
   read `vm_writer_lock` at **zero** spin calls across 5.9 million waits, taken to
   mean the shared word is uncontended. It shows only that the *writer* never
   blocks. The **readers** do: `passive_lock` spins while `g_range_lock_bits[1]`
   is nonzero, the shared `writer_lock` path holds a bit in that word for its
   whole lifetime, and `vm_passive_lock` measured **17.5% of all emulator spin —
   1.33M calls, 13.9 core-seconds**.

   So the redesign now has a **measured** target. It is still a change to the
   hottest lock in the memory subsystem, and `bits != umax` doubles as the
   exclusive-lock detector, so the correctness question is unanswered.
4. **`mcpu` to an Armv9 model** — proven safe, benefit is scheduling quality only.

And one correctness question found in passing that is not an ARM matter at all:
`VSUMSWS`/`VSUM2SWS` never set the VSCR SAT bit, because the expression that
did so was arithmetically dead. The performance change around it was taken; the
semantics were left alone.

## Open opportunities, ranked

Items 1 to 4 of the original list are resolved: `SQRDMLAH` measured and
declined, the float conversions fixed, `FLAGM` found unreachable, and `eor3`
deleted. What is left:

1. ~~Re-evaluate the A510 cache-worker default.~~ **Reversed. Compilation is
   no longer throttled.**

   The old default pinned startup cache and PPU compile workers to the three
   A510 cores, on this measurement, both arms from a 34.7 C preflight:

   | cache workers | first runtime sample | outcome |
   | --- | --- | --- |
   | ordinary scheduler | `71.1 C` | thermal guard stopped it 0.7 s in |
   | A510 cluster | `53.8 C` | peaked `67.8 C`, survived 9.5 s |

   That reads like a settled case, and it was wrong as a *default*. Watching a
   real cold PPU recompile with the pinning in place: 78 modules, roughly ten
   minutes, with the device sitting at **51-58 C the whole time** and the guard
   at 72 C. Fourteen to twenty-one degrees of headroom went unused for ten
   minutes to avoid a hot case that the thermal guard already exists to catch.

   The trade was backwards. Pre-emptively throttling *every* compile to avoid
   occasionally reaching a limit spends a large certain cost against a small
   uncertain one, when the guard is right there and costs nothing until it
   fires. The guard is unchanged and still bounds the hot case.

   `debug.rpcsx.thor.cache_worker_affinity_mask` remains, and `0x07` restores
   the old pinning if a boot ever does stop on temperature. Reach for that
   before reintroducing a default that slows every compile.

   **The affinity was only half of it, and the smaller half.** Compilation
   concurrency is also capped by `Max LLVM Compile Threads` in `config.yml`,
   which feeds `jit_core_allocator`:

       thread_count = llvm_threads ? min(llvm_threads, limit()) : limit()

   On this device that was set to **2**, so PPU module compilation ran two-wide
   no matter how many cores the affinity mask allowed. Freeing all eight cores
   while leaving the cap at 2 would have looked like the affinity change did
   nothing. Setting it to `0` means auto, which is `limit()`, which is every
   hardware thread.

   **And the cap is set in three places, two of which overwrite the third.**
   `config.yml` holds the value, but `ThorPerformanceProfile` calls
   `setSetting("Core@@Max LLVM Compile Threads", "2")` on every boot and the
   `BLUS30161` entry in `GameSettingsDatabase` carries it in the managed profile.
   Editing the config alone is silently undone on the next launch. All three are
   now `0`, meaning auto, meaning every hardware thread.

   Worth internalising as a debugging habit: **when a throttle is removed and
   nothing gets faster, look for the second throttle before doubting the first.**
   Two independent limiters in series are common in this codebase precisely
   because each was added for a different reason at a different time.

   The general lesson, which is the reason this is written at length: **a
   measurement can be correct and still support the wrong decision.** The 71.1 C
   number was real. What it did not capture was how often that case arises, what
   the alternative costs when it does not, or that a guard already handled it.
   An A/B that answers "which arm is cooler" does not answer "which default is
   better".

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

## The rest of the codebase, and why it needed nothing

The sweep that found the eight items in the x86-habit table was carried to the
end. The last three subsystem groups produced no changes, and the reasons are
worth keeping so the ground is not re-covered.

**~~lv2, HLE modules, Audio and Io are architecture-neutral.~~ Half of this was a
grep against nothing.** The claim rested on a search across `Emu/Cell/lv2`,
`Emu/Cell/Modules`, `Emu/Audio` and `Emu/Io` matching **zero files**.

`Emu/Cell/lv2` and `Emu/Cell/Modules` **do not exist in this fork.** The syscall
layer is `kernel/cellos/`, 117 source files, and it was never scanned. `Audio`
(23 files) and `Io` (73 files) are real and are genuinely clean, so that half
stands.

Scanning `kernel/cellos/` properly returns one file with x86 markers,
`src/lv2.cpp`, and it is not trivia: it holds a **second copy of the
power-optimized wait**, giving x86 `TPAUSE`/`MWAITX` and AArch64 a
`sched_yield` loop on every sub-quantum guest thread sleep. Written up in
[`power-and-thermal.md`](power-and-thermal.md).

The lesson is the one the APK gate already taught and this repeated: **a search
that finds nothing and a search that searches nothing produce identical output.**
Confirm the path exists before recording a zero.

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

## The correction lens, swept and now exhausted

The most productive heuristic recorded here is that **auditing x86 *corrections*
has high yield where auditing opcodes has low yield** — every real defect in this
codebase was shared code compensating for an x86 quirk, never LLVM picking a bad
instruction from a clean description. It found `CFLTS`, the `FCTIW` family,
`VPKUHUS`, `bswap.i128`, `mov_rdata` and `VMSUMSHS`.

It has now been swept mechanically for its own tell — an XOR against a
sign-extended comparison, which is the shape a saturation fix-up takes — across
both translators. **Three sites, all correct:**

| site | verdict |
| --- | --- |
| `SPULLVMRecompiler.cpp:8700` (`CFLTS`) | inside `#else` of `#ifdef ARCH_ARM64`; the ARM path above it uses `fptosi_sat` |
| `SPULLVMRecompiler.cpp:8721` (`CFLTS`, second instance) | same structure, same guard |
| `PPUTranslator.cpp:1708` (`VMSUMSHS`) | not an x86 workaround — it implements PowerPC's own saturation of the `0x80000000` product |

The first two are the fix working exactly as intended: the correction survives for
x86, and AArch64 takes hardware saturation. Finding them in a grep is the
expected result, not a regression. The third is a case where the "correction"
shape is the *guest architecture's* semantics rather than a host workaround, which
is the distinction that makes this lens need reading rather than pattern-matching.

**So the lens is exhausted for this shape.** That does not mean no corrections
remain — it means the ones written as an XOR against a comparison are all
accounted for. A correction spelled as a `select`, a clamp before a conversion,
or a literal limit would not match this pattern; the `select` forms were checked
by hand in the same pass and are `FREST`/`FRSQEST` exponent handling, which is
algorithm rather than compensation.

Worth recording as a negative result because the alternative is re-running the
most productive heuristic in this document every time someone looks for work, and
concluding from silence that they searched badly.

## Plain `char` is unsigned here and signed on x86, and it does not matter

A dimension this ledger never covered, and a classic x86-to-AArch64 divergence:
**plain `char` has no fixed signedness**, and the platform defaults differ.
Verified on the actual target rather than assumed — NDK clang for
`aarch64-linux-android29` defines:

    #define __CHAR_UNSIGNED__ 1

and the build passes neither `-fsigned-char` nor `-funsigned-char`, so it takes
that default. On x86_64 Linux and Windows plain `char` is **signed**. Code
holding numeric data in a `char` and testing `c < 0`, or right-shifting it, gets
different behaviour on the two hosts with no warning.

**Swept, and the codebase is structurally immune.** How it spells 8-bit types,
counting `Emu/`, `kernel/` and `rx/` and excluding vendored `3rdparty/`:

| spelling | uses |
| --- | --- |
| `u8` | 2,928 |
| plain `char` | 1,250 |
| `s8` | 107 |
| `signed char` (explicit) | 51 |
| `unsigned char` (explicit) | 16 |

`rx/types.hpp` defines `u8 = std::uint8_t` and `s8 = std::int8_t`, both of which
have fixed signedness independent of the `char` default. Numeric byte data goes
through those; plain `char` is used for text. A sweep for the failing shape — a
plain `char` variable subsequently tested against `< 0` — matched nothing in
`Emu/`, and the 51 `signed char` uses are explicit where signedness is wanted.

The only plain-`char` sign-dependent code in the tree is inside
`3rdparty/7zip`, which is vendored, builds on both hosts upstream, and is not
emulator logic.

**Recorded as a negative result because the reasoning generalises.** The codebase
is not safe here by having audited `char` usage; it is safe because it adopted
fixed-width typedefs everywhere numeric bytes appear, which makes the entire
question unreachable. That is worth more than a fix: **a convention that removes a
class of bug is stronger than a sweep that finds none this time**, and it is why
this dimension needs no re-check when new code lands, provided the convention
holds.

## Integer division by zero: a divergence that exists and cannot be exploited

Another x86-to-AArch64 divergence not previously covered, and one where the
tempting ARM conclusion is wrong.

**The divergence is real.** On x86 an integer `div` by zero raises `#DE` and the
process takes `SIGFPE`; `INT_MIN / -1` traps the same way. On AArch64 `SDIV` and
`UDIV` are *defined* for both cases — division by zero yields `0`, and
`INT_MIN / -1` yields `INT_MIN`, with no trap at all.

So the four PPU divide opcodes look like they carry a removable x86 guard. Each
substitutes a safe divisor before dividing, `DIVW` being representative:

```cpp
const auto o = CreateOr(IsZero(b), CreateAnd(ICmpEQ(a, smin), IsOnes(b)));
const auto result = CreateSDiv(a, CreateSelect(o, smin, b));   // <- the guard
SetGpr(op.rd, CreateSelect(o, 0, result));
if (op.oe) SetOverflow(o);
```

**It is not removable, and the reason is worth writing down.** The guard is not
protecting against an x86 trap. It is protecting against **undefined behaviour in
LLVM IR**: `sdiv` and `udiv` by zero are UB at the IR level, independent of any
target. Without the substitution LLVM is entitled to propagate that UB backwards
and miscompile the surrounding block — a far worse outcome than a wrong quotient,
and one no amount of hardware definedness prevents, because the optimizer acts
before the backend sees an `SDIV` at all.

The outer select and `SetOverflow` are separate and also stay: they implement
PowerPC's own semantics, where both cases set `OV` and leave `rd` undefined,
which this fork resolves as zero.

**The transferable point: a hardware guarantee does not erase an IR-level
guarantee.** "AArch64 defines division by zero, so the check is redundant" is a
plausible sentence, correct about the hardware, and wrong about the compiler. The
same reasoning would be wrong for shift-count overflow and for `__builtin_clz(0)`.
When considering whether a defensive construct can be dropped on this target,
establish which layer requires it before checking what the silicon does.

Cost of keeping it is one `CSEL` per divide, which is not worth a JIT-level
inline-asm escape to avoid.

## Two more dimensions swept clean: `long double` and TLS access cost

**`long double` differs between the hosts and is unused.** It is 80-bit x87 on
x86_64 and 128-bit quad on AArch64, so any arithmetic routed through it produces
different results on the two hosts — a correctness divergence for an emulator,
not a performance one. Swept across `Emu/`, `kernel/`, `rx/` and `util/`: **one
occurrence**, in `util/cfmt.h` handling the `%L` printf length modifier, whose
case body says "not supported". No arithmetic uses the type, and there are no
`__float80` or `_Float80` remnants. Nothing to do.

**TLS access is already on the fast general-dynamic variant.** A `thread_local`
in a shared library normally resolves through `__tls_get_addr`, a function call
per access, which would matter if hot code touched TLS. The build sets no
`-ftls-model`, so this looked like an open question. It is not, for two
independent reasons:

- **The toolchain already emits TLSDESC.** The shipped library carries **134
  TLSDESC relocations against 22 `__tls_get_addr` calls** — clang defaults to
  the TLS-descriptor dialect on AArch64 Android, which resolves through a small
  inline sequence rather than the classic call, and is substantially cheaper.
- **The hot path does not use TLS at all.** The GETLLAR spin region, which the
  profiler measured at 82.5% of all emulator spin, contains **zero** TLS
  accesses. The `thread_local`s in `SPUThread.cpp` are fault handling, the log
  prefix, a name cache, wait statistics and a notify flag — all outside the
  measured hot loop.

`-ftls-model=initial-exec` would be faster still, dropping the descriptor call
for a `tpidr_el0` read plus a GOT offset. It is deliberately **not** proposed:
this core is `dlopen`ed, Android reserves only a limited surplus of static TLS
for dynamically loaded libraries, and exhausting it makes `dlopen` fail outright.
Trading a guaranteed load failure risk for an unmeasurable gain on a path that
does not execute is a bad exchange.

Recorded because "no TLS model is set" is the kind of observation that looks like
a finding, and the two facts that make it a non-issue — which dialect clang
actually picked, and whether the hot path touches TLS — both need checking rather
than assuming.

## 16 KB pages: an AArch64-only requirement, clean on both halves

x86 Android is always 4 KB paged. **AArch64 Android can be 16 KB**, and Android 15
onwards requires apps to support it, so this is a divergence that only exists on
the architecture this fork targets — and one that fails as a hard load error
rather than a slowdown. An emulator that `mmap`s and `mprotect`s guest memory
constantly is exactly where a 4 KB assumption would be buried.

It has **two independent halves**, and passing one says nothing about the other.

**Source: queries the real page size.** No hardcoded `4096` or `0x1000` in
`util/vm_native.cpp`. The three places that need it all ask:

    util/vm_native.cpp:199   result = ::sysconf(_SC_PAGESIZE);
    rx/src/mem.cpp:10        rx::mem::pageSize = sysconf(_SC_PAGE_SIZE);
    util/sysinfo.cpp:1195    ::sysconf(_SC_PHYS_PAGES) * ::sysconf(_SC_PAGE_SIZE)

**Binary: segments are 16 KB aligned.** This is the half that is not a source
property at all — a library whose `LOAD` segments are 4 KB aligned cannot be
mapped on a 16 KB kernel no matter how careful the code is. Checked on every
native library actually inside the shipped APK:

| library | max `LOAD` align |
| --- | --- |
| `librpcsx-android.so` | `0x4000` |
| `librpcsx-ui-jni.so` | `0x4000` |
| `libhook_impl.so`, `libmain_hook.so` | `0x4000` |
| `libfile_redirect_hook.so`, `libgsl_alloc_hook.so` | `0x4000` |
| `libandroidx.graphics.path.so` | `0x4000` |

All seven at `0x4000`, which is 16384. NDK 29 emits this by default, so it is
inherited rather than configured — worth knowing, because it means the property
would silently regress if the NDK were pinned back to an older revision, with no
source change to blame.

Recorded as a clean result on a dimension that had not been examined, and one
where the failure mode is not subtle: the app would not start at all on a 16 KB
device. The check is cheap and belongs in any toolchain change.
