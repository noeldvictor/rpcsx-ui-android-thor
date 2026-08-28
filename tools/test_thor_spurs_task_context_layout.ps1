$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $repoRoot "app\src\main\cpp\rpcsx\ps3fw\cellSpursSpu.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$packedOffset = 'contextSaveStorage + 0x400 + (savedLsBlock << 11)'
$packedOffsetCount = ([regex]::Matches($source, [regex]::Escape($packedOffset))).Count
if ($packedOffsetCount -ne 2) {
    throw "The SPURS save and restore paths must both use the packed context offset."
}

$advance = 'savedLsBlock++;'
$advanceCount = ([regex]::Matches($source, [regex]::Escape($advance))).Count
if ($advanceCount -ne 2) {
    throw "The SPURS save and restore paths must both advance the packed context slot."
}

$sparseOffset = 'contextSaveStorage + 0x400 + ((i - 6) << 11)'
if ($source.Contains($sparseOffset)) {
    throw "The SPURS context path still uses the sparse LS block number as a context offset."
}

$selectedLsBlocks = @(6, 64, 127)
$contextOffsets = @()
$sourceOffsets = @()
for ($slot = 0; $slot -lt $selectedLsBlocks.Count; $slot++) {
    $contextOffsets += 0x400 + ($slot -shl 11)
    $sourceOffsets += 0x3000 + (($selectedLsBlocks[$slot] - 6) -shl 11)
}

$expectedContextOffsets = @(0x400, 0xC00, 0x1400)
$expectedSourceOffsets = @(0x3000, 0x20000, 0x3F800)
if ((Compare-Object $contextOffsets $expectedContextOffsets) -or
    (Compare-Object $sourceOffsets $expectedSourceOffsets)) {
    throw "The sparse LS pattern did not map to compact context slots."
}

$allocationSize = 0x400 + ($selectedLsBlocks.Count -shl 11)
$lastCopyEnd = $contextOffsets[-1] + 0x800
if ($lastCopyEnd -ne $allocationSize) {
    throw "The compact context copy does not end at the allocation boundary."
}

Write-Output "Thor SPURS task context layout test passed."
