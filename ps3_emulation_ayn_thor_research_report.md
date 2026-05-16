# PS3 Emulation on AYN Thor: Eternal Sonata Speed Research Report

- Date: 2026-05-16
- Target device: AYN Thor Max first, with Base/Pro compatibility tracked separately
- Primary game canary: Eternal Sonata `BLUS30161`
- Local Android repo: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android`
- Local Windows lab repo: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`

## Executive Summary

We now have the first modest Eternal Sonata FPS speedup signal, but not a fully proven playable-speed win yet. We have a repeatable Thor field route, direct agent control, clean Android baselines, and a cache-safe reduced-loop/codegen experiment that improves the field/menu samples while battle validation remains open.

The Windows RPCS3 lab reaches the first playable 3D field with FPS overlay and can profile Eternal Sonata SPU DMA jobs. The Android debug APK now has a direct pad bridge, so Codex can boot Eternal Sonata and press PS3 controls without flaky Android key mapping. On Thor Max with `NeutralCore`, the direct route reaches first controllable field at roughly `16-18 FPS`; direct stick movement and pause overlay both work.

The strongest current hot-path finding is that the field route repeatedly hits SPU image `0x958dfe208b686622`, especially hot PCs `0x25cc` and `0x451c`. RPCS3's SPU disassembly sidecars show both hot PCs are MFC/DMA command issue/wait code, not obvious bulk shader-style math. Android DMA/MFC profiling now confirms the same image/PCs on Thor, with zero RSX-local traffic in the sampled field route. Android field snapshots show `rsx::thread`, multiple SPU threads, and active PPU threads hot at the same time.

That means the first serious speed experiment should be a title-gated, verify-first SPU DMA/job superpath or reduced-loop/codegen/scheduler win. A blind "move SPU to GPU" rewrite is not justified by the field sample yet because the probe found zero RSX-local/GPU-memory traffic.

Three negative results are now important. The aggressive `SafeSpeed` CPU profile with `RPCS3 Scheduler` plus SPU reservation busy-wait is not a win for this route; it dropped the opening sequence into low single digits on Thor. Follow-up `OldNeutral`/`AltNeutral` scheduler profiles also crawled around `2.2 FPS` in the story/tree route even without busy-wait. `Multithreaded RSX=true` also lost, falling to about `12.7 FPS` in the field. Eternal Sonata defaults should stay neutral on scheduler/busy-wait and RSX threading while we hunt real SPU/RSX wins.

The first Android semaphore superpath did work in the narrow sense: it was title-gated, correct-looking in field, and logged roughly `98k` fast semaphore operations by the time the route reached gameplay. It did not improve field FPS versus Off, so the project should not keep polishing syscall wrappers as the main path. The next high-leverage target is deeper: SPU MFC/DMA loops, SPU reduced-loop/codegen, and RSX/Vulkan traffic.

The first Android DMA/MFC verifier also says "not yet" to the simplest superpath. Verify mode produced no output mismatches, but exact repeated `(pattern,get_hash,put_hash)` hits stayed at `0`, so we do not have evidence for a simple output replay cache. A first aligned six-element list GET copy fast path rendered correctly at about `17.59 FPS`, but that remains inside the current `16-18 FPS` field band and is not a meaningful speedup.

The first positive result is SPU reduced-loop emission. After separating the experimental SPU cache into `spu-safe-thor-rl-v1-tane.dat` and restoring the normal cache, Thor Max field captures reached about `19.86 FPS` cold and `19.61 FPS` warm with correct-looking visuals; pause/menu proof reached about `20.18 FPS`. This is roughly a low-teens percentage gain over the clean `17.43-17.59 FPS` field band. It is promising, but not yet the 20%+ acceptance target and not yet field + battle + menu complete.

The broader Thor utilization strategy should be: use the CPU more intelligently, feed the GPU better, and avoid CPU/GPU sync stalls. The goal is not 100% CPU plus 100% GPU at all times; it is balanced frame throughput with field, battle, and menu correctness intact.

