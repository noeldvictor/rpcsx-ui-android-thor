[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [int]$MaxRuns = 20,

    [int]$Top = 20,

    [string]$OutPath = "",

    [string]$CsvPath = "",

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

function Format-PercentDouble {
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

function To-HexUInt64 {
    param([object]$Value)

    if ($null -eq $Value) {
        return [UInt64]0
    }
    $text = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [UInt64]0
    }
    if ($text.StartsWith("0x", [StringComparison]::OrdinalIgnoreCase)) {
        return [Convert]::ToUInt64($text.Substring(2), 16)
    }
    return To-UInt64Safe $text
}

function Format-HexUInt64 {
    param([UInt64]$Value)

    return ("0x{0:x}" -f $Value)
}

function Add-SetValue {
    param(
        [hashtable]$Set,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }
    if (-not $Set.ContainsKey($Value)) {
        $Set[$Value] = $true
    }
}

function Get-LaneHookPoint {
    param([string]$Lane)

    switch ($Lane) {
        "small-list-control" { return "SPUThread.cpp: MFC_Cmd -> process_mfc_cmd list branch; SPULLVMRecompiler.cpp dynamic MFC_Cmd fallback" }
        "list-descriptor-batch" { return "SPUThread.cpp: do_list_transfer descriptor walker and six-element GET inliner" }
        "large-preserve-copy" { return "SPUThread.cpp: do_dma_transfer preserve-copy backend" }
        "exact-get-preserve-copy" { return "SPUThread.cpp: process_mfc_cmd -> do_dma_transfer exact 0x451c GET" }
        default { return "SPUThread.cpp: generic process_mfc_cmd / do_dma_transfer preserve-order path" }
    }
}

function Get-LaneNextExperiment {
    param([string]$Lane)

    switch ($Lane) {
        "small-list-control" { return "Verify a title/image/PC-gated dynamic-command recognizer for hot 0x46 descriptors before fast mode." }
        "list-descriptor-batch" { return "Add descriptor-batch counters around do_list_transfer and prove whether decode/control overhead can be reduced." }
        "large-preserve-copy" { return "Preserve DMA semantics and test vectorized/copy-backend specialization, not skip." }
        "exact-get-preserve-copy" { return "Specialize exact GET codegen/copy dispatch while preserving destination writes; copy elision is blocked." }
        default { return "Keep generic preserve-order MFC instrumentation until a narrower repeated shape appears." }
    }
}
function Read-VisualStatus {
    param([string]$RunDir)

    $summary = Join-Path $RunDir "eternal-sonata-windows-visual-gate-summary.md"
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
    $files = @("rpcs3.stderr.txt", "rpcs3.stdout.txt", "RPCS3.log", "windows-rpcs3-lab.txt")

    foreach ($file in $files) {
        $path = Join-Path $RunDir $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        if ($file -eq "RPCS3.log") {
            $hit = Get-Content -LiteralPath $path -Tail 4000 -ErrorAction SilentlyContinue |
                Select-String -Pattern $patterns -SimpleMatch |
                Where-Object { $_.Line -notmatch "Show fatal error hints" } |
                Select-Object -First 1
        } else {
            $hit = Select-String -LiteralPath $path -Pattern $patterns -SimpleMatch -List -ErrorAction SilentlyContinue |
                Where-Object { $_.Line -notmatch "Show fatal error hints" } |
                Select-Object -First 1
        }
        if ($hit) {
            return [pscustomobject]@{ HasFatal = $true; Detail = ("{0}: {1}" -f $file, $hit.Line.Trim()) }
        }
    }

    return [pscustomobject]@{ HasFatal = $false; Detail = "" }
}

function Update-DescriptorAggregate {
    param(
        [hashtable]$Map,
        [object]$Row,
        [string]$Kind,
        [UInt64]$Hits,
        [UInt64]$Bytes,
        [UInt64]$TotalUs,
        [UInt64]$MaxUs,
        [string]$RunName
    )

    $cmd = "$($Row.last_cmd)"
    $tag = "$($Row.last_tag)"
    $size = "$($Row.last_size)"
    $lsa = "$($Row.last_lsa)"
    $group = "$($Row.group_name)"
    $spu = "$($Row.spu_name)"
    $key = "$Kind|$group|$spu|$cmd|$tag|$size|$lsa"

    if (-not $Map.ContainsKey($key)) {
        $Map[$key] = [pscustomobject]@{
            Kind = $Kind
            Group = $group
            Spu = $spu
            Cmd = $cmd
            Tag = $tag
            Size = $size
            Lsa = $lsa
            Records = 0
            Hits = [UInt64]0
            Bytes = [UInt64]0
            TotalUs = [UInt64]0
            MaxUs = [UInt64]0
            EalMin = [UInt64]::MaxValue
            EalMax = [UInt64]0
            Eals = @{}
            Runs = @{}
        }
    }

    $item = $Map[$key]
    $item.Records++
    $item.Hits += $Hits
    $item.Bytes += $Bytes
    $item.TotalUs += $TotalUs
    if ($MaxUs -gt $item.MaxUs) {
        $item.MaxUs = $MaxUs
    }

    $eal = To-HexUInt64 $Row.last_eal
    if ($eal -lt $item.EalMin) {
        $item.EalMin = $eal
    }
    if ($eal -gt $item.EalMax) {
        $item.EalMax = $eal
    }
    Add-SetValue -Set $item.Eals -Value "$($Row.last_eal)"
    Add-SetValue -Set $item.Runs -Value $RunName
}

function Update-ShadowAggregate {
    param(
        [hashtable]$Map,
        [object]$Row,
        [string]$RunName
    )

    $cmd = "$($Row.last_cmd)"
    $tag = "$($Row.last_tag)"
    $size = "$($Row.last_size)"
    $lsa = "$($Row.last_lsa)"
    $group = "$($Row.group_name)"
    $spu = "$($Row.spu_name)"
    $key = "shadow-verify|$group|$spu|$cmd|$tag|$size|$lsa"

    if (-not $Map.ContainsKey($key)) {
        $Map[$key] = [pscustomobject]@{
            Kind = "shadow-verify"
            Group = $group
            Spu = $spu
            Cmd = $cmd
            Tag = $tag
            Size = $size
            Lsa = $lsa
            Records = 0
            Hits = [UInt64]0
            Bytes = [UInt64]0
            OutputMatch = [UInt64]0
            OutputMismatch = [UInt64]0
            DstChanged = [UInt64]0
            DstUnchanged = [UInt64]0
            SkipHits = [UInt64]0
            SkipBytes = [UInt64]0
            SkipMisses = [UInt64]0
            EalMin = [UInt64]::MaxValue
            EalMax = [UInt64]0
            Eals = @{}
            Runs = @{}
        }
    }

    $item = $Map[$key]
    $item.Records++
    $item.Hits += To-UInt64Safe $Row.hits
    $item.Bytes += To-UInt64Safe $Row.bytes
    $item.OutputMatch += To-UInt64Safe $Row.output_match
    $item.OutputMismatch += To-UInt64Safe $Row.output_mismatch
    $item.DstChanged += To-UInt64Safe $Row.dst_changed
    $item.DstUnchanged += To-UInt64Safe $Row.dst_unchanged
    $item.SkipHits += To-UInt64Safe $Row.skip_hits
    $item.SkipBytes += To-UInt64Safe $Row.skip_bytes
    $item.SkipMisses += To-UInt64Safe $Row.skip_misses

    $eal = To-HexUInt64 $Row.last_eal
    if ($eal -lt $item.EalMin) {
        $item.EalMin = $eal
    }
    if ($eal -gt $item.EalMax) {
        $item.EalMax = $eal
    }
    Add-SetValue -Set $item.Eals -Value "$($Row.last_eal)"
    Add-SetValue -Set $item.Runs -Value $RunName
}

if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path (Get-RepoRoot) "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-451c-contract-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-451c-contract-latest.csv"
}

