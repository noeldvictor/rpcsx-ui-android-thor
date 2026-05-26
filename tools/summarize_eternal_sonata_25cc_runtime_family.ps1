param(
    [string]$RunDir = "",
    [int]$Top = 20,
    [string]$OutPath = "",
    [string]$PatternCsvPath = "",
    [string]$BucketCsvPath = "",
    [string]$HashCsvPath = "",
    [string]$ShadowCsvPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ToolPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Convert-ToolNumber {
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

function Format-ToolBytes {
    param([UInt64]$Value)

    if ($Value -ge 1073741824) {
        return ("{0:N2} GB" -f ([double]$Value / 1073741824.0))
    }
    if ($Value -ge 1048576) {
        return ("{0:N2} MB" -f ([double]$Value / 1048576.0))
    }
    if ($Value -ge 1024) {
        return ("{0:N1} KB" -f ([double]$Value / 1024.0))
    }
    return "$Value B"
}

function Format-ToolPercent {
    param(
        [UInt64]$Numerator,
        [UInt64]$Denominator
    )

    if ($Denominator -eq 0) {
        return "0.000%"
    }

    return ("{0:N3}%" -f (([double]$Numerator / [double]$Denominator) * 100.0))
}

function Get-ToolSum {
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

$repoRoot = Resolve-ToolPath (Join-Path $PSScriptRoot "..")
$windowsLabRoot = Join-Path $repoRoot "debug-captures\windows-lab"

if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $latest = Get-ChildItem -LiteralPath $windowsLabRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-spu-hle-25cc-family-profile.csv") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-gpu-probe-records.csv") -PathType Leaf)
        } |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No Windows run with 25cc family and GPU probe CSVs found under $windowsLabRoot"
    }

    $RunDir = $latest.FullName
}

$RunDir = Resolve-ToolPath $RunDir
$familyCsv = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-family-profile.csv"
$gpuCsv = Join-Path $RunDir "eternal-sonata-gpu-probe-records.csv"

if (-not (Test-Path -LiteralPath $familyCsv -PathType Leaf)) {
    throw "Missing 25cc family CSV: $familyCsv"
}
if (-not (Test-Path -LiteralPath $gpuCsv -PathType Leaf)) {
    throw "Missing GPU probe CSV: $gpuCsv"
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunDir "eternal-sonata-25cc-runtime-family-summary.md"
}
if ([string]::IsNullOrWhiteSpace($PatternCsvPath)) {
    $PatternCsvPath = Join-Path $RunDir "eternal-sonata-25cc-runtime-family-patterns.csv"
}
if ([string]::IsNullOrWhiteSpace($BucketCsvPath)) {
    $BucketCsvPath = Join-Path $RunDir "eternal-sonata-25cc-runtime-family-buckets.csv"
}
if ([string]::IsNullOrWhiteSpace($HashCsvPath)) {
    $HashCsvPath = Join-Path $RunDir "eternal-sonata-25cc-runtime-family-hash-semantics.csv"
}
if ([string]::IsNullOrWhiteSpace($ShadowCsvPath)) {
    $ShadowCsvPath = Join-Path $RunDir "eternal-sonata-spu-hle-25cc-shadow-profile.csv"
}

$familyRows = @(Import-Csv -LiteralPath $familyCsv)
$gpuRows = @(Import-Csv -LiteralPath $gpuCsv | Where-Object { $_.max_dma_pc -eq "0x25cc" -and $_.image_sig -eq "0x958dfe208b686622" })
$shadowRows = @()
if (Test-Path -LiteralPath $ShadowCsvPath -PathType Leaf) {
    $shadowRows = @(Import-Csv -LiteralPath $ShadowCsvPath)
}

