param(
    [ValidateSet("ToolStatus", "DeviceSnapshot", "WindowsScene", "AndroidStart", "AndroidCapture", "AndroidStop", "AndroidScene", "AndroidRouteScene")]
    [string]$Action = "ToolStatus",
    [ValidateSet("field", "battle", "menu")]
    [string]$Scene = "field",
    [string]$Package = "net.rpcsx.easy",
    [string]$AndroidSerial = "",
    [string]$Label = "",
    [string]$BootTarget = "",
    [string]$InputMacro = "",
    [ValidateSet("Keyboard", "PadApi")]
    [string]$WindowsInputBackend = "Keyboard",
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
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataMfcShapeProbe = "Off",
    [ValidateSet("Off", "Verify", "Fast")]
    [string]$EternalSonataMfcLadder = "Off",
    [ValidateSet("Off", "Verify", "VerifyShadow", "Verify25ccShadow", "Skip")]
    [string]$EternalSonataSpuHleVerify = "Off",
    [ValidateSet("Off", "Verify", "Fast")]
    [string]$EternalSonataSpuHle25ccBody = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataSpuHleSize16Body = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataSpuHle451cPreserveBody = "Off",
    [ValidateSet("Off", "Profile")]
    [string]$EternalSonataKernelCapsule = "Off",
    [ValidateSet("Off", "Profile", "Verify")]
    [string]$EternalSonataReservationLoop = "Off",
    [ValidateSet("Off", "Relaxed")]
    [string]$EternalSonataPutllc16Reservations = "Off",
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$EternalSonataPutllc16Pair = "Off",
    [ValidateSet("Off", "Verify")]
    [string]$EternalSonataDmaSuperPath = "Off",
    [string]$WindowsRsxAuditor = "Off",
    [ValidateSet("Off", "Host")]
    [string]$WindowsRsxDmaFence = "Off",
    [ValidateSet("Off", "Depth", "DepthReadOnly", "Color", "All")]
    [string]$WindowsRsxTextureBarrier = "Off",
    [ValidateSet("Off", "KeepReadOnly")]
    [string]$WindowsRsxDepthFeedback = "Off",
    [ValidateSet("Off", "Profile", "SkipColor", "SkipDepth", "SkipAll")]
    [string]$WindowsRsxResolve = "Off",
    [ValidateSet("Off", "Verify", "VerifySampled", "VerifyCachedSampled", "VerifyCachedTransferSampled", "VerifyCachedDeferSampled", "Fast", "FastSampled", "FastCachedSampled", "FastCachedTransferSampled", "FastCachedDeferSampled", "FastKeepSrc")]
    [string]$WindowsRsxBlitSourceResolve = "Off",
    [ValidateSet("Off", "GpuSwap")]
    [string]$WindowsRsxPresentUpload = "Off",
    [ValidateSet("Off", "GpuSwap", "GpuSwapCached")]
    [string]$WindowsRsxIndexUpload = "Off",
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$WindowsRsxIndexPersistentCache = "Off",
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$WindowsRsxVertexSupersetCache = "Off",
    [int]$WindowsRsxVertexSupersetScanLimit = 0,
    [ValidateSet("Off", "Profile", "Verify", "Fast")]
    [string]$WindowsRsxVertexPersistentCache = "Off",
    [ValidateSet("Off", "Profile", "Fast")]
    [string]$WindowsRsxVertexVolatileCache = "Off",
    [ValidateSet("Off", "Verify", "VerifySampled", "Fast", "FastSampled")]
    [string]$AndroidRsxBlitSourceResolve = "Off",
    [ValidateSet("Keep", "On", "Off")]
    [string]$WindowsRsxForceHwMsaaResolve = "Keep",
    [ValidateSet("Keep", "Off", "Auto", "PS3Native", "30", "60", "120", "240")]
    [string]$WindowsFrameLimit = "Keep",
    [int]$WindowsVblankRate = 0,
    [ValidateSet("Keep", "On", "Off")]
    [string]$WindowsSpuAccurateReservations = "Keep",
    [ValidateSet("Keep", "On", "Off")]
    [string]$WindowsSpuAccurateDma = "Keep",
    [int]$WindowsGameScreen = 1,
    [int]$MaxSeconds = 120,
    [ValidateRange(1, 30)]
    [int]$AndroidSceneSeconds = 20,
    [ValidateRange(1, 5)]
    [int]$AndroidThermalPollSeconds = 2,
    [ValidateRange(0, 20)]
    [double]$AndroidThermalRuntimeStopHeadroomC = 4.0,
    [ValidateRange(0, 30)]
    [double]$AndroidThermalRuntimeProbeWindowC = 16.0,
    [ValidateRange(1, 5)]
    [int]$AndroidThermalPreflightSamples = 3,
    [ValidateRange(1, 10)]
    [int]$AndroidThermalPreflightIntervalSeconds = 2,
    [ValidateRange(0, 20)]
    [double]$AndroidThermalPreflightHeadroomC = 5.0,
    [ValidateRange(25, 60)]
    [double]$AndroidMaxLaunchSiliconTemperatureC = 40.0,
    [ValidateRange(0, 10)]
    [double]$AndroidThermalPreflightMaxRiseC = 2.0,
    [ValidateRange(30, 50)]
    [double]$AndroidMaxBatteryTemperatureC = 39.0,
    [ValidateRange(35, 60)]
    [double]$AndroidMaxSkinTemperatureC = 45.0,
    [ValidateRange(50, 110)]
    [double]$AndroidMaxSiliconTemperatureC = 72.0,
    [ValidateRange(0, 16)]
    [int]$AndroidRsxCacheWorkers = 0,
    [ValidateRange(0, 4096)]
    [int]$AndroidRsxCachePreloadLimit = 0,
    [ValidateRange(0, 4096)]
    [int]$AndroidSpuCachePreloadLimit = 0,
    [ValidateSet("on", "off")]
    [string]$AndroidVkPipelineCache = "on",
    [ValidateSet("on", "off")]
    [string]$AndroidVkPreloadCacheHitsOnly = "off",
    [ValidateSet("on", "off")]
    [string]$AndroidCachePhasePacing = "off",
    [int]$ScreenshotEverySeconds = 15,
    [int]$ScreenshotStartSeconds = 15,
    [int]$ScreenshotMaxCount = 6,
    [ValidateSet("Off", "FieldLike", "FieldByDeadline", "CleanAfterField", "BattleRoute")]
    [string]$WindowsVisualGate = "Off",
    [ValidateSet("Legacy", "TopSlot")]
    [string]$WindowsBattleLoadRoute = "Legacy",
    [int]$WindowsVisualGateFieldSeconds = 160,
    [long]$WindowsVisualGateMinFieldPngBytes = 1000000,
    [int]$HostSampleSeconds = 1,
    [int]$HostSampleEverySeconds = 30,
    [ValidateSet("Off", "Warn", "Fail", "ExternalFail")]
    [string]$WindowsHostContentionGate = "Off",
    [string]$WindowsCpuAffinityMask = "",
    [string]$WindowsRpcs3Bin = "",
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$AndroidInputMode = "Direct",
    [ValidateSet("Keep", "Quiet", "Normal", "Verbose", "ReducedLoop", "SpursProbe", "SemaProfile", "SemaFast", "DmaProfile", "DmaVerify", "GpuSuperpathScout", "RsxAuditor", "RsxDmaHostFence", "RsxDepthFeedback", "RsxTextureBarrierSkipColor", "RsxTextureBarrierSkipDepth", "RsxTextureBarrierSkipAll", "FastBusyWaitLight", "FastBusyWait", "FastBusyWaitAggressive", "WaitProfiler", "WaitProfilerVerbose", "GetllarProbe", "GetllarShort", "GetllarTiny", "GetllarYield8", "GetllarNoRsxLock")]
    [string]$AndroidLogMode = "Keep",
    [ValidateSet("Keep", "DefaultF8", "AllThreadsFF", "RsxPrimeSpuNonPrimePpuA715")]
    [string]$AndroidRuntimeAffinityMode = "Keep",
    [string]$AndroidInputProfile = "",
    [ValidateRange(0, 10)]
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
    [switch]$NoScreenRecord,
    [switch]$KeepAndroidRunningAfterCapture
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

function Resolve-SpeedAndroidSerial {
    param([string]$RequestedSerial)

    if ([string]::IsNullOrWhiteSpace($RequestedSerial)) {
        $RequestedSerial = $env:ANDROID_SERIAL
    }

    $deviceRows = @(& $Adb devices 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "adb devices failed: $($deviceRows -join ' ')"
    }

    $onlineSerials = @(
        $deviceRows |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -match '^(\S+)\s+device$' } |
            ForEach-Object { $Matches[1] }
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedSerial)) {
        $RequestedSerial = $RequestedSerial.Trim()
        if ($RequestedSerial -notin $onlineSerials) {
            throw "Requested Android device '$RequestedSerial' is not online. Online devices: $($onlineSerials -join ', ')"
        }
        return $RequestedSerial
    }

    if ($onlineSerials.Count -eq 1) {
        return $onlineSerials[0]
    }
    if ($onlineSerials.Count -eq 0) {
        throw "No online Android device found."
    }

    throw "Multiple Android devices are online: $($onlineSerials -join ', '). Pass -AndroidSerial to select the AYN Thor explicitly."
}

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
    param(
        [string]$Scene,
        [string]$BattleLoadRoute = "Legacy"
    )

    # Short title pulses are required; longer down/left-stick presses can skip from NEW GAME to title OPTIONS.
    # The load menu can remember a lower save slot from a prior failed route, so normalize to Save File 01 before selecting.
    $selectTopSave = "up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500"
    $loadField = "wait:45000;down:20;wait:500;cross:80;wait:12000;$selectTopSave;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000"
    # The first-battle route is timing-sensitive. The normalized TopSlot loader
    # intentionally avoids a post-load start/cross pair, which can pause the
    # field and fake a battle-route baseline while never reaching first battle.
    $loadBattleLegacy = "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000"
    $loadBattleTopSlot = $loadField

    switch ($Scene) {
        "field" {
            return "$loadField;shot:100;wait:15000;shot:100"
        }
        "menu" {
            # Full title Options page, not the weaker field Pause overlay.
            # First settle/skip to the title menu, then wait for the Options
            # selection to stabilize before opening it. Shorter timing can miss
            # the full Options page and fall into intro playback.
            return "wait:65000;cross:180;wait:9000;shot:100;down:220;wait:1000;shot:100;down:220;wait:16000;shot:100;cross:180;wait:8000;shot:100;wait:6000;shot:100"
        }
        "battle" {
            $loadBattle = if ($BattleLoadRoute -eq "TopSlot") { $loadBattleTopSlot } else { $loadBattleLegacy }
            return "$loadBattle;shot:100;ls_left:2600;wait:1000;combo:ls_left+ls_down:2200;wait:45000;shot:100;dpad_down:120;wait:500;cross:180;wait:60000;shot:100;wait:60000;shot:100"
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
        "battle" {
            return "eternal-sonata-battle-intro-route"
        }
        default {
            return ""
        }
    }
}

