$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradleSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$cmakeSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/CMakeLists.txt") -Raw
$asmSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rx/include/rx/asm.hpp") -Raw
$loggingSource = Get-Content -LiteralPath (Join-Path $repoRoot "tools/set_thor_logging.ps1") -Raw

$requiredGradleFragments = @(
    'providers.gradleProperty("rpcsxThorBusyWaitExperiment")',
    'System.getenv("RPCSX_THOR_BUSY_WAIT_EXPERIMENT_BUILD")',
    '"-DRPCSX_THOR_BUSY_WAIT_EXPERIMENT=${if (rpcsxThorBusyWaitExperiment) "ON" else "OFF"}"'
)

foreach ($fragment in $requiredGradleFragments) {
    if (-not $gradleSource.Contains($fragment)) {
        throw "Missing busy-wait experiment Gradle build gate: $fragment"
    }
}

$requiredCmakeFragments = @(
    'option(RPCSX_THOR_BUSY_WAIT_EXPERIMENT "Build the failed Android ARM64 busy-wait batching experiment" OFF)',
    'add_compile_definitions(RPCSX_THOR_BUSY_WAIT_EXPERIMENT=1)'
)

foreach ($fragment in $requiredCmakeFragments) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "Missing busy-wait experiment CMake build gate: $fragment"
    }
}

$gate = 'defined\(ARCH_ARM64\) && defined\(ANDROID\) &&\s*\\\s*defined\(RPCSX_THOR_BUSY_WAIT_EXPERIMENT\)'
$gateCount = [regex]::Matches($asmSource, $gate).Count
if ($gateCount -ne 3) {
    throw "Expected include, implementation, and callsite busy-wait experiment gates, found $gateCount."
}

$requiredExperimentFragments = @(
    'enum class thor_busy_wait_mode : u32',
    'inline thor_busy_wait_mode parse_thor_busy_wait_mode(const char *value)',
    'inline thor_busy_wait_mode get_thor_busy_wait_mode()',
    '__system_property_get("debug.rpcsx.thor.fast_busy_wait", value)',
    'std::getenv("RPCSX_THOR_FAST_BUSY_WAIT")',
    'inline u32 thor_busy_wait_poll_batch(usz cycles)',
    'const u32 batch = thor_busy_wait_poll_batch(cycles);',
    'if (batch > 1)'
)

foreach ($fragment in $requiredExperimentFragments) {
    if (-not $asmSource.Contains($fragment)) {
        throw "Explicit diagnostic busy-wait experiment was removed: $fragment"
    }
}

$stockLoop = @'
  const u64 stop = get_tsc() + cycles;
  do
    pause();
  while (get_tsc() < stop);
'@

if (-not $asmSource.Contains($stockLoop)) {
    throw "Normal Android no longer retains the exact stock busy-wait loop."
}

$requiredLoggingModes = @(
    '"FastBusyWaitLight"',
    '"FastBusyWait"',
    '"FastBusyWaitAggressive"',
    'Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "light"',
    'Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "fast"',
    'Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "aggressive"'
)

foreach ($fragment in $requiredLoggingModes) {
    if (-not $loggingSource.Contains($fragment)) {
        throw "Explicit diagnostic busy-wait route control was removed: $fragment"
    }
}

if ($gradleSource -match 'rpcsxThorBusyWaitExperiment[^\r\n]*\?:\s*true') {
    throw "The Android busy-wait experiment must remain disabled by default."
}

if ($cmakeSource -match 'option\(RPCSX_THOR_BUSY_WAIT_EXPERIMENT[^\r\n]*\sON\)') {
    throw "The CMake busy-wait experiment must remain disabled by default."
}

Write-Output "Thor busy-wait experiment build gate passed: normal Android uses the stock polling loop while explicit diagnostics retain failed batching modes."
