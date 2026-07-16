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

Status: `promoted-workflow`.

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

Promotion note, 2026-05-28: this build-type correction is now promoted as the
official Thor dev-core speed workflow. Debug native cores are debug-only
evidence and must not be used for FPS/Rocknix comparisons. This does not promote
reduced-loop u4, `0x25cc bodyfast`, or any HLE/GPU fast path as a default speed
win.

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

## 2026-07-14 Upstream ARM/RSX Backport and Flicker Profile Correction

Status: `parked-device-validation`.

Scope:

- Changed the Thor process-affinity default from `0xF8` to `0xFF`. A matched
  pre-patch static-field A/B measured `23.28 FPS` median with `0xF8` and
  `27.71 FPS` median with `0xFF` (`+19.0%`). This gives Android's scheduler
  access to the efficiency cores for Java, audio, compiler, and service work
  instead of crowding all process threads onto CPUs 3-7.
- Backported the focused RPCS3 ARM I8MM work: Linux `HWCAP2_I8MM` detection,
  LLVM `+i8mm` target advertisement, and SPU LLVM `GBH`/`GBB` UMMLA/SMMLA
  lowering.
- Backported the focused RPCS3 ARM64 RSX wait work: cacheline-aware WFE waits
  for Vulkan flush coordination and the RSX semaphore acquire loop, while
  preserving RPCSX stop/debug/timeout checks.
- Corrected `push_eternal_sonata_thor_profile.ps1` so Rocknix-compatible Thor
  profiles write `Relaxed ZCULL Sync: false`. The prior generated profile had
  it enabled while the observed field run repeatedly missed the same texture
  cache keys; this is a flicker-risk correction, not yet a visual proof.
- Normalized the runtime-affinity helper's generated Android shell script from
  CRLF to LF, fixing the observed `case ... in\r` parse failure.

Local build proof:

- Native command:
  `.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon`
- Native result: success.
- Native core SHA256:
  `4A1C8A7E4AAE8568253CDAC43969D2D414FC216658834C7B04545771FE26D74D`
- Loader/package command:
  `.\gradlew.bat :app:assembleRelease -PbuildBundledRpcsxCore=false --no-daemon`
- Loader/package result: success; the APK was built locally but deliberately
  not installed after the user reported that the Thor had been hot too long.
- Local APK SHA256:
  `099431C919760990C68C95338A5777209A93C927717CA02486203E002A316A2C`

Device state at stop:

- Corrected `BLUS30161` profile and optimized native dev core were copied
  before the heat stop. The profile backup is
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/config/custom_configs/config_BLUS30161.pre-thor-speed-20260714-135736.yml`.
- The installed loader still contains profile version 12 and therefore still
  applies `0xF8`; the locally built APK containing profile version 13 and
  `0xFF` was not installed.
- RPCSX was force-stopped immediately when requested. No post-patch field,
  menu, battle, flicker, or performance run was performed.

Reading: retain the source changes and successful compile proof, but do not
classify this round as a speed win or flicker fix yet. Any later validation must
start only with a cool device and explicit user approval, use a short
screenshot-only field check first, and avoid sustained profiling or recording.

## 2026-07-14 ARM64 SPU Shuffle and Variable-Shift Follow-Up

Status: `parked-device-validation`.

Source-only follow-up while the Thor remained stopped:

- Backported upstream RPCS3 `2d1be09` so the SPU LLVM byte-rotate and
  byte-shift family emits AArch64 `TBL` directly instead of passing through the
  generic x86 `PSHUFB` compatibility lowering and its extra index mask.
- Added the single-table helper from upstream `dff29a7`. The broader
  `TBL2`/`TBX2` SHUFB and PPU VPERM conversion was deliberately not ported:
  upstream needed the much larger `a87d175` JIT retry mechanism for rare
  AArch64 register-scavenger failures. This round keeps only the safe
  single-table portion.
- Backported upstream RPCS3 `18fe6ee` so bounded infinite-precision SPU shifts
  use the AArch64 `USHL` intrinsic instead of LLVM's select-based poison-value
  workaround.

Local build proof:

- Command:
  `.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon`
- Result: success in `102s`; only pre-existing LLVM/libc++ deprecation
  warnings were emitted.
- Native core SHA256:
  `8ED415E408BAA2D44413E0A509EAF4BAD5CC43332C53DA0A241F54987BCA8832`
- Deployment: none. No ADB, APK install, app launch, capture, or device test was
  performed.

Reading: this is a compile-proven ARM64 codegen candidate, not a measured speed
win. It changes generated SPU code, so a later approved cool-device check must
use a deliberately fresh SPU cache and the normal field/menu/battle correctness
gates before promotion.

## 2026-07-14 ARM64 Single-Table SHUFB/VPERM Follow-Up

Status: `parked-device-validation`.

Continued the safe subset of upstream RPCS3 `dff29a7` while the Thor remained
stopped:

- Added the AArch64 `TBX1` LLVM helper.
- Same-source SPU `SHUFB` now uses `TBL1`/`TBX1`, including the encoded fixed
  value selectors handled by the fallback table.
- Same-source PPU `VPERM` now uses `TBL1` directly.
- Two-source SPU `SHUFB` and PPU `VPERM` deliberately retain the existing
  lowering. No `TBL2`/`TBX2` instruction or JIT retry machinery was added.

Local build proof:

- Command:
  `.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon`
- Result: success in `96.5s`; only the existing LLVM/libc++ deprecation
  warnings were emitted.
- Native core SHA256:
  `170947B2108A4D41873CE6D13C1BC49E4E574255876C11D8714E9A2E7066DC3F`
- Deployment: none. No ADB, install, launch, capture, cache mutation, or Thor
  workload occurred.

Reading: this is another compile-proven ARM64 codegen candidate, not a measured
speed win. It should be validated together with the preceding I8MM, WFE,
ROTQBY/TBL1, and USHL changes in one short cool-device field run before any
additional broad JIT or synchronization backports are stacked.

## 2026-07-14 Cool-Device Boot Check and ARM64 Verification Follow-Up

Status: `boot-only-new-core-compile-proven`.

Short Thor validation of the previously consolidated core:

- Installed the profile-v13 debuggable loader and activated consolidated core
  SHA256 `170947B2108A4D41873CE6D13C1BC49E4E574255876C11D8714E9A2E7066DC3F`.
- Moved only the five `BLUS30161` generated `spu-*.dat` files to the reversible
  device backup
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/codex-cache-backups/20260714-1728-arm64-codegen-validation/`
  before launch.
- Capture directories:
  `debug-captures/android-speed-sprint/20260714-172856-thor-input-custom/`
  and
  `debug-captures/android-speed-sprint/20260714-172941-thor-input-custom/`.
- The app ran for under one minute, produced black boot frames at both sampled
  points, and was force-stopped. Logcat confirmed the internal dev-core override,
  profile-v13 application, and Adreno Vulkan initialization, with no fatal,
  `SIGSEGV`, or `VK_ERROR` in the sampled log. This did not reach field, menu, or
  battle and therefore is not a speed, correctness, or flicker pass.
- Thor battery temperature remained `25.0 C` before and after, and Android
  thermal status remained `0`. No screen recording, Perfetto, or sustained load
  was used.

Upstream ARM64 verification/codegen follow-up:

- Backported upstream RPCS3 `ed14554` for NEON multiply-accumulate SPU runtime
  data comparisons and the AArch64 dot-product verification lane.
- Backported upstream RPCS3 `35f65c2` so large safe-mode SPU integrity checks use
  four 128-bit AArch64 accumulators and the `add(uabd)` pattern LLVM selects as
  `UABA`, instead of emulating a 512-bit checksum through generic vectors.
- Backported upstream RPCS3 `fa5b899` so the dot-product verification result is
  reduced with AArch64 `UADDV` before the expected-value comparison.
- Improved `tools/build_push_thor_core.ps1`: it now resolves and pins exactly one
  device (or accepts `-Serial`), rejects ambiguous/offline targets before build,
  and verifies `run-as` access before compiling or uploading the large core.
  The multiple-device rejection, PowerShell parser, and an explicit-serial
  successful `run-as` preflight were smoke-tested without launching RPCSX or
  pushing a core.

Local build proof:

- Command:
  `.\gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon`
- Result: success in `102.3s`; only existing LLVM/libc++ deprecation warnings.
- Native core SHA256:
  `350E2F75C9062477A05854BD9E363E730197C0025361B3F16E46795BC27EC038`.
- Deployment of this newer core: none. The Thor remains force-stopped with the
  preceding `170947...DC3F` core active.

Reading: the short device session proves loader/core bring-up only. The new
verification changes are current-upstream, ARM64-specific, and compile-proven,
but remain unmeasured. Do not claim a performance or flicker improvement until a
later cool-device field/menu/battle route validates the new cache and visuals.

## 2026-07-14 Cool-Device Field and Menu Validation

Status: `field-menu-pass-battle-pending`.

Deployment and cache state:

- Deployed ARM64 verification core SHA256
  `350E2F75C9062477A05854BD9E363E730197C0025361B3F16E46795BC27EC038`
  with the explicit-serial, no-build, no-launch path in
  `tools/build_push_thor_core.ps1`.
- Deployment capture:
  `debug-captures/20260714-190044-thor-arm64-spu-verify-uaba-uaddv-dev-core-push/build-push.txt`.
