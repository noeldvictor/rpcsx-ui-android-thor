$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$translatorPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$translatorSource = Get-Content -LiteralPath $translatorPath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw

# Official RPCS3 7e436f9bf136ad00321a97c09fb371fbd4eafe6b lowers
# the low-half SPU multiply family to native AArch64 widening multiplies.
foreach ($fragment in @(
    'value_t<s32[4]> smull(T1 a, T2 b)',
    'llvm::Intrinsic::aarch64_neon_smull',
    'value_t<u32[4]> umull(T1 a, T2 b)',
    'llvm::Intrinsic::aarch64_neon_umull'
)) {
    if (-not $translatorSource.Contains($fragment)) {
        throw "Missing ARM64 widening-multiply helper fragment: $fragment"
    }
}

$requiredArm64Fragments = @(
    'set_vr(op.rt, smull(zshuffle(bitcast<s16[8]>(a), 0, 2, 4, 6), zshuffle(bitcast<s16[8]>(b), 0, 2, 4, 6)));',
    'set_vr(op.rt, smull(zshuffle(bitcast<s16[8]>(a), 0, 2, 4, 6), zshuffle(bitcast<s16[8]>(b), 0, 2, 4, 6)) >> 16);',
    'set_vr(op.rt, umull(zshuffle(bitcast<u16[8]>(a), 0, 2, 4, 6), zshuffle(bitcast<u16[8]>(b), 0, 2, 4, 6)));',
    'set_vr(op.rt, smull(zshuffle(bitcast<s16[8]>(get_vr<s32[4]>(op.ra)), 0, 2, 4, 6), get_imm<s16[4]>(op.si10)));',
    'set_vr(op.rt, umull(zshuffle(bitcast<u16[8]>(get_vr<u32[4]>(op.ra)), 0, 2, 4, 6), get_imm<u16[4]>(op.si10)));',
    'set_vr(op.rt4, smull(zshuffle(bitcast<s16[8]>(a), 0, 2, 4, 6), zshuffle(bitcast<s16[8]>(b), 0, 2, 4, 6)) + get_vr<s32[4]>(op.rc));'
)

foreach ($fragment in $requiredArm64Fragments) {
    if (-not $spuSource.Contains($fragment)) {
        throw "Missing native ARM64 SPU multiply lowering: $fragment"
    }
}

$requiredFallbackFragments = @(
    'set_vr(op.rt, (get_vr<s32[4]>(op.ra) << 16 >> 16) * (get_vr<s32[4]>(op.rb) << 16 >> 16));',
    'set_vr(op.rt, mpyu(get_vr(op.ra), get_vr(op.rb)));',
    'set_vr(op.rt, (get_vr<s32[4]>(op.ra) << 16 >> 16) * get_imm<s32[4]>(op.si10));',
    'set_vr(op.rt, (get_vr(op.ra) << 16 >> 16) * (get_imm(op.si10) & 0xffff));',
    'set_vr(op.rt4, (get_vr<s32[4]>(op.ra) << 16 >> 16) * (get_vr<s32[4]>(op.rb) << 16 >> 16) + get_vr<s32[4]>(op.rc));'
)

foreach ($fragment in $requiredFallbackFragments) {
    if (-not $spuSource.Contains($fragment)) {
        throw "Non-ARM64 SPU multiply fallback was lost: $fragment"
    }
}

foreach ($opcode in @('MPY', 'MPYS', 'MPYU', 'MPYI', 'MPYUI', 'MPYA')) {
    $guardPattern = "(?s)void $opcode\(spu_opcode_t op\)\s*\{\s*#ifdef ARCH_ARM64.*?#else.*?#endif\s*\}"
    if (-not [regex]::IsMatch($spuSource, $guardPattern)) {
        throw "SPU $opcode no longer keeps its native lowering inside ARCH_ARM64 with a generic fallback."
    }
}

Write-Output "Thor ARM64 SPU multiply contract passed: MPY/MPYS/MPYU/MPYI/MPYUI/MPYA use SMULL/UMULL while generic fallbacks remain."
