# Fast AArch64 PS3 Emulation on Snapdragon 8 Gen 2

Technical notes for making this emulator fast on Thor. `AGENTS.md` is the
operating contract; this file is the hardware knowledge behind it.

# Write all documentation in ASD-STE100

Use Simplified Technical English (ASD-STE100) for all new documentation and all
commit messages. Write the rules into new text. Do not rewrite old text only to
change its style.

## The rules that apply here

1. **Write short sentences.** Use a maximum of 25 words in a descriptive
   sentence. Use a maximum of 20 words in an instruction.
2. **Write one instruction in one sentence.** Do not put two commands together.
3. **Use the active voice.** Write "the JIT emits a spin loop". Do not write "a
   spin loop is emitted".
4. **Use one word for one meaning.** If you call it a "park", call it a "park"
   every time. Do not also call it a "sleep", a "wait", or a "block".
5. **Use simple tenses.** Use the present, the past, or the future. Do not use
   the perfect tenses.
6. **Keep noun clusters to three words.** Write "the cache for SPU objects". Do
   not write "the SPU native object cache key".
7. **Write a maximum of six sentences in a paragraph.**
8. **Use articles.** Write "the profile shows". Do not write "profile shows".
9. **Do not use synonyms for effect.** Repeat the noun.

## What does not change

STE controls the language. It does not control the content. These rules stay:

* Give the number, and give the workload with it.
* Say what you measured. Say what you did not measure.
* Record a retraction in the same file as the claim.
* Quote the file and the line.

STE makes these easier, not harder. A short sentence in the active voice cannot
hide a weak claim behind a long clause.

## The tension, stated plainly

Much of the older text in `docs/arm64/` is discursive. It explains why an
inference failed. STE permits this, but STE needs more sentences to do it. Accept
the extra sentences. Do not compress the reasoning to save words.

**Do not convert the old documents in one pass.** A large rewrite of correct text
creates risk and gives no gain. Convert a document when you change it for another
reason.

## Read this first: the lv2 waits spin instead of sleeping, and a profile found it

A symbolized profile of a healthy 60 fps run — 31,657 samples, 0 lost, no pause —
puts **73.9% of cycles inside two lv2 wait syscalls**. Read that number with its
workload attached: it is **Folklore's title screen**, where the emulator is mostly
waiting. Under Eternal Sonata gameplay the same change is worth 4.5%, not 67%. The
spin is pure waste on both — no arm ever lost frame rate — but the size of the
prize tracks how idle the scene is. The two hot functions are
`sys_event_queue_receive` (47.8%) and `_sys_lwcond_queue_wait` (26.1%), as *self*
time that never reaches `atomic_wait_engine::wait`. They are spinning, not
sleeping: `50 × rx::busy_wait(500)`, which on a **19.2 MHz** generic timer is
**1.3 ms** of `YIELD` — a nop on this SMP core. The identical loop is at
**eight sites** across the guest synchronization layer.

**Measured, not just predicted**, with the budget behind
`debug.rpcsx.thor.lv2_spin`:

| workload | default (50) | no spin (0) | saving |
| --- | --- | --- | --- |
| Folklore, title screen | 1.200 cores | 0.390 | **67.6%** (spread 0.005) |
| Eternal Sonata, gameplay | 3.193 | 3.049 | **not established** — see below |

**Eternal Sonata CPU cannot resolve anything below ~1.4 cores.** Two arms running
*identical code* (a failed install, caught by grepping the on-device `.so`)
differed by **1.37 cores, 58%**. Every gameplay CPU delta reported here is an
order of magnitude under that, so the gameplay saving is downgraded to not
established. Folklore resolves 0.005 cores and is the title to A/B on.

Then frame-time percentiles from `dumpsys SurfaceFlinger --latency` on the BLAST
layer — four gameplay arms in both orders, ~750 frame intervals each — put
**p50/p95/p99 within 0.02 ms across every arm**, with CPU lower in every pairing.
No latency cost at any percentile.

**So the default is now `0`.** `debug.rpcsx.thor.lv2_spin=50` restores upstream
behaviour. Full account in
[`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md).

## And where gameplay time actually goes

A second profile — Eternal Sonata gameplay, **119,662 samples, 0 lost, 0 pauses** —
shares almost no hot code with the title screen above:

| | share |
| --- | --- |
| **JIT-generated code (unnamed)** | **47.88%** |
| `librpcsx-android.so` | 34.65% |
| kernel | 11.80% |

| top named symbol | share |
| --- | --- |
| `spu_thread::process_mfc_cmd()` | **20.13%** |
| `vm::writer_lock` | 4.49% |
| `vm::passive_lock` | 1.73% |

**Almost half of gameplay is code no symbolizer can name**, and the biggest named
function is the SPU DMA path, which this project had never looked at. The lv2
waits that were 73.9% of the title screen do not reach 1% here. Details and the
static disassembly of the JIT cache in
[`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md).

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
correctness requirement, is also the faster form by a factor of two.
**Corrected: that row is X3 only, and it inverts on the cluster SPU runs on.** On
A715 and A710, `TBL` with 1 or 2 tables is latency 2 at throughput 2 on all `V`
pipes, and 2-table `TBX` is latency 4 at throughput 1. So `TBX2` in `SHUFB`
stays for correctness and is the *slower* form on `CPU5`/`CPU6`. See
[`x86-tricks-arm64-answers.md`](docs/arm64/x86-tricks-arm64-answers.md). And **`USHL` is
the only lowering here stuck on a two-pipe group**; it is used for `inf_shl`/`inf_lshr`
to dodge an LLVM poison-value pessimization, so it is load-bearing, but if a hot block
is shift-heavy that `V13` restriction is where it will show.

