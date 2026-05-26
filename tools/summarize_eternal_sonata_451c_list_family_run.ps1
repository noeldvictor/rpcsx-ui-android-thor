[CmdletBinding()]
param(
    [string]$RunDir = "",

    [string]$LogPath = "",

    [string]$OutPath = "",

    [string]$CsvPath = "",

    [string]$ClusterCsvPath = "",

    [int]$Top = 20,

    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
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
        [UInt64]$Part,
        [UInt64]$Whole
    )

    if ($Whole -eq 0) {
        return "0.00%"
    }
    return ("{0:N2}%" -f (100.0 * [double]$Part / [double]$Whole))
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
    if ($text.StartsWith("0x", [StringComparison]::OrdinalIgnoreCase)) {
        return [UInt64]0
    }
    $number = [UInt64]0
    if ([UInt64]::TryParse($text, [ref]$number)) {
        return $number
    }
    return [UInt64]0
}

function Resolve-RunPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $root = Get-RepoRoot
        return Join-Path $root "debug-captures\windows-lab"
    }
    return [System.IO.Path]::GetFullPath($Path)
}

function Resolve-LogPath {
    param(
        [string]$RunDir,
        [string]$LogPath
    )

    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        return [System.IO.Path]::GetFullPath($LogPath)
    }
    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        throw "RunDir or LogPath is required."
    }
    return Join-Path (Resolve-RunPath $RunDir) "RPCS3.log"
}

function Read-VisualStatus {
    param([string]$RunDir)

    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        return [pscustomobject]@{ Status = ""; FirstField = ""; FirstFieldSeconds = "" }
    }

    $summary = Join-Path (Resolve-RunPath $RunDir) "eternal-sonata-windows-visual-gate-summary.md"
    if (-not (Test-Path -LiteralPath $summary -PathType Leaf)) {
        return [pscustomobject]@{ Status = ""; FirstField = ""; FirstFieldSeconds = "" }
    }

    $text = Get-Content -LiteralPath $summary -Raw
    $status = ""
    $firstField = ""
    $seconds = ""
    if ($text -match '- Status:\s*`?([^`\r\n]+)`?') {
        $status = $matches[1].Trim()
    }
    if ($text -match '- First field-like screenshot:\s*`([^`]+)` at `?([0-9]+)s`?') {
        $firstField = $matches[1].Trim()
        $seconds = $matches[2].Trim()
    }

    return [pscustomobject]@{ Status = $status; FirstField = $firstField; FirstFieldSeconds = $seconds }
}

function Read-FatalStatus {
    param([string]$RunDir)

    if ([string]::IsNullOrWhiteSpace($RunDir)) {
        return [pscustomobject]@{ HasFatal = $false; Detail = "" }
    }

    $root = Resolve-RunPath $RunDir
    $patterns = @(
        "Access violation",
        "Unhandled exception",
        "SIGSEGV",
        "SIGBUS",
        "likely crashed",
        "Unknown STOP code",
        "Assertion",
        "assertion failed",
        "VK_ERROR_DEVICE_LOST",
        "device lost"
    )
    $files = @("rpcs3.stderr.txt", "rpcs3.stdout.txt", "windows-rpcs3-lab.txt")

    foreach ($file in $files) {
        $path = Join-Path $root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        $hit = Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue |
            Where-Object { $_.Line -notmatch "Show fatal error hints" } |
            Select-Object -First 1
        if ($hit) {
            return [pscustomobject]@{ HasFatal = $true; Detail = ("{0}: {1}" -f $file, $hit.Line.Trim()) }
        }
    }

    $log = Join-Path $root "RPCS3.log"
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $hit = Get-Content -LiteralPath $log -Tail 4000 |
            Select-String -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue |
            Where-Object { $_.Line -notmatch "Show fatal error hints" } |
            Select-Object -First 1
        if ($hit) {
            return [pscustomobject]@{ HasFatal = $true; Detail = ("RPCS3.log tail: {0}" -f $hit.Line.Trim()) }
        }
    }

    return [pscustomobject]@{ HasFatal = $false; Detail = "" }
}

