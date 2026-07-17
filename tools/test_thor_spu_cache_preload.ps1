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

$llvmDiagnosticsPattern = '(?s)static bool spu_compile_diagnostics_enabled\(\) noexcept\s*\{\s*#ifdef __ANDROID__\s*return g_cfg\.core\.spu_debug\.get\(\);\s*#else\s*return true;\s*#endif\s*\}'
$commonDiagnosticsPattern = '(?s)static bool spu_pattern_diagnostics_enabled\(\) noexcept\s*\{\s*#ifdef ANDROID\s*return g_cfg\.core\.spu_debug\.get\(\);\s*#else\s*return true;\s*#endif\s*\}'
$compileDiagnosticsIndex = $llvmSource.IndexOf('const bool compile_diagnostics = spu_compile_diagnostics_enabled();')
$compileDiagnosticsGateIndex = $llvmSource.IndexOf('if (compile_diagnostics)', $compileDiagnosticsIndex)
$decrementerScanIndex = $llvmSource.IndexOf('for (u32 data : func.data)', $compileDiagnosticsGateIndex)
$compileDiagnosticsGateCount = [regex]::Matches($llvmSource, [regex]::Escape('if (spu_compile_diagnostics_enabled())')).Count
$patternDiagnosticsGateCount = [regex]::Matches($commonSource, [regex]::Escape('if (spu_pattern_diagnostics_enabled())')).Count
$patternBreakGateCount = [regex]::Matches($commonSource, [regex]::Escape('if (!spu_pattern_diagnostics_enabled() || !spu_log.notice)')).Count
$likelyPutllcGateCount = [regex]::Matches($commonSource, [regex]::Escape('if (likely_putllc_loop && !had_putllc_evaluation && spu_pattern_diagnostics_enabled())')).Count
if (-not [regex]::IsMatch($llvmSource, $llvmDiagnosticsPattern) -or
    -not [regex]::IsMatch($commonSource, $commonDiagnosticsPattern) -or
    $compileDiagnosticsIndex -lt 0 -or
    $compileDiagnosticsGateIndex -le $compileDiagnosticsIndex -or
    $decrementerScanIndex -le $compileDiagnosticsGateIndex -or
    $compileDiagnosticsGateCount -ne 3 -or
    $patternDiagnosticsGateCount -ne 2 -or
    $patternBreakGateCount -ne 2 -or
    $likelyPutllcGateCount -ne 1) {
    throw "Android non-debug SPU compile diagnostics are no longer gated while desktop/debug diagnostics remain available."
}

Write-Output "Thor SPU cache preload contract passed: opt-in oldest-first unique bound, all cached identities retained, normal LLVM miss path preserved, duplicate disk appends suppressed, Android non-debug compile diagnostics pruned."
