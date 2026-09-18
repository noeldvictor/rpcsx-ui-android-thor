$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$dispatchMatch = [regex]::Match(
    $source,
    '(?m)^void spursTasksetDispatch\(spu_thread& spu\)[\s\S]*?(?=^s32 spursTasksetProcessSyscall)'
)
if (-not $dispatchMatch.Success) {
    throw "The SPURS taskset dispatcher was not found."
}

$dispatch = $dispatchMatch.Value
foreach ($required in @(
    'const v128 runningTasks = vm::_ref<v128>',
    'OFFSET_OF(CellSpursTaskset, running)',
    'rx::popcnt128(runningTasks._u)',
    '.atomic_op([runningTaskCount](u8& current)',
    'if (current > runningTaskCount)',
    'current--;',
    'kctxt->wklLocContention[held] = 0;',
    'thor_release_wkl(held, kctxt->spuNum);'
)) {
    if (-not $dispatch.Contains($required)) {
        throw "The idle taskset contention release is missing '$required'."
    }
}

$unconditionalRelease = [regex]::Match(
    $dispatch,
    'wklCurrentContention\) \+ held\)\s*\.atomic_op\(\[\]\(u8& (?:v|current)\) \{ if \((?:v|current)\) (?:v|current)--; \}\);'
)
if ($unconditionalRelease.Success) {
    throw "The idle taskset path can release active task contention."
}

Write-Output "Thor HLE SPURS idle contention contract passed."
