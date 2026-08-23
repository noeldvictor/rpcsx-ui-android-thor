
package net.rpcsx

import android.app.Application
import android.content.Context

class RPCSXApplication : Application() {
    init {
        instance = this
    }

    companion object {
        lateinit var instance : RPCSXApplication
            private set

        val context : Context get() = instance.applicationContext
    }

    override fun onCreate() {
        super.onCreate()
        instance = this

        // Debug builds only, loopback only. It gives a tool direct control of
        // the emulated pad, which cannot be driven from outside the app.
        net.rpcsx.debug.ThorControlServer.startIfDebug()
    }
}
