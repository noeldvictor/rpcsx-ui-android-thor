[CmdletBinding()]
param(
    [string]$HashTargetCsvPath = ".\debug-experiments\20260526-25cc-pattern-hash-targets.csv",

    [string]$RunDir = "",

    [string]$SourceRoot = "..\rpcs3-upstream",

    [string]$OutPath = ".\debug-experiments\20260526-25cc-shadow-native-contract.md",

    [string]$OutCsvPath = ".\debug-experiments\20260526-25cc-shadow-native-contract.csv",

    [int]$Top = 8,

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

function To-UInt64Safe {
    param([object]$Value)

    if ($null -eq $Value) {
        return [UInt64]0
    }

    $text = "$Value".Trim().Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [UInt64]0
    }

    if ($text -match '^0x([0-9a-fA-F]+)$') {
        return [Convert]::ToUInt64($Matches[1], 16)
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
        return "0.0%"
    }

    return ("{0:N1}%" -f (100.0 * [double]$Part / [double]$Whole))
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
$hashTargetPath = Resolve-RepoPath $repoRoot $HashTargetCsvPath
$sourceRootPath = Resolve-RepoPath $repoRoot $SourceRoot
$outFile = Resolve-RepoPath $repoRoot $OutPath
$outCsvFile = Resolve-RepoPath $repoRoot $OutCsvPath

if (-not (Test-Path -LiteralPath $hashTargetPath -PathType Leaf)) {
    throw "Missing hash-target CSV: $hashTargetPath"
}

$windowsLabRoot = Join-Path $repoRoot "debug-captures\windows-lab"
if ([string]::IsNullOrWhiteSpace($RunDir)) {
    $latest = Get-ChildItem -LiteralPath $windowsLabRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-spu-hle-25cc-shadow-profile.csv") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "eternal-sonata-25cc-runtime-family-patterns.csv") -PathType Leaf)
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw "No Windows run with 25cc shadow and runtime-pattern CSVs found under $windowsLabRoot"
    }

    $RunDir = $latest.FullName
}

$runPath = Resolve-RepoPath $repoRoot $RunDir
$shadowCsvPath = Join-Path $runPath "eternal-sonata-spu-hle-25cc-shadow-profile.csv"
$runtimePatternCsvPath = Join-Path $runPath "eternal-sonata-25cc-runtime-family-patterns.csv"

if (-not (Test-Path -LiteralPath $shadowCsvPath -PathType Leaf)) {
    throw "Missing shadow profile CSV: $shadowCsvPath"
}
if (-not (Test-Path -LiteralPath $runtimePatternCsvPath -PathType Leaf)) {
    throw "Missing runtime pattern CSV: $runtimePatternCsvPath"
}

$targetRows = @(Import-Csv -LiteralPath $hashTargetPath)
$shadowRows = @(Import-Csv -LiteralPath $shadowCsvPath)
$runtimeRows = @(Import-Csv -LiteralPath $runtimePatternCsvPath)

$runtimeSeenTargets = @($targetRows |
    Where-Object { $_.runtime_seen -eq "True" } |
    Sort-Object { To-UInt64Safe $_.runtime_total_bytes } -Descending |
    Select-Object -First $Top)

if ($runtimeSeenTargets.Count -eq 0) {
    throw "Hash-target CSV has no runtime_seen rows: $hashTargetPath"
}

$shadowHits = Get-UInt64Sum $shadowRows "hits"
$shadowBytes = Get-UInt64Sum $shadowRows "bytes"
$shadowGetHits = Get-UInt64Sum $shadowRows "get_hits"
$shadowPutHits = Get-UInt64Sum $shadowRows "put_hits"
$shadowMatch = Get-UInt64Sum $shadowRows "output_match"
$shadowMismatch = Get-UInt64Sum $shadowRows "output_mismatch"
$shadowChanged = Get-UInt64Sum $shadowRows "dst_changed"
$shadowUnchanged = Get-UInt64Sum $shadowRows "dst_unchanged"

$targetRuntimeBytes = Get-UInt64Sum $runtimeSeenTargets "runtime_total_bytes"
$targetRuntimeGetBytes = Get-UInt64Sum $runtimeSeenTargets "runtime_get_bytes"
$targetRuntimePutBytes = Get-UInt64Sum $runtimeSeenTargets "runtime_put_bytes"
$targetAtlasBytes = Get-UInt64Sum $runtimeSeenTargets "atlas_total_bytes"

