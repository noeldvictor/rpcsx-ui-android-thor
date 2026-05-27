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
        [double]$BadDiff
    )

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

function Get-BestTargetMatch {
    param(
        [string]$CandidatePath,
        [string]$GoodExemplarPath,
        [string]$BadExemplarPath,
        [int[]]$CropYs
    )

    $matches = foreach ($candidateY in $CropYs) {
        $goodDiff = Get-RegionDiff -CandidatePath $CandidatePath -ExemplarPath $GoodExemplarPath -CandidateY $candidateY
        $badDiff = Get-RegionDiff -CandidatePath $CandidatePath -ExemplarPath $BadExemplarPath -CandidateY $candidateY
        $target = Get-TargetClass -GoodDiff $goodDiff -BadDiff $badDiff
        [pscustomobject]@{
            CandidateY = $candidateY
            GoodDiff = $goodDiff
            BadDiff = $badDiff
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

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot

if ([string]::IsNullOrWhiteSpace($GoodExemplar)) {
    $GoodExemplar = "debug-captures\windows-lab\20260526-001938-cpu4-stateaware-late-load-confirm-left200-visualgate-windows-windows\screenshots\screenshot-0117s.png"
}
if ([string]::IsNullOrWhiteSpace($BadExemplar)) {
    $BadExemplar = "debug-captures\windows-lab\20260526-003206-cpu4-stateaware-late-load-doubleconfirm-dismisssave-left200-visualgate-windows-windows\screenshots\screenshot-0118s.png"
}

$resolvedRunDir = Resolve-RepoPath -Root $repoRoot -Path $RunDir
$resolvedGoodExemplar = Resolve-RepoPath -Root $repoRoot -Path $GoodExemplar
$resolvedBadExemplar = Resolve-RepoPath -Root $repoRoot -Path $BadExemplar

if (-not (Test-Path -LiteralPath $resolvedRunDir -PathType Container)) {
    throw "Run directory not found: $resolvedRunDir"
}
if (-not (Test-Path -LiteralPath $resolvedGoodExemplar -PathType Leaf)) {
    throw "Path-to-Tenuto exemplar not found: $resolvedGoodExemplar"
}
if (-not (Test-Path -LiteralPath $resolvedBadExemplar -PathType Leaf)) {
    throw "Debug-Save exemplar not found: $resolvedBadExemplar"
}

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
    [pscustomobject]@{
        Screenshot = $shot.Name
        Seconds = $(if ((Get-ScreenshotSecond $shot.Name) -eq [int]::MaxValue) { $null } else { Get-ScreenshotSecond $shot.Name })
        Bytes = $shot.Length
        CropY = $bestMatch.CandidateY
        GoodDiff = $bestMatch.GoodDiff
        BadDiff = $bestMatch.BadDiff
        Target = $bestMatch.Target
        PathCandidateYs = @($bestMatch.PathCandidateYs) -join ","
        DebugCandidateYs = @($bestMatch.DebugCandidateYs) -join ","
        TopPathOnly = [bool]$bestMatch.TopPathOnly
    }
}

$pathRows = @($rows | Where-Object { $_.Target -eq "path-to-tenuto" })
$debugRows = @($rows | Where-Object { $_.Target -eq "debug-save-prologue" })
$unknownRows = @($rows | Where-Object { $_.Target -eq "unknown-load-target" })
$damagedRows = @($rows | Where-Object { $_.Target -eq "path-to-tenuto" -and $_.TopPathOnly })
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
$summary.Add(("- Method: stable Load-list crop comparison across visible save rows, not OCR."))
$summary.Add(("- Path-to-Tenuto exemplar: ``{0}``" -f $resolvedGoodExemplar))
$summary.Add(("- Debug-Save exemplar: ``{0}``" -f $resolvedBadExemplar))
$summary.Add(("- Crop reference: x={0}, y={1}, width={2}, height={3} on 1296x759 screenshots." -f $CropX, $CropY, $CropWidth, $CropHeight))
$summary.Add(("- Candidate crop Y rows: ``{0}``." -f ($CandidateCropYs -join ", ")))
$summary.Add(("- Decision margin: ``{0}``; max known diff: ``{1}``." -f $DecisionMargin, $MaxKnownDiff))
$summary.Add(("- Loose lower-row Path-to-Tenuto margin: ``{0}``; loose max diff: ``{1}``." -f $LoosePathDecisionMargin, $LoosePathMaxDiff))
$summary.Add(("- Status: ``{0}``" -f $status))
$summary.Add(("- Counts: path-to-tenuto={0}, debug-save-prologue={1}, unknown={2}." -f $pathRows.Count, $debugRows.Count, $unknownRows.Count))
if ($damagedRows.Count -gt 0) {
    $summary.Add(("- Damaged target guard: ``{0}`` top-only Path-to-Tenuto row(s) with no adjacent lower Path row." -f $damagedRows.Count))
}
$summary.Add("")
$summary.Add("| Screenshot | Seconds | Bytes | Crop Y | Good diff | Bad diff | Path Ys | Debug Ys | Top path only | Target |")
$summary.Add("| --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |")
foreach ($row in $rows) {
    $seconds = if ($null -eq $row.Seconds) { "" } else { $row.Seconds }
    $summary.Add(("| ``{0}`` | {1} | {2} | {3} | {4:N3} | {5:N3} | ``{6}`` | ``{7}`` | ``{8}`` | ``{9}`` |" -f $row.Screenshot, $seconds, $row.Bytes, $row.CropY, $row.GoodDiff, $row.BadDiff, $row.PathCandidateYs, $row.DebugCandidateYs, $row.TopPathOnly, $row.Target))
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
