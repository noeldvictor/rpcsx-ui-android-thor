param(
    [ValidateSet("Smoke", "Run", "LocateGame", "InstallFirmware")]
    [string]$Action = "Smoke",
    [string]$Label = "windows-rpcs3",
    [string]$BootTarget = "",
    [string]$FirmwarePath = "",
    [ValidateSet("NoGui", "Headless", "Gui")]
    [string]$Mode = "NoGui",
    [string]$TitleId = "BLUS30161",
    [ValidateSet("Off", "Detect", "Cache")]
    [string]$EternalSonataSuperPath = "Off",
    [int]$EternalSonataJoinSpin = -1,
    [ValidateSet("Off", "Profile", "Yield", "Skip", "Clamp")]
    [string]$EternalSonataWaitSuperPath = "Off",
    [int]$EternalSonataWaitMaxUs = 100,
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$EternalSonataSemaphoreSuperPath = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataGpuProbe = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataMfcShapeProbe = "Off",
    [ValidateSet("Off", "Verify", "Fast")]
    [string]$EternalSonataMfcLadder = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataSpuHeatProfile = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataPpuRsxProfile = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataSyncProfile = "Off",
    [ValidateSet("Off", "Wait")]
    [string]$EternalSonataFramePollWait = "Off",
    [ValidateRange(0, 500)]
    [int]$EternalSonataFramePollHandlerGraceUs = 500,
    [ValidateSet("Off", "On")]
    [string]$EternalSonataFramePollContinuousRearm = "Off",
    [ValidateSet("Off", "Verify", "VerifyShadow", "Verify25ccShadow", "Skip")]
    [string]$EternalSonataSpuHleVerify = "Off",
    [ValidateSet("Off", "Verify", "Fast")]
    [string]$EternalSonataSpuHle25ccBody = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataSpuHleSize16Body = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataSpuHle451cPreserveBody = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataKernelCapsule = "Off",
    [ValidateSet("Off", "Profile", "Verify")]
    [string]$EternalSonataReservationLoop = "Off",
    [ValidateSet("Off", "Relaxed")]
    [string]$EternalSonataPutllc16Reservations = "Off",
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$EternalSonataPutllc16Pair = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataDmaSuperPath = "Off",
    [string]$RsxAuditor = "Off",
    [ValidateSet("Off", "Host")]
    [string]$RsxDmaFence = "Off",
    [ValidateSet("Off", "Depth", "DepthReadOnly", "Color", "All")]
    [string]$RsxTextureBarrier = "Off",
    [ValidateSet("Off", "KeepReadOnly")]
    [string]$RsxDepthFeedback = "Off",
    [ValidateSet("Off", "Profile", "SkipColor", "SkipDepth", "SkipAll")]
    [string]$RsxResolve = "Off",
    [ValidateSet("Off", "Verify", "VerifySampled", "VerifyCachedSampled", "VerifyCachedTransferSampled", "VerifyCachedDeferSampled", "Fast", "FastSampled", "FastCachedSampled", "FastCachedTransferSampled", "FastCachedDeferSampled", "FastKeepSrc")]
    [string]$RsxBlitSourceResolve = "Off",
    [ValidateSet("Off", "GpuSwap")]
    [string]$RsxPresentUpload = "Off",
    [ValidateSet("Off", "GpuSwap", "GpuSwapCached")]
    [string]$RsxIndexUpload = "Off",
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$RsxIndexPersistentCache = "Off",
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$RsxVertexSupersetCache = "Off",
    [int]$RsxVertexSupersetScanLimit = 0,
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$RsxVertexPersistentCache = "Off",
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$RsxVertexVolatileCache = "Off",
    [ValidateSet("Keep", "On", "Off")]
    [string]$RsxForceHwMsaaResolve = "Keep",
    [string[]]$SearchRoots = @(),
    [string]$Rpcs3BinOverride = "",
    [int]$MaxSeconds = 20,
    [string]$InputMacro = "",
    [ValidateSet("Keyboard", "PadApi")]
    [string]$InputBackend = "Keyboard",
    [int]$InputStartSeconds = 0,
    [int]$InputDefaultPressMs = 120,
    [ValidateSet("Keep", "Off", "Auto", "PS3Native", "30", "60", "120", "240")]
    [string]$FrameLimit = "Keep",
    [int]$VblankRate = 0,
    [ValidateSet("Keep", "On", "Off")]
    [string]$SpuAccurateReservations = "Keep",
    [ValidateSet("Keep", "On", "Off")]
    [string]$SpuAccurateDma = "Keep",
    [ValidateSet("Keep", "On", "Off")]
    [string]$PpuDazAndFtz = "Keep",
    [int]$GameScreen = 1,
    [int]$ScreenshotEverySeconds = 0,
    [int]$ScreenshotStartSeconds = 20,
    [int]$ScreenshotMaxCount = 0,
    [int]$HostSampleSeconds = 1,
    [int]$HostSampleEverySeconds = 30,
    [ValidateSet("Off", "Warn", "Fail", "ExternalFail")]
    [string]$HostContentionGate = "Off",
    [switch]$SkipHostSystemCheck,
    [string]$CpuAffinityMask = "",
    [switch]$RenderDocInject,
    [string]$RenderDocPath = "",
    [switch]$RenderDocApiValidation,
    [switch]$RenderDocCaptureCallstacks,
    [switch]$RefreshConfigDb,
    [switch]$SkipConfigDbRefresh,
    [switch]$SkipAgentInputProfile,
    [long]$GpuProbeSummaryMaxLogBytes = 33554432,
    [switch]$Visible,
    [switch]$NoTimestampDir
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

if ($SkipHostSystemCheck -and $HostContentionGate -ne "Off") {
    throw "HostContentionGate requires host system checks. Remove -SkipHostSystemCheck or set -HostContentionGate Off."
}

function Get-LabRepoRoot {
    $root = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if (-not $root) {
        throw "Could not resolve repo root from $PSScriptRoot"
    }
    return $root.Trim()
}

function New-LabSafeLabel {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9_.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "windows-rpcs3"
    }
    return $safe
}

function Resolve-LabPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Write-LabLine {
    param(
        [string]$Path,
        [string]$Text = ""
    )

    $Text | Tee-Object -FilePath $Path -Append | ForEach-Object { Write-Host $_ }
}

function Test-LabKnownEmulatorProcessName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return $Name -imatch '^(rpcs3|vita3k|pcsx2|duckstation|xemu|cemu|yuzu|suyu|ryujinx|ppsspp|retroarch|dolphin|xenia|citra|azahar|lime3ds)$'
}

function Get-LabSafeProcessPath {
    param([System.Diagnostics.Process]$Process)

    try {
        return $Process.Path
    } catch {
        return ""
    }
}

function Get-LabProcessCpuRows {
    param([int]$SampleSeconds = 1)

    $sampleMs = [Math]::Max(250, $SampleSeconds * 1000)
    $actualSeconds = [double]$sampleMs / 1000.0
    $logicalProcessors = [Math]::Max(1, [Environment]::ProcessorCount)
    $before = @{}

    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($null -ne $process.CPU) {
            $before[[int]$process.Id] = [double]$process.CPU
        }
    }

    Start-Sleep -Milliseconds $sampleMs

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $deltaCpu = 0.0
        if ($null -ne $process.CPU -and $before.ContainsKey([int]$process.Id)) {
            $deltaCpu = [Math]::Max(0.0, ([double]$process.CPU - [double]$before[[int]$process.Id]))
        }

        $cpuPercent = [Math]::Round(($deltaCpu / $actualSeconds / $logicalProcessors) * 100.0, 1)
        $rows.Add([pscustomobject]@{
            name           = $process.ProcessName
            pid            = [int]$process.Id
            cpu_percent    = $cpuPercent
            working_set_mb = [Math]::Round(([double]$process.WorkingSet64 / 1MB), 1)
            private_mb     = [Math]::Round(([double]$process.PrivateMemorySize64 / 1MB), 1)
            path           = Get-LabSafeProcessPath -Process $process
        }) | Out-Null
    }

    return @($rows | Sort-Object -Property cpu_percent -Descending)
}

function Get-LabMemorySnapshot {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $totalMb = [Math]::Round(([double]$os.TotalVisibleMemorySize / 1024.0), 1)
        $freeMb = [Math]::Round(([double]$os.FreePhysicalMemory / 1024.0), 1)
        $usedMb = [Math]::Max(0.0, $totalMb - $freeMb)
        $usedPercent = if ($totalMb -gt 0) { [Math]::Round(($usedMb / $totalMb) * 100.0, 1) } else { $null }

        return [pscustomobject]@{
            total_mb     = $totalMb
            free_mb      = $freeMb
            used_mb      = [Math]::Round($usedMb, 1)
            used_percent = $usedPercent
        }
    } catch {
        return [pscustomobject]@{
            total_mb     = $null
            free_mb      = $null
            used_mb      = $null
            used_percent = $null
        }
    }
}

function Get-LabGpuEngineUtilization {
    try {
        $samples = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
        $gpuSamples = @($samples.CounterSamples | Where-Object {
            $_.InstanceName -match 'engtype_(3d|compute|copy|videoencode|videodecode)'
        })

        if ($gpuSamples.Count -eq 0) {
            return $null
        }

        $sum = ($gpuSamples | Measure-Object -Property CookedValue -Sum).Sum
        return [Math]::Round([double]$sum, 1)
    } catch {
        return $null
    }
}

function Get-LabHostContention {
    param(
        [AllowNull()]$TotalCpuPercent,
        [AllowNull()]$GpuEngineUtilPercent,
        [AllowNull()]$MemoryUsedPercent,
        [object[]]$ProcessRows,
        [int]$RunPid = 0
    )

    $rank = 0
    $reasons = New-Object System.Collections.Generic.List[string]
    $externalEmulators = @($ProcessRows | Where-Object {
        (Test-LabKnownEmulatorProcessName -Name $_.name) -and ($RunPid -le 0 -or $_.pid -ne $RunPid)
    })

    if ($externalEmulators.Count -gt 0) {
        $rank = [Math]::Max($rank, 2)
        $names = @($externalEmulators | ForEach-Object { "$($_.name)#$($_.pid)" })
        $reasons.Add("external emulator active: $($names -join ', ')") | Out-Null
    }

    if ($null -ne $TotalCpuPercent) {
        if ([double]$TotalCpuPercent -ge 80.0) {
            $rank = [Math]::Max($rank, 2)
            $reasons.Add("host CPU estimate >= 80%") | Out-Null
        } elseif ([double]$TotalCpuPercent -ge 45.0) {
            $rank = [Math]::Max($rank, 1)
            $reasons.Add("host CPU estimate >= 45%") | Out-Null
        }
    }

    if ($null -ne $GpuEngineUtilPercent) {
        if ([double]$GpuEngineUtilPercent -ge 90.0) {
            $rank = [Math]::Max($rank, 2)
            $reasons.Add("GPU engine utilization sum >= 90%") | Out-Null
        } elseif ([double]$GpuEngineUtilPercent -ge 60.0) {
            $rank = [Math]::Max($rank, 1)
            $reasons.Add("GPU engine utilization sum >= 60%") | Out-Null
        }
    }

    if ($null -ne $MemoryUsedPercent) {
        if ([double]$MemoryUsedPercent -ge 90.0) {
            $rank = [Math]::Max($rank, 2)
            $reasons.Add("host memory used >= 90%") | Out-Null
        } elseif ([double]$MemoryUsedPercent -ge 80.0) {
            $rank = [Math]::Max($rank, 1)
            $reasons.Add("host memory used >= 80%") | Out-Null
        }
    }

    $heavyOther = @($ProcessRows | Where-Object {
        ($RunPid -le 0 -or $_.pid -ne $RunPid) -and ([double]$_.cpu_percent -ge 15.0)
    } | Select-Object -First 3)

    if ($heavyOther.Count -gt 0) {
        $rank = [Math]::Max($rank, 1)
        $heavyNames = @($heavyOther | ForEach-Object { "$($_.name)#$($_.pid)=$($_.cpu_percent)%" })
        $reasons.Add("other hot process: $($heavyNames -join ', ')") | Out-Null
    }

    $grade = switch ($rank) {
        2 { "high" }
        1 { "moderate" }
        default { "clean" }
    }

    if ($reasons.Count -eq 0) {
        $reasons.Add("no competing emulator or heavy host load detected") | Out-Null
    }

    return [pscustomobject]@{
        grade   = $grade
        reasons = @($reasons)
    }
}

function Get-LabExternalHostContention {
    param(
        [AllowNull()]$MemoryUsedPercent,
        [object[]]$ProcessRows,
        [int]$RunPid = 0
    )

    $rank = 0
    $reasons = New-Object System.Collections.Generic.List[string]
    $externalEmulators = @($ProcessRows | Where-Object {
        (Test-LabKnownEmulatorProcessName -Name $_.name) -and ($RunPid -le 0 -or $_.pid -ne $RunPid)
    })

    if ($externalEmulators.Count -gt 0) {
        $rank = [Math]::Max($rank, 2)
        $names = @($externalEmulators | ForEach-Object { "$($_.name)#$($_.pid)" })
        $reasons.Add("external emulator active: $($names -join ', ')") | Out-Null
    }

    $heavyOther = @($ProcessRows | Where-Object {
        ($RunPid -le 0 -or $_.pid -ne $RunPid) -and ([double]$_.cpu_percent -ge 15.0)
    } | Select-Object -First 3)

    if ($heavyOther.Count -gt 0) {
        $rank = [Math]::Max($rank, 1)
        $heavyNames = @($heavyOther | ForEach-Object { "$($_.name)#$($_.pid)=$($_.cpu_percent)%" })
        $reasons.Add("hot non-run process: $($heavyNames -join ', ')") | Out-Null
    }

    if ($null -ne $MemoryUsedPercent) {
        if ([double]$MemoryUsedPercent -ge 90.0) {
            $rank = [Math]::Max($rank, 2)
            $reasons.Add("host memory used >= 90%") | Out-Null
        } elseif ([double]$MemoryUsedPercent -ge 80.0) {
            $rank = [Math]::Max($rank, 1)
            $reasons.Add("host memory used >= 80%") | Out-Null
        }
    }

    $grade = switch ($rank) {
        2 { "high" }
        1 { "moderate" }
        default { "clean" }
    }

    if ($reasons.Count -eq 0) {
        $reasons.Add("no competing emulator, hot non-run process, or memory pressure detected") | Out-Null
    }

    return [pscustomobject]@{
        grade   = $grade
        reasons = @($reasons)
    }
}

function Get-LabHostLoadSnapshot {
    param(
        [string]$Phase,
        [int]$SampleSeconds = 1,
        [int]$RunPid = 0
    )

    $sampleSeconds = [Math]::Max(1, $SampleSeconds)
    $processRows = @(Get-LabProcessCpuRows -SampleSeconds $sampleSeconds)
    $memory = Get-LabMemorySnapshot
    $gpuEngineUtil = Get-LabGpuEngineUtilization
    $totalCpu = $null
    if ($processRows.Count -gt 0) {
        $totalCpu = [Math]::Round([Math]::Min(100.0, [double](($processRows | Measure-Object -Property cpu_percent -Sum).Sum)), 1)
    }

    $contention = Get-LabHostContention -TotalCpuPercent $totalCpu -GpuEngineUtilPercent $gpuEngineUtil -MemoryUsedPercent $memory.used_percent -ProcessRows $processRows -RunPid $RunPid
    $externalContention = Get-LabExternalHostContention -MemoryUsedPercent $memory.used_percent -ProcessRows $processRows -RunPid $RunPid
    $topProcesses = @($processRows | Select-Object -First 12)
    $emulatorProcesses = @($processRows | Where-Object { Test-LabKnownEmulatorProcessName -Name $_.name })
    $runProcess = @($processRows | Where-Object { $RunPid -gt 0 -and $_.pid -eq $RunPid } | Select-Object -First 1)

    return [pscustomobject]@{
        version                       = 1
        phase                         = $Phase
        timestamp                     = (Get-Date).ToString("o")
        sample_seconds                = $sampleSeconds
        logical_processors            = [Environment]::ProcessorCount
        total_cpu_percent_estimate    = $totalCpu
        gpu_engine_util_percent_sum   = $gpuEngineUtil
        memory                        = $memory
        run_pid                       = $RunPid
        run_process                   = @($runProcess)
        contention_grade              = $contention.grade
        contention_reasons            = @($contention.reasons)
        external_contention_grade     = $externalContention.grade
        external_contention_reasons   = @($externalContention.reasons)
        emulator_processes            = @($emulatorProcesses)
        top_processes                 = @($topProcesses)
    }
}

