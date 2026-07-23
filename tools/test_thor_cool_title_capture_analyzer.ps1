$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$analyzerPath = Join-Path $PSScriptRoot "analyze_thor_cool_title_capture.ps1"
$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$candidatePath = Join-Path $PSScriptRoot "thor_cool_title_candidate.psd1"
$candidate = Import-PowerShellDataFile -LiteralPath $candidatePath
if ([string]$candidate.ApkSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "Thor cool-title candidate APK identity is invalid: $candidatePath"
}
$candidateApkSha256 = ([string]$candidate.ApkSha256).ToUpperInvariant()

foreach ($path in @($analyzerPath, $macroPath)) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) {
        throw "$path has PowerShell parse errors: $($parseErrors.Message -join '; ')"
    }
}

$macroSource = Get-Content -LiteralPath $macroPath -Raw
foreach ($fragment in @(
    'startup-profile-effective.txt',
    'startup-profile-reset-effective.txt',
    'startup-profile-failure-reset-effective.txt',
    '$script:ThorDebugBootRequested = $false',
    '$script:ThorDebugBootRequested = $true',
    'if ($script:ThorDebugBootRequested)',
    'Invoke-ThorAdbText $Adb $captureDir "failure-pid.txt"',
    'setprop debug.rpcsx.thor.es_sema_superpath off',
    'setprop debug.rpcsx.thor.es_dma_superpath off',
    'setprop debug.rpcsx.thor.rsx_blit_source_resolve off',
    'setprop debug.rpcsx.thor.es_frame_wait off',
    'setprop debug.rpcsx.thor.es_frame_wait_grace_us 0',
    'setprop debug.rpcsx.thor.es_frame_wait_continuous_rearm off',
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    'debug.rpcsx.thor.es_frame_wait_continuous_rearm',
    'log.tag.RPCS3',
    'log.tag.RPCSX-UI',
    'ExpectedInstalledApkSha256',
    'installed-apk-identity.txt',
    'Assert-ThorInstalledApkIdentity',
    'thorDebugBootRequestId',
    'Assert-ThorDebugBootAccepted -RequestId'
)) {
    if (-not $macroSource.Contains($fragment)) {
        throw "Thor input macro is missing combined cool-title property evidence: $fragment"
    }
}

