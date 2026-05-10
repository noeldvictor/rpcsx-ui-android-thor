package net.rpcsx.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileUtilTest {
    @Test
    fun nativeInstallerSafeFileNamesAreConservative() {
        assertTrue(FileUtil.isNativeInstallerSafeFileName("game.pkg"))
        assertTrue(FileUtil.isNativeInstallerSafeFileName("LICENSE.EDAT"))
        assertFalse(FileUtil.isNativeInstallerSafeFileName("disc.iso"))
        assertFalse(FileUtil.isNativeInstallerSafeFileName("PS3_GAME"))
        assertFalse(FileUtil.isNativeInstallerSafeFileName("readme.txt"))
    }

    @Test
    fun isoFileNamesAreDetectedForFolderLibraries() {
        assertTrue(FileUtil.isIsoFileName("Demon's Souls.iso"))
        assertTrue(FileUtil.isIsoFileName("ODIN.ISO"))
        assertFalse(FileUtil.isIsoFileName("game.pkg"))
        assertFalse(FileUtil.isIsoFileName("PS3_GAME"))
    }

    @Test
    fun externalStorageDocumentIdsMapToFilesystemPaths() {
        assertEquals(
            "/storage/ABCD-1234/roms/ps3/Game.iso",
            FileUtil.externalStorageDocumentIdToFilePath("ABCD-1234:roms/ps3/Game.iso")
        )
        assertEquals(
            "/storage/emulated/0/roms/ps3",
            FileUtil.externalStorageDocumentIdToFilePath("primary:roms/ps3")
        )
    }

    @Test
    fun externalStoragePathsMapToDocumentIds() {
        assertEquals(
            "ABCD-1234:roms/ps3/Game.iso",
            FileUtil.externalStoragePathToDocumentId("/storage/ABCD-1234/roms/ps3/Game.iso")
        )
        assertEquals(
            "primary:roms/ps3",
            FileUtil.externalStoragePathToDocumentId("/storage/emulated/0/roms/ps3")
        )
    }
}
