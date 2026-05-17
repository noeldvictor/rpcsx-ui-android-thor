param(
    [ValidateSet("Quiet", "Normal", "Verbose", "ReducedLoop", "ReducedLoopEmit", "ReducedLoopEmitQuiet", "ReducedLoopEmitU4", "ReducedLoopEmitU4Quiet", "ReducedLoopEmitU4DynMfcQuiet", "ReducedLoopEmitU8", "ReducedLoopEmitU8Quiet", "SpursProbe", "SemaProfile", "SemaFast", "DmaProfile", "DmaVerify", "RsxAuditor", "RsxDmaHostFence", "RsxDepthFeedback", "RsxTextureBarrierSkipColor", "RsxTextureBarrierSkipDepth", "RsxTextureBarrierSkipAll", "FastBusyWaitLight", "FastBusyWait", "FastBusyWaitAggressive", "WaitProfiler", "WaitProfilerVerbose", "GetllarProbe", "GetllarShort", "GetllarTiny", "GetllarYield8", "GetllarNoRsxLock", "Status")]
    [string]$Mode = "Status"
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

function Set-DeviceProp {
    param(
        [string]$Name,
        [string]$Value
    )

    & $adb shell setprop $Name $Value | Out-Null
}

function Get-DeviceProp {
    param([string]$Name)

    $value = (& $adb shell getprop $Name).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = "<unset>"
    }

    "{0}={1}" -f $Name, $value
}

$ReducedLoopUnroll = "2"
$DynamicMfcFast = "0"

