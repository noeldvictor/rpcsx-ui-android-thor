param(
    [string]$RunDir = "",
    [string]$LogPath = "",
    [int]$Top = 25,
    [string]$OutPath = "",
    [string]$CsvPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ProbePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Convert-ProbeNumber {
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

function Format-ProbeHex {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "0x0"
    }

    $text = $Value.Trim()
    if ($text -match '^0x') {
        return $text.ToLowerInvariant()
    }

    return ("0x{0:x}" -f (Convert-ProbeNumber $text))
}

function Format-ProbeBytes {
    param([UInt64]$Value)

    if ($Value -ge 1048576) {
        return ("{0:N2} MB" -f ([double]$Value / 1048576.0))
    }
    if ($Value -ge 1024) {
        return ("{0:N1} KB" -f ([double]$Value / 1024.0))
    }
    return "$Value B"
}

function Read-ProbeRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata GPU candidate probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('total_bytes')) {
        return $null
    }

    return [pscustomobject]@{
        mode            = $fields['mode']
        title           = $fields['title']
        ppu             = Format-ProbeHex $fields['ppu']
        ppu_name        = $fields['ppu_name']
        group           = Format-ProbeHex $fields['group']
        group_name      = $fields['group_name']
        spu             = Format-ProbeHex $fields['spu']
        spu_index       = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name        = $fields['spu_name']
        entry           = Format-ProbeHex $fields['entry']
        image_sig       = Format-ProbeHex $fields['image_sig']
        pattern_sig     = Format-ProbeHex $fields['pattern_sig']
        duration_us     = Convert-ProbeNumber $fields['duration_us']
        total_bytes     = Convert-ProbeNumber $fields['total_bytes']
        get_bytes       = Convert-ProbeNumber $fields['get_bytes']
        put_bytes       = Convert-ProbeNumber $fields['put_bytes']
        list_get_bytes  = Convert-ProbeNumber $fields['list_get_bytes']
        list_put_bytes  = Convert-ProbeNumber $fields['list_put_bytes']
        rsx_get_bytes   = Convert-ProbeNumber $fields['rsx_get_bytes']
        rsx_put_bytes   = Convert-ProbeNumber $fields['rsx_put_bytes']
        cmd_count       = Convert-ProbeNumber $fields['cmd_count']
        list_cmd_count  = Convert-ProbeNumber $fields['list_cmd_count']
        dma_mode        = $fields['dma_mode']
        get_payload_hash = Format-ProbeHex $fields['get_payload_hash']
        put_payload_hash = Format-ProbeHex $fields['put_payload_hash']
        get_payload_bytes = Convert-ProbeNumber $fields['get_payload_bytes']
        put_payload_bytes = Convert-ProbeNumber $fields['put_payload_bytes']
        sampled_get_payload_bytes = Convert-ProbeNumber $fields['sampled_get_payload_bytes']
        sampled_put_payload_bytes = Convert-ProbeNumber $fields['sampled_put_payload_bytes']
        ls_start_hash   = Format-ProbeHex $fields['ls_start_hash']
        ls_end_hash     = Format-ProbeHex $fields['ls_end_hash']
        repeat_hits     = Convert-ProbeNumber $fields['repeat_hits']
        output_mismatches = Convert-ProbeNumber $fields['output_mismatches']
        max_dma_size    = [UInt64](Convert-ProbeNumber $fields['max_dma_size'])
        max_dma_pc      = Format-ProbeHex $fields['max_dma_pc']
        max_dma_ea      = Format-ProbeHex $fields['max_dma_ea']
        block_hash      = Format-ProbeHex $fields['block_hash']
        max_dma_block_hash = Format-ProbeHex $fields['max_dma_block_hash']
        cause           = Format-ProbeHex $fields['cause']
        status          = Format-ProbeHex $fields['status']
    }
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw "Pass -RunDir or -LogPath."
    }

    $LogPath = Join-Path (Resolve-ProbePath $RunDir) "RPCS3.log"
}

$LogPath = Resolve-ProbePath $LogPath
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "RPCS3 log not found: $LogPath"
}

