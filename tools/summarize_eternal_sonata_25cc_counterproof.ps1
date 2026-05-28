[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir
)

$ErrorActionPreference = "Stop"

function Format-CounterBytes {
    param([UInt64]$Bytes)

    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0} B" -f $Bytes)
}

function Read-KvPairs {
    param([string]$Line)

    $result = @{}
    foreach ($match in [regex]::Matches($Line, '([A-Za-z0-9_]+)=("[^"]*"|\S+)')) {
        $value = $match.Groups[2].Value
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $result[$match.Groups[1].Value] = $value
    }
    return $result
}

function Get-U64 {
    param(
        [hashtable]$Map,
        [string]$Key
    )

    if (-not $Map.ContainsKey($Key) -or [string]::IsNullOrWhiteSpace($Map[$Key])) {
        return [UInt64]0
    }
    return [UInt64]$Map[$Key]
}

function New-Aggregate {
    param(
        [string]$Direction,
        [string]$RawCmd
    )

    return [ordered]@{
        Direction = $Direction
        RawCmd = $RawCmd
        Rows = [UInt64]0
        Hits = [UInt64]0
        Bytes = [UInt64]0
        OutputMatch = [UInt64]0
        OutputMismatch = [UInt64]0
        DstChanged = [UInt64]0
        DstUnchanged = [UInt64]0
        DescOverflowMax = [UInt64]0
        Patterns = @{}
    }
}

$root = [System.IO.Path]::GetFullPath($RunDir)
$logPath = Join-Path $root "RPCS3.log"
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "RPCS3 log not found: $logPath"
}

$visualSummaryPath = Join-Path $root "eternal-sonata-windows-visual-gate-summary.md"
$visualStatus = "missing"
$firstField = "missing"
if (Test-Path -LiteralPath $visualSummaryPath -PathType Leaf) {
    $visualLines = Get-Content -LiteralPath $visualSummaryPath
    $statusLine = $visualLines | Where-Object { $_ -match '^- Status:' } | Select-Object -First 1
    if ($statusLine -and $statusLine -match '`([^`]+)`') { $visualStatus = $matches[1] }
    $firstFieldLine = $visualLines | Where-Object { $_ -match '^- First field-like(?: screenshot)?:' } | Select-Object -First 1
    if ($firstFieldLine) { $firstField = ($firstFieldLine -replace '^- First field-like(?: screenshot)?:\s*', '').TrimEnd('.') }
}

$fatalPattern = 'VM: Access violation|VK_ERROR_DEVICE_LOST|Device lost|Assertion Failed|Thread terminated due to fatal error'
$fatalHits = 0
$fatalExamples = New-Object System.Collections.Generic.List[string]

$shadow = [ordered]@{
    Rows = [UInt64]0
    Hits = [UInt64]0
    Bytes = [UInt64]0
    GetHits = [UInt64]0
    PutHits = [UInt64]0
    OutputMatch = [UInt64]0
    OutputMismatch = [UInt64]0
    DstChanged = [UInt64]0
    DstUnchanged = [UInt64]0
}
$directions = @{}
$genericShadowMismatchLines = [UInt64]0
$genericShadowMismatchSum = [UInt64]0
$genericShadowMismatchPcs = @{}

foreach ($line in [System.IO.File]::ReadLines($logPath)) {
    if ($line -match $fatalPattern) {
        $fatalHits++
        if ($fatalExamples.Count -lt 5) {
            $fatalExamples.Add($line.Trim()) | Out-Null
        }
    }

    if ($line.Contains("Eternal Sonata SPU HLE shadow verifier:")) {
        $kv = Read-KvPairs $line
        $mismatch = Get-U64 $kv "output_mismatch"
        if ($mismatch -gt 0) {
            $genericShadowMismatchLines++
            $genericShadowMismatchSum += $mismatch
            $pc = if ($kv.ContainsKey("last_pc")) { $kv["last_pc"] } else { "unknown" }
            $genericShadowMismatchPcs[$pc] = $true
        }
    }

    if ($line.Contains("Eternal Sonata SPU HLE 25cc shadow verifier:")) {
        $kv = Read-KvPairs $line
        $shadow.Rows++
        $shadow.Hits += Get-U64 $kv "hits"
        $shadow.Bytes += Get-U64 $kv "bytes"
        $shadow.GetHits += Get-U64 $kv "get_hits"
        $shadow.PutHits += Get-U64 $kv "put_hits"
        $shadow.OutputMatch += Get-U64 $kv "output_match"
        $shadow.OutputMismatch += Get-U64 $kv "output_mismatch"
        $shadow.DstChanged += Get-U64 $kv "dst_changed"
        $shadow.DstUnchanged += Get-U64 $kv "dst_unchanged"
    }

    if ($line.Contains("Eternal Sonata SPU HLE 25cc shadow descriptor:")) {
        $kv = Read-KvPairs $line
        $rawCmd = if ($kv.ContainsKey("raw_cmd")) { $kv["raw_cmd"] } else { "unknown" }
        $directionValue = if ($kv.ContainsKey("direction")) { $kv["direction"] } else { "unknown" }
        $directionName = switch ($rawCmd) {
            "0x40" { "GET" }
            "0x20" { "PUT" }
            default {
                if ($directionValue -eq "1") { "GET" }
                elseif ($directionValue -eq "2") { "PUT" }
                else { "UNKNOWN" }
            }
        }
        $key = "$directionName/$rawCmd"
        if (-not $directions.ContainsKey($key)) {
            $directions[$key] = New-Aggregate -Direction $directionName -RawCmd $rawCmd
        }

        $agg = $directions[$key]
        $agg.Rows++
        $agg.Hits += Get-U64 $kv "hits"
        $agg.Bytes += Get-U64 $kv "bytes"
        $agg.OutputMatch += Get-U64 $kv "output_match"
        $agg.OutputMismatch += Get-U64 $kv "output_mismatch"
        $agg.DstChanged += Get-U64 $kv "dst_changed"
        $agg.DstUnchanged += Get-U64 $kv "dst_unchanged"
        $overflow = Get-U64 $kv "desc_overflow"
        if ($overflow -gt $agg.DescOverflowMax) { $agg.DescOverflowMax = $overflow }
        if ($kv.ContainsKey("pattern_sig")) { $agg.Patterns[$kv["pattern_sig"]] = $true }
    }
}

