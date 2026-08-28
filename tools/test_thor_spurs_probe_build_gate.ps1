$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$headerSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/thor_spurs_probe.h") -Raw
$kernelSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_spu.cpp") -Raw
$spuThreadSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp") -Raw
$hleSpursSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/ps3fw/cellSpursSpu.cpp") -Raw
$eventSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_event.cpp") -Raw
$semaphoreSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp") -Raw
$timerSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_timer.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorSpursProbe")',
    'System.getenv("RPCSX_THOR_SPURS_PROBE_BUILD")',
    '"-DRPCSX_THOR_SPURS_PROBE=${if (rpcsxThorSpursProbe) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing SPURS-probe Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_SPURS_PROBE "Instrument Android SPURS waits for Thor diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_SPURS_PROBE=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing SPURS-probe CMake gate: $fragment"
    }
}

if ($headerSource -notmatch '#if defined\(__ANDROID__\) && !defined\(RPCSX_THOR_SPURS_PROBE\)[\s\S]*?static FORCE_INLINE constexpr bool thor_spurs_probe_enabled\(\) noexcept[\s\S]*?return false;[\s\S]*?#define THOR_SPURS_PROBE_LOG_PPU_WAIT\(\.\.\.\) \(\(void\)0\)[\s\S]*?#else[\s\S]*?void thor_spurs_probe_log_ppu_wait[\s\S]*?#define THOR_SPURS_PROBE_LOG_PPU_WAIT\(\.\.\.\)[\s\S]*?thor_spurs_probe_log_ppu_wait\(__VA_ARGS__\)[\s\S]*?#endif') {
    throw "Normal Android PPU syscall probe hooks must discard arguments while diagnostic/desktop builds retain the logger."
}

if ($kernelSource -notmatch '#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_SPURS_PROBE\)[\s\S]*?__system_property_get\("debug\.rpcsx\.thor\.spurs_probe", value\)[\s\S]*?Thor SPURS PPU wait probe:[\s\S]*?Thor SPURS probe:[\s\S]*?#else\s+static FORCE_INLINE constexpr void\s+thor_spurs_probe_log[\s\S]*?#endif') {
    throw "Kernel SPURS probe state/reporting is not wholly excluded from normal Android builds."
}

if ($spuThreadSource -notmatch '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_SPURS_PROBE\)[\s\S]*?__system_property_get\("debug\.rpcsx\.thor\.spurs_probe", value\)[\s\S]*?Thor SPURS wait probe:[\s\S]*?#else\s+enum class thor_spurs_wait_event[\s\S]*?static FORCE_INLINE constexpr void\s+thor_spurs_wait_probe_log[\s\S]*?#endif') {
    throw "SPU reservation/wait diagnostics are not wholly excluded from normal Android builds."
}

if ($hleSpursSource -notmatch '#if defined\(ANDROID\) && !defined\(RPCSX_THOR_SPURS_PROBE\)[\s\S]*?static FORCE_INLINE constexpr bool thor_hle_spurs_diagnostics\(\) noexcept[\s\S]*?return false;[\s\S]*?#else[\s\S]*?__system_property_get\("debug\.rpcsx\.thor\.spurs_probe", value\)[\s\S]*?#endif') {
    throw "HLE SPURS hot-loop diagnostics are not excluded from normal Android builds."
}

$hleDiagnosticGateCount = [regex]::Matches($hleSpursSource, 'thor_hle_spurs_diagnostics\(\)').Count - 2
if ($hleDiagnosticGateCount -ne 6) {
    throw "Expected 6 HLE SPURS hot-loop diagnostic gates, found $hleDiagnosticGateCount."
}

$ppuSources = @($eventSource, $semaphoreSource, $timerSource)
$ppuHookCount = ($ppuSources | ForEach-Object {
    [regex]::Matches($_, 'THOR_SPURS_PROBE_LOG_PPU_WAIT\(').Count
} | Measure-Object -Sum).Sum
if ($ppuHookCount -ne 9) {
    throw "Expected all 9 restorable PPU SPURS-probe hooks, found $ppuHookCount."
}
if (($ppuSources | Where-Object { $_ -cmatch 'thor_spurs_probe_log_ppu_wait\(' }).Count -ne 0) {
    throw "Normal Android PPU syscall sources contain a direct probe call that would still evaluate disabled arguments."
}

$spuHookCount = [regex]::Matches($spuThreadSource, 'thor_spurs_wait_probe_log\(\*this,').Count
if ($spuHookCount -ne 4) {
    throw "Expected all 4 restorable SPU wait hooks, found $spuHookCount."
}

if ($gradleSource -match 'rpcsxThorSpursProbe[^\r\n]*\?:\s*true') {
    throw "The Android SPURS probe must remain disabled by default."
}

Write-Output "Thor SPURS-probe build gate passed: normal Android discards all PPU probe arguments and omits PPU/SPU probe calls and state while explicit diagnostics and desktop behavior remain."
