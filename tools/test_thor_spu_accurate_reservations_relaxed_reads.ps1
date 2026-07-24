$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Config.h"
$systemConfigPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUThread.cpp"

foreach ($path in @($configPath, $systemConfigPath, $spuPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU accurate-reservations relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$systemConfig = Get-Content -LiteralPath $systemConfigPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw

$boolObservePattern = '(?s)class _bool final : public _base.*?bool observe\(\) const\s*\{\s*return m_value\.observe\(\);\s*\}.*?void from_default\(\) override;'
if (-not [regex]::IsMatch($config, $boolObservePattern)) {
    throw 'cfg::_bool must retain the relaxed atomic observation primitive.'
}

if (-not $systemConfig.Contains('cfg::_bool spu_accurate_reservations{this, "Accurate SPU Reservations", true};')) {
    throw 'Accurate SPU Reservations must remain a non-dynamic, default-enabled configuration boolean.'
}

$helperPattern = '(?s)static FORCE_INLINE bool get_spu_accurate_reservations_for_runtime\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.spu_accurate_reservations\.observe\(\);\s*#else\s*return g_cfg\.core\.spu_accurate_reservations\.get\(\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($spu, $helperPattern)) {
    throw 'SPU accurate-reservation decisions must use relaxed Android and ordered desktop reads.'
}

$directReadCount = ([regex]::Matches($spu, 'g_cfg\.core\.spu_accurate_reservations')).Count
if ($directReadCount -ne 2) {
    throw "Expected direct Accurate SPU Reservations access only in the helper's Android/desktop branches, found $directReadCount occurrences."
}

function Get-SourceRegion([string] $startText, [string] $endText, [int] $searchStart = 0) {
    $start = $spu.IndexOf($startText, $searchStart)
    $end = $spu.IndexOf($endText, $start)
    if ($start -lt 0 -or $end -le $start) {
        throw "Could not isolate source region '$startText' to '$endText'."
    }
    return $spu.Substring($start, $end - $start)
}

$putllc = Get-SourceRegion 'bool spu_thread::do_putllc(' 'void do_cell_atomic_128_store('
$atomicStore = Get-SourceRegion 'void do_cell_atomic_128_store(' 'void spu_thread::do_putlluc(' $spu.IndexOf('bool spu_thread::do_putllc(')
$putlluc = Get-SourceRegion 'void spu_thread::do_putlluc(' 'bool spu_thread::do_mfc('
$channelRead = Get-SourceRegion 's64 spu_thread::get_ch_value(' 'bool spu_thread::stop_and_signal('

$expectedCounts = [ordered]@{
    Putllc = @($putllc, 3)
    AtomicStore = @($atomicStore, 1)
    Putlluc = @($putlluc, 1)
    ChannelRead = @($channelRead, 1)
}

$activeCount = 0
foreach ($entry in $expectedCounts.GetEnumerator()) {
    $actual = ([regex]::Matches($entry.Value[0], 'get_spu_accurate_reservations_for_runtime\(\)')).Count
    if ($actual -ne $entry.Value[1]) {
        throw "Unexpected Accurate SPU Reservations helper coverage in $($entry.Key): expected $($entry.Value[1]), found $actual."
    }
    $activeCount += $actual
}

if ($activeCount -ne 6) {
    throw "Expected six active Accurate SPU Reservations observations, found $activeCount."
}

$allHelperCount = ([regex]::Matches($spu, 'get_spu_accurate_reservations_for_runtime\(\)')).Count
if ($allHelperCount -ne 7) {
    throw "Expected one helper definition and six active calls, found $allHelperCount occurrences."
}

foreach ($anchor in @(
    'vm::reservation_acquire(addr)',
    'rsx::reservation_lock rsx_lock(addr, 128)',
    'vm::writer_lock lock(addr, range_lock)',
    'vm::reservation_notifier_notify(addr)',
    'vm::reservation_notifier_begin_wait(raddr, rtime)',
    'cmp_rdata(to_write, rdata)'
)) {
    if (-not $spu.Contains($anchor)) {
        throw "Reservation synchronization/data-path anchor was removed: $anchor"
    }
}

Write-Output "Thor SPU accurate-reservations relaxed-read contract passed: six selector loads are relaxed only on Android while desktop ordering and reservation synchronization remain."
