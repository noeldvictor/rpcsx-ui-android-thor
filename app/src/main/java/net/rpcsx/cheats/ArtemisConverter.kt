package net.rpcsx.cheats

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import net.rpcsx.Game
import net.rpcsx.RPCSX
import net.rpcsx.utils.GameIdentity
import java.io.File
import java.util.Locale

data class ArtemisWrite(
    val address: String,
    val value: String,
    val patchType: String = "be32"
)

data class ArtemisAobPatch(
    val searchPattern: String,
    val replacePattern: String
)

data class ArtemisCheat(
    val name: String,
    val author: String,
    val writes: List<ArtemisWrite>,
    val aobPatches: List<ArtemisAobPatch>,
    val unsupportedReasons: List<String>
) {
    val isSupported: Boolean
        get() = writes.isNotEmpty() && unsupportedReasons.isEmpty()
}

data class ArtemisInstallResult(
    val titleId: String?,
    val patchHash: String?,
    val installedCheats: Int,
    val skippedCheats: Int,
    val installedWrites: Int,
    val patchFilePath: String?,
    val configFilePath: String?,
    val backupPaths: List<String>,
    val missingHash: Boolean,
    val message: String
)

data class ArtemisPatchPreview(
    val patchBody: String,
    val configBody: String,
    val installedCheats: Int,
    val skippedCheats: Int,
    val installedWrites: Int
)

object ArtemisConverter {
    private const val PATCH_VERSION = "1.2"
    private const val APP_VERSION = "All"
    private const val PATCH_SECTION_START = "# RPCSX Easy Artemis patches start"
    private const val PATCH_SECTION_END = "# RPCSX Easy Artemis patches end"
    private const val CONFIG_SECTION_START = "# RPCSX Easy Artemis patch config start"
    private const val CONFIG_SECTION_END = "# RPCSX Easy Artemis patch config end"

    private const val MAX_STATIC_OPS_PER_CHEAT = 4096

    private val fixedWriteRegex = Regex("^0\\s+([0-9A-Fa-f]{8})\\s+([0-9A-Fa-f]+)(?:\\s+.*)?$")
    private val serialWriteRegex = Regex("^4\\s+([0-9A-Fa-f]{8})\\s+([0-9A-Fa-f]+)(?:\\s+.*)?$")
    private val aobReplaceRegex = Regex("^B\\s+([0-9A-Fa-f]{16,})\\s+([0-9A-Fa-f]{16,})(?:\\s+.*)?$", RegexOption.IGNORE_CASE)
    private val codeTokenRegex = Regex("^[0-9A-Fa-f]{1,2}$")
    private val whitespaceRegex = Regex("\\s+")

    fun parse(text: String): List<ArtemisCheat> {
        return text
            .replace("\r\n", "\n")
            .replace('\r', '\n')
            .split("\n#")
            .mapNotNull { parseBlock(it) }
    }

