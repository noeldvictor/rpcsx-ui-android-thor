param(
    [string]$LogPath = "",
    [string[]]$InputLine = @(),
    [string]$SchemaPath = "spu-contracts\BLUS30161\verify-logrow-implementation.json",
    [string]$PromotionScorePath = "spu-contracts\BLUS30161\promotion-score.json",
    [string]$OutJson = "",
    [string]$OutMarkdown = "",
    [switch]$RequireAcceptedRow,
    [switch]$RequireNoRejected,
    [switch]$RequirePromotionScore,
    [switch]$RequireCpuHleRecommendation,
    [ValidateSet("Any", "Full", "Sampled", "Counts")]
    [string]$RequiredPayloadMode = "Any",
    [Int64]$MinContractHits = 0,
    [switch]$FailOnGate
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Convert-Scalar {
    param([string]$Value)
    if ($Value -match '^0x[0-9a-fA-F]+$') {
        return $Value.ToLowerInvariant()
    }
    $num = 0L
    if ([Int64]::TryParse($Value, [ref]$num)) {
        return $num
    }
    return $Value
}

function Parse-ContractLine {
    param([string]$Line)
    $fields = [ordered]@{}
    foreach ($match in [regex]::Matches($Line, '(?<key>[A-Za-z0-9_]+)=(?:"(?<quoted>[^"]*)"|(?<value>\S+))')) {
        $raw = if ($match.Groups["quoted"].Success) { $match.Groups["quoted"].Value } else { $match.Groups["value"].Value }
        $fields[$match.Groups["key"].Value] = Convert-Scalar $raw
    }
    return [pscustomobject]$fields
}

$schemaFullPath = Resolve-RepoPath $SchemaPath
if (-not (Test-Path -LiteralPath $schemaFullPath -PathType Leaf)) {
    throw "Schema not found: $schemaFullPath"
}

$schema = Get-Content -Raw -LiteralPath $schemaFullPath | ConvertFrom-Json
$prefix = [string]$schema.target_log_row.prefix
$expectedHleMode = [string]$schema.target_log_row.hle_mode
$expectedContractId = [string]$schema.contract_id
$requiredKeys = @($schema.target_log_row.format_keys)
$expectedFields = $schema.target_log_row.expected_fields
$blockedFields = $schema.target_log_row.blocked_fields
$bytesPerHit = if ($schema.target_log_row.bytes_per_hit) { [Int64]$schema.target_log_row.bytes_per_hit } else { 0L }
$rejectBucketKeys = @($schema.target_log_row.reject_bucket_keys)

$promotionFullPath = Resolve-RepoPath $PromotionScorePath
$promotionRow = $null
if (Test-Path -LiteralPath $promotionFullPath -PathType Leaf) {
    $promotionScore = Get-Content -Raw -LiteralPath $promotionFullPath | ConvertFrom-Json
    $promotionRow = @($promotionScore.rows | Where-Object { [string]$_.contract_id -eq $expectedContractId } | Select-Object -First 1)
}

$lines = New-Object System.Collections.Generic.List[string]
foreach ($line in $InputLine) {
    if ((-not [string]::IsNullOrWhiteSpace($line)) -and ($line -like "*$prefix*")) {
        $lines.Add($line) | Out-Null
    }
}

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $logFullPath = Resolve-RepoPath $LogPath
    if (-not (Test-Path -LiteralPath $logFullPath -PathType Leaf)) {
        throw "Log not found: $logFullPath"
    }
    foreach ($line in Get-Content -LiteralPath $logFullPath) {
        if ($line -like "*$prefix*") {
            $lines.Add($line) | Out-Null
        }
    }
}

