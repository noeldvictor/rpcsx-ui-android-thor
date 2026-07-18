$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPipelineCompiler.h") -Raw
$compilerSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPipelineCompiler.cpp") -Raw
$deviceHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/device.h") -Raw
$deviceSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/device.cpp") -Raw
$programBufferSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKProgramBuffer.h") -Raw
$stateCacheSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/ProgramStateCache.h") -Raw
$inputMacroSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/thor_input_macro.ps1") -Raw
$speedSprintSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1") -Raw

$deviceFragments = @(
    'VkPhysicalDevicePipelineCreationCacheControlFeatures pipeline_cache_control_info{}',
    'base_properties.apiVersion >= VK_API_VERSION_1_3 || pipeline_cache_control_extension',
    'VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PIPELINE_CREATION_CACHE_CONTROL_FEATURES',
    'pipeline_cache_control_info.pipelineCreationCacheControl = VK_TRUE',
    'VK_EXT_PIPELINE_CREATION_CACHE_CONTROL_EXTENSION_NAME',
    'pipeline_creation_cache_control_extension',
    'pipelineCreationCacheControl'
)
foreach ($fragment in $deviceFragments) {
    if (-not $deviceSource.Contains($fragment) -and -not $deviceHeader.Contains($fragment)) {
        throw "Vulkan cache-control device contract is missing: $fragment"
    }
}

$compilerFragments = @(
    'debug.rpcsx.thor.vk_preload_cache_hits_only',
    'g_pipeline_preload_cache_hits_only_enabled = false',
    'g_pipeline_preload_cache_hit_scope_active',
    'VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT',
    'compile_result == VK_PIPELINE_COMPILE_REQUIRED',
    'g_pipeline_preload_compile_required = true',
    'g_pipeline_preload_compile_required_count.fetch_add(1)',
    'Vulkan preload cache-hits-only summary: hits=%u, deferred_misses=%u.'
)
foreach ($fragment in $compilerFragments) {
    if (-not $compilerSource.Contains($fragment)) {
        throw "Vulkan cache-hit-only preload compiler contract is missing: $fragment"
    }
}

if ($compilerSource -notmatch 'pipeline_preload_cache_hits_only_requested\(\)[\s\S]*?length\s*<=\s*0[\s\S]*?return false;[\s\S]*?setting\s*==\s*"on"') {
    throw "Vulkan cache-hit-only preload is no longer default-off and explicitly opt-in."
}
if ($compilerSource -notmatch 'if\s*\(cache_hits_only_requested\)[\s\S]*?get_pipeline_creation_cache_control_support\(\)[\s\S]*?else if\s*\(!accepted_seed_size\)[\s\S]*?g_pipeline_preload_cache_hits_only_enabled\s*=\s*true') {
    throw "Vulkan cache-hit-only preload is not gated by both device support and a validated warm seed."
}
if ($compilerSource -notmatch 'effective_create_info\.flags\s*\|=\s*VK_PIPELINE_CREATE_FAIL_ON_PIPELINE_COMPILE_REQUIRED_BIT[\s\S]*?if\s*\(compile_result\s*==\s*VK_PIPELINE_COMPILE_REQUIRED[\s\S]*?return \{\};[\s\S]*?CHECK_RESULT\(compile_result\);') {
    throw "VK_PIPELINE_COMPILE_REQUIRED is not handled as a preload miss before the normal fatal result path."
}
if ($compilerHeader -notmatch 'class\s+pipeline_preload_cache_hit_scope[\s\S]*?consume_pipeline_preload_compile_required') {
    throw "The preload-only compiler scope is missing from the Vulkan compiler interface."
}
if ([regex]::Matches($programBufferSource, 'pipeline_preload_cache_hit_scope\s+preload_scope').Count -ne 1 -or
    $programBufferSource -notmatch 'add_pipeline_entry[\s\S]*?pipeline_preload_cache_hit_scope\s+preload_scope[\s\S]*?get_graphics_pipeline') {
    throw "The cache-hit-only scope is not isolated to cached-pipeline preload entries."
}
if ($stateCacheSource -notmatch 'consume_pipeline_preload_compile_required\(\)[\s\S]*?found\s*!=\s*m_storage\.end\(\)\s*&&\s*!found->second[\s\S]*?m_storage\.erase\(found\)') {
    throw "A compile-required preload miss does not erase only its null placeholder for normal runtime fallback."
}
if ($stateCacheSource -notmatch 'if constexpr\s*\(requires\s*\{\s*backend_traits::consume_pipeline_preload_compile_required\(\);\s*\}\)') {
    throw "Non-Vulkan backends no longer retain their unchanged generic state-cache behavior."
}

if ($inputMacroSource -notmatch '\[ValidateSet\("on",\s*"off"\)\]\s*\[string\]\$VkPreloadCacheHitsOnly\s*=\s*"off"') {
    throw "The Thor route does not keep cache-hit-only preload opt-in."
}
$resetCount = [regex]::Matches($inputMacroSource, [regex]::Escape('setprop debug.rpcsx.thor.vk_preload_cache_hits_only off')).Count
if ($resetCount -ne 3) {
    throw "The Thor route must reset cache-hit-only preload before launch and after success/failure; found $resetCount resets."
}
if ($inputMacroSource -notmatch 'setprop debug\.rpcsx\.thor\.vk_preload_cache_hits_only \$VkPreloadCacheHitsOnly') {
    throw "The Thor route does not set the requested cache-hit-only preload mode."
}
if ($speedSprintSource -notmatch '\[string\]\$AndroidVkPreloadCacheHitsOnly\s*=\s*"off"' -or
    $speedSprintSource -notmatch 'VkPreloadCacheHitsOnly\s*=\s*\$AndroidVkPreloadCacheHitsOnly') {
    throw "The speed-sprint wrapper does not expose and forward cache-hit-only preload."
}

Write-Output "Thor Vulkan preload cache-hit-only source-contract tests passed with warm-seed, feature, preload-scope, runtime-fallback, and cleanup gates."
