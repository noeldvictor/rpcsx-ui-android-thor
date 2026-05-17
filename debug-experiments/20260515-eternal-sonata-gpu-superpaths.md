# Eternal Sonata GPU Superpaths

- Status: `optimized-native-core-baseline`
- Title ID: `BLUS30161`
- Game: Eternal Sonata
- Platform scope: `experimental-gated`
- Owner: Codex + user
- Created: 2026-05-15
- Last updated: 2026-05-16

## Hypothesis

Thor and Steam Deck style shared APU systems should not leave obvious bulk emulator work on CPU when the GPU has headroom. Eternal Sonata may contain SPU/PPU/RSX helper jobs that are data-parallel enough to move into Vulkan compute or GPU-resident RSX-side paths.

This is not a plan to run the whole SPU emulator on GPU. The viable target is a small set of title/signature-gated superpaths:

- stable `BLUS30161` SPU image hash, DMA pattern, or PPU callsite;
- bulk arithmetic, transform, decode, copy, swizzle, skinning, particle, texture, or render-prep work;
- output consumed by RSX/GPU, or large enough to amortize dispatch/barrier/readback cost;
- exact CPU/SPU output available for verification before fast mode.

## Target Scene

- Required checkpoints: first playable field, first battle, and in-game menu.
- First candidate route: Windows field route from save `BLUS3016100`, then mirrored on Thor Max.
- Driver baseline: stock Qualcomm first, then Turnip/Kimchi only after correctness and stock-driver behavior are understood.
- Host baseline: Windows runs must have matching host-contention grade before any timing comparison.

## Gates And Rollback

- Every GPU superpath must be off by default.
- First implementation mode should be verify-only:
  - run normal CPU/SPU path;
  - run candidate GPU path against the same input;
  - compare output bytes or structured results;
  - log input signature, output hash, mismatch count, and scene.
- Fast mode can exist only after repeated verify-clean runs.
- First Thor target may be labeled `max-only`; Base/Pro promotion requires separate memory and stability proof.
- Rollback is disabling the debug property/config gate and returning to normal emulator behavior.

## Measurement Plan

- Windows:
  - Use Ghidra plus runtime logs to identify SPU jobs by image hash, DMA ranges, and output buffers.
  - Use RenderDoc/RSX traces to see whether candidate outputs flow into GPU-visible resources.
  - Use normalized `tools/windows_rpcs3_lab.ps1` runs for route/correctness and host-contention labels.
- Android Thor:
  - Use Thor Max first.
  - Capture field, battle, and menu with screenshots/video, FPS/frame pacing, memory, thermals, and hot threads.
  - Use AGI/Perfetto/Snapdragon tooling where available to confirm the GPU path increases useful GPU work instead of adding stalls.
- Metrics:
  - output match rate in verification mode;
  - sustained FPS/frame time;
  - CPU hot thread reduction;
  - GPU busy/queue behavior;
  - RSS/memory pressure, especially if labeled `max-only`.
- Regression checks:
  - no new black spots, missing textures, flicker, broken lighting, or menu corruption;
  - no shader/cache poisoning after toggling the gate;
  - no Base/Pro default promotion until memory risk is measured.

## Results

### Android Native Build-Type Breakthrough

- The largest Android/Rocknix gap was not a Vulkan superpath. It was the local
  dev-core build type.
- Before 2026-05-17, `tools/build_push_thor_core.ps1` defaulted to
  `:app:buildCMakeDebug[arm64-v8a]`, and active FPS cores came from
  `app\.cxx\Debug\...`.
- Debug compile commands for SPU/RSX code had `-g`, `_DEBUG`, and
  `-fno-limit-debug-info`, but no `-O2`/`-DNDEBUG`.
- RelWithDebInfo dev-core SHA:
  `BFC15D139DFA798D8FA7C4331DF1A32A14BFE3F863D3F177BCA240E3E3E40AC7`.
- Verified RelWithDebInfo flags:
  `-O2 -g -DNDEBUG -flto=thin`.
- Same 720p/u4/WCB-on profile:
  - Debug native moving field: about `13.3-13.7 FPS`.
  - RelWithDebInfo field after short movement: `27.35-28.08 FPS`.
  - RelWithDebInfo first battle tutorial prompt: `30.00 FPS`.
- Workflow fix: dev-core hot-swap now defaults to RelWithDebInfo and requires
  `-AllowDebugFallback` for Debug fallback.

Reading: GPU offload remains a research lane, but the immediate "get to the
Rocknix video" answer was to stop benchmarking an unoptimized native core. All
future GPU superpath claims must use an optimized native core baseline.

### Windows

