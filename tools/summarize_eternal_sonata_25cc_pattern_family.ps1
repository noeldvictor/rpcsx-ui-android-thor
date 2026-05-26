[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [int]$MaxRuns = 12,

    [int]$Top = 24,

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

function To-UInt64Safe {
    param([object]$Value)

    if ($null -eq $Value) {
        return [UInt64]0
    }
    $text = "$Value".Trim().Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [UInt64]0
    }
    $number = [UInt64]0
    if ([UInt64]::TryParse($text, [ref]$number)) {
        return $number
    }
    return [UInt64]0
}

function Add-SetValue {
    param(
        [hashtable]$Set,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Set[$Value] = $true
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
    $files = @(
        "rpcs3.stderr.txt",
        "rpcs3.stdout.txt",
        "RPCS3.log",
        "windows-rpcs3-lab.txt"
    )

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
            return [pscustomobject]@{ HasFatal = $true; Source = $file; Line = $hit.Line.Trim() }
        }
    }

    return [pscustomobject]@{ HasFatal = $false; Source = ""; Line = "" }
}

function New-Bucket {
    param(
        [string]$Kind,
        [string]$Key,
        [string]$Ea,
        [string]$Pattern,
        [string]$MaxDmaSize,
        [string]$CmdCount,
        [string]$OffloadFit,
        [string]$DispatchRisk
    )

    return [pscustomobject]@{
        Kind = $Kind
        Key = $Key
        Ea = $Ea
        Pattern = $Pattern
        MaxDmaSize = $MaxDmaSize
        CmdCount = $CmdCount
        OffloadFit = $OffloadFit
        DispatchRisk = $DispatchRisk
        Records = [UInt64]0
        TotalBytes = [UInt64]0
        GetBytes = [UInt64]0
        PutBytes = [UInt64]0
        RsxBytes = [UInt64]0
        DurationUs = [UInt64]0
        MaxJobBytes = [UInt64]0
        Runs = @{}
        Patterns = @{}
        EAs = @{}
        CmdCounts = @{}
    }
}

function Update-Bucket {
    param(
        [object]$Bucket,
        [object]$Row,
        [string]$RunName
    )

    $total = To-UInt64Safe $Row.total_bytes
    $get = To-UInt64Safe $Row.get_bytes
    $put = To-UInt64Safe $Row.put_bytes
    $rsx = (To-UInt64Safe $Row.rsx_get_bytes) + (To-UInt64Safe $Row.rsx_put_bytes)
    $duration = To-UInt64Safe $Row.duration_us
    $maxDma = To-UInt64Safe $Row.max_dma_size

    $Bucket.Records++
    $Bucket.TotalBytes += $total
    $Bucket.GetBytes += $get
    $Bucket.PutBytes += $put
    $Bucket.RsxBytes += $rsx
    $Bucket.DurationUs += $duration
    if ($total -gt $Bucket.MaxJobBytes) {
        $Bucket.MaxJobBytes = $total
    }
    if ($maxDma -gt (To-UInt64Safe $Bucket.MaxDmaSize)) {
        $Bucket.MaxDmaSize = "$maxDma"
    }
    Add-SetValue -Set $Bucket.Runs -Value $RunName
    Add-SetValue -Set $Bucket.Patterns -Value $Row.pattern_sig
    Add-SetValue -Set $Bucket.EAs -Value $Row.max_dma_ea
    Add-SetValue -Set $Bucket.CmdCounts -Value $Row.cmd_count
}

function Get-Hint {
    param([object]$Cluster)

    $runsSeen = @($Cluster.Runs.Keys).Count
    if ($Cluster.RsxBytes -gt 0) {
        return "rsx-consumer-scout"
    }
    if ($Cluster.Ea -eq "0x9e4000" -and $runsSeen -ge 2 -and (To-UInt64Safe $Cluster.MaxDmaSize) -eq 16384) {
        return "broaden-25cc-verify-ea-family"
    }
    if ($runsSeen -ge 2 -and $Cluster.TotalBytes -ge 64MB) {
        return "verify-repeated-runtime-family"
    }
    return "profile-only"
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-25cc-pattern-family-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-25cc-pattern-family-latest.csv"
}

$runDirs = Get-ChildItem -LiteralPath $RunRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-gpu-probe-records.csv") -PathType Leaf } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $MaxRuns

$validRuns = New-Object System.Collections.Generic.List[object]
$excludedRuns = New-Object System.Collections.Generic.List[object]
$eaMap = @{}
$clusterMap = @{}

