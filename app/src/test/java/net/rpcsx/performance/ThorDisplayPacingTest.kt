package net.rpcsx.performance

import org.junit.Assert.assertEquals
import org.junit.Test

class ThorDisplayPacingTest {
    @Test
    fun eternalSonataOnThorRequestsThirtyFps() {
        assertEquals(
            30f,
            ThorDisplayPacing.targetFrameRate(
                isThorTarget = true,
                titleId = "BLUS30161",
                gamePath = "/games/Eternal Sonata"
            )
        )
    }

    @Test
    fun debugBootCanIdentifyEternalSonataFromPath() {
        assertEquals(
            30f,
            ThorDisplayPacing.targetFrameRate(
                isThorTarget = true,
                titleId = null,
                gamePath = "/storage/emulated/0/PS3/BLUS-30161"
            )
        )
    }

    @Test
    fun otherGamesAndDevicesKeepSystemDefault() {
        assertEquals(
            0f,
            ThorDisplayPacing.targetFrameRate(
                isThorTarget = true,
                titleId = "BLUS99999",
                gamePath = "/games/Other"
            )
        )
        assertEquals(
            0f,
            ThorDisplayPacing.targetFrameRate(
                isThorTarget = false,
                titleId = "BLUS30161",
                gamePath = "/games/Eternal Sonata"
            )
        )
        assertEquals(
            0f,
            ThorDisplayPacing.targetFrameRate(
                isThorTarget = true,
                titleId = "BLUS30161",
                gamePath = "/games/Eternal Sonata",
                enabled = false
            )
        )
    }
}
