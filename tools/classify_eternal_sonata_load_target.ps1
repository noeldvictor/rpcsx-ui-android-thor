[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir,

    [string]$GoodExemplar = "",

    [string]$BadExemplar = "",

    [int]$CropX = 650,

    [int]$CropY = 190,

    [int[]]$CandidateCropYs = @(),

    [int]$CropWidth = 500,

    [int]$CropHeight = 145,

    [int]$GridColumns = 80,

    [int]$GridRows = 28,

    [double]$DecisionMargin = 4.0,

    [double]$MaxKnownDiff = 8.0,

    [double]$LoosePathMaxDiff = 22.0,

    [double]$LoosePathDecisionMargin = 6.0,

    [double]$MaxEmptyKnownDiff = 25.0,

    [double]$MinLoadTargetTextBrightRatio = 0.012,

    [string]$DamagedExemplar = "",

    [int[]]$DamagedExemplarRows = @(),

    [int]$DamagedTextCropX = 120,

    [int]$DamagedTextCropYOffset = 25,

    [int]$DamagedTextCropWidth = 430,

    [int]$DamagedTextCropHeight = 55,

    [double]$DamagedTextMaxDiff = 14.0,

    [switch]$RequirePathToTenuto,

    [switch]$NoWriteSummary
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $root = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if (-not $root) {
        throw "Could not resolve repo root from $PSScriptRoot"
    }
    return $root.Trim()
}

function Resolve-RepoPath {
    param(
        [string]$Root,
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Resolve-FirstExistingRepoPath {
    param(
        [string]$Root,
        [string[]]$Paths
    )

    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }
        $resolved = Resolve-RepoPath -Root $Root -Path $path
        if (Test-Path -LiteralPath $resolved -PathType Leaf) {
            return $resolved
        }
    }
    return ""
}

function Get-ScreenshotSecond {
    param([string]$Name)

    if ($Name -match '^screenshot-(\d+)s(?:-|\.png$)') {
        return [int]$matches[1]
    }
    return [int]::MaxValue
}

function Get-ScaledRect {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [int]$Y = $CropY
    )

    $baseWidth = 1296.0
    $baseHeight = 759.0
    $x = [math]::Floor($CropX * $Bitmap.Width / $baseWidth)
    $y = [math]::Floor($Y * $Bitmap.Height / $baseHeight)
    $w = [math]::Max(1, [math]::Floor($CropWidth * $Bitmap.Width / $baseWidth))
    $h = [math]::Max(1, [math]::Floor($CropHeight * $Bitmap.Height / $baseHeight))

    if (($x + $w) -gt $Bitmap.Width) {
        $w = $Bitmap.Width - $x
    }
    if (($y + $h) -gt $Bitmap.Height) {
        $h = $Bitmap.Height - $y
    }

    return [pscustomobject]@{
        X = [int]$x
        Y = [int]$y
        Width = [int]$w
        Height = [int]$h
    }
}

function Get-RegionDiff {
    param(
        [string]$CandidatePath,
        [string]$ExemplarPath,
        [int]$CandidateY = $CropY
    )

    $candidate = [System.Drawing.Bitmap]::FromFile($CandidatePath)
    $exemplar = [System.Drawing.Bitmap]::FromFile($ExemplarPath)

    try {
        $candidateRect = Get-ScaledRect -Bitmap $candidate -Y $CandidateY
        $exemplarRect = Get-ScaledRect -Bitmap $exemplar -Y $CropY
        [double]$sum = 0
        [int]$count = 0

        for ($row = 0; $row -lt $GridRows; $row++) {
            $rowFrac = if ($GridRows -le 1) { 0.5 } else { ($row + 0.5) / $GridRows }
            $cy = [math]::Min($candidate.Height - 1, $candidateRect.Y + [math]::Floor($rowFrac * $candidateRect.Height))
            $ey = [math]::Min($exemplar.Height - 1, $exemplarRect.Y + [math]::Floor($rowFrac * $exemplarRect.Height))

            for ($col = 0; $col -lt $GridColumns; $col++) {
                $colFrac = if ($GridColumns -le 1) { 0.5 } else { ($col + 0.5) / $GridColumns }
                $cx = [math]::Min($candidate.Width - 1, $candidateRect.X + [math]::Floor($colFrac * $candidateRect.Width))
                $ex = [math]::Min($exemplar.Width - 1, $exemplarRect.X + [math]::Floor($colFrac * $exemplarRect.Width))
                $cp = $candidate.GetPixel($cx, $cy)
                $ep = $exemplar.GetPixel($ex, $ey)
                $sum += [math]::Abs($cp.R - $ep.R)
                $sum += [math]::Abs($cp.G - $ep.G)
                $sum += [math]::Abs($cp.B - $ep.B)
                $count += 3
            }
        }

        if ($count -eq 0) {
            return [double]::PositiveInfinity
        }
        return [math]::Round($sum / $count, 3)
    } finally {
        $candidate.Dispose()
        $exemplar.Dispose()
    }
}

