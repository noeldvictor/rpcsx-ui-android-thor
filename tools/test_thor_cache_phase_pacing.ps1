$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$phasePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/cache_phase_pacing.h"
$spuPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$rsxPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$macroPath = Join-Path $repoRoot "tools/thor_input_macro.ps1"
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"

$phaseSource = Get-Content -LiteralPath $phasePath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$rsxSource = Get-Content -LiteralPath $rsxPath -Raw
$macroSource = Get-Content -LiteralPath $macroPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw

$requiredPhaseFragments = @(
    'inline atomic_t<u64> spu_preload_started{};',
    'inline atomic_t<u64> spu_preload_complete{};'
)
$requiredSpuFragments = @(
    'const u64 emulation_id = static_cast<u64>(Emu.GetEmulationIdentifier());',
    'spu_preload_started.release(emulation_id);',
    'struct preload_phase_completion_guard',
    'spu_preload_complete.release(emulation_id);'
)
$requiredRsxFragments = @(
    '__system_property_get("debug.rpcsx.thor.cache_phase_pacing", value)',
    'std::getenv("RPCSX_THOR_CACHE_PHASE_PACING")',
    'const auto deadline = start + 5s;',
    'steady_clock::now() < deadline',
    "thread_ctrl::wait_for(5'000);",
    'wait_for_android_spu_preload_phase();',
    'compile_shaders(preload_workers, unpacked, entry_count, dlg, compile_budget_ms, std::forward<Args>(args)...);'
)

foreach ($contract in @(
    @{ Name = "shared phase"; Source = $phaseSource; Fragments = $requiredPhaseFragments },
    @{ Name = "SPU publisher"; Source = $spuSource; Fragments = $requiredSpuFragments },
    @{ Name = "RSX consumer"; Source = $rsxSource; Fragments = $requiredRsxFragments }
)) {
    foreach ($fragment in $contract.Fragments) {
        if (-not $contract.Source.Contains($fragment)) {
            throw "Missing $($contract.Name) contract fragment: $fragment"
        }
    }
}

$androidGuardIndex = $rsxSource.LastIndexOf('#ifdef __ANDROID__', $rsxSource.IndexOf('static bool get_android_cache_phase_pacing()'))
$waitFunctionIndex = $rsxSource.IndexOf('static void wait_for_android_spu_preload_phase()')
$guardEndIndex = $rsxSource.IndexOf('#endif', $waitFunctionIndex)
if ($androidGuardIndex -lt 0 -or $waitFunctionIndex -le $androidGuardIndex -or $guardEndIndex -le $waitFunctionIndex) {
    throw "Cache phase pacing is no longer Android-only."
}

$waitCallIndex = $rsxSource.IndexOf('wait_for_android_spu_preload_phase();')
$compileCallIndex = $rsxSource.IndexOf('compile_shaders(preload_workers, unpacked, entry_count, dlg, compile_budget_ms, std::forward<Args>(args)...);', $waitCallIndex)
if ($waitCallIndex -lt 0 -or $compileCallIndex -le $waitCallIndex) {
    throw "RSX phase wait no longer precedes pipeline compilation."
}

$macroContracts = @(
    '[string]$CachePhasePacing = "off"',
    'setprop debug.rpcsx.thor.cache_phase_pacing $CachePhasePacing',
    'getprop debug.rpcsx.thor.cache_phase_pacing',
    'cache-phase-pacing-prelaunch-reset.txt',
    'cache-phase-pacing-failure-reset.txt',
    'cache-phase-pacing-reset.txt',
    'if ($PostSnapshot -or $BootGame)'
)
foreach ($fragment in $macroContracts) {
    if (-not $macroSource.Contains($fragment)) {
        throw "Missing Thor route phase-pacing contract fragment: $fragment"
    }
}
if (-not $sprintSource.Contains('[string]$AndroidCachePhasePacing = "off"') -or
    -not $sprintSource.Contains('CachePhasePacing = $AndroidCachePhasePacing')) {
    throw "Eternal Sonata route wrapper no longer forwards default-off cache phase pacing."
}

Write-Output "Thor startup cache phase pacing contract passed: Android-only, opt-in/default-off, generation-safe, timeout-bounded, ordered before RSX compilation, route resets and boot-failure evidence preserved."
