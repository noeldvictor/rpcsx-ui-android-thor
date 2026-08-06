$ErrorActionPreference = "Stop"

# Contract: JIT-generated code must never contain SVE instructions.
#
# Measured on this device: ID_AA64PFR0_EL1.SVE = 0, and HWCAP lists no sve.
# Emitting a single SVE instruction is an immediate SIGILL, and because the JIT
# emits at runtime it would surface as a crash in whatever game happened to
# compile that block, not as a build failure.
#
# The hazard is real rather than theoretical. Measured with clang at -O3 on the
# same trivial IR, counting SVE instructions in the output:
#
#   -mcpu=cortex-a78    0        (46 instructions total)
#   -mcpu=cortex-a710   7
#   -mcpu=cortex-a715   7
#   -mcpu=cortex-x3     7
#
# Thor's cores are X3 + A715 + A710 + A510, so every scheduling model that
# actually matches the silicon turns SVE on by default in bundled LLVM.
#
# Two independent mechanisms keep it off, and this pins both:
#
#   1. The attribute list always carries an explicit +sve/-sve and +sve2/-sve2
#      decided by runtime HWCAP. Verified that this is sufficient on its own:
#      cortex-x3 with -target-feature -sve emits 0 SVE instructions and the same
#      46 as cortex-a78.
#   2. sanitize_android_arm64_llvm_cpu rewrites any SVE-implying CPU name to
#      cortex-a78 when HWCAP reports no SVE.
#
# Keeping both is deliberate. Either alone would do, which is the point: this is
# a crash-on-first-execution failure, so it gets a belt and braces.

$repoRoot = Split-Path -Parent $PSScriptRoot
$jit = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp") -Raw

# Strip comments so prose about SVE cannot satisfy the checks.
$code = ($jit -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"

# 1. The attribute list must be able to say "no" as well as "yes". A bare
#    if (has_sve()) push("+sve") with no else would leave the CPU default in
#    force, which is exactly the failure being guarded against.
foreach ($pair in @(
    @{ feature = 'sve';  probe = 'utils::has_sve\(\)' },
    @{ feature = 'sve2'; probe = 'utils::has_sve2\(\)' }
)) {
    $f = $pair.feature
    if ($code -notmatch "$($pair.probe)") {
        throw "JIT no longer probes HWCAP for $f."
    }
    if ($code -notmatch [regex]::Escape("attributes.push_back(`"+$f`")")) {
        throw "JIT no longer advertises +$f when the hardware has it."
    }
    if ($code -notmatch [regex]::Escape("attributes.push_back(`"-$f`")")) {
        throw "JIT no longer emits an explicit -$f, so an SVE-capable scheduling model would keep SVE enabled."
    }
}

# 2. The CPU-name fallback must survive.
if ($code -notmatch 'sanitize_android_arm64_llvm_cpu') {
    throw "The SVE-implying CPU name sanitizer was removed."
}
if ($code -notmatch 'android_arm64_cpu_enables_sve_by_default') {
    throw "The check for CPU names that enable SVE by default was removed."
}
if ($code -notmatch 'return "cortex-a78"') {
    throw "The sanitizer no longer falls back to a scheduling model without SVE."
}

# 3. The fallback must be conditional on the runtime probe, not unconditional.
#    An unconditional rewrite would silently pin every device to cortex-a78,
#    including hardware that does have SVE.
if ($code -notmatch '!utils::has_sve\(\)\s*&&\s*android_arm64_cpu_enables_sve_by_default') {
    throw "The CPU sanitizer no longer gates on the runtime SVE probe."
}

Write-Output "Thor ARM64 JIT no-SVE contract passed: explicit -sve/-sve2 attributes plus the cortex-a78 fallback, both gated on runtime HWCAP."
