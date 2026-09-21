package net.rpcsx.ui.games

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import net.rpcsx.EmulatorState
import net.rpcsx.FirmwareRepository
import net.rpcsx.Game
import net.rpcsx.GameFlag
import net.rpcsx.GameProgress
import net.rpcsx.GameProgressType
import net.rpcsx.GameRepository
import net.rpcsx.ProgressRepository
import net.rpcsx.R
import net.rpcsx.RPCSX
import net.rpcsx.RPCSXActivity
import net.rpcsx.config.GameSettingsDatabase
import net.rpcsx.dialogs.AlertDialogQueue
import net.rpcsx.performance.ThorPerformanceProfile
import net.rpcsx.utils.GameIdentity
import kotlin.concurrent.thread

@Composable
fun rememberGameLauncher(game: Game): () -> Unit {
    val context = LocalContext.current
    val installKeyLauncher =
        rememberLauncherForActivityResult(contract = ActivityResultContracts.GetContent()) { uri ->
            if (uri != null) {
                val descriptor = context.contentResolver.openAssetFileDescriptor(uri, "r")
                val fd = descriptor?.parcelFileDescriptor?.fd

                if (fd != null) {
                    val installProgress = ProgressRepository.create(
                        context,
                        context.getString(R.string.license_installation)
                    )
                    game.addProgress(GameProgress(installProgress, GameProgressType.Compile))

                    thread(isDaemon = true) {
                        if (!RPCSX.instance.installKey(fd, installProgress, game.info.path)) {
                            try {
                                ProgressRepository.onProgressEvent(installProgress, -1, 0)
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        }

                        try {
                            descriptor.close()
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                    }
                } else {
                    try {
                        descriptor?.close()
                    } catch (e: Exception) {
                        e.printStackTrace()
                    }
                }
            }
        }

    return {
        launchGame(context, game) {
            installKeyLauncher.launch("*/*")
        }
    }
}

private fun launchGame(
    context: Context,
    game: Game,
    installKey: () -> Unit
) {
    if (game.hasFlag(GameFlag.Locked)) {
        AlertDialogQueue.showDialog(
            title = context.getString(R.string.missing_key),
            message = context.getString(R.string.game_require_key),
            onConfirm = installKey,
            onDismiss = {},
            confirmText = context.getString(R.string.install_rap_file)
        )
        return
    }

    if (FirmwareRepository.version.value == null) {
        AlertDialogQueue.showDialog(
            title = context.getString(R.string.missing_firmware),
            message = context.getString(R.string.install_firmware_to_continue)
        )
        return
    }

    if (FirmwareRepository.progressChannel.value != null) {
        AlertDialogQueue.showDialog(
            title = context.getString(R.string.missing_firmware),
            message = context.getString(R.string.wait_until_firmware_install)
        )
        return
    }

    if (game.info.path == "$" || game.findProgress(arrayOf(GameProgressType.Install, GameProgressType.Remove)) != null) {
        Log.w("RPCSX Launch", "refused '${game.info.path}': install or remove in progress")
        return
    }

    if (game.findProgress(GameProgressType.Compile) != null) {
        AlertDialogQueue.showDialog(
            title = context.getString(R.string.game_compiling_not_finished),
            message = context.getString(R.string.wait_until_game_compile)
        )
        return
    }

    // Ask the core, not the cached value. The cached value is set from the
    // game activity's stop watcher, which the activity can outlive, so it can
    // say Stopping after the core reached Stopped. A refusal here used to be
    // silent; the tap did nothing and the log held nothing (2026-09-21).
    val emulatorState = runCatching { RPCSX.getState() }.getOrDefault(RPCSX.state.value)
    if (emulatorState == EmulatorState.Stopping) {
        Log.w("RPCSX Launch", "refused '${game.info.path}': the previous game is still stopping")
        AlertDialogQueue.showDialog(
            title = context.getString(R.string.failed_to_boot),
            message = context.getString(R.string.previous_game_still_stopping)
        )
        return
    }

    GameSettingsDatabase.applyRecommendedConfig(context, game)
    ThorPerformanceProfile.applyRuntimeAffinity()
    GameRepository.onBoot(game)
    val emulatorWindow = Intent(context, RPCSXActivity::class.java)
    emulatorWindow.putExtra("path", game.info.path)
    GameIdentity.primaryTitleId(game)?.let { emulatorWindow.putExtra("titleId", it) }
    context.startActivity(emulatorWindow)
}
