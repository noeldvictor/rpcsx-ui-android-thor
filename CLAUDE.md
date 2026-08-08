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
- **A search that finds nothing and a search that searches nothing look
  identical.** This has now cost three times. The third was a device experiment
  labelled "shader cache cleared" that had cleared nothing: the `mv` failed because
  `files/cache/cache/` is `drwxr-s---` and denies the group write, while
  `config/custom_configs/` is `drwxrws---` and allows it. The `&&`-guarded success
  `echo` never printed and nobody looked. Confirm the postcondition after the
  command, not the precondition before it. `tools/test_thor_arm64_apk.ps1` defaulted
  to `app/build/outputs/apk/release/`, a variant nobody builds, and passed for
  months while x86_64 shipped. Then the ledger recorded `lv2` and the HLE modules
  as architecture-neutral on a grep across `Emu/Cell/lv2` and `Emu/Cell/Modules`,
  **neither of which exists in this fork** — the syscall layer is
  `kernel/cellos/`, and scanning it properly turned up a second x86-only
  power-optimized wait. Before recording a zero, confirm the path exists.
- **`TBL2`/`TBX2` need a retry owner.** They can trip the AArch64 register
  scavenger. The SPU block compiler has `compile_spu_llvm_with_retry`; the SPU
  interpreter builder deliberately does not, and stays on the plain path.

## Measuring things here, and five ways it went wrong

Every one of these cost a build and a device run, and each is written up where it
happened. They are collected because they are about *method*, not about any
subsystem, and every one of them produced a confident wrong answer first.

- **Normalize by something the change provably cannot touch.** Two WFE A/Bs
  failed on workload variance before the third worked, and the fix was not a
  steadier workload but a better denominator: `spu_getllar_retry` sits in a loop
  the flag never enters, so dividing by it took a 59% spread down to 1.1%. Read
  which branch the flag is in before designing the experiment.
- **A mean over a heavy-tailed distribution invites the wrong decision.** GETLLAR
  spin depth averaged `135.2`, which reads as "every wait is long". The histogram
  put **95.5% below 8**; one deep wait was carrying the mean. The check that
  catches it — what would a single extreme sample alone produce — is one line of
  arithmetic.
- **Instrument what you changed, not only what you hoped to improve.** A
  graduated backoff on GETLLAR measured as an exact no-op, `300.0` ticks per call
  unchanged, because the gate it keyed on had already been passed. Had it shifted
  5% it would have been kept, and the broken denominator never noticed.
- **A fix that transfers between sites is a hypothesis.** `passive_lock` and
  `GETLLAR` looked like one shape — a busy-wait whose measured wait seems shorter
  than its backoff. One spins immediately; the other only after a separate gate
  has decided the wait is durable. The gate was in the source the whole time.
- **When a shared variable is suspected of contention, instrument every party
  that reads it.** `vm_writer_lock` recorded zero spins, which was read as "this
  word is uncontended". It only showed the *writer* never blocks; the readers in
  `passive_lock` were 17.5% of all spin, in the same log line.

The pattern across all five: the measurement was correct and the *inference* was
not. When a number decides something, state what population it is over and what
it excludes, before acting on it.

## First: the game does not currently boot

Eternal Sonata hangs about eight and a half seconds into emulation, deterministically,
with `rsx::thread` pegged at 100% and ~85% of that in the kernel. It never recovers.
The screen keeps the last frame RSX presented — usually the SPU cache overlay — which
makes it look like a stalled compile. It is not; nothing is being written to disk.

This **blocks the GETLLAR sweep below**, which needs the title to reach gameplay.

The upside is the trade it offers: reproducing the open guest crash meant playing to a
combat encounter, and reproducing this takes one command and ten seconds. Full write-up,
including the six hypotheses ruled out and the two unbounded `sync.cpp` waits it is
narrowed to, in [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md).

Answering it needs a **debuggable** build. The installed release build refuses `run-as`,
the device has no root, so `/proc/<tid>/syscall` and `debuggerd -b` are both closed.
`/proc/<tid>/stat` still works, and that is all it will give up.

## The one thing to run next, once it boots

**93% of all emulator spin is the SPU `GETLLAR` wait, and the emulator spins there
because it is configured to, 100% of the time.**