foreach ($run in $runDirs) {
    $visual = Read-VisualStatus -RunDir $run.FullName
    if ($visual.Status -ne "FIELD_LIKE_PRESENT") {
        continue
    }

    $fatal = Read-FatalStatus -RunDir $run.FullName
    if ($fatal.HasFatal) {
        $excludedRuns.Add([pscustomobject]@{ Name = $run.Name; Reason = "fatal-log"; Detail = ("{0}: {1}" -f $fatal.Source, $fatal.Line) }) | Out-Null
        continue
    }

    $validRuns.Add([pscustomobject]@{ Name = $run.Name; Path = $run.FullName; FirstField = $visual.FirstField; FirstFieldSeconds = $visual.FirstFieldSeconds }) | Out-Null
    $recordsPath = Join-Path $run.FullName "eternal-sonata-gpu-probe-records.csv"

    Import-Csv -LiteralPath $recordsPath | ForEach-Object {
        if ($_.title -ne "BLUS30161") {
            return
        }
        if ($_.image_sig -ne "0x958dfe208b686622") {
            return
        }
        if ($_.group_name -ne "CellSpursKernelGroup" -or $_.spu_name -ne "CellSpursKernel0") {
            return
        }
        if ($_.max_dma_pc -ne "0x25cc") {
            return
        }

        $ea = if ([string]::IsNullOrWhiteSpace($_.max_dma_ea)) { "unknown" } else { $_.max_dma_ea }
        $pattern = if ([string]::IsNullOrWhiteSpace($_.pattern_sig)) { "unknown" } else { $_.pattern_sig }
        $maxDmaSize = if ([string]::IsNullOrWhiteSpace($_.max_dma_size)) { "0" } else { $_.max_dma_size }
        $cmdCount = if ([string]::IsNullOrWhiteSpace($_.cmd_count)) { "0" } else { $_.cmd_count }
        $offloadFit = if ([string]::IsNullOrWhiteSpace($_.offload_fit)) { "unknown" } else { $_.offload_fit }
        $dispatchRisk = if ([string]::IsNullOrWhiteSpace($_.dispatch_risk)) { "unknown" } else { $_.dispatch_risk }

        if (-not $eaMap.ContainsKey($ea)) {
            $eaMap[$ea] = New-Bucket -Kind "ea" -Key $ea -Ea $ea -Pattern "*" -MaxDmaSize $maxDmaSize -CmdCount "*" -OffloadFit $offloadFit -DispatchRisk $dispatchRisk
        }
        Update-Bucket -Bucket $eaMap[$ea] -Row $_ -RunName $run.Name

        $clusterKey = "{0}|{1}|{2}|{3}|{4}|{5}" -f $ea, $pattern, $maxDmaSize, $cmdCount, $offloadFit, $dispatchRisk
        if (-not $clusterMap.ContainsKey($clusterKey)) {
            $clusterMap[$clusterKey] = New-Bucket -Kind "cluster" -Key $clusterKey -Ea $ea -Pattern $pattern -MaxDmaSize $maxDmaSize -CmdCount $cmdCount -OffloadFit $offloadFit -DispatchRisk $dispatchRisk
        }
        Update-Bucket -Bucket $clusterMap[$clusterKey] -Row $_ -RunName $run.Name
    }
}

$eaRows = @($eaMap.Values | ForEach-Object {
    [pscustomobject]@{
        Ea = $_.Ea
        Records = $_.Records
        RunsSeen = @($_.Runs.Keys).Count
        PatternCount = @($_.Patterns.Keys).Count
        CmdCountKinds = @($_.CmdCounts.Keys).Count
        TotalBytes = $_.TotalBytes
        Total = Format-Bytes $_.TotalBytes
        Get = Format-Bytes $_.GetBytes
        Put = Format-Bytes $_.PutBytes
        RsxBytes = $_.RsxBytes
        Rsx = Format-Bytes $_.RsxBytes
        DurationUs = $_.DurationUs
        DurationMs = ("{0:N3}" -f ([double]$_.DurationUs / 1000.0))
        MaxJob = Format-Bytes $_.MaxJobBytes
    }
}) | Sort-Object @{ Expression = "TotalBytes"; Descending = $true }, @{ Expression = "Records"; Descending = $true }

$total25ccBytes = [UInt64]0
$total25ccRsx = [UInt64]0
foreach ($row in $eaRows) {
    $total25ccBytes += $row.TotalBytes
    $total25ccRsx += $row.RsxBytes
}

$clusterRows = @($clusterMap.Values | ForEach-Object {
    $hint = Get-Hint -Cluster $_
    [pscustomobject]@{
        Hint = $hint
        Ea = $_.Ea
        Pattern = $_.Pattern
        MaxDmaSize = To-UInt64Safe $_.MaxDmaSize
        CmdCount = To-UInt64Safe $_.CmdCount
        OffloadFit = $_.OffloadFit
        DispatchRisk = $_.DispatchRisk
        Records = $_.Records
        RunsSeen = @($_.Runs.Keys).Count
        TotalBytes = $_.TotalBytes
        Total = Format-Bytes $_.TotalBytes
        ShareOf25cc = Format-Percent $_.TotalBytes $total25ccBytes
        Get = Format-Bytes $_.GetBytes
        Put = Format-Bytes $_.PutBytes
        RsxBytes = $_.RsxBytes
        Rsx = Format-Bytes $_.RsxBytes
        DurationUs = $_.DurationUs
        DurationMs = ("{0:N3}" -f ([double]$_.DurationUs / 1000.0))
        MaxJob = Format-Bytes $_.MaxJobBytes
    }
}) | Sort-Object @{ Expression = "TotalBytes"; Descending = $true }, @{ Expression = "RunsSeen"; Descending = $true }

