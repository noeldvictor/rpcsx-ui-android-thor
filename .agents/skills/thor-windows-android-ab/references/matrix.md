# Windows / Android A-B Matrix

## Windows Lab

Use:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -WindowsInputBackend PadApi -WindowsGameScreen 1 -MaxSeconds 130
```

Rules:

- Launch through repo scripts, not double-click RPCS3.
- Keep RPCS3/PS3 gameplay on `\\.\DISPLAY2` with `-WindowsGameScreen 1`.
- Keep FPS overlay/window title enabled.
- Mark `contended-host` if Vita3K, another emulator, encoding, builds, or heavy GPU work is active.
- Windows explains route, RenderDoc/RSX behavior, and shared-core plausibility; it is not Thor performance truth.
- Current GPU/CPU-to-GPU work remains Windows-only until the 200% field/menu/battle gate is met.

## Thor Truth

Use:

```powershell
.\tools\eternal_sonata_speed_sprint.ps1 -Action AndroidRouteScene -Scene field -Driver stock-qualcomm -Core LABEL -AndroidSceneSeconds 12 -NoPerfetto
```

Rules:

- Start stock Qualcomm driver unless driver matrix is the explicit variable.
- Use `NeutralCore` and quiet logging for FPS sweeps.
- Capture screenshot, hot threads, memory, thermal, config, core identity, and cache state.

## Comparison Rules

Only compare runs with the same:

- scene and camera/player state;
- driver/config/WCB state unless explicitly varied;
- logging mode;
- cache state;
- core build or declared changed files;
- host-contention grade for Windows.

Report FPS as evidence, not certainty, when scene position differs.
