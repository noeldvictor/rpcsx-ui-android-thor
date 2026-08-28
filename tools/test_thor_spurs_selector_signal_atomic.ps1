$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$helperMatch = [regex]::Match(
    $source,
    '(?m)^static void spursAtomicClearSelectedSignal\([\s\S]*?(?=^static bool thor_hle_once)'
)

if (-not $helperMatch.Success) {
    throw "The atomic SPURS signal clear helper was not found."
}

$helperSource = $helperMatch.Value
foreach ($signalName in @("wklSignal1", "wklSignal2")) {
    if (-not $helperSource.Contains("$signalName.atomic_op")) {
        throw "The SPURS signal clear helper must update $signalName atomically."
    }
}

if (-not $helperSource.Contains('else if (!guardSystemService)') -or
    -not $helperSource.Contains('signal1Mask = 0x8000u;')) {
    throw "The atomic helper must preserve the measured system service behavior."
}

$selectorCall = 'spursAtomicClearSelectedSignal(spurs, wklSelectedId, thor_spurs_signal_fix());'
$selectorCallCount = [regex]::Matches($source, [regex]::Escape($selectorCall)).Count
if ($selectorCallCount -ne 2) {
    throw "Expected both SPURS selectors to use the atomic signal helper. Found $selectorCallCount calls."
}

if ($source.Contains('wklSignal1.raw() &=') -or $source.Contains('wklSignal2.raw() &=')) {
    throw "A SPURS selector still updates a workload signal through a non-atomic raw reference."
}

Write-Output "Thor SPURS selector signal atomic test passed."
