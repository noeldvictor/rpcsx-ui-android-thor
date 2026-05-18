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
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataDmaSuperPath = "Off",
    [string]$RsxAuditor = "Off",
    [ValidateSet("Off", "Host")]
    [string]$RsxDmaFence = "Off",
    [ValidateSet("Off", "Depth", "Color", "All")]
    [string]$RsxTextureBarrier = "Off",
    [ValidateSet("Off", "Profile", "SkipColor", "SkipDepth", "SkipAll")]
    [string]$RsxResolve = "Off",
    [string[]]$SearchRoots = @(),
    [int]$MaxSeconds = 20,
    [string]$InputMacro = "",
    [int]$InputStartSeconds = 0,
    [int]$InputDefaultPressMs = 120,
    [int]$ScreenshotEverySeconds = 0,
    [int]$ScreenshotStartSeconds = 20,
    [int]$ScreenshotMaxCount = 0,
    [int]$HostSampleSeconds = 1,
    [int]$HostSampleEverySeconds = 30,
    [switch]$SkipHostSystemCheck,
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

    Write-LabLine $RunLog "- Host check [$($Snapshot.phase)]: $($Snapshot.contention_grade); cpu=${cpuText}%; mem=${memText}%; gpu-engine-sum=${gpuText}%; external-emulators=$emulatorText; $reasonText"
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

        if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
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
                Save-LabScreenshot -Process $Process -ScreenshotDir $ScreenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $RunLog
            }
            Start-Sleep -Milliseconds $duration
            continue
        }

        $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
        if ($handle -ne [IntPtr]::Zero) {
            [LabInput.Win32]::SetForegroundWindow($handle) | Out-Null
        }

        $vk = Get-LabVirtualKey $name
        Write-LabLine $RunLog "Input press: $name ${duration}ms"
        [LabInput.Win32]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds $duration
        [LabInput.Win32]::keybd_event($vk, 0, 2, [UIntPtr]::Zero)
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
    }
}
"@
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
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
    [LabVisual.Win32]::SetForegroundWindow($handle) | Out-Null
    Write-LabLine $RunLog "- Secondary monitor: moved RPCS3 window to $($secondary.DeviceName) at ${x},${y} (${width}x${height})"
}

function Save-LabScreenshot {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ScreenshotDir,
        [int]$ElapsedSeconds,
        [string]$RunLog
    )

    Initialize-LabVisual

    $handle = Wait-LabProcessWindow -Process $Process -TimeoutSeconds 1
    if ($handle -eq [IntPtr]::Zero) {
        Write-LabLine $RunLog "Screenshot skipped at ${ElapsedSeconds}s: game window was not found."
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
    [LabVisual.Win32]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 100

    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [System.Drawing.Size]::new($width, $height))
        $path = Join-Path $ScreenshotDir ("screenshot-{0:0000}s.png" -f $ElapsedSeconds)
        $suffix = 1
        while (Test-Path -LiteralPath $path) {
            $path = Join-Path $ScreenshotDir ("screenshot-{0:0000}s-{1:00}.png" -f $ElapsedSeconds, $suffix)
            $suffix++
        }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-LabLine $RunLog "Screenshot: $path"
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
Write-LabLine $runLog "- Eternal Sonata DMA superpath: $EternalSonataDmaSuperPath"
Write-LabLine $runLog "- RSX auditor: $RsxAuditor"
Write-LabLine $runLog "- RSX DMA fence: $RsxDmaFence"
Write-LabLine $runLog "- RSX texture barrier: $RsxTextureBarrier"
Write-LabLine $runLog "- RSX resolve probe: $RsxResolve"
if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") {
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
$previousEsSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_SUPERPATH", "Process")
$previousEsJoinSpin = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_JOIN_SPIN", "Process")
$previousEsWaitSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_SUPERPATH", "Process")
$previousEsWaitMaxUs = [Environment]::GetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_MAX_US", "Process")
$previousEsSemaSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_SEMA_ESRCH_SUPERPATH", "Process")
$previousEsGpuProbe = [Environment]::GetEnvironmentVariable("RPCS3_ES_GPU_PROBE", "Process")
$previousEsGpuProbeDumpDir = [Environment]::GetEnvironmentVariable("RPCS3_ES_GPU_PROBE_DUMP_DIR", "Process")
$previousEsDmaSuperPath = [Environment]::GetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", "Process")
$previousRsxAuditor = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", "Process")
$previousRsxDmaFence = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", "Process")
$previousRsxTextureBarrier = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", "Process")
$previousRsxResolve = [Environment]::GetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", "Process")
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
    "Color" { "color" }
    "All" { "all" }
    default { "off" }
}
$rsxResolveEnv = switch ($RsxResolve) {
    "Profile" { "profile" }
    "SkipColor" { "color" }
    "SkipDepth" { "depth" }
    "SkipAll" { "all" }
    default { "off" }
}
$esGpuProbeDumpDir = if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") { Join-Path $runDir "spu-images" } else { "" }

