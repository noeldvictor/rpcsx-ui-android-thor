param(
    [string]$Package = "net.rpcsx.easy",
    [string]$Serial = "",
    [string]$Profile = "custom",
    [string]$Macro = "",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [ValidatePattern("^[A-Z]{4}[0-9]{5}$")]
    [string]$TitleId = "BLUS30161",
    [int]$Display = 0,
    [int]$DefaultWaitMs = 500,
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Virtual",
    [string]$RawInputDevice = "/dev/input/event9",
    [ValidateRange(1, 5)]
    [int]$ThermalPreflightSamples = 3,
    [ValidateRange(1, 10)]
    [int]$ThermalPreflightIntervalSeconds = 2,
    [ValidateRange(0, 20)]
    [double]$ThermalPreflightHeadroomC = 5.0,
    [ValidateRange(25, 60)]
    [double]$MaxLaunchSiliconTemperatureC = 40.0,
    [ValidateRange(0, 10)]
    [double]$ThermalPreflightMaxRiseC = 2.0,
    [ValidateRange(1, 5)]
    [int]$ThermalPollIntervalSeconds = 2,
    [ValidateRange(0, 20)]
    [double]$ThermalRuntimeStopHeadroomC = 4.0,
    [ValidateRange(0, 30)]
    [double]$ThermalRuntimeProbeWindowC = 16.0,
    [double]$MaxBatteryTemperatureC = 39.0,
    [ValidateRange(35, 60)]
    [double]$MaxSkinTemperatureC = 45.0,
    [ValidateRange(50, 110)]
    [double]$MaxSiliconTemperatureC = 72.0,
    [ValidateRange(0, 16)]
    [int]$RsxCacheWorkers = 0,
    [ValidateRange(0, 4096)]
    [int]$RsxCachePreloadLimit = 0,
    [ValidateRange(0, 5000)]
    [int]$RsxCacheLoadBudgetMs = 0,
    [ValidateRange(0, 5000)]
    [int]$RsxCacheCompileBudgetMs = 0,
    [ValidateRange(0, 4096)]
    [int]$SpuCachePreloadLimit = 0,
    [ValidateRange(0, 5000)]
    [int]$SpuCacheCompileBudgetMs = 0,
    [ValidateSet("on", "off")]
    [string]$SpuNativeObjectCache = "off",
    [ValidateRange(0, 255)]
    [int]$CacheWorkerAffinityMask = 0,
    [ValidateSet("on", "off")]
    [string]$VkPipelineCache = "on",
    [ValidateSet("on", "off")]
    [string]$VkPreloadCacheHitsOnly = "off",
    [ValidateSet("on", "off")]
    [string]$AdpfRsx = "off",
    [ValidateSet("on", "off")]
    [string]$CachePhasePacing = "off",
    [ValidateSet("off", "publisher", "parser", "both")]
    [string]$EsPpuCommandInterp = "off",
    [ValidateSet("off", "on")]
    [string]$EsPpuDispatchProbe = "off",
    [ValidateSet("off", "verify", "repair")]
    [string]$EsAsyncDrawBarrier = "off",
    [ValidateSet("on", "off")]
    [string]$ThorDisplayPacing = "on",
    [ValidatePattern('^$|^[0-9A-Fa-f]{64}$')]
    [string]$ExpectedInstalledApkSha256 = "",
    [switch]$BootGame,
    [switch]$ForceStop,
    [switch]$PostSnapshot,
    [switch]$PassThruCaptureDirectory,
    [switch]$AllowUnknownDraw
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

if ($ThermalRuntimeProbeWindowC -lt $ThermalRuntimeStopHeadroomC) {
    throw "ThermalRuntimeProbeWindowC must be greater than or equal to ThermalRuntimeStopHeadroomC."
}

if ($Profile -eq "strict-cool-gate") {
    if ($BootGame) {
        throw "The strict-cool-gate profile forbids -BootGame."
    }
    if (-not $ForceStop) {
        throw "The strict-cool-gate profile requires -ForceStop."
    }
    if (-not [string]::IsNullOrWhiteSpace($Macro)) {
        throw "The strict-cool-gate profile forbids a custom macro."
    }

    $strictCoolGateParameters = [ordered]@{
        ThermalPreflightSamples = @($ThermalPreflightSamples, 3)
        ThermalPreflightIntervalSeconds = @($ThermalPreflightIntervalSeconds, 2)
        ThermalPreflightHeadroomC = @($ThermalPreflightHeadroomC, 0)
        MaxLaunchSiliconTemperatureC = @($MaxLaunchSiliconTemperatureC, 35)
        ThermalPreflightMaxRiseC = @($ThermalPreflightMaxRiseC, 1)
        MaxBatteryTemperatureC = @($MaxBatteryTemperatureC, 34)
        MaxSkinTemperatureC = @($MaxSkinTemperatureC, 40)
        MaxSiliconTemperatureC = @($MaxSiliconTemperatureC, 72)
    }
    foreach ($entry in $strictCoolGateParameters.GetEnumerator()) {
        if ($entry.Value[0] -ne $entry.Value[1]) {
            throw "The strict-cool-gate profile requires -$($entry.Key) '$($entry.Value[1])', got '$($entry.Value[0])'."
        }
    }
}

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb

function Resolve-ThorInputDeviceSerial {
    $requestedSerial = $Serial
    if ([string]::IsNullOrWhiteSpace($requestedSerial)) {
        $requestedSerial = $env:ANDROID_SERIAL
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

    if (-not [string]::IsNullOrWhiteSpace($requestedSerial)) {
        if ($requestedSerial -notin $onlineSerials) {
            throw "Requested Android device '$requestedSerial' is not online. Online devices: $($onlineSerials -join ', ')"
        }
        return $requestedSerial
    }

    if ($onlineSerials.Count -eq 1) {
        return $onlineSerials[0]
    }
    if ($onlineSerials.Count -eq 0) {
        throw "No online Android device found."
    }

    throw "Multiple Android devices are online: $($onlineSerials -join ', '). Pass -Serial or set ANDROID_SERIAL before running an input macro."
}

$DeviceSerial = Resolve-ThorInputDeviceSerial
$env:ANDROID_SERIAL = $DeviceSerial
$requestedInputMode = $InputMode
$profileForcesDirectInput = $Profile -eq "eternal-sonata-battle-intro-route" -and $InputMode -ne "Direct"
if ($profileForcesDirectInput) {
    # Android virtual gamepad injection can be dropped while the title is
    # visibly ready. Battle proof routes use the app-owned direct pad path so
    # an ignored Load input cannot waste the short thermal window in New Game.
    $InputMode = "Direct"
}
$requestedEsAsyncDrawBarrier = $EsAsyncDrawBarrier
if ($EsAsyncDrawBarrier -eq "repair") {
    # Runtime write-back proved unsafe on Thor. Preserve old invocations but
    # force them onto the read-only verifier before any property is written.
    $EsAsyncDrawBarrier = "verify"
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeProfile = New-ThorSafeLabel $Profile
$captureDir = Join-Path $RepoRoot "debug-captures\android-speed-sprint\$stamp-thor-input-$safeProfile"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null
$strictGuestDrawStream = $Profile -eq "eternal-sonata-battle-intro-route" -and -not $AllowUnknownDraw
$thorDisplayPacingValue = if ($ThorDisplayPacing -eq "on") { "true" } else { "false" }
$normalizedExpectedInstalledApkSha256 = $ExpectedInstalledApkSha256.ToUpperInvariant()

$keyAliases = @{
    "a" = "KEYCODE_BUTTON_A"
    "cross" = "KEYCODE_BUTTON_A"
    "confirm" = "KEYCODE_BUTTON_A"
    "b" = "KEYCODE_BUTTON_B"
    "circle" = "KEYCODE_BUTTON_B"
    "cancel" = "KEYCODE_BUTTON_B"
    "x" = "KEYCODE_BUTTON_X"
    "square" = "KEYCODE_BUTTON_X"
    "y" = "KEYCODE_BUTTON_Y"
    "triangle" = "KEYCODE_BUTTON_Y"
    "start" = "KEYCODE_BUTTON_START"
    "select" = "KEYCODE_BUTTON_SELECT"
    "l1" = "KEYCODE_BUTTON_L1"
    "r1" = "KEYCODE_BUTTON_R1"
    "l2" = "KEYCODE_BUTTON_L2"
    "r2" = "KEYCODE_BUTTON_R2"
    "up" = "KEYCODE_DPAD_UP"
    "down" = "KEYCODE_DPAD_DOWN"
    "left" = "KEYCODE_DPAD_LEFT"
    "right" = "KEYCODE_DPAD_RIGHT"
    "dpad_up" = "KEYCODE_DPAD_UP"
    "dpad_down" = "KEYCODE_DPAD_DOWN"
    "dpad_left" = "KEYCODE_DPAD_LEFT"
    "dpad_right" = "KEYCODE_DPAD_RIGHT"
}

$rawKeyAliases = @{
    "a" = 0x130
    "cross" = 0x130
    "confirm" = 0x130
    "b" = 0x131
    "circle" = 0x131
    "cancel" = 0x131
    "x" = 0x133
    "square" = 0x133
    "y" = 0x134
    "triangle" = 0x134
    "start" = 0x13b
    "select" = 0x13a
    "l1" = 0x136
    "r1" = 0x137
    "l2" = 0x138
    "r2" = 0x139
    "up" = 0x220
    "down" = 0x221
    "left" = 0x222
    "right" = 0x223
    "dpad_up" = 0x220
    "dpad_down" = 0x221
    "dpad_left" = 0x222
    "dpad_right" = 0x223
}

$directPadAliases = @{
    "select" = @(0x00000001, 0)
    "l3" = @(0x00000002, 0)
    "r3" = @(0x00000004, 0)
    "start" = @(0x00000008, 0)
    "up" = @(0x00000010, 0)
    "dpad_up" = @(0x00000010, 0)
    "right" = @(0x00000020, 0)
    "dpad_right" = @(0x00000020, 0)
    "down" = @(0x00000040, 0)
    "dpad_down" = @(0x00000040, 0)
    "left" = @(0x00000080, 0)
    "dpad_left" = @(0x00000080, 0)
    "ps" = @(0x00000100, 0)
    "l2" = @(0, 0x00000001)
    "r2" = @(0, 0x00000002)
    "l1" = @(0, 0x00000004)
    "r1" = @(0, 0x00000008)
    "triangle" = @(0, 0x00000010)
    "y" = @(0, 0x00000010)
    "circle" = @(0, 0x00000020)
    "b" = @(0, 0x00000020)
    "cross" = @(0, 0x00000040)
    "a" = @(0, 0x00000040)
    "confirm" = @(0, 0x00000040)
    "square" = @(0, 0x00000080)
    "x" = @(0, 0x00000080)
}

function Get-ThorMacroForProfile {
    param([string]$Name)

    switch ($Name) {
        "fast-forward-toggle" {
            return "combo:select+r1:800"
        }
        "title-new-game" {
            return "shot:title-before-new-game;cross;wait:15000;shot:new-game-start"
        }
        "title-load-save" {
            return "shot:title-before-load;dpad_down;wait:800;cross;wait:15000;shot:load-start"
        }
        "eternal-sonata-new-game-probe" {
            return "wait:120000;shot:title;cross;wait:45000;start;wait:1200;cross;wait:45000;shot:newgame-1;start;wait:1200;cross;wait:60000;shot:newgame-2;cross;wait:30000;shot:newgame-3"
        }
        "eternal-sonata-load-probe" {
            return "wait:120000;shot:title;dpad_down;wait:800;cross;wait:30000;shot:load-30s;wait:90000;shot:load-120s"
        }
        "eternal-sonata-load-field-route" {
            return "gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;gate:visual:load-menu:30000;cross;wait:1000;dpad_up;wait:500;cross;gate:visual:load-complete:50000;cross;gate:visual:field-frame:25000;check:guest:loaded-field;threads:load-field-route"
        }
        "eternal-sonata-battle-intro-route" {
            # Screenshot labels remain candidates until visual review confirms the battle UI.
            # A short screenshot burst samples transient corruption/flicker without
            # the sustained encoder load of screen recording. The later 10/20s
            # checkpoints still cover battle stability. Thread snapshots stay out
            # of this visual route so profiling overhead cannot perturb the proof.
            # Start the visual readiness gate immediately. It rejects PPU
            # compilation and black transition frames, so a fixed 60-second
            # pre-wait only heats the device and delays warm-cache routes.
            return "gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;gate:visual:load-menu:30000;cross;wait:1000;dpad_up;wait:500;cross;gate:visual:load-complete:50000;cross;gate:visual:field-frame:25000;check:guest:loaded-field;stick:left:down_left:700;wait:1000;approach:battle:left:left:900:3:11000;shot:first-battle-prompt-candidate;dpad_down;wait:300;cross;wait:4000;shot:first-battle-active-candidate;check:visual:battle-frame;check:guest:battle-active;wait:750;shot:first-battle-temporal-01;check:visual:battle-frame;wait:750;shot:first-battle-temporal-02;check:visual:battle-frame;wait:750;shot:first-battle-temporal-03;check:visual:battle-frame;wait:750;shot:first-battle-temporal-04;check:visual:battle-frame;wait:4000;shot:first-battle-live-10s-candidate;check:visual:battle-frame;check:visual:changed:first-battle-temporal-04;check:guest:battle-live-10s;wait:10000;shot:first-battle-live-20s-candidate;check:visual:battle-frame;check:visual:changed:first-battle-live-10s-candidate;check:guest:battle-live-20s;stop"
        }
        "eternal-sonata-field-direct" {
            return "gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;gate:visual:load-menu:30000;cross;wait:1000;dpad_up;wait:500;cross;gate:visual:load-complete:50000;cross;gate:visual:field-frame:25000;check:guest:loaded-field;shot:field;stick:left:left:1000;wait:1000;shot:field-move;check:guest:field-move;start;wait:1000;shot:pause-menu;check:guest:pause-menu"
        }
        "eternal-sonata-field-route" {
            return "gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;gate:visual:load-menu:30000;cross;wait:1000;dpad_up;wait:500;cross;gate:visual:load-complete:50000;cross;gate:visual:field-frame:25000;check:guest:loaded-field;shot:field;stick:left:left:1000;wait:1000;shot:field-move;check:guest:field-move;threads:field-route"
        }
        "eternal-sonata-menu-route" {
            return "gate:ppu-ready:150000;shot:title-before-load;check:visual:title-menu;dpad_down;wait:800;cross;gate:visual:load-menu:30000;cross;wait:1000;dpad_up;wait:500;cross;gate:visual:load-complete:50000;cross;gate:visual:field-frame:25000;check:guest:loaded-field;shot:field;start;wait:1000;shot:pause-menu;check:guest:pause-menu;threads:menu-route"
        }
        "strict-cool-gate" {
            # A no-input profile for install-only thermal qualification. The
            # dedicated wrapper supplies the fail-closed temperature limits.
            return ""
        }
        "custom" {
            return $Macro
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($Macro)) {
                return $Macro
            }
            throw "Unknown Thor input profile '$Name'. Supply -Macro or use strict-cool-gate, fast-forward-toggle, title-new-game, title-load-save, eternal-sonata-new-game-probe, eternal-sonata-load-probe, eternal-sonata-load-field-route, eternal-sonata-battle-intro-route, eternal-sonata-field-direct, eternal-sonata-field-route, eternal-sonata-menu-route."
        }
    }
}

function ConvertTo-ThorKeyCode {
    param([string]$Name)

    $key = $Name.Trim()
    $lower = $key.ToLowerInvariant()
    if ($keyAliases.ContainsKey($lower)) {
        return $keyAliases[$lower]
    }
    if ($key -match '^KEYCODE_') {
        return $key
    }
    throw "Unknown key alias '$Name'."
}

function ConvertTo-ThorRawKeyCode {
    param([string]$Name)

    $key = $Name.Trim()
    $lower = $key.ToLowerInvariant()
    if ($rawKeyAliases.ContainsKey($lower)) {
        return [int]$rawKeyAliases[$lower]
    }
    if ($key -match '^0x[0-9a-fA-F]+$') {
        return [Convert]::ToInt32($key, 16)
    }
    if ($key -match '^\d+$') {
        return [int]$key
    }
    throw "Unknown raw key alias '$Name'."
}

function ConvertTo-ThorDirectPadBits {
    param([string]$Name)

    $key = $Name.Trim()
    $lower = $key.ToLowerInvariant()
    if ($directPadAliases.ContainsKey($lower)) {
        return $directPadAliases[$lower]
    }
    throw "Unknown direct pad alias '$Name'."
}

function ConvertTo-ShellSingleQuoted {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-ThorPadKey {
    param([string]$Key)

    if ($InputMode -eq "OdinRaw") {
        Invoke-ThorRawKey -Key $Key -DurationMs 80
        return
    }

    if ($InputMode -eq "Direct") {
        Invoke-ThorDirectPadKey -Key $Key -DurationMs 80
        return
    }

    $code = ConvertTo-ThorKeyCode $Key
    & $Adb shell input gamepad -d $Display keyevent $code | Out-Null
}

function Invoke-ThorVirtualKey {
    param([string]$Key)

    $code = ConvertTo-ThorKeyCode $Key
    & $Adb shell input gamepad -d $Display keyevent $code | Out-Null
}

function Invoke-ThorDirectPadKey {
    param(
        [string]$Key,
        [int]$DurationMs = 80
    )

    $bits = ConvertTo-ThorDirectPadBits $Key
    $digital1 = [int]$bits[0]
    $digital2 = [int]$bits[1]
    & $Adb shell "am broadcast -a net.rpcsx.THOR_DEBUG_PAD -n $Package/net.rpcsx.ThorDebugPadReceiver --ei digital1 $digital1 --ei digital2 $digital2 --el durationMs $DurationMs" | Out-Null
}

function Invoke-ThorDirectStick {
    param(
        [string]$Stick,
        [string]$Direction,
        [int]$DurationMs = 500
    )

    $stickName = $Stick.Trim().ToLowerInvariant()
    $directionName = $Direction.Trim().ToLowerInvariant()
    $x = 127
    $y = 127

    switch ($directionName) {
        "up" { $y = 0 }
        "down" { $y = 255 }
        "left" { $x = 0 }
        "right" { $x = 255 }
        "up_left" { $x = 0; $y = 0 }
        "up-right" { $x = 255; $y = 0 }
        "up_right" { $x = 255; $y = 0 }
        "down_left" { $x = 0; $y = 255 }
        "down-right" { $x = 255; $y = 255 }
        "down_right" { $x = 255; $y = 255 }
        default { throw "Unknown stick direction '$Direction'." }
    }

    if ($stickName -eq "left" -or $stickName -eq "ls" -or $stickName -eq "l") {
        & $Adb shell "am broadcast -a net.rpcsx.THOR_DEBUG_PAD -n $Package/net.rpcsx.ThorDebugPadReceiver --ei leftStickX $x --ei leftStickY $y --el durationMs $DurationMs" | Out-Null
    } elseif ($stickName -eq "right" -or $stickName -eq "rs" -or $stickName -eq "r") {
        & $Adb shell "am broadcast -a net.rpcsx.THOR_DEBUG_PAD -n $Package/net.rpcsx.ThorDebugPadReceiver --ei rightStickX $x --ei rightStickY $y --el durationMs $DurationMs" | Out-Null
    } else {
        throw "Unknown stick '$Stick'. Use left/ls or right/rs."
    }
}

function Invoke-ThorRawKey {
    param(
        [string]$Key,
        [int]$DurationMs = 80
    )

    $code = ConvertTo-ThorRawKeyCode $Key
    & $Adb shell "sendevent $RawInputDevice 1 $code 1; sendevent $RawInputDevice 0 0 0" | Out-Null
    Start-Sleep -Milliseconds $DurationMs
    & $Adb shell "sendevent $RawInputDevice 1 $code 0; sendevent $RawInputDevice 0 0 0" | Out-Null
}

function Invoke-ThorPadCombo {
    param(
        [string[]]$Keys,
        [int]$DurationMs
    )

    if ($InputMode -eq "OdinRaw") {
        $codes = @()
        foreach ($key in $Keys) {
            $codes += ConvertTo-ThorRawKeyCode $key
        }

        foreach ($code in $codes) {
            & $Adb shell "sendevent $RawInputDevice 1 $code 1; sendevent $RawInputDevice 0 0 0" | Out-Null
        }
        Start-Sleep -Milliseconds $DurationMs
        $releaseCodes = @($codes)
        [array]::Reverse($releaseCodes)
        foreach ($code in $releaseCodes) {
            & $Adb shell "sendevent $RawInputDevice 1 $code 0; sendevent $RawInputDevice 0 0 0" | Out-Null
        }
        return
    }

    if ($InputMode -eq "Direct") {
        $digital1 = 0
        $digital2 = 0
        foreach ($key in $Keys) {
            $bits = ConvertTo-ThorDirectPadBits $key
            $digital1 = $digital1 -bor [int]$bits[0]
            $digital2 = $digital2 -bor [int]$bits[1]
        }
        & $Adb shell "am broadcast -a net.rpcsx.THOR_DEBUG_PAD -n $Package/net.rpcsx.ThorDebugPadReceiver --ei digital1 $digital1 --ei digital2 $digital2 --el durationMs $DurationMs" | Out-Null
        return
    }

    $codes = @()
    foreach ($key in $Keys) {
        $codes += ConvertTo-ThorKeyCode $key
    }

    & $Adb shell input gamepad -d $Display keycombination -t $DurationMs @codes | Out-Null
}

function Save-ThorScreenshot {
    param(
        [string]$Label,
        [int]$Index
    )

    $safe = New-ThorSafeLabel $Label
    $remote = "/sdcard/Android/data/$Package/files/debug-captures/$stamp-$safe.png"
    $localName = "{0:D2}-{1}.png" -f $Index, $safe
    Assert-ThorProcessIdentity "screenshot-$safe-pre"
    Invoke-ThorAdbText $Adb $captureDir "$localName.screencap.txt" @("shell", "mkdir -p '/sdcard/Android/data/$Package/files/debug-captures' && screencap -p '$remote'") -AllowFailure | Out-Null
    Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remote -LocalName $localName | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "$localName.cleanup.txt" @("shell", "rm -f '$remote'") -AllowFailure | Out-Null
    $script:LastThorScreenshotPath = Join-Path $captureDir $localName
    Assert-ThorProcessIdentity "screenshot-$safe-post"
}

function Save-ThorThreadSnapshot {
    param([string]$Label)

    $safe = New-ThorSafeLabel $Label
    $snapshotScript = Join-Path $PSScriptRoot "thor_thread_wait_snapshot.ps1"
    & $snapshotScript -Package $Package -Label $safe -Samples 3 -IntervalMs 1000 -OutputRoot $captureDir
}

function Get-ThorTemperatureSnapshot {
    $thermalZoneCommand = Get-ThorThermalZoneShellCommand
    $telemetryCommand = 'printf "__THOR_BATTERY__\n"; dumpsys battery; printf "__THOR_HARDWARE__\n"; dumpsys hardware_properties; printf "__THOR_ZONES__\n"; ' + $thermalZoneCommand
    $telemetryLines = @(Invoke-ThorAdbLines -Adb $Adb -AdbArgs @("shell", $telemetryCommand) -ScratchDir $captureDir -TimeoutSeconds 3)
    $batteryLines = @()
    $hardwareLines = @()
    $thermalZoneLines = @()
    $section = ""

    foreach ($line in $telemetryLines) {
        switch ($line) {
            "__THOR_BATTERY__" { $section = "battery"; continue }
            "__THOR_HARDWARE__" { $section = "hardware"; continue }
            "__THOR_ZONES__" { $section = "zones"; continue }
        }

        switch ($section) {
            "battery" { $batteryLines += $line }
            "hardware" { $hardwareLines += $line }
            "zones" { $thermalZoneLines += $line }
        }
    }

    $snapshotParams = @{
        BatteryLines = $batteryLines
        ThermalZoneLines = $thermalZoneLines
        HardwareLines = $hardwareLines
    }
    return Get-ThorThermalGuardSnapshot @snapshotParams
}

$script:ExpectedThorPackageProcessId = $null

function Get-ThorPackageProcessId {
    $processIdLines = @(& $Adb shell pidof $Package 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $processIdLines) {
        foreach ($candidate in ($line.ToString().Trim() -split '\s+')) {
            if ($candidate -match '^\d+$') {
                return $candidate
            }
        }
    }

    return $null
}

function Save-ThorProcessFailureEvidence {
    param(
        [string]$Stage,
        [string]$CurrentProcessId = "unknown"
    )

    $safeStage = New-ThorSafeLabel $Stage
    $baseName = "process-failure-$safeStage"
    @(
        "stage=$Stage",
        "expected_pid=$($script:ExpectedThorPackageProcessId)",
        "current_pid=$CurrentProcessId",
        "captured_at=$(Get-Date -Format o)"
    ) | Set-Content -LiteralPath (Join-Path $captureDir "$baseName-metadata.txt") -Encoding UTF8

    # Failure evidence is rare, so retain the complete in-memory logcat buffer.
    # A replacement process can emit hundreds of shader lines in seconds and
    # push the original fatal out of a short tail before the PID guard fires.
    $logcatLines = @(& $Adb logcat -d -v threadtime 2>&1)
    $logcatExitCode = $LASTEXITCODE
    $logcatLines | Set-Content -LiteralPath (Join-Path $captureDir "$baseName-logcat-full.txt") -Encoding UTF8

    $packagePattern = [regex]::Escape($Package)
    $expectedPattern = if ([string]::IsNullOrWhiteSpace($script:ExpectedThorPackageProcessId)) { '(?!)' } else { [regex]::Escape($script:ExpectedThorPackageProcessId) }
    $evidencePattern = "$packagePattern|$expectedPattern|RPCSX|RPCS3|ActivityManager|Zygote|libc|DEBUG|Fatal signal|signal 11|Segfault|terminated abnormally"
    @($logcatLines | Select-String -Pattern $evidencePattern -CaseSensitive:$false | ForEach-Object { $_.Line }) |
        Set-Content -LiteralPath (Join-Path $captureDir "$baseName-logcat-filtered.txt") -Encoding UTF8

    if ($logcatExitCode -ne 0) {
        "adb logcat exited with code $logcatExitCode" |
            Set-Content -LiteralPath (Join-Path $captureDir "$baseName-logcat-error.txt") -Encoding UTF8
    }
}

function Initialize-ThorProcessIdentity {
    if (-not $BootGame) {
        return
    }

    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $packageProcessId = Get-ThorPackageProcessId
        if (-not [string]::IsNullOrWhiteSpace($packageProcessId)) {
            $script:ExpectedThorPackageProcessId = $packageProcessId
            "$(Get-Date -Format o) stage=boot expected_pid=$packageProcessId current_pid=$packageProcessId status=established" |
                Out-File -LiteralPath (Join-Path $captureDir "process-guard.log") -Append -Encoding UTF8
            return
        }
        Start-Sleep -Milliseconds 250
    }

    Save-ThorProcessFailureEvidence "boot-no-process" "absent"
    & $Adb shell am force-stop $Package | Out-Null
    throw "RPCSX did not start within 5 seconds of the debug boot request. See the process-failure-boot-no-process logcat files."
}

function Get-ThorDebugBootHandshakeLog {
    param([Parameter(Mandatory = $true)][string]$RequestId)

    $logcatLines = @(& $Adb logcat -d -v brief -s "RPCSX-UI:V" "*:S" 2>&1)
    $logcatExitCode = $LASTEXITCODE
    $requestPattern = [regex]::Escape("request=$RequestId")
    $requestLines = @($logcatLines | Where-Object { $_ -match $requestPattern })
    return [pscustomobject]@{
        exit_code = $logcatExitCode
        all_lines = $logcatLines
        request_lines = $requestLines
        accepted = @($requestLines | Where-Object { $_ -match 'Thor debug boot accepted:' }).Count -gt 0
        rejected = @($requestLines | Where-Object { $_ -match 'Thor debug boot rejected:' }).Count -gt 0
    }
}

function Assert-ThorDebugBootAccepted {
    param(
        [Parameter(Mandatory = $true)][string]$RequestId,
        [int]$TimeoutMs = 30000
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $handshake = $null
    do {
        Assert-ThorProcessIdentity "debug-boot-handshake"
        $handshake = Get-ThorDebugBootHandshakeLog -RequestId $RequestId
        if ($handshake.rejected -or $handshake.accepted) {
            @($handshake.all_lines) | Set-Content -LiteralPath (Join-Path $captureDir "debug-boot-handshake.log") -Encoding UTF8
            $status = if ($handshake.accepted) { "accepted" } else { "rejected" }
            "$(Get-Date -Format o) request_id=$RequestId status=$status elapsed_ms=$($timer.ElapsedMilliseconds)" |
                Out-File -LiteralPath (Join-Path $captureDir "debug-boot-handshake-status.log") -Append -Encoding UTF8
            if ($handshake.rejected) {
                & $Adb shell am force-stop $Package | Out-Null
                throw "RPCSX rejected Thor debug boot request '$RequestId': $($handshake.request_lines -join ' ')"
            }
            return
        }
        Start-Sleep -Milliseconds 500
    } while ($timer.ElapsedMilliseconds -lt $TimeoutMs)

    if ($null -ne $handshake) {
        @($handshake.all_lines) | Set-Content -LiteralPath (Join-Path $captureDir "debug-boot-handshake.log") -Encoding UTF8
    }
    "$(Get-Date -Format o) request_id=$RequestId status=timeout elapsed_ms=$($timer.ElapsedMilliseconds)" |
        Out-File -LiteralPath (Join-Path $captureDir "debug-boot-handshake-status.log") -Append -Encoding UTF8
    Save-ThorProcessFailureEvidence "debug-boot-handshake-timeout" $script:ExpectedThorPackageProcessId
    & $Adb shell am force-stop $Package | Out-Null
    throw "RPCSX did not acknowledge Thor debug boot request '$RequestId' within $TimeoutMs ms; it was force-stopped before the visual route."
}

function Assert-ThorProcessIdentity {
    param([string]$Stage)

    if (-not $BootGame) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:ExpectedThorPackageProcessId)) {
        throw "Thor process identity guard was not initialized before '$Stage'."
    }

    $currentProcessId = Get-ThorPackageProcessId
    $currentText = if ([string]::IsNullOrWhiteSpace($currentProcessId)) { "absent" } else { $currentProcessId }
    if ($currentText -eq $script:ExpectedThorPackageProcessId) {
        return
    }

    "$(Get-Date -Format o) stage=$Stage expected_pid=$($script:ExpectedThorPackageProcessId) current_pid=$currentText status=failed" |
        Out-File -LiteralPath (Join-Path $captureDir "process-guard.log") -Append -Encoding UTF8
    Save-ThorProcessFailureEvidence $Stage $currentText
    & $Adb shell am force-stop $Package | Out-Null
    throw "RPCSX process changed at '$Stage' (expected PID $($script:ExpectedThorPackageProcessId), current PID $currentText). A native crash or app restart is assumed and RPCSX was force-stopped."
}

function Assert-ThorThermalBudget {
    param(
        [string]$Stage,
        [double]$BatteryLimitC = $MaxBatteryTemperatureC,
        [double]$SkinLimitC = $MaxSkinTemperatureC,
        [double]$SiliconLimitC = $MaxSiliconTemperatureC,
        [switch]$PassThru
    )

    if ($BatteryLimitC -le 0) {
        return
    }

    $snapshot = Get-ThorTemperatureSnapshot
    $batteryText = Format-ThorTemperatureC $snapshot.battery_temperature_c
    $skinText = Format-ThorTemperatureC $snapshot.skin_temperature_c
    $siliconText = Format-ThorTemperatureC $snapshot.silicon_temperature_c
    "$(Get-Date -Format o) stage=$Stage battery_temperature_c=$batteryText battery_source=$($snapshot.battery_source) battery_limit_c=$BatteryLimitC skin_temperature_c=$skinText skin_source=$($snapshot.skin_source) skin_limit_c=$SkinLimitC silicon_temperature_c=$siliconText silicon_source=$($snapshot.silicon_source) silicon_limit_c=$SiliconLimitC skin_sensor_count=$($snapshot.skin_sensor_count) silicon_sensor_count=$($snapshot.silicon_sensor_count) guard_sensor_count=$($snapshot.guard_sensor_count) thermal_zone_count=$($snapshot.thermal_zone_count) hardware_sensor_count=$($snapshot.hardware_sensor_count) sources=$($snapshot.source_summary)" |
        Out-File -LiteralPath (Join-Path $captureDir "thermal-guard.log") -Append -Encoding UTF8

    $violationParams = @{
        Snapshot = $snapshot
        MaxBatteryTemperatureC = $BatteryLimitC
        MaxSkinTemperatureC = $SkinLimitC
        MaxSiliconTemperatureC = $SiliconLimitC
    }
    $violation = Get-ThorThermalGuardViolation @violationParams
    if ($null -ne $violation) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "$($violation.message) Stage '$Stage'. RPCSX was force-stopped."
    }

    if ($PassThru) {
        return $snapshot
    }
}