function Save-LabHostLoadSnapshot {
    param(
        [string]$RunDir,
        [string]$RunLog,
        [object]$Snapshot
    )

    $hostDir = Join-Path $RunDir "host-system"
    New-Item -ItemType Directory -Force -Path $hostDir | Out-Null
    $phase = New-LabSafeLabel -Value $Snapshot.phase
    $jsonPath = Join-Path $hostDir "$phase.json"
    $Snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $cpuText = if ($null -ne $Snapshot.total_cpu_percent_estimate) { "$($Snapshot.total_cpu_percent_estimate)" } else { "unknown" }
    $memText = if ($null -ne $Snapshot.memory.used_percent) { "$($Snapshot.memory.used_percent)" } else { "unknown" }
    $gpuText = if ($null -ne $Snapshot.gpu_engine_util_percent_sum) { "$($Snapshot.gpu_engine_util_percent_sum)" } else { "unknown" }
    $externalEmulators = @($Snapshot.emulator_processes | Where-Object {
        $Snapshot.run_pid -le 0 -or $_.pid -ne $Snapshot.run_pid
    })
    $emulatorText = if ($externalEmulators.Count -gt 0) {
        (@($externalEmulators | ForEach-Object { "$($_.name)#$($_.pid)" }) -join ", ")
    } else {
        "none"
    }
    $reasonText = @($Snapshot.contention_reasons) -join "; "
    $externalGrade = if ($Snapshot.PSObject.Properties.Name -contains "external_contention_grade") { $Snapshot.external_contention_grade } else { "unknown" }
    $externalReasonText = if ($Snapshot.PSObject.Properties.Name -contains "external_contention_reasons") { @($Snapshot.external_contention_reasons) -join "; " } else { "not recorded" }

    Write-LabLine $RunLog "- Host check [$($Snapshot.phase)]: $($Snapshot.contention_grade); external=$externalGrade; cpu=${cpuText}%; mem=${memText}%; gpu-engine-sum=${gpuText}%; external-emulators=$emulatorText; $reasonText; external reasons: $externalReasonText"
    Write-LabLine $RunLog "  host snapshot: $jsonPath"

    return $jsonPath
}

function Get-LabWorstHostContentionGrade {
    param([object[]]$Snapshots)

    $worstRank = -1
    foreach ($snapshot in @($Snapshots)) {
        $rank = switch ($snapshot.contention_grade) {
            "high" { 2 }
            "moderate" { 1 }
            "clean" { 0 }
            default { 1 }
        }
        $worstRank = [Math]::Max($worstRank, $rank)
    }

    switch ("$worstRank") {
        "2" { return "high" }
        "1" { return "moderate" }
        "0" { return "clean" }
        default { return "unknown" }
    }
}

function Get-LabWorstExternalHostContentionGrade {
    param([object[]]$Snapshots)

    $worstRank = -1
    foreach ($snapshot in @($Snapshots)) {
        $grade = if ($snapshot.PSObject.Properties.Name -contains "external_contention_grade") {
            $snapshot.external_contention_grade
        } else {
            "unknown"
        }
        $rank = switch ($grade) {
            "high" { 2 }
            "moderate" { 1 }
            "clean" { 0 }
            default { 1 }
        }
        $worstRank = [Math]::Max($worstRank, $rank)
    }

    switch ("$worstRank") {
        "2" { return "high" }
        "1" { return "moderate" }
        "0" { return "clean" }
        default { return "unknown" }
    }
}

function Convert-LabArgumentList {
    param([string[]]$ArgumentValues)

    return ($ArgumentValues | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '
}

function Resolve-LabRenderDoc {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $full = Resolve-LabPath $RequestedPath
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
            throw "RenderDoc command does not exist: $full"
        }
        return $full
    }

    $fromPath = Get-Command renderdoccmd.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $candidates = @(
        "C:\Program Files\RenderDoc\renderdoccmd.exe",
        "C:\Program Files (x86)\RenderDoc\renderdoccmd.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "RenderDoc command not found. Run tools\install_speed_sprint_tools.ps1 -Install first, or pass -RenderDocPath."
}

function Invoke-LabRenderDocInject {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$RunDir,
        [string]$SafeLabel,
        [string]$RunLog,
        [string]$RequestedPath,
        [switch]$ApiValidation,
        [switch]$CaptureCallstacks
    )

    $renderDoc = Resolve-LabRenderDoc -RequestedPath $RequestedPath
    $captureDir = Join-Path $RunDir "renderdoc"
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
    $captureTemplate = Join-Path $captureDir "$SafeLabel"

    $injectArgs = New-Object System.Collections.Generic.List[string]
    $injectArgs.Add("inject")
    $injectArgs.Add("--PID=$($Process.Id)")
    $injectArgs.Add("--capture-file")
    $injectArgs.Add($captureTemplate)
    if ($ApiValidation) {
        $injectArgs.Add("--opt-api-validation")
    }
    if ($CaptureCallstacks) {
        $injectArgs.Add("--opt-capture-callstacks")
    }

    Write-LabLine $RunLog "- RenderDoc: $renderDoc"
    Write-LabLine $RunLog "- RenderDoc capture template: $captureTemplate"
    Write-LabLine $RunLog "- RenderDoc trigger: use input macro key 'f12' or press F12 while the game window has focus"
    $argumentLine = Convert-LabArgumentList -ArgumentValues ($injectArgs.ToArray())
    Write-LabLine $RunLog "- RenderDoc inject command: $renderDoc $argumentLine"

    $stdoutPath = Join-Path $RunDir "renderdoc-inject.stdout.txt"
    $stderrPath = Join-Path $RunDir "renderdoc-inject.stderr.txt"
    $injectProcess = Start-Process -FilePath $renderDoc -ArgumentList $argumentLine -WorkingDirectory $RunDir -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru -Wait
    $injectExit = $injectProcess.ExitCode
    if (Test-Path -LiteralPath $stdoutPath) {
        foreach ($line in @(Get-Content -LiteralPath $stdoutPath)) {
            Write-LabLine $RunLog "  stdout: $line"
        }
    }
    if (Test-Path -LiteralPath $stderrPath) {
        foreach ($line in @(Get-Content -LiteralPath $stderrPath)) {
            Write-LabLine $RunLog "  stderr: $line"
        }
    }
    Write-LabLine $RunLog "- RenderDoc inject exit: $injectExit"
}

function Get-LabDefaultSearchRoots {
    return @(
        (Join-Path $repoRoot "iso")
    ) | Where-Object { Test-Path -LiteralPath $_ }
}

function Test-LabExcludedPath {
    param([string]$Path)
    return $Path -match '\\(\.git|build-msvc|out|debug-captures|debug-experiments)\\'
}

function Resolve-LabBootTarget {
    param([string]$Path)

    $full = Resolve-LabPath $Path
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        return $full
    }

    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw "Boot target does not exist: $full"
    }

    $directCandidates = @(
        (Join-Path $full "PS3_GAME\USRDIR\EBOOT.BIN"),
        (Join-Path $full "USRDIR\EBOOT.BIN")
    )

    foreach ($candidate in $directCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $nested = Get-ChildItem -LiteralPath $full -Recurse -File -Filter "EBOOT.BIN" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\PS3_GAME\\USRDIR\\EBOOT\.BIN$' } |
        Select-Object -First 1

    if ($nested) {
        return $nested.FullName
    }

    throw "Could not resolve a PS3 boot target under: $full"
}

function Find-LabBootCandidates {
    param(
        [string[]]$Roots,
        [string]$TitleId
    )

    $bootTargets = New-Object System.Collections.Generic.List[string]
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        Get-ChildItem -LiteralPath $root -Recurse -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-LabExcludedPath $_.FullName) -and
                ($_.Name -eq "PS3_GAME" -or $_.FullName -match [regex]::Escape($TitleId))
            } |
            ForEach-Object {
                try {
                    $bootTargets.Add((Resolve-LabBootTarget $_.FullName))
                } catch {}
            }

        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "PARAM.SFO" -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-LabExcludedPath $_.FullName)
            } |
            ForEach-Object {
                try {
                    $bootTargets.Add((Resolve-LabBootTarget (Split-Path -Parent $_.FullName)))
                } catch {}
            }

        Get-ChildItem -LiteralPath $root -Recurse -File -Include "*.iso" -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-LabExcludedPath $_.FullName) -and
                ($_.FullName -match [regex]::Escape($TitleId) -or $_.FullName -match "Eternal|Sonata")
            } |
            ForEach-Object {
                $bootTargets.Add($_.FullName)
            }
    }

    return @($bootTargets | Sort-Object -Unique)
}

function Initialize-LabInput {
    if ("LabInput.Win32" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace LabInput
{
    public static class Win32
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    }
}
"@
}

function Get-LabVirtualKey {
    param([string]$Name)

    $key = $Name.Trim().ToLowerInvariant()
    $map = @{
        "cross" = 0x58; "x" = 0x58
        "circle" = 0x43; "c" = 0x43
        "square" = 0x5A; "z" = 0x5A
        "triangle" = 0x56; "v" = 0x56
        "start" = 0x0D; "enter" = 0x0D; "return" = 0x0D
        "select" = 0x20; "space" = 0x20
        "ps" = 0x08; "backspace" = 0x08
        "up" = 0x26; "dpad_up" = 0x26
        "down" = 0x28; "dpad_down" = 0x28
        "left" = 0x25; "dpad_left" = 0x25
        "right" = 0x27; "dpad_right" = 0x27
        "ls_up" = 0x57; "lstick_up" = 0x57; "w" = 0x57
        "ls_left" = 0x41; "lstick_left" = 0x41; "a" = 0x41
        "ls_down" = 0x53; "lstick_down" = 0x53; "s" = 0x53
        "ls_right" = 0x44; "lstick_right" = 0x44; "d" = 0x44
        "rs_up" = 0x24; "rstick_up" = 0x24; "home" = 0x24
        "rs_left" = 0x2E; "rstick_left" = 0x2E; "delete" = 0x2E
        "rs_down" = 0x23; "rstick_down" = 0x23; "end" = 0x23
        "rs_right" = 0x22; "rstick_right" = 0x22; "pagedown" = 0x22
        "l1" = 0x51; "q" = 0x51
        "l2" = 0x52; "r" = 0x52
        "l3" = 0x46; "f" = 0x46
        "r1" = 0x45; "e" = 0x45
        "r2" = 0x54; "t" = 0x54
        "r3" = 0x47; "g" = 0x47
        "f12" = 0x7B
    }

    if (-not $map.ContainsKey($key)) {
        throw "Unknown input macro key: '$Name'"
    }

    return [byte]$map[$key]
}

function Get-LabKeyboardEventFlags {
    param(
        [byte]$VirtualKey,
        [switch]$KeyUp
    )

    # Navigation keys are encoded as extended keys by Win32. Without this flag,
    # arrow presses can be interpreted as keypad scan codes and never reach the
    # RPCS3 keyboard handler even though ordinary keys (for example X) work.
    $flags = if (($VirtualKey -ge 0x21 -and $VirtualKey -le 0x28) -or $VirtualKey -eq 0x2D -or $VirtualKey -eq 0x2E) { 0x1 } else { 0x0 }
    if ($KeyUp) {
        $flags = $flags -bor 0x2
    }
    return [uint32]$flags
}

function Convert-LabAffinityMask {
    param([string]$Mask)

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return $null
    }

    $text = $Mask.Trim()
    if ($text -match '^0x([0-9a-fA-F]+)$') {
        return [Convert]::ToInt64($Matches[1], 16)
    }

    return [Convert]::ToInt64($text, 10)
}

function Set-LabProcessAffinity {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Mask,
        [string]$RunLog
    )

    if ([string]::IsNullOrWhiteSpace($Mask)) {
        return
    }

    $affinity = Convert-LabAffinityMask -Mask $Mask
    if ($null -eq $affinity -or $affinity -le 0) {
        throw "CPU affinity mask must be a positive decimal or hex value, got '$Mask'."
    }

    $Process.Refresh()
    $Process.ProcessorAffinity = [IntPtr]::new([int64]$affinity)
    Write-LabLine $RunLog ("- CPU affinity applied: {0} (0x{1:x})" -f $affinity, $affinity)
}

function Set-LabPadApiState {
    param(
        [string]$Path,
        [string[]]$Keys = @()
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "PadApi input requires a state file path."
    }

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $cleanKeys = @(
        $Keys |
            ForEach-Object { "$_".Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $text = ($cleanKeys -join " ")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $tmp = "{0}.{1}.tmp" -f $Path, [Guid]::NewGuid().ToString("N")
    [System.IO.File]::WriteAllText($tmp, $text, $utf8NoBom)

    $lastError = $null
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            if (Test-Path -LiteralPath $Path) {
                [System.IO.File]::Replace($tmp, $Path, $null, $true)
            } else {
                [System.IO.File]::Move($tmp, $Path)
            }
            return
        } catch {
            $lastError = $_
            try {
                [System.IO.File]::Copy($tmp, $Path, $true)
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                return
            } catch {
                $lastError = $_
                Start-Sleep -Milliseconds 25
            }
        }
    }

    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Failed to update PadApi state file '$Path': $($lastError.Exception.Message)"
}

function Wait-LabProcessWindow {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            return [IntPtr]::Zero
        }

        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $Process.MainWindowHandle
        }

        Start-Sleep -Milliseconds 250
    }

    return [IntPtr]::Zero
}

function Set-LabAgentInputProfile {
    param(
        [string]$Rpcs3Bin,
        [string]$TitleId,
        [string]$RunLog
    )

    $inputRoot = Join-Path $Rpcs3Bin "config\input_configs"
    $globalDir = Join-Path $inputRoot "global"
    $titleDir = if ([string]::IsNullOrWhiteSpace($TitleId)) { "" } else { Join-Path $inputRoot $TitleId }
    $profileName = "Default.yml"
    $marker = "RPCS3 Thor Lab agent keyboard profile"

    $profileText = @"
# $marker
Player 1 Input:
  Handler: Keyboard
  Device: Keyboard
  Config: {}
  Buddy Device: ""
Player 2 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
Player 3 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
Player 4 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
Player 5 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
Player 6 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
Player 7 Input:
  Handler: "Null"
  Device: "Null"
  Config: {}
  Buddy Device: "Null"
"@

    $activeLines = [System.Collections.Generic.List[string]]::new()
    $activeLines.Add("# $marker")
    $activeLines.Add("Active Configurations:")
    $activeLines.Add("  global: Default")
    if (-not [string]::IsNullOrWhiteSpace($TitleId)) {
        $activeLines.Add("  ${TitleId}: Default")
    }
    $activeText = ($activeLines -join [Environment]::NewLine) + [Environment]::NewLine
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    function Write-AgentProfileFile {
        param(
            [string]$Path,
            [string]$Text
        )

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $existing = [System.IO.File]::ReadAllText($Path, $utf8NoBom)
            if ($existing -eq $Text) {
                return "already-current"
            }

            if ($existing -notmatch [regex]::Escape($marker)) {
                $backup = "$Path.pre-agent-$((Get-Date).ToString('yyyyMMdd-HHmmss')).bak"
                Copy-Item -LiteralPath $Path -Destination $backup -Force
            }
        }

        [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
        return "written"
    }

    $globalPath = Join-Path $globalDir $profileName
    $globalStatus = Write-AgentProfileFile -Path $globalPath -Text $profileText
    Write-LabLine $RunLog "- Agent input profile: global $globalStatus ($globalPath)"

    if (-not [string]::IsNullOrWhiteSpace($titleDir)) {
        $titlePath = Join-Path $titleDir $profileName
        $titleStatus = Write-AgentProfileFile -Path $titlePath -Text $profileText
        Write-LabLine $RunLog "- Agent input profile: ${TitleId} $titleStatus ($titlePath)"
    }

    $activePath = Join-Path $inputRoot "active_input_configurations.yml"
    $activeStatus = Write-AgentProfileFile -Path $activePath -Text $activeText
    Write-LabLine $RunLog "- Agent input profile: active map $activeStatus ($activePath)"
}

function Test-LabTitleMenuScreenshot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 500000) {
        return $false
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    } catch {
        return $false
    }

    try {
        if ($bitmap.Width -lt 900 -or $bitmap.Height -lt 600) {
            return $false
        }

        # The three title choices occupy separate, stable horizontal bands.
        # Requiring all three keeps subtitle-only cutscenes from satisfying the
        # gate, while the blue-field check rejects the tan Options/Load pages.
        $brightRatios = foreach ($band in @(@(520, 585), @(580, 635), @(630, 690))) {
            $bright = 0
            $samples = 0
            $startY = [int][Math]::Floor($band[0] * $bitmap.Height / 759.0)
            $endY = [int][Math]::Floor($band[1] * $bitmap.Height / 759.0)
            $startX = [int][Math]::Floor(480 * $bitmap.Width / 1296.0)
            $endX = [int][Math]::Floor(820 * $bitmap.Width / 1296.0)
            for ($y = $startY; $y -lt $endY; $y += 2) {
                for ($x = $startX; $x -lt $endX; $x += 2) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    if ($pixel.R -ge 180 -and $pixel.G -ge 180 -and $pixel.B -ge 180) {
                        $bright++
                    }
                    $samples++
                }
            }
            if ($samples -eq 0) { 0.0 } else { $bright / [double]$samples }
        }

        $blue = 0
        $blueSamples = 0
        for ($y = [int][Math]::Floor(80 * $bitmap.Height / 759.0); $y -lt [int][Math]::Floor(500 * $bitmap.Height / 759.0); $y += 8) {
            for ($x = [int][Math]::Floor(250 * $bitmap.Width / 1296.0); $x -lt [int][Math]::Floor(1050 * $bitmap.Width / 1296.0); $x += 8) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.B -ge ($pixel.R + 20) -and $pixel.B -ge ($pixel.G + 15)) {
                    $blue++
                }
                $blueSamples++
            }
        }

        $blueRatio = if ($blueSamples -eq 0) { 0.0 } else { $blue / [double]$blueSamples }
        return (
            $brightRatios.Count -eq 3 -and
            $brightRatios[0] -ge 0.020 -and
            $brightRatios[1] -ge 0.020 -and
            $brightRatios[2] -ge 0.020 -and
            $blueRatio -ge 0.35
        )
    } finally {
        $bitmap.Dispose()
    }
}

