---
date: 2026-05-12
semantic_name: thor-ps3-speed-hack-research
target: AYN Thor Base/Pro/Max, Snapdragon 8 Gen 2, Adreno 740, Android 13
status: deep research report and implementation map
---

# AYN Thor PS3 Speed Hack Research

## Short Answer

The best Thor speed hacks are not a single magic GPU toggle. The biggest likely wins are:

1. Mine upstream RPCS3 arm64 work aggressively, especially new AArch64 dot-product SPU paths.
2. Treat Thor as a heterogeneous CPU target, not as "8 cores equals 8 compile workers."
3. Keep first-boot compilation controlled, because real Thor logs already caught native OOM during full PPU precompile.
4. Build a guarded cache-preparation mode instead of forcing expensive precompile on every first launch.
5. Use Android Performance Hint and Thermal APIs to tell Android what the emulator is doing.
6. Keep GPU work per-game and measured: Vulkan driver choice, shader/pipeline cache behavior, RSX accuracy options, and second-screen overhead.
7. Avoid global unsafe RPCS3 knobs. Many "speed" settings are really "accuracy tradeoffs" and should be title-specific.

Most important correction: RPCS3 not officially supporting Android does not mean we cannot borrow from RPCS3 arm64. We absolutely can. The right framing is:

```text
Borrow proven RPCS3 arm64 compiler/runtime ideas,
then adapt them to Android JNI, app lifecycle, memory limits, thermals, and Adreno Vulkan.
```

## Target Facts

AYN's Thor Base/Pro/Max target is Snapdragon 8 Gen 2 with Adreno 740, Android 13, two AMOLED displays, active cooling, a 6000 mAh battery, LPDDR5X, and UFS 4.0. AYN's system-parameter sheet lists:

| Area | Thor Base/Pro/Max |
| --- | --- |
| SoC | Snapdragon 8 Gen 2 |
| Process | 4 nm |
| CPU | 1 GoldPlus at 3.2 GHz, 4 Gold at 2.8 GHz, 3 Silver at 2.0 GHz |
| GPU | Adreno 740 at 680 MHz |
| RAM | 8 GB / 12 GB / 16 GB LPDDR5X at 4200 MHz |
| Storage | 128 GB / 256 GB / 1 TB UFS 4.0 |
| OS | Android 13 |

The connected Thor topology measured earlier in this repo:

| CPU | Core | Part | Mask | Suggested role |
| ---: | --- | --- | ---: | --- |
| 0-2 | Cortex-A510 | `0xd46` | `0x07` | UI, background, light service work |
| 3-4 | Cortex-A715 | `0xd4d` | `0x18` | sustained high-performance work |
| 5-6 | Cortex-A710 | `0xd47` | `0x60` | sustained high-performance work |
| 7 | Cortex-X3 | `0xd4e` | `0x80` | latency-critical bursts |
| 3-7 | performance + prime | mixed | `0xF8` | current heavy-work safety mask |

Thor Lite is Snapdragon 865 / Adreno 650. It should remain compatibility-only and should not inherit the same masks or performance assumptions.

## Why PS3 Is Hard On Thor

PS3 emulation is mostly a CPU and memory problem before it is a pure GPU problem.

The PS3 Cell architecture has a PowerPC PPU and multiple SPU workers. RPCS3 recompiles that guest code into host code. On x86 desktop, RPCS3 leans heavily on AVX/AVX2/AVX-512-class SIMD and high single-thread performance. Thor has a very good mobile SoC, but it has:

- Heterogeneous cores, so generated code and threads can land on different core classes.
- Shared thermal and power limits, so short wins can turn into sustained throttling.
- Android memory limits and LMK behavior, not a desktop memory model.
- A mobile Vulkan stack with Adreno proprietary or custom Turnip drivers.
- Two active displays, where the second screen can add small but real overhead.

RPCS3's official quickstart recommends powerful x64 CPUs for best PC results and says laptop performance varies heavily on lower-power chipsets. That does not doom Thor, but it tells us where to focus: reduce CPU translation cost, reduce memory stalls, avoid compile storms, keep caches hot, and use the GPU only where it is actually the bottleneck.

## Current Local Fork State

Current Thor startup profile in `app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt`:

