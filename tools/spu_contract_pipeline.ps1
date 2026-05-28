param(
    [string]$RunDir = "",
    [string]$RunRoot = "debug-captures\windows-lab",
    [string]$TitleId = "BLUS30161",
    [string]$OutDir = "spu-contracts",
    [string[]]$Pc = @("0x25cc", "0x451c"),
    [string[]]$Ea = @("0x9e4000"),
    [string]$GhidraHeadless = "",
    [switch]$NoGhidra,
    [int]$MaxWindows = 12
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Normalize-Hex {
    param([string]$Value)
    $v = $Value.Trim().ToLowerInvariant()
    if ($v.StartsWith("0x")) { return $v }
    if ($v -match '^\d+$') {
        return ("0x{0:x}" -f [Int64]$v)
    }
    return "0x$v"
}

function Normalize-HexKey {
    param([string]$Value)
    $key = (Normalize-Hex $Value).Substring(2).TrimStart("0")
    if ([string]::IsNullOrWhiteSpace($key)) { return "0" }
    return $key
}

function Normalize-HexCanonical {
    param([string]$Value)
    return "0x$(Normalize-HexKey $Value)"
}

function Find-LatestRun {
    param([string]$Root)
    $rootPath = Resolve-RepoPath $Root
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        throw "Run root not found: $rootPath"
    }
    $runs = Get-ChildItem -LiteralPath $rootPath -Directory |
        Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName "RPCS3.log") -PathType Leaf) -or
            (Test-Path -LiteralPath (Join-Path $_.FullName "spu-images") -PathType Container)
        } |
        Sort-Object LastWriteTime -Descending
    if ($runs.Count -eq 0) {
        throw "No run directories with RPCS3.log or spu-images under $rootPath"
    }
    return $runs[0].FullName
}

function Read-SpuWindows {
    param(
        [string]$ImagesDir,
        [string[]]$TargetPcs,
        [int]$Max
    )

    $windows = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $ImagesDir -PathType Container)) {
        return @()
    }

    $target = @{}
    foreach ($pcValue in $TargetPcs) {
        $target[(Normalize-HexKey $pcValue)] = $true
    }

    foreach ($file in Get-ChildItem -LiteralPath $ImagesDir -Filter "*.disasm.txt" | Sort-Object Name) {
        if ($file.Name -notmatch '^BLUS30161-spu-image-(?<image>[0-9a-f]+)-entry-(?<entry>[0-9a-f]+)-pc-(?<pc>[0-9a-f]+)-group-(?<group>.+)-spu-(?<spuIndex>\d+)-(?<spuName>.+)\.disasm\.txt$') {
            continue
        }
        $pcRaw = $Matches.pc.ToLowerInvariant()
        $pcKey = $pcRaw.TrimStart("0")
        if ([string]::IsNullOrWhiteSpace($pcKey)) { $pcKey = "0" }
        if (-not $target.ContainsKey($pcKey)) {
            continue
        }
        $windows.Add([pscustomobject]@{
            image_sig = "0x$($Matches.image)"
            entry     = "0x$($Matches.entry)"
            pc        = "0x$pcRaw"
            group     = $Matches.group
            spu_index = [int]$Matches.spuIndex
            spu_name  = $Matches.spuName
            disasm    = $file.FullName
        }) | Out-Null
        if ($windows.Count -ge $Max) {
            break
        }
    }
    return $windows.ToArray()
}

