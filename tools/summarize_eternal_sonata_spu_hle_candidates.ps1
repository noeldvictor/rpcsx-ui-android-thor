[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [int]$MaxRuns = 12,

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

function Read-VisualStatus {
    param([string]$RunDir)

    $summary = Join-Path $RunDir "eternal-sonata-windows-visual-gate-summary.md"
    if (-not (Test-Path -LiteralPath $summary -PathType Leaf)) {
        return [pscustomobject]@{
            Status = ""
            FirstField = ""
            FirstFieldSeconds = ""
        }
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
    return [pscustomobject]@{
        Status = $status
        FirstField = $firstField
        FirstFieldSeconds = $seconds
    }
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
            return [pscustomobject]@{
                HasFatal = $true
                Source = $file
                Line = $hit.Line.Trim()
            }
        }
    }

    return [pscustomobject]@{
        HasFatal = $false
        Source = ""
        Line = ""
    }
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

function Add-SetValue {
    param(
        [hashtable]$Set,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Set[$Value] = $true
    }
}

function Get-PcFileToken {
    param([string]$Pc)

    $hex = "$Pc".Trim().ToLowerInvariant()
    if ($hex.StartsWith("0x")) {
        $hex = $hex.Substring(2)
    }
    return $hex.PadLeft(5, "0")
}

function Get-DisasmSnippet {
    param(
        [string]$RunDir,
        [string]$Pc,
        [string]$Group,
        [int]$ContextLines = 20
    )

    $spuDir = Join-Path $RunDir "spu-images"
    if (-not (Test-Path -LiteralPath $spuDir -PathType Container)) {
        return [pscustomobject]@{
            Path = ""
            Lines = @()
        }
    }

    $pcToken = Get-PcFileToken -Pc $Pc
    $matches = @(Get-ChildItem -LiteralPath $spuDir -File -Filter "*pc-$pcToken*.disasm.txt" |
        Where-Object { $_.Name -like "*group-$Group-*" } |
        Sort-Object Name)
    if ($matches.Count -eq 0) {
        $matches = @(Get-ChildItem -LiteralPath $spuDir -File -Filter "*pc-$pcToken*.disasm.txt" | Sort-Object Name)
    }
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{
            Path = ""
            Lines = @()
        }
    }

    $path = $matches[0].FullName
    $lines = @(Get-Content -LiteralPath $path)
    $focusLine = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ("^\s*0*{0}:" -f (("$Pc").ToLowerInvariant() -replace "^0x", ""))) {
            $focusLine = $i
            break
        }
    }
    if ($focusLine -lt 0) {
        $focusLine = [Math]::Min(8, [Math]::Max(0, $lines.Count - 1))
    }

    $start = [Math]::Max(0, $focusLine - 8)
    $end = [Math]::Min($lines.Count - 1, $focusLine + $ContextLines)
    $snippet = @()
    if ($lines.Count -gt 0) {
        $snippet = $lines[$start..$end]
    }

    return [pscustomobject]@{
        Path = $path
        Lines = $snippet
    }
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-spu-hle-candidates-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-spu-hle-candidates-latest.csv"
}

$runDirs = Get-ChildItem -LiteralPath $RunRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-gpu-probe-records.csv") -PathType Leaf } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $MaxRuns

$validRuns = New-Object System.Collections.Generic.List[object]
$excludedRuns = New-Object System.Collections.Generic.List[object]
$candidateMap = @{}
$patternMap = @{}

