[CmdletBinding()]
param(
    [string]$RunRoot = "",

    [string]$StockRun = "20260525-180238-hle-25cc-stock-battle-topslot-nopause-battleroute-ab-windows",

    [string]$BodyRun = "20260525-181425-hle-25cc-body-battle-topslot-nopause-battleroute-ab-windows",

    [int]$BattleSeconds = 231,

    [int]$StableSeconds = 292,

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

function Convert-AbNumber {
    param([object]$Value)

    if ($null -eq $Value) {
        return [double]0
    }

    $text = "$Value".Trim().Replace(",", "")
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [double]0
    }

    $number = [double]0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return $number
    }

    return [double]0
}

function Format-AbBytes {
    param([double]$Bytes)

    if ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ("{0:N2} MB" -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ("{0:N2} KB" -f ($Bytes / 1KB))
    }
    return ("{0:N0} B" -f $Bytes)
}

function Format-AbDelta {
    param(
        [double]$Body,
        [double]$Stock
    )

    $delta = $Body - $Stock
    $pct = [double]0
    if ($Stock -ne 0) {
        $pct = 100.0 * $delta / $Stock
    }

    return [pscustomobject]@{
        Delta = $delta
        Percent = $pct
        Text = ("{0:N2} FPS / {1:N2}%" -f $delta, $pct)
    }
}

function Read-FpsStats {
    param(
        [string]$RunDir,
        [int]$MinSeconds = 0
    )

    $path = Join-Path $RunDir "window-title-samples.csv"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Count = 0; Average = 0; Minimum = 0; Maximum = 0 }
    }

    $rows = @(Import-Csv -LiteralPath $path | Where-Object { [int](Convert-AbNumber $_.elapsed_seconds) -ge $MinSeconds })
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{ Count = 0; Average = 0; Minimum = 0; Maximum = 0 }
    }

    $measure = $rows | Measure-Object -Property fps -Average -Minimum -Maximum
    return [pscustomobject]@{
        Count = [int]$measure.Count
        Average = [double]$measure.Average
        Minimum = [double]$measure.Minimum
        Maximum = [double]$measure.Maximum
    }
}

function Read-VisualGate {
    param([string]$RunDir)

    $path = Join-Path $RunDir "eternal-sonata-windows-visual-gate-summary.md"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{
            Present = $false
            Status = "missing"
            GateResult = "missing"
            FirstField = ""
            BattleLike = ""
        }
    }

    $status = ""
    $gate = ""
    $first = ""
    $battle = ""
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^- Status: `(?<value>[^`]+)`') {
            $status = $matches["value"]
        }
        elseif ($line -match '^- Gate result: `(?<value>[^`]+)`') {
            $gate = $matches["value"]
        }
        elseif ($line -match '^- First field-like screenshot: (?<value>.+)$') {
            $first = $matches["value"].Trim()
        }
        elseif ($line -match '^- Required battle-like at or after `[^`]+`: (?<value>.+)$') {
            $battle = $matches["value"].Trim()
        }
    }

    return [pscustomobject]@{
        Present = $true
        Status = $status
        GateResult = $gate
        FirstField = $first
        BattleLike = $battle
    }
}

function Parse-AbFields {
    param([string]$Line)

    $fields = @{}
    foreach ($match in [regex]::Matches($Line, '(\w+)=("[^"]*"|[^\s]+)')) {
        $value = $match.Groups[2].Value.Trim('"')
        $fields[$match.Groups[1].Value] = $value
    }

    return $fields
}

function Add-AbSum {
    param(
        [hashtable]$Target,
        [hashtable]$Fields,
        [string]$Name
    )

    if (-not $Target.ContainsKey($Name)) {
        $Target[$Name] = [double]0
    }
    if ($Fields.ContainsKey($Name)) {
        $Target[$Name] = [double]$Target[$Name] + (Convert-AbNumber $Fields[$Name])
    }
}