- `Max LLVM Compile Threads = 2`
- `LLVM Precompilation = false`
- `SPU Cache = true`
- `Use LLVM CPU = "cortex-a78"`
- on-disk shader cache enabled
- runtime process affinity mask `0xF8`

This matches the 2026-05-11 crash finding: full first-boot PPU precompile with 4 workers crashed around PPU LLVM compilation with `llvm::report_bad_alloc_error`, `memory_commit(... errno=12=Out of memory)`, and high thermals. So the conservative default is justified.

The current profile is a survival baseline, not the final performance state. Long-term, we want a guarded cache builder that can use more threads only when memory and thermals say it is safe.

## The Big Upstream RPCS3 Arm64 Opportunity

This is the most important new finding from the current research.

Upstream RPCS3 has arm64 support for Linux, macOS, and Windows-on-ARM. The official project says it is not targeting Android/iOS, but the arm64 work still contains emulator-level ideas we can reuse.

Concrete local diff:

- Upstream checkout: `rpcs3-upstream`, commit `cd7cb1c`.
- Vendored Android RPCSX core: `rpcsx-ui-android/app/src/main/cpp/rpcsx`, commit `e309e1e`.
- Diff stats show large deltas in AArch64 backend files, `SPULLVMRecompiler.cpp`, `SPUCommonRecompiler.cpp`, and `CPUTranslator.cpp`.
- Upstream `SPULLVMRecompiler.cpp` includes AArch64 `m_use_dotprod` paths using `sdot` and `udot` for SPU `GB`, `GBH`, `GBB`, and `SUMB`.
- The vendored Android core still visibly has x86 GFNI/AVX/VNNI paths for those opcodes but no matching AArch64 dot-product path.

That is not vague inspiration. It is a specific import candidate.

Why it matters:

- Arm dot-product instructions operate on packed 8-bit data and accumulate into 32-bit lanes.
- SPU `GB`, `GBH`, `GBB`, and `SUMB` are bit/byte packing and summing patterns that map naturally to that kind of instruction.
- Linux exposes dot-product availability through `HWCAP_ASIMDDP`; the fork already reports this in Thor Feature Doctor as `ASIMDDP/dotprod`.
- Snapdragon 8 Gen 2 should be checked through HWCAP on the actual Thor before enabling any path.

### Import Target 1: SPU DotProd

Files to inspect and port carefully:

```text
rpcs3-upstream/rpcs3/Emu/CPU/CPUTranslator.cpp
rpcs3-upstream/rpcs3/Emu/CPU/CPUTranslator.h
rpcs3-upstream/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp
rpcs3-upstream/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp
rpcs3-upstream/rpcs3/util/sysinfo.cpp
rpcs3-upstream/rpcs3/util/sysinfo.hpp
```

Core pieces:

- `utils::has_dotprod()`
- `m_use_dotprod`
- `sdot(...)` and `udot(...)` helper lowering
- SPU opcode paths for `GB`, `GBH`, `GBB`, `SUMB`
- any related LLVM IR helper changes from upstream

Expected payoff:

| Metric | Expected impact |
| --- | --- |
| Cold PPU compile | little direct improvement |
| Warm gameplay FPS | possible medium uplift in SPU-heavy games |
| Audio stutter | possible improvement where SPU workers fall behind |
| Heat | possible improvement if fewer host instructions do the same SPU work |
| Risk | medium, because LLVM helper changes may be entangled with upstream recompiler changes |

Validation plan:

1. Confirm Thor Feature Doctor reports `ASIMDDP/dotprod`.
2. Port the minimum upstream dotprod support into a branch.
3. Add a log line when `m_use_dotprod` is enabled.
4. Add compile-time counters for `GB`, `GBH`, `GBB`, and `SUMB` blocks.
5. Compare warm gameplay, not just boot time.
6. Test at least one SPU-heavy game, one lighter 2D/PSN title, and one title known to stress audio.

### Import Target 2: AArch64 JIT And Signal Work

Upstream RPCS3's arm64 support solved platform-neutral emulator problems:

- JIT gateway/tail-call assumptions originally shaped around x86.
- AArch64 signal handling and fault decoding.
- arm64 calling-convention and register handling.
- non-x86 fallback correctness in high-performance code.

