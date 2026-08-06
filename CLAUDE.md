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
PS3 target, at `24.7-33.1%` total CPU and `53-57 C`. Peak over a `111 s` run
was `57.8 C`.

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

## Open opportunities, ranked

1. **`SQRDMLAH` for PPU `VMHRADDSHS` / `VMHADDSHS`**
   (`Emu/Cell/PPUTranslator.cpp:1539`). The current lowering sign-extends to
   `s32[8]`, multiplies, adds `0x4000`, shifts, adds, clamps twice and
   truncates. `SQRDMULH` computes `sat((a*b + 0x4000) >> 15)` and `SQRDMLAH`
   folds the accumulate in, one instruction for all eight lanes. `asimdrdm` is
   present and already implied by `cortex-a78`. The catch is `set_sat`, which
   wants the pre-saturation value, so the VSCR SAT bit needs its own cheap
   computation or an explicit decision to derive it differently.
2. **`FRINT32Z`/`FRINT64Z` for SPU `CFLTS`/`CFLTU`**
   (`Emu/Cell/SPULLVMRecompiler.cpp:8621`, `:8693`). Float to integer with
   saturation currently needs explicit clamp sequences. `frint` is present but
   **not** implied by `cortex-a78`, so this needs `+frint` added to the JIT
   attribute list first, gated on a new `utils::has_frint()`.
3. **`FLAGM`/`FLAGM2` (`RMIF`, `SETF8`/`SETF16`, `AXFLAG`) for PPU condition
   and carry emulation.** Present on device, not implied by `cortex-a78`.
   Worth profiling PPU `CR`/`XER` update paths before committing.
4. **`EOR3` currently has no call site.** The helper exists next to `bcax` in
   `CPUTranslator.h` and is contract-tested, but nothing emits it. Either find
   a genuine three-way XOR in the PPU or SPU lowering or delete it; carrying an
   unused helper invites someone to assume it is load-bearing.
5. **Re-evaluate the A510 cache-worker default.** It was justified by surviving
   the thermal guard longer, and that guard was tripping on an artifact.
   Pinning compile workers to three little cores plausibly makes the ~50 s SPU
   cache build slower, which is the largest user-visible cost at boot. Measure
   time-to-title with the property unset versus explicitly `0` now that runs
   complete.
6. **Revisit `mcpu`.** `cortex-a78` is a v8.2 scheduling model standing in for a
   1+2+2+3 Armv9 machine. `cortex-a715` or `cortex-x3` with explicit `-sve`
   `-sve2` may schedule better, but only if the negative attributes reliably
   clear the implied SVE. Verify with `llvm-objdump` that no SVE instruction is
   emitted before trusting it.
