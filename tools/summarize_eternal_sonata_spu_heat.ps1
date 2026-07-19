param(
    [Parameter(Mandatory = $true)]
    [string]$RunDir,
    [string]$SummaryPath = "",
    [int]$FromSnapshot = 0,
    [int]$ToSnapshot = 0,
    [ValidateRange(1, 32)]
    [int]$Top = 20
)

$ErrorActionPreference = "Stop"
$runDirPath = (Resolve-Path -LiteralPath $RunDir).Path
if ([string]::IsNullOrWhiteSpace($SummaryPath)) {
    $SummaryPath = Join-Path $runDirPath "spu-heat-summary.txt"
}
$summaryFile = (Resolve-Path -LiteralPath $SummaryPath).Path

$summaries = New-Object System.Collections.Generic.List[object]
$blocks = New-Object System.Collections.Generic.List[object]
foreach ($line in [System.IO.File]::ReadLines($summaryFile)) {
    if ($line -match 'ES SPU heat summary: snapshot=(?<snapshot>\d+), final=(?<final>\d+), active_samples=(?<active>\d+), zero_samples=(?<zero>\d+), dropped_samples=(?<dropped>\d+), unique_blocks=(?<unique>\d+)') {
        $summaries.Add([pscustomobject]@{
            snapshot        = [int]$Matches.snapshot
            final           = [int]$Matches.final
            active_samples  = [long]$Matches.active
            zero_samples    = [long]$Matches.zero
            dropped_samples = [long]$Matches.dropped
            unique_blocks   = [long]$Matches.unique
        }) | Out-Null
    } elseif ($line -match 'ES SPU heat block: snapshot=(?<snapshot>\d+), rank=(?<rank>\d+), hash=0x(?<hash>[0-9a-fA-F]+), pc=0x(?<pc>[0-9a-fA-F]+), samples=(?<samples>\d+), entries=(?<entries>\d+), mean_samples_x100=(?<mean>\d+)') {
        $blocks.Add([pscustomobject]@{
            snapshot          = [int]$Matches.snapshot
            rank              = [int]$Matches.rank
            hash              = $Matches.hash.ToLowerInvariant()
            pc                = $Matches.pc.ToLowerInvariant()
            samples           = [long]$Matches.samples
            entries           = [long]$Matches.entries
            mean_samples_x100 = [long]$Matches.mean
        }) | Out-Null
    }
}

if ($summaries.Count -eq 0) {
    throw "No SPU heat snapshots found in '$summaryFile'."
}

$maxSnapshot = ($summaries | Measure-Object -Property snapshot -Maximum).Maximum
if ($ToSnapshot -le 0) {
    $ToSnapshot = $maxSnapshot
}
if ($FromSnapshot -le 0) {
    $FromSnapshot = [Math]::Max(1, $ToSnapshot - 3)
}
if ($FromSnapshot -ge $ToSnapshot) {
    throw "FromSnapshot must be less than ToSnapshot."
}

$fromSummary = $summaries | Where-Object snapshot -eq $FromSnapshot | Select-Object -First 1
$toSummary = $summaries | Where-Object snapshot -eq $ToSnapshot | Select-Object -First 1
if ($null -eq $fromSummary -or $null -eq $toSummary) {
    throw "Requested snapshot range $FromSnapshot->$ToSnapshot is unavailable; captured snapshots are 1..$maxSnapshot."
}

$fromByHash = @{}
$blocks | Where-Object snapshot -eq $FromSnapshot | ForEach-Object { $fromByHash[$_.hash] = $_ }
$deltaRows = @($blocks | Where-Object snapshot -eq $ToSnapshot | ForEach-Object {
    $old = $fromByHash[$_.hash]
    $oldSamples = if ($null -ne $old) { $old.samples } else { 0 }
    $oldEntries = if ($null -ne $old) { $old.entries } else { 0 }
    $deltaSamples = $_.samples - $oldSamples
    $deltaEntries = $_.entries - $oldEntries
    [pscustomobject]@{
        hash              = $_.hash
        pc                = $_.pc
        delta_samples     = $deltaSamples
        delta_entries     = $deltaEntries
        samples_per_entry = if ($deltaEntries -gt 0) { [Math]::Round($deltaSamples / $deltaEntries, 3) } else { 0 }
        final_samples     = $_.samples
        from_observed     = ($null -ne $old)
    }
} | Sort-Object delta_samples -Descending)

$activeDelta = $toSummary.active_samples - $fromSummary.active_samples
$zeroDelta = $toSummary.zero_samples - $fromSummary.zero_samples
$droppedDelta = $toSummary.dropped_samples - $fromSummary.dropped_samples
$plateau = $activeDelta -eq 0
$baseName = "spu-heat-delta-s$FromSnapshot-s$ToSnapshot"
$csvPath = Join-Path $runDirPath "$baseName.csv"
$markdownPath = Join-Path $runDirPath "$baseName.md"
$deltaRows | Select-Object -First $Top | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add("# SPU heat delta") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("- Snapshot range: $FromSnapshot -> $ToSnapshot") | Out-Null
$markdown.Add("- Active sample delta: $activeDelta") | Out-Null
$markdown.Add("- Zero-hash sample delta: $zeroDelta") | Out-Null
$markdown.Add("- Dropped sample delta: $droppedDelta") | Out-Null
$markdown.Add("- Plateau: $($plateau.ToString().ToLowerInvariant())") | Out-Null
$markdown.Add("- Note: block rows are limited to each snapshot's logged top 32.") | Out-Null
$markdown.Add("") | Out-Null
$markdown.Add("| Hash | PC | Delta samples | Delta entries | Samples/entry | Seen in start top 32 |") | Out-Null
$markdown.Add("|---|---:|---:|---:|---:|---|") | Out-Null
foreach ($row in $deltaRows | Select-Object -First $Top) {
    $markdown.Add(('| {0} | 0x{1} | {2} | {3} | {4} | {5} |' -f
        $row.hash,
        $row.pc,
        $row.delta_samples,
        $row.delta_entries,
        $row.samples_per_entry,
        $row.from_observed)) | Out-Null
}
[System.IO.File]::WriteAllLines($markdownPath, $markdown, [System.Text.UTF8Encoding]::new($false))

Write-Output "SPU heat range: $FromSnapshot->$ToSnapshot; active_delta=$activeDelta; zero_delta=$zeroDelta; dropped_delta=$droppedDelta; plateau=$($plateau.ToString().ToLowerInvariant())"
Write-Output "SPU heat CSV: $csvPath"
Write-Output "SPU heat report: $markdownPath"
