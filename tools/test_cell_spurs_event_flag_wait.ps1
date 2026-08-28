$ErrorActionPreference = "Stop"

$cellSpursPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$cellSpurs = Get-Content -LiteralPath $cellSpursPath -Raw

$requiredFragment = 'receivedEvents = eventFlag->pendingRecvTaskEvents[i];'
if (-not $cellSpurs.Contains($requiredFragment)) {
    throw "The blocking SPURS event-flag wait does not keep the received event mask."
}

$rejectedFragment = '*mask = eventFlag->pendingRecvTaskEvents[i];'
if ($cellSpurs.Contains($rejectedFragment)) {
    throw "The blocking SPURS event-flag wait writes the mask before the final assignment."
}

$finalAssignment = '*mask = receivedEvents;'
if (-not $cellSpurs.Contains($finalAssignment)) {
    throw "The SPURS event-flag wait does not return the selected event mask."
}

Write-Output "SPURS event-flag wait contract passed."
