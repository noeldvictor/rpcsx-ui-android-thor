$ErrorActionPreference = "Stop"

$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$macro = Get-Content -LiteralPath $macroPath -Raw
$renderProbePath = Join-Path $PSScriptRoot "invoke_thor_transformers_hle_render_probe.ps1"
$renderProbe = Get-Content -LiteralPath $renderProbePath -Raw
$pcCensusPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\thor_spu_pc_census.h"
$pcCensus = Get-Content -LiteralPath $pcCensusPath -Raw
$eventWaitProbePath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\thor_spurs_event_wait_probe.h"
$eventWaitProbe = Get-Content -LiteralPath $eventWaitProbePath -Raw
$lsDumpPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\rpcs3\Emu\Cell\thor_spu_ls_dump.h"
$lsDump = Get-Content -LiteralPath $lsDumpPath -Raw
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
$lwmutexPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\sys_lwmutex_.cpp"
$lwmutex = Get-Content -LiteralPath $lwmutexPath -Raw
$lv2LwmutexPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\kernel\cellos\src\sys_lwmutex.cpp"
$lv2Lwmutex = Get-Content -LiteralPath $lv2LwmutexPath -Raw
$sysEventPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\kernel\cellos\src\sys_event.cpp"
$sysEvent = Get-Content -LiteralPath $sysEventPath -Raw
$lv2Path = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\kernel\cellos\src\lv2.cpp"
$lv2 = Get-Content -LiteralPath $lv2Path -Raw
$sysSyncPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\kernel\cellos\include\cellos\sys_sync.h"
$sysSync = Get-Content -LiteralPath $sysSyncPath -Raw
$cellAudioPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\ps3fw\cellAudio.cpp"
$cellAudio = Get-Content -LiteralPath $cellAudioPath -Raw
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
    '[string]$RequireManagedProfile = "on"',
    '[string]$ReplaceCustomProfile = "on"',
    '$lfqAny2AnyPropertyValue = if ($LfqAny2Any -eq "on") { "1" } else { "0" }',
    '$spursSelectorFixPropertyValue = if ($SpursSelectorFixes -eq "on") { "1" } else { "0" }',
    '$tasksetSelectAtomicPropertyValue = if ($TasksetSelectAtomic -eq "on") { "1" } else { "0" }',
    '$requireManagedProfileValue = if ($RequireManagedProfile -eq "on") { "true" } else { "false" }',
    '$replaceCustomProfileValue = if ($ReplaceCustomProfile -eq "on") { "true" } else { "false" }',
    '--ez thorRequireManagedProfile $requireManagedProfileValue',
    '--ez thorReplaceCustomProfile $replaceCustomProfileValue',
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
    '"debug.rpcsx.thor.fmod_event_interp"',
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
    '[string]$QueuePublishOrder = "on"',
    '[string]$QueueDiagnostics = "off"',
    '[ValidateSet(1, 2, 4, 8, 16, 32, 64)]',
    '[int]$YieldRedispatchEvery = 1',
    '[string]$PpuCachedRtimeFix = "on"',
    '[string]$SpursProbe = "off"',
    '[string]$SpursAtomicCensus = "off"',
    '[string]$EdgeTaskCensus = "off"',
    '[string]$EdgeEventWaitTrace = "off"',
    '[string]$FmodEventWaitTrace = "off"',
    '[string]$FmodEventInterp = "on"',
    '[string]$FmodAudioWakeFix = "on"',
    '[string]$PhysxStartInterp = "on"',
    '[string]$RsxFifoOrdered = "off"',
    '[string]$RuntimeCensus = "off"',
    '[string]$SpuPcCensus = "off"',
    '[string]$PpuPcCensus = "off"',
    '[string]$PpuProfiler = "off"',
    '[string]$LwmutexTrace = "off"',
    '[string]$InputMode = "Direct"',
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
    '"debug.rpcsx.thor.queue_publish_order" = if ($Mode -eq "HLE" -and $QueuePublishOrder -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.queue_diagnostics" = if ($Mode -eq "HLE" -and $QueueDiagnostics -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.yield_redispatch_fix" = "$YieldRedispatchEvery"',
    '"debug.rpcsx.thor.ppu_cached_rtime_fix" = if ($PpuCachedRtimeFix -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spurs_probe" = if ($SpursProbe -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spurs_atomic_census" = if ($SpursAtomicCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_atomic_census" -Value "0"',
    '"debug.rpcsx.thor.edge_task_census" = if ($EdgeTaskCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_task_census" -Value "0"',
    '"debug.rpcsx.thor.edge_event_wait_trace" = if ($Mode -eq "HLE" -and $EdgeEventWaitTrace -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_wait_trace" -Value "0"',
    '"debug.rpcsx.thor.fmod_event_wait_trace" = if ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.fmod_event_interp" = if ($Mode -eq "HLE" -and $FmodEventInterp -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_audio_wake_fix" = if ($Mode -eq "HLE" -and $FmodAudioWakeFix -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_physx_queue_wait" = if ($Mode -eq "HLE" -and $PhysxQueueWait -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_physx_start_interp" = if ($Mode -eq "HLE" -and $PhysxStartInterp -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_fifo_ordered" = if ($Mode -eq "HLE" -and $RsxFifoOrdered -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.transformers_lwmutex_trace" = if ($Mode -eq "HLE" -and $LwmutexTrace -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spu_ls_dump" = if ($Mode -eq "HLE" -and $PhysxLsDump -eq "on") { "@physx" } elseif ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on") { "@fmod" } else { "0" }',
    '[double]$SliceAfterStartSeconds = 0.0',
    '$effectiveAfterStartSliceSeconds = if ($SliceAfterStartSeconds -gt 0.0)',
    '$afterStartArguments.seconds = $effectiveAfterStartSliceSeconds',
    '[string]$SliceAfterStartHandoffMatch = ''Thread "PPU PhysX thread" created''',
    '[double]$SliceAfterHandoffSeconds = 30.0',
    '[ValidateRange(0.0, 300.0)]',
    '$afterStartArguments.stopMatch = $SliceAfterStartHandoffMatch',
    'slice-loop-after-start-handoff.json',
    '$afterStartArguments.seconds = $effectiveAfterHandoffSliceSeconds',
    '$afterStartArguments.maxDurationS = $effectiveAfterHandoffSliceSeconds',
    'The after-START handoff loop did not reach its requested paused marker.',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.fmod_event_wait_trace" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.fmod_event_interp" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_audio_wake_fix" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_physx_queue_wait" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_physx_start_interp" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_fifo_ordered" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_lwmutex_trace" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_ls_dump" -Value "0"',
    '"debug.rpcsx.thor.draw_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.spu_pc_census" = if ($RuntimeCensus -eq "on" -or $SpuPcCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_pc_census" -Value "0"',
    '"debug.rpcsx.thor.spu_event_census" = if ($RuntimeCensus -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spu_event_census" -Value "0"',
    '"debug.rpcsx.thor.ppu_pc_census" = if ($RuntimeCensus -eq "on" -or $PpuPcCensus -eq "on") { "1" } else { "0" }',
    '"debug.rpcsx.thor.ppu_prof" = if ($PpuProfiler -eq "on") { "1" } else { "0" }',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_pc_census" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_prof" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.spurs_probe" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.edge_event_interp" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.task_attr_fix" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.transformers_spu_reserve" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.start_paused" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.yield_fast_path" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.queue_publish_order" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.queue_diagnostics" -Value "0"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.ppu_cached_rtime_fix" -Value "0"',
    '[ValidateRange(1, 4096)]',
    '[int]$SpuCachePreloadLimit = 64',
    '[string]$Macro = "wait:8000;shot:render-boundary;wait:4000;shot:active-draw-boundary;stop"',
    '[switch]$SliceLoop',
    '[ValidateRange(0.1, 15.0)]',
    '[double]$SliceSeconds = 1.0',
    '[int]$MaxSlices = 64',
    '[double]$MaxSliceHostSeconds = 240',
    '[int]$SliceCoolTimeoutSeconds = 120',
    '[int]$SliceResumeStableSamples = 3',
    '[double]$SliceResumeSampleIntervalSeconds = 1.0',
    '[string]$SliceStopMatch = "Thor LATE LOAD IO COMPLETION: sample=2"',
    '[string]$SliceArmMatch = ""',
    '[int]$SlicePostArmSlices = 0',
    '[switch]$SlicePressStartAfterFirstLoop',
    '[int]$SliceAfterStartMaxSlices = 32',
    '[double]$SliceAfterStartMaxHostSeconds = 240',
    '[string]$SliceAfterStartStopMatch = "Thor Transformers PhysX queue startup wait:"',
    '[int]$SliceAfterStartPostMarkerSlices = 0',
    'if ($Mode -eq "HLE" -and $FmodEventWaitTrace -eq "on" -and',
    '[string]::IsNullOrWhiteSpace($SliceArmMatch) -and',
    '-not $PSBoundParameters.ContainsKey("SliceStopMatch")) {',
    '$SliceStopMatch = "Thor FMOD EFWAIT RETURN #0"',
    'if ($SliceLoop -and $SliceStopMatch.StartsWith("Thor LATE LOAD") -and',
    'throw "A late-load slice marker requires -PpuPcCensus on or -RuntimeCensus on."',
    'throw "Post-arm slices require -SliceArmMatch."',
    'if ($SliceLoop -and $StartPaused -ne "on")',
    'Macro = if ($SliceLoop) { "" } else { $Macro }',
    'InputMode = $InputMode',
    'ThermalRuntimeStopHeadroomC = 0',
    'ThermalRuntimeProbeWindowC = 2',
    'ThermalRuntimeTelemetry = if ($SliceLoop) { "full" } else { "device" }',
    'ThermalPreflightSamples = 1',
    'MaxLaunchSiliconTemperatureC = 70',
    'SpuCachePreloadLimit = $SpuCachePreloadLimit',
    'SpuCacheCompileBudgetMs = 50',
    'CacheWorkerAffinityMask = 7',
    '$sliceLoopProperties["debug.rpcsx.thor.spu_cache_preload_limit"] = "$SpuCachePreloadLimit"',
    '$sliceLoopProperties["debug.rpcsx.thor.spu_cache_compile_budget_ms"] = "50"',
    '$sliceLoopProperties["debug.rpcsx.thor.spu_native_object_cache"] = "on"',
    '$sliceLoopProperties["debug.rpcsx.thor.cache_worker_affinity_mask"] = "7"',
    '$sliceLoopProperties["debug.rpcsx.thor.lfq_any2any"] = if ($hleLfqAny2Any -eq "on") { "1" } else { "0" }',
    '$sliceLoopProperties["debug.rpcsx.thor.spurs_sel_cond_fix"] = if ($hleSpursSelectorFixes -eq "on") { "1" } else { "0" }',
    '$sliceLoopProperties["debug.rpcsx.thor.spurs_signal_fix"] = if ($hleSpursSelectorFixes -eq "on") { "1" } else { "0" }',
    '$sliceLoopProperties["debug.rpcsx.thor.taskset_select_atomic"] = if ($hleTasksetSelectAtomic -eq "on") { "1" } else { "0" }',
    'function Set-ThorRenderProbeSliceProfile',
    '"slice-loop-profile-effective.txt"',
    "if (`$actual -cne [string]`$property.Value)",
    'Set-ThorRenderProbeSliceProfile -CaptureDir $captureDir',
    'RequireManagedProfile = "off"',
    'ReplaceCustomProfile = "off"',
    '$env:THOR_CALL_ARGS = $Arguments | ConvertTo-Json -Depth 8 -Compress',
    '-Name "thor_slice_loop"',
    'Start-ThorSliceDeviceGuard -CaptureDir $captureDir',
    '$sliceResult = ($controllerOutput -join [Environment]::NewLine) | ConvertFrom-Json',
    'if ($SlicePressStartAfterFirstLoop) {',
    '$transformersStartCheckPath = Join-Path $PSScriptRoot "bench\thor_transformers_start_check.py"',
    'function Test-ThorTransformersStartFrame',
    '$startGateArguments.maxSlices = 1',
    '$startGateArguments.stopMatch = "__THOR_TRANSFORMERS_START_GATE_UNREACHED__"',
    '$startGateArguments.Remove("armMatch")',
    '$startGateArguments.Remove("postArmSlices")',
    'Test-ThorTransformersStartFrame',
    'throw "The START visual gate did not find the Unreal and PhysX legal frame."',
    '-Name "thor_wait_cool_paused"',
    'targetC = 65',
    'stableSamples = 2',
    '-Name "thor_press"',
    '$afterStartArguments.maxSlices = $SliceAfterStartMaxSlices',
    '$afterStartArguments.maxHostS = $SliceAfterStartMaxHostSeconds',
    'if ($SliceAfterStartPostMarkerSlices -gt 0) {',
    '$afterStartArguments.armMatch = $SliceAfterStartStopMatch',
    '$afterStartArguments.postArmSlices = $SliceAfterStartPostMarkerSlices',
    '-OutputName "slice-loop-after-start.json"',
    'maxStartC = 70',
    'resumeTargetC = 68',
    'resumeStableSamples = $SliceResumeStableSamples',
    'resumeSampleIntervalS = $SliceResumeSampleIntervalSeconds',
    'maxSiliconC = 72',
    'markerEvery = 1',
    'allowStarting = $true',
    '$sliceArguments.armMatch = $SliceArmMatch',
    '$sliceArguments.postArmSlices = $SlicePostArmSlices',
    '-Name "thor_screenshot"',
    '$pidRows = @(',
    'Get-Content -LiteralPath $pidEvidence',
    '$sliceResult.markerReached',
    'Write-ThorStandardSnapshot -Adb $adb -CaptureDir $captureDir -Package "net.rpcsx.easy" -Prefix "slice-loop"',
    '-Name "thor_stop"',
    'for ($stopAttempt = 1; $stopAttempt -le 5; $stopAttempt++)',
    '& $adb -s $Serial shell am force-stop net.rpcsx.easy',
    '-Name "thor_clearprops"'
)

