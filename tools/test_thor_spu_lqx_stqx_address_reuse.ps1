$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

# Official RPCS3 9bf67f031288b3197ed07d2305da273a6ebe65bc canonicalizes
# out-of-range LS constants to one negative mirror. Current tip 0fcb15ab1810926
# retains this for aligned operands while reverting non-aligned address reuse.
$alignedGuard = 'if (const u32 remainder = data._u32[3] % 0x10; remainder == 0)'
$alignedAddress = 'splat<u64>(addend) + zext<u64>(extract(pair.second, 3) & 0x3fff0)'
$genericAddress = 'zext<u64>((extract(a, 3) + extract(b, 3)) & 0x3fff0)'
$negativeOffset = 'return original | ~u64{SPU_LS_SIZE - 1};'
$canonicalAddend = 'const u64 addend = (data._u32[3] >= SPU_LS_SIZE) ? make_negative_LS_offset(data._u32[3]) : data._u32[3];'

if (-not $source.Contains($negativeOffset)) {
    throw 'SPU local-store negative mirror helper is missing.'
}

$alignedGuardCount = ([regex]::Matches($source, [regex]::Escape($alignedGuard))).Count
if ($alignedGuardCount -ne 2) {
    throw "Expected aligned-only STQX/LQX guards twice; found $alignedGuardCount."
}

$alignedAddressCount = ([regex]::Matches($source, [regex]::Escape($alignedAddress))).Count
if ($alignedAddressCount -ne 2) {
    throw "Expected aligned STQX/LQX address reuse twice; found $alignedAddressCount."
}

$genericAddressCount = ([regex]::Matches($source, [regex]::Escape($genericAddress))).Count
if ($genericAddressCount -ne 2) {
    throw "Expected generic masked STQX/LQX fallback twice; found $genericAddressCount."
}

$canonicalAddendCount = ([regex]::Matches($source, [regex]::Escape($canonicalAddend))).Count
if ($canonicalAddendCount -ne 2) {
    throw "Expected canonical STQX/LQX constant addends twice; found $canonicalAddendCount."
}

if ($source.Contains('data._u32[3] - remainder') -or
    $source.Contains('(extract(pair.second, 3) + remainder) & 0x3fff0') -or
    $source.Contains('data._u32[3] %= SPU_LS_SIZE')) {
    throw 'Unsafe/noncanonical LQX/STQX constant address reuse is present.'
}

Write-Output 'Thor SPU LQX/STQX address contract passed: aligned constants use one canonical LS mirror and non-aligned operands use the generic masked fallback.'
