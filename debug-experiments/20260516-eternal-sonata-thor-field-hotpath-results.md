# Eternal Sonata Thor Field Hot-Path Results - 2026-05-16

## Scope

- Game: Eternal Sonata `BLUS30161`
- Device: AYN Thor Max
- Scene: first playable field
- Driver: stock Qualcomm
- Cache state: warm SPU/PPU/shader caches
- Core label: `es-fast-busy-wait` dev core
- Active core SHA256: `53D8E9964A3E2E2045A50FC60AEDB08A545B4F2E4630AA6BD4994FDFF8BF36B1`
- Correctness gate: screenshot visual check for field, no obvious black spots, missing textures, or menu overlays in tested field captures

SPU/PPU caches were not cleared for these speed sweeps. Rebuild the Android native
core for C++ changes, but clear SPU/PPU caches only when changing recompiler
behavior, cache keys, timing semantics that are baked into generated code, or
when running a deliberately labeled cold-cache baseline.

## Native Build-Type Correction

Status: `major-win`.

The Android dev-core hot-swap path was pushing `CMAKE_BUILD_TYPE=Debug` native
cores for FPS tests. That invalidated the Rocknix comparison: representative
SPU/RSX compile commands had `-g`, `_DEBUG`, and `-fno-limit-debug-info`, but no
`-O2`/`-DNDEBUG`.

Optimized RelWithDebInfo dev-core:

- Build command:
  `.\tools\build_push_thor_core.ps1 -Label relwithdebinfo-speed-core -GradleTask ':app:buildCMakeRelWithDebInfo[arm64-v8a]' -NoFallbackBuild -NoStream`
- SHA256:
  `BFC15D139DFA798D8FA7C4331DF1A32A14BFE3F863D3F177BCA240E3E3E40AC7`
- Compile flags verified:
  `-O2 -g -DNDEBUG -flto=thin`
- Workflow fix:
  `tools/build_push_thor_core.ps1` now defaults to RelWithDebInfo and requires
  `-AllowDebugFallback` before any Debug fallback is used.

Measured same-profile result, 720p Rocknix-correct, WCB on, reduced-loop u4,
stock Qualcomm, AllThreadsFF runtime affinity:

