param(
    [string]$RunDir = "",
    [string]$LogPath = "",
    [int]$Top = 25,
    [string]$OutPath = "",
    [string]$CsvPath = "",
    [string]$MfcShapeCsvPath = "",
    [string]$MfcLadderCsvPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-ProbePath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-ProbeLogPath {
    param([string]$RunDir)

    $root = Resolve-ProbePath $RunDir
    $candidates = @(
        "RPCS3.log",
        "RPCSX.log",
        "logcat-full.txt",
        "logcat-live.txt",
        "thor-rsx-auditor-logcat.txt",
        "rpcsx-live-tail.txt"
    )

    foreach ($candidate in $candidates) {
        $path = Join-Path $root $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            return $path
        }
    }

    $fallback = Get-ChildItem -LiteralPath $root -Recurse -File -Include $candidates -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($fallback) {
        return $fallback.FullName
    }

    return Join-Path $root "RPCS3.log"
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

function Get-ProbeOffloadFit {
    param([object]$Record)

    if ($Record.output_mismatches -gt 0) {
        return "reject-mismatch"
    }

    $rsxBytes = [UInt64]($Record.rsx_get_bytes + $Record.rsx_put_bytes)
    if ($rsxBytes -gt 0 -and $Record.total_bytes -ge 1048576) {
        return "gpu-resident-strong"
    }

    if ($rsxBytes -gt 0) {
        return "gpu-resident-check"
    }

    if ($Record.repeat_hits -gt 0 -and $Record.put_payload_bytes -gt 0) {
        return "cpu-hle-or-replay"
    }

    if ($Record.total_bytes -ge 1048576) {
        return "spu-kernel-hle"
    }

    if ($Record.max_dma_size -ge 65536) {
        return "batch-first"
    }

    return "too-small"
}

function Get-ProbeDispatchRisk {
    param([object]$Record)

    if ($Record.max_dma_size -eq 0) {
        return "unknown"
    }

    if ($Record.cmd_count -gt 128 -and $Record.max_dma_size -lt 65536) {
        return "tiny-dispatch-trap"
    }

    if ($Record.cmd_count -gt 32 -and $Record.max_dma_size -lt 262144) {
        return "needs-batching"
    }

    if ($Record.total_bytes -ge 1048576 -or $Record.max_dma_size -ge 262144) {
        return "batchable"
    }

    return "low"
}

function Get-ProbeReading {
    param([object]$Record)

    switch ($Record.offload_fit) {
        "reject-mismatch" { return "Verification saw mismatched outputs; do not fast-path this signature." }
        "gpu-resident-strong" { return "Nonzero RSX-local traffic plus large DMA makes this a real Vulkan/RSX superpath candidate." }
        "gpu-resident-check" { return "RSX-local traffic exists, but size/repeat evidence must survive field, battle, and menu." }
        "cpu-hle-or-replay" { return "Repeat-clean payloads point at a verified CPU/HLE or replay cache before Vulkan compute." }
        "spu-kernel-hle" { return "Large SPU traffic with zero RSX-local bytes points first at SPU kernel HLE, NEON/dotprod, reduced-loop, or scheduler/copy work." }
        "batch-first" { return "Potentially useful only if batched; one dispatch per DMA command would be too expensive." }
        default { return "Too small or insufficiently stable for a GPU offload experiment." }
    }
}

function Format-MfcShapeFlags {
    param([UInt64]$Flags)

    $names = New-Object System.Collections.Generic.List[string]
    $map = @(
        @{ bit = 0; name = "list" },
        @{ bit = 1; name = "get" },
        @{ bit = 2; name = "put" },
        @{ bit = 3; name = "atomic" },
        @{ bit = 4; name = "barrier" },
        @{ bit = 5; name = "fence" },
        @{ bit = 6; name = "rsx-local" }
    )

    foreach ($entry in $map) {
        if (($Flags -band ([UInt64]1 -shl $entry.bit)) -ne 0) {
            $names.Add($entry.name) | Out-Null
        }
    }

    if ($names.Count -eq 0) {
        return "none"
    }

    return ($names -join ",")
}

function Read-ProbeRecord {
    param([string]$Line)

    $probeKind = ""
    if ($Line -match 'Eternal Sonata GPU candidate probe:') {
        $probeKind = "windows-gpu"
    } elseif ($Line -match 'Eternal Sonata DMA candidate probe:') {
        $probeKind = "thor-dma"
    } else {
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

    $record = [pscustomobject]@{
        probe_kind      = $probeKind
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

    $record | Add-Member -NotePropertyName offload_fit -NotePropertyValue (Get-ProbeOffloadFit $record)
    $record | Add-Member -NotePropertyName dispatch_risk -NotePropertyValue (Get-ProbeDispatchRisk $record)
    $record | Add-Member -NotePropertyName reading -NotePropertyValue (Get-ProbeReading $record)
    return $record
}

function Read-MfcShapeRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC shape probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('count')) {
        return $null
    }

    return [pscustomobject]@{
        mode       = $fields['mode']
        title      = $fields['title']
        group      = Format-ProbeHex $fields['group']
        group_name = $fields['group_name']
        spu        = Format-ProbeHex $fields['spu']
        spu_index  = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name   = $fields['spu_name']
        entry      = Format-ProbeHex $fields['entry']
        image_sig  = Format-ProbeHex $fields['image_sig']
        pc         = Format-ProbeHex $fields['pc']
        block_hash = Format-ProbeHex $fields['block_hash']
        cmd        = Format-ProbeHex $fields['cmd']
        tag        = Convert-ProbeNumber $fields['tag']
        size       = Convert-ProbeNumber $fields['size']
        lsa        = Format-ProbeHex $fields['lsa']
        flags      = Convert-ProbeNumber $fields['flags']
        count      = Convert-ProbeNumber $fields['count']
        bytes      = Convert-ProbeNumber $fields['bytes']
        eal_first  = Format-ProbeHex $fields['eal_first']
        eal_last   = Format-ProbeHex $fields['eal_last']
        eal_min    = Format-ProbeHex $fields['eal_min']
        eal_max    = Format-ProbeHex $fields['eal_max']
        overflow   = Convert-ProbeNumber $fields['overflow']
        cause      = Format-ProbeHex $fields['cause']
        status     = Format-ProbeHex $fields['status']
    }
}

function Read-MfcLadderRecord {
    param([string]$Line)

    if ($Line -notmatch 'Eternal Sonata MFC ladder probe:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups['key'].Value
        $quoted = $match.Groups['quoted']
        $value = if ($quoted.Success) { $quoted.Value } else { $match.Groups['value'].Value }
        $fields[$key] = $value
    }

    if (-not $fields.ContainsKey('eligible')) {
        return $null
    }

    return [pscustomobject]@{
        mode        = $fields['mode']
        ladder_mode = $fields['ladder_mode']
        title       = $fields['title']
        group       = Format-ProbeHex $fields['group']
        group_name  = $fields['group_name']
        spu         = Format-ProbeHex $fields['spu']
        spu_index   = [int](Convert-ProbeNumber $fields['spu_index'])
        spu_name    = $fields['spu_name']
        entry       = Format-ProbeHex $fields['entry']
        image_sig   = Format-ProbeHex $fields['image_sig']
        pc          = Format-ProbeHex $fields['pc']
        last_lsa    = Format-ProbeHex $fields['last_lsa']
        eligible    = Convert-ProbeNumber $fields['eligible']
        verify_hits = Convert-ProbeNumber $fields['verify_hits']
        fast_hits   = Convert-ProbeNumber $fields['fast_hits']
        blocked     = Convert-ProbeNumber $fields['blocked']
        mismatches  = Convert-ProbeNumber $fields['mismatches']
        bytes       = Convert-ProbeNumber $fields['bytes']
        eal_first   = Format-ProbeHex $fields['eal_first']
        eal_last    = Format-ProbeHex $fields['eal_last']
        eal_min     = Format-ProbeHex $fields['eal_min']
        eal_max     = Format-ProbeHex $fields['eal_max']
        cause       = Format-ProbeHex $fields['cause']
        status      = Format-ProbeHex $fields['status']
    }
}

function Read-RsxAuditorRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Auditor:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames        = Convert-ProbeNumber $fields['frames']
        submits       = Convert-ProbeNumber $fields['submits']
        waits         = Convert-ProbeNumber $fields['waits']
        signals       = Convert-ProbeNumber $fields['signals']
        flush_req     = Convert-ProbeNumber $fields['flush_req']
        async_req     = Convert-ProbeNumber $fields['async_req']
        hard_sync     = Convert-ProbeNumber $fields['hard_sync']
        rp_break      = Convert-ProbeNumber $fields['rp_break']
        all_barriers  = Convert-ProbeNumber $fields['all']
        pipe          = $fields['pipe']
        detile        = Convert-ProbeNumber $fields['detile']
        simple_upload = Convert-ProbeNumber $fields['simple_upload']
    }
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw "Pass -RunDir or -LogPath."
    }

    $LogPath = Resolve-ProbeLogPath $RunDir
}

