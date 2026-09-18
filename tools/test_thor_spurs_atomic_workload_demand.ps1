$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$helperMatch = [regex]::Match(
    $source,
    '(?m)^struct alignas\(128\) spurs_kernel1_claim_op[\s\S]*?(?=^static bool thor_hle_once)'
)
if (-not $helperMatch.Success) {
    throw "The atomic SPURS workload-demand helper was not found."
}

$helper = $helperMatch.Value
foreach ($required in @(
    'CHECK_SIZE_ALIGN(spurs_kernel1_claim_op, 128, 128);',
    'vm::reservation_op<true>(spu,',
    'op.currentContention[selectedId]',
    'op.maxContention[selectedId]',
    'const bool hasSignal =',
    'const bool hasFlag =',
    'const bool hasReadyDemand =',
    'if (current >= maximum || (!hasSignal && !hasFlag && !hasReadyDemand))',
    'op.currentContention[selectedId] = current + 1;',
    'op.signal1 &= ~signalMask;',
    'op.workloadFlag = -1;'
)) {
    if (-not $helper.Contains($required)) {
        throw "The atomic SPURS workload-demand claim is missing '$required'."
    }
}

foreach ($forbidden in @(
    'spursConsumeHleEntrySignal',
    'spursAtomicNotifySignalWaiters',
    'deferHleSignal',
    'deferSignalToHleEntry'
)) {
    if ($source.Contains($forbidden)) {
        throw "Obsolete HLE entry signal deferral remains: '$forbidden'."
    }
}

$helperEnd = $source.IndexOf('static bool thor_hle_once')
$selectorEnd = $source.IndexOf('// Select a workload to run', $helperEnd)
$selectorStart = $source.LastIndexOf('bool spursKernel1SelectWorkload(spu_thread& spu)', $selectorEnd)
if ($selectorStart -lt 0 -or $selectorEnd -le $selectorStart) {
    throw "The SPURS kernel 1 selector was not found."
}
$selector = $source.Substring($selectorStart, $selectorEnd - $selectorStart)

$claimIndex = $selector.IndexOf('contentionClaimed = spursAtomicTryClaimWorkload(spu, ctxt, wklSelectedId);')
$claimClearGuardIndex = $selector.IndexOf('else if (contentionClaimed)', $claimIndex)
$fallbackClearIndex = $selector.IndexOf('spursAtomicClearSelectedSignal(spurs, wklSelectedId, thor_spurs_signal_fix());', $claimClearGuardIndex)
if ($claimIndex -lt 0 -or $claimClearGuardIndex -le $claimIndex -or $fallbackClearIndex -le $claimClearGuardIndex) {
    throw "The selector can clear a new workload signal after an atomic claim."
}

if (-not $source.Contains('const bool signalConsumedBySelector = thor_spurs_signal_fix()')) {
    throw "The dispatch path can clear a new HLE workload signal after selection."
}

Write-Output "Thor SPURS atomic workload-demand contract passed."
