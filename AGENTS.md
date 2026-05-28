# RPCSX Thor Agent Notes

This file is the compact operating contract. It is not an experiment ledger.
Put dated run details in `debug-experiments/`, not here.

## Communication

- Be concise, factual, and specific.
- State what changed, what was verified, and what remains.
- Do not use hype, filler, or long historical summaries.

## Git

- Work on `master` only for this repo.
- Remote push target: `git@github.com:noeldvictor/rpcsx-ui-android-thor.git`.
- Commit and push completed work to `origin master`.
- Do not create feature branches, PR branches, or extra RPCSX forks unless the user explicitly asks.
- Do not commit game data, firmware, generated builds, Gradle caches, `.cxx`, runtime caches, APKs, or capture blobs.

## Source Layout

- Vendored RPCSX core: `app/src/main/cpp/rpcsx`.
- Android JNI full-core bridge: `app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp`.
- Lightweight loader wrapper: `app/src/main/cpp/native-lib.cpp`.
- Upstream RPCS3 comparison checkout: `C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream`.
- Refresh vendored core with `tools/sync_rpcsx_core.ps1`.
- Hydrate core deps with `tools/hydrate_rpcsx_core_deps.ps1`.
- Normal debug build: `.\gradlew.bat :app:assembleDebug`.
- Fast native-core hot swap: `.\tools\build_push_thor_core.ps1 -Label NAME`.
- Reset hot swap: `.\tools\build_push_thor_core.ps1 -ResetToBundled`.

## PS3 Sprint Gate

- Active goal: prove a stable Windows-only Eternal Sonata `BLUS30161` 200% or better moving-gameplay result with correct field, title Options/menu, and first-battle visuals.
- Until that Windows gate is met, do not run Android, ADB, Thor installs, or Thor captures for this lane.
- Keep RPCS3 gameplay on screen 1 with `-WindowsGameScreen 1`.
- Use repo-local skills only: `codex-goal-loop`, `ps3-debug-knowledge`, `ps3-speed-proof-gate`, `ps3-rsx-experiment-gate`, and `ps3-continual-harness-refiner`.
- Always start by checking for an active meaningful run/edit. Do not duplicate live work.
- Newest failed visual/log/window/route evidence overrides older opportunities.

## Sprint Workflow

