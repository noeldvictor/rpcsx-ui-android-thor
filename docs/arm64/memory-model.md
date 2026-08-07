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
  such as finer-grained per-reservation locking using LSE. ~~That is a real
  design change with real risk, and it is the highest-value ARM work left
  here.~~

  > **Superseded — read the correction section below before acting on this.**
  > Locking is *already* per-reservation; `vm::reservation_lock` takes the
  > 128-byte line's own word and each entry has its own cache line. LSE was never
  > the missing piece, because the cost is which line an atomic touches rather
  > than how it is spelled. The contention is one `bit_test_set` on
  > `g_range_lock_bits[1]`, it is paid by `passive_lock`'s **readers** rather
  > than by the writer, and it was measured at 17.5% of all emulator spin — most
  > of which was then removed by fixing that site's backoff instead of
  > redesigning anything. This paragraph is kept because the reasoning that led
  > to it is instructive, not because its conclusion still holds.

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

## A publish-then-flag race in the semaphore fast cache

Found by applying this document's own advice — grep for the *shape*, not for an
ARM path, because there is no ARM path to read — to `kernel/cellos/`, the
subsystem the ledger's "architecture-neutral" sweep never actually scanned.

`sys_semaphore.cpp` keeps a 64-entry cache mapping a semaphore id to its
`lv2_sema*`, so a lookup can skip the id manager. Three operations touch it, and
every access in all three was `memory_order_relaxed`:

```cpp
// publish
entry.sema.store(sema, relaxed);
entry.sem_id.store(sem_id, relaxed);

// read
if (entry.sem_id.load(relaxed) != sem_id) return nullptr;
return entry.sema.load(relaxed);

// invalidate
if (fast_entry.sem_id.compare_exchange_strong(expected, 0, relaxed))
    fast_entry.sema.store(nullptr, relaxed);
```

**All relaxed is correct on x86 and a data race on AArch64.** TSO reorders
neither store-store nor load-load, so a reader that observed the new id was
guaranteed to observe the pointer written before it. AArch64 promises neither:

- the id store can become visible **before** the pointer store, so a reader
  matches the id and reads a stale or null pointer;
- the pointer load can be satisfied **before** the id load that is supposed to
  authorise it, so the check validates an id against a pointer read earlier.

Either way the caller dereferences a pointer that may belong to a destroyed
semaphore.

The fix is the textbook pairing, one ordered access on each side: the id store
becomes a **release**, the id load an **acquire**, and the pointer accesses stay
relaxed underneath them. The invalidate CAS becomes `acq_rel`.

**Acquire is sufficient here and RCpc does not weaken it.** The note above warns
that on this `armv8.4` baseline an explicit `memory_order_acquire` compiles to
`LDAPR` rather than `LDAR`, losing the RCsc StoreLoad property. That matters for
Dekker-shaped protocols; it does not matter here. This needs only the
synchronises-with edge from the matching release, which is exactly what release/
acquire is defined to give and what `LDAPR` implements. **Knowing which of the
two guarantees a site actually needs is what makes the distinction useful rather
than alarming.**

**Latent, not live.** The Eternal Sonata semaphore superpath defaults to
`disabled` and is enabled by a system property or environment variable, so no
shipped configuration reaches this today. It is fixed anyway: a race reachable by
setting one property is not meaningfully safer than one reachable by default, and
a use-after-free on a destroyed semaphore is not a good thing to leave armed
behind a flag someone will eventually set.

Two things worth carrying forward. **The statistics counters in the same file
stay relaxed and must**, which the contract test asserts explicitly — 45 of the
65 relaxed accesses in `kernel/` are hit counters that participate in no
protocol, and a uniform "fix the file" sweep would add cost for nothing while
obscuring the two accesses that genuinely carry ordering. And this is the third
find in the same family, after the reservation seqlock and the MFC DMA read:
**every weak-memory defect in this codebase has been an ordering that TSO
supplied for free, in code with no architecture-specific branch at all.** There
is nothing to notice when reading; only the shape gives it away.

## Correction: the range-lock bitmask does contend, on the reader side

Earlier in this work the shared-bitmask question was closed on evidence, on the
grounds that `vm_writer_lock` recorded **zero** spin calls across 5.9 million
waits: `writer_lock` always acquires first try, so there is no contention to
remove. **That conclusion was drawn from the wrong site.**

The measured second-largest spin source in the whole emulator is
`vm_passive_lock`, at **17.5% of all spin — 1.33 million calls, 13.9
core-seconds**. Reading what it waits for closes the loop:

```cpp
void passive_lock(cpu_thread& cpu) {
    ...
    for (u64 i = 0;; i++) {
        if (cpu.is_paused()) return;
        if (!get_range_lock_bits(true)) [[likely]] return;   // proceed once the word is zero
        if (i < 100) profiled_busy_wait(site::vm_passive_lock, 200);   // 10.42 us
        else std::this_thread::yield();
    }
}
```

