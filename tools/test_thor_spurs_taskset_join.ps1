$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$joinMatch = [regex]::Match(
    $source,
    '(?m)^s32 cellSpursJoinTaskset\([\s\S]*?(?=^s32 cellSpursGetTasksetId\()'
)
if (-not $joinMatch.Success) {
    throw "The SPURS taskset join function was not found."
}

$join = $joinMatch.Value
foreach ($required in @(
    's32 cellSpursJoinTaskset(ppu_thread& ppu, vm::ptr<CellSpursTaskset> taskset)',
    'return CELL_SPURS_TASK_ERROR_NULL_POINTER;',
    'return CELL_SPURS_TASK_ERROR_ALIGN;',
    'if (wid >= CELL_SPURS_MAX_WORKLOAD2)',
    'const auto spurs = +taskset->spurs;',
    'case CELL_SPURS_POLICY_MODULE_ERROR_INVAL: return CELL_SPURS_TASK_ERROR_INVAL;',
    'case CELL_SPURS_POLICY_MODULE_ERROR_STAT: return CELL_SPURS_TASK_ERROR_STAT;',
    'ppu_execute<&cellSpursWaitForWorkloadShutdown>(ppu, spurs, wid)',
    'ppu_execute<&cellSpursRemoveWorkload>(ppu, spurs, wid)',
    'taskset->wid = CELL_SPURS_MAX_WORKLOAD2;'
)) {
    if (-not $join.Contains($required)) {
        throw "The SPURS taskset join contract is missing '$required'."
    }
}

$waitIndex = $join.IndexOf('ppu_execute<&cellSpursWaitForWorkloadShutdown>')
$removeIndex = $join.IndexOf('ppu_execute<&cellSpursRemoveWorkload>')
$invalidateIndex = $join.IndexOf('taskset->wid = CELL_SPURS_MAX_WORKLOAD2;')
if ($waitIndex -lt 0 -or $removeIndex -le $waitIndex -or $invalidateIndex -le $removeIndex) {
    throw "The taskset join lifecycle is not wait, remove, and invalidate."
}

foreach ($forbidden in @('UNIMPLEMENTED_FUNC(cellSpurs)')) {
    if ($join.Contains($forbidden)) {
        throw "The SPURS taskset join contains the forbidden fragment '$forbidden'."
    }
}

Write-Output "Thor SPURS taskset join contract passed."
