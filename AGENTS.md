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
- Use repo-local skills only: `codex-goal-loop`, `ps3-debug-knowledge`, `ps3-speed-proof-gate`, `ps3-rsx-experiment-gate`, `ps3-continual-harness-refiner`, and `ps3-spu-contract-compiler`.
- Always start by checking for an active meaningful run/edit. Do not duplicate live work.
- Newest failed visual/log/window/route evidence overrides older opportunities.

## Sprint Workflow

1. Read this file, the relevant `.agents/skills/*/SKILL.md`, and the narrowest `debug-experiments/` ledger.
2. Run `.\tools\ps3_harness_refiner.ps1 -MaxRuns 8`.
3. Take one concrete Windows-only step: route repair, boundary bisection, harness fix, contract extraction, analysis, or one gated experiment.
4. Verify screenshots, fatal logs, host grade, and counters.
5. Classify honestly: `speed-win`, `windows-micro-win`, `stackable-cpu-pressure`, `gpu-migration-credit`, `valid-field-triage`, `valid-options-counterproof`, `route-tooling`, `failed`, `stack-regression`, `parked`, or `not-comparable`.
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
- Latest left200x2 reconfirm `20260528-080430-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` failed visual gate without fatal logs: all `16` screenshots were `Now Loading...`/loading-like small PNGs through `210s`; manual `0117s` review confirmed loading, not Path-to-Tenuto field. Host contention was clean, but FPS/counters are invalid because visuals failed.
- Latest state-aware reset `20260528-082422-cpu4-stateaware-one-step-visualgate-windows-windows` passed `CleanAfterField`: field-like screenshots at `117s` and `133s`, manual `0117s` review confirmed Path-to-Tenuto field, stdout/stderr were empty, and fatal scan was clean. Postrun host summary was moderate only because Codex CPU was sampled after RPCS3 stopped.
- Latest TopSlot left-only diagnostic `20260528-084504-cpu4-reservation-loop-topslot-leftonly-diagnostic-windows-windows` reached a clean accepted-field screenshot, then `ls_left:2600` produced a crash overlay/corrupt field and a real `VM: Access violation reading location 0x40` at `0x002aedd0`. Treat it as `failed-fatal-log`, not movement, speed, GPU, first-battle, or 200% evidence.
- Latest no-movement loader-control reproof `20260528-090516-cpu4-loader-control-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `10` screenshots field-like through `190s`, manual final-field review was clean, stderr had only Qt warnings, host checks were clean, and no real targeted fatal/access/device-lost/assertion/verification log hit appeared. Reservation-loop verify logged `1489` MFC dynamic records, `1610` wait records, `84265` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `242`. Treat it as `valid-field-triage` and route-tooling only.
- Latest small movement proof `20260528-092432-cpu4-loader-control-left200-visualgate-windows-windows` passed `CleanAfterField`: first field-like screenshot at `117s`, all `14` screenshots field-like through `200s`, manual immediate-post-left and final-field reviews were clean, stderr had only Qt warnings, host checks were clean, and no real targeted fatal/access/device-lost/assertion/verification log hit appeared. Reservation-loop verify logged `1619` MFC dynamic records, `1745` wait records, `91872` wait-PC records, max output mismatches `0`, max dynamic fail `0`, and max overflow reads `189`. Treat it as `valid-field-triage` plus small route/movement tooling only.
- Latest 0x25cc coverage refresh `debug-captures\windows-lab\_eternal-sonata-25cc-coverage-latest.md` shows the clean exact `0xa1c000` skip removes only `5.55 MB`, `0.97%` of that run's hot 0x25cc bytes, and `0.10%` of the refreshed `5.65 GB` 0x25cc atlas; do not rerun the exact skip expecting speed. The useful CPU-pressure path is broader verify-only coverage around dynamic MFC / `0x9e4000` families or SPU codegen dispatch overhead.
- Latest 0x25cc runtime-family refresh `debug-captures\windows-lab\20260526-180020-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows\eternal-sonata-25cc-runtime-family-summary.md` found `10` repeated `0x9e4000` HLE pattern-body candidate groups covering `437.30 MB` of `0x25cc` traffic with `0 B` RSX-local and zero shadow mismatches, but the source run has a real `VM: Access violation reading location 0x40`; use this as sizing/target selection only, not proof.
- Latest stock-control TopSlot battle-route isolation `20260528-102538-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows` also failed without `Verify25ccShadow`: `15` black-overlay screenshots through `320s`, no field/battle visuals, clean host checks, and a real `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event` with fault address `0x2d0614000`. Treat as route/RSX-device-loss evidence only.
- Latest `left200x1` reproof `20260528-104441-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `14` field-like screenshots through `200s`, manual immediate/late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion hits, and clean host checks. Treat it as `valid-field-triage` plus route/movement tooling only.
- Latest `left200x2` rerun `20260528-110434-cpu4-loader-control-left200x2-visualgate-windows-windows` failed `CleanAfterField`: `16` screenshots were `cutscene-or-nonfield-small-png`, manual frames were blue/starry non-field output, stdout was empty, stderr had only libusb device warnings, host checks were clean, and targeted fatal/access/device-lost/assertion/verification scan was clean. Reservation-loop counters were clean (`0` mismatches, max overflow reads `212`) but invalid for promotion because visuals failed.
- Latest `left200x2-confirm` reproof `20260528-112431-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual post-second-pulse and late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. Postrun host was moderate only from Codex CPU after RPCS3 exited; do not use this as speed evidence.
- Latest `left200x2-diag200` proof `20260528-114457-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: `18` field-like screenshots through `220s`, first field-like at `117s`, manual post-diagonal and late field reviews clean, stdout/stderr empty, no real fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. It is route-tooling only, not speed, first-battle, Options/menu, GPU migration, or 200%.
- Latest SPU HLE atlas refresh `debug-captures\windows-lab\_eternal-sonata-spu-hle-candidates-latest.md` scanned `12` recent runs, used `2` valid field runs, excluded `2` fatal field-like runs, and selected PC `0x25cc` / `CellSpursKernel0` as top verify-gated CPU/SPU HLE/codegen target: `3.06 GB` over `1946` records, `58` patterns, max job `3.06 MB`, `0 B` RSX-local. Broad SPU-to-Vulkan remains parked.
- Latest `0x25cc / 0x9e4000` verifier-plan refresh `debug-experiments\20260526-25cc-9e4000-verifier-plan.md` updated current `rpcs3-upstream` source anchors and keeps the historical broad family at `6.86 GB`, `4340` records, `159` pattern rows, and `0 B` RSX-local. It is analysis only; next code work is verify-only family/hash counters before any fast/body mode.
- Latest `0x25cc` pattern-hash target refresh `debug-experiments\20260526-25cc-pattern-hash-targets.md` shows `10` runtime groups, `437.30 MB`, top-16 atlas overlap `5` groups / `274.17 MB`, shadow verifier `11988` hits / `187.31 MB`, GET/PUT `5688/6300`, and match/mismatch `11988/0`. The matched groups are PUT-heavy, so GET-only bodyfast cannot cover the main bytes.
- Latest `0x25cc` native-contract refresh `debug-experiments\20260526-25cc-shadow-native-contract.md` classifies the selected shadow verifier data as fatal-run sizing only: `11988` hits / `187.31 MB`, GET/PUT `5688/6300`, match/mismatch `11988/0`, and runtime-seen top groups `274.17 MB` with `84.4%` PUT. Upstream `rpcs3-upstream` already has direction-split descriptor anchors; the vendored Android core was not run.
- Latest `0x25cc` field counterproof `20260528-132515-cpu4-hle-25cc-shadow-desc-loader-control-left200x2-diag200-counterproof-windows-windows` passed visual triage: `18` field-like screenshots, first field at `117s`, no invalid-after-field frames, and `0` targeted fatal/access/device-lost/assertion hits. 25cc descriptors had `22008` rows / `23643` hits / `369.42 MB`, GET/PUT `10998/12645`, mismatch `0`, overflow `0`. Generic non-25cc shadow rows at PC `0x451c` still had mismatches, so this is 25cc-only field counterproof.
- Latest `Verify25ccShadow` first-battle attempt `20260528-135315-cpu4-hle-25cc-shadow-desc-battle-topslot-counterproof-after-fieldclean-windows` failed visual gate: all `15` screenshots were black-overlay small PNGs, no field-like or battle-like screenshot appeared, targeted fatal scan was clean, and 25cc counters were partial-only despite zero 25cc mismatch/overflow. Treat window-title FPS samples as invalid when screenshots are black.
- Latest loader-control `left200x2` reconfirm `20260528-141346-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual `0117s`/`0210s` review confirmed clean Path-to-Tenuto field after movement, stdout/stderr empty, host clean, and no targeted fatal/access/device-lost/assertion hits. Extracted counters: `1539` GPU-probe records, `2.28 GB` observed DMA, `0 B` RSX-local, reservation-loop rows `1639`, command exact-PC rows `44896`, wait exact-PC rows `86252`. Treat as `valid-field-triage` and route/counter base only.
- Latest loader-control `left200x2-diag200` repro `20260528-143321-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` passed `CleanAfterField`: `18` field-like screenshots through `220s`, first field-like at `117s`, manual `0117s`/`0141s`/`0220s` review confirmed clean Path-to-Tenuto field after diagonal movement, stdout/stderr empty, and no targeted fatal/access/device-lost/assertion hits. Runtime host samples were clean; postrun was moderate only from Codex CPU after RPCS3 exited. Extracted counters: `1743` GPU-probe records, `2.68 GB` observed DMA, `0 B` RSX-local, reservation-loop rows `1884`, command exact-PC rows `51325`, wait exact-PC rows `98353`. Treat as `valid-field-triage` and route/counter base only.
- Latest loader-control `left200x2-diag200-left400` repro `20260528-151432-cpu4-loader-control-left200x2-diag200-left400-visualgate-windows-windows` passed `CleanAfterField`: `19` field-like screenshots through `230s`, first field-like at `117s`, manual `0129s`/`0230s` review confirmed clean field visuals after the `left400` bridge, stdout/stderr empty, no targeted fatal/access/device-lost/assertion hits, and `0 B` RSX-local. Treat as `valid-field-triage`; not first-battle proof, speed, GPU migration, or 200%.
- Latest `Verify25ccShadow` first-battle repair probe `20260528-154248-cpu4-hle-25cc-shadow-desc-left400-diag400-battleprobe-windows` failed BattleRoute visual gate: all `20` screenshots were black-overlay small PNGs, no field-like or battle-like screenshots appeared, stdout/stderr empty, targeted fatal/access/device-lost/assertion hits `0`, and 25cc descriptor counters were clean but partial-only. Ignore title FPS samples when screenshots are black.
- Latest loader-control `left200x2` reproof `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots through `210s`, first field-like at `117s`, manual `0117s`/`0210s` review confirmed clean Path-to-Tenuto field after two left pulses, stdout/stderr empty, no real targeted fatal/access/device-lost/assertion/verification hits, and runtime host samples clean. The wrapper stalled after RPCS3 exited and was killed; reservation-loop CSVs were missing, so treat this as visual route proof only.
- Latest loader-control `left200x2-diag200` repro `20260528-162812-cpu4-loader-control-left200x2-diag200-visualgate-windows-windows` failed `CleanAfterField`: all `18` screenshots were blue/starry non-field frames, first field-like was none, manual `0117s`/`0220s` review confirmed wrong-scene sky output, stdout/stderr empty, and no real fatal/access/device-lost/assertion/verification hits. Runtime/postrun host grade was clean, but visuals invalidate all FPS/counter use.
- Latest loader-control `left200x2` backoff reproof `20260528-164731-cpu4-loader-control-left200x2-confirm-visualgate-windows-windows` failed `CleanAfterField`: all `16` screenshots were black-overlay frames, first field-like was none, manual `0117s`/`0210s` review confirmed black output with perf overlay only, stdout/stderr empty, and no real fatal/access/device-lost/assertion/verification hits. Runtime host samples were clean; postrun was moderate only after RPCS3 exited. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing, so no counter or speed claim exists.
- Latest loader-control `left200x2` reproof `20260528-170717-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows` reached a field-like screenshot at `138s` but failed `CleanAfterField`: later invalid cutscene/non-field frames appeared, `0190s+` screenshots showed the RPCS3 crash overlay on black output, and `stderr`/`RPCS3.log` had real SPU fatal unknown STOP codes at about `187s`. Host checks were clean, but visuals/logs invalidate all FPS/counter use. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing.
- Latest lower-bound repair `20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows` passed `CleanAfterField`: `16` field-like screenshots from `117s` through `220s`, manual first/last review confirmed correct Path-to-Tenuto field visuals, runtime/postrun host checks were clean, and targeted crash scan found no real fatal/access/device-lost/assertion hit. The wrapper stalled after RPCS3 exit and was killed; reservation-loop CSVs were missing, so it is visual route proof only.
- Current refiner next action: do not repeat `loader-control-left200x2`; it has failed `3` times in the recent window after lower `left200` stayed clean. Repair route control or switch to focused SPU kernel HLE/codegen/verifier analysis before another movement run. Latest valid lower bound is `20260528-172735-cpu4-loader-control-left200-repair-after-left200x2-fatal-visualgate-windows-windows`; latest valid `left200x2` base remains `20260528-160536-cpu4-loader-control-left200x2-reconfirm-visualgate-windows-windows`.
- Latest SPU verifier pivot audit refreshed the 8-run HLE atlas: PC `0x25cc` / `CellSpursKernel0` is still the top CPU-pressure target at `3.68 GB` over `3` valid field runs, `0 B` RSX-local. Dedicated `25cc-counterproof` parsing of the latest clean `left200` repair and latest tracked `left200x2` loader-control base found `0` shadow descriptor rows/hits in both logs, so loader-control atlas data is target selection only, not counterproof. Use the dedicated `Verify25ccShadow`/descriptor route for future proof; do not cite loader-control logs as 25cc descriptor proof.
- Latest current-format `Verify25ccShadow` Options counterproof `20260528-182410-cpu4-hle-25cc-shadow-desc-options-fastselect-currentproof-windows` reached the full title Options page (`screenshot-0079s-options-candidate.png`, `screenshot-0089s-options-late.png`), had clean host/fatal checks, and summarized as `valid-options-counterproof`: 25cc descriptors `8958` rows / `9498` hits / `148.41 MB`, GET/PUT `4473/5025`, output mismatches `0`, overflow `0`. Refiner says do not rerun field or Options; next proof target is first battle under `Verify25ccShadow`.
- Latest first-battle `Verify25ccShadow` attempt `20260528-184420-cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute-windows` failed: it reached clean field at `117s`, then hit a real PPU VM access violation at `0x002aedd0` reading `0x40`; `169s+` screenshots show the likely-crashed overlay/corrupt frozen field and no battle-like frame. 25cc descriptors stayed mismatch/overflow clean (`9918` rows / `10833` hits / `169.27 MB`), but this is `failed-fatal-log`, not first-battle proof. Refiner next action is the same TopSlot battle route with `Verify25ccShadow` off to isolate route-vs-verifier fatal.
- Latest stock-control TopSlot isolation `20260528-190511-cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute-windows` also failed with `Verify25ccShadow` off: all `15` screenshots were black-overlay frames, visual gate found no field or battle visuals, host checks were clean, and stderr/RPCS3 log hit real RSX `VK_ERROR_DEVICE_LOST` in `vk::wait_for_event`. GPU probe saw `724.84 MB` DMA, hot PCs `0x451c`/`0x25cc`, and `0 B` RSX-local. Treat as route/RSX-device-loss evidence only; refiner next action is to re-prove the clean `left200x1` loader-control boundary before extending movement or battle routing.
- Latest `left200x1` refiner reproof `20260528-192415-cpu4-loader-control-left200-reconfirm-visualgate-windows-windows` reached correct Path-to-Tenuto field at `136s`, then later invalid/crash-overlay screenshots appeared; visual gate reported `FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS`, and stderr/RPCS3 log had real SPU unknown STOP fatals. Treat it as `failed-fatal-log` / `failed-visual-gate`, not movement, speed, GPU, first-battle, or 200% proof.
- Current route lesson: do not keep extending or rerunning the loader-control movement ladder from the latest fatal. Prefer focused SPU contract/compiler analysis until a new route repair is justified.
- Source-aligned Windows repair `e12beb222fea26fa5e5f86fa507ad91536fa4d60` now includes upstream RPCS3 reservation-priority fix `e379fba` and disables the unsafe CellSpurs JobChain acquire hash. Exact rebuilt binary `0.0.41-597-e12beb22` / SHA256 `C31622E54441A6946A9AFC6986E8F7C9193F55541E158B2959BEE95B07AA3CC9` removed the prior unknown-draw/VM-access corruption on the same bounded route.
- Latest corrected-contract field proof `20260715-220332-cpu4-verify25cc-e379fba-extendedkey-first-battle-windows` is a valid moving-field counterproof: correct field/animation through `185s`, five external-clean host snapshots, zero targeted fatal/draw/access/Vulkan/device-lost/assertion hits, and strict verifier `732/732` accepted with `1878` hits and mismatch/overflow `0`. Scripted screenshot labels did not make it a battle.
- Exact repaired-binary Options proof `20260715-223137-cpu4-verify25cc-e379fba-options-fastselect-windows` reached and held the complete title Options page through `130s`, had six external-clean host snapshots and zero targeted fatal signatures, and passed the strict verifier `461/461` with `957` hits and mismatch/overflow `0`. Do not rerun capped field or Options; genuine first battle is the only remaining correctness checkpoint.

