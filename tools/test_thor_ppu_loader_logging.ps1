$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$sourcePath = Join-Path $repoRoot "app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\PPUModule.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

function Assert-SourcePattern {
    param(
        [string]$Name,
        [string]$Pattern
    )

    if ($source -notmatch $Pattern) {
        throw "Missing PPU loader logging contract: $Name"
    }
}

Assert-SourcePattern "Android function-export suppression" '#ifndef __ANDROID__[\s\S]*?ppu_loader\.notice\("\*\*\*\* %s export: \(0x%08x\)[\s\S]*?#endif'
Assert-SourcePattern "Android variable-export suppression" '#ifndef __ANDROID__\s*ppu_loader\.notice\("\*\*\*\* %s export: &\[%s\] at 0x%x"[\s\S]*?#endif'
Assert-SourcePattern "Android function-import suppression" '#ifndef __ANDROID__\s*ppu_loader\.notice\("\*\*\*\* %s import: \[%s\] \(0x%08x\) -> 0x%x"[\s\S]*?#endif'

Assert-SourcePattern "Android PPU-debug verbose-success gate" '(?s)static bool ppu_loader_verbose_success_enabled\(\) noexcept\s*\{\s*#ifdef __ANDROID__\s*return g_cfg\.core\.ppu_debug\.get\(\);\s*#else\s*return true;\s*#endif\s*\}'

$verboseGateCount = [regex]::Matches($source, [regex]::Escape('if (ppu_loader_verbose_success_enabled())')).Count
if ($verboseGateCount -ne 10) {
    throw "Expected 10 PPU verbose-success gates, found $verboseGateCount."
}

$gatedLogPatterns = @(
    [pscustomobject]@{ Name = "special exports"; Pattern = '(?s)if \(ppu_loader_verbose_success_enabled\(\)\)\s*\{\s*if \(i < lib\.num_func\)[\s\S]*?ppu_loader\.notice\("\*\* Special: \[%s\][\s\S]*?ppu_loader\.notice\("\*\* Special: &\[%s\]'; Count = 1 },
    [pscustomobject]@{ Name = "roaming SPU discovery"; Pattern = 'if \(ppu_loader_verbose_success_enabled\(\)\)\s*\{\s*ppu_log\.success\("Found valid roaming SPU code'; Count = 1 },
    [pscustomobject]@{ Name = "ELF segments"; Pattern = 'if \(ppu_loader_verbose_success_enabled\(\)\)\s*\{\s*ppu_loader\.notice\("\*\* Segment: p_type'; Count = 3 },
    [pscustomobject]@{ Name = "PRX loaded ranges"; Pattern = 'if \(ppu_loader_verbose_success_enabled\(\)\)\s*\{\s*ppu_loader\.warning\("\*\*\*\* Loaded to'; Count = 1 },
    [pscustomobject]@{ Name = "ELF sections"; Pattern = 'if \(ppu_loader_verbose_success_enabled\(\)\)\s*\{\s*ppu_loader\.notice\("\*\* Section: sh_type'; Count = 4 }
)

foreach ($gate in $gatedLogPatterns) {
    $count = [regex]::Matches($source, $gate.Pattern).Count
    if ($count -ne $gate.Count) {
        throw "Expected $($gate.Count) gated $($gate.Name) log block(s), found $count."
    }
}

Assert-SourcePattern "exported-module summary retained" 'ppu_loader\.notice\("\*\* Exported module'
Assert-SourcePattern "imported-module summary retained" 'ppu_loader\.notice\("\*\* Imported module'
Assert-SourcePattern "invalid function error retained" 'ppu_loader\.error\("\*\*\*\* %s export: \(0x%08x\).*Invalid Function Address'
Assert-SourcePattern "illegal descriptor warning retained" 'ppu_loader\.warning\("\*\*\*\* %s export: \(0x%08x\).*Illegal Descriptor Address'

Write-Output "Thor PPU loader logging contract passed: Android non-debug suppresses successful per-symbol and verbose loader rows while retaining module summaries and linkage failures."
