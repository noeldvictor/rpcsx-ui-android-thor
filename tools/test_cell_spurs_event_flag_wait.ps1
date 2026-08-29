$ErrorActionPreference = "Stop"

$cellSpursPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$cellSpurs = Get-Content -LiteralPath $cellSpursPath -Raw
$probePath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\thor_spurs_event_wait_probe.h"
$probe = Get-Content -LiteralPath $probePath -Raw

$setComment = $cellSpurs.IndexOf('/// Set a SPURS event flag')
$setStart = $cellSpurs.IndexOf('s32 cellSpursEventFlagSet(', $setComment)
$waitStart = $cellSpurs.IndexOf('s32 _spurs::event_flag_wait(', $setStart)
if ($setComment -lt 0 -or $setStart -lt 0 -or $waitStart -le $setStart) {
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

$requiredSignalDiagnostic = 'if (rc != CELL_OK)'
if (-not $setBody.Contains($requiredSignalDiagnostic)) {
    throw "The SPURS event-flag Set function does not handle a firmware diagnostic result."
}

$requiredSignalState = 'state{run=%08x ready=%08x pready=%08x wait=%08x enabled=%08x sig=%08x}'
if (-not $setBody.Contains($requiredSignalState)) {
    throw "The SPURS event-flag signal diagnostic does not record the task state."
}

$requiredFatalResults = 'rc + 0u == CELL_SPURS_TASK_ERROR_INVAL || rc + 0u == CELL_SPURS_TASK_ERROR_STAT'
if (-not $setBody.Contains($requiredFatalResults)) {
    throw "The SPURS event-flag Set function does not map INVAL and STAT to FATAL."
}

$rejectedSignalAssert = 'ensure(rc == CELL_OK);'
if ($setBody.Contains($rejectedSignalAssert)) {
    throw "The SPURS event-flag Set function stops the PPU thread for a firmware diagnostic result."
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

$requiredTraceFragments = @(
    'static bool thor_transformers_edge_event_wait_trace() noexcept',
    '"debug.rpcsx.thor.edge_event_wait_trace"',
    'eventFlag.addr() == 0x01e54800u',
    'const u16 requested_mask = *mask;',
    'thor_edge_wait_index < 2048 && (thor_edge_wait_index & 0x7f) == 0',
    'Thor EDGE EFWAIT ARM #%u',
    'Thor EDGE EFWAIT WAKE #%u',
    'Thor EDGE EFWAIT RETURN #%u',
    'thor::spurs_event_wait_arm(',
    'thor::spurs_event_wait_wake(',
    'thor::spurs_event_wait_finish(',
    'receivedEvents = eventFlag->pendingRecvTaskEvents[i];'
)

foreach ($fragment in $requiredTraceFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The bounded SPURS event-flag wait trace is missing: $fragment"
    }
}

$requiredProbeFragments = @(
    'inline spurs_event_wait_probe_state g_spurs_event_wait_probe;',
    'inline void spurs_event_wait_arm(',
    'inline void spurs_event_wait_wake(',
    'inline void spurs_event_wait_finish(',
    'inline spurs_event_wait_snapshot get_spurs_event_wait_snapshot()',
    'state.active.store(1, std::memory_order_release);',
    'state.active.store(0, std::memory_order_release);'
)

foreach ($fragment in $requiredProbeFragments) {
    if (-not $probe.Contains($fragment)) {
        throw "The SPURS event-wait state probe is missing: $fragment"
    }
}

Write-Output "SPURS event-flag wait contract passed."