function Add-AbAggregate {
    param(
        [hashtable]$Target,
        [hashtable]$Fields,
        [string]$Name
    )

    if (-not $Target.ContainsKey($Name)) {
        $Target[$Name] = [double]0
    }
    if (-not $Fields.ContainsKey($Name)) {
        return
    }

    $value = Convert-AbNumber $Fields[$Name]
    if ($Name -like "max_*") {
        $Target[$Name] = [Math]::Max([double]$Target[$Name], $value)
        return
    }

    $Target[$Name] = [double]$Target[$Name] + $value
}

function Read-ProbeAggregate {
    param(
        [string]$RunDir,
        [string]$Pattern,
        [string[]]$Fields
    )

    $path = Join-Path $RunDir "RPCS3.log"
    $result = @{
        records = [double]0
    }
    foreach ($field in $Fields) {
        $result[$field] = [double]0
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]$result
    }

    foreach ($match in Select-String -LiteralPath $path -SimpleMatch $Pattern) {
        $result["records"] = [double]$result["records"] + 1
        $parsed = Parse-AbFields $match.Line
        foreach ($field in $Fields) {
            Add-AbAggregate -Target $result -Fields $parsed -Name $field
        }
    }

    return [pscustomobject]$result
}

function Read-SeriousFatalCount {
    param([string]$RunDir)

    $paths = @(
        (Join-Path $RunDir "RPCS3.log"),
        (Join-Path $RunDir "rpcs3.stdout.txt"),
        (Join-Path $RunDir "rpcs3.stderr.txt")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }

    if ($paths.Count -eq 0) {
        return 0
    }

    $hits = Select-String -LiteralPath $paths -Pattern '(?i)(access violation|SIGSEGV|SIGBUS|assertion|Vulkan validation|likely-crashed|Unhandled exception|crash)' |
        Where-Object { $_.Line -notmatch 'renderer|crash dump|Show fatal error hints' }
    return @($hits).Count
}

function Get-AbGradeRank {
    param([string]$Grade)

    switch -Regex ($Grade) {
        '^clean$' { return 0 }
        '^moderate$' { return 1 }
        '^hot$' { return 2 }
        '^fail(ed)?$' { return 3 }
        default { return -1 }
    }
}

function Read-HostSampleStats {
    param([string]$RunDir)

    $hostDir = Join-Path $RunDir "host-system"
    if (-not (Test-Path -LiteralPath $hostDir -PathType Container)) {
        return [pscustomobject]@{
            Count = 0
            AvgRunCpu = 0
            AvgTotalCpu = 0
            AvgGpu = 0
            WorstExternal = "missing"
            GateFailure = ""
        }
    }

    $samples = @(Get-ChildItem -LiteralPath $hostDir -Filter "sample-*.json" -File | Sort-Object Name)
    $runCpu = New-Object System.Collections.Generic.List[double]
    $totalCpu = New-Object System.Collections.Generic.List[double]
    $gpu = New-Object System.Collections.Generic.List[double]
    $worstExternal = "missing"
    $worstRank = -1

    foreach ($sample in $samples) {
        try {
            $json = Get-Content -LiteralPath $sample.FullName -Raw | ConvertFrom-Json
        }
        catch {
            continue
        }

        $totalCpu.Add((Convert-AbNumber $json.total_cpu_percent_estimate)) | Out-Null
        $gpu.Add((Convert-AbNumber $json.gpu_engine_util_percent_sum)) | Out-Null
        $run = @($json.run_process | Select-Object -First 1)
        if ($run.Count -gt 0) {
            $runCpu.Add((Convert-AbNumber $run[0].cpu_percent)) | Out-Null
        }

        $external = "$($json.external_contention_grade)"
        $rank = Get-AbGradeRank $external
        if ($rank -gt $worstRank) {
            $worstRank = $rank
            $worstExternal = $external
        }
    }

    $gateFailurePath = Join-Path $RunDir "host-contention-gate-failed.txt"
    $gateFailure = ""
    if (Test-Path -LiteralPath $gateFailurePath -PathType Leaf) {
        $gateFailure = (Get-Content -LiteralPath $gateFailurePath -Raw).Trim()
    }

    $runCpuAvg = [double]0
    if ($runCpu.Count -gt 0) {
        $runCpuAvg = ($runCpu | Measure-Object -Average).Average
    }
    $totalCpuAvg = [double]0
    if ($totalCpu.Count -gt 0) {
        $totalCpuAvg = ($totalCpu | Measure-Object -Average).Average
    }
    $gpuAvg = [double]0
    if ($gpu.Count -gt 0) {
        $gpuAvg = ($gpu | Measure-Object -Average).Average
    }

    return [pscustomobject]@{
        Count = $samples.Count
        AvgRunCpu = $runCpuAvg
        AvgTotalCpu = $totalCpuAvg
        AvgGpu = $gpuAvg
        WorstExternal = $worstExternal
        GateFailure = $gateFailure
    }
}