    suspend fun installEntries(
        context: Context,
        game: Game,
        entries: List<CheatEntry>
    ): ArtemisInstallResult = withContext(Dispatchers.IO) {
        val readyEntries = entries.filter { it.format == CheatRepository.FORMAT_RPCS3_PATCH }
        val artemisEntries = entries.filter { it.format != CheatRepository.FORMAT_RPCS3_PATCH }
        val titleId = GameIdentity.primaryTitleId(game)
            ?: entries.flatMap { it.titleIds }.firstOrNull()

        if (titleId == null) {
            return@withContext ArtemisInstallResult(
                titleId = null,
                patchHash = null,
                installedCheats = 0,
                skippedCheats = 0,
                installedWrites = 0,
                patchFilePath = null,
                configFilePath = null,
                backupPaths = emptyList(),
                missingHash = false,
                message = "No title ID was detected for this game, so RPCSX Easy cannot create a title patch yet."
            )
        }

        val root = rpcsxRoot(context)
        val patchesDir = File(root, "config/patches").apply { mkdirs() }
        val patchFile = File(patchesDir, "${titleId}_patch.yml")
        val configFile = File(root, "config/patch_config.yml")
        val backups = mutableListOf<String>()

        if (entries.isEmpty()) {
            backups += writeGeneratedSection(
                file = patchFile,
                startMarker = PATCH_SECTION_START,
                endMarker = PATCH_SECTION_END,
                body = "",
                prefixIfCreated = "Version: $PATCH_VERSION\n\n"
            )
            backups += writeGeneratedSection(
                file = configFile,
                startMarker = CONFIG_SECTION_START,
                endMarker = CONFIG_SECTION_END,
                body = "",
                prefixIfCreated = ""
            )

            return@withContext ArtemisInstallResult(
                titleId = titleId,
                patchHash = null,
                installedCheats = 0,
                skippedCheats = 0,
                installedWrites = 0,
                patchFilePath = patchFile.absolutePath,
                configFilePath = configFile.absolutePath,
                backupPaths = backups,
                missingHash = false,
                message = "Cleared generated Artemis patch selections for $titleId."
            )
        }

        val readyPreview = buildReadyPatchPreview(readyEntries)
        val ppuHash = if (artemisEntries.isNotEmpty()) {
            PatchHashRepository.requirePpuHash(context, game, titleId)
        } else {
            null
        }
        if (artemisEntries.isNotEmpty() && ppuHash == null && readyPreview.installedCheats == 0) {
            return@withContext ArtemisInstallResult(
                titleId = titleId,
                patchHash = null,
                installedCheats = 0,
                skippedCheats = 0,
                installedWrites = 0,
                patchFilePath = patchFile.absolutePath,
                configFilePath = configFile.absolutePath,
                backupPaths = emptyList(),
                missingHash = true,
                message = "Boot $titleId once, close it, then install again. RPCSX Easy needs the PPU patch hash from RPCSX.log."
            )
        }

        val gameTitle = game.info.name.value
            ?: entries.firstOrNull()?.title
            ?: titleId
        val artemisPreview = if (artemisEntries.isNotEmpty() && ppuHash != null) {
            val entryTexts = artemisEntries.map { entry -> entry to CheatRepository.getCheatText(context, entry) }
            buildPatchPreview(
                entries = entryTexts,
                titleId = titleId,
                ppuHash = ppuHash,
                gameTitle = gameTitle
            )
        } else {
            ArtemisPatchPreview("", "", 0, artemisEntries.size, 0)
        }

        val patchBody = listOf(readyPreview.patchBody, artemisPreview.patchBody)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")
        val configBody = listOf(readyPreview.configBody, artemisPreview.configBody)
            .filter { it.isNotBlank() }
            .joinToString("\n\n")

        backups += writeGeneratedSection(
            file = patchFile,
            startMarker = PATCH_SECTION_START,
            endMarker = PATCH_SECTION_END,
            body = patchBody,
            prefixIfCreated = "Version: $PATCH_VERSION\n\n"
        )
        backups += writeGeneratedSection(
            file = configFile,
            startMarker = CONFIG_SECTION_START,
            endMarker = CONFIG_SECTION_END,
            body = configBody,
            prefixIfCreated = ""
        )

        val installedCheats = readyPreview.installedCheats + artemisPreview.installedCheats
        val skippedCheats = readyPreview.skippedCheats + artemisPreview.skippedCheats
        val installedWrites = readyPreview.installedWrites + artemisPreview.installedWrites
        val message = if (installedCheats == 0) {
            "No static Artemis cheats were installable for $titleId. Risky AoB/configurable/runtime codes were skipped."
        } else if (artemisEntries.isNotEmpty() && ppuHash == null) {
            "Installed ${readyPreview.installedCheats} RPCS3-ready cheats for next boot. Boot $titleId once to learn the PPU hash before converting ${artemisEntries.size} Artemis entries."
        } else {
            "Installed $installedCheats cheats ($installedWrites static patch ops) for next boot. Skipped $skippedCheats risky or runtime-only cheats."
        }

        ArtemisInstallResult(
            titleId = titleId,
            patchHash = ppuHash ?: readyEntries.firstOrNull()?.patchHash,
            installedCheats = installedCheats,
            skippedCheats = skippedCheats,
            installedWrites = installedWrites,
            patchFilePath = patchFile.absolutePath,
            configFilePath = configFile.absolutePath,
            backupPaths = backups,
            missingHash = artemisEntries.isNotEmpty() && ppuHash == null,
            message = message
        )
    }

    fun summarize(text: String): Pair<Int, Int> {
        val cheats = parse(text)
        return cheats.count { it.isSupported } to cheats.count { !it.isSupported }
    }

