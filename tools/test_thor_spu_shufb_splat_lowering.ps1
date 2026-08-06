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

# TBL2/TBX2 are no longer parked here. They were ported on 2026-08-05 together
# with the register-scavenger retry, and the SPU block compiler is the owner of
# that retry. The contract is therefore not "never emit them" but "never emit
# them without a retry owner", so assert the owner still exists.
if ($armBlock.Contains('tbl2(') -or $armBlock.Contains('tbx2(')) {
    $translatorPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.h"
    $translator = Get-Content -LiteralPath $translatorPath -Raw
    if (-not $translator.Contains('bool m_use_tbl2 = true;')) {
        throw "SHUFB emits TBL2/TBX2 but the m_use_tbl2 gate is gone."
    }

    $commonPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
    $common = Get-Content -LiteralPath $commonPath -Raw
    if (-not $common.Contains('compile_spu_llvm_with_retry')) {
        throw "SHUFB emits TBL2/TBX2 but the SPU block compiler lost its scavenger retry."
    }
    if (-not $common.Contains('Cannot scavenge register without an emergency spill slot')) {
        throw "SHUFB emits TBL2/TBX2 but the retry no longer matches the scavenger error."
    }

    $spuBuilder = [regex]::Match($spuSource, '(?s)m_use_tbl2 = [^;]+;')
    if (-not $spuBuilder.Success) {
        throw "SHUFB emits TBL2/TBX2 but nothing clears m_use_tbl2 on retry."
    }
}

Write-Output "Thor ARM64 SPU SHUFB contract passed: two constant splats use SELECT/TBL, and TBL2/TBX2 keep their scavenger retry owner."