$hits = Get-ToolSum $familyRows "hits"
$success = Get-ToolSum $familyRows "success"
$fail = Get-ToolSum $familyRows "fail"
$getHits = Get-ToolSum $familyRows "get_hits"
$putHits = Get-ToolSum $familyRows "put_hits"
$bytes = Get-ToolSum $familyRows "bytes"
$totalUs = Get-ToolSum $familyRows "total_us"
$ea9Hits = Get-ToolSum $familyRows "ea9e4000_hits"
$ea4Hits = Get-ToolSum $familyRows "ea4f0b80_hits"
$exactHits = Get-ToolSum $familyRows "exact_a1c000_hits"
$otherHits = Get-ToolSum $familyRows "other_ea_hits"
$maxTotalUs = if ($familyRows.Count) { [UInt64](($familyRows | Measure-Object -Property max_total_us -Maximum).Maximum) } else { [UInt64]0 }
$avgUsPerHit = if ($hits -gt 0) { [double]$totalUs / [double]$hits } else { 0.0 }
$bytesPerHit = [UInt64]16384

$bucketRows = @(
    [pscustomobject]@{
        bucket = "ea9e4000"
        hits = $ea9Hits
        bytes_estimate = $ea9Hits * $bytesPerHit
        percent_hits = Format-ToolPercent $ea9Hits $hits
        reading = "exact command-level EA, too narrow alone"
    }
    [pscustomobject]@{
        bucket = "ea4f0b80"
        hits = $ea4Hits
        bytes_estimate = $ea4Hits * $bytesPerHit
        percent_hits = Format-ToolPercent $ea4Hits $hits
        reading = "tiny secondary bucket"
    }
    [pscustomobject]@{
        bucket = "exact_a1c000"
        hits = $exactHits
        bytes_estimate = $exactHits * $bytesPerHit
        percent_hits = Format-ToolPercent $exactHits $hits
        reading = "known guarded-skip shape, still narrow"
    }
    [pscustomobject]@{
        bucket = "other_matching_ea"
        hits = $otherHits
        bytes_estimate = $otherHits * $bytesPerHit
        percent_hits = Format-ToolPercent $otherHits $hits
        reading = "main runtime body needs broader pattern or descriptor gate"
    }
)

$patternGroups = @{}
foreach ($row in $gpuRows) {
    $key = "$($row.max_dma_ea)|$($row.pattern_sig)|$($row.max_dma_size)"
    if (-not $patternGroups.ContainsKey($key)) {
        $patternGroups[$key] = [pscustomobject]@{
            max_dma_ea = $row.max_dma_ea
            pattern_sig = $row.pattern_sig
            max_dma_size = Convert-ToolNumber $row.max_dma_size
            records = [UInt64]0
            total_bytes = [UInt64]0
            get_bytes = [UInt64]0
            put_bytes = [UInt64]0
            list_get_bytes = [UInt64]0
            list_put_bytes = [UInt64]0
            rsx_get_bytes = [UInt64]0
            rsx_put_bytes = [UInt64]0
            cmd_count = [UInt64]0
            list_cmd_count = [UInt64]0
            max_record_bytes = [UInt64]0
            max_cmd_count = [UInt64]0
            group_name = $row.group_name
            spu_name = $row.spu_name
            image_sig = $row.image_sig
        }
    }

    $group = $patternGroups[$key]
    $rowTotal = Convert-ToolNumber $row.total_bytes
    $rowCmds = Convert-ToolNumber $row.cmd_count
    $group.records++
    $group.total_bytes += $rowTotal
    $group.get_bytes += Convert-ToolNumber $row.get_bytes
    $group.put_bytes += Convert-ToolNumber $row.put_bytes
    $group.list_get_bytes += Convert-ToolNumber $row.list_get_bytes
    $group.list_put_bytes += Convert-ToolNumber $row.list_put_bytes
    $group.rsx_get_bytes += Convert-ToolNumber $row.rsx_get_bytes
    $group.rsx_put_bytes += Convert-ToolNumber $row.rsx_put_bytes
    $group.cmd_count += $rowCmds
    $group.list_cmd_count += Convert-ToolNumber $row.list_cmd_count
    $group.max_record_bytes = [Math]::Max($group.max_record_bytes, $rowTotal)
    $group.max_cmd_count = [Math]::Max($group.max_cmd_count, $rowCmds)
}