- The device-side dev-core SHA256 matched the local core after the run.
- The prior five generated SPU cache files remain in the reversible backup
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/codex-cache-backups/20260714-1728-arm64-codegen-validation/`.
  This run started without an active generated SPU cache and produced a fresh
  `spu-safe-v1-tane.dat`.

Launcher correction:

- The first bounded launch stayed black and nearly idle because Android reported
  `mWakefulness=Asleep` and both displays were off; the native activity had no
  active surface. This also explains the misleading black boot-only captures in
  the preceding round.
- `tools/thor_input_macro.ps1` now sends `KEYCODE_WAKEUP`, dismisses the keyguard,
  and waits 500 ms before the debug-boot intent. The next launch immediately
  progressed through Vulkan initialization and normal guest execution.

Bounded visual validation:

- Awake boot captures:
  `debug-captures/android-speed-sprint/20260714-190731-thor-input-custom/01-boot-awake-30s.png`
  and
  `debug-captures/android-speed-sprint/20260714-190828-thor-input-custom/01-boot-awake-60s.png`.
  The second frame shows the correct Eternal Sonata title at `30.00 FPS`.
- New-game chapter capture:
  `debug-captures/android-speed-sprint/20260714-190929-thor-input-custom/01-post-skip.png`.
  It shows the correct Chapter 1 `Raindrops` splash at `30 FPS`.
- Field captures:
  `debug-captures/android-speed-sprint/20260714-191024-thor-input-custom/01-field-candidate.png`
  and
  `debug-captures/android-speed-sprint/20260714-191155-thor-input-custom/01-field-second.png`.
  Both show the correct playable opening forest field at approximately `30 FPS`.
- Menu capture:
  `debug-captures/android-speed-sprint/20260714-191155-thor-input-custom/02-menu.png`.
  It shows the correct pause overlay over the rendered field at `30.00 FPS`.
- Short movement captures:
  `debug-captures/android-speed-sprint/20260714-191243-thor-input-custom/01-battle-approach.png`
  and
  `debug-captures/android-speed-sprint/20260714-191243-thor-input-custom/02-battle-transition.png`.
  They show valid moving-field frames with instantaneous overlay samples of
  `17.74 FPS` and `28.71 FPS`. The route missed the visible enemy and did not
  enter battle, so these are not first-battle proof.
- No missing textures, black regions, or obvious flicker appeared in the sampled
  title, field, movement, and menu frames. Screenshot samples cannot prove the
  complete absence of temporal flicker.

Safety and error checks:

- The entire awake validation used screenshots only: no screen recording,
  Perfetto, or sustained profiler.
- Battery temperature stayed between `23.0 C` and `25.0 C`; Android thermal
  status stayed `0`. RPCSX was force-stopped after the short battle route missed,
  and its process was confirmed absent.
- Final logcat and `RPCSX.log` scans found no fatal exception, fatal signal,
  `SIGSEGV`, `VK_ERROR`, LLVM error, or SPU verification failure.

Reading: promote this core from boot-only to title/field/menu and moving-field
correctness pass. Do not claim a performance win because there is no matched A/B,
and do not claim a complete flicker fix or battle pass. The next device action,
after another cool-device check, is a short deterministic first-battle route;
only then should a bounded matched performance comparison be considered.

## 2026-07-14 Deterministic First-Battle Route and Fatal Isolation

Status: `battle-visual-reached-fatal-invalid`.

Bounded checkpoint route:

- Kept ARM64 verification core SHA256
  `350E2F75C9062477A05854BD9E363E730197C0025361B3F16E46795BC27EC038`
  active and used the existing top save slot, `Path to Tenuto / South Section`.
- Staged screenshots confirmed the correct title, top save slot, load-complete
  prompt, and correct checkpoint field:
  `debug-captures/android-speed-sprint/20260714-192209-thor-input-custom/01-title-ready-70s.png`,
  `debug-captures/android-speed-sprint/20260714-192320-thor-input-custom/01-save-list.png`,
  `debug-captures/android-speed-sprint/20260714-192415-thor-input-custom/01-loaded-checkpoint.png`,
  and
  `debug-captures/android-speed-sprint/20260714-192526-thor-input-custom/01-loaded-field.png`.
- The previous `left:2600` plus `down_left:2200` movement was too long. From
  the exact save checkpoint, `down_left:700`, then `left:900`, hit the visible
  enemy. The transition capture is
  `debug-captures/android-speed-sprint/20260714-192709-thor-input-custom/01-enemy-approach-left900.png`
  at an instantaneous `29.77 FPS`.
- Ten seconds later, the first-battle tutorial prompt rendered correctly at
  `30.00 FPS`, with Polka, the arena, HP, timer, and battle UI intact:
  `debug-captures/android-speed-sprint/20260714-192756-thor-input-custom/01-battle-state-10s.png`.

Fatal classification:

- Manual inspection between staged inputs left the tutorial prompt idle. Before
  the attempted post-tutorial input, `RPCSX.log` reported
  `VM: Access violation reading location 0x40` on PPU thread `0x100000c` at CIA
  `0x002aedd0`, then `Emulation has been frozen!` at emulation time `0:08:03`.
- The attempted post-tutorial capture still showed the prompt and the RPCSX
  frozen-app notification at `29.68 FPS`:
  `debug-captures/android-speed-sprint/20260714-192916-thor-input-custom/01-first-battle-active.png`.
  It is failure evidence, not active-combat proof.
- Android logcat had no native fatal signal or process crash. This is a guest PPU
  fatal at the same `0x002aedd0` / `0x40` signature already documented in older
  Windows route failures, not evidence of a native ARM64 verifier crash.
- Because the same run later fatally froze, the earlier correct battle prompt is
  not a promotable first-battle pass. Field/menu correctness from the preceding
  bounded run remains valid, but full battle and speed promotion remain pending.

Harness correction, source-only after stopping the device:

- Replaced the over-eight-minute `eternal-sonata-battle-intro-route` with the
  observed checkpoint timings and the deterministic `down_left:700` plus
  `left:900` enemy path. The new route immediately selects `No` at the tutorial
  instead of idling there for several minutes.
- Added explicit `-Serial` device selection with early ambiguity/offline errors.
- Added a default `39.0 C` battery-temperature ceiling. Long waits are split into
  five-second thermal checks, and reaching the ceiling force-stops RPCSX.
- Added `check:guest:LABEL` to scan the current `RPCSX.log` tail for guest VM,
  frozen-emulation, SPU STOP, Vulkan device-lost, LLVM, and verification fatals;
  a match force-stops RPCSX. Added a final `stop` macro token so the corrected
  battle profile cannot leave the emulator running.
- These harness changes were not used for another Thor launch in this round.

Safety: the device stayed at `25.0-26.0 C` with Android thermal status `0` and
was confirmed stopped. Do not immediately rerun after this fatal. The next proof
should use the corrected one-shot profile on a separately cool device; it must
show a post-tutorial active-battle frame and a clean guest-fatal guard before any
performance comparison.

## 2026-07-14 Guarded One-Shot Battle Result and ARM64 Upstream Backports

Status: `active-battle-visual-fatal-invalid`; new core is `host-build-only`.

Corrected one-shot route:

- Ran `eternal-sonata-battle-intro-route` exactly once against serial
  `c3ca0370`, with `-BootGame`, `-ForceStop`, direct input, the `39 C` ceiling,
  and guest-fatal checks. Evidence is under
  `debug-captures/android-speed-sprint/20260714-201323-thor-input-eternal-sonata-battle-intro-route`.
- The installed core remained SHA256
  `350E2F75C9062477A05854BD9E363E730197C0025361B3F16E46795BC27EC038`.
  All Eternal Sonata superpath/fast-wait/RSX experiment gates were off; SPU
  verification and accurate reservations remained enabled.
- The route reproduced the correct field at `27.15 FPS`, first-battle tutorial
  prompt at `30.00 FPS`, and visually complete active-battle UI/arena at
  `29.53 FPS` in `04-loaded-field.png`, `05-first-battle-prompt.png`, and
  `06-first-battle-active.png` respectively.
- The active-battle capture also contains the frozen-application notification.
  The guest-fatal guard detected the fault, pulled the log, force-stopped RPCSX,
  and prevented the route from continuing. The displayed FPS is therefore a
  frozen instantaneous sample, not a valid battle-speed result.

New fatal boundary:

- At emulation time `0:02:50.539004`, PPU thread `0x100000c` faulted at CIA
  `0x002ad588` while reading `0x3f80000c`, then froze emulation. The call stack
  is `0x002ad588 <- 0x002fa0f0 <- 0x002ad5a8 <- 0x002afd14`.
- The command stream supplied `r4/r8 = 0x3f800000` (IEEE-754 `1.0`) where the
  callee treated the value as an object pointer and read its `+0x0c` member.
  Immediately before the fault, the game reported unknown draw commands
  `3f800001` and `3fd20001`. This is consistent with guest draw-command/object
  stream desynchronization, not a native Android signal or Vulkan device loss.
- The exact CIA differs from the older Windows/Android
  `0x002aedd0 -> 0x40` boundary, but it remains in the same guest PPU command
  parser thread. No title-specific fast gate was enabled, and older stock
  Windows controls have shown the same class of guest failure. Do not attribute
  this fault to a performance gate without a matched reproducer.

Thermal/safety result:

- Every five-second guard sample remained exactly `25.0 C`; Android thermal
  status was `0` before and after the route. RPCSX was confirmed stopped.
- No second Thor run, screen recording, Perfetto capture, APK install, or new
  core deployment was performed in this round.

Source-only upstream candidates:

- Adapted upstream RPCS3 commits `3f27cb8` and `03647fd` to the Android ARM64
  SPU LLVM verifier. Large hole-free verification regions now use a generated
  loop over 96-byte/six-NEON-vector checksum blocks; partial/holey regions keep
  the checked fallback. SPU verification is not disabled or weakened.
- Adapted upstream RPCS3 commit `b90eef3` to the vendored PPU LLVM worker
  callback. It checks for remaining work before locking a compiler core and
  explicitly unlocks if the post-lock recheck fails, avoiding a retained core
  lock during compiler-worker shutdown.
- `./gradlew.bat :app:assembleDebug --no-daemon --console=plain` completed with
  `BUILD SUCCESSFUL`; both `buildCMakeDebug[arm64-v8a]` and
  `buildCMakeDebug[x86_64]` are current. The debug APK SHA256 is
  `F17D1927DBAA98162572AD097354AE9B61BAC6D65F252CBC9AB8E1D8FC7132CE`;
  its stripped ARM64 `librpcsx-android.so` SHA256 is
  `E560C2D7643A152B9E7E5DF2F17BDD890FBD05CB13986AA72CEF762E1A9920F2`.
- This candidate is host-build validated only and is not the installed Thor
  core. The next device action, after an explicit cool-device check, is one
  bounded corrected route with the new core. Promotion still requires clean
  field, menu, tutorial, and live battle evidence with no guest-fatal guard hit.

## 2026-07-14 Upstream RCHCNT Fix and Guarded Field Result

Status: `field-clean-battle-route-missed`; correctness candidate remains
`battle-pending`.

Source findings and fixes:

- Current official RPCS3 includes `7d0df30`, which fixes SPU output-mailbox
  `RCHCNT` loops by blocking in `wait_rchcnt` for `SPU_WrOutMbox` and
  `SPU_WrOutIntrMbox`. The vendored Android core lacked both cases and therefore
  kept polling those write channels. The two upstream cases were backported
  using this tree's `OFFSET_OF` convention. This is both a timing-correctness
  candidate and a CPU/thermal improvement; it is not a title-specific shortcut.
- Backported upstream `42242b3`, correcting the Giga analyzer re-decode index
  from `/ 41` to `/ 4`. Eternal Sonata currently uses Safe block size, so this
  is a general codebase correctness repair rather than the explanation for this
  run.
- Fixed `tools/thor_ooda.ps1` to splat named stream parameters with a hashtable.
  Its previous array splat bound literal option names positionally and attempted
  to convert `net.rpcsx.easy` into `PollSeconds`.
- Future battle-route screenshots now use `-candidate` labels until visual
  review confirms that combat was actually reached.

Host and deployment proof:

- `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` completed successfully in `151.9s`.
- RelWithDebInfo ARM64 core SHA256:
  `A7D5A628128A2D4949CA5E0A641CF6C2B1D4EAB061129C202ECE40AAA6899593`.
- The same SHA256 was verified at
  `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so` after deploy.
- The previous Eternal Sonata SPU cache was moved, not deleted, to
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/codex-cache-backups/20260714-2340-rchcnt-upstream-fix/spu-safe-v1-tane.dat`.