| feature | instruction | where |
| --- | --- | --- |
| `asimddp` | `SDOT`/`UDOT` | SPU `SUMB` (9 emitted); SPU `GB` bit-gather via a shift-and-sum constant (31 `sdot`); **and the block-verification accumulate, which is 1,664 of the 1,673 `udot`** |
| `i8mm` | `SMMLA`/`UMMLA` | SPU `GBH`/`GBB` bit-gather, 26 emitted |
| `sha3` | `BCAX` | SPU `EQV`, and both `SHUFB` selector paths |
| — | `TBL`/`TBX`, `TBL2`/`TBX2` | SPU `SHUFB`, `ROTQBY` family, PPU `VPERM` |
| — | `UABD` | SPU `ABSDB` only in principle. **Removed from the block-verification checksum** — `\|a - b\|` is not injective and the checksum decides block identity; see [`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md). After the fix the on-device cache contains **zero** `uabd`, so Eternal Sonata never issues `ABSDB` |
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

   **Set `debug.rpcsx.thor.spu_native_object_cache=1` before that boot.** It is
   **off by default** — `spu_native_object_cache_enabled()`
   (`SPUCommonRecompiler.cpp:307`) needs the property *and* title `BLUS30161` —
   so a boot without it recompiles every program and writes **nothing**. An empty
   `spu-native-v2` then looks exactly like a boot that never reached the SPU
   runtime. `SPU Runtime: Built 1188 functions.` in `RPCSX.log` tells the two
   apart. Cost one full boot on 2026-08-10.

   And disassemble the **old** cache first, before clearing it. Reproducing a
   published count on the pre-change corpus is what proves the pipeline works;
   the `xargs -n 40` failure below returns zero for every mnemonic and reads as a
   perfect result.

When counting, match two-source `tbx v.16b, { v.16b, v.16b }` as well as
two-source `tbl`. Our `SHUFB` path emits `TBX2`; a `tbl`-only sweep reads as a
false negative and cost hours once.

## Test an acceleration theory outside the app first

**Build the theory as a bespoke program, not as a change to the emulator.** The
in-app loop costs about forty minutes for one arm: a native build, an install, a
cooldown to 45 C, a boot, and a settle window. The out-of-app loop costs seconds
to minutes. Use the slow loop to confirm a result on the real workload, never to
find out whether an idea is worth having.

Four checks on 2026-08-13 took minutes each and each one decided something:

| question | what answered it | outcome |
| --- | --- | --- |
| Does our restart-index loop need ARMSX3's NEON? | `clang -S` at the JIT's target, both shapes | **No.** Ours already emits their lane algebra, unrolled twice as wide |
| Does bionic's memcpy go non-temporal for large copies? | `llvm-objdump` over the device's own libc | **No.** `stnp` appears zero times in 146,002 lines |
| Is upstream's FI rewrite bit-identical on our clamp path? | a u32 lane model, 2,005,369 pairs | **Yes.** Zero mismatches, so it was safe to take |
| Is the non-temporal copy's block-and-tail arithmetic right? | a model diffed against `memcpy`, 3,072 cases | **Yes**, and the codegen was read separately |

Three shapes, cheapest first:

1. **Read the codegen.** Feed the construct to NDK clang at the target the JIT
   uses and read the assembly. Answers "what does this compile to", which is most
   of what an instruction-selection theory claims.
2. **Model it.** Reimplement both forms as integer functions and diff them over
   the input space. Answers "are these the same", which is what a rewrite of
   correctness-sensitive code has to prove before it ships.
3. **Run it on the device, outside the emulator.** A static AArch64 binary pushed
   to `/data/local/tmp` and run over `adb`, timed with `cntvct_el0` at 19.2 MHz.
   This repo already did this twice: `CTR_EL0` was read that way, and the AES
   numbers (18.9x on the X3, 9.0x on an A510) came from a kernel run against the
   emulator's own code. No APK, no boot, no thermal gate for a short run.

**And the limits, because this project has been fooled by its own microbenchmarks.**
A bespoke program answers *what does this cost in isolation*. It cannot answer
*is this hot* or *what does it compete with*, and those are what decided nine of
the nine refuted predictions in the ledger. The `BCAX` benchmark is the specific
warning: its chain forwarded inside one region where the real code crosses two, so
the number was real and the inference was wrong. Establish reach first — the
[`fi` count of 399 against 5,794 `shufb`](docs/arm64/codegen.md) came out of the
on-device SPU cache, not out of a benchmark — then bench, then confirm in the app.

## Put the command in a script, not in the shell

**Run tools, not long inline commands.** A measurement typed straight into the
shell cannot be re-run, cannot be reviewed, and cannot be fixed once it is wrong;
the same twenty lines get retyped with one value changed and nobody can say later
which arm used which. Every A/B on 2026-08-13 was inlined that way, and two of the
results were retracted.

Anything with a loop, a retry, or more than about three commands belongs in
`tools/`, where it can carry its own refusals. The scripts here already refuse on
the things that have gone wrong before: an absent property, a device that answers
empty because it is unreachable, an arm that samples the wrong scene, a mode that
prints nothing.

`tools/thor_phase_gated_ab.sh` is the current A/B runner:

    tools/thor_phase_gated_ab.sh debug.rpcsx.thor.spu_branch_extract 0 1 3

It interleaves the arms, proves the property is in the shipped `.so`, waits for
frames rather than a fixed time, accepts an arm only when its frame count lands in
the band, and prints both temperatures.

## The phase gate, and the scatter it does not fix

**A title screen is not one workload.** Folklore has an attract movie and a menu,
and a boot lands in whichever. The identical configuration, launched twice, gave
**185 ticks over 1,750 frames** and **1,720 over 3,500**. Ticks per frame does not
rescue it: 0.106 against 0.491. Accepting only 3,500-frame windows pins the scene.

**And that is not enough.** Inside the band the spread for one fixed setting is
about **50 ticks**, several percent. Two results were claimed and retracted on this
basis within a day:

* the SPU self-loop park, reported as a 14% frame-rate regression, then withdrawn
  when a control pair with identical settings disagreed with itself;
* the SPU branch lane extract, reported as 2.8% less CPU and briefly made the
  default, then withdrawn when a control run put the two settings level with the
  sign flipping between pairs.

So: **read ranges, not means**; interleave arms rather than grouping them, because
the device drifted 12% for identical work as it warmed from 30 C to 68 C over a
session; and treat anything under about 5% as unresolved until there are many more
samples per arm, or a normaliser the change provably cannot touch — the
`spu_getllar_retry` denominator in `lv2-ppu-spin.md` took a 59% spread to 1.1%.

**Measure frames alongside CPU, always.** A CPU number on its own cannot tell a
thread that stopped spinning from an emulator that stopped working. That is what
caught the park's first reading, which looked like a 97% saving.

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
  identical.** This has now cost five times. **The fifth, 2026-08-13:**
  `tools/test_thor_arm64_icache_maintenance.ps1` passed on every run while
  `rpcs3/util/JITASM.cpp` still held the reversed bare `asm("ISB"); asm("DSB ISH")`
  pair at two code-publication sites. The test never listed that file. ARMSX3 found
  both sites, not us, and our green test is what said there was nothing to find. The
  file is in the list now, the list asserts that each path exists, and the test was
  shown to fail against a reconstruction of the defect before it was trusted. The third was a device experiment
  labelled "shader cache cleared" that had cleared nothing: the `mv` failed because
  the cache tree is `drwxr-s---` and denies the group write, while
  `config/custom_configs/` is `drwxrws---` and allows it. The `&&`-guarded success
  `echo` never printed and nobody looked. Confirm the postcondition after the
  command, not the precondition before it. **Re-measured 2026-08-10:**
  `files/cache/cache/` itself is now `drwxrws---`, but every level below it —
  `BLUS30161/`, `ppu-*/`, `spu-native-v2/` — is still `drwxr-s---`, so `shell`
  cannot unlink an object there despite being in `ext_data_rw`. On a debuggable
  build `run-as net.rpcsx.easy` runs as the owning uid and clears it; the proof is
  a re-`ls` reading **0**, never the `rm`'s exit status. `tools/test_thor_arm64_apk.ps1` defaulted
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
- **A cold boot spends about 27 minutes in PPU precompile before the first PPU
  thread exists, so a short settle window measures the precompile and not the
  game.** Measured 2026-08-13 on Folklore with a parked cache: `SYS: Title:` at
  `0:00:03`, and the first `PPU[0x1000000] main_thread` line at **`0:27:01`**. An
  A/B arm with a 240 second settle therefore reported **14.6 CPU-seconds over 254
  seconds**, no `SPU Runtime` line and no PPU threads, and every other check came
  back clean — pid alive, nothing paused, device cool and uncontended.
  **The first diagnosis of that arm was wrong.** It was read as
  `launcher-ui-instead-of-title`, a failure this repo already records, when the
  boot was in fact healthy and simply 27 minutes from starting. The check written
  to catch it — refuse an arm with no `PPU[0x` lines — would have voided **every**
  cold run. `tools/thor_spu_compile_claim_ab.ps1` now separates three states: no
  log at all is an instrument fault, precompile activity with no PPU threads is a
  window that is too short, and neither is a boot that never started. Size a cold
  arm past the precompile, or run it against a warm PPU cache.
- **The vendored core is far newer than its version string says, so do not date it
  from `rpcs3_version.cpp`.** That file reads `0, 0, 36`, and upstream bumped 0.0.36
  on **2025-03-30**. Counting upstream commits from that bump gives "523 commits and
  16 months behind" for the CPU core and RSX, and **that number is wrong**. Checked
  by content instead: upstream's ARM64 change `21d533675` (2026-07-06) is present in
  `SPURecompiler.h:392`, as are `61a260482` (readcyclecounter, 2026-05-14) and
  `320e8d634` (the FCGT/BSL workaround, 2026-05-12). The base carries upstream work
  through **at least 2026-07-06**. This is the version-banner trap above in a second
  costume: date the tree by finding a known commit's code in it, never by a
  constant. And note our direct upstream `RPCSX/rpcsx` is nearly dormant — its
  master's newest commit is **2026-06-06** — so this fork is *ahead* of RPCSX on
  rpcs3 content and takes rpcs3 changes directly.
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

## SUPERSEDED 2026-08-16: Eternal Sonata boots and reaches its title screen

**Observed on device at 21:27, 29.99 FPS at the title screen.** The overlay read
PPU 2.0%, SPU 17.4%, RSX 2.5%, Total 22.0%. The section below describes a
deterministic hang about eight and a half seconds into emulation. That did not
happen. Read the rest of this section as history, and for the SPURS analysis,
which is still the best account of what the stall was.

**Do not credit any one change for this.** The build carried five, and no control
was run:

* the SPURS `cpu_flag::wait` port (`47cff9303`)
* the Adreno fence poll (`28cd69e9e`)
* conditional rendering off on Qualcomm drivers (`489b1845e`)
* the descriptor reserve cut (`cb6a7ab6c`)
* the occlusion query yield (`60d5a5be5`)

**And the baseline is not clean.** Every earlier hang observation on this device
was taken while the app loaded the **dev-core override from 2026-07-17**, not the
core in the APK. See "Prove which binary the device is running". The bundled core
may well have booted this title before any of the five landed. Nobody has run
that arm.

**The control that would settle it:** build the bundled core at `2d7145325`, the
commit before the five, install it, verify `/proc/<pid>/maps`, and boot the same
title. Until then this is "it boots", not "we fixed it".

Two other things the same boot settled:

* **The precompile progress display already exists and is good.** The screen reads
  `Compiling PPU Modules...`, `Progress: file 78 of 78, module 44 of 76`, and a
  remaining time, over a progress bar. A QOL list built from the README claimed
  this was missing. It was wrong, as were four other items on it.
* **Precompile here was about five minutes, not twenty-seven.** Boot at 21:22:25,
  title screen by 21:27. The 27 minute figure in "A cold boot spends about 27
  minutes in PPU precompile" was a colder cache; treat it as an upper bound, not
  the normal case.

## History: the game did not boot before 2026-08-16

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

**Items 0 and 1 need re-testing before anyone works on them.** Eternal Sonata
reached its title screen on 2026-08-16 at 29.99 FPS, so the stall they describe
did not occur in that build. Whether the defect is fixed, or merely not reached,
is unknown: the build carried five changes and the earlier observations were all
taken against the July dev-core override. **Boot Folklore before assuming the
SPURS analysis below still describes live behaviour.** Full note at the top of
this file.

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
| **SPU block-verification checksum** | **fixed, confirmed on device** | the ARM64 path folded half of every 96-byte block through `UABD`, and `\|a - b\|` is not injective — a uniform delta across a pair collides, so the verifier could accept the wrong cached block. Inherited from **upstream RPCS3 master**; fix (sum the pairs) taken from ARMSX3. Cleared cache, cold boot, re-disassembled 2026-08-10: `uaba` **4,503 → 0** and `uabd` **910 → 0** of **509,424** instructions, `add` +9,587. Title boots and holds 30 FPS |
| `BufferUtils.cpp` | **ported, unmeasured** | `copy_data_swap_u32` had 11 x86 gates and no ARM64 form, so it fell through to a scalar loop behind a non-inlinable function pointer with LTO off. `copy_data_swap_u32_neon` ported from ARMSX3. **No device measurement**; our profile puts the whole vertex/buffer cluster near 0.2% |
| `BufferUtils.cpp`, restart path | **clean, verified** | ARMSX3 hand-wrote NEON for the primitive-restart index upload, saying clang cannot vectorize it. True of upstream's conditional shape, false of ours: the branch-free rewrite here compiles to `rev16`/`cmeq`/`orr`/`bic`/`umin`/`umax`/`uminv`/`umaxv` — their exact lane algebra — unrolled to two `q` registers per iteration, so it is twice as wide as their kernel. Upstream's shape emits four `csel` and no vector instruction. Read at `-O2 -march=armv8.4-a -mtune=cortex-a715`, not assumed |
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
| [`docs/arm64/x86-tricks-arm64-answers.md`](docs/arm64/x86-tricks-arm64-answers.md) | **The seven x86 instructions RPCS3 abuses for SPU work, answered for AArch64.** None of the seven is a candidate; together they are 0.04% of emitted code. It corrects two claims in this file: **1,664 of the 1,673 `udot` are the block-verification accumulate, not `SUMB` or `GB`**, and **`TBX` does not beat `TBL` on A715/A710**. The real candidate it found is the SPU branch lowering, which builds a 16-bit movemask at 1,402 sites to test one bit. **That candidate now passes check 1: LLVM keeps the lane extract (8 instructions against 2), and the two spellings compute the same predicate. The lane extract now ships at all eight opcodes behind `debug.rpcsx.thor.spu_branch_extract`, default 0, so nothing changes by default. The reach is still unmeasured, and only 786 of the 1,402 sites are attributed.** |
| [`docs/arm64/bench-results.md`](docs/arm64/bench-results.md) | **Measured on the silicon, outside the emulator, 2026-08-13.** **And a warning about the in-app arms: every one of them is void.** A control pair with identical settings gave 185 ticks over 1,750 frames and 1,720 over 3,500, so Folklore's title screen has phases and a boot lands in one of them. Run a control pair that agrees with itself before believing any arm on a title. `YIELD` is exactly a `nop` (0.36 ns, same as a load); `ISB` is 11.42 ns, which is the arithmetic behind the +23% regression. A futex park costs **~10 us** of wake latency against 0.44 us for a spin, which sizes the SPU self-loop park at 0.06% of a frame. **`TBX2` costs 2.1x the throughput of `TBL2` on the A715 and A710** — and `SHUFB`, the most common operation in the corpus at 5,794, emits `TBX2`. The non-temporal copy is only **3.1% faster at 16 KB**. And **CPU5 and CPU7 refuse an exclusive pin while the device is idle** — Qualcomm `core_ctl` pauses them, so they read `online=1` and still reject affinity. Load the machine and the same pin succeeds, so the placement advice stands; the trap is that **a light benchmark cannot measure the prime core**. |
| [`docs/arm64/microarchitecture.md`](docs/arm64/microarchitecture.md) | What the hardware does: instruction latency, throughput and pipe assignment from the vendored per-core guides, the forwarding regions, and the chapter 4 rules. |
| [`docs/arm64/memory-model.md`](docs/arm64/memory-model.md) | Atomics and ordering: the LSE2 128-bit path (no longer dead — see below), the reservation seqlock, RCsc versus RCpc, and instruction-cache maintenance. |
| [`docs/arm64/lv2-ppu-spin.md`](docs/arm64/lv2-ppu-spin.md) | **The largest finding here, and the only one from a real profile.** 73.9% of all cycles are a nop-spin in two lv2 wait syscalls; the same loop appears at eight sites across the guest sync layer. |
| [`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md) | **What the SPU JIT actually emits**, disassembled from the on-device cache: 1,185 objects, 509,468 instructions. `udot` at 1,661 was read as proof the video's optimization is taken. **Corrected:** 1,664 of the 1,673 post-fix `udot` are the **block-verification accumulate**; `SUMB` emits **9**. The largest visible cost is stack traffic — `sp` is the second hottest base register, 10.1% of all instructions. |
| [`docs/arm64/armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) | **ARMSX3 diffed against upstream RPCS3**, so their work is separated from what they inherited. **The one correctness item in the first pass was ours too** — the SPU checksum's non-injective `UABD` fold, now fixed here. **Second pass, 2026-08-13, against their `e10f846`:** diff from the fork point (`652cf60bf`) instead of from master, which attributes all 210 commits exactly. **It retracts two claims:** they reverted `thread_scheduler_mode::alt` after measuring six SPU threads on four cores, and they put the GETLLAR busy-wait percentage back to upstream's 100. Four things ported: the same-item SPU compile race, two remaining JIT i-cache sites, the GETLLAR out-buffer memo and cap, and a memory budget for the PPU compile workers. One rejected after checking: their NEON index upload, because our branch-free loop already compiles to the same kernel, unrolled twice as wide. |
| [`docs/arm64/three-way-audit.md`](docs/arm64/three-way-audit.md) | **The second pass of the three-way method**, over the six files the gameplay profile makes hot. One correctness item: the SPU **ubertrampoline** reaches other cores with **no instruction cache maintenance** in our tree and in upstream, and ARMSX3 flushes it. Two defects live in the other two trees and are already fixed here: PPU `FCTIW`/`FCTID` and SPU `CFLTS`/`CFLTU` apply an **x86 saturation correction on AArch64**, which turns a correct value into the wrong one. No second non-injective fold exists, and no dead ARM branch exists in the hot files. |
| [`docs/arm64/busy-wait-inventory.md`](docs/arm64/busy-wait-inventory.md) | **Every `busy_wait` site with its real duration in µs**, computable statically because `get_tsc` is `cntvct_el0` at 19.2 MHz. Six sites pass no argument and so took the x86 default of 3000 — 156 µs each — and could not have been part of the hand-retune. `shared_mutex` spins **1.56 ms** in front of a working futex. |
| [`docs/arm64/spin.md`](docs/arm64/spin.md) | Where the CPU time goes *on the SPU side*: 93% of instrumented spin is the `GETLLAR` wait. Read `lv2-ppu-spin.md` first — that 93% is a share of the sites the wait profiler counts, and it counts no PPU sites. |
| [`docs/arm64/rsx-boot-hang.md`](docs/arm64/rsx-boot-hang.md) | **Resolved.** The boot hang, three wrong diagnoses, and the empty `mov_rdata` branch behind it. Folklore now reaches its title screen at 60.01 FPS. |
| [`docs/arm64/uma-bar-heap.md`](docs/arm64/uma-bar-heap.md) | Snapdragon is UMA, so the "BAR heap" the Vulkan backend parks as scarce is all 11.4 GB of it. What is measured and what is not. |
| [`docs/arm64/ppu-compile-oom.md`](docs/arm64/ppu-compile-oom.md) | A second title dies in PPU precompile with a Scudo out-of-memory, and why the 1536 MB budget bounds concurrency rather than footprint. |
| [`docs/arm64/aes.md`](docs/arm64/aes.md) | AES-NI is x86-gated, so every module decrypted at boot uses software AES on a chip with AES instructions — plus three related checks that came back negative. |
| [`docs/arm64/x86-isms-sweep.md`](docs/arm64/x86-isms-sweep.md) | Every remaining `_mm_*` site outside 3rdparty, asked "is this executed?" before "is this optimal?" — and why the interpreters, which look like the biggest target, are not. |
| [`docs/arm64/rosetta-lessons.md`](docs/arm64/rosetta-lessons.md) | What Rosetta 2 does and why its central problem — x86's TSO — does not exist here, plus the four techniques it is famous for that this codebase already has. |
| [`docs/arm64/adreno-tiler.md`](docs/arm64/adreno-tiler.md) | **The one place the code is still written for the wrong hardware.** Every render pass unresolves and resolves both attachments, and `LOAD_OP_CLEAR` is used zero times. |
| [`docs/arm64/instruments.md`](docs/arm64/instruments.md) | The measuring tools, what each can and cannot answer, and the mistakes made building them. **Frame timing: `dumpsys SurfaceFlinger --latency` on the `(BLAST)` layer gives per-frame present timestamps — a real distribution, no build flag, no code.** |
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


# ARMSX3 0.8 and upstream RPCS3, third pass, 2026-08-16

ARMSX3 is at `62d8208c7`, release **0.8** of 2026-08-15. That is **27 commits**
after `e10f846`, which the second pass in
[`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) used. Upstream RPCS3 is
at `ffc50905a`.

**Nothing below is ported, and nothing below is measured on the device.** Each
item says what was checked and how.

## The `cortex-a78` pin now has a second reason

ARMSX3 vendored an LLVM patch, `3rdparty/llvm/armsx3-aarch64-ghc-emergency-spill.patch`
(`b5a715adc`). AArch64 `determineCalleeSaves` returns early for
`CallingConv::GHC`, so a GHC function never gets a scavenging frame index. That
is safe only while GHC functions have no frame. When the allocator spills, the
function gets real stack objects, `eliminateFrameIndex` needs a scratch register
to build an offset, and GHC has reserved nearly every GPR. LLVM then aborts the
whole module with `Cannot scavenge register without an emergency spill slot`.
The PPU recompiler emits `ghccc` for every guest function, so one bad function
costs the module, and its functions fall back to an interpreter loop.

Their note records the trigger set exactly. It needs `ghccc`, **and** `-O2`,
**and** a scheduling model that pushes pressure over the line. It reproduces on
`cortex-x1`, `cortex-x2`, `cortex-x3` and `cortex-a55`. It does **not** reproduce
on `cortex-a76`, `cortex-a78` or `generic`.

**This fork pins `cpu=cortex-a78`, so it is on the safe side of that list.** The
pin now carries two load-bearing reasons: SVE codegen, recorded above, and this.
Anyone who changes the LLVM CPU name inherits both. Do not port the patch while
the target stays `cortex-a78`; do read this row before changing the target.

## The event stream already bounds `WFE` here, and nothing checks it

`rx::wait_for_event()` at `rx/include/rx/asm.hpp:474` emits `sevl / wfe / wfe`,
and the comment above it records a **measured park of 72,024 ns** set by the
architected event stream at about 100 µs. So the video table's `FEAT_WFxT` row is
correct about a *programmable per-wait timeout* and wrong if anybody reads it as
"`WFE` cannot be bounded here". The event stream is the bound, and this fork
measured it.

**The premise is unchecked.** `rx/asm.hpp` states that Linux and Android arm the
stream. `HWCAP_EVTSTRM` appears **nowhere** in `rpcs3/util/sysinfo.cpp`, whose
`getauxval` family covers `ASIMD`, `SHA3`, `ASIMDDP`, `I8MM`, `SVE` and `SVE2`.
ARMSX3 added `utils::has_wfe_event_stream()` for exactly this (`5ef731c9e`), and
records that the stream is a kernel property and not an architectural guarantee.
On Thor the stream is on — `evtstrm` is in the cpuinfo list in "The machine" — so
the premise holds on this device, and it is untested on any other.

And the fork does not depend on the stream today. The one call site,
`RSXFIFO.cpp:751`, sits behind `thor_rsx_fifo_park_enabled()`
(`debug.rpcsx.thor.rsx_fifo_park`), which is **default 0 and unmeasured**.

## ARMSX3 hardened the RSX semaphore wait; ours is still the plain spin

The site is `nv406e::semaphore_acquire`. Ours calls
`rx::spin_on_cacheline_once(sema, sema.load(), 100)` at `nv406e.cpp:94`. Theirs
spins 500 iterations, then falls back to `wait_for_event()` (`002a9b274`,
hardened twice afterwards at `5ef731c9e` and `b29810d1a`).

**Check the premise before porting this.** Their stated cause is **Oryon**, the
Snapdragon 8 Elite class, where `WFE` returns immediately while the exclusive
monitor is armed. The armed wait degrades to a spin there at tens of millions of
iterations per second. **This device is 8 Gen 2, not Oryon**, and `asm.hpp:461`
already measures an armed `WFE` parking for 72 µs on it. The defect they fixed
may not exist on this chip.

This is the `busy_wait` trap in a new costume: a fix aimed at another core class,
taken without asking whether this core has the problem. Two fixes for one problem
multiply, and that one dropped Thor to about 1 FPS.

## Two upstream ARM64 commits are absent, checked by content

Dated by finding the code, never by `rpcs3_version.cpp`:

| commit | date | what it adds | evidence it is absent |
| --- | --- | --- | --- |
| `5e8ba021a` | 2026-07-26 | SPU/ARM64 RawSPU MMIO, 403 lines: `GPR(context, index)` accessors and `decode_a64_mem_inst` | our `rpcs3/util/Thread.cpp:1215-1227` defines `RIP` only, and has no `GPR` macro |
| `d7ed328f4` | 2026-08-01 | `vm::writer_lock` deadlock fix: sets `cpu_flag::wait` across the `hack_alloc` recovery paths | our `hack_alloc` at `Thread.cpp:1481` has no `added_flag` |

The file is the right one in both cases: it holds `handle_access_violation` at
1237 and `hack_alloc` at 1481. `vm::writer_lock` is **4.49%** of the gameplay
profile and one of the four spin layers, so the second row is worth reading.

**Already present, so nobody re-ports it:** `b35e4434a`, "SPU LLVM: Add
`spu_thread::state` check in Reduced Loop", is at `SPULLVMRecompiler.cpp:2779-2783`.
It is adapted to the RPCSX `spu_ptr<u32>(OFFSET_OF(...))` idiom, which is why a
search for upstream's exact text misses it.

## One of the three-way audit's defects is now closed on their side

[`three-way-audit.md`](docs/arm64/three-way-audit.md) records the x86
float-to-int saturation correction, applied on AArch64, as a defect that lives in
the other two trees and is fixed here. ARMSX3 fixed the PPU half on 2026-08-13
(`87ccdb851`). Nothing to port. Narrow that row to upstream RPCS3.

## Do not port 0.7-era renderer work

ARMSX3 shipped a new renderer in 0.7 and reverted it in 0.7.1 on the same day
(`4797ad8a9`, `8ee20d91d`). They then returned to the 0.6 path and kept only the
FIFO idle fix and ADPF (`0819f1ef1`). Read that sequence before taking any VK
commit from the 0.7 range.

## Read but not yet examined

Listed so the next pass resumes rather than restarts:

* `dbbb6fbde` — VK extended dynamic state, to collapse pipeline permutations.
* `b82432c79` — native fp16 on Adreno drivers that accept it. It **deletes** 203
  lines of `device.cpp`.
* `d069a55ac` and `614bf8b71` — a lost surface becomes recoverable, and Android
  re-delivers the Surface. These aim at the README's "launching a second game
  after closing the first can fail".
* `cce09dbb3` — SPU recovers from a failed analysis, and the log floods stop.
* `7f54855b7` — an lv2/vm read-only unlink lockup, and three log floods.

# `_rpcsx_surfaceEvent` leaks an ANativeWindow reference, and that blocks a fix

**Found by reading, on 2026-08-17, while porting ARMSX3's Surface re-delivery.
Not yet fixed, because the fix cannot be validated without the device.**

`ANativeWindow_fromSurface` **returns a reference the caller owns** and must
release. `_rpcsx_surfaceEvent` treats it as borrowed:

```cpp
auto newWindow = ANativeWindow_fromSurface(env, surface);   // ref 1, owned by us
auto prevWindow = g_native_window.exchange(newWindow);
if (newWindow != prevWindow) {
    ANativeWindow_acquire(newWindow);                        // ref 2
    if (prevWindow) ANativeWindow_release(prevWindow);       // releases prev once
}
```

Both paths leak. A **different** window ends holding two references where one is
released later, and an **identical** window skips the block entirely while the
`fromSurface` reference is never dropped at all.

Today it is bounded, because the surface changes rarely.

**It is what stops the real fix.** `SurfaceHolder.Callback::surfaceChanged` is a
one-shot: Android delivers it on create or resize and never repeats it. A single
missed delivery parks `getNativeWindow()` forever, which is a black game area at
~0% CPU for the rest of the session, and rotating the device only appears to fix
it because a configuration change forces a fresh `surfaceChanged`. ARMSX3 fixes
this by **re-delivering the surface on attach and on every window visibility
change** (`614bf8b71`), relying on the native side to no-op when the window
matches.

On this tree that no-op is the leaking path, so the fix would leak a window
reference **per delivery** instead of once per session.

**Order of work: fix the refcounting first, then port the re-delivery.** The
correct shape is to let `g_native_window` own the `fromSurface` reference, drop
the extra `acquire`, and release the incoming reference when the window is
unchanged. That is a lifetime change on the render surface, where a mistake is a
use-after-free rather than a leak, so it wants a device and a
rotate/background/resume cycle before it is trusted.

The diagnostic half is already in: the wait loop now says
`Still waiting for a Surface after N ms` every three seconds, so the silent
version of this failure cannot recur.

# The syscall log flood was the UE3 slowness, and it is measured

**449,180 RPCS3 lines in one logcat buffer**, taken while Transformers ran its
Unreal Engine 3 HD-cache install. On Android a log line is a syscall plus IPC, and
this install is thousands of file operations back to back, so the logging cost
more than the work it described.

| lines | message |
| --- | --- |
| 119,107 | `Failed to lock sudo memory` |
| 119,083 | `sys_memory_allocate` |
| 118,789 | `sys_memory_free` |
| 31,743 | `sys_fs_stat` |
| 8,846 | `sys_fs_close` |
| 8,203 | `sys_fs_open` |
| 4,434 | `sys_fs_unlink` |
| 2,191 | `sys_fs_rename` |

All demoted to trace, or reported once per session for `lock_sudo`. **Measured
after: 1,836 lines over three minutes** of boot and install on Transformers: War
for Cybertron, which reached its title screen at 24.80 FPS with no `Fatal signal`
and no Scudo OOM at 459% CPU.

**Two traps in doing this.** Allocation and free come in pairs, and so do open and
close: the first pass fixed one side of each and halved the flood rather than
stopping it. And `sys_fs_close` builds its string under `if (sys_fs.warning)` and
prints later, so the GATE has to move with the level - leaving it would pay
`fmt::format` on every close and print nothing.

**Do not port ARMSX3's flood list and stop.** Their four (`sys_fs_utime`,
`sys_fs_fcntl`, `sys_mmapper` map/unmap, `vm::lock_sudo`) contained **none** of
this tree's top four. The floods that matter here had to be counted here.