function Invoke-LabTitleMenuGate {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [string]$RunLog,
        [datetime]$LaunchTime = (Get-Date),
        [int]$TimeoutMilliseconds = 90000,
        [int]$PollMilliseconds = 1000
    )

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        Write-LabLine $RunLog "Title-menu gate failed: no screenshot directory was provided."
        return $false
    }
    if ($TimeoutMilliseconds -le 0) { $TimeoutMilliseconds = 90000 }
    if ($PollMilliseconds -le 0) { $PollMilliseconds = 1000 }

    $runDir = Split-Path -Parent $ScreenshotDir
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $attempt = 1
    Write-LabLine $RunLog "Title-menu gate polling for NEW GAME / LOAD / OPTIONS for up to ${TimeoutMilliseconds}ms."

    while ($true) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                $marker = Join-Path $runDir "title-menu-gate-failed.txt"
                "Title-menu gate failed at ${elapsedSeconds}s: RPCS3 exited before the menu appeared." | Set-Content -LiteralPath $marker -Encoding UTF8
                Write-LabLine $RunLog "Title-menu gate failed: RPCS3 exited before the menu appeared."
                return $false
            }
        }

        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
        $tag = if ($attempt -eq 1) { "title-menu-gate" } else { "title-menu-gate-$attempt" }
        $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $tag
        if (Test-LabTitleMenuScreenshot -Path $screenshotPath) {
            Write-LabLine $RunLog "Title-menu gate passed after attempt ${attempt} at ${elapsedSeconds}s."
            return $true
        }
        if (Test-LabActionableFatalScreenshot -Path $screenshotPath) {
            $marker = Join-Path $runDir "title-menu-gate-failed.txt"
            "Title-menu gate stopped at ${elapsedSeconds}s on a probable crash/device-loss overlay." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Title-menu gate failed: probable crash/device-loss overlay."
            return $false
        }

        if ((Get-Date) -ge $deadline) {
            $marker = Join-Path $runDir "title-menu-gate-failed.txt"
            "Title-menu gate timed out at ${elapsedSeconds}s after ${attempt} screenshot(s)." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Title-menu gate failed: timed out after ${TimeoutMilliseconds}ms."
            Write-LabLine $RunLog "Title-menu gate marker: $marker"
            return $false
        }

        $remainingMs = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remainingMs))
        $attempt++
    }
}

function Test-LabLoadCompleteScreenshot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    # The load-complete banner has a narrow dark border at both y=360 and
    # y=424 in the harness' 1296x759 capture. The confirmation and loading
    # dialogs are wider, so the same center-row samples remain gold/tan. A
    # minimum PNG size rejects the small black-overlay/device-lost frame.
    if ((Get-Item -LiteralPath $Path).Length -lt 500000) {
        return $false
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    } catch {
        return $false
    }

    try {
        if ($bitmap.Width -lt 900 -or $bitmap.Height -lt 600) {
            return $false
        }

        $topY = [Math]::Min($bitmap.Height - 1, [int][Math]::Round($bitmap.Height * (360.0 / 759.0)))
        $bottomY = [Math]::Min($bitmap.Height - 1, [int][Math]::Round($bitmap.Height * (424.0 / 759.0)))
        $topDark = 0
        $bottomDark = 0

        foreach ($referenceX in 500, 525, 550, 575, 600, 625, 650, 675, 700, 725, 750, 775, 800) {
            $x = [Math]::Min($bitmap.Width - 1, [int][Math]::Round($bitmap.Width * ($referenceX / 1296.0)))
            $top = $bitmap.GetPixel($x, $topY)
            $bottom = $bitmap.GetPixel($x, $bottomY)
            if (($top.R + $top.G + $top.B) -lt 190) { $topDark++ }
            if (($bottom.R + $bottom.G + $bottom.B) -lt 190) { $bottomDark++ }
        }

        # A cutscene can also have dark pixels at both border rows. Require the
        # warm dialog body and bright banner text in the center region so blue
        # story frames cannot masquerade as a completed save load.
        $warm = 0
        $brightText = 0
        $regionSamples = 0
        $startX = [int][Math]::Floor(500 * $bitmap.Width / 1296.0)
        $endX = [int][Math]::Floor(800 * $bitmap.Width / 1296.0)
        for ($y = $topY; $y -le $bottomY; $y += 2) {
            for ($x = $startX; $x -le $endX; $x += 2) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.R -ge 110 -and $pixel.R -ge ($pixel.B + 35) -and $pixel.G -ge ($pixel.B + 15)) {
                    $warm++
                }
                if ($pixel.R -ge 190 -and $pixel.G -ge 170 -and $pixel.B -ge 120) {
                    $brightText++
                }
                $regionSamples++
            }
        }

        $warmRatio = if ($regionSamples -eq 0) { 0.0 } else { $warm / [double]$regionSamples }
        $brightTextRatio = if ($regionSamples -eq 0) { 0.0 } else { $brightText / [double]$regionSamples }
        return (
            $topDark -ge 10 -and
            $bottomDark -ge 8 -and
            $warmRatio -ge 0.25 -and
            $brightTextRatio -ge 0.015
        )
    } finally {
        $bitmap.Dispose()
    }
}

function Invoke-LabLoadCompleteGate {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [string]$RunLog,
        [datetime]$LaunchTime = (Get-Date),
        [int]$TimeoutMilliseconds = 60000,
        [int]$PollMilliseconds = 1000
    )

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        Write-LabLine $RunLog "Load-complete gate failed: no screenshot directory was provided."
        return $false
    }
    if ($TimeoutMilliseconds -le 0) { $TimeoutMilliseconds = 60000 }
    if ($PollMilliseconds -le 0) { $PollMilliseconds = 1000 }

    $runDir = Split-Path -Parent $ScreenshotDir
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $attempt = 1
    Write-LabLine $RunLog "Load-complete gate polling for the completion banner for up to ${TimeoutMilliseconds}ms."

    while ($true) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                $marker = Join-Path $runDir "load-complete-gate-failed.txt"
                "Load-complete gate failed at ${elapsedSeconds}s: RPCS3 exited before completion." | Set-Content -LiteralPath $marker -Encoding UTF8
                Write-LabLine $RunLog "Load-complete gate failed: RPCS3 exited before completion."
                return $false
            }
        }

        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
        $tag = if ($attempt -eq 1) { "load-complete-gate" } else { "load-complete-gate-$attempt" }
        $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $tag
        if (Test-LabLoadCompleteScreenshot -Path $screenshotPath) {
            Write-LabLine $RunLog "Load-complete gate passed after attempt ${attempt} at ${elapsedSeconds}s."
            return $true
        }
        if (Test-LabActionableFatalScreenshot -Path $screenshotPath) {
            $marker = Join-Path $runDir "load-complete-gate-failed.txt"
            "Load-complete gate stopped at ${elapsedSeconds}s on a probable crash/device-loss overlay." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Load-complete gate failed: probable crash/device-loss overlay."
            return $false
        }

        if ((Get-Date) -ge $deadline) {
            $marker = Join-Path $runDir "load-complete-gate-failed.txt"
            "Load-complete gate timed out at ${elapsedSeconds}s after ${attempt} screenshot(s)." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Load-complete gate failed: timed out after ${TimeoutMilliseconds}ms."
            Write-LabLine $RunLog "Load-complete gate marker: $marker"
            return $false
        }

        $remainingMs = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remainingMs))
        $attempt++
    }
}

function Test-LabPathToTenutoFieldScreenshot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 1000000) {
        return $false
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    } catch {
        return $false
    }

    try {
        if ($bitmap.Width -lt 900 -or $bitmap.Height -lt 600) {
            return $false
        }

        $green = 0
        $blue = 0
        $dark = 0
        $samples = 0
        for ($y = [int][Math]::Floor(40 * $bitmap.Height / 759.0); $y -lt [int][Math]::Floor(730 * $bitmap.Height / 759.0); $y += 8) {
            for ($x = [int][Math]::Floor(180 * $bitmap.Width / 1296.0); $x -lt [int][Math]::Floor(1260 * $bitmap.Width / 1296.0); $x += 8) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.G -ge ($pixel.R + 15) -and $pixel.G -ge ($pixel.B + 15)) { $green++ }
                if ($pixel.B -ge ($pixel.R + 20) -and $pixel.B -ge ($pixel.G + 15)) { $blue++ }
                if (($pixel.R + $pixel.G + $pixel.B) -lt 90) { $dark++ }
                $samples++
            }
        }

        if ($samples -eq 0) {
            return $false
        }
        return (
            ($green / [double]$samples) -ge 0.55 -and
            ($blue / [double]$samples) -lt 0.15 -and
            ($dark / [double]$samples) -lt 0.40
        )
    } finally {
        $bitmap.Dispose()
    }
}

function Invoke-LabPathToTenutoFieldGate {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [string]$RunLog,
        [datetime]$LaunchTime = (Get-Date),
        [int]$TimeoutMilliseconds = 30000,
        [int]$PollMilliseconds = 1000
    )

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        Write-LabLine $RunLog "Path-to-Tenuto field gate failed: no screenshot directory was provided."
        return $false
    }
    if ($TimeoutMilliseconds -le 0) { $TimeoutMilliseconds = 30000 }
    if ($PollMilliseconds -le 0) { $PollMilliseconds = 1000 }

    $runDir = Split-Path -Parent $ScreenshotDir
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $attempt = 1
    $consecutiveFatalScreenshots = 0
    $fatalScreenshotThreshold = 3
    Write-LabLine $RunLog "Path-to-Tenuto field gate polling for the green playable field for up to ${TimeoutMilliseconds}ms."

    while ($true) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                $marker = Join-Path $runDir "path-to-tenuto-field-gate-failed.txt"
                "Path-to-Tenuto field gate failed at ${elapsedSeconds}s: RPCS3 exited before the field appeared." | Set-Content -LiteralPath $marker -Encoding UTF8
                Write-LabLine $RunLog "Path-to-Tenuto field gate failed: RPCS3 exited before the field appeared."
                return $false
            }
        }

        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
        $tag = if ($attempt -eq 1) { "path-to-tenuto-field-gate" } else { "path-to-tenuto-field-gate-$attempt" }
        $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $tag
        if (Test-LabPathToTenutoFieldScreenshot -Path $screenshotPath) {
            Write-LabLine $RunLog "Path-to-Tenuto field gate passed after attempt ${attempt} at ${elapsedSeconds}s."
            return $true
        }
        if (Test-LabActionableFatalScreenshot -Path $screenshotPath) {
            $consecutiveFatalScreenshots++
            Write-LabLine $RunLog "Path-to-Tenuto field gate observed probable crash/device-loss overlay ${consecutiveFatalScreenshots}/${fatalScreenshotThreshold}; waiting for confirmation."
            if ($consecutiveFatalScreenshots -ge $fatalScreenshotThreshold) {
                $marker = Join-Path $runDir "path-to-tenuto-field-gate-failed.txt"
                "Path-to-Tenuto field gate stopped at ${elapsedSeconds}s after ${consecutiveFatalScreenshots} consecutive probable crash/device-loss overlays." | Set-Content -LiteralPath $marker -Encoding UTF8
                Write-LabLine $RunLog "Path-to-Tenuto field gate failed: ${consecutiveFatalScreenshots} consecutive probable crash/device-loss overlays."
                return $false
            }
        } else {
            $consecutiveFatalScreenshots = 0
        }

        if ((Get-Date) -ge $deadline) {
            $marker = Join-Path $runDir "path-to-tenuto-field-gate-failed.txt"
            "Path-to-Tenuto field gate timed out at ${elapsedSeconds}s after ${attempt} screenshot(s)." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Path-to-Tenuto field gate failed: timed out after ${TimeoutMilliseconds}ms."
            Write-LabLine $RunLog "Path-to-Tenuto field gate marker: $marker"
            return $false
        }

        $remainingMs = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remainingMs))
        $attempt++
    }
}

function Test-LabFirstBattlePromptScreenshot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 1000000) {
        return $false
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    } catch {
        return $false
    }

    try {
        if ($bitmap.Width -lt 900 -or $bitmap.Height -lt 600) {
            return $false
        }

        $warm = 0
        $bright = 0
        $dark = 0
        $samples = 0
        for ($y = [int][Math]::Floor(485 * $bitmap.Height / 759.0); $y -le [int][Math]::Floor(645 * $bitmap.Height / 759.0); $y += 2) {
            for ($x = [int][Math]::Floor(395 * $bitmap.Width / 1296.0); $x -le [int][Math]::Floor(900 * $bitmap.Width / 1296.0); $x += 2) {
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.R -ge 90 -and $pixel.R -ge ($pixel.B + 25) -and $pixel.G -ge ($pixel.B + 10)) { $warm++ }
                if ($pixel.R -ge 190 -and $pixel.G -ge 180 -and $pixel.B -ge 160) { $bright++ }
                if (($pixel.R + $pixel.G + $pixel.B) -lt 120) { $dark++ }
                $samples++
            }
        }

        $borderDark = 0
        $borderSamples = 0
        foreach ($referenceY in 480, 645) {
            $y = [int][Math]::Floor($referenceY * $bitmap.Height / 759.0)
            for ($x = [int][Math]::Floor(390 * $bitmap.Width / 1296.0); $x -le [int][Math]::Floor(910 * $bitmap.Width / 1296.0); $x += 3) {
                $pixel = $bitmap.GetPixel($x, $y)
                if (($pixel.R + $pixel.G + $pixel.B) -lt 160) { $borderDark++ }
                $borderSamples++
            }
        }

        if ($samples -eq 0 -or $borderSamples -eq 0) {
            return $false
        }
        return (
            ($warm / [double]$samples) -ge 0.50 -and
            ($bright / [double]$samples) -ge 0.020 -and
            ($dark / [double]$samples) -lt 0.40 -and
            ($borderDark / [double]$borderSamples) -ge 0.40
        )
    } finally {
        $bitmap.Dispose()
    }
}

function Invoke-LabFirstBattlePromptGate {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [string]$RunLog,
        [datetime]$LaunchTime = (Get-Date),
        [int]$TimeoutMilliseconds = 20000,
        [int]$PollMilliseconds = 750
    )

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        Write-LabLine $RunLog "First-battle prompt gate failed: no screenshot directory was provided."
        return $false
    }
    if ($TimeoutMilliseconds -le 0) { $TimeoutMilliseconds = 20000 }
    if ($PollMilliseconds -le 0) { $PollMilliseconds = 750 }

    $runDir = Split-Path -Parent $ScreenshotDir
    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $attempt = 1
    Write-LabLine $RunLog "First-battle prompt gate polling for the View the tutorial dialog for up to ${TimeoutMilliseconds}ms."

    while ($true) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                $marker = Join-Path $runDir "first-battle-prompt-gate-failed.txt"
                "First-battle prompt gate failed at ${elapsedSeconds}s: RPCS3 exited before the prompt appeared." | Set-Content -LiteralPath $marker -Encoding UTF8
                Write-LabLine $RunLog "First-battle prompt gate failed: RPCS3 exited before the prompt appeared."
                return $false
            }
        }

        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
        $tag = if ($attempt -eq 1) { "first-battle-prompt-gate" } else { "first-battle-prompt-gate-$attempt" }
        $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $tag
        if (Test-LabFirstBattlePromptScreenshot -Path $screenshotPath) {
            Write-LabLine $RunLog "First-battle prompt gate passed after attempt ${attempt} at ${elapsedSeconds}s."
            return $true
        }
        if (Test-LabActionableFatalScreenshot -Path $screenshotPath) {
            $marker = Join-Path $runDir "first-battle-prompt-gate-failed.txt"
            "First-battle prompt gate stopped at ${elapsedSeconds}s on a probable crash/device-loss overlay." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "First-battle prompt gate failed: probable crash/device-loss overlay."
            return $false
        }

        if ((Get-Date) -ge $deadline) {
            $marker = Join-Path $runDir "first-battle-prompt-gate-failed.txt"
            "First-battle prompt gate timed out at ${elapsedSeconds}s after ${attempt} screenshot(s)." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "First-battle prompt gate failed: timed out after ${TimeoutMilliseconds}ms."
            Write-LabLine $RunLog "First-battle prompt gate marker: $marker"
            return $false
        }

        $remainingMs = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
        Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remainingMs))
        $attempt++
    }
}

function Test-LabActionableFatalLog {
    param(
        [string]$Path,
        [datetime]$LaunchTime
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.LastWriteTime -lt $LaunchTime -or $item.Length -le 0) {
        return $false
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $tailBytes = [Math]::Min([int64]262144, $stream.Length)
        [void]$stream.Seek(-$tailBytes, [System.IO.SeekOrigin]::End)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        $tail = $reader.ReadToEnd()
        return $tail -match '(?im)(unknown draw command|Thread terminated due to fatal error|VM:\s+Access violation|VK_ERROR_DEVICE_LOST|Assertion Failed!|Emulation has been frozen!)'
    } catch {
        return $false
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Test-LabActionableFatalScreenshot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0 -or $item.Length -gt 200000) {
        return $false
    }

    $bitmap = $null
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::new($Path)
        if ($bitmap.Width -lt 64 -or $bitmap.Height -lt 64) {
            return $false
        }

        $darkSamples = 0
        $sampleCount = 0
        for ($row = 1; $row -le 8; $row++) {
            $y = [int][Math]::Round(($bitmap.Height - 1) * ($row / 9.0))
            for ($column = 1; $column -le 12; $column++) {
                $x = [int][Math]::Round(($bitmap.Width - 1) * ($column / 13.0))
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.R -le 24 -and $pixel.G -le 24 -and $pixel.B -le 24) {
                    $darkSamples++
                }
                $sampleCount++
            }
        }

        return $sampleCount -gt 0 -and ($darkSamples / [double]$sampleCount) -ge 0.85
    } catch {
        return $false
    } finally {
        if ($bitmap) { $bitmap.Dispose() }
    }
}