1. Read this file, the relevant `.agents/skills/*/SKILL.md`, and the narrowest `debug-experiments/` ledger.
2. Run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8`.
3. Take one concrete Windows-only step: route repair, boundary bisection, harness fix, analysis, or one gated experiment.
4. Verify screenshots, fatal logs, host grade, and counters.
5. Classify honestly: `speed-win`, `windows-micro-win`, `stackable-cpu-pressure`, `gpu-migration-credit`, `valid-field-triage`, `route-tooling`, `failed`, `stack-regression`, `parked`, or `not-comparable`.
6. Update the narrowest ledger before stopping.
7. Commit and push after each completed work round.

## Current PS3 State

- Current route base: Down160 title route, `PATH_TO_TENUTO_PRESENT` gate, strong post-load dismiss, Path-to-Tenuto field.
- Current movement bracket: `left1317` is clean single-axis movement, `left1318` is fatal/corrupt, and `left1317-down120` is failed.
- Latest refreshed lower proof: `20260527-221838-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` re-proved the route and left movement clean after the no-movement load-stability control.
- Historical left-only ladder already includes clean `left1312`, fatal `left1331`, fatal `left1321`, clean `left1316`, fatal `left1318`, and clean `left1317`; do not loop back through those midpoint proofs from a fresh `left1275`.
- Clean lower proof: `20260527-202051-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-longgate-diagnostic-windows`.
- Fatal upper proof: `20260527-181934-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1318-longgate-diagnostic-windows`.
- `20260527-210215-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1317-reproof-after-down120-fatal-windows` re-proved plain `left1317` as clean after the `down120` fatal.
- `left1317` remains route/movement evidence only. It is not first-battle proof, speed proof, GPU migration, or 200%.
- `left1318` has VM/access/corrupt-field evidence. Treat it as failed even if byte-size visual triage looks field-like.
- Latest no-movement load-stability reproof `20260527-215837-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` reached clean Path-to-Tenuto field at `195s` and stayed field-like through late checks.
- `left1316-down120` remains a loading-only failure. Movement was not tested; do not repeat that combo.
- `left1316-down60` first aborted on `Save File 01 / Debug Save / Prologue`; the title-to-Load repair then restored `PATH_TO_TENUTO_PRESENT`.
- Latest repaired `left1316-down60` reached clean Path-to-Tenuto field, but RPCS3 lost the window/process after `ls_left:1316`; `down60` was not verified.
- Backed-off `left1275-down60` then aborted before slot load on `Save File 01 / Debug Save / Prologue`; movement was not tested.
- This is route-tooling failure only, not movement, speed, GPU migration, or 200% evidence. Next expected action is save-list inventory with no slot `Cross`.

## Banked Findings

- `0x25cc bodyfast` is banked only as stackable CPU-pressure reduction: RPCS3 process CPU `42.60%` to `37.10%` (`-5.50 pp`, `-12.91%`) on clean capped BattleRoute repeat. It is not an FPS win, GPU migration, or 200% candidate.
- Final bodyfast plus RSX-local stack is visually compatible on the capped TopSlot BattleRoute, but it remains around `120 FPS` and reports `0 B` promoted CPU/SPU-to-GPU replacement. Do not keep stacking RSX toggles or rerun the auditor.
- RSX-local accounting is useful but separate from CPU/SPU-to-GPU migration. Current promoted CPU/SPU-to-GPU credit remains `0 B`.
- 0x25cc descriptor/shadow verifier has clean field and Options coverage with zero mismatches and overflow `0`; first-battle verifier attempts hit fatal/corrupt evidence. Treat as verifier coverage only.
- Broad SPU-to-GPU compute offload remains parked unless a candidate has stable batching, low readback pressure, and explicit correctness gates.

## Speed Claim Rules

- Never claim speed from a route miss, wrong scene, black/corrupt visuals, crash overlay, fatal log, lost window, mismatched host grade, or different config/cache state.
- CPU-pressure reductions are useful and bankable, but they do not satisfy the 200% gate.
- `gpu-migration-credit` requires real CPU/SPU/PPU work moved toward GPU or kept GPU-resident, clean visuals, rollback, and counters.
- Do not add small wins arithmetically. Only a measured combined run can be called an aggregate win.
- Field proof, Options/menu proof, and first-battle proof are all required before promotion.

## Windows Lab

- Use `tools/windows_rpcs3_lab.ps1` and `tools/eternal_sonata_speed_sprint.ps1`; do not launch RPCS3 manually.
- Keep screenshots enabled for serious route/perf work.
- Use host contention output. Compare performance only across matching host grades.
- `iso/` is ignored and is the only local place for legally owned test content.
- Official config DB cache path: `rpcs3-upstream\build-msvc\bin\GuiConfigs\config_database.dat`.

## Android And Thor

- Android/Thor work is dormant for the PS3 200% Windows gate unless the user explicitly reopens it.
- Active proof device when reopened: AYN Thor Max, Snapdragon 8 Gen 2 / Adreno 740, board `kalama`.
- Base/Pro/Max share the target CPU/GPU behavior; mark memory-heavy experiments `pro-max` or `max-only`.
- Thor Lite is Snapdragon 865 / Adreno 650 and is not the PS3 performance target.
- Heavy Thor affinity mask is CPUs `3-7`, mask `0xF8`.
- Do not use ARM64 ASMJIT SPU. ARM64 SPU should use LLVM.
- Do not reintroduce `Use LLVM CPU = cortex-a34`.
- Use `cortex-a78` fallback unless a proven better ARM64 target exists.
- Do not assume SVE on Snapdragon 8 Gen 2. Gate NEON, DOTPROD, I8MM, BF16, SVE, and SVE2 from actual feature reports.

## Native Home Menu

- Android already opens the native RPCSX Home Menu through `_rpcsx_openHomeMenu`.
- Do not build a separate Compose OSD unless explicitly requested.
- Home Menu source: `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/HomeMenu/`.
- Localized IDs: `app/src/main/cpp/rpcsx/rpcs3/Emu/localized_string_id.h`.
- Perf overlay: `app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/overlay_perf_metrics.cpp`.
- Current menu should include Resume, Cheats, Fast Forward 2x, Show FPS, Settings, Trophies, Screenshot, Recording, SaveState, Restart, and Exit.
- Fast Forward 2x changes `Core -> Clocks scale` to `200`; it is not a frame-limit uncap.

## Cheats

- Offline single-player cheats only.
- Do not bypass DRM, anti-cheat, or online protections.
- Bundled cheat assets: `app/src/main/assets/cheats`.
- SQLite DB: `app/src/main/assets/cheats/cheats.db`.
- Rebuild DB after cheat asset changes: `python tools/build_cheat_db.py`.
- RPCS3 patch entries can install when they include PPU hashes.
- AoB cheats are risky until native byte validation/scanning exists.
- Current fixture: Odin Sphere Leifthrasir `BLUS31601`.

## Recommended Settings And Cache

- Bundled config DB: `app/src/main/assets/config/config_database.dat`.
- Source endpoint: `https://api.rpcs3.net/config/?api=v1`.
- Android manager: `app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt`.
- Managed per-game configs use `config/custom_configs/config_TITLEID.yml` with `# RPCSX_THOR_AUTO_SETTINGS`.
- Never overwrite user custom configs without the managed header.
- Cache status: `app/src/main/java/net/rpcsx/performance/GameCacheRepository.kt`.
- Cache storage: `app/src/main/java/net/rpcsx/performance/CacheStorageManager.kt`.
- Core cache root remains `RPCSX.rootDirectory/cache/cache`; SD-card selection uses an app-owned symlink.
- PPU cache hook: `_rpcsx_preparePpuCache`, surfaced through `RPCSX.supportsPpuCachePreparation()` and `RPCSX.preparePpuCache(...)`.

## Durable Memory

- Current detailed sprint ledger: `debug-experiments/20260525-reservation-loop-branchstate-battle-route-worklog.md`.
- Current refiner: `tools/ps3_harness_refiner.ps1`.
- Current refiner skill: `.agents/skills/ps3-continual-harness-refiner/SKILL.md`.
- Add new dated facts to the ledger. Update this file only for standing rules, current state, or repeated gotchas.
