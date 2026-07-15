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
