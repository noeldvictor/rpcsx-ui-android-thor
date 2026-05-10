---
date: 2026-05-10
semantic_name: thor-core-speedup-plan
target: AYN Thor Base/Pro/Max, Snapdragon 8 Gen 2, Adreno 740
repo_branch: master
status: research and implementation plan
---

# Thor Core Speedup Plan

## Short Answer

There is no single magic flag, but there are real wins left.

The best path is to make the fork stop behaving like a generic Android app and start behaving like a Thor-targeted emulator runtime:

1. Use Android Dynamic Performance Framework hints instead of making Android guess when PPU/SPU/RSX threads need big cores.
2. Add native thread classification for PPU, SPU, RSX, shader compile, and LLVM compile workers.
3. Make compile/cache work thermal-aware instead of always pushing the same worker count.
4. Finish real PPU/SPU cache preparation so first boot can be moved out of gameplay.
5. Keep caches on fast internal storage by default and make SD-cache mode clearly slower/emergency.
6. Profile on the Thor with simpleperf, Perfetto, and Android GPU Inspector before touching risky core settings globally.

The current fork already applies a good first pass: `Max LLVM Compile Threads = 4`, `LLVM Precompilation = true`, `SPU Cache = true`, blank/generic `Use LLVM CPU`, and a runtime CPU mask of `0xF8` so existing threads stay on Thor CPUs `3-7` where Android permits it. That is useful, but blunt.

## Sources Checked

- Qualcomm Snapdragon 8 Gen 2 product page: <https://www.qualcomm.com/smartphones/products/8-series/snapdragon-8-gen-2-mobile-platform>
- Android Performance Hint API: <https://developer.android.com/games/optimize/adpf/performance-hint-api?hl=en>
- Android NDK `APerformanceHint`: <https://developer.android.com/ndk/reference/group/a-performance-hint>
- Android Thermal API: <https://developer.android.com/games/optimize/adpf/thermal>
- Android Game Mode API: <https://developer.android.com/games/optimize/adpf/gamemode/gamemode-api>
- Android Game State API: <https://developer.android.com/games/optimize/adpf/gamemode/gamestate-api>
- Android Simpleperf guide: <https://developer.android.com/ndk/guides/simpleperf>
- Android GPU Inspector: <https://developer.android.com/agi>
- Android Vulkan design guidelines: <https://developer.android.com/ndk/guides/graphics/design-notes>
- RPCS3 configurations wiki: <https://wiki.rpcs3.net/index.php?title=Help%3AConfigurations>
- Local fork source: `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`
- Local fork source: `app/src/main/cpp/native-lib.cpp`
- Local bundled core source: `app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h`
- Local bundled core source: `app/src/main/cpp/rpcsx/rpcs3/util/Thread.cpp`
- Local bundled core source: `app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUThread.cpp`
- Local bundled core source: `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/RSXThread.cpp`

## Device Facts That Matter

Qualcomm lists Snapdragon 8 Gen 2 as a 4 nm platform with Kryo CPU up to 3.36 GHz, Adreno GPU, Vulkan 1.3 support, and improved CPU/GPU performance over the previous generation. For our measured AYN Thor, the practical CPU layout is:

| CPU | Core | Mask |
| ---: | --- | ---: |
| 0 | Cortex-A510 | `0x01` |
| 1 | Cortex-A510 | `0x02` |
| 2 | Cortex-A510 | `0x04` |
| 3 | Cortex-A715 | `0x08` |
| 4 | Cortex-A715 | `0x10` |
| 5 | Cortex-A710 | `0x20` |
| 6 | Cortex-A710 | `0x40` |
| 7 | Cortex-X3 | `0x80` |

Important masks:

| Group | CPUs | Mask | Use |
| --- | --- | --- | --- |
| Little cores | `0-2` | `0x07` | UI/background only, avoid LLVM compile bursts. |
| A715 pair | `3-4` | `0x18` | Good sustained high-performance work. |
| A710 pair | `5-6` | `0x60` | Good sustained work, likely safer than X3-only. |
| Prime | `7` | `0x80` | Latency-critical, easy to heat. |
| Performance plus prime | `3-7` | `0xF8` | Current safe heavy-work mask. |

