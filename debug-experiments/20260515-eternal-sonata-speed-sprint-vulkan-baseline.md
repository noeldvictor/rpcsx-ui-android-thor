# 20260515-eternal-sonata-speed-sprint-vulkan-baseline

- Status: `measuring`
- Title ID: `BLUS30161`
- Game: Eternal Sonata
- Platform scope: `windows-lab`, `android-thor`, `vulkan-shared`, `adreno-thor`, `visual-correctness`
- Owner: Codex + user
- Created: 2026-05-15
- Last updated: 2026-05-15

## Hypothesis

Eternal Sonata's current Thor speed problem is likely not one small setting. The highest-confidence drastic win path is to make the field, battle, and menu route repeatable, then use Windows RenderDoc/RSX traces and Android Adreno traces to identify expensive `Write Color Buffers`, render-target writeback/readback, barrier, texture flush, shader pipeline, or driver-specific stalls.

## Target Scenes

Required correctness checkpoints:

- `field`: first playable field.
- `battle`: first battle.
- `menu`: in-game menu.

Save/checkpoint route is preferred over long boot macros. Store local saves/checkpoints under ignored `save-checkpoints/` or emulator-managed save folders, never in Git.

## Gates And Rollback

- Windows runs use `tools/windows_rpcs3_lab.ps1` with official config DB, FPS overlay, and `Write Color Buffers=true`.
- Android runs use `debug-profiles/eternal-sonata-speed.json` in `Quiet` logging.
- Stock Qualcomm driver is the first Android baseline.
- Turnip/Kimchi A6xx/A7xx driver experiments are allowed only after stock baseline and must record driver name/version/date plus rollback to `Default`.
- Speed wins are correctness-locked: no new black spots, missing textures, flicker, broken lighting, or menu corruption in field, battle, or menu.

## Measurement Plan

- Tooling:
  - RenderDoc for Windows Vulkan frame capture.
  - Android GPU Inspector and Perfetto for Thor GPU/system traces.
  - Snapdragon Profiler if Qualcomm login/download is available; otherwise use AGI/Perfetto/`dumpsys`.
- Windows:
  - Capture each scene with screenshots and FPS overlay.
  - Take RenderDoc capture for `field` first; capture `battle` and `menu` only after the first capture path is stable.
  - Inspect render target traffic, WCB cost, attachment load/store, barriers, texture flushes, shader/pipeline churn, and driver stalls.
- Android Thor:
  - Capture screenshots/video, FPS/frame pacing, hot threads, memory, thermals, active core identity, config, cache state, and driver.
  - Run at least one sustained capture because short bursts can hide thermal behavior.
- Metrics:
  - Baseline FPS/frame-time per scene.
  - CPU hot threads and RSX/PPU/SPU symptoms.
  - GPU/driver counters when AGI/Snapdragon tooling permits them.
  - Visual pass/fail per scene.

## Results

### Tooling

- RenderDoc installed via winget package `BaldurKarlsson.RenderDoc`.
  - Verified command: `C:\Program Files\RenderDoc\renderdoccmd.exe`
  - Version: `renderdoccmd x64 v1.44`, build `050034a0faa37d606ce1b8cf677dba4bc36984ea`.
- Android GPU Inspector installed under the local toolchain.
  - Verified command: `C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\agi-3.3.3\agi\agi.exe`
  - Version: `AGI version 3.3.3:5f97b4fd99a9459320b782203ce2de5351a1e661`.
  - Downloaded zip SHA256: `3fad329ede78ee3d8fb9947906b138afa851c851ad22b20fb47d5388e25500c2`.
- Snapdragon Profiler not installed. Treat as blocked until Qualcomm login/download is available; AGI/Perfetto/`dumpsys` are the Android trace path for now.
- Tooling report: `debug-captures/tooling/20260515-183235-10424-speed-sprint-tools.md`.

### Windows

- Route/tool proof, not a true field baseline:
  - Capture: `debug-captures/windows-lab/20260515-183351-eternal-sonata-field-route-probe-windows/`
  - Result: ISO auto-located, official config DB refreshed, `Write Color Buffers: true`, FPS overlay enabled, GUI suppressed, screenshots captured.
  - Screenshot showed the shader/pipeline preload screen, not the first playable field.
- RenderDoc injection proof:
  - Capture: `debug-captures/windows-lab/20260515-183906-eternal-sonata-renderdoc-inject-proof3-windows/`
  - `.rdc`: `renderdoc/eternal-sonata-renderdoc-inject-proof3-windows_frame1598.rdc`
  - Size: about 130 MB.
  - Thumbnail export succeeded and showed the title/menu with FPS overlay. This proves the lab can launch RPCS3, inject RenderDoc, send `f12`, save `.rdc`, and shut down without leaving a stray process.
  - Status: tooling pass only. Still need first playable field, first battle, and in-game menu saves/checkpoints.

### Android Thor

- Device snapshot:
  - Capture: `debug-captures/android-speed-sprint/20260515-183313-eternal-sonata-field-stock-qualcomm-device/`
  - ADB device: `c3ca0370`, product/model `kalama` / `AYN_Thor`.
  - Device properties: `AYN Thor`, `QCS8550`, `qcom`, `kalama`.
  - SurfaceFlinger GLES line: `Qualcomm, Adreno (TM) 740, OpenGL ES 3.2 V@0676.53 ... Date:12/27/23`.
  - Status: device/driver identity proof only. Still need stock-driver field/battle/menu FPS and screenshot captures.

### Driver Matrix

| Driver | Version/date | Scene(s) | FPS/frame-time | Visual status | Notes |
| --- | --- | --- | --- | --- | --- |
| Stock Qualcomm | Adreno 740 GLES `V@0676.53`, `Date:12/27/23` from SurfaceFlinger | device snapshot only | pending | pending | First required baseline |

## Evidence

- Captures:
  - `debug-captures/tooling/20260515-183235-10424-speed-sprint-tools.md`
  - `debug-captures/android-speed-sprint/20260515-183313-eternal-sonata-field-stock-qualcomm-device/`
  - `debug-captures/windows-lab/20260515-183351-eternal-sonata-field-route-probe-windows/`
  - `debug-captures/windows-lab/20260515-183906-eternal-sonata-renderdoc-inject-proof3-windows/`
- Saves/checkpoints: pending local-only under `save-checkpoints/` or emulator save paths.
- Logs: pending.
- RenderDoc/AGI/Snapdragon traces:
  - RenderDoc route proof `.rdc` exists for the title/menu screen.
  - AGI installed but no Android trace captured yet.
  - Snapdragon Profiler blocked/missing.

## Decision

`measuring`

## Next Steps

1. Create or mirror save/checkpoints for field, battle, and menu.
2. Run Android Thor stock-driver field/battle/menu baseline in Quiet mode.
3. Run Windows field capture from matching checkpoint with screenshots and RenderDoc `f12` capture.
4. Use AGI/Perfetto on Thor for the matching field scene after the stock baseline is stable.
5. Promote the first confirmed Vulkan/RSX bottleneck into a gated speed experiment.
