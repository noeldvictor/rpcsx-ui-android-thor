$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    'debug.rpcsx.thor.taskset_select_atomic',
    'return false;',
    'if (thor_taskset_select_atomic())',
    'vm::reservation_op(spu, vm::unsafe_ptr_cast<spurs_taskset_signal_op>(+ctxt->taskset)',
    'be_t<v128> bitmap;',
    'const be_t<v128> stored = bitmap;',
    'v128 running = thor_load_task_bitmap(op.running);',
    'v128 enabled = thor_load_task_bitmap(op.enabled);',
    'thor_store_task_bitmap(op.running, running);',
    'thor_store_task_bitmap(op.waiting, waiting);',
    'thor_store_task_bitmap(op.ready, ready0);',
    'thor_store_task_bitmap(op.pending_ready, v128{});',
    'thor_store_task_bitmap(op.signalled, signalled0);',
    'std::memcpy(spu._ptr<void>(0x2700), &committed, sizeof(committed));',
    'Thor TASKSET SELECT ATOMIC'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "The atomic taskset selection contract is missing: $fragment"
    }
}

$propertyMatch = [regex]::Match(
    $source,
    '(?m)^static bool thor_taskset_select_atomic\(\) noexcept[\s\S]*?(?=^static bool thor_release_idle_taskset)'
)
if (-not $propertyMatch.Success -or -not $propertyMatch.Value.Contains('return false;')) {
    throw "Atomic taskset requests must stay off by default."
}

$atomicRequestMatch = [regex]::Match(
    $source,
    '(?m)^\s*if \(thor_taskset_select_atomic\(\)\)[\s\S]*?(?=^\s*// vm::reservation_op)'
)
if (-not $atomicRequestMatch.Success -or $atomicRequestMatch.Value.Contains('reinterpret_cast<v128&>(op.')) {
    throw "Atomic taskset requests must convert the big-endian bitmaps before they use a task ID."
}

$requestNames = @(
    'SPURS_TASKSET_REQUEST_POLL_SIGNAL',
    'SPURS_TASKSET_REQUEST_DESTROY_TASK',
    'SPURS_TASKSET_REQUEST_YIELD_TASK',
    'SPURS_TASKSET_REQUEST_WAIT_SIGNAL',
    'SPURS_TASKSET_REQUEST_POLL',
    'SPURS_TASKSET_REQUEST_WAIT_WKL_FLAG',
    'SPURS_TASKSET_REQUEST_SELECT_TASK',
    'SPURS_TASKSET_REQUEST_RECV_WKL_FLAG'
)

foreach ($requestName in $requestNames) {
    if (-not $atomicRequestMatch.Value.Contains("case ${requestName}:")) {
        throw "The atomic taskset request contract does not cover: $requestName"
    }
}

if ($source.Contains('request == SPURS_TASKSET_REQUEST_SELECT_TASK && thor_taskset_select_atomic()')) {
    throw "The firmware reservation contract must not be limited to SELECT_TASK."
}

Write-Output "Thor atomic taskset request contract passed."
