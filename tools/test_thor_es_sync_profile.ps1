$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $repoRoot
$upstreamRoot = Join-Path $workspaceRoot "rpcs3-upstream"
$profileHeaderPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/es_sync_profile.h"
$eventPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_event.cpp"
$semaphorePath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_semaphore.cpp"
$timerPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_timer.cpp"
$spuPath = Join-Path $upstreamRoot "rpcs3/Emu/Cell/lv2/sys_spu.cpp"
$sprintPath = Join-Path $PSScriptRoot "eternal_sonata_speed_sprint.ps1"
$labPath = Join-Path $PSScriptRoot "windows_rpcs3_lab.ps1"

foreach ($path in @($profileHeaderPath, $eventPath, $semaphorePath, $timerPath, $spuPath, $sprintPath, $labPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing synchronization-profile dependency: $path"
    }
}

$headerSource = Get-Content -LiteralPath $profileHeaderPath -Raw
$eventSource = Get-Content -LiteralPath $eventPath -Raw
$semaphoreSource = Get-Content -LiteralPath $semaphorePath -Raw
$timerSource = Get-Content -LiteralPath $timerPath -Raw
$spuSource = Get-Content -LiteralPath $spuPath -Raw
$sprintSource = Get-Content -LiteralPath $sprintPath -Raw
$labSource = Get-Content -LiteralPath $labPath -Raw

foreach ($fragment in @(
    'event_ready',
    'event_wait',
    'semaphore_ready',
    'semaphore_wait',
    'timer_usleep',
    'spurs_start',
    'spurs_join',
    'es_sync_thread_class',
    'es_sync_profile_scope(const es_sync_profile_scope&) = delete'
)) {
    if (-not $headerSource.Contains($fragment)) {
        throw "Missing bounded synchronization site or scope contract: $fragment"
    }
}

foreach ($fragment in @(
    '::getenv("RPCS3_ES_SYNC_PROFILE")',
    'Emu.GetTitleID() == "BLUS30161"',
    'now - last < 5''000''000',
    'Eternal Sonata sync profile:',
    'event_wait_max_us=',
    'semaphore_wait_max_us=',
    'semaphore_wait_spurs_us=',
    'timer_requested_us=',
    'timer_spurs_us=',
    'Eternal Sonata sync long wait:',
    'elapsed_us >= 1''000''000',
    'long_log < 64',
    'spurs_join_max_us='
)) {
    if (-not $eventSource.Contains($fragment)) {
        throw "Missing title-gated synchronization aggregator contract: $fragment"
    }
}

if (-not $eventSource.Contains('es_sync.set_site(es_sync_site::event_wait)')) {
    throw "Event receives must distinguish immediate and blocked calls."
}
if (-not $semaphoreSource.Contains('es_sync.set_site(es_sync_site::semaphore_wait)')) {
    throw "Semaphore waits must distinguish immediate and blocked calls."
}
if (-not $timerSource.Contains('es_sync.set_requested_us(sleep_time)')) {
    throw "Timer profiling must retain the effective requested sleep."
}
foreach ($fragment in @(
    'is_es_spurs_sync_profile_candidate',
    'group.max_num != 1 || group.max_run != 1',
    'CellSpursKernelGroup',
    'SpursHdlr0',
    'es_sync_site::spurs_start',
    'es_sync_site::spurs_join'
)) {
    if (-not $spuSource.Contains($fragment)) {
        throw "Missing narrow SPURS synchronization contract: $fragment"
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataSyncProfile = "Off"',
    'EternalSonataSyncProfile = $EternalSonataSyncProfile'
)) {
    if (-not $sprintSource.Contains($fragment)) {
        throw "Missing speed-sprint synchronization-profile plumbing: $fragment"
    }
}

foreach ($fragment in @(
    '[string]$EternalSonataSyncProfile = "Off"',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_SYNC_PROFILE", $esSyncProfileEnv, "Process")',
    '[Environment]::SetEnvironmentVariable("RPCS3_ES_SYNC_PROFILE", $previousEsSyncProfile, "Process")',
    '$EternalSonataSyncProfile -eq "Profile")',
    '$syncSummaryPath = Join-Path $runDir "sync-profile.txt"',
    '$line.Contains("Eternal Sonata sync profile:")',
    '$line.Contains("Eternal Sonata sync long wait:")'
)) {
    if (-not $labSource.Contains($fragment)) {
        throw "Missing Windows-lab synchronization-profile contract: $fragment"
    }
}

foreach ($scriptPath in @($sprintPath, $labPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for '$scriptPath': $($errors[0].Message)"
    }
}

Write-Output "Thor Eternal Sonata synchronization-profile contract passed: the opt-in host probe is title-gated, bounded, and separates immediate calls from real waits."
