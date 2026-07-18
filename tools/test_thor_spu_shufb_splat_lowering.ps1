$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$match = [regex]::Match($spuSource, '(?s)void SHUFB\(spu_opcode_t op\).*?(?=\s+void MPYA\(spu_opcode_t op\))')

if (-not $match.Success) {
    throw "Could not isolate the SPU SHUFB lowering."
}

$shufb = $match.Value
$requiredFragments = @(
    'const auto [a_is_const, a_data] = get_const_vector(a.value, m_pos);',
    'const auto [b_is_const, b_data] = get_const_vector(b.value, m_pos);',
    'if (a_is_splat && b_is_splat)',
    'set_vr(op.rt4, select_by_bit4(c, a, b));',
    'const auto splat_lut = build<u8[16]>',
    'set_vr(op.rt4, tbl(splat_lut, (c >> 4)));'
)

foreach ($fragment in $requiredFragments) {
    if (-not $shufb.Contains($fragment)) {
        throw "Missing ARM64 two-splat SHUFB lowering fragment: $fragment"
    }
}

$armStart = $shufb.IndexOf('#ifdef ARCH_ARM64')
$armEnd = $shufb.IndexOf('#endif', $armStart)
if ($armStart -lt 0 -or $armEnd -lt 0) {
    throw "The two-splat SHUFB lowering is no longer guarded by ARCH_ARM64."
}

$armBlock = $shufb.Substring($armStart, $armEnd - $armStart)
foreach ($fragment in $requiredFragments) {
    if (-not $armBlock.Contains($fragment)) {
        throw "ARM64 guard no longer contains two-splat SHUFB fragment: $fragment"
    }
}

foreach ($unsafeHelper in @('tbl2(', 'tbx2(')) {
    if ($armBlock.Contains($unsafeHelper)) {
        throw "Thor SHUFB lowering unexpectedly enables the parked $unsafeHelper path."
    }
}

Write-Output "Thor ARM64 SPU SHUFB contract passed: two constant splats use SELECT/TBL while TBL2/TBX2 stays parked."