function Get-TargetClass {
    param(
        [double]$GoodDiff,
        [double]$BadDiff,
        [double]$TextBrightRatio
    )

    $knownDiff = if ([double]::IsPositiveInfinity($BadDiff)) { $GoodDiff } else { [math]::Min($GoodDiff, $BadDiff) }

    if ($TextBrightRatio -lt $MinLoadTargetTextBrightRatio -and
        ($knownDiff -le $MaxEmptyKnownDiff)) {
        return "empty-load-slot"
    }
    if ($GoodDiff -le $MaxKnownDiff -and ($BadDiff - $GoodDiff) -ge $DecisionMargin) {
        return "path-to-tenuto"
    }
    if ($BadDiff -le $MaxKnownDiff -and ($GoodDiff - $BadDiff) -ge $DecisionMargin) {
        return "debug-save-prologue"
    }
    if ($GoodDiff -le $LoosePathMaxDiff -and ($BadDiff - $GoodDiff) -ge $LoosePathDecisionMargin) {
        return "path-to-tenuto"
    }
    return "unknown-load-target"
}

function Get-RegionTextBrightRatio {
    param(
        [string]$CandidatePath,
        [int]$CandidateY = $CropY
    )

    $candidate = [System.Drawing.Bitmap]::FromFile($CandidatePath)

    try {
        $candidateRect = Get-ScaledRect -Bitmap $candidate -Y $CandidateY
        [int]$bright = 0
        [int]$count = 0

        for ($row = 0; $row -lt $GridRows; $row++) {
            $rowFrac = if ($GridRows -le 1) { 0.5 } else { ($row + 0.5) / $GridRows }
            $cy = [math]::Min($candidate.Height - 1, $candidateRect.Y + [math]::Floor($rowFrac * $candidateRect.Height))

            for ($col = 0; $col -lt $GridColumns; $col++) {
                $colFrac = if ($GridColumns -le 1) { 0.5 } else { ($col + 0.5) / $GridColumns }
                $cx = [math]::Min($candidate.Width - 1, $candidateRect.X + [math]::Floor($colFrac * $candidateRect.Width))
                $pixel = $candidate.GetPixel($cx, $cy)
                $count++
                if ($pixel.R -gt 210 -and $pixel.G -gt 180 -and $pixel.B -gt 120) {
                    $bright++
                }
            }
        }

        if ($count -eq 0) {
            return 0.0
        }
        return [math]::Round($bright / $count, 4)
    } finally {
        $candidate.Dispose()
    }
}

function Get-DamagedTextDiff {
    param(
        [string]$CandidatePath,
        [string]$ExemplarPath,
        [int]$CandidateY,
        [int]$ExemplarY
    )

    $candidate = [System.Drawing.Bitmap]::FromFile($CandidatePath)
    $exemplar = [System.Drawing.Bitmap]::FromFile($ExemplarPath)

    try {
        [double]$sum = 0
        [int]$count = 0

        for ($row = 0; $row -lt $GridRows; $row++) {
            $rowFrac = if ($GridRows -le 1) { 0.5 } else { ($row + 0.5) / $GridRows }
            $cy = [math]::Min($candidate.Height - 1, [math]::Floor(($CandidateY + $DamagedTextCropYOffset + ($rowFrac * $DamagedTextCropHeight)) * $candidate.Height / 759.0))
            $ey = [math]::Min($exemplar.Height - 1, [math]::Floor(($ExemplarY + $DamagedTextCropYOffset + ($rowFrac * $DamagedTextCropHeight)) * $exemplar.Height / 759.0))

            for ($col = 0; $col -lt $GridColumns; $col++) {
                $colFrac = if ($GridColumns -le 1) { 0.5 } else { ($col + 0.5) / $GridColumns }
                $cx = [math]::Min($candidate.Width - 1, [math]::Floor(($DamagedTextCropX + ($colFrac * $DamagedTextCropWidth)) * $candidate.Width / 1296.0))
                $ex = [math]::Min($exemplar.Width - 1, [math]::Floor(($DamagedTextCropX + ($colFrac * $DamagedTextCropWidth)) * $exemplar.Width / 1296.0))
                $cp = $candidate.GetPixel($cx, $cy)
                $ep = $exemplar.GetPixel($ex, $ey)
                $sum += [math]::Abs($cp.R - $ep.R)
                $sum += [math]::Abs($cp.G - $ep.G)
                $sum += [math]::Abs($cp.B - $ep.B)
                $count += 3
            }
        }

        if ($count -eq 0) {
            return [double]::PositiveInfinity
        }
        return [math]::Round($sum / $count, 3)
    } finally {
        $candidate.Dispose()
        $exemplar.Dispose()
    }
}

