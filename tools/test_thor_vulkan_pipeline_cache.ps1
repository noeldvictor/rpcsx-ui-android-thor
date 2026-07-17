$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pipelinePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPipelineCompiler.cpp"
$devicePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/device.h"

$pipelineSource = Get-Content -LiteralPath $pipelinePath -Raw
$deviceSource = Get-Content -LiteralPath $devicePath -Raw

$requiredFragments = @(
    '#ifdef __ANDROID__',
    'debug.rpcsx.thor.vk_pipeline_cache',
    'driver_pipeline_cache_max_size = 64 * 1024 * 1024',
    'VK_PIPELINE_CACHE_HEADER_VERSION_ONE',
    'properties.vendorID',
    'properties.deviceID',
    'properties.pipelineCacheUUID',
    'rpcs3::cache::get_ppu_cache()',
    'shaders_cache/vulkan/',
    'fs::write_pending_file',
    'vkCreatePipelineCache',
    'vkGetPipelineCacheData',
    'vkDestroyPipelineCache',
    'g_driver_pipeline_create_count.fetch_add(1) + 1',
    'g_driver_pipeline_first_checkpoint = 32',
    'accepted_seed_size = initial_data.size()',
    'g_driver_pipeline_first_checkpoint = accepted_seed_size ? 256u : 32u',
    'create_count >= g_driver_pipeline_first_checkpoint && (create_count & (create_count - 1)) == 0',
    'initialize_driver_pipeline_cache();',
    'destroy_driver_pipeline_cache();'
)
foreach ($fragment in $requiredFragments) {
    if (-not $pipelineSource.Contains($fragment)) {
        throw "Vulkan pipeline cache source contract is missing: $fragment"
    }
}

if ($pipelineSource -notmatch 'vkCreateComputePipelines\)\(\s*\*g_render_device,\s*g_driver_pipeline_cache') {
    throw "Compute pipeline creation does not use the shared Vulkan pipeline cache."
}
if ($pipelineSource -notmatch 'vkCreateGraphicsPipelines\)\(\s*\*m_device,\s*g_driver_pipeline_cache') {
    throw "Graphics pipeline creation does not use the shared Vulkan pipeline cache."
}
if ($pipelineSource -notmatch 'result\s*!=\s*VK_SUCCESS\s*&&\s*!initial_data\.empty\(\)[\s\S]*?initialDataSize\s*=\s*0[\s\S]*?vkCreatePipelineCache') {
    throw "A driver-rejected seed does not fall back to an empty pipeline cache."
}
if ($pipelineSource -notmatch 'result\s*!=\s*VK_SUCCESS\s*&&\s*!initial_data\.empty\(\)[\s\S]*?accepted_seed_size\s*=\s*0[\s\S]*?vkCreatePipelineCache') {
    throw "A driver-rejected seed is still treated as accepted for warm checkpoint scheduling."
}
if ($pipelineSource -notmatch 'g_pipe_compilers\.reset\(\);\s*destroy_driver_pipeline_cache\(\);') {
    throw "Pipeline workers are not stopped before the final pipeline cache checkpoint."
}
if ($deviceSource -notmatch 'const VkPhysicalDeviceProperties& get_properties\(\) const\s*\{\s*return props;\s*\}') {
    throw "The physical-device properties required for cache header validation are not exposed read-only."
}

Write-Output "Thor Vulkan pipeline cache source-contract tests passed."