function Invoke-SpeedWindowsVisualGate {
    param(
        [string]$SafeLabel,
        [datetime]$StartedAt
    )

    if ($WindowsVisualGate -eq "Off") {
        return
    }

    $checker = Join-Path $PSScriptRoot "check_eternal_sonata_windows_visual_gate.ps1"
    if (-not (Test-Path -LiteralPath $checker -PathType Leaf)) {
        throw "Windows visual gate helper not found: $checker"
    }

    $captureRoot = Join-Path $RepoRoot "debug-captures\windows-lab"
    $runNameSuffix = "-$SafeLabel-windows"
    $runDir = Get-ChildItem -LiteralPath $captureRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.EndsWith($runNameSuffix, [System.StringComparison]::OrdinalIgnoreCase) -and $_.LastWriteTime -ge $StartedAt.AddMinutes(-5) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $runDir) {
        throw "Could not find latest Windows run directory ending with '$runNameSuffix' for visual gate."
    }

    $gateParams = @{
        RunDir = $runDir.FullName
        MinFieldPngBytes = $WindowsVisualGateMinFieldPngBytes
    }

    switch ($WindowsVisualGate) {
        "FieldLike" {
            $gateParams.RequireFieldLike = $true
        }
        "FieldByDeadline" {
            $gateParams.RequireFieldLike = $true
            $gateParams.RequireFieldAtOrBeforeSeconds = $WindowsVisualGateFieldSeconds
        }
        "CleanAfterField" {
            $gateParams.RequireFieldLike = $true
            $gateParams.RequireFieldAtOrBeforeSeconds = $WindowsVisualGateFieldSeconds
            $gateParams.RequireNoInvalidAfterFirstField = $true
            $gateParams.RequireNoFatalLog = $true
        }
        "BattleRoute" {
            $gateParams.RequireFieldLike = $true
            $gateParams.RequireFieldAtOrBeforeSeconds = $WindowsVisualGateFieldSeconds
            $gateParams.RequireFieldAtOrAfterSeconds = 220
            $gateParams.RequireMinFieldLikeCount = 2
            $gateParams.RequireBattleLikeAtOrAfterSeconds = 200
            $gateParams.RequireNoInvalidAfterFirstField = $true
            $gateParams.RequireNoFatalLog = $true
            if ($gateParams.MinFieldPngBytes -lt 1500000) {
                $gateParams.MinFieldPngBytes = 1500000
            }
        }
    }

    & $checker @gateParams
}

