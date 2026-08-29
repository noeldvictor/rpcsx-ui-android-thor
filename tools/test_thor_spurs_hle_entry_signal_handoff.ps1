$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

foreach ($required in @(
    'static bool spursWorkloadUsesHleEntry(',
    'policyAddress == SPURS_IMG_ADDR_TASKSET_PM',
    'policyAddress == SPURS_IMG_ADDR_JOBCHAIN_PM',
    'static void spursConsumeHleEntrySignal(',
    'spursAtomicClearSelectedSignal(ctxt->spurs.get_ptr(), ctxt->wklCurrentId, true);',
    'const bool deferSignalToHleEntry = thor_spurs_signal_fix()',
    'spursConsumeHleEntrySignal(spu, kernelCtxt);'
)) {
    if (-not $source.Contains($required)) {
        throw "The HLE entry signal handoff is missing '$required'."
    }
}

$entryConsumeCount = [regex]::Matches(
    $source,
    [regex]::Escape('spursConsumeHleEntrySignal(spu, kernelCtxt);')
).Count
if ($entryConsumeCount -ne 2) {
    throw "Expected the taskset and job-chain HLE entries to consume deferred signals. Found $entryConsumeCount calls."
}

$selectorDeferralCount = [regex]::Matches($source, 'deferHleSignal2? =').Count
if ($selectorDeferralCount -ne 2) {
    throw "Expected both SPURS selectors to defer HLE policy signals. Found $selectorDeferralCount deferrals."
}

$dispatchGuard = 'if (!deferSignalToHleEntry && wid < CELL_SPURS_MAX_WORKLOAD)'
if (-not $source.Contains($dispatchGuard)) {
    throw "The dispatch path can consume an HLE policy signal before its entry callback."
}

Write-Output "Thor SPURS HLE entry signal handoff test passed."
