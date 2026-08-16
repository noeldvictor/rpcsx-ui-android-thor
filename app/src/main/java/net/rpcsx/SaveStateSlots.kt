package net.rpcsx

import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Numbered savestate slots, built on top of the single savestate the core keeps.
 *
 * WHY THIS IS ALL FILE WORK, AND NOT A CORE CHANGE
 *
 * The core exposes saveState() and loadState() with no slot argument.
 * loadState() calls boot_last_savestate(), which scans the savestate directory
 * and picks the file with the greatest mtime whose NAME CONTAINS THE TITLE ID
 * (savestate_utils.cpp:355-381). It skips directories, and it never recurses.
 *
 * Two facts fall out of that, and this whole file rests on them:
 *
 *   1. To make the core load a chosen savestate, put the file in that directory
 *      with the title id in its name and the newest mtime. Nothing else selects.
 *   2. A subdirectory is invisible to the scan, so archived slots cannot be
 *      picked up by accident.
 *
 * Slots therefore live OUTSIDE the scanned directory, and restoring a slot is a
 * copy plus a touch. No native code changes, and nothing here can make the core
 * boot a savestate the user did not choose.
 *
 * WHAT THIS DOES NOT DO
 *
 * It does not make a savestate. saveState() does that, asynchronously: the core
 * kills and restarts the emulator to write one. Call archiveNewest() only after
 * the write has finished, or it archives the previous savestate.
 * awaitNewSavestate() exists for that.
 */
object SaveStateSlots {
    private const val TAG = "SaveStateSlots"

    /** Extensions boot_last_savestate() accepts, in the order it tries them. */
    private val SAVESTATE_EXTENSIONS = listOf(".zst", ".gz", "")

    const val SLOT_COUNT = 8

    data class Slot(
        val index: Int,
        val file: File,
        val savedAtMillis: Long,
        val sizeBytes: Long,
    ) {
        val label: String
            get() = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(Date(savedAtMillis))

        val sizeLabel: String
            get() = when {
                sizeBytes >= 1L shl 30 -> "%.1f GB".format(sizeBytes.toDouble() / (1L shl 30))
                sizeBytes >= 1L shl 20 -> "%.0f MB".format(sizeBytes.toDouble() / (1L shl 20))
                else -> "%d KB".format(sizeBytes / 1024)
            }
    }

    private fun root(): File? =
        RPCSX.rootDirectory.takeIf { it.isNotEmpty() }?.let { File(it) }

    /**
     * The directory the core writes savestates into, and the one
     * boot_last_savestate() scans.
     *
     * Both layouts are checked because the core builds this path itself and a
     * per-title subdirectory has been observed. A directory that does not exist
     * is dropped rather than created, so a wrong guess reads as "no savestate"
     * instead of creating an empty directory the core then scans.
     */
    private fun savestateDirs(titleId: String): List<File> {
        val base = root()?.resolve("config/savestates") ?: return emptyList()
        return listOf(base.resolve(titleId), base).filter { it.isDirectory }
    }

    /** Slots live outside the scanned directory. See the note at the top. */
    private fun slotsDir(titleId: String): File? =
        root()?.resolve("config/savestate-slots")?.resolve(titleId)

    /**
     * The savestate the core would load right now: newest mtime, title id in the
     * name. This mirrors boot_last_savestate()'s choice, minus the compatibility
     * check, which only the core can do.
     */
    fun newestSavestate(titleId: String): File? =
        savestateDirs(titleId)
            .flatMap { it.listFiles()?.asList() ?: emptyList() }
            .filter { it.isFile && it.name.contains(titleId) }
            .maxByOrNull { it.lastModified() }

    private fun slotFile(titleId: String, index: Int, extension: String): File? =
        slotsDir(titleId)?.resolve("slot%02d%s".format(index, extension))

    private fun findSlotFile(titleId: String, index: Int): File? {
        val dir = slotsDir(titleId) ?: return null
        return SAVESTATE_EXTENSIONS
            .map { dir.resolve("slot%02d%s".format(index, it)) }
            .firstOrNull { it.isFile }
    }

    fun listSlots(titleId: String): List<Slot> =
        (0 until SLOT_COUNT).mapNotNull { index ->
            findSlotFile(titleId, index)?.let {
                Slot(index, it, it.lastModified(), it.length())
            }
        }

    fun slot(titleId: String, index: Int): Slot? =
        findSlotFile(titleId, index)?.let { Slot(index, it, it.lastModified(), it.length()) }

