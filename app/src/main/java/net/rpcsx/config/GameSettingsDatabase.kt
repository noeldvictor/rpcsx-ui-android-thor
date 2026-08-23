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
            # PPU LLVM compile threads are uncapped (0 = auto). The old value of 2, with
            # native code pinning them to the three A510 cores, made a cold recompile take
            # about ten minutes at 51-58 C package against a 72 C guard.
            # Do not cap SPURS here; SPURS 4 caused a black-screen-alive load hang on Thor.
            # 2026-05-16 Thor A/B: RPCS3 Scheduler + SPU busy-wait dropped the opening field route to low single digits.
            Core:
              Max LLVM Compile Threads: 0
              Set DAZ and FTZ: true
              Thread Scheduler Mode: Operating System
              SPU Reservation Busy Waiting Percentage: 0
              SPU Reservation Busy Waiting Enabled: false
              Max SPURS Threads: 6
              # Accurate SPU Reservations stays ON. See the reversal note below.
              #
              # REVERTED 2026-08-23. It was set to false for a measured -10.6% CPU,
              # and the measurement stands, but the setting is not safe here:
              #
              #  - Upstream documents that disabling it "can break games like
              #    InFamous, which freezes right after the intro". Transformers on
              #    this device halts its SPU shortly after its intro.
              #  - SPUThread.cpp has a path taken ONLY when this is false, for
              #    reservations inside the SPURS block (raddr - spurs_addr <= 0x80).
              #    Its own comment says it works because "we have notifications for
              #    nearly all writes". Nearly all is not all, and a missed
              #    notification leaves SPURS reading stale state, which is what its
              #    kernel asserts on.
              #  - This profile had it explicitly true before, which was a decision,
              #    and flipping it was overriding that decision on a CPU number.
              #
              # The -10.6% is still available per-session and is recorded in
              # CLAUDE.md and README.md:
              #   adb shell setprop debug.rpcsx.thor.spu_accurate_reservations 0
              #
              # OLD COMMENT, kept because the measurement is still valid:
              # Accurate SPU Reservations OFF. -10.6% CPU at identical frames.
              #
              # g_use_rtm is false on ARM64, so with this ON every reservation store
              # in do_putlluc takes the hard vm::writer_lock. A profile of restored
              # gameplay puts VM range locking at 12.7% of ALL cycles.
              #
              # Two interleaved rounds on one restored savestate:
              #   on    fps 27.41  cores 3.348 [3.345..3.351]  SPU threads 1.782
              #   off   fps 27.30  cores 2.994 [2.951..3.037]  SPU threads 1.617
              # Ranges do not overlap, which the +/-5% noise floor demands.
              #
              # THIS RELAXES RESERVATION ATOMICITY and upstream ships it on. Observed
              # clean: both arms, plus about three minutes of restored gameplay with
              # no faults. That cannot rule out a problem an hour in. If this title
              # ever corrupts a save or hangs, set it back to true here first.
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
        """.trimIndent(),
        "BLUS30357" to """
            # RPCSX_THOR_PROFILE_OVERRIDE
            # Transformers: War for Cybertron profile for AYN Thor.
            #
            # MEASURED on device 2026-08-22, warm PPU cache. The frame rate in this
            # title swings enormously by scene, so a single number describes nothing:
            #
            #   engine cutscene, uncapped   120-133 FPS   3.74 cores
            #   engine cutscene, 30 cap     29.8-30.0     2.81 cores
            #   3D gameplay, uncapped       40.4 FPS      85.9% total CPU
            #   while compiling a shader     2.0 FPS
            #
            # THE CAP IS FOR HEAT, NOT FOR SPEED. Uncapped 3D gameplay at 85.9% CPU
            # took the CPU thermal zones to 88-94 C, against the 72 C guard this
            # project uses elsewhere; they fell back to 53 C within 25 s of stopping.
            # Capping the parts that can run fast keeps them from cooking the device
            # for frames the title never asked for, and costs -25% CPU on the scenes
            # that were exceeding 30.
            #
            # NOT VERIFIED, and it should not be assumed: whether uncapped frames mean
            # the SIMULATION runs fast. Frame rate and game speed are different things
            # and only the frame rate was measured here.
            #
            # Async with Shader Interpreter, not the default Async Shader Recompiler.
            # The recompiler stalls the frame when a shader is not ready yet, which is
            # what the 2.0 FPS reading above is: the overlay reads "Compiling shaders"
            # and the picture stops. The interpreter draws immediately with an
            # interpreted shader and compiles the real one behind it, which trades a
            # little steady-state cost for not freezing.
            #
            # No Core tuning here on purpose. A 25 s profile of this title puts 29.37%
            # of cycles in guest SPU code and 10.71% in rsx::thread::run_FIFO, with
            # vm::writer_lock at 1.24% and spu_thread::process_mfc_cmd at 1.05%. It is
            # NOT reservation-bound the way Eternal Sonata is, so that title's Core
            # settings do not apply and are deliberately not copied.
            #
            # The first boot costs about ten minutes of PPU LLVM compilation across six
            # workers. That is the size of this EBOOT, not a setting. The cache is
            # reused: the second boot reached a frame in about 30 s.
            # RSX FIFO Accuracy: Atomic, and this is the important line in this file.
            #
            # WITH THE DEFAULT "Fast" THIS TITLE HANGS. Measured twice: the RSX thread
            # dies about 35 s in with
            #
            #   SIG: Thread terminated due to fatal error:
            #        Dead FIFO commands queue state has been detected!
            #
            # and after that the emulator does NOT stop. One SPU thread keeps spinning
            # at ~90% of the whole process, 0.00 FPS, 87-94 C, until the user notices.
            # A profile taken in that state reads 90.79% in a single SPU thread and
            # describes nothing except a hung emulator; it was very nearly mistaken for
            # a bottleneck here.
            #
            # The exception text says what to do, and it is right: with Atomic and a
            # 20 us wake-up delay the same boot ran 280 s with zero fatal errors,
            # held 30.00 FPS, and reached the "Press START button" title screen, which
            # it had never got to before.
            Core:
              RSX FIFO Accuracy: Atomic
              # Accurate SPU Reservations stays ON. Reverted 2026-08-23.
              #
              # This title HALTS ITS OWN SPU inside CellSpursKernel0, and disabling
              # accurate reservations is documented upstream as causing exactly this
              # class of failure, a freeze shortly after the intro, in other titles.
              # SPUThread.cpp's SPURS path for !accurate_reservations relies on
              # "notifications for nearly all writes"; a missed one leaves the SPURS
              # kernel reading stale state, and stale state is what it asserts on.
              #
              # -8.4% CPU is not worth a freeze on a title that already halts. The
              # measurement is kept below and the property is still available.
              #
              # OLD COMMENT, measurement still valid:
              # Accurate SPU Reservations OFF. -8.4% CPU at identical frames.
              #
              # This title is MORE reservation-bound than Eternal Sonata. A verified
              # gameplay profile, 243,663 samples with no fatal error in the window,
              # reads vm::range_lock_internal 15.37%, vm::writer_lock 10.69% and
              # vm::passive_lock 3.07%: 29.1% of ALL cycles in VM range locking.
              #
              # Two interleaved rounds, measured at the title screen because it is
              # deterministic and already heavy at 70.7% CPU, reached with no input:
              #   on    fps 29.99  cores 2.81  [2.81..2.81]
              #   off   fps 30.00  cores 2.575 [2.57..2.58]
              #
              # Measuring by pressing through cutscenes was tried first and is WORTHLESS:
              # the same configuration gave 3.78 and 5.89 cores on consecutive rounds
              # because each run lands in a different scene. Use a state you can reach
              # identically every time.
              Accurate SPU Reservations: true
            Video:
              Frame limit: 30
              Shader Mode: Async with Shader Interpreter
              # 50 us, which is what the RPCS3 community recommends for this engine.
              #
              # STABILITY, and it is nearly free here. At 20 us this title crashed
              # roughly two boots in five with an SPU halt in CellSpursKernel0. At
              # 50 us: 0 of 4 boots crashed.
              #
              # Upstream warns that raising this costs performance badly
              # (RPCS3 issue 12295, 60 FPS to 20 FPS on God of War), so it was
              # measured rather than assumed: 2.568 cores against 2.557 at 20 us,
              # a 0.4% difference with overlapping ranges, at the same 30 FPS. The
              # regression that issue describes does not bite this title on this
              # device.
              Driver Wake-Up Delay: 50
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