## Banked Findings

- Promoted workflow: Thor dev-core speed pushes use RelWithDebInfo as the official baseline. Debug native cores are invalid for FPS/Rocknix comparisons and `tools/build_push_thor_core.ps1` now blocks Debug tasks or newest-Debug-library pushes unless `-AllowDebugFallback` is explicit. This is workflow promotion only; reduced-loop u4, `0x25cc bodyfast`, and HLE/GPU fast paths remain gated until field, Options/menu, and first-battle proof all pass.
- Ghidra/static analysis has been used for SPURS/semaphore and SPU-window understanding, and current 25cc work has source/disasm anchors. There is no promoted fusion superpath from Ghidra. Existing fused RSX paths are experimental/parked, and `0x25cc/0x9e4000` remains a CPU/SPU HLE/codegen candidate, not a GPU-resident fused path.
- Default SPU speed lane is now the contract compiler: runtime logs -> SPU windows -> Ghidra headless/static tightening -> `spu-contracts\BLUS30161` JSON -> verify-only emulator counters -> fast path. Start with `0x25cc/0x9e4000` and `0x451c`; GPU compute stays parked until contracts prove stable batching, low readback pressure, and RSX-consumed data.
- Current source alignment says Windows has the priority-1 `0x25cc/0x9e4000` predicate, corrected verify-only contract counters/reject buckets, the `0x451c` dynamic-list helper, and upstream reservation-priority fix `e379fba`; vendored RPCSX still has only the generic Thor DMA probe. Do not port to Android or enable fast mode yet.
- Current verify-counter schema requires `RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow`, blocks fast/body/GPU fast values, and defines reject buckets for title/image/PC/group/SPU/cmd/list/tag/size/EA/LS/risky-config/fast-mode before any behavior change.
- Current verify log row is implemented and runtime-proven on a moving field with `hle_mode=contract-25cc-9e4000`; it remains log/shadow-only and body behavior stays off.
- Current verify log-row parser: `tools/parse_spu_contract_verify_log.ps1`. It validates exact contract anchors, hit/byte arithmetic, reject sums, fast-mode leakage, mismatch, and overflow, supports strict `-FailOnGate` checks, and always reports `promotion_ready=false` because visuals/fatal-log gates are external.
- `0x25cc bodyfast` is banked only as stackable CPU-pressure reduction: RPCS3 process CPU `42.60%` to `37.10%` (`-5.50 pp`, `-12.91%`) on clean capped BattleRoute repeat. It is not an FPS win, GPU migration, or 200% candidate.
- Final bodyfast plus RSX-local stack is visually compatible on the capped TopSlot BattleRoute, but it remains around `120 FPS` and reports `0 B` promoted CPU/SPU-to-GPU replacement. Do not keep stacking RSX toggles or rerun the auditor.
- RSX-local accounting is useful but separate from CPU/SPU-to-GPU migration. Current promoted CPU/SPU-to-GPU credit remains `0 B`.
- 0x25cc descriptor/shadow verifier now has exact source-aligned clean moving-field and full title Options counterproofs with zero 25cc mismatches and overflow `0`. It has not yet entered battle on that binary. Treat this as verifier coverage only, not bodyfast/codegen promotion.
- Loader-control runs can have useful SPU atlas bytes while still having no 25cc descriptor rows. Counterproof requires explicit `Verify25ccShadow`/descriptor logs.
- Exact `0xa1c000` 0x25cc skip is correctness-clean but too small for a speed path: latest refresh says `5.55 MB` skipped versus `5.65 GB` observed 0x25cc atlas (`0.10%`).
- Broader `0x9e4000` 0x25cc pattern groups are the better CPU-pressure candidate. Current sizing is `3.06 GB` in valid field atlas data, `6.86 GB` in the wider historical verifier-plan CSV, and `437.30 MB` in the latest shadow-run runtime family, still with `0 B` RSX-local; treat as verify/codegen CPU-pressure work, not GPU offload proof.
- Direction-split PUT-heavy `0x25cc` evidence now has clean field and Options/menu counterproofs with zero 25cc descriptor mismatches/overflow. It is still not promotion until first-battle visuals are clean under the same proof discipline.
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
- Current SPU contract plan: `debug-experiments/20260528-spu-contract-pipeline-plan.md`.
- Current SPU contract tool: `tools/spu_contract_pipeline.ps1`.
- Current SPU contract outputs: `spu-contracts/BLUS30161/latest-summary.md`.
- Current SPU verify-counter plan: `spu-contracts/BLUS30161/verify-counter-plan.md`.
- Current SPU source alignment: `spu-contracts/BLUS30161/source-alignment.md`.
- Current SPU verify-counter schema: `spu-contracts/BLUS30161/verify-counter-schema.md`.
- Current SPU verify log-row scaffold: `spu-contracts/BLUS30161/verify-logrow-implementation.md`.
- Current SPU verify log-row parser: `tools/parse_spu_contract_verify_log.ps1`.
- Current refiner: `tools/ps3_harness_refiner.ps1`.
- Current refiner skill: `.agents/skills/ps3-continual-harness-refiner/SKILL.md`.
- Current SPU contract skill: `.agents/skills/ps3-spu-contract-compiler/SKILL.md`.
- Current safe Windows runtime base is current upstream RPCS3 `1269ebff` on local branch `codex/clean-upstream-20260715`, plus local MSVC zlib commit `c433cc7` and preserved curl/wolfSSL integration fix `6311394472`. Exact `rpcs3.exe` SHA256 is `7A9E5E0CA3465359E8E6339D14B29359A9847CBAD9450C8AC087218B404AEC28`.
- Do not use the older monolithic instrumented fork for promotion runs. Preserve it for forensic comparison only; it has produced native/JIT and movement failures even with probes disabled.
- CPU affinity `0x0f` is now a known invalid promotion condition for the long diagonal/left first-battle route: both custom and clean current-upstream builds can hit guest PPU `0x002aedd0` reading `0x40`. Treat four-core route failures as stress evidence, not normal-scheduler regressions.
- Current-upstream normal-scheduler speed proof is `20260715-230705-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-first-battle-speed-windows`: exact Path-to-Tenuto field at `57s`, real tutorial prompt at `69s`, correct battle through the `150s` cutoff, zero actionable fatal hits, external-clean host evidence, and 30 gameplay samples averaging `120.002 FPS` (`119.85` to `120.38`). This is a stable 400% Windows gameplay proof.
- Matching exact-build/config Options proof is `20260715-231132-clean-upstream1269ebf-allcore-uncap240-frame-scaled20-options-speed-windows`: correct full Options page through `70s`, zero actionable fatal hits, external-clean host evidence, and six Options samples averaging `240.072 FPS` (`239.88` to `240.40`). Together these runs clear the Windows 200% field/menu/first-battle gate.
- High-vblank Windows routes must scale input pulses by emulated frames: the title needs `down:20` at 240 Hz; `down:80` and `down:300` repeat into Options. Use `gate_title_menu`, `gate_load_target`, `gate_load_complete`, `gate_field`, and `gate_first_battle_prompt` instead of fixed route delays. The load-target gate classifies only its latest screenshot to avoid rescanning the full run.
- No Android build, ADB action, Thor launch, capture, or sensor query was used for the current-upstream Windows proof. Thor work is now permitted only as a short thermally gated baseline/port check; query temperature first and abort if the handheld is still hot.
- Add new dated facts to the ledger. Update this file only for standing rules, current state, or repeated gotchas.
