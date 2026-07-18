$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$translatorPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$translatorSource = Get-Content -LiteralPath $translatorPath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw

$requiredTranslatorFragments = @(
    'llvm::KnownFPClass get_known_fp_class',
    'llvm::computeKnownFPClass(a.eval(m_ir), m_module->getDataLayout(), interested_classes',
    'llvm::MaxAnalysisRecursionDepth - depth'
)

foreach ($fragment in $requiredTranslatorFragments) {
    if (-not $translatorSource.Contains($fragment)) {
        throw "Missing LLVM known floating-point class helper fragment: $fragment"
    }
}

$requiredSpuFragments = @(
    'spu_zero_fp_classes = llvm::FPClassTest::fcSubnormal | llvm::FPClassTest::fcZero',
    'clamp_positive_smax(value_t<f32[4]> v, std::optional<llvm::KnownFPClass>',
    'clamp_negative_smax(value_t<f32[4]> v, std::optional<llvm::KnownFPClass>',
    'clamp_smax(value_t<f32[4]> v, std::optional<llvm::KnownFPClass>',
    'known.isKnownNever(overflow_classes)',
    'a_known.isKnownNeverNaN() && b_known.isKnownNeverNaN()',
    'a_known.isKnownNever(spu_zero_fp_classes) && b_known.isKnownNever(spu_zero_fp_classes)',
    'c_known.isKnownAlways(spu_zero_fp_classes)',
    'a_known.isKnownAlways(spu_zero_fp_classes) || b_known.isKnownAlways(spu_zero_fp_classes)',
    'a_known.fneg()',
    'fma32x4(a_clamp, b_clamp, eval(-c), a_known, b_known)'
)

foreach ($fragment in $requiredSpuFragments) {
    if (-not $spuSource.Contains($fragment)) {
        throw "Missing SPU known floating-point class optimization fragment: $fragment"
    }
}

$knownQueryCount = [regex]::Matches($spuSource, [regex]::Escape('get_known_fp_class<')).Count
$knownFmaCount = [regex]::Matches($spuSource, [regex]::Escape('fma32x4(')).Count
if ($knownQueryCount -lt 15) {
    throw "Expected at least 15 SPU KnownFPClass queries across clamp, multiply, compare, and FMA paths; found $knownQueryCount."
}

if ($knownFmaCount -lt 11) {
    throw "Expected KnownFPClass-aware FMA propagation across all SPU FMA variants; found only $knownFmaCount fma32x4 definitions/call sites."
}

if ($spuSource.Contains('is_spu_float_zero(')) {
    throw "Legacy constant-only SPU zero classifier remains active instead of LLVM KnownFPClass analysis."
}

Write-Output "Thor SPU KnownFPClass contract passed: clamps, multiply/equality masks, and FMA zero/NaN paths use LLVM value analysis."
