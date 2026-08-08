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
