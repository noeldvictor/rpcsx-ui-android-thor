# 2026-05-10 AYN Thor Base/Pro/Max Snapdragon 8 Gen 2 Target Notes

## Scope

Target device family: AYN Thor Base, Pro, and Max. These are the Snapdragon 8 Gen 2 / Adreno 740 variants and are the PS3 performance target for this fork.

Thor Lite is a Snapdragon 865 / Adreno 650 device. It may remain compatible, but it should not inherit the Base/Pro/Max CPU masks or performance assumptions.

Goal: make RPCSX for AYN Thor Experiment feel less like a generic Android port and more like a handheld-first PS3 app with clear cache/precompile flow, sane defaults, and no mystery knobs.

Current implementation checkpoint: the app now applies a first-pass Thor compile-relief preset, pins current app/native threads to CPUs `3-7` where Android permits it, and shows per-game cache status on game detail. A real background PPU prepare action is wired only as an optional native hook because the currently installed RPCSX core does not expose `_rpcsx_preparePpuCache`.

## Public Research

- Qualcomm lists Snapdragon 8 Gen 2 as an active premium-tier 4 nm platform with CPU speed up to 3.36 GHz depending on platform version, Qualcomm Adreno graphics, Quick Charge 5 support, and the Snapdragon X70 modem family: <https://www.qualcomm.com/smartphones/products/8-series/snapdragon-8-gen-2-mobile-platform>
- Qualcomm's launch note frames the platform around system-wide AI, Adreno gaming improvements, and broader connected-device use beyond phones: <https://www.qualcomm.com/news/onq/2022/11/new-snapdragon-8-gen-2-8-extraordinary-mobile-experiences-unveiled>
- AYN's own site lists Thor as `Qualcomm 8Gen2 CPU`, customized 6 inch FHD AMOLED touch screen, Android 13, and a 6000 mAh battery: <https://www.ayntec.com/>
- AYN's one-page Thor system-parameters sheet lists Base/Pro/Max as 8 Gen 2, 4 nm, `1 GoldPlus@3.2GHz`, `4 Gold@2.8GHz`, `3 Silver@2.0GHz`, Adreno 740 at 680 MHz, LPDDR5X at 4200 MHz in 8/12/16 GB capacities, and UFS 4.0 in 128 GB/256 GB/1 TB capacities: <https://manuals.plus/m/7e96f29e93e4e571eb4e2ee5f2220a98db9ab0a295678d69157e99ddfc948028.pdf>
- Time Extension reports the public SKU mapping as Base 8 GB + 128 GB, Pro 12 GB + 256 GB, and Max 16 GB + 1 TB, all with Snapdragon 8 Gen 2 and Adreno 740: <https://www.timeextension.com/news/2025/08/ayn-reveals-release-date-colours-and-specs-for-its-pocket-ds-rival>
- Notebookcheck's shipping recap repeats that Base/Pro/Max share Snapdragon 8 Gen 2 and differ by RAM/storage, while Lite uses Snapdragon 865 and Adreno 650: <https://www.notebookcheck.net/AYN-Thor-dual-screen-handheld-begins-shipping-but-only-the-Snapdragon-8-Gen-2-version.1138344.0.html>
- Android's NDK Performance Hint API can report actual work duration, notify CPU/GPU workload changes, and let the system adjust scheduling/performance for a thread group when supported: <https://developer.android.com/ndk/reference/group/a-performance-hint>
- Android Game Mode interventions can change frame pacing, backbuffer scaling, and FPS behavior on Android 12/13+ devices, so the app should eventually be explicit about whether it opts in, opts out, or manages game-mode behavior itself: <https://developer.android.com/games/optimize/adpf/gamemode/gamemode-interventions>

## Variant Matrix

| Variant | CPU/GPU | RAM | Internal storage | Optimization meaning |
| --- | --- | ---: | ---: | --- |
| Thor Base | Snapdragon 8 Gen 2 / Adreno 740 | 8 GB LPDDR5X | 128 GB UFS 4.0 | Same CPU/GPU speed target as Pro/Max, but tighter cache and memory budget. |
| Thor Pro | Snapdragon 8 Gen 2 / Adreno 740 | 12 GB LPDDR5X | 256 GB UFS 4.0 | Default comfort target for testing. |
| Thor Max | Snapdragon 8 Gen 2 / Adreno 740 | 16 GB LPDDR5X | 1 TB UFS 4.0 | Best local cache/library headroom, not a faster PPU compiler by itself. |
| Thor Lite | Snapdragon 865 / Adreno 650 | 8 GB LPDDR4X | 128 GB UFS 3.1 | Compatibility target only; do not use Base/Pro/Max CPU masks. |

