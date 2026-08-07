$ErrorActionPreference = "Stop"

# Contract for the 16-byte atomic fast paths on AArch64.
#
# util/atomic.hpp has LSE2 variants of load/store/release for atomic_t<u128>,
# guarded on ARM_FEATURE_LSE2. There is no ACLE feature macro for FEAT_LSE2, and
# the __ARM_ARCH_8_4__ family that rx/types.hpp probes for is not defined by
# clang on AArch64 at any -march, so for the whole life of this fork the macro
# was never defined and every one of those fast paths was dead.
#
# What the fallback costs is the point. Without LSE2:
#
#   load()    -> ldaxp / stlxp / cbnz retry loop
#   store()   -> exchange() -> same loop
#   release() -> exchange() -> same loop
#
# STLXP takes the cache line in exclusive state, so a thread merely *reading*
# a reservation invalidates every other core's copy. vm::g_reservations is
# shared by every SPU thread, which makes this the worst place in the emulator
# to force write-intent on readers. With LSE2 an aligned LDP is single-copy
# atomic and the read is just a load.
#
# This test pins the three things that have to stay true together, because any
# one of them alone silently reverts to the slow path or, worse, to a race.

$repoRoot = Split-Path -Parent $PSScriptRoot
$cmake = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$gradle = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$atomic = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/atomic.hpp") -Raw

# 1. The macro must be defined by the build, since no compiler defines it.
if ($cmake -notmatch 'add_compile_definitions\(ARM_FEATURE_LSE2=1\)') {
    throw "The Android build no longer defines ARM_FEATURE_LSE2, so the 16-byte atomic fast paths are dead again."
}

# 2. The ISA baseline must actually guarantee FEAT_LSE2 (Armv8.4-A or newer).
#    Below that an aligned LDP is not single-copy atomic and assuming it is
#    turns these atomics into a data race.
$archMatch = [regex]::Match($cmake, 'set\(RPCSX_ANDROID_ARM_ARCH "(?<arch>[^"]+)"')
if (-not $archMatch.Success) {
    throw "Could not read RPCSX_ANDROID_ARM_ARCH from CMakeLists.txt."
}
$arch = $archMatch.Groups['arch'].Value
if ($arch -notmatch '^armv(8\.[4-9]|9)') {
    throw "ARM baseline '$arch' does not guarantee FEAT_LSE2, but ARM_FEATURE_LSE2 is defined."
}

# Armv9 mandates SVE2 and this device advertises no SVE at all, so the baseline
# must stay on the 8.x line. See sanitize_android_arm64_llvm_cpu for the JIT-side
# version of the same constraint.
if ($arch -match '^armv9') {
    throw "ARM baseline '$arch' mandates SVE2, which this device does not advertise. Use armv8.4-a."
}

# 3. Gradle passes -DRPCSX_ANDROID_ARM_ARCH explicitly and so overrides the
#    CMake cache default. If the two drift apart the guard fires at configure
#    time, but catching it here is cheaper than a failed build.
$gradleArch = [regex]::Match($gradle, '\?: "(?<arch>armv[^"]+)"')
if (-not $gradleArch.Success) {
    throw "Could not read the Gradle ARM baseline default."
}
if ($gradleArch.Groups['arch'].Value -ne $arch) {
    throw "Gradle ARM baseline '$($gradleArch.Groups['arch'].Value)' disagrees with CMake's '$arch'."
}

# 4. The guard that refuses to assume LSE2 on too low a baseline must remain.
if ($cmake -notmatch 'RPCSX_ANDROID_ARM_LSE2 requires an Armv8\.4-A or newer baseline') {
    throw "The LSE2 baseline guard was removed; a lower -march would now silently race instead of failing."
}

# 5. The fast paths themselves must still be there and must still be plain
#    LDP/STP, not another flavour of exclusive loop.
# Strip comments first. The comments here explain what the fast path replaces
# and necessarily name the preprocessor branches, so leaving them in lets a
# "#else" inside a comment terminate the match early. Same reason
# test_thor_arm64_ppu_vector_endian.ps1 strips them.
$atomicCode = ($atomic -split "`n" | Where-Object { $_.Trim() -notmatch '^//' }) -join "`n"

$lse2Load = [regex]::Match($atomicCode, '(?s)#if defined\(ARM_FEATURE_LSE2\)(?<body>.*?)#else')
if (-not $lse2Load.Success) {
    throw "util/atomic.hpp lost its ARM_FEATURE_LSE2 fast path."
}
if ($lse2Load.Groups['body'].Value -notmatch 'ldp ') {
    throw "The LSE2 16-byte load is no longer a plain LDP."
}
if ($lse2Load.Groups['body'].Value -match 'ldaxp|stlxp') {
    throw "The LSE2 16-byte load reintroduced exclusive-access instructions."
}

# atomic_t::load() is sequentially consistent. "ldp; dmb ish" is only the
# acquire mapping, so the load needs a barrier on both sides to match what the
# LDAXP/STLXP loop provided. Dropping the leading one is a silent weakening on
# the busiest shared structure in SPU emulation, so pin the count.
$loadBarriers = ([regex]::Matches($lse2Load.Groups['body'].Value, 'dmb ish')).Count
if ($loadBarriers -lt 2) {
    throw "The LSE2 16-byte load has $loadBarriers barrier(s); seq_cst needs one before and one after the LDP."
}

$storeCount = ([regex]::Matches($atomicCode, '#if defined\(ARM_FEATURE_LSE2\)')).Count
if ($storeCount -lt 2) {
    throw "Expected both the load and the store/release LSE2 paths, found $storeCount guard(s)."
}

# The SPU mailbox is the widest consumer of the 16-byte path after the
# reservations, and only because sync_var_t is exactly 16 bytes: count plus all
# three queued values in one atomic. If it ever grows, atomic_t<sync_var_t> no
# longer resolves to atomic_storage<T, 16>, and both the atomicity this relies
# on and the LSE2 fast path go away silently.
$spuHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.h") -Raw
$syncVar = [regex]::Match($spuHeader, '(?s)struct alignas\(16\) sync_var_t\s*\{(?<body>.*?)\};')
if (-not $syncVar.Success) {
    throw "Could not find spu_channel_4_t::sync_var_t, which the 16-byte atomic path depends on."
}

$fieldBytes = @{ 'u8' = 1; 'u16' = 2; 'u32' = 4; 'u64' = 8 }
$total = 0
foreach ($m in [regex]::Matches($syncVar.Groups['body'].Value, '\b(?<type>u8|u16|u32|u64)\s+\w+\s*;')) {
    $total += $fieldBytes[$m.Groups['type'].Value]
}
if ($total -ne 16) {
    throw "sync_var_t is now $total bytes, not 16. atomic_t<sync_var_t> no longer uses the 128-bit atomic storage, so SPU mailbox updates are no longer one atomic operation."
}

Write-Output "Thor ARM64 LSE2 atomic contract passed: baseline $arch guarantees FEAT_LSE2, the build defines ARM_FEATURE_LSE2, and the 16-byte fast paths are plain LDP/STP."
