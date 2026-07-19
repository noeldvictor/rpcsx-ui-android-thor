$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$headerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPURecompiler.h"
$llvmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"

foreach ($path in @($headerPath, $llvmPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU Reduced Loop dependency: $path"
    }
}

$header = Get-Content -LiteralPath $headerPath -Raw
$llvm = Get-Content -LiteralPath $llvmPath -Raw

$arm64HintGate = '(?s)bool is_gpr_not_NaN_hint\(u32 i\) const noexcept.*?#ifdef ARCH_X64.*?gpr_not_nans\.test\(i\).*?#else.*?return false;.*?#endif'
if ($header -notmatch $arm64HintGate) {
    throw "ARM64 Reduced Loop must not reuse the x64-only not-NaN analysis hint."
}

foreach ($fragment in @(
    '// Check spu_thread::state before continuing the optimized loop.',
    'spu_ptr<u32>(OFFSET_OF(spu_thread, state))',
    'spu_context_attr(m_ir->CreateLoad(get_type<u32>()',
    'm_ir->CreateICmpEQ(',
    'm_ir->getInt32(0)), condition)'
)) {
    if (-not $llvm.Contains($fragment)) {
        throw "SPU Reduced Loop is missing its state-stop contract: $fragment"
    }
}

Write-Output "Thor SPU Reduced Loop upstream contract passed: ARM64 NaN hints are disabled and optimized loops observe thread stop state."
