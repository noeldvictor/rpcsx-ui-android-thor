$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$phasePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/cache_phase_pacing.h"
$rsxPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/rsx_cache.h"
$decompilerPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/Emu/RSX/Program/FragmentProgramDecompiler.cpp"

$phase = Get-Content -LiteralPath $phasePath -Raw
$rsx = Get-Content -LiteralPath $rsxPath -Raw
$decompiler = Get-Content -LiteralPath $decompilerPath -Raw

function Assert-Contains([string]$Source, [string]$Fragment, [string]$Message) {
    if (-not $Source.Contains($Fragment)) {
        throw $Message
    }
}

$diagnostics = [ordered]@{
    bad_scale = 'Bad scale: %d'
    unexpected_precision = 'Unexpected precision modifier (%d)'
    nested_indexed_loop = 'Nested loop with indexed load was detected.'
    indexed_control_override = 'Indexed load with control override mask detected.'
    bad_source_register = 'Bad src reg num: %d'
    unknown_source_type = 'Src type 3 used, opcode=0x%X'
    break_outside_loop = 'BRK opcode found outside of a loop'
    unimplemented_call = 'Unimplemented SIP instruction: CAL'
    unknown_instruction = 'Unknown/illegal instruction: 0x%x'
    hanging_block = 'Hanging block found at end of shader.'
}

foreach ($entry in $diagnostics.GetEnumerator()) {
    Assert-Contains $phase "$($entry.Key)," "Missing preload diagnostic category $($entry.Key)."
    Assert-Contains $decompiler "rsx_preload_diagnostic::$($entry.Key)" "Decompiler diagnostic $($entry.Key) is not routed through the preload summary."
    Assert-Contains $decompiler $entry.Value "Decompiler diagnostic text disappeared for $($entry.Key)."
}

$phaseContracts = @(
    'inline thread_local bool rsx_preload_diagnostic_summary_active = false;',
    'inline thread_local u32 rsx_preload_diagnostic_seen_mask = 0;',
    'inline thread_local u32 rsx_preload_diagnostics_suppressed = 0;',
    'if (!rsx_preload_diagnostic_summary_active)',
    'rsx_preload_diagnostic_seen_mask |= bit;',
    '++rsx_preload_diagnostics_suppressed;',
    'inline bool should_emit_rsx_preload_diagnostic(rsx_preload_diagnostic) noexcept'
)
foreach ($fragment in $phaseContracts) {
    Assert-Contains $phase $fragment "Missing preload diagnostic compaction contract: $fragment"
}

$tlsIndex = $phase.IndexOf('inline thread_local bool rsx_preload_diagnostic_summary_active')
$androidGuardIndex = $phase.LastIndexOf('#ifdef __ANDROID__', $tlsIndex)
$desktopStubIndex = $phase.IndexOf('#else', $tlsIndex)
if ($androidGuardIndex -lt 0 -or $desktopStubIndex -le $tlsIndex) {
    throw 'Preload diagnostic TLS state is no longer Android-only.'
}

$rsxContracts = @(
    'g_cfg.video.renderer == video_renderer::vulkan',
    'Emu.GetTitleID() == "BLUS30161"',
    'nb_workers > 1 || rpcsx::startup_cache_phase::get_cache_worker_affinity_mask',
    'begin_rsx_preload_diagnostic_summary();',
    'suppressed_preload_diagnostics += rpcsx::startup_cache_phase::end_rsx_preload_diagnostic_summary();',
    'Android RSX shader-cache preload retained one decompiler diagnostic per kind and worker; suppressed %u duplicates.'
)
foreach ($fragment in $rsxContracts) {
    Assert-Contains $rsx $fragment "Missing RSX preload diagnostic summary contract: $fragment"
}

$beginIndex = $rsx.IndexOf('begin_rsx_preload_diagnostic_summary();')
$preloadBodyIndex = $rsx.IndexOf('m_storage.preload_programs(')
$preloadIndex = $rsx.IndexOf('load_one(pos);', $beginIndex)
$endIndex = $rsx.IndexOf('end_rsx_preload_diagnostic_summary();', $preloadIndex)
$summaryIndex = $rsx.IndexOf('Android RSX shader-cache preload retained', $endIndex)
if ($preloadBodyIndex -lt 0 -or $beginIndex -lt 0 -or $preloadIndex -le $beginIndex -or $endIndex -le $preloadIndex -or $summaryIndex -le $endIndex) {
    throw 'RSX preload diagnostic scope or summary ordering changed.'
}

$guardCount = ([regex]::Matches($decompiler, 'should_emit_rsx_preload_diagnostic\(')).Count
$errorCount = ([regex]::Matches($decompiler, 'rsx_log\.error\(')).Count
if ($guardCount -ne $diagnostics.Count -or $errorCount -ne $diagnostics.Count) {
    throw "Expected $($diagnostics.Count) guarded decompiler errors, found guards=$guardCount errors=$errorCount."
}

Write-Output "Thor RSX preload diagnostic compaction contract passed: BLUS30161 Android Vulkan load workers retain representative errors, aggregate duplicates, and leave non-Android/runtime diagnostics unchanged."