if ($lines.Count -eq 0) {
    $result = [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        classification = @("analysis", "verify-logrow-parser")
        source = $(if ($LogPath) { Resolve-RepoPath $LogPath } else { "input-lines" })
        contract_id = $expectedContractId
        hle_mode = $expectedHleMode
        rows = 0
        accepted_rows = 0
        rejected_rows = 0
        total_contract_hits = 0
        total_contract_bytes = 0
        total_contract_rejects = 0
        total_output_mismatch = 0
        total_desc_overflow = 0
        missing_required_keys = @()
        failures = @("no contract verifier rows found")
        promotion_ready = $false
    }
} else {
    $parsedRows = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[string]
    $accepted = 0
    $totalHits = 0L
    $totalBytes = 0L
    $totalRejects = 0L
    $totalMismatch = 0L
    $totalOverflow = 0L
    $missingGlobal = New-Object System.Collections.Generic.HashSet[string]

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $row = Parse-ContractLine -Line $lines[$i]
        $rowFailures = New-Object System.Collections.Generic.List[string]
        foreach ($key in $requiredKeys) {
            if (-not $row.PSObject.Properties.Name.Contains($key)) {
                $rowFailures.Add("missing:$key") | Out-Null
                $missingGlobal.Add($key) | Out-Null
            }
        }

        if (($row.PSObject.Properties.Name.Contains("hle_mode")) -and ([string]$row.hle_mode -ne $expectedHleMode)) {
            $rowFailures.Add("wrong_hle_mode:$($row.hle_mode)") | Out-Null
        }
        if (($row.PSObject.Properties.Name.Contains("contract_id")) -and ([string]$row.contract_id -ne $expectedContractId)) {
            $rowFailures.Add("wrong_contract_id:$($row.contract_id)") | Out-Null
        }

        if ($expectedFields) {
            foreach ($expected in $expectedFields.PSObject.Properties) {
                $key = [string]$expected.Name
                if ($row.PSObject.Properties.Name.Contains($key)) {
                    $actual = [string]$row.$key
                    $wanted = [string](Convert-Scalar ([string]$expected.Value))
                    if ($actual -cne $wanted) {
                        $rowFailures.Add("wrong_${key}:$actual") | Out-Null
                    }
                }
            }
        }

        if ($blockedFields) {
            foreach ($blocked in $blockedFields.PSObject.Properties) {
                $key = [string]$blocked.Name
                if ($row.PSObject.Properties.Name.Contains($key)) {
                    $actual = [string]$row.$key
                    if (@($blocked.Value) -contains $actual) {
                        $rowFailures.Add("blocked_${key}:$actual") | Out-Null
                    }
                }
            }
        }

        $hits = if ($row.PSObject.Properties.Name.Contains("contract_hits")) { [Int64]$row.contract_hits } else { 0L }
        $bytes = if ($row.PSObject.Properties.Name.Contains("contract_bytes")) { [Int64]$row.contract_bytes } else { 0L }
        $getHits = if ($row.PSObject.Properties.Name.Contains("contract_get_hits")) { [Int64]$row.contract_get_hits } else { 0L }
        $putHits = if ($row.PSObject.Properties.Name.Contains("contract_put_hits")) { [Int64]$row.contract_put_hits } else { 0L }
        $contractRejects = if ($row.PSObject.Properties.Name.Contains("contract_reject_total")) { [Int64]$row.contract_reject_total } else { 0L }
        $mismatch = if ($row.PSObject.Properties.Name.Contains("output_mismatch")) { [Int64]$row.output_mismatch } else { 0L }
        $overflow = if ($row.PSObject.Properties.Name.Contains("desc_overflow")) { [Int64]$row.desc_overflow } else { 0L }

        if (($row.PSObject.Properties.Name.Contains("contract_hits")) -and ($row.PSObject.Properties.Name.Contains("contract_get_hits")) -and ($row.PSObject.Properties.Name.Contains("contract_put_hits")) -and ($hits -ne ($getHits + $putHits))) {
            $rowFailures.Add("hit_split_mismatch") | Out-Null
        }
        if (($bytesPerHit -gt 0) -and ($row.PSObject.Properties.Name.Contains("contract_bytes")) -and ($bytes -ne ($hits * $bytesPerHit))) {
            $rowFailures.Add("contract_bytes_mismatch") | Out-Null
        }
        if (($rejectBucketKeys.Count -gt 0) -and ($row.PSObject.Properties.Name.Contains("contract_reject_total"))) {
            $rejectSum = 0L
            $haveAllRejectBuckets = $true
            foreach ($key in $rejectBucketKeys) {
                if ($row.PSObject.Properties.Name.Contains($key)) {
                    $rejectSum += [Int64]$row.$key
                } else {
                    $haveAllRejectBuckets = $false
                }
            }
            if ($haveAllRejectBuckets -and ($contractRejects -ne $rejectSum)) {
                $rowFailures.Add("reject_total_mismatch") | Out-Null
            }
        }
        if (($row.PSObject.Properties.Name.Contains("reject_fast_mode")) -and ([Int64]$row.reject_fast_mode -ne 0)) {
            $rowFailures.Add("fast_mode_rejected") | Out-Null
        }
        if ($mismatch -ne 0) {
            $rowFailures.Add("output_mismatch_nonzero") | Out-Null
        }
        if ($overflow -ne 0) {
            $rowFailures.Add("desc_overflow_nonzero") | Out-Null
        }

        $acceptedRow = $rowFailures.Count -eq 0
        if ($acceptedRow) {
            $accepted++
        } else {
            foreach ($failure in $rowFailures) {
                $failures.Add("row=$($i + 1):$failure") | Out-Null
            }
        }

        $totalHits += $hits
        $totalBytes += $bytes
        $totalRejects += $contractRejects
        $totalMismatch += $mismatch
        $totalOverflow += $overflow
        $parsedRows.Add([pscustomobject]@{
            index = $i + 1
            accepted = $acceptedRow
            failures = @($rowFailures)
            fields = $row
        }) | Out-Null
    }

    $result = [pscustomobject]@{
        schema_version = 1
        generated_at = (Get-Date).ToString("o")
        classification = @("analysis", "verify-logrow-parser")
        source = $(if ($LogPath) { Resolve-RepoPath $LogPath } else { "input-lines" })
        contract_id = $expectedContractId
        hle_mode = $expectedHleMode
        rows = $lines.Count
        accepted_rows = $accepted
        rejected_rows = $lines.Count - $accepted
        total_contract_hits = $totalHits
        total_contract_bytes = $totalBytes
        total_contract_rejects = $totalRejects
        total_output_mismatch = $totalMismatch
        total_desc_overflow = $totalOverflow
        missing_required_keys = @($missingGlobal)
        failures = @($failures)
        promotion_ready = $false
        rows_detail = $parsedRows.ToArray()
    }
}

