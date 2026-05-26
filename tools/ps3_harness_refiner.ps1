[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [int]$MaxRuns = 8,

    [string]$OutPath = "",

    [string]$JsonPath = "",

    [long]$MinFieldPngBytes = 1000000,

    [long]$MinBlackOverlayPngBytes = 20000,

    [long]$MaxBlackOverlayPngBytes = 60000,

    [long]$MinLoadingPngBytes = 90000,

    [long]$MaxLoadingPngBytes = 160000,

    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function ConvertTo-RepoRelativePath {
    param(
        [string]$Root,
        [string]$Path
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($rootFull.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
    }
    return $full
}

function Format-HarnessBytes {
    param([UInt64]$Bytes)

    if ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ([double]$Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ("{0:N2} MB" -f ([double]$Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ("{0:N2} KB" -f ([double]$Bytes / 1KB))
    }
    return ("{0} B" -f $Bytes)
}

function Get-ScreenshotSecond {
    param([string]$Name)

    if ($Name -match '^screenshot-(\d+)s(?:-|\.png$)') {
        return [int]$matches[1]
    }
    return [int]::MaxValue
}

function Get-HarnessScreenshotColorStats {
    param([string]$Path)

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    } catch {
        return $null
    }

    try {
        $count = 0
        [double]$red = 0
        [double]$green = 0
        [double]$blue = 0
        [int]$greenDominant = 0
        [int]$blueDominant = 0
        [int]$redDominant = 0
        [int]$dark = 0

        for ($y = 0; $y -lt $bitmap.Height; $y += 48) {
            for ($x = 0; $x -lt $bitmap.Width; $x += 48) {
                $pixel = $bitmap.GetPixel($x, $y)
                $count++
                $red += $pixel.R
                $green += $pixel.G
                $blue += $pixel.B

                if ($pixel.G -gt ($pixel.R + 15) -and $pixel.G -gt ($pixel.B + 15)) {
                    $greenDominant++
                }
                if ($pixel.B -gt ($pixel.R + 20) -and $pixel.B -gt ($pixel.G + 20)) {
                    $blueDominant++
                }
                if ($pixel.R -gt ($pixel.G + 20) -and $pixel.R -gt ($pixel.B + 20)) {
                    $redDominant++
                }
                if (($pixel.R + $pixel.G + $pixel.B) -lt 90) {
                    $dark++
                }
            }
        }

        if ($count -eq 0) {
            return $null
        }

        return [pscustomobject]@{
            AvgR = [math]::Round($red / $count, 1)
            AvgG = [math]::Round($green / $count, 1)
            AvgB = [math]::Round($blue / $count, 1)
            GreenRatio = [math]::Round($greenDominant / $count, 3)
            BlueRatio = [math]::Round($blueDominant / $count, 3)
            RedRatio = [math]::Round($redDominant / $count, 3)
            DarkRatio = [math]::Round($dark / $count, 3)
        }
    } finally {
        $bitmap.Dispose()
    }
}

function Test-HarnessBlueNonFieldScreenshot {
    param([AllowNull()][object]$ColorStats)

    if (-not $ColorStats) {
        return $false
    }

    return (
        $ColorStats.BlueRatio -ge 0.35 -and
        $ColorStats.GreenRatio -lt 0.20 -and
        $ColorStats.AvgB -ge ($ColorStats.AvgR + 20) -and
        $ColorStats.AvgB -ge ($ColorStats.AvgG + 15)
    )
}

function Test-HarnessCutsceneOrNonFieldClass {
    param([string]$Class)

    return $Class -in @("cutscene-or-nonfield-large-png", "cutscene-or-nonfield-small-png")
}

function Get-HarnessScreenshotClass {
    param(
        [long]$Bytes,
        [string]$Path = ""
    )

    $colorStats = if ([string]::IsNullOrWhiteSpace($Path)) { $null } else { Get-HarnessScreenshotColorStats -Path $Path }
    if (Test-HarnessBlueNonFieldScreenshot -ColorStats $colorStats) {
        if ($Bytes -ge $MinFieldPngBytes) {
            return "cutscene-or-nonfield-large-png"
        }
        return "cutscene-or-nonfield-small-png"
    }

    if ($Bytes -ge $MinFieldPngBytes) {
        if ($colorStats -and (
            $colorStats.RedRatio -ge 0.45 -or
            $colorStats.DarkRatio -ge 0.70 -or
            ($colorStats.GreenRatio -lt 0.15 -and $colorStats.DarkRatio -ge 0.35)
        )) {
            return "cutscene-or-nonfield-large-png"
        }
        return "field-like-large-png"
    }
    if ($Bytes -ge $MinBlackOverlayPngBytes -and $Bytes -le $MaxBlackOverlayPngBytes) {
        return "black-overlay-small-png"
    }
    if ($Bytes -ge $MinLoadingPngBytes -and $Bytes -le $MaxLoadingPngBytes) {
        return "loading-like-small-png"
    }
    return "wrong-window-or-other-small-png"
}

function Get-LoaderControlLeftPulseCount {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return -1
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if ($text -notlike "*loader-control*") {
        return -1
    }
    if ($text -match 'loader-control-left200x([0-9]+)') {
        return [int]$matches[1]
    }
    if ($text -match 'loader-control-left200') {
        return 1
    }
    return 0
}

function Get-LoaderControlLeftPulseLabel {
    param(
        [int]$Count,
        [switch]$Reconfirm
    )

    if ($Count -le 0) {
        return "cpu4-loader-control-visualgate-windows"
    }

    $suffix = if ($Reconfirm) { "reconfirm-visualgate-windows" } else { "visualgate-windows" }
    if ($Count -eq 1) {
        return "cpu4-loader-control-left200-$suffix"
    }
    return "cpu4-loader-control-left200x$Count-$suffix"
}

function New-LoaderControlLeftPulseCommand {
    param(
        [int]$Count,
        [switch]$Reconfirm
    )

    $tokens = @(
        "wait:45000",
        "down:20",
        "wait:500",
        "cross:80",
        "wait:12000",
        "up:80",
        "wait:160",
        "up:80",
        "wait:160",
        "up:80",
        "wait:160",
        "up:80",
        "wait:160",
        "up:80",
        "wait:500",
        "cross:80",
        "wait:3000",
        "up:80",
        "wait:500",
        "cross:80",
        "wait:32000",
        "cross:120",
        "wait:18000",
        "shot:100",
        "wait:15000",
        "shot:100"
    )

    for ($i = 0; $i -lt $Count; $i++) {
        $tokens += @("wait:1000", "ls_left:200", "wait:1000", "shot:100")
    }
    $tokens += @("wait:10000", "shot:100")

    $maxSeconds = if ($Count -le 0) { 190 } else { 195 + ($Count * 10) }
    $screenshotMax = if ($Count -le 0) { 8 } else { 9 + $Count }
    $label = Get-LoaderControlLeftPulseLabel -Count $Count -Reconfirm:$Reconfirm
    $macro = $tokens -join ";"

    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label $label -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"$macro`" -MaxSeconds $maxSeconds -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount $screenshotMax"
}

function New-Hle451cSize16CandidateReproofCommand {
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label hle-451c-size16-candidate-reproof-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -WindowsHostContentionGate ExternalFail -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8"
}

function New-Hle451cBodyOffBattleLeftOnlyDiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;ls_left:2600;wait:45000;shot:left-only-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-size16-body-off-battle-leftonly-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 185 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cBodyOffBattleNoPostFieldMoveDiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;wait:45000;shot:no-postfield-move-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-size16-body-off-battle-nopostmove-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 185 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleNoPostFieldMoveDiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:30000;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:field-check;wait:45000;shot:no-postfield-move-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-nopostmove-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 185 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeftOnlyDiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:2600;wait:45000;shot:left-only-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-leftonly-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft800DiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:800;wait:45000;shot:left800-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left800-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1200DiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1200;wait:45000;shot:left1200-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1200-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300LoadingCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1200;wait:45000;shot:left1200-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1200-reproof-after-left1300-loading -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200ReproofCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:15000;shot:accepted-field-stability-1;wait:15000;shot:accepted-field-stability-2;wait:30000;shot:accepted-field-stability-3"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 190 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1250StateGatedDiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;wait:10000;shot:accepted-field-pre-left1250;ls_left:1250;wait:45000;shot:left1250-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1250-state-gated-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1300DiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1300;wait:45000;shot:left1300-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1300-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1400DiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1400;wait:45000;shot:left1400-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1400-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-Hle451cPreserveBodyOffBattleTopslotLeft1600DiagnosticCommand {
    $macro = "wait:45000;ls_down:120;wait:800;cross:180;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:180;wait:1500;ls_up:120;wait:500;cross:180;wait:12000;start:180;wait:1500;cross:180;wait:35000;shot:accepted-field-check;ls_left:1600;wait:45000;shot:left1600-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-battle-topslot-left1600-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -InputMacro `"$macro`" -MaxSeconds 205 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function Read-FileLines {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    return [System.IO.File]::ReadAllLines($Path)
}

function Get-MarkdownBulletValue {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $pattern = "^- " + [regex]::Escape($Label) + ":\s*(.+)$"
    foreach ($line in $Lines) {
        if ($line -match $pattern) {
            return $matches[1].Trim().TrimEnd(".").Trim('`')
        }
    }
    return ""
}

function Get-LabSetting {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    return Get-MarkdownBulletValue -Lines $Lines -Label $Label
}

function Get-PrimarySmallClass {
    param([object[]]$Rows)

    $smallRows = @($Rows | Where-Object { $_.Class -ne "field-like-large-png" })
    if ($smallRows.Count -eq 0) {
        return ""
    }

    $primary = $smallRows | Group-Object Class | Sort-Object -Property @{ Expression = "Count"; Descending = $true }, Name | Select-Object -First 1
    return $primary.Name
}

function Read-VisualEvidence {
    param([System.IO.DirectoryInfo]$Run)

    $summaryPath = Join-Path $Run.FullName "eternal-sonata-windows-visual-gate-summary.md"
    $summaryLines = Read-FileLines -Path $summaryPath
    $screenshotDir = Join-Path $Run.FullName "screenshots"
    if (-not (Test-Path -LiteralPath $screenshotDir -PathType Container)) {
        $screenshotDir = $Run.FullName
    }

    $shots = @(Get-ChildItem -LiteralPath $screenshotDir -Filter "*.png" -File -ErrorAction SilentlyContinue |
        Sort-Object @{ Expression = { Get-ScreenshotSecond $_.Name } }, Name)

    $rows = foreach ($shot in $shots) {
        $second = Get-ScreenshotSecond $shot.Name
        [pscustomobject]@{
            Screenshot = $shot.Name
            Seconds = if ($second -eq [int]::MaxValue) { $null } else { $second }
            Bytes = [UInt64]$shot.Length
            HumanBytes = Format-HarnessBytes -Bytes ([UInt64]$shot.Length)
            Class = Get-HarnessScreenshotClass -Bytes $shot.Length -Path $shot.FullName
        }
    }

    $fieldRows = @($rows | Where-Object { $_.Class -eq "field-like-large-png" })
    $firstField = $fieldRows | Sort-Object Seconds, Screenshot | Select-Object -First 1
    $invalidAfterFirstField = @()
    if ($firstField) {
        $invalidAfterFirstField = @($rows | Where-Object { $_.Class -ne "field-like-large-png" -and ($null -eq $_.Seconds -or $_.Seconds -ge $firstField.Seconds) })
    }

    $status = Get-MarkdownBulletValue -Lines $summaryLines -Label "Status"
    if ([string]::IsNullOrWhiteSpace($status)) {
        if ($fieldRows.Count -eq 0 -and $rows.Count -gt 0) {
            $status = "NO_FIELD_LIKE_SCREENSHOT"
        } elseif ($invalidAfterFirstField.Count -gt 0) {
            $status = "FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS"
        } elseif ($fieldRows.Count -gt 0) {
            $status = "FIELD_LIKE_PRESENT"
        } else {
            $status = "NO_SCREENSHOTS"
        }
    }

    $gateResult = Get-MarkdownBulletValue -Lines $summaryLines -Label "Gate result"
    if ([string]::IsNullOrWhiteSpace($gateResult)) {
        $gateResult = if ($status -eq "FIELD_LIKE_PRESENT") { "unknown-passish" } else { "unknown" }
    }

    $classCounts = @{}
    foreach ($group in ($rows | Group-Object Class)) {
        $classCounts[$group.Name] = $group.Count
    }

    $primarySmallClass = Get-PrimarySmallClass -Rows $rows
    $firstInvalid = $rows | Where-Object { $_.Class -ne "field-like-large-png" } | Sort-Object Seconds, Screenshot | Select-Object -First 1

    return [pscustomobject]@{
        SummaryPath = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { $summaryPath } else { "" }
        ScreenshotCount = $shots.Count
        Status = $status
        GateResult = $gateResult
        FirstFieldScreenshot = if ($firstField) { $firstField.Screenshot } else { "" }
        FirstFieldSeconds = if ($firstField) { $firstField.Seconds } else { $null }
        FirstFieldBytes = if ($firstField) { $firstField.Bytes } else { [UInt64]0 }
        InvalidAfterFirstField = $invalidAfterFirstField.Count
        PrimarySmallClass = $primarySmallClass
        FirstInvalidScreenshot = if ($firstInvalid) { $firstInvalid.Screenshot } else { "" }
        FirstInvalidSeconds = if ($firstInvalid) { $firstInvalid.Seconds } else { $null }
        FirstInvalidBytes = if ($firstInvalid) { $firstInvalid.Bytes } else { [UInt64]0 }
        ClassCounts = $classCounts
    }
}

