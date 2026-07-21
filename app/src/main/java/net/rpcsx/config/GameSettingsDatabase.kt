package net.rpcsx.config

import android.content.Context
import android.util.Log
import net.rpcsx.Game
import net.rpcsx.RPCSX
import net.rpcsx.performance.ThorPerformanceProfile
import net.rpcsx.utils.GameIdentity
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

object GameSettingsDatabase {
    private const val TAG = "GameSettingsDatabase"
    private const val ASSET_PATH = "config/config_database.dat"
    private const val PREFS_NAME = "rpcsx_auto_game_settings"
    private const val DISABLED_PREFIX = "disabled_"
    private const val MANAGED_HEADER = "# RPCSX_THOR_AUTO_SETTINGS"
    private const val TIMESTAMP_HEADER = "# Database timestamp: "
    private const val SOURCE_URL = "https://api.rpcs3.net/config/?api=v1"
    private val thorUnsafeSpuAsmjit = Regex("""^(\s*SPU Decoder:\s*)Recompiler \(ASMJIT\)\s*$""")
    private val databaseTimestampPattern = Regex("""^\s*"timestamp"\s*:\s*(\d+)\s*,?\s*$""")

    private val lock = Any()
    private var cachedDatabase: Database? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val thorProfileOverrides = mapOf(
        "BLUS30161" to """
            # RPCSX_THOR_PROFILE_OVERRIDE
            # Eternal Sonata stability/speed profile for AYN Thor.
            # Official DB requires Write Color Buffers; keep it for black-spot correctness.
            # 30 FPS matches the practical full-speed target for this title on Thor.
            # Cap Vulkan VRAM on shared-memory Adreno so cache/shader spikes do not eat the device.
            # Do not cap SPURS here; SPURS 4 caused a black-screen-alive load hang on Thor.
            # 2026-05-16 Thor A/B: RPCS3 Scheduler + SPU busy-wait dropped the opening field route to low single digits.
            Core:
              Set DAZ and FTZ: true
              Thread Scheduler Mode: Operating System
              SPU Reservation Busy Waiting Percentage: 0
              SPU Reservation Busy Waiting Enabled: false
              Max SPURS Threads: 6
              Accurate SPU Reservations: true
              SPU Verification: true
              Sleep Timers Accuracy: As Host
            Video:
              Frame limit: 30
              Write Color Buffers: true
              Accurate ZCULL stats: false
              Relaxed ZCULL Sync: false
              Multithreaded RSX: false
              Shader Compiler Threads: 0
              Vulkan:
                Force FIFO present mode: true
                VRAM allocation limit (MB): 3072
              Performance Overlay:
                Enabled: true
        """.trimIndent()
    )

    data class Status(
        val titleId: String?,
        val hasProfile: Boolean,
        val enabled: Boolean,
        val applied: Boolean,
        val customConfigPresent: Boolean,
        val configPath: String?,
        val databaseTimestamp: Long?,
        val databaseSource: String?,
        val databaseProfileCount: Int?,
        val cachePath: String?,
        val managedConfigStale: Boolean = false,
        val error: String? = null
    )

    data class RefreshResult(
        val updated: Boolean,
        val timestamp: Long?,
        val profileCount: Int?,
        val message: String?
    )

    private enum class DatabaseSource(val label: String) {
        LocalCache("local cache"),
        BundledSnapshot("bundled snapshot")
    }

    private data class Database(
        val timestamp: Long,
        val profiles: Map<String, String>,
        val source: DatabaseSource,
        val cachePath: String?
    )

    fun ensureDatabaseExported(context: Context): Boolean {
        return runCatching {
            val bundledTimestamp = readBundledDatabaseTimestamp(context)
            val local = readLocalDatabase(context)
            var selected = local

            if (local == null || bundledTimestamp == null || local.timestamp < bundledTimestamp) {
                val bundledText = readBundledDatabaseText(context)
                val bundled = parseDatabase(
                    json = bundledText,
                    source = DatabaseSource.BundledSnapshot,
                    cachePath = null
                )

                if (local == null || local.timestamp < bundled.timestamp) {
                    val target = localDatabaseFile(context)
                    target.parentFile?.mkdirs()
                    target.writeText(bundledText)
                    selected = bundled.copy(
                        source = DatabaseSource.LocalCache,
                        cachePath = target.absolutePath
                    )
                }
            }

            val ready = checkNotNull(selected) { "No usable config database was selected" }
            synchronized(lock) { cachedDatabase = ready }
            true
        }.getOrElse {
            Log.w(TAG, "Could not prepare local config database cache", it)
            false
        }
    }