- Implemented Windows RPCS3 candidate discovery gate:
  - env: `RPCS3_ES_GPU_PROBE=profile`
  - dump env: `RPCS3_ES_GPU_PROBE_DUMP_DIR`
  - script flag: `tools/windows_rpcs3_lab.ps1 -EternalSonataGpuProbe Profile`
  - wrapper flag: `tools/eternal_sonata_speed_sprint.ps1 -EternalSonataGpuProbe Profile`
  - summary tool: `tools/summarize_eternal_sonata_gpu_probe.ps1 -RunDir RUN_DIR`
- Probe runs now write ignored local sidecars under each run's `spu-images/` folder:
  - one 256 KB SPU local-storage image per image/entry signature;
  - RPCS3 SPU disassembly windows around hot max-DMA PCs.
- Built `rpcs3-upstream` Release `rpcs3` successfully after adding the sampled probe and max-DMA block hash field.
- Diagnostic field run:
  - run dir: `debug-captures/windows-lab/20260515-230825-eternal-sonata-gpu-probe-field-sampled-windows/`
  - scene: first playable field
  - result: reached 3D gameplay, FPS overlay visible, no obvious field visual corruption in screenshots
  - host contention: `high` because Vita3K was active, so this is not a clean FPS comparison
  - records: `1157`
  - total observed DMA: about `1,382.74 MB`
  - largest sampled job: about `2.98 MB`
  - hot image: `0x958dfe208b686622`
  - hot PCs: `0x25cc` for `CellSpursKernelGroup`, `0x451c` for `TCX_CellSpursKernelGroup`
  - RSX-local traffic: `0` records
- Earlier unsampled field run:
  - run dir: `debug-captures/windows-lab/20260515-224923-eternal-sonata-gpu-probe-field-windows/`
  - records: `43640`
  - total observed DMA: about `49,393.64 MB`
  - largest job: about `4.15 MB`
  - RSX-local traffic: `0` records
- Reading: the field sample contains huge repeated SPU DMA jobs but no GPU-local buffer traffic. The immediate high-value path is likely a verified title-gated SPU-kernel replacement, NEON/dotprod path, reduced-loop/codegen path, or scheduler/data-copy superpath. Vulkan compute remains open for battle/menu or later RenderDoc/AGI evidence, but a blind CPU-to-GPU rewrite would probably add readback/barrier cost.
- Disassembly smoke:
  - run dir: `debug-captures/windows-lab/20260515-232647-eternal-sonata-gpu-probe-disasm-smoke-windows/`
  - LS dump: `spu-images/BLUS30161-spu-image-958dfe208b686622-entry-00818-group-CellSpursKernelGroup-spu-0-CellSpursKernel0.ls.bin`
  - hot-PC disasm: `pc-025cc` and `pc-0451c`
  - quick read: both hot PCs are MFC/DMA command issue/wait code. This points toward SPU DMA-loop/job-HLE, reduced-loop/codegen, scheduler, or copy-path work before Vulkan compute.

### Android Thor

- Direct-mode field route now exists and reaches first controllable field on Thor Max.
- NeutralCore field baseline:
  - run dir: `debug-captures/android-speed-sprint/20260516-042622-thor-input-custom/`
  - field FPS: about `16.4-17.5`
  - route/menu proof: `debug-captures/android-speed-sprint/20260516-043657-thor-input-custom/`
  - memory: about `4.45 GB` RSS, about `1.9 GB` graphics memory
  - hot threads: `rsx::thread` plus multiple SPU and PPU threads; this is not pure GPU-idle CPU waiting.
- Stock Adreno Vulkan Feature Doctor from earlier 2026-05-16 captures:
  - GPU: Adreno 740, Qualcomm stock driver `512.676.53`, Vulkan API `1.3.128`
  - supported watched extension: `VK_QCOM_tile_properties`, `VK_KHR_synchronization2`, `VK_EXT_descriptor_indexing`, `VK_EXT_custom_border_color`
  - missing watched extensions include `VK_QCOM_tile_memory_heap`, `VK_QCOM_tile_shading`, `VK_QCOM_elapsed_timer_query`, `VK_QCOM_queue_perf_hint`, `VK_KHR_pipeline_binary`, `VK_KHR_dynamic_rendering_local_read`, `VK_KHR_unified_image_layouts`, and `VK_EXT_shader_tile_image`
  - conclusion: stock-driver dramatic Vulkan work should focus on barriers, render-target traffic, WCB cost, texture flushes, and pipeline churn, not QCOM tile-memory/tile-shading-only paths.
- Failed profile A/B:
  - `SafeSpeed` with RPCS3 Scheduler + SPU busy-wait dropped the opening route to low single digits in `debug-captures/android-speed-sprint/20260516-044501-thor-input-custom/`
  - do not treat CPU busy-wait as a GPU-utilization win for Eternal Sonata.
