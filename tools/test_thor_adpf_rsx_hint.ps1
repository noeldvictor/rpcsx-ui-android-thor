$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$hint = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/vkutils/thor_adpf_rsx_hint.h") -Raw
$draw = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKDraw.cpp") -Raw
$present = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPresent.cpp") -Raw
$cmake = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/CMakeLists.txt") -Raw
$inputMacro = Get-Content -LiteralPath (Join-Path $repoRoot "tools/thor_input_macro.ps1") -Raw
$sprint = Get-Content -LiteralPath (Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1") -Raw
$gradle = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$topCmake = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorAdpfRsxHint")',
    'System.getenv("RPCSX_THOR_ADPF_RSX_HINT_BUILD")',
    '"-DRPCSX_THOR_ADPF_RSX_HINT=${if (rpcsxThorAdpfRsxHint) "ON" else "OFF"}"'
)
foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradle.Contains($fragment)) {
        throw "Thor ADPF RSX Gradle build gate is missing: $fragment"
    }
}

foreach ($fragment in @(
    'option(RPCSX_THOR_ADPF_RSX_HINT "Build the experimental Android RSX performance-hint session" OFF)',
    'add_compile_definitions(RPCSX_THOR_ADPF_RSX_HINT=1)'
)) {
    if (-not $topCmake.Contains($fragment)) {
        throw "Thor ADPF RSX CMake build gate is missing: $fragment"
    }
}

$normalGatePattern = '(?s)#if defined\(ANDROID\) && !defined\(RPCSX_THOR_ADPF_RSX_HINT\).*?inline constexpr bool requested\(\) noexcept.*?return false;.*?inline constexpr void begin\(bool\) noexcept.*?inline constexpr void finish\(bool\) noexcept.*?#elif defined\(ANDROID\)'
if ($hint -notmatch $normalGatePattern) {
    throw "Normal Android does not compile the ADPF experiment to a constant-false, no-op gate."
}
if ($gradle -match 'rpcsxThorAdpfRsxHint[^\r\n]*\?:\s*true' -or
    $topCmake -match 'option\(RPCSX_THOR_ADPF_RSX_HINT[^\r\n]*\sON\)') {
    throw "The Android ADPF RSX experiment must remain disabled by default."
}

function Assert-OrderedFragments {
    param(
        [string]$Name,
        [string]$Source,
        [string[]]$Fragments
    )

    $position = 0
    foreach ($fragment in $Fragments) {
        $next = $Source.IndexOf($fragment, $position, [StringComparison]::Ordinal)
        if ($next -lt 0) {
            throw "$Name is missing ordered fragment: $fragment"
        }
        $position = $next + $fragment.Length
    }
}

$requiredHintFragments = @(
    '#elif defined(ANDROID)',
    'debug.rpcsx.thor.adpf_rsx',
    'if (length <= 0)',
    'return false;',
    "target_work_duration_ns = 33'333'333",
    'dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL)',
    'rsx_log.always()("Thor ADPF RSX hint enabled',
    'APerformanceHint_getManager',
    'APerformanceHint_createSession',
    'APerformanceHint_reportActualWorkDuration',
    'APerformanceHint_closeSession',
    'APerformanceHint_setPreferPowerEfficiency',
    'static thread_local session_state state',
    'static_cast<std::int32_t>(gettid())',
    'std::chrono::steady_clock::now()',
    'actual_duration_ns <= 0',
    'state.close();',
    'state.failed = true;'
)
foreach ($fragment in $requiredHintFragments) {
    if (-not $hint.Contains($fragment)) {
        throw "Thor ADPF RSX source contract is missing: $fragment"
    }
}

if ($hint.Contains('android/performance_hint.h')) {
    throw "Thor ADPF RSX code directly imports API-33 symbols instead of resolving them safely for the API-29 minimum."
}

Assert-OrderedFragments "Unavailable-API shutdown" $hint @(
    'if (!api.available())',
    'state.failed = true;',
    'return;'
)
Assert-OrderedFragments "Session-creation shutdown" $hint @(
    'state.session = manager ?',
    'if (!state.session)',
    'state.failed = true;',
    'return;'
)
Assert-OrderedFragments "Every-positive-cycle reporting" $hint @(
    'if (actual_duration_ns <= 0)',
    'return;',
    'report_actual(state.session, actual_duration_ns)'
)
if ($hint.Contains('actual_duration_ns > target_work_duration_ns')) {
    throw "Thor ADPF RSX feedback must not discard over-target frame cycles."
}
Assert-OrderedFragments "First-draw work-window start" $draw @(
    'if (vk::thor::adpf_rsx_hint::requested())',
    'vk::thor::adpf_rsx_hint::begin(Emu.GetTitleID() == "BLUS30161");',
    'init_buffers(rsx::framebuffer_creation_context::context_draw);'
)
Assert-OrderedFragments "Vulkan frame-boundary finish" $present @(
    'void VKGSRender::flip(const rsx::display_flip_info_t& info)',
    'if (vk::thor::adpf_rsx_hint::requested())',
    'vk::thor::adpf_rsx_hint::finish(Emu.GetTitleID() == "BLUS30161");',
    '// Check swapchain condition/status'
)
Assert-OrderedFragments "Android libdl link" $cmake @(
    'target_link_libraries(${RPCSX_ANDROID_LIBRARY_NAME}',
    '    android',
    '    dl',
    '    log'
)

if (-not $inputMacro.Contains('[string]$AdpfRsx = "off"')) {
    throw "The Thor run route does not keep ADPF RSX opt-in."
}

$resetCount = [regex]::Matches(
    $inputMacro,
    [regex]::Escape('setprop debug.rpcsx.thor.adpf_rsx off')
).Count
if ($resetCount -ne 3) {
    throw "The Thor run route must reset ADPF RSX before launch and after success/failure; found $resetCount resets."
}
if (-not $inputMacro.Contains('setprop debug.rpcsx.thor.adpf_rsx $AdpfRsx') -or
    -not $inputMacro.Contains('getprop debug.rpcsx.thor.adpf_rsx')) {
    throw "The Thor run route does not set and capture the requested ADPF RSX state."
}
if (-not $sprint.Contains('[string]$AndroidAdpfRsx = "off"') -or
    -not $sprint.Contains('AdpfRsx = $AndroidAdpfRsx')) {
    throw "The speed-sprint wrapper does not safely expose and forward ADPF RSX."
}

Write-Output "Thor ADPF RSX source contracts passed: API-29-safe dynamic loading, title/default-off gating, exact 30 FPS deadline, every-positive-cycle reporting, failure shutdown, and route cleanup."
