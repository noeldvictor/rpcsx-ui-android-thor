package net.rpcsx.utils

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import net.rpcsx.BuildConfig
import net.rpcsx.RPCSX

/**
 * Load a savestate into the RUNNING emulator, over adb.
 *
 * The save half already existed as ThorDebugSaveStateReceiver. The load half did
 * not, and load is the half a measurement needs: an A/B is only worth taking when
 * both arms restore the same frame.
 *
 * Load has to happen INTO a running session, not by booting a savestate file. A
 * savestate resolves its disc through games.yml, and this fork stores that as a
 * virtual path backed by a SAF content URI. That path only resolves while the disc
 * is mounted, so booting the savestate directly fails with
 *
 *     Disc directory not found. Savestate cannot be loaded. ('BLUS30161')
 *
 * which reads like a corrupt savestate and is not one. Boot the disc first, then
 * broadcast this.
 *
 * A broadcast, not an activity intent, for the same reason as the save receiver:
 * starting an activity would bring MainActivity forward and push the emulator out
 * of the foreground, changing the workload being measured.
 *
 * Debug builds only. THOR_DEBUG_TOOLS is false for release and this returns at
 * once there, so exporting the receiver does not widen the shipped app.
 *
 * Usage:
 *
 *     adb shell am broadcast -a net.rpcsx.THOR_DEBUG_LOADSTATE \
 *         -n net.rpcsx.easy/net.rpcsx.utils.ThorDebugLoadStateReceiver
 */
class ThorDebugLoadStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!BuildConfig.THOR_DEBUG_TOOLS) {
            return
        }

        if (intent?.action != ACTION) {
            return
        }

        val requestId = intent.getStringExtra("thorLoadStateRequestId")
            ?.takeIf { it.matches(Regex("^[A-Za-z0-9._-]{1,80}$")) }
            ?: "unknown"

        if (RPCSX.activeLibrary.value == null) {
            Log.e(TAG, "Thor debug loadstate rejected: request=$requestId reason=library-inactive")
            return
        }

        // ON the main thread, and NOT on a worker like the save receiver uses.
        //
        // loadState reaches boot_last_savestate(false), which runs
        // Emu.GracefulShutdown() and then Emu.BootGame(): a full teardown and reboot
        // of the VM. Those are wrapped in Emu.CallFromMainThread, but this port binds
        // that callback to run INLINE on the calling thread, at
        // android/src/rpcsx-android.cpp setupCallbacks. So the thread which calls in is
        // the thread which tears the VM down.
        //
        // MEASURED, AND THE THREAD IS NOT THE CAUSE. Both forms corrupt the heap:
        //
        //   worker thread : Scudo ERROR: invalid chunk state when deallocating ...
        //   main looper   : scudo::reportInvalidChunkState(...)  -- same crash
        //
        // So savestate RESTORE is broken in this fork on any thread, and the fault is
        // in the load path itself, not in how it is dispatched. The main looper is kept
        // because it is the thread the lifecycle code expects, not because it helps.
        //
        // RPCSXActivity drives the same call from a worker, through runNativeHotkey, so
        // the SELECT + right stick UP hotkey is broken too. This is a real user-facing
        // defect and it is UNFIXED.
        //
        // Consequence: there is no repeatable gameplay workload on this device. Capture
        // works, restore does not, so a heavy scene cannot be replayed across arms.
        Handler(Looper.getMainLooper()).post {
            val result = runCatching { RPCSX.instance.loadState() }
                .onFailure { Log.e(TAG, "Thor debug loadstate failed: request=$requestId", it) }
                .getOrDefault(false)
            Log.w(TAG, "Thor debug loadstate finished: request=$requestId result=$result")
        }
    }

    private companion object {
        const val TAG = "RPCSX-UI"
        const val ACTION = "net.rpcsx.THOR_DEBUG_LOADSTATE"
    }
}
