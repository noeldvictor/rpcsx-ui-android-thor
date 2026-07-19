$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$loggingToolPath = Join-Path $repoRoot "tools/set_thor_logging.ps1"
$source = Get-Content -LiteralPath $sourcePath -Raw
$loggingTool = Get-Content -LiteralPath $loggingToolPath -Raw

$filter = [regex]::Match(
    $source,
    'static bool android_logcat_allows\(int prio\) noexcept \{(?<body>[\s\S]*?)\r?\n\}\r?\n\r?\nstruct LogListener'
).Groups['body'].Value

if ([string]::IsNullOrWhiteSpace($filter)) {
    throw "Missing Android logcat filter implementation."
}

$requiredFilterFragments = @(
    'constexpr u32 enabled_bit = 1u << 31;',
    'constexpr u32 priority_mask = 0xff;',
    'static std::atomic<u32> observed_property_serial{~u32{0}};',
    'static std::atomic<u32> packed_config{',
    'enabled_bit | static_cast<u32>(ANDROID_LOG_WARN)};',
    'const u32 area_serial = __system_property_area_serial();',
    'observed_property_serial.load(std::memory_order_acquire) != area_serial',
    'android_property_enabled("debug.rpcsx.thor.logcat", true)',
    'android_property_log_priority("log.tag.RPCS3", ANDROID_LOG_WARN)',
    'packed_config.store(next_config, std::memory_order_relaxed);',
    'observed_property_serial.store(area_serial, std::memory_order_release);',
    'const u32 config = packed_config.load(std::memory_order_relaxed);',
    'const int threshold = static_cast<int>(config & priority_mask);',
    'return threshold < ANDROID_LOG_SILENT && prio >= threshold;'
)

foreach ($fragment in $requiredFilterFragments) {
    if (-not $filter.Contains($fragment)) {
        throw "Android logcat filter lost its change-driven contract: $fragment"
    }
}

if ($filter -notmatch 'packed_config\.store\(next_config, std::memory_order_relaxed\);\s+observed_property_serial\.store\(area_serial, std::memory_order_release\);') {
    throw "Logcat config must publish before the matching property serial."
}

$forbiddenFilterFragments = @(
    'get_system_time()',
    'next_check',
    'compare_exchange_strong',
    "now + 1'000'000"
)

foreach ($fragment in $forbiddenFilterFragments) {
    if ($filter.Contains($fragment)) {
        throw "Android logcat filter restored per-message timed polling: $fragment"
    }
}

if ($source -notmatch 'if \(!android_logcat_allows\(prio\)\) \{\s+return;\s+\}\s+\s*__android_log_write\(prio, "RPCS3", text\.c_str\(\)\);') {
    throw "Android logs no longer pass through the filter immediately before logcat output."
}

if ($source -notmatch '__android_log_write\(ANDROID_LOG_FATAL, "RPCS3", buf\.c_str\(\)\);') {
    throw "Crash handling no longer bypasses the regular logcat filter with a fatal report."
}

$requiredProfiles = @(
    '(?s)"Quiet"\s*\{.*?debug\.rpcsx\.thor\.logcat" "0".*?log\.tag\.RPCS3" "S".*?break',
    '(?s)"Normal"\s*\{.*?debug\.rpcsx\.thor\.logcat" "1".*?log\.tag\.RPCS3" "I".*?break',
    '(?s)"Verbose"\s*\{.*?debug\.rpcsx\.thor\.logcat" "1".*?log\.tag\.RPCS3" "V".*?break'
)

foreach ($pattern in $requiredProfiles) {
    if ($loggingTool -notmatch $pattern) {
        throw "Thor logging tool lost a Quiet/Normal/Verbose dynamic control."
    }
}

foreach ($path in @($loggingToolPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw "PowerShell/source contract parse failed for ${path}: $($errors[0].Message)"
    }
}

Write-Output "Thor logcat filter contract passed: warning-safe default, direct fatal crash reports, live controls, packed publication, and no per-message clock polling."
