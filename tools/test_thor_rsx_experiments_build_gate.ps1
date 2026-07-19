$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$auditorSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/thor_rsx_auditor.h") -Raw
$resolveSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKResolveHelper.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorRsxExperiments")',
    'System.getenv("RPCSX_THOR_RSX_EXPERIMENTS_BUILD")',
    '"-DRPCSX_THOR_RSX_EXPERIMENTS=${if (rpcsxThorRsxExperiments) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing RSX-experiment Gradle build gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_RSX_EXPERIMENTS "Build experimental Android RSX fence, locality, and resolve behavior" OFF)',
    'add_compile_definitions(RPCSX_THOR_RSX_EXPERIMENTS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing RSX-experiment CMake build gate: $fragment"
    }
}

$gate = '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_RSX_EXPERIMENTS\)'
$gateCount = [regex]::Matches($auditorSource, $gate).Count
if ($gateCount -ne 2) {
    throw "Expected fence/locality and blit-source RSX experiment gates, found $gateCount."
}

$requiredProperties = @(
    'debug.rpcsx.thor.rsx_dma_fence',
    'debug.rpcsx.thor.rsx_depth_feedback',
    'debug.rpcsx.thor.rsx_texture_barrier',
    'debug.rpcsx.thor.rsx_blit_source_resolve'
)

foreach ($property in $requiredProperties) {
    if (-not $auditorSource.Contains($property)) {
        throw "Explicit diagnostic/desktop RSX experiment property was removed: $property"
    }
}

$requiredRuntimeFragments = @(
    'return detail::get_dma_fence_mode() == detail::dma_fence_mode::host_read;',
    'return detail::get_depth_feedback_mode() == detail::depth_feedback_mode::persist_readonly;',
    'const auto mode = detail::get_texture_barrier_mode();',
    'return detail::get_blit_source_resolve_mode() == detail::blit_source_resolve_mode::fast;',
    'return detail::get_blit_source_resolve_mode() == detail::blit_source_resolve_mode::verify;',
    'return detail::get_blit_source_resolve_mode() != detail::blit_source_resolve_mode::off;'
)

foreach ($fragment in $requiredRuntimeFragments) {
    if (-not $auditorSource.Contains($fragment)) {
        throw "Explicit diagnostic/desktop RSX experiment behavior was removed: $fragment"
    }
}

$requiredStockConstants = @(
    'FORCE_INLINE constexpr bool use_host_read_dma_fence() noexcept',
    'FORCE_INLINE constexpr bool persist_readonly_depth_feedback() noexcept',
    'FORCE_INLINE constexpr bool skip_texture_barrier(bool) noexcept',
    'FORCE_INLINE constexpr bool fuse_blit_source_resolve() noexcept',
    'FORCE_INLINE constexpr bool verify_blit_source_resolve() noexcept',
    'FORCE_INLINE constexpr bool test_blit_source_resolve() noexcept'
)

foreach ($function in $requiredStockConstants) {
    if ($auditorSource -notmatch ([regex]::Escape($function) + '\s*\{\s*return false;\s*\}')) {
        throw "Normal Android RSX stock behavior is not compile-time false: $function"
    }
}

if ($auditorSource -notmatch ($gate + '[\s\S]*?use_host_read_dma_fence[\s\S]*?persist_readonly_depth_feedback[\s\S]*?skip_texture_barrier[\s\S]*?#else[\s\S]*?FORCE_INLINE constexpr bool use_host_read_dma_fence[\s\S]*?FORCE_INLINE constexpr bool persist_readonly_depth_feedback[\s\S]*?FORCE_INLINE constexpr bool skip_texture_barrier[\s\S]*?#endif')) {
    throw "DMA-fence, depth-feedback, and texture-barrier behavior is not restored only by the explicit build gate."
}

if ($auditorSource -notmatch ($gate + '[\s\S]*?fuse_blit_source_resolve[\s\S]*?verify_blit_source_resolve[\s\S]*?test_blit_source_resolve[\s\S]*?#else[\s\S]*?FORCE_INLINE constexpr bool fuse_blit_source_resolve[\s\S]*?FORCE_INLINE constexpr bool verify_blit_source_resolve[\s\S]*?FORCE_INLINE constexpr bool test_blit_source_resolve[\s\S]*?#endif')) {
    throw "Blit-source experiment behavior is not restored only by the explicit build gate."
}

$resolveGateCount = [regex]::Matches($resolveSource, $gate).Count
if ($resolveGateCount -ne 5) {
    throw "Expected compute task, containers, implementation, and two cleanup RSX resolve gates, found $resolveGateCount."
}

$requiredResolveFragments = @(
    'struct cs_resolve_blit_task : compute_task',
    'std::unordered_map<VkFormat, std::unique_ptr<vk::cs_resolve_blit_task>> g_resolve_blit_helpers;',
    'std::unordered_map<u64, std::unique_ptr<vk::viewable_image>> g_resolve_blit_scratch_images;',
    'bool resolve_blit_image(',
    'bool resolve_blit_image_to_scratch(',
    'g_resolve_blit_helpers.clear();',
    'g_resolve_blit_scratch_images.clear();'
)

foreach ($fragment in $requiredResolveFragments) {
    if (-not $resolveSource.Contains($fragment)) {
        throw "Explicit diagnostic/desktop blit-source implementation was removed: $fragment"
    }
}

if ($gradleSource -match 'rpcsxThorRsxExperiments[^\r\n]*\?:\s*true') {
    throw "Android RSX experiments must remain disabled by default."
}

Write-Output "Thor RSX-experiment build gate passed: normal Android uses stock fence/barrier/resolve constants while explicit diagnostics and desktop retain runtime controls."
