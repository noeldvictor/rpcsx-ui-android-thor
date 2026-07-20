param(
    [string]$CorePath,
    [string]$ReadElfPath,
    [int]$MaxDefinedDynamicSymbols = 64,
    [int]$MaxExplicitRelocations = 1024,
    [int]$MaxJumpSlots = 1024,
    [int]$MaxEncodedRelocationBytes = 65536
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$cmakePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/CMakeLists.txt"
$mapPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/rpcsx-android.map"

$cmakeSource = Get-Content -LiteralPath $cmakePath -Raw
$mapSource = Get-Content -LiteralPath $mapPath -Raw

foreach ($fragment in @(
    "RPCSX_ANDROID_LIMIT_DYNAMIC_EXPORTS",
    "--version-script=",
    "--exclude-libs,ALL",
    "--pack-dyn-relocs=android+relr",
    "--use-android-relr-tags",
    "LINK_DEPENDS"
)) {
    if (-not $cmakeSource.Contains($fragment)) {
        throw "RPCSX Android export localization is missing CMake fragment: $fragment"
    }
}

if ($mapSource -notmatch "(?s)global:\s*_rpcsx_\*;.*local:\s*\*;") {
    throw "RPCSX Android version script must export only _rpcsx_*."
}

if ([string]::IsNullOrWhiteSpace($CorePath)) {
    $CorePath = Join-Path $repoRoot (
        "app/build/intermediates/stripped_native_libs/thortest/" +
        "stripThortestDebugSymbols/out/lib/arm64-v8a/librpcsx-android.so"
    )
}

if (-not (Test-Path -LiteralPath $CorePath -PathType Leaf)) {
    throw "Stripped Thor core does not exist: $CorePath"
}

if ([string]::IsNullOrWhiteSpace($ReadElfPath)) {
    $readElfCommand = Get-Command llvm-readelf -ErrorAction SilentlyContinue
    if ($readElfCommand) {
        $ReadElfPath = $readElfCommand.Source
    } else {
        $sdkRoots = @(
            $env:ANDROID_HOME,
            $env:ANDROID_SDK_ROOT,
            (Join-Path $env:LOCALAPPDATA "Android/Sdk")
        ) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique

        foreach ($sdkRoot in $sdkRoots) {
            $ndkRoot = Join-Path $sdkRoot "ndk"
            if (-not (Test-Path -LiteralPath $ndkRoot -PathType Container)) {
                continue
            }

            $ndkVersions = Get-ChildItem -LiteralPath $ndkRoot -Directory |
                Sort-Object Name -Descending
            foreach ($ndkVersion in $ndkVersions) {
                $candidate = Join-Path $ndkVersion.FullName (
                    "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe"
                )
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $ReadElfPath = $candidate
                    break
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($ReadElfPath)) {
                break
            }
        }
    }
}

if ([string]::IsNullOrWhiteSpace($ReadElfPath) -or
    -not (Test-Path -LiteralPath $ReadElfPath -PathType Leaf)) {
    throw "llvm-readelf was not found. Pass -ReadElfPath explicitly."
}

function Invoke-ReadElf {
    param([string[]]$Arguments)

    $output = & $ReadElfPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "llvm-readelf failed: $($output -join [Environment]::NewLine)"
    }

    return @($output)
}

$symbolLines = Invoke-ReadElf @("--dyn-syms", "--wide", $CorePath)
$definedNames = [System.Collections.Generic.List[string]]::new()

foreach ($line in $symbolLines) {
    if ($line -notmatch (
        "^\s*\d+:\s+\S+\s+\d+\s+\S+\s+" +
        "(?<bind>GLOBAL|WEAK)\s+\S+\s+(?<ndx>\S+)\s+(?<name>\S+)"
    )) {
        continue
    }

    if ($matches.ndx -eq "UND") {
        continue
    }

    [void]$definedNames.Add(($matches.name -replace "@.*$", ""))
}

$unexpectedExports = @($definedNames | Where-Object { $_ -notmatch "^_rpcsx_" })
if ($unexpectedExports.Count -ne 0) {
    $sample = $unexpectedExports | Select-Object -First 20
    throw "Unexpected dynamic exports ($($unexpectedExports.Count)): " +
        "$($sample -join ', ')"
}

