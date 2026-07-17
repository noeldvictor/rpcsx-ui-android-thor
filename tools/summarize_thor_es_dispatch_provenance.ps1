param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [string]$OutputDirectory = "",
    [string]$Label = "dispatch"
)

$ErrorActionPreference = "Stop"

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Split-Path -Parent $resolvedInput
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

$safeLabel = ($Label -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = "dispatch"
}

function Get-ProvenanceField {
    param(
        [string]$Line,
        [string]$Name
    )

    $pattern = '(?:^|\s)' + [Regex]::Escape($Name) + '=([^\s]+)'
    $match = [Regex]::Match($Line, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    return ""
}

function Get-ProvenanceDecision {
    param([Collections.IDictionary]$Fields)

    if ($Fields.template_start -eq "" -or $Fields.template_start -eq "0x0") {
        return "template_event_missing"
    }
    if ($Fields.command9_start -eq "" -or $Fields.command9_start -eq "0x0") {
        return "command9_event_missing"
    }
    if ($Fields.template_payload_relation -eq "stable_since_emit") {
        return "template_not_changed"
    }
    if ($Fields.command9_template_object_relation -eq "different_object") {
        return "different_object_challenge"
    }
    if ($Fields.command9_template_object_relation -ne "same_object") {
        return "ownership_incomplete"
    }

    if ($Fields.command9_template_ppu_relation -eq "different_ppu") {
        if ($Fields.command9_template_order_relation -eq "command9_before_template_complete" -and
            $Fields.template_completion_relation -eq "header_changed_at_complete") {
            return "cross_ppu_overlap_before_template_complete"
        }
        if ($Fields.command9_template_order_relation -eq "command9_after_template_complete") {
            return "cross_ppu_post_template_overwrite"
        }
        return "same_object_cross_ppu"
    }

    if ($Fields.command9_template_ppu_relation -eq "same_ppu") {
        if ($Fields.command9_template_order_relation -eq "command9_before_template_complete" -and
            $Fields.template_completion_relation -eq "header_changed_at_complete") {
            return "same_ppu_reentrant_overlap"
        }
        if ($Fields.command9_template_order_relation -eq "command9_after_template_complete") {
            return "same_ppu_reentrant_post_template_overwrite"
        }
        return "same_object_same_ppu"
    }

    return "ownership_incomplete"
}

$provenanceLines = @(
    Get-Content -LiteralPath $resolvedInput |
        Where-Object { $_ -match 'Thor Eternal Sonata PPU dispatch provenance:' }
)

if ($provenanceLines.Count -eq 0) {
    [PSCustomObject]@{
        InputPath = $resolvedInput
        Count = 0
        RawPath = ""
        JsonPath = ""
        DecisionPath = ""
    }
    return
}

$rawPath = Join-Path $OutputDirectory "guest-dispatch-provenance-$safeLabel.txt"
$jsonPath = Join-Path $OutputDirectory "guest-dispatch-provenance-$safeLabel.json"
$decisionPath = Join-Path $OutputDirectory "guest-dispatch-decision-$safeLabel.txt"

$provenanceLines | Set-Content -LiteralPath $rawPath -Encoding UTF8

$rows = @()
foreach ($line in $provenanceLines) {
    $fields = [ordered]@{
        kind = Get-ProvenanceField $line "kind"
        hit = Get-ProvenanceField $line "hit"
        parser_ppu = Get-ProvenanceField $line "ppu"
        address = Get-ProvenanceField $line "address"
        command = Get-ProvenanceField $line "command"
        template_boundary_candidate = Get-ProvenanceField $line "template_boundary_candidate"
        template_boundary_hit = Get-ProvenanceField $line "template_boundary_hit"
        command9_start = Get-ProvenanceField $line "command9_start"
        command9_emitter = Get-ProvenanceField $line "command9_emitter"
        command9_emitter_ppu = Get-ProvenanceField $line "command9_emitter_ppu"
        command9_object = Get-ProvenanceField $line "command9_object"
        command9_argument = Get-ProvenanceField $line "command9_argument"
        command9_event_age = Get-ProvenanceField $line "command9_event_age"
        command9_order = Get-ProvenanceField $line "command9_order"
        command9_stable = Get-ProvenanceField $line "command9_stable"
        command9_object_relation = Get-ProvenanceField $line "command9_object_relation"
        template_start = Get-ProvenanceField $line "template_start"
        template_emitter = Get-ProvenanceField $line "template_emitter"
        template_emitter_ppu = Get-ProvenanceField $line "template_emitter_ppu"
        template_object = Get-ProvenanceField $line "template_object"
        template_event_age = Get-ProvenanceField $line "template_event_age"
        template_fault_word = Get-ProvenanceField $line "template_fault_word"
        template_fault_word_stable = Get-ProvenanceField $line "template_fault_word_stable"
        template_order = Get-ProvenanceField $line "template_order"
        template_payload_relation = Get-ProvenanceField $line "template_payload_relation"
        template_completion_relation = Get-ProvenanceField $line "template_completion_relation"
        template_object_relation = Get-ProvenanceField $line "template_object_relation"
        command9_template_object_relation = Get-ProvenanceField $line "command9_template_object_relation"
        command9_template_ppu_relation = Get-ProvenanceField $line "command9_template_ppu_relation"
        command9_template_order_relation = Get-ProvenanceField $line "command9_template_order_relation"
    }
    $fields["decision"] = Get-ProvenanceDecision $fields
    $rows += [PSCustomObject]$fields
}

ConvertTo-Json -InputObject $rows -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
@(
    $rows | ForEach-Object {
        "hit=$($_.hit) command=$($_.command) address=$($_.address) decision=$($_.decision) " +
        "template_boundary_candidate=$($_.template_boundary_candidate) " +
        "template_boundary_hit=$($_.template_boundary_hit) " +
        "command9_emitter=$($_.command9_emitter) template_emitter=$($_.template_emitter) " +
        "object_relation=$($_.command9_template_object_relation) " +
        "ppu_relation=$($_.command9_template_ppu_relation) " +
        "order_relation=$($_.command9_template_order_relation) " +
        "completion_relation=$($_.template_completion_relation)"
    }
) | Set-Content -LiteralPath $decisionPath -Encoding UTF8

[PSCustomObject]@{
    InputPath = $resolvedInput
    Count = $rows.Count
    RawPath = $rawPath
    JsonPath = $jsonPath
    DecisionPath = $decisionPath
}
