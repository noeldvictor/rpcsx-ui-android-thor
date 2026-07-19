package net.rpcsx.performance

import java.util.Locale

object ThorDisplayPacing {
    internal const val ETERNAL_SONATA_TITLE_ID = "BLUS30161"
    internal const val ETERNAL_SONATA_FRAME_RATE = 30f
    private val identitySeparators = Regex("[\\s_-]")

    fun targetFrameRate(
        isThorTarget: Boolean,
        titleId: String?,
        gamePath: String,
        enabled: Boolean = true
    ): Float {
        if (!enabled || !isThorTarget) {
            return 0f
        }

        val identity = "${titleId.orEmpty()} $gamePath"
            .uppercase(Locale.US)
            .replace(identitySeparators, "")
        return if (ETERNAL_SONATA_TITLE_ID in identity) {
            ETERNAL_SONATA_FRAME_RATE
        } else {
            0f
        }
    }
}
