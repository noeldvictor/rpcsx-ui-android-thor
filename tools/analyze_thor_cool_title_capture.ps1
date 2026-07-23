param(
    [Parameter(Mandatory = $true)]
    [string]$CaptureDir,
    [ValidateRange(1, 64)]
    [int]$MinimumSpuNativeObjects = 1,
    [switch]$RequireReady,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$candidatePath = Join-Path $PSScriptRoot "thor_cool_title_candidate.psd1"
$candidate = Import-PowerShellDataFile -LiteralPath $candidatePath
if ([string]$candidate.ApkSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "Thor cool-title candidate APK identity is invalid: $candidatePath"
}
$expectedInstalledApkSha256 = $candidate.ApkSha256.ToUpperInvariant()

$resolvedCaptureDir = (Resolve-Path -LiteralPath $CaptureDir -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedCaptureDir -PathType Container)) {
    throw "Thor cool-title capture directory does not exist: $CaptureDir"
}

function Get-LastEvidenceValue {
    param([string]$Name)

    $path = Join-Path $resolvedCaptureDir $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    return @(
        Get-Content -LiteralPath $path |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith("#") }
    ) | Select-Object -Last 1
}

function Read-OptionalLines {
    param([string]$Name)

    $path = Join-Path $resolvedCaptureDir $Name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        return @(Get-Content -LiteralPath $path)
    }
    return @()
}

$effectiveProperties = [ordered]@{
    "rsx-cache-workers-effective.txt" = "2"
    "rsx-cache-preload-limit-effective.txt" = "64"
    "rsx-cache-load-budget-effective.txt" = "200"
    "rsx-cache-compile-budget-effective.txt" = "0"
    "spu-cache-preload-limit-effective.txt" = "17"
    "spu-cache-compile-budget-effective.txt" = "50"
    "spu-native-object-cache-effective.txt" = "on"
    "cache-worker-affinity-effective.txt" = "7"
    "vk-pipeline-cache-effective.txt" = "on"
    "vk-preload-cache-hits-only-effective.txt" = "on"
    "adpf-rsx-effective.txt" = "off"
    "cache-phase-pacing-effective.txt" = "off"
}

$profilePropertyMismatches = New-Object System.Collections.Generic.List[string]
foreach ($entry in $effectiveProperties.GetEnumerator()) {
    $actual = Get-LastEvidenceValue $entry.Key
    if ($actual -cne $entry.Value) {
        $actualText = if ($null -eq $actual) { "<missing>" } else { $actual }
        $profilePropertyMismatches.Add("$($entry.Key): expected '$($entry.Value)', got '$actualText'") | Out-Null
    }
}

$startupExpected = [ordered]@{
    "debug.rpcsx.thor.rsx_cache_workers" = "2"
    "debug.rpcsx.thor.rsx_cache_preload_limit" = "64"
    "debug.rpcsx.thor.rsx_cache_load_budget_ms" = "200"
    "debug.rpcsx.thor.rsx_cache_compile_budget_ms" = "0"
    "debug.rpcsx.thor.spu_cache_preload_limit" = "17"
    "debug.rpcsx.thor.spu_cache_compile_budget_ms" = "50"
    "debug.rpcsx.thor.spu_native_object_cache" = "on"
    "debug.rpcsx.thor.cache_worker_affinity_mask" = "7"
    "debug.rpcsx.thor.vk_pipeline_cache" = "on"
    "debug.rpcsx.thor.vk_preload_cache_hits_only" = "on"
    "debug.rpcsx.thor.adpf_rsx" = "off"
    "debug.rpcsx.thor.cache_phase_pacing" = "off"
    "debug.rpcsx.thor.logcat" = "0"
    "debug.rpcsx.thor.syscall_stats" = "0"
    "debug.rpcsx.thor.spu_reduced_loop_detect" = "0"
    "debug.rpcsx.thor.spu_reduced_loop_emit" = "0"
    "debug.rpcsx.thor.spurs_probe" = "0"
    "debug.rpcsx.thor.es_sema_superpath" = "off"
    "debug.rpcsx.thor.es_dma_superpath" = "off"
    "debug.rpcsx.thor.rsx_blit_source_resolve" = "off"
    "debug.rpcsx.thor.rsx_auditor" = "0"
    "debug.rpcsx.thor.dump_prx" = "0"
    "debug.rpcsx.thor.es_frame_wait" = "wait"
    "debug.rpcsx.thor.es_frame_wait_grace_us" = "500"
    "debug.rpcsx.thor.es_frame_wait_continuous_rearm" = "on"
    "log.tag.RPCS3" = "S"
    "log.tag.RPCSX-UI" = "W"
}