| Build | Capture | FPS overlay | Visual result |
| --- | --- | ---: | --- |
| Debug native | `debug-captures/android-speed-sprint/20260517-131902-thor-input-custom/01-moving-left-mid.png` | `13.55` | correct field, tree-heavy moving camera |
| Debug native | `debug-captures/android-speed-sprint/20260517-131902-thor-input-custom/02-moving-left-end.png` | `13.67` | correct field |
| Debug native | `debug-captures/android-speed-sprint/20260517-131902-es-u4-720correct-moving-baseline-live-scene/scene.png` | `13.27` | correct field |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-thor-input-custom/01-moving-left-3s.png` | `19.68` | correct field, worst short moving/tree sample |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-thor-input-custom/02-field-after-short-move.png` | `28.08` | correct field |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-140441-es-rel-u4-720correct-moving-short-live-scene/scene.png` | `27.35` | correct field |
| RelWithDebInfo native | `debug-captures/android-speed-sprint/20260517-135651-thor-input-custom/02-moving-left-end.png` | `30.00` | first battle tutorial prompt |

The optimized core drops `rsx::thread` from near one full core in some static
samples to about 21% in the battle prompt and moves the field from fake
debug-bound `13 FPS` toward Rocknix-class `27-28 FPS`. The remaining field dip
is now a real scene hot path, not a build mistake.

Menu note: a quick direct `start` macro after the RelWithDebInfo field test
opened the Dear ImGui demo/debug overlay instead of a valid Eternal Sonata menu
checkpoint (`debug-captures/android-speed-sprint/20260517-142325-thor-input-custom/01-rel-pause-menu.png`).
Do not count that as menu correctness. Re-run the dedicated menu route or fix
the menu/input path before promoting the optimized core as field+battle+menu
complete.

## RSX Depth Texture Barrier Skip

Hypothesis: Eternal Sonata field was breaking the render pass once per frame for
a depth-only texture barrier; title-gated skipping might avoid GMEM/system-memory
traffic on Adreno.

Changed files/settings:

- `VKRenderTargets.cpp` gated `render_target::texture_barrier` skip for
  `BLUS30161`.
- `thor_rsx_auditor.h` classified color versus depth texture barriers.
- `tools/set_thor_logging.ps1` added texture-barrier skip modes.
- Rollback switch: `debug.rpcsx.thor.rsx_texture_barrier=off`.

Thor result:

- Classify/off capture:
  `debug-captures/android-speed-sprint/20260516-124222-eternal-sonata-field-stock-qualcomm-scene`
- Forced depth-skip capture:
  `debug-captures/android-speed-sprint/20260516-124727-eternal-sonata-field-stock-qualcomm-scene`
- Off auditor sample: about `18.93 FPS`, `rp_break=60`,
  `tex_depth=60`.
- Depth-skip sample: about `19.49 FPS`, `rp_break=0`,
  `tex_skip=60`, `forced_skip=60`.

Status: `parked`. This is a real mechanical reduction and field visuals survived,
but the win is only about 3 percent and does not meet the first 20 percent target.
Do not expand it until battle and menu prove correctness.

## Semaphore Fast Path

Hypothesis: the previous semaphore path might reduce field wait overhead.

Thor result:

- Valid capture:
  `debug-captures/android-speed-sprint/20260516-130400-eternal-sonata-field-stock-qualcomm-scene`
- Result: about `19.28 FPS`, field visually correct.

Status: `parked`. Neutral in the field scene; not the dramatic speed path.

## Global ARM64 Busy-Wait Batching

Hypothesis: simpleperf showed `rx::get_tsc()` and `rx::busy_wait()` as huge CPU
costs, so polling `cntvct_el0` less often inside Android/ARM64 busy waits might
free CPU.

Changed files/settings:

- `rx/include/rx/asm.hpp` added opt-in Android/ARM64 modes behind
  `debug.rpcsx.thor.fast_busy_wait`.
- `tools/set_thor_logging.ps1` added `FastBusyWaitLight`, `FastBusyWait`, and
  `FastBusyWaitAggressive`.
- Rollback switch: `debug.rpcsx.thor.fast_busy_wait=off`.

Thor A/B result:

| Mode | Capture | FPS overlay | Visual result |
| --- | --- | ---: | --- |
| off | `debug-captures/android-speed-sprint/20260516-132621-eternal-sonata-field-stock-qualcomm-scene` | `19.35` | correct field |
| fast | `debug-captures/android-speed-sprint/20260516-133117-eternal-sonata-field-stock-qualcomm-scene` | `18.15` | correct field |
| light | `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene` | `17.72` | correct field |

Light-mode simpleperf:

- Report:
  `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene/simpleperf-report-app.txt`
- Raw data:
  `debug-captures/android-speed-sprint/20260516-133619-eternal-sonata-field-stock-qualcomm-scene/es_field_fast_busy_wait_light.data`
- Still hot: `spu_thread::process_mfc_cmd()` about `28.77%`,
  `spu_llvm_recompiler::exec_mfc_cmd<false>()` about `28.14%`,
  `rsx::thread::run_FIFO()` about `24.46%`, `rx::get_tsc()` about `19.48%`,
  `rx::busy_wait()` about `18.08%`.

Status: `failed`. Global busy-wait batching preserved field visuals but reduced
FPS. The likely failure mode is added synchronization latency in tight SPU/RSX
wait loops. Keep the code gated/off only if useful for future profiling; do not
promote it as a speed path.

## Next Action

The real target is still timing/synchronization, but it needs callsite surgery:

1. Add low-overhead per-callsite counters/timing for `rx::busy_wait()` callers,
   especially SPU MFC/PUTLLC, RSX FIFO, mutex/sema, and VM reservation waits.
2. Attack the biggest stable caller, not global `busy_wait()`.
3. Inspect the unknown JIT block that stays near 15-17 percent self time and
   map it back to SPU/PPU generated code.
4. Keep RSX work focused on `load_texture_env`, `load_program`,
   `upload_vertex_data`, and texture upload churn; the depth barrier alone is
   not enough.
5. Re-test field, first battle, and menu before counting any speed win.

## Wait-Profiler Follow-Up

The first callsite profiler pass found a concrete static-analysis target:

- Capture:
  `debug-captures/android-speed-sprint/20260516-140131-eternal-sonata-field-stock-qualcomm-scene`
- Total profiled waits: `11,250,000`.
- SPU reservation waits dominated: `spu_getllar_retry=8,442,390` calls and
  `spu_getllar=1,556,660` calls.
- Secondary core wait: `vm_passive=1,197,687` calls.
- RSX FIFO and generic semaphore waits were not the dominant wait sites in this
  field sample.

Next slice: add a gated `GETLLAR` retry probe that records top SPU image hash,
PC, block hash, reservation address, and thread/group name, then feed the top
hot SPU local-store window into the Ghidra/static-analysis lane documented in
`debug-experiments/20260516-ghidra-ps3-tooling.md`.

## GETLLAR Clean-Mode A/B

Hypothesis: the dominant `spu_getllar_retry` wait site might be reduced by
shortening the retry spin limit or by skipping the RSX reservation lock for the
exact Eternal Sonata SPURS GETLLAR signatures found by the probe.

Changed files/settings:

- `app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp` added Android-direct
  GETLLAR probe logging, split `profile` mode from speed modes so FPS sweeps do
  not pay profiler atomics/logging, and added a `norsx` gate for exact
  `BLUS30161` / image `0x958dfe208b686622` / PC/address/LSA keys.
- `tools/set_thor_logging.ps1` added `GetllarNoRsxLock`.
- Rollback switch: `debug.rpcsx.thor.es_getllar=off`.

Thor clean field result with dev core `es-getllar-cleanmodes`, SHA256
`6E5311A8F0366EFC8BB7846F1B663B2924F8C9342AA8B138B28E0ED08EC7B4ED`:

| Mode | Capture | Matched field FPS | Later scene FPS | Visual result |
| --- | --- | ---: | ---: | --- |
| quiet, reduced-loop off | `debug-captures/android-speed-sprint/20260516-153950-thor-input-eternal-sonata-field-route/01-field.png` | `16.30` | `15.73` | correct field |
| reduced-loop emit, GETLLAR off | `debug-captures/android-speed-sprint/20260516-154532-thor-input-eternal-sonata-field-route/01-field.png` | `19.60` | `18.40` | correct field |
| reduced-loop emit, `yield8` | `debug-captures/android-speed-sprint/20260516-155117-thor-input-eternal-sonata-field-route/01-field.png` | `18.45` | `18.08` | correct field |
| reduced-loop emit, `norsx` | `debug-captures/android-speed-sprint/20260516-155730-thor-input-eternal-sonata-field-route/01-field.png` | `18.84` | `17.60` | correct field |

Status: `failed` as a speed path. The GETLLAR profile was real and correctly
identified the SPURS kernel hot loop, but these wait/RSX-lock tweaks did not
beat the reduced-loop baseline once profiler overhead was removed. Keep the
probe code useful for future static analysis, but do not promote `yield8` or
`norsx` for Eternal Sonata field FPS.

Next action: continue SPU reduced-loop/codegen coverage and use Ghidra/disasm
around image `0x958dfe208b686622` hot PCs `0x25cc`, `0x451c`, and GETLLAR PC
`0x0a70` to find a real loop/body optimization rather than another wait knob.

## GhidraSPU Hot-Window Lane

Status: installed and smoke-tested on the Eternal Sonata hot SPU image.

- Source: `https://github.com/aerosoul94/GhidraSPU`, local checkout
  `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\GhidraSPU`
  at commit `b85076d`.
