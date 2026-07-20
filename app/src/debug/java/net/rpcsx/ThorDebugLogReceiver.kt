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

        val synced = RPCSX.instance.syncLogs()
        resultCode = if (synced) Activity.RESULT_OK else Activity.RESULT_CANCELED
        resultData = if (synced) RESULT_SYNCED else RESULT_FAILED
        Log.i("RPCSX-UI", "Thor debug log sync result=$synced")
    }

    companion object {
        const val ACTION = "net.rpcsx.THOR_DEBUG_SYNC_LOG"
        const val RESULT_SYNCED = "synced"
        const val RESULT_FAILED = "failed"
    }
}
