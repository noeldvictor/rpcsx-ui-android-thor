# 20260515-eternal-sonata-first-playable-baseline

- Status: `android-baseline`
- Title ID: `BLUS30161`
- Game: Eternal Sonata
- Platform scope: `android-thor`, with later `shared-core` comparison once a Windows test copy is available
- Owner: Codex + user
- Created: 2026-05-15
- Last updated: 2026-05-16

## Hypothesis

Eternal Sonata's first playable area is slow on AYN Thor because multiple emulator subsystems are contending at once: SPU/SPURS churn, PPU waits, RSX thread work, shader/pipeline stalls, and Android scheduling/thermal limits. Before optimizing, we need a clean baseline that names the dominant hot paths and gives us a repeatable route to the same scene.

## Target Scene

Reach the first playable area on Thor and hold a stable camera/player state long enough to capture frame pacing, hot threads, memory, and logs.

Known constraints:

- Previous Android captures showed roughly 10-13 FPS and SPURS/RSX/SPU contention.
- Direct debug input is now available through `tools/thor_input_macro.ps1 -InputMode Direct`, so route control does not depend on Android keyevent mapping.

## Automation Need

We need a repeatable input route from boot to first playable area.

Current helper:

```powershell
.\tools\thor_input_macro.ps1 -BootGame -ForceStop -InputMode Direct -Profile eternal-sonata-field-route -PostSnapshot
```

## Gates And Rollback

- Use `Quiet` logging for FPS baseline.
- Use `SpursProbe` only for short follow-up diagnostics, not the main FPS run.
- Reset noisy props with `.\tools\set_thor_logging.ps1 -Mode Quiet` after diagnostics.
- Confirm whether the active core is bundled APK core or dev-core override before recording results.
- Do not change code for this baseline experiment.

## Measurement Plan

Android Thor baseline:

- Verify connected device is AYN Thor.
- Verify game config: `config/custom_configs/config_BLUS30161.yml`.
- Verify selected GPU driver and cache state.
- Start OODA stream with `default` or a light Eternal Sonata profile in `Quiet`.
- Reach first playable area.
- Capture 60-120 seconds of:
  - FPS/frame pacing or performance overlay if available.
  - `top -H` / hot thread summary.
  - RSS/PSS/memory pressure.
  - thermal state when available.
  - RPCSX log tail.
  - logcat interesting lines.
  - screenshot or short video proof of the scene.

Windows baseline:

- Blocked until the same game dump/save is available on Windows.
- Once available, run the same scene and capture SPU block/hash/syscall/RSX timing data for shared-core comparison.

Regression checks:

- Game must still boot.
- First playable area must render correctly enough to compare.
- No Android crash, ANR, or low-memory kill.
- Logging must not be heavy enough to poison FPS.

## Results

### Android Thor

Run: `debug-captures/android-speed-sprint/20260516-042622-thor-input-custom/`

- Device/profile: AYN Thor Max, stock Qualcomm driver, bundled APK core, `NeutralCore`, quiet logging, WCB enabled, Vulkan VRAM cap 3072 MB.
- Result: reached first controllable field. Direct stick input moved Polka, and direct Start opened the pause overlay.
- FPS proof:
  - field sequence at `01-field-seq-30.png`: about `16.40 FPS`;
  - later field at `03-field-seq-120.png`: about `17.54 FPS`;
  - direct movement/menu run `20260516-043657-thor-input-custom`: field about `16.50-17.99 FPS`.
- Visual proof: field rendering looks correct enough for baseline comparison; no obvious black spots or missing major textures in the captured field/menu images.
- Hot threads from `post-top-threads.txt`: `rsx::thread` around `69.5%`, five SPU threads around `30-46%`, active PPU threads around `10-24%`.
- Memory from `post-meminfo.txt`: about `4.45 GB` total RSS, about `4.25 GB` total PSS, about `1.9 GB` graphics memory, about `1.62 GB` native heap.
- Wait snapshot: `thread-wait-field-seq-120/thread-wait.txt` shows RSX, multiple SPU threads, and PPU threads runnable/running. This is an active CPU/RSX workload, not the earlier loading-progress hang.
- Input control: Direct debug pad bridge is the preferred route path; raw Odin d-pad works, but virtual/raw confirm buttons were inconsistent.
- Failed A/B: `SafeSpeed` route `debug-captures/android-speed-sprint/20260516-044501-thor-input-custom/` dropped to about `4.94 FPS` then `1.28 FPS` during the opening sequence. Do not promote RPCS3 Scheduler + SPU busy-wait as the default for this game.
- Clean route proof after timing fix:
  - route dir: `debug-captures/android-speed-sprint/20260516-053102-thor-input-eternal-sonata-field-route/`
  - capture dir: `debug-captures/android-speed-sprint/20260516-053507-eternal-sonata-field-stock-qualcomm-scene/`
  - result: reached correct first controllable field instead of stopping on the story skip prompt; FPS overlay about `15.77 FPS`; hot `rsx::thread`, active SPU workers, and active PPU threads persisted.
- Dev-core semaphore A/B:
  - Off: `debug-captures/android-speed-sprint/20260516-055612-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.43 FPS`, correct visuals.
  - Fast: `debug-captures/android-speed-sprint/20260516-060122-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.03 FPS`, correct visuals, about `98k` logged fast semaphore hits during the route.
  - interpretation: the semaphore wrapper path is hot and safe enough to keep gated, but it is not the current field FPS limiter.