$identityCallIndex = $macroSource.LastIndexOf("Assert-ThorInstalledApkIdentity")
$thermalPreflightCallIndex = $macroSource.LastIndexOf('Assert-ThorThermalPreflight "pre-run"')
$bootCallIndex = $macroSource.LastIndexOf('am start -a net.rpcsx.THOR_DEBUG_BOOT')
$bootHandshakeIndex = $macroSource.LastIndexOf('Assert-ThorDebugBootAccepted -RequestId')
if ($identityCallIndex -lt 0 -or $thermalPreflightCallIndex -le $identityCallIndex -or $bootCallIndex -le $thermalPreflightCallIndex -or $bootHandshakeIndex -le $bootCallIndex) {
    throw "Installed APK identity must be checked before thermal preflight and debug boot."
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("rpcsx-thor-cool-title-analyzer-" + [guid]::NewGuid().ToString("N"))

function Write-AdbEvidence {
    param(
        [string]$Directory,
        [string]$Name,
        [string]$Value
    )

    @(
        "# synthetic adb evidence",
        "# captured 2026-07-19T12:00:00-04:00",
        "",
        $Value
    ) | Set-Content -LiteralPath (Join-Path $Directory $Name) -Encoding UTF8
}

function Write-TitleProofPng {
    param([string]$Path)

    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(640, 360)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $brush = $null
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(30, 60, 120))
        $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(170, 20, 120))
        $graphics.FillRectangle($brush, 256, 126, 128, 144)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($brush) { $brush.Dispose() }
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Write-LauncherProofPng {
    param([string]$Path)

    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new(640, 360)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $coverBrush = $null
    $accentBrush = $null
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(235, 235, 235))
        $coverBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(180, 20, 150))
        $accentBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(20, 190, 210))
        $graphics.FillRectangle($coverBrush, 260, 130, 120, 110)
        $graphics.FillRectangle($accentBrush, 500, 90, 45, 150)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        if ($coverBrush) { $coverBrush.Dispose() }
        if ($accentBrush) { $accentBrush.Dispose() }
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Write-ReadyFixture {
    param([string]$Directory)

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $effectiveProperties = [ordered]@{
        "rsx-cache-workers-effective.txt" = "2"
        "rsx-cache-preload-limit-effective.txt" = "64"
        "rsx-cache-load-budget-effective.txt" = "200"
        "rsx-cache-compile-budget-effective.txt" = "50"
        "spu-cache-preload-limit-effective.txt" = "17"
        "spu-cache-compile-budget-effective.txt" = "50"
        "spu-native-object-cache-effective.txt" = "on"
        "cache-worker-affinity-effective.txt" = "7"
        "vk-pipeline-cache-effective.txt" = "on"
        "vk-preload-cache-hits-only-effective.txt" = "on"
        "adpf-rsx-effective.txt" = "off"
        "cache-phase-pacing-effective.txt" = "off"
    }
    foreach ($entry in $effectiveProperties.GetEnumerator()) {
        Write-AdbEvidence -Directory $Directory -Name $entry.Key -Value $entry.Value
    }

    @(
        "debug.rpcsx.thor.rsx_cache_workers=2",
        "debug.rpcsx.thor.rsx_cache_preload_limit=64",
        "debug.rpcsx.thor.rsx_cache_load_budget_ms=200",
        "debug.rpcsx.thor.rsx_cache_compile_budget_ms=50",
        "debug.rpcsx.thor.spu_cache_preload_limit=17",
        "debug.rpcsx.thor.spu_cache_compile_budget_ms=50",
        "debug.rpcsx.thor.spu_native_object_cache=on",
        "debug.rpcsx.thor.cache_worker_affinity_mask=7",
        "debug.rpcsx.thor.vk_pipeline_cache=on",
        "debug.rpcsx.thor.vk_preload_cache_hits_only=on",
        "debug.rpcsx.thor.adpf_rsx=off",
        "debug.rpcsx.thor.cache_phase_pacing=off",
        "debug.rpcsx.thor.logcat=0",
        "debug.rpcsx.thor.syscall_stats=0",
        "debug.rpcsx.thor.spu_reduced_loop_detect=0",
        "debug.rpcsx.thor.spu_reduced_loop_emit=0",
        "debug.rpcsx.thor.spurs_probe=0",
        "debug.rpcsx.thor.es_sema_superpath=off",
        "debug.rpcsx.thor.es_dma_superpath=off",
        "debug.rpcsx.thor.rsx_blit_source_resolve=off",
        "debug.rpcsx.thor.rsx_auditor=0",
        "debug.rpcsx.thor.dump_prx=0",
        "debug.rpcsx.thor.es_frame_wait=wait",
        "debug.rpcsx.thor.es_frame_wait_grace_us=500",
        "debug.rpcsx.thor.es_frame_wait_continuous_rearm=on",
        "log.tag.RPCS3=S",
        "log.tag.RPCSX-UI=W"
    ) | Set-Content -LiteralPath (Join-Path $Directory "startup-profile-effective.txt") -Encoding UTF8

    @(
        "debug.rpcsx.thor.rsx_cache_workers=0",
        "debug.rpcsx.thor.rsx_cache_preload_limit=0",
        "debug.rpcsx.thor.rsx_cache_load_budget_ms=0",
        "debug.rpcsx.thor.rsx_cache_compile_budget_ms=0",
        "debug.rpcsx.thor.spu_cache_preload_limit=0",
        "debug.rpcsx.thor.spu_cache_compile_budget_ms=0",
        "debug.rpcsx.thor.spu_native_object_cache=off",
        "debug.rpcsx.thor.cache_worker_affinity_mask=0",
        "debug.rpcsx.thor.vk_pipeline_cache=on",
        "debug.rpcsx.thor.vk_preload_cache_hits_only=off",
        "debug.rpcsx.thor.adpf_rsx=off",
        "debug.rpcsx.thor.cache_phase_pacing=off",
        "debug.rpcsx.thor.es_ppu_command_interp=off",
        "debug.rpcsx.thor.es_ppu_dispatch_probe=off",
        "debug.rpcsx.thor.es_async_draw_barrier=off",
        "debug.rpcsx.thor.es_sema_superpath=off",
        "debug.rpcsx.thor.es_dma_superpath=off",
        "debug.rpcsx.thor.rsx_blit_source_resolve=off",
        "debug.rpcsx.thor.es_frame_wait=off",
        "debug.rpcsx.thor.es_frame_wait_grace_us=0",
        "debug.rpcsx.thor.es_frame_wait_continuous_rearm=off"
    ) | Set-Content -LiteralPath (Join-Path $Directory "startup-profile-reset-effective.txt") -Encoding UTF8

    @(
        "package=net.rpcsx.easy",
        "remote_path=/data/app/example/net.rpcsx.easy/base.apk",
        "expected_sha256=$candidateApkSha256",
        "actual_sha256=$candidateApkSha256",
        "match=True"
    ) | Set-Content -LiteralPath (Join-Path $Directory "installed-apk-identity.txt") -Encoding UTF8

    @(
        "- Input mode: Direct",
        "- Thermal preflight samples: 3",
        "- Thermal preflight interval seconds: 2",
        "- Thermal preflight headroom C: 0",
        "- Max launch silicon temperature C: 35",
        "- Thermal preflight max silicon rise C: 1",
        "- Thermal poll interval seconds: 1",
        "- Runtime thermal early-stop headroom C: 4",
        "- Runtime thermal confirmation window C: 4",
        "- Max battery temperature C: 34",
        "- Max skin temperature C: 40",
        "- Max silicon temperature C: 64",
        "- RSX cache preload workers (0=auto): 2",
        "- RSX cached pipeline preload limit (0=all): 64",
        "- RSX cached pipeline load budget ms (0=unbounded): 200",
        "- RSX cached pipeline compile budget ms (0=unbounded): 50",
        "- SPU cached-program preload limit (0=all): 17",
        "- SPU cached-program compile budget ms (0=unbounded): 50",
        "- Startup cache-worker affinity mask (0=default scheduler): 7",
        "- Persistent Vulkan driver pipeline cache: on",
        "- Vulkan preload cache hits only: on",
        "- Android RSX performance hint: off",
        "- Startup cache phase pacing: off",
        "- Expected installed APK SHA-256: $candidateApkSha256",
        "- Macro: gate:ppu-ready:90000;shot:title-proof;check:visual:title-menu;check:guest:title-proof;stop"
    ) | Set-Content -LiteralPath (Join-Path $Directory "README.md") -Encoding UTF8

    @(
        "2026-07-19T12:00:00-04:00 gate:ppu-ready:90000",
        "2026-07-19T12:00:01-04:00 shot:title-proof",
        "2026-07-19T12:00:02-04:00 check:visual:title-menu",
        "2026-07-19T12:00:03-04:00 check:guest:title-proof",
        "2026-07-19T12:00:04-04:00 stop"
    ) | Set-Content -LiteralPath (Join-Path $Directory "macro.log") -Encoding UTF8
    "synthetic force-stop evidence" | Set-Content -LiteralPath (Join-Path $Directory "macro-stop.txt") -Encoding UTF8
    "2026-07-19T12:00:00-04:00 request_id=synthetic status=accepted elapsed_ms=100" | Set-Content -LiteralPath (Join-Path $Directory "debug-boot-handshake-status.log") -Encoding UTF8
    Write-AdbEvidence -Directory $Directory -Name "post-pid.txt" -Value "exit=1"
    @(
        "attempt=1 elapsed_ms=1200 ready_candidate_count=1 title_menu_present=True",
        "attempt=2 elapsed_ms=6500 ready_candidate_count=2 title_menu_present=True"
    ) | Set-Content -LiteralPath (Join-Path $Directory "ppu-ready-gate.log") -Encoding UTF8
    @(
        "stage=pre-run-1-of-3 silicon_temperature_c=31.5 silicon_limit_c=35",
        "stage=pre-run-2-of-3 silicon_temperature_c=31.8 silicon_limit_c=35",
        "stage=pre-run-3-of-3 silicon_temperature_c=31.7 silicon_limit_c=35",
        "stage=screenshot-title-proof silicon_temperature_c=58.0 silicon_limit_c=64",
        "stage=post-run silicon_temperature_c=44.0 silicon_limit_c=64"
    ) | Set-Content -LiteralPath (Join-Path $Directory "thermal-guard.log") -Encoding UTF8
    @(
        "  Max LLVM Compile Threads: 2",
        "Â·A 0:00:01.384222 PPU: Thor PPU warm-cache link using default scheduler: objects=41.",
        "Â·A 0:00:01.690222 PPU: Thor PPU warm-cache link using default scheduler: objects=1.",
        "Android shader cache preload limit: 64 of 939 oldest pipelines; 875 will compile on demand",
        "Android shader cache load budget enabled for BLUS30161: 200 ms.",
        "Android shader cache load budget: attempted 16 of 64 cached pipelines with a 200 ms budget; 48 will load and compile on demand.",
        "Android shader cache compile budget enabled for BLUS30161: 50 ms.",
        "Android shader cache compile budget: attempted 2 of 16 pipelines with a 50 ms budget; 14 will compile on demand.",
        "Thor SPU cache preload limit: 17 of 300 oldest unique programs (300 records, 283 will compile on demand).",
        "Thor SPU native-object cache enabled for startup LLVM objects: bounded preload plus interpreter where required; runtime misses remain uncached.",
        "LLVM: Loaded module: 4E6Tn-thor-native-key.obj",
        "Shader cache preload workers: load=2, compile=1",
        "Android shader cache compile worker cap enabled for BLUS30161: workers=1.",
        "Thor RSX cache-worker affinity enabled for load: requested=0x7, effective=0x7.",
        "Thor RSX cache-worker affinity enabled for compile: requested=0x7, effective=0x7.",
        "Thor SPU cache-worker affinity enabled: requested=0x7, effective=0x7.",
        "Thor SPU cache-worker pool matched to affinity: requested=2, workers=2, mask=0x7.",
        "Thor SPU cache compile budget enabled for BLUS30161: 50 ms.",
        "Vulkan preload cache-hits-only enabled for validated warm seed (4899180 bytes).",
        "·! 0:00:03.000000 SYS: Set DAZ and FTZ: true"
    ) | Set-Content -LiteralPath (Join-Path $Directory "post-RPCSX.log") -Encoding UTF8
    Write-TitleProofPng -Path (Join-Path $Directory "03-title-proof.png")
    Copy-Item -LiteralPath (Join-Path $Directory "03-title-proof.png") -Destination (Join-Path $Directory "01-ppu-ready-poll-01.png")
    Copy-Item -LiteralPath (Join-Path $Directory "03-title-proof.png") -Destination (Join-Path $Directory "02-ppu-ready-poll-02.png")
}

