# The PPU precompile OOM, and a memory budget that does not bound the thing that grows

Odin Sphere (`BLUS31601`) does not finish its first-boot PPU compilation. It dies
at `module 60-ish of 93` with:

```
Abort message: 'Scudo ERROR: internal map failure (NO MEMORY) requesting 4KB'
signal 6 (SIGABRT), tid PPUW.1.2
```

Failing to map **4 KB** is the allocator's last gasp, not the size of the thing
that broke. Note also that the emulator is not killed by lmkd — this is the
process's own allocator giving up, so `am_kill` and low-memory heuristics will not
show it.

## Where it dies

Symbolized against the unstripped library, the interesting part of the backtrace is:

```
processRelocationRef        <- LLVM RuntimeDyld
try_emplace<>
Allocate
allocate_buffer
operator new
__libcpp_aligned_alloc      <- Scudo says no
```

That is the JIT object linker building its relocation map. And the module it was
linking had logged, one line earlier:

```
LLVM: 502556 functions generated (code_size=0x12228, num_func=3396, ...)
```

**502,556 generated functions from 3,396 guest functions.** Every other module in
the same run reports the two within a few percent of each other:

| generated | num_func | code_size |
| --- | --- | --- |
| 6323 | 6296 | 0x18ff8 |
| 6209 | 6082 | 0x18fe0 |
| 6538 | 6506 | 0x18ff8 |
| 5267 | 5217 | 0x18b20 |
| **502556** | **3396** | 0x12228 |

The code size is *smaller* than its neighbours while the generated-function count is
roughly 148x larger. Whatever that counter is measuring, this module is not like the
others, and it is the one that exhausts memory a second later.

This is suggestive rather than proven: the two facts are one log line apart, in the
same worker, on the same module. It has not been shown that the count causes the
relocation map to blow up.

## The budget exists and did not help

`ppu_precompile` sets one up:

```
PPU precompile memory budget: 1536 MB (total 15255 MB)
```

1536 MB on a device with **15 GB**. The cap is not the problem by itself — bounding
concurrent LLVM instances is reasonable — but two things about it are worth writing
down.

**The accounting is a heuristic over the wrong quantity.** `PPUThread.cpp:7095`
estimates a module's cost as guest function bytes times 16384:

```cpp
ppu_log.warning("LLVM: reporting used memory %u (free/total: %u/%u) ...",
    total_fn_size * 1024 * 16, memory_limit.free_memory(), memory_limit.total_memory(), ...);
auto used_memory = memory_limit.acquire(total_fn_size * 1024 * 16);
```

Guest bytes times a constant does not track what RuntimeDyld actually allocates for
relocations, which is what ran out. On the failing module the estimate came to
1,677,197,312 bytes — **larger than the entire 1,610,612,736 byte budget**.

**`acquire` is correct about that, which is worth saying because it looks wrong.**

```cpp
if (value >= amount || value == m_total)
```

The `value == m_total` arm is what saves an oversized request: when a request
exceeds the whole budget, the thread waits until every other user has released, then
saturating-subtracts to zero and proceeds alone. So an over-budget module is not a
deadlock and not an assert. It is admitted, deliberately, as a sole user. The budget
therefore bounds *concurrency*, not peak footprint — and peak footprint is what
Scudo refused.

## What this is not

It is not the Eternal Sonata boot deadlock in
[`rsx-boot-hang.md`](rsx-boot-hang.md). That one is an SPU reservation loop that
never settles, with two threads pegged and no memory growth. This one is a PPU
compile worker that allocates until the allocator fails. Different title, different
subsystem, different signature.

It is also not established as a regression, and it is not clean-room: another
emulator (Xenia) was resident during this run, and the system showed 11 GB of 15 GB
used. Xenia itself was idle at 95 MB, so it is not a plausible cause of a
multi-gigabyte shortfall, but the run was not on an otherwise-quiet device and
should be repeated on one before any number here is treated as a threshold.

## Next

- Repeat on a quiet device, and record the process RSS over the compile rather than
  only the budget's own accounting. The budget reports what it *thinks* is in use;
  nothing currently records what actually is.