foreach ($fragment in $requiredRenderProbeFragments) {
    if (-not $renderProbe.Contains($fragment)) {
        throw "The Transformers HLE render probe is missing: $fragment"
    }
}

$requiredTransformersFifoFragments = @(
    'm_title_id == "BLUS30357"',
    '"debug.rpcsx.thor.transformers_fifo_ordered"',
    'g_cfg.core.rsx_fifo_accuracy.from_string("Ordered & Atomic")',
    '"Thor: Transformers RSX FIFO accuracy forced to %s"'
)

foreach ($fragment in $requiredTransformersFifoFragments) {
    if (-not $system.Contains($fragment)) {
        throw "The Transformers ordered FIFO route is missing: $fragment"
    }
}

if ($renderProbe.Contains('Get-ThorEvidenceBody')) {
    throw "The Transformers HLE render probe uses a private input-macro helper."
}

if ($renderProbe.Contains('$sliceResult.holdMode -ne "process"')) {
    throw "The Transformers HLE route skips a stable process-held screenshot."
}

$requiredLwmutexTraceFragments = @(
    'constexpr u32 thor_transformers_main_lwmutex_lock_lr = 0x00e28c5c;',
    'constexpr u32 thor_transformers_lwmutex_unlock_lr = 0x00e28c18;',
    'constexpr u32 thor_transformers_lwmutex_trace_limit = 128;',
    '"debug.rpcsx.thor.transformers_lwmutex_trace"',
    'Emu.GetTitleID() == "BLUS30357"',
    'static_cast<u32>(ppu.lr) != thor_transformers_main_lwmutex_lock_lr',
    'static_cast<std::string>(ppu.thread_name).find("main_thread")',
    'g_thor_transformers_lwmutex_addr.compare_exchange_strong(',
    '"Thor TWC LWM ARM:',
    '"Thor TWC LWM #%u:',
    'thor_transformers_lwmutex_caller_lr(ppu)',
    'caller=0x%x',
    '"LOCK-SLEEP"',
    '"LOCK-WAKE"',
    '"UNLOCK-ENTER"',
    '"UNLOCK-RETURN"'
)

