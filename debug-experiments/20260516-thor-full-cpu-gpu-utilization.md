# Thor Full CPU/GPU Utilization Research

- Status: `active`
- Target device: AYN Thor Base/Pro/Max, Snapdragon 8 Gen 2 / Adreno 740
- Proof device: Thor Max first
- Emulator target: RPCSX Android fork with upstream RPCS3 ARM64 ideas
- Created: 2026-05-16

## Goal

Make the emulator use the AYN Thor intelligently, not merely show high aggregate
CPU/GPU percentages. For PS3 emulation, "full utilization" should mean:

- the PPU, hottest SPU workers, RSX, and audio/frame pacing threads are not
  waiting on avoidable host scheduling stalls;
- CPU0-2 little cores do not steal latency-critical Cell/RSX work;
- the Adreno GPU is fed with long enough Vulkan work to be useful, without
  adding CPU/GPU sync bubbles;
- shader/JIT/cache work happens before or beside gameplay without pushing the
  real-time threads into thermal throttling;
- every speed path preserves field, battle, and menu correctness.

Raw 100% CPU can be bad if it is busy waiting, oversubscribed LLVM compilation,
or bad affinity. Raw high GPU can be bad if it is pointless barriers, readbacks,
or slow shader churn. The metric is playable frame time plus correctness.

## Hardware Baseline

Official AYN product text lists Thor as a 6 inch dual-AMOLED Android 13 handheld
with a Snapdragon CPU and 6000 mAh battery. The current product page maps SKUs:

- Lite: Snapdragon 865, 8+128 GB UFS 3.1
- Base: Snapdragon 8 Gen 2, 8+128 GB UFS 3.1
- Pro: Snapdragon 8 Gen 2, 12+256 GB UFS 3.1
- Max: Snapdragon 8 Gen 2, 16+512 GB or 16+1 TB UFS 3.1

Qualcomm's Snapdragon 8 Gen 2 product brief confirms Vulkan 1.3, OpenGL ES 3.2,
and OpenCL 2.0 FP API support. The connected Thor in this repo has already
reported `QCS8550`, `kalama`, `Adreno (TM) 740`, and about 15.6 GB RAM.

Measured Thor CPU topology in the existing notes:

| CPU | Core family | Mask bit | Suggested role |
| ---: | --- | ---: | --- |
| 0-2 | Cortex-A510 | `0x07` | Android/UI/background only |
| 3-4 | Cortex-A715 | `0x18` | sustained high-performance work |
| 5-6 | Cortex-A710 | `0x60` | sustained high-performance work |
| 7 | Cortex-X3 | `0x80` | one latency-critical thread |
| 3-7 | perf + prime | `0xF8` | first heavy-work process mask |

## PS3 Bottleneck Shape

The Cell Broadband Engine is not a normal multicore CPU. IBM/Sony/Toshiba's Cell
work describes one PPE/PPU for control plus eight SPEs/SPUs designed for
data-parallel work, each with a private local store and DMA/synchronization
behavior. PS3 games commonly use the PPU to orchestrate SPU jobs, events,
semaphores, DMA, and RSX work.

RPCS3's official ARM64 announcement is important but limited for this fork:

- official RPCS3 now ships Linux ARM64 and macOS ARM64 binaries;
- its Linux ARM64 target requires ARMv8.2-A, 8 GB RAM, and OpenGL 4.3 or Vulkan;
- official RPCS3 explicitly does not target Android/iOS at this time;
- RPCSX-UI-Android is an experimental Android native UI around the RPCSX
  ecosystem, so we should treat it as a research fork, not official RPCS3.

The likely bottlenecks on Thor are:

- SPU LLVM code quality on AArch64;
- PPU/SPU synchronization around SPURS, events, semaphores, reservations, and
  timers;
- Android scheduling of emulator-critical threads across heterogeneous cores;
- Vulkan/Adreno barriers, shader/pipeline churn, texture flushes, and
  render-target traffic;
- first-boot cache/JIT/shader compilation memory pressure.

## Current Local Starting Point

Already present in this fork:

- `ThorPerformanceProfile` applies heavy process affinity `0xF8`.
- Thor defaults use SPU LLVM, SPU cache, `Use LLVM CPU = cortex-a78`, and a low
  LLVM compile-thread count.
- Android wrapper exposes `setProcessAffinityMask(...)` through JNI and applies
  `sched_setaffinity` to `/proc/self/task` threads.
- Core-side Android affinity intersects configured PPU/SPU/RSX masks with the
  runtime process/thread mask.
- AArch64 JIT feature gating passes `+dotprod` when `HWCAP_ASIMDDP` is present
  and avoids unsafe SVE target CPUs when Android does not report SVE.
- SPU reduced-loop detection/emission exists behind Android debug properties.
- Eternal Sonata SPURS probes already found heavy start/join churn and a
  promising direct semaphore fast-path candidate in the Windows lab.

