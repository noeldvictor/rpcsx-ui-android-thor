$ErrorActionPreference = "Stop"

$probePath = Join-Path $PSScriptRoot "invoke_thor_transformers_hle_ppu_pc_probe.ps1"
$probeSource = Get-Content -LiteralPath $probePath -Raw
$perfPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\perf_monitor.cpp"
$perfSource = Get-Content -LiteralPath $perfPath -Raw

$requiredFragments = @(
    '"debug.rpcsx.thor.hle_libs" = "libsre.sprx"',
    '"debug.rpcsx.thor.hle_spurs_kernel" = "1"',
    '"debug.rpcsx.thor.draw_census" = "0"',
    '"debug.rpcsx.thor.ppu_pc_census" = "1"',
    '[switch]$EnableSpursProbe',
    '"debug.rpcsx.thor.spurs_probe" = if ($EnableSpursProbe) { "1" } else { "0" }',
    '"debug.rpcsx.thor.ppu_call_trace" = "0"',
    'Macro = "wait:15000;stop"',
    'ThermalPreflightSamples = 1',
    'MaxLaunchSiliconTemperatureC = 70',
    'MaxSiliconTemperatureC = 72',
    'SpuCachePreloadLimit = 64',
    'SpuCacheCompileBudgetMs = 50',
    'SpuNativeObjectCache = "on"',
    'CacheWorkerAffinityMask = 7',
    'ExpectedInstalledApkSha256 = $ExpectedInstalledApkSha256.ToUpperInvariant()',
    'Set-ThorPpuProbeProperty -Name "debug.rpcsx.thor.ppu_pc_census" -Value "0"',
    'Set-ThorPpuProbeProperty -Name "debug.rpcsx.thor.spurs_probe" -Value "0"'
)

foreach ($fragment in $requiredFragments) {
    if (-not $probeSource.Contains($fragment)) {
        throw "The Transformers HLE PPU PC probe is missing: $fragment"
    }
}

$requiredPerfFragments = @(
    'static std::atomic<u64> s_last_main_stack_key{0};',
    'static std::atomic<u32> s_main_stack_dumps{0};',
    's_main_stack_dumps.load() < 8',
    's_last_main_stack_key.load() != stack_key',
    'Thor PPU STACK BEGIN: sample=%u',
    'Thor PPU STACK: sample=%u frame=%u',
    'Thor PPU STACK END: sample=%u'
)

foreach ($fragment in $requiredPerfFragments) {
    if (-not $perfSource.Contains($fragment)) {
        throw "The bounded Transformers PPU stack census is missing: $fragment"
    }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($probePath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "The Transformers HLE PPU PC probe has a PowerShell syntax error: $($errors[0].Message)"
}

Write-Output "Transformers HLE PPU PC probe contract passed."
