param(
    [string]$PatternCsvPath = "",
    [string]$RunDir = "",
    [string]$OutPath = "",
    [string]$OutCsvPath = "",
    [int]$Top = 16,
    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Convert-Number {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [UInt64]0
    }

    $text = $Value.Trim()
    if ($text -match '^0x([0-9a-fA-F]+)$') {
        return [Convert]::ToUInt64($Matches[1], 16)
    }

    return [Convert]::ToUInt64($text, 10)
}

function Format-Bytes {
    param([UInt64]$Value)

    if ($Value -ge 1GB) {
        return ("{0:N2} GB" -f ([double]$Value / 1GB))
    }
    if ($Value -ge 1MB) {
        return ("{0:N2} MB" -f ([double]$Value / 1MB))
    }
    if ($Value -ge 1KB) {
        return ("{0:N1} KB" -f ([double]$Value / 1KB))
    }
    return ("{0} B" -f $Value)
}

function Format-Percent {
    param(
        [UInt64]$Numerator,
        [UInt64]$Denominator
    )

    if ($Denominator -eq 0) {
        return "0.0%"
    }

    return ("{0:N1}%" -f (([double]$Numerator / [double]$Denominator) * 100.0))
}

function Get-Sum {
    param(
        [object[]]$Rows,
        [string]$Property
    )

    if ($Rows.Count -eq 0) {
        return [UInt64]0
    }

    $sum = ($Rows | Measure-Object -Property $Property -Sum).Sum
    if ($null -eq $sum) {
        return [UInt64]0
    }

    return [UInt64]$sum
}

$repoRoot = Resolve-RepoPath (Join-Path $PSScriptRoot "..")
$windowsLabRoot = Join-Path $repoRoot "debug-captures\windows-lab"

if ([string]::IsNullOrWhiteSpace($PatternCsvPath)) {
    $PatternCsvPath = Join-Path $repoRoot "debug-experiments\20260526-25cc-pattern-family.csv"
}

if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $latest = Get-ChildItem -LiteralPath $windowsLabRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-25cc-runtime-family-patterns.csv") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-spu-hle-25cc-shadow-profile.csv") -PathType Leaf)
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No Windows run with 25cc runtime pattern and shadow CSVs found under $windowsLabRoot"
    }

    $RunDir = $latest.FullName
}

$PatternCsvPath = Resolve-RepoPath $PatternCsvPath
$RunDir = Resolve-RepoPath $RunDir
$runtimePatternCsv = Join-Path $RunDir "eternal-sonata-25cc-runtime-family-patterns.csv"
$shadowCsv = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-shadow-profile.csv"

if (-not (Test-Path -LiteralPath $PatternCsvPath -PathType Leaf)) {
    throw "Missing pattern CSV: $PatternCsvPath"
}
if (-not (Test-Path -LiteralPath $runtimePatternCsv -PathType Leaf)) {
    throw "Missing runtime pattern CSV: $runtimePatternCsv"
}
if (-not (Test-Path -LiteralPath $shadowCsv -PathType Leaf)) {
    throw "Missing shadow CSV: $shadowCsv"
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $repoRoot "debug-experiments\20260526-25cc-pattern-hash-targets.md"
}
if ([string]::IsNullOrWhiteSpace($OutCsvPath)) {
    $OutCsvPath = Join-Path $repoRoot "debug-experiments\20260526-25cc-pattern-hash-targets.csv"
}

$atlasRows = @(Import-Csv -LiteralPath $PatternCsvPath | Where-Object {
    $_.Ea -eq "0x9e4000" -and
    $_.MaxDmaSize -eq "16384" -and
    $_.OffloadFit -eq "spu-kernel-hle"
})
$runtimeRows = @(Import-Csv -LiteralPath $runtimePatternCsv | Where-Object {
    $_.max_dma_ea -eq "0x9e4000" -and
    $_.max_dma_size -eq "16384" -and
    $_.candidate -eq "hle-pattern-body-candidate"
})
$shadowRows = @(Import-Csv -LiteralPath $shadowCsv)

$runtimeByPattern = @{}
foreach ($row in $runtimeRows) {
    $runtimeByPattern[$row.pattern_sig] = $row
}

