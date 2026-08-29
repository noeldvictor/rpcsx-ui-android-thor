$ErrorActionPreference = "Stop"

$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$macro = Get-Content -LiteralPath $macroPath -Raw
$renderProbePath = Join-Path $PSScriptRoot "invoke_thor_transformers_hle_render_probe.ps1"
$renderProbe = Get-Content -LiteralPath $renderProbePath -Raw
$pcCensusPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\thor_spu_pc_census.h"
$pcCensus = Get-Content -LiteralPath $pcCensusPath -Raw
$perfMonitorPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\perf_monitor.cpp"
$perfMonitor = Get-Content -LiteralPath $perfMonitorPath -Raw
$spuThreadPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\SPUThread.cpp"
$spuThread = Get-Content -LiteralPath $spuThreadPath -Raw
$spuLlvmPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"
$spuLlvm = Get-Content -LiteralPath $spuLlvmPath -Raw
$spuCommonPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\SPUCommonRecompiler.cpp"
$spuCommon = Get-Content -LiteralPath $spuCommonPath -Raw
$ppuThreadPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\PPUThread.cpp"
$ppuThread = Get-Content -LiteralPath $ppuThreadPath -Raw
$cellSpursPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellSpurs.cpp"
$cellSpurs = Get-Content -LiteralPath $cellSpursPath -Raw
$androidPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\android\src\rpcsx-android.cpp"
$android = Get-Content -LiteralPath $androidPath -Raw
$systemHeaderPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\System.h"
$systemHeader = Get-Content -LiteralPath $systemHeaderPath -Raw
$systemPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\System.cpp"
$system = Get-Content -LiteralPath $systemPath -Raw

$requiredFragments = @(
    '[int]$ThermalPreflightSamples = 1',
    '[double]$ThermalPreflightHeadroomC = 0.0',
    '[double]$MaxLaunchSiliconTemperatureC = 70.0',
    '[string]$LfqAny2Any = "off"',
    '[string]$SpursSelectorFixes = "off"',
    '[string]$TasksetSelectAtomic = "off"',
    '$lfqAny2AnyPropertyValue = if ($LfqAny2Any -eq "on") { "1" } else { "0" }',
    '$spursSelectorFixPropertyValue = if ($SpursSelectorFixes -eq "on") { "1" } else { "0" }',
    '$tasksetSelectAtomicPropertyValue = if ($TasksetSelectAtomic -eq "on") { "1" } else { "0" }',
    '"- SPURS ANY2ANY LFQueue: $LfqAny2Any"',
    '"- SPURS selector repair pair: $SpursSelectorFixes"',
    '"- SPURS taskset atomic selection: $TasksetSelectAtomic"',
    '"debug.rpcsx.thor.lfq_any2any"',
    '"setprop debug.rpcsx.thor.lfq_any2any $lfqAny2AnyPropertyValue"',
    '"getprop debug.rpcsx.thor.lfq_any2any"',
    '"setprop debug.rpcsx.thor.lfq_any2any 0"',
    '"lfq-any2any-prelaunch-reset.txt"',
    '"lfq-any2any-failure-reset.txt"',
    '"lfq-any2any-reset.txt"',
    '"spurs-selector-fixes-set.txt"',
    '"spurs-selector-fixes-effective.txt"',
    '"setprop debug.rpcsx.thor.spurs_sel_cond_fix $spursSelectorFixPropertyValue; setprop debug.rpcsx.thor.spurs_signal_fix $spursSelectorFixPropertyValue"',
    '"debug.rpcsx.thor.taskset_select_atomic"',
    '"debug.rpcsx.thor.spu_pc_census"',
    '"debug.rpcsx.thor.spu_event_census"',
    '"debug.rpcsx.thor.edge_event_interp"',
    '"setprop debug.rpcsx.thor.taskset_select_atomic $tasksetSelectAtomicPropertyValue"',
    '"getprop debug.rpcsx.thor.taskset_select_atomic"',
    '"taskset-select-atomic-prelaunch-reset.txt"',
    '"taskset-select-atomic-failure-reset.txt"',
    '"taskset-select-atomic-reset.txt"',
    '[ValidateRange(25, 70)]'
)

foreach ($fragment in $requiredFragments) {
    if (-not $macro.Contains($fragment)) {
        throw "The Transformers HLE LFQueue route is missing: $fragment"
    }
}

if ($macro.Contains('setprop debug.rpcsx.thor.lfq_any2any off')) {
    throw "The LFQueue property accepts 0 as off. The text value off enables this gate."
}

