param(
    [ValidateSet("OfficialStable", "SafeSpeed", "OfficialMinimal", "NeutralCore", "RsxThreaded", "OldNeutral", "AltNeutral", "AltPpuPrime", "AltSpuWide", "RocknixFast", "RocknixCorrect", "Rocknix720Fast", "Rocknix720Correct")]
    [string]$Mode = "OfficialStable",
    [string]$Serial,
    [ValidateRange(512, 8192)]
    [int]$VramMb = 3072,
    [ValidateRange(0, 8)]
    [int]$ShaderCompilerThreads = 2,
    [switch]$PpuReservationPriority,
    [switch]$StopApp,
    [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

$connectedDevices = @(
    & $adb devices |
        Select-Object -Skip 1 |
        ForEach-Object {
            if ($_ -match '^(\S+)\s+device$') {
                $Matches[1]
            }
        }
)

if ([string]::IsNullOrWhiteSpace($Serial)) {
    if ($connectedDevices.Count -ne 1) {
        throw "Specify -Serial when exactly one online ADB device is not available. Online devices: $($connectedDevices -join ', ')"
    }

    $Serial = $connectedDevices[0]
} elseif ($Serial -notin $connectedDevices) {
    throw "ADB device '$Serial' is not online. Online devices: $($connectedDevices -join ', ')"
}

function Invoke-AdbChecked {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $script:adb -s $script:Serial @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "adb -s $script:Serial $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$packageName = "net.rpcsx.easy"
$remoteDir = "/storage/emulated/0/Android/data/$packageName/files/config/custom_configs"
$remoteConfig = "$remoteDir/config_BLUS30161.yml"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remoteBackup = "$remoteDir/config_BLUS30161.pre-thor-speed-$timestamp.yml"
$ppuReservationPriorityValue = if ($PpuReservationPriority) { "true" } else { "false" }

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

if ($Mode -in @("RocknixFast", "RocknixCorrect", "Rocknix720Fast", "Rocknix720Correct")) {
    $is720Target = $Mode -in @("Rocknix720Fast", "Rocknix720Correct")
    $isCorrectTarget = $Mode -in @("RocknixCorrect", "Rocknix720Correct")
    $writeColorBuffers = if ($isCorrectTarget) { "true" } else { "false" }
    $resolution = if ($is720Target) { "1280x720" } else { "720x480" }
    $resolutionScale = if ($is720Target) { 100 } else { 50 }
    $targetNote = if ($is720Target) { "720p mirror for the AYN Thor Rocknix video target." } else { "Low-res Rocknix SM8550 preset mirror." }
    $wcbNote = if ($isCorrectTarget) { "WCB on for correctness comparison." } else { "WCB off to test the likely Rocknix-fast path; visual correctness must be checked." }

    $profile = @"
# RPCSX_THOR_ROCKNIX_MIRROR_PROFILE
# Source: Rocknix SM8550 RPCS3 preset / launcher delta investigation.
# Title ID: BLUS30161
# $targetNote
# $wcbNote
# Android-safe mirror: keeps VRAM capped instead of Rocknix's effectively uncapped Linux value.
Core:
  Thread Scheduler Mode: Operating System
  LLVM Precompilation: false
  PPU Reservation Priority Over SPUs: $ppuReservationPriorityValue
  SPU Reservation Busy Waiting Percentage: 0
  SPU Reservation Busy Waiting Enabled: false
  SPU GETLLAR Busy Waiting Percentage: 100
  Max SPURS Threads: 6
  Accurate SPU Reservations: true
  SPU Verification: true
  Sleep Timers Accuracy: As Host
  XFloat Accuracy: Approximate

Video:
  Renderer: Vulkan
  Resolution: $resolution
  Aspect ratio: 16:9
  Frame limit: 30
  Shader Precision: Low
  Write Color Buffers: $writeColorBuffers
  Accurate ZCULL stats: false
  Relaxed ZCULL Sync: false
  Multithreaded RSX: false
  Disable On-Disk Shader Cache: false
  Resolution Scale: $resolutionScale
  Shader Compiler Threads: $ShaderCompilerThreads
  Driver Wake-Up Delay: 1
  Vulkan:
    Asynchronous Texture Streaming 2: false
    Asynchronous Queue Scheduler: Safe
    VRAM allocation limit (MB): $VramMb
  Performance Overlay:
    Enabled: true
    Detail level: Minimal
"@
} elseif ($Mode -eq "OfficialStable") {
    $profile = @"
# RPCSX_THOR_OFFICIAL_STABLE_PROFILE
# Source: clean current-upstream RPCS3 first-battle control plus Thor-safe resource limits.
# Title ID: BLUS30161
# Correctness-first profile for draw-stream stability and the reported flicker.
# Keep experimental superpaths off; optimize only after this profile survives battle repetition.
Core:
  Thread Scheduler Mode: Operating System
  LLVM Precompilation: false
  PPU Reservation Priority Over SPUs: $ppuReservationPriorityValue
  SPU Reservation Busy Waiting Percentage: 0
  SPU Reservation Busy Waiting Enabled: false
  SPU GETLLAR Busy Waiting Percentage: 100
  Max SPURS Threads: 6
  Accurate SPU Reservations: true
  SPU Verification: true
  Sleep Timers Accuracy: Usleep Only
  XFloat Accuracy: Approximate

Video:
  Renderer: Vulkan
  Resolution: 1280x720
  Aspect ratio: 16:9
  Frame limit: 30
  Shader Precision: High
  Write Color Buffers: true
  Accurate ZCULL stats: true
  Relaxed ZCULL Sync: false
  Multithreaded RSX: false
  Disable On-Disk Shader Cache: false
  Resolution Scale: 100
  Shader Compiler Threads: $ShaderCompilerThreads
  Driver Wake-Up Delay: 0
  Vulkan:
    Asynchronous Texture Streaming 2: false
    Asynchronous Queue Scheduler: Safe
    VRAM allocation limit (MB): $VramMb
  Performance Overlay:
    Enabled: true
    Detail level: Minimal
"@
} elseif ($Mode -eq "OfficialMinimal") {
    $profile = @"
# RPCSX_THOR_OFFICIAL_MINIMAL_PROFILE
# Source: local Thor Eternal Sonata compatibility baseline.
# Title ID: BLUS30161
# This keeps official DB-critical WCB and avoids SPURS/scheduler overrides.
Core:
  PPU Reservation Priority Over SPUs: $ppuReservationPriorityValue
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
  PPU Reservation Priority Over SPUs: $ppuReservationPriorityValue
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
  PPU Reservation Priority Over SPUs: $ppuReservationPriorityValue
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

Invoke-AdbChecked shell "mkdir -p '$remoteDir'"
Invoke-AdbChecked shell "if [ -f '$remoteConfig' ]; then cp '$remoteConfig' '$remoteBackup'; fi"
Invoke-AdbChecked push $tempFile $remoteConfig
Invoke-AdbChecked shell "chmod 664 '$remoteConfig'"

Remove-Item -LiteralPath $tempFile -Force

if ($StopApp) {
    Invoke-AdbChecked shell am force-stop $packageName
}

if ($LaunchApp) {
    Invoke-AdbChecked shell am start -n "$packageName/net.rpcsx.MainActivity"
}

"Pushed $remoteConfig"
"Backup: $remoteBackup"
"Device serial: $Serial"
"Mode: $Mode"
"PPU reservation priority over SPUs: $ppuReservationPriorityValue"
"Vulkan VRAM allocation limit (MB): $VramMb"
"Shader Compiler Threads: $ShaderCompilerThreads"
if ($StopApp) {
    "Stopped $packageName so the next boot uses this profile."
}
if ($LaunchApp) {
    "Launched $packageName."
}
