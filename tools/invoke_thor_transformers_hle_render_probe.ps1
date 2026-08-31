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
    [string]$QueuePublishOrder = "on",
    [ValidateSet("on", "off")]
    [string]$QueueDiagnostics = "off",
    [ValidateSet(1, 2, 4, 8, 16, 32, 64)]
    [int]$YieldRedispatchEvery = 1,
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
    [string]$FmodEventWaitTrace = "off",
    [ValidateSet("on", "off")]
    [string]$FmodEventInterp = "on",
    [ValidateSet("on", "off")]
    [string]$FmodAudioWakeFix = "on",
    [ValidateSet("on", "off")]
    [string]$PhysxQueueWait = "on",
    [ValidateSet("on", "off")]
    [string]$PhysxStartInterp = "on",
    [ValidateSet("on", "off")]
    [string]$PhysxLsDump = "off",
    [ValidateSet("on", "off")]
    [string]$RsxFifoOrdered = "off",
    [ValidateSet("on", "off")]
    [string]$LwmutexTrace = "off",
    [ValidateSet("on", "off")]
    [string]$RuntimeCensus = "off",
    [ValidateSet("on", "off")]
    [string]$SpuPcCensus = "off",
    [ValidateSet("on", "off")]
    [string]$PpuPcCensus = "off",
    [ValidateSet("on", "off")]
    [string]$PpuProfiler = "off",
    [ValidateSet(10, 25, 50, 100, 200, 400)]
    [int]$RenderPollUs = 400,
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Direct",
    [ValidateRange(1, 4096)]
    [int]$SpuCachePreloadLimit = 64,
    [string]$Macro = "wait:8000;shot:render-boundary;wait:4000;shot:active-draw-boundary;stop",
    [switch]$SliceLoop,
    [ValidateRange(0.1, 15.0)]
    [double]$SliceSeconds = 1.0,
    [ValidateRange(1, 256)]
    [int]$MaxSlices = 64,
    [ValidateRange(30, 600)]
    [double]$MaxSliceHostSeconds = 240,
    [ValidateRange(2, 300)]
    [int]$SliceCoolTimeoutSeconds = 120,
    [ValidateRange(1, 5)]
    [int]$SliceResumeStableSamples = 3,
    [ValidateRange(0.25, 5.0)]
    [double]$SliceResumeSampleIntervalSeconds = 1.0,
    [string]$SliceStopMatch = "Thor LATE LOAD IO COMPLETION: sample=2",
    [string]$SliceArmMatch = "",
    [ValidateRange(0, 64)]
    [int]$SlicePostArmSlices = 0,
    [switch]$SlicePressStartAfterFirstLoop,
    [ValidateRange(0.0, 15.0)]
    [double]$SliceAfterStartSeconds = 0.0,
    [ValidateRange(1, 256)]
    [int]$SliceAfterStartMaxSlices = 32,
    [ValidateRange(30, 600)]
    [double]$SliceAfterStartMaxHostSeconds = 240,
    [string]$SliceAfterStartHandoffMatch = 'Thread "PPU PhysX thread" created',
    [string]$SliceAfterStartDiagnosticMatch = 'stage=PRE-SCHEDULE-SCAN',
    [string]$SliceAfterStartFailureMatch = 'stage=REPAIR-SELF-CYCLE',
    [string]$SliceAfterStartDeadOwnerMatch = 'owner=0x100000c owner_live=0',
    [string]$SliceAfterStartDiagnosticStopMatch = 'stage=POST-FETCH',
    [ValidateRange(0.0, 300.0)]
    [double]$SliceAfterHandoffSeconds = 30.0,
    [ValidateRange(1, 256)]
    [int]$SliceAfterHandoffMaxSlices = 32,
    [ValidateRange(30, 600)]
    [double]$SliceAfterHandoffMaxHostSeconds = 240,
    [string]$SliceAfterStartStopMatch = "Thor Transformers PhysX queue startup wait:",
    [ValidateRange(0, 64)]
    [int]$SliceAfterStartPostMarkerSlices = 0
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$deadOwnerMatches = @(
    $SliceAfterStartFailureMatch,
    $SliceAfterStartDeadOwnerMatch
) | Where-Object { $_ -match 'owner_live=0' }
foreach ($deadOwnerMatch in $deadOwnerMatches) {
    if ($deadOwnerMatch -notmatch 'owner=0x100000c') {
        throw "An after-START dead-owner marker must include owner=0x100000c. The reserved owner is a normal handoff value."
    }
}

