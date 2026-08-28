$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredFragments = @(
    'debug.rpcsx.thor.taskset_select_atomic',
    'return false;',
    'request == SPURS_TASKSET_REQUEST_SELECT_TASK && thor_taskset_select_atomic()',
    'vm::reservation_op(spu, vm::unsafe_ptr_cast<spurs_taskset_signal_op>(+ctxt->taskset)',
    'reinterpret_cast<v128&>(op.running[0]) = running;',
    'reinterpret_cast<v128&>(op.waiting[0]) = waiting;',
    'reinterpret_cast<v128&>(op.ready[0]) = ready0;',
    'reinterpret_cast<v128&>(op.pending_ready[0]) = v128{};',
    'reinterpret_cast<v128&>(op.signalled[0]) = signalled0;',
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

Write-Output "Thor taskset atomic selection contract passed."
