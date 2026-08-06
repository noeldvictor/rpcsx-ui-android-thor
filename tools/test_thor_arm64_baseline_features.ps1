$ErrorActionPreference = "Stop"

# Contract for AArch64 baseline feature decisions.
#
# Features that are optional on x86 but mandatory on AArch64 must be decided by
# architecture, never by CPU name. FMA is the case that bit us: the translator
# enabled it only for cpu == "cyclone" or a name containing "cortex", which is
# correct thinking for x86 and wrong for ARM, where FMLA is base ARMv8-A.
#
# The MIDR table resolves plenty of names without "cortex" in them, and each one
# silently fell back to separate multiply and add, costing speed and changing
# rounding against a guest that fuses.

$repoRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3"
$translator = Get-Content -LiteralPath (Join-Path $corePath "Emu/CPU/CPUTranslator.cpp") -Raw
$cpuTable = Get-Content -LiteralPath (Join-Path $corePath "Emu/CPU/Backends/AArch64/AArch64Common.cpp") -Raw

# 1. The ARM64 branch must set FMA unconditionally.
$armBlock = [regex]::Match($translator, '(?s)#ifdef ARCH_ARM64\s*\r?\n\s*m_use_fma = true;.*?#else')
if (-not $armBlock.Success) {
    throw "m_use_fma is no longer set unconditionally on ARCH_ARM64."
}

# 2. The name allowlist must not be what decides it on ARM.
$nameCheck = [regex]::Match($translator, '(?s)(if \(cpu == "cyclone" \|\| cpu\.contains\("cortex"\)\)).{0,400}?m_use_fma = true;')
if ($nameCheck.Success) {
    $before = $translator.Substring(0, $nameCheck.Index)
    $lastIfdef = $before.LastIndexOf('#ifdef ARCH_ARM64')
    $lastElse = $before.LastIndexOf('#else')
    if ($lastIfdef -gt $lastElse) {
        throw "The cortex name check still decides FMA inside the ARCH_ARM64 branch."
    }
}

# 3. Guard the reasoning: if the MIDR table can produce names without "cortex",
#    a name-based check would miss them. This is what makes the rule necessary,
#    so assert the premise rather than trusting the comment.
$names = [regex]::Matches($cpuTable, '"([a-z0-9][a-z0-9.-]*)"\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$nonCortex = @($names | Where-Object { $_ -notlike '*cortex*' -and $_ -match '^(kryo|krait|falkor|saphira|oryon|apple|neoverse|ampere|carmel|tsv110|thunderx|star-mc1)' })
if ($nonCortex.Count -lt 1) {
    throw "The AArch64 MIDR table no longer resolves any non-cortex CPU name; re-check whether this contract still applies."
}

Write-Output "Thor AArch64 baseline-feature contract passed: FMA decided by architecture, not by CPU name ($($nonCortex.Count) non-cortex names reachable from MIDR detection)."
