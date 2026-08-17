package net.rpcsx

import android.content.Context
import android.util.Log
import net.rpcsx.utils.FileUtil

/**
 * Re-import every game folder the user has already granted access to.
 *
 * WHY THIS IS POSSIBLE WITHOUT STORING ANYTHING
 *
 * The folder picker already calls takePersistableUriPermission on whatever the
 * user chose (AppNavHost), so Android keeps those grants across restarts and
 * hands them back through contentResolver.persistedUriPermissions. The app never
 * looked at them for this purpose - there is a standing
 * `// TODO: FileUtil.saveGameFolderUri` next to the picker - but the list is
 * already there and is the authoritative record of "folders this app may read".
 *
 * WHY IT WAS NEEDED
 *
 * GameRepository.refresh() re-collects exactly two fixed paths,
 * `config/dev_hdd0/game` and `config/games`. It never re-walks a folder the user
 * imported, so a game added to that folder afterwards is invisible until the
 * folder is imported again by hand. There was no menu action to do it.
 *
 * WHY RE-IMPORTING IS SAFE TO REPEAT
 *
 * FileUtil.installPackages skips any folder whose target is already known
 * (`if (GameRepository.find(it.targetPath) != null) return@forEach`), so a rescan
 * adds new titles and leaves existing ones alone. It does not duplicate entries
 * and it does not re-copy data that is already installed.
 */
object GameFolderRescan {
    private const val TAG = "GameFolderRescan"

    /** Folders Android still lets us read, newest grant first. */
    fun grantedFolderCount(context: Context): Int =
        context.contentResolver.persistedUriPermissions.count { it.isReadPermission }

    /**
     * Re-walk every granted folder. Returns how many were submitted.
     *
     * installPackages() does its own work on a background thread and reports
     * through ProgressRepository, so this returns as soon as the walks are
     * started rather than when they finish.
     */
    fun rescanAll(context: Context): Int {
        val uris = context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { it.uri }

        if (uris.isEmpty()) {
            Log.i(TAG, "no persisted folder grants; nothing to rescan")
            return 0
        }

        uris.forEach { uri ->
            Log.i(TAG, "rescanning $uri")
            runCatching { FileUtil.installPackages(context, uri) }
                .onFailure { Log.w(TAG, "rescan failed for $uri", it) }
        }

        // Pick up anything the walk registered into the two internal roots.
        GameRepository.queueRefresh()
        return uris.size
    }
}