$requiredRenderProbeFragments = @(
    '[ValidateSet("HLE", "LLE")]',
    '[string]$Mode = "HLE"',
    '[string]$LfqAny2Any = "on"',
    '[string]$SpursSelectorFixes = "on"',
    '[string]$TasksetSelectAtomic = "on"',
    '[string]$EdgeEventInterp = "on"',
    '[string]$TaskAttrFix = "on"',
    '[string]$SpuReserve = "on"',
    '[string]$StartPaused = "on"',
    '[string]$YieldFastPath = "off"',
    '[string]$PpuCachedRtimeFix = "on"',
    '[string]$SpursProbe = "off"',
    '[string]$RuntimeCensus = "off"',
    '"debug.rpcsx.thor.hle_libs" = if ($Mode -eq "HLE") { "libsre.sprx" } else { "none" }',
    '"debug.rpcsx.thor.hle_spurs_kernel" = if ($Mode -eq "HLE") { "1" } else { "0" }',
    '$hleLfqAny2Any = if ($Mode -eq "HLE") { $LfqAny2Any } else { "off" }',
    '$hleSpursSelectorFixes = if ($Mode -eq "HLE") { $SpursSelectorFixes } else { "off" }',
    '$hleTasksetSelectAtomic = if ($Mode -eq "HLE") { $TasksetSelectAtomic } else { "off" }',
    'LfqAny2Any = $hleLfqAny2Any',
    'SpursSelectorFixes = $hleSpursSelectorFixes',
    'TasksetSelectAtomic = $hleTasksetSelectAtomic',
    '"debug.rpcsx.thor.edge_event_interp" = if ($Mode -eq "HLE" -and $EdgeEventInterp -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.task_attr_fix" = if ($TaskAttrFix -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_spu_reserve" = if ($Mode -eq "HLE" -and $SpuReserve -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.start_paused" = if ($StartPaused -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.yield_fast_path" = if ($YieldFastPath -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.ppu_cached_rtime_fix" = if ($PpuCachedRtimeFix -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spurs_probe" = if ($SpursProbe -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spurs_atomic_census" = "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_atomic_census" -Value "0"',
    '"debug.rpcsx.thor.draw_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spu_pc_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_pc_census" -Value "0"',
    '"debug.rpcsx.thor.spu_event_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_event_census" -Value "0"',
    '"debug.rpcsx.thor.ppu_pc_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_pc_census" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_probe" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_interp" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.task_attr_fix" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_spu_reserve" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.start_paused" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.yield_fast_path" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_cached_rtime_fix" -Value "0"',
    '[ValidateRange(1, 4096)]',
    '[int]$SpuCachePreloadLimit = 64',
    '[string]$Macro = "wait:8000;shot:render-boundary;wait:4000;shot:active-draw-boundary;stop"',
    'Macro = $Macro',
    'ThermalRuntimeStopHeadroomC = 0',
    'ThermalRuntimeProbeWindowC = 2',
    'ThermalRuntimeTelemetry = "device"',
    'ThermalPreflightSamples = 1',
    'MaxLaunchSiliconTemperatureC = 70',
    'SpuCachePreloadLimit = $SpuCachePreloadLimit',
    'SpuCacheCompileBudgetMs = 50',
    'CacheWorkerAffinityMask = 7'
)

foreach ($fragment in $requiredRenderProbeFragments) {
    if (-not $renderProbe.Contains($fragment)) {
        throw "The Transformers HLE render probe is missing: $fragment"
    }
}

$requiredPcCensusFragments = @(
    '"debug.rpcsx.thor.spu_pc_census"',
    'static constexpr u32 max_samples = 64;',
    'std::memcmp(spu._ptr<u8>(0x3000), edge_signature.data(), edge_signature.size())',
    'Thor EDGE PC sample=%u',
	'r3=0x%08x r4=0x%08x r5=0x%08x',
	'out=%u intr=%u in=%u state=0x%08x',
	'group=%u spursrun=%u blocks=%llu recover=%llu failures=%llu',
	'hash=0x%016llx interp=%u',
	'spu.state.load().toUnderlying()',
	'spu.group->run_state.load()',
    'thor::spu_pc_census_tick();'
)

foreach ($fragment in $requiredPcCensusFragments) {
    if (-not ($pcCensus.Contains($fragment) -or $perfMonitor.Contains($fragment))) {
        throw "The edgeZlib SPU PC census is missing: $fragment"
    }
}

