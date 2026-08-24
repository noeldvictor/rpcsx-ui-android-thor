# Transformers at 18.7 FPS: where the frames are, measured

Part of the notes indexed from [`AGENTS.md`](../../AGENTS.md).

The 3D combat scene holds **18.7 FPS against its own 30 FPS cap**. This is the
first profile of that scene rather than of a title screen or an intro movie.

    tools/thor_profile_combat.sh

143,223 samples, 0 lost, 25 s, restored 3D combat, gated on `coresBusy>4.5`,
shipped configuration.

## Where the time goes

| share | object |
| --- | --- |
| **54.0%** | `unknown` - JIT-generated GUEST code, not file backed |
| 28.7% | `librpcsx-android.so`, the emulator |
| 11.7% | kernel |
| 2.8% | libc |
| **2.3%** | the Vulkan driver |

**The GPU driver is 2.3% of the profile.** That is the whole budget a driver
swap can compete for, and it is why Balemuni's Aurora measured as a null. No
Turnip build can matter here. See [`gpu-drivers.md`](gpu-drivers.md).

Inside the emulator's 28.7%, one cluster dominates. Resolved against the
unstripped library with `llvm-addr2line`:

| offset | symbol | share |
| --- | --- | --- |
| `+37764c0`, `+37764c8` | `atomic_storage<EnumBitSet<cpu_flag>>::load`, inlined in `writer_lock` | 8.43% |
| `+37764cc` | `vm::writer_lock::writer_lock` | 1.76% |
| `+3775edc`, `+37764c4`, `+3775b6c`, `+3863f00`, `+36e1280`, `+166ad60` | `rx::pause()` | ~8.3% |

**About 18% of all cycles are spinning on the VM range lock.**

## The two numbers that decide what to do next

**CPU total is 62 to 68%, not 100%.** About 5 of 8 cores are busy. The scene is
NOT compute saturated; it is SERIALISED. Threads are blocked, not working, so
there is idle capacity to reclaim.

**`stcx: stale128` climbs by about 365,000 per 10 s**, roughly 36,000 failed
reservation stores per second. That is the guest's PPU and SPUs colliding on the
same 128-byte lines, and it is what feeds the spin above.

## Levers measured against this, all null

| lever | result |
| --- | --- |
| `vm::writer_lock` spins/cycles tuning | null; every arm inside the control pair's spread |
| Balemuni Aurora GPU driver | null; the driver is 2.3% of the profile |
| `Accurate SPU Reservations: false` | **retracted.** A single run gave 19.30 and was reported as +3.8%. Repeated with the limiter fix it gave 18.90 and 18.70 against 18.80 and 18.70 baseline. It was noise. |
| SPURS `max_run` clamp 4 | 18.60 FPS, CPU 64.5 to 59.8%, stale128 UNCHANGED at 365k |
| SPURS `max_run` clamp 3 | 18.30 FPS, CPU 59.0%, stale128 unchanged at 360k |

The clamp result is the informative one: **the reservation conflict rate does not
depend on how many SPURS threads run.** So the contention is not SPU against SPU
on the job queue. Fewer threads simply do less work.

## Why shortening the spin cannot work

It converts spinning into yielding. The thread still waits, because the cost is
the CONTENTION, not the length of the pause. That is why the spins/cycles arm
measured as an exact null and why tuning it further is not worth device time.

## What 30 FPS would actually require

18.7 to 30 FPS is **+60% throughput**, so about 38% of per-frame CPU has to
disappear. Removing every spin cycle in `writer_lock`, all 18%, lands near 22
FPS. **The lock alone is not enough.** Over half the profile is guest code in the
JIT, which only comes down through better SPU and PPU code generation or through
the guest doing less work.

Anyone told that 30 FPS is one setting away should be shown this table.

## PhysX: there is nothing to patch from here

The title is Unreal Engine 3, which the log confirms via
`UnrealEngine3/TransGame/PS3Cache`, and UE3 on PS3 runs PhysX on the SPUs. But
the game creates exactly **six SPU threads, all `CellSpursKernel0` to `5`**, and
loads `libspurs_jq.sprx`, the SPURS job queue. Physics is dispatched as SPURS
JOBS on those same kernels, so there is no PhysX thread or group to throttle,
and no emulator-side switch for it. Separating physics jobs from rendering and
animation jobs would mean reverse engineering the job descriptors.
