$ErrorActionPreference = "Stop"

# Contract: the 128-byte reservation comparison must stay a tree, not a chain.
#
# cmp_rdata answers one question - are these two 128-byte reservation blocks
# identical - and it runs on the GETLLAR retry path, so its latency is on the
# critical path of a spin.
#
# It has now been reviewed twice, and the first review reached the wrong answer
# for an instructive reason. The ARM path used to accumulate match counts
# serially: four dependent vmlaq_s16 steps into one register, then compare the
# total against 32. Compared against an XOR/OR tree it measured 29 instructions
# against 28, near enough to a tie that leaving working code alone was correct on
# the evidence available.
#
# The evidence was incomplete. Instruction count cannot see either of the two
# things that actually separate these shapes:
#
#   dependency depth   The accumulate is a real serial chain. Each SUB - what the
#                      multiply-accumulate strength-reduces to, since the
#                      operands are 0/-1 masks - waits on the previous, and the
#                      chain only starts after CMEQ and two ANDs. Roughly 14
#                      cycles before the reduction, against roughly 8 for a tree
#                      whose leaves are independent.
#
#   reduction width    Counting matches requires a 16-bit reduction, ADDV 8H, at
#                      latency 4. Testing for any difference at all can use the
#                      widest lanes available, UMAXV 4S, at latency 2, since lane
#                      boundaries do not matter to "is any bit set".
#
# Both figures come from the per-core optimization guides in docs/hardware/.
#
# This test exists because the serial form is the one that looks clever. Counting
# matches with a multiply-accumulate reads as the tighter idea, and reverting to
# it would be a plausible-looking change that quietly lengthens a hot dependency
# chain and widens the reduction, with no visible symptom.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuThread = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

if (-not (Test-Path $spuThread)) { throw "SPUThread.cpp not found at $spuThread" }
$source = Get-Content $spuThread -Raw

# 1. The serial accumulator must be gone.
#
# Match a *call*, with its opening parenthesis, not a bare mention. The first
# version of this test searched for the bare name and failed against the comment
# in SPUThread.cpp that explains why the serial form was replaced. A test that
# forbids a construct must not trip over the prose documenting why it is
# forbidden, or the only way to keep it passing is to stop writing the prose.
if ($source -match 'cmp16_pair_accum_arm64\s*\(') {
    throw "cmp16_pair_accum_arm64 is back. That is the serial multiply-accumulate chain: four dependent steps before a 16-bit ADDV, roughly 14 cycles of dependency where the tree needs 8."
}
if ($source -match 'vmlaq_s16\s*\(') {
    throw "vmlaq_s16 reappeared in the reservation comparison. Counting matches forces a 16-bit reduction (ADDV 8H, latency 4) where testing for any difference needs only UMAXV 4S at latency 2."
}

# 2. The tree helper must exist and be what cmp_rdata's ARM branch calls.
if ($source -notmatch 'cmp16_all_equal_arm64') {
    throw "cmp16_all_equal_arm64 is missing; the ARM reservation comparison has been changed or removed."
}

$cmpStart = $source.IndexOf("cmp_rdata(const spu_rdata_t& _lhs, const spu_rdata_t& _rhs)")
if ($cmpStart -lt 0) { throw "cmp_rdata definition not found; this test needs updating." }
# Bound to cmp_rdata's own body so a neighbouring function cannot satisfy this.
$tail = $source.Substring($cmpStart)
$cmpEnd = $tail.IndexOf("`n}")
if ($cmpEnd -lt 0) { throw "Could not find the end of cmp_rdata." }
$body = $tail.Substring(0, $cmpEnd)

if ($body -notmatch 'ARCH_ARM64') {
    throw "cmp_rdata has no ARCH_ARM64 branch."
}
if ($body -notmatch 'cmp16_all_equal_arm64') {
    throw "cmp_rdata's ARM64 branch does not call cmp16_all_equal_arm64."
}

# 3. The helper must keep the tree shape: four independent pairs combined
#    pairwise, rather than one accumulator threaded through every step.
$helperStart = $source.IndexOf("static FORCE_INLINE bool cmp16_all_equal_arm64")
if ($helperStart -lt 0) { throw "cmp16_all_equal_arm64 definition not found." }
$helperTail = $source.Substring($helperStart)
$helperEnd = $helperTail.IndexOf("`n}")
$helper = $helperTail.Substring(0, $helperEnd)

foreach ($pair in @('a', 'b', 'c', 'd')) {
    if ($helper -notmatch "uint8x16_t $pair = vorrq_u8\(ne\(") {
        throw "cmp16_all_equal_arm64 no longer builds independent pair '$pair'. The four leaf pairs must stay independent; that is the whole point of the shape."
    }
}
if ($helper -notmatch 'vorrq_u8\(a, b\)' -or $helper -notmatch 'vorrq_u8\(c, d\)') {
    throw "cmp16_all_equal_arm64 no longer combines its pairs as a balanced tree."
}

# 4. The reduction must stay 32-bit wide. UMAXV 4S is latency 2; the 8H and 16B
#    forms are latency 4, and 16B is half the throughput as well.
if ($helper -notmatch 'vmaxvq_u32') {
    throw "cmp16_all_equal_arm64 no longer reduces with vmaxvq_u32. The widest-lane reduction is the cheapest one that answers 'is any bit set'."
}
if ($helper -match 'vmaxvq_u8|vmaxvq_u16|vaddvq_') {
    throw "cmp16_all_equal_arm64 uses a narrower or additive reduction. UMAXV 4S at latency 2 is the correct form; 8H and 16B are latency 4."
}

# 5. The x86 path must be untouched.
if ($body -notmatch 'cmp_rdata_avx') {
    throw "The x86 path in cmp_rdata was modified. This change is ARM-only."
}

# 6. The guides the reasoning rests on must still be present.
foreach ($guide in @(
    "docs/hardware/arm_cortex_x3_software_optimization_guide.pdf",
    "docs/hardware/arm_cortex_a710_software_optimization_guide.pdf"
)) {
    if (-not (Test-Path (Join-Path $repoRoot $guide))) {
        throw "Missing $guide. The latency figures this test enforces come from it."
    }
}

Write-Output "Thor cmp_rdata tree contract passed: the serial multiply-accumulate is gone, four independent pairs combine as a balanced tree, and the reduction stays UMAXV 4S with the x86 path untouched."
