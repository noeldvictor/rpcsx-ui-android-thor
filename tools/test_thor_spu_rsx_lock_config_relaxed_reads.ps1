$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU RSX-lock relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

$boolObservePattern = '(?s)class _bool final : public _base.*?bool observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?void from_default\(\) override;'
if (-not [regex]::IsMatch($config, $boolObservePattern)) {
    throw 'cfg::_bool must expose the relaxed atomic observation primitive.'
}

$enumObservePattern = '(?s)template <typename T>\s*class _enum : public _base.*?T observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?T get_default\(\) const'
if (-not [regex]::IsMatch($config, $enumObservePattern)) {
    throw 'cfg::_enum must expose the relaxed atomic observation primitive.'
}

foreach ($definition in @(
    'fifo_setting rsx_fifo_accuracy{this, "RSX FIFO Accuracy", rsx_fifo_mode::fast};',
    'cfg::_bool strict_rendering_mode{this, "Strict Rendering Mode"};'
)) {
    if (-not $systemConfig.Contains($definition)) {
        throw "SPU RSX-lock setting must remain non-dynamic with its current default: $definition"
    }
}

$helperContracts = @(
    @{ Name = 'strict rendering'; Pattern = '(?s)static FORCE_INLINE bool get_strict_rendering_mode_for_spu_mfc\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.video\.strict_rendering_mode\.observe\(\);\s*#else\s*return g_cfg\.video\.strict_rendering_mode\.get\(\);\s*#endif\s*\}' },
    @{ Name = 'RSX FIFO accuracy'; Pattern = '(?s)static FORCE_INLINE bool get_rsx_fifo_accuracy_for_spu_mfc\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.rsx_fifo_accuracy\.observe\(\) != rsx_fifo_mode::fast;\s*#else\s*return g_cfg\.core\.rsx_fifo_accuracy\.get\(\) != rsx_fifo_mode::fast;\s*#endif\s*\}' }
)

foreach ($contract in $helperContracts) {
    if (-not [regex]::IsMatch($spu, $contract.Pattern)) {
        throw "SPU $($contract.Name) decision must use relaxed Android and ordered desktop reads."
    }
}

foreach ($field in @('g_cfg.video.strict_rendering_mode', 'g_cfg.core.rsx_fifo_accuracy')) {
    $count = ([regex]::Matches($spu, [regex]::Escape($field))).Count
    if ($count -ne 2) {
        throw "Expected direct $field access only in its helper branches, found $count occurrences."
    }
}

$dmaStart = $spu.IndexOf('void spu_thread::do_dma_transfer(')
$dmaEnd = $spu.IndexOf('bool spu_thread::do_dma_check(', $dmaStart)
$listStart = $spu.IndexOf('bool spu_thread::do_list_transfer(', $dmaEnd)
$listEnd = $spu.IndexOf('bool spu_thread::do_putllc(', $listStart)
if ($dmaStart -lt 0 -or $dmaEnd -le $dmaStart -or $listStart -lt 0 -or $listEnd -le $listStart) {
    throw 'Could not isolate SPU DMA/list transfer function bodies.'
}

$dmaBody = $spu.Substring($dmaStart, $dmaEnd - $dmaStart)
$listBody = $spu.Substring($listStart, $listEnd - $listStart)

foreach ($body in @($dmaBody, $listBody)) {
    if (([regex]::Matches($body, 'get_strict_rendering_mode_for_spu_mfc\(\)')).Count -ne 1 -or
        ([regex]::Matches($body, 'get_rsx_fifo_accuracy_for_spu_mfc\(\)')).Count -ne 1) {
        throw 'Each focused SPU transfer path must observe strict rendering and FIFO accuracy once.'
    }

    if (-not $body.Contains('rsx::reservation_lock<false, 1>') -or
        -not $body.Contains('get_spu_accurate_dma_for_mfc()')) {
        throw 'RSX reservation-lock or accurate-DMA ordering structure was removed.'
    }
}

if (-not $dmaBody.Contains('eal < rsx::constants::local_mem_base') -or
    -not $dmaBody.Contains('do_cell_atomic_128_store') -or
    -not $dmaBody.Contains('vm::reservation_acquire')) {
    throw 'DMA address gate or reservation synchronization was removed.'
}

Write-Output "Thor SPU RSX-lock relaxed-read contract passed: four config reads are relaxed only on Android while RSX reservation and DMA synchronization remain."