Single guarded Thor result:

- Capture:
  `debug-captures/android-speed-sprint/20260714-233735-thor-input-eternal-sonata-battle-intro-route`.
- The route loaded the correct `Path to Tenuto / South Section` save and showed
  a clean field at `27.27 FPS`. The later candidate frames remained in the
  field at `27.04` and `28.61 FPS`; the movement missed the enemy, so there is
  no tutorial or active-battle proof and no battle-speed claim.
- The fresh `RPCSX.log` was `635820` bytes and contained zero targeted unknown
  draw, VM access, frozen-emulation, fatal, SPU STOP, verification, or Vulkan
  device-loss hits. This is a clean field result only.
- Battery temperature stayed between `24.0 C` and `25.0 C` under a `35 C`
  ceiling, Android thermal status remained `0`, and RPCSX was force-stopped and
  confirmed absent. No second run, recording, Perfetto, or sustained profiler
  was used.

Decision: retain the upstream fixes and deployed candidate. Do not claim the
battle corruption fixed until a later cool-device run visibly reaches live
combat and remains free of the guest parser fatal. Do not repeat this route
unchanged; repair its collision movement/state gate first.

## 2026-07-15 State-Gated First-Battle Pass and Android TTY Stall Fix

Status: `valid-first-battle-triage-with-guest-draw-warnings`; not a matched
speed result and not a complete temporal-flicker proof.

Route repair:

- The prior miss was not a wrong save and the direct-stick durations were not
  truncated. Manual and automated captures showed wall-time movement distance
  varied while SPU/shader work warmed, so a single blind collision pulse was
  not a reliable state gate.
- `tools/thor_debug_common.ps1` now classifies Eternal Sonata's battle HUD from
  the normalized cyan action-time bar at the left edge. Known field captures
  measured `0 / 13488` matching samples while known tutorial/live-battle
  captures measured `463 / 13488` (`3.433%`).
- `tools/thor_input_macro.ps1` now uses
  `approach:battle:left:left:900:3:11000`: a maximum of three thermally bounded
  pulses, with a screenshot and guest-fatal check after each. It stops adding
  movement as soon as the battle HUD is present and force-stops RPCSX on any
  unexpected macro failure. The route also keeps 10-second and 20-second live
  battle checkpoints and records unknown-draw messages into sidecars.

Single guarded Thor proof:

- Core under test: the previously deployed upstream-RCHCNT candidate SHA256
  `A7D5A628128A2D4949CA5E0A641CF6C2B1D4EAB061129C202ECE40AAA6899593`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-144058-thor-input-eternal-sonata-battle-intro-route`.
- The first approach attempt passed the visual gate with `463 / 13488` cyan
  samples. Screenshots show the correct field at `27.68 FPS`, tutorial prompt
  at `29.99-30.00 FPS`, live battle at `30.00 FPS`, live battle after 10 seconds
  at `29.99 FPS`, and live battle after 20 seconds at `30.00 FPS`.
- All three live-battle frames show the arena, Polka, HP/timer, and command UI
  without the old frozen-app notification or visible black/corrupt regions.
  Guest guards found no VM access violation, frozen emulation, STOP,
  verification failure, LLVM fatal, or Vulkan device loss.
- The game did still print internal unknown draw commands `3f800000`,
  `30b12f20`, `3e21bf94`, and `bf7a924b`. They no longer escalated to the old
  `0x002ad588` / `0x3f80000c` fatal during this bounded run, but they keep full
  temporal-flicker promotion open.
- The one 205.9-second run stayed exactly `25.0 C` across 54 battery guard
  samples with Android thermal status `0`. RPCSX was force-stopped and the PID
  was absent. No second launch, video, Perfetto, or sustained profiler was used.

Android logging hot-path fix:

- Each non-warning guest TTY message was also triggering upstream's
  `dump_useful_thread_info()` all-thread diagnostic walk. The unknown-draw
  prints therefore produced large PPU/SPU context dumps and mobile log I/O on
  the gameplay path.
- `app/src/main/cpp/rpcsx/kernel/cellos/src/sys_tty.cpp` now skips that full
  context dump for routine TTY output on Android while preserving the actual
  guest message and preserving full context dumps for warning-class output.
  This is a semantics-neutral mobile frame-time/log-I/O optimization, not a
  guest draw-parser bypass.
- RelWithDebInfo ARM64 build completed successfully in `100.3s`. The resulting
  core SHA256 is
  `548A4CF44904223E5B47E6817EC15C19B4FDA57CADA72E2C67D0BA4927537264`.
- The core was copied and hash-verified at
  `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so` using
  `tools/build_push_thor_core.ps1 -NoBuild -NoLaunch -NoStream`. Thor remained
  stopped at `25.0 C`, thermal status `0`; this newest logging-only core is
  host-build/deploy validated but intentionally has no second gameplay run.

Decision: bank the RCHCNT candidate as a bounded first-battle correctness pass,
not a speed win. Keep the new Android TTY optimization installed without a
same-day rerun. The next cool-device proof should focus on temporal flicker and
unknown-draw frequency; do not repeat the already-clean route merely for FPS.

## 2026-07-15 Intermittent Battle Fatal and PPU Reservation-Priority Candidate

- Status: `failed` for the logging-only core battle proof; `proposed` and
  build/deploy-only for the reservation-priority candidate.
- Scope: `spu-codegen` / PPU-SPU reservation contention / battle stability.
- Hypothesis: the prior successful battle pass did not remove the underlying
  PPU/SPU shared-state race. Giving a contending PPU writer the opt-in head
  start added by upstream RPCS3 commit `e379fba` may prevent reservation-heavy
  SPU work from repeatedly winning the VM range lock.

Failed single guarded proof:

- Core SHA256:
  `548A4CF44904223E5B47E6817EC15C19B4FDA57CADA72E2C67D0BA4927537264`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-154520-thor-input-eternal-sonata-battle-intro-route`.
- The same state gate reached the correct field and detected the battle HUD on
  approach attempt one (`463 / 13488`, `3.433%`). The field screenshot was
  visually clean at `27.13 FPS`; the active-battle screenshot was visually
  clean at `29.99 FPS`.
- The first active-battle guest guard then found the exact historical fatal:
  CIA `0x002ad588`, VM read at `0x3f80000c`, followed by frozen emulation.
  Preceding internal draw values included `3e21bf94`, `bf7a924b`, and
  `3f800000`. This supersedes the prior one-pass stability conclusion: the
  RCHCNT change lowered or shifted the failure probability but did not fix it.
- The harness force-stopped RPCSX immediately. The planned temporal burst and
  10/20-second checkpoints were not executed, so this run provides no flicker
  clearance and no speed result.
- Device temperature moved only from `24.0 C` to `25.0 C`; Android thermal
  status remained `0`. There was no second gameplay run, screen recording,
  Perfetto capture, or sustained profiler.

Logging optimization result:

- The Android TTY optimization behaved as intended even though gameplay later
  failed. All three routine unknown-draw messages in the new health log had
  zero attached all-thread context dumps. In the preceding core's comparable
  battle-active health log, two of four unknown-draw messages carried 332-line
  context blocks. Keep the logging optimization; it is not the cause of the
  guest VM fault and it removes avoidable mobile log work.

Source candidate and deployment:

- Backported the runtime half of upstream RPCS3 `e379fba`: a new
  `PPU Reservation Priority Over SPUs` core option performs one short
  `busy_wait(5000)` when a writer first encounters a contended exclusive range
  lock. The option defaults off globally.
- `tools/push_eternal_sonata_thor_profile.ps1` exposes the option as
  `-PpuReservationPriority`; the deployed BLUS30161 custom profile enables it,
  keeping the experiment title-scoped and reversible.
- The battle macro now schedules four short still captures after active battle
  and omits the broken thread snapshot. This is lower-load temporal evidence
  than screen recording and does not mix profiling overhead into the route.
- `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` completed with `BUILD SUCCESSFUL`. Candidate ARM64 core
  SHA256:
  `AE07E245D4FD40C01FF34B6C433755227E56F39F79C55C00528829497228B3E8`.
- The candidate core and profile were pushed with no launch. The same SHA was
  verified at `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`;
  RPCSX remained stopped at `25.0 C`, thermal status `0`.
- Rollback: rerun `tools/push_eternal_sonata_thor_profile.ps1` without
  `-PpuReservationPriority` (which writes the setting as `false`), or restore
  `config_BLUS30161.pre-thor-speed-20260715-155905.yml`. The code option itself
  remains inert unless enabled.

