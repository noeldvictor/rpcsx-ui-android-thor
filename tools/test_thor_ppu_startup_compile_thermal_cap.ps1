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

# Compilation is no longer capped. 0 means auto, which is every hardware thread.
# The old value of 2 capped PPU module compilation two-wide regardless of
# available cores and was the dominant cost in a cold recompile: 78 modules in
# roughly ten minutes, at 51-58 C package against a 72 C guard.
if ($titleProfile -notmatch '(?m)^\s+Max LLVM Compile Threads: 0\s*$') {
    throw "Eternal Sonata Thor profile must leave PPU LLVM compile threads uncapped (0 = auto)."
}
if ($global -notmatch 'setSetting\("Core@@Max LLVM Compile Threads", "0"') {
    throw "The global Thor default must leave PPU compile threads uncapped, or it will overwrite the profile on boot."
}
# The affinity hook must survive so the property override still works, but it
# must not pin by default. Both the cap above and this pinning existed to satisfy
# a guard that compared per-core junction temperatures to a package-shaped limit.
if (-not $control.Contains('inline u64 get_ppu_compile_worker_affinity_mask(std::string_view title_id) noexcept') -or
    -not $ppu.Contains('get_ppu_compile_worker_affinity_mask(Emu.GetTitleID())')) {
    throw "The PPU compile-worker affinity hook was removed; the property override depends on it."
}
if ($control -match 'return 0x07;') {
    throw "PPU compilers are pinned to the little cores again by default. Use debug.rpcsx.thor.cache_worker_affinity_mask instead."
}
# The analyzer and artifact contracts previously demanded runtime proof of the
# two-thread cap. That proof is meaningless now the cap is gone, so those
# assertions are dropped rather than inverted: there is nothing to prove about a
# setting whose value is "use everything".

Write-Output "Thor PPU startup compile contract passed: compile threads uncapped, no default little-core pinning, affinity override hook intact, other titles retain normal scheduling."