$ErrorActionPreference = "Stop"

# Contract for 128-bit big-endian guest memory access on AArch64.
#
# PS3 memory is big-endian and the host is not, so every VMX load and store gets
# byte-reversed. Expressed as llvm.bswap.i128 the backend has no way to keep it
# in the vector unit: it loads into two general-purpose registers, REVs each and
# moves both halves back with FMOV and MOV Vd.d[1]. Those GPR-to-SIMD transfers
# cost several cycles each.
#
#   ldp x8, x9, [x0] / rev x9 / rev x8 / fmov d0, x9 / mov v0.d[1], x8
#
# As a byte-reversing shuffle it stays in SIMD and becomes three instructions:
#
#   ldr q0, [x0] / rev64 v0.16b, v0.16b / ext v0.16b, v0.16b, v0.16b, #8
#
# Only the 128-bit case is special-cased; narrower accesses lower to a single
# REV already, so llvm.bswap is the right thing for them.

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUTranslator.cpp") -Raw

function Get-Func([string]$name) {
    $m = [regex]::Match($ppu, "(?s)(Value\*|void) PPUTranslator::$name\(.*?\n\}")
    if (-not $m.Success) {
        throw "Could not isolate PPUTranslator::$name."
    }
    return $m.Value
}

foreach ($fn in @('ReadMemory', 'WriteMemory')) {
    $body = Get-Func $fn
    $arm = [regex]::Match($body, '(?s)#ifdef ARCH_ARM64(.*?)#endif').Groups[1].Value
    if (-not $arm) {
        throw "$fn lost its ARCH_ARM64 128-bit path."
    }

    # Strip comments: they explain what the ARM path avoids, and naming the
    # avoided intrinsic there should not read as using it.
    $arm = ($arm -split "`n" | Where-Object { $_.Trim() -notmatch '^//' }) -join "`n"
    if ($arm -notmatch 'size == 128') {
        throw "$fn no longer special-cases the 128-bit byteswap on ARM64."
    }
    if ($arm -notmatch 'CreateShuffleVector') {
        throw "$fn no longer reverses 128-bit values as a vector shuffle on ARM64."
    }
    if ($arm -match 'llvm\.bswap\.i128') {
        throw "$fn is back to routing the 128-bit byteswap through llvm.bswap.i128 on ARM64."
    }

    # The reversal must be a full 16-byte reverse, not a partial permute.
    if ($arm -notmatch '15,\s*14,\s*13,\s*12,\s*11,\s*10,\s*9,\s*8,\s*7,\s*6,\s*5,\s*4,\s*3,\s*2,\s*1,\s*0') {
        throw "$fn's 128-bit reversal is not a full byte reverse."
    }

    # Narrower sizes must keep the portable intrinsic.
    if ($body -notmatch 'llvm\.bswap\.i%u') {
        throw "$fn lost the portable byteswap used for sizes below 128 bits."
    }
}

# The read path must keep the access volatile, as the non-ARM path does.
$read = Get-Func 'ReadMemory'
$armRead = [regex]::Match($read, '(?s)#ifdef ARCH_ARM64(.*?)#endif').Groups[1].Value
if ($armRead -notmatch 'setVolatile\(true\)') {
    throw "The ARM64 128-bit read dropped the volatile marking the other paths use."
}

Write-Output "Thor ARM64 PPU vector-endian contract passed: 128-bit byteswap stays in SIMD, narrower sizes keep llvm.bswap, volatile preserved."
