param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedSha256,
    [Parameter(Mandatory = $true)]
    [string]$CoolGateCaptureDir,
    [ValidateRange(1, 60)]
    [int]$CoolGateMaxAgeMinutes = 15,
    [string]$Serial = "",
    [string]$Package = "net.rpcsx.easy",
    [string]$Label = "apk-no-launch-install"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$repoRoot = Get-ThorRepoRoot
$adb = Resolve-ThorAdb
$requestedApk = if ([IO.Path]::IsPathRooted($ApkPath)) {
    $ApkPath
} else {
    Join-Path $repoRoot $ApkPath
}
$resolvedApk = (Resolve-Path -LiteralPath $requestedApk).Path
$requestedCoolGate = if ([IO.Path]::IsPathRooted($CoolGateCaptureDir)) {
    $CoolGateCaptureDir
} else {
    Join-Path $repoRoot $CoolGateCaptureDir
}
$resolvedCoolGate = (Resolve-Path -LiteralPath $requestedCoolGate).Path
$expectedHash = $ExpectedSha256.ToUpperInvariant()
$hostHash = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash

if ($hostHash -ne $expectedHash) {
    throw "Host APK hash mismatch: expected $expectedHash, got $hostHash"
}

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

if ([string]::IsNullOrWhiteSpace($Serial)) {
    if ($onlineSerials.Count -ne 1) {
        throw "Expected exactly one online Android device; found: $($onlineSerials -join ', ')"
    }
    $Serial = $onlineSerials[0]
} elseif ($Serial -notin $onlineSerials) {
    throw "Requested Android device '$Serial' is not online. Online devices: $($onlineSerials -join ', ')"
}

$env:ANDROID_SERIAL = $Serial
$coolGateReadmePath = Join-Path $resolvedCoolGate "README.md"
$coolGateThermalPath = Join-Path $resolvedCoolGate "thermal-guard.log"
if (-not (Test-Path -LiteralPath $coolGateReadmePath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $coolGateThermalPath -PathType Leaf)) {
    throw "Cool gate capture must contain README.md and thermal-guard.log: $resolvedCoolGate"
}

$coolGateAge = (Get-Date) - (Get-Item -LiteralPath $coolGateThermalPath).LastWriteTime
if ($coolGateAge.TotalMinutes -lt 0 -or $coolGateAge.TotalMinutes -gt $CoolGateMaxAgeMinutes) {
    throw "Cool gate is stale: age $([math]::Round($coolGateAge.TotalMinutes, 2)) minutes exceeds $CoolGateMaxAgeMinutes minutes."
}

$coolGateReadme = Get-Content -LiteralPath $coolGateReadmePath -Raw
$requiredGateMetadata = @(
    "- Device serial: $Serial",
    "- Package: $Package",
    "- BootGame: False",
    "- ForceStop: True"
)
foreach ($metadata in $requiredGateMetadata) {
    if (-not $coolGateReadme.Contains($metadata)) {
        throw "Cool gate metadata mismatch or unsafe gate: missing '$metadata'."
    }
}

$coolGateSamples = @(
    Get-Content -LiteralPath $coolGateThermalPath |
        ForEach-Object {
            $match = [regex]::Match($_, 'stage=pre-run-(\d+)-of-(\d+).*?silicon_temperature_c=([0-9]+(?:[.][0-9]+)?)')
            if ($match.Success) {
                [pscustomobject]@{
                    Index = [int]$match.Groups[1].Value
                    Count = [int]$match.Groups[2].Value
                    TemperatureC = [double]::Parse($match.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture)
                }
            }
        }
)
if ($coolGateSamples.Count -ne 3 -or
    @($coolGateSamples | Where-Object { $_.Count -ne 3 }).Count -ne 0 -or
    (($coolGateSamples | Sort-Object Index | ForEach-Object Index) -join ',') -ne '1,2,3') {
    throw "Cool gate must contain exactly three ordered pre-run samples."
}

