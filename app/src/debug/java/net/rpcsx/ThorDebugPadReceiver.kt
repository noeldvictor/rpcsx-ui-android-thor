package net.rpcsx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class ThorDebugPadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) {
            return
        }

        val ok = RPCSXActivity.thorDebugPad(
            digital1 = intent.getIntExtra("digital1", 0),
            digital2 = intent.getIntExtra("digital2", 0),
            leftStickX = intent.getIntExtra("leftStickX", -1),
            leftStickY = intent.getIntExtra("leftStickY", -1),
            rightStickX = intent.getIntExtra("rightStickX", -1),
            rightStickY = intent.getIntExtra("rightStickY", -1),
            durationMs = intent.getLongExtra("durationMs", 80L)
        )

        Log.i("RPCSX-UI", "Thor debug pad broadcast result=$ok")
    }

    companion object {
        const val ACTION = "net.rpcsx.THOR_DEBUG_PAD"
    }
}