function Invoke-LabLoadTargetGate {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [string]$RunLog,
        [datetime]$LaunchTime = (Get-Date),
        [int]$TimeoutMilliseconds = 15000,
        [int]$PollMilliseconds = 1500
    )

    if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
        Write-LabLine $RunLog "Load target gate failed: no screenshot directory was provided."
        return $false
    }

    $runDir = Split-Path -Parent $ScreenshotDir
    if ([string]::IsNullOrWhiteSpace($runDir)) {
        Write-LabLine $RunLog "Load target gate failed: could not resolve run directory from $ScreenshotDir."
        return $false
    }

    $classifier = Join-Path $PSScriptRoot "classify_eternal_sonata_load_target.ps1"
    if (-not (Test-Path -LiteralPath $classifier -PathType Leaf)) {
        Write-LabLine $RunLog "Load target gate failed: classifier not found at $classifier."
        return $false
    }

    if ($TimeoutMilliseconds -le 0) {
        $TimeoutMilliseconds = 15000
    }
    if ($PollMilliseconds -le 0) {
        $PollMilliseconds = 1500
    }

    function Get-LabLoadTargetGateColorStats {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $null
        }

        try {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
            $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
        } catch {
            return $null
        }

        try {
            $count = 0
            [double]$red = 0
            [double]$green = 0
            [double]$blue = 0
            [int]$greenDominant = 0
            [int]$blueDominant = 0
            [int]$redDominant = 0
            [int]$dark = 0

            for ($y = 0; $y -lt $bitmap.Height; $y += 48) {
                for ($x = 0; $x -lt $bitmap.Width; $x += 48) {
                    $pixel = $bitmap.GetPixel($x, $y)
                    $count++
                    $red += $pixel.R
                    $green += $pixel.G
                    $blue += $pixel.B

                    if ($pixel.G -gt ($pixel.R + 15) -and $pixel.G -gt ($pixel.B + 15)) {
                        $greenDominant++
                    }
                    if ($pixel.B -gt ($pixel.R + 20) -and $pixel.B -gt ($pixel.G + 20)) {
                        $blueDominant++
                    }
                    if ($pixel.R -gt ($pixel.G + 20) -and $pixel.R -gt ($pixel.B + 20)) {
                        $redDominant++
                    }
                    if (($pixel.R + $pixel.G + $pixel.B) -lt 90) {
                        $dark++
                    }
                }
            }

            if ($count -eq 0) {
                return $null
            }

            return [pscustomobject]@{
                AvgR = [math]::Round($red / $count, 1)
                AvgG = [math]::Round($green / $count, 1)
                AvgB = [math]::Round($blue / $count, 1)
                GreenRatio = [math]::Round($greenDominant / $count, 3)
                BlueRatio = [math]::Round($blueDominant / $count, 3)
                RedRatio = [math]::Round($redDominant / $count, 3)
                DarkRatio = [math]::Round($dark / $count, 3)
            }
        } finally {
            $bitmap.Dispose()
        }
    }

    function Test-LabLoadTargetGateBlueNonField {
        param([AllowNull()][object]$ColorStats)

        if (-not $ColorStats) {
            return $false
        }

        return (
            $ColorStats.BlueRatio -ge 0.35 -and
            $ColorStats.GreenRatio -lt 0.20 -and
            $ColorStats.AvgB -ge ($ColorStats.AvgR + 20) -and
            $ColorStats.AvgB -ge ($ColorStats.AvgG + 15)
        )
    }

    function Get-LabLoadTargetGateScreenshotClass {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return ""
        }

        $bytes = (Get-Item -LiteralPath $Path).Length
        $colorStats = Get-LabLoadTargetGateColorStats -Path $Path

        if (Test-LabLoadTargetGateBlueNonField -ColorStats $colorStats) {
            if ($bytes -ge 1000000) {
                return "cutscene-or-nonfield-large-png"
            }
            return "cutscene-or-nonfield-small-png"
        }

        if ($bytes -ge 1000000) {
            if ($colorStats -and (
                $colorStats.RedRatio -ge 0.45 -or
                $colorStats.DarkRatio -ge 0.70 -or
                ($colorStats.GreenRatio -lt 0.15 -and $colorStats.DarkRatio -ge 0.35)
            )) {
                return "cutscene-or-nonfield-large-png"
            }
            return "large-unknown-or-field-like-png"
        }

        if ($bytes -ge 20000 -and $bytes -le 60000) {
            return "black-overlay-small-png"
        }
        if ($bytes -ge 90000 -and $bytes -le 160000) {
            return "loading-like-small-png"
        }
        return "load-ui-or-other-png"
    }

    function Test-LabLoadTargetGateWrongStateClass {
        param([string]$Class)

        return $Class -like "cutscene-or-nonfield-*"
    }

    function Get-LabLoadTargetStatus {
        param([object[]]$ClassifierOutput)

        foreach ($line in @($ClassifierOutput)) {
            $text = "$line"
            if ($text -match '- Status:\s+`+([^`]+)`+') {
                return $matches[1].Trim()
            }
            if ($text -match '- Status:\s+([A-Z_]+)') {
                return $matches[1].Trim()
            }
            if ($text -match '\bgot\s+([A-Z_]+)\b') {
                return $matches[1].Trim()
            }
        }
        return ""
    }

    function Write-LabLoadTargetFailure {
        param(
            [int]$ElapsedSeconds,
            [string]$Message
        )

        $marker = Join-Path $runDir "load-target-gate-failed.txt"
        "Load target gate failed at ${ElapsedSeconds}s: $Message" | Set-Content -LiteralPath $marker -Encoding UTF8
        Write-LabLine $RunLog "Load target gate failed: $Message"
        Write-LabLine $RunLog "Load target gate marker: $marker"
    }

    $deadline = (Get-Date).AddMilliseconds($TimeoutMilliseconds)
    $attempt = 1
    $consecutiveWrongStateScreenshots = 0
    $wrongStateAbortThreshold = 2
    Write-LabLine $RunLog "Load target gate polling for PATH_TO_TENUTO_PRESENT for up to ${TimeoutMilliseconds}ms."
    while ($true) {
        if ($Process) {
            $Process.Refresh()
            if ($Process.HasExited) {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                Write-LabLoadTargetFailure -ElapsedSeconds $elapsedSeconds -Message "RPCS3 exited before the load target could be classified."
                return $false
            }
        }

        $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
        $tag = if ($attempt -eq 1) { "load-target-gate" } else { "load-target-gate-$attempt" }
        $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $tag

        $output = @()
        try {
            $output = @(& $classifier -RunDir $runDir -CandidateScreenshotPaths $screenshotPath -RequirePathToTenuto -NoWriteSummary 2>&1)
            foreach ($line in @($output)) {
                Write-LabLine $RunLog "Load target gate: $line"
            }
            Write-LabLine $RunLog "Load target gate passed after attempt ${attempt}: PATH_TO_TENUTO_PRESENT."
            return $true
        } catch {
            $message = $_.Exception.Message
            $status = Get-LabLoadTargetStatus -ClassifierOutput (@($output) + @($message))
            if ([string]::IsNullOrWhiteSpace($status)) {
                $status = "UNKNOWN_LOAD_TARGET"
            }

            Write-LabLine $RunLog "Load target gate attempt ${attempt}: $status ($message)"
            if ($status -eq "DEBUG_SAVE_PROLOGUE_PRESENT" -or $status -eq "MIXED_LOAD_TARGETS" -or $status -eq "DAMAGED_SAVE_TARGET") {
                foreach ($line in @($output)) {
                    Write-LabLine $RunLog "Load target gate: $line"
                }
                Write-LabLoadTargetFailure -ElapsedSeconds $elapsedSeconds -Message $message
                return $false
            }

            $screenshotClass = Get-LabLoadTargetGateScreenshotClass -Path $screenshotPath
            if (-not [string]::IsNullOrWhiteSpace($screenshotClass)) {
                Write-LabLine $RunLog "Load target gate screenshot class: $screenshotClass"
            }
            if ($status -eq "UNKNOWN_LOAD_TARGET" -and (Test-LabLoadTargetGateWrongStateClass -Class $screenshotClass)) {
                $consecutiveWrongStateScreenshots++
                if ($consecutiveWrongStateScreenshots -ge $wrongStateAbortThreshold) {
                    foreach ($line in @($output)) {
                        Write-LabLine $RunLog "Load target gate: $line"
                    }
                    Write-LabLoadTargetFailure -ElapsedSeconds $elapsedSeconds -Message ("wrong-state/cutscene while waiting for Load list; {0} consecutive {1} screenshots; {2}" -f $consecutiveWrongStateScreenshots, $screenshotClass, $message)
                    return $false
                }
            } else {
                $consecutiveWrongStateScreenshots = 0
            }

            if ((Get-Date) -ge $deadline) {
                foreach ($line in @($output)) {
                    Write-LabLine $RunLog "Load target gate: $line"
                }
                Write-LabLoadTargetFailure -ElapsedSeconds $elapsedSeconds -Message ("timed out after {0}ms; last status {1}; {2}" -f $TimeoutMilliseconds, $status, $message)
                return $false
            }

            $remainingMs = [int][Math]::Max(0, ($deadline - (Get-Date)).TotalMilliseconds)
            Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, $remainingMs))
            $attempt++
        }
    }
}