- Install: compiled `spu.slaspec` with Ghidra 12.0.4 `support\sleigh.bat` and
  installed the language under `Ghidra\Processors\SPU`.
- Repo tooling added:
  - `tools/run_ghidra_spu_window.ps1`
  - `tools/ghidra_scripts/DisassembleSpuWindows.java`
- Smoke output:
  `debug-captures/ghidra-spu-window-20260516-212927/spu-hot-window-ghidra.txt`.

Important correction: the old `*.ls.bin` sidecars for image
`0x958dfe208b686622` are mostly zero at hot PCs `0x25cc` and `0x451c`, so a
Ghidra import of those files is misleading. The working lane rebuilds a
base-zero SPU hot-window image from the RPCS3 disassembly sidecar bytes and then
uses GhidraSPU to decode the exact runtime PCs.

Static result:

- `0x25cc` sits after a `wrch MFC_Cmd` / `rdch MFC_RdAtomicStat` reservation
  loop and falls into tag wait (`MFC_WrTagMask`, `MFC_WrTagUpdate`,
  `MFC_RdTagStat`).
- `0x451c` is the chunked MFC command issuer: it computes size, writes
  `MFC_LSA`, `MFC_EAL`, `MFC_Size`, `MFC_TagID`, then `wrch MFC_Cmd`.
- Both match the runtime SPU LLVM warnings:
  `[0x25cc] MFC_Cmd: $11 is not a constant` and
  `[0x451c] MFC_Cmd: $12 is not a constant`.

Next optimization target: add a narrow dynamic `MFC_Cmd` hot-PC probe or
compiler-side pattern proof for image `0x958dfe208b686622`, then decide whether
we can safely avoid the generic `spu_exec_mfc_cmd` fallback for the stable
command shapes in field/battle/menu.

## Reduced-Loop Unroll A/B

Hypothesis: reduced-loop emission is the only meaningful speed signal so far,
so batching more guest SPU loop iterations per generated host loop might shave
branch/condition overhead without changing normal emulator behavior.

Changed files/settings:

- `SPUCommonRecompiler.cpp` added `debug.rpcsx.thor.spu_reduced_loop_unroll`
  / `RPCSX_SPU_REDUCED_LOOP_UNROLL` with allowed effective values `1`, `2`,
  `4`, and `8`.
