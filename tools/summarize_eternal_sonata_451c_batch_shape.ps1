[CmdletBinding()]
param(
    [string]$RunDir = "",

    [string]$DescBatchCsvPath = "",

    [string]$ListFamilyCsvPath = "",

    [string]$OutPath = "",

    [string]$CsvPath = "",

    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-RunPath {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    $root = Join-Path (Get-RepoRoot) "debug-captures\windows-lab"
    $latest = Get-ChildItem -LiteralPath $root -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-spu-hle-451c-desc-batch-profile.csv") -PathType Leaf } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No recent run with eternal-sonata-spu-hle-451c-desc-batch-profile.csv found under $root"
    }

    return $latest.FullName
}

function Format-Bytes {
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

function Format-Percent {
    param(
        [double]$Part,
        [double]$Whole
    )

    if ($Whole -eq 0.0) {
        return "0.00%"
    }
    return ("{0:N2}%" -f (100.0 * $Part / $Whole))
}

function To-UInt64Safe {
    param([object]$Value)

    if ($null -eq $Value) {
        return [UInt64]0
    }

    $text = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [UInt64]0
    }

    $number = [UInt64]0
    if ([UInt64]::TryParse($text, [ref]$number)) {
        return $number
    }
    return [UInt64]0
}

function Add-Total {
    param(
        [hashtable]$Totals,
        [object]$Row,
        [string]$Key
    )

    if (-not $Totals.ContainsKey($Key)) {
        $Totals[$Key] = [UInt64]0
    }
    $Totals[$Key] = [UInt64]($Totals[$Key] + (To-UInt64Safe $Row.$Key))
}

$resolvedRunDir = Resolve-RunPath $RunDir
if ([string]::IsNullOrWhiteSpace($DescBatchCsvPath)) {
    $DescBatchCsvPath = Join-Path $resolvedRunDir "eternal-sonata-spu-hle-451c-desc-batch-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($ListFamilyCsvPath)) {
    $ListFamilyCsvPath = Join-Path $resolvedRunDir "eternal-sonata-spu-hle-451c-list-family-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $resolvedRunDir "eternal-sonata-451c-batch-shape-summary.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $resolvedRunDir "eternal-sonata-451c-batch-shape-families.csv"
}

if (-not (Test-Path -LiteralPath $DescBatchCsvPath -PathType Leaf)) {
    throw "Descriptor-batch CSV not found: $DescBatchCsvPath"
}

$descRows = @(Import-Csv -LiteralPath $DescBatchCsvPath)
$listRows = @()
if (Test-Path -LiteralPath $ListFamilyCsvPath -PathType Leaf) {
    $listRows = @(Import-Csv -LiteralPath $ListFamilyCsvPath)
}

$familyDefs = @(
    [pscustomobject]@{ Id = 1; Name = "tag1_size8";  Tag = 1; Size = 8;  BatchKey = "family1_calls"; ListKey = "tag1_size8_hits";  PreserveGroupKey = "preserve_family1_groups"; PreserveDescKey = "preserve_family1_desc"; PreserveBytesKey = "preserve_family1_bytes" },
    [pscustomobject]@{ Id = 2; Name = "tag0_size8";  Tag = 0; Size = 8;  BatchKey = "family2_calls"; ListKey = "tag0_size8_hits";  PreserveGroupKey = "preserve_family2_groups"; PreserveDescKey = "preserve_family2_desc"; PreserveBytesKey = "preserve_family2_bytes" },
    [pscustomobject]@{ Id = 3; Name = "tag0_size16"; Tag = 0; Size = 16; BatchKey = "family3_calls"; ListKey = "tag0_size16_hits"; PreserveGroupKey = "preserve_family3_groups"; PreserveDescKey = "preserve_family3_desc"; PreserveBytesKey = "preserve_family3_bytes" },
    [pscustomobject]@{ Id = 4; Name = "tag1_size16"; Tag = 1; Size = 16; BatchKey = "family4_calls"; ListKey = "tag1_size16_hits"; PreserveGroupKey = "preserve_family4_groups"; PreserveDescKey = "preserve_family4_desc"; PreserveBytesKey = "preserve_family4_bytes" },
    [pscustomobject]@{ Id = 5; Name = "tag1_size24"; Tag = 1; Size = 24; BatchKey = "family5_calls"; ListKey = "tag1_size24_hits"; PreserveGroupKey = "preserve_family5_groups"; PreserveDescKey = "preserve_family5_desc"; PreserveBytesKey = "preserve_family5_bytes" },
    [pscustomobject]@{ Id = 6; Name = "tag0_size24"; Tag = 0; Size = 24; BatchKey = "family6_calls"; ListKey = "tag0_size24_hits"; PreserveGroupKey = "preserve_family6_groups"; PreserveDescKey = "preserve_family6_desc"; PreserveBytesKey = "preserve_family6_bytes" }
)

