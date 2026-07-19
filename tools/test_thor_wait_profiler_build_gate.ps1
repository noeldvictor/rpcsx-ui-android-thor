$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$profilerSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/thor_wait_profiler.h") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorWaitProfiler")',
    'System.getenv("RPCSX_THOR_WAIT_PROFILER_BUILD")',
    '"-DRPCSX_THOR_WAIT_PROFILER=${if (rpcsxThorWaitProfiler) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing wait-profiler Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_WAIT_PROFILER "Instrument Android busy-wait sites for Thor diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_WAIT_PROFILER=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing wait-profiler CMake gate: $fragment"
    }
}

if ($profilerSource -notmatch '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_WAIT_PROFILER\)[\s\S]*?#else\s+\tFORCE_INLINE void profiled_busy_wait\(site, usz cycles = 3000\) noexcept\s+\t\{\s+\t\trx::busy_wait\(cycles\);\s+\t\}\s+#endif') {
    throw "Android's default wait-profiler path is not a direct, always-inline busy wait."
}

if ($gradleSource -match 'rpcsxThorWaitProfiler[^\r\n]*\?:\s*true') {
    throw "The Android wait profiler must remain disabled by default."
}

Write-Output "Thor wait-profiler build gate passed: Android defaults to direct busy waits and diagnostics require an explicit build-time opt-in."
