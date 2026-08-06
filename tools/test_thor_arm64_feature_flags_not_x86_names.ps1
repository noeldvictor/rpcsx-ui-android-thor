$ErrorActionPreference = "Stop"

# Contract: on AArch64, host-capability flags must not be decided by matching
# x86 CPU model names.
#
# cpu_translator::initialize answers "what can this host do" with a series of
# string comparisons against x86 model names. That is fine on x86. On AArch64
# the same flags still gate real lowerings, so a CPU string that matches nothing
# silently selects a fallback written for 2006 hardware.
#
# Two of these have already bitten or nearly bitten:
#
#   m_use_fma  - was gated on cpu == "cyclone" || cpu.contains("cortex"). FMA is
#                mandatory on AArch64, so the allowlist could only ever fail to
#                enable it.
#   m_use_ssse3 - gates the x86_pshufb lowering. On AArch64 that lowering is AND
#                with 0x8F then TBL, baseline NEON with no SSSE3 involvement.
#                The else branch is a 16-iteration scalar loop of
#                extractelement/insertelement, and it would be taken by VPERM,
#                LVLX, LVRX, STVLX, STVRX, ROTQBY and SHUFB simultaneously.
#
# The second was reachable rather than merely ugly: the allowlist includes
# "generic", and cpu comes from getTargetCPU() with a fallback_cpu_detection()
# path behind it. Nothing about AArch64 guarantees that string stays out of the
# list forever.

$repoRoot = Split-Path -Parent $PSScriptRoot
$src = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.cpp") -Raw

# Strip comments so the explanations above the code cannot satisfy the checks.
$code = ($src -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"

# The ARM64 block must state the capabilities it relies on rather than inherit
# them from a default or from an x86 name match.
$armBlock = [regex]::Match($code, '(?s)#ifdef ARCH_ARM64\s+m_use_fma = true;(?<body>.*?)#else')
if (-not $armBlock.Success) {
    throw "Could not find the ARCH_ARM64 feature block in cpu_translator::initialize."
}

foreach ($flag in @('m_use_fma = true;', 'm_use_ssse3 = true;')) {
    $whole = "#ifdef ARCH_ARM64`n`tm_use_fma = true;" + $armBlock.Groups['body'].Value
    if ($whole -notmatch [regex]::Escape($flag)) {
        throw "The ARCH_ARM64 block no longer sets $flag, so it falls back to an x86 name match or a default."
    }
}

# The SSSE3 allowlist must not be compiled on ARM64 at all. If it is, a CPU
# string of "generic" turns every byte shuffle into a scalar loop.
$ssse3 = [regex]::Match($code, '(?s)(?<guard>#ifndef ARCH_ARM64\s*)?if \(cpu == "generic" \|\|.*?m_use_ssse3 = false;\s*\}\s*(?<endif>#endif)?')
if (-not $ssse3.Success) {
    throw "Could not locate the SSSE3 CPU-name allowlist."
}
if (-not $ssse3.Groups['guard'].Success -or -not $ssse3.Groups['endif'].Success) {
    throw "The SSSE3 CPU-name allowlist is no longer excluded from ARM64 builds; a 'generic' CPU string would select the scalar-loop pshufb."
}

# The AArch64 pshufb lowering itself must stay a single TBL, not the loop.
$lowering = [regex]::Match($code, '(?s)#elif defined\(ARCH_ARM64\)(?<body>.*?)#else\s*#error "Unimplemented"')
if (-not $lowering.Success) {
    throw "Could not find the AArch64 x86_pshufb lowering."
}
if ($lowering.Groups['body'].Value -notmatch 'aarch64_neon_tbl1') {
    throw "The AArch64 x86_pshufb lowering no longer uses TBL."
}
if ($lowering.Groups['body'].Value -notmatch '0x8F') {
    throw "The AArch64 x86_pshufb lowering dropped the 0x8F mask, which is what reproduces PSHUFB's high-bit-zeroes rule."
}

Write-Output "Thor ARM64 feature-flag contract passed: FMA and byte-shuffle capability are stated for AArch64, the x86 CPU-name allowlist is excluded, and pshufb stays a masked TBL."
