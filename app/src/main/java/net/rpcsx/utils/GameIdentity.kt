package net.rpcsx.utils

import net.rpcsx.Game

object GameIdentity {
    private val titleIdRegex = Regex("\\b[A-Z]{4}\\d{5}\\b")

    fun titleIdsFromText(text: String?): List<String> {
        if (text.isNullOrBlank()) {
            return emptyList()
        }

        return titleIdRegex.findAll(text.uppercase())
            .map { it.value }
            .distinct()
            .toList()
    }

    fun titleIdsForGame(game: Game): List<String> {
        val ids = linkedSetOf<String>()
        ids += titleIdsFromText(game.info.titleId.value)
        ids += titleIdsFromText(game.info.path)
        ids += titleIdsFromText(game.info.name.value)
        return ids.toList()
    }

    fun primaryTitleId(game: Game): String? = titleIdsForGame(game).firstOrNull()
}