$patternRows = @($patternGroups.Values | ForEach-Object {
    $rsxBytes = $_.rsx_get_bytes + $_.rsx_put_bytes
    $avgBytes = if ($_.records -gt 0) { [UInt64]([Math]::Round([double]$_.total_bytes / [double]$_.records)) } else { [UInt64]0 }
    $candidate = if ($rsxBytes -gt 0) {
        "rsx-overlap-investigate"
    } elseif ($_.max_dma_ea -eq "0x9e4000" -and $_.records -ge 2 -and $_.total_bytes -ge 25MB -and $_.max_dma_size -eq 16384) {
        "hle-pattern-body-candidate"
    } elseif ($_.records -ge 2 -and $_.total_bytes -ge 8MB) {
        "secondary-pattern"
    } else {
        "too-small"
    }

    [pscustomobject]@{
        max_dma_ea = $_.max_dma_ea
        pattern_sig = $_.pattern_sig
        max_dma_size = $_.max_dma_size
        records = $_.records
        total_bytes = $_.total_bytes
        avg_bytes = $avgBytes
        max_record_bytes = $_.max_record_bytes
        get_bytes = $_.get_bytes
        put_bytes = $_.put_bytes
        list_get_bytes = $_.list_get_bytes
        list_put_bytes = $_.list_put_bytes
        rsx_bytes = $rsxBytes
        cmd_count = $_.cmd_count
        max_cmd_count = $_.max_cmd_count
        candidate = $candidate
        group_name = $_.group_name
        spu_name = $_.spu_name
        image_sig = $_.image_sig
    }
} | Sort-Object -Property total_bytes,records -Descending)

$patternRows | Export-Csv -LiteralPath $PatternCsvPath -NoTypeInformation -Encoding UTF8
$bucketRows | Export-Csv -LiteralPath $BucketCsvPath -NoTypeInformation -Encoding UTF8

$hashGroups = @{}
foreach ($row in $gpuRows) {
    $key = "$($row.max_dma_ea)|$($row.get_payload_hash)|$($row.put_payload_hash)|$($row.sampled_get_payload_bytes)|$($row.sampled_put_payload_bytes)|$($row.ls_start_hash)|$($row.ls_end_hash)|$($row.block_hash)|$($row.max_dma_block_hash)"
    if (-not $hashGroups.ContainsKey($key)) {
        $hashGroups[$key] = [pscustomobject]@{
            max_dma_ea = $row.max_dma_ea
            get_payload_hash = $row.get_payload_hash
            put_payload_hash = $row.put_payload_hash
            sampled_get_payload_bytes = Convert-ToolNumber $row.sampled_get_payload_bytes
            sampled_put_payload_bytes = Convert-ToolNumber $row.sampled_put_payload_bytes
            ls_start_hash = $row.ls_start_hash
            ls_end_hash = $row.ls_end_hash
            block_hash = $row.block_hash
            max_dma_block_hash = $row.max_dma_block_hash
            records = [UInt64]0
            total_bytes = [UInt64]0
            get_bytes = [UInt64]0
            put_bytes = [UInt64]0
            rsx_bytes = [UInt64]0
            distinct_patterns = [System.Collections.Generic.HashSet[string]]::new()
        }
    }

    $group = $hashGroups[$key]
    $group.records++
    $group.total_bytes += Convert-ToolNumber $row.total_bytes
    $group.get_bytes += Convert-ToolNumber $row.get_bytes
    $group.put_bytes += Convert-ToolNumber $row.put_bytes
    $group.rsx_bytes += (Convert-ToolNumber $row.rsx_get_bytes) + (Convert-ToolNumber $row.rsx_put_bytes)
    [void]$group.distinct_patterns.Add($row.pattern_sig)
}