    internal fun buildPatchPreview(
        entry: CheatEntry,
        cheatText: String,
        titleId: String,
        ppuHash: String,
        gameTitle: String = entry.title
    ): ArtemisPatchPreview = buildPatchPreview(
        entries = listOf(entry to cheatText),
        titleId = titleId,
        ppuHash = ppuHash,
        gameTitle = gameTitle
    )

    internal fun buildPatchPreview(
        entries: List<Pair<CheatEntry, String>>,
        titleId: String,
        ppuHash: String,
        gameTitle: String
    ): ArtemisPatchPreview {
        val patchItems = mutableListOf<PatchItem>()
        var skippedCheats = 0

        entries.forEach { (entry, text) ->
            parse(text).forEach { cheat ->
                if (cheat.isSupported) {
                    patchItems += PatchItem(entry = entry, cheat = cheat)
                } else {
                    skippedCheats++
                }
            }
        }

        val hashKey = "$titleId-$ppuHash"
        return ArtemisPatchPreview(
            patchBody = buildPatchBody(hashKey, titleId, gameTitle, patchItems),
            configBody = buildConfigBody(hashKey, titleId, gameTitle, patchItems),
            installedCheats = patchItems.size,
            skippedCheats = skippedCheats,
            installedWrites = patchItems.sumOf { it.cheat.writes.size }
        )
    }

    internal fun buildReadyPatchPreview(entries: List<CheatEntry>): ArtemisPatchPreview {
        return ArtemisPatchPreview(
            patchBody = mergeReadyYaml(entries.mapNotNull { it.readyPatchBody?.takeIf(String::isNotBlank) }),
            configBody = mergeReadyYaml(entries.mapNotNull { it.readyConfigBody?.takeIf(String::isNotBlank) }),
            installedCheats = entries.count { !it.readyPatchBody.isNullOrBlank() },
            skippedCheats = entries.count { it.readyPatchBody.isNullOrBlank() },
            installedWrites = entries.sumOf { countPatchOps(it.readyPatchBody) }
        )
    }

    private fun mergeReadyYaml(bodies: List<String>): String {
        val groupedBodies = linkedMapOf<String, MutableList<String>>()
        bodies.forEach { body ->
            val lines = body.trim().lines()
            val hashKey = lines.firstOrNull()
                ?.trim()
                ?.removeSuffix(":")
                ?.takeIf { it.isNotBlank() }
                ?: return@forEach
            val childBody = lines.drop(1).joinToString("\n").trimEnd()
            if (childBody.isNotBlank()) {
                groupedBodies.getOrPut(hashKey) { mutableListOf() } += childBody
            }
        }

        return groupedBodies.entries.joinToString("\n\n") { (hashKey, children) ->
            "$hashKey:\n${children.joinToString("\n")}"
        }
    }

    private fun countPatchOps(patchBody: String?): Int {
        if (patchBody.isNullOrBlank()) {
            return 0
        }

        return patchBody.lineSequence().count { it.trimStart().startsWith("- [") }
    }

    private fun parseBlock(rawBlock: String): ArtemisCheat? {
        val lines = rawBlock
            .lines()
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "#" }

        if (lines.isEmpty()) {
            return null
        }

        val name = lines.first().removePrefix("#").trim()
        if (name.isBlank()) {
            return null
        }

        var codeStart = 1
        if (lines.getOrNull(1)?.matches(Regex("[01]")) == true) {
            codeStart = 2
        }

        val author = lines.getOrNull(codeStart)
            ?.takeUnless { looksLikeCodeLine(it) }
            .orEmpty()
            .ifBlank { "Unknown" }
        if (author != "Unknown") {
            codeStart++
        }

        val writes = mutableListOf<ArtemisWrite>()
        val aobPatches = mutableListOf<ArtemisAobPatch>()
        val unsupported = linkedSetOf<String>()

