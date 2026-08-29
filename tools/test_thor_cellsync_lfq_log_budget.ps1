$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSync.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$records = @(
    '_cellSyncLFQueuePushBody(queue=*0x%x, buffer=*0x%x, isBlocking=%d)',
    '_cellSyncLFQueuePopBody(queue=*0x%x, buffer=*0x%x, isBlocking=%d)'
)

foreach ($record in $records) {
    if (-not $source.Contains("cellSync.trace(`"$record`"")) {
        throw "The hot cellSync LFQueue call record must use trace level: $record"
    }

    if ($source.Contains("cellSync.warning(`"$record`"")) {
        throw "The hot cellSync LFQueue call record must not use warning level: $record"
    }
}

Write-Output "Thor cellSync LFQueue log budget test passed."
