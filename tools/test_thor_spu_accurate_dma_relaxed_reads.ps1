$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU accurate-DMA relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

$boolObservePattern = '(?s)class _bool final : public _base.*?bool observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?void from_default\(\) override;'
if (-not [regex]::IsMatch($config, $boolObservePattern)) {
    throw 'cfg::_bool must expose the existing relaxed atomic observation primitive.'
}

if (-not $systemConfig.Contains('cfg::_bool spu_accurate_dma{this, "Accurate SPU DMA", false};')) {
    throw 'Accurate SPU DMA must remain a non-dynamic configuration boolean.'
}

$helperPattern = '(?s)static FORCE_INLINE bool get_spu_accurate_dma_for_mfc\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.spu_accurate_dma\.observe\(\);\s*#else\s*return g_cfg\.core\.spu_accurate_dma\.get\(\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($spu, $helperPattern)) {
    throw 'SPU MFC paths must use relaxed Android and ordered desktop accurate-DMA reads.'
}

$helperCount = ([regex]::Matches($spu, 'get_spu_accurate_dma_for_mfc\(\)')).Count
if ($helperCount -ne 6) {
    throw "Expected one helper definition plus five MFC call sites, found $helperCount occurrences."
}

$directReadCount = ([regex]::Matches($spu, 'g_cfg\.core\.spu_accurate_dma')).Count
if ($directReadCount -ne 2) {
    throw "Expected direct accurate-DMA access only in the helper's Android/desktop branches, found $directReadCount occurrences."
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
$dmaHelperCount = ([regex]::Matches($dmaBody, 'get_spu_accurate_dma_for_mfc\(\)')).Count
$listHelperCount = ([regex]::Matches($listBody, 'get_spu_accurate_dma_for_mfc\(\)')).Count
if ($dmaHelperCount -ne 3 -or $listHelperCount -ne 2) {
    throw "Unexpected focused helper coverage: DMA=$dmaHelperCount list=$listHelperCount."
}

if (-not $dmaBody.Contains('rsx::reservation_lock<false, 1>') -or
    -not $listBody.Contains('rsx::reservation_lock<false, 1>') -or
    -not $dmaBody.Contains('do_cell_atomic_128_store') -or
    -not $dmaBody.Contains('vm::reservation_acquire')) {
    throw 'DMA ordering, reservation, or RSX lock structure was removed.'
}

Write-Output "Thor SPU accurate-DMA relaxed-read contract passed: five MFC config reads are relaxed only on Android while transfer synchronization and desktop ordering remain."
