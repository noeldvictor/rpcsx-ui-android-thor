$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU MFC-scheduler relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

$uintObservePattern = '(?s)class uint final : public _base.*?int_type observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?void from_default\(\) override;'
if (-not [regex]::IsMatch($config, $uintObservePattern)) {
    throw 'cfg::uint must expose the relaxed atomic observation primitive.'
}

foreach ($definition in @(
    'cfg::uint<0, 16> mfc_transfers_shuffling{this, "MFC Commands Shuffling Limit", 0};',
    'cfg::uint<0, 10000> mfc_transfers_timeout{this, "MFC Commands Timeout", 0, true};',
    'cfg::_bool mfc_shuffling_in_steps{this, "MFC Commands Shuffling In Steps", false, true};'
)) {
    if (-not $systemConfig.Contains($definition)) {
        throw "MFC scheduler setting definition changed: $definition"
    }
}

$helperContracts = @(
    @{ Name = 'shuffling limit'; Pattern = '(?s)static FORCE_INLINE u32 get_mfc_transfers_shuffling_for_runtime\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.mfc_transfers_shuffling\.observe\(\);\s*#else\s*return g_cfg\.core\.mfc_transfers_shuffling\.get\(\);\s*#endif\s*\}' },
    @{ Name = 'timeout'; Pattern = '(?s)static FORCE_INLINE u32 get_mfc_transfers_timeout_for_runtime\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.mfc_transfers_timeout\.observe\(\);\s*#else\s*return g_cfg\.core\.mfc_transfers_timeout\.get\(\);\s*#endif\s*\}' },
    @{ Name = 'step mode'; Pattern = '(?s)static FORCE_INLINE bool get_mfc_shuffling_in_steps_for_runtime\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.mfc_shuffling_in_steps\.observe\(\);\s*#else\s*return g_cfg\.core\.mfc_shuffling_in_steps\.get\(\);\s*#endif\s*\}' }
)

foreach ($contract in $helperContracts) {
    if (-not [regex]::IsMatch($spu, $contract.Pattern)) {
        throw "MFC scheduler $($contract.Name) must use relaxed Android and ordered desktop reads."
    }
}

foreach ($field in @('mfc_transfers_shuffling', 'mfc_transfers_timeout', 'mfc_shuffling_in_steps')) {
    $count = ([regex]::Matches($spu, "g_cfg\.core\.$field")).Count
    if ($count -ne 2) {
        throw "Expected direct $field access only in its helper branches, found $count occurrences."
    }
}

function Get-SourceRegion([string] $startText, [string] $endText) {
    $start = $spu.IndexOf($startText)
    $end = $spu.IndexOf($endText, $start)
    if ($start -lt 0 -or $end -le $start) {
        throw "Could not isolate source region '$startText' to '$endText'."
    }
    return $spu.Substring($start, $end - $start)
}

$cpuWork = Get-SourceRegion 'void spu_thread::cpu_work()' 'spu_thread::spu_thread(lv2_spu_group*'
$doMfc = Get-SourceRegion 'bool spu_thread::do_mfc(' 'bool spu_thread::process_mfc_cmd()'
$process = Get-SourceRegion 'bool spu_thread::process_mfc_cmd()' 'bool spu_thread::reservation_check('

if (([regex]::Matches($cpuWork, 'get_mfc_transfers_shuffling_for_runtime\(\)')).Count -ne 1 -or
    ([regex]::Matches($doMfc, 'get_mfc_transfers_shuffling_for_runtime\(\)')).Count -ne 1 -or
    ([regex]::Matches($process, 'get_mfc_transfers_shuffling_for_runtime\(\)')).Count -ne 2) {
    throw 'Expected four MFC shuffling-limit observations across cpu_work, do_mfc, and process_mfc_cmd.'
}

if (([regex]::Matches($cpuWork, 'get_mfc_transfers_timeout_for_runtime\(\)')).Count -ne 1 -or
    ([regex]::Matches($doMfc, 'get_mfc_shuffling_in_steps_for_runtime\(\)')).Count -ne 1) {
    throw 'Expected one timeout observation in cpu_work and one step-mode observation in do_mfc.'
}

$defaultFastPathPattern = '(?s)if \(u32 shuffle_count = get_mfc_transfers_shuffling_for_runtime\(\)\)\s*\{\s*const u32 timeout = get_mfc_transfers_timeout_for_runtime\(\);'
if (-not [regex]::IsMatch($cpuWork, $defaultFastPathPattern)) {
    throw 'The default zero-shuffling path must bypass the unused timeout observation.'
}

foreach ($anchor in @(
    'mfc_last_timestamp',
    'get_system_time()',
    'mfc_barrier',
    'mfc_fence',
    'MFC_BARRIER_MASK',
    'MFC_FENCE_MASK',
    'do_dma_transfer(this, ch_mfc_cmd, ls)'
)) {
    if (-not $spu.Contains($anchor)) {
        throw "MFC scheduling/ordering anchor was removed: $anchor"
    }
}

Write-Output "Thor SPU MFC-scheduler relaxed-read contract passed: the default path skips the unused timeout load, six setting reads are relaxed only on Android, and MFC ordering remains."
