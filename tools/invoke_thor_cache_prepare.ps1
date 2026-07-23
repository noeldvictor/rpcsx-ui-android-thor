param(
    [ValidateSet("Status", "Run")]
    [string]$Action = "Status",
    [string]$Serial = "c3ca0370",
    [string]$CandidatePath = "",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [ValidateRange(30, 180)]
    [int]$MaxSeconds = 70
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"
. "$PSScriptRoot\thor_cache_prepare_process_health.ps1"
. "$PSScriptRoot\thor_cache_prepare_progress.ps1"

$expectedSerial = "c3ca0370"
$titleId = "BLUS30161"
$package = "net.rpcsx.easy"
$intentAction = "net.rpcsx.THOR_DEBUG_PREPARE_CACHE"
$maxBatteryTemperatureC = 34.0
$maxSkinTemperatureC = 40.0
$maxLaunchSiliconTemperatureC = 35.0
$maxPreflightRiseC = 1.0
$maxSiliconTemperatureC = 60.0
$runtimeStopHeadroomC = 5.0
$runtimeProbeWindowC = 10.0
$runtimeWarmTelemetryC = 45.0
$minimumCacheCooldownMinutes = 30.0
$preflightSamples = 3
$preflightIntervalSeconds = 2
$pollIntervalSeconds = 2
$acceptDeadlineSeconds = 15
$timeoutFailureMessage = "Cache preparation did not complete inside the $MaxSeconds-second bound."
$spuNativeObjectCache = "on"
$spuCachePreloadLimit = 64
$spuCacheCompileBudgetMs = 100
$cacheWorkerAffinityMask = 7
$spuCacheWorkerLimit = 3

if ($Serial -ne $expectedSerial) {
    throw "This cache-preparation proof is pinned to Thor serial $expectedSerial; got $Serial."
}
if (-not $GamePath.StartsWith("/") -or $GamePath.Contains("`n") -or $GamePath.Contains("`r")) {
    throw "GamePath must be one absolute Android path without newlines."
}
if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
    $CandidatePath = Join-Path $PSScriptRoot "thor_cool_title_candidate.psd1"
}
$resolvedCandidatePath = (Resolve-Path -LiteralPath $CandidatePath).Path
$candidate = Import-PowerShellDataFile -LiteralPath $resolvedCandidatePath
foreach ($field in @("Package", "ApkSha256", "ApkSize")) {
    if (-not $candidate.ContainsKey($field)) {
        throw "Pinned Thor candidate is missing '$field': $resolvedCandidatePath"
    }
}
if ([string]$candidate.Package -ne $package) {
    throw "Pinned package mismatch: expected $package, got $($candidate.Package)."
}
$expectedApkHash = ([string]$candidate.ApkSha256).ToUpperInvariant()
if ($expectedApkHash -notmatch '^[0-9A-F]{64}$') {
    throw "Pinned APK SHA-256 is invalid: $expectedApkHash"
}

$repoRoot = Get-ThorRepoRoot
$apkPath = Join-Path $repoRoot "app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk"
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Pinned Thor APK is missing: $apkPath"
}
$apkItem = Get-Item -LiteralPath $apkPath
$hostApkHash = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash
if ($apkItem.Length -ne [long]$candidate.ApkSize -or $hostApkHash -ne $expectedApkHash) {
    throw "Pinned host APK identity does not match $resolvedCandidatePath."
}

