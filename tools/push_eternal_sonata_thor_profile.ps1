param(
    [switch]$StopApp,
    [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

$packageName = "net.rpcsx.easy"
$remoteDir = "/storage/emulated/0/Android/data/$packageName/files/config/custom_configs"
$remoteConfig = "$remoteDir/config_BLUS30161.yml"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteBackup = "$remoteDir/config_BLUS30161.pre-thor-spurs4-$timestamp.yml"

$profile = @"
# RPCSX_THOR_AUTO_SETTINGS
# Source: local Thor Eternal Sonata override
# Database timestamp: 20260512
# Title ID: BLUS30161
# RPCSX_THOR_PROFILE_OVERRIDE
# Eternal Sonata performance profile for AYN Thor.
Core:
  Max SPURS Threads: 4
  SPU Reservation Busy Waiting Enabled: true
  SPU Reservation Busy Waiting Percentage: 100
  Accurate SPU Reservations: false
  SPU Verification: false
  Sleep Timers Accuracy: As Host
Video:
  Frame limit: 30
  Accurate ZCULL stats: false
  Relaxed ZCULL Sync: true
  Multithreaded RSX: true
"@

$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "config_BLUS30161.thor.yml"
[System.IO.File]::WriteAllText(
    $tempFile,
    $profile,
    [System.Text.UTF8Encoding]::new($false)
)

& $adb shell "mkdir -p '$remoteDir'"
& $adb shell "if [ -f '$remoteConfig' ]; then cp '$remoteConfig' '$remoteBackup'; fi"
& $adb push $tempFile $remoteConfig

Remove-Item -LiteralPath $tempFile -Force

if ($StopApp) {
    & $adb shell am force-stop $packageName
}

if ($LaunchApp) {
    & $adb shell am start -n "$packageName/net.rpcsx.MainActivity"
}

"Pushed $remoteConfig"
"Backup: $remoteBackup"
if ($StopApp) {
    "Stopped $packageName so the next boot uses this profile."
}
if ($LaunchApp) {
    "Launched $packageName."
}
