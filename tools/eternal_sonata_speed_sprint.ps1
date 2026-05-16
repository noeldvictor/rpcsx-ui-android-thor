param(
    [ValidateSet("ToolStatus", "DeviceSnapshot", "WindowsScene", "AndroidStart", "AndroidCapture", "AndroidStop", "AndroidScene", "AndroidRouteScene")]
    [string]$Action = "ToolStatus",
    [ValidateSet("field", "battle", "menu")]
    [string]$Scene = "field",
    [string]$Package = "net.rpcsx.easy",
    [string]$Label = "",
    [string]$BootTarget = "",
    [string]$InputMacro = "",
    [ValidateSet("Off", "Detect", "Cache")]
    [string]$EternalSonataSuperPath = "Off",
    [int]$EternalSonataJoinSpin = -1,
    [ValidateSet("Off", "Profile", "Yield", "Skip", "Clamp")]
    [string]$EternalSonataWaitSuperPath = "Off",
    [int]$EternalSonataWaitMaxUs = 100,
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$EternalSonataSemaphoreSuperPath = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataGpuProbe = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataDmaSuperPath = "Off",
    [int]$MaxSeconds = 120,
    [int]$AndroidSceneSeconds = 20,
    [int]$ScreenshotEverySeconds = 15,
    [int]$ScreenshotStartSeconds = 15,
    [int]$ScreenshotMaxCount = 6,
    [int]$HostSampleSeconds = 1,
    [int]$HostSampleEverySeconds = 30,
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$AndroidInputMode = "Direct",
    [string]$AndroidInputProfile = "",
    [int]$AndroidRoutePostWaitSeconds = 5,
    [string]$Driver = "stock-qualcomm",
    [string]$Core = "unknown",
    [switch]$RenderDoc,
    [switch]$RenderDocApiValidation,
    [switch]$RenderDocCaptureCallstacks,
    [switch]$RefreshConfigDb,
    [switch]$NoBuildInstall,
    [switch]$NoLaunch,
    [switch]$SkipHostSystemCheck,
    [switch]$NoPerfetto,
    [switch]$NoScreenRecord
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Adb = "C:\Users\leanerdesigner\AppData\Local\Android\Sdk\platform-tools\adb.exe"
if ($env:ANDROID_HOME -and (Test-Path -LiteralPath (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"))) {
    $Adb = Join-Path $env:ANDROID_HOME "platform-tools\adb.exe"
}
. "$PSScriptRoot\thor_debug_common.ps1"

function New-SpeedSafeLabel {
    param([string]$Value)
    $safe = ($Value -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "eternal-sonata"
    }
    return $safe
}

function Get-SpeedLabel {
    if (-not [string]::IsNullOrWhiteSpace($Label)) {
        return New-SpeedSafeLabel $Label
    }
    return "eternal-sonata-$Scene-$Driver"
}

function Get-SpeedWindowsSceneMacro {
    param([string]$Scene)

    switch ($Scene) {
        "field" {
            return "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:100;wait:15000;shot:100"
        }
        default {
            return ""
        }
    }
}

function Get-SpeedAndroidSceneProfile {
    param([string]$Scene)

    if (-not [string]::IsNullOrWhiteSpace($AndroidInputProfile)) {
        return $AndroidInputProfile
    }

    switch ($Scene) {
        "field" {
            return "eternal-sonata-field-route"
        }
        "menu" {
            return "eternal-sonata-menu-route"
        }
        default {
            return ""
        }
    }
}

function Invoke-SpeedAdbText {
    param(
        [string]$CaptureDir,
        [string]$Name,
        [string[]]$AdbArgs,
        [switch]$AllowFailure
    )

    return Invoke-ThorAdbText -Adb $Adb -CaptureDir $CaptureDir -Name $Name -AdbArgs $AdbArgs -AllowFailure:$AllowFailure
}

function Set-AndroidSpeedProperties {
    $semaMode = switch ($EternalSonataSemaphoreSuperPath) {
        "Profile" { "profile" }
        "Fast" { "fast" }
        default { "off" }
    }
    $dmaMode = switch ($EternalSonataDmaSuperPath) {
        "Verify" { "verify" }
        default {
            if ($EternalSonataGpuProbe -eq "Profile") { "profile" } else { "off" }
        }
    }

    & $Adb shell setprop debug.rpcsx.thor.es_sema_superpath $semaMode | Out-Null
    & $Adb shell setprop debug.rpcsx.thor.es_dma_superpath $dmaMode | Out-Null
    Write-Host "Android speed properties: debug.rpcsx.thor.es_sema_superpath=$semaMode debug.rpcsx.thor.es_dma_superpath=$dmaMode"
}

function Invoke-DeviceSnapshot {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safe = Get-SpeedLabel
    $captureDir = Join-Path $RepoRoot "debug-captures\android-speed-sprint\$stamp-$safe-device"
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "adb-devices.txt" -AdbArgs @("devices", "-l") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "getprop-device.txt" -AdbArgs @("shell", "getprop ro.product.model; getprop ro.soc.model; getprop ro.hardware; getprop ro.board.platform") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "surfaceflinger.txt" -AdbArgs @("shell", "dumpsys SurfaceFlinger") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "gfxinfo.txt" -AdbArgs @("shell", "dumpsys gfxinfo $Package") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "thermal.txt" -AdbArgs @("shell", "dumpsys thermalservice") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "memory.txt" -AdbArgs @("shell", "dumpsys meminfo $Package") -AllowFailure | Out-Null

    @(
        "# Eternal Sonata Android Device Snapshot",
        "",
        "- Created: $(Get-Date -Format o)",
        "- Scene: $Scene",
        "- Driver: $Driver",
        "- Core: $Core",
        "- Capture dir: $captureDir",
        "",
        "Use this snapshot with the field/battle/menu baseline so GPU driver, memory, thermal, and device identity are not guessed."
    ) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

    Write-Host "Device snapshot: $captureDir"
}

function Invoke-AndroidSceneCapture {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $safe = Get-SpeedLabel
    $captureDir = Join-Path $RepoRoot "debug-captures\android-speed-sprint\$stamp-$safe-scene"
    New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

    $remotePublicDir = "/sdcard/Android/data/$Package/files/debug-captures"
    $remoteBase = "$remotePublicDir/$stamp-$safe"
    $remoteScreenshot = "$remoteBase.png"
    $remoteVideo = "$remoteBase.mp4"
    $remoteTrace = "/data/misc/perfetto-traces/$stamp-$safe.perfetto-trace"
    $perfettoCats = "sched freq idle am wm gfx view binder_driver hal dalvik input res memory"

    @(
        "# Eternal Sonata Thor Scene Capture",
        "",
        "- Created: $(Get-Date -Format o)",
        "- Scene: $Scene",
        "- Driver: $Driver",
        "- Core: $Core",
        "- Package: $Package",
        "- Duration seconds: $AndroidSceneSeconds",
        "- Perfetto: $(-not $NoPerfetto)",
        "- Screenrecord: $(-not $NoScreenRecord)",
        "- Capture dir: $captureDir",
        "",
        "Use this for fast warm-cache truth checks at the same field/battle/menu checkpoint. It captures visual proof plus low-overhead Android timing data without rebuilding or reinstalling."
    ) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "mkdir-public-capture-dir.txt" -AdbArgs @("shell", "mkdir -p '$remotePublicDir'") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "pre-pid.txt" -AdbArgs @("shell", "pidof $Package") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "pre-top-threads.txt" -AdbArgs @("shell", "top -H -b -n 1 | grep -E '$Package|rpcsx|RPCS3|PPU|SPU|RSX|CPU'") -AllowFailure | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "pre-gfxinfo.txt" -AdbArgs @("shell", "dumpsys gfxinfo $Package") -AllowFailure | Out-Null

    $screenProcess = $null
    if (-not $NoScreenRecord) {
        $screenProcess = Start-ThorAdbStream -Adb $Adb -CaptureDir $captureDir -Name "screenrecord" -AdbArgs @("shell", "screenrecord --time-limit $AndroidSceneSeconds '$remoteVideo'")
        Start-Sleep -Seconds 1
    }

    if (-not $NoPerfetto) {
        Invoke-SpeedAdbText -CaptureDir $captureDir -Name "perfetto-run.txt" -AdbArgs @("shell", "perfetto -t ${AndroidSceneSeconds}s -b 64mb -o '$remoteTrace' $perfettoCats") -AllowFailure | Out-Null
    } else {
        Start-Sleep -Seconds $AndroidSceneSeconds
    }

    if ($screenProcess) {
        $remainingMs = [Math]::Max(1000, ($AndroidSceneSeconds + 15) * 1000)
        $process = Get-Process -Id $screenProcess.pid -ErrorAction SilentlyContinue
        if ($process -and -not $process.WaitForExit($remainingMs)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }

    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "screencap.txt" -AdbArgs @("shell", "screencap -p '$remoteScreenshot'") -AllowFailure | Out-Null
    Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "post"

    if (-not $NoScreenRecord) {
        Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteVideo -LocalName "scene.mp4" | Out-Null
    }
    Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteScreenshot -LocalName "scene.png" | Out-Null
    if (-not $NoPerfetto) {
        Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteTrace -LocalName "scene.perfetto-trace" | Out-Null
    }

    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "cleanup-remote.txt" -AdbArgs @("shell", "rm -f '$remoteScreenshot' '$remoteVideo' '$remoteTrace'") -AllowFailure | Out-Null

    Write-Host "Android scene capture: $captureDir"
}

function Invoke-AndroidRouteScene {
    $profile = Get-SpeedAndroidSceneProfile -Scene $Scene
    if ([string]::IsNullOrWhiteSpace($profile) -and [string]::IsNullOrWhiteSpace($InputMacro)) {
        throw "No Android route profile is defined for scene '$Scene'. Supply -AndroidInputProfile or -InputMacro."
    }

    $macroParams = @{
        Package = $Package
        InputMode = $AndroidInputMode
        BootGame = $true
        ForceStop = $true
        PostSnapshot = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($InputMacro)) {
        $macroParams.Profile = "custom"
        $macroParams.Macro = $InputMacro
    } else {
        $macroParams.Profile = $profile
    }

    Write-Host "Routing Android scene with thor_input_macro.ps1 profile=$($macroParams.Profile) input=$AndroidInputMode scene=$Scene"
    & (Join-Path $PSScriptRoot "thor_input_macro.ps1") @macroParams

    if ($AndroidRoutePostWaitSeconds -gt 0) {
        Start-Sleep -Seconds $AndroidRoutePostWaitSeconds
    }

    Invoke-AndroidSceneCapture
}

$safeLabel = Get-SpeedLabel

switch ($Action) {
    "ToolStatus" {
        & (Join-Path $PSScriptRoot "install_speed_sprint_tools.ps1") -VerifyOnly
    }
    "DeviceSnapshot" {
        Invoke-DeviceSnapshot
    }
    "WindowsScene" {
        $runParams = @{
            Action = "Run"
            Label = "$safeLabel-windows"
            Mode = "NoGui"
            EternalSonataSuperPath = $EternalSonataSuperPath
            EternalSonataJoinSpin = $EternalSonataJoinSpin
            EternalSonataWaitSuperPath = $EternalSonataWaitSuperPath
            EternalSonataWaitMaxUs = $EternalSonataWaitMaxUs
            EternalSonataSemaphoreSuperPath = $EternalSonataSemaphoreSuperPath
            EternalSonataGpuProbe = $EternalSonataGpuProbe
            EternalSonataDmaSuperPath = $EternalSonataDmaSuperPath
            MaxSeconds = $MaxSeconds
            ScreenshotEverySeconds = $ScreenshotEverySeconds
            ScreenshotStartSeconds = $ScreenshotStartSeconds
            ScreenshotMaxCount = $ScreenshotMaxCount
            HostSampleSeconds = $HostSampleSeconds
            HostSampleEverySeconds = $HostSampleEverySeconds
        }
        if ($BootTarget) {
            $runParams.BootTarget = $BootTarget
        }
        $sceneMacro = if ($InputMacro) { $InputMacro } else { Get-SpeedWindowsSceneMacro -Scene $Scene }
        if ($sceneMacro) {
            $runParams.InputMacro = $sceneMacro
        }
        if ($RefreshConfigDb) {
            $runParams.RefreshConfigDb = $true
        }
        if ($RenderDoc) {
            $runParams.RenderDocInject = $true
        }
        if ($RenderDocApiValidation) {
            $runParams.RenderDocApiValidation = $true
        }
        if ($RenderDocCaptureCallstacks) {
            $runParams.RenderDocCaptureCallstacks = $true
        }
        if ($SkipHostSystemCheck) {
            $runParams.SkipHostSystemCheck = $true
        }
        & (Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1") @runParams
    }
    "AndroidStart" {
        Set-AndroidSpeedProperties
        $runParams = @{
            Action = "Auto"
            Profile = "eternal-sonata-speed"
            Label = "$safeLabel-android-start"
            Symptom = "Eternal Sonata $Scene baseline, driver=$Driver, core=$Core"
        }
        if ($NoBuildInstall) {
            $runParams.NoBuildInstall = $true
        }
        if ($NoLaunch) {
            $runParams.NoLaunch = $true
        }
        & (Join-Path $PSScriptRoot "thor_ooda.ps1") @runParams
    }
    "AndroidCapture" {
        & (Join-Path $PSScriptRoot "thor_ooda.ps1") -Action Capture -Profile eternal-sonata-speed -Label "$safeLabel-android-capture" -Symptom "Eternal Sonata $Scene baseline capture, driver=$Driver, core=$Core"
    }
    "AndroidScene" {
        Invoke-AndroidSceneCapture
    }
    "AndroidRouteScene" {
        Set-AndroidSpeedProperties
        Invoke-AndroidRouteScene
    }
    "AndroidStop" {
        & (Join-Path $PSScriptRoot "thor_ooda.ps1") -Action Stop -Profile eternal-sonata-speed -Label "$safeLabel-android-stop" -Symptom "Eternal Sonata $Scene baseline stop, driver=$Driver, core=$Core"
    }
}
