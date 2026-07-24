param(
    [string]$RunRoot = "debug-captures\windows-lab",
    [string]$OutPath = "spu-contracts\BLUS30161\25cc-route-safety-audit.md",
    [string]$SpuThreadPath = "..\rpcs3-upstream\rpcs3\Emu\Cell\SPUThread.cpp",
    [string]$SysSpuPath = "..\rpcs3-upstream\rpcs3\Emu\Cell\lv2\sys_spu.cpp"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-BulletValue {
    param(
        [string[]]$Lines,
        [string]$Label
    )

    $prefix = "- ${Label}:"
    foreach ($line in $Lines) {
        if ($line.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            return $line.Substring($prefix.Length).Trim().Trim('`')
        }
    }

    return ""
}

function Get-FirstLineNumber {
    param(
        [string]$Path,
        [string]$Pattern,
        [switch]$SimpleMatch
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $match = if ($SimpleMatch) {
        Select-String -LiteralPath $Path -Pattern $Pattern -SimpleMatch | Select-Object -First 1
    } else {
        Select-String -LiteralPath $Path -Pattern $Pattern | Select-Object -First 1
    }

    if ($match) {
        return [int]$match.LineNumber
    }

    return $null
}

function Get-LatestUnsafe25ccRun {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $null
    }

    $runs = Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.Name -like '*25cc*' } |
        Sort-Object LastWriteTime -Descending

    foreach ($run in $runs) {
        $visual = Join-Path $run.FullName 'eternal-sonata-windows-visual-gate-summary.md'
        if (-not (Test-Path -LiteralPath $visual -PathType Leaf)) {
            continue
        }

        $lines = Get-Content -LiteralPath $visual
        $status = Get-BulletValue -Lines $lines -Label 'Status'
        if ($status -eq 'FIELD_LIKE_PRESENT') {
            continue
        }

        $json = Join-Path $run.FullName 'contract-verify-logrow-results.json'
        return [pscustomobject]@{
            Name = $run.Name
            Path = $run.FullName
            VisualPath = $visual
            VisualLines = $lines
            ContractJsonPath = $json
            Contract = if (Test-Path -LiteralPath $json -PathType Leaf) { Get-Content -Raw -LiteralPath $json | ConvertFrom-Json } else { $null }
        }
    }

    return $null
}

$unsafeRun = Get-LatestUnsafe25ccRun -Root $RunRoot
$spuThreadResolved = if (Test-Path -LiteralPath $SpuThreadPath -PathType Leaf) { (Resolve-Path -LiteralPath $SpuThreadPath).Path } else { $SpuThreadPath }
$sysSpuResolved = if (Test-Path -LiteralPath $SysSpuPath -PathType Leaf) { (Resolve-Path -LiteralPath $SysSpuPath).Path } else { $SysSpuPath }

$beginLine = Get-FirstLineNumber -Path $SpuThreadPath -Pattern 'begin_es_spu_hle_shadow_sample' -SimpleMatch
$finishLine = Get-FirstLineNumber -Path $SpuThreadPath -Pattern 'finish_es_spu_hle_shadow_sample' -SimpleMatch
$hashLine = Get-FirstLineNumber -Path $SpuThreadPath -Pattern 'compute_es_spu_hle_shadow_hash' -SimpleMatch
$record25Line = Get-FirstLineNumber -Path $SpuThreadPath -Pattern 'record_es_spu_hle_25cc_shadow_sample' -SimpleMatch
$memcmpLine = Get-FirstLineNumber -Path $SpuThreadPath -Pattern 'std::memcmp(src, dst, cmd.size)' -SimpleMatch
$contractLogLine = Get-FirstLineNumber -Path $SysSpuPath -Pattern 'Eternal Sonata SPU contract verifier' -SimpleMatch
$verboseLine = Get-FirstLineNumber -Path $SysSpuPath -Pattern 'RPCS3_ES_SPU_HLE_VERIFY_VERBOSE' -SimpleMatch

$rows = 0L
$hits = 0L
$bytes = 0L
$getHits = 0L
$putHits = 0L
$mismatch = 0L
$overflow = 0L
if ($unsafeRun -and $unsafeRun.Contract) {
    $rows = [int64]$unsafeRun.Contract.rows
    $hits = [int64]$unsafeRun.Contract.total_contract_hits
    $bytes = [int64]$unsafeRun.Contract.total_contract_bytes
    $mismatch = [int64]$unsafeRun.Contract.total_output_mismatch
    $overflow = [int64]$unsafeRun.Contract.total_desc_overflow
    foreach ($row in $unsafeRun.Contract.rows_detail) {
        $getHits += [int64]$row.fields.contract_get_hits
        $putHits += [int64]$row.fields.contract_put_hits
    }
}

$payloadReadBytes = $hits * 0x4000 * 4
$payloadReadMiB = [Math]::Round($payloadReadBytes / 1MB, 3)