$LogPath = Resolve-ProbePath $LogPath
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "Probe log not found: $LogPath"
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
if ([string]::IsNullOrWhiteSpace($MfcShapeCsvPath)) {
    $MfcShapeCsvPath = Join-Path $RunDir "eternal-sonata-mfc-shape-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($MfcLadderCsvPath)) {
    $MfcLadderCsvPath = Join-Path $RunDir "eternal-sonata-mfc-ladder-profile.csv"
}

$records = New-Object System.Collections.Generic.List[object]
$rsxAuditorRecords = New-Object System.Collections.Generic.List[object]
$mfcShapeRecords = New-Object System.Collections.Generic.List[object]
$mfcLadderRecords = New-Object System.Collections.Generic.List[object]
$mfcShapeGroups = @{}
$mfcShapeRawRecords = [UInt64]0
foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
    $record = Read-ProbeRecord $line
    if ($null -ne $record) {
        $records.Add($record) | Out-Null
    }

    $rsxRecord = Read-RsxAuditorRecord $line
    if ($null -ne $rsxRecord) {
        $rsxAuditorRecords.Add($rsxRecord) | Out-Null
    }

    $mfcShapeRecord = Read-MfcShapeRecord $line
    if ($null -ne $mfcShapeRecord) {
        $mfcShapeRawRecords++
        $key = @(
            $mfcShapeRecord.mode,
            $mfcShapeRecord.title,
            $mfcShapeRecord.group_name,
            $mfcShapeRecord.spu_name,
            $mfcShapeRecord.entry,
            $mfcShapeRecord.image_sig,
            $mfcShapeRecord.pc,
            $mfcShapeRecord.block_hash,
            $mfcShapeRecord.cmd,
            $mfcShapeRecord.tag,
            $mfcShapeRecord.size,
            $mfcShapeRecord.lsa,
            $mfcShapeRecord.flags
        ) -join "|"

        $minValue = Convert-ProbeNumber $mfcShapeRecord.eal_min
        $maxValue = Convert-ProbeNumber $mfcShapeRecord.eal_max

        if (-not $mfcShapeGroups.ContainsKey($key)) {
            $mfcShapeGroups[$key] = [pscustomobject]@{
                mode       = $mfcShapeRecord.mode
                title      = $mfcShapeRecord.title
                group      = $mfcShapeRecord.group
                group_name = $mfcShapeRecord.group_name
                spu        = $mfcShapeRecord.spu
                spu_index  = $mfcShapeRecord.spu_index
                spu_name   = $mfcShapeRecord.spu_name
                entry      = $mfcShapeRecord.entry
                image_sig  = $mfcShapeRecord.image_sig
                pc         = $mfcShapeRecord.pc
                block_hash = $mfcShapeRecord.block_hash
                cmd        = $mfcShapeRecord.cmd
                tag        = $mfcShapeRecord.tag
                size       = $mfcShapeRecord.size
                lsa        = $mfcShapeRecord.lsa
                flags      = $mfcShapeRecord.flags
                count      = $mfcShapeRecord.count
                bytes      = $mfcShapeRecord.bytes
                eal_first  = $mfcShapeRecord.eal_first
                eal_last   = $mfcShapeRecord.eal_last
                eal_min    = $mfcShapeRecord.eal_min
                eal_max    = $mfcShapeRecord.eal_max
                overflow   = $mfcShapeRecord.overflow
                cause      = $mfcShapeRecord.cause
                status     = $mfcShapeRecord.status
                eal_min_value = $minValue
                eal_max_value = $maxValue
            }
        } else {
            $aggregate = $mfcShapeGroups[$key]
            $aggregate.count += $mfcShapeRecord.count
            $aggregate.bytes += $mfcShapeRecord.bytes
            $aggregate.eal_last = $mfcShapeRecord.eal_last
            if ($minValue -lt $aggregate.eal_min_value) {
                $aggregate.eal_min_value = $minValue
                $aggregate.eal_min = $mfcShapeRecord.eal_min
            }
            if ($maxValue -gt $aggregate.eal_max_value) {
                $aggregate.eal_max_value = $maxValue
                $aggregate.eal_max = $mfcShapeRecord.eal_max
            }
            if ($mfcShapeRecord.overflow -gt $aggregate.overflow) {
                $aggregate.overflow = $mfcShapeRecord.overflow
            }
        }
    }

    $mfcLadderRecord = Read-MfcLadderRecord $line
    if ($null -ne $mfcLadderRecord) {
        $mfcLadderRecords.Add($mfcLadderRecord) | Out-Null
    }
}