## Open: 436 `sys_memory_free` failures in three minutes

With the floods gone, the largest remaining entry is
`'sys_memory_free' failed with CELL_EINVAL`, 436 of them in three minutes.

`sys_memory_free` returns `CELL_EINVAL` when the address is not 64 KB aligned, or
when `sys_memory_address_table.addrs[addr >> 16]` holds nothing. The two internal
callers in `sys_memory.cpp` free an address they have just registered, so they
cannot be the source - this is the **guest** freeing addresses the table does not
know about.

Benign engine behaviour or a tracking bug is undecided, and it cannot be decided
from the code: it needs the addresses logged and checked against what was
allocated. Do not "fix" it before that.

# What the log-flood fix is actually worth, measured both ways

**Built the pre-flood commit (9b48b5130) and the fixed tree, installed each, and
booted Transformers: War for Cybertron from the same ISO to the same title screen,
sampling at the same offset (~t+290 s), screen awake, back to back.**

| | baseline | fixed |
| --- | --- | --- |
| RPCS3 log lines at t+290 s | **19,848** | **2,060** |
| guest CPU total | 50.7% | 50.0% |
| PPU / SPU / RSX | 10.1 / 37.2 / 3.3 | 9.9 / 36.9 / 3.2 |
| host CPU, 5 samples | 371 437 407 448 492 | 425 388 429 462 489 |
| FPS, single sample | 29.69 | 30.49 |

