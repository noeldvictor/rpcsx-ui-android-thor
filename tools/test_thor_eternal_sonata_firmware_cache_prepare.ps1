$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$androidPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$repositoryPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/performance/GameCacheRepository.kt"
$settingsPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/config/GameSettingsDatabase.kt"

$android = Get-Content -LiteralPath $androidPath -Raw
$ppu = Get-Content -LiteralPath $ppuPath -Raw
$repository = Get-Content -LiteralPath $repositoryPath -Raw
$settings = Get-Content -LiteralPath $settingsPath -Raw

function Assert-Contains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

foreach ($fragment in @(
    'bool precompileFirmwareModules = false;',
    'const bool precompileFirmwareModules = titleId == "BLUS30161";',
    'rpcs3::utils::get_custom_config_path(titleId)',
    'titleConfigText.starts_with("# RPCSX_THOR_AUTO_SETTINGS")',
    'titleConfigText.find("# Title ID: BLUS30161")',
    'AtExit configRestore{[&] {',
    'g_cfg.from_string(previousConfig)',
    'g_cfg.core.ppu_use_nj_bit.set(false);',
    'g_cfg.core.ppu_set_vnan.set(false);',
    'g_cfg.core.ppu_set_fpcc.set(false);',
    'g_cfg.core.ppu_decoder != ppu_decoder_type::llvm_legacy',
    '!g_cfg.core.set_daz_and_ftz',
    'g_cfg.core.llvm_threads != 2',
    'fs::is_dir(firmwareRoot)',
    'Thor PPU cache preparation activated: title=%s',
    'Thor PPU cache preparation completed: title=%s',
    '.precompileFirmwareModules =',
    'if (workload.precompileFirmwareModules) {',
    'dir_queue.push_back(g_cfg_vfs.get_dev_flash() + "sys/external/");'
)) {
    Assert-Contains $android $fragment "Missing Eternal Sonata firmware-cache preparation contract: $fragment"
}

foreach ($fragment in @(
    'val settingsStatus = GameSettingsDatabase.applyRecommendedConfig(context, game)',
    'if (titleId == "BLUS30161" && !(settingsStatus.enabled && settingsStatus.applied))',
    'return@thread',
    'RPCSX.instance.preparePpuCache(game.info.path, titleId, progressId)'
)) {
    Assert-Contains $repository $fragment "Missing app-side managed-profile cache gate: $fragment"
}

foreach ($fragment in @(
    'Max LLVM Compile Threads: 2',
    'Set DAZ and FTZ: true'
)) {
    Assert-Contains $settings $fragment "Managed Eternal Sonata cache identity is missing: $fragment"
}

foreach ($fragment in @(
    'const std::string firmware_sprx_path = vfs::get("/dev_flash/sys/external/");',
    'if (dir_queue[i] != firmware_sprx_path)',
    'g_cfg.core.libraries_control.get_set().count(entry.name + ":lle")',
    'return g_prx_list.count(entry.name) && ::at32(g_prx_list, entry.name) != 0;',
    'dir_queue.emplace_back(dir_queue[i] + entry.name + ''/'');'
)) {
    Assert-Contains $ppu $fragment "Firmware PPU precompile filtering/recursion changed: $fragment"
}

foreach ($fragment in @(
    'const u32 thread_count = std::min<u32>(::size32(workload), rpcs3::utils::get_max_threads());',
    'named_thread_group threads(worker_group_name, thread_count,',
    'threads.join();'
)) {
    Assert-Contains $ppu $fragment "PPU cache compilation no longer uses the full named-worker pool: $fragment"
}
if ($ppu.Contains('thread_ctrl::set_name(worker_group_name')) {
    throw "PPU cache compilation can still rename and execute on a foreign JNI caller thread."
}

$prepareStart = $android.IndexOf('bool prepare(JNIEnv *env, std::string path, std::string titleId,')
$compileStart = $android.IndexOf('bool compile(JNIEnv *env, CompilationWorkload workload)', $prepareStart)
if ($prepareStart -lt 0 -or $compileStart -le $prepareStart) {
    throw "Could not isolate the explicit PPU cache preparation implementation."
}
$prepareBlock = $android.Substring($prepareStart, $compileStart - $prepareStart)

$profileGate = $prepareBlock.IndexOf('titleConfigText.starts_with("# RPCSX_THOR_AUTO_SETTINGS")')
$configApply = $prepareBlock.IndexOf('g_cfg.from_string(titleConfigText)')
$identityGate = $prepareBlock.IndexOf('g_cfg.core.ppu_decoder != ppu_decoder_type::llvm_legacy')
$firmwareGate = $prepareBlock.IndexOf('fs::is_dir(firmwareRoot)')
$compileCall = $prepareBlock.IndexOf('return compile(env,')
if ($profileGate -lt 0 -or $configApply -le $profileGate -or
    $identityGate -le $configApply -or $firmwareGate -le $identityGate -or
    $compileCall -le $firmwareGate) {
    throw "Managed config, exact cache identity, firmware presence, and compile ordering are not fail-closed."
}

$repositoryGate = $repository.IndexOf('if (titleId == "BLUS30161" && !(settingsStatus.enabled && settingsStatus.applied))')
$repositoryNativeCall = $repository.IndexOf('RPCSX.instance.preparePpuCache(game.info.path, titleId, progressId)')
if ($repositoryGate -lt 0 -or $repositoryNativeCall -le $repositoryGate) {
    throw "The app can call native Eternal Sonata cache preparation before validating its managed profile."
}

$compileEnd = $android.IndexOf('} static g_compilationQueue;', $compileStart)
if ($compileEnd -le $compileStart) {
    throw "Could not isolate CompilationQueue::compile."
}
$compileBlock = $android.Substring($compileStart, $compileEnd - $compileStart)
if ($compileBlock.Contains('std::filesystem::recursive_directory_iterator(rootPath)')) {
    throw "Explicit cache preparation still pre-enumerates directories that ppu_precompile recursively scans."
}

$firmwareAppend = $compileBlock.IndexOf('dir_queue.push_back(g_cfg_vfs.get_dev_flash() + "sys/external/");')
$firmwareScope = $compileBlock.LastIndexOf('if (workload.precompileFirmwareModules) {', $firmwareAppend)
if ($firmwareAppend -lt 0 -or $firmwareScope -lt 0 -or $firmwareScope -gt $firmwareAppend) {
    throw "Firmware scanning is no longer strictly workload-gated."
}

$precompileCall = $compileBlock.IndexOf('ppu_precompile(dir_queue, mod_list.empty() ? nullptr : &mod_list);')
$completionEvidence = $compileBlock.IndexOf('Thor PPU cache preparation completed: title=%s')
$finalization = $compileBlock.IndexOf('rpcsx_android.error("Finalization")')
if ($precompileCall -lt 0 -or $completionEvidence -le $precompileCall -or $finalization -le $completionEvidence) {
    throw "Firmware cache completion evidence no longer proves ppu_precompile returned before finalization."
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "PowerShell AST parse failed: $($errors -join '; ')"
}

Write-Output "Thor Eternal Sonata firmware PPU cache preparation contract passed: managed FTZ identity is loaded and restored, firmware LLE modules are prewarmed only for BLUS30161, and duplicate directory scans stay removed."