- Gated semaphore A/B:
  - Off capture: `debug-captures/android-speed-sprint/20260516-055612-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.43 FPS`, correct field visuals.
  - Fast capture: `debug-captures/android-speed-sprint/20260516-060122-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.03 FPS`, correct field visuals.
  - The gate logged roughly `98k` fast hits by field time, so the wrapper path is hot, but not the field bottleneck.
- `Multithreaded RSX=true` A/B:
  - capture: `debug-captures/android-speed-sprint/20260516-061355-eternal-sonata-field-stock-qualcomm-scene/scene.png`
  - result: about `12.71 FPS` with correct-looking field visuals, hot `RSX Offloader`, and worse throughput than NeutralCore.
  - decision: do not enable RSX threading by default; investigate RSX/Vulkan traffic directly instead.
- Android DMA/MFC candidate proof:
  - profile capture: `debug-captures/android-speed-sprint/20260516-063711-eternal-sonata-field-stock-qualcomm-scene/`
  - result: probe-overhead field overlay about `15.33 FPS`, correct field visuals, hot image `0x958dfe208b686622`, hot PCs `0x25cc` and `0x451c`, about `4.29 GB` sampled DMA, about `3.49 GB` PUT traffic, about `623.6 MB` GET traffic, about `176.8 MB` list GET traffic, and zero RSX-local bytes.
  - verify capture: `debug-captures/android-speed-sprint/20260516-064251-eternal-sonata-field-stock-qualcomm-scene/`
  - result: verify-overhead overlay about `11.13 FPS`; output mismatches `0`, but exact repeat hits `0`, with repeated patterns carrying changing input/output hashes.
  - interpretation: Android matches Windows. The hot work is real SPU/MFC traffic, but the field scene does not yet justify a naive Vulkan compute offload or output replay cache.
- First MFC/list-copy fast path:
  - capture: `debug-captures/android-speed-sprint/20260516-065348-eternal-sonata-field-stock-qualcomm-scene/scene.png`
  - result: about `17.59 FPS`, correct-looking field, `rsx::thread` still about `82.5%`, five SPU workers about `37.5-50%`, memory about `4.67 GB` RSS and `1.98 GB` graphics.
  - decision: correctness-safe but neutral. Keep looking at reduced-loop/codegen, broader copy/range-lock behavior, SPURS scheduling, and RSX/Vulkan traffic.
- Scheduler matrix follow-up:
  - `AltNeutral`: `debug-captures/android-speed-sprint/20260516-070447-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `2.22 FPS` in the story/tree route, `rsx::thread` about `97%`.
  - `OldNeutral`: `debug-captures/android-speed-sprint/20260516-070955-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `2.19 FPS` in the story/tree route, `rsx::thread` about `100%`.
  - decision: RPCS3 scheduler modes are bad for this title on Thor even without SPU reservation busy-wait; keep OS scheduling.
- Reduced-loop emission follow-up:
  - code fix: reduced-loop mode now uses a separate SPU cache file, `spu-safe-thor-rl-v1-tane.dat`, so normal FPS sweeps are not polluted by experimental compiler output.
  - dev-core: `es-reduced-loop-cache-key`, SHA256 `CE15F5A95F636CAB3BCDFB347D9D3FE280B29924432652C37A0FC4225D1A69E9`.
  - cold field: `debug-captures/android-speed-sprint/20260516-073902-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `19.86 FPS`, correct-looking field.
  - warm field: `debug-captures/android-speed-sprint/20260516-073947-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `19.61 FPS`, correct-looking field.
  - menu: `debug-captures/android-speed-sprint/20260516-074024-thor-input-custom/01-menu-reduced-loop-cache-key.png`, about `20.18 FPS`, correct-looking pause overlay.
  - decision: this is the first real positive signal from the hot-map direction, but it is CPU/SPU codegen, not GPU compute. Do not count it as a full speed win until first battle also passes.

## Evidence

- Existing SPURS/semaphore work shows Eternal Sonata is CPU/sync-heavy, but not all hot CPU work is GPU-offload friendly.
- Candidate discovery should start from SPU image hashes, DMA/output ranges, and RSX resource use, not from raw syscall volume.

## Decision

`windows-probe-android-baseline`: Android now confirms the Windows DMA/MFC hot-map for image `0x958dfe208b686622` around PCs `0x25cc` and `0x451c`. The tested semaphore, RSX-threading, RPCS3 scheduler modes, exact job-output replay, and first list-copy shortcut did not produce field FPS wins. Reduced-loop emission now gives a modest but real field/menu gain, so continue that codegen path while RSX/Vulkan traffic is investigated directly. Do not build Vulkan compute fast mode from the field sample until an RSX-local or GPU-consumed output path is observed.

## Notes

Good candidates: bulk math/transform/decode/render-prep jobs whose outputs are consumed by RSX or large buffers.

Bad candidates unless proven otherwise: tiny SPURS control loops, semaphore wait/post wrappers, immediate PPU synchronization, and any job requiring small frequent GPU readbacks.
