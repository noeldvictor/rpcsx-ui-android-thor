$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$threadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"
$vmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/vm_native.cpp"
$llvmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$threadSource = Get-Content -LiteralPath $threadPath -Raw
$vmSource = Get-Content -LiteralPath $vmPath -Raw
$llvmSource = Get-Content -LiteralPath $llvmPath -Raw

$requiredThreadFragments = @(
    'enum : s64',
    'SIGNED_LS_SIZE = SPU_LS_SIZE',
    'for (s64 ls_offs = 0 - SIGNED_LS_SIZE * 2; ls_offs <= SIGNED_LS_SIZE * 2; ls_offs += SIGNED_LS_SIZE)',
    'utils::memory_release(ls - SIGNED_LS_SIZE * 3, SIGNED_LS_SIZE * 7);',
    'utils::memory_reserve(SIGNED_LS_SIZE * 7, nullptr, true)',
    '+ SIGNED_LS_SIZE * 3',
    'const auto [ptr_ret, str] = shm.map_critical(ls + ls_offs);',
    'if (ptr_ret != ls + ls_offs)',
    'if (!str.empty())'
)

foreach ($fragment in $requiredThreadFragments) {
    if (-not $threadSource.Contains($fragment)) {
        throw "Missing extended local-store mirror fragment: $fragment"
    }
}

foreach ($legacyFragment in @(
    'memory_reserve(SPU_LS_SIZE * 5, nullptr, true)',
    'memory_release(ls - SPU_LS_SIZE * 2, SPU_LS_SIZE * 5)',
    'ensure(shm.map_critical(ls - SPU_LS_SIZE).first'
)) {
    if ($threadSource.Contains($legacyFragment)) {
        throw "Legacy three-mirror local-store layout remains: $legacyFragment"
    }
}

foreach ($fragment in @(
    'const auto mapped_addr = this->map(target, prot, cow);',
    'if (!mapped_addr)',
    'return {mapped_addr, {}};',
    'VirtualQuery() reported unexpected memory info'
)) {
    if (-not $vmSource.Contains($fragment)) {
        throw "Missing strict shared-memory mapping result fragment: $fragment"
    }
}

if ($vmSource.Contains('return {this->map(target, prot, cow), "Failed to map"};')) {
    throw 'Successful critical mappings still carry the legacy failure string.'
}

foreach ($fragment in @(
    'return original | ~u64{SPU_LS_SIZE - 1};',
    'get_imm<u64>(op.si10) << 4'
)) {
    if (-not $llvmSource.Contains($fragment)) {
        throw "The address-specialization dependency changed: $fragment"
    }
}

# LQD/STQD can combine a canonical constant, a masked LS base, and a signed
# 10-bit quadword displacement. Prove that the old -1..+1 mirror layout was
# too small at both extremes and that the current -2..+2 mappings cover every
# byte of the resulting 16-byte vector access.
$lsSize = 0x40000L
$oldMappedMin = -$lsSize
$oldMappedMax = (2 * $lsSize) - 1
$newMappedMin = -2 * $lsSize
$newMappedMax = (3 * $lsSize) - 1
$specializedMin = -$lsSize + (-512 * 16)
$specializedMax = ($lsSize - 16) + ($lsSize - 16) + (511 * 16) + 15

if ($specializedMin -ge $oldMappedMin -or $specializedMax -le $oldMappedMax) {
    throw 'The mirror coverage proof no longer demonstrates the old-layout underflow and overflow.'
}

if ($specializedMin -lt $newMappedMin -or $specializedMax -gt $newMappedMax) {
    throw "Extended mirrors do not cover the specialized LQD/STQD range [$specializedMin,$specializedMax]."
}

Write-Output "Thor SPU LS mirror contract passed: five mapped copies cover the full canonical LQD/STQD range [$specializedMin,$specializedMax], and critical mapping errors fail closed."