try {
    $readyDir = Join-Path $tempRoot "ready"
    Write-ReadyFixture $readyDir
    $ready = & $analyzerPath -CaptureDir $readyDir
    if ($ready.status -ne "title-proof-ready" -or -not $ready.ready_for_comparison -or $ready.speed_credit -or
        -not $ready.cleanup_ready -or $ready.cleanup_property_mismatches.Count -ne 0 -or
        $ready.first_title_frame_elapsed_ms -ne 1200 -or $ready.stable_title_frame_elapsed_ms -ne 6500 -or
        $ready.title_stability_window_ms -ne 5300 -or $ready.spu_native_objects_loaded -ne 1 -or
        $ready.ppu_warm_link_event_count -ne 2 -or $ready.ppu_warm_link_primary_objects -ne 41 -or
        $ready.ppu_warm_link_primary_start_seconds -ne 1.384222 -or $ready.ppu_warm_link_next_module_start_seconds -ne 1.690222 -or
        $ready.ppu_warm_link_primary_to_next_module_ms -ne 306 -or -not $ready.ppu_warm_link_timing_ready -or
        $ready.minimum_required_spu_native_objects -ne 1 -or -not $ready.spu_native_object_reuse_floor_satisfied) {
        throw "Synthetic ready capture was not classified as title-proof-ready without speed credit and exact title timing."
    }
    $readyJsonPath = Join-Path $readyDir "cool-title-analysis.json"
    & $analyzerPath -CaptureDir $readyDir -OutputPath $readyJsonPath -RequireReady | Out-Null
    $readyJson = Get-Content -LiteralPath $readyJsonPath -Raw | ConvertFrom-Json
    if ($readyJson.status -ne "title-proof-ready" -or -not $readyJson.ready_for_comparison -or
        -not $readyJson.cleanup_ready -or $readyJson.cleanup_property_mismatches.Count -ne 0 -or
        $readyJson.first_title_frame_elapsed_ms -ne 1200 -or $readyJson.stable_title_frame_elapsed_ms -ne 6500 -or
        $readyJson.title_stability_window_ms -ne 5300 -or $readyJson.spu_native_objects_loaded -ne 1 -or
        $readyJson.ppu_warm_link_event_count -ne 2 -or $readyJson.ppu_warm_link_primary_objects -ne 41 -or
        $readyJson.ppu_warm_link_primary_start_seconds -ne 1.384222 -or $readyJson.ppu_warm_link_next_module_start_seconds -ne 1.690222 -or
        $readyJson.ppu_warm_link_primary_to_next_module_ms -ne 306 -or -not $readyJson.ppu_warm_link_timing_ready -or
        $readyJson.minimum_required_spu_native_objects -ne 1 -or -not $readyJson.spu_native_object_reuse_floor_satisfied) {
        throw "Persisted title analysis JSON did not retain exact classification and timing evidence."
    }

    $floorLimitedDir = Join-Path $tempRoot "continuity-floor-limited-preload"
    Copy-Item -LiteralPath $readyDir -Destination $floorLimitedDir -Recurse
    "exit=0`n1" | Set-Content -LiteralPath (Join-Path $floorLimitedDir "spu-cache-preload-limit-effective.txt") -Encoding UTF8
    (Get-Content -LiteralPath (Join-Path $floorLimitedDir "startup-profile-effective.txt")) -replace
        '^debug[.]rpcsx[.]thor[.]spu_cache_preload_limit=17$', 'debug.rpcsx.thor.spu_cache_preload_limit=1' |
        Set-Content -LiteralPath (Join-Path $floorLimitedDir "startup-profile-effective.txt") -Encoding UTF8
    (Get-Content -LiteralPath (Join-Path $floorLimitedDir "README.md")) -replace
        '^- SPU cached-program preload limit [(]0=all[)]: 17$', '- SPU cached-program preload limit (0=all): 1' |
        Set-Content -LiteralPath (Join-Path $floorLimitedDir "README.md") -Encoding UTF8
    (Get-Content -LiteralPath (Join-Path $floorLimitedDir "post-RPCSX.log")) -replace
        'Thor SPU cache preload limit: 17 of 300 oldest unique programs [(]300 records, 283 will compile on demand[)][.]',
        'Thor SPU cache preload limit: 1 of 300 oldest unique programs (300 records, 299 will compile on demand).' |
        Set-Content -LiteralPath (Join-Path $floorLimitedDir "post-RPCSX.log") -Encoding UTF8
    $floorLimited = & $analyzerPath -CaptureDir $floorLimitedDir -MinimumSpuNativeObjects 1 -ExpectedSpuCachePreloadLimit 1
    if ($floorLimited.status -ne "title-proof-ready" -or -not $floorLimited.ready_for_comparison -or
        $floorLimited.expected_spu_cache_preload_limit -ne 1 -or
        $floorLimited.spu_native_objects_loaded -ne 1 -or
        -not $floorLimited.spu_native_object_reuse_floor_satisfied) {
        throw "Synthetic continuity-floor-limited SPU preload did not remain comparison-ready."
    }

    $missingTimingDir = Join-Path $tempRoot "missing-title-timing"
    Copy-Item -LiteralPath $readyDir -Destination $missingTimingDir -Recurse
    "attempt=2 ready_candidate_count=2 title_menu_present=True" | Set-Content -LiteralPath (Join-Path $missingTimingDir "ppu-ready-gate.log") -Encoding UTF8
    $missingTiming = & $analyzerPath -CaptureDir $missingTimingDir
    if ($missingTiming.status -ne "proof-sequence-incomplete" -or $missingTiming.ready_for_comparison -or
        $null -ne $missingTiming.first_title_frame_elapsed_ms -or $null -ne $missingTiming.stable_title_frame_elapsed_ms) {
        throw "Synthetic title proof without elapsed timing evidence did not fail closed."
    }

    $launcherDir = Join-Path $tempRoot "launcher-ui"
    Copy-Item -LiteralPath $readyDir -Destination $launcherDir -Recurse
    Write-LauncherProofPng -Path (Join-Path $launcherDir "03-title-proof.png")
    Write-LauncherProofPng -Path (Join-Path $launcherDir "01-ppu-ready-poll-01.png")
    Write-LauncherProofPng -Path (Join-Path $launcherDir "02-ppu-ready-poll-02.png")
    $launcher = & $analyzerPath -CaptureDir $launcherDir
    if ($launcher.status -ne "launcher-ui-instead-of-title" -or $launcher.ready_for_comparison -or
        $launcher.title_menu_present -or -not $launcher.launcher_ui_present -or $launcher.ppu_ready_gate_stable -or
        $launcher.ppu_ready_gate_evidence_source -ne "frame-replay") {
        throw "Synthetic RPCSX launcher frame did not override stale title-gate evidence and fail closed."
    }

    $missingHandshakeDir = Join-Path $tempRoot "missing-debug-boot-handshake"
    Copy-Item -LiteralPath $readyDir -Destination $missingHandshakeDir -Recurse
    Remove-Item -LiteralPath (Join-Path $missingHandshakeDir "debug-boot-handshake-status.log") -Force
    $missingHandshake = & $analyzerPath -CaptureDir $missingHandshakeDir
    if ($missingHandshake.status -ne "debug-boot-handshake-missing" -or $missingHandshake.ready_for_comparison -or $missingHandshake.debug_boot_accepted) {
        throw "Synthetic title proof without an accepted debug-boot handshake did not fail closed."
    }

    $rejectedHandshakeDir = Join-Path $tempRoot "rejected-debug-boot-handshake"
    Copy-Item -LiteralPath $readyDir -Destination $rejectedHandshakeDir -Recurse
    "2026-07-19T12:00:00-04:00 request_id=synthetic status=rejected elapsed_ms=100" | Set-Content -LiteralPath (Join-Path $rejectedHandshakeDir "debug-boot-handshake-status.log") -Encoding UTF8
    $rejectedHandshake = & $analyzerPath -CaptureDir $rejectedHandshakeDir
    if ($rejectedHandshake.status -ne "debug-boot-rejected" -or $rejectedHandshake.ready_for_comparison -or -not $rejectedHandshake.debug_boot_rejected) {
        throw "Synthetic rejected debug-boot handshake was not classified precisely."
    }

    $mismatchDir = Join-Path $tempRoot "activation-mismatch"
    Copy-Item -LiteralPath $readyDir -Destination $mismatchDir -Recurse
    Write-AdbEvidence -Directory $mismatchDir -Name "rsx-cache-workers-effective.txt" -Value "0"
    $mismatch = & $analyzerPath -CaptureDir $mismatchDir
    if ($mismatch.status -ne "activation-incomplete" -or $mismatch.ready_for_comparison -or $mismatch.property_mismatches.Count -eq 0) {
        throw "Synthetic activation mismatch did not fail closed."
    }

    $cleanupMissingDir = Join-Path $tempRoot "cleanup-evidence-missing"
    Copy-Item -LiteralPath $readyDir -Destination $cleanupMissingDir -Recurse
    Remove-Item -LiteralPath (Join-Path $cleanupMissingDir "startup-profile-reset-effective.txt") -Force
    $cleanupMissing = & $analyzerPath -CaptureDir $cleanupMissingDir
    if ($cleanupMissing.status -ne "proof-sequence-incomplete" -or $cleanupMissing.ready_for_comparison -or
        $cleanupMissing.cleanup_ready -or $cleanupMissing.cleanup_property_mismatches.Count -ne 21) {
        throw "Synthetic missing post-stop property evidence did not fail closed."
    }

    $cleanupMismatchDir = Join-Path $tempRoot "cleanup-property-mismatch"
    Copy-Item -LiteralPath $readyDir -Destination $cleanupMismatchDir -Recurse
    (Get-Content -LiteralPath (Join-Path $cleanupMismatchDir "startup-profile-reset-effective.txt")) -replace '^debug[.]rpcsx[.]thor[.]spu_native_object_cache=off$', 'debug.rpcsx.thor.spu_native_object_cache=on' |
        Set-Content -LiteralPath (Join-Path $cleanupMismatchDir "startup-profile-reset-effective.txt") -Encoding UTF8
    $cleanupMismatch = & $analyzerPath -CaptureDir $cleanupMismatchDir
    if ($cleanupMismatch.status -ne "proof-sequence-incomplete" -or $cleanupMismatch.ready_for_comparison -or
        $cleanupMismatch.cleanup_ready -or $cleanupMismatch.cleanup_property_mismatches.Count -ne 1 -or
        $cleanupMismatch.cleanup_property_mismatches -notmatch 'spu_native_object_cache') {
        throw "Synthetic leaked SPU native-object cache property did not fail closed."
    }

    $identityMismatchDir = Join-Path $tempRoot "apk-identity-mismatch"
    Copy-Item -LiteralPath $readyDir -Destination $identityMismatchDir -Recurse
    (Get-Content -LiteralPath (Join-Path $identityMismatchDir "installed-apk-identity.txt")) -replace '^actual_sha256=.*$', ('actual_sha256=' + ('0' * 64)) |
        Set-Content -LiteralPath (Join-Path $identityMismatchDir "installed-apk-identity.txt") -Encoding UTF8
    $identityMismatch = & $analyzerPath -CaptureDir $identityMismatchDir
    if ($identityMismatch.status -ne "activation-incomplete" -or $identityMismatch.ready_for_comparison -or $identityMismatch.property_mismatches -notmatch 'installed APK actual_sha256') {
        throw "Synthetic installed APK identity mismatch did not fail closed."
    }

    $ftzMissingDir = Join-Path $tempRoot "managed-ftz-missing"
    Copy-Item -LiteralPath $readyDir -Destination $ftzMissingDir -Recurse
    $ftzLogPath = Join-Path $ftzMissingDir "post-RPCSX.log"
    $ftzLogLines = @(Get-Content -LiteralPath $ftzLogPath)
    $ftzLogLines |
        Where-Object { $_ -notmatch 'Set DAZ and FTZ:\s*true' } |
        Set-Content -LiteralPath $ftzLogPath -Encoding UTF8
    $ftzMissing = & $analyzerPath -CaptureDir $ftzMissingDir
    if ($ftzMissing.status -ne "activation-incomplete" -or $ftzMissing.ready_for_comparison -or $ftzMissing.activation_missing -notcontains "managed hardware FTZ") {
        throw "Synthetic managed-profile FTZ omission did not fail closed."
    }

    $nativeActivationMissingDir = Join-Path $tempRoot "native-object-cache-activation-missing"
    Copy-Item -LiteralPath $readyDir -Destination $nativeActivationMissingDir -Recurse
    $nativeActivationLogPath = Join-Path $nativeActivationMissingDir "post-RPCSX.log"
    @(Get-Content -LiteralPath $nativeActivationLogPath) |
        Where-Object { $_ -notmatch 'Thor SPU native-object cache enabled for startup LLVM objects:' } |
        Set-Content -LiteralPath $nativeActivationLogPath -Encoding UTF8
    $nativeActivationMissing = & $analyzerPath -CaptureDir $nativeActivationMissingDir
    if ($nativeActivationMissing.status -ne "activation-incomplete" -or $nativeActivationMissing.ready_for_comparison -or
        $nativeActivationMissing.activation_missing -notcontains "SPU native-object cache activation") {
        throw "Synthetic missing SPU native-object cache activation did not fail closed."
    }

    $nativeReuseMissingDir = Join-Path $tempRoot "native-object-reuse-missing"
    Copy-Item -LiteralPath $readyDir -Destination $nativeReuseMissingDir -Recurse
    $nativeReuseLogPath = Join-Path $nativeReuseMissingDir "post-RPCSX.log"
    @(Get-Content -LiteralPath $nativeReuseLogPath) |
        Where-Object { $_ -notmatch 'LLVM: Loaded module: [^\r\n]+[.]obj' } |
        Set-Content -LiteralPath $nativeReuseLogPath -Encoding UTF8
    $nativeReuseMissing = & $analyzerPath -CaptureDir $nativeReuseMissingDir
    if ($nativeReuseMissing.status -ne "activation-incomplete" -or $nativeReuseMissing.ready_for_comparison -or
        $nativeReuseMissing.activation_missing -notcontains "SPU native-object reuse") {
        throw "Synthetic missing SPU native-object reuse did not fail closed."
    }

    $partialNativeReuse = & $analyzerPath -CaptureDir $readyDir -MinimumSpuNativeObjects 2
    if ($partialNativeReuse.status -ne "activation-incomplete" -or $partialNativeReuse.ready_for_comparison -or
        $partialNativeReuse.spu_native_objects_loaded -ne 1 -or
        $partialNativeReuse.minimum_required_spu_native_objects -ne 2 -or
        $partialNativeReuse.spu_native_object_reuse_floor_satisfied -or
        $partialNativeReuse.activation_missing -notcontains "SPU native-object reuse") {
        throw "Synthetic partial SPU native-object reuse did not fail the continuity floor."
    }

    $rsxCompileBudgetMissingDir = Join-Path $tempRoot "rsx-compile-budget-missing"
    Copy-Item -LiteralPath $readyDir -Destination $rsxCompileBudgetMissingDir -Recurse
    $rsxCompileBudgetLogPath = Join-Path $rsxCompileBudgetMissingDir "post-RPCSX.log"
    @(Get-Content -LiteralPath $rsxCompileBudgetLogPath) |
        Where-Object { $_ -notmatch 'Android shader cache compile budget' } |
        Set-Content -LiteralPath $rsxCompileBudgetLogPath -Encoding UTF8
    $rsxCompileBudgetMissing = & $analyzerPath -CaptureDir $rsxCompileBudgetMissingDir
    if ($rsxCompileBudgetMissing.status -ne "activation-incomplete" -or $rsxCompileBudgetMissing.ready_for_comparison -or
        $rsxCompileBudgetMissing.activation_missing -notcontains "bounded RSX compile time" -or
        $rsxCompileBudgetMissing.activation_missing -notcontains "deferred RSX compile fallback") {
        throw "Synthetic missing RSX compile-budget activation and fallback did not fail closed."
    }

    $logIncompleteDir = Join-Path $tempRoot "title-proof-log-incomplete"
    Copy-Item -LiteralPath $readyDir -Destination $logIncompleteDir -Recurse
    "·! 0:00:00.010546 Input: startup log writer stopped before activation evidence" |
        Set-Content -LiteralPath (Join-Path $logIncompleteDir "post-RPCSX.log") -Encoding UTF8
    $logIncomplete = & $analyzerPath -CaptureDir $logIncompleteDir
    if ($logIncomplete.status -ne "title-proof-log-incomplete" -or $logIncomplete.ready_for_comparison -or
        -not $logIncomplete.guest_log_evidence_incomplete -or $logIncomplete.guest_log_latest_emulator_seconds -ge 1.0 -or
        $logIncomplete.activation_missing.Count -ne 19) {
        throw "Synthetic stable title with a stalled runtime log was not classified precisely and fail closed."
    }

    $ppuCapMissingDir = Join-Path $tempRoot "ppu-compile-cap-missing"
    Copy-Item -LiteralPath $readyDir -Destination $ppuCapMissingDir -Recurse
    $ppuCapLogPath = Join-Path $ppuCapMissingDir "post-RPCSX.log"
    @(Get-Content -LiteralPath $ppuCapLogPath) |
        Where-Object { $_ -notmatch 'Max LLVM Compile Threads:\s*2' } |
        Set-Content -LiteralPath $ppuCapLogPath -Encoding UTF8
    $ppuCapMissing = & $analyzerPath -CaptureDir $ppuCapMissingDir
    if ($ppuCapMissing.status -ne "activation-incomplete" -or $ppuCapMissing.ready_for_comparison -or
        $ppuCapMissing.activation_missing -notcontains "two little-core PPU compile threads") {
        throw "Synthetic missing two-thread little-core PPU compile cap did not fail closed."
    }

    $ppuSchedulerMissingDir = Join-Path $tempRoot "ppu-warm-default-scheduler-missing"
    Copy-Item -LiteralPath $readyDir -Destination $ppuSchedulerMissingDir -Recurse
    $ppuSchedulerLogPath = Join-Path $ppuSchedulerMissingDir "post-RPCSX.log"
    @(Get-Content -LiteralPath $ppuSchedulerLogPath) |
        Where-Object { $_ -notmatch 'Thor PPU warm-cache link using default scheduler:' } |
        Set-Content -LiteralPath $ppuSchedulerLogPath -Encoding UTF8
    $ppuSchedulerMissing = & $analyzerPath -CaptureDir $ppuSchedulerMissingDir
    if ($ppuSchedulerMissing.status -ne "activation-incomplete" -or $ppuSchedulerMissing.ready_for_comparison -or
        $ppuSchedulerMissing.activation_missing -notcontains "PPU warm-cache default scheduler") {
        throw "Synthetic missing PPU warm-cache default-scheduler evidence did not fail closed."
    }

    $runningDir = Join-Path $tempRoot "still-running"
    Copy-Item -LiteralPath $readyDir -Destination $runningDir -Recurse
    Write-AdbEvidence -Directory $runningDir -Name "post-pid.txt" -Value "12345"
    $running = & $analyzerPath -CaptureDir $runningDir
    if ($running.status -ne "proof-sequence-incomplete" -or $running.ready_for_comparison -or $running.stopped_after_proof) {
        throw "Synthetic still-running capture did not fail closed."
    }

    $thermalDir = Join-Path $tempRoot "thermal-stop"
    Copy-Item -LiteralPath $readyDir -Destination $thermalDir -Recurse
    Remove-Item -LiteralPath (Join-Path $thermalDir "03-title-proof.png") -Force
    "Thor CPU/GPU silicon temperature is 63.4 C, at or above the 60.0 C early-stop threshold below the 64 C hard limit." | Set-Content -LiteralPath (Join-Path $thermalDir "macro-failure.txt") -Encoding UTF8
    @(
        "stage=screenshot-ppu-ready silicon_temperature_c=63.4 silicon_limit_c=64",
        "stage=screenshot-ppu-ready status=failed code=silicon-temperature-headroom stop_temperature_c=60 hard_limit_c=64"
    ) | Add-Content -LiteralPath (Join-Path $thermalDir "thermal-guard.log") -Encoding UTF8
    Write-AdbEvidence -Directory $thermalDir -Name "failure-pid.txt" -Value "exit=1"
    Copy-Item -LiteralPath (Join-Path $thermalDir "startup-profile-reset-effective.txt") `
        -Destination (Join-Path $thermalDir "startup-profile-failure-reset-effective.txt")
    $thermal = & $analyzerPath -CaptureDir $thermalDir
    if ($thermal.status -ne "thermal-stop-before-title" -or $thermal.ready_for_comparison -or
        -not $thermal.failure_cleanup_ready -or $thermal.failure_cleanup_property_mismatches.Count -ne 0) {
        throw "Synthetic launched thermal stop with normal preflight rows did not retain its primary failure classification."
    }

    $thermalCleanupMismatchDir = Join-Path $tempRoot "thermal-stop-cleanup-mismatch"
    Copy-Item -LiteralPath $thermalDir -Destination $thermalCleanupMismatchDir -Recurse
    (Get-Content -LiteralPath (Join-Path $thermalCleanupMismatchDir "startup-profile-failure-reset-effective.txt")) -replace '^debug[.]rpcsx[.]thor[.]spu_native_object_cache=off$', 'debug.rpcsx.thor.spu_native_object_cache=on' |
        Set-Content -LiteralPath (Join-Path $thermalCleanupMismatchDir "startup-profile-failure-reset-effective.txt") -Encoding UTF8
    $thermalCleanupMismatch = & $analyzerPath -CaptureDir $thermalCleanupMismatchDir
    if ($thermalCleanupMismatch.status -ne "thermal-stop-before-title" -or $thermalCleanupMismatch.ready_for_comparison -or
        $thermalCleanupMismatch.failure_cleanup_ready -or $thermalCleanupMismatch.failure_cleanup_property_mismatches.Count -ne 1 -or
        $thermalCleanupMismatch.failure_cleanup_property_mismatches -notmatch 'spu_native_object_cache') {
        throw "Synthetic launched thermal stop with leaked failure-reset state did not report incomplete cleanup."
    }

    $preflightDir = Join-Path $tempRoot "preflight-refused-hot"
    New-Item -ItemType Directory -Force -Path $preflightDir | Out-Null
    @(
        "stage=pre-run-1-of-3 silicon_temperature_c=44.9 silicon_limit_c=35",
        "stage=failure-post-stop silicon_temperature_c=45.8 silicon_limit_c=64"
    ) | Set-Content -LiteralPath (Join-Path $preflightDir "thermal-guard.log") -Encoding UTF8
    "Thor CPU/GPU silicon temperature is 44.9 C, at or above the 35 C limit. Stage 'pre-run-1-of-3'. RPCSX was force-stopped." |
        Set-Content -LiteralPath (Join-Path $preflightDir "macro-failure.txt") -Encoding UTF8
    @(
        "# adb shell pidof net.rpcsx.easy",
        "",
        "exit=1"
    ) | Set-Content -LiteralPath (Join-Path $preflightDir "failure-pid.txt") -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $readyDir "post-RPCSX.log") -Destination (Join-Path $preflightDir "failure-RPCSX.log")
    $preflight = & $analyzerPath -CaptureDir $preflightDir
    if ($preflight.status -ne "preflight-refused-hot" -or $preflight.ready_for_comparison -or $preflight.speed_credit -or
        -not $preflight.process_absent_at_failure -or $preflight.guest_log_trusted -or
        $preflight.spu_native_objects_loaded -ne 0 -or $preflight.spu_native_object_reuse_floor_satisfied) {
        throw "Synthetic hot preflight refusal was not distinguished from a launched thermal stop."
    }

    $fatalDir = Join-Path $tempRoot "fatal"
    Copy-Item -LiteralPath $readyDir -Destination $fatalDir -Recurse
    "VM: Access violation reading location 0x40" | Add-Content -LiteralPath (Join-Path $fatalDir "post-RPCSX.log") -Encoding UTF8
    $fatal = & $analyzerPath -CaptureDir $fatalDir
    if ($fatal.status -ne "fatal-at-title" -or $fatal.ready_for_comparison -or $fatal.fatal_hits.Count -eq 0) {
        throw "Synthetic fatal capture did not fail closed."
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Output "Thor cool-title capture analyzer contract passed: exact APK/core identity, bounded RSX load/compile work, two-thread little-core PPU compile cap, managed FTZ, durable SPU native-object activation/reuse floor, stalled-log diagnosis, property/runtime activation, title, fatal, thermal, self-stop, and no-speed-credit gates are deterministic and host-only."
