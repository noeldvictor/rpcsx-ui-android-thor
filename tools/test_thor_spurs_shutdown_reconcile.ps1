$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$repairMatch = [regex]::Match(
    $source,
    '(?m)^static s32 thor_reconcile_transformers_shutdown\([\s\S]*?(?=^/// Wait for workload shutdown)'
)
if (-not $repairMatch.Success) {
    throw "The Transformers shutdown repair was not found."
}

$repair = $repairMatch.Value
foreach ($required in @(
    '!get_thor_hle_spurs_kernel_enabled()',
    'Emu.GetTitleID() != "BLUS30357"',
    'wid != 7',
    'currentIds.fill(umax);',
    'const u32 current1 = +atomic_storage<be_t<u32>>::load(ctxt->wklCurrentId);',
    'const u32 current2 = +atomic_storage<be_t<u32>>::load(ctxt->wklCurrentId);',
    'current1 != current2',
    'ctxt->spurs.addr() != spurs.addr()',
    'const u8 keepSpus = activeSpus | static_cast<u8>(~knownSpus);',
    'state != SPURS_WKL_STATE_SHUTTING_DOWN',
    'status = (status & keepSpus) | activeSpus;',
    'state = SPURS_WKL_STATE_REMOVABLE;',
    'sendEvent = event & 0x12 && !(event & 1);',
    'event |= 1;',
    'sys_event_port_send(spurs->eventPort, 0, 0, (1u << 31) >> wid)',
    'Thor TWC SHUTDOWN RECONCILE'
)) {
    if (-not $repair.Contains($required)) {
        throw "The Transformers shutdown repair is missing '$required'."
    }
}

if ($repair.Contains('status = 0;')) {
    throw "The Transformers shutdown repair clears unknown SPU status bits."
}

$waitMatch = [regex]::Match(
    $source,
    '(?m)^s32 cellSpursWaitForWorkloadShutdown\([\s\S]*?(?=^s32 cellSpursRemoveSystemWorkloadForUtility\()'
)
if (-not $waitMatch.Success) {
    throw "The SPURS workload wait function was not found."
}

$wait = $waitMatch.Value
$repairIndex = $wait.IndexOf('thor_reconcile_transformers_shutdown(ppu, spurs, wid)')
$syncIndex = $wait.IndexOf('auto& info = spurs->wklSyncInfo(wid);')
if ($repairIndex -lt 0 -or $syncIndex -le $repairIndex) {
    throw "The shutdown repair does not run before the semaphore wait setup."
}

foreach ($required in @(
    'const bool retry_transformers_shutdown = get_thor_hle_spurs_kernel_enabled()',
    'Emu.GetTitleID() == "BLUS30357" && wid == 7;',
    "constexpr u64 retry_us = 20'000;",
    'sys_semaphore_wait(ppu, static_cast<u32>(info.sem), retry_us)',
    'wait_result + 0u == CELL_ETIMEDOUT',
    'Thor TWC SHUTDOWN WAIT RETRY'
)) {
    if (-not $wait.Contains($required)) {
        throw "The Transformers shutdown wait retry is missing '$required'."
    }
}

$timedWaitIndex = $wait.IndexOf('sys_semaphore_wait(ppu, static_cast<u32>(info.sem), retry_us)')
$lateRepairIndex = $wait.LastIndexOf('thor_reconcile_transformers_shutdown(ppu, spurs, wid)')
if ($timedWaitIndex -lt 0 -or $lateRepairIndex -le $timedWaitIndex) {
    throw "The shutdown repair does not retry after the timed semaphore wait."
}

Write-Output "Thor SPURS shutdown reconciliation contract passed."