$visualStatus = if ($unsafeRun) { Get-BulletValue -Lines $unsafeRun.VisualLines -Label 'Status' } else { 'n/a' }
$firstField = if ($unsafeRun) { Get-BulletValue -Lines $unsafeRun.VisualLines -Label 'First field-like screenshot' } else { 'n/a' }
$gateResult = if ($unsafeRun) { Get-BulletValue -Lines $unsafeRun.VisualLines -Label 'Gate result' } else { 'n/a' }
$classCounts = if ($unsafeRun) { @($unsafeRun.VisualLines | Where-Object { $_ -match '^  - `' }) } else { @() }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Eternal Sonata 25cc Route-Safety Audit') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- Generated: `{0}`' -f (Get-Date).ToString('o'))) | Out-Null
$lines.Add('- Classification: source/RAG route-safety audit, not speed, not GPU migration credit, not promotion evidence.') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Latest unsafe 25cc run') | Out-Null
$lines.Add('') | Out-Null
if ($unsafeRun) {
    $lines.Add(('- Run: `{0}`' -f $unsafeRun.Name)) | Out-Null
    $lines.Add(('- Visual status: `{0}`; gate: `{1}`; first field-like: `{2}`' -f $visualStatus, $gateResult, $firstField)) | Out-Null
    foreach ($classLine in $classCounts) {
        $lines.Add($classLine) | Out-Null
    }
    $lines.Add(('- Contract rows: rows={0}, hits={1}, bytes={2}, GET={3}, PUT={4}, output_mismatch={5}, desc_overflow={6}' -f $rows, $hits, $bytes, $getHits, $putHits, $mismatch, $overflow)) | Out-Null
} else {
    $lines.Add('- No failed/non-field 25cc run with visual summary was found under the run root.') | Out-Null
}
$lines.Add('') | Out-Null
$lines.Add('## Source alignment') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- SPU hook source: `{0}`' -f $spuThreadResolved)) | Out-Null
$lines.Add(('- Contract log source: `{0}`' -f $sysSpuResolved)) | Out-Null
$lines.Add(('- `compute_es_spu_hle_shadow_hash`: line {0}' -f $hashLine)) | Out-Null
$lines.Add(('- `begin_es_spu_hle_shadow_sample`: line {0}' -f $beginLine)) | Out-Null
$lines.Add(('- `finish_es_spu_hle_shadow_sample`: line {0}' -f $finishLine)) | Out-Null
$lines.Add(('- `record_es_spu_hle_25cc_shadow_sample`: line {0}' -f $record25Line)) | Out-Null
$lines.Add(('- `std::memcmp(src, dst, cmd.size)`: line {0}' -f $memcmpLine)) | Out-Null
$lines.Add(('- compact contract row logger: line {0}' -f $contractLogLine)) | Out-Null
$lines.Add(('- verbose trace opt-in: line {0}' -f $verboseLine)) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Route-safety read') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('- The active 25cc shadow verifier is behavior-preserving, but it samples matched 16 KiB transfers by hashing source and destination before the DMA, then hashing destination and comparing source/destination after the DMA.') | Out-Null
$lines.Add(('- For the latest unsafe run this implies about `{0}` MiB of extra payload reads in the SPU MFC hot path before any logging cost, based on `{1}` contract hits at 16 KiB and four full payload passes per hit.' -f $payloadReadMiB, $hits)) | Out-Null
$lines.Add('- The compact logger already suppresses deep trace rows by default, so the remaining likely perturbation is payload sampling cost/timing, not text log volume.') | Out-Null
$lines.Add('- Counts and descriptor shape are still valuable, but promotion must remain blocked unless a full-payload verification mode proves zero mismatch/overflow across field, Options/menu, and first battle.') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('## Recommended next source change') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('- Add an explicit 25cc shadow payload mode, for example `RPCS3_ES_SPU_HLE_25CC_SHADOW_PAYLOAD=full|sampled|counts`, defaulting route-repair runs to `counts` or sparse `sampled`.') | Out-Null
$lines.Add('- Emit a `payload_mode=` field in the strict contract row and teach the parser to reject promotion unless `payload_mode=full`.') | Out-Null
$lines.Add('- In counts/sampled mode, keep descriptor GET/PUT/family/bytes/overflow counters but avoid or sparsely run the 16 KiB source/destination hashing and memcmp path.') | Out-Null
$lines.Add('- Only after a counts/sampled 25cc run reaches clean field should a full-payload verifier rerun be attempted, followed by Options/menu and first battle before any body/codegen/Vulkan fast mode.') | Out-Null

$outDir = Split-Path -Parent $OutPath
if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
[System.IO.File]::WriteAllLines($OutPath, $lines, [System.Text.UTF8Encoding]::new($false))
$lines | Write-Output
Write-Output ""
Write-Output ("Markdown: {0}" -f (Resolve-Path -LiteralPath $OutPath).Path)
