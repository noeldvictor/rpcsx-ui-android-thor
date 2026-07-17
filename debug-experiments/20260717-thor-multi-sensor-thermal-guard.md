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
- `tools/test_thor_visual_route_gate.ps1`

The shared parser now combines:

- `dumpsys battery` battery temperature;
- `dumpsys hardware_properties` CPU, GPU, battery, and skin temperatures;
- readable `/sys/class/thermal/thermal_zone*/type` and `temp` samples.

Each sample is categorized as battery, skin, silicon, or informational. The hottest value in each guarded category is used. Hardware throttling/shutdown thresholds, malformed values, `NaN`, impossible negative values, and values above `150 C` are excluded.

Separate default ceilings avoid applying a battery-safe limit to normal silicon temperatures:

- battery: `39 C`;
- skin: `45 C`;
- CPU/GPU silicon: `80 C`.

Both the route macro and bounded scene capture now fail closed when battery temperature is unavailable or when no CPU/GPU silicon sensor is readable. Skin-only telemetry is not sufficient because the real Thor evidence below showed a `30.0 C` skin reading while a CPU zone was at `87.1 C`. A threshold breach or telemetry failure force-stops RPCSX. The route log records every source and hottest category value; the scene capture also saves raw battery, hardware-properties, and thermal-zone output for each guard stage.

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

Next action: do not repeat the long route. Only after cooldown, permit a pre-run telemetry query and require battery plus real CPU/GPU silicon sources below their separate limits. Any later route must use the shortened visual-state gates described below.

## Real Thor preflight and thermal abort

A stopped-device preflight validated the parser against the actual AYN Thor sensor layout without launching RPCSX:

- report: `debug-captures/adb-reports/20260717-020014-thor-thermal-preflight`;
- battery: `25.0 C`;
- skin: `30.0 C` from `hardware/skin/0`;
- hottest silicon: `48.6 C` from `thermal_zone44/cpu-1-9`;
- parsed sources: 65 thermal-zone values, one hardware value, and 30 guarded CPU/GPU/skin values;
- result: below the tightened menu limits, so one bounded menu attempt was allowed.

The single menu attempt used direct input, quiet logging, stock Qualcomm Vulkan, all experimental speed properties off, no screen recording, automatic stop, and tightened `35 C` battery / `42 C` skin / `75 C` silicon ceilings.

Evidence:

- route: `debug-captures/android-speed-sprint/20260717-020116-thor-input-custom`;
- aborted scene: `debug-captures/android-speed-sprint/20260717-020519-eternal-sonata-menu-stock-qualcomm-scene`;
- route duration: about `247.8 s` before the scene preflight;
- `13-pause-menu.png` is visually correct and reads `29.09 FPS`;
- both `guest-health-loaded-field.log` and `guest-health-pause-menu.log` contain zero fatal, device-loss, unknown-draw, `VK_ERROR`, `SIGSEGV`, `SIGABRT`, or assertion matches;
- scene preflight: battery `26.0 C`, skin `30.0 C`, hottest silicon `87.1 C` at `thermal_zone44/cpu-1-9`;
- `guard-pre-capture-silicon-temperature-stop.txt` records the forced package stop.

Classification: the pause frame is a useful `29.09 FPS` candidate, but the menu proof is `failed-thermal-guard`. The capture window never started, so this is not accepted as a menu stability pass and no repeat run is allowed in the same thermal round. The previously banked clean field result remains `28.00-28.96 FPS`.

## Post-abort safety fix

The route's own thermal log exposed a host bug: every poll had `thermal_zone_count=0`, yet the old guard accepted the lone `30.0 C` skin source. Direct PowerShell native invocation had flattened the quoted remote shell command; the later scene capture used the lossless process wrapper and therefore saw all silicon zones.

Host-only corrections:

- route polling now uses `Invoke-ThorAdbLines`, the same lossless native-argument path as scene capture;
- a guard snapshot records separate skin and silicon sensor counts;
- missing CPU/GPU silicon telemetry fails closed even when battery and skin are readable;
- thermal-zone polling uses shell `read` built-ins rather than spawning two `cat` processes per zone;
- the standard log includes the skin and silicon sensor counts.

No ADB command, app launch, or device workload was used to validate these corrections.

## Shorter state-aware route

The three large fixed waits in the Eternal Sonata load route were replaced with bounded visual gates:

- Load menu: `gate:visual:load-menu:30000`;
- Load-complete popup: `gate:visual:load-complete:50000`;
- playable field: `gate:visual:field-frame:25000`.

Each gate requires two consecutive matching frames, pins the RPCSX process, checks the multi-sensor thermal budget, logs the classification, and fails closed on timeout. The Load-complete detector uses the popup's language-independent dark/edge signature over the parchment panel. It is gated by the existing Load-menu classifier, so title, field, and wrong-route captures cannot authorize the dismiss input.

Host evidence:

- the new synthetic visual-route test passed;
- the real 2026-07-17 Load list, Load-complete popup, and field frames classified correctly;
- an offline sweep accepted 76 historical frames as valid Load-menu fixtures and produced zero Load-list versus Load-complete mismatches;
- battle and load-field profile contracts contain all three new gates and none of the old `wait:20000`, `wait:35000`, or `wait:12000` transition sequences;
- thermal parser/violation tests passed;
- all changed PowerShell files passed AST parsing;
- `git diff --check` passed.

Status: `route-tooling` / host-pass for the safety and route-shortening changes; `failed-thermal-guard` for the menu device proof. No emulator FPS gain is attributed to these host changes, but they reduce avoidable hot dwell and prevent skin-only telemetry from masking a hot SoC.

## Cool-soak launch gate

The single pre-run snapshot still allowed a launch immediately below a runtime
ceiling, and it sampled before the normal force-stop block. An already-running
guest could therefore continue heating during a repeated check. The launch
contract is now:

1. force-stop RPCSX and reset experimental properties;
2. collect three complete battery/skin/silicon snapshots two seconds apart;
3. require every snapshot to remain five degrees below the configured runtime ceilings;
4. only then set the requested properties and boot the game.

With the normal `39/45/80 C` runtime ceilings, launch requires readings below
`34/40/75 C`. A tightened `35/42/75 C` proof route requires launch readings
below `30/37/70 C`. Runtime polling keeps the configured ceilings rather than
the launch margin, so the route still force-stops on the original limit while
preserving five degrees of initial thermal headroom.

The sample count, interval, and headroom are explicit bounded parameters in
both `thor_input_macro.ps1` and `eternal_sonata_speed_sprint.ps1`. Any missing
telemetry or threshold violation aborts on that sample and keeps RPCSX stopped.

Host-only validation:

- replay of the real `87.1 C` capture still selects a silicon-temperature violation;
- the thermal test verifies the three-sample, two-second, five-degree defaults,
  wrapper forwarding, and quiesce-before-soak-before-launch ordering;
- PowerShell AST parsing passed for all three changed scripts;
- `test_thor_thermal_guard.ps1` and `test_thor_visual_route_gate.ps1` passed;
- `git diff --check` passed.

Classification: `route-tooling` / host-pass. No ADB query, device launch, or
Thor workload was used in this round.
