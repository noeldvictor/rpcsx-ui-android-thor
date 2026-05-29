param(
    [string]$RunDir = "",
    [string]$RunRoot = "debug-captures\windows-lab",
    [string]$TitleId = "BLUS30161",
    [string]$OutDir = "spu-contracts",
    [string[]]$Pc = @("0x25cc", "0x451c"),
    [string[]]$Ea = @("0x9e4000"),
    [string]$GhidraHeadless = "",
    [string]$UpstreamSourceRoot = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream",
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

function Test-SourceFeature {
    param(
        [string]$SourceRole,
        [string]$Lane,
        [string]$Name,
        [string]$Path,
        [string[]]$Patterns,
        [string]$Expectation,
        [string]$Interpretation
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $patternRows = New-Object System.Collections.Generic.List[object]
    foreach ($pattern in $Patterns) {
        $match = $null
        if ($exists) {
            $match = Select-String -LiteralPath $Path -SimpleMatch -Pattern $pattern | Select-Object -First 1
        }
        $patternRows.Add([pscustomobject]@{
            pattern = $pattern
            present = [bool]$match
            line = $(if ($match) { $match.LineNumber } else { $null })
        }) | Out-Null
    }

    $presentCount = @($patternRows | Where-Object { $_.present }).Count
    $status = if (-not $exists) {
        "source-missing"
    } elseif ($presentCount -eq $Patterns.Count) {
        "present"
    } elseif ($presentCount -gt 0) {
        "partial"
    } else {
        "absent"
    }

    return [pscustomobject]@{
        source_role = $SourceRole
        lane = $Lane
        feature = $Name
        file = $Path
        source_exists = $exists
        status = $status
        present_patterns = $presentCount
        total_patterns = $Patterns.Count
        expectation = $Expectation
        interpretation = $Interpretation
        patterns = $patternRows.ToArray()
    }
}

function New-SourceAlignment {
    param(
        [string]$Title,
        [string]$RunPath,
        [object[]]$ContractRows,
        [string]$UpstreamRoot
    )

    $upstreamRootPath = Resolve-RepoPath $UpstreamRoot
    $upstreamSpuThread = Join-Path $upstreamRootPath "rpcs3\Emu\Cell\SPUThread.cpp"
    $upstreamLlvm = Join-Path $upstreamRootPath "rpcs3\Emu\Cell\SPULLVMRecompiler.cpp"
    $vendoredSysSpu = Resolve-RepoPath "app\src\main\cpp\rpcsx\kernel\cellos\src\sys_spu.cpp"

    $contractRefs = @($ContractRows | ForEach-Object {
        [pscustomobject]@{
            contract_id = $_.contract_id
            pc = $_.runtime_anchor.pc
            image_sig = $_.runtime_anchor.image_sig
            group = $_.runtime_anchor.group
            spu_name = $_.runtime_anchor.spu_name
        }
    })

    $features = New-Object System.Collections.Generic.List[object]
    $features.Add((Test-SourceFeature `
        -SourceRole "windows-upstream" `
        -Lane "mfc-descriptor-family-25cc-9e4000" `
        -Name "25cc runtime family predicate" `
        -Path $upstreamSpuThread `
        -Patterns @("get_es_mfc_25cc_runtime_family_raw", "cmd.tag != 31", "cmd.size != 0x4000", "cmd.eal == 0x9e4000", "get_es_mfc_25cc_runtime_family(spu, cmd)") `
        -Expectation "Priority-1 contract can be keyed by image, PC, tag, size, EA family, and command shape." `
        -Interpretation "If present, the next useful change is counter labeling/reject accounting, not inventing a new predicate.")) | Out-Null
    $features.Add((Test-SourceFeature `
        -SourceRole "windows-upstream" `
        -Lane "tcx-spurs-descriptor-family-451c" `
        -Name "451c dynamic list predicate" `
        -Path $upstreamSpuThread `
        -Patterns @("get_es_mfc_451c_dynamic_list_family", "spu->pc != 0x451c", "record_es_mfc_dynamic_cmd") `
        -Expectation "Priority-2 contract can reuse the existing 451c list-family classifier after the 25cc lane is labeled." `
        -Interpretation "Use as a second lane after the 25cc verify counters are explicit.")) | Out-Null
    $features.Add((Test-SourceFeature `
        -SourceRole "windows-upstream" `
        -Lane "verify-only-emulator-counters" `
        -Name "SPU HLE verify hooks" `
        -Path $upstreamSpuThread `
        -Patterns @("RPCS3_ES_SPU_HLE_VERIFY", "record_es_spu_hle_verify_candidate", "is_es_spu_hle_25cc_shadow_enabled", "is_es_spu_hle_25cc_body_enabled") `
        -Expectation "Verify-only counters should extend existing HLE verification hooks instead of adding fast mode." `
        -Interpretation "Use these hooks for contract-id counters, reject buckets, and source/destination hashes.")) | Out-Null
    $features.Add((Test-SourceFeature `
        -SourceRole "windows-upstream" `
        -Lane "llvm-verify-candidate" `
        -Name "LLVM verify callout" `
        -Path $upstreamLlvm `
        -Patterns @("exec_es_spu_hle_verify_candidate", "pc != 0x25cc", "else if (pc == 0x451c)", "spu_es_hle_verify_candidate") `
        -Expectation "LLVM-generated paths can report the same contract counters as interpreter/MFC paths." `
        -Interpretation "Keep this in verify-only parity before any codegen-fast path.")) | Out-Null
    $features.Add((Test-SourceFeature `
        -SourceRole "vendored-rpcsx-core" `
        -Lane "generic-dma-probe" `
        -Name "Thor generic DMA probe" `
        -Path $vendoredSysSpu `
        -Patterns @("thor_es_dma_superpath_mode", "record_thor_es_dma_seen", "log_thor_es_dma_probe") `
        -Expectation "Vendored core has generic DMA profiling, but this is not the 25cc/451c contract lane." `
        -Interpretation "Do not port or enable Android fast paths during the Windows gate; use this only as later porting context.")) | Out-Null
    $features.Add((Test-SourceFeature `
        -SourceRole "vendored-rpcsx-core" `
        -Lane "mfc-descriptor-family-25cc-9e4000" `
        -Name "Vendored 25cc/451c contract predicates" `
        -Path $vendoredSysSpu `
        -Patterns @("get_es_mfc_25cc_runtime_family_raw", "get_es_mfc_451c_dynamic_list_family", "record_es_mfc_dynamic_cmd") `
        -Expectation "These should remain absent or partial until Windows proof is clean enough to port." `
        -Interpretation "Current vendored core is not the implementation target for this heartbeat lane.")) | Out-Null

    return [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        title_id = $Title
        source_run = $RunPath
        classification = @("analysis", "source-alignment")
        contracts = $contractRefs
        sources = @(
            [pscustomobject]@{ role = "windows-upstream"; file = $upstreamSpuThread; exists = (Test-Path -LiteralPath $upstreamSpuThread -PathType Leaf) },
            [pscustomobject]@{ role = "windows-upstream-llvm"; file = $upstreamLlvm; exists = (Test-Path -LiteralPath $upstreamLlvm -PathType Leaf) },
            [pscustomobject]@{ role = "vendored-rpcsx-core"; file = $vendoredSysSpu; exists = (Test-Path -LiteralPath $vendoredSysSpu -PathType Leaf) }
        )
        features = $features.ToArray()
        conclusions = @(
            "The Windows upstream source already contains the priority-1 25cc runtime-family predicate for the 0x9e4000 descriptor family.",
            "The Windows upstream source also contains the 451c dynamic-list classifier, but it should stay priority 2.",
            "The vendored RPCSX core currently has a generic Thor DMA probe, not the Windows 25cc/451c contract predicate lane.",
            "The next non-duplicative implementation step is explicit verify-only contract counters and reject buckets in the Windows upstream hooks."
        )
        next_action = "Add contract-id labeled verify-only counters for mfc-descriptor-family-25cc-9e4000, then re-run field, Options/menu, and first-battle gates before any fast path."
    }
}

function New-VerifyCounterSchema {
    param(
        [string]$Title,
        [string]$RunPath,
        [object[]]$ContractRows
    )

    $priorityContract = @($ContractRows | Where-Object { (Normalize-HexKey $_.runtime_anchor.pc) -eq "25cc" } | Select-Object -First 1)
    if (-not $priorityContract) {
        $priorityContract = @($ContractRows | Select-Object -First 1)
    }

    return [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        title_id = $Title
        source_run = $RunPath
        classification = @("analysis", "verify-counter-schema")
        lane = "mfc-descriptor-family-25cc-9e4000"
        contract_id = $priorityContract.contract_id
        mode = "verify-only"
        required_environment = [pscustomobject]@{
            RPCS3_ES_SPU_HLE_VERIFY = "verify-25cc-shadow"
            RPCS3_ES_SPU_HLE_25CC_BODY = "disabled-or-verify-only"
            blocked_values = @(
                "RPCS3_ES_SPU_HLE_VERIFY=skip",
                "RPCS3_ES_SPU_HLE_VERIFY=fast",
                "RPCS3_ES_SPU_HLE_25CC_BODY=fast",
                "RPCS3_ES_GPU_PROBE=fast",
                "vulkan-compute-fast-path"
            )
        }
        contract_predicate = @(
            [pscustomobject]@{ field = "title_id"; op = "equals"; value = "BLUS30161"; reject_bucket = "reject_title" },
            [pscustomobject]@{ field = "image_sig"; op = "equals"; value = "0x958dfe208b686622"; reject_bucket = "reject_image_sig" },
            [pscustomobject]@{ field = "pc"; op = "equals"; value = "0x25cc"; reject_bucket = "reject_pc" },
            [pscustomobject]@{ field = "group"; op = "equals"; value = "CellSpursKernelGroup"; reject_bucket = "reject_group" },
            [pscustomobject]@{ field = "spu_name"; op = "equals"; value = "CellSpursKernel0"; reject_bucket = "reject_spu_name" },
            [pscustomobject]@{ field = "base_cmd"; op = "in"; value = @("MFC_GET_CMD", "MFC_PUT_CMD"); reject_bucket = "reject_cmd" },
            [pscustomobject]@{ field = "list_bit"; op = "equals"; value = $false; reject_bucket = "reject_list" },
            [pscustomobject]@{ field = "tag"; op = "equals"; value = 31; reject_bucket = "reject_tag" },
            [pscustomobject]@{ field = "size"; op = "equals"; value = "0x4000"; reject_bucket = "reject_size" },
            [pscustomobject]@{ field = "eah"; op = "equals"; value = "0x0"; reject_bucket = "reject_eah" },
            [pscustomobject]@{ field = "eal"; op = "equals"; value = "0x9e4000"; reject_bucket = "reject_eal_family" },
            [pscustomobject]@{ field = "lsa"; op = "local-store-range"; value = "lsa + size <= SPU_LS_SIZE"; reject_bucket = "reject_lsa_range" },
            [pscustomobject]@{ field = "mfc_transfers_shuffling"; op = "equals"; value = $false; reject_bucket = "reject_mfc_shuffle" },
            [pscustomobject]@{ field = "spu_accurate_dma"; op = "equals"; value = $false; reject_bucket = "reject_accurate_dma" },
            [pscustomobject]@{ field = "fast_mode"; op = "equals"; value = $false; reject_bucket = "reject_fast_mode" }
        )
        existing_upstream_counters = @(
            "spu_hle_25cc_family_hits",
            "spu_hle_25cc_family_success",
            "spu_hle_25cc_family_fail",
            "spu_hle_25cc_family_bytes",
            "spu_hle_25cc_family_total_us",
            "spu_hle_25cc_family_max_total_us",
            "spu_hle_25cc_family_get_hits",
            "spu_hle_25cc_family_put_hits",
            "spu_hle_25cc_family_ea9e4000_hits",
            "spu_hle_25cc_family_ea4f0b80_hits",
            "spu_hle_25cc_family_exact_a1c000_hits",
            "spu_hle_25cc_family_other_ea_hits",
            "spu_hle_25cc_family_last_family",
            "spu_hle_25cc_family_last_pc",
            "spu_hle_25cc_family_last_cmd",
            "spu_hle_25cc_family_last_tag",
            "spu_hle_25cc_family_last_size",
            "spu_hle_25cc_family_last_lsa",
            "spu_hle_25cc_family_last_eal",
            "spu_hle_25cc_shadow_hits",
            "spu_hle_25cc_shadow_bytes",
            "spu_hle_25cc_shadow_get_hits",
            "spu_hle_25cc_shadow_put_hits",
            "spu_hle_25cc_shadow_ea9e4000_hits",
            "spu_hle_25cc_shadow_src_repeats",
            "spu_hle_25cc_shadow_dst_pre_repeats",
            "spu_hle_25cc_shadow_dst_post_repeats",
            "spu_hle_25cc_shadow_dst_changed",
            "spu_hle_25cc_shadow_dst_unchanged",
            "spu_hle_25cc_shadow_output_match",
            "spu_hle_25cc_shadow_output_mismatch",
            "spu_hle_25cc_shadow_last_src_hash",
            "spu_hle_25cc_shadow_last_dst_pre_hash",
            "spu_hle_25cc_shadow_last_dst_post_hash",
            "spu_hle_25cc_shadow_desc_overflow",
            "spu_hle_25cc_body_put_rejects"
        )
        counters_to_add_or_label = @(
            "contract_id=mfc-descriptor-family-25cc-9e4000",
            "contract_hits",
            "contract_bytes",
            "contract_get_hits",
            "contract_put_hits",
            "contract_reject_total",
            "reject_title",
            "reject_image_sig",
            "reject_pc",
            "reject_group",
            "reject_spu_name",
            "reject_cmd",
            "reject_list",
            "reject_tag",
            "reject_size",
            "reject_eah",
            "reject_eal_family",
            "reject_lsa_range",
            "reject_mfc_shuffle",
            "reject_accurate_dma",
            "reject_fast_mode",
            "last_src_hash",
            "last_dst_pre_hash",
            "last_dst_post_hash"
        )
        parser_acceptance = @(
            "contract_id is present in the log row",
            "contract_hits == spu_hle_25cc_family_ea9e4000_hits for the 0x9e4000 lane",
            "contract_hits == contract_get_hits + contract_put_hits",
            "spu_hle_25cc_shadow_output_mismatch == 0",
            "spu_hle_25cc_shadow_desc_overflow == 0",
            "fatal_log_hits == 0",
            "visual_gate in field, Options/menu, and first-battle is clean before promotion"
        )
        implementation_sites = @(
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\SPUThread.h"; area = "es_gpu_probe_state_t"; action = "add contract-id/reject bucket fields only if log labeling cannot derive them" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\SPUThread.cpp"; area = "get_es_mfc_25cc_runtime_family_raw"; action = "preserve predicate; optionally split reject reasons in a verify-only helper" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\SPUThread.cpp"; area = "record_es_mfc_dynamic_cmd"; action = "label 0x9e4000 family rows with contract_id and reject buckets" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\SPUThread.cpp"; area = "record_es_spu_hle_25cc_shadow_sample"; action = "reuse src/dst hashes, mismatch, descriptor overflow, and direction fields" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; area = "probe log dump"; action = "emit contract_id, reject buckets, existing family counters, shadow hashes, mismatch, and overflow in one parseable row" }
        )
        promotion_blockers = @(
            "Any nonzero output mismatch",
            "Any nonzero descriptor overflow",
            "Any fatal/access/device-lost/assertion log hit",
            "Any black, wrong-window, loading-only, corrupt, crash-overlay, or nonfield visual where field/menu/battle is required",
            "Any fast/body/codegen/Vulkan mode enabled before verify-only proof"
        )
        next_action = "Implement the log-label/reject-bucket row for the priority-1 lane; do not change copy/body behavior."
    }
}

function New-VerifyLogRowImplementation {
    param(
        [string]$Title,
        [string]$RunPath,
        [object]$CounterSchema
    )

    $contractId = $CounterSchema.contract_id
    $lane = $CounterSchema.lane
    $logPrefix = "Eternal Sonata SPU contract verifier"

    return [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        title_id = $Title
        source_run = $RunPath
        classification = @("analysis", "verify-logrow-implementation-scaffold")
        lane = $lane
        contract_id = $contractId
        source_context = [pscustomobject]@{
            upstream_checkout = "C:\Users\leanerdesigner\Documents\New project 6\rpcs3-upstream"
            note = "Do not apply automatically when the upstream checkout is dirty. This scaffold is log-only and does not change copy/body behavior."
        }
        existing_log_rows = @(
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; row = "Eternal Sonata SPU HLE 25cc family verifier"; use = "family hits, bytes, GET/PUT split, EA-family split, last command fields" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; row = "Eternal Sonata SPU HLE 25cc shadow verifier"; use = "shadow hits, hashes, output match/mismatch, descriptor overflow context" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; row = "Eternal Sonata SPU HLE 25cc shadow descriptor"; use = "per-descriptor family, direction, command shape, hashes, mismatch, overflow" },
            [pscustomobject]@{ file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; row = "Eternal Sonata SPU HLE 25cc body verifier"; use = "body verify/fast guard visibility and PUT rejects" }
        )
        target_log_row = [pscustomobject]@{
            prefix = $logPrefix
            hle_mode = "contract-25cc-9e4000"
            format_keys = @(
                "hle_mode",
                "contract_id",
                "title",
                "mode",
                "verify_mode",
                "body_mode",
                "group_name",
                "spu_name",
                "entry",
                "image_sig",
                "pc",
                "tag",
                "size",
                "eal",
                "contract_hits",
                "contract_bytes",
                "contract_get_hits",
                "contract_put_hits",
                "contract_reject_total",
                "reject_title",
                "reject_image_sig",
                "reject_pc",
                "reject_group",
                "reject_spu_name",
                "reject_cmd",
                "reject_list",
                "reject_tag",
                "reject_size",
                "reject_eah",
                "reject_eal_family",
                "reject_lsa_range",
                "reject_mfc_shuffle",
                "reject_accurate_dma",
                "reject_fast_mode",
                "output_mismatch",
                "desc_overflow",
                "last_src_hash",
                "last_dst_pre_hash",
                "last_dst_post_hash",
                "cause",
                "status"
            )
            example = "Eternal Sonata SPU contract verifier: hle_mode=contract-25cc-9e4000 contract_id=$contractId title=BLUS30161 mode=profile verify_mode=verify-25cc-shadow body_mode=disabled group_name=`"CellSpursKernelGroup`" spu_name=`"CellSpursKernel0`" entry=0x0 image_sig=0x958dfe208b686622 pc=0x25cc tag=31 size=16384 eal=0x9e4000 contract_hits=0 contract_bytes=0 contract_get_hits=0 contract_put_hits=0 contract_reject_total=0 reject_title=0 reject_image_sig=0 reject_pc=0 reject_group=0 reject_spu_name=0 reject_cmd=0 reject_list=0 reject_tag=0 reject_size=0 reject_eah=0 reject_eal_family=0 reject_lsa_range=0 reject_mfc_shuffle=0 reject_accurate_dma=0 reject_fast_mode=0 output_mismatch=0 desc_overflow=0 last_src_hash=0x0 last_dst_pre_hash=0x0 last_dst_post_hash=0x0 cause=0x0 status=0x0"
        }
        derived_from_existing = @(
            [pscustomobject]@{ target = "contract_hits"; source = "spu_hle_25cc_shadow_ea9e4000_hits or sum(desc.hits where desc.family == 1)" },
            [pscustomobject]@{ target = "contract_bytes"; source = "sum(desc.bytes where desc.family == 1 and desc.eal == 0x9e4000)" },
            [pscustomobject]@{ target = "contract_get_hits"; source = "sum(desc.hits where desc.family == 1 and desc.direction == 1)" },
            [pscustomobject]@{ target = "contract_put_hits"; source = "sum(desc.hits where desc.family == 1 and desc.direction == 2)" },
            [pscustomobject]@{ target = "output_mismatch"; source = "spu_hle_25cc_shadow_output_mismatch or sum matching descriptor output_mismatch" },
            [pscustomobject]@{ target = "desc_overflow"; source = "spu_hle_25cc_shadow_desc_overflow" },
            [pscustomobject]@{ target = "last_src_hash"; source = "spu_hle_25cc_shadow_last_src_hash" },
            [pscustomobject]@{ target = "last_dst_pre_hash"; source = "spu_hle_25cc_shadow_last_dst_pre_hash" },
            [pscustomobject]@{ target = "last_dst_post_hash"; source = "spu_hle_25cc_shadow_last_dst_post_hash" }
        )
        reject_bucket_strategy = @(
            [pscustomobject]@{ bucket = "reject_title"; source = "derived before title gate; should stay zero inside BLUS30161-only logger" },
            [pscustomobject]@{ bucket = "reject_image_sig"; source = "increment when image_sig != 0x958dfe208b686622" },
            [pscustomobject]@{ bucket = "reject_pc"; source = "increment when pc != 0x25cc" },
            [pscustomobject]@{ bucket = "reject_group"; source = "increment when group_name != CellSpursKernelGroup" },
            [pscustomobject]@{ bucket = "reject_spu_name"; source = "increment when spu_name != CellSpursKernel0" },
            [pscustomobject]@{ bucket = "reject_cmd"; source = "increment when base command is not MFC GET or PUT" },
            [pscustomobject]@{ bucket = "reject_list"; source = "increment when MFC list bit is set" },
            [pscustomobject]@{ bucket = "reject_tag"; source = "increment when tag != 31" },
            [pscustomobject]@{ bucket = "reject_size"; source = "increment when size != 0x4000" },
            [pscustomobject]@{ bucket = "reject_eah"; source = "increment when eah != 0" },
            [pscustomobject]@{ bucket = "reject_eal_family"; source = "increment when eal != 0x9e4000 for this priority-1 row" },
            [pscustomobject]@{ bucket = "reject_lsa_range"; source = "increment when lsa + size exceeds SPU_LS_SIZE" },
            [pscustomobject]@{ bucket = "reject_mfc_shuffle"; source = "increment when MFC transfer shuffling is enabled" },
            [pscustomobject]@{ bucket = "reject_accurate_dma"; source = "increment when accurate DMA is enabled" },
            [pscustomobject]@{ bucket = "reject_fast_mode"; source = "increment when verify skip/fast, 25cc body fast, GPU fast, or Vulkan compute fast path is active" }
        )
        implementation_order = @(
            [pscustomobject]@{ step = 1; file = "rpcs3\Emu\Cell\lv2\sys_spu.cpp"; action = "emit one additional parseable notice row after the existing 25cc shadow descriptor rows" },
            [pscustomobject]@{ step = 2; file = "rpcs3\Emu\Cell\SPUThread.cpp"; action = "if reject buckets cannot be derived at dump time, add a verify-only classifier helper that mirrors get_es_mfc_25cc_runtime_family_raw without changing behavior" },
            [pscustomobject]@{ step = 3; file = "rpcs3\Emu\Cell\SPUThread.h"; action = "add persistent reject-bucket counters only if the dump-time derivation is insufficient" },
            [pscustomobject]@{ step = 4; file = "tools/windows log parser"; action = "accept only rows with contract_id=mfc-descriptor-family-25cc-9e4000 and hle_mode=contract-25cc-9e4000" }
        )
        acceptance_checks = @(
            "No memcpy/body/fast path behavior changes in the first patch.",
            "The row appears under RPCS3_ES_SPU_HLE_VERIFY=verify-25cc-shadow.",
            "The row does not appear under blocked fast modes except as reject_fast_mode > 0.",
            "contract_hits equals contract_get_hits + contract_put_hits.",
            "output_mismatch == 0 and desc_overflow == 0 are required before any promotion.",
            "Field, Options/menu, and first-battle visual gates are still required."
        )
        next_action = "Apply the log-only row in the Windows upstream checkout after isolating or stashing unrelated upstream changes; then run field/Options/first-battle verifier captures."
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
$summary.Add("Source alignment: $($bt)source-alignment.md$bt.") | Out-Null
$summary.Add("Verify counter schema: $($bt)verify-counter-schema.md$bt.") | Out-Null
$summary.Add("Verify log-row scaffold: $($bt)verify-logrow-implementation.md$bt.") | Out-Null
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

$sourceAlignment = New-SourceAlignment -Title $TitleId -RunPath $runPath -ContractRows ($contractDetails.ToArray()) -UpstreamRoot $UpstreamSourceRoot
$sourceAlignmentPath = Join-Path $outRoot "source-alignment.json"
$sourceAlignment | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sourceAlignmentPath -Encoding UTF8

$sourceMdPath = Join-Path $outRoot "source-alignment.md"
$sourceMd = New-Object System.Collections.Generic.List[string]
$sourceMd.Add("# SPU Contract Source Alignment") | Out-Null
$sourceMd.Add("") | Out-Null
$sourceMd.Add("- Generated: $bt$generatedAt$bt") | Out-Null
$sourceMd.Add("- Title: $bt$TitleId$bt") | Out-Null
$sourceMd.Add("- Source run: $bt$runPath$bt") | Out-Null
$sourceMd.Add("- Classification: $($bt)analysis$bt, $($bt)source-alignment$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
$sourceMd.Add("") | Out-Null
$sourceMd.Add("| Source | Lane | Feature | Status | Patterns |") | Out-Null
$sourceMd.Add("| --- | --- | --- | --- | ---: |") | Out-Null
foreach ($feature in $sourceAlignment.features) {
    $sourceMd.Add("| $bt$($feature.source_role)$bt | $bt$($feature.lane)$bt | $bt$($feature.feature)$bt | $bt$($feature.status)$bt | $($feature.present_patterns)/$($feature.total_patterns) |") | Out-Null
}
$sourceMd.Add("") | Out-Null
$sourceMd.Add("## Conclusions") | Out-Null
foreach ($conclusion in $sourceAlignment.conclusions) {
    $sourceMd.Add("- $conclusion") | Out-Null
}
$sourceMd.Add("") | Out-Null
$sourceMd.Add("## Pattern Lines") | Out-Null
foreach ($feature in $sourceAlignment.features) {
    $sourceMd.Add("") | Out-Null
    $sourceMd.Add("### $($feature.source_role): $($feature.feature)") | Out-Null
    $sourceMd.Add("") | Out-Null
    $sourceMd.Add("- File: $bt$($feature.file)$bt") | Out-Null
    $sourceMd.Add("- Expectation: $($feature.expectation)") | Out-Null
    $sourceMd.Add("- Interpretation: $($feature.interpretation)") | Out-Null
    foreach ($patternRow in $feature.patterns) {
        $lineText = if ($patternRow.present) { "line $($patternRow.line)" } else { "missing" }
        $sourceMd.Add("- $bt$($patternRow.pattern)${bt}: $lineText") | Out-Null
    }
}
$sourceMd.Add("") | Out-Null
$sourceMd.Add("Next action: $($sourceAlignment.next_action)") | Out-Null
$sourceMd | Set-Content -LiteralPath $sourceMdPath -Encoding UTF8

$counterSchema = New-VerifyCounterSchema -Title $TitleId -RunPath $runPath -ContractRows ($contractDetails.ToArray())
$counterSchemaPath = Join-Path $outRoot "verify-counter-schema.json"
$counterSchema | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $counterSchemaPath -Encoding UTF8

$counterMdPath = Join-Path $outRoot "verify-counter-schema.md"
$counterMd = New-Object System.Collections.Generic.List[string]
$counterMd.Add("# SPU Verify Counter Schema") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("- Generated: $bt$generatedAt$bt") | Out-Null
$counterMd.Add("- Title: $bt$TitleId$bt") | Out-Null
$counterMd.Add("- Source run: $bt$runPath$bt") | Out-Null
$counterMd.Add("- Lane: $bt$($counterSchema.lane)$bt") | Out-Null
$counterMd.Add("- Contract: $bt$($counterSchema.contract_id)$bt") | Out-Null
$counterMd.Add("- Classification: $($bt)analysis$bt, $($bt)verify-counter-schema$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("## Required Environment") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("- $($bt)RPCS3_ES_SPU_HLE_VERIFY=$($counterSchema.required_environment.RPCS3_ES_SPU_HLE_VERIFY)$bt") | Out-Null
$counterMd.Add("- $($bt)RPCS3_ES_SPU_HLE_25CC_BODY=$($counterSchema.required_environment.RPCS3_ES_SPU_HLE_25CC_BODY)$bt") | Out-Null
$counterMd.Add("- Blocked: $bt$($counterSchema.required_environment.blocked_values -join ', ')$bt") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("## Predicate And Reject Buckets") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("| Field | Op | Value | Reject bucket |") | Out-Null
$counterMd.Add("| --- | --- | --- | --- |") | Out-Null
foreach ($predicate in $counterSchema.contract_predicate) {
    $valueText = if ($predicate.value -is [array]) { $predicate.value -join "," } else { [string]$predicate.value }
    $counterMd.Add("| $bt$($predicate.field)$bt | $bt$($predicate.op)$bt | $bt$valueText$bt | $bt$($predicate.reject_bucket)$bt |") | Out-Null
}
$counterMd.Add("") | Out-Null
$counterMd.Add("## Existing Upstream Counters") | Out-Null
foreach ($counter in $counterSchema.existing_upstream_counters) {
    $counterMd.Add("- $bt$counter$bt") | Out-Null
}
$counterMd.Add("") | Out-Null
$counterMd.Add("## Counters To Add Or Label") | Out-Null
foreach ($counter in $counterSchema.counters_to_add_or_label) {
    $counterMd.Add("- $bt$counter$bt") | Out-Null
}
$counterMd.Add("") | Out-Null
$counterMd.Add("## Parser Acceptance") | Out-Null
foreach ($rule in $counterSchema.parser_acceptance) {
    $counterMd.Add("- $rule") | Out-Null
}
$counterMd.Add("") | Out-Null
$counterMd.Add("## Implementation Sites") | Out-Null
$counterMd.Add("") | Out-Null
$counterMd.Add("| File | Area | Action |") | Out-Null
$counterMd.Add("| --- | --- | --- |") | Out-Null
foreach ($site in $counterSchema.implementation_sites) {
    $counterMd.Add("| $bt$($site.file)$bt | $bt$($site.area)$bt | $($site.action) |") | Out-Null
}
$counterMd.Add("") | Out-Null
$counterMd.Add("Next action: $($counterSchema.next_action)") | Out-Null
$counterMd | Set-Content -LiteralPath $counterMdPath -Encoding UTF8

$logRowImplementation = New-VerifyLogRowImplementation -Title $TitleId -RunPath $runPath -CounterSchema $counterSchema
$logRowPath = Join-Path $outRoot "verify-logrow-implementation.json"
$logRowImplementation | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $logRowPath -Encoding UTF8

$logRowMdPath = Join-Path $outRoot "verify-logrow-implementation.md"
$logRowMd = New-Object System.Collections.Generic.List[string]
$logRowMd.Add("# SPU Verify Log-Row Implementation Scaffold") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("- Generated: $bt$generatedAt$bt") | Out-Null
$logRowMd.Add("- Title: $bt$TitleId$bt") | Out-Null
$logRowMd.Add("- Source run: $bt$runPath$bt") | Out-Null
$logRowMd.Add("- Lane: $bt$($logRowImplementation.lane)$bt") | Out-Null
$logRowMd.Add("- Contract: $bt$($logRowImplementation.contract_id)$bt") | Out-Null
$logRowMd.Add("- Classification: $($bt)analysis$bt, $($bt)verify-logrow-implementation-scaffold$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Target Row") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("- Prefix: $bt$($logRowImplementation.target_log_row.prefix)$bt") | Out-Null
$logRowMd.Add("- HLE mode: $bt$($logRowImplementation.target_log_row.hle_mode)$bt") | Out-Null
$logRowMd.Add("- Example: $bt$($logRowImplementation.target_log_row.example)$bt") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("Required keys:") | Out-Null
foreach ($key in $logRowImplementation.target_log_row.format_keys) {
    $logRowMd.Add("- $bt$key$bt") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Existing Rows To Reuse") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("| Row | File | Use |") | Out-Null
$logRowMd.Add("| --- | --- | --- |") | Out-Null
foreach ($row in $logRowImplementation.existing_log_rows) {
    $logRowMd.Add("| $bt$($row.row)$bt | $bt$($row.file)$bt | $($row.use) |") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Derived Fields") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("| Target | Source |") | Out-Null
$logRowMd.Add("| --- | --- |") | Out-Null
foreach ($field in $logRowImplementation.derived_from_existing) {
    $logRowMd.Add("| $bt$($field.target)$bt | $($field.source) |") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Reject Buckets") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("| Bucket | Source |") | Out-Null
$logRowMd.Add("| --- | --- |") | Out-Null
foreach ($bucket in $logRowImplementation.reject_bucket_strategy) {
    $logRowMd.Add("| $bt$($bucket.bucket)$bt | $($bucket.source) |") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Implementation Order") | Out-Null
$logRowMd.Add("") | Out-Null
$logRowMd.Add("| Step | File | Action |") | Out-Null
$logRowMd.Add("| ---: | --- | --- |") | Out-Null
foreach ($step in $logRowImplementation.implementation_order) {
    $logRowMd.Add("| $($step.step) | $bt$($step.file)$bt | $($step.action) |") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("## Acceptance Checks") | Out-Null
foreach ($check in $logRowImplementation.acceptance_checks) {
    $logRowMd.Add("- $check") | Out-Null
}
$logRowMd.Add("") | Out-Null
$logRowMd.Add("Next action: $($logRowImplementation.next_action)") | Out-Null
$logRowMd | Set-Content -LiteralPath $logRowMdPath -Encoding UTF8

Write-Output "SPU contract index: $indexPath"
Write-Output "SPU contract summary: $summaryPath"
Write-Output "SPU verify plan: $verifyPlanPath"
Write-Output "SPU verify plan summary: $verifyMdPath"
Write-Output "SPU source alignment: $sourceAlignmentPath"
Write-Output "SPU source alignment summary: $sourceMdPath"
Write-Output "SPU verify counter schema: $counterSchemaPath"
Write-Output "SPU verify counter schema summary: $counterMdPath"
Write-Output "SPU verify log-row scaffold: $logRowPath"
Write-Output "SPU verify log-row scaffold summary: $logRowMdPath"
