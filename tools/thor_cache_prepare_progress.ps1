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
    $latestModule = 0
    $totalModules = 0
    $latestFile = 0
    $totalFiles = 0
    if ($progressMatches.Count -gt 0) {
        $latest = $progressMatches[$progressMatches.Count - 1]
        if ($latest.Groups[1].Success) {
            $latestFile = [int]$latest.Groups[1].Value
            $totalFiles = [int]$latest.Groups[2].Value
        }
        $latestModule = [int]$latest.Groups[3].Value
        $totalModules = [int]$latest.Groups[4].Value
    }

    $initialProgressMatches = [regex]::Matches(
        $NativeText,
        'Progress: module ([0-9]+) of ([0-9]+)'
    )
    $scanProgressMatches = [regex]::Matches(
        $NativeText,
        'Progress: file ([0-9]+) of ([0-9]+), module ([0-9]+) of ([0-9]+)'
    )
    $initialModule = 0
    $initialTotalModules = 0
    if ($scanProgressMatches.Count -gt 0) {
        $scanStarted = $scanProgressMatches[0]
        $initialModule = [int]$scanStarted.Groups[3].Value
        $initialTotalModules = [int]$scanStarted.Groups[4].Value
    } elseif ($initialProgressMatches.Count -gt 0) {
        $initialLatest = $initialProgressMatches[$initialProgressMatches.Count - 1]
        $initialModule = [int]$initialLatest.Groups[1].Value
        $initialTotalModules = [int]$initialLatest.Groups[2].Value
    }

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
        initial_workload_complete = $initialTotalModules -gt 0 -and
            $initialModule -eq $initialTotalModules
        has_reuse = $reusedModules -gt 0
        has_progress = $compiledModules -gt 0 -and $latestModule -gt 0 -and
            $totalModules -ge $latestModule
    }
}

function Test-ThorCachePrepareNativeFatal {
    param([string]$NativeText)

    return [regex]::IsMatch(
        $NativeText,
        '(?im)^(?:[^\x00-\x7f]+)?F\s|VM:\s+Access violation|VK_ERROR_DEVICE_LOST|Fatal signal'
    )
}
