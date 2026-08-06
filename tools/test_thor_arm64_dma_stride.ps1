$ErrorActionPreference = "Stop"

# Contract for the MFC DMA copy width on AArch64.
#
# The x86 path widens to a 32-byte stride only when the LS address is a known
# constant that is 32-byte aligned, because AVX's aligned moves want that. ARM
# pairs two 128-bit accesses with LDP/STP at any alignment, verified against the
# NDK backend at align 32, 16 and 1, all producing identical ldp/stp. Requiring
# the alignment there only forced copies onto the 16-byte stride, which emits
# twice the memory instructions for the same bytes.
#
# MFC DMA is one of the hottest paths in SPU emulation, so this stays pinned.

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$spu = Get-Content -LiteralPath $spuPath -Raw

$region = [regex]::Match($spu, '(?s)// Check if the LS address is constant and 256 bit aligned.*?else if \(csize\)')
if (-not $region.Success) {
    throw "Could not isolate the MFC DMA copy width selection."
}

$body = $region.Value

if (-not ($body -match '(?s)#ifdef ARCH_ARM64.*?if \(csize >= 32\)\s*\r?\n\s*\{\s*\r?\n\s*vtype = get_type<u8\[32\]>\(\);\s*\r?\n\s*stride = 32;')) {
    throw "The ARM64 DMA path no longer widens on size alone."
}

$armBranch = [regex]::Match($body, '(?s)#ifdef ARCH_ARM64(.*?)#else').Groups[1].Value
if ($armBranch -match 'clsa % 32') {
    throw "The ARM64 DMA path reintroduced the x86 32-byte constant-alignment requirement."
}
if ($armBranch -match 'm_use_avx') {
    throw "The ARM64 DMA width should not be gated on an x86 feature flag."
}

# The x86 path must keep its own rule intact.
$x86Branch = [regex]::Match($body, '(?s)#else(.*?)#endif').Groups[1].Value
if ($x86Branch -notmatch 'm_use_avx && csize >= 32 && !\(clsa % 32\)') {
    throw "The x86 DMA width rule was altered; only the ARM64 branch should differ."
}

# The emitted copies must still declare an explicit 16-byte alignment, which is
# what makes widening safe when the address is not known to be aligned.
if ($body -notmatch 'CreateAlignedStore\(m_ir->CreateAlignedLoad\(vtype, _src, llvm::MaybeAlign\{16\}\), _dst, llvm::MaybeAlign\{16\}\)') {
    throw "The DMA copy no longer declares align 16, so widening would assume an alignment it does not have."
}

Write-Output "Thor ARM64 DMA stride contract passed: widened on size alone, align 16 preserved, x86 alignment rule untouched."