foreach ($fragment in $requiredLwmutexTraceFragments) {
    if (-not $lwmutex.Contains($fragment)) {
        throw "The bounded Transformers lightweight-mutex trace is missing: $fragment"
    }
}

$requiredLv2LwmutexTraceFragments = @(
    'constexpr u32 thor_transformers_main_lwmutex_lock_lr = 0x00e28c5c;',
    'constexpr u32 thor_transformers_lv2_lwmutex_trace_limit = 128;',
    '"debug.rpcsx.thor.transformers_lwmutex_trace"',
    'Emu.GetTitleID() == "BLUS30357"',
    "ppu.id != 0x0100'0000",
    'static_cast<u32>(ppu.lr) != thor_transformers_main_lwmutex_lock_lr',
    'g_thor_transformers_lv2_lwmutex_id.compare_exchange_strong(',
    '"Thor TWC LV2 ARM:',
    '"Thor TWC LV2 #%u:',
    'thor_transformers_lv2_lwmutex_caller_lr(ppu)',
    'caller=0x%x',
    'atomic_storage<s32>::load(mutex.lv2_control.raw().signaled)',
    'const u32 queue_ppu = queue ? queue->id : 0;',
    '"LOCK-SLEEP"',
    '"LOCK-WAKE"',
    '"UNLOCK-ENTER"',
    '"UNLOCK-HANDOFF"',
    '"UNLOCK-RETURN"',
    'thor_transformers_reown_with_trace(',
    '"Thor TWC POST AUDIO REOWN #%u.%u: stage=PRE-SCHEDULE "',
    '"Thor TWC POST AUDIO REOWN #%u.%u: stage=POST-SCHEDULE "',
    '"Thor TWC POST AUDIO REOWN #%u: stage=POST-FETCH attempts=%u "',
    'head && next == head ? 1u : 0u'
)