$hashRows = @($hashGroups.Values | ForEach-Object {
    $sampledBytes = $_.sampled_get_payload_bytes + $_.sampled_put_payload_bytes
    $hasRealBlockHash = ($_.block_hash -ne "0x0" -or $_.max_dma_block_hash -ne "0x0" -or $_.ls_start_hash -ne "0x0" -or $_.ls_end_hash -ne "0x0")
    $reading = if ($sampledBytes -eq 0 -and -not $hasRealBlockHash) {
        "hash-instrumentation-gap"
    } elseif ($_.get_payload_hash -eq $_.put_payload_hash -and $_.put_bytes -gt 0) {
        "mirrored-payload-hash-scout"
    } else {
        "hash-divergence-scout"
    }

    [pscustomobject]@{
        max_dma_ea = $_.max_dma_ea
        get_payload_hash = $_.get_payload_hash
        put_payload_hash = $_.put_payload_hash
        sampled_get_payload_bytes = $_.sampled_get_payload_bytes
        sampled_put_payload_bytes = $_.sampled_put_payload_bytes
        ls_start_hash = $_.ls_start_hash
        ls_end_hash = $_.ls_end_hash
        block_hash = $_.block_hash
        max_dma_block_hash = $_.max_dma_block_hash
        records = $_.records
        pattern_count = [UInt64]$_.distinct_patterns.Count
        total_bytes = $_.total_bytes
        get_bytes = $_.get_bytes
        put_bytes = $_.put_bytes
        rsx_bytes = $_.rsx_bytes
        reading = $reading
    }
} | Sort-Object -Property total_bytes,records -Descending)

$hashRows | Export-Csv -LiteralPath $HashCsvPath -NoTypeInformation -Encoding UTF8

$rsxBytesTotal = (Get-ToolSum $gpuRows "rsx_get_bytes") + (Get-ToolSum $gpuRows "rsx_put_bytes")
$gpuTotalBytes = Get-ToolSum $gpuRows "total_bytes"
$candidateRows = @($patternRows | Where-Object { $_.candidate -eq "hle-pattern-body-candidate" })
$candidateBytes = Get-ToolSum $candidateRows "total_bytes"
$candidateRecords = Get-ToolSum $candidateRows "records"
$sampledPayloadRows = @($gpuRows | Where-Object {
    (Convert-ToolNumber $_.sampled_get_payload_bytes) -gt 0 -or
    (Convert-ToolNumber $_.sampled_put_payload_bytes) -gt 0
})
$nonzeroHashRows = @($gpuRows | Where-Object {
    $_.block_hash -ne "0x0" -or $_.max_dma_block_hash -ne "0x0" -or
    $_.ls_start_hash -ne "0x0" -or $_.ls_end_hash -ne "0x0"
})

