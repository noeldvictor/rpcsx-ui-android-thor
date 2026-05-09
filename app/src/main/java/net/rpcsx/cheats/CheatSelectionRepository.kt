package net.rpcsx.cheats

import android.content.Context
import androidx.core.content.edit

object CheatSelectionRepository {
    private const val PREFS = "cheat_selections"

    fun isEnabled(context: Context, gameKey: String, entry: CheatEntry): Boolean {
        return prefs(context).getBoolean(key(gameKey, entry), false)
    }

    fun setEnabled(context: Context, gameKey: String, entry: CheatEntry, enabled: Boolean) {
        prefs(context).edit {
            putBoolean(key(gameKey, entry), enabled)
        }
    }

    fun enabledCount(context: Context, gameKey: String, entries: List<CheatEntry>): Int {
        return entries.count { isEnabled(context, gameKey, it) }
    }

    fun enabledEntries(context: Context, gameKey: String, entries: List<CheatEntry>): List<CheatEntry> {
        return entries.filter { isEnabled(context, gameKey, it) }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(gameKey: String, entry: CheatEntry): String =
        "${gameKey}:${entry.fileName}"
}