function Parse-ProbeFields {
    param([string]$Line)

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $key = $match.Groups["key"].Value
        if ($match.Groups["quoted"].Success) {
            $fields[$key] = $match.Groups["quoted"].Value
        } else {
            $fields[$key] = $match.Groups["value"].Value
        }
    }
    return $fields
}

function Add-Sum {
    param(
        [hashtable]$Target,
        [hashtable]$Fields,
        [string]$Key
    )

    if (-not $Target.ContainsKey($Key)) {
        $Target[$Key] = [UInt64]0
    }
    if ($Fields.ContainsKey($Key)) {
        $Target[$Key] = [UInt64]($Target[$Key] + (To-UInt64Safe $Fields[$Key]))
    }
}

function Update-Max {
    param(
        [hashtable]$Target,
        [hashtable]$Fields,
        [string]$Key
    )

    $maxKey = "max_$Key"
    if (-not $Target.ContainsKey($maxKey)) {
        $Target[$maxKey] = [UInt64]0
    }
    if ($Fields.ContainsKey($Key)) {
        $value = To-UInt64Safe $Fields[$Key]
        if ($value -gt $Target[$maxKey]) {
            $Target[$maxKey] = $value
        }
    }
}

$resolvedLog = Resolve-LogPath -RunDir $RunDir -LogPath $LogPath
if (-not (Test-Path -LiteralPath $resolvedLog -PathType Leaf)) {
    throw "Log not found: $resolvedLog"
}

$resolvedRun = ""
if (-not [string]::IsNullOrWhiteSpace($RunDir)) {
    $resolvedRun = Resolve-RunPath $RunDir
}

if ([string]::IsNullOrWhiteSpace($OutPath)) {
    if (-not [string]::IsNullOrWhiteSpace($resolvedRun)) {
        $OutPath = Join-Path $resolvedRun "eternal-sonata-451c-list-family-quick-summary.md"
    } else {
        $OutPath = [System.IO.Path]::ChangeExtension($resolvedLog, ".451c-list-family-summary.md")
    }
}

if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    if (-not [string]::IsNullOrWhiteSpace($resolvedRun)) {
        $CsvPath = Join-Path $resolvedRun "eternal-sonata-451c-list-family-quick-rows.csv"
    } else {
        $CsvPath = [System.IO.Path]::ChangeExtension($resolvedLog, ".451c-list-family-rows.csv")
    }
}

if ([string]::IsNullOrWhiteSpace($ClusterCsvPath)) {
    if (-not [string]::IsNullOrWhiteSpace($resolvedRun)) {
        $ClusterCsvPath = Join-Path $resolvedRun "eternal-sonata-451c-list-family-quick-clusters.csv"
    } else {
        $ClusterCsvPath = [System.IO.Path]::ChangeExtension($resolvedLog, ".451c-list-family-clusters.csv")
    }
}

$listFamilyRows = [System.Collections.Generic.List[object]]::new()
$dynamic = @{ rows = [UInt64]0 }
$list = @{ rows = [UInt64]0 }
$desc = @{ rows = [UInt64]0 }
$gpu = @{ rows = [UInt64]0 }