**The log reduction is real and large: 9.6x at the same point.** The CPU figures
are identical within noise.

**The FPS difference is NOT a result.** Three further samples of the fixed arm ten
seconds apart gave **27.23** with guest CPU at 72.6%, so that arm alone spans
27.23-30.49. The title screen animates - the planet rotates and debris moves - so
it is not a steady scene, and the 29.69 vs 30.49 gap sits inside one arm's own
range. Reporting it as +2.7% would have been the retraction pattern this file
already records twice.

**So: the fix removes 90% of the log volume at zero CPU cost, and does not move
frame rate on a post-install title screen.** That is consistent with where the
flood actually was - the 449,180-line buffer was captured during the UE3 HD-cache
INSTALL, which is thousands of file operations back to back and happens once. The
user's report of the title being unusably slow was during that phase.

**What would resolve a frame-rate claim:** Folklore, per the ledger, and the phase
gate - accept only 3,500-frame windows, interleave the arms, and read ranges
rather than single samples. A capped, animated title screen cannot answer it.

# A Thor with its screen off cannot boot a title

**Measured 2026-08-18, and it cost most of an A/B session.** A scripted boot sat
at 3.7% CPU with the renderer reporting
`Still waiting for a Surface after 534000 ms`. Nothing was wrong with the
emulator. The device had gone to sleep during a long adb session, so the window
was never laid out, and `dumpsys activity top` showed it plainly:

    net.rpcsx.GraphicsFrame{... 0,0-0,0 app:id/surfaceView}

