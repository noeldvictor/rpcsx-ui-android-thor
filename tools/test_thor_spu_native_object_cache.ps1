param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$spuHeaderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPURecompiler.h"
$spuCommonPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$spuLlvmPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"
$jitHeaderPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JIT.h"
$jitSourcePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"
$macroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"
$installerPath = Join-Path $repoRoot "tools/install_thor_apk_no_launch.ps1"
$androidPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$cachePreparePath = Join-Path $repoRoot "tools/invoke_thor_cache_prepare.ps1"

$spuHeader = Get-Content -LiteralPath $spuHeaderPath -Raw
$spuCommon = Get-Content -LiteralPath $spuCommonPath -Raw
$spuLlvm = Get-Content -LiteralPath $spuLlvmPath -Raw
$jitHeader = Get-Content -LiteralPath $jitHeaderPath -Raw
$jitSource = Get-Content -LiteralPath $jitSourcePath -Raw
$macroSource = Get-Content -LiteralPath $macroPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw
$installerSource = Get-Content -LiteralPath $installerPath -Raw
$androidSource = Get-Content -LiteralPath $androidPath -Raw
$cachePrepareSource = Get-Content -LiteralPath $cachePreparePath -Raw

function Assert-Contains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

Assert-Contains $spuCommon 'bool spu_native_object_cache_enabled() noexcept' "SPU native-cache parser is missing."
Assert-Contains $spuCommon 'Emu.GetTitleID() != "BLUS30161"' "SPU native cache is not title-gated."
Assert-Contains $spuCommon '__system_property_get("debug.rpcsx.thor.spu_native_object_cache", property_value)' "SPU native-cache property is missing."
Assert-Contains $spuCommon 'RPCSX_THOR_SPU_NATIVE_OBJECT_CACHE' "SPU native-cache environment fallback is missing."
Assert-Contains $spuCommon 'normalized == "1" || normalized == "on" || normalized == "true" || normalized == "yes"' "SPU native-cache parser does not fail closed to its explicit allow-list."
Assert-Contains $spuCommon 'g_cfg.core.spu_decoder == spu_decoder_type::llvm' "SPU native cache is not restricted to LLVM startup paths."
Assert-Contains $spuCommon 'spu_native_object_cache_enabled() && g_cfg.core.spu_decoder == spu_decoder_type::llvm' "The native-cache capability is no longer independent of guest-program cache contents."
Assert-Contains $spuCommon 'runtime.enable_native_object_cache()' "SPU native-cache directory creation is not fail-closed."
Assert-Contains $spuCommon 'startup LLVM objects: bounded preload plus interpreter where required; runtime misses remain uncached.' "Startup-object activation and runtime-miss isolation are not documented."
Assert-Contains $spuCommon 'spu_recompiler_base::make_llvm_recompiler(11, use_native_object_cache)' "The startup LLVM interpreter does not receive the native-cache capability."
Assert-Contains $spuCommon 'spu_recompiler_base::make_llvm_recompiler(0, use_native_object_cache)' "Startup workers do not receive the native-cache capability."
Assert-Contains $spuCommon 'compiler = spu_recompiler_base::make_llvm_recompiler();' "The runtime optimization worker no longer retains the default uncached compiler."
Assert-Contains $spuCommon 'm_cache_path + "spu-native-v2/"' "SPU native objects are not isolated from debug and guest-program caches."

Assert-Contains $spuHeader 'std::string m_native_object_cache_path;' "SPU runtime does not own a separate native-cache path."
Assert-Contains $spuHeader 'bool use_native_object_cache = false' "LLVM compiler factory is not default-off."
Assert-Contains $spuLlvm 'const bool m_use_native_object_cache;' "SPU LLVM compiler does not carry an immutable startup-cache decision."
Assert-Contains $spuLlvm 'else if (m_use_native_object_cache && !m_spurt->get_native_object_cache_path().empty())' "Production SPU native-cache branch is missing."
Assert-Contains $spuLlvm 'm_jit.make_object_cache_key(*_module, "thor-spu-native-v2")' "SPU native objects do not use the exact final-IR key."
Assert-Contains $spuLlvm '_module->setModuleIdentifier(fmt::format("%s-%s.obj", m_hash, key));' "SPU native cache does not replace the guest-only module identifier."
Assert-Contains $spuLlvm 'm_jit.make_object_cache_key(*_module, "thor-spu-interpreter-native-v2")' "SPU interpreter object does not use a separate exact final-IR schema."
Assert-Contains $spuLlvm '_module->setModuleIdentifier(fmt::format("spu-interpreter-%s.obj", key));' "SPU interpreter object does not use an isolated module name."
Assert-Contains $spuLlvm 'if (!m_use_native_object_cache)' "Default-off SPU timebase lowering is not preserved."
Assert-Contains $spuLlvm 'llvm::GlobalValue::ExternalLinkage, nullptr, "spu_timebase_offs"' "Opted-in SPU objects do not use a relocatable timebase symbol."
Assert-Contains $spuLlvm 'm_engine->updateGlobalMapping("spu_timebase_offs", reinterpret_cast<u64>(&g_timebase_offs));' "The relocatable SPU timebase symbol is not rebound for the current launch."
if (([regex]::Matches($spuLlvm, [regex]::Escape('const auto timebase_offs = load_timebase_offs();'))).Count -ne 2) {
    throw "Both SPU decrementer lowering sites must use the ASLR-safe timebase helper."
}
if (([regex]::Matches($spuLlvm, [regex]::Escape('CreateIntToPtr(m_ir->getInt64(reinterpret_cast<u64>(&g_timebase_offs))'))).Count -ne 1) {
    throw "Only the preserved default-off helper may embed the SPU timebase address."
}

