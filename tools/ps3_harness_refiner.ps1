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

function New-StateAwareDamagedSaveConfirmCommand {
    $macro = "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;cross:120;wait:15000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-damaged-confirm-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"$macro`" -MaxSeconds 175 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8"
}

function New-StateAwareDamagedSaveDismissMovementCommand {
    $macro = "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;cross:120;wait:15000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-damaged-confirm-dismiss-save-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 160 -InputMacro `"$macro`" -MaxSeconds 185 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8"
}

function New-StateAwareLateLoadConfirmCommand {
    $macro = "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;up:80;wait:300;cross:120;wait:35000;shot:100;wait:1000;ls_left:200;wait:1000;shot:100;wait:10000;shot:100"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-late-load-confirm-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 175 -InputMacro `"$macro`" -MaxSeconds 215 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 135 -ScreenshotMaxCount 8"
}

function New-StateAwareLateLoadDoubleConfirmDismissMovementCommand {
    $macro = "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;up:80;wait:300;cross:120;wait:1200;cross:120;wait:35000;shot:100;down:80;wait:300;cross:120;wait:1500;ls_left:200;wait:1000;shot:100;wait:10000;shot:100"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-loadtarget-pollgated-doubleconfirm-dismisssave-left200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 215 -InputMacro `"$macro`" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 155 -ScreenshotMaxCount 10"
}

function New-StateAwareLoadTargetPollGatedDirectLeftCommand {
    $macro = "wait:45000;down:20;wait:500;cross:80;wait:12000;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:100;ls_left:200;wait:1200;shot:100;wait:10000;shot:100"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-stateaware-loadtarget-pollgated-directleft200-longgate-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 175 -InputMacro `"$macro`" -MaxSeconds 230 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 130 -ScreenshotMaxCount 9"
}

function New-StateAwareTitleToLoadDiagnosticCommand {
    $macro = "wait:65000;shot:title-settle;down:20;wait:500;shot:title-after-down;cross:80;wait:12000;shot:post-title-cross;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:160;up:80;wait:500;shot:pre-load-target-gate;gate_load_target:25000"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-title-to-load-state-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 125 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-StateAwareTitleToLoadDownHoldDiagnosticCommand {
    $macro = "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:12000;shot:post-title-cross-down160;up:120;wait:200;up:120;wait:200;up:120;wait:200;up:120;wait:200;up:120;wait:600;shot:pre-load-target-gate-down160;gate_load_target:30000"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-title-to-load-down160-state-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 140 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-StateAwareTitleToLoadDownHoldLoadTargetReproofCommand {
    $macro = "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:12000;shot:post-title-cross-down160;gate_load_target:45000"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadtarget-reproof-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 145 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
}

function New-StateAwareTitleToLoadDownHoldDirectLeftCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field-check;ls_left:200;wait:1200;shot:left200-check;wait:10000;shot:late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-pollgated-directleft200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 175 -InputMacro `"$macro`" -MaxSeconds 230 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 130 -ScreenshotMaxCount 9"
}

function New-StateAwareTitleToLoadDownHoldLoadStabilityNoMoveCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:post-confirm-90s;wait:45000;shot:post-confirm-135s;wait:45000;shot:post-confirm-180s"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadstability-nocross-nomove-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro `"$macro`" -MaxSeconds 285 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 130 -ScreenshotMaxCount 13"
}

function New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissNoMoveCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;wait:45000;shot:post-dismiss-63s"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-lateloadcomplete-dismiss-nomove-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 275 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10"
}

function New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissDirectLeftCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:200;wait:1200;shot:left200-check;wait:10000;shot:late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-lateloadcomplete-dismiss-directleft200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10"
}

function New-Hle25ccShadowDescDown160VerifyCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:200;wait:1200;shot:left200-check;wait:10000;shot:late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-down160-latedismiss-directleft-field -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 260 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescOptionsCommand {
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -MaxSeconds 190 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 90 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescOptionsNoInitialCrossCommand {
    $macro = "wait:65000;shot:title-preinput;down:220;wait:1000;shot:title-after-down1;down:220;wait:16000;shot:title-after-down2;cross:180;wait:8000;shot:options-candidate;wait:12000;shot:options-late"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-nocross-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 155 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 70 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescOptionsFastSelectCommand {
    $macro = "wait:65000;shot:title-preinput;down:160;wait:600;shot:title-after-down1;down:160;wait:600;shot:title-after-down2-fast;cross:180;wait:6000;shot:options-candidate;wait:10000;shot:options-late"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene menu -Label cpu4-hle-25cc-shadow-desc-options-fastselect-proof -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 130 -ScreenshotEverySeconds 5 -ScreenshotStartSeconds 65 -ScreenshotMaxCount 14 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleVerifyCommand {
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -EternalSonataSpuHleVerify Verify25ccShadow -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockControlCommand {
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-hle-25cc-shadow-desc-battle-stock-control-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160LeftOnlyCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:2600;wait:45000;shot:left2600-check;wait:60000;shot:left2600-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-leftonly-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160Left1200Command {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-left1200-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160StrongDismissNoMoveCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;wait:45000;shot:strong-dismiss-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-nomove-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1200Command {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 270 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1200LongGateCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1200;wait:12000;shot:left1200-check;wait:45000;shot:left1200-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro `"$macro`" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1800LongGateCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:60000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:300;wait:18000;shot:post-load-complete-strong-dismiss-18s;ls_left:1800;wait:12000;shot:left1800-check;wait:45000;shot:left1800-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1800-longgate-diagnostic -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataGpuProbe Profile -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 260 -InputMacro `"$macro`" -MaxSeconds 300 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 8 -HostSampleSeconds 1 -HostSampleEverySeconds 30"
}

function New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissBattleLeftOnlyDiagnosticCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:90000;shot:load-complete-90s;cross:120;wait:18000;shot:post-load-complete-dismiss-18s;ls_left:2600;wait:45000;shot:left2600-check;wait:60000;shot:left2600-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 240 -InputMacro `"$macro`" -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 170 -ScreenshotMaxCount 10"
}

function New-StateAwareTitleToLoadDownHoldPostLoadCompleteDismissCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:load-complete-check;cross:120;wait:12000;shot:post-load-complete-dismiss-check;ls_left:200;wait:1200;shot:left200-check;wait:10000;shot:late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-postloadcomplete-dismiss-directleft200-visualgate-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 190 -InputMacro `"$macro`" -MaxSeconds 250 -ScreenshotEverySeconds 10 -ScreenshotStartSeconds 130 -ScreenshotMaxCount 10"
}

function New-StateAwareTitleToLoadDownHoldBattleRouteCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field-check;ls_left:2600;wait:1000;combo:ls_left+ls_down:2200;wait:45000;shot:battle-candidate;dpad_down:120;wait:500;cross:180;wait:60000;shot:first-battle-check;wait:60000;shot:late-battle-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-titleload-down160-firstbattle-battleroute-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 175 -InputMacro `"$macro`" -MaxSeconds 335 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12"
}

function New-StateAwareTitleToLoadDownHoldBattleLeftOnlyDiagnosticCommand {
    $macro = "wait:65000;down:160;wait:900;cross:120;wait:12000;gate_load_target:30000;cross:80;wait:3000;up:80;wait:500;cross:80;wait:32000;cross:120;wait:18000;shot:accepted-field-check;ls_left:2600;wait:45000;shot:left2600-check;wait:60000;shot:left2600-late-check"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-firstbattle-leftonly-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate CleanAfterField -WindowsVisualGateFieldSeconds 175 -InputMacro `"$macro`" -MaxSeconds 285 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 130 -ScreenshotMaxCount 10"
}

function New-StateAwareTitleToLoadDownHoldLoadListCursorDiagnosticCommand {
    $macro = "wait:65000;shot:title-settle;down:160;wait:900;shot:title-after-down160;cross:120;wait:14000;shot:save-check-14s;wait:16000;shot:load-list-probe-30s;wait:15000;shot:load-list-stable-45s;up:120;wait:900;shot:load-list-after-up1;up:120;wait:900;shot:load-list-after-up2;down:120;wait:900;shot:load-list-after-down1"
    return ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene field -Label cpu4-titleload-down160-loadlist-cursor-diagnostic-windows -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsVisualGate Off -InputMacro `"$macro`" -MaxSeconds 170 -ScreenshotEverySeconds 0 -ScreenshotStartSeconds 0 -ScreenshotMaxCount 0"
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

function Get-LabPlainValue {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $pattern = "^" + [regex]::Escape($Label) + ":\s*(.+)$"
    foreach ($line in $Lines) {
        if ($line -match $pattern) {
            return $matches[1].Trim().TrimEnd(".")
        }
    }
    return ""
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
        InputMacro = Get-LabSetting -Lines $lines -Label "Input macro"
        InputMacroTokens = Get-LabPlainValue -Lines $lines -Label "Input macro tokens"
        HostChecks = $hostChecks.Count
        HostBadChecks = $hostBad.Count
        WindowNotFoundScreenshots = $windowNotFoundScreenshots.Count
        ProcessExitedWindowLoss = $processExitedWindowLoss.Count
        EarlyProcessExitLines = $earlyProcessExitLines.Count
    }
}

