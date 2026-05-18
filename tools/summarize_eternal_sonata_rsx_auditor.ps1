param(
    [string]$RunDir = "",
    [string]$LogPath = "",
    [int]$Top = 15,
    [string]$OutPath = "",
    [string]$CsvPath = ""
)

$ErrorActionPreference = "Stop"

function Resolve-AuditorPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-AuditorLogPath {
    param([string]$RunDir)

    $root = Resolve-AuditorPath $RunDir
    $candidates = @(
        "thor-rsx-auditor-logcat.txt",
        "RPCS3.log",
        "logcat-full.txt",
        "logcat-live.txt",
        "RPCSX.log",
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

    return Join-Path $root "thor-rsx-auditor-logcat.txt"
}

function Convert-AuditorNumber {
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

function Convert-AuditorDecimal {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [double]0.0
    }

    return [double]::Parse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-AuditorDecimal {
    param([double]$Value, [int]$Digits = 2)

    return $Value.ToString("N$Digits", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-AuditorRate {
    param([double]$Value, [UInt64]$Frames, [int]$Scale = 60)

    if ($Frames -eq 0) {
        return "0"
    }

    return Format-AuditorDecimal (($Value * [double]$Scale) / [double]$Frames)
}

function Split-AuditorTuple {
    param([AllowNull()][string]$Value, [int]$Count)

    $result = New-Object System.Collections.Generic.List[UInt64]
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        foreach ($part in $Value.Split('/')) {
            if ($result.Count -lt $Count) {
                $result.Add((Convert-AuditorNumber $part)) | Out-Null
            }
        }
    }

    while ($result.Count -lt $Count) {
        $result.Add([UInt64]0) | Out-Null
    }

    return @($result)
}

function Split-AuditorImageSourceTuple {
    param([hashtable]$Fields, [string]$Prefix)

    $newKey = "${Prefix}(unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up)"
    if ($Fields.ContainsKey($newKey)) {
        return Split-AuditorTuple $Fields[$newKey] 10
    }

    $oldKey = "${Prefix}(unk/rt/tc/draw/pres/tex/up)"
    $old = Split-AuditorTuple $Fields[$oldKey] 7
    return @(
        $old[0],
        [UInt64]0,
        [UInt64]0,
        [UInt64]0,
        $old[1],
        $old[2],
        $old[3],
        $old[4],
        $old[5],
        $old[6]
    )
}

function Get-AuditorPressure {
    param([object]$Record)

    if ($Record.pipe_slow -gt 0 -or $Record.pipe_us -ge 1000000) {
        return "pipeline-stutter"
    }

    if ($Record.rp_break_texture -gt 0 -or $Record.tex_depth -gt 0 -or $Record.tex_color -gt 0) {
        return "tile-locality-texture"
    }

    if ($Record.rp_break_image -gt 0) {
        return "tile-locality-image"
    }

    if ($Record.dma_transfer_all -gt 0 -or $Record.dma_transfer_host -gt 0) {
        return "dma-fence-bandwidth"
    }

    if ($Record.hard_sync -gt 0) {
        return "cpu-gpu-drain"
    }

    if ($Record.detile -gt 0 -or $Record.simple_upload -gt 0) {
        return "upload-detile-bandwidth"
    }

    if ($Record.barrier_mb -gt 0.0 -or $Record.barrier_buffer -gt 0) {
        return "buffer-barrier-bandwidth"
    }

    return "low"
}

function Get-AuditorScore {
    param([object]$Record)

    return (
        ([double]$Record.rp_break * 4.0) +
        ([double]$Record.hard_sync * 3.0) +
        ([double]$Record.dma_mb * 8.0) +
        ([double]$Record.dma_host_mb * 8.0) +
        ([double]$Record.barrier_mb * 0.25) +
        ([double]$Record.pipe_slow * 5.0) +
        ([double]$Record.pipe_us / 1000000.0) +
        ([double]$Record.in_mb * 4.0) +
        ([double]$Record.out_mb * 4.0) +
        ([double]$Record.upload_mb * 4.0)
    )
}

function Read-RsxAuditorRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Auditor:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    $rpBreak = Split-AuditorTuple $fields['rp_break(g/b/i/t)'] 4
    $barriers = Split-AuditorTuple $fields['barriers(g/b/i/t/all)'] 5
    $imageSources = Split-AuditorImageSourceTuple $fields 'img_src'
    $imageBreakSources = Split-AuditorImageSourceTuple $fields 'img_break'
    $pipe = Split-AuditorTuple $fields['pipe(g/c/slow/us)'] 4

    $record = [pscustomobject]@{
        frames            = Convert-AuditorNumber $fields['frames']
        submits           = Convert-AuditorNumber $fields['submits']
        waits             = Convert-AuditorNumber $fields['waits']
        signals           = Convert-AuditorNumber $fields['signals']
        flush_req         = Convert-AuditorNumber $fields['flush_req']
        async_req         = Convert-AuditorNumber $fields['async_req']
        hard_sync         = Convert-AuditorNumber $fields['hard_sync']
        rp_begin          = Convert-AuditorNumber $fields['rp_begin']
        rp_end            = Convert-AuditorNumber $fields['rp_end']
        rp_break          = Convert-AuditorNumber $fields['rp_break']
        rp_break_global   = $rpBreak[0]
        rp_break_buffer   = $rpBreak[1]
        rp_break_image    = $rpBreak[2]
        rp_break_texture  = $rpBreak[3]
        barrier_global    = $barriers[0]
        barrier_buffer    = $barriers[1]
        barrier_image     = $barriers[2]
        barrier_texture   = $barriers[3]
        barrier_all       = $barriers[4]
        barrier_mb        = Convert-AuditorDecimal $fields['barrier_mb']
        image_src_unknown = $imageSources[0]
        image_src_rt_res  = $imageSources[1]
        image_src_rt_unres = $imageSources[2]
        image_src_rt_post = $imageSources[3]
        image_src_rt_other = $imageSources[4]
        image_src_tc      = $imageSources[5]
        image_src_draw    = $imageSources[6]
        image_src_present = $imageSources[7]
        image_src_texture = $imageSources[8]
        image_src_up      = $imageSources[9]
        image_break_unknown = $imageBreakSources[0]
        image_break_rt_res  = $imageBreakSources[1]
        image_break_rt_unres = $imageBreakSources[2]
        image_break_rt_post = $imageBreakSources[3]
        image_break_rt_other = $imageBreakSources[4]
        image_break_tc      = $imageBreakSources[5]
        image_break_draw    = $imageBreakSources[6]
        image_break_present = $imageBreakSources[7]
        image_break_texture = $imageBreakSources[8]
        image_break_up      = $imageBreakSources[9]
        tex_color         = Convert-AuditorNumber $fields['tex_color']
        tex_depth         = Convert-AuditorNumber $fields['tex_depth']
        tex_skip          = Convert-AuditorNumber $fields['tex_skip']
        depth_skip        = Convert-AuditorNumber $fields['depth_skip']
        forced_skip       = Convert-AuditorNumber $fields['forced_skip']
        post_elide        = Convert-AuditorNumber $fields['post_elide']
        post_persist      = Convert-AuditorNumber $fields['post_persist']
        dma_transfer_all  = Convert-AuditorNumber $fields['dma_transfer_all']
        dma_mb            = Convert-AuditorDecimal $fields['dma_mb']
        dma_transfer_host = Convert-AuditorNumber $fields['dma_transfer_host']
        dma_host_mb       = Convert-AuditorDecimal $fields['dma_host_mb']
        query_wait        = Convert-AuditorNumber $fields['query_wait']
        query_slots       = Convert-AuditorNumber $fields['slots']
        pipe_graphics     = $pipe[0]
        pipe_compute      = $pipe[1]
        pipe_slow         = $pipe[2]
        pipe_us           = $pipe[3]
        detile            = Convert-AuditorNumber $fields['detile']
        in_mb             = Convert-AuditorDecimal $fields['in_mb']
        out_mb            = Convert-AuditorDecimal $fields['out_mb']
        simple_upload     = Convert-AuditorNumber $fields['simple_upload']
        upload_mb         = Convert-AuditorDecimal $fields['upload_mb']
    }

    $record | Add-Member -NotePropertyName pressure -NotePropertyValue (Get-AuditorPressure $record)
    $record | Add-Member -NotePropertyName pressure_score -NotePropertyValue (Get-AuditorScore $record)
    return $record
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw "Pass -RunDir or -LogPath."
    }

    $LogPath = Resolve-AuditorLogPath $RunDir
}

$LogPath = Resolve-AuditorPath $LogPath
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "RSX auditor log not found: $LogPath"
}