function Assert-ThorRuntimeThermalBudget {
    param([string]$Stage)

    if ($MaxBatteryTemperatureC -le 0) {
        return
    }

    $snapshot = Assert-ThorThermalBudget $Stage -PassThru
    $decisionParams = @{
        Snapshot = $snapshot
        MaxSiliconTemperatureC = $MaxSiliconTemperatureC
        StopHeadroomC = $ThermalRuntimeStopHeadroomC
        ProbeWindowC = $ThermalRuntimeProbeWindowC
    }
    $decision = Get-ThorThermalRuntimeGuardDecision @decisionParams

    if ($null -ne $decision -and $decision.action -eq "confirm") {
        "$(Get-Date -Format o) stage=$Stage status=confirm-requested code=$($decision.code) probe_temperature_c=$($decision.probe_temperature_c) stop_temperature_c=$($decision.stop_temperature_c) hard_limit_c=$MaxSiliconTemperatureC" |
            Out-File -LiteralPath (Join-Path $captureDir "thermal-guard.log") -Append -Encoding UTF8
        $snapshot = Assert-ThorThermalBudget "$Stage-near-limit-confirm" -PassThru
        $decisionParams.Snapshot = $snapshot
        $decisionParams.Confirmed = $true
        $decision = Get-ThorThermalRuntimeGuardDecision @decisionParams
    }

    if ($null -ne $decision -and $decision.action -eq "stop") {
        "$(Get-Date -Format o) stage=$Stage status=failed code=$($decision.code) stop_temperature_c=$($decision.stop_temperature_c) hard_limit_c=$MaxSiliconTemperatureC" |
            Out-File -LiteralPath (Join-Path $captureDir "thermal-guard.log") -Append -Encoding UTF8
        & $Adb shell am force-stop $Package | Out-Null
        throw "$($decision.message) Stage '$Stage'. RPCSX was force-stopped."
    }
}