Decision: do not call the game stable or faster yet. On the next cool-device
round, run at most one guarded state-gated battle proof with `AE07...B3E8`.
Because the failure is intermittent, one pass is only a candidate; require two
consecutive clean battle proofs across separate cool rounds before stability
promotion. If the exact `0x002ad588` / `0x3f80000c` fatal repeats, turn the
setting back off and pivot to deeper SPU/PPU reservation-semantics analysis
instead of repeating the route.

## 2026-07-15 Reservation-Priority Rejection and Process-Restart Guard

- Status: `failed`; the reservation-priority switch did not prevent the
  intermittent first-battle crash and is disabled again.
- Core SHA256 under test:
  `AE07E245D4FD40C01FF34B6C433755227E56F39F79C55C00528829497228B3E8`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-160625-thor-input-eternal-sonata-battle-intro-route`.

Single guarded Thor result:

- The state gate reached the battle HUD on approach attempt one. The correct
  field was visually clean at `26.97 FPS`; the first active-battle image was
  clean at `30.00 FPS`, and the first 750 ms temporal image was clean at
  `29.90 FPS`.
- At device log time `12:09:26.061`, PID `12630` then reported
  `Segfault reading location 0000000ff88a7008 at 0000007a1bdd180c` on
  `PPU[0x100000c]`. The fatal thread termination followed at `12:09:26.082`,
  Android declared PID `12630` dead at `12:09:26.402`, and started replacement
  PID `13909` at `12:09:26.419`.
- The second through fourth temporal images and both nominal 10/20-second
  images therefore show the replacement process preloading shaders and
  analyzing PPU code, not live battle. The visible flicker was an internal
  native-core/app restart. Those checkpoints and the script's original
  success exit are invalid; there is no stability or speed pass.
- The last guest-log tail from the old process contained unknown draw commands
  `3e21bf94`, `bf7a924b`, and `30b12f20`, but no targeted guest fatal. Pulling
  `RPCSX.log` from the replacement process hid the old process's terminal
  lines, which explains the false-negative health check.
- The same native address and `PPU[0x100000c]` signature is present in logcat
  for the preceding logging-only-core failure at device time `10:44:19`.
  Therefore this run rejects reservation priority as a fix; it does not show
  that the switch introduced a new crash signature.
- The one `206.6s` route stayed from `25.0 C` to `26.0 C` across 61 thermal
  samples under the `35 C` cutoff. RPCSX was stopped, no second route was run,
  and no recording, Perfetto trace, or sustained profiler was used.

Rollback and harness hardening:

- Re-pushed the title profile without `-PpuReservationPriority`; deployed
  `config_BLUS30161.yml` now explicitly has
  `PPU Reservation Priority Over SPUs: false`. The dormant, default-off
  upstream code remains available but is not active for Eternal Sonata.
- Booted input macros now pin the first RPCSX PID, validate it during bounded
  waits and around every token, screenshot, and guest-log check, and fail
  closed if the PID disappears or changes. A failed guard captures the final
  400 logcat lines before force-stopping the replacement process.
- Native `Segfault reading location` and abnormal-thread termination text was
  also added to the guest-log fatal patterns for cases where the original log
  remains readable.

Decision: keep the Android TTY logging optimization, keep reservation priority
off, and do not repeat this route just to chase a pass. The next optimization
round should investigate the recurring `PPU[0x100000c]` native address fault
from host/static evidence first; any later Thor proof must use the PID guard.

## 2026-07-15 Upstream Access-Violation Exit Fix and ARM64 Crash Context

Status: `host-build-and-deploy-only`; upstream stability candidate, not a
gameplay pass.

Static fault mapping:

- The replacement process's startup log shows Thor's guarded guest VM window
  at `0x1000000000..0x10ffffffff`. The repeated native read location
  `0x0ff88a7008` is `0x07758ff8` below that base and is exactly
  `base + sign_extend_32(0xf88a7008)`. A zero-extended guest address would
  instead be `0x10f88a7008`, inside the guarded 4 GiB window.
- This proves that the terminal PPU access escaped the guest fault handler via
  an invalid high-bit effective-address state. It does not by itself prove
  whether the bad PPU address was the primary fault or a secondary fault while
  the emulator was already pausing/stopping. A global address mask was not
  added because it would diverge from the interpreter's checked `vm::cast`
  semantics and could hide guest-state corruption.
- The prior same-signature event at device time `10:44:19` coincided with the
  end of the earlier clean battle route: its last health check began at local
  `14:44:19.050`, immediately before the old thread-snapshot token. The
  signature is therefore recurring and is not specific to reservation
  priority.

Upstream backport:

- Ported the compatible core of upstream RPCS3 `bb3e268`, "Thread.cpp: Fix
  game exit on access violation." Access-violation recovery now tracks the
  exact recovered address instead of a process-wide boolean, distinguishes
  data from executable faults, restores executable mappings through
  `ppu_register_range`, and keeps retrying the emergency page recovery while
  emulation is stopping instead of escalating a transient guest fault to a
  native process exit.
- The fork predates upstream's second executable-address side table, so that
  unrelated later branch was not fabricated here. Existing base and executable
  mirror handling is retained.
- Android ARM64 terminal faults now add the VM/sudo/exec bases, faulting
  instruction, PPU CIA, X0-X30, and SP to the existing fatal message. This runs
  only after an unrecovered crash and adds no normal frame-path work. Combined
  with the macro PID guard, a future single failure should be actionable
  without a screen recording or sustained profiler.

Build and cool deployment proof:

- `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` completed successfully in `73s`; only existing deprecation
  warnings were emitted.
- Candidate ARM64 core SHA256:
  `8E4150FFF7F75233FE1C4C9537B4A78B18317FC942D1558E620D82EB580363AE`.
- `tools/build_push_thor_core.ps1 -NoBuild -NoLaunch -NoStream` copied the
  candidate to `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`;
  `run-as ... sha256sum` verified the identical remote hash.
- RPCSX remained stopped. Thor battery temperature was `26.0 C`, Android
  thermal status was `0`, and the deployed BLUS30161 profile still has
  `PPU Reservation Priority Over SPUs: false`. No game launch, cache mutation,
  recording, trace, or profiler was used.

Decision: retain this upstream recovery candidate for the next separately cool
proof, but do not call the intermittent battle fault fixed yet. The next run
must be one PID-guarded, screenshot-only battle route; a process change is an
automatic failure, while a clean route still needs repetition in a later cool
round before stability promotion.

## 2026-07-15 PID-Guarded Native Fault Resolution and PPU Worker Recycle

Status: `failed-before-battle` for gameplay; the replacement core is
`host-build-and-deploy-only` and has not been launched.

Guarded Thor result:

- Capture:
  `debug-captures/android-speed-sprint/20260715-164549-thor-input-eternal-sonata-battle-intro-route`.
- The route reached a visually clean field at `27.33 FPS`, but it did not
  produce a first-battle frame. Expected PID `27977` died and replacement PID
  `29264` appeared before the `wait-11900-ms` checkpoint at `167.7s`; the PID
  guard force-stopped the replacement and failed the run.
- The original process reported signal 11 while reading
  `0x0000000ff88a6ff8` at native PC `0x0000007a2f4c180c`. Its VM, sudo, and
  executable bases were `0x1000000000`, `0x1100000000`, and `0x1200000000`.
  ARM64 instruction `0xb8686ac8` decodes as `LDR W8, [X22, X8]`; `X22` held
  the VM base and `X8` held the sign-extended bad guest address
  `0xfffffffff88a6ff8`. The active PPU CIA was `0x002ad294`.
- Corrected EBOOT disassembly identifies `0x002ad294` as
  `rldicl r11,r31,0,32`, followed by `lwz r3,0(r11)` at `0x002ad2a4` and
  `lfsx` at `0x002ad2bc`. This is in the same corrupt command-stream family as
  the prior `0x002ad588` / `lwz r4,0(r9)` failure. The upstream exit-recovery
  backport did not repair the invalid guest state.
- No broad address mask was added. Masking would diverge from checked
  interpreter address semantics and could hide the corrupt producer/publisher
  state rather than fix it. The stream-corruption root cause remains open.
- Thor stayed at `26.0 C` with thermal status `0`. RPCSX was stopped after the
  guarded failure and no second gameplay route, recording, Perfetto trace, or
  sustained profiler was used.

Upstream and diagnostic follow-up:

- Compared the Android fork with current upstream RPCS3 `origin/master`
  `49b0306`, the official Windows build that previously completed the corrected
  battle route. Relevant ARM64 `cmp_rdata` NEON and I8MM work is already in
  this fork; duplicating it would not address this failure.
- Adapted upstream `24a1576`, "PPU LLVM: Recycle current thread for execution."
  PPU module compilation now runs one worker on the caller and creates one
  fewer background thread while preserving the local memory and compiler-core
  limits. This reduces compilation contention and transient thread pressure;
  it is not evidence of higher gameplay FPS.
- Android ARM64 fatal logging now emits a same-page nine-instruction window
  around the native PC. The PID guard now saves the complete in-memory logcat,
  a filtered fatal/process view, and PID metadata before force-stop. This avoids
  losing the original crash when a replacement process floods a short log tail
  with shader startup messages.

Build and cool deployment proof:

- `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` completed successfully in `98s`; only existing deprecation
  warnings were emitted.
- Replacement ARM64 core SHA256:
  `C1A5E6A0E8982A02A6C06C6C72B566F00E11EFBC372DE62449BD494EC981B16A`.
- `tools/build_push_thor_core.ps1 -NoBuild -NoLaunch -NoStream -Label
  ppu-worker-recycle` deployed the core without launching RPCSX. Push record:
  `debug-captures/20260715-171237-ppu-worker-recycle-dev-core-push/build-push.txt`.
  `run-as` verified the same hash at
  `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`.
- Final device state was RPCSX stopped, `26.0 C`, thermal status `0`.

Decision: retain the worker-recycle and crash-evidence improvements. Do not
claim faster or stable gameplay from this round. A later separately cool round
may spend at most one PID-guarded battle route on this core; promotion still
requires a live battle with no process replacement, correct field/battle/menu
visuals, and a later independent clean repetition.

## 2026-07-15 Battle-Visual Guest Fatal and JIT-Manager Concurrency Backport

Status: `active-battle-visual-fatal-invalid` for gameplay; the replacement
core is `host-build-and-deploy-only` and has not been launched.

Single guarded Thor result:

- Core SHA256 under test:
  `C1A5E6A0E8982A02A6C06C6C72B566F00E11EFBC372DE62449BD494EC981B16A`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-171802-thor-input-eternal-sonata-battle-intro-route`.