function Get-DamagedTextRows {
    param(
        [string]$CandidatePath,
        [string]$ExemplarPath,
        [int[]]$CandidateYs,
        [int[]]$ExemplarYs
    )

    if ([string]::IsNullOrWhiteSpace($ExemplarPath) -or -not (Test-Path -LiteralPath $ExemplarPath -PathType Leaf)) {
        return @()
    }

    $damagedRows = New-Object System.Collections.Generic.List[int]
    foreach ($candidateY in $CandidateYs) {
        $bestDiff = [double]::PositiveInfinity
        foreach ($exemplarY in $ExemplarYs) {
            $diff = Get-DamagedTextDiff -CandidatePath $CandidatePath -ExemplarPath $ExemplarPath -CandidateY $candidateY -ExemplarY $exemplarY
            if ($diff -lt $bestDiff) {
                $bestDiff = $diff
            }
        }
        if ($bestDiff -le $DamagedTextMaxDiff) {
            [void]$damagedRows.Add([int]$candidateY)
        }
    }
    return @($damagedRows)
}

function Get-BestTargetMatch {
    param(
        [string]$CandidatePath,
        [string]$GoodExemplarPath,
        [string]$BadExemplarPath,
        [int[]]$CropYs
    )

    $matches = foreach ($candidateY in $CropYs) {
        $goodDiff = Get-RegionDiff -CandidatePath $CandidatePath -ExemplarPath $GoodExemplarPath -CandidateY $candidateY
        $badDiff = if ([string]::IsNullOrWhiteSpace($BadExemplarPath) -or -not (Test-Path -LiteralPath $BadExemplarPath -PathType Leaf)) {
            [double]::PositiveInfinity
        } else {
            Get-RegionDiff -CandidatePath $CandidatePath -ExemplarPath $BadExemplarPath -CandidateY $candidateY
        }
        $textBrightRatio = Get-RegionTextBrightRatio -CandidatePath $CandidatePath -CandidateY $candidateY
        $target = Get-TargetClass -GoodDiff $goodDiff -BadDiff $badDiff -TextBrightRatio $textBrightRatio
        [pscustomobject]@{
            CandidateY = $candidateY
            GoodDiff = $goodDiff
            BadDiff = $badDiff
            TextBrightRatio = $textBrightRatio
            BestKnownDiff = [math]::Min($goodDiff, $badDiff)
            Target = $target
        }
    }

    $pathCandidateYs = @($matches | Where-Object { $_.Target -eq "path-to-tenuto" } | Select-Object -ExpandProperty CandidateY)
    $debugCandidateYs = @($matches | Where-Object { $_.Target -eq "debug-save-prologue" } | Select-Object -ExpandProperty CandidateY)
    $topPathOnly = ($pathCandidateYs.Count -eq 1 -and $pathCandidateYs[0] -eq $CropY)

    $best = @($matches | Sort-Object `
        @{ Expression = {
            if ($_.Target -eq "path-to-tenuto") { 0 }
            elseif ($_.Target -eq "debug-save-prologue") { 1 }
            else { 2 }
        } }, `
        BestKnownDiff, CandidateY | Select-Object -First 1)[0]

    $best | Add-Member -NotePropertyName PathCandidateYs -NotePropertyValue $pathCandidateYs -Force
    $best | Add-Member -NotePropertyName DebugCandidateYs -NotePropertyValue $debugCandidateYs -Force
    $best | Add-Member -NotePropertyName TopPathOnly -NotePropertyValue $topPathOnly -Force
    return $best
}