if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    throw "Run root not found: $RunRoot"
}

$runDirs = Get-ChildItem -LiteralPath $RunRoot -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $MaxRuns

$validRuns = New-Object System.Collections.Generic.List[object]
$skippedRuns = New-Object System.Collections.Generic.List[object]
$descriptorMap = @{}
$shadowMap = @{}

foreach ($run in $runDirs) {
    $visual = Read-VisualStatus -RunDir $run.FullName
    if ($visual.Status -ne "FIELD_LIKE_PRESENT") {
        continue
    }
    $fatal = Read-FatalStatus -RunDir $run.FullName
    if ($fatal.HasFatal) {
        $skippedRuns.Add([pscustomobject]@{ Name = $run.Name; Reason = "fatal-log-hit"; Detail = $fatal.Detail }) | Out-Null
        continue
    }

    $validRuns.Add([pscustomobject]@{
        Name = $run.Name
        Path = $run.FullName
        FirstField = $visual.FirstField
        FirstFieldSeconds = $visual.FirstFieldSeconds
    }) | Out-Null

    $dynamicCsv = Join-Path $run.FullName "eternal-sonata-mfc-dynamic-profile.csv"
    if (Test-Path -LiteralPath $dynamicCsv -PathType Leaf) {
        Import-Csv -LiteralPath $dynamicCsv | ForEach-Object {
            if ($_.title -ne "BLUS30161" -or $_.image_sig -ne "0x958dfe208b686622") { return }
            if ($_.group_name -ne "TCX_CellSpursKernelGroup" -or $_.spu_name -ne "TCX_CellSpursKernel0") { return }
            $pc451cHits = To-UInt64Safe $_.pc451c_hits
            if ($pc451cHits -eq 0 -or "$($_.last_pc)" -ne "0x451c") { return }
            Update-DescriptorAggregate -Map $descriptorMap -Row $_ -Kind "dynamic-mfc" -Hits $pc451cHits -Bytes (To-UInt64Safe $_.bytes) -TotalUs (To-UInt64Safe $_.pc451c_us) -MaxUs (To-UInt64Safe $_.max_total_us) -RunName $run.Name
        }
    }

    $listCsv = Join-Path $run.FullName "eternal-sonata-mfc-list-transfer-profile.csv"
    if (Test-Path -LiteralPath $listCsv -PathType Leaf) {
        Import-Csv -LiteralPath $listCsv | ForEach-Object {
            if ($_.title -ne "BLUS30161" -or $_.image_sig -ne "0x958dfe208b686622") { return }
            if ($_.group_name -ne "TCX_CellSpursKernelGroup" -or $_.spu_name -ne "TCX_CellSpursKernel0") { return }
            $pc451cHits = To-UInt64Safe $_.pc451c_hits
            if ($pc451cHits -eq 0 -or "$($_.last_pc)" -ne "0x451c") { return }
            Update-DescriptorAggregate -Map $descriptorMap -Row $_ -Kind "list-transfer" -Hits $pc451cHits -Bytes (To-UInt64Safe $_.desc_bytes) -TotalUs (To-UInt64Safe $_.pc451c_us) -MaxUs (To-UInt64Safe $_.max_total_us) -RunName $run.Name
        }
    }

    $shadowCsv = Join-Path $run.FullName "eternal-sonata-spu-hle-shadow-profile.csv"
    if (Test-Path -LiteralPath $shadowCsv -PathType Leaf) {
        Import-Csv -LiteralPath $shadowCsv | ForEach-Object {
            if ($_.title -ne "BLUS30161" -or $_.image_sig -ne "0x958dfe208b686622") { return }
            if ($_.group_name -ne "TCX_CellSpursKernelGroup" -or $_.spu_name -ne "TCX_CellSpursKernel0") { return }
            if ("$($_.last_pc)" -ne "0x451c") { return }
            Update-ShadowAggregate -Map $shadowMap -Row $_ -RunName $run.Name
        }
    }
}

