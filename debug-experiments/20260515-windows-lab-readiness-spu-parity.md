# 20260515-windows-lab-readiness-spu-parity

- Status: `runtime-smoke-ready`
- Title ID: `BLUS30161` context, but no game-specific Windows run yet
- Game: Eternal Sonata context
- Platform scope: `windows-lab`, `shared-core`
- Owner: Codex + user
- Created: 2026-05-15
- Last updated: 2026-05-15

## Hypothesis

Before we can run Windows gameplay tests, the Windows lab must be able to build or at least analyze the upstream/shared core. Even without the game dump on Windows, static comparison can identify which upstream SPU hot-path machinery is missing or incomplete in the Android vendored core.

## Windows Lab Readiness

Commands were run on Windows only. Thor was not launched or used for Android testing.

Observed:

- Visual Studio Build Tools exists at `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`.
- `cl.exe` is available after `VsDevCmd.bat`; detected compiler: MSVC `19.44.35226` x64.
- `cmake` is on PATH but is `3.26.3`; upstream `BUILDING.md` asks for `3.28.0+`.
- Visual Studio's bundled CMake is available at `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`; detected version: `3.31.6-msvc6`.
- `ninja` is on PATH: `1.13.2`.
- `python` is on PATH: `3.10.11`.
- `Qt6_ROOT`, `QTDIR`, and `VULKAN_SDK` are not set in the current shell.
- Ghidra headless exists and prints usage from `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat`.
- `rpcs3-upstream` started as a sparse checkout containing `rpcs3`, `Utilities`, `bin`, `.ci`, `.github`, and `buildfiles`; sparse checkout has now been disabled so root build files and `3rdparty` are present.
- `rpcs3-upstream` submodules have been hydrated with `git submodule update --init --recursive --jobs 8`.
- First configure attempt with `cmake --preset msvc` failed because `USE_SYSTEM_SDL=ON` expected a system SDL3 package.
- Second configure attempt with `cmake --preset msvc -DUSE_SYSTEM_SDL=OFF -DUSE_VULKAN=OFF` used builtin SDL3, downloaded the RPCS3 ffmpeg Windows x64 prebuilt, and reached the Qt6 dependency gate.
- Installed `aqtinstall` with Python and installed Qt `6.10.3` MSVC 2022 x64 under `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\qt\6.10.3\msvc2022_64`.
- The Qt install requested `qtmultimedia`; `qtsvg` was pulled as part of the resolved payload and `Qt6Svg`/`Qt6SvgWidgets` were available to CMake.
- `winget` found Vulkan SDK `1.4.350.0` and verified the installer download, but the installer requested administrator elevation and was cancelled.
- Installed local Vulkan build inputs through vcpkg instead: `vulkan-headers:x64-windows` and `vulkan-loader:x64-windows`, version `1.4.341.0`.
- Vulkan-enabled configure succeeded by setting `Qt6_ROOT`, `QTDIR`, `VULKAN_SDK` to the vcpkg install root and passing explicit `Vulkan_INCLUDE_DIR`/`Vulkan_LIBRARY`.
- Release build succeeded with `cmake --build --preset msvc-release --target rpcs3 --parallel 8`.
- Build artifact: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\build-msvc\bin\rpcs3.exe` (`64,597,504` bytes).
- Smoke command `rpcs3.exe --version` exited `0` with Qt/Vulkan DLL paths on `PATH`, but printed no version text.
- Added `tools/windows_rpcs3_lab.ps1` in the Android repo as the Windows-side launcher/recorder. It sets Qt/Vulkan paths, creates `build-msvc\bin\log`, supports `Smoke`, `LocateGame`, and `Run`, and stores output under `debug-captures\windows-lab`.
- A GUI popup occurred when probing RPCS3 without explicit headless/no-gui flags. The process was stopped, and follow-up smoke runs now use explicit `--headless --no-gui`.
- Headless no-target smoke succeeded as an expected negative test: RPCS3 initialized, logged version `0.0.40-501-cd7cb1cc`, then reported `Cannot run headless mode without boot target. Terminating...`.
- Tight game locator scans over `Documents`, `Downloads`, `Desktop`, and `E:\` found no real Windows-side Eternal Sonata boot target; they ignored debug captures/build outputs and looked for `PS3_GAME`, `PARAM.SFO`, or `BLUS30161` candidates.

Build readiness decision:

- Windows upstream lab can now configure and build a Vulkan-enabled Release executable.
- Windows launcher smoke is ready and avoids GUI popups by default.
- Do not attempt gameplay tests until Eternal Sonata or a legally available Windows-side test title/module is staged.
- The system-wide Vulkan SDK is not required for compile anymore; vcpkg provides enough headers/import lib for this lab build.

Local Windows-lab build shims:

- `buildfiles/cmake/FindZLIB.cmake`: map builtin zlib to MSVC-produced `Debug/zsd.lib` and `Release/zs.lib` instead of the Unix-style `libzlibstatic.a`; also guard duplicate `ZLIB::ZLIB` target creation.
- `3rdparty/wolfssl/wolfssl/wolfssl/wolfcrypt/settings.h`: convert wolfSSL's `#warning` to `#pragma message` under MSVC while preserving `#warning` elsewhere.