$adb = Resolve-ThorAdb
$inputMacroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$thorCallPath = Join-Path $PSScriptRoot "thor_mcp\call.py"
$transformersStartCheckPath = Join-Path $PSScriptRoot "bench\thor_transformers_start_check.py"
$env:ANDROID_SERIAL = $Serial
$hleLfqAny2Any = if ($Mode -eq "HLE") { $LfqAny2Any } else { "off" }
$hleSpursSelectorFixes = if ($Mode -eq "HLE") { $SpursSelectorFixes } else { "off" }
$hleTasksetSelectAtomic = if ($Mode -eq "HLE") { $TasksetSelectAtomic } else { "off" }
$effectiveAfterStartSliceSeconds = if ($SliceAfterStartSeconds -gt 0.0) {
    $SliceAfterStartSeconds
} else {
    $SliceSeconds
}
$effectiveAfterHandoffSliceSeconds = if ($SliceAfterHandoffSeconds -gt 0.0) {
    $SliceAfterHandoffSeconds
} else {
    $effectiveAfterStartSliceSeconds
}

if ($SliceLoop -and $StartPaused -ne "on") {
    throw "The Transformers slice loop requires -StartPaused on."
}

if ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on" -and
        [string]::IsNullOrWhiteSpace($SliceArmMatch) -and
        -not $PSBoundParameters.ContainsKey("SliceStopMatch")) {
    $SliceStopMatch = "Thor FMOD EFWAIT RETURN #0"
}

if ($SliceLoop -and $SliceStopMatch.StartsWith("Thor LATE LOAD") -and
        $RuntimeCensus -ne "on" -and $PpuPcCensus -ne "on") {
    throw "A late-load slice marker requires -PpuPcCensus on or -RuntimeCensus on."
}

if ($SliceLoop -and $SlicePostArmSlices -gt 0 -and [string]::IsNullOrWhiteSpace($SliceArmMatch)) {
    throw "Post-arm slices require -SliceArmMatch."
}