$totals = @{}
foreach ($key in @(
    "calls", "desc_bytes", "fetch_groups", "fast_groups", "fast_desc",
    "slow_desc", "nonzero_desc", "zero_desc", "stall_desc",
    "inline_get_desc", "inline_put_desc", "dma_desc",
    "preserve_groups", "preserve_single_groups", "preserve_multi_groups",
    "preserve_full_groups", "preserve_partial_groups", "preserve_desc",
    "preserve_bytes", "preserve_zero_stops", "preserve_stall_stops",
    "preserve_raw_stops",
    "size16_candidate_groups", "size16_candidate_desc", "size16_candidate_bytes",
    "size16_candidate_family3_groups", "size16_candidate_family3_desc", "size16_candidate_family3_bytes",
    "size16_candidate_family4_groups", "size16_candidate_family4_desc", "size16_candidate_family4_bytes",
    "size16_body_groups", "size16_body_desc", "size16_body_bytes",
    "size16_body_family3_groups", "size16_body_family3_desc", "size16_body_family3_bytes",
    "size16_body_family4_groups", "size16_body_family4_desc", "size16_body_family4_bytes",
    "size16_reject_groups", "size16_reject_single_groups", "size16_reject_partial_groups",
    "size16_reject_stop_groups"
)) {
    $totals[$key] = [UInt64]0
}

foreach ($row in $descRows) {
    foreach ($key in @($totals.Keys)) {
        Add-Total -Totals $totals -Row $row -Key $key
    }
}

$familyRows = foreach ($family in $familyDefs) {
    $batchCalls = [UInt64]0
    $preserveGroups = [UInt64]0
    $preserveDesc = [UInt64]0
    $preserveBytes = [UInt64]0
    foreach ($row in $descRows) {
        $batchCalls += To-UInt64Safe $row.($family.BatchKey)
        $preserveGroups += To-UInt64Safe $row.($family.PreserveGroupKey)
        $preserveDesc += To-UInt64Safe $row.($family.PreserveDescKey)
        $preserveBytes += To-UInt64Safe $row.($family.PreserveBytesKey)
    }

    $listHits = [UInt64]0
    $listSuccess = [UInt64]0
    $listFail = [UInt64]0
    $listDescBytes = [UInt64]0
    $listTotalUs = [double]0.0
    $listMaxUs = [UInt64]0

    foreach ($row in $listRows) {
        $familyHits = To-UInt64Safe $row.($family.ListKey)
        $rowHits = To-UInt64Safe $row.hits
        $listHits += $familyHits
        $listSuccess += To-UInt64Safe $row.success
        $listFail += To-UInt64Safe $row.fail
        $listDescBytes += [UInt64]($familyHits * [UInt64]$family.Size)

        if ($familyHits -gt 0 -and $rowHits -gt 0) {
            $listTotalUs += [double](To-UInt64Safe $row.total_us) * ([double]$familyHits / [double]$rowHits)
            $rowMax = To-UInt64Safe $row.max_total_us
            if ($rowMax -gt $listMaxUs) {
                $listMaxUs = $rowMax
            }
        }
    }

    $listTotalUsRounded = [UInt64][Math]::Round($listTotalUs)
    $exactPreserve = $preserveGroups -gt 0 -or $preserveDesc -gt 0 -or $preserveBytes -gt 0
    $shapeGroups = if ($exactPreserve) { $preserveGroups } else { $batchCalls }
    $shapeDesc = if ($exactPreserve) { $preserveDesc } else { $listHits }
    $shapeBytes = if ($exactPreserve) { $preserveBytes } else { [UInt64]($listHits * [UInt64]$family.Size) }

    [pscustomobject]@{
        Family = $family.Name
        Id = $family.Id
        Tag = $family.Tag
        Size = $family.Size
        BatchCalls = $shapeGroups
        BatchShare = Format-Percent ([double]$shapeGroups) ([double]$totals["preserve_groups"])
        PreserveDesc = $shapeDesc
        ListHits = $listHits
        HitShare = Format-Percent ([double]$listHits) ([double]($listRows | ForEach-Object { To-UInt64Safe $_.hits } | Measure-Object -Sum).Sum)
        ListDescBytesRaw = $shapeBytes
        ListDescBytes = Format-Bytes $shapeBytes
        TotalUs = $listTotalUsRounded
        TotalMs = ("{0:N3}" -f ($listTotalUs / 1000.0))
        AvgUsPerHit = if ($listHits -gt 0) { "{0:N3}" -f ($listTotalUs / [double]$listHits) } else { "0.000" }
        MaxUs = $listMaxUs
        ExactPreserve = $exactPreserve
    }
}