function Invoke-LabInputMacro {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Macro,
        [ValidateSet("Keyboard", "PadApi")]
        [string]$InputBackend = "Keyboard",
        [string]$PadApiFile = "",
        [int]$StartSeconds,
        [int]$DefaultPressMs,
        [string]$RunLog,
        [string]$ScreenshotDir = "",
        [string]$LiveLogPath = "",
        [datetime]$LaunchTime = (Get-Date)
    )

    if ([string]::IsNullOrWhiteSpace($Macro)) {
        return
    }

    Initialize-LabInput
    if ($InputBackend -eq "PadApi") {
        Set-LabPadApiState -Path $PadApiFile -Keys @()
        Write-LabLine $RunLog "Input backend: PadApi ($PadApiFile)"
    } else {
        Write-LabLine $RunLog "Input backend: Keyboard"
    }

    if ($StartSeconds -gt 0) {
        Write-LabLine $RunLog "Input macro initial wait: ${StartSeconds}s"
        Start-Sleep -Seconds $StartSeconds
    }

    $tokens = @($Macro -split '[;,]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Write-LabLine $RunLog "Input macro tokens: $($tokens.Count)"

    while ($tokens.Count -gt 0) {
        $parts = $tokens[0].Trim() -split ':', 2
        $name = $parts[0].Trim()
        if ($name.ToLowerInvariant() -ne "wait") {
            break
        }

        $duration = $DefaultPressMs
        if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $duration = [int]$parts[1].Trim()
        }

        Write-LabLine $RunLog "Input pre-window wait: ${duration}ms"
        Start-Sleep -Milliseconds $duration
        if ($tokens.Count -eq 1) {
            $tokens = @()
        } else {
            $tokens = @($tokens[1..($tokens.Count - 1)])
        }
    }

    if ($tokens.Count -eq 0) {
        return
    }

    $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 30
    if ($handle -eq [IntPtr]::Zero) {
        Write-LabLine $RunLog "Input macro skipped: RPCS3 game window was not found."
        return
    }

    [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 300

    foreach ($token in $tokens) {
        if (Test-LabActionableFatalLog -Path $LiveLogPath -LaunchTime $LaunchTime) {
            $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
            $runDir = Split-Path -Parent $ScreenshotDir
            $marker = Join-Path $runDir "live-fatal-gate-failed.txt"
            "Actionable RPCS3 fatal detected during the input macro at ${elapsedSeconds}s." | Set-Content -LiteralPath $marker -Encoding UTF8
            Write-LabLine $RunLog "Live fatal gate: stopping RPCS3 at ${elapsedSeconds}s instead of continuing the route."
            Write-LabLine $RunLog "Live fatal gate marker: $marker"
            if (-not $Process.HasExited) {
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500
            }
            return
        }

        $parts = $token.Trim() -split ':', 2
        $name = $parts[0].Trim()
        $nameLower = $name.ToLowerInvariant()
        $duration = $DefaultPressMs

        $shotTag = ""
        if (($nameLower -eq "shot" -or $nameLower -eq "screenshot") -and $parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $shotArg = $parts[1].Trim()
            $parsedDuration = 0
            if ([int]::TryParse($shotArg, [ref]$parsedDuration)) {
                $duration = $parsedDuration
            } else {
                $shotTag = $shotArg
            }
        } elseif ($nameLower -ne "combo" -and $parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $duration = [int]$parts[1].Trim()
        }

        if ($nameLower -eq "wait") {
            Write-LabLine $RunLog "Input wait: ${duration}ms"
            Start-Sleep -Milliseconds $duration
            continue
        }

        if ($nameLower -eq "focus") {
            $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
            if ($handle -ne [IntPtr]::Zero) {
                [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
                Write-LabLine $RunLog "Input focus"
                Start-Sleep -Milliseconds $duration
            }
            continue
        }

        if ($nameLower -eq "move2" -or $nameLower -eq "secondary") {
            Move-LabWindowToSecondaryMonitor -Process $Process -RunLog $RunLog
            $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
            if ($handle -ne [IntPtr]::Zero) {
                [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
            }
            Start-Sleep -Milliseconds $duration
            continue
        }

        if ($nameLower -eq "shot" -or $nameLower -eq "screenshot") {
            if ([string]::IsNullOrWhiteSpace($ScreenshotDir)) {
                Write-LabLine $RunLog "Input screenshot skipped: no screenshot directory was provided."
            } else {
                $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $LaunchTime).TotalSeconds)
                $screenshotPath = Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $shotTag
                if (Test-LabActionableFatalScreenshot -Path $screenshotPath) {
                    $runDir = Split-Path -Parent $ScreenshotDir
                    $marker = Join-Path $runDir "live-fatal-visual-gate-failed.txt"
                    "Probable RPCS3 crash or device-loss overlay detected at ${elapsedSeconds}s in $screenshotPath." | Set-Content -LiteralPath $marker -Encoding UTF8
                    Write-LabLine $RunLog "Live fatal visual gate: stopping RPCS3 at ${elapsedSeconds}s instead of continuing the route."
                    Write-LabLine $RunLog "Live fatal visual gate marker: $marker"
                    if (-not $Process.HasExited) {
                        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 500
                    }
                    return
                }
            }
            Start-Sleep -Milliseconds $duration
            continue
        }

        if ($nameLower -eq "gate_title_menu" -or $nameLower -eq "wait_title_menu" -or $nameLower -eq "assert_title_menu") {
            $gateTimeoutMilliseconds = if ($duration -gt 0) { $duration } else { 90000 }
            Write-LabLine $RunLog "Input title-menu gate (timeout ${gateTimeoutMilliseconds}ms)"
            $gatePassed = Invoke-LabTitleMenuGate -Process $Process -ScreenshotDir $ScreenshotDir -RunLog $RunLog -LaunchTime $LaunchTime -TimeoutMilliseconds $gateTimeoutMilliseconds
            if (-not $gatePassed) {
                Write-LabLine $RunLog "Input macro aborted before title-menu navigation because the gate failed."
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                return
            }
            continue
        }

        if ($nameLower -eq "gate_load_target" -or $nameLower -eq "assert_load_target" -or $nameLower -eq "load_target_gate") {
            $gateTimeoutMilliseconds = if ($duration -gt 0) { $duration } else { 15000 }
            Write-LabLine $RunLog "Input load target gate (timeout ${gateTimeoutMilliseconds}ms)"
            $gatePassed = Invoke-LabLoadTargetGate -Process $Process -ScreenshotDir $ScreenshotDir -RunLog $RunLog -LaunchTime $LaunchTime -TimeoutMilliseconds $gateTimeoutMilliseconds
            if (-not $gatePassed) {
                Write-LabLine $RunLog "Input macro aborted before pressing Cross because the load target gate failed."
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                return
            }
            continue
        }

        if ($nameLower -eq "gate_load_complete" -or $nameLower -eq "wait_load_complete" -or $nameLower -eq "assert_load_complete") {
            $gateTimeoutMilliseconds = if ($duration -gt 0) { $duration } else { 60000 }
            Write-LabLine $RunLog "Input load-complete gate (timeout ${gateTimeoutMilliseconds}ms)"
            $gatePassed = Invoke-LabLoadCompleteGate -Process $Process -ScreenshotDir $ScreenshotDir -RunLog $RunLog -LaunchTime $LaunchTime -TimeoutMilliseconds $gateTimeoutMilliseconds
            if (-not $gatePassed) {
                Write-LabLine $RunLog "Input macro aborted before dismissing the load-complete banner because the gate failed."
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                return
            }
            continue
        }

        if ($nameLower -eq "gate_path_to_tenuto_field" -or $nameLower -eq "gate_field" -or $nameLower -eq "assert_field") {
            $gateTimeoutMilliseconds = if ($duration -gt 0) { $duration } else { 30000 }
            Write-LabLine $RunLog "Input Path-to-Tenuto field gate (timeout ${gateTimeoutMilliseconds}ms)"
            $gatePassed = Invoke-LabPathToTenutoFieldGate -Process $Process -ScreenshotDir $ScreenshotDir -RunLog $RunLog -LaunchTime $LaunchTime -TimeoutMilliseconds $gateTimeoutMilliseconds
            if (-not $gatePassed) {
                Write-LabLine $RunLog "Input macro aborted before field movement because the gate failed."
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                return
            }
            continue
        }

        if ($nameLower -eq "gate_first_battle_prompt" -or $nameLower -eq "wait_first_battle_prompt" -or $nameLower -eq "assert_first_battle_prompt") {
            $gateTimeoutMilliseconds = if ($duration -gt 0) { $duration } else { 20000 }
            Write-LabLine $RunLog "Input first-battle prompt gate (timeout ${gateTimeoutMilliseconds}ms)"
            $gatePassed = Invoke-LabFirstBattlePromptGate -Process $Process -ScreenshotDir $ScreenshotDir -RunLog $RunLog -LaunchTime $LaunchTime -TimeoutMilliseconds $gateTimeoutMilliseconds
            if (-not $gatePassed) {
                Write-LabLine $RunLog "Input macro aborted before first-battle prompt input because the gate failed."
                if (-not $Process.HasExited) {
                    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                }
                return
            }
            continue
        }

        if ($nameLower -eq "combo") {
            try {
                if ($parts.Count -lt 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
                    throw "Input combo token must look like combo:key1+key2:duration."
                }

                $comboParts = $parts[1].Trim() -split ':', 2
                $comboKeys = @($comboParts[0] -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($comboKeys.Count -eq 0) {
                    throw "Input combo token must include at least one key."
                }

                if ($comboParts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($comboParts[1])) {
                    $duration = [int]$comboParts[1].Trim()
                }

                Write-LabLine $RunLog "Input combo: $($comboKeys -join '+') ${duration}ms"
                if ($InputBackend -eq "PadApi") {
                    Set-LabPadApiState -Path $PadApiFile -Keys $comboKeys
                    Start-Sleep -Milliseconds $duration
                    Set-LabPadApiState -Path $PadApiFile -Keys @()
                } else {
                    $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
                    if ($handle -ne [IntPtr]::Zero) {
                        [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
                    }

                    $comboVks = @($comboKeys | ForEach-Object { Get-LabVirtualKey $_ })
                    foreach ($vk in $comboVks) {
                        [LabInput.Win32]::keybd_event($vk, 0, (Get-LabKeyboardEventFlags -VirtualKey $vk), [UIntPtr]::Zero)
                    }
                    Start-Sleep -Milliseconds $duration
                    for ($i = $comboVks.Count - 1; $i -ge 0; $i--) {
                        [LabInput.Win32]::keybd_event($comboVks[$i], 0, (Get-LabKeyboardEventFlags -VirtualKey $comboVks[$i] -KeyUp), [UIntPtr]::Zero)
                    }
                }
                Start-Sleep -Milliseconds 80
            } catch {
                Write-LabLine $RunLog "Input combo failed: $($_.Exception.Message)"
                throw
            }
            continue
        }

        Write-LabLine $RunLog "Input press: $name ${duration}ms"
        if ($InputBackend -eq "PadApi") {
            Set-LabPadApiState -Path $PadApiFile -Keys @($name)
            Start-Sleep -Milliseconds $duration
            Set-LabPadApiState -Path $PadApiFile -Keys @()
        } else {
            $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
            if ($handle -ne [IntPtr]::Zero) {
                [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
            }

            $vk = Get-LabVirtualKey $name
            [LabInput.Win32]::keybd_event($vk, 0, (Get-LabKeyboardEventFlags -VirtualKey $vk), [UIntPtr]::Zero)
            Start-Sleep -Milliseconds $duration
            [LabInput.Win32]::keybd_event($vk, 0, (Get-LabKeyboardEventFlags -VirtualKey $vk -KeyUp), [UIntPtr]::Zero)
        }
        Start-Sleep -Milliseconds 80
    }
}

function Initialize-LabVisual {
    if (-not ("LabVisual.Win32" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace LabVisual
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static class Win32
    {
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool BringWindowToTop(IntPtr hWnd);
    }
}
"@
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

function Set-LabWindowForeground {
    param([IntPtr]$Handle)

    if ($Handle -eq [IntPtr]::Zero) {
        return
    }

    $swRestore = 9
    $flagsNoMoveNoSizeShow = 0x0001 -bor 0x0002 -bor 0x0040
    $hwndTopMost = [IntPtr]::new(-1)
    $hwndNoTopMost = [IntPtr]::new(-2)

    [LabVisual.Win32]::ShowWindow($Handle, $swRestore) | Out-Null
    [LabVisual.Win32]::BringWindowToTop($Handle) | Out-Null
    [LabVisual.Win32]::SetForegroundWindow($Handle) | Out-Null
    [LabVisual.Win32]::SetWindowPos($Handle, $hwndTopMost, 0, 0, 0, 0, $flagsNoMoveNoSizeShow) | Out-Null
    [LabVisual.Win32]::SetWindowPos($Handle, $hwndNoTopMost, 0, 0, 0, 0, $flagsNoMoveNoSizeShow) | Out-Null
    [LabVisual.Win32]::BringWindowToTop($Handle) | Out-Null
    [LabVisual.Win32]::SetForegroundWindow($Handle) | Out-Null
}

function Move-LabWindowToSecondaryMonitor {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$RunLog
    )

    Initialize-LabVisual

    $secondary = [System.Windows.Forms.Screen]::AllScreens |
        Where-Object { -not $_.Primary } |
        Select-Object -First 1

    if (-not $secondary) {
        Write-LabLine $RunLog "- Secondary monitor: not found; leaving RPCS3 window on current display"
        return
    }

    $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 30
    if ($handle -eq [IntPtr]::Zero) {
        Write-LabLine $RunLog "- Secondary monitor: RPCS3 game window was not found"
        return
    }

    $rect = New-Object LabVisual.RECT
    if (-not [LabVisual.Win32]::GetWindowRect($handle, [ref]$rect)) {
        Write-LabLine $RunLog "- Secondary monitor: could not read RPCS3 window bounds"
        return
    }

    $width = [Math]::Max(640, $rect.Right - $rect.Left)
    $height = [Math]::Max(360, $rect.Bottom - $rect.Top)
    $area = $secondary.WorkingArea
    $x = $area.Left + [Math]::Max(0, [int](($area.Width - $width) / 2))
    $y = $area.Top + [Math]::Max(0, [int](($area.Height - $height) / 2))
    $flagsNoZOrder = 0x0004

    [LabVisual.Win32]::SetWindowPos($handle, [IntPtr]::Zero, $x, $y, $width, $height, $flagsNoZOrder) | Out-Null
    Set-LabWindowForeground -Handle $handle
    Write-LabLine $RunLog "- Secondary monitor: moved RPCS3 window to $($secondary.DeviceName) at ${x},${y} (${width}x${height})"
}

function Convert-LabCsvField {
    param([string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }

    return '"' + ($Value -replace '"', '""') + '"'
}

function Write-LabWindowTitleSample {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$TitleSamplesPath,
        [string]$RunLog,
        [int]$ElapsedSeconds,
        [string]$Phase
    )

    if ([string]::IsNullOrWhiteSpace($TitleSamplesPath)) {
        return
    }

    $title = ""
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $title = $Process.MainWindowTitle
        }
    } catch {
        $title = ""
    }

    $fps = ""
    if ($title -match 'FPS:\s*(?<fps>[0-9]+(?:\.[0-9]+)?)') {
        $fps = $Matches.fps
    }

    $titleDir = Split-Path -Parent $TitleSamplesPath
    if (-not [string]::IsNullOrWhiteSpace($titleDir)) {
        New-Item -ItemType Directory -Force -Path $titleDir | Out-Null
    }

    if (-not (Test-Path -LiteralPath $TitleSamplesPath -PathType Leaf)) {
        "timestamp,elapsed_seconds,phase,fps,window_title" | Set-Content -LiteralPath $TitleSamplesPath -Encoding UTF8
    }

    $fields = @(
        (Convert-LabCsvField (Get-Date -Format o)),
        $ElapsedSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture),
        (Convert-LabCsvField $Phase),
        (Convert-LabCsvField $fps),
        (Convert-LabCsvField $title)
    )
    Add-Content -LiteralPath $TitleSamplesPath -Value ($fields -join ",") -Encoding UTF8

    if (-not [string]::IsNullOrWhiteSpace($title)) {
        $fpsText = if ([string]::IsNullOrWhiteSpace($fps)) { "n/a" } else { $fps }
        Write-LabLine $RunLog "- Window title sample [$Phase]: fps=$fpsText; title=$title"
    }
}

function Save-LabScreenshot {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [int]$ElapsedSeconds,
        [string]$RunLog,
        [string]$Tag = ""
    )

    Initialize-LabVisual

    $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
    if ($handle -eq [IntPtr]::Zero) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $exitCode = if ($null -eq $Process.ExitCode -or "$($Process.ExitCode)" -eq "") { "exited" } else { "$($Process.ExitCode)" }
            Write-LabLine $RunLog "Screenshot skipped at ${ElapsedSeconds}s: game window was not found; process has exited with code $exitCode."
        } else {
            Write-LabLine $RunLog "Screenshot skipped at ${ElapsedSeconds}s: game window was not found; process is still running with an empty MainWindowHandle."
        }
        return
    }

    $rect = New-Object LabVisual.RECT
    if (-not [LabVisual.Win32]::GetWindowRect($handle, [ref]$rect)) {
        Write-LabLine $RunLog "Screenshot skipped at ${ElapsedSeconds}s: could not read window bounds."
        return
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
        Write-LabLine $RunLog "Screenshot skipped at ${ElapsedSeconds}s: invalid window bounds ${width}x${height}."
        return
    }

    New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
    Set-LabWindowForeground -Handle $handle
    Start-Sleep -Milliseconds 250

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [System.Drawing.Size]::new($width, $height))
        $safeTag = ""
        if (-not [string]::IsNullOrWhiteSpace($Tag)) {
            $safeTag = ($Tag.Trim() -replace '[^A-Za-z0-9_.-]', '-').Trim("-")
            if ($safeTag.Length -gt 48) {
                $safeTag = $safeTag.Substring(0, 48)
            }
        }

        $baseName = if ([string]::IsNullOrWhiteSpace($safeTag)) {
            "screenshot-{0:0000}s.png" -f $ElapsedSeconds
        } else {
            "screenshot-{0:0000}s-{1}.png" -f $ElapsedSeconds, $safeTag
        }

        $path = Join-Path $ScreenshotDir $baseName
        $suffix = 1
        while (Test-Path -LiteralPath $path) {
            $baseName = if ([string]::IsNullOrWhiteSpace($safeTag)) {
                "screenshot-{0:0000}s-{1:00}.png" -f $ElapsedSeconds, $suffix
            } else {
                "screenshot-{0:0000}s-{1}-{2:00}.png" -f $ElapsedSeconds, $safeTag, $suffix
            }
            $path = Join-Path $ScreenshotDir $baseName
            $suffix++
        }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-LabLine $RunLog "Screenshot: $path"
        $titleSamplesPath = Join-Path (Split-Path -Parent $ScreenshotDir) "window-title-samples.csv"
        Write-LabWindowTitleSample -Process $Process -TitleSamplesPath $titleSamplesPath -RunLog $RunLog -ElapsedSeconds $ElapsedSeconds -Phase ("screenshot:{0}" -f (Split-Path -Leaf $path))
    } finally {
        $graphics.Dispose()
        $bmp.Dispose()
    }

    return $path
}

function Set-LabFpsOverlayConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $false
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $original = [System.IO.File]::ReadAllText($ConfigPath, $utf8NoBom)
    $lines = [System.Collections.Generic.List[string]]::new()
    $inPerfOverlay = $false
    foreach ($line in [System.IO.File]::ReadLines($ConfigPath, $utf8NoBom)) {
        $newLine = $line

        if ($line -match '^  Performance Overlay:') {
            $inPerfOverlay = $true
        } elseif ($inPerfOverlay -and $line -match '^  \S') {
            $inPerfOverlay = $false
        }

        if ($inPerfOverlay -and $line -match '^    Enabled: ') {
            $newLine = '    Enabled: true'
        } elseif ($inPerfOverlay -and $line -match '^    Enable Framerate Graph: ') {
            $newLine = '    Enable Framerate Graph: true'
        } elseif ($inPerfOverlay -and $line -match '^    Enable Frametime Graph: ') {
            $newLine = '    Enable Frametime Graph: true'
        } elseif ($inPerfOverlay -and $line -match '^    Detail level: ') {
            $newLine = '    Detail level: Medium'
        } elseif ($inPerfOverlay -and $line -match '^    Metrics update interval \(ms\): ') {
            $newLine = '    Metrics update interval (ms): 250'
        } elseif ($line -match '^  Start games in fullscreen mode: ') {
            $newLine = '  Start games in fullscreen mode: false'
        } elseif ($line -match '^  Background input enabled: ') {
            $newLine = '  Background input enabled: true'
        } elseif ($line -match '^  Lock overlay input to player one: ') {
            $newLine = '  Lock overlay input to player one: false'
        } elseif ($line -match '^  Window Title Format: ') {
            $newLine = '  Window Title Format: "FPS: %F | %R | %V | %T [%t]"'
        }

        $lines.Add($newLine)
    }

    $updated = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    if ($updated -ne $original) {
        [System.IO.File]::WriteAllText($ConfigPath, $updated, $utf8NoBom)
        return $true
    }

    return $false
}

