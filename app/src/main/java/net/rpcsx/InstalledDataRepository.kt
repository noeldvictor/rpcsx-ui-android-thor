package net.rpcsx

import android.util.Log
import java.io.File

/**
 * The per-title data the emulator keeps on its virtual hard disk, and a way to
 * see and remove it.
 *
 * WHY THIS EXISTS
 *
 * Deleting a game from the library removes `game.info.path` when that path is app
 * managed, plus `cache/cache/<titleId>`, which is the PPU and SPU compile cache.
 * Neither of those is `dev_hdd0/game/<TITLEID>`.
 *
 * For a game booted from an ISO those are DIFFERENT places. The ISO is the
 * library entry; the title still writes to the virtual hard disk while it runs.
 * Unreal Engine 3 games do this at first boot and it is not small: Transformers
 * (BLUS30357) copies its cooked assets into
 * `dev_hdd0/game/BLUS30357/USRDIR/UnrealEngine3/TransGame/CookedPS3/`. Delete the
 * ISO entry and all of that stays behind, with nothing in the app that can see
 * it, let alone remove it.
 *
 * WHAT IS IN HERE, AND WHY DELETING IS NOT ALWAYS SAFE
 *
 * `dev_hdd0/game/<TITLEID>/` holds more than a cache. Depending on the title it
 * can also carry installed game data the title expects to find again, and patch
 * or update files. It is NOT the save directory - saves live in
 * `dev_hdd0/home/<user>/savedata` - so removing this cannot destroy a save file.
 * It can still cost a long reinstall, so the caller is expected to confirm.
 */
object InstalledDataRepository {
    private const val TAG = "InstalledDataRepository"

    data class Entry(
        val titleId: String,
        val dir: File,
        val sizeBytes: Long,
        val fileCount: Int,
    ) {
        val sizeLabel: String
            get() = when {
                sizeBytes >= 1L shl 30 -> "%.2f GB".format(sizeBytes.toDouble() / (1L shl 30))
                sizeBytes >= 1L shl 20 -> "%.0f MB".format(sizeBytes.toDouble() / (1L shl 20))
                else -> "%d KB".format(sizeBytes / 1024)
            }
    }

    private fun gameRoot(): File? =
        RPCSX.rootDirectory.takeIf { it.isNotEmpty() }
            ?.let { File(it).resolve("config/dev_hdd0/game") }
            ?.takeIf { it.isDirectory }

    /**
     * Walk once, summing sizes and counting files.
     *
     * Deliberately not [File.walkTopDown] with a second pass for the count: these
     * trees run to tens of thousands of files after a UE3 install, and walking
     * twice on a phone's storage is slow enough to be felt in the UI.
     */
    private fun measure(dir: File): Pair<Long, Int> {
        var bytes = 0L
        var files = 0

        dir.walkTopDown().forEach {
            if (it.isFile) {
                bytes += it.length()
                files++
            }
        }

        return bytes to files
    }

    fun list(): List<Entry> {
        val root = gameRoot() ?: return emptyList()

        return (root.listFiles() ?: emptyArray())
            .filter { it.isDirectory }
            .map { dir ->
                val (bytes, files) = measure(dir)
                Entry(dir.name, dir, bytes, files)
            }
            .sortedByDescending { it.sizeBytes }
    }

    fun entryFor(titleId: String): Entry? {
        val dir = gameRoot()?.resolve(titleId)?.takeIf { it.isDirectory } ?: return null
        val (bytes, files) = measure(dir)
        return Entry(titleId, dir, bytes, files)
    }

    fun totalBytes(): Long = list().sumOf { it.sizeBytes }

    /**
     * Remove one title's installed data.
     *
     * Confirms the postcondition rather than trusting deleteRecursively()'s return
     * value: a partial delete on external storage reports true often enough that
     * this project has been caught by it before.
     */
    fun delete(titleId: String): Result<Unit> {
        val dir = gameRoot()?.resolve(titleId)
            ?: return Result.failure(IllegalStateException("no dev_hdd0/game directory"))

        if (!dir.isDirectory) {
            return Result.failure(IllegalStateException("no installed data for $titleId"))
        }

        // Refuse anything that is not directly under dev_hdd0/game. titleId reaches
        // this from a directory listing today, but a caller passing "../.." later
        // must not be able to delete outside the tree.
        val root = gameRoot()!!.canonicalFile
        if (dir.canonicalFile.parentFile != root) {
            return Result.failure(IllegalArgumentException("$titleId is not directly under dev_hdd0/game"))
        }

        return runCatching {
            dir.deleteRecursively()

            check(!dir.exists()) {
                "deleteRecursively() reported success but ${dir.name} still exists"
            }

            Log.i(TAG, "removed installed data for $titleId")
        }
    }
}
