# Vulkan / Adreno / CS Paper Delta For Thor PS3

- Status: `proposed`
- Target: AYN Thor Base/Pro/Max, Adreno 740
- Emulator target: RPCSX Android fork, with Windows RPCS3 as lab
- Created: 2026-05-16

Follow-up: `debug-experiments/20260516-vulkan-adreno-deep-research.md` expands
this into a research-to-experiment map with local RPCSX touchpoints.

## Why This Exists

The earlier full-utilization plan correctly framed the problem as "feed the PS3
critical path," not "show 100% CPU/GPU." The missing layer is newer Vulkan,
mobile-GPU, compiler, and scheduling research. The useful papers do not say
"make RPCS3 fast on Adreno," but they do point to constraints that should shape
our next experiments:

- tiny GPU dispatches are poison;
- tile memory is the real mobile-GPU prize;
- GPU compute and graphics overlap must be proven, not assumed;
- frame-to-frame coherence can avoid repeated work;
- shader/kernel generation should be treated like compiler infrastructure, not
  hand-written one-off GLSL snippets;
- frame pacing can be bad even when average FPS improves.

## Missing Angle 1: Tile-Local Compute On Adreno

Khronos' `VK_QCOM_tile_shading` proposal is the biggest Adreno-specific clue.
It exposes tile shading features that map directly to Adreno TBDR behavior:
commands can run per tile, and shaders can access tile image attachments while
framebuffer data is still in tile memory.

For Thor this suggests a new class of RSX/Vulkan experiments:

- Probe whether Thor's stock Qualcomm driver and Turnip expose
  `VK_QCOM_tile_shading`, `VK_QCOM_tile_properties`, and
  `VK_KHR_dynamic_rendering_local_read`.
- If present, do not try to move arbitrary SPU work there. Start with
  framebuffer-local work: resolve/postprocess/upscale/color conversion/tile
  effects where data is already in RSX/Vulkan attachments.
- If absent, still apply the lesson: keep render passes explicit, avoid needless
  external-memory round trips, and use AGI to find GMEM/sysmem switches.

RPCS3/RPCSX implication: the Adreno path should not only count draw calls or GPU
busy time. It should classify passes by whether they are tile-local, attachment
readback-heavy, or forced to sysmem.

## Missing Angle 2: Dispatch Overhead Means Batch Or Do Not Offload

Recent GPU-runtime papers are screaming the same thing from different angles:

- WebGPU dispatch-overhead characterization reports Vulkan-path dispatch costs
  in the tens of microseconds and shows fusion can matter more than kernel
  arithmetic quality for many small operations.
- GPUOS uses a persistent worker-kernel idea to avoid repeated tiny launches.
- VkSplat shows that fully Vulkan compute can be competitive when the workload
  is structured, batched, memory-conscious, and vendor-portable.

For Thor, this should become a hard rule:

> No GPU superpath for Eternal Sonata gets promoted if it launches one dispatch
> per tiny SPU/PPU event.

The first viable GPU compute path must batch work:

- one dispatch per frame or per large SPU job family, not per syscall;
- persistent descriptor sets and buffers;
- no CPU readback on the critical path;
- timestamp queries around dispatch, barriers, and queue submit;
- verify-only mode comparing CPU/SPU output hashes before fast mode.

Good candidate shape: a stable BLUS30161 SPU image/hash that produces a large
buffer consumed by RSX. Bad candidate shape: the current SPURS start/join loop
or semaphore wait/post wrappers.

## Missing Angle 3: Compute/Graphics Overlap Must Be Measured

VUDA is not directly portable to Android because it depends on CUDA/Vulkan
driver-level channel and address-space tricks. The lesson still matters:
GPU utilization can be low because graphics and compute are time-sliced or
isolated, not because the GPU lacks arithmetic work.

Thor action:

- Log Vulkan queue-family capabilities on startup.
- Add a microbenchmark that submits graphics and compute timestamp workloads
  independently and concurrently.
- Use AGI to verify whether Adreno actually overlaps those queues or serializes
  them.
- If overlap is fake or harmful, schedule compute superpaths in predictable
  gaps, not beside heavy RSX render passes.

Do not assume "async compute" exists just because Vulkan exposes a compute
queue. The only truth is timestamp plus AGI counter proof on Thor.

## Missing Angle 4: Frame-To-Frame Tile Coherence

KHEPRI and Rendering Elimination both exploit the fact that many tiles behave
similarly across adjacent frames. KHEPRI predicts tile behavior from the previous
frame; Rendering Elimination skips redundant tile work when signatures match.

We cannot rewrite Adreno hardware, but we can steal the idea:

- Add an experimental RSX frame/tile signature probe for Eternal Sonata field
  route.
- Track repeated render-target regions, unchanged texture uploads, and repeated
  postprocess inputs across frames.
- Build a verify-only "skip unchanged upload/resolve" detector before any fast
  path.
- Look for scenes where field camera/menu/static UI produce repeated tiles or
  repeated RSX resources.

