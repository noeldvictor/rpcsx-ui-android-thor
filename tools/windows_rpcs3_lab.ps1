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
                Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog -Tag $shotTag
            }
            Start-Sleep -Milliseconds $duration
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
                        [LabInput.Win32]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
                    }
                    Start-Sleep -Milliseconds $duration
                    for ($i = $comboVks.Count - 1; $i -ge 0; $i--) {
                        [LabInput.Win32]::keybd_event($comboVks[$i], 0, 2, [UIntPtr]::Zero)
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
            [LabInput.Win32]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
            Start-Sleep -Milliseconds $duration
            [LabInput.Win32]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
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
        [string]$RunLog
    )

    if ($FrameLimit -eq "Keep" -and $VblankRate -le 0 -and $SpuAccurateReservations -eq "Keep") {
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

        if ($inCore -and $accurateReservationsValue -and $line -match '^  Accurate SPU Reservations: ') {
            $newLine = "  Accurate SPU Reservations: $accurateReservationsValue"
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
$rpcs3Exe = Join-Path $rpcs3Root "build-msvc\bin\rpcs3.exe"
$rpcs3Bin = Split-Path -Parent $rpcs3Exe
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
$runConfigOverride = New-LabRunConfig -SourcePath $rpcs3Config -RunDir $runDir -FrameLimit $FrameLimit -VblankRate $VblankRate -SpuAccurateReservations $SpuAccurateReservations -RunLog $runLog
if ($null -eq $runConfigOverride) {
    Write-LabLine $runLog "- Run config override: keep"
} else {
    Write-LabLine $runLog "- Run config override: $($runConfigOverride.path)"
    Write-LabLine $runLog "- Run config frame limit: $($runConfigOverride.frame_limit)"
    Write-LabLine $runLog "- Run config vblank rate: $($runConfigOverride.vblank_rate)"
    Write-LabLine $runLog "- Run config Accurate SPU Reservations: $($runConfigOverride.spu_accurate_reservations)"
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
$env:PATH = "$qtBin;$vcpkgBin;$env:PATH"

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

$startInfo = @{
    FilePath = $rpcs3Exe
    ArgumentList = $argumentLine
    WorkingDirectory = $rpcs3Bin
    RedirectStandardOutput = $stdoutPath
    RedirectStandardError = $stderrPath
    PassThru = $true
}
$windowHidden = -not $Visible -and [string]::IsNullOrWhiteSpace($InputMacro) -and $ScreenshotEverySeconds -le 0 -and $Action -ne "InstallFirmware"
if ($windowHidden) {
    $startInfo.WindowStyle = "Hidden"
}

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
    $process = Start-Process @startInfo
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
Invoke-LabInputMacro -Process $process -Macro $InputMacro -InputBackend $InputBackend -PadApiFile $padApiFile -StartSeconds $InputStartSeconds -DefaultPressMs $InputDefaultPressMs -RunLog $runLog -ScreenshotDir $screenshotDir -LaunchTime $launchTime
$exited = $false

$nextScreenshotAt = [Math]::Max(0, $ScreenshotStartSeconds)
$screenshotCount = 0
$nextHostSampleAt = if (-not $SkipHostSystemCheck -and $HostSampleEverySeconds -gt 0) { [Math]::Max(1, $HostSampleEverySeconds) } else { [int]::MaxValue }

while ($true) {
    $process.Refresh()
    $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $launchTime).TotalSeconds)
    if ($process.HasExited) {
        $exited = $true
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
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    $exited = $process.HasExited
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

$exitCode = if ($exited -and $process.HasExited) {
    if ($null -eq $process.ExitCode -or "$($process.ExitCode)" -eq "") {
        "exited"
    } else {
        $process.ExitCode
    }
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

    if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataMfcShapeProbe -ne "Off" -or $EternalSonataMfcLadder -ne "Off" -or $EternalSonataSpuHleVerify -ne "Off" -or $EternalSonataSpuHle25ccBody -ne "Off" -or $EternalSonataSpuHle451cPreserveBody -ne "Off" -or $EternalSonataKernelCapsule -ne "Off" -or $EternalSonataReservationLoop -ne "Off" -or $EternalSonataPutllc16Pair -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") {
        $gpuProbeSummary = Join-Path $PSScriptRoot "summarize_eternal_sonata_gpu_probe.ps1"
        if (Test-Path -LiteralPath $gpuProbeSummary -PathType Leaf) {
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
