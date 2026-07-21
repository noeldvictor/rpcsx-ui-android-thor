$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$managedProfilePath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt"
$globalProfilePath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt"
$analyzerPath = Join-Path $repoRoot "tools/analyze_thor_cool_title_capture.ps1"
$analyzerTestPath = Join-Path $repoRoot "tools/test_thor_cool_title_capture_analyzer.ps1"
$artifactTestPath = Join-Path $repoRoot "tools/test_thor_cool_title_candidate_artifact.ps1"

$managed = Get-Content -LiteralPath $managedProfilePath -Raw
$global = Get-Content -LiteralPath $globalProfilePath -Raw
$analyzer = Get-Content -LiteralPath $analyzerPath -Raw
$analyzerTest = Get-Content -LiteralPath $analyzerTestPath -Raw
$artifactTest = Get-Content -LiteralPath $artifactTestPath -Raw

$titleStart = $managed.IndexOf('"BLUS30161" to """', [StringComparison]::Ordinal)
if ($titleStart -lt 0) {
    throw "Eternal Sonata Thor managed profile is missing."
}
$titleEnd = $managed.IndexOf('""".trimIndent()', $titleStart, [StringComparison]::Ordinal)
if ($titleEnd -lt 0) {
    throw "Eternal Sonata Thor managed profile terminator is missing."
}
$titleProfile = $managed.Substring($titleStart, $titleEnd - $titleStart)

if ($titleProfile -notmatch '(?m)^\s+Max LLVM Compile Threads: 1\s*$') {
    throw "Eternal Sonata Thor profile must serialize cold PPU LLVM compilation to one thread."
}
if ($titleProfile -match '(?m)^\s+Max LLVM Compile Threads: (?:0|[2-9]|[1-9][0-9]+)\s*$') {
    throw "Eternal Sonata Thor profile contains a conflicting PPU compile-thread value."
}
if ($global -notmatch 'setSetting\("Core@@Max LLVM Compile Threads", "2"') {
    throw "The title-specific thermal cap must not reduce the global Thor compile-thread default."
}
if (-not $analyzer.Contains('"single PPU compile thread" = ''Max LLVM Compile Threads:\s*1''')) {
    throw "Cool-title analyzer does not require runtime proof of the one-thread PPU compile cap."
}
if ($analyzerTest -notmatch 'ppu-compile-cap-missing' -or
    $analyzerTest -notmatch 'single PPU compile thread') {
    throw "Cool-title analyzer contract lacks a missing-cap counterproof."
}
if (-not $artifactTest.Contains('"Max LLVM Compile Threads: 1"')) {
    throw "Candidate artifact contract does not require the packaged managed-profile marker."
}

Write-Output "Thor PPU startup compile thermal-cap contract passed: BLUS30161 uses one LLVM compile thread, other Thor titles retain the two-thread default, and runtime/artifact proof is fail closed."