A `SurfaceView` measured 0x0 never creates a surface, so `surfaceChanged` never
fires and `getNativeWindow()` blocks for the rest of the session.

**Before that log line existed this was indistinguishable from a hang** - black
screen, no output, and a plausible story about a missed one-shot delivery ready to
be believed. Check the display before diagnosing anything:

    adb shell dumpsys power | grep mWakefulness=
    adb shell svc power stayon true     # before any unattended arm

# Eternal Sonata's opening cutscene cannot resolve an A/B

Ten consecutive CPU samples of ONE arm, thirty seconds, no setting changed:

    503 496 518 111 159 148 151 144 185 129

That is 1.1 to 5.2 cores busy within a single arm. The cutscene has phases, and
the phase decides the number. This is the same wall the ledger already records -
"Eternal Sonata CPU cannot resolve anything below ~1.4 cores" - reached from a
different direction, and it rules the cutscene out as an A/B scene entirely.

**Use Folklore.** The ledger says it resolves 0.005 cores and is the title to A/B
on, and nothing since has contradicted that. A number taken from an Eternal Sonata
cutscene is noise wearing a result's clothes, which is how two findings were
retracted here in one day.

# Diagnosing a boot: what the log will and will not tell you

**A failed boot used to report its reason to a dialog and nowhere else.**
`RPCSXActivity` called `RPCSX.boot()` and, on failure, showed an AlertDialog and
called `finish()`. Over adb that is indistinguishable from a hang: the activity
starts, the surface is created and destroyed inside 50 ms, and the log holds three
surface events and nothing else.

That cost a session on 2026-08-17. Three titles were read as "boot accepted but
silently does nothing", and a Surface delivery bug was hunted that did not exist.
The result is logged now, success and failure both, so the first line of a capture
answers "did it boot".

**Two harness facts worth knowing before scripting a boot:**

* `THOR_DEBUG_BOOT` with `--ez thorRequireManagedProfile true` **refuses any title
  without a recommended settings profile**. Eternal Sonata has one; Transformers,
  Tales of Symphonia and BLUS30126 do not. Pass `false` for a diagnostic boot, and
  read the accept or reject line before believing anything that follows.
* `MSYS_NO_PATHCONV=1` fixes Git Bash rewriting **device** paths, and breaks
  **local** ones in the same command. `adb install` needs a Windows path for the
  APK while `adb shell` needs the guard for `/storage/...`. Scope it, do not export
  it for the whole script.

# 8.3 GB of installed data had no library entry at all

`dev_hdd0/game` on this device, 2026-08-18:

    BLUS30357  4.6 GB     BLUS30126  3.7 GB
    BLUS31172_INSTALL_TOSRATATOSK  1.5 GB     BCUS98147  30 MB

**BLUS30357 and BLUS30126 are not in `games.json`.** Their 8.3 GB is orphaned: no
library entry, and deleting a game never touched it anyway - that path removes
`game.info.path` when app managed, plus `cache/cache/<titleId>`, which is only the
compile cache.

For a disc game these are simply different places. The title writes to the virtual
hard disk while it runs; the library entry is the ISO. Drawer > **Installed game
data** lists them with sizes and deletes one on confirmation. Saves are not in
there - those are `dev_hdd0/home/<user>/savedata` - so a delete costs a reinstall
and cannot lose a save.

Not everything under that folder is a title: `$locks` is emulator bookkeeping.
Entries whose name does not begin with a title id are listed without a Delete
button. The test is a **prefix**, because `BLUS31172_INSTALL_TOSRATATOSK` is real
game data.

# The upstream texture series of 2026-08-14..17, and why almost none of it is ours

Upstream landed 16 commits on the RSX texture cache, `ffc50905a..f9f88aa9e`, 511
insertions over 12 files. It was reported as a GPU improvement. **Three commits
came here. The rest should not, and this section is why, so nobody re-derives it.**

## Taken (`bf60895ea`)

* `f9f88aa9e` — a real bug. `uvec4(floor(...))` on a **negative** float is
  undefined, and `round_to_8bit()` feeds it an `fma` result that can go negative.
  Both the fp32 and the native fp16 forms are fixed. Per fragment, and `max()` is
  free next to what surrounds it.
* `26782525f` — depth shrinks with every mip level. This tree used the base depth
  for every level, so `get_texture_size()` overstated every mipmapped 3D texture.
* `5e2d0eb76` — border texels pad the mip dimensions. **Order matters**: this was
  written on top of `26782525f`, and taking it alone against this tree's older
  base would compute the wrong size. They go together.

## Not taken: the performance half has no reach here

The performance work is host-side mipmap scanning for 3D textures (`7e35f5999`,
191 lines) and the one-line commit that enables its fast path (`107b751a4`). It
runs only for a texture that is **both 3D and mipmapped**.

`debug.rpcsx.thor.tex3d_reach` measured it. Eternal Sonata, title screen and
menus, 2,700 frames:

    total=12950  3d=0  3d_mipmapped=0  cubemap_mipmapped=0

**Not one 3D texture in 12,950 uploads.** Gameplay is still unsampled; if it
agrees, this half is inert on this title.

`970d74581` looks general from its title — "respect mip levels actually used" —
and is not. Its only call sites are `generate_cubemap_from_images` and
`generate_3d_from_2d_images`, so the same two counters cover it, and both read 0.

## Not taken: two "general fixes" repair a feature this tree does not have

`4475671bb` lets `process_framebuffer_resource_fast` take an offset. Two later
commits then fix what that broke:

* `9a4b84926` scales the offset when src and dst bpp mismatch.
* `6f5f198ac` adds a cyclic-ref check "since we now allow offsets".

This tree's call site passes **no offset at all**, and `scaled_offset` appears
zero times in its `texture_cache_helpers.h`. It also already performs the
cyclic-ref barrier those commits restore. **Predating the feature means predating
its bugs.** Porting either one would be meaningless at best.

## The porting cost, if the reach answer ever changes

A trial 3-way merge resolves to 40 conflicts over five files, which reads as
tractable and is not. A partial application failed to build with **102 errors of a
different kind**: 50 `cannot initialize object parameter of type rsx::thread`, 18
`override hides virtual member function`, 16 `vk::texture_cache is an abstract
class`. Upstream changed the texture cache's **virtual interface**, so files with
no conflicts at all stop compiling. It is a cross-cutting refactor of the VK
backend, and it collides with this fork's `can_sample_linear` logic in
`VKDraw.cpp`, where there is no side to pick.

**Conflict count does not see interface changes.** That is the lesson worth
keeping.

# `rsx_log.always()` does not reach logcat. `rsx_log.error()` does.

**Measured 2026-08-17, and it cost a build and a boot.** A new counter logged
through `rsx_log.always()` printed **nothing** across 20,750 frames, while the
property it was gated on read `1` and the string was confirmed present in the
shipped `.so`. Every static check passed and the instrument was silent.

Switching the same line to `rsx_log.error()` made it print immediately, on the
first frame.

`always` is level 0 in `util/logs.hpp`, commented "cannot be disabled", so the
header says it is the *most* visible channel. On this device's Android log sink it
is the least. Do not reason from the enum.

**Use `rsx_log.error()` for anything you intend to read back over `adb`**, which
is what `thor_rsx_auditor` already does - and that working precedent was sitting
in the tree the whole time.

This is the `vm_log` entry in a new costume, and the cost was the same shape: a
silent instrument was nearly read as a zero result. The one-shot unconditional
log is what separated them, and it should have been the first move:

    static bool s_reported_once = false;
    if (!s_reported_once) { s_reported_once = true; rsx_log.error("alive: gate=%d", gate); }

Put it OUTSIDE the gate, so a false gate cannot silence the message that reports
the gate.

# Prove which binary the device is running, before you measure anything

**The app can load a dev-core override instead of the core in the APK.**
`files/dev-core/active-core.json` names a library, and the app loads that one.
An `adb install` then changes nothing that runs.

