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
    $progressMatches = [regex]::Matches($NativeText, 'Progress: module ([0-9]+) of ([0-9]+)')
    $latestModule = 0
    $totalModules = 0
    if ($progressMatches.Count -gt 0) {
        $latest = $progressMatches[$progressMatches.Count - 1]
        $latestModule = [int]$latest.Groups[1].Value
        $totalModules = [int]$latest.Groups[2].Value
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