$requiredExports = @(
    "_rpcsx_boot",
    "_rpcsx_collectGameInfo",
    "_rpcsx_consumeHomeMenuExitGameSelected",
    "_rpcsx_getDirInstallPath",
    "_rpcsx_getState",
    "_rpcsx_getTitleId",
    "_rpcsx_getUser",
    "_rpcsx_getVersion",
    "_rpcsx_initialize",
    "_rpcsx_install",
    "_rpcsx_installFw",
    "_rpcsx_installKey",
    "_rpcsx_isFastForwardEnabled",
    "_rpcsx_isInstallableFile",
    "_rpcsx_kill",
    "_rpcsx_loadState",
    "_rpcsx_loginUser",
    "_rpcsx_noteHomeMenuExitGameSelected",
    "_rpcsx_openHomeMenu",
    "_rpcsx_overlayPadData",
    "_rpcsx_preparePpuCache",
    "_rpcsx_processCompilationQueue",
    "_rpcsx_resume",
    "_rpcsx_saveState",
    "_rpcsx_setCustomDriver",
    "_rpcsx_setFastForwardEnabled",
    "_rpcsx_settingsGet",
    "_rpcsx_settingsSet",
    "_rpcsx_shutdown",
    "_rpcsx_startMainThreadProcessor",
    "_rpcsx_syncLogs",
    "_rpcsx_surfaceEvent",
    "_rpcsx_systemInfo",
    "_rpcsx_toggleFastForward",
    "_rpcsx_usbDeviceEvent"
)

$missingExports = @($requiredExports | Where-Object { $_ -notin $definedNames })
if ($missingExports.Count -ne 0) {
    throw "Required RPCSX Android exports are missing: $($missingExports -join ', ')"
}

if ($definedNames.Count -gt $MaxDefinedDynamicSymbols) {
    throw "Defined dynamic symbol count $($definedNames.Count) exceeds " +
        "$MaxDefinedDynamicSymbols."
}

$dynamicLines = Invoke-ReadElf @("-d", "--wide", $CorePath)
$dynamicText = $dynamicLines -join [Environment]::NewLine
if ($dynamicText -notmatch "\(ANDROID_RELR\)") {
    throw "Thor core does not use API-28-compatible ANDROID_RELR tags."
}
if ($dynamicText -notmatch "\(ANDROID_RELA\)") {
    throw "Thor core does not use Android packed non-relative relocations."
}

$sectionLines = Invoke-ReadElf @("-S", "--wide", $CorePath)
$encodedRelocationBytes = 0
foreach ($line in $sectionLines) {
    if ($line -match (
        "^\s*\[\s*\d+\]\s+" +
        "(?:\.rela\.dyn|\.relr\.dyn|\.rela\.plt)\s+\S+\s+" +
        "\S+\s+\S+\s+(?<size>[0-9a-fA-F]+)\s+"
    )) {
        $encodedRelocationBytes += [Convert]::ToInt64($matches.size, 16)
    }
}

if ($encodedRelocationBytes -gt $MaxEncodedRelocationBytes) {
    throw "Encoded relocation data $encodedRelocationBytes bytes exceeds " +
        "$MaxEncodedRelocationBytes bytes."
}

$relocationLines = Invoke-ReadElf @("-r", "--wide", $CorePath)
$relocationTypes = @()
$relocationSection = ""
foreach ($line in $relocationLines) {
    if ($line -match "^Relocation section '(?<section>[^']+)'") {
        $relocationSection = $matches.section
        continue
    }

    # LLVM 18 expands packed RELR entries while LLVM 20 leaves them encoded.
    # They are not explicit dynamic relocations in either representation.
    if ($relocationSection -ne ".relr.dyn" -and
        $line -match "\s(R_AARCH64_[A-Z0-9_]+)\s") {
        $relocationTypes += $matches[1]
    }
}

if ($relocationTypes.Count -gt $MaxExplicitRelocations) {
    throw "Explicit relocation count $($relocationTypes.Count) exceeds " +
        "$MaxExplicitRelocations."
}

$jumpSlotCount = @(
    $relocationTypes | Where-Object { $_ -eq "R_AARCH64_JUMP_SLOT" }
).Count
if ($jumpSlotCount -gt $MaxJumpSlots) {
    throw "JUMP_SLOT count $jumpSlotCount exceeds $MaxJumpSlots."
}

Write-Output (
    (
        "Thor core export surface passed: {0} defined dynamic symbols, " +
        "{1} explicit relocations, {2} JUMP_SLOT, {3} encoded relocation bytes."
    ) -f
        $definedNames.Count,
        $relocationTypes.Count,
        $jumpSlotCount,
        $encodedRelocationBytes
)