$promotionAvailable = [bool]$promotionRow
$payloadModeCounts = [ordered]@{}
if ($result.PSObject.Properties.Name.Contains("rows_detail")) {
    foreach ($detail in @($result.rows_detail)) {
        $mode = if ($detail.fields.PSObject.Properties.Name.Contains("payload_mode")) { [string]$detail.fields.payload_mode } else { "missing" }
        if (-not $payloadModeCounts.Contains($mode)) { $payloadModeCounts[$mode] = 0 }
        $payloadModeCounts[$mode]++
    }
}
$result | Add-Member -NotePropertyName payload_mode_counts -NotePropertyValue ([pscustomobject]$payloadModeCounts)
$result | Add-Member -NotePropertyName promotion_score_available -NotePropertyValue $promotionAvailable
$result | Add-Member -NotePropertyName promotion_score_source -NotePropertyValue $promotionFullPath
if ($promotionRow) {
    $result | Add-Member -NotePropertyName recommended_lane -NotePropertyValue ([string]$promotionRow.recommended_lane)
    $result | Add-Member -NotePropertyName cpu_hle_score -NotePropertyValue ([int]$promotionRow.cpu_hle_score)
    $result | Add-Member -NotePropertyName host_simd_score -NotePropertyValue ([int]$promotionRow.host_simd_score)
    $result | Add-Member -NotePropertyName vulkan_gpu_score -NotePropertyValue ([int]$promotionRow.vulkan_gpu_score)
    $result | Add-Member -NotePropertyName readback_risk -NotePropertyValue ([string]$promotionRow.readback_risk)
    $result | Add-Member -NotePropertyName rsx_destination_evidence -NotePropertyValue ([string]$promotionRow.rsx_destination_evidence)
} else {
    $result | Add-Member -NotePropertyName recommended_lane -NotePropertyValue "unknown"
    $result | Add-Member -NotePropertyName cpu_hle_score -NotePropertyValue 0
    $result | Add-Member -NotePropertyName host_simd_score -NotePropertyValue 0
    $result | Add-Member -NotePropertyName vulkan_gpu_score -NotePropertyValue 0
    $result | Add-Member -NotePropertyName readback_risk -NotePropertyValue "unknown"
    $result | Add-Member -NotePropertyName rsx_destination_evidence -NotePropertyValue "unknown"
}