function Invoke-SpeedAdbText {
    param(
        [string]$CaptureDir,
        [string]$Name,
        [string[]]$AdbArgs,
        [switch]$AllowFailure,
        [int]$TimeoutSeconds = 0
    )

    return Invoke-ThorAdbText -Adb $Adb -CaptureDir $CaptureDir -Name $Name -AdbArgs $AdbArgs -AllowFailure:$AllowFailure -TimeoutSeconds $TimeoutSeconds
}

function Stop-SpeedAndroidPackage {
    param(
        [string]$CaptureDir,
        [string]$Name,
        [switch]$AllowFailure
    )

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $attemptName = if ($attempt -eq 1) { $Name } else { "$Name-retry" }
        $path = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name $attemptName -AdbArgs @("shell", "am force-stop $Package") -AllowFailure -TimeoutSeconds 3
        $failed = @(Select-String -LiteralPath $path -Pattern '^exit=\d+$').Count -gt 0
        if (-not $failed) {
            return
        }
        if ($attempt -lt 2) {
            Start-Sleep -Milliseconds 250
        }
    }

    if ($AllowFailure) {
        return
    }

    throw "Unable to force-stop RPCSX after two bounded attempts. See $Name and $Name-retry in $CaptureDir."
}

function Get-SpeedAndroidProcessId {
    param(
        [string]$CaptureDir,
        [string]$Name
    )

    $path = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name $Name -AdbArgs @("shell", "pidof $Package") -AllowFailure -TimeoutSeconds 3
    foreach ($line in (Get-Content -LiteralPath $path)) {
        if ($line -match '^\s*(\d+)(?:\s+\d+)*\s*$') {
            return $Matches[1]
        }
    }

    return $null
}

