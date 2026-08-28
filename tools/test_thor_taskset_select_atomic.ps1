$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    'debug.rpcsx.thor.taskset_select_atomic',
    'return false;',
    'request == SPURS_TASKSET_REQUEST_SELECT_TASK && thor_taskset_select_atomic()',
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
    throw "Atomic taskset selection must stay off by default."
}

$atomicSelectMatch = [regex]::Match(
    $source,
    '(?m)^\s*if \(request == SPURS_TASKSET_REQUEST_SELECT_TASK && thor_taskset_select_atomic\(\)\)[\s\S]*?(?=^\s*// vm::reservation_op)'
)
if (-not $atomicSelectMatch.Success -or $atomicSelectMatch.Value.Contains('reinterpret_cast<v128&>(op.')) {
    throw "Atomic taskset selection must convert the big-endian bitmap before it uses a task ID."
}

Write-Output "Thor taskset atomic selection contract passed."
