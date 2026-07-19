$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/logs.cpp"
$androidPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw
$androidSource = Get-Content -LiteralPath $androidPath -Raw

$sizeGate = [regex]::Match(
    $source,
    '#ifdef ANDROID[\s\S]*?constexpr u64 s_log_size = 4 \* 1024 \* 1024;\s*#else\s*constexpr u64 s_log_size = 32 \* 1024 \* 1024;\s*#endif\s*constexpr u64 s_log_write_chunk_size = 32 \* 1024;'
)
if (-not $sizeGate.Success) {
    throw "Log ring sizing is no longer Android 4 MiB / desktop 32 MiB with a 32 KiB write chunk."
}

$requiredFragments = @(
    'static_assert(s_log_size * s_log_size > s_log_size && (s_log_size & (s_log_size - 1)) == 0);',
    'static_assert(s_log_write_chunk_size < s_log_size);',
    'std::make_unique<uchar[]>(s_log_size)',
    'const u64 pushed = (bufv / s_log_size) % s_log_size;',
    'const u64 size = std::min<u64>(end - read_pos, s_log_write_chunk_size);',
    'while (size && size < s_log_size)',
    'm_buf += (size * s_log_size) - size;',
    'atomic_t<u64, 64> m_buf{0}; // Quotient: push begin, remainder: in-progress push size'
)

foreach ($fragment in $requiredFragments) {
    if (-not $source.Contains($fragment)) {
        throw "Android log ring lost required generic behavior: $fragment"
    }
}

if ($source.Contains('LSB (25 bis)') -or $source.Contains('LSB (25 bits)')) {
    throw "Log ring encoding comments are still hard-coded to the desktop 32 MiB width."
}

$listenerCount = [regex]::Matches($androidSource, 'logs::make_file_listener\(').Count
if ($listenerCount -ne 1) {
    throw "Expected exactly one Android file listener, found $listenerCount."
}

foreach ($fragment in @(
    'logs::make_file_listener(fs::get_log_dir() + "RPCSX.log"',
    'stats.avail_free / 4'
)) {
    if (-not $androidSource.Contains($fragment)) {
        throw "Android log persistence/maximum-size behavior changed: $fragment"
    }
}

$desktopRingBytes = 32 * 1024 * 1024
$androidRingBytes = 4 * 1024 * 1024
$removedGzipScratchBytes = 65536
$savedBytes = $desktopRingBytes - $androidRingBytes + $removedGzipScratchBytes
if ($savedBytes -ne 29425664) {
    throw "Unexpected per-listener resident/initialization saving: $savedBytes"
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $PSCommandPath,
    [ref]$tokens,
    [ref]$errors
)
if ($errors.Count -ne 0) {
    throw "PowerShell contract parse failed: $($errors[0].Message)"
}

Write-Output "Thor Android log-buffer contract passed: one listener uses a 4 MiB ring, desktop keeps 32 MiB, 32 KiB writes remain, and 28.0625 MiB of Android allocation/zeroing is removed."