        val codeLines = lines.drop(codeStart)
        var index = 0
        while (index < codeLines.size) {
            val line = codeLines[index]
            when {
                line.startsWith(";") -> Unit
                line.startsWith("[") -> unsupported += "Configurable placeholder values need a user choice before conversion."
                fixedWriteRegex.matches(line) -> {
                    val match = fixedWriteRegex.matchEntire(line) ?: error("Fixed write regex precheck failed")
                    val parsedWrites = staticWritesForValue(
                        address = match.groupValues[1],
                        value = match.groupValues[2]
                    )
                    if (parsedWrites == null) {
                        unsupported += "Static write value is not byte-aligned hex."
                    } else if (writes.size + parsedWrites.size > MAX_STATIC_OPS_PER_CHEAT) {
                        unsupported += "Static write payload is too large for a generated patch."
                    } else {
                        writes += parsedWrites
                    }
                }

                serialWriteRegex.matches(line) -> {
                    val match = serialWriteRegex.matchEntire(line) ?: error("Serial write regex precheck failed")
                    val nextLine = codeLines.getOrNull(index + 1)
                    val repeatMatch = nextLine?.let { serialWriteRegex.matchEntire(it) }
                    if (repeatMatch == null) {
                        unsupported += "Serial static write is missing its repeat descriptor."
                    } else {
                        val parsedWrites = serialWrites(
                            address = match.groupValues[1],
                            value = match.groupValues[2],
                            addressStep = repeatMatch.groupValues[1],
                            count = repeatMatch.groupValues[2]
                        )
                        if (parsedWrites == null) {
                            unsupported += "Serial static write is invalid or too large."
                        } else {
                            writes += parsedWrites
                        }
                        index++
                    }
                }

                aobReplaceRegex.matches(line) -> {
                    val match = aobReplaceRegex.matchEntire(line) ?: error("AoB regex precheck failed")
                    val searchPattern = match.groupValues[1].uppercase(Locale.US)
                    val replacePattern = match.groupValues[2].uppercase(Locale.US)
                    if (searchPattern.length == replacePattern.length && searchPattern.length % 2 == 0) {
                        aobPatches += ArtemisAobPatch(searchPattern, replacePattern)
                    } else {
                        unsupported += "AoB search/replace pattern lengths do not match."
                    }
                }

                firstToken(line).equals("B", ignoreCase = true) -> {
                    unsupported += "Unsupported AoB search/replace code."
                }

                looksLikeCodeLine(line) -> {
                    unsupported += "Unsupported Artemis code type: ${firstToken(line)}"
                }
            }
            index++
        }

        if (aobPatches.isNotEmpty()) {
            unsupported += "AoB search/replace parsed, but needs native byte validation before install."
        }

        if (writes.isEmpty() && unsupported.isEmpty()) {
            return null
        }