if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $RunDir = Split-Path -Parent $LogPath
} else {
    $RunDir = Resolve-ProbePath $RunDir
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunDir "eternal-sonata-gpu-probe-summary.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunDir "eternal-sonata-gpu-probe-records.csv"
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
    $record = Read-ProbeRecord $line
    if ($null -ne $record) {
        $records.Add($record) | Out-Null
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata GPU Probe Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format o)") | Out-Null
$lines.Add("- Log: $LogPath") | Out-Null
$lines.Add("- Records: $($records.Count)") | Out-Null
$lines.Add("- Top rows: $Top") | Out-Null

if ($records.Count -eq 0) {
    $lines.Add("") | Out-Null
    $lines.Add('No `Eternal Sonata GPU candidate probe` records were found.') | Out-Null
    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "GPU probe summary: $OutPath"
    return
}

$records | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$lines.Add("- CSV: $CsvPath") | Out-Null

$totalBytes = [UInt64](($records | Measure-Object -Property total_bytes -Sum).Sum)
$maxRecord = $records | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
$rsxRecords = @($records | Where-Object { $_.rsx_get_bytes -gt 0 -or $_.rsx_put_bytes -gt 0 })
$lines.Add("- Total observed DMA bytes: $(Format-ProbeBytes $totalBytes)") | Out-Null
$lines.Add(('- Largest single job: {0} in `{1}` / `{2}`' -f (Format-ProbeBytes $maxRecord.total_bytes), $maxRecord.group_name, $maxRecord.spu_name)) | Out-Null
$lines.Add("- RSX-local traffic records: $($rsxRecords.Count)") | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Top Candidates By DMA Bytes") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Group | SPU | Image | Pattern | Total | GET | PUT | List GET | List PUT | RSX GET | RSX PUT | Cmds | List Cmds | Max DMA | PC | Block | EA |") | Out-Null
$lines.Add("| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

$rank = 1
foreach ($record in @($records | Sort-Object -Property total_bytes -Descending | Select-Object -First $Top)) {
    $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | `{4}` | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | `{15}` | `{16}` | `{17}` |' -f $rank, $record.group_name, $record.spu_name, $record.image_sig, $record.pattern_sig, (Format-ProbeBytes $record.total_bytes), (Format-ProbeBytes $record.get_bytes), (Format-ProbeBytes $record.put_bytes), (Format-ProbeBytes $record.list_get_bytes), (Format-ProbeBytes $record.list_put_bytes), (Format-ProbeBytes $record.rsx_get_bytes), (Format-ProbeBytes $record.rsx_put_bytes), $record.cmd_count, $record.list_cmd_count, (Format-ProbeBytes $record.max_dma_size), $record.max_dma_pc, $record.max_dma_block_hash, $record.max_dma_ea)) | Out-Null
    $rank++
}

$lines.Add("") | Out-Null
$lines.Add("## Group Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Group | Records | Max Total | Sum Total | Max List GET | Max List PUT | Max RSX GET | Max RSX PUT | Top SPU | Top Image | Top PC |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

foreach ($group in @($records | Group-Object -Property group_name | Sort-Object -Property Count -Descending)) {
    $groupRecords = @($group.Group)
    $topRecord = $groupRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $sum = [UInt64](($groupRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $maxListGet = [UInt64](($groupRecords | Measure-Object -Property list_get_bytes -Maximum).Maximum)
    $maxListPut = [UInt64](($groupRecords | Measure-Object -Property list_put_bytes -Maximum).Maximum)
    $maxRsxGet = [UInt64](($groupRecords | Measure-Object -Property rsx_get_bytes -Maximum).Maximum)
    $maxRsxPut = [UInt64](($groupRecords | Measure-Object -Property rsx_put_bytes -Maximum).Maximum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} | {7} | `{8}` | `{9}` | `{10}` |' -f $group.Name, $group.Count, (Format-ProbeBytes $topRecord.total_bytes), (Format-ProbeBytes $sum), (Format-ProbeBytes $maxListGet), (Format-ProbeBytes $maxListPut), (Format-ProbeBytes $maxRsxGet), (Format-ProbeBytes $maxRsxPut), $topRecord.spu_name, $topRecord.image_sig, $topRecord.max_dma_pc)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Hot PC Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| PC | Records | Sum Total | Max Total | Max DMA | Top Group | Top SPU | Top EA |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

foreach ($pcGroup in @($records | Group-Object -Property max_dma_pc | Sort-Object -Property Count -Descending | Select-Object -First $Top)) {
    $pcRecords = @($pcGroup.Group)
    $pcTop = $pcRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $pcSum = [UInt64](($pcRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $pcMaxDma = [UInt64](($pcRecords | Measure-Object -Property max_dma_size -Maximum).Maximum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} | `{5}` | `{6}` | `{7}` |' -f $pcGroup.Name, $pcGroup.Count, (Format-ProbeBytes $pcSum), (Format-ProbeBytes $pcTop.total_bytes), (Format-ProbeBytes $pcMaxDma), $pcTop.group_name, $pcTop.spu_name, $pcTop.max_dma_ea)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Repeated Pattern Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Pattern | Records | Sum Total | Max Total | Group | SPU | PC | Max EA |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | --- | --- | --- | --- |") | Out-Null

foreach ($patternGroup in @($records | Group-Object -Property pattern_sig | Sort-Object -Property Count -Descending | Select-Object -First $Top)) {
    $patternRecords = @($patternGroup.Group)
    $patternTop = $patternRecords | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
    $patternSum = [UInt64](($patternRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $lines.Add(('| `{0}` | {1} | {2} | {3} | `{4}` | `{5}` | `{6}` | `{7}` |' -f $patternGroup.Name, $patternGroup.Count, (Format-ProbeBytes $patternSum), (Format-ProbeBytes $patternTop.total_bytes), $patternTop.group_name, $patternTop.spu_name, $patternTop.max_dma_pc, $patternTop.max_dma_ea)) | Out-Null
}

$dmaRecords = @($records | Where-Object { $_.get_payload_bytes -gt 0 -or $_.put_payload_bytes -gt 0 -or $_.repeat_hits -gt 0 -or $_.output_mismatches -gt 0 })
if ($dmaRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## DMA Superpath Verification") | Out-Null
    $lines.Add("") | Out-Null

    $payloadGet = [UInt64](($dmaRecords | Measure-Object -Property get_payload_bytes -Sum).Sum)
    $payloadPut = [UInt64](($dmaRecords | Measure-Object -Property put_payload_bytes -Sum).Sum)
    $sampledGet = [UInt64](($dmaRecords | Measure-Object -Property sampled_get_payload_bytes -Sum).Sum)
    $sampledPut = [UInt64](($dmaRecords | Measure-Object -Property sampled_put_payload_bytes -Sum).Sum)
    $maxRepeat = [UInt64](($dmaRecords | Measure-Object -Property repeat_hits -Maximum).Maximum)
    $maxMismatch = [UInt64](($dmaRecords | Measure-Object -Property output_mismatches -Maximum).Maximum)

    $lines.Add("- Payload GET bytes: $(Format-ProbeBytes $payloadGet)") | Out-Null
    $lines.Add("- Payload PUT bytes: $(Format-ProbeBytes $payloadPut)") | Out-Null
    $lines.Add("- Sampled GET bytes: $(Format-ProbeBytes $sampledGet)") | Out-Null
    $lines.Add("- Sampled PUT bytes: $(Format-ProbeBytes $sampledPut)") | Out-Null
    $lines.Add("- Max repeat hits for a seen input/output key: $maxRepeat") | Out-Null
    $lines.Add("- Max output mismatches for a seen input key: $maxMismatch") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Image | Pattern | Input Hash | Output Hash | Repeats | Mismatches | GET Payload | PUT Payload | Sampled GET | Sampled PUT | Group | SPU | PC |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($dmaRecords | Sort-Object -Property repeat_hits, total_bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | `{4}` | {5} | {6} | {7} | {8} | {9} | {10} | `{11}` | `{12}` | `{13}` |' -f $rank, $record.image_sig, $record.pattern_sig, $record.get_payload_hash, $record.put_payload_hash, $record.repeat_hits, $record.output_mismatches, (Format-ProbeBytes $record.get_payload_bytes), (Format-ProbeBytes $record.put_payload_bytes), (Format-ProbeBytes $record.sampled_get_payload_bytes), (Format-ProbeBytes $record.sampled_put_payload_bytes), $record.group_name, $record.spu_name, $record.max_dma_pc)) | Out-Null
        $rank++
    }
}

if ($rsxRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## RSX-Local Candidates") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Group | SPU | Total | RSX GET | RSX PUT | Image | PC | EA |") | Out-Null
    $lines.Add("| ---: | --- | --- | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($rsxRecords | Sort-Object -Property rsx_get_bytes, rsx_put_bytes, total_bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | {3} | {4} | {5} | `{6}` | `{7}` | `{8}` |' -f $rank, $record.group_name, $record.spu_name, (Format-ProbeBytes $record.total_bytes), (Format-ProbeBytes $record.rsx_get_bytes), (Format-ProbeBytes $record.rsx_put_bytes), $record.image_sig, $record.max_dma_pc, $record.max_dma_ea)) | Out-Null
        $rank++
    }
}

$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add('- High `total/list` bytes with zero RSX traffic is still valuable, but it points first at SPU/kernel replacement, NEON, scheduler, or verified CPU superpaths.') | Out-Null
$lines.Add('- Nonzero `RSX GET/PUT` is the stronger Vulkan compute or GPU-resident superpath signal, especially if it repeats in field, battle, and menu.') | Out-Null
$lines.Add("- Do not claim FPS wins from this summary. Pair it with normalized host grade and visual proof.") | Out-Null

$lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "GPU probe summary: $OutPath"
Write-Host "GPU probe CSV: $CsvPath"