function Read-GpuSummary {
    param([System.IO.DirectoryInfo]$Run)

    $summaryPath = Join-Path $Run.FullName "eternal-sonata-gpu-probe-summary.md"
    $lines = Read-FileLines -Path $summaryPath
    $hotPcs = New-Object System.Collections.Generic.List[string]
    $inHotPc = $false

    foreach ($line in $lines) {
        if ($line -eq "## Hot PC Summary") {
            $inHotPc = $true
            continue
        }
        if ($inHotPc -and $line.StartsWith("## ")) {
            $inHotPc = $false
        }
        if ($inHotPc -and $line -match '^\| `0x[0-9a-f]+` \|') {
            $cols = $line.Trim("|").Split("|") | ForEach-Object { $_.Trim() }
            if ($cols.Count -ge 4) {
                $hotPcs.Add(("{0} records={1} sum={2}" -f $cols[0].Trim('`'), $cols[1], $cols[2]))
            }
        }
    }

    return [pscustomobject]@{
        SummaryPath = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { $summaryPath } else { "" }
        Records = Get-MarkdownBulletValue -Lines $lines -Label "Records"
        TotalObservedDmaBytes = Get-MarkdownBulletValue -Lines $lines -Label "Total observed DMA bytes"
        RsxLocalTrafficRecords = Get-MarkdownBulletValue -Lines $lines -Label "RSX-local traffic records"
        IndirectRsxOverlapRecords = Get-MarkdownBulletValue -Lines $lines -Label "Indirect RSX resource overlap records"
        OffloadFitMix = Get-MarkdownBulletValue -Lines $lines -Label "Offload fit mix"
        HotPcs = @($hotPcs | Select-Object -First 3)
    }
}

function Read-LaneEvidence {
    param([System.IO.DirectoryInfo]$Run)

    $csvPath = Join-Path $Run.FullName "eternal-sonata-reservation-loop-lane-join-profile.csv"
    if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        return [pscustomobject]@{
            CsvPath = ""
            Lane2 = $null
        }
    }

    $rows = @(Import-Csv -LiteralPath $csvPath)
    $lane2 = $rows | Where-Object { $_.lane -eq "2" } | Sort-Object @{ Expression = { [int64]$_.verify_success } } -Descending | Select-Object -First 1
    if (-not $lane2) {
        return [pscustomobject]@{
            CsvPath = $csvPath
            Lane2 = $null
        }
    }

    return [pscustomobject]@{
        CsvPath = $csvPath
        Lane2 = [pscustomobject]@{
            Attempts = $lane2.verify_attempts
            Completed = $lane2.verify_completed
            Success = $lane2.verify_success
            Failure = $lane2.verify_failure
            Unexpected = $lane2.verify_unexpected
            RetryBranches = $lane2.verify_retry_branches
            RetryTaken = $lane2.verify_retry_taken
            RetryFallthrough = $lane2.verify_retry_fallthrough
            NextBranches = $lane2.verify_next_branches
            NextTaken = $lane2.verify_next_taken
            NextFallthrough = $lane2.verify_next_fallthrough
            RetryPc = $lane2.retry_pc
            NextPc = $lane2.next_branch_pc
        }
    }
}

function Read-LabEvidence {
    param([System.IO.DirectoryInfo]$Run)

    $labPath = Join-Path $Run.FullName "windows-rpcs3-lab.txt"
    $lines = Read-FileLines -Path $labPath
    $hostChecks = @($lines | Where-Object { $_ -match '^- Host check \[[^\]]+\]: ' })
    $hostBad = @($hostChecks | Where-Object { $_ -notmatch ': clean;' })
    $windowNotFoundScreenshots = @($lines | Where-Object { $_ -match '^Screenshot skipped at \d+s: game window was not found' })
    $processExitedWindowLoss = @($windowNotFoundScreenshots | Where-Object { $_ -match 'process has exited' })
    $earlyProcessExitLines = @($lines | Where-Object { $_ -match '^Process exited at \d+s before max \d+s\.' })

    return [pscustomobject]@{
        LabPath = if (Test-Path -LiteralPath $labPath -PathType Leaf) { $labPath } else { "" }
        Label = Get-LabSetting -Lines $lines -Label "Label"
        GameScreen = Get-LabSetting -Lines $lines -Label "Game screen"
        InputBackend = Get-LabSetting -Lines $lines -Label "Input backend"
        ReservationLoop = Get-LabSetting -Lines $lines -Label "Eternal Sonata reservation loop"
        CpuAffinity = Get-LabSetting -Lines $lines -Label "CPU affinity mask requested"
        FrameLimit = Get-LabSetting -Lines $lines -Label "Frame limit override"
        VblankRate = Get-LabSetting -Lines $lines -Label "Vblank rate override"
        HostChecks = $hostChecks.Count
        HostBadChecks = $hostBad.Count
        WindowNotFoundScreenshots = $windowNotFoundScreenshots.Count
        ProcessExitedWindowLoss = $processExitedWindowLoss.Count
        EarlyProcessExitLines = $earlyProcessExitLines.Count
    }
}

function Read-FatalEvidence {
    param([System.IO.DirectoryInfo]$Run)

    $fatalPattern = "Unknown STOP code|Thread terminated due to fatal error|likely crashed|Access violation|VM: Access|SIGSEGV|SIGBUS|VK_ERROR|Validation Error|verification failure|assertion|Unhandled exception"
    $paths = @(
        (Join-Path $Run.FullName "rpcs3.stderr.txt"),
        (Join-Path $Run.FullName "rpcs3.stdout.txt"),
        (Join-Path $Run.FullName "RPCS3.log")
    )

    $existingPaths = @($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($existingPaths.Count -eq 0) {
        return [pscustomobject]@{
            HasFatal = $false
            MatchCount = 0
            FirstMatch = ""
        }
    }

    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if ($rg) {
        $rgOutput = @(& $rg.Source --line-number --no-heading -m 1 --regexp $fatalPattern -- $existingPaths 2>$null)
        $first = $rgOutput | Select-Object -First 1
        if ($first) {
            if ($first.Length -gt 220) {
                $first = $first.Substring(0, 220) + "..."
            }
            return [pscustomobject]@{
                HasFatal = $true
                MatchCount = $rgOutput.Count
                FirstMatch = $first
            }
        }
        return [pscustomobject]@{
            HasFatal = $false
            MatchCount = 0
            FirstMatch = ""
        }
    }

    $matchCount = 0
    $firstMatch = ""
    foreach ($path in $existingPaths) {
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            $lineNumber++
            if ($line -match $fatalPattern) {
                $matchCount = 1
                $leaf = Split-Path -Leaf $path
                $text = $line.Trim()
                if ($text.Length -gt 180) {
                    $text = $text.Substring(0, 180) + "..."
                }
                $firstMatch = "{0}:{1}: {2}" -f $leaf, $lineNumber, $text
                break
            }
        }
        if ($matchCount -gt 0) {
            break
        }
    }

    return [pscustomobject]@{
        HasFatal = $matchCount -gt 0
        MatchCount = $matchCount
        FirstMatch = $firstMatch
    }
}

function Get-RunDecision {
    param([object]$RunEvidence)

    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return "failed-fatal-log"
    }

    $visual = $RunEvidence.Visual
    if ($visual.ScreenshotCount -eq 0) {
        return "not-comparable-no-screenshots"
    }
    if (Test-Hle451cSize16BodyOptionsProof -RunEvidence $RunEvidence) {
        return "valid-options-triage"
    }
    if (Test-Hle451cPreserveBodyOptionsProof -RunEvidence $RunEvidence) {
        return "valid-options-triage"
    }
    if (Test-Hle25ccBodyBattleOptionsRouteMiss -RunEvidence $RunEvidence) {
        return "route-miss-options-not-battle"
    }
    if (Test-Hle25ccBodyOptionsProof -RunEvidence $RunEvidence) {
        return "valid-options-triage"
    }
    if ($RunEvidence.Lab -and $RunEvidence.Lab.WindowNotFoundScreenshots -gt 0) {
        return "failed-window-lost-after-field"
    }
    if ($visual.GateResult -eq "failed") {
        return "failed-visual-gate"
    }
    if ($visual.Status -eq "FIELD_LIKE_PRESENT" -and $visual.InvalidAfterFirstField -eq 0) {
        return "valid-field-triage"
    }
    if ($visual.PrimarySmallClass -eq "black-overlay-small-png") {
        return "failed-black-overlay-visual"
    }
    if ($visual.PrimarySmallClass -eq "loading-like-small-png") {
        return "failed-loading-visual"
    }
    if (Test-HarnessCutsceneOrNonFieldClass -Class $visual.PrimarySmallClass) {
        return "failed-cutscene-or-nonfield-visual"
    }
    if ($visual.PrimarySmallClass -eq "wrong-window-or-other-small-png") {
        return "failed-wrong-window-or-other-visual"
    }
    return "failed-visual-gate"
}

function Test-Hle451cSize16BodyOptionsProof {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return $false
    }
    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if (($text -notlike "*451c-size16-body*" -and $text -notlike "*size16-body*") -or
        $text -like "*size16-body-off*" -or
        ($text -notlike "*options*" -and $text -notlike "*menu*")) {
        return $false
    }

    if (-not $RunEvidence.Visual -or $RunEvidence.Visual.ScreenshotCount -eq 0) {
        return $false
    }
    if ($RunEvidence.Visual.Status -ne "NO_FIELD_LIKE_SCREENSHOT") {
        return $false
    }

    $counts = $RunEvidence.Visual.ClassCounts
    $black = if ($counts.ContainsKey("black-overlay-small-png")) { [int]$counts["black-overlay-small-png"] } else { 0 }
    $loading = if ($counts.ContainsKey("loading-like-small-png")) { [int]$counts["loading-like-small-png"] } else { 0 }
    $otherSmall = if ($counts.ContainsKey("wrong-window-or-other-small-png")) { [int]$counts["wrong-window-or-other-small-png"] } else { 0 }
    $nonFieldSmall = if ($counts.ContainsKey("cutscene-or-nonfield-small-png")) { [int]$counts["cutscene-or-nonfield-small-png"] } else { 0 }

    # The title background can trip the field-only cutscene heuristic. The full
    # Options page itself compresses below the field PNG threshold in this
    # capture path, so repeated small menu screenshots are expected here.
    return ($black -eq 0 -and $loading -eq 0 -and ($otherSmall + $nonFieldSmall) -ge 2)
}

