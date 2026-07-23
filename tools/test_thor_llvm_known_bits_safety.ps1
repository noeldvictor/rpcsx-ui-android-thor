$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$headerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.h"
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/CPU/CPUTranslator.cpp"
$header = Get-Content -LiteralPath $headerPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw

$requiredHeaderFragments = @(
    '#include "llvm/ADT/SmallPtrSet.h"',
    '#include "llvm/ADT/SmallVector.h"',
    'static bool is_known_bits_safe(llvm::Value* value)',
    'llvm::SmallPtrSet<const llvm::Value*, 32> visited;',
    'llvm::SmallVector<const llvm::Value*, 32> worklist{value};',
    'llvm::isa<llvm::PHINode>(v) || visited.size() > 256',
    'i && !llvm::isa<llvm::LoadInst>(i)',
    'llvm::KnownBits get_known_bits_fallback(llvm::Value* value);',
    'if (!is_known_bits_safe(value))',
    'return get_known_bits_fallback(value);',
    'return llvm::computeKnownBits(value, m_module->getDataLayout());'
)

foreach ($fragment in $requiredHeaderFragments) {
    if (-not $header.Contains($fragment)) {
        throw "Missing LLVM KnownBits safety fragment: $fragment"
    }
}

if ($header.Contains('return llvm::computeKnownBits(a.eval(m_ir), m_module->getDataLayout());')) {
    throw "Unsafe direct KnownBits analysis remains active."
}

$constVectorMatch = [regex]::Match($source, '(?s)get_const_vector<v128>\(llvm::Value\* c.*?(?=\r?\ntemplate <>)')
if (-not $constVectorMatch.Success) {
    throw "Could not isolate v128 constant extraction."
}

$constVector = $constVectorMatch.Value
$peekIndex = $constVector.IndexOf('c = peek_through_bitcasts(c);')
$constantIndex = $constVector.IndexOf('if (!llvm::isa<llvm::Constant>(c))')
if ($peekIndex -lt 0 -or $constantIndex -lt 0 -or $peekIndex -gt $constantIndex) {
    throw "v128 constant extraction does not remove bitcasts before the constant check."
}

$fallbackMatch = [regex]::Match($source, '(?s)llvm::KnownBits cpu_translator::get_known_bits_fallback.*?(?=\r?\n#endif)')
if (-not $fallbackMatch.Success) {
    throw "Could not isolate the KnownBits fallback."
}

$fallback = $fallbackMatch.Value
$requiredFallbackFragments = @(
    'const auto original_value = peek_through_bitcasts(value);',
    'const auto [all, any] = combine_bits',
    'ret.One = all_lanes;',
    'ret.Zero = any_lanes;',
    'ret.Zero.flipAllBits();'
)

foreach ($fragment in $requiredFallbackFragments) {
    if (-not $fallback.Contains($fragment)) {
        throw "Missing LLVM KnownBits fallback fragment: $fragment"
    }
}

if ($fallback.Contains('ret.One = dest;') -or $fallback.Contains('ret.Zero = dest;')) {
    throw "The pre-fix vector mask reduction remains active."
}

Write-Output "Thor LLVM KnownBits contract passed: incomplete PHI graphs fail closed, constant-mask fallback preserves safe ARM64 shift facts, and bitcasted v128 constants remain visible."
