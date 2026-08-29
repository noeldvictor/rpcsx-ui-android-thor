$ErrorActionPreference = "Stop"

$guardPath = Join-Path $PSScriptRoot "thor_device_thermal_guard.sh"
$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$routePath = Join-Path $PSScriptRoot "invoke_thor_transformers_hle_render_probe.ps1"

$guard = Get-Content -LiteralPath $guardPath -Raw
$macro = Get-Content -LiteralPath $macroPath -Raw
$route = Get-Content -LiteralPath $routePath -Raw

$requiredGuardFragments = @(
    'silicon_zones="31 32 33 34 55 63 64 65 66 67 68 69 70 82 90"',
    'junction_zones="35 36 37 38 39 40 41 42 43 44 45 47 48 49"',
    'battery_zone=94',
    '[ "$silicon_count" -ne 15 ]',
    '[ "$junction_count" -ne 14 ]',
    'code=sensor-set',
    'code=silicon-hard-limit',
    'code=silicon-early-stop',
    'code=junction-hard-limit',
    'code=battery-hard-limit',
    'code=skin-hard-limit',
    'am force-stop "$package"',
    'sleep 2'
)

foreach ($fragment in $requiredGuardFragments) {
    if (-not $guard.Contains($fragment)) {
        throw "The device thermal guard is missing: $fragment"
    }
}

$requiredMacroFragments = @(
    '[ValidateSet("full", "fast", "device")]',
    'Assert-ThorThermalBudget "device-guard-source-check" -FastTelemetry -PassThru',
    '$remoteGuard = "/data/local/tmp/rpcsx-thor-thermal-guard.sh"',
    '$script:ThorDeviceThermalGuardPowerShell = [PowerShell]::Create()',
    '$script:ThorDeviceThermalGuardPowerShell.AddCommand($Adb)',
    '$script:ThorDeviceThermalGuardPowerShell.BeginInvoke()',
    'Complete-ThorDeviceThermalGuard',
    'AsyncWaitHandle.WaitOne(5000)',
    'if ($ThermalRuntimeTelemetry -eq "device")',
    'Start-Sleep -Milliseconds $Milliseconds',
    'Assert-ThorDeviceThermalGuardAlive',
    'Start-ThorDeviceThermalGuard',
    'Stop-ThorDeviceThermalGuard',
    'Device runtime thermal telemetry requires a stop token or -StopAfterMacro.',
    'function Invoke-ThorControlPause',
    'function Invoke-ThorControlResume',
    '& $Adb -s $DeviceSerial forward tcp:8099 tcp:8099',
    'Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8099/pause"',
    'Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8099/resume"',
    'while ($timer.ElapsedMilliseconds -lt 8000)',
    'Start-Sleep -Milliseconds 100',
    '} elseif ($token -eq ''pause'') {',
    '} elseif ($token -eq ''resume'') {'
)

foreach ($fragment in $requiredMacroFragments) {
    if (-not $macro.Contains($fragment)) {
        throw "The input macro device thermal route is missing: $fragment"
    }
}

$preflightIndex = $macro.IndexOf('Assert-ThorThermalPreflight "pre-run"')
$guardStartIndex = if ($preflightIndex -ge 0) {
    $macro.IndexOf('Start-ThorDeviceThermalGuard', $preflightIndex)
} else {
    -1
}
if ($preflightIndex -lt 0 -or $guardStartIndex -le $preflightIndex) {
    throw "The device thermal guard must start after the full thermal preflight."
}

$guardStopCount = ([regex]::Matches($macro, '(?m)^\s*Stop-ThorDeviceThermalGuard\s*$')).Count
if ($guardStopCount -lt 2) {
    throw "The input macro must stop the device guard on success and failure."
}

if (-not $route.Contains('ThermalRuntimeTelemetry = "device"')) {
    throw "The Transformers HLE route does not select device thermal telemetry."
}

Write-Output "Thor device thermal guard contract passed."
