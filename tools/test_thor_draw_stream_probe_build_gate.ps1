$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$headerSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/thor_es_draw_stream_probe.h") -Raw
$semaphoreSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp") -Raw
$ttySource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_tty.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorDrawStreamProbe")',
    'System.getenv("RPCSX_THOR_DRAW_STREAM_PROBE_BUILD")',
    '"-DRPCSX_THOR_DRAW_STREAM_PROBE=${if (rpcsxThorDrawStreamProbe) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing draw-stream Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_DRAW_STREAM_PROBE "Instrument Eternal Sonata draw-stream handoff diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_DRAW_STREAM_PROBE=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing draw-stream CMake gate: $fragment"
    }
}

if ($headerSource -notmatch '#if defined\(__ANDROID__\) && !defined\(RPCSX_THOR_DRAW_STREAM_PROBE\)\s+static FORCE_INLINE constexpr void\s+thor_es_draw_stream_probe_tty[\s\S]*?#else[\s\S]*?void thor_es_draw_stream_probe_tty[\s\S]*?#endif') {
    throw "Normal Android TTY call sites do not see the compile-time draw-stream no-op."
}

if ($semaphoreSource -notmatch '#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_DRAW_STREAM_PROBE\)\s+namespace \{[\s\S]*?debug\.rpcsx\.thor\.es_draw_stream_probe[\s\S]*?void thor_es_draw_stream_probe_tty[\s\S]*?#else\s+static FORCE_INLINE constexpr void\s+maybe_thor_es_draw_stream_probe_before_post[\s\S]*?static FORCE_INLINE constexpr void\s+maybe_thor_es_draw_stream_probe_after_wait[\s\S]*?#endif\s+\s*static thor_es_sema_superpath_mode') {
    throw "The draw-stream state, repair, reports, and semaphore hooks are not wholly excluded from normal Android builds."
}

$afterWaitHooks = [regex]::Matches($semaphoreSource, 'maybe_thor_es_draw_stream_probe_after_wait\(ppu, sem_id\);').Count
if ($afterWaitHooks -ne 3) {
    throw "Expected all 3 restorable draw-stream wait hooks, found $afterWaitHooks."
}

$beforePostHooks = [regex]::Matches($semaphoreSource, 'maybe_thor_es_draw_stream_probe_before_post\(ppu, sem_id, count\);').Count
if ($beforePostHooks -ne 1) {
    throw "Expected the restorable draw-stream post hook, found $beforePostHooks."
}

$ttyHooks = [regex]::Matches($ttySource, 'thor_es_draw_stream_probe_tty\(ppu, msg\);').Count
if ($ttyHooks -ne 1) {
    throw "Expected the restorable draw-stream TTY hook, found $ttyHooks."
}

if ($gradleSource -match 'rpcsxThorDrawStreamProbe[^\r\n]*\?:\s*true') {
    throw "The Android draw-stream probe must remain disabled by default."
}

Write-Output "Thor draw-stream build gate passed: normal Android omits semaphore/TTY diagnostic work while explicit diagnostics and desktop behavior remain."
