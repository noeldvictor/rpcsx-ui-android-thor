[CmdletBinding()]
param(
    [string]$PatternCsvPath = ".\debug-experiments\20260526-25cc-pattern-family.csv",

    [string]$CoverageCsvPath = ".\debug-experiments\20260526-25cc-coverage-gap.csv",

    [string]$SourceRoot = "..\rpcs3-upstream",

    [string]$OutPath = ".\debug-experiments\20260526-25cc-9e4000-verifier-plan.md",

    [int]$Top = 12,

    [switch]$NoWrite
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-RepoPath {
    param(
        [string]$Root,
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
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

function Get-UInt64Sum {
    param(
        [object[]]$Rows,
        [string]$Property
    )

    $sum = [UInt64]0
    foreach ($row in $Rows) {
        $sum += To-UInt64Safe $row.$Property
    }
    return $sum
}

function Find-SourceAnchor {
    param(
        [string]$Path,
        [string]$Needle
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return "missing: $Path"
    }

    $hit = Select-String -LiteralPath $Path -SimpleMatch $Needle -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $hit) {
        return "not found: $Needle"
    }

    return ("{0}:{1}" -f $Path, $hit.LineNumber)
}

$repoRoot = Get-RepoRoot
$patternPath = Resolve-RepoPath $repoRoot $PatternCsvPath
$coveragePath = Resolve-RepoPath $repoRoot $CoverageCsvPath
$sourceRootPath = Resolve-RepoPath $repoRoot $SourceRoot
$outFile = Resolve-RepoPath $repoRoot $OutPath

if (-not (Test-Path -LiteralPath $patternPath -PathType Leaf)) {
    throw "Missing pattern-family CSV: $patternPath"
}

$rows = @(Import-Csv -LiteralPath $patternPath)
$familyRows = @($rows | Where-Object { $_.Ea -eq "0x9e4000" })
if ($familyRows.Count -eq 0) {
    throw "Pattern-family CSV has no 0x9e4000 rows: $patternPath"
}

$totalBytes = Get-UInt64Sum $familyRows "TotalBytes"
$totalRecords = Get-UInt64Sum $familyRows "Records"
$totalDurationUs = Get-UInt64Sum $familyRows "DurationUs"
$totalRsxBytes = Get-UInt64Sum $familyRows "RsxBytes"
$topRows = @($familyRows | Sort-Object { To-UInt64Safe $_.TotalBytes } -Descending | Select-Object -First $Top)
$repeatRows = @($familyRows | Where-Object { (To-UInt64Safe $_.RunsSeen) -ge 2 })
$all25ccBytes = Get-UInt64Sum $rows "TotalBytes"

$coverageRows = @()
if (Test-Path -LiteralPath $coveragePath -PathType Leaf) {
    $coverageRows = @(Import-Csv -LiteralPath $coveragePath)
}
$skipRow = $coverageRows | Where-Object { $_.Mode -eq "Skip" } | Select-Object -First 1
$verifyRow = $coverageRows | Where-Object { $_.Mode -eq "Verify" } | Select-Object -First 1

$spuThread = Join-Path $sourceRootPath "rpcs3\Emu\Cell\SPUThread.cpp"
$spuLlvm = Join-Path $sourceRootPath "rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"
$anchors = @(
    [pscustomobject]@{ Area = "runtime family classifier"; File = "SPUThread.cpp"; Anchor = Find-SourceAnchor $spuThread "get_es_mfc_25cc_runtime_family_raw" },
    [pscustomobject]@{ Area = "0x9e4000 family predicate"; File = "SPUThread.cpp"; Anchor = Find-SourceAnchor $spuThread "cmd.eal == 0x9e4000" },
    [pscustomobject]@{ Area = "shadow sample counters"; File = "SPUThread.cpp"; Anchor = Find-SourceAnchor $spuThread "record_es_spu_hle_25cc_shadow_sample" },
    [pscustomobject]@{ Area = "runtime body-copy hook"; File = "SPUThread.cpp"; Anchor = Find-SourceAnchor $spuThread "try_es_spu_hle_25cc_body_copy" },
    [pscustomobject]@{ Area = "MFC command entry"; File = "SPUThread.cpp"; Anchor = Find-SourceAnchor $spuThread "process_mfc_cmd" },
    [pscustomobject]@{ Area = "LLVM verifier candidate"; File = "SPULLVMRecompiler.cpp"; Anchor = Find-SourceAnchor $spuLlvm "exec_es_spu_hle_verify_candidate" },
    [pscustomobject]@{ Area = "dynamic MFC fallback signal"; File = "SPULLVMRecompiler.cpp"; Anchor = Find-SourceAnchor $spuLlvm "is not a constant" }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc / 0x9e4000 Verifier Plan")
$lines.Add("")
$lines.Add("- Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")")
$lines.Add("- Pattern CSV: ``$patternPath``")
$lines.Add("- Coverage CSV: ``$coveragePath``")
$lines.Add("- Source root: ``$sourceRootPath``")
$lines.Add("")
$lines.Add("## Classification")
$lines.Add("")
$lines.Add("- ``analysis``")
$lines.Add("- ``spu-hle-25cc-9e4000-verifier-plan``")
$lines.Add("- Not speed.")
$lines.Add("- Not ``gpu-migration-credit``.")
$lines.Add("- Not a 200% moving-gameplay gate candidate.")
$lines.Add("")
$lines.Add("## Why This Lane")
$lines.Add("")
$lines.Add("- Broad max-DMA ``0x9e4000`` pattern coverage: ``$(Format-Bytes $totalBytes)`` across ``$totalRecords`` records, ``$($familyRows.Count)`` pattern rows, ``$($repeatRows.Count)`` repeated pattern rows, and ``$(Format-Bytes $totalRsxBytes)`` RSX-local bytes.")
$lines.Add("- Total sampled ``0x25cc`` pattern-family bytes in the input CSV: ``$(Format-Bytes $all25ccBytes)``.")
$lines.Add("- Estimated aggregate duration for ``0x9e4000`` rows: ``$("{0:N3}" -f ([double]$totalDurationUs / 1000.0)) ms``.")
if ($skipRow) {
    $lines.Add("- Old exact ``0xa1c000`` guarded skip: ``$($skipRow.SkipTotal)`` skipped, ``$($skipRow.SkipShareOfHotPc)`` of that run's hot ``0x25cc`` bytes, ``$($skipRow.SkipShareOfExactVerify)`` of exact verifier-shape bytes, ``$($skipRow.OutputMismatches)`` mismatches, and ``$($skipRow.DstChanged)`` destination changes.")
}
if ($verifyRow) {
    $lines.Add("- Verify baseline for the exact slice saw ``$($verifyRow.ExactVerifyTotal)`` exact verifier bytes and ``$($verifyRow.OutputMismatches)`` mismatches, but that shape is still too narrow for the refreshed family bucket.")
}
$lines.Add("")
$lines.Add("## Top 0x9e4000 Clusters")
$lines.Add("")
$lines.Add("| Rank | Pattern | Runs | CmdCount | Records | Total | ShareOf25cc | GET | PUT | MaxJob |")
$lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
$rank = 1
foreach ($row in $topRows) {
    $lines.Add("| $rank | ``$($row.Pattern)`` | $($row.RunsSeen) | $($row.CmdCount) | $($row.Records) | $($row.Total) | $($row.ShareOf25cc) | $($row.Get) | $($row.Put) | $($row.MaxJob) |")
    $rank++
}
$lines.Add("")
$lines.Add("## Source Anchors")
$lines.Add("")
$lines.Add("| Area | File | Anchor |")
$lines.Add("| --- | --- | --- |")
foreach ($anchor in $anchors) {
    $lines.Add("| $($anchor.Area) | ``$($anchor.File)`` | ``$($anchor.Anchor)`` |")
}
$lines.Add("")
$lines.Add("## Verifier Predicate")
$lines.Add("")
$lines.Add("The first code change should be verify-only and should not reuse either the exact ``0xa1c000`` skip predicate or an exact command-level ``eal == 0x9e4000`` predicate as the main gate. The broad signal is the max-DMA ``0x9e4000`` pattern/descriptor family from GPU-probe records, while command-level EA buckets must be recorded separately.")
$lines.Add("")
$lines.Add("Gate the broad family by:")
$lines.Add("")
$lines.Add("- title ID ``BLUS30161``")
$lines.Add("- SPU image signature ``0x958dfe208b686622``")
$lines.Add("- group ``CellSpursKernelGroup`` / SPU ``CellSpursKernel0``")
$lines.Add("- PC ``0x25cc``")
$lines.Add("- MFC GET/PUT command, non-list, tag ``31``, size ``0x4000``")
$lines.Add("- main-memory DMA records whose repeated max-DMA EA/pattern signature belongs to the ``0x9e4000`` pattern family")
$lines.Add("- command-level family bucket counters for ``ea9e4000``, ``exact_a1c000``, ``ea4f0b80``, and other matching EAs, without treating any one bucket as the whole fast predicate")
$lines.Add("- valid LS range with no shuffle/accurate-DMA path")
$lines.Add("- verify-only rollback path before any fast/body/skip mode")
$lines.Add("")
$lines.Add("## Counters To Add Or Confirm")
$lines.Add("")
$lines.Add("- family hits, GET hits, PUT hits, rejects, bytes, and duration")
$lines.Add("- command descriptor fields: cmd, tag, size, eah, eal, lsa, PC, image, group, SPU name")
$lines.Add("- source hash, destination pre-hash, destination post-hash, and mismatch count")
$lines.Add("- ``dst_changed`` after stock execution, because unchanged destination data is the safe-copy clue")
$lines.Add("- touched GET/PUT ranges and source/destination overlap rejects")
$lines.Add("- max-DMA pattern signature, command-count bucket, and command-level EA bucket so reports line up with ``20260526-25cc-pattern-family.csv`` without confusing max-DMA EA for exact command EA")
$lines.Add("- payload or LS-range hash samples for the top max-DMA pattern groups; if those remain zero, classify the run as a hash-instrumentation gap")
$lines.Add("")
$lines.Add("## Implementation Reading")
$lines.Add("")
$lines.Add("- Runtime code already has useful exact-EA family counters; extend the pattern/descriptor lane first instead of narrowing the fast predicate to exact command-level ``eal == 0x9e4000``.")
$lines.Add("- LLVM direct-copy recognition is secondary for this sprint because the hot command path has been observed as dynamic/non-constant.")
$lines.Add("- A broad Vulkan compute path remains parked: this family still has ``0 B`` RSX-local bytes and is a tiny-dispatch trap unless a later scout proves an RSX-consumed batch.")
$lines.Add("")
$lines.Add("## First Windows Proof Shape After Code Change")
$lines.Add("")
$lines.Add('```powershell')
$lines.Add('$env:RPCS3_ES_SPU_HLE_VERIFY = "Verify"')
$lines.Add('$env:RPCS3_ES_SPU_HLE_25CC_SHADOW = "1"')
$lines.Add('$env:RPCS3_ES_SPU_HLE_25CC_BODY = "0"')
$lines.Add('.\tools\eternal_sonata_speed_sprint.ps1 <field route> -CleanAfterField')
$lines.Add('```')
$lines.Add("")
$lines.Add("Required proof order after the verifier is clean: field visual, menu/Options visual, then first-battle visual. Only after all three are mismatch-clean should fast/body mode or stacked speed testing be enabled.")
$lines.Add("")
$lines.Add("## Do Not Spend Another Round On")
$lines.Add("")
$lines.Add("- rerunning the exact ``0xa1c000`` guarded skip as if it can produce a large speed gate")
$lines.Add("- enabling fast/body mode before verifier hashes and visuals agree")
$lines.Add("- moving this broad SPU family to Vulkan compute without RSX-local or coarse-batch evidence")

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $outFile
    if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir | Out-Null
    }
    [System.IO.File]::WriteAllLines($outFile, $lines, [System.Text.UTF8Encoding]::new($false))
}

[pscustomobject]@{
    PatternCsv = $patternPath
    CoverageCsv = $coveragePath
    OutPath = $outFile
    FamilyRows = $familyRows.Count
    RepeatedRows = $repeatRows.Count
    Records = $totalRecords
    Bytes = $totalBytes
    BytesText = Format-Bytes $totalBytes
    RsxBytes = $totalRsxBytes
    RsxText = Format-Bytes $totalRsxBytes
}
