$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU MFC-debug relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

$boolObservePattern = '(?s)class _bool final : public _base.*?bool observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?void from_default\(\) override;'
if (-not [regex]::IsMatch($config, $boolObservePattern)) {
    throw 'cfg::_bool must retain the relaxed atomic observation primitive.'
}

if (-not $systemConfig.Contains('cfg::_bool mfc_debug{this, "MFC Debug"};')) {
    throw 'MFC Debug must remain a non-dynamic, default-disabled configuration boolean.'
}

$helperPattern = '(?s)static FORCE_INLINE bool get_mfc_debug_for_runtime\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.mfc_debug\.observe\(\);\s*#else\s*return g_cfg\.core\.mfc_debug\.get\(\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($spu, $helperPattern)) {
    throw 'MFC diagnostic gates must use relaxed Android and ordered desktop reads.'
}

$directReadCount = ([regex]::Matches($spu, 'g_cfg\.core\.mfc_debug')).Count
if ($directReadCount -ne 2) {
    throw "Expected direct MFC Debug access only in the helper's Android/desktop branches, found $directReadCount occurrences."
}

function Get-SourceRegion([string] $startText, [string] $endText, [int] $searchStart = 0) {
    $start = $spu.IndexOf($startText, $searchStart)
    $end = $spu.IndexOf($endText, $start)
    if ($start -lt 0 -or $end -le $start) {
        throw "Could not isolate source region '$startText' to '$endText'."
    }
    return $spu.Substring($start, $end - $start)
}

$normalCtor = Get-SourceRegion 'spu_thread::spu_thread(lv2_spu_group*' 'void spu_thread::serialize_common('
$saveCtor = Get-SourceRegion 'spu_thread::spu_thread(utils::serial&' 'void spu_thread::save('
$dma = Get-SourceRegion 'void spu_thread::do_dma_transfer(' 'bool spu_thread::do_dma_check('
$list = Get-SourceRegion 'bool spu_thread::do_list_transfer(' 'bool spu_thread::do_putllc('
$process = Get-SourceRegion 'bool spu_thread::process_mfc_cmd()' 'bool spu_thread::reservation_check('

$expectedCounts = [ordered]@{
    NormalConstructor = @($normalCtor, 1)
    SaveConstructor = @($saveCtor, 1)
    DmaTransfer = @($dma, 5)
    ListTransfer = @($list, 1)
    ProcessMfcCommand = @($process, 6)
}

$activeCount = 0
foreach ($entry in $expectedCounts.GetEnumerator()) {
    $activeSource = [regex]::Replace($entry.Value[0], '(?m)^\s*//.*$', '')
    $actual = ([regex]::Matches($activeSource, 'get_mfc_debug_for_runtime\(\)')).Count
    if ($actual -ne $entry.Value[1]) {
        throw "Unexpected MFC Debug helper coverage in $($entry.Key): expected $($entry.Value[1]), found $actual."
    }
    $activeCount += $actual
}

if ($activeCount -ne 14) {
    throw "Expected fourteen active MFC Debug observations, found $activeCount."
}

$allHelperCount = ([regex]::Matches($spu, 'get_mfc_debug_for_runtime\(\)')).Count
if ($allHelperCount -ne 16) {
    throw "Expected one helper definition, fourteen active calls, and one preserved TODO comment, found $allHelperCount occurrences."
}

if (-not $normalCtor.Contains('mfc_history.resize(max_mfc_dump_idx)') -or
    -not $saveCtor.Contains('mfc_history.resize(max_mfc_dump_idx)') -or
    -not $dma.Contains('mfc_history[') -or
    -not $process.Contains('mfc_history[') -or
    -not $list.Contains('get_spu_accurate_dma_for_mfc()')) {
    throw 'MFC history allocation/recording or the accurate-DMA gate was removed.'
}

Write-Output "Thor SPU MFC-debug relaxed-read contract passed: fourteen active diagnostic gates are relaxed only on Android while desktop ordering and all history paths remain."