$familyRows = @($familyRows | Sort-Object BatchCalls -Descending)

$preserveGroups = $totals["preserve_groups"]
$preserveDesc = $totals["preserve_desc"]
$preserveBytes = $totals["preserve_bytes"]
$avgDescPerGroup = if ($preserveGroups -gt 0) { [double]$preserveDesc / [double]$preserveGroups } else { 0.0 }
$avgBytesPerGroup = if ($preserveGroups -gt 0) { [double]$preserveBytes / [double]$preserveGroups } else { 0.0 }
$multiShare = Format-Percent ([double]$totals["preserve_multi_groups"]) ([double]$preserveGroups)
$fullShare = Format-Percent ([double]$totals["preserve_full_groups"]) ([double]$preserveGroups)
$zeroStopShare = Format-Percent ([double]$totals["preserve_zero_stops"]) ([double]$preserveGroups)
$inlineGetShare = Format-Percent ([double]$totals["inline_get_desc"]) ([double]$totals["nonzero_desc"])
$size16CandidateGroups = $totals["size16_candidate_groups"]
$size16CandidateDesc = $totals["size16_candidate_desc"]
$size16CandidateBytes = $totals["size16_candidate_bytes"]
$size16CandidateShare = Format-Percent ([double]$size16CandidateGroups) ([double]$preserveGroups)
$size16CandidateDescShare = Format-Percent ([double]$size16CandidateDesc) ([double]$preserveDesc)
$size16RejectGroups = $totals["size16_reject_groups"]
$size16BodyGroups = $totals["size16_body_groups"]
$size16BodyDesc = $totals["size16_body_desc"]
$size16BodyBytes = $totals["size16_body_bytes"]
$size16BodyCandidateShare = Format-Percent ([double]$size16BodyGroups) ([double]$size16CandidateGroups)
$size16BodyDescShare = Format-Percent ([double]$size16BodyDesc) ([double]$size16CandidateDesc)

