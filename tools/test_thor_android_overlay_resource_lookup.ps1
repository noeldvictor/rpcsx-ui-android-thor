$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$headerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/overlay_controls.h"
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Overlays/overlay_controls.cpp"
$header = Get-Content -LiteralPath $headerPath -Raw
$source = Get-Content -LiteralPath $sourcePath -Raw

function Assert-Contains([string]$Text, [string]$Fragment, [string]$Message) {
    if (-not $Text.Contains($Fragment)) {
        throw $Message
    }
}

Assert-Contains $header 'image_info(const std::string& filename, bool grayscaled = false, bool log_failure = true);' 'Ordinary image loads no longer log failures by default.'
Assert-Contains $source 'image_info::image_info(const std::string& filename, bool grayscaled, bool log_failure)' 'Image loader implementation no longer accepts the scoped log control.'
Assert-Contains $source 'if (log_failure)' 'Image loader no longer preserves ordinary failure logging.'
Assert-Contains $source 'std::make_unique<image_info>(image_path, false, false)' 'Android config lookup no longer suppresses per-path failure broadcasts.'
Assert-Contains $source 'missing_android_resources++' 'Android missing-resource aggregation disappeared.'
Assert-Contains $source 'Android overlay UI resources: %u of %u unavailable in the config directory; skipped desktop fallback paths.' 'Android aggregate warning disappeared.'

$loadStart = $source.IndexOf('void resource_config::load_files()')
$loadEnd = $source.IndexOf('void resource_config::free_resources()', $loadStart)
if ($loadStart -lt 0 -or $loadEnd -le $loadStart) {
    throw 'Could not isolate resource_config::load_files().'
}
$loadBody = $source.Substring($loadStart, $loadEnd - $loadStart)

$androidGuard = $loadBody.IndexOf('#ifdef __ANDROID__')
$configLookup = $loadBody.IndexOf('std::make_unique<image_info>(image_path, false, false)')
$desktopElse = $loadBody.IndexOf('#else', $configLookup)
$relativeLookup = $loadBody.IndexOf('std::string src = "Icons/ui/" + res;', $desktopElse)
$executableLookup = $loadBody.IndexOf('readlink("/proc/self/exe"', $relativeLookup)
$push = $loadBody.IndexOf('texture_raw_data.push_back', $executableLookup)
$aggregate = $loadBody.IndexOf('Android overlay UI resources:', $push)

if ($androidGuard -lt 0 -or
    $configLookup -le $androidGuard -or
    $desktopElse -le $configLookup -or
    $relativeLookup -le $desktopElse -or
    $executableLookup -le $relativeLookup -or
    $push -le $executableLookup -or
    $aggregate -le $push) {
    throw 'Android config-only branch or desktop fallback ordering changed.'
}

$resourceNames = @(
    'fade_top.png', 'fade_bottom.png', 'select.png', 'start.png',
    'cross.png', 'circle.png', 'triangle.png', 'square.png',
    'L1.png', 'R1.png', 'L2.png', 'R2.png',
    'save.png', 'new.png', 'spinner-24.png'
)
foreach ($name in $resourceNames) {
    Assert-Contains $loadBody "`"$name`"" "Overlay resource list lost $name."
}

$silentLookupCount = ([regex]::Matches($loadBody, [regex]::Escape('std::make_unique<image_info>(image_path, false, false)'))).Count
if ($silentLookupCount -ne 1) {
    throw "Expected one Android silent config lookup callsite, found $silentLookupCount."
}

$desktopRelativeCount = ([regex]::Matches($loadBody, [regex]::Escape('std::string src = "Icons/ui/" + res;'))).Count
if ($desktopRelativeCount -ne 1) {
    throw "Expected the desktop relative fallback to remain exactly once, found $desktopRelativeCount."
}

Write-Output 'Thor Android overlay resource contract passed: one config probe per icon, desktop-only fallback paths preserved, ordinary image errors preserved, aggregate warning retained.'