- The route showed a visually clean field at `26.04 FPS`, tutorial/battle
  prompt frames at `28.02` and `30.01 FPS`, and a visually clean active-battle
  frame at `30.48 FPS`. The battle HUD gate passed on approach attempt one
  (`463 / 13488` cyan samples, `3.433%`). These stills prove route position,
  not live stability: the guest log had already reported corrupt draw values.
- At emulation time `0:02:51.134`, the draw parser received float-like command
  values `bf26f13a`, `bfca2f4e`, `3f955080`, `3f800001`, and `3fd20001`.
  At `0:03:00.849`, PPU thread `0x100000c` then faulted at CIA `0x002ad588`
  while reading unmapped guest address `0x3f80000c`; frozen emulation followed.
  This is the same intermittent corrupt command-stream family as the earlier
  `0x002ad588` failures, so the worker-recycle change is neither a fix nor a
  newly introduced regression.
- PID `7993` remained the original process until the guest-health guard found
  the fatal; there was no Android process replacement in this run. The harness
  force-stopped RPCSX immediately. No second gameplay run, recording, Perfetto
  trace, or sustained profiler was used.
- All guarded thermal samples were exactly `26.0 C` under the `35 C` cutoff.
  The final cool-state check also reported `26.0 C`, Android thermal status
  `0`, and no RPCSX PID.

Upstream performance and harness follow-up:

- Adapted current upstream RPCS3 `f05ece4`, "PPU LLVM: Fix concurrency
  weakness of jit_module_manager." The PPU JIT manager now uses 256 buckets
  instead of 30, hashes cache-relative module names with the upstream FNV
  helper, and removes the dead extra-large-module lock path. This reduces
  PPU-module compilation contention without changing guest execution or the
  battle command parser. It is a compile/loading performance improvement, not
  evidence of higher warm-cache battle FPS or of a stability fix.
- A booted input-macro failure now always force-stops RPCSX, records the
  original failure text and a post-stop thermal sample, and writes the
  requested failure snapshot before rethrowing. This closes the prior gap
  where `-PostSnapshot` was skipped on a guest-fatal exception. PowerShell
  parser validation passed; the change was not used to justify another run.

Build and cool deployment proof:

- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  ppu-jit-manager-concurrency -NoLaunch -NoStream` completed the optimized
  RelWithDebInfo ARM64 build successfully in `2m 38s`; only existing
  deprecation warnings were emitted.
- Replacement ARM64 core SHA256:
  `90646E5386E922DC65FDA1E4006E6A3026C0FAB7F45832756FC1EC3AC4681F0A`.
  Push record:
  `debug-captures/20260715-174253-ppu-jit-manager-concurrency-dev-core-push/build-push.txt`.
  `run-as` verified the identical hash at
  `/data/data/net.rpcsx.easy/files/dev-core/librpcsx-android.so`.
- RPCSX remained stopped after deployment at `26.0 C`, thermal status `0`.
  The new core was not launched, so no gameplay claim is attached to it.

Decision: retain the upstream JIT-manager and failure-snapshot improvements,
but keep the stability issue open. Do not rerun on the hot path in this round.
The next separately cool proof may spend one guarded battle route on
`90646E...1F0A`; even a clean run remains provisional until repeated in a
later cool round.

## 2026-07-15 Live-Battle Guest Fatal and Title-Gated Publish Fence

Status: `active-battle-live-fatal-invalid` for gameplay; the replacement core
is `host-build-and-deploy-only` and has not been launched.

Single guarded Thor result:

- Core SHA256 under test:
  `90646E5386E922DC65FDA1E4006E6A3026C0FAB7F45832756FC1EC3AC4681F0A`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-175013-thor-input-eternal-sonata-battle-intro-route`.
- The route showed a visually clean field at `26.68 FPS` and a visually clean
  active-battle candidate at `29.99 FPS`. The battle gate passed on attempt one
  (`463 / 13488` cyan samples, `3.433%`). The fourth temporal still and the
  ten-second live candidate were the same frozen battle image with the guest
  crash toast; their approximately 30-FPS overlays were stale and are not
  performance evidence.
- Draw-command corruption began at emulation time `0:02:45.673` with
  `3f800000`, followed by `32dfda10`, `1c005505`, `18018184`, `207ffa8e`,
  `461c4000`, `30b12f20`, and another `3f800000`. At `0:03:09.773`, PPU thread
  `0x100000c` faulted at CIA `0x002ad588` while reading guest address
  `0x3f80000c`.
- The fault registers make the stream desynchronization concrete: the command
  buffer pointer in `r31` remained valid, while `r4`, `r8`, and `r24` held
  float `1.0` (`0x3f800000`) and the handler dereferenced it at offset `+0x0c`.
  A broad VM address mask would hide this corrupt guest state and was not used.
- PID `16952` remained the original RPCSX process throughout; there was no
  Android process replacement. Peak RSS was `9312 MB`, falling to `6983 MB`
  after the guest froze. The improved failure path captured the full snapshot,
  original PID, and thermal state before force-stop.
- Every guarded sample was exactly `26.0 C`, below the `35 C` cutoff. RPCSX was
  stopped after the failure, and no second route, screen recording, Perfetto
  trace, or sustained profiler was used.

Static-analysis result and narrow workaround:

- Ghidra traced the EBOOT command producer through `0x002f76a4` into publisher
  `0x002ac618`. The publisher terminates the current buffer at `0x002ac620`,
  then stores the new active-buffer flag at `0x002ac638`; it contains no guest
  `sync` or `lwsync`. The consumer reads the selector at `0x002acc24` and the
  selected buffer pointer at `0x002acc4c` before entering the command loop.
- Current upstream RPCS3 has no PPU memory-ordering change at these paths. The
  Android ARM64 LLVM translator now emits a release fence immediately before
  the exact publisher store and an acquire fence immediately before the exact
  selected-buffer load. Both fences require title ID `BLUS30161`, so other
  games and desktop builds are unchanged; there is no per-frame broad fence.
- The PPU object-cache settings include a matching BLUS30161 Android bit. Old
  cached objects therefore cannot silently bypass the new code generation.
  This is an evidence-backed experiment, not a confirmed fix until a later
  cool guarded route reaches and remains in live battle.

Build and cool deployment proof:

- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  es-command-publish-fence -NoLaunch -NoStream -NoFallbackBuild` completed the
  optimized RelWithDebInfo ARM64 build successfully in `99.8s`; only existing
  deprecation warnings were emitted.
- Replacement ARM64 core SHA256:
  `15291FA7A30276BB91CB92F06187D57CA1D277F7FA4637D0C8D10A7C33C35EA6`.
  Push record:
  `debug-captures/20260715-181251-es-command-publish-fence-dev-core-push/build-push.txt`.
- RPCSX remained stopped after deployment. The post-push battery temperature
  was `27.0 C` and Android thermal status was `0`; the replacement core was not
  launched.

Decision: retain the title-gated fence as the next stability candidate, but do
not call it fixed or faster yet. The next separately cool round may spend one
PID-guarded, screenshot-only route; it must keep the same process alive and the
battle live past the temporal gate. A clean result still needs a later
independent repetition before promotion.

## 2026-07-15 Cold PPU Recompile Route Miss and Cache-Key Narrowing

Status: `invalid-ppu-compilation-route-miss`; the narrowed replacement core is
`host-build-and-deploy-only` and has not been launched.

Single guarded Thor result:

- Core SHA256 under test:
  `15291FA7A30276BB91CB92F06187D57CA1D277F7FA4637D0C8D10A7C33C35EA6`.
- Capture:
  `debug-captures/android-speed-sprint/20260715-181722-thor-input-eternal-sonata-battle-intro-route`.
- The macro exited zero after `209.7s`, but visual review invalidated the entire
  route. Every intended title, field, and battle screenshot still showed the
  `Compiling PPU Modules...` splash. Progress moved from file `71 / 78`, module
  `92 / 94` to file `78 / 78`, module `108 / 140`; gameplay never started.
  There is no field, battle, menu, FPS, frame-pacing, or stability credit.
- The cyan-only battle gate falsely accepted the splash on approach attempt one
  with `7005 / 13488` samples (`51.935%`). Historical real battle frames from
  the two preceding routes each measure `463 / 13488` (`3.433%`), while clean
  field frames measure zero. The zero macro exit was therefore a harness
  false-positive, not evidence that the publication fence fixed the fatal.
- PID `24556` remained the original process and the guest-health logs contained
  no fatal/access-violation/device-lost signature, but those facts cover PPU
  compilation only. All guarded temperatures were `26.0-27.0 C`; RPCSX was
  force-stopped at the scripted end, and no second device run, recording,
  Perfetto trace, or sustained profiler was used.

Cache and harness follow-up:

- The first cache-version bit was title-wide, so it needlessly changed the PPU
  object key for every module compiled under BLUS30161. The bit is now set only
  for a JIT object part whose function range actually contains publisher CIA
  `0x002ac638` or consumer CIA `0x002acc4c`. The runtime fence remains exactly
  title/address-gated, while unaffected firmware and EBOOT objects can reuse
  their prior cache keys.
- The battle classifier now recognizes the compilation splash by combining its
  cyan-heavy left region with the long white center progress bar. Battle
  acceptance also requires cyan coverage at or below `10%`, closing the broad
  blue-background false positive.
- The battle route now performs `check:visual:not-ppu-compilation` immediately
  after its first title screenshot. A cold rebuild still visible after the
  75-second boot wait fails closed before route inputs. The battle gate logs
  both compilation and progress-bar classifications for later audit.
- PowerShell parsing passed. Offline classifier regression passed on five
  retained screenshots: the compilation splash was compile=true/battle=false;
  two real battle frames were compile=false/battle=true; clean field and title
  frames were false for both classifications.

Build and cool deployment proof:

- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  es-fence-narrow-cache-gate -NoLaunch -NoStream -NoFallbackBuild` completed the
  optimized RelWithDebInfo ARM64 build successfully in `71s`; only existing
  deprecation warnings were emitted.