It spins while `g_range_lock_bits[1]` is nonzero. And the **shared** `writer_lock`
path sets a bit in exactly that word:

```cpp
auto& bits = get_range_lock_bits(true);        // g_range_lock_bits[1]
...
range_lock->release(addr | u64{size} << 32 | flags);
if (bits != umax && !bits.bit_test_set(u32(diff))) break;
```

and the destructor holds it for the lock's whole lifetime:

```cpp
writer_lock::~writer_lock() noexcept {
    if (range_lock) {
        g_range_lock_bits[1] &= ~(1ull << (range_lock - g_range_lock_set));
```

**So every PUTLLC that takes a `writer_lock` stalls every thread entering
`passive_lock` for as long as it holds the lock.** The bit does not make the
writer wait — which is why `vm_writer_lock` reads zero — it makes the readers
wait, at 10.42 us per iteration, up to 100 iterations before yielding.

Two lessons, and the second is the more useful.

**The measurement was right and the inference was wrong.** `vm_writer_lock = 0`
is a true fact that says only "the writer never blocks". Reading it as "this
shared word is uncontended" required an assumption that was never checked: that
the writer is the only party affected by the word it writes. The site that pays
is on the other side of the protocol and has its own counter, which was sitting
in the same log line reading 17.5%.

**When a shared variable is suspected of contention, instrument every party that
reads it, not just the one that writes it.** The first pass looked at
`vm_writer_lock` and `vm_reservation_lock` because those are the names containing
"lock". `passive_lock` is the one that waits on the result.

**Status.** The bitmask redesign sketched earlier — have exclusive takers scan the
64 per-thread slots instead of consulting a shared summary word — is **reopened,
and now has a measured target**: 17.5% of all emulator spin, 13.9 core-seconds
per 200 seconds of play. It remains a change to the hottest lock in the memory
subsystem and still needs the correctness question answered (the `bits != umax`
test also detects a held exclusive lock). But it is no longer theoretical, and it
is no longer competing with `GETLLAR` for attention on a guess.

## Sweeping for the publish-then-flag shape, and what it found

The semaphore fast-cache race was found by chance while auditing an unscanned
directory. Since the shape is mechanical — a data store followed by a flag store,
then a flag load guarding a data load — it is worth searching for deliberately
rather than stumbling on. The signature that catches it is **two adjacent relaxed
stores to different atomics**.

Swept across the whole of `rpcsx/`. The sweep returned **two** sites, and the
useful result is how few:

**`SPUThread.cpp:802` — not a defect.** Seven relaxed stores publish descriptive
fields into a GETLLAR diagnostic bucket after a CAS claims it. A reader could see
a claimed bucket with stale fields, but the consumer is a statistics dump: the
fields are last-writer-wins and a torn read produces slightly stale diagnostic
output, not a dereferenced stale pointer. Left alone.

**`thor_rsx_auditor.h:154` — a real inversion, now fixed.** The pair is:

```cpp
g_cached_enabled.store(enabled ? 2u : 1u, relaxed);   // the flag
g_report_interval.store(parse_interval(...), relaxed); // the data
```

and `enabled()` short-circuits on `g_cached_enabled` being non-zero. So a second
thread could observe "already polled", skip polling, and read `g_report_interval`
still holding its default of 60 rather than the configured value.

**This one is wrong on x86 too**, which makes it a cleaner example than the
semaphore case. TSO preserves store order faithfully — and the store order itself
was backwards. No weak-memory subtlety is required; the flag was simply published
before the data it guards. Fixed by swapping the two and pairing a release with an
acquire on the flag.

Impact is small and worth saying so: it changes a diagnostic report cadence,
behind `RPCSX_THOR_RSX_AUDITOR`, which defaults off. It is fixed because it is two
lines and the same shape, not because it mattered.

**The negative result is the more valuable half.** One mechanical sweep across
every source file in the fork found exactly one live instance of the pattern, and
it was in default-off diagnostic code. Combined with the earlier audit — the SPU
reservation seqlock, the MFC DMA read, and the semaphore cache, all found and
fixed — the codebase now looks genuinely clean of this class rather than merely
unexamined. That is a different statement from "we looked and found nothing",
because this time the search space was defined by the shape rather than by which
files someone happened to open.

## All three weak-memory shapes, swept mechanically

This document's own advice is to grep for the *shape* rather than for an ARM
path, because there is no ARM path to read: **a validated re-read, a
double-check, a publish-then-flag**, and ask what TSO was providing for free.
Every defect found in this codebase came from one of those three. They have now
all been swept across the whole tree rather than encountered by accident.

### 1. Publish-then-flag — 2 sites

Signature: two adjacent relaxed stores to different atomics.

