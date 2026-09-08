# Upstream survey, 2026-09-07: ARMSX3 eighth pass and RPCS3 master

Part of the notes indexed from [`AGENTS.md`](../../AGENTS.md). The ledger for
the survey series is [`../fork-watch.md`](../fork-watch.md).

This pass has two halves. The first half is a read of the two upstream trees in
the comparison checkout, `rpcs3-upstream`, after a fetch. The second half is a
web search for what the RPCS3 project and the Android forks say about the
Transformers bottleneck. Both halves are host work. Neither touched the Thor.

## Fetch state

| ref | head | date | note |
| --- | --- | --- | --- |
| `origin/master` (RPCS3/rpcs3) | `54014a7de` | 2026-09-07 | 206 commits since 2026-08-15 |
| `armsx3/master` (ARMSX2/ARMSX3) | `6925a398e` | 2026-09-07 | 443 non-merge commits since 2026-08-15; tags 0.9.5, 0.9.6, 0.9.7, 0.9.7.1 to 0.9.7.3 |

The seventh pass stopped at ARMSX3 `daed55c42` and RPCS3 `3aac7d776`.

## Ported in this pass

Each port carries the origin hash in its commit message. Each one is a code
change and needs the same proof as any other change. None is a speed claim
until a device A/B says so.

### 1. Stop reading the ARM system counter on every guest atomic and DMA

ARMSX3 `2f0ce7786`, 2026-08-30. `perf_meter`'s default constructor calls
`restart()`, which is `rx::get_tsc()`, which is `mrs cntvct_el0`. The Thor
measures that read at 38 ns. The destructor discards the sample unless
`g_cfg.core.perf_report` is on, and it defaults off. So every PPU `lwarx` and
`stwcx`, every SPU DMA transfer, every MFC list command and every `PUTLLC` paid
the read and threw it away.

The port adds `perf_meter(std::nullptr_t)`, which samples only under
`perf_report`, and uses it at five sites: `ppu_load_acquire_reservation`,
`ppu_store_reservation`, `do_dma_transfer`, `do_list_transfer` and
`do_putllc`. The LARX after-fail window test reads the counter only when
`last_faddr` matches, which is the only path that uses the value.

Not changed, on purpose: the `STORE128` meter in `do_cell_atomic_128_store`.
Its value is read to time the `suspend_all` path. This fork also has one more
in-function read than upstream, `perf2.get()` in `do_putllc`. It feeds only a
`perf_report`-guarded warning, so a disabled meter cannot be observed.

Why it matters here: Transformers combat runs about 36,000 failed reservation
stores per second, and the SPU profiler puts SPU0 at 99 percent reservation
traffic. Every one of those operations carried at least one wasted counter
read.

### 2. Ask for precise timers

ARMSX3 `67c2763b9`, 2026-08-29. Desktop `rpcs3.cpp` sets
`prctl(PR_SET_TIMERSLACK, 1)` in `main()`, and `lv2.cpp`'s wait path assumes
it. The Android app `dlopen()`s the core and never runs that `main()`, so the
process kept Android's default slack of 50,000 ns. Every `sys_timer_usleep`
overshot by up to 50 us. The port adds the same call to `_rpcsx_initialize`.

ARMSX3 first changed the sleep timer default to "Usleep Only" (`198ca8eca`),
then reverted it (`3fc662e56`) once the `prctl` proved to be the real fix. This
fork keeps "As Host" and takes only the `prctl`.

### 3. The SPU-compile waiter throttle formula

ARMSX3 `00f0d2e38`, 2026-08-30. Upstream's `true_free = thread_count - 10` is 0
on every 8-core device. So while any SPU block compiles, a random reservation
waiter sleeps 200 us. ARMSX3 measured 2,179 ms frames at the tail of a
1,723-block compile burst with that formula. Their head keeps
`hw_threads > 10 ? hw_threads - 10 : hw_threads / 2`. This fork's native SPU
object cache is off by default, so every boot is a cold burst and the throttle
is live through the whole warm-up. Ported as the same one-line formula.

## Rejected in this pass, with the reason

| change | reason |
| --- | --- |
| RPCS3 `2416d6526` SHUFB known-constant fast paths | ARMSX3 `1be6ebb4b` reverted it on ARM64. Special-index constants were misread as source selects: 403 ms frames, hangs, crashes. This fork already carries ARMSX3's `19d23eb69` shape. |
| ARMSX3 SPU reservation backoffs that sleep (`eafe7bee1`, `4ed00d145`, `d8bcbf7bf`) | Reverted by their own `00f0d2e38` after 2,179 ms frames. Only the `true_free` half survived, and that is item 3 above. |
| ARMSX3 "RSX no longer spins on empty FIFO" (`814ffe9de`, `6d728f5ad`) | Reverted twice by them, God of War 3 fell from 54 to 14 FPS. This fork has its own FIFO idle design in `RSXFIFO.cpp`, measured null on Transformers. |
| ARMSX3 "SPU threads kept off the little cluster" (`dc70fe2c9`) | Reverted by `577d60604` inside the same release. This fork already records that affinity is inert under the OS scheduler mode. |
| ARMSX3 RSX label wait uses driver timeout (`f6f580ca6`, `6ed8e45c5`) | Already present. `nv406e.cpp` compares against `tdr`. Only their logging is absent. |
| RPCS3 PR #18055, `busy_wait` scaled by ARM timer frequency | Present and neutralised on purpose. `rx/asm.hpp` records why the scale must not apply here. Do not re-port. |
| ARMSX3 `9b3331698` NEON `mov_rdata` | Conflicts with this fork's rule in `SPUThread.cpp`: a re-land needs randomised equivalence testing first. |
| RPCS3 programmable blending series, GFNI and AVX-512 commits, macOS JIT commits | Not applicable to Adreno or ARM64. |

