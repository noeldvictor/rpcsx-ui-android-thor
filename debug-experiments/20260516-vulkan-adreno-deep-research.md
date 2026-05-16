# Deep Vulkan / Adreno Research Map For Thor PS3

- Status: `research-to-experiment`
- Target device: AYN Thor Max / Snapdragon 8 Gen 2 / Adreno 740
- Emulator target: RPCSX Android fork, with RPCS3 Windows as the fast lab
- Canary title: Eternal Sonata `BLUS30161`
- Created: 2026-05-16

## Thesis

"Use the full CPU/GPU" should mean "remove avoidable bubbles on the PS3
critical path." Raw 100 percent CPU or GPU activity can be fake progress if it
comes from busy waits, broad barriers, shader compile stalls, tiny compute
dispatches, or thermal-throttled overwork.

The deeper research points to a sharper plan:

1. Keep the Cell-side critical path on the right Thor CPU cores.
2. Make the RSX/Vulkan path Adreno-aware: tile locality first, fewer global
   barriers, fewer render-pass breaks, fewer readbacks.
3. Treat GPU compute offload as a batched compiler/runtime problem, not as a
   one-shader-per-event trick.
4. Measure GPU work with tiler-aware timers and AGI counters before promoting
   any fast path.
5. Accept a change only if FPS, pacing, thermals, and correctness all survive
   field, menu, and first-battle checks.

## What The Newer Vulkan / Adreno Work Changes

### 1. Qualcomm Tile Memory Is The Real Prize

`VK_QCOM_tile_memory_heap`, `VK_QCOM_tile_shading`, and
`VK_QCOM_tile_properties` are the clearest Adreno-specific signals. The APIs
exist because Adreno is a tile renderer and because keeping framebuffer-local
work inside tile memory can avoid expensive movement through system memory.

Important details:

- `VK_QCOM_tile_memory_heap` exposes a tile-memory heap. Contents have special
  lifetime rules and normally persist only within a command buffer submission
  batch boundary, with a property to query whether that can extend to a queue
  submit boundary.
- `VK_QCOM_tile_shading` lets compute-style work happen in a render pass with
  access to tile image attachments. It has serious restrictions, so it is not a
  generic SPU accelerator.
- `VK_QCOM_tile_properties` lets an app query tile layout. Qualcomm notes that
  Adreno can switch to direct rendering / Flex render, so the returned data is
  useful but not absolute truth.

RPCSX implication:

- Do not start by moving arbitrary SPU work to the GPU.
- Start with RSX-local work: resolves, postprocess, color conversion,
  framebuffer feedback, upscaling, repeated UI overlays, or attachment-local
  effects.
- Add an RSX pass classifier that tells us whether a pass stayed tile-local,
  forced sysmem, hit a readback, or broke a render pass.

Thor test:

- Dump support for:
  - `VK_QCOM_tile_memory_heap`
  - `VK_QCOM_tile_shading`
  - `VK_QCOM_tile_properties`
  - `VK_KHR_dynamic_rendering_local_read`
  - `VK_EXT_shader_tile_image`
- Compare stock Qualcomm driver versus Turnip, if Turnip is viable on the
  build.
- In AGI, look for GMEM/sysmem switches, bandwidth spikes, and GPU idle gaps
  around Eternal Sonata field/menu/battle transitions.

### 2. Vulkan Timestamps Can Lie On Tilers

`VK_QCOM_elapsed_timer_query` exists because ordinary timestamp comparisons
inside render passes can undercount work on tile renderers. The proposal says
timestamp comparisons on tilers may return a single tile cost or near-zero time,
which can make a pass look cheaper than it is.

RPCSX implication:

- If Thor exposes `VK_QCOM_elapsed_timer_query`, prefer it for measuring RSX
  pass cost on Adreno.
- If it is absent, use AGI counters and coarse submit timing, and avoid drawing
  hard conclusions from timestamp-only render-pass probes.

Thor test:

- Add a Vulkan timing probe mode:
  - timestamp query outside render pass;
  - timestamp query inside render pass;
  - elapsed timer query, if exposed;
  - AGI trace for the same scene.
- Reject any metric that disagrees badly with AGI counters or visible frame
  cost.

### 3. Queue Performance Hints Are A Clock-Ramp Experiment

`VK_QCOM_queue_perf_hint` lets an app apply normalized performance hints to
Vulkan queues. Qualcomm frames this as a way to influence clock-frequency
selection on power-sensitive devices without directly setting frequencies.