| site | verdict |
| --- | --- |
| `SPUThread.cpp:802` | benign — descriptive fields in a GETLLAR diagnostic bucket, last-writer-wins, consumed by a stats dump |
| `thor_rsx_auditor.h:154` | **real inversion, fixed** — flag stored before the data it guards, wrong on x86 too |

Plus the two already fixed before the sweep: the semaphore fast cache, and the
reservation seqlock fences.

### 2. Validated re-read — 2 sites

Signature: the same accessor loaded twice with work between, then compared.

| site | verdict |
| --- | --- |
| `SPUThread.cpp:3767` (MFC DMA) | **already fixed** — carries `atomic_fence_acquire()` before the validating read |
| `SPUThread.cpp:7421` | **safe by construction, and worth explaining** |

The second one looks like the seqlock shape and is not. It checks the version
*first* and reads the data second:

```cpp
if (!vm::check_addr(raddr) || rtime != vm::reservation_acquire(raddr))
    set_lr = true;
else if (!cmp_rdata(rdata, *resrv_mem))
```

The seqlock trap is a data read **sinking below** the validating counter read.
Here the data read is already after it in program order, and
`reservation_acquire` is an acquire load, which stops it moving **above**.
Version-then-data is the safe ordering; data-then-version is the one needing a
fence. **Two sites that pattern-match identically require opposite treatment, and
the deciding factor is which of the two reads comes first.**

### 3. Double-check — 0 hand-rolled instances

Signature: test, take a lock, test again.

The sweep found none, and the reason is structural rather than lucky. Lazy
initialisation in this codebase is done with **function-local statics**,
`static const auto x = []{ ... }()`, of which there are 413 across 25 files. C++11
requires those to be thread-safe, and the compiler emits a guard variable with
the acquire/release semantics already correct. There is no hand-rolled
double-checked locking here to get wrong on a weak-memory machine.

### What this closes

The weak-memory dimension is now swept **by shape across the entire fork**, not
by which files someone opened. Four defects total, all found and fixed: the SPU
reservation seqlock, the MFC DMA read, the semaphore fast cache, and the RSX
auditor inversion.

That is a stronger statement than the ledger could previously make. Its earlier
claim that `lv2` and the HLE modules were architecture-neutral rested on a grep
across **two directories that do not exist in this fork**, and scanning the real
one turned up both a live race and a second x86-only power path. The difference
is not diligence, it is that a shape-defined search cannot silently cover
nothing: if the pattern matches zero files, that is a fact about the pattern,
which is checkable, rather than a fact about a path list, which is not.

## The inline-asm audit: clobbers, and one dead label

Inline assembly is the one place where the compiler cannot check the work, and
this document already records one instance getting it wrong — the seven i-cache
sites whose `ISB`/`DSB` pair was neither `volatile` nor memory-clobbering, so the
compiler was free to move them across the very stores they existed to publish.
That made a full audit of every ARM inline-asm block worthwhile.

**Every block that compiles on this target is correct.** Checked against what
each instruction actually needs rather than by pattern:

| site | clobbers | verdict |
| --- | --- | --- |
| `rx/asm.hpp` `yield` | none | correct — a hint that touches no memory |
| `rx/asm.hpp` `mrs cntfrq_el0` | none | correct — reads a constant system register |
| `rx/asm.hpp` `ldaxr{,b,h}` ×8 | `"memory"` | correct |
| `rx/asm.hpp` `wfe`, `clrex` ×4 | `"memory"` | correct |
| `atomic.hpp` LSE2 `dmb`/`ldp`/`dmb` | `"memory"` | correct |
| `atomic.hpp` `ldaxp`/`stlxp` loops | `"memory"`, outputs `"=&r"` | correct — early-clobber is required here because the `CBNZ` branches back |

One block is sloppy and does not build here:
`rx/asm.hpp::trigger_write_page_fault`'s AArch64 arm is
`#elif defined(ARCH_ARM64) && !defined(ANDROID)`, so Android takes the generic
`fetch_or` instead. Its template `"ldset %w0, %w0, %1"` references `%0` twice and
`%1` once, leaving the third operand `"r"(value)` unused. Harmless, unreachable
on this target, and left alone rather than edited blind for a platform this fork
cannot test.

**One real wart, and it was mine.** The LSE2 16-byte load carried a `1:` label
with nothing branching to it — inherited from the `LDAXP`/`STLXP` form below,
where the `CBNZ` genuinely uses it. Numeric labels are local in GNU as, so
duplicates across inlined copies assemble fine and it was never a bug. It was
worse than a bug in one narrow sense: it *implied a retry loop* in the hottest
16-byte atomic in the emulator, which is precisely the property the LSE2 path
exists to remove. Removed, with a comment saying why the absence is deliberate so
it does not get "restored" for symmetry with the block below it.

The LSE2 contract test still passes, and the difference between the two blocks is
now visible at a glance: the exclusive form loops, the LSE2 form does not.
