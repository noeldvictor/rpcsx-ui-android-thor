param(
    [ValidateSet("HLE", "LLE")]
    [string]$Mode = "HLE",
    [string]$Serial = "192.168.1.3:5555",
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstalledApkSha256,
    [ValidateSet("on", "off")]
    [string]$LfqAny2Any = "on",
    [ValidateSet("on", "off")]
    [string]$SpursSelectorFixes = "on",
    [ValidateSet("on", "off")]
    [string]$TasksetSelectAtomic = "on",
    [ValidateSet("on", "off")]
    [string]$EdgeEventInterp = "on",
    [ValidateSet("on", "off")]
    [string]$TaskAttrFix = "on",
    [ValidateSet("on", "off")]
    [string]$SpuReserve = "on",
    [ValidateSet("on", "off")]
    [string]$StartPaused = "on",
    [ValidateSet("on", "off")]
    [string]$YieldFastPath = "off",
    [ValidateSet("on", "off")]
    [string]$PpuCachedRtimeFix = "on",
    [ValidateSet("on", "off")]
    [string]$SpursProbe = "off",
    [ValidateSet("on", "off")]
    [string]$SpursAtomicCensus = "off",
    [ValidateSet("on", "off")]
    [string]$EdgeTaskCensus = "off",
    [ValidateSet("on", "off")]
    [string]$RuntimeCensus = "off",
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Direct",
    [ValidateRange(1, 4096)]
    [int]$SpuCachePreloadLimit = 64,
    [string]$Macro = "wait:8000;shot:render-boundary;wait:4000;shot:active-draw-boundary;stop"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$adb = Resolve-ThorAdb
$inputMacroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$env:ANDROID_SERIAL = $Serial
$hleLfqAny2Any = if ($Mode -eq "HLE") { $LfqAny2Any } else { "off" }
$hleSpursSelectorFixes = if ($Mode -eq "HLE") { $SpursSelectorFixes } else { "off" }
$hleTasksetSelectAtomic = if ($Mode -eq "HLE") { $TasksetSelectAtomic } else { "off" }

function Set-ThorRenderProbeProperty {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    & $adb -s $Serial shell setprop $Name $Value | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not set Thor property '$Name'."
    }
}

# Keep the measured HLE candidate stack explicit. Enable bounded render probes.
$profileProperties = [ordered]@{
    "debug.rpcsx.thor.hle_libs" = if ($Mode -eq "HLE") { "libsre.sprx" } else { "none" }
    "debug.rpcsx.thor.hle_spurs_kernel" = if ($Mode -eq "HLE") { "1" } else { "0" }
    "debug.rpcsx.thor.real_spu_kernel" = "0"
    "debug.rpcsx.thor.real_taskset_pm" = "0"
    "debug.rpcsx.thor.yield_fast_path" = if ($YieldFastPath -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.ppu_cached_rtime_fix" = if ($PpuCachedRtimeFix -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.pm_capture" = "0"
    "debug.rpcsx.thor.draw_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spurs_atomic_census" = if ($SpursAtomicCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.edge_task_census" = if ($EdgeTaskCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spu_pc_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spu_event_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.edge_event_interp" = if ($Mode -eq "HLE" -and $EdgeEventInterp -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.ppu_pc_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.ppu_call_trace" = "0"
    "debug.rpcsx.thor.spurs_probe" = if ($SpursProbe -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spurs_sel_cond_fix" = "0"
    "debug.rpcsx.thor.spurs_signal_fix" = "0"
    "debug.rpcsx.thor.spurs_always_notify" = "0"
    "debug.rpcsx.thor.task_attr_fix" = if ($TaskAttrFix -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_spu_reserve" = if ($Mode -eq "HLE" -and $SpuReserve -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.start_paused" = if ($StartPaused -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.contention_atomic_fix" = "1"
    "debug.rpcsx.thor.contention_orphan_fix" = "1"
    "debug.rpcsx.thor.pending_contention_fix" = "1"
    "debug.rpcsx.thor.release_idle_taskset" = "1"
    "debug.rpcsx.thor.syscall_dma_wait" = "1"
    "debug.rpcsx.thor.task_ls_clear_fix" = "1"
    "debug.rpcsx.thor.taskset_enabled_fix" = "1"
    "debug.rpcsx.thor.taskset_snapshot_fix" = "1"
    "debug.rpcsx.thor.taskset_syscall_fix" = "1"
    "debug.rpcsx.thor.yield_redispatch_fix" = "1"
}

$macroParameters = [ordered]@{
    Serial = $Serial
    Profile = "custom"
    InputMode = $InputMode
    Macro = $Macro
    GamePath = "/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
    TitleId = "BLUS30357"
    ThermalPreflightSamples = 1
    ThermalPreflightIntervalSeconds = 2
    ThermalPreflightHeadroomC = 0
    MaxLaunchSiliconTemperatureC = 70
    ThermalPreflightMaxRiseC = 1
    ThermalRuntimeTelemetry = "device"
    ThermalRuntimeStopHeadroomC = 0
    ThermalRuntimeProbeWindowC = 2
    MaxBatteryTemperatureC = 34
    MaxSkinTemperatureC = 40
    MaxSiliconTemperatureC = 72
    SpuCachePreloadLimit = $SpuCachePreloadLimit
    SpuCacheCompileBudgetMs = 50
    SpuNativeObjectCache = "on"
    LfqAny2Any = $hleLfqAny2Any
    SpursSelectorFixes = $hleSpursSelectorFixes
    TasksetSelectAtomic = $hleTasksetSelectAtomic
    CacheWorkerAffinityMask = 7
    ExpectedInstalledApkSha256 = $ExpectedInstalledApkSha256.ToUpperInvariant()
    BootGame = $true
    ForceStop = $true
    PostSnapshot = $true
    PassThruCaptureDirectory = $true
}

try {
    foreach ($property in $profileProperties.GetEnumerator()) {
        Set-ThorRenderProbeProperty -Name $property.Key -Value $property.Value
    }

    $captureOutput = @(& $inputMacroPath @macroParameters 6>$null)
} catch {
    $failureCaptureDir = [string]$_.Exception.Data["ThorCaptureDirectory"]
    if (-not [string]::IsNullOrWhiteSpace($failureCaptureDir)) {
        $resolvedFailureCaptureDir = [IO.Path]::GetFullPath($failureCaptureDir)
        throw "Transformers $Mode render probe failed (capture_dir=$resolvedFailureCaptureDir): $($_.Exception.Message)"
    }
    throw
} finally {
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.draw_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_atomic_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_task_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_pc_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_event_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_pc_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_probe" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_interp" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.task_attr_fix" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_spu_reserve" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.start_paused" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.yield_fast_path" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_cached_rtime_fix" -Value "0"
}

$captureCandidates = @(
    $captureOutput |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($captureCandidates.Count -ne 1) {
    throw "Transformers $Mode render probe expected one capture directory, got $($captureCandidates.Count)."
}

$captureDir = $captureCandidates[0]
if (-not (Test-Path -LiteralPath $captureDir -PathType Container)) {
    throw "Transformers $Mode render probe capture does not exist: $captureDir"
}

Write-Output (Resolve-Path -LiteralPath $captureDir).Path
