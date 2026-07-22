param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildGradle = Get-Content -LiteralPath (Join-Path $repoRoot "app/build.gradle.kts") -Raw
$mainActivity = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/MainActivity.kt") -Raw
$rpcsxActivity = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/java/net/rpcsx/RPCSXActivity.kt") -Raw
$devCoreProvider = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/debug/java/net/rpcsx/ThorDevCoreOverrideProvider.java") -Raw

$requiredBuildFragments = @(
    'targets += if (buildBundledRpcsxCore)',
    'listOf("rpcsx-ui-jni", "rpcsx-android")',
    'listOf("rpcsx-ui-jni")',
    'buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "false")',
    'buildConfigField("Boolean", "THOR_DEV_CORE_OVERRIDE", "false")',
    'create("thortest")',
    'initWith(getByName("release"))',
    'isDebuggable = false',
    'signingConfig = signingConfigs.getByName("debug")',
    'matchingFallbacks += listOf("release")',
    'buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "true")',
    'buildConfigField("Boolean", "THOR_DEV_CORE_OVERRIDE", "true")',
    'getByName("thortest")',
    'manifest.srcFile("src/debug/AndroidManifest.xml")',
    'java.srcDir("src/debug/java")'
)

foreach ($fragment in $requiredBuildFragments) {
    if (-not $buildGradle.Contains($fragment)) {
        throw "ThorTest build contract is missing: $fragment"
    }
}

if ($buildGradle.Contains('matchingFallbacks += listOf("release", "debug")')) {
    throw "The optimized Thor test variant must never fall back to Debug native outputs."
}

$debugToolsTrueCount = [regex]::Matches(
    $buildGradle,
    [regex]::Escape('buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "true")')
).Count

if ($debugToolsTrueCount -ne 2) {
    throw "Expected THOR_DEBUG_TOOLS in Debug and ThorTest, found $debugToolsTrueCount true definitions."
}

$devCoreOverrideTrueCount = [regex]::Matches(
    $buildGradle,
    [regex]::Escape('buildConfigField("Boolean", "THOR_DEV_CORE_OVERRIDE", "true")')
).Count

if ($devCoreOverrideTrueCount -ne 1) {
    throw "Expected THOR_DEV_CORE_OVERRIDE only in Debug, found $devCoreOverrideTrueCount true definitions."
}

$runtimeSources = @(
    [pscustomobject]@{
        Name = "MainActivity"
        Source = $mainActivity
        RequiredCount = 2
        DevCoreGateCount = 1
    },
    [pscustomobject]@{
        Name = "RPCSXActivity"
        Source = $rpcsxActivity
        RequiredCount = 1
        DevCoreGateCount = 0
    },
    [pscustomobject]@{
        Name = "ThorDevCoreOverrideProvider"
        Source = $devCoreProvider
        RequiredCount = 0
        DevCoreGateCount = 1
    }
)

foreach ($runtimeSource in $runtimeSources) {
    if ($runtimeSource.Source.Contains("BuildConfig.DEBUG")) {
        throw "$($runtimeSource.Name) still ties Thor test hooks to the unoptimized Debug variant."
    }

    $gateCount = [regex]::Matches(
        $runtimeSource.Source,
        [regex]::Escape("BuildConfig.THOR_DEBUG_TOOLS")
    ).Count
    if ($gateCount -ne $runtimeSource.RequiredCount) {
        throw "$($runtimeSource.Name) expected $($runtimeSource.RequiredCount) Thor test-tool gates, found $gateCount."
    }

    $devCoreGateCount = [regex]::Matches(
        $runtimeSource.Source,
        [regex]::Escape("BuildConfig.THOR_DEV_CORE_OVERRIDE")
    ).Count
    if ($devCoreGateCount -ne $runtimeSource.DevCoreGateCount) {
        throw "$($runtimeSource.Name) expected $($runtimeSource.DevCoreGateCount) dev-core gates, found $devCoreGateCount."
    }
}

Write-Output "Thor optimized test-hook contract passed."