$latestCacheCaptureName = "none"
$latestCacheCompletedAt = $null
$latestCacheReadmeText = ""
$cacheCaptures = @()
$latestInstallCaptureName = "none"
$latestInstallCompletedAt = $null
$latestTitleCaptureName = "none"
$latestTitleCompletedAt = $null
$cacheCaptureRoot = Join-Path $repoRoot "debug-captures\android-speed-sprint"
if (Test-Path -LiteralPath $cacheCaptureRoot -PathType Container) {
    $cacheCaptures = @(Get-ChildItem -LiteralPath $cacheCaptureRoot -Directory |
        Where-Object { $_.Name -match '^[0-9]{8}-[0-9]{6}-firmware-ppu-prewarm$' } |
        Sort-Object Name -Descending)
    $latestCacheCapture = $cacheCaptures | Select-Object -First 1
    if ($null -ne $latestCacheCapture) {
        $latestCacheCaptureName = $latestCacheCapture.Name
        $latestReadme = Join-Path $latestCacheCapture.FullName "README.md"
        if (-not (Test-Path -LiteralPath $latestReadme -PathType Leaf)) {
            throw "Latest cache capture has no README; refusing cooldown inference: $latestCacheCaptureName"
        }
        $latestCacheReadmeText = Get-Content -LiteralPath $latestReadme -Raw
        $createdMatch = [regex]::Match(
            $latestCacheReadmeText,
            '(?m)^- Created:\s*(\S.+)$'
        )
        $parsedCreatedAt = [DateTimeOffset]::MinValue
        if (-not $createdMatch.Success -or
            -not [DateTimeOffset]::TryParse(
                $createdMatch.Groups[1].Value.Trim(),
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsedCreatedAt
            )) {
            throw "Latest cache capture has an invalid Created timestamp: $latestCacheCaptureName"
        }
        $latestCacheCompletedAt = $parsedCreatedAt
    }

    $latestInstallCapture = Get-ChildItem -LiteralPath $cacheCaptureRoot -Directory |
        Where-Object { $_.Name -match '^[0-9]{8}-[0-9]{6}-.+-apk-install$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -ne $latestInstallCapture) {
        $latestInstallCaptureName = $latestInstallCapture.Name
        $latestInstallReadme = Join-Path $latestInstallCapture.FullName "README.md"
        if (-not (Test-Path -LiteralPath $latestInstallReadme -PathType Leaf)) {
            throw "Latest install capture has no README; refusing cooldown inference: $latestInstallCaptureName"
        }
        $latestInstallReadmeText = Get-Content -LiteralPath $latestInstallReadme -Raw
        if (-not $latestInstallReadmeText.StartsWith("# Thor APK No-Launch Install", [StringComparison]::Ordinal) -or
            -not $latestInstallReadmeText.Contains("- Device serial: $Serial") -or
            -not $latestInstallReadmeText.Contains("- Package: $package") -or
            -not $latestInstallReadmeText.Contains("- Emulator launch: no") -or
            $latestInstallReadmeText -notmatch '(?m)^- Status: (installed-exact-no-launch|failed)\r?$') {
            throw "Latest install capture is not valid no-launch evidence: $latestInstallCaptureName"
        }
        $installCreatedMatch = [regex]::Match(
            $latestInstallReadmeText,
            '(?m)^- Created:\s*(\S.+)$'
        )
        $parsedInstallAt = [DateTimeOffset]::MinValue
        if (-not $installCreatedMatch.Success -or
            -not [DateTimeOffset]::TryParse(
                $installCreatedMatch.Groups[1].Value.Trim(),
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsedInstallAt
            )) {
            throw "Latest install capture has an invalid Created timestamp: $latestInstallCaptureName"
        }
        $latestInstallCompletedAt = $parsedInstallAt
    }
    $latestTitleCapture = Get-ChildItem -LiteralPath $cacheCaptureRoot -Directory |
        Where-Object { $_.Name -match '^[0-9]{8}-[0-9]{6}-thor-input-custom$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -ne $latestTitleCapture) {
        $latestTitleCaptureName = $latestTitleCapture.Name
        $latestTitleReadme = Join-Path $latestTitleCapture.FullName "README.md"
        if (-not (Test-Path -LiteralPath $latestTitleReadme -PathType Leaf)) {
            throw "Latest title capture has no README; refusing cooldown inference: $latestTitleCaptureName"
        }
        $latestTitleReadmeText = Get-Content -LiteralPath $latestTitleReadme -Raw
        if (-not $latestTitleReadmeText.StartsWith("# Thor Input Macro", [StringComparison]::Ordinal) -or
            -not $latestTitleReadmeText.Contains("- Device serial: $Serial") -or
            -not $latestTitleReadmeText.Contains("- Package: $package") -or
            $latestTitleReadmeText -notmatch '(?m)^- Expected installed APK SHA-256: [0-9A-Fa-f]{64}\r?$' -or
            -not $latestTitleReadmeText.Contains("- BootGame: True") -or
            -not $latestTitleReadmeText.Contains("- ForceStop: True") -or
            -not $latestTitleReadmeText.Contains("- Macro: gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop")) {
            throw "Latest title capture is not valid safe title-route cooldown evidence: $latestTitleCaptureName"
        }
        $latestTitleCompletedAt = Get-ThorCaptureRecordedCompletion `
            -CaptureDirectory $latestTitleCapture.FullName
    }
}
$minimumRequiredReuse = Get-ThorCachePrepareReuseFloor -LatestReadmeText $latestCacheReadmeText
$minimumRequiredSpuNativeObjects = 0
$spuContinuityCaptureName = "none"
foreach ($cacheCapture in $cacheCaptures) {
    $continuityReadme = Join-Path $cacheCapture.FullName "README.md"
    if (-not (Test-Path -LiteralPath $continuityReadme -PathType Leaf)) {
        continue
    }
    $continuityReadmeText = Get-Content -LiteralPath $continuityReadme -Raw
    $candidateSpuFloor = Get-ThorSpuNativeObjectReuseFloor `
        -LatestReadmeText $continuityReadmeText `
        -MaximumObjects $spuCachePreloadLimit
    if ($candidateSpuFloor -gt 0) {
        $minimumRequiredSpuNativeObjects = $candidateSpuFloor
        $spuContinuityCaptureName = $cacheCapture.Name
        break
    }
}
$cooldownSource = Get-ThorCachePrepareCooldownSource `
    -CacheCaptureName $latestCacheCaptureName `
    -CacheCompletedAt $latestCacheCompletedAt `
    -InstallCaptureName $latestInstallCaptureName `
    -InstallCompletedAt $latestInstallCompletedAt `
    -TitleCaptureName $latestTitleCaptureName `
    -TitleCompletedAt $latestTitleCompletedAt
$cacheCooldown = Get-ThorCachePrepareCooldownState `
    -LastCompletedAt $cooldownSource.completed_at `
    -MinimumMinutes $minimumCacheCooldownMinutes

if ($Action -eq "Status") {
    @(
        "action=Status",
        "device_contact=False",
        "serial=$Serial",
        "package=$package",
        "title_id=$titleId",
        "intent_action=$intentAction",
        "game_path=$GamePath",
        "apk_sha256=$expectedApkHash",
        "max_seconds=$MaxSeconds",
        "preflight_samples=$preflightSamples",
        "preflight_interval_seconds=$preflightIntervalSeconds",
        "max_launch_silicon_c=$maxLaunchSiliconTemperatureC",
        "max_preflight_rise_c=$maxPreflightRiseC",
        "runtime_probe_silicon_c=$($maxSiliconTemperatureC - $runtimeProbeWindowC)",
        "runtime_stop_silicon_c=$($maxSiliconTemperatureC - $runtimeStopHeadroomC)",
        "max_silicon_c=$maxSiliconTemperatureC",
        "minimum_cache_cooldown_minutes=$minimumCacheCooldownMinutes",
        "latest_cache_capture=$latestCacheCaptureName",
        "latest_cache_completed_at=$(if ($null -eq $latestCacheCompletedAt) { 'none' } else { $latestCacheCompletedAt.ToString('o') })",
        "spu_continuity_capture=$spuContinuityCaptureName",
        "latest_install_capture=$latestInstallCaptureName",
        "latest_install_completed_at=$(if ($null -eq $latestInstallCompletedAt) { 'none' } else { $latestInstallCompletedAt.ToString('o') })",
        "latest_title_capture=$latestTitleCaptureName",
        "latest_title_completed_at=$(if ($null -eq $latestTitleCompletedAt) { 'none' } else { $latestTitleCompletedAt.ToString('o') })",
        "cooldown_source_kind=$($cooldownSource.kind)",
        "cooldown_source=$($cooldownSource.name)",
        "cache_cooldown_ready=$($cacheCooldown.ready)",
        "cache_cooldown_ready_at=$(if ($null -eq $cacheCooldown.ready_at) { 'now' } else { $cacheCooldown.ready_at.ToString('o') })",
        "cache_cooldown_remaining_seconds=$($cacheCooldown.remaining_seconds)",
        "required_compile_workers=2",
        "spu_native_object_cache=$spuNativeObjectCache",
        "spu_cache_preload_limit=$spuCachePreloadLimit",
        "spu_cache_compile_budget_ms=$spuCacheCompileBudgetMs",
        "cache_worker_affinity_mask=$cacheWorkerAffinityMask",
        "spu_cache_worker_limit=$spuCacheWorkerLimit",
        "require_validated_cache_reuse=True",
        "minimum_required_reused_modules=$minimumRequiredReuse",
        "minimum_required_spu_native_objects=$minimumRequiredSpuNativeObjects",
        "launch_game=False",
        "force_stop=True",
        "progress_checkpoint=True"
    ) | Write-Output
    return
}

if (-not $cacheCooldown.ready) {
    throw "Cache cooldown refused before device contact: source=$($cooldownSource.kind) '$($cooldownSource.name)'; $($cacheCooldown.remaining_seconds) seconds remain until $($cacheCooldown.ready_at.ToString('o'))."
}

$adb = Resolve-ThorAdb
$deviceRows = @(& $adb devices 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed: $($deviceRows -join ' ')"
}
$onlineSerials = @(
    $deviceRows |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ -match '^(\S+)\s+device$' } |
        ForEach-Object { $Matches[1] }
)
if ($Serial -notin $onlineSerials) {
    throw "Pinned Thor '$Serial' is not online. Online devices: $($onlineSerials -join ', ')"
}
$env:ANDROID_SERIAL = $Serial

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$requestId = "cache-$stamp-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$captureDir = Join-Path $repoRoot "debug-captures\android-speed-sprint\$stamp-firmware-ppu-prewarm"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
$thermalLogPath = Join-Path $captureDir "thermal-guard.log"
$remoteLog = "/storage/emulated/0/Android/data/$package/files/cache/RPCSX.log"

function Get-ThorCapturedBody {
    param([string]$Path)

    return @(
        Get-Content -LiteralPath $Path |
            Where-Object { $_ -notmatch '^#' -and $_ -notmatch '^exit=' -and -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ThermalSection {
    param(
        [object[]]$Lines,
        [int]$StartIndex,
        [int]$EndIndex
    )

    if ($StartIndex -lt 0 -or $EndIndex -le ($StartIndex + 1)) {
        return @()
    }
    return @($Lines[($StartIndex + 1)..($EndIndex - 1)])
}

function Get-CachePrepareThermalSnapshot {
    $thermalZoneCommand = Get-ThorThermalZoneShellCommand
    $combinedCommand = 'echo __THOR_BATTERY__; dumpsys battery; echo __THOR_ZONES__; ' +
        $thermalZoneCommand + '; echo __THOR_HARDWARE__; dumpsys hardware_properties; echo __THOR_END__'
    $lines = @(Invoke-ThorAdbLines -Adb $adb -AdbArgs @("shell", $combinedCommand) -ScratchDir $captureDir -TimeoutSeconds 10)
    $batteryIndex = [Array]::IndexOf($lines, "__THOR_BATTERY__")
    $zonesIndex = [Array]::IndexOf($lines, "__THOR_ZONES__")
    $hardwareIndex = [Array]::IndexOf($lines, "__THOR_HARDWARE__")
    $endIndex = [Array]::IndexOf($lines, "__THOR_END__")
    if ($batteryIndex -lt 0 -or $zonesIndex -le $batteryIndex -or
        $hardwareIndex -le $zonesIndex -or $endIndex -le $hardwareIndex) {
        throw "Combined Thor thermal snapshot is incomplete."
    }

    return Get-ThorThermalGuardSnapshot `
        -BatteryLines (Get-ThermalSection $lines $batteryIndex $zonesIndex) `
        -ThermalZoneLines (Get-ThermalSection $lines $zonesIndex $hardwareIndex) `
        -HardwareLines (Get-ThermalSection $lines $hardwareIndex $endIndex)
}

function Add-ThermalSnapshot {
    param(
        [string]$Stage,
        [object]$Snapshot
    )

    $row = "captured=$(Get-Date -Format o) stage=$Stage " +
        "battery_temperature_c=$(Format-ThorTemperatureC $Snapshot.battery_temperature_c) " +
        "skin_temperature_c=$(Format-ThorTemperatureC $Snapshot.skin_temperature_c) " +
        "silicon_temperature_c=$(Format-ThorTemperatureC $Snapshot.silicon_temperature_c) " +
        "sources=$($Snapshot.source_summary)"
    $row | Out-File -LiteralPath $thermalLogPath -Append -Encoding UTF8
}

function Read-FreshLogcat {
    return @(
        Invoke-ThorAdbLines -Adb $adb -AdbArgs @("logcat", "-d", "-v", "threadtime") -ScratchDir $captureDir -TimeoutSeconds 10
    )
}

function Read-RecentLogcat {
    return @(
        Invoke-ThorAdbLines -Adb $adb -AdbArgs @("logcat", "-d", "-v", "threadtime", "-t", "500") -ScratchDir $captureDir -TimeoutSeconds 10
    )
}

$runFailure = $null
$success = $false
$accepted = $false
$nativeActivated = $false
$nativeCompleted = $false
$spuNativeActivated = $false
$spuNativeCompleted = $false
$spuNativeCacheEnabled = $false
$spuCachePreloadBounded = $false
$spuCacheBudgetEnabled = $false
$spuCacheAffinityMatched = $false
$spuCacheWorkerPoolMatched = $false
$spuCacheWorkerPoolRequested = 0
$spuCacheWorkerPoolWorkers = 0
$spuNativeLoadedObjects = 0
$spuWorkersBuiltPrograms = 0
$spuNativeObjectReuseFloorSatisfied = $minimumRequiredSpuNativeObjects -eq 0
$spuPropertiesReset = $false
$nativeProcessDied = $false
$nativeFatal = $false
$progressCheckpoint = $false
$sourceResolved = $false
$namedWorkerActivated = $false
$cacheProgress = Get-ThorCachePrepareProgress -NativeText ""
$reuseFloorSatisfied = $false
$callbackFinished = $false
$nativeText = ""
$deviceApkHash = ""
$pidBefore = @()
$pidAfter = @()
$preflight = @()
$runtimeSnapshots = 0
$runtimeSiliconTemperaturesC = @()
$peakSiliconC = $null
$stopwatch = [Diagnostics.Stopwatch]::new()

try {
    Invoke-ThorAdbText $adb $captureDir "force-stop-before.txt" @("shell", "am force-stop $package") -AllowFailure | Out-Null
    $pidBeforePath = Invoke-ThorAdbText $adb $captureDir "pid-before.txt" @("shell", "pidof $package") -AllowFailure
    $pidBefore = @(Get-ThorCapturedBody $pidBeforePath)
    if ($pidBefore.Count -ne 0) {
        throw "RPCSX PID remained active before cache preparation: $($pidBefore -join ' ')"
    }

    $packagePathCapture = Invoke-ThorAdbText $adb $captureDir "package-path.txt" @("shell", "pm path $package")
    $packageRows = @(Get-ThorCapturedBody $packagePathCapture)
    $baseApkRows = @($packageRows | Where-Object { $_ -match '^package:(/.+/base[.]apk)$' })
    if ($baseApkRows.Count -ne 1) {
        throw "Expected exactly one installed base.apk for $package; found $($baseApkRows.Count)."
    }
    $remoteApk = $baseApkRows[0] -replace '^package:', ''
    $deviceHashPath = Invoke-ThorAdbText $adb $captureDir "installed-base-apk-sha256.txt" @("shell", "sha256sum '$remoteApk'")
    $deviceHashText = (Get-ThorCapturedBody $deviceHashPath) -join "`n"
    $deviceHashMatch = [regex]::Match($deviceHashText, '(?i)\b([0-9a-f]{64})\b')
    if (-not $deviceHashMatch.Success) {
        throw "Could not parse installed base.apk SHA-256."
    }
    $deviceApkHash = $deviceHashMatch.Groups[1].Value.ToUpperInvariant()
    if ($deviceApkHash -ne $expectedApkHash) {
        throw "Installed APK mismatch: expected $expectedApkHash, got $deviceApkHash."
    }

    Invoke-ThorAdbText $adb $captureDir "cache-worker-affinity-set.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask $cacheWorkerAffinityMask") | Out-Null
    $cacheAffinityEffectivePath = Invoke-ThorAdbText $adb $captureDir "cache-worker-affinity-effective.txt" @("shell", "getprop debug.rpcsx.thor.cache_worker_affinity_mask")
    Invoke-ThorAdbText $adb $captureDir "spu-native-object-cache-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache $spuNativeObjectCache") | Out-Null
    $spuNativeEffectivePath = Invoke-ThorAdbText $adb $captureDir "spu-native-object-cache-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_native_object_cache")
    Invoke-ThorAdbText $adb $captureDir "spu-cache-preload-limit-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit $spuCachePreloadLimit") | Out-Null
    $spuPreloadEffectivePath = Invoke-ThorAdbText $adb $captureDir "spu-cache-preload-limit-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_preload_limit")
    Invoke-ThorAdbText $adb $captureDir "spu-cache-compile-budget-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms $spuCacheCompileBudgetMs") | Out-Null
    $spuBudgetEffectivePath = Invoke-ThorAdbText $adb $captureDir "spu-cache-compile-budget-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_compile_budget_ms")
    Invoke-ThorAdbText $adb $captureDir "spu-cache-worker-limit-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_worker_limit $spuCacheWorkerLimit") | Out-Null
    $spuWorkerLimitEffectivePath = Invoke-ThorAdbText $adb $captureDir "spu-cache-worker-limit-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_worker_limit")
    $cacheAffinityEffective = (Get-ThorCapturedBody $cacheAffinityEffectivePath) -join ""
    $spuNativeEffective = (Get-ThorCapturedBody $spuNativeEffectivePath) -join ""
    $spuPreloadEffective = (Get-ThorCapturedBody $spuPreloadEffectivePath) -join ""
    $spuBudgetEffective = (Get-ThorCapturedBody $spuBudgetEffectivePath) -join ""
    $spuWorkerLimitEffective = (Get-ThorCapturedBody $spuWorkerLimitEffectivePath) -join ""
    if ($cacheAffinityEffective -ne [string]$cacheWorkerAffinityMask -or
        $spuNativeEffective -ne $spuNativeObjectCache -or
        $spuPreloadEffective -ne [string]$spuCachePreloadLimit -or
        $spuBudgetEffective -ne [string]$spuCacheCompileBudgetMs -or
        $spuWorkerLimitEffective -ne [string]$spuCacheWorkerLimit) {
        throw "SPU cache-preparation properties did not apply exactly."
    }

    Write-ThorLaunchPowerState -Adb $adb -CaptureDir $captureDir -Prefix "prelaunch"
    for ($index = 1; $index -le $preflightSamples; $index++) {
        $snapshot = Get-CachePrepareThermalSnapshot
        $preflight += $snapshot
        Add-ThermalSnapshot -Stage "preflight-$index-of-$preflightSamples" -Snapshot $snapshot
        $violation = Get-ThorThermalGuardViolation `
            -Snapshot $snapshot `
            -MaxBatteryTemperatureC $maxBatteryTemperatureC `
            -MaxSkinTemperatureC $maxSkinTemperatureC `
            -MaxSiliconTemperatureC $maxLaunchSiliconTemperatureC
        if ($null -ne $violation) {
            throw "Preflight refused: $($violation.message)"
        }
        if ($index -lt $preflightSamples) {
            Start-Sleep -Seconds $preflightIntervalSeconds
        }
    }
    $preflightSilicon = @($preflight | ForEach-Object { [double]$_.silicon_temperature_c })
    $preflightRiseC = $preflightSilicon[-1] - $preflightSilicon[0]
    if ($preflightRiseC -gt $maxPreflightRiseC) {
        throw "Preflight refused: silicon rose $($preflightRiseC.ToString('0.0')) C, above the $maxPreflightRiseC C limit."
    }

    Invoke-ThorAdbText $adb $captureDir "logcat-clear.txt" @("logcat", "-c") | Out-Null
    $quotedGamePath = ConvertTo-ThorRemoteShellLiteral -Value $GamePath
    $launchArgs = @(
        "shell", "am", "start", "-W",
        "-n", "$package/net.rpcsx.MainActivity",
        "-a", $intentAction,
        "--es", "path", $quotedGamePath,
        "--es", "titleId", $titleId,
        "--es", "thorCachePrepareRequestId", $requestId,
        "--ez", "thorRequireManagedProfile", "true"
    )
    Invoke-ThorAdbText $adb $captureDir "intent-start.txt" $launchArgs -TimeoutSeconds 20 | Out-Null
    $stopwatch.Start()

    while ($stopwatch.Elapsed.TotalSeconds -lt $MaxSeconds) {
        $snapshot = Get-CachePrepareThermalSnapshot
        $runtimeSnapshots++
        Add-ThermalSnapshot -Stage "runtime-$runtimeSnapshots" -Snapshot $snapshot
        if ($null -ne $snapshot.silicon_temperature_c) {
            $runtimeSiliconTemperaturesC += [double]$snapshot.silicon_temperature_c
            if ($null -eq $peakSiliconC -or [double]$snapshot.silicon_temperature_c -gt $peakSiliconC) {
                $peakSiliconC = [double]$snapshot.silicon_temperature_c
            }
        }

        $hardViolation = Get-ThorThermalGuardViolation `
            -Snapshot $snapshot `
            -MaxBatteryTemperatureC $maxBatteryTemperatureC `
            -MaxSkinTemperatureC $maxSkinTemperatureC `
            -MaxSiliconTemperatureC $maxSiliconTemperatureC
        if ($null -ne $hardViolation) {
            throw "Runtime thermal stop: $($hardViolation.message)"
        }
        $runtimeDecision = Get-ThorThermalRuntimeGuardDecision `
            -Snapshot $snapshot `
            -MaxSiliconTemperatureC $maxSiliconTemperatureC `
            -StopHeadroomC $runtimeStopHeadroomC `
            -ProbeWindowC $runtimeProbeWindowC
        if ($null -ne $runtimeDecision -and $runtimeDecision.action -eq "stop") {
            throw "Runtime thermal stop: $($runtimeDecision.message)"
        }
        if ($null -ne $runtimeDecision -and $runtimeDecision.action -eq "confirm") {
            $confirm = Get-CachePrepareThermalSnapshot
            $runtimeSnapshots++
            Add-ThermalSnapshot -Stage "runtime-$runtimeSnapshots-confirm" -Snapshot $confirm
            if ($null -ne $confirm.silicon_temperature_c) {
                $runtimeSiliconTemperaturesC += [double]$confirm.silicon_temperature_c
                if ($null -eq $peakSiliconC -or [double]$confirm.silicon_temperature_c -gt $peakSiliconC) {
                    $peakSiliconC = [double]$confirm.silicon_temperature_c
                }
            }
            $confirmDecision = Get-ThorThermalRuntimeGuardDecision `
                -Snapshot $confirm `
                -MaxSiliconTemperatureC $maxSiliconTemperatureC `
                -StopHeadroomC $runtimeStopHeadroomC `
                -ProbeWindowC $runtimeProbeWindowC `
                -Confirmed
            if ($null -ne $confirmDecision -and $confirmDecision.action -eq "stop") {
                throw "Runtime thermal stop: $($confirmDecision.message)"
            }
        }

        # Do not let log collection plus the fixed poll sleep extend a bounded
        # cache round after its useful atomic writes have already completed.
        if ($stopwatch.Elapsed.TotalSeconds -ge $MaxSeconds) {
            break
        }

        $logcat = Read-RecentLogcat
        $logText = $logcat -join "`n"
        if ($logText.Contains("Thor debug cache preparation rejected: request=$requestId")) {
            throw "Cache preparation intent was rejected; inspect logcat-full.txt."
        }
        $accepted = $accepted -or $logText.Contains("Thor debug cache preparation accepted: request=$requestId titleId=$titleId")
        $callbackFinished = $callbackFinished -or $logText.Contains("Thor debug cache preparation finished: request=$requestId titleId=$titleId")
        if (Test-ThorCachePrepareNativeProcessDeath -LogText $logText -Package $package) {
            $nativeProcessDied = $true
            throw "Cache preparation native process died before completion; inspect logcat-full.txt."
        }
        if (-not $accepted -and $stopwatch.Elapsed.TotalSeconds -ge $acceptDeadlineSeconds) {
            throw "Cache preparation intent was not accepted within $acceptDeadlineSeconds seconds."
        }
        if ($accepted -and $callbackFinished) {
            $success = $true
            break
        }

        $remainingMilliseconds = [Math]::Max(
            0,
            [Math]::Ceiling(($MaxSeconds - $stopwatch.Elapsed.TotalSeconds) * 1000.0)
        )
        if ($remainingMilliseconds -le 0) {
            break
        }
        Start-Sleep -Milliseconds ([Math]::Min($pollIntervalSeconds * 1000, $remainingMilliseconds))
    }

    if (-not $success) {
        throw $timeoutFailureMessage
    }
} catch {
    $runFailure = $_
} finally {
    $stopwatch.Stop()
    Invoke-ThorAdbText $adb $captureDir "force-stop-after.txt" @("shell", "am force-stop $package") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "cache-worker-affinity-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "spu-native-object-cache-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "spu-cache-preload-limit-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "spu-cache-compile-budget-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "spu-cache-worker-limit-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_worker_limit 0") -AllowFailure | Out-Null
    $cacheAffinityResetPath = Invoke-ThorAdbText $adb $captureDir "cache-worker-affinity-reset-effective.txt" @("shell", "getprop debug.rpcsx.thor.cache_worker_affinity_mask") -AllowFailure
    $spuNativeResetPath = Invoke-ThorAdbText $adb $captureDir "spu-native-object-cache-reset-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_native_object_cache") -AllowFailure
    $spuPreloadResetPath = Invoke-ThorAdbText $adb $captureDir "spu-cache-preload-limit-reset-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_preload_limit") -AllowFailure
    $spuBudgetResetPath = Invoke-ThorAdbText $adb $captureDir "spu-cache-compile-budget-reset-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_compile_budget_ms") -AllowFailure
    $spuWorkerLimitResetPath = Invoke-ThorAdbText $adb $captureDir "spu-cache-worker-limit-reset-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_worker_limit") -AllowFailure
    $spuPropertiesReset =
        ((Get-ThorCapturedBody $cacheAffinityResetPath) -join "") -eq "0" -and
        ((Get-ThorCapturedBody $spuNativeResetPath) -join "") -eq "off" -and
        ((Get-ThorCapturedBody $spuPreloadResetPath) -join "") -eq "0" -and
        ((Get-ThorCapturedBody $spuBudgetResetPath) -join "") -eq "0" -and
        ((Get-ThorCapturedBody $spuWorkerLimitResetPath) -join "") -eq "0"
    $pidAfterPath = Invoke-ThorAdbText $adb $captureDir "pid-after.txt" @("shell", "pidof $package") -AllowFailure
    $pidAfter = @(Get-ThorCapturedBody $pidAfterPath)
    $finalLogcat = Read-FreshLogcat
    $finalLogcat | Set-Content -LiteralPath (Join-Path $captureDir "logcat-full.txt") -Encoding UTF8
    $requestReachedApp = ($finalLogcat -join "`n").Contains($requestId)
    if ($requestReachedApp) {
        [void](Copy-ThorAdbFile -Adb $adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteLog -LocalName "RPCSX.log")
        $nativeLogPath = Join-Path $captureDir "RPCSX.log"
        if (Test-Path -LiteralPath $nativeLogPath -PathType Leaf) {
            $nativeText = Get-Content -LiteralPath $nativeLogPath -Raw
            $nativeActivated = $nativeText.Contains(
                "Thor PPU cache preparation activated: title=$titleId"
            )
            $nativeCompleted = $nativeText.Contains(
                "Thor PPU cache preparation completed: title=$titleId"
            )
            $spuActivationMarker = "Thor SPU native-object cache preparation activated: title=$titleId"
            $spuCompletionMarker = "Thor SPU native-object cache preparation completed: title=$titleId"
            $spuActivationLogIndex = $nativeText.IndexOf($spuActivationMarker, [StringComparison]::Ordinal)
            $spuCompletionLogIndex = $nativeText.IndexOf($spuCompletionMarker, [StringComparison]::Ordinal)
            $spuNativeActivated = $spuActivationLogIndex -ge 0
            $spuNativeCompleted = $spuCompletionLogIndex -gt $spuActivationLogIndex
            if ($spuNativeCompleted) {
                $spuPhaseText = $nativeText.Substring(
                    $spuActivationLogIndex,
                    $spuCompletionLogIndex - $spuActivationLogIndex
                )
                $spuNativeCacheEnabled = $spuPhaseText.Contains(
                    "Thor SPU native-object cache enabled for startup LLVM objects:"
                )
                $spuCachePreloadBounded = $spuPhaseText.Contains(
                    "Thor SPU cache preload limit: $spuCachePreloadLimit of "
                )
                $spuCacheBudgetEnabled = $spuPhaseText.Contains(
                    "Thor SPU cache compile budget enabled for BLUS30161: $spuCacheCompileBudgetMs ms."
                )
                $spuCacheAffinityMatched = $spuPhaseText.Contains(
                    "Thor SPU cache-worker affinity enabled: requested=0x7, effective=0x7."
                )
                $spuWorkerPoolMatch = [regex]::Match(
                    $spuPhaseText,
                    'Thor SPU cache-worker pool matched to affinity: requested=([0-9]+), workers=([0-9]+), mask=0x7[.]'
                )
                if ($spuWorkerPoolMatch.Success) {
                    $spuCacheWorkerPoolRequested = [int]$spuWorkerPoolMatch.Groups[1].Value
                    $spuCacheWorkerPoolWorkers = [int]$spuWorkerPoolMatch.Groups[2].Value
                    $spuCacheWorkerPoolMatched =
                        $spuCacheWorkerPoolRequested -ge $spuCacheWorkerLimit -and
                        $spuCacheWorkerPoolWorkers -eq $spuCacheWorkerLimit
                }
                $spuNativeLoadedObjects = ([regex]::Matches(
                    $spuPhaseText,
                    '(?m)LLVM: Loaded module: [^\r\n]+[.]obj\r?$'
                )).Count
                $spuBuiltMatch = [regex]::Match(
                    $spuPhaseText,
                    'SPU Runtime: Workers built ([0-9]+) programs[.]'
                )
                if ($spuBuiltMatch.Success) {
                    $spuWorkersBuiltPrograms = [int]$spuBuiltMatch.Groups[1].Value
                }
            }
            $sourceResolved = $nativeText.Contains(
                "Thor PPU cache source resolved: title=$titleId, source=iso"
            )
            $namedWorkerActivated = $nativeText.Contains(
                "Thor PPU LLVM compile-worker affinity enabled: requested=0x7, effective=0x7."
            )
            $nativeFatal = Test-ThorCachePrepareNativeFatal -NativeText $nativeText
            $cacheProgress = Get-ThorCachePrepareProgress -NativeText $nativeText
        }
    } else {
        "RPCSX.log was not collected because the current request ID never reached app logcat; an existing remote log may be stale." |
            Set-Content -LiteralPath (Join-Path $captureDir "RPCSX-log-not-collected.txt") -Encoding UTF8
    }
    $postStopSnapshot = Get-CachePrepareThermalSnapshot
    Add-ThermalSnapshot -Stage "post-stop" -Snapshot $postStopSnapshot
}

