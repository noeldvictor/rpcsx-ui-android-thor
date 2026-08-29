$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$helperMatch = [regex]::Match(
    $source,
    '(?m)^static bool spursAtomicTryClaimWorkload\([\s\S]*?(?=^static bool thor_hle_once)'
)
if (-not $helperMatch.Success) {
    throw "The atomic SPURS contention claim helper was not found."
}

$helper = $helperMatch.Value
foreach ($required in @(
    'vm::reservation_op<true>(spu,',
    'op.maxContention[selectedId]',
    'op.currentContention[selectedId]',
    'if (current >= maximum',
    'op.currentContention[selectedId] = current + 1;'
)) {
    if (-not $helper.Contains($required)) {
        throw "The atomic SPURS contention claim is missing '$required'."
    }
}

$helperEnd = $source.IndexOf('static bool thor_hle_once')
$selectorEnd = $source.IndexOf('// Select a workload to run', $helperEnd)
$selectorStart = $source.LastIndexOf('bool spursKernel1SelectWorkload(spu_thread& spu)', $selectorEnd)
if ($selectorStart -lt 0 -or $selectorEnd -le $selectorStart) {
    throw "The SPURS kernel 1 selector was not found."
}
$selector = $source.Substring($selectorStart, $selectorEnd - $selectorStart)

$claimCall = 'contentionClaimed = spursAtomicTryClaimWorkload(spu, ctxt, wklSelectedId);'
$failedClaim = [regex]::Match(
    $selector,
    'if \(!contentionClaimed\)\s*\{\s*wklSelectedId = CELL_SPURS_SYS_SERVICE_WORKLOAD_ID;\s*pollStatus = 0;\s*\}'
)
$signalClear = 'spursAtomicClearSelectedSignal(spurs, wklSelectedId, thor_spurs_signal_fix());'
$claimIndex = $selector.IndexOf($claimCall)
$failedClaimIndex = if ($failedClaim.Success) { $failedClaim.Index } else { -1 }
$signalIndex = $selector.IndexOf($signalClear)
if ($claimIndex -lt 0 -or $failedClaimIndex -le $claimIndex -or $signalIndex -le $failedClaimIndex) {
    throw "The selector does not reject a failed claim before it clears a workload signal."
}

$claimGuard = '!isPoll && thor_contention_atomic_fix()'
if (-not $selector.Contains($claimGuard)) {
    throw "The atomic SPURS contention claim is not limited to a kernel selection."
}

$transferGuard = 'if (!contentionClaimed)'
if ([regex]::Matches($selector, [regex]::Escape($transferGuard)).Count -lt 2) {
    throw "The SPURS contention transfer can increment a slot after an atomic claim."
}

Write-Output "Thor HLE SPURS contention claim contract passed."