## Needs adaptation, not ported yet

- **ARMSX3 PUTLLC16 whitelist series** (`3a491b44e`, `6c4b63905`,
  `357eee994`, `3a03103fa`). Their finding: upstream's `allowed_patterns` holds
  one disabled placeholder, so with accurate reservations on, `PUTLLC16` never
  installs and every SPU conditional store takes the `vm::writer_lock` global
  barrier. This fork's gate at `SPUCommonRecompiler.cpp` has a different
  shape and no `allowed_patterns` symbol. Read the fork's own refusal log
  before a port. The unconditional filtering half, `357eee994`, is the safe
  part.
- **ARMSX3 `27819fba8`** notifies `g_range_lock_bits[1]` when it clears and
  makes the PPU `passive_lock` wait on the word instead of yielding. This fork
  measures `writer_lock` plus `passive_lock` at 6.2 percent of gameplay and has
  its own graduated backoff in `vm.cpp`. Read the else branch before a patch.
- **ARMSX3 `a4d06a016`** stops suppressing the reservation notify for cellSync
  `PUTLLC`. Behaviour change with a thundering-herd risk on SPURS titles.
  Measure, do not assume.
- **RPCS3 ZCULL report fixes** `1559b15af` and `7a953ecf0` (`>=` on
  `write_length`, unique-address count) are small and clean. `25f1a9dfc`,
  `57dd6e763`, `0ead9328f` and `065b490eb` add `mm_flush` calls that need a
  redesign against this fork's `Host/MM.cpp` mirror. Unreal Engine 3 uses
  occlusion queries, so these have medium rank for Transformers.
- **ARMSX3 `c78913cfd` and `0cabd1468`** drop a vblank event into a full queue
  instead of stranding the VBlank thread. Robustness, clean port, not speed.
- **ARMSX3 `41ec00735`** XER SO/CA transposition in `MFXER`/`MTXER`.
  Correctness only. Needs a PPU object-cache version bump.
- **ARMSX3 `884cb47dd`, `424514fde`** FMS NaN-sign `negate_addend` and the
  f64[4] low-side select. Partially present. Correctness only.

## Hazard, not a port

ARMSX3 `457a932c7`: their ARM64 SPU object cache baked `&g_timebase_offs` as a
`movk` immediate and crashed at boot. This fork's `SPULLVMRecompiler.cpp` has
the same IR shape at one site and a `updateGlobalMapping` path at another.
Which one the `spu-native-v2` cache path emits is not determined. Check before
you enable `debug.rpcsx.thor.spu_native_object_cache=1` for a measurement.

## What the web says about the Transformers bottleneck

The fetches to wiki.rpcs3.net, forums.rpcs3.net and web.archive.org returned
HTTP 403, so wiki and forum facts come from search snippets only.

- **The 2400-iteration `RdDec` loop is a libspurs pattern, not game code.**
  RPCS3 PR #14469 (Whatcookie, 2023) describes Red Dead Redemption running
  `for (i = 0; i < 2400; i++) read_decrementer();` on the SPU and inlined the
  read to make it cheaper. Same count. RDR is not Unreal Engine 3.
- **Upstream has not solved skipping that loop.** Issue #16834, "SPU LLVM:
  Detect and optimize SPU_RdDec based loops" (elad335, 2025-03-09) is open with
  no comments. PR #17172, "Alpha WIP: SPU Analyzer: Detect RdDec pseudo-reads
  loops" (2025-05-06) is a draft whose author says it does not work. Nobody has
  replaced such a loop with a host sleep. A fork-side fix is new work.
- **PR #18751** (2026-05-16) inlines the decrementer read on ARM through LLVM
  `readcyclecounter`. This fork already has it, adapted from commit
  `61a2604824`. The inline path is gated on SPU loop detection being OFF, which
  is why loop detection measured hotter here.
- **PR #18395** (2026-03-26) is the "Reduced Loop" work, plus 3 to 8 percent
  in SPU-bound titles. Follow-ups #18500 and #18581 (RCHCNT write-channel
  loops). None addresses a channel-read delay loop.
- **Why `mrs cntvct_el0` costs 38 ns.** Measured reads elsewhere: 14 ns on
  Apple M1, 28 ns on a Raspberry Pi 5, 45 ns on a Pi 3B. A hypervisor trap
  would cost far more. So 38 ns is a normal, slow, non-pipelined system
  register read on this core, not a trap. No emulator was found that elides
  per-instruction counter reads inside a counted loop.
- **Transformers on the RPCS3 wiki**: Playable since 0.0.25-14483. One
  "Unlock FPS" patch by FlexBy, a single `be32` write at `0x0020099C`. It lifts
  the 30 cap and cannot help a title that runs below it.
- **ZCULL and vblank on Unreal Engine 3 titles**: the wiki pages for Unreal
  Tournament 3, Mirror's Edge and Medal of Honor all say the unlocked maximum is
  half the vblank frequency, so these ports present every second vblank. Relaxed
  ZCULL Sync helps some titles and drops others to 1 or 2 FPS (RPCS3 issue
  #12972). No Unreal Engine 3 specific ZCULL report was found.
- **ARMSX3 0.9.5 release notes** list the counter-read removal, little-cluster
  avoidance, reservation backoffs, FIFO spin removal and the sleep timer
  default. The table above says which survived to their head. Only the
  counter-read removal did.
