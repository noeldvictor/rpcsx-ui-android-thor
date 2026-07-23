$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainActivityPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/MainActivity.kt"
$nativePath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/android/src/rpcsx-android.cpp"
$harnessPath = Join-Path $repoRoot "tools/invoke_thor_cache_prepare.ps1"
$commonPath = Join-Path $repoRoot "tools/thor_debug_common.ps1"
$processHealthPath = Join-Path $repoRoot "tools/thor_cache_prepare_process_health.ps1"
$progressPath = Join-Path $repoRoot "tools/thor_cache_prepare_progress.ps1"
$jitPath = Join-Path $repoRoot "app/src/main/cpp/rpcsx/rpcs3/util/JITLLVM.cpp"

$mainActivity = Get-Content -LiteralPath $mainActivityPath -Raw
$native = Get-Content -LiteralPath $nativePath -Raw
$harness = Get-Content -LiteralPath $harnessPath -Raw
. $commonPath
. $processHealthPath
. $progressPath
$jit = Get-Content -LiteralPath $jitPath -Raw

function Assert-Contains {
    param([string]$Source, [string]$Needle, [string]$Message)
    if (-not $Source.Contains($Needle)) {
        throw $Message
    }
}

$quotedPath = ConvertTo-ThorRemoteShellLiteral -Value "/storage/A B's (USA).iso"
if ($quotedPath -ne "'/storage/A B'`"'`"'s (USA).iso'") {
    throw "Remote-shell literal quoting did not preserve spaces, parentheses, and apostrophes."
}
$newlineRejected = $false
try {
    [void](ConvertTo-ThorRemoteShellLiteral -Value "bad`npath")
} catch {
    $newlineRejected = $true
}
if (-not $newlineRejected) {
    throw "Remote-shell literal quoting accepted a newline."
}

$fatalSignal = "07-22 16:41:10.000 F libc : Fatal signal 5 (SIGTRAP), code -6 in tid 12585 (RPCSX-PrepareCa), pid 12525 (net.rpcsx.easy)"
$activityDeath = "07-22 16:41:10.100 I ActivityManager: Process net.rpcsx.easy (pid 12525) has died: fg TOP"
if (-not (Test-ThorCachePrepareNativeProcessDeath -LogText $fatalSignal -Package "net.rpcsx.easy") -or
    -not (Test-ThorCachePrepareNativeProcessDeath -LogText $activityDeath -Package "net.rpcsx.easy")) {
    throw "Cache-preparation process health detector missed a target native death marker."
}
if (Test-ThorCachePrepareNativeProcessDeath -LogText $fatalSignal -Package "net.rpcsx.other") {
    throw "Cache-preparation process health detector matched another package."
}