function Assert-ThorThermalPreflight {
    param([string]$Stage)

    if ($MaxBatteryTemperatureC -le 0) {
        return
    }

    $preflightBatteryLimitC = [Math]::Max(0.1, $MaxBatteryTemperatureC - $ThermalPreflightHeadroomC)
    $preflightSkinLimitC = [Math]::Max(0.1, $MaxSkinTemperatureC - $ThermalPreflightHeadroomC)
    $preflightSiliconLimitC = Get-ThorPreflightSiliconLimitC -RuntimeLimitC $MaxSiliconTemperatureC -HeadroomC $ThermalPreflightHeadroomC -MaxLaunchSiliconTemperatureC $MaxLaunchSiliconTemperatureC
    $snapshots = @()

    for ($sample = 1; $sample -le $ThermalPreflightSamples; $sample++) {
        $snapshots += Assert-ThorThermalBudget "$Stage-$sample-of-$ThermalPreflightSamples" -BatteryLimitC $preflightBatteryLimitC -SkinLimitC $preflightSkinLimitC -SiliconLimitC $preflightSiliconLimitC -PassThru
        if ($sample -lt $ThermalPreflightSamples) {
            Start-Sleep -Seconds $ThermalPreflightIntervalSeconds
        }
    }

    $trendViolation = Get-ThorThermalPreflightTrendViolation -Snapshots $snapshots -MaxRiseC $ThermalPreflightMaxRiseC
    if ($null -ne $trendViolation) {
        "$(Get-Date -Format o) stage=$Stage status=failed code=$($trendViolation.code) rise_c=$($trendViolation.rise_c) max_rise_c=$ThermalPreflightMaxRiseC" |
            Out-File -LiteralPath (Join-Path $captureDir "thermal-guard.log") -Append -Encoding UTF8
        & $Adb shell am force-stop $Package | Out-Null
        throw "$($trendViolation.message) Stage '$Stage'. RPCSX was force-stopped."
    }
}

