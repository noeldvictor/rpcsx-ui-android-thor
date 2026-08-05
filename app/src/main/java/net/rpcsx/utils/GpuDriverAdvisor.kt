package net.rpcsx.utils

import android.os.Build
import net.rpcsx.performance.ThorPerformanceProfile

/**
 * Judges a GPU driver package against the device actually running the app.
 *
 * The driver list previously showed the same paragraph of advice next to every
 * entry, so a package built for a different Adreno generation looked exactly
 * like one built for this device. Installing the wrong one typically fails at
 * boot or corrupts rendering, and the only clue was in the package name.
 *
 * AdrenoTools metadata carries no field naming the target GPU, so the family
 * has to be recovered from the package name and description. That is a
 * heuristic, and it is reported as such: an unrecognised package is never
 * presented as verified, only as unknown.
 */
object GpuDriverAdvisor {

    enum class Verdict {
        /** Known not to work here. Installing is very likely to break rendering. */
        INCOMPATIBLE,

        /** Probably wrong for this device, or bleeding edge. Keep a fallback. */
        RISKY,

        /** Targets this GPU family and satisfies the API requirement. */
        COMPATIBLE,

        /** Nothing in the package identifies a target. Cannot judge it. */
        UNKNOWN
    }

    data class Assessment(
        val verdict: Verdict,
        /** One short line for the list row. */
        val summary: String,
        /** Concrete observations behind the verdict. */
        val reasons: List<String>,
        /** Mesa/Turnip version if one could be recovered, for display only. */
        val driverVersion: String? = null
    )

    /** Adreno generation this device needs, e.g. "a7xx" on Thor's Adreno 740. */
    data class DeviceTarget(
        val family: String?,
        val model: String?,
        val sdkInt: Int,
        val isThor: Boolean
    )

    private val ADRENO_MODEL_RE = Regex("""adreno\s*\(?tm\)?\s*(\d{3})""", RegexOption.IGNORE_CASE)
    private val FAMILY_RE = Regex("""\ba([678])xx\b""", RegexOption.IGNORE_CASE)
    private val GEN_RE = Regex("""\bgen\s*([0-9])\b""", RegexOption.IGNORE_CASE)
    private val MESA_RE = Regex("""\b(2[0-9]\.[0-9]+(?:\.[0-9]+)?)\b""")

    /**
     * Thor is Snapdragon 8 Gen 2 / Adreno 740, which is the a7xx family. Detected
     * by board rather than by querying Vulkan, so this stays cheap and works
     * before any surface exists.
     */
    fun deviceTarget(): DeviceTarget {
        val isThor = ThorPerformanceProfile.isThorTarget()
        return if (isThor) {
            DeviceTarget(family = "a7xx", model = "Adreno 740", sdkInt = Build.VERSION.SDK_INT, isThor = true)
        } else {
            DeviceTarget(family = null, model = null, sdkInt = Build.VERSION.SDK_INT, isThor = false)
        }
    }

    /** Families a package claims to target, from its name and description. */
    private fun claimedFamilies(text: String): Set<String> {
        val out = mutableSetOf<String>()
        FAMILY_RE.findAll(text).forEach { out += "a${it.groupValues[1]}xx" }

        // "Adreno 740" style model numbers imply their family.
        ADRENO_MODEL_RE.findAll(text).forEach {
            it.groupValues[1].firstOrNull()?.let { d -> out += "a${d}xx" }
        }

        // Qualcomm "Gen N" marketing maps onto Adreno generations for the parts
        // this app cares about. Gen 1/2 are a7xx, Gen 3 and later are a8xx.
        GEN_RE.findAll(text).forEach {
            when (it.groupValues[1].toIntOrNull()) {
                1, 2 -> out += "a7xx"
                3, 4, 5 -> out += "a8xx"
            }
        }
        return out
    }

    fun assess(metadata: GpuDriverMetadata): Assessment = assess(
        name = metadata.name,
        description = metadata.description,
        vendor = metadata.vendor,
        driverVersion = metadata.driverVersion,
        minApi = metadata.minApi
    )

    /**
     * Also usable before download, from a release asset name alone, where only
     * [name] is known.
     */
    fun assess(
        name: String,
        description: String = "",
        vendor: String = "",
        driverVersion: String = "",
        minApi: Int = 0
    ): Assessment {
        val device = deviceTarget()
        val haystack = listOf(name, description, vendor).joinToString(" ")
        val reasons = mutableListOf<String>()

        val mesa = MESA_RE.find(driverVersion)?.value
            ?: MESA_RE.find(name)?.value

        // API level is a hard gate: the loader will refuse the library outright.
        if (minApi > 0 && minApi > device.sdkInt) {
            return Assessment(
                verdict = Verdict.INCOMPATIBLE,
                summary = "Needs Android API $minApi, this device is API ${device.sdkInt}",
                reasons = listOf("The package declares minApi $minApi. This device runs API ${device.sdkInt}, so the driver cannot load."),
                driverVersion = mesa
            )
        }

        if (!device.isThor || device.family == null) {
            return Assessment(
                verdict = Verdict.UNKNOWN,
                summary = "Unrecognised device, cannot check GPU compatibility",
                reasons = listOf("Driver checks are tuned for the AYN Thor (Adreno 740). This device was not recognised, so only the API level was verified."),
                driverVersion = mesa
            )
        }

        val claimed = claimedFamilies(haystack)

        // Samsung OneUI packages carry vendor blob assumptions that do not hold here.
        val oneUi = Regex("""one\s*ui|oneui""", RegexOption.IGNORE_CASE).containsMatchIn(haystack)
        if (oneUi) {
            reasons += "Built for Samsung OneUI, which expects vendor libraries this device does not ship."
        }

        return when {
            claimed.isEmpty() -> Assessment(
                verdict = if (oneUi) Verdict.RISKY else Verdict.UNKNOWN,
                summary = if (oneUi) "Likely wrong: OneUI build" else "No target GPU named in the package",
                reasons = reasons + "Nothing in the name or description identifies an Adreno family, so it cannot be matched against ${device.model}. Keep the default driver ready.",
                driverVersion = mesa
            )

            device.family in claimed && claimed.size == 1 && !oneUi -> Assessment(
                verdict = Verdict.COMPATIBLE,
                summary = "Targets ${device.family} — matches ${device.model}",
                reasons = reasons + "Package targets ${claimed.joinToString()}, which covers this device's ${device.model}.",
                driverVersion = mesa
            )

            device.family in claimed -> Assessment(
                verdict = if (oneUi) Verdict.RISKY else Verdict.COMPATIBLE,
                summary = "Covers ${device.family} (also targets ${(claimed - device.family).joinToString()})",
                reasons = reasons + "Package targets ${claimed.joinToString()}. It includes this device's ${device.family}, but is not built for it exclusively.",
                driverVersion = mesa
            )

            else -> Assessment(
                verdict = Verdict.INCOMPATIBLE,
                summary = "Built for ${claimed.joinToString()}, this device is ${device.family}",
                reasons = reasons + "Package targets ${claimed.joinToString()} and this device is ${device.model} (${device.family}). Drivers for another Adreno generation usually fail to boot or render incorrectly.",
                driverVersion = mesa
            )
        }
    }

    /** Short label for a list row. */
    fun badge(verdict: Verdict): String = when (verdict) {
        Verdict.COMPATIBLE -> "Recommended"
        Verdict.RISKY -> "Risky"
        Verdict.INCOMPATIBLE -> "Not for this device"
        Verdict.UNKNOWN -> "Unverified"
    }
}