if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $RunDir = Split-Path -Parent $LogPath
} else {
    $RunDir = Resolve-AuditorPath $RunDir
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunDir "eternal-sonata-rsx-auditor-summary.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunDir "eternal-sonata-rsx-auditor-records.csv"
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
    $record = Read-RsxAuditorRecord $line
    if ($null -ne $record) {
        $records.Add($record) | Out-Null
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata RSX Auditor Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $(Get-Date -Format o)") | Out-Null
$lines.Add("- Log: $LogPath") | Out-Null
$lines.Add("- Records: $($records.Count)") | Out-Null
$lines.Add("- Top rows: $Top") | Out-Null

if ($records.Count -eq 0) {
    $lines.Add("") | Out-Null
    $lines.Add("No `Thor RSX Auditor:` records were found.") | Out-Null
    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Host "RSX auditor summary: $OutPath"
    return
}

$records | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
$lines.Add("- CSV: $CsvPath") | Out-Null

$totalFrames = [UInt64](($records | Measure-Object -Property frames -Sum).Sum)
$totalSubmits = [UInt64](($records | Measure-Object -Property submits -Sum).Sum)
$totalWaits = [UInt64](($records | Measure-Object -Property waits -Sum).Sum)
$totalSignals = [UInt64](($records | Measure-Object -Property signals -Sum).Sum)
$totalFlushReq = [UInt64](($records | Measure-Object -Property flush_req -Sum).Sum)
$totalHardSync = [UInt64](($records | Measure-Object -Property hard_sync -Sum).Sum)
$totalRpBreak = [UInt64](($records | Measure-Object -Property rp_break -Sum).Sum)
$totalRpBreakGlobal = [UInt64](($records | Measure-Object -Property rp_break_global -Sum).Sum)
$totalRpBreakBuffer = [UInt64](($records | Measure-Object -Property rp_break_buffer -Sum).Sum)
$totalRpBreakImage = [UInt64](($records | Measure-Object -Property rp_break_image -Sum).Sum)
$totalRpBreakTexture = [UInt64](($records | Measure-Object -Property rp_break_texture -Sum).Sum)
$totalBarrierGlobal = [UInt64](($records | Measure-Object -Property barrier_global -Sum).Sum)
$totalBarrierBuffer = [UInt64](($records | Measure-Object -Property barrier_buffer -Sum).Sum)
$totalBarrierImage = [UInt64](($records | Measure-Object -Property barrier_image -Sum).Sum)
$totalBarrierTexture = [UInt64](($records | Measure-Object -Property barrier_texture -Sum).Sum)
$totalBarrierAll = [UInt64](($records | Measure-Object -Property barrier_all -Sum).Sum)
$totalBarrierMb = [double](($records | Measure-Object -Property barrier_mb -Sum).Sum)
$totalImageSrcUnknown = [UInt64](($records | Measure-Object -Property image_src_unknown -Sum).Sum)
$totalImageSrcRtRes = [UInt64](($records | Measure-Object -Property image_src_rt_res -Sum).Sum)
$totalImageSrcRtUnres = [UInt64](($records | Measure-Object -Property image_src_rt_unres -Sum).Sum)
$totalImageSrcRtPost = [UInt64](($records | Measure-Object -Property image_src_rt_post -Sum).Sum)
$totalImageSrcRtOther = [UInt64](($records | Measure-Object -Property image_src_rt_other -Sum).Sum)
$totalImageSrcTc = [UInt64](($records | Measure-Object -Property image_src_tc -Sum).Sum)
$totalImageSrcDraw = [UInt64](($records | Measure-Object -Property image_src_draw -Sum).Sum)
$totalImageSrcPresent = [UInt64](($records | Measure-Object -Property image_src_present -Sum).Sum)
$totalImageSrcTexture = [UInt64](($records | Measure-Object -Property image_src_texture -Sum).Sum)
$totalImageSrcUp = [UInt64](($records | Measure-Object -Property image_src_up -Sum).Sum)
$totalImageBreakUnknown = [UInt64](($records | Measure-Object -Property image_break_unknown -Sum).Sum)
$totalImageBreakRtRes = [UInt64](($records | Measure-Object -Property image_break_rt_res -Sum).Sum)
$totalImageBreakRtUnres = [UInt64](($records | Measure-Object -Property image_break_rt_unres -Sum).Sum)
$totalImageBreakRtPost = [UInt64](($records | Measure-Object -Property image_break_rt_post -Sum).Sum)
$totalImageBreakRtOther = [UInt64](($records | Measure-Object -Property image_break_rt_other -Sum).Sum)
$totalImageBreakTc = [UInt64](($records | Measure-Object -Property image_break_tc -Sum).Sum)
$totalImageBreakDraw = [UInt64](($records | Measure-Object -Property image_break_draw -Sum).Sum)
$totalImageBreakPresent = [UInt64](($records | Measure-Object -Property image_break_present -Sum).Sum)
$totalImageBreakTexture = [UInt64](($records | Measure-Object -Property image_break_texture -Sum).Sum)
$totalImageBreakUp = [UInt64](($records | Measure-Object -Property image_break_up -Sum).Sum)
$totalTexColor = [UInt64](($records | Measure-Object -Property tex_color -Sum).Sum)
$totalTexDepth = [UInt64](($records | Measure-Object -Property tex_depth -Sum).Sum)
$totalTexSkip = [UInt64](($records | Measure-Object -Property tex_skip -Sum).Sum)
$totalPostElide = [UInt64](($records | Measure-Object -Property post_elide -Sum).Sum)
$totalDmaAll = [UInt64](($records | Measure-Object -Property dma_transfer_all -Sum).Sum)
$totalDmaMb = [double](($records | Measure-Object -Property dma_mb -Sum).Sum)
$totalDmaHost = [UInt64](($records | Measure-Object -Property dma_transfer_host -Sum).Sum)
$totalDmaHostMb = [double](($records | Measure-Object -Property dma_host_mb -Sum).Sum)
$totalQueryWait = [UInt64](($records | Measure-Object -Property query_wait -Sum).Sum)
$totalPipeGraphics = [UInt64](($records | Measure-Object -Property pipe_graphics -Sum).Sum)
$totalPipeCompute = [UInt64](($records | Measure-Object -Property pipe_compute -Sum).Sum)
$totalPipeSlow = [UInt64](($records | Measure-Object -Property pipe_slow -Sum).Sum)
$totalPipeUs = [UInt64](($records | Measure-Object -Property pipe_us -Sum).Sum)
$totalDetile = [UInt64](($records | Measure-Object -Property detile -Sum).Sum)
$totalInMb = [double](($records | Measure-Object -Property in_mb -Sum).Sum)
$totalOutMb = [double](($records | Measure-Object -Property out_mb -Sum).Sum)
$totalUpload = [UInt64](($records | Measure-Object -Property simple_upload -Sum).Sum)
$totalUploadMb = [double](($records | Measure-Object -Property upload_mb -Sum).Sum)

$lines.Add("- Auditor frames: $totalFrames") | Out-Null
$lines.Add("- Queue submits: $totalSubmits ($(Format-AuditorRate $totalSubmits $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Hard sync flushes: $totalHardSync ($(Format-AuditorRate $totalHardSync $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Render-pass barrier breaks: $totalRpBreak ($(Format-AuditorRate $totalRpBreak $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Image barrier source totals unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up: $totalImageSrcUnknown/$totalImageSrcRtRes/$totalImageSrcRtUnres/$totalImageSrcRtPost/$totalImageSrcRtOther/$totalImageSrcTc/$totalImageSrcDraw/$totalImageSrcPresent/$totalImageSrcTexture/$totalImageSrcUp") | Out-Null
$lines.Add("- Image break source totals unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up: $totalImageBreakUnknown/$totalImageBreakRtRes/$totalImageBreakRtUnres/$totalImageBreakRtPost/$totalImageBreakRtOther/$totalImageBreakTc/$totalImageBreakDraw/$totalImageBreakPresent/$totalImageBreakTexture/$totalImageBreakUp") | Out-Null
$lines.Add("- Barrier-tracked buffer range: $(Format-AuditorDecimal $totalBarrierMb) MB") | Out-Null
$lines.Add("- DMA transfer fences: all=$totalDmaAll / host=$totalDmaHost, bytes=$(Format-AuditorDecimal ($totalDmaMb + $totalDmaHostMb)) MB") | Out-Null
$lines.Add("- Pipeline creates: graphics=$totalPipeGraphics compute=$totalPipeCompute slow=$totalPipeSlow total_us=$totalPipeUs") | Out-Null
$lines.Add("- Detile/upload: detile=$totalDetile in=$(Format-AuditorDecimal $totalInMb) MB out=$(Format-AuditorDecimal $totalOutMb) MB simple_upload=$totalUpload upload=$(Format-AuditorDecimal $totalUploadMb) MB") | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Totals") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Bucket | Total | Per 60 Frames | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null
$lines.Add(('| Queue submits | {0} | {1} | Driver submission pressure. |' -f $totalSubmits, (Format-AuditorRate $totalSubmits $totalFrames))) | Out-Null
$lines.Add(('| Wait semaphores | {0} | {1} | Queue dependency pressure. |' -f $totalWaits, (Format-AuditorRate $totalWaits $totalFrames))) | Out-Null
$lines.Add(('| Signal semaphores | {0} | {1} | Queue dependency pressure. |' -f $totalSignals, (Format-AuditorRate $totalSignals $totalFrames))) | Out-Null
$lines.Add(('| Flush requests | {0} | {1} | CPU/GPU drain or explicit submit pressure. |' -f $totalFlushReq, (Format-AuditorRate $totalFlushReq $totalFrames))) | Out-Null
$lines.Add(('| Hard sync flushes | {0} | {1} | Strong CPU/GPU drain signal. |' -f $totalHardSync, (Format-AuditorRate $totalHardSync $totalFrames))) | Out-Null
$lines.Add(('| Render-pass breaks | {0} | {1} | Tile-locality loss candidate on Adreno. |' -f $totalRpBreak, (Format-AuditorRate $totalRpBreak $totalFrames))) | Out-Null
$lines.Add(('| Break source g/b/i/t | {0}/{1}/{2}/{3} | - | Global/buffer/image/texture split. |' -f $totalRpBreakGlobal, $totalRpBreakBuffer, $totalRpBreakImage, $totalRpBreakTexture)) | Out-Null
$lines.Add(('| Barriers g/b/i/t/all | {0}/{1}/{2}/{3}/{4} | - | Synchronization narrowing targets. |' -f $totalBarrierGlobal, $totalBarrierBuffer, $totalBarrierImage, $totalBarrierTexture, $totalBarrierAll)) | Out-Null
$lines.Add(('| Image barriers unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up | {0}/{1}/{2}/{3}/{4}/{5}/{6}/{7}/{8}/{9} | - | Total image barriers by callsite bucket. |' -f $totalImageSrcUnknown, $totalImageSrcRtRes, $totalImageSrcRtUnres, $totalImageSrcRtPost, $totalImageSrcRtOther, $totalImageSrcTc, $totalImageSrcDraw, $totalImageSrcPresent, $totalImageSrcTexture, $totalImageSrcUp)) | Out-Null
$lines.Add(('| Image breaks unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up | {0}/{1}/{2}/{3}/{4}/{5}/{6}/{7}/{8}/{9} | - | Image barriers that ended an open render pass. |' -f $totalImageBreakUnknown, $totalImageBreakRtRes, $totalImageBreakRtUnres, $totalImageBreakRtPost, $totalImageBreakRtOther, $totalImageBreakTc, $totalImageBreakDraw, $totalImageBreakPresent, $totalImageBreakTexture, $totalImageBreakUp)) | Out-Null
$lines.Add(('| Barrier MB | {0} | {1} | Buffer-range traffic touched by barriers. |' -f (Format-AuditorDecimal $totalBarrierMb), (Format-AuditorRate $totalBarrierMb $totalFrames))) | Out-Null
$lines.Add(('| Texture barriers color/depth | {0}/{1} | - | Color versus depth feedback risk. |' -f $totalTexColor, $totalTexDepth)) | Out-Null
$lines.Add(('| Texture skips/post elides | {0}/{1} | - | Existing skip or post-barrier elision activity. |' -f $totalTexSkip, $totalPostElide)) | Out-Null
$lines.Add(('| DMA fences all/host | {0}/{1} | {2}/{3} | Candidate for narrower host-read or GPU-resident path. |' -f $totalDmaAll, $totalDmaHost, (Format-AuditorRate $totalDmaAll $totalFrames), (Format-AuditorRate $totalDmaHost $totalFrames))) | Out-Null
$lines.Add(('| DMA MB all/host | {0}/{1} | {2}/{3} | Bandwidth tied to transfer fences. |' -f (Format-AuditorDecimal $totalDmaMb), (Format-AuditorDecimal $totalDmaHostMb), (Format-AuditorRate $totalDmaMb $totalFrames), (Format-AuditorRate $totalDmaHostMb $totalFrames))) | Out-Null
$lines.Add(('| Query waits | {0} | {1} | Occlusion/query wait pressure if nonzero. |' -f $totalQueryWait, (Format-AuditorRate $totalQueryWait $totalFrames))) | Out-Null
$lines.Add(('| Pipeline creates g/c/slow | {0}/{1}/{2} | - | Warmup/stutter lane, not steady-state unless repeated. |' -f $totalPipeGraphics, $totalPipeCompute, $totalPipeSlow)) | Out-Null
$lines.Add(('| Pipeline create ms | {0} | {1} | Shader/pipeline creation wall time. |' -f (Format-AuditorDecimal ([double]$totalPipeUs / 1000.0)), (Format-AuditorRate ([double]$totalPipeUs / 1000.0) $totalFrames))) | Out-Null
$lines.Add(('| Detile in/out MB | {0}/{1} | {2}/{3} | Texture prep or layout conversion candidate. |' -f (Format-AuditorDecimal $totalInMb), (Format-AuditorDecimal $totalOutMb), (Format-AuditorRate $totalInMb $totalFrames), (Format-AuditorRate $totalOutMb $totalFrames))) | Out-Null
$lines.Add(('| Simple upload MB | {0} | {1} | CPU-to-GPU upload bandwidth candidate. |' -f (Format-AuditorDecimal $totalUploadMb), (Format-AuditorRate $totalUploadMb $totalFrames))) | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Top Intervals By Pressure") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Class | Frames | Score | Submits | Hard Sync | RP Break g/b/i/t | Barriers g/b/i/t/all | Barrier MB | DMA all/host MB | Pipe g/c/slow/ms | Detile in/out MB | Upload MB |") | Out-Null
$lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |") | Out-Null

$rank = 1
foreach ($record in @($records | Sort-Object -Property pressure_score -Descending | Select-Object -First $Top)) {
    $pipeMs = [double]$record.pipe_us / 1000.0
    $lines.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6}/{7}/{8}/{9} | {10}/{11}/{12}/{13}/{14} | {15} | {16}/{17} | {18}/{19}/{20}/{21} | {22}/{23} | {24} |' -f
        $rank,
        $record.pressure,
        $record.frames,
        (Format-AuditorDecimal $record.pressure_score),
        $record.submits,
        $record.hard_sync,
        $record.rp_break_global,
        $record.rp_break_buffer,
        $record.rp_break_image,
        $record.rp_break_texture,
        $record.barrier_global,
        $record.barrier_buffer,
        $record.barrier_image,
        $record.barrier_texture,
        $record.barrier_all,
        (Format-AuditorDecimal $record.barrier_mb),
        (Format-AuditorDecimal $record.dma_mb),
        (Format-AuditorDecimal $record.dma_host_mb),
        $record.pipe_graphics,
        $record.pipe_compute,
        $record.pipe_slow,
        (Format-AuditorDecimal $pipeMs),
        (Format-AuditorDecimal $record.in_mb),
        (Format-AuditorDecimal $record.out_mb),
        (Format-AuditorDecimal $record.upload_mb))) | Out-Null
    $rank++
}

