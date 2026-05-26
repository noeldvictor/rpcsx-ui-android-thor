# AYN Thor vs PS3: Emulation, Translation, Recompilation, And Novel Offload Paths

- Status: `research-report`
- Created: 2026-05-19
- Platform gate: Windows-only for new GPU-shift experiments until the 200% moving-gameplay gate is met.
- Canary: Eternal Sonata `BLUS30161`

## Executive Read

The right mental model is not "emulation or translation?" It is layered
emulation:

- exact emulation for externally visible PS3 behavior, timing-sensitive
  synchronization, memory ordering, exceptions, atomics, syscalls, and RSX
  correctness;
- dynamic recompilation for PPU and SPU guest code;
- title/signature-gated HLE or superpath translation for repeated SPU kernels,
  MFC/DMA shapes, and RSX-local helper work;
- Vulkan translation for RSX graphics, with mobile tiler locality as the main
  Adreno prize;
- optional GPU compute only for bulk, batched, verified work whose result either
  stays near RSX/Vulkan or is large enough to amortize dispatch, barriers, and
  readback.

The interesting novel lane is a recognized-kernel translation system, not a
general PS3-to-GPU rewrite. Treat each hot SPU/RSX-adjacent pattern as a
candidate kernel with a proof envelope: input ranges, output ranges,
dependencies, synchronization contract, consumer timing, CPU SIMD target, and
Vulkan/SPIR-V target. CPU remains authoritative until the GPU or HLE target
passes shadow verification repeatedly.

## Hardware Comparison That Matters

AYN's current Thor page lists the device as a 6 inch dual-AMOLED Android 13
handheld with a 6000 mAh battery. The current AYN SKU table says Lite is SD865,
while Base/Pro/Max use Snapdragon 8 Gen 2 with 8/12/16 GB RAM and UFS 3.1
storage options. Qualcomm's Snapdragon 8 Gen 2 brief gives the CPU shape as one
Cortex-X3 prime core, four performance cores, and three efficiency cores, plus
an Adreno GPU with Vulkan 1.3, OpenGL ES 3.2, and OpenCL 2.0 FP support.

The PS3 is different in kind, not just slower in clock speed. IBM describes
Cell BE as a heterogeneous 9-core design; the formal architecture splits storage
into SPU local storage and main storage, with MFC DMA transfers as the intended
path between them. The Cell architecture also has detailed atomic and ordering
rules for MFC get/put and reservation commands. That is exactly why "just
translate everything" is dangerous: many PS3 games are written around local
store, DMA, tag waits, reservations, SPURS jobs, semaphores, and RSX interaction.

Thor's strengths:

- much more RAM than PS3;
- modern out-of-order ARM cores;
- AArch64 NEON/dotprod paths;
- a mobile Vulkan GPU that is fast when fed coherent work;
- Android tooling for deployment, screenshots, Perfetto-lite, and driver swaps.

Thor's weaknesses for PS3:

- fewer truly high-performance CPU cores than the PS3's intended SPU parallel
  job model might imply;
- no native Cell local-store/DMA engine;
- JIT/code cache and shader cache pressure inside Android;
- mobile thermals and shared CPU/GPU memory bandwidth;
- Adreno tiler behavior where broad barriers, render-pass breaks, and readbacks
  can cost more than the arithmetic we hoped to accelerate.

## Why Pure Emulation Is Necessary

Purely semantic emulation is still the baseline because the PS3 exposes behavior
that games rely on:

- PPU PowerPC execution and memory ordering;
- SPU local-store execution;
- MFC DMA commands, tag status, barriers, and list transfers;
- GETLLAR/PUTLLC reservation behavior;
- syscalls, SPURS, events, semaphores, timers, and audio/video pacing;
- RSX command ordering and read/write buffers such as WCB;
- game-specific timing traps.

Our own history backs this up. The direct rtime-keyed reservation-notifier port
previously crashed with a deterministic `SIGBUS BUS_ADRALN`. That is the kind
of bug a "faster translation" can create if it changes a memory-ordering edge
the game actually observes.