$progressFixture = @'
S 0:00:09.000000 {TID: 100} PPU: LLVM: Module exists: cached.obj
S 0:00:10.000000 {PPUW.1.1} PPU: LLVM: Compiled module first.obj
W 0:00:11.000000 {PPUW.1.2} PPU: LLVM: Compiling module second.obj
W 0:00:11.100000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: module 2 of 41 (4m remaining))
'@
$progress = Get-ThorCachePrepareProgress -NativeText $progressFixture
if (-not $progress.has_reuse -or -not $progress.has_progress -or
    $progress.compiled_modules -ne 1 -or
    $progress.loaded_modules -ne 0 -or $progress.existing_modules -ne 1 -or
    $progress.reused_modules -ne 1 -or $progress.latest_module -ne 2 -or
    $progress.total_modules -ne 41 -or $progress.remaining_modules -ne 39 -or
    $progress.compile_worker_count -ne 2 -or
    ($progress.compile_worker_names -join ',') -ne 'PPUW.1.1,PPUW.1.2') {
    throw "Cache-preparation progress parser rejected a clean resumable checkpoint."
}
$firmwareProgressFixture = @"
S 0:00:40.000000 {PPUW.1.1} PPU: LLVM: Compiled module title.obj
W 0:00:40.100000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: module 4 of 5)
W 0:01:02.000000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: file 0 of 142, module 5 of 5)
S 0:01:07.000000 {PPUW.2.1} PPU: LLVM: Compiled module firmware.obj
W 0:01:32.000000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: file 70 of 142, module 8 of 11)
"@
$firmwareProgress = Get-ThorCachePrepareProgress -NativeText $firmwareProgressFixture
if (-not $firmwareProgress.has_progress -or
    $firmwareProgress.latest_module -ne 8 -or
    $firmwareProgress.total_modules -ne 11 -or
    $firmwareProgress.remaining_modules -ne 3 -or
    $firmwareProgress.latest_file -ne 70 -or
    $firmwareProgress.total_files -ne 142 -or
    $firmwareProgress.remaining_files -ne 72 -or
    $firmwareProgress.initial_module -ne 5 -or
    $firmwareProgress.initial_total_modules -ne 5 -or
    -not $firmwareProgress.initial_progress_observed -or
    -not $firmwareProgress.initial_workload_complete) {
    throw "Cache-preparation progress parser conflated completed EBOOT work with the growing firmware scan."
}
$warmEbootProgressFixture = @"
S 0:00:01.000000 {PPUW.1.1} PPU: LLVM: Module exists: cached-title.obj
W 0:00:01.100000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: file 0 of 142, module 0 of 1)
W 0:00:09.000000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: file 83 of 142, module 16 of 21)
"@
$warmEbootProgress = Get-ThorCachePrepareProgress -NativeText $warmEbootProgressFixture
if ($warmEbootProgress.initial_progress_observed -or
    -not $warmEbootProgress.initial_workload_complete -or
    $warmEbootProgress.initial_module -ne 0 -or
    $warmEbootProgress.initial_total_modules -ne 0 -or
    $warmEbootProgress.latest_file -ne 83 -or
    $warmEbootProgress.total_files -ne 142 -or
    $warmEbootProgress.latest_module -ne 16 -or
    $warmEbootProgress.total_modules -ne 21) {
    throw "Cache-preparation progress parser treated warm EBOOT firmware counters as initial-module progress."
}
$fileOnlyProgress = Get-ThorCachePrepareProgress -NativeText @"
W 0:00:01.100000 {Progress Dialog Server} ANDROID: ProgressMessageDialog::ProgressBarSetMsg(0, Progress: file 12 of 142)
"@
if (-not $fileOnlyProgress.initial_workload_complete -or
    $fileOnlyProgress.initial_progress_observed -or
    $fileOnlyProgress.latest_file -ne 12 -or
    $fileOnlyProgress.total_files -ne 142 -or
    $fileOnlyProgress.latest_module -ne 0 -or
    $fileOnlyProgress.total_modules -ne 0) {
    throw "Cache-preparation progress parser missed firmware scan entry before the first module is discovered."
}
$thermalSummary = Get-ThorCachePrepareThermalSummary `
    -SiliconTemperaturesC @(35.5, 38.1, 45.0, 49.4, 50.0) `
    -WarmThresholdC 45.0 `
    -ProbeThresholdC 50.0
if ($thermalSummary.sample_count -ne 5 -or
    [Math]::Round($thermalSummary.average_c, 2) -ne 43.6 -or
    $thermalSummary.minimum_c -ne 35.5 -or
    $thermalSummary.maximum_c -ne 50.0 -or
    $thermalSummary.at_or_above_warm -ne 3 -or
    $thermalSummary.at_or_above_probe -ne 1) {
    throw "Cache-preparation thermal summary lost sample or threshold accounting."
}
$emptyThermalSummary = Get-ThorCachePrepareThermalSummary -SiliconTemperaturesC @()
if ($emptyThermalSummary.sample_count -ne 0 -or
    $null -ne $emptyThermalSummary.average_c -or
    $emptyThermalSummary.at_or_above_warm -ne 0 -or
    $emptyThermalSummary.at_or_above_probe -ne 0) {
    throw "Cache-preparation thermal summary did not handle an empty run deterministically."
}
$lastCompletedAt = [DateTimeOffset]::Parse('2026-07-22T20:15:42-04:00')
$cooldownWaiting = Get-ThorCachePrepareCooldownState `
    -LastCompletedAt $lastCompletedAt `
    -Now ([DateTimeOffset]::Parse('2026-07-22T20:25:42-04:00')) `
    -MinimumMinutes 30