function Wait-ThorThermallyBounded {
    param([int]$Milliseconds)

    $remaining = $Milliseconds
    while ($remaining -gt 0) {
        $slice = [Math]::Min($remaining, $ThermalPollIntervalSeconds * 1000)
        Start-Sleep -Milliseconds $slice
        $remaining -= $slice
        Assert-ThorProcessIdentity "wait-$Milliseconds-ms"
        Assert-ThorRuntimeThermalBudget "wait-$Milliseconds-ms"
    }
}

function Save-ThorGuestLogEvidence {
    param([string]$Label)

    $safeLabel = New-ThorSafeLabel $Label
    $remoteLog = "/storage/emulated/0/Android/data/$Package/files/cache/RPCSX.log"
    $logTail = @(& $Adb shell tail -n 800 $remoteLog 2>&1)
    $logExitCode = $LASTEXITCODE
    $localLog = Join-Path $captureDir "guest-health-$safeLabel.log"
    $logTail | Set-Content -LiteralPath $localLog -Encoding UTF8
    & (Join-Path $PSScriptRoot "summarize_thor_es_dispatch_provenance.ps1") `
        -InputPath $localLog -OutputDirectory $captureDir -Label $safeLabel | Out-Null

    return [PSCustomObject]@{
        SafeLabel = $safeLabel
        LogTail = $logTail
        Success = $logExitCode -eq 0
    }
}

function Sync-ThorGuestLogEvidence {
    param([string]$Label)

    $safeLabel = New-ThorSafeLabel $Label
    $syncOutput = @(
        & $Adb shell "am broadcast --receiver-foreground -a net.rpcsx.THOR_DEBUG_SYNC_LOG -n $Package/net.rpcsx.ThorDebugLogReceiver" 2>&1
    )
    $syncExitCode = $LASTEXITCODE
    $syncPath = Join-Path $captureDir "guest-log-sync-$safeLabel.txt"
    $syncOutput | Set-Content -LiteralPath $syncPath -Encoding UTF8
    $syncText = $syncOutput -join "`n"
    $syncMatch = [regex]::Match($syncText, 'Broadcast completed:\s*result=-1(?:,|\s).*data="checkpoint:(\d+)"')

    if ($syncExitCode -ne 0 -or -not $syncMatch.Success) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "Guest log synchronization failed at '$Label'. RPCSX was force-stopped; see guest-log-sync-$safeLabel.txt."
    }

    return [PSCustomObject]@{
        Sequence = [UInt64]$syncMatch.Groups[1].Value
        Path = $syncPath
    }
}

