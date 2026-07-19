$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$ppuSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorEsPpuExperiments")',
    'System.getenv("RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD")',
    '"-DRPCSX_THOR_ES_PPU_EXPERIMENTS=${if (rpcsxThorEsPpuExperiments) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing Eternal Sonata PPU-experiment Gradle gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_ES_PPU_EXPERIMENTS "Build Eternal Sonata PPU isolation and provenance experiments on Android" OFF)',
    'add_compile_definitions(RPCSX_THOR_ES_PPU_EXPERIMENTS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing Eternal Sonata PPU-experiment CMake gate: $fragment"
    }
}

$gate = '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_ES_PPU_EXPERIMENTS\)'
$gateCount = [regex]::Matches($ppuSource, $gate).Count
if ($gateCount -ne 3) {
    throw "Expected PPU experiment body, resolver, and cache-scan gates, found $gateCount."
}

if ($ppuSource -notmatch ($gate + '\s+namespace\s+\{[\s\S]*?debug\.rpcsx\.thor\.es_ppu_command_interp[\s\S]*?debug\.rpcsx\.thor\.es_ppu_dispatch_probe[\s\S]*?debug\.rpcsx\.thor\.es_async_draw_barrier[\s\S]*?void ppu_thor_es_async_draw_consume[\s\S]*?#else[\s\S]*?#endif\s+\s*static void ppu_fallback')) {
    throw "PPU interpreter, provenance, async verifier, ring state, and reports are not wholly excluded from normal Android builds."
}

$requiredAndroidStubs = @(
    'bool ppu_thor_es_command_interp_range(u32, u32&, u32&)',
    'bool ppu_thor_es_dispatch_probe_range(u32, u32)',
    'bool ppu_thor_es_async_draw_barrier_range(u32, u32)'
)

$androidStubBlock = [regex]::Match($ppuSource, '#else\s+(?<stubs>bool ppu_thor_es_command_interp_range[\s\S]*?)#endif\s+\s*static void ppu_fallback').Groups['stubs'].Value
foreach ($stub in $requiredAndroidStubs) {
    if (-not $androidStubBlock.Contains($stub) -or $androidStubBlock -notmatch ([regex]::Escape($stub) + '\s*\{\s*return false;\s*\}')) {
        throw "Missing constant-false normal-Android PPU range stub: $stub"
    }
}

if ($ppuSource -notmatch ('\{"__resinterp"[\s\S]*?' + $gate + '[\s\S]*?\{"__thor_es_command_interp"[\s\S]*?\{"__thor_es_async_draw_consume"[\s\S]*?#endif\s+\s*\{"__escape"')) {
    throw "PPU diagnostic resolver symbols are not excluded from normal Android builds."
}

$resolverCount = [regex]::Matches($ppuSource, '\{"__thor_es_[a-z0-9_]+"').Count
if ($resolverCount -ne 10) {
    throw "Expected all 10 restorable PPU diagnostic resolver symbols, found $resolverCount."
}

if ($ppuSource -notmatch ($gate + '\s+bool has_thor_es_interp_publisher[\s\S]*?for \(const ppu_function& f : part\.get_funcs\(\)\)[\s\S]*?settings \+= ppu_settings::thor_es_async_draw_barrier_v8;\s+#endif\s+\s*if \(fpos')) {
    throw "Normal Android still scans each PPU function for disabled experiment ranges or changes diagnostic cache keys."
}

$requiredCacheBits = @(
    'thor_es_command_interp_publisher',
    'thor_es_command_interp_parser',
    'thor_es_dispatch_probe',
    'thor_es_dispatch_provenance_v6',
    'thor_es_async_draw_barrier_v8'
)

foreach ($bit in $requiredCacheBits) {
    if (-not $ppuSource.Contains($bit)) {
        throw "Diagnostic PPU object-cache identity bit was removed: $bit"
    }
}

$requiredRuntimeFragments = @(
    'ppu_thor_es_command_interp_range',
    'ppu_thor_es_dispatch_probe_range',
    'ppu_thor_es_dispatch_provenance_range',
    'ppu_thor_es_async_draw_barrier_range',
    'Thor Eternal Sonata command interpreter isolation enabled:',
    'Thor Eternal Sonata PPU dispatch probe v6 enabled:',
    'Thor Eternal Sonata PPU dispatch provenance:',
    'Thor Eternal Sonata async draw verifier v8 enabled:',
    'Thor Eternal Sonata async draw post-drain v8:'
)

foreach ($fragment in $requiredRuntimeFragments) {
    if (-not $ppuSource.Contains($fragment)) {
        throw "Explicit diagnostic build lost PPU experiment behavior: $fragment"
    }
}

if ($gradleSource -match 'rpcsxThorEsPpuExperiments[^\r\n]*\?:\s*true') {
    throw "The Android Eternal Sonata PPU experiments must remain disabled by default."
}

Write-Output "Thor Eternal Sonata PPU-experiment build gate passed: normal Android omits isolation/provenance/async diagnostics and range scans while explicit diagnostics, desktop behavior, and cache-bit identity remain."