    /**
     * Wait for the core to finish writing a new savestate.
     *
     * saveState() returns as soon as the request is accepted, not when the file
     * exists. Poll for a file newer than [since], because archiving too early
     * copies the PREVIOUS savestate and reports success, which is worse than
     * failing.
     */
    fun awaitNewSavestate(
        titleId: String,
        since: Long,
        timeoutMillis: Long = 60_000,
        pollMillis: Long = 500,
    ): File? {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            val newest = newestSavestate(titleId)
            // Require the file to have settled, so a partly written savestate is
            // not archived. Two equal sizes across one poll is the cheap test.
            if (newest != null && newest.lastModified() > since) {
                val firstSize = newest.length()
                Thread.sleep(pollMillis)
                if (newest.length() == firstSize && firstSize > 0) {
                    return newest
                }
            } else {
                Thread.sleep(pollMillis)
            }
        }
        Log.w(TAG, "no new savestate for $titleId within ${timeoutMillis}ms")
        return null
    }

    /** Copy the current savestate into [index]. Replaces whatever was there. */
    fun archiveNewest(titleId: String, index: Int): Result<Slot> {
        require(index in 0 until SLOT_COUNT) { "slot $index out of range" }

        val source = newestSavestate(titleId)
            ?: return Result.failure(IllegalStateException("no savestate to archive"))
        val dir = slotsDir(titleId)
            ?: return Result.failure(IllegalStateException("no root directory"))

        return runCatching {
            dir.mkdirs()
            // Drop any previous file for this slot first, so a slot cannot end up
            // holding two files with different extensions.
            SAVESTATE_EXTENSIONS.forEach { dir.resolve("slot%02d%s".format(index, it)).delete() }

            val extension = SAVESTATE_EXTENSIONS.first { source.name.endsWith(it) }
            val target = slotFile(titleId, index, extension)!!
            source.copyTo(target, overwrite = true)

            // Confirm the postcondition rather than the copy's return value.
            check(target.isFile && target.length() == source.length()) {
                "slot $index copy is short: ${target.length()} of ${source.length()}"
            }
            Log.i(TAG, "archived $titleId savestate to slot $index (${target.length()} bytes)")
            Slot(index, target, target.lastModified(), target.length())
        }
    }

    /**
     * Make slot [index] the savestate the core will load.
     *
     * Copies it back into the scanned directory under a name that carries the
     * title id, then stamps it as the newest file there. loadState() picks it up
     * with no further argument.
     */
    fun restoreSlot(titleId: String, index: Int): Result<File> {
        val slotSource = findSlotFile(titleId, index)
            ?: return Result.failure(IllegalStateException("slot $index is empty"))
        val destinationDir = savestateDirs(titleId).firstOrNull()
            ?: return Result.failure(IllegalStateException("no savestate directory for $titleId"))

        return runCatching {
            val extension = SAVESTATE_EXTENSIONS.first { slotSource.name.endsWith(it) }
            // The name must contain the title id or the core's scan skips it.
            val target = destinationDir.resolve("$titleId-slot%02d%s".format(index, extension))
            slotSource.copyTo(target, overwrite = true)

            // mtime is the ONLY thing that decides which savestate loads, so make
            // this one newest. setLastModified can fail silently on some volumes;
            // verify instead of trusting it.
            val now = System.currentTimeMillis()
            target.setLastModified(now)
            val newest = newestSavestate(titleId)
            check(newest?.canonicalPath == target.canonicalPath) {
                "slot $index is not the newest savestate after restore; " +
                    "newest is ${newest?.name}. The next load would pick that instead."
            }
            Log.i(TAG, "restored $titleId slot $index as ${target.name}")
            target
        }
    }

    /**
     * The slot an automatic archive should use: the first empty one, or the
     * oldest if all are full.
     *
     * Derived from the files themselves, so there is no counter to persist and
     * nothing to fall out of step with what is on disk.
     */
    fun nextArchiveSlot(titleId: String): Int {
        val used = listSlots(titleId)
        val firstEmpty = (0 until SLOT_COUNT).firstOrNull { index ->
            used.none { it.index == index }
        }
        return firstEmpty ?: used.minByOrNull { it.savedAtMillis }?.index ?: 0
    }

    fun deleteSlot(titleId: String, index: Int): Boolean {
        val file = findSlotFile(titleId, index) ?: return false
        val deleted = file.delete()
        // Confirm by re-checking, not by the return value.
        return deleted && findSlotFile(titleId, index) == null
    }
}
