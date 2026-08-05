
package net.rpcsx.utils

import android.view.KeyEvent
import net.rpcsx.Digital1Flags
import net.rpcsx.Digital2Flags
import org.json.JSONObject

object InputBindingPrefs {
    
    val defaultBindings = mapOf(
        KeyEvent.KEYCODE_DPAD_UP to Pair(Digital1Flags.CELL_PAD_CTRL_UP.bit, 0),
        KeyEvent.KEYCODE_DPAD_DOWN to Pair(Digital1Flags.CELL_PAD_CTRL_DOWN.bit, 0),
        KeyEvent.KEYCODE_DPAD_LEFT to Pair(Digital1Flags.CELL_PAD_CTRL_LEFT.bit, 0),
        KeyEvent.KEYCODE_DPAD_RIGHT to Pair(Digital1Flags.CELL_PAD_CTRL_RIGHT.bit, 0),
        KeyEvent.KEYCODE_BUTTON_A to Pair(Digital2Flags.CELL_PAD_CTRL_CROSS.bit, 1),
        KeyEvent.KEYCODE_BUTTON_B to Pair(Digital2Flags.CELL_PAD_CTRL_CIRCLE.bit, 1),
        KeyEvent.KEYCODE_BUTTON_X to Pair(Digital2Flags.CELL_PAD_CTRL_SQUARE.bit, 1),
        KeyEvent.KEYCODE_BUTTON_Y to Pair(Digital2Flags.CELL_PAD_CTRL_TRIANGLE.bit, 1),
        KeyEvent.KEYCODE_BUTTON_L1 to Pair(Digital2Flags.CELL_PAD_CTRL_L1.bit, 1),
        KeyEvent.KEYCODE_BUTTON_R1 to Pair(Digital2Flags.CELL_PAD_CTRL_R1.bit, 1),
        KeyEvent.KEYCODE_BUTTON_L2 to Pair(Digital2Flags.CELL_PAD_CTRL_L2.bit, 1),
        KeyEvent.KEYCODE_BUTTON_R2 to Pair(Digital2Flags.CELL_PAD_CTRL_R2.bit, 1),
        KeyEvent.KEYCODE_BUTTON_START to Pair(Digital1Flags.CELL_PAD_CTRL_START.bit, 0),
        KeyEvent.KEYCODE_BUTTON_SELECT to Pair(Digital1Flags.CELL_PAD_CTRL_SELECT.bit, 0),
        KeyEvent.KEYCODE_BUTTON_THUMBL to Pair(Digital1Flags.CELL_PAD_CTRL_L3.bit, 0),
        KeyEvent.KEYCODE_BUTTON_THUMBR to Pair(Digital1Flags.CELL_PAD_CTRL_R3.bit, 0),
        666666 to Pair(Digital1Flags.CELL_PAD_CTRL_PS.bit, 0)
    )

    private const val GLOBAL_KEY = "input_bindings"

    private val TITLE_ID_RE = Regex("^[A-Z]{4}[0-9]{5}$")

    /**
     * Storage key for a title's own bindings, or the global key when [titleId]
     * is null or not a valid PS3 title id. Guarding the format keeps a stray
     * value from silently creating an orphan preference key.
     */
    private fun keyFor(titleId: String?): String {
        val id = titleId?.trim()?.uppercase()
        return if (id != null && TITLE_ID_RE.matches(id)) "${GLOBAL_KEY}_$id" else GLOBAL_KEY
    }

    private fun parse(jsonString: String): Map<Int, Pair<Int, Int>>? {
        return try {
            val json = JSONObject(jsonString)
            val map = mutableMapOf<Int, Pair<Int, Int>>()
            json.keys().forEach { key ->
                val parts = json.getString(key).split(",")
                val keyCode = key.toIntOrNull() ?: return@forEach
                if (parts.size == 2) {
                    map[keyCode] = Pair(parts[0].toIntOrNull() ?: 0, parts[1].toIntOrNull() ?: 0)
                }
            }
            if (map.isEmpty()) null else map
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Persist bindings. With a [titleId] this writes that game's own layout and
     * leaves the global one untouched; without one it writes the global layout
     * used by every game that has no override.
     */
    fun saveBindings(bindings: Map<Int, Pair<Int, Int>>, titleId: String? = null): Boolean {
        try {
            val json = JSONObject()
            bindings.forEach { (keyCode, value) ->
                json.put(keyCode.toString(), "${value.first},${value.second}")
            }

            GeneralSettings.setValue(keyFor(titleId), json.toString())
        } catch (_: Exception) {
            return false
        }
        return true
    }

    /**
     * Resolve bindings for a game: its own layout if it has one, otherwise the
     * global layout, otherwise the built-in defaults.
     */
    fun loadBindings(titleId: String? = null): Map<Int, Pair<Int, Int>> {
        if (titleId != null) {
            val perGame = GeneralSettings[keyFor(titleId)] as String?
            if (perGame != null) {
                parse(perGame)?.let { return it }
            }
        }

        val global = GeneralSettings[GLOBAL_KEY] as String? ?: return defaultBindings
        return parse(global) ?: defaultBindings
    }

    /** True when this game overrides the global layout. */
    fun hasPerGameBindings(titleId: String?): Boolean {
        if (titleId == null) return false
        val key = keyFor(titleId)
        if (key == GLOBAL_KEY) return false
        return (GeneralSettings[key] as String?) != null
    }

    /**
     * Drop a game's override so it follows the global layout again. Returns
     * false when there was nothing to remove.
     */
    fun clearPerGameBindings(titleId: String?): Boolean {
        if (!hasPerGameBindings(titleId)) return false
        return try {
            GeneralSettings.setValue(keyFor(titleId), null)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun rpcsxKeyCodeToString(keyCode: Int, digitalNumber: Int): String {
        val digital1 = Digital1Flags.values().find { keyCode == it.bit }?.name?.removePrefix("CELL_PAD_CTRL_")
        val digital2 = Digital2Flags.values().find { keyCode == it.bit }?.name?.removePrefix("CELL_PAD_CTRL_")
        if (digitalNumber == 1) return digital2 ?: "Unknown" else return digital1 ?: "Unknown"
    }
}
