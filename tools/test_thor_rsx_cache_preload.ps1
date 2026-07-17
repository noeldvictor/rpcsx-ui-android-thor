$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$programCachePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/ProgramStateCache.h"
$cacheSource = Get-Content -LiteralPath $cachePath -Raw
$programCacheSource = Get-Content -LiteralPath $programCachePath -Raw
$vkRenderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKGSRender.cpp"
$inputMacroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$speedSprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"
$vkRenderSource = Get-Content -LiteralPath $vkRenderPath -Raw
$inputMacroSource = Get-Content -LiteralPath $inputMacroPath -Raw
$speedSprintSource = Get-Content -LiteralPath $speedSprintPath -Raw

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
    'nb_workers = std::min<uint>(nb_workers, 2);',
    'rsx_log.notice("Shader cache preload workers: %u", nb_workers);'
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

$requiredDeferFragments = @(
    '__system_property_get("debug.rpcsx.thor.rsx_cache_preload", value)',
    'std::string_view(value, static_cast<usz>(length)) == "defer"',
    'if (android_defer_shader_cache_preload() && g_cfg.video.shadermode == shader_mode::async_with_interpreter)',
    'Shader cache preload deferred on Android; shader interpreter fallback will cover asynchronous pipeline misses'
)

foreach ($fragment in $requiredDeferFragments) {
    if (-not $cacheSource.Contains($fragment)) {
        throw "Missing deferred RSX preload contract fragment: $fragment"
    }
}

$deferProbeIndex = $vkRenderSource.IndexOf('if (rsx::android_defer_shader_cache_preload())')
$instanceCreateIndex = $vkRenderSource.IndexOf('if (!m_instance.create("RPCS3"))')
if ($deferProbeIndex -lt 0 -or $instanceCreateIndex -le $deferProbeIndex) {
    throw "The Android deferred-preload mode is not selected before Vulkan resource creation."
}

$requiredVulkanFragments = @(
    'if (g_cfg.video.shadermode == shader_mode::async_recompiler)',
    'g_cfg.video.shadermode.set(shader_mode::async_with_interpreter);',
    'Android shader cache preload defer enabled; using shader interpreter fallback for pipeline misses',
    'Android shader cache preload defer ignored because the configured shader mode has no asynchronous interpreter fallback'
)

foreach ($fragment in $requiredVulkanFragments) {
    if (-not $vkRenderSource.Contains($fragment)) {
        throw "Missing Vulkan deferred-preload correctness fragment: $fragment"
    }
}

if ($inputMacroSource -notmatch '\[ValidateSet\("preload",\s*"defer"\)\]\s*\[string\]\$RsxCachePreload\s*=\s*"preload"') {
    throw "The guarded Thor route does not expose stock-default preload/defer control."
}

$preloadResetCount = [regex]::Matches(
    $inputMacroSource,
    [regex]::Escape('setprop debug.rpcsx.thor.rsx_cache_preload preload')
).Count
if ($preloadResetCount -ne 3) {
    throw "The Thor route must reset shader-cache preload before launch and after success or failure; found $preloadResetCount resets."
}

if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.rsx_cache_preload \$RsxCachePreload' -or
    $inputMacroSource -notmatch 'getprop debug\.rpcsx\.thor\.rsx_cache_preload') {
    throw "The Thor route does not set and capture the effective shader-cache preload mode."
}

if ($speedSprintSource -notmatch '\[ValidateSet\("preload",\s*"defer"\)\]\s*\[string\]\$AndroidRsxCachePreload\s*=\s*"preload"' -or
    $speedSprintSource -notmatch 'RsxCachePreload\s*=\s*\$AndroidRsxCachePreload') {
    throw "The Android speed-sprint wrapper does not expose and forward stock-default preload/defer control."
}

Write-Output "Thor RSX cache preload contract passed: dynamic work sharing, bounded workers, trace-only Android logging, and stock-default defer/interpreter fallback."