$requiredEventCensusFragments = @(
    '"debug.rpcsx.thor.spu_event_census"',
    'static std::atomic<u32> s_event_count{0};',
    'if (n < 32)',
	'queue_depth = static_cast<u32>(queue->events.size());',
	'ppu_waiter = queue->pq ? 1 : 0;',
	'state.load().toUnderlying()',
	'is_thor_edge_zlib_spu(*this)',
	'pc == 0xa500',
	'pc == 0xa514',
	'Thor EDGE EVENT out-entry #%u',
	'Thor EDGE EVENT intr-entry #%u',
	'Thor EDGE EVENT result #%u',
    'Thor SPU EVENT #%u'
)

$requiredPpuCachedRtimeFragments = @(
    'static bool thor_ppu_cached_rtime_fix() noexcept',
    '"debug.rpcsx.thor.ppu_cached_rtime_fix"',
    'if (!thor_ppu_cached_rtime_fix())',
    'ppu.rtime -= 128;',
    'ppu.rtime += 128;'
)

foreach ($fragment in $requiredPpuCachedRtimeFragments) {
    if (-not $ppuThread.Contains($fragment)) {
        throw "The PPU cached reservation fix is missing: $fragment"
    }
}

$requiredTransformersSpuReserveFragments = @(
    'static bool thor_transformers_spu_reserve() noexcept',
    '"debug.rpcsx.thor.transformers_spu_reserve"',
    's_on && Emu.GetTitleID() == "BLUS30357"',
    'wnum == 6',
    'size == 0x4000',
    'minContention == 1 && maxContention == 5',
    'maxContention = 4;'
)

foreach ($fragment in $requiredTransformersSpuReserveFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers SPU reserve is missing: $fragment"
    }
}

if ($cellSpurs.Contains('pm.addr() == 0x02390000')) {
    throw "The Transformers SPU reserve must not depend on a variable policy-image address."
}

$requiredStartPausedFragments = @(
    'static std::atomic<bool> g_thor_start_paused_ready{false};',
    '"debug.rpcsx.thor.start_paused", false',
    'Emu.SetForceBoot(!startPaused);',
    'Emu.SetPreventAutostart(startPaused);',
    'result == game_boot_result::no_errors && Emu.IsReady()',
    '"Thor start-paused gate is ready."',
    '"Thor start-paused gate released."',
    'Emu.Run(true);'
)

foreach ($fragment in $requiredStartPausedFragments) {
    if (-not $android.Contains($fragment)) {
        throw "The Thor start-paused gate is missing: $fragment"
    }
}

$requiredAutostartFragments = @(
    'bool m_prevent_autostart = false;',
    'void SetPreventAutostart(bool prevent_autostart);',
    'void Emulator::SetPreventAutostart(bool prevent_autostart)',
    'm_prevent_autostart = prevent_autostart;',
    'const bool autostart = !std::exchange(m_prevent_autostart, false) &&'
)

foreach ($fragment in $requiredAutostartFragments) {
    if (-not ($systemHeader.Contains($fragment) -or $system.Contains($fragment))) {
        throw "The one-shot autostart control is missing: $fragment"
    }
}

foreach ($fragment in $requiredEventCensusFragments) {
    if (-not $spuThread.Contains($fragment)) {
        throw "The SPU event census is missing: $fragment"
    }
}

$requiredEdgeEventInterpFragments = @(
    '"debug.rpcsx.thor.edge_event_interp"',
    'return false;',
    'm_pos == 0x0a4d8',
    'emit_thor_edge_event_interp_guard();',
    'm_ir->getInt64(0x82c07e4302244742)',
    'm_ir->getInt64(0x826d0142020f3e43)',
    'm_ir->CreateCondBr(m_ir->CreateAnd(is_edge0, is_edge1), interp, native, m_md_unlikely);',
	'is_thor_edge_event_interp_dispatch(spu)',
	'spu.pc != 0x0a4d8',
	'std::memcmp(spu._ptr<u8>(0x3000), s_edge_signature.data(), s_edge_signature.size())',
	'Thor EDGE EVENT DISPATCH INTERPRETER enter #%u',
	'Thor EDGE EVENT DISPATCH INTERPRETER leave #%u',
    'spu->interp_fallback_begin = 0x0a4d8;',
    'spu->interp_fallback_end = 0x0a520;',
    'spu_recompiler_base::old_interpreter(*spu, spu->_ptr<u8>(0), nullptr);',
    'Thor EDGE EVENT INTERPRETER enter #%u',
    'Thor EDGE EVENT INTERPRETER leave #%u'
)

foreach ($fragment in $requiredEdgeEventInterpFragments) {
    if (-not ($spuLlvm.Contains($fragment) -or $spuCommon.Contains($fragment))) {
        throw "The edgeZlib event interpreter handoff is missing: $fragment"
    }
}

Write-Output "Transformers HLE LFQueue route contract passed."
