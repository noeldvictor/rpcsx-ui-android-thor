$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw
$functionMatch = [regex]::Match(
    $source,
    '(?m)^s32 cellSpursSendWorkloadSignal\(ppu_thread& ppu, vm::ptr<CellSpurs> spurs, u32 wid\)\r?\n\{[\s\S]*?^\}'
)

if (-not $functionMatch.Success) {
    throw "The SPURS workload signal function was not found."
}

$functionSource = $functionMatch.Value
$budgetGateCount = [regex]::Matches($functionSource, 'if \(thor_call_index < 8\)').Count

if (-not $functionSource.Contains('static std::atomic<u32> s_thor_signal_calls{0};')) {
    throw "The SPURS workload signal log counter was not found."
}

if ($budgetGateCount -ne 2) {
    throw "Expected two bounded SPURS workload signal log gates, found $budgetGateCount."
}

if ($functionSource -notmatch 'if \(thor_call_index < 8\)[\s\S]*?Thor signal wid=%u: inside=') {
    throw "The successful SPURS workload signal record is not bounded."
}

if (-not $functionSource.Contains('vm::light_op<true>(wid < CELL_SPURS_MAX_WORKLOAD ? spurs->wklSignal1 : spurs->wklSignal2')) {
    throw "The SPURS workload signal write must notify reservation waiters."
}

if ($functionSource -match '\? spurs->wklSignal1 : spurs->wklSignal2\)\.atomic_op') {
    throw "The SPURS workload signal write must not use a non-notifying member atomic."
}

Write-Output "Thor SPURS workload signal log budget test passed."
