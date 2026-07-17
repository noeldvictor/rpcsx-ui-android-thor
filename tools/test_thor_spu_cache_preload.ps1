$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$commonPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$llvmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$commonSource = Get-Content -LiteralPath $commonPath -Raw
$llvmSource = Get-Content -LiteralPath $llvmPath -Raw

$requiredCommonFragments = @(
    '__system_property_get("debug.rpcsx.thor.spu_cache_preload_limit", property_value)',
    'std::getenv("RPCSX_THOR_SPU_CACHE_PRELOAD_LIMIT")',
    'result > 4096',
    'spu_item* const item = runtime.add_empty(std::move(func));',
    'item->cached.exchange(1)',
    'preload_list.emplace_back(item->data);',
    'func_list = std::move(preload_list);',
    'newest unique prefix',
    'will compile on demand'
)

foreach ($fragment in $requiredCommonFragments) {
    if (-not $commonSource.Contains($fragment)) {
        throw "Missing bounded SPU cache preload contract fragment: $fragment"
    }
}

$registerIndex = $commonSource.IndexOf('spu_item* const item = runtime.add_empty(std::move(func));')
$limitIndex = $commonSource.IndexOf('if (preload_list.size() < preload_limit)')
$replaceIndex = $commonSource.IndexOf('func_list = std::move(preload_list);')
if ($registerIndex -lt 0 -or $limitIndex -le $registerIndex -or $replaceIndex -le $limitIndex) {
    throw "Cached identities are no longer registered before the bounded eager-compile queue is installed."
}

if (-not $llvmSource.Contains('const auto add_loc = m_spurt->add_empty(std::move(_func));') -or
    -not $llvmSource.Contains('if (auto& cache = g_fxo->get<spu_cache>(); cache && g_cfg.core.spu_cache && !add_loc->cached.exchange(1))')) {
    throw "Omitted cached SPU programs no longer retain the normal LLVM miss path or duplicate-write guard."
}

Write-Output "Thor SPU cache preload contract passed: opt-in newest-first unique bound, all cached identities retained, normal LLVM miss path preserved, duplicate disk appends suppressed."
