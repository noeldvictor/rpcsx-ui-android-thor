package net.rpcsx.utils

import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.serialization.SerializationException
import java.io.File
import java.io.IOException
import java.io.InputStream

private const val GPU_DRIVER_DIRECTORY = "gpu_drivers"
private const val GPU_DRIVER_FILE_REDIRECT_DIR = "gpu/vk_file_redirect"
private const val GPU_DRIVER_INSTALL_TEMP_DIR = "driver_temp"
private const val GPU_DRIVER_META_FILE = "meta.json"
private const val TAG = "GPUDriverHelper"

object GpuDriverHelper {
    fun getInstalledDrivers(context: Context): Map<File, GpuDriverMetadata> {
        val gpuDriverDir = getDriversDirectory(context)

        // A map between the driver location and its metadata
        val driverMap = mutableMapOf<File, GpuDriverMetadata>()
        driverMap[File("/system/vendor")] = getSystemDriverMetadata()

        gpuDriverDir.listFiles()?.forEach { entry ->
            // Delete any files that aren't a directory
            if (!entry.isDirectory) {
                entry.delete()
                return@forEach
            }

            val metadataFile = File(entry.canonicalPath, GPU_DRIVER_META_FILE)
            if (!metadataFile.exists()) {
                // This used to call entry.delete(), which silently fails on a
                // non-empty directory, so such a driver was invisible in the list
                // yet still on disk and still loadable if it was the selected one.
                //
                // Deliberately still not deleting it. Making that delete work
                // would destroy a driver the user may be running right now, and
                // an unreadable meta.json is not good enough evidence to throw
                // away a payload the loader can still use. Skip it and say so.
                Log.w(TAG, "Driver directory ${entry.name} has no $GPU_DRIVER_META_FILE; " +
                        "not listing it, and leaving it alone in case it is the driver in use")
                return@forEach
            }

            try {
                driverMap[entry] = GpuDriverMetadata.deserialize(metadataFile)
            } catch (e: SerializationException) {
                Log.w(
                    TAG,
                    "Failed to load gpu driver metadata for ${entry.name}, skipping\n${e.message}"
                )
            }
        }

        return driverMap
    }

    private fun getSystemDriverMetadata(): GpuDriverMetadata {
        return GpuDriverMetadata(
            name = "Default",
            author = "",
            packageVersion = "",
            vendor = "",
            driverVersion = "",
            minApi = 0,
            description = "The driver provided by your device system",
            libraryName = ""
        )
    }

    fun installDriver(context: Context, stream: InputStream): GpuDriverInstallResult {
        val installTempDir =
            File(context.cacheDir.canonicalPath, GPU_DRIVER_INSTALL_TEMP_DIR).apply {
                deleteRecursively()
            }

        try {
            ZipUtil.unzip(stream, installTempDir)
        } catch (e: Exception) {
            e.printStackTrace()
            installTempDir.deleteRecursively()
            return GpuDriverInstallResult.InvalidArchive
        }

        return installUnpackedDriver(context, installTempDir)
    }

    fun installDriver(context: Context, file: File): GpuDriverInstallResult {
        val installTempDir =
            File(context.cacheDir.canonicalPath, GPU_DRIVER_INSTALL_TEMP_DIR).apply {
                deleteRecursively()
            }

        try {
            ZipUtil.unzip(file, installTempDir)
        } catch (e: Exception) {
            e.printStackTrace()
            installTempDir.deleteRecursively()
            return GpuDriverInstallResult.InvalidArchive
        }

        return installUnpackedDriver(context, installTempDir)
    }

