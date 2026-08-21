package net.rpcsx.ui.settings.main

import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.documentfile.provider.DocumentFile
import net.rpcsx.R
import net.rpcsx.RPCSX
import net.rpcsx.UserRepository
import net.rpcsx.dialogs.AlertDialogQueue
import net.rpcsx.performance.CacheStorageManager
import net.rpcsx.provider.AppDataDocumentProvider
import net.rpcsx.ui.common.ComposePreview
import net.rpcsx.ui.settings.components.core.PreferenceIcon
import net.rpcsx.ui.settings.components.preference.HomePreference
import net.rpcsx.utils.FileUtil
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    modifier: Modifier = Modifier,
    navigateBack: () -> Unit,
    navigateTo: (path: String) -> Unit,
    onRefresh: () -> Unit
) {
    val topBarScrollBehavior = TopAppBarDefaults.enterAlwaysScrollBehavior()
    val activeUser by remember { UserRepository.activeUser }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var cacheStorageStatus by remember { mutableStateOf<CacheStorageManager.Status?>(null) }
    var cacheStorageMessage by remember { mutableStateOf<String?>(null) }
    var cacheStorageBusy by remember { mutableStateOf(false) }
    var showCacheStorageDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        cacheStorageStatus = withContext(Dispatchers.IO) {
            CacheStorageManager.status(context)
        }
    }

    fun switchCacheStorage(location: CacheStorageManager.Location) {
        showCacheStorageDialog = false
        val warning = if (location.removable) {
            "SD-card compiled cache can save internal space, but shader/PPU/SPU cache reads can stutter. Close running games first. Moving a large cache can take minutes."
        } else {
            "Internal compiled cache is the fastest choice for shader/PPU/SPU cache. Switching back may move cache files from SD storage and can take minutes if the cache is large."
        }

        AlertDialogQueue.showDialog(
            title = "Use ${location.label}?",
            message = warning,
            confirmText = "Use",
            dismissText = "Cancel",
            onConfirm = {
                scope.launch {
                    cacheStorageBusy = true
                    val result = withContext(Dispatchers.IO) {
                        CacheStorageManager.setLocation(context, location)
                    }
                    cacheStorageStatus = result.status
                    cacheStorageMessage = result.message
                    cacheStorageBusy = false
                    if (!result.success) {
                        AlertDialogQueue.showDialog(
                            title = context.getString(R.string.error),
                            message = result.message
                        )
                    }
                }
            }
        )
    }

    if (showCacheStorageDialog) {
        CacheStorageDialog(
            status = cacheStorageStatus,
            busy = cacheStorageBusy,
            onDismiss = { showCacheStorageDialog = false },
            onSelect = ::switchCacheStorage
        )
    }

    Scaffold(
        modifier = Modifier
            .nestedScroll(topBarScrollBehavior.nestedScrollConnection)
            .then(modifier), topBar = {
            LargeTopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.settings),
                        fontWeight = FontWeight.Medium
                    )
                },
                scrollBehavior = topBarScrollBehavior,
                navigationIcon = {
                    IconButton(
                        onClick = navigateBack
                    ) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_keyboard_arrow_left),
                            null
                        )
                    }
                })
        }
    ) { contentPadding ->
        val configPicker = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.OpenDocument(),
            onResult = { uri: Uri? ->
                uri?.let {
                    if (FileUtil.importConfig(context, it))
                        onRefresh()
                }
            }
        )

        val configExporter = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.CreateDocument("application/x-yaml"),
            onResult = { uri: Uri? ->
                uri?.let { FileUtil.exportConfig(context, it) }
            }
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding),
        ) {
            item {
                Spacer(modifier = Modifier.height(16.dp))
            }

            item(
                key = "internal_directory"
            ) {
                HomePreference(
                    title = stringResource(R.string.view_internal_dir),
                    icon = { PreferenceIcon(icon = painterResource(R.drawable.ic_folder)) },
                    description = stringResource(R.string.view_internal_dir_description),
                    onClick = {
                        if (!FileUtil.launchInternalDir(context)) {
                            AlertDialogQueue.showDialog(
                                R.string.failed_to_view_internal_dir,
                                R.string.no_activity_to_handle_action
                            )
                        }
                    }
                )
            }

            item(key = "cache_storage") {
                val status = cacheStorageStatus
                val description = when {
                    cacheStorageBusy -> "Switching cache storage."
                    status == null -> "Checking cache storage."
                    else -> buildString {
                        append(status.activeLocation.label)
                        append("; PPU/SPU/shaders; ")
                        append(CacheStorageManager.formatBytes(status.bytes))
                        append(" used; ")
                        append(CacheStorageManager.formatBytes(status.activeLocation.freeBytes))
                        append(" free.")
                        if (status.redirected) {
                            append(" Redirected to selected storage.")
                        }
                        status.warning?.let {
                            append(" ")
                            append(it)
                        }
                        cacheStorageMessage?.let {
                            append(" ")
                            append(it)
                        }
                    }
                }

                HomePreference(
                    title = "Compiled Cache Storage",
                    icon = { PreferenceIcon(icon = painterResource(R.drawable.ic_folder)) },
                    description = description,
                    onClick = {
                        showCacheStorageDialog = true
                    }
                )
            }

            item(
                key = "users"
            ) {
                HomePreference(
                    title = stringResource(R.string.users),
                    description = "${stringResource(R.string.active_user)}: ${
                        UserRepository.getUsername(
                            activeUser
                        )
                    }",
                    icon = {
                        PreferenceIcon(icon = painterResource(id = R.drawable.ic_person))
                    },
                    onClick = {
                        navigateTo("users")
                    }
                )
            }

            item(key = "update_channels") {
                HomePreference(
                    title = stringResource(R.string.download_channels),
                    icon = { PreferenceIcon(icon = painterResource(R.drawable.ic_cloud_download)) },
                    description = "",
                    onClick = {
                        navigateTo("update_channels")
                    }
                )
            }

            item(key = "advanced_settings") {
                HomePreference(
                    title = stringResource(R.string.advanced_settings),
                    icon = { Icon(painterResource(R.drawable.tune), null) },
                    description = stringResource(R.string.advanced_settings_description),
                    onClick = {
                        navigateTo("settings@@$")
                    },
                    onLongClick = {
                        AlertDialogQueue.showDialog(
                            titleRes = R.string.manage_settings,
                            confirmTextRes = R.string.export,
                            dismissTextRes = R.string.import_,
                            onDismiss = {
                                configPicker.launch(arrayOf("*/*"))
                            },
                            onConfirm = {
                                configExporter.launch("config.yml")
                            }
                        )
                    }
                )
            }

            item(
                key = "custom_driver"
            ) {
                HomePreference(
                    title = stringResource(R.string.custom_driver),
                    icon = { Icon(painterResource(R.drawable.memory), contentDescription = null) },
                    description = stringResource(R.string.custom_driver_description),
                    onClick = {
                        if (RPCSX.instance.supportsCustomDriverLoading()) {
                            navigateTo("drivers")
                        } else {
                            AlertDialogQueue.showDialog(
                                titleRes = R.string.custom_driver_not_supported,
                                messageRes = R.string.custom_driver_not_supported_description,
                                confirmTextRes = R.string.close,
                                dismissTextRes = null
                            )
                        }
                    }
                )
            }

            item(key = "controls") {
                HomePreference(
                    title = stringResource(R.string.controls),
                    icon = { Icon(painterResource(R.drawable.gamepad), null) },
                    description = stringResource(R.string.controls_description),
                    onClick = { navigateTo("controls") }
                )
            }

            item(key = "share_logs") {
                HomePreference(
                    title = stringResource(R.string.share_log),
                    icon = {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_share),
                            contentDescription = null
                        )
                    },
                    description = stringResource(R.string.share_log_description),
                    onClick = {
                        val file = DocumentFile.fromSingleUri(
                            context, DocumentsContract.buildDocumentUri(
                                AppDataDocumentProvider.AUTHORITY,
                                "${AppDataDocumentProvider.ROOT_ID}/cache/RPCSX${if (RPCSX.lastPlayedGame.isNotEmpty()) "" else ".old"}.log"
                            )
                        )

                        if (file != null && file.exists() && file.length() != 0L) {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                setDataAndType(file.uri, "text/plain")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                putExtra(Intent.EXTRA_STREAM, file.uri)
                            }
                            context.startActivity(
                                Intent.createChooser(
                                    intent,
                                    context.getString(R.string.share_log)
                                )
                            )
                        } else {
                            Toast.makeText(
                                context,
                                R.string.log_not_found,
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                )
            }
        }
    }
}

@Preview
@Composable
private fun SettingsScreenPreview() {
    ComposePreview {
//        SettingsScreen {}
    }
}

@Composable
private fun CacheStorageDialog(
    status: CacheStorageManager.Status?,
    busy: Boolean,
    onDismiss: () -> Unit,
    onSelect: (CacheStorageManager.Location) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Compiled Cache Storage") },
        text = {
            Column {
                Text(
                    "This stores PPU, SPU, and RSX shader cache in the selected app storage. Internal is fastest. SD card is for saving space, and may make cache-heavy boot or shader work slower."
                )
                Spacer(Modifier.height(12.dp))
                if (status == null) {
                    Text("Checking storage locations.")
                } else {
                    status.locations.forEach { location ->
                        val current = location.rootPath == status.activeLocation.rootPath
                        TextButton(
                            enabled = !busy,
                            modifier = Modifier.fillMaxWidth(),
                            onClick = { onSelect(location) }
                        ) {
                            Text(
                                buildString {
                                    append(location.label)
                                    if (current) {
                                        append(" (current)")
                                    }
                                    append(" - ")
                                    append(CacheStorageManager.formatBytes(location.freeBytes))
                                    append(" free")
                                }
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.close))
            }
        }
    )
}