$directionRows = foreach ($key in ($directions.Keys | Sort-Object)) {
    $agg = $directions[$key]
    [pscustomobject]@{
        direction = $agg.Direction
        raw_cmd = $agg.RawCmd
        rows = $agg.Rows
        hits = $agg.Hits
        bytes = $agg.Bytes
        bytes_text = Format-CounterBytes $agg.Bytes
        output_match = $agg.OutputMatch
        output_mismatch = $agg.OutputMismatch
        dst_changed = $agg.DstChanged
        dst_unchanged = $agg.DstUnchanged
        desc_overflow_max = $agg.DescOverflowMax
        unique_patterns = $agg.Patterns.Count
    }
}

$descRows = [UInt64](($directionRows | Measure-Object -Property rows -Sum).Sum)
$descHits = [UInt64](($directionRows | Measure-Object -Property hits -Sum).Sum)
$descBytes = [UInt64](($directionRows | Measure-Object -Property bytes -Sum).Sum)
$descMismatch = [UInt64](($directionRows | Measure-Object -Property output_mismatch -Sum).Sum)
$descOverflow = [UInt64](($directionRows | Measure-Object -Property desc_overflow_max -Maximum).Maximum)
$putHits = [UInt64](($directionRows | Where-Object { $_.direction -eq "PUT" } | Measure-Object -Property hits -Sum).Sum)
$getHits = [UInt64](($directionRows | Where-Object { $_.direction -eq "GET" } | Measure-Object -Property hits -Sum).Sum)

$classification = if ($visualStatus -eq "FIELD_LIKE_PRESENT" -and $fatalHits -eq 0 -and $descRows -gt 0 -and $putHits -gt 0 -and $getHits -gt 0 -and $descMismatch -eq 0 -and $descOverflow -eq 0 -and $shadow.OutputMismatch -eq 0) {
    "valid-field-counterproof"
} elseif ($descRows -gt 0) {
    "partial-counterproof"
} else {
    "failed-counterproof"
}

$csvPath = Join-Path $root "eternal-sonata-25cc-counterproof-direction-summary.csv"
$directionRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$mdPath = Join-Path $root "eternal-sonata-25cc-counterproof-summary.md"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Counterproof") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Classification: ``$classification``.") | Out-Null
$lines.Add("- Run: ``$root``.") | Out-Null
$lines.Add("- Visual status: ``$visualStatus``; first field-like: $firstField.") | Out-Null
$lines.Add("- Targeted fatal/access/device-lost/assertion hits: ``$fatalHits``.") | Out-Null
$lines.Add("- 25cc shadow verifier: ``$($shadow.Hits)`` hits, ``$(Format-CounterBytes $shadow.Bytes)``, GET/PUT ``$($shadow.GetHits)/$($shadow.PutHits)``, match/mismatch ``$($shadow.OutputMatch)/$($shadow.OutputMismatch)``, changed/unchanged ``$($shadow.DstChanged)/$($shadow.DstUnchanged)``.") | Out-Null
$lines.Add("- 25cc shadow descriptors: ``$descRows`` rows, ``$descHits`` hits, ``$(Format-CounterBytes $descBytes)``, GET/PUT hits ``$getHits/$putHits``, output mismatches ``$descMismatch``, max descriptor overflow ``$descOverflow``.") | Out-Null
$lines.Add("- Generic non-25cc shadow mismatches: ``$genericShadowMismatchSum`` across ``$genericShadowMismatchLines`` line(s); PCs: ``$(($genericShadowMismatchPcs.Keys | Sort-Object) -join ', ')``. This blocks broad shadow claims but not the 25cc-only descriptor reading above.") | Out-Null
$lines.Add("- Direction CSV: ``$csvPath``.") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Direction Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Direction | Raw cmd | Rows | Hits | Bytes | Match | Mismatch | Changed | Unchanged | Overflow max | Patterns |") | Out-Null
$lines.Add("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |") | Out-Null
foreach ($row in $directionRows) {
    $lines.Add((
        "| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |" -f
        $row.direction,
        $row.raw_cmd,
        $row.rows,
        $row.hits,
        $row.bytes_text,
        $row.output_match,
        $row.output_mismatch,
        $row.dst_changed,
        $row.dst_unchanged,
        $row.desc_overflow_max,
        $row.unique_patterns
    )) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- This is a verify-only field counterproof. It is not speed, GPU migration, Options/menu proof, first-battle proof, or a 200% gate candidate.") | Out-Null
$lines.Add("- Body/skip paths were off. Any later fast path still needs clean field, Options/menu, and first-battle visuals with zero 25cc mismatches.") | Out-Null
if ($fatalExamples.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Fatal Examples") | Out-Null
    $lines.Add("") | Out-Null
    foreach ($fatal in $fatalExamples) {
        $lines.Add("- ``$fatal``") | Out-Null
    }
}

$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
Write-Host "Classification: $classification"
Write-Host "Summary: $mdPath"
Write-Host "CSV: $csvPath"
