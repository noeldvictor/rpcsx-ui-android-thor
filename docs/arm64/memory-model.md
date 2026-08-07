# Memory model, atomics and code publication

x86 is total-store-ordered and ARM is weakly ordered, so this is where an
emulator written on x86 is most likely to be subtly wrong. Includes the
instruction-cache work, since publishing code is the same class of problem.

Part of the notes indexed from [`CLAUDE.md`](../../CLAUDE.md).

## The memory model, and the one structural gap left

x86 is total-store-ordered and ARM is weakly ordered, so this is where an
emulator written on x86 is most likely to be subtly wrong. Audited, and the
synchronization primitives hold up:

- **`atomic_t` is conservative by construction.** `load()` is `SEQ_CST`,
  `store()` is `RELEASE`, and every read-modify-write is `SEQ_CST`. On ARM those
  become `LDAR`/`STLR` and full-barrier RMWs, so the default path is safe.
- **`observe()` is the relaxed one, and it is only used for settings.** All
  thirteen uses are config reads behind `#ifdef ANDROID`, values written once at
  boot. That is the one place where relaxed is right and cheap, and it is the
  only place it appears.
- **Fences are real.** `atomic_fence_*` fall through to
  `__atomic_thread_fence`, which emits `DMB` on AArch64; the compiler-barrier
  forms are x86-only, which is correct for TSO.
- **`trigger_write_page_fault` looks alarming and is not.** The ARM64 inline-asm
  path excludes Android, but the generic fallback compiles to
  `ldset wzr, w8, [x0]`, one instruction, because `-march=armv8.2-a` supplies
  LSE. It is actually one instruction shorter than the hand-written version.

Two things that are worth knowing rather than acting on blindly:

- **The GETLLAR fast path is a seqlock, and seqlocks are the classic weak-memory
  trap.** It reads the reservation counter, compares 128 bytes, then re-reads
  the counter and re-compares. Both counter reads are `SEQ_CST`, so nothing can
  hoist above the first one. Acquire is one-way though, so in principle the data
  comparison can sink below the second counter read, which is exactly what a
  seqlock must not allow. The doubled check makes this extremely narrow rather
  than theoretical-only, and this code runs on Apple Silicon upstream, so it is
  recorded as a risk area rather than "fixed" by dropping a `DMB` into the
  hottest SPU path on a hunch. If reservation desyncs ever show up on ARM, start
  here, and make the change with a measurement attached.
- **The SPU atomic fast path is x86-only, and that is the largest remaining
  structural gap.** `utils::has_rtm()` is hard-coded `false` on AArch64, so
  `g_use_rtm` is always false and ARM takes the pre-TSX fallback on all eight
  branches that test it. For a 128-byte atomic store that means
  `vm::writer_lock`: a CAS loop on one shared 64-bit bitmask, plus
  `cpu_thread::suspend_all` on some paths, where x86 uses a hardware
  transaction. Every SPU atomic therefore contends on a single cache line across
  eight cores.

  **Armv8.5 does define transactional memory, FEAT_TME, and this chip does not
  have it.** Decoded from the `ID_AA64ISAR0_EL1` captured on device,
  `0x0021111110212120`: TME is bits [27:24], which read `0`. (Cross-check: bits
  [23:20] read `2`, the FEAT_LSE field, matching what the probe reported.) So
  the "port TSX to ARM transactions" idea is closed, not merely unexplored, and
  nobody needs to re-investigate it on this hardware.

  What remains is therefore a redesign rather than a port: something ARM-shaped,
  such as finer-grained per-reservation locking using LSE. That is a real design
  change with real risk, and it is the highest-value ARM work left here.

  One part of the cost has already come down, though, and it is worth not
  double-counting. The heavyweight path's own bookkeeping runs on 16-byte
  atomics, and those no longer take a cache line exclusive merely to be read
  (see the dead-macro section of this document). The lock is still shared and
  still contended; it is
  the *reads around it* that got cheaper.

  Related and also closed: the HLE variants in `shared_mutex`
  (`compare_exchange_hle_acq`, `fetch_add_hle_rel`) are x86 lock-elision
  primitives, and they degrade correctly rather than silently. `s_hle_ack` and
  `s_hle_rel` fall back to plain `__ATOMIC_SEQ_CST` when
  `__ATOMIC_HLE_ACQUIRE`/`_RELEASE` are undefined, and clang defines neither on
  aarch64 (verified with `-dM -E`). So those are ordinary seq_cst RMWs on ARM:
  no elision, but no correctness gap and nothing to port.