$contractRows = @()
$rank = 1
foreach ($row in $runtimeSeenTargets) {
    $runtimeBytes = To-UInt64Safe $row.runtime_total_bytes
    $runtimeGetBytes = To-UInt64Safe $row.runtime_get_bytes
    $runtimePutBytes = To-UInt64Safe $row.runtime_put_bytes
    $contractRows += [pscustomobject]@{
        rank = $rank
        pattern_sig = $row.pattern_sig
        atlas_bytes = To-UInt64Safe $row.atlas_total_bytes
        runtime_records = To-UInt64Safe $row.runtime_records
        runtime_bytes = $runtimeBytes
        runtime_get_bytes = $runtimeGetBytes
        runtime_put_bytes = $runtimePutBytes
        runtime_get_share = Format-Percent $runtimeGetBytes $runtimeBytes
        runtime_put_share = Format-Percent $runtimePutBytes $runtimeBytes
        max_cmd_count = To-UInt64Safe $row.runtime_max_cmd_count
        body_gap = $row.body_gap
        native_contract = "verify-put-and-get-shadow-by-pattern-before-bodyfast"
    }
    $rank++
}

$spuThreadPath = Join-Path $sourceRootPath "rpcs3\Emu\Cell\SPUThread.cpp"
$spuLlvmPath = Join-Path $sourceRootPath "rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"
$anchors = @(
    [pscustomobject]@{ Area = "25cc runtime family predicate"; Anchor = Find-SourceAnchor $spuThreadPath "get_es_mfc_25cc_runtime_family_raw" },
    [pscustomobject]@{ Area = "shadow candidate gate"; Anchor = Find-SourceAnchor $spuThreadPath "is_es_spu_hle_shadow_shape_candidate" },
    [pscustomobject]@{ Area = "shadow hash"; Anchor = Find-SourceAnchor $spuThreadPath "compute_es_spu_hle_shadow_hash" },
    [pscustomobject]@{ Area = "shadow begin"; Anchor = Find-SourceAnchor $spuThreadPath "begin_es_spu_hle_shadow_sample" },
    [pscustomobject]@{ Area = "25cc shadow recorder"; Anchor = Find-SourceAnchor $spuThreadPath "record_es_spu_hle_25cc_shadow_sample" },
    [pscustomobject]@{ Area = "25cc body copy"; Anchor = Find-SourceAnchor $spuThreadPath "try_es_spu_hle_25cc_body_copy" },
    [pscustomobject]@{ Area = "MFC shadow begin hook"; Anchor = Find-SourceAnchor $spuThreadPath "const es_spu_hle_shadow_sample es_spu_hle_shadow" },
    [pscustomobject]@{ Area = "MFC shadow finish hook"; Anchor = Find-SourceAnchor $spuThreadPath "finish_es_spu_hle_shadow_sample(_this, args" },
    [pscustomobject]@{ Area = "GPU-probe pattern signature"; Anchor = Find-SourceAnchor $spuThreadPath "mix_es_gpu_probe_signature(probe.pattern_signature" },
    [pscustomobject]@{ Area = "LLVM verifier candidate"; Anchor = Find-SourceAnchor $spuLlvmPath "exec_es_spu_hle_verify_candidate" },
    [pscustomobject]@{ Area = "dynamic MFC fallback signal"; Anchor = Find-SourceAnchor $spuLlvmPath "is not a constant" }
)

