$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$threadPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/Thread.cpp"
$atomicPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/atomic.cpp"
$threadSource = Get-Content -LiteralPath $threadPath -Raw
$atomicSource = Get-Content -LiteralPath $atomicPath -Raw

$startMatch = [regex]::Match($threadSource, '(?s)void thread_base::start\(\).*?(?=\s+void thread_base::initialize\()')
$initializeMatch = [regex]::Match($threadSource, '(?s)void thread_base::initialize\(.*?(?=\s+void thread_base::set_name\()')
$tidMatch = [regex]::Match($threadSource, '(?s)u64 thread_ctrl::get_tid\(\).*?(?=\s+bool thread_ctrl::is_main\()')

if (-not $startMatch.Success -or -not $initializeMatch.Success -or -not $tidMatch.Success) {
    throw "Could not isolate the thread start, initialization, and TID helpers."
}

$startSource = $startMatch.Value
$initializeSource = $initializeMatch.Value
$tidSource = $tidMatch.Value

$requiredStartFragments = @(
    '#elif defined(__APPLE__) || defined(ANDROID)',
    'pthread_attr_setstacksize(&stack_size_attr, 0x800000);',
    'pthread_create(&thread_id, &stack_size_attr, entry_point, this)',
    'pthread_create(&thread_id, nullptr, entry_point, this)',
    'std::memcpy(&dest_id, &thread_id, sizeof(thread_id));',
    'm_thread.compare_and_swap_test(0, dest_id)',
    'ensure(m_thread == dest_id);'
)

foreach ($fragment in $requiredStartFragments) {
    if (-not $startSource.Contains($fragment)) {
        throw "Missing atomic native-thread publication fragment: $fragment"
    }
}

$requiredInitializeFragments = @(
    '#ifdef __APPLE__',
    'while (!m_thread)',
    '#elif defined(ANDROID)',
    'const u64 new_tid = pthread_self();',
    'm_thread.compare_and_swap_test(0, new_tid)',
    'ensure(m_thread == new_tid);'
)

foreach ($fragment in $requiredInitializeFragments) {
    if (-not $initializeSource.Contains($fragment)) {
        throw "Missing race-safe thread initialization fragment: $fragment"
    }
}

$requiredTidFragments = @(
    'static thread_local u64 s_tls_tid',
    '#elif defined(ANDROID)',
    'return pthread_gettid_np(pthread_self());',
    'return s_tls_tid;'
)

foreach ($fragment in $requiredTidFragments) {
    if (-not $tidSource.Contains($fragment)) {
        throw "Missing cached Android kernel-TID fragment: $fragment"
    }
}

foreach ($legacyFragment in @(
    'reinterpret_cast<pthread_t*>(&m_thread.raw())',
    'm_thread.release(pthread_self())'
)) {
    if ($threadSource.Contains($legacyFragment)) {
        throw "Legacy racy thread-handle or uncached Android TID path remains: $legacyFragment"
    }
}

if (-not $atomicSource.Contains('tid = pthread_gettid_np(pthread_self());')) {
    throw "The Android atomic wait handle no longer records a kernel TID."
}

Write-Output "Thor Android thread identity contract passed: native handles publish atomically, the 8 MiB stack is preserved, and kernel TIDs are cached/consistent."