foreach ($shape in $mfcShapeGroups.Values) {
    $mfcShapeRecords.Add($shape) | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata GPU Probe Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format o)") | Out-Null
$lines.Add("- Log: $LogPath") | Out-Null
$lines.Add("- Records: $($records.Count)") | Out-Null
$lines.Add("- MFC shape records: $mfcShapeRawRecords raw, $($mfcShapeRecords.Count) aggregated") | Out-Null
$lines.Add("- MFC ladder records: $($mfcLadderRecords.Count)") | Out-Null
$lines.Add("- RSX auditor records: $($rsxAuditorRecords.Count)") | Out-Null
$lines.Add("- Top rows: $Top") | Out-Null

if ($records.Count -eq 0) {
    $lines.Add("") | Out-Null
    $lines.Add('No `Eternal Sonata GPU/DMA candidate probe` records were found.') | Out-Null
    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "GPU probe summary: $OutPath"
    return
}

$records | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$lines.Add("- CSV: $CsvPath") | Out-Null
if ($mfcShapeRecords.Count -gt 0) {
    $mfcShapeRecords |
        Select-Object mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,block_hash,cmd,tag,size,lsa,flags,count,bytes,eal_first,eal_last,eal_min,eal_max,overflow,cause,status |
        Export-Csv -LiteralPath $MfcShapeCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC shape CSV: $MfcShapeCsvPath") | Out-Null
}
if ($mfcLadderRecords.Count -gt 0) {
    $mfcLadderRecords |
        Select-Object mode,ladder_mode,title,group,group_name,spu,spu_index,spu_name,entry,image_sig,pc,last_lsa,eligible,verify_hits,fast_hits,blocked,mismatches,bytes,eal_first,eal_last,eal_min,eal_max,cause,status |
        Export-Csv -LiteralPath $MfcLadderCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- MFC ladder CSV: $MfcLadderCsvPath") | Out-Null
}

