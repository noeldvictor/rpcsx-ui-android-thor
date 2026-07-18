$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

# Official RPCS3 0fcb15ab1810926ac0b3ffdbcc38ed01eadbf861 reverted
# reuse for non-16-byte-aligned constant operands. Preserve only the aligned
# specialization and let the generic masked address calculation handle the rest.
$alignedGuard = 'if (const u32 remainder = data._u32[3] % 0x10; remainder == 0)'
$alignedAddress = 'splat<u64>(data._u32[3]) + zext<u64>(extract(pair.second, 3) & 0x3fff0)'
$genericAddress = 'zext<u64>((extract(a, 3) + extract(b, 3)) & 0x3fff0)'

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

if ($source.Contains('data._u32[3] - remainder') -or
    $source.Contains('(extract(pair.second, 3) + remainder) & 0x3fff0')) {
    throw "Unsafe non-aligned LQX/STQX address reuse is still present."
}

Write-Output "Thor SPU LQX/STQX address contract passed: aligned reuse remains and non-aligned operands use the generic masked fallback."
