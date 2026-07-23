$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$ppu = Get-Content -LiteralPath $ppuPath -Raw

$start = $ppu.IndexOf('// Create worker threads for compilation', [StringComparison]::Ordinal)
$end = $ppu.IndexOf('// Initialize compiler instance', $start, [StringComparison]::Ordinal)
if ($start -lt 0 -or $end -le $start) {
    throw "Could not isolate the PPU cold-compile worker block."
}
$compileBlock = $ppu.Substring($start, $end - $start)

$requiredFragments = @(
    'atomic_t<u64> work_cv = 0;',
    'atomic_t<u64> work_done = 0;',
    'const u32 thread_count = std::min<u32>(::size32(workload), rpcs3::utils::get_max_threads());',
    '(thread_index + *op.work_done) < workload.size()',
    '// Recheck after waiting for the compiler-core semaphore.',
    '// Only named compile workers enter this scope. The foreign cache-',
    'scoped_compile_affinity compile_affinity(affinity_mask);',
    'named_thread_group threads(worker_group_name, thread_count,',
    'threads.join();'
)
foreach ($fragment in $requiredFragments) {
    if (-not $compileBlock.Contains($fragment)) {
        throw "Missing isolated PPU compile-worker fragment: $fragment"
    }
}

$forbiddenFragments = @(
    'std::max<u32>(std::min<u32>(::size32(workload), rpcs3::utils::get_max_threads()), 1) - 1',
    'thread_ctrl::set_name(worker_group_name +',
    'thread_op cur_op(',
    'try_lock_thread(thread_count, cur_op)',
    '// Recycle current thread'
)
foreach ($fragment in $forbiddenFragments) {
    if ($compileBlock.Contains($fragment)) {
        throw "The foreign PPU caller is being recycled into cold compilation: $fragment"
    }
}

Write-Output "Thor PPU compile-caller isolation contract passed: concurrency/hash fixes remain, two named workers own cold compilation, and the foreign JNI caller is not affinity/priority-repurposed."