function Format-AbPercentDelta {
    param(
        [double]$Body,
        [double]$Stock
    )

    $delta = $Body - $Stock
    $pct = [double]0
    if ($Stock -ne 0) {
        $pct = 100.0 * $delta / $Stock
    }

    return [pscustomobject]@{
        Delta = $delta
        Percent = $pct
        Text = ("{0:N2} pp / {1:N2}%" -f $delta, $pct)
    }
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $RunRoot = Join-Path $repoRoot "debug-captures\windows-lab"
}
if ([string]::IsNullOrWhiteSpace($OutPath)) {
    $OutPath = Join-Path $RunRoot "_eternal-sonata-25cc-battle-ab-latest.md"
}
if ([string]::IsNullOrWhiteSpace($CsvPath)) {
    $CsvPath = Join-Path $RunRoot "_eternal-sonata-25cc-battle-ab-latest.csv"
}

$stockDir = Resolve-RunDir -Root $RunRoot -Run $StockRun
$bodyDir = Resolve-RunDir -Root $RunRoot -Run $BodyRun

$stockAll = Read-FpsStats -RunDir $stockDir
$bodyAll = Read-FpsStats -RunDir $bodyDir
$stockBattle = Read-FpsStats -RunDir $stockDir -MinSeconds $BattleSeconds
$bodyBattle = Read-FpsStats -RunDir $bodyDir -MinSeconds $BattleSeconds
$stockStable = Read-FpsStats -RunDir $stockDir -MinSeconds $StableSeconds
$bodyStable = Read-FpsStats -RunDir $bodyDir -MinSeconds $StableSeconds

$bodyFields = @("hits", "get_hits", "put_rejects", "bytes", "total_us", "max_total_us", "ea9e4000_hits", "other_ea_hits")
$shadowFields = @("hits", "bytes", "dst_changed", "dst_unchanged", "output_match", "output_mismatch", "ea9e4000_hits", "other_ea_hits")
$familyFields = @("hits", "success", "fail", "bytes", "total_us", "max_total_us")
$bodyAgg = Read-ProbeAggregate -RunDir $bodyDir -Pattern "Eternal Sonata SPU HLE 25cc body verifier:" -Fields $bodyFields
$shadowAgg = Read-ProbeAggregate -RunDir $bodyDir -Pattern "Eternal Sonata SPU HLE 25cc shadow verifier:" -Fields $shadowFields
$familyAgg = Read-ProbeAggregate -RunDir $bodyDir -Pattern "Eternal Sonata SPU HLE 25cc family verifier:" -Fields $familyFields

$stockVisual = Read-VisualGate -RunDir $stockDir
$bodyVisual = Read-VisualGate -RunDir $bodyDir
$stockFatal = Read-SeriousFatalCount -RunDir $stockDir
$bodyFatal = Read-SeriousFatalCount -RunDir $bodyDir
$stockHost = Read-HostSampleStats -RunDir $stockDir
$bodyHost = Read-HostSampleStats -RunDir $bodyDir

