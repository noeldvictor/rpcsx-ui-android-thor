param(
    [string]$Package = "net.rpcsx.easy",
    [string]$Profile = "custom",
    [string]$Macro = "",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [int]$Display = 0,
    [int]$DefaultWaitMs = 500,
    [ValidateSet("Virtual", "OdinRaw", "Direct")]
    [string]$InputMode = "Virtual",
    [string]$RawInputDevice = "/dev/input/event9",
    [switch]$BootGame,
    [switch]$ForceStop,
    [switch]$PostSnapshot
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb
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
            throw "Unknown Thor input profile '$Name'. Supply -Macro or use fast-forward-toggle, title-new-game, title-load-save, eternal-sonata-new-game-probe, eternal-sonata-load-probe, eternal-sonata-field-direct, eternal-sonata-field-route, eternal-sonata-menu-route."
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
    Invoke-ThorAdbText $Adb $captureDir "$localName.screencap.txt" @("shell", "mkdir -p '/sdcard/Android/data/$Package/files/debug-captures' && screencap -p '$remote'") -AllowFailure | Out-Null
    Copy-ThorAdbFile -Adb $Adb -CaptureDir $captureDir -DeviceFilesDir $captureDir -Remote $remote -LocalName $localName | Out-Null
    Invoke-ThorAdbText $Adb $captureDir "$localName.cleanup.txt" @("shell", "rm -f '$remote'") -AllowFailure | Out-Null
}

function Save-ThorThreadSnapshot {
    param([string]$Label)

    $safe = New-ThorSafeLabel $Label
    $snapshotScript = Join-Path $PSScriptRoot "thor_thread_wait_snapshot.ps1"
    & $snapshotScript -Package $Package -Label $safe -Samples 3 -IntervalMs 1000 -OutputRoot $captureDir
}

$resolvedMacro = Get-ThorMacroForProfile $Profile

@(
    "# Thor Input Macro",
    "",
    "- Created: $(Get-Date -Format o)",
    "- Package: $Package",
    "- Profile: $Profile",
    "- Game path: $GamePath",
    "- Display: $Display",
    "- Input mode: $InputMode",
    "- Raw input device: $RawInputDevice",
    "- BootGame: $BootGame",
    "- ForceStop: $ForceStop",
    "- Macro: $resolvedMacro",
    "",
    "Syntax: `wait:MS`, `shot:NAME`, `threads:NAME`, key aliases such as `cross`/`dpad_down`, and `combo:select+r1:800`."
    "Hybrid input overrides: `virtual:cross` forces Android virtual gamepad input; `raw:dpad_down` forces Odin `/dev/input` injection; `direct:cross` sends a debug-only RPCSX overlay pad press.",
    "Direct stick syntax: `stick:left:up:1000`, `stick:ls:down_right:750`, or `stick:rs:left:500`."
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

if ($ForceStop -or $BootGame) {
    Invoke-ThorAdbText $Adb $captureDir "force-stop.txt" @("shell", "am force-stop $Package") -AllowFailure | Out-Null
}

if ($BootGame) {
    $quotedPath = ConvertTo-ShellSingleQuoted $GamePath
    Invoke-ThorAdbText $Adb $captureDir "debug-boot.txt" @("shell", "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path $quotedPath") -AllowFailure | Out-Null
}

$tokens = @()
if (-not [string]::IsNullOrWhiteSpace($resolvedMacro)) {
    $tokens = $resolvedMacro.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

$index = 1
foreach ($token in $tokens) {
    $line = "$(Get-Date -Format o) $token"
    $line | Out-File -LiteralPath (Join-Path $captureDir "macro.log") -Append -Encoding UTF8

    if ($token -match '^wait:(\d+)$') {
        Start-Sleep -Milliseconds ([int]$Matches[1])
    } elseif ($token -match '^shot:(.+)$') {
        Save-ThorScreenshot $Matches[1] $index
        $index++
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
}

if ($PostSnapshot) {
    Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "post"
}

Write-Host "Thor input macro capture: $captureDir"
