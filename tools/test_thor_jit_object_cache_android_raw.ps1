$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$jitHeader = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JIT.h") -Raw
$jitSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp") -Raw
$androidSource = Get-Content -LiteralPath (Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp") -Raw

$requiredHeader = @(
    'static void set_raw_cache_materialization(bool enabled) noexcept;'
)

$requiredJit = @(
    '#ifdef __ANDROID__',
    'static std::atomic_bool g_materialize_raw_object_cache{false};',
    'static std::atomic<usz> g_raw_object_cache_budget{0};',
    'module_file.file.write(obj.getBufferStart(), obj.getBufferSize())',
    'static std::unique_ptr<llvm::MemoryBuffer> load_compressed(const std::string& path)',
    'static std::unique_ptr<llvm::MemoryBuffer> load_raw(const std::string& path)',
    'static bool materialize_raw(const std::string& path, const llvm::MemoryBuffer& buffer)',
    'g_raw_object_cache_budget.compare_exchange_weak(remaining, remaining - size',
    'g_raw_object_cache_budget.fetch_add(size, std::memory_order_relaxed);',
    'const usz budget = fs::statfs(fs::get_cache_dir(), stats) ? stats.avail_free / 4 : 0;',
    'g_raw_object_cache_budget.store(budget, std::memory_order_relaxed);',
    'ObjectCache::load(path, &loaded_compressed)',
    'loaded_compressed && g_materialize_raw_object_cache.load(std::memory_order_acquire)',
    'ObjectCache::materialize_raw(path, *cache);',
    'const bool removed_raw = fs::remove_file(path);',
    'const bool removed_compressed = fs::remove_file(path + ".gz");'
)

$requiredAndroid = @(
    'jit_compiler::set_raw_cache_materialization(true);',
    'AtExit rawCacheMaterializationGuard{',
    '[] { jit_compiler::set_raw_cache_materialization(false); }'
)

foreach ($fragment in $requiredHeader) {
    if (-not $jitHeader.Contains($fragment)) {
        throw "Missing Android raw JIT cache header contract: $fragment"
    }
}

foreach ($fragment in $requiredJit) {
    if (-not $jitSource.Contains($fragment)) {
        throw "Missing Android raw JIT cache implementation contract: $fragment"
    }
}

foreach ($fragment in $requiredAndroid) {
    if (-not $androidSource.Contains($fragment)) {
        throw "Missing Android prepare-cache materialization contract: $fragment"
    }
}

$rawCall = $jitSource.IndexOf('if (auto raw = load_raw(path))')
$compressedCall = $jitSource.IndexOf('if (auto compressed = load_compressed(path))', $rawCall)
$androidBlock = $jitSource.LastIndexOf('#ifdef __ANDROID__', $rawCall)
if ($androidBlock -lt 0 -or $rawCall -le $androidBlock -or $compressedCall -le $rawCall) {
    throw "Android JIT cache load order is no longer raw-first with compressed fallback."
}

$notifyStart = $jitSource.IndexOf('void notifyObjectCompiled')
$loadStart = $jitSource.IndexOf('static std::unique_ptr<llvm::MemoryBuffer> load_compressed', $notifyStart)
$notifyBlock = $jitSource.Substring($notifyStart, $loadStart - $notifyStart)
if (-not $notifyBlock.Contains('#ifndef __ANDROID__') -or
    -not $notifyBlock.Contains('name.append(".gz");') -or
    -not $notifyBlock.Contains('fs::remove_file(name + ".gz");')) {
    throw "Android raw writes or desktop gzip compatibility are no longer explicit."
}

$parseIndex = $jitSource.IndexOf('llvm::object::ObjectFile::createObjectFile(*cache)')
$materializeIndex = $jitSource.IndexOf('ObjectCache::materialize_raw(path, *cache);', $parseIndex)
if ($parseIndex -lt 0 -or $materializeIndex -le $parseIndex) {
    throw "Legacy gzip migration can occur before LLVM object validation."
}

Write-Output "Thor Android raw JIT cache contract passed: new objects skip gzip, raw loads win, explicit preparation migrates only validated live objects, and compressed compatibility/corruption cleanup remain."
