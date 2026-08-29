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
    [string]$EdgeEventWaitTrace = "off",
    [ValidateSet("on", "off")]
    [string]$RuntimeCensus = "off",
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Direct",
    [ValidateRange(1, 4096)]
    [int]$SpuCachePreloadLimit = 64,
    [string]$Macro = "wait:8000;shot:render-boundary;wait:4000;shot:active-draw-boundary;stop",
    [switch]$SliceLoop,
    [ValidateRange(0.1, 5.0)]
    [double]$SliceSeconds = 1.0,
    [ValidateRange(1, 128)]
    [int]$MaxSlices = 64,
    [ValidateRange(30, 420)]
    [double]$MaxSliceHostSeconds = 240,
    [ValidateRange(2, 300)]
    [int]$SliceCoolTimeoutSeconds = 120,
    [string]$SliceStopMatch = "Thor EDGE EFWAIT EVENT"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$adb = Resolve-ThorAdb
$inputMacroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$thorCallPath = Join-Path $PSScriptRoot "thor_mcp\call.py"
$env:ANDROID_SERIAL = $Serial
$hleLfqAny2Any = if ($Mode -eq "HLE") { $LfqAny2Any } else { "off" }
$hleSpursSelectorFixes = if ($Mode -eq "HLE") { $SpursSelectorFixes } else { "off" }
$hleTasksetSelectAtomic = if ($Mode -eq "HLE") { $TasksetSelectAtomic } else { "off" }

if ($SliceLoop -and $StartPaused -ne "on") {
    throw "The Transformers slice loop requires -StartPaused on."
}

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