Current profile result: `Video@@Multithreaded RSX` should stay false for Eternal
Sonata. The 2026-05-16 Thor Max field A/B reached correct-looking visuals but
dropped from the NeutralCore `16-18 FPS` band to about `12.71 FPS` and added a
hot `RSX Offloader` thread. Keep RSX threading as an opt-in diagnostic only.

The direct semaphore fast path also proved hot but not decisive: about `98k`
fast wait/post hits by field time, correct-looking field visuals, but no FPS
gain versus Off. That means the next "full utilization" work should target
SPU/MFC loops, reduced-loop/codegen, scheduler behavior, or RSX/Vulkan traffic
rather than simply making tiny syscall wrappers cheaper.

Android DMA/MFC verification now agrees with the Windows lab on the first field:
the hot Eternal Sonata image is `0x958dfe208b686622`, hot PCs are `0x25cc` and
`0x451c`, and sampled RSX-local DMA bytes are still `0`. Verify mode found no
output mismatches but also no exact reusable job-output hits, so the first
simple cache/replay idea is not the speed lever. A narrow MFC/list GET copy
fast path was correct-looking at about `17.59 FPS`, but still inside the
NeutralCore `16-18 FPS` band.

The scheduler matrix has an early negative: `OldNeutral` and `AltNeutral`
RPCS3 scheduler profiles, even without SPU reservation busy-wait, crawled around
`2.2 FPS` in the story/tree route and saturated `rsx::thread`. Keep Eternal
Sonata on OS scheduling until a trace proves a narrower per-thread change.

The first positive utilization signal is SPU reduced-loop emission. After
splitting its cache key to `spu-safe-thor-rl-v1-tane.dat` and restoring the
normal `spu-safe-v1-tane.dat`, Thor Max field captures reached about
`19.86 FPS` cold and `19.61 FPS` warm with correct-looking visuals; the pause
overlay/menu proof reached about `20.18 FPS`. This is not the huge target yet,
but it is the strongest measured reason to keep pushing SPU codegen.

## The Smart Route

### 1. Measure Thread Reality Before Tuning

Add or use a Thor trace mode that records, per second:

- emulator thread name, TID, class, affinity mask, current CPU, and priority;
- PPU/SPU/RSX/audio/JIT/shader worker frame-time slices;
- FPS, frame pacing, audio underruns, RAM, temperature, and thermal throttle
  state;
- Vulkan queue busy time and Adreno counters through AGI where available.

Use Perfetto for scheduler/CPU/memory timelines and AGI for GPU counters and
Vulkan frame analysis. If CPU hot threads are asleep while FPS is bad, this is a
synchronization problem. If CPU is hot and GPU idle, this is SPU/PPU/JIT. If GPU
is hot and CPU waiting, this is RSX/Vulkan/driver.

### 2. Run A Thor Scheduler Matrix

Do not chase one magic mask. Test these as named, reversible presets:

| Preset | PPU | SPU | RSX | General | Notes |
| --- | --- | --- | --- | --- | --- |
| Current | CPU4 | CPU5-6 | CPU7 | CPU3 | Existing direction; good baseline |
| PPU Prime | CPU7 | CPU5-6 | CPU3-4 | CPU3-4 | Tests PPU latency dominance |
| SPU Wide | CPU7 | CPU3-6 | CPU4 | CPU3 | Tests SPU throughput dominance |
| Cool Sustained | CPU3-4 | CPU5-6 | CPU7 | CPU3 | Lower prime pressure |
| RSX MT Test | CPU4 | CPU5-6 | CPU7 | CPU3 | Same as current but `Multithreaded RSX=true` |

Keep process mask `0xF8` for these tests, but record whether Android actually
honors each per-thread mask. Android's official ADPF guidance cautions against
hard affinity as a general product strategy; for this single-device research
fork, affinity is still useful as an experiment gate if we verify it in traces.

Current result: broad RPCS3 scheduler modes lost badly for Eternal Sonata on
Thor. Future scheduler work should be narrower: thread-class affinity, wake
latency probes, and Android performance hints instead of swapping the emulator
scheduler globally.

### 3. Add Android Performance Hint Sessions

Android's Performance Hint API lets an app group long-lived workload threads and
report actual versus target work duration. Add an optional native/Java bridge
for:

- real-time emulation frame session: PPU, hot SPU, RSX, audio;
- background cache/compiler session: LLVM compile and shader workers.

Use it as a companion to affinity, not a replacement. It gives Android a cleaner
signal than fake busy loops and may improve ramp-up and sustained behavior.

### 4. Spend CPU Work On SPU Codegen And SPURS Hot Paths

Highest value CPU work:

- continue upstream RPCS3 SPU reduced-loop parity behind
  `debug.rpcsx.thor.spu_reduced_loop_emit`;
- mine hot SPU image hashes and loops from Eternal Sonata;
- validate AArch64 `sdot`/`udot` paths for SPU `GB`, `GBH`, `GBB`, and `SUMB`;
- port the direct semaphore fast path only after Windows A/B timing is
  normalized, then gate it per title/signature on Thor;
