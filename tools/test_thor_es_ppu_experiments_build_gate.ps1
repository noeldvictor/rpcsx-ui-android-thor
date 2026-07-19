$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$ppuSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp") -Raw
$prxSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_prx.cpp") -Raw
$prxProbeSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/run_thor_ghidra_prx_probe.ps1") -Raw

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
    'option(RPCSX_THOR_ES_PPU_EXPERIMENTS "Build Eternal Sonata PPU and PRX diagnostics on Android" OFF)',
    'add_compile_definitions(RPCSX_THOR_ES_PPU_EXPERIMENTS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing Eternal Sonata PPU-experiment CMake gate: $fragment"
    }
}

$ppuGate = '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_ES_PPU_EXPERIMENTS\)'
$gateCount = [regex]::Matches($ppuSource, $ppuGate).Count
if ($gateCount -ne 3) {
    throw "Expected PPU experiment body, resolver, and cache-scan gates, found $gateCount."
}

if ($ppuSource -notmatch ($ppuGate + '\s+namespace\s+\{[\s\S]*?debug\.rpcsx\.thor\.es_ppu_command_interp[\s\S]*?debug\.rpcsx\.thor\.es_ppu_dispatch_probe[\s\S]*?debug\.rpcsx\.thor\.es_async_draw_barrier[\s\S]*?void ppu_thor_es_async_draw_consume[\s\S]*?#else[\s\S]*?#endif\s+\s*static void ppu_fallback')) {
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

if ($ppuSource -notmatch ('\{"__resinterp"[\s\S]*?' + $ppuGate + '[\s\S]*?\{"__thor_es_command_interp"[\s\S]*?\{"__thor_es_async_draw_consume"[\s\S]*?#endif\s+\s*\{"__escape"')) {
    throw "PPU diagnostic resolver symbols are not excluded from normal Android builds."
}

$resolverCount = [regex]::Matches($ppuSource, '\{"__thor_es_[a-z0-9_]+"').Count
if ($resolverCount -ne 10) {
    throw "Expected all 10 restorable PPU diagnostic resolver symbols, found $resolverCount."
}

if ($ppuSource -notmatch ($ppuGate + '\s+bool has_thor_es_interp_publisher[\s\S]*?for \(const ppu_function& f : part\.get_funcs\(\)\)[\s\S]*?settings \+= ppu_settings::thor_es_async_draw_barrier_v8;\s+#endif\s+\s*if \(fpos')) {
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

$prxGate = '#if !defined\(ANDROID\) \|\| defined\(RPCSX_THOR_ES_PPU_EXPERIMENTS\)'
$prxGateCount = [regex]::Matches($prxSource, $prxGate).Count
if ($prxGateCount -ne 4) {
    throw "Expected PRX helper, selection, success-report, and failure-report gates, found $prxGateCount."
}

if ($prxSource -notmatch '#if defined\(ANDROID\) && defined\(RPCSX_THOR_ES_PPU_EXPERIMENTS\)\s+#include <sys/system_properties\.h>\s+#endif') {
    throw "Normal Android still includes the system-property API solely for the disabled PRX dump hook."
}

if ($prxSource -notmatch ($prxGate + '\s+static std::string thor_prx_dump_target[\s\S]*?static bool thor_prx_dump_requested[\s\S]*?static std::string thor_prx_dump_path[\s\S]*?#endif')) {
    throw "PRX dump property parsing and output-path helpers are not wholly excluded from normal Android builds."
}

if ($prxSource -notmatch ($prxGate + '\s+const bool thor_dump_prx = thor_prx_dump_requested\(name, vpath0\);\s+#else\s+constexpr bool thor_dump_prx = false;\s+#endif')) {
    throw "Normal Android PRX loading does not constant-fold the disabled diagnostic request."
}

if ($prxSource -notmatch ('if \(prx && \(g_cfg\.core\.ppu_debug \|\| thor_dump_prx\)\) \{\s+dump_executable[\s\S]*?' + $prxGate + '\s+if \(thor_dump_prx\)[\s\S]*?Thor PRX dump: module=[\s\S]*?#endif\s+\}')) {
    throw "Normal PPU Debug dumping is not preserved outside the gated PRX success report."
}

if ($prxSource -notmatch ($prxGate + '\s+if \(!prx && thor_dump_prx\)[\s\S]*?Thor PRX dump failed before module load:[\s\S]*?#endif')) {
    throw "The explicit diagnostic build lost the PRX failure report or normal Android still retains it."
}

if ([regex]::Matches($prxSource, 'debug\.rpcsx\.thor\.dump_prx').Count -ne 1) {
    throw "Expected exactly one restorable Android PRX-dump property lookup."
}

$requiredPrxRuntimeFragments = @(
    'debug.rpcsx.thor.dump_prx',
    'RPCSX_THOR_DUMP_PRX',
    'Thor PRX dump: module=',
    'Thor PRX dump failed before module load:',
    'g_cfg.core.ppu_debug || thor_dump_prx',
    'if (!prx && thor_dump_prx)',
    'dump_executable({src_data.data(), src_data.size()}, prx.get(),'
)

foreach ($fragment in $requiredPrxRuntimeFragments) {
    if (-not $prxSource.Contains($fragment)) {
        throw "Explicit diagnostic or normal PPU-debug PRX behavior was lost: $fragment"
    }
}

$requiredPrxProbeFragments = @(
    'debug.rpcsx.thor.dump_prx',
    '-PrpcsxThorEsPpuExperiments=true',
    'RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD=true',
    "the log prints 'Thor PRX dump'"
)

foreach ($fragment in $requiredPrxProbeFragments) {
    if (-not $prxProbeSource.Contains($fragment)) {
        throw "Ghidra PRX probe lost its explicit diagnostic-build contract: $fragment"
    }
}

if ($gradleSource -match 'rpcsxThorEsPpuExperiments[^\r\n]*\?:\s*true') {
    throw "The Android Eternal Sonata PPU experiments must remain disabled by default."
}

Write-Output "Thor Eternal Sonata PPU-experiment build gate passed: normal Android omits isolation/provenance/async/PRX diagnostics and range scans while explicit diagnostics, PPU Debug, desktop behavior, and cache-bit identity remain."