    private fun installUnpackedDriver(context: Context, unpackDirRaw: File): GpuDriverInstallResult {
        val cleanup = {
            unpackDirRaw.deleteRecursively()
        }

        // AdrenoTools packages are supposed to hold meta.json at the archive
        // root, and plenty do not: they wrap everything in a single folder named
        // after the release, e.g. Turnip_v26.0.0_R8/meta.json. Those used to fail
        // as MissingMetadata, which looked identical to a corrupt download and
        // left nothing in the driver list. Descend one level when the root is a
        // single directory that does carry the metadata.
        val unpackDir = run {
            if (File(unpackDirRaw, GPU_DRIVER_META_FILE).isFile) return@run unpackDirRaw

            val entries = unpackDirRaw.listFiles().orEmpty()
            val nested = entries.singleOrNull { it.isDirectory }

            if (nested != null && File(nested, GPU_DRIVER_META_FILE).isFile) {
                Log.i(TAG, "Driver metadata found one level down, in ${nested.name}")
                nested
            } else {
                unpackDirRaw
            }
        }

        // Check that the metadata file exists
        val metadataFile = File(unpackDir, GPU_DRIVER_META_FILE)
        if (!metadataFile.isFile) {
            cleanup()
            return GpuDriverInstallResult.MissingMetadata
        }

        // Check that the driver metadata is valid
        val driverMetadata = try {
            GpuDriverMetadata.deserialize(metadataFile)
        } catch (_: SerializationException) {
            cleanup()
            return GpuDriverInstallResult.InvalidMetadata
        }

        // Check that the device satisfies the driver's minimum Android version requirements
        if (Build.VERSION.SDK_INT < driverMetadata.minApi) {
            cleanup()
            return GpuDriverInstallResult.UnsupportedAndroidVersion
        }

        // Check that the driver is not already installed
        val installedDrivers = getInstalledDrivers(context)
        val finalInstallDir = File(getDriversDirectory(context), driverMetadata.label)
        if (installedDrivers[finalInstallDir] != null) {
            cleanup()
            return GpuDriverInstallResult.AlreadyInstalled
        }

        // Move the driver files to the final location
        if (!unpackDir.renameTo(finalInstallDir)) {
            cleanup()
            throw IOException("Failed to create directory ${finalInstallDir.name}")
        }

        // When the metadata was one level down, the wrapper directory is still
        // sitting in the cache. Harmless but it accumulates per install.
        if (unpackDir != unpackDirRaw) {
            unpackDirRaw.deleteRecursively()
        }

        return GpuDriverInstallResult.Success
    }

    fun getLibraryName(context: Context, driverLabel: String): String {
        val driverDir = File(getDriversDirectory(context), driverLabel)
        val metadataFile = File(driverDir, GPU_DRIVER_META_FILE)
        return try {
            GpuDriverMetadata.deserialize(metadataFile).libraryName
        } catch (_: SerializationException) {
            Log.w(
                TAG,
                "Failed to load library name for driver ${driverLabel}, driver may not exist or have invalid metadata"
            )
            ""
        }
    }

    fun ensureFileRedirectDir(context: Context) {
        File(context.getExternalFilesDir(null), GPU_DRIVER_FILE_REDIRECT_DIR).apply {
            if (!isDirectory) {
                delete()
                mkdirs()
            }
        }
    }

    private fun getDriversDirectory(context: Context) =
        File(context.filesDir.canonicalPath, GPU_DRIVER_DIRECTORY).apply {
            // Create the directory if it doesn't exist
            if (!isDirectory) {
                delete()
                mkdirs()
            }
        }

    fun resolveInstallResultToString(result: GpuDriverInstallResult) = when (result) {
        GpuDriverInstallResult.Success -> "Successfully installed GPU driver"
        GpuDriverInstallResult.InvalidArchive -> "Invalid GPU driver archive"
        GpuDriverInstallResult.MissingMetadata -> "Selected driver's metadata is missing"
        GpuDriverInstallResult.InvalidMetadata -> "Selected driver's metadata is invalid"
        GpuDriverInstallResult.UnsupportedAndroidVersion -> "Your android version doesn't support selected driver"
        GpuDriverInstallResult.AlreadyInstalled -> "Selected driver is already installed"
    }
}

enum class GpuDriverInstallResult {
    Success, InvalidArchive, MissingMetadata, InvalidMetadata, UnsupportedAndroidVersion, AlreadyInstalled,
}