$allDelta = Format-AbDelta -Body $bodyAll.Average -Stock $stockAll.Average
$battleDelta = Format-AbDelta -Body $bodyBattle.Average -Stock $stockBattle.Average
$stableDelta = Format-AbDelta -Body $bodyStable.Average -Stock $stockStable.Average
$runCpuDelta = Format-AbPercentDelta -Body $bodyHost.AvgRunCpu -Stock $stockHost.AvgRunCpu
$totalCpuDelta = Format-AbPercentDelta -Body $bodyHost.AvgTotalCpu -Stock $stockHost.AvgTotalCpu
$gpuDelta = Format-AbPercentDelta -Body $bodyHost.AvgGpu -Stock $stockHost.AvgGpu
$hasHostGateNoise = -not [string]::IsNullOrWhiteSpace($stockHost.GateFailure) -or -not [string]::IsNullOrWhiteSpace($bodyHost.GateFailure)
$hasCleanComparableHostSamples =
    $stockHost.Count -gt 0 -and
    $bodyHost.Count -gt 0 -and
    $stockHost.WorstExternal -eq "clean" -and
    $bodyHost.WorstExternal -eq "clean"
$cpuLoadReductionCandidate = $hasCleanComparableHostSamples -and $runCpuDelta.Delta -le -5.0

$bodyAvgUs = [double]0
if ($bodyAgg.hits -gt 0) {
    $bodyAvgUs = [double]$bodyAgg.total_us / [double]$bodyAgg.hits
}
$familyAvgUs = [double]0
if ($familyAgg.hits -gt 0) {
    $familyAvgUs = [double]$familyAgg.total_us / [double]$familyAgg.hits
}

$classification = "valid-matched-no-pause-first-battle-ab"
if ($stockVisual.GateResult -ne "passed-for-triage" -or $bodyVisual.GateResult -ne "passed-for-triage" -or $stockFatal -gt 0 -or $bodyFatal -gt 0) {
    $classification = "not-comparable"
}
elseif ($battleDelta.Percent -gt 1.0 -or $stableDelta.Percent -gt 1.0) {
    $classification = "windows-micro-win-candidate"
}
elseif ($cpuLoadReductionCandidate -and -not $hasHostGateNoise) {
    $classification = "windows-cpu-load-micro-win-candidate"
}
elseif ($cpuLoadReductionCandidate) {
    $classification = "directional-cpu-load-reduction-candidate"
}
elseif ($battleDelta.Percent -lt 0.0 -or $stableDelta.Percent -lt 0.0) {
    $classification = "not-speed-win"
}