$strictRequested = $RequireAcceptedRow -or $RequireNoRejected -or $RequirePromotionScore -or $RequireCpuHleRecommendation -or ($RequiredPayloadMode -ne "Any") -or ($MinContractHits -gt 0)
$strictFailures = New-Object System.Collections.Generic.List[string]
if ($RequireAcceptedRow -and $result.accepted_rows -lt 1) {
    $strictFailures.Add("accepted_rows_lt_1") | Out-Null
}
if ($RequireNoRejected -and $result.rejected_rows -gt 0) {
    $strictFailures.Add("rejected_rows_nonzero") | Out-Null
}
if (($MinContractHits -gt 0) -and ([Int64]$result.total_contract_hits -lt $MinContractHits)) {
    $strictFailures.Add("contract_hits_lt_$MinContractHits") | Out-Null
}
if ($strictRequested -and ([Int64]$result.total_output_mismatch -ne 0)) {
    $strictFailures.Add("output_mismatch_nonzero") | Out-Null
}
if ($strictRequested -and ([Int64]$result.total_desc_overflow -ne 0)) {
    $strictFailures.Add("desc_overflow_nonzero") | Out-Null
}
if ($RequirePromotionScore -and -not $promotionAvailable) {
    $strictFailures.Add("promotion_score_missing") | Out-Null
}
if ($RequiredPayloadMode -ne "Any") {
    $wantedPayloadMode = $RequiredPayloadMode.ToLowerInvariant()
    $badPayloadRows = 0
    if ($result.PSObject.Properties.Name.Contains("rows_detail")) {
        foreach ($detail in @($result.rows_detail)) {
            if (-not $detail.fields.PSObject.Properties.Name.Contains("payload_mode") -or [string]$detail.fields.payload_mode -ne $wantedPayloadMode) {
                $badPayloadRows++
            }
        }
    } else {
        $badPayloadRows = [int]$result.rows
    }
    if ($badPayloadRows -gt 0) {
        $strictFailures.Add("payload_mode_not_${wantedPayloadMode}:$badPayloadRows") | Out-Null
    }
}
if ($RequireCpuHleRecommendation -and ([string]$result.recommended_lane -ne "verify-only-cpu-hle-or-codegen")) {
    $strictFailures.Add("recommended_lane_not_cpu_hle_or_codegen:$($result.recommended_lane)") | Out-Null
}
$strictGatePass = $strictRequested -and ($strictFailures.Count -eq 0)
$result | Add-Member -NotePropertyName strict_gate_requested -NotePropertyValue $strictRequested
$result | Add-Member -NotePropertyName strict_gate_pass -NotePropertyValue $strictGatePass
$result | Add-Member -NotePropertyName strict_failures -NotePropertyValue @($strictFailures)