$descriptors = @($descriptorMap.Values | ForEach-Object {
    $ealMin = if ($_.EalMin -eq [UInt64]::MaxValue) { [UInt64]0 } else { $_.EalMin }
    $avgUsPerHit = if ($_.Hits -gt 0) { [double]$_.TotalUs / [double]$_.Hits } else { 0.0 }
    $avgBytesPerHit = if ($_.Hits -gt 0) { [double]$_.Bytes / [double]$_.Hits } else { 0.0 }
    $lane = if ($_.Kind -eq "list-transfer") {
        "list-descriptor-batch"
    } elseif ($_.Cmd -eq "0x40" -and $_.Tag -eq "31" -and $_.Size -eq "256" -and $_.Lsa -eq "0x4a00") {
        "exact-get-preserve-copy"
    } elseif ($_.Cmd -eq "0x46") {
        "small-list-control"
    } elseif ((To-UInt64Safe $_.Size) -ge 1024) {
        "large-preserve-copy"
    } else {
        "preserve-order-mfc"
    }

    [pscustomobject]@{
        Kind = $_.Kind
        Group = $_.Group
        Spu = $_.Spu
        Cmd = $_.Cmd
        Tag = $_.Tag
        Size = $_.Size
        Lsa = $_.Lsa
        Records = $_.Records
        Hits = $_.Hits
        BytesRaw = $_.Bytes
        Bytes = Format-Bytes $_.Bytes
        TotalMsRaw = [double]$_.TotalUs / 1000.0
        TotalMs = ("{0:N3}" -f ([double]$_.TotalUs / 1000.0))
        AvgUsPerHitRaw = $avgUsPerHit
        AvgUsPerHit = ("{0:N3}" -f $avgUsPerHit)
        AvgBytesPerHitRaw = $avgBytesPerHit
        AvgBytesPerHit = ("{0:N1}" -f $avgBytesPerHit)
        MaxUs = $_.MaxUs
        RunsSeen = @($_.Runs.Keys).Count
        EalCount = @($_.Eals.Keys).Count
        EalMin = Format-HexUInt64 $ealMin
        EalMax = Format-HexUInt64 $_.EalMax
        CandidateLane = $lane
    }
}) | Sort-Object @{ Expression = "Hits"; Descending = $true }, @{ Expression = "BytesRaw"; Descending = $true }

