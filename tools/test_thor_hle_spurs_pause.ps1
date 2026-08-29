$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

function Get-FunctionBody {
    param(
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )

    $end = $source.IndexOf($EndMarker)
    $start = if ($end -ge 0) { $source.LastIndexOf($StartMarker, $end) } else { -1 }
    if ($start -lt 0 -or $end -le $start) {
        throw "Could not isolate '$StartMarker'."
    }
    return $source.Substring($start, $end - $start)
}

$idle = Get-FunctionBody `
    -StartMarker 'void spursSysServiceIdleHandler(spu_thread& spu, SpursKernelContext* ctxt)' `
    -EndMarker '// Main function for the system service'
$main = Get-FunctionBody `
    -StartMarker 'void spursSysServiceMain(spu_thread& spu, u32 pollStatus)' `
    -EndMarker '// Process any requests'

$stateLoad = 'const auto threadState = spu.state.load();'
$stateCheck = 'if ((is_stopped(threadState) || threadState & (cpu_flag::dbg_global_pause | cpu_flag::dbg_pause)) && spu.check_state())'
foreach ($entry in @(
    @{ Name = "idle handler"; Body = $idle },
    @{ Name = "system service"; Body = $main }
)) {
    if ($entry.Body.Contains('if (spu.state && spu.check_state())')) {
        throw "The HLE SPURS $($entry.Name) still processes normal scheduler state bits."
    }

    foreach ($schedulerState in @('is_paused(threadState)', 'threadState & cpu_flag::pause')) {
        if ($entry.Body.Contains($schedulerState)) {
            throw "The HLE SPURS $($entry.Name) processes the normal scheduler state '$schedulerState'."
        }
    }

    if (-not $entry.Body.Contains($stateLoad)) {
        throw "The HLE SPURS $($entry.Name) does not take one state snapshot."
    }

    if (-not $entry.Body.Contains($stateCheck)) {
        throw "The HLE SPURS $($entry.Name) does not limit the state check to pause and stop."
    }

    $loopIndex = $entry.Body.IndexOf('while (true)')
    $checkIndex = $entry.Body.IndexOf($stateCheck, $loopIndex)
    if ($loopIndex -lt 0 -or $checkIndex -le $loopIndex) {
        throw "The HLE SPURS $($entry.Name) state check is not inside its long loop."
    }
}

Write-Output "Thor HLE SPURS pause contract passed."