## The dead macro that cost every 16-byte atomic

The single largest find of the sweep, and it was not a missing instruction but a
macro that could never be true.

`util/atomic.hpp` has LSE2 fast paths for `atomic_t<u128>` guarded on
`ARM_FEATURE_LSE2`. There is no ACLE feature macro for FEAT_LSE2, so
`rx/types.hpp` inferred it from `__ARM_ARCH_8_4__`, `__ARM_ARCH_8_5__`,
`__ARM_ARCH_8_6__` or `__ARM_ARCH_9__`. **Clang on AArch64 defines none of
those, at any `-march`.** Verified directly: at `armv8.2-a`, `armv8.4-a` and
`armv9-a` the only things that appear are `__ARM_ARCH 8` or `9` and the
`__ARM_FEATURE_*` family. The comment above the probe even calls itself a hack
because `__ARM_ARCH` "isn't universally defined"; the replacement doesn't work
either. So the macro was never set, and every LSE2 path was dead code.

What the fallback actually does:

| operation | with LSE2 | what we were running |
| --- | --- | --- |
| `load` | `ldp` + `dmb ish` | `ldaxp` / `stlxp` / `cbnz` retry loop |
| `store` | `dmb` + `stp` + `dmb` | falls through to `exchange`, same loop |
| `release` | `dmb` + `stp` | falls through to `exchange`, same loop |

The instruction count is the least of it. `STLXP` takes the cache line in
**exclusive** state, so a thread that only wants to *read* a reservation
acquires it for writing and invalidates every other core's copy. The structure
this happens on is `vm::g_reservations`, shared by every SPU thread, which is
the worst possible place in the emulator to force write-intent onto readers.
This sits directly underneath the contention described in the SPU atomic
fast-path section of this document.

**The blast radius is wider than the reservation path**, which is worth knowing
because it is easy to read the above and conclude this only mattered for
`GETLLAR`. Every 16-byte `atomic_t` in the emulator went through that loop:

| site | what it is |
| --- | --- |
| `vm::g_reservations` (two sites) | SPU reservation stamps, the case already described |
| `spu_channel_4_t::values` | **SPU mailboxes.** `sync_var_t` is `alignas(16)` and exactly 16 bytes (`u8`+`u8`+`u16`+3×`u32`), so count and all three queued values are one 128-bit atomic. Every `try_pop`, `try_read` and `push` on a channel-4 hits it |
| `s_cpu_bits` | the **global CPU-thread bitmask**, touched by `suspend_all` and by thread state changes, so shared by every thread in the process |
| RSX label store | one `release`, cold by comparison |

The mailbox one is the sharpest. `try_read` is a pure peek, and before this fix
peeking at a mailbox took the cache line **exclusive**, on a structure written by
one thread and read by another. That is the ping-pong described above, on the
SPU/PPU communication path rather than on reservations.

The fix is not to write new NEON but to make the build state what it knows.
`-march` moves to `armv8.4-a`, the lowest baseline that architecturally
guarantees FEAT_LSE2, and CMake defines `ARM_FEATURE_LSE2` explicitly, gated on
that baseline. Deliberately **not** `armv9-a`: Armv9 mandates SVE2 and this
device advertises no SVE, the same constraint `sanitize_android_arm64_llvm_cpu`
exists to enforce on the JIT side.

