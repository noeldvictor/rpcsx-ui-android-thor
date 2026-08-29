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

Write-Output "Thor SPURS queue log budget test passed."