$totalBytes = [UInt64](($records | Measure-Object -Property total_bytes -Sum).Sum)
$maxRecord = $records | Sort-Object -Property total_bytes -Descending | Select-Object -First 1
$rsxRecords = @($records | Where-Object { $_.rsx_get_bytes -gt 0 -or $_.rsx_put_bytes -gt 0 })
$lines.Add("- Total observed DMA bytes: $(Format-ProbeBytes $totalBytes)") | Out-Null
$lines.Add(('- Largest single job: {0} in `{1}` / `{2}`' -f (Format-ProbeBytes $maxRecord.total_bytes), $maxRecord.group_name, $maxRecord.spu_name)) | Out-Null
$lines.Add("- RSX-local traffic records: $($rsxRecords.Count)") | Out-Null
$fitGroups = @($records | Group-Object -Property offload_fit | Sort-Object -Property Count -Descending)
$lines.Add("- Offload fit mix: $(@($fitGroups | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')") | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Top Candidates By DMA Bytes") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Fit | Dispatch | Group | SPU | Image | Pattern | Total | GET | PUT | List GET | List PUT | RSX GET | RSX PUT | Cmds | List Cmds | Max DMA | PC | Block | EA |") | Out-Null
$lines.Add("| ---: | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |") | Out-Null

$rank = 1
foreach ($record in @($records | Sort-Object -Property total_bytes -Descending | Select-Object -First $Top)) {
    $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | `{4}` | `{5}` | `{6}` | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | {15} | {16} | `{17}` | `{18}` | `{19}` |' -f $rank, $record.offload_fit, $record.dispatch_risk, $record.group_name, $record.spu_name, $record.image_sig, $record.pattern_sig, (Format-ProbeBytes $record.total_bytes), (Format-ProbeBytes $record.get_bytes), (Format-ProbeBytes $record.put_bytes), (Format-ProbeBytes $record.list_get_bytes), (Format-ProbeBytes $record.list_put_bytes), (Format-ProbeBytes $record.rsx_get_bytes), (Format-ProbeBytes $record.rsx_put_bytes), $record.cmd_count, $record.list_cmd_count, (Format-ProbeBytes $record.max_dma_size), $record.max_dma_pc, $record.max_dma_block_hash, $record.max_dma_ea)) | Out-Null
    $rank++
}