    fun refreshLocalCache(context: Context): RefreshResult {
        return runCatching {
            val before = loadDatabase(context)
            val request = Request.Builder().url(SOURCE_URL).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return RefreshResult(
                        updated = false,
                        timestamp = before?.timestamp,
                        profileCount = before?.profiles?.size,
                        message = "Could not update settings cache: ${response.code}"
                    )
                }

                val body = response.body.string()
                val target = localDatabaseFile(context)
                val remote = parseDatabase(
                    json = body,
                    source = DatabaseSource.LocalCache,
                    cachePath = target.absolutePath
                )

                if (before != null && before.source == DatabaseSource.LocalCache && before.timestamp > remote.timestamp) {
                    return RefreshResult(
                        updated = false,
                        timestamp = before.timestamp,
                        profileCount = before.profiles.size,
                        message = "Local settings cache is newer than the server copy."
                    )
                }

                target.parentFile?.mkdirs()
                target.writeText(body)
                synchronized(lock) { cachedDatabase = remote }

                val beforeProfileCount = before?.profiles?.size
                val changed = before?.timestamp != remote.timestamp ||
                    beforeProfileCount != remote.profiles.size
                RefreshResult(
                    updated = changed,
                    timestamp = remote.timestamp,
                    profileCount = remote.profiles.size,
                    message = if (changed) {
                        "Updated settings cache."
                    } else {
                        "Settings cache is already current."
                    }
                )
            }
        }.getOrElse {
            Log.w(TAG, "Could not refresh local config database cache", it)
            val current = loadDatabase(context)
            RefreshResult(
                updated = false,
                timestamp = current?.timestamp,
                profileCount = current?.profiles?.size,
                message = "Could not update settings cache: ${it.message ?: "network error"}"
            )
        }
    }

    fun statusForGame(context: Context, game: Game): Status =
        statusForTitleId(context, GameIdentity.primaryTitleId(game))

    private fun statusForTitleId(context: Context, titleId: String?): Status {
        val database = loadDatabase(context)
        if (titleId == null) {
            return Status(
                titleId = null,
                hasProfile = false,
                enabled = false,
                applied = false,
                customConfigPresent = false,
                configPath = null,
                databaseTimestamp = database?.timestamp,
                databaseSource = database?.source?.label,
                databaseProfileCount = database?.profiles?.size,
                cachePath = database?.cachePath
            )
        }

        val profileConfig = database?.profiles?.get(titleId)
        val target = customConfigFile(titleId)
        val configText = target?.takeIf { it.exists() }?.readText()
        val expectedManagedConfig = if (
            configText?.startsWith(MANAGED_HEADER) == true &&
            database?.timestamp != null &&
            profileConfig != null
        ) {
            buildManagedConfig(titleId, database.timestamp, profileConfig)
        } else {
            null
        }
        return statusForConfigSnapshot(
            context,
            titleId,
            database,
            target,
            configText,
            expectedManagedConfig
        )
    }

    private fun statusForConfigSnapshot(
        context: Context,
        titleId: String,
        database: Database?,
        target: File?,
        configText: String?,
        expectedManagedConfig: String?
    ): Status {
        val hasProfile = database?.profiles?.containsKey(titleId) == true
        val disabled = isDisabled(context, titleId)
        val managed = configText?.startsWith(MANAGED_HEADER) == true
        val managedTimestamp = managedConfigTimestamp(configText)
        val timestampStale = database?.timestamp != null &&
            managedTimestamp != null &&
            managedTimestamp != database.timestamp
        val contentStale = expectedManagedConfig != null &&
            configText != expectedManagedConfig
        val managedStale = managed && (timestampStale || contentStale)
        val custom = configText != null && !managed

        return Status(
            titleId = titleId,
            hasProfile = hasProfile,
            enabled = hasProfile && !disabled && !custom,
            applied = hasProfile && managed && !managedStale,
            customConfigPresent = custom,
            configPath = target?.absolutePath,
            databaseTimestamp = database?.timestamp,
            databaseSource = database?.source?.label,
            databaseProfileCount = database?.profiles?.size,
            cachePath = database?.cachePath,
            managedConfigStale = managedStale
        )
    }

    fun setRecommendedSettingsEnabled(context: Context, game: Game, enabled: Boolean): Status {
        val titleId = GameIdentity.primaryTitleId(game) ?: return statusForGame(context, game)

        prefs(context)
            .edit()
            .putBoolean(DISABLED_PREFIX + titleId, !enabled)
            .apply()

        if (enabled) {
            applyRecommendedConfig(context, game)
        } else {
            removeManagedConfig(titleId)
        }

        return statusForGame(context, game)
    }

    fun applyRecommendedConfig(context: Context, game: Game): Status =
        applyRecommendedConfig(
            context,
            GameIdentity.primaryTitleId(game),
            replaceCustomConfig = false
        )

    fun applyRecommendedConfigForTitleId(context: Context, titleId: String): Status =
        applyRecommendedConfig(
            context,
            GameIdentity.titleIdsFromText(titleId).firstOrNull(),
            replaceCustomConfig = false
        )

    fun replaceCustomWithRecommendedConfig(context: Context, game: Game): Status =
        applyRecommendedConfig(
            context,
            GameIdentity.primaryTitleId(game),
            replaceCustomConfig = true
        )

    fun replaceCustomWithRecommendedConfigForTitleId(context: Context, titleId: String): Status =
        applyRecommendedConfig(
            context,
            GameIdentity.titleIdsFromText(titleId).firstOrNull(),
            replaceCustomConfig = true
        )

    private fun applyRecommendedConfig(
        context: Context,
        titleId: String?,
        replaceCustomConfig: Boolean
    ): Status {
        if (titleId == null) return statusForTitleId(context, null)
        val database = loadDatabase(context) ?: return statusForTitleId(context, titleId).copy(
            error = "Settings cache could not be loaded"
        )
        val config = database.profiles[titleId] ?: return statusForTitleId(context, titleId)

        if (isDisabled(context, titleId) && !replaceCustomConfig) {
            return statusForTitleId(context, titleId)
        }

        val target = customConfigFile(titleId) ?: return statusForTitleId(context, titleId).copy(
            error = "RPCSX root directory is not ready"
        )

        return runCatching {
            val existing = target.takeIf { it.exists() }?.readText()
            if (existing != null && !existing.startsWith(MANAGED_HEADER)) {
                if (!replaceCustomConfig) {
                    statusForConfigSnapshot(context, titleId, database, target, existing, null)
                } else {
                    backupCustomConfig(target)
                    val body = buildManagedConfig(titleId, database.timestamp, config)
                    target.writeText(body)
                    prefs(context)
                        .edit()
                        .putBoolean(DISABLED_PREFIX + titleId, false)
                        .apply()
                    statusForConfigSnapshot(context, titleId, database, target, body, body)
                }
            } else {
                val body = buildManagedConfig(titleId, database.timestamp, config)
                if (existing != body) {
                    target.parentFile?.mkdirs()
                    target.writeText(body)
                }
                if (replaceCustomConfig) {
                    prefs(context)
                        .edit()
                        .putBoolean(DISABLED_PREFIX + titleId, false)
                        .apply()
                }

                statusForConfigSnapshot(context, titleId, database, target, body, body)
            }
        }.getOrElse {
            Log.w(TAG, "Could not apply recommended settings for $titleId", it)
            statusForTitleId(context, titleId).copy(error = it.message)
        }
    }

    private fun backupCustomConfig(target: File) {
        if (!target.exists()) {
            return
        }

        val backupName = buildString {
            append(target.nameWithoutExtension)
            append(".user-backup-")
            append(System.currentTimeMillis())
            if (target.extension.isNotBlank()) {
                append('.')
                append(target.extension)
            }
        }
        target.copyTo(File(target.parentFile, backupName), overwrite = false)
    }

    private fun removeManagedConfig(titleId: String) {
        val target = customConfigFile(titleId) ?: return
        if (!target.exists()) {
            return
        }

        val existing = runCatching { target.readText() }.getOrNull()
        if (existing?.startsWith(MANAGED_HEADER) == true) {
            target.delete()
        }
    }

    private fun loadDatabase(context: Context): Database? = synchronized(lock) {
        cachedDatabase?.let { return@synchronized it }

        val database = readLocalDatabase(context) ?: readBundledDatabase(context)
        cachedDatabase = database
        database
    }

    private fun readLocalDatabase(context: Context): Database? {
        val file = localDatabaseFile(context)
        if (!file.exists()) {
            return null
        }

        return runCatching {
            parseDatabase(
                json = file.readText(),
                source = DatabaseSource.LocalCache,
                cachePath = file.absolutePath
            )
        }.getOrElse {
            Log.w(TAG, "Ignoring invalid local config database cache", it)
            null
        }
    }

    private fun readBundledDatabase(context: Context): Database? {
        return runCatching {
            parseDatabase(
                json = readBundledDatabaseText(context),
                source = DatabaseSource.BundledSnapshot,
                cachePath = null
            )
        }.getOrElse {
            Log.w(TAG, "Could not load bundled config database", it)
            null
        }
    }

    private fun readBundledDatabaseText(context: Context): String =
        context.assets.open(ASSET_PATH).bufferedReader().use { it.readText() }

    private fun readBundledDatabaseTimestamp(context: Context): Long? {
        context.assets.open(ASSET_PATH).bufferedReader().use { reader ->
            repeat(16) {
                val line = reader.readLine() ?: return null
                val timestamp = databaseTimestampPattern
                    .matchEntire(line)
                    ?.groupValues
                    ?.getOrNull(1)
                    ?.toLongOrNull()
                if (timestamp != null) return timestamp
            }
        }
        return null
    }

    private fun parseDatabase(
        json: String,
        source: DatabaseSource,
        cachePath: String?
    ): Database {
        val root = JSONObject(json)
        if (root.optInt("return_code", -1) < 0) {
            error("Config database returned an error code")
        }

        val games = root.optJSONObject("games") ?: error("Config database has no games object")
        val profiles = buildMap {
            val keys = games.keys()
            while (keys.hasNext()) {
                val titleId = keys.next()
                val config = games.optJSONObject(titleId)?.optString("config").orEmpty()
                if (config.isNotBlank()) {
                    put(titleId, config)
                }
            }
            thorProfileOverrides.forEach { (titleId, config) ->
                put(titleId, config)
            }
        }

        if (profiles.isEmpty()) {
            error("Config database has no valid profiles")
        }

        return Database(
            timestamp = root.optLong("timestamp", 0L),
            profiles = profiles,
            source = source,
            cachePath = cachePath
        )
    }

    private fun localDatabaseFile(context: Context): File {
        val externalRoot = context.getExternalFilesDir(null)
        val root = when {
            RPCSX.rootDirectory.isNotBlank() -> File(RPCSX.rootDirectory)
            externalRoot != null -> externalRoot
            else -> context.filesDir
        }

        return File(root, "config/GuiConfigs/config_database.dat")
    }

    private fun customConfigFile(titleId: String): File? {
        if (RPCSX.rootDirectory.isBlank()) {
            return null
        }

        return File(RPCSX.rootDirectory, "config/custom_configs/config_$titleId.yml")
    }

    private fun buildManagedConfig(titleId: String, timestamp: Long, config: String): String {
        return buildString {
            appendLine(MANAGED_HEADER)
            appendLine("# Source: $SOURCE_URL")
            appendLine(TIMESTAMP_HEADER + timestamp)
            appendLine("# Title ID: $titleId")
            append(sanitizeThorManagedConfig(config.trimEnd()))
            appendLine()
        }
    }

    private fun sanitizeThorManagedConfig(config: String): String {
        if (!ThorPerformanceProfile.isThorTarget()) {
            return config
        }

        return config
            .lineSequence()
            .map { line ->
                thorUnsafeSpuAsmjit.matchEntire(line)?.let { match ->
                    "${match.groupValues[1]}Recompiler (LLVM)"
                } ?: line
            }
            .joinToString("\n")
    }

    private fun managedConfigTimestamp(configText: String?): Long? {
        if (configText.isNullOrBlank()) {
            return null
        }

        return configText
            .lineSequence()
            .firstOrNull { it.startsWith(TIMESTAMP_HEADER) }
            ?.removePrefix(TIMESTAMP_HEADER)
            ?.trim()
            ?.toLongOrNull()
    }

    private fun isDisabled(context: Context, titleId: String): Boolean =
        prefs(context).getBoolean(DISABLED_PREFIX + titleId, false)

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
