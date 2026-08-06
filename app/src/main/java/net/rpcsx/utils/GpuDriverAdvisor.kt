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

    // Not \b before the digits. Real asset names look like "Turnip_v26.0.0_R8",
    // and 'v' is a word character, so \b never matches there and every genuine
    // package read as having no version at all. Bound on digits instead.
    private val MESA_RE = Regex("""(?<![0-9.])(2[0-9]\.[0-9]+(?:\.[0-9]+)?)(?![0-9])""")

    /**
     * Underscores are word characters, so "turnip_a8xx" has no \b before "a8xx"
     * and the family match silently failed on exactly the packages it exists to
     * catch. Separators become spaces before matching; dots are kept so version
     * numbers survive.
     */
    private fun normalize(text: String) = text.replace(Regex("""[^A-Za-z0-9.]+"""), " ")
    private val TURNIP_RE = Regex("""turnip|freedreno|mesa""", RegexOption.IGNORE_CASE)

    /**
     * Mesa release from which a7xx (Adreno 730/740) support is dependable.
     * a7xx landed earlier than this, but earlier builds are patchy enough that
     * recommending them would be misleading.
     */
    const val A7XX_MESA_MIN = "24.0"

    private fun isTurnip(text: String) = TURNIP_RE.containsMatchIn(text)

    /** Compares dotted Mesa versions numerically, not lexically: 24.0 > 9.9, 25.1 > 24.3. */
    private fun mesaAtLeast(version: String?, minimum: String): Boolean {
        if (version == null) return false
        val a = version.split('.').mapNotNull { it.toIntOrNull() }
        val b = minimum.split('.').mapNotNull { it.toIntOrNull() }
        if (a.isEmpty() || b.isEmpty()) return false
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return true
    }

    /**
     * Parses the newline-separated key=value block returned by
     * RPCSX.queryDriverInfo. Returns null when the package could not be loaded,
     * which is itself the useful answer: the driver does not work here.
     */
    fun parseLiveDriver(raw: String): LiveDriver? {
        if (raw.isBlank()) return null
        val fields = raw.lineSequence()
            .mapNotNull { line ->
                val i = line.indexOf('=')
                if (i <= 0) null else line.substring(0, i) to line.substring(i + 1)
            }
            .toMap()

        val device = fields["device"].orEmpty()
        if (device.isBlank()) return null

        return LiveDriver(
            deviceName = device,
            driverName = fields["driverName"].orEmpty(),
            driverInfo = fields["driverInfo"].orEmpty(),
            apiVersion = fields["api"].orEmpty()
        )
    }

    /** What a driver reports about itself once actually loaded. */
    data class LiveDriver(
        val deviceName: String,
        val driverName: String,
        val driverInfo: String,
        val apiVersion: String
    ) {
        /** One line for the UI, e.g. "Adreno (TM) 740 — turnip Mesa 25.0.2 (Vulkan 1.3.274)". */
        fun summary(): String {
            val driver = listOf(driverName, driverInfo)
                .filter { it.isNotBlank() }
                .joinToString(" ")
            return buildString {
                append(deviceName)
                if (driver.isNotBlank()) append(" — ").append(driver)
                if (apiVersion.isNotBlank()) append(" (Vulkan ").append(apiVersion).append(")")
            }
        }
    }

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
        val haystack = normalize(listOf(name, description, vendor).joinToString(" "))
        val reasons = mutableListOf<String>()

        val mesa = MESA_RE.find(normalize(driverVersion))?.value
            ?: MESA_RE.find(haystack)?.value

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
            // Most real Turnip releases never name a family, because Turnip is
            // one Mesa driver covering many Adreno generations. Judging those
            // "Unverified" made almost every genuine package look unjudged,
            // which is worse than no advice at all. What actually decides it is
            // whether the Mesa build is new enough to support a7xx.
            claimed.isEmpty() && isTurnip(haystack) && mesaAtLeast(mesa, A7XX_MESA_MIN) -> Assessment(
                verdict = if (oneUi) Verdict.RISKY else Verdict.COMPATIBLE,
                summary = if (oneUi) "Mesa $mesa, but a OneUI build" else "Turnip Mesa $mesa — supports ${device.family}",
                reasons = reasons + "Turnip is a single Mesa driver covering several Adreno generations, so it does not name one. Mesa $mesa is at or past $A7XX_MESA_MIN, which is where a7xx support (${device.model}) is usable.",
                driverVersion = mesa
            )

            claimed.isEmpty() && isTurnip(haystack) && mesa != null -> Assessment(
                verdict = Verdict.RISKY,
                summary = "Turnip Mesa $mesa — older than $A7XX_MESA_MIN",
                reasons = reasons + "Mesa $mesa predates dependable a7xx support, so ${device.model} may render incorrectly or fail to boot. Keep the default driver ready.",
                driverVersion = mesa
            )

            claimed.isEmpty() -> Assessment(
                verdict = if (oneUi) Verdict.RISKY else Verdict.UNKNOWN,
                summary = if (oneUi) "Likely wrong: OneUI build" else "No target GPU or Mesa version in the package",
                reasons = reasons + "Nothing in the name or description identifies an Adreno family or a Mesa version, so it cannot be matched against ${device.model}. Keep the default driver ready.",
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
