plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
    id("org.jetbrains.kotlin.plugin.serialization")
    id("kotlin-parcelize")
}

val buildBundledRpcsxCore =
    when (providers.gradleProperty("buildBundledRpcsxCore").orNull ?: System.getenv("RPCSX_BUILD_BUNDLED_CORE")) {
        "0", "false", "False", "FALSE", "off", "Off", "OFF" -> false
        else -> true
    }

// Armv8.4-A is the lowest baseline guaranteeing FEAT_LSE2, which the 16-byte
// atomic fast paths in util/atomic.hpp need. Kept in step with the CMake default
// and its RPCSX_ANDROID_ARM_LSE2 guard; lowering this without also turning that
// option off is a configure-time error rather than a silent slow path.
val rpcsxAndroidArmArch =
    providers.gradleProperty("rpcsxAndroidArmArch").orNull
        ?: System.getenv("RPCSX_ANDROID_ARM_ARCH")
        ?: "armv8.4-a"
val rpcsxAndroidArmTune =
    providers.gradleProperty("rpcsxAndroidArmTune").orNull
        ?: System.getenv("RPCSX_ANDROID_ARM_TUNE")
        ?: "cortex-a715"

val rpcsxThorWaitProfiler =
    when (providers.gradleProperty("rpcsxThorWaitProfiler").orNull ?: System.getenv("RPCSX_THOR_WAIT_PROFILER_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

// Make the thortest variant debuggable, so run-as, /proc/<tid>/syscall and
// simpleperf become available on device.
//
// This is opt-in rather than the default because thortest is the *measurement*
// variant, and android:debuggable changes ART's behaviour - it is the wrong
// footing to take a power or spin number from. Diagnosis and measurement want
// different builds.
//
// It deliberately does not touch the CMake arguments, so flipping it reuses the
// cached native objects instead of forcing a full rebuild. The RSX boot hang
// needs exactly this and nothing else: see docs/arm64/rsx-boot-hang.md.
val rpcsxThorDebuggable =
    when (providers.gradleProperty("rpcsxThorDebuggable").orNull ?: System.getenv("RPCSX_THOR_DEBUGGABLE_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

// AArch64 answer to the x86 MONITORX/MWAITX GETLLAR wait: park the core with
// WFE instead of spinning. Off by default; the case for it is power and
// thermal behaviour, which this fork cannot measure.
val rpcsxThorArm64WfeWait =
    when (providers.gradleProperty("rpcsxThorArm64WfeWait").orNull ?: System.getenv("RPCSX_THOR_ARM64_WFE_WAIT_BUILD")) {
        null, "", "0", "false", "off", "OFF" -> false
        else -> true
    }

val rpcsxThorBusyWaitExperiment =
    when (providers.gradleProperty("rpcsxThorBusyWaitExperiment").orNull ?: System.getenv("RPCSX_THOR_BUSY_WAIT_EXPERIMENT_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorSpuReducedLoopDiagnostics =
    when (providers.gradleProperty("rpcsxThorSpuReducedLoopDiagnostics").orNull ?: System.getenv("RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorRsxAuditor =
    when (providers.gradleProperty("rpcsxThorRsxAuditor").orNull ?: System.getenv("RPCSX_THOR_RSX_AUDITOR_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorRsxExperiments =
    when (providers.gradleProperty("rpcsxThorRsxExperiments").orNull ?: System.getenv("RPCSX_THOR_RSX_EXPERIMENTS_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorSyscallStats =
    when (providers.gradleProperty("rpcsxThorSyscallStats").orNull ?: System.getenv("RPCSX_THOR_SYSCALL_STATS_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorSpursProbe =
    when (providers.gradleProperty("rpcsxThorSpursProbe").orNull ?: System.getenv("RPCSX_THOR_SPURS_PROBE_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorDrawStreamProbe =
    when (providers.gradleProperty("rpcsxThorDrawStreamProbe").orNull ?: System.getenv("RPCSX_THOR_DRAW_STREAM_PROBE_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorSemaSuperpath =
    when (providers.gradleProperty("rpcsxThorSemaSuperpath").orNull ?: System.getenv("RPCSX_THOR_SEMA_SUPERPATH_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorEsSpuExperiments =
    when (providers.gradleProperty("rpcsxThorEsSpuExperiments").orNull ?: System.getenv("RPCSX_THOR_ES_SPU_EXPERIMENTS_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorEsPpuExperiments =
    when (providers.gradleProperty("rpcsxThorEsPpuExperiments").orNull ?: System.getenv("RPCSX_THOR_ES_PPU_EXPERIMENTS_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorAdpfRsxHint =
    when (providers.gradleProperty("rpcsxThorAdpfRsxHint").orNull ?: System.getenv("RPCSX_THOR_ADPF_RSX_HINT_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

val rpcsxThorThermalHeadroomProbe =
    when (providers.gradleProperty("rpcsxThorThermalHeadroomProbe").orNull ?: System.getenv("RPCSX_THOR_THERMAL_HEADROOM_PROBE_BUILD")) {
        "1", "true", "True", "TRUE", "on", "On", "ON" -> true
        else -> false
    }

// This fork targets the AYN Thor, which is arm64-v8a. Building x86_64 as well
// put 26 MiB compressed / 65 MiB uncompressed of unreachable code into a 96 MiB
// APK, more than half the payload, and doubled the native compile. Anyone who
// needs it back can pass -PrpcsxAndroidAbis=arm64-v8a,x86_64 or set
// RPCSX_ANDROID_ABIS; the arm64-only default is what ships to the device.
val rpcsxAndroidAbis =
    (providers.gradleProperty("rpcsxAndroidAbis").orNull
        ?: System.getenv("RPCSX_ANDROID_ABIS")
        ?: "arm64-v8a")
        .split(',')
        .map(String::trim)
        .filter(String::isNotEmpty)
        .distinct()

require(rpcsxAndroidAbis.isNotEmpty()) {
    "rpcsxAndroidAbis/RPCSX_ANDROID_ABIS must contain at least one Android ABI"
}

android {
    namespace = "net.rpcsx"
    compileSdk = 36
    ndkVersion = "29.0.13113456"

    defaultConfig {
        applicationId = "net.rpcsx.easy"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "${System.getenv("RX_VERSION") ?: "local"}${if (System.getenv("RX_SHA") != null) "-" + System.getenv("RX_SHA") else ""}"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += rpcsxAndroidAbis
        }

        externalNativeBuild {
            cmake {
                // The adrenotools hook libraries have to be built and packaged or
                // custom GPU drivers cannot load at all. adrenotools_open_libvulkan
                // dlopens libhook_impl.so and then libmain_hook.so out of
                // nativeLibraryDir, and returns null the moment either is missing.
                // They were absent from this list, so the APK shipped without them
                // and every Turnip package failed silently: the only symptom was
                // "failed to load selected driver" with no reason given.
                //
                // file_redirect_hook and gsl_alloc_hook are only dlopened when
                // their feature flags are set, but they are a few KiB each and
                // leaving them out is how this class of bug happens.
                val adrenotoolsHooks = listOf(
                    "hook_impl",
                    "main_hook",
                    "file_redirect_hook",
                    "gsl_alloc_hook"
                )

                targets += if (buildBundledRpcsxCore) {
                    listOf("rpcsx-ui-jni", "rpcsx-android") + adrenotoolsHooks
                } else {
                    listOf("rpcsx-ui-jni") + adrenotoolsHooks
                }
                arguments += listOf(
                    "-DRPCSX_BUILD_BUNDLED_CORE=${if (buildBundledRpcsxCore) "ON" else "OFF"}",
                    "-DRPCSX_ANDROID_ARM_ARCH=$rpcsxAndroidArmArch",
                    "-DRPCSX_ANDROID_ARM_TUNE=$rpcsxAndroidArmTune",
                    "-DRPCSX_THOR_WAIT_PROFILER=${if (rpcsxThorWaitProfiler) "ON" else "OFF"}",
                    "-DRPCSX_THOR_BUSY_WAIT_EXPERIMENT=${if (rpcsxThorBusyWaitExperiment) "ON" else "OFF"}",
                    "-DRPCSX_THOR_ARM64_WFE_WAIT=${if (rpcsxThorArm64WfeWait) "ON" else "OFF"}",
                    "-DRPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS=${if (rpcsxThorSpuReducedLoopDiagnostics) "ON" else "OFF"}",
                    "-DRPCSX_THOR_RSX_AUDITOR=${if (rpcsxThorRsxAuditor) "ON" else "OFF"}",
                    "-DRPCSX_THOR_RSX_EXPERIMENTS=${if (rpcsxThorRsxExperiments) "ON" else "OFF"}",
                    "-DRPCSX_THOR_SYSCALL_STATS=${if (rpcsxThorSyscallStats) "ON" else "OFF"}",
                    "-DRPCSX_THOR_SPURS_PROBE=${if (rpcsxThorSpursProbe) "ON" else "OFF"}",
                    "-DRPCSX_THOR_DRAW_STREAM_PROBE=${if (rpcsxThorDrawStreamProbe) "ON" else "OFF"}",
                    "-DRPCSX_THOR_SEMA_SUPERPATH=${if (rpcsxThorSemaSuperpath) "ON" else "OFF"}",
                    "-DRPCSX_THOR_ES_SPU_EXPERIMENTS=${if (rpcsxThorEsSpuExperiments) "ON" else "OFF"}",
                    "-DRPCSX_THOR_ES_PPU_EXPERIMENTS=${if (rpcsxThorEsPpuExperiments) "ON" else "OFF"}",
                    "-DRPCSX_THOR_ADPF_RSX_HINT=${if (rpcsxThorAdpfRsxHint) "ON" else "OFF"}",
                    "-DRPCSX_THOR_THERMAL_HEADROOM_PROBE=${if (rpcsxThorThermalHeadroomProbe) "ON" else "OFF"}",
                )
            }
        }

        buildConfigField("String", "Version", "\"v${versionName}\"")
        buildConfigField("Boolean", "FORK_BUILD", "true")
        buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "false")
        buildConfigField("Boolean", "THOR_DEV_CORE_OVERRIDE", "false")
    }

    signingConfigs {
        val keystoreAlias = System.getenv("KEYSTORE_ALIAS") ?: ""
        val keystorePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
        val keystorePath = System.getenv("KEYSTORE_PATH") ?: ""

        if (keystorePath.isNotEmpty() && file(keystorePath).exists() && file(keystorePath).length() > 0) {
            create("custom-key") {
                keyAlias = keystoreAlias
                keyPassword = keystorePassword
                storeFile = file(keystorePath)
                storePassword = keystorePassword
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "true")
            buildConfigField("Boolean", "THOR_DEV_CORE_OVERRIDE", "true")
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("custom-key") ?: signingConfigs.getByName("debug")
        }

        create("thortest") {
            initWith(getByName("release"))
            isDebuggable = rpcsxThorDebuggable
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
            matchingFallbacks += listOf("release")
            buildConfigField("Boolean", "THOR_DEBUG_TOOLS", "true")
        }
    }

    sourceSets {
        getByName("thortest") {
            manifest.srcFile("src/debug/AndroidManifest.xml")
            java.srcDir("src/debug/java")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.6"
        }
    }

    buildFeatures {
        viewBinding = true
        compose = true
        buildConfig = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.15"
    }

    packaging {
        // This is necessary for libadrenotools custom driver loading
        jniLibs.useLegacyPackaging = true
    }
}

base.archivesName = "rpcsx-thor-experiment"

dependencies {
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.ui.tooling.preview.android)
    val composeBom = platform("androidx.compose:compose-bom:2026.02.01")
    implementation(composeBom)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.activity)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    debugImplementation(libs.androidx.ui.tooling)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.coil.compose)
    implementation(libs.squareup.okhttp3)
    implementation(libs.androidx.documentfile)
    implementation(libs.compose.preferences)
}
