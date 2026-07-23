$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$header = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/thermal_headroom_probe.h") -Raw
$ppu = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp") -Raw
$gradle = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmake = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$macro = Get-Content -LiteralPath (Join-Path $repoRoot "tools/thor_input_macro.ps1") -Raw
$sprint = Get-Content -LiteralPath (Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1") -Raw

$requiredBuildFragments = @(
    'providers.gradleProperty("rpcsxThorThermalHeadroomProbe")',
    'System.getenv("RPCSX_THOR_THERMAL_HEADROOM_PROBE_BUILD")',
    '"-DRPCSX_THOR_THERMAL_HEADROOM_PROBE=${if (rpcsxThorThermalHeadroomProbe) "ON" else "OFF"}"',
    'option(RPCSX_THOR_THERMAL_HEADROOM_PROBE "Build the diagnostic Android PPU thermal-headroom probe" OFF)',
    'add_compile_definitions(RPCSX_THOR_THERMAL_HEADROOM_PROBE=1)'
)
foreach ($fragment in $requiredBuildFragments) {
    if (-not ($gradle.Contains($fragment) -or $cmake.Contains($fragment))) {
        throw "Missing thermal-headroom build gate: $fragment"
    }
}
if ($gradle -match 'rpcsxThorThermalHeadroomProbe[^\r\n]*\?:\s*true' -or
    $cmake -match 'option\(RPCSX_THOR_THERMAL_HEADROOM_PROBE[^\r\n]*\sON\)') {
    throw "Thermal-headroom diagnostics must remain disabled by default."
}

$normalGate = '(?s)#if defined\(__ANDROID__\) && defined\(RPCSX_THOR_THERMAL_HEADROOM_PROBE\).*?#else\s+inline constexpr bool requested\(\) noexcept\s+\{\s+return false;.*?inline constexpr sample sample_before_ppu_compile\(std::string_view\) noexcept\s+\{\s+return \{\};'
if ($header -notmatch $normalGate) {
    throw "Normal Android/desktop does not compile the thermal probe to constant no-ops."
}

$requiredHeaderFragments = @(
    'debug.rpcsx.thor.thermal_headroom_probe',
    'title_id != "BLUS30161" || !requested()',
    'dlopen("libandroid.so", RTLD_NOW | RTLD_LOCAL)',
    'dlsym(library, "AThermal_acquireManager")',
    'dlsym(library, "AThermal_releaseManager")',
    'dlsym(library, "AThermal_getCurrentThermalStatus")',
    'dlsym(library, "AThermal_getThermalHeadroom")',
    'static std::atomic_flag sampled = ATOMIC_FLAG_INIT;',
    'sampled.test_and_set(std::memory_order_relaxed)',
    'result.headroom = api.get_headroom(manager, 0);',
    'std::isfinite(result.headroom) && result.headroom >= 0.0f',
    'api.release_manager(manager);'
)
foreach ($fragment in $requiredHeaderFragments) {
    if (-not $header.Contains($fragment)) {
        throw "Missing thermal-headroom source contract: $fragment"
    }
}
if ($header.Contains('android/thermal.h')) {
    throw "The API-29 build directly imports newer Thermal API symbols."
}

$acquireIndex = $header.IndexOf('auto* manager = api.acquire_manager();', [StringComparison]::Ordinal)
$statusIndex = $header.IndexOf('result.status = api.get_status(manager);', [StringComparison]::Ordinal)
$headroomIndex = $header.IndexOf('result.headroom = api.get_headroom(manager, 0);', [StringComparison]::Ordinal)
$releaseIndex = $header.IndexOf('api.release_manager(manager);', [StringComparison]::Ordinal)
if ($acquireIndex -lt 0 -or $statusIndex -le $acquireIndex -or $headroomIndex -le $statusIndex -or $releaseIndex -le $headroomIndex) {
    throw "Thermal manager acquire/query/release ordering is unsafe."
}

$compileStart = $ppu.IndexOf('// Create worker threads for compilation', [StringComparison]::Ordinal)
$compileEnd = $ppu.IndexOf('// Initialize compiler instance', $compileStart, [StringComparison]::Ordinal)
if ($compileStart -lt 0 -or $compileEnd -le $compileStart) {
    throw "Could not isolate the PPU compile block."
}
$compileBlock = $ppu.Substring($compileStart, $compileEnd - $compileStart)
foreach ($fragment in @(
    'sample_before_ppu_compile(Emu.GetTitleID())',
    'Thor PPU thermal-headroom probe unavailable:',
    'Thor PPU thermal-headroom probe: headroom=nan',
    'Thor PPU thermal-headroom probe: headroom=%.3f',
    'workers=%u, affinity=0x%x, scheduling=unchanged.'
)) {
    if (-not $compileBlock.Contains($fragment)) {
        throw "Missing PPU thermal-headroom evidence fragment: $fragment"
    }
}
if ($compileBlock.Contains('thermal_probe.headroom_valid ? 1') -or
    $compileBlock.Contains('thread_count = thermal_probe') -or
    $compileBlock.Contains('affinity_mask = thermal_probe')) {
    throw "The first diagnostic probe changes scheduling instead of observing it."
}

foreach ($fragment in @(
    '[string]$ThermalHeadroomProbe = "off"',
    '- Android thermal-headroom probe: $ThermalHeadroomProbe',
    'setprop debug.rpcsx.thor.thermal_headroom_probe $ThermalHeadroomProbe',
    'getprop debug.rpcsx.thor.thermal_headroom_probe',
    '[string]$AndroidThermalHeadroomProbe = "off"',
    'ThermalHeadroomProbe = $AndroidThermalHeadroomProbe'
)) {
    if (-not ($macro.Contains($fragment) -or $sprint.Contains($fragment))) {
        throw "Missing thermal-headroom route contract: $fragment"
    }
}
$resetCount = [regex]::Matches($macro, [regex]::Escape('setprop debug.rpcsx.thor.thermal_headroom_probe off')).Count
if ($resetCount -ne 3) {
    throw "Thermal-headroom property must reset before launch and after success/failure; found $resetCount resets."
}

Write-Output "Thor thermal-headroom probe build gate passed: API-29-safe dynamic loading, one process sample, title/default-off gating, observation-only PPU logging, and route cleanup are intact."
