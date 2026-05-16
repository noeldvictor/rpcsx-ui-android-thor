param(
    [ValidateSet("SafeSpeed", "OfficialMinimal", "NeutralCore", "RsxThreaded", "OldNeutral", "AltNeutral", "AltPpuPrime", "AltSpuWide")]
    [string]$Mode = "SafeSpeed",
    [ValidateRange(512, 8192)]
    [int]$VramMb = 3072,
    [ValidateRange(0, 8)]
    [int]$ShaderCompilerThreads = 2,
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
$remoteBackup = "$remoteDir/config_BLUS30161.pre-thor-speed-$timestamp.yml"

$schedulerMode = "Operating System"
$affinityNote = "OS scheduler/process affinity only."
$affinityBlock = ""

if ($Mode -in @("OldNeutral", "AltNeutral", "AltPpuPrime", "AltSpuWide")) {
    if ($Mode -eq "OldNeutral") {
        $schedulerMode = "RPCS3 Scheduler"
    } else {
        $schedulerMode = "RPCS3 Alternative Scheduler"
    }

    $cpu3 = "General"
    $cpu4 = "PPU"
    $cpu5 = "SPU"
    $cpu6 = "SPU"
    $cpu7 = "RSX"
    $affinityNote = "Scheduler matrix: neutral affinity map."

    if ($Mode -eq "AltPpuPrime") {
        $cpu4 = "RSX"
        $cpu7 = "PPU"
        $affinityNote = "Scheduler matrix: PPU on prime CPU7, RSX on CPU4, SPU on CPU5-6."
    } elseif ($Mode -eq "AltSpuWide") {
        $cpu4 = "SPU"
        $affinityNote = "Scheduler matrix: SPU widened to CPU4-6, RSX on CPU7, PPU falls back to general CPU3."
    }

    $affinityBlock = @"
  Affinity:
    CPU0: General
    CPU1: General
    CPU2: General
    CPU3: $cpu3
    CPU4: $cpu4
    CPU5: $cpu5
    CPU6: $cpu6
    CPU7: $cpu7
"@
}

if ($Mode -eq "OfficialMinimal") {
    $profile = @"
# RPCSX_THOR_OFFICIAL_MINIMAL_PROFILE
# Source: local Thor Eternal Sonata compatibility baseline.
# Title ID: BLUS30161
# This keeps official DB-critical WCB and avoids SPURS/scheduler overrides.
Video:
  Frame limit: 30
  Write Color Buffers: true
  Disable On-Disk Shader Cache: false
  Shader Compiler Threads: $ShaderCompilerThreads
  Vulkan:
    VRAM allocation limit (MB): $VramMb
  Performance Overlay:
    Enabled: true
    Detail level: Minimal
"@
} elseif ($Mode -eq "NeutralCore" -or $Mode -eq "RsxThreaded" -or $Mode -eq "OldNeutral" -or $Mode -eq "AltNeutral" -or $Mode -eq "AltPpuPrime" -or $Mode -eq "AltSpuWide") {
    $rsxThreadedLine = ""
    $rsxThreadedNote = "No RSX threading override."
    if ($Mode -eq "RsxThreaded") {
        $rsxThreadedLine = "  Multithreaded RSX: true`n"
        $rsxThreadedNote = "A/B experiment: force Multithreaded RSX on because Thor field captures show rsx::thread hot."
    }

    $profile = @"
# RPCSX_THOR_NEUTRAL_CORE_PROFILE
# Source: local Thor Eternal Sonata compatibility baseline.
# Title ID: BLUS30161
# This explicitly neutralizes aggressive Android/global CPU settings while keeping official DB-critical WCB.
# $rsxThreadedNote
# $affinityNote
Core:
  Thread Scheduler Mode: $schedulerMode
  SPU Reservation Busy Waiting Percentage: 0
  SPU Reservation Busy Waiting Enabled: false
  Max SPURS Threads: 6
  Accurate SPU Reservations: true
  SPU Verification: true
  Sleep Timers Accuracy: As Host
$affinityBlock
Video:
  Frame limit: 30
  Write Color Buffers: true
${rsxThreadedLine}  Accurate ZCULL stats: false
  Relaxed ZCULL Sync: false
  Disable On-Disk Shader Cache: false
  Shader Compiler Threads: $ShaderCompilerThreads
  Vulkan:
    VRAM allocation limit (MB): $VramMb
  Performance Overlay:
    Enabled: true
    Detail level: Minimal
"@
} else {
    $profile = @"
# RPCSX_THOR_SAFE_SPEED_PROFILE
# Source: local Thor Eternal Sonata speed/correctness profile.
# Title ID: BLUS30161
# This intentionally does not use RPCSX_THOR_AUTO_SETTINGS, so the app will not rewrite it.
# Official DB requires Write Color Buffers. Vulkan VRAM is capped for shared-memory Adreno.
Core:
  Thread Scheduler Mode: RPCS3 Scheduler
  SPU Reservation Busy Waiting Percentage: 100
  SPU Reservation Busy Waiting Enabled: true
  Max SPURS Threads: 6
  Accurate SPU Reservations: true
  SPU Verification: true
  Sleep Timers Accuracy: As Host
Video:
  Frame limit: 30
  Write Color Buffers: true
  Accurate ZCULL stats: false
  Relaxed ZCULL Sync: false
  Multithreaded RSX: false
  Disable On-Disk Shader Cache: false
  Shader Compiler Threads: $ShaderCompilerThreads
  Vulkan:
    VRAM allocation limit (MB): $VramMb
  Performance Overlay:
    Enabled: true
    Detail level: Minimal
"@
}

$tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "config_BLUS30161.thor.yml"
[System.IO.File]::WriteAllText(
    $tempFile,
    $profile,
    [System.Text.UTF8Encoding]::new($false)
)

& $adb shell "mkdir -p '$remoteDir'"
& $adb shell "if [ -f '$remoteConfig' ]; then cp '$remoteConfig' '$remoteBackup'; fi"
& $adb push $tempFile $remoteConfig
& $adb shell "chmod 664 '$remoteConfig'"

Remove-Item -LiteralPath $tempFile -Force

if ($StopApp) {
    & $adb shell am force-stop $packageName
}

if ($LaunchApp) {
    & $adb shell am start -n "$packageName/net.rpcsx.MainActivity"
}

"Pushed $remoteConfig"
"Backup: $remoteBackup"
"Mode: $Mode"
"Vulkan VRAM allocation limit (MB): $VramMb"
"Shader Compiler Threads: $ShaderCompilerThreads"
if ($StopApp) {
    "Stopped $packageName so the next boot uses this profile."
}
if ($LaunchApp) {
    "Launched $packageName."
}
