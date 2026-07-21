param(
    [string]$CaptureRoot = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "thor_debug_common.ps1")

function Assert-ThorVisualEqual {
    param(
        [string]$Name,
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name failed: expected '$Expected', got '$Actual'."
    }
}

function New-ThorSyntheticRouteFrame {
    param(
        [string]$Path,
        [ValidateSet("load-list", "load-complete", "field", "launcher-library")]
        [string]$State
    )

    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 640, 360
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            if ($State -eq "field") {
                $graphics.Clear([System.Drawing.Color]::FromArgb(35, 100, 35))
            } elseif ($State -eq "launcher-library") {
                $graphics.Clear([System.Drawing.Color]::FromArgb(235, 235, 235))
                $coverBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(180, 20, 150))
                $accentBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(20, 190, 210))
                try {
                    $graphics.FillRectangle($coverBrush, 260, 130, 120, 110)
                    $graphics.FillRectangle($accentBrush, 500, 90, 45, 150)
                } finally {
                    $coverBrush.Dispose()
                    $accentBrush.Dispose()
                }
            } else {
                $graphics.Clear([System.Drawing.Color]::FromArgb(150, 100, 50))
            }

            if ($State -eq "load-complete") {
                $dialogBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, 45, 25))
                $stripePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(205, 160, 95)), 4
                try {
                    $graphics.FillRectangle($dialogBrush, 300, 160, 210, 70)
                    for ($x = 315; $x -le 495; $x += 18) {
                        $graphics.DrawLine($stripePen, $x, 175, $x, 215)
                    }
                } finally {
                    $dialogBrush.Dispose()
                    $stripePen.Dispose()
                }
            }
        } finally {
            $graphics.Dispose()
        }

        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bitmap.Dispose()
    }
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("thor-visual-gate-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    $listPath = Join-Path $scratch "load-list.png"
    $completePath = Join-Path $scratch "load-complete.png"
    $fieldPath = Join-Path $scratch "field.png"
    $launcherPath = Join-Path $scratch "launcher-library.png"
    New-ThorSyntheticRouteFrame -Path $listPath -State "load-list"
    New-ThorSyntheticRouteFrame -Path $completePath -State "load-complete"
    New-ThorSyntheticRouteFrame -Path $fieldPath -State "field"
    New-ThorSyntheticRouteFrame -Path $launcherPath -State "launcher-library"

    $list = Get-ThorBattleUiClassification -Path $listPath
    $complete = Get-ThorBattleUiClassification -Path $completePath
    $field = Get-ThorBattleUiClassification -Path $fieldPath
    $launcher = Get-ThorBattleUiClassification -Path $launcherPath

    Assert-ThorVisualEqual "synthetic load list" $list.load_menu_present $true
    Assert-ThorVisualEqual "synthetic load list is not complete" $list.load_complete_present $false
    Assert-ThorVisualEqual "synthetic load complete menu" $complete.load_menu_present $true
    Assert-ThorVisualEqual "synthetic load complete dialog" $complete.load_complete_present $true
    Assert-ThorVisualEqual "synthetic field" $field.field_frame_present $true
    Assert-ThorVisualEqual "synthetic field is not load complete" $field.load_complete_present $false
    Assert-ThorVisualEqual "synthetic launcher app shell" $launcher.launcher_ui_present $true
    Assert-ThorVisualEqual "synthetic launcher is not title" $launcher.title_menu_present $false
    Assert-ThorVisualEqual "synthetic launcher is not field" $launcher.field_frame_present $false
} finally {
    Get-ChildItem -LiteralPath $scratch -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue
}

if (-not [string]::IsNullOrWhiteSpace($CaptureRoot)) {
    $resolvedCaptureRoot = (Resolve-Path -LiteralPath $CaptureRoot).Path
    $labelledFrames = @(Get-ChildItem -LiteralPath $resolvedCaptureRoot -File | Where-Object Name -Match 'load-(save-list|complete).*\.png$')
    $validatedFrames = 0
    foreach ($frame in $labelledFrames) {
        $classification = Get-ThorBattleUiClassification -Path $frame.FullName
        if (-not $classification.load_menu_present) {
            continue
        }

        $expectedComplete = $frame.Name -match 'load-complete'
        Assert-ThorVisualEqual "captured $($frame.Name) load-complete state" $classification.load_complete_present $expectedComplete
        $validatedFrames++
    }

    if ($validatedFrames -lt 2) {
        throw "Capture root '$resolvedCaptureRoot' did not contain at least two valid Load-menu fixtures."
    }

    Write-Output "Validated $validatedFrames captured Eternal Sonata Load-menu fixtures."
}

$inputMacroSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "thor_input_macro.ps1") -Raw
foreach ($profileName in @(
    "eternal-sonata-load-field-route",
    "eternal-sonata-battle-intro-route",
    "eternal-sonata-field-direct",
    "eternal-sonata-field-route",
    "eternal-sonata-menu-route"
)) {
    $profilePattern = '"' + [regex]::Escape($profileName) + '"\s*\{[\s\S]*?return\s+"([^"]+)"'
    $profileMatch = [regex]::Match($inputMacroSource, $profilePattern)
    if (-not $profileMatch.Success) {
        throw "The Eternal Sonata profile '$profileName' could not be isolated."
    }

    $profileMacro = $profileMatch.Groups[1].Value
    foreach ($requiredGate in @(
        "gate:ppu-ready:150000",
        "gate:visual:load-menu:30000",
        "gate:visual:load-complete:50000",
        "gate:visual:field-frame:25000"
    )) {
        if (-not $profileMacro.Contains($requiredGate)) {
            throw "Profile '$profileName' is missing state gate '$requiredGate'."
        }
    }
    foreach ($obsoleteWait in @("wait:90000", "wait:100000")) {
        if ($profileMacro.Contains($obsoleteWait)) {
            throw "Profile '$profileName' still contains blind hot dwell '$obsoleteWait'."
        }
    }
}

$battleStart = $inputMacroSource.IndexOf('"eternal-sonata-battle-intro-route" {')
$battleEnd = $inputMacroSource.IndexOf('"eternal-sonata-field-direct" {', $battleStart)
if ($battleStart -lt 0 -or $battleEnd -le $battleStart) {
    throw "The Eternal Sonata battle route profile could not be isolated."
}
$battleProfile = $inputMacroSource.Substring($battleStart, $battleEnd - $battleStart)
foreach ($requiredGate in @(
    "gate:visual:load-menu:30000",
    "gate:visual:load-complete:50000",
    "gate:visual:field-frame:25000"
)) {
    if (-not $battleProfile.Contains($requiredGate)) {
        throw "Battle route is missing state gate '$requiredGate'."
    }
}
foreach ($obsoleteWait in @(
    "wait:20000;shot:load-save-list",
    "wait:35000;shot:load-complete",
    "wait:12000;shot:loaded-field"
)) {
    if ($battleProfile.Contains($obsoleteWait)) {
        throw "Battle route still contains obsolete fixed wait '$obsoleteWait'."
    }
}
if ($inputMacroSource -notmatch '\$visualStableCount\s+-ge\s+2') {
    throw "Visual-state gates do not require two consecutive matching frames."
}

$windowsLabSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1") -Raw
if ($windowsLabSource -notmatch '\$fatalScreenshotThreshold\s*=\s*3') {
    throw "The Windows field gate does not require three consecutive fatal-looking frames."
}
if ($windowsLabSource -notmatch '\$consecutiveFatalScreenshots\+\+[\s\S]*?waiting for confirmation') {
    throw "The Windows field gate does not debounce transient black load-transition frames."
}

if ($windowsLabSource -notmatch "return \`$tail -match '[^']*unknown draw command") {
    throw "The Windows live fatal gate does not fail closed on unknown guest draw commands."
}

$speedSprintSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1") -Raw
if ($speedSprintSource -notmatch '\[string\]\$AndroidSerial\s*=\s*""') {
    throw "The Android speed-sprint wrapper does not expose an explicit device serial."
}
if ($speedSprintSource -notmatch 'function\s+Resolve-SpeedAndroidSerial[\s\S]*?Multiple Android devices are online:[\s\S]*?Pass -AndroidSerial') {
    throw "The Android speed-sprint wrapper does not fail clearly on ambiguous ADB targets."
}
if ($speedSprintSource -notmatch '\$macroParams\.Serial\s*=\s*\$AndroidSerial') {
    throw "The Android speed-sprint wrapper does not explicitly forward the requested serial to the input route."
}
$targetInitIndex = $speedSprintSource.IndexOf('$AndroidSerial = Resolve-SpeedAndroidSerial -RequestedSerial $AndroidSerial')
$actionSwitchIndex = $speedSprintSource.LastIndexOf('switch ($Action)')
if ($targetInitIndex -lt 0 -or $actionSwitchIndex -le $targetInitIndex -or $speedSprintSource -notmatch '\$env:ANDROID_SERIAL\s*=\s*\$AndroidSerial') {
    throw "The Android speed-sprint wrapper does not pin nested ADB helpers before action dispatch."
}

Write-Output "Thor visual route gate tests passed."
