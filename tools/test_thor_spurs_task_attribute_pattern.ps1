$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $repoRoot "app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$signature = 's32 _cellSpursTaskAttributeInitialize(ppu_thread& ppu, vm::ptr<CellSpursTaskAttribute> attribute, u32 revision, u32 sdk_version, vm::cptr<void> elf, u64 ea_context, u32 size_context)'
if (-not $source.Contains($signature)) {
    throw "The task attribute initializer must use the verified six-argument ABI."
}

$oldTail = 'u32 size_context, vm::cptr<CellSpursTaskLsPattern> ls_pattern, vm::cptr<CellSpursTaskArgument> argument)'
if ($source.Contains($oldTail)) {
    throw "The task attribute initializer still treats stale r9 and r10 as arguments."
}

$copy = 'const CellSpursTaskLsPattern caller_pattern ='
$clear = 'std::memset(attribute.get_ptr(), 0, sizeof(CellSpursTaskAttribute));'
$copyIndex = $source.IndexOf($copy, [System.StringComparison]::Ordinal)
$clearIndex = $source.IndexOf($clear, [System.StringComparison]::Ordinal)
if ($copyIndex -lt 0 -or $clearIndex -lt 0 -or $copyIndex -gt $clearIndex) {
    throw "The caller LS pattern must be copied before the attribute buffer is cleared."
}

$requiredFragments = @(
    'const u32 caller_blocks = rx::popcnt128(caller_pattern_128._u);',
    '(caller_pattern_128 & v128::from32r(0xFC000000)) != v128::from32(0);',
    'caller_blocks == alloc_blocks && !caller_uses_management;',
    'view->ls_pattern = caller_pattern;',
    'kept caller LS pattern for %u blocks'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "The caller LS pattern contract is missing: $fragment"
    }
}

# Model a three-block caller pattern with two sparse mutable blocks and the
# final stack block. It must fit a 0x1c00 context and must not become the old
# fallback pattern for blocks 125 through 127.
$selectedBlocks = @(55, 56, 127)
[uint64]$high = 0
[uint64]$low = 0
foreach ($block in $selectedBlocks) {
    if ($block -lt 64) {
        $high = $high -bor ([uint64]1 -shl (63 - $block))
    }
    else {
        $low = $low -bor ([uint64]1 -shl (127 - $block))
    }
}

if ($high -ne [uint64]0x180 -or $low -ne [uint64]1) {
    throw "The sparse LS block model produced the wrong pattern."
}

$contextSize = 0x400 + ($selectedBlocks.Count -shl 11)
if ($contextSize -ne 0x1C00) {
    throw "The sparse LS pattern does not fit the three-block context."
}

$oldFallbackLow = [uint64]7
if ($high -eq 0 -and $low -eq $oldFallbackLow) {
    throw "The sparse caller pattern collapsed to the old top-stack fallback."
}

Write-Output "Thor SPURS task attribute pattern test passed."