function Read-LoadTargetEvidence {
    param([System.IO.DirectoryInfo]$Run)

    $summaryPath = Join-Path $Run.FullName "eternal-sonata-load-target-summary.md"
    $markerPath = Join-Path $Run.FullName "load-target-gate-failed.txt"
    $summaryLines = Read-FileLines -Path $summaryPath
    $status = Get-MarkdownBulletValue -Lines $summaryLines -Label "Status"
    if ([string]::IsNullOrWhiteSpace($status)) {
        $status = ""
    }

    $markerText = ""
    if (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        $markerText = ((Read-FileLines -Path $markerPath) -join " ").Trim()
        if ($markerText.Length -gt 220) {
            $markerText = $markerText.Substring(0, 220) + "..."
        }
    }

    return [pscustomobject]@{
        SummaryPath = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { $summaryPath } else { "" }
        Status = $status
        GateFailed = Test-Path -LiteralPath $markerPath -PathType Leaf
        MarkerPath = if (Test-Path -LiteralPath $markerPath -PathType Leaf) { $markerPath } else { "" }
        MarkerText = $markerText
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

function Test-HarnessLaunchMacroTruncated {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence -or -not $RunEvidence.Lab) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if ($text -notlike "*titleload-down160*") {
        return $false
    }
    if ($text -like "*titleload-down160-loadtarget-reproof*") {
        return $false
    }

    $tokenText = if ($RunEvidence.Lab.InputMacroTokens) { $RunEvidence.Lab.InputMacroTokens } else { "" }
    [int]$tokens = 0
    if ([int]::TryParse($tokenText, [ref]$tokens)) {
        return $tokens -lt 10
    }
    return $false
}

function Get-RunDecision {
    param([object]$RunEvidence)

    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return "failed-fatal-log"
    }
    if ($RunEvidence.LoadTarget -and $RunEvidence.LoadTarget.GateFailed) {
        return "failed-load-target-gate"
    }
    if (Test-HarnessLaunchMacroTruncated -RunEvidence $RunEvidence) {
        return "failed-harness-launch"
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
    if (Test-Hle25ccShadowDescOptionsProof -RunEvidence $RunEvidence) {
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

function Test-Hle25ccShadowDescOptionsProof {
    param([AllowNull()][object]$RunEvidence)

    if (-not $RunEvidence) {
        return $false
    }
    if ($RunEvidence.Fatal -and $RunEvidence.Fatal.HasFatal) {
        return $false
    }

    $label = if ($RunEvidence.Lab.Label) { $RunEvidence.Lab.Label } else { "" }
    $text = "$($RunEvidence.Name) $label"
    if ($text -notlike "*25cc*" -or
        $text -notlike "*shadow-desc*" -or
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

    # The title Options page is a valid menu proof, but the field-only visual
    # classifier records it as small non-field output.
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
        LoadTarget = Read-LoadTargetEvidence -Run $run
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
$truncatedMacroRuns = @($runEvidence | Where-Object { $_.Decision -eq "failed-harness-launch" })
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
$latestValidLoaderControlDiag200 = $false
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
$latestCleanHle25ccShadowField = $false
$latestHle25ccShadowDescDown160FieldPass = $false
$latestHle25ccShadowDescOptionsPass = $false
$latestHle25ccShadowDescBattleFatal = $false
$latestHle25ccShadowDescBattleStockLoading = $false
$latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit = $false
$latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck = $false
$latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass = $false
$latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate = $false
$latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass = $false
$latestHle25ccShadowDescBuildcheckRouteMiss = $false
$latestHle25ccShadowDescOptionsRouteMiss = $false
$latestHle25ccShadowDescOptionsNoCrossRouteMiss = $false
$latestHle25ccBodyBattleOptionsRouteMiss = $false
$latestHle25ccNoPauseBattleAbComplete = $false
$latestHle25ccBodyFastRsxGeomStackWindowLost = $false
$latestHle25ccBodyFastRsxGeometryOnlyPass = $false
$latestHle25ccBodyFastRsxResolveDepthPresentPass = $false
$latestHle25ccBodyFastRsxRdpVertexSupersetPass = $false
$latestHle25ccBodyFastRsxRdpVertexPersistentPass = $false
$latestHle25ccBodyFastRsxRdpIndexPersistentPass = $false
$latestHle25ccBodyFastRsxFinalStackAuditorPass = $false
$latestStateAwarePromptStuck = $false
$latestStateAwareSavePromptField = $false
$latestStateAwareDismissLoadMenuMiss = $false
$latestStateAwareLateLoadConfirmNeedsSecondCross = $false
$latestStateAwareLateDoubleConfirmRouteDrift = $false
$latestLoadTargetGateFailure = $false
$latestLoadTargetGateStatus = ""
$latestLoadTargetPollGatedSaveMenuAfterField = $false
$latestLoadTargetDirectLeftGateFailure = $false
$latestLoadTargetDirectLeftLongGateCutscene = $false
$latestTitleToLoadDiagnosticCutscene = $false
$latestTitleToLoadDownHoldWrongSaveTarget = $false
$latestTitleToLoadDownHoldClassifierFalseGateFailure = $false
$latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck = $false
$latestTitleToLoadDownHoldLoadStabilityNeedsDismiss = $false
$latestTitleToLoadDownHoldLateDismissNoMoveFieldPass = $false
$latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass = $false
$latestTitleToLoadDownHoldPostLoadCompleteSavePrompt = $false
$latestTitleToLoadDownHoldLoadTargetPass = $false
$latestTitleToLoadDownHoldDirectLeftFieldPass = $false
$latestTitleToLoadDownHoldBattleFatal = $false
$latestTitleToLoadDownHoldBattleLeftOnlyPass = $false
$latestTitleToLoadDownHoldBattleLeftOnlyFatal = $false
$latestTitleToLoadDownHoldLeftOnlyClassifierDrift = $false
$latestTitleToLoadDownHoldLoadTopNormalizeBlack = $false
$latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall = $false
$latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition = $false
$latestTitleToLoadDownHoldLoadTargetReproofPass = $false
$recentTitleToLoadDownHoldBattleFatal = @($runEvidence | Where-Object {
    $label = if ($_.Lab -and $_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    $_.Fatal -and
        $_.Fatal.HasFatal -and
        $text -like "*titleload-down160-firstbattle*"
}).Count -gt 0
$recentTitleToLoadDownHoldDirectLeftFieldPass = @($runEvidence | Where-Object {
    $label = if ($_.Lab -and $_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    $_.Decision -eq "valid-field-triage" -and
        $_.LoadTarget -and
        $_.LoadTarget.Status -eq "PATH_TO_TENUTO_PRESENT" -and
        $text -like "*titleload-down160-pollgated-directleft200*"
}).Count -gt 0
$recentHle25ccBodyFastRsxGeomStackWindowLost = @($runEvidence | Where-Object {
    $label = if ($_.Lab -and $_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    $_.Decision -eq "failed-window-lost-after-field" -and
        $text -like "*bodyfast*" -and
        $text -like "*rsx*" -and
        $text -like "*geomstack*" -and
        $text -like "*battle*"
}).Count -gt 0
$recentHle25ccBodyFastRsxGeometryOnlyPass = @($runEvidence | Where-Object {
    $label = if ($_.Lab -and $_.Lab.Label) { $_.Lab.Label } else { "" }
    $text = "$($_.Name) $label"
    $_.Decision -eq "valid-field-triage" -and
        $text -like "*bodyfast*" -and
        $text -like "*rsx*" -and
        $text -like "*geometryonly*" -and
        $text -like "*battle*"
}).Count -gt 0
$latestHle25ccBodyFastCpuStackComponent = $false
$latestHle25ccBodyFastCpuCandidate = $false
$latestHle25ccBodyFastCpuEvidence = ""
if ($latestRun) {
    $latestLabel = if ($latestRun.Lab.Label) { $latestRun.Lab.Label } else { "" }
    $latestText = "$($latestRun.Name) $latestLabel"
    $latestFatal = $latestRun.Fatal -and $latestRun.Fatal.HasFatal
    $latestLoadTargetGateFailure = $latestRun.LoadTarget -and $latestRun.LoadTarget.GateFailed
    $latestLoadTargetGateStatus = if ($latestRun.LoadTarget -and $latestRun.LoadTarget.Status) { $latestRun.LoadTarget.Status } else { "" }
    $latestLoadTargetPollGatedSaveMenuAfterField =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.Visual.Status -eq "FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*loadtarget-pollgated*" -and
        $latestText -like "*dismisssave*"
    $latestLoadTargetDirectLeftGateFailure =
        $latestLoadTargetGateFailure -and
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestText -like "*loadtarget-pollgated-directleft*"
    $latestLoadTargetDirectLeftLongGateCutscene =
        $latestLoadTargetDirectLeftGateFailure -and
        $latestText -like "*longgate*" -and
        (
            (Test-HarnessCutsceneOrNonFieldClass -Class $latestRun.Visual.PrimarySmallClass) -or
            ($latestRun.LoadTarget -and $latestRun.LoadTarget.MarkerText -match "wrong-state|cutscene")
        )
    $latestTitleToLoadDiagnosticCutscene =
        $latestLoadTargetGateFailure -and
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestText -like "*title-to-load-state-diagnostic*" -and
        (
            (Test-HarnessCutsceneOrNonFieldClass -Class $latestRun.Visual.PrimarySmallClass) -or
            ($latestRun.LoadTarget -and $latestRun.LoadTarget.MarkerText -match "wrong-state|cutscene")
        )
    $latestTitleToLoadDownHoldWrongSaveTarget =
        $latestLoadTargetGateFailure -and
        (@("DEBUG_SAVE_PROLOGUE_PRESENT", "MIXED_LOAD_TARGETS") -contains $latestLoadTargetGateStatus) -and
        (
            $latestText -like "*titleload-down160*" -or
            $latestText -like "*title-to-load-down160*"
        )
    $latestTitleToLoadDownHoldClassifierFalseGateFailure =
        $latestLoadTargetGateFailure -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160*" -and
        $latestText -like "*directleft200*"
    $latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck =
        (@("failed-visual-gate", "failed-loading-visual") -contains $latestRun.Decision) -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160*" -and
        $latestText -like "*directleft200*"
    $latestTitleToLoadDownHoldDirectLeftPersistentLoading =
        $latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck -and
        $latestRun.Visual.PrimarySmallClass -eq "loading-like-small-png"
    $latestTitleToLoadDownHoldLoadStabilityNeedsDismiss =
        (@("failed-wrong-window-or-other-visual", "failed-visual-gate") -contains $latestRun.Decision) -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-loadstability-nocross-nomove*"
    $latestTitleToLoadDownHoldLateDismissNoMoveFieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-lateloadcomplete-dismiss-nomove*"
    $latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-lateloadcomplete-dismiss-directleft200*"
    $latestTitleToLoadDownHoldPostLoadCompleteSavePrompt =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-postloadcomplete-dismiss-directleft200*"
    $latestTitleToLoadDownHoldLoadTargetPass =
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*title-to-load-down160-state-diagnostic*"
    $latestTitleToLoadDownHoldDirectLeftFieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-pollgated-directleft200*"
    $latestTitleToLoadDownHoldBattleFatal =
        $latestFatal -and
        $latestText -like "*titleload-down160-firstbattle*"
    $latestTitleToLoadDownHoldBattleLeftOnlyPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-firstbattle-leftonly*"
    $latestTitleToLoadDownHoldBattleLeftOnlyFatal =
        $latestFatal -and
        $latestText -like "*titleload-down160-firstbattle-leftonly*"
    $latestTitleToLoadDownHoldLeftOnlyClassifierDrift =
        $latestLoadTargetGateFailure -and
        (@("DEBUG_SAVE_PROLOGUE_PRESENT", "MIXED_LOAD_TARGETS") -contains $latestLoadTargetGateStatus) -and
        $latestText -like "*titleload-down160-lateloadcomplete-dismiss-firstbattle-leftonly*"
    $latestTitleToLoadDownHoldLoadTopNormalizeBlack =
        $latestLoadTargetGateFailure -and
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestText -like "*titleload-down160-loadtopnormalize*" -and
        $latestRun.Visual.PrimarySmallClass -eq "black-overlay-small-png"
    $latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall =
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestText -like "*titleload-down160-loadlist-cursor-diagnostic*" -and
        $latestRun.Decision -ne "valid-field-triage" -and
        $latestRun.Visual.PrimarySmallClass -ne "black-overlay-small-png"
    $latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition =
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestText -like "*titleload-down160-loadlist-cursor-diagnostic*" -and
        $latestRun.Decision -ne "valid-field-triage" -and
        $latestRun.Visual.PrimarySmallClass -eq "black-overlay-small-png"
    $latestTitleToLoadDownHoldLoadTargetReproofPass =
        $latestLoadTargetGateStatus -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*titleload-down160-loadtarget-reproof*"
    $latestCutsceneOrNonfield = (Test-HarnessCutsceneOrNonFieldClass -Class $latestRun.Visual.PrimarySmallClass) -and $latestRun.Decision -ne "valid-field-triage"
    $latestBlackOverlay = $latestRun.Visual.PrimarySmallClass -eq "black-overlay-small-png" -and $latestRun.Decision -ne "valid-field-triage"
    $latestStateAwarePromptStuck =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
        ($latestText -like "*stateaware-one-step*" -or $latestText -like "*state-aware-one-step*")
    $latestStateAwareSavePromptField =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*stateaware-damaged-confirm*" -and
        $latestText -notlike "*dismiss-save*"
    $latestStateAwareDismissLoadMenuMiss =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
        $latestText -like "*stateaware-damaged-confirm-dismiss-save*"
    $latestStateAwareLateLoadConfirmNeedsSecondCross =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
        $latestText -like "*stateaware-late-load-confirm*"
    $latestStateAwareLateDoubleConfirmRouteDrift =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
        $latestText -like "*stateaware-late-load-doubleconfirm*"
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
    $latestCleanHle25ccShadowField =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*25cc*" -and
        ($latestText -like "*shadow*" -or
        $latestText -like "*verify25ccshadow*" -or
        $latestText -like "*9e4000*")
    $latestHle25ccShadowDescDown160FieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*down160*" -and
        ($latestText -like "*latedismiss*" -or
        $latestText -like "*lateloadcomplete*") -and
        ($latestText -like "*directleft*" -or
        $latestText -like "*field*")
    $latestHle25ccShadowDescOptionsPass =
        $latestRun.Decision -eq "valid-options-triage" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        ($latestText -like "*options*" -or
        $latestText -like "*menu*")
    $latestHle25ccShadowDescBattleFatal =
        $latestFatal -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle*"
    $latestHle25ccShadowDescBattleStockLoading =
        (@("failed-visual-gate", "failed-loading-visual") -contains $latestRun.Decision) -and
        $latestRun.Visual.PrimarySmallClass -eq "loading-like-small-png" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-control*"
    $latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit =
        $latestRun.Decision -eq "failed-window-lost-after-field" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-down160-leftonly*" -and
        $latestRun.Lab -and
        $latestRun.Lab.ProcessExitedWindowLoss -gt 0
    $latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestRun.LoadTarget -and
        $latestRun.LoadTarget.Status -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestRun.Visual.PrimarySmallClass -eq "wrong-window-or-other-small-png" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-down160-left1200*"
    $latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestRun.LoadTarget -and
        $latestRun.LoadTarget.Status -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-down160-strongdismiss-nomove*"
    $latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate =
        $latestLoadTargetGateFailure -and
        $latestLoadTargetGateStatus -eq "UNKNOWN_LOAD_TARGET" -and
        $latestRun.Visual.PrimarySmallClass -eq "black-overlay-small-png" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-down160-strongdismiss-left1200*"
    $latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestRun.LoadTarget -and
        $latestRun.LoadTarget.Status -eq "PATH_TO_TENUTO_PRESENT" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*battle-stock-down160-strongdismiss-left1200*"
    $latestHle25ccShadowDescBuildcheckRouteMiss =
        $latestRun.Decision -eq "failed-visual-gate" -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        ($latestText -like "*buildcheck*" -or
        $latestText -like "*desc-field*")
    $latestHle25ccShadowDescOptionsNoCrossRouteMiss =
        $latestCutsceneOrNonfield -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        $latestText -like "*options-nocross*"
    $latestHle25ccShadowDescOptionsRouteMiss =
        $latestCutsceneOrNonfield -and
        $latestText -like "*25cc*" -and
        $latestText -like "*shadow-desc*" -and
        ($latestText -like "*options-proof*" -or
        $latestText -like "*options*")
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
    $latestHle25ccBodyFastRsxGeomStackWindowLost =
        $latestRun.Decision -eq "failed-window-lost-after-field" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*geomstack*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxGeometryOnlyPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*geometryonly*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxResolveDepthPresentPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*resolvedepthpresent*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxRdpVertexSupersetPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*rdp-vertexsuperset*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxRdpVertexPersistentPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*rdp-vertexpersistent*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxRdpIndexPersistentPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        $latestText -like "*rdp-indexpersistent*" -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastRsxFinalStackAuditorPass =
        $latestRun.Decision -eq "valid-field-triage" -and
        $latestText -like "*bodyfast*" -and
        $latestText -like "*rsx*" -and
        ($latestText -like "*finalstack-auditor*" -or
        ($latestText -like "*finalstack*" -and $latestText -like "*auditor*")) -and
        $latestText -like "*battle*"
    $latestHle25ccBodyFastSummaryPaths = @(
        (Join-Path $RunRoot "_eternal-sonata-25cc-bodyfast-repeat-battle-ab-latest.md"),
        (Join-Path $RunRoot "_eternal-sonata-25cc-bodyfast-battle-ab-latest.md")
    )
    $latestHle25ccBodyFastSummaryPath = $latestHle25ccBodyFastSummaryPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($latestText -like "*bodyfast*" -and $latestText -notlike "*rsx*" -and $latestHle25ccBodyFastSummaryPath) {
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
    $latestValidLoaderControlDiag200 =
        $latestValidLoaderControl -and
        ($latestRun.Name -like "*loader-control-left200x2-diag200*" -or $latestLabel -like "*loader-control-left200x2-diag200*")
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
        } elseif ($latestValidLoaderControlDiag200) {
            "Latest loader-control-left200x2-diag200 route already passed field triage; do not repeat it. Bank it as route tooling only, then pivot to a different proof axis before lane-2 HLE/GPU fast modes."
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
if ($cutsceneRuns.Count -ge 1 -and $latestRun.Decision -ne "valid-options-triage") {
    $cutsceneAction = if ($latestHle25ccShadowDescBattleFatal) {
        "The current blocker is the 0x25cc descriptor first-battle fatal, not the older Options/cutscene route misses. Ignore old loader-control fallback advice and isolate the same TopSlot battle route with Verify25ccShadow off."
    } elseif ($latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck) {
        "The current blocker is the stock Down160 left1200 load-complete popup miss, not the older Options/cutscene route misses. Keep the repaired Down160 base and prove a stronger no-movement dismiss before movement."
    } elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass) {
        "The newest useful proof is the stock Down160 strong-dismiss no-movement field boundary. Ignore older Options/cutscene route misses and add only ls_left:1200 on the same strong-dismiss base."
    } elseif ($latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit) {
        "The current blocker is the stock Down160 left-only process exit after clean field, not the older Options/cutscene route misses. Keep the repaired Down160 base and shrink the stock left movement."
    } elseif ($latestHle25ccShadowDescBattleStockLoading) {
        "The current blocker is the no-verifier TopSlot stock-control loading miss, not the older Options/cutscene route misses. Ignore old loader-control fallback advice and repair from the current Down160 late-load-complete base."
    } elseif ($latestTitleToLoadDownHoldClassifierFalseGateFailure) {
        "The newest blocker is a Down160 load-target classifier row-drift false gate. Keep the Down160 route and rerun the post-load-complete repair under the multi-row classifier before any old loader-control or speed work."
    } elseif ($latestHle25ccShadowDescOptionsNoCrossRouteMiss) {
        "The newest blocker is the no-initial-Cross 0x25cc descriptor Options route miss. It reached the title menu and Load, but the long second wait drifted into intro/title loop. Use the fast Down160 Options select route instead of repeating no-cross or backing off to field movement."
    } elseif ($latestHle25ccShadowDescOptionsRouteMiss) {
        "The newest blocker is the 0x25cc descriptor Options route miss. Do not back off to loader-control field movement; rerun the no-initial-Cross Options proof with explicit preinput/selection screenshots."
    } elseif ($latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition) {
        "The newest blocker is a Down160 load-list diagnostic black transition, not the older cutscene route. Re-prove the Down160 load-target gate with no cursor input before any old loader-control or speed work."
    } elseif ($latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall) {
        "The newest blocker is a Down160 load-list diagnostic timing miss, not the older cutscene route. Rerun the extended cursor diagnostic that waits through Checking save files before any old loader-control or speed work."
    } elseif ($latestTitleToLoadDownHoldLoadTopNormalizeBlack) {
        "The newest blocker is a Down160 load-top-normalize black gate. Ignore older cutscene/harness-noise frames and run the load-list cursor diagnostic before another left-only isolation."
    } elseif ($latestTitleToLoadDownHoldLeftOnlyClassifierDrift) {
        "The newest blocker is Down160 left-only load-list cursor/classifier drift. Ignore older cutscene/harness-noise frames and repair selected-row gating before another left-only isolation."
    } elseif ($latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass) {
        "The newest useful proof is a Down160 late-dismiss direct-left boundary that reached and stayed in clean field. Ignore older cutscene/harness-noise frames and isolate the larger left-only battle movement on the same late-dismiss base."
    } elseif ($latestTitleToLoadDownHoldLateDismissNoMoveFieldPass) {
        "The newest useful proof is a Down160 late load-complete dismiss that reached clean field with no movement. Ignore older cutscene/harness-noise frames and add only one direct-left movement pulse on the same late-dismiss base."
    } elseif ($latestTitleToLoadDownHoldLoadStabilityNeedsDismiss) {
        "The newest blocker is a Down160 no-movement load-complete-waits-for-dismiss state. Ignore older cutscene/harness-noise frames and run the delayed single-dismiss no-movement proof before any old loader-control or speed work."
    } elseif ($latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck) {
        "The newest blocker is a Down160 post-load-complete route miss. Keep the Down160 route and repair the load-complete dismissal before any old loader-control or speed work."
    } elseif ($latestTitleToLoadDownHoldWrongSaveTarget) {
        "The newest blocker is not the older cutscene route miss; it is a Down160 wrong-save-target gate. Restore or repair Path to Tenuto and verify PATH_TO_TENUTO_PRESENT before any route rerun."
    } elseif ($latestTitleToLoadDiagnosticCutscene -or $latestLoadTargetDirectLeftLongGateCutscene) {
        "Keep the title/load state-gated ladder. Do not back off to old loader-control movement or speed toggles."
    } elseif ($latestHle451cSize16BodyMenuRouteMiss) {
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
if ($truncatedMacroRuns.Count -ge 1) {
    Add-AntiPattern -List $antiPatterns -Name "truncated-input-macro" -Severity "harness-noise" -Evidence ("{0} recent run(s) launched a Down160 route label with too few input macro tokens." -f $truncatedMacroRuns.Count) -Action "Ignore these as harness launch noise. Re-run only with the full quoted macro and do not count their screenshots as field, speed, or route proof."
}
if ($latestStateAwarePromptStuck) {
    Add-AntiPattern -List $antiPatterns -Name "stateaware-load-confirm-prompt-stuck" -Severity "blocker" -Evidence "Newest state-aware one-step repair stayed on the load-confirm prompt instead of reaching field; screenshots show the damaged-save confirmation dialog, not a wrong window." -Action "Do not rerun the default field macro. Add an explicit post-prompt Cross confirm, delay screenshots until after the confirm, then re-test the one-left-pulse field route under CleanAfterField."
}
if ($latestStateAwareSavePromptField) {
    Add-AntiPattern -List $antiPatterns -Name "stateaware-save-prompt-field-not-moving" -Severity "route-repair" -Evidence "Newest damaged-save-confirm state-aware route reached field-like Path to Tenuto output, but manual screenshot review showed the save-point prompt over the field, so it is not moving gameplay proof." -Action "Do not fall back to the default state-aware command. Dismiss the save prompt, then capture the same one-left-pulse route under CleanAfterField before any speed or HLE/GPU promotion."
}
if ($latestStateAwareDismissLoadMenuMiss) {
    Add-AntiPattern -List $antiPatterns -Name "stateaware-dismiss-save-load-menu-miss" -Severity "blocker" -Evidence "Newest dismiss-save state-aware route never reached field; screenshots stayed on the Load/Proceed screen and then the Load list, despite clean host and fatal-clean logs." -Action "Do not rerun the old default or the dismiss-save macro. Treat this as a late load-confirm timing miss and use a late Yes-confirm repair before any save-prompt dismissal or movement proof."
}
if ($latestStateAwareLateLoadConfirmNeedsSecondCross) {
    Add-AntiPattern -List $antiPatterns -Name "stateaware-late-load-confirm-needs-second-cross" -Severity "blocker" -Evidence "Newest late load-confirm repair opened the Load data/Proceed prompt with Yes highlighted, but never sent the second Cross confirm, so every screenshot stayed on the Load UI." -Action "Do not rerun the one-cross late-confirm macro. Send a second Cross after the prompt appears, then capture field, dismiss the save prompt, and test the one-left-pulse route under CleanAfterField."
}
if ($latestLoadTargetGateFailure -and
    -not $latestTitleToLoadDownHoldClassifierFalseGateFailure -and
    -not $latestTitleToLoadDownHoldLeftOnlyClassifierDrift -and
    -not $latestTitleToLoadDownHoldLoadTopNormalizeBlack -and
    -not $latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate) {
    $statusText = if ([string]::IsNullOrWhiteSpace($latestLoadTargetGateStatus)) { "no classifier status" } else { $latestLoadTargetGateStatus }
    Add-AntiPattern -List $antiPatterns -Name "load-target-gate-failed-before-slot-cross" -Severity "blocker" -Evidence "Newest load-target-gated route aborted before pressing Cross on the save slot; classifier status was $statusText." -Action "Do not run HLE/RSX speed experiments until the gate reports PATH_TO_TENUTO_PRESENT. Use only the polling load-target-gated route; if it times out as UNKNOWN_LOAD_TARGET, inspect the save-check screen or checkpoint state instead of stacking speed toggles."
}
if ($latestLoadTargetPollGatedSaveMenuAfterField) {
    Add-AntiPattern -List $antiPatterns -Name "pollgated-route-opens-save-menu-after-field" -Severity "blocker" -Evidence "Newest polling-gated route proved Path to Tenuto and reached field, but later screenshots stayed on the Save/Create new save file menu after the post-load dismissal presses." -Action "Remove the obsolete field-side save-prompt dismissal sequence. After the accepted field screenshot, go directly to the movement pulse and screenshots."
}
if ($latestLoadTargetDirectLeftLongGateCutscene) {
    Add-AntiPattern -List $antiPatterns -Name "directleft-longgate-entered-cutscene" -Severity "blocker" -Evidence "Newest long-gate direct-left route stayed UNKNOWN_LOAD_TARGET while screenshots showed story/cutscene frames, not the Load list or Path to Tenuto field." -Action "Stop longer-gate reruns. Run the title-to-Load diagnostic: screenshot title settle, after title Down, after title Cross, before the Load-target gate, then abort unless PATH_TO_TENUTO_PRESENT."
}
if ($latestTitleToLoadDiagnosticCutscene) {
    Add-AntiPattern -List $antiPatterns -Name "title-to-load-diagnostic-entered-newgame" -Severity "blocker" -Evidence "Newest title-to-Load diagnostic stayed on the title screen after the short Down press, then Cross entered New Game/story cutscene instead of the Load list." -Action "Do not fall back to double-confirm or long-gate routes. Use the down160 title-to-Load diagnostic to prove Load selection before any save-slot Cross."
}
if ($latestTitleToLoadDownHoldWrongSaveTarget) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-wrong-save-target" -Severity "blocker" -Evidence "Newest Down160 title/load route selected $latestLoadTargetGateStatus instead of PATH_TO_TENUTO_PRESENT, so the live gate aborted before save-slot Cross." -Action "Do not fall back to generic state-aware, old loader-control, or blind double-confirm macros. Restore or repair the Path-to-Tenuto save target, verify the gate reports PATH_TO_TENUTO_PRESENT, then re-run the Down160 direct-left boundary proof."
}
if ($latestTitleToLoadDownHoldClassifierFalseGateFailure) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-load-target-classifier-row-drift" -Severity "route-repair" -Evidence "Newest Down160 post-load-complete route has a live gate-failed marker, but the corrected multi-row classifier now reports PATH_TO_TENUTO_PRESENT on the lower selected Path-to-Tenuto row." -Action "Do not fall back to generic state-aware or old loader-control macros. Re-run the same Down160 post-load-complete dismiss direct-left repair under the multi-row classifier."
}
if ($latestTitleToLoadDownHoldDirectLeftPersistentLoading) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-path-target-loading-only" -Severity "blocker" -Evidence "Newest plain Down160 direct-left route removed the save-prompt Cross and still stayed on Now Loading through late screenshots despite PATH_TO_TENUTO_PRESENT." -Action "Do not fall back to generic state-aware routes or repeat the save-prompt-opening repair. Run the Down160 no-movement load-stability diagnostic to separate persistent loading from movement/prompt timing before any speed/HLE/RSX work."
}
if ($latestTitleToLoadDownHoldLoadStabilityNeedsDismiss) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-load-complete-waits-for-dismiss" -Severity "route-repair" -Evidence "Newest Down160 no-movement load-stability diagnostic passed PATH_TO_TENUTO_PRESENT, then stayed on the Load UI with the Load complete banner through late checkpoints." -Action "Do not fall back to generic state-aware routes or add movement. Send exactly one delayed post-load-complete Cross, then capture no-movement field proof before any direct-left, first-battle, HLE, RSX, GPU, or speed work."
}
if ($latestTitleToLoadDownHoldLateDismissNoMoveFieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-late-dismiss-field-clean" -Severity "resolved-control" -Evidence ("Newest Down160 delayed single-dismiss route reached Path-to-Tenuto field at {0}s without opening the save prompt or adding movement." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep this late-dismiss route base and add only one direct-left movement pulse next. Do not fall back to generic state-aware, old loader-control, first-battle, HLE, RSX, GPU, or speed work yet."
}
if ($latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-late-dismiss-directleft-field-clean" -Severity "resolved-control" -Evidence ("Newest Down160 delayed single-dismiss direct-left route reached Path-to-Tenuto field at {0}s and stayed field-clean after the left200 pulse." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep this late-dismiss route base. Run only the left-only first-battle movement isolation next; do not fall back to generic state-aware, old loader-control, full battle, HLE, RSX, GPU, or speed work yet."
}
if ($latestTitleToLoadDownHoldLeftOnlyClassifierDrift) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-leftonly-load-list-cursor-drift" -Severity "route-repair" -Evidence "Newest Down160 late-dismiss left-only isolation aborted before slot Cross after the load-target classifier latched onto damaged/debug-like upper rows while manual screenshot review showed a lower Path-to-Tenuto row visible." -Action "Do not restore the already-matching checkpoint, fall back to generic state-aware, or stack HLE/RSX/GPU work. Run a load-list cursor diagnostic or selected-row-aware classifier repair before another left-only isolation."
}
if ($latestTitleToLoadDownHoldLoadTopNormalizeBlack) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-loadtopnormalize-black-gate" -Severity "harness-noise" -Evidence "Newest load-top-normalize repair sent pre-gate Up taps and then only captured black-overlay load-target frames, so it did not prove the save target or route." -Action "Do not repeat blind pre-gate Up normalization. Run the load-list cursor diagnostic to screenshot the Load list before/after controlled cursor movement, then update the classifier or macro from that evidence."
}
if ($latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-loadlist-diagnostic-save-check-stall" -Severity "route-repair" -Evidence "Newest Down160 load-list cursor diagnostic captured the Checking save files dialog for every supposed load-list cursor screenshot, so Up/Down was sent before the Load list was visible." -Action "Do not fall back to generic state-aware or old loader-control macros. Rerun the extended cursor diagnostic that waits through the save-check transition before controlled cursor movement."
}
if ($latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-loadlist-diagnostic-black-transition" -Severity "route-repair" -Evidence "Newest Down160 load-list cursor diagnostic selected LOAD, then captured only black/perf-overlay frames through the 45s load-list wait and cursor taps." -Action "Do not keep extending the cursor diagnostic and do not fall back to generic state-aware macros. Re-prove the Down160 load-target gate with no cursor input before another cursor or movement repair."
}
if ($latestTitleToLoadDownHoldLoadTargetReproofPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-loadtarget-reproof-passed" -Severity "resolved-control" -Evidence "Newest no-cursor Down160 reproof selected LOAD and the live load-target gate eventually reported PATH_TO_TENUTO_PRESENT." -Action "Treat this as route target repair only, not field or speed proof. Resume the late-dismiss left-only first-battle movement isolation instead of falling back to generic loader-control."
}
if ($latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck -and -not $latestTitleToLoadDownHoldDirectLeftPersistentLoading) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-path-target-no-field" -Severity "route-repair" -Evidence "Newest Down160 direct-left-shaped route has PATH_TO_TENUTO_PRESENT but failed the field visual gate. The preceding manual screenshot review showed the Load UI with a Load complete popup, and the latest live gate needed the multi-row target classifier." -Action "Do not fall back to generic state-aware or old loader-control macros. Keep the Down160 route and use the post-load-complete Cross repair before the field and movement screenshots."
}
if ($latestTitleToLoadDownHoldPostLoadCompleteSavePrompt) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-postloadcomplete-cross-opens-save-prompt" -Severity "route-repair" -Evidence "Newest Down160 post-load-complete repair reached Path-to-Tenuto field, but manual screenshot review showed the extra post-field Cross opened the Save game prompt before the left movement proof." -Action "Do not treat this as moving gameplay and do not use generic valid-field fallback. Remove the extra post-load-complete Cross and rerun the plain Down160 load-target-gated direct-left route."
}
if ($latestTitleToLoadDownHoldLoadTargetPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-target-proven-no-field-yet" -Severity "route-repair" -Evidence "Newest down160 title-to-Load diagnostic reached PATH_TO_TENUTO_PRESENT but intentionally stopped before pressing the save slot, so it is not field or moving gameplay proof." -Action "Continue only with the down160 load-target-gated direct-left route. Keep HLE/RSX speed work blocked until field movement is valid."
}
if ($latestTitleToLoadDownHoldDirectLeftFieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-field-route-proven" -Severity "resolved-control" -Evidence ("Newest down160 load-target-gated route reached Path to Tenuto, accepted field at {0}s, and kept field-like screenshots after the direct-left movement pulse." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not fall back to generic state-aware one-step or old loader-control macros. Use the down160 route base for first-battle proof; keep speed/HLE/RSX promotion blocked until field, menu/Options, and first-battle visuals all pass."
}
if ($latestTitleToLoadDownHoldBattleFatal) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-firstbattle-fatal" -Severity "blocker" -Evidence "Newest Down160 first-battle route reached accepted field, then the movement branch produced likely-crashed overlay/corrupt field visuals and a PPU access violation." -Action "Do not fall back to generic loader-control or speed/HLE/RSX promotion. Re-prove the last clean Down160 direct-left boundary, then shrink or state-gate the battle movement leg before another first-battle attempt."
}
if ($latestTitleToLoadDownHoldDirectLeftFieldPass -and $recentTitleToLoadDownHoldBattleFatal) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-boundary-reproved-after-battle-fatal" -Severity "route-repair" -Evidence "Newest Down160 direct-left field boundary is clean while a recent Down160 first-battle extension crashed after a larger movement branch." -Action "Do not repeat the full first-battle movement branch. Run the Down160 left-only diagnostic to isolate whether `ls_left:2600` is safe before adding down-left movement."
}
if ($latestTitleToLoadDownHoldBattleLeftOnlyPass) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-leftonly-clean" -Severity "resolved-control" -Evidence ("Newest Down160 left-only first-battle diagnostic reached field at {0}s and survived the `ls_left:2600` branch without fatal evidence." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep the Down160 route base. Add only a smaller/state-gated down-left leg next; do not jump back to the full crashing `down-left:2200` branch."
}
if ($latestTitleToLoadDownHoldBattleLeftOnlyFatal) {
    Add-AntiPattern -List $antiPatterns -Name "titleload-down160-leftonly-fatal" -Severity "blocker" -Evidence "Newest Down160 left-only first-battle diagnostic crashed, so the left-only movement branch is already too large or unsafe." -Action "Back off to the clean Down160 direct-left boundary and shrink the left movement before any down-left or first-battle attempt."
}
if ($latestLoadTargetDirectLeftGateFailure -and -not $latestLoadTargetDirectLeftLongGateCutscene) {
    Add-AntiPattern -List $antiPatterns -Name "directleft-load-target-gate-timeout" -Severity "blocker" -Evidence "Newest direct-left route aborted before slot Cross because all polling-gate screenshots stayed UNKNOWN_LOAD_TARGET; manual visual inspection showed a black screen, not a save slot." -Action "Retry only the direct-left route with a longer load-target gate. Do not fall back to the old dismiss-save macro because it already proved it opens the Save menu after field."
}
if ($latestStateAwareLateDoubleConfirmRouteDrift) {
    Add-AntiPattern -List $antiPatterns -Name "stateaware-late-doubleconfirm-wrong-save-target" -Severity "blocker" -Evidence "Newest late double-confirm route still missed field, and manual screenshots showed the Load list on Debug Save / Prologue instead of the known Path to Tenuto save target." -Action "Do not rerun blind state-aware load macros. Use only the load-target-gated diagnostic; it screenshots, runs tools\classify_eternal_sonata_load_target.ps1, and aborts before Cross unless the gate reports PATH_TO_TENUTO_PRESENT."
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
    } elseif ($latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck) {
        "A recent 0x25cc descriptor verifier battle run fataled, but the newest stock Down160 left1200 run stayed on the Load complete popup. Repair the dismiss step before any verifier or movement retry."
    } elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass) {
        "A recent 0x25cc descriptor verifier battle run fataled, but the newest stock Down160 strong-dismiss no-movement route is field-clean. Keep that boundary and add only ls_left:1200 before any verifier retry."
    } elseif ($latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit) {
        "A recent 0x25cc descriptor verifier battle run fataled, but the newest stock Down160 route now reaches field and exits only after ls_left:2600. Shrink stock left movement on the repaired Down160 base before any verifier retry."
    } elseif ($latestHle25ccShadowDescBattleStockLoading) {
        "A recent 0x25cc descriptor verifier battle run fataled, and the newest no-verifier stock-control route stayed on Now Loading. Do not retry either unchanged; repair the battle route from the Down160 late-load-complete base first."
    } elseif ($latestHle25ccShadowDescBattleFatal) {
        "Latest 0x25cc descriptor first-battle Verify25ccShadow run fataled after field/battle visuals. Do not rerun it unchanged or reset to loader-control; isolate the same TopSlot battle route with Verify25ccShadow off first."
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
if ($latestCleanHle25ccShadowField -and -not $latestHle25ccShadowDescDown160FieldPass -and -not $latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass -and -not $latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-pattern-gap" -Severity "direction" -Evidence ("Newest 0x25cc shadow verifier reached field at {0}s, but exact command-level EA buckets cover only a small slice of the max-DMA pattern family and the current shadow/body path is GET-only." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not rerun generic movement or exact-EA 0x9e4000 skips. Add pattern/descriptor-level payload or LS-range hashing split by GET/PUT direction for the top max-DMA groups before fast/body promotion."
}
if ($latestHle25ccShadowDescDown160FieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-down160-field-clean" -Severity "resolved-control" -Evidence ("Newest 0x25cc descriptor Down160 field proof reached Path-to-Tenuto field at {0}s with the widened descriptor table, PUT/GET descriptor coverage, zero mismatches, and descriptor overflow 0." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not rerun the 0x25cc descriptor field proof. Prove title Options/menu with Verify25ccShadow next, then first battle, before bodyfast, stack, GPU, or speed promotion."
}
if ($latestHle25ccShadowDescOptionsPass) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-options-clean" -Severity "resolved-control" -Evidence "Newest 0x25cc descriptor fast-select Options proof reached the full title Options page with expected small menu screenshots, fatal-clean logs, zero target 0x25cc shadow/descriptor mismatches, and descriptor overflow 0." -Action "Do not rerun field or Options. Prove first battle with Verify25ccShadow next before bodyfast, stack, GPU, or speed promotion."
}
if ($latestHle25ccShadowDescBattleFatal) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-fatal" -Severity "blocker" -Evidence "Newest 0x25cc descriptor first-battle Verify25ccShadow run reached field and battle/tutorial visuals, but fataled with a PPU VM access violation at 0x002aedd0 reading 0x40; late screenshots are frozen/corrupt and cannot count as first-battle proof." -Action "Do not rerun the same TopSlot verifier command and do not fall back to old loader-control. Isolate the same TopSlot battle route with Verify25ccShadow off, or repair/state-gate the battle macro before another verifier proof."
}
if ($latestHle25ccShadowDescBattleStockLoading) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-loading" -Severity "route-repair" -Evidence "Newest no-Verify25ccShadow TopSlot stock-control battle isolation stayed on Now Loading for every screenshot, with clean host/fatal logs and no field or battle visuals." -Action "Do not treat this as a verifier-only fatal and do not fall back to generic field movement. Repair the battle route from the current Down160 late-load-complete base with a stock left-only diagnostic before any verifier retry."
}
if ($latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-down160-left1200-load-complete-stuck" -Severity "route-repair" -Evidence "Newest stock Down160 left1200 diagnostic proved PATH_TO_TENUTO_PRESENT, but all post-load and post-left screenshots stayed on the Load UI with the Load complete popup until max wall-time." -Action "Do not count the left1200 input as movement and do not fall back to generic loader-control. Keep the Down160 base and run a stronger no-movement post-load-complete dismiss diagnostic before any verifier or movement retry."
}
if ($latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-field-clean" -Severity "resolved-control" -Evidence ("Newest stock Down160 strong-dismiss no-movement diagnostic reached Path-to-Tenuto field at {0}s and stayed field-clean through the late checkpoint." -f $latestRun.Visual.FirstFieldSeconds) -Action "Keep the strong-dismiss Down160 base and add only ls_left:1200 next. Do not fall back to generic 0x25cc pattern-gap advice, verifier retry, full battle, HLE, RSX, GPU, or speed work yet."
}
if ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-black-gate" -Severity "route-repair" -Evidence "Newest stock Down160 strong-dismiss left1200 attempt aborted before save-slot Cross because every load-target polling frame was a black overlay with UNKNOWN_LOAD_TARGET." -Action "Treat this as pre-slot gate noise, not a movement or save-target failure. Keep the strong-dismiss base and rerun the same left1200 shape with a longer load-target gate before verifier, battle, HLE, RSX, GPU, or speed work."
}
if ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-down160-strongdismiss-left1200-field-clean" -Severity "resolved-control" -Evidence ("Newest stock Down160 strong-dismiss left1200 long-gate diagnostic reached Path-to-Tenuto field at {0}s, accepted the left1200 pulse, and stayed field-clean through late screenshots." -f $latestRun.Visual.FirstFieldSeconds) -Action "Bank this as a route/movement boundary only, not speed or GPU migration. Keep the strong-dismiss long-gate base and try the left1800 midpoint before verifier, full battle, HLE, RSX, GPU, or speed promotion."
}
if ($latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-battle-stock-down160-leftonly-process-exit" -Severity "route-repair" -Evidence "Newest stock Down160 left-only diagnostic proved Path-to-Tenuto field, then RPCS3 exited after the ls_left:2600 movement before left-check screenshots." -Action "Keep the repaired classifier and Down160 load-complete base. Shrink the stock left-only movement to ls_left:1200 with an immediate post-movement screenshot before any verifier or full first-battle retry."
}
if ($latestHle25ccShadowDescBuildcheckRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-buildcheck-route-miss" -Severity "blocker" -Evidence "Newest 0x25cc descriptor buildcheck proved nonzero PUT shadow coverage but stayed in the Load menu and used the stale down:20/up macro." -Action "Do not fall back to generic state-aware or old loader-control movement. Use the widened descriptor table with the current Down160 late-dismiss direct-left route, then require clean field visuals, PUT descriptor rows, zero mismatches, and descriptor overflow 0."
}
if ($latestHle25ccShadowDescOptionsNoCrossRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-options-nocross-wait-drift" -Severity "blocker" -Evidence "Newest no-initial-Cross 0x25cc descriptor Options proof reached the title menu and selected Load, but the long post-second-Down wait drifted into intro/title-loop frames before Options opened." -Action "Do not repeat the same no-cross route and do not back off to loader-control field movement. Use the fast Down160 Options-select proof with short waits and explicit selection screenshots."
}
if ($latestHle25ccShadowDescOptionsRouteMiss -and -not $latestHle25ccShadowDescOptionsNoCrossRouteMiss) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-shadow-desc-options-initial-cross-cutscene-route-miss" -Severity "blocker" -Evidence "Newest 0x25cc descriptor Options proof used the repaired old menu macro, but the initial Cross selected New Game/story instead of opening title Options." -Action "Do not back off to loader-control field movement. Re-run the 0x25cc descriptor Options proof with the no-initial-Cross title route and explicit preinput/selection screenshots."
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
if ($latestHle25ccBodyFastRsxFinalStackAuditorPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-finalstack-auditor-complete" -Severity "direction" -Evidence "Newest bodyfast plus exact RSX final-stack auditor/accounting run reached field and active first battle, quantified large RSX-local residency/cache credit, and still showed zero promoted CPU/SPU-to-GPU replacement bytes with capped 120 FPS." -Action "Do not rerun the auditor and do not add more RSX cache toggles. If staying RSX, change source-read/fill architecture; otherwise pivot to SPU/PPU/codegen speed proof."
}
elseif ($latestHle25ccBodyFastRsxRdpIndexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-rdp-indexpersistent-interaction-passed" -Severity "resolved-bisect" -Evidence "Newest bodyfast plus RSX resolve/depth/present plus VertexSuperset plus VertexPersistent plus IndexPersistent final recombine reached field and active first battle after the earlier full bodyfast plus RSX geometry/locality stack lost the window." -Action "Treat the full RSX locality stack as visually compatible on this route, but not a speed win and not new CPU/SPU GPU migration. Do not keep stacking RSX toggles; next run, if needed, should be an auditor/accounting proof for this exact stack or a fresh non-RSX speed lane."
}
elseif ($latestHle25ccBodyFastRsxRdpVertexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-rdp-vertexpersistent-interaction-passed" -Severity "resolved-bisect" -Evidence "Newest bodyfast plus RSX resolve/depth/present plus VertexSuperset plus VertexPersistent interaction step reached field and active first battle after the full bodyfast plus RSX geometry/locality stack previously lost the window." -Action "Keep resolve/depth/present plus VertexSuperset plus VertexPersistent provisionally compatible. Continue the interaction ladder by adding IndexPersistent as the final isolated recombine step."
}
elseif ($latestHle25ccBodyFastRsxRdpVertexSupersetPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-rdp-vertexsuperset-interaction-passed" -Severity "resolved-bisect" -Evidence "Newest bodyfast plus RSX resolve/depth/present plus VertexSuperset interaction step reached field and active first battle after the full bodyfast plus RSX geometry/locality stack previously lost the window." -Action "Keep resolve/depth/present plus VertexSuperset provisionally compatible. Continue the interaction ladder by adding VertexPersistent next while keeping IndexPersistent off."
}
elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-subsets-pass-full-stack-fails" -Severity "interaction-bisect" -Evidence "Newest bodyfast plus RSX resolve/depth/present-only bisection reached field and active first battle after geometry-only also passed, while the full bodyfast plus RSX geometry/locality stack previously lost the window." -Action "Do not resurrect the failed full stack. Isolate the cross-family interaction by adding one geometry family to the resolve/depth/present subset, starting with VertexSuperset only; keep persistent vertex and index caches off."
}
elseif ($latestHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-geometryonly-bisect-passed" -Severity "resolved-bisect" -Evidence "Newest bodyfast plus RSX geometry-only vertex/index cache bisection reached field and active first battle after the prior full bodyfast plus RSX geometry/locality stack lost the window." -Action "Do not resurrect the failed full stack. Test the complementary resolve/depth/present-only subset next; if it passes, the failure is an interaction, and if it fails, split that subset."
}
elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-resolvedepthpresent-bisect-passed" -Severity "resolved-bisect" -Evidence "Newest bodyfast plus RSX resolve/depth/present-only bisection reached field and active first battle after the prior full bodyfast plus RSX geometry/locality stack lost the window." -Action "Do not resurrect the failed full stack. Test the complementary geometry-only subset next unless a recent clean geometry-only proof already exists."
}
elseif ($latestHle25ccBodyFastRsxGeomStackWindowLost) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-rsx-geomstack-window-lost" -Severity "blocker" -Evidence "Newest bodyfast plus RSX geometry/locality stack reached field/tutorial but lost the game window before the required late field and active first-battle screenshots." -Action "Do not rerun the same combined stack and do not add another candidate. Bisect the stack from the known-good bodyfast-only proof, starting with bodyfast plus geometry-only vertex/index caches."
}
elseif ($latestHle25ccBodyFastCpuStackComponent) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-cpu-load-stack-component" -Severity "resolved-control" -Evidence ("Newest 0x25cc bodyfast BattleRoute repeat is field/battle clean, fatal-clean, and has clean external host samples; {0}. FPS remains capped, so this is a CPU-pressure component only." -f $latestHle25ccBodyFastCpuEvidence) -Action "Stack bodyfast with the existing verified RSX geometry/locality credit stack in a combined Windows proof. Do not count bodyfast as FPS or GPU migration, and do not rerun bodyfast alone unless the stack regresses."
}
elseif ($latestHle25ccBodyFastCpuCandidate) {
    Add-AntiPattern -List $antiPatterns -Name "hle-25cc-bodyfast-cpu-load-candidate" -Severity "direction" -Evidence ("Newest 0x25cc bodyfast BattleRoute removed verifier/family/shadow timing overhead and held capped first-battle FPS; {0}. The body run still had postrun host-gate noise, so this is not banked." -f $latestHle25ccBodyFastCpuEvidence) -Action "Do not return to verifier-overhead removal. Repeat one clean bodyfast BattleRoute or run a fresh stock/bodyfast pair to confirm CPU-load reduction, then pivot to a larger 0x451c/codegen body if the gain remains capped."
}
if ($latestHle451cPreserveBodyOffBattleTopslotLeftOnlyProcessExit) {
    Add-AntiPattern -List $antiPatterns -Name "hle-451c-preserve-body-off-battle-topslot-leftonly-exit" -Severity "blocker" -Evidence ("Newest preserve-body-off top-slot left-only diagnostic reached accepted field at {0}s, then RPCS3 exited after the left-only movement branch." -f $latestRun.Visual.FirstFieldSeconds) -Action "Do not fall back to the old non-top-slot no-post diagnostic. Top-slot no-post already stayed alive; shrink or repair the left-only movement branch before diagonal or preserve-body-on battle work."
}

