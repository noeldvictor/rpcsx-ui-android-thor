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
PS3 target, at `24.7-33.1%` total CPU.

Thermal profile of a direct boot, sampled every 2 s (an earlier 4 s sweep
reported a `57.8 C` peak and simply missed the spike):

```
2s:56.2  4s:60.2  6s:46.2  8s:47.8  10s:44.9 ... 60s:55.0 ... 90s:56.6
```

The transient peaks `60.2 C` at `t=4s` and collapses to `46.2 C` two seconds
later, after which the run sits at `44-57 C` and drifts up slowly. Sample at
2 s or finer; a 4 s sweep aliases the spike.

**The harness is not thermally free.** The same build, game, and settings run
through `thor_input_macro.ps1` climbs `59.4 -> 58.6 -> 61.0 -> 64.6 -> 70.7 C`
within about ten seconds and trips the early stop, while the direct boot above
never leaves the fifties. Its per-sample `adb shell` spawns walk roughly fifty
`thermal_zone*` sysfs entries, the sustain loop adds a poll per second exactly
when the device is hottest, and each readiness poll takes a 1080p `screencap`.
That overhead lands on a machine with no spare headroom during boot. Treat
harness temperatures as an upper bound that includes the observer, and use a
direct `THOR_DEBUG_BOOT` when the question is about the emulator rather than the
route.

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

## When LLVM already does it, and when it does not

Measure the baseline before writing a lowering. LLVM's AArch64 backend is
better at this than it looks, and three of the four opportunities on the first
version of the list below evaporated on contact.

- **It forms `BCAX` and `EOR3` by itself** from `a ^ (b & ~c)` and `a ^ b ^ c`
  whenever `+sha3` is advertised, on **value** operands.
- **Constant operands defeat it.** With a constant mask, instcombine folds the
  `NOT` away first (`c & ~0x60` becomes `c & 0x9f`), so the pattern never
  matches and you get `movi`/`and`/`movi`/`eor`. This is exactly why the
  `SHUFB` selector and `EQV` emit `bcax()` by hand and why there is no `eor3()`
  helper: no site needs one.
- **It already fuses the AltiVec multiply-highs.** `VMHRADDSHS` lowers to
  `smlal`/`smlal2`/`ssra`/`sshr`/`saddw2`/`sqxtn`, 11 instructions, and 13 with
  the SAT indicator. An exact `SQRDMULH` rewrite measured 12. One instruction
  saved is not worth the risk, so it was not taken. The 1-instruction
  `sqrdmlah` form only exists if you give up the SAT flag and the
  `a == b == INT16_MIN` case, where PowerPC does not saturate the intermediate
  and the true value `32769` cannot be held in a 16-bit lane.
- **`FLAGM` is unreachable.** LLVM 20.1.3 exposes no `RMIF`/`SETF8`/`SETF16`/
  `AXFLAG` intrinsics, and PPU condition emulation is value-based
  (`CreateICmp` into CR fields) rather than host-flag based, so there is
  nothing to map even with inline asm.

## Where the wins actually were

`fptosi`/`fptoui` are **poison** on overflow, so shared code bolts a correction
on by hand, and that correction is written for x86. AArch64 saturates in
hardware, which makes the correction wrong rather than merely redundant:

- **SPU `CFLTS` was incorrect on ARM64.** `CVTTPS2DQ` returns `0x80000000` on
  overflow so the x86 path XORs it to `0x7fffffff`; `FCVTZS` already gives
  `0x7fffffff`, and the same XOR turns it into `0x80000000`. Any value at or
  above `2^31` produced the wrong result, upstream included.
- **SPU `CFLTU` was correct but redundant.** `FCVTZU` already clamps negatives
  to zero and saturates at `2^32`, so the select and sign mask were dead work.

`llvm.fptosi.sat` / `llvm.fptoui.sat` lower to a single `FCVTZS` / `FCVTZU`,
fixing the first and shortening both from four instructions to one. The x86
paths keep their corrections; only the ARM64 branches changed. Pinned by
`tools/test_thor_spu_arm64_float_convert.ps1`.

The general lesson: on a target whose hardware semantics are *stronger* than
the IR's, a portable correction can be worse than nothing. Grep for the other
places shared code compensates for x86 quirks before assuming they are neutral.

## Open opportunities, ranked

Items 1 to 4 of the original list are resolved: `SQRDMLAH` measured and
declined, the float conversions fixed, `FLAGM` found unreachable, and `eor3`
deleted. What is left:

1. ~~Re-evaluate the A510 cache-worker default.~~ **Done, and it stays.**
   Re-measured after the guard artifact was understood, using
   `SPU Runtime: Built %u functions.` as the completion marker and direct
   `THOR_DEBUG_BOOT` rather than the harness. Both arms launched from `33.9 C`:

   | cache workers | SPU cache build, 1179 functions | peak |
   | --- | --- | --- |
   | A510 cluster, the default | completes at `0:00:52.3` | `53.0 C` |
   | ordinary scheduler | never completes | `70 C` at wall `t=6s`, `71.5 C` |

   The original justification was wrong, but the conclusion holds for a better
   reason. Letting the build run on all eight cores puts it on the X3 at full
   clock and takes the device from `33.9` to `70 C` in six seconds, so it cannot
   finish inside the `72 C` bound at all. Pinned to the A510s it completes the
   whole build with `19 C` of headroom to spare. The unmeasured question is
   wall-clock: the ordinary scheduler might finish sooner if allowed to run hot,
   but it would be throttling by then, so that comparison needs a run that is
   allowed past the bound and is not obviously worth taking.
2. **Advertise the features the device actually has.** The JIT sends
   `+sha3,+dotprod,+i8mm,-sve,-sve2` on top of `cortex-a78`, so everything past
   Armv8.2 is invisible to LLVM: `lrcpc`, `flagm`, `flagm2`, `frint`, `fcma`.
   Adding them costs nothing when each is gated on its own `utils::has_*()` with
   an explicit negative, and it lets the backend choose instructions we have not
   had to think about. `frint` turned out unnecessary for the conversions, but
   the general point stands.
3. **Revisit `mcpu`.** `cortex-a78` is a v8.2 scheduling model standing in for a
   1+2+2+3 Armv9 machine. `cortex-a715` or `cortex-x3` with explicit `-sve`
   `-sve2` may schedule better, but only if the negative attributes reliably
   clear the implied SVE. Verify with `llvm-objdump` that no SVE instruction is
   emitted before trusting it.
4. **Audit the other x86 compensations.** `CFLTS` was wrong on ARM64 because a
   portable correction assumed x86 overflow semantics. The same shape may exist
   elsewhere; `CreateFPToSI`, `CreateFPToUI`, and any `^ sext(...)` correction
   next to a conversion or saturation are the places to look.
