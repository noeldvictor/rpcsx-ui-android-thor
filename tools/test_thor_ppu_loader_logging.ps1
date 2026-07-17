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

Assert-SourcePattern "exported-module summary retained" 'ppu_loader\.notice\("\*\* Exported module'
Assert-SourcePattern "imported-module summary retained" 'ppu_loader\.notice\("\*\* Imported module'
Assert-SourcePattern "invalid function error retained" 'ppu_loader\.error\("\*\*\*\* %s export: \(0x%08x\).*Invalid Function Address'
Assert-SourcePattern "illegal descriptor warning retained" 'ppu_loader\.warning\("\*\*\*\* %s export: \(0x%08x\).*Illegal Descriptor Address'

Write-Output "Thor PPU loader logging contract passed: Android suppresses successful per-symbol rows while retaining module summaries and linkage failures."
