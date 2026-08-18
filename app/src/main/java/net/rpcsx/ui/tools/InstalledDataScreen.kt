package net.rpcsx.ui.tools

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import net.rpcsx.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.rpcsx.InstalledDataRepository
import net.rpcsx.dialogs.AlertDialogQueue

/**
 * What each title has written to the emulator's virtual hard disk, and a way to
 * remove it.
 *
 * This is not the game library. A disc game appears here only if it has written
 * something to `dev_hdd0/game/<TITLEID>`, which is what Unreal Engine 3 titles do
 * on first boot when they cache their cooked assets. Deleting the library entry
 * for such a game does not remove any of this, which is why the screen exists.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InstalledDataScreen(navigateBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var entries by remember { mutableStateOf<List<InstalledDataRepository.Entry>?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    suspend fun reload() {
        entries = null
        entries = withContext(Dispatchers.IO) { InstalledDataRepository.list() }
    }

    LaunchedEffect(Unit) { reload() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Installed game data") },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(
                            painter = painterResource(id = R.drawable.ic_keyboard_arrow_left),
                            contentDescription = "Back"
                        )
                    }
                }
            )
        }
    ) { padding ->
        val list = entries

        Column(Modifier.padding(padding).fillMaxSize()) {
            if (list == null) {
                // Measuring walks the whole tree, and a UE3 install is tens of
                // thousands of files, so say we are working rather than showing an
                // empty list that looks like "nothing installed".
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(12.dp))
                    Text("Measuring installed data...", style = MaterialTheme.typography.bodySmall)
                }
                return@Column
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(horizontal = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "This is data titles write to the emulator's virtual hard disk, under " +
                            "dev_hdd0/game. Unreal Engine 3 games cache their assets here on first " +
                            "boot, and deleting the game from the library does NOT remove it.",
                        style = MaterialTheme.typography.bodySmall
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        "Saves are not stored here, so removing this cannot delete a save. It can " +
                            "mean a long reinstall the next time the game boots.",
                        style = MaterialTheme.typography.bodySmall
                    )
                }

                message?.let { text ->
                    item { Text(text, style = MaterialTheme.typography.bodySmall) }
                }

                if (list.isEmpty()) {
                    item {
                        Card(Modifier.fillMaxWidth()) {
                            Text(
                                "No title has written to dev_hdd0/game yet.",
                                modifier = Modifier.padding(12.dp),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }

                val titles = list.filter { it.isTitle }
                val other = list.filterNot { it.isTitle }

                if (titles.isNotEmpty()) {
                    item {
                        val total = titles.sumOf { it.sizeBytes }
                        Text(
                            "${titles.size} title(s), ${"%.2f".format(total.toDouble() / (1L shl 30))} GB total",
                            style = MaterialTheme.typography.titleSmall
                        )
                    }
                }

                items(titles, key = { it.titleId }) { entry ->
                    Card(Modifier.fillMaxWidth()) {
                        Row(
                            Modifier.padding(12.dp).fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(entry.titleId, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    "${entry.sizeLabel}  ${entry.fileCount} files",
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    entry.dir.absolutePath,
                                    style = MaterialTheme.typography.bodySmall,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            OutlinedButton(onClick = {
                                AlertDialogQueue.showDialog(
                                    title = "Delete installed data?",
                                    message = "This removes ${entry.sizeLabel} for ${entry.titleId} " +
                                        "from dev_hdd0/game. Saves are not affected. The game may " +
                                        "need to reinstall its data the next time it boots.",
                                    confirmText = "Delete",
                                    dismissText = "Cancel",
                                    onConfirm = {
                                        scope.launch {
                                            val result = withContext(Dispatchers.IO) {
                                                InstalledDataRepository.delete(entry.titleId)
                                            }
                                            message = result.fold(
                                                onSuccess = { "Removed ${entry.titleId}." },
                                                onFailure = { "Failed: ${it.message}" }
                                            )
                                            reload()
                                        }
                                    }
                                )
                            }) { Text("Delete") }
                        }
                    }
                }

                // Everything under dev_hdd0/game that is not a title: emulator
                // bookkeeping such as $locks, and leftovers like TEST12345. Shown so
                // the sizes add up and nothing is hidden, but with no Delete button,
                // because deleting bookkeeping is not a thing a user should be invited
                // to do from a screen about game data.
                if (other.isNotEmpty()) {
                    item {
                        Spacer(Modifier.height(4.dp))
                        Text("Other data", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Not game installs. Emulator bookkeeping and leftovers, listed so the " +
                                "sizes account for everything in the folder.",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }

                    items(other, key = { it.titleId }) { entry ->
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text(entry.titleId, style = MaterialTheme.typography.bodyMedium)
                                Text(
                                    "${entry.sizeLabel}  ${entry.fileCount} files",
                                    style = MaterialTheme.typography.bodySmall
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