[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_SUPERPATH", $esSuperPathEnv, "Process")
if ($EternalSonataJoinSpin -ge 0) {
    [Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_JOIN_SPIN", "$EternalSonataJoinSpin", "Process")
}
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_SUPERPATH", $esWaitSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SPURS_WAIT_MAX_US", "$EternalSonataWaitMaxUs", "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_SEMA_ESRCH_SUPERPATH", $esSemaSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE", $esGpuProbeEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_GPU_PROBE_DUMP_DIR", $esGpuProbeDumpDir, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", $esDmaSuperPathEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", $rsxAuditorEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", $rsxDmaFenceEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", $rsxTextureBarrierEnv, "Process")
[Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", $rsxResolveEnv, "Process")
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
    [Environment]::SetEnvironmentVariable("RPCS3_ES_DMA_SUPERPATH", $previousEsDmaSuperPath, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_AUDITOR", $previousRsxAuditor, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_DMA_FENCE", $previousRsxDmaFence, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_TEXTURE_BARRIER", $previousRsxTextureBarrier, "Process")
    [Environment]::SetEnvironmentVariable("RPCS3_ES_RSX_RESOLVE", $previousRsxResolve, "Process")
}

if (-not $SkipHostSystemCheck) {
    $postlaunchSnapshot = Get-LabHostLoadSnapshot -Phase "postlaunch" -SampleSeconds $HostSampleSeconds -RunPid $process.Id
    $hostSnapshots.Add($postlaunchSnapshot) | Out-Null
    Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $postlaunchSnapshot | Out-Null
}

if (-not $windowHidden -and $Action -ne "InstallFirmware") {
    Move-LabWindowToSecondaryMonitor -Process $process -RunLog $runLog
}

$screenshotDir = Join-Path $runDir "screenshots"

if ($RenderDocInject) {
    Invoke-LabRenderDocInject -Process $process -RunDir $runDir -SafeLabel $safeLabel -RunLog $runLog -RequestedPath $RenderDocPath -ApiValidation:$RenderDocApiValidation -CaptureCallstacks:$RenderDocCaptureCallstacks
}
Invoke-LabInputMacro -Process $process -Macro $InputMacro -StartSeconds $InputStartSeconds -DefaultPressMs $InputDefaultPressMs -RunLog $runLog -ScreenshotDir $screenshotDir -LaunchTime $launchTime
$exited = $false

$nextScreenshotAt = [Math]::Max(0, $ScreenshotStartSeconds)
$screenshotCount = 0
$nextHostSampleAt = if (-not $SkipHostSystemCheck -and $HostSampleEverySeconds -gt 0) { [Math]::Max(1, $HostSampleEverySeconds) } else { [int]::MaxValue }

while ($true) {
    $process.Refresh()
    if ($process.HasExited) {
        $exited = $true
        break
    }

    $elapsedSeconds = [int][Math]::Floor(((Get-Date) - $launchTime).TotalSeconds)
    if ($ScreenshotEverySeconds -gt 0 -and $elapsedSeconds -ge $nextScreenshotAt -and ($ScreenshotMaxCount -le 0 -or $screenshotCount -lt $ScreenshotMaxCount)) {
        Save-LabScreenshot -Process $process -ScreenshotDir $screenshotDir -ElapsedSeconds $elapsedSeconds -RunLog $runLog
        $screenshotCount++
        $nextScreenshotAt += $ScreenshotEverySeconds
    }

    if (-not $SkipHostSystemCheck -and $HostSampleEverySeconds -gt 0 -and $elapsedSeconds -ge $nextHostSampleAt) {
        $hostSnapshot = Get-LabHostLoadSnapshot -Phase ("sample-{0:0000}s" -f $elapsedSeconds) -SampleSeconds $HostSampleSeconds -RunPid $process.Id
        $hostSnapshots.Add($hostSnapshot) | Out-Null
        Save-LabHostLoadSnapshot -RunDir $runDir -RunLog $runLog -Snapshot $hostSnapshot | Out-Null
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
    Write-LabLine $runLog "Host contention summary: $worstHostContention ($($hostSnapshots.Count) snapshots)"
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

    if ($EternalSonataGpuProbe -ne "Off" -or $EternalSonataDmaSuperPath -ne "Off") {
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

Write-LabLine $runLog ""
Write-LabLine $runLog "Run dir: $runDir"
