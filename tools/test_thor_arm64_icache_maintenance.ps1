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

# JITASM.cpp joined this list on 2026-08-13, and it is the reason the list matters.
# The test passed for weeks while that file still held the reversed bare pair,
# because the test never read it. ARMSX3 found the two sites in it: their commit
# c2b5f0c40. This is the failure this repo records more than any other, which is that
# a search that finds nothing and a search that searches nothing look the same.
$sources = @(
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/util/JITASM.cpp",
    "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"
)

foreach ($rel in $sources) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $rel))) {
        throw "$rel does not exist, so scanning it proves nothing. Fix the path before trusting a pass."
    }
}

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

# asmjit output is copied into executable memory by jit_runtime_base::_add, and
# jit_runtime::finalize rewrites an executable snapshot in place when the emulator
# restarts. Both are reached on ARM64: build_function_asm makes ppu_gateway
# (PPUThread.cpp), tr_dispatch (SPUCommonRecompiler.cpp) and the thread entry
# (Thread.cpp) through this runtime.
$jitasm = Get-Code "app/src/main/cpp/rpcsx/rpcs3/util/JITASM.cpp"
$asmClears = ([regex]::Matches($jitasm, '__builtin___clear_cache')).Count
if ($asmClears -lt 2) {
    throw "Expected jit_runtime_base::_add and jit_runtime::finalize to invalidate the code they write; found $asmClears __builtin___clear_cache call(s) in JITASM.cpp."
}
if ($jitasm -notmatch '__builtin___clear_cache\(reinterpret_cast<char\*>\(p\), reinterpret_cast<char\*>\(p\) \+ codeSize\)') {
    throw "jit_runtime_base::_add no longer invalidates exactly the range it copied."
}
if ($jitasm -notmatch '__builtin___clear_cache\(reinterpret_cast<char\*>\(code_ptr\), reinterpret_cast<char\*>\(code_ptr\) \+ s_code_init\.size\(\)\)') {
    throw "jit_runtime::finalize no longer invalidates the restored code snapshot."
}

Write-Output "Thor ARM64 i-cache contract passed: no reversed bare barriers, remaining pairs are volatile DSB-then-ISB with a memory clobber, known ranges use __builtin___clear_cache, both MCJIT memory managers flush code sections, and both asmjit publication sites in JITASM.cpp invalidate what they wrote."
