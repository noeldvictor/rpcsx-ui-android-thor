package net.rpcsx.utils

import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.security.MessageDigest
import java.util.Locale
import kotlin.math.min

data class Ps3IsoMetadata(
    val titleId: String? = null,
    val title: String? = null,
    val iconPath: String? = null
) {
    val hasMetadata: Boolean
        get() = titleId != null || title != null || iconPath != null
}

object Ps3IsoMetadataReader {
    private const val sectorSize = 2048
    private const val maxParamSfoBytes = 1024 * 1024
    private const val maxIconBytes = 8 * 1024 * 1024
    private const val maxDirectoryBytes = 16L * 1024L * 1024L

    fun read(context: Context, uri: Uri, isoPath: String, fallbackName: String): Ps3IsoMetadata {
        return runCatching {
            context.contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).channel.use { channel ->
                    readFromChannel(context, channel, isoPath, fallbackName)
                }
            }
        }.onFailure {
            Log.w("Ps3IsoMetadata", "Unable to read ISO metadata from $fallbackName", it)
        }.getOrNull() ?: Ps3IsoMetadata()
    }

    fun readPath(context: Context, isoPath: String, fallbackName: String): Ps3IsoMetadata {
        return runCatching {
            FileInputStream(isoPath).channel.use { channel ->
                readFromChannel(context, channel, isoPath, fallbackName)
            }
        }.onFailure {
            Log.w("Ps3IsoMetadata", "Unable to read ISO metadata from $isoPath", it)
        }.getOrNull() ?: Ps3IsoMetadata()
    }

    private fun readFromChannel(
        context: Context,
        channel: FileChannel,
        isoPath: String,
        fallbackName: String
    ): Ps3IsoMetadata {
        val paramSfo = readIsoFile(channel, "PS3_GAME/PARAM.SFO", maxParamSfoBytes)
        val sfo = paramSfo?.let { parseParamSfo(it) } ?: SfoMetadata()
        val titleId = sfo.titleId ?: GameIdentity.titleIdsFromText(fallbackName).firstOrNull()
        val title = sfo.title?.takeIf { it.isNotBlank() }
        val iconPath = extractIcon(context, channel, isoPath, titleId)

        return Ps3IsoMetadata(
            titleId = titleId,
            title = title,
            iconPath = iconPath
        )
    }

    private fun extractIcon(
        context: Context,
        channel: FileChannel,
        isoPath: String,
        titleId: String?
    ): String? {
        val iconBytes = readIsoFile(channel, "PS3_GAME/ICON0.PNG", maxIconBytes) ?: return null
        if (!iconBytes.isPng()) {
            return null
        }

        val iconDir = File(context.getExternalFilesDir(null), "cache/iso-icons")
        if (!iconDir.exists() && !iconDir.mkdirs()) {
            return null
        }

        val safeTitleId = titleId?.replace(Regex("[^A-Za-z0-9_-]"), "")
            ?.takeIf { it.isNotBlank() }
        val iconName = listOfNotNull(safeTitleId, stableHash(isoPath)).joinToString("_") + ".png"
        val iconFile = File(iconDir, iconName)
        if (!iconFile.exists() || iconFile.length() != iconBytes.size.toLong()) {
            iconFile.writeBytes(iconBytes)
        }

        return iconFile.absolutePath
    }

    internal fun readIsoFile(channel: FileChannel, path: String, maxBytes: Int): ByteArray? {
        return IsoImage(channel).readFile(path, maxBytes)
    }

    internal fun parseParamSfo(bytes: ByteArray): SfoMetadata {
        if (bytes.size < 20 || bytes[0] != 0.toByte() || bytes[1] != 'P'.code.toByte() ||
            bytes[2] != 'S'.code.toByte() || bytes[3] != 'F'.code.toByte()
        ) {
            return SfoMetadata()
        }

        val keyTableOffset = bytes.u32Le(8).toInt()
        val dataTableOffset = bytes.u32Le(12).toInt()
        val entryCount = bytes.u32Le(16).toInt()
        var titleId: String? = null
        var title: String? = null

        repeat(entryCount) { index ->
            val entryOffset = 20 + index * 16
            if (entryOffset + 16 > bytes.size) {
                return@repeat
            }

            val keyOffset = bytes.u16Le(entryOffset)
            val dataLength = bytes.u32Le(entryOffset + 4).toInt()
            val dataOffset = bytes.u32Le(entryOffset + 12).toInt()
            val key = bytes.cString(keyTableOffset + keyOffset)
            val valueOffset = dataTableOffset + dataOffset
            if (key.isBlank() || valueOffset < 0 || valueOffset >= bytes.size || dataLength <= 0) {
                return@repeat
            }

            val valueLength = min(dataLength, bytes.size - valueOffset)
            val value = bytes.copyOfRange(valueOffset, valueOffset + valueLength)
                .toString(Charsets.UTF_8)
                .trim('\u0000', ' ', '\n', '\r', '\t')
                .takeIf { it.isNotBlank() }

            when (key.uppercase(Locale.US)) {
                "TITLE_ID" -> titleId = value
                "TITLE" -> title = value
            }
        }

        return SfoMetadata(titleId = titleId, title = title)
    }

    private class IsoImage(private val channel: FileChannel) {
        private val root: IsoEntry? by lazy { readRootEntry() }

        fun readFile(path: String, maxBytes: Int): ByteArray? {
            val entry = findEntry(path) ?: return null
            if (entry.isDirectory || entry.size <= 0 || entry.size > maxBytes) {
                return null
            }

            return readFully(entry.extent * sectorSize, entry.size.toInt())
        }

        private fun findEntry(path: String): IsoEntry? {
            var current = root ?: return null
            val parts = path.trim('/').split('/').filter { it.isNotBlank() }
            for (part in parts) {
                if (!current.isDirectory) {
                    return null
                }
                current = listDirectory(current).firstOrNull {
                    it.name.equals(part, ignoreCase = true)
                } ?: return null
            }
            return current
        }

        private fun readRootEntry(): IsoEntry? {
            for (sector in 16 until 256) {
                val descriptor = readFully(sector.toLong() * sectorSize, sectorSize) ?: return null
                val identifier = descriptor.copyOfRange(1, 6).toString(Charsets.US_ASCII)
                if (identifier != "CD001") {
                    continue
                }

                when (descriptor[0].toInt() and 0xff) {
                    1 -> return parseDirectoryRecord(descriptor, 156)
                    255 -> return null
                }
            }

            return null
        }

        private fun listDirectory(directory: IsoEntry): List<IsoEntry> {
            if (!directory.isDirectory) {
                return emptyList()
            }

            val entries = mutableListOf<IsoEntry>()
            val bytesToRead = min(directory.size, maxDirectoryBytes)
            var sector = 0L
            while (sector * sectorSize < bytesToRead) {
                val data = readFully((directory.extent + sector) * sectorSize, sectorSize) ?: break
                var offset = 0
                while (offset < sectorSize) {
                    val recordLength = data[offset].toInt() and 0xff
                    if (recordLength == 0) {
                        break
                    }
                    if (offset + recordLength > sectorSize) {
                        break
                    }

                    parseDirectoryRecord(data, offset)?.let {
                        if (it.name != "." && it.name != "..") {
                            entries += it
                        }
                    }
                    offset += recordLength
                }
                sector++
            }
            return entries
        }

        private fun parseDirectoryRecord(data: ByteArray, offset: Int): IsoEntry? {
            if (offset < 0 || offset + 34 > data.size) {
                return null
            }

            val recordLength = data[offset].toInt() and 0xff
            if (recordLength < 34 || offset + recordLength > data.size) {
                return null
            }

            val extent = data.u32Le(offset + 2)
            val size = data.u32Le(offset + 10)
            val flags = data[offset + 25].toInt() and 0xff
            val nameLength = data[offset + 32].toInt() and 0xff
            if (offset + 33 + nameLength > data.size) {
                return null
            }

            val rawName = data.copyOfRange(offset + 33, offset + 33 + nameLength)
            val name = when {
                rawName.size == 1 && rawName[0] == 0.toByte() -> "."
                rawName.size == 1 && rawName[0] == 1.toByte() -> ".."
                else -> rawName.toString(Charsets.US_ASCII)
                    .substringBefore(';')
                    .trimEnd('.')
            }

            return IsoEntry(
                name = name,
                extent = extent,
                size = size,
                isDirectory = (flags and 0x02) != 0
            )
        }

        private fun readFully(position: Long, size: Int): ByteArray? {
            val data = ByteArray(size)
            val buffer = ByteBuffer.wrap(data)
            var currentPosition = position
            while (buffer.hasRemaining()) {
                val read = channel.read(buffer, currentPosition)
                if (read <= 0) {
                    return null
                }
                currentPosition += read
            }
            return data
        }
    }

    private data class IsoEntry(
        val name: String,
        val extent: Long,
        val size: Long,
        val isDirectory: Boolean
    )

    private fun ByteArray.isPng(): Boolean {
        val signature = byteArrayOf(
            0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a
        )
        return size >= signature.size && signature.indices.all { this[it] == signature[it] }
    }

    private fun ByteArray.u16Le(offset: Int): Int {
        if (offset < 0 || offset + 2 > size) {
            return 0
        }
        return (this[offset].toInt() and 0xff) or
            ((this[offset + 1].toInt() and 0xff) shl 8)
    }

    private fun ByteArray.u32Le(offset: Int): Long {
        if (offset < 0 || offset + 4 > size) {
            return 0
        }
        return (this[offset].toLong() and 0xff) or
            ((this[offset + 1].toLong() and 0xff) shl 8) or
            ((this[offset + 2].toLong() and 0xff) shl 16) or
            ((this[offset + 3].toLong() and 0xff) shl 24)
    }

    private fun ByteArray.cString(offset: Int): String {
        if (offset < 0 || offset >= size) {
            return ""
        }
        var end = offset
        while (end < size && this[end] != 0.toByte()) {
            end++
        }
        return copyOfRange(offset, end).toString(Charsets.UTF_8)
    }

    private fun stableHash(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.take(8).joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}

data class SfoMetadata(
    val titleId: String? = null,
    val title: String? = null
)
