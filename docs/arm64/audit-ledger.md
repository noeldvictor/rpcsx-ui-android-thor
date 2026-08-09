# Codebase-vs-manuals audit: method, coverage, and what is left

The goal is a systematic check of the whole native codebase against the vendored
ARM64 manuals, aimed at making the emulator faster or cooler. This file is the
ledger, so the sweep can be resumed mechanically instead of restarted.

## The method that works, and the one that does not

**Does not work: sweeping the manual for slow instructions and hunting for them.**
Tried repeatedly this session. Four predictions derived that way, four refuted:

| prediction from the manual | measured | verdict |
| --- | --- | --- |
| `ISB` beats `YIELD` for spin | **+23% cycles** | regression, rejected |
| XOR/OR tree beats `MLA` in `cmp_rdata` | 0.3% | noise, no change |
| UMA direct upload avoids staging copies | 8.5 KB/frame | negligible, closed |
| shift-by-immediate beats shift-by-register | both `V13` | no difference, killed on paper |
| removing the `static` guard from `pause()` helps | 5,954 vs 5,859 Mcyc/s | **no change** — inside the ~2% noise floor |

The one that was killed on paper is the cheapest and the model to copy: read the
exact table row *before* building anything.

**Works: establish reach first, then optimality.** Every real defect this session
came from asking "does this code run at all, and with what?" rather than "is this
instruction ideal":

* `mov_rdata` — an ARM64 `#elif` containing only comments, so the copy every
  reservation validates against did nothing. Two titles could not boot.
* the RSX auditor — `enabled()` is `constexpr false` on Android without
  `RPCSX_THOR_RSX_AUDITOR`, so its property could never work.
* 1.88 W — a leaked emulator process at 210% CPU, found with `top`, not a manual.

### The profile, and what it says the target really is

First profile of the session (Eternal Sonata, 40,337 samples, none lost):

```
54.30%  unknown              JIT-generated SPU/PPU code, no symbols
37.22%  librpcsx-android.so
 6.48%  [kernel.kallsyms]
```

**Over half the CPU is in JIT output.** Every audit above — inline assembly,
sse2neon, intrinsic inventory, narrow-pipe sweep — covers the other 37%, and all
of it came back clean. The manuals need applying to *what the recompilers emit*,
which is the one thing not yet examined.

A caution learned by falling for it: within the named 37%, ~31% of samples
resolved to `get_thor_pause_mode`, an inline helper added earlier the same day.
That looked like a hot-path regression — a function-local `static` in `pause()`
costs a guard load and branch per call, and `pause()` sits in the spin where
93% of spin time lives. The reasoning was sound and **the measurement refused
it**: 5,954 Mcyc/s after removing it against 5,859 before, i.e. nothing.

`get_thor_pause_mode` is `inline` and emitted into many translation units, so it
becomes the *nearest preceding symbol* over large address spans in a
partially-stripped binary. **Nearest-symbol attribution on an inline function is
not evidence of heat.** The change was kept anyway — a finished A/B does not
belong in a hot loop at runtime — but it is not a win and is not counted as one.

## Auditing the JIT output, which is where the time is

The recompiler caches its compiled modules as ELF objects on device, under
`files/cache/cache/ppu-*/*.obj`. That makes the 54% auditable: pull one and
disassemble it. (`Save LLVM logs: true` in `config.yml` produces them; remember
`adb push` to write that file and restore it afterwards — the mode is
`-rw-r-----` and a shell redirect silently does nothing.)

Instruction histogram of one PPU module (979 KB of compiled code):

```
20767 mov     18593 ldr     14486 add     12982 str      8937 ret
 8163 bl       6382 nop      5116 rev      4217 brk      3947 cbnz
 3946 ldsetal  3577 strb     2595 cset     2460 stp      1586 and
```

Two entries worth checking, and both came back clean:

* **`rev` (5,116)** — byte swapping for a big-endian guest. `REV` is the correct
  instruction and it is `V`-pipe; nothing to improve.
* **`ldsetal` (3,946)** — an LSE atomic OR with *acquire-release*, the strongest
  ordering, and an alarming count for one module. It comes from
  `PPUTranslator.cpp:263`, raising `cpu_flag::wait`.

**`ldsetal` is on the cold path.** The emitted shape is:

```cpp
const auto vstate = m_ir->CreateLoad(..., ptr, true);
m_ir->CreateCondBr(m_ir->CreateIsNull(vstate), body, vcheck, m_md_likely);
m_ir->SetInsertPoint(vcheck);   // the atomic is here
```

