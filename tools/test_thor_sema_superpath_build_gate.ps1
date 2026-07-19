$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$semaphoreSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_semaphore.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorSemaSuperpath")',
    'System.getenv("RPCSX_THOR_SEMA_SUPERPATH_BUILD")',
    '"-DRPCSX_THOR_SEMA_SUPERPATH=${if (rpcsxThorSemaSuperpath) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing semaphore-superpath Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_SEMA_SUPERPATH "Build the Eternal Sonata semaphore experiment on Android" OFF)',
    'add_compile_definitions(RPCSX_THOR_SEMA_SUPERPATH=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing semaphore-superpath CMake gate: $fragment"
    }
}

$gate = '#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_SEMA_SUPERPATH\)'
$gateCount = [regex]::Matches($semaphoreSource, $gate).Count
if ($gateCount -ne 10) {
    throw "Expected 10 semaphore-superpath Android build guards, found $gateCount."
}

if ($semaphoreSource -notmatch ($gate + '\s+enum class thor_es_sema_superpath_mode[\s\S]*?g_thor_es_sema_fast_cache\{\};\s+#endif\s+\s*#if !defined\(__ANDROID__\) \|\| defined\(RPCSX_THOR_DRAW_STREAM_PROBE\)')) {
    throw "Semaphore-superpath state and cache are not wholly excluded from normal Android builds."
}

if ($semaphoreSource -notmatch ($gate + '\s+static thor_es_sema_superpath_mode[\s\S]*?static void log_thor_es_sema_superpath[\s\S]*?#endif\s+\s*lv2_sema::lv2_sema')) {
    throw "Semaphore-superpath parsing, fast actions, and logging are not wholly excluded from normal Android builds."
}

$guardedCallPatterns = @(
    ($gate + '\s+record_thor_es_sema_created_id\(created_id\);\s+#endif'),
    ($gate + '\s+record_thor_es_sema_destroyed_id\(sem_id\);\s+#endif'),
    ($gate + '\s+if \(is_thor_es_sema_superpath_candidate\(ppu, false\)\)[\s\S]*?#endif\s+\s*const auto sem = idm::get<lv2_obj, lv2_sema>'),
    ('if \(!sem\) \{\s+' + $gate + '\s+if \(is_thor_es_sema_superpath_candidate\(ppu, false\)\)[\s\S]*?#endif\s+\s*return CELL_ESRCH;'),
    ($gate + '\s+record_thor_es_sema_fast_object\(sem_id, sem\.ptr\.get\(\)\);\s+#endif\s+\s*if \(sem\.ret\)'),
    ($gate + '\s+if \(is_thor_es_sema_superpath_candidate\(ppu, true\)\)[\s\S]*?#endif\s+\s*const auto sem = idm::get<lv2_obj, lv2_sema>'),
    ('if \(!sem\) \{\s+' + $gate + '\s+if \(is_thor_es_sema_superpath_candidate\(ppu, true\)\)[\s\S]*?#endif\s+\s*return CELL_ESRCH;'),
    ($gate + '\s+record_thor_es_sema_fast_object\(sem_id, sem\.ptr\.get\(\)\);\s+#endif\s+\s*if \(count <= 0\)')
)

foreach ($pattern in $guardedCallPatterns) {
    if ($semaphoreSource -notmatch $pattern) {
        throw "A semaphore-superpath hot-path hook is not protected by the Android build gate: $pattern"
    }
}

$requiredRuntimeFragments = @(
    'debug.rpcsx.thor.es_sema_superpath',
    'RPCSX_THOR_ES_SEMA_SUPERPATH',
    'RPCS3_ES_SEMA_ESRCH_SUPERPATH',
    'try_thor_es_sema_fast_wait',
    'try_thor_es_sema_fast_post',
    'fast-direct-wait',
    'fast-direct-post',
    'fast-zero-esrch',
    'fast-cached-esrch',
    'fast-destroyed-esrch',
    'fast-uncreated-esrch',
    'Eternal Sonata semaphore superpath:'
)

foreach ($fragment in $requiredRuntimeFragments) {
    if (-not $semaphoreSource.Contains($fragment)) {
        throw "Explicit diagnostic build lost semaphore-superpath behavior: $fragment"
    }
}

$expectedHookCounts = @{
    'record_thor_es_sema_created_id\(' = 2
    'record_thor_es_sema_destroyed_id\(' = 2
    'record_thor_es_sema_cached_esrch_id\(' = 3
    'record_thor_es_sema_fast_object\(' = 3
    'is_thor_es_sema_superpath_candidate\(' = 5
}

foreach ($entry in $expectedHookCounts.GetEnumerator()) {
    $actual = [regex]::Matches($semaphoreSource, $entry.Key).Count
    if ($actual -ne $entry.Value) {
        throw "Expected $($entry.Value) restorable hooks matching $($entry.Key), found $actual."
    }
}

if ($gradleSource -match 'rpcsxThorSemaSuperpath[^\r\n]*\?:\s*true') {
    throw "The Android semaphore superpath must remain disabled by default."
}

Write-Output "Thor semaphore-superpath build gate passed: normal Android omits the inactive experiment while explicit diagnostics and desktop behavior remain."
