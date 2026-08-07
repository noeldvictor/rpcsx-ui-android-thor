$ErrorActionPreference = "Stop"

# Contract: AltiVec 32-bit saturating adds use add_sat, not a hand-rolled one.
#
# x86 SSE saturates at 8 and 16 bits only. There is no 32-bit packed saturating
# add, so upstream writes it out: compute the exact sum, derive the limit from
# the sign of the addend, detect overflow from the sign relationship, then
# select between them branch-free.
#
# AArch64 has SQADD on 4x32 and llvm.sadd.sat lowers straight to it. Measured on
# identical IR at -O2 -mcpu=cortex-a78:
#
#   hand-rolled, value + SAT mask   12 instructions
#   add_sat,     value + SAT mask    5
#   add_sat,     value only          2
#
# The last row is the interesting one. set_sat only emits anything when the
# module reads VSCR (ppu_attr::has_mfvscr), so modules that never do collapse to
# a single SQADD. The hand-rolled form could never benefit from that, because it
# needed the overflow mask to select the result and so paid for it always.
#
# VADDSWS and VSUBSWS already did this. VMSUMSHS did not, which is what made it
# findable: an op whose siblings use the helper it should have used.
#
# Equivalence was verified on device rather than argued: all pairs of 13 edge
# values plus 3,000,000 randomised pairs, comparing both the result and whether
# the SAT flag fires. 3,000,169 cases, zero mismatches.

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUTranslator.cpp") -Raw

function Get-Func([string]$name) {
    $m = [regex]::Match($ppu, "(?s)void PPUTranslator::$name\(ppu_opcode_t op\)\s*\{.*?\n\}")
    if (-not $m.Success) { throw "Could not isolate PPUTranslator::$name." }
    # Strip comments: they describe the x86 form being replaced.
    return (($m.Value -split "`n" | Where-Object { $_.Trim() -notmatch '^//' }) -join "`n")
}

# The three 32-bit saturating AltiVec adds must all go through the helper.
foreach ($fn in @('VADDSWS', 'VMSUMSHS')) {
    $body = Get-Func $fn
    if ($body -notmatch 'add_sat\(') {
        throw "$fn no longer uses add_sat, so it cannot reach SQADD on AArch64."
    }
}

$sub = Get-Func 'VSUBSWS'
if ($sub -notmatch 'sub_sat\(') {
    throw "VSUBSWS no longer uses sub_sat."
}

# VMSUMSHS specifically must not have regrown the hand-rolled form. The tell is
# the saturation limit being derived from the sign of the addend.
$vmsum = Get-Func 'VMSUMSHS'
if ($vmsum -match '0x7fffffff') {
    throw "VMSUMSHS reintroduced a hand-derived saturation limit; it should let add_sat do it."
}
if ($vmsum -match '>> 31') {
    throw "VMSUMSHS reintroduced sign-based overflow detection; add_sat already saturates."
}

# The SAT flag must still be reported, and by the same idiom as its siblings:
# the XOR of saturated and exact results is nonzero exactly when it saturated.
if ($vmsum -notmatch 'set_sat\(') {
    throw "VMSUMSHS stopped reporting saturation to VSCR."
}
if ($vmsum -notmatch 'set_sat\(r \^ \(mx \+ c\)\)') {
    throw "VMSUMSHS no longer derives the SAT flag as saturated XOR exact, which is what lets it vanish when the module never reads VSCR."
}

# The intermediate fixup is a separate concern and must survive: it maps a
# product sum of 0x80000000 to 0x7fffffff before the saturating add.
if ($vmsum -notmatch 'm == 0x80000000u') {
    throw "VMSUMSHS lost the intermediate product-sum fixup."
}

Write-Output "Thor ARM64 PPU saturating-add contract passed: VADDSWS, VSUBSWS and VMSUMSHS all use the saturating helpers, and VMSUMSHS keeps its intermediate fixup and XOR-derived SAT."