function Get-LowerCursorRows {
    param(
        [string]$CandidatePath,
        [int[]]$CropYs
    )

    $bitmap = [System.Drawing.Bitmap]::FromFile($CandidatePath)
    try {
        $cursorRows = New-Object System.Collections.Generic.List[int]
        foreach ($candidateY in @($CropYs | Where-Object { $_ -ne $CropY })) {
            $x = [math]::Floor(60 * $bitmap.Width / 1296.0)
            $y = [math]::Floor(($candidateY - 15) * $bitmap.Height / 759.0)
            $w = [math]::Max(1, [math]::Floor(95 * $bitmap.Width / 1296.0))
            $h = [math]::Max(1, [math]::Floor(100 * $bitmap.Height / 759.0))
            $xMax = [math]::Min($bitmap.Width, $x + $w)
            $yMax = [math]::Min($bitmap.Height, $y + $h)
            [int]$whitePixels = 0

            for ($py = [math]::Max(0, $y); $py -lt $yMax; $py += 2) {
                for ($px = [math]::Max(0, $x); $px -lt $xMax; $px += 2) {
                    $pixel = $bitmap.GetPixel($px, $py)
                    if ($pixel.R -gt 220 -and $pixel.G -gt 200 -and $pixel.B -gt 150) {
                        $whitePixels++
                    }
                }
            }

            if ($whitePixels -ge 20) {
                [void]$cursorRows.Add([int]$candidateY)
            }
        }
        return @($cursorRows)
    } finally {
        $bitmap.Dispose()
    }
}

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot

if ([string]::IsNullOrWhiteSpace($GoodExemplar)) {
    $GoodExemplar = "debug-captures\windows-lab\20260526-001938-cpu4-stateaware-late-load-confirm-left200-visualgate-windows-windows\screenshots\screenshot-0117s.png"
}
if ([string]::IsNullOrWhiteSpace($BadExemplar)) {
    $BadExemplar = "debug-captures\windows-lab\20260526-003206-cpu4-stateaware-late-load-doubleconfirm-dismisssave-left200-visualgate-windows-windows\screenshots\screenshot-0118s.png"
}
if ([string]::IsNullOrWhiteSpace($DamagedExemplar)) {
    $DamagedExemplar = "debug-captures\windows-lab\20260527-152343-cpu4-hle-25cc-shadow-desc-battle-stock-down160-strongdismiss600-nomove-longgate-diagnostic-windows\screenshots\screenshot-0081s-load-target-gate.png"
}
if ($DamagedExemplarRows.Count -eq 0) {
    $DamagedExemplarRows = @($CropY, 365)
}

$resolvedRunDir = Resolve-RepoPath -Root $repoRoot -Path $RunDir
$resolvedGoodExemplar = Resolve-FirstExistingRepoPath -Root $repoRoot -Paths @(
    $GoodExemplar,
    "debug-captures\windows-lab\20260602-165106-cpu4-titleload-blackcontrol-resloop-diagnostic-windows-windows\screenshots\screenshot-0192s-load-target-gate-33.png",
    "debug-captures\windows-lab\20260601-212031-cpu4-stateaware-loadtarget-savecheck-diagnostic-windows-windows\screenshots\screenshot-0069s.png"
)
$resolvedBadExemplar = Resolve-FirstExistingRepoPath -Root $repoRoot -Paths @($BadExemplar)
$resolvedDamagedExemplar = Resolve-RepoPath -Root $repoRoot -Path $DamagedExemplar

if (-not (Test-Path -LiteralPath $resolvedRunDir -PathType Container)) {
    throw "Run directory not found: $resolvedRunDir"
}
if (-not (Test-Path -LiteralPath $resolvedGoodExemplar -PathType Leaf)) {
    throw "Path-to-Tenuto exemplar not found: $resolvedGoodExemplar"
}
$badGuardEnabled = (-not [string]::IsNullOrWhiteSpace($resolvedBadExemplar)) -and (Test-Path -LiteralPath $resolvedBadExemplar -PathType Leaf)
$damagedGuardEnabled = Test-Path -LiteralPath $resolvedDamagedExemplar -PathType Leaf