This is probably more useful for bandwidth and thermals than for raw SPU-bound
FPS, but that matters on a handheld.

## Missing Angle 5: Compiler Infrastructure For Vulkan Kernels

The Vcc paper is useful because it treats Vulkan shader generation as a real
compiler problem. For us, that means GPU superpaths should not become a pile of
fragile handwritten shader strings.

If a GPU superpath graduates past one prototype:

- define a small typed IR for candidate SPU/RSX bulk jobs;
- lower it to SPIR-V/GLSL through a repeatable generator;
- include CPU reference, GPU verify, hash/mismatch logs, and offline fixtures;
- compile/cache per driver and title ID, like PPU/SPU/shader cache.

This pairs naturally with the existing SPU image hash / DMA pattern gates.

## Missing Angle 6: Frame Pacing Is Part Of Speed

`VK_EXT_present_timing` is a recent Vulkan ecosystem clue: average FPS is not
enough. Presentation timing and display cadence need to be measured separately
from emulation frame time.

Thor action:

- Check driver support for `VK_EXT_present_timing`, `VK_KHR_present_wait`, and
  `VK_KHR_present_id`.
- If present, add a frame-pacing trace lane: emulated frame ready time, Vulkan
  submit time, present request time, actual/predicted present time.
- If absent, use Android Choreographer/SurfaceFlinger/Perfetto as fallback.

For PS3 emulation, "30 FPS" with bad pacing can still feel broken. This matters
when deciding between CPU scheduler masks, RSX multithreading, shader preloading,
and dynamic resolution.

## Concrete Next Patch Ideas

1. Extend Thor Feature Doctor with Vulkan extension and queue-family dump:
   - `VK_QCOM_tile_shading`
   - `VK_QCOM_tile_properties`
   - `VK_KHR_dynamic_rendering_local_read`
   - `VK_EXT_present_timing`
   - `VK_KHR_present_wait`
   - `VK_KHR_unified_image_layouts`
   - queue family count/flags/timestamp bits

2. Add a Vulkan microbench mode:
   - graphics-only timestamp pass;
   - compute-only timestamp pass;
   - concurrent graphics+compute submission;
   - barrier-heavy versus narrow-barrier variant;
   - stock Qualcomm versus Turnip.

3. Add an RSX pass classifier for Eternal Sonata:
   - render target size/format/load/store;
   - attachment readback/feedback;
   - texture upload/flush bytes;
   - barrier count and broad `ALL_COMMANDS` style barriers;
   - shader/pipeline cache miss over 1 ms.

4. Tighten GPU superpath rules:
   - batch-first;
   - one or few dispatches per frame/job family;
   - no critical readback;
   - verify-only before fast;
   - title/signature gate.

5. Add frame-pacing acceptance:
   - sustained FPS;
   - 1% low frame time;
   - present cadence/jitter;
   - no audio underrun;
   - field, battle, menu correctness.

## Sources

- `VK_QCOM_tile_shading` proposal:
  https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_tile_shading.html
- Vulkan tile-based rendering best practices:
  https://docs.vulkan.org/guide/latest/tile_based_rendering_best_practices.html
- Mesa Freedreno/Turnip documentation:
  https://docs.mesa3d.org/drivers/freedreno.html
- Android GPU Inspector counters:
  https://developer.android.com/agi/sys-trace/counters
- Qualcomm Snapdragon Game Super Resolution 2:
  https://www.qualcomm.com/developer/blog/2024/10/introducing-snapdragon-game-super-resolution-2
- Qualcomm Adreno low-power gaming guide:
  https://www.qualcomm.com/developer/blog/2025/08/optimize-performance-and-graphics-for-adreno-gpu-low-power-gaming
- VkSplat, high-performance Vulkan compute, 2026:
  https://arxiv.org/abs/2605.00219
- VUDA, CUDA/Vulkan spatial sharing, 2026:
  https://arxiv.org/abs/2605.01352
- WebGPU dispatch overhead, including Vulkan backend costs, 2026:
  https://arxiv.org/abs/2604.02344
- GPUOS persistent GPU worker/fusion, 2026:
  https://arxiv.org/abs/2604.17861
- KHEPRI heterogeneous/tile-aware GPU scheduling, 2026:
  https://arxiv.org/abs/2601.22862
- Rendering Elimination, redundant tile skipping, 2018:
  https://arxiv.org/abs/1807.09449
- GPreempt GPU preemptive scheduling, USENIX ATC 2025:
  https://www.usenix.org/conference/atc25/presentation/fan
- Vcc / compiling C++ to Vulkan shaders, HPG 2025:
  https://graphics.cg.uni-saarland.de/papers/devillers-2025-hpg-vcc.pdf
- `VK_EXT_present_timing` Khronos blog:
  https://www.khronos.org/blog/vk-ext-present-timing-the-journey-to-state-of-the-art-frame-pacing-in-vulkan
- `VK_KHR_unified_image_layouts` proposal:
  https://docs.vulkan.org/features/latest/features/proposals/VK_KHR_unified_image_layouts.html
