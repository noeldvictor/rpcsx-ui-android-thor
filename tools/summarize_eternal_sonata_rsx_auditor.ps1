param(
    [string]$RunDir = "",
    [string]$LogPath = "",
    [int]$Top = 15,
    [string]$OutPath = "",
    [string]$CsvPath = "",
    [string]$ResolveProfileCsvPath = "",
    [string]$BlitSourceProfileCsvPath = "",
    [string]$TextureBarrierProfileCsvPath = "",
    [string]$VertexUploadProfileCsvPath = "",
    [string]$IndexUploadProfileCsvPath = "",
    [string]$SourceBaseJoinCsvPath = "",
    [string]$SourceLocalEligibilityCsvPath = ""
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

function Format-ResolveReason {
    param([UInt64]$Reason)

    switch ($Reason) {
        1 { return "spill" }
        2 { return "transfer-read" }
        3 { return "memory-copy" }
        4 { return "texture-gather-slices" }
        5 { return "texture-fbo-copy" }
        6 { return "texture-fbo-sample" }
        7 { return "texture-fbo-wrap" }
        8 { return "surface-collapse" }
        9 { return "present" }
        10 { return "texture-cache-lock" }
        11 { return "surface-store-lookup" }
        12 { return "framebuffer-readback" }
        13 { return "blit-source" }
        14 { return "old-content-copy-source" }
        default { return "unknown" }
    }
}

function Format-BlitFlags {
    param([UInt64]$Flags)

    $names = New-Object System.Collections.Generic.List[string]
    $map = @(
        @{ bit = 0; name = "interpolate" },
        @{ bit = 1; name = "format-convert" },
        @{ bit = 2; name = "src-typeless" },
        @{ bit = 3; name = "dst-typeless" },
        @{ bit = 4; name = "null-region" },
        @{ bit = 5; name = "cached-dest" },
        @{ bit = 6; name = "dst-render-target" },
        @{ bit = 7; name = "src-depth" },
        @{ bit = 8; name = "dst-depth" },
        @{ bit = 9; name = "src-tiled" },
        @{ bit = 10; name = "dst-tiled" },
        @{ bit = 11; name = "dst-swizzled" },
        @{ bit = 12; name = "flip-horizontal" },
        @{ bit = 13; name = "flip-vertical" }
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

function Format-TextureBarrierFlags {
    param([UInt64]$Flags)

    $names = New-Object System.Collections.Generic.List[string]
    $map = @(
        @{ bit = 0; name = "depth" },
        @{ bit = 1; name = "read-only" },
        @{ bit = 2; name = "fbo-loop" },
        @{ bit = 3; name = "tracker-can-skip" },
        @{ bit = 4; name = "current-optimal" },
        @{ bit = 5; name = "renderpass-open" },
        @{ bit = 6; name = "bound" }
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

function Split-AuditorTextTuple {
    param([AllowNull()][string]$Value, [int]$Count)

    $result = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        foreach ($part in $Value.Split('/')) {
            if ($result.Count -lt $Count) {
                $result.Add($part) | Out-Null
            }
        }
    }

    while ($result.Count -lt $Count) {
        $result.Add("0") | Out-Null
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

    if ($Record.blit_cache_rp_fill -gt 0 -or $Record.blit_cache_rp_copy -gt 0 -or $Record.blit_cache_defer_fill -gt 0) {
        return "tile-locality-blit-cache"
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

    if (($Record.vertex_upload_persistent_mb + $Record.vertex_upload_volatile_mb + $Record.index_upload_mb) -gt 1.0) {
        return "vertex-index-upload"
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
        ([double]$Record.upload_mb * 4.0) +
        ([double]($Record.blit_cache_rp_fill + $Record.blit_cache_rp_copy + $Record.blit_cache_defer_fill) * 4.0) +
        ([double]($Record.vertex_upload_persistent_mb + $Record.vertex_upload_volatile_mb + $Record.index_upload_mb) * 4.0)
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
    $resolve = Split-AuditorTuple $fields['resolve(color/depth/skip_color/skip_depth)'] 4
    $pipe = Split-AuditorTuple $fields['pipe(g/c/slow/us)'] 4
    $depthFeedback = Split-AuditorTuple $fields['depth_feedback(prep_keep/prep_layout/prep_write/end_keep/end_layout/end_write/end_restore)'] 7
    $blitResolve = Split-AuditorTuple $fields['blit_resolve(fast/verify/reject)'] 3
    $blitResolvePathKey = 'blit_resolve_path(storage_fast/sampled_fast/storage_verify/sampled_verify)'
    $blitResolvePath = if ($fields.ContainsKey($blitResolvePathKey)) {
        Split-AuditorTuple $fields[$blitResolvePathKey] 4
    } else {
        @($blitResolve[0], [UInt64]0, $blitResolve[1], [UInt64]0)
    }
    $blitReject = Split-AuditorTuple $fields['blit_reject(region/typeless/format/rt/dispatch)'] 5
    $blitCache = Split-AuditorTuple $fields['blit_cache(hit/miss/fill/fanout/reject)'] 5
    $blitCacheTransferSrc = Split-AuditorTuple $fields['blit_cache_transfer_src(fill/fanout)'] 2
    $blitCacheRpKey = 'blit_cache_rp(fill/src_layout/copy/hit_copy)'
    $blitCacheRp = if ($fields.ContainsKey($blitCacheRpKey)) {
        Split-AuditorTuple $fields[$blitCacheRpKey] 4
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $blitCacheDeferKey = 'blit_cache_defer(fill/src_layout)'
    $blitCacheDefer = if ($fields.ContainsKey($blitCacheDeferKey)) {
        Split-AuditorTuple $fields[$blitCacheDeferKey] 2
    } else {
        @([UInt64]0, [UInt64]0)
    }
    $sourcePrefillKey = 'source_prefill(close/bound/hot/resolve/tagdirty)'
    $sourcePrefill = if ($fields.ContainsKey($sourcePrefillKey)) {
        Split-AuditorTuple $fields[$sourcePrefillKey] 5
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourcePrefillCacheKey = 'source_prefill_cache(attempt/hit/fill/reject)'
    $sourcePrefillCache = if ($fields.ContainsKey($sourcePrefillCacheKey)) {
        Split-AuditorTuple $fields[$sourcePrefillCacheKey] 4
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourcePrefillBeginKey = 'source_prefill_begin(call/rp/bound/hot/resolve/tagdirty)'
    $sourcePrefillBegin = if ($fields.ContainsKey($sourcePrefillBeginKey)) {
        Split-AuditorTuple $fields[$sourcePrefillBeginKey] 6
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceTransitionKey = 'source_transition(check/hot/retire/rp/resolve/tagdirty)'
    $sourceTransition = if ($fields.ContainsKey($sourceTransitionKey)) {
        Split-AuditorTuple $fields[$sourceTransitionKey] 6
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceWriterKey = 'source_writer(hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache)'
    $sourceWriter = if ($fields.ContainsKey($sourceWriterKey)) {
        Split-AuditorTuple $fields[$sourceWriterKey] 10
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceWriterTagKey = 'source_writer_tag(new/repeat/collision/zero)'
    $sourceWriterTag = if ($fields.ContainsKey($sourceWriterTagKey)) {
        Split-AuditorTuple $fields[$sourceWriterTagKey] 4
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceBlitStateKey = 'source_blit_state(hit/hot/rp/read/color/general/resolve/tagdirty)'
    $sourceBlitState = if ($fields.ContainsKey($sourceBlitStateKey)) {
        Split-AuditorTuple $fields[$sourceBlitStateKey] 8
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceFusedStateKey = 'source_fused_state(hit/hot/rp/read/color/general/resolve/tagdirty)'
    $sourceFusedState = if ($fields.ContainsKey($sourceFusedStateKey)) {
        Split-AuditorTuple $fields[$sourceFusedStateKey] 8
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $sourceFusedTagKey = 'source_fused_tag(new/repeat/collision/zero)'
    $sourceFusedTag = if ($fields.ContainsKey($sourceFusedTagKey)) {
        Split-AuditorTuple $fields[$sourceFusedTagKey] 4
    } else {
        @([UInt64]0, [UInt64]0, [UInt64]0, [UInt64]0)
    }
    $resolveBarrier = Split-AuditorTuple $fields['resolve_barrier(rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable)'] 7
    $resolveBreak = Split-AuditorTuple $fields['resolve_break(rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable)'] 7
    $presentUpload = Split-AuditorTuple $fields['present_upload(cpu/gpu)'] 2
    $presentUploadBytes = Split-AuditorTuple $fields['present_upload_bytes(cpu/gpu)'] 2
    $vertexUpload = Split-AuditorTextTuple $fields['vertex_upload(draws/cache_hit/cache_miss/persistent_mb/volatile_mb)'] 5
    $vertexSupersetCache = Split-AuditorTextTuple $fields['vertex_superset_cache(hit/miss/hit_mb)'] 3
    $vertexPersistentCacheKey = 'vertex_persistent_cache(hit/change/new/hit_mb)'
    $vertexPersistentCache = if ($fields.ContainsKey($vertexPersistentCacheKey)) {
        Split-AuditorTextTuple $fields[$vertexPersistentCacheKey] 4
    } else {
        @("0", "0", "0", "0")
    }
    $vertexPersistentVerifyKey = 'vertex_persistent_verify(hit/store/mismatch/hit_mb/store_mb)'
    $vertexPersistentVerify = if ($fields.ContainsKey($vertexPersistentVerifyKey)) {
        Split-AuditorTextTuple $fields[$vertexPersistentVerifyKey] 5
    } else {
        @("0", "0", "0", "0", "0")
    }
    $vertexPersistentFastKey = 'vertex_persistent_fast(hit/store/reject/hit_mb/store_mb)'
    $vertexPersistentFast = if ($fields.ContainsKey($vertexPersistentFastKey)) {
        Split-AuditorTextTuple $fields[$vertexPersistentFastKey] 5
    } else {
        @("0", "0", "0", "0", "0")
    }
    $vertexVolatileCache = Split-AuditorTextTuple $fields['vertex_volatile_cache(hit/miss/hit_mb)'] 3
    $indexUpload = Split-AuditorTextTuple $fields['index_upload(draws/emulated/restart/mb)'] 4
    $indexGpuConvert = Split-AuditorTextTuple $fields['index_gpu_convert(eligible/dispatch/reject/mb)'] 4
    $indexGpuCache = Split-AuditorTextTuple $fields['index_gpu_cache(hit/miss/hit_mb)'] 3
    $indexPersistentCacheKey = 'index_persistent_cache(hit/change/new/hit_mb)'
    $indexPersistentCache = if ($fields.ContainsKey($indexPersistentCacheKey)) {
        Split-AuditorTextTuple $fields[$indexPersistentCacheKey] 4
    } else {
        @("0", "0", "0", "0")
    }
    $indexPersistentVerifyKey = 'index_persistent_verify(hit/store/mismatch/hit_mb/store_mb)'
    $indexPersistentVerify = if ($fields.ContainsKey($indexPersistentVerifyKey)) {
        Split-AuditorTextTuple $fields[$indexPersistentVerifyKey] 5
    } else {
        @("0", "0", "0", "0", "0")
    }
    $indexPersistentFastKey = 'index_persistent_fast(hit/store/reject/hit_mb/store_mb)'
    $indexPersistentFast = if ($fields.ContainsKey($indexPersistentFastKey)) {
        Split-AuditorTextTuple $fields[$indexPersistentFastKey] 5
    } else {
        @("0", "0", "0", "0", "0")
    }

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
        resolve_color     = $resolve[0]
        resolve_depth     = $resolve[1]
        resolve_skip_color = $resolve[2]
        resolve_skip_depth = $resolve[3]
        resolve_barrier_rt_src = $resolveBarrier[0]
        resolve_barrier_rt_dst = $resolveBarrier[1]
        resolve_barrier_rt_restore = $resolveBarrier[2]
        resolve_barrier_rt_readable = $resolveBarrier[3]
        resolve_barrier_blit_src = $resolveBarrier[4]
        resolve_barrier_blit_restore = $resolveBarrier[5]
        resolve_barrier_blit_readable = $resolveBarrier[6]
        resolve_break_rt_src = $resolveBreak[0]
        resolve_break_rt_dst = $resolveBreak[1]
        resolve_break_rt_restore = $resolveBreak[2]
        resolve_break_rt_readable = $resolveBreak[3]
        resolve_break_blit_src = $resolveBreak[4]
        resolve_break_blit_restore = $resolveBreak[5]
        resolve_break_blit_readable = $resolveBreak[6]
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
        vertex_upload_draws = Convert-AuditorNumber $vertexUpload[0]
        vertex_upload_cache_hit = Convert-AuditorNumber $vertexUpload[1]
        vertex_upload_cache_miss = Convert-AuditorNumber $vertexUpload[2]
        vertex_upload_persistent_mb = Convert-AuditorDecimal $vertexUpload[3]
        vertex_upload_volatile_mb = Convert-AuditorDecimal $vertexUpload[4]
        vertex_superset_cache_hit = Convert-AuditorNumber $vertexSupersetCache[0]
        vertex_superset_cache_miss = Convert-AuditorNumber $vertexSupersetCache[1]
        vertex_superset_cache_hit_mb = Convert-AuditorDecimal $vertexSupersetCache[2]
        vertex_persistent_cache_hit = Convert-AuditorNumber $vertexPersistentCache[0]
        vertex_persistent_cache_change = Convert-AuditorNumber $vertexPersistentCache[1]
        vertex_persistent_cache_new = Convert-AuditorNumber $vertexPersistentCache[2]
        vertex_persistent_cache_hit_mb = Convert-AuditorDecimal $vertexPersistentCache[3]
        vertex_persistent_verify_hit = Convert-AuditorNumber $vertexPersistentVerify[0]
        vertex_persistent_verify_store = Convert-AuditorNumber $vertexPersistentVerify[1]
        vertex_persistent_verify_mismatch = Convert-AuditorNumber $vertexPersistentVerify[2]
        vertex_persistent_verify_hit_mb = Convert-AuditorDecimal $vertexPersistentVerify[3]
        vertex_persistent_verify_store_mb = Convert-AuditorDecimal $vertexPersistentVerify[4]
        vertex_persistent_fast_hit = Convert-AuditorNumber $vertexPersistentFast[0]
        vertex_persistent_fast_store = Convert-AuditorNumber $vertexPersistentFast[1]
        vertex_persistent_fast_reject = Convert-AuditorNumber $vertexPersistentFast[2]
        vertex_persistent_fast_hit_mb = Convert-AuditorDecimal $vertexPersistentFast[3]
        vertex_persistent_fast_store_mb = Convert-AuditorDecimal $vertexPersistentFast[4]
        vertex_volatile_cache_hit = Convert-AuditorNumber $vertexVolatileCache[0]
        vertex_volatile_cache_miss = Convert-AuditorNumber $vertexVolatileCache[1]
        vertex_volatile_cache_hit_mb = Convert-AuditorDecimal $vertexVolatileCache[2]
        index_upload_draws = Convert-AuditorNumber $indexUpload[0]
        index_upload_emulated = Convert-AuditorNumber $indexUpload[1]
        index_upload_restart = Convert-AuditorNumber $indexUpload[2]
        index_upload_mb = Convert-AuditorDecimal $indexUpload[3]
        index_gpu_convert_eligible = Convert-AuditorNumber $indexGpuConvert[0]
        index_gpu_convert_dispatch = Convert-AuditorNumber $indexGpuConvert[1]
        index_gpu_convert_reject = Convert-AuditorNumber $indexGpuConvert[2]
        index_gpu_convert_mb = Convert-AuditorDecimal $indexGpuConvert[3]
        index_gpu_cache_hit = Convert-AuditorNumber $indexGpuCache[0]
        index_gpu_cache_miss = Convert-AuditorNumber $indexGpuCache[1]
        index_gpu_cache_hit_mb = Convert-AuditorDecimal $indexGpuCache[2]
        index_persistent_cache_hit = Convert-AuditorNumber $indexPersistentCache[0]
        index_persistent_cache_change = Convert-AuditorNumber $indexPersistentCache[1]
        index_persistent_cache_new = Convert-AuditorNumber $indexPersistentCache[2]
        index_persistent_cache_hit_mb = Convert-AuditorDecimal $indexPersistentCache[3]
        index_persistent_verify_hit = Convert-AuditorNumber $indexPersistentVerify[0]
        index_persistent_verify_store = Convert-AuditorNumber $indexPersistentVerify[1]
        index_persistent_verify_mismatch = Convert-AuditorNumber $indexPersistentVerify[2]
        index_persistent_verify_hit_mb = Convert-AuditorDecimal $indexPersistentVerify[3]
        index_persistent_verify_store_mb = Convert-AuditorDecimal $indexPersistentVerify[4]
        index_persistent_fast_hit = Convert-AuditorNumber $indexPersistentFast[0]
        index_persistent_fast_store = Convert-AuditorNumber $indexPersistentFast[1]
        index_persistent_fast_reject = Convert-AuditorNumber $indexPersistentFast[2]
        index_persistent_fast_hit_mb = Convert-AuditorDecimal $indexPersistentFast[3]
        index_persistent_fast_store_mb = Convert-AuditorDecimal $indexPersistentFast[4]
        present_upload_cpu = $presentUpload[0]
        present_upload_gpu = $presentUpload[1]
        present_upload_cpu_bytes = $presentUploadBytes[0]
        present_upload_gpu_bytes = $presentUploadBytes[1]
        present_upload_cpu_mb = ([double]$presentUploadBytes[0] / 1048576.0)
        present_upload_gpu_mb = ([double]$presentUploadBytes[1] / 1048576.0)
        depth_feedback_prep_keep = $depthFeedback[0]
        depth_feedback_prep_layout = $depthFeedback[1]
        depth_feedback_prep_write = $depthFeedback[2]
        depth_feedback_end_keep = $depthFeedback[3]
        depth_feedback_end_layout = $depthFeedback[4]
        depth_feedback_end_write = $depthFeedback[5]
        depth_feedback_end_restore = $depthFeedback[6]
        blit_resolve_fast = $blitResolve[0]
        blit_resolve_verify = $blitResolve[1]
        blit_resolve_reject = $blitResolve[2]
        blit_resolve_storage_fast = $blitResolvePath[0]
        blit_resolve_sampled_fast = $blitResolvePath[1]
        blit_resolve_storage_verify = $blitResolvePath[2]
        blit_resolve_sampled_verify = $blitResolvePath[3]
        blit_reject_region = $blitReject[0]
        blit_reject_typeless = $blitReject[1]
        blit_reject_format = $blitReject[2]
        blit_reject_rt = $blitReject[3]
        blit_reject_dispatch = $blitReject[4]
        blit_cache_hit = $blitCache[0]
        blit_cache_miss = $blitCache[1]
        blit_cache_fill = $blitCache[2]
        blit_cache_fanout = $blitCache[3]
        blit_cache_reject = $blitCache[4]
        blit_cache_transfer_src_fill = $blitCacheTransferSrc[0]
        blit_cache_transfer_src_fanout = $blitCacheTransferSrc[1]
        blit_cache_rp_fill = $blitCacheRp[0]
        blit_cache_rp_src_layout = $blitCacheRp[1]
        blit_cache_rp_copy = $blitCacheRp[2]
        blit_cache_rp_hit_copy = $blitCacheRp[3]
        blit_cache_defer_fill = $blitCacheDefer[0]
        blit_cache_defer_src_layout = $blitCacheDefer[1]
        source_prefill_close = $sourcePrefill[0]
        source_prefill_bound = $sourcePrefill[1]
        source_prefill_hot = $sourcePrefill[2]
        source_prefill_resolve = $sourcePrefill[3]
        source_prefill_tagdirty = $sourcePrefill[4]
        source_prefill_cache_attempt = $sourcePrefillCache[0]
        source_prefill_cache_hit = $sourcePrefillCache[1]
        source_prefill_cache_fill = $sourcePrefillCache[2]
        source_prefill_cache_reject = $sourcePrefillCache[3]
        source_prefill_begin_call = $sourcePrefillBegin[0]
        source_prefill_begin_rp = $sourcePrefillBegin[1]
        source_prefill_begin_bound = $sourcePrefillBegin[2]
        source_prefill_begin_hot = $sourcePrefillBegin[3]
        source_prefill_begin_resolve = $sourcePrefillBegin[4]
        source_prefill_begin_tagdirty = $sourcePrefillBegin[5]
        source_transition_check = $sourceTransition[0]
        source_transition_hot = $sourceTransition[1]
        source_transition_retire = $sourceTransition[2]
        source_transition_rp = $sourceTransition[3]
        source_transition_resolve = $sourceTransition[4]
        source_transition_tagdirty = $sourceTransition[5]
        source_writer_hit = $sourceWriter[0]
        source_writer_hot = $sourceWriter[1]
        source_writer_fast = $sourceWriter[2]
        source_writer_full = $sourceWriter[3]
        source_writer_hot_fast = $sourceWriter[4]
        source_writer_hot_full = $sourceWriter[5]
        source_writer_hot_resolve = $sourceWriter[6]
        source_writer_hot_tagdirty = $sourceWriter[7]
        source_writer_hot_gtcache = $sourceWriter[8]
        source_writer_hot_lecache = $sourceWriter[9]
        source_writer_tag_new = $sourceWriterTag[0]
        source_writer_tag_repeat = $sourceWriterTag[1]
        source_writer_tag_collision = $sourceWriterTag[2]
        source_writer_tag_zero = $sourceWriterTag[3]
        source_blit_state_hit = $sourceBlitState[0]
        source_blit_state_hot = $sourceBlitState[1]
        source_blit_state_rp = $sourceBlitState[2]
        source_blit_state_read = $sourceBlitState[3]
        source_blit_state_color = $sourceBlitState[4]
        source_blit_state_general = $sourceBlitState[5]
        source_blit_state_resolve = $sourceBlitState[6]
        source_blit_state_tagdirty = $sourceBlitState[7]
        source_fused_state_hit = $sourceFusedState[0]
        source_fused_state_hot = $sourceFusedState[1]
        source_fused_state_rp = $sourceFusedState[2]
        source_fused_state_read = $sourceFusedState[3]
        source_fused_state_color = $sourceFusedState[4]
        source_fused_state_general = $sourceFusedState[5]
        source_fused_state_resolve = $sourceFusedState[6]
        source_fused_state_tagdirty = $sourceFusedState[7]
        source_fused_tag_new = $sourceFusedTag[0]
        source_fused_tag_repeat = $sourceFusedTag[1]
        source_fused_tag_collision = $sourceFusedTag[2]
        source_fused_tag_zero = $sourceFusedTag[3]
    }

    $record | Add-Member -NotePropertyName pressure -NotePropertyValue (Get-AuditorPressure $record)
    $record | Add-Member -NotePropertyName pressure_score -NotePropertyValue (Get-AuditorScore $record)
    return $record
}

function Read-RsxResolveProfileRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Resolve Profile:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames  = Convert-AuditorNumber $fields['frames']
        slot    = if ($fields.ContainsKey('slot')) { $fields['slot'] } else { "" }
        count   = Convert-AuditorNumber $fields['count']
        skips   = Convert-AuditorNumber $fields['skips']
        dup     = Convert-AuditorNumber $fields['dup']
        reason  = if ($fields.ContainsKey('reason')) { Convert-AuditorNumber $fields['reason'] } else { [UInt64]0 }
        depth   = Convert-AuditorNumber $fields['depth']
        fmt     = if ($fields.ContainsKey('fmt')) { $fields['fmt'] } else { "0x00000000" }
        w       = Convert-AuditorNumber $fields['w']
        h       = Convert-AuditorNumber $fields['h']
        samples = Convert-AuditorNumber $fields['samples']
        sx      = Convert-AuditorNumber $fields['sx']
        sy      = Convert-AuditorNumber $fields['sy']
        pitch   = Convert-AuditorNumber $fields['pitch']
        base    = if ($fields.ContainsKey('base')) { $fields['base'] } else { "0x00000000" }
        key     = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0000000000000000" }
    }
}

function Read-RsxBlitSourceProfileRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Blit Source Profile:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames    = Convert-AuditorNumber $fields['frames']
        slot      = if ($fields.ContainsKey('slot')) { $fields['slot'] } else { "" }
        count     = Convert-AuditorNumber $fields['count']
        src       = if ($fields.ContainsKey('src')) { $fields['src'] } else { "0x00000000" }
        dst       = if ($fields.ContainsKey('dst')) { $fields['dst'] } else { "0x00000000" }
        src_pitch = Convert-AuditorNumber $fields['src_pitch']
        dst_pitch = Convert-AuditorNumber $fields['dst_pitch']
        src_bpp   = Convert-AuditorNumber $fields['src_bpp']
        dst_bpp   = Convert-AuditorNumber $fields['dst_bpp']
        src_req   = if ($fields.ContainsKey('src_req')) { $fields['src_req'] } else { "0x0" }
        dst_req   = if ($fields.ContainsKey('dst_req')) { $fields['dst_req'] } else { "0x0" }
        src_fmt   = if ($fields.ContainsKey('src_fmt')) { $fields['src_fmt'] } else { "0x00000000" }
        dst_fmt   = if ($fields.ContainsKey('dst_fmt')) { $fields['dst_fmt'] } else { "0x00000000" }
        src_ctx   = Convert-AuditorNumber $fields['src_ctx']
        dst_ctx   = Convert-AuditorNumber $fields['dst_ctx']
        src_rect  = if ($fields.ContainsKey('src_rect')) { $fields['src_rect'] } else { "0/0/0/0" }
        dst_rect  = if ($fields.ContainsKey('dst_rect')) { $fields['dst_rect'] } else { "0/0/0/0" }
        flags     = if ($fields.ContainsKey('flags')) { Convert-AuditorNumber $fields['flags'] } else { [UInt64]0 }
        key       = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0000000000000000" }
    }
}

function Read-RsxTextureBarrierProfileRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Texture Barrier Profile:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames        = Convert-AuditorNumber $fields['frames']
        slot          = if ($fields.ContainsKey('slot')) { $fields['slot'] } else { "" }
        count         = Convert-AuditorNumber $fields['count']
        barriers      = Convert-AuditorNumber $fields['barriers']
        skip_readonly = Convert-AuditorNumber $fields['skip_readonly']
        skip_forced   = Convert-AuditorNumber $fields['skip_forced']
        flags         = if ($fields.ContainsKey('flags')) { Convert-AuditorNumber $fields['flags'] } else { [UInt64]0 }
        cur           = Convert-AuditorNumber $fields['cur']
        opt           = Convert-AuditorNumber $fields['opt']
        fmt           = if ($fields.ContainsKey('fmt')) { $fields['fmt'] } else { "0x00000000" }
        w             = Convert-AuditorNumber $fields['w']
        h             = Convert-AuditorNumber $fields['h']
        samples       = Convert-AuditorNumber $fields['samples']
        sx            = Convert-AuditorNumber $fields['sx']
        sy            = Convert-AuditorNumber $fields['sy']
        pitch         = Convert-AuditorNumber $fields['pitch']
        base          = if ($fields.ContainsKey('base')) { $fields['base'] } else { "0x00000000" }
        key           = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0000000000000000" }
    }
}

function Read-RsxVertexUploadProfileRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Vertex Upload Profile:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames          = Convert-AuditorNumber $fields['frames']
        slot            = if ($fields.ContainsKey('slot')) { $fields['slot'] } else { "" }
        count           = Convert-AuditorNumber $fields['count']
        cache_hit       = Convert-AuditorNumber $fields['cache_hit']
        cache_miss      = Convert-AuditorNumber $fields['cache_miss']
        persistent_mb   = Convert-AuditorDecimal $fields['persistent_mb']
        volatile_mb     = Convert-AuditorDecimal $fields['volatile_mb']
        cmd             = Convert-AuditorNumber $fields['cmd']
        prim            = Convert-AuditorNumber $fields['prim']
        attr            = if ($fields.ContainsKey('attr')) { $fields['attr'] } else { "0x0000" }
        blocks          = Convert-AuditorNumber $fields['blocks']
        volatile_blocks = Convert-AuditorNumber $fields['volatile_blocks']
        regs            = Convert-AuditorNumber $fields['regs']
        stride          = Convert-AuditorNumber $fields['stride']
        base            = if ($fields.ContainsKey('base')) { $fields['base'] } else { "0x00000000" }
        vertices        = Convert-AuditorNumber $fields['vertices']
        persistent_size = Convert-AuditorNumber $fields['persistent_size']
        volatile_size   = Convert-AuditorNumber $fields['volatile_size']
        key             = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0000000000000000" }
    }
}

function Read-RsxIndexUploadProfileRecord {
    param([string]$Line)

    if ($Line -notmatch 'Thor RSX Index Upload Profile:') {
        return $null
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_()\/]+)=(?<value>\S+)')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value
    }

    if (-not $fields.ContainsKey('frames')) {
        return $null
    }

    return [pscustomobject]@{
        frames      = Convert-AuditorNumber $fields['frames']
        slot        = if ($fields.ContainsKey('slot')) { $fields['slot'] } else { "" }
        count       = Convert-AuditorNumber $fields['count']
        emulated    = Convert-AuditorNumber $fields['emulated']
        restart     = Convert-AuditorNumber $fields['restart']
        mb          = Convert-AuditorDecimal $fields['mb']
        cmd         = Convert-AuditorNumber $fields['cmd']
        prim        = Convert-AuditorNumber $fields['prim']
        index_type  = Convert-AuditorNumber $fields['index_type']
        type_size   = Convert-AuditorNumber $fields['type_size']
        indices     = Convert-AuditorNumber $fields['indices']
        upload_size = Convert-AuditorNumber $fields['upload_size']
        immediate   = Convert-AuditorNumber $fields['immediate']
        key         = if ($fields.ContainsKey('key')) { $fields['key'] } else { "0x0000000000000000" }
    }
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
if ([string]::IsNullOrWhiteSpace($ResolveProfileCsvPath)) {
    $ResolveProfileCsvPath = Join-Path $RunDir "eternal-sonata-rsx-resolve-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($BlitSourceProfileCsvPath)) {
    $BlitSourceProfileCsvPath = Join-Path $RunDir "eternal-sonata-rsx-blit-source-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($TextureBarrierProfileCsvPath)) {
    $TextureBarrierProfileCsvPath = Join-Path $RunDir "eternal-sonata-rsx-texture-barrier-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($VertexUploadProfileCsvPath)) {
    $VertexUploadProfileCsvPath = Join-Path $RunDir "eternal-sonata-rsx-vertex-upload-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($IndexUploadProfileCsvPath)) {
    $IndexUploadProfileCsvPath = Join-Path $RunDir "eternal-sonata-rsx-index-upload-profile.csv"
}
if ([string]::IsNullOrWhiteSpace($SourceBaseJoinCsvPath)) {
    $SourceBaseJoinCsvPath = Join-Path $RunDir "eternal-sonata-rsx-source-base-join.csv"
}
if ([string]::IsNullOrWhiteSpace($SourceLocalEligibilityCsvPath)) {
    $SourceLocalEligibilityCsvPath = Join-Path $RunDir "eternal-sonata-rsx-source-local-eligibility.csv"
}

$records = New-Object System.Collections.Generic.List[object]
$resolveProfileRecords = New-Object System.Collections.Generic.List[object]
$blitSourceProfileRecords = New-Object System.Collections.Generic.List[object]
$textureBarrierProfileRecords = New-Object System.Collections.Generic.List[object]
$vertexUploadProfileRecords = New-Object System.Collections.Generic.List[object]
$indexUploadProfileRecords = New-Object System.Collections.Generic.List[object]
foreach ($line in [System.IO.File]::ReadLines($LogPath)) {
    $record = Read-RsxAuditorRecord $line
    if ($null -ne $record) {
        $records.Add($record) | Out-Null
    }

    $resolveProfileRecord = Read-RsxResolveProfileRecord $line
    if ($null -ne $resolveProfileRecord) {
        $resolveProfileRecords.Add($resolveProfileRecord) | Out-Null
    }

    $blitSourceProfileRecord = Read-RsxBlitSourceProfileRecord $line
    if ($null -ne $blitSourceProfileRecord) {
        $blitSourceProfileRecords.Add($blitSourceProfileRecord) | Out-Null
    }

    $textureBarrierProfileRecord = Read-RsxTextureBarrierProfileRecord $line
    if ($null -ne $textureBarrierProfileRecord) {
        $textureBarrierProfileRecords.Add($textureBarrierProfileRecord) | Out-Null
    }

    $vertexUploadProfileRecord = Read-RsxVertexUploadProfileRecord $line
    if ($null -ne $vertexUploadProfileRecord) {
        $vertexUploadProfileRecords.Add($vertexUploadProfileRecord) | Out-Null
    }

    $indexUploadProfileRecord = Read-RsxIndexUploadProfileRecord $line
    if ($null -ne $indexUploadProfileRecord) {
        $indexUploadProfileRecords.Add($indexUploadProfileRecord) | Out-Null
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
if ($resolveProfileRecords.Count -gt 0) {
    $resolveProfileRecords | Export-Csv -LiteralPath $ResolveProfileCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Resolve profile CSV: $ResolveProfileCsvPath") | Out-Null
}
if ($blitSourceProfileRecords.Count -gt 0) {
    $blitSourceProfileRecords | Export-Csv -LiteralPath $BlitSourceProfileCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Blit source profile CSV: $BlitSourceProfileCsvPath") | Out-Null
}
if ($textureBarrierProfileRecords.Count -gt 0) {
    $textureBarrierProfileRecords | Export-Csv -LiteralPath $TextureBarrierProfileCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Texture barrier profile CSV: $TextureBarrierProfileCsvPath") | Out-Null
}
if ($vertexUploadProfileRecords.Count -gt 0) {
    $vertexUploadProfileRecords | Export-Csv -LiteralPath $VertexUploadProfileCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Vertex upload profile CSV: $VertexUploadProfileCsvPath") | Out-Null
}
if ($indexUploadProfileRecords.Count -gt 0) {
    $indexUploadProfileRecords | Export-Csv -LiteralPath $IndexUploadProfileCsvPath -NoTypeInformation -Encoding UTF8
    $lines.Add("- Index upload profile CSV: $IndexUploadProfileCsvPath") | Out-Null
}

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
$totalResolveColor = [UInt64](($records | Measure-Object -Property resolve_color -Sum).Sum)
$totalResolveDepth = [UInt64](($records | Measure-Object -Property resolve_depth -Sum).Sum)
$totalResolveSkipColor = [UInt64](($records | Measure-Object -Property resolve_skip_color -Sum).Sum)
$totalResolveSkipDepth = [UInt64](($records | Measure-Object -Property resolve_skip_depth -Sum).Sum)
$totalResolveBarrierRtSrc = [UInt64](($records | Measure-Object -Property resolve_barrier_rt_src -Sum).Sum)
$totalResolveBarrierRtDst = [UInt64](($records | Measure-Object -Property resolve_barrier_rt_dst -Sum).Sum)
$totalResolveBarrierRtRestore = [UInt64](($records | Measure-Object -Property resolve_barrier_rt_restore -Sum).Sum)
$totalResolveBarrierRtReadable = [UInt64](($records | Measure-Object -Property resolve_barrier_rt_readable -Sum).Sum)
$totalResolveBarrierBlitSrc = [UInt64](($records | Measure-Object -Property resolve_barrier_blit_src -Sum).Sum)
$totalResolveBarrierBlitRestore = [UInt64](($records | Measure-Object -Property resolve_barrier_blit_restore -Sum).Sum)
$totalResolveBarrierBlitReadable = [UInt64](($records | Measure-Object -Property resolve_barrier_blit_readable -Sum).Sum)
$totalResolveBreakRtSrc = [UInt64](($records | Measure-Object -Property resolve_break_rt_src -Sum).Sum)
$totalResolveBreakRtDst = [UInt64](($records | Measure-Object -Property resolve_break_rt_dst -Sum).Sum)
$totalResolveBreakRtRestore = [UInt64](($records | Measure-Object -Property resolve_break_rt_restore -Sum).Sum)
$totalResolveBreakRtReadable = [UInt64](($records | Measure-Object -Property resolve_break_rt_readable -Sum).Sum)
$totalResolveBreakBlitSrc = [UInt64](($records | Measure-Object -Property resolve_break_blit_src -Sum).Sum)
$totalResolveBreakBlitRestore = [UInt64](($records | Measure-Object -Property resolve_break_blit_restore -Sum).Sum)
$totalResolveBreakBlitReadable = [UInt64](($records | Measure-Object -Property resolve_break_blit_readable -Sum).Sum)
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
$totalVertexUploadDraws = [UInt64](($records | Measure-Object -Property vertex_upload_draws -Sum).Sum)
$totalVertexUploadCacheHit = [UInt64](($records | Measure-Object -Property vertex_upload_cache_hit -Sum).Sum)
$totalVertexUploadCacheMiss = [UInt64](($records | Measure-Object -Property vertex_upload_cache_miss -Sum).Sum)
$totalVertexUploadPersistentMb = [double](($records | Measure-Object -Property vertex_upload_persistent_mb -Sum).Sum)
$totalVertexUploadVolatileMb = [double](($records | Measure-Object -Property vertex_upload_volatile_mb -Sum).Sum)
$totalVertexSupersetCacheHit = [UInt64](($records | Measure-Object -Property vertex_superset_cache_hit -Sum).Sum)
$totalVertexSupersetCacheMiss = [UInt64](($records | Measure-Object -Property vertex_superset_cache_miss -Sum).Sum)
$totalVertexSupersetCacheHitMb = [double](($records | Measure-Object -Property vertex_superset_cache_hit_mb -Sum).Sum)
$totalVertexPersistentCacheHit = [UInt64](($records | Measure-Object -Property vertex_persistent_cache_hit -Sum).Sum)
$totalVertexPersistentCacheChange = [UInt64](($records | Measure-Object -Property vertex_persistent_cache_change -Sum).Sum)
$totalVertexPersistentCacheNew = [UInt64](($records | Measure-Object -Property vertex_persistent_cache_new -Sum).Sum)
$totalVertexPersistentCacheHitMb = [double](($records | Measure-Object -Property vertex_persistent_cache_hit_mb -Sum).Sum)
$totalVertexPersistentVerifyHit = [UInt64](($records | Measure-Object -Property vertex_persistent_verify_hit -Sum).Sum)
$totalVertexPersistentVerifyStore = [UInt64](($records | Measure-Object -Property vertex_persistent_verify_store -Sum).Sum)
$totalVertexPersistentVerifyMismatch = [UInt64](($records | Measure-Object -Property vertex_persistent_verify_mismatch -Sum).Sum)
$totalVertexPersistentVerifyHitMb = [double](($records | Measure-Object -Property vertex_persistent_verify_hit_mb -Sum).Sum)
$totalVertexPersistentVerifyStoreMb = [double](($records | Measure-Object -Property vertex_persistent_verify_store_mb -Sum).Sum)
$totalVertexPersistentFastHit = [UInt64](($records | Measure-Object -Property vertex_persistent_fast_hit -Sum).Sum)
$totalVertexPersistentFastStore = [UInt64](($records | Measure-Object -Property vertex_persistent_fast_store -Sum).Sum)
$totalVertexPersistentFastReject = [UInt64](($records | Measure-Object -Property vertex_persistent_fast_reject -Sum).Sum)
$totalVertexPersistentFastHitMb = [double](($records | Measure-Object -Property vertex_persistent_fast_hit_mb -Sum).Sum)
$totalVertexPersistentFastStoreMb = [double](($records | Measure-Object -Property vertex_persistent_fast_store_mb -Sum).Sum)
$totalVertexVolatileCacheHit = [UInt64](($records | Measure-Object -Property vertex_volatile_cache_hit -Sum).Sum)
$totalVertexVolatileCacheMiss = [UInt64](($records | Measure-Object -Property vertex_volatile_cache_miss -Sum).Sum)
$totalVertexVolatileCacheHitMb = [double](($records | Measure-Object -Property vertex_volatile_cache_hit_mb -Sum).Sum)
$totalIndexUploadDraws = [UInt64](($records | Measure-Object -Property index_upload_draws -Sum).Sum)
$totalIndexUploadEmulated = [UInt64](($records | Measure-Object -Property index_upload_emulated -Sum).Sum)
$totalIndexUploadRestart = [UInt64](($records | Measure-Object -Property index_upload_restart -Sum).Sum)
$totalIndexUploadMb = [double](($records | Measure-Object -Property index_upload_mb -Sum).Sum)
$totalIndexGpuConvertEligible = [UInt64](($records | Measure-Object -Property index_gpu_convert_eligible -Sum).Sum)
$totalIndexGpuConvertDispatch = [UInt64](($records | Measure-Object -Property index_gpu_convert_dispatch -Sum).Sum)
$totalIndexGpuConvertReject = [UInt64](($records | Measure-Object -Property index_gpu_convert_reject -Sum).Sum)
$totalIndexGpuConvertMb = [double](($records | Measure-Object -Property index_gpu_convert_mb -Sum).Sum)
$totalIndexGpuCacheHit = [UInt64](($records | Measure-Object -Property index_gpu_cache_hit -Sum).Sum)
$totalIndexGpuCacheMiss = [UInt64](($records | Measure-Object -Property index_gpu_cache_miss -Sum).Sum)
$totalIndexGpuCacheHitMb = [double](($records | Measure-Object -Property index_gpu_cache_hit_mb -Sum).Sum)
$totalIndexPersistentCacheHit = [UInt64](($records | Measure-Object -Property index_persistent_cache_hit -Sum).Sum)
$totalIndexPersistentCacheChange = [UInt64](($records | Measure-Object -Property index_persistent_cache_change -Sum).Sum)
$totalIndexPersistentCacheNew = [UInt64](($records | Measure-Object -Property index_persistent_cache_new -Sum).Sum)
$totalIndexPersistentCacheHitMb = [double](($records | Measure-Object -Property index_persistent_cache_hit_mb -Sum).Sum)
$totalIndexPersistentVerifyHit = [UInt64](($records | Measure-Object -Property index_persistent_verify_hit -Sum).Sum)
$totalIndexPersistentVerifyStore = [UInt64](($records | Measure-Object -Property index_persistent_verify_store -Sum).Sum)
$totalIndexPersistentVerifyMismatch = [UInt64](($records | Measure-Object -Property index_persistent_verify_mismatch -Sum).Sum)
$totalIndexPersistentVerifyHitMb = [double](($records | Measure-Object -Property index_persistent_verify_hit_mb -Sum).Sum)
$totalIndexPersistentVerifyStoreMb = [double](($records | Measure-Object -Property index_persistent_verify_store_mb -Sum).Sum)
$totalIndexPersistentFastHit = [UInt64](($records | Measure-Object -Property index_persistent_fast_hit -Sum).Sum)
$totalIndexPersistentFastStore = [UInt64](($records | Measure-Object -Property index_persistent_fast_store -Sum).Sum)
$totalIndexPersistentFastReject = [UInt64](($records | Measure-Object -Property index_persistent_fast_reject -Sum).Sum)
$totalIndexPersistentFastHitMb = [double](($records | Measure-Object -Property index_persistent_fast_hit_mb -Sum).Sum)
$totalIndexPersistentFastStoreMb = [double](($records | Measure-Object -Property index_persistent_fast_store_mb -Sum).Sum)
$totalPresentUploadCpu = [UInt64](($records | Measure-Object -Property present_upload_cpu -Sum).Sum)
$totalPresentUploadGpu = [UInt64](($records | Measure-Object -Property present_upload_gpu -Sum).Sum)
$totalPresentUploadCpuMb = [double](($records | Measure-Object -Property present_upload_cpu_mb -Sum).Sum)
$totalPresentUploadGpuMb = [double](($records | Measure-Object -Property present_upload_gpu_mb -Sum).Sum)
$totalDepthFeedbackPrepKeep = [UInt64](($records | Measure-Object -Property depth_feedback_prep_keep -Sum).Sum)
$totalDepthFeedbackPrepLayout = [UInt64](($records | Measure-Object -Property depth_feedback_prep_layout -Sum).Sum)
$totalDepthFeedbackPrepWrite = [UInt64](($records | Measure-Object -Property depth_feedback_prep_write -Sum).Sum)
$totalDepthFeedbackEndKeep = [UInt64](($records | Measure-Object -Property depth_feedback_end_keep -Sum).Sum)
$totalDepthFeedbackEndLayout = [UInt64](($records | Measure-Object -Property depth_feedback_end_layout -Sum).Sum)
$totalDepthFeedbackEndWrite = [UInt64](($records | Measure-Object -Property depth_feedback_end_write -Sum).Sum)
$totalDepthFeedbackEndRestore = [UInt64](($records | Measure-Object -Property depth_feedback_end_restore -Sum).Sum)
$totalBlitResolveFast = [UInt64](($records | Measure-Object -Property blit_resolve_fast -Sum).Sum)
$totalBlitResolveVerify = [UInt64](($records | Measure-Object -Property blit_resolve_verify -Sum).Sum)
$totalBlitResolveReject = [UInt64](($records | Measure-Object -Property blit_resolve_reject -Sum).Sum)
$totalBlitResolveStorageFast = [UInt64](($records | Measure-Object -Property blit_resolve_storage_fast -Sum).Sum)
$totalBlitResolveSampledFast = [UInt64](($records | Measure-Object -Property blit_resolve_sampled_fast -Sum).Sum)
$totalBlitResolveStorageVerify = [UInt64](($records | Measure-Object -Property blit_resolve_storage_verify -Sum).Sum)
$totalBlitResolveSampledVerify = [UInt64](($records | Measure-Object -Property blit_resolve_sampled_verify -Sum).Sum)
$totalBlitRejectRegion = [UInt64](($records | Measure-Object -Property blit_reject_region -Sum).Sum)
$totalBlitRejectTypeless = [UInt64](($records | Measure-Object -Property blit_reject_typeless -Sum).Sum)
$totalBlitRejectFormat = [UInt64](($records | Measure-Object -Property blit_reject_format -Sum).Sum)
$totalBlitRejectRt = [UInt64](($records | Measure-Object -Property blit_reject_rt -Sum).Sum)
$totalBlitRejectDispatch = [UInt64](($records | Measure-Object -Property blit_reject_dispatch -Sum).Sum)
$totalBlitCacheHit = [UInt64](($records | Measure-Object -Property blit_cache_hit -Sum).Sum)
$totalBlitCacheMiss = [UInt64](($records | Measure-Object -Property blit_cache_miss -Sum).Sum)
$totalBlitCacheFill = [UInt64](($records | Measure-Object -Property blit_cache_fill -Sum).Sum)
$totalBlitCacheFanout = [UInt64](($records | Measure-Object -Property blit_cache_fanout -Sum).Sum)
$totalBlitCacheReject = [UInt64](($records | Measure-Object -Property blit_cache_reject -Sum).Sum)
$totalBlitCacheTransferSrcFill = [UInt64](($records | Measure-Object -Property blit_cache_transfer_src_fill -Sum).Sum)
$totalBlitCacheTransferSrcFanout = [UInt64](($records | Measure-Object -Property blit_cache_transfer_src_fanout -Sum).Sum)
$totalBlitCacheRpFill = [UInt64](($records | Measure-Object -Property blit_cache_rp_fill -Sum).Sum)
$totalBlitCacheRpSrcLayout = [UInt64](($records | Measure-Object -Property blit_cache_rp_src_layout -Sum).Sum)
$totalBlitCacheRpCopy = [UInt64](($records | Measure-Object -Property blit_cache_rp_copy -Sum).Sum)
$totalBlitCacheRpHitCopy = [UInt64](($records | Measure-Object -Property blit_cache_rp_hit_copy -Sum).Sum)
$totalBlitCacheDeferFill = [UInt64](($records | Measure-Object -Property blit_cache_defer_fill -Sum).Sum)
$totalBlitCacheDeferSrcLayout = [UInt64](($records | Measure-Object -Property blit_cache_defer_src_layout -Sum).Sum)
$totalSourcePrefillClose = [UInt64](($records | Measure-Object -Property source_prefill_close -Sum).Sum)
$totalSourcePrefillBound = [UInt64](($records | Measure-Object -Property source_prefill_bound -Sum).Sum)
$totalSourcePrefillHot = [UInt64](($records | Measure-Object -Property source_prefill_hot -Sum).Sum)
$totalSourcePrefillResolve = [UInt64](($records | Measure-Object -Property source_prefill_resolve -Sum).Sum)
$totalSourcePrefillTagDirty = [UInt64](($records | Measure-Object -Property source_prefill_tagdirty -Sum).Sum)
$totalSourcePrefillCacheAttempt = [UInt64](($records | Measure-Object -Property source_prefill_cache_attempt -Sum).Sum)
$totalSourcePrefillCacheHit = [UInt64](($records | Measure-Object -Property source_prefill_cache_hit -Sum).Sum)
$totalSourcePrefillCacheFill = [UInt64](($records | Measure-Object -Property source_prefill_cache_fill -Sum).Sum)
$totalSourcePrefillCacheReject = [UInt64](($records | Measure-Object -Property source_prefill_cache_reject -Sum).Sum)
$totalSourcePrefillBeginCall = [UInt64](($records | Measure-Object -Property source_prefill_begin_call -Sum).Sum)
$totalSourcePrefillBeginRp = [UInt64](($records | Measure-Object -Property source_prefill_begin_rp -Sum).Sum)
$totalSourcePrefillBeginBound = [UInt64](($records | Measure-Object -Property source_prefill_begin_bound -Sum).Sum)
$totalSourcePrefillBeginHot = [UInt64](($records | Measure-Object -Property source_prefill_begin_hot -Sum).Sum)
$totalSourcePrefillBeginResolve = [UInt64](($records | Measure-Object -Property source_prefill_begin_resolve -Sum).Sum)
$totalSourcePrefillBeginTagDirty = [UInt64](($records | Measure-Object -Property source_prefill_begin_tagdirty -Sum).Sum)
$totalSourceTransitionCheck = [UInt64](($records | Measure-Object -Property source_transition_check -Sum).Sum)
$totalSourceTransitionHot = [UInt64](($records | Measure-Object -Property source_transition_hot -Sum).Sum)
$totalSourceTransitionRetire = [UInt64](($records | Measure-Object -Property source_transition_retire -Sum).Sum)
$totalSourceTransitionRp = [UInt64](($records | Measure-Object -Property source_transition_rp -Sum).Sum)
$totalSourceTransitionResolve = [UInt64](($records | Measure-Object -Property source_transition_resolve -Sum).Sum)
$totalSourceTransitionTagDirty = [UInt64](($records | Measure-Object -Property source_transition_tagdirty -Sum).Sum)
$totalSourceWriterHit = [UInt64](($records | Measure-Object -Property source_writer_hit -Sum).Sum)
$totalSourceWriterHot = [UInt64](($records | Measure-Object -Property source_writer_hot -Sum).Sum)
$totalSourceWriterFast = [UInt64](($records | Measure-Object -Property source_writer_fast -Sum).Sum)
$totalSourceWriterFull = [UInt64](($records | Measure-Object -Property source_writer_full -Sum).Sum)
$totalSourceWriterHotFast = [UInt64](($records | Measure-Object -Property source_writer_hot_fast -Sum).Sum)
$totalSourceWriterHotFull = [UInt64](($records | Measure-Object -Property source_writer_hot_full -Sum).Sum)
$totalSourceWriterHotResolve = [UInt64](($records | Measure-Object -Property source_writer_hot_resolve -Sum).Sum)
$totalSourceWriterHotTagDirty = [UInt64](($records | Measure-Object -Property source_writer_hot_tagdirty -Sum).Sum)
$totalSourceWriterHotGtCache = [UInt64](($records | Measure-Object -Property source_writer_hot_gtcache -Sum).Sum)
$totalSourceWriterHotLeCache = [UInt64](($records | Measure-Object -Property source_writer_hot_lecache -Sum).Sum)
$totalSourceWriterTagNew = [UInt64](($records | Measure-Object -Property source_writer_tag_new -Sum).Sum)
$totalSourceWriterTagRepeat = [UInt64](($records | Measure-Object -Property source_writer_tag_repeat -Sum).Sum)
$totalSourceWriterTagCollision = [UInt64](($records | Measure-Object -Property source_writer_tag_collision -Sum).Sum)
$totalSourceWriterTagZero = [UInt64](($records | Measure-Object -Property source_writer_tag_zero -Sum).Sum)
$totalSourceBlitStateHit = [UInt64](($records | Measure-Object -Property source_blit_state_hit -Sum).Sum)
$totalSourceBlitStateHot = [UInt64](($records | Measure-Object -Property source_blit_state_hot -Sum).Sum)
$totalSourceBlitStateRp = [UInt64](($records | Measure-Object -Property source_blit_state_rp -Sum).Sum)
$totalSourceBlitStateRead = [UInt64](($records | Measure-Object -Property source_blit_state_read -Sum).Sum)
$totalSourceBlitStateColor = [UInt64](($records | Measure-Object -Property source_blit_state_color -Sum).Sum)
$totalSourceBlitStateGeneral = [UInt64](($records | Measure-Object -Property source_blit_state_general -Sum).Sum)
$totalSourceBlitStateResolve = [UInt64](($records | Measure-Object -Property source_blit_state_resolve -Sum).Sum)
$totalSourceBlitStateTagDirty = [UInt64](($records | Measure-Object -Property source_blit_state_tagdirty -Sum).Sum)
$totalSourceFusedStateHit = [UInt64](($records | Measure-Object -Property source_fused_state_hit -Sum).Sum)
$totalSourceFusedStateHot = [UInt64](($records | Measure-Object -Property source_fused_state_hot -Sum).Sum)
$totalSourceFusedStateRp = [UInt64](($records | Measure-Object -Property source_fused_state_rp -Sum).Sum)
$totalSourceFusedStateRead = [UInt64](($records | Measure-Object -Property source_fused_state_read -Sum).Sum)
$totalSourceFusedStateColor = [UInt64](($records | Measure-Object -Property source_fused_state_color -Sum).Sum)
$totalSourceFusedStateGeneral = [UInt64](($records | Measure-Object -Property source_fused_state_general -Sum).Sum)
$totalSourceFusedStateResolve = [UInt64](($records | Measure-Object -Property source_fused_state_resolve -Sum).Sum)
$totalSourceFusedStateTagDirty = [UInt64](($records | Measure-Object -Property source_fused_state_tagdirty -Sum).Sum)
$totalSourceFusedTagNew = [UInt64](($records | Measure-Object -Property source_fused_tag_new -Sum).Sum)
$totalSourceFusedTagRepeat = [UInt64](($records | Measure-Object -Property source_fused_tag_repeat -Sum).Sum)
$totalSourceFusedTagCollision = [UInt64](($records | Measure-Object -Property source_fused_tag_collision -Sum).Sum)
$totalSourceFusedTagZero = [UInt64](($records | Measure-Object -Property source_fused_tag_zero -Sum).Sum)
$blitSourceResolveProfileRecords = @($resolveProfileRecords | Where-Object { $_.reason -eq 13 })
$totalProfileBlitSourceCalls = [UInt64]0
$totalProfileBlitSourceDuplicateTags = [UInt64]0
$profileBlitSourceUniqueTagFloor = [UInt64]0
$profileBlitSourceDuplicateShare = 0.0
if ($blitSourceResolveProfileRecords.Count -gt 0) {
    $totalProfileBlitSourceCalls = [UInt64](($blitSourceResolveProfileRecords | Measure-Object -Property count -Sum).Sum)
    $totalProfileBlitSourceDuplicateTags = [UInt64](($blitSourceResolveProfileRecords | Measure-Object -Property dup -Sum).Sum)
    if ($totalProfileBlitSourceCalls -gt $totalProfileBlitSourceDuplicateTags) {
        $profileBlitSourceUniqueTagFloor = [UInt64]($totalProfileBlitSourceCalls - $totalProfileBlitSourceDuplicateTags)
    }
    if ($totalProfileBlitSourceCalls -gt 0) {
        $profileBlitSourceDuplicateShare = ([double]$totalProfileBlitSourceDuplicateTags * 100.0) / [double]$totalProfileBlitSourceCalls
    }
}
$blitSourceProfileDistinctKeys = [UInt64]0
$topBlitSourceProfileCount = [UInt64]0
$topBlitSourceProfileKey = ""
if ($blitSourceProfileRecords.Count -gt 0) {
    $blitSourceProfileGroupsForScout = @(
        $blitSourceProfileRecords |
            Group-Object -Property key |
            ForEach-Object {
                [pscustomobject]@{
                    key   = $_.Name
                    count = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                }
            } |
            Sort-Object -Property count -Descending
    )
    $blitSourceProfileDistinctKeys = [UInt64]$blitSourceProfileGroupsForScout.Count
    if ($blitSourceProfileGroupsForScout.Count -gt 0) {
        $topBlitSourceProfileCount = [UInt64]$blitSourceProfileGroupsForScout[0].count
        $topBlitSourceProfileKey = $blitSourceProfileGroupsForScout[0].key
    }
}
$totalTextureProfileReadonlySkips = [UInt64]0
$totalTextureProfileForcedSkips = [UInt64]0
if ($textureBarrierProfileRecords.Count -gt 0) {
    $totalTextureProfileReadonlySkips = [UInt64](($textureBarrierProfileRecords | Measure-Object -Property skip_readonly -Sum).Sum)
    $totalTextureProfileForcedSkips = [UInt64](($textureBarrierProfileRecords | Measure-Object -Property skip_forced -Sum).Sum)
}
$totalTextureElisions = [UInt64]($totalTexSkip + $totalPostElide)
$totalDepthFeedbackKeeps = [UInt64]($totalDepthFeedbackPrepKeep + $totalDepthFeedbackEndKeep)
$totalFusedResolveDispatches = [UInt64]($totalBlitResolveFast + $totalBlitResolveVerify)
$totalNewTextureCreditSkips = [UInt64]($totalTextureProfileReadonlySkips + $totalTextureProfileForcedSkips)
$totalRsxLocalCreditEvents = [UInt64]($totalNewTextureCreditSkips + $totalDepthFeedbackKeeps + $totalFusedResolveDispatches + $totalPresentUploadGpu + $totalIndexGpuConvertDispatch + $totalIndexGpuCacheHit + $totalIndexPersistentFastHit + $totalVertexSupersetCacheHit + $totalVertexPersistentFastHit + $totalVertexVolatileCacheHit)
$gpuMigrationCreditClass = if ($totalRsxLocalCreditEvents -gt 0) { "gpu-migration-credit-candidate" } else { "no-gpu-migration-credit-observed" }
$blitSourceBreakShare = 0.0
if ($totalRpBreak -gt 0) {
    $blitSourceBreakShare = ([double]$totalResolveBreakBlitSrc * 100.0) / [double]$totalRpBreak
}
$blitBreaksPerFusedResolve = 0.0
if ($totalFusedResolveDispatches -gt 0) {
    $blitBreaksPerFusedResolve = ([double]$totalResolveBreakBlitSrc * 100.0) / [double]$totalFusedResolveDispatches
}
$blitCacheFanoutPerMiss = 0.0
if ($totalBlitCacheMiss -gt 0) {
    $blitCacheFanoutPerMiss = [double]$totalBlitCacheFanout / [double]$totalBlitCacheMiss
}
$sourceLocalDebtClass = "no-source-local-debt-observed"
$sourceLocalDebtReading = "No fused blit-source render-pass debt was observed in this capture."
if ($totalResolveBreakBlitSrc -gt 0 -and $totalBlitCacheFanout -gt 0 -and $totalBlitCacheRpSrcLayout -gt 0) {
    $sourceLocalDebtClass = "cache-fanout-active-source-layout-bound"
    $sourceLocalDebtReading = "Cached source fanout is active, but the first source fill/layout transition still breaks the render pass; park cache-copy tuning and target render-pass-local source read/fill."
} elseif ($totalResolveBreakBlitSrc -gt 0) {
    $sourceLocalDebtClass = "source-layout-renderpass-bound"
    $sourceLocalDebtReading = "Fused blit-source reads are still forcing render-pass breaks; the next RSX-only speed lane must change source-read architecture, not add more cache fanout."
} elseif ($totalBlitCacheDeferFill -gt 0) {
    $sourceLocalDebtClass = "deferred-source-fill-bound"
    $sourceLocalDebtReading = "Cache fills were deferred to avoid open render-pass breaks; use this only as correctness evidence unless a later design can consume the source locally."
}

$lines.Add("- Auditor frames: $totalFrames") | Out-Null
$lines.Add("- Queue submits: $totalSubmits ($(Format-AuditorRate $totalSubmits $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Hard sync flushes: $totalHardSync ($(Format-AuditorRate $totalHardSync $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Render-pass barrier breaks: $totalRpBreak ($(Format-AuditorRate $totalRpBreak $totalFrames) per 60 frames)") | Out-Null
$lines.Add("- Image barrier source totals unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up: $totalImageSrcUnknown/$totalImageSrcRtRes/$totalImageSrcRtUnres/$totalImageSrcRtPost/$totalImageSrcRtOther/$totalImageSrcTc/$totalImageSrcDraw/$totalImageSrcPresent/$totalImageSrcTexture/$totalImageSrcUp") | Out-Null
$lines.Add("- Image break source totals unk/rt_res/rt_unres/rt_post/rt_other/tc/draw/pres/tex/up: $totalImageBreakUnknown/$totalImageBreakRtRes/$totalImageBreakRtUnres/$totalImageBreakRtPost/$totalImageBreakRtOther/$totalImageBreakTc/$totalImageBreakDraw/$totalImageBreakPresent/$totalImageBreakTexture/$totalImageBreakUp") | Out-Null
$lines.Add("- Resolve calls/skips color/depth: calls=$totalResolveColor/$totalResolveDepth skips=$totalResolveSkipColor/$totalResolveSkipDepth") | Out-Null
$lines.Add("- Resolve barrier detail rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable: $totalResolveBarrierRtSrc/$totalResolveBarrierRtDst/$totalResolveBarrierRtRestore/$totalResolveBarrierRtReadable/$totalResolveBarrierBlitSrc/$totalResolveBarrierBlitRestore/$totalResolveBarrierBlitReadable") | Out-Null
$lines.Add("- Resolve break detail rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable: $totalResolveBreakRtSrc/$totalResolveBreakRtDst/$totalResolveBreakRtRestore/$totalResolveBreakRtReadable/$totalResolveBreakBlitSrc/$totalResolveBreakBlitRestore/$totalResolveBreakBlitReadable") | Out-Null
$lines.Add("- Barrier-tracked buffer range: $(Format-AuditorDecimal $totalBarrierMb) MB") | Out-Null
$lines.Add("- DMA transfer fences: all=$totalDmaAll / host=$totalDmaHost, bytes=$(Format-AuditorDecimal ($totalDmaMb + $totalDmaHostMb)) MB") | Out-Null
$lines.Add("- Pipeline creates: graphics=$totalPipeGraphics compute=$totalPipeCompute slow=$totalPipeSlow total_us=$totalPipeUs") | Out-Null
$lines.Add("- Detile/upload: detile=$totalDetile in=$(Format-AuditorDecimal $totalInMb) MB out=$(Format-AuditorDecimal $totalOutMb) MB simple_upload=$totalUpload upload=$(Format-AuditorDecimal $totalUploadMb) MB") | Out-Null
$lines.Add("- Vertex upload: draws=$totalVertexUploadDraws cache_hit/cache_miss=$totalVertexUploadCacheHit/$totalVertexUploadCacheMiss persistent=$(Format-AuditorDecimal $totalVertexUploadPersistentMb) MB volatile=$(Format-AuditorDecimal $totalVertexUploadVolatileMb) MB") | Out-Null
$lines.Add("- Vertex superset cache: hit=$totalVertexSupersetCacheHit miss=$totalVertexSupersetCacheMiss hit_bytes=$(Format-AuditorDecimal $totalVertexSupersetCacheHitMb) MB") | Out-Null
$lines.Add("- Vertex persistent cache scout: hit/change/new=$totalVertexPersistentCacheHit/$totalVertexPersistentCacheChange/$totalVertexPersistentCacheNew hit_bytes=$(Format-AuditorDecimal $totalVertexPersistentCacheHitMb) MB") | Out-Null
$lines.Add("- Vertex persistent cache verify: hit/store/mismatch=$totalVertexPersistentVerifyHit/$totalVertexPersistentVerifyStore/$totalVertexPersistentVerifyMismatch hit_bytes=$(Format-AuditorDecimal $totalVertexPersistentVerifyHitMb) MB store_bytes=$(Format-AuditorDecimal $totalVertexPersistentVerifyStoreMb) MB") | Out-Null
$lines.Add("- Vertex persistent cache fast: hit/store/reject=$totalVertexPersistentFastHit/$totalVertexPersistentFastStore/$totalVertexPersistentFastReject hit_bytes=$(Format-AuditorDecimal $totalVertexPersistentFastHitMb) MB store_bytes=$(Format-AuditorDecimal $totalVertexPersistentFastStoreMb) MB") | Out-Null
$lines.Add("- Vertex volatile cache: hit=$totalVertexVolatileCacheHit miss=$totalVertexVolatileCacheMiss hit_bytes=$(Format-AuditorDecimal $totalVertexVolatileCacheHitMb) MB") | Out-Null
$lines.Add("- Index upload: draws=$totalIndexUploadDraws emulated/restart=$totalIndexUploadEmulated/$totalIndexUploadRestart bytes=$(Format-AuditorDecimal $totalIndexUploadMb) MB") | Out-Null
$lines.Add("- Index GPU convert: eligible=$totalIndexGpuConvertEligible dispatch=$totalIndexGpuConvertDispatch reject=$totalIndexGpuConvertReject bytes=$(Format-AuditorDecimal $totalIndexGpuConvertMb) MB") | Out-Null
$lines.Add("- Index GPU cache: hit=$totalIndexGpuCacheHit miss=$totalIndexGpuCacheMiss hit_bytes=$(Format-AuditorDecimal $totalIndexGpuCacheHitMb) MB") | Out-Null
$lines.Add("- Index persistent cache scout: hit/change/new=$totalIndexPersistentCacheHit/$totalIndexPersistentCacheChange/$totalIndexPersistentCacheNew hit_bytes=$(Format-AuditorDecimal $totalIndexPersistentCacheHitMb) MB") | Out-Null
$lines.Add("- Index persistent cache verify: hit/store/mismatch=$totalIndexPersistentVerifyHit/$totalIndexPersistentVerifyStore/$totalIndexPersistentVerifyMismatch hit_bytes=$(Format-AuditorDecimal $totalIndexPersistentVerifyHitMb) MB store_bytes=$(Format-AuditorDecimal $totalIndexPersistentVerifyStoreMb) MB") | Out-Null
$lines.Add("- Index persistent cache fast: hit/store/reject=$totalIndexPersistentFastHit/$totalIndexPersistentFastStore/$totalIndexPersistentFastReject hit_bytes=$(Format-AuditorDecimal $totalIndexPersistentFastHitMb) MB store_bytes=$(Format-AuditorDecimal $totalIndexPersistentFastStoreMb) MB") | Out-Null
$lines.Add("- Present upload split: cpu=$totalPresentUploadCpu/$(Format-AuditorDecimal $totalPresentUploadCpuMb) MB gpu=$totalPresentUploadGpu/$(Format-AuditorDecimal $totalPresentUploadGpuMb) MB") | Out-Null
$lines.Add("- Depth feedback prep keep/layout/write: $totalDepthFeedbackPrepKeep/$totalDepthFeedbackPrepLayout/$totalDepthFeedbackPrepWrite; end keep/layout/write/restore: $totalDepthFeedbackEndKeep/$totalDepthFeedbackEndLayout/$totalDepthFeedbackEndWrite/$totalDepthFeedbackEndRestore") | Out-Null
$lines.Add("- Blit-source fused resolve: fast=$totalBlitResolveFast verify=$totalBlitResolveVerify rejects=$totalBlitResolveReject") | Out-Null
$lines.Add("- Blit-source resolve path storage_fast/sampled_fast/storage_verify/sampled_verify: $totalBlitResolveStorageFast/$totalBlitResolveSampledFast/$totalBlitResolveStorageVerify/$totalBlitResolveSampledVerify") | Out-Null
$lines.Add("- Blit-source reject reasons region/typeless/format/rt/dispatch: $totalBlitRejectRegion/$totalBlitRejectTypeless/$totalBlitRejectFormat/$totalBlitRejectRt/$totalBlitRejectDispatch") | Out-Null
$lines.Add("- Blit-source cache hit/miss/fill/fanout/reject: $totalBlitCacheHit/$totalBlitCacheMiss/$totalBlitCacheFill/$totalBlitCacheFanout/$totalBlitCacheReject") | Out-Null
$lines.Add("- Blit-source cache transfer-src fill/fanout: $totalBlitCacheTransferSrcFill/$totalBlitCacheTransferSrcFanout") | Out-Null
$lines.Add("- Blit-source cache render-pass breaks fill/src_layout/copy/hit_copy: $totalBlitCacheRpFill/$totalBlitCacheRpSrcLayout/$totalBlitCacheRpCopy/$totalBlitCacheRpHitCopy") | Out-Null
$lines.Add("- Blit-source cache deferred fills fill/src_layout: $totalBlitCacheDeferFill/$totalBlitCacheDeferSrcLayout") | Out-Null
if (($totalSourcePrefillClose + $totalSourcePrefillHot + $totalSourcePrefillResolve + $totalSourcePrefillTagDirty) -gt 0) {
    $lines.Add("- Source prefill profile close/bound/hot/resolve/tagdirty: $totalSourcePrefillClose/$totalSourcePrefillBound/$totalSourcePrefillHot/$totalSourcePrefillResolve/$totalSourcePrefillTagDirty") | Out-Null
}
if ($totalSourcePrefillCacheAttempt -gt 0) {
    $lines.Add("- Source prefill cache attempt/hit/fill/reject: $totalSourcePrefillCacheAttempt/$totalSourcePrefillCacheHit/$totalSourcePrefillCacheFill/$totalSourcePrefillCacheReject") | Out-Null
}
if ($totalSourceWriterHit -gt 0) {
    $lines.Add("- Source writer state hit/hot/fast/full/hot_fast/hot_full/hot_resolve/hot_tagdirty/hot_gtcache/hot_lecache: $totalSourceWriterHit/$totalSourceWriterHot/$totalSourceWriterFast/$totalSourceWriterFull/$totalSourceWriterHotFast/$totalSourceWriterHotFull/$totalSourceWriterHotResolve/$totalSourceWriterHotTagDirty/$totalSourceWriterHotGtCache/$totalSourceWriterHotLeCache") | Out-Null
}
if (($totalSourceWriterTagNew + $totalSourceWriterTagRepeat + $totalSourceWriterTagCollision + $totalSourceWriterTagZero) -gt 0) {
    $lines.Add("- Source writer tag new/repeat/collision/zero: $totalSourceWriterTagNew/$totalSourceWriterTagRepeat/$totalSourceWriterTagCollision/$totalSourceWriterTagZero") | Out-Null
}
if ($totalSourceBlitStateHit -gt 0) {
    $lines.Add("- Source blit state hit/hot/rp/read/color/general/resolve/tagdirty: $totalSourceBlitStateHit/$totalSourceBlitStateHot/$totalSourceBlitStateRp/$totalSourceBlitStateRead/$totalSourceBlitStateColor/$totalSourceBlitStateGeneral/$totalSourceBlitStateResolve/$totalSourceBlitStateTagDirty") | Out-Null
}
if ($totalSourceFusedStateHit -gt 0) {
    $lines.Add("- Source fused state hit/hot/rp/read/color/general/resolve/tagdirty: $totalSourceFusedStateHit/$totalSourceFusedStateHot/$totalSourceFusedStateRp/$totalSourceFusedStateRead/$totalSourceFusedStateColor/$totalSourceFusedStateGeneral/$totalSourceFusedStateResolve/$totalSourceFusedStateTagDirty") | Out-Null
}
if (($totalSourceFusedTagNew + $totalSourceFusedTagRepeat + $totalSourceFusedTagCollision + $totalSourceFusedTagZero) -gt 0) {
    $lines.Add("- Source fused tag new/repeat/collision/zero: $totalSourceFusedTagNew/$totalSourceFusedTagRepeat/$totalSourceFusedTagCollision/$totalSourceFusedTagZero") | Out-Null
}
if (($totalSourcePrefillBeginCall + $totalSourcePrefillBeginHot + $totalSourcePrefillBeginResolve + $totalSourcePrefillBeginTagDirty) -gt 0) {
    $lines.Add("- Source prefill begin call/rp/bound/hot/resolve/tagdirty: $totalSourcePrefillBeginCall/$totalSourcePrefillBeginRp/$totalSourcePrefillBeginBound/$totalSourcePrefillBeginHot/$totalSourcePrefillBeginResolve/$totalSourcePrefillBeginTagDirty") | Out-Null
}
if (($totalSourceTransitionCheck + $totalSourceTransitionHot + $totalSourceTransitionRetire + $totalSourceTransitionResolve + $totalSourceTransitionTagDirty) -gt 0) {
    $lines.Add("- Source transition check/hot/retire/rp/resolve/tagdirty: $totalSourceTransitionCheck/$totalSourceTransitionHot/$totalSourceTransitionRetire/$totalSourceTransitionRp/$totalSourceTransitionResolve/$totalSourceTransitionTagDirty") | Out-Null
}
$lines.Add("- GPU migration credit class: $gpuMigrationCreditClass") | Out-Null
$lines.Add("- Source-local debt class: $sourceLocalDebtClass") | Out-Null
if ($resolveProfileRecords.Count -gt 0) {
    $lines.Add("- Resolve profile records: $($resolveProfileRecords.Count)") | Out-Null
}
if ($totalProfileBlitSourceCalls -gt 0) {
    $lines.Add(("- Resolve coalescing scout: blit_source_calls={0} duplicate_tags={1} unique_tag_floor={2} duplicate_share={3}%" -f
        $totalProfileBlitSourceCalls,
        $totalProfileBlitSourceDuplicateTags,
        $profileBlitSourceUniqueTagFloor,
        (Format-AuditorDecimal $profileBlitSourceDuplicateShare))) | Out-Null
}
if ($blitSourceProfileDistinctKeys -gt 0) {
    $lines.Add("- Blit source profile keys: $blitSourceProfileDistinctKeys, top=$topBlitSourceProfileCount ($topBlitSourceProfileKey)") | Out-Null
}
if ($textureBarrierProfileRecords.Count -gt 0) {
    $lines.Add("- Texture barrier profile records: $($textureBarrierProfileRecords.Count)") | Out-Null
}
if ($vertexUploadProfileRecords.Count -gt 0) {
    $lines.Add("- Vertex upload profile records: $($vertexUploadProfileRecords.Count)") | Out-Null
}
if ($indexUploadProfileRecords.Count -gt 0) {
    $lines.Add("- Index upload profile records: $($indexUploadProfileRecords.Count)") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## GPU Migration Credit") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Track | Counter | Per 60 Frames | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null
$lines.Add("| Promoted CPU/SPU/PPU job bytes | 0 | 0 | This RSX auditor proves residency/locality only; use the GPU probe summary for SPU/PPU replacement bytes. |") | Out-Null
$lines.Add(('| RSX-local credit events | {0} | {1} | Sum of new/gated GPU-residency footholds: profiled skip credit, depth-feedback keeps, fused GPU resolves, GPU present-upload swaps, GPU index byte-swap dispatches, frame-local/persistent index-cache hits, and vertex-cache hits. |' -f $totalRsxLocalCreditEvents, (Format-AuditorRate $totalRsxLocalCreditEvents $totalFrames))) | Out-Null
$lines.Add(('| All texture/post elisions | {0} | {1} | Texture skips plus post-barrier elides; useful context, but only profiled read-only/forced skips count as new credit. |' -f $totalTextureElisions, (Format-AuditorRate $totalTextureElisions $totalFrames))) | Out-Null
$lines.Add(('| Profiled read-only/forced texture skips | {0}/{1} | {2}/{3} | Per-resource proof that the elided texture barrier is the intended read-only depth surface, not a broad unsafe skip. |' -f $totalTextureProfileReadonlySkips, $totalTextureProfileForcedSkips, (Format-AuditorRate $totalTextureProfileReadonlySkips $totalFrames), (Format-AuditorRate $totalTextureProfileForcedSkips $totalFrames))) | Out-Null
$lines.Add(('| Read-only depth feedback keeps | {0} | {1} | Layout-preservation attempts that keep the depth feedback loop GPU-local instead of churned through write layouts. |' -f $totalDepthFeedbackKeeps, (Format-AuditorRate $totalDepthFeedbackKeeps $totalFrames))) | Out-Null
$lines.Add(('| Fused GPU resolve/blit dispatches | {0} | {1} | Fast or verify blit-source resolve work running on GPU; still needs screenshot correctness before promotion. |' -f $totalFusedResolveDispatches, (Format-AuditorRate $totalFusedResolveDispatches $totalFrames))) | Out-Null
$lines.Add(('| Sampled-MSAA resolve/blit dispatches | {0} | {1} | Subset using sampled MSAA reads instead of storage-image reads; useful for mobile-shaped RSX GPU residency experiments. |' -f ($totalBlitResolveSampledFast + $totalBlitResolveSampledVerify), (Format-AuditorRate ($totalBlitResolveSampledFast + $totalBlitResolveSampledVerify) $totalFrames))) | Out-Null
$lines.Add(('| Present upload GPU byte-swap | {0} / {1} MB | {2} / {3} MB | Fallback Cell-memory present uploads whose 32-bit endian swap ran through the Vulkan upload/GPU-shuffle path instead of the CPU row loop. |' -f $totalPresentUploadGpu, (Format-AuditorDecimal $totalPresentUploadGpuMb), (Format-AuditorRate $totalPresentUploadGpu $totalFrames), (Format-AuditorRate $totalPresentUploadGpuMb $totalFrames))) | Out-Null
$lines.Add(('| Index upload GPU byte-swap | {0} / {1} MB | {2} / {3} MB | Native u16 index uploads whose endian conversion ran through Vulkan compute instead of the CPU conversion loop; per-draw dispatch cost still decides whether this is a speed win. |' -f $totalIndexGpuConvertDispatch, (Format-AuditorDecimal $totalIndexGpuConvertMb), (Format-AuditorRate $totalIndexGpuConvertDispatch $totalFrames), (Format-AuditorRate $totalIndexGpuConvertMb $totalFrames))) | Out-Null
$lines.Add(('| Frame-local index GPU-cache hits | {0} / {1} MB | {2} / {3} MB | Repeated native u16 index sources that reused an already GPU-swapped buffer in the same frame instead of launching another compute dispatch. |' -f $totalIndexGpuCacheHit, (Format-AuditorDecimal $totalIndexGpuCacheHitMb), (Format-AuditorRate $totalIndexGpuCacheHit $totalFrames), (Format-AuditorRate $totalIndexGpuCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Cross-frame persistent index scout hits | {0} / {1} MB | {2} / {3} MB | Profile-only exact native u16 index sources whose raw bytes matched a prior frame; this is a future persistent GPU index-cache candidate, not current migrated work. |' -f $totalIndexPersistentCacheHit, (Format-AuditorDecimal $totalIndexPersistentCacheHitMb), (Format-AuditorRate $totalIndexPersistentCacheHit $totalFrames), (Format-AuditorRate $totalIndexPersistentCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Persistent index verify hits | {0} / {1} MB | {2} / {3} MB | Verify-mode Vulkan-ready index bytes that matched a dedicated long-lived index-buffer heap while rendering still used the normal path. Mismatches must stay zero before any Fast mode. |' -f $totalIndexPersistentVerifyHit, (Format-AuditorDecimal $totalIndexPersistentVerifyHitMb), (Format-AuditorRate $totalIndexPersistentVerifyHit $totalFrames), (Format-AuditorRate $totalIndexPersistentVerifyHitMb $totalFrames))) | Out-Null
$lines.Add(('| Persistent index fast hits | {0} / {1} MB | {2} / {3} MB | Fast-mode indexed draws whose Vulkan index buffer came from the long-lived cache heap instead of regenerating and rewriting the index bytes. |' -f $totalIndexPersistentFastHit, (Format-AuditorDecimal $totalIndexPersistentFastHitMb), (Format-AuditorRate $totalIndexPersistentFastHit $totalFrames), (Format-AuditorRate $totalIndexPersistentFastHitMb $totalFrames))) | Out-Null
$lines.Add(('| Frame-local vertex superset hits | {0} / {1} MB | {2} / {3} MB | Persistent vertex draws that can reuse a contained slice of a same-frame GPU-resident upload instead of re-running CPU vertex prep/upload. Profile mode counts only; Fast mode changes rendering. |' -f $totalVertexSupersetCacheHit, (Format-AuditorDecimal $totalVertexSupersetCacheHitMb), (Format-AuditorRate $totalVertexSupersetCacheHit $totalFrames), (Format-AuditorRate $totalVertexSupersetCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Cross-frame persistent vertex scout hits | {0} / {1} MB | {2} / {3} MB | Profile-only exact source ranges whose bytes matched a previous frame; this is a future long-lived GPU-cache candidate, not current migrated work. |' -f $totalVertexPersistentCacheHit, (Format-AuditorDecimal $totalVertexPersistentCacheHitMb), (Format-AuditorRate $totalVertexPersistentCacheHit $totalFrames), (Format-AuditorRate $totalVertexPersistentCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Persistent vertex verify hits | {0} / {1} MB | {2} / {3} MB | Verify-mode generated vertex bytes that matched a dedicated long-lived cache copy while rendering still used the normal path. Mismatches must stay zero before any Fast mode. |' -f $totalVertexPersistentVerifyHit, (Format-AuditorDecimal $totalVertexPersistentVerifyHitMb), (Format-AuditorRate $totalVertexPersistentVerifyHit $totalFrames), (Format-AuditorRate $totalVertexPersistentVerifyHitMb $totalFrames))) | Out-Null
$lines.Add(('| Persistent vertex fast hits | {0} / {1} MB | {2} / {3} MB | Fast-mode draws whose persistent vertex texel-buffer data came from the long-lived cache heap instead of rewriting generated bytes into the attribute ring. |' -f $totalVertexPersistentFastHit, (Format-AuditorDecimal $totalVertexPersistentFastHitMb), (Format-AuditorRate $totalVertexPersistentFastHit $totalFrames), (Format-AuditorRate $totalVertexPersistentFastHitMb $totalFrames))) | Out-Null
$lines.Add(('| Frame-local volatile vertex hits | {0} / {1} MB | {2} / {3} MB | Repeated transient vertex blobs that can reuse a same-frame GPU-resident upload instead of mapping and rewriting volatile vertex bytes. Profile mode counts only; Fast mode changes rendering. |' -f $totalVertexVolatileCacheHit, (Format-AuditorDecimal $totalVertexVolatileCacheHitMb), (Format-AuditorRate $totalVertexVolatileCacheHit $totalFrames), (Format-AuditorRate $totalVertexVolatileCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Remaining render-pass break debt | {0} | {1} | Main RSX-local debt left after the credit path; on current DepthReadOnly runs this is mostly blit-source source-layout breaks. |' -f $totalRpBreak, (Format-AuditorRate $totalRpBreak $totalFrames))) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Credit class: $gpuMigrationCreditClass. Promote to `gpu-migration-credit` only when the matching screenshots/video are clean and the switch is title-scoped and reversible.") | Out-Null

$lines.Add("") | Out-Null
$lines.Add("## Source-Local Debt") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Signal | Total | Per 60 Frames | Reading |") | Out-Null
$lines.Add("| --- | ---: | ---: | --- |") | Out-Null
$lines.Add(('| Source-read render-pass breaks | {0} | {1} | `resolve_break_blit_src`: the visible source-layout debt left by the fused blit-source path. |' -f $totalResolveBreakBlitSrc, (Format-AuditorRate $totalResolveBreakBlitSrc $totalFrames))) | Out-Null
$lines.Add(('| Source-read share of all breaks | {0}% | - | Share of render-pass breaks explained by fused blit-source source reads. |' -f (Format-AuditorDecimal $blitSourceBreakShare))) | Out-Null
$lines.Add(('| Breaks per fused resolve/blit | {0}% | - | Percent of fused GPU resolve/blit dispatches that still force a render-pass source-layout break. |' -f (Format-AuditorDecimal $blitBreaksPerFusedResolve))) | Out-Null
$lines.Add(('| Cached-source fanout per miss | {0} | - | If fanout is high but source breaks remain flat, cache fanout is not the speed bottleneck. |' -f (Format-AuditorDecimal $blitCacheFanoutPerMiss))) | Out-Null
$lines.Add(('| Cached-source fill/src-layout RP breaks | {0}/{1} | {2}/{3} | Hidden cost in the cached source path; source-layout parity with visible breaks means the first fill is the real debt. |' -f $totalBlitCacheRpFill, $totalBlitCacheRpSrcLayout, (Format-AuditorRate $totalBlitCacheRpFill $totalFrames), (Format-AuditorRate $totalBlitCacheRpSrcLayout $totalFrames))) | Out-Null
$lines.Add(('| Deferred source fills/src-layout | {0}/{1} | {2}/{3} | Deferral avoids new cache-fill breaks only by falling back to the normal visible source path. |' -f $totalBlitCacheDeferFill, $totalBlitCacheDeferSrcLayout, (Format-AuditorRate $totalBlitCacheDeferFill $totalFrames), (Format-AuditorRate $totalBlitCacheDeferSrcLayout $totalFrames))) | Out-Null
if (($totalSourcePrefillClose + $totalSourcePrefillHot + $totalSourcePrefillResolve + $totalSourcePrefillTagDirty) -gt 0) {
    $lines.Add(('| Source prefill profile close/bound | {0}/{1} | {2}/{3} | Profile-only count of natural `close_render_pass()` probes and bound color targets inspected. |' -f $totalSourcePrefillClose, $totalSourcePrefillBound, (Format-AuditorRate $totalSourcePrefillClose $totalFrames), (Format-AuditorRate $totalSourcePrefillBound $totalFrames))) | Out-Null
    $lines.Add(('| Source prefill profile hot/resolve/tagdirty | {0}/{1}/{2} | {3}/{4}/{5} | Hot-source matches at that hook, hot matches needing resolve, and hot matches whose write tag differed from the last resolve tag. Zero hot matches means this hook is not a useful prefill point. |' -f $totalSourcePrefillHot, $totalSourcePrefillResolve, $totalSourcePrefillTagDirty, (Format-AuditorRate $totalSourcePrefillHot $totalFrames), (Format-AuditorRate $totalSourcePrefillResolve $totalFrames), (Format-AuditorRate $totalSourcePrefillTagDirty $totalFrames))) | Out-Null
}
if (($totalSourcePrefillBeginCall + $totalSourcePrefillBeginHot + $totalSourcePrefillBeginResolve + $totalSourcePrefillBeginTagDirty) -gt 0) {
    $lines.Add(('| Source prefill begin call/rp/bound | {0}/{1}/{2} | {3}/{4}/{5} | Profile-only count before `begin_render_pass()`, how often a render pass was already open, and bound color targets inspected. A useful pre-stage point needs hot/resolve hits while `rp` stays low. |' -f $totalSourcePrefillBeginCall, $totalSourcePrefillBeginRp, $totalSourcePrefillBeginBound, (Format-AuditorRate $totalSourcePrefillBeginCall $totalFrames), (Format-AuditorRate $totalSourcePrefillBeginRp $totalFrames), (Format-AuditorRate $totalSourcePrefillBeginBound $totalFrames))) | Out-Null
    $lines.Add(('| Source prefill begin hot/resolve/tagdirty | {0}/{1}/{2} | {3}/{4}/{5} | Hot-source matches at the begin hook, hot matches needing resolve, and hot matches whose write tag differed from the last resolve tag. These are the candidates for a separate cache/scratch prefill before the dependent render pass opens. |' -f $totalSourcePrefillBeginHot, $totalSourcePrefillBeginResolve, $totalSourcePrefillBeginTagDirty, (Format-AuditorRate $totalSourcePrefillBeginHot $totalFrames), (Format-AuditorRate $totalSourcePrefillBeginResolve $totalFrames), (Format-AuditorRate $totalSourcePrefillBeginTagDirty $totalFrames))) | Out-Null
}
if (($totalSourceTransitionCheck + $totalSourceTransitionHot + $totalSourceTransitionRetire + $totalSourceTransitionResolve + $totalSourceTransitionTagDirty) -gt 0) {
    $lines.Add(('| Source transition check/hot/retire | {0}/{1}/{2} | {3}/{4}/{5} | Profile-only inspection at framebuffer transition before previous color targets are made sampleable. A useful pre-stage signal needs hot retired targets at low frequency. |' -f $totalSourceTransitionCheck, $totalSourceTransitionHot, $totalSourceTransitionRetire, (Format-AuditorRate $totalSourceTransitionCheck $totalFrames), (Format-AuditorRate $totalSourceTransitionHot $totalFrames), (Format-AuditorRate $totalSourceTransitionRetire $totalFrames))) | Out-Null
    $lines.Add(('| Source transition rp/resolve/tagdirty | {0}/{1}/{2} | {3}/{4}/{5} | Whether the transition point was already inside a render pass, whether the hot target still required resolve, and whether its write tag differed from the last resolve tag. Useful prestage wants `rp` low and resolve/tagdirty aligned with later source breaks. |' -f $totalSourceTransitionRp, $totalSourceTransitionResolve, $totalSourceTransitionTagDirty, (Format-AuditorRate $totalSourceTransitionRp $totalFrames), (Format-AuditorRate $totalSourceTransitionResolve $totalFrames), (Format-AuditorRate $totalSourceTransitionTagDirty $totalFrames))) | Out-Null
}
if ($totalSourceWriterHit -gt 0) {
    $lines.Add(('| Source writer state hit/hot | {0}/{1} | {2}/{3} | Profile-only count at `surface_store::on_write()` before the render target write tag update, plus matches for the exact hot Eternal Sonata source. |' -f $totalSourceWriterHit, $totalSourceWriterHot, (Format-AuditorRate $totalSourceWriterHit $totalFrames), (Format-AuditorRate $totalSourceWriterHot $totalFrames))) | Out-Null
    $lines.Add(('| Source writer state fast/full all | {0}/{1} | {2}/{3} | Existing writer path classification before the update: fast means `last_use_tag > cache_tag`; full means the slower `on_write()` path. |' -f $totalSourceWriterFast, $totalSourceWriterFull, (Format-AuditorRate $totalSourceWriterFast $totalFrames), (Format-AuditorRate $totalSourceWriterFull $totalFrames))) | Out-Null
    $lines.Add(('| Source writer state hot fast/full | {0}/{1} | {2}/{3} | Exact hot-source write classification. If hot writes are already mostly fast, a future producer-stage path must avoid adding expensive work to this boundary. |' -f $totalSourceWriterHotFast, $totalSourceWriterHotFull, (Format-AuditorRate $totalSourceWriterHotFast $totalFrames), (Format-AuditorRate $totalSourceWriterHotFull $totalFrames))) | Out-Null
    $lines.Add(('| Source writer state hot resolve/tagdirty | {0}/{1} | {2}/{3} | Exact hot-source state before the new write: whether the surface still had unresolved MSAA contents and whether the write tag differed from the last audited resolve tag. |' -f $totalSourceWriterHotResolve, $totalSourceWriterHotTagDirty, (Format-AuditorRate $totalSourceWriterHotResolve $totalFrames), (Format-AuditorRate $totalSourceWriterHotTagDirty $totalFrames))) | Out-Null
    $lines.Add(('| Source writer state hot gt/le cache | {0}/{1} | {2}/{3} | Exact hot-source `last_use_tag` relationship to `cache_tag`; this is the producer-side test for whether the clean moving route actually revisits the same hot surface as a fresh writer. |' -f $totalSourceWriterHotGtCache, $totalSourceWriterHotLeCache, (Format-AuditorRate $totalSourceWriterHotGtCache $totalFrames), (Format-AuditorRate $totalSourceWriterHotLeCache $totalFrames))) | Out-Null
}
if (($totalSourceWriterTagNew + $totalSourceWriterTagRepeat + $totalSourceWriterTagCollision + $totalSourceWriterTagZero) -gt 0) {
    $lines.Add(('| Source writer tag new/repeat | {0}/{1} | {2}/{3} | Coalescing scout for exact hot-source writer tags per auditor interval. Low `new` with high `repeat` means a future producer-stage cache can be keyed, while high `new` keeps the path too hot. |' -f $totalSourceWriterTagNew, $totalSourceWriterTagRepeat, (Format-AuditorRate $totalSourceWriterTagNew $totalFrames), (Format-AuditorRate $totalSourceWriterTagRepeat $totalFrames))) | Out-Null
    $lines.Add(('| Source writer tag collision/zero | {0}/{1} | {2}/{3} | Hash-table overflow and zero-tag guardrail for the scout. Nonzero collisions make the unique count a lower bound instead of an exact count. |' -f $totalSourceWriterTagCollision, $totalSourceWriterTagZero, (Format-AuditorRate $totalSourceWriterTagCollision $totalFrames), (Format-AuditorRate $totalSourceWriterTagZero $totalFrames))) | Out-Null
}
if ($totalSourceBlitStateHit -gt 0) {
    $lines.Add(('| Source blit state hit/hot | {0}/{1} | {2}/{3} | Profile-only count of render-target blit sources inspected at the consumer callsite and matches for the exact hot Eternal Sonata source. |' -f $totalSourceBlitStateHit, $totalSourceBlitStateHot, (Format-AuditorRate $totalSourceBlitStateHit $totalFrames), (Format-AuditorRate $totalSourceBlitStateHot $totalFrames))) | Out-Null
    $lines.Add(('| Source blit state rp/read/color/general | {0}/{1}/{2}/{3} | {4}/{5}/{6}/{7} | Render-pass-open count and source layout before fused blit-source work. High `rp` plus zero `read` means there is no cheap already-readable source to consume. |' -f $totalSourceBlitStateRp, $totalSourceBlitStateRead, $totalSourceBlitStateColor, $totalSourceBlitStateGeneral, (Format-AuditorRate $totalSourceBlitStateRp $totalFrames), (Format-AuditorRate $totalSourceBlitStateRead $totalFrames), (Format-AuditorRate $totalSourceBlitStateColor $totalFrames), (Format-AuditorRate $totalSourceBlitStateGeneral $totalFrames))) | Out-Null
    $lines.Add(('| Source blit state resolve/tagdirty | {0}/{1} | {2}/{3} | Hot-source state that still requires resolve and whose write tag differs from the last resolve tag at the consumer callsite. |' -f $totalSourceBlitStateResolve, $totalSourceBlitStateTagDirty, (Format-AuditorRate $totalSourceBlitStateResolve $totalFrames), (Format-AuditorRate $totalSourceBlitStateTagDirty $totalFrames))) | Out-Null
}
if ($totalSourceFusedStateHit -gt 0) {
    $lines.Add(('| Source fused state hit/hot | {0}/{1} | {2}/{3} | Profile-only count after fused blit-source rejects have passed. This is the narrow counter for the source-local candidate path. |' -f $totalSourceFusedStateHit, $totalSourceFusedStateHot, (Format-AuditorRate $totalSourceFusedStateHit $totalFrames), (Format-AuditorRate $totalSourceFusedStateHot $totalFrames))) | Out-Null
    $lines.Add(('| Source fused state rp/read/color/general | {0}/{1}/{2}/{3} | {4}/{5}/{6}/{7} | Layout at the exact fused candidate. Hot `rp` plus zero `read` confirms source-read debt is real at the candidate, not broad loading noise. |' -f $totalSourceFusedStateRp, $totalSourceFusedStateRead, $totalSourceFusedStateColor, $totalSourceFusedStateGeneral, (Format-AuditorRate $totalSourceFusedStateRp $totalFrames), (Format-AuditorRate $totalSourceFusedStateRead $totalFrames), (Format-AuditorRate $totalSourceFusedStateColor $totalFrames), (Format-AuditorRate $totalSourceFusedStateGeneral $totalFrames))) | Out-Null
    $lines.Add(('| Source fused state resolve/tagdirty | {0}/{1} | {2}/{3} | Fused candidate state that still requires resolve and whose write tag differs from the last resolve tag. |' -f $totalSourceFusedStateResolve, $totalSourceFusedStateTagDirty, (Format-AuditorRate $totalSourceFusedStateResolve $totalFrames), (Format-AuditorRate $totalSourceFusedStateTagDirty $totalFrames))) | Out-Null
}
if (($totalSourceFusedTagNew + $totalSourceFusedTagRepeat + $totalSourceFusedTagCollision + $totalSourceFusedTagZero) -gt 0) {
    $lines.Add(('| Source fused tag new/repeat | {0}/{1} | {2}/{3} | Exact hot-source content tag reuse at the fused resolve boundary. Repeats here prove consumer-side source coalescing is available; new tags approximate the first-break floor. |' -f $totalSourceFusedTagNew, $totalSourceFusedTagRepeat, (Format-AuditorRate $totalSourceFusedTagNew $totalFrames), (Format-AuditorRate $totalSourceFusedTagRepeat $totalFrames))) | Out-Null
    $lines.Add(('| Source fused tag collision/zero | {0}/{1} | {2}/{3} | Hash-table overflow and missing-tag guardrail for the consumer scout. Nonzero collisions make the unique count a lower bound. |' -f $totalSourceFusedTagCollision, $totalSourceFusedTagZero, (Format-AuditorRate $totalSourceFusedTagCollision $totalFrames), (Format-AuditorRate $totalSourceFusedTagZero $totalFrames))) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("Debt class: $sourceLocalDebtClass. $sourceLocalDebtReading") | Out-Null

if ($totalProfileBlitSourceCalls -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("## Resolve Coalescing Scout") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Signal | Total | Per 60 Frames | Reading |") | Out-Null
    $lines.Add("| --- | ---: | ---: | --- |") | Out-Null
    $lines.Add(('| Profiled blit-source resolve calls | {0} | {1} | Source-level resolve demand seen while `RSX resolve probe: Profile` is enabled. |' -f $totalProfileBlitSourceCalls, (Format-AuditorRate $totalProfileBlitSourceCalls $totalFrames))) | Out-Null
    $lines.Add(('| Duplicate source-tag calls | {0} | {1} | Upper-bound calls whose source content tag repeated; these still may need distinct destination writes. |' -f $totalProfileBlitSourceDuplicateTags, (Format-AuditorRate $totalProfileBlitSourceDuplicateTags $totalFrames))) | Out-Null
    $lines.Add(('| Unique source-tag floor | {0} | {1} | Lower-bound source resolves if a future GPU-resident source-resolve cache can fan out to destination blits. |' -f $profileBlitSourceUniqueTagFloor, (Format-AuditorRate $profileBlitSourceUniqueTagFloor $totalFrames))) | Out-Null
    $lines.Add(('| Duplicate share | {0}% | - | High values point at a source-resolve cache/coalescer experiment, not at dropping destination copies. |' -f (Format-AuditorDecimal $profileBlitSourceDuplicateShare))) | Out-Null
    if ($blitSourceProfileDistinctKeys -gt 0) {
        $lines.Add(('| Blit-source profile keys | {0} | - | Top key `{1}` accounts for {2} calls; repeated keys are better cache targets than one-off blits. |' -f $blitSourceProfileDistinctKeys, $topBlitSourceProfileKey, $topBlitSourceProfileCount)) | Out-Null
    }
}

if ($blitSourceResolveProfileRecords.Count -gt 0 -and $blitSourceProfileRecords.Count -gt 0) {
    $resolveSourceJoins = @(
        $blitSourceResolveProfileRecords |
            Group-Object -Property base, pitch, h, w, fmt, samples, sx, sy |
            ForEach-Object {
                $first = $_.Group[0]
                $resolveCount = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                $resolveDup = [UInt64](($_.Group | Measure-Object -Property dup -Sum).Sum)
                $baseValue = Convert-AuditorNumber $first.base
                $byteSpan = [UInt64]($first.pitch * $first.h)
                $endValue = $baseValue + $byteSpan
                $matchingSourceRecords = @(
                    $blitSourceProfileRecords | Where-Object {
                        $sourceValue = Convert-AuditorNumber $_.src
                        $sourceValue -ge $baseValue -and $sourceValue -lt $endValue
                    }
                )
                $matchingCount = [UInt64]0
                if ($matchingSourceRecords.Count -gt 0) {
                    $matchingCount = [UInt64](($matchingSourceRecords | Measure-Object -Property count -Sum).Sum)
                }
                $uniqueFloor = [UInt64]0
                if ($resolveCount -gt $resolveDup) {
                    $uniqueFloor = [UInt64]($resolveCount - $resolveDup)
                }
                $breaksPerUniquePercent = 0.0
                if ($uniqueFloor -gt 0) {
                    $breaksPerUniquePercent = ([double]$totalResolveBreakBlitSrc * 100.0) / [double]$uniqueFloor
                }

                $sourceShapes = @(
                    $matchingSourceRecords |
                        Group-Object -Property src, src_req, src_rect, src_pitch, src_bpp, src_fmt, src_ctx, flags |
                        ForEach-Object {
                            $sourceFirst = $_.Group[0]
                            $sourceValue = Convert-AuditorNumber $sourceFirst.src
                            $offset = $sourceValue - $baseValue
                            $destCount = @(
                                $_.Group |
                                    ForEach-Object { '{0}:{1}:{2}:{3}:{4}:{5}:{6}' -f $_.dst, $_.dst_req, $_.dst_rect, $_.dst_pitch, $_.dst_bpp, $_.dst_fmt, $_.dst_ctx } |
                                    Sort-Object -Unique
                            ).Count
                            [pscustomobject]@{
                                count        = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                                offset_value = [UInt64]$offset
                                offset       = ('+0x{0:x}' -f $offset)
                                src          = $sourceFirst.src
                                req          = $sourceFirst.src_req
                                rect         = $sourceFirst.src_rect
                                dests        = [UInt64]$destCount
                            }
                        } |
                        Sort-Object -Property @{ Expression = "count"; Descending = $true }, @{ Expression = "offset_value"; Ascending = $true }
                )

                $shapeText = if ($sourceShapes.Count -gt 0) {
                    ($sourceShapes | Select-Object -First 6 | ForEach-Object { '{0}x {1} {2} {3} ({4} dst)' -f $_.count, $_.offset, $_.req, $_.rect, $_.dests }) -join ", "
                } else {
                    "-"
                }

                $eligibilityRows = @(
                    $matchingSourceRecords |
                        ForEach-Object {
                            $flags = [UInt64]$_.flags
                            $cachedDest = (($flags -band ([UInt64]1 -shl 5)) -ne 0)
                            $dstRenderTarget = (($flags -band ([UInt64]1 -shl 6)) -ne 0)
                            $blockingFlags = $flags -band (
                                ([UInt64]1 -shl 0) -bor
                                ([UInt64]1 -shl 1) -bor
                                ([UInt64]1 -shl 2) -bor
                                ([UInt64]1 -shl 3) -bor
                                ([UInt64]1 -shl 4) -bor
                                ([UInt64]1 -shl 12) -bor
                                ([UInt64]1 -shl 13))
                            $cleanFlags = ($blockingFlags -eq 0)
                            $formatMatch = ($_.src_fmt -eq $_.dst_fmt)
                            $areaMatch = ($_.src_req -eq $_.dst_req -and $_.src_rect -eq $_.dst_rect)
                            $candidate = ($cachedDest -and $cleanFlags -and $formatMatch -and $areaMatch -and -not $dstRenderTarget)
                            $sourceValue = Convert-AuditorNumber $_.src

                            [pscustomobject]@{
                                join_base      = $first.base
                                resolve_calls  = $resolveCount
                                source_rp_breaks = $totalResolveBreakBlitSrc
                                src            = $_.src
                                src_offset     = ('+0x{0:x}' -f ($sourceValue - $baseValue))
                                dst            = $_.dst
                                count          = $_.count
                                src_req        = $_.src_req
                                dst_req        = $_.dst_req
                                src_rect       = $_.src_rect
                                dst_rect       = $_.dst_rect
                                src_pitch      = $_.src_pitch
                                dst_pitch      = $_.dst_pitch
                                src_fmt        = $_.src_fmt
                                dst_fmt        = $_.dst_fmt
                                src_ctx        = $_.src_ctx
                                dst_ctx        = $_.dst_ctx
                                flags          = ('0x{0:x8}' -f $flags)
                                cached_dest    = $cachedDest
                                dst_render_target = $dstRenderTarget
                                clean_flags    = $cleanFlags
                                format_match   = $formatMatch
                                area_match     = $areaMatch
                                candidate      = $candidate
                            }
                        }
                )

                $eligibleCount = [UInt64]0
                $cachedDestCount = [UInt64]0
                $cleanFlagCount = [UInt64]0
                $formatMatchCount = [UInt64]0
                $areaMatchCount = [UInt64]0
                if ($eligibilityRows.Count -gt 0) {
                    $eligibleCount = [UInt64](($eligibilityRows | Where-Object { $_.candidate } | Measure-Object -Property count -Sum).Sum)
                    $cachedDestCount = [UInt64](($eligibilityRows | Where-Object { $_.cached_dest } | Measure-Object -Property count -Sum).Sum)
                    $cleanFlagCount = [UInt64](($eligibilityRows | Where-Object { $_.clean_flags } | Measure-Object -Property count -Sum).Sum)
                    $formatMatchCount = [UInt64](($eligibilityRows | Where-Object { $_.format_match } | Measure-Object -Property count -Sum).Sum)
                    $areaMatchCount = [UInt64](($eligibilityRows | Where-Object { $_.area_match } | Measure-Object -Property count -Sum).Sum)
                }

                [pscustomobject]@{
                    count       = $resolveCount
                    dup         = $resolveDup
                    unique_floor = $uniqueFloor
                    matched     = $matchingCount
                    match_share = if ($resolveCount -gt 0) { ([double]$matchingCount * 100.0) / [double]$resolveCount } else { 0.0 }
                    source_rp_breaks = $totalResolveBreakBlitSrc
                    source_rp_breaks_per60 = if ($totalFrames -gt 0) { ([double]$totalResolveBreakBlitSrc * 60.0) / [double]$totalFrames } else { 0.0 }
                    breaks_per_unique_percent = $breaksPerUniquePercent
                    base        = $first.base
                    span_mb     = [double]$byteSpan / 1048576.0
                    w           = $first.w
                    h           = $first.h
                    fmt         = $first.fmt
                    samples     = $first.samples
                    grid        = ('{0}x{1}' -f $first.sx, $first.sy)
                    pitch       = $first.pitch
                    shapes      = $sourceShapes.Count
                    shape_text  = $shapeText
                    eligible    = $eligibleCount
                    cached_dest = $cachedDestCount
                    clean_flags = $cleanFlagCount
                    format_match = $formatMatchCount
                    area_match  = $areaMatchCount
                    eligibility_rows = $eligibilityRows
                }
            } |
            Sort-Object -Property count -Descending
    )

    $resolveSourceJoins | Export-Csv -LiteralPath $SourceBaseJoinCsvPath -NoTypeInformation -Encoding UTF8

    $sourceLocalEligibilityRawRows = @(
        $resolveSourceJoins |
            ForEach-Object { $_.eligibility_rows } |
            Where-Object { $null -ne $_ } |
            Sort-Object -Property @{ Expression = "count"; Descending = $true }, @{ Expression = "src"; Ascending = $true }, @{ Expression = "dst"; Ascending = $true }
    )
    $sourceLocalEligibilityRows = @(
        $sourceLocalEligibilityRawRows |
            Group-Object -Property join_base, src, src_offset, dst, src_req, dst_req, src_rect, dst_rect, src_pitch, dst_pitch, src_fmt, dst_fmt, src_ctx, dst_ctx, flags, cached_dest, dst_render_target, clean_flags, format_match, area_match, candidate |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    join_base      = $first.join_base
                    resolve_calls  = $first.resolve_calls
                    source_rp_breaks = $first.source_rp_breaks
                    src            = $first.src
                    src_offset     = $first.src_offset
                    dst            = $first.dst
                    count          = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    src_req        = $first.src_req
                    dst_req        = $first.dst_req
                    src_rect       = $first.src_rect
                    dst_rect       = $first.dst_rect
                    src_pitch      = $first.src_pitch
                    dst_pitch      = $first.dst_pitch
                    src_fmt        = $first.src_fmt
                    dst_fmt        = $first.dst_fmt
                    src_ctx        = $first.src_ctx
                    dst_ctx        = $first.dst_ctx
                    flags          = $first.flags
                    cached_dest    = $first.cached_dest
                    dst_render_target = $first.dst_render_target
                    clean_flags    = $first.clean_flags
                    format_match   = $first.format_match
                    area_match     = $first.area_match
                    candidate      = $first.candidate
                }
            } |
            Sort-Object -Property @{ Expression = "count"; Descending = $true }, @{ Expression = "src"; Ascending = $true }, @{ Expression = "dst"; Ascending = $true }
    )
    if ($sourceLocalEligibilityRows.Count -gt 0) {
        $sourceLocalEligibilityRows | Export-Csv -LiteralPath $SourceLocalEligibilityCsvPath -NoTypeInformation -Encoding UTF8
    }

    $lines.Add("") | Out-Null
    $lines.Add("## Resolve Source-Base Join") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("This joins exact blit-source resolve bases with source-profile rows whose source address falls inside the resolve base span. Counts still inherit profile aggregation limits, but an exact 100% join gives a concrete source-local target.") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Resolve Calls | Source Profile In Base | Match | Dup | Unique Floor | Source RP Break Target | Base | Size/Fmt/Samples | Pitch/Grid | Source Shapes | Reading |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($join in @($resolveSourceJoins | Select-Object -First $Top)) {
        $reading = if ($join.matched -eq $join.count -and $join.count -gt 0) {
            "Exact source-base join; target these split source shapes for source-local/pre-stage."
        } elseif ($join.matched -gt 0) {
            "Partial or aggregate join; useful for ranking, but verify with direct source-local counters before a fast path."
        } else {
            "No matching source-profile rows; keep this out of the source-local fast path."
        }
        $targetText = ('{0} ({1}/60, {2}% of unique)' -f
            $join.source_rp_breaks,
            (Format-AuditorDecimal $join.source_rp_breaks_per60),
            (Format-AuditorDecimal $join.breaks_per_unique_percent))
        $lines.Add(('| {0} | {1} | {2} | {3}% | {4} | {5} | {6} | `{7}` | {8}x{9} `{10}` {11}x | {12}/{13} | {14} | {15} |' -f
            $rank,
            $join.count,
            $join.matched,
            (Format-AuditorDecimal $join.match_share),
            $join.dup,
            $join.unique_floor,
            $targetText,
            $join.base,
            $join.w,
            $join.h,
            $join.fmt,
            $join.samples,
            $join.pitch,
            $join.grid,
            $join.shape_text,
            $reading)) | Out-Null
        $rank++
    }

    if ($sourceLocalEligibilityRows.Count -gt 0) {
        $topJoin = @($resolveSourceJoins | Select-Object -First 1)[0]
        $eligibleShare = if ($topJoin.matched -gt 0) { ([double]$topJoin.eligible * 100.0) / [double]$topJoin.matched } else { 0.0 }
        $cachedDestShare = if ($topJoin.matched -gt 0) { ([double]$topJoin.cached_dest * 100.0) / [double]$topJoin.matched } else { 0.0 }
        $cleanFlagsShare = if ($topJoin.matched -gt 0) { ([double]$topJoin.clean_flags * 100.0) / [double]$topJoin.matched } else { 0.0 }
        $formatMatchShare = if ($topJoin.matched -gt 0) { ([double]$topJoin.format_match * 100.0) / [double]$topJoin.matched } else { 0.0 }
        $areaMatchShare = if ($topJoin.matched -gt 0) { ([double]$topJoin.area_match * 100.0) / [double]$topJoin.matched } else { 0.0 }
        $lines.Add("") | Out-Null
        $lines.Add("## Source-Local Eligibility") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("This uses the existing Windows callsite `Thor RSX Blit Source Profile` rows to decide whether the exact joined source base is eligible for a future source-local/pre-stage fast path. It is profile-only, not a behavior change.") | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add("| Signal | Count | Share | Reading |") | Out-Null
        $lines.Add("| --- | ---: | ---: | --- |") | Out-Null
        $lines.Add(('| Source-profile rows in top base | {0} | 100.00% | Top joined source base `{1}`, pitch `{2}`, target source RP break baseline `{3}`. |' -f $topJoin.matched, $topJoin.base, $topJoin.pitch, $topJoin.source_rp_breaks)) | Out-Null
        $lines.Add(('| Cached-dest rows | {0} | {1}% | Candidate path writes GPU-resident blit destinations rather than a render-target attachment. |' -f $topJoin.cached_dest, (Format-AuditorDecimal $cachedDestShare))) | Out-Null
        $lines.Add(('| Clean flag rows | {0} | {1}% | Excludes interpolate, format-convert, typeless, null-region, and flip cases. |' -f $topJoin.clean_flags, (Format-AuditorDecimal $cleanFlagsShare))) | Out-Null
        $lines.Add(('| Format-match rows | {0} | {1}% | Source and destination GCM formats match in the blit-source profile row. |' -f $topJoin.format_match, (Format-AuditorDecimal $formatMatchShare))) | Out-Null
        $lines.Add(('| Area-match rows | {0} | {1}% | Source and destination requested size/rect match, so the candidate is copy-like after resolve. |' -f $topJoin.area_match, (Format-AuditorDecimal $areaMatchShare))) | Out-Null
        $lines.Add(('| Fully eligible rows | {0} | {1}% | Rows that pass cached-dest, clean-flags, format-match, area-match, and non-render-target-destination gates. |' -f $topJoin.eligible, (Format-AuditorDecimal $eligibleShare))) | Out-Null
        $lines.Add("") | Out-Null
        $lines.Add(('CSV: `{0}`' -f $SourceLocalEligibilityCsvPath)) | Out-Null
    }
}

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
$lines.Add(('| Resolve calls color/depth | {0}/{1} | {2}/{3} | MSAA resolve demand before any lab skip. |' -f $totalResolveColor, $totalResolveDepth, (Format-AuditorRate $totalResolveColor $totalFrames), (Format-AuditorRate $totalResolveDepth $totalFrames))) | Out-Null
$lines.Add(('| Resolve skips color/depth | {0}/{1} | {2}/{3} | Unsafe lab probe activity; screenshots decide whether route survives. |' -f $totalResolveSkipColor, $totalResolveSkipDepth, (Format-AuditorRate $totalResolveSkipColor $totalFrames), (Format-AuditorRate $totalResolveSkipDepth $totalFrames))) | Out-Null
$lines.Add(('| Resolve barriers rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable | {0}/{1}/{2}/{3}/{4}/{5}/{6} | - | Split of resolve layout transitions by normal resolve versus fused blit-source path. |' -f $totalResolveBarrierRtSrc, $totalResolveBarrierRtDst, $totalResolveBarrierRtRestore, $totalResolveBarrierRtReadable, $totalResolveBarrierBlitSrc, $totalResolveBarrierBlitRestore, $totalResolveBarrierBlitReadable)) | Out-Null
$lines.Add(('| Resolve breaks rt_src/rt_dst/rt_restore/rt_readable/blit_src/blit_restore/blit_readable | {0}/{1}/{2}/{3}/{4}/{5}/{6} | - | Resolve layout transitions that ended an open render pass. |' -f $totalResolveBreakRtSrc, $totalResolveBreakRtDst, $totalResolveBreakRtRestore, $totalResolveBreakRtReadable, $totalResolveBreakBlitSrc, $totalResolveBreakBlitRestore, $totalResolveBreakBlitReadable)) | Out-Null
$lines.Add(('| DMA fences all/host | {0}/{1} | {2}/{3} | Candidate for narrower host-read or GPU-resident path. |' -f $totalDmaAll, $totalDmaHost, (Format-AuditorRate $totalDmaAll $totalFrames), (Format-AuditorRate $totalDmaHost $totalFrames))) | Out-Null
$lines.Add(('| DMA MB all/host | {0}/{1} | {2}/{3} | Bandwidth tied to transfer fences. |' -f (Format-AuditorDecimal $totalDmaMb), (Format-AuditorDecimal $totalDmaHostMb), (Format-AuditorRate $totalDmaMb $totalFrames), (Format-AuditorRate $totalDmaHostMb $totalFrames))) | Out-Null
$lines.Add(('| Query waits | {0} | {1} | Occlusion/query wait pressure if nonzero. |' -f $totalQueryWait, (Format-AuditorRate $totalQueryWait $totalFrames))) | Out-Null
$lines.Add(('| Pipeline creates g/c/slow | {0}/{1}/{2} | - | Warmup/stutter lane, not steady-state unless repeated. |' -f $totalPipeGraphics, $totalPipeCompute, $totalPipeSlow)) | Out-Null
$lines.Add(('| Pipeline create ms | {0} | {1} | Shader/pipeline creation wall time. |' -f (Format-AuditorDecimal ([double]$totalPipeUs / 1000.0)), (Format-AuditorRate ([double]$totalPipeUs / 1000.0) $totalFrames))) | Out-Null
$lines.Add(('| Detile in/out MB | {0}/{1} | {2}/{3} | Texture prep or layout conversion candidate. |' -f (Format-AuditorDecimal $totalInMb), (Format-AuditorDecimal $totalOutMb), (Format-AuditorRate $totalInMb $totalFrames), (Format-AuditorRate $totalOutMb $totalFrames))) | Out-Null
$lines.Add(('| Simple upload MB | {0} | {1} | CPU-to-GPU upload bandwidth candidate. |' -f (Format-AuditorDecimal $totalUploadMb), (Format-AuditorRate $totalUploadMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex upload draws cache hit/miss | {0} {1}/{2} | {3} {4}/{5} | CPU-side vertex prep for GPU-consumed data; high miss/volatile traffic marks a GPU-resident cache or format-conversion lane. |' -f $totalVertexUploadDraws, $totalVertexUploadCacheHit, $totalVertexUploadCacheMiss, (Format-AuditorRate $totalVertexUploadDraws $totalFrames), (Format-AuditorRate $totalVertexUploadCacheHit $totalFrames), (Format-AuditorRate $totalVertexUploadCacheMiss $totalFrames))) | Out-Null
$lines.Add(('| Vertex upload MB persistent/volatile | {0}/{1} | {2}/{3} | Persistent cacheable bytes versus volatile per-draw bytes. |' -f (Format-AuditorDecimal $totalVertexUploadPersistentMb), (Format-AuditorDecimal $totalVertexUploadVolatileMb), (Format-AuditorRate $totalVertexUploadPersistentMb $totalFrames), (Format-AuditorRate $totalVertexUploadVolatileMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex superset cache hit/miss | {0}/{1} | {2}/{3} | Contained-range reuse opportunities in the same frame; hits are CPU vertex-prep work we can potentially keep GPU-resident. |' -f $totalVertexSupersetCacheHit, $totalVertexSupersetCacheMiss, (Format-AuditorRate $totalVertexSupersetCacheHit $totalFrames), (Format-AuditorRate $totalVertexSupersetCacheMiss $totalFrames))) | Out-Null
$lines.Add(('| Vertex superset cache hit MB | {0} | {1} | Persistent vertex bytes represented by same-frame superset hits. |' -f (Format-AuditorDecimal $totalVertexSupersetCacheHitMb), (Format-AuditorRate $totalVertexSupersetCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent cache scout hit/change/new | {0}/{1}/{2} | {3}/{4}/{5} | Exact cross-frame source ranges that were stable, changed, or first-seen under the profile-only long-lived-cache scout. |' -f $totalVertexPersistentCacheHit, $totalVertexPersistentCacheChange, $totalVertexPersistentCacheNew, (Format-AuditorRate $totalVertexPersistentCacheHit $totalFrames), (Format-AuditorRate $totalVertexPersistentCacheChange $totalFrames), (Format-AuditorRate $totalVertexPersistentCacheNew $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent cache scout hit MB | {0} | {1} | Stable exact-range persistent vertex bytes that could feed a future dedicated GPU-resident cache with real invalidation. |' -f (Format-AuditorDecimal $totalVertexPersistentCacheHitMb), (Format-AuditorRate $totalVertexPersistentCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent verify hit/store/mismatch | {0}/{1}/{2} | {3}/{4}/{5} | Dedicated-cache verify activity for generated persistent vertex bytes; nonzero mismatches block any Fast path. |' -f $totalVertexPersistentVerifyHit, $totalVertexPersistentVerifyStore, $totalVertexPersistentVerifyMismatch, (Format-AuditorRate $totalVertexPersistentVerifyHit $totalFrames), (Format-AuditorRate $totalVertexPersistentVerifyStore $totalFrames), (Format-AuditorRate $totalVertexPersistentVerifyMismatch $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent verify hit/store MB | {0}/{1} | {2}/{3} | Bytes compared against or inserted into the dedicated persistent vertex cache heap while visible rendering stayed on the normal upload path. |' -f (Format-AuditorDecimal $totalVertexPersistentVerifyHitMb), (Format-AuditorDecimal $totalVertexPersistentVerifyStoreMb), (Format-AuditorRate $totalVertexPersistentVerifyHitMb $totalFrames), (Format-AuditorRate $totalVertexPersistentVerifyStoreMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent fast hit/store/reject | {0}/{1}/{2} | {3}/{4}/{5} | Dedicated-cache fast path activity; rejects are guarded fallbacks to the normal CPU upload path. |' -f $totalVertexPersistentFastHit, $totalVertexPersistentFastStore, $totalVertexPersistentFastReject, (Format-AuditorRate $totalVertexPersistentFastHit $totalFrames), (Format-AuditorRate $totalVertexPersistentFastStore $totalFrames), (Format-AuditorRate $totalVertexPersistentFastReject $totalFrames))) | Out-Null
$lines.Add(('| Vertex persistent fast hit/store MB | {0}/{1} | {2}/{3} | Bytes served from or inserted into the long-lived persistent vertex cache heap in Fast mode. |' -f (Format-AuditorDecimal $totalVertexPersistentFastHitMb), (Format-AuditorDecimal $totalVertexPersistentFastStoreMb), (Format-AuditorRate $totalVertexPersistentFastHitMb $totalFrames), (Format-AuditorRate $totalVertexPersistentFastStoreMb $totalFrames))) | Out-Null
$lines.Add(('| Vertex volatile cache hit/miss | {0}/{1} | {2}/{3} | Same-frame transient vertex-data reuse opportunities keyed by the actual volatile source bytes. |' -f $totalVertexVolatileCacheHit, $totalVertexVolatileCacheMiss, (Format-AuditorRate $totalVertexVolatileCacheHit $totalFrames), (Format-AuditorRate $totalVertexVolatileCacheMiss $totalFrames))) | Out-Null
$lines.Add(('| Vertex volatile cache hit MB | {0} | {1} | Volatile vertex bytes represented by same-frame cache hits. |' -f (Format-AuditorDecimal $totalVertexVolatileCacheHitMb), (Format-AuditorRate $totalVertexVolatileCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Index upload draws emulated/restart | {0} {1}/{2} | {3} {4}/{5} | CPU-side index generation/primitive-restart handling; emulated or restart-heavy draws are offload candidates only if visual proof survives. |' -f $totalIndexUploadDraws, $totalIndexUploadEmulated, $totalIndexUploadRestart, (Format-AuditorRate $totalIndexUploadDraws $totalFrames), (Format-AuditorRate $totalIndexUploadEmulated $totalFrames), (Format-AuditorRate $totalIndexUploadRestart $totalFrames))) | Out-Null
$lines.Add(('| Index upload MB | {0} | {1} | GPU-consumed index-buffer upload bandwidth. |' -f (Format-AuditorDecimal $totalIndexUploadMb), (Format-AuditorRate $totalIndexUploadMb $totalFrames))) | Out-Null
$lines.Add(('| Index GPU convert eligible/dispatch/reject | {0}/{1}/{2} | {3}/{4}/{5} | Gated native u16 index byte-swap attempts. Dispatches mean endian conversion was moved to Vulkan compute; rejects mean the gate saw a candidate but kept the CPU path. |' -f $totalIndexGpuConvertEligible, $totalIndexGpuConvertDispatch, $totalIndexGpuConvertReject, (Format-AuditorRate $totalIndexGpuConvertEligible $totalFrames), (Format-AuditorRate $totalIndexGpuConvertDispatch $totalFrames), (Format-AuditorRate $totalIndexGpuConvertReject $totalFrames))) | Out-Null
$lines.Add(('| Index GPU convert MB | {0} | {1} | Bytes converted by the gated GPU index byte-swap path. |' -f (Format-AuditorDecimal $totalIndexGpuConvertMb), (Format-AuditorRate $totalIndexGpuConvertMb $totalFrames))) | Out-Null
$lines.Add(('| Index GPU cache hit/miss | {0}/{1} | {2}/{3} | Frame-local reuse of already GPU-swapped native u16 index buffers. Hits avoid another compute dispatch and avoid another index upload. |' -f $totalIndexGpuCacheHit, $totalIndexGpuCacheMiss, (Format-AuditorRate $totalIndexGpuCacheHit $totalFrames), (Format-AuditorRate $totalIndexGpuCacheMiss $totalFrames))) | Out-Null
$lines.Add(('| Index GPU cache hit MB | {0} | {1} | Bytes represented by frame-local GPU index-cache hits. |' -f (Format-AuditorDecimal $totalIndexGpuCacheHitMb), (Format-AuditorRate $totalIndexGpuCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Index persistent cache scout hit/change/new | {0}/{1}/{2} | {3}/{4}/{5} | Exact cross-frame native u16 index sources that were stable, changed, or first-seen under the profile-only long-lived-cache scout. |' -f $totalIndexPersistentCacheHit, $totalIndexPersistentCacheChange, $totalIndexPersistentCacheNew, (Format-AuditorRate $totalIndexPersistentCacheHit $totalFrames), (Format-AuditorRate $totalIndexPersistentCacheChange $totalFrames), (Format-AuditorRate $totalIndexPersistentCacheNew $totalFrames))) | Out-Null
$lines.Add(('| Index persistent cache scout hit MB | {0} | {1} | Stable exact index bytes that could feed a future persistent GPU index buffer without one compute dispatch per draw. |' -f (Format-AuditorDecimal $totalIndexPersistentCacheHitMb), (Format-AuditorRate $totalIndexPersistentCacheHitMb $totalFrames))) | Out-Null
$lines.Add(('| Index persistent verify hit/store/mismatch | {0}/{1}/{2} | {3}/{4}/{5} | Dedicated-cache verify activity for generated persistent index bytes; nonzero mismatches block any Fast path. |' -f $totalIndexPersistentVerifyHit, $totalIndexPersistentVerifyStore, $totalIndexPersistentVerifyMismatch, (Format-AuditorRate $totalIndexPersistentVerifyHit $totalFrames), (Format-AuditorRate $totalIndexPersistentVerifyStore $totalFrames), (Format-AuditorRate $totalIndexPersistentVerifyMismatch $totalFrames))) | Out-Null
$lines.Add(('| Index persistent verify hit/store MB | {0}/{1} | {2}/{3} | Bytes compared against or inserted into the dedicated persistent index cache heap while visible rendering stayed on the normal upload path. |' -f (Format-AuditorDecimal $totalIndexPersistentVerifyHitMb), (Format-AuditorDecimal $totalIndexPersistentVerifyStoreMb), (Format-AuditorRate $totalIndexPersistentVerifyHitMb $totalFrames), (Format-AuditorRate $totalIndexPersistentVerifyStoreMb $totalFrames))) | Out-Null
$lines.Add(('| Index persistent fast hit/store/reject | {0}/{1}/{2} | {3}/{4}/{5} | Dedicated-cache fast path activity; rejects are guarded fallbacks to the normal CPU index-generation path. |' -f $totalIndexPersistentFastHit, $totalIndexPersistentFastStore, $totalIndexPersistentFastReject, (Format-AuditorRate $totalIndexPersistentFastHit $totalFrames), (Format-AuditorRate $totalIndexPersistentFastStore $totalFrames), (Format-AuditorRate $totalIndexPersistentFastReject $totalFrames))) | Out-Null
$lines.Add(('| Index persistent fast hit/store MB | {0}/{1} | {2}/{3} | Bytes served from or inserted into the long-lived persistent index cache heap in Fast mode. |' -f (Format-AuditorDecimal $totalIndexPersistentFastHitMb), (Format-AuditorDecimal $totalIndexPersistentFastStoreMb), (Format-AuditorRate $totalIndexPersistentFastHitMb $totalFrames), (Format-AuditorRate $totalIndexPersistentFastStoreMb $totalFrames))) | Out-Null
$lines.Add(('| Present upload count CPU/GPU | {0}/{1} | {2}/{3} | Whether fallback present upload used the old CPU row conversion or the gated GPU-swap path. |' -f $totalPresentUploadCpu, $totalPresentUploadGpu, (Format-AuditorRate $totalPresentUploadCpu $totalFrames), (Format-AuditorRate $totalPresentUploadGpu $totalFrames))) | Out-Null
$lines.Add(('| Present upload MB CPU/GPU | {0}/{1} | {2}/{3} | Bytes attached to the present upload split. |' -f (Format-AuditorDecimal $totalPresentUploadCpuMb), (Format-AuditorDecimal $totalPresentUploadGpuMb), (Format-AuditorRate $totalPresentUploadCpuMb $totalFrames), (Format-AuditorRate $totalPresentUploadGpuMb $totalFrames))) | Out-Null
$lines.Add(('| Depth feedback prep keep/layout/write | {0}/{1}/{2} | {3}/{4}/{5} | Read-only feedback-layout preservation attempts before drawing. |' -f $totalDepthFeedbackPrepKeep, $totalDepthFeedbackPrepLayout, $totalDepthFeedbackPrepWrite, (Format-AuditorRate $totalDepthFeedbackPrepKeep $totalFrames), (Format-AuditorRate $totalDepthFeedbackPrepLayout $totalFrames), (Format-AuditorRate $totalDepthFeedbackPrepWrite $totalFrames))) | Out-Null
$lines.Add(('| Depth feedback end keep/layout/write/restore | {0}/{1}/{2}/{3} | {4}/{5}/{6}/{7} | End-of-draw feedback-layout gate results and fallback restores. |' -f $totalDepthFeedbackEndKeep, $totalDepthFeedbackEndLayout, $totalDepthFeedbackEndWrite, $totalDepthFeedbackEndRestore, (Format-AuditorRate $totalDepthFeedbackEndKeep $totalFrames), (Format-AuditorRate $totalDepthFeedbackEndLayout $totalFrames), (Format-AuditorRate $totalDepthFeedbackEndWrite $totalFrames), (Format-AuditorRate $totalDepthFeedbackEndRestore $totalFrames))) | Out-Null
$lines.Add(('| Blit-source fused resolve fast/verify/reject | {0}/{1}/{2} | {3}/{4}/{5} | Verify exercises the GPU candidate while keeping the normal visible frame. |' -f $totalBlitResolveFast, $totalBlitResolveVerify, $totalBlitResolveReject, (Format-AuditorRate $totalBlitResolveFast $totalFrames), (Format-AuditorRate $totalBlitResolveVerify $totalFrames), (Format-AuditorRate $totalBlitResolveReject $totalFrames))) | Out-Null
$lines.Add(('| Blit-source path storage_fast/sampled_fast/storage_verify/sampled_verify | {0}/{1}/{2}/{3} | {4}/{5}/{6}/{7} | Separates classic storage-image reads from sampled-MSAA reads for the fused resolve/blit path. |' -f $totalBlitResolveStorageFast, $totalBlitResolveSampledFast, $totalBlitResolveStorageVerify, $totalBlitResolveSampledVerify, (Format-AuditorRate $totalBlitResolveStorageFast $totalFrames), (Format-AuditorRate $totalBlitResolveSampledFast $totalFrames), (Format-AuditorRate $totalBlitResolveStorageVerify $totalFrames), (Format-AuditorRate $totalBlitResolveSampledVerify $totalFrames))) | Out-Null
$lines.Add(('| Blit-source reject reasons region/typeless/format/rt/dispatch | {0}/{1}/{2}/{3}/{4} | - | Classifies why candidate fused resolves did not dispatch. |' -f $totalBlitRejectRegion, $totalBlitRejectTypeless, $totalBlitRejectFormat, $totalBlitRejectRt, $totalBlitRejectDispatch)) | Out-Null
$lines.Add(('| Blit-source cache hit/miss/fill/fanout/reject | {0}/{1}/{2}/{3}/{4} | {5}/{6}/{7}/{8}/{9} | Verify/fast cached-source resolve activity; fanout still writes every destination. |' -f $totalBlitCacheHit, $totalBlitCacheMiss, $totalBlitCacheFill, $totalBlitCacheFanout, $totalBlitCacheReject, (Format-AuditorRate $totalBlitCacheHit $totalFrames), (Format-AuditorRate $totalBlitCacheMiss $totalFrames), (Format-AuditorRate $totalBlitCacheFill $totalFrames), (Format-AuditorRate $totalBlitCacheFanout $totalFrames), (Format-AuditorRate $totalBlitCacheReject $totalFrames))) | Out-Null
$lines.Add(('| Blit-source cache transfer-src fill/fanout | {0}/{1} | {2}/{3} | Cache image kept as a GPU transfer source for destination fanout instead of restoring it to shader-read between copies. |' -f $totalBlitCacheTransferSrcFill, $totalBlitCacheTransferSrcFanout, (Format-AuditorRate $totalBlitCacheTransferSrcFill $totalFrames), (Format-AuditorRate $totalBlitCacheTransferSrcFanout $totalFrames))) | Out-Null
$lines.Add(('| Blit-source cache RP breaks fill/src_layout/copy/hit_copy | {0}/{1}/{2}/{3} | {4}/{5}/{6}/{7} | Hidden tile-locality cost in the cached-source path: fill dispatches and transfer-copy fanouts that started while a render pass was open. |' -f $totalBlitCacheRpFill, $totalBlitCacheRpSrcLayout, $totalBlitCacheRpCopy, $totalBlitCacheRpHitCopy, (Format-AuditorRate $totalBlitCacheRpFill $totalFrames), (Format-AuditorRate $totalBlitCacheRpSrcLayout $totalFrames), (Format-AuditorRate $totalBlitCacheRpCopy $totalFrames), (Format-AuditorRate $totalBlitCacheRpHitCopy $totalFrames))) | Out-Null
$lines.Add(('| Blit-source cache deferred fill/src_layout | {0}/{1} | {2}/{3} | Defer mode fallback count: cache misses that were deliberately left on the normal visible path because filling the cache would have broken the open render pass. |' -f $totalBlitCacheDeferFill, $totalBlitCacheDeferSrcLayout, (Format-AuditorRate $totalBlitCacheDeferFill $totalFrames), (Format-AuditorRate $totalBlitCacheDeferSrcLayout $totalFrames))) | Out-Null

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
        "tile-locality-blit-cache" { "Blit-source cached resolve is running into render-pass/source-layout locality cost; prefer local/deferred source fill over fanout-copy tuning." }
        "dma-fence-bandwidth" { "Transfer fences/bytes dominate; narrow fence scope or keep producer/consumer GPU-resident." }
        "cpu-gpu-drain" { "Hard syncs drain GPU work; find caller before changing semantics." }
        "upload-detile-bandwidth" { "Texture prep/upload traffic is present; consider GPU-side conversion or caching." }
        "vertex-index-upload" { "Vertex or index prep/upload is visible; this is a candidate for GPU-resident cache or batched conversion experiments." }
        "buffer-barrier-bandwidth" { "Buffer barriers touch large ranges; label callsites before optimizing." }
        default { "No single RSX pressure bucket dominates this interval." }
    }
    $lines.Add(('| `{0}` | {1} | {2} | {3} |' -f $group.Name, $group.Count, $groupFrames, $reading)) | Out-Null
}

if ($resolveProfileRecords.Count -gt 0) {
    $profileGroups = @(
        $resolveProfileRecords |
            Group-Object -Property key, reason |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    key     = $first.key
                    reason  = $first.reason
                    count   = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    skips   = [UInt64](($_.Group | Measure-Object -Property skips -Sum).Sum)
                    dup     = [UInt64](($_.Group | Measure-Object -Property dup -Sum).Sum)
                    depth   = $first.depth
                    fmt     = $first.fmt
                    w       = $first.w
                    h       = $first.h
                    samples = $first.samples
                    sx      = $first.sx
                    sy      = $first.sy
                    pitch   = $first.pitch
                    base    = $first.base
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Resolve Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Count | Per 60 Frames | Skips | Dup Tags | Reason | Depth | Format | Size | Samples | Grid | Pitch | Base | Key |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | ---: | --- | ---: | --- | --- |") | Out-Null

    $rank = 1
    foreach ($profile in @($profileGroups | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | `{5}` | {6} | `{7}` | {8}x{9} | {10} | {11}x{12} | {13} | `{14}` | `{15}` |' -f
            $rank,
            $profile.count,
            (Format-AuditorRate $profile.count $totalFrames),
            $profile.skips,
            $profile.dup,
            (Format-ResolveReason $profile.reason),
            $profile.depth,
            $profile.fmt,
            $profile.w,
            $profile.h,
            $profile.samples,
            $profile.sx,
            $profile.sy,
            $profile.pitch,
            $profile.base,
            $profile.key)) | Out-Null
        $rank++
    }
}

if ($blitSourceProfileRecords.Count -gt 0) {
    $blitGroups = @(
        $blitSourceProfileRecords |
            Group-Object -Property key |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    key       = $first.key
                    count     = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    src       = $first.src
                    dst       = $first.dst
                    src_pitch = $first.src_pitch
                    dst_pitch = $first.dst_pitch
                    src_bpp   = $first.src_bpp
                    dst_bpp   = $first.dst_bpp
                    src_req   = $first.src_req
                    dst_req   = $first.dst_req
                    src_fmt   = $first.src_fmt
                    dst_fmt   = $first.dst_fmt
                    src_ctx   = $first.src_ctx
                    dst_ctx   = $first.dst_ctx
                    src_rect  = $first.src_rect
                    dst_rect  = $first.dst_rect
                    flags     = $first.flags
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Blit Source Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Count | Per 60 Frames | Src | Dst | Src/Dst Req | Src/Dst Rect | Pitch | BPP | Format | Ctx | Flags | Key |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($profile in @($blitGroups | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | `{3}` | `{4}` | {5} / {6} | `{7}` / `{8}` | {9}/{10} | {11}/{12} | `{13}` / `{14}` | {15}/{16} | `{17}` | `{18}` |' -f
            $rank,
            $profile.count,
            (Format-AuditorRate $profile.count $totalFrames),
            $profile.src,
            $profile.dst,
            $profile.src_req,
            $profile.dst_req,
            $profile.src_rect,
            $profile.dst_rect,
            $profile.src_pitch,
            $profile.dst_pitch,
            $profile.src_bpp,
            $profile.dst_bpp,
            $profile.src_fmt,
            $profile.dst_fmt,
            $profile.src_ctx,
            $profile.dst_ctx,
            (Format-BlitFlags $profile.flags),
            $profile.key)) | Out-Null
        $rank++
    }

    $sourceGroups = @(
        $blitSourceProfileRecords |
            Group-Object -Property src, src_req, src_rect, src_pitch, src_bpp, src_fmt, src_ctx, flags |
            ForEach-Object {
                $first = $_.Group[0]
                $destShapes = @(
                    $_.Group |
                        ForEach-Object { '{0}:{1}:{2}:{3}:{4}:{5}:{6}' -f $_.dst, $_.dst_req, $_.dst_rect, $_.dst_pitch, $_.dst_bpp, $_.dst_fmt, $_.dst_ctx } |
                        Sort-Object -Unique
                )
                $shapeKeys = @($_.Group | ForEach-Object { $_.key } | Sort-Object -Unique)
                $topDestRows = @(
                    $_.Group |
                        Group-Object -Property dst, dst_req, dst_rect, dst_pitch, dst_bpp, dst_fmt, dst_ctx |
                        ForEach-Object {
                            $dstFirst = $_.Group[0]
                            [pscustomobject]@{
                                count = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                                text  = ('{0} {1} {2}' -f $dstFirst.dst, $dstFirst.dst_req, $dstFirst.dst_rect)
                            }
                        } |
                        Sort-Object -Property count -Descending
                )
                [pscustomobject]@{
                    count      = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    src        = $first.src
                    src_req    = $first.src_req
                    src_rect   = $first.src_rect
                    src_pitch  = $first.src_pitch
                    src_bpp    = $first.src_bpp
                    src_fmt    = $first.src_fmt
                    src_ctx    = $first.src_ctx
                    flags      = $first.flags
                    dests      = [UInt64]$destShapes.Count
                    keys       = [UInt64]$shapeKeys.Count
                    top_dests  = (($topDestRows | Select-Object -First 3 | ForEach-Object { '{0}x {1}' -f $_.count, $_.text }) -join ", ")
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Blit Source Source-Shape Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add('Blit-source profile rows can be cumulative/slot aggregates; use this table to rank source shapes. Use `Resolve Coalescing Scout` for exact blit-source call totals.') | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Profile Count | Profile / 60 Frames | Dsts | Keys | Src | Src Req | Src Rect | Pitch/BPP | Format/Ctx | Flags | Top Dests | Reading |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($source in @($sourceGroups | Select-Object -First $Top)) {
        $reading = if ($source.dests -gt 1) {
            "Source fanout candidate; profile-rank only; pre-stage or read this source before the dependent render pass, then fan out locally."
        } else {
            "Single-destination source; profile-rank only; useful only if its source fill/layout transition can move before the dependent render pass."
        }
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} | `{5}` | {6} | `{7}` | {8}/{9} | `{10}`/{11} | `{12}` | {13} | {14} |' -f
            $rank,
            $source.count,
            (Format-AuditorRate $source.count $totalFrames),
            $source.dests,
            $source.keys,
            $source.src,
            $source.src_req,
            $source.src_rect,
            $source.src_pitch,
            $source.src_bpp,
            $source.src_fmt,
            $source.src_ctx,
            (Format-BlitFlags $source.flags),
            $source.top_dests,
            $reading)) | Out-Null
        $rank++
    }
}

if ($textureBarrierProfileRecords.Count -gt 0) {
    $textureGroups = @(
        $textureBarrierProfileRecords |
            Group-Object -Property key |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    key           = $first.key
                    count         = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    barriers      = [UInt64](($_.Group | Measure-Object -Property barriers -Sum).Sum)
                    skip_readonly = [UInt64](($_.Group | Measure-Object -Property skip_readonly -Sum).Sum)
                    skip_forced   = [UInt64](($_.Group | Measure-Object -Property skip_forced -Sum).Sum)
                    flags         = $first.flags
                    cur           = $first.cur
                    opt           = $first.opt
                    fmt           = $first.fmt
                    w             = $first.w
                    h             = $first.h
                    samples       = $first.samples
                    sx            = $first.sx
                    sy            = $first.sy
                    pitch         = $first.pitch
                    base          = $first.base
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Texture Barrier Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Count | Per 60 Frames | Barrier/Readonly/Forced | Format | Size | Samples | Grid | Pitch | Base | Layout Cur/Opt | Flags | Key |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | --- | --- | --- | ---: | --- | ---: | --- | --- | --- | --- |") | Out-Null

    $rank = 1
    foreach ($profile in @($textureGroups | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3}/{4}/{5} | `{6}` | {7}x{8} | {9} | {10}x{11} | {12} | `{13}` | {14}/{15} | `{16}` | `{17}` |' -f
            $rank,
            $profile.count,
            (Format-AuditorRate $profile.count $totalFrames),
            $profile.barriers,
            $profile.skip_readonly,
            $profile.skip_forced,
            $profile.fmt,
            $profile.w,
            $profile.h,
            $profile.samples,
            $profile.sx,
            $profile.sy,
            $profile.pitch,
            $profile.base,
            $profile.cur,
            $profile.opt,
            (Format-TextureBarrierFlags $profile.flags),
            $profile.key)) | Out-Null
        $rank++
    }
}

if ($vertexUploadProfileRecords.Count -gt 0) {
    $vertexGroups = @(
        $vertexUploadProfileRecords |
            Group-Object -Property key |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    key             = $first.key
                    count           = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    cache_hit       = [UInt64](($_.Group | Measure-Object -Property cache_hit -Sum).Sum)
                    cache_miss      = [UInt64](($_.Group | Measure-Object -Property cache_miss -Sum).Sum)
                    persistent_mb   = [double](($_.Group | Measure-Object -Property persistent_mb -Sum).Sum)
                    volatile_mb     = [double](($_.Group | Measure-Object -Property volatile_mb -Sum).Sum)
                    cmd             = $first.cmd
                    prim            = $first.prim
                    attr            = $first.attr
                    blocks          = $first.blocks
                    volatile_blocks = $first.volatile_blocks
                    regs            = $first.regs
                    stride          = $first.stride
                    base            = $first.base
                    vertices        = $first.vertices
                    persistent_size = $first.persistent_size
                    volatile_size   = $first.volatile_size
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Vertex Upload Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Count | Per 60 Frames | Hit/Miss | Persistent/Volatile MB | Cmd/Prim | Attr | Blocks/VBlocks/Regs | Stride | Sample Base | Sample Vertices | Sample Sizes | Shape Key |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | --- | ---: | --- | --- | --- | ---: | --- | ---: | --- | --- |") | Out-Null

    $rank = 1
    foreach ($profile in @($vertexGroups | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3}/{4} | {5}/{6} | {7}/{8} | `{9}` | {10}/{11}/{12} | {13} | `{14}` | {15} | {16}/{17} | `{18}` |' -f
            $rank,
            $profile.count,
            (Format-AuditorRate $profile.count $totalFrames),
            $profile.cache_hit,
            $profile.cache_miss,
            (Format-AuditorDecimal $profile.persistent_mb),
            (Format-AuditorDecimal $profile.volatile_mb),
            $profile.cmd,
            $profile.prim,
            $profile.attr,
            $profile.blocks,
            $profile.volatile_blocks,
            $profile.regs,
            $profile.stride,
            $profile.base,
            $profile.vertices,
            $profile.persistent_size,
            $profile.volatile_size,
            $profile.key)) | Out-Null
        $rank++
    }
}

if ($indexUploadProfileRecords.Count -gt 0) {
    $indexGroups = @(
        $indexUploadProfileRecords |
            Group-Object -Property key |
            ForEach-Object {
                $first = $_.Group[0]
                [pscustomobject]@{
                    key         = $first.key
                    count       = [UInt64](($_.Group | Measure-Object -Property count -Sum).Sum)
                    emulated    = [UInt64](($_.Group | Measure-Object -Property emulated -Sum).Sum)
                    restart     = [UInt64](($_.Group | Measure-Object -Property restart -Sum).Sum)
                    mb          = [double](($_.Group | Measure-Object -Property mb -Sum).Sum)
                    cmd         = $first.cmd
                    prim        = $first.prim
                    index_type  = $first.index_type
                    type_size   = $first.type_size
                    indices     = $first.indices
                    upload_size = $first.upload_size
                    immediate   = $first.immediate
                }
            } |
            Sort-Object -Property count -Descending
    )

    $lines.Add("") | Out-Null
    $lines.Add("## Index Upload Profile") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add("| Rank | Count | Per 60 Frames | Emulated/Restart | MB | Cmd/Prim | Type/Size | Sample Indices | Sample Upload Size | Immediate | Shape Key |") | Out-Null
    $lines.Add("| ---: | ---: | ---: | --- | ---: | --- | --- | ---: | ---: | ---: | --- |") | Out-Null

    $rank = 1
    foreach ($profile in @($indexGroups | Select-Object -First $Top)) {
        $lines.Add(('| {0} | {1} | {2} | {3}/{4} | {5} | {6}/{7} | {8}/{9} | {10} | {11} | {12} | `{13}` |' -f
            $rank,
            $profile.count,
            (Format-AuditorRate $profile.count $totalFrames),
            $profile.emulated,
            $profile.restart,
            (Format-AuditorDecimal $profile.mb),
            $profile.cmd,
            $profile.prim,
            $profile.index_type,
            $profile.type_size,
            $profile.indices,
            $profile.upload_size,
            $profile.immediate,
            $profile.key)) | Out-Null
        $rank++
    }
}

$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add('- `RSX on GPU` should mean fewer CPU/GPU drains, fewer render-pass breaks, and more GPU-resident texture/vertex/render-target traffic.') | Out-Null
$lines.Add('- High `rp_break` from texture or image barriers is an Adreno tile-locality target before compute offload.') | Out-Null
$lines.Add('- If `Source-local debt` says source-layout-bound, do not keep stacking cached-source fanout variants for speed; change the source-read/fill architecture or pivot back to SPU/codegen/HLE.') | Out-Null
$lines.Add('- High DMA fence bytes point first at `VKTextureCache` transfer/fence scope and producer-consumer residency, not a new compute shader.') | Out-Null
$lines.Add('- Pipeline creates are a warmup/stutter lane; do not mix them with steady-field FPS claims.') | Out-Null
$lines.Add('- Pair this summary with screenshot/video correctness for field, first battle, and menu before promoting any fast path.') | Out-Null

$lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
Write-Host "RSX auditor summary: $OutPath"
Write-Host "RSX auditor CSV: $CsvPath"