$cooldownReady = Get-ThorCachePrepareCooldownState `
    -LastCompletedAt $lastCompletedAt `
    -Now ([DateTimeOffset]::Parse('2026-07-22T20:45:42-04:00')) `
    -MinimumMinutes 30
$cooldownNoHistory = Get-ThorCachePrepareCooldownState -LastCompletedAt $null
if ($cooldownWaiting.ready -or
    $cooldownWaiting.remaining_seconds -ne 1200 -or
    $cooldownWaiting.ready_at.ToString('o') -ne '2026-07-22T20:45:42.0000000-04:00' -or
    -not $cooldownReady.ready -or $cooldownReady.remaining_seconds -ne 0 -or
    -not $cooldownNoHistory.ready -or $cooldownNoHistory.remaining_seconds -ne 0) {
    throw "Cache-preparation independent cooldown accounting is not fail-closed."
}
$thermalStopReuseFloor = Get-ThorCachePrepareReuseFloor -LatestReadmeText @'
- Status: failed
- Compiled modules this round: 16
- Reused modules this round: 153
- Failure: Runtime thermal stop: silicon reached the early threshold.
'@
$checkpointReuseFloor = Get-ThorCachePrepareReuseFloor -LatestReadmeText @'
- Status: cache-progress-checkpoint
- Compiled modules this round: 10
- Reused modules this round: 169
- Failure: none
'@
if ($thermalStopReuseFloor -ne 169 -or $checkpointReuseFloor -ne 179) {
    throw "Cache-preparation reuse floor did not preserve checkpoint continuity."
}
$malformedThermalStopRejected = $false
try {
    [void](Get-ThorCachePrepareReuseFloor -LatestReadmeText "- Status: failed`n- Failure: Runtime thermal stop: test")
} catch {
    $malformedThermalStopRejected = $true
}
if (-not $malformedThermalStopRejected) {
    throw "Malformed thermal-stop continuity evidence was accepted."
}
$malformedCheckpointRejected = $false
try {
    [void](Get-ThorCachePrepareReuseFloor -LatestReadmeText "- Status: cache-progress-checkpoint`n- Failure: none")
} catch {
    $malformedCheckpointRejected = $true
}
if (-not $malformedCheckpointRejected) {
    throw "Malformed checkpoint continuity evidence was accepted."
}
if ((Test-ThorCachePrepareNativeFatal -NativeText $progressFixture) -or
    -not (Test-ThorCachePrepareNativeFatal -NativeText "F 0:00:12.0 PPU: fatal")) {
    throw "Cache-preparation native-fatal classifier is not fail-closed."
}
foreach ($fragment in @(
    'fs::pending_file module_file;',
    'if (!module_file.commit())'
)) {
    Assert-Contains $jit $fragment "PPU cache object writes are no longer atomically committed: $fragment"
}

foreach ($fragment in @(
    'net.rpcsx.THOR_DEBUG_PREPARE_CACHE',
    'thorCachePrepareRequestId',
    'thorRequireManagedProfile',
    'Thor debug cache preparation rejected: request=',
    'reject("invalid-request-id")',
    'reject("missing-or-nonabsolute-path")',
    'reject("unsupported-title titleId=$titleId")',
    'reject("managed-profile-required")',
    'reject("library-inactive")',
    'reject("busy activeRequest=$activeRequestId")',
    'GameSettingsDatabase.applyRecommendedConfigForTitleId(this, titleId)',
    'val cacheGame = Game(GameInfoStore(gamePath))',
    'cacheGame.info.titleId.value = titleId',
    'Thor debug cache preparation accepted: request=',
    'GameCacheRepository.prepareGameCache(this, cacheGame)',
    'Thor debug cache preparation finished: request=',
    'maybeStartThorDebugCachePreparation(intent) || maybeStartThorDebugBoot(intent)'
)) {
    Assert-Contains $mainActivity $fragment "Missing debug cache-preparation route contract: $fragment"
}

