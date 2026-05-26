[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [string]$VerifyRun = "20260524-125346-hle-shadow-verify-titlecsv-uncap240-field-windows-windows",

    [string]$SkipRun = "20260524-125942-hle-shadow-skip-titlecsv-uncap240-field-windows-windows",

    [string]$AtlasCsvPath = "",

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

function Convert-SizeToBytes {
    param([string]$Text)

    $clean = "$Text".Trim().Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return [UInt64]0
    }
    if ($clean -match '^(?<value>[0-9]+(?:\.[0-9]+)?)\s*(?<unit>GB|MB|KB|B)$') {
        $value = [double]$matches["value"]
        switch ($matches["unit"]) {
            "GB" { return [UInt64][Math]::Round($value * 1GB) }
            "MB" { return [UInt64][Math]::Round($value * 1MB) }
            "KB" { return [UInt64][Math]::Round($value * 1KB) }
            "B" { return [UInt64][Math]::Round($value) }
        }
    }
    return To-UInt64Safe $clean
}

function Resolve-RunDir {
    param(
        [string]$Root,
        [string]$Run
    )

    if ([System.IO.Path]::IsPathRooted($Run)) {
        return (Resolve-Path -LiteralPath $Run).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $Root $Run)).Path
}

function Read-HotPcSummary {
    param(
        [string]$RunDir,
        [string]$Pc = "0x25cc"
    )

    $path = Join-Path $RunDir "eternal-sonata-gpu-probe-summary.md"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing GPU probe summary: $path"
    }

    $pcLiteral = [regex]::Escape(('`' + $Pc + '`'))
    $pattern = '^\|\s*' + $pcLiteral + '\s*\|\s*(?<records>[0-9,]+)\s*\|\s*(?<sum>[^|]+)\|\s*(?<maxTotal>[^|]+)\|\s*(?<maxDma>[^|]+)\|\s*(?<group>[^|]+)\|\s*(?<spu>[^|]+)\|\s*(?<topEa>[^|]+)\|'
    $line = Get-Content -LiteralPath $path | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if (-not $line) {
        throw "Could not find Hot PC Summary row for $Pc in $path"
    }

    $null = $line -match $pattern
    return [pscustomobject]@{
        Records = To-UInt64Safe $matches["records"]
        SumBytes = Convert-SizeToBytes $matches["sum"]
        SumText = $matches["sum"].Trim()
        MaxTotal = $matches["maxTotal"].Trim()
        MaxDma = $matches["maxDma"].Trim()
        Group = $matches["group"].Trim().Trim([char]0x60)
        Spu = $matches["spu"].Trim().Trim([char]0x60)
        TopEa = $matches["topEa"].Trim().Trim([char]0x60)
    }
}

function Read-ExactVerifyShape {
    param([string]$RunDir)

    $path = Join-Path $RunDir "eternal-sonata-spu-hle-verify-profile.csv"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU HLE verify CSV: $path"
    }

    $rows = @(Import-Csv -LiteralPath $path | Where-Object {
        $_.last_pc -eq "0x25cc" -and
        $_.last_cmd -eq "0x40" -and
        $_.last_tag -eq "31" -and
        $_.last_size -eq "16384" -and
        $_.last_lsa -eq "0x3b000" -and
        $_.last_eal -eq "0xa1c000"
    })

    $hits = [UInt64]0
    $runtime = [UInt64]0
    $llvm = [UInt64]0
    $bytes = [UInt64]0
    foreach ($row in $rows) {
        $hits += To-UInt64Safe $row.hits
        $runtime += To-UInt64Safe $row.runtime_hits
        $llvm += To-UInt64Safe $row.llvm_hits
        $bytes += To-UInt64Safe $row.bytes
    }

    return [pscustomobject]@{
        Rows = [UInt64]$rows.Count
        Hits = $hits
        RuntimeHits = $runtime
        LlvmHits = $llvm
        Bytes = $bytes
    }
}

