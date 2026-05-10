package net.rpcsx.utils

import android.net.Uri
import android.util.Log
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.AssetFileDescriptor
import android.content.ActivityNotFoundException
import android.database.Cursor
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import androidx.core.content.edit
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.rpcsx.GameInfo
import net.rpcsx.GameRepository
import net.rpcsx.PrecompilerService
import net.rpcsx.PrecompilerServiceAction
import net.rpcsx.ProgressRepository
import net.rpcsx.R
import net.rpcsx.RPCSX
import net.rpcsx.provider.AppDataDocumentProvider
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.IOException
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

private data class InstallableFolder(
    val uri: Uri, val targetPath: String
)

object FileUtil {
    private const val copyBufferSize = 64 * 1024

    private val nativeInstallerSafeExtensions = setOf("pkg", "edat")
    private val isoExtensions = setOf("iso")
    private val externalIsoMetadataRefreshActive = AtomicBoolean(false)

    fun installPackages(context: Context, rootFolderUri: Uri) {
        thread {
            val workList = ArrayDeque<Uri>()
            workList.add(rootFolderUri)

            val batchFiles = mutableListOf<Uri>()
            val batchDirs = mutableListOf<InstallableFolder>()

            while (workList.isNotEmpty()) {
                val currentFolderUri = workList.removeFirst()

                val paramSfo =
                    uriOpenFile(context, currentFolderUri, "PS3_GAME/PARAM.SFO") ?: uriOpenFile(
                        context, currentFolderUri, "PARAM.SFO"
                    )

                if (paramSfo != null) {
                    val installDir =
                        RPCSX.instance.getDirInstallPath(paramSfo.parcelFileDescriptor.fd)
                    paramSfo.close()

                    if (installDir != null) {
                        val externalPath = documentUriToFilePath(currentFolderUri)
                        if (externalPath != null && File(externalPath).exists()) {
                            RPCSX.instance.collectGameInfo(externalPath, -1L)
                        } else {
                            batchDirs += InstallableFolder(currentFolderUri, installDir)
                        }
                    } else {
                        workList.add(currentFolderUri)
                    }

                    continue
                }

                listFiles(currentFolderUri, context).forEach { item ->
                    if (item.isDirectory) {
                        workList.add(item.uri)
                    } else if (isNativeInstallerSafeFileName(item.filename)) {
                        batchFiles += item.uri
                    } else if (isIsoFileName(item.filename)) {
                        addExternalIsoGame(context, item)
                    } else {
                        Log.i("FileUtil", "Skipping unsupported folder import file: ${item.filename}")
                    }
                }
            }

            if (batchFiles.isNotEmpty()) {
                PrecompilerService.start(
                    context, PrecompilerServiceAction.Install, ArrayList(batchFiles)
                )
            }

            batchDirs.forEach {
                if (GameRepository.find(it.targetPath) != null) {
                    return@forEach
                }

                val progress = ProgressRepository.create(context, context.getString(R.string.installing_dir))
                GameRepository.add(arrayOf(GameInfo("$")), progress)
                copyDirUriToInternalStorage(context, it.uri, it.targetPath, progress)
                RPCSX.instance.collectGameInfo(it.targetPath, -1L)
            }
        }
    }