- RSX threaded A/B:
  - run: `debug-captures/android-speed-sprint/20260516-061355-eternal-sonata-field-stock-qualcomm-scene/scene.png`
  - result: `Multithreaded RSX=true` dropped the field to about `12.71 FPS` and added a hot `RSX Offloader` thread; do not enable by default.
- DMA/MFC probe and fast-path follow-up:
  - profile run: `debug-captures/android-speed-sprint/20260516-063711-eternal-sonata-field-stock-qualcomm-scene/`
  - result: probe overhead lowered the overlay to about `15.33 FPS`, but it confirmed image `0x958dfe208b686622`, hot PCs `0x25cc` and `0x451c`, about `4.29 GB` sampled DMA, and zero RSX-local traffic.
  - verify run: `debug-captures/android-speed-sprint/20260516-064251-eternal-sonata-field-stock-qualcomm-scene/`
  - result: verify hashing lowered the overlay to about `11.13 FPS`; no output mismatches were logged, but exact repeat hits stayed `0`, so a simple output replay cache is not supported by field evidence.
  - MFC/list fast-path run: `debug-captures/android-speed-sprint/20260516-065348-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `17.59 FPS`, correct field visuals, hot `rsx::thread` plus SPU/PPU threads persisted. This is neutral versus baseline, not a real speed win.
- Scheduler follow-up:
  - `AltNeutral` capture: `debug-captures/android-speed-sprint/20260516-070447-eternal-sonata-field-stock-qualcomm-scene/scene.png`
  - `OldNeutral` capture: `debug-captures/android-speed-sprint/20260516-070955-eternal-sonata-field-stock-qualcomm-scene/scene.png`
  - result: both RPCS3 scheduler modes crawled around `2.2 FPS` in the story/tree route and did not produce comparable field samples. Keep `Thread Scheduler Mode: Operating System`.
- Reduced-loop cache-key run:
  - dev-core SHA256: `CE15F5A95F636CAB3BCDFB347D9D3FE280B29924432652C37A0FC4225D1A69E9`
  - cache state: normal `spu-safe-v1-tane.dat` restored to `395108` bytes; reduced-loop now writes separate `spu-safe-thor-rl-v1-tane.dat` at `346072` bytes.
  - cold field capture: `debug-captures/android-speed-sprint/20260516-073902-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `19.86 FPS`, correct-looking field visuals.
  - warm field capture: `debug-captures/android-speed-sprint/20260516-073947-eternal-sonata-field-stock-qualcomm-scene/scene.png`, about `19.61 FPS`, correct-looking field visuals.
  - menu proof: `debug-captures/android-speed-sprint/20260516-074024-thor-input-custom/01-menu-reduced-loop-cache-key.png`, about `20.18 FPS`, pause overlay correct-looking.
  - interpretation: first positive field/menu speed signal, roughly low-teens percentage over the clean `17.43-17.59 FPS` field band. It is promising but not yet a 20%+ win and still needs first-battle validation.
- Battle route attempt:
  - macro tail: `stick:left:right:5000;wait:8000;shot:battle-candidate;threads:battle-route`
  - capture: `debug-captures/android-speed-sprint/20260516-074912-thor-input-custom/02-battle-candidate.png`
  - result: missed battle and triggered Polka's boundary dialogue, "Let's go back to Tenuto."; follow-up scene capture `debug-captures/android-speed-sprint/20260516-075332-eternal-sonata-battle-stock-qualcomm-scene/scene.png` is the same dialogue, not a battle.
  - decision: first battle route remains open. Do not count reduced-loop as correctness-locked until a different route/checkpoint reaches battle.

### Windows

Windows has a separate field proof in `debug-captures/windows-lab/20260515-203026-eternal-sonata-field-menu-proof/`; use it for route and shared-core reasoning, not Thor FPS truth.

## Evidence

- Captures: `debug-captures/android-speed-sprint/20260516-042622-thor-input-custom/`, `debug-captures/android-speed-sprint/20260516-043657-thor-input-custom/`, and failed SafeSpeed A/B `debug-captures/android-speed-sprint/20260516-044501-thor-input-custom/`.
- Logs: `post-top-threads.txt`, `post-meminfo.txt`, `thread-wait-field-seq-120/thread-wait.txt`.
- Ghidra: existing `libsre` addresses from prior loading/SPURS work remain relevant for follow-up, but this baseline should not start with Ghidra.
- Related profile: `debug-profiles/eternal-sonata.json`.

## Decision

`android-baseline`: first controllable field is now routed and measurable. Reduced-loop emission is the first measured positive field/menu signal, while RPCS3 scheduler modes, RSX threading, semaphore wrappers, simple output replay, and the first MFC/list shortcut are not the breakthrough. Battle validation is now the missing correctness gate.

## Next Steps

1. Use `tools/eternal_sonata_speed_sprint.ps1 -Action AndroidRouteScene -Scene field -AndroidInputMode Direct` for route-plus-capture runs.
2. Use short SPU/MFC hot-block probes on the field scene to connect active Android SPU threads to Windows image `0x958dfe208b686622` and PCs `0x25cc`/`0x451c`.
3. Continue reduced-loop/codegen work around the same SPU image while keeping the cache-key separation; compare against clean normal-cache runs only.
4. Extend the route matrix to first battle; menu proof now exists, but speed wins still need field + battle + menu.