function Test-Hle451cPreserveBodyOptionsProof {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return $false
    }
    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if (($text -notlike "*451c-preserve-body*" -and $text -notlike "*preserve-body*") -or
        ($text -notlike "*options*" -and $text -notlike "*menu*")) {
        return $false
    }

    if (-not $RunEvidence.Visual -or $RunEvidence.Visual.ScreenshotCount -eq 0) {
        return $false
    }
    if ($RunEvidence.Visual.Status -ne "NO_FIELD_LIKE_SCREENSHOT") {
        return $false
    }

    $counts = $RunEvidence.Visual.ClassCounts
    $black = if ($counts.ContainsKey("black-overlay-small-png")) { [int]$counts["black-overlay-small-png"] } else { 0 }
    $loading = if ($counts.ContainsKey("loading-like-small-png")) { [int]$counts["loading-like-small-png"] } else { 0 }
    $otherSmall = if ($counts.ContainsKey("wrong-window-or-other-small-png")) { [int]$counts["wrong-window-or-other-small-png"] } else { 0 }
    $nonFieldSmall = if ($counts.ContainsKey("cutscene-or-nonfield-small-png")) { [int]$counts["cutscene-or-nonfield-small-png"] } else { 0 }

    # Options/menu screenshots are valid for this route even though the field-only
    # classifier records them as small non-field PNGs.
    return ($black -eq 0 -and $loading -eq 0 -and ($otherSmall + $nonFieldSmall) -ge 2)
}

function Test-Hle25ccBodyOptionsProof {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return $false
    }
    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if (($text -notlike "*25cc-body*" -and $text -notlike "*hle-25cc-body*") -or
        ($text -notlike "*options*" -and $text -notlike "*menu*") -or
        $text -like "*battle*") {
        return $false
    }

    if (-not $RunEvidence.Visual -or $RunEvidence.Visual.ScreenshotCount -eq 0) {
        return $false
    }
    if ($RunEvidence.Visual.Status -ne "NO_FIELD_LIKE_SCREENSHOT") {
        return $false
    }

    $counts = $RunEvidence.Visual.ClassCounts
    $black = if ($counts.ContainsKey("black-overlay-small-png")) { [int]$counts["black-overlay-small-png"] } else { 0 }
    $loading = if ($counts.ContainsKey("loading-like-small-png")) { [int]$counts["loading-like-small-png"] } else { 0 }
    $otherSmall = if ($counts.ContainsKey("wrong-window-or-other-small-png")) { [int]$counts["wrong-window-or-other-small-png"] } else { 0 }
    $nonFieldSmall = if ($counts.ContainsKey("cutscene-or-nonfield-small-png")) { [int]$counts["cutscene-or-nonfield-small-png"] } else { 0 }

    # The title Options page is expected to classify as small non-field output
    # under the field-only byte-size visual gate.
    return ($black -eq 0 -and $loading -eq 0 -and ($otherSmall + $nonFieldSmall) -ge 2)
}

function Test-Hle25ccBodyBattleOptionsRouteMiss {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return $false
    }
    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if (($text -notlike "*25cc-body*" -and $text -notlike "*hle-25cc-body*") -or
        $text -notlike "*battle*") {
        return $false
    }

    if (-not $RunEvidence.Visual -or $RunEvidence.Visual.ScreenshotCount -eq 0) {
        return $false
    }
    if ($RunEvidence.Visual.Status -ne "NO_FIELD_LIKE_SCREENSHOT") {
        return $false
    }

    $counts = $RunEvidence.Visual.ClassCounts
    $black = if ($counts.ContainsKey("black-overlay-small-png")) { [int]$counts["black-overlay-small-png"] } else { 0 }
    $loading = if ($counts.ContainsKey("loading-like-small-png")) { [int]$counts["loading-like-small-png"] } else { 0 }
    $otherSmall = if ($counts.ContainsKey("wrong-window-or-other-small-png")) { [int]$counts["wrong-window-or-other-small-png"] } else { 0 }
    $nonFieldSmall = if ($counts.ContainsKey("cutscene-or-nonfield-small-png")) { [int]$counts["cutscene-or-nonfield-small-png"] } else { 0 }

    return ($black -eq 0 -and $loading -eq 0 -and ($otherSmall + $nonFieldSmall) -ge 2)
}

function Add-AntiPattern {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$Name,
        [string]$Severity,
        [string]$Evidence,
        [string]$Action
    )

    $List.Add([pscustomobject]@{
        Name = $Name
        Severity = $Severity
        Evidence = $Evidence
        Action = $Action
    })
}

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot

if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_ps3-harness-refiner-latest.md"
}
if ([string]::IsNullOrWhiteSpace($JsonPath)) {
    $JsonPath = Join-Path $RunRoot "_ps3-harness-refiner-latest.json"
}

if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    throw "Run root not found: $RunRoot"
}