## Hardware Context

AYN Thor Base/Pro/Max use Snapdragon 8 Gen 2 class hardware with Adreno 740, while Thor Lite is Snapdragon 865 / Adreno 650 and is not the PS3 performance target. The active proof device is Thor Max, but Base and Pro remain relevant because they share CPU/GPU but have less RAM.

Local device notes already confirmed the connected Thor reports `QCS8550`, `kalama`, Adreno 740, and roughly 15.6 GB RAM. Public/retail specs line up with Snapdragon 8 Gen 2 and Adreno 740 for Thor Max.

Implication: Thor has a strong mobile CPU/GPU pair, but PS3 emulation is hard because the emulator pipeline is synchronization-heavy: PPU, SPU, RSX, shader compilation, memory reservations, render-target behavior, and Android/Adreno driver behavior all matter.

## Current Local Findings

### Windows Lab Status

Windows RPCS3 is now the fast hypothesis lab:

- `tools/windows_rpcs3_lab.ps1` launches RPCS3 popup-suppressed, moves the game window to the second monitor, enables FPS overlay, applies the official RPCS3 config DB, and records host contention.
- `tools/eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field` routes to first playable field.
- `-EternalSonataGpuProbe Profile` enables Eternal Sonata SPU/DMA candidate discovery.
- `tools/summarize_eternal_sonata_gpu_probe.ps1 -RunDir RUN_DIR` ranks candidate jobs.
- Probe runs write `spu-images/` sidecars: a 256 KB SPU local-storage image and RPCS3 SPU disassembly windows around hot PCs.

Important diagnostic run:

- Run dir: `debug-captures/windows-lab/20260515-230825-eternal-sonata-gpu-probe-field-sampled-windows/`
- Scene: first playable field
- Result: reached 3D gameplay with FPS overlay and no obvious field visual corruption
- Host contention: `high` because Vita3K was active, so not clean FPS proof
- Records: `1157`
- Observed DMA: about `1,382.74 MB`
- Hot image: `0x958dfe208b686622`
- Hot PCs: `0x25cc` and `0x451c`
- RSX-local traffic: `0` records

Disassembly smoke:

- Run dir: `debug-captures/windows-lab/20260515-232647-eternal-sonata-gpu-probe-disasm-smoke-windows/`
- LS dump: `spu-images/BLUS30161-spu-image-958dfe208b686622-entry-00818-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.ls.bin`
- Hot-PC sidecars: `pc-025cc` and `pc-0451c`
- Quick read: both are MFC/DMA command loops.

### Meaning

The field bottleneck currently looks like repeated SPU jobs moving data through MFC/DMA, not an obvious GPU-resident render-prep kernel. This can still be a big win, but the likely first paths are:

- SPU reduced-loop/codegen improvements around the hot DMA loop.
- Faster SPU MFC/list transfer path when correctness conditions match.
- Title-gated job verification and possible job-output cache/HLE only after proof.
- Scheduler/SPURS join/wait improvements if Thor traces show wake latency or excessive sleeps.

GPU compute remains a research track, but only after battle/menu/RenderDoc/AGI proves that candidate output is GPU-consumed or GPU-resident enough to amortize dispatch, barriers, and readback.

### Android Thor Status

