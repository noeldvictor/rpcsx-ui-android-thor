$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw
$functionMatch = [regex]::Match(
    $source,
    '(?m)^s32 cellSpursQueuePushBody\(ppu_thread& ppu,[\s\S]*?(?=^s32 cellSpursQueuePopBody)'
)

if (-not $functionMatch.Success) {
    throw "The SPURS queue push function was not found."
}

$functionSource = $functionMatch.Value
$callRecord = 'cellSpursQueuePushBody(queue=*0x%x, buffer=*0x%x, taskId=%d)'

if (-not $functionSource.Contains("cellSpurs.trace(`"$callRecord`"")) {
    throw "The SPURS queue push call record must use trace level."
}

if ($functionSource.Contains("cellSpurs.warning(`"$callRecord`"")) {
    throw "The SPURS queue push call record must not use warning level."
}

$requiredFragments = @(
    'static bool thor_queue_diagnostics() noexcept',
    '"debug.rpcsx.thor.queue_diagnostics"',
    'if (thor_queue_diagnostics())',
    'Thor QUEUE RING',
    'Thor PAYLOAD',
    'Thor QUEUE PUSH OK'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "The SPURS queue log budget is missing: $fragment"
    }
}

if ([regex]::Matches($functionSource, 'if \(thor_queue_diagnostics\(\)\)').Count -lt 3) {
    throw "The SPURS queue diagnostics must gate the ring, payload, and success records."
}

$signalIndex = $functionSource.IndexOf('Thor SIGNAL')
$signalGateIndex = $functionSource.LastIndexOf('if (thor_queue_diagnostics())', $signalIndex)

if ($signalIndex -lt 0 -or $signalGateIndex -lt 0 -or ($signalIndex - $signalGateIndex) -gt 1200) {
    throw "The SPURS queue diagnostics must gate the signal state record."
}

Write-Output "Thor SPURS queue log budget test passed."
