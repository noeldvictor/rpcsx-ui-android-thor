$ErrorActionPreference = "Stop"

function Get-ThorCachePrepareProgress {
    param([string]$NativeText)

    $compiledModules = [regex]::Matches($NativeText, '(?m)PPU: LLVM: Compiled module ').Count
    $loadedModules = [regex]::Matches($NativeText, '(?m)PPU: LLVM: Loaded module ').Count
    $existingModules = [regex]::Matches($NativeText, '(?m)PPU: LLVM: Module exists: ').Count
    $reusedModules = $loadedModules + $existingModules
    $compileWorkerNames = @(
        [regex]::Matches(
            $NativeText,
            '\{(PPUW[.][^}]+)\}\s+PPU: LLVM: (?:Compiling|Compiled|Loaded) module '
        ) |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    )
    $progressMatches = [regex]::Matches(
        $NativeText,
        'Progress: (?:file ([0-9]+) of ([0-9]+), )?module ([0-9]+) of ([0-9]+)'
    )
    $fileProgressMatches = [regex]::Matches(
        $NativeText,
        'Progress: file ([0-9]+) of ([0-9]+)'
    )
    $latestModule = 0
    $totalModules = 0
    $latestFile = 0
    $totalFiles = 0
    if ($progressMatches.Count -gt 0) {
        $latest = $progressMatches[$progressMatches.Count - 1]
        $latestModule = [int]$latest.Groups[3].Value
        $totalModules = [int]$latest.Groups[4].Value
    }
    if ($fileProgressMatches.Count -gt 0) {
        $latestFileProgress = $fileProgressMatches[$fileProgressMatches.Count - 1]
        $latestFile = [int]$latestFileProgress.Groups[1].Value
        $totalFiles = [int]$latestFileProgress.Groups[2].Value
    }

    $initialProgressMatches = [regex]::Matches(
        $NativeText,
        'Progress: module ([0-9]+) of ([0-9]+)'
    )

    $initialModule = 0
    $initialTotalModules = 0
    $initialProgressObserved = $initialProgressMatches.Count -gt 0
    $firmwareScanStarted = $fileProgressMatches.Count -gt 0
    if ($initialProgressObserved) {
        $initialLatest = $initialProgressMatches[$initialProgressMatches.Count - 1]
        $initialModule = [int]$initialLatest.Groups[1].Value
        $initialTotalModules = [int]$initialLatest.Groups[2].Value
        if ($firmwareScanStarted) {
            # Firmware enumeration starts only after ppu_initialize() returns.
            # Its module counters belong to the growing SPRX workload, not the
            # main EBOOT phase. Crossing that boundary proves the prior phase
            # completed even when its last emitted row was N-1/N.
            $initialModule = $initialTotalModules
        }
    }
    $initialWorkloadComplete = $firmwareScanStarted -or
        ($initialTotalModules -gt 0 -and $initialModule -eq $initialTotalModules)

    $remainingModules = if ($totalModules -ge $latestModule) {
        $totalModules - $latestModule
    } else {
        0
    }
    $remainingFiles = if ($totalFiles -ge $latestFile) {
        $totalFiles - $latestFile
    } else {
        0
    }

    return [pscustomobject]@{
        compiled_modules = $compiledModules
        loaded_modules = $loadedModules
        existing_modules = $existingModules
        reused_modules = $reusedModules
        compile_worker_names = $compileWorkerNames
        compile_worker_count = $compileWorkerNames.Count
        latest_module = $latestModule
        total_modules = $totalModules
        remaining_modules = $remainingModules
        latest_file = $latestFile
        total_files = $totalFiles
        remaining_files = $remainingFiles
        initial_module = $initialModule
        initial_total_modules = $initialTotalModules
        initial_progress_observed = $initialProgressObserved
        initial_workload_complete = $initialWorkloadComplete
        has_reuse = $reusedModules -gt 0
        has_progress = $compiledModules -gt 0 -and $latestModule -gt 0 -and
            $totalModules -ge $latestModule
    }
}

function Get-ThorCachePrepareThermalSummary {
    param(
        [object[]]$SiliconTemperaturesC,
        [double]$WarmThresholdC = 45.0,
        [double]$ProbeThresholdC = 50.0
    )

    $temperatures = @(
        $SiliconTemperaturesC |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [double]$_ }
    )
    if ($temperatures.Count -eq 0) {
        return [pscustomobject]@{
            sample_count = 0
            average_c = $null
            minimum_c = $null
            maximum_c = $null
            at_or_above_warm = 0
            at_or_above_probe = 0
        }
    }

    $measure = $temperatures | Measure-Object -Average -Minimum -Maximum
    return [pscustomobject]@{
        sample_count = $temperatures.Count
        average_c = [double]$measure.Average
        minimum_c = [double]$measure.Minimum
        maximum_c = [double]$measure.Maximum
        at_or_above_warm = @($temperatures | Where-Object { $_ -ge $WarmThresholdC }).Count
        at_or_above_probe = @($temperatures | Where-Object { $_ -ge $ProbeThresholdC }).Count
    }
}

function Get-ThorCachePrepareCooldownState {
    param(
        [AllowNull()][object]$LastCompletedAt,
        [DateTimeOffset]$Now = [DateTimeOffset]::Now,
        [double]$MinimumMinutes = 30.0
    )

    if ($null -eq $LastCompletedAt) {
        return [pscustomobject]@{
            ready = $true
            ready_at = $null
            remaining_seconds = 0
        }
    }

    $readyAt = ([DateTimeOffset]$LastCompletedAt).AddMinutes($MinimumMinutes)
    $remainingSeconds = [Math]::Max(0.0, ($readyAt - $Now).TotalSeconds)
    return [pscustomobject]@{
        ready = $remainingSeconds -le 0.0
        ready_at = $readyAt
        remaining_seconds = [int][Math]::Ceiling($remainingSeconds)
    }
}

function Test-ThorCachePrepareNativeFatal {
    param([string]$NativeText)

    return [regex]::IsMatch(
        $NativeText,
        '(?im)^(?:[^\x00-\x7f]+)?F\s|VM:\s+Access violation|VK_ERROR_DEVICE_LOST|Fatal signal'
    )
}