if ($pidAfter.Count -ne 0 -and $null -eq $runFailure) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "RPCSX PID remained active after force-stop: $($pidAfter -join ' ')"
    )
}
if (-not $spuPropertiesReset -and $null -eq $runFailure) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "SPU cache-preparation properties did not reset exactly after force-stop."
    )
}

$finalText = $finalLogcat -join "`n"
$nativeProcessDied = $nativeProcessDied -or
    (Test-ThorCachePrepareNativeProcessDeath -LogText $finalText -Package $package)
$acceptedMarker = "Thor debug cache preparation accepted: request=$requestId titleId=$titleId"
$activationMarker = "Thor PPU cache preparation activated: title=$titleId"
$completionMarker = "Thor PPU cache preparation completed: title=$titleId"
$spuActivationMarker = "Thor SPU native-object cache preparation activated: title=$titleId"
$spuCompletionMarker = "Thor SPU native-object cache preparation completed: title=$titleId"
$finishedMarker = "Thor debug cache preparation finished: request=$requestId titleId=$titleId"
$acceptedIndex = $finalText.IndexOf($acceptedMarker, [StringComparison]::Ordinal)
$activationIndex = $nativeText.IndexOf($activationMarker, [StringComparison]::Ordinal)
$completionIndex = $nativeText.IndexOf($completionMarker, [StringComparison]::Ordinal)
$spuActivationIndex = $nativeText.IndexOf($spuActivationMarker, [StringComparison]::Ordinal)
$spuCompletionIndex = $nativeText.IndexOf($spuCompletionMarker, [StringComparison]::Ordinal)
$finishedIndex = $finalText.IndexOf($finishedMarker, [StringComparison]::Ordinal)

