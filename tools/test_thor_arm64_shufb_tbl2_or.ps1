$ErrorActionPreference = "Stop"

# Contract for the SHUFB fallback replacement.
#
# The SHUFB path that is not perm_only emits, for a selector that may hold the
# constant-generating bytes:
#
#     x = tbl(zero_lut, c >> 4)        the 0x00 / 0xff / 0x80 constants
#     r = tbx2(x, a, b, idx)           out-of-range lanes keep x
#
# Measured on the device 2026-08-13: TBX2 costs 0.377 ns against TBL2's 0.178 on
# the A715 and the A710, which are the cores the SPU threads run on. `shufb` is
# the most common operation in the compiled corpus, at 5,794.
#
# `zero_lut` is twelve zero bytes then ff, ff, 80, 80, so x is zero exactly where
# the selector is in range, and TBL2 writes zero exactly where the index is out
# of range. Those two facts are complementary and they are what makes
#
#     r = tbl2(a, b, idx) | x
#
# equivalent. **This test pins the facts the equivalence rests on**, because the
# replacement silently becomes wrong if either one changes. A future edit to
# zero_lut is the realistic way that happens.

$repoRoot = Split-Path -Parent $PSScriptRoot
$rel = "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$path = Join-Path $repoRoot $rel
if (-not (Test-Path $path)) {
    throw "$rel does not exist, so scanning it proves nothing."
}

$raw = Get-Content -LiteralPath $path -Raw
$code = ($raw -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"

# 1. The constants table must stay zero for every in-range selector.
#
# The lut is indexed by (c >> 4). An index below 12 means c < 0xc0, and the SPU
# selector's constant-generating bytes are >= 0xc0, so the first twelve entries
# are exactly the in-range half and they must all be zero.
if ($code -notmatch 'zero_lut\s*=\s*build<u8\[16\]>\(([^)]*)\)') {
    throw "zero_lut is gone or no longer built with build<u8[16]>; the equivalence rests on its contents."
}

$lutText = $matches[1]
$lut = @($lutText -split ',' | ForEach-Object { $_.Trim() })
if ($lut.Count -ne 16) {
    throw "zero_lut has $($lut.Count) entries, expected 16."
}

for ($i = 0; $i -lt 12; $i++) {
    if ($lut[$i] -notmatch '^0x0+$|^0$') {
        throw "zero_lut[$i] is '$($lut[$i])', not zero. An in-range selector would then OR a nonzero constant into the result and the TBL2 replacement becomes wrong."
    }
}
if ($lut[12] -notmatch '0xff' -or $lut[13] -notmatch '0xff' -or $lut[14] -notmatch '0x80' -or $lut[15] -notmatch '0x80') {
    throw "zero_lut's constant half changed: got $($lut[12..15] -join ', '). The SPU constant-generating bytes are 0xff and 0x80."
}

# 2. Both fallback sites must offer the replacement, and both must keep TBX2 for
#    the default path. A site that lost its gate would silently ship untested
#    codegen; a site that lost its TBX2 would ship it unconditionally.
$gated = ([regex]::Matches($code, 'm_thor_shufb_tbl2_or')).Count
if ($gated -lt 3) {
    throw "Expected the gate member plus both SHUFB fallback sites to read it; found $gated references."
}

$orForms = ([regex]::Matches($code, 'tbl2\([^;]*\)\s*\|\s*x')).Count
if ($orForms -lt 2) {
    throw "Expected both fallback sites to offer 'tbl2(...) | x'; found $orForms."
}

$tbx2Forms = ([regex]::Matches($code, 'tbx2\(x,')).Count
if ($tbx2Forms -lt 2) {
    throw "Expected both fallback sites to keep tbx2(x, ...) as the default; found $tbx2Forms."
}

# 3. The gate must default to off. The equivalence is proved; the speed is not.
$header = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/thor_shufb_tbl2_or.h"
if (-not (Test-Path $header)) { throw "missing thor_shufb_tbl2_or.h" }
$h = Get-Content -LiteralPath $header -Raw
if ($h -notmatch 'return\s+false;') {
    throw "thor_shufb_tbl2_or.h no longer returns false when the property is unset. Trading TBX2 for TBL2 plus an ORR is unmeasured; it must not become the default without the bench numbers."
}

Write-Output "Thor SHUFB TBL2-or contract passed: zero_lut is zero across all twelve in-range indices and 0xff/0x80 above them, both fallback sites carry the gate and keep TBX2 as the default, and the gate is off unless the property is set."