Android may need different wrappers, but the core lessons are valuable. This is especially relevant for native crashes where the current log cannot clearly identify whether the fault is JIT code, VM reservation, RSX memory, or Android Vulkan.

Import/diff target:

```text
rpcs3-upstream/rpcs3/Emu/CPU/Backends/AArch64/*
rpcs3-upstream/rpcs3/Emu/Cell/PPUThread.cpp
rpcs3-upstream/rpcs3/Emu/Cell/PPUTranslator.cpp
rpcs3-upstream/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp
rpcs3-upstream/rpcs3/util/sysinfo.*
```

### Import Target 3: 16K Page-Size And Dirty Tracking Lessons

RPCS3's arm64 blog calls out that many arm64 platforms use 16 KiB page granularity, while PS3 expects 4 KiB behavior. Even when games boot, dirty-page tracking can become expensive because small PS3 GPU objects share larger host pages.

Android Snapdragon devices often use 4 KiB pages, but this still matters:

- Do not assume page granularity forever.
- Dirty texture/page tracking is one of the places where arm64 platform assumptions matter.
- If Thor forks move to newer Android kernels or other handhelds, the page-size lesson becomes important.

Speed-hack angle:

- Add startup logging for host page size.
- Add telemetry around dirty-page invalidation and texture re-upload spikes.
- If page size is 16K on a future device, avoid blaming "GPU driver" first.

## CPU Speed Hacks

### 1. Use Upstream DotProd SPU Paths

Priority: highest native optimization.

This is the best "good idea from RPCS3 arm64" currently visible. It targets translation quality, not just thread placement.

Implementation notes:

- Gate on `HWCAP_ASIMDDP`.
- Keep `Use LLVM CPU = cortex-a78` until we prove safer CPU target strings.
- Avoid enabling `cortex-a510`, `cortex-a710`, `cortex-a715`, or `cortex-x3` in the current vendored LLVM on Thor if those targets imply SVE/SVE2 while the device does not expose SVE.
- Preserve cache identity carefully. A new CPU feature path may require stale-cache invalidation.

### 2. Guarded PPU Cache Builder

Priority: very high user-perceived speedup.

The current safe default disables full PPU precompile because it crashed on Thor. That is a good default, but users still need a way to prepare cache deliberately.

Build a `Prepare Cache` action:

- Foreground service.
- Internal storage by default.
- Start with 2 compile workers.
- Sample RSS/swap, thermal headroom, battery state, fan/thermal logs if exposed.
- If memory stays healthy, optionally step to 3 or 4 workers.
- If RSS approaches danger or thermal headroom is poor, step down.
- Write a per-game cache report.

Do not make "more compile threads" a normal startup default.

Suggested modes:

| Mode | Compile threads | PPU precompile | Use case |
| --- | ---: | --- | --- |
| Thor Safe | 2 | off | default launch stability |
| Cache Builder Safe | 2 | on | user explicitly prepares cache |
| Cache Builder Balanced | 3 | on | Pro/Max after memory checks |
| Cache Builder Burst | 4 | on | cold device, plugged in, monitored |

### 3. Per-Class Native Affinity

Priority: high after telemetry.

The wrapper currently pins existing threads to `0xF8`. This avoids the A510 cores for current threads, but it is blunt.

Better:

| Thread class | Candidate mask | Notes |
| --- | --- | --- |
| PPU runtime | `0x98` or `0xF8` | A715 plus X3 may help latency; all performance cores may smooth stalls |
| SPU runtime | `0x60` or `0xF8` | sustained SPU load may be better on A710/A715 than X3-only |
| RSX/Vulkan | `0x80` or `0x18` | latency-sensitive but can heat prime core |
| LLVM compile | `0xF8`, adaptive threads | keep off A510 |
| UI/background | `0x07` or OS default | keep app responsive without stealing big cores |

Current core has `Core / Affinity / CPU0..CPU7`, but the `General` class is shared into PPU/SPU/RSX masks, so it cannot cleanly say "never use A510 for heavy work." Fix with direct masks or a true background/unused class before relying on scheduler mode globally.

### 4. Android Dynamic Performance Framework

Priority: high, low risk.

