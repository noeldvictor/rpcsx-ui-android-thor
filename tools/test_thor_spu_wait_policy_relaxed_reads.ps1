$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU wait-policy relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

foreach ($observeContract in @(
    '(?s)class _bool final : public _base.*?bool observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}',
    '(?s)class uint final : public _base.*?int_type observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}',
    '(?s)class _int final : public _base.*?int_type observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}'
)) {
    if (-not [regex]::IsMatch($config, $observeContract)) {
        throw 'A required config scalar no longer exposes relaxed atomic observation.'
    }
}

foreach ($definition in @(
    'cfg::uint<0, 100> spu_reservation_busy_waiting_percentage{this, "SPU Reservation Busy Waiting Percentage", 0, true};',
    'cfg::_bool spu_reservation_busy_waiting_enabled{this, "SPU Reservation Busy Waiting Enabled", false, true};',
    'cfg::uint<0, 100> spu_getllar_busy_waiting_percentage{this, "SPU GETLLAR Busy Waiting Percentage", 100, true};',
    'cfg::_bool spu_getllar_spin_optimization_disabled{this, "Disable SPU GETLLAR Spin Optimization", false, true};',
    'cfg::_bool spu_loop_detection{this, "SPU loop detection", false};',
    'cfg::_int<1, 6> max_spurs_threads{this, "Max SPURS Threads", 6, true};',
    'cfg::_bool rsx_accurate_res_access{this, "Accurate RSX reservation access", false, true};'
)) {
    if (-not $systemConfig.Contains($definition)) {
        throw "SPU wait-policy definition changed: $definition"
    }
}

$helperPattern = '(?s)template <typename T>\s*static FORCE_INLINE auto get_spu_wait_policy_for_runtime\(const T& setting\) noexcept\s*\{\s*#ifdef ANDROID\s*return setting\.observe\(\);\s*#else\s*return setting\.get\(\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($spu, $helperPattern)) {
    throw 'SPU wait-policy settings must use relaxed Android and ordered desktop reads.'
}

$fieldCalls = @{
    'spu_reservation_busy_waiting_percentage' = 1
    'spu_reservation_busy_waiting_enabled' = 1
    'spu_getllar_busy_waiting_percentage' = 1
    'spu_getllar_spin_optimization_disabled' = 2
    'spu_loop_detection' = 1
    'max_spurs_threads' = 1
    'rsx_accurate_res_access' = 1
}

foreach ($entry in $fieldCalls.GetEnumerator()) {
    $directPattern = "g_cfg\.core\.$([regex]::Escape($entry.Key))"
    $directCount = ([regex]::Matches($spu, $directPattern)).Count
    if ($directCount -ne $entry.Value) {
        throw "Expected $($entry.Value) focused $($entry.Key) call sites, found $directCount."
    }

    $wrappedPattern = "get_spu_wait_policy_for_runtime\(g_cfg\.core\.$([regex]::Escape($entry.Key))\)"
    $wrappedCount = ([regex]::Matches($spu, $wrappedPattern)).Count
    if ($wrappedCount -ne $entry.Value) {
        throw "Every $($entry.Key) call site must use the SPU wait-policy helper."
    }
}

$evaluatePattern = '(?s)u32 evaluate_spin_optimization\(std::span<u8> stats, u64 evaluate_time, u32 wait_percent, bool inclined_for_responsiveness = false\)\s*\{.*?const u32 percent = wait_percent;'
if (-not [regex]::IsMatch($spu, $evaluatePattern)) {
    throw 'The shared spin evaluator must consume a pre-observed percentage value.'
}

if ([regex]::IsMatch($spu, 'evaluate_spin_optimization\([^;]*cfg::uint')) {
    throw 'The shared spin evaluator must not reload a config object.'
}

foreach ($anchor in @(
    'rsx::reservation_lock rsx_lock(addr, 128,',
    'thor_es_getllar_skip_rsx_lock',
    'vm::reservation_acquire(addr)',
    'ch_events.load().mask',
    'eventstat_busy_waiting_switch',
    'group->spurs_running.fetch_op',
    'group->max_run',
    'SPU_EVENT_LR'
)) {
    if (-not $spu.Contains($anchor)) {
        throw "SPU wait/reservation synchronization anchor was removed: $anchor"
    }
}

Write-Output "Thor SPU wait-policy relaxed-read contract passed: seven policy reads are relaxed only on Android while reservation, event, and SPURS synchronization remain."