function Read-HotEvidence {
    param(
        [string]$LogPath,
        [string]$PcValue,
        [string[]]$EaValues
    )

    $pcCanonical = Normalize-HexCanonical $PcValue
    $pcPatterns = New-Object System.Collections.Generic.List[string]
    $pcPatterns.Add("pc=$pcCanonical") | Out-Null
    $pcPatterns.Add("max_dma_pc=$pcCanonical") | Out-Null
    $pcPatterns.Add("last_pc=$pcCanonical") | Out-Null
    $pcPatterns.Add("[$pcCanonical]") | Out-Null

    $eaPatterns = New-Object System.Collections.Generic.List[string]
    foreach ($eaValue in $EaValues) {
        $eaCanonical = Normalize-HexCanonical $eaValue
        $eaPatterns.Add("ea=$eaCanonical") | Out-Null
        $eaPatterns.Add("max_dma_ea=$eaCanonical") | Out-Null
        $eaPatterns.Add("last_eal=$eaCanonical") | Out-Null
        $eaPatterns.Add("last_ea=$eaCanonical") | Out-Null
    }

    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return [pscustomobject]@{
            hit_count = 0
            pc_hit_count = 0
            ea_hit_count = 0
            sample_lines = @()
            classes = @("no-log")
        }
    }

    $pcMatches = @(Select-String -LiteralPath $LogPath -SimpleMatch -Pattern @($pcPatterns) | Select-Object -First 80)
    $eaMatches = @(Select-String -LiteralPath $LogPath -SimpleMatch -Pattern @($eaPatterns) | Select-Object -First 80)
    $combined = @{}
    foreach ($match in @($pcMatches + $eaMatches)) {
        $combined["$($match.Path):$($match.LineNumber)"] = $match
    }
    $lineMatches = @($combined.Values | Sort-Object Path,LineNumber | Select-Object -First 80)
    $sampleSource = if ($pcMatches.Count -gt 0) { $pcMatches } else { $lineMatches }
    $sampleLines = @($sampleSource | Select-Object -First 8 | ForEach-Object { $_.Line.Trim() })
    $joined = ($sampleLines -join "`n")
    $classes = New-Object System.Collections.Generic.List[string]
    if ($joined -match 'reservation loop verify|GETLLAR|PUTLLC') { $classes.Add("reservation-loop") | Out-Null }
    if ($joined -match 'MFC dynamic probe') { $classes.Add("dynamic-mfc-shape") | Out-Null }
    if ($joined -match 'GPU candidate probe|max_dma') { $classes.Add("dma-window") | Out-Null }
    if ($joined -match 'SPURS|Spurs|CellSpurs') { $classes.Add("spurs-kernel") | Out-Null }
    if ($classes.Count -eq 0) { $classes.Add("unclassified-hot-window") | Out-Null }

    return [pscustomobject]@{
        hit_count = $lineMatches.Count
        pc_hit_count = $pcMatches.Count
        ea_hit_count = $eaMatches.Count
        sample_lines = $sampleLines
        classes = @($classes)
    }
}

function New-Contract {
    param(
        [object]$Window,
        [object]$Evidence,
        [string]$RunPath,
        [string]$Title,
        [bool]$GhidraAvailable,
        [string]$GhidraPath
    )

    $contractId = "{0}-{1}-{2}-{3}" -f $Title, $Window.image_sig.Replace("0x", ""), $Window.pc.Replace("0x", "pc"), $Window.spu_name
    return [pscustomobject]@{
        schema_version = 1
        contract_id = $contractId
        generated_at = (Get-Date).ToString("o")
        title_id = $Title
        source_run = $RunPath
        runtime_anchor = [pscustomobject]@{
            image_sig = $Window.image_sig
            entry = $Window.entry
            pc = $Window.pc
            group = $Window.group
            spu_index = $Window.spu_index
            spu_name = $Window.spu_name
            disasm = $Window.disasm
        }
        inferred_classes = $Evidence.classes
        evidence = [pscustomobject]@{
            hot_log_hits = $Evidence.hit_count
            pc_hot_log_hits = $Evidence.pc_hit_count
            ea_hot_log_hits = $Evidence.ea_hit_count
            sample_lines = $Evidence.sample_lines
        }
        cell_semantics_contract = [pscustomobject]@{
            preserve_mfc_order = $true
            preserve_tags = $true
            preserve_waits = $true
            preserve_dma_size_alignment = $true
            preserve_local_store_ranges = $true
            preserve_reservation_state = ($Evidence.classes -contains "reservation-loop")
        }
        ghidra = [pscustomobject]@{
            status = $(if ($GhidraAvailable) { "available-not-run-by-default" } else { "missing-or-skipped" })
            headless_path = $GhidraPath
            note = "Use Ghidra output to tighten this contract; do not bypass verify-only emulator checks."
        }
        verifier = [pscustomobject]@{
            mode = "verify-only-required"
            required_visuals = @("field", "options-menu", "first-battle")
            required_counters = @("output_mismatch=0", "descriptor_overflow=0", "fatal_log_hits=0")
            fast_mode = "blocked"
        }
    }
}

$runPath = if ([string]::IsNullOrWhiteSpace($RunDir)) {
    Find-LatestRun -Root $RunRoot
} else {
    Resolve-RepoPath $RunDir
}
if (-not (Test-Path -LiteralPath $runPath -PathType Container)) {
    throw "RunDir not found: $runPath"
}

