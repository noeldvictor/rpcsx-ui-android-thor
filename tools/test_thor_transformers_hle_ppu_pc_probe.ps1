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
    'static std::atomic<u32> s_main_fence_dumps{0};',
    'const bool main_fence_wait = pc == 0x00102b98u || static_cast<u32>(ppu.lr) == 0x00102b98u;',
    'const u32 counter_addr = static_cast<u32>(ppu.gpr[28]);',
    'const u32 target = static_cast<u32>(ppu.gpr[29]);',
    'const u32 wait_arg = static_cast<u32>(ppu.gpr[30]);',
    'constexpr u32 task_ring = 0x01d2ffb0u;',
    'Thor MAIN FENCE: sample=%u',
    'Thor PPU TASK RING 00: sample=%u',
    'Thor PPU TASK RING 20: sample=%u',
    'static std::atomic<u32> s_render_command_wait_dumps{0};',
    'pc == 0x0152efc0u',
    'const u32 command_base = static_cast<u32>(ppu.gpr[25]);',
    'const u32 lane = static_cast<u32>(ppu.gpr[26]);',
    'const u32 timeout_addr = static_cast<u32>(ppu.gpr[1]) - 0x28u;',
    'const bool timeout_ok = vm::check_addr(timeout_addr, 0, 4);',
    '? static_cast<s32>(+vm::_ref<be_t<u32>>(timeout_addr)) : 0;',
    'scratch27=0x%08x',
    'Thor RENDER COMMAND WAIT: sample=%u',
    'Thor RENDER COMMAND STACK BEGIN: count=%u',
    'Thor RENDER COMMAND STACK END',
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