function Set-LabForceHwMsaaResolveConfig {
    param(
        [string]$ConfigPath,
        [string]$Mode
    )

    if ($Mode -eq "Keep" -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $original = [System.IO.File]::ReadAllText($ConfigPath, $utf8NoBom)
    $lines = [System.Collections.Generic.List[string]]::new()
    $found = $false
    $oldValue = ""
    $newValue = if ($Mode -eq "On") { "true" } else { "false" }

    foreach ($line in [System.IO.File]::ReadLines($ConfigPath, $utf8NoBom)) {
        if ($line -match '^  Force Hardware MSAA Resolve: (?<value>\S+)\s*$') {
            $found = $true
            $oldValue = $Matches['value']
            $lines.Add("  Force Hardware MSAA Resolve: $newValue")
        } else {
            $lines.Add($line)
        }
    }

    $updated = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    if ($updated -ne $original) {
        [System.IO.File]::WriteAllText($ConfigPath, $updated, $utf8NoBom)
    }

    return [pscustomobject]@{
        found = $found
        old_value = $oldValue
        new_value = $newValue
        changed = ($updated -ne $original)
    }
}

function New-LabRunConfig {
    param(
        [string]$SourcePath,
        [string]$RunDir,
        [string]$FrameLimit,
        [int]$VblankRate,
        [string]$SpuAccurateReservations,
        [string]$SpuAccurateDma,
        [string]$EternalSonataSpuHeatProfile,
        [string]$EternalSonataPpuRsxProfile,
        [string]$PpuDazAndFtz,
        [string]$RunLog
    )

    if ($FrameLimit -eq "Keep" -and $VblankRate -le 0 -and $SpuAccurateReservations -eq "Keep" -and $SpuAccurateDma -eq "Keep" -and $EternalSonataSpuHeatProfile -eq "Off" -and $EternalSonataPpuRsxProfile -eq "Off" -and $PpuDazAndFtz -eq "Keep") {
        return $null
    }
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        Write-LabLine $RunLog "- Run config override: skipped; missing source config"
        return $null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $target = Join-Path $RunDir "rpcs3-run-config.yml"
    $lines = New-Object System.Collections.Generic.List[string]
    $frameValue = switch ($FrameLimit) {
        "Off" { "Off" }
        "Auto" { "Auto" }
        "PS3Native" { "PS3 Native" }
        "30" { "30" }
        "60" { "60" }
        "120" { "120" }
        "240" { "240" }
        default { "" }
    }
    $accurateReservationsValue = switch ($SpuAccurateReservations) {
        "On" { "true" }
        "Off" { "false" }
        default { "" }
    }
    $accurateDmaValue = switch ($SpuAccurateDma) {
        "On" { "true" }
        "Off" { "false" }
        default { "" }
    }
    $spuProfilerValue = switch ($EternalSonataSpuHeatProfile) {
        "Profile" { "true" }
        default { "" }
    }
    $ppuProfilerValue = switch ($EternalSonataPpuRsxProfile) {
        "Profile" { "true" }
        default { "" }
    }
    $dazAndFtzValue = switch ($PpuDazAndFtz) {
        "On" { "true" }
        "Off" { "false" }
        default { "" }
    }

    $inCore = $false
    $inVideo = $false
    foreach ($line in [System.IO.File]::ReadLines($SourcePath, $utf8NoBom)) {
        $newLine = $line
        if ($line -match '^Core:\s*$') {
            $inCore = $true
            $inVideo = $false
        } elseif ($line -match '^Video:\s*$') {
            $inCore = $false
            $inVideo = $true
        } elseif ($line -match '^[^ ].*:\s*$') {
            $inCore = $false
            $inVideo = $false
        }

        if ($inCore -and $dazAndFtzValue -and $line -match '^  Set DAZ and FTZ: ') {
            $newLine = "  Set DAZ and FTZ: $dazAndFtzValue"
        } elseif ($inCore -and $accurateReservationsValue -and $line -match '^  Accurate SPU Reservations: ') {
            $newLine = "  Accurate SPU Reservations: $accurateReservationsValue"
        } elseif ($inCore -and $accurateDmaValue -and $line -match '^  Accurate SPU DMA: ') {
            $newLine = "  Accurate SPU DMA: $accurateDmaValue"
        } elseif ($inCore -and $spuProfilerValue -and $line -match '^  SPU Profiler: ') {
            $newLine = "  SPU Profiler: $spuProfilerValue"
        } elseif ($inCore -and $ppuProfilerValue -and $line -match '^  PPU Profiler: ') {
            $newLine = "  PPU Profiler: $ppuProfilerValue"
        }

        if ($inVideo) {
            if ($frameValue -and $line -match '^  Frame limit: ') {
                $newLine = "  Frame limit: $frameValue"
            } elseif ($VblankRate -gt 0 -and $line -match '^  Vblank Rate: ') {
                $newLine = "  Vblank Rate: $VblankRate"
            } elseif ($line -match '^  Write Color Buffers: ') {
                $newLine = '  Write Color Buffers: true'
            }
        }

        $lines.Add($newLine) | Out-Null
    }

    [System.IO.File]::WriteAllText($target, (($lines.ToArray()) -join "`n") + "`n", $utf8NoBom)
    return [pscustomobject]@{
        path                      = $target
        frame_limit               = $(if ($frameValue) { $frameValue } else { "default" })
        vblank_rate               = $(if ($VblankRate -gt 0) { $VblankRate } else { "default" })
        spu_accurate_reservations = $(if ($accurateReservationsValue) { $accurateReservationsValue } else { "default" })
        spu_accurate_dma          = $(if ($accurateDmaValue) { $accurateDmaValue } else { "default" })
        spu_profiler              = $(if ($spuProfilerValue) { $spuProfilerValue } else { "default" })
        ppu_profiler              = $(if ($ppuProfilerValue) { $ppuProfilerValue } else { "default" })
        ppu_daz_and_ftz           = $(if ($dazAndFtzValue) { $dazAndFtzValue } else { "default" })
    }
}

function Update-LabConfigDatabase {
    param(
        [string]$ConfigDbPath,
        [string]$TitleId,
        [bool]$Force,
        [bool]$Skip,
        [string]$RunLog
    )

    $url = "https://api.rpcs3.net/config/?api=v1"
    $refreshNeeded = $Force -or -not (Test-Path -LiteralPath $ConfigDbPath -PathType Leaf)

    if (-not $refreshNeeded -and (Test-Path -LiteralPath $ConfigDbPath -PathType Leaf)) {
        $age = (Get-Date) - (Get-Item -LiteralPath $ConfigDbPath).LastWriteTime
        $refreshNeeded = $age.TotalHours -ge 24
    }

    if ($Skip) {
        Write-LabLine $RunLog "- Config DB refresh: skipped"
    } elseif ($refreshNeeded) {
        try {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigDbPath) | Out-Null
            $tmp = "$ConfigDbPath.tmp"
            Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -OutFile $tmp
            Move-Item -LiteralPath $tmp -Destination $ConfigDbPath -Force
            $item = Get-Item -LiteralPath $ConfigDbPath
            Write-LabLine $RunLog "- Config DB refresh: downloaded $($item.Length) bytes"
        } catch {
            Write-LabLine $RunLog "- Config DB refresh: failed: $($_.Exception.Message)"
            if (Test-Path -LiteralPath "$ConfigDbPath.tmp") {
                Remove-Item -LiteralPath "$ConfigDbPath.tmp" -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        Write-LabLine $RunLog "- Config DB refresh: cached"
    }

    if (-not (Test-Path -LiteralPath $ConfigDbPath -PathType Leaf)) {
        Write-LabLine $RunLog "- Config DB: missing"
        return
    }

    try {
        $json = Get-Content -LiteralPath $ConfigDbPath -Raw | ConvertFrom-Json
        $game = $json.games.PSObject.Properties[$TitleId]
        if ($game) {
            Write-LabLine $RunLog "- Config DB entry for ${TitleId}: present"
            $configText = $game.Value.config
            foreach ($line in ($configText -split "`n")) {
                Write-LabLine $RunLog "  $line"
            }
        } else {
            Write-LabLine $RunLog "- Config DB entry for ${TitleId}: absent"
        }
    } catch {
        Write-LabLine $RunLog "- Config DB parse: failed: $($_.Exception.Message)"
    }
}

$repoRoot = Get-LabRepoRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$rpcs3Root = Join-Path $workspaceRoot "rpcs3-upstream"
$rpcs3Bin = if ([string]::IsNullOrWhiteSpace($Rpcs3BinOverride)) {
    Join-Path $rpcs3Root "build-msvc\bin"
} else {
    Resolve-LabPath $Rpcs3BinOverride
}
$rpcs3Exe = Join-Path $rpcs3Bin "rpcs3.exe"
$rpcs3LogDir = Join-Path $rpcs3Bin "log"
$rpcs3Config = Join-Path $rpcs3Bin "config\config.yml"
$rpcs3ConfigDb = Join-Path $rpcs3Bin "GuiConfigs\config_database.dat"
$qtRoot = "C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\qt\6.10.3\msvc2022_64"
$vcpkgRoot = "C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\vcpkg\installed\x64-windows"
$qtBin = Join-Path $qtRoot "bin"
$vcpkgBin = Join-Path $vcpkgRoot "bin"

if (-not (Test-Path -LiteralPath $rpcs3Exe)) {
    throw "Missing RPCS3 executable: $rpcs3Exe"
}
if (-not (Test-Path -LiteralPath $qtBin)) {
    throw "Missing Qt bin path: $qtBin"
}
if (-not (Test-Path -LiteralPath $vcpkgBin)) {
    throw "Missing vcpkg Vulkan bin path: $vcpkgBin"
}

$safeLabel = New-LabSafeLabel $Label
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$captureRoot = Join-Path $repoRoot "debug-captures\windows-lab"
$runDirName = if ($NoTimestampDir) { $safeLabel } else { "$stamp-$safeLabel" }
$runDir = Join-Path $captureRoot $runDirName
$runLog = Join-Path $runDir "windows-rpcs3-lab.txt"
$stdoutPath = Join-Path $runDir "rpcs3.stdout.txt"
$stderrPath = Join-Path $runDir "rpcs3.stderr.txt"

New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $rpcs3LogDir | Out-Null

Write-LabLine $runLog "# Windows RPCS3 Lab"
Write-LabLine $runLog ""
Write-LabLine $runLog "- Created: $(Get-Date -Format o)"
Write-LabLine $runLog "- Action: $Action"
Write-LabLine $runLog "- Label: $safeLabel"
Write-LabLine $runLog "- RPCS3: $rpcs3Exe"
Write-LabLine $runLog "- Qt: $qtRoot"
Write-LabLine $runLog "- Vulkan/vcpkg: $vcpkgRoot"
$fpsConfigChanged = Set-LabFpsOverlayConfig -ConfigPath $rpcs3Config
Write-LabLine $runLog "- FPS overlay config: $(if ($fpsConfigChanged) { 'updated' } else { 'already-enabled-or-missing' })"
$forceHwMsaaResolveOverride = Set-LabForceHwMsaaResolveConfig -ConfigPath $rpcs3Config -Mode $RsxForceHwMsaaResolve
if ($null -eq $forceHwMsaaResolveOverride) {
    Write-LabLine $runLog "- Force Hardware MSAA Resolve override: keep"
} elseif ($forceHwMsaaResolveOverride.found) {
    Write-LabLine $runLog "- Force Hardware MSAA Resolve override: $($forceHwMsaaResolveOverride.old_value) -> $($forceHwMsaaResolveOverride.new_value) changed=$($forceHwMsaaResolveOverride.changed)"
} else {
    Write-LabLine $runLog "- Force Hardware MSAA Resolve override: key missing"
}
$runConfigOverride = New-LabRunConfig -SourcePath $rpcs3Config -RunDir $runDir -FrameLimit $FrameLimit -VblankRate $VblankRate -SpuAccurateReservations $SpuAccurateReservations -SpuAccurateDma $SpuAccurateDma -EternalSonataSpuHeatProfile $EternalSonataSpuHeatProfile -EternalSonataPpuRsxProfile $EternalSonataPpuRsxProfile -PpuDazAndFtz $PpuDazAndFtz -RunLog $runLog
if ($null -eq $runConfigOverride) {
    Write-LabLine $runLog "- Run config override: keep"
} else {
    Write-LabLine $runLog "- Run config override: $($runConfigOverride.path)"
    Write-LabLine $runLog "- Run config frame limit: $($runConfigOverride.frame_limit)"
    Write-LabLine $runLog "- Run config vblank rate: $($runConfigOverride.vblank_rate)"
    Write-LabLine $runLog "- Run config Accurate SPU Reservations: $($runConfigOverride.spu_accurate_reservations)"
    Write-LabLine $runLog "- Run config Accurate SPU DMA: $($runConfigOverride.spu_accurate_dma)"
    Write-LabLine $runLog "- Run config SPU Profiler: $($runConfigOverride.spu_profiler)"
    Write-LabLine $runLog "- Run config PPU Profiler: $($runConfigOverride.ppu_profiler)"
    Write-LabLine $runLog "- Run config Set DAZ and FTZ: $($runConfigOverride.ppu_daz_and_ftz)"
    Write-LabLine $runLog "- Run config Write Color Buffers: forced true"
}
Update-LabConfigDatabase -ConfigDbPath $rpcs3ConfigDb -TitleId $TitleId -Force ([bool]$RefreshConfigDb) -Skip ([bool]$SkipConfigDbRefresh) -RunLog $runLog
if ($Action -eq "Run") {
    if ($SkipAgentInputProfile) {
        Write-LabLine $runLog "- Agent input profile: skipped"
    } else {
        Set-LabAgentInputProfile -Rpcs3Bin $rpcs3Bin -TitleId $TitleId -RunLog $runLog
    }
}

if ($Action -eq "LocateGame") {
    $roots = if ($SearchRoots.Count -gt 0) { $SearchRoots } else { Get-LabDefaultSearchRoots }
    Write-LabLine $runLog "- Title ID: $TitleId"
    Write-LabLine $runLog ""
    Write-LabLine $runLog "## Search roots"
    foreach ($root in $roots) {
        Write-LabLine $runLog "- $root"
    }

    $candidateMatches = @(Find-LabBootCandidates -Roots $roots -TitleId $TitleId)

    Write-LabLine $runLog ""
    Write-LabLine $runLog "## Boot Targets"
    if ($candidateMatches.Count -eq 0) {
        Write-LabLine $runLog "No candidate Windows-side boot target found."
    } else {
        foreach ($match in $candidateMatches) {
            Write-LabLine $runLog "- $match"
        }
    }

    Write-LabLine $runLog ""
    Write-LabLine $runLog "Run log: $runLog"
    return
}

$env:Qt6_ROOT = $qtRoot
$env:QTDIR = $qtRoot
$env:VULKAN_SDK = $vcpkgRoot
$env:RPCS3_LAB_NO_FATAL_DIALOG = "1"
# Some Windows hosts expose both Path and PATH. Canonicalize before creating
# ProcessStartInfo because its case-insensitive environment map rejects both.
$processEnvironment = [Environment]::GetEnvironmentVariables("Process")
$pathVariables = @($processEnvironment.Keys | Where-Object { [string]$_ -ieq "Path" } | ForEach-Object {
    [pscustomobject]@{
        Name = [string]$_
        Value = [string]$processEnvironment[$_]
    }
})
$inheritedPath = [string]($pathVariables | Where-Object { $_.Name -ceq "PATH" } | Select-Object -First 1).Value
if ([string]::IsNullOrWhiteSpace($inheritedPath)) {
    $inheritedPath = [string]($pathVariables | Where-Object { $_.Name -ceq "Path" } | Select-Object -First 1).Value
}
if ([string]::IsNullOrWhiteSpace($inheritedPath)) {
    throw "The process environment does not contain a usable Path value."
}
foreach ($pathVariable in $pathVariables) {
    [Environment]::SetEnvironmentVariable($pathVariable.Name, $null, "Process")
}
[Environment]::SetEnvironmentVariable("Path", "$qtBin;$vcpkgBin;$inheritedPath", "Process")

if ($Action -eq "InstallFirmware") {
    if ([string]::IsNullOrWhiteSpace($FirmwarePath)) {
        $defaultFirmware = Join-Path $env:USERPROFILE "Downloads\PS3UPDAT.PUP"
        if (Test-Path -LiteralPath $defaultFirmware -PathType Leaf) {
            $FirmwarePath = $defaultFirmware
        } else {
            throw "Action InstallFirmware requires -FirmwarePath, or PS3UPDAT.PUP in Downloads."
        }
    }

    $FirmwarePath = Resolve-LabPath $FirmwarePath
    if (-not (Test-Path -LiteralPath $FirmwarePath -PathType Leaf)) {
        throw "Firmware file does not exist: $FirmwarePath"
    }

    if ($MaxSeconds -eq 20) {
        $MaxSeconds = 300
    }
}

$argsList = New-Object System.Collections.Generic.List[string]
if ($Action -eq "Smoke") {
    $argsList.Add("--headless")
    $argsList.Add("--no-gui")
} elseif ($Action -eq "InstallFirmware") {
    $argsList.Add("--installfw")
    $argsList.Add($FirmwarePath)
} else {
    if ([string]::IsNullOrWhiteSpace($BootTarget)) {
        $isoRoot = Join-Path $repoRoot "iso"
        $foundTargets = @(Find-LabBootCandidates -Roots @($isoRoot) -TitleId $TitleId)
        if ($foundTargets.Count -eq 1) {
            $BootTarget = $foundTargets[0]
        } elseif ($foundTargets.Count -eq 0) {
            throw "Action Run requires -BootTarget, or exactly one boot target under $isoRoot."
        } else {
            throw "Multiple boot targets found under $isoRoot. Re-run with -BootTarget set to one exact path."
        }
    }

    if ($Mode -eq "Headless") {
        $argsList.Add("--headless")
    } elseif ($Mode -eq "NoGui") {
        $argsList.Add("--no-gui")
        if ($GameScreen -ge 0) {
            $argsList.Add("--game-screen")
            $argsList.Add("$GameScreen")
        }
    }

    if ($null -ne $runConfigOverride) {
        $argsList.Add("--config")
        $argsList.Add($runConfigOverride.path)
    }

    $BootTarget = Resolve-LabBootTarget $BootTarget
    $argsList.Add($BootTarget)
}

Write-LabLine $runLog "- Mode: $Mode"
Write-LabLine $runLog "- Eternal Sonata SPURS superpath: $EternalSonataSuperPath"
if ($EternalSonataJoinSpin -ge 0) {
    Write-LabLine $runLog "- Eternal Sonata SPURS join spin: $EternalSonataJoinSpin"
}
Write-LabLine $runLog "- Eternal Sonata SPURS wait superpath: $EternalSonataWaitSuperPath"
if ($EternalSonataWaitSuperPath -eq "Clamp") {
    Write-LabLine $runLog "- Eternal Sonata SPURS wait max us: $EternalSonataWaitMaxUs"
}
Write-LabLine $runLog "- Eternal Sonata semaphore ESRCH superpath: $EternalSonataSemaphoreSuperPath"
Write-LabLine $runLog "- Eternal Sonata GPU candidate probe: $EternalSonataGpuProbe"
Write-LabLine $runLog "- Eternal Sonata MFC shape probe: $EternalSonataMfcShapeProbe"
Write-LabLine $runLog "- Eternal Sonata MFC ladder: $EternalSonataMfcLadder"
Write-LabLine $runLog "- Eternal Sonata SPU heat profile: $EternalSonataSpuHeatProfile"
Write-LabLine $runLog "- Eternal Sonata PPU/RSX profile: $EternalSonataPpuRsxProfile"
Write-LabLine $runLog "- Eternal Sonata synchronization profile: $EternalSonataSyncProfile"
Write-LabLine $runLog "- Eternal Sonata frame-poll wait: $EternalSonataFramePollWait"
Write-LabLine $runLog "- Eternal Sonata frame-poll handler grace: ${EternalSonataFramePollHandlerGraceUs}us"
Write-LabLine $runLog "- Eternal Sonata frame-poll continuous rearm: $EternalSonataFramePollContinuousRearm"
Write-LabLine $runLog "- Eternal Sonata SPU HLE verifier: $EternalSonataSpuHleVerify"
Write-LabLine $runLog "- Eternal Sonata SPU HLE 0x25cc body: $EternalSonataSpuHle25ccBody"
Write-LabLine $runLog "- Eternal Sonata SPU HLE size16 body: $EternalSonataSpuHleSize16Body"
Write-LabLine $runLog "- Eternal Sonata SPU HLE 0x451c preserve body: $EternalSonataSpuHle451cPreserveBody"
Write-LabLine $runLog "- Eternal Sonata kernel capsule: $EternalSonataKernelCapsule"
Write-LabLine $runLog "- Eternal Sonata reservation loop: $EternalSonataReservationLoop"
Write-LabLine $runLog "- Eternal Sonata PUTLLC16 reservations: $EternalSonataPutllc16Reservations"
Write-LabLine $runLog "- Eternal Sonata PUTLLC16 pair: $EternalSonataPutllc16Pair"
Write-LabLine $runLog "- Eternal Sonata DMA superpath: $EternalSonataDmaSuperPath"
Write-LabLine $runLog "- RSX auditor: $RsxAuditor"
Write-LabLine $runLog "- RSX DMA fence: $RsxDmaFence"
Write-LabLine $runLog "- RSX texture barrier: $RsxTextureBarrier"
Write-LabLine $runLog "- RSX depth feedback: $RsxDepthFeedback"
Write-LabLine $runLog "- RSX resolve probe: $RsxResolve"
Write-LabLine $runLog "- RSX blit-source resolve: $RsxBlitSourceResolve"
Write-LabLine $runLog "- RSX present upload: $RsxPresentUpload"
Write-LabLine $runLog "- RSX index upload: $RsxIndexUpload"
Write-LabLine $runLog "- RSX index persistent cache scout: $RsxIndexPersistentCache"
Write-LabLine $runLog "- RSX vertex superset cache: $RsxVertexSupersetCache"
if ($RsxVertexSupersetScanLimit -gt 0) {
    Write-LabLine $runLog "- RSX vertex superset scan limit: $RsxVertexSupersetScanLimit"
}
Write-LabLine $runLog "- RSX vertex persistent cache scout: $RsxVertexPersistentCache"
Write-LabLine $runLog "- RSX vertex volatile cache: $RsxVertexVolatileCache"
Write-LabLine $runLog "- RSX Force Hardware MSAA Resolve: $RsxForceHwMsaaResolve"
Write-LabLine $runLog "- Frame limit override: $FrameLimit"
Write-LabLine $runLog "- Vblank rate override: $VblankRate"
Write-LabLine $runLog "- Game screen: $GameScreen"
if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataMfcShapeProbe -ne "Off" -or $EternalSonataMfcLadder -ne "Off" -or $EternalSonataSpuHleVerify -ne "Off" -or $EternalSonataSpuHle25ccBody -ne "Off" -or $EternalSonataSpuHle451cPreserveBody -ne "Off" -or $EternalSonataKernelCapsule -ne "Off" -or $EternalSonataReservationLoop -ne "Off" -or $EternalSonataPutllc16Pair -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") {
    $gpuProbeDumpDir = Join-Path $runDir "spu-images"
    Write-LabLine $runLog "- Eternal Sonata GPU probe SPU image dump dir: $gpuProbeDumpDir"
}
if ($BootTarget) {
    Write-LabLine $runLog "- Boot target: $BootTarget"
}
if ($FirmwarePath) {
    Write-LabLine $runLog "- Firmware: $FirmwarePath"
}
Write-LabLine $runLog "- Max seconds: $MaxSeconds"
if ($InputMacro) {
    Write-LabLine $runLog "- Input macro: $InputMacro"
    Write-LabLine $runLog "- Input backend: $InputBackend"
    Write-LabLine $runLog "- Input start seconds: $InputStartSeconds"
    Write-LabLine $runLog "- Input default press ms: $InputDefaultPressMs"
}
if ($ScreenshotEverySeconds -gt 0) {
    Write-LabLine $runLog "- Screenshot every seconds: $ScreenshotEverySeconds"
    Write-LabLine $runLog "- Screenshot start seconds: $ScreenshotStartSeconds"
    Write-LabLine $runLog "- Screenshot max count: $ScreenshotMaxCount"
}
if ($SkipHostSystemCheck) {
    Write-LabLine $runLog "- Host system check: skipped"
} else {
    Write-LabLine $runLog "- Host system check: enabled"
    Write-LabLine $runLog "- Host sample seconds: $HostSampleSeconds"
    Write-LabLine $runLog "- Host periodic sample seconds: $HostSampleEverySeconds"
    Write-LabLine $runLog "- Host contention gate: $HostContentionGate"
}
if (-not [string]::IsNullOrWhiteSpace($CpuAffinityMask)) {
    Write-LabLine $runLog "- CPU affinity mask requested: $CpuAffinityMask"
}
if ($RenderDocInject) {
    Write-LabLine $runLog "- RenderDoc inject: true"
    Write-LabLine $runLog "- RenderDoc API validation: $([bool]$RenderDocApiValidation)"
    Write-LabLine $runLog "- RenderDoc callstacks: $([bool]$RenderDocCaptureCallstacks)"
}
Write-LabLine $runLog ""
Write-LabLine $runLog "## Command"
$argumentLine = Convert-LabArgumentList -ArgumentValues ($argsList.ToArray())
Write-LabLine $runLog "$rpcs3Exe $argumentLine"
Write-LabLine $runLog ""

$hostSnapshots = New-Object System.Collections.Generic.List[object]
$hostContentionGateFailed = $false
$worstHostContention = "unknown"
$worstExternalHostContention = "unknown"
if (-not $SkipHostSystemCheck) {
    $prelaunchSnapshot = Get-LabHostLoadSnapshot -Phase "prelaunch" -SampleSeconds $HostSampleSeconds
    $hostSnapshots.Add($prelaunchSnapshot) | Out-Null
    Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $prelaunchSnapshot | Out-Null
}

$processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
$processStartInfo.FileName = $rpcs3Exe
$processStartInfo.Arguments = $argumentLine
$processStartInfo.WorkingDirectory = $rpcs3Bin
$processStartInfo.UseShellExecute = $false
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.RedirectStandardError = $true
$windowHidden = -not $Visible -and [string]::IsNullOrWhiteSpace($InputMacro) -and $ScreenshotEverySeconds -le 0 -and $Action -ne "InstallFirmware"
if ($windowHidden) {
	$processStartInfo.CreateNoWindow = $true
    $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
}

$stdoutReadTask = $null
$stderrReadTask = $null
[System.IO.File]::WriteAllText($stdoutPath, "", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($stderrPath, "", [System.Text.UTF8Encoding]::new($false))

$launchTime = Get-Date
$padApiFile = ""
if ($InputMacro -and $InputBackend -eq "PadApi") {
    $padApiFile = Join-Path $runDir "windows-pad-api-state.txt"
    Set-LabPadApiState -Path $padApiFile -Keys @()
    Write-LabLine $runLog "- PadApi state file: $padApiFile"
}
$previousEsSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_SUPERPATH", "Process")
$previousEsJoinSpin = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_JOIN_SPIN", "Process")
$previousEsWaitSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_SUPERPATH", "Process")
$previousEsWaitMaxUs = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_MAX_US", "Process")
$previousEsSemaSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SEMA_ESRCH_SUPERPATH", "Process")
$previousEsGpuProbe = [Environment]::GetEnvironmentVariable("RPCS3_ES_GPU_PROBE", "Process")
$previousEsGpuProbeDumpDir = [Environment]::GetEnvironmentVariable("RPCS3_ES_GPU_PROBE_DUMP_DIR", "Process")
$previousEsMfcShapeProbe = [Environment]::GetEnvironmentVariable("RPCS3_ES_MFC_SHAPE_PROBE", "Process")
$previousEsMfcLadder = [Environment]::GetEnvironmentVariable("RPCS3_ES_MFC_LADDER", "Process")
$previousEsSpuHeatProfile = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPU_HEAT_PROFILE", "Process")
$previousEsPpuRsxProfile = [Environment]::GetEnvironmentVariable("RPCS3_ES_PPU_RSX_PROFILE", "Process")
$previousEsSyncProfile = [Environment]::GetEnvironmentVariable("RPCS3_ES_SYNC_PROFILE", "Process")
$previousEsFramePollWait = [Environment]::GetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", "Process")
$previousEsFramePollHandlerGraceUs = [Environment]::GetEnvironmentVariable("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US", "Process")
$previousEsFramePollContinuousRearm = [Environment]::GetEnvironmentVariable("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM", "Process")
$previousEsSpuHleVerify = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPU_HLE_VERIFY", "Process")
$previousEsSpuHle25ccBody = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPU_HLE_25CC_BODY", "Process")
$previousEsSpuHleSize16Body = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPU_HLE_SIZE16_BODY", "Process")
$previousEsSpuHle451cPreserveBody = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPU_HLE_451C_PRESERVE_BODY", "Process")
$previousEsKernelCapsule = [Environment]::GetEnvironmentVariable("RPCS3_ES_KERNEL_CAPSULE", "Process")
$previousEsReservationLoop = [Environment]::GetEnvironmentVariable("RPCS3_ES_RESERVATION_LOOP", "Process")
$previousEsPutllc16Relaxed = [Environment]::GetEnvironmentVariable("RPCS3_ES_PUTLLC16_RELAXED", "Process")
$previousEsPutllc16Pair = [Environment]::GetEnvironmentVariable("RPCS3_ES_PUTLLC16_PAIR", "Process")
$previousEsDmaSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", "Process")
$previousRsxAuditor = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", "Process")
$previousRsxDmaFence = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", "Process")
$previousRsxTextureBarrier = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", "Process")
$previousRsxDepthFeedback = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_DEPTH_FEEDBACK", "Process")
$previousRsxResolve = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", "Process")
$previousRsxBlitSourceResolve = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE", "Process")
$previousRsxPresentUpload = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_PRESENT_UPLOAD", "Process")
$previousRsxIndexUpload = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_INDEX_UPLOAD", "Process")
$previousRsxIndexPersistentCache = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_INDEX_PERSISTENT_CACHE", "Process")
$previousRsxVertexSupersetCache = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_CACHE", "Process")
$previousRsxVertexSupersetScan = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_SCAN", "Process")
$previousRsxVertexPersistentCache = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_PERSISTENT_CACHE", "Process")
$previousRsxVertexVolatileCache = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_VOLATILE_CACHE", "Process")
$previousPadApiFile = [Environment]::GetEnvironmentVariable("RPCS3_ES_PAD_API_FILE", "Process")
$esSuperPathEnv = switch ($EternalSonataSuperPath) {
    "Detect" { "detect" }
    "Cache" { "cache" }
    default { "off" }
}
$esWaitSuperPathEnv = switch ($EternalSonataWaitSuperPath) {
    "Profile" { "profile" }
    "Yield" { "yield" }
    "Skip" { "skip" }
    "Clamp" { "clamp" }
    default { "off" }
}
$esSemaSuperPathEnv = switch ($EternalSonataSemaphoreSuperPath) {
    "Profile" { "profile" }
    "Fast" { "fast" }
    default { "off" }
}
$esGpuProbeEnv = switch ($EternalSonataGpuProbe) {
    "Profile" { "profile" }
    default { "off" }
}
$esMfcShapeProbeEnv = switch ($EternalSonataMfcShapeProbe) {
    "Profile" { "profile" }
    default { "off" }
}
$esMfcLadderEnv = switch ($EternalSonataMfcLadder) {
    "Verify" { "verify" }
    "Fast" { "fast" }
    default { "off" }
}
$esSpuHeatProfileEnv = switch ($EternalSonataSpuHeatProfile) {
    "Profile" { "compact" }
    default { "off" }
}
$esPpuRsxProfileEnv = switch ($EternalSonataPpuRsxProfile) {
    "Profile" { "compact" }
    default { "off" }
}
$esSyncProfileEnv = switch ($EternalSonataSyncProfile) {
    "Profile" { "compact" }
    default { "off" }
}
$esFramePollWaitEnv = switch ($EternalSonataFramePollWait) {
    "Wait" { "wait" }
    default { "off" }
}
$esFramePollContinuousRearmEnv = switch ($EternalSonataFramePollContinuousRearm) {
    "On" { "on" }
    default { "off" }
}
$esSpuHleVerifyEnv = switch ($EternalSonataSpuHleVerify) {
    "Verify" { "verify" }
    "VerifyShadow" { "verify-shadow" }
    "Verify25ccShadow" { "verify-25cc-shadow" }
    "Skip" { "skip" }
    default { "off" }
}
$esSpuHle25ccBodyEnv = switch ($EternalSonataSpuHle25ccBody) {
    "Verify" { "verify" }
    "Fast" { "fast" }
    default { "off" }
}
$esSpuHleSize16BodyEnv = switch ($EternalSonataSpuHleSize16Body) {
    "Verify" { "verify" }
    default { "off" }
}
$esSpuHle451cPreserveBodyEnv = switch ($EternalSonataSpuHle451cPreserveBody) {
    "Verify" { "verify" }
    default { "off" }
}
$esKernelCapsuleEnv = switch ($EternalSonataKernelCapsule) {
    "Profile" { "profile" }
    default { "off" }
}
$esReservationLoopEnv = switch ($EternalSonataReservationLoop) {
    "Profile" { "profile" }
    "Verify" { "verify" }
    default { "off" }
}
$esPutllc16RelaxedEnv = switch ($EternalSonataPutllc16Reservations) {
    "Relaxed" { "1" }
    default { "off" }
}
$esPutllc16PairEnv = switch ($EternalSonataPutllc16Pair) {
    "Profile" { "profile" }
    "Verify" { "verify" }
    "Fast" { "fast" }
    default { "off" }
}
$esDmaSuperPathEnv = switch ($EternalSonataDmaSuperPath) {
    "Verify" { "verify" }
    default { "off" }
}
$rsxAuditorEnv = if ([string]::IsNullOrWhiteSpace($RsxAuditor) -or $RsxAuditor -eq "Off") {
    "off"
} elseif ($RsxAuditor -eq "On") {
    "60"
} else {
    $RsxAuditor.ToLowerInvariant()
}
$rsxDmaFenceEnv = switch ($RsxDmaFence) {
    "Host" { "host" }
    default { "off" }
}
$rsxTextureBarrierEnv = switch ($RsxTextureBarrier) {
    "Depth" { "depth" }
    "DepthReadOnly" { "depth-readonly" }
    "Color" { "color" }
    "All" { "all" }
    default { "off" }
}
$rsxDepthFeedbackEnv = switch ($RsxDepthFeedback) {
    "KeepReadOnly" { "keep-readonly" }
    default { "off" }
}
$rsxResolveEnv = switch ($RsxResolve) {
    "Profile" { "profile" }
    "SkipColor" { "color" }
    "SkipDepth" { "depth" }
    "SkipAll" { "all" }
    default { "off" }
}
$rsxBlitSourceResolveEnv = switch ($RsxBlitSourceResolve) {
    "Verify" { "verify" }
    "VerifySampled" { "verify-sampled" }
    "VerifyCachedSampled" { "verify-cached-sampled" }
    "VerifyCachedTransferSampled" { "verify-cached-transfer-sampled" }
    "VerifyCachedDeferSampled" { "verify-cached-defer-sampled" }
    "Fast" { "fast" }
    "FastSampled" { "fast-sampled" }
    "FastCachedSampled" { "fast-cached-sampled" }
    "FastCachedTransferSampled" { "fast-cached-transfer-sampled" }
    "FastCachedDeferSampled" { "fast-cached-defer-sampled" }
    "FastKeepSrc" { "fast-keep-src" }
    default { "off" }
}
$rsxPresentUploadEnv = switch ($RsxPresentUpload) {
    "GpuSwap" { "gpu-swap" }
    default { "off" }
}
$rsxIndexUploadEnv = switch ($RsxIndexUpload) {
    "GpuSwap" { "gpu-swap" }
    "GpuSwapCached" { "gpu-swap-cached" }
    default { "off" }
}
$rsxIndexPersistentCacheEnv = switch ($RsxIndexPersistentCache) {
    "Profile" { "profile" }
    "Verify" { "verify" }
    "Fast" { "fast" }
    default { "off" }
}
$rsxVertexSupersetCacheEnv = switch ($RsxVertexSupersetCache) {
    "Profile" { "profile" }
    "Fast" { "fast" }
    default { "off" }
}
$rsxVertexPersistentCacheEnv = switch ($RsxVertexPersistentCache) {
    "Profile" { "profile" }
    "Verify" { "verify" }
    "Fast" { "fast" }
    default { "off" }
}
$rsxVertexVolatileCacheEnv = switch ($RsxVertexVolatileCache) {
    "Profile" { "profile" }
    "Fast" { "fast" }
    default { "off" }
}
$esGpuProbeDumpDir = if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataMfcShapeProbe -ne "Off" -or $EternalSonataMfcLadder -ne "Off" -or $EternalSonataSpuHleVerify -ne "Off" -or $EternalSonataSpuHle25ccBody -ne "Off" -or $EternalSonataSpuHle451cPreserveBody -ne "Off" -or $EternalSonataKernelCapsule -ne "Off" -or $EternalSonataReservationLoop -ne "Off" -or $EternalSonataPutllc16Pair -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") { Join-Path $runDir "spu-images" } else { "" }

[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_SUPERPATH", $esSuperPathEnv, "Process")
if ($EternalSonataJoinSpin -ge 0) {
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_JOIN_SPIN", "$EternalSonataJoinSpin", "Process")
}
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_SUPERPATH", $esWaitSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_MAX_US", "$EternalSonataWaitMaxUs", "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SEMA_ESRCH_SUPERPATH", $esSemaSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE", $esGpuProbeEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE_DUMP_DIR", $esGpuProbeDumpDir, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_MFC_SHAPE_PROBE", $esMfcShapeProbeEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_MFC_LADDER", $esMfcLadderEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HEAT_PROFILE", $esSpuHeatProfileEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_PPU_RSX_PROFILE", $esPpuRsxProfileEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SYNC_PROFILE", $esSyncProfileEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $esFramePollWaitEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US", "$EternalSonataFramePollHandlerGraceUs", "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM", $esFramePollContinuousRearmEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_VERIFY", $esSpuHleVerifyEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_25CC_BODY", $esSpuHle25ccBodyEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_SIZE16_BODY", $esSpuHleSize16BodyEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_451C_PRESERVE_BODY", $esSpuHle451cPreserveBodyEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_KERNEL_CAPSULE", $esKernelCapsuleEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RESERVATION_LOOP", $esReservationLoopEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_PUTLLC16_RELAXED", $esPutllc16RelaxedEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_PUTLLC16_PAIR", $esPutllc16PairEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", $esDmaSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", $rsxAuditorEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", $rsxDmaFenceEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", $rsxTextureBarrierEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DEPTH_FEEDBACK", $rsxDepthFeedbackEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", $rsxResolveEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE", $rsxBlitSourceResolveEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_PRESENT_UPLOAD", $rsxPresentUploadEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_INDEX_UPLOAD", $rsxIndexUploadEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_INDEX_PERSISTENT_CACHE", $rsxIndexPersistentCacheEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_CACHE", $rsxVertexSupersetCacheEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_SCAN", $(if ($RsxVertexSupersetScanLimit -gt 0) { "$RsxVertexSupersetScanLimit" } else { $null }), "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_PERSISTENT_CACHE", $rsxVertexPersistentCacheEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_VOLATILE_CACHE", $rsxVertexVolatileCacheEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_PAD_API_FILE", $padApiFile, "Process")
try {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processStartInfo
    if (-not $process.Start()) {
        throw "System.Diagnostics.Process failed to start RPCS3."
    }
    $stdoutReadTask = $process.StandardOutput.ReadToEndAsync()
    $stderrReadTask = $process.StandardError.ReadToEndAsync()
} finally {
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_SUPERPATH", $previousEsSuperPath, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_JOIN_SPIN", $previousEsJoinSpin, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_SUPERPATH", $previousEsWaitSuperPath, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_MAX_US", $previousEsWaitMaxUs, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SEMA_ESRCH_SUPERPATH", $previousEsSemaSuperPath, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE", $previousEsGpuProbe, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE_DUMP_DIR", $previousEsGpuProbeDumpDir, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_MFC_SHAPE_PROBE", $previousEsMfcShapeProbe, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_MFC_LADDER", $previousEsMfcLadder, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HEAT_PROFILE", $previousEsSpuHeatProfile, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_PPU_RSX_PROFILE", $previousEsPpuRsxProfile, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SYNC_PROFILE", $previousEsSyncProfile, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_WAIT", $previousEsFramePollWait, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US", $previousEsFramePollHandlerGraceUs, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM", $previousEsFramePollContinuousRearm, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_VERIFY", $previousEsSpuHleVerify, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_25CC_BODY", $previousEsSpuHle25ccBody, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_SIZE16_BODY", $previousEsSpuHleSize16Body, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HLE_451C_PRESERVE_BODY", $previousEsSpuHle451cPreserveBody, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_KERNEL_CAPSULE", $previousEsKernelCapsule, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RESERVATION_LOOP", $previousEsReservationLoop, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_PUTLLC16_RELAXED", $previousEsPutllc16Relaxed, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_PUTLLC16_PAIR", $previousEsPutllc16Pair, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", $previousEsDmaSuperPath, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", $previousRsxAuditor, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", $previousRsxDmaFence, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", $previousRsxTextureBarrier, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DEPTH_FEEDBACK", $previousRsxDepthFeedback, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", $previousRsxResolve, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_BLIT_SOURCE_RESOLVE", $previousRsxBlitSourceResolve, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_PRESENT_UPLOAD", $previousRsxPresentUpload, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_INDEX_UPLOAD", $previousRsxIndexUpload, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_INDEX_PERSISTENT_CACHE", $previousRsxIndexPersistentCache, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_CACHE", $previousRsxVertexSupersetCache, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_SUPERSET_SCAN", $previousRsxVertexSupersetScan, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_PERSISTENT_CACHE", $previousRsxVertexPersistentCache, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_VERTEX_VOLATILE_CACHE", $previousRsxVertexVolatileCache, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_PAD_API_FILE", $previousPadApiFile, "Process")
}

Set-LabProcessAffinity -Process $process -Mask $CpuAffinityMask -RunLog $runLog

if (-not $SkipHostSystemCheck) {
    $postlaunchSnapshot = Get-LabHostLoadSnapshot -Phase "postlaunch" -SampleSeconds $HostSampleSeconds -RunPid $process.Id
    $hostSnapshots.Add($postlaunchSnapshot) | Out-Null
    Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $postlaunchSnapshot | Out-Null
}

if (-not $windowHidden -and $Action -ne "InstallFirmware") {
    Move-LabWindowToSecondaryMonitor -Process $process -RunLog $runLog
}

$screenshotDir = Join-Path $runDir "screenshots"
$titleSamplesPath = Join-Path $runDir "window-title-samples.csv"

if ($RenderDocInject) {
    Invoke-LabRenderDocInject -Process $process -RunDir $runDir -SafeLabel $safeLabel -RunLog $runLog -RequestedPath $RenderDocPath -ApiValidation:$RenderDocApiValidation -CaptureCallstacks:$RenderDocCaptureCallstacks
}
$liveRpcs3Log = Join-Path $rpcs3LogDir "RPCS3.log"
Invoke-LabInputMacro -Process $process -Macro $InputMacro -InputBackend $InputBackend -PadApiFile $padApiFile -StartSeconds $InputStartSeconds -DefaultPressMs $InputDefaultPressMs -RunLog $runLog -ScreenshotDir $screenshotDir -LiveLogPath $liveRpcs3Log -LaunchTime $launchTime
$exited = $false
$processExitedBeforeDeadline = $false

$nextScreenshotAt = [Math]::Max(0, $ScreenshotStartSeconds)
$screenshotCount = 0
$nextHostSampleAt = if (-not $SkipHostSystemCheck -and $HostSampleEverySeconds -gt 0) { [Math]::Max(1, $HostSampleEverySeconds) } else { [int]::MaxValue }

while ($true) {
    $process.Refresh()
    $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $launchTime).TotalSeconds)
    if ($process.HasExited) {
        $exited = $true
        $processExitedBeforeDeadline = $true
        Write-LabLine $runLog "Process exited at ${elapsedSeconds}s before max ${MaxSeconds}s."
        break
    }

    if ($ScreenshotEverySeconds -gt 0 -and $elapsedSeconds -ge $nextScreenshotAt -and ($ScreenshotMaxCount -le 0 -or $screenshotCount -lt $ScreenshotMaxCount)) {
        Save-LabScreenshot -Process $process -ScreenshotDir $screenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $runLog
        $screenshotCount++
        $nextScreenshotAt += $ScreenshotEverySeconds
    }

    if (-not $SkipHostSystemCheck -and $HostSampleEverySeconds -gt 0 -and $elapsedSeconds -ge $nextHostSampleAt) {
        $hostSnapshot = Get-LabHostLoadSnapshot -Phase ("sample-{0:0000}s" -f $elapsedSeconds) -SampleSeconds $HostSampleSeconds -RunPid $process.Id
        $hostSnapshots.Add($hostSnapshot) | Out-Null
        Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $hostSnapshot | Out-Null
        Write-LabWindowTitleSample -Process $process -TitleSamplesPath $titleSamplesPath -RunLog $runLog -ElapsedSeconds $elapsedSeconds -Phase ("host-sample-{0:0000}s" -f $elapsedSeconds)
        while ($nextHostSampleAt -le $elapsedSeconds) {
            $nextHostSampleAt += $HostSampleEverySeconds
        }
    }

    if ($elapsedSeconds -ge $MaxSeconds) {
        break
    }

    Start-Sleep -Milliseconds 250
}

