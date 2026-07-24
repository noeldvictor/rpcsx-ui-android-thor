$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sprintPath = Join-Path $repoRoot "tools/eternal_sonata_speed_sprint.ps1"
$analyzerPath = Join-Path $repoRoot "tools/analyze_thor_cool_title_capture.ps1"
$candidatePath = Join-Path $repoRoot "tools/thor_cool_title_candidate.psd1"
$candidate = Import-PowerShellDataFile -LiteralPath $candidatePath
$source = Get-Content -LiteralPath $sprintPath -Raw
$analyzerSource = Get-Content -LiteralPath $analyzerPath -Raw

$tokens = $null
$parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($sprintPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count) {
    throw "Eternal Sonata sprint wrapper has PowerShell parse errors: $($parseErrors.Message -join '; ')"
}

$sourceContracts = @(
    '[ValidateSet("Off", "ThorCoolTitle", "ThorCoolGameplay")]',
    '[string]$AndroidStartupProfile = "Off"',
    '$ScriptBoundParameters = @{} + $PSBoundParameters',
    'thor_cool_title_candidate.psd1',
    'AndroidExpectedInstalledApkSha256 = [string]$thorCoolTitleCandidate.ApkSha256',
    '$settings.AndroidRsxCacheCompileBudgetMs = 50',
    'AndroidSpuNativeObjectCache = "on"',
    '$ThorCoolTitleMinimumNativeObjects = 0',
    'ExpectedInstalledApkSha256 = $AndroidExpectedInstalledApkSha256',
    'if ($Action -notin @("AndroidRouteScene", "AndroidProfileStatus"))',
    'Set-Variable -Scope Script -Name $setting.Key -Value $setting.Value',
    'Set-AndroidStartupProfile',
    'Assert-ThorCoolRouteCooldown',
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
$cooldownGateIndex = $source.LastIndexOf('Assert-ThorCoolRouteCooldown', $deviceResolutionIndex)
$switchIndex = $source.IndexOf('switch ($Action)', $deviceResolutionIndex)
if ($applyIndex -lt 0 -or $cooldownGateIndex -le $applyIndex -or
    $deviceResolutionIndex -le $cooldownGateIndex -or $switchIndex -le $deviceResolutionIndex) {
    throw 'Thor startup profile/cooldown gate is no longer applied before device resolution and action dispatch.'
}

$deviceResolutionBlock = $source.Substring($deviceResolutionIndex, $switchIndex - $deviceResolutionIndex)
if ($deviceResolutionBlock.Contains('AndroidProfileStatus')) {
    throw 'AndroidProfileStatus must remain host-only and must not resolve or query ADB.'
}

$cooldownFunctionStart = $source.IndexOf('function Assert-ThorCoolRouteCooldown')
$serialFunctionStart = $source.IndexOf('function Resolve-SpeedAndroidSerial', $cooldownFunctionStart)
if ($cooldownFunctionStart -lt 0 -or $serialFunctionStart -le $cooldownFunctionStart) {
    throw 'Could not isolate the Thor cool-title cooldown gate.'
}
$cooldownFunction = $source.Substring($cooldownFunctionStart, $serialFunctionStart - $cooldownFunctionStart)
foreach ($fragment in @(
    'invoke_thor_cache_prepare.ps1',
    '-Action Status',
    '"device_contact"',
    '"spu_continuity_capture"',
    '"spu_continuity_apk_sha256"',
    '"cache_cooldown_ready"',
    '"cooldown_source_kind"',
    '"latest_title_capture"',
    '"latest_gameplay_capture"',
    '"minimum_required_spu_native_objects"',
    'requires at least one durable SPU native object',
    'SPU continuity was seeded by a different APK',
    'exceeds the safe startup preload envelope',
    'independent cooldown is not ready',
    '$script:ThorCoolTitleMinimumNativeObjects = $minimumObjects',
    '$script:AndroidSpuCachePreloadLimit = $minimumObjects'
)) {
    if (-not $cooldownFunction.Contains($fragment)) {
        throw "Thor cool-title cooldown gate is missing: $fragment"
    }
}

$summary = @(& $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle 2>&1 | ForEach-Object { $_.ToString() })
$requiredSummary = @(
    'profile=ThorCoolTitle',
    'route_profile=custom',
    'self_stopping=True',
    'package=net.rpcsx.easy',
    "expected_installed_apk_sha256=$($candidate.ApkSha256)",
    "expected_packaged_core_sha256=$($candidate.PackagedCoreSha256)",
    'input_macro=gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop',
    'input_mode=Direct',
    'scene_seconds=1',
    'thermal_poll_seconds=1',
    'thermal_stop_headroom_c=4',
    'thermal_probe_window_c=4',
    'preflight_samples=3',
    'preflight_interval_seconds=2',
    'preflight_headroom_c=0',
    'max_launch_silicon_c=35',
    'max_preflight_rise_c=1',
    'max_battery_c=34',
    'max_skin_c=40',
    'max_silicon_c=64',
    'rsx_workers=2',
    'rsx_preload_limit=64',
    'rsx_load_budget_ms=200',
    'rsx_compile_budget_ms=50',
    'spu_preload_limit=17',
    'spu_compile_budget_ms=50',
    'spu_native_object_cache=on',
    'cache_affinity_mask=7',
    'vk_pipeline_cache=on',
    'vk_hits_only=on',
    'cache_phase_pacing=off',
    'adpf=off',
    'log_mode=Quiet',
    'frame_wait=Fast',
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

$summaryValues = @{}
foreach ($line in $summary) {
    $separator = $line.IndexOf("=")
    if ($separator -gt 0) {
        $summaryValues[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
    }
}
foreach ($mapping in @(
    [pscustomobject]@{ Key = "thermal_stop_headroom_c"; AnalyzerLabel = "Runtime thermal early-stop headroom C" },
    [pscustomobject]@{ Key = "thermal_probe_window_c"; AnalyzerLabel = "Runtime thermal confirmation window C" },
    [pscustomobject]@{ Key = "max_silicon_c"; AnalyzerLabel = "Max silicon temperature C" },
    [pscustomobject]@{ Key = "rsx_compile_budget_ms"; AnalyzerLabel = "RSX cached pipeline compile budget ms (0=unbounded)" }
)) {
    if (-not $summaryValues.ContainsKey($mapping.Key)) {
        throw "Thor cool-title dry-run has no analyzer mapping value: $($mapping.Key)"
    }
    $requiredAnalyzerLine = '"- {0}: {1}"' -f $mapping.AnalyzerLabel, $summaryValues[$mapping.Key]
    if (-not $analyzerSource.Contains($requiredAnalyzerLine)) {
        throw "Thor title analyzer drifted from the route profile: missing $requiredAnalyzerLine"
    }
}

$gameplaySummary = @(& $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolGameplay -Scene field 2>&1 | ForEach-Object { $_.ToString() })
foreach ($line in @(
    'profile=ThorCoolGameplay',
    'route_profile=eternal-sonata-field-route',
    'self_stopping=True',
    'input_macro=',
    'input_mode=Direct',
    'max_launch_silicon_c=35',
    'thermal_stop_headroom_c=4',
    'thermal_probe_window_c=4',
    'max_silicon_c=64',
    'rsx_preload_limit=64',
    'rsx_compile_budget_ms=0',
    'spu_preload_limit=17',
    'spu_compile_budget_ms=50',
    'spu_native_object_cache=on',
    'no_perfetto=True',
    'no_screen_record=True',
    'keep_running=False',
    'route_post_wait_seconds=0'
)) {
    if ($gameplaySummary -notcontains $line) {
        throw "Thor cool-gameplay dry-run is missing: $line"
    }
}

$routeFunctionStart = $source.IndexOf('function Resolve-ThorCoolTitleInputCapture')
$profileApplyStart = $source.IndexOf('Set-AndroidStartupProfile', $routeFunctionStart)
if ($routeFunctionStart -lt 0 -or $profileApplyStart -le $routeFunctionStart) {
    throw 'Could not isolate the Android route function for cool-title stop/proof contracts.'
}
$routeFunction = $source.Substring($routeFunctionStart, $profileApplyStart - $routeFunctionStart)
$routeContracts = @(
    'function Resolve-ThorCoolTitleInputCapture',
    '$Failure.Exception.Data["ThorCaptureDirectory"]',
    '$_.Name -like "*-thor-input-$Profile"',
    '-Profile $macroParams.Profile',
    'function Write-ThorCoolTitleAnalysis',
    '$macroStartedAt = Get-Date',
    '$AndroidStartupProfile -eq "ThorCoolTitle"',
    '$AndroidStartupProfile -eq "ThorCoolGameplay"',
    '$macroParams.StopAfterMacro = $true',
    'catch {',
    'Write-ThorCoolTitleAnalysis -InputCapture $inputCapture',
    'failure analysis saved before propagating the route failure',
    'throw $routeFailure',
    'cool-gameplay profile self-stopped',
    'analyze_thor_cool_title_capture.ps1',
    'cool-title-analysis.json',
    '$analysisParams.RequireReady = $true',
    'MinimumSpuNativeObjects = $ThorCoolTitleMinimumNativeObjects',
    'ExpectedSpuCachePreloadLimit = $AndroidSpuCachePreloadLimit',
    'Write-ThorCoolTitleAnalysis -InputCapture $inputCapture -RequireReady',
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
    $conflictRejected = $_.Exception.Message -like "*requires -AndroidRsxCachePreloadLimit '64'*"
}
if (-not $conflictRejected) {
    throw 'Thor cool-title profile did not reject an explicit unsafe RSX preload-limit conflict.'
}

$loadBudgetConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidRsxCacheLoadBudgetMs 0 2>&1 | Out-Null
} catch {
    $loadBudgetConflictRejected = $_.Exception.Message -like "*requires -AndroidRsxCacheLoadBudgetMs '200'*"
}
if (-not $loadBudgetConflictRejected) {
    throw 'Thor cool-title profile did not reject an unbounded RSX load-budget override.'
}

$compileBudgetConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidRsxCacheCompileBudgetMs 0 2>&1 | Out-Null
} catch {
    $compileBudgetConflictRejected = $_.Exception.Message -like "*requires -AndroidRsxCacheCompileBudgetMs '50'*"
}
if (-not $compileBudgetConflictRejected) {
    throw 'Thor cool-title profile did not reject an unbounded RSX compile-budget override.'
}

$budgetConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidSpuCacheCompileBudgetMs 0 2>&1 | Out-Null
} catch {
    $budgetConflictRejected = $_.Exception.Message -like "*requires -AndroidSpuCacheCompileBudgetMs '50'*"
}
if (-not $budgetConflictRejected) {
    throw 'Thor cool-title profile did not reject an unbounded SPU compile-budget override.'
}

$nativeCacheConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidSpuNativeObjectCache off 2>&1 | Out-Null
} catch {
    $nativeCacheConflictRejected = $_.Exception.Message -like "*requires -AndroidSpuNativeObjectCache 'on'*"
}
if (-not $nativeCacheConflictRejected) {
    throw 'Thor cool-title profile did not reject disabling durable SPU native-object reuse.'
}

$apkIdentityConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidExpectedInstalledApkSha256 ('0' * 64) 2>&1 | Out-Null
} catch {
    $apkIdentityConflictRejected = $_.Exception.Message -like "*requires -AndroidExpectedInstalledApkSha256 '$($candidate.ApkSha256)'*"
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

$thermalCeilingConflictRejected = $false
try {
    & $sprintPath -Action AndroidProfileStatus -AndroidStartupProfile ThorCoolTitle -AndroidMaxSiliconTemperatureC 72 2>&1 | Out-Null
} catch {
    $thermalCeilingConflictRejected = $_.Exception.Message -like "*requires -AndroidMaxSiliconTemperatureC '64'*"
}
if (-not $thermalCeilingConflictRejected) {
    throw 'Thor cool-title profile did not reject the superseded 72 C hard ceiling.'
}

Write-Output 'Thor cool-title startup profile contract passed: exact APK/core identity, host-only dry-run, lower-power controls, unsafe overrides, and device-resolution gates are fail closed.'