$generated = (Get-Date).ToString("o")
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Eternal Sonata 0x25cc Pattern Family")
$md.Add("")
$md.Add(("- Generated: {0}" -f $generated))
$md.Add(("- Run root: {0}" -f (Resolve-Path -LiteralPath $RunRoot).Path))
$md.Add(("- Recent run dirs scanned: {0}" -f $runDirs.Count))
$md.Add(("- Valid field runs used: {0}" -f $validRuns.Count))
$md.Add(("- Field-like runs excluded by fatal logs: {0}" -f $excludedRuns.Count))
$md.Add('- Scope: title `BLUS30161`, image `0x958dfe208b686622`, `CellSpursKernelGroup` / `CellSpursKernel0`, PC `0x25cc`.')
$md.Add('- Classification: `analysis`, `spu-hle-25cc-pattern-family`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.')
$md.Add("")
$md.Add("## Reading")
$md.Add("")
if ($eaRows.Count -eq 0) {
    $md.Add('- No valid `0x25cc` rows were found in the selected valid field runs.')
} else {
    $topEa = $eaRows[0]
    $md.Add(('- Total selected `0x25cc` traffic: {0} over {1} EA bucket(s), with {2} RSX-local bytes.' -f (Format-Bytes $total25ccBytes), $eaRows.Count, (Format-Bytes $total25ccRsx)))
    $md.Add(('- Top EA bucket: `{0}`, {1} over {2} records, {3} pattern(s), {4} ms.' -f $topEa.Ea, $topEa.Total, $topEa.Records, $topEa.PatternCount, $topEa.DurationMs))
    if ($total25ccRsx -eq 0) {
        $md.Add('- RSX-local traffic is still `0 B`; this is CPU/SPU HLE/codegen target sizing, not GPU migration.')
    }
    $md.Add('- The broad target is the repeated `0x9e4000` EA family, not the earlier exact `eal=0xa1c000` redundant-copy skip.')
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
$md.Add("## EA Buckets")
$md.Add("")
$md.Add("| Rank | EA | Runs | Records | Patterns | Total | GET | PUT | Duration ms | RSX | Max Job |")
$md.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
$rank = 0
foreach ($row in ($eaRows | Select-Object -First $Top)) {
    $rank++
    $md.Add(('| {0} | `{1}` | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} |' -f $rank, $row.Ea, $row.RunsSeen, $row.Records, $row.PatternCount, $row.Total, $row.Get, $row.Put, $row.DurationMs, $row.Rsx, $row.MaxJob))
}
$md.Add("")
$md.Add("## Top Clusters")
$md.Add("")
$md.Add("| Rank | Hint | EA | Pattern | Runs | Records | Total | Share | Duration ms | Max DMA | Cmds | Fit | Risk |")
$md.Add("| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |")
$rank = 0
foreach ($row in ($clusterRows | Select-Object -First $Top)) {
    $rank++
    $md.Add(('| {0} | {1} | `{2}` | `{3}` | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} |' -f $rank, $row.Hint, $row.Ea, $row.Pattern, $row.RunsSeen, $row.Records, $row.Total, $row.ShareOf25cc, $row.DurationMs, $row.MaxDmaSize, $row.CmdCount, $row.OffloadFit, $row.DispatchRisk))
}
$md.Add("")
$md.Add("## Verifier Contract")
$md.Add("")
$md.Add('- Keep fast mode off. Start with verify-only logging for the `0x9e4000` EA family under the existing `BLUS30161` / image / group / SPU / PC gate.')
$md.Add("- Record command descriptors, source/destination hashes, touched GET/PUT byte ranges, and whether the stock path changes destination data before considering any HLE/codegen specialization.")
$md.Add("- Do not route this to Vulkan compute unless a future capture shows RSX-consumed data; current evidence is CPU/SPU codegen/HLE only.")
$md.Add("")
$md.Add("## Classification")
$md.Add("")
$md.Add('- `analysis`, `spu-hle-25cc-pattern-family`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.')

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $OutPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutPath, $md, [System.Text.UTF8Encoding]::new($false))

    $csvDir = Split-Path -Parent $CsvPath
    if ($csvDir -and -not (Test-Path -LiteralPath $csvDir -PathType Container)) {
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
    }
    $clusterRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$md | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