        return ArtemisCheat(
            name = name,
            author = author,
            writes = writes,
            aobPatches = aobPatches,
            unsupportedReasons = unsupported.toList()
        )
    }

    private fun staticWritesForValue(address: String, value: String): List<ArtemisWrite>? {
        val normalizedAddress = address.uppercase(Locale.US)
        val normalizedValue = value.uppercase(Locale.US)

        if (normalizedValue.length % 2 != 0) {
            return null
        }

        val startAddress = normalizedAddress.toLongOrNull(16) ?: return null
        val byteCount = normalizedValue.length / 2
        val chunkBytes = when {
            byteCount == 1 -> 1
            byteCount == 2 && startAddress % 2L == 0L -> 2
            byteCount >= 4 && byteCount % 4 == 0 && startAddress % 4L == 0L -> 4
            byteCount >= 2 && byteCount % 2 == 0 && startAddress % 2L == 0L -> 2
            else -> 1
        }
        val patchType = when (chunkBytes) {
            1 -> "be8"
            2 -> "be16"
            else -> "be32"
        }

        val chunks = normalizedValue.chunked(chunkBytes * 2)
        if (chunks.size > MAX_STATIC_OPS_PER_CHEAT) {
            return null
        }

        return chunks.mapIndexed { index, chunk ->
            ArtemisWrite(
                address = (startAddress + index.toLong() * chunkBytes)
                    .toString(16)
                    .uppercase(Locale.US)
                    .padStart(8, '0'),
                value = chunk,
                patchType = patchType
            )
        }
    }

    private fun serialWrites(
        address: String,
        value: String,
        addressStep: String,
        count: String
    ): List<ArtemisWrite>? {
        val startAddress = address.toLongOrNull(16) ?: return null
        val step = addressStep.toLongOrNull(16) ?: return null
        val repeatCount = count.toIntOrNull(16) ?: return null
        if (repeatCount <= 0 || repeatCount > MAX_STATIC_OPS_PER_CHEAT) {
            return null
        }

        val writes = mutableListOf<ArtemisWrite>()
        repeat(repeatCount) { index ->
            val targetAddress = (startAddress + step * index)
                .toString(16)
                .uppercase(Locale.US)
                .padStart(8, '0')
            val parsedWrites = staticWritesForValue(targetAddress, value) ?: return null
            writes += parsedWrites
            if (writes.size > MAX_STATIC_OPS_PER_CHEAT) {
                return null
            }
        }

        return writes
    }

    private fun looksLikeCodeLine(line: String): Boolean {
        val first = firstToken(line)
        return codeTokenRegex.matches(first)
    }

    private fun firstToken(line: String): String =
        line.trim().split(whitespaceRegex, limit = 2).firstOrNull().orEmpty()

    private fun buildPatchBody(
        hashKey: String,
        titleId: String,
        gameTitle: String,
        patchItems: List<PatchItem>
    ): String {
        if (patchItems.isEmpty()) {
            return ""
        }

        return buildString {
            appendLine("${yamlKey(hashKey)}:")
            patchItems.forEachIndexed { index, item ->
                val description = item.description(index)
                appendLine("  ${yamlKey(description)}:")
                appendLine("    Games:")
                appendLine("      ${yamlKey(gameTitle)}:")
                appendLine("        ${yamlKey(titleId)}:")
                appendLine("          - $APP_VERSION")
                appendLine("    Author: ${yamlScalar(item.cheat.author)}")
                appendLine("    Patch Version: \"1.0\"")
                appendLine("    Group: \"Artemis\"")
                appendLine("    Notes: ${yamlScalar("Converted from AldosTools Artemis NCL by RPCSX Easy. Source: ${item.entry.fileName}.")}")
                appendLine("    Patch:")
                item.cheat.writes.forEach { write ->
                    appendLine("      - [ ${write.patchType}, 0x${write.address}, 0x${write.value} ]")
                }
            }
        }.trimEnd()
    }

    private fun buildConfigBody(
        hashKey: String,
        titleId: String,
        gameTitle: String,
        patchItems: List<PatchItem>
    ): String {
        if (patchItems.isEmpty()) {
            return ""
        }

        return buildString {
            appendLine("${yamlKey(hashKey)}:")
            patchItems.forEachIndexed { index, item ->
                val description = item.description(index)
                appendLine("  ${yamlKey(description)}:")
                appendLine("    ${yamlKey(gameTitle)}:")
                appendLine("      ${yamlKey(titleId)}:")
                appendLine("        $APP_VERSION:")
                appendLine("          Enabled: true")
            }
        }.trimEnd()
    }

    private fun writeGeneratedSection(
        file: File,
        startMarker: String,
        endMarker: String,
        body: String,
        prefixIfCreated: String
    ): List<String> {
        file.parentFile?.mkdirs()

        val existed = file.exists()
        val original = if (existed) file.readText() else ""
        val backupPaths = mutableListOf<String>()

        if (existed && !original.contains(startMarker)) {
            val backup = File("${file.absolutePath}.rpcsx-easy.bak")
            if (!backup.exists()) {
                file.copyTo(backup, overwrite = false)
                backupPaths += backup.absolutePath
            }
        }

        val section = buildString {
            appendLine(startMarker)
            if (body.isNotBlank()) {
                appendLine(body)
            }
            appendLine(endMarker)
        }

        val current = if (original.isBlank() && prefixIfCreated.isNotBlank()) {
            prefixIfCreated
        } else {
            original
        }

        val updated = if (current.contains(startMarker) && current.contains(endMarker)) {
            val pattern = Regex(
                "${Regex.escape(startMarker)}[\\s\\S]*?${Regex.escape(endMarker)}\\s*"
            )
            pattern.replace(current, section)
        } else {
            buildString {
                append(current.trimEnd())
                if (isNotEmpty()) {
                    appendLine()
                    appendLine()
                }
                append(section)
            }
        }

        file.writeText(updated)
        return backupPaths
    }

    private fun rpcsxRoot(context: Context): File {
        return if (RPCSX.rootDirectory.isNotBlank()) {
            File(RPCSX.rootDirectory)
        } else {
            context.getExternalFilesDir(null) ?: context.filesDir
        }
    }

    private fun yamlKey(value: String): String = yamlScalar(value)

    private fun yamlScalar(value: String): String {
        val clean = value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", " ")
            .replace(whitespaceRegex, " ")
            .trim()
        return "\"$clean\""
    }

    private data class PatchItem(
        val entry: CheatEntry,
        val cheat: ArtemisCheat
    ) {
        fun description(index: Int): String {
            return "Artemis: ${entry.title} - ${cheat.name} [${index + 1}]"
        }
    }
}