$orderedGateSamples = @($coolGateSamples | Sort-Object Index)
$coolGateMaximumC = ($orderedGateSamples | Measure-Object -Property TemperatureC -Maximum).Maximum
$coolGateRiseC = $orderedGateSamples[-1].TemperatureC - $orderedGateSamples[0].TemperatureC
if ($coolGateMaximumC -ge 35.0) {
    throw "Cool gate failed: maximum silicon temperature $coolGateMaximumC C is not below 35 C."
}
if ($coolGateRiseC -gt 1.0) {
    throw "Cool gate failed: silicon rise $coolGateRiseC C exceeds 1 C."
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = New-ThorSafeLabel $Label
$captureDir = Join-Path $repoRoot "debug-captures\android-speed-sprint\$stamp-$safeLabel"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

function Get-ThorCapturedBody {
    param([string]$Path)

    return @(
        Get-Content -LiteralPath $Path |
            Where-Object { $_ -notmatch '^#' -and $_ -notmatch '^exit=' -and -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Write-PostInstallThermalSnapshot {
    $batteryLines = @(Invoke-ThorAdbLines -Adb $adb -AdbArgs @("shell", "dumpsys battery") -ScratchDir $captureDir)
    $thermalZoneLines = @(Invoke-ThorAdbLines -Adb $adb -AdbArgs @("shell", (Get-ThorThermalZoneShellCommand)) -ScratchDir $captureDir)
    $hardwareLines = @(Invoke-ThorAdbLines -Adb $adb -AdbArgs @("shell", "dumpsys hardware_properties") -ScratchDir $captureDir)
    $snapshot = Get-ThorThermalGuardSnapshot -BatteryLines $batteryLines -ThermalZoneLines $thermalZoneLines -HardwareLines $hardwareLines

    @(
        "captured=$(Get-Date -Format o)",
        "battery_temperature_c=$(Format-ThorTemperatureC $snapshot.battery_temperature_c)",
        "battery_source=$($snapshot.battery_source)",
        "skin_temperature_c=$(Format-ThorTemperatureC $snapshot.skin_temperature_c)",
        "skin_source=$($snapshot.skin_source)",
        "silicon_temperature_c=$(Format-ThorTemperatureC $snapshot.silicon_temperature_c)",
        "silicon_source=$($snapshot.silicon_source)",
        "skin_sensor_count=$($snapshot.skin_sensor_count)",
        "silicon_sensor_count=$($snapshot.silicon_sensor_count)"
    ) | Set-Content -LiteralPath (Join-Path $captureDir "post-install-thermal.txt") -Encoding UTF8

    return $snapshot
}

Invoke-ThorAdbText $adb $captureDir "force-stop-before.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
$pidBeforePath = Invoke-ThorAdbText $adb $captureDir "pid-before.txt" @("shell", "pidof $Package") -AllowFailure
$pidBefore = @(Get-ThorCapturedBody $pidBeforePath)
if ($pidBefore.Count -ne 0) {
    throw "RPCSX PID remained active before installation: $($pidBefore -join ' ')"
}

Write-ThorLaunchPowerState -Adb $adb -CaptureDir $captureDir -Prefix "preinstall"

$installFailure = $null
$deviceHash = ""
$remoteApk = ""
$snapshot = $null

try {
    $installPath = Invoke-ThorAdbText $adb $captureDir "adb-install.txt" @("install", "-r", $resolvedApk) -TimeoutSeconds 180
    $installBody = @(Get-ThorCapturedBody $installPath)
    if (($installBody -join "`n") -notmatch '(?m)^Success\s*$') {
        throw "adb install did not report Success."
    }

    $packagePath = Invoke-ThorAdbText $adb $captureDir "package-path.txt" @("shell", "pm path $Package")
    $packageBody = @(Get-ThorCapturedBody $packagePath)
    $packageRow = @($packageBody | Where-Object { $_ -match '^package:(/.+/base[.]apk)$' } | Select-Object -First 1)
    if ($packageRow.Count -ne 1) {
        throw "Could not resolve installed base.apk for $Package."
    }
    $remoteApk = $packageRow[0] -replace '^package:', ''

    $deviceHashPath = Invoke-ThorAdbText $adb $captureDir "installed-base-apk-sha256.txt" @("shell", "sha256sum '$remoteApk'")
    $deviceHashBody = @(Get-ThorCapturedBody $deviceHashPath)
    $hashMatch = [regex]::Match(($deviceHashBody -join "`n"), '(?i)\b([0-9a-f]{64})\b')
    if (-not $hashMatch.Success) {
        throw "Could not parse installed base.apk SHA-256."
    }
    $deviceHash = $hashMatch.Groups[1].Value.ToUpperInvariant()
    if ($deviceHash -ne $expectedHash) {
        throw "Installed APK hash mismatch: expected $expectedHash, got $deviceHash"
    }

    Invoke-ThorAdbText $adb $captureDir "package-version.txt" @("shell", "dumpsys package $Package | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime|installerPackageName'") -AllowFailure | Out-Null
    Invoke-ThorAdbText $adb $captureDir "experiment-controls.txt" @("shell", 'printf "rsx_workers="; getprop debug.rpcsx.thor.rsx_cache_workers; printf "rsx_limit="; getprop debug.rpcsx.thor.rsx_cache_preload_limit; printf "rsx_load_budget_ms="; getprop debug.rpcsx.thor.rsx_cache_load_budget_ms; printf "rsx_budget_ms="; getprop debug.rpcsx.thor.rsx_cache_compile_budget_ms; printf "spu_limit="; getprop debug.rpcsx.thor.spu_cache_preload_limit; printf "spu_budget_ms="; getprop debug.rpcsx.thor.spu_cache_compile_budget_ms; printf "spu_workers="; getprop debug.rpcsx.thor.spu_cache_worker_limit; printf "spu_native_cache="; getprop debug.rpcsx.thor.spu_native_object_cache; printf "cache_affinity="; getprop debug.rpcsx.thor.cache_worker_affinity_mask; printf "vk_cache="; getprop debug.rpcsx.thor.vk_pipeline_cache; printf "vk_hits_only="; getprop debug.rpcsx.thor.vk_preload_cache_hits_only; printf "ppu_interp="; getprop debug.rpcsx.thor.es_ppu_command_interp; printf "dispatch_probe="; getprop debug.rpcsx.thor.es_ppu_dispatch_probe; printf "async_draw="; getprop debug.rpcsx.thor.es_async_draw_barrier') -AllowFailure | Out-Null
} catch {
    $installFailure = $_
} finally {
    Invoke-ThorAdbText $adb $captureDir "force-stop-after.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
    $pidAfterPath = Invoke-ThorAdbText $adb $captureDir "pid-after.txt" @("shell", "pidof $Package") -AllowFailure
    $pidAfter = @(Get-ThorCapturedBody $pidAfterPath)
    Write-ThorLaunchPowerState -Adb $adb -CaptureDir $captureDir -Prefix "postinstall"
    $snapshot = Write-PostInstallThermalSnapshot
}

if ($pidAfter.Count -ne 0) {
    if ($null -eq $installFailure) {
        $installFailure = [System.Management.Automation.RuntimeException]::new("RPCSX PID remained active after installation: $($pidAfter -join ' ')")
    }
}

$status = if ($null -eq $installFailure) { "installed-exact-no-launch" } else { "failed" }
@(
    "# Thor APK No-Launch Install",
    "",
    "- Created: $(Get-Date -Format o)",
    "- Status: $status",
    "- Device serial: $Serial",
    "- Package: $Package",
    "- APK: $resolvedApk",
    "- APK size: $((Get-Item -LiteralPath $resolvedApk).Length)",
    "- Expected/host SHA-256: $expectedHash",
    "- Cool gate capture: $resolvedCoolGate",
    "- Cool gate age minutes at validation: $([math]::Round($coolGateAge.TotalMinutes, 2))",
    "- Cool gate silicon samples C: $(($orderedGateSamples | ForEach-Object { $_.TemperatureC.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) }) -join ', ')",
    "- Cool gate maximum silicon C: $($coolGateMaximumC.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))",
    "- Cool gate silicon rise C: $($coolGateRiseC.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))",
    "- Installed base.apk: $remoteApk",
    "- Installed SHA-256: $deviceHash",
    "- PID before: $(if ($pidBefore.Count) { $pidBefore -join ' ' } else { 'absent' })",
    "- PID after: $(if ($pidAfter.Count) { $pidAfter -join ' ' } else { 'absent' })",
    "- Post-install battery C: $(Format-ThorTemperatureC $snapshot.battery_temperature_c)",
    "- Post-install skin C: $(Format-ThorTemperatureC $snapshot.skin_temperature_c)",
    "- Post-install silicon C: $(Format-ThorTemperatureC $snapshot.silicon_temperature_c)",
    "- Emulator launch: no",
    "- Failure: $(if ($null -eq $installFailure) { 'none' } else { $installFailure.Exception.Message })"
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

if ($null -ne $installFailure) {
    throw "No-launch APK install failed; see ${captureDir}: $($installFailure.Exception.Message)"
}

Write-Output "Thor no-launch install capture: $captureDir"
Write-Output "Installed exact APK SHA-256: $deviceHash"
Write-Output "RPCSX PID after install: absent"