$dynamicKeys = @("hits", "success", "fail", "bytes", "total_us", "pc25_hits", "pc25_us", "pc451c_hits", "pc451c_us", "get_hits", "put_hits", "list_hits", "atomic_hits")
$listKeys = @("calls", "success", "fail", "desc_bytes", "total_us", "pc451c_hits", "pc451c_us", "get_calls", "put_calls")
$descKeys = @("calls", "desc_bytes", "fetch_groups", "fast_groups", "fast_desc", "slow_desc", "nonzero_desc", "zero_desc", "stall_desc", "inline_get_desc", "inline_put_desc", "dma_desc", "shadow_groups", "shadow_single_groups", "shadow_multi_groups", "shadow_full_groups", "shadow_partial_groups", "shadow_desc", "shadow_bytes", "shadow_uniform_size_groups", "shadow_mixed_size_groups", "shadow_zero_rejects", "shadow_stall_rejects", "shadow_raw_rejects", "preserve_groups", "preserve_single_groups", "preserve_multi_groups", "preserve_full_groups", "preserve_partial_groups", "preserve_desc", "preserve_bytes", "preserve_zero_stops", "preserve_stall_stops", "preserve_raw_stops", "family1_calls", "family2_calls", "family3_calls", "family4_calls", "family5_calls", "family6_calls")
$gpuKeys = @("total_bytes", "get_bytes", "put_bytes", "list_get_bytes", "list_put_bytes", "rsx_get_bytes", "rsx_put_bytes", "cmd_count", "list_cmd_count")
$familyKeys = @("hits", "success", "fail", "tag1_size8_hits", "tag0_size8_hits", "tag0_size16_hits", "tag1_size16_hits", "tag1_size24_hits", "tag0_size24_hits", "desc_bytes", "total_us")
foreach ($key in $descKeys) { $desc[$key] = [UInt64]0 }

Select-String -LiteralPath $resolvedLog -Pattern @(
    "Eternal Sonata SPU HLE 451c list family verifier:",
    "Eternal Sonata SPU HLE 451c descriptor batch verifier:",
    "Eternal Sonata MFC dynamic probe:",
    "Eternal Sonata MFC list transfer probe:",
    "Eternal Sonata GPU candidate probe:"
) -SimpleMatch | ForEach-Object {
    $line = $_.Line
    $fields = Parse-ProbeFields $line

    if ($line.Contains("Eternal Sonata SPU HLE 451c list family verifier:")) {
        $row = [pscustomobject]@{
            hits             = To-UInt64Safe $fields["hits"]
            success          = To-UInt64Safe $fields["success"]
            fail             = To-UInt64Safe $fields["fail"]
            tag1_size8_hits  = To-UInt64Safe $fields["tag1_size8_hits"]
            tag0_size8_hits  = To-UInt64Safe $fields["tag0_size8_hits"]
            tag0_size16_hits = To-UInt64Safe $fields["tag0_size16_hits"]
            tag1_size16_hits = To-UInt64Safe $fields["tag1_size16_hits"]
            tag1_size24_hits = To-UInt64Safe $fields["tag1_size24_hits"]
            tag0_size24_hits = To-UInt64Safe $fields["tag0_size24_hits"]
            desc_bytes       = To-UInt64Safe $fields["desc_bytes"]
            total_us         = To-UInt64Safe $fields["total_us"]
            max_total_us     = To-UInt64Safe $fields["max_total_us"]
            last_family      = $fields["last_family"]
            last_pc          = $fields["last_pc"]
            last_cmd         = $fields["last_cmd"]
            last_tag         = $fields["last_tag"]
            last_size        = $fields["last_size"]
            last_lsa         = $fields["last_lsa"]
            last_eal         = $fields["last_eal"]
            group_name       = $fields["group_name"]
            spu_name         = $fields["spu_name"]
            image_sig        = $fields["image_sig"]
        }
        $listFamilyRows.Add($row) | Out-Null
    } elseif ($line.Contains("Eternal Sonata MFC dynamic probe:")) {
        $dynamic.rows = [UInt64]($dynamic.rows + 1)
        foreach ($key in $dynamicKeys) { Add-Sum -Target $dynamic -Fields $fields -Key $key }
        Update-Max -Target $dynamic -Fields $fields -Key "max_total_us"
    } elseif ($line.Contains("Eternal Sonata MFC list transfer probe:")) {
        $list.rows = [UInt64]($list.rows + 1)
        foreach ($key in $listKeys) { Add-Sum -Target $list -Fields $fields -Key $key }
        Update-Max -Target $list -Fields $fields -Key "max_total_us"
    } elseif ($line.Contains("Eternal Sonata SPU HLE 451c descriptor batch verifier:")) {
        $desc.rows = [UInt64]($desc.rows + 1)
        foreach ($key in $descKeys) { Add-Sum -Target $desc -Fields $fields -Key $key }
        Update-Max -Target $desc -Fields $fields -Key "shadow_max_desc"
        Update-Max -Target $desc -Fields $fields -Key "shadow_max_bytes"
        Update-Max -Target $desc -Fields $fields -Key "preserve_max_desc"
        Update-Max -Target $desc -Fields $fields -Key "preserve_max_bytes"
    } elseif ($line.Contains("Eternal Sonata GPU candidate probe:")) {
        $gpu.rows = [UInt64]($gpu.rows + 1)
        foreach ($key in $gpuKeys) { Add-Sum -Target $gpu -Fields $fields -Key $key }
    }
}

