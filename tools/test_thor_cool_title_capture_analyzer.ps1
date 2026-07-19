$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$analyzerPath = Join-Path $PSScriptRoot "analyze_thor_cool_title_capture.ps1"
$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"

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
    'debug.rpcsx.thor.es_frame_wait',
    'debug.rpcsx.thor.es_frame_wait_grace_us',
    'debug.rpcsx.thor.es_frame_wait_continuous_rearm',
    'log.tag.RPCS3',
    'log.tag.RPCSX-UI'
)) {
    if (-not $macroSource.Contains($fragment)) {
        throw "Thor input macro is missing combined cool-title property evidence: $fragment"
    }
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

function Write-ReadyFixture {
    param([string]$Directory)

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $effectiveProperties = [ordered]@{
        "rsx-cache-workers-effective.txt" = "2"
        "rsx-cache-preload-limit-effective.txt" = "256"
        "rsx-cache-compile-budget-effective.txt" = "0"
        "spu-cache-preload-limit-effective.txt" = "64"
        "spu-cache-compile-budget-effective.txt" = "100"
        "spu-native-object-cache-effective.txt" = "off"
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
        "debug.rpcsx.thor.rsx_cache_preload_limit=256",
        "debug.rpcsx.thor.rsx_cache_compile_budget_ms=0",
        "debug.rpcsx.thor.spu_cache_preload_limit=64",
        "debug.rpcsx.thor.spu_cache_compile_budget_ms=100",
        "debug.rpcsx.thor.spu_native_object_cache=off",
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
        "- Max silicon temperature C: 72",
        "- RSX cache preload workers (0=auto): 2",
        "- RSX cached pipeline preload limit (0=all): 256",
        "- RSX cached pipeline compile budget ms (0=unbounded): 0",
        "- SPU cached-program preload limit (0=all): 64",
        "- SPU cached-program compile budget ms (0=unbounded): 100",
        "- Startup cache-worker affinity mask (0=default scheduler): 7",
        "- Persistent Vulkan driver pipeline cache: on",
        "- Vulkan preload cache hits only: on",
        "- Android RSX performance hint: off",
        "- Startup cache phase pacing: off",
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
    Write-AdbEvidence -Directory $Directory -Name "post-pid.txt" -Value "exit=1"
    "attempt=2 ready_candidate_count=2 title_menu_present=True" | Set-Content -LiteralPath (Join-Path $Directory "ppu-ready-gate.log") -Encoding UTF8
    @(
        "stage=pre-run-1-of-3 silicon_temperature_c=31.5 silicon_limit_c=35",
        "stage=pre-run-2-of-3 silicon_temperature_c=31.8 silicon_limit_c=35",
        "stage=pre-run-3-of-3 silicon_temperature_c=31.7 silicon_limit_c=35",
        "stage=screenshot-title-proof silicon_temperature_c=58.0 silicon_limit_c=72",
        "stage=post-run silicon_temperature_c=44.0 silicon_limit_c=72"
    ) | Set-Content -LiteralPath (Join-Path $Directory "thermal-guard.log") -Encoding UTF8
    @(
        "Android shader cache preload limit: 256 of 939 oldest pipelines; 683 will compile on demand",
        "Thor SPU cache preload limit: 64 of 300 oldest unique programs (300 records, 236 will compile on demand).",
        "Shader cache preload workers: load=2, compile=2",
        "Thor RSX cache-worker affinity enabled for load: requested=0x7, effective=0x7.",
        "Thor SPU cache-worker affinity enabled: requested=0x7, effective=0x7.",
        "Thor SPU cache-worker pool matched to affinity: requested=2, workers=2, mask=0x7.",
        "Thor SPU cache compile budget enabled for BLUS30161: 100 ms.",
        "Vulkan preload cache-hits-only enabled for validated warm seed (4899180 bytes)."
    ) | Set-Content -LiteralPath (Join-Path $Directory "post-RPCSX.log") -Encoding UTF8
    Write-TitleProofPng -Path (Join-Path $Directory "03-title-proof.png")
}

try {
    $readyDir = Join-Path $tempRoot "ready"
    Write-ReadyFixture $readyDir
    $ready = & $analyzerPath -CaptureDir $readyDir
    if ($ready.status -ne "title-proof-ready" -or -not $ready.ready_for_comparison -or $ready.speed_credit) {
        throw "Synthetic ready capture was not classified as title-proof-ready without speed credit."
    }
    & $analyzerPath -CaptureDir $readyDir -RequireReady | Out-Null

    $mismatchDir = Join-Path $tempRoot "activation-mismatch"
    Copy-Item -LiteralPath $readyDir -Destination $mismatchDir -Recurse
    Write-AdbEvidence -Directory $mismatchDir -Name "rsx-cache-workers-effective.txt" -Value "0"
    $mismatch = & $analyzerPath -CaptureDir $mismatchDir
    if ($mismatch.status -ne "activation-incomplete" -or $mismatch.ready_for_comparison -or $mismatch.property_mismatches.Count -eq 0) {
        throw "Synthetic activation mismatch did not fail closed."
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
    "Thor CPU/GPU silicon temperature is 72.7 C, at or above the 72 C limit." | Set-Content -LiteralPath (Join-Path $thermalDir "macro-failure.txt") -Encoding UTF8
    "stage=screenshot-ppu-ready-near-limit-confirm silicon_temperature_c=72.7 silicon_limit_c=72" |
        Add-Content -LiteralPath (Join-Path $thermalDir "thermal-guard.log") -Encoding UTF8
    $thermal = & $analyzerPath -CaptureDir $thermalDir
    if ($thermal.status -ne "thermal-stop-before-title" -or $thermal.ready_for_comparison) {
        throw "Synthetic thermal stop did not retain its primary failure classification."
    }

    $preflightDir = Join-Path $tempRoot "preflight-refused-hot"
    New-Item -ItemType Directory -Force -Path $preflightDir | Out-Null
    @(
        "stage=pre-run-1-of-3 silicon_temperature_c=44.9 silicon_limit_c=35",
        "stage=failure-post-stop silicon_temperature_c=45.8 silicon_limit_c=72"
    ) | Set-Content -LiteralPath (Join-Path $preflightDir "thermal-guard.log") -Encoding UTF8
    "Thor CPU/GPU silicon temperature is 44.9 C, at or above the 35 C limit. Stage 'pre-run-1-of-3'. RPCSX was force-stopped." |
        Set-Content -LiteralPath (Join-Path $preflightDir "macro-failure.txt") -Encoding UTF8
    @(
        "# adb shell pidof net.rpcsx.easy",
        "",
        "exit=1"
    ) | Set-Content -LiteralPath (Join-Path $preflightDir "failure-pid.txt") -Encoding UTF8
    $preflight = & $analyzerPath -CaptureDir $preflightDir
    if ($preflight.status -ne "preflight-refused-hot" -or $preflight.ready_for_comparison -or $preflight.speed_credit -or -not $preflight.process_absent_at_failure) {
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

Write-Output "Thor cool-title capture analyzer contract passed: exact property/runtime activation, title image, preflight refusal, fatal, thermal, self-stop, and no-speed-credit gates are deterministic and host-only."