- Find out what `502556 functions generated` is counting, since either the counter is
  wrong or that module really does explode, and those want different fixes.
- If it is real growth, the lever is the estimate at `PPUThread.cpp:7095` or the
  worker count, not the 1536 MB cap — raising a cap that admits oversized modules
  anyway will not change the outcome.

## The worker count lever is now taken, 2026-08-13

`jit_core_allocator::limit()` was upstream's: the thread count, and nothing else.
**Eight LLVM workers on this device, with no reference to memory at all.** The
budget above bounds concurrent *estimates*; it never bounded the number of workers
that the estimates come from.

ARMSX3 hit the same Scudo failure on two titles and fixed it twice, in `903220790`
and `e7606bda0`. Their second set of numbers is now here: reserve 2 GB for the
emulator, then 1.5 GB for each worker, measured against `MemAvailable` instead of
installed memory. Two differences from their patch. It reuses
`utils::get_memory_usage()`, which already reads `MemAvailable` in this tree. And it
is `#ifdef ANDROID`, so the Windows build keeps the upstream count.

Their reasoning, which is worth keeping: total memory is the wrong number on a phone
that also holds everything else the user runs, one large PPU module can take more
than a gigabyte through MCJIT and relocation processing, and the reading happens
before the emulator maps the PS3 address space.

**This is unmeasured here, and it is a trade, not a win.** It lowers the default
compile parallelism, so a cold precompile takes longer. The argument for it is that
a run which finishes beats a run which aborts. `Max LLVM Compile Threads` still
overrides it.

## First observation on device, 2026-08-13: the budget is live and chose 4

A cold Folklore boot with the title cache parked ran **four** PPU compile
workers, `PPUW.1.1` through `PPUW.1.4`, with `Max LLVM Compile Threads: 0` in the
config, which means the automatic path. Before this change that path returned the
thread count, which is **8** on this device. So the budget applies, and it is not
the core count.

Four is consistent with the arithmetic at the memory the device actually had:
`(avail - 2 GB) / 1.5 GB = 4` needs about 8 GB available, and the other session's
emulator was resident for this boot. A reading taken while the device was quiet
gave `MemAvailable` of 10.3 GB, which predicts 5. **Neither number is a
measurement of the fix's value** — they only show the code runs and the count
moved off the core count.

The same boot reproduced the oversized-module case this document is about:

```
PPU: LLVM: reporting used memory 1677524992 (free/total: 0/1610612736)
```

That is the request being larger than the whole budget, admitted as a sole user,
exactly as the `value == m_total` arm describes above. It did not abort.

**What to measure, and it needs Odin Sphere rather than a synthetic clear.** Boot
`BLUS31601` cold and record two things: whether it passes module 60 of 93, and the
worker count the allocator chose. The second is the one to check first, because a
device with plenty free will still choose several workers and will not test the
change at all. That is this repo's own rule about proving that the arm you think you
are running is the arm that runs.

## The cause named exactly, 2026-09-21: Scudo's per-size-class region

A second Odin Sphere cold boot died the same way, 10 seconds after `boot ok`,
with the worker-count lever in. This time the allocator said what it ran out
of, one line before the 4 KB message:

```
Scudo OOM: The process has exhausted 256M for size class 262160.
Scudo ERROR: internal map failure (NO MEMORY) requesting 4KB
Fatal signal 6 (SIGABRT) in tid 7880 (LLVM JIT)
```

The size-class table printed with it holds the number that matters:

```
F 38 (262160): mapped: 261888K ... inuse: 1022 total: 1022
```

Android's Scudo gives every primary size class a fixed region of 256 MB
(`PrimaryRegionSizeLog = 28` in the Android config, set at build time, not
tunable). The 256 KB class had 1,022 blocks live, which is the whole region.
The process had gigabytes free. The system was not out of memory; one size
class was.

So the two levers in this document work against the odds, not the cause:

- The worker count lowers how many relocation maps are live at once. It ran
  with the lever in and still hit 1,022 live 256 KB blocks.
- The 1536 MB budget counts estimates. It cannot see a size class.

The fix has to move those 256 KB allocations out of Scudo's primary allocator
or cut their count. Candidates, in order of size:

1. Find what allocates 256 KB blocks in the LLVM JIT thread during PPU
   linking. LLVM's `BumpPtrAllocator` slabs grow in powers of two and reach
   256 KB; the RuntimeDyld relocation map in the earlier backtrace is one
   user. A `MallocAllocator` replaced by an `mmap`-backed one for slabs at or
   above 64 KB leaves Scudo's regions alone.
2. Override `operator new` for sizes at or above 64 KB with `mmap`, process
   wide. Wider, and it changes every large allocation.
3. Serialize PPU module linking, so at most one relocation map is live. Slow,
   and it still fails on a single module that needs more than 1,022 blocks.

The RSX thread died a moment later with `VK_ERROR_MEMORY_MAP_FAILED`, which is
the same exhaustion reached from a Vulkan map.

Log source: logcat of pid 7704, 2026-09-21 19:13:41 to 19:13:52.

## The cause, measured, and the fix, 2026-10-03

The 256 KB class was the last class to fill, not the first. The thing that grew was
the PPU **symbol resolver**, and the measurements say so directly.

**What the "functions generated" count is.** It is
`_module->getFunctionList().size()`, so it counts declarations too. The module that
closes a JIT group (100 modules) gets `__resolve_symbols`
(`PPUTranslator::GetSymbolResolver`). That function holds a table of pointers to every
function of the group, so the module declares all of them: Watch_Dogs (BLUS31176)
559,355 in one group, Odin Sphere (BLUS31601) 502,556. Every other module reports
about 1.0 to 1.1 functions per guest function.

**Why that runs out.** Each table entry is an external-symbol relocation. LLVM's
RuntimeDyld keeps one `StringMap` entry per external symbol, and its value is a
`SmallVector<RelocationEntry, 64>`, about 3 KB, until the group is finalized. That is
about 1.7 GB of 3 KB blocks in one link. Scudo's 256 MB region for that class fills,
Scudo retries each larger class until the 256 KB one is full too ("exhausted 256M for
size class 262160"), and then it maps every further block on its own.

**The map count, sampled every 2 s on a Watch_Dogs cold compile.** For 7 minutes the
process held 4,350 to 4,550 maps, with RSS about 1.2 GB. Then, in under 2 s, it went to
65,531 maps (the kernel's `vm.max_map_count` is 65,530) and RSS to 3.3 GB, and Scudo
aborted: "internal map failure (NO MEMORY) requesting 8KB", SIGABRT in the `LLVM JIT`
thread, with 8 GB free.

**The fix.** A JIT group with more than 32,768 functions (`c_thor_lookup_min_funcs`,
Android only) gets no `__resolve_symbols`. After the link, `ppu_initialize` looks up
each `__0x<pc>` symbol in the group's engine and stores the same value the generated
loop stores: `(seg0 << 35) | host` at `exec + (pc << 1)`, with `seg0` added to `pc`
for a relocatable module. A new settings bit, `thor_symbols_by_lookup_v1`, gives the
changed module a new object name, so only one module per such group recompiles and
every other title keeps its cache.

The lookup uses `ExecutionEngine::getPointerToNamedFunction`, not
`getGlobalValueAddress`. The second one finalizes on every call, and that cost
24 us per lookup in a 600,000-function group: 34 s of a warm Watch_Dogs boot. The
first one does not, and the same fill takes 0.43 s.

| Title | Groups filled from C++ | Functions | Fill time | Result |
| --- | --- | --- | --- | --- |
| Watch_Dogs (BLUS31176) | 4 | 612,847 + 550,431 + 559,310 + 102,061, 0 not found | 0.43 s | Cold compile: no abort, peak 6,937 maps, RSS 2.2 GB. Reaches its title screen for the first time on this device. |
| Odin Sphere Leifthrasir (BLUS31601) | 1 | 502,542, 0 not found | 0.18 s | First frame 12 s after boot; largest module now 3,440 functions. |

The earlier mitigations stay: the worker count and the 1536 MB budget limit
concurrency, and `b9bfafca0` sends LLVM container buffers of 64 KB and more to `mmap`.
None of them could fix this case, because one link needed 1.7 GB of small blocks.
