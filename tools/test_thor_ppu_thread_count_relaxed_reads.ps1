$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/system_config.h"
$lv2Path = Join-Path $repoRoot "app/src/main/cpp/rpcsx/kernel/cellos/src/lv2.cpp"
$vmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Memory/vm.cpp"

foreach ($path in @($configPath, $lv2Path, $vmPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing PPU-thread-count relaxed-read dependency: $path"
    }
}

$config = Get-Content -LiteralPath $configPath -Raw
$lv2 = Get-Content -LiteralPath $lv2Path -Raw
$vm = Get-Content -LiteralPath $vmPath -Raw

if (-not $config.Contains('cfg::_int<1, 8> ppu_threads{this, "PPU Threads", 2};')) {
    throw 'PPU Threads must remain a non-dynamic, range-bounded configuration scalar.'
}

$schedulerHelperPattern = '(?s)static FORCE_INLINE u32 get_ppu_thread_count_for_scheduler\(\) noexcept \{\s*#ifdef __ANDROID__\s*return static_cast<u32>\(g_cfg\.core\.ppu_threads\.observe\(\)\);\s*#else\s*return static_cast<u32>\(g_cfg\.core\.ppu_threads\.get\(\)\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($lv2, $schedulerHelperPattern)) {
    throw 'lv2 must use relaxed Android and ordered desktop PPU-thread-count reads.'
}

$lockHelperPattern = '(?s)static FORCE_INLINE u32 get_ppu_thread_count_for_locks\(\) noexcept\s*\{\s*#ifdef __ANDROID__\s*return static_cast<u32>\(g_cfg\.core\.ppu_threads\.observe\(\)\);\s*#else\s*return static_cast<u32>\(g_cfg\.core\.ppu_threads\.get\(\)\);\s*#endif\s*\}'
if (-not [regex]::IsMatch($vm, $lockHelperPattern)) {
    throw 'VM locking must use relaxed Android and ordered desktop PPU-thread-count reads.'
}

$schedulerCallCount = ([regex]::Matches($lv2, 'get_ppu_thread_count_for_scheduler\(\)')).Count
if ($schedulerCallCount -ne 8) {
    throw "Expected one scheduler helper definition plus seven call sites, found $schedulerCallCount total occurrences."
}

$lockCallCount = ([regex]::Matches($vm, 'get_ppu_thread_count_for_locks\(\)')).Count
if ($lockCallCount -ne 3) {
    throw "Expected one VM helper definition plus two observations, found $lockCallCount total occurrences."
}

if (-not [regex]::IsMatch($vm, '(?s)const u32 ppu_thread_count = get_ppu_thread_count_for_locks\(\);.*?end = lock \+ ppu_thread_count.*?end = lock \+ ppu_thread_count')) {
    throw 'VM writer locking must reuse one immutable PPU-thread count across both sequential lock scans.'
}

$lv2DirectReads = ([regex]::Matches($lv2, 'g_cfg\.core\.ppu_threads(?!\.(?:observe|get)\(\)|\.max)')).Count
$vmDirectReads = ([regex]::Matches($vm, 'g_cfg\.core\.ppu_threads(?!\.(?:observe|get)\(\)|\.max)')).Count
if ($lv2DirectReads -ne 0 -or $vmDirectReads -ne 0) {
    throw "Direct ordered PPU-thread-count reads remain: lv2=$lv2DirectReads vm=$vmDirectReads"
}

Write-Output "Thor PPU-thread-count relaxed-read contract passed: all scheduler/VM runtime sites use relaxed Android observations, desktop keeps ordered reads, and writer locking reuses one immutable count."
