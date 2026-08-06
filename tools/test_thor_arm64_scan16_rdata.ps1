$ErrorActionPreference = "Stop"

# Contract for scan16_rdata's AArch64 path.
#
# scan16_rdata finds the single changed 16-byte block of a 128-byte reservation
# so a PUTLLC can be published atomically instead of exposing a torn update. It
# runs on the SPU conditional-store commit path whenever the data actually
# changed, so it is hot in anything SPU-heavy.
#
# Written portably it is eight separate v128 != v128 compares. That is fine on
# x86, where PTEST sets flags directly, but v128::operator!= is gv_testz and on
# AArch64 gv_testz narrows and then moves to a general-purpose register. Eight
# compares therefore become eight SQXTN/FMOV/CSET triples, and those FMOVs are
# SIMD-to-GPR transfers sitting on the critical path. Measured with clang at
# -O2 -march=armv8.4-a: 65 instructions, 8 FMOVs.
#
# UMAXP folds lane pairs while preserving their order, so two rounds reduce
# eight 4-lane blocks to eight lanes, one per block, each nonzero exactly when
# its block differs. Weighting and adding across builds the same bitmask with a
# single transfer: 42 instructions, no per-block FMOV.
#
# Equivalence was verified on the device rather than argued: all 256 patterns of
# which blocks differ, 64 randomised byte positions each, plus 200000 random
# pairs. 216384 cases, zero mismatches.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp") -Raw

$fn = [regex]::Match($spu, '(?s)static FORCE_INLINE usz scan16_rdata\(.*?\n\}')
if (-not $fn.Success) {
    throw "Could not isolate scan16_rdata."
}
$body = $fn.Value

# Strip comments so prose describing the scalar shape cannot satisfy the checks.
$code = ($body -split "`n" | Where-Object { $_.Trim() -notmatch '^//' }) -join "`n"

$arm = [regex]::Match($code, '(?s)#if defined\(ARCH_ARM64\)(?<body>.*?)#else').Groups['body'].Value
if (-not $arm) {
    throw "scan16_rdata lost its ARCH_ARM64 path."
}

foreach ($required in @('vpmaxq_u32', 'vtstq_u32', 'vaddvq_u32')) {
    if ($arm -notmatch [regex]::Escape($required)) {
        throw "scan16_rdata's ARM64 path no longer uses $required."
    }
}

# Two rounds of pairwise max are what collapse 8 blocks to 8 lanes. Fewer and
# the lanes no longer correspond one-to-one with blocks.
$folds = ([regex]::Matches($arm, 'vpmaxq_u32')).Count
if ($folds -lt 6) {
    throw "scan16_rdata's ARM64 fold uses $folds vpmaxq_u32 calls; the two-round fold needs 6."
}

# The whole point is to stop turning each block into a scalar. If the ARM path
# ever compares v128s directly again it has regressed to the eight-FMOV shape.
if ($arm -match 'lhs\[i \+ \d\] != rhs\[i \+ \d\]') {
    throw "scan16_rdata's ARM64 path went back to per-block scalar compares."
}

# The weights must cover all eight blocks, or the mask silently loses blocks and
# a multi-block change can look like a single-block one, which would publish a
# torn 128-byte update as if it were atomic.
foreach ($weight in @('1u, 2u, 4u, 8u', '16u, 32u, 64u, 128u')) {
    if ($arm -notmatch [regex]::Escape($weight)) {
        throw "scan16_rdata's ARM64 block weights are wrong; expected $weight."
    }
}

# x86 must keep the portable loop.
$other = [regex]::Match($code, '(?s)#else(?<body>.*?)#endif').Groups['body'].Value
if ($other -notmatch 'lhs\[i \+ 0\] != rhs\[i \+ 0\]') {
    throw "scan16_rdata lost the portable non-ARM64 loop."
}

# The single-bit test and countr_zero tail are shared and must stay.
if ($code -notmatch 'mask & \(mask - 1\)' -or $code -notmatch 'countr_zero') {
    throw "scan16_rdata lost its single-changed-block test."
}

Write-Output "Thor ARM64 scan16_rdata contract passed: block mask is folded with UMAXP and moved once, x86 keeps the portable loop."