Add-Type -AssemblyName System.Drawing -ErrorAction Stop

if ($CandidateCropYs.Count -eq 0) {
    $CandidateCropYs = @($CropY, 365, 535)
}
$CandidateCropYs = @($CandidateCropYs | Select-Object -Unique)

$screenshotDir = Join-Path $resolvedRunDir "screenshots"
if (-not (Test-Path -LiteralPath $screenshotDir -PathType Container)) {
    $directPngs = @(Get-ChildItem -LiteralPath $resolvedRunDir -Filter "*.png" -File -ErrorAction SilentlyContinue)
    if ($directPngs.Count -gt 0) {
        $screenshotDir = $resolvedRunDir
    } else {
        throw "No screenshots directory or PNG files found under $resolvedRunDir"
    }
}

$screenshots = @(Get-ChildItem -LiteralPath $screenshotDir -Filter "*.png" -File |
    Sort-Object @{ Expression = { Get-ScreenshotSecond $_.Name } }, Name)
if ($screenshots.Count -eq 0) {
    throw "No PNG screenshots found in $screenshotDir"
}

$rows = foreach ($shot in $screenshots) {
    $bestMatch = Get-BestTargetMatch -CandidatePath $shot.FullName -GoodExemplarPath $resolvedGoodExemplar -BadExemplarPath $resolvedBadExemplar -CropYs $CandidateCropYs
    $lowerCursorRows = @(Get-LowerCursorRows -CandidatePath $shot.FullName -CropYs $CandidateCropYs)
    $damagedTextRows = if ($damagedGuardEnabled) {
        @(Get-DamagedTextRows -CandidatePath $shot.FullName -ExemplarPath $resolvedDamagedExemplar -CandidateYs $CandidateCropYs -ExemplarYs $DamagedExemplarRows)
    } else {
        @()
    }
    [pscustomobject]@{
        Screenshot = $shot.Name
        Seconds = $(if ((Get-ScreenshotSecond $shot.Name) -eq [int]::MaxValue) { $null } else { Get-ScreenshotSecond $shot.Name })
        Bytes = $shot.Length
        CropY = $bestMatch.CandidateY
        GoodDiff = $bestMatch.GoodDiff
        BadDiff = $bestMatch.BadDiff
        TextBrightRatio = $bestMatch.TextBrightRatio
        Target = $bestMatch.Target
        PathCandidateYs = @($bestMatch.PathCandidateYs) -join ","
        DebugCandidateYs = @($bestMatch.DebugCandidateYs) -join ","
        TopPathOnly = [bool]$bestMatch.TopPathOnly
        LowerCursorYs = $lowerCursorRows -join ","
        DamagedTextYs = $damagedTextRows -join ","
    }
}

$pathRows = @($rows | Where-Object { $_.Target -eq "path-to-tenuto" })
$debugRows = @($rows | Where-Object { $_.Target -eq "debug-save-prologue" })
$emptyRows = @($rows | Where-Object { $_.Target -eq "empty-load-slot" })
$unknownRows = @($rows | Where-Object { $_.Target -eq "unknown-load-target" })
$lowerCursorRows = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.LowerCursorYs) })
$damagedTextRows = @($rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.DamagedTextYs) })
$damagedRows = @($rows | Where-Object {
        $_.Target -eq "path-to-tenuto" -and (
            ($_.TopPathOnly -and -not [string]::IsNullOrWhiteSpace($_.LowerCursorYs)) -or
            (-not [string]::IsNullOrWhiteSpace($_.LowerCursorYs) -and -not [string]::IsNullOrWhiteSpace($_.DamagedTextYs))
        )
    })
