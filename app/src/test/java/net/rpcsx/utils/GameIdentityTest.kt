package net.rpcsx.utils

import org.junit.Assert.assertEquals
import org.junit.Test

class GameIdentityTest {
    @Test
    fun titleIdsNormalizeCommonSeparators() {
        assertEquals(
            listOf("BLUS31601", "BLES02241", "NPUB31848"),
            GameIdentity.titleIdsFromText("BLUS31601 / BLUS-31601 / BLES 02241 / NPUB_31848")
        )
    }
}