$familyTotals = [ordered]@{
    tag1_size8  = [UInt64](($listFamilyRows | Measure-Object -Property tag1_size8_hits -Sum).Sum)
    tag0_size8  = [UInt64](($listFamilyRows | Measure-Object -Property tag0_size8_hits -Sum).Sum)
    tag0_size16 = [UInt64](($listFamilyRows | Measure-Object -Property tag0_size16_hits -Sum).Sum)
    tag1_size16 = [UInt64](($listFamilyRows | Measure-Object -Property tag1_size16_hits -Sum).Sum)
    tag1_size24 = [UInt64](($listFamilyRows | Measure-Object -Property tag1_size24_hits -Sum).Sum)
    tag0_size24 = [UInt64](($listFamilyRows | Measure-Object -Property tag0_size24_hits -Sum).Sum)
}
$familyHits = [UInt64](($listFamilyRows | Measure-Object -Property hits -Sum).Sum)
$familySuccess = [UInt64](($listFamilyRows | Measure-Object -Property success -Sum).Sum)
$familyFail = [UInt64](($listFamilyRows | Measure-Object -Property fail -Sum).Sum)
$familyBytes = [UInt64](($listFamilyRows | Measure-Object -Property desc_bytes -Sum).Sum)
$familyTotalUs = [UInt64](($listFamilyRows | Measure-Object -Property total_us -Sum).Sum)
$familyMaxUs = [UInt64](($listFamilyRows | Measure-Object -Property max_total_us -Maximum).Maximum)
$avgUs = if ($familyHits -gt 0) { [double]$familyTotalUs / [double]$familyHits } else { 0.0 }

$clusterRows = @($listFamilyRows |
    Group-Object -Property last_tag,last_size,last_lsa,last_eal |
    ForEach-Object {
        $first = $_.Group | Select-Object -First 1
        $hits = [UInt64](($_.Group | Measure-Object -Property hits -Sum).Sum)
        $success = [UInt64](($_.Group | Measure-Object -Property success -Sum).Sum)
        $fail = [UInt64](($_.Group | Measure-Object -Property fail -Sum).Sum)
        $descBytes = [UInt64](($_.Group | Measure-Object -Property desc_bytes -Sum).Sum)
        $totalUs = [UInt64](($_.Group | Measure-Object -Property total_us -Sum).Sum)
        $maxUs = [UInt64](($_.Group | Measure-Object -Property max_total_us -Maximum).Maximum)
        $share = if ($familyHits -gt 0) { 100.0 * [double]$hits / [double]$familyHits } else { 0.0 }
        $avg = if ($hits -gt 0) { [double]$totalUs / [double]$hits } else { 0.0 }

        [pscustomobject]@{
            last_tag          = $first.last_tag
            last_size         = $first.last_size
            last_lsa          = $first.last_lsa
            last_eal          = $first.last_eal
            rows              = $_.Count
            hits              = $hits
            success           = $success
            fail              = $fail
            desc_bytes        = $descBytes
            total_us          = $totalUs
            max_total_us      = $maxUs
            avg_us_per_hit    = [math]::Round($avg, 3)
            share_percent     = [math]::Round($share, 3)
            last_pc           = $first.last_pc
            last_cmd          = $first.last_cmd
            group_name        = $first.group_name
            spu_name          = $first.spu_name
            image_sig         = $first.image_sig
        }
    } |
    Sort-Object -Property hits,total_us -Descending)