- The reduced-loop SPU cache key now includes the unroll factor:
  `spu-...-thor-rl-uN-v1-tane.dat`, preventing stale u2/u4/u8 compiler output
  from mixing during A/B tests.
- `SPULLVMRecompiler.cpp` uses the factor for both the reduced-loop entry guard
  and emitted loop body unroll count.
- `tools/set_thor_logging.ps1` added `ReducedLoopEmitU4` and
  `ReducedLoopEmitU8`; `ReducedLoopEmit` keeps the previous u2 behavior.
- Follow-up tooling adds `ReducedLoopEmitQuiet`, `ReducedLoopEmitU4Quiet`,
  and `ReducedLoopEmitU8Quiet` so matched FPS sweeps can keep the reduced-loop
  compiler path on while suppressing logcat/tag pressure.
- Rollback switch: use `ReducedLoopEmit` or set
  `debug.rpcsx.thor.spu_reduced_loop_unroll=2`.

Thor dev core `es-reduced-loop-unroll`, SHA256
`880C8B172817EB575C5201DED837905E3785960E70C4ACD609BC4025497A63AE`:

| Mode | Capture | FPS overlay | Visual result |
| --- | --- | ---: | --- |
| u2 | `debug-captures/android-speed-sprint/20260516-174120-es-rl-u2-field-scene/scene.png` | `18.65` | correct field |
| u4 | `debug-captures/android-speed-sprint/20260516-174631-es-rl-u4-field-scene/scene.png` | `19.81` | correct field |
| u8 | `debug-captures/android-speed-sprint/20260516-175209-es-rl-u8-field-scene/scene.png` | `19.29` | correct field |
| u4 menu | `debug-captures/android-speed-sprint/20260516-175353-thor-input-eternal-sonata-menu-route/02-pause-menu.png` | `20.22` | correct pause/menu overlay |

Additional flicker burst:

- `debug-captures/thor-screenshots/20260516-175921-es-rl-u4-menu-flicker-burst`
- 8 frames captured; first/last inspected and showed the same pause/menu overlay
  without obvious black spots or menu corruption. FPS varied during the burst,
  likely because repeated `screencap` pulls are intrusive.

Low-overhead follow-up:

- Added quiet reduced-loop logging modes so u4 can be measured without logcat
  pressure: `ReducedLoopEmitQuiet`, `ReducedLoopEmitU4Quiet`, and
  `ReducedLoopEmitU8Quiet`.
- u4 quiet field route:
  `debug-captures/android-speed-sprint/20260516-203315-thor-input-eternal-sonata-field-route/`
  plus `debug-captures/android-speed-sprint/20260516-203729-es-u4quiet-field-lowoverhead-scene/`.
  Screenshot overlays read `18.22`, `19.49`, and `19.27 FPS`; visuals looked
  correct.
- stock quiet field route:
  `debug-captures/android-speed-sprint/20260516-203849-thor-input-eternal-sonata-field-route/`
  plus `debug-captures/android-speed-sprint/20260516-204305-es-stockquiet-field-lowoverhead-scene/`.
  Screenshot overlays read `16.36`, `13.89`, and `17.95 FPS`; visuals looked
  correct. This is a low-sample overlay check, not a sustained frame-time proof,
  but it keeps u4 in the `promising` bucket and close to the first `20%` target.
- Live flicker report capture while stock quiet was active:
  `debug-captures/thor-screenshots/20260516-204435-es-live-flicker-fast`,
  `debug-captures/thor-screenshots/20260516-204848-es-live-flicker-execout`,
  and video `debug-captures/thor-screenshots/20260516-205053-es-live-flicker-video`.
  Captured props show `spu_reduced_loop_emit=0`, `spu_reduced_loop_unroll=2`,
  `logcat=0`, `rsx_texture_barrier=off`, and `rsx_depth_feedback=off`.
  Contact sheets and 10 FPS video frame extraction did not show a black-frame or
  missing-texture flash; the strongest diffs were normal butterfly/lighting
  motion. If the panel visibly flickers while capture stays clean, investigate
  presentation/frame pacing or display-path behavior before blaming u4.

Status: `promising-field-menu`, not a full win. u4 is the best tested unroll
factor and is a small field uplift over the same dev-core u2 run, with menu
visuals surviving. It still does not meet the 20% sustained target and cannot
be promoted until first battle is routable and visually correct.

Next action: keep u4 as the current reduced-loop experiment setting, then find
or create a first-battle checkpoint. After battle validation, profile u4 with
simpleperf/Perfetto to see whether SPU loop codegen or RSX FIFO becomes the new
dominant limit.
