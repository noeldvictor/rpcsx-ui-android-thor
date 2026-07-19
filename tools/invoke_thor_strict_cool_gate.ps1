param(
    [ValidateSet("Status", "Run")]
    [string]$Action = "Status",
    [string]$Serial = "c3ca0370"
)

$ErrorActionPreference = "Stop"

$inputMacroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$gateParameters = [ordered]@{
    Serial = $Serial
    Profile = "strict-cool-gate"
    ForceStop = $true
    ThermalPreflightSamples = 3
    ThermalPreflightIntervalSeconds = 2
    ThermalPreflightHeadroomC = 0
    MaxLaunchSiliconTemperatureC = 35
    ThermalPreflightMaxRiseC = 1
    MaxBatteryTemperatureC = 34
    MaxSkinTemperatureC = 40
    MaxSiliconTemperatureC = 72
}

if ($Action -eq "Status") {
    @(
        "action=Status",
        "device_contact=False",
        "serial=$Serial",
        "profile=strict-cool-gate",
        "boot_game=False",
        "force_stop=True",
        "preflight_samples=3",
        "preflight_interval_seconds=2",
        "preflight_headroom_c=0",
        "max_launch_silicon_c=35",
        "max_preflight_rise_c=1",
        "max_battery_c=34",
        "max_skin_c=40",
        "max_silicon_c=72",
        "pass_thru_capture_directory=True"
    ) | Write-Output
    return
}

$captureOutput = @(& $inputMacroPath @gateParameters -PassThruCaptureDirectory)
$captureCandidates = @(
    $captureOutput |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($captureCandidates.Count -ne 1) {
    throw "Strict cool gate expected one machine-readable capture directory, got $($captureCandidates.Count)."
}

$captureDir = $captureCandidates[0]
if (-not (Test-Path -LiteralPath $captureDir -PathType Container)) {
    throw "Strict cool gate capture directory was not created: $captureDir"
}
foreach ($requiredFile in @("README.md", "thermal-guard.log")) {
    if (-not (Test-Path -LiteralPath (Join-Path $captureDir $requiredFile) -PathType Leaf)) {
        throw "Strict cool gate capture is incomplete: missing $requiredFile in $captureDir"
    }
}

Write-Output (Resolve-Path -LiteralPath $captureDir).Path