foreach ($fragment in $requiredLv2LwmutexTraceFragments) {
    if (-not $lv2Lwmutex.Contains($fragment)) {
        throw "The bounded Transformers kernel mutex trace is missing: $fragment"
    }
}

$requiredCellAudioTraceFragments = @(
    'constexpr u32 thor_transformers_audio_trace_limit = 64;',
    '"debug.rpcsx.thor.transformers_lwmutex_trace"',
    'Emu.GetTitleID() == "BLUS30357"',
    'g_thor_transformers_audio_trace_seq.fetch_add(1, std::memory_order_relaxed)',
    '"Thor TWC AUDIO #%u: SET',
    '"Thor TWC AUDIO #%u: SEND',
    'const CellError result = queues[i]->send(',
    'thor_transformers_audio_trace_send(event_period, *queues[i],',
    'thor_transformers_audio_trace_set('
)

foreach ($fragment in $requiredCellAudioTraceFragments) {
    if (-not $cellAudio.Contains($fragment)) {
        throw "The bounded Transformers cellAudio trace is missing: $fragment"
    }
}

$requiredAudioQueueTraceFragments = @(
    'constexpr u64 thor_transformers_audio_queue_key = 0x80004d494f323221;',
    'constexpr u32 thor_transformers_audio_queue_trace_limit = 64;',
    'constexpr u32 thor_transformers_audio_wake_log_limit = 8;',
    '"debug.rpcsx.thor.transformers_lwmutex_trace"',
    'Emu.GetTitleID() == "BLUS30357"',
    '"Thor TWC AUDIOQ #%u:',
    '"SEND-STORED"',
    '"SEND-FULL"',
    '"SEND-WAKE"',
    '"RECV-WAIT"',
    '"RECV-READY"',
    '"debug.rpcsx.thor.transformers_audio_wake_fix"',
    'lv2_obj::complete_deferred_wake(ppu)',
    'g_thor_transformers_audio_wake_log_seq.fetch_add(',
    '"Thor TWC AUDIO WAKE FIX:'
)