The fast path is `state == 0 → body`, marked likely. The atomic executes only
when the thread has a pending flag. Those 3,946 are one per function entry —
**static occurrences, not executions**.

That is the same error as reading nearest-symbol attribution as heat, in a new
disguise: **a histogram of a JIT dump is a count of what was compiled, not of
what runs.** Weakening that ordering would have been a correctness risk taken
for no gain.

### JIT output vs rule 4.8, branch density

§4.8 is one of the few manual rules aimed squarely at *generated* code:

> avoid placing more than four branch instructions within an aligned 32-byte
> instruction memory region

PPU JIT output is branch-heavy by nature (`bl` 8163, `ret` 8937, `cbnz` 3947),
so this was a plausible violation. Measured over 124,556 disassembled
instructions:

```
32-byte regions containing code           15570
regions with >4 branches (violates 4.8)     330   (2.12%)
branches per region   1:4426  2:6206  3:1089  4:239  5:330
```

**Compliant.** 2.12% marginal violations, and the distribution stops dead at
five — not one region has six or more, which points at a single repeated
codegen pattern rather than sprawling branch soup. Nothing to fix.

## Coverage so far

| area | how checked | result |
| --- | --- | --- |
| Empty/neutralised arch branches | `tools/check_empty_arch_branches.py`, 1,489 files | 1 found (`mov_rdata`), fixed; now clean and guarded |
| NEON intrinsic inventory | all 1,489 non-3rdparty sources | 696 distinct; top of list is sse2neon |
| **sse2neon reach** | includers of `Emu/CPU/sse2neon.h` | **only 2**: `SPUInterpreter.cpp` (cold — both decoders are LLVM) and `ProgramStateCache.cpp` (already `vrev16q_u8`, AVX-512 behind `ARCH_X64`). Closed |
| Narrow-pipe ASIMD ops | every X3 table row narrower than `V` | see [`microarchitecture.md`](microarchitecture.md); shifts all `V13`, 8-bit `SDOT` full width |
| `cmp_rdata` lowering | X3 pipe tables + A/B on device | `MLA` is `V02`, but 0.3% — not worth churning |
| `pause()` / spin instruction | X3 + 3-arm A/B | `YIELD` ≈ `nop` confirmed; `ISB` +23%. Default kept |
| AES | X3 §4.6 | wants 4 blocks interleaved, we do 1 — real, but 35 ms of boot total |
| SDOT/UDOT | source + device log | present, `HWCAP_ASIMDDP`-gated, **on** |
| SVE | `HWCAP_SVE` on device | **absent on this chip**; two video chapters inapplicable |
| GPU tile memory | Adreno guide + `VkPhysicalDeviceMemoryProperties` | type 3 `LAZILY_ALLOCATED` exists and is **never used** — open |
| `LOAD_OP_CLEAR` | GPU busy A/B on device | implemented incl. depth, verified correct, **12.39% -> 12.65% GPU busy: no saving**. Default off |
| JIT output, instruction mix | disassembled a cached PPU module | `rev` correct; `ldsetal` is cold-path (static count, not executions) |
| JIT output, branch density (§4.8) | 124,556 instructions | 2.12% of regions marginally over, max 5. Compliant |
| SPU JIT lowering: BCAX in SHUFB | A715 tables + on-device A/B | `V0` thr 1 looked wrong; **measured 5.6% better than BIC+EOR**. Existing code correct, `no-sha3` mode added to re-ask |
| PPU translator ARM64 lowerings | 14 `ARCH_ARM64` sites read | already ARM64-aware: vector byteswap avoids GPR↔SIMD transfers, `VMAXFP`/`VMINFP` use native `fmax`/`fmin`, `VPERM` uses `TBL` (`2 2 V`). Clean |
| All three core guides | X3, A715, A510 cross-checked | X3 was the wrong reference for mid-cluster work; A510 shares one VPU per complex |
| **TSO assumptions (seqlock read sides)** | every `reservation_acquire` call site | both read-validate pairs already carry `atomic_fence_acquire`: SPU DMA (`SPUThread.cpp:3785`) and SPU GETLLAR. PPU `LARX` fences after `mov_rdata` and defers validation to `STCX`, a different but sound model. Clean |
| **All inline assembly** | enumerated: 73 sites in 18 files | see below — every ARM64 site checked against the guide, all cleared |
| FPCR access (§4.9, §4.10) | call-site reach | `mrs/msr FPCR` in `rx/simd.hpp` is reached only from `ppu_thread::cpu_task` and `spu_thread::cpu_task` — **once per thread start**. Special-register flush side-effects do not apply to a cold path. Cleared |
| I-cache maintenance (§4.13) | rule text vs our usage | §4.13 concerns set/way L1 invalidation; our `dsb ish; isb` after codegen is the architectural I-cache sequence, not a set/way op. Not applicable |
| x86 asm guards | every `__asm__` site | all x86 sequences (`lock orl`, `xend`, `cpuid`, `xgetbv`, `comisd`, `movq`) sit behind `ARCH_X64`; `bless.hpp` carries a correct ARM64 `mov` arm |