$generated = (Get-Date).ToString("o")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Eternal Sonata 0x25cc Battle A/B Summary") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Generated: $generated") | Out-Null
$lines.Add(("- Stock run: {0}" -f (Split-Path -Leaf $stockDir))) | Out-Null
$lines.Add(("- Body run: {0}" -f (Split-Path -Leaf $bodyDir))) | Out-Null
$lines.Add(("- Classification: {0}" -f $classification)) | Out-Null
$lines.Add("- Not gpu-migration-credit, not a 200% gate candidate.") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Visual And Logs") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- Stock visual gate: {0} / {1}; first field {2}; battle-like {3}; serious fatal hits {4}." -f $stockVisual.Status, $stockVisual.GateResult, $stockVisual.FirstField, $stockVisual.BattleLike, $stockFatal)) | Out-Null
$lines.Add(("- Body visual gate: {0} / {1}; first field {2}; battle-like {3}; serious fatal hits {4}." -f $bodyVisual.Status, $bodyVisual.GateResult, $bodyVisual.FirstField, $bodyVisual.BattleLike, $bodyFatal)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## FPS Windows") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Window | Stock count | Stock avg | Body count | Body avg | Delta |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: | ---: | ---: |") | Out-Null
$lines.Add(("| all samples | {0} | {1:N2} | {2} | {3:N2} | {4} |" -f $stockAll.Count, $stockAll.Average, $bodyAll.Count, $bodyAll.Average, $allDelta.Text)) | Out-Null
$lines.Add(("| >= {0}s | {1} | {2:N2} | {3} | {4:N2} | {5} |" -f $BattleSeconds, $stockBattle.Count, $stockBattle.Average, $bodyBattle.Count, $bodyBattle.Average, $battleDelta.Text)) | Out-Null
$lines.Add(("| >= {0}s | {1} | {2:N2} | {3} | {4:N2} | {5} |" -f $StableSeconds, $stockStable.Count, $stockStable.Average, $bodyStable.Count, $bodyStable.Average, $stableDelta.Text)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Host Sample CPU") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Metric | Stock | Body | Delta |") | Out-Null
$lines.Add("| --- | ---: | ---: | ---: |") | Out-Null
$lines.Add(("| In-run host samples | {0} | {1} |  |" -f $stockHost.Count, $bodyHost.Count)) | Out-Null
$lines.Add(("| RPCS3 process CPU avg | {0:N2}% | {1:N2}% | {2} |" -f $stockHost.AvgRunCpu, $bodyHost.AvgRunCpu, $runCpuDelta.Text)) | Out-Null
$lines.Add(("| Total host CPU avg | {0:N2}% | {1:N2}% | {2} |" -f $stockHost.AvgTotalCpu, $bodyHost.AvgTotalCpu, $totalCpuDelta.Text)) | Out-Null
$lines.Add(("| GPU engine util sum avg | {0:N2}% | {1:N2}% | {2} |" -f $stockHost.AvgGpu, $bodyHost.AvgGpu, $gpuDelta.Text)) | Out-Null
$lines.Add(("| Worst in-run external grade | {0} | {1} |  |" -f $stockHost.WorstExternal, $bodyHost.WorstExternal)) | Out-Null
if (-not [string]::IsNullOrWhiteSpace($stockHost.GateFailure) -or -not [string]::IsNullOrWhiteSpace($bodyHost.GateFailure)) {
    $lines.Add("") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($stockHost.GateFailure)) {
        $lines.Add(("- Stock host gate note: {0}" -f $stockHost.GateFailure)) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($bodyHost.GateFailure)) {
        $lines.Add(("- Body host gate note: {0}" -f $bodyHost.GateFailure)) | Out-Null
    }
}
$lines.Add("") | Out-Null
$lines.Add("## 0x25cc Body Counters") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- Body records/hits/bytes: {0} / {1} / {2}." -f [int]$bodyAgg.records, [UInt64]$bodyAgg.hits, (Format-AbBytes $bodyAgg.bytes))) | Out-Null
$lines.Add(("- Body timing total/avg/max: {0:N0} us / {1:N3} us/hit / {2:N0} us." -f $bodyAgg.total_us, $bodyAvgUs, $bodyAgg.max_total_us)) | Out-Null
$lines.Add(("- Shadow records/hits/mismatch: {0} / {1} / {2}; destination changed/unchanged {3} / {4}." -f [int]$shadowAgg.records, [UInt64]$shadowAgg.hits, [UInt64]$shadowAgg.output_mismatch, [UInt64]$shadowAgg.dst_changed, [UInt64]$shadowAgg.dst_unchanged)) | Out-Null
$lines.Add(("- Family hits/success/fail/bytes: {0} / {1} / {2} / {3}." -f [UInt64]$familyAgg.hits, [UInt64]$familyAgg.success, [UInt64]$familyAgg.fail, (Format-AbBytes $familyAgg.bytes))) | Out-Null
$lines.Add(("- Family timing total/avg/max: {0:N0} us / {1:N3} us/hit / {2:N0} us." -f $familyAgg.total_us, $familyAvgUs, $familyAgg.max_total_us)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Reading") | Out-Null
$lines.Add("") | Out-Null
if ($classification -eq "not-comparable") {
    $lines.Add("- Do not use this A/B for speed. One side failed the visual or serious-fatal gate.") | Out-Null
}
elseif ($classification -eq "windows-micro-win-candidate") {
    $lines.Add("- The body side is faster in a matched first-battle window, but still needs a repeat and full field/menu/battle proof before banking a micro-win.") | Out-Null
}
elseif ($classification -eq "windows-cpu-load-micro-win-candidate") {
    $lines.Add("- The body side is correctness-clean and reproduced a clean in-run RPCS3 CPU-load reduction. Bank this only as a CPU-pressure stack component, not as an FPS win.") | Out-Null
}
elseif ($classification -eq "directional-cpu-load-reduction-candidate") {
    $lines.Add("- The body side is correctness-clean and lowers in-run RPCS3 CPU load, but host-gate noise keeps this directional until a clean repeat pair confirms it.") | Out-Null
}
else {
    $lines.Add("- The body side is correctness-clean but not faster in the matched first-battle windows. Do not bank a micro-win.") | Out-Null
}
if ($cpuLoadReductionCandidate -and -not $hasHostGateNoise) {
    $lines.Add("- The capped-FPS host samples now have a clean stock/bodyfast pair: RPCS3 process CPU dropped by at least 5 pp while field and first-battle visuals stayed valid.") | Out-Null
}
elseif ($bodyHost.Count -gt 0 -and $stockHost.Count -gt 0 -and $runCpuDelta.Delta -lt -5.0) {
    $lines.Add("- The capped-FPS host samples show directional RPCS3 CPU-load reduction, but treat it as a CPU-load candidate until a clean repeat pair avoids host-gate noise.") | Out-Null
}
$lines.Add("- The 0x25cc path remains CPU/SPU HLE/codegen work. No CPU/SPU-to-GPU replacement or RSX-consumed batch was tested here.") | Out-Null
if ($bodyAgg.hits -gt 0 -and $shadowAgg.hits -eq 0 -and $familyAgg.hits -eq 0) {
    $lines.Add("- Next speed work should stack this opt-in CPU-pressure component with one compatible verified path in a combined Windows proof, or pivot to a larger 0x451c/codegen body where removed CPU work can show beyond the 120 FPS cap.") | Out-Null
}
else {
    $lines.Add("- Next speed work should remove verifier/family overhead or narrow the body before another A/B.") | Out-Null
}

$summaryRows = @(
    [pscustomobject]@{ window = "all"; stock_count = $stockAll.Count; stock_avg = $stockAll.Average; body_count = $bodyAll.Count; body_avg = $bodyAll.Average; delta_fps = $allDelta.Delta; delta_percent = $allDelta.Percent },
    [pscustomobject]@{ window = "ge_$($BattleSeconds)s"; stock_count = $stockBattle.Count; stock_avg = $stockBattle.Average; body_count = $bodyBattle.Count; body_avg = $bodyBattle.Average; delta_fps = $battleDelta.Delta; delta_percent = $battleDelta.Percent },
    [pscustomobject]@{ window = "ge_$($StableSeconds)s"; stock_count = $stockStable.Count; stock_avg = $stockStable.Average; body_count = $bodyStable.Count; body_avg = $bodyStable.Average; delta_fps = $stableDelta.Delta; delta_percent = $stableDelta.Percent },
    [pscustomobject]@{ window = "host_rpcs3_cpu_avg"; stock_count = $stockHost.Count; stock_avg = $stockHost.AvgRunCpu; body_count = $bodyHost.Count; body_avg = $bodyHost.AvgRunCpu; delta_fps = $runCpuDelta.Delta; delta_percent = $runCpuDelta.Percent },
    [pscustomobject]@{ window = "host_total_cpu_avg"; stock_count = $stockHost.Count; stock_avg = $stockHost.AvgTotalCpu; body_count = $bodyHost.Count; body_avg = $bodyHost.AvgTotalCpu; delta_fps = $totalCpuDelta.Delta; delta_percent = $totalCpuDelta.Percent },
    [pscustomobject]@{ window = "host_gpu_engine_avg"; stock_count = $stockHost.Count; stock_avg = $stockHost.AvgGpu; body_count = $bodyHost.Count; body_avg = $bodyHost.AvgGpu; delta_fps = $gpuDelta.Delta; delta_percent = $gpuDelta.Percent }
)

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
    $summaryRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation
}

$lines | Write-Output
if (-not $NoWrite) {
    Write-Output ""
    Write-Output ("Markdown: {0}" -f $OutPath)
    Write-Output ("CSV: {0}" -f $CsvPath)
}
