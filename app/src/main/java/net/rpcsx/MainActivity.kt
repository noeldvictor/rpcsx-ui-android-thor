package net.rpcsx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import net.rpcsx.config.GameSettingsDatabase
import net.rpcsx.dialogs.AlertDialogQueue
import net.rpcsx.performance.CacheStorageManager
import net.rpcsx.performance.GameCacheRepository
import net.rpcsx.performance.ThorPerformanceProfile
import net.rpcsx.ui.navigation.AppNavHost
import net.rpcsx.utils.GameIdentity
import net.rpcsx.utils.GeneralSettings
import net.rpcsx.utils.GitHub
import net.rpcsx.utils.RpcsxUpdater
import java.io.File
import kotlin.concurrent.thread

class MainActivity : ComponentActivity() {
    private var unregisterUsbEventListener: () -> Unit = {}
    private var thorCachePreparationRequestId: String? = null

    private fun findThorDevCoreOverride(): File? {
        if (!BuildConfig.THOR_DEV_CORE_OVERRIDE) {
            return null
        }

        val marker = File(filesDir, "dev-core/active-core.path")
        if (!marker.isFile || !marker.canRead()) {
            return null
        }

        val corePath = runCatching { marker.readLines().firstOrNull()?.trim() }.getOrNull()
        if (corePath.isNullOrEmpty()) {
            return null
        }

        val core = File(corePath)
        if (!core.isFile || !core.canRead() || core.length() < 4096) {
            Log.w("RPCSX-UI", "Ignoring invalid Thor dev core override: $corePath")
            return null
        }

        return core
    }

    private fun maybeStartThorDebugCachePreparation(sourceIntent: Intent?): Boolean {
        if (!BuildConfig.THOR_DEBUG_TOOLS || sourceIntent == null) {
            return false
        }

        if (sourceIntent.action != "net.rpcsx.THOR_DEBUG_PREPARE_CACHE") {
            return false
        }

        val rawRequestId = sourceIntent.getStringExtra("thorCachePrepareRequestId")
        val requestId = rawRequestId
            ?.takeIf { it.matches(Regex("^[A-Za-z0-9._-]{1,80}$")) }
            ?: "invalid"
        val gamePath = sourceIntent.getStringExtra("path")
        val requestedTitleId = sourceIntent.getStringExtra("titleId")
        val requireManagedProfile = sourceIntent.getBooleanExtra("thorRequireManagedProfile", false)
        sourceIntent.removeExtra("path")
        sourceIntent.removeExtra("titleId")
        sourceIntent.removeExtra("thorCachePrepareRequestId")
        sourceIntent.removeExtra("thorRequireManagedProfile")

        fun reject(reason: String): Boolean {
            Log.e("RPCSX-UI", "Thor debug cache preparation rejected: request=$requestId reason=$reason")
            return true
        }

        if (requestId == "invalid") {
            return reject("invalid-request-id")
        }
        if (gamePath.isNullOrBlank() || !File(gamePath).isAbsolute) {
            return reject("missing-or-nonabsolute-path")
        }

        val titleId = GameIdentity.titleIdsFromText(requestedTitleId).firstOrNull()
        if (titleId != "BLUS30161") {
            return reject("unsupported-title titleId=$titleId")
        }
        if (!requireManagedProfile) {
            return reject("managed-profile-required")
        }
        if (RPCSX.activeLibrary.value == null) {
            return reject("library-inactive")
        }
        thorCachePreparationRequestId?.let { activeRequestId ->
            return reject("busy activeRequest=$activeRequestId")
        }

        val settingsStatus = GameSettingsDatabase.applyRecommendedConfigForTitleId(this, titleId)
        if (!(settingsStatus.enabled && settingsStatus.applied)) {
            return reject(
                "managed-profile-not-applied titleId=$titleId " +
                    "custom=${settingsStatus.customConfigPresent} enabled=${settingsStatus.enabled} " +
                    "applied=${settingsStatus.applied} stale=${settingsStatus.managedConfigStale} " +
                    "error=${settingsStatus.error}"
            )
        }

        val cacheGame = Game(GameInfoStore(gamePath))
        cacheGame.info.titleId.value = titleId
        thorCachePreparationRequestId = requestId
        Log.w(
            "RPCSX-UI",
            "Thor debug cache preparation accepted: request=$requestId titleId=$titleId path=$gamePath"
        )
        GameCacheRepository.prepareGameCache(this, cacheGame) { status ->
            if (thorCachePreparationRequestId == requestId) {
                thorCachePreparationRequestId = null
            }
            Log.w(
                "RPCSX-UI",
                "Thor debug cache preparation finished: request=$requestId titleId=$titleId " +
                    "warm=${status.isWarm} ppu=${status.ppuEntries} entries=${status.totalEntries} " +
                    "bytes=${status.bytes}"
            )
        }
        return true
    }