- Replacement ARM64 core SHA256:
  `037F2B4FFC3B6A4EF19282C08904CAB857557D8262B299274E577549A4689A13`.
  Local and app-internal device hashes match. Push record:
  `debug-captures/20260715-182904-es-fence-narrow-cache-gate-dev-core-push/build-push.txt`.
- RPCSX remained stopped after deployment at `27.0 C`, Android thermal status
  `0`, and battery `79%`. The replacement core was not launched.

Decision: retain the runtime publication-fence candidate, the per-object cache
key, and the fail-closed visual gate. Do not claim the fence fixed gameplay
until a later separately cool run reaches real field and battle frames. The
next run may spend one guarded route only; if compilation is still visible at
75 seconds, the new early gate must stop it and the result remains a cache-warm
step rather than gameplay proof.

## 2026-07-15 Publication-Fence First Real Battle Pass

Status: `provisional-first-pass-with-residual-draw-warnings`; this is one clean
route, not a stability promotion.

Single guarded Thor result:

- Core SHA256 under test:
  `037F2B4FFC3B6A4EF19282C08904CAB857557D8262B299274E577549A4689A13`.
  Capture:
  `debug-captures/android-speed-sprint/20260715-183435-thor-input-eternal-sonata-battle-intro-route`.
- The early compilation-screen gate correctly accepted real gameplay
  (`ppu_compilation_screen_present=False`, cyan `0.519%`, progress bar
  `0.814%`). The title was visually clean at `29.99 FPS`; the field was
  visually clean at `27.25 FPS`.
- The first-battle gate passed on its first attempt (`463 / 13488` cyan
  samples, `3.433%`). The tutorial prompt rendered cleanly at `30.00 FPS`.
  Active, temporal, 10-second, and 20-second battle frames remained visually
  clean at `29.90-30.00 FPS`. Character pose and the `Next` marker changed
  between the retained frames, proving that the guest remained live through
  the 20-second checkpoint rather than displaying a stale FPS overlay.
- PID `29973` remained the original RPCSX process. Capture-wide fatal scanning
  found no guest VM/access violation, crash marker, native signal, Vulkan
  device loss, assertion, or verification failure.
- Four retained log occurrences remain warning evidence: draw-command value
  `30b12f20` appeared at emulation times `0:02:41.308` and `0:02:53.074`, and
  values `30b12f20` plus `3e9e0000` appeared at `0:03:15.896`. They did not
  become fatal during this route, but they are pointer/float-like values and
  clean official Windows controls generally contain no unknown draw commands.
  The candidate's two-value warning set is smaller than the prior failing
  routes, but that comparison is not proof that the publication fence fixed
  the race.
- The route took `211.7s`; every guarded battery-temperature sample was exactly
  `27.0 C`, below the `35 C` cutoff. Battery ended near `79%`. RPCSX was
  force-stopped at the scripted end. No second run, screen recording, Perfetto
  trace, or sustained profiler was used.

Fail-closed temporal-liveness follow-up:

- The guarded route now compares the central battle arena between its existing
  temporal, 10-second, and 20-second screenshots. It excludes the FPS overlay,
  left battle meter, bottom command HUD, and Android crash-toast region, and
  fails closed when neither enough changed samples nor enough mean RGB change
  is present. This reuses retained screenshots and adds no work to the device.
- Offline fixtures separated live and invalid states: the current temporal-to-
  10-second pair measured `2.090%` changed samples and mean RGB delta `6.778`;
  the 10-to-20-second pair measured `1.698%` and `2.333`. A prior fatal frozen
  pair measured exactly `0%` and `0`, while the compilation-splash pair
  measured `0.292%` and `0.690` and was also rejected. PowerShell parser and
  whitespace validation passed.
- No runtime source changed, and no replacement core was built or deployed.
  The same hash remains installed on the Thor so the next proof tests an
  identical candidate.

Decision: retain the title-gated publication-fence candidate unchanged. The
next separately cool round may spend one guarded repeat with the same core and
harness. A second independent live route would support a stronger stability
promotion, while residual unknown draw commands must remain monitored even if
the repeat passes.

## 2026-07-15 Publication-Fence Rejection and ARM64 SPU Upstream Candidate

Status: `repeat-live-then-fatal`; the publication fence is rejected and the
replacement ARM64/SPU core is `host-build-and-deploy-only`.

Single guarded Thor repeat:

- Core SHA256 under test:
  `037F2B4FFC3B6A4EF19282C08904CAB857557D8262B299274E577549A4689A13`.
  Capture:
  `debug-captures/android-speed-sprint/20260715-185639-thor-input-eternal-sonata-battle-intro-route`.
- The PPU-compilation gate accepted real gameplay (cyan `0.156%`, progress
  bar `1.466%`). The field rendered cleanly at `28.03 FPS`; the tutorial
  prompt, active battle, temporal frame, and ten-second battle frame were
  visually clean at approximately `30 FPS`. The battle gate passed on attempt
  one (`463 / 13488` cyan samples, `3.433%`).
- The central-arena liveness check passed before the fatal: temporal-to-
  ten-second motion measured `6059 / 63360` changed samples (`9.563%`) and
  mean RGB delta `15.31`. This proves that the repeat reached live battle; it
  does not make the later failure valid performance evidence.
- Unknown draw values reappeared in the established corrupt-stream family:
  `32c7d890`, `30323900`, `80040033`, `001b0001`, `3e21bf94`, `bf7a924b`,
  `3f800000`, `30b12f20`, `3ef10000`, `bea60000`, and `be5b8000`. At emulation
  time `0:03:15.653814`, PPU thread `0x100000c` faulted at CIA `0x002ad588`
  while reading guest address `0x3f80000c`; frozen emulation followed.
- The route ran `200.2s`. Every guarded sample remained exactly `27.0 C`,
  Android thermal status was `0`, and battery remained `79%`. The harness
  force-stopped RPCSX immediately after the fatal. No second device run,
  recording, Perfetto trace, or sustained profiler was used.

Fence rejection and upstream replacement:

- A first live pass followed by this repeat fatal disproves the title-gated
  PPU publication fence as a reliable fix. Its acquire/release fences and
  per-object PPU cache-key bit were removed; they are not retained as hidden
  per-frame overhead. The narrowed PPU invalidation and fail-closed visual and
  temporal harness gates remain.
- Backported upstream RPCS3 `320e8d6`, which replaces LLVM's known long and
  incorrect AArch64 FCGT vector-select sequence with the intended `bsl`
  instruction. This is both a direct ARM64 code-quality improvement and a
  correctness fix, but it has not yet been measured on Thor.
- Backported the compatible portions of upstream `4cc0e4c` and `53d76db`:
  initialize SPU recompiler state, prevent exact-end-of-local-storage block-map
  indexing, and deterministically select only the dominant analyzed jump
  table. These remove undefined behavior and out-of-bounds risks on the SPU
  compile path; they are not yet evidence that Eternal Sonata's PPU command
  corruption is fixed.

Build, deployment, and cache proof:

- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  arm64-spu-upstream-correctness -NoLaunch -NoStream -NoFallbackBuild`
  completed the optimized RelWithDebInfo ARM64 build successfully in `95.6s`;
  only existing deprecation warnings were emitted. Push record:
  `debug-captures/20260715-191359-arm64-spu-upstream-correctness-dev-core-push/build-push.txt`.
- Replacement ARM64 core SHA256:
  `3D30A94B01D797D204453035CCE8A2759DF90E58F2693A3D12F69088F6DAEDC3`.
  `run-as` verified the identical app-internal core hash.
- The old `spu-safe-v1-tane.dat` was moved, not deleted, to
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/codex-cache-backups/20260715-1916-arm64-spu-upstream-correctness/`.
  The next route will therefore compile SPU code with the corrected ARM64
  generator while retaining reusable PPU objects.
- RPCSX remained stopped after deployment and cache backup. The final device
  check reported `27.0 C`, thermal status `0`, and battery `79%`. The new core
  was not launched.

Decision: reject and remove the publication-fence experiment. Retain the
upstream ARM64/SPU fixes as the next candidate, but make no speed or stability
claim until one later, separately cool guarded route rebuilds the SPU cache and
reaches live battle. Do not spend a second device run in this round.

## 2026-07-15 ARM64 SPU Cold-Cache Failure and Official-Stable Profile

Status: `clean-field-and-tutorial-fatal-invalid`; the ARM64/SPU backports are
retained as upstream correctness fixes but are not a stability or speed
promotion. The replacement settings are `profile-deployed-no-launch`.

Single guarded Thor proof:

- Core SHA256 under test:
  `3D30A94B01D797D204453035CCE8A2759DF90E58F2693A3D12F69088F6DAEDC3`.
  Capture:
  `debug-captures/android-speed-sprint/20260715-192032-thor-input-eternal-sonata-battle-intro-route`.
- The deliberately absent SPU cache was rebuilt with the corrected compiler;
  the new `spu-safe-v1-tane.dat` is `383968` bytes. The PPU-compilation visual
  gate accepted real gameplay (cyan `0.052%`, progress bar `1.629%`).
- Retained screenshots are visually clean: loaded field `27.89 FPS`, first
  enemy approach `28.01 FPS`, and first-battle tutorial prompt `30.00 FPS`.
  The first approach frame correctly failed the battle classifier with zero
  cyan samples; the second frame visibly reached the real tutorial UI.
- At emulation time `0:03:00.681622`, the parser reported unknown draw values
  `3e21bf94` and `bf7a924b`, then repeated them at `0:03:01.031602`. At
  `0:03:06.145964`, PPU thread `0x100000c` faulted at CIA `0x002aedd0` while
  reading guest address `0x40`; frozen emulation followed. This is the same
  historical draw-stream family seen in stock Windows and earlier Android
  routes, not an SPU unknown-STOP, native ARM64 signal, or Vulkan device loss.
- The register dump again shows a valid command-buffer cursor with valid-looking
  small command words being consumed as object pointers. This is stream
  desynchronization, not evidence that the clean tutorial image remained live
  after the fatal.
- Cold SPU compilation raised measured peak RSS to `9479 MB`, then it fell to
  `7053 MB` near the fatal. Treat this cold-cache behavior as `max-first` until
  Base/Pro memory pressure is measured; the next proof is warm-cache.