`SPU GETLLAR Busy Waiting Percentage` decides whether that wait spins or sleeps.
Upstream defaults it to 100 — always spin — and no Thor profile overrides it,
while the analogous `SPU Reservation Busy Waiting Percentage` is explicitly set
to 0 for this device. The trade was considered once, applied to the smaller of
the two sites, and never revisited for the larger.

The alternative branch is a **real futex sleep**, woken by the actual reservation
notifier with the timeout as a fallback — which is a better-shaped mechanism than
the `WFE` park this fork spent three experiments on, because `WFE` cannot have a
timeout without `FEAT_WFxT` and this chip lacks it.

Every link is verified except the effect size:

    ./gradlew assembleThortest -PrpcsxThorWaitProfiler=1
    # unplug the Thor first, or the wattage is only a floor
    .	ools	hor_getllar_percent_sweep.ps1

Four arms, one command. It throws rather than guessing if the property did not
take, the boot failed, or the profiler is absent, and it reports p95 frame time
because the risk of sleeping is **latency**, which a capped frame rate hides.
Detail in [`docs/arm64/spin.md`](docs/arm64/spin.md).

## Where the rest of this lives

These notes outgrew a single file. The detail is split by topic; each document
stands on its own and this file is the map.

| document | what is in it |
| --- | --- |
| [`docs/arm64/codegen.md`](docs/arm64/codegen.md) | What this fork does: the lowerings chosen here, the missing movemask, the SPU opcode audit, and the x86-habit table that produced most of the real defects. |
| [`docs/arm64/microarchitecture.md`](docs/arm64/microarchitecture.md) | What the hardware does: instruction latency, throughput and pipe assignment from the vendored per-core guides, the forwarding regions, and the chapter 4 rules. |
| [`docs/arm64/memory-model.md`](docs/arm64/memory-model.md) | Atomics and ordering: the dead LSE2 macro, the reservation seqlock, RCsc versus RCpc, and instruction-cache maintenance. |
| [`docs/arm64/spin.md`](docs/arm64/spin.md) | Where the CPU time goes: 93% of spin is the `GETLLAR` wait, what was tried against it, and the one lever still untested. |
| [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) | The deterministic RSX hang that currently stops the game booting: the ten-second repro, what it is not, and why it needs a debuggable build. |
| [`docs/arm64/instruments.md`](docs/arm64/instruments.md) | The measuring tools, what each can and cannot answer, and the mistakes made building them. |
| [`docs/arm64/thermal.md`](docs/arm64/thermal.md) | Junction versus package sensors, and the guard that compared a limit against the wrong one. |
| [`docs/arm64/ledger.md`](docs/arm64/ledger.md) | The audit ledger: every `ARCH_X64` block accounted for, the open opportunities, and the subsystems that needed nothing. |
| [`docs/hardware/`](docs/hardware/) | Arm's Cortex-X3 and A710 optimization guides, vendored, plus how to read their tables. |

`AGENTS.md` is the operating contract. This file is the hardware knowledge behind
it.

## Two things that outrank everything else here

**Most of these notes are still not measured against a running game.** The
exception is the wait profiler, which has now been run on device during gameplay
and gave the first hard numbers here: **16.9% of busy CPU time is spin, 82.5% of
that in `GETLLAR`**, with `vm_passive_lock` a further 17.5%, and a normalized WFE
A/B showing the park displacing 20% of the inner spin at eighteen times the noise
floor.

Everything else — every instruction-selection change in particular — is still
argued from correctness, instruction counts or hardware capability, with no
before-and-after. And the changes most likely to matter in practice were never
about instruction selection at all: custom GPU drivers going from never-loading to
working, and i-cache maintenance that a stale fetch would have turned into an
unreproducible crash.

**The recurring failure mode is a measurement that is correct and still supports
the wrong decision.** It has happened at least four times: a junction temperature
compared against a package-shaped limit, a thermal A/B that was really detecting
which cores an arm ran on, a WFE experiment whose two arms sampled different
cutscenes, and a BCAX microbenchmark whose chain forwarded within one region
where the real code crosses two. In each case the number was real and the
inference was not. When a result decides something, check that the thing measured
is the thing that ships.