The Base/Pro/Max Thor variants should share the same CPU/GPU performance preset. Their differences are mostly RAM and storage budget, not a different PPU compiler problem.

## What The Fork Already Does

`ThorPerformanceProfile.kt` currently detects AYN/Thor/kalama-like devices and applies:

- `Core@@Max LLVM Compile Threads = 4`
- `Core@@LLVM Precompilation = true`
- `Core@@SPU Cache = true`
- `Core@@Use LLVM CPU = ""`
- JNI `setProcessAffinityMask(0xF8)`
- Android thread priority bump with `THREAD_PRIORITY_MORE_FAVORABLE`

`native-lib.cpp` implements `setProcessAffinityMask` by walking `/proc/self/task` and calling `sched_setaffinity` on existing threads. This is better than doing nothing, and new threads often inherit the creating thread's affinity, but it is still a snapshot-style tool. It does not classify future PPU/SPU/RSX/LLVM workers by role.

The bundled core already has Android affinity config in `system_config.h`:

- `Core / Affinity / CPU0` through `CPU7`
- values are `General`, `PPU`, `SPU`, and `RSX`

The important catch: `CPUThread.cpp`, `RSXThread.cpp`, and `RSXOffload.cpp` only apply those masks when `Thread Scheduler Mode` is not `Operating System`.

The second catch: `Thread.cpp` treats `General` CPUs as shared by every class. That means setting CPUs `0-2` to `General` would still let PPU/SPU/RSX masks include the A510 cores. We need either a true `Unused`/`Background` class or a mask-based Android path before we trust this as the main Thor scheduler.

## Biggest Speedup Candidates

### 1. ADPF Runtime Hints

Android's Performance Hint API exists for exactly this shape of problem: a game tells the OS which thread group has a target duration and reports actual work duration. Android can then ramp CPU resources more intelligently. The docs explicitly warn that manual affinity is fragile across devices, which is true for a public Android game. For this fork, the right answer is probably hybrid:

- ADPF sessions for render/RSX, compile workers, and IO/cache work.
- Thor-specific affinity only after the user selects the Thor preset.
- Thermal headroom used to back off compile bursts before the device throttles.

Implementation shape:

- Add `ThorRuntimeHints.kt` for Java/Kotlin API access.
- Add NDK `APerformanceHint` helpers for native thread IDs.
- Expose a core thread snapshot export: thread name, TID, class, and current affinity.
- Send `notifyWorkloadIncrease` before PPU/SPU compile bursts.
- Report actual frame/compile durations where we can measure them.

Why this matters: Android docs say governor movement can lag, and the API gives the scheduler earlier, cleaner information. PPU compile pain is full of short brutal bursts, so this should help more than random busy loops.

### 2. Native Per-Class Affinity That Actually Excludes A510

The current process mask `0xF8` is a good safety belt. The next level is native thread classification:

| Class | Candidate mask | Why |
| --- | --- | --- |
| PPU runtime | `0x98` or `0xF8` | A715 plus X3 might help latency, but all perf cores may be smoother. |
| SPU runtime | `0x60` or `0xF8` | SPU is often the sustained CPU monster. |
| RSX/Vulkan | `0x80` or `0x18` | Needs latency, but X3-only can heat quickly. |
| LLVM compile workers | `0xF8`, thermal-limited | Avoid A510, avoid too many workers. |
| UI/background | `0x07` or no special pinning | Keep app UI responsive without stealing big cores. |

Concrete core change:

- Replace Android `Affinity CPU0..CPU7 = thread_class` behavior with direct masks:
  - `PPU Thread Affinity Mask`
  - `SPU Thread Affinity Mask`
  - `RSX Thread Affinity Mask`
  - `LLVM Compile Affinity Mask`
- Or add a `thread_class::background`/`unused` class and stop treating `General` as part of every heavy group on Android.

This is one of the clearest codebase wins because the plumbing is half there already.

### 3. Thermal-Aware Compile Thread Count

The current `Max LLVM Compile Threads = 4` is sane. The mistake would be assuming more is always better.