$pressureGroups = @($records | Group-Object -Property pressure | Sort-Object -Property Count -Descending)
$lines.Add("") | Out-Null
$lines.Add("## Pressure Mix") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Class | Records | Frames | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null
foreach ($group in $pressureGroups) {
    $groupFrames = [UInt64](($group.Group | Measure-Object -Property frames -Sum).Sum)
    $reading = switch ($group.Name) {
        "pipeline-stutter" { "Pipeline creation is visible; separate warmup from steady-field FPS." }
        "tile-locality-texture" { "Texture/depth feedback is breaking render passes; strongest RSX-on-GPU locality target." }
        "tile-locality-image" { "Image barriers are breaking render passes; inspect layout transitions and preservation." }
        "dma-fence-bandwidth" { "Transfer fences/bytes dominate; narrow fence scope or keep producer/consumer GPU-resident." }
        "cpu-gpu-drain" { "Hard syncs drain GPU work; find caller before changing semantics." }
        "upload-detile-bandwidth" { "Texture prep/upload traffic is present; consider GPU-side conversion or caching." }
        "buffer-barrier-bandwidth" { "Buffer barriers touch large ranges; label callsites before optimizing." }
        default { "No single RSX pressure bucket dominates this interval." }
    }
    $lines.Add(('| `{0}` | {1} | {2} | {3} |' -f $group.Name, $group.Count, $groupFrames, $reading)) | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add('- `RSX on GPU` should mean fewer CPU/GPU drains, fewer render-pass breaks, and more GPU-resident texture/vertex/render-target traffic.') | Out-Null
$lines.Add('- High `rp_break` from texture or image barriers is an Adreno tile-locality target before compute offload.') | Out-Null
$lines.Add('- High DMA fence bytes point first at `VKTextureCache` transfer/fence scope and producer-consumer residency, not a new compute shader.') | Out-Null
$lines.Add('- Pipeline creates are a warmup/stutter lane; do not mix them with steady-field FPS claims.') | Out-Null
$lines.Add('- Pair this summary with screenshot/video correctness for field, first battle, and menu before promoting any fast path.') | Out-Null

$lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "RSX auditor summary: $OutPath"
Write-Host "RSX auditor CSV: $CsvPath"