function Save-ThorFullGuestLogEvidence {
    param([string]$Label)

    $safeLabel = New-ThorSafeLabel $Label
    $remoteLog = "/storage/emulated/0/Android/data/$Package/files/cache/RPCSX.log"
    $localName = "RPCSX-full-$safeLabel.log"
    Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remoteLog -LocalName $localName | Out-Null
    $localLog = Join-Path $captureDir $localName
    if (Test-Path -LiteralPath $localLog) {
        & (Join-Path $PSScriptRoot "summarize_thor_es_dispatch_provenance.ps1") `
            -InputPath $localLog -OutputDirectory $captureDir -Label "full-$safeLabel" | Out-Null
    }
}

function Throw-ThorVisualFailure {
    param(
        [string]$Message,
        [string]$Label
    )

    Save-ThorGuestLogEvidence $Label | Out-Null
    Save-ThorFullGuestLogEvidence $Label
    throw $Message
}

function Assert-ThorGuestHealthy {
    param([string]$Label = "guest")

    $safeLabel = New-ThorSafeLabel $Label
    Assert-ThorProcessIdentity "guest-health-$safeLabel-pre"
    $syncEvidence = Sync-ThorGuestLogEvidence $Label
    $evidence = Save-ThorGuestLogEvidence $Label
    $logTail = @($evidence.LogTail)

    if (-not $evidence.Success) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "Could not read the guest log at '$Label'. RPCSX was force-stopped; see guest-health-$safeLabel.log."
    }

    $checkpoint = "Thor debug log sync checkpoint: $($syncEvidence.Sequence)."
    if (-not (($logTail -join "`n").Contains($checkpoint))) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "Guest log checkpoint was not durable at '$Label'. RPCSX was force-stopped; see $($syncEvidence.Path) and guest-health-$safeLabel.log."
    }

    $fatalMatches = @(Get-ThorGuestFatalMatches -Lines $logTail)
    $unknownDrawMatches = @(Get-ThorGuestUnknownDrawMatches -Lines $logTail)

    if ($unknownDrawMatches.Count -gt 0) {
        $unknownDrawMatches.Line |
            Sort-Object -Unique |
            Set-Content -LiteralPath (Join-Path $captureDir "guest-unknown-draw-$safeLabel.txt") -Encoding UTF8
    }

    if ($fatalMatches.Count -gt 0) {
        $fatalMatches.Line |
            Sort-Object -Unique |
            Set-Content -LiteralPath (Join-Path $captureDir "guest-fatal-$safeLabel.txt") -Encoding UTF8
        Save-ThorFullGuestLogEvidence "fatal-$safeLabel"
        & $Adb shell am force-stop $Package | Out-Null
        throw "Guest fatal detected at '$Label'. RPCSX was force-stopped; see guest-fatal-$safeLabel.txt."
    }

    if ($unknownDrawMatches.Count -gt 0 -and $strictGuestDrawStream) {
        Save-ThorFullGuestLogEvidence "unknown-draw-$safeLabel"
        & $Adb shell am force-stop $Package | Out-Null
        throw "Unknown guest draw command detected at '$Label'. RPCSX was force-stopped; see guest-unknown-draw-$safeLabel.txt. Pass -AllowUnknownDraw only for an explicit diagnostic capture."
    }

    Assert-ThorProcessIdentity "guest-health-$safeLabel-post"
}

function Get-ThorEvidenceBody {
    param([string]$Path)

    return @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object {
                $_ -and
                -not $_.StartsWith("#") -and
                $_ -notmatch '^exit='
            }
    )
}

function Assert-ThorInstalledApkIdentity {
    if (-not $BootGame -or [string]::IsNullOrWhiteSpace($normalizedExpectedInstalledApkSha256)) {
        return
    }

    $packagePathEvidence = Invoke-ThorAdbText $Adb $captureDir "installed-apk-package-path.txt" @("shell", "pm path $Package")
    $packageRows = @(
        Get-ThorEvidenceBody $packagePathEvidence |
            Where-Object { $_ -match '^package:/.+/base[.]apk$' }
    )
    if ($packageRows.Count -ne 1) {
        throw "Expected exactly one installed base.apk for $Package; found $($packageRows.Count)."
    }

    $remoteApk = $packageRows[0].Substring("package:".Length)
    $quotedRemoteApk = ConvertTo-ShellSingleQuoted $remoteApk
    $hashEvidence = Invoke-ThorAdbText $Adb $captureDir "installed-apk-sha256.txt" @("shell", "sha256sum $quotedRemoteApk")
    $hashBody = (Get-ThorEvidenceBody $hashEvidence) -join "`n"
    $hashMatch = [regex]::Match($hashBody, '(?i)\b([0-9a-f]{64})\b')
    if (-not $hashMatch.Success) {
        throw "Could not parse the installed base.apk SHA-256 for $Package."
    }

    $actualSha256 = $hashMatch.Groups[1].Value.ToUpperInvariant()
    $identityMatches = $actualSha256 -ceq $normalizedExpectedInstalledApkSha256
    @(
        "package=$Package",
        "remote_path=$remoteApk",
        "expected_sha256=$normalizedExpectedInstalledApkSha256",
        "actual_sha256=$actualSha256",
        "match=$identityMatches"
    ) | Set-Content -LiteralPath (Join-Path $captureDir "installed-apk-identity.txt") -Encoding UTF8

    if (-not $identityMatches) {
        throw "Installed APK identity mismatch for ${Package}: expected $normalizedExpectedInstalledApkSha256, got $actualSha256."
    }
}

$resolvedMacro = Get-ThorMacroForProfile $Profile

@(
    "# Thor Input Macro",
    "",
    "- Created: $(Get-Date -Format o)",
    "- Package: $Package",
    "- Device serial: $DeviceSerial",
    "- Profile: $Profile",
    "- Game path: $GamePath",
    "- Title ID: $TitleId",
    "- Display: $Display",
    "- Thor display pacing: $ThorDisplayPacing",
    "- Input mode requested: $requestedInputMode",
    "- Input mode: $InputMode",
    "- Battle profile forced direct input: $profileForcesDirectInput",
    "- Raw input device: $RawInputDevice",
    "- Thermal preflight samples: $ThermalPreflightSamples",
    "- Thermal preflight interval seconds: $ThermalPreflightIntervalSeconds",
    "- Thermal preflight headroom C: $ThermalPreflightHeadroomC",
    "- Max launch silicon temperature C: $MaxLaunchSiliconTemperatureC",
    "- Thermal preflight max silicon rise C: $ThermalPreflightMaxRiseC",
    "- Thermal poll interval seconds: $ThermalPollIntervalSeconds",
    "- Runtime thermal early-stop headroom C: $ThermalRuntimeStopHeadroomC",
    "- Runtime thermal confirmation window C: $ThermalRuntimeProbeWindowC",
    "- Max battery temperature C: $MaxBatteryTemperatureC",
    "- Max skin temperature C: $MaxSkinTemperatureC",
    "- Max silicon temperature C: $MaxSiliconTemperatureC",
    "- RSX cache preload workers (0=auto): $RsxCacheWorkers",
    "- RSX cached pipeline preload limit (0=all): $RsxCachePreloadLimit",
    "- RSX cached pipeline load budget ms (0=unbounded): $RsxCacheLoadBudgetMs",
    "- RSX cached pipeline compile budget ms (0=unbounded): $RsxCacheCompileBudgetMs",
    "- SPU cached-program preload limit (0=all): $SpuCachePreloadLimit",
    "- SPU cached-program compile budget ms (0=unbounded): $SpuCacheCompileBudgetMs",
    "- SPU startup native-object cache: $SpuNativeObjectCache",
    "- Startup cache-worker affinity mask (0=default scheduler): $CacheWorkerAffinityMask",
    "- Persistent Vulkan driver pipeline cache: $VkPipelineCache",
    "- Vulkan preload cache hits only: $VkPreloadCacheHitsOnly",
    "- Android RSX performance hint: $AdpfRsx",
    "- Startup cache phase pacing: $CachePhasePacing",
    "- Eternal Sonata PPU command interpreter: $EsPpuCommandInterp",
    "- Eternal Sonata PPU dispatch probe: $EsPpuDispatchProbe",
    "- Eternal Sonata async draw barrier requested: $requestedEsAsyncDrawBarrier",
    "- Eternal Sonata async draw barrier effective: $EsAsyncDrawBarrier",
    "- Unknown draw policy: $(if ($strictGuestDrawStream) { 'fail-closed' } else { 'record-only' })",
    "- Expected installed APK SHA-256: $(if ($normalizedExpectedInstalledApkSha256) { $normalizedExpectedInstalledApkSha256 } else { 'not-required' })",
    "- BootGame: $BootGame",
    "- ForceStop: $ForceStop",
    "- Macro: $resolvedMacro",
    "",
    'Syntax: `wait:MS`, `gate:ppu-ready:MAX_MS`, `gate:visual:load-menu:MAX_MS`, `gate:visual:load-complete:MAX_MS`, `gate:visual:field-frame:MAX_MS`, `shot:NAME`, `threads:NAME`, `check:guest:NAME`, `check:visual:not-ppu-compilation`, `check:visual:title-menu`, `check:visual:load-menu`, `check:visual:field-frame`, `check:visual:battle-frame`, `check:visual:changed:REFERENCE_LABEL`, `stop`, key aliases such as `cross`/`dpad_down`, and `combo:select+r1:800`. Eternal Sonata battle proofs fail closed on wrong-route, black-battle, and unknown-draw states; use `-AllowUnknownDraw` only for an explicit diagnostic capture.'
    'Hybrid input overrides: `virtual:cross` forces Android virtual gamepad input; `raw:dpad_down` forces Odin `/dev/input` injection; `direct:cross` sends a debug-only RPCSX overlay pad press.',
    'Direct stick syntax: `stick:left:up:1000`, `stick:ls:down_right:750`, or `stick:rs:left:500`.'
    'State-gated battle approach: `approach:battle:left:left:900:3:11000` retries a bounded stick pulse until the Eternal Sonata battle HUD is detected.'
    'Booted runs pin the initial RPCSX PID and fail closed if Android restarts the process; complete and filtered logcat evidence is captured before force-stop.'
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

if ($ForceStop -or $BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "force-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-workers-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_workers 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-preload-limit-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_preload_limit 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-load-budget-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_load_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-compile-budget-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-preload-limit-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-compile-budget-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-native-object-cache-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-worker-affinity-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-pipeline-cache-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_pipeline_cache on") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-preload-cache-hits-only-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_preload_cache_hits_only off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "adpf-rsx-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.adpf_rsx off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-phase-pacing-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_phase_pacing off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-command-interp-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_command_interp off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-dispatch-probe-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_dispatch_probe off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-async-draw-barrier-prelaunch-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_async_draw_barrier off") -AllowFailure | Out-Null
}