if ($nativeProcessDied) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "Cache preparation native process died before completion; inspect logcat-full.txt."
    )
}
if ($nativeFatal) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "Cache preparation native log contains a fatal marker; inspect RPCSX.log."
    )
}
$gameBootDetected = $finalText.Contains("Thor debug boot accepted:") -or
    $finalText.Contains("net.rpcsx.RPCSXActivity")
if ($gameBootDetected) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "Cache preparation unexpectedly entered the game-boot activity path."
    )
}
$spuNativeObjectReuseFloorSatisfied =
    $spuNativeLoadedObjects -ge $minimumRequiredSpuNativeObjects

if ($null -eq $runFailure -and
    ($acceptedIndex -lt 0 -or $finishedIndex -le $acceptedIndex -or
        $activationIndex -lt 0 -or $completionIndex -le $activationIndex -or
        $spuActivationIndex -le $completionIndex -or
        $spuCompletionIndex -le $spuActivationIndex -or
        -not $spuNativeCacheEnabled -or -not $spuCachePreloadBounded -or
        -not $spuCacheBudgetEnabled -or -not $spuCacheAffinityMatched -or
        -not $spuCacheWorkerPoolMatched -or
        -not $spuNativeObjectReuseFloorSatisfied)) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "PPU/SPU cache-preparation evidence is incomplete, unsafe, or internally out of order."
    )
}