function Read-ExactShadowShape {
    param([string]$RunDir)

    $path = Join-Path $RunDir "eternal-sonata-spu-hle-shadow-profile.csv"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU HLE shadow CSV: $path"
    }

    $rows = @(Import-Csv -LiteralPath $path | Where-Object {
        $_.last_pc -eq "0x25cc" -and
        $_.last_cmd -eq "0x40" -and
        $_.last_tag -eq "31" -and
        $_.last_size -eq "16384" -and
        $_.last_lsa -eq "0x3b000" -and
        $_.last_eal -eq "0xa1c000"
    })

    $hits = [UInt64]0
    $bytes = [UInt64]0
    $match = [UInt64]0
    $mismatch = [UInt64]0
    $dstChanged = [UInt64]0
    $dstUnchanged = [UInt64]0
    $skipHits = [UInt64]0
    $skipBytes = [UInt64]0
    $skipMisses = [UInt64]0
    foreach ($row in $rows) {
        $hits += To-UInt64Safe $row.hits
        $bytes += To-UInt64Safe $row.bytes
        $match += To-UInt64Safe $row.output_match
        $mismatch += To-UInt64Safe $row.output_mismatch
        $dstChanged += To-UInt64Safe $row.dst_changed
        $dstUnchanged += To-UInt64Safe $row.dst_unchanged
        $skipHits += To-UInt64Safe $row.skip_hits
        $skipBytes += To-UInt64Safe $row.skip_bytes
        $skipMisses += To-UInt64Safe $row.skip_misses
    }

    return [pscustomobject]@{
        Rows = [UInt64]$rows.Count
        Hits = $hits
        Bytes = $bytes
        OutputMatch = $match
        OutputMismatch = $mismatch
        DstChanged = $dstChanged
        DstUnchanged = $dstUnchanged
        SkipHits = $skipHits
        SkipBytes = $skipBytes
        SkipMisses = $skipMisses
    }
}

function Read-TitleSamples {
    param([string]$RunDir)

    $path = Join-Path $RunDir "window-title-samples.csv"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Samples = [UInt64]0; AverageFps = ""; MedianFps = ""; MaxFps = "" }
    }

    $rows = @(Import-Csv -LiteralPath $path | Where-Object { $_.fps -match '^[0-9]+(?:\.[0-9]+)?$' })
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{ Samples = [UInt64]0; AverageFps = ""; MedianFps = ""; MaxFps = "" }
    }

    $values = @($rows | ForEach-Object { [double]$_.fps } | Sort-Object)
    $avg = ($values | Measure-Object -Average).Average
    $median = if (($values.Count % 2) -eq 1) {
        $values[[int][Math]::Floor($values.Count / 2)]
    } else {
        ($values[($values.Count / 2) - 1] + $values[$values.Count / 2]) / 2.0
    }

    return [pscustomobject]@{
        Samples = [UInt64]$values.Count
        AverageFps = ("{0:N2}" -f $avg)
        MedianFps = ("{0:N2}" -f $median)
        MaxFps = ("{0:N2}" -f ($values | Select-Object -Last 1))
    }
}

function Build-RunSummary {
    param(
        [string]$Mode,
        [string]$RunDir
    )

    $hot = Read-HotPcSummary -RunDir $RunDir
    $verify = Read-ExactVerifyShape -RunDir $RunDir
    $shadow = Read-ExactShadowShape -RunDir $RunDir
    $title = Read-TitleSamples -RunDir $RunDir

    return [pscustomobject]@{
        Mode = $Mode
        Run = Split-Path -Leaf $RunDir
        HotPcRecords = $hot.Records
        HotPcBytes = $hot.SumBytes
        HotPcTotal = Format-Bytes $hot.SumBytes
        HotPcTopEa = $hot.TopEa
        ExactVerifyRows = $verify.Rows
        ExactVerifyHits = $verify.Hits
        ExactVerifyBytes = $verify.Bytes
        ExactVerifyTotal = Format-Bytes $verify.Bytes
        ExactVerifyShareOfHotPc = Format-Percent $verify.Bytes $hot.SumBytes
        ExactShadowRows = $shadow.Rows
        ExactShadowBytes = $shadow.Bytes
        ExactShadowTotal = Format-Bytes $shadow.Bytes
        OutputMismatches = $shadow.OutputMismatch
        DstChanged = $shadow.DstChanged
        SkipHits = $shadow.SkipHits
        SkipBytes = $shadow.SkipBytes
        SkipTotal = Format-Bytes $shadow.SkipBytes
        SkipMisses = $shadow.SkipMisses
        SkipShareOfHotPc = Format-Percent $shadow.SkipBytes $hot.SumBytes
        SkipShareOfExactVerify = Format-Percent $shadow.SkipBytes $verify.Bytes
        TitleSamples = $title.Samples
        TitleAverageFps = $title.AverageFps
        TitleMedianFps = $title.MedianFps
        TitleMaxFps = $title.MaxFps
    }
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($AtlasCsvPath)) {
    $AtlasCsvPath = Join-Path $RunRoot "_eternal-sonata-spu-hle-candidates-latest.csv"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-25cc-coverage-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-25cc-coverage-latest.csv"
}

