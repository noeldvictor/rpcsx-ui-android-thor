package net.rpcsx.utils

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.io.RandomAccessFile

class Ps3IsoMetadataReaderTest {
    @Test
    fun paramSfoParserReadsTitleFields() {
        val metadata = Ps3IsoMetadataReader.parseParamSfo(
            buildParamSfo(
                mapOf(
                    "TITLE_ID" to "BLUS12345",
                    "TITLE" to "Example Game"
                )
            )
        )

        assertEquals("BLUS12345", metadata.titleId)
        assertEquals("Example Game", metadata.title)
    }

    @Test
    fun isoReaderFindsPs3MetadataFiles() {
        val sfo = buildParamSfo(mapOf("TITLE_ID" to "NPEB54321", "TITLE" to "Tiny ISO"))
        val icon = byteArrayOf(
            0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3
        )
        val iso = buildPs3Iso(sfo, icon)
        val file = File.createTempFile("tiny-ps3", ".iso")

        try {
            file.writeBytes(iso)
            RandomAccessFile(file, "r").channel.use { channel ->
                assertArrayEquals(
                    sfo,
                    Ps3IsoMetadataReader.readIsoFile(channel, "ps3_game/param.sfo", 4096)
                )
                assertArrayEquals(
                    icon,
                    Ps3IsoMetadataReader.readIsoFile(channel, "PS3_GAME/ICON0.PNG", 4096)
                )
            }
        } finally {
            file.delete()
        }
    }

    private fun buildParamSfo(values: Map<String, String>): ByteArray {
        val entries = values.entries.toList()
        val keyBytes = entries.map { it.key.toByteArray(Charsets.UTF_8) }
        val valueBytes = entries.map { (it.value + "\u0000").toByteArray(Charsets.UTF_8) }
        val headerSize = 20 + entries.size * 16
        val keyTableOffset = headerSize
        val keyTableSize = keyBytes.sumOf { it.size + 1 }
        val dataTableOffset = align4(keyTableOffset + keyTableSize)
        val dataSize = valueBytes.sumOf { align4(it.size) }
        val bytes = ByteArray(dataTableOffset + dataSize)

        bytes[0] = 0
        bytes[1] = 'P'.code.toByte()
        bytes[2] = 'S'.code.toByte()
        bytes[3] = 'F'.code.toByte()
        bytes.putU32Le(8, keyTableOffset)
        bytes.putU32Le(12, dataTableOffset)
        bytes.putU32Le(16, entries.size)

        var keyCursor = 0
        var dataCursor = 0
        entries.forEachIndexed { index, _ ->
            val entryOffset = 20 + index * 16
            val key = keyBytes[index]
            val value = valueBytes[index]
            bytes.putU16Le(entryOffset, keyCursor)
            bytes.putU16Le(entryOffset + 2, 0x0204)
            bytes.putU32Le(entryOffset + 4, value.size)
            bytes.putU32Le(entryOffset + 8, align4(value.size))
            bytes.putU32Le(entryOffset + 12, dataCursor)
            key.copyInto(bytes, keyTableOffset + keyCursor)
            value.copyInto(bytes, dataTableOffset + dataCursor)
            keyCursor += key.size + 1
            dataCursor += align4(value.size)
        }

        return bytes
    }

    private fun buildPs3Iso(paramSfo: ByteArray, icon: ByteArray): ByteArray {
        val sectorSize = 2048
        val bytes = ByteArray(sectorSize * 24)

        val primaryVolumeOffset = sectorSize * 16
        bytes[primaryVolumeOffset] = 1
        "CD001".toByteArray(Charsets.US_ASCII).copyInto(bytes, primaryVolumeOffset + 1)
        bytes[primaryVolumeOffset + 6] = 1
        directoryRecord(byteArrayOf(0), 20, sectorSize, true)
            .copyInto(bytes, primaryVolumeOffset + 156)

        val terminatorOffset = sectorSize * 17
        bytes[terminatorOffset] = 255.toByte()
        "CD001".toByteArray(Charsets.US_ASCII).copyInto(bytes, terminatorOffset + 1)
        bytes[terminatorOffset + 6] = 1

        writeDirectory(
            bytes,
            20,
            listOf(
                directoryRecord(byteArrayOf(0), 20, sectorSize, true),
                directoryRecord(byteArrayOf(1), 20, sectorSize, true),
                directoryRecord("PS3_GAME".toByteArray(Charsets.US_ASCII), 21, sectorSize, true)
            )
        )
        writeDirectory(
            bytes,
            21,
            listOf(
                directoryRecord(byteArrayOf(0), 21, sectorSize, true),
                directoryRecord(byteArrayOf(1), 20, sectorSize, true),
                directoryRecord("PARAM.SFO;1".toByteArray(Charsets.US_ASCII), 22, paramSfo.size, false),
                directoryRecord("ICON0.PNG;1".toByteArray(Charsets.US_ASCII), 23, icon.size, false)
            )
        )

        paramSfo.copyInto(bytes, sectorSize * 22)
        icon.copyInto(bytes, sectorSize * 23)
        return bytes
    }

    private fun writeDirectory(bytes: ByteArray, sector: Int, records: List<ByteArray>) {
        var offset = sector * 2048
        records.forEach { record ->
            record.copyInto(bytes, offset)
            offset += record.size
        }
    }

    private fun directoryRecord(name: ByteArray, extent: Int, size: Int, directory: Boolean): ByteArray {
        val recordSize = align2(33 + name.size)
        val record = ByteArray(recordSize)
        record[0] = recordSize.toByte()
        record.putU32Le(2, extent)
        record.putU32Le(10, size)
        record[25] = if (directory) 2 else 0
        record.putU16Le(28, 1)
        record[32] = name.size.toByte()
        name.copyInto(record, 33)
        return record
    }

    private fun ByteArray.putU16Le(offset: Int, value: Int) {
        this[offset] = (value and 0xff).toByte()
        this[offset + 1] = ((value ushr 8) and 0xff).toByte()
    }

    private fun ByteArray.putU32Le(offset: Int, value: Int) {
        this[offset] = (value and 0xff).toByte()
        this[offset + 1] = ((value ushr 8) and 0xff).toByte()
        this[offset + 2] = ((value ushr 16) and 0xff).toByte()
        this[offset + 3] = ((value ushr 24) and 0xff).toByte()
    }

    private fun align2(value: Int) = if (value % 2 == 0) value else value + 1

    private fun align4(value: Int) = if (value % 4 == 0) value else value + (4 - value % 4)
}