$atlasTotalBytes = Get-Sum $atlasRows "TotalBytes"
$runtimeTotalBytes = Get-Sum $runtimeRows "total_bytes"
$matchedAtlasBytes = [UInt64]0
$matchedRuntimeBytes = [UInt64]0
$matchedRows = 0

$targets = @()
$rank = 1
foreach ($atlas in @($atlasRows | Sort-Object { Convert-Number $_.TotalBytes } -Descending | Select-Object -First $Top)) {
    $runtime = $runtimeByPattern[$atlas.Pattern]
    $runtimeSeen = $null -ne $runtime
    $runtimeBytes = if ($runtimeSeen) { Convert-Number $runtime.total_bytes } else { [UInt64]0 }
    $runtimeGet = if ($runtimeSeen) { Convert-Number $runtime.get_bytes } else { [UInt64]0 }
    $runtimePut = if ($runtimeSeen) { Convert-Number $runtime.put_bytes } else { [UInt64]0 }
    $runtimeRecords = if ($runtimeSeen) { Convert-Number $runtime.records } else { [UInt64]0 }
    $runtimeMaxCmd = if ($runtimeSeen) { Convert-Number $runtime.max_cmd_count } else { [UInt64]0 }
    $putShare = Format-Percent $runtimePut $runtimeBytes
    $getShare = Format-Percent $runtimeGet $runtimeBytes
    $bodyGap = if (-not $runtimeSeen) {
        "not-seen-in-latest-shadow-run"
    } elseif ($runtimePut -gt ($runtimeGet * 3)) {
        "put-heavy-get-only-body-caps-coverage"
    } elseif ($runtimePut -gt $runtimeGet) {
        "put-skew-verify-before-body"
    } else {
        "balanced-or-get-skew"
    }

    if ($runtimeSeen) {
        $matchedRows++
        $matchedAtlasBytes += Convert-Number $atlas.TotalBytes
        $matchedRuntimeBytes += $runtimeBytes
    }

    $targets += [pscustomobject]@{
        rank = $rank
        pattern_sig = $atlas.Pattern
        runtime_seen = $runtimeSeen
        atlas_records = Convert-Number $atlas.Records
        atlas_runs_seen = Convert-Number $atlas.RunsSeen
        atlas_total_bytes = Convert-Number $atlas.TotalBytes
        atlas_share = $atlas.ShareOf25cc
        atlas_cmd_count = Convert-Number $atlas.CmdCount
        runtime_records = $runtimeRecords
        runtime_total_bytes = $runtimeBytes
        runtime_get_bytes = $runtimeGet
        runtime_put_bytes = $runtimePut
        runtime_get_share = $getShare
        runtime_put_share = $putShare
        runtime_max_cmd_count = $runtimeMaxCmd
        body_gap = $bodyGap
        hash_gate = "family+direction+lsa+eal+src_hash+dst_pre_hash+dst_post_hash+output_match"
        next_probe = "aggregate shadow hashes by pattern/descriptor, not only by exact eal bucket"
    }
    $rank++
}

$shadowHits = Get-Sum $shadowRows "hits"
$shadowBytes = Get-Sum $shadowRows "bytes"
$shadowGet = Get-Sum $shadowRows "get_hits"
$shadowPut = Get-Sum $shadowRows "put_hits"
$shadowChanged = Get-Sum $shadowRows "dst_changed"
$shadowUnchanged = Get-Sum $shadowRows "dst_unchanged"
$shadowMatch = Get-Sum $shadowRows "output_match"
$shadowMismatch = Get-Sum $shadowRows "output_mismatch"
$shadowEa9 = Get-Sum $shadowRows "ea9e4000_hits"
$shadowExact = Get-Sum $shadowRows "exact_a1c000_hits"
$shadowOther = Get-Sum $shadowRows "other_ea_hits"

