# RPCSX for AYN Thor Experiment

# EXTREMELY UNSTABLE RESEARCH BUILD

## I am testing stuff right now. Do not treat this as a general PS3-on-Android release.

### Upstream ARM64 integration (2026-08-05)

Audited this tree against upstream RPCS3's ARM64 CPU-emulation series, the work
covered in Whatcookie's "PS3 emulation is fast on ARM now".

Result of the audit: this tree was already carrying nearly all of it. SPU
multiplies, the inlined decrementer, `FSM`, the `GB`/`GBH`/`GBB` dot-product
paths, the `FCGT` workaround and the ARM `UABA` checksum path were all present,
several in forms further along than upstream's. This tree also has `smmla` /
`ummla` (i8mm) helpers that upstream does not.

Newly integrated: SPU `SHUFB` and PPU `VPERM` now emit native `TBL2`/`TBX2`
instead of an emulated x86 `PSHUFB` sequence, together with the recoverable-JIT
and register-scavenger retry mechanism that makes those instructions safe to
use. Upstream measures the shuffle change at about +8% on its own hardware.

Deliberately not taken: upstream's `busy_wait` timer scaling. This tree had
already solved the same problem by hand-retuning its spin sites against the real
19.2MHz generic timer, so applying the upstream scale on top divided already
correct values a second time and collapsed Thor to roughly 1 FPS. Reverted. See
`debug-experiments/20260805-arm64-upstream-perf-uplift.md`. The two remaining
unported upstream commits are SVE-only and the Snapdragon 8 Gen 2 exposes no SVE.

Early result: informal testing on Thor of build `49FCB2F5...7FED7` reports many
titles running well. That build carries the `TBL2`/`TBX2` shuffle work and the
retry mechanism, with the `busy_wait` scaling and ISB changes reverted, so it is
a reasonably clean read on the shuffle port.

This is hands-on testing rather than a harness-gated measurement. No FPS figure,
no thermal envelope and no per-title compatibility matrix has been captured yet,
and the automated gated run still thermal-stops during cold PPU/SPU compilation
before the title renders. A separate change bounding the cold-compile memory
budget on Android is committed but is not in the build above and remains
unmeasured. Read the above as promising, not as a benchmark.

<p align="center">
  <img src="docs/images/rpcsx-thor-experiment-banner.png" alt="RPCSX for AYN Thor Experiment">
</p>

<p align="center">
  <a href="https://github.com/noeldvictor/rpcsx-ui-android-thor/fork">
    <img src="docs/images/fork-it-button.png" alt="Fork and build yourself - no APK support queue" width="620">
  </a>
</p>

Personal-use Android fork of RPCSX-UI-Android for **AYN Thor Base, Pro, and Max**. It targets Snapdragon 8 Gen 2 / Adreno 740 Thor hardware and handheld PS3 testing.

No stability guarantee. No support queue. No APK support. Build it yourself and use legally owned dumps with legally obtained firmware.

## Quick Read

- **Target:** AYN Thor Base / Pro / Max. Thor Lite may run it, but is not the PS3 performance target.
- **Purpose:** library setup, Thor controls, cheat lists, cache status, and Thor-specific performance experiments.
- **Current benchmark:** Eternal Sonata `BLUS30161` reaches near-30-FPS first-field and first-battle-prompt performance on Thor Max with the optimized RelWithDebInfo native core. This is not broad compatibility or a finished 30-FPS guarantee.
- **Release style:** source-first. GitHub Actions artifacts may exist, but builds are the expected path.
- **Upstream:** still GPLv2, still based on RPCSX-UI-Android, still dependent on RPCSX core behavior.

## Current Performance Canary

The current focused test game is **Eternal Sonata `BLUS30161`** on an AYN Thor Max, stock Qualcomm Vulkan driver, 720p Rocknix-correct profile, Write Color Buffers on, reduced-loop u4 enabled, and the optimized Android native core.

As of **2026-05-17**, this fork matches the public Rocknix/RPCS3 720p field target for the tested scene. The Android Thor core is no longer stuck at `10-13 FPS` in the first playable field when using the optimized dev-core workflow.

Measured on Thor Max:

| Scene/check | FPS | Status |
| --- | ---: | --- |
| First field route | `29.14 FPS` | Near target |
| Short moving field, open view | `27.35-28.08 FPS` | Near target |
| Short moving field, tree-heavy view | `19.68 FPS` | Still a hotspot |
| First battle tutorial prompt | `30.00 FPS` | Target met |

Important caveats:

