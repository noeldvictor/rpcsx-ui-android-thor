package net.rpcsx.utils

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlin.concurrent.thread
import net.rpcsx.BuildConfig
import net.rpcsx.RPCSX

/**
 * Triggers a savestate from adb, so a measurement can start from a fixed scene.
 *
 * Every power result this fork has produced has been invalidated by the same
 * thing: the workload will not hold still. Booting Eternal Sonata lands in its
 * opening cutscene, which advances on its own schedule, so two arms of an A/B
 * sample different content. Measured directly, three consecutive 60 s windows on
 * one unchanged build ranged over 4.3 W and 2.0 busy cores. Against that, a
 * probe with a 0.002 W noise floor is a sharp ruler held against a moving object.
 *
 * A savestate fixes it: boot it, and the emulator starts from the same frame with
 * the same threads doing the same work every time. What was missing was a way to
 * *create* one without a human holding the device, since the only trigger was the
 * Select+L1 hotkey path in RPCSXActivity.
 *
 * This is a broadcast rather than an activity intent on purpose. Starting an
 * activity would bring MainActivity to the front and push the running emulator
 * out of the foreground, changing the very workload being captured.
 *
 * Debug builds only. THOR_DEBUG_TOOLS is false for release, and this returns
 * immediately there, so the receiver being exported does not widen the shipped
 * app's surface. It is exported because `adb shell am broadcast` cannot reach a
 * receiver that is not.
 *
 * Usage:
 *
 *     adb shell am broadcast -a net.rpcsx.THOR_DEBUG_SAVESTATE \
 *         -n net.rpcsx.easy/net.rpcsx.utils.ThorDebugSaveStateReceiver
 *
 * The savestate lands in files/config/savestates/<TITLEID>/ and can then be
 * booted like any other game path.
 *
 * One prerequisite that is easy to miss and produces a misleading error. Loading
 * a savestate resolves its disc through games.yml, so the title must already be
 * registered there. Registration happens as a side effect of booting the disc
 * normally at least once. A savestate for an unregistered title fails with
 * "Disc directory not found. Savestate cannot be loaded", which reads like a
 * broken savestate rather than a missing games.yml entry.
 */
class ThorDebugSaveStateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!BuildConfig.THOR_DEBUG_TOOLS) {
            return
        }

        if (intent?.action != ACTION) {
            return
        }

        val requestId = intent.getStringExtra("thorSaveStateRequestId")
            ?.takeIf { it.matches(Regex("^[A-Za-z0-9._-]{1,80}$")) }
            ?: "unknown"

        if (RPCSX.activeLibrary.value == null) {
            Log.e(TAG, "Thor debug savestate rejected: request=$requestId reason=library-inactive")
            return
        }

        // Off the main thread, matching how RPCSXActivity drives the same call.
        // saveState() enters the emulator and can block while it quiesces the
        // guest, which would be an ANR on the broadcast thread.
        thread(name = "RPCSX-ThorDebugSaveState") {
            val result = runCatching { RPCSX.instance.saveState() }
                .onFailure { Log.e(TAG, "Thor debug savestate failed: request=$requestId", it) }
                .getOrDefault(false)
            Log.w(TAG, "Thor debug savestate finished: request=$requestId result=$result")
        }
    }

    private companion object {
        const val TAG = "RPCSX-UI"
        const val ACTION = "net.rpcsx.THOR_DEBUG_SAVESTATE"
    }
}
