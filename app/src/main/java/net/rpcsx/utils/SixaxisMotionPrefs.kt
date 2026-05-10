package net.rpcsx.utils

import net.rpcsx.performance.ThorPerformanceProfile
import net.rpcsx.utils.GeneralSettings.boolean

object SixaxisMotionPrefs {
    private const val PREF_ENABLE_SIXAXIS_MOTION = "enable_sixaxis_motion"

    fun defaultEnabled(): Boolean = ThorPerformanceProfile.isThorTarget()

    fun isEnabled(): Boolean {
        return GeneralSettings[PREF_ENABLE_SIXAXIS_MOTION].boolean(defaultEnabled())
    }

    fun setEnabled(value: Boolean) {
        GeneralSettings.setValue(PREF_ENABLE_SIXAXIS_MOTION, value)
    }
}
