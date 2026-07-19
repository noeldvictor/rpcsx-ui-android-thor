$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$programCachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/ProgramStateCache.h"
$vkRenderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKGSRender.cpp"
$thorProfilePath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/performance/ThorPerformanceProfile.kt"
$gameSettingsPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt"
$profileToolPath = Join-Path $repoRoot "tools/push_eternal_sonata_thor_profile.ps1"
$cacheSource = Get-Content -LiteralPath $cachePath -Raw
$programCacheSource = Get-Content -LiteralPath $programCachePath -Raw
$vkRenderSource = Get-Content -LiteralPath $vkRenderPath -Raw
$thorProfileSource = Get-Content -LiteralPath $thorProfilePath -Raw
$gameSettingsSource = Get-Content -LiteralPath $gameSettingsPath -Raw
$profileToolSource = Get-Content -LiteralPath $profileToolPath -Raw

$claim = 'while (((pos = processed++) < stop_at) && !Emu.IsStopped())'
$claimCount = [regex]::Matches($cacheSource, [regex]::Escape($claim)).Count
if ($claimCount -ne 2) {
    throw "Expected the load worker and default compile worker to preserve one-atomic dynamic claims, found $claimCount."
}

$sentinelCount = [regex]::Matches($cacheSource, '(?m)^\s*processed--;\s*$').Count
if ($sentinelCount -ne 2) {
    throw "Expected one sentinel rollback in the load and default compile workers, found $sentinelCount."
}

$compileClaim = 'while (((pos = next++) < stop_at) && !Emu.IsStopped())'
$compileClaimCount = [regex]::Matches($cacheSource, [regex]::Escape($compileClaim)).Count
$compileSentinelCount = [regex]::Matches($cacheSource, '(?m)^\s*next--;\s*$').Count
if ($compileClaimCount -ne 2 -or $compileSentinelCount -ne 2) {
    throw "Expected budgeted load and compile claims with separate completion counters and sentinel rollbacks."
}

if (-not $cacheSource.Contains('if (!compile_budget_ms)') -or
    -not $cacheSource.Contains('Preserve the original one-atomic fast path when the experiment is disabled.')) {
    throw "Default-off RSX compilation no longer preserves the original one-atomic fast path."
}

$workerTypeCount = [regex]::Matches($cacheSource, [regex]::Escape('std::function<void(u32)>')).Count
if ($workerTypeCount -ne 4) {
    throw "Expected load, default compile, budgeted compile, and single-bound await callbacks, found $workerTypeCount."
}

$requiredCacheFragments = @(
    'worker(entry_count);',
    '__system_property_get("debug.rpcsx.thor.rsx_cache_workers", value)',
    '__system_property_get("debug.rpcsx.thor.rsx_cache_preload_limit", value)',
    'parsed < 0 || parsed > 16',
    'worker_override == 0 || g_cfg.video.shader_compiler_threads_count == 0',
    'nb_workers = std::min<uint>(nb_workers, 2);',
    'rsx_log.notice("Shader cache preload workers: load=%u, compile=%u", preload_workers, preload_workers);',
    'load_shaders(preload_workers, unpacked, directory_path, entries, entry_count, load_budget_ms, dlg);',
    'compile_shaders(preload_workers, unpacked, entry_count, dlg, compile_budget_ms, std::forward<Args>(args)...);',
    'lhs.mtime != rhs.mtime ? lhs.mtime < rhs.mtime : lhs.name < rhs.name',
    'entry_count = static_cast<u32>(preload_limit);',
    'will compile on demand'
)

foreach ($fragment in $requiredCacheFragments) {
    if (-not $cacheSource.Contains($fragment)) {
        throw "Missing RSX preload contract fragment: $fragment"
    }
}

$forbiddenCacheFragments = @(
    'std::function<void(u32, u32)>',
    'per_thread_entries',
    'worker(start_at, stop_at)'
)

foreach ($fragment in $forbiddenCacheFragments) {
    if ($cacheSource.Contains($fragment)) {
        throw "Static RSX preload partitioning returned: $fragment"
    }
}

if ($cacheSource.Contains('async_with_interpreter') -or $cacheSource.Contains('Shader cache preload deferred')) {
    throw "The retired interpreter/deferred preload path returned."
}
if ($cacheSource -match 'get_preload_compile_worker_count' -or
    $cacheSource -notmatch 'const uint preload_workers = get_preload_worker_count\(\);[\s\S]*?load_shaders\(preload_workers[\s\S]*?compile_shaders\(preload_workers') {
    throw "RSX preload no longer shares the same dynamic worker count across load and compile stages."
}
if ($thorProfileSource -notmatch 'PROFILE_VERSION\s*=\s*14' -or
    $thorProfileSource -notmatch 'setSetting\("Video@@Shader Compiler Threads", "0"' -or
    $gameSettingsSource -notmatch 'Shader Compiler Threads:\s*0' -or
    $profileToolSource -notmatch '\[int\]\$ShaderCompilerThreads\s*=\s*0') {
    throw "Thor managed/default profiles no longer select automatic capped RSX preload scheduling."
}
if (-not $programCacheSource.Contains('auto result = backend_traits::build_pipeline(') -or
    -not $vkRenderSource.Contains('shadermode != shader_mode::recompiler, true, m_pipeline_layout')) {
    throw "Limited preload no longer retains the configured runtime pipeline cache-miss path."
}

$traceLine = 'rsx_log.trace("Add program (vp id = %d, fp id = %d)", vertex_program.id, fragment_program.id);'
$noticeLine = 'rsx_log.notice("Add program (vp id = %d, fp id = %d)", vertex_program.id, fragment_program.id);'
$traceIndex = $programCacheSource.IndexOf($traceLine)
$noticeIndex = $programCacheSource.IndexOf($noticeLine)
$androidIndex = if ($traceIndex -ge 0) { $programCacheSource.LastIndexOf('#ifdef __ANDROID__', $traceIndex) } else { -1 }
$elseIndex = if ($traceIndex -ge 0) { $programCacheSource.IndexOf('#else', $traceIndex) } else { -1 }
$endifIndex = if ($noticeIndex -ge 0) { $programCacheSource.IndexOf('#endif', $noticeIndex) } else { -1 }
if ($androidIndex -lt 0 -or $traceIndex -le $androidIndex -or $elseIndex -le $traceIndex -or
    $noticeIndex -le $elseIndex -or $endifIndex -le $noticeIndex) {
    throw "Android Add-program logging is not trace-only with desktop notice behavior preserved."
}

Write-Output "Thor RSX cache preload contract passed: zero-valued auto override, managed auto profile migration, dynamic work sharing, default and budgeted load/compile paths, positive worker overrides, opt-in oldest-first pipeline and load-time limits, configured cache-miss fallback, trace-only Android program logging."