Android's Performance Hint API is built for exactly this problem: tell the OS the target and actual duration for thread groups instead of trying to trick governors with wasteful load. Android docs explicitly warn that fixed affinity is fragile across device models.

Use it for:

- gameplay/render frame session
- compile/cache-builder session
- shader/pipeline compile bursts
- occasional workload spike hints before expensive transitions

Use Thermal API alongside it:

- sample `getThermalHeadroom` no more than recommended frequency
- record thermal headroom in run logs
- reduce compile threads or frame target before throttling

### 5. SPU Settings Are Per-Game, Not Global

Candidate knobs:

| Setting | Possible speed effect | Risk |
| --- | --- | --- |
| Preferred SPU Threads | can reduce contention | wrong value hurts or stutters |
| SPU Block Size = Mega | can help some low-thread systems | can break games |
| SPU Loop Detection | can reduce busy waits | can break timing |
| Max SPURS Threads | can reduce overload | can break SPURS-heavy games |
| SPU XFloat Accuracy Relaxed | can speed some math | visual/gameplay correctness risk |

Use recommended settings database and local title profiles. Do not globally set Mega/Giga or relaxed math.

### 6. Fast Forward As Runtime Speedhack

The fork already has Fast Forward 2x via `Core -> Clocks scale = 200`.

This is a gameplay speedhack, not an emulator performance speedup. It only works when the game already has headroom. On borderline PS3 games it can cause audio breakage, timing bugs, and more heat.

Keep it as:

- runtime toggle
- per-game sticky preference optional later
- visible warning if game cannot sustain 1x

Do not combine with unstable CPU/GPU accuracy hacks by default.

## GPU Speed Hacks

### GPU Reality Check

Qualcomm lists Snapdragon 8 Gen 2 as supporting Vulkan 1.3, OpenGL ES 3.2, and OpenCL 2.0 FP. Adreno 740 is strong for Android emulation, but PS3/RPCS3 often bottlenecks on CPU, memory synchronization, shader compilation, or readbacks rather than raw shader throughput.

GPU work should be measured after warm cache.

### 1. Driver Selection: Default First, Turnip Per-Game

Default proprietary driver should remain fallback. Turnip can help emulator workloads, but driver regressions are common.

For Thor / Adreno 740:

- prefer A6xx/A7xx Turnip packages for experiments
- label A8xx/Gen8 packages as not for Thor unless testing another device
- keep per-game driver notes:
  - `Default best`
  - `Turnip improves`
  - `Turnip breaks`
  - `Unknown`

Do not make a bleeding-edge Turnip global default.

### 2. Shader And Pipeline Cache Preservation

Vulkan pipeline creation can be expensive, and Vulkan puts more responsibility on the app/emulator to cache and reuse pipeline state. Keep shader and pipeline caches on fast internal storage where possible.

Speed-hack tasks:

- never disable on-disk shader cache for normal Thor use
- label stale cache after driver/core/settings changes
- avoid moving cache to SD unless user needs the space
- track driver ID in cache metadata

### 3. RSX Accuracy Settings

Useful but risky knobs:

| Setting | Speed meaning | Risk |
| --- | --- | --- |
| ZCULL Accuracy = Relaxed/Approximate | less strict occlusion behavior | missing geometry or effects |
| Write Color Buffers off | avoids CPU/GPU sync/readback | broken effects in games needing it |
| Read Color/Depth Buffers off | avoids expensive readbacks | broken post-processing or shadows |
| Strict Rendering Mode off | faster | accuracy risk |
| Multithreaded RSX on | can improve RSX workload distribution | title-dependent |
| Asynchronous Texture Streaming on | can reduce stalls | driver/title-dependent |
| Anti-Aliasing disabled | lower GPU work | visual downgrade |
| Resolution Scale lower | lower GPU work | visual downgrade |

These belong in per-game config, not the global Thor preset.

### 4. Second Screen And Overlay Cost

DROIX testing saw Thor benchmark differences with the bottom screen on versus off. For PS3, the second screen does not add gameplay value most of the time.

Speed-hack rules:

- Add `PS3 Performance Mode`: bottom display off or static minimal overlay.
- Avoid high-frequency Compose redraws while game is running.
- Keep performance overlay lightweight.
- Avoid animated UI over Vulkan surface during gameplay.