$cacheHandlerStart = $mainActivity.IndexOf('private fun maybeStartThorDebugCachePreparation(sourceIntent: Intent?): Boolean')
$debugBootStart = $mainActivity.IndexOf('private fun maybeStartThorDebugBoot(sourceIntent: Intent?): Boolean', $cacheHandlerStart)
if ($cacheHandlerStart -lt 0 -or $debugBootStart -le $cacheHandlerStart) {
    throw "Could not isolate the debug cache-preparation handler."
}
$cacheHandler = $mainActivity.Substring($cacheHandlerStart, $debugBootStart - $cacheHandlerStart)

$actionGate = $cacheHandler.IndexOf('sourceIntent.action != "net.rpcsx.THOR_DEBUG_PREPARE_CACHE"')
$requestGate = $cacheHandler.IndexOf('if (requestId == "invalid")')
$titleGate = $cacheHandler.IndexOf('if (titleId != "BLUS30161")')
$managedIntentGate = $cacheHandler.IndexOf('if (!requireManagedProfile)')
$libraryGate = $cacheHandler.IndexOf('if (RPCSX.activeLibrary.value == null)')
$profileGate = $cacheHandler.IndexOf('GameSettingsDatabase.applyRecommendedConfigForTitleId(this, titleId)')
$acceptedLog = $cacheHandler.IndexOf('Thor debug cache preparation accepted: request=')
$prepareCall = $cacheHandler.IndexOf('GameCacheRepository.prepareGameCache(this, cacheGame)')
$finishedLog = $cacheHandler.IndexOf('Thor debug cache preparation finished: request=')
if ($actionGate -lt 0 -or $requestGate -le $actionGate -or $titleGate -le $requestGate -or
    $managedIntentGate -le $titleGate -or $libraryGate -le $managedIntentGate -or
    $profileGate -le $libraryGate -or $acceptedLog -le $profileGate -or
    $prepareCall -le $acceptedLog -or $finishedLog -le $prepareCall) {
    throw "Debug cache preparation is not fail-closed or its durable evidence is out of order."
}
if ($cacheHandler.Contains('RPCSXActivity') -or $cacheHandler.Contains('startActivity(')) {
    throw "Debug cache preparation can enter the game-boot activity path."
}
if (-not $cacheHandler.Contains('fun reject(reason: String): Boolean') -or
    -not $cacheHandler.Contains('return true')) {
    throw "Rejected cache intents are not consumed before launcher composition."
}

foreach ($fragment in @(
    'std::string scanRoot;',
    'std::string paramSfoPath;',
    'std::string titleId;',
    'getFileType(source) == FileType::Iso',
    'iso_dev::open(',
    'fs::set_virtual_device(isoPrefix, isoDevice)',
    'fs::set_virtual_device(isoPrefix, {})',
    'scanRoot = isoPrefix + "/PS3_GAME";',
    'paramSfoPath = scanRoot + "/PARAM.SFO";',
    'ebootPath = scanRoot + "/USRDIR/EBOOT.BIN";',
    '!isCachePreparationExecutable(ebootPath)',
    'sourceTitleId != titleId',
    '.scanRoot = std::move(scanRoot),',
    '.paramSfoPath = std::move(paramSfoPath),',
    '.titleId = titleId,',
    'Thor PPU cache source resolved: title=%s, source=%s,',
    'Thor PPU cache preparation activated: title=%s',
    'Thor PPU cache preparation completed: title=%s'
)) {
    Assert-Contains $native $fragment "Missing native cache-preparation evidence contract: $fragment"
}
$prepareStart = $native.IndexOf('bool prepare(JNIEnv *env, std::string path, std::string titleId,')
$prepareEnd = $native.IndexOf('private:', $prepareStart)
if ($prepareStart -lt 0 -or $prepareEnd -le $prepareStart) {
    throw "Could not isolate CompilationQueue::prepare."
}
$prepareBlock = $native.Substring($prepareStart, $prepareEnd - $prepareStart)
foreach ($fragment in @(
    'sourceKind = "iso";',
    'scanRoot = isoPrefix + "/PS3_GAME";',
    'paramSfoPath = scanRoot + "/PARAM.SFO";',
    'ebootPath = scanRoot + "/USRDIR/EBOOT.BIN";',
    'The selected game does not match the requested title ID.',
    'Thor PPU cache source resolved: title=%s, source=%s,'
)) {
    Assert-Contains $prepareBlock $fragment "Cache preparation is not fail-closed to the selected ISO/title root: $fragment"
}
if ($prepareBlock.Contains('vfs::mount("/dev_bdvd"')) {
    throw "Cache preparation mutates the global /dev_bdvd VFS mount."
}