$dynamicDescriptors = @($descriptors | Where-Object { $_.Kind -eq "dynamic-mfc" })
$listDescriptors = @($descriptors | Where-Object { $_.Kind -eq "list-transfer" })
$runtimeCostDescriptors = @($descriptors | Sort-Object @{ Expression = "TotalMsRaw"; Descending = $true }, @{ Expression = "Hits"; Descending = $true })
$dynamicRecognizerSeeds = @($runtimeCostDescriptors | Where-Object { $_.CandidateLane -eq "small-list-control" -and $_.Cmd -eq "0x46" })
$dynamicPredicateSeeds = @($dynamicRecognizerSeeds | Select-Object -First 2)
$dynamic46Descriptors = @($dynamicDescriptors | Where-Object { $_.Cmd -eq "0x46" } | Sort-Object @{ Expression = "TotalMsRaw"; Descending = $true }, @{ Expression = "Hits"; Descending = $true })
$dynamic46Hits = [UInt64](($dynamic46Descriptors | Measure-Object -Property Hits -Sum).Sum)
$dynamic46Bytes = [UInt64](($dynamic46Descriptors | Measure-Object -Property BytesRaw -Sum).Sum)
$dynamic46TotalMsRaw = [double](($dynamic46Descriptors | Measure-Object -Property TotalMsRaw -Sum).Sum)
$dynamic46PredicateHits = [UInt64](($dynamicPredicateSeeds | Measure-Object -Property Hits -Sum).Sum)
$dynamic46PredicateBytes = [UInt64](($dynamicPredicateSeeds | Measure-Object -Property BytesRaw -Sum).Sum)
$dynamic46PredicateMsRaw = [double](($dynamicPredicateSeeds | Measure-Object -Property TotalMsRaw -Sum).Sum)
$dynamic46CoverageMarks = @(2, 4, 8, 12, 16, 24, 32, 64, 128)
$dynamic46CoverageSteps = @(
    $dynamic46CoverageMarks |
        Where-Object { $_ -le $dynamic46Descriptors.Count } |
        ForEach-Object {
            $count = [int]$_
            $items = @($dynamic46Descriptors | Select-Object -First $count)
            $hits = [UInt64](($items | Measure-Object -Property Hits -Sum).Sum)
            $bytes = [UInt64](($items | Measure-Object -Property BytesRaw -Sum).Sum)
            $totalMs = [double](($items | Measure-Object -Property TotalMsRaw -Sum).Sum)

            [pscustomobject]@{
                Descriptors = $count
                Hits = $hits
                HitShare = Format-Percent $hits $dynamic46Hits
                BytesRaw = $bytes
                Bytes = Format-Bytes $bytes
                TotalMsRaw = $totalMs
                TotalMs = ("{0:N3}" -f $totalMs)
                TimeShare = Format-PercentDouble $totalMs $dynamic46TotalMsRaw
            }
        }
)
$dynamic46FamilyBuckets = @(
    $dynamic46Descriptors |
        Group-Object -Property Tag,Size |
        ForEach-Object {
            $items = @($_.Group)
            $first = $items[0]
            $hits = [UInt64](($items | Measure-Object -Property Hits -Sum).Sum)
            $bytes = [UInt64](($items | Measure-Object -Property BytesRaw -Sum).Sum)
            $totalMs = [double](($items | Measure-Object -Property TotalMsRaw -Sum).Sum)
            $avgUsPerHit = if ($hits -gt 0) { ($totalMs * 1000.0) / [double]$hits } else { 0.0 }

            [pscustomobject]@{
                Tag = $first.Tag
                Size = $first.Size
                Descriptors = $items.Count
                Hits = $hits
                HitShare = Format-Percent $hits $dynamic46Hits
                BytesRaw = $bytes
                Bytes = Format-Bytes $bytes
                TotalMsRaw = $totalMs
                TotalMs = ("{0:N3}" -f $totalMs)
                TimeShare = Format-PercentDouble $totalMs $dynamic46TotalMsRaw
                AvgUsPerHit = ("{0:N3}" -f $avgUsPerHit)
            }
        } |
        Sort-Object @{ Expression = "TotalMsRaw"; Descending = $true }, @{ Expression = "Hits"; Descending = $true }
)
$totalDynamicHits = [UInt64](($dynamicDescriptors | Measure-Object -Property Hits -Sum).Sum)
$totalListHits = [UInt64](($listDescriptors | Measure-Object -Property Hits -Sum).Sum)
$totalDynamicBytes = [UInt64](($dynamicDescriptors | Measure-Object -Property BytesRaw -Sum).Sum)
$totalListDescBytes = [UInt64](($listDescriptors | Measure-Object -Property BytesRaw -Sum).Sum)
$laneTotals = @($descriptors | Group-Object -Property CandidateLane | ForEach-Object {
    $items = @($_.Group)
    $hits = [UInt64](($items | Measure-Object -Property Hits -Sum).Sum)
    $bytes = [UInt64](($items | Measure-Object -Property BytesRaw -Sum).Sum)
    $totalMs = [double](($items | Measure-Object -Property TotalMsRaw -Sum).Sum)
    $avgUsPerHit = if ($hits -gt 0) { ($totalMs * 1000.0) / [double]$hits } else { 0.0 }
    $kinds = @($items | Select-Object -ExpandProperty Kind -Unique) -join "+"

    [pscustomobject]@{
        Lane = $_.Name
        Kinds = $kinds
        Descriptors = $items.Count
        Hits = $hits
        BytesRaw = $bytes
        Bytes = Format-Bytes $bytes
        TotalMsRaw = $totalMs
        TotalMs = ("{0:N3}" -f $totalMs)
        AvgUsPerHit = ("{0:N3}" -f $avgUsPerHit)
        HookPoint = Get-LaneHookPoint $_.Name
        NextExperiment = Get-LaneNextExperiment $_.Name
    }
}) | Sort-Object @{ Expression = "TotalMsRaw"; Descending = $true }, @{ Expression = "Hits"; Descending = $true }
$shadowDescriptors = @($shadowMap.Values | ForEach-Object {
    $ealMin = if ($_.EalMin -eq [UInt64]::MaxValue) { [UInt64]0 } else { $_.EalMin }
    $matchRate = if ($_.Hits -gt 0) { 100.0 * [double]$_.OutputMatch / [double]$_.Hits } else { 0.0 }
    $mismatchRate = if ($_.Hits -gt 0) { 100.0 * [double]$_.OutputMismatch / [double]$_.Hits } else { 0.0 }
    $dstChangedRate = if ($_.Hits -gt 0) { 100.0 * [double]$_.DstChanged / [double]$_.Hits } else { 0.0 }
    $verdict = if ($_.Hits -eq 0) {
        "no-shadow-hits"
    } elseif ($_.OutputMismatch -eq 0 -and $_.DstChanged -eq 0) {
        "possible-skip-candidate"
    } elseif ($_.OutputMismatch -eq 0) {
        "preserve-dma-semantics"
    } else {
        "not-skip-safe"
    }

    [pscustomobject]@{
        Kind = $_.Kind
        Group = $_.Group
        Spu = $_.Spu
        Cmd = $_.Cmd
        Tag = $_.Tag
        Size = $_.Size
        Lsa = $_.Lsa
        Records = $_.Records
        Hits = $_.Hits
        BytesRaw = $_.Bytes
        Bytes = Format-Bytes $_.Bytes
        OutputMatch = $_.OutputMatch
        OutputMismatch = $_.OutputMismatch
        MatchRate = ("{0:N2}%" -f $matchRate)
        MismatchRate = ("{0:N2}%" -f $mismatchRate)
        DstChanged = $_.DstChanged
        DstUnchanged = $_.DstUnchanged
        DstChangedRate = ("{0:N2}%" -f $dstChangedRate)
        SkipHits = $_.SkipHits
        SkipBytesRaw = $_.SkipBytes
        SkipBytes = Format-Bytes $_.SkipBytes
        SkipMisses = $_.SkipMisses
        RunsSeen = @($_.Runs.Keys).Count
        EalCount = @($_.Eals.Keys).Count
        EalMin = Format-HexUInt64 $ealMin
        EalMax = Format-HexUInt64 $_.EalMax
        Verdict = $verdict
    }
}) | Sort-Object @{ Expression = "Hits"; Descending = $true }, @{ Expression = "BytesRaw"; Descending = $true }
$totalShadowHits = [UInt64](($shadowDescriptors | Measure-Object -Property Hits -Sum).Sum)
$totalShadowBytes = [UInt64](($shadowDescriptors | Measure-Object -Property BytesRaw -Sum).Sum)
$totalShadowOutputMismatch = [UInt64](($shadowDescriptors | Measure-Object -Property OutputMismatch -Sum).Sum)
$totalShadowDstChanged = [UInt64](($shadowDescriptors | Measure-Object -Property DstChanged -Sum).Sum)
$totalShadowSkipHits = [UInt64](($shadowDescriptors | Measure-Object -Property SkipHits -Sum).Sum)

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Eternal Sonata 0x451c MFC Contract Scout")
$md.Add("")
$md.Add(("- Generated: {0}" -f (Get-Date).ToString("o")))
$md.Add(("- Run root: {0}" -f (Resolve-Path -LiteralPath $RunRoot).Path))
$md.Add(("- Recent run dirs scanned: {0}" -f $runDirs.Count))
$md.Add(("- Valid fatal-clean field runs used: {0}" -f $validRuns.Count))
$md.Add(("- Fatal-clean field runs skipped: {0}" -f $skippedRuns.Count))
$md.Add("")
$md.Add("## Reading")
$md.Add("")
if ($descriptors.Count -eq 0) {
    $md.Add("- No 0x451c descriptor rows were found in valid field captures. Re-run verify telemetry on a clean field route before writing an HLE contract.")
} else {
    $md.Add(("- Dynamic MFC 0x451c hits: {0}, bytes observed: {1}." -f $totalDynamicHits, (Format-Bytes $totalDynamicBytes)))
    $md.Add(("- List-transfer 0x451c calls: {0}, descriptor bytes observed: {1}." -f $totalListHits, (Format-Bytes $totalListDescBytes)))
    if (@($runtimeCostDescriptors).Count -gt 0) {
        $topCost = @($runtimeCostDescriptors)[0]
        $md.Add(("- Top runtime-cost descriptor: {0} {1}/{2}/{3}/{4}, {5} ms, {6} hits, lane `{7}`." -f $topCost.Kind, $topCost.Cmd, $topCost.Tag, $topCost.Size, $topCost.Lsa, $topCost.TotalMs, $topCost.Hits, $topCost.CandidateLane))
    }
    if (@($laneTotals).Count -gt 0) {
        $topLane = @($laneTotals)[0]
        $md.Add(("- Top runtime-cost lane: `{0}`, {1} ms, {2} hits, {3}, {4} descriptors." -f $topLane.Lane, $topLane.TotalMs, $topLane.Hits, $topLane.Bytes, $topLane.Descriptors))
    }
    if (@($dynamic46Descriptors).Count -gt 0) {
        $md.Add(("- Broad dynamic 0x46 list-control lane: {0} hits, {1}, {2} ms, {3} descriptors; current top-two predicate coverage: {4} hits ({5}), {6} ms ({7})." -f $dynamic46Hits, (Format-Bytes $dynamic46Bytes), ("{0:N3}" -f $dynamic46TotalMsRaw), $dynamic46Descriptors.Count, $dynamic46PredicateHits, (Format-Percent $dynamic46PredicateHits $dynamic46Hits), ("{0:N3}" -f $dynamic46PredicateMsRaw), (Format-Percent ([UInt64]([Math]::Round($dynamic46PredicateMsRaw * 1000.0))) ([UInt64]([Math]::Round($dynamic46TotalMsRaw * 1000.0))))))
        if (@($dynamic46FamilyBuckets).Count -gt 0) {
            $topFamily = @($dynamic46FamilyBuckets)[0]
            $md.Add(("- Broadest dynamic 0x46 tag/size family: tag={0}, size={1}, {2} descriptors, {3} hits ({4}), {5} ms ({6})." -f $topFamily.Tag, $topFamily.Size, $topFamily.Descriptors, $topFamily.Hits, $topFamily.HitShare, $topFamily.TotalMs, $topFamily.TimeShare))
        }
    }
    if (@($shadowDescriptors).Count -gt 0) {
        $md.Add(("- Shadow verifier 0x451c hits: {0}, bytes shadowed: {1}, output mismatches: {2}, destination changes: {3}, skip hits: {4}." -f $totalShadowHits, (Format-Bytes $totalShadowBytes), $totalShadowOutputMismatch, $totalShadowDstChanged, $totalShadowSkipHits))
    }
    $md.Add("- The top descriptors are MFC command/size/tag/LSA shapes for a verify-only HLE/codegen contract. They are not speed proof and not GPU migration credit.")
    if ($totalShadowOutputMismatch -gt 0 -or $totalShadowDstChanged -gt 0) {
        $md.Add("- Shadow verifier evidence blocks copy-elision for the exact 0x451c bucket. Future fast paths must preserve DMA ordering/data movement or reduce descriptor/codegen overhead.")
    }
}
$md.Add("")
$md.Add("## Valid Runs")
$md.Add("")
if ($validRuns.Count -eq 0) {
    $md.Add("- None.")
} else {
    foreach ($run in $validRuns) {
        $md.Add(("- {0}: first field {1} at {2}s" -f $run.Name, $run.FirstField, $run.FirstFieldSeconds))
    }
}
$md.Add("")
$md.Add("## Top Dynamic MFC Descriptors")
$md.Add("")
$md.Add("| Rank | Cmd | Tag | Size | LSA | Runs | Records | Hits | Bytes | Total ms | Avg us/hit | Max us | Lane | EAs | EA min | EA max |")
$md.Add("| ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |")
$rank = 0
foreach ($item in ($dynamicDescriptors | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | `{12}` | {13} | {14} | {15} |" -f $rank, $item.Cmd, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Records, $item.Hits, $item.Bytes, $item.TotalMs, $item.AvgUsPerHit, $item.MaxUs, $item.CandidateLane, $item.EalCount, $item.EalMin, $item.EalMax))
}
$md.Add("")
$md.Add("## Top List-Transfer Descriptors")
$md.Add("")
$md.Add("| Rank | Cmd | Tag | Size | LSA | Runs | Records | Calls | Desc bytes | Total ms | Avg us/call | Max us | Lane | EAs | EA min | EA max |")
$md.Add("| ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | --- | --- |")
$rank = 0
foreach ($item in ($listDescriptors | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | `{12}` | {13} | {14} | {15} |" -f $rank, $item.Cmd, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Records, $item.Hits, $item.Bytes, $item.TotalMs, $item.AvgUsPerHit, $item.MaxUs, $item.CandidateLane, $item.EalCount, $item.EalMin, $item.EalMax))
}
$md.Add("")
$md.Add("## Top Runtime-Cost Descriptors")
$md.Add("")
$md.Add("| Rank | Kind | Cmd | Tag | Size | LSA | Runs | Hits | Bytes | Total ms | Avg us/hit | Max us | Lane | EA min | EA max |")
$md.Add("| ---: | --- | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |")
$rank = 0
foreach ($item in ($runtimeCostDescriptors | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | `{12}` | {13} | {14} |" -f $rank, $item.Kind, $item.Cmd, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Hits, $item.Bytes, $item.TotalMs, $item.AvgUsPerHit, $item.MaxUs, $item.CandidateLane, $item.EalMin, $item.EalMax))
}
$md.Add("")
$md.Add("## Runtime-Cost Lane Totals")
$md.Add("")
$md.Add("| Rank | Lane | Kinds | Descriptors | Hits | Bytes | Total ms | Avg us/hit |")
$md.Add("| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: |")
$rank = 0
foreach ($item in ($laneTotals | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} |" -f $rank, $item.Lane, $item.Kinds, $item.Descriptors, $item.Hits, $item.Bytes, $item.TotalMs, $item.AvgUsPerHit))
}
$md.Add("")
$md.Add("## Implementation Hook Shortlist")
$md.Add("")
$md.Add("| Rank | Lane | Total ms | Hook point | Next verifier |")
$md.Add("| ---: | --- | ---: | --- | --- |")
$rank = 0
foreach ($item in ($laneTotals | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | `{1}` | {2} | {3} | {4} |" -f $rank, $item.Lane, $item.TotalMs, $item.HookPoint, $item.NextExperiment))
}
$md.Add("")
$md.Add("## Dynamic Command Recognizer Seeds")
$md.Add("")
$md.Add("| Rank | Cmd | Tag | Size | LSA | Runs | Hits | Bytes | Total ms | Avg us/hit | Max us | EA min | EA max | Verifier seed |")
$md.Add("| ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |")
$rank = 0
foreach ($item in ($dynamicRecognizerSeeds | Select-Object -First $Top)) {
    $rank++
    $seed = "title=BLUS30161,image=0x958dfe208b686622,pc=0x451c,cmd=$($item.Cmd),tag=$($item.Tag),size=$($item.Size),lsa=$($item.Lsa),ea=$($item.EalMin)..$($item.EalMax)"
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | `{13}` |" -f $rank, $item.Cmd, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Hits, $item.Bytes, $item.TotalMs, $item.AvgUsPerHit, $item.MaxUs, $item.EalMin, $item.EalMax, $seed))
}
$md.Add("")
$md.Add("## Dynamic 0x46 Family Coverage")
$md.Add("")
if ($dynamic46Descriptors.Count -eq 0) {
    $md.Add("- No dynamic `0x46` list-control descriptors were found.")
} else {
    $md.Add(("- Dynamic ``0x46`` descriptors: {0}; hits: {1}; bytes: {2}; total time: {3:N3} ms." -f $dynamic46Descriptors.Count, $dynamic46Hits, (Format-Bytes $dynamic46Bytes), $dynamic46TotalMsRaw))
    $md.Add(("- Current top-two predicate coverage: {0} hits ({1}), {2}, {3:N3} ms ({4})." -f $dynamic46PredicateHits, (Format-Percent $dynamic46PredicateHits $dynamic46Hits), (Format-Bytes $dynamic46PredicateBytes), $dynamic46PredicateMsRaw, (Format-Percent ([UInt64]([Math]::Round($dynamic46PredicateMsRaw * 1000.0))) ([UInt64]([Math]::Round($dynamic46TotalMsRaw * 1000.0))))))
    $md.Add('- Broad-family reading: if coverage is low, do not make those two seeds fast. First add a verify-only family recognizer for more `0x46` descriptors or move down into `do_list_transfer` descriptor batching.')
    $md.Add("")
    $md.Add("| Rank | Tag | Size | LSA | Runs | Hits | Share | Bytes | Total ms | Avg us/hit | EA min | EA max |")
    $md.Add("| ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |")
    $rank = 0
    foreach ($item in ($dynamic46Descriptors | Select-Object -First $Top)) {
        $rank++
        $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} |" -f $rank, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Hits, (Format-Percent $item.Hits $dynamic46Hits), $item.Bytes, $item.TotalMs, $item.AvgUsPerHit, $item.EalMin, $item.EalMax))
    }
    $md.Add("")
    $md.Add("### Dynamic 0x46 Coverage Ladder")
    $md.Add("")
    $md.Add("| Top descriptors | Hits | Hit share | Bytes | Total ms | Time share |")
    $md.Add("| ---: | ---: | ---: | ---: | ---: | ---: |")
    foreach ($step in $dynamic46CoverageSteps) {
        $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $step.Descriptors, $step.Hits, $step.HitShare, $step.Bytes, $step.TotalMs, $step.TimeShare))
    }
    $md.Add("")
    $md.Add("### Dynamic 0x46 Tag/Size Families")
    $md.Add("")
    $md.Add("| Rank | Tag | Size | Descriptors | Hits | Hit share | Bytes | Total ms | Time share | Avg us/hit |")
    $md.Add("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    $rank = 0
    foreach ($family in $dynamic46FamilyBuckets) {
        $rank++
        $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $rank, $family.Tag, $family.Size, $family.Descriptors, $family.Hits, $family.HitShare, $family.Bytes, $family.TotalMs, $family.TimeShare, $family.AvgUsPerHit))
    }
}
$md.Add("")
$md.Add("## C++ Verifier Predicate Sketch")
$md.Add("")
if ($dynamicPredicateSeeds.Count -eq 0) {
    $md.Add('- No dynamic `0x46` seeds were found, so no predicate sketch was emitted.')
} else {
    $md.Add('- Sketch only, not drop-in code: wire this into the existing title/image/PC gate, keep it `Verify` only, log counters, and return to the stock MFC/list path.')
    $md.Add('- Do not enable `Fast` from this predicate. The current proof is descriptor-recognition prep, not copy elision and not GPU migration.')
    $md.Add("")
    $md.Add('```cpp')
    $md.Add("static bool is_es_451c_dynamic_list_seed(const spu_thread& spu, const spu_mfc_cmd& cmd)")
    $md.Add("{")
    $md.Add("    // Reuse the existing BLUS30161 + image 0x958dfe208b686622 + PC 0x451c gate.")
    $md.Add("    if (!es_title_image_pc_451c_gate(spu))")
    $md.Add("    {")
    $md.Add("        return false;")
    $md.Add("    }")
    $md.Add("")
    $md.Add("    if (g_cfg.core.spu_accurate_dma || g_cfg.core.mfc_transfers_shuffling)")
    $md.Add("    {")
    $md.Add("        return false;")
    $md.Add("    }")
    $md.Add("")
    $md.Add("    if (cmd.cmd != MFC_GETLF_CMD || cmd.eah != 0)")
    $md.Add("    {")
    $md.Add("        return false;")
    $md.Add("    }")
    $md.Add("")
    $md.Add("    const u32 lsa = cmd.lsa & (SPU_LS_SIZE - 1);")
    $md.Add("    const u32 eal = cmd.eal;")
    $md.Add("")
    foreach ($item in $dynamicPredicateSeeds) {
        $md.Add(("    if (cmd.tag == {0} && cmd.size == {1} && lsa == {2} && eal >= {3} && eal <= {4})" -f $item.Tag, $item.Size, $item.Lsa, $item.EalMin, $item.EalMax))
        $md.Add("    {")
        $md.Add("        return true;")
        $md.Add("    }")
        $md.Add("")
    }
    $md.Add("    return false;")
    $md.Add("}")
    $md.Add('```')
}
$md.Add("")
$md.Add("## Top Shadow Safety Buckets")
$md.Add("")
$md.Add("| Rank | Cmd | Tag | Size | LSA | Runs | Records | Hits | Bytes | Match | Mismatch | Dst changed | Skip hits | EAs | EA min | EA max | Verdict |")
$md.Add("| ---: | --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |")
$rank = 0
foreach ($item in ($shadowDescriptors | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} ({10}) | {11} ({12}) | {13} ({14}) | {15} | {16} | {17} | {18} | {19} |" -f $rank, $item.Cmd, $item.Tag, $item.Size, $item.Lsa, $item.RunsSeen, $item.Records, $item.Hits, $item.Bytes, $item.OutputMatch, $item.MatchRate, $item.OutputMismatch, $item.MismatchRate, $item.DstChanged, $item.DstChangedRate, $item.SkipHits, $item.EalCount, $item.EalMin, $item.EalMax, $item.Verdict))
}
$md.Add("")
$md.Add("## Verifier Plan")
$md.Add("")
$md.Add('- Gate on title `BLUS30161`, image `0x958dfe208b686622`, group `TCX_CellSpursKernelGroup`, SPU `TCX_CellSpursKernel0`, and PC `0x451c`.')
$md.Add('- Start by shadowing descriptor classes, not outputs: command, tag, size, LSA, EA range, dynamic/list kind, and stock success/failure.')
$md.Add('- A fast path is blocked until the verifier proves stable output or a codegen specialization can reduce descriptor overhead without changing DMA order.')
$md.Add('- Vulkan compute remains parked because the valid field set still has `0 B` RSX-local bytes for this bucket.')
$md.Add("")
$md.Add("## Classification")
$md.Add("")
$md.Add("- analysis, not windows-micro-win, not gpu-migration-credit, not a 200% gate candidate.")