function Assert-SpeedAndroidSceneGuard {
    param(
        [string]$CaptureDir,
        [string]$Stage,
        [string]$ExpectedProcessId
    )

    $safeStage = New-SpeedSafeLabel $Stage
    $batteryPath = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name "guard-$safeStage-battery.txt" -AdbArgs @("shell", "dumpsys battery") -AllowFailure -TimeoutSeconds 3
    $hardwarePath = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name "guard-$safeStage-hardware-temperatures.txt" -AdbArgs @("shell", "dumpsys hardware_properties") -AllowFailure -TimeoutSeconds 3
    $thermalZoneCommand = Get-ThorThermalZoneShellCommand
    $thermalZonePath = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name "guard-$safeStage-thermal-zones.txt" -AdbArgs @("shell", $thermalZoneCommand) -AllowFailure -TimeoutSeconds 3
    $snapshotParams = @{
        BatteryLines = @(Get-Content -LiteralPath $batteryPath)
        HardwareLines = @(Get-Content -LiteralPath $hardwarePath)
        ThermalZoneLines = @(Get-Content -LiteralPath $thermalZonePath)
    }
    $snapshot = Get-ThorThermalGuardSnapshot @snapshotParams
    $batteryText = Format-ThorTemperatureC $snapshot.battery_temperature_c
    $skinText = Format-ThorTemperatureC $snapshot.skin_temperature_c
    $siliconText = Format-ThorTemperatureC $snapshot.silicon_temperature_c

    "$(Get-Date -Format o) stage=$Stage battery_temperature_c=$batteryText battery_source=$($snapshot.battery_source) battery_limit_c=$AndroidMaxBatteryTemperatureC skin_temperature_c=$skinText skin_source=$($snapshot.skin_source) skin_limit_c=$AndroidMaxSkinTemperatureC silicon_temperature_c=$siliconText silicon_source=$($snapshot.silicon_source) silicon_limit_c=$AndroidMaxSiliconTemperatureC skin_sensor_count=$($snapshot.skin_sensor_count) silicon_sensor_count=$($snapshot.silicon_sensor_count) guard_sensor_count=$($snapshot.guard_sensor_count) thermal_zone_count=$($snapshot.thermal_zone_count) hardware_sensor_count=$($snapshot.hardware_sensor_count) sources=$($snapshot.source_summary)" |
        Out-File -LiteralPath (Join-Path $CaptureDir "thermal-guard.log") -Append -Encoding UTF8

    $violationParams = @{
        Snapshot = $snapshot
        MaxBatteryTemperatureC = $AndroidMaxBatteryTemperatureC
        MaxSkinTemperatureC = $AndroidMaxSkinTemperatureC
        MaxSiliconTemperatureC = $AndroidMaxSiliconTemperatureC
    }
    $violation = Get-ThorThermalGuardViolation @violationParams
    if ($null -ne $violation) {
        Stop-SpeedAndroidPackage -CaptureDir $CaptureDir -Name "guard-$safeStage-$($violation.code)-stop.txt"
        throw "$($violation.message) Stage '$Stage'. RPCSX was force-stopped."
    }

    $currentProcessId = Get-SpeedAndroidProcessId -CaptureDir $CaptureDir -Name "guard-$safeStage-pid.txt"
    $currentText = if ([string]::IsNullOrWhiteSpace($currentProcessId)) { "absent" } else { $currentProcessId }
    "$(Get-Date -Format o) stage=$Stage expected_pid=$ExpectedProcessId current_pid=$currentText" |
        Out-File -LiteralPath (Join-Path $CaptureDir "process-guard.log") -Append -Encoding UTF8
    if ($currentText -ne $ExpectedProcessId) {
        Stop-SpeedAndroidPackage -CaptureDir $CaptureDir -Name "guard-$safeStage-process-stop.txt"
        throw "RPCSX process changed at '$Stage' (expected PID $ExpectedProcessId, current PID $currentText). RPCSX was force-stopped."
    }

    $remoteLog = "/storage/emulated/0/Android/data/$Package/files/cache/RPCSX.log"
    $guestPath = Invoke-SpeedAdbText -CaptureDir $CaptureDir -Name "guard-$safeStage-guest-tail.txt" -AdbArgs @("shell", "tail -n 300 '$remoteLog'") -AllowFailure -TimeoutSeconds 3
    $guestLines = @(Get-Content -LiteralPath $guestPath)
    if ($guestLines -match '^exit=\d+$') {
        Stop-SpeedAndroidPackage -CaptureDir $CaptureDir -Name "guard-$safeStage-guest-read-stop.txt"
        throw "RPCSX guest log could not be read at '$Stage'. RPCSX was force-stopped instead of continuing an unverified capture."
    }

    $fatalMatches = @(Get-ThorGuestFatalMatches -Lines $guestLines)
    if ($fatalMatches.Count -gt 0) {
        $fatalMatches.Line |
            Sort-Object -Unique |
            Set-Content -LiteralPath (Join-Path $CaptureDir "guard-$safeStage-guest-fatal.txt") -Encoding UTF8
        Stop-SpeedAndroidPackage -CaptureDir $CaptureDir -Name "guard-$safeStage-guest-fatal-stop.txt"
        throw "RPCSX guest fatal detected at '$Stage'. RPCSX was force-stopped."
    }

    $unknownDrawMatches = @(Get-ThorGuestUnknownDrawMatches -Lines $guestLines)
    if ($unknownDrawMatches.Count -gt 0) {
        $unknownDrawMatches.Line |
            Sort-Object -Unique |
            Set-Content -LiteralPath (Join-Path $CaptureDir "guard-$safeStage-guest-unknown-draw.txt") -Encoding UTF8
        Stop-SpeedAndroidPackage -CaptureDir $CaptureDir -Name "guard-$safeStage-guest-unknown-draw-stop.txt"
        throw "RPCSX unknown draw command detected at '$Stage'. RPCSX was force-stopped."
    }
}