foreach ($fragment in $requiredAudioQueueTraceFragments) {
    if (-not $sysEvent.Contains($fragment)) {
        throw "The bounded Transformers audio queue trace is missing: $fragment"
    }
}

$requiredDeferredWakeFragments = @(
    'u32 lv2_obj::complete_deferred_wake(ppu_thread &thread)',
    'if (!g_scheduler_ready || !g_pending)',
    'for (usz slots = get_ppu_thread_count_for_scheduler(); target && slots;',
    'cpu_flag::wait - state',
    'state += cpu_flag::signal;',
    'state -= cpu_flag::suspend;',
    'thread.state.notify_one();'
)

foreach ($fragment in $requiredDeferredWakeFragments) {
    if (-not $lv2.Contains($fragment)) {
        throw "The deferred PPU wake repair is missing: $fragment"
    }
}

if (-not $sysSync.Contains('static u32 complete_deferred_wake(ppu_thread &thread);')) {
    throw "The deferred PPU wake repair declaration is missing."
}

$requiredOwnerWakeFragments = @(
    'bool lv2_obj::force_owner_wake_after_waiter_sleep(ppu_thread &thread)',
    'if (!g_scheduler_ready)',
    'std::exchange(thread.ack_suspend, false)',
    'state += cpu_flag::signal;',
    'state -= cpu_flag::suspend;',
    'thread.state.notify_one();'
)

foreach ($fragment in $requiredOwnerWakeFragments) {
    if (-not $lv2.Contains($fragment)) {
        throw "The post-wait owner wake repair is missing: $fragment"
    }
}

if (-not $sysSync.Contains('static bool force_owner_wake_after_waiter_sleep(ppu_thread &thread);')) {
    throw "The post-wait owner wake repair declaration is missing."
}