$outRoot = Resolve-RepoPath (Join-Path $OutDir $TitleId)
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

$pcs = @($Pc | ForEach-Object { Normalize-Hex $_ })
$eas = @($Ea | ForEach-Object { Normalize-Hex $_ })
$imagesDir = Join-Path $runPath "spu-images"
$logPath = Join-Path $runPath "RPCS3.log"
$windows = @(Read-SpuWindows -ImagesDir $imagesDir -TargetPcs $pcs -Max $MaxWindows)
if ($windows.Count -eq 0) {
    throw "No SPU disassembly windows found for PCs $($pcs -join ', ') in $imagesDir"
}

$ghidraPath = $GhidraHeadless
if ([string]::IsNullOrWhiteSpace($ghidraPath)) {
    $default = "C:\Users\leanerdesigner\Documents\SteamPortableTools\toolchains\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat"
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        $ghidraPath = $default
    }
}
$ghidraAvailable = (-not $NoGhidra.IsPresent) -and (-not [string]::IsNullOrWhiteSpace($ghidraPath)) -and (Test-Path -LiteralPath $ghidraPath -PathType Leaf)

$contracts = New-Object System.Collections.Generic.List[object]
foreach ($window in $windows) {
    $evidence = Read-HotEvidence -LogPath $logPath -PcValue $window.pc -EaValues $eas
    $contract = New-Contract -Window $window -Evidence $evidence -RunPath $runPath -Title $TitleId -GhidraAvailable $ghidraAvailable -GhidraPath $ghidraPath
    $safeName = ($contract.contract_id -replace '[^A-Za-z0-9_.-]', '_') + ".json"
    $path = Join-Path $outRoot $safeName
    $contract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    $contracts.Add([pscustomobject]@{
        contract_id = $contract.contract_id
        path = $path
        pc = $window.pc
        image_sig = $window.image_sig
        classes = $contract.inferred_classes
        hot_log_hits = $contract.evidence.hot_log_hits
    }) | Out-Null
}

$index = [pscustomobject]@{
    schema_version = 1
    generated_at = (Get-Date).ToString("o")
    title_id = $TitleId
    source_run = $runPath
    target_pcs = $pcs
    target_eas = $eas
    ghidra_available = $ghidraAvailable
    contracts = $contracts.ToArray()
}
$indexPath = Join-Path $outRoot "index.json"
$index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath -Encoding UTF8

$summaryPath = Join-Path $outRoot "latest-summary.md"
$generatedAt = (Get-Date).ToString('o')
$ghidraSummary = if ($ghidraAvailable) { $ghidraPath } else { 'missing-or-skipped' }
$bt = [char]96
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("# SPU Contract Pipeline Summary") | Out-Null
$summary.Add("") | Out-Null
$summary.Add("- Generated: $bt$generatedAt$bt") | Out-Null
$summary.Add("- Title: $bt$TitleId$bt") | Out-Null
$summary.Add("- Source run: $bt$runPath$bt") | Out-Null
$summary.Add("- Target PCs: $bt$($pcs -join ', ')$bt") | Out-Null
$summary.Add("- Target EAs: $bt$($eas -join ', ')$bt") | Out-Null
$summary.Add("- Ghidra headless: $bt$ghidraSummary$bt") | Out-Null
$summary.Add("- Contracts: $bt$($contracts.Count)$bt") | Out-Null
$summary.Add("") | Out-Null
$summary.Add("| Contract | PC | Image | Classes | Hot log hits |") | Out-Null
$summary.Add("| --- | --- | --- | --- | ---: |") | Out-Null
foreach ($contractRow in $contracts) {
    $idText = $contractRow.contract_id
    $pcText = $contractRow.pc
    $imageText = $contractRow.image_sig
    $classText = $contractRow.classes -join ","
    $hitText = $contractRow.hot_log_hits
    $summary.Add("| $bt$idText$bt | $bt$pcText$bt | $bt$imageText$bt | $bt$classText$bt | $hitText |") | Out-Null
}
$summary.Add("") | Out-Null
$summary.Add("Classification: $($bt)analysis$bt, $($bt)spu-contract-scaffold$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
$summary.Add("Next: wire the selected contract into a verify-only emulator counter before any fast path.") | Out-Null
$summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Output "SPU contract index: $indexPath"
Write-Output "SPU contract summary: $summaryPath"
