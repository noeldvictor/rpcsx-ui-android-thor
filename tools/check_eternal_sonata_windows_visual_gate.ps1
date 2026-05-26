[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir,

    [long]$MinFieldPngBytes = 1000000,

    [long]$MinBlackOverlayPngBytes = 20000,

    [long]$MaxBlackOverlayPngBytes = 60000,

    [long]$MinLoadingPngBytes = 90000,

    [long]$MaxLoadingPngBytes = 160000,

    [int]$RequireFieldAtOrBeforeSeconds = -1,

    [int]$RequireFieldAtOrAfterSeconds = -1,

    [int]$RequireMinFieldLikeCount = 0,

    [int]$RequireBattleLikeAtOrAfterSeconds = -1,

    [double]$MinBattleLikeRedRatio = 0.25,

    [double]$MaxBattleLikeGreenRatio = 0.34,

    [switch]$RequireFieldLike,

    [switch]$RequireNoInvalidAfterFirstField,

    [switch]$DisableColorHeuristic,

    [switch]$NoWriteSummary
)

$ErrorActionPreference = "Stop"

function Format-Bytes {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ("{0:N2} MB" -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ("{0:N2} KB" -f ($Bytes / 1KB))
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

function Get-ScreenshotColorStats {
    param([string]$Path)

    if ($DisableColorHeuristic) {
        return $null
    }

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

function Test-BlueNonFieldScreenshot {
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

function Get-ScreenshotClass {
    param(
        [long]$Bytes,
        [AllowNull()][object]$ColorStats
    )

    if (Test-BlueNonFieldScreenshot -ColorStats $ColorStats) {
        if ($Bytes -ge $MinFieldPngBytes) {
            return "cutscene-or-nonfield-large-png"
        }
        return "cutscene-or-nonfield-small-png"
    }

    if ($Bytes -ge $MinFieldPngBytes) {
        if ($ColorStats -and (
            $ColorStats.RedRatio -ge 0.45 -or
            $ColorStats.DarkRatio -ge 0.70 -or
            ($ColorStats.GreenRatio -lt 0.15 -and $ColorStats.DarkRatio -ge 0.35)
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

$resolvedRunDir = (Resolve-Path -LiteralPath $RunDir).Path
$screenshotDir = Join-Path $resolvedRunDir "screenshots"
if (-not (Test-Path -LiteralPath $screenshotDir -PathType Container)) {
    $directPngs = @(Get-ChildItem -LiteralPath $resolvedRunDir -Filter "*.png" -File -ErrorAction SilentlyContinue)
    if ($directPngs.Count -gt 0) {
        $screenshotDir = $resolvedRunDir
    } else {
        throw "No screenshots directory or PNG files found under $resolvedRunDir"
    }
}

$screenshots = @(Get-ChildItem -LiteralPath $screenshotDir -Filter "*.png" -File | Sort-Object @{ Expression = { Get-ScreenshotSecond $_.Name } }, Name)
if ($screenshots.Count -eq 0) {
    throw "No PNG screenshots found in $screenshotDir"
}

$rows = foreach ($shot in $screenshots) {
    $second = Get-ScreenshotSecond $shot.Name
    $colorStats = Get-ScreenshotColorStats -Path $shot.FullName
    $class = Get-ScreenshotClass -Bytes $shot.Length -ColorStats $colorStats

    [pscustomobject]@{
        Screenshot = $shot.Name
        Seconds = if ($second -eq [int]::MaxValue) { $null } else { $second }
        Bytes = $shot.Length
        HumanBytes = Format-Bytes $shot.Length
        Class = $class
        AvgR = if ($colorStats) { $colorStats.AvgR } else { $null }
        AvgG = if ($colorStats) { $colorStats.AvgG } else { $null }
        AvgB = if ($colorStats) { $colorStats.AvgB } else { $null }
        GreenRatio = if ($colorStats) { $colorStats.GreenRatio } else { $null }
        BlueRatio = if ($colorStats) { $colorStats.BlueRatio } else { $null }
        RedRatio = if ($colorStats) { $colorStats.RedRatio } else { $null }
        DarkRatio = if ($colorStats) { $colorStats.DarkRatio } else { $null }
    }
}

$fieldRows = @($rows | Where-Object { $_.Class -eq "field-like-large-png" })
$firstField = $fieldRows | Sort-Object Seconds, Screenshot | Select-Object -First 1
$invalidRows = @($rows | Where-Object { $_.Class -ne "field-like-large-png" })
$invalidAfterFirstField = @()
if ($firstField) {
    $invalidAfterFirstField = @($invalidRows | Where-Object { $null -eq $_.Seconds -or $_.Seconds -ge $firstField.Seconds })
}
$fieldBeforeDeadline = @()
if ($RequireFieldAtOrBeforeSeconds -ge 0) {
    $fieldBeforeDeadline = @($fieldRows | Where-Object { $null -ne $_.Seconds -and $_.Seconds -le $RequireFieldAtOrBeforeSeconds })
}
$fieldAfterDeadline = @()
if ($RequireFieldAtOrAfterSeconds -ge 0) {
    $fieldAfterDeadline = @($fieldRows | Where-Object { $null -ne $_.Seconds -and $_.Seconds -ge $RequireFieldAtOrAfterSeconds })
}
$battleLikeRows = @($fieldRows | Where-Object {
    $null -ne $_.RedRatio -and
    $null -ne $_.GreenRatio -and
    $_.RedRatio -ge $MinBattleLikeRedRatio -and
    $_.GreenRatio -le $MaxBattleLikeGreenRatio
})
$battleLikeAfterDeadline = @()
if ($RequireBattleLikeAtOrAfterSeconds -ge 0) {
    $battleLikeAfterDeadline = @($battleLikeRows | Where-Object { $null -ne $_.Seconds -and $_.Seconds -ge $RequireBattleLikeAtOrAfterSeconds })
}

$status = if ($fieldRows.Count -eq 0) {
    "NO_FIELD_LIKE_SCREENSHOT"
} elseif ($invalidAfterFirstField.Count -gt 0) {
    "FIELD_LIKE_PRESENT_WITH_LATER_INVALID_SCREENSHOTS"
} else {
    "FIELD_LIKE_PRESENT"
}

$gateFailures = New-Object System.Collections.Generic.List[string]
if ($RequireFieldLike -and $fieldRows.Count -eq 0) {
    $gateFailures.Add("No field-like screenshot was found.")
}
if ($RequireNoInvalidAfterFirstField -and $invalidAfterFirstField.Count -gt 0) {
    $gateFailures.Add("Invalid small screenshot(s) appeared after the first field-like screenshot.")
}
if ($RequireFieldAtOrBeforeSeconds -ge 0 -and $fieldBeforeDeadline.Count -eq 0) {
    $gateFailures.Add("No field-like screenshot was found at or before ${RequireFieldAtOrBeforeSeconds}s.")
}
if ($RequireFieldAtOrAfterSeconds -ge 0 -and $fieldAfterDeadline.Count -eq 0) {
    $gateFailures.Add("No field-like screenshot was found at or after ${RequireFieldAtOrAfterSeconds}s.")
}
if ($RequireMinFieldLikeCount -gt 0 -and $fieldRows.Count -lt $RequireMinFieldLikeCount) {
    $gateFailures.Add("Only $($fieldRows.Count) field-like screenshot(s) were found; required at least $RequireMinFieldLikeCount.")
}
if ($RequireBattleLikeAtOrAfterSeconds -ge 0 -and $battleLikeAfterDeadline.Count -eq 0) {
    $gateFailures.Add("No battle-like screenshot was found at or after ${RequireBattleLikeAtOrAfterSeconds}s using red-ratio >= $MinBattleLikeRedRatio and green-ratio <= $MaxBattleLikeGreenRatio.")
}

$summaryPath = Join-Path $resolvedRunDir "eternal-sonata-windows-visual-gate-summary.md"
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# Eternal Sonata Windows Visual Gate")
$summary.Add("")
$summary.Add(("- Run directory: ``{0}``" -f $resolvedRunDir))
$summary.Add(("- Screenshot directory: ``{0}``" -f $screenshotDir))
$method = if ($DisableColorHeuristic) {
    "PNG byte-size triage, color heuristic disabled; not OCR or final visual proof."
} else {
    "PNG byte-size triage plus sampled color heuristic for blue non-field frames and large red/dark cutscene frames; not OCR or final visual proof."
}
$summary.Add(("- Classification method: {0}" -f $method))
$summary.Add(("- Minimum field-like PNG bytes: ``{0}``" -f $MinFieldPngBytes))
$summary.Add(("- Black-overlay PNG byte window: ``{0}`` to ``{1}``." -f $MinBlackOverlayPngBytes, $MaxBlackOverlayPngBytes))
$summary.Add(("- Loading-like PNG byte window: ``{0}`` to ``{1}``." -f $MinLoadingPngBytes, $MaxLoadingPngBytes))
$summary.Add(("- Status: ``{0}``" -f $status))
if ($firstField) {
    $summary.Add(("- First field-like screenshot: ``{0}`` at ``{1}s`` (``{2}``)." -f $firstField.Screenshot, $firstField.Seconds, $firstField.HumanBytes))
} else {
    $summary.Add("- First field-like screenshot: none.")
}
if ($invalidAfterFirstField.Count -gt 0) {
    $firstInvalidAfterField = $invalidAfterFirstField | Sort-Object Seconds, Screenshot | Select-Object -First 1
    $summary.Add(("- Invalid screenshots after first field-like: ``{0}``, first ``{1}`` at ``{2}s`` (``{3}``)." -f $invalidAfterFirstField.Count, $firstInvalidAfterField.Screenshot, $firstInvalidAfterField.Seconds, $firstInvalidAfterField.HumanBytes))
} else {
    $summary.Add("- Invalid screenshots after first field-like: ``0``.")
}
if ($RequireFieldAtOrBeforeSeconds -ge 0) {
    $deadlineStatus = if ($fieldBeforeDeadline.Count -gt 0) { "passed" } else { "failed" }
    $summary.Add(("- Required field-like at or before ``{0}s``: ``{1}``." -f $RequireFieldAtOrBeforeSeconds, $deadlineStatus))
}
if ($RequireFieldAtOrAfterSeconds -ge 0) {
    $afterStatus = if ($fieldAfterDeadline.Count -gt 0) { "passed" } else { "failed" }
    $summary.Add(("- Required field-like at or after ``{0}s``: ``{1}``." -f $RequireFieldAtOrAfterSeconds, $afterStatus))
}
if ($RequireMinFieldLikeCount -gt 0) {
    $countStatus = if ($fieldRows.Count -ge $RequireMinFieldLikeCount) { "passed" } else { "failed" }
    $summary.Add(("- Required field-like screenshot count ``{0}``: ``{1}`` (found ``{2}``)." -f $RequireMinFieldLikeCount, $countStatus, $fieldRows.Count))
}
if ($RequireBattleLikeAtOrAfterSeconds -ge 0) {
    $battleLikeStatus = if ($battleLikeAfterDeadline.Count -gt 0) { "passed" } else { "failed" }
    $battleLikeFirst = $battleLikeAfterDeadline | Sort-Object Seconds, Screenshot | Select-Object -First 1
    if ($battleLikeFirst) {
        $summary.Add(("- Required battle-like at or after ``{0}s``: ``{1}`` (first ``{2}`` at ``{3}s``, red/green ratios ``{4}``/``{5}``)." -f $RequireBattleLikeAtOrAfterSeconds, $battleLikeStatus, $battleLikeFirst.Screenshot, $battleLikeFirst.Seconds, $battleLikeFirst.RedRatio, $battleLikeFirst.GreenRatio))
    } else {
        $summary.Add(("- Required battle-like at or after ``{0}s``: ``{1}`` (found ``0``)." -f $RequireBattleLikeAtOrAfterSeconds, $battleLikeStatus))
    }
}
$summary.Add("- Class counts:")
$classCounts = $rows | Group-Object Class | Sort-Object Name
foreach ($classCount in $classCounts) {
    $summary.Add(("  - ``{0}``: ``{1}``." -f $classCount.Name, $classCount.Count))
}
if ($gateFailures.Count -gt 0) {
    $summary.Add("- Gate result: ``failed``.")
} else {
    $summary.Add("- Gate result: ``passed-for-triage``.")
}
$summary.Add("")
$summary.Add("| Screenshot | Seconds | Bytes | Class | Avg RGB | G/B/R/D ratios |")
$summary.Add("| --- | ---: | ---: | --- | ---: | ---: |")
foreach ($row in $rows) {
    $secondsText = if ($null -eq $row.Seconds) { "" } else { "$($row.Seconds)" }
    $avgText = if ($null -eq $row.AvgR) { "" } else { "{0}/{1}/{2}" -f $row.AvgR, $row.AvgG, $row.AvgB }
    $ratioText = if ($null -eq $row.GreenRatio) { "" } else { "{0}/{1}/{2}/{3}" -f $row.GreenRatio, $row.BlueRatio, $row.RedRatio, $row.DarkRatio }
    $summary.Add(("| ``{0}`` | {1} | {2} | ``{3}`` | {4} | {5} |" -f $row.Screenshot, $secondsText, $row.Bytes, $row.Class, $avgText, $ratioText))
}

if (-not $NoWriteSummary) {
    [System.IO.File]::WriteAllLines($summaryPath, $summary, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Run: $resolvedRunDir"
Write-Host "Screenshots: $($screenshots.Count)"
Write-Host "Status: $status"
if ($firstField) {
    Write-Host "First field-like: $($firstField.Screenshot) at $($firstField.Seconds)s ($($firstField.HumanBytes))"
} else {
    Write-Host "First field-like: none"
}
if (-not $NoWriteSummary) {
    Write-Host "Summary: $summaryPath"
}
if ($gateFailures.Count -gt 0) {
    foreach ($failure in $gateFailures) {
        Write-Host "Gate failure: $failure"
    }
    throw "Windows visual gate failed: $($gateFailures -join '; ')"
}