$compileStart = $native.IndexOf('bool compile(JNIEnv *env, CompilationWorkload workload)')
$compileEnd = $native.IndexOf('} static g_compilationQueue;', $compileStart)
if ($compileStart -lt 0 -or $compileEnd -le $compileStart) {
    throw "Could not isolate CompilationQueue::compile."
}
$compileBlock = $native.Substring($compileStart, $compileEnd - $compileStart)
$boundedRoot = $compileBlock.IndexOf('workload.scanRoot.empty() ? workload.path : workload.scanRoot')
$queuedRoot = $compileBlock.IndexOf('dir_queue.push_back(rootPath.string());')
$precompileCall = $compileBlock.IndexOf('ppu_precompile(dir_queue, mod_list.empty() ? nullptr : &mod_list);')
$completionEvidence = $compileBlock.IndexOf('Thor PPU cache preparation completed: title=%s')
$finalization = $compileBlock.IndexOf('rpcsx_android.error("Finalization")')
if ($boundedRoot -lt 0 -or $queuedRoot -le $boundedRoot -or
    $precompileCall -le $queuedRoot -or $completionEvidence -le $precompileCall -or
    $finalization -le $completionEvidence) {
    throw "Native cache preparation is not bounded to its resolved root or completion evidence is out of order."
}

