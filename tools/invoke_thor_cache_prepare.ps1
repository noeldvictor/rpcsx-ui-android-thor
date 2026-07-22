param(
    [ValidateSet("Status", "Run")]
    [string]$Action = "Status",
    [string]$Serial = "c3ca0370",
    [string]$CandidatePath = "",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [ValidateRange(30, 180)]
    [int]$MaxSeconds = 150
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"
. "$PSScriptRoot\thor_cache_prepare_process_health.ps1"

$expectedSerial = "c3ca0370"
$titleId = "BLUS30161"
$package = "net.rpcsx.easy"
$intentAction = "net.rpcsx.THOR_DEBUG_PREPARE_CACHE"
$maxBatteryTemperatureC = 34.0
$maxSkinTemperatureC = 40.0
$maxLaunchSiliconTemperatureC = 35.0
$maxPreflightRiseC = 1.0
$maxSiliconTemperatureC = 72.0
$runtimeStopHeadroomC = 4.0
$runtimeProbeWindowC = 16.0
$preflightSamples = 3
$preflightIntervalSeconds = 2
$pollIntervalSeconds = 2
$acceptDeadlineSeconds = 15

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
        "launch_game=False",
        "force_stop=True"
    ) | Write-Output
    return
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

$runFailure = $null
$success = $false
$accepted = $false
$nativeActivated = $false
$nativeCompleted = $false
$nativeProcessDied = $false
$callbackFinished = $false
$nativeText = ""
$deviceApkHash = ""
$pidBefore = @()
$pidAfter = @()
$preflight = @()
$runtimeSnapshots = 0
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
        if ($null -ne $snapshot.silicon_temperature_c -and
            ($null -eq $peakSiliconC -or [double]$snapshot.silicon_temperature_c -gt $peakSiliconC)) {
            $peakSiliconC = [double]$snapshot.silicon_temperature_c
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
            if ($null -ne $confirm.silicon_temperature_c -and
                ($null -eq $peakSiliconC -or [double]$confirm.silicon_temperature_c -gt $peakSiliconC)) {
                $peakSiliconC = [double]$confirm.silicon_temperature_c
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

        $logcat = Read-FreshLogcat
        $logText = $logcat -join "`n"
        if ($logText.Contains("Thor debug cache preparation rejected: request=$requestId")) {
            throw "Cache preparation intent was rejected; inspect logcat-full.txt."
        }
        $accepted = $logText.Contains("Thor debug cache preparation accepted: request=$requestId titleId=$titleId")
        $callbackFinished = $logText.Contains("Thor debug cache preparation finished: request=$requestId titleId=$titleId")
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

        Start-Sleep -Seconds $pollIntervalSeconds
    }

    if (-not $success) {
        throw "Cache preparation did not complete inside the $MaxSeconds-second bound."
    }
} catch {
    $runFailure = $_
} finally {
    $stopwatch.Stop()
    Invoke-ThorAdbText $adb $captureDir "force-stop-after.txt" @("shell", "am force-stop $package") -AllowFailure | Out-Null
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

$finalText = $finalLogcat -join "`n"
$acceptedMarker = "Thor debug cache preparation accepted: request=$requestId titleId=$titleId"
$activationMarker = "Thor PPU cache preparation activated: title=$titleId"
$completionMarker = "Thor PPU cache preparation completed: title=$titleId"
$finishedMarker = "Thor debug cache preparation finished: request=$requestId titleId=$titleId"
$acceptedIndex = $finalText.IndexOf($acceptedMarker, [StringComparison]::Ordinal)
$activationIndex = $nativeText.IndexOf($activationMarker, [StringComparison]::Ordinal)
$completionIndex = $nativeText.IndexOf($completionMarker, [StringComparison]::Ordinal)
$finishedIndex = $finalText.IndexOf($finishedMarker, [StringComparison]::Ordinal)
if ($null -eq $runFailure -and
    ($acceptedIndex -lt 0 -or $finishedIndex -le $acceptedIndex -or
        $activationIndex -lt 0 -or $completionIndex -le $activationIndex)) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "Logcat accepted/finished or native activated/completed evidence is incomplete or internally out of order."
    )
}
if ($null -eq $runFailure -and
    ($finalText.Contains("Thor debug boot accepted:") -or $finalText.Contains("net.rpcsx.RPCSXActivity"))) {
    $runFailure = [System.Management.Automation.RuntimeException]::new(
        "Cache preparation unexpectedly entered the game-boot activity path."
    )
}

$status = if ($null -eq $runFailure) { "cache-prepared-exact-no-game-boot" } else { "failed" }
$preflightSummary = if ($preflight.Count -eq $preflightSamples) {
    (@($preflight | ForEach-Object { Format-ThorTemperatureC $_.silicon_temperature_c }) -join " -> ") + " C"
} else {
    "incomplete"
}
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
    "- Runtime peak silicon C: $(Format-ThorTemperatureC $peakSiliconC)",
    "- Post-stop battery C: $(Format-ThorTemperatureC $postStopSnapshot.battery_temperature_c)",
    "- Post-stop skin C: $(Format-ThorTemperatureC $postStopSnapshot.skin_temperature_c)",
    "- Post-stop silicon C: $(Format-ThorTemperatureC $postStopSnapshot.silicon_temperature_c)",
    "- Accepted: $accepted",
    "- Native activated: $nativeActivated",
    "- Native completed: $nativeCompleted",
    "- Native process died: $nativeProcessDied",
    "- Callback finished: $callbackFinished",
    "- PID before: $(if ($pidBefore.Count) { $pidBefore -join ' ' } else { 'absent' })",
    "- PID after: $(if ($pidAfter.Count) { $pidAfter -join ' ' } else { 'absent' })",
    "- Game boot: no",
    "- Failure: $(if ($null -eq $runFailure) { 'none' } else { $runFailure.Exception.Message })"
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

if ($null -ne $runFailure) {
    throw "Thor cache preparation failed; see ${captureDir}: $($runFailure.Exception.Message)"
}

Write-Output "Thor cache preparation capture: $captureDir"
Write-Output "Cache preparation completed with RPCSX PID absent and no game boot."