On 2026-08-16 this cost a full boot. The override pinned a 1.35 GB library from
**2026-07-17**, built from a different working copy
(`Documents\New project 6\rpcsx-ui-android\`). A freshly built APK was installed
and verified by `lastUpdateTime`, the title was booted, and the result was read
as evidence about a change that never executed.

`lastUpdateTime` proves the APK arrived. It does not prove the core ran. Only one
thing does:

```sh
adb shell run-as net.rpcsx.easy cat /proc/<pid>/maps | grep librpcsx-android
```

The bundled core answers `/data/app/.../lib/arm64/librpcsx-android.so`. An
override answers `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`.
**Read that line before the run, not after it.**

To disable an override without destroying it, rename `active-core.path` and
`active-core.json`. `tools/build_push_thor_core.ps1 -ResetToBundled` also deletes
the library itself, which is not recoverable if the checkout that built it has
moved on.

This is the version-banner trap in a third costume. The banner lied about the
build, a property can be absent from the `.so`, and now the whole library can be
the wrong one.

# ADPF is written, gated at runtime, and compiled out

`thor_adpf_rsx_hint.h` is complete. It dlsym's the `APerformanceHint_*` family,
gives ADPF a real 30 FPS deadline for Eternal Sonata, and reports the miss signal
as well as the headroom signal. When it is compiled in it reads
`debug.rpcsx.thor.adpf_rsx` and **defaults to off**, so the property alone
decides.

It is not compiled in. `CMakeLists.txt:19` defaults `RPCSX_THOR_ADPF_RSX_HINT` to
`OFF`, and `build.gradle.kts:219` passes that default explicitly.

**That last part is the cost.** The flag is always in the CMake argument list, so
turning it on changes the argument string, which changes the `app/.cxx` hash, which
means **a fresh 8-11 GB tree and a full native rebuild** - not a re-link. Budget
for that before flipping `-PrpcsxThorAdpfRsxHint=1`, and read the disk warning in
"Every distinct CMake flag combination costs 8-11 GB" first.

Worth doing once, because after that build the experiment is one property and no
rebuild. ARMSX3 shipped ADPF and kept it through a full renderer revert, which is
weak evidence that it earns its place. Unmeasured here.

# Build the probe, do not take the number

**A number from outside this repo is a reason to test, never a result.** ARMSX3
measures on their device, upstream measures on x86, and a vendor manual measures
nothing at all. Nine of nine manual-derived predictions here were refuted.

**Write the throwaway program. It is cheap and it is allowed.** The precedent is
already in `tools/`: `bench/thor_bench.cpp`, `aes_arm64_bench.cpp`,
`bcax_bench.c`, `read_ctr_el0.c`, `rdata_equiv.c`. Results go in
[`bench-results.md`](docs/arm64/bench-results.md).

Three shapes, cheapest first, all covered in "Test an acceleration theory outside
the app first" above: read the codegen, model the two forms and diff them, or run
a static binary on the device. None of them needs an APK, a boot, or a thermal
gate.

**Two open questions that each want one small program:**

* Does `vkGetFenceStatus` really block on Turnip and Adreno 740? A commit already
  landed on ARMSX3's 14.6 ms figure. One Vulkan binary that times the call
  against an unsignalled fence settles it, and refutes the commit if they are
  wrong about this driver.
* Is SVE truly absent, or only unreported? `HWCAP` and the JIT log agree it is
  absent, and Qualcomm disabled SVE2 across this generation. A static binary that
  executes one SVE instruction under a `SIGILL` handler turns that into proof.

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

**And `VK_QCOM_tile_memory_heap` is closed for a better reason than the driver:
it requires Adreno 840 or newer, and this is an Adreno 740.** Explicit GMEM
allocation is therefore unobtainable on this device by *any* driver — not another
Turnip build, not Qualcomm's proprietary one. Do not go looking; there is nothing
to find. Implicit GMEM already works (Turnip bins and tiles on A6xx/A7xx/A8xx),
and the portable substitute below needs no extension at all.

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
5. **Read the temperature before an arm, and treat a hot device as somebody else's
   run until proved otherwise.** On 2026-08-13 a harness waited to start and watched
   the cores go **47 C to 95 C** without ever launching the emulator. The other
   session had taken the device: Xenia sat at **174-211% CPU**, relaunching on a
   cycle, its memory climbing to 1.0 GB. Any arm taken then measures throttling and
   contention. `tools/thor_spu_compile_claim_ab.ps1` now refuses on both counts, and
   `tools/thor_wait_then_compile_claim_ab.ps1` waits for the device instead of
   competing for it. **Do not force-stop their package**, and do not lower the
   thermal gate to make a run start.
6. **Installing an APK is itself a heat source.** The same device read 38.5 C before
   an install and 50.2 C right after it. That is a transient, like the launch spike
   in `thermal.md`. Poll for the cooldown; do not conclude the device is hot.

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
| 54:24 | Optimizing via hardware wait instructions | `WFE` explored (three experiments, [`spin.md`](docs/arm64/spin.md)); `FEAT_WFxT` absent on this chip so `WFE` cannot carry a *programmable per-wait* timeout. **It is still bounded**: `rx/asm.hpp:474` measures an armed `WFE` parking **72,024 ns**, set by the architected event stream. See the third ARMSX3 pass below |
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

# Where this stands, and the one thing left to build

Everything cheap has been tried. The scoreboard:

| lead | outcome |
| --- | --- |
| lv2 wait spin | **fixed and shipped** — default `lv2_spin=0`, 67.6% CPU cut on a light scene, no latency cost at any percentile |
| `host_mutex_spin` | measured 2.2% on Folklore, ~1% of the lv2 win — **default left at 10** |
| `SPU loop detection: true` | **null** — and consistent with the profile, since the hot loop polls `state`, not a channel |
| SPU affinity widening | **null, and the config block is inert** — see the retraction below |
| ARMSX3 second pass, 2026-08-13 | **four ported, none measured** — the same-item SPU compile claim, two JIT i-cache sites, the GETLLAR out-buffer memo and cap, and a memory budget for the PPU compile workers. The APK is installed and the device was then taken by the other session. See [`armsx3-comparison.md`](docs/arm64/armsx3-comparison.md) |
| ARMSX3 third pass, 2026-08-16 | **read, none ported** — 27 commits to release 0.8. The `cortex-a78` pin dodges their LLVM GHC scavenger defect; their RSX semaphore fallback targets Oryon, not 8 Gen 2; two upstream ARM64 commits confirmed absent here. Section above |
| `PMULL` for texture swizzle | correct technique, **cold** — `calculate_z_index` absent from the profile at any threshold |
| exclusive monitor as reservation | **half-viable** — `ERG=64` measured, PS3 needs 128 |
| ARM TME, SVE | **absent from this chip** |

**BUILT 2026-08-13, default off, and unmeasured.** `debug.rpcsx.thor.spu_selfloop_park`
takes the timeout in microseconds; `0`, the default, keeps the spin. `BR` now has a
case for `target == m_pos` and calls `spu_selfloop_park`, which parks on `state`
with that timeout. The record is written **on entry** — `entries`, `last_pc`, then
`exits` — so a watchdog reading `entries - exits > 0` sees a park while it is
happening. That is the record-on-entry slot this file asks for below, and it exists
because parking turns a burning core into a quiet sleeping thread, which is what a
guest deadlock would then look like. See `Emu/Cell/thor_spu_selfloop_park.h`. The
paragraph below is the design it was built from, and it still describes the problem.

**What remains is the SPU self-loop park, and there is no shortcut left to it.**
Roughly 20% of gameplay CPU sits in two instructions — `ldr w8,[x19,#0x14]` /
`cbz w8, .-4` — that spin on `spu_thread::state` with no pause, no yield and no
backoff.

Everything needed to build it is now known:

* **Site:** `SPULLVMRecompiler.cpp:9874`, `BR`, which has no case for
  `target == m_pos`. Detection needs no dataflow analysis.
* **API:** `thread_ctrl::wait_on(state, old, timeout_ns)`, with precedent in the
  same file at `SPUThread.cpp:7907`.
* **Emitting the call:** the `call("name", +lambda, m_thread, ...)` helper, as
  `wait_spu_inbox` does at `SPULLVMRecompiler.cpp:4558`.
* **Hazards, both unresolved:** every writer of `state` must notify or the thread
  sleeps to the timeout, which is why the timeout is mandatory; and `BR`-to-self
  is also what a guest deadlock looks like, so parking makes a hang silent —
  keep a counter or log at the park.
* **Gate:** `debug.rpcsx.thor.spu_selfloop_park`, default off, A/B'd with p95 from
  `dumpsys SurfaceFlinger --latency`.

Two smaller items also remain unmeasured and need no recompiler work: **non-
temporal large DMA** (`LDNP`/`STNP` for the 16 KB transfers) and the **MFC
prefetch oracle**. Both aim at `process_mfc_cmd`, 20% of gameplay.

# Novel hardware acceleration: what is viable, measured on device

Measured, not assumed — `mrs ctr_el0` from a static binary on the Thor:

```
CTR_EL0 = 0x000000049444c004
ERG      = 64 bytes   (exclusive reservation granule)
CWG      = 64 bytes   (cache writeback granule)
DminLine = 64 bytes   IminLine = 64 bytes
```

**The exclusive monitor cannot serve as a PS3 reservation.** The idea was
attractive: `GETLLAR`/`PUTLLC` is load-linked / store-conditional over a 128-byte
line, which is *exactly* what ARM's monitor does natively, while x86 has no LL/SC
at all and forces the seqlock + `mov_rdata` + `cmp_rdata` emulation this fork
carries. It is the one place where AArch64 is structurally **better** suited to the
PS3 than the architecture the emulator was written for.

**ERG is 64 bytes and there is one monitor per core, so it covers half a
reservation.** What survives:

* **A wake source.** `WFE` wakes on monitor loss, so `LDXR` + `WFE` is an
  event-driven wait on half the line — strictly better than the spin that is there
  now, with a timeout covering the other half.
* **A fast negative check.** Monitor lost means something in that 64 bytes
  changed, so the reservation is definitely broken and the 128-byte compare can be
  skipped entirely on that path.

What does not survive: replacing the compare outright. Written down with the
number so the idea is not re-derived a fourth time.

## Two more, and one correction

**The MFC command queue is a free prefetch oracle.** Emulators rarely prefetch
because real hardware does not need to, but the SPU's MFC queue *lists the
addresses the guest is about to touch*. `PRFM` the destination of DMA *n+1* while
transfer *n* runs. Unmeasured, and it aims at `process_mfc_cmd`, which is 20% of
gameplay.

**BUILT 2026-08-13, default off, and unmeasured**, as
`debug.rpcsx.thor.dma_nontemporal = <bytes>`, the size at which the pair loop
takes over. `__movsb` on ARM64 now routes through `thor_dma_copy`, so one gate
covers all six DMA call sites. Whole 64-byte blocks go through `LDNP`/`STNP`; the
remainder goes to `memcpy`, so the tail cannot be got wrong.

**And the premise was checked, because it was wrong.** The comment in
`SPUThread.cpp` claimed bionic's memcpy "uses ldp/stp pairs and non-temporal
stores for large sizes". Read out of the device's own libc: `memcpy` is an ifunc
choosing `memmove_generic` or `memcpy_opt`, and **neither contains `stnp`, `ldnp`
or `prfm`**. `stnp` and `ldnp` appear **zero** times in the entire library, across
146,002 disassembled lines in which `ldp` appears 4,439 times and `prfm` 10 — that
last count is what makes the zero mean something. So nothing downstream was
mitigating the eviction, and the item below is real rather than already-solved.

Verified two ways, because AArch64 code cannot run on this host: the target build
emits exactly `ldnp q0,q1 / ldnp q2,q3 / stnp q0,q1 / stnp q2,q3 / add / add /
subs / b.ne`, and a model of the block-and-tail arithmetic matches `memcpy` over
3,072 cases spanning every residue mod 64 at three start offsets, including the
16 KB size the SPU jobs use.

**Large DMA should be non-temporal.** The comment at `SPUThread.cpp:1108` says
Eternal Sonata "pounds 16 KB transfers", and the bulk path is plain
`std::memcpy`. A 16 KB copy evicts most of L1 and much of L2 — including the
working set of the other five SPU threads sharing those two cores. `LDNP`/`STNP`
and `PRFM PSTL1STRM` exist for this, and `buffer_stream.hpp` already reaches a
real `STNP` elsewhere.

**Correction to the affinity advice: not the A510s.** They share one vector unit
per *pair*, which this repo already measured as AES at 18.9x on X3 against **9.0x**
on an A510. SPU emulation is vector-heavy, so A510s are the worst home for it.
Widen SPU affinity toward CPU3 (A715) and CPU7 (X3, currently running a
single-threaded RSX that costs 2.23%) — never CPU0–2.

## Confirmed dead, so nobody re-derives them

**ARM TME** would make `PUTLLC` a native transaction; it is not in this chip's
feature list. **SVE** is the natural fix for 128 SPU registers spilling onto 32
(10.1% of emitted JIT instructions are spills); this chip does not have it and
upstream's two SVE commits must never be ported. Both are the architecturally
right answer and both are unavailable.

# Every wait in this emulator spins, and only one of them parks

Four layers, found independently from two profiles, all the same shape:

| layer | bounded spin | fallback | share of gameplay |
| --- | --- | --- | --- |
| lv2 syscalls | 50 × 26 µs = **1.3 ms** | futex — a real sleep | 73.9% of a title screen, ~0 in gameplay — **fixed** |
| SPU JIT self-loop | none — bare `ldr`/`cbz` | **none** | **~20%** |
| SPU MFC reservation | 15 × 26 µs = **390 µs** | `sched_yield` forever | ~7% |
| `vm::writer_lock` | 100 × 10.4 µs = **1.04 ms** | `sched_yield` forever | 6.2%, six threads at once |

Only the first had a real sleep underneath, and it is the only one that was
fixable cheaply. The rest end in nothing or an unbounded `sched_yield`, which does
not sleep — it re-queues, keeps the thread runnable, and holds the cluster at a
high operating point regardless of work retired. **Roughly a third of gameplay CPU
is threads waiting, at full issue rate, for something that has not happened yet.**

Detail, insertion points and hazards in
[`docs/arm64/jit-emitted-code.md`](docs/arm64/jit-emitted-code.md). The SPU
self-loop site is exact: `SPULLVMRecompiler.cpp:9874`, `BR`, which has no case for
`target == m_pos`.

# Two config-only experiments outrank all of that

**RETRACTED: SPU threads are not pinned to two cores.** This section claimed the
`Affinity` block in `config.yml` (`CPU5: SPU`, `CPU6: SPU`) meant six SPU threads
shared two cores, and built an oversubscription argument on it. **Measured on
device, every emulator thread reports `Cpus_allowed_list: 0-7`** — all eight
cores. PPU threads are unrestricted despite `CPU4: PPU`, which proves the table is
not applied at all under `Thread Scheduler Mode: Operating System`. The Linux
scheduler places these threads; the config block is inert.

The error is the one this file warns about more than any other: **a config value
was read and assumed to take effect.** One `grep Cpus_allowed_list
/proc/<pid>/task/*/status` would have caught it before the claim was written, and
it is the same class as trusting the version banner or a property that never
reaches the binary.

Both experiments built on it came back null, as they had to:

| change | result |
| --- | --- |
| `Affinity` SPU → CPU3 as well (2 cores → 3) | 3.944 vs 3.946 cores — **identical**, and inert anyway |
| `SPU loop detection: true` | 4.029 vs 3.949 cores, frame times unchanged — no effect, and deep inside Eternal Sonata's ~1.4-core noise floor |

`SPU loop detection` failing to help is independently consistent with the profile:
the hot `0xcc4` loop polls `spu_thread::state`, not a channel, and that setting
targets channel/idle loops.

**What survives.** Thread placement is still worth investigating, but through the
**scheduler**, not this config block — and any future attempt must verify with
`Cpus_allowed_list` that the change actually landed. If affinity is ever forced,
avoid CPU0–2: the A510s share one vector unit per *pair*, measured here as 9.0x
against the X3's 18.9x on AES, and SPU emulation is vector-heavy.

The codegen work is therefore **not** obviated. Both cheap escapes are closed.

# Grep the shipped `.so` for the property before every property A/B

One command, before the arms run:

```sh
P=$(adb shell pm path net.rpcsx.easy | sed 's/package://;s/base.apk//')
adb shell "grep -ac 'debug.rpcsx.thor.<name>' ${P}lib/arm64/librpcsx-android.so"
```

It has already caught three distinct silent no-ops in one session, each of which
would have produced a confident number from two identical arms:

1. **An `adb install` that printed `device offline`** and scrolled past. Both arms
   ran the old build; they differed by **1.37 cores, 58%**, purely from
   between-boot variance. Written up unchecked, that is a 37% win.
2. **A gate on `defined(ARCH_ARM64) && defined(ANDROID)` in `rx/asm.hpp`** —
   correct for the rpcs3 translation units that use the neighbouring helpers, and
   silently false for `rx`'s own, which folded the function to a constant.
3. **A gate applied to `rx/src/SharedMutex.cpp`**, which is `EXCLUDE_FROM_ALL` and
   not linked at all; the live `shared_mutex` is `rpcs3/util/mutex.cpp`.

All three compile, link, run, and change nothing. The string in the binary is the
cheapest proof that the code you edited is the code that executes — the same rule
this file already states for the version banner, applied to properties.

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

# The SPU self-loop park has no reach on Folklore's title screen

**Measured 2026-08-18, and it closes an item this file carried as "built, default
off, and unmeasured" since 2026-08-13.**

The park counters now print. `perf_monitor` appends them to its own periodic line,
which already reaches `RPCSX.log`:

    SPU self-loop park: entries=0 exits=0 parked_now=0 last_pc=0x00000

**Nine PERF lines, nine zeros**, with `debug.rpcsx.thor.spu_selfloop_park=100`, the
property read back from `getprop`, and the format string confirmed in the shipped
`.so`. The report fires and counts nothing, so the SPU never branches to itself on
this scene. The `BR target == m_pos` case is never reached.

**Before this, the counters had no reader.** `thor::g_spu_selfloop_park` was written
at `SPULLVMRecompiler.cpp:10093-10098` and read by nothing; the string "selfloop"
appeared in exactly two files in the tree. So the record-on-entry slot this file
asks for existed and could not be read, and a lever with no reach was
indistinguishable from a lever with no effect. That is the same shape as `vm_log`
emitting nothing, and it is now fixed.

**The 20% figure is Eternal Sonata gameplay, not a title screen.** Nothing here
contradicts it. It says only that Folklore's title screen cannot test it, so any
future arm on this lever needs a gameplay scene.

## The A/B that ran first, and the control that killed it

The park was A/B'd before the counter existed. Six interleaved arms, 60 s windows,
every arm at 7200 frames:

| arm | SPU ticks | process total | frames |
| --- | --- | --- | --- |
| park 0 | 576, 582, 588 | 1886, 1832, 1854 | 7200 each |
| park 100 | 556, 567, 574 | 1825, 1873, 1866 | 7200 each |

The ranges do not overlap - 576-588 against 556-574 - which reads as **-2.8% SPU
thread CPU at no frame cost**. It is not a result.

**A control pair with both arms at 0 gave 561, 575, 565, 571, 573.** That spread is
14 ticks, the same size as the 16-tick "effect", and it straddles both arms. The
counter then said `entries=0`, so there was never a mechanism.

**This is the third time this exact shape has been retracted here**, and the second
at the number 2.8% - the SPU branch lane extract was reported at 2.8%, made the
default, and withdrawn. Run the control before believing a separation under 5%.

# Measure the thread the change lives in, not the process

`tools/thor_thread_ab.sh` A/Bs one property and reports **per-thread** CPU, summed
over a thread-name prefix. `tools/thor_phase_gated_ab.sh` measures the whole
process, which is right for a change that touches every thread and wrong for one
that touches a single thread.

Folklore's title screen, in one 60 s window:

| | ticks | share |
| --- | --- | --- |
| process total | 1823-1890 | 0.30-0.35 cores |
| `SPU[0x0000100]` | 561-592 | ~31% of the process |
| `rsx::thread` | 252-323 | ~15% of the process |

The process total spread for one fixed setting is about 60 ticks. A change confined
to `rsx::thread` can therefore halve its own thread and stay inside the process
noise. Name the thread.

The tool takes a **prefix**, so `SPU[` sums every SPU thread, and it prints the
matching thread count. A boot with a different thread count is not comparable, and
the count is what says so.

# Traps found while measuring on 2026-08-18

* **The frame delta is quantized to 300.** The `tex3d_reach` probe reports every
  300 frames, so every frame count is a multiple of 300. "Exactly 3600 against
  exactly 7200" is the reporting granularity, not a deterministic result. Do not
  read the roundness as strength.
* **`tex3d_reach` is a free frame counter.** It prints `over N frames` through
  `rsx_log.error()`, which this device flushes, so an A/B needs no build flag and
  no SurfaceFlinger parsing to count frames.
* **The screen and the charger heat the device with the emulator stopped.**
  `svc power stayon true` plus USB charging held the CPU junction at 81-82 C for 40 s
  of idle, with nothing running and the battery at 26 C. It is neither a launch
  transient nor an artifact of reading the sensor.
* **Tell a hot sensor from a real throttle with `scaling_max_freq`.** At 82 C the
  A710/A715 cluster read `scaling_max_freq=2707200` against
  `cpuinfo_max_freq=2803200`, a 3.4% cap, while CPU7 stayed uncapped at 3187200.
  The frequency cap is the throttle; the temperature is only its cause.
* **A bare max over `thermal_zone*` reads the wrong sensor.** All zones gave 63400
  in the same minute that `cpu-1-*` gave 84300. Read the `cpu-1-*` junction zones.
* **Widening the frame band lets a compile arm through.** A control arm passed a
  3000-7600 band at 6000 frames while burning **6874** ticks against a normal 1850.
  It was still compiling. The tight 6800-7600 band would have rejected it.
* **The USB serial died mid-session and came back `unauthorized`.** The network
  transport kept working throughout. Set `THOR_SERIAL=192.168.1.33:5555` rather
  than restarting the session.

# The lv2 spin win, re-measured on 2026-08-18 with a second instrument

**This is the largest ARM64 performance property in the build, and it now has an
independent confirmation.** The original measurement used cores-busy and reported a
67.6% saving. This one counts scheduler ticks per thread, on a different build,
months later, with the arms interleaved.

Folklore, title screen, 60 s windows, every accepted arm at **7200 frames** and
**16 PPU threads**:

| `debug.rpcsx.thor.lv2_spin` | PPU thread ticks | process total | frames |
| --- | --- | --- | --- |
| **0** - this fork's default | **520** | **1824** | 7200 |
| 50 - upstream behaviour | 4426 | 6003 | 7200 |
| 50 - upstream behaviour | 4591 | 5937 | 7200 |

**Upstream's spin costs 8.5x the PPU thread CPU and 3.3x the process CPU for the
same 7200 frames.** The saving is **69%**, which agrees with the 67.6% already
recorded here.

**The ranges cannot be argued with.** Fifteen accepted default arms across the whole
session, over four separate experiments, put the process total between **1823 and
1890**. The two upstream arms are **5937 and 6003**. Nothing overlaps, and the
separation is 3.2x against a control spread measured the same day at 14 ticks.

**The frame count is the guard.** A CPU number alone cannot tell a thread that
stopped spinning from an emulator that stopped working. Every arm here rendered
exactly 7200 frames, so the CPU came off the spin and not off the work.

The hotter arms are the upstream ones - 64.6 C and 66.2 C against 59.0 C. That is
the consequence of burning three times the CPU, not a confound, and it pushes the
upstream arm in the direction it already lost.

# What this session did NOT establish

Said plainly, because this file records retractions beside claims:

* **No new optimization was found.** The number above is the fork's existing
  default, re-verified. It is not work done on 2026-08-18.
* **`spu_selfloop_park` gained nothing**, and now cannot on this scene - the counter
  reads `entries=0`.
* **`rsx_fifo_park` is still unresolved.** With the park on, `rsx::thread` spent
  267-285 ticks against 252 with it off, from one sample of the off arm. If
  anything that is worse, and it is not established either way. The default stays 0.
* **A mid-session claim that the park halved the frame rate was wrong and is
  withdrawn.** Two boots at park=1 read 3600 frames while twelve at park=0 read
  7200, which looked decisive. Four more boots at park=1 then read 7200 three times.
  The 3600 readings were the attract-movie phase this file already documents, and
  the phase gate is what exposed the error.

# Folklore's title screen has two steady states, and one of them starves the RSX

**Profiled on device 2026-08-18. This is the mechanism behind the phase scatter
this file has fought for weeks.**

One 60 s window, same title, same build, same settings:

| state | process ticks | frames | `rsx::thread` ticks |
| --- | --- | --- | --- |
| light | 1823-1890 | 7200 | 256-283 |
| starved | 6876-6879 | 6000-6300 | 5985 |

**The starved state costs 3.7x the CPU and delivers FEWER frames.** `rsx::thread`
sits at 5985 ticks per 60 s, which is 99.75% of one core.

A 24,208-sample profile of the starved state, 0 lost:

| | share |
| --- | --- |
| `rsx::thread` | **89.13%** of all cycles |
| kernel | 81.71% |
| `librpcsx-android.so` | 3.95% |
| `sched_yield`, self | 5.79% |

**Every single `sched_yield` sample is on `rsx::thread`** - 1,295 samples, 100%
self. That is the `FIFO_EMPTY` branch at `RSXFIFO.cpp:756` calling
`std::this_thread::yield()` while the guest fails to feed the ring. The RSX starves
and burns a whole core doing it.

The light state, 9,365 samples, is a different program:

| thread | share | | object | share |
| --- | --- | --- | --- | --- |
| `SPU[0x0000100]` | 40.35% | | JIT code (unnamed) | 42.19% |
| `PPU[0x1000000]` | 24.04% | | `librpcsx-android.so` | 25.07% |
| `rsx::thread` | 16.31% | | kernel | 17.10% |

**Read the state before reading any arm.** The 185-ticks-over-1750-frames against
1720-over-3500 pair this file records is these two states, not random scatter. The
frame count identifies which one: 7200 per 60 s is light, 6000 is starved.

# `rsx_fifo_park` is not a win, and the default stays 0

**Measured 2026-08-18 across about twenty boots.** The property replaces the
`sched_yield` spin above with eight `rx::pause()` calls and then
`rx::wait_for_event()`.

In the light state it is a small, consistent **regression**:

| `rsx_fifo_park` | `rsx::thread` ticks | frames |
| --- | --- | --- |
| 0 | 256, 257 | 7200 |
| 1 | 281, 283 | 7200 |

That is +10% on the thread, +1.4% on the process, and the ranges do not overlap.
The FIFO is rarely empty here, so the park pays its cost and buys nothing.

Under induced starvation - seven spinner processes taking the cores away from the
guest, identical in both arms - the park does bound the spin, and it also breaks:

| arm | `rsx::thread` ticks | frames |
| --- | --- | --- |
| park 0 | 3863 | 4200 |
| park 0 | 3691 | 4200 |
| park 1 | 1083 | 5100 |
| park 1 | **2200** | **2700** |

The last row is the problem. **2700 frames is the worst throughput measured in the
whole session**, and it came from the park. That is the wake latency ARMSX3
records: ouroboros420/rpcsx parked bare here (`e31ef44ef`) and reverted it
(`832c23078`) because it cost frame-time smoothness. This tree reproduced their
result independently.

**So the park trades a bounded worst case for an unbounded frame cost, and neither
side is reliable.** It stays off. A change that fixes the starve without the wake
latency has to keep short idles spinning - raise the eight-spin threshold far
enough that only sustained starvation parks - and that is unbuilt and unmeasured.

# `dma_nontemporal` is closed by arithmetic, not by an experiment

The light-state profile puts `memcpy_opt` at **5.19%** of cycles, which is the
reach this lever needs and the first time it has been measured. Then
[`bench-results.md`](docs/arm64/bench-results.md) supplies the other half: the
non-temporal copy is **3.1% faster at 16 KB**.

3.1% of 5.19% is **0.16% of cycles**. The control spread on this device is several
percent, so the experiment cannot resolve its own prediction. Do not run it.

This is the rule about writing the predicted magnitude down first, working exactly
as intended: two numbers already in the repo killed a lever in one line of
arithmetic and cost no device time.

# simpleperf needs `run-as` on this device

`perf_event_paranoid` is 1 and `setprop security.perf_harden 0` does not change it,
so `simpleperf record -p <pid>` fails with `Permission denied` on `cpu-cycles`.
Run it as the app instead, which a debuggable build allows:

    adb shell run-as net.rpcsx.easy /system/bin/simpleperf record \
      -p <pid> --duration 25 -f 1000 -g -o /data/data/net.rpcsx.easy/perf.data

The shipped `.so` is stripped, so symbols inside it come back as
`librpcsx-android.so[+offset]`. Thread, DSO and kernel attribution all work
without symbols, and that was enough to find the starve.
