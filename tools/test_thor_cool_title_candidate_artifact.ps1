param(
    [string]$CandidatePath,
    [string]$ApkPath,
    [string]$MergedCorePath,
    [string]$StrippedCorePath
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path $PSScriptRoot "thor_cool_title_candidate.psd1"
}
if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $repoRoot "app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk"
}
if ([string]::IsNullOrWhiteSpace($MergedCorePath)) {
    $MergedCorePath = Join-Path $repoRoot "app/build/intermediates/merged_native_libs/thortest/mergeThortestNativeLibs/out/lib/arm64-v8a/librpcsx-android.so"
}
if ([string]::IsNullOrWhiteSpace($StrippedCorePath)) {
    $StrippedCorePath = Join-Path $repoRoot "app/build/intermediates/stripped_native_libs/thortest/stripThortestDebugSymbols/out/lib/arm64-v8a/librpcsx-android.so"
}

foreach ($path in @($CandidatePath, $ApkPath, $MergedCorePath, $StrippedCorePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pinned Thor artifact input does not exist: $path"
    }
}

$candidate = Import-PowerShellDataFile -LiteralPath $CandidatePath
$requiredFields = @(
    "Package",
    "ApkSha256",
    "ApkSize",
    "MergedCoreSha256",
    "MergedCoreSize",
    "PackagedCoreSha256",
    "PackagedCoreSize"
)
foreach ($field in $requiredFields) {
    if (-not $candidate.ContainsKey($field)) {
        throw "Pinned Thor candidate is missing '$field': $CandidatePath"
    }
}

if ([string]::IsNullOrWhiteSpace([string]$candidate.Package)) {
    throw "Pinned Thor candidate package is empty."
}
foreach ($field in @("ApkSha256", "MergedCoreSha256", "PackagedCoreSha256")) {
    if ([string]$candidate[$field] -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Pinned Thor candidate '$field' is not a SHA-256 value."
    }
}
foreach ($field in @("ApkSize", "MergedCoreSize", "PackagedCoreSize")) {
    if ([long]$candidate[$field] -le 0) {
        throw "Pinned Thor candidate '$field' must be positive."
    }
}

function Assert-PinnedFileIdentity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [long]$ExpectedSize,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    $item = Get-Item -LiteralPath $Path
    if ($item.Length -ne $ExpectedSize) {
        throw "$Label size mismatch: expected $ExpectedSize, got $($item.Length) ($Path)"
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($hash -ne $ExpectedSha256.ToUpperInvariant()) {
        throw "$Label SHA-256 mismatch: expected $ExpectedSha256, got $hash ($Path)"
    }

    return [pscustomobject]@{
        Label = $Label
        Path = (Resolve-Path -LiteralPath $Path).Path
        Size = $item.Length
        Sha256 = $hash
    }
}

$rows = @(
    Assert-PinnedFileIdentity -Label "APK" -Path $ApkPath -ExpectedSize ([long]$candidate.ApkSize) -ExpectedSha256 ([string]$candidate.ApkSha256)
    Assert-PinnedFileIdentity -Label "Merged core" -Path $MergedCorePath -ExpectedSize ([long]$candidate.MergedCoreSize) -ExpectedSha256 ([string]$candidate.MergedCoreSha256)
    Assert-PinnedFileIdentity -Label "Stripped core" -Path $StrippedCorePath -ExpectedSize ([long]$candidate.PackagedCoreSize) -ExpectedSha256 ([string]$candidate.PackagedCoreSha256)
)

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath))
try {
    $entryName = "lib/arm64-v8a/librpcsx-android.so"
    $entries = @($archive.Entries | Where-Object FullName -eq $entryName)
    if ($entries.Count -ne 1) {
        throw "Pinned Thor APK must contain exactly one '$entryName' entry; found $($entries.Count)."
    }

    $entry = $entries[0]
    if ($entry.Length -ne [long]$candidate.PackagedCoreSize) {
        throw "Packaged core entry size mismatch: expected $($candidate.PackagedCoreSize), got $($entry.Length)."
    }

    $stream = $entry.Open()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $entryHash = [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace("-", "")
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }

    if ($entryHash -ne ([string]$candidate.PackagedCoreSha256).ToUpperInvariant()) {
        throw "Packaged core entry SHA-256 mismatch: expected $($candidate.PackagedCoreSha256), got $entryHash."
    }

    $dexEntries = @($archive.Entries | Where-Object { $_.FullName -match '^classes(?:[0-9]+)?[.]dex$' })
    if ($dexEntries.Count -eq 0) {
        throw "Pinned Thor APK contains no DEX entries."
    }

    $dexText = foreach ($dexEntry in $dexEntries) {
        $dexStream = $dexEntry.Open()
        $dexBytes = [IO.MemoryStream]::new()
        try {
            $dexStream.CopyTo($dexBytes)
            [Text.Encoding]::ASCII.GetString($dexBytes.ToArray())
        } finally {
            $dexBytes.Dispose()
            $dexStream.Dispose()
        }
    }
    $joinedDexText = $dexText -join [Environment]::NewLine
    foreach ($requiredDexMarker in @(
        "thorDebugBootRequestId",
        "Thor debug boot accepted:",
        "thorReplaceCustomProfile",
        "replaceCustomWithRecommendedConfigForTitleId"
    )) {
        if (-not $joinedDexText.Contains($requiredDexMarker)) {
            throw "Pinned Thor APK DEX is missing debug-boot marker: $requiredDexMarker"
        }
    }
} finally {
    $archive.Dispose()
}

$rows | Format-Table Label, Size, Sha256 -AutoSize
Write-Output "package=$($candidate.Package)"
Write-Output "apk_entry_sha256=$entryHash"
Write-Output "Thor cool-title candidate artifact contract passed."
