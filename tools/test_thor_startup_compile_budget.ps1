param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$rsxPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$macroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"

$rsxSource = Get-Content -LiteralPath $rsxPath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$macroSource = Get-Content -LiteralPath $macroPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw

function Assert-Contains {
    param(
        [string]$Source,
        [string]$Needle,
        [string]$Message
    )

    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

Assert-Contains $rsxSource 'Emu.GetTitleID() != "BLUS30161"' "RSX compile budget is not title-gated."
Assert-Contains $rsxSource '__system_property_get("debug.rpcsx.thor.rsx_cache_compile_budget_ms", value)' "RSX compile-budget property is missing."
Assert-Contains $rsxSource 'RPCSX_THOR_RSX_CACHE_COMPILE_BUDGET_MS' "RSX compile-budget environment fallback is missing."
Assert-Contains $rsxSource 'parsed > 5000' "RSX compile budget does not fail closed above 5000 ms."
Assert-Contains $rsxSource 'steady_clock::now() >= deadline' "RSX compile loop does not check its deadline."
Assert-Contains $rsxSource 'atomic_t<bool>* stop_early = nullptr' "RSX worker wait cannot terminate cleanly after a budget expiry."
Assert-Contains $rsxSource 'will compile on demand.' "RSX deferred fallback is not documented in the activation log."
Assert-Contains $rsxSource 'if (!compile_budget_ms)' "RSX default-off path still pays budget bookkeeping."
Assert-Contains $rsxSource 'Preserve the original one-atomic fast path when the experiment is disabled.' "RSX default-off fast-path invariant is missing."

$rsxDeadline = $rsxSource.IndexOf('steady_clock::now() >= deadline')
$rsxSubmit = $rsxSource.IndexOf('m_storage.add_pipeline_entry', $rsxDeadline)
if ($rsxDeadline -lt 0 -or $rsxSubmit -lt 0 -or $rsxDeadline -ge $rsxSubmit) {
    throw "RSX compile budget is not checked before the next driver submission."
}

Assert-Contains $spuSource 'static u32 spu_cache_compile_budget_ms() noexcept' "SPU compile-budget parser is missing."
Assert-Contains $spuSource 'Emu.GetTitleID() != "BLUS30161"' "SPU compile budget is not title-gated."
Assert-Contains $spuSource '__system_property_get("debug.rpcsx.thor.spu_cache_compile_budget_ms", property_value)' "SPU compile-budget property is missing."
Assert-Contains $spuSource 'RPCSX_THOR_SPU_CACHE_COMPILE_BUDGET_MS' "SPU compile-budget environment fallback is missing."
Assert-Contains $spuSource 'result > 5000' "SPU compile budget does not fail closed above 5000 ms."
Assert-Contains $spuSource 'std::chrono::steady_clock::now() >= compile_deadline' "SPU compile loop does not check its deadline."
Assert-Contains $spuSource 'Remaining identities stay registered' "SPU on-demand identity invariant is not documented."
Assert-Contains $spuSource 'will compile on demand.' "SPU deferred fallback is not documented in the activation log."

$spuBudgetCheck = $spuSource.IndexOf('std::chrono::steady_clock::now() >= compile_deadline')
$spuAnalyse = $spuSource.IndexOf('compiler->analyse(ls.data(), func.entry_point)', $spuBudgetCheck)
if ($spuBudgetCheck -lt 0 -or $spuAnalyse -lt 0 -or $spuBudgetCheck -ge $spuAnalyse) {
    throw "SPU compile budget is not checked before eager analysis/compilation."
}

foreach ($name in @("RsxCacheCompileBudgetMs", "SpuCacheCompileBudgetMs")) {
    if ($macroSource -notmatch ("(?s)\[ValidateRange\(0,\s*5000\)\]\s*\[int\]\$" + $name + "\s*=\s*0")) {
        throw "Thor route parameter $name is missing or not default-off."
    }
}

$routeContracts = @(
    'setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms $RsxCacheCompileBudgetMs',
    'setprop debug.rpcsx.thor.spu_cache_compile_budget_ms $SpuCacheCompileBudgetMs'
)
foreach ($contract in $routeContracts) {
    Assert-Contains $macroSource $contract "Thor route does not set and capture $contract."
}

foreach ($reset in @(
    'setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms 0',
    'setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0'
)) {
    $count = ([regex]::Matches($macroSource, [regex]::Escape($reset))).Count
    if ($count -ne 3) {
        throw "Expected prelaunch, failure, and success reset coverage for '$reset'; found $count."
    }
}

foreach ($name in @("AndroidRsxCacheCompileBudgetMs", "AndroidSpuCacheCompileBudgetMs")) {
    if ($sprintSource -notmatch ("(?s)\[ValidateRange\(0,\s*5000\)\]\s*\[int\]\$" + $name + "\s*=\s*0")) {
        throw "Speed-sprint parameter $name is missing or not default-off."
    }
}

Assert-Contains $sprintSource 'RsxCacheCompileBudgetMs = $AndroidRsxCacheCompileBudgetMs' "Speed sprint does not forward the RSX budget."
Assert-Contains $sprintSource 'SpuCacheCompileBudgetMs = $AndroidSpuCacheCompileBudgetMs' "Speed sprint does not forward the SPU budget."

foreach ($path in @($macroPath, $sprintPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell AST parse failed for ${path}: $($errors -join '; ')"
    }
}

Write-Host "Thor startup compile-budget contract: PASS"
