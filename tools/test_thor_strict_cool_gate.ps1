$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$macroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$wrapperPath = Join-Path $repoRoot "tools/invoke_thor_strict_cool_gate.ps1"
$macroSource = Get-Content -LiteralPath $macroPath -Raw
$wrapperSource = Get-Content -LiteralPath $wrapperPath -Raw

foreach ($path in @($macroPath, $wrapperPath)) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) {
        throw "$path has PowerShell parse errors: $($parseErrors.Message -join '; ')"
    }
}

foreach ($fragment in @(
    '[switch]$PassThruCaptureDirectory',
    '"strict-cool-gate" {',
    'if ($Profile -eq "strict-cool-gate")',
    'if ($PassThruCaptureDirectory)',
    'Write-Output $captureDir',
    '"failure-pid.txt" @("shell", "pidof $Package")',
    '$failure.Exception.Data["ThorCaptureDirectory"] = $captureDir'
    'function Assert-ThorStrictColdStartGate'
    '$launchLimitC = 70.0'
    'gate=fixed-silicon-only'
    'if ([double]$snapshot.silicon_temperature_c -ge $launchLimitC)'
    'if ($Profile -eq "strict-cool-gate") {'
    'Assert-ThorStrictColdStartGate "pre-run"'
)) {
    if (-not $macroSource.Contains($fragment)) {
        throw "Thor input macro is missing strict cool-gate contract: $fragment"
    }
}

$strictGuardIndex = $macroSource.IndexOf('if ($Profile -eq "strict-cool-gate")')
$adbResolutionIndex = $macroSource.IndexOf('$Adb = Resolve-ThorAdb')
if ($strictGuardIndex -lt 0 -or $adbResolutionIndex -le $strictGuardIndex) {
    throw "Strict cool-gate validation must run before ADB resolution."
}

$requiredWrapperFragments = @(
    '[ValidateSet("Status", "Run")]',
    '[string]$Action = "Status"',
    'Profile = "strict-cool-gate"',
    'ForceStop = $true',
    'ThermalPreflightSamples = 1',
    'ThermalPreflightIntervalSeconds = 2',
    'ThermalPreflightHeadroomC = 0',
    'MaxLaunchSiliconTemperatureC = 70',
    'ThermalPreflightMaxRiseC = 1',
    'MaxBatteryTemperatureC = 34',
    'MaxSkinTemperatureC = 40',
    'MaxSiliconTemperatureC = 72',
    '-PassThruCaptureDirectory',
    '6>$null',
    '"README.md", "thermal-guard.log"',
    '$_.Exception.Data["ThorCaptureDirectory"]',
    'Strict cool gate failed (capture_dir='
)
foreach ($fragment in $requiredWrapperFragments) {
    if (-not $wrapperSource.Contains($fragment)) {
        throw "Strict cool-gate wrapper is missing: $fragment"
    }
}

if ($wrapperSource -match '(?i)\bam\s+start\b|\bmonkey\b|-BootGame\b') {
    throw "Strict cool-gate wrapper contains an emulator activity-launch path."
}

$bootRejected = $false
try {
    & $macroPath -Profile strict-cool-gate -BootGame -ForceStop 2>&1 | Out-Null
} catch {
    $bootRejected = $_.Exception.Message -like '*strict-cool-gate profile forbids -BootGame*'
}
if (-not $bootRejected) {
    throw "Strict cool-gate profile did not reject -BootGame before device resolution."
}

$stopRejected = $false
try {
    & $macroPath -Profile strict-cool-gate 2>&1 | Out-Null
} catch {
    $stopRejected = $_.Exception.Message -like '*strict-cool-gate profile requires -ForceStop*'
}
if (-not $stopRejected) {
    throw "Strict cool-gate profile did not require -ForceStop before device resolution."
}

$status = @(& $wrapperPath -Action Status 2>&1 | ForEach-Object { $_.ToString() })
foreach ($line in @(
    'action=Status',
    'device_contact=False',
    'serial=c3ca0370',
    'profile=strict-cool-gate',
    'boot_game=False',
    'force_stop=True',
    'preflight_samples=1',
    'preflight_interval_seconds=2',
    'preflight_headroom_c=0',
    'max_launch_silicon_c=70',
    'max_preflight_rise_c=1',
    'max_battery_c=34',
    'max_skin_c=40',
    'max_silicon_c=72',
    'pass_thru_capture_directory=True'
)) {
    if ($status -notcontains $line) {
        throw "Strict cool-gate host-only status is missing: $line"
    }
}

Write-Output "Thor strict cool-gate contract passed: one fixed-silicon sample below 70 C can run, other temperatures do not decide launch, Run is no-boot/force-stop, and success/failure capture output is machine-readable with post-stop PID evidence."
