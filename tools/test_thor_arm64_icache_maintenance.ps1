$ErrorActionPreference = "Stop"

# Contract for publishing JIT-written code to instruction fetch on AArch64.
#
# x86 instruction caches are coherent with the data caches, so writing code and
# jumping to it needs ordering at most. AArch64 makes no such guarantee, and
# what it does require is advertised per-implementation in CTR_EL0:
#
#   IDC = 1  data cache clean to PoU not required
#   DIC = 1  instruction cache invalidation not required
#
# Read on the AYN Thor's Snapdragon 8 Gen 2: IDC=1, DIC=0. So invalidating the
# instruction cache is architecturally required on this device. Apple Silicon
# reports DIC=1, which is the likely reason this survived upstream despite
# RPCS3 running on arm64 Macs.
#
# What was there before, at seven sites:
#
#   asm("ISB");
#   asm("DSB ISH");
#
# wrong three ways. The barriers are in the opposite of the required order, so
# the pipeline was flushed before the store was guaranteed complete. Neither is
# asm volatile with a memory clobber, so the compiler was free to move them
# across the writes they were supposed to publish. And no cache maintenance was
# performed at all, which DIC=0 says is needed.

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-Code([string]$rel) {
    $raw = Get-Content -LiteralPath (Join-Path $repoRoot $rel) -Raw
    # Strip comments; they necessarily quote the old broken sequence.
    return ($raw -split "`n" | Where-Object { $_.Trim() -notmatch '^\s*//' }) -join "`n"
}

$sources = @(
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"
)

foreach ($rel in $sources) {
    $code = Get-Code $rel

    # The reversed, non-volatile pair must not come back anywhere.
    if ($code -match 'asm\("ISB"\)') {
        throw "$rel still has a bare asm(""ISB""); it is not volatile, has no memory clobber, and was ordered before its DSB."
    }
    if ($code -match 'asm\("DSB ISH"\)') {
        throw "$rel still has a bare asm(""DSB ISH"")."
    }

    # Any barrier that remains must be volatile with a memory clobber and in the
    # order DSB then ISB.
    foreach ($m in [regex]::Matches($code, '__asm__ volatile\("(?<body>[^"]*)"[^;]*;')) {
        $body = $m.Groups['body'].Value
        if ($body -match 'isb' -and $body -match 'dsb') {
            if ($body.IndexOf('dsb') -gt $body.IndexOf('isb')) {
                throw "$rel has a barrier pair with ISB before DSB; DSB must complete first."
            }
            if ($m.Value -notmatch '"memory"') {
                throw "$rel has a barrier pair without a memory clobber, so it can move across the code it publishes."
            }
        }
    }
}

# Sites that know the exact range written must invalidate it, not merely order.
$spuCommon = Get-Code "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$clears = ([regex]::Matches($spuCommon, '__builtin___clear_cache')).Count
if ($clears -lt 3) {
    throw "Expected the two 16-byte trampoline patches and the branch patchpoint to invalidate their written ranges; found $clears __builtin___clear_cache call(s)."
}
if ($spuCommon -notmatch '__builtin___clear_cache\(reinterpret_cast<char\*>\(patch_fn\), reinterpret_cast<char\*>\(raw\)\)') {
    throw "The SPU branch patchpoint no longer invalidates exactly the range it wrote."
}

# MCJIT writes far more code than the hand-patched trampolines do. Both custom
# memory managers override finalizeMemory, which is where the stock
# SectionMemoryManager does this, so they have to do it themselves.
$jit = Get-Code "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"
if ($jit -notmatch 'jit_flush_code_sections') {
    throw "JITLLVM no longer flushes JIT-written code sections."
}
$records = ([regex]::Matches($jit, 'jit_record_code_section')).Count
if ($records -lt 3) {
    throw "Expected both allocateCodeSection overrides to record their ranges plus the helper definition; found $records reference(s)."
}
$finalizers = ([regex]::Matches($jit, 'jit_flush_code_sections\(m_code_ranges\)')).Count
if ($finalizers -lt 2) {
    throw "Expected both MemoryManager finalizeMemory overrides to flush; found $finalizers."
}

Write-Output "Thor ARM64 i-cache contract passed: no reversed bare barriers, remaining pairs are volatile DSB-then-ISB with a memory clobber, known ranges use __builtin___clear_cache, and both MCJIT memory managers flush code sections."
