$ErrorActionPreference = "Stop"

# Contract: the 128-byte reservation copy must keep Arm's prescribed shape.
#
# The Cortex-X3 Software Optimization Guide (docs/hardware/) section 4.3 gives an
# explicit recipe for a memory copy on this core: unroll it, use the
# non-writeback forms of LDP and STP, interleave each load with its store, and
# align stores on a 32-byte boundary. Section 4.4 separately lists "store
# operations that cross a 32B boundary" as a case that costs bandwidth or
# latency.
#
# std::memcpy, which is what ARM64 used to fall through to, satisfies none of
# that. Measured at -O2 -march=armv8.4-a with NDK clang, a fixed 128-byte copy
# expanded to 12 memory operations rather than 8, and two of its stores were
#
#     stp q0, q1, [x0, #16]
#     stp q0, q1, [x0, #80]
#
# Against the alignas(64) rdata this runs on, offsets 16 and 80 are both 16 mod
# 32, so each of those 32-byte stores straddles a 32-byte boundary.
#
# This is the hottest copy in the emulator: it runs on every GETLLAR retry
# iteration, and the retry limit is 24.
#
# Two ways this regresses silently, which is why it is pinned rather than
# trusted:
#
#  1. Loop-idiom recognition. Writing the copy as a tidy loop gets it rewritten
#     straight back into memcpy, restoring the bad expansion. The same trap is
#     already documented on mov_rdata_nt, where it also drops the non-temporal
#     metadata. So the copy must stay written out.
#  2. Someone "simplifying" the unrolled body back to std::memcpy, which looks
#     like a tidy-up and is a performance regression with no visible symptom.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuThread = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

if (-not (Test-Path $spuThread)) { throw "SPUThread.cpp not found at $spuThread" }
$source = Get-Content $spuThread -Raw

# 1. mov_rdata must have an ARM64 branch at all, and it must come before the
#    generic memcpy fallback.
$movRdataStart = $source.IndexOf("mov_rdata(spu_rdata_t& _dst, const spu_rdata_t& _src)")
if ($movRdataStart -lt 0) { throw "mov_rdata definition not found; this test needs updating." }

# Bound the search to mov_rdata's own body, so mov_rdata_nt's ARM path below
# cannot make this pass by accident. That mistake has been made in this suite
# before: asserting on a neighbour and reporting success.
$movRdataNtStart = $source.IndexOf("mov_rdata_nt(spu_rdata_t& _dst, const spu_rdata_t& _src)")
if ($movRdataNtStart -lt 0) { throw "mov_rdata_nt definition not found; this test needs updating." }
if ($movRdataNtStart -le $movRdataStart) { throw "Unexpected ordering of mov_rdata and mov_rdata_nt." }

$body = $source.Substring($movRdataStart, $movRdataNtStart - $movRdataStart)

if ($body -notmatch '#elif defined\(ARCH_ARM64\)') {
    throw "mov_rdata has no ARCH_ARM64 branch. ARM64 is falling back to std::memcpy, which expands to 12 memory operations with two stores crossing a 32-byte boundary."
}

# 2. The copy must be written out, not looped. A loop is what loop-idiom
#    recognition turns back into memcpy.
if ($body -match '(?m)^\s*for\s*\(' ) {
    throw "mov_rdata's ARM64 path contains a loop. Loop-idiom recognition rewrites copy loops into memcpy, undoing this change silently. Write the chunk copies out."
}

# 3. All eight 16-byte chunks must be present, so the whole 128 bytes is covered
#    by the explicit form rather than half of it falling to something else.
foreach ($i in 0..7) {
    if ($body -notmatch "src_chunks\[$i\]") {
        throw "mov_rdata's ARM64 path does not read src_chunks[$i]. All eight 16-byte chunks must be copied explicitly."
    }
    if ($body -notmatch "dst_chunks\[$i\]") {
        throw "mov_rdata's ARM64 path does not write dst_chunks[$i]. All eight 16-byte chunks must be copied explicitly."
    }
}

# 4. The pairing must be interleaved load-load-store-store per 32-byte group,
#    which is what produces LDP followed by STP at a 32-byte aligned offset.
#    Check the ordering of the first group explicitly.
$firstGroup = [regex]::Match($body, 'src_chunks\[0\][\s\S]{0,400}?dst_chunks\[1\]')
if (-not $firstGroup.Success) {
    throw "Could not find the first 32-byte group in mov_rdata's ARM64 path."
}
$groupText = $firstGroup.Value
$idxSrc1 = $groupText.IndexOf("src_chunks[1]")
$idxDst0 = $groupText.IndexOf("dst_chunks[0]")
if ($idxSrc1 -lt 0 -or $idxDst0 -lt 0 -or $idxSrc1 -gt $idxDst0) {
    throw "mov_rdata's ARM64 path does not load both halves of the first 32-byte group before storing. That ordering is what lets the backend form LDP then STP."
}

# 5. The chunk type must stay 16 bytes. A 32-byte chunk here would be a
#    different instruction selection question, and the static_asserts in the
#    source are what keep this honest at compile time.
if ($body -notmatch 'vector_size\(16\)') {
    throw "mov_rdata's ARM64 path no longer uses a 16-byte vector chunk. LDP/STP of Q registers is what section 4.3 prescribes."
}

# 6. The x86 path must be untouched.
if ($body -notmatch '_mm_storeu_si128') {
    throw "The x86 path in mov_rdata was modified. This change is ARM-only."
}

# 7. mov_rdata_nt must keep its own 32-byte non-temporal chunks. A 16-byte
#    non-temporal store is not equivalent: clang splits it into D registers,
#    giving three instructions per chunk instead of a paired STNP.
$ntBody = $source.Substring($movRdataNtStart)
$ntEnd = $ntBody.IndexOf("`n}")
if ($ntEnd -gt 0) { $ntBody = $ntBody.Substring(0, $ntEnd) }
if ($ntBody -notmatch 'vector_size\(32\)') {
    throw "mov_rdata_nt no longer uses 32-byte non-temporal chunks. A 16-byte non-temporal store lowers to a D-register split plus STNP, three instructions where the paired form is one."
}

# 8. The hardware guides the reasoning rests on must still be in the repo.
$guide = Join-Path $repoRoot "docs/hardware/arm_cortex_x3_software_optimization_guide.pdf"
if (-not (Test-Path $guide)) {
    throw "The Cortex-X3 optimization guide is missing from docs/hardware/. The 32-byte store alignment rule this test enforces comes from it."
}

Write-Output "Thor rdata copy shape contract passed: mov_rdata has an explicit ARM64 path, unrolled rather than looped, all eight chunks interleaved into 32-byte aligned LDP/STP pairs, with mov_rdata_nt's 32-byte non-temporal chunks and the x86 path intact."
