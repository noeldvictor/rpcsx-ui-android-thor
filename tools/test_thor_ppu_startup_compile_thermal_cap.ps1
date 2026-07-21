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
$controlPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/cache_phase_pacing.h"
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$control = Get-Content -LiteralPath $controlPath -Raw
$ppu = Get-Content -LiteralPath $ppuPath -Raw

$titleStart = $managed.IndexOf('"BLUS30161" to """', [StringComparison]::Ordinal)
if ($titleStart -lt 0) {
    throw "Eternal Sonata Thor managed profile is missing."
}
$titleEnd = $managed.IndexOf('""".trimIndent()', $titleStart, [StringComparison]::Ordinal)
if ($titleEnd -lt 0) {
    throw "Eternal Sonata Thor managed profile terminator is missing."
}
$titleProfile = $managed.Substring($titleStart, $titleEnd - $titleStart)

if ($titleProfile -notmatch '(?m)^\s+Max LLVM Compile Threads: 2\s*$') {
    throw "Eternal Sonata Thor profile must use two cold PPU LLVM compile threads."
}
if ($titleProfile -match '(?m)^\s+Max LLVM Compile Threads: (?:0|1|[3-9]|[1-9][0-9]+)\s*$') {
    throw "Eternal Sonata Thor profile contains a conflicting PPU compile-thread value."
}
if ($global -notmatch 'setSetting\("Core@@Max LLVM Compile Threads", "2"') {
    throw "The Eternal Sonata compile-thread count must match the bounded global Thor default."
}
if (-not $control.Contains('inline u64 get_ppu_compile_worker_affinity_mask(std::string_view title_id) noexcept') -or
    -not $control.Contains('return 0x07;') -or
    -not $ppu.Contains('get_ppu_compile_worker_affinity_mask(Emu.GetTitleID())')) {
    throw "Eternal Sonata PPU compilers are not default-pinned to the three little cores."
}
if (-not $analyzer.Contains('"two little-core PPU compile threads" = ''Max LLVM Compile Threads:\s*2''')) {
    throw "Cool-title analyzer does not require runtime proof of the two-thread PPU compile cap."
}
if ($analyzerTest -notmatch 'ppu-compile-cap-missing' -or
    $analyzerTest -notmatch 'two little-core PPU compile threads') {
    throw "Cool-title analyzer contract lacks a missing-cap counterproof."
}
if (-not $artifactTest.Contains('"Max LLVM Compile Threads: 2"')) {
    throw "Candidate artifact contract does not require the packaged managed-profile marker."
}

Write-Output "Thor PPU startup compile thermal-cap contract passed: BLUS30161 uses two LLVM workers pinned to 0x07, runtime threads and other titles retain normal scheduling, and runtime/artifact proof is fail closed."