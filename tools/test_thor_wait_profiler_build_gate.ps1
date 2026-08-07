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

# The disabled branch must add no cost: every stub in it is either an empty body
# or a direct call to rx::busy_wait.
#
# This used to pin the exact text of the whole #else block, which asserted that
# profiled_busy_wait was the *only* thing in it. That broke the moment a second
# stub was needed: lv2_short_timeout_yield is not a busy wait, so it calls
# record() directly, and record() therefore needs a no-op here too. The contract
# was never "one function"; it was "no overhead when disabled". Check that.
# Anchor on the *last* #else, the one closing the namespace, with a GREEDY
# prefix. Regex.Match returns the leftmost match, so any non-greedy form starts
# at log_summary's nested "#ifdef ANDROID ... #else (void)total;" and then runs
# its tail all the way to the final #endif, capturing the enabled branch as
# though it were the disabled one. Three attempts got this wrong before the
# captured text was actually printed and looked at, which is the lesson: when a
# pattern keeps not matching, print what it captured instead of editing it
# again.
#
# The greedy '^[\s\S]*' forces #else to be the final one, whose #endif is
# followed by the closing brace of namespace thor_wait at end of file.
$disabledMatch = [regex]::Match(
    $profilerSource,
    '^[\s\S]*#else([\s\S]*?)#endif\s*\}\s*$')
if (-not $disabledMatch.Success) {
    throw "Could not find the profiler-disabled branch in thor_wait_profiler.h."
}
$disabled = $disabledMatch.Groups[1].Value

if ($disabled -notmatch 'FORCE_INLINE void profiled_busy_wait\(site, usz cycles = 3000\) noexcept\s*\{\s*rx::busy_wait\(cycles\);\s*\}') {
    throw "Android's default wait-profiler path is not a direct, always-inline busy wait."
}

if ($disabled -notmatch 'FORCE_INLINE void record\(site, usz\) noexcept\s*\{\s*\}') {
    throw "The profiler-disabled branch has no no-op record() stub. Sites that are not busy waits call record() directly, so without it a profiler-off build fails to compile."
}

# Nothing in the disabled branch may touch the counters, which is what would
# reintroduce cost on the default path.
foreach ($banned in @('g_stats', 'fetch_add', 'log_summary', '__android_log_print')) {
    if ($disabled -match [regex]::Escape($banned)) {
        throw "The profiler-disabled branch references '$banned'. That branch must add no cost at all when diagnostics are off."
    }
}

if ($gradleSource -match 'rpcsxThorWaitProfiler[^\r\n]*\?:\s*true') {
    throw "The Android wait profiler must remain disabled by default."
}

Write-Output "Thor wait-profiler build gate passed: Android defaults to direct busy waits and diagnostics require an explicit build-time opt-in."
