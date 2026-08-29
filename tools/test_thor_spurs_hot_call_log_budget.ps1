$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$records = @(
    'cellSpursWakeUp(spurs=*0x%x)',
    'cellSpursEventFlagWait(eventFlag=*0x%x, mask=*0x%x, mode=%d)',
    'cellSpursEventFlagTryWait(eventFlag=*0x%x, mask=*0x%x, mode=0x%x)',
    '_cellSpursLFQueuePushBody(queue=*0x%x, buffer=*0x%x, isBlocking=%d)',
    '_cellSpursLFQueuePopBody(queue=*0x%x, buffer=*0x%x, isBlocking=%d)',
    'cellSpursLookUpTasksetAddress(spurs=*0x%x, taskset=**0x%x, id=0x%x)'
)

foreach ($record in $records) {
    $traceCall = "cellSpurs.trace(`"$record`""
    $warningCall = "cellSpurs.warning(`"$record`""

    if (-not $source.Contains($traceCall)) {
        throw "The hot SPURS call record must use trace level: $record"
    }

    if ($source.Contains($warningCall)) {
        throw "The hot SPURS call record must not use warning level: $record"
    }
}

Write-Output "Thor SPURS hot-call log budget test passed."