- Direct route tool: `tools/thor_input_macro.ps1 -InputMode Direct`
- Debug bridge: `net.rpcsx.THOR_DEBUG_PAD` broadcast into `RPCSXActivity`, debug APK only
- Baseline run: `debug-captures/android-speed-sprint/20260516-042622-thor-input-custom/`
- Route/menu proof: `debug-captures/android-speed-sprint/20260516-043657-thor-input-custom/`
- Field FPS: about `16.4-17.5`, with pause/menu overlay about `18 FPS`
- Hot threads: `rsx::thread`, five SPU threads, and several PPU threads
- Memory: about `4.45 GB` RSS, about `1.9 GB` graphics memory
- Failed A/B: `SafeSpeed` in `debug-captures/android-speed-sprint/20260516-044501-thor-input-custom/` dropped to about `4.9 FPS` and then near `1.3 FPS`
- Semaphore A/B: Off at `debug-captures/android-speed-sprint/20260516-055612-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `17.43 FPS`; Fast at `debug-captures/android-speed-sprint/20260516-060122-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `17.03 FPS` with correct field visuals and roughly `98k` fast hits logged.
- RSX threaded A/B: `debug-captures/android-speed-sprint/20260516-061355-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `12.71 FPS`, worse than NeutralCore.
- Scheduler A/B: `debug-captures/android-speed-sprint/20260516-070447-eternal-sonata-field-stock-qualcomm-scene/scene.png` and `debug-captures/android-speed-sprint/20260516-070955-eternal-sonata-field-stock-qualcomm-scene/scene.png` stayed around `2.2 FPS` in the story/tree route; keep OS scheduling.
- DMA/MFC profile: `debug-captures/android-speed-sprint/20260516-063711-eternal-sonata-field-stock-qualcomm-scene/` confirmed image `0x958dfe208b686622`, PCs `0x25cc`/`0x451c`, about `4.29 GB` sampled DMA, and `0` RSX-local bytes.
- DMA/MFC verify: `debug-captures/android-speed-sprint/20260516-064251-eternal-sonata-field-stock-qualcomm-scene/` logged no output mismatches but also no exact repeat hits.
- MFC/list fast path: `debug-captures/android-speed-sprint/20260516-065348-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `17.59 FPS`, correct-looking but neutral versus baseline.
- Reduced-loop cache-key path: dev-core `es-reduced-loop-cache-key` SHA256 `CE15F5A95F636CAB3BCDFB347D9D3FE280B29924432652C37A0FC4225D1A69E9`; `debug-captures/android-speed-sprint/20260516-073902-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `19.86 FPS`, warm `debug-captures/android-speed-sprint/20260516-073947-eternal-sonata-field-stock-qualcomm-scene/scene.png` was about `19.61 FPS`, and menu proof `debug-captures/android-speed-sprint/20260516-074024-thor-input-custom/01-menu-reduced-loop-cache-key.png` was about `20.18 FPS`.
- Battle route attempt: `debug-captures/android-speed-sprint/20260516-074912-thor-input-custom/02-battle-candidate.png` and `debug-captures/android-speed-sprint/20260516-075332-eternal-sonata-battle-stock-qualcomm-scene/scene.png` did not reach battle; the right-walk macro hit the "Let's go back to Tenuto." boundary dialogue.

Stock Adreno Vulkan Feature Doctor showed Adreno 740 on Qualcomm driver `512.676.53`, Vulkan `1.3.128`. The stock driver exposes `VK_QCOM_tile_properties`, `VK_KHR_synchronization2`, `VK_EXT_descriptor_indexing`, and `VK_EXT_custom_border_color`, but not the QCOM tile-memory/tile-shading/perf-hint extensions we hoped might unlock a simple mobile-tiler shortcut. Vulkan work should therefore focus on barriers, render-target traffic, WCB cost, texture flushes, and pipeline churn.

The Vulkan/Adreno paper delta changes the GPU plan in one important way: any future GPU superpath must be batched and measured as a runtime/compiler problem, not a pile of tiny shaders. Tile-local Adreno work is worth testing on Turnip/custom drivers if `VK_QCOM_tile_shading` or tile-memory support appears, but stock-driver evidence points first toward RSX pass classification, barrier/load-store reduction, texture/upload coherence, and frame-pacing metrics. Compute/graphics overlap must be proven on Thor with timestamps plus AGI/Perfetto before a fast path relies on async compute.

## Thor Full CPU/GPU Utilization Research

### Core Principle

"Use the GPU more" is the right instinct, but on Android shared-memory systems it does not mean SPU work is free to move to Vulkan compute. Even with shared physical memory, GPU dispatch, synchronization, barriers, cache coherency, and readback can cost more than optimized CPU/SPU code.

Better target: remove stalls and rebalance the emulator pipeline.

- If GPU utilization is low, RSX may be starved by PPU/SPU/scheduler work.
- If CPU utilization is high, some of it may be useful compute, but some may be spin/wait/sync overhead.
- If both look moderate but FPS is low, frame pacing, locks, barriers, or memory bandwidth may be the bottleneck.

### CPU Utilization Track

Use Android CPU resources deliberately:

- Keep PPU/SPU/RSX native threads on appropriate performance cores where the fork already has scheduler/affinity support, but verify because Android can vary scheduling behavior.
- Consider Android Dynamic Performance Framework / Performance Hint sessions for frame-critical native threads. Android's own guidance says apps should report work duration and targets instead of using fake busy loops.
- Keep SPU LLVM/AArch64 feature gates correct for Thor: NEON, dotprod, i8mm/bf16 where safely usable, no bogus SVE assumption.
- Prioritize SPU reduced-loop, hot-block profiling, and MFC/list transfer fast paths.
- Keep logging quiet during FPS sweeps; verbose syscall/Ghidra probes can become the bottleneck.

CPU "full utilization" win condition:

- More time spent doing PPU/SPU/RSX work.
- Less time in syscall churn, sleeps, event queues, semaphore ping-pong, reservation waits, range locks, and avoidable memory copies.
- Lower hot-thread CPU for the same frame, or higher FPS at the same thermal envelope.

### GPU Utilization Track

Adreno 740 is a tile-based mobile GPU. Vulkan/RSX work should focus on mobile tiler correctness and bandwidth:

- Attachment `loadOp` / `storeOp`: avoid loading/storing render targets that are overwritten or not needed.
- Write Color Buffers: preserve correctness, but identify exactly where Eternal Sonata needs it and whether any pass can avoid extra traffic.
- Pipeline barriers: narrow stage/access masks and avoid full-pipeline flushes where possible.
- Texture flushes and render-target readbacks: locate forced synchronization and cache invalidation.
- Shader/pipeline churn: reduce pipeline variant compilation and descriptor churn.
- Driver matrix: stock Qualcomm first, then Turnip/Kimchi A6xx/A7xx with rollback and screenshot proof.

GPU "full utilization" win condition:

- GPU busy rises because useful RSX work is being fed earlier and with fewer stalls.
- CPU hot threads drop or frame time improves.
- No black spots, missing textures, flicker, broken lighting, or menu corruption.

### CPU-to-GPU Offload Track

Approved, but narrow:

- Only title/signature-gated.
- Verify-only first.
- Must compare normal CPU/SPU output against candidate fast output.
- Best candidates are bulk transforms, swizzles, decodes, skinning, particles, texture prep, or render-prep jobs whose output stays GPU-side.
- Bad candidates are tiny SPURS control loops, immediate PPU sync, semaphore wrappers, or frequent small readbacks.

Current Eternal Sonata field evidence does not justify Vulkan compute yet because `rsx_get_bytes` and `rsx_put_bytes` stayed zero in the hot samples.

## Proposed Next Implementation

### Experiment 1: Eternal Sonata DMA Job Verifier

Implemented on Android as a gated mode:

```text
debug.rpcsx.thor.es_dma_superpath=profile|verify
```

Scope:

- Title: `BLUS30161` only.
- SPU image: `0x958dfe208b686622`.
- Hot PCs: `0x25cc` and `0x451c`.
- Initial mode: no behavior change.

What it should collect:

- Job key: image signature, entry, group name, SPU name, max DMA PC, command pattern.
- Input hashes: GET/list source ranges read from main memory into SPU LS.
- Output hashes: PUT ranges written back to main memory.
- Range summary: top EAs, byte counts, repetition count, max DMA size, RSX-local flags.
- Repeat classification:
  - identical input, identical output;
  - identical pattern, different input, deterministic output;
  - unstable/non-cacheable.

Pass condition:

- Field route produces stable job signatures and hashes.
- No behavior change.
- Summary tells whether a cache/HLE skip is plausible.

Current result: field route produced stable image/PC signatures, but not exact reusable output hits. A cache/HLE skip is not justified yet.

### Experiment 2: Verify-Only Candidate Fast Path

Only if Experiment 1 shows repeated deterministic jobs:

- Run normal SPU job.
- Independently compute candidate output or replay cached output.
- Compare bytes after normal path.
- Log mismatch count and affected ranges.
- Still no fast skip.

Pass condition:

- Multiple field runs verify clean.
- Then repeat for battle and menu.

### Experiment 3: Fast Mode

Only after verify-clean:

- Skip or replace the specific job output.
- Keep rollback env gate.
- Measure Windows under matching host contention.
- Port to Android only after Windows correctness proof.
- Thor Max first, then Base/Pro risk label.

## Measurement Matrix

Every meaningful result should record:

- Scene: field, battle, menu.
- Platform: Windows lab or Thor Max.
- Core/build identity.
- Config and driver.
- Cache state.
- Host contention on Windows.
- FPS/frame time.
- CPU hot threads.
- GPU busy/queue behavior where available.
- Memory and thermals on Thor.
- Screenshots/video proof.
- Visual regressions.

## Near-Term Attack Order

1. Keep the Android DMA verifier available for short targeted runs, but leave it off for FPS sweeps.
2. Continue the cache-safe reduced-loop/codegen path and explain why it raises field FPS: inspect emitted blocks for image `0x958dfe208b686622`, especially PCs `0x25cc`/`0x451c`.
3. Add a small Android hot-block timing probe around SPU LLVM blocks for image `0x958dfe208b686622`.
4. Extend route to first battle; menu proof already exists, but the speed win is not correctness-locked until field + battle + menu all pass.
5. Investigate RSX/Vulkan traffic directly because `rsx::thread` stays hot even when MFC shortcuts are neutral.
6. Port only proven shared-core changes into Android vendored core.
7. Thor Max truth run with CPU/GPU traces, screenshots, and thermal/memory notes.

## Research Sources

- AYN official site: [AYN Thor listing](https://www.ayntec.com/)
- Retail Thor Max specs: [Best Buy Thor Max](https://www.bestbuy.com/product/thor-max-6-dualamoled-android-gaming-handheld-snapdragon-8-gen-2-16gb-ram-1tb-storage/J3R85PHQWG)
- Qualcomm SoC brief: [Snapdragon 8 Gen 2 product brief](https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/images/company/news-media/media-center/press-kits/summit-2022/day-1/documents/Snapdragon_8_Gen_2_Product_Brief.pdf)
- Android CPU performance hints: [Performance Hint API](https://source.android.com/docs/core/perf/performance-hint-api)
- Android GPU profiling: [Android GPU Inspector quickstart](https://developer.android.com/agi/start)
- Vulkan tiler guidance: [Tile Based Rendering best practices](https://docs.vulkan.org/guide/latest/tile_based_rendering_best_practices.html)
- Vulkan barrier guidance: [Using pipeline barriers efficiently](https://docs.vulkan.org/samples/latest/samples/performance/pipeline_barriers/README.html)
- Vulkan render-pass guidance: [Appropriate use of render pass attachments](https://github.khronos.org/Vulkan-Site/samples/latest/samples/performance/render_passes/README.html)
- Qualcomm profiling: [Snapdragon Profiler](https://www.qualcomm.com/developer/software/snapdragon-profiler)

## Bottom Line

The current speed baby is reduced-loop/codegen: it is the first measured positive path on Thor. The next move is to make that gain explainable, battle-safe, and bigger, while continuing RSX/Vulkan traffic analysis. GPU compute is still a later verify-first track, not the next blind leap.