- This is a **single-game canary**, not proof that all PS3 games are fast.
- The menu checkpoint still needs a clean correctness pass; one quick menu probe opened the ImGui debug overlay instead of the game menu.
- The worst tree-heavy field camera still dips below the 30-FPS target. Remaining work is RSX/SPU/GPU hot-path tuning.
- Do not compare FPS from `app\.cxx\Debug\...` native cores. FPS runs must use the optimized RelWithDebInfo dev core or a release-equivalent build.

## Thor Variants

Base, Pro, and Max share the same CPU/GPU target. The main difference is cache/storage headroom.

| Variant | CPU/GPU | RAM | Storage | Practical note |
| --- | --- | ---: | ---: | --- |
| Thor Base | Snapdragon 8 Gen 2 / Adreno 740 | 8 GB | 128 GB | Same speed target, tightest cache budget. |
| Thor Pro | Snapdragon 8 Gen 2 / Adreno 740 | 12 GB | 256 GB | Default comfort target. |
| Thor Max | Snapdragon 8 Gen 2 / Adreno 740 | 16 GB | 1 TB | Best cache/library headroom. |

## Screenshots

Captured from the connected AYN Thor test device.

![Thor library](docs/screenshots/rpcsx-thor-library.png)

![Thor menu](docs/screenshots/rpcsx-thor-menu.png)

## User-Facing Differences

Summary: upstream is the general Android app; this fork is the Thor handheld build.

| Area | This fork changes |
| --- | --- |
| Updates | Upstream-style update nags are disabled for this fork. |
| Library setup | External PS3 folders and ISOs can be added with SD-card use in mind. |
| Titles and covers | Reads `PARAM.SFO` and `ICON0.PNG` from PS3 game folders/ISOs where possible. |
| Cheats | Adds cheat badges, per-game cheat lists, bundled cheat database, and toggles. |
| In-game menu | Adds Thor-friendly Cheats, Fast Forward 2x, Show FPS, Save State, and Load State paths. |
| Hotkeys | `Select + R1` fast-forward, `Select + right stick down` save, `Select + right stick up` load. |
| Back button | Android Back opens the in-game menu during gameplay and pauses. |
| Touch overlay | Thor defaults to hidden on-screen controls because it has physical controls. |
| Sixaxis | Thor motion sensors are wired for PS3 motion when the bundled core exposes the bridge. |
| Recommended settings | Per-game settings can be enabled with one switch. |
| Compiled cache | Game detail shows PPU, SPU, and shader cache status instead of hiding it. |
| Cache storage | Internal or app-owned SD-card compiled-cache storage can be selected when Android exposes both. |
| Trim / Optimize | Experimental personal-use trimming tools are available in the app. |
| GPU drivers | Driver UI is Thor-guided with Adreno 740 notes and curated Turnip-style sources. |
| Debugging | Thor log/screenshot capture scripts are included for reproducible play-session debugging. |

## Technical Differences

- RPCSX core source is vendored under `app/src/main/cpp/rpcsx`, so Android UI and Thor core experiments live in one repo.
- The default Gradle APK bundles this fork's source-built RPCSX core unless `-PbuildBundledRpcsxCore=false` is passed.
- Fork update prompts are disabled through `BuildConfig.FORK_BUILD=true`.
- Cheat work includes bundled database assets, Artemis/Aldos conversion experiments, RPCS3 patch imports, and patch-hash learning.
- Recommended settings use a bundled RPCS3 config snapshot plus a writable local cache.
- Per-game compiled-cache status reads `cache/cache/TITLEID` and counts PPU, SPU, and RSX shader cache entries.
- RSX shader cache lives below the PPU cache tree (`.../ppu-*/shaders_cache/`), so selected compiled-cache storage covers CPU and shader cache together.
- Thor defaults cap LLVM compile workers, disable full first-boot PPU precompile, enable SPU and on-disk shader cache, and use a Thor-safe `cortex-a78` LLVM target.
- ARM64 native code uses the Thor-wide ARMv8.2-A baseline for inline LSE atomics and an A715 scheduling model; these tune ahead-of-time host code without changing runtime JIT feature gates.
- The old Android `cortex-a34` startup override is removed because it silently downgrades Thor JIT codegen.
- Fast Forward 2x uses RPCSX/RPCS3 `Clocks scale`, not raw uncapped rendering.
- System Info includes `Thor Feature Doctor` output for LLVM CPU, detected AArch64 cores, and Android feature flags.
- Android-side cleanup reduces main-thread file probing, speeds folder scan queues, improves large-file copy, caches patch status reads, and debounces library saves.

## Cheats Setup

The APK bundles `app/src/main/assets/cheats/cheats.db`. It currently contains `2501` Aldos/Artemis entries and `28` RPCS3-ready patch entries, so the app can show matching cheats on a game detail page without a network fetch.

Install flow:

