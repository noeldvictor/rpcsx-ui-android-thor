$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$spuSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp") -Raw
$loggingSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/set_thor_logging.ps1") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorSpuReducedLoopDiagnostics")',
    'System.getenv("RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS_BUILD")',
    '"-DRPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS=${if (rpcsxThorSpuReducedLoopDiagnostics) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing SPU reduced-loop diagnostics Gradle build gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS "Build Android SPU reduced-loop detect-only diagnostics" OFF)',
    'add_compile_definitions(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing SPU reduced-loop diagnostics CMake build gate: $fragment"
    }
}

$scannerGate = '#if !defined(ANDROID) || defined(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS)'
$diagnosticHelperGate = @'
#if !defined(ANDROID) || defined(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS)
static bool spu_reduced_loop_detect_only_enabled() noexcept
'@

if (-not $spuSource.Contains($diagnosticHelperGate)) {
    throw "The reduced-loop detect property helper must exist only in desktop or explicit diagnostic builds."
}

if ([regex]::Matches($spuSource, [regex]::Escape($scannerGate)).Count -ne 4) {
    throw "Expected the detect helper, scanner, detect log, and emitter registration to share the explicit diagnostics build gate."
}

$requiredDiagnosticFragments = @(
    '__system_property_get("debug.rpcsx.thor.spu_reduced_loop_detect", value)',
    'std::getenv("RPCSX_SPU_REDUCED_LOOP_DETECT")',
    'const bool log_reduced_loop_candidates = spu_reduced_loop_detect_only_enabled();',
    'const bool scan_reduced_loops = (log_reduced_loop_candidates || emit_reduced_loops) && should_search_patterns;',
    'Reduced Loop Candidate (detect-only)'
)

foreach ($fragment in $requiredDiagnosticFragments) {
    if (-not $spuSource.Contains($fragment)) {
        throw "Explicit reduced-loop detect-only diagnostic was removed: $fragment"
    }
}

$requiredLoggingFragments = @(
    '"ReducedLoop"',
    'Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "1"'
)

foreach ($fragment in $requiredLoggingFragments) {
    if (-not $loggingSource.Contains($fragment)) {
        throw "Explicit reduced-loop detect-only route control was removed: $fragment"
    }
}

$androidEmitClamp = '(?s)static bool spu_reduced_loop_emit_enabled\(\) noexcept\s*\{\s*#ifdef ANDROID\s*// Fresh-cache U2 and U4 runs both corrupt BLUS30161 at the same SPU PC\.\s*return false;\s*#else'
if (-not [regex]::IsMatch($spuSource, $androidEmitClamp)) {
    throw "Unsafe Android reduced-loop emission is no longer unconditionally clamped off."
}

if ($gradleSource -match 'rpcsxThorSpuReducedLoopDiagnostics[^\r\n]*\?:\s*true') {
    throw "Android SPU reduced-loop diagnostics must remain disabled by default."
}

if ($cmakeSource -match 'option\(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS[^\r\n]*\sON\)') {
    throw "The CMake SPU reduced-loop diagnostics gate must remain disabled by default."
}

Write-Output "Thor SPU reduced-loop diagnostics build gate passed: normal Android compiles out detect-only scanning while explicit diagnostics retain it and emission stays disabled."