$shadowHits = Get-ToolSum $shadowRows "hits"
$shadowBytes = Get-ToolSum $shadowRows "bytes"
$shadowGetHits = Get-ToolSum $shadowRows "get_hits"
$shadowPutHits = Get-ToolSum $shadowRows "put_hits"
$shadowChanged = Get-ToolSum $shadowRows "dst_changed"
$shadowUnchanged = Get-ToolSum $shadowRows "dst_unchanged"
$shadowMatch = Get-ToolSum $shadowRows "output_match"
$shadowMismatch = Get-ToolSum $shadowRows "output_mismatch"
$shadowEa9 = Get-ToolSum $shadowRows "ea9e4000_hits"
$shadowEa4 = Get-ToolSum $shadowRows "ea4f0b80_hits"
$shadowExact = Get-ToolSum $shadowRows "exact_a1c000_hits"
$shadowOther = Get-ToolSum $shadowRows "other_ea_hits"
$shadowUniqueSrc = @($shadowRows | Select-Object -ExpandProperty last_src_hash -Unique -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
$shadowUniqueDstPost = @($shadowRows | Select-Object -ExpandProperty last_dst_post_hash -Unique -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Runtime-Family Analysis") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- Run directory: ``{0}``" -f $RunDir)) | Out-Null
$lines.Add(("- Runtime family CSV: ``{0}``" -f $familyCsv)) | Out-Null
$lines.Add(("- GPU probe CSV: ``{0}``" -f $gpuCsv)) | Out-Null
$lines.Add(("- Pattern CSV: ``{0}``" -f $PatternCsvPath)) | Out-Null
$lines.Add(("- Bucket CSV: ``{0}``" -f $BucketCsvPath)) | Out-Null
$lines.Add(("- Hash semantics CSV: ``{0}``" -f $HashCsvPath)) | Out-Null
if ($shadowRows.Count -gt 0) {
    $lines.Add(("- 0x25cc shadow CSV: ``{0}``" -f $ShadowCsvPath)) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Runtime Hook Buckets") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Rows: $($familyRows.Count)") | Out-Null
$lines.Add("- Hits: $hits, success/fail: $success/$fail") | Out-Null
$lines.Add("- Direction hits: GET=$getHits, PUT=$putHits") | Out-Null
$lines.Add("- Bytes: $(Format-ToolBytes $bytes)") | Out-Null
$lines.Add(("- Timing: total={0:N3} ms, avg={1:N3} us/hit, max={2} us" -f ([double]$totalUs / 1000.0), $avgUsPerHit, $maxTotalUs)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Bucket | Hits | Share | Bytes estimate | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | --- |") | Out-Null
foreach ($bucket in $bucketRows) {
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} |' -f $bucket.bucket, $bucket.hits, $bucket.percent_hits, (Format-ToolBytes $bucket.bytes_estimate), $bucket.reading)) | Out-Null
}
$lines.Add("") | Out-Null
if ($shadowRows.Count -gt 0) {
    $lines.Add("## 0x25cc Shadow Semantics") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("- Shadow rows: $($shadowRows.Count)") | Out-Null
    $lines.Add("- Hits: $shadowHits") | Out-Null
    $lines.Add("- Direction hits: GET=$shadowGetHits, PUT=$shadowPutHits") | Out-Null
    $lines.Add("- Bytes: $(Format-ToolBytes $shadowBytes)") | Out-Null
    $lines.Add("- Destination changed/unchanged: $shadowChanged/$shadowUnchanged") | Out-Null
    $lines.Add("- Output match/mismatch: $shadowMatch/$shadowMismatch") | Out-Null
    $lines.Add("- EA buckets: ea9e4000=$shadowEa9, ea4f0b80=$shadowEa4, exact_a1c000=$shadowExact, other=$shadowOther") | Out-Null
    $lines.Add("- Unique last source hashes: $shadowUniqueSrc") | Out-Null
    $lines.Add("- Unique last destination-post hashes: $shadowUniqueDstPost") | Out-Null
    $lines.Add("") | Out-Null
}
$lines.Add("## 0x25cc Max-DMA Pattern Groups") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- GPU-probe 0x25cc rows: $($gpuRows.Count)") | Out-Null
$lines.Add("- GPU-probe 0x25cc total bytes: $(Format-ToolBytes $gpuTotalBytes)") | Out-Null
$lines.Add("- Direct RSX-local bytes: $(Format-ToolBytes $rsxBytesTotal)") | Out-Null
$lines.Add("- HLE pattern-body candidates: $($candidateRows.Count) groups, $candidateRecords records, $(Format-ToolBytes $candidateBytes)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Candidate | EA | Pattern | Records | Total | Avg | Max Row | Cmds | Max Cmds | GET | PUT | List GET | RSX |") | Out-Null
$lines.Add("| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |") | Out-Null