switch ($Mode) {
    "Quiet" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "0"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "S"
        Set-DeviceProp "log.tag.RPCSX-UI" "W"
        break
    }
    "Normal" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "Verbose" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "1"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "V"
        Set-DeviceProp "log.tag.RPCSX-UI" "V"
        break
    }
    "ReducedLoop" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "1"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "V"
        Set-DeviceProp "log.tag.RPCSX-UI" "V"
        break
    }
    "ReducedLoopEmit" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "ReducedLoopEmitQuiet" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "0"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "S"
        Set-DeviceProp "log.tag.RPCSX-UI" "W"
        break
    }
    "ReducedLoopEmitU4" {
        $ReducedLoopUnroll = "4"
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "ReducedLoopEmitU4Quiet" {
        $ReducedLoopUnroll = "4"
        Set-DeviceProp "debug.rpcsx.thor.logcat" "0"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "S"
        Set-DeviceProp "log.tag.RPCSX-UI" "W"
        break
    }
    "ReducedLoopEmitU4DynMfcQuiet" {
        $ReducedLoopUnroll = "4"
        $DynamicMfcFast = "1"
        Set-DeviceProp "debug.rpcsx.thor.logcat" "0"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "S"
        Set-DeviceProp "log.tag.RPCSX-UI" "W"
        break
    }
    "ReducedLoopEmitU8" {
        $ReducedLoopUnroll = "8"
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "ReducedLoopEmitU8Quiet" {
        $ReducedLoopUnroll = "8"
        Set-DeviceProp "debug.rpcsx.thor.logcat" "0"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "S"
        Set-DeviceProp "log.tag.RPCSX-UI" "W"
        break
    }
    "SpursProbe" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "1"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "1"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "SemaProfile" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "profile"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "SemaFast" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "fast"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "DmaProfile" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "profile"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "DmaVerify" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "verify"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxAuditor" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxDmaHostFence" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.rsx_dma_fence" "host"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxDepthFeedback" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback" "persist"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxTextureBarrierSkipColor" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback" "persist"
        Set-DeviceProp "debug.rpcsx.thor.rsx_texture_barrier" "color"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxTextureBarrierSkipDepth" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback" "persist"
        Set-DeviceProp "debug.rpcsx.thor.rsx_texture_barrier" "depth"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "RsxTextureBarrierSkipAll" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "0"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "60"
        Set-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback" "persist"
        Set-DeviceProp "debug.rpcsx.thor.rsx_texture_barrier" "all"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "FastBusyWaitLight" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "light"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "FastBusyWait" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "fast"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "FastBusyWaitAggressive" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "aggressive"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "WaitProfiler" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "250000"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "WaitProfilerVerbose" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "100000"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "GetllarProbe" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_getllar" "profile"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "GetllarShort" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_getllar" "short"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "GetllarTiny" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_getllar" "tiny"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "GetllarYield8" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_getllar" "yield8"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
    "GetllarNoRsxLock" {
        Set-DeviceProp "debug.rpcsx.thor.logcat" "1"
        Set-DeviceProp "debug.rpcsx.thor.syscall_stats" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect" "0"
        Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit" "1"
        Set-DeviceProp "debug.rpcsx.thor.spurs_probe" "0"
        Set-DeviceProp "debug.rpcsx.thor.es_sema_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_dma_superpath" "off"
        Set-DeviceProp "debug.rpcsx.thor.rsx_auditor" "0"
        Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
        Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
        Set-DeviceProp "debug.rpcsx.thor.es_getllar" "norsx"
        Set-DeviceProp "debug.rpcsx.thor.dump_prx" "0"
        Set-DeviceProp "log.tag.RPCS3" "I"
        Set-DeviceProp "log.tag.RPCSX-UI" "I"
        break
    }
}

if ($Mode -ne "Status" -and $Mode -ne "RsxDmaHostFence") {
    Set-DeviceProp "debug.rpcsx.thor.rsx_dma_fence" "off"
}

if ($Mode -ne "Status" -and $Mode -ne "RsxDepthFeedback" -and $Mode -notlike "RsxTextureBarrierSkip*") {
    Set-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback" "off"
}

if ($Mode -ne "Status" -and $Mode -notlike "RsxTextureBarrierSkip*") {
    Set-DeviceProp "debug.rpcsx.thor.rsx_texture_barrier" "off"
}

if ($Mode -ne "Status" -and $Mode -notlike "FastBusyWait*") {
    Set-DeviceProp "debug.rpcsx.thor.fast_busy_wait" "off"
}

if ($Mode -ne "Status" -and $Mode -notlike "WaitProfiler*") {
    Set-DeviceProp "debug.rpcsx.thor.wait_profiler" "off"
}

if ($Mode -ne "Status" -and $Mode -notlike "Getllar*") {
    Set-DeviceProp "debug.rpcsx.thor.es_getllar" "off"
}

if ($Mode -ne "Status") {
    Set-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_unroll" $ReducedLoopUnroll
    Set-DeviceProp "debug.rpcsx.thor.spu_dynamic_mfc_fast" $DynamicMfcFast
}

Get-DeviceProp "debug.rpcsx.thor.logcat"
Get-DeviceProp "debug.rpcsx.thor.syscall_stats"
Get-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_detect"
Get-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_emit"
Get-DeviceProp "debug.rpcsx.thor.spu_reduced_loop_unroll"
Get-DeviceProp "debug.rpcsx.thor.spu_dynamic_mfc_fast"
Get-DeviceProp "debug.rpcsx.thor.spurs_probe"
Get-DeviceProp "debug.rpcsx.thor.es_sema_superpath"
Get-DeviceProp "debug.rpcsx.thor.es_dma_superpath"
Get-DeviceProp "debug.rpcsx.thor.rsx_auditor"
Get-DeviceProp "debug.rpcsx.thor.rsx_dma_fence"
Get-DeviceProp "debug.rpcsx.thor.rsx_depth_feedback"
Get-DeviceProp "debug.rpcsx.thor.rsx_texture_barrier"
Get-DeviceProp "debug.rpcsx.thor.fast_busy_wait"
Get-DeviceProp "debug.rpcsx.thor.wait_profiler"
Get-DeviceProp "debug.rpcsx.thor.es_getllar"
Get-DeviceProp "debug.rpcsx.thor.dump_prx"
Get-DeviceProp "log.tag.RPCS3"
Get-DeviceProp "log.tag.RPCSX-UI"