if (-not $exited) {
    Write-LabLine $runLog "Process exceeded ${MaxSeconds}s total wall time; stopping PID $($process.Id)."
    if ($EternalSonataSpuHeatProfile -eq "Profile" -or $EternalSonataPpuRsxProfile -eq "Profile" -or $EternalSonataSyncProfile -eq "Profile") {
        $closeRequested = $process.CloseMainWindow()
        Write-LabLine $runLog "Profiler graceful stop requested: $closeRequested"
        if ($closeRequested) {
            $exited = $process.WaitForExit(10000)
            Write-LabLine $runLog "Profiler graceful stop completed: $exited"
        }
    }

    if (-not $exited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        $exited = $process.HasExited
    }
}

$process.Refresh()
if (-not $SkipHostSystemCheck) {
    $postrunSnapshot = Get-LabHostLoadSnapshot -Phase "postrun" -SampleSeconds $HostSampleSeconds -RunPid $process.Id
    $hostSnapshots.Add($postrunSnapshot) | Out-Null
    Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $postrunSnapshot | Out-Null
    $worstHostContention = Get-LabWorstHostContentionGrade -Snapshots $hostSnapshots.ToArray()
    $worstExternalHostContention = Get-LabWorstExternalHostContentionGrade -Snapshots $hostSnapshots.ToArray()
    Write-LabLine $runLog "Host contention summary: $worstHostContention ($($hostSnapshots.Count) snapshots)"
    Write-LabLine $runLog "Host external contention summary: $worstExternalHostContention ($($hostSnapshots.Count) snapshots)"
    if ($HostContentionGate -ne "Off") {
        if ($HostContentionGate -eq "ExternalFail") {
            Write-LabLine $runLog "Host contention gate: $HostContentionGate; require=external-clean; worst-external=$worstExternalHostContention; worst-total=$worstHostContention"
        } else {
            Write-LabLine $runLog "Host contention gate: $HostContentionGate; require=clean; worst=$worstHostContention; worst-external=$worstExternalHostContention"
        }
        if ($HostContentionGate -eq "Fail" -and $worstHostContention -ne "clean") {
            $hostContentionGateFailed = $true
            $gatePath = Join-Path $runDir "host-contention-gate-failed.txt"
            "Host contention gate failed: worst=$worstHostContention; require=clean" | Set-Content -LiteralPath $gatePath -Encoding UTF8
            Write-LabLine $runLog "Host contention gate failed: $gatePath"
        } elseif ($HostContentionGate -eq "ExternalFail" -and $worstExternalHostContention -ne "clean") {
            $hostContentionGateFailed = $true
            $gatePath = Join-Path $runDir "host-contention-gate-failed.txt"
            "Host contention gate failed: worst_external=$worstExternalHostContention; require=external-clean; worst_total=$worstHostContention" | Set-Content -LiteralPath $gatePath -Encoding UTF8
            Write-LabLine $runLog "Host contention gate failed: $gatePath"
        }
    }
}