RPCSX implication:

- This is not a correctness path and not a substitute for removing barriers.
- It might reduce ramp latency or stabilize clocks for a known RSX-heavy phase.
- It could hurt thermals if applied blindly.

Thor test:

- Only test after baseline traces exist.
- Apply hint to graphics queue during a known RSX-heavy capture and compare:
  - FPS;
  - 1 percent lows;
  - GPU busy;
  - GPU frequency;
  - skin temp / thermal throttle;
  - battery draw if available.
- Test default, min-frequency, scaled, and reset behavior behind one property.

### 4. Pipeline Binary Matters For Stutter, Not Raw Peak FPS

`VK_KHR_pipeline_binary` gives applications direct control over pipeline binary
data instead of relying only on opaque pipeline cache behavior. It can retrieve
binary data for individual pipelines and lets apps validate cached data against
implementation keys on later runs.

RPCSX implication:

- Existing shader cache is necessary but may not be enough for driver-level
  pipeline creation cost on Android.
- If supported, pipeline binary should be evaluated for shader/pipeline stutter
  in Eternal Sonata scene changes, first battle, and menu transitions.
- Cache key must include driver/vendor/device/build/title/settings. Wrong cache
  reuse is worse than no cache.

Thor test:

- Add Feature Doctor dump for `VK_KHR_pipeline_binary`.
- Log pipeline creation over 1 ms and correlate with frame spikes.
- Prototype capture/reload for a tiny known pipeline set before touching the
  whole pipeline compiler.

### 5. Dynamic Local Reads And Unified Layouts Are Barrier-Reduction Tools

`VK_KHR_dynamic_rendering_local_read` enables reads from attachments/resources
written by previous fragment shaders within a dynamic render pass. This is
relevant because input attachments and local dependencies are exactly where
tile renderers can avoid global memory round trips.

`VK_KHR_unified_image_layouts` and related modern layout features may reduce
layout churn in engines that bounce images through many narrowly different
layouts. It does not remove the need for correct hazards, but it can reduce
layout transition complexity where supported.

RPCSX implication:

- These are not first patches.
- First, count barriers and render-pass breaks.
- Then test whether specific repeated RSX patterns can stay inside one dynamic
  rendering scope or use local reads instead of a texture/readback path.

Thor test:

- Instrument:
  - global memory barriers;
  - `ALL_COMMANDS` barriers;
  - render pass begin/end count;
  - attachment feedback/readback events;
  - image layout transitions per frame.
- Build one title-gated RSX path only after the counters identify a hot pattern.

## What The Papers Actually Say For Us

### Dispatch Overhead: Batch Or Do Not Offload

The 2026 WebGPU dispatch-overhead paper reports Vulkan-path per-dispatch API
overhead in the tens of microseconds, and shows that fusion can matter more
than arithmetic quality for small operations. GPUOS attacks the same shape with
a persistent GPU worker and fused submissions.

For RPCSX:

- One Vulkan compute dispatch per small SPU event is dead on arrival.
- A GPU superpath must batch by frame, SPU image family, RSX resource family, or
  another coarse unit.
- The minimum promotion rule should be:
  - one or a few dispatches per frame/job;
  - persistent buffers/descriptors;
  - no CPU readback on the critical path;
  - verify-only hashes before fast mode;
  - title/hash/settings gate.

### Compute / Graphics Overlap: Measure, Do Not Assume

VUDA is CUDA/Vulkan and driver-level research, not something to port to Android.
The important lesson is that GPU utilization can be limited by scheduling
isolation between compute and graphics work. Vulkan exposing a compute queue
does not prove useful overlap on Adreno.

For RPCSX:

- Build a tiny overlap microbench before any compute offload.
- Submit graphics-only, compute-only, and concurrent graphics+compute work.
- Use timestamps, `VK_QCOM_elapsed_timer_query` if available, and AGI counters.
- If overlap is fake, schedule compute in predictable RSX gaps.

### Vulkan Compute Can Work, But Only With Compiler Discipline

VkSplat shows fully Vulkan compute can be fast and portable when the workload is
structured and the implementation owns its memory, caching, and pipeline
discipline. Vcc shows that treating Vulkan shader generation like a real
compiler can make complex GPU code manageable.

For RPCSX:

