package net.rpcsx

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ThorDebugLogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            return
        }

        val checkpoint = RPCSX.instance.syncLogs()
        val accepted = checkpoint > 0
        resultCode = if (accepted) Activity.RESULT_OK else Activity.RESULT_CANCELED
        resultData = if (accepted) "$RESULT_CHECKPOINT_PREFIX$checkpoint" else RESULT_FAILED
        Log.i("RPCSX-UI", "Thor debug log sync checkpoint=$checkpoint accepted=$accepted")
    }

    companion object {
        const val ACTION = "net.rpcsx.THOR_DEBUG_SYNC_LOG"
        const val RESULT_CHECKPOINT_PREFIX = "checkpoint:"
        const val RESULT_FAILED = "failed"
    }
}