function Stop-SpeedAndroidAdbStream {
    param(
        [object]$Stream,
        [int]$TimeoutMilliseconds = 3000
    )

    if ($null -eq $Stream) {
        return
    }

    $process = Get-Process -Id $Stream.pid -ErrorAction SilentlyContinue
    if ($process -and -not $process.WaitForExit($TimeoutMilliseconds)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
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
    if ($AndroidLogMode -eq "GpuSuperpathScout" -and $EternalSonataGpuProbe -eq "Off" -and $EternalSonataDmaSuperPath -eq "Off") {
        $dmaMode = "verify"
    }
    $rsxBlitSourceMode = switch ($AndroidRsxBlitSourceResolve) {
        "Verify" { "verify" }
        "VerifySampled" { "verify-sampled" }
        "Fast" { "fast" }
        "FastSampled" { "fast-sampled" }
        default { "off" }
    }

    & $Adb shell setprop debug.rpcsx.thor.es_sema_superpath $semaMode | Out-Null
    & $Adb shell setprop debug.rpcsx.thor.es_dma_superpath $dmaMode | Out-Null
    & $Adb shell setprop debug.rpcsx.thor.rsx_blit_source_resolve $rsxBlitSourceMode | Out-Null
    Write-Host "Android speed properties: debug.rpcsx.thor.es_sema_superpath=$semaMode debug.rpcsx.thor.es_dma_superpath=$dmaMode debug.rpcsx.thor.rsx_blit_source_resolve=$rsxBlitSourceMode"
}

function Set-AndroidLogMode {
    if ($AndroidLogMode -eq "Keep") {
        return
    }

    & (Join-Path $PSScriptRoot "set_thor_logging.ps1") -Mode $AndroidLogMode
}

function Set-AndroidRuntimeAffinity {
    if ($AndroidRuntimeAffinityMode -eq "Keep") {
        return
    }

    & (Join-Path $PSScriptRoot "set_thor_runtime_affinity.ps1") -Mode $AndroidRuntimeAffinityMode -Package $Package
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
        "- Device serial: $(if ([string]::IsNullOrWhiteSpace($AndroidSerial)) { 'ANDROID_SERIAL/default' } else { $AndroidSerial })",
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
        "- Device serial: $(if ([string]::IsNullOrWhiteSpace($AndroidSerial)) { 'ANDROID_SERIAL/default' } else { $AndroidSerial })",
        "- Duration seconds: $AndroidSceneSeconds",
        "- Thermal poll seconds: $AndroidThermalPollSeconds",
        "- Max launch silicon temperature C: $AndroidMaxLaunchSiliconTemperatureC",
        "- Thermal preflight max silicon rise C: $AndroidThermalPreflightMaxRiseC",
        "- Max battery temperature C: $AndroidMaxBatteryTemperatureC",
        "- Max skin temperature C: $AndroidMaxSkinTemperatureC",
        "- Max silicon temperature C: $AndroidMaxSiliconTemperatureC",
        "- Force-stop after capture: $(-not $KeepAndroidRunningAfterCapture)",
        "- Android log mode: $AndroidLogMode",
        "- Android runtime affinity mode: $AndroidRuntimeAffinityMode",
        "- Perfetto: $(-not $NoPerfetto)",
        "- Screenrecord: $(-not $NoScreenRecord)",
        "- Capture dir: $captureDir",
        "",
        "The live interval is bounded to 30 seconds. Temperature, process identity, and guest fatal markers are polled during capture; any failed guard force-stops RPCSX. RPCSX is also force-stopped after successful evidence capture unless -KeepAndroidRunningAfterCapture is explicitly supplied."
    ) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "mkdir-public-capture-dir.txt" -AdbArgs @("shell", "mkdir -p '$remotePublicDir'") -AllowFailure -TimeoutSeconds 5 | Out-Null
    $expectedProcessId = Get-SpeedAndroidProcessId -CaptureDir $captureDir -Name "pre-pid.txt"
    if ([string]::IsNullOrWhiteSpace($expectedProcessId)) {
        Stop-SpeedAndroidPackage -CaptureDir $captureDir -Name "pre-missing-process-stop.txt"
        throw "RPCSX is not running at the start of the Android scene capture."
    }

    Assert-SpeedAndroidSceneGuard -CaptureDir $captureDir -Stage "pre-capture" -ExpectedProcessId $expectedProcessId
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "pre-top-threads.txt" -AdbArgs @("shell", "top -H -b -n 1 | grep -E '$Package|rpcsx|RPCS3|PPU|SPU|RSX|CPU'") -AllowFailure -TimeoutSeconds 5 | Out-Null
    Invoke-SpeedAdbText -CaptureDir $captureDir -Name "pre-gfxinfo.txt" -AdbArgs @("shell", "dumpsys gfxinfo $Package") -AllowFailure -TimeoutSeconds 5 | Out-Null

    $screenProcess = $null
    $perfettoProcess = $null
    $captureSucceeded = $false
    $packageStopped = $false
    try {
        Set-AndroidRuntimeAffinity
        if (-not $NoScreenRecord) {
            $screenProcess = Start-ThorAdbStream -Adb $Adb -CaptureDir $captureDir -Name "screenrecord" -AdbArgs @("shell", "screenrecord --time-limit $AndroidSceneSeconds '$remoteVideo'")
        }
        if (-not $NoPerfetto) {
            $perfettoProcess = Start-ThorAdbStream -Adb $Adb -CaptureDir $captureDir -Name "perfetto" -AdbArgs @("shell", "perfetto -t $($AndroidSceneSeconds)s -b 64mb -o '$remoteTrace' $perfettoCats")
        }

        $timer = [Diagnostics.Stopwatch]::StartNew()
        $pollIndex = 0
        while ($timer.Elapsed.TotalSeconds -lt $AndroidSceneSeconds) {
            $remainingMs = [Math]::Max(1, [int](($AndroidSceneSeconds - $timer.Elapsed.TotalSeconds) * 1000))
            $sleepMs = [Math]::Min($AndroidThermalPollSeconds * 1000, $remainingMs)
            Start-Sleep -Milliseconds $sleepMs
            $pollIndex++
            Assert-SpeedAndroidSceneGuard -CaptureDir $captureDir -Stage ("capture-{0:D2}" -f $pollIndex) -ExpectedProcessId $expectedProcessId
        }
        $timer.Stop()

        Stop-SpeedAndroidAdbStream -Stream $screenProcess
        $screenProcess = $null
        Stop-SpeedAndroidAdbStream -Stream $perfettoProcess
        $perfettoProcess = $null

        Assert-SpeedAndroidSceneGuard -CaptureDir $captureDir -Stage "pre-proof" -ExpectedProcessId $expectedProcessId
        Invoke-SpeedAdbText -CaptureDir $captureDir -Name "screencap.txt" -AdbArgs @("shell", "screencap -p '$remoteScreenshot'") -TimeoutSeconds 5 | Out-Null
        Invoke-SpeedAdbText -CaptureDir $captureDir -Name "post-top-threads.txt" -AdbArgs @("shell", "top -H -b -n 1 | grep -E '$Package|rpcsx|RPCS3|PPU|SPU|RSX|CPU'") -AllowFailure -TimeoutSeconds 5 | Out-Null
        Invoke-SpeedAdbText -CaptureDir $captureDir -Name "post-gfxinfo.txt" -AdbArgs @("shell", "dumpsys gfxinfo $Package") -AllowFailure -TimeoutSeconds 5 | Out-Null
        Assert-SpeedAndroidSceneGuard -CaptureDir $captureDir -Stage "post-proof" -ExpectedProcessId $expectedProcessId
        $captureSucceeded = $true

        if (-not $KeepAndroidRunningAfterCapture) {
            Stop-SpeedAndroidPackage -CaptureDir $captureDir -Name "post-capture-stop.txt"
            $packageStopped = $true
        }

        if (-not $NoScreenRecord) {
            Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteVideo -LocalName "scene.mp4" | Out-Null
        }
        Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteScreenshot -LocalName "scene.png" | Out-Null
        if (-not $NoPerfetto) {
            Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteTrace -LocalName "scene.perfetto-trace" | Out-Null
        }

        Invoke-SpeedAdbText -CaptureDir $captureDir -Name "cleanup-remote.txt" -AdbArgs @("shell", "rm -f '$remoteScreenshot' '$remoteVideo' '$remoteTrace'") -AllowFailure -TimeoutSeconds 5 | Out-Null
        Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "post-stop"
    } catch {
        $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "capture-failure.txt") -Encoding UTF8
        throw
    } finally {
        Stop-SpeedAndroidAdbStream -Stream $screenProcess
        Stop-SpeedAndroidAdbStream -Stream $perfettoProcess
        if (-not $packageStopped -and (-not $KeepAndroidRunningAfterCapture -or -not $captureSucceeded)) {
            Stop-SpeedAndroidPackage -CaptureDir $captureDir -Name "capture-finally-stop.txt" -AllowFailure
        }
    }

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
        ThermalPollIntervalSeconds = $AndroidThermalPollSeconds
        ThermalRuntimeStopHeadroomC = $AndroidThermalRuntimeStopHeadroomC
        ThermalRuntimeProbeWindowC = $AndroidThermalRuntimeProbeWindowC
        ThermalPreflightSamples = $AndroidThermalPreflightSamples
        ThermalPreflightIntervalSeconds = $AndroidThermalPreflightIntervalSeconds
        ThermalPreflightHeadroomC = $AndroidThermalPreflightHeadroomC
        MaxLaunchSiliconTemperatureC = $AndroidMaxLaunchSiliconTemperatureC
        ThermalPreflightMaxRiseC = $AndroidThermalPreflightMaxRiseC
        MaxBatteryTemperatureC = $AndroidMaxBatteryTemperatureC
        MaxSkinTemperatureC = $AndroidMaxSkinTemperatureC
        MaxSiliconTemperatureC = $AndroidMaxSiliconTemperatureC
        RsxCacheWorkers = $AndroidRsxCacheWorkers
        RsxCachePreloadLimit = $AndroidRsxCachePreloadLimit
        SpuCachePreloadLimit = $AndroidSpuCachePreloadLimit
        VkPipelineCache = $AndroidVkPipelineCache
        VkPreloadCacheHitsOnly = $AndroidVkPreloadCacheHitsOnly
        CachePhasePacing = $AndroidCachePhasePacing
    }

    if (-not [string]::IsNullOrWhiteSpace($AndroidSerial)) {
        $macroParams.Serial = $AndroidSerial
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

if ($Action -in @(
    "DeviceSnapshot",
    "AndroidStart",
    "AndroidCapture",
    "AndroidStop",
    "AndroidScene",
    "AndroidRouteScene"
)) {
    $AndroidSerial = Resolve-SpeedAndroidSerial -RequestedSerial $AndroidSerial
    $env:ANDROID_SERIAL = $AndroidSerial
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
        $effectiveMaxSeconds = $MaxSeconds
        if ($Scene -eq "battle" -and [string]::IsNullOrWhiteSpace($InputMacro) -and $effectiveMaxSeconds -lt 330) {
            $effectiveMaxSeconds = 330
        }
        if ($WindowsVisualGate -eq "BattleRoute" -and $effectiveMaxSeconds -lt 220) {
            throw "WindowsVisualGate BattleRoute requires MaxSeconds >= 220 because its late-field proof starts at 220s."
        }

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
            EternalSonataMfcShapeProbe = $EternalSonataMfcShapeProbe
            EternalSonataMfcLadder = $EternalSonataMfcLadder
            EternalSonataSpuHleVerify = $EternalSonataSpuHleVerify
            EternalSonataSpuHle25ccBody = $EternalSonataSpuHle25ccBody
            EternalSonataSpuHleSize16Body = $EternalSonataSpuHleSize16Body
            EternalSonataSpuHle451cPreserveBody = $EternalSonataSpuHle451cPreserveBody
            EternalSonataKernelCapsule = $EternalSonataKernelCapsule
            EternalSonataReservationLoop = $EternalSonataReservationLoop
            EternalSonataPutllc16Reservations = $EternalSonataPutllc16Reservations
            EternalSonataPutllc16Pair = $EternalSonataPutllc16Pair
            EternalSonataDmaSuperPath = $EternalSonataDmaSuperPath
            RsxAuditor = $WindowsRsxAuditor
            RsxDmaFence = $WindowsRsxDmaFence
            RsxTextureBarrier = $WindowsRsxTextureBarrier
            RsxDepthFeedback = $WindowsRsxDepthFeedback
            RsxResolve = $WindowsRsxResolve
            RsxBlitSourceResolve = $WindowsRsxBlitSourceResolve
            RsxPresentUpload = $WindowsRsxPresentUpload
            RsxIndexUpload = $WindowsRsxIndexUpload
            RsxIndexPersistentCache = $WindowsRsxIndexPersistentCache
            RsxVertexSupersetCache = $WindowsRsxVertexSupersetCache
            RsxVertexSupersetScanLimit = $WindowsRsxVertexSupersetScanLimit
            RsxVertexPersistentCache = $WindowsRsxVertexPersistentCache
            RsxVertexVolatileCache = $WindowsRsxVertexVolatileCache
            RsxForceHwMsaaResolve = $WindowsRsxForceHwMsaaResolve
            FrameLimit = $WindowsFrameLimit
            VblankRate = $WindowsVblankRate
            SpuAccurateReservations = $WindowsSpuAccurateReservations
            SpuAccurateDma = $WindowsSpuAccurateDma
            GameScreen = $WindowsGameScreen
            MaxSeconds = $effectiveMaxSeconds
            InputBackend = $WindowsInputBackend
            ScreenshotEverySeconds = $ScreenshotEverySeconds
            ScreenshotStartSeconds = $ScreenshotStartSeconds
            ScreenshotMaxCount = $ScreenshotMaxCount
            HostSampleSeconds = $HostSampleSeconds
            HostSampleEverySeconds = $HostSampleEverySeconds
            HostContentionGate = $WindowsHostContentionGate
        }
        if (-not [string]::IsNullOrWhiteSpace($WindowsCpuAffinityMask)) {
            $runParams.CpuAffinityMask = $WindowsCpuAffinityMask
        }
        if (-not [string]::IsNullOrWhiteSpace($WindowsRpcs3Bin)) {
            $runParams.Rpcs3BinOverride = $WindowsRpcs3Bin
        }
        if ($BootTarget) {
            $runParams.BootTarget = $BootTarget
        }
        $sceneMacro = if ($InputMacro) { $InputMacro } else { Get-SpeedWindowsSceneMacro -Scene $Scene -BattleLoadRoute $WindowsBattleLoadRoute }
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
        $labStartedAt = Get-Date
        & (Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1") @runParams
        Invoke-SpeedWindowsVisualGate -SafeLabel $safeLabel -StartedAt $labStartedAt
    }
    "AndroidStart" {
        Set-AndroidLogMode
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
        Set-AndroidLogMode
        Invoke-AndroidSceneCapture
    }
    "AndroidRouteScene" {
        Set-AndroidLogMode
        Set-AndroidSpeedProperties
        Invoke-AndroidRouteScene
    }
    "AndroidStop" {
        & (Join-Path $PSScriptRoot "thor_ooda.ps1") -Action Stop -Profile eternal-sonata-speed -Label "$safeLabel-android-stop" -Symptom "Eternal Sonata $Scene baseline stop, driver=$Driver, core=$Core"
    }
}
