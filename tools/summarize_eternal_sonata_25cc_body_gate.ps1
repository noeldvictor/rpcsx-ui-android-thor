[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [string]$FieldRun = "20260525-102628-hle-25cc-shadow-verify-field-windows",

    [string]$OptionsRun = "20260525-105528-hle-25cc-shadow-verify-options-route-repair-windows",

    [string]$BattleRun = "20260525-110806-hle-25cc-shadow-verify-battle-windows",

    [string]$OutPath = "",

    [string]$CsvPath = "",

    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
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

function Convert-GateNumber {
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

function Format-GateBytes {
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

function Get-GateSum {
    param(
        [object[]]$Rows,
        [string]$Property
    )

    $sum = [UInt64]0
    foreach ($row in $Rows) {
        $sum += Convert-GateNumber $row.$Property
    }
    return $sum
}

function Read-GateCsv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required CSV: $Path"
    }

    return @(Import-Csv -LiteralPath $Path)
}

function Build-SceneGate {
    param(
        [string]$Scene,
        [string]$RunDir
    )

    $familyRows = Read-GateCsv (Join-Path $RunDir "eternal-sonata-spu-hle-25cc-family-profile.csv")
    $shadowRows = Read-GateCsv (Join-Path $RunDir "eternal-sonata-spu-hle-25cc-shadow-profile.csv")
    $gpuRows = @(Read-GateCsv (Join-Path $RunDir "eternal-sonata-gpu-probe-records.csv") | Where-Object {
        $_.max_dma_pc -eq "0x25cc" -and $_.image_sig -eq "0x958dfe208b686622"
    })

    $familyHits = Get-GateSum $familyRows "hits"
    $familyFail = Get-GateSum $familyRows "fail"
    $shadowHits = Get-GateSum $shadowRows "hits"
    $shadowMismatch = Get-GateSum $shadowRows "output_mismatch"
    $shadowChanged = Get-GateSum $shadowRows "dst_changed"
    $shadowUnchanged = Get-GateSum $shadowRows "dst_unchanged"
    $shadowBytes = Get-GateSum $shadowRows "bytes"
    $gpuTotal = Get-GateSum $gpuRows "total_bytes"
    $rsxBytes = (Get-GateSum $gpuRows "rsx_get_bytes") + (Get-GateSum $gpuRows "rsx_put_bytes")

    return [pscustomobject]@{
        Scene = $Scene
        Run = Split-Path -Leaf $RunDir
        RunDir = $RunDir
        FamilyRows = [UInt64]$familyRows.Count
        FamilyHits = $familyHits
        FamilyFail = $familyFail
        ShadowRows = [UInt64]$shadowRows.Count
        ShadowHits = $shadowHits
        ShadowMismatch = $shadowMismatch
        ShadowDstChanged = $shadowChanged
        ShadowDstUnchanged = $shadowUnchanged
        ShadowBytes = $shadowBytes
        ShadowBytesText = Format-GateBytes $shadowBytes
        GpuProbeRows = [UInt64]$gpuRows.Count
        GpuProbeBytes = $gpuTotal
        GpuProbeBytesText = Format-GateBytes $gpuTotal
        RsxBytes = $rsxBytes
        RsxBytesText = Format-GateBytes $rsxBytes
    }
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-25cc-body-gate-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-25cc-body-gate-latest.csv"
}

$sceneRows = @(
    Build-SceneGate -Scene "field" -RunDir (Resolve-RunDir -Root $RunRoot -Run $FieldRun)
    Build-SceneGate -Scene "options" -RunDir (Resolve-RunDir -Root $RunRoot -Run $OptionsRun)
    Build-SceneGate -Scene "battle" -RunDir (Resolve-RunDir -Root $RunRoot -Run $BattleRun)
)

$familyFailTotal = Get-GateSum $sceneRows "FamilyFail"
$shadowMismatchTotal = Get-GateSum $sceneRows "ShadowMismatch"
$shadowChangedTotal = Get-GateSum $sceneRows "ShadowDstChanged"
$rsxBytesTotal = Get-GateSum $sceneRows "RsxBytes"
$shadowHitsTotal = Get-GateSum $sceneRows "ShadowHits"
$shadowBytesTotal = Get-GateSum $sceneRows "ShadowBytes"
$bodyScaffoldReady = $sceneRows.Count -eq 3 -and $familyFailTotal -eq 0 -and $shadowMismatchTotal -eq 0
$copyRequired = $shadowChangedTotal -gt 0
$gpuMigrationReady = $rsxBytesTotal -gt 0
$classification = "analysis"
if ($bodyScaffoldReady) {
    $classification = "spu-hle-25cc-body-scaffold-ready"
}

$generated = (Get-Date).ToString("o")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Body Gate") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $generated") | Out-Null
$lines.Add("- Run root: $((Resolve-Path -LiteralPath $RunRoot).Path)") | Out-Null
$lines.Add(('- Field run: `{0}`' -f $FieldRun)) | Out-Null
$lines.Add(('- Options run: `{0}`' -f $OptionsRun)) | Out-Null
$lines.Add(('- Battle run: `{0}`' -f $BattleRun)) | Out-Null
$lines.Add(('- Body scaffold ready: `{0}`' -f $bodyScaffoldReady)) | Out-Null
$lines.Add(('- Copy/update semantics required: `{0}`' -f $copyRequired)) | Out-Null
$lines.Add(('- GPU migration ready: `{0}`' -f $gpuMigrationReady)) | Out-Null
$lines.Add(('- Classification: `{0}`, not `windows-micro-win`, not `gpu-migration-credit`, not a speed result, not a 200% gate candidate.' -f $classification)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Scene Gates") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Scene | Family hits | Family fail | Shadow hits | Shadow mismatch | Dst changed | Dst unchanged | Shadow bytes | 0x25cc GPU bytes | RSX bytes |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |") | Out-Null
foreach ($row in $sceneRows) {
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |' -f
        $row.Scene,
        $row.FamilyHits,
        $row.FamilyFail,
        $row.ShadowHits,
        $row.ShadowMismatch,
        $row.ShadowDstChanged,
        $row.ShadowDstUnchanged,
        $row.ShadowBytesText,
        $row.GpuProbeBytesText,
        $row.RsxBytesText)) | Out-Null
}
$lines.Add("") | Out-Null
$lines.Add("## Aggregate") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Total shadow hits: $shadowHitsTotal") | Out-Null
$lines.Add("- Total shadow bytes: $(Format-GateBytes $shadowBytesTotal)") | Out-Null
$lines.Add("- Total shadow mismatches: $shadowMismatchTotal") | Out-Null
$lines.Add("- Total destination-changed hits: $shadowChangedTotal") | Out-Null
$lines.Add(('- Total `0x25cc` RSX-local bytes: {0}' -f (Format-GateBytes $rsxBytesTotal))) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
if ($bodyScaffoldReady) {
    $lines.Add('- Field, title Options, and first battle all have zero family failures and zero `0x25cc` shadow mismatches, so an opt-in body scaffold is allowed.') | Out-Null
} else {
    $lines.Add("- Do not enable a body scaffold yet. At least one required scene has a family failure, a shadow mismatch, or missing evidence.") | Out-Null
}
if ($copyRequired) {
    $lines.Add("- The body cannot be a broad skip because destination data changed in the verified shadow samples.") | Out-Null
}
if (-not $gpuMigrationReady) {
    $lines.Add('- This remains CPU/SPU HLE/codegen work, not GPU migration, because the selected `0x25cc` rows have no RSX-local bytes.') | Out-Null
}
$lines.Add("- Any body-on path still needs field, Options, first-battle visual proof and matched uncapped A/B before a speed claim.") | Out-Null

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $OutPath
    if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutPath, $lines, [System.Text.UTF8Encoding]::new($false))

    $csvDir = Split-Path -Parent $CsvPath
    if ($csvDir -and -not (Test-Path -LiteralPath $csvDir -PathType Container)) {
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
    }
    $sceneRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$lines | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
