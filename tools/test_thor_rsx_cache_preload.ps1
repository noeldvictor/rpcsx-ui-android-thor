$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$programCachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/ProgramStateCache.h"
$vkRenderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKGSRender.cpp"
$cacheSource = Get-Content -LiteralPath $cachePath -Raw
$programCacheSource = Get-Content -LiteralPath $programCachePath -Raw
$vkRenderSource = Get-Content -LiteralPath $vkRenderPath -Raw

$claim = 'while (((pos = processed++) < stop_at) && !Emu.IsStopped())'
$claimCount = [regex]::Matches($cacheSource, [regex]::Escape($claim)).Count
if ($claimCount -ne 2) {
    throw "Expected dynamic atomic claims in load and compile workers, found $claimCount."
}

$sentinelCount = [regex]::Matches($cacheSource, '(?m)^\s*processed--;\s*$').Count
if ($sentinelCount -ne 2) {
    throw "Expected one sentinel rollback in each dynamic worker, found $sentinelCount."
}

$workerTypeCount = [regex]::Matches($cacheSource, [regex]::Escape('std::function<void(u32)>')).Count
if ($workerTypeCount -ne 3) {
    throw "Expected two dynamic callbacks plus the single-bound await contract, found $workerTypeCount."
}

$requiredCacheFragments = @(
    'worker(entry_count);',
    '__system_property_get("debug.rpcsx.thor.rsx_cache_workers", value)',
    '__system_property_get("debug.rpcsx.thor.rsx_cache_preload_limit", value)',
    'nb_workers = std::min<uint>(nb_workers, 2);',
    'static uint get_preload_compile_worker_count(uint load_workers)',
    'get_android_worker_override() <= 0)',
    'rsx_log.notice("Shader cache preload workers: load=%u, compile=%u", load_workers, compile_workers);',
    'load_shaders(load_workers, unpacked, directory_path, entries, entry_count, dlg);',
    'compile_shaders(compile_workers, unpacked, entry_count, dlg, std::forward<Args>(args)...);',
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
if ($cacheSource -notmatch 'get_preload_compile_worker_count\(uint load_workers\)[\s\S]*?shader_compiler_threads_count == 0[\s\S]*?get_android_worker_override\(\) <= 0[\s\S]*?return 1;[\s\S]*?return load_workers;') {
    throw "Android auto mode no longer keeps two load workers while serializing hot pipeline compilation."
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

Write-Output "Thor RSX cache preload contract passed: dynamic work sharing, two load/one compile Android auto mode, explicit worker overrides, opt-in oldest-first pipeline limit, configured cache-miss fallback, trace-only Android program logging."