$requiredAudioOwnerWakeFragments = @(
    '"debug.rpcsx.thor.transformers_audio_wake_fix"',
    'thor_transformers_main_lwmutex_caller = 0x00dd6264',
    'thor_transformers_post_audio_lwmutex_id = 0x95008d00',
    'lv2_obj::force_owner_wake_after_waiter_sleep(*owner)',
    '"Thor TWC AUDIO OWNER WAKE:',
    'g_thor_transformers_audio_owner_wake_completed.store(',
    'g_thor_transformers_audio_owner_wake_completed.load(',
    'thor_transformers_audio_owner_candidate_limit = 64',
    '"Thor TWC AUDIO OWNER CANDIDATE #%u:',
    '"FMOD libAudio event receive thread"',
    'thor_transformers_discover_audio_dependency(lwmutex_id);',
    'idm::select<lv2_obj, lv2_lwmutex>(',
    'for (auto cpu = candidate.load_sq(); cpu; cpu = cpu->next_cpu)',
    'cpu->id == 0x0100''000c',
    'idm::unlocked',
    'g_thor_transformers_audio_dependency_lwmutex_id.store(',
    'g_thor_transformers_audio_dependency_owner_id.store(',
    'dependency_owner_id != waiting_ppu.id',
    'dependency_owner_id != owner_id',
    'phase=queue-scan',
    'phase=queue-scan-miss',
    'thor_transformers_audio_dependency_yield_limit = 4096',
    'cpu_flag::suspend - owner->state',
    'std::this_thread::yield();',
    'thor_transformers_discover_audio_dependency(lwmutex_id, false)',
    '"Thor TWC AUDIO OWNER DEFERRED SCAN:',
    'found ? "candidate-deferred"',
    '"Thor TWC AUDIO OWNER CHAIN WAKE #%u:',
    'bool thor_transformers_audio_owner_wake_completed() noexcept',
    'std::memory_order_acquire'
)

foreach ($fragment in $requiredAudioOwnerWakeFragments) {
    if (-not $lv2Lwmutex.Contains($fragment)) {
        throw "The deferred audio-owner wake repair is missing: $fragment"
    }
}

$requiredDeferredPpuCensusFragments = @(
    's_defer_pc_census_until_audio_wake',
    's_explicit_pc_census',
    '"debug.rpcsx.thor.transformers_audio_wake_fix"',
    'const bool pc_census_armed = s_explicit_pc_census ||',
    'thor_transformers_audio_owner_wake_completed()',
    'if (s_pc_census && pc_census_armed)'
)

foreach ($fragment in $requiredDeferredPpuCensusFragments) {
    if (-not $perfMonitor.Contains($fragment)) {
        throw "The deferred Transformers PPU census is missing: $fragment"
    }
}

$requiredPcCensusFragments = @(
    '"debug.rpcsx.thor.spu_pc_census"',
    'static constexpr u32 max_samples = 64;',
	'const u32 sample = s_sample + 1;',
	'bool matched = false;',
    'std::memcmp(spu._ptr<u8>(0x3000), edge_signature.data(), edge_signature.size())',
	'matched = true;',
	'if (matched)',
	's_sample++;',
    'Thor EDGE PC sample=%u',
	'r3=0x%08x r4=0x%08x r5=0x%08x',
	'out=%u intr=%u in=%u state=0x%08x',
	'group=%u spursrun=%u blocks=%llu recover=%llu failures=%llu',
	'hash=0x%016llx interp=%u',
	'spu.state.load().toUnderlying()',
	'spu.group->run_state.load()',
	'thor::spu_pc_census_tick();',
	'arm_transformers_physx_spu_census',
	'Thor PHYSX PC sample=%u',
	'Thor PHYSX PC WAIT sample=%u',
	'spu_transformers_physx_pc_census_tick();'
)

foreach ($fragment in $requiredPcCensusFragments) {
    if (-not ($pcCensus.Contains($fragment) -or $perfMonitor.Contains($fragment))) {
        throw "The edgeZlib SPU PC census is missing: $fragment"
    }
}

$spuMapReadyGuard = 'g_fxo->try_get<id_manager::id_map<named_thread<spu_thread>>>()'
if ([regex]::Matches($pcCensus, [regex]::Escape($spuMapReadyGuard)).Count -lt 3) {
    throw "Each SPU PC census path must wait for the SPU ID map."
}

$requiredPhysxCensusArmFragments = @(
	'#include "Emu/Cell/thor_spu_pc_census.h"',
	'Emu.GetTitleID() == "BLUS30357" && elf.addr() == 0x018c1000u',
	'thor::arm_transformers_physx_spu_census(taskset.addr(), *taskId, elf.addr());'
)

foreach ($fragment in $requiredPhysxCensusArmFragments) {
	if (-not $cellSpurs.Contains($fragment)) {
		throw "The Transformers PhysX SPU census arm is missing: $fragment"
	}
}

if ($pcCensus.IndexOf('s_sample++') -lt $pcCensus.IndexOf('matched = true;')) {
    throw "The edgeZlib SPU PC census must not use its quota before a task matches."
}

$requiredEventCensusFragments = @(
    '"debug.rpcsx.thor.spu_event_census"',
	'(n % 4096) == 0',
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

if ($spuThread.Contains('(n % 64) == 0')) {
    throw "The SPURS atomic census reintroduced the high-rate 64-hit log interval."
}

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
    'maxContention = 3;'
)