Recommended behavior:

- Start cold at 4 compile threads.
- If thermal headroom stays comfortable during first compile, allow 5 as an optional `Compile Burst` mode.
- If headroom approaches throttling, drop to 3 for the next compile phase or next boot.
- Log compile time, thread count, thermal headroom, battery state, and game ID.

Android's Thermal API exposes `getThermalHeadroom`; the docs recommend using thermal headroom over relying only on coarse thermal status. That gives us a real feedback loop instead of "Thor Max surely can take 6 threads" guessing.

### 4. Real PPU/SPU Cache Preparation

We already have Android UI plumbing for cache status and an optional JNI hook:

- `supportsPpuCachePreparation()`
- `preparePpuCache(path, titleId, progressId)`
- native lookup for `_rpcsx_preparePpuCache`

The bundled source currently does not expose a working `_rpcsx_preparePpuCache` export in `rpcsx-android.cpp`. Finishing that would not make LLVM faster, but it would move the pain away from "I pressed Play and now I wait forever."

Implementation target:

- Export `_rpcsx_preparePpuCache` from the bundled core.
- Run it from a foreground service.
- Use Thor affinity and ADPF compile hints during preparation.
- Store cache identity with core version, title ID, game executable hash, firmware/module state, LLVM CPU target, and relevant core settings.
- Show `Ready`, `Cold`, `Stale`, and `Building` in game detail.

This is probably the biggest user-perceived speedup, because warm cache second boot is the experience people actually want.

### 5. Local Game Config Cache Should Drive Safe Settings

RPCS3's wiki tracks per-game settings that differ from defaults, including CPU, SPU, GPU, ZCULL, shader mode, vblank, and advanced settings. We already started a local cache version of this idea.

Use it to avoid global risky settings:

- Keep global `SPU Block Size = Safe`.
- Allow per-game `Mega` only when the local config says so.
- Keep accurate settings only where needed.
- Apply vblank/framelimit/ZCULL settings per game.
- Surface a simple `Recommended for this game` state instead of showing users raw RPCS3 knobs.

This is not just UX. Bad global accuracy/performance knobs can make a game slower, broken, or both.

### 6. Vulkan/Adreno Work

The custom driver flow is already useful: Default driver first, curated Turnip options, and Thor/Adreno 740 warnings.

Next GPU work should be measured, not guessed:

- Use Android GPU Inspector system profiling to see CPU/GPU/battery/GPU-counter behavior on Thor.
- Use AGI frame profiling on games where runtime FPS is bad after warm cache.
- Verify Vulkan hardware path and driver selection, never SwiftShader/software.
- Preserve pipeline/shader caches on internal storage.
- Add per-game driver notes: `Default best`, `Turnip improves`, `Turnip breaks`.

Android's Vulkan design docs specifically call out pipeline reuse/render-pass decisions as app-level responsibilities. We should profile before changing renderer internals, because PPU compile is CPU-bound but runtime stutter can easily be shader/pipeline/cache related.

### 7. Build Flags And Core Binary

Current core CMake already has:

- `BUILD_LLVM on`
- `STATIC_LINK_LLVM on`
- `USE_LTO on`
- `DISABLE_LTO off`
- optional `USE_ARCH` that adds `-march=...`
- a suspicious `TEST_OVERRIDE_CPU` path that uses `-mcpu=cortex-a53` for aarch64

Do not force `Use LLVM CPU = cortex-x3` or compile everything for a single big core blindly. Generated code may run on A710/A715/X3, cache keys can change, and heterogeneous cores make this easy to get wrong.

Worth testing:

- Thor-only release artifact with only `arm64-v8a`, not `x86_64`.
- Benchmark generic flags vs `-mcpu=cortex-a710` vs `-mcpu=cortex-a715` if the NDK supports them cleanly.
- Keep `Use LLVM CPU` blank by default.
- Only expose LLVM CPU target as an advanced benchmark experiment, with a warning that cache reuse may change.

Expected gain: small to moderate for the app/core binary, possibly bigger only if a specific hot loop benefits. Runtime-generated PPU/SPU code and scheduling probably matter more.

