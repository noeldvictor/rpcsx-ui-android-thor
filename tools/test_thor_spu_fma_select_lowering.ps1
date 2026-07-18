$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$spuSource = Get-Content -LiteralPath $spuPath -Raw

$start = $spuSource.IndexOf('register_intrinsic("spu_fma"')
$end = $spuSource.IndexOf('if (m_use_avx512)', $start)
if ($start -lt 0 -or $end -le $start) {
    throw "Unable to isolate the SPU FMA intrinsic lowering."
}

$fmaSource = $spuSource.Substring($start, $end - $start)
$requiredFragments = @(
    'const auto normal_fma = fma32x4(a, b, c, a_known, b_known);',
    'return eval(select(fcmp_uno(a != fsplat<f32[4]>(0.)), normal_fma, c));',
    'return eval(select(fcmp_uno(b != fsplat<f32[4]>(0.)), normal_fma, c));',
    'const auto a_cmp = fcmp_uno(a != fsplat<f32[4]>(0.));',
    'const auto b_cmp = fcmp_uno(b != fsplat<f32[4]>(0.));',
    'return eval(select(a_cmp & b_cmp, normal_fma, c));'
)

foreach ($fragment in $requiredFragments) {
    if (-not $fmaSource.Contains($fragment)) {
        throw "Missing shortened SPU FMA dependency-chain fragment: $fragment"
    }
}

$normalFmaCount = [regex]::Matches($fmaSource, [regex]::Escape('const auto normal_fma = fma32x4(a, b, c, a_known, b_known);')).Count
if ($normalFmaCount -ne 3) {
    throw "Expected three shortened SPU FMA select paths; found $normalFmaCount."
}

$legacyFragments = @(
    'const auto ma = sext<s32[4]>(fcmp_uno(a != fsplat<f32[4]>(0.)));',
    'const auto mb = sext<s32[4]>(fcmp_uno(b != fsplat<f32[4]>(0.)));',
    'bitcast<s32[4]>(b) & ma',
    'bitcast<s32[4]>(a) & mb'
)

foreach ($fragment in $legacyFragments) {
    if ($fmaSource.Contains($fragment)) {
        throw "Legacy mask-before-FMA dependency remains: $fragment"
    }
}

Write-Output "Thor SPU FMA select-lowering contract passed: approximate xfloat FMA selects the normal result or addend without masking a multiplicand first."
