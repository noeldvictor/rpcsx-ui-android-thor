$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$threadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"
$headerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h"
$failedSetPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUFailedBlocks.h"

$common = Get-Content -LiteralPath $commonPath -Raw
$thread = Get-Content -LiteralPath $threadPath -Raw
$header = Get-Content -LiteralPath $headerPath -Raw
$failedSet = Get-Content -LiteralPath $failedSetPath -Raw

foreach ($required in @(
    '#include "SPUFailedBlocks.h"',
    'spu_mark_block_compile_failed(entry_point);',
    'if (program.data.empty())',
    'spu_run_interp_fallback(spu);',
    'spu_recompiler_base::old_interpreter(spu, spu._ptr<u8>(0), nullptr);',
    'spu_runtime::g_escape(&spu);'
)) {
    if (-not $common.Contains($required)) {
        throw "The SPU failed-analysis fallback is missing: $required"
    }
}

if (-not $common.Contains('spu.pc < spu.interp_fallback_begin || spu.pc >= spu.interp_fallback_end')) {
    throw "The interpreter must stop when it leaves the failed range."
}

foreach ($required in @('bool interp_fallback = false;', 'u32 interp_fallback_begin = 0;', 'u32 interp_fallback_end = 0;')) {
    if (-not $header.Contains($required)) {
        throw "The SPU thread fallback state is missing: $required"
    }
}

$gatewayMatch = [regex]::Match(
    $thread,
    '(?m)interp_fallback = false;\s*allow_interrupts_in_cpu_work = false;\s*spu_runtime::g_gateway'
)

if (-not $gatewayMatch.Success) {
    throw "The SPU loop must clear fallback state before the next JIT gateway call."
}

foreach ($required in @('class spu_failed_block_set', 'while (it != m_map.end() && it->first <= end)', 'm_map.emplace(begin, end);')) {
    if (-not $failedSet.Contains($required)) {
        throw "The failed-range set does not merge overlapping ranges: $required"
    }
}

Write-Output "Thor SPU failed-analysis fallback test passed."