The Base/Pro/Max CPU and GPU presets should be the same. The SKU differences matter for storage policy, cache retention, memory pressure, and how aggressive we can be with background indexing.

## Measured Thor CPU Topology

Measured over ADB on the connected user device:

```text
ro.product.model: AYN Thor
ro.board.platform: kalama

processor 0 CPU part 0xd46
processor 1 CPU part 0xd46
processor 2 CPU part 0xd46
processor 3 CPU part 0xd4d
processor 4 CPU part 0xd4d
processor 5 CPU part 0xd47
processor 6 CPU part 0xd47
processor 7 CPU part 0xd4e
```

Interpreted mapping:

| CPU | Core | Mask bit |
| ---: | --- | ---: |
| 0 | Cortex-A510 | `0x01` |
| 1 | Cortex-A510 | `0x02` |
| 2 | Cortex-A510 | `0x04` |
| 3 | Cortex-A715 | `0x08` |
| 4 | Cortex-A715 | `0x10` |
| 5 | Cortex-A710 | `0x20` |
| 6 | Cortex-A710 | `0x40` |
| 7 | Cortex-X3 | `0x80` |

Important groups:

| Group | CPUs | Mask | Use |
| --- | --- | --- | --- |
| Little cores | `0-2` | `0x07` | Background UI/light services only. Avoid LLVM compile bursts here. |
| A715 pair | `3-4` | `0x18` | Good sustained high-performance CPU work. |
| A710 pair | `5-6` | `0x60` | Good compatibility/performance CPU work. |
| X3 prime | `7` | `0x80` | Latency-critical work, but easy to heat. |
| Performance plus prime | `3-7` | `0xF8` | First safe mask for PPU/SPU/RSX heavy work. |
| A715 plus prime | `3-4,7` | `0x98` | Candidate for PPU foreground/compile work. |

Do not hardcode these masks for every Snapdragon 8 Gen 2 device. They are measured for this AYN Thor and should become the fallback only after runtime topology detection fails.

## Android-Side Optimizations Already Applied

- Folder scans now use queue-friendly `ArrayDeque` behavior instead of `removeAt(0)` on growing lists.
- URI copy now uses a stream copy with a larger buffer instead of fixed 1 KB writes.
- ISO metadata reads reuse one parsed ISO directory cache for `PARAM.SFO` and `ICON0.PNG`.
- Game-card icon file existence checks moved off the composition path.
- Patch status checks cache generated patch-section file reads.
- `games.json` saves are debounced during library changes.
- Game detail now scans `cache/cache/TITLEID`, shows PPU cache size/entry counts, and clears cache by title ID.

These do not make LLVM itself faster, but they reduce UI/library jank and wasted SD/internal-storage work around the emulator.

## Why PPU Compiles Hurt

PPU LLVM compile is CPU-heavy, bursty, and cache-sensitive. On a handheld SoC, throwing more threads at it can be slower after heat and scheduler contention kick in. The practical danger zones:

- Compile workers land on A510 efficiency cores and crawl.
- Too many compile workers keep X3/A715/A710 hot until sustained clocks drop.
- Game files are on SD and cache writes/reads fight slower storage.
- The app hides whether a game is cold-cache, warm-cache, or stale-cache.
- `Use LLVM CPU` gets changed without explaining that cache reuse and portability may change.

Base/Pro/Max note: the Max model's extra RAM and 1 TB internal storage can make cache-heavy workflows more comfortable, but it should not be treated as a different CPU/GPU class. A slow PPU compile on Base will usually still be a slow PPU compile on Max unless the bottleneck is storage pressure, RAM pressure, or thermal policy.

## Preset Experiments To Build

These are experiment names, not promises:

| Preset | Max LLVM compile threads | PPU mask | SPU mask | RSX mask | Intent |
| --- | ---: | --- | --- | --- | --- |
| Thor Safe | 4 | `0xF8` | `0xF8` | `0xF8` | Keep heavy work off A510 and avoid extreme oversubscription. |
| Thor Compile Burst | 5 | `0xF8` | `0xF8` | `0x80` | Test whether one more worker helps first-boot compile before heat wins. |
| Thor Cool | 3 | `0x18` | `0x60` | `0x80` | Lower thermal load for longer sessions. |
| Thor PPU Focus | 4 | `0x98` | `0x60` | `0x80` | Let PPU use A715+X3 while SPU gets A710. Risky until profiled. |

First benchmark should compare wall-clock PPU compile time, first playable frame time, second boot time, FPS after warm cache, battery state, and any thermal throttling signal available from Android.

## Variant-Specific Defaults

| Area | Base | Pro | Max |
| --- | --- | --- | --- |
| LLVM compile threads | Start at `4`; benchmark down to `3` if thermals/storage pressure show up. | Start at `4`; benchmark `5`. | Start at `4`; benchmark `5` and `6`, but treat heat as the deciding factor. |
| Cache retention | Smaller per-game cache budget; clear stale caches loudly. | Balanced cache budget. | Larger cache budget and easiest import/export story. |
| Cheat browser | Avoid expensive global expansion until the user searches or opens a game. | Normal lazy expansion. | Normal lazy expansion; still avoid wasteful startup parsing. |
| Covers/metadata | Lazy and cached; never block library scroll. | Same. | Same. |
| SD-card libraries | Warn when cache or metadata work is repeatedly touching slow removable storage. | Same. | Same, but internal storage can absorb more cache. |

## Android Work To Add

1. Runtime CPU topology reader in Kotlin/JNI:
   - Read `/proc/cpuinfo` part IDs.
   - Read `/sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq` when exposed.
   - Build masks by detected core family.
   - Show the detected layout in Device Info.

2. Thor preset UI:
   - One obvious `AYN Thor Base/Pro/Max / Snapdragon 8 Gen 2` preset.
   - Hide scary mask names behind "Safe", "Compile Burst", and "Cool".
   - Keep an advanced readout for people who actually want masks.
   - Treat Lite as a separate compatibility preset if it is detected.

3. Cache workflow:
   - Per-game cache badge: cold, building, ready, stale.
   - `Prepare cache` action from the game detail page when `_rpcsx_preparePpuCache` exists.
   - Store caches on internal app storage by default.
   - Warn if games are external/SD but cache storage is slow or missing.

4. Native/core asks:
   - Expose direct PPU cache precompile if RPCSX core supports it internally.
   - Expose affinity controls for PPU/SPU/RSX classes instead of pretending UI-only settings can pin threads.
   - Expose cache status by title ID/path/hash.
   - Emit PPU/SPU hash events so cheat and cache UI can stop guessing.

5. Android performance hooks:
   - Use a foreground service for long compile/cache builds.
   - Try NDK `APerformanceHint` around compile and frame workloads where supported.
   - Evaluate Android Game Mode behavior explicitly on Thor. If it downscales or throttles in ways that hurt emulator UI, opt out; if it helps frame pacing, document the mode.

## GPU/Display Notes

Base/Pro/Max share Adreno 740 at the target level. The Android repo can help by keeping custom-driver selection obvious, preserving Vulkan/shader cache data, and avoiding unnecessary redraw/update churn on the second screen and overlay. PPU compile is CPU-bound, but bad UI polling, shader-cache churn, or aggressive overlay updates can still make the whole handheld feel worse.

## Immediate Product Direction

For users, the cheats/trim/performance UI should not feel like three separate developer experiments. The game detail screen should become the home base:

- Cover/title/status at top.
- `Play`, `Prepare cache`, and `Manage cheats` as primary actions.
- Badges for cheats available, cache ready/stale, firmware/key problems, and trim candidates.
- Advanced settings remain available but do not gate the simple path.

This is also where the fork needs to be honest: some features are experimental, some are risky, and some need native RPCSX core changes before they can be real. The docs should keep saying Base/Pro/Max share the same CPU/GPU target so users do not expect Max to magically fix PPU compile time.