## Why Recompilation Is The Mainline

Dynamic recompilation is the only plausible everyday strategy for PPU/SPU
execution on Thor. RPCS3's own ARM64 work is evidence that native AArch64
support matters, but its official blog also says Android/iOS are not their
current target. Our fork therefore needs to mine upstream ARM64 compiler/runtime
work while accepting Android-specific packaging, scheduler, memory, and driver
constraints.

For Eternal Sonata, the strongest measured speed signal remains SPU
reduced-loop/codegen, not GPU compute. The existing local evidence says:

- hot image: `0x958dfe208b686622`;
- hot PCs include `0x25cc`, `0x451c`, `0xa74`, and `0xad8`;
- MFC/DMA wrapper and dynamic `MFC_Cmd` costs are real but too small to be the
  breakthrough alone;
- sampled direct RSX-local traffic from those SPU probes remains zero;
- reduced-loop u4 is the first real Thor speed movement, while semaphore and
  MFC wrapper shortcuts were correctness-useful but not FPS-changing.

So the immediate "translation" target should be:

1. exact SPU interpreter/recompiler remains authoritative;
2. recognized loops get better AArch64 codegen or title-gated HLE;
3. only after we have stable job capsules do we test GPU/SPIR-V as a competing
   backend.

## Why RSX Is Already "On GPU" But Still Not Enough

Stock RPCS3 already translates RSX graphics to host GPU APIs such as Vulkan.
The new work is not "put RSX on GPU" in the naive sense; it is GPU residency:

- fewer CPU/GPU drain points;
- fewer render-pass breaks;
- fewer broad image/barrier transitions;
- fewer host-visible transfer ping-pongs;
- more render-target, texture, and depth feedback state staying in Vulkan
  resources;
- more work kept inside one renderpass/tile-local lifetime.

Our current Windows stack:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 `
  -Action WindowsScene `
  -Scene battle `
  -WindowsInputBackend PadApi `
  -WindowsRsxTextureBarrier DepthReadOnly `
  -WindowsRsxBlitSourceResolve Fast `
  -WindowsRsxDepthFeedback KeepReadOnly `
  -WindowsRsxAuditor 60 `
  -WindowsGameScreen 1 `
  -MaxSeconds 330
```

This now has field, Options/menu, and first-battle visual proof on Windows. It
is durable `gpu-migration-credit` for RSX residency/locality. It is not a 200%
speed proof, and it does not count as promoted CPU/SPU replacement bytes.

The remaining RSX debt is precise: `blit_src_to_general` render-pass breaks.
That points at renderpass-local/tile-local resolve/blit architecture, not more
one-dispatch compute blits.

## What Academia Suggests

### Binary Hotspot To GPU: Useful, But Only After Profiling

GXBIT proposes a two-phase model: profile/extract hot spots from binary code,
prove they have suitable dependence properties, then map those hot spots to GPU.
That maps well to our `GpuSuperpathScout`, but with one important warning: the
first phase is the product. We need much stronger candidate proof before GPU
dispatch deserves trust.

Project translation:

- use Windows to record job capsules;
- classify dependencies, DMA shape, output ranges, and consumer timing;
- generate CPU SIMD and GPU variants only for stable kernels;
- keep CPU authoritative during shadow verification.

### Throughput-Oriented GPU Binary Translation: Only If We Can Batch

VectorVisor shows that binary translation to GPU can work when many copies of
similar work run concurrently. CuLE's GPU Atari emulator shows the same lesson
from emulation: huge throughput comes from batching many environments and
keeping frames/data on GPU.

Project translation:

- one latency-sensitive PS3 instance is the opposite of CuLE's best case;
- a single SPU DMA helper is too small;
- many repeated particles, skinning chunks, texture swizzles, decode blocks, or
  RSX-local postprocess blocks could fit;