- The route ran `189.7s`. Thermal samples were `27.0 C`, rising only to
  `28.0 C` near the end, under the `35 C` cutoff. Battery ended at `78%`,
  Android thermal status was `0`, and the failure path force-stopped RPCSX.
  No second route, recording, Perfetto trace, or sustained profiler was used.

Candidate classification:

- The backported AArch64 FCGT `bsl`, initialized SPU compiler state, and SPU
  analyzer bounds fixes compiled and executed far enough to rebuild the cache,
  load the field, and enter the tutorial. The observed fatal predates those
  changes, so they remain in source; this run still supplies no measurable
  speed or stability credit.
- The prior Rocknix-mirror config differed from the clean current-upstream
  first-battle control in four stability-sensitive settings: `As Host` versus
  `Usleep Only`, low versus high shader precision, inaccurate versus accurate
  ZCULL statistics, and driver wake delay `1` versus `0`. The current-upstream
  control survived active battle for about `34s` with no unknown draw or fatal.

Official-stable profile follow-up:

- Added `OfficialStable` to `tools/push_eternal_sonata_thor_profile.ps1` and
  made it the safe default instead of the known-slow busy-wait scheduler
  profile. The tool now requires unambiguous ADB device selection and accepts
  explicit `-Serial`; all ADB failures are checked.
- The built-in BLUS30161 Thor override and `OfficialStable` both use OS
  scheduling, accurate SPU reservations, SPU verification, `Usleep Only`, high
  shader precision, WCB, accurate ZCULL statistics, no relaxed ZCULL, no
  multithreaded RSX, and driver wake delay `0`. The 30-FPS cap and 3-GB Vulkan
  allocation limit remain.
- Applied the profile to serial `c3ca0370` with `-StopApp` and no launch. The
  previous device config is preserved at
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/config/custom_configs/config_BLUS30161.pre-thor-speed-20260715-193402.yml`.
  The installed profile header is `RPCSX_THOR_OFFICIAL_STABLE_PROFILE`.
- PowerShell parsing and whitespace validation passed. Host-only
  `./gradlew.bat :app:compileDebugKotlin --console=plain` completed with
  `BUILD SUCCESSFUL` in `15s`. Final device state was stopped, `27.0 C`,
  thermal status `0`, and battery `78%`.

Decision: keep the upstream ARM64/SPU fixes but do not promote them from this
failed route. Use one later, separately cool warm-cache route to isolate the
official-stable profile. It must contain no unknown draw commands, preserve
field/tutorial/active-battle visuals, and pass the temporal liveness gate
before any stability or performance claim. Do not run it in this round.

## 2026-07-15 Official-Stable Rejection and RCHCNT Fallback Candidate

Status: `warm-cache-tutorial-fatal-invalid`; the official-stable settings are
rejected and restored. The exact Eternal Sonata RCHCNT fallback is
`built-and-deployed-no-launch`.

Single guarded Thor proof:

- Core SHA256 under test:
  `3D30A94B01D797D204453035CCE8A2759DF90E58F2693A3D12F69088F6DAEDC3`.
  Capture:
  `debug-captures/android-speed-sprint/20260715-194013-thor-input-eternal-sonata-battle-intro-route`.
- The warm SPU cache was `383968` bytes. The PPU-compilation gate accepted
  real gameplay (cyan `0.326%`, progress bar `1.629%`). The field screenshot
  was visually clean at `27.01 FPS`, below the preceding `27.89` and `28.03`
  class results. The first-battle tutorial became visible at `29.68 FPS`, but
  already contained the Android crash toast and is invalid performance data.
- At emulation time `0:02:43.280765`, unknown draw values `32c7d930`,
  `30323900`, `80040033`, `001b0001`, and `00000233` appeared. Values
  `3e21bf94` and `bf7a924b` followed at `0:02:44.057065`. At
  `0:02:46.865930`, PPU thread `0x100000c` faulted at CIA `0x002aedd0` while
  reading guest address `0x40`; frozen emulation followed.
- The register state matches the prior fatal family: `r3=4`, `r4=0x48`, `r10`
  points to those small command words, and `r31` remains a valid stream cursor
  followed by words `0` and `0x43`. This is deterministic guest draw-stream
  desynchronization, not a native ARM64 crash, SPU unknown STOP, or Vulkan
  device loss.
- Warm-cache peak RSS still reached `9412 MB` before falling to `7285 MB`, so
  the memory spike is not exclusively cold SPU compilation. Retain the
  Max-first classification until Base/Pro memory pressure is measured.
- The route ran `175.3s`. Every guarded battery-temperature sample was exactly
  `27.0 C`; battery ended at `78%` and Android thermal status was `0`. The
  failure path force-stopped RPCSX. No second route, recording, Perfetto trace,
  or sustained profiler was used.

Profile rejection and restoration:

- Matching the Windows control's timer, shader-precision, ZCULL, and driver
  wake-delay settings neither prevented the identical fatal nor improved the
  field result. `OfficialStable` was removed from the profile tool and from the
  built-in BLUS30161 override. The tool now defaults to `OfficialMinimal` while
  retaining its explicit-serial and checked-ADB safety improvements.
- Restored the pre-test device config from
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/config/custom_configs/config_BLUS30161.pre-thor-speed-20260715-193402.yml`.
  The current header is `RPCSX_THOR_ROCKNIX_MIRROR_PROFILE`, with `As Host`,
  low shader precision, inaccurate ZCULL statistics, and driver wake delay
  `1`. The app remained stopped after restoration.

Narrow RCHCNT fallback candidate:

- Fresh Android logs identify only one completed special SPU channel loop:
  CellSpursKernel function `0xa7c-7PiXnkUPiv7ZdGvUkndsHKRu6ZNZ`, with
  `read_pc=0xa7c`. The current core already contains upstream's RCHCNT loop fix,
  yet the draw stream still corrupts. The next isolation therefore declines
  `inst_attr::rchcnt_loop` only when all four gates match: Android,
  `BLUS30161`, entry/read PC `0xa7c`, and the exact function hash. All other
  titles and functions retain the optimized path and normal channel semantics
  handle this one loop.
- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  es-rchcnt-loop-disable -NoLaunch -NoStream -NoFallbackBuild` completed the
  optimized RelWithDebInfo ARM64 build and deploy successfully in `65.7s`;
  only existing warnings were emitted. Push record:
  `debug-captures/20260715-194843-es-rchcnt-loop-disable-dev-core-push/build-push.txt`.
- Replacement core SHA256:
  `6B97B0964C57A0AEFD51CF9655528245FDCCA4515EA9137041564E14BA0CD47E`.
  The previous analyzed SPU cache was moved, not deleted, to
  `/storage/emulated/0/Android/data/net.rpcsx.easy/files/cache/codex-cache-backups/20260715-195012-es-rchcnt-loop-disable/spu-safe-v1-tane.dat`.
  The next proof must rebuild the cache to exercise the fallback.
- The replacement core was not launched. Final verification left RPCSX
  stopped at `27.0 C`, thermal status `0`, and battery `78%`.

Decision: reject the official-stable settings and restore the prior profile.
Retain the exact RCHCNT fallback only as an unproven stability candidate. Spend
one later, separately cool guarded route to confirm that the skip notice is
logged, the cache is rebuilt, battle remains live, and no unknown draw or
fatal appears. Do not run it in this round.

## 2026-07-15 RCHCNT Fallback First Proof

Status: `live-battle-no-fatal-with-unknown-draw`; positive stability signal,
but not a stability or speed promotion.

Single guarded cold-cache Thor proof:

- Core SHA256:
  `6B97B0964C57A0AEFD51CF9655528245FDCCA4515EA9137041564E14BA0CD47E`.
  Capture:
  `debug-captures/android-speed-sprint/20260715-195442-thor-input-eternal-sonata-battle-intro-route`.
- The old SPU cache was absent at boot. The full guest log proves the exact
  gate activated at emulation time `0:00:28.440330` for
  `read_pc=0xa7c`, entry `0xa7c`, and function hash
  `7PiXnkUPiv7ZdGvUkndsHKRu6ZNZ`. The rebuilt `spu-safe-v1-tane.dat` is
  `382116` bytes, smaller than the preceding optimized-loop cache as expected.
- The PPU-compilation gate accepted real title output (cyan `0.126%`, progress
  bar `1.303%`). The loaded field was visually clean at `25.82 FPS`; the
  tutorial prompt was clean at `29.01 FPS`; active battle and the retained
  10-second and 20-second frames were clean at `30.00`, `30.01`, and
  `30.00 FPS`. The field sample is lower than the preceding 27-FPS class and
  supplies no speed credit because this was a cold-cache stability proof.
- The first approach frame correctly failed the battle classifier with zero
  cyan samples; attempt two passed with `463 / 13488` samples (`3.433%`).
  Temporal liveness passed twice: temporal-to-10-second measured
  `4732 / 63360` changed samples (`7.468%`) with mean RGB delta `13.443`, and
  10-to-20-second measured `1214 / 63360` (`1.916%`) with mean delta `6.466`.
- No VM access violation, frozen emulation, unknown STOP, native signal,
  Vulkan device loss, or verification failure appeared through the completed
  route. This is the first fallback run to remain live through the full
  20-second battle window, extending past the two preceding early fatal runs.
- The result still fails a strict stability promotion. Six unknown draw rows
  remained: `3f800000` at `0:03:08.128399`, `30b12f20` at
  `0:03:08.782748`, `3f800000` at `0:03:17.600492` and `0:03:19.860770`,
  then `30b12f20` plus `be9e8000` at `0:03:27.964890..4930`. The severe
  pointer-like pre-fatal set from the prior two runs did not appear, but one
  run cannot establish causality or long-session stability.
- Cold-cache peak RSS reached `9465 MB`, then fell near `7.1 GB`. Continue to
  label this memory behavior `max-first` / `pro-max` until Base/Pro pressure is
  measured. The route lasted `227.3s`; every thermal sample was exactly
  `27.0 C`. It ended at battery `77%`, thermal status `0`, with RPCSX stopped.
  No second route, recording, Perfetto trace, or sustained profiler was used.

Proof-harness hardening:

- `tools/thor_input_macro.ps1` now treats any unknown draw command as a
  fail-closed error for `eternal-sonata-battle-intro-route`, preserves the
  offending rows, and immediately force-stops RPCSX. `-AllowUnknownDraw` is an
  explicit diagnostic-only override; other profiles retain record-only
  behavior. This prevents a live-looking 30-FPS battle from being mislabeled
  stable while the known corrupt-stream precursor is present.

Decision: retain the exact RCHCNT fallback for one warm-cache repeat because
it eliminated the immediate fatal and kept battle visibly live through the
full window. Do not promote it yet: unknown draw commands remain and the cold
field sample is slower. The next separately cool run must pass the new
fail-closed draw-stream gate before any stability claim; only then compare a
matched warm-cache field FPS sample. Do not run a second route in this round.

## 2026-07-15 Offline Handoff Trace and Upstream Semaphore Optimization

Status: `host-build-pass`; generic synchronization-overhead improvement, no
device run and no speed or stability promotion.

- Ghidra now proves the guest command buffers are protected by a synchronous
  two-semaphore handshake. After publishing, the producer acquires the
  completion token, wakes the parser, waits for parser completion, and restores
  the token before returning. The consumer waits for work and posts completion
  at the stream terminator. This rules out producer/consumer buffer overlap and
  rejects another generic Android publication fence.
- Official upstream was refreshed through `1269ebf`. Backported `537ad39`,
  which makes an already-registered host semaphore waiter skip a redundant
  no-op atomic RMW/CAS when no signal exists. Guest semaphore ordering, wakeups,
  and values are unchanged.
- `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` completed successfully in `1m 10s`. Host-built core SHA256:
  `A599F9BC1A6DCD2C718ED17A6DE76DE4E47F0E2347B0C9E9C38F972E48144681`.
- The new core was not deployed or launched. Final read-only verification found
  RPCSX stopped at `27.0 C`, battery `77%`, and Android thermal status `0`; the
  installed exact-RCHCNT candidate remains unchanged.

Decision: keep the upstream host semaphore optimization as a low-risk generic
performance improvement. Retain the exact RCHCNT fallback as provisional and
keep the fail-closed unknown-draw gate. A later, separately cool warm-cache
battle repeat is still required before either stability or speed credit.

## 2026-07-15 RCHCNT Warm Repeat Failure and Revert

Status: `fail-closed-unknown-draw`; exact RCHCNT fallback rejected and removed.

Single guarded warm-cache Thor repeat:

- Core SHA256 under test:
  `A599F9BC1A6DCD2C718ED17A6DE76DE4E47F0E2347B0C9E9C38F972E48144681`.
  This combined the provisional exact RCHCNT fallback with the retained
  upstream host-semaphore optimization. Capture:
  `debug-captures/android-speed-sprint/20260715-202904-thor-input-eternal-sonata-battle-intro-route`.
- The full guest log confirmed the exact RCHCNT exception activated at
  emulation time `0:00:32.243886` for `read_pc=0xa7c`, entry `0xa7c`, and
  function hash `7PiXnkUPiv7ZdGvUkndsHKRu6ZNZ`. No cache was removed between
  the preceding cold proof and this required repeat.
- The PPU-compilation visual gate accepted title output (`cyan=0.067%`, white
  progress bar `1.954%`). Retained screenshots are visually clean: loaded
  field `27.78 FPS` and the real first-battle tutorial prompt `30.00 FPS`.
  The route reached the battle UI on its first bounded approach.
- At emulation time `0:02:48.709891`, the parser reported unknown draw command
  `30b12f20`. This is the same float-like corrupt-stream precursor seen in the
  prior fallback proof. The new fail-closed gate immediately force-stopped
  RPCSX at `battle-approach-1`; the route did not continue into active combat.
  No VM access violation, frozen emulation, unknown STOP, native restart, or
  Vulkan device loss occurred before the stop.
- Performance-sensor RAM peaked at `11229 MB` and had fallen to `9098 MB` at
  the last sample. This exceeds the earlier roughly `9.5 GB` peaks and
  reinforces the `max-first` / `pro-max` memory classification. The run lasted
  `175.7s`; every guarded temperature sample was `27.0 C`.

Revert and deployment:

- Removed the Android/title/hash-specific RCHCNT skip from
  `SPUCommonRecompiler.cpp`, restoring normal upstream RCHCNT-loop analysis for
  every title. The generic upstream host-semaphore no-op-CAS optimization is
  retained, but receives no FPS or stability credit from this failed route.
- `tools/build_push_thor_core.ps1 -Serial c3ca0370 -Label
  es-rchcnt-fallback-revert -NoLaunch -NoStream -NoFallbackBuild` completed the
  optimized RelWithDebInfo ARM64 build successfully in `1m 1s` and deployed
  the result without launching. Core SHA256:
  `F0B66982FDF481F42E0C82AA59F5EB8D3DAA99BD9F4F8904E1FA50CD3EBE8F3B`.
- Final read-only verification found RPCSX stopped, battery `77%`, temperature
  `27.0 C`, and Android thermal status `0`.

Decision: reject the exact RCHCNT fallback. Its first cold proof remained live
but already contained unknown commands, and its required warm repeat failed at
the first strict guest-health check with the same precursor. Do not rerun or
reintroduce it. Keep the fail-closed draw-stream gate and pursue a different
root-cause lane before another separately cool device proof.

## 2026-07-15 Offline Draw-Stream Handoff Verifier

Status: `host-build-pass`; verify-only instrumentation, default off, no device
run and no speed or stability promotion.

- Added a separate `debug.rpcsx.thor.es_draw_stream_probe=verify` gate with
  host equivalent `RPCSX_THOR_ES_DRAW_STREAM_PROBE=verify`. Unknown values and
  the default state are disabled.
- The probe is exact-title and exact-call-site scoped. It recognizes the
  producer work post at `CIA=0x0031c1bc`, `LR=0x002ac7f0` and the consumer work
  wait return at `CIA=0x0031c18c`, `LR=0x002afd08`. Ghidra-proven preserved
  registers reconstruct the command object from producer `r29` and consumer
  `r30`; the parser cursor/object use `r31`/`r22` only on an actual
  `unknown draw command` TTY message.
- Immediately before the producer semaphore post can wake the parser, the
  verifier copies the full selected `0x180000`-byte published buffer. After the
  consumer wait succeeds and before parsing begins, it compares every byte with
  the snapshot. A mismatch records the first changed byte plus producer/live
  words. A later parser fault records the exact producer snapshot word, live
  word, surrounding five-word producer context, and whether the handoff compare
  had already matched.
- Normal emulation behavior is unchanged: the probe never alters guest memory,
  semaphore state, parser state, or return values. Its allocation/copy/compare
  work exists only when explicitly enabled. The disabled semaphore path uses an
  inlined false branch and never enters the full verifier.
- Optimized ARM64 validation command
  `./gradlew.bat ":app:buildCMakeRelWithDebInfo[arm64-v8a]" --no-daemon
  --console=plain` passed in `1m 9s`. Host-built core SHA256:
  `EB88FF4373292B400A0617E7396EC076010674CCF6FE2044875B99716C684785`.
- The core was not deployed or launched. The stopped Thor and installed core
  `F0B66982FDF481F42E0C82AA59F5EB8D3DAA99BD9F4F8904E1FA50CD3EBE8F3B`
  were left untouched.

Decision: retain this verifier off by default. One later short, separately cool
route can now answer the next root-cause question directly: if the consumer
handoff matches and the TTY fault word also matches the producer snapshot, the
bad word was already published; if the handoff differs, the first changed byte
identifies an intervening memory mutation. This instrumentation earns no FPS
credit and must not be enabled for normal benchmarks.

## 2026-07-16 Atomic Publication Counterproof And PPU Isolation Build

Status: `device-fail-closed`; next candidate is host-build-only and default off.

- Exact core `884FD8B36AB257CFDDDB910E683D185A6B2DFA02C4C5753DF7AA0FD64D9D3DF8`
  ran once in `20260716-022914-thor-input-eternal-sonata-battle-intro-route`.
  Correct field/tutorial visuals measured `27.12/28.88 FPS` and no retained
  frame was black, but unknown draw `0x30b12f20` appeared at emulated
  `0:02:40.030250`; the familiar later corrupt-word burst returned.
- No VM/native/restart/Vulkan/LLVM fatal preceded the controlled stop. The
  route stayed at `24 C`, thermal status `0`, ended stopped, and received no
  second device run. The upstream-aligned atomic `PUTLLC` patch remains a
  correctness improvement, not a demonstrated stability or speed improvement.
- Ghidra mapped the exact PPU command publisher/parser ranges to
  `[0x002ac618,0x002ac65c)` and `[0x002acbc8,0x002afce0)`. A new BLUS30161-only
  property can interpret `publisher`, `parser`, or `both` while leaving normal
  PPU LLVM execution as the default. Independent cache bits prevent mode
  collisions within their shared EBOOT object part.
- The ARM64 RelWithDebInfo core built and linked successfully at
  `1,349,614,432` bytes, SHA256
  `D33AC093C9516653687F8ED512931AB1B77D03B5E9B7B6A74BA9C271FDF1BC21`.
  It was not deployed or launched. One later cool guarded `both` route is the
  next isolation test; this build currently earns no performance credit.

## 2026-07-16 PPU Both Cold-Cache Readiness Failure

Status: `route-tooling`; runtime hypothesis remains untested.

- Exact core `D33AC093C9516653687F8ED512931AB1B77D03B5E9B7B6A74BA9C271FDF1BC21`
  was deployed without rebuilding and launched once with only PPU interpreter
  mode `both`. The log confirmed both exact mapped ranges enabled.
- The `75s` screenshot still showed PPU compilation at module `60/62` with
  about `24s` remaining. The wrapper failed closed before route input, so no
  field, battle, flicker, stability, or FPS conclusion can be drawn.
- Temperature remained `23 C`, thermal status `0`, no fatal signature appeared,
  cleanup stopped RPCSX and reset the property, and no second route ran.
- The battle harness now polls actual compilation readiness for a bounded
  interval with PID/thermal checks and automatically retains full guest logs on
  failures. Host detection replay and PowerShell parsing pass. A later single
  cool `both` route is still required; this attempt earns no speed credit.
