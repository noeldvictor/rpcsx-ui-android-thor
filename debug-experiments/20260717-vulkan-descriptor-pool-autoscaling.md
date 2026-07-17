# Vulkan descriptor-pool autoscaling

Date: 2026-07-17

## Goal

Reduce Vulkan descriptor-pool startup allocation and growth pressure on AYN Thor without changing descriptor contents, draw ordering, or synchronization.

## Upstream basis

- Adapted RPCS3 `8e370c2` (automatic descriptor-pool sizing).
- Adapted RPCS3 `bf85a3f` (debounced pool growth).
- Did not take `3b1abec`; its bulk aligned allocator depends on the newer `rsx::data_heap` / `ring_buffer_helper` architecture that this tree does not have.

## Local adaptation

This renderer uses one older global draw descriptor pool rather than the newer per-pipeline arrangement. The global renderer and shader interpreter now start at 256 sets and grow on demand up to the existing device-derived ceiling (normally 32,768, or 8,192 on devices with lower descriptor-indexing limits). Compute and overlay pools retain their fixed 1,024-set behavior.

Each newly created subpool stores its actual set capacity. Allocation, cache fill, and rollover decisions use that recorded capacity. A failed Vulkan pool creation rolls the autoscaling state back before retrying.

The modeled new-pool sequence at a 32,768 ceiling is:

```text
256, 256, 512, 512, 1024, 1024, 2048, 2048,
4096, 4096, 8192, 8192, 16384, 16384, 32768, 32768
```

The initial reservation is therefore 128 times smaller than the former 32,768-set pool. Repeating each size once before doubling avoids runaway growth after a single overflow.

## Host proof

- ARM64 Android RelWithDebInfo build: passed (`BUILD SUCCESSFUL in 1m 31s`).
- Artifact: `app/build/intermediates/cxx/RelWithDebInfo/724a6w64/obj/arm64-v8a/librpcsx-android.so`
- Size: `1,351,033,144` bytes.
- SHA-256: `85B82314153CC3F20016A3AC1C7096F0F67BF9753881FD3C070653AF1A7676C7`.
- Modified UTC: `2026-07-17T05:20:35.0134261Z`.
- `git diff --check`: passed.
- Call-site and `maxSets`/`max_sets()` audit: passed.

## Thermally bounded Thor field validation

The initial implementation round was host-only. After the battery sensor reported `25.0 C`, one no-repeat field validation was allowed on the AYN Thor (`kalama`). The already-built core was pushed without launching, then the route used direct input, stock Qualcomm Vulkan, quiet logging, all experimental speed properties off, an eight-second Perfetto trace, no screen recording, a `35 C` cutoff, and automatic force-stop.

Core identity:

- Commit: `76f95af3b`.
- SHA-256: `85B82314153CC3F20016A3AC1C7096F0F67BF9753881FD3C070653AF1A7676C7`.
- Push evidence: `debug-captures/20260717-012850-76f95af3b-descriptor-autoscale-dev-core-push`.

Exact route command:

```powershell
$env:ANDROID_SERIAL='c3ca0370'
$macro='gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;wait:20000;shot:load-save-list;check:visual:load-menu;cross;wait:1000;dpad_up;wait:500;cross;wait:35000;shot:load-complete;check:visual:load-menu;cross;wait:12000;shot:loaded-field;check:visual:field-frame;check:guest:loaded-field'
.\tools\eternal_sonata_speed_sprint.ps1 -Action AndroidRouteScene -Scene field -InputMacro $macro -AndroidInputMode Direct -AndroidLogMode Quiet -Driver stock-qualcomm -Core 76f95af3b-descriptor-autoscale -AndroidRoutePostWaitSeconds 1 -AndroidSceneSeconds 8 -AndroidThermalPollSeconds 2 -AndroidMaxBatteryTemperatureC 35 -NoScreenRecord
```

Evidence:

- Route capture: `debug-captures/android-speed-sprint/20260717-013012-thor-input-custom`.
- Scene capture: `debug-captures/android-speed-sprint/20260717-013312-eternal-sonata-field-stock-qualcomm-scene`.
- The automated field gate passed: field present, no story/title/load/battle misclassification, and no black frame.
- `14-loaded-field.png` showed `28.00 FPS`.
- `scene.png`, captured about 16 seconds later, showed `28.96 FPS`.
- Both field frames were visually clean: no black spots, missing textures, lighting corruption, or menu overlay. Character/particle state changed between frames, so the field was not a frozen duplicate.
- Guest guards found no fatal, access violation, Vulkan device loss, verification failure, or unknown draw.
- The pinned RPCSX process survived the route and capture, then was force-stopped successfully.
- Battery temperature remained `25.0 C` at every five-second route poll and every two-second capture poll; Android thermal status was `0`. No second run was made.
- Perfetto trace completed: `39,572` bytes. This host has no trace processor installed, so the trace is retained but not decoded in this round.
- Field snapshot: GPU `680 MHz` with `843132 / 1008682` busy counters (about `83.6%`), RSX thread `94.5%` CPU, and five main SPU workers at about `45.9%-56.7%` CPU.
- Memory snapshot: total PSS `2,381,536 KiB`, RSS `2,597,024 KiB`, and swap `984 KiB`.

Classification: `valid-field-triage`; `not-comparable` for patch-specific speed attribution. The current build is near the 30 FPS field target and materially above the historical roughly 17 FPS field evidence, but this was not a stock-versus-patch A/B and includes the accumulated core work. It therefore does not prove that descriptor autoscaling alone caused the increase.

Still missing before a full stability/speed claim: in-game menu correctness, active first-battle correctness and FPS, a temporal capture able to detect transient flicker, and a matched comparison if individual-patch attribution is required.