$runs = @(Get-ChildItem -LiteralPath $RunRoot -Directory |
    Where-Object { $_.Name -notlike "_*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $MaxRuns)

if ($runs.Count -eq 0) {
    throw "No run directories found under $RunRoot"
}

$runEvidence = foreach ($run in $runs) {
    $item = [pscustomobject]@{
        Name = $run.Name
        Path = $run.FullName
        LastWriteTime = $run.LastWriteTime
        Visual = Read-VisualEvidence -Run $run
        Gpu = Read-GpuSummary -Run $run
        Lane = Read-LaneEvidence -Run $run
        Lab = Read-LabEvidence -Run $run
        Fatal = Read-FatalEvidence -Run $run
        Decision = ""
    }
    $item.Decision = Get-RunDecision -RunEvidence $item
    $item
}

$antiPatterns = New-Object System.Collections.Generic.List[object]
$blackRuns = @($runEvidence | Where-Object { $_.Visual.PrimarySmallClass -eq "black-overlay-small-png" -and $_.Visual.Status -ne "FIELD_LIKE_PRESENT" })
$loadingRuns = @($runEvidence | Where-Object { $_.Visual.PrimarySmallClass -eq "loading-like-small-png" -and $_.Visual.Status -ne "FIELD_LIKE_PRESENT" })
$cutsceneRuns = @($runEvidence | Where-Object { (Test-HarnessCutsceneOrNonFieldClass -Class $_.Visual.PrimarySmallClass) -and $_.Visual.Status -ne "FIELD_LIKE_PRESENT" })
$optionsProofRuns = @($runEvidence | Where-Object {
    (Test-Hle451cSize16BodyOptionsProof -RunEvidence $_) -or
    (Test-Hle451cPreserveBodyOptionsProof -RunEvidence $_) -or
    (Test-Hle25ccBodyOptionsProof -RunEvidence $_)
})
$wrongWindowRuns = @($runEvidence | Where-Object {
    $_.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
    -not ((Test-Hle451cSize16BodyOptionsProof -RunEvidence $_) -or
        (Test-Hle451cPreserveBodyOptionsProof -RunEvidence $_) -or
        (Test-Hle25ccBodyOptionsProof -RunEvidence $_) -or
        (Test-Hle25ccBodyBattleOptionsRouteMiss -RunEvidence $_))
})
$fatalRuns = @($runEvidence | Where-Object { $_.Fatal -and $_.Fatal.HasFatal })
$validFieldRuns = @($runEvidence | Where-Object { $_.Decision -eq "valid-field-triage" })
$rsxZeroRuns = @($runEvidence | Where-Object { $_.Gpu.RsxLocalTrafficRecords -eq "0" -or $_.Gpu.RsxLocalTrafficRecords -eq "0 raw, 0 aggregated" })
$recentHle451cPreserveBodyOffBattleTopslotLeft1600Fatal = @($runEvidence | Where-Object {
    $label = if ($_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    ($_.Fatal -and $_.Fatal.HasFatal) -and
    ($text -like "*451c-preserve-body-off*" -or $text -like "*preserve-body-off*") -and
    $text -like "*battle*" -and
    $text -like "*topslot*" -and
    $text -like "*left1600*"
}).Count -ge 1
$recentDiag200Rejected = @($cutsceneRuns | Where-Object {
    $label = if ($_.Lab.Label) { $_.Lab.Label } else { "" }
    $_.Name -like "*loader-control-left200x2-diag200*" -or $label -like "*loader-control-left200x2-diag200*"
}).Count -ge 1
$latestRun = $runEvidence | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestValidLoaderControl = $false
$latestValidLoaderControlLeft200 = $false
$latestValidLoaderControlLeft200x2 = $false
$latestValidLoaderControlLeft200x3 = $false
$latestValidLoaderControlLeft200x4 = $false
$latestValidLoaderControlLeftCount = -1
$latestCutsceneOrNonfield = $false
$latestBlackOverlay = $false
$latestFatal = $false
$latestLoaderControlReconfirm = $false
$latestCleanHleDescriptorBatch = $false
$latestHle451cSize16Candidate = $false
$latestBlackHle451cSize16Candidate = $false
$latestCleanHle451cSize16BodyOff = $false
$latestCleanHle451cSize16BodyOn = $false
$latestCleanHle451cSize16BodyOptions = $false
$latestHle451cSize16BodyBattleBlack = $false
$latestHle451cSize16BodyMenuRouteMiss = $false
$latestHle451cSize16BodyOffBattleRouteLost = $false
$latestHle451cSize16BodyOffBattleProcessExit = $false
$latestHle451cSize16BodyOffBattleLeftOnlyProcessExit = $false
$latestCleanHle451cPreserveBodyField = $false
$latestCleanHle451cPreserveBodyOptions = $false
$latestHle451cPreserveBodyBattleFatal = $false
$latestHle451cPreserveBodyOffBattleRouteLost = $false
$latestHle451cPreserveBodyOffBattleProcessExit = $false
$latestHle451cPreserveBodyBattleRouteMiss = $false
$latestHle451cPreserveBodyOffBattleTopslotFieldClean = $false
$latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft800FieldClean = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading = $false
$latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1250StateGatedBlack = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1300Loading = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit = $false
$latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal = $false
$latestCleanHle25ccBodyOptions = $false
$latestHle25ccBodyBattleOptionsRouteMiss = $false
$latestHle25ccNoPauseBattleAbComplete = $false
$latestHle25ccBodyFastCpuStackComponent = $false
$latestHle25ccBodyFastCpuCandidate = $false
$latestHle25ccBodyFastCpuEvidence = ""
if ($latestRun) {
    $latestLabel = if ($latestRun.Lab.Label) { $latestRun.Lab.Label } else { "" }
    $latestText = "$($latestRun.Name) $latestLabel"
    $latestFatal = $latestRun.Fatal -and $latestRun.Fatal.HasFatal
    $latestCutsceneOrNonfield = (Test-HarnessCutsceneOrNonFieldClass -Class $latestRun.Visual.PrimarySmallClass) -and $latestRun.Decision -ne "valid-field-triage"
    $latestBlackOverlay = $latestRun.Visual.PrimarySmallClass -eq "black-overlay-small-png" -and $latestRun.Decision -ne "valid-field-triage"
    $latestHle451cSize16Candidate =
        $latestText -like "*451c-size16*" -or
        $latestText -like "*size16-candidate*" -or
        ($latestText -like "*451c*" -and $latestText -like "*size16*")
    $latestBlackHle451cSize16Candidate = $latestBlackOverlay -and $latestHle451cSize16Candidate
    $latestHle451cSize16BodyOnText =
        ($latestText -like "*451c-size16-body*" -or $latestText -like "*size16-body*") -and
        $latestText -notlike "*size16-body-off*"
    $latestHle451cSize16BodyBattleBlack =
        $latestBlackOverlay -and
        $latestHle451cSize16BodyOnText -and
        $latestText -like "*battle*"
    if ($latestHle451cSize16BodyBattleBlack) {
        $latestBlackHle451cSize16Candidate = $false
    }
    $latestCleanHle451cSize16BodyOff =
        $latestRun.Decision -eq "valid-field-triage" -and
        ($latestText -like "*451c-size16-body-off*" -or $latestText -like "*size16-body-off*")
    $latestHle451cSize16BodyOffBattleRouteLost =
        $latestRun.Decision -eq "failed-window-lost-after-field" -and
        ($latestText -like "*451c-size16-body-off*" -or $latestText -like "*size16-body-off*") -and
        $latestText -like "*battle*"
    $latestHle451cSize16BodyOffBattleProcessExit =
        $latestHle451cSize16BodyOffBattleRouteLost -and
        $latestRun.Lab -and
        $latestRun.Lab.ProcessExitedWindowLoss -gt 0
    $latestHle451cSize16BodyOffBattleLeftOnlyProcessExit =
        $latestHle451cSize16BodyOffBattleProcessExit -and
        $latestText -like "*leftonly-diagnostic*"
    $latestCleanHle451cSize16BodyOn =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestHle451cSize16BodyOnText
    $latestCleanHle451cSize16BodyOptions =
        $latestRun.Decision -eq "valid-options-triage" -and
        $latestHle451cSize16BodyOnText
    $latestHle451cSize16BodyMenuRouteMiss =
        $latestCutsceneOrNonfield -and
        ($latestText -like "*451c-size16-body*" -or $latestText -like "*size16-body*") -and
        ($latestText -like "*options*" -or $latestText -like "*menu*")
    $latestHle451cPreserveBodyOnText =
        ($latestText -like "*451c-preserve-body*" -or $latestText -like "*preserve-body*") -and
        $latestText -notlike "*preserve-body-off*"
    $latestCleanHle451cPreserveBodyField =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestHle451cPreserveBodyOnText
    $latestCleanHle451cPreserveBodyOptions =
        $latestRun.Decision -eq "valid-options-triage" -and
        $latestHle451cPreserveBodyOnText
    $latestHle451cPreserveBodyBattleFatal =
        $latestFatal -and
        $latestHle451cPreserveBodyOnText -and
        $latestText -like "*battle*"
    $latestHle451cPreserveBodyOffBattleRouteLost =
        $latestRun.Decision -eq "failed-window-lost-after-field" -and
        ($latestText -like "*451c-preserve-body-off*" -or $latestText -like "*preserve-body-off*") -and
        $latestText -like "*battle*"
    $latestHle451cPreserveBodyOffBattleProcessExit =
        $latestHle451cPreserveBodyOffBattleRouteLost -and
        $latestRun.Lab -and
        $latestRun.Lab.ProcessExitedWindowLoss -gt 0
    $latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit =
        $latestHle451cPreserveBodyOffBattleProcessExit -and
        ($latestText -like "*topslot-leftonly*" -or
        ($latestText -like "*topslot*" -and $latestText -like "*leftonly*"))
    $latestHle451cPreserveBodyBattleRouteMiss =
        $latestRun.Decision -eq "failed-wrong-window-or-other-visual" -and
        ($latestText -like "*451c-preserve-body*" -or $latestText -like "*preserve-body*") -and
        $latestText -like "*battle*"
    $latestHle451cPreserveBodyOffBattleTopslotFieldClean =
        $latestRun.Decision -eq "valid-field-triage" -and
        ($latestText -like "*451c-preserve-body-off*" -or $latestText -like "*preserve-body-off*") -and
        $latestText -like "*battle*" -and
        ($latestText -like "*topslot*" -or $latestText -like "*accepted-field*")
    $latestHle451cPreserveBodyOffBattleTopslotLeft800FieldClean =
        $latestHle451cPreserveBodyOffBattleTopslotFieldClean -and
        ($latestText -like "*topslot-left800*" -or
        ($latestText -like "*topslot*" -and $latestText -like "*left800*"))
    $latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean =
        $latestHle451cPreserveBodyOffBattleTopslotFieldClean -and
        $latestText -notlike "*route-state-gate-after-left1200-reproof*" -and
        ($latestText -like "*topslot-left1200*" -or
        ($latestText -like "*topslot*" -and $latestText -like "*left1200*"))
    $latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading =
        $latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean -and
        $latestText -like "*reproof-after-left1300-loading*"
    $latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof =
        $latestHle451cPreserveBodyOffBattleTopslotFieldClean -and
        $latestText -like "*route-state-gate-after-left1200-reproof*"
    $latestHle451cPreserveBodyOffBattleTopslotLeft1250StateGatedBlack =
        $latestBlackOverlay -and
        ($latestText -like "*451c-preserve-body-off*" -or $latestText -like "*preserve-body-off*") -and
        $latestText -like "*battle*" -and
        $latestText -like "*topslot*" -and
        $latestText -like "*left1250*" -and
        $latestText -like "*state-gated*"
    $latestHle451cPreserveBodyOffBattleTopslotLeft1300Loading =
        $latestRun.Decision -eq "failed-loading-visual" -and
        ($latestText -like "*451c-preserve-body-off*" -or $latestText -like "*preserve-body-off*") -and
        $latestText -like "*battle*" -and
        $latestText -like "*topslot*" -and
        $latestText -like "*left1300*"
    $latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit =
        $latestHle451cPreserveBodyOffBattleProcessExit -and
        ($latestText -like "*topslot-left1400*" -or
        ($latestText -like "*topslot*" -and $latestText -like "*left1400*"))
    $latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal =
        $latestFatal -and
        ($latestText -like "*451c-preserve-body-off*" -or $latestText -like "*preserve-body-off*") -and
        $latestText -like "*battle*" -and
        $latestText -like "*topslot*" -and
        $latestText -like "*left1600*"
    $latestCleanHle25ccBodyOptions =
        $latestRun.Decision -eq "valid-options-triage" -and
        (($latestText -like "*25cc-body*" -or $latestText -like "*hle-25cc-body*") -and
        ($latestText -like "*options*" -or $latestText -like "*menu*"))
    $latestHle25ccBodyBattleOptionsRouteMiss =
        $latestRun.Decision -eq "route-miss-options-not-battle"
    $latestHle25ccNoPauseBattleAbComplete =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*battle*" -and
        $latestText -like "*topslot*" -and
        $latestText -like "*nopause*" -and
        $latestText -like "*battleroute*" -and
        $latestText -like "*ab*"
    $latestHle25ccBodyFastSummaryPaths = @(
        (Join-Path $RunRoot "_eternal-sonata-25cc-bodyfast-repeat-battle-ab-latest.md"),
        (Join-Path $RunRoot "_eternal-sonata-25cc-bodyfast-battle-ab-latest.md")
    )
    $latestHle25ccBodyFastSummaryPath = $latestHle25ccBodyFastSummaryPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($latestText -like "*bodyfast*" -and $latestHle25ccBodyFastSummaryPath) {
        $bodyFastSummary = Get-Content -LiteralPath $latestHle25ccBodyFastSummaryPath -Raw
        $latestHle25ccBodyFastCpuStackComponent =
            $bodyFastSummary -like "*windows-cpu-load-micro-win-candidate*" -or
            $bodyFastSummary -like "*CPU-pressure stack component*"
        $latestHle25ccBodyFastCpuCandidate =
            $latestHle25ccBodyFastCpuStackComponent -or
            $bodyFastSummary -like "*directional RPCS3 CPU-load reduction*" -or
            $bodyFastSummary -like "*directional CPU-load reduction*"
        if ($bodyFastSummary -match 'RPCS3 process CPU avg \| (?<stock>[0-9.]+)% \| (?<body>[0-9.]+)% \| (?<delta>-[0-9.]+ pp / -[0-9.]+%)') {
            $latestHle25ccBodyFastCpuEvidence = "RPCS3 process CPU avg stock $($matches['stock'])%, bodyfast $($matches['body'])%, delta $($matches['delta'])"
        } elseif ($latestHle25ccBodyFastCpuCandidate) {
            $latestHle25ccBodyFastCpuEvidence = "capped-FPS host samples show directional RPCS3 CPU-load reduction"
        }
    }
    $latestLoaderControlReconfirm = $latestRun.Name -like "*loader-control*reconfirm*" -or $latestLabel -like "*loader-control*reconfirm*"
    $latestCleanHleDescriptorBatch =
        $latestRun.Decision -eq "valid-field-triage" -and
        ($latestHle451cSize16Candidate -or
        $latestText -like "*descbatch*" -or
        $latestText -like "*descriptor-batch*" -or
        $latestText -like "*451c-desc*")
    $latestValidLoaderControl =
        $latestRun.Decision -eq "valid-field-triage" -and
        ($latestRun.Name -like "*loader-control*" -or $latestLabel -like "*loader-control*")
    if ($latestValidLoaderControl) {
        $latestValidLoaderControlLeftCount = Get-LoaderControlLeftPulseCount -RunEvidence $latestRun
    }
    $latestValidLoaderControlLeft200x4 =
        $latestValidLoaderControl -and
        ($latestRun.Name -like "*loader-control-left200x4*" -or $latestLabel -like "*loader-control-left200x4*")
    $latestValidLoaderControlLeft200x3 =
        $latestValidLoaderControl -and
        !$latestValidLoaderControlLeft200x4 -and
        ($latestRun.Name -like "*loader-control-left200x3*" -or $latestLabel -like "*loader-control-left200x3*")
    $latestValidLoaderControlLeft200x2 =
        $latestValidLoaderControl -and
        !$latestValidLoaderControlLeft200x4 -and
        !$latestValidLoaderControlLeft200x3 -and
        ($latestRun.Name -like "*loader-control-left200x2*" -or $latestLabel -like "*loader-control-left200x2*")
    $latestValidLoaderControlLeft200 =
        $latestValidLoaderControl -and
        !$latestValidLoaderControlLeft200x4 -and
        !$latestValidLoaderControlLeft200x2 -and
        !$latestValidLoaderControlLeft200x3 -and
        ($latestRun.Name -like "*loader-control-left200*" -or $latestLabel -like "*loader-control-left200*")
}
$newestValidLoaderControlRun = @($runEvidence | Where-Object {
    $label = if ($_.Lab.Label) { $_.Lab.Label } else { "" }
    $_.Decision -eq "valid-field-triage" -and
    ($_.Name -like "*loader-control*" -or $label -like "*loader-control*")
} | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
$newestValidLoaderControlLeft200x4 = $false
$newestValidLoaderControlLeft200x3 = $false
$newestValidLoaderControlLeft200x2 = $false
$newestValidLoaderControlLeftCount = -1
if ($newestValidLoaderControlRun) {
    $newestLabel = if ($newestValidLoaderControlRun.Lab.Label) { $newestValidLoaderControlRun.Lab.Label } else { "" }
    $newestValidLoaderControlLeftCount = Get-LoaderControlLeftPulseCount -RunEvidence $newestValidLoaderControlRun
    $newestValidLoaderControlLeft200x4 =
        $newestValidLoaderControlRun.Name -like "*loader-control-left200x4*" -or
        $newestLabel -like "*loader-control-left200x4*"
    $newestValidLoaderControlLeft200x3 =
        !$newestValidLoaderControlLeft200x4 -and
        ($newestValidLoaderControlRun.Name -like "*loader-control-left200x3*" -or
        $newestLabel -like "*loader-control-left200x3*")
    $newestValidLoaderControlLeft200x2 =
        !$newestValidLoaderControlLeft200x4 -and
        !$newestValidLoaderControlLeft200x3 -and
        ($newestValidLoaderControlRun.Name -like "*loader-control-left200x2*" -or $newestLabel -like "*loader-control-left200x2*")
}
$lane2CounterCleanVisualInvalid = @($runEvidence | Where-Object {
    $_.Decision -ne "valid-field-triage" -and
    $_.Decision -ne "valid-options-triage" -and
    $_.Lane.Lane2 -and
    $_.Lane.Lane2.Success -ne "" -and
    $_.Lane.Lane2.Failure -eq "0" -and
    $_.Lane.Lane2.Unexpected -eq "0"
})
$failedHle451cSize16BodyRuns = @($runEvidence | Where-Object {
    $label = if ($_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    ($text -like "*451c-size16-body-verify*" -or $text -like "*size16-body-verify*") -and
    $text -notlike "*size16-body-off*" -and
    $_.Decision -ne "valid-field-triage"
})
$baseLoaderControlLeftCount = if ($latestValidLoaderControlLeftCount -ge 0) {
    $latestValidLoaderControlLeftCount
} elseif ($newestValidLoaderControlLeftCount -ge 0) {
    $newestValidLoaderControlLeftCount
} else {
    -1
}
$nextLoaderControlLeftCount = if ($baseLoaderControlLeftCount -ge 0) { $baseLoaderControlLeftCount + 1 } else { -1 }
$nextLoaderControlLeftFailures = @()
if ($nextLoaderControlLeftCount -ge 1) {
    $nextLoaderControlLeftFailures = @($runEvidence | Where-Object {
        (Get-LoaderControlLeftPulseCount -RunEvidence $_) -eq $nextLoaderControlLeftCount -and
        $_.Decision -ne "valid-field-triage"
    })
}
$repeatFailedNextLoaderControl = $nextLoaderControlLeftFailures.Count -ge 2
$blockFailedNextLoaderControl = $repeatFailedNextLoaderControl -or (
    $baseLoaderControlLeftCount -eq 0 -and
    $nextLoaderControlLeftCount -eq 1 -and
    $nextLoaderControlLeftFailures.Count -ge 1
)
$nextLoaderControlRouteName = if ($nextLoaderControlLeftCount -eq 1) {
    "loader-control-left200"
} else {
    "loader-control-left200x$nextLoaderControlLeftCount"
}
$blockedNextLoaderControlAction = if ($blockFailedNextLoaderControl) {
    if ($repeatFailedNextLoaderControl) {
        "Do not repeat $nextLoaderControlRouteName; it has failed $($nextLoaderControlLeftFailures.Count) time(s) in the recent window. Repair route control or switch to SPU kernel HLE/codegen/verifier analysis before another movement run."
    } else {
        "Do not auto-rerun $nextLoaderControlRouteName. It already failed after a clean no-movement boundary; add or use black-overlay route control, shrink/change the movement pulse, or switch to SPU kernel HLE/codegen/verifier analysis before another movement run."
    }
} else {
    ""
}

if ($blackRuns.Count -ge 2) {
    if ($latestValidLoaderControl) {
        $controlAction = if ($blockFailedNextLoaderControl) {
            $blockedNextLoaderControlAction
        } elseif ($latestValidLoaderControlLeftCount -ge 5) {
            if ($repeatFailedNextLoaderControl) {
                $blockedNextLoaderControlAction
            } else {
                "Use the latest valid loader-control-left200x$latestValidLoaderControlLeftCount route as the base, but do not repeat the rejected diag200 branch; try one more left-only micro-pulse or start route-control repair before lane-2 HLE/GPU fast modes."
            }
        } elseif ($latestValidLoaderControlLeft200x4) {
            "Use the latest valid loader-control-left200x4 route as the base, but do not repeat the rejected diag200 branch; try one more left-only micro-pulse or start route-control repair before lane-2 HLE/GPU fast modes."
        } elseif ($latestValidLoaderControlLeft200x3) {
            "Use the latest valid loader-control-left200x3 route as the base, but do not repeat the rejected diag200 branch; try one more left-only micro-pulse or start route-control repair before lane-2 HLE/GPU fast modes."
        } elseif ($latestValidLoaderControlLeft200x2) {
            if ($recentDiag200Rejected) {
                "Use the latest valid loader-control-left200x2 route as the base, but do not repeat the rejected diag200 branch; try one left-only micro-pulse or rebuild route control before lane-2 HLE/GPU fast modes."
            } else {
                "Use the latest valid loader-control-left200x2 route as the base for one tiny diagonal micro-pulse; keep lane-2 HLE/GPU fast modes blocked."
            }
        } elseif ($latestValidLoaderControlLeft200) {
            "Use the latest valid loader-control-left200 route as the base for one second tiny state-aware movement step; keep lane-2 HLE/GPU fast modes blocked."
        } else {
            "Use the latest valid loader-control route as the base for one small state-aware movement step; keep lane-2 HLE/GPU fast modes blocked."
        }
        Add-AntiPattern -List $antiPatterns -Name "black-overlay-control-passed" -Severity "resolved-control" -Evidence ("{0} recent black/perf-overlay run(s), but newest loader-control reached field at {1}s." -f $blackRuns.Count, $latestRun.Visual.FirstFieldSeconds) -Action $controlAction
    } else {
        $blackAction = if ($latestLoaderControlReconfirm -and $latestBlackOverlay -and $newestValidLoaderControlLeftCount -ge 2) {
            "Latest reconfirm black-overlayed before field; do not loop the same reconfirm. Back off one pulse to loader-control-left200x$($newestValidLoaderControlLeftCount - 1)-reconfirm or repair route control."
        } elseif ($newestValidLoaderControlLeftCount -ge 5) {
            "Latest run black-overlayed before field; re-prove the newest clean loader-control-left200x$newestValidLoaderControlLeftCount boundary before adding another left-only pulse."
        } elseif ($newestValidLoaderControlLeft200x4) {
            "Latest run black-overlayed before field; re-prove the newest clean loader-control-left200x4 boundary before trying left200x5."
        } elseif ($newestValidLoaderControlLeft200x3) {
            "Latest run black-overlayed before field; re-prove the newest clean loader-control-left200x3 boundary before trying left200x4 again."
        } elseif ($newestValidLoaderControlLeft200x2) {
            "Latest run black-overlayed before field; re-prove the newest clean loader-control-left200x2 boundary before adding movement."
        } else {
            "Stop adding movement. Re-prove a no-movement loader/control with CleanAfterField, or add a route reset/black-overlay detector before SPU lane dry-runs."
        }
        Add-AntiPattern -List $antiPatterns -Name "repeated-black-overlay-pre-field" -Severity "blocker" -Evidence ("{0} of {1} recent runs were black/perf-overlay before accepted field." -f $blackRuns.Count, $runEvidence.Count) -Action $blackAction
    }
}
if ($loadingRuns.Count -ge 2) {
    Add-AntiPattern -List $antiPatterns -Name "repeated-loading-before-field" -Severity "blocker" -Evidence ("{0} of {1} recent runs stayed loading-like." -f $loadingRuns.Count, $runEvidence.Count) -Action "Increase or repair the accepted-field state gate before movement. Counters from loading-only captures are not comparable."
}
if ($cutsceneRuns.Count -ge 1) {
    $cutsceneAction = if ($latestHle451cSize16BodyMenuRouteMiss) {
        "Latest opt-in size16 body menu/Options attempt rendered clean intro/cutscene frames but missed the title Options target. Do not switch back to loader-control movement; repair or state-gate the menu route before rerunning the body menu proof."
    } elseif ($recentDiag200Rejected -and $latestValidLoaderControlLeftCount -ge 2) {
        "The left-only base has been re-proved, so keep the rejected diag200 branch blocked and try another left-only micro-pulse or route-control repair before any lane-2 HLE/GPU fast mode."
    } else {
        "Do not trust byte-size-only visual gates. Back off to the last valid loader-control route and re-prove the accepted field before adding movement."
    }
    Add-AntiPattern -List $antiPatterns -Name "cutscene-or-nonfield-frames" -Severity "blocker" -Evidence ("{0} recent run(s) had blue/red/dark non-field screenshots, including small blue/starry route misses." -f $cutsceneRuns.Count) -Action $cutsceneAction
}
if ($wrongWindowRuns.Count -ge 1) {
    $realWrongWindowRuns = @($wrongWindowRuns | Where-Object { $_.Decision -ne "valid-options-triage" })
    if ($realWrongWindowRuns.Count -ge 1) {
        Add-AntiPattern -List $antiPatterns -Name "window-capture-instability" -Severity "warning" -Evidence ("{0} recent run(s) had wrong-window/other small screenshots." -f $realWrongWindowRuns.Count) -Action "Keep RPCS3 on screen 1 and reject captures with small screenshots after first field-like output."
    }
}
if ($latestHle451cSize16BodyOffBattleRouteLost) {
    $battleRouteLossEvidence = if ($latestHle451cSize16BodyOffBattleProcessExit) {
        if ($latestHle451cSize16BodyOffBattleLeftOnlyProcessExit) {
            "Latest body-off first-battle left-only diagnostic reached a field screenshot, then RPCS3 exited before the left-only follow-up screenshot."
        } else {
            "Latest body-off first-battle diagnostic reached a field screenshot, then RPCS3 exited before the next battle screenshot."
        }
    } else {
        "Latest body-off first-battle reproof reached a field screenshot, then later battle screenshots were skipped because the game window was not found."
    }
    $battleRouteLossAction = if ($latestHle451cSize16BodyOffBattleProcessExit) {
        if ($latestHle451cSize16BodyOffBattleLeftOnlyProcessExit) {
            "Do not rerun the same left-only diagnostic. Run a no-post-field-movement diagnostic to separate route/timer exit from movement-triggered guest exit."
        } else {
            "Do not treat this as a clean body-off battle proof or body semantics proof. Isolate the failing input branch with a left-only diagnostic before testing the diagonal branch or body-on semantics."
        }
    } else {
        "Do not treat this as a clean body-off battle proof or body semantics proof. Repair the battle route/window-lost detection, or shorten/state-gate the capture around the battle transition, before any body-on rerun."
    }
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-off-battle-window-lost" -Severity "blocker" -Evidence $battleRouteLossEvidence -Action $battleRouteLossAction
}
if ($latestHle451cPreserveBodyOffBattleRouteLost -and
    -not $latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit -and
    -not $latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit) {
    $preserveBodyOffEvidence = if ($latestHle451cPreserveBodyOffBattleProcessExit) {
        "Latest preserve-body-off first-battle reproof reached a field screenshot, then RPCS3 exited before the battle screenshots."
    } else {
        "Latest preserve-body-off first-battle reproof reached a field screenshot, then the game window disappeared before the battle screenshots."
    }
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-window-lost" -Severity "blocker" -Evidence $preserveBodyOffEvidence -Action "Do not treat this as a clean body-off battle proof or preserve-body semantics result. Run a no-post-field-movement diagnostic before another body-on or body-off battle proof."
}
if ($latestHle451cPreserveBodyBattleRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-battle-route-miss" -Severity "blocker" -Evidence "Latest preserve-body battle diagnostic produced wrong-window/other screenshots instead of field or first battle. Manual check showed the route parked on the load menu." -Action "Repair or state-gate the Windows battle load macro before another preserve-body body-on/body-off proof. Do not switch to generic movement or preserve-body semantics work from this capture."
}
if ($latestHle25ccBodyBattleOptionsRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-body-battle-options-route-miss" -Severity "blocker" -Evidence "Latest 0x25cc body battle attempt produced repeated small title Options-page screenshots instead of active first battle." -Action "Do not rerun the same battle command. Repair the first-battle macro or add a battle-aware route/visual gate before any 0x25cc body battle proof or stock/body battle A/B."
}
if ($fatalRuns.Count -ge 1) {
    $fatalAction = if ($latestHle451cPreserveBodyBattleFatal) {
        "Latest preserve-body first-battle proof reached battle but froze with VM access violation. Re-prove the exact first-battle route with preserve-body Off before narrowing preserve-body semantics."
    } elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
        "Latest preserve-body-off top-slot left1600 diagnostic produced fatal RSX/shader evidence and corrupt field visuals after a clean left800 boundary. Back off to re-prove left800 before trying a smaller midpoint."
    } elseif ($latestFatal -and $newestValidLoaderControlLeftCount -ge 1) {
        "Do not extend the latest fatal route. Re-prove the newest clean loader-control-left200x$newestValidLoaderControlLeftCount boundary or repair route control before adding movement."
    } else {
        "Treat fatal log hits as invalid even when screenshots look field-like; re-prove the last clean boundary before more movement or lane-2 HLE/GPU fast modes."
    }
    Add-AntiPattern -List $antiPatterns -Name "fatal-log-hit" -Severity "blocker" -Evidence ("{0} recent run(s) had fatal/crash/access/Vulkan/assertion log hits." -f $fatalRuns.Count) -Action $fatalAction
}
if ($lane2CounterCleanVisualInvalid.Count -ge 1) {
    Add-AntiPattern -List $antiPatterns -Name "clean-lane-counters-with-invalid-visuals" -Severity "blocker" -Evidence ("{0} recent invalid visual run(s) still had clean lane-2 counters." -f $lane2CounterCleanVisualInvalid.Count) -Action "Do not start lane-2 HLE/GPU fast mode from counters alone. Require field/menu/battle visuals first."
}
if ($latestBlackHle451cSize16Candidate) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-candidate-black-overlay" -Severity "blocker" -Evidence "Latest 0x451c size-16 candidate capture black-overlayed before accepted field; its counters are runtime smoke only." -Action "Do not design or enable the batch body from this capture. Confirm no active RPCS3/RPCSX process, then rerun the no-movement 0x451c size-16 Verify route with CleanAfterField."
}
if ($latestHle451cSize16BodyBattleBlack) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-battle-black-overlay" -Severity "blocker" -Evidence "Latest opt-in size16 body first-battle proof black-overlayed before any valid battle visuals." -Action "Keep the body opt-in/off by default. Reprove the same first-battle route with size16 body off before another body-on battle, then inspect or narrow the body semantics."
}
if ($blockFailedNextLoaderControl) {
    $failedNextPatternName = if ($repeatFailedNextLoaderControl) { "repeated-next-loader-control-failure" } else { "single-next-loader-control-failure" }
    $failedNextEvidence = if ($repeatFailedNextLoaderControl) {
        "{0} failed {1} time(s) in the recent window after a lower boundary was clean." -f $nextLoaderControlRouteName, $nextLoaderControlLeftFailures.Count
    } else {
        "{0} failed once in the recent window after a clean no-movement boundary." -f $nextLoaderControlRouteName
    }
    Add-AntiPattern -List $antiPatterns -Name $failedNextPatternName -Severity "blocker" -Evidence $failedNextEvidence -Action $blockedNextLoaderControlAction
}
if ($rsxZeroRuns.Count -ge 2) {
    Add-AntiPattern -List $antiPatterns -Name "zero-rsx-local-repeated" -Severity "direction" -Evidence ("{0} recent summaries reported zero RSX-local traffic." -f $rsxZeroRuns.Count) -Action "Treat broad SPU-to-Vulkan compute as parked. Prefer SPU kernel HLE/codegen/verifier work unless a new scout proves RSX-consumed data."
}
if ($latestCleanHleDescriptorBatch) {
    Add-AntiPattern -List $antiPatterns -Name "hle-descriptor-baseline-clean" -Severity "resolved-control" -Evidence ("Newest clean HLE descriptor-batch run reached field at {0}s with fatal-clean logs." -f $latestRun.Visual.FirstFieldSeconds) -Action "Use this as the current HLE baseline. Do not rerun VerifyShadow or movement next; move to a bounded preserve-order inline-GET batch copier/verifier design."
}
if ($latestCleanHle451cSize16BodyOn) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-field-clean" -Severity "resolved-control" -Evidence ("Newest opt-in size16 body run reached field at {0}s after the release-exit repair." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep the body opt-in. Require menu/Options and first-battle visual/fatal proof before A/B timing, speed claims, or promotion."
}
if ($latestCleanHle451cSize16BodyOptions) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-options-clean" -Severity "resolved-control" -Evidence "Newest opt-in size16 body run reached the full title Options page with expected small menu screenshots and no black/loading classes." -Action "Keep the body opt-in. Run first-battle visual/fatal proof before A/B timing, speed claims, or promotion."
}
if ($latestCleanHle25ccBodyOptions) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-body-options-clean" -Severity "resolved-control" -Evidence "Newest opt-in 0x25cc body run reached the full title Options page with expected small menu screenshots and no black/loading classes." -Action "Keep the body opt-in. Prove first-battle visuals before stock/body battle A/B, micro-win banking, speed claims, or promotion."
}
if ($latestHle451cSize16BodyMenuRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-menu-route-miss" -Severity "blocker" -Evidence "Newest opt-in size16 body menu/Options attempt missed the Options target and captured intro/cutscene frames instead." -Action "Keep the body opt-in and repair the Windows menu/Options route or add a title-menu visual gate before rerunning menu proof."
}
if ($latestCleanHle451cSize16BodyOff -and $failedHle451cSize16BodyRuns.Count -ge 1) {
    Add-AntiPattern -List $antiPatterns -Name "hle-size16-body-black-overlay" -Severity "blocker" -Evidence ("{0} recent size16 body-on run(s) failed before clean visuals; newest body-off Verify reproof reached field at {1}s." -f $failedHle451cSize16BodyRuns.Count, $latestRun.Visual.FirstFieldSeconds) -Action "Keep the size16 body opt-in/off by default. Do not rerun the body path until the copy semantics are repaired or narrowed and a new Verify body run is explicitly requested."
}
if ($latestCleanHle451cPreserveBodyField) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-field-clean" -Severity "resolved-control" -Evidence ("Newest opt-in preserve-body run reached field at {0}s and kept the no-post-field route alive." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep preserve-body opt-in. Do not switch to movement next; prove title Options, then first battle, then matched timing before speed or migration claims."
}
if ($latestHle451cPreserveBodyOffBattleTopslotFieldClean -and -not $latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading -and -not $latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-field-clean" -Severity "resolved-control" -Evidence ("Newest preserve-body-off battle top-slot diagnostic reached accepted field at {0}s and stayed alive for the follow-up screenshot." -f $latestRun.Visual.FirstFieldSeconds) -Action "Treat this as battle load-route repair only, not preserve-body opt-in proof. Reuse the top-slot-normalized macro to isolate the left-only movement branch before any preserve-body-on battle retry."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft800FieldClean) {
    $left800Action = if ($recentHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
        "Treat left800 as the lower clean movement boundary, not battle proof. Since left1600 produced fatal RSX/shader evidence, try the smaller left1200 midpoint before diagonal movement or preserve-body-on battle work."
    } else {
        "Treat left800 as the lower clean movement boundary, not battle proof. Since left2600 exited RPCS3, binary-search with left1600 before diagonal movement or preserve-body-on battle work."
    }
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left800-field-clean" -Severity "resolved-control" -Evidence ("Newest preserve-body-off top-slot left800 diagnostic reached accepted field at {0}s and survived the follow-up screenshot." -f $latestRun.Visual.FirstFieldSeconds) -Action $left800Action
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1200-reproof-after-left1300-loading" -Severity "resolved-control" -Evidence ("Newest preserve-body-off top-slot left1200 reproof reached accepted field at {0}s and survived the follow-up screenshot after the left1300 loading-only miss." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep left1200 as the clean lower movement boundary, but do not loop back to left1400 or left1300. Repair/state-gate the accepted-field load route before trying another midpoint."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1200-field-clean" -Severity "resolved-control" -Evidence ("Newest preserve-body-off top-slot left1200 diagnostic reached accepted field at {0}s and survived the follow-up screenshot." -f $latestRun.Visual.FirstFieldSeconds) -Action "Treat left1200 as the new clean lower movement boundary, not battle proof. Since left1600 produced fatal RSX/shader evidence, try left1400 before diagonal movement or preserve-body-on battle work."
}
if ($latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-route-state-gate-after-left1200-reproof" -Severity "resolved-control" -Evidence ("Newest preserve-body-off top-slot route-state gate reached accepted field at {0}s and stayed field-clean through the stability screenshots." -f $latestRun.Visual.FirstFieldSeconds) -Action "The accepted-field route is stable again. Do not fall back to full left-only or rerun left1300; try a smaller state-gated left1250 diagnostic next."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft1250StateGatedBlack) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1250-state-gated-black" -Severity "blocker" -Evidence "Newest preserve-body-off top-slot left1250 state-gated diagnostic black-overlayed at accepted-field and pre-movement checkpoints before any left1250 boundary evidence." -Action "Do not treat left1250 as a movement boundary and do not shrink movement yet. Reconfirm or repair the accepted-field route-state gate before any further movement midpoint."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1400-exit" -Severity "blocker" -Evidence ("Newest preserve-body-off top-slot left1400 diagnostic reached accepted field at {0}s, then RPCS3 exited before the follow-up screenshot." -f $latestRun.Visual.FirstFieldSeconds) -Action "Treat left1400 as above the current clean boundary, not battle proof. Since left1200 survived cleanly, try left1300 before diagonal movement or preserve-body-on battle work."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft1300Loading) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1300-loading" -Severity "blocker" -Evidence "Newest preserve-body-off top-slot left1300 diagnostic stayed on the Now Loading screen at both accepted-field and follow-up checkpoints." -Action "Do not count left1300 as a movement boundary and do not switch to generic field movement. Re-prove the left1200 clean boundary with the same top-slot load macro before trying a new midpoint or route repair."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-left1600-fatal" -Severity "blocker" -Evidence ("Newest preserve-body-off top-slot left1600 diagnostic reached field at {0}s but had fatal RSX/shader evidence and corrupt follow-up visuals." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not repeat left1600 or generic no-movement. Re-prove the clean left800 boundary first; after it re-passes, binary-search with left1200."
}
if ($latestHle25ccNoPauseBattleAbComplete) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-nopause-battle-ab-complete" -Severity "direction" -Evidence "Newest 0x25cc no-pause BattleRoute A/B already reached valid field and late first-battle visuals, and the narrow A/B summary classifies the body as not-speed-win." -Action "Do not suggest generic loader-control movement or rerun the same A/B. Inspect body/family verifier timing, remove measurement overhead, or narrow the 0x25cc body before the next stock/body comparison."
}
if ($latestHle25ccBodyFastCpuStackComponent) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-cpu-load-stack-component" -Severity "resolved-control" -Evidence ("Newest 0x25cc bodyfast BattleRoute repeat is field/battle clean, fatal-clean, and has clean external host samples; {0}. FPS remains capped, so this is a CPU-pressure component only." -f $latestHle25ccBodyFastCpuEvidence) -Action "Stack bodyfast with the existing verified RSX geometry/locality credit stack in a combined Windows proof. Do not count bodyfast as FPS or GPU migration, and do not rerun bodyfast alone unless the stack regresses."
}
elseif ($latestHle25ccBodyFastCpuCandidate) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-cpu-load-candidate" -Severity "direction" -Evidence ("Newest 0x25cc bodyfast BattleRoute removed verifier/family/shadow timing overhead and held capped first-battle FPS; {0}. The body run still had postrun host-gate noise, so this is not banked." -f $latestHle25ccBodyFastCpuEvidence) -Action "Do not return to verifier-overhead removal. Repeat one clean bodyfast BattleRoute or run a fresh stock/bodyfast pair to confirm CPU-load reduction, then pivot to a larger 0x451c/codegen body if the gain remains capped."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-leftonly-exit" -Severity "blocker" -Evidence ("Newest preserve-body-off top-slot left-only diagnostic reached accepted field at {0}s, then RPCS3 exited after the left-only movement branch." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not fall back to the old non-top-slot no-post diagnostic. Top-slot no-post already stayed alive; shrink or repair the left-only movement branch before diagonal or preserve-body-on battle work."
}

