$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$paths = @{
    Logs = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/logs.hpp"
    System = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/System.cpp"
    Rsx = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
    Spu = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
    Ppu = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
    Vulkan = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/VK/VKPipelineCompiler.cpp"
    Android = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
    Analyzer = Join-Path $repoRoot "tools/analyze_thor_cool_title_capture.ps1"
}

$source = @{}
foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
        throw "Thor evidence-logging surface is missing: $($entry.Value)"
    }
    $source[$entry.Key] = Get-Content -LiteralPath $entry.Value -Raw
}

function Assert-Contains {
    param([string]$Key, [string]$Needle)
    if (-not $source[$Key].Contains($Needle)) {
        throw ("Missing Android evidence-logging contract in {0}: {1}" -f $Key, $Needle)
    }
}

$operator = [regex]::Match(
    $source.Logs,
    'inline logs::message::operator bool\(\) const\s*\{(?<body>[\s\S]*?)\r?\n\t\}'
).Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($operator)) {
    throw "Could not isolate logs::message::operator bool()."
}
if ($operator -notmatch '(?s)#ifdef __ANDROID__.*?static_cast<level>\(\*this\) <= level::error.*?return true;.*?#endif.*?return \*this <= \(\*this\)->enabled\.observe\(\);') {
    throw "Android fatal/error rows do not bypass channel silence before the ordinary filter."
}
if ($operator -match 'level::notice|level::trace') {
    throw "Android evidence logging must not globally enable routine Notice/Trace traffic."
}

foreach ($contract in @(
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Android shader cache preload limit:' },
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Android shader cache load budget enabled for BLUS30161:' },
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Android shader cache load budget: attempted' },
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Shader cache preload workers: load=' },
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Thor RSX cache-worker affinity enabled for %s:' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU cache preload limit:' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU native-object cache enabled for startup LLVM objects:' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU cache compile budget enabled for BLUS30161:' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU cache-worker pool matched to affinity:' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU cache-worker affinity enabled:' },
    @{ Key = 'Ppu'; Text = 'ppu_log.always()("Thor PPU LLVM compile-worker affinity enabled:' },
    @{ Key = 'Vulkan'; Text = 'rsx_log.always()("Vulkan preload cache-hits-only enabled for validated warm seed' },
    @{ Key = 'System'; Text = 'sys_log.always()("Thor managed configuration: Set DAZ and FTZ: %s."' }
)) {
    Assert-Contains $contract.Key $contract.Text
}

foreach ($contract in @(
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Thor RSX cache-worker affinity was not applied exactly' },
    @{ Key = 'Spu'; Text = 'spu_log.always()("Thor SPU cache-worker affinity was not applied exactly' },
    @{ Key = 'Ppu'; Text = 'ppu_log.always()("Thor PPU LLVM compile-worker affinity was not applied exactly' },
    @{ Key = 'Rsx'; Text = 'rsx_log.always()("Android startup cache phase pacing timed out' },
    @{ Key = 'Vulkan'; Text = 'rsx_log.always()("Vulkan preload cache-hits-only was requested without an enabled driver cache' },
    @{ Key = 'Vulkan'; Text = 'rsx_log.always()("Vulkan preload cache-hits-only was requested but pipelineCreationCacheControl is unsupported' },
    @{ Key = 'Vulkan'; Text = 'rsx_log.always()("Vulkan preload cache-hits-only was requested without a validated warm seed' }
)) {
    Assert-Contains $contract.Key $contract.Text
}

if ($source.System -notmatch '(?s)#ifdef __ANDROID__.*?if \(m_title_id == "BLUS30161"\).*?Thor managed configuration: Set DAZ and FTZ: %s\..*?#endif') {
    throw "Managed FTZ evidence is not Android-only and BLUS30161-gated."
}

if ($source.Rsx -notmatch '(?s)#ifdef __ANDROID__\s*rsx_log\.always\(\)\("Shader cache preload workers:.*?#else\s*rsx_log\.notice\("Shader cache preload workers:.*?#endif') {
    throw "RSX worker evidence must stay Notice on desktop and Always on Android."
}
foreach ($message in @(
    'Thor SPU cache preload limit:',
    'Thor SPU native-object cache enabled for startup LLVM objects:',
    'Thor SPU cache compile budget enabled for BLUS30161:'
)) {
    $escaped = [regex]::Escape($message)
    $pattern = '(?s)#ifdef __ANDROID__\s*spu_log\.always\(\)\("' + $escaped +
        '.*?#else\s*spu_log\.notice\("' + $escaped + '.*?#endif'
    if ($source.Spu -notmatch $pattern) {
        throw "SPU evidence must stay Notice on desktop and Always on Android: $message"
    }
}

$activationBlock = [regex]::Match(
    $source.Analyzer,
    '\$activationRequirements = \[ordered\]@\{(?<body>[\s\S]*?)\r?\n\}'
).Groups['body'].Value
if ([string]::IsNullOrWhiteSpace($activationBlock)) {
    throw "Could not isolate the Thor activation requirements."
}
$activationCount = ([regex]::Matches($activationBlock, '(?m)^\s*"[^"]+"\s*=')).Count
if ($activationCount -ne 15) {
    throw "Expected exactly 15 Thor activation requirements; found $activationCount."
}

Assert-Contains 'Android' 'if (!android_logcat_allows(prio))'
Assert-Contains 'Android' '__android_log_write(prio, "RPCS3", text.c_str());'

foreach ($scriptPath in @($paths.Analyzer, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw ("PowerShell/source contract parse failed for {0}: {1}" -f $scriptPath, $errors[0].Message)
    }
}

Write-Output "Thor Android evidence-logging contract passed: 15 bounded activation rows and failures survive Quiet logging, fatal/error rows remain durable, desktop Notice behavior is preserved, and logcat keeps its independent filter."
