param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$controlPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/cache_phase_pacing.h"
$rsxPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$ppuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/PPUThread.cpp"
$macroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"
$installerPath = Join-Path $repoRoot "tools/install_thor_apk_no_launch.ps1"

$control = Get-Content -LiteralPath $controlPath -Raw
$rsx = Get-Content -LiteralPath $rsxPath -Raw
$spu = Get-Content -LiteralPath $spuPath -Raw
$ppu = Get-Content -LiteralPath $ppuPath -Raw
$macro = Get-Content -LiteralPath $macroPath -Raw
$sprint = Get-Content -LiteralPath $sprintPath -Raw
$installer = Get-Content -LiteralPath $installerPath -Raw

function Assert-Contains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if ($Source.Contains($Needle)) {
        throw $Message
    }
}

foreach ($fragment in @(
    'inline u64 get_cache_worker_affinity_mask(std::string_view title_id) noexcept',
    'inline u64 get_ppu_compile_worker_affinity_mask(std::string_view title_id) noexcept',
    'title_id != "BLUS30161"',
    '__system_property_get("debug.rpcsx.thor.cache_worker_affinity_mask", value)',
    'RPCSX_THOR_CACHE_WORKER_AFFINITY_MASK',
    'if (const u64 requested_mask = get_cache_worker_affinity_mask(title_id))',
    'parsed > 0xff',
    '(void)title_id;'
)) {
    Assert-Contains $control $fragment "Missing shared cache-worker affinity contract: $fragment"
}

# Compilation must not be throttled by default. The old default pinned these
# workers to the three A510 cores, which made a cold PPU recompile take about
# ten minutes while the device sat at 51-58 C against a 72 C guard. The guard
# already bounds the hot case; throttling every compile to pre-empt it spends a
# large certain cost against a small uncertain one.
#
# The property override survives, so 0x07 can restore the old behaviour if a
# boot ever does stop on temperature.
if ($control -match 'return 0x07;') {
    throw 'The A510 cache-worker pinning is back as a default. Compilation should not be throttled; use debug.rpcsx.thor.cache_worker_affinity_mask instead.'
}
foreach ($fragment in @(
    'worker_affinity_mask = rpcsx::startup_cache_phase::get_cache_worker_affinity_mask(Emu.GetTitleID());',
    'if (nb_workers == 1 && !worker_affinity_mask)',
    'named_thread_group workers("RSX Worker ", nb_workers',
    'thread_ctrl::set_thread_affinity_mask(worker_affinity_mask);',
    'Thor RSX cache-worker affinity enabled for %s',
    'effective_mask == worker_affinity_mask'
)) {
    Assert-Contains $rsx $fragment "Missing RSX cache-worker affinity contract: $fragment"
}

$rsxSet = $rsx.IndexOf('thread_ctrl::set_thread_affinity_mask(worker_affinity_mask);')
$rsxWork = $rsx.IndexOf('worker(entry_count);', $rsxSet)
if ($rsxSet -lt 0 -or $rsxWork -le $rsxSet) {
    throw "RSX cache worker does not apply affinity before loading/compiling."
}

foreach ($fragment in @(
    'cache_worker_affinity_mask = rpcsx::startup_cache_phase::get_cache_worker_affinity_mask(Emu.GetTitleID());',
    'std::popcount(cache_worker_affinity_mask)',
    'worker_count = std::min(worker_count, affinity_worker_count);',
    'Thor SPU cache-worker pool matched to affinity',
    'named_thread_group workers("SPU Worker ", worker_count',
    'thread_ctrl::set_thread_affinity_mask(cache_worker_affinity_mask);',
    'Thor SPU cache-worker affinity enabled',
    'effective_mask == cache_worker_affinity_mask',
    'thread_ctrl::scoped_priority low_prio(-1);'
)) {
    Assert-Contains $spu $fragment "Missing SPU cache-worker affinity contract: $fragment"
}

$spuSet = $spu.IndexOf('thread_ctrl::set_thread_affinity_mask(cache_worker_affinity_mask);')
$spuPoolCap = $spu.IndexOf('worker_count = std::min(worker_count, affinity_worker_count);')
$spuWorkerGroup = $spu.IndexOf('named_thread_group workers("SPU Worker ", worker_count')
if ($spuPoolCap -lt 0 -or $spuWorkerGroup -le $spuPoolCap) {
    throw "SPU cache-worker pool is not capped to the requested affinity before workers are created."
}

$spuCompiler = $spu.IndexOf('compiler->init();', $spuSet)
if ($spuSet -lt 0 -or $spuCompiler -le $spuSet) {
    throw "SPU cache worker does not apply affinity before LLVM initialization/compilation."
}

foreach ($fragment in @(
    '#include "Emu/cache_phase_pacing.h"',
    'ppu_compile_worker_affinity_mask = rpcsx::startup_cache_phase::get_ppu_compile_worker_affinity_mask(Emu.GetTitleID());',
    'struct scoped_compile_affinity',
    'previous_mask = thread_ctrl::get_thread_affinity_mask();',
    'thread_ctrl::set_thread_affinity_mask(requested_mask);',
    'thread_ctrl::set_thread_affinity_mask(previous_mask);',
    'scoped_compile_affinity compile_affinity(affinity_mask);',
    'Thor PPU LLVM compile-worker affinity enabled:',
    'Thor PPU LLVM compile-worker affinity was not applied exactly:',
    'ppu_compile_worker_affinity_mask, &ppu_compile_worker_affinity_logged',
    'workload.empty() && retained_validated_count',
    'Thor PPU warm-cache link using default scheduler:'
)) {
    Assert-Contains $ppu $fragment "Missing PPU compile-worker affinity contract: $fragment"
}