Two things had to be checked before trusting it, and both hold. An aligned
16-byte `LDP` is only single-copy atomic *with* LSE2, so on a lower baseline
this change would be a data race rather than a slow path — hence the
configure-time guard that refuses the combination. And the alignment has to be
real: `atomic_t<u128>` gets `alignas(16)` from `Align = sizeof(T)`, and
`g_reservations` is `alignas(4096)` with every index a multiple of 16.

Pinned by `tools/test_thor_arm64_lse2_atomics.ps1`, which checks the macro, the
baseline, the Gradle/CMake agreement, the guard, and that the fast paths are
still plain `LDP`/`STP`.

The lesson generalizes past this one macro: **a feature probe that cannot fire
is indistinguishable from a feature the hardware lacks.** Grep for `#if
defined(SOME_FEATURE)` where nothing defines `SOME_FEATURE`, and check the
`-dM -E` output rather than trusting the comment above the probe.

## Acquire is one-way, and a seqlock needs both

The reservation seqlock is where TSO quietly did work nobody had to write down.
GETLLAR and the MFC DMA read share a shape:

    t0 = vm::reservation_acquire(addr)        // load-acquire
    ... copy guest data ...                   // plain loads
    if (t0 != vm::reservation_acquire(addr))  // validate
        retry

The copy is only meaningful if it is observed **strictly between** the two
reservation reads. The first read is a load-acquire, so the copy cannot be
hoisted above it. That is the half everyone remembers. The other half:
**load-acquire is one-way.** It orders later accesses after itself and does
nothing to stop earlier accesses from being observed after it. So the copy can
be satisfied *after* the validating read, and a writer that bumped the counter
in between goes undetected — which is precisely the case the check exists for.

x86 never exhibits this, because TSO does not reorder loads with loads. The read
side was correct as written, for the architecture it was written for. There was
no barrier to port because there was never a barrier.

`atomic_fence_acquire()` closes it. On x86 it is a compiler barrier and costs
nothing, so this is not a trade.

The DMA path deserved the fence as much as GETLLAR despite looking better
guarded. It re-compares the copied data, but **only in the 128-byte case**;
every smaller transfer rests on the timestamp check alone.

Two things to carry forward. First, the failure mode is an SPU atomic accepting
stale reservation data, which surfaces as a desync or hang long after the fact
and never as a slow frame — so its absence proves nothing, and no measurement
would have found it. Second, and more useful for the rest of this sweep:
**a barrier that does not exist cannot be found by reading the ARM path**,
because there is no ARM path. Grep for the *shape* — a validated re-read, a
double-check, a publish-then-flag — and ask what TSO was providing for free.
Pinned by `tools/test_thor_arm64_seqlock_fences.ps1`.

## Where AArch64 is the stronger architecture

Worth stating plainly, because the whole rest of this document points the other
way: **ARM's `LDAR`/`STLR` are RCsc, and that is stronger than x86 TSO for the
one reordering TSO allows.**

`vm::range_lock` is the case. Both sides publish their range, then read the
other side's state, which is Dekker and needs StoreLoad ordering:

    range_lock->store(to_store);                       // release store
    busy = for_all_range_locks(get_range_lock_bits(true), ...);  // seq_cst load

On AArch64 that is `STLR` then `LDAR`, and an `LDAR` cannot be observed before a
preceding `STLR`, so the ordering is free. On x86 a release store is a plain
`MOV` and a seq_cst load is a plain `MOV`, and **StoreLoad is precisely the
reordering x86 permits**. The exclusive side closes its own half with
`bit_test_set`, an atomic RMW and therefore a full barrier on both.

So there is nothing to fix here for ARM, and it is the one place found in this
sweep where the port is safer than the original. Left alone deliberately: the
protocol is intricate, the reader retries in a loop, and changing the hottest
lock in the memory subsystem on partial understanding is how you buy a rare
corruption bug in exchange for nothing.

