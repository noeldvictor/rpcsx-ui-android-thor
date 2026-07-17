param(
    [string]$ApkPath
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gradlePath = Join-Path $repoRoot "app/build.gradle.kts"

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $repoRoot "app/build/outputs/apk/release/rpcsx-thor-experiment-release.apk"
}

if (-not (Test-Path -LiteralPath $ApkPath -PathType Leaf)) {
    throw "Thor APK does not exist: $ApkPath"
}

$gradleSource = Get-Content -LiteralPath $gradlePath -Raw
if (-not $gradleSource.Contains('providers.gradleProperty("rpcsxAndroidAbis")')) {
    throw "The Android build no longer exposes the rpcsxAndroidAbis property."
}

if (-not $gradleSource.Contains("abiFilters += rpcsxAndroidAbis")) {
    throw "The configured Thor ABI list is not wired to ndk.abiFilters."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath))

try {
    $entryNames = @($archive.Entries | ForEach-Object FullName)
    $requiredEntries = @(
        "lib/arm64-v8a/librpcsx-android.so",
        "lib/arm64-v8a/librpcsx-ui-jni.so"
    )

    foreach ($requiredEntry in $requiredEntries) {
        if ($entryNames -notcontains $requiredEntry) {
            throw "Thor APK is missing required entry: $requiredEntry"
        }
    }

    $wrongAbiCoreEntries = @(
        $entryNames |
            Where-Object {
                $_ -match '^lib/(?!arm64-v8a/)[^/]+/(librpcsx-android|librpcsx-ui-jni)[.]so$'
            }
    )

    if ($wrongAbiCoreEntries.Count -ne 0) {
        throw "Thor APK contains RPCSX libraries for another ABI: $($wrongAbiCoreEntries -join ', ')"
    }

    $entryRows = foreach ($requiredEntry in $requiredEntries) {
        $entry = $archive.GetEntry($requiredEntry)
        [pscustomobject]@{
            Entry = $requiredEntry
            MiB = [math]::Round($entry.Length / 1MB, 2)
        }
    }
} finally {
    $archive.Dispose()
}

$apkHash = (Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256).Hash
$entryRows | Format-Table -AutoSize
Write-Output "APK SHA256: $apkHash"
Write-Output "Thor arm64 APK contract passed."