## Inline assembly, all 73 sites

Enumerated across 18 files. The ARM64 ones, and what the manuals say about each:

| site | asm | verdict |
| --- | --- | --- |
| `rx/asm.hpp` (20) | `isb`, `nop`, `yield`, `mrs cntfrq_el0`, `wfe` | the spin primitives — measured, see [`spin.md`](spin.md) |
| `rpcs3/util/atomic.hpp` (15) | `lock orl`, `lock bts/btr/btc` | **all `ARCH_X64`** |
| `Emu/Memory/vm_reservation.h` (9) | `xend` (TSX) | **all `ARCH_X64`** |
| `Emu/CPU/sse2neon.h` (5) | `isb`, `crc32c*` | shim; two cold includers |
| `rx/simd.hpp` (4) | `mrs/msr FPCR` | cold, once per thread |
| `Emu/Cell/SPUThread.cpp` (3) | `ldxr`, `wfe`, `clrex` | the WFE park, [`spin.md`](spin.md) |
| `util/sysinfo.cpp` (3) | `cpuid`, `xgetbv`, `mrs cntfrq_el0` | first two `ARCH_X64` |
| `Emu/Cell/PPUThread.cpp` (2) | `dsb ish; isb` | correct I-cache sequence for JIT |
| `util/bless.hpp` (2) | `movq` / `mov` | correctly split per arch |
| `Emu/Cell/PPUInterpreter.cpp` (1) | `comisd` | `ARCH_X64`; interpreter is cold |
| `Emu/Cell/SPUCommonRecompiler.cpp` (1) | `dsb ish; isb` | correct |

**No defect found.** Every x86 sequence is guarded and every ARM64 sequence is
either correct or already measured. Hand-written assembly is not where this
codebase's ARM64 problems live — which is consistent with the pattern above: the
defects were in code that did not run, not code that ran badly.

## What is left, in priority order

1. **Profile before auditing further.** The theoretical sweeps are exhausted;
   what remains is to find the hot code and check *that* against the manuals.
   Blocked on a debuggable build: `simpleperf` refuses with *"Package
   net.rpcsx.easy doesn't exist or isn't debuggable/profileable"*. Rebuild with
   `-PrpcsxThorDebuggable=1`, profile Eternal Sonata (the SPU-heavy title, SPU
   47.1%), then audit the top symbols.
2. **`LOAD_OP_CLEAR` call site** — 100% eligibility measured, infrastructure
   landed, the remaining work is state handling around `m_current_renderpass_key`
   and its two caches. See [`adreno-tiler.md`](adreno-tiler.md).
3. **Transient attachments on tile memory** — `TRANSIENT_ATTACHMENT` +
   `LAZILY_ALLOCATED` appear nowhere in the VK backend, and the vendor documents
   the saving as a power win. See [`uma-bar-heap.md`](uma-bar-heap.md).
4. **§4.2, spill GPRs to vector registers** — aimed exactly at a JIT under
   register pressure. Whether LLVM exposes it is unestablished.

## Standing rule for this audit

A row in a manual is a hypothesis. It earns a code change only after a
measurement on this device, and the measurement has to be of a workload where
the code is actually hot — `cmp_rdata` looked critical at 10 million calls, and
those calls only existed because of a deadlock that has since been fixed.

## Why nine predictions failed, and it is not the manuals

Worth answering directly, because "the manual said so" kept being wrong.

**The manuals were accurate every time the right row was read.** `YIELD` really
is a nop on an SMP core — measured, `yield ≈ nop` within 2%. `MLA` really is
`V0`. The chip really is UMA with no separate VRAM. The A510 really does share
one VPU per complex. Not one chip-level fact has been contradicted by the device.

The failures are all in the **inference from chip fact to code change**, and they
come in four kinds:

1. **Read one row, assumed the neighbour differed.** The shift rewrite: read
   "shift by register `V13`" and assumed immediate shifts were wider. They are
   also `V13`. Cost nothing because it was caught on paper — read the adjacent
   rows before believing a contrast exists.
2. **Wrong core's table.** The whole narrow-pipe sweep quoted Cortex-X3 while the
   work runs on A715, where the same instructions are *narrower still*. A
   big.LITTLE target has three answers to every timing question.
