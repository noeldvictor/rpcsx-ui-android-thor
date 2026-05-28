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
- Latest no-movement load-stability reproof `20260528-004219-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, and stayed field-like through very-late checks.
- `left1316-down120` remains a loading-only failure. Movement was not tested; do not repeat that combo.
- `left1316-down60` first aborted on `Save File 01 / Debug Save / Prologue`; the title-to-Load repair then restored `PATH_TO_TENUTO_PRESENT`.
- Latest repaired `left1316-down60` reached clean Path-to-Tenuto field, but RPCS3 lost the window/process after `ls_left:1316`; `down60` was not verified.
- Backed-off `left1275-down60` then aborted before slot load on `Save File 01 / Debug Save / Prologue`; movement was not tested.
- Latest save-list inventory shows the initial Load-list row is `Save File 01 / Path to Tenuto`; later `Down` inputs move the cursor onto lower rows where the Path preview can stay stale over empty slots.
- The repaired no-movement route base is `valid-field-triage` only, not movement, speed, GPU migration, first-battle, or 200% evidence. Next expected action is the same strongdismiss600 base with `ls_left:1275` and immediate/late screenshots.
- Latest `left1275` rerun `20260528-010220-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` aborted before slot `Cross`: all `16` load-target gate frames were black-overlay `UNKNOWN_LOAD_TARGET`; movement was not tested. Next expected action is a target-only Path-to-Tenuto reproof before any movement or speed work.
- Latest target-only reproof `20260528-012228-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-target-reproof-after-left1275-blackgate-windows` aborted before slot `Cross` on `DEBUG_SAVE_PROLOGUE_PRESENT`; next expected action is a polling load-target-gated route repair that requires `PATH_TO_TENUTO_PRESENT` before continuing.
- Latest polling repair `20260528-014240-cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows-windows` also aborted before slot `Cross` on `DEBUG_SAVE_PROLOGUE_PRESENT`, now with damaged-save markers; movement was not tested. Continue route repair only.
- Latest save-list inventory `20260528-020512-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-save-list-inventory-after-pregate-debugsave-windows` re-proved the initial Load-list row is `Save File 01 / Path to Tenuto`; `Down` moves the cursor onto lower empty rows while the Path preview remains stale. Next expected action is no-movement long-gate proof from the initial row, without save-list normalization.
- Latest no-movement reproof `20260528-022230-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` aborted before slot `Cross`: all `16` load-target frames were black-overlay `UNKNOWN_LOAD_TARGET`; no slot, field, or movement was tested. Next expected action is the title-to-Load pre-gate black diagnostic with timed screenshots.
- Latest title-to-Load pre-gate diagnostic `20260528-024313-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-titleload-pregate-black-diagnostic-windows` selected `LOAD`, then settled on lower `Save File 05 / Path to Tenuto` with damaged-save rows above it. The gate reported `DAMAGED_SAVE_TARGET`; no slot, field, movement, speed, or GPU credit exists. Next expected action is only the stable Load-list Up-repair target diagnostic.
- Latest Load-list Up-repair target diagnostic `20260528-030231-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-loadlist-uprepair-target-diagnostic-windows` restored top-row `Save File 01 / Path to Tenuto`; gate passed `PATH_TO_TENUTO_PRESENT` with zero lower-row cursor and damaged-save markers. This is target repair only; next action is no-movement stability before any movement, battle, HLE, RSX, GPU, or speed work.
- Latest no-movement stability proof `20260528-032238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, and stayed field-like through `286s`; host contention was high/moderate, so it is route proof only.
- Latest `left1275` rerun `20260528-034311-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT` but stayed on `Now Loading...` through immediate, late, and `260s+` screenshots. Visual gate failed `NO_FIELD_LIKE_SCREENSHOT`; fatal/log scan was clean; no movement, speed, GPU, first-battle, or 200% credit exists.
- Latest no-movement reproof `20260528-040209-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows` passed `PATH_TO_TENUTO_PRESENT`, reached clean Path-to-Tenuto field at `195s`, stayed field-like through `286s`, and had clean host contention. It is route-base proof only.
- Latest `left1275` retry `20260528-042238-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-left1275-longgate-diagnostic-windows` reached field and took immediate/late screenshots, but RPCS3 reported a fatal VM access violation at `0x002aedd0` reading `0x40`; screenshots show crash overlay/corrupt field. It is `failed-fatal-log`, not movement, speed, GPU, first-battle, or 200%.
- Latest loader-control `20260528-044508-cpu4-loader-control-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `10` screenshots field-like through `190s`, `0` invalid after first field-like, empty stderr/stdout, and no targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1477` candidate/dynamic records, `1606` wait records, `83740` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `318`. Treat it as `valid-field-triage` and route-tooling only.
- The loader-control wrapper stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200` route proof `20260528-050402-cpu4-loader-control-left200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `14` screenshots field-like through `200s`, `0` invalid after first field-like, manual pre/post-movement field screenshots clean, empty stderr/stdout, and no targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1597` candidate/dynamic records, `1733` wait records, `90899` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `807`. Treat it as `valid-field-triage` plus small movement route-tooling only.
- The `left200` wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200x2` attempt `20260528-052421-cpu4-loader-control-left200x2-visualgate-windows-windows` failed `CleanAfterField`: `16` screenshots were `cutscene-or-nonfield-small-png`, first field-like was none, manual frames showed blue/starry non-field output, and no Path-to-Tenuto field appeared. Stderr/stdout were empty and targeted fatal scan found no real crash/access/device-lost/assertion/verification hit. Reservation-loop verify logged `1765` candidate/dynamic records, `1841` wait records, `106734` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `539`; counters are invalid for promotion because visuals failed.
- The `left200x2` wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest `left200x2` confirmation `20260528-054511-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `16` screenshots field-like through `210s`, `0` invalid after first field-like, manual pre/post-second-pulse field screenshots clean, empty stderr/stdout, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1573` candidate/dynamic records, `1695` wait records, `88724` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `212`. Treat it as `valid-field-triage` plus route/movement tooling only.
- The `left200x2` confirmation wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest diagonal micro-pulse proof `20260528-060335-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `18` screenshots field-like through `220s`, `0` invalid after first field-like, manual pre/diag/post-diag field screenshots clean, empty stderr/stdout, clean host summary, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `1766` candidate/dynamic records, `1893` wait records, `100595` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `710`. Treat it as `valid-field-triage` plus route/movement tooling only.
- The diagonal micro-pulse wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then visual gate and refiner were run manually against the finished artifact. No emulator process remained active.
- Latest reservation-loop Options proof `20260528-062448-cpu4-reservation-loop-options-fastselect-proof-windows` reached the full title Options page with `screenshot-0077s-options-candidate.png`, stayed there through `screenshot-0130s.png`, had empty stderr/stdout, and no real targeted fatal/access/device-lost/assertion/verification log hit. Reservation-loop verify logged `975` candidate/dynamic records, `1063` wait records, `51726` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `390`. Treat it as `valid-options-triage` only.
- The Options proof wrapper also stalled during postrun log analysis after RPCS3 had exited; the wrapper was killed, then screenshots, logs, counters, and refiner were checked manually. No emulator process remained active.
- `tools/ps3_harness_refiner.ps1` now recognizes `reservation-loop-options-fastselect-proof` as valid Options proof instead of wrong-window noise and points the next action to first-battle proof/repair under `ReservationLoop Verify`.
- Latest reservation-loop first-battle attempt `20260528-064514-cpu4-reservation-loop-battle-topslot-route-proof-windows` reached a valid Path-to-Tenuto field screenshot at `117s`, then RPCS3 exited before the `169s+` screenshots. Manual `BattleRoute` gate failed because there was no late field or battle-like visual. Fatal scan was clean except the harmless `Show fatal error hints: false` config line; stderr/stdout were empty.
- Treat the latest battle attempt as `failed-window-lost-after-field`, not first-battle proof, speed, GPU migration, or 200% evidence. Its clean reservation-loop counters are route/tooling evidence only because visuals failed after field.
- Latest state-aware field reproof `20260528-070432-cpu4-stateaware-one-step-visualgate-windows-windows` passed `CleanAfterField`: field screenshots at `117s` and `133s`, empty stdout/stderr, no real targeted fatal/access/device-lost/assertion/verification log hit, and reservation-loop counters clean. Treat it as `valid-field-triage` only.
- Latest TopSlot left-only diagnostic `20260528-072448-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows` failed visual gate: the `117s` accepted-field screenshot was cutscene-like, the `165s+` left2600 frames were blue/starry non-field frames, stdout/stderr were empty, and fatal scan was clean. Host gate failed only on postrun Codex CPU, but visuals already invalidate the run.
- Latest left200x2 reproof `20260528-074420-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` failed: all `16` screenshots were black-overlay frames, manual `0117s` review confirmed black output with overlay only, and `RPCS3.log`/stderr reported `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event`. Host contention was clean, but the fatal/visual failure invalidates all counters and FPS samples.
- Current refiner next action: re-prove the newest clean loader-control-left200x2 boundary with `cpu4-loader-control-left200x2-reconfirm-visualgate-windows` before adding any diagonal pulse, battle route, HLE/GPU fast mode, speed claim, or 200% promotion. Lane-2 HLE/GPU fast modes remain blocked until field, Options, and first-battle visuals are all valid.

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