- If a GPU superpath survives one prototype, make it compiler-like:
  - typed input/output buffers;
  - CPU reference implementation;
  - generated SPIR-V/GLSL from a small IR or generator;
  - offline fixture;
  - cache key per driver/title;
  - mismatch logs with rollback.

### Frame-To-Frame Coherence Is Useful Even Without New Hardware

KHEPRI uses previous-frame tile behavior to guide scheduling. Rendering
Elimination skips repeated tile work with signatures. We cannot change Adreno
hardware, but we can steal the engineering shape.

For RPCSX:

- Look for repeated texture uploads, repeated resolves, repeated postprocess
  inputs, unchanged UI overlays, and repeated render targets.
- First make a verify-only detector that says "this could have been skipped."
- Only then gate a skip/fast path.

### Preemption Research Says Keep GPU Jobs Schedulable

GPreempt is not directly usable, but its lesson matters: huge non-preemptible
GPU jobs can hurt latency. For an emulator, long compute kernels may improve
average GPU busy while making frame pacing worse.

For RPCSX:

- Any GPU superpath must report its worst-case duration.
- Accept small batches only if launch overhead does not dominate.
- Accept large batches only if they do not damage pacing or audio.

## Local RPCSX Findings That Match The Research

These are current code touchpoints worth instrumenting before optimizing:

- `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`
  - `PERFORMANCE_CORE_MASK = 0xF8`
  - SPU LLVM is enabled.
  - LLVM CPU is forced to `cortex-a78`.
  - `Multithreaded RSX` is currently false.
  - process affinity is applied through `setProcessAffinityMask`.

- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKTextureCache.cpp`
  - A DMA fence path uses destination stage `ALL_COMMANDS`.
  - This is a prime "maybe too broad on Adreno" measurement point.

- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/barriers.h`
  - `insert_global_memory_barrier` defaults source and destination stages to
    `ALL_COMMANDS`.
  - Count every call before changing it.

- `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKQueryPool.cpp`
  - `vkCmdCopyQueryPoolResults` uses `VK_QUERY_RESULT_WAIT_BIT`.
  - The surrounding comment already notes render-pass interruption can matter
    on tile-based renderers.

- Current RSX/Vulkan scan did not find real `VK_QCOM_*`,
  `VK_KHR_pipeline_binary`, `VK_EXT_present_timing`, or
  `VK_QCOM_elapsed_timer_query` usage in the inspected VK files.

## Concrete Experiment Order

### Phase 0: Feature Doctor, No Behavior Change

Add a Thor Vulkan Feature Doctor dump:

- device name, driver version, API version;
- queue family count, flags, timestamp bits;
- supported-present modes;
- all QCOM/KHR/EXT features below:
  - `VK_QCOM_tile_memory_heap`
  - `VK_QCOM_tile_shading`
  - `VK_QCOM_tile_properties`
  - `VK_QCOM_elapsed_timer_query`
  - `VK_QCOM_queue_perf_hint`
  - `VK_KHR_pipeline_binary`
  - `VK_KHR_dynamic_rendering_local_read`
  - `VK_KHR_unified_image_layouts`
  - `VK_EXT_present_timing`
  - `VK_KHR_present_wait`
  - `VK_KHR_present_id`
  - `VK_EXT_shader_tile_image`

Output should go to logcat and the existing debug report path.

### Phase 1: RSX Barrier And Pass Auditor

Add counters only:

- count `ALL_COMMANDS` barriers;
- count global memory barriers;
- count transfer-to-all barriers;
- count query result waits;
- count render-pass begin/end;
- count layout transitions;
- count detile bytes;
- count texture upload/flush bytes;
- count pipeline creations and creations over 1 ms;
- count command buffer submits;
- count queue idle/wait calls.

Acceptance:

- No performance tuning yet.
- One Eternal Sonata route produces a per-scene report.
- Counters must not alter correctness.

### Phase 2: Tiler-Aware Microbench

Add an opt-in debug screen or property-driven mode:

- graphics-only timestamp workload;
- compute-only timestamp workload;
- concurrent graphics plus compute workload;
- barrier-heavy versus narrow-barrier workload;
- timestamp versus elapsed-timer comparison when QCOM elapsed timer exists.

Acceptance:

- Report whether Adreno overlaps compute/graphics or serializes them.
- Report whether timestamp timing disagrees with AGI.
- Do not use these results across drivers without re-running.