3. **Inferred a remedy the manual never states.** This is the main one. A guide
   says what an instruction costs *on the chip*. It does not say that replacing
   it makes *this* code faster, because that depends on facts the manual cannot
   know: whether the code is hot, what else contends for the pipe, and what was
   tuned around the current form. `ISB` is the clean example — the manual was
   right that `YIELD` does nothing, and the swap still cost **23%**, because the
   spin counts were calibrated around a cheap instruction. BCAX is the same shape
   inverted: `V0` throughput 1 is real, and it still wins by **5.6%** because it
   replaces two operations.
4. **Optimising before establishing reach.** `cmp_rdata` looked critical at
   10,093,915 calls; those calls existed only because of a deadlock that was then
   fixed.

The practical rule this yields, and it is cheap: **a manual row is a hypothesis
about the chip, never a conclusion about the code.** Before building anything,
answer two questions the manual cannot — *is this code hot on this workload*, and
*what is it competing with* — and then measure, because on this project the
device has overruled the table nine times out of nine.

## The harness is the problem, not only the hypotheses

Asked why improvements keep failing. The honest answer is that **the A/B tool
cannot resolve the effects being chased**, and I treated its output as
measurement anyway.

Every run this session, by verified state:

| state | Mcyc/s |
| --- | --- |
| verified gameplay, 6 runs | 13,352 – 14,624 (**±5%**) |
| still compiling PPU modules | 10,691 |
| unverified arm, JIT A/B | 7,317 |

**When both arms are demonstrably in the same place, the instrument is tight.**
Every wild number has been a *phase mismatch*, never noise.

`tools/thor_property_ab.ps1` settles for a fixed number of seconds and never
checks where the program got to. Eternal Sonata does not reach a deterministic
state in fixed time — it passes through PPU compilation, two splashes, a
cutscene and a menu. So the tool reports precise-looking figures for **different
programs**, and three large results have already been artifacts:

* `cortex-a710` "−24%" — one arm was on the *"Compiling PPU Modules"* screen
* `jit_cpu_native` "+92%" — one arm at 2.762 cores against a gameplay norm of 5.2
* the same JIT question, twice, from the cache being keyed on the target CPU

### What this does and does not invalidate

**Stands:** the small refutations, because both arms were verified at ~5.2 cores
— `cmp_rdata` 0.3%, GETLLAR busy-wait −2.9%, `LOAD_OP_CLEAR` 12.39→12.65%, BCAX
+5.6%. Same state, tight instrument, real answers.

**Does not stand:** any large delta from this harness without a state check.

### The fix, and it is a prerequisite for everything else

Before any further optimisation work is worth doing, the harness needs:

1. **A state gate, not a timer.** Wait for a specific log marker or a screenshot
   match, and abort the arm if it is not reached — never settle blind.
2. **Cores-busy as a sanity check.** Both arms within a few percent of the same
   figure, or the comparison is void. This alone would have caught all three
   artifacts.
3. **A deterministic scene.** A save state loaded to a fixed point beats "boot
   and wait", which is what makes the phase mismatch possible at all.

Chasing 3-5% effects with a tool that silently compares different program phases
is how twelve predictions get "refuted" and two artifacts get mistaken for wins.
The instrument comes first.

### The likely cause of the phase artifacts: the home menu pauses emulation

The final JIT-target attempt aborted with *"emulator died during settle"* — the
harness's own liveness check, after confirming adb was reachable, so a real
death rather than a lost link. The log says what happened:

```
RSX: Friends list hidden in home menu. RPCN is not configured.
SYS: Emulation is being paused... (mark=0)
Input: opened home menu with result 0
```

**A stray input opened the PS3 home menu, which pauses emulation**, and the
session ended from there. Not a codegen fault — an environment one.

This is very likely the real mechanism behind the "phase mismatch" artifacts,
and it is a better explanation than the one recorded above. A *paused* emulator
does almost no work, which is precisely the signature seen:

* `jit_cpu_native` arm at **2.762 cores** against a gameplay norm of 5.2
* the `cortex-a710` arm reported as "still compiling" — plausibly paused instead

Both were read as the program being at a different point in its run. Paused is
simpler, fits the numbers better, and is invisible in cores-busy alone unless
you know to look for it.

**Add to the harness checklist:** grep the log for `Emulation is being paused`
and `opened home menu` in every arm, and void the comparison if either appears.
That is cheaper than the screenshot check and catches the same class. A device
being handled — or an overlay taking a stray tap — is enough to do it, and the
Thor is shared with another session.