- GPU verification can run in the background before fast mode exists.

### CPU SIMD Is A Serious Competitor To GPU

Parsimony and ISPC-style work argue that SPMD structure can be mapped cleanly to
CPU SIMD through compiler IR. For Thor, a recognized SPU kernel should usually
try AArch64 NEON/dotprod first. It has lower launch overhead than Vulkan
compute, avoids CPU/GPU synchronization, and transfers directly into the current
SPU recompiler pipeline.

Project translation:

- build a small `spu-kernel-ir` that can lower to AArch64 SIMD first;
- only add a SPIR-V backend when the job is big or GPU-consumed;
- compare CPU SIMD and GPU on the same captured job capsules.

### Vulkan As Compiler Target Is Plausible Now

Recent OpenMP-to-Vulkan work shows a high-level compiler/runtime path to Vulkan
compute, including embedded/mobile GPUs. MLIR's SPIR-V dialect shows the
compiler ecosystem has a real path for structured IR to SPIR-V. This supports a
future recognized-kernel compiler, but not a first step of translating raw SPU
control flow directly to arbitrary Vulkan shaders.

Project translation:

- use handcrafted GLSL/SPIR-V for the first one or two kernels;
- keep the long-term design as `recognized SPU/RSX kernel -> small IR ->
  AArch64 SIMD or SPIR-V`;
- cache pipelines and descriptors persistently;
- avoid CPU readback unless the job is explicitly a verification lane.

### Mobile GPU Synchronization Is The Trap

Qualcomm's Adreno material warns that local memory and barriers can erase the
benefit of low-latency access. Khronos Vulkan docs make the same point from the
API side: synchronization is explicit and memory dependencies/layout transitions
are real work.

Project translation:

- dispatch count, barrier count, submit count, and readback count are first-class
  metrics;
- a GPU path with more synchronization than the CPU path is a regression even if
  it looks like "using the GPU";
- RSX-local wins should first remove render-pass breaks and global transitions.

### Shared Compute/Graphics Is A Future Prize

VUDA is CUDA/Vulkan research, not an Android Adreno feature we can just import.
Still, the idea matters: compute/graphics wins depend on shared scheduling and
shared memory without copy-heavy ping-pong. For us, that means GPU offload
should live inside the existing Vulkan renderer/device lifetime whenever
possible.

## Novel Directions Worth Trying

### 1. SPU Job Capsules

Create a Windows-only recorder for hot SPU jobs:

- title ID, SPU image hash, PC/block hash;
- input LS ranges and EA ranges;
- output LS/EA ranges;
- MFC command shapes and tag waits;
- reservation addresses if any;
- first CPU consumer and first RSX consumer;
- per-job wall time and repeat count;
- output hash.

This creates a replayable benchmark corpus without touching Android. It also
turns "could this be GPU?" into a measurable question.

### 2. Dual-Backend Shadow Verifier

For each capsule:

- run stock CPU/SPU path;
- run candidate CPU SIMD/HLE path;
- optionally run candidate Vulkan path;
- compare output bytes or structured hashes;
- log mismatch, timing, dispatch/barrier/readback cost, and consumer delay.

Fast mode only exists after the verifier has repeated clean results across
field, menu, and first battle.

### 3. Recognized-Kernel IR

Define a tiny IR for stable SPU kernels, not a generic SPU compiler:

- vector load/store from LS slices;
- affine address increments;
- fixed MFC get/put/list shapes;
- compare/branch patterns for reduced loops;
- reductions or table lookups only when proven;
- explicit sync contract.

Targets:

- AArch64 scalar fallback;
- AArch64 NEON/dotprod;
- Vulkan SPIR-V for large batches or RSX-consumed output.

This is the most academically interesting lane because it sits between emulator
HLE, dynamic binary translation, and heterogeneous compiler research.

### 4. RSX Residency Accountant

Keep extending the auditor so every RSX experiment says:

- what work stayed GPU-local;
- what work moved from CPU to GPU;
- what work was already stock Vulkan;
- what render-pass/tile breaks remain;
- whether GPU residency increased without FPS improvement.

This prevents "GPU usage" from becoming a vague feel-good metric.

### 5. Renderpass-Local Resolve/Blit Prototype

The current debt is `blit_src_to_general`. The next RSX prototype should not be
another global compute dispatch. It should test whether the hot MSAA
resolve/blit-source path can be expressed as a renderpass-local or dynamic
rendering/local-read pattern while preserving Eternal Sonata visuals.

Acceptance:

- validation-clean on Windows;
- field/menu/battle screenshots;
- lower `resolve_break(blit_src)` count;
- no black foliage/flower artifacts;
- no new hard sync/readback debt.

### 6. GPU As Proof Engine Before GPU As Fast Engine

Use the underused GPU to run shadow verification in parallel with the stock CPU
path while gameplay remains CPU-authoritative. Even if it does not speed up the
first run, it builds a database of verified kernels. Later, fast mode can be
enabled for the kernels with long clean histories.

This is lateral but practical: the GPU becomes a correctness scout before it
becomes the replacement engine.

## Decision Matrix

| Work type | Best first target | Why | Avoid |
| --- | --- | --- | --- |
| PPU control | AArch64 JIT and HLE for stable syscalls | latency-sensitive, branchy | GPU dispatch |
| SPU hot loops | reduced-loop/codegen, then recognized-kernel IR | local-store kernels can be specialized | changing reservation semantics early |
| MFC/DMA wrappers | shape profiling and batching | wrapper cost alone is small | GPU copy-only offload |
| SPURS/semaphores | title-gated HLE only after proof | synchronization is visible to game | global wait rewrites |
| RSX graphics | Vulkan residency and renderpass locality | already GPU-facing | turning RSX command processor into compute |
| Texture/render prep | GPU compute if batched and GPU-consumed | likely data-parallel | immediate CPU readback |
| Verification | GPU shadow path | builds proof database | calling it a speed win |

## Next Windows-Only Experiments

Status update, 2026-05-19: the first recorder slice is now wired locally as
`RPCS3_ES_KERNEL_CAPSULE=profile`, exposed through
`tools/windows_rpcs3_lab.ps1 -EternalSonataKernelCapsule Profile` and the
sprint wrapper. It is observe-only: it classifies hot Eternal Sonata SPU/MFC
activity into GPU-batch, CPU-SIMD-first, RSX-consumed, sync-only,
reservation-risk, and tiny-dispatch buckets without replacing execution yet.
First field capture
`debug-captures/windows-lab/20260519-175217-eternal-sonata-field-stock-qualcomm-windows`
proved the recorder on Windows: `1.39 GB` observed DMA, `1583` capsule rows,
`0 B` RSX-local traffic, and every capsule classified `reservation-risk` because
the hot work is wrapped around AtomicStat/PUTLLC16 reservation loops. That is
not a Vulkan batch candidate yet; it points back to reservation-loop HLE/codegen
or to a separate RSX-consumed scout.

1. **Capsule Recorder**
   Add a Windows-only `RPCS3_ES_KERNEL_CAPSULE=profile` mode for
   `BLUS30161` / image `0x958dfe208b686622` that records compact capsules for
   `0x25cc`, `0x451c`, `0xa74`, and `0xad8`. Do not store raw game data in Git;
   emit hashes, ranges, timings, and ignored local binary payloads if needed.

2. **Capsule Summarizer**
   Extend `summarize_eternal_sonata_gpu_probe.ps1` to classify capsules as:
   `cpu-simd-first`, `gpu-batch-candidate`, `sync-only`, `reservation-risk`,
   `rsx-consumed`, or `tiny-dispatch-trap`.

3. **CPU SIMD Baseline**
   Before Vulkan, build a small AArch64/portable CPU-kernel evaluator for a
   verified capsule shape. On Windows this can be scalar/SSE/AVX proof; on Thor
   later it maps to NEON/dotprod. Under the current user gate, keep it Windows
   lab only unless the 200% proof bar is met.