$startupActual = @{}
foreach ($line in (Read-OptionalLines "startup-profile-effective.txt")) {
    if ($line -match '^([^#][^=]+)=(.*)$') {
        $startupActual[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
foreach ($entry in $startupExpected.GetEnumerator()) {
    $actual = if ($startupActual.ContainsKey($entry.Key)) { $startupActual[$entry.Key] } else { $null }
    if ($actual -cne $entry.Value) {
        $actualText = if ($null -eq $actual) { "<missing>" } else { $actual }
        $profilePropertyMismatches.Add("startup $($entry.Key): expected '$($entry.Value)', got '$actualText'") | Out-Null
    }
}

$cleanupExpected = [ordered]@{
    "debug.rpcsx.thor.rsx_cache_workers" = "0"
    "debug.rpcsx.thor.rsx_cache_preload_limit" = "0"
    "debug.rpcsx.thor.rsx_cache_load_budget_ms" = "0"
    "debug.rpcsx.thor.rsx_cache_compile_budget_ms" = "0"
    "debug.rpcsx.thor.spu_cache_preload_limit" = "0"
    "debug.rpcsx.thor.spu_cache_compile_budget_ms" = "0"
    "debug.rpcsx.thor.spu_native_object_cache" = "off"
    "debug.rpcsx.thor.cache_worker_affinity_mask" = "0"
    "debug.rpcsx.thor.vk_pipeline_cache" = "on"
    "debug.rpcsx.thor.vk_preload_cache_hits_only" = "off"
    "debug.rpcsx.thor.adpf_rsx" = "off"
    "debug.rpcsx.thor.cache_phase_pacing" = "off"
    "debug.rpcsx.thor.es_ppu_command_interp" = "off"
    "debug.rpcsx.thor.es_ppu_dispatch_probe" = "off"
    "debug.rpcsx.thor.es_async_draw_barrier" = "off"
    "debug.rpcsx.thor.es_sema_superpath" = "off"
    "debug.rpcsx.thor.es_dma_superpath" = "off"
    "debug.rpcsx.thor.rsx_blit_source_resolve" = "off"
    "debug.rpcsx.thor.es_frame_wait" = "off"
    "debug.rpcsx.thor.es_frame_wait_grace_us" = "0"
    "debug.rpcsx.thor.es_frame_wait_continuous_rearm" = "off"
}
$cleanupActual = @{}
foreach ($line in (Read-OptionalLines "startup-profile-reset-effective.txt")) {
    if ($line -match '^([^#][^=]+)=(.*)$') {
        $cleanupActual[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
$cleanupPropertyMismatches = New-Object System.Collections.Generic.List[string]
foreach ($entry in $cleanupExpected.GetEnumerator()) {
    $actual = if ($cleanupActual.ContainsKey($entry.Key)) { $cleanupActual[$entry.Key] } else { $null }
    if ($actual -cne $entry.Value) {
        $actualText = if ($null -eq $actual) { "<missing>" } else { $actual }
        $cleanupPropertyMismatches.Add("$($entry.Key): expected reset '$($entry.Value)', got '$actualText'") | Out-Null
    }
}
$failureCleanupActual = @{}
foreach ($line in (Read-OptionalLines "startup-profile-failure-reset-effective.txt")) {
    if ($line -match '^([^#][^=]+)=(.*)$') {
        $failureCleanupActual[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
$failureCleanupPropertyMismatches = New-Object System.Collections.Generic.List[string]
foreach ($entry in $cleanupExpected.GetEnumerator()) {
    $actual = if ($failureCleanupActual.ContainsKey($entry.Key)) { $failureCleanupActual[$entry.Key] } else { $null }
    if ($actual -cne $entry.Value) {
        $actualText = if ($null -eq $actual) { "<missing>" } else { $actual }
        $failureCleanupPropertyMismatches.Add("$($entry.Key): expected failure reset '$($entry.Value)', got '$actualText'") | Out-Null
    }
}
$installedApkIdentity = @{}
foreach ($line in (Read-OptionalLines "installed-apk-identity.txt")) {
    if ($line -match '^([^#][^=]+)=(.*)$') {
        $installedApkIdentity[$Matches[1].Trim()] = $Matches[2].Trim()
    }
}
$installedApkExpected = [ordered]@{
    "package" = [string]$candidate.Package
    "expected_sha256" = $expectedInstalledApkSha256
    "actual_sha256" = $expectedInstalledApkSha256
    "match" = "True"
}
foreach ($entry in $installedApkExpected.GetEnumerator()) {
    $actual = if ($installedApkIdentity.ContainsKey($entry.Key)) { $installedApkIdentity[$entry.Key] } else { $null }
    if ($actual -cne $entry.Value) {
        $actualText = if ($null -eq $actual) { "<missing>" } else { $actual }
        $profilePropertyMismatches.Add("installed APK $($entry.Key): expected '$($entry.Value)', got '$actualText'") | Out-Null
    }
}
$installedApkRemotePath = if ($installedApkIdentity.ContainsKey("remote_path")) {
    $installedApkIdentity["remote_path"]
} else {
    $null
}
if ($installedApkRemotePath -notmatch '^/.+/base[.]apk$') {
    $actualText = if ($null -eq $installedApkRemotePath) { "<missing>" } else { $installedApkRemotePath }
    $profilePropertyMismatches.Add("installed APK remote_path is not an exact base.apk path: '$actualText'") | Out-Null
}

$requiredReadmeLines = @(
    "- Input mode: Direct",
    "- Thermal preflight samples: 3",
    "- Thermal preflight interval seconds: 2",
    "- Thermal preflight headroom C: 0",
    "- Max launch silicon temperature C: 35",
    "- Thermal preflight max silicon rise C: 1",
    "- Thermal poll interval seconds: 1",
    "- Runtime thermal early-stop headroom C: 4",
    "- Runtime thermal confirmation window C: 16",
    "- Max battery temperature C: 34",
    "- Max skin temperature C: 40",
    "- Max silicon temperature C: 68",
    "- RSX cache preload workers (0=auto): 2",
    "- RSX cached pipeline preload limit (0=all): 64",
    "- RSX cached pipeline load budget ms (0=unbounded): 200",
    "- RSX cached pipeline compile budget ms (0=unbounded): 0",
    "- SPU cached-program preload limit (0=all): 17",
    "- SPU cached-program compile budget ms (0=unbounded): 50",
    "- Startup cache-worker affinity mask (0=default scheduler): 7",
    "- Persistent Vulkan driver pipeline cache: on",
    "- Vulkan preload cache hits only: on",
    "- Android RSX performance hint: off",
    "- Startup cache phase pacing: off",
    "- Expected installed APK SHA-256: $expectedInstalledApkSha256",
    "- Macro: gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop"
)
$readmeText = (Read-OptionalLines "README.md") -join "`n"
foreach ($requiredLine in $requiredReadmeLines) {
    if (-not $readmeText.Contains($requiredLine)) {
        $profilePropertyMismatches.Add("README missing exact profile row: $requiredLine") | Out-Null
    }
}

$expectedMacroTokens = @(
    "gate:ppu-ready:90000",
    "shot:title-proof",
    "check:visual:title-menu",
    "check:guest:title-proof",
    "stop"
)
$actualMacroTokens = @(
    Read-OptionalLines "macro.log" |
        ForEach-Object { ($_ -replace '^\S+\s+', '').Trim() } |
        Where-Object { $_ }
)
if (($actualMacroTokens -join "|") -cne ($expectedMacroTokens -join "|")) {
    $profilePropertyMismatches.Add("macro.log did not execute the exact bounded title-proof/stop sequence") | Out-Null
}

$debugBootHandshakeLines = Read-OptionalLines "debug-boot-handshake-status.log"
$debugBootAccepted = @($debugBootHandshakeLines | Where-Object { $_ -match '\bstatus=accepted\b' }).Count -gt 0
$debugBootRejected = @($debugBootHandshakeLines | Where-Object { $_ -match '\bstatus=rejected\b' }).Count -gt 0
$debugBootTimedOut = @($debugBootHandshakeLines | Where-Object { $_ -match '\bstatus=timeout\b' }).Count -gt 0
$guestLogTrusted = $debugBootAccepted
$logFiles = if ($guestLogTrusted) {
    @(
        Get-ChildItem -LiteralPath $resolvedCaptureDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(RPCSX.*\.log|guest-health.*\.log|logcat.*\.txt)$' }
    )
} else {
    @()
}
$guestLogLines = New-Object System.Collections.Generic.List[string]
foreach ($file in $logFiles) {
    foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
        $guestLogLines.Add($line) | Out-Null
    }
}
$guestLogText = $guestLogLines -join "`n"
$guestLogLatestEmulatorSeconds = $null
foreach ($line in $guestLogLines) {
    if ($line -match '(?<!\d)(?<hours>\d+):(?<minutes>\d{2}):(?<seconds>\d{2})[.](?<fraction>\d{6})(?!\d)') {
        $timestampSeconds =
            ([double]$Matches.hours * 3600) +
            ([double]$Matches.minutes * 60) +
            [double]$Matches.seconds +
            ([double]$Matches.fraction / 1000000)
        if ($null -eq $guestLogLatestEmulatorSeconds -or $timestampSeconds -gt $guestLogLatestEmulatorSeconds) {
            $guestLogLatestEmulatorSeconds = $timestampSeconds
        }
    }
}
$spuNativeObjectPhaseMarker = "Thor SPU native-object cache enabled for startup LLVM objects:"
$spuNativeObjectPhaseIndex = $guestLogText.IndexOf($spuNativeObjectPhaseMarker, [StringComparison]::Ordinal)
$spuNativeObjectPhaseText = if ($spuNativeObjectPhaseIndex -ge 0) {
    $spuNativeObjectPhaseEndIndex = $guestLogText.IndexOf("SPU Runtime: Workers built", $spuNativeObjectPhaseIndex, [StringComparison]::Ordinal)
    if ($spuNativeObjectPhaseEndIndex -gt $spuNativeObjectPhaseIndex) {
        $guestLogText.Substring($spuNativeObjectPhaseIndex, $spuNativeObjectPhaseEndIndex - $spuNativeObjectPhaseIndex)
    } else {
        $guestLogText.Substring($spuNativeObjectPhaseIndex)
    }
} else {
    ""
}
$spuNativeObjectLoadCount = ([regex]::Matches(
    $spuNativeObjectPhaseText,
    '(?m)LLVM: Loaded module: [^\r\n]+[.]obj\r?$'
)).Count
$spuNativeObjectReuseFloorSatisfied = $spuNativeObjectLoadCount -ge $MinimumSpuNativeObjects

$activationRequirements = [ordered]@{
    "two little-core PPU compile threads" = 'Max LLVM Compile Threads:\s*2'
    "PPU efficiency-core startup affinity" = 'Thor PPU (?:LLVM compile-worker|warm-cache link) affinity enabled:\s*requested=0x7, effective=0x7'
    "bounded RSX preload" = 'Android shader cache preload limit:\s*64 of'
    "bounded RSX load time" = 'Android shader cache load budget enabled for BLUS30161:\s*200 ms'
    "deferred RSX load fallback" = 'Android shader cache load budget:\s*attempted \d+ of \d+ cached pipelines with a 200 ms budget; \d+ will load and compile on demand\.'
    "bounded SPU preload" = 'Thor SPU cache preload limit:\s*17 of'
    "SPU native-object cache activation" = 'Thor SPU native-object cache enabled for startup LLVM objects:'
    "SPU native-object reuse" = '(?m)LLVM: Loaded module: [^\r\n]+[.]obj\r?$'
    "two RSX preload workers" = 'Shader cache preload workers:\s*load=2, compile=2'
    "RSX efficiency-core affinity" = 'Thor RSX cache-worker affinity enabled for load:\s*requested=0x7, effective=0x7'
    "SPU efficiency-core affinity" = 'Thor SPU cache-worker affinity enabled:\s*requested=0x7, effective=0x7'
    "two SPU preload workers" = 'Thor SPU cache-worker pool matched to affinity:\s*requested=2, workers=2, mask=0x7'
    "bounded SPU compile time" = 'Thor SPU cache compile budget enabled for BLUS30161:\s*50 ms'
    "warm Vulkan hit-only preload" = 'Vulkan preload cache-hits-only enabled for validated warm seed'
    "managed hardware FTZ" = 'Set DAZ and FTZ:\s*true'
}
$activationMissing = New-Object System.Collections.Generic.List[string]
foreach ($entry in $activationRequirements.GetEnumerator()) {
    if ($guestLogText -notmatch $entry.Value) {
        $activationMissing.Add($entry.Key) | Out-Null
    }
}
if (-not $spuNativeObjectReuseFloorSatisfied -and $activationMissing -notcontains "SPU native-object reuse") {
    $activationMissing.Add("SPU native-object reuse") | Out-Null
}

$activationFallbackPattern = 'cache-worker affinity was not applied exactly|warm-cache link affinity was not applied exactly|preload cache-hits-only was requested (?:without|but)|startup cache phase pacing timed out'
$activationFallbackHits = @(
    $guestLogLines |
        Select-String -Pattern $activationFallbackPattern -CaseSensitive:$false |
        ForEach-Object { $_.Line.Trim() } |
        Sort-Object -Unique
)
$fatalHits = @(
    Get-ThorGuestFatalMatches -Lines $guestLogLines |
        ForEach-Object { $_.Line.Trim() } |
        Sort-Object -Unique
)

$thermalLines = Read-OptionalLines "thermal-guard.log"
$macroFailureLines = Read-OptionalLines "macro-failure.txt"
$thermalFailureLines = @(
    $thermalLines | Where-Object { $_ -match 'status=failed' }
    $macroFailureLines |
        Where-Object { $_ -match '(?i)thermal|temperature' } |
        ForEach-Object { "macro-failure: $($_.Trim())" }
)
$preflightRefusalLines = @(
    $thermalLines |
        Where-Object {
            $_ -match 'stage=pre-run-\d+-of-\d+' -and
            $_ -match 'status=failed'
        } |
        ForEach-Object { $_.Trim() }
    $macroFailureLines |
        Where-Object { $_ -match "(?i)Stage 'pre-run-\d+-of-\d+'" } |
        ForEach-Object { $_.Trim() }
)
$failurePidLines = Read-OptionalLines "failure-pid.txt"
$failurePidValues = @(
    $failurePidLines |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+(?:\s+\d+)*$' }
)
$processAbsentAtFailure = $failurePidLines.Count -gt 0 -and $failurePidValues.Count -eq 0
$failureCleanupReady = $processAbsentAtFailure -and $failureCleanupPropertyMismatches.Count -eq 0
$siliconTemperatures = New-Object System.Collections.Generic.List[double]
foreach ($line in $thermalLines) {
    if ($line -match 'silicon_temperature_c=([0-9]+(?:\.[0-9]+)?)') {
        $siliconTemperatures.Add([double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)) | Out-Null
    }
}
$maxSiliconTemperatureC = if ($siliconTemperatures.Count) {
    [Math]::Round(($siliconTemperatures | Measure-Object -Maximum).Maximum, 1)
} else {
    $null
}
if ($thermalLines.Count -eq 0) {
    $profilePropertyMismatches.Add("thermal-guard.log is missing") | Out-Null
}

$gateLines = Read-OptionalLines "ppu-ready-gate.log"
$gateStable = $false
$gateEvidenceSource = "log"
$gateFrameCount = 0
$gateFrameErrors = New-Object System.Collections.Generic.List[string]
$firstTitleFrameElapsedMs = $null
$stableTitleFrameElapsedMs = $null
foreach ($gateLine in $gateLines) {
    if ($gateLine -notmatch 'elapsed_ms=(\d+)') {
        continue
    }

    $elapsedMs = [long]$Matches[1]
    if ($gateLine -notmatch 'title_menu_present=True') {
        continue
    }
    if ($null -eq $firstTitleFrameElapsedMs -or $elapsedMs -lt $firstTitleFrameElapsedMs) {
        $firstTitleFrameElapsedMs = $elapsedMs
    }
    if ($gateLine -match 'ready_candidate_count=([2-9]|[1-9][0-9]+)' -and
        ($null -eq $stableTitleFrameElapsedMs -or $elapsedMs -lt $stableTitleFrameElapsedMs)) {
        $stableTitleFrameElapsedMs = $elapsedMs
    }
}
$gateFrames = @(Get-ChildItem -LiteralPath $resolvedCaptureDir -File -Filter "*-ppu-ready-poll-*.png" -ErrorAction SilentlyContinue | Sort-Object Name)
if ($gateFrames.Count -gt 0) {
    $gateEvidenceSource = "frame-replay"
    $consecutiveTitleFrames = 0
    foreach ($gateFrame in $gateFrames) {
        $gateFrameCount++
        try {
            $gateClassification = Get-ThorBattleUiClassification -Path $gateFrame.FullName
            if ($gateClassification.title_menu_present) {
                $consecutiveTitleFrames++
                if ($consecutiveTitleFrames -ge 2) {
                    $gateStable = $true
                }
            } else {
                $consecutiveTitleFrames = 0
            }
        } catch {
            $consecutiveTitleFrames = 0
            $gateFrameErrors.Add("$($gateFrame.Name): $($_.Exception.Message)") | Out-Null
        }
    }
} else {
    $gateStable = @(
        $gateLines | Where-Object {
            $_ -match 'ready_candidate_count=([2-9]|[1-9][0-9]+)' -and
            $_ -match 'title_menu_present=True'
        }
    ).Count -gt 0
}

$titleProof = Get-ChildItem -LiteralPath $resolvedCaptureDir -File -Filter "*-title-proof.png" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$titleMenuPresent = $false
$launcherUiPresent = $false
$titleMagentaPercent = $null
$titleClassificationError = $null
if ($titleProof) {
    try {
        $classification = Get-ThorBattleUiClassification -Path $titleProof.FullName
        $titleMenuPresent = [bool]$classification.title_menu_present
        $launcherUiPresent = [bool]$classification.launcher_ui_present
        $titleMagentaPercent = $classification.title_magenta_percent
    } catch {
        $titleClassificationError = $_.Exception.Message
    }
}
$gateTimingReady = (
    $titleMenuPresent -and
    $gateStable -and
    $null -ne $firstTitleFrameElapsedMs -and
    $null -ne $stableTitleFrameElapsedMs -and
    $stableTitleFrameElapsedMs -ge $firstTitleFrameElapsedMs
)
$titleStabilityWindowMs = if ($gateTimingReady) {
    $stableTitleFrameElapsedMs - $firstTitleFrameElapsedMs
} else {
    $null
}
if (-not $titleMenuPresent -or -not $gateStable) {
    $firstTitleFrameElapsedMs = $null
    $stableTitleFrameElapsedMs = $null
}
$guestLogEvidenceIncomplete = (
    $titleMenuPresent -and
    $gateStable -and
    $activationMissing.Count -gt 0 -and
    $null -ne $guestLogLatestEmulatorSeconds -and
    $guestLogLatestEmulatorSeconds -lt 1.0
)

$macroFailure = $macroFailureLines.Count -gt 0
$stopEvidence = Test-Path -LiteralPath (Join-Path $resolvedCaptureDir "macro-stop.txt") -PathType Leaf
$postPidPath = Join-Path $resolvedCaptureDir "post-pid.txt"
$postPidEvidence = Test-Path -LiteralPath $postPidPath -PathType Leaf
$postPidValue = Get-LastEvidenceValue "post-pid.txt"
$processAbsentAfterProof = $postPidEvidence -and ($null -eq $postPidValue -or $postPidValue -notmatch '^\d+(?:\s+\d+)*$')
$stoppedAfterProof = $stopEvidence -and $processAbsentAfterProof
$cleanupReady = $stoppedAfterProof -and $cleanupPropertyMismatches.Count -eq 0
$profileActivationReady = (
    $profilePropertyMismatches.Count -eq 0 -and
    $activationMissing.Count -eq 0 -and
    $activationFallbackHits.Count -eq 0
)
$readyForComparison = (
    $profileActivationReady -and
    $debugBootAccepted -and
    -not $macroFailure -and
    $thermalFailureLines.Count -eq 0 -and
    $fatalHits.Count -eq 0 -and
    $gateStable -and
    $gateTimingReady -and
    $titleMenuPresent -and
    $cleanupReady
)

$status = if ($preflightRefusalLines.Count -gt 0 -and $processAbsentAtFailure -and -not $titleMenuPresent) {
    "preflight-refused-hot"
} elseif ($thermalFailureLines.Count -gt 0 -and -not $titleMenuPresent) {
    "thermal-stop-before-title"
} elseif ($fatalHits.Count -gt 0 -and -not $titleMenuPresent) {
    "fatal-before-title"
} elseif ($launcherUiPresent) {
    "launcher-ui-instead-of-title"
} elseif ($debugBootRejected) {
    "debug-boot-rejected"
} elseif ($debugBootTimedOut) {
    "debug-boot-handshake-timeout"
} elseif ($macroFailure -and -not $titleMenuPresent) {
    "route-failed-before-title"
} elseif (-not $titleProof) {
    "title-proof-missing"
} elseif (-not $titleMenuPresent) {
    "title-proof-invalid"
} elseif ($thermalFailureLines.Count -gt 0) {
    "thermal-stop-at-title"
} elseif ($fatalHits.Count -gt 0) {
    "fatal-at-title"
} elseif (-not $debugBootAccepted) {
    "debug-boot-handshake-missing"
} elseif ($guestLogEvidenceIncomplete) {
    "title-proof-log-incomplete"
} elseif (-not $profileActivationReady) {
    "activation-incomplete"
} elseif (-not $gateStable -or -not $gateTimingReady -or -not $cleanupReady -or $macroFailure) {
    "proof-sequence-incomplete"
} else {
    "title-proof-ready"
}

$result = [pscustomobject]@{
    status = $status
    ready_for_comparison = $readyForComparison
    speed_credit = $false
    capture_dir = $resolvedCaptureDir
    expected_installed_apk_sha256 = $expectedInstalledApkSha256
    actual_installed_apk_sha256 = $installedApkIdentity["actual_sha256"]
    packaged_core_sha256 = [string]$candidate.PackagedCoreSha256
    title_proof = if ($titleProof) { $titleProof.FullName } else { $null }
    title_menu_present = $titleMenuPresent
    launcher_ui_present = $launcherUiPresent
    title_magenta_percent = $titleMagentaPercent
    title_classification_error = $titleClassificationError
    ppu_ready_gate_stable = $gateStable
    ppu_ready_gate_evidence_source = $gateEvidenceSource
    ppu_ready_gate_frame_count = $gateFrameCount
    ppu_ready_gate_frame_errors = @($gateFrameErrors)
    first_title_frame_elapsed_ms = $firstTitleFrameElapsedMs
    stable_title_frame_elapsed_ms = $stableTitleFrameElapsedMs
    title_stability_window_ms = $titleStabilityWindowMs
    stopped_after_proof = $stoppedAfterProof
    cleanup_ready = $cleanupReady
    debug_boot_accepted = $debugBootAccepted
    debug_boot_rejected = $debugBootRejected
    debug_boot_timed_out = $debugBootTimedOut
    guest_log_trusted = $guestLogTrusted
    guest_log_latest_emulator_seconds = $guestLogLatestEmulatorSeconds
    guest_log_evidence_incomplete = $guestLogEvidenceIncomplete
    post_proof_pid_value = $postPidValue
    max_silicon_temperature_c = $maxSiliconTemperatureC
    thermal_failure_lines = @($thermalFailureLines)
    preflight_refusal_lines = @($preflightRefusalLines)
    process_absent_at_failure = $processAbsentAtFailure
    failure_cleanup_ready = $failureCleanupReady
    failure_cleanup_property_mismatches = @($failureCleanupPropertyMismatches)
    fatal_hits = @($fatalHits)
    property_mismatches = @($profilePropertyMismatches)
    cleanup_property_mismatches = @($cleanupPropertyMismatches)
    activation_missing = @($activationMissing)
    activation_fallback_hits = @($activationFallbackHits)
    spu_native_objects_loaded = $spuNativeObjectLoadCount
    minimum_required_spu_native_objects = $MinimumSpuNativeObjects
    spu_native_object_reuse_floor_satisfied = $spuNativeObjectReuseFloorSatisfied
    note = "Title-proof-ready authorizes a later correctness-locked A/B only; it is not FPS, speed, stability, or temperature credit."
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

Write-Host "Thor cool-title capture classification: $status (comparison-ready=$readyForComparison, cleanup-ready=$cleanupReady, max-silicon-C=$maxSiliconTemperatureC, spu-native-objects=$spuNativeObjectLoadCount/$MinimumSpuNativeObjects)"
if ($RequireReady -and -not $readyForComparison) {
    throw "Thor cool-title capture is not comparison-ready: status=$status, property-mismatches=$($profilePropertyMismatches.Count), cleanup-mismatches=$($cleanupPropertyMismatches.Count), activation-missing=$($activationMissing.Count), spu-native-objects=$spuNativeObjectLoadCount/$MinimumSpuNativeObjects, fatal-hits=$($fatalHits.Count), thermal-failures=$($thermalFailureLines.Count)."
}

$result