$nextAction = if ($latestStateAwarePromptStuck) {
    "Latest state-aware one-step repair reached the load-confirm prompt and never accepted field. Do not rerun the default field macro; use the damaged-save-confirm variant with an extra Cross after the prompt and delayed screenshots."
} elseif ($latestStateAwareSavePromptField) {
    "Latest damaged-save-confirm route repaired the load-confirm failure and reached field-like output, but it is parked on the save prompt. Dismiss the save prompt and re-test the same one-left-pulse field route before any broader battle or speed proof."
} elseif ($latestStateAwareDismissLoadMenuMiss) {
    "Latest dismiss-save route missed field entirely and stayed in the Load screen/Proceed state. Do not rerun the default or dismiss-save macros; use a late load-confirm Yes repair, then prove field before any save-prompt dismissal or speed work."
} elseif ($latestStateAwareLateLoadConfirmNeedsSecondCross) {
    "Latest late load-confirm route opened the Proceed prompt but did not send the second Cross confirm. Do not rerun the one-cross macro; use the double-confirm plus save-prompt dismissal route before any speed work."
} elseif ($latestLoadTargetPollGatedSaveMenuAfterField) {
    "Latest polling-gated route proved Path to Tenuto and field, then the old save-prompt dismissal opened the Save/Create-new-file menu. Remove those field-side Cross presses and go directly to a left-movement proof."
} elseif ($latestLoadTargetDirectLeftLongGateCutscene) {
    "Latest long-gate direct-left route entered story/cutscene frames while the load-target classifier stayed UNKNOWN_LOAD_TARGET. Run the title-to-Load diagnostic next; it screenshots each title/menu/load-list transition and stops before slot Cross unless PATH_TO_TENUTO_PRESENT."
} elseif ($latestTitleToLoadDiagnosticCutscene) {
    "Latest title-to-Load diagnostic proved the short title Down press did not reach Load; Cross entered New Game/story cutscene. Run the down160 title-selection diagnostic next and keep all speed/HLE/RSX work blocked."
} elseif ($latestTitleToLoadDownHoldClassifierFalseGateFailure) {
    "Latest Down160 post-load-complete repair aborted on a stale fixed-row live gate, but the corrected multi-row classifier now reports PATH_TO_TENUTO_PRESENT on the lower selected row. Treat it as classifier row drift and rerun the same Down160 post-load-complete dismiss route before any speed/HLE/RSX work."
} elseif ($latestTitleToLoadDownHoldPostLoadCompleteSavePrompt) {
    "Latest Down160 post-load-complete repair reached field, but the extra post-field Cross opened the Save game prompt and blocked movement. Remove that Cross and rerun the plain Down160 load-target-gated direct-left route before any speed/HLE/RSX work."
} elseif ($latestTitleToLoadDownHoldDirectLeftPersistentLoading) {
    "Latest plain Down160 direct-left route removed the save-prompt Cross but stayed on Now Loading through late screenshots. Do not use the generic state-aware fallback or repeat the prompt route; run a Down160 no-movement load-stability diagnostic first."
} elseif ($latestTitleToLoadDownHoldLoadStabilityNeedsDismiss) {
    "Latest Down160 no-movement diagnostic proved the Path-to-Tenuto load target but stayed on the Load complete banner. Send one delayed post-load-complete Cross and capture no-movement field proof before any movement, battle, HLE, RSX, GPU, or speed work."
} elseif ($latestTitleToLoadDownHoldLoadTopNormalizeBlack) {
    "Latest Down160 load-top-normalize repair black-overlayed before proving a load target. Do not repeat blind Up normalization or fall back to generic state-aware macros; run a load-list cursor diagnostic and repair selected-row load-target gating before another left-only isolation."
} elseif ($latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition) {
    "Latest Down160 load-list cursor diagnostic selected Load but then black-overlayed through the extended wait and cursor taps. Re-prove the Down160 load-target gate with no cursor input before any cursor, movement, speed, HLE, or RSX work."
} elseif ($latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall) {
    "Latest Down160 load-list cursor diagnostic sent cursor input while the game was still on Checking save files. Rerun the extended diagnostic that waits for the Load list before Up/Down; this is route timing, not speed or GPU work."
} elseif ($latestTitleToLoadDownHoldLoadTargetReproofPass) {
    "Latest no-cursor Down160 reproof selected Load and proved PATH_TO_TENUTO_PRESENT again. Resume only the late-dismiss left-only first-battle movement isolation before any cursor, full battle, HLE, RSX, GPU, or speed work."
} elseif ($latestTitleToLoadDownHoldLeftOnlyClassifierDrift) {
    "Latest Down160 late-dismiss left-only isolation has load-list cursor/classifier drift: a lower Path-to-Tenuto row was visible, but the gate aborted on damaged/debug-like upper rows. Repair the load-list cursor diagnostic or selected-row classifier before rerunning left-only movement."
} elseif ($latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass) {
    "Latest Down160 delayed single-dismiss direct-left route proved Path to Tenuto field and stayed field-clean after the left200 pulse. Run only the same late-dismiss base with a left-only first-battle movement isolation before full battle, HLE, RSX, GPU, or speed work."
} elseif ($latestTitleToLoadDownHoldLateDismissNoMoveFieldPass) {
    "Latest Down160 delayed single-dismiss no-movement route proved Path to Tenuto field without opening the save prompt. Add only one direct-left movement pulse on the same late-dismiss base before first-battle, HLE, RSX, GPU, or speed work."
} elseif ($latestTitleToLoadDownHoldLoadTargetPass) {
    "Latest down160 title-to-Load diagnostic proved PATH_TO_TENUTO_PRESENT and intentionally stopped before slot Cross. Continue with the down160 load-target-gated direct-left route; this is still route repair, not speed."
} elseif ($latestTitleToLoadDownHoldBattleLeftOnlyFatal) {
    "Latest Down160 left-only first-battle diagnostic crashed, so even the left-only movement branch is unsafe. Back off to the clean Down160 direct-left boundary and shrink the left movement before any down-left attempt."
} elseif ($latestTitleToLoadDownHoldBattleLeftOnlyPass) {
    "Latest Down160 left-only diagnostic survived the larger left movement. Add only a smaller/state-gated down-left leg next; do not repeat the full crashing first-battle movement."
} elseif ($latestTitleToLoadDownHoldDirectLeftFieldPass -and $recentTitleToLoadDownHoldBattleFatal) {
    "Latest Down160 direct-left boundary is clean after a recent first-battle crash. Isolate the battle movement with a left-only diagnostic before any down-left movement."
} elseif ($latestTitleToLoadDownHoldDirectLeftFieldPass) {
    "Latest down160 load-target-gated route proved Path to Tenuto field plus direct-left movement. Use that route base for first-battle proof next; title Options is still separately required before any 200% or speed promotion."
} elseif ($latestTitleToLoadDownHoldBattleFatal -and $recentTitleToLoadDownHoldDirectLeftFieldPass) {
    "Latest Down160 first-battle route crashed after accepted field and movement. Re-prove the last clean Down160 direct-left boundary, then shrink or state-gate the battle movement branch before another first-battle attempt."
} elseif ($latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck) {
    "Latest Down160 direct-left-shaped route has Path-to-Tenuto target evidence but no field proof. Keep the Down160 route and run the post-load-complete Cross repair under the multi-row load-target classifier."
} elseif ($latestTitleToLoadDownHoldWrongSaveTarget) {
    "Latest Down160 title/load route selected $latestLoadTargetGateStatus, not Path to Tenuto. Stop route retries, restore or repair the save target, and require PATH_TO_TENUTO_PRESENT before re-running the Down160 direct-left boundary."
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate) {
    "Latest stock Down160 strong-dismiss left1200 attempt aborted before slot Cross on black-overlay UNKNOWN_LOAD_TARGET gate frames. Treat it as pre-slot gate noise, not movement failure; rerun the same strong-dismiss left1200 shape with a longer load-target gate."
} elseif ($latestLoadTargetDirectLeftGateFailure) {
    "Latest direct-left route never reached a classifiable load slot; the load-target gate saw UNKNOWN_LOAD_TARGET black-screen captures through timeout. Retry only direct-left with a longer gate, not the obsolete dismiss-save sequence."
} elseif ($latestLoadTargetGateFailure) {
    "Latest load-target gate aborted before save-slot Cross with status $latestLoadTargetGateStatus. Do not run speed/HLE/RSX experiments; use the polling load-target gate and require PATH_TO_TENUTO_PRESENT before continuing."
} elseif ($latestStateAwareLateDoubleConfirmRouteDrift) {
    "Latest late double-confirm route missed field and selected Debug Save / Prologue instead of Path to Tenuto. Use a load-target-gated diagnostic only; it must abort before Cross unless Path to Tenuto is selected."
} elseif ($latestHle451cPreserveBodyBattleFatal) {
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
} elseif ($latestHle25ccBodyFastRsxFinalStackAuditorPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus exact RSX final-stack auditor/accounting run passed field and active first-battle triage. Bank it as RSX-local residency/cache accounting, not a speed win and not promoted CPU/SPU GPU work; next pivot to SPU/PPU/codegen proof, or a source-read/fill architecture change if staying RSX."
} elseif ($latestHle25ccBodyFastRsxRdpIndexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX resolve/depth/present plus VertexSuperset plus VertexPersistent plus IndexPersistent final recombine passed field and active first-battle triage. Treat the stack as compatible but capped at about 120 FPS; next, run an auditor/accounting proof for the exact stack if RSX-local credit needs to be quantified, otherwise pivot to a larger SPU/PPU speed lane."
} elseif ($latestHle25ccBodyFastRsxRdpVertexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX resolve/depth/present plus VertexSuperset plus VertexPersistent interaction step passed field and active first-battle triage. Keep that subset compatible; next add IndexPersistent Fast as the final isolated recombine step."
} elseif ($latestHle25ccBodyFastRsxRdpVertexSupersetPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX resolve/depth/present plus VertexSuperset interaction step passed field and active first-battle triage. Keep that subset compatible; next add VertexPersistent Fast while keeping IndexPersistent off."
} elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX resolve/depth/present-only bisection passed field and active first-battle triage, and geometry-only also passed after the full stack lost the window. Treat this as a cross-family interaction; add one geometry family to the resolve/depth/present subset, starting with VertexSuperset only, instead of rerunning the full stack."
} elseif ($latestHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX geometry-only bisection passed field and active first-battle triage after the full RSX geometry/locality stack lost the window. Keep geometry caches provisionally compatible; next isolate the complementary resolve/depth/present-only subset instead of rerunning the full stack."
} elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX resolve/depth/present-only bisection passed field and active first-battle triage after the full RSX geometry/locality stack lost the window. Keep resolve/depth/present provisionally compatible; next isolate the complementary geometry-only subset unless a recent clean geometry-only proof already exists."
} elseif ($latestHle25ccBodyFastRsxGeomStackWindowLost) {
    "Latest bodyfast plus RSX geometry/locality stack failed after field/tutorial and lost the game window before active first battle. Stop stacking. Bisect from the known-good bodyfast-only proof, starting with bodyfast plus geometry-only vertex/index caches."
} elseif ($latestHle25ccBodyFastCpuStackComponent) {
    "Latest 0x25cc bodyfast BattleRoute repeat is clean and confirms lower RPCS3 CPU pressure while FPS stays capped. Treat it as a stackable CPU-pressure component; next run should combine it with the existing RSX geometry/locality credit stack, not rerun bodyfast alone."
} elseif ($latestHle25ccBodyFastCpuCandidate) {
    "Latest 0x25cc bodyfast BattleRoute has clean field/battle visuals and capped FPS, with directional CPU-load reduction but postrun host-gate noise. Repeat a clean bodyfast or fresh stock/bodyfast pair to confirm CPU-load micro-win potential; otherwise pivot to larger 0x451c/codegen work."
} elseif ($latestHle25ccNoPauseBattleAbComplete) {
    "Latest 0x25cc no-pause BattleRoute A/B is complete and classified not-speed-win. Do not add generic route movement or rerun the same A/B; inspect body/family verifier timing, remove measurement overhead, or narrow the 0x25cc body before another matched comparison."
} elseif ($latestHle25ccBodyBattleOptionsRouteMiss) {
    "Latest 0x25cc body battle attempt opened the title Options page instead of first battle. Do not rerun that battle command unchanged; repair the first-battle macro or add a battle-aware route/visual gate before battle proof or stock/body A/B."
} elseif ($latestHle25ccShadowDescOptionsPass) {
    "Latest 0x25cc descriptor fast-select Options proof reached the full title Options page with Verify25ccShadow and zero target 0x25cc shadow/descriptor mismatches. Do not rerun field or Options; prove first battle next before bodyfast, stack, GPU, or speed promotion."
} elseif ($latestHle25ccShadowDescBattleFatal) {
    "Latest 0x25cc descriptor first-battle Verify25ccShadow run reached battle/tutorial visuals but fataled at PPU VM access 0x002aedd0 reading 0x40. Do not count it as first-battle proof, do not rerun unchanged, and do not reset to loader-control; first isolate whether the same TopSlot battle route is fatal without Verify25ccShadow."
} elseif ($latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck) {
    "Latest stock Down160 left1200 diagnostic never dismissed the Load complete popup, so its left1200 input is not movement. Keep the Down160 base, prove a stronger no-movement post-load-complete dismiss, then retry movement only after field appears."
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass) {
    "Latest stock Down160 strong-dismiss no-movement diagnostic reached clean Path-to-Tenuto field and stayed there. Keep the strong-dismiss base and retry only ls_left:1200 next before any verifier or first-battle promotion."
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass) {
    "Latest stock Down160 strong-dismiss left1200 long-gate diagnostic reached Path-to-Tenuto field and stayed field-clean after the left1200 pulse. Bank it as route movement only; try the left1800 midpoint on the same strong-dismiss long-gate base before verifier or battle promotion."
} elseif ($latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit) {
    "Latest stock Down160 left-only diagnostic reached Path-to-Tenuto field at $($latestRun.Visual.FirstFieldSeconds)s with clean fatal logs, then RPCS3 exited after ls_left:2600 before left-check screenshots. Treat the Down160 base as repaired, but not movement/battle proof; shrink to ls_left:1200 with an immediate post-movement screenshot before any verifier retry."
} elseif ($latestHle25ccShadowDescBattleStockLoading) {
    "Latest no-Verify25ccShadow TopSlot stock-control battle isolation stayed on Now Loading through every screenshot with clean fatal logs. This means the default TopSlot battle macro is not a valid stock control here; repair from the current Down160 late-load-complete base with a stock left-only diagnostic before any verifier retry."
} elseif ($latestHle25ccShadowDescBuildcheckRouteMiss) {
    "Latest 0x25cc descriptor buildcheck is source-instrumentation validated but route-invalid and used the stale down:20/up macro. Do not fall back to generic movement. Rerun Verify25ccShadow on the current Down160 late-dismiss direct-left field route with the widened descriptor table, then require clean field visuals, nonzero PUT descriptor rows, zero mismatches, and descriptor overflow 0."
} elseif ($latestHle25ccShadowDescOptionsNoCrossRouteMiss) {
    "Latest no-initial-Cross 0x25cc descriptor Options proof reached the title menu and selected Load, but the long second wait drifted into intro/title-loop frames before Options opened. Do not repeat it; run the fast Down160 Options-select proof with short waits and explicit selection screenshots."
} elseif ($latestHle25ccShadowDescOptionsRouteMiss) {
    "Latest 0x25cc descriptor Options proof entered story/cutscene because the initial Cross selected New Game instead of opening Options. Do not back off to loader-control field movement; rerun the Options proof with the no-initial-Cross title route and explicit preinput/selection screenshots."
} elseif ($latestHle25ccShadowDescDown160FieldPass) {
    "Latest 0x25cc descriptor Down160 field proof is clean and source-instrumentation validated with PUT/GET descriptor coverage, zero mismatches, and descriptor overflow 0. Do not rerun field; prove title Options/menu with Verify25ccShadow next, then first battle, before bodyfast, stack, GPU, or speed promotion."
} elseif ($latestCleanHle25ccShadowField) {
    "Latest 0x25cc shadow verifier is field-clean, but it proved exact command-level EA is the wrong broad predicate and the current shadow/body path is GET-only. Do not rerun generic movement or exact-EA skips; add pattern/descriptor-level payload or LS-range hashing split by GET/PUT direction for the top max-DMA groups before fast/body promotion."
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
} elseif ($latestValidLoaderControlDiag200) {
    "Latest loader-control-left200x2-diag200 field proof is clean. Do not repeat the same diagonal command; bank the diagonal micro-pulse as route-tooling only, then pivot to Options/menu proof, first-battle route repair, or focused SPU kernel HLE/codegen/verifier analysis."
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

$suggestedCommand = if ($latestStateAwarePromptStuck) {
    New-StateAwareDamagedSaveConfirmCommand
} elseif ($latestStateAwareSavePromptField) {
    New-StateAwareDamagedSaveDismissMovementCommand
} elseif ($latestStateAwareDismissLoadMenuMiss) {
    New-StateAwareLateLoadConfirmCommand
} elseif ($latestStateAwareLateLoadConfirmNeedsSecondCross) {
    New-StateAwareLateLoadDoubleConfirmDismissMovementCommand
} elseif ($latestLoadTargetPollGatedSaveMenuAfterField) {
    New-StateAwareLoadTargetPollGatedDirectLeftCommand
} elseif ($latestLoadTargetDirectLeftLongGateCutscene) {
    New-StateAwareTitleToLoadDiagnosticCommand
} elseif ($latestTitleToLoadDiagnosticCutscene) {
    New-StateAwareTitleToLoadDownHoldDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldClassifierFalseGateFailure) {
    New-StateAwareTitleToLoadDownHoldPostLoadCompleteDismissCommand
} elseif ($latestTitleToLoadDownHoldDirectLeftPersistentLoading) {
    New-StateAwareTitleToLoadDownHoldLoadStabilityNoMoveCommand
} elseif ($latestTitleToLoadDownHoldLoadStabilityNeedsDismiss) {
    New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissNoMoveCommand
} elseif ($latestTitleToLoadDownHoldLoadTopNormalizeBlack) {
    New-StateAwareTitleToLoadDownHoldLoadListCursorDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldLoadListDiagnosticBlackTransition) {
    New-StateAwareTitleToLoadDownHoldLoadTargetReproofCommand
} elseif ($latestTitleToLoadDownHoldLoadListDiagnosticSaveCheckStall) {
    New-StateAwareTitleToLoadDownHoldLoadListCursorDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldLoadTargetReproofPass) {
    New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissBattleLeftOnlyDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldLeftOnlyClassifierDrift) {
    New-StateAwareTitleToLoadDownHoldLoadListCursorDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldLateDismissDirectLeftFieldPass) {
    New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissBattleLeftOnlyDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldLateDismissNoMoveFieldPass) {
    New-StateAwareTitleToLoadDownHoldLateLoadCompleteDismissDirectLeftCommand
} elseif ($latestTitleToLoadDownHoldPostLoadCompleteSavePrompt) {
    New-StateAwareTitleToLoadDownHoldDirectLeftCommand
} elseif ($latestTitleToLoadDownHoldLoadTargetPass) {
    New-StateAwareTitleToLoadDownHoldDirectLeftCommand
} elseif ($latestTitleToLoadDownHoldBattleLeftOnlyFatal) {
    New-StateAwareTitleToLoadDownHoldDirectLeftCommand
} elseif ($latestTitleToLoadDownHoldBattleLeftOnlyPass) {
    "# No automatic full battle rerun: Down160 left-only survived after the full down-left branch crashed. Add a smaller/state-gated down-left diagnostic before another first-battle attempt."
} elseif ($latestTitleToLoadDownHoldDirectLeftFieldPass -and $recentTitleToLoadDownHoldBattleFatal) {
    New-StateAwareTitleToLoadDownHoldBattleLeftOnlyDiagnosticCommand
} elseif ($latestTitleToLoadDownHoldDirectLeftFieldPass) {
    New-StateAwareTitleToLoadDownHoldBattleRouteCommand
} elseif ($latestTitleToLoadDownHoldBattleFatal -and $recentTitleToLoadDownHoldDirectLeftFieldPass) {
    New-StateAwareTitleToLoadDownHoldDirectLeftCommand
} elseif ($latestTitleToLoadDownHoldDirectLeftLoadCompleteStuck) {
    New-StateAwareTitleToLoadDownHoldPostLoadCompleteDismissCommand
} elseif ($latestTitleToLoadDownHoldWrongSaveTarget) {
    "# No automatic route rerun: latest Down160 gate selected $latestLoadTargetGateStatus. Restore or repair the Path-to-Tenuto save target, verify PATH_TO_TENUTO_PRESENT with the load-target gate, then re-run the Down160 direct-left boundary proof."
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200BlackGate) {
    New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1200LongGateCommand
} elseif ($latestLoadTargetDirectLeftGateFailure) {
    New-StateAwareLoadTargetPollGatedDirectLeftCommand
} elseif ($latestLoadTargetGateFailure) {
    New-StateAwareLateLoadDoubleConfirmDismissMovementCommand
} elseif ($latestStateAwareLateDoubleConfirmRouteDrift) {
    New-StateAwareLateLoadDoubleConfirmDismissMovementCommand
} elseif ($latestHle451cPreserveBodyBattleFatal) {
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
} elseif ($latestHle25ccBodyFastRsxFinalStackAuditorPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label cpu4-reservation-loop-branchstate-verify-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsCpuAffinityMask 0x0F -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataReservationLoop Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxRdpIndexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-finalstack-auditor-battle-topslot-nopause-accounting -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsRsxAuditor 60 -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxRdpVertexPersistentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-indexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxRdpVertexSupersetPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexpersistent-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-rdp-vertexsuperset-battle-topslot-nopause-interaction -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxGeometryOnlyPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-resolvedepthpresent-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxResolveDepthPresentPass -and $recentHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-geometryonly-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastRsxGeomStackWindowLost) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-geometryonly-battle-topslot-nopause-bisect -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastCpuStackComponent) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-rsx-geomstack-battle-topslot-nopause -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsRsxTextureBarrier DepthReadOnly -WindowsRsxBlitSourceResolve FastSampled -WindowsRsxDepthFeedback KeepReadOnly -WindowsRsxPresentUpload GpuSwap -WindowsRsxVertexSupersetCache Fast -WindowsRsxVertexPersistentCache Fast -WindowsRsxIndexPersistentCache Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccBodyFastCpuCandidate) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-bodyfast-battle-topslot-nopause-battleroute-repeat -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHle25ccBody Fast -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccNoPauseBattleAbComplete) {
    "# No automatic rerun: latest 0x25cc no-pause BattleRoute A/B already proved field and first-battle visuals but was slower. Inspect body/family timing, remove verifier overhead, or narrow the 0x25cc body before another stock/body A/B."
} elseif ($latestHle25ccBodyBattleOptionsRouteMiss) {
    ".\tools\eternal_sonata_speed_sprint.ps1 -Action WindowsScene -Scene battle -Label hle-25cc-body-battle-topslot-battleroute -WindowsInputBackend PadApi -WindowsGameScreen 1 -WindowsBattleLoadRoute TopSlot -WindowsFrameLimit 240 -WindowsVblankRate 240 -EternalSonataSpuHleVerify Verify25ccShadow -EternalSonataSpuHle25ccBody Verify -WindowsHostContentionGate ExternalFail -MaxSeconds 330 -ScreenshotEverySeconds 20 -ScreenshotStartSeconds 120 -ScreenshotMaxCount 12 -WindowsVisualGate BattleRoute -WindowsVisualGateFieldSeconds 160"
} elseif ($latestHle25ccShadowDescOptionsPass) {
    New-Hle25ccShadowDescBattleVerifyCommand
} elseif ($latestHle25ccShadowDescBattleFatal) {
    New-Hle25ccShadowDescBattleStockControlCommand
} elseif ($latestHle25ccShadowDescBattleStockDown160Left1200LoadCompleteStuck) {
    New-Hle25ccShadowDescBattleStockDown160StrongDismissNoMoveCommand
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissNoMoveFieldPass) {
    New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1200Command
} elseif ($latestHle25ccShadowDescBattleStockDown160StrongDismissLeft1200FieldPass) {
    New-Hle25ccShadowDescBattleStockDown160StrongDismissLeft1800LongGateCommand
} elseif ($latestHle25ccShadowDescBattleStockDown160LeftOnlyProcessExit) {
    New-Hle25ccShadowDescBattleStockDown160Left1200Command
} elseif ($latestHle25ccShadowDescBattleStockLoading) {
    New-Hle25ccShadowDescBattleStockDown160LeftOnlyCommand
} elseif ($latestHle25ccShadowDescBuildcheckRouteMiss) {
    New-Hle25ccShadowDescDown160VerifyCommand
} elseif ($latestHle25ccShadowDescOptionsNoCrossRouteMiss) {
    New-Hle25ccShadowDescOptionsFastSelectCommand
} elseif ($latestHle25ccShadowDescOptionsRouteMiss) {
    New-Hle25ccShadowDescOptionsNoInitialCrossCommand
} elseif ($latestHle25ccShadowDescDown160FieldPass) {
    New-Hle25ccShadowDescOptionsCommand
} elseif ($latestCleanHle25ccShadowField) {
    "# No automatic movement rerun: latest clean 0x25cc shadow run exposes a pattern-hash instrumentation gap, and the current shadow/body path is GET-only while matched target rows are PUT-heavy. Add pattern/descriptor-level payload or LS-range hashing split by GET/PUT direction for the top max-DMA 0x9e4000 groups, then rerun Verify25ccShadow across field, menu/Options, and first battle."
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
} elseif ($latestValidLoaderControlDiag200) {
    "# No automatic duplicate: latest loader-control-left200x2-diag200 already passed field triage. Bank it as route tooling and pivot to Options/menu proof, first-battle route repair, or focused SPU kernel HLE/codegen/verifier analysis."
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
$md.Add("| Run | Visual | Load target | Fatal | Primary small class | Field | RSX-local | Offload fit | Lane 2 | Decision |")
$md.Add("| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- |")
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
    $loadTargetText = if ($run.LoadTarget -and $run.LoadTarget.Status) { $run.LoadTarget.Status } elseif ($run.LoadTarget -and $run.LoadTarget.GateFailed) { "failed-no-status" } else { "n/a" }
    $md.Add(("| ``{0}`` | ``{1}`` | ``{2}`` | ``{3}`` | ``{4}`` | {5} | {6} | {7} | {8} | ``{9}`` |" -f $run.Name, $run.Visual.Status, $loadTargetText, $fatalText, $primarySmall, $fieldText, $rsxLocal, $fit, $laneText, $run.Decision))
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