$interpreterIr = $spuLlvm.IndexOf('LLVM IR (interpreter):')
$interpreterVerify = $spuLlvm.IndexOf('if (verifyModule(*_module, &out))', $interpreterIr)
$interpreterKey = $spuLlvm.IndexOf('"thor-spu-interpreter-native-v2"', $interpreterVerify)
if ($interpreterIr -lt 0 -or $interpreterVerify -le $interpreterIr -or $interpreterKey -le $interpreterVerify) {
    throw "SPU interpreter native-cache key is not computed after transformed-IR verification."
}

$debugBranch = $spuLlvm.IndexOf('if (g_cfg.core.spu_debug)')
$nativeBranch = $spuLlvm.IndexOf('else if (m_use_native_object_cache', $debugBranch)
if ($debugBranch -lt 0 -or $nativeBranch -le $debugBranch) {
    throw "SPU debug output no longer takes precedence over the production native cache."
}

$passes = $spuLlvm.IndexOf('fpm.run(*f, fam);')
$key = $spuLlvm.IndexOf('m_jit.make_object_cache_key(*_module', $passes)
if ($passes -lt 0 -or $key -le $passes) {
    throw "SPU native-cache key is computed before the final optimization passes."
}

Assert-Contains $jitHeader 'std::string m_object_cache_identity;' "JIT compiler does not retain backend identity."
Assert-Contains $jitHeader 'make_object_cache_key(const llvm::Module& module, std::string_view schema) const' "Exact native-object key API is missing."
foreach ($fragment in @(
    'LLVM_VERSION_STRING, m_cpu, target_triple, attribute_identity',
    'm_engine->getTargetMachine()->createDataLayout().getStringRepresentation()',
    '#include <llvm/Bitcode/BitcodeWriter.h>',
    'llvm::WriteBitcodeToFile(module, stream, true);',
    'sha1_finish(&context, output);',
    'llvm::object::ObjectFile::createObjectFile(*buf)',
    'ObjectCache: Removed damaged compile object:'
)) {
    Assert-Contains $jitSource $fragment "Missing exact/corruption-safe JIT object-cache contract: $fragment"
}
if ($jitSource.Contains('module.print(stream, nullptr);')) {
    throw "Exact native-object keys must not pay textual LLVM IR formatting cost."
}

if ($macroSource -notmatch '(?s)\[ValidateSet\("on",\s*"off"\)\]\s*\[string\]\$SpuNativeObjectCache\s*=\s*"off"') {
    throw "Thor route SPU native-cache control is missing or not default-off."
}
Assert-Contains $macroSource 'setprop debug.rpcsx.thor.spu_native_object_cache $SpuNativeObjectCache' "Thor route does not activate/capture the requested native-cache value."
$reset = 'setprop debug.rpcsx.thor.spu_native_object_cache off'
if (([regex]::Matches($macroSource, [regex]::Escape($reset))).Count -ne 3) {
    throw "Expected prelaunch, failure, and success native-cache resets."
}

if ($sprintSource -notmatch '(?s)\[ValidateSet\("on",\s*"off"\)\]\s*\[string\]\$AndroidSpuNativeObjectCache\s*=\s*"off"') {
    throw "Speed-sprint native-cache control is missing or not default-off."
}
Assert-Contains $sprintSource 'SpuNativeObjectCache = $AndroidSpuNativeObjectCache' "Speed sprint does not forward the SPU native-cache control."
Assert-Contains $installerSource 'spu_native_cache=' "No-launch installer does not capture SPU native-cache state."
foreach ($fragment in @(
    'Thor SPU native-object cache preparation activated: title=%s',
    'spu_cache::initialize();',
    'Thor SPU native-object cache preparation completed: title=%s'
)) {
    Assert-Contains $androidSource $fragment "Stopped-emulator SPU native-object preparation is missing: $fragment"
}
foreach ($fragment in @(
    '$spuNativeObjectCache = "on"',
    '$spuCachePreloadLimit = 64',
    '$spuCacheCompileBudgetMs = 100',
    'setprop debug.rpcsx.thor.spu_native_object_cache $spuNativeObjectCache',
    'setprop debug.rpcsx.thor.spu_cache_preload_limit $spuCachePreloadLimit',
    'setprop debug.rpcsx.thor.spu_cache_compile_budget_ms $spuCacheCompileBudgetMs',
    'setprop debug.rpcsx.thor.spu_native_object_cache off',
    'setprop debug.rpcsx.thor.spu_cache_preload_limit 0',
    'setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0',
    'SPU properties reset:'
)) {
    Assert-Contains $cachePrepareSource $fragment "Guarded cache-preparation SPU control is missing: $fragment"
}

foreach ($path in @($macroPath, $sprintPath, $installerPath, $cachePreparePath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell AST parse failed for ${path}: $($errors -join '; ')"
    }
}

Write-Host "Thor SPU native-object cache contract: PASS"