if ($BootGame) {
    Write-ThorLaunchPowerState -Adb $Adb -CaptureDir $captureDir
}

$tokens = @()
$index = 1
$script:LastThorScreenshotPath = $null
try {
Assert-ThorInstalledApkIdentity
Assert-ThorThermalPreflight "pre-run"

if ($BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-workers-set.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_workers $RsxCacheWorkers") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-workers-effective.txt" @("shell", "getprop debug.rpcsx.thor.rsx_cache_workers") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-preload-limit-set.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_preload_limit $RsxCachePreloadLimit") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-preload-limit-effective.txt" @("shell", "getprop debug.rpcsx.thor.rsx_cache_preload_limit") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-load-budget-set.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_load_budget_ms $RsxCacheLoadBudgetMs") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-load-budget-effective.txt" @("shell", "getprop debug.rpcsx.thor.rsx_cache_load_budget_ms") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-compile-budget-set.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms $RsxCacheCompileBudgetMs") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-compile-budget-effective.txt" @("shell", "getprop debug.rpcsx.thor.rsx_cache_compile_budget_ms") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-preload-limit-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit $SpuCachePreloadLimit") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-preload-limit-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_preload_limit") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-compile-budget-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms $SpuCacheCompileBudgetMs") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-compile-budget-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_cache_compile_budget_ms") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-native-object-cache-set.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache $SpuNativeObjectCache") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-native-object-cache-effective.txt" @("shell", "getprop debug.rpcsx.thor.spu_native_object_cache") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-worker-affinity-set.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask $CacheWorkerAffinityMask") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-worker-affinity-effective.txt" @("shell", "getprop debug.rpcsx.thor.cache_worker_affinity_mask") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-pipeline-cache-set.txt" @("shell", "setprop debug.rpcsx.thor.vk_pipeline_cache $VkPipelineCache") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-pipeline-cache-effective.txt" @("shell", "getprop debug.rpcsx.thor.vk_pipeline_cache") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-preload-cache-hits-only-set.txt" @("shell", "setprop debug.rpcsx.thor.vk_preload_cache_hits_only $VkPreloadCacheHitsOnly") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-preload-cache-hits-only-effective.txt" @("shell", "getprop debug.rpcsx.thor.vk_preload_cache_hits_only") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "adpf-rsx-set.txt" @("shell", "setprop debug.rpcsx.thor.adpf_rsx $AdpfRsx") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "adpf-rsx-effective.txt" @("shell", "getprop debug.rpcsx.thor.adpf_rsx") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-phase-pacing-set.txt" @("shell", "setprop debug.rpcsx.thor.cache_phase_pacing $CachePhasePacing") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-phase-pacing-effective.txt" @("shell", "getprop debug.rpcsx.thor.cache_phase_pacing") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-command-interp-set.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_command_interp $EsPpuCommandInterp") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-command-interp-effective.txt" @("shell", "getprop debug.rpcsx.thor.es_ppu_command_interp") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-dispatch-probe-set.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_dispatch_probe $EsPpuDispatchProbe") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-dispatch-probe-effective.txt" @("shell", "getprop debug.rpcsx.thor.es_ppu_dispatch_probe") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-async-draw-barrier-set.txt" @("shell", "setprop debug.rpcsx.thor.es_async_draw_barrier $EsAsyncDrawBarrier") | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-async-draw-barrier-effective.txt" @("shell", "getprop debug.rpcsx.thor.es_async_draw_barrier") | Out-Null
    $startupProfilePropertyNames = @(
        "debug.rpcsx.thor.rsx_cache_workers",
        "debug.rpcsx.thor.rsx_cache_preload_limit",
        "debug.rpcsx.thor.rsx_cache_load_budget_ms",
        "debug.rpcsx.thor.rsx_cache_compile_budget_ms",
        "debug.rpcsx.thor.spu_cache_preload_limit",
        "debug.rpcsx.thor.spu_cache_compile_budget_ms",
        "debug.rpcsx.thor.spu_native_object_cache",
        "debug.rpcsx.thor.cache_worker_affinity_mask",
        "debug.rpcsx.thor.vk_pipeline_cache",
        "debug.rpcsx.thor.vk_preload_cache_hits_only",
        "debug.rpcsx.thor.adpf_rsx",
        "debug.rpcsx.thor.cache_phase_pacing",
        "debug.rpcsx.thor.logcat",
        "debug.rpcsx.thor.syscall_stats",
        "debug.rpcsx.thor.spu_reduced_loop_detect",
        "debug.rpcsx.thor.spu_reduced_loop_emit",
        "debug.rpcsx.thor.spurs_probe",
        "debug.rpcsx.thor.es_sema_superpath",
        "debug.rpcsx.thor.es_dma_superpath",
        "debug.rpcsx.thor.rsx_blit_source_resolve",
        "debug.rpcsx.thor.rsx_auditor",
        "debug.rpcsx.thor.dump_prx",
        "debug.rpcsx.thor.es_frame_wait",
        "debug.rpcsx.thor.es_frame_wait_grace_us",
        "debug.rpcsx.thor.es_frame_wait_continuous_rearm",
        "log.tag.RPCS3",
        "log.tag.RPCSX-UI"
    )
    $startupProfilePropertyCommand = 'for p in ' + ($startupProfilePropertyNames -join ' ') + '; do printf "%s=%s\n" "$p" "$(getprop "$p")"; done'
    Invoke-ThorAdbText $Adb $captureDir "startup-profile-effective.txt" @("shell", $startupProfilePropertyCommand) | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "wake-display.txt" @("shell", "input keyevent KEYCODE_WAKEUP") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "dismiss-keyguard.txt" @("shell", "wm dismiss-keyguard") -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 500

    $debugBootRequestId = [Guid]::NewGuid().ToString("N")
    Invoke-ThorAdbText $Adb $captureDir "debug-boot-logcat-clear.txt" @("logcat", "-c") -AllowFailure | Out-Null
    $quotedPath = ConvertTo-ShellSingleQuoted $GamePath
    Invoke-ThorAdbText $Adb $captureDir "debug-boot.txt" @("shell", "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path $quotedPath --es titleId $TitleId --es thorDebugBootRequestId $debugBootRequestId --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true --ez thorDisplayPacing $thorDisplayPacingValue") -AllowFailure | Out-Null
    Initialize-ThorProcessIdentity
    Assert-ThorDebugBootAccepted -RequestId $debugBootRequestId
}