### Phase 3: First Low-Risk Optimization Candidate

Pick only after Phase 1 data:

- If barriers dominate, narrow one known-safe barrier behind a property.
- If query waits dominate, test deferred query result handling.
- If pipeline creation dominates, test `VK_KHR_pipeline_binary` or pipeline
  warmup.
- If detile/upload bandwidth dominates, test a repeated-resource detector.
- If render-pass breaks dominate, test local-read/dynamic-rendering refactor on
  a tiny title-gated path.

Acceptance:

- Eternal Sonata field/menu/battle pass.
- FPS and 1 percent lows improve or remain stable.
- Frame pacing improves or remains stable.
- No new visual corruption.
- No extra thermal cliff after sustained run.

### Phase 4: GPU Superpath Only If A Bulk Pattern Exists

A compute offload can proceed only if Phase 1 or Ghidra/SPU tracing finds a
large stable pattern:

- fixed title ID;
- fixed SPU image/hash or RSX resource signature;
- large enough work batch;
- no critical readback;
- CPU reference implementation exists;
- GPU verify mode can hash outputs.

Bad candidates:

- SPURS start/join wrappers;
- semaphores and tiny sync events;
- one-dispatch-per-PPU-call paths;
- anything that requires CPU readback before the frame can proceed.

Good candidates:

- repeated bulk memory transform consumed by RSX;
- stable framebuffer-local RSX pass;
- repeated resolve/conversion/upscale path;
- large texture/postprocess operation already living in GPU memory.

## What To Patch First

The smartest first patch is not an optimization. It is a visibility patch:

1. Thor Vulkan Feature Doctor extension and queue dump.
2. RSX barrier/pass auditor counters.
3. Optional QCOM elapsed timer probe if exposed.

Reason: until we know whether Thor is CPU-bound, barrier-bound, tile-memory
bound, pipeline-stutter-bound, or fake-async-bound in a specific Eternal Sonata
scene, any "use the GPU more" patch is likely to move bottlenecks around.

## Implementation Slice: RSX Auditor

- Status: `implemented-build-passed`
- Gate: `debug.rpcsx.thor.rsx_auditor`
- Helper: `tools/set_thor_logging.ps1 -Mode RsxAuditor`
- Default behavior: off, no fast path, no renderer behavior change.

The first visibility slice adds an opt-in RSX/Vulkan auditor that emits one
compact `Thor RSX Auditor:` summary every N frames. `RsxAuditor` mode sets the
interval to `60`; setting the property to `frame` logs every frame, and setting
it to a numeric value such as `120` changes the interval.

The summary is emitted at warning level while the gate is enabled because the
Android logcat path can drop notice-level RSX lines.

Build verification:

- `.\gradlew.bat :app:assembleDebug` passed on 2026-05-16.
- The build included `configureCMakeDebug[arm64-v8a]` and
  `buildCMakeDebug[arm64-v8a]`.
- Dev-core push `rsx-auditor-warning` installed
  `SHA256 9AFB799C24C1AB2DA13A43E00439BB3332684094D84D15F8DF6DE096B12633B6`
  to `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`.

Counters currently covered:

- queue submits, wait/signal semaphores, async-submit requests, flush requests,
  hard-sync flushes;
- render-pass begin/end counts and render-pass breaks caused by barriers;
- global, buffer, image, texture, and `ALL_COMMANDS` barriers;
- the DMA transfer-to-`ALL_COMMANDS` fence in `VKTextureCache.cpp`;
- indirect query result copies using `VK_QUERY_RESULT_WAIT_BIT`;
- graphics/compute pipeline creation count, total creation time, and creates
  over 1 ms;
- detile jobs and bytes;
- simple CPU-to-linear-image uploads and bytes.

First Thor capture command:

```powershell
.\tools\set_thor_logging.ps1 -Mode RsxAuditor
.\tools\eternal_sonata_speed_sprint.ps1 -Action AndroidScene -Scene field -Driver stock-qualcomm -Core rsx-auditor
.\tools\set_thor_logging.ps1 -Mode Quiet
```

How to read the first run:

- high `rp_break` plus high texture/image barriers means Adreno tile locality is
  probably being destroyed;
- high `all` barriers means the first optimization target is synchronization
  narrowing, not GPU compute;
- high `query_wait` points at occlusion/query streaming stalls;
- high `pipe(.../slow/us)` points at pipeline/shader stutter and makes
  `VK_KHR_pipeline_binary` or warmup worth testing;
