$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spursPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$spuThreadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"
$spursSource = Get-Content -LiteralPath $spursPath -Raw
$spuThreadSource = Get-Content -LiteralPath $spuThreadPath -Raw

$helperMatch = [regex]::Match(
    $spursSource,
    '(?m)^static void spursDispatchFromSelectorHle\([\s\S]*?(?=^static bool thor_hle_once)'
)
if (-not $helperMatch.Success) {
    throw "The selector HLE dispatch helper was not found."
}

$helper = $helperMatch.Value
foreach ($required in @(
    'if (spu.pc == ctxt->selectWorkloadAddr)',
    'spursKernelDispatchWorkload(spu, result);'
)) {
    if (-not $helper.Contains($required)) {
        throw "The selector HLE dispatch helper is missing '$required'."
    }
}
if ($helper.Contains('spu.pc = spu.gpr[0]._u32[3];')) {
    throw "The HLE selector must not enter guest dispatch without its local-store DMA state."
}

$dispatchCall = 'spursDispatchFromSelectorHle(spu, ctxt, result);'
$dispatchCallCount = [regex]::Matches($spursSource, [regex]::Escape($dispatchCall)).Count
if ($dispatchCallCount -ne 2) {
    throw "Expected both SPURS selectors to use the HLE dispatcher. Found $dispatchCallCount calls."
}

$runnerMatch = [regex]::Match(
    $spuThreadSource,
    '(?m)^bool spu_thread::RunHleFunction\(\)[\s\S]*?(?=^void spu_thread::cpu_task\(\))'
)
if (-not $runnerMatch.Success -or
    -not $runnerMatch.Value.Contains('found->second(*this);') -or
    -not $runnerMatch.Value.Contains('return true;')) {
    throw "The SPU HLE runner contract changed. Recheck selector dispatch handling."
}

Write-Output "Thor SPURS selector HLE dispatch contract passed."
