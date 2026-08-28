param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("HLE", "LLE")]
    [string]$Mode,
    [string]$Serial = "192.168.1.3:5555",
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstalledApkSha256
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$adb = Resolve-ThorAdb
$inputMacroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$env:ANDROID_SERIAL = $Serial

function Set-ThorProbeProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    & $adb -s $Serial shell setprop $Name $Value | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set Thor property '$Name'."
    }
}

$profileProperties = [ordered]@{
    "debug.rpcsx.thor.hle_libs" = if ($Mode -eq "HLE") { "libsre.sprx" } else { "none" }
    "debug.rpcsx.thor.hle_spurs_kernel" = if ($Mode -eq "HLE") { "1" } else { "0" }
    "debug.rpcsx.thor.real_spu_kernel" = "0"
    "debug.rpcsx.thor.real_taskset_pm" = "0"
    "debug.rpcsx.thor.yield_fast_path" = "0"
    "debug.rpcsx.thor.pm_capture" = "0"
    "debug.rpcsx.thor.draw_census" = "0"
    "debug.rpcsx.thor.ppu_pc_census" = "0"
    "debug.rpcsx.thor.ppu_call_trace" = "6"
    "debug.rpcsx.thor.spurs_probe" = "0"
    "debug.rpcsx.thor.spurs_sel_cond_fix" = "0"
    "debug.rpcsx.thor.spurs_signal_fix" = "0"
}

foreach ($property in $profileProperties.GetEnumerator()) {
    Set-ThorProbeProperty -Name $property.Key -Value $property.Value
}

$macroParameters = [ordered]@{
    Serial = $Serial
    Profile = "custom"
    Macro = "wait:10000;stop"
    GamePath = "/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
    TitleId = "BLUS30357"
    ThermalPreflightSamples = 3
    ThermalPreflightIntervalSeconds = 2
    ThermalPreflightHeadroomC = 0
    MaxLaunchSiliconTemperatureC = 35
    ThermalPreflightMaxRiseC = 1
    ThermalRuntimeProbeWindowC = 12
    MaxBatteryTemperatureC = 34
    MaxSkinTemperatureC = 40
    MaxSiliconTemperatureC = 72
    SpuNativeObjectCache = "on"
    ExpectedInstalledApkSha256 = $ExpectedInstalledApkSha256.ToUpperInvariant()
    BootGame = $true
    ForceStop = $true
    PassThruCaptureDirectory = $true
}

try {
    $captureOutput = @(& $inputMacroPath @macroParameters 6>$null)
} catch {
    $failureCaptureDir = [string]$_.Exception.Data["ThorCaptureDirectory"]
    if (-not [string]::IsNullOrWhiteSpace($failureCaptureDir)) {
        $resolvedFailureCaptureDir = [IO.Path]::GetFullPath($failureCaptureDir)
        throw "Transformers $Mode counter probe failed (capture_dir=$resolvedFailureCaptureDir): $($_.Exception.Message)"
    }
    throw
} finally {
    Set-ThorProbeProperty -Name "debug.rpcsx.thor.ppu_call_trace" -Value "0"
}

$captureCandidates = @(
    $captureOutput |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($captureCandidates.Count -ne 1) {
    throw "Transformers $Mode counter probe expected one capture directory, got $($captureCandidates.Count)."
}

$captureDir = $captureCandidates[0]
if (-not (Test-Path -LiteralPath $captureDir -PathType Container)) {
    throw "Transformers $Mode counter probe capture does not exist: $captureDir"
}

Write-Output (Resolve-Path -LiteralPath $captureDir).Path