$nextAction = if ($latestHle451cPreserveBodyBattleFatal) {
    "Latest 0x451c preserve-body first-battle proof reached battle, then froze with VM access violation at 0x40. Keep preserve-body opt-in/off and re-prove the same first-battle route with preserve-body Off before narrowing semantics."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1250StateGatedBlack) {
    "Latest preserve-body-off top-slot left1250 state-gated diagnostic black-overlayed before it proved accepted field, so it is a route/control miss rather than a movement boundary. Reconfirm or repair the no-movement route-state gate before any further midpoint."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1300Loading) {
    "Latest preserve-body-off top-slot left1300 diagnostic never reached field and stayed on Now Loading, so it is route/load failure rather than a movement boundary. Re-prove the left1200 clean boundary with the same top-slot macro before trying another midpoint or route repair."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
    "Latest preserve-body-off top-slot left1600 diagnostic hit fatal RSX/shader evidence and corrupt field visuals after left800 was clean. Back off to re-prove the left800 boundary before trying the left1200 midpoint."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof) {
    "Latest preserve-body-off top-slot route-state gate stayed field-clean through repeated accepted-field screenshots after the left1200 reproof. Keep left1200 as the lower boundary and try a state-gated left1250 diagnostic before any left1300/left1400 rerun."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading) {
    "Latest preserve-body-off top-slot left1200 reproof is clean after the left1300 loading-only miss. Keep left1200 as the clean lower boundary, but repair/state-gate the accepted-field load route before trying another midpoint."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean) {
    "Latest preserve-body-off top-slot left1200 diagnostic survived clean field follow-up after left1600 failed fatally. Keep preserve-body Off and try the left1400 midpoint before diagonal or preserve-body-on battle work."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit) {
    "Latest preserve-body-off top-slot left1400 diagnostic exited RPCS3 after accepted field, while left1200 survived cleanly. Keep preserve-body Off and try the left1300 midpoint before diagonal or preserve-body-on battle work."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft800FieldClean) {
    if ($recentHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
        "Latest preserve-body-off top-slot left800 diagnostic survived clean field follow-up, and a recent left1600 attempt failed fatally. Keep preserve-body Off and try the left1200 midpoint before diagonal or preserve-body-on battle work."
    } else {
        "Latest preserve-body-off top-slot left800 diagnostic survived clean field follow-up, while left2600 exited RPCS3. Keep preserve-body Off and binary-search the left branch with a left1600 diagnostic before diagonal or preserve-body-on battle work."
    }
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit) {
    "Latest preserve-body-off top-slot left-only diagnostic reached accepted field, then RPCS3 exited after left-only movement. The top-slot no-post route already stayed alive, so shrink the left pulse or repair route control before diagonal or preserve-body-on battle work."
} elseif ($latestHle451cPreserveBodyOffBattleRouteLost) {
    if ($latestHle451cPreserveBodyOffBattleProcessExit) {
        "Latest preserve-body-off first-battle reproof reached field, then RPCS3 exited before battle screenshots. Treat this as battle-route process exit; run a no-post-field-movement diagnostic before inspecting preserve-body semantics."
    } else {
        "Latest preserve-body-off first-battle reproof only reached field, then the game window disappeared before battle screenshots. Treat this as route/window-loss, not clean body-off proof; repair or state-gate the battle route before preserve-body semantics work."
    }
} elseif ($latestHle451cPreserveBodyBattleRouteMiss) {
    "Latest preserve-body battle diagnostic stayed in the load menu instead of reaching field or battle. Repair/state-gate the Windows battle route before any preserve-body semantics or speed work."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotFieldClean) {
    "Latest preserve-body-off battle top-slot diagnostic repaired the load-menu miss and reached accepted field. Keep preserve-body Off and isolate the left-only movement branch with the same top-slot-normalized load macro before any preserve-body semantics or speed work."
} elseif ($latestHle25ccBodyFastCpuStackComponent) {
    "Latest 0x25cc bodyfast BattleRoute repeat is clean and confirms lower RPCS3 CPU pressure while FPS stays capped. Treat it as a stackable CPU-pressure component; next run should combine it with the existing RSX geometry/locality credit stack, not rerun bodyfast alone."
} elseif ($latestHle25ccBodyFastCpuCandidate) {
    "Latest 0x25cc bodyfast BattleRoute has clean field/battle visuals and capped FPS, with directional CPU-load reduction but postrun host-gate noise. Repeat a clean bodyfast or fresh stock/bodyfast pair to confirm CPU-load micro-win potential; otherwise pivot to larger 0x451c/codegen work."
} elseif ($latestHle25ccNoPauseBattleAbComplete) {
    "Latest 0x25cc no-pause BattleRoute A/B is complete and classified not-speed-win. Do not add generic route movement or rerun the same A/B; inspect body/family verifier timing, remove measurement overhead, or narrow the 0x25cc body before another matched comparison."
} elseif ($latestHle25ccBodyBattleOptionsRouteMiss) {
    "Latest 0x25cc body battle attempt opened the title Options page instead of first battle. Do not rerun that battle command unchanged; repair the first-battle macro or add a battle-aware route/visual gate before battle proof or stock/body A/B."
} elseif ($latestFatal -and $newestValidLoaderControlLeftCount -ge 1) {
    "Latest run had fatal/crash log evidence; do not extend it. Re-prove the newest clean loader-control-left200x$newestValidLoaderControlLeftCount boundary with CleanAfterField before adding another pulse."
} elseif ($latestFatal) {
    "Latest run had fatal/crash log evidence; run a no-movement loader/control with CleanAfterField before adding movement."
} elseif ($latestBlackOverlay -and $latestLoaderControlReconfirm -and $newestValidLoaderControlLeftCount -ge 2) {
    "Latest reconfirm of loader-control-left200x$newestValidLoaderControlLeftCount black-overlayed before accepted field; do not loop the same command. Back off one pulse and re-prove loader-control-left200x$($newestValidLoaderControlLeftCount - 1) with CleanAfterField."
} elseif ($latestHle451cSize16BodyMenuRouteMiss) {
    "Latest size-16 body menu/Options attempt rendered clean intro/cutscene frames but missed the Options target; repair or state-gate the menu route before rerunning menu proof, and do not claim menu correctness."
} elseif ($latestHle451cSize16BodyOffBattleRouteLost) {
    if ($latestHle451cSize16BodyOffBattleProcessExit) {
        if ($latestHle451cSize16BodyOffBattleLeftOnlyProcessExit) {
            "Latest body-off first-battle left-only diagnostic also exited RPCS3 after field. Run a no-post-field-movement diagnostic next to separate route/timer exit from movement-triggered guest exit."
        } else {
            "Latest body-off first-battle diagnostic reached field, then RPCS3 exited before the next screenshot. Treat this as battle-route process exit; run a left-only isolation diagnostic before testing diagonal movement or body-on semantics."
        }
    } else {
        "Latest body-off first-battle reproof only reached field, then the game window disappeared before battle screenshots. Treat this as route/window-loss, not clean body-off proof; repair the battle route or window-lost gate before inspecting body semantics."
    }
} elseif ($latestCleanHle451cSize16BodyOptions) {
    "Latest size-16 body path reached the full title Options page after the fast-open route repair; keep it opt-in and prove first-battle visuals before speed A/B or promotion."
} elseif ($latestCleanHle25ccBodyOptions) {
    "Latest 0x25cc body path reached the full title Options page. Keep it opt-in and prove first-battle visuals before stock/body battle A/B, micro-win banking, speed claims, or promotion."
} elseif ($latestCleanHle451cPreserveBodyOptions) {
    "Latest 0x451c preserve-body path reached the full title Options page. Keep it opt-in and prove first-battle visuals before matched timing, speed A/B, or promotion."
} elseif ($latestCleanHle451cPreserveBodyField) {
    "Latest 0x451c preserve-body field smoke is clean. Keep it opt-in, do not add movement next, and prove title Options before first-battle or speed A/B claims."
} elseif ($latestCutsceneOrNonfield -and $blockFailedNextLoaderControl) {
    "Latest loader-control movement produced non-field/cutscene frames after a clean lower boundary; do not auto-rerun that movement. Add or repair route-state visual detection, shrink/change the pulse only after pre-movement field is proven, or switch to focused SPU kernel HLE/codegen/verifier analysis."
} elseif ($latestCutsceneOrNonfield) {
    "Back off from the latest non-field/cutscene route and re-prove the last clean loader-control-left200x2 route with CleanAfterField before adding any diagonal or HLE/GPU fast mode."
} elseif ($latestCleanHle451cSize16BodyOn) {
    "Latest size-16 body path is field-clean after the release-exit repair; keep it opt-in and prove menu/Options plus first-battle visuals before any speed A/B or promotion."
} elseif ($latestCleanHle451cSize16BodyOff -and $failedHle451cSize16BodyRuns.Count -ge 1) {
    "Latest body-off Verify reproof is clean after the size16 body-on path black-overlayed; keep the body opt-in/off and inspect/repair the body copy semantics before rerunning it."
} elseif ($latestCleanHleDescriptorBatch) {
    "Latest clean descriptor-batch Verify route restored the HLE baseline; do not rerun VerifyShadow or movement now. Next step is a bounded preserve-order inline-GET batch copier/verifier design while broad SPU-to-Vulkan remains parked."
} elseif ($latestHle451cSize16BodyBattleBlack) {
    "Latest size-16 body first-battle proof black-overlayed; keep the body opt-in/off, reprove first battle with size16 body off, then inspect or narrow the body semantics before another body-on battle."
} elseif ($latestBlackHle451cSize16Candidate) {
    "Latest 0x451c size-16 candidate capture black-overlayed; discard it for body design, confirm no active RPCS3/RPCSX process, then re-prove the no-movement HLE Verify route with CleanAfterField before implementing a batch body."
} elseif ($blockFailedNextLoaderControl) {
    $blockedNextLoaderControlAction
} elseif ($latestValidLoaderControlLeftCount -ge 5 -and $recentDiag200Rejected) {
    "Do not repeat the rejected diag200 route; extend the newest valid loader-control-left200x$latestValidLoaderControlLeftCount route by exactly one more left-only micro-pulse with CleanAfterField, while lane-2 HLE/GPU dry-runs stay blocked."
} elseif ($latestValidLoaderControlLeftCount -ge 5) {
    "Extend the newest valid loader-control-left200x$latestValidLoaderControlLeftCount route by exactly one more left-only micro-pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestValidLoaderControlLeft200x4 -and $recentDiag200Rejected) {
    "Do not repeat the rejected diag200 route; extend the newest valid loader-control-left200x4 route by exactly one more left-only micro-pulse with CleanAfterField, while lane-2 HLE/GPU dry-runs stay blocked."
} elseif ($latestValidLoaderControlLeft200x4) {
    "Extend the newest valid loader-control-left200x4 route by exactly one more left-only micro-pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestValidLoaderControlLeft200x3 -and $recentDiag200Rejected) {
    "Do not repeat the rejected diag200 route; extend the newest valid loader-control-left200x3 route by exactly one more left-only micro-pulse with CleanAfterField, while lane-2 HLE/GPU dry-runs stay blocked."
} elseif ($latestValidLoaderControlLeft200x3) {
    "Extend the newest valid loader-control-left200x3 route by exactly one more left-only micro-pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestValidLoaderControlLeft200x2 -and $recentDiag200Rejected) {
    "Do not repeat the rejected diag200 route; extend the newest valid loader-control-left200x2 route by exactly one left-only micro-pulse with CleanAfterField, while lane-2 HLE/GPU dry-runs stay blocked."
} elseif ($latestValidLoaderControlLeft200x2) {
    "Extend the newest valid loader-control-left200x2 route by exactly one tiny diagonal micro-pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestValidLoaderControlLeft200) {
    "Extend the newest valid loader-control-left200 route by exactly one more tiny state-aware left pulse with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestValidLoaderControl) {
    "Use the newest valid loader-control as the route base, then add one small state-aware movement step with CleanAfterField; keep lane-2 HLE/GPU dry-runs blocked."
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeftCount -ge 5) {
    "Latest run black-overlayed before accepted field; re-prove the newest clean loader-control-left200x$newestValidLoaderControlLeftCount boundary with CleanAfterField before adding another left-only pulse."
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x4) {
    "Latest run black-overlayed before accepted field; re-prove the newest clean loader-control-left200x4 boundary with CleanAfterField before trying left200x5."
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x3) {
    "Latest run black-overlayed before accepted field; re-prove the newest clean loader-control-left200x3 boundary with CleanAfterField before trying left200x4 again."
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x2) {
    "Latest run black-overlayed before accepted field; re-prove the newest clean loader-control-left200x2 boundary with CleanAfterField before adding movement."
} elseif ($blackRuns.Count -ge 2) {
    "Add or use black-overlay route control before any movement or lane-2 HLE/GPU dry-run."
} elseif ($loadingRuns.Count -ge 2) {
    "Repair accepted-field loader gating before adding movement."
} elseif ($validFieldRuns.Count -gt 0) {
    "Use the newest valid-field run as the route base, but only add one small state-aware movement step with CleanAfterField."
} else {
    "Run a no-movement Windows loader/control with CleanAfterField to regain a valid field baseline."
}