$requiredEdgeEventWaitTraceFragments = @(
    'static bool thor_transformers_edge_event_wait_trace() noexcept',
    '"debug.rpcsx.thor.edge_event_wait_trace"',
    's_on && Emu.GetTitleID() == "BLUS30357"',
    'eventFlag.addr() == 0x01e54800u',
    'thor_edge_wait_index < 2048 && (thor_edge_wait_index & 0x7f) == 0',
    'Thor EDGE EFWAIT BUSY #%u',
    'Thor EDGE EFWAIT ERROR #%u',
    'Thor EDGE EFWAIT ARM #%u',
    'Thor EDGE EFWAIT WAKE #%u',
    'Thor EDGE EFWAIT RETURN #%u',
    'Thor EDGE EFWAIT MISMATCH #%u',
    'mode == CELL_SPURS_EVENT_FLAG_OR',
    'request=0x%04x',
    'slotEvents=0x%04x',
    'state{events=%04x wait=%04x slotmode=%02x pending=%u}'
)

foreach ($fragment in $requiredEdgeEventWaitTraceFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers EDGE event-wait trace is missing: $fragment"
    }
}

$requiredFmodEventWaitTraceFragments = @(
    'static bool thor_transformers_fmod_event_wait_trace() noexcept',
    '"debug.rpcsx.thor.fmod_event_wait_trace"',
	'static bool thor_transformers_fmod_event_interp() noexcept',
	'"debug.rpcsx.thor.fmod_event_interp"',
	'const bool thor_fmod_trace = thor_transformers_fmod_event_wait_trace();',
	'(thor_fmod_trace || thor_transformers_fmod_event_interp()) && block',
	'const bool thor_log_fmod_wait = thor_fmod_trace && thor_fmod_wait',
    'static_cast<u32>(ppu.lr) == 0x00e2bab4u',
    'Thor FMOD EFWAIT BUSY #%u',
    'Thor FMOD EFWAIT ARM #%u',
    'Thor FMOD EFWAIT ERROR #%u',
    'Thor FMOD EFWAIT WAKE #%u',
    'Thor FMOD EFWAIT MISMATCH #%u',
    'Thor FMOD EFWAIT RETURN #%u',
    'thor::fmod_event_wait_arm(',
    'thor::fmod_event_wait_wake(',
    'thor::fmod_event_wait_finish('
)

foreach ($fragment in $requiredFmodEventWaitTraceFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers FMOD event-wait trace is missing: $fragment"
    }
}

$requiredPhysxQueueWaitFragments = @(
    'static bool thor_transformers_physx_queue_wait() noexcept',
    '"debug.rpcsx.thor.transformers_physx_queue_wait"',
    'static_cast<u32>(ppu.lr) == 0x00a94678u',
    'first_task_elf == 0x018c1000u',
    'static constexpr u64 c_max_wait_us = 5''000''000;',
    'while (get_system_time() - started < c_max_wait_us)',
    'thread_ctrl::wait_for(c_poll_us, false);',
    'Thor Transformers PhysX queue startup wait:'
)

foreach ($fragment in $requiredPhysxQueueWaitFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers PhysX queue startup wait is missing: $fragment"
    }
}

$requiredPhysxStartInterpFragments = @(
    'static bool is_thor_transformers_physx_start_interp_dispatch(const spu_thread& spu) noexcept',
    '"debug.rpcsx.thor.transformers_physx_start_interp"',
    'const auto task = thor::get_transformers_physx_task_snapshot();',
    'task.elf != 0x018c1000u',
    'static_cast<u32>(+spu._ref<u64>(0x27b8)) != task.taskset',
    '+spu._ref<u32>(0x27d4) != task.task_id',
    'spu.interp_fallback_begin = 0x030a8;',
    'spu.interp_fallback_end = 0x06e54;',
    'Thor Transformers PhysX startup interpreter leave'
)

foreach ($fragment in $requiredPhysxStartInterpFragments) {
    if (-not $spuCommon.Contains($fragment)) {
        throw "The Transformers PhysX startup interpreter is missing: $fragment"
    }
}

$requiredPhysxDumpFragments = @(
    'const bool physx_task_dump = want == "@physx";',
    'const auto physx_task = get_transformers_physx_task_snapshot();',
    'physx_task.elf != 0x018c1000u',
    'static_cast<u32>(+spu._ref<u64>(0x27b8)) != physx_task.taskset',
    'physx_task_dump ? "Transformers_PhysX"'
)