- high `detile` or `simple_upload` bytes points at bandwidth/sysmem traffic;
- high `hard_sync` means the emulator is forcing CPU/GPU drain points.

### First Thor Result

Capture:
`debug-captures/android-speed-sprint/20260516-101045-eternal-sonata-field-stock-qualcomm-scene`

Proof:

- Device loaded the dev-core override.
- Vulkan device was `Adreno (TM) 740`, driver `512.676.53`.
- Field screenshot reached the expected Eternal Sonata field, overlay about
  `15.11 FPS`.
- Auditor log saved to
  `debug-captures/android-speed-sprint/20260516-101045-eternal-sonata-field-stock-qualcomm-scene/thor-rsx-auditor-logcat.txt`.

First read:

- Shader/pipeline warmup is visible and ugly: early intervals reported `79`
  graphics pipeline creates, all slow, with about `52.1s` total create time,
  followed by another `76` slow graphics creates at about `37.1s`.
- In the heavy field/transition window, the auditor saw up to `360` submits per
  60 emulated frames, `1740` buffer barriers, `120` image barriers, about
  `7508.45 MB` of barrier-tracked buffer range, and `300`
  transfer-to-`ALL_COMMANDS` DMA fences carrying about `1032.42 MB`.
- Later field intervals repeatedly show `rp_break=60`, usually paired with
  texture/image barriers. That is exactly the Adreno tile-locality suspicion.
- `query_wait=0`, `all=0`, `async_req=0`, and no detile/simple-upload bytes in
  this capture, so the first target is not occlusion-query streaming, generic
  `ALL_COMMANDS` global barriers, fake async compute, detiling, or simple CPU
  present upload.

Decision from this first run:

1. Add call-site labels for the high-volume buffer barriers and DMA
   transfer-to-`ALL_COMMANDS` fences.
2. Split the auditor's `rp_break` count by texture/image/buffer barrier source.
3. Investigate the DMA fence in `VKTextureCache.cpp` first, because it already
   showed hundreds of fences and hundreds of MB to about 1 GB per 60 frames in
   the field route.
4. Treat `VK_KHR_pipeline_binary` / pipeline warmup as a separate stutter track,
   not as the main steady-field FPS track.

## Source Trail

- AYN Thor specs: https://www.ayntec.com/products/ayn-thor
- Qualcomm Snapdragon 8 Gen 2 product brief:
  https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Snapdragon-8-Gen-2-Product-Brief.pdf
- Android Performance Hint API:
  https://source.android.com/docs/core/perf/performance-hint-api
- Android GPU Inspector counters:
  https://developer.android.com/agi/sys-trace/counters
- Mesa Freedreno / Turnip architecture notes:
  https://docs.mesa3d.org/drivers/freedreno.html
- `VK_QCOM_tile_memory_heap`:
  https://docs.vulkan.org/refpages/latest/refpages/source/VK_QCOM_tile_memory_heap.html
- `VK_QCOM_tile_shading`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_tile_shading.html
- `VK_QCOM_tile_properties`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_tile_properties.html
- `VK_QCOM_elapsed_timer_query`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_elapsed_timer_query.html
- `VK_QCOM_queue_perf_hint`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_QCOM_queue_perf_hint.html
- `VK_KHR_pipeline_binary`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_KHR_pipeline_binary.html
- `VK_KHR_dynamic_rendering_local_read`:
  https://docs.vulkan.org/features/latest/features/proposals/VK_KHR_dynamic_rendering_local_read.html
- WebGPU dispatch overhead, 2026:
  https://arxiv.org/abs/2604.02344
- GPUOS persistent worker/fusion, 2026:
  https://arxiv.org/abs/2604.17861
- VUDA CUDA/Vulkan spatial sharing, 2026:
  https://arxiv.org/abs/2605.01352
- VkSplat Vulkan compute, 2026:
  https://arxiv.org/abs/2605.00219
- KHEPRI tile-aware heterogeneous GPU scheduling, 2026:
  https://arxiv.org/abs/2601.22862
- GPreempt GPU scheduling, USENIX ATC 2025:
  https://www.usenix.org/conference/atc25/presentation/fan
- Vcc C++ to Vulkan shaders, HPG 2025:
  https://graphics.cg.uni-saarland.de/papers/devillers-2025-hpg-vcc.pdf