$timedOutCleanly = $runFailure -is [System.Management.Automation.ErrorRecord] -and
    $runFailure.Exception.Message -eq $timeoutFailureMessage
$reuseFloorSatisfied = $cacheProgress.reused_modules -ge $minimumRequiredReuse
if ($timedOutCleanly -and $accepted -and $nativeActivated -and
    -not $nativeCompleted -and -not $callbackFinished -and
    -not $nativeProcessDied -and -not $nativeFatal -and -not $gameBootDetected -and
    $pidAfter.Count -eq 0 -and $sourceResolved -and $namedWorkerActivated -and
    $cacheProgress.has_reuse -and $reuseFloorSatisfied -and $cacheProgress.has_progress -and
    $cacheProgress.compile_worker_count -ge 2) {
    $progressCheckpoint = $true
    $runFailure = $null
}

$failureMessage = if ($null -eq $runFailure) {
    "none"
} elseif ($runFailure -is [System.Management.Automation.ErrorRecord]) {
    $runFailure.Exception.Message
} else {
    $runFailure.Message
}
$status = if ($null -ne $runFailure) {
    "failed"
} elseif ($progressCheckpoint) {
    "cache-progress-checkpoint"
} else {
    "cache-prepared-exact-no-game-boot"
}
$preflightSummary = if ($preflight.Count -eq $preflightSamples) {
    (@($preflight | ForEach-Object { Format-ThorTemperatureC $_.silicon_temperature_c }) -join " -> ") + " C"
} else {
    "incomplete"
}
$initialProgressSummary = if ($cacheProgress.initial_progress_observed) {
    "$($cacheProgress.initial_module)/$($cacheProgress.initial_total_modules)"
} elseif ($cacheProgress.initial_workload_complete) {
    "not emitted; firmware scan start proves phase completion"
} else {
    "not observed"
}
$runtimeProbeSiliconC = $maxSiliconTemperatureC - $runtimeProbeWindowC
$runtimeThermalSummary = Get-ThorCachePrepareThermalSummary `
    -SiliconTemperaturesC $runtimeSiliconTemperaturesC `
    -WarmThresholdC $runtimeWarmTelemetryC `
    -ProbeThresholdC $runtimeProbeSiliconC
@(
    "# Thor Firmware PPU Cache Preparation",
    "",
    "- Created: $(Get-Date -Format o)",
    "- Status: $status",
    "- Device serial: $Serial",
    "- Package: $package",
    "- Title ID: $titleId",
    "- Game path: $GamePath",
    "- Request ID: $requestId",
    "- Intent action: $intentAction",
    "- Expected/host APK SHA-256: $expectedApkHash",
    "- Installed APK SHA-256: $deviceApkHash",
    "- Preflight silicon: $preflightSummary",
    "- Runtime bound seconds: $MaxSeconds",
    "- Runtime elapsed seconds: $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 3))",
    "- Runtime thermal samples: $($runtimeThermalSummary.sample_count)",
    "- Runtime average silicon C: $(Format-ThorTemperatureC $runtimeThermalSummary.average_c)",
    "- Runtime minimum silicon C: $(Format-ThorTemperatureC $runtimeThermalSummary.minimum_c)",
    "- Runtime peak silicon C: $(Format-ThorTemperatureC $peakSiliconC)",
    "- Runtime samples at or above $runtimeWarmTelemetryC C: $($runtimeThermalSummary.at_or_above_warm)",
    "- Runtime samples at or above $runtimeProbeSiliconC C: $($runtimeThermalSummary.at_or_above_probe)",
    "- Post-stop battery C: $(Format-ThorTemperatureC $postStopSnapshot.battery_temperature_c)",
    "- Post-stop skin C: $(Format-ThorTemperatureC $postStopSnapshot.skin_temperature_c)",
    "- Post-stop silicon C: $(Format-ThorTemperatureC $postStopSnapshot.silicon_temperature_c)",
    "- Accepted: $accepted",
    "- Native activated: $nativeActivated",
    "- Native completed: $nativeCompleted",
    "- SPU native activated: $spuNativeActivated",
    "- SPU native completed: $spuNativeCompleted",
    "- SPU native cache enabled: $spuNativeCacheEnabled",
    "- SPU preload bounded: $spuCachePreloadBounded",
    "- SPU compile budget enabled: $spuCacheBudgetEnabled",
    "- SPU cache affinity matched: $spuCacheAffinityMatched",
    "- SPU cache worker pool matched: $spuCacheWorkerPoolMatched",
    "- SPU cache worker pool requested/workers: $spuCacheWorkerPoolRequested/$spuCacheWorkerPoolWorkers",
    "- SPU native objects loaded: $spuNativeLoadedObjects",
    "- SPU workers built programs: $spuWorkersBuiltPrograms",
    "- Minimum required SPU native objects loaded: $minimumRequiredSpuNativeObjects",
    "- SPU native-object reuse floor satisfied: $spuNativeObjectReuseFloorSatisfied",
    "- SPU properties reset: $spuPropertiesReset",
    "- Native process died: $nativeProcessDied",
    "- Native fatal: $nativeFatal",
    "- Callback finished: $callbackFinished",
    "- Source resolved: $sourceResolved",
    "- Named worker activated: $namedWorkerActivated",
    "- Distinct compile workers: $($cacheProgress.compile_worker_count)",
    "- Compile worker names: $(if ($cacheProgress.compile_worker_count) { $cacheProgress.compile_worker_names -join ', ' } else { 'none' })",
    "- Progress checkpoint: $progressCheckpoint",
    "- Compiled modules this round: $($cacheProgress.compiled_modules)",
    "- Loaded modules this round: $($cacheProgress.loaded_modules)",
    "- Existing validated modules this round: $($cacheProgress.existing_modules)",
    "- Reused modules this round: $($cacheProgress.reused_modules)",
    "- Cache reuse observed: $($cacheProgress.has_reuse)",
    "- Minimum required reused modules: $minimumRequiredReuse",
    "- Reuse floor satisfied: $reuseFloorSatisfied",
    "- Initial EBOOT module progress: $initialProgressSummary",
    "- Initial EBOOT workload complete: $($cacheProgress.initial_workload_complete)",
    "- Firmware scan progress: $($cacheProgress.latest_file)/$($cacheProgress.total_files)",
    "- Remaining firmware files to scan: $($cacheProgress.remaining_files)",
    "- Latest discovered module progress: $($cacheProgress.latest_module)/$($cacheProgress.total_modules)",
    "- Known remaining modules in scanned workload: $($cacheProgress.remaining_modules)",
    "- PID before: $(if ($pidBefore.Count) { $pidBefore -join ' ' } else { 'absent' })",
    "- PID after: $(if ($pidAfter.Count) { $pidAfter -join ' ' } else { 'absent' })",
    "- Game boot: no",
    "- Failure: $failureMessage"
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

if ($null -ne $runFailure) {
    throw "Thor cache preparation failed; see ${captureDir}: $failureMessage"
}

if ($progressCheckpoint) {
    Write-Output "Thor cache preparation checkpoint: $captureDir"
    Write-Output "Committed cache progress was preserved with RPCSX PID absent and no game boot."
    return
}

Write-Output "Thor cache preparation capture: $captureDir"
Write-Output "Cache preparation completed with RPCSX PID absent and no game boot."
