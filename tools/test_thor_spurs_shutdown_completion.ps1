$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$ppuSource = Get-Content -LiteralPath $ppuPath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw

$createMatch = [regex]::Match(
    $ppuSource,
    '(?m)^s32 _spurs::create_event_helper\([\s\S]*?(?=^void _spurs::init_event_port_mux\()'
)
if (-not $createMatch.Success) {
    throw "The SPURS event helper creation function was not found."
}

$create = $createMatch.Value
foreach ($required in @(
    'func_addr(s_thor_spurs_event_helper_index, true)',
    'vm::alloc(0x8000, vm::stack, 4096)',
    'idm::import<named_thread<ppu_thread>>',
    'p.entry = ppu_func_opd_t{code, 0};',
    'p.arg0 = spurs.addr();',
    'spurs->ppu1 = tid;',
    'sys_ppu_thread_start(ppu, tid)'
)) {
    if (-not $create.Contains($required)) {
        throw "The SPURS event helper creation contract is missing '$required'."
    }
}

if (-not $ppuSource.Contains('register_function<decltype(&_spurs::event_helper_entry), &_spurs::event_helper_entry>')) {
    throw "The SPURS event helper HLE entry is not registered."
}

$entryMatch = [regex]::Match(
    $ppuSource,
    '(?m)^void _spurs::event_helper_entry\([\s\S]*?(?=^s32 _spurs::create_event_helper\()'
)
if (-not $entryMatch.Success) {
    throw "The SPURS event helper entry was not found."
}

$entry = $entryMatch.Value
foreach ($required in @(
    'return sys_ppu_thread_exit(ppu, 0);',
    'const u32 shutdownMask = static_cast<u32>(event_data3);',
    '_spurs::wakeup_shutdown_completion_waiter(ppu, spurs, wid)'
)) {
    if (-not $entry.Contains($required)) {
        throw "The SPURS event helper entry contract is missing '$required'."
    }
}

$completionMatch = [regex]::Match(
    $spuSource,
    '(?m)^void spursSysServiceUpdateShutdownCompletionEvents\([\s\S]*?(?=^// Update the trace count)'
)
if (-not $completionMatch.Success) {
    throw "The SPURS shutdown completion function was not found."
}

$processMatch = [regex]::Match(
    $spuSource,
    '(?m)^void spursSysServiceProcessRequests\([\s\S]*?(?=^// Activate a workload)'
)
if (-not $processMatch.Success) {
    throw "The SPURS system-service request function was not found."
}

$activateMatch = [regex]::Match(
    $spuSource,
    '(?m)^void spursSysServiceActivateWorkload\([\s\S]*?(?=^// Update shutdown completion events)'
)
if (-not $activateMatch.Success) {
    throw "The SPURS workload activation function was not found."
}

$reservationContract = @(
    'vm::reservation_op(spu,',
    'vm::unsafe_ptr_cast<spurs_wkl_state_op>(ctxt->spurs.ptr(&CellSpurs::wklState1))',
    '[&](spurs_wkl_state_op& op)'
)
foreach ($function in @($processMatch.Value, $activateMatch.Value, $completionMatch.Value)) {
    foreach ($required in $reservationContract) {
        if (-not $function.Contains($required)) {
            throw "A SPURS shutdown-state update is outside the shared reservation: $required"
        }
    }
}

foreach ($required in @(
    'op.sysSrvMsgUpdateWorkload &= ~(1 << ctxt->spuNum);',
    'std::memcpy(spu._ptr<void>(0x2D80), &op, sizeof(op));'
)) {
    if (-not $processMatch.Value.Contains($required)) {
        throw "The SPURS request update contract is missing '$required'."
    }
}

foreach ($required in @(
    'op.wklStatus1[i] &= ~(1 << ctxt->spuNum);',
    'op.wklState1[i] = SPURS_WKL_STATE_REMOVABLE;',
    'std::memcpy(spu._ptr<void>(0x2D80), &op, sizeof(op));'
)) {
    if (-not $activateMatch.Value.Contains($required)) {
        throw "The SPURS atomic workload-removal contract is missing '$required'."
    }
}

$completion = $completionMatch.Value
foreach ($required in @(
    'op.wklEvent1[i] |= 0x01;',
    'op.wklEvent2[i] |= 0x01;',
    'std::memcpy(spu._ptr<void>(0x2D80), &op, sizeof(op));',
    'sys_spu_thread_send_event(spu, spuPort, 0, wklNotifyBitSet)'
)) {
    if (-not $completion.Contains($required)) {
        throw "The SPURS shutdown completion contract is missing '$required'."
    }
}

if ($completion.Contains('TODO: sys_spu_thread_send_event')) {
    throw "The SPURS shutdown completion event is still a TODO."
}

Write-Output "Thor SPURS shutdown completion contract passed."