$verifyDir = Resolve-RunDir -Root $RunRoot -Run $VerifyRun
$skipDir = Resolve-RunDir -Root $RunRoot -Run $SkipRun
$summaries = @(
    (Build-RunSummary -Mode "Verify" -RunDir $verifyDir),
    (Build-RunSummary -Mode "Skip" -RunDir $skipDir)
)

$atlasRow = $null
if (Test-Path -LiteralPath $AtlasCsvPath -PathType Leaf) {
    $atlasRow = Import-Csv -LiteralPath $AtlasCsvPath |
        Where-Object { $_.Pc -eq "0x25cc" -and $_.Image -eq "0x958dfe208b686622" } |
        Select-Object -First 1
}

$atlasBytes = if ($atlasRow) { To-UInt64Safe $atlasRow.TotalBytes } else { [UInt64]0 }
$skipSummary = $summaries | Where-Object { $_.Mode -eq "Skip" } | Select-Object -First 1

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Coverage Gap")
$lines.Add("")
$lines.Add(('- Generated: {0}' -f (Get-Date -Format o)))
$lines.Add(('- Verify run: `{0}`' -f $summaries[0].Run))
$lines.Add(('- Skip run: `{0}`' -f $summaries[1].Run))
if ($atlasRow) {
    $lines.Add(('- Latest atlas 0x25cc bucket: `{0}` records across `{1}` valid field runs, `{2}`, `{3}` RSX-local.' -f $atlasRow.Records, $atlasRow.RunsSeen, $atlasRow.Total, $atlasRow.Rsx))
}
$lines.Add('- Classification: `analysis`, `spu-hle-25cc-coverage-gap`, not `windows-micro-win`, not `gpu-migration-credit`, not a 200% gate candidate.')
$lines.Add("")
$lines.Add("## Coverage")
$lines.Add("")
$lines.Add("| Mode | Hot 0x25cc | Top EA | Exact verify shape | Verify share | Shadow bytes | Skip bytes | Skip/Hot | Skip/Exact | Mismatch | Dst changed | Title avg FPS |")
$lines.Add("| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
foreach ($summary in $summaries) {
    $lines.Add(('| {0} | {1} / {2} rec | `{3}` | {4} / {5} hits | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} |' -f $summary.Mode, $summary.HotPcTotal, $summary.HotPcRecords, $summary.HotPcTopEa, $summary.ExactVerifyTotal, $summary.ExactVerifyHits, $summary.ExactVerifyShareOfHotPc, $summary.ExactShadowTotal, $summary.SkipTotal, $summary.SkipShareOfHotPc, $summary.SkipShareOfExactVerify, $summary.OutputMismatches, $summary.DstChanged, $summary.TitleAverageFps))
}
$lines.Add("")
$lines.Add("## Reading")
$lines.Add("")
$lines.Add(('- The exact guarded skip shape remains correctness-clean: the title-CSV skip run has `{0}` mismatches, `{1}` destination changes, `{2}` skip misses, and `{3}` of proven redundant copy removal.' -f $skipSummary.OutputMismatches, $skipSummary.DstChanged, $skipSummary.SkipMisses, $skipSummary.SkipTotal))
$lines.Add(('- The same skip removes only `{0}` of that run''s total hot `0x25cc` bytes and `{1}` of the exact verifier-shape bytes.' -f $skipSummary.SkipShareOfHotPc, $skipSummary.SkipShareOfExactVerify))
if ($atlasRow) {
    $lines.Add(('- Against the refreshed atlas bucket (`{0}`), the title-CSV skip''s `{1}` is only `{2}` of observed `0x25cc` traffic.' -f $atlasRow.Total, $skipSummary.SkipTotal, (Format-Percent $skipSummary.SkipBytes $atlasBytes)))
}
$lines.Add(('- The hot `0x25cc` row''s top EA is `{0}`, while the exact skip shape is fixed to `lsa=0x3b000` / `eal=0xa1c000`; this explains why the clean skip did not become a measured speed win.' -f $skipSummary.HotPcTopEa))
$lines.Add('- Next useful `0x25cc` work should broaden verify-only coverage around the dynamic MFC / `0x9e4000` pattern families or codegen dispatch overhead. Do not rerun the exact `0xa1c000` skip expecting 200%.')
$lines.Add("")

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $OutPath
    if (-not [string]::IsNullOrWhiteSpace($outDir)) {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    }
    $summaries | Export-Csv -NoTypeInformation -LiteralPath $CsvPath
    [System.IO.File]::WriteAllLines($OutPath, $lines)
}

$lines -join [Environment]::NewLine
