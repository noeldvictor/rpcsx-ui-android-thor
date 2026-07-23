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

function Get-ThorCaptureRecordedCompletion {
    param([Parameter(Mandatory = $true)][string]$CaptureDirectory)

    if (-not (Test-Path -LiteralPath $CaptureDirectory -PathType Container)) {
        throw "Thor capture directory does not exist: $CaptureDirectory"
    }

    $timestamps = New-Object System.Collections.Generic.List[DateTimeOffset]
    $evidenceFiles = @(
        Get-ChildItem -LiteralPath $CaptureDirectory -File -Filter "*.txt"
        foreach ($name in @(
            "thermal-guard.log",
            "debug-boot-handshake.log",
            "debug-boot-handshake-status.log",
            "macro.log",
            "process-guard.log"
        )) {
            $path = Join-Path $CaptureDirectory $name
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                Get-Item -LiteralPath $path
            }
        }
    ) | Sort-Object FullName -Unique

    foreach ($file in $evidenceFiles) {
        foreach ($line in (Get-Content -LiteralPath $file.FullName)) {
            $timestampText = if ($line -match '^# captured\s+(\S+)\s*$') {
                $Matches[1]
            } elseif ($file.Extension -eq ".log" -and $line -match '^(\d{4}-\d{2}-\d{2}T\S+)\s') {
                $Matches[1]
            } else {
                $null
            }
            if ($null -eq $timestampText) {
                continue
            }

            $parsed = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse(
                    $timestampText,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::RoundtripKind,
                    [ref]$parsed
                )) {
                throw "Thor capture contains an invalid recorded timestamp in $($file.Name): $timestampText"
            }
            $timestamps.Add($parsed) | Out-Null
        }
    }

    if ($timestamps.Count -eq 0) {
        throw "Thor capture has no recorded device-contact timestamp: $CaptureDirectory"
    }

    return @($timestamps | Sort-Object -Descending)[0]
}
function Get-ThorCachePrepareCooldownSource {
    param(
        [string]$CacheCaptureName = "none",
        [AllowNull()][object]$CacheCompletedAt,
        [string]$InstallCaptureName = "none",
        [AllowNull()][object]$InstallCompletedAt,
        [string]$TitleCaptureName = "none",
        [AllowNull()][object]$TitleCompletedAt
    )

    if ($null -ne $TitleCompletedAt -and
        ($null -eq $InstallCompletedAt -or
            [DateTimeOffset]$TitleCompletedAt -ge [DateTimeOffset]$InstallCompletedAt) -and
        ($null -eq $CacheCompletedAt -or
            [DateTimeOffset]$TitleCompletedAt -ge [DateTimeOffset]$CacheCompletedAt)) {
        return [pscustomobject]@{
            kind = "title"
            name = $TitleCaptureName
            completed_at = [DateTimeOffset]$TitleCompletedAt
        }
    }

    if ($null -ne $InstallCompletedAt -and
        ($null -eq $CacheCompletedAt -or
            [DateTimeOffset]$InstallCompletedAt -ge [DateTimeOffset]$CacheCompletedAt)) {
        return [pscustomobject]@{
            kind = "install"
            name = $InstallCaptureName
            completed_at = [DateTimeOffset]$InstallCompletedAt
        }
    }

    if ($null -ne $CacheCompletedAt) {
        return [pscustomobject]@{
            kind = "cache"
            name = $CacheCaptureName
            completed_at = [DateTimeOffset]$CacheCompletedAt
        }
    }

    return [pscustomobject]@{
        kind = "none"
        name = "none"
        completed_at = $null
    }
}

function Get-ThorCachePrepareReuseFloor {
    param(
        [AllowEmptyString()][string]$LatestReadmeText,
        [ValidateRange(1, [int]::MaxValue)][int]$DefaultMinimum = 1
    )

    if ([string]::IsNullOrWhiteSpace($LatestReadmeText)) {
        return $DefaultMinimum
    }

    $status = [regex]::Match($LatestReadmeText, '(?m)^- Status:\s*(.+)$')
    $failure = [regex]::Match($LatestReadmeText, '(?m)^- Failure:\s*(.+)$')
    $isProgressCheckpoint = $status.Success -and
        $status.Groups[1].Value.Trim() -eq 'cache-progress-checkpoint'
    $isThermalStop = $status.Success -and $status.Groups[1].Value.Trim() -eq 'failed' -and
        $failure.Success -and $failure.Groups[1].Value.Trim().StartsWith('Runtime thermal stop:')
    if (-not $isProgressCheckpoint -and -not $isThermalStop) {
        return $DefaultMinimum
    }

    $reused = [regex]::Match($LatestReadmeText, '(?m)^- Reused modules this round:\s*([0-9]+)\s*$')
    $compiled = [regex]::Match($LatestReadmeText, '(?m)^- Compiled modules this round:\s*([0-9]+)\s*$')
    if (-not $reused.Success -or -not $compiled.Success) {
        throw 'Latest cache-progress capture is missing reusable-object continuity evidence.'
    }

    return [Math]::Max(
        $DefaultMinimum,
        [int]$reused.Groups[1].Value + [int]$compiled.Groups[1].Value
    )
}

function Get-ThorSpuNativeObjectReuseFloor {
    param(
        [AllowEmptyString()][string]$LatestReadmeText,
        [ValidateRange(1, [int]::MaxValue)][int]$MaximumObjects = 64
    )

    if ([string]::IsNullOrWhiteSpace($LatestReadmeText)) {
        return 0
    }

    $status = [regex]::Match($LatestReadmeText, '(?m)^- Status:\s*(.+)$')
    $loaded = [regex]::Match(
        $LatestReadmeText,
        '(?m)^- SPU native objects loaded:\s*([0-9]+)\s*$'
    )
    $built = [regex]::Match(
        $LatestReadmeText,
        '(?m)^- SPU workers built programs:\s*([0-9]+)\s*$'
    )
    if (-not $loaded.Success -and -not $built.Success) {
        return 0
    }
    if (-not $status.Success -or
        $status.Groups[1].Value.Trim() -notin @(
            'cache-progress-checkpoint',
            'cache-prepared-exact-no-game-boot'
        )) {
        return 0
    }
    if (-not $loaded.Success -or -not $built.Success) {
        throw 'Latest cache capture has incomplete SPU native-object continuity evidence.'
    }

    foreach ($requiredSafetyRow in @(
        '- SPU native completed: True',
        '- SPU native cache enabled: True',
        '- SPU preload bounded: True',
        '- SPU compile budget enabled: True',
        '- SPU cache affinity matched: True',
        '- SPU cache worker pool matched: True',
        '- SPU properties reset: True',
        '- Native process died: False',
        '- Native fatal: False',
        '- Game boot: no'
    )) {
        if (-not $LatestReadmeText.Contains($requiredSafetyRow)) {
            throw "Latest cache capture cannot seed SPU native-object continuity: missing '$requiredSafetyRow'."
        }
    }

    $floor = [int]$loaded.Groups[1].Value + [int]$built.Groups[1].Value
    if ($floor -gt $MaximumObjects) {
        throw "Latest cache capture reports $floor SPU native objects, above the $MaximumObjects-object bound."
    }

    return $floor
}

function Test-ThorCachePrepareNativeFatal {
    param([string]$NativeText)

    return [regex]::IsMatch(
        $NativeText,
        '(?im)^(?:[^\x00-\x7f]+)?F\s|VM:\s+Access violation|VK_ERROR_DEVICE_LOST|Fatal signal'
    )
}
