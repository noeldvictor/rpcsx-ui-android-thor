$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"
$source = Get-Content -LiteralPath $sprintPath -Raw

$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($sprintPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) {
    throw "Eternal Sonata sprint wrapper has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

$sourceContracts = @(
    '[ValidateSet("Off", "ThorCoolTitle")]',
    '[string]$AndroidStartupProfile = "Off"',
    '$ScriptBoundParameters = @{} + $PSBoundParameters',
    'thor_cool_title_candidate.psd1',
    'AndroidExpectedInstalledApkSha256 = [string]$thorCoolTitleCandidate.ApkSha256',
    'ExpectedInstalledApkSha256 = $AndroidExpectedInstalledApkSha256',
    'if ($Action -notin @("AndroidRouteScene", "AndroidProfileStatus"))',
    'Set-Variable -Scope Script -Name $setting.Key -Value $setting.Value',
    'Set-AndroidStartupProfile',
    '"AndroidProfileStatus" {',
    'Write-AndroidStartupProfileSummary'
)
foreach ($fragment in $sourceContracts) {
    if (-not $source.Contains($fragment)) {
        throw "Missing Thor cool-title profile source contract: $fragment"
    }
}

$applyIndex = $source.LastIndexOf('Set-AndroidStartupProfile', $source.IndexOf('if ($Action -in @('))
$deviceResolutionIndex = $source.IndexOf('if ($Action -in @(')
$switchIndex = $source.IndexOf('switch ($Action)', $deviceResolutionIndex)
if ($applyIndex -lt 0 -or $deviceResolutionIndex -le $applyIndex -or $switchIndex -le $deviceResolutionIndex) {
    throw 'Thor startup profile is no longer applied before device resolution and action dispatch.'
}

$deviceResolutionBlock = $source.Substring($deviceResolutionIndex, $switchIndex - $deviceResolutionIndex)
if ($deviceResolutionBlock.Contains('AndroidProfileStatus')) {
    throw 'AndroidProfileStatus must remain host-only and must not resolve or query ADB.'
}

$summary = @(& $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle 2>&1 | ForEach-Object { $_.ToString() })
$requiredSummary = @(
    'profile=ThorCoolTitle',
    'package=net.rpcsx.easy',
    'expected_installed_apk_sha256=E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073',
    'expected_packaged_core_sha256=CC2FF22E6D190B97E58E1466E139FB4DAC711F988A91FFF2C01D13B1CB5EA3CA',
    'input_macro=gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop',
    'input_mode=Direct',
    'scene_seconds=1',
    'thermal_poll_seconds=1',
    'thermal_stop_headroom_c=4',
    'thermal_probe_window_c=16',
    'preflight_samples=3',
    'preflight_interval_seconds=2',
    'preflight_headroom_c=0',
    'max_launch_silicon_c=35',
    'max_preflight_rise_c=1',
    'max_battery_c=34',
    'max_skin_c=40',
    'max_silicon_c=72',
    'rsx_workers=2',
    'rsx_preload_limit=256',
    'rsx_load_budget_ms=500',
    'rsx_compile_budget_ms=0',
    'spu_preload_limit=64',
    'spu_compile_budget_ms=100',
    'cache_affinity_mask=7',
    'vk_pipeline_cache=on',
    'vk_hits_only=on',
    'cache_phase_pacing=off',
    'adpf=off',
    'log_mode=Quiet',
    'frame_wait=Wait',
    'frame_grace_us=500',
    'frame_continuous_rearm=On',
    'no_perfetto=True',
    'no_screen_record=True',
    'keep_running=False',
    'route_post_wait_seconds=0'
)
foreach ($line in $requiredSummary) {
    if ($summary -notcontains $line) {
        throw "Thor cool-title dry-run is missing: $line"
    }
}
$routeFunctionStart = $source.IndexOf('function Invoke-AndroidRouteScene')
$profileApplyStart = $source.IndexOf('Set-AndroidStartupProfile', $routeFunctionStart)
if ($routeFunctionStart -lt 0 -or $profileApplyStart -le $routeFunctionStart) {
    throw 'Could not isolate the Android route function for cool-title stop/proof contracts.'
}
$routeFunction = $source.Substring($routeFunctionStart, $profileApplyStart - $routeFunctionStart)
$routeContracts = @(
    '$macroStartedAt = Get-Date',
    '$AndroidStartupProfile -eq "ThorCoolTitle"',
    'analyze_thor_cool_title_capture.ps1',
    '-RequireReady',
    'redundant live scene capture skipped',
    'return'
)
foreach ($fragment in $routeContracts) {
    if (-not $routeFunction.Contains($fragment)) {
        throw "Thor cool-title route is missing stop/proof contract: $fragment"
    }
}


$conflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidRsxCachePreloadLimit 0 2>&1 | Out-Null
} catch {
    $conflictRejected = $_.Exception.Message -like "*requires -AndroidRsxCachePreloadLimit '256'*"
}
if (-not $conflictRejected) {
    throw 'Thor cool-title profile did not reject an explicit unsafe RSX preload-limit conflict.'
}

$loadBudgetConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidRsxCacheLoadBudgetMs 0 2>&1 | Out-Null
} catch {
    $loadBudgetConflictRejected = $_.Exception.Message -like "*requires -AndroidRsxCacheLoadBudgetMs '500'*"
}
if (-not $loadBudgetConflictRejected) {
    throw 'Thor cool-title profile did not reject an unbounded RSX load-budget override.'
}

$budgetConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidSpuCacheCompileBudgetMs 0 2>&1 | Out-Null
} catch {
    $budgetConflictRejected = $_.Exception.Message -like "*requires -AndroidSpuCacheCompileBudgetMs '100'*"
}
if (-not $budgetConflictRejected) {
    throw 'Thor cool-title profile did not reject an unbounded SPU compile-budget override.'
}

$apkIdentityConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidExpectedInstalledApkSha256 ('0' * 64) 2>&1 | Out-Null
} catch {
    $apkIdentityConflictRejected = $_.Exception.Message -like "*requires -AndroidExpectedInstalledApkSha256 'E69ABCB05E2028C32197D4358E94F0EA8AF2E42366F75D8335AE40BB7A208073'*"
}
if (-not $apkIdentityConflictRejected) {
    throw 'Thor cool-title profile did not reject the wrong installed APK identity.'
}

$actionRejected = $false
try {
    & $sprintPath -Action ToolStatus -AndroidStartupProfile ThorCoolTitle 2>&1 | Out-Null
} catch {
    $actionRejected = $_.Exception.Message -like '*requires -Action AndroidRouteScene or AndroidProfileStatus*'
}
if (-not $actionRejected) {
    throw 'Thor cool-title profile did not reject a non-route action.'
}

$keepRunningRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -KeepAndroidRunningAfterCapture 2>&1 | Out-Null
} catch {
    $keepRunningRejected = $_.Exception.Message -like "*requires -KeepAndroidRunningAfterCapture 'False'*"
}
if (-not $keepRunningRejected) {
    throw 'Thor cool-title profile did not reject keeping the emulator alive after capture.'
}

Write-Output 'Thor cool-title startup profile contract passed: exact APK/core identity, host-only dry-run, lower-power controls, unsafe overrides, and device-resolution gates are fail closed.'
