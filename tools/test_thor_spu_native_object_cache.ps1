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

$spuHeader = Get-Content -LiteralPath $spuHeaderPath -Raw
$spuCommon = Get-Content -LiteralPath $spuCommonPath -Raw
$spuLlvm = Get-Content -LiteralPath $spuLlvmPath -Raw
$jitHeader = Get-Content -LiteralPath $jitHeaderPath -Raw
$jitSource = Get-Content -LiteralPath $jitSourcePath -Raw
$macroSource = Get-Content -LiteralPath $macroPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw
$installerSource = Get-Content -LiteralPath $installerPath -Raw

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
Assert-Contains $spuCommon 'g_cfg.core.spu_decoder == spu_decoder_type::llvm' "SPU native cache is not restricted to LLVM startup preload."
Assert-Contains $spuCommon 'runtime.enable_native_object_cache()' "SPU native-cache directory creation is not fail-closed."
Assert-Contains $spuCommon 'runtime misses remain uncached.' "Runtime-miss isolation is not documented in the activation row."
Assert-Contains $spuCommon 'spu_recompiler_base::make_llvm_recompiler(0, use_native_object_cache)' "Startup workers do not receive the native-cache capability."
Assert-Contains $spuCommon 'compiler = spu_recompiler_base::make_llvm_recompiler();' "The runtime optimization worker no longer retains the default uncached compiler."
Assert-Contains $spuCommon 'm_cache_path + "spu-native-v1/"' "SPU native objects are not isolated from debug and guest-program caches."

Assert-Contains $spuHeader 'std::string m_native_object_cache_path;' "SPU runtime does not own a separate native-cache path."
Assert-Contains $spuHeader 'bool use_native_object_cache = false' "LLVM compiler factory is not default-off."
Assert-Contains $spuLlvm 'const bool m_use_native_object_cache;' "SPU LLVM compiler does not carry an immutable startup-cache decision."
Assert-Contains $spuLlvm 'else if (m_use_native_object_cache && !m_spurt->get_native_object_cache_path().empty())' "Production SPU native-cache branch is missing."
Assert-Contains $spuLlvm 'm_jit.make_object_cache_key(*_module, "thor-spu-native-v1")' "SPU native objects do not use the exact final-IR key."
Assert-Contains $spuLlvm '_module->setModuleIdentifier(fmt::format("%s-%s.obj", m_hash, key));' "SPU native cache does not replace the guest-only module identifier."

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
    'module.print(stream, nullptr);',
    'sha1_finish(&context, output);',
    'llvm::object::ObjectFile::createObjectFile(*buf)',
    'ObjectCache: Removed damaged compile object:'
)) {
    Assert-Contains $jitSource $fragment "Missing exact/corruption-safe JIT object-cache contract: $fragment"
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

foreach ($path in @($macroPath, $sprintPath, $installerPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell AST parse failed for ${path}: $($errors -join '; ')"
    }
}

Write-Host "Thor SPU native-object cache contract: PASS"
