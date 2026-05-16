package net.rpcsx

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

class ThorDebugLaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val gamePath = intent.getStringExtra("path")
            ?: intent.dataString
            ?: ""

        if (gamePath.isBlank()) {
            Log.e(TAG, "Missing debug boot path extra")
            finish()
            return
        }

        Log.i(TAG, "Debug boot requested for $gamePath")
        startActivity(
            Intent(this, MainActivity::class.java)
                .setAction("net.rpcsx.THOR_DEBUG_BOOT")
                .putExtra("path", gamePath)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    private companion object {
        const val TAG = "ThorDebugLaunch"
    }
}