foreach ($run in $runDirs) {
    $visual = Read-VisualStatus -RunDir $run.FullName
    if ($visual.Status -ne "FIELD_LIKE_PRESENT") {
        continue
    }
    $fatal = Read-FatalStatus -RunDir $run.FullName
    if ($fatal.HasFatal) {
        $excludedRuns.Add([pscustomobject]@{
            Name = $run.Name
            Reason = "fatal-log-hit"
            Detail = ("{0}: {1}" -f $fatal.Source, $fatal.Line)
        }) | Out-Null
        continue
    }

    $recordsPath = Join-Path $run.FullName "eternal-sonata-gpu-probe-records.csv"
    $validRuns.Add([pscustomobject]@{
        Name = $run.Name
        Path = $run.FullName
        FirstField = $visual.FirstField
        FirstFieldSeconds = $visual.FirstFieldSeconds
    }) | Out-Null

    Import-Csv -LiteralPath $recordsPath | ForEach-Object {
        if ($_.title -ne "BLUS30161") {
            return
        }
        if ($_.image_sig -ne "0x958dfe208b686622") {
            return
        }

        $pc = "$($_.max_dma_pc)"
        $fit = "$($_.offload_fit)"
        $dispatch = "$($_.dispatch_risk)"
        $group = "$($_.group_name)"
        $spu = "$($_.spu_name)"
        if ([string]::IsNullOrWhiteSpace($pc) -or [string]::IsNullOrWhiteSpace($fit)) {
            return
        }

        $key = "$($_.image_sig)|$pc|$group|$spu|$fit|$dispatch"
        if (-not $candidateMap.ContainsKey($key)) {
            $candidateMap[$key] = [pscustomobject]@{
                Image = "$($_.image_sig)"
                Pc = $pc
                Group = $group
                Spu = $spu
                Fit = $fit
                Dispatch = $dispatch
                Records = 0
                TotalBytes = [UInt64]0
                GetBytes = [UInt64]0
                PutBytes = [UInt64]0
                ListGetBytes = [UInt64]0
                ListPutBytes = [UInt64]0
                RsxBytes = [UInt64]0
                MaxJobBytes = [UInt64]0
                Runs = @{}
                Patterns = @{}
                TopEa = @{}
            }
        }

        $item = $candidateMap[$key]
        $total = To-UInt64Safe $_.total_bytes
        $rsx = (To-UInt64Safe $_.rsx_get_bytes) + (To-UInt64Safe $_.rsx_put_bytes)
        $item.Records++
        $item.TotalBytes += $total
        $item.GetBytes += To-UInt64Safe $_.get_bytes
        $item.PutBytes += To-UInt64Safe $_.put_bytes
        $item.ListGetBytes += To-UInt64Safe $_.list_get_bytes
        $item.ListPutBytes += To-UInt64Safe $_.list_put_bytes
        $item.RsxBytes += $rsx
        if ($total -gt $item.MaxJobBytes) {
            $item.MaxJobBytes = $total
        }
        Add-SetValue -Set $item.Runs -Value $run.Name
        Add-SetValue -Set $item.Patterns -Value "$($_.pattern_sig)"
        Add-SetValue -Set $item.TopEa -Value "$($_.max_dma_ea)"

        $patternKey = "$($_.image_sig)|$pc|$($_.pattern_sig)|$group|$spu|$fit|$dispatch"
        if (-not $patternMap.ContainsKey($patternKey)) {
            $patternMap[$patternKey] = [pscustomobject]@{
                Image = "$($_.image_sig)"
                Pc = $pc
                Pattern = "$($_.pattern_sig)"
                Group = $group
                Spu = $spu
                Fit = $fit
                Dispatch = $dispatch
                Records = 0
                TotalBytes = [UInt64]0
                Runs = @{}
                RsxBytes = [UInt64]0
            }
        }
        $pattern = $patternMap[$patternKey]
        $pattern.Records++
        $pattern.TotalBytes += $total
        $pattern.RsxBytes += $rsx
        Add-SetValue -Set $pattern.Runs -Value $run.Name
    }
}

$validRunCount = $validRuns.Count
$candidates = @($candidateMap.Values | ForEach-Object {
    $runsSeen = @($_.Runs.Keys).Count
    $patternCount = @($_.Patterns.Keys).Count
    $eaCount = @($_.TopEa.Keys).Count
    $recommendation = if ($_.RsxBytes -gt 0) {
        "gpu-superpath-scout"
    } elseif ($_.Fit -eq "spu-kernel-hle" -and $runsSeen -ge 2 -and $_.TotalBytes -ge 512MB) {
        "spu-hle-codegen-priority"
    } elseif ($_.Fit -eq "spu-kernel-hle") {
        "spu-hle-codegen-candidate"
    } elseif ($_.Fit -eq "too-small") {
        "too-small-parked"
    } else {
        "profile-more"
    }

    [pscustomobject]@{
        Recommendation = $recommendation
        Image = $_.Image
        Pc = $_.Pc
        Group = $_.Group
        Spu = $_.Spu
        Fit = $_.Fit
        Dispatch = $_.Dispatch
        Records = $_.Records
        RunsSeen = $runsSeen
        PatternCount = $patternCount
        EaCount = $eaCount
        TotalBytes = $_.TotalBytes
        Total = Format-Bytes $_.TotalBytes
        Get = Format-Bytes $_.GetBytes
        Put = Format-Bytes $_.PutBytes
        ListGet = Format-Bytes $_.ListGetBytes
        ListPut = Format-Bytes $_.ListPutBytes
        RsxBytes = $_.RsxBytes
        Rsx = Format-Bytes $_.RsxBytes
        MaxJob = Format-Bytes $_.MaxJobBytes
    }
}) | Sort-Object @{ Expression = "TotalBytes"; Descending = $true }, @{ Expression = "Records"; Descending = $true }

