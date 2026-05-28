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

function New-VerifyCounterPlan {
    param(
        [string]$Title,
        [string]$RunPath,
        [object[]]$ContractRows
    )

    $sourceAnchors = @(
        [pscustomobject]@{ area = "runtime family classifier"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp"; line = 656 },
        [pscustomobject]@{ area = "0x9e4000 family predicate"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp"; line = 683 },
        [pscustomobject]@{ area = "shadow sample counters"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp"; line = 1989 },
        [pscustomobject]@{ area = "runtime body-copy hook"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp"; line = 2161 },
        [pscustomobject]@{ area = "MFC command entry"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp"; line = 6774 },
        [pscustomobject]@{ area = "LLVM verifier candidate"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"; line = 4401 },
        [pscustomobject]@{ area = "dynamic MFC fallback signal"; file = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream\rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"; line = 5707 }
    )

    $lanes = New-Object System.Collections.Generic.List[object]
    foreach ($contract in $ContractRows) {
        $pcKey = Normalize-HexKey $contract.runtime_anchor.pc
        $is25cc = $pcKey -eq "25cc"
        $laneName = if ($is25cc) { "mfc-descriptor-family-25cc-9e4000" } else { "tcx-spurs-descriptor-family-$pcKey" }
        $predicate = if ($is25cc) {
            @(
                "title_id == BLUS30161",
                "image_sig == 0x958dfe208b686622",
                "pc == 0x25cc",
                "group == CellSpursKernelGroup",
                "spu_name == CellSpursKernel0",
                "MFC GET/PUT non-list command",
                "tag == 31",
                "size == 0x4000",
                "max_dma_ea family contains 0x9e4000",
                "valid LS range",
                "no fast/body mutation in verify mode"
            )
        } else {
            @(
                "title_id == BLUS30161",
                "image_sig == 0x958dfe208b686622",
                "pc == 0x$pcKey",
                "group == $($contract.runtime_anchor.group)",
                "spu_name == $($contract.runtime_anchor.spu_name)",
                "MFC command shape recorded before specialization",
                "list and non-list traffic split",
                "valid LS range",
                "no fast/body mutation in verify mode"
            )
        }

        $lanes.Add([pscustomobject]@{
            lane = $laneName
            contract_id = $contract.contract_id
            priority = $(if ($is25cc) { 1 } else { 2 })
            runtime_anchor = $contract.runtime_anchor
            predicate = $predicate
            required_counters = @(
                "hits",
                "bytes",
                "get_hits",
                "put_hits",
                "rejects_by_reason",
                "duration_us",
                "cmd",
                "tag",
                "size",
                "eah",
                "eal",
                "lsa",
                "pc",
                "image_sig",
                "group",
                "spu_name",
                "src_hash",
                "dst_pre_hash",
                "dst_post_hash",
                "output_mismatches",
                "descriptor_overflow",
                "fatal_log_hits"
            )
            promotion_gate = @(
                "verify-only field visual",
                "verify-only Options/menu visual",
                "verify-only first-battle visual",
                "output_mismatches == 0",
                "descriptor_overflow == 0",
                "fatal_log_hits == 0"
            )
            blocked_modes = @("bodyfast", "codegen-fast", "vulkan-compute")
        }) | Out-Null
    }

    return [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        title_id = $Title
        source_run = $RunPath
        classification = @("analysis", "verify-counter-plan")
        source_anchors = $sourceAnchors
        lanes = $lanes.ToArray()
        next_action = "Implement the priority-1 lane as verify-only counters before any fast/body/codegen mode."
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
$contractDetails = New-Object System.Collections.Generic.List[object]
foreach ($window in $windows) {
    $evidence = Read-HotEvidence -LogPath $logPath -PcValue $window.pc -EaValues $eas
    $contract = New-Contract -Window $window -Evidence $evidence -RunPath $runPath -Title $TitleId -GhidraAvailable $ghidraAvailable -GhidraPath $ghidraPath
    $safeName = ($contract.contract_id -replace '[^A-Za-z0-9_.-]', '_') + ".json"
    $path = Join-Path $outRoot $safeName
    $contract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    $contractDetails.Add($contract) | Out-Null
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

$verifyPlan = New-VerifyCounterPlan -Title $TitleId -RunPath $runPath -ContractRows ($contractDetails.ToArray())
$verifyPlanPath = Join-Path $outRoot "verify-counter-plan.json"
$verifyPlan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $verifyPlanPath -Encoding UTF8

$verifyMdPath = Join-Path $outRoot "verify-counter-plan.md"
$verifyMd = New-Object System.Collections.Generic.List[string]
$verifyMd.Add("# SPU Verify Counter Plan") | Out-Null
$verifyMd.Add("") | Out-Null
$verifyMd.Add("- Generated: $bt$generatedAt$bt") | Out-Null
$verifyMd.Add("- Title: $bt$TitleId$bt") | Out-Null
$verifyMd.Add("- Source run: $bt$runPath$bt") | Out-Null
$verifyMd.Add("- Classification: $($bt)analysis$bt, $($bt)verify-counter-plan$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
$verifyMd.Add("") | Out-Null
$verifyMd.Add("| Priority | Lane | Contract | PC | Fast modes |") | Out-Null
$verifyMd.Add("| ---: | --- | --- | --- | --- |") | Out-Null
foreach ($lane in $verifyPlan.lanes) {
    $verifyMd.Add("| $($lane.priority) | $bt$($lane.lane)$bt | $bt$($lane.contract_id)$bt | $bt$($lane.runtime_anchor.pc)$bt | $bt$($lane.blocked_modes -join ', ')$bt |") | Out-Null
}
$verifyMd.Add("") | Out-Null
$verifyMd.Add("Priority-1 implementation target: add verify-only counters for the $($bt)0x25cc/0x9e4000$($bt) MFC descriptor family. Keep bodyfast, codegen-fast, and Vulkan compute blocked until field, Options/menu, and first-battle visuals all pass with zero mismatches, zero descriptor overflow, and zero fatal log hits.") | Out-Null
$verifyMd.Add("") | Out-Null
$verifyMd.Add("Source anchors to inspect first:") | Out-Null
foreach ($anchor in $verifyPlan.source_anchors) {
    $verifyMd.Add("- $($bt)$($anchor.area)$($bt): $($bt)$($anchor.file):$($anchor.line)$bt") | Out-Null
}
$verifyMd | Set-Content -LiteralPath $verifyMdPath -Encoding UTF8

Write-Output "SPU contract index: $indexPath"
Write-Output "SPU contract summary: $summaryPath"
Write-Output "SPU verify plan: $verifyPlanPath"
Write-Output "SPU verify plan summary: $verifyMdPath"
