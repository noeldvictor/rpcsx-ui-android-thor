$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spursPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$spuThreadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"
$spursSource = Get-Content -LiteralPath $spursPath -Raw
$spuThreadSource = Get-Content -LiteralPath $spuThreadPath -Raw

$helperMatch = [regex]::Match(
    $spursSource,
    '(?m)^static void spursReturnFromSelectorHle\([\s\S]*?(?=^static bool thor_hle_once)'
)
if (-not $helperMatch.Success) {
    throw "The selector HLE return helper was not found."
}

$helper = $helperMatch.Value
foreach ($required in @(
    'if (spu.pc == ctxt->selectWorkloadAddr)',
    'spu.pc = spu.gpr[0]._u32[3];'
)) {
    if (-not $helper.Contains($required)) {
        throw "The selector HLE return helper is missing '$required'."
    }
}

$returnCall = 'spursReturnFromSelectorHle(spu, ctxt);'
$returnCallCount = [regex]::Matches($spursSource, [regex]::Escape($returnCall)).Count
if ($returnCallCount -ne 2) {
    throw "Expected both SPURS selectors to return through the HLE helper. Found $returnCallCount calls."
}

$runnerMatch = [regex]::Match(
    $spuThreadSource,
    '(?m)^bool spu_thread::RunHleFunction\(\)[\s\S]*?(?=^void spu_thread::cpu_task\(\))'
)
if (-not $runnerMatch.Success -or
    -not $runnerMatch.Value.Contains('found->second(*this);') -or
    -not $runnerMatch.Value.Contains('return true;')) {
    throw "The SPU HLE runner contract changed. Recheck selector PC handling."
}

Write-Output "Thor SPURS selector HLE return contract passed."