## Codebase Performance Risks Seen Locally

These are not all critical, but they are worth tracking:

1. `GameCacheRepository.statusForGame()` walks the entire per-game cache directory to count files and bytes. If this runs during game detail recomposition on a huge cache, it can become visible jank. Cache the result and refresh explicitly or from a background worker.
2. `CacheStorageManager.status(calculateBytes = true)` can walk a large redirected cache. Settings should avoid full size calculation on every screen entry unless the user asks or the value is stale.
3. Current process affinity is called from several app paths, but native core thread classes are still not first-class in the UI. We need one source of truth for thread policy.
4. The source core has Android affinity support, but the current class mapping cannot cleanly say "never use A510 for heavy emulator work." Fix that before enabling scheduler mode globally.
5. GPU driver release fetching and ZIP inspection should stay off gameplay paths. It looks UI-bound now, which is fine.

## Bad Ideas To Avoid

- Do not set LLVM compile threads to 8 just because Thor has 8 cores. Three A510 cores are not where we want compile work, and heat can erase the gain.
- Do not pin everything to the X3 prime core. It will feel fast briefly, then heat and contention can punish the whole session.
- Do not store PPU/SPU/shader cache on SD by default. SD is for space emergencies.
- Do not globally set SPU Block Size to Mega/Giga. Use per-game config.
- Do not globally force `Use LLVM CPU = cortex-x3`.
- Do not enable RPCS3 scheduler mode until the Android affinity map is fixed or benchmarked with the current `General` behavior.

## Proposed Implementation Order

### Phase 1: Instrument Before Tuning

- Add per-game performance log entries:
  - title ID
  - core version
  - driver name
  - game path storage class
  - cache path storage class
  - LLVM CPU target
  - max LLVM compile threads
  - thread scheduler mode
  - PPU compile start/end
  - SPU/shader compile start/end when visible
  - first frame time
  - thermal headroom samples
- Add a simple export button for a performance report from the app.
- Use simpleperf on Thor for cold boot and warm boot.

### Phase 2: ADPF And Thermal

- Add Java/Kotlin Game Mode/Game State declarations and runtime checks.
- Add native `APerformanceHint` sessions for render and compile worker groups.
- Add thermal headroom polling at low frequency.
- Back off compile thread count when the device is near throttling.

### Phase 3: Native Affinity

- Add native export for thread snapshot: TID, name, class, current mask.
- Add direct masks for PPU/SPU/RSX/LLVM compile.
- Keep a `Thor Safe` preset:
  - heavy mask `0xF8`
  - compile threads `4`
  - generic LLVM CPU
- Add experimental presets hidden behind a warning:
  - `Compile Burst`: 5 threads, heavy mask `0xF8`
  - `Cool`: 3 threads, avoid hammering X3
  - `PPU Focus`: PPU `0x98`, SPU `0x60`, RSX `0x80`

### Phase 4: Cache Preparation

- Implement `_rpcsx_preparePpuCache`.
- Run it as a foreground service.
- Use internal cache by default.
- Let users pick SD only with the current warning.
- Mark stale caches loudly after core/settings changes.

### Phase 5: GPU Runtime Profiling

- Use Android GPU Inspector on Star Fox and at least one heavier PS3 title after warm cache.
- Record Default driver vs selected Turnip.
- Add local per-game driver notes.
- Do not make Turnip the default globally unless the measured game set agrees.

## First Concrete Patch I Would Do Next

The most useful next patch is not a random speed knob. It is a `ThorPerformanceTelemetry` layer:

- Adds thermal headroom sampling.
- Logs cold/warm boot timings.
- Logs current affinity and thread scheduler mode.
- Records compile worker count.
- Exports a small markdown or JSON report per run.

Then the next code patch should be the native affinity fix:

- Add direct PPU/SPU/RSX/LLVM masks or an `Unused` class for A510 exclusion.
- Add an app-side Thor preset that sets those masks only after the core supports them cleanly.

This keeps us from doing placebo tuning. Once we can see where time goes, we can make the Thor sweat in the useful places instead of just making it hot.