if (-not [string]::IsNullOrWhiteSpace($resolvedMacro)) {
    $tokens = $resolvedMacro.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

    foreach ($token in $tokens) {
        $line = "$(Get-Date -Format o) $token"
        $line | Out-File -LiteralPath (Join-Path $captureDir "macro.log") -Append -Encoding UTF8

        if ($token -ne 'stop') {
            Assert-ThorProcessIdentity "token-$token-pre"
        }

        if ($token -match '^wait:(\d+)$') {
            Wait-ThorThermallyBounded ([int]$Matches[1])
        } elseif ($token -match '^gate:ppu-ready(?::(\d+))?$') {
            $gateTimeoutMs = if ($Matches[1]) { [int]$Matches[1] } else { 120000 }
            if ($gateTimeoutMs -lt 10000 -or $gateTimeoutMs -gt 180000) {
                throw "PPU-ready gate timeout must be between 10000 and 180000 ms."
            }

            $gateTimer = [Diagnostics.Stopwatch]::StartNew()
            $gateAttempt = 0
            $readyCandidateCount = 0
            $ppuReady = $false
            while ($gateTimer.ElapsedMilliseconds -le $gateTimeoutMs) {
                $gateAttempt++
                $gateLabel = "ppu-ready-poll-{0:D2}" -f $gateAttempt
                Save-ThorScreenshot $gateLabel $index
                $index++
                Assert-ThorRuntimeThermalBudget "screenshot-$gateLabel"

                $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
                $readyCandidate = $classification.title_menu_present
                if ($readyCandidate) {
                    $readyCandidateCount++
                } else {
                    $readyCandidateCount = 0
                }

                "$(Get-Date -Format o) attempt=$gateAttempt elapsed_ms=$($gateTimer.ElapsedMilliseconds) timeout_ms=$gateTimeoutMs ready_candidate_count=$readyCandidateCount title_menu_present=$($classification.title_menu_present) title_magenta_percent=$($classification.title_magenta_percent) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) black_frame_present=$($classification.black_frame_present) dark_percent=$($classification.dark_percent) cyan_percent=$($classification.cyan_percent) progress_bar_white_percent=$($classification.progress_bar_white_percent) path=$($classification.path)" |
                    Out-File -LiteralPath (Join-Path $captureDir "ppu-ready-gate.log") -Append -Encoding UTF8

                # Compilation completion commonly exposes one or more fully
                # black transition frames before the title becomes ready for
                # input. Require the title selector in two consecutive frames
                # so a transient post-compilation image cannot authorize keys.
                if ($readyCandidateCount -ge 2) {
                    $ppuReady = $true
                    break
                }

                $remainingMs = $gateTimeoutMs - [int]$gateTimer.ElapsedMilliseconds
                if ($remainingMs -le 0) {
                    break
                }
                $pollDelayMs = if ($readyCandidate) { 2500 } else { 10000 }
                Wait-ThorThermallyBounded ([Math]::Min($pollDelayMs, $remainingMs))
            }
            $gateTimer.Stop()

            if (-not $ppuReady) {
                Throw-ThorVisualFailure "The Eternal Sonata title menu did not stabilize after PPU compilation within the bounded $gateTimeoutMs ms readiness gate; route inputs and gameplay claims are invalid." "visual-ppu-ready-timeout"
            }
        } elseif ($token -match '^gate:visual:(load-menu|load-complete|field-frame)(?::(\d+))?$') {
            $visualState = $Matches[1]
            $visualTimeoutMs = if ($Matches[2]) {
                [int]$Matches[2]
            } else {
                switch ($visualState) {
                    "load-menu" { 30000 }
                    "load-complete" { 50000 }
                    "field-frame" { 25000 }
                }
            }
            if ($visualTimeoutMs -lt 5000 -or $visualTimeoutMs -gt 60000) {
                throw "Visual-state gate timeout must be between 5000 and 60000 ms."
            }

            $visualTimer = [Diagnostics.Stopwatch]::StartNew()
            $visualAttempt = 0
            $visualStableCount = 0
            $visualReady = $false
            while ($visualTimer.ElapsedMilliseconds -le $visualTimeoutMs) {
                $visualAttempt++
                $visualLabel = "$visualState-gate-{0:D2}" -f $visualAttempt
                Save-ThorScreenshot $visualLabel $index
                $index++
                Assert-ThorProcessIdentity "visual-$visualState-$visualAttempt"
                Assert-ThorRuntimeThermalBudget "screenshot-$visualLabel"

                $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
                $visualCandidate = switch ($visualState) {
                    "load-menu" { $classification.load_menu_present }
                    "load-complete" { $classification.load_complete_present }
                    "field-frame" { $classification.field_frame_present }
                }
                if ($visualCandidate) {
                    $visualStableCount++
                } else {
                    $visualStableCount = 0
                }

                "$(Get-Date -Format o) state=$visualState attempt=$visualAttempt elapsed_ms=$($visualTimer.ElapsedMilliseconds) timeout_ms=$visualTimeoutMs candidate=$visualCandidate stable_count=$visualStableCount load_menu_present=$($classification.load_menu_present) load_complete_present=$($classification.load_complete_present) load_dialog_dark_percent=$($classification.load_dialog_dark_percent) load_dialog_edge_percent=$($classification.load_dialog_edge_percent) field_frame_present=$($classification.field_frame_present) title_menu_present=$($classification.title_menu_present) story_scene_present=$($classification.story_scene_present) battle_ui_present=$($classification.battle_ui_present) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) black_frame_present=$($classification.black_frame_present) path=$($classification.path)" |
                    Out-File -LiteralPath (Join-Path $captureDir "visual-$visualState-gate.log") -Append -Encoding UTF8

                if ($visualStableCount -ge 2) {
                    $visualReady = $true
                    break
                }

                $remainingMs = $visualTimeoutMs - [int]$visualTimer.ElapsedMilliseconds
                if ($remainingMs -le 0) {
                    break
                }
                Start-Sleep -Milliseconds ([Math]::Min(1500, $remainingMs))
            }
            $visualTimer.Stop()

            if (-not $visualReady) {
                Throw-ThorVisualFailure "Eternal Sonata visual state '$visualState' did not stabilize within $visualTimeoutMs ms; subsequent inputs are unsafe." "visual-$visualState-timeout"
            }
        } elseif ($token -match '^shot:(.+)$') {
            Save-ThorScreenshot $Matches[1] $index
            $index++
            Assert-ThorRuntimeThermalBudget "screenshot-$($Matches[1])"
        } elseif ($token -match '^check:guest(?::(.+))?$') {
            $healthLabel = if ($Matches[1]) { $Matches[1] } else { "guest" }
            Assert-ThorGuestHealthy $healthLabel
        } elseif ($token -eq 'check:visual:not-ppu-compilation') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The PPU compilation visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) black_frame_present=$($classification.black_frame_present) dark_percent=$($classification.dark_percent) cyan_percent=$($classification.cyan_percent) progress_bar_white_percent=$($classification.progress_bar_white_percent) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "ppu-compilation-visual-gate.log") -Append -Encoding UTF8

            if ($classification.ppu_compilation_screen_present) {
                Throw-ThorVisualFailure "PPU compilation is still visible after the boot wait; route inputs and gameplay claims are invalid." "visual-ppu-compilation-failure"
            }
            if ($classification.black_frame_present) {
                Throw-ThorVisualFailure "A black transition frame is still visible after the boot wait; route inputs and gameplay claims are invalid." "visual-black-boot-transition-failure"
            }
        } elseif ($token -eq 'check:visual:title-menu') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The title-menu visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) title_menu_present=$($classification.title_menu_present) title_magenta_percent=$($classification.title_magenta_percent) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) black_frame_present=$($classification.black_frame_present) dark_percent=$($classification.dark_percent) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "title-menu-visual-gate.log") -Append -Encoding UTF8

            if (-not $classification.title_menu_present) {
                Throw-ThorVisualFailure "The settled Eternal Sonata title menu is not visible; route inputs and gameplay claims are invalid." "visual-title-menu-failure"
            }
        } elseif ($token -eq 'check:visual:load-menu') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The Load-menu visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) load_menu_present=$($classification.load_menu_present) load_beige_samples=$($classification.load_beige_samples) load_total_samples=$($classification.load_total_samples) load_beige_percent=$($classification.load_beige_percent) title_menu_present=$($classification.title_menu_present) story_scene_present=$($classification.story_scene_present) black_frame_present=$($classification.black_frame_present) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "load-menu-visual-gate.log") -Append -Encoding UTF8

            if (-not $classification.load_menu_present) {
                Throw-ThorVisualFailure "The Eternal Sonata Load menu is not visible; a title input was dropped or the route entered the wrong state." "visual-load-menu-failure"
            }
        } elseif ($token -eq 'check:visual:load-complete') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The Load-complete visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) load_complete_present=$($classification.load_complete_present) load_menu_present=$($classification.load_menu_present) load_dialog_dark_percent=$($classification.load_dialog_dark_percent) load_dialog_edge_percent=$($classification.load_dialog_edge_percent) black_frame_present=$($classification.black_frame_present) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "load-complete-visual-gate.log") -Append -Encoding UTF8

            if (-not $classification.load_complete_present) {
                Throw-ThorVisualFailure "The Eternal Sonata Load-complete popup is not visible; dismissing the load state is unsafe." "visual-load-complete-failure"
            }
        } elseif ($token -eq 'check:visual:field-frame') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The field-frame visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) field_frame_present=$($classification.field_frame_present) story_scene_present=$($classification.story_scene_present) story_logo_bright_samples=$($classification.story_logo_bright_samples) story_logo_total_samples=$($classification.story_logo_total_samples) story_logo_bright_percent=$($classification.story_logo_bright_percent) load_menu_present=$($classification.load_menu_present) title_menu_present=$($classification.title_menu_present) battle_ui_present=$($classification.battle_ui_present) black_frame_present=$($classification.black_frame_present) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "field-frame-visual-gate.log") -Append -Encoding UTF8

            if (-not $classification.field_frame_present) {
                Throw-ThorVisualFailure "A controllable Eternal Sonata field frame is not visible; movement and battle inputs are unsafe in the current route state." "visual-field-frame-failure"
            }
        } elseif ($token -eq 'check:visual:battle-frame') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The battle-frame visual check requires a preceding screenshot."
            }

            $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
            "$(Get-Date -Format o) battle_ui_present=$($classification.battle_ui_present) black_frame_present=$($classification.black_frame_present) dark_percent=$($classification.dark_percent) cyan_percent=$($classification.cyan_percent) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) path=$($classification.path)" |
                Out-File -LiteralPath (Join-Path $captureDir "battle-frame-visual-gate.log") -Append -Encoding UTF8

            if ($classification.black_frame_present) {
                Throw-ThorVisualFailure "Black battle frame detected; transient renderer flicker is assumed." "visual-black-battle-frame-failure"
            }
            if (-not $classification.battle_ui_present) {
                Throw-ThorVisualFailure "Expected live Eternal Sonata battle HUD was not present." "visual-battle-hud-failure"
            }
        } elseif ($token -match '^check:visual:changed:(.+)$') {
            if ([string]::IsNullOrWhiteSpace($script:LastThorScreenshotPath)) {
                throw "The temporal-change visual check requires a preceding candidate screenshot."
            }

            $referenceLabel = $Matches[1]
            $referenceScreenshot = Get-ChildItem -LiteralPath $captureDir -Filter "*-$referenceLabel.png" -File |
                Sort-Object Name |
                Select-Object -Last 1
            if (-not $referenceScreenshot) {
                throw "Temporal-change reference screenshot '$referenceLabel' was not found in '$captureDir'."
            }

            $classification = Get-ThorScreenshotChangeClassification -ReferencePath $referenceScreenshot.FullName -CandidatePath $script:LastThorScreenshotPath
            "$(Get-Date -Format o) reference_label=$referenceLabel meaningful_change_present=$($classification.meaningful_change_present) changed_samples=$($classification.changed_samples) total_samples=$($classification.total_samples) changed_percent=$($classification.changed_percent) mean_rgb_delta=$($classification.mean_rgb_delta) reference_path=$($classification.reference_path) candidate_path=$($classification.candidate_path)" |
                Out-File -LiteralPath (Join-Path $captureDir "battle-temporal-change-gate.log") -Append -Encoding UTF8

            if (-not $classification.meaningful_change_present) {
                Throw-ThorVisualFailure "Battle image did not change meaningfully from '$referenceLabel'; frozen emulation is assumed." "visual-battle-temporal-failure"
            }
        } elseif ($token -match '^approach:battle:([^:]+):([^:]+):(\d+):(\d+):(\d+)$') {
            $approachStick = $Matches[1]
            $approachDirection = $Matches[2]
            $approachDurationMs = [int]$Matches[3]
            $approachAttempts = [int]$Matches[4]
            $approachSettleMs = [int]$Matches[5]
            $battleUiReached = $false

            if ($approachAttempts -lt 1 -or $approachAttempts -gt 6) {
                throw "Battle approach attempts must be between 1 and 6."
            }

            for ($attempt = 1; $attempt -le $approachAttempts; $attempt++) {
                Assert-ThorRuntimeThermalBudget "battle-approach-$attempt-pre"
                Invoke-ThorDirectStick -Stick $approachStick -Direction $approachDirection -DurationMs $approachDurationMs
                Wait-ThorThermallyBounded ($approachDurationMs + $approachSettleMs)

                $label = "battle-approach-$attempt-candidate"
                Save-ThorScreenshot $label $index
                $index++
                Assert-ThorRuntimeThermalBudget "screenshot-$label"
                Assert-ThorGuestHealthy "battle-approach-$attempt"

                $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
                "$(Get-Date -Format o) attempt=$attempt battle_ui_present=$($classification.battle_ui_present) black_frame_present=$($classification.black_frame_present) dark_percent=$($classification.dark_percent) ppu_compilation_screen_present=$($classification.ppu_compilation_screen_present) cyan_samples=$($classification.cyan_samples) total_samples=$($classification.total_samples) cyan_percent=$($classification.cyan_percent) progress_bar_white_percent=$($classification.progress_bar_white_percent) path=$($classification.path)" |
                    Out-File -LiteralPath (Join-Path $captureDir "battle-visual-gate.log") -Append -Encoding UTF8

                if ($classification.battle_ui_present) {
                    $battleUiReached = $true
                    break
                }
            }

            if (-not $battleUiReached) {
                Throw-ThorVisualFailure "Battle UI was not detected after $approachAttempts bounded movement attempts." "visual-battle-approach-failure"
            }
        } elseif ($token -eq 'stop') {
            Invoke-ThorAdbText $Adb $captureDir "macro-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
        } elseif ($token -match '^threads:(.+)$') {
            Save-ThorThreadSnapshot $Matches[1]
        } elseif ($token -match '^virtual:(.+)$') {
            Invoke-ThorVirtualKey $Matches[1]
            Start-Sleep -Milliseconds $DefaultWaitMs
        } elseif ($token -match '^raw:(.+)$') {
            Invoke-ThorRawKey -Key $Matches[1] -DurationMs 80
            Start-Sleep -Milliseconds $DefaultWaitMs
        } elseif ($token -match '^direct:(.+)$') {
            Invoke-ThorDirectPadKey -Key $Matches[1] -DurationMs 80
            Start-Sleep -Milliseconds $DefaultWaitMs
        } elseif ($token -match '^stick:([^:]+):([^:]+)(?::(\d+))?$') {
            $duration = if ($Matches[3]) { [int]$Matches[3] } else { 500 }
            Invoke-ThorDirectStick -Stick $Matches[1] -Direction $Matches[2] -DurationMs $duration
            Start-Sleep -Milliseconds $DefaultWaitMs
        } elseif ($token -match '^combo:([^:]+)(?::(\d+))?$') {
            $keys = $Matches[1].Split('+') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            $duration = if ($Matches[2]) { [int]$Matches[2] } else { 500 }
            Invoke-ThorPadCombo $keys $duration
            Start-Sleep -Milliseconds $DefaultWaitMs
        } else {
            Invoke-ThorPadKey $token
            Start-Sleep -Milliseconds $DefaultWaitMs
        }

        if ($token -ne 'stop') {
            Assert-ThorProcessIdentity "token-$token-post"
        }
    }
} catch {
    $failure = $_
    if ($ForceStop -or $BootGame -or $tokens -contains 'stop') {
        Invoke-ThorAdbText $Adb $captureDir "macro-failure-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
    }

    if ($ForceStop -and -not $BootGame -and -not $PostSnapshot) {
        Invoke-ThorAdbText $Adb $captureDir "failure-pid.txt" @("shell", "pidof $Package") -AllowFailure | Out-Null
    }

    $failure.Exception.Data["ThorCaptureDirectory"] = $captureDir
    $failure.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "macro-failure.txt") -Encoding UTF8

    try {
        Assert-ThorThermalBudget "failure-post-stop"
    } catch {
        $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "macro-failure-thermal-error.txt") -Encoding UTF8
    }

    if ($PostSnapshot -or $BootGame) {
        try {
            Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "failure"
        } catch {
            $_.ToString() | Set-Content -LiteralPath (Join-Path $captureDir "macro-failure-snapshot-error.txt") -Encoding UTF8
        }
    }

    if ($BootGame) {
        Invoke-ThorAdbText $Adb $captureDir "rsx-cache-workers-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_workers 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "rsx-cache-preload-limit-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_preload_limit 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "rsx-cache-load-budget-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_load_budget_ms 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "rsx-cache-compile-budget-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "spu-cache-preload-limit-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "spu-cache-compile-budget-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "spu-native-object-cache-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "cache-worker-affinity-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask 0") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "vk-pipeline-cache-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_pipeline_cache on") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "vk-preload-cache-hits-only-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_preload_cache_hits_only off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "adpf-rsx-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.adpf_rsx off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "cache-phase-pacing-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_phase_pacing off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "es-ppu-command-interp-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_command_interp off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "es-ppu-dispatch-probe-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_dispatch_probe off") -AllowFailure | Out-Null
        Invoke-ThorAdbText $Adb $captureDir "es-async-draw-barrier-failure-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_async_draw_barrier off; setprop debug.rpcsx.thor.es_sema_superpath off; setprop debug.rpcsx.thor.es_dma_superpath off; setprop debug.rpcsx.thor.rsx_blit_source_resolve off; setprop debug.rpcsx.thor.es_frame_wait off; setprop debug.rpcsx.thor.es_frame_wait_grace_us 0; setprop debug.rpcsx.thor.es_frame_wait_continuous_rearm off") -AllowFailure | Out-Null
    }

    throw $failure
}