foreach ($fragment in $requiredPhysxDumpFragments) {
    if (-not $lsDump.Contains($fragment)) {
        throw "The Transformers PhysX local-store dump is missing: $fragment"
    }
}

$requiredFmodCorrelationFragments = @(
    @($eventWaitProbe, 'inline fmod_event_wait_probe_state g_fmod_event_wait_probe;'),
    @($eventWaitProbe, 'inline u32 fmod_event_dispatch('),
    @($spuThread, 'Thor FMOD EFWAIT EVENT #%u'),
    @($spuThread, 'current_taskset == fmod_wait.taskset'),
    @($spuThread, 'spup == fmod_wait.event_port'),
    @($spuThread, 'const u32 queue_id = queue ? queue->id : 0;'),
    @($spuThread, 'expected_queue=0x%08x'),
    @($pcCensus, 'static_cast<u32>(+spu._ref<u64>(0x27b8))'),
    @($pcCensus, 'Thor FMOD PC sample=%u'),
    @($pcCensus, 'Thor FMOD EFWAIT CENSUS: sample=%u'),
    @($lsDump, 'const bool fmod_wait_dump = want == "@fmod";'),
    @($lsDump, 'fmod_wait_dump ? "FMOD"')
)

foreach ($requirement in $requiredFmodCorrelationFragments) {
    if (-not $requirement[0].Contains($requirement[1])) {
        throw "The Transformers FMOD correlation probe is missing: $($requirement[1])"
    }
}

foreach ($fragment in $requiredTransformersSpuReserveFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers SPU reserve is missing: $fragment"
    }
}

$requiredQueuePublishFragments = @(
    'static bool thor_queue_publish_order() noexcept',
    'return Emu.GetTitleID() == "BLUS30357";',
    'if (thor_queue_reserve_fix() || order_fix)',
    'std::memcpy(vm::base(queue->buffer.addr() + claimed * entry_size), buffer.get_ptr(), entry_size);',
    'op.tail = (seen_tail + 1) % spurs_ring_range(depth);',
    'published = order_fix;'
)

$requiredRenderQueueDiagnosticFragments = @(
    'queue->taskset.addr() == 0x10364100 && depth == 256 && entry_size == 16',
    's_render_pay.fetch_add(1, std::memory_order_relaxed)',
    'Thor %sPAYLOAD #%u: queue=0x%x taskset=0x%x',
    'render_queue && n < 128'
)

foreach ($fragment in $requiredQueuePublishFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers queue publish route is missing: $fragment"
    }
}

foreach ($fragment in $requiredRenderQueueDiagnosticFragments) {
    if (-not $cellSpurs.Contains($fragment)) {
        throw "The Transformers render queue diagnostic is missing: $fragment"
    }
}

if ($cellSpurs.Contains('const u32 guess_slot')) {
    throw "The queue publish route must not write a guessed slot before ownership."
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
    'Emu.SetPauseAfterStartup(true);',
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
    'const bool autostart = !std::exchange(m_prevent_autostart, false) &&',
    'atomic_t<bool> m_pause_after_startup = false;',
    'void SetPauseAfterStartup(bool pause_after_startup);',
    'void Emulator::SetPauseAfterStartup(bool pause_after_startup)',
    'm_pause_after_startup = pause_after_startup;',
    'const bool pause_after_startup = m_pause_after_startup.exchange(false);',
    'const bool autostart = !pause_after_startup && (!m_ar || !!g_cfg.misc.autostart);',
    '"Thor start-paused startup handoff is ready."'
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

$requiredFmodEventInterpFragments = @(
    '"debug.rpcsx.thor.fmod_event_interp"',
    'is_thor_fmod_event_interp_dispatch(spu)',
    'spu.pc != 0x14008',
    'thor::get_fmod_event_wait_snapshot()',
    'static_cast<u32>(+spu._ref<u64>(0x27b8)) != wait.taskset',
    'std::memcmp(spu._ptr<u8>(0x14008), s_fmod_event_signature.data()',
    'spu.interp_fallback_begin = 0x14008;',
    'spu.interp_fallback_end = 0x14050;',
    'Thor FMOD EVENT DISPATCH INTERPRETER enter #%u',
    'Thor FMOD EVENT DISPATCH INTERPRETER leave #%u'
)

foreach ($fragment in $requiredFmodEventInterpFragments) {
    if (-not $spuCommon.Contains($fragment)) {
        throw "The FMOD event interpreter handoff is missing: $fragment"
    }
}

Write-Output "Transformers HLE LFQueue route contract passed."