if (-not [string]::IsNullOrWhiteSpace($OutJson)) {
    $outJsonPath = Resolve-RepoPath $OutJson
    $parent = Split-Path -Parent $outJsonPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $outJsonPath -Encoding UTF8
}

if (-not [string]::IsNullOrWhiteSpace($OutMarkdown)) {
    $outMdPath = Resolve-RepoPath $OutMarkdown
    $parent = Split-Path -Parent $outMdPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $bt = [char]96
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add("# SPU Contract Verify Log Parse") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("- Generated: $bt$($result.generated_at)$bt") | Out-Null
    $md.Add("- Contract: $bt$($result.contract_id)$bt") | Out-Null
    $md.Add("- HLE mode: $bt$($result.hle_mode)$bt") | Out-Null
    $md.Add("- Rows: $bt$($result.rows)$bt") | Out-Null
    $md.Add("- Accepted rows: $bt$($result.accepted_rows)$bt") | Out-Null
    $md.Add("- Rejected rows: $bt$($result.rejected_rows)$bt") | Out-Null
    $md.Add("- Total hits: $bt$($result.total_contract_hits)$bt") | Out-Null
    $md.Add("- Total bytes: $bt$($result.total_contract_bytes)$bt") | Out-Null
    $md.Add("- Total contract rejects: $bt$($result.total_contract_rejects)$bt") | Out-Null
    $md.Add("- Output mismatch: $bt$($result.total_output_mismatch)$bt") | Out-Null
    $md.Add("- Descriptor overflow: $bt$($result.total_desc_overflow)$bt") | Out-Null
    $md.Add("- Promotion score available: $bt$($result.promotion_score_available)$bt") | Out-Null
    $md.Add("- Recommended lane: $bt$($result.recommended_lane)$bt") | Out-Null
    $md.Add("- CPU/HLE score: $bt$($result.cpu_hle_score)$bt") | Out-Null
    $md.Add("- Host SIMD score: $bt$($result.host_simd_score)$bt") | Out-Null
    $md.Add("- Vulkan/GPU score: $bt$($result.vulkan_gpu_score)$bt") | Out-Null
    $md.Add("- Readback risk: $bt$($result.readback_risk)$bt") | Out-Null
    $md.Add("- RSX destination evidence: $bt$($result.rsx_destination_evidence)$bt") | Out-Null
    $md.Add("- Payload modes: $bt$($result.payload_mode_counts | ConvertTo-Json -Compress)$bt") | Out-Null
    $md.Add("- Required payload mode: $bt$RequiredPayloadMode$bt") | Out-Null
    $md.Add("- Strict gate requested: $bt$($result.strict_gate_requested)$bt") | Out-Null
    $md.Add("- Strict gate pass: $bt$($result.strict_gate_pass)$bt") | Out-Null
    $md.Add("") | Out-Null
    $md.Add("Classification: $($bt)analysis$bt, $($bt)verify-logrow-parser$bt, not speed, not $($bt)gpu-migration-credit$bt, not a 200% gate candidate.") | Out-Null
    if ($result.strict_failures.Count -gt 0) {
        $md.Add("") | Out-Null
        $md.Add("## Strict Gate Failures") | Out-Null
        foreach ($failure in $result.strict_failures) {
            $md.Add("- $bt$failure$bt") | Out-Null
        }
    }
    if ($result.failures.Count -gt 0) {
        $md.Add("") | Out-Null
        $md.Add("## Failures") | Out-Null
        foreach ($failure in $result.failures) {
            $md.Add("- $bt$failure$bt") | Out-Null
        }
    }
    $md | Set-Content -LiteralPath $outMdPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 16
if ($FailOnGate -and $strictRequested -and -not $strictGatePass) {
    exit 2
}

