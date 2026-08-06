$ErrorActionPreference = "Stop"

# Contract for PPU float-to-integer conversion on AArch64.
#
# FCTIW, FCTIWZ, FCTID and FCTIDZ all applied the same correction on both
# architectures:
#
#   xormask = sext(b >= 2^31)          // or 2^63
#   result  = xormask ^ convert(b)
#
# That is right for x86, where CVTSD2SI returns 0x80000000 on overflow and the
# XOR turns it into the PowerPC 0x7fffffff. AArch64's FCVTNS/FCVTZS saturate to
# 0x7fffffff already, so the same XOR produced 0x80000000: the wrong value, for
# every float at or above the limit, on four of the PPU's conversion
# instructions. Same species as the SPU CFLTS bug.
#
# AArch64 disagrees with PowerPC on exactly one case after that, NaN, which
# converts to 0 rather than the minimum, so the ARM path selects it explicitly.

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUTranslator.cpp") -Raw

$cases = @(
    @{ Name = 'FCTIW';  Intrinsic = 'fcvtns.i32.f64'; Min = "m_ir->getInt32(0x8000'0000u)" },
    @{ Name = 'FCTIWZ'; Intrinsic = 'fcvtzs.i32.f64'; Min = "m_ir->getInt32(0x8000'0000u)" },
    @{ Name = 'FCTID';  Intrinsic = 'fcvtns.i64.f64'; Min = "m_ir->getInt64(0x8000'0000'0000'0000ull)" },
    @{ Name = 'FCTIDZ'; Intrinsic = 'fcvtzs.i64.f64'; Min = "m_ir->getInt64(0x8000'0000'0000'0000ull)" }
)

foreach ($case in $cases) {
    $name = $case.Name
    $match = [regex]::Match($ppu, "(?s)void PPUTranslator::$name\(ppu_opcode_t op\)\s*\{.*?\n\}")
    if (-not $match.Success) {
        throw "Could not isolate PPUTranslator::$name."
    }

    $body = $match.Value
    $arm = [regex]::Match($body, '(?s)#elif defined\(ARCH_ARM64\)(.*?)#endif').Groups[1].Value
    if (-not $arm) {
        throw "$name has no ARCH_ARM64 branch."
    }

    if ($arm -match 'CreateXor') {
        throw "$name still applies the x86 saturation correction on ARM64, which inverts a correct result."
    }
    if ($arm -notmatch [regex]::Escape($case.Intrinsic)) {
        throw "$name no longer uses the saturating $($case.Intrinsic) conversion on ARM64."
    }
    if ($arm -notmatch 'CreateFCmpUNO') {
        throw "$name does not fix up NaN on ARM64, where the conversion yields 0 instead of the minimum."
    }
    if ($arm -notmatch [regex]::Escape($case.Min)) {
        throw "$name does not select the PowerPC minimum for NaN on ARM64."
    }

    # x86 must keep the correction, and must still compute the mask it needs.
    $x86 = [regex]::Match($body, '(?s)#if defined\(ARCH_X64\)(.*?)#elif').Groups[1].Value
    if ($x86 -notmatch 'CreateXor' -or $x86 -notmatch 'xormask') {
        throw "$name lost the x86 overflow correction, which that architecture still needs."
    }
}

Write-Output "Thor ARM64 PPU float-convert contract passed: FCTIW/FCTIWZ/FCTID/FCTIDZ saturate in hardware, NaN fixed up, x86 correction retained off ARM64."
