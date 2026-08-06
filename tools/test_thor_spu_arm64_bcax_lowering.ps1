$ErrorActionPreference = "Stop"

# Contract for the AArch64 SHA-3 bitwise path. Thor's Snapdragon 8 Gen 2
# reports sha3, and BCAX/EOR3 are plain logic instructions behind the crypto
# extension, so the SPU translator emits them directly instead of waiting for
# LLVM to form them. Everything here has to stay true together: detection, the
# JIT feature advertisement, the runtime gate, the non-SHA-3 fallback, and the
# two call sites.

$repoRoot = Split-Path -Parent $PSScriptRoot
$corePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3"

function Read-CoreFile([string]$relative) {
    $path = Join-Path $corePath $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing vendored core file: $relative"
    }
    return Get-Content -LiteralPath $path -Raw
}

$sysinfo = Read-CoreFile "util/sysinfo.cpp"
$jit = Read-CoreFile "util/JITLLVM.cpp"
$translatorHeader = Read-CoreFile "Emu/CPU/CPUTranslator.h"
$translatorSource = Read-CoreFile "Emu/CPU/CPUTranslator.cpp"
$spu = Read-CoreFile "Emu/Cell/SPULLVMRecompiler.cpp"

# 1. Detection has to come from the kernel, not from a CPU name guess.
if (-not $sysinfo.Contains('bool utils::has_sha3()')) {
    throw "utils::has_sha3() is gone; the SHA-3 paths would lose their runtime gate."
}
if (-not ($sysinfo -match '(?s)bool utils::has_sha3\(\).*?HWCAP_SHA3')) {
    throw "utils::has_sha3() no longer reads HWCAP_SHA3."
}

# 2. The JIT must advertise the feature both ways. Without +sha3 the intrinsics
#    fail instruction selection; without -sha3 a non-SHA-3 host could inherit it
#    from the CPU name.
foreach ($attribute in @('"+sha3"', '"-sha3"')) {
    if (-not $jit.Contains($attribute)) {
        throw "The JIT no longer advertises $attribute to LLVM."
    }
}
if (-not ($jit -match '(?s)utils::has_sha3\(\)\s*\)\s*\r?\n\s*attributes\.push_back\("\+sha3"\)')) {
    throw "The +sha3 attribute is no longer tied to utils::has_sha3()."
}

# 3. The translator gate is set once from detection.
if (-not $translatorSource.Contains('m_use_sha3 = utils::has_sha3();')) {
    throw "cpu_translator::initialize no longer sets m_use_sha3 from detection."
}
if (-not $translatorHeader.Contains('bool m_use_sha3 = false;')) {
    throw "m_use_sha3 is gone, or no longer defaults to off."
}

# 4. Both helpers must keep an arithmetic fallback, so callers never branch and
#    non-SHA-3 ARM hosts keep the previous codegen.
foreach ($helper in @('bcax', 'eor3')) {
    $match = [regex]::Match($translatorHeader, "(?s)value_t<T> $helper\(T1 a, T2 b, T3 c\)\s*\{.*?\n\t\}")
    if (-not $match.Success) {
        throw "Could not isolate the $helper helper in CPUTranslator.h."
    }

    $body = $match.Value
    if (-not $body.Contains('if (!m_use_sha3)')) {
        throw "$helper no longer falls back when the host has no SHA-3."
    }
    if (-not $body.Contains("llvm::Intrinsic::aarch64_crypto_${helper}u")) {
        throw "$helper no longer emits the aarch64_crypto_${helper}u intrinsic."
    }
    if (-not $body.Contains('get_intrinsic<u64[2]>')) {
        throw "$helper no longer requests the v2i64 overload, which is the one bundled LLVM selects."
    }
}

$bcaxBody = [regex]::Match($translatorHeader, '(?s)value_t<T> bcax\(T1 a, T2 b, T3 c\)\s*\{.*?\n\t\}').Value
if (-not $bcaxBody.Contains('m_ir->CreateXor(va, m_ir->CreateAnd(vb, m_ir->CreateNot(vc)))')) {
    throw "The bcax fallback no longer computes a ^ (b & ~c), so it would disagree with the instruction."
}

$eor3Body = [regex]::Match($translatorHeader, '(?s)value_t<T> eor3\(T1 a, T2 b, T3 c\)\s*\{.*?\n\t\}').Value
if (-not $eor3Body.Contains('m_ir->CreateXor(m_ir->CreateXor(va, vb), vc)')) {
    throw "The eor3 fallback no longer computes a ^ b ^ c."
}

# 5. EQV: BCAX with an all-ones second operand is a ^ ~b, which is ~(a ^ b).
$eqv = [regex]::Match($spu, '(?s)void EQV\(spu_opcode_t op\)\s*\{.*?\n\t\}')
if (-not $eqv.Success) {
    throw "Could not isolate the SPU EQV lowering."
}
if (-not $eqv.Value.Contains('bcax(get_vr<u32[4]>(op.ra), splat<u32[4]>(0xffffffff), get_vr<u32[4]>(op.rb))')) {
    throw "EQV no longer uses BCAX with an all-ones mask on ARM64."
}
if (-not $eqv.Value.Contains('set_vr(op.rt, ~(get_vr(op.ra) ^ get_vr(op.rb)));')) {
    throw "EQV lost its non-ARM64 form."
}
if (-not $eqv.Value.Contains('#ifdef ARCH_ARM64')) {
    throw "The EQV BCAX path is no longer guarded by ARCH_ARM64."
}

# 6. SHUFB: (c & ~0x60) ^ 0x0f is BCAX(0x0f, c, 0x60) on both selector paths.
$shufb = [regex]::Match($spu, '(?s)void SHUFB\(spu_opcode_t op\).*?(?=\s+void MPYA\(spu_opcode_t op\))')
if (-not $shufb.Success) {
    throw "Could not isolate the SPU SHUFB lowering."
}

$selector = 'bcax(splat<u8[16]>(0x0f), c, splat<u8[16]>(0x60))'
$selectorUses = ([regex]::Matches($shufb.Value, [regex]::Escape($selector))).Count
if ($selectorUses -lt 2) {
    throw "Expected the BCAX selector on both SHUFB paths, found $selectorUses."
}
if ($shufb.Value.Contains('const auto cm = eval(c & 0x9f);') -or $shufb.Value.Contains('const auto cm = eval(c & ~0x60);')) {
    throw "SHUFB still carries the superseded AND/XOR selector next to the BCAX one."
}

Write-Output "Thor ARM64 SHA-3 contract passed: HWCAP detection, +sha3/-sha3 advertisement, m_use_sha3 gate, arithmetic fallbacks, and BCAX at EQV plus both SHUFB selectors."