if ($SlicePressStartAfterFirstLoop -and -not $SliceLoop) {
    throw "The slice START handoff requires -SliceLoop."
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

function Test-ThorTransformersStartFrame {
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [Parameter(Mandatory = $true)][string]$CaptureDir,
        [Parameter(Mandatory = $true)][string]$OutputName
    )

    $checkOutput = @(& python $transformersStartCheckPath --image $ImagePath 2>&1)
    $checkExitCode = $LASTEXITCODE
    $checkOutput | Set-Content -LiteralPath (Join-Path $CaptureDir $OutputName) -Encoding UTF8
    if ($checkExitCode -eq 2) {
        throw "The Transformers START-frame check could not score '$ImagePath'."
    }
    return $checkExitCode -eq 0
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

$script:ThorSliceDeviceGuardPowerShell = $null
$script:ThorSliceDeviceGuardAsync = $null
$script:ThorSliceDeviceGuardText = $null
$script:ThorSliceDeviceGuardOutput = $null
$script:ThorSliceDeviceGuardError = $null
$script:ThorSliceDeviceGuardReady = $null

function Complete-ThorSliceDeviceGuard {
    if ($null -ne $script:ThorSliceDeviceGuardText) {
        return $script:ThorSliceDeviceGuardText
    }
    if ($null -eq $script:ThorSliceDeviceGuardPowerShell) {
        return ""
    }

    $outputLines = @()
    try {
        $outputLines = @(
            $script:ThorSliceDeviceGuardPowerShell.EndInvoke($script:ThorSliceDeviceGuardAsync) |
                ForEach-Object { $_.ToString() }
        )
    } catch {
        $outputLines += "status=host-completion-error message=$($_.Exception.Message)"
    }
    $errorLines = @(
        $script:ThorSliceDeviceGuardPowerShell.Streams.Error |
            ForEach-Object { $_.ToString() }
    )
    $outputLines | Set-Content -LiteralPath $script:ThorSliceDeviceGuardOutput -Encoding UTF8
    $errorLines | Set-Content -LiteralPath $script:ThorSliceDeviceGuardError -Encoding UTF8
    $script:ThorSliceDeviceGuardText = ($outputLines -join [Environment]::NewLine).Trim()
    return $script:ThorSliceDeviceGuardText
}

function Start-ThorSliceDeviceGuard {
    param([Parameter(Mandatory = $true)][string]$CaptureDir)

    $localGuard = Join-Path $PSScriptRoot "thor_device_thermal_guard.sh"
    $remoteGuard = "/data/local/tmp/rpcsx-thor-thermal-guard.sh"
    $script:ThorSliceDeviceGuardReady = "/data/local/tmp/rpcsx-thor-slice-guard-$PID.ready"
    Invoke-ThorAdbText $adb $CaptureDir "slice-device-thermal-guard-push.txt" @("push", $localGuard, $remoteGuard) | Out-Null
    & $adb -s $Serial shell rm -f $script:ThorSliceDeviceGuardReady | Out-Null

    $script:ThorSliceDeviceGuardOutput = Join-Path $CaptureDir "slice-device-thermal-guard.log"
    $script:ThorSliceDeviceGuardError = Join-Path $CaptureDir "slice-device-thermal-guard.stderr.log"
    $guardArguments = @(
        "-s", $Serial, "shell", "sh", $remoteGuard, "net.rpcsx.easy",
        "68000", "72000", "95000", "34000", "40",
        $script:ThorSliceDeviceGuardReady, "0.25", "hold", "4"
    )

    $script:ThorSliceDeviceGuardPowerShell = [PowerShell]::Create()
    $null = $script:ThorSliceDeviceGuardPowerShell.AddCommand($adb)
    foreach ($argument in $guardArguments) {
        $null = $script:ThorSliceDeviceGuardPowerShell.AddArgument([string]$argument)
    }
    $script:ThorSliceDeviceGuardAsync = $script:ThorSliceDeviceGuardPowerShell.BeginInvoke()

    $ready = $false
    for ($attempt = 1; $attempt -le 40; $attempt++) {
        if ($script:ThorSliceDeviceGuardAsync.IsCompleted) {
            $guardText = Complete-ThorSliceDeviceGuard
            & $adb -s $Serial shell am force-stop net.rpcsx.easy | Out-Null
            throw "The slice device thermal guard exited before it became ready: $guardText"
        }
        & $adb -s $Serial shell test -f $script:ThorSliceDeviceGuardReady 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) {
        & $adb -s $Serial shell am force-stop net.rpcsx.easy | Out-Null
        throw "The slice device thermal guard did not become ready within its bounded wait."
    }
    Invoke-ThorAdbText $adb $CaptureDir "slice-device-thermal-guard-ready.txt" @("shell", "cat $($script:ThorSliceDeviceGuardReady)") | Out-Null
}

function Stop-ThorSliceDeviceGuard {
    if ($null -eq $script:ThorSliceDeviceGuardPowerShell) {
        return
    }
    if (-not $script:ThorSliceDeviceGuardAsync.IsCompleted) {
        $script:ThorSliceDeviceGuardAsync.AsyncWaitHandle.WaitOne(5000) | Out-Null
    }
    if (-not $script:ThorSliceDeviceGuardAsync.IsCompleted) {
        $script:ThorSliceDeviceGuardPowerShell.Stop()
    }
    Complete-ThorSliceDeviceGuard | Out-Null
    $script:ThorSliceDeviceGuardPowerShell.Dispose()
    if (-not [string]::IsNullOrWhiteSpace($script:ThorSliceDeviceGuardReady)) {
        & $adb -s $Serial shell rm -f $script:ThorSliceDeviceGuardReady | Out-Null
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
    "debug.rpcsx.thor.fmod_event_wait_trace" = if ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.fmod_event_interp" = if ($Mode -eq "HLE" -and $FmodEventInterp -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_audio_wake_fix" = if ($Mode -eq "HLE" -and $FmodAudioWakeFix -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_physx_queue_wait" = if ($Mode -eq "HLE" -and $PhysxQueueWait -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_physx_start_interp" = if ($Mode -eq "HLE" -and $PhysxStartInterp -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_fifo_ordered" = if ($Mode -eq "HLE" -and $RsxFifoOrdered -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_lwmutex_trace" = if ($Mode -eq "HLE" -and $LwmutexTrace -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spu_ls_dump" = if ($Mode -eq "HLE" -and $PhysxLsDump -eq "on") { "@physx" } elseif ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on") { "@fmod" } else { "0" }
    "debug.rpcsx.thor.spu_pc_census" = if ($RuntimeCensus -eq "on" -or $SpuPcCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spu_event_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.edge_event_interp" = if ($Mode -eq "HLE" -and $EdgeEventInterp -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.ppu_pc_census" = if ($RuntimeCensus -eq "on" -or $PpuPcCensus -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.ppu_prof" = if ($PpuProfiler -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.tf_render_poll_us" = "$RenderPollUs"
    "debug.rpcsx.thor.ppu_call_trace" = "0"
    "debug.rpcsx.thor.spurs_probe" = if ($SpursProbe -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.spurs_sel_cond_fix" = "0"
    "debug.rpcsx.thor.spurs_signal_fix" = "0"
    "debug.rpcsx.thor.spurs_always_notify" = "0"
    "debug.rpcsx.thor.task_attr_fix" = if ($TaskAttrFix -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.transformers_spu_reserve" = if ($Mode -eq "HLE" -and $SpuReserve -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.start_paused" = if ($StartPaused -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.queue_publish_order" = if ($Mode -eq "HLE" -and $QueuePublishOrder -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.queue_diagnostics" = if ($Mode -eq "HLE" -and $QueueDiagnostics -eq "on") { "1" } else { "0" }
    "debug.rpcsx.thor.contention_atomic_fix" = "1"
    "debug.rpcsx.thor.contention_orphan_fix" = "1"
    "debug.rpcsx.thor.pending_contention_fix" = "1"
    "debug.rpcsx.thor.release_idle_taskset" = "1"
    "debug.rpcsx.thor.syscall_dma_wait" = "1"
    "debug.rpcsx.thor.task_ls_clear_fix" = "1"
    "debug.rpcsx.thor.taskset_enabled_fix" = "1"
    "debug.rpcsx.thor.taskset_snapshot_fix" = "1"
    "debug.rpcsx.thor.taskset_syscall_fix" = "1"
    "debug.rpcsx.thor.yield_redispatch_fix" = "$YieldRedispatchEvery"
}

# The input macro owns its launch properties and clears them when it returns.
# A normal macro keeps running until the title stops, but an empty slice-loop
# macro returns while the preserved process is still in startup. Reapply every
# route property here so delayed SPU initialization sees the requested cache
# and HLE controls for the full process lifetime.
$sliceLoopProperties = [ordered]@{}
foreach ($property in $profileProperties.GetEnumerator()) {
    $sliceLoopProperties[$property.Key] = [string]$property.Value
}
$sliceLoopProperties["debug.rpcsx.thor.spu_cache_preload_limit"] = "$SpuCachePreloadLimit"
$sliceLoopProperties["debug.rpcsx.thor.spu_cache_compile_budget_ms"] = "50"
$sliceLoopProperties["debug.rpcsx.thor.spu_native_object_cache"] = "on"
$sliceLoopProperties["debug.rpcsx.thor.cache_worker_affinity_mask"] = "7"
$sliceLoopProperties["debug.rpcsx.thor.lfq_any2any"] = if ($hleLfqAny2Any -eq "on") { "1" } else { "0" }
$sliceLoopProperties["debug.rpcsx.thor.spurs_sel_cond_fix"] = if ($hleSpursSelectorFixes -eq "on") { "1" } else { "0" }
$sliceLoopProperties["debug.rpcsx.thor.spurs_signal_fix"] = if ($hleSpursSelectorFixes -eq "on") { "1" } else { "0" }
$sliceLoopProperties["debug.rpcsx.thor.taskset_select_atomic"] = if ($hleTasksetSelectAtomic -eq "on") { "1" } else { "0" }

function Set-ThorRenderProbeSliceProfile {
    param([Parameter(Mandatory = $true)][string]$CaptureDir)

    foreach ($property in $sliceLoopProperties.GetEnumerator()) {
        Set-ThorRenderProbeProperty -Name $property.Key -Value $property.Value
    }

    $propertyNames = @($sliceLoopProperties.Keys)
    $readbackCommand = 'for p in ' + ($propertyNames -join ' ') + '; do printf "%s=%s\n" "$p" "$(getprop "$p")"; done'
    $readbackPath = Invoke-ThorAdbText $adb $CaptureDir "slice-loop-profile-effective.txt" @("shell", $readbackCommand)
    $effective = @{}
    foreach ($line in Get-Content -LiteralPath $readbackPath) {
        if ($line.StartsWith("#")) {
            continue
        }
        if ($line -match '^([^=\s]+)=(.*)$') {
            $effective[$Matches[1]] = $Matches[2]
        }
    }

    foreach ($property in $sliceLoopProperties.GetEnumerator()) {
        $actual = if ($effective.ContainsKey($property.Key)) { [string]$effective[$property.Key] } else { "<missing>" }
        if ($actual -cne [string]$property.Value) {
            & $adb -s $Serial shell am force-stop net.rpcsx.easy | Out-Null
            throw "Thor slice-loop property '$($property.Key)' read back as '$actual', expected '$($property.Value)'. RPCSX was force-stopped."
        }
    }
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
        Set-ThorRenderProbeSliceProfile -CaptureDir $captureDir
        Start-ThorSliceDeviceGuard -CaptureDir $captureDir
        @(
            "",
            "## Paused slice loop",
            "",
            "- Active slice seconds: $SliceSeconds",
            "- Maximum slices: $MaxSlices",
            "- Maximum host seconds: $MaxSliceHostSeconds",
            "- Cool timeout seconds: $SliceCoolTimeoutSeconds",
            "- Active slice start ceiling C: 68",
            "- Runtime slice resume target C: 68",
            "- Runtime resume stable samples: $SliceResumeStableSamples",
            "- Runtime resume sample interval seconds: $SliceResumeSampleIntervalSeconds",
            "- Slice-loop property readback: slice-loop-profile-effective.txt",
            "- Device watchdog hold C: 68",
            "- Device watchdog poll interval seconds: 0.25",
            "- Stop match: $SliceStopMatch",
            "- Arm match: $SliceArmMatch",
            "- Post-arm slices: $SlicePostArmSlices",
            "- Press START after the first loop: $SlicePressStartAfterFirstLoop",
            "- START frame gate: Unreal and PhysX legal frame",
            "- Bounded queue payload diagnostics: $QueueDiagnostics",
            "- After-START active slice seconds: $effectiveAfterStartSliceSeconds",
            "- After-START maximum slices: $SliceAfterStartMaxSlices",
            "- After-START maximum host seconds: $SliceAfterStartMaxHostSeconds",
            "- After-START handoff marker: $SliceAfterStartHandoffMatch",
            "- After-START diagnostic marker: $SliceAfterStartDiagnosticMatch",
            "- After-START diagnostic result: $SliceAfterStartDiagnosticStopMatch",
            "- After-handoff active slice seconds: $effectiveAfterHandoffSliceSeconds",
            "- After-handoff maximum slices: $SliceAfterHandoffMaxSlices",
            "- After-handoff maximum host seconds: $SliceAfterHandoffMaxHostSeconds",
            "- After-START marker: $SliceAfterStartStopMatch",
            "- After-START post-marker slices: $SliceAfterStartPostMarkerSlices"
        ) | Add-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

        $sliceArguments = @{
            seconds = $SliceSeconds
            maxSlices = $MaxSlices
            maxHostS = $MaxSliceHostSeconds
            coolTimeoutS = $SliceCoolTimeoutSeconds
            maxStartC = 68
            resumeTargetC = 68
            resumeStableSamples = $SliceResumeStableSamples
            resumeSampleIntervalS = $SliceResumeSampleIntervalSeconds
            maxSiliconC = 72
            stopMatch = $SliceStopMatch
            markerEvery = 1
            allowStarting = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($SliceArmMatch)) {
            $sliceArguments.armMatch = $SliceArmMatch
            $sliceArguments.postArmSlices = $SlicePostArmSlices
        }
        if ($SlicePressStartAfterFirstLoop) {
            $startGateWatch = [Diagnostics.Stopwatch]::StartNew()
            $startReady = $false
            $sliceResult = $null
            for ($startCheck = 1; $startCheck -le $MaxSlices; $startCheck++) {
                if ($startGateWatch.Elapsed.TotalSeconds -ge $MaxSliceHostSeconds) {
                    break
                }

                $startGateArguments = @{}
                foreach ($entry in $sliceArguments.GetEnumerator()) {
                    $startGateArguments[$entry.Key] = $entry.Value
                }
                $startGateArguments.maxSlices = 1
                $startGateArguments.maxHostS = [Math]::Min(
                    600,
                    [Math]::Max(30, $SliceCoolTimeoutSeconds + $SliceSeconds + 30)
                )
                $startGateArguments.stopMatch = "__THOR_TRANSFORMERS_START_GATE_UNREACHED__"
                $startGateArguments.Remove("armMatch")
                $startGateArguments.Remove("postArmSlices")

                $startIndex = "{0:D2}" -f $startCheck
                $startGateControllerTimeout = [int][Math]::Ceiling($startGateArguments.maxHostS + 90)
                $controllerOutput = Invoke-ThorRenderProbeController `
                    -Name "thor_slice_loop" `
                    -Arguments $startGateArguments `
                    -CaptureDir $captureDir `
                    -OutputName "slice-loop-before-start-$startIndex.json" `
                    -TimeoutSeconds $startGateControllerTimeout
                $sliceResult = ($controllerOutput -join [Environment]::NewLine) | ConvertFrom-Json
                if ($sliceResult.error -or $sliceResult.refused -or
                        $sliceResult.thermalStop -or $sliceResult.fatal -or
                        -not $sliceResult.paused) {
                    throw "The START visual gate did not end at a controlled pause."
                }

                $preStartScreenshotPath = Join-Path $captureDir "slice-loop-before-start-$startIndex.png"
                $null = Invoke-ThorRenderProbeController `
                    -Name "thor_screenshot" `
                    -Arguments @{ path = $preStartScreenshotPath } `
                    -CaptureDir $captureDir `
                    -OutputName "slice-loop-before-start-$startIndex-screenshot.json" `
                    -TimeoutSeconds 60
                $startReady = Test-ThorTransformersStartFrame `
                    -ImagePath $preStartScreenshotPath `
                    -CaptureDir $captureDir `
                    -OutputName "slice-loop-before-start-$startIndex-check.json"
                if ($startReady) {
                    break
                }
            }
            $startGateWatch.Stop()
            if (-not $startReady) {
                throw "The START visual gate did not find the Unreal and PhysX legal frame."
            }

            $startCoolOutput = Invoke-ThorRenderProbeController `
                -Name "thor_wait_cool_paused" `
                -Arguments @{
                    targetC = 65
                    maxSiliconC = 72
                    timeoutS = $SliceCoolTimeoutSeconds
                    stableSamples = 2
                    sampleIntervalS = 0.5
                } `
                -CaptureDir $captureDir `
                -OutputName "slice-loop-before-start-cool.json" `
                -TimeoutSeconds ($SliceCoolTimeoutSeconds + 60)
            $startCoolResult = ($startCoolOutput -join [Environment]::NewLine) | ConvertFrom-Json
            if ($startCoolResult.error -or $startCoolResult.refused -or
                    $startCoolResult.thermalStop -or
                    -not $startCoolResult.cooled -or -not $startCoolResult.paused) {
                throw "The START handoff did not cool to its controlled pause boundary."
            }

            $pressOutput = Invoke-ThorRenderProbeController `
                -Name "thor_press" `
                -Arguments @{
                    buttons = "START"
                    ms = 150
                    settleS = 0.5
                    rePause = $true
                    maxStartC = 68
                    maxSiliconC = 72
                } `
                -CaptureDir $captureDir `
                -OutputName "slice-loop-start-press.json" `
                -TimeoutSeconds 60
            $pressResult = ($pressOutput -join [Environment]::NewLine) | ConvertFrom-Json
            if ($pressResult.error -or $pressResult.thermalStop -or
                    $pressResult.refused -or
                    -not $pressResult.wasPaused -or -not $pressResult.rePaused) {
                throw "The cooled START handoff did not complete at a paused thermal-safe boundary."
            }

            $afterStartArguments = @{}
            foreach ($entry in $sliceArguments.GetEnumerator()) {
                $afterStartArguments[$entry.Key] = $entry.Value
            }
            $afterStartArguments.seconds = $effectiveAfterStartSliceSeconds
            $afterStartArguments.maxSlices = $SliceAfterStartMaxSlices
            $afterStartArguments.maxHostS = $SliceAfterStartMaxHostSeconds
            $afterStartArguments.Remove("armMatch")
            $afterStartArguments.Remove("postArmSlices")

            if (-not [string]::IsNullOrWhiteSpace($SliceAfterStartHandoffMatch)) {
                $afterStartArguments.Remove("stopMatch")
                $afterStartArguments.stopMatches = @(
                    @(
                        $SliceAfterStartFailureMatch,
                        $SliceAfterStartDeadOwnerMatch,
                        $SliceAfterStartDiagnosticMatch,
                        $SliceAfterStartHandoffMatch
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
                $handoffControllerTimeout = [int][Math]::Ceiling($SliceAfterStartMaxHostSeconds + 150)
                $handoffOutput = Invoke-ThorRenderProbeController `
                    -Name "thor_slice_loop" `
                    -Arguments $afterStartArguments `
                    -CaptureDir $captureDir `
                    -OutputName "slice-loop-after-start-handoff.json" `
                    -TimeoutSeconds $handoffControllerTimeout
                $handoffResult = ($handoffOutput -join [Environment]::NewLine) | ConvertFrom-Json
                if ($handoffResult.error -or $handoffResult.refused -or
                        $handoffResult.thermalStop -or $handoffResult.fatal -or
                        -not $handoffResult.markerReached -or -not $handoffResult.paused) {
                    throw "The after-START handoff loop did not reach its requested paused marker."
                }

                $matchedHandoff = [string]$handoffResult.matchedStopMatch
                $failureHandoffs = @(
                    $SliceAfterStartFailureMatch,
                    $SliceAfterStartDeadOwnerMatch
                ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $failedSourceRepair = $failureHandoffs -ccontains $matchedHandoff
                if ($failedSourceRepair) {
                    throw "The after-START source repair reached a proven failure marker."
                }

                $diagnosticHandoff = (
                    -not [string]::IsNullOrWhiteSpace($SliceAfterStartDiagnosticMatch) -and
                    $matchedHandoff -ceq $SliceAfterStartDiagnosticMatch
                )
                $afterStartArguments.Remove("stopMatches")
                if ($diagnosticHandoff) {
                    # Give the exact diagnostic one normal slice. A missing
                    # POST-FETCH row then bounds the internal atomic suspect.
                    $afterStartArguments.seconds = $effectiveAfterStartSliceSeconds
                    $afterStartArguments.Remove("maxDurationS")
                    $afterStartArguments.maxSlices = 1
                    $afterStartArguments.maxHostS = 60
                    $effectiveAfterStartStopMatch = $SliceAfterStartDiagnosticStopMatch
                } else {
                    $afterStartArguments.seconds = $effectiveAfterHandoffSliceSeconds
                    if ($effectiveAfterHandoffSliceSeconds -gt 15.0) {
                        # Use one continuous window only after the exact handoff.
                        # Both fixed-silicon guards stay active during this window.
                        $afterStartArguments.maxDurationS = $effectiveAfterHandoffSliceSeconds
                    }
                    $afterStartArguments.maxSlices = $SliceAfterHandoffMaxSlices
                    $afterStartArguments.maxHostS = $SliceAfterHandoffMaxHostSeconds
                    $effectiveAfterStartStopMatch = $SliceAfterStartStopMatch
                }
            } else {
                $effectiveAfterStartStopMatch = $SliceAfterStartStopMatch
            }

            if ($SliceAfterStartPostMarkerSlices -gt 0) {
                $afterStartArguments.stopMatch = "__THOR_TRANSFORMERS_AFTER_START_UNREACHED__"
                $afterStartArguments.armMatch = $effectiveAfterStartStopMatch
                $afterStartArguments.postArmSlices = $SliceAfterStartPostMarkerSlices
            } else {
                $afterStartArguments.stopMatch = $effectiveAfterStartStopMatch
            }

            $afterStartControllerTimeout = [int][Math]::Ceiling($afterStartArguments.maxHostS + 150)
            $afterStartOutput = Invoke-ThorRenderProbeController `
                -Name "thor_slice_loop" `
                -Arguments $afterStartArguments `
                -CaptureDir $captureDir `
                -OutputName "slice-loop-after-start.json" `
                -TimeoutSeconds $afterStartControllerTimeout
            $sliceResult = ($afterStartOutput -join [Environment]::NewLine) | ConvertFrom-Json
            if ($sliceResult.error -or $sliceResult.refused -or
                    $sliceResult.thermalStop -or $sliceResult.fatal -or
                    -not $sliceResult.markerReached -or -not $sliceResult.paused) {
                throw "The after-START slice loop did not reach its requested paused marker."
            }
        } else {
            $controllerTimeout = [int][Math]::Ceiling($MaxSliceHostSeconds + 150)
            $controllerOutput = Invoke-ThorRenderProbeController `
                -Name "thor_slice_loop" `
                -Arguments $sliceArguments `
                -CaptureDir $captureDir `
                -OutputName "slice-loop.json" `
                -TimeoutSeconds $controllerTimeout
            $sliceResult = ($controllerOutput -join [Environment]::NewLine) | ConvertFrom-Json
        }

        $pidEvidence = Invoke-ThorAdbText $adb $captureDir "slice-loop-pid.txt" @("shell", "pidof net.rpcsx.easy") -AllowFailure
        $pidRows = @(
            Get-Content -LiteralPath $pidEvidence |
                ForEach-Object { $_.ToString().Trim() } |
                Where-Object {
                    $_ -and
                    -not $_.StartsWith("#") -and
                    $_ -notmatch '^exit='
                }
        )
        if ($pidRows.Count -gt 0 -and $sliceResult.markerReached -and
            $sliceResult.paused) {
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
            try {
                Stop-ThorSliceDeviceGuard
            } catch {
                $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "slice-device-thermal-guard-stop-error.txt") -Encoding UTF8
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
            Stop-ThorSliceDeviceGuard
        }
    }
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.draw_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_atomic_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_task_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_wait_trace" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.fmod_event_wait_trace" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.fmod_event_interp" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_audio_wake_fix" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_physx_queue_wait" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_physx_start_interp" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_fifo_ordered" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_lwmutex_trace" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_ls_dump" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_pc_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_event_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_pc_census" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_prof" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.tf_render_poll_us" -Value "400"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_probe" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_interp" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.task_attr_fix" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_spu_reserve" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.start_paused" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.queue_publish_order" -Value "0"
    Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.queue_diagnostics" -Value "0"
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