if ($BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-workers-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_workers 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-preload-limit-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_preload_limit 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-load-budget-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_load_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "rsx-cache-compile-budget-reset.txt" @("shell", "setprop debug.rpcsx.thor.rsx_cache_compile_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-preload-limit-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_preload_limit 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-cache-compile-budget-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_cache_compile_budget_ms 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "spu-native-object-cache-reset.txt" @("shell", "setprop debug.rpcsx.thor.spu_native_object_cache off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-worker-affinity-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_worker_affinity_mask 0") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-pipeline-cache-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_pipeline_cache on") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "vk-preload-cache-hits-only-reset.txt" @("shell", "setprop debug.rpcsx.thor.vk_preload_cache_hits_only off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "adpf-rsx-reset.txt" @("shell", "setprop debug.rpcsx.thor.adpf_rsx off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "cache-phase-pacing-reset.txt" @("shell", "setprop debug.rpcsx.thor.cache_phase_pacing off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-command-interp-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_command_interp off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-ppu-dispatch-probe-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_ppu_dispatch_probe off") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "es-async-draw-barrier-reset.txt" @("shell", "setprop debug.rpcsx.thor.es_async_draw_barrier off; setprop debug.rpcsx.thor.es_sema_superpath off; setprop debug.rpcsx.thor.es_dma_superpath off; setprop debug.rpcsx.thor.rsx_blit_source_resolve off; setprop debug.rpcsx.thor.es_frame_wait off; setprop debug.rpcsx.thor.es_frame_wait_grace_us 0; setprop debug.rpcsx.thor.es_frame_wait_continuous_rearm off") -AllowFailure | Out-Null
    $startupProfileResetPropertyNames = @(
        "debug.rpcsx.thor.rsx_cache_workers",
        "debug.rpcsx.thor.rsx_cache_preload_limit",
        "debug.rpcsx.thor.rsx_cache_load_budget_ms",
        "debug.rpcsx.thor.rsx_cache_compile_budget_ms",
        "debug.rpcsx.thor.spu_cache_preload_limit",
        "debug.rpcsx.thor.spu_cache_compile_budget_ms",
        "debug.rpcsx.thor.spu_native_object_cache",
        "debug.rpcsx.thor.cache_worker_affinity_mask",
        "debug.rpcsx.thor.vk_pipeline_cache",
        "debug.rpcsx.thor.vk_preload_cache_hits_only",
        "debug.rpcsx.thor.adpf_rsx",
        "debug.rpcsx.thor.cache_phase_pacing",
        "debug.rpcsx.thor.es_ppu_command_interp",
        "debug.rpcsx.thor.es_ppu_dispatch_probe",
        "debug.rpcsx.thor.es_async_draw_barrier",
        "debug.rpcsx.thor.es_sema_superpath",
        "debug.rpcsx.thor.es_dma_superpath",
        "debug.rpcsx.thor.rsx_blit_source_resolve",
        "debug.rpcsx.thor.es_frame_wait",
        "debug.rpcsx.thor.es_frame_wait_grace_us",
        "debug.rpcsx.thor.es_frame_wait_continuous_rearm"
    )
    $startupProfileResetPropertyCommand = 'for p in ' + ($startupProfileResetPropertyNames -join ' ') + '; do printf "%s=%s\n" "$p" "$(getprop "$p")"; done'
    Invoke-ThorAdbText $Adb $captureDir "startup-profile-reset-effective.txt" @("shell", $startupProfileResetPropertyCommand) | Out-Null
}

Assert-ThorRuntimeThermalBudget "post-run"

if ($PostSnapshot) {
    Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "post"
}

Write-Host "Thor input macro capture: $captureDir"
if ($PassThruCaptureDirectory) {
    Write-Output $captureDir
}