### 5. AGI And GPU Profiling

Use Android GPU Inspector for warm-cache frame captures:

- Vulkan API calls
- framebuffer content
- draw calls
- GPU memory
- pipeline data
- shader resources
- render state

Run AGI only after CPU compile/cache is not the dominant bottleneck. Otherwise the GPU trace will mostly prove the CPU is late.

## Memory And Storage Speed Hacks

### 1. Avoid Whole-File ISO Reads

The 2026-05-11 notes already caught huge direct ISO reads and Android LMK around 6 GB RSS. Treat streaming as mandatory.

Rules:

- Do not reintroduce whole-file ISO reads.
- Do not extract full ISO contents into memory.
- Keep large archive reads streaming.
- Add memory telemetry to every long boot/debug stream.

### 2. Internal UFS For Cache

Thor Base/Pro/Max have UFS 4.0 internal storage. Use it for:

- PPU cache
- SPU cache
- shader/pipeline cache
- game metadata cache

SD card is fine for game storage, but compiled cache on SD should remain an emergency option with warnings.

### 3. Cache Identity

Cache identity should include:

- title ID
- executable hash
- core version/hash
- firmware/module state
- LLVM CPU target
- relevant CPU feature flags
- driver ID where shader cache is involved
- settings that alter generated code

If dotprod codegen lands, stale-cache labeling becomes more important.

## What Not To Do

- Do not dismiss upstream RPCS3 arm64 because Android is unofficial.
- Do not claim this is official RPCS3 Android.
- Do not set compile threads to 8.
- Do not pin everything to the Cortex-X3.
- Do not globally enable `SPU Block Size = Mega` or `Giga`.
- Do not globally relax RSX/PPU/SPU accuracy.
- Do not force `cortex-x3`, `cortex-a715`, `cortex-a710`, or `cortex-a510` CPU targets until LLVM feature output is proven safe on Thor.
- Do not store compiled cache on SD by default.
- Do not use fast-forward as proof that a game is performant.
- Do not profile GPU before warm-cache CPU bottlenecks are under control.

## Prioritized Implementation Queue

### Phase 1: Report And Tracking

Done:

- Add `AGENTS.md` upstream arm64 mining section.
- Record the dotprod SPU import candidate.
- Keep current startup defaults conservative after the PPU OOM crash.

### Phase 2: Upstream DotProd Port Spike

Goal: import the smallest working upstream AArch64 dot-product SPU path.

Tasks:

1. Diff upstream `CPUTranslator.*`, `SPULLVMRecompiler.cpp`, and helper files.
2. Add `utils::has_dotprod()` or equivalent if missing in vendored path.
3. Add `m_use_dotprod`.
4. Port `sdot/udot` helper lowering required by `GB/GBH/GBB/SUMB`.
5. Gate on Android HWCAP.
6. Log enablement and test boot.

Success criteria:

- Build succeeds for `arm64-v8a`.
- Thor Feature Doctor reports dotprod available.
- Emulator logs `m_use_dotprod` enabled or equivalent.
- No regression in a simple game.
- Warm-cache benchmark shows no worse performance.

### Phase 3: Guarded Cache Builder

Goal: regain the user-perceived speed of precompiled cache without the OOM crash.

Tasks:

- implement/export `_rpcsx_preparePpuCache`
- run from foreground service
- use memory and thermal telemetry
- adapt compile worker count
- write per-game cache report

### Phase 4: Per-Class Thread Policy

Goal: replace process-wide `0xF8` with real PPU/SPU/RSX/LLVM masks.

Tasks:

- expose native thread snapshot: name, TID, class, current mask
- add direct masks or a background/unused affinity class
- test scheduler mode interactions
- keep ADPF sessions active

### Phase 5: GPU Per-Game Profiles

Goal: make GPU speed hacks title-specific and measurable.

Tasks:

- add per-game driver notes
- test default vs Turnip A6xx/A7xx
- preserve shader/pipeline caches
- AGI traces for warm-cache bottleneck games
- only then tune RSX settings

## Benchmark Matrix

Every performance claim should record:

| Field | Why |
| --- | --- |
| Title ID and game name | PS3 performance is wildly title-specific |
| Core commit/hash | compiler behavior changes |
| GPU driver | proprietary vs Turnip can dominate graphics behavior |
| LLVM CPU target | affects generated code and cache |
| Dotprod enabled | key new arm64 path |
| Compile threads | affects cold boot and OOM risk |
| PPU precompile on/off | changes first launch behavior |
| Cache state | cold, building, warm, stale |
| Storage location | internal vs SD |
| Thermal headroom/status | explains throttling |
| RSS/swap peak | catches LMK/OOM risk |
| First frame time | user-perceived boot speed |
| Warm FPS/frame time | real gameplay speed |
| Audio stutter | SPU underrun symptom |
| Crash/tombstone | correctness gate |

## Best Bets Ranked

| Rank | Idea | Expected payoff | Risk | Why |
| ---: | --- | --- | --- | --- |
| 1 | Port upstream AArch64 dotprod SPU paths | medium in SPU-heavy games | medium | concrete upstream code exists for Thor-relevant ISA |
| 2 | Guarded cache builder | high user-perceived | medium | avoids startup OOM while restoring warm-cache experience |
| 3 | ADPF + Thermal | low-medium but broad | low | Android-native way to stabilize clocks without waste |
| 4 | Native per-class affinity | medium | medium | better than process-wide `0xF8`, but needs careful thread classification |
| 5 | Internal cache policy + stale labels | medium user-perceived | low | avoids SD stalls and bad cache reuse |
| 6 | Per-game RSX/GPU settings | title-dependent | medium | can help, but global use breaks games |
| 7 | Turnip per-game driver profiles | title-dependent | medium | useful on Adreno, but regressions are normal |
| 8 | Fast Forward 2x | only if headroom exists | medium | gameplay speedhack, not a performance fix |

## Bottom Line

The strongest path is:

```text
Use upstream RPCS3 arm64 as the compiler/runtime idea source.
Port dotprod SPU codegen first.
Keep Thor startup safe.
Build a guarded cache-prep pipeline.
Use Android ADPF/thermal telemetry.
Tune GPU per game after warm-cache CPU bottlenecks are understood.
```

That is the practical speed-hack strategy for AYN Thor. It is not "wait for official Android RPCS3." It is "borrow the arm64 work that already exists, then solve the Android handheld parts ourselves."

## Sources

- AYN official Thor listing: https://www.ayntec.com/
- AYN Thor system-parameters sheet: https://manuals.plus/m/7e96f29e93e4e571eb4e2ee5f2220a98db9ab0a295678d69157e99ddfc948028.pdf
- Qualcomm Snapdragon 8 Gen 2 product page: https://www.qualcomm.com/smartphones/products/8-series/snapdragon-8-gen-2-mobile-platform
- Qualcomm Snapdragon 8 Gen 2 product brief: https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Snapdragon-8-Gen-2-Product-Brief.pdf
- RPCS3 quickstart hardware requirements: https://rpcs3.net/quickstart
- RPCS3 arm64 blog: https://blog.rpcs3.net/
- RPCS3 hardware performance scaling: https://blog.rpcs3.net/2020/08/21/hardware-performance-scaling/
- RPCS3 configurations wiki: https://wiki.rpcs3.net/index.php?title=Help%3AConfigurations
- Android Performance Hint API: https://developer.android.com/ndk/reference/group/a-performance-hint
- Android ADPF Performance Hint overview: https://source.android.com/docs/core/perf/performance-hint-api
- Android Thermal API: https://developer.android.com/games/optimize/adpf/thermal
- Android Vulkan design notes: https://developer.android.com/ndk/guides/graphics/design-notes
- Android GPU Inspector frame profiling: https://developer.android.com/agi/frame-trace/frame-profiler
- Vulkan pipeline cache guide: https://docs.vulkan.org/guide/latest/pipeline_cache.html
- Linux arm64 ELF HWCAP docs: https://www.kernel.org/doc/html/next/arch/arm64/elf_hwcaps.html
- Arm dot-product instruction overview: https://developer.arm.com/community/arm-community-blogs/b/tools-software-ides-blog/posts/exploring-the-arm-dot-product-instructions
- Local upstream checkout inspected: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`
- Local Android fork inspected: `C:\Users\leanerdesigner\Documents\New project 6\rpcsx-ui-android`