$visual = Read-VisualStatus -RunDir $RunDir
$fatal = Read-FatalStatus -RunDir $RunDir

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Eternal Sonata 0x451c List-Family Quick Summary") | Out-Null
$lines.Add("") | Out-Null
if (-not [string]::IsNullOrWhiteSpace($resolvedRun)) {
    $lines.Add(('- Run directory: `{0}`' -f $resolvedRun)) | Out-Null
}
$lines.Add(('- Log path: `{0}`' -f $resolvedLog)) | Out-Null
$lines.Add(('- Visual status: `{0}`' -f $visual.Status)) | Out-Null
if (-not [string]::IsNullOrWhiteSpace($visual.FirstField)) {
    $lines.Add(('- First field-like screenshot: `{0}` at `{1}s`' -f $visual.FirstField, $visual.FirstFieldSeconds)) | Out-Null
}
$fatalText = if ($fatal.HasFatal) { "hit: $($fatal.Detail)" } else { "clean" }
$lines.Add(("- Fatal scan: $fatalText")) | Out-Null
$lines.Add("- Purpose: focused streaming parser for 0x451c list-family runs when the full GPU probe summarizer is too slow for a heartbeat.") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Totals") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- List-family rows: $($listFamilyRows.Count)") | Out-Null
$lines.Add("- List-family hits: $familyHits") | Out-Null
$lines.Add("- Success / fail: $familySuccess / $familyFail") | Out-Null
$lines.Add("- Descriptor bytes: $(Format-Bytes $familyBytes)") | Out-Null
$avgUsText = "{0:N3}" -f $avgUs
$familyMsText = [math]::Round($familyTotalUs / 1000.0, 3)
$lines.Add("- Timing: $familyMsText ms total, $avgUsText us/hit average, $familyMaxUs us max row") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Family | Hits | Share |") | Out-Null
$lines.Add("| --- | ---: | ---: |") | Out-Null
foreach ($item in $familyTotals.GetEnumerator() | Sort-Object -Property Value -Descending) {
    $lines.Add(('| `{0}` | {1} | {2} |' -f $item.Key, $item.Value, (Format-Percent $item.Value $familyHits))) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Related MFC Traffic") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Dynamic MFC rows/hits: $($dynamic.rows) / $($dynamic.hits)") | Out-Null