$topFamily = $familyRows | Select-Object -First 1
$md = [System.Collections.Generic.List[string]]::new()
$md.Add("# Eternal Sonata 0x451c Batch-Shape Summary")
$md.Add("")
$md.Add(("- Generated: {0}" -f (Get-Date).ToString("o")))
$md.Add(("- Run directory: {0}" -f $resolvedRunDir))
$md.Add(("- Descriptor-batch CSV: {0}" -f $DescBatchCsvPath))
$md.Add(("- List-family CSV: {0}" -f $ListFamilyCsvPath))
$md.Add("")
$md.Add("## Reading")
$md.Add("")
$md.Add(("- Preserve-order groups: {0}; descriptors: {1}; bytes: {2}." -f $preserveGroups, $preserveDesc, (Format-Bytes $preserveBytes)))
$md.Add(("- Average preserve descriptors/group: {0:N3}; average bytes/group: {1}." -f $avgDescPerGroup, (Format-Bytes ([UInt64][Math]::Round($avgBytesPerGroup)))))
$md.Add(("- Multi-descriptor groups: {0} ({1}); full groups: {2} ({3}); zero stops: {4} ({5})." -f $totals["preserve_multi_groups"], $multiShare, $totals["preserve_full_groups"], $fullShare, $totals["preserve_zero_stops"], $zeroStopShare))
$md.Add(("- Nonzero descriptor split: inline GET {0}/{1} ({2}), inline PUT {3}, DMA fallback {4}." -f $totals["inline_get_desc"], $totals["nonzero_desc"], $inlineGetShare, $totals["inline_put_desc"], $totals["dma_desc"]))
if (($size16CandidateGroups -gt 0) -or ($size16RejectGroups -gt 0)) {
    $md.Add(("- Size-16 full-batch candidates: {0} groups ({1} of preserve groups), {2} descriptors ({3} of preserve descriptors), {4}; rejects: {5} groups (single={6}, partial={7}, stop={8})." -f $size16CandidateGroups, $size16CandidateShare, $size16CandidateDesc, $size16CandidateDescShare, (Format-Bytes $size16CandidateBytes), $size16RejectGroups, $totals["size16_reject_single_groups"], $totals["size16_reject_partial_groups"], $totals["size16_reject_stop_groups"]))
    $md.Add(("- Size-16 family split: tag0_size16={0} groups / {1} desc / {2}; tag1_size16={3} groups / {4} desc / {5}." -f $totals["size16_candidate_family3_groups"], $totals["size16_candidate_family3_desc"], (Format-Bytes $totals["size16_candidate_family3_bytes"]), $totals["size16_candidate_family4_groups"], $totals["size16_candidate_family4_desc"], (Format-Bytes $totals["size16_candidate_family4_bytes"])))
}
if ($size16BodyGroups -gt 0) {
    $md.Add(("- Size-16 verify body executed: {0} groups ({1} of size-16 candidates), {2} descriptors ({3} of candidate descriptors), {4}." -f $size16BodyGroups, $size16BodyCandidateShare, $size16BodyDesc, $size16BodyDescShare, (Format-Bytes $size16BodyBytes)))
    $md.Add(("- Size-16 body family split: tag0_size16={0} groups / {1} desc / {2}; tag1_size16={3} groups / {4} desc / {5}." -f $totals["size16_body_family3_groups"], $totals["size16_body_family3_desc"], (Format-Bytes $totals["size16_body_family3_bytes"]), $totals["size16_body_family4_groups"], $totals["size16_body_family4_desc"], (Format-Bytes $totals["size16_body_family4_bytes"])))
}
if ($topFamily) {
    $md.Add(("- Top preserve-order family by batch calls: {0} with {1} calls ({2}), list hits {3}, estimated timing {4} ms." -f $topFamily.Family, $topFamily.BatchCalls, $topFamily.BatchShare, $topFamily.ListHits, $topFamily.TotalMs))
}
$md.Add("- Batch-shape verdict: this is a CPU/SPU HLE/codegen target for a verify-only preserve-order batch path. It is not copy-elision, not GPU migration credit, and not speed proof.")
$md.Add("- GPU compute remains parked for this bucket until a scout proves RSX-consumed data or a GPU-resident consumer; current descriptor evidence is CPU-side DMA/list-control work.")
if (($familyRows | Where-Object { $_.ExactPreserve } | Measure-Object).Count -gt 0) {
    $md.Add("- Per-family preserve groups/descriptors/bytes use exact verifier fields from the descriptor-batch log.")
} else {
    $md.Add("- Per-family timing is hit-weighted from mixed-family rows; descriptor bytes are estimated from family descriptor-size counts until exact preserve-family fields are present.")
}
$md.Add("")
$md.Add("## Family Table")
$md.Add("")
$md.Add("| Family | Tag | Size | Batch calls | Batch share | List hits | Hit share | Desc bytes | Est ms | Est us/hit | Max row us |")
$md.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
foreach ($family in $familyRows) {
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f $family.Family, $family.Tag, $family.Size, $family.BatchCalls, $family.BatchShare, $family.ListHits, $family.HitShare, $family.ListDescBytes, $family.TotalMs, $family.AvgUsPerHit, $family.MaxUs))
}
$md.Add("")
$md.Add("## Verifier Design Notes")
$md.Add("")
$md.Add("- Gate on title BLUS30161, image 0x958dfe208b686622, SPU PC 0x451c, command 0x46, and the six tag/size families above.")
$md.Add("- Preserve all destination writes and DMA ordering. A batch path can only reduce descriptor/control overhead after verify mode proves stock-equivalent results.")
$md.Add("- Prioritize size-16 multi-descriptor full groups first when the candidate counters are present; single/partial/stop groups stay on the stock path.")
$md.Add("- Keep fast mode disabled until a matched Windows A/B shows clean field, menu/Options, first-battle visuals, and a measurable timing or CPU-load reduction.")
$md.Add("")
$md.Add("## Classification")
$md.Add("")
$md.Add("- analysis, harness-tooling, spu-hle-codegen-targeting, not windows-micro-win, not gpu-migration-credit, not a 200% gate candidate.")

if (-not $NoWrite) {
    [System.IO.File]::WriteAllLines($OutPath, $md, [System.Text.UTF8Encoding]::new($false))
    $familyRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$md | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
