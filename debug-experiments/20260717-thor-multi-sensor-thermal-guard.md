# Thor multi-sensor thermal guard

Date: 2026-07-17

## Hypothesis

A battery-only ceiling is not sufficient for bounded AYN Thor validation. The 2026-07-17 field route reported exactly `25.0 C` at every poll while `dumpsys thermalservice` reported `HAL Ready: false`. Future menu and battle routes need independent readable workload telemetry before RPCSX is allowed to run.

## Change

Changed files:

- `tools/thor_debug_common.ps1`
- `tools/thor_input_macro.ps1`
- `tools/eternal_sonata_speed_sprint.ps1`
- `tools/test_thor_thermal_guard.ps1`

The shared parser now combines:

- `dumpsys battery` battery temperature;
- `dumpsys hardware_properties` CPU, GPU, battery, and skin temperatures;
- readable `/sys/class/thermal/thermal_zone*/type` and `temp` samples.

Each sample is categorized as battery, skin, silicon, or informational. The hottest value in each guarded category is used. Hardware throttling/shutdown thresholds, malformed values, `NaN`, impossible negative values, and values above `150 C` are excluded.

Separate default ceilings avoid applying a battery-safe limit to normal silicon temperatures:

- battery: `39 C`;
- skin: `45 C`;
- CPU/GPU silicon: `80 C`.

Both the route macro and bounded scene capture now fail closed when battery temperature is unavailable or when no CPU/GPU/skin sensor is readable. A threshold breach or telemetry failure force-stops RPCSX. The route log records every source and hottest category value; the scene capture also saves raw battery, hardware-properties, and thermal-zone output for each guard stage.

## Host verification

No ADB, launch, install, capture, or device query occurred during this implementation round.

Commands:

```powershell
$files = @(
  'tools/thor_debug_common.ps1',
  'tools/thor_input_macro.ps1',
  'tools/eternal_sonata_speed_sprint.ps1',
  'tools/test_thor_thermal_guard.ps1'
)
foreach ($file in $files) {
  $null = [scriptblock]::Create((Get-Content -Raw -LiteralPath $file))
}

.\tools\test_thor_thermal_guard.ps1
git diff --check
```

Results:

- all four PowerShell files parsed successfully;
- battery, skin, and silicon maximum selection passed;
- malformed/negative/`NaN` filtering passed;
- cool snapshot passed;
- missing battery failed closed;
- battery-only telemetry failed closed;
- battery, skin, and silicon boundary cases each selected the correct violation;
- thermal-zone shell-output contract passed;
- `git diff --check` passed.

## Rollback

Revert the thermal-guard commit. Do not disable the guard for performance measurements.

## Result

Status: `route-tooling` / host-pass. This does not change emulator FPS. It makes the next cool-device menu or battle proof safer and gives a trustworthy thermal reason when a run is stopped.

Next action: after cooldown, allow only the pre-run telemetry query. Launch one bounded route only if battery plus at least one CPU/GPU/skin source are readable and below their separate limits.