    fun isNativeInstallerSafeFileName(fileName: String): Boolean {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.US)
        return extension in nativeInstallerSafeExtensions
    }

    fun isIsoFileName(fileName: String): Boolean {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.US)
        return extension in isoExtensions
    }

    fun canUseNativeInstaller(context: Context, uri: Uri): Boolean {
        return displayName(context, uri)?.let { isNativeInstallerSafeFileName(it) } == true
    }

    fun documentUriToFilePath(uri: Uri): String? {
        if (uri.authority != "com.android.externalstorage.documents") {
            return null
        }

        val documentId = runCatching {
            if (isRootTreeUri(uri)) {
                DocumentsContract.getTreeDocumentId(uri)
            } else {
                DocumentsContract.getDocumentId(uri)
            }
        }.getOrNull() ?: return null

        return externalStorageDocumentIdToFilePath(documentId)
    }

    fun externalStorageDocumentIdToFilePath(documentId: String): String? {
        val parts = documentId.split(':', limit = 2)
        if (parts.isEmpty() || parts[0].isBlank()) {
            return null
        }

        val volume = parts[0]
        val relativePath = parts.getOrNull(1).orEmpty().trim('/')
        val root = if (volume.equals("primary", ignoreCase = true)) {
            "/storage/emulated/0"
        } else {
            "/storage/$volume"
        }

        return if (relativePath.isBlank()) {
            root
        } else {
            "$root/$relativePath"
        }
    }

    fun externalStoragePathToDocumentId(path: String): String? {
        val normalized = path.replace('\\', '/').trimEnd('/')
        val primaryRoot = "/storage/emulated/0"
        if (normalized == primaryRoot) {
            return "primary:"
        }
        if (normalized.startsWith("$primaryRoot/")) {
            return "primary:${normalized.removePrefix("$primaryRoot/")}"
        }

        val storageRoot = "/storage/"
        if (!normalized.startsWith(storageRoot)) {
            return null
        }

        val remaining = normalized.removePrefix(storageRoot)
        val volume = remaining.substringBefore('/')
        if (volume.isBlank() || volume == "emulated") {
            return null
        }

        val relativePath = remaining.substringAfter('/', "")
        return if (relativePath.isBlank()) {
            "$volume:"
        } else {
            "$volume:$relativePath"
        }
    }

    fun documentUriForExternalStoragePath(context: Context, path: String): Uri? {
        val documentId = externalStoragePathToDocumentId(path) ?: return null
        val treeUri = context.contentResolver.persistedUriPermissions
            .asSequence()
            .filter { it.isReadPermission }
            .map { it.uri }
            .filter { it.authority == "com.android.externalstorage.documents" }
            .firstOrNull { uri ->
                runCatching {
                    isDocumentIdInsideTree(
                        documentId,
                        DocumentsContract.getTreeDocumentId(uri)
                    )
                }.getOrDefault(false)
            } ?: return null

        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    fun isAppManagedPath(path: String): Boolean {
        val root = RPCSX.rootDirectory.takeIf { it.isNotBlank() } ?: return false
        return isInsideDirectory(File(path), File(root))
    }

    fun refreshExternalIsoMetadata(context: Context) {
        if (!externalIsoMetadataRefreshActive.compareAndSet(false, true)) {
            return
        }

        thread {
            try {
                GameRepository.list()
                    .filter { game -> isIsoFileName(game.info.path) }
                    .filter { game ->
                        game.info.iconPath.value == null ||
                            game.info.titleId.value == null ||
                            game.info.name.value.isNullOrBlank()
                    }
                    .forEach { game ->
                        val path = game.info.path
                        val uri = game.info.sourceUri.value?.let { Uri.parse(it) }
                            ?: documentUriForExternalStoragePath(context, path)
                        val fallbackName = game.info.name.value ?: path.substringAfterLast('/')
                        val metadata = if (uri != null) {
                            Ps3IsoMetadataReader.read(context, uri, path, fallbackName)
                        } else if (File(path).canRead()) {
                            Ps3IsoMetadataReader.readPath(context, path, fallbackName)
                        } else {
                            Ps3IsoMetadata()
                        }

                        if (metadata.hasMetadata) {
                            GameRepository.add(
                                arrayOf(
                                    GameInfo(
                                        path = path,
                                        name = metadata.title ?: game.info.name.value ?: fallbackName.substringBeforeLast('.'),
                                        iconPath = metadata.iconPath ?: game.info.iconPath.value,
                                        gameFlags = game.info.gameFlags.intValue,
                                        titleId = metadata.titleId ?: game.info.titleId.value,
                                        sourceUri = uri?.toString() ?: game.info.sourceUri.value
                                    )
                                ),
                                -1L
                            )
                        }
                    }

                backfillMissingIconsFromKnownGames()
            } finally {
                externalIsoMetadataRefreshActive.set(false)
            }
        }
    }

    private fun addExternalIsoGame(context: Context, item: SimpleDocument) {
        val path = documentUriToFilePath(item.uri)
        if (path == null) {
            Log.w("FileUtil", "Cannot add ISO without direct storage path: ${item.filename}")
            return
        }

        val fallbackName = item.filename.substringBeforeLast('.', item.filename)
        val metadata = Ps3IsoMetadataReader.read(context, item.uri, path, item.filename)

        GameRepository.add(
            arrayOf(
                GameInfo(
                    path = path,
                    name = metadata.title ?: fallbackName,
                    iconPath = metadata.iconPath,
                    titleId = metadata.titleId,
                    sourceUri = item.uri.toString()
                )
            ),
            -1L
        )
    }

    private fun isDocumentIdInsideTree(documentId: String, treeDocumentId: String): Boolean {
        val documentParts = documentId.split(':', limit = 2)
        val treeParts = treeDocumentId.split(':', limit = 2)
        if (documentParts.getOrNull(0) != treeParts.getOrNull(0)) {
            return false
        }

        val documentRelativePath = documentParts.getOrNull(1).orEmpty().trim('/')
        val treeRelativePath = treeParts.getOrNull(1).orEmpty().trim('/')
        return treeRelativePath.isBlank() ||
            documentRelativePath == treeRelativePath ||
            documentRelativePath.startsWith("$treeRelativePath/")
    }

    private fun backfillMissingIconsFromKnownGames() {
        val games = GameRepository.list().toList()
        val iconsByTitleId = linkedMapOf<String, String>()

        games.forEach { game ->
            val iconPath = game.info.iconPath.value?.takeIf { File(it).exists() } ?: return@forEach
            GameIdentity.titleIdsForGame(game).forEach { titleId ->
                iconsByTitleId.putIfAbsent(titleId, iconPath)
            }
        }

        games.forEach { game ->
            val currentIcon = game.info.iconPath.value
            if (currentIcon != null && File(currentIcon).exists()) {
                return@forEach
            }

            val titleId = GameIdentity.titleIdsForGame(game)
                .firstOrNull { titleId -> iconsByTitleId.containsKey(titleId) }
                ?: return@forEach

            GameRepository.add(
                arrayOf(
                    GameInfo(
                        path = game.info.path,
                        name = game.info.name.value,
                        iconPath = iconsByTitleId[titleId],
                        gameFlags = game.info.gameFlags.intValue,
                        titleId = game.info.titleId.value ?: titleId,
                        sourceUri = game.info.sourceUri.value
                    )
                ),
                -1L
            )
        }
    }

    private fun isInsideDirectory(file: File, directory: File): Boolean {
        return runCatching {
            val filePath = file.canonicalFile.toPath()
            val directoryPath = directory.canonicalFile.toPath()
            filePath.startsWith(directoryPath)
        }.getOrDefault(false)
    }

    private fun displayName(context: Context, uri: Uri): String? {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        return runCatching {
            context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)
                } else {
                    null
                }
            }
        }.getOrNull() ?: uri.lastPathSegment
    }

    fun saveGameFolderUri(prefs: SharedPreferences, uri: Uri) {
        prefs.edit { putString("selected_game_folder", uri.toString()) }
    }

    fun copyDirUriToInternalStorage(
        context: Context, rootFolderUri: Uri, path: String, progressId: Long
    ) {
        val workList = ArrayDeque<Pair<Uri, String>>()
        workList.add(Pair(rootFolderUri, path))
        val fileList = mutableListOf<Pair<Uri, String>>()

        while (workList.isNotEmpty()) {
            val currentFolderUriTarget = workList.removeFirst()
            val currentFolderUri = currentFolderUriTarget.first
            val currentFolderTarget = currentFolderUriTarget.second

            listFiles(currentFolderUri, context).forEach { item ->
                val file = File(currentFolderTarget, item.filename)
                if (item.isDirectory) {
                    file.mkdirs()
                    workList.add(Pair(item.uri, file.path))
                } else {
                    fileList.add(Pair(item.uri, file.path))
                }
            }
        }

        ProgressRepository.onProgressEvent(progressId, 0, fileList.size.toLong())
        var processed = 0L

        fileList.forEach { file ->
            saveFile(context, file.first, file.second)
            ProgressRepository.onProgressEvent(progressId, ++processed, fileList.size.toLong())
        }
    }

    fun saveFile(context: Context, source: Uri, target: String) {
        try {
            val targetFile = File(target)
            targetFile.parentFile?.mkdirs()
            val inputStream = context.contentResolver.openInputStream(source)
                ?: throw IOException("Cannot open input stream for $source")

            inputStream.use { input ->
                targetFile.outputStream().use { output ->
                    input.copyTo(output, copyBufferSize)
                }
            }
        } catch (e: IOException) {
            e.printStackTrace()
        }
    }

    fun uriChild(context: Context, rootUri: Uri, path: String): SimpleDocument? {
        val pathDirectories = path.split("/").toMutableList()
        var uri = rootUri
        val filename = pathDirectories.removeAt(pathDirectories.size - 1)

        while (pathDirectories.isNotEmpty()) {
            val dirName = pathDirectories.removeAt(0)
            val entry = listFiles(uri, context).find { it.filename == dirName }
            if (entry == null || !entry.isDirectory) {
                return null
            }

            uri = entry.uri
        }

        return listFiles(uri, context).find { it.filename == filename }
    }

    fun uriOpenFile(context: Context, rootUri: Uri, path: String): AssetFileDescriptor? {
        val entry = uriChild(context, rootUri, path)

        if (entry == null || entry.isDirectory) {
            return null
        }

        return context.contentResolver.openAssetFileDescriptor(entry.uri, "r")
    }

    fun listFiles(uri: Uri, context: Context): Array<SimpleDocument> {
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        var c: Cursor? = null
        val results: MutableList<SimpleDocument> = ArrayList()
        try {
            val docId = if (isRootTreeUri(uri)) {
                DocumentsContract.getTreeDocumentId(uri)
            } else {
                DocumentsContract.getDocumentId(uri)
            }

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(uri, docId)
            c = context.contentResolver.query(childrenUri, columns, null, null, null)
            while (c!!.moveToNext()) {
                val documentId = c.getString(0)
                val documentName = c.getString(1)
                val documentMimeType = c.getString(2)
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(uri, documentId)
                val document = SimpleDocument(documentName, documentMimeType, documentUri)
                results.add(document)
            }
        } catch (e: Exception) {
            Log.e("FileUtil", "Cannot list file error: " + e.message)
        } finally {
            c?.close()
        }
        return results.toTypedArray<SimpleDocument>()
    }

    fun isRootTreeUri(uri: Uri): Boolean {
        val paths = uri.pathSegments
        return paths.size == 2 && "tree" == paths[0]
    }

    fun deleteCache(ctx: Context, gameId: String, onComplete: (Boolean) -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            val cacheDir = File(ctx.getExternalFilesDir(null)!!, "cache/cache/$gameId")
            val result = !cacheDir.exists() || cacheDir.deleteRecursively()
            withContext(Dispatchers.Main) {
                onComplete(result)
            }
        }
    }

    fun importConfig(ctx: Context, uri: Uri): Boolean {
        return try {
            val docFile = DocumentFile.fromSingleUri(ctx, uri)
            if (docFile == null || (docFile.name?.endsWith(".yml", true) != true)) return false
            val inputStream: InputStream = ctx.contentResolver.openInputStream(uri) ?: return false
            val outputFile: File = ctx.getExternalFilesDir(null)?.resolve("config")?.resolve("config.yml") ?: return false
            val outputStream: OutputStream = outputFile.outputStream()
            inputStream.copyTo(outputStream)
            inputStream.close()
            outputStream.close()
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun exportConfig(ctx: Context, uri: Uri): Boolean {
        return try {
            val inputFile = ctx.getExternalFilesDir(null)?.resolve("config")?.resolve("config.yml") ?: return false
            val inputStream: InputStream = inputFile.inputStream()
            val outputStream: OutputStream = ctx.contentResolver.openOutputStream(uri) ?: return false
            inputStream.copyTo(outputStream)
            inputStream.close()
            outputStream.close()
           true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun launchInternalDir(ctx: Context): Boolean {
        if (!ctx.launchBrowseIntent(Intent.ACTION_VIEW)) {
            if (!ctx.launchBrowseIntent()) {
                if (!ctx.launchBrowseIntent(Intent.ACTION_OPEN_DOCUMENT_TREE)) {
                    return false
                }
            }
        }
        return true
    }

    private fun Context.launchBrowseIntent(
        action: String = "android.provider.action.BROWSE"
    ): Boolean {
        return try {
            val intent = Intent(action).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                data = DocumentsContract.buildRootUri(
                    AppDataDocumentProvider.AUTHORITY, AppDataDocumentProvider.ROOT_ID
                )
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            println("No activity found to handle $action intent")
            false
        }
    } 
}

class SimpleDocument(val filename: String, val mimeType: String, val uri: Uri) {
    val isDirectory: Boolean
        get() = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
}