$ppuApply = $ppu.IndexOf('scoped_compile_affinity compile_affinity(affinity_mask);')
$ppuCompile = $ppu.IndexOf('jit_compiler jit2', $ppuApply)
if ($ppuApply -lt 0 -or $ppuCompile -le $ppuApply) {
    throw "PPU LLVM compilation does not apply the temporary affinity first."
}

$ppuRestore = $ppu.IndexOf('thread_ctrl::set_thread_affinity_mask(previous_mask);')
if ($ppuRestore -lt 0 -or $ppuRestore -ge $ppuApply) {
    throw "PPU compile affinity is not guarded by a scoped restore."
}

$ppuWarmMarker = $ppu.IndexOf('Thor PPU warm-cache link using default scheduler:')
$ppuWarmReuse = $ppu.IndexOf('LLVM: Reusing %u validated warm-cache objects.', $ppuWarmMarker)
$ppuWarmLink = $ppu.IndexOf('jits[mod_index / c_moudles_per_jit]->add', $ppuWarmReuse)
$ppuWarmFinalize = $ppu.IndexOf('jit->fin();', $ppuWarmLink)
$ppuWarmResolve = $ppu.IndexOf('for (auto& sim : jit_mod.symbol_resolvers)', $ppuWarmFinalize)
if ($ppuWarmMarker -lt 0 -or $ppuWarmReuse -le $ppuWarmMarker -or $ppuWarmLink -le $ppuWarmReuse -or
    $ppuWarmFinalize -le $ppuWarmLink -or $ppuWarmResolve -le $ppuWarmFinalize) {
    throw "PPU warm-cache default-scheduler marker does not precede object admission/finalization/symbol resolution."
}

foreach ($forbidden in @(
    'warm_link_affinity_mask',
    'warm_link_affinity.emplace',
	'warm_link_affinity->restore',
	'struct scoped_warm_link_affinity',
	'Thor PPU warm-cache link affinity enabled:',
	'Thor PPU warm-cache link affinity was not applied exactly:'
)) {
    Assert-NotContains $ppu $forbidden "PPU warm-cache admission must stay on the default scheduler: $forbidden"
}

if ($macro -notmatch '(?s)\[ValidateRange\(0,\s*255\)\]\s*\[int\]\$CacheWorkerAffinityMask\s*=\s*0') {
    throw "Thor route cache-worker affinity parameter is missing or not default-off/range-bounded."
}

# The core now defaults these workers to the A510 cluster, so the route must
# distinguish "caller said nothing" from "caller said 0". Writing the parameter
# unconditionally would push a 0 onto every run and silently measure the old
# behavior while claiming to measure the default.
Assert-Contains $macro '$PSBoundParameters.ContainsKey("CacheWorkerAffinityMask")' "Thor route overrides the core default instead of honoring an unset mask."
Assert-Contains $macro 'setprop debug.rpcsx.thor.cache_worker_affinity_mask $cacheWorkerAffinityProperty' "Thor route does not set cache-worker affinity."
Assert-Contains $macro 'getprop debug.rpcsx.thor.cache_worker_affinity_mask' "Thor route does not capture effective cache-worker affinity."

# For the same reason the resets clear the property rather than forcing 0.
# A trailing 0 would outlive the run and disable the default for the next
# ordinary app launch.
$reset = 'setprop debug.rpcsx.thor.cache_worker_affinity_mask ""'
$resetCount = ([regex]::Matches($macro, [regex]::Escape($reset))).Count
if ($resetCount -ne 3) {
    throw "Expected prelaunch, failure, and success affinity resets to clear the property; found $resetCount."
}
if ($macro.Contains('setprop debug.rpcsx.thor.cache_worker_affinity_mask 0')) {
    throw "Thor route still forces the cache-worker affinity property to 0."
}

if ($sprint -notmatch '(?s)\[ValidateRange\(0,\s*255\)\]\s*\[int\]\$AndroidCacheWorkerAffinityMask\s*=\s*0') {
    throw "Speed-sprint cache-worker affinity parameter is missing or not default-off/range-bounded."
}
Assert-Contains $sprint 'CacheWorkerAffinityMask = $AndroidCacheWorkerAffinityMask' "Speed sprint does not forward cache-worker affinity."
Assert-Contains $installer 'getprop debug.rpcsx.thor.cache_worker_affinity_mask' "No-launch installer does not capture cache-worker affinity."

foreach ($scriptPath in @($macroPath, $sprintPath, $installerPath, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -ne 0) {
        throw "PowerShell AST parse failed for $($scriptPath): $($errors -join '; ')"
    }
}

Write-Host "Thor startup RSX/SPU/PPU cache-worker affinity contract: PASS"