$status = if ($damagedRows.Count -gt 0) {
    "DAMAGED_SAVE_TARGET"
} elseif ($pathRows.Count -gt 0 -and $debugRows.Count -eq 0) {
    "PATH_TO_TENUTO_PRESENT"
} elseif ($debugRows.Count -gt 0 -and $pathRows.Count -eq 0) {
    "DEBUG_SAVE_PROLOGUE_PRESENT"
} elseif ($pathRows.Count -gt 0 -and $debugRows.Count -gt 0) {
    "MIXED_LOAD_TARGETS"
} else {
    "UNKNOWN_LOAD_TARGET"
}

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# Eternal Sonata Load Target Classifier")
$summary.Add("")
$summary.Add(("- Run directory: ``{0}``" -f $resolvedRunDir))
$summary.Add(("- Screenshot directory: ``{0}``" -f $screenshotDir))
$summary.Add(("- Method: stable Load-list crop comparison across visible save rows plus lower-row cursor-marker and damaged-save text detection, not OCR."))
$summary.Add(("- Path-to-Tenuto exemplar: ``{0}``" -f $resolvedGoodExemplar))
if ($badGuardEnabled) {
    $summary.Add(("- Debug-Save exemplar: ``{0}``" -f $resolvedBadExemplar))
} else {
    $summary.Add(("- Debug-Save exemplar: disabled; no existing fallback found from ``{0}``." -f $BadExemplar))
}
$summary.Add(("- Crop reference: x={0}, y={1}, width={2}, height={3} on 1296x759 screenshots." -f $CropX, $CropY, $CropWidth, $CropHeight))
$summary.Add(("- Candidate crop Y rows: ``{0}``." -f ($CandidateCropYs -join ", ")))
$summary.Add(("- Decision margin: ``{0}``; max known diff: ``{1}``." -f $DecisionMargin, $MaxKnownDiff))
$summary.Add(("- Loose lower-row Path-to-Tenuto margin: ``{0}``; loose max diff: ``{1}``." -f $LoosePathDecisionMargin, $LoosePathMaxDiff))
$summary.Add(("- Empty-slot guard: bright-text ratio below ``{0}`` with best known diff <= ``{1}``." -f $MinLoadTargetTextBrightRatio, $MaxEmptyKnownDiff))
if ($damagedGuardEnabled) {
    $summary.Add(("- Damaged-save text guard: exemplar ``{0}``, rows ``{1}``, max diff ``{2}``." -f $resolvedDamagedExemplar, ($DamagedExemplarRows -join ", "), $DamagedTextMaxDiff))
} else {
    $summary.Add(("- Damaged-save text guard: disabled; exemplar not found at ``{0}``." -f $resolvedDamagedExemplar))
}
$summary.Add(("- Status: ``{0}``" -f $status))
$summary.Add(("- Counts: path-to-tenuto={0}, debug-save-prologue={1}, empty-load-slot={2}, unknown={3}." -f $pathRows.Count, $debugRows.Count, $emptyRows.Count, $unknownRows.Count))
$summary.Add(("- Lower-row cursor markers: ``{0}`` screenshot(s)." -f $lowerCursorRows.Count))
$summary.Add(("- Damaged-save text markers: ``{0}`` screenshot(s)." -f $damagedTextRows.Count))
if ($damagedRows.Count -gt 0) {
    $summary.Add(("- Damaged target guard: ``{0}`` Path-to-Tenuto preview row(s) had lower-row cursor drift and/or damaged-save text markers." -f $damagedRows.Count))
}
$summary.Add("")
$summary.Add("| Screenshot | Seconds | Bytes | Crop Y | Good diff | Bad diff | Text bright | Path Ys | Debug Ys | Top path only | Lower cursor Ys | Damaged text Ys | Target |")
$summary.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |")
foreach ($row in $rows) {
    $seconds = if ($null -eq $row.Seconds) { "" } else { $row.Seconds }
    $summary.Add(("| ``{0}`` | {1} | {2} | {3} | {4:N3} | {5:N3} | {6:N4} | ``{7}`` | ``{8}`` | ``{9}`` | ``{10}`` | ``{11}`` | ``{12}`` |" -f $row.Screenshot, $seconds, $row.Bytes, $row.CropY, $row.GoodDiff, $row.BadDiff, $row.TextBrightRatio, $row.PathCandidateYs, $row.DebugCandidateYs, $row.TopPathOnly, $row.LowerCursorYs, $row.DamagedTextYs, $row.Target))
}

$outPath = Join-Path $resolvedRunDir "eternal-sonata-load-target-summary.md"
if (-not $NoWriteSummary) {
    [System.IO.File]::WriteAllLines($outPath, $summary, [System.Text.UTF8Encoding]::new($false))
}

$summary | Write-Output
if (-not $NoWriteSummary) {
    Write-Output ""
    Write-Output ("Summary: {0}" -f $outPath)
}

if ($RequirePathToTenuto -and $status -ne "PATH_TO_TENUTO_PRESENT") {
    throw "Load target gate failed: expected only Path to Tenuto, got $status."
}
