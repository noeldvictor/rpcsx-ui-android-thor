$ErrorActionPreference = "Stop"

# Contract for SPU float-to-integer conversion on AArch64.
#
# The shared lowering is written for x86, where CVTTPS2DQ returns 0x80000000 on
# overflow, so it XORs a correction in to turn that into 0x7fffffff. AArch64's
# FCVTZS saturates to 0x7fffffff by itself, so applying the same correction
# flipped a correct result into 0x80000000. That is a wrong value, not just a
# slow one, and it is still wrong upstream.
#
# The fix is to let the hardware saturate: llvm.fptosi.sat / llvm.fptoui.sat
# lower to a single FCVTZS / FCVTZU. This test pins both halves, because a
# revert on either side reintroduces either the bug or the redundant work.

$repoRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3"
$header = Get-Content -LiteralPath (Join-Path $corePath "Emu/CPU/CPUTranslator.h") -Raw
$spu = Get-Content -LiteralPath (Join-Path $corePath "Emu/Cell/SPULLVMRecompiler.cpp") -Raw

foreach ($helper in @('fptosi_sat', 'fptoui_sat')) {
    $match = [regex]::Match($header, "(?s)value_t<T> $helper\(U a\)\s*\{.*?\n\t\}")
    if (-not $match.Success) {
        throw "Could not isolate the $helper helper in CPUTranslator.h."
    }

    $intrinsic = $helper -replace '_', '.'
    if (-not $match.Value.Contains("llvm::Intrinsic::$helper")) {
        throw "$helper no longer emits llvm.$intrinsic."
    }
}

function Get-SpuOpcode([string]$name, [string]$next) {
    $m = [regex]::Match($spu, "(?s)void $name\(spu_opcode_t op\).*?(?=\s+void $next\(spu_opcode_t op\))")
    if (-not $m.Success) {
        throw "Could not isolate the SPU $name lowering."
    }
    return $m.Value
}

$cflts = Get-SpuOpcode 'CFLTS' 'CFLTU'
$cfltu = Get-SpuOpcode 'CFLTU' 'CSFLT'

# Both the accurate f64 path and the relaxed f32 path need the saturating form,
# so two call sites each.
$sCount = ([regex]::Matches($cflts, [regex]::Escape('fptosi_sat<s32[4]>(a)'))).Count
if ($sCount -lt 2) {
    throw "CFLTS should use the saturating conversion on both accuracy paths; found $sCount."
}

$uCount = ([regex]::Matches($cfltu, [regex]::Escape('fptoui_sat<s32[4]>(a)'))).Count
if ($uCount -lt 2) {
    throw "CFLTU should use the saturating conversion on both accuracy paths; found $uCount."
}

# The x86 correction must survive for x86, and must not be reachable on ARM64.
if (-not $cflts.Contains('#ifdef ARCH_ARM64')) {
    throw "CFLTS no longer guards the saturating path with ARCH_ARM64."
}
if (-not $cflts.Contains('r ^ sext<s32[4]>(bitcast<s32[4]>(a) > splat<s32[4]>(((31 + 127) << 23) - 1))')) {
    throw "CFLTS lost the x86 overflow correction, which non-ARM64 hosts still need."
}
if (-not $cfltu.Contains('r & ~(bitcast<s32[4]>(a) >> 31)')) {
    throw "CFLTU lost the x86 sign mask, which non-ARM64 hosts still need."
}

foreach ($guarded in @($cflts, $cfltu)) {
    foreach ($block in [regex]::Matches($guarded, '(?s)#ifdef ARCH_ARM64(.*?)#else')) {
        $arm = $block.Groups[1].Value
        if ($arm -match 'CreateFPToSI|CreateFPToUI') {
            throw "An ARM64 branch still uses the non-saturating conversion."
        }
    }
}

Write-Output "Thor ARM64 float-convert contract passed: saturating conversions on both CFLTS/CFLTU accuracy paths, x86 corrections retained off ARM64."