$patterns = @($patternMap.Values | ForEach-Object {
    [pscustomobject]@{
        Image = $_.Image
        Pc = $_.Pc
        Pattern = $_.Pattern
        Group = $_.Group
        Spu = $_.Spu
        Fit = $_.Fit
        Dispatch = $_.Dispatch
        Records = $_.Records
        RunsSeen = @($_.Runs.Keys).Count
        TotalBytes = $_.TotalBytes
        Total = Format-Bytes $_.TotalBytes
        RsxBytes = $_.RsxBytes
        Rsx = Format-Bytes $_.RsxBytes
    }
}) | Sort-Object @{ Expression = "RunsSeen"; Descending = $true }, @{ Expression = "TotalBytes"; Descending = $true }

$generated = (Get-Date).ToString("o")
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# Eternal Sonata SPU HLE Candidate Atlas")
$md.Add("")
$md.Add(("- Generated: {0}" -f $generated))
$md.Add(("- Run root: {0}" -f (Resolve-Path -LiteralPath $RunRoot).Path))
$md.Add(("- Recent run dirs scanned: {0}" -f $runDirs.Count))
$md.Add(("- Valid field runs used: {0}" -f $validRunCount))
$md.Add(("- Field-like runs excluded by fatal logs: {0}" -f $excludedRuns.Count))
$md.Add("")
$md.Add("## Reading")
$md.Add("")
if ($validRunCount -eq 0) {
    $md.Add("- No valid field runs were found. Re-establish a clean Windows field route before ranking HLE candidates.")
} else {
    $topCandidate = @($candidates | Select-Object -First 1)
    if ($topCandidate.Count -gt 0) {
        $md.Add(("- Top stable bucket: PC {0}, {1} / {2}, {3} over {4} valid run(s), recommendation {5}." -f $topCandidate[0].Pc, $topCandidate[0].Group, $topCandidate[0].Spu, $topCandidate[0].Total, $topCandidate[0].RunsSeen, $topCandidate[0].Recommendation))
    }
    $rsxCandidates = @($candidates | Where-Object { $_.RsxBytes -gt 0 })
    if ($rsxCandidates.Count -eq 0) {
        $md.Add("- No candidate in the valid field set has RSX-local bytes. Broad SPU-to-Vulkan compute remains parked; target SPU kernel HLE/codegen/verifier first.")
    } else {
        $md.Add(("- {0} candidate bucket(s) had RSX-local bytes and need a GPU-superpath scout before any fast path." -f $rsxCandidates.Count))
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
$md.Add("## Excluded Runs")
$md.Add("")
if ($excludedRuns.Count -eq 0) {
    $md.Add("- None.")
} else {
    foreach ($run in $excludedRuns) {
        $md.Add(("- {0}: {1}, {2}" -f $run.Name, $run.Reason, $run.Detail))
    }
}
$md.Add("")
$md.Add("## Candidate Buckets")
$md.Add("")
$md.Add("| Rank | Recommendation | PC | Group | SPU | Fit | Dispatch | Runs | Records | Patterns | Total | GET | PUT | List GET | RSX | Max Job |")
$md.Add("| ---: | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
$rank = 0
foreach ($candidate in ($candidates | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | {15} |" -f $rank, $candidate.Recommendation, $candidate.Pc, $candidate.Group, $candidate.Spu, $candidate.Fit, $candidate.Dispatch, $candidate.RunsSeen, $candidate.Records, $candidate.PatternCount, $candidate.Total, $candidate.Get, $candidate.Put, $candidate.ListGet, $candidate.Rsx, $candidate.MaxJob))
}
$md.Add("")
$md.Add("## Repeated Patterns")
$md.Add("")
$md.Add("| Rank | PC | Pattern | Group | SPU | Runs | Records | Total | RSX | Fit |")
$md.Add("| ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- |")
$rank = 0
foreach ($pattern in ($patterns | Select-Object -First $Top)) {
    $rank++
    $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f $rank, $pattern.Pc, $pattern.Pattern, $pattern.Group, $pattern.Spu, $pattern.RunsSeen, $pattern.Records, $pattern.Total, $pattern.Rsx, $pattern.Fit))
}
$md.Add("")
$md.Add("## Next HLE Verifier Target")
$md.Add("")
if ($validRunCount -eq 0 -or $candidates.Count -eq 0) {
    $md.Add("- No verifier target selected because no valid candidate bucket was available.")
} else {
    $priority = @($candidates | Where-Object { $_.Recommendation -eq "spu-hle-codegen-priority" } | Select-Object -First 1)
    if ($priority.Count -eq 0) {
        $priority = @($candidates | Select-Object -First 1)
    }
    $target = $priority[0]
    $newestRun = $validRuns[0]
    $targetPatterns = @($patterns |
        Where-Object {
            $_.Pc -eq $target.Pc -and
            $_.Group -eq $target.Group -and
            $_.Spu -eq $target.Spu -and
            $_.Fit -eq $target.Fit
        } |
        Select-Object -First 6)
    $snippet = Get-DisasmSnippet -RunDir $newestRun.Path -Pc $target.Pc -Group $target.Group

    $md.Add(("- Target: PC {0}, {1} / {2}, image {3}." -f $target.Pc, $target.Group, $target.Spu, $target.Image))
    $md.Add(("- Shape: {0} total over {1} record(s), GET {2}, PUT {3}, list GET {4}, RSX {5}, max job {6}." -f $target.Total, $target.Records, $target.Get, $target.Put, $target.ListGet, $target.Rsx, $target.MaxJob))
    $md.Add(("- Stability: {0} valid run(s), {1} pattern signature(s), {2} max-DMA EA value(s)." -f $target.RunsSeen, $target.PatternCount, $target.EaCount))
    if ($snippet.Path) {
        $md.Add(("- Latest valid disasm window: {0}" -f $snippet.Path))
    } else {
        $md.Add("- Latest valid disasm window: not found in the newest valid run.")
    }
    if ($targetPatterns.Count -gt 0) {
        $md.Add("")
        $md.Add("| Rank | Pattern | Runs | Records | Total | RSX |")
        $md.Add("| ---: | --- | ---: | ---: | ---: | ---: |")
        $patternRank = 0
        foreach ($targetPattern in $targetPatterns) {
            $patternRank++
            $md.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $patternRank, $targetPattern.Pattern, $targetPattern.RunsSeen, $targetPattern.Records, $targetPattern.Total, $targetPattern.Rsx))
        }
    }
    if ($snippet.Lines.Count -gt 0) {
        $md.Add("")
        $md.Add("Disasm cue:")
        $md.Add("")
        $md.Add('```text')
        foreach ($line in $snippet.Lines) {
            $md.Add($line)
        }
        $md.Add('```')
    }
    $md.Add("")
    $md.Add("Verifier contract:")
    $md.Add("")
    $md.Add(("- Gate first on title BLUS30161, image {0}, group {1}, SPU {2}, and PC {3}." -f $target.Image, $target.Group, $target.Spu, $target.Pc))
    $md.Add("- Start with verify mode only: record the MFC command descriptor and touched GET/PUT ranges, run the stock path, then compare the candidate result before any fast return.")
    $md.Add("- Do not use Vulkan compute for this bucket unless a later trace shows RSX-consumed data; this target is currently an SPU HLE/codegen/verifier target, not GPU migration credit.")
}
$md.Add("")
$md.Add("## Classification")
$md.Add("")
$md.Add("- analysis, not gpu-migration-credit, not windows-micro-win, not a 200% gate candidate.")
$md.Add("- Use this atlas to choose a verify-gated SPU HLE/codegen target, then prove field/menu/battle visuals before fast mode.")

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
    $candidates | Select-Object Recommendation,Image,Pc,Group,Spu,Fit,Dispatch,Records,RunsSeen,PatternCount,EaCount,TotalBytes,RsxBytes,Total,Get,Put,ListGet,ListPut,Rsx,MaxJob |
        Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$md | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