if (-not $NoWrite) {
    [System.IO.File]::WriteAllLines($OutPath, $md, [System.Text.UTF8Encoding]::new($false))
    $csvRows = @(
        $descriptors | Select-Object Kind,Group,Spu,Cmd,Tag,Size,Lsa,Records,Hits,BytesRaw,Bytes,TotalMs,AvgUsPerHit,AvgBytesPerHit,MaxUs,RunsSeen,EalCount,EalMin,EalMax,CandidateLane,@{Name="OutputMatch";Expression={""}},@{Name="OutputMismatch";Expression={""}},@{Name="MatchRate";Expression={""}},@{Name="DstChanged";Expression={""}},@{Name="DstUnchanged";Expression={""}},@{Name="DstChangedRate";Expression={""}},@{Name="SkipHits";Expression={""}},@{Name="SkipBytesRaw";Expression={""}},@{Name="SkipBytes";Expression={""}},@{Name="SkipMisses";Expression={""}},@{Name="Verdict";Expression={""}}
        $shadowDescriptors | Select-Object Kind,Group,Spu,Cmd,Tag,Size,Lsa,Records,Hits,BytesRaw,Bytes,@{Name="TotalMs";Expression={""}},@{Name="AvgUsPerHit";Expression={""}},@{Name="AvgBytesPerHit";Expression={""}},@{Name="MaxUs";Expression={""}},RunsSeen,EalCount,EalMin,EalMax,@{Name="CandidateLane";Expression={""}},OutputMatch,OutputMismatch,MatchRate,DstChanged,DstUnchanged,DstChangedRate,SkipHits,SkipBytesRaw,SkipBytes,SkipMisses,Verdict
    )
    $csvRows |
        Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$md | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