$lines.Add("") | Out-Null
$lines.Add("## Offload Fit Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Fit | Records | Sum Total | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null

foreach ($fitGroup in $fitGroups) {
    $fitRecords = @($fitGroup.Group)
    $fitSum = [UInt64](($fitRecords | Measure-Object -Property total_bytes -Sum).Sum)
    $sample = $fitRecords | Select-Object -First 1
    $lines.Add(('| `{0}` | {1} | {2} | {3} |' -f $fitGroup.Name, $fitGroup.Count, (Format-ProbeBytes $fitSum), $sample.reading)) | Out-Null
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

if ($mfcShapeRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC Shape Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | PC | Cmd | Flags | Count | Bytes | Size | Tag | LSA | EAL Range | First -> Last EAL | Group | SPU | Image | Block | Overflow |") | Out-Null
    $lines.Add("| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | ---: |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcShapeRecords | Sort-Object -Property count, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | `{3}` | {4} | {5} | {6} | {7} | `{8}` | `{9}`-`{10}` | `{11}` -> `{12}` | `{13}` | `{14}` | `{15}` | `{16}` | {17} |' -f
            $rank,
            $record.pc,
            $record.cmd,
            (Format-MfcShapeFlags $record.flags),
            $record.count,
            (Format-ProbeBytes $record.bytes),
            $record.size,
            $record.tag,
            $record.lsa,
            $record.eal_min,
            $record.eal_max,
            $record.eal_first,
            $record.eal_last,
            $record.group_name,
            $record.spu_name,
            $record.image_sig,
            $record.block_hash,
            $record.overflow)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC shape reading: high counts with a small command/size/tag/LSA set are a codegen/HLE candidate; many one-off rows or large overflow means the path is still too dynamic for a fast path.") | Out-Null
}

if ($mfcLadderRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## MFC 0x25cc Ladder Gate") | Out-Null
    $lines.Add("") | Out-Null

    $ladderEligible = [UInt64](($mfcLadderRecords | Measure-Object -Property eligible -Sum).Sum)
    $ladderVerify = [UInt64](($mfcLadderRecords | Measure-Object -Property verify_hits -Sum).Sum)
    $ladderFast = [UInt64](($mfcLadderRecords | Measure-Object -Property fast_hits -Sum).Sum)
    $ladderBlocked = [UInt64](($mfcLadderRecords | Measure-Object -Property blocked -Sum).Sum)
    $ladderMismatches = [UInt64](($mfcLadderRecords | Measure-Object -Property mismatches -Sum).Sum)
    $ladderBytes = [UInt64](($mfcLadderRecords | Measure-Object -Property bytes -Sum).Sum)

    $lines.Add("- Eligible hits: $ladderEligible") | Out-Null
    $lines.Add("- Verify hits: $ladderVerify") | Out-Null
    $lines.Add("- Fast hits: $ladderFast") | Out-Null
    $lines.Add("- Blocked by generic MFC ordering: $ladderBlocked") | Out-Null
    $lines.Add("- Ordering mismatches: $ladderMismatches") | Out-Null
    $lines.Add("- Ladder bytes: $(Format-ProbeBytes $ladderBytes)") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Mode | PC | Eligible | Verify | Fast | Blocked | Mismatches | Bytes | Last LSA | EAL Range | Group | SPU | Image |") | Out-Null
    $lines.Add("| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($record in @($mfcLadderRecords | Sort-Object -Property eligible, bytes -Descending | Select-Object -First $Top)) {
        $lines.Add(('| {0} | `{1}` | `{2}` | {3} | {4} | {5} | {6} | {7} | {8} | `{9}` | `{10}`-`{11}` | `{12}` | `{13}` | `{14}` |' -f
            $rank,
            $record.ladder_mode,
            $record.pc,
            $record.eligible,
            $record.verify_hits,
            $record.fast_hits,
            $record.blocked,
            $record.mismatches,
            (Format-ProbeBytes $record.bytes),
            $record.last_lsa,
            $record.eal_min,
            $record.eal_max,
            $record.group_name,
            $record.spu_name,
            $record.image_sig)) | Out-Null
        $rank++
    }

    $lines.Add("") | Out-Null
    $lines.Add("MFC ladder reading: verify mode should show eligible hits with zero ordering mismatches before fast mode is trusted. A fast-mode FPS win here would be a CPU/SPU dispatch/codegen win, not proof of GPU-resident work.") | Out-Null
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

if ($rsxAuditorRecords.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## RSX Auditor Snapshot") | Out-Null
    $lines.Add("") | Out-Null

    $auditorFrames = [UInt64](($rsxAuditorRecords | Measure-Object -Property frames -Sum).Sum)
    $auditorSubmits = [UInt64](($rsxAuditorRecords | Measure-Object -Property submits -Sum).Sum)
    $auditorHardSync = [UInt64](($rsxAuditorRecords | Measure-Object -Property hard_sync -Sum).Sum)
    $auditorRenderPassBreaks = [UInt64](($rsxAuditorRecords | Measure-Object -Property rp_break -Sum).Sum)
    $auditorDetile = [UInt64](($rsxAuditorRecords | Measure-Object -Property detile -Sum).Sum)
    $auditorUploads = [UInt64](($rsxAuditorRecords | Measure-Object -Property simple_upload -Sum).Sum)

    $lines.Add("- Auditor frames: $auditorFrames") | Out-Null
    $lines.Add("- Queue submits: $auditorSubmits") | Out-Null
    $lines.Add("- Hard sync flushes: $auditorHardSync") | Out-Null
    $lines.Add("- Render-pass barrier breaks: $auditorRenderPassBreaks") | Out-Null
    $lines.Add("- Detile jobs: $auditorDetile") | Out-Null
    $lines.Add("- Simple uploads: $auditorUploads") | Out-Null
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