if (-not $NoWrite) {
    $contractRows | Export-Csv -LiteralPath $outCsvFile -NoTypeInformation -Encoding UTF8
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Shadow Native Contract")
$lines.Add("")
$lines.Add("- Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")")
$lines.Add("- Classification: ``analysis``, ``spu-hle-25cc-shadow-native-contract``.")
$lines.Add("- Not speed.")
$lines.Add("- Not ``gpu-migration-credit``.")
$lines.Add("- Not a 200% moving-gameplay gate candidate.")
$lines.Add("")
$lines.Add("## Inputs")
$lines.Add("")
$lines.Add("- Hash target CSV: ``$hashTargetPath``")
$lines.Add("- Shadow run: ``$runPath``")
$lines.Add("- Shadow profile CSV: ``$shadowCsvPath``")
$lines.Add("- Runtime pattern CSV: ``$runtimePatternCsvPath``")
$lines.Add("- Source root inspected: ``$sourceRootPath``")
$lines.Add("- Contract CSV: ``$outCsvFile``")
$lines.Add("")
$lines.Add("## Contract Summary")
$lines.Add("")
$lines.Add("- Latest clean shadow verifier output is GET-only: ``$shadowHits`` hits, ``$(Format-Bytes $shadowBytes)``, GET/PUT ``$shadowGetHits/$shadowPutHits``, changed/unchanged ``$shadowChanged/$shadowUnchanged``, match/mismatch ``$shadowMatch/$shadowMismatch``.")
$lines.Add("- Runtime-seen target patterns are PUT-heavy: ``$($runtimeSeenTargets.Count)`` groups, ``$(Format-Bytes $targetRuntimeBytes)`` latest-run bytes, GET ``$(Format-Bytes $targetRuntimeGetBytes)`` (``$(Format-Percent $targetRuntimeGetBytes $targetRuntimeBytes)``), PUT ``$(Format-Bytes $targetRuntimePutBytes)`` (``$(Format-Percent $targetRuntimePutBytes $targetRuntimeBytes)``).")
$lines.Add("- Multi-run atlas coverage for those runtime-seen groups is ``$(Format-Bytes $targetAtlasBytes)``.")
$lines.Add("- Therefore a GET-only body copy can only prove a minority of the runtime-seen hot byte mass. The next source change must make PUT-side shadow semantics visible before any bodyfast or skip promotion.")
$lines.Add("")
$lines.Add("## Runtime-Seen PUT-Heavy Targets")
$lines.Add("")
$lines.Add("| Rank | Pattern | Atlas Bytes | Runtime Records | Runtime Bytes | GET | PUT | Max Cmds | Body Gap |")
$lines.Add("| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |")
foreach ($row in $contractRows) {
    $lines.Add(("| {0} | ``{1}`` | {2} | {3} | {4} | {5} ({6}) | {7} ({8}) | {9} | ``{10}`` |" -f $row.rank, $row.pattern_sig, (Format-Bytes $row.atlas_bytes), $row.runtime_records, (Format-Bytes $row.runtime_bytes), (Format-Bytes $row.runtime_get_bytes), $row.runtime_get_share, (Format-Bytes $row.runtime_put_bytes), $row.runtime_put_share, $row.max_cmd_count, $row.body_gap))
}
$lines.Add("")
$lines.Add("## Source Anchors")
$lines.Add("")
$lines.Add("| Area | Anchor |")
$lines.Add("| --- | --- |")
foreach ($anchor in $anchors) {
    $lines.Add("| $($anchor.Area) | ``$($anchor.Anchor)`` |")
}
$lines.Add("")
$lines.Add("## Native Patch Contract")
$lines.Add("")
$lines.Add("The next productive patch should be a verify-only C++ instrumentation change. Do not add another planning report before this source slice.")
$lines.Add("")
$lines.Add("Required behavior:")
$lines.Add("")
$lines.Add("- Keep stock DMA execution active. Fast/body mode stays off.")
$lines.Add("- Preserve the current title/image/PC/tag/size/non-list/LS-range gates.")
$lines.Add("- Add a pattern or descriptor key to the 0x25cc shadow path: direction, raw/base command, tag, size, LSA, EAL, runtime family, and max-DMA pattern signature or equivalent descriptor hash.")
$lines.Add("- Record GET and PUT rows separately. A run that still emits PUT ``0`` is a verifier failure, not a speed result.")
$lines.Add("- For both directions, record source hash, destination-before hash, destination-after hash, destination changed/unchanged, and output match/mismatch after stock execution.")
$lines.Add("- If PUT semantics need reversed source/destination naming, make that explicit in the CSV columns rather than reusing GET labels ambiguously.")
$lines.Add("- Emit one aggregate CSV row per pattern/descriptor plus direction, with rejects and bytes, so the top rows above can be accepted or killed one by one.")
$lines.Add("- Keep command-level buckets ``ea9e4000``, ``exact_a1c000``, ``ea4f0b80``, and ``other`` only as accounting buckets. They are not broad fast predicates.")
$lines.Add("")
$lines.Add("Acceptance for the next run:")
$lines.Add("")
$lines.Add("- Field route must remain visually clean.")
$lines.Add("- Pattern/descriptor shadow output must include nonzero PUT rows for the targets above or explain a concrete reject reason.")
$lines.Add("- GET and PUT output mismatch counts must be zero before any fast/body path is considered.")
$lines.Add("- Menu/Options and first-battle visual proof are still required before this can become stackable speed work.")
$lines.Add("")
$lines.Add("## Parked Paths")
$lines.Add("")
$lines.Add("- Broad SPU-to-Vulkan compute remains parked. The latest evidence still has ``0 B`` RSX-local or indirect RSX-resource overlap, so this is CPU/SPU verifier work, not GPU migration.")
$lines.Add("- Exact-EA skip/body paths remain parked. The evidence says the broad family is pattern/descriptor shaped, not a single command-level EA.")
$lines.Add("- More route movement reruns are parked until this verifier emits direction-split shadow data.")

if (-not $NoWrite) {
    $outDir = Split-Path -Parent $outFile
    if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir | Out-Null
    }
    [System.IO.File]::WriteAllLines($outFile, $lines, [System.Text.UTF8Encoding]::new($false))
}

$lines | Write-Output

if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $outFile)
    Write-Output ("CSV: {0}" -f $outCsvFile)
}