foreach ($fragment in @(
    '[string]$Serial = "c3ca0370"',
    '[int]$MaxSeconds = 70',
    '/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso',
    '$intentAction = "net.rpcsx.THOR_DEBUG_PREPARE_CACHE"',
    '$maxLaunchSiliconTemperatureC = 35.0',
    '$maxPreflightRiseC = 1.0',
    '$maxSiliconTemperatureC = 60.0',
    '$runtimeStopHeadroomC = 5.0',
    '$runtimeProbeWindowC = 10.0',
    '$runtimeWarmTelemetryC = 45.0',
    '$minimumCacheCooldownMinutes = 30.0',
    '$runtimeSiliconTemperaturesC += [double]$snapshot.silicon_temperature_c',
    'Runtime average silicon C:',
    'Runtime samples at or above $runtimeProbeSiliconC C:',
    'minimum_cache_cooldown_minutes=',
    'Cache cooldown refused before device contact:',
    'if ($stopwatch.Elapsed.TotalSeconds -ge $MaxSeconds)',
    '$remainingMilliseconds = [Math]::Max(',
    'Start-Sleep -Milliseconds ([Math]::Min($pollIntervalSeconds * 1000, $remainingMilliseconds))',
    '$preflightSamples = 3',
    'device_contact=False',
    'sha256sum',
    'Installed APK mismatch:',
    'am force-stop $package',
    'pidof $package',
    'thorCachePrepareRequestId',
    'thorRequireManagedProfile',
    'ConvertTo-ThorRemoteShellLiteral -Value $GamePath',
    '"--es", "path", $quotedGamePath',
    '$requestReachedApp = ($finalLogcat -join "`n").Contains($requestId)',
    'function Read-RecentLogcat',
    '@("logcat", "-d", "-v", "threadtime", "-t", "500")',
    '$logcat = Read-RecentLogcat',
    '$accepted = $accepted -or $logText.Contains',
    '$callbackFinished = $callbackFinished -or $logText.Contains',
    '$finalLogcat = Read-FreshLogcat',
    'Test-ThorCachePrepareNativeProcessDeath -LogText $logText -Package $package',
    'Cache preparation native process died before completion; inspect logcat-full.txt.',
    '$nativeText = Get-Content -LiteralPath $nativeLogPath -Raw',
    '$activationIndex = $nativeText.IndexOf($activationMarker',
    '$completionIndex = $nativeText.IndexOf($completionMarker',
    'Logcat accepted/finished or native activated/completed evidence is incomplete or internally out of order.',
    'RPCSX-log-not-collected.txt',
    'Get-ThorThermalRuntimeGuardDecision',
    'Thor debug cache preparation accepted: request=',
    'Thor PPU cache preparation activated: title=',
    'Thor PPU cache preparation completed: title=',
    'Thor debug cache preparation finished: request=',
    'Cache preparation unexpectedly entered the game-boot activity path.',
    'cache-prepared-exact-no-game-boot',
    'cache-progress-checkpoint',
    'progress_checkpoint=True',
    'required_compile_workers=2',
    'require_validated_cache_reuse=True',
    'minimum_required_reused_modules=',
    '$reuseFloorSatisfied = $cacheProgress.reused_modules -ge $minimumRequiredReuse',
    '$cacheProgress.has_reuse -and $reuseFloorSatisfied -and $cacheProgress.has_progress',
    'Minimum required reused modules:',
    'Reuse floor satisfied:',
    '$cacheProgress.has_reuse',
    '$cacheProgress.has_progress',
    '$cacheProgress.compile_worker_count -ge 2',
    'Initial EBOOT workload complete:',
    'Remaining firmware files to scan:',
    'Known remaining modules in scanned workload:',
    '$progressCheckpoint = $true'
)) {
    Assert-Contains $harness $fragment "Missing thermally bounded cache-preparation harness contract: $fragment"
}

if ($harness.Contains('$nativeActivated = $logText.Contains') -or
    $harness.Contains('$nativeCompleted = $logText.Contains')) {
    throw "Harness still expects native RPCSX markers in logcat instead of the pulled current RPCSX.log."
}

foreach ($forbidden in @(
    'net.rpcsx.THOR_DEBUG_BOOT',
    'thorReplaceCustomProfile',
    'monkey',
    '--ez BootGame',
    'pm clear',
    'uninstall'
)) {
    if ($harness.Contains($forbidden)) {
        throw "Cache-preparation harness contains forbidden game-boot/destructive route: $forbidden"
    }
}

$forceStopCount = ([regex]::Matches($harness, [regex]::Escape('am force-stop $package'))).Count
$pidCount = ([regex]::Matches($harness, [regex]::Escape('pidof $package'))).Count
if ($forceStopCount -lt 2 -or $pidCount -lt 2) {
    throw "Harness must force-stop and prove PID absence at both boundaries."
}
$cooldownGateIndex = $harness.IndexOf('if (-not $cacheCooldown.ready)')
$adbResolveIndex = $harness.IndexOf('$adb = Resolve-ThorAdb')
if ($cooldownGateIndex -lt 0 -or $adbResolveIndex -le $cooldownGateIndex) {
    throw "Cache cooldown gate can resolve or contact ADB before refusing an early retry."
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($harnessPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "Cache-preparation harness PowerShell AST parse failed: $($errors -join '; ')"
}

Write-Output "Thor cache-preparation route contract passed: debug-only BLUS30161 intent, native completion evidence, exact APK identity, bounded thermal stop, no game boot, and final PID absence are fail-closed."
