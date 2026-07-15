param(
    [string]$Package = "net.rpcsx.easy",
    [string]$Serial = "",
    [string]$Profile = "custom",
    [string]$Macro = "",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [int]$Display = 0,
    [int]$DefaultWaitMs = 500,
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Virtual",
    [string]$RawInputDevice = "/dev/input/event9",
    [double]$MaxBatteryTemperatureC = 39.0,
    [switch]$BootGame,
    [switch]$ForceStop,
    [switch]$PostSnapshot
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

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
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeProfile = New-ThorSafeLabel $Profile
$captureDir = Join-Path $RepoRoot "debug-captures\android-speed-sprint\$stamp-thor-input-$safeProfile"
New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

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
            return "wait:90000;shot:title-before-load;dpad_down;wait:800;shot:title-load-selected;cross;wait:55000;shot:load-save-list;cross;wait:1000;dpad_up;wait:500;cross;wait:65000;shot:load-complete;cross;wait:30000;shot:loaded-field;threads:load-field-route"
        }
        "eternal-sonata-battle-intro-route" {
            # Screenshot labels remain candidates until visual review confirms the battle UI.
            # A short screenshot burst samples transient corruption/flicker without
            # the sustained encoder load of screen recording. The later 10/20s
            # checkpoints still cover battle stability. Thread snapshots stay out
            # of this visual route so profiling overhead cannot perturb the proof.
            return "wait:75000;shot:title-before-load;dpad_down;wait:800;cross;wait:20000;shot:load-save-list;cross;wait:1000;dpad_up;wait:500;cross;wait:35000;shot:load-complete;cross;wait:12000;shot:loaded-field;stick:left:down_left:700;wait:1000;approach:battle:left:left:900:3:11000;shot:first-battle-prompt-candidate;dpad_down;wait:300;cross;wait:4000;shot:first-battle-active-candidate;check:guest:battle-active;wait:750;shot:first-battle-temporal-01;wait:750;shot:first-battle-temporal-02;wait:750;shot:first-battle-temporal-03;wait:750;shot:first-battle-temporal-04;wait:4000;shot:first-battle-live-10s-candidate;check:guest:battle-live-10s;wait:10000;shot:first-battle-live-20s-candidate;check:guest:battle-live-20s;stop"
        }
        "eternal-sonata-field-direct" {
            return "wait:90000;cross;wait:20000;start;wait:3000;cross;wait:1000;cross;wait:100000;shot:field;stick:left:left:1000;wait:1000;shot:field-move;start;wait:1000;shot:pause-menu"
        }
        "eternal-sonata-field-route" {
            return "wait:90000;cross;wait:20000;start;wait:3000;cross;wait:1000;cross;wait:100000;shot:field;stick:left:left:1000;wait:1000;shot:field-move;threads:field-route"
        }
        "eternal-sonata-menu-route" {
            return "wait:90000;cross;wait:20000;start;wait:3000;cross;wait:1000;cross;wait:100000;shot:field;start;wait:1000;shot:pause-menu;threads:menu-route"
        }
        "custom" {
            return $Macro
        }
        default {
            if (-not [string]::IsNullOrWhiteSpace($Macro)) {
                return $Macro
            }
            throw "Unknown Thor input profile '$Name'. Supply -Macro or use fast-forward-toggle, title-new-game, title-load-save, eternal-sonata-new-game-probe, eternal-sonata-load-probe, eternal-sonata-load-field-route, eternal-sonata-battle-intro-route, eternal-sonata-field-direct, eternal-sonata-field-route, eternal-sonata-menu-route."
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

function Get-ThorBatteryTemperatureC {
    $batteryLines = @(& $Adb shell dumpsys battery 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    foreach ($line in $batteryLines) {
        if ($line -match '^\s*temperature:\s*(-?\d+)\s*$') {
            return ([double]$Matches[1] / 10.0)
        }
    }

    return $null
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
    param([string]$Stage)

    $safeStage = New-ThorSafeLabel $Stage
    Invoke-ThorAdbText $Adb $captureDir "process-failure-$safeStage-logcat.txt" @("logcat", "-v", "threadtime", "-t", "400") -AllowFailure | Out-Null
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

    Save-ThorProcessFailureEvidence "boot-no-process"
    & $Adb shell am force-stop $Package | Out-Null
    throw "RPCSX did not start within 5 seconds of the debug boot request. See process-failure-boot-no-process-logcat.txt."
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
    Save-ThorProcessFailureEvidence $Stage
    & $Adb shell am force-stop $Package | Out-Null
    throw "RPCSX process changed at '$Stage' (expected PID $($script:ExpectedThorPackageProcessId), current PID $currentText). A native crash or app restart is assumed and RPCSX was force-stopped."
}

function Assert-ThorThermalBudget {
    param([string]$Stage)

    if ($MaxBatteryTemperatureC -le 0) {
        return
    }

    $temperatureC = Get-ThorBatteryTemperatureC
    $temperatureText = if ($null -eq $temperatureC) { "unknown" } else { $temperatureC.ToString("F1", [Globalization.CultureInfo]::InvariantCulture) }
    "$(Get-Date -Format o) stage=$Stage battery_temperature_c=$temperatureText limit_c=$MaxBatteryTemperatureC" |
        Out-File -LiteralPath (Join-Path $captureDir "thermal-guard.log") -Append -Encoding UTF8

    if ($null -ne $temperatureC -and $temperatureC -ge $MaxBatteryTemperatureC) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "Thor battery temperature is $temperatureText C at '$Stage', at or above the $MaxBatteryTemperatureC C limit. RPCSX was force-stopped."
    }
}

function Wait-ThorThermallyBounded {
    param([int]$Milliseconds)

    $remaining = $Milliseconds
    while ($remaining -gt 0) {
        $slice = [Math]::Min($remaining, 5000)
        Start-Sleep -Milliseconds $slice
        $remaining -= $slice
        Assert-ThorProcessIdentity "wait-$Milliseconds-ms"
        Assert-ThorThermalBudget "wait-$Milliseconds-ms"
    }
}

function Assert-ThorGuestHealthy {
    param([string]$Label = "guest")

    $safeLabel = New-ThorSafeLabel $Label
    Assert-ThorProcessIdentity "guest-health-$safeLabel-pre"
    $remoteLog = "/storage/emulated/0/Android/data/$Package/files/cache/RPCSX.log"
    $logTail = @(& $Adb shell tail -n 800 $remoteLog 2>&1)
    $logExitCode = $LASTEXITCODE
    $logTail | Set-Content -LiteralPath (Join-Path $captureDir "guest-health-$safeLabel.log") -Encoding UTF8

    if ($logExitCode -ne 0) {
        & $Adb shell am force-stop $Package | Out-Null
        throw "Could not read the guest log at '$Label'. RPCSX was force-stopped; see guest-health-$safeLabel.log."
    }

    $fatalPattern = 'VM: Access violation|Emulation has been frozen|Unknown STOP code|VK_ERROR_DEVICE_LOST|Verification failed|LLVM ERROR|Segfault reading location|Thread terminated due to fatal error|terminated abnormally'
    $fatalMatches = @($logTail | Select-String -Pattern $fatalPattern -CaseSensitive:$false)
    $unknownDrawMatches = @($logTail | Select-String -Pattern 'unknown draw command' -CaseSensitive:$false)
    if ($unknownDrawMatches.Count -gt 0) {
        $unknownDrawMatches.Line |
            Sort-Object -Unique |
            Set-Content -LiteralPath (Join-Path $captureDir "guest-unknown-draw-$safeLabel.txt") -Encoding UTF8
    }

    if ($fatalMatches.Count -gt 0) {
        $fatalMatches.Line | Set-Content -LiteralPath (Join-Path $captureDir "guest-fatal-$safeLabel.txt") -Encoding UTF8
        & $Adb shell am force-stop $Package | Out-Null
        throw "Guest fatal detected at '$Label'. RPCSX was force-stopped; see guest-fatal-$safeLabel.txt."
    }

    Assert-ThorProcessIdentity "guest-health-$safeLabel-post"
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
    "- Display: $Display",
    "- Input mode: $InputMode",
    "- Raw input device: $RawInputDevice",
    "- Max battery temperature C: $MaxBatteryTemperatureC",
    "- BootGame: $BootGame",
    "- ForceStop: $ForceStop",
    "- Macro: $resolvedMacro",
    "",
    "Syntax: `wait:MS`, `shot:NAME`, `threads:NAME`, `check:guest:NAME`, `stop`, key aliases such as `cross`/`dpad_down`, and `combo:select+r1:800`."
    "Hybrid input overrides: `virtual:cross` forces Android virtual gamepad input; `raw:dpad_down` forces Odin `/dev/input` injection; `direct:cross` sends a debug-only RPCSX overlay pad press.",
    "Direct stick syntax: `stick:left:up:1000`, `stick:ls:down_right:750`, or `stick:rs:left:500`."
    "State-gated battle approach: `approach:battle:left:left:900:3:11000` retries a bounded stick pulse until the Eternal Sonata battle HUD is detected."
    "Booted runs pin the initial RPCSX PID and fail closed if Android restarts the process; the last 400 logcat lines are captured before force-stop."
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

Assert-ThorThermalBudget "pre-run"

if ($ForceStop -or $BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "force-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
}

if ($BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "wake-display.txt" @("shell", "input keyevent KEYCODE_WAKEUP") -AllowFailure | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "dismiss-keyguard.txt" @("shell", "wm dismiss-keyguard") -AllowFailure | Out-Null
    Start-Sleep -Milliseconds 500

    $quotedPath = ConvertTo-ShellSingleQuoted $GamePath
    Invoke-ThorAdbText $Adb $captureDir "debug-boot.txt" @("shell", "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path $quotedPath") -AllowFailure | Out-Null
    Initialize-ThorProcessIdentity
}

$tokens = @()
if (-not [string]::IsNullOrWhiteSpace($resolvedMacro)) {
    $tokens = $resolvedMacro.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$index = 1
$script:LastThorScreenshotPath = $null
try {
    foreach ($token in $tokens) {
        $line = "$(Get-Date -Format o) $token"
        $line | Out-File -LiteralPath (Join-Path $captureDir "macro.log") -Append -Encoding UTF8

        if ($token -ne 'stop') {
            Assert-ThorProcessIdentity "token-$token-pre"
        }

        if ($token -match '^wait:(\d+)$') {
            Wait-ThorThermallyBounded ([int]$Matches[1])
        } elseif ($token -match '^shot:(.+)$') {
            Save-ThorScreenshot $Matches[1] $index
            $index++
            Assert-ThorThermalBudget "screenshot-$($Matches[1])"
        } elseif ($token -match '^check:guest(?::(.+))?$') {
            $healthLabel = if ($Matches[1]) { $Matches[1] } else { "guest" }
            Assert-ThorGuestHealthy $healthLabel
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
                Assert-ThorThermalBudget "battle-approach-$attempt-pre"
                Invoke-ThorDirectStick -Stick $approachStick -Direction $approachDirection -DurationMs $approachDurationMs
                Wait-ThorThermallyBounded ($approachDurationMs + $approachSettleMs)

                $label = "battle-approach-$attempt-candidate"
                Save-ThorScreenshot $label $index
                $index++
                Assert-ThorThermalBudget "screenshot-$label"
                Assert-ThorGuestHealthy "battle-approach-$attempt"

                $classification = Get-ThorBattleUiClassification -Path $script:LastThorScreenshotPath
                "$(Get-Date -Format o) attempt=$attempt battle_ui_present=$($classification.battle_ui_present) cyan_samples=$($classification.cyan_samples) total_samples=$($classification.total_samples) cyan_percent=$($classification.cyan_percent) path=$($classification.path)" |
                    Out-File -LiteralPath (Join-Path $captureDir "battle-visual-gate.log") -Append -Encoding UTF8

                if ($classification.battle_ui_present) {
                    $battleUiReached = $true
                    break
                }
            }

            if (-not $battleUiReached) {
                throw "Battle UI was not detected after $approachAttempts bounded movement attempts."
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
    if ($tokens -contains 'stop') {
        Invoke-ThorAdbText $Adb $captureDir "macro-failure-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
    }
    throw $failure
}

Assert-ThorThermalBudget "post-run"

if ($PostSnapshot) {
    Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "post"
}

Write-Host "Thor input macro capture: $captureDir"