function Resolve-ThorRenderProbeCaptureDirectory {
    param([object[]]$Output)

    $captureCandidates = @(
        $Output |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($captureCandidates.Count -ne 1) {
        throw "Transformers $Mode render probe expected one capture directory, got $($captureCandidates.Count)."
    }

    $candidate = $captureCandidates[0]
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "Transformers $Mode render probe capture does not exist: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Invoke-ThorRenderProbeController {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][hashtable]$Arguments,
        [Parameter(Mandatory = $true)][string]$CaptureDir,
        [Parameter(Mandatory = $true)][string]$OutputName,
        [int]$TimeoutSeconds = 600
    )

    $python = Get-Command python -ErrorAction Stop
    $previousSerial = [Environment]::GetEnvironmentVariable("THOR_SERIAL", "Process")
    $previousArgs = [Environment]::GetEnvironmentVariable("THOR_CALL_ARGS", "Process")
    $previousTimeout = [Environment]::GetEnvironmentVariable("THOR_CALL_TIMEOUT", "Process")
    try {
        $env:THOR_SERIAL = $Serial
        $env:THOR_CALL_ARGS = $Arguments | ConvertTo-Json -Depth 8 -Compress
        $env:THOR_CALL_TIMEOUT = "$TimeoutSeconds"
        $controllerOutput = @(& $python.Source $thorCallPath $Name 2>&1)
        $controllerExitCode = $LASTEXITCODE
        $controllerOutput | Set-Content -LiteralPath (Join-Path $CaptureDir $OutputName) -Encoding UTF8
        if ($controllerExitCode -ne 0) {
            throw "Thor controller '$Name' failed with exit code $controllerExitCode."
        }
        return $controllerOutput
    } finally {
        [Environment]::SetEnvironmentVariable("THOR_SERIAL", $previousSerial, "Process")
        [Environment]::SetEnvironmentVariable("THOR_CALL_ARGS", $previousArgs, "Process")
        [Environment]::SetEnvironmentVariable("THOR_CALL_TIMEOUT", $previousTimeout, "Process")
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
    "debug.rpcsx.thor.edge_event_wait_trace" = if ($Mode -eq "HLE" -and $EdgeEventWaitTrace -eq "on") { "1" } else { "0" }
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
    Macro = if ($SliceLoop) { "" } else { $Macro }
    GamePath = "/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
    TitleId = "BLUS30357"
    ThermalPreflightSamples = 1
    ThermalPreflightIntervalSeconds = 2
    ThermalPreflightHeadroomC = 0
    MaxLaunchSiliconTemperatureC = 70
    ThermalPreflightMaxRiseC = 1
    ThermalRuntimeTelemetry = if ($SliceLoop) { "full" } else { "device" }
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
    RequireManagedProfile = "off"
    ReplaceCustomProfile = "off"
    ExpectedInstalledApkSha256 = $ExpectedInstalledApkSha256.ToUpperInvariant()
    BootGame = $true
    ForceStop = $true
    PostSnapshot = $true
    PassThruCaptureDirectory = $true
}

$captureDir = $null
try {
    foreach ($property in $profileProperties.GetEnumerator()) {
        Set-ThorRenderProbeProperty -Name $property.Key -Value $property.Value
    }

    $captureOutput = @(& $inputMacroPath @macroParameters 6>$null)
    $captureDir = Resolve-ThorRenderProbeCaptureDirectory -Output $captureOutput

    if ($SliceLoop) {
        @(
            "",
            "## Paused slice loop",
            "",
            "- Active slice seconds: $SliceSeconds",
            "- Maximum slices: $MaxSlices",
            "- Maximum host seconds: $MaxSliceHostSeconds",
            "- Cool timeout seconds: $SliceCoolTimeoutSeconds",
            "- Stop match: $SliceStopMatch"
        ) | Add-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

        $sliceArguments = @{
            seconds = $SliceSeconds
            maxSlices = $MaxSlices
            maxHostS = $MaxSliceHostSeconds
            coolTimeoutS = $SliceCoolTimeoutSeconds
            maxStartC = 70
            maxSiliconC = 72
            stopMatch = $SliceStopMatch
            markerEvery = 1
        }
        $controllerTimeout = [int][Math]::Ceiling($MaxSliceHostSeconds + 150)
        $null = Invoke-ThorRenderProbeController `
            -Name "thor_slice_loop" `
            -Arguments $sliceArguments `
            -CaptureDir $captureDir `
            -OutputName "slice-loop.json" `
            -TimeoutSeconds $controllerTimeout

        $pidEvidence = Invoke-ThorAdbText $adb $captureDir "slice-loop-pid.txt" @("shell", "pidof net.rpcsx.easy") -AllowFailure
        if (@(Get-ThorEvidenceBody $pidEvidence).Count -gt 0) {
            $screenshotArguments = @{ path = (Join-Path $captureDir "slice-loop-boundary.png") }
            $null = Invoke-ThorRenderProbeController `
                -Name "thor_screenshot" `
                -Arguments $screenshotArguments `
                -CaptureDir $captureDir `
                -OutputName "slice-loop-screenshot.json" `
                -TimeoutSeconds 60
        }
        Write-ThorStandardSnapshot -Adb $adb -CaptureDir $captureDir -Package "net.rpcsx.easy" -Prefix "slice-loop"
    }
} catch {
    $failure = $_
    $failureCaptureDir = if (-not [string]::IsNullOrWhiteSpace($captureDir)) {
        $captureDir
    } else {
        [string]$failure.Exception.Data["ThorCaptureDirectory"]
    }
    if (-not [string]::IsNullOrWhiteSpace($failureCaptureDir)) {
        $resolvedFailureCaptureDir = [IO.Path]::GetFullPath($failureCaptureDir)
        $captureDir = $resolvedFailureCaptureDir
        if ($SliceLoop) {
            try {
                Write-ThorStandardSnapshot -Adb $adb -CaptureDir $resolvedFailureCaptureDir -Package "net.rpcsx.easy" -Prefix "slice-loop-failure"
            } catch {
                $_.ToString() | Set-Content -LiteralPath (Join-Path $resolvedFailureCaptureDir "slice-loop-failure-snapshot-error.txt") -Encoding UTF8
            }
        }
        throw "Transformers $Mode render probe failed (capture_dir=$resolvedFailureCaptureDir): $($failure.Exception.Message)"
    }
    throw $failure
} finally {
    if ($SliceLoop) {
        if (-not [string]::IsNullOrWhiteSpace($captureDir)) {
            try {
                $null = Invoke-ThorRenderProbeController `
                    -Name "thor_stop" `
                    -Arguments @{} `
                    -CaptureDir $captureDir `
                    -OutputName "slice-loop-stop.json" `
                    -TimeoutSeconds 120
            } catch {
                $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "slice-loop-stop-error.txt") -Encoding UTF8
            }
        } else {
            # Keep the failure safe if boot completed but capture-path parsing
            # failed. The normal controller path records and verifies its stop.
            for ($stopAttempt = 1; $stopAttempt -le 5; $stopAttempt++) {
                & $adb -s $Serial shell am force-stop net.rpcsx.easy | Out-Null
                Start-Sleep -Seconds 2
                $remainingPid = [string](& $adb -s $Serial shell pidof net.rpcsx.easy 2>$null)
                $remainingPid = $remainingPid.Trim()
                if ([string]::IsNullOrWhiteSpace($remainingPid)) {
                    break
                }
            }
        }
    }
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.draw_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_atomic_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_task_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_wait_trace" -Value "0"
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
    if ($SliceLoop -and -not [string]::IsNullOrWhiteSpace($captureDir)) {
        try {
            $null = Invoke-ThorRenderProbeController `
                -Name "thor_clearprops" `
                -Arguments @{} `
                -CaptureDir $captureDir `
                -OutputName "slice-loop-clearprops.json" `
                -TimeoutSeconds 60
        } catch {
            $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "slice-loop-clearprops-error.txt") -Encoding UTF8
        }
    }
}

Write-Output $captureDir
