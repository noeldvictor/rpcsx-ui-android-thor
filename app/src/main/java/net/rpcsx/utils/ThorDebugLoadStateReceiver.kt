package net.rpcsx.utils

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import net.rpcsx.BuildConfig
import net.rpcsx.RPCSX
import kotlin.concurrent.thread

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

        // Off the main thread, matching the save receiver and RPCSXActivity.
        // loadState() enters the emulator and blocks while it restores.
        thread(name = "RPCSX-ThorDebugLoadState") {
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
