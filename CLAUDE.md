# Fast AArch64 PS3 Emulation on Snapdragon 8 Gen 2

Technical notes for making this emulator fast on Thor. `AGENTS.md` is the
operating contract; this file is the hardware knowledge behind it.

## Read this first: 74% of cycles are a nop-spin, and a profile found it

A symbolized profile of a healthy 60 fps run — 31,657 samples, 0 lost, no pause —
puts **73.9% of all CPU cycles inside two lv2 wait syscalls**,
`sys_event_queue_receive` (47.8%) and `_sys_lwcond_queue_wait` (26.1%), as *self*
time that never reaches `atomic_wait_engine::wait`. They are spinning, not
sleeping: `50 × rx::busy_wait(500)`, which on a **19.2 MHz** generic timer is
**1.3 ms** of `YIELD` — a nop on this SMP core. The identical loop is at
**eight sites** across the guest synchronization layer.

**Measured, not just predicted.** With the budget behind
`debug.rpcsx.thor.lv2_spin`, Folklore's title screen goes from **1.200 cores to
0.390** — a **67.6% cut in emulator CPU, 0.81 cores freed — at an identical frame
rate.** Two independent alternating runs agree to within 0.005 cores. The default
is still `50`, because this is one title and one non-sync-heavy scene and the
parity check cannot see p95 stutter; what would justify flipping it is written
down. Full account in
[`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md).

Two lessons outrank the finding itself:

* **Nothing in a year of manual sweeps found this, and one profile did.** Twelve
  manual-derived predictions were refuted; the audit concluded "the ARM64 code is
  clean", and at instruction level it is. The waste was never in instruction
  selection — it was in how long a wait waits. Get the profile first.
* **"93% of spin is GETLLAR" was a share of the instrumented sites only.** The wait
  profiler counts SPU sites and no PPU sites, so these eight could not appear and
  their absence read as evidence. Same failure the ledger lists twice: a search that
  finds nothing and a search that searches nothing look identical.

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

AOT code is built `-march=armv8.4-a -mtune=cortex-a715`. Atomics are real
inline LSE, confirmed by zero `__aarch64_cas*` / `__aarch64_ldadd*` undefined
symbols in the built objects, so there is no outline-atomics tax to remove.

That baseline expands to `+complxnum +crc +dotprod +fp-armv8 +jsconv +lse +neon
+outline-atomics +pauth +ras +rcpc +rdm +v8.1a..v8.4a` — asked of the compiler,
not read off the spec. What it does **not** include, on a chip that has all of
them, is `+aes`, `+sha2`, `+sha3`, `+i8mm`, `+fullfp16` and `+bf16`. The one that
currently costs something is `aes`: the whole AES-NI file is `#if defined(__SSE2__)`,
so every SELF, SPRX and PKG decryption on this device runs four-table software AES.
Measured on device against that exact code, ARMv8 AES decrypts **18.9x** faster on
the X3 and **21.8x** on the A710/A715 (9.0x on an A510, which shares a vector unit
per core pair), with zero mismatches over 60,000 blocks.
See [`docs/arm64/aes.md`](docs/arm64/aes.md).

## Feature to instruction to use-case

What the translators already exploit, so nobody re-derives it:

Pipe assignment for every one of these, read out of the vendored Cortex-X3 guide
rather than assumed. The *pipes* column decides more than the latency does:

| instruction | latency | throughput | pipes | note |
| --- | --- | --- | --- | --- |
| `SDOT`/`UDOT` | 3 (1) | 4 | **V** | all four pipes — the `SUMB`/`GB` choice is well placed |
| `TBX` | 2 | 4 | **V** | all four |
| `TBL` | 2 | 2 | `V01` | **half the throughput of `TBX`, and only two pipes** |
| `TBL`, 3 table regs | 4 | 1 | `V01` | |
| `CNT`, `UABD` | 2 | 4 | **V** | all four |
| `USHL`/`SSHL` | 2 | 2 | `V13` | pipe-restricted; the one to watch |

Two things fall out. **`TBX` beats `TBL` on this core** — four pipes against two,
throughput 4 against 2 — so the `SHUFB` path emitting `TBX2`, recorded below as a
correctness requirement, is also the faster form by a factor of two. And **`USHL` is
the only lowering here stuck on a two-pipe group**; it is used for `inf_shl`/`inf_lshr`
to dodge an LLVM poison-value pessimization, so it is load-bearing, but if a hot block
is shift-heavy that `V13` restriction is where it will show.

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
- **`config.yml` cannot be restored with a device-side redirect, and the emulator
  rewrites it on exit.** The file is `-rw-r-----` owned by the app, so `adb shell` is
  in its group with **read only** — `cat backup > config.yml` reports success and
  changes nothing. `adb push` works, because it replaces the file rather than writing
  into it. And RPCSX re-serialises the config when it exits, so a setting changed for
  one experiment survives into the next run and into the file itself. Raising a log
  channel to Trace for a single boot and walking away leaves verbose logging on
  permanently, which then slows every measurement after it. Restore with `adb push`
  and **verify the byte count matches the backup**.
- **Confirm an instrument's output channel produces anything before trusting its
  silence.** `vm_log` writes **zero** lines to `RPCSX.log` on this device, while
  `spu_log`, `ppu_loader`, `RSX`, `sys_*` all appear in quantity. A reservation watch
  logging through `vm_log` was placed six times, produced six silences, and had five
  conclusions drawn from it — all void, because the sink was dead. Checking that the
  format string is in the `.so`, that the property is set, and that the code path
  runs is worthless if nothing flushes. One `grep -c '} vm:'` would have caught it
  before the first build.
- **Every counter in this fork is incremented on completion, so none of them can see
  a hang.** The wait profiler records after `profiled_busy_wait`, the GETLLAR probe
  after its retry loop exits, the RSX auditor after a frame is presented. All three
  were armed against the Eternal Sonata deadlock and all three logged nothing, which
  looks exactly like "this code never ran". They answer *how much did this cost*,
  which is right for a spin and useless for a stall. Every fact in
  [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) came from sampling
  (`simpleperf`) or state inspection (`/proc`, `top -H`, a screenshot) instead. Do
  not add a fourth counter; what is missing is a record-on-entry slot a watchdog can
  read while the wait is still happening.
- **`grep -e 'a\|b'` through PowerShell into `adb shell` does not survive the trip.**
  A search for the RSX auditor's output returned nothing and was briefly taken as
  "the auditor never fired" — it had fired ten times. The alternation is mangled
  somewhere between PowerShell, `adb`, and the device's `sh`. Use a single plain
  pattern per invocation on device. This is the same failure as the entry below,
  which is why it is now listed as four.
- **A search that finds nothing and a search that searches nothing look
  identical.** This has now cost four times. The third was a device experiment
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
- **`debuggable` used to decide the native optimization level, and nobody noticed.**
  AGP picks `CMAKE_BUILD_TYPE` from the variant's debuggable flag — debuggable gives
  `Debug`, otherwise `RelWithDebInfo`. So `-PrpcsxThorDebuggable=1` silently moved the
  emulator core from `-O2 -g -DNDEBUG` to unoptimized **with assertions enabled**,
  which is a measurement hazard first and a 1.4 GB `.so` second. Any timing taken on a
  debuggable build before this was fixed is comparable only against another build from
  the same flag set. Now pinned: `build.gradle.kts` passes
  `-DCMAKE_BUILD_TYPE=RelWithDebInfo` explicitly, because debuggability is an APK
  manifest property and has no business deciding whether the SPU recompiler is
  optimized.
- **Every distinct CMake flag combination costs 8-11 GB of disk, and nothing reaps
  them.** `app/.cxx/<buildType>/<hash>/` is keyed on the argument list, so each flag
  combination spawns a fresh tree with its own objects and unstripped library. One
  session of toggling reached ~80 GB and filled a 930 GB disk. The failure does not
  look like a disk problem — Gradle reports
  `Failed to stop service '...BuildFinishBuildService'` under a Kotlin daemon heading,
  with `There is not enough space on the disk` in a sub-clause, so the instinct is to
  debug the toolchain. Run `tools/thor_reap_build_cache.ps1` (dry run by default,
  `-Apply` to delete) and check `app/.cxx` before believing any build error.
- **The version banner in `RPCSX.log` does not prove which binary is installed.**
  It read `v20260807-88f714c` while the running build was three commits newer and
  contained code that commit does not have. The build-info string is generated by a
  task that goes up-to-date and stops regenerating. This fork has already had one
  round where the question "did the change reach the device?" mattered enough to get
  its own commit, so verify with something the new code *does* — a property it reads,
  a symbol `grep -a` finds in the shipped `.so` — never the banner.
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
and never recovers. The screen keeps the last frame RSX presented — usually the SPU
cache overlay — which makes it look like a stalled compile. It is not; nothing is
being written to disk.

`simpleperf` on a debuggable build puts **two** threads at exactly 100%: an SPU thread
and `rsx::thread`, both reaching `sched_yield`. The SPU one is the real stall — it sits
in the **`GETLLAR` reservation retry loop** (`SPUThread.cpp:6212`), past its 24-spin
limit, in the slow-yield branch, waiting on a reservation that never settles. RSX is
merely spinning on an **empty FIFO** behind it.

The same site is the 93%-of-spin lever below. That makes this **the** thing to
understand: a reservation path that both deadlocks at boot and produced the two earlier
guest faults. It also blocks the GETLLAR sweep, which needs the title to reach gameplay.

Reproducing it takes one command and ten seconds, against a combat encounter for the
guest crash. Write-up, the six hypotheses ruled out, and the confident wrong answer that
static reading produced first, in [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md);
`tools/thor_diagnose_rsx_hang.ps1` gets back to it.

Investigating it needs `-PrpcsxThorDebuggable=1`. The release build refuses `run-as`,
and `/proc/<tid>/syscall` is useless anyway for a thread that never blocks — it reports
`running` every time.

## The three things actually open

0. **It is a SPURS defect, not one game.** Folklore stalls at the **same SPU PC
   `0x12b0`** in `CellSpursKernel0`, same `lsa=0x100`, same 24-retry cap, on a
   different reservation address. Both load Sony's SPURS kernel from `libsre`, so
   this is one instruction in one firmware module failing identically in two
   unrelated titles — two of the three tested. Fixing it is worth far more than one
   boot, and it also unblocks the GPU tiler work, which needs a title that renders.

1. **The Eternal Sonata deadlock**, above — now with an address and a culprit.
   `CellSpursKernel0` stalls on its workload reservation at **`0x9d4d80`**
   (`lsa=0x100`, `pc=0x12b0`, retries capped at 24), reported from inside the wait
   because no completion-time counter can see it. The reservation word is
   `ntime=0x200, unique_lock=0, counter=4` — **no leaked lock, line clean and
   readable, written exactly four times since boot and then never again.** So the
   reservation machinery is not at fault; the PPU side stops publishing the SPURS
   workload descriptor. SPURS has hung this title on this device before — the profile
   still carries *"SPURS 4 caused a black-screen-alive load hang on Thor"*. Next:
   log the four writes to `0x9d4d80` and find what should have caused a fifth.
2. **~~What hardware AES is worth on a cold boot.~~ Closed: nothing.** The firmware
   set is 144 files totalling **13.6 MB**, so at the measured rates the whole thing
   is 36.6 ms of software AES against 1.9 ms of hardware — about 35 ms, against a
   boot that takes minutes. The 19-22x is real and the volume is tiny; the ratio was
   never the interesting number. Still worth timing where the volume *is* large:
   PKG install and runtime EDAT/SDAT streaming. See
   [`docs/arm64/aes.md`](docs/arm64/aes.md).
3. **`SPULLVMRecompiler` and `PPUTranslator`.** The genuinely hot path, barely
   touched. One probe in so far, and it argues these are in good shape: saturating
   arithmetic goes through `llvm::Intrinsic::sadd_sat`, which AArch64 selects as a
   single `sqadd`/`uqadd` at **every** width — where x86 SSE has no 32-bit saturating
   add at all and synthesises it from `pcmpgtd`. VMX's `VADDSWS` is therefore cheaper
   here than on the architecture this emulator was written for.

   The lesson generalises: the translators emit **IR, not per-ISA intrinsics**, so
   the backend picks the encoding and there are no x86 intrinsics to find. The real
   search is narrower — *which operations have no natural IR spelling, and did the
   hand-written lowering pick well?* That is the `BCAX`/`SDOT`/`TBL`/`USHL` set, and
   [`codegen.md`](docs/arm64/codegen.md) already tracks it.

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
    ./tools/thor_getllar_percent_sweep.ps1

Four arms, one command. It throws rather than guessing if the property did not
take, the boot failed, or the profiler is absent, and it reports p95 frame time
because the risk of sleeping is **latency**, which a capped frame rate hides.
Detail in [`docs/arm64/spin.md`](docs/arm64/spin.md).

## ARM64 review coverage, so nobody re-sweeps clean ground

What has actually been looked at for "x86 assumptions that need rethinking here",
and what the answer was. **Most candidate wins evaporated under
measurement**, which is why this table exists.

The exception is instructive. The largest real defect was not a missed
optimization — it was `mov_rdata` silently compiling to nothing, found by
counting which branch of a loop executed rather than by reading code. Noticing
something was broken mattered more than optimizing anything.

| area | status | finding |
| --- | --- | --- |
| AES / `Crypto` | **fixed** | AES-NI was `#if __SSE2__`; ARMv8 AES now wired in, 19-22x on the primitive — but worth **~35 ms** of boot, because only 13.6 MB is decrypted |
| Saturating arithmetic | clean | `llvm.sadd.sat` → one `SQADD` at every width; x86 has no 32-bit saturating add at all, so VMX is *cheaper* here |
| Float↔int with scale | clean | `fptosi.sat(x * 2^n)` folds to a single fixed-point `FCVTZS` |
| Acquire loads | clean | `cortex-a78` already emits `LDAPR`; `+rcpc` changes nothing |
| 128-bit atomics | clean | LSE2 path live and verified in the build cache, not the `LDAXP`/`STLXP` loop |
| Non-temporal stores | clean | `_mm_stream_si128` reaches a real `STNP` through the shim |
| `MFCR`, PPU interpreter | clean | already `ARCH_X64`-guarded with an ARM64 fallback |
| SPU interpreter | **cold** | unguarded `movemask`, but both decoders are LLVM — the interpreter is fallback-only |
| Rosetta techniques | n/a | its central problem (x86 TSO) does not exist; PowerPC is weakly ordered and AArch64 is stronger |
| **GPU render passes** | **open, instrumented** | unconditional `LOAD_OP_LOAD`/`STORE_OP_STORE`, `LOAD_OP_CLEAR` used zero times, ~16 MB/frame. The blocker (a title that renders) is gone; eligibility counters now at `VKGSRender.cpp:1631`, unrun |
| **`mov_rdata`** | **fixed** | the `#elif defined(ARCH_ARM64) && defined(__clang__)` branch held **only comments** after a revert, so the copy every reservation is validated against did nothing. 10,093,915 failed retries in one boot; two titles could not boot. `tools/check_empty_arch_branches.py` now guards the class |
| **UMA / BAR heap** | **open, measured** | `device.cpp` parks host-visible+device-local memory as a scarce PCIe aperture. Here it is 11441 MB — one heap, every type device-local, type 1 also `HOST_CACHED`. The staging copy's destination is its own source. Volume counter added, unrun |
| SDOT/UDOT | clean | the video's headline optimization is already here: `sdot`/`udot` at a dozen sites in `SPULLVMRecompiler.cpp`, gated on `HWCAP_ASIMDDP`, default **on**, with a `debug.rpcsx.thor.spu_arm_features` override |
| SPU/PPU translator lowerings | clean so far, 3 probes | saturating arithmetic → `SQADD` at every width; SPU `AVGB` → a single **`URHADD`**; SPU `ABSDB` → a single **`UABD`**. All from *generic IR* with no ARM-specific code. The remaining question is only the ops with **no** IR spelling — the `BCAX`/`SDOT`/`TBL`/`USHL` set in [`codegen.md`](docs/arm64/codegen.md), which already have hand-written lowerings |
| RSX vertex/texture paths | clean | `RSXThread.cpp` has **no** x86 intrinsics; `ProgramStateCache.cpp` already byteswaps with `vrev16q_u8` (one `REV16` against x86's shift-or pair) and keeps its AVX-512 behind `ARCH_X64`; `buffer_stream.hpp` reaches a real `STNP` |

The pattern worth carrying: the translators emit **IR, not per-ISA intrinsics**, so
the backend picks the encoding and there are usually no x86 habits to find. Effort
belongs where no portable IR construct exists, or where the *hardware model*
differs — which is why the GPU tiler row is the one that is still open.

## Where the rest of this lives

These notes outgrew a single file. The detail is split by topic; each document
stands on its own and this file is the map.

| document | what is in it |
| --- | --- |
| [`docs/arm64/codegen.md`](docs/arm64/codegen.md) | What this fork does: the lowerings chosen here, the missing movemask, the SPU opcode audit, and the x86-habit table that produced most of the real defects. |
| [`docs/arm64/microarchitecture.md`](docs/arm64/microarchitecture.md) | What the hardware does: instruction latency, throughput and pipe assignment from the vendored per-core guides, the forwarding regions, and the chapter 4 rules. |
| [`docs/arm64/memory-model.md`](docs/arm64/memory-model.md) | Atomics and ordering: the LSE2 128-bit path (no longer dead — see below), the reservation seqlock, RCsc versus RCpc, and instruction-cache maintenance. |
| [`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md) | **The largest finding here, and the only one from a real profile.** 73.9% of all cycles are a nop-spin in two lv2 wait syscalls; the same loop appears at eight sites across the guest sync layer. |
| [`docs/arm64/spin.md`](docs/arm64/spin.md) | Where the CPU time goes *on the SPU side*: 93% of instrumented spin is the `GETLLAR` wait. Read `lv2-ppu-spin.md` first — that 93% is a share of the sites the wait profiler counts, and it counts no PPU sites. |
| [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) | **Resolved.** The boot hang, three wrong diagnoses, and the empty `mov_rdata` branch behind it. Folklore now reaches its title screen at 60.01 FPS. |
| [`docs/arm64/uma-bar-heap.md`](docs/arm64/uma-bar-heap.md) | Snapdragon is UMA, so the "BAR heap" the Vulkan backend parks as scarce is all 11.4 GB of it. What is measured and what is not. |
| [`docs/arm64/ppu-compile-oom.md`](docs/arm64/ppu-compile-oom.md) | A second title dies in PPU precompile with a Scudo out-of-memory, and why the 1536 MB budget bounds concurrency rather than footprint. |
| [`docs/arm64/aes.md`](docs/arm64/aes.md) | AES-NI is x86-gated, so every module decrypted at boot uses software AES on a chip with AES instructions — plus three related checks that came back negative. |
| [`docs/arm64/x86-isms-sweep.md`](docs/arm64/x86-isms-sweep.md) | Every remaining `_mm_*` site outside 3rdparty, asked "is this executed?" before "is this optimal?" — and why the interpreters, which look like the biggest target, are not. |
| [`docs/arm64/rosetta-lessons.md`](docs/arm64/rosetta-lessons.md) | What Rosetta 2 does and why its central problem — x86's TSO — does not exist here, plus the four techniques it is famous for that this codebase already has. |
| [`docs/arm64/adreno-tiler.md`](docs/arm64/adreno-tiler.md) | **The one place the code is still written for the wrong hardware.** Every render pass unresolves and resolves both attachments, and `LOAD_OP_CLEAR` is used zero times. |
| [`docs/arm64/instruments.md`](docs/arm64/instruments.md) | The measuring tools, what each can and cannot answer, and the mistakes made building them. |
| [`docs/arm64/thermal.md`](docs/arm64/thermal.md) | Junction versus package sensors, and the guard that compared a limit against the wrong one. |
| [`docs/arm64/ledger.md`](docs/arm64/ledger.md) | The audit ledger: every `ARCH_X64` block accounted for, the open opportunities, and the subsystems that needed nothing. |
| [`docs/hardware/`](docs/hardware/) | Vendored vendor docs: Arm's Cortex-X3, A715 and A710 optimization guides, plus Qualcomm's 200-page Adreno guide — and why the GPU one opens a review axis nothing here has started. |

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

## Traps found while enumerating guest threads

**PPU thread ids are not stable across boots.** `0x1000009` was `SpursHdlr0` in one
Folklore boot and `LoadThreadMain` in the next. Ids are handed out in creation
order, so any tool that hardcodes an id-to-name map is only valid for the boot it
was written against — and `tools/thor_gdb_probe.py` did exactly that. Recover names
from `RPCSX.log`, which prints them as `PPU[0x100000c] Thread (SpursHdlr0)`.

**The GDB stub implements `qfThreadInfo` and nothing else.** No `qThreadExtraInfo`,
so it cannot tell you a thread name. Worse, it is single-shot in two ways:
connecting **pauses emulation** (`Emulation is being paused... (mark=0)`), and
disconnecting **kills the stub thread** (`GDB.cpp:241`, "Tried to read char, but no
data was available"). Budget one probe per boot and collect everything in that one
connection. `tools/thor_gdb_all_threads.py` does the full sweep.

**Git Bash rewrites device paths.** `adb pull /sdcard/...` becomes
`C:/Program Files/Git/sdcard/...` and fails with a confusing "failed to stat remote
object" naming a local path. Prefix with `MSYS_NO_PATHCONV=1`. This is separate from
the heredoc backslash problem that previously turned `.\tools\thor_x.ps1` into a
line with two literal tabs in it.

**A conclusion from one boot is a conclusion about one boot.** The SPURS descriptor
was all zero in one run and had `wklReadyCount1[7] = 1` in the next — same title,
same stall, same `pc=0x12b0`, opposite readings. Two conclusions in
`docs/arm64/rsx-boot-hang.md` were drawn from single boots and neither survived a
second. Re-run before concluding.

## Read the build warnings

`mov_rdata` compiled to a function that copied nothing on every ARM64 build from
b46198f0b (2026-08-07) until b15d105a6, because that revert left an empty
`#elif defined(ARCH_ARM64) && defined(__clang__)` branch behind. It is the copy
every SPU reservation is validated against, and it cost several sessions of
investigation across `docs/arm64/rsx-boot-hang.md`.

The compiler reported it on every single build:

    SPUThread.cpp:1301:25: warning: unused parameter '_dst'
    SPUThread.cpp:1301:50: warning: unused parameter '_src'

Unused parameters on a function whose only job is to write `_dst`. Nobody read
it because the build prints hundreds of warnings.

`./gradlew assembleThortest 2>&1 | grep -E "warning: unused (parameter|variable)"`
is cheap. An unused parameter on a function that exists to write through it is
not style: it means the body is gone.

**And when a loop will not exit, count its exits.** Four counters on the four
`continue` paths of the GETLLAR retry loop identified the failing comparison in
a single boot — after three separate wrong conclusions had been reasoned out
from static reading and single-boot dumps.

## The BAR heap is not an aperture on this device

`Emu/RSX/VK/vkutils/device.cpp` collects memory that is host-visible *and*
device-local into a "BAR heap" and parks it: `// BAR heap, currently parked for
future use`. That is right for a discrete GPU, where those bits mean the PCIe
aperture and historically 256 MB of it.

Measured on the Thor — `VkPhysicalDeviceMemoryProperties`, dumped at
`device.cpp:1186`:

    type 0: DEVICE_LOCAL HOST_VISIBLE HOST_COHERENT              11441 MB
    type 1: DEVICE_LOCAL HOST_VISIBLE HOST_COHERENT HOST_CACHED  11441 MB
    type 2: DEVICE_LOCAL HOST_VISIBLE HOST_CACHED                11441 MB
    type 3: DEVICE_LOCAL LAZILY_ALLOCATED                        11441 MB

**One heap, every type device-local.** There is no separate VRAM here, so the
staging copy on the way to "device-local" memory has a destination that is the
same physical DRAM as its source. Type 1 is device-local, host-visible, coherent
and cached at once, which is the combination a direct-write upload path needs.

Type 3 (`DEVICE_LOCAL | LAZILY_ALLOCATED`, no host visibility) is Adreno's
on-chip tile memory — the correct backing for transient depth/MSAA attachments
that are never sampled outside their pass, and a direct pairing with the
`LOAD_OP_CLEAR` work in `docs/arm64/adreno-tiler.md`.

Feasibility is settled; the win is not measured. `docs/arm64/uma-bar-heap.md`
records what still has to be shown before changing the upload path.

## The manual the video was about, and the optimization it describes

The video that set this project's direction is *"PS3 emulation is fast on ARM
now"* (2026-08-04). The manual it refers to is **not** a Qualcomm chipset
document — it is the **Arm Architecture Reference Manual**, which the RPCS3 team
describe scouring *"every page"* of, *"over 17,000 pages"*. That page count
identifies the issue exactly: **DDI 0487 M.c has 17,145 pages**. It is now
vendored in `docs/hardware/` as three ~40 MB parts, rebuilt by
`sh docs/hardware/assemble_arm_arm.sh` (SHA-256 checked). Split because 120 MB
exceeds GitHub's hard 100 MB blob limit and **LFS is refused on this repo** —
GitHub blocks LFS uploads to a public fork, as the objects bill to the upstream
owner.

Fetch the current issue from Arm's JSON index rather than guessing CDN paths:

    curl -sS "https://documentation-service.arm.com/documentation/ddi0487/latest?lang=en&baseUrl=/documentation"

`_links.resources[0].href` is a plain-`curl`-fetchable URL.

**Its headline optimization is already in this fork.** The video's specific claim
is Armv8 `SDOT`/`UDOT` used to speed up SPU emulation. Checked rather than
assumed, after `mov_rdata` taught this project what an unchecked assumption
costs:

* `SPULLVMRecompiler.cpp` uses `sdot`/`udot` at a dozen sites.
* They are gated on `m_use_dotprod` ← `utils::use_spu_dotprod()`
  (`sysinfo.cpp:548`).
* That reads `has_dotprod()`, which tests **`HWCAP_ASIMDDP`** — correct runtime
  detection, not a compile-time guess.
* The default feature mode is `native`, so it is **on**, with a runtime override
  at `debug.rpcsx.thor.spu_arm_features` (`no-dotprod`, `no-i8mm`, `baseline`)
  for A/B work.

So there is nothing to port here — the useful follow-up is measuring what those
modes are worth on this device, not implementing them.

## Guard against the empty-branch class

`python tools/check_empty_arch_branches.py` walks the native tree and fails if any
`#if`/`#elif` on `ARCH_ARM64`, `ARCH_X64`, `__aarch64__` or `__x86_64__` contains
only comments. It skips `3rdparty` and `llvm`, and handles nesting so an inner
`#else` is not mistaken for the end of the branch.

Currently: **1,489 files scanned, zero findings.** It is verified against a
reconstruction of the `mov_rdata` defect, which it flags with exit 1 — a check
that has never caught anything and has never been shown to catch anything is not
worth trusting.

Run it after any revert that removes a function body. That is precisely how the
original was introduced.

## Wireless adb, and "the process died" when it did not

The Thor answers on both a USB serial and `192.168.1.33:5555`. The USB serial
disappears without warning, and `adb devices` then lists only the network one —
so a script pinned to the USB serial fails with `device 'c3ca0370' not found`
rather than falling back. Reconnect with `adb connect 192.168.1.33:5555`.

Over Wi-Fi the link drops mid-run. That breaks the obvious liveness check:

```sh
alive=$(adb -s $S shell "pidof net.rpcsx.easy")
if [ -z "$alive" ]; then echo "DIED"; fi      # wrong
```

An unreachable device returns empty exactly like a dead process. A watcher
written this way reported `DIED` while the emulator was still running and had
been for two minutes. Probe reachability separately before believing an empty
`pidof`:

```sh
ok=$(adb -s $S shell "echo ok" 2>/dev/null | tr -d '\r ')
[ "$ok" != "ok" ] && echo "adb unreachable, liveness unknown"
```

The general shape is the one this project keeps rediscovering: **a negative
result from a channel you have not proved is working is not a negative result.**
Same class as `vm_log` emitting nothing and the `grep 'a\|b'` alternation.

## Confirmed on device: the dotprod path is live

Not inferred from source — logged by `CPUTranslator.cpp:248` on the Thor:

    LLVM: AArch64 SPU fast paths: mode=native, dotprod=true, i8mm=true, sha3=true
    JIT: LLVM AArch64 target: cpu=cortex-a78 attrs=+sha3,+dotprod,+i8mm,-sve,-sve2

So the video's SDOT/UDOT work is active here, and any A/B against it only needs
the `debug.rpcsx.thor.spu_arm_features` property, not a rebuild.

## Do not put `head -N` on a grep you are about to reason from

Searching for `on_frame_end` call sites with `| head -5` returned five hits from
`texture_cache.h`, none of them the auditor, and the conclusion drawn was "the
auditor is never called". It is called, at `VKPresent.cpp:286` — the line was
just past the cut.

`head` on an exploratory grep is fine. `head` on a grep whose *absence* of a
result you intend to treat as evidence is the same mistake as the alternation
grep, in a new costume. Count first (`grep -c`), then page.


# The audit ledger

[`docs/arm64/audit-ledger.md`](docs/arm64/audit-ledger.md) tracks the
codebase-vs-manuals sweep: what has been checked, by what method, and what is
left in priority order. Read it before starting another pass, so the sweep is
resumed rather than restarted.

Its central finding is about method. **Sweeping the manual for slow instructions
and hunting for them does not work here** — four predictions derived that way,
four refuted by measurement (`ISB` +23%, `cmp_rdata` 0.3%, UMA upload 8.5
KB/frame, shift-form rewrite identical). **Establishing reach first does work** —
every real defect came from asking whether code runs at all and with what:
`mov_rdata` compiled to nothing, the auditor's `enabled()` is `constexpr false`,
1.88 W was a leaked process.

sse2neon is closed as a concern: `Emu/CPU/sse2neon.h` has exactly **two**
includers, `SPUInterpreter.cpp` (cold, both decoders are LLVM) and
`ProgramStateCache.cpp` (already `vrev16q_u8`).

# Use the manuals

They are vendored in `docs/hardware/` for a reason. Reasoning from memory about
what a chip does, when a 17,145-page manual describing it is sitting in the
repo, has produced wrong answers in this project more than once. Open them.

**But route the question to the right one.** Measured by counting pages that
mention power/energy/watt:

| document | pages | covers | does *not* cover |
| --- | --- | --- | --- |
| Arm ARM (DDI 0487M.c) | 17,145 | instruction semantics, encodings, system registers | timing, power — none at all |
| Cortex X3/A715/A710/A510 guides | 71-73 each | latency, throughput, **pipe assignment** | power (2 of 73 pages mention it) |
| Adreno Game Developer Guide | 200 | GPU architecture, GMEM, UBWC, **power** (28/200 pages) | CPU anything |
| Snapdragon OpenCL guide | 116 | memory hierarchy, cache line, zero-copy, **power** (24/116) | the Vulkan API surface |

The Arm core guides are timing documents. For a *power* question the Qualcomm
documents are the ones with content, which is the opposite of what I assumed.

## The Adreno guide assumes a driver we are not running

`Thor Vulkan Feature Doctor: gpu='Turnip Adreno (TM) 740'`

**Turnip** is Mesa's open-source Adreno driver, not Qualcomm's. Every proprietary
extension the Adreno guide recommends is absent on this device:

    extension: [missing] VK_QCOM_tile_memory_heap
    extension: [missing] VK_QCOM_tile_shading
    extension: [missing] VK_QCOM_tile_properties
    extension: [missing] VK_QCOM_elapsed_timer_query
    extension: [missing] VK_QCOM_queue_perf_hint

So read that guide for **what the hardware does** and discount its API advice.
`VK_QCOM_tile_memory_heap`, which it recommends for exactly the reason we care
about — *"replacing comparatively power-hungry memory bus traffic with cheaper
GMEM operations"* — cannot be used here.

## Tile memory is available anyway, and unused

The portable route to GMEM is core Vulkan, not a QCOM extension:
`VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT` backed by a
`VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` memory type. This device offers one:

    type 3: DEVICE_LOCAL LAZILY_ALLOCATED   11441 MB

and the emulator **never uses either flag** — the only occurrence of
`LAZILY_ALLOCATED` in the whole VK backend is the diagnostic that printed that
line. Every depth and MSAA attachment is therefore backed by real DRAM even when
it is never sampled outside its pass and never needed to leave the tile.

That is an unexploited hardware capability, it is reachable without the missing
extensions, and the vendor documents it as a power win. It pairs with the
`LOAD_OP_CLEAR` work in [`docs/arm64/adreno-tiler.md`](docs/arm64/adreno-tiler.md).

## A stale process cost 1.9 W

The user reported the device drawing 1-2 W more than the day before.
`tools/thor_power_probe.ps1` with the emulator supposedly stopped:

    system power   : 3.481 W    cores busy (avg) : 3.27 of 8
      A710/A715    : 2.216 cores busy at 2803 MHz

`pidof net.rpcsx.easy` returned empty immediately after `am force-stop`, and a
`net.rpcsx.easy` process was nonetheless alive at **210% CPU** with `ETIME`
showing it had started *after* the force-stop. It respawns. After killing it:

    system power   : 1.598 W    cores busy (avg) : 0.676 of 8

**1.88 W, entirely a leaked emulator process.** Check `top` before trusting
`pidof` after a force-stop, and check power against a known-idle baseline rather
than against memory of yesterday.

# Shared device protocol

**The Thor is shared with another Claude session testing Xbox 360 emulation**
(`jp.xenia.emulator.github.debug`). Both agents install, launch and kill apps on
the same hardware.

Rules, learned by breaking them:

1. **Close the emulator before you start and after you finish.** Not only after.
   A previous session's emulator left running is indistinguishable from your own
   until you check the pid, and it costs real power — a leaked `net.rpcsx.easy`
   was measured at **210% CPU and 1.88 W** while nothing was on screen.
2. **Never force-stop the other session's package.** Xenia is not ours. Check
   what is running before assuming a busy device is your fault.
3. `pidof` is not sufficient after `am force-stop`. The process can respawn on
   its own, and an unreachable adb returns empty exactly like a dead process.
   Confirm with `top -b -n 2 -d 2` (a single `-n 1` sample reports every row as
   0.0% because there is no delta to compute).
4. Battery is shared too. Check the level before starting a long run.

# The manual question, settled

The goal text asks for "a snapdragon gen 8 chipset manual that was huge" from
the video. **That manual is the Arm Architecture Reference Manual, not a
Qualcomm document.** The video ("PS3 emulation is fast on ARM now") describes
scouring *"every page of an ARM Architecture manual with over 17,000 pages"*,
and the page count identifies the issue exactly: **DDI 0487M.c is 17,145
pages**. It is vendored, split into three parts.

The Snapdragon SoC-level manual — the SM8550 *Hardware Register Description* —
**is not public**, confirmed from two independent directions: Qualcomm
distributes it to partners, and Lantronix states plainly that HDK schematics and
manuals are available only to purchasers through their technical portal. The
SM8550 data sheet (80-33265-1) surfaces only on Scribd behind a paywall.

What is public and vendored instead covers **every block of this chip**, which
is the useful form of the question. `docs/hardware/README.md` carries the map;
in short, the device reports `ro.soc.model=QCS8550` / `kalama`, and its
Cortex-X3 (3187 MHz), A715/A710 (2803 MHz) and A510 (2016 MHz) clusters, its
Armv9-A instruction set and its Adreno 740 each have a vendored document. The
Arm core guides are not generic material here: those cores *are* the 8 Gen 2.

Two things were found and deliberately **not** vendored. The Snapdragon 8 Gen 2
Product Brief is public, and is two pages of marketing with no technical
content. `docs.qualcomm.com` numbers briefs `87-*` and technical guides `80-*`,
which is why both Qualcomm files here are `80-*`. Padding `docs/hardware/` to
satisfy a checkbox is worse than recording that the real document is gated.

The register description would not help much even if it were public: it
documents SoC peripheral registers for driver authors, while this project writes
userspace on top of Android's drivers and Mesa Turnip. Every finding so far came
from instruction timing, instruction semantics or GPU behaviour.

# Open: the RSX auditor emits nothing

Unresolved, and worth writing down so the next session does not re-derive it.
With `debug.rpcsx.thor.rsx_auditor=1` set before launch and Folklore rendering
at 60 FPS, the auditor produces **zero** lines. Everything checked so far says
it should work:

* `on_frame_end` is at `thor_rsx_auditor.h:857`; the
  `RPCSX_THOR_RSX_EXPERIMENTS` guard at 794 closes at 825, so it is **not**
  compiled out.
* It is called from `VKPresent.cpp:286`, inside `advance_queued_frames()`,
  reached from `queue_swap_request()` at `VKPresent.cpp:1003`.
* The `skip_frame || swapchain_unavailable` mini-flip path that bypasses it
  early-returns at `VKPresent.cpp:588` and does not apply while rendering.
* `looks_disabled("1")` is false and `parse_interval("1")` yields 60, so the
  property is enabled with a 60-frame interval.
* Other `rsx_log.warning` output does reach the log, so the channel works.

The installed APK was confirmed to be the instrumented one
(`lastUpdateTime` after the build). Next step is a one-shot unconditional log at
the top of `on_frame_end` to separate "not called" from "`enabled()` false" —
which is the same technique that cracked `mov_rdata`, and should have been the
first move rather than five rounds of reading.

# The video's optimization list, checked against this fork

Pulled from the source rather than from summaries: the chapter markers of
*"PS3 emulation is fast on ARM now"* (`ytInitialPlayerResponse.videoDetails`,
via `tools/` Playwright). This is the actual list of things it claims, so it is
the actual list to check. Status is what was verified here, not what was assumed.

| # | chapter | status in this fork |
| --- | --- | --- |
| 00:55 | Busy wait shenanigans | covered at length in [`spin.md`](docs/arm64/spin.md); 93% of spin is the GETLLAR wait |
| 06:40 | **Don't use Yield in place of Pause!** | **was wrong here.** `rx::pause()` emitted `yield`, a nop on SMP. Now switchable via `debug.rpcsx.thor.pause_mode`; **unmeasured** |
| 09:32 | What was LLVM doing on ARM? | JIT attrs logged and verified on device: `cpu=cortex-a78 +sha3,+dotprod,+i8mm,-sve,-sve2` |
| 12:45 | How we optimized SHUFB | hand-written lowering already present — see [`codegen.md`](docs/arm64/codegen.md) (`TBL` set) |
| 19:04 | The rest of the instructions | swept: `SQADD`, `URHADD`, `UABD`, fixed-point `FCVTZS` all clean from generic IR |
| 29:46 | The most optimized way to compare data on ARM | `cmp_rdata`/`mov_rdata` — where the empty `#elif` was found; **re-examine the compare now that the copy is fixed** |
| 38:55 | How to play wow optimally | n/a |
| 39:28 | SVE are the *special* vector extensions | **does not apply to this device.** `has_sve()` reads `HWCAP_SVE`, and the Thor's HWCAP does not report it — the JIT log shows `-sve,-sve2` |
| 47:50 | Optimizing RPCS3 with SVE | same: no SVE on this hardware, so both chapters are inapplicable here |
| 54:24 | Optimizing via hardware wait instructions | `WFE` explored (three experiments, [`spin.md`](docs/arm64/spin.md)); `FEAT_WFxT` absent on this chip so `WFE` cannot carry a timeout |
| 55:33 | Lightning round | the sweep table above covers this ground |

Two things this changed. The pause/yield item was a **real defect sitting behind
a TODO** in our own source, and it is the item the video names most explicitly.
And the two SVE chapters — a fifth of the video — are inapplicable to this
device, which is worth knowing before anyone spends a session on them.

Get the chapter list this way rather than from news coverage; the summaries
paraphrase and one of them is what led to the wrong idea that the manual was a
Qualcomm document:

```js
await p.evaluate(() => window.ytInitialPlayerResponse.videoDetails.shortDescription)
```

# Measuring power on the Thor's second screen

The AYN Thor has a secondary display that can show live power draw. That is the
instrument to trust for "is this cooler", because `tools/thor_power_probe.ps1`
degrades badly when USB is attached: adb over USB charges the device, so
`power_supply/battery/current_now` reports charge current rather than system
draw and the probe reports a **FLOOR**, not a figure. Wireless adb plus the
second screen gives a real number.

Reference loads measured this session, so a reading has something to sit against:

| workload | cores busy | probe reading |
| --- | --- | --- |
| idle, emulator stopped | 0.68 of 8 | **1.60 W** (on battery, exact) |
| idle with a leaked emulator process | 3.27 | **3.48 W** |
| Folklore, title screen, 60 fps | 2.23 | not derivable (charging) |
| **Eternal Sonata, gameplay** | **5.26** | 5.5 W floor, USB attached |

Eternal Sonata is the heavy one — 5.26 of 8 cores busy, with 3.18 of those on the
A710/A715 cluster — and a **9 W spike at the wall during it is expected**, not a
fault. Folklore at ~2.2 cores is less than half that load.

If a spike appears with nothing obviously running, check `top` before anything
else: a leaked `net.rpcsx.easy` at 210% CPU accounted for 1.88 W once already,
and `pidof` did not report it after `am force-stop`.

# Before acting on anything a manual says

Nine manual-derived predictions were measured on this project and **nine were
refuted**. The manuals were right every time; the reasoning on top of them was
not. Full analysis in [`docs/arm64/audit-ledger.md`](docs/arm64/audit-ledger.md).
The four failure modes, as a checklist to run before writing code:

1. **Did I read the adjacent rows?** The shift rewrite assumed immediate shifts
   were wider than register shifts. Both are `V13`. One extra row would have
   killed it before any work.
2. **Am I reading the right core?** This is big.LITTLE with three guides. The
   whole narrow-pipe sweep quoted Cortex-X3 while the code runs on A715, where
   the same instructions are narrower still. Check where the thread is pinned
   (`config.yml` Affinity) before picking a guide.
3. **Is the manual actually recommending this, or am I inferring it?** A guide
   states what an instruction costs on the chip. It cannot know whether the code
   is hot, what contends for the pipe, or what was tuned around the current form.
   `ISB`: the manual was right that `YIELD` is a nop, and the swap still cost
   **23%** because the spin counts were calibrated around a cheap instruction.
   `BCAX`: `V0` throughput 1 is real and it still **wins by 5.6%** because it
   replaces two operations.
4. **Have I established reach before optimality?** `cmp_rdata` looked critical at
   10,093,915 calls; those calls existed only because of a deadlock later fixed.
   Ask "does this run, and how often, on the workload that matters" first.

And the two attribution traps that produced confident wrong answers:

* **Nearest-symbol attribution is not heat.** An `inline` function emitted into
  many translation units becomes the nearest preceding symbol over large address
  ranges in a partly-stripped binary. ~31% of samples "in"
  `get_thor_pause_mode` were an artifact.
* **A histogram of a JIT dump counts what was compiled, not what runs.** 3,946
  `ldsetal` in one module looked alarming; they are one per function entry, on a
  path guarded by a likely-branch.

**The rule:** a manual row is a hypothesis about the chip, never a conclusion
about the code. Answer the two questions the manual cannot — *is this hot* and
*what is it competing with* — then measure on device. The device has overruled
the table nine times out of nine.

# Write the hypothesis down before touching the device

Twelve optimisation attempts here were refuted or retracted. **Eleven had no
predicted effect size.** That is the single cheapest thing to fix, and it costs
nothing but a minute of thinking.

Before any experiment, state four things. If any cannot be answered, the answer
is not "run it and see" — it is that the experiment is not ready.

1. **Mechanism.** What physically gets cheaper, in one sentence.
2. **Predicted magnitude, as a number.** Not "faster" — a percentage or a
   millisecond count, with the arithmetic. Most bad experiments die here: AES
   interleaving is a real 4x on the primitive, and `aes.md` already measured the
   total volume at 13.6 MB / ~35 ms of boot, so the prize is ~26 ms. Written
   down, it is obviously not worth doing.
3. **What already bears on this in the repo.** Almost every failure below was
   answerable from something already present — a code comment, a filename, an
   existing measurement — and was not looked at.
4. **What result would falsify it**, and what confound would fake a win.

## The twelve, and the prior that would have killed each

| attempt | prior question | where the answer already was |
| --- | --- | --- |
| `ISB` for `YIELD` (+23%) | was surrounding code tuned around current behaviour? | **the comment at the site said the spin counts were hand-tuned with YIELD** |
| `cmp_rdata` tree (0.3%) | still hot after the bug I just fixed? | the profile; the 10M calls were the deadlock |
| UMA direct upload (8 KB/frame) | what is the byte volume? | one counter, no code change |
| AES 4x interleave | how many bytes total? | `aes.md`: 13.6 MB, ~35 ms |
| shift rewrite (identical) | read the adjacent table row | the same page |
| `pause()` guard (no change) | is nearest-symbol valid for an `inline` function? | it never is |
| `LOAD_OP_CLEAR` (no saving) | does Turnip already fold this? | Mesa is open source |
| cortex-a710 ×2, jit A/B (artifacts) | does changing this invalidate a cache? | **the cache filename contains the CPU name** |
| GETLLAR busy-wait (−2.9%) | 93% of *spin* — but how much of *total* is spin? | the profile |

**Retrieval was not the problem.** The right manual row was found every time.
RAG or embeddings over the manuals would have helped with exactly one of these —
reading the X3 table for work that runs on A715 — and that is a routing rule
("which core is this thread pinned to?"), not a search problem.

## The two habits that produce fake wins

* **A large result is a bug until proven otherwise.** Three "wins" of +24%, +92%
  and −24% were all phase mismatches. Verified gameplay on this title sits at
  13,352–14,624 Mcyc/s at ~5.2 cores busy; anything far outside that band is
  measuring a different program state, not a faster one.
* **Check cores-busy across arms before reading the headline number.** It caught
  all three. If the arms differ by more than a few percent there, the comparison
  is void regardless of what the summary says.