if (-not $NoWrite) {
    $targets | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Encoding UTF8
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Pattern Hash Targets")
$lines.Add("")
$lines.Add("- Generated: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz"))")
$lines.Add('- Classification: `analysis`, `spu-hle-25cc-pattern-hash-targets`.')
$lines.Add("- Not speed.")
$lines.Add('- Not `gpu-migration-credit`.')
$lines.Add("- Not a 200% moving-gameplay gate candidate.")
$lines.Add("")
$lines.Add("## Inputs")
$lines.Add("")
$lines.Add(("- Atlas CSV: ``{0}``" -f $PatternCsvPath))
$lines.Add(("- Latest shadow run: ``{0}``" -f $RunDir))
$lines.Add(("- Runtime pattern CSV: ``{0}``" -f $runtimePatternCsv))
$lines.Add(("- Shadow CSV: ``{0}``" -f $shadowCsv))
$lines.Add(("- Target CSV: ``{0}``" -f $OutCsvPath))
$lines.Add("")
$lines.Add("## Summary")
$lines.Add("")
$lines.Add("- Atlas ``0x9e4000`` HLE candidates: $($atlasRows.Count) groups, $(Format-Bytes $atlasTotalBytes).")
$lines.Add("- Latest shadow-run runtime candidates: $($runtimeRows.Count) groups, $(Format-Bytes $runtimeTotalBytes).")
$lines.Add("- Top-$Top atlas groups seen in latest shadow run: $matchedRows groups, $(Format-Bytes $matchedAtlasBytes) atlas bytes, $(Format-Bytes $matchedRuntimeBytes) latest-run bytes.")
$lines.Add("- Shadow verifier: $shadowHits hits, $(Format-Bytes $shadowBytes), GET/PUT $shadowGet/$shadowPut, changed/unchanged $shadowChanged/$shadowUnchanged, match/mismatch $shadowMatch/$shadowMismatch.")
$lines.Add("- Exact EA buckets remain too narrow: ea9e4000=$shadowEa9, exact_a1c000=$shadowExact, other_matching_ea=$shadowOther.")
$lines.Add("")
$lines.Add("## Top Hash Targets")
$lines.Add("")
$lines.Add("| Rank | Pattern | Runtime | Atlas Records | Atlas Bytes | Atlas Share | Runtime Records | Runtime Bytes | GET Share | PUT Share | Max Cmds | Body Gap |")
$lines.Add("| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |")
foreach ($target in $targets) {
    $runtimeText = if ($target.runtime_seen) { "yes" } else { "no" }
    $lines.Add(("| {0} | ``{1}`` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | ``{11}`` |" -f $target.rank, $target.pattern_sig, $runtimeText, $target.atlas_records, (Format-Bytes $target.atlas_total_bytes), $target.atlas_share, $target.runtime_records, (Format-Bytes $target.runtime_total_bytes), $target.runtime_get_share, $target.runtime_put_share, $target.runtime_max_cmd_count, $target.body_gap))
}
$lines.Add("")
$lines.Add("## Reading")
$lines.Add("")
$lines.Add("- Several high-ranked repeated groups are visible in both the multi-run atlas and latest shadow run, enough to make the next step a verifier/instrumentation change rather than another route scout.")
$lines.Add('- The matched latest-run rows are strongly PUT-heavy. The current `0x25cc` body copy fast path only accepts GET, so a GET-only body cannot cover the main bytes in these groups.')
$lines.Add('- Pattern signature should remain a scout key, not the only fast predicate. The safe verifier key needs title `BLUS30161`, image `0x958dfe208b686622`, PC `0x25cc`, tag `31`, size `0x4000`, MFC direction, LSA, EAL, source hash, destination-before hash, destination-after hash, and output-match status.')
$lines.Add("- Broad SPU-to-Vulkan compute remains parked because these rows still report zero RSX-local bytes and tiny one-job dispatch risk.")
$lines.Add("")
$lines.Add("## Next Implementation Slice")
$lines.Add("")
$lines.Add('- Extend the runtime `0x25cc` shadow verifier to aggregate rows by pattern/descriptor plus direction, not just exact command-level EA buckets.')
$lines.Add("- Emit GET and PUT hash summaries separately for the top target groups, including changed/unchanged and output-match/mismatch.")
$lines.Add("- Keep fast/body mode off until the pattern-level verifier is clean in field, menu/Options, and first battle.")

if (-not $NoWrite) {
    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
}

$lines | Write-Output

if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $OutCsvPath)
}