**This has a sharp edge, and it is one this fork walked into.** Raising `-march`
to `armv8.4-a` for LSE2 also enables RCPC, and RCPC changes what an *explicit*
acquire load compiles to:

| | `armv8.2-a` | `armv8.4-a` |
| --- | --- | --- |
| `load()` (seq_cst) | `LDAR` | `LDAR` |
| `load(memory_order_acquire)` | `LDAR` | **`LDAPR`** |
| `store(memory_order_release)` | `STLR` | `STLR` |

`LDAPR` is RCpc: it is *not* ordered after a preceding `STLR`. Any code relying
on the RCsc property above would silently lose it, and the symptom would be a
rare mutual-exclusion failure, not a build error.

Checked before trusting the baseline bump. `atomic_t` is seq_cst throughout, so
every `atomic_t::load()` keeps `LDAR` and is unaffected. There are exactly two
explicit `memory_order_acquire` uses in `Emu` and `util`: one is an
`atomic_thread_fence`, which RCPC does not touch, and the other reads a config
flag for the raw object cache and participates in no protocol. Both benign.

The rule for anyone adding one later: **on this baseline, `memory_order_acquire`
buys RCpc, not RCsc.** If a StoreLoad guarantee is wanted, use a seq_cst
operation or an explicit fence, and do not assume the acquire will be an `LDAR`.

## The instruction cache is not coherent, and this chip says so

x86 instruction caches are coherent with the data caches. Write code, jump to
it, done. AArch64 makes no such promise, and crucially **what it requires varies
by implementation and is advertised in `CTR_EL0`**:

    IDC = 1   data cache clean to PoU not required
    DIC = 1   instruction cache invalidation not required

Read on the Thor's Snapdragon 8 Gen 2, by running a probe on the device rather
than assuming: **`IDC=1, DIC=0`**, with 64-byte I and D min lines. So the data
cache does not need cleaning, but **the instruction cache genuinely does need
invalidating**. Apple Silicon reports `DIC=1`, which is almost certainly why
this survived upstream despite RPCS3 running on arm64 Macs: on that hardware
the missing maintenance is harmless.

Seven sites in this codebase carried:

    asm("ISB");
    asm("DSB ISH");

which is wrong three separate ways:

1. **The barriers are reversed.** `DSB` must complete before `ISB`, so the store
   is guaranteed visible before the pipeline is flushed. As written, the flush
   happens first and orders nothing.
2. **Neither is `volatile`, and neither clobbers memory.** The compiler was free
   to move them across the very writes they exist to publish, or delete them.
3. **No cache maintenance at all**, which `DIC=0` says this chip requires.

Where the written range is known it is now invalidated exactly, via
`__builtin___clear_cache`, which consults `CTR_EL0` itself and emits only the
maintenance the implementation needs. Elsewhere the barriers became a single
`__asm__ volatile("dsb ish\n\tisb" ::: "memory")`.

The larger hole was not the hand-written trampolines but **MCJIT**, which writes
far more code than they do. `llvm::SectionMemoryManager` invalidates in
`finalizeMemory`; both custom managers here override `finalizeMemory` to
`return false` and do nothing, so **nothing was invalidating anything** for
compiled PPU or SPU code. They now record each allocated code section and clear
it. Pinned by `tools/test_thor_arm64_icache_maintenance.ps1`.

Two things worth carrying forward. First, this is a correctness fix, not a
speedup, and its failure mode is a stale instruction fetch: an unreproducible
crash or wrong branch, never a slow frame. Do not expect to see it in a
measurement. Second, and more generally: **when an architecture makes a
guarantee optional, read the register that says whether this part provides it**
instead of reasoning from the architecture manual alone. `CTR_EL0` answered in
one device-side probe what no amount of source reading would have settled.

