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
    'for (auto it = func_list.rbegin(); it != func_list.rend(); ++it)',
    'spu_item* const item = runtime.add_empty(std::move(*it));',
    'item->cached.exchange(1)',
    'preload_list.emplace_back(item->data);',
    'func_list = std::move(preload_list);',
    'oldest unique programs',
    'will compile on demand'
)

foreach ($fragment in $requiredCommonFragments) {
    if (-not $commonSource.Contains($fragment)) {
        throw "Missing bounded SPU cache preload contract fragment: $fragment"
    }
}

$reverseIndex = $commonSource.IndexOf('for (auto it = func_list.rbegin(); it != func_list.rend(); ++it)')
$registerIndex = $commonSource.IndexOf('spu_item* const item = runtime.add_empty(std::move(*it));')
$limitIndex = $commonSource.IndexOf('if (preload_list.size() < preload_limit)')
$replaceIndex = $commonSource.IndexOf('func_list = std::move(preload_list);')
if ($reverseIndex -lt 0 -or $registerIndex -le $reverseIndex -or $limitIndex -le $registerIndex -or $replaceIndex -le $limitIndex) {
    throw "Oldest-first cached identities are no longer registered before the bounded eager-compile queue is installed."
}

if (-not $llvmSource.Contains('const auto add_loc = m_spurt->add_empty(std::move(_func));') -or
    -not $llvmSource.Contains('if (auto& cache = g_fxo->get<spu_cache>(); cache && g_cfg.core.spu_cache && !add_loc->cached.exchange(1))')) {
    throw "Omitted cached SPU programs no longer retain the normal LLVM miss path or duplicate-write guard."
}

$diagnosticGateIndex = $llvmSource.IndexOf('if (write_debug_log || to_log_func)')
$diagnosticDumpIndex = $llvmSource.IndexOf('this->dump(func, function_log);')
$llvmVerifierIndex = $llvmSource.IndexOf('std::string& llvm_log = function_log;')
if ($diagnosticGateIndex -lt 0 -or
    $diagnosticDumpIndex -le $diagnosticGateIndex -or
    $llvmVerifierIndex -le $diagnosticDumpIndex) {
    throw "SPU disassembly is no longer lazily materialized while preserving the LLVM verifier log buffer."
}

if (-not $llvmSource.Contains('#ifdef __ANDROID__') -or
    -not $llvmSource.Contains('if (to_log_func && !g_cfg.core.spu_debug)') -or
    -not $llvmSource.Contains('full diagnostic dump suppressed on Android.')) {
    throw "Android non-debug SPU decrementer diagnostics no longer suppress the full function dump."
}

Write-Output "Thor SPU cache preload contract passed: opt-in oldest-first unique bound, all cached identities retained, normal LLVM miss path preserved, duplicate disk appends suppressed."