1. Add a game so the app can read its title ID from `PARAM.SFO` or the ISO.
2. Open the game detail page, then open `Cheats`.
3. For Aldos/Artemis cheats, start the game once, close it, then return to `Cheats`. RPCSX needs the PPU patch hash before it can write RPCS3 patch files.
4. Turn on the cheats you want. The app writes generated patches to `config/patches/TITLEID_patch.yml` and enables them in `config/patch_config.yml`.
5. Restart the game. Cheat changes apply on the next game start.

RPCS3-ready patch entries already include PPU hashes and can be toggled without the Aldos/Artemis conversion step. Risky AoB, runtime, or unsupported Artemis codes stay visible as unavailable until native validation exists.

Developer refresh:

```powershell
.\tools\update_aldos_cheats.ps1
python .\tools\build_cheat_db.py
```

<details>
<summary>AYN Thor hardware notes</summary>

The connected Thor reports `kalama` hardware and this CPU layout from `/proc/cpuinfo`:

| CPU | Part | Interpreted core |
| ---: | --- | --- |
| 0 | `0xd46` | Cortex-A510 |
| 1 | `0xd46` | Cortex-A510 |
| 2 | `0xd46` | Cortex-A510 |
| 3 | `0xd4d` | Cortex-A715 |
| 4 | `0xd4d` | Cortex-A715 |
| 5 | `0xd47` | Cortex-A710 |
| 6 | `0xd47` | Cortex-A710 |
| 7 | `0xd4e` | Cortex-X3 |

Useful masks for native/core experiments:

| Group | CPUs | Mask |
| --- | --- | --- |
| Efficiency only | `0-2` | `0x07` |
| A715 only | `3-4` | `0x18` |
| A710 only | `5-6` | `0x60` |
| Prime X3 only | `7` | `0x80` |
| Performance plus prime | `3-7` | `0xF8` |
| A715 plus prime | `3-4,7` | `0x98` |

Practical direction: keep PPU/SPU/shader caches on internal storage when possible, cap LLVM compile workers before heat and memory pressure snowball, and expose obvious Thor controls instead of making users dig through advanced settings.

</details>

## Reports

- [APS3E, RPCSX, and Thor PPU compile notes](report/2026-05-10-aps3e-rpcsx-thor-ppu-compile.md)
- [RPCS3 automatic game settings notes](report/2026-05-10-rpcs3-auto-game-settings.md)
- [AYN Thor Base/Pro/Max Snapdragon 8 Gen 2 target notes](report/2026-05-10-snapdragon-8-gen-2-thor-target.md)
- [Markdown and Thor variant audit](report/2026-05-10-markdown-and-thor-variant-audit.md)
- [Thor black screen debug pipeline](report/2026-05-11-thor-black-screen-debug-pipeline.md)

## Building

Requirements: Android SDK, JDK 17, Android 10+ target device.

```powershell
.\gradlew.bat :app:assembleDebug
```

Debug APK:

```text
app\build\outputs\apk\debug\rpcsx-thor-experiment-debug.apk
```

The default build compiles the Android JNI wrapper and bundles this fork's source-built RPCSX core. Hydrate pinned RPCSX third-party submodules once before the first full source-core build:

```powershell
.\tools\hydrate_rpcsx_core_deps.ps1
```

For faster UI-only iteration:

```powershell
.\gradlew.bat :app:assembleDebug -PbuildBundledRpcsxCore=false
```

For native/core speed iteration on Thor, use the optimized dev-core hot-swap path:

```powershell
.\tools\build_push_thor_core.ps1 -Label eternal-sonata-speed
```

That script defaults to `:app:buildCMakeRelWithDebInfo[arm64-v8a]` so FPS tests use `-O2 -DNDEBUG -flto=thin`. Debug native fallback is intentionally opt-in with `-AllowDebugFallback`; Debug native cores are useful for diagnosis, not FPS claims.

ARM64 builds also default to `-march=armv8.2-a -mtune=cortex-a715`. Override either setting for a diagnostic build with `-PrpcsxAndroidArmArch=...` or `-PrpcsxAndroidArmTune=...`; pass an empty value to disable that flag. The architecture baseline is valid across Thor's Snapdragon 865 and Snapdragon 8 Gen 2 variants, while `-mtune` changes scheduling decisions only.

## Thor Debug Capture

Live stream while playing:

```powershell
.\tools\start_thor_debug_stream.ps1 -ClearLogcat -Launch -Label game-name
.\tools\summarize_thor_debug_stream.ps1 -Latest
.\tools\stop_thor_debug_stream.ps1 -Latest
```

One-shot capture:

```powershell
.\tools\collect_thor_debug.ps1 -Label game-name
```

Debug streams and captures are written to ignored `debug-captures/` folders.

## License

This fork keeps the upstream GPLv2 license unless a directory or file contains its own license.
