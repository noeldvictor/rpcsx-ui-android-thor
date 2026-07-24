$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$lv2Path = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/lv2.cpp"
$timerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/sys_timer.cpp"

foreach ($path in @($configPath, $lv2Path, $timerPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing timer-config relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$lv2 = Get-Content -LiteralPath $lv2Path -Raw
$timer = Get-Content -LiteralPath $timerPath -Raw

$enumObservePattern = '(?s)class _enum : public _base.*?T observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}'
if (-not [regex]::IsMatch($config, $enumObservePattern)) {
    throw 'cfg::_enum must expose an explicit relaxed observe() accessor.'
}

$accuracyHelperPattern = '(?s)static FORCE_INLINE sleep_timers_accuracy_level\s*get_sleep_timers_accuracy_for_wait\(\) noexcept\s*\{\s*#ifdef __ANDROID__\s*return g_cfg\.core\.sleep_timers_accuracy\.observe\(\);\s*#else\s*return g_cfg\.core\.sleep_timers_accuracy\.get\(\);\s*#endif\s*\}'
foreach ($source in @(
    @{ Label = "lv2 scheduler"; Text = $lv2 },
    @{ Label = "sys_timer"; Text = $timer }
)) {
    if (-not [regex]::IsMatch($source.Text, $accuracyHelperPattern)) {
        throw "$($source.Label) must use relaxed Android and ordered desktop sleep-timer accuracy reads."
    }
}

foreach ($contract in @(
    'get_sleep_timers_accuracy_for_wait() ==',
    'if (get_sleep_timers_accuracy_for_wait() <'
)) {
    if (-not $lv2.Contains($contract)) {
        throw "lv2 scheduler/timeout is missing the timer-accuracy helper call: $contract"
    }
}

if (-not $timer.Contains('lv2_obj::sleep(ppu, get_sleep_timers_accuracy_for_wait() <')) {
    throw 'sys_timer_usleep must use the timer-accuracy helper before the normal sleep path.'
}

$clockScalePattern = '(?s)if \(scale\) \{\s*// Scale time\s*#ifdef __ANDROID__\s*const u64 clocks_scale = g_cfg\.core\.clocks_scale\.observe\(\);\s*#else\s*const u64 clocks_scale = g_cfg\.core\.clocks_scale\.get\(\);\s*#endif\s*usec = std::min<u64>\(usec, u64\{umax\} / 100\) \* 100 / clocks_scale;\s*\}'
if (-not [regex]::IsMatch($lv2, $clockScalePattern)) {
    throw 'lv2 wait_timeout must use a relaxed Android clock-scale read while preserving the ordered desktop read.'
}

Write-Output "Thor timer-config relaxed-read contract passed: Android uses relaxed live scalar loads for timer accuracy and clock scale, desktop retains ordered reads, and all scheduler/timeout call sites are covered."