$lines.Add("- Dynamic MFC bytes/timing: $(Format-Bytes $dynamic.bytes) / $([math]::Round([double]$dynamic.total_us / 1000.0, 3)) ms") | Out-Null
$pc25Ms = [math]::Round([double]$dynamic.pc25_us / 1000.0, 3)
$pc451cMs = [math]::Round([double]$dynamic.pc451c_us / 1000.0, 3)
$lines.Add(('- Dynamic PC split: `0x25cc={0} / {1} ms`, `0x451c={2} / {3} ms`' -f $dynamic.pc25_hits, $pc25Ms, $dynamic.pc451c_hits, $pc451cMs)) | Out-Null
$lines.Add("- Dynamic command split: get=$($dynamic.get_hits), put=$($dynamic.put_hits), list=$($dynamic.list_hits), atomic=$($dynamic.atomic_hits)") | Out-Null
$lines.Add("- List-transfer calls/timing: $($list.calls) / $([math]::Round([double]$list.total_us / 1000.0, 3)) ms") | Out-Null
$lines.Add("- List-transfer descriptor bytes: $(Format-Bytes $list.desc_bytes)") | Out-Null
$lines.Add("- Descriptor-batch rows/calls: $($desc.rows) / $($desc.calls)") | Out-Null
$lines.Add("- Descriptor-batch fetch groups: $($desc.fetch_groups), fast groups: $($desc.fast_groups), fast descriptors: $($desc.fast_desc), slow descriptors: $($desc.slow_desc)") | Out-Null
$lines.Add("- Descriptor-batch item split: nonzero=$($desc.nonzero_desc), zero=$($desc.zero_desc), stall=$($desc.stall_desc), inline_get=$($desc.inline_get_desc), inline_put=$($desc.inline_put_desc), dma=$($desc.dma_desc)") | Out-Null
$lines.Add("- Descriptor-batch shadow groups: total=$($desc.shadow_groups), single=$($desc.shadow_single_groups), multi=$($desc.shadow_multi_groups), full=$($desc.shadow_full_groups), partial=$($desc.shadow_partial_groups)") | Out-Null
$lines.Add("- Descriptor-batch shadow descriptors: desc=$($desc.shadow_desc), bytes=$(Format-Bytes $desc.shadow_bytes), uniform_groups=$($desc.shadow_uniform_size_groups), mixed_groups=$($desc.shadow_mixed_size_groups), max_desc=$($desc.max_shadow_max_desc), max_bytes=$(Format-Bytes $desc.max_shadow_max_bytes)") | Out-Null
$lines.Add("- Descriptor-batch shadow rejects: zero=$($desc.shadow_zero_rejects), stall=$($desc.shadow_stall_rejects), raw=$($desc.shadow_raw_rejects)") | Out-Null
$lines.Add("- Descriptor-batch preserve-order groups: total=$($desc.preserve_groups), single=$($desc.preserve_single_groups), multi=$($desc.preserve_multi_groups), full=$($desc.preserve_full_groups), partial=$($desc.preserve_partial_groups)") | Out-Null
$lines.Add("- Descriptor-batch preserve-order descriptors: desc=$($desc.preserve_desc), bytes=$(Format-Bytes $desc.preserve_bytes), max_desc=$($desc.max_preserve_max_desc), max_bytes=$(Format-Bytes $desc.max_preserve_max_bytes)") | Out-Null
$lines.Add("- Descriptor-batch preserve-order stops: zero=$($desc.preserve_zero_stops), stall=$($desc.preserve_stall_stops), raw=$($desc.preserve_raw_stops)") | Out-Null
$lines.Add("- Descriptor-batch family calls: f1=$($desc.family1_calls), f2=$($desc.family2_calls), f3=$($desc.family3_calls), f4=$($desc.family4_calls), f5=$($desc.family5_calls), f6=$($desc.family6_calls)") | Out-Null
$lines.Add("- GPU candidate rows/total DMA: $($gpu.rows) / $(Format-Bytes $gpu.total_bytes)") | Out-Null
$lines.Add("- Direct RSX-local bytes: $(Format-Bytes ([UInt64]($gpu.rsx_get_bytes + $gpu.rsx_put_bytes)))") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Top Rows") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Hits | Total us | Max us | Last tag | Last size | Last LSA | Last EAL | Group | SPU |") | Out-Null
$lines.Add("| ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |") | Out-Null
$rank = 1
foreach ($row in @($listFamilyRows | Sort-Object -Property hits,total_us -Descending | Select-Object -First $Top)) {
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | `{6}` | `{7}` | `{8}` | `{9}` |' -f
        $rank,
        $row.hits,
        $row.total_us,
        $row.max_total_us,
        $row.last_tag,
        $row.last_size,
        $row.last_lsa,
        $row.last_eal,
        $row.group_name,
        $row.spu_name)) | Out-Null
    $rank++
}
$lines.Add("") | Out-Null
$lines.Add("## Hot Descriptor Clusters") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Tag | Size | LSA | EAL | Rows | Hits | Share | Total us | Avg us/hit | Max us |") | Out-Null
$lines.Add("| ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |") | Out-Null
$rank = 1
foreach ($cluster in @($clusterRows | Select-Object -First $Top)) {
    $lines.Add(('| {0} | {1} | {2} | `{3}` | `{4}` | {5} | {6} | {7:N2}% | {8} | {9:N3} | {10} |' -f
        $rank,
        $cluster.last_tag,
        $cluster.last_size,
        $cluster.last_lsa,
        $cluster.last_eal,
        $cluster.rows,
        $cluster.hits,
        $cluster.share_percent,
        $cluster.total_us,
        $cluster.avg_us_per_hit,
        $cluster.max_total_us)) | Out-Null
    $rank++
}
$lines.Add("") | Out-Null
$lines.Add("## Slowest Descriptor Clusters") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Rank | Tag | Size | LSA | EAL | Rows | Hits | Total us | Avg us/hit | Max us |") | Out-Null
$lines.Add("| ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |") | Out-Null
$rank = 1
foreach ($cluster in @($clusterRows | Sort-Object -Property total_us,hits -Descending | Select-Object -First $Top)) {
    $lines.Add(('| {0} | {1} | {2} | `{3}` | `{4}` | {5} | {6} | {7} | {8:N3} | {9} |' -f
        $rank,
        $cluster.last_tag,
        $cluster.last_size,
        $cluster.last_lsa,
        $cluster.last_eal,
        $cluster.rows,
        $cluster.hits,
        $cluster.total_us,
        $cluster.avg_us_per_hit,
        $cluster.max_total_us)) | Out-Null
    $rank++
}
$lines.Add("") | Out-Null
$lines.Add("## Predicate Seeds") | Out-Null
$lines.Add("") | Out-Null
foreach ($cluster in @($clusterRows | Select-Object -First ([math]::Min(6, $Top)))) {
    $lines.Add(('- `pc={0} cmd={1} tag={2} size={3} lsa={4} eal={5}` -> hits={6}, rows={7}, total_us={8}' -f
        $cluster.last_pc,
        $cluster.last_cmd,
        $cluster.last_tag,
        $cluster.last_size,
        $cluster.last_lsa,
        $cluster.last_eal,
        $cluster.hits,
        $cluster.rows,
        $cluster.total_us)) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
$lines.Add('- This is target sizing for `0x451c` list-control and descriptor batching. It does not enable fast mode or skip stock DMA/list behavior.') | Out-Null
$lines.Add('- Direct RSX-local bytes remain `0`, so broad SPU-to-Vulkan compute stays parked unless a later scout proves RSX-consumed data.') | Out-Null
$lines.Add("- Treat a clean visual/fatal result as HLE/codegen evidence only; speed, GPU migration credit, and the 200% gate still need matched field/menu/battle proof.") | Out-Null

if (-not $NoWrite) {
    $outParent = Split-Path -Parent $OutPath
    if (-not [string]::IsNullOrWhiteSpace($outParent)) {
        New-Item -ItemType Directory -Force -Path $outParent | Out-Null
    }
    $csvParent = Split-Path -Parent $CsvPath
    if (-not [string]::IsNullOrWhiteSpace($csvParent)) {
        New-Item -ItemType Directory -Force -Path $csvParent | Out-Null
    }
    $clusterCsvParent = Split-Path -Parent $ClusterCsvPath
    if (-not [string]::IsNullOrWhiteSpace($clusterCsvParent)) {
        New-Item -ItemType Directory -Force -Path $clusterCsvParent | Out-Null
    }
    $lines | Set-Content -LiteralPath $OutPath -Encoding UTF8
    $listFamilyRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    $clusterRows | Export-Csv -LiteralPath $ClusterCsvPath -NoTypeInformation -Encoding UTF8
}

$lines -join [Environment]::NewLine
