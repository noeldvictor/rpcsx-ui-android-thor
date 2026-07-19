$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamPath = Join-Path $workspaceRoot "rpcs3-upstream/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp"
$sprintPath = Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1"
$labPath = Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1"
$summaryPath = Join-Path $PSScriptRoot "summarize_eternal_sonata_spu_heat.ps1"

foreach ($path in @($upstreamPath, $sprintPath, $labPath, $summaryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SPU heat-profile dependency: $path"
    }
}

$upstreamSource = Get-Content -LiteralPath $upstreamPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw
$labSource = Get-Content -LiteralPath $labPath -Raw
$summarySource = Get-Content -LiteralPath $summaryPath -Raw

foreach ($fragment in @(
    'g_cfg.core.spu_prof',
    '::getenv("RPCS3_ES_SPU_HEAT_PROFILE")',
    'std::string_view{heat_profile_mode} != "compact"',
    'Emu.GetTitleID() == "BLUS30161"',
    'named_thread heat_profiler("ES SPU Heat Profiler"sv',
    'constexpr usz heat_sample_limit = 8192',
    'thread_ctrl::wait_for(250, false)',
    'std::chrono::seconds(30)',
    'report_heat(false)',
    'report_heat(true)',
    'heat_dropped_samples',
    'mean_samples_x100',
    'ES SPU heat summary:',
    'ES SPU heat block:'
)) {
    if (-not $upstreamSource.Contains($fragment)) {
        throw "Missing bounded SPU heat-sampler fragment: $fragment"
    }
}

$heatThreadIndex = $upstreamSource.IndexOf('named_thread heat_profiler("ES SPU Heat Profiler"sv')
$cacheWaitIndex = $upstreamSource.IndexOf('while (!registered && thread_ctrl::state() != thread_state::aborting)')
if ($heatThreadIndex -lt 0 -or $cacheWaitIndex -lt 0 -or $heatThreadIndex -ge $cacheWaitIndex) {
    throw "The heat profiler must start before the warmed-cache compiler wait."
}

foreach ($fragment in @(
    '[string]$EternalSonataSpuHeatProfile = "Off"',
    'EternalSonataSpuHeatProfile = $EternalSonataSpuHeatProfile',
    '[string]$WindowsBattleLoadRoute = "StateAware"',
    'gate_first_battle_prompt:25000',
    '$minimumBattleSeconds = if ($WindowsBattleLoadRoute -eq "StateAware") { 155 } else { 330 }'
)) {
    if (-not $sprintSource.Contains($fragment)) {
        throw "Missing speed-sprint heat-profile plumbing: $fragment"
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataSpuHeatProfile = "Off"',
    '$newLine = "  SPU Profiler: $spuProfilerValue"',
    '"Profile" { "compact" }',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HEAT_PROFILE", $esSpuHeatProfileEnv, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_SPU_HEAT_PROFILE", $previousEsSpuHeatProfile, "Process")',
    '$closeRequested = $process.CloseMainWindow()',
    '$exited = $process.WaitForExit(10000)',
    '$heatSummaryPath = Join-Path $runDir "spu-heat-summary.txt"',
    '$heatAnalyzer = Join-Path $PSScriptRoot "summarize_eternal_sonata_spu_heat.ps1"',
    '$line.Contains("ES SPU heat ")'
)) {
    if (-not $labSource.Contains($fragment)) {
        throw "Missing Windows-lab heat-profile contract: $fragment"
    }
}

foreach ($fragment in @(
    'active_samples',
    'delta_samples',
    'samples_per_entry',
    '$plateau = $activeDelta -eq 0',
    "'| {0} | 0x{1} | {2} | {3} | {4} | {5} |' -f",
    'block rows are limited to each snapshot''s logged top 32'
)) {
    if (-not $summarySource.Contains($fragment)) {
        throw "Missing SPU heat summary contract: $fragment"
    }
}

foreach ($scriptPath in @($sprintPath, $labPath, $summaryPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for '$scriptPath': $($errors[0].Message)"
    }
}

Write-Output "Thor SPU heat-profile contract passed: the sampler is title/config-gated, bounded to 8192 hashes, emits 30-second snapshots, and is opt-in through the Windows lab."