$rank = 1
foreach ($pattern in @($patternRows | Select-Object -First $Top)) {
    $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} |' -f $rank, $pattern.candidate, $pattern.max_dma_ea, $pattern.pattern_sig, $pattern.records, (Format-ToolBytes $pattern.total_bytes), (Format-ToolBytes $pattern.avg_bytes), (Format-ToolBytes $pattern.max_record_bytes), $pattern.cmd_count, $pattern.max_cmd_count, (Format-ToolBytes $pattern.get_bytes), (Format-ToolBytes $pattern.put_bytes), (Format-ToolBytes $pattern.list_get_bytes), (Format-ToolBytes $pattern.rsx_bytes))) | Out-Null
    $rank++
}

$lines.Add("") | Out-Null
$lines.Add("## Hash Semantics Scout") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Hash groups: $($hashRows.Count)") | Out-Null
$lines.Add("- Rows with sampled payload bytes: $($sampledPayloadRows.Count)") | Out-Null
$lines.Add("- Rows with nonzero LS/block hashes: $($nonzeroHashRows.Count)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | EA | GET hash | PUT hash | Records | Patterns | Total | Sampled GET | Sampled PUT | LS start | LS end | Block | Max DMA block | Reading |") | Out-Null
$lines.Add("| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

$rank = 1
foreach ($hash in @($hashRows | Select-Object -First $Top)) {
    $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}` | `{11}` | `{12}` | {13} |' -f $rank, $hash.max_dma_ea, $hash.get_payload_hash, $hash.put_payload_hash, $hash.records, $hash.pattern_count, (Format-ToolBytes $hash.total_bytes), (Format-ToolBytes $hash.sampled_get_payload_bytes), (Format-ToolBytes $hash.sampled_put_payload_bytes), $hash.ls_start_hash, $hash.ls_end_hash, $hash.block_hash, $hash.max_dma_block_hash, $hash.reading)) | Out-Null
    $rank++
}

$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(('- Exact command-level EA `0x9e4000` covered {0} of runtime-family hits; exact command-level EA matching is too narrow for a fast body.' -f (Format-ToolPercent $ea9Hits $hits))) | Out-Null
$lines.Add('- The useful next gate is pattern-level or descriptor-level semantics over repeated `0x25cc` max-DMA pattern groups, especially `0x9e4000` groups with repeated 16 KB jobs.') | Out-Null
if ($shadowRows.Count -gt 0) {
    if ($shadowMismatch -eq 0 -and $shadowHits -gt 0) {
        $lines.Add("- The 0x25cc shadow verifier now provides source/destination-before/destination-after semantics with zero output mismatches for this run; the next gate is a narrow opt-in body design, not another generic scout.") | Out-Null
    } else {
        $lines.Add("- The 0x25cc shadow verifier is present but has mismatches or no hits; do not design a fast body until the shadow contract is repaired.") | Out-Null
    }
} else {
    $lines.Add("- Current hash fields are not enough for a fast body if sampled payload bytes and LS/block hashes are zero; add a verify-shadow runtime scout that hashes source, destination-before, and destination-after for the repeated groups.") | Out-Null
}
$lines.Add("- Direct RSX-local traffic remains $(Format-ToolBytes $rsxBytesTotal), so this is CPU/SPU HLE/codegen sizing, not GPU migration credit.") | Out-Null
$lines.Add("- No speed result is implied. Any fast path still needs verify-shadow/source-destination semantics plus field/menu/first-battle proof before A/B timing.") | Out-Null

$lines | Set-Content -LiteralPath $OutPath -Encoding UTF8

Write-Host "25cc runtime-family summary: $OutPath"
Write-Host "25cc pattern CSV: $PatternCsvPath"
Write-Host "25cc bucket CSV: $BucketCsvPath"
Write-Host "25cc hash semantics CSV: $HashCsvPath"