$suggestedCommand = if ($latestHle451cPreserveBodyBattleFatal) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-off-first-battle-reproof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Off -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8"
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1250StateGatedBlack) {
    New-Hle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200ReproofCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1300Loading) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300LoadingCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft800DiagnosticCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200Reproof) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft1250StateGatedDiagnosticCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1200ReproofAfterLeft1300Loading) {
    New-Hle451cPreserveBodyOffBattleTopslotRouteStateGateAfterLeft1200ReproofCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1200FieldClean) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft1400DiagnosticCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft1400ProcessExit) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft1300DiagnosticCommand
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeft800FieldClean) {
    if ($recentHle451cPreserveBodyOffBattleTopslotLeft1600Fatal) {
        New-Hle451cPreserveBodyOffBattleTopslotLeft1200DiagnosticCommand
    } else {
        New-Hle451cPreserveBodyOffBattleTopslotLeft1600DiagnosticCommand
    }
} elseif ($latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit) {
    New-Hle451cPreserveBodyOffBattleTopslotLeft800DiagnosticCommand
} elseif ($latestHle451cPreserveBodyOffBattleRouteLost) {
    if ($latestHle451cPreserveBodyOffBattleProcessExit) {
        New-Hle451cPreserveBodyOffBattleNoPostFieldMoveDiagnosticCommand
    } else {
        "# No automatic preserve-body rerun: preserve-body-off first-battle reproof lost the RPCS3 window after a field screenshot. Repair/state-gate the battle route and window-lost detector before testing preserve-body semantics."
    }
} elseif ($latestHle451cPreserveBodyBattleRouteMiss) {
    "# No automatic preserve-body battle rerun: latest preserve-body battle diagnostic stayed on the load menu. Repair the battle load macro or add an accepted-field visual gate before testing body-on/body-off semantics again."
} elseif ($latestHle451cPreserveBodyOffBattleTopslotFieldClean) {
    New-Hle451cPreserveBodyOffBattleTopslotLeftOnlyDiagnosticCommand
} elseif ($latestHle25ccBodyFastCpuStackComponent) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-geomstack-battle-topslot-nopause -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastCpuCandidate) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-battle-topslot-nopause-battleroute-repeat -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccNoPauseBattleAbComplete) {
    "# No automatic rerun: latest 0x25cc no-pause BattleRoute A/B already proved field and first-battle visuals but was slower. Inspect body/family timing, remove verifier overhead, or narrow the 0x25cc body before another stock/body A/B."
} elseif ($latestHle25ccBodyBattleOptionsRouteMiss) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestFatal -and $newestValidLoaderControlLeftCount -ge 1) {
    New-LoaderControlLeftPulseCommand -Count $newestValidLoaderControlLeftCount -Reconfirm
} elseif ($latestFatal) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8"
} elseif ($latestBlackOverlay -and $latestLoaderControlReconfirm -and $newestValidLoaderControlLeftCount -ge 2) {
    New-LoaderControlLeftPulseCommand -Count ($newestValidLoaderControlLeftCount - 1) -Reconfirm
} elseif ($latestHle451cSize16BodyMenuRouteMiss) {
    "# Latest size16 body Options attempt missed the title Options route. Repair the Windows menu macro or add a title-menu/Options visual gate, then rerun with -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Verify."
} elseif ($latestHle451cSize16BodyOffBattleRouteLost) {
    if ($latestHle451cSize16BodyOffBattleProcessExit) {
        if ($latestHle451cSize16BodyOffBattleLeftOnlyProcessExit) {
            New-Hle451cBodyOffBattleNoPostFieldMoveDiagnosticCommand
        } else {
            New-Hle451cBodyOffBattleLeftOnlyDiagnosticCommand
        }
    } else {
        "# No automatic body rerun: body-off first-battle reproof lost the RPCS3 window after a field screenshot. Repair/state-gate the battle route and window-lost detector before testing size16 body semantics."
    }
} elseif ($latestCleanHle451cSize16BodyOptions) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-size16-body-releasefix-battle -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8"
} elseif ($latestCleanHle25ccBodyOptions) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestCleanHle451cPreserveBodyOptions) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-preserve-body-first-battle-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8"
} elseif ($latestCleanHle451cPreserveBodyField) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label hle-451c-preserve-body-options-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -EternalSonataSpuHle451cPreserveBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 90 -ScreenshotMaxCount 8"
} elseif ($latestCutsceneOrNonfield -and $blockFailedNextLoaderControl) {
    "# No automatic loader-control movement rerun: latest route produced cutscene/non-field frames after a clean lower boundary. Repair route-state detection, shrink/change the pulse after pre-movement field proof, or switch to SPU kernel HLE/codegen/verifier analysis."
} elseif ($latestCutsceneOrNonfield) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-confirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11"
} elseif ($latestCleanHle451cSize16BodyOn) {
    "# Size16 body field proof is clean. Next: run menu/Options and first-battle with -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Verify before speed A/B or promotion."
} elseif ($latestCleanHle451cSize16BodyOff -and $failedHle451cSize16BodyRuns.Count -ge 1) {
    "# No automatic size16 body rerun: body-on black-overlayed and body-off reproof is clean. Keep -EternalSonataSpuHleSize16Body Off while inspecting/repairing copy semantics."
} elseif ($latestCleanHleDescriptorBatch) {
    "# No automatic movement rerun: latest clean HLE descriptor-batch run is the base. Inspect do_list_transfer() and implement a verify-gated preserve-order inline-GET batch copier next."
} elseif ($latestHle451cSize16BodyBattleBlack) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-451c-size16-body-off-battle-reproof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify -EternalSonataSpuHleSize16Body Off -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 220 -ScreenshotMaxCount 8"
} elseif ($latestBlackHle451cSize16Candidate) {
    New-Hle451cSize16CandidateReproofCommand
} elseif ($blockFailedNextLoaderControl) {
    if ($repeatFailedNextLoaderControl) {
        "# No automatic movement rerun: $nextLoaderControlRouteName already failed $($nextLoaderControlLeftFailures.Count) time(s). Repair route control or run a focused SPU kernel HLE/codegen/verifier analysis next."
    } else {
        "# No automatic movement rerun: $nextLoaderControlRouteName already failed after a clean no-movement boundary. Add or use black-overlay route control, shrink/change the movement pulse, or run focused SPU kernel HLE/codegen/verifier analysis next."
    }
} elseif ($latestValidLoaderControlLeftCount -ge 5) {
    New-LoaderControlLeftPulseCommand -Count ($latestValidLoaderControlLeftCount + 1)
} elseif ($latestValidLoaderControlLeft200x4) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x5-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 245 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 14"
} elseif ($latestValidLoaderControlLeft200x3) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x4-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 235 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 13"
} elseif ($latestValidLoaderControlLeft200x2 -and $recentDiag200Rejected) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x3-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12"
} elseif ($latestValidLoaderControlLeft200x2) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-diag200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;combo:ls_left+ls_down:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12"
} elseif ($latestValidLoaderControlLeft200) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11"
} elseif ($latestValidLoaderControl) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 205 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 10"
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeftCount -ge 5) {
    New-LoaderControlLeftPulseCommand -Count $newestValidLoaderControlLeftCount -Reconfirm
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x4) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x4-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 235 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 13"
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x3) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x3-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 225 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 12"
} elseif ($latestBlackOverlay -and $newestValidLoaderControlLeft200x2) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-left200x2-reconfirm-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100`" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 110 -ScreenshotMaxCount 11"
} elseif ($blackRuns.Count -ge 2 -or $validFieldRuns.Count -eq 0) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-loader-control-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 8"
} else {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-one-step-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160"
}

$generated = (Get-Date).ToString("o")
$antiPatternArray = @($antiPatterns | ForEach-Object { $_ })
$runEvidenceArray = @($runEvidence | ForEach-Object { $_ })
$result = [pscustomobject]@{
    Generated = $generated
    RunRoot = (Resolve-Path -LiteralPath $RunRoot).Path
    MaxRuns = $MaxRuns
    SourceIdea = "Adapted from continual-harness as a deterministic trajectory-window refiner, not as an autonomous code mutation loop."
    NextAction = $nextAction
    SuggestedCommand = $suggestedCommand
    AntiPatterns = $antiPatternArray
    Runs = $runEvidenceArray
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# PS3 Continual Harness Refiner")
$md.Add("")
$md.Add(("- Generated: ``{0}``" -f $generated))
$md.Add(("- Run root: ``{0}``" -f (Resolve-Path -LiteralPath $RunRoot).Path))
$md.Add(("- Recent runs scanned: ``{0}``" -f $runEvidence.Count))
$md.Add("- Source adaptation: trajectory-window refinement inspired by sethkarten/continual-harness; this repo version only reports gates, anti-patterns, and next actions.")
$md.Add("")
$md.Add("## Next Action")
$md.Add("")
$md.Add(("- Decision: ``{0}``" -f $nextAction))
$md.Add("")
$md.Add('```powershell')
$md.Add($suggestedCommand)
$md.Add('```')
$md.Add("")
$md.Add("## Anti-Patterns")
$md.Add("")
if ($antiPatterns.Count -eq 0) {
    $md.Add("- None detected in the recent window.")
} else {
    foreach ($antiPattern in $antiPatterns) {
        $md.Add(("- ``{0}`` (``{1}``): {2} Action: {3}" -f $antiPattern.Name, $antiPattern.Severity, $antiPattern.Evidence, $antiPattern.Action))
    }
}
$md.Add("")
$md.Add("## Recent Runs")
$md.Add("")
$md.Add("| Run | Visual | Fatal | Primary small class | Field | RSX-local | Offload fit | Lane 2 | Decision |")
$md.Add("| --- | --- | --- | --- | --- | ---: | --- | --- | --- |")
foreach ($run in $runEvidence) {
    $fieldText = if ($run.Visual.FirstFieldScreenshot) {
        "{0} at {1}s" -f $run.Visual.FirstFieldScreenshot, $run.Visual.FirstFieldSeconds
    } else {
        "none"
    }
    $laneText = if ($run.Lane.Lane2) {
        "{0}/{1}/{2}/{3}/{4}" -f $run.Lane.Lane2.Attempts, $run.Lane.Lane2.Completed, $run.Lane.Lane2.Success, $run.Lane.Lane2.Failure, $run.Lane.Lane2.Unexpected
    } else {
        "n/a"
    }
    $rsxLocal = if ($run.Gpu.RsxLocalTrafficRecords) { $run.Gpu.RsxLocalTrafficRecords } else { "n/a" }
    $fit = if ($run.Gpu.OffloadFitMix) { $run.Gpu.OffloadFitMix } else { "n/a" }
    $primarySmall = if ($run.Visual.PrimarySmallClass) { $run.Visual.PrimarySmallClass } else { "none" }
    $fatalText = if ($run.Fatal -and $run.Fatal.HasFatal) { "yes" } else { "no" }
    $md.Add(("| ``{0}`` | ``{1}`` | ``{2}`` | ``{3}`` | {4} | {5} | {6} | {7} | ``{8}`` |" -f $run.Name, $run.Visual.Status, $fatalText, $primarySmall, $fieldText, $rsxLocal, $fit, $laneText, $run.Decision))
}
$md.Add("")
$md.Add("## Reading")
$md.Add("")
$md.Add("- This is process tooling, not a speed result and not GPU migration credit.")
$md.Add("- Counters from black, loading, or wrong-window captures stay invalid for HLE/GPU promotion.")
$md.Add("- Fatal/crash/access/Vulkan/assertion log hits invalidate a run even when screenshots look field-like.")
$md.Add("- A clean lane-2 counter row is only actionable after field, menu/Options, and first-battle visuals are valid.")

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $OutPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutPath, $md, [System.Text.UTF8Encoding]::new($false))

    $jsonDir = Split-Path -Parent $JsonPath
    if ($jsonDir -and -not (Test-Path -LiteralPath $jsonDir -PathType Container)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
}

$md | Write-Output

if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("JSON: {0}" -f $JsonPath)
}
