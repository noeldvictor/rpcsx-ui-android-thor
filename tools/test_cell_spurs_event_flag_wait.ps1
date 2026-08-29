$ErrorActionPreference = "Stop"

$cellSpursPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$cellSpurs = Get-Content -LiteralPath $cellSpursPath -Raw

$setStart = $cellSpurs.IndexOf('s32 cellSpursEventFlagSet(')
$waitStart = $cellSpurs.IndexOf('s32 _spurs::event_flag_wait(', $setStart)
if ($setStart -lt 0 -or $waitStart -le $setStart) {
    throw "The SPURS event-flag Set function is not in the expected source range."
}

$setBody = $cellSpurs.Substring($setStart, $waitStart - $setStart)
$setDirection = 'dir != CELL_SPURS_EVENT_FLAG_PPU2SPU && dir != CELL_SPURS_EVENT_FLAG_ANY2ANY'
if (-not $setBody.Contains($setDirection)) {
    throw "The PPU event-flag Set function does not allow PPU-to-SPU flags."
}

$rejectedSetDirection = 'dir != CELL_SPURS_EVENT_FLAG_SPU2PPU && dir != CELL_SPURS_EVENT_FLAG_ANY2ANY'
if ($setBody.Contains($rejectedSetDirection)) {
    throw "The PPU event-flag Set function incorrectly allows only SPU-to-PPU flags."
}

$requiredSlotWrite = 'pendingRecvTaskEvents[i] = spuTaskRelevantEvents;'
if (-not $setBody.Contains($requiredSlotWrite)) {
    throw "The SPURS event-flag Set function does not save events in the selected wait slot."
}

$rejectedSlotWrite = 'pendingRecvTaskEvents[j] = spuTaskRelevantEvents;'
if ($setBody.Contains($rejectedSlotWrite)) {
    throw "The SPURS event-flag Set function saves events in the mirrored wait slot."
}

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