- avoid broad reservation-notifier rewrites until the previous `SIGBUS` area is
  instrumented first.

### 5. Use Adreno For The Right Work

Adreno/Turnip is tile-mode/GMEM-oriented and UMA. That means Vulkan wins come
from fewer state changes, fewer barriers, fewer readbacks, better shader caches,
and render-pass shapes that do not thrash system memory.

GPU compute offload should not start as "run the SPU emulator on GPU." The only
viable first version is a title/signature-gated superpath:

1. identify a stable SPU image hash, DMA pattern, PPU callsite, or RSX resource
   flow;
2. run normal CPU/SPU path and candidate GPU path in verify-only mode;
3. compare output bytes/hashes;
4. enable fast mode only after clean field, battle, and menu checks.

Good targets: large transforms, swizzles, texture prep, decompression, particles,
skinning, or render-prep data consumed by RSX. Bad first targets: tiny SPURS
control loops, immediate semaphore wrappers, and anything requiring frequent GPU
readback.

## First Sprint Recommendation

1. Keep the scheduler matrix code path, but do not promote RPCS3 scheduler
   modes for Eternal Sonata; OS scheduling is the known-good default.
2. Add a low-overhead native trace marker layer for PPU/SPU/RSX/JIT/shader/SPURS
   phases, plus thread class/mask/current CPU logging.
3. Continue the reduced-loop/codegen path with clean cache separation and add
   first-battle validation before calling it a speed win.
4. Repeat the winning CPU preset on one A6xx/A7xx Turnip build.
5. Use the result to choose the next code path:
   - CPU saturated, GPU idle: SPU reduced-loop/codegen/MFC/scheduler fast path.
   - GPU saturated, CPU waiting: RSX Vulkan barrier/pipeline/render-scale work.
   - both underused with bad FPS: SPURS/event/timer synchronization path.

## Paper Delta

Follow-up research is captured in
`debug-experiments/20260516-vulkan-adreno-paper-delta.md`. The important extra
angles are `VK_QCOM_tile_shading`, Vulkan dispatch overhead and kernel fusion,
compute/graphics overlap measurement, frame-to-frame tile coherence, reusable
SPIR-V/compiler infrastructure for GPU superpaths, and presentation/frame-pacing
measurement.

## Ghidra And Static Analysis Delta

Follow-up Ghidra/tooling research is captured in
`debug-experiments/20260516-ghidra-ps3-tooling.md`. The important practical
change is that Ghidra work must start from runtime anchors: hot SPU PC/image
hash/block, PPU module/address, or RSX callsite. For the current Eternal Sonata
field bottleneck, the first static target is the SPU `GETLLAR`/reservation retry
loop, not broad whole-game decompilation.

## Current Thor Field Results

The latest field-scene experiment ledger is
`debug-experiments/20260516-eternal-sonata-thor-field-hotpath-results.md`.
Important outcome: RSX depth texture-barrier skipping was only a small win,
semaphore fast path was neutral, and global ARM64 busy-wait batching lost FPS.
Next speed work should be callsite-specific SPU MFC/PUTLLC, RSX FIFO, VM
reservation, or generated-code timing surgery rather than broad `rx::busy_wait`
changes.

## Sources

- AYN Thor product page: https://www.ayntec.com/products/ayn-thor
- AYN homepage Thor summary: https://www.ayntec.com/
- Qualcomm Snapdragon 8 Gen 2 product brief:
  https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Snapdragon-8-Gen-2-Product-Brief.pdf
- Qualcomm Snapdragon OpenCL optimization guide:
  https://docs.qualcomm.com/bundle/publicresource/80-NB295-11_REV_C_Qualcomm_Snapdragon_Mobile_Platform_Opencl_General_Programming_and_Optimization.pdf
- IBM Cell Broadband Engine paper:
  https://research.ibm.com/publications/cell-broadband-engine-processor-design-and-implementation
- IBM/IEEE Cell synergistic processing paper:
  https://people.eecs.berkeley.edu/~kubitron/cs258/handouts/papers/cell_2006_ieeemicro.pdf
- RPCS3 official ARM64 announcement:
  https://blog.rpcs3.net/2024/12/09/introducing-rpcs3-for-arm64/
- RPCS3 configuration wiki:
  https://wiki.rpcs3.net/index.php?title=Help:Configurations
- RPCSX-UI-Android GitHub:
  https://github.com/RPCSX/rpcsx-ui-android
- Android Performance Hint API:
  https://source.android.com/docs/core/perf/performance-hint-api
- Android NDK Performance Hint API:
  https://developer.android.com/ndk/reference/group/a-performance-hint
- Android GPU Inspector:
  https://developer.android.com/agi
- Android GPU counters:
  https://developer.android.google.cn/agi/sys-trace/counters?hl=en
- Mesa Freedreno/Turnip docs:
  https://docs.mesa3d.org/drivers/freedreno.html