## Static SPU Reduced-Loop Parity Scan

Compared upstream RPCS3 files against the Android vendored core:

- `SPUCommonRecompiler.cpp`
- `SPULLVMRecompiler.cpp`
- `SPURecompiler.h`

Diff size:

- `SPUCommonRecompiler.cpp`: `1471 insertions`, `2277 deletions`
- `SPULLVMRecompiler.cpp`: `1162 insertions`, `1595 deletions`
- `SPURecompiler.h`: `17 insertions`, `385 deletions`

Pattern counts:

| File area | Upstream | Android vendored | Read |
| --- | ---: | ---: | --- |
| `SPUCommonRecompiler.cpp` reduced-loop refs | 139 | 39 | Android has a much smaller/gated reduced-loop slice. |
| `SPUCommonRecompiler.cpp` `is_no_return` refs | 13 | 0 | Android lacks upstream no-return-aware analysis in this area. |
| `SPUCommonRecompiler.cpp` supplemental-condition refs | 7 | 9 | Android has a custom/gated candidate path, not direct parity. |
| `SPULLVMRecompiler.cpp` reduced-loop emit refs | 61 | 48 | Android has partial reduced-loop emission. |
| `SPULLVMRecompiler.cpp` not-NaN hint refs | 22 | 0 | Android lacks upstream reduced-loop not-NaN hint use in LLVM emission. |

Important code observations:

- Android vendored core has Android-gated reduced-loop detection/emission props: `debug.rpcsx.thor.spu_reduced_loop_detect` and `debug.rpcsx.thor.spu_reduced_loop_emit`.
- Android's reduced-loop implementation is deliberately narrower and feature-gated, which is good for safety but means Windows/shared-core parity is not complete.
- Upstream `SPURecompiler.h` has a much richer `reduced_loop_t::origin_t` tracker with loop-dictator/predictability helpers. Android's `reduced_loop_t` is simpler and lacks that origin-tracking body.
- Upstream `SPUCommonRecompiler.cpp` has no-return-aware block analysis that Android currently lacks in the searched reduced-loop area.
- Upstream LLVM emission uses reduced-loop not-NaN hints in multiple FP paths; Android currently has no matching references.

## Interpretation

The first Windows/shared-core test does not point to Ghidra yet. It points to SPU reduced-loop parity as a likely high-impact workstream:

1. Make the Windows upstream tree buildable.
2. Preserve Android's gated behavior.
3. Port/analyze upstream reduced-loop support in smaller units: no-return analysis, origin tracking, not-NaN hints, then emission behavior.
4. Keep Eternal Sonata as the Android proof target once a gated patch survives build/correctness checks.

## Current Blockers

- Eternal Sonata is not available in the Windows setup, so no Windows gameplay scene can run yet.
- The Windows locator found no `PS3_GAME`/`PARAM.SFO`/`BLUS30161` boot target in `Documents`, `Downloads`, `Desktop`, or `E:\`.
- System SDL3 is not installed; use `-DUSE_SYSTEM_SDL=OFF` unless we deliberately add a system package later.
- PATH CMake is below upstream's documented minimum, but Visual Studio's bundled CMake is new enough.
- System-wide Vulkan SDK installation was blocked by UAC/admin; keep using explicit vcpkg Vulkan paths for now.
- The Release build logs a nonfatal `LNK4098` default CRT conflict warning. Track it, but it did not block `rpcs3.exe`.

## Next Windows-Only Test Candidates

1. Windows lab setup test: expand sparse checkout, hydrate submodules, configure CMake/Visual Studio environment, and stop at configure/build readiness.
2. Static reduced-loop parity report: produce a focused checklist of upstream reduced-loop pieces missing from Android vendored core.
3. Build-only shared-core smoke test: once dependencies are hydrated, compile the upstream Windows core/app without any game run.
4. Ghidra readiness test: run headless import/decompile only against a legally available module or a previously dumped local analysis artifact, not by pulling game content from Thor.
5. Runtime smoke test: launch the Windows build to an empty GUI/profile state with Qt and vcpkg DLL paths set, then close it without installing or launching a game.
6. Deterministic scene test: once the Windows-side game dump or a safe test module exists, record boot-to-first-playable timings, SPU LLVM compile count/timing, RSX frame timing, and shader compile spikes.

## Decision

`runtime-smoke-ready`

## Notes

The user asked to start only Windows tests. No Android repro, no Thor launch, and no game-content pull was performed in this pass.
