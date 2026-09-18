$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$functionMatch = [regex]::Match(
    $source,
    '(?m)^void spursSysServiceActivateWorkload\(spu_thread& spu, SpursKernelContext\* ctxt\)[\s\S]*?^\}'
)

if (-not $functionMatch.Success) {
    throw "The SPURS workload activation function was not found."
}

$functionSource = $functionMatch.Value
$refresh = 'std::memcpy(spu._ptr<void>(0x100), ctxt->spurs.get_ptr(), 128);'
$staleWriteback = 'std::memcpy(ctxt->spurs.get_ptr(), spu._ptr<void>(0x100), 128);'

if (-not $functionSource.Contains($refresh)) {
    throw "The SPURS workload activation function must refresh its private first-line snapshot."
}

if ($functionSource.Contains($staleWriteback)) {
    throw "The SPURS workload activation function must not copy its private first-line snapshot to shared memory."
}

if (-not $functionSource.Contains('auto spurs = ctxt->spurs.get_ptr();')) {
    throw "The SPURS workload state updates must use the shared CellSpurs object."
}

Write-Output "Thor SPURS workload activation snapshot test passed."