## Locating the reservation contention exactly, and what it is not

The ledger calls per-reservation LSE locking the highest-value ARM work left,
resting on the claim that "every SPU atomic contends on a single cache line
across eight cores". That claim survives checking, but it was recorded without
naming the instruction, and the missing detail changes what the fix should be.

**Two independent locking mechanisms exist and only one of them contends.**

`vm::reservation_lock(addr)` in `vm_reservation.h` takes the **per-address**
reservation word:

    auto res = &vm::reservation_acquire(addr);   // this 128-byte line's own word
    auto rtime = res->load();
    if (rtime & 127 || !reservation_try_lock(*res, rtime))
        rtime = reservation_lock_internal(addr, *res);

`g_reservations` gives every 128-byte guest line 64 bytes, so each of those words
is on its own cache line. Two SPUs locking different addresses do not interfere
at all. **This part is already per-reservation and needs nothing.**

`vm::writer_lock` is the other one, and it is the contended one. Traced to its
callers, `spu_thread::do_putllc` takes it at `SPUThread.cpp:5109` — so it is on
the hot atomic path, not some cold corner. Reading the constructor, the
per-acquisition cost is:

    range_lock->release(addr | u64{size} << 32 | flags);   // own slot, own line
    const auto diff = range_lock - g_range_lock_set;
    if (bits != umax && !bits.bit_test_set(u32(diff)))     // shared word, atomic RMW
        break;

`bits` is `g_range_lock_bits[1]`, one 64-bit word. **`bit_test_set` is an atomic
read-modify-write on it, executed on every `writer_lock` acquisition.** Each
thread sets a different bit, so there is no logical conflict, but an atomic RMW
must take the line exclusively regardless, and that is the ping-pong: eight cores
serialising on one line to set bits that never collide.

**What is not contended, contrary to a first reading.** The per-thread
`range_lock` slot is `g_range_lock_set[i]`, `alignas(64)`, and each SPU thread
allocates one **once**, at construction (`SPUThread.cpp:3335` and `:3396`, freed
at `:3244`). The `fetch_op` on `g_range_lock_bits[0]` inside `alloc_range_lock`
is therefore thread setup, once per thread lifetime, not per operation. Writing
the slot itself touches only that thread's own cache line.

So the contention is one instruction, not a lock protocol: a single
`bit_test_set` on a shared word.

**That reframes the fix, and away from LSE.** The proposal on the ledger is to
move locking into the per-reservation word — but locking is *already* there. The
shared word is not a lock at all; it is a **presence bitmask**, published so that
whoever takes an exclusive range lock can cheaply find which slots are active.

Since every thread already publishes its full range into its own slot, the
bitmask is redundant for correctness. An exclusive taker could scan the 64 slots
directly instead of reading one summarised word. That trades:

- **removed:** one atomic RMW on a globally shared line, on every PUTLLC;
- **added:** a 64-cache-line scan on the exclusive path, which is taken for
  memory setting changes and the no-argument `writer_lock()`, both rare.

That is a real and specific change, and it is not what "per-reservation LSE
locking" describes. It needs no new instruction: `LSE` was never the missing
piece, because the expensive part is *which line is touched*, not how the atomic
is spelled. Consistent with the finding that neither optimization guide documents
atomics at all — the cost here is coherence traffic, and coherence traffic is a
function of the address.

**Not implemented, deliberately.** The `bits != umax` test also detects a held
exclusive lock, so removing the bitmask means finding another way to answer that,
and the protocol is a Dekker pattern whose reader retries in a loop. This
document already records the rule for this code: changing the hottest lock in the
memory subsystem on partial understanding buys a rare corruption bug in exchange
for nothing measurable. What has changed is that the target is now one named
instruction on one named line rather than a vague structural gap, and that
`thor_wait_profiler`'s `vm_writer_lock` counter can confirm or refute its cost in
a single run.