    private fun maybeStartThorDebugBoot(sourceIntent: Intent?): Boolean {
        if (!BuildConfig.THOR_DEBUG_TOOLS || sourceIntent == null) {
            return false
        }

        if (sourceIntent.action != "net.rpcsx.THOR_DEBUG_BOOT") {
            return false
        }

        val gamePath = sourceIntent.getStringExtra("path")
        val requestedTitleId = sourceIntent.getStringExtra("titleId")
        val requestId = sourceIntent.getStringExtra("thorDebugBootRequestId")
            ?.takeIf { it.matches(Regex("^[A-Za-z0-9._-]{1,80}$")) }
            ?: "unknown"
        val requireManagedProfile = sourceIntent.getBooleanExtra("thorRequireManagedProfile", false)
        val replaceCustomProfile = sourceIntent.getBooleanExtra("thorReplaceCustomProfile", false)
        val displayPacingEnabled = sourceIntent.getBooleanExtra("thorDisplayPacing", true)
        sourceIntent.removeExtra("path")
        sourceIntent.removeExtra("titleId")
        sourceIntent.removeExtra("thorDebugBootRequestId")
        sourceIntent.removeExtra("thorRequireManagedProfile")
        sourceIntent.removeExtra("thorReplaceCustomProfile")
        sourceIntent.removeExtra("thorDisplayPacing")
        if (gamePath.isNullOrBlank()) {
            Log.e("RPCSX-UI", "Thor debug boot rejected: request=$requestId reason=missing-path")
            return false
        }

        if (RPCSX.activeLibrary.value == null) {
            Log.e("RPCSX-UI", "Thor debug boot rejected: request=$requestId reason=library-inactive")
            return false
        }

        val game = GameRepository.find(gamePath)
        val titleId = GameIdentity.titleIdsFromText(requestedTitleId).firstOrNull()
            ?: game?.let(GameIdentity::primaryTitleId)
        val settingsStatus = when {
            requireManagedProfile && titleId != null && replaceCustomProfile ->
                GameSettingsDatabase.replaceCustomWithRecommendedConfigForTitleId(this, titleId)
            requireManagedProfile && titleId != null ->
                GameSettingsDatabase.applyRecommendedConfigForTitleId(this, titleId)
            else -> null
        }
        val managedProfileReady = settingsStatus?.let { it.enabled && it.applied } == true
        if (requireManagedProfile && !managedProfileReady) {
            Log.e(
                "RPCSX-UI",
                "Thor debug boot rejected: request=$requestId reason=managed-profile-not-applied " +
                    "titleId=$titleId custom=${settingsStatus?.customConfigPresent} " +
                    "enabled=${settingsStatus?.enabled} applied=${settingsStatus?.applied} " +
                    "stale=${settingsStatus?.managedConfigStale} error=${settingsStatus?.error}"
            )
            return false
        }

        val emulatorWindow = Intent(this, RPCSXActivity::class.java)
            .putExtra("path", gamePath)
            .putExtra("thorDisplayPacing", displayPacingEnabled)
        titleId?.let {
            emulatorWindow.putExtra("titleId", it)
        }
        startActivity(emulatorWindow)
        Log.w("RPCSX-UI", "Thor debug boot accepted: request=$requestId titleId=$titleId path=$gamePath")
        return true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        GeneralSettings.init(this)

        WindowCompat.setDecorFitsSystemWindows(window, false)

        if (!RPCSX.initialized) {
            Permission.PostNotifications.requestPermission(this)

            with(getSystemService(NOTIFICATION_SERVICE) as NotificationManager) {
                val channel = NotificationChannel(
                    "rpcsx-progress",
                    getString(R.string.installation_progress),
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }

                createNotificationChannel(channel)
            }

            RPCSX.rootDirectory = applicationContext.getExternalFilesDir(null).toString()
            if (!RPCSX.rootDirectory.endsWith("/")) {
                RPCSX.rootDirectory += "/"
            }
            CacheStorageManager.ensureSelectedLocation(this).also { result ->
                if (!result.success) {
                    Log.w("RPCSX-UI", "Cache storage setup failed: ${result.message}")
                }
            }
            GameSettingsDatabase.ensureDatabaseExported(this)

            lifecycleScope.launch {
                GameRepository.load()
            }

            FirmwareRepository.load()
            GitHub.initialize(this)

            val nativeLibraryDir =
                packageManager.getApplicationInfo(packageName, 0).nativeLibraryDir
            RPCSX.nativeLibDirectory = nativeLibraryDir

            var rpcsxLibrary = GeneralSettings["rpcsx_library"] as? String
            val rpcsxPrevLibrary = GeneralSettings["rpcsx_prev_library"] as? String

            val bundledCore = File(nativeLibraryDir, "librpcsx-android.so")
            val hasBundledCore = bundledCore.isFile && bundledCore.canRead()
            val devCore = findThorDevCoreOverride()

            if (devCore != null) {
                val activeDevCore = checkNotNull(devCore)
                rpcsxLibrary = activeDevCore.path
                GeneralSettings["rpcsx_library"] = activeDevCore.path
                GeneralSettings["rpcsx_installed_arch"] = "dev-core"
                GeneralSettings["rpcsx_update_status"] = true
                GeneralSettings["rpcsx_prev_installed_arch"] = null
                GeneralSettings["rpcsx_prev_library"] = null
                GeneralSettings["rpcsx_bad_version"] = null
                GeneralSettings.sync()
                Log.w("RPCSX-UI", "Using Thor dev core override: ${activeDevCore.path}")
            }

            if (devCore == null && (BuildConfig.FORK_BUILD || rpcsxLibrary == null) && hasBundledCore) {
                rpcsxLibrary = bundledCore.path
                GeneralSettings["rpcsx_library"] = bundledCore.path
                GeneralSettings["rpcsx_installed_arch"] = "bundled"
                GeneralSettings["rpcsx_update_status"] = true
                GeneralSettings["rpcsx_prev_installed_arch"] = null
                GeneralSettings["rpcsx_prev_library"] = null
                GeneralSettings["rpcsx_bad_version"] = null
                GeneralSettings.sync()
            }

            if (rpcsxLibrary != null) {
                val rpcsxUpdateStatus = GeneralSettings["rpcsx_update_status"]
                if (rpcsxUpdateStatus == false && rpcsxPrevLibrary != null) {
                    GeneralSettings["rpcsx_library"] = rpcsxPrevLibrary
                    GeneralSettings["rpcsx_installed_arch"] = GeneralSettings["rpcsx_prev_installed_arch"]
                    GeneralSettings["rpcsx_prev_installed_arch"] = null
                    GeneralSettings["rpcsx_prev_library"] = null
                    GeneralSettings["rpcsx_bad_version"] = RpcsxUpdater.getFileVersion(File(rpcsxLibrary))
                    GeneralSettings.sync()

                    File(rpcsxLibrary).delete()
                    rpcsxLibrary = rpcsxPrevLibrary

                    AlertDialogQueue.showDialog(
                        getString(R.string.failed_to_update_rpcsx),
                        getString(R.string.failed_to_load_new_version)
                    )
                } else if (rpcsxUpdateStatus == null) {
                    GeneralSettings["rpcsx_update_status"] = false
                    GeneralSettings.sync()
                }

                if (!RPCSX.openLibrary(rpcsxLibrary) && hasBundledCore && rpcsxLibrary != bundledCore.path) {
                    rpcsxLibrary = bundledCore.path
                    GeneralSettings["rpcsx_library"] = bundledCore.path
                    GeneralSettings["rpcsx_installed_arch"] = "bundled"
                    GeneralSettings["rpcsx_update_status"] = true
                    GeneralSettings.sync()
                    RPCSX.openLibrary(rpcsxLibrary)
                }
            }

            if (RPCSX.activeLibrary.value != null) {
                ThorPerformanceProfile.applyRuntimeAffinity()
                RPCSX.instance.initialize(RPCSX.rootDirectory, UserRepository.getUserFromSettings())
                ThorPerformanceProfile.applyStartupDefaults()
                val gpuDriverPath = GeneralSettings["gpu_driver_path"] as? String
                val gpuDriverName = GeneralSettings["gpu_driver_name"] as? String

                if (gpuDriverPath != null && gpuDriverName != null) {
                    RPCSX.instance.setCustomDriver(gpuDriverPath, gpuDriverName, nativeLibraryDir)
                }

                lifecycleScope.launch {
                    UserRepository.load()
                }

                RPCSX.initialized = true

                thread(name = "RPCSX-MainThreadProcessor") {
                    ThorPerformanceProfile.applyRuntimeAffinity()
                    RPCSX.instance.startMainThreadProcessor()
                }

                thread(name = "RPCSX-CompilationQueue") {
                    ThorPerformanceProfile.applyRuntimeAffinity()
                    RPCSX.instance.processCompilationQueue()
                }

                GeneralSettings["rpcsx_update_status"] = true
                if (rpcsxPrevLibrary != null) {
                    if (rpcsxLibrary != rpcsxPrevLibrary) {
                        File(rpcsxPrevLibrary).delete()
                    }

                    GeneralSettings["rpcsx_prev_library"] = null
                    GeneralSettings["rpcsx_prev_installed_arch"] = null
                    GeneralSettings.sync()
                }
            }

            val updateFile = File(RPCSX.rootDirectory + "cache", "rpcsx-${BuildConfig.Version}.apk")
            if (updateFile.exists()) {
                updateFile.delete()
            }
        }

        // A benchmark/debug launch does not need to compose and draw the game
        // library underneath the emulation surface. Skipping it also prevents
        // launcher cover art from appearing as a transient route candidate.
        if (maybeStartThorDebugCachePreparation(intent) || maybeStartThorDebugBoot(intent)) {
            return
        }

        setContent {
            RPCSXTheme {
                AppNavHost()
            }
        }

        if (RPCSX.activeLibrary.value != null) {
            unregisterUsbEventListener = listenUsbEvents(this)
        } else {
            unregisterUsbEventListener = {}
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (maybeStartThorDebugCachePreparation(intent)) {
            return
        }
        maybeStartThorDebugBoot(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterUsbEventListener()
    }

}
