package net.rpcsx.performance

import android.os.Build
import android.os.Process
import android.util.Log
import net.rpcsx.RPCSX
import net.rpcsx.utils.GeneralSettings

object ThorPerformanceProfile {
    private const val TAG = "ThorPerformanceProfile"
    private const val PROFILE_VERSION = 12
    private const val PROFILE_PREF = "thor_compile_profile_version"
    private const val PERFORMANCE_CORE_MASK = 0xF8

    data class ApplyResult(
        val applied: Boolean,
        val affinityApplied: Boolean,
        val changedSettings: List<String>,
        val failedSettings: List<String>
    )

    fun isThorTarget(): Boolean {
        val deviceText = listOf(
            Build.MODEL,
            Build.DEVICE,
            Build.BOARD,
            Build.HARDWARE,
            Build.PRODUCT,
            Build.MANUFACTURER
        ).joinToString(" ").lowercase()

        return "ayn" in deviceText || "thor" in deviceText || "kalama" in deviceText
    }

    fun applyStartupDefaults(force: Boolean = false): ApplyResult {
        if (!isThorTarget()) {
            return ApplyResult(
                applied = false,
                affinityApplied = false,
                changedSettings = emptyList(),
                failedSettings = emptyList()
            )
        }

        val affinityApplied = applyRuntimeAffinity()
        val alreadyApplied = (GeneralSettings[PROFILE_PREF] as? Int ?: 0) >= PROFILE_VERSION
        if (alreadyApplied && !force) {
            return ApplyResult(
                applied = false,
                affinityApplied = affinityApplied,
                changedSettings = emptyList(),
                failedSettings = emptyList()
            )
        }

        val changed = mutableListOf<String>()
        val failed = mutableListOf<String>()

        setSetting("Core@@Max LLVM Compile Threads", "2", "Max LLVM Compile Threads", changed, failed)
        setSetting("Core@@LLVM Precompilation", "false", "LLVM Precompilation", changed, failed)
        setSetting("Core@@SPU Cache", "true", "SPU Cache", changed, failed)
        setSetting("Core@@SPU Decoder", "\"Recompiler (LLVM)\"", "SPU Decoder", changed, failed)
        setSetting("Core@@Max SPURS Threads", "6", "Max SPURS Threads", changed, failed)
        setSetting("Core@@SPU Reservation Busy Waiting Enabled", "false", "SPU Reservation Busy Waiting", changed, failed)
        setSetting("Core@@SPU Reservation Busy Waiting Percentage", "0", "SPU Reservation Busy Waiting Percentage", changed, failed)
        setSetting("Core@@Accurate SPU Reservations", "true", "Accurate SPU Reservations", changed, failed)
        setSetting("Core@@SPU Verification", "true", "SPU Verification", changed, failed)
        setSetting("Core@@Use LLVM CPU", "\"cortex-a78\"", "Use LLVM CPU", changed, failed)
        setSetting("Video@@Accurate ZCULL stats", "true", "Accurate ZCULL stats", changed, failed)
        setSetting("Video@@Relaxed ZCULL Sync", "false", "Relaxed ZCULL Sync", changed, failed)
        setSetting("Video@@Multithreaded RSX", "false", "Multithreaded RSX", changed, failed)
        setSetting("Video@@Disable On-Disk Shader Cache", "false", "On-Disk Shader Cache", changed, failed)
        setSetting("Video@@Shader Compiler Threads", "2", "Shader Compiler Threads", changed, failed)
        setSetting("Video@@Vulkan@@VRAM allocation limit (MB)", "3072", "Vulkan VRAM Allocation Limit", changed, failed)
        setSetting("Video@@Performance Overlay@@Enabled", "true", "Performance Overlay", changed, failed)
        if (affinityApplied) {
            setThorSchedulerDefaults(changed, failed)
        }

        if (failed.isEmpty()) {
            GeneralSettings[PROFILE_PREF] = PROFILE_VERSION
            GeneralSettings.sync()
        }

        Log.i(
            TAG,
            "Thor compile profile applied=${failed.isEmpty()} affinity=$affinityApplied changed=$changed failed=$failed"
        )

        return ApplyResult(
            applied = failed.isEmpty(),
            affinityApplied = affinityApplied,
            changedSettings = changed,
            failedSettings = failed
        )
    }

    fun forceApplyCompileDefaults(): ApplyResult = applyStartupDefaults(force = true)

    private fun setSetting(
        path: String,
        value: String,
        label: String,
        changed: MutableList<String>,
        failed: MutableList<String>
    ) {
        val ok = runCatching {
            RPCSX.instance.settingsSet(path, value)
        }.getOrElse {
            Log.w(TAG, "Failed to set $path", it)
            false
        }

        if (ok) {
            changed += label
        } else {
            failed += label
        }
    }

    private fun setThorSchedulerDefaults(
        changed: MutableList<String>,
        failed: MutableList<String>
    ) {
        setSetting("Core@@Thread Scheduler Mode", "\"Operating System\"", "Thread Scheduler Mode", changed, failed)
        setSetting("Core@@Affinity@@CPU0", "\"General\"", "Affinity CPU0", changed, failed)
        setSetting("Core@@Affinity@@CPU1", "\"General\"", "Affinity CPU1", changed, failed)
        setSetting("Core@@Affinity@@CPU2", "\"General\"", "Affinity CPU2", changed, failed)
        setSetting("Core@@Affinity@@CPU3", "\"General\"", "Affinity CPU3", changed, failed)
        setSetting("Core@@Affinity@@CPU4", "\"PPU\"", "Affinity CPU4", changed, failed)
        setSetting("Core@@Affinity@@CPU5", "\"SPU\"", "Affinity CPU5", changed, failed)
        setSetting("Core@@Affinity@@CPU6", "\"SPU\"", "Affinity CPU6", changed, failed)
        setSetting("Core@@Affinity@@CPU7", "\"RSX\"", "Affinity CPU7", changed, failed)
    }

    fun applyRuntimeAffinity(): Boolean {
        if (!isThorTarget()) {
            return false
        }

        val result = runCatching {
            RPCSX.instance.setProcessAffinityMask(PERFORMANCE_CORE_MASK)
        }.getOrElse {
            Log.w(TAG, "Could not set Thor performance-core affinity", it)
            false
        }

        runCatching {
            Process.setThreadPriority(Process.THREAD_PRIORITY_MORE_FAVORABLE)
        }.onFailure {
            Log.w(TAG, "Could not raise thread priority", it)
        }

        return result
    }
}
