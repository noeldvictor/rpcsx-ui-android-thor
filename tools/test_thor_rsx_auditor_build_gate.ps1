$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$auditorSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/thor_rsx_auditor.h") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorRsxAuditor")',
    'System.getenv("RPCSX_THOR_RSX_AUDITOR_BUILD")',
    '"-DRPCSX_THOR_RSX_AUDITOR=${if (rpcsxThorRsxAuditor) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing RSX-auditor Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_RSX_AUDITOR "Instrument Android Vulkan work for Thor diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_RSX_AUDITOR=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing RSX-auditor CMake gate: $fragment"
    }
}

if ($auditorSource -notmatch '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_RSX_AUDITOR\)[\s\S]*?return detail::enabled\(\);[\s\S]*?#else[\s\S]*?FORCE_INLINE constexpr bool enabled\(\) noexcept[\s\S]*?return false;[\s\S]*?#endif') {
    throw "Android's default RSX-auditor path is not an always-inline compile-time false gate."
}

$requiredBehaviorFragments = @(
    'return detail::get_dma_fence_mode() == detail::dma_fence_mode::host_read;',
    'return detail::get_depth_feedback_mode() == detail::depth_feedback_mode::persist_readonly;',
    'const auto mode = detail::get_texture_barrier_mode();',
    'return detail::get_blit_source_resolve_mode() == detail::blit_source_resolve_mode::fast;',
    'return detail::get_blit_source_resolve_mode() == detail::blit_source_resolve_mode::verify;'
)

foreach ($fragment in $requiredBehaviorFragments) {
    if (-not $auditorSource.Contains($fragment)) {
        throw "RSX behavior experiment was lost while gating diagnostics: $fragment"
    }
}

if ($gradleSource -match 'rpcsxThorRsxAuditor[^\r\n]*\?:\s*true') {
    throw "The Android RSX auditor must remain disabled by default."
}

Write-Output "Thor RSX-auditor build gate passed: normal Android omits recorder polling while desktop and explicit experiment builds retain behavior controls."