4. **GPU Shadow Prototype**
   Pick one capsule only if it has:
   - many repeats;
   - no immediate CPU readback;
   - stable input/output ranges;
   - no reservation semantics;
   - consumer delay long enough to hide dispatch.

   Run GPU output in verify-only mode and compare hashes. Count dispatches,
   barriers, readbacks, and total GPU time.

5. **RSX `blit_src_to_general` Reduction**
   In parallel, keep the RSX-local path alive by targeting the remaining
   render-pass break debt from the proven `DepthReadOnly + Fast + KeepReadOnly`
   stack. This is the most direct way to keep using the underused GPU without
   inventing a general SPU compute port.

## Report Conclusion

Thor does not need "less emulation." It needs more selective translation inside
a correctness-locked emulator:

- emulate the PS3 contracts exactly where games observe them;
- recompile hot PPU/SPU code aggressively;
- HLE only stable, signature-gated kernels;
- keep RSX data GPU-resident;
- use GPU compute first as a verified, batched backend for recognized kernels,
  not as a generic SPU interpreter.

The novel research-worthy shape is a PS3 recognized-kernel system: capture hot
SPU/RSX-adjacent work from real gameplay, prove dependence and consumer timing,
lower to CPU SIMD and/or Vulkan SPIR-V, shadow-verify for many frames, then
promote only the kernels that survive. That is much more plausible than a broad
"SPU on GPU" rewrite, and it gives us a path where every small GPU migration can
be banked without pretending it is already the 200% speed win.

## Sources

- AYN Thor product page: https://www.ayntec.com/collections/frontpage/products/ayn-thor
- Qualcomm Snapdragon 8 Gen 2 product page: https://www.qualcomm.com/smartphones/products/8-series/snapdragon-8-gen-2-mobile-platform
- Qualcomm Snapdragon 8 Gen 2 product brief: https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/images/company/news-media/media-center/press-kits/summit-2022/day-1/documents/Snapdragon_8_Gen_2_Product_Brief.pdf
- IBM, `Beyond gaming: Programming the PLAYSTATION 3 cell architecture`: https://research.ibm.com/publications/beyond-gaming-programming-the-playstationr3-cell-architecture-for-cost-effective-parallel-processing
- Cell Broadband Engine Architecture v1.01: https://www.ps3linux.net/ps3-filez/cellsdk-docs/3.1/arch/CBEA_v1.01_3Oct2006.pdf
- RPCS3 ARM64 blog: https://blog.rpcs3.net/2024/12/09/introducing-rpcs3-for-arm64/
- GXBIT, `Two-phase execution of binary applications on CPU/GPU machines`: https://www.sciencedirect.com/science/article/abs/pii/S0045790614000299
- VectorVisor, USENIX ATC 2023: https://www.usenix.org/conference/atc23/presentation/ginzburg
- CuLE, `Accelerating Reinforcement Learning through GPU Atari Emulation`: https://arxiv.org/abs/1907.08467
- Parsimony, CGO 2023: https://research.nvidia.com/publication/2023-02_parsimony-enabling-simdvector-programming-standard-compiler-flows
- `High-level Programming of Vulkan-based GPUs Through OpenMP`: https://link.springer.com/article/10.1007/s10766-026-00816-8
- MLIR SPIR-V dialect: https://mlir.llvm.org/docs/Dialects/SPIR-V/
- Khronos Vulkan synchronization specification: https://docs.vulkan.org/spec/latest/chapters/synchronization.html
- Qualcomm Adreno OpenCL memory optimization: https://www.qualcomm.com/news/onq/2016/06/better-opencl-performance-qualcomm-adreno-gpu-memory-optimization
- VUDA, `Breaking CUDA-Vulkan Isolation`: https://arxiv.org/abs/2605.01352
