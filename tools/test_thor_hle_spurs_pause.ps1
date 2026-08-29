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
}

if (-not $idle.Contains($stateLoad) -or -not $idle.Contains($stateCheck)) {
    throw "The HLE SPURS idle handler does not limit its state check to debug pause and stop."
}

$noWorkIndex = $idle.IndexOf('if (spuIdling && shouldExit == false && foundReadyWorkload == false)')
$checkIndex = $idle.IndexOf($stateCheck, $noWorkIndex)
$sleepIndex = $idle.IndexOf('thread_ctrl::wait_for(1000);', $noWorkIndex)
if ($noWorkIndex -lt 0 -or $checkIndex -le $noWorkIndex -or $sleepIndex -le $checkIndex) {
    throw "The HLE SPURS state check is not in the idle no-work branch before its sleep."
}

$rateLimit = 'if ((++pauseCheckCounter & 0xff) == 0)'
$loopIndex = $main.IndexOf('while (true)')
$rateLimitIndex = $main.IndexOf($rateLimit, $loopIndex)
$mainLoadIndex = $main.IndexOf($stateLoad, $rateLimitIndex)
$mainCheckIndex = $main.IndexOf($stateCheck, $mainLoadIndex)
$processIndex = $main.IndexOf('spursSysServiceProcessRequests(spu, ctxt);', $mainCheckIndex)
if (-not $main.Contains('u32 pauseCheckCounter = 0;') -or
    $loopIndex -lt 0 -or
    $rateLimitIndex -le $loopIndex -or
    $mainLoadIndex -le $rateLimitIndex -or
    $mainCheckIndex -le $mainLoadIndex -or
    $processIndex -le $mainCheckIndex) {
    throw "The HLE SPURS active pause check is not rate-limited before system-service work."
}

if ($main.IndexOf($stateLoad, $mainLoadIndex + $stateLoad.Length) -ge 0 -or
    $main.IndexOf('spu.check_state()', $mainCheckIndex + $stateCheck.Length) -ge 0) {
    throw "The HLE SPURS system-service loop has more than one active state check."
}

Write-Output "Thor HLE SPURS pause contract passed."