$numericExitCode = $null
if ($exited -and $process.HasExited) {
    try {
        $process.WaitForExit()
        $process.Refresh()
        $numericExitCode = [int]$process.ExitCode
    } catch {
        Write-LabLine $runLog "Exit code query failed: $($_.Exception.Message)"
    }
}

if ($process.HasExited) {
    $stdoutText = if ($null -ne $stdoutReadTask) { [string]$stdoutReadTask.Result } else { "" }
    $stderrText = if ($null -ne $stderrReadTask) { [string]$stderrReadTask.Result } else { "" }
    [System.IO.File]::WriteAllText($stdoutPath, $stdoutText, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($stderrPath, $stderrText, [System.Text.UTF8Encoding]::new($false))
}

$exitCode = if ($null -ne $numericExitCode) {
    $numericExitCode
} elseif ($exited -and $process.HasExited) {
    "exited"
} else {
    "timeout"
}
Write-LabLine $runLog "Exit code: $exitCode"
Write-LabLine $runLog "stdout: $stdoutPath"
Write-LabLine $runLog "stderr: $stderrPath"

$sourceLog = Join-Path $rpcs3LogDir "RPCS3.log"
if (Test-Path -LiteralPath $sourceLog) {
    $destLog = Join-Path $runDir "RPCS3.log"
    Copy-Item -LiteralPath $sourceLog -Destination $destLog -Force
    Write-LabLine $runLog "RPCS3 log: $destLog"

    if ($EternalSonataSpuHeatProfile -eq "Profile") {
        $heatSummaryPath = Join-Path $runDir "spu-heat-summary.txt"
        $heatLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in [System.IO.File]::ReadLines($destLog)) {
            if ($line.Contains("ES SPU heat ")) {
                $heatLines.Add($line) | Out-Null
            }
        }

        if ($heatLines.Count -gt 0) {
            [System.IO.File]::WriteAllLines($heatSummaryPath, $heatLines, [System.Text.UTF8Encoding]::new($false))
            Write-LabLine $runLog "SPU heat summary: $heatSummaryPath ($($heatLines.Count) lines)"
            $heatAnalyzer = Join-Path $PSScriptRoot "summarize_eternal_sonata_spu_heat.ps1"
            if (Test-Path -LiteralPath $heatAnalyzer -PathType Leaf) {
                try {
                    $heatAnalysis = & $heatAnalyzer -RunDir $runDir -SummaryPath $heatSummaryPath -Top 20 2>&1
                    foreach ($line in @($heatAnalysis)) {
                        Write-LabLine $runLog "$line"
                    }
                } catch {
                    Write-LabLine $runLog "SPU heat analysis failed: $($_.Exception.Message)"
                }
            }
        } else {
            Write-LabLine $runLog "SPU heat summary missing: no sampler lines found in $destLog"
        }
    }

    if ($EternalSonataPpuRsxProfile -eq "Profile") {
        $ppuRsxSummaryPath = Join-Path $runDir "ppu-rsx-profile.txt"
        $ppuRsxLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in [System.IO.File]::ReadLines($destLog)) {
            if ($line.Contains("ES PPU/RSX ")) {
                $ppuRsxLines.Add($line) | Out-Null
            }
        }

        if ($ppuRsxLines.Count -gt 0) {
            [System.IO.File]::WriteAllLines($ppuRsxSummaryPath, $ppuRsxLines, [System.Text.UTF8Encoding]::new($false))
            Write-LabLine $runLog "PPU/RSX profile summary: $ppuRsxSummaryPath ($($ppuRsxLines.Count) lines)"
        } else {
            Write-LabLine $runLog "PPU/RSX profile summary missing: no sampler lines found in $destLog"
        }
    }

    if ($EternalSonataSyncProfile -eq "Profile") {
        $syncSummaryPath = Join-Path $runDir "sync-profile.txt"
        $syncLines = New-Object System.Collections.Generic.List[string]
        foreach ($line in [System.IO.File]::ReadLines($destLog)) {
            if ($line.Contains("Eternal Sonata sync profile:") -or $line.Contains("Eternal Sonata sync long wait:")) {
                $syncLines.Add($line) | Out-Null
            }
        }

        if ($syncLines.Count -gt 0) {
            [System.IO.File]::WriteAllLines($syncSummaryPath, $syncLines, [System.Text.UTF8Encoding]::new($false))
            Write-LabLine $runLog "Synchronization profile summary: $syncSummaryPath ($($syncLines.Count) lines)"
        } else {
            Write-LabLine $runLog "Synchronization profile summary missing: no profiler lines found in $destLog"
        }
    }

    if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataMfcShapeProbe -ne "Off" -or $EternalSonataMfcLadder -ne "Off" -or $EternalSonataSpuHleVerify -ne "Off" -or $EternalSonataSpuHle25ccBody -ne "Off" -or $EternalSonataSpuHle451cPreserveBody -ne "Off" -or $EternalSonataKernelCapsule -ne "Off" -or $EternalSonataReservationLoop -ne "Off" -or $EternalSonataPutllc16Pair -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") {
        $gpuProbeSummary = Join-Path $PSScriptRoot "summarize_eternal_sonata_gpu_probe.ps1"
        if (Test-Path -LiteralPath $gpuProbeSummary -PathType Leaf) {
            $destLogBytes = (Get-Item -LiteralPath $destLog).Length
            if ($GpuProbeSummaryMaxLogBytes -gt 0 -and $destLogBytes -gt $GpuProbeSummaryMaxLogBytes) {
                Write-LabLine $runLog "GPU probe summary deferred: log_bytes=$destLogBytes exceeds synchronous limit=$GpuProbeSummaryMaxLogBytes."
                Write-LabLine $runLog "Deferred summary command: .\tools\summarize_eternal_sonata_gpu_probe.ps1 -RunDir `"$runDir`" -LogPath `"$destLog`" -Top 25"
            } else {
                try {
                    $summaryOutput = & $gpuProbeSummary -RunDir $runDir -LogPath $destLog -Top 25 2>&1
                    foreach ($line in @($summaryOutput)) {
                        Write-LabLine $runLog "$line"
                    }
                } catch {
                    Write-LabLine $runLog "GPU probe summary failed: $($_.Exception.Message)"
                }
            }
        }
    }
}

if ($null -ne $forceHwMsaaResolveOverride -and $forceHwMsaaResolveOverride.found) {
    $restoreMode = if ($forceHwMsaaResolveOverride.old_value -match '^(?i:true|1|yes|on)$') { "On" } else { "Off" }
    $restoreResult = Set-LabForceHwMsaaResolveConfig -ConfigPath $rpcs3Config -Mode $restoreMode
    if ($null -ne $restoreResult) {
        Write-LabLine $runLog "- Force Hardware MSAA Resolve restored: $($restoreResult.old_value) -> $($restoreResult.new_value) changed=$($restoreResult.changed)"
    }
}

Write-LabLine $runLog ""
Write-LabLine $runLog "Run dir: $runDir"
if ($hostContentionGateFailed) {
    throw "Host contention gate failed: worst=$worstHostContention; worst_external=$worstExternalHostContention; run=$runDir"
}
if ($processExitedBeforeDeadline) {
    $processExitGatePath = Join-Path $runDir "process-exit-gate-failed.txt"
    "Process exited before deadline: exit_code=$exitCode; max_seconds=$MaxSeconds" | Set-Content -LiteralPath $processExitGatePath -Encoding UTF8
    throw "RPCS3 exited before the run deadline: exit_code=$exitCode; run=$runDir"
}
