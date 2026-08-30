$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $repoRoot "tools/thor_mcp/server.py"
$callerPath = Join-Path $repoRoot "tools/thor_mcp/call.py"
$server = Get-Content -LiteralPath $serverPath -Raw
$caller = Get-Content -LiteralPath $callerPath -Raw

foreach ($required in @(
    'def fixed_silicon_c():',
    'cpuss-*|gpuss-*|ddr|xo-therm',
    'The socd zone is battery state of charge, not SoC temperature.',
    't = fixed_silicon_c()',
    'if t >= ceiling:',
    'hard_limit = float(a.get("maxSiliconC", 72))',
    'interval = min(2, limit - waited)',
    'if silicon < 0 or silicon >= hard_limit:',
    'stop = t_stop({})',
    '"triggerFixedSiliconC": silicon',
    'out["fixedSiliconC"] = silicon',
    'elif silicon >= 72:',
    'def t_slice(a):',
    'def emulation_state():',
    'EMU_STATE_STARTING = 7',
    'def stop_process_for_slice(p):',
    'run-as {PKG} kill -STOP {p}',
    'def continue_process_for_slice(p):',
    'run-as {PKG} kill -CONT {p}',
    'def wake_display_for_guest():',
    'input keyevent KEYCODE_WAKEUP',
    'return emulation_state() in (EMU_STATE_PAUSED, EMU_STATE_READY)',
    'duration = max(0.1, min(float(a.get("seconds", 1.5)), 15.0))',
    'interval = min(0.25, duration - elapsed)',
    '"the bounded slice could not restore a held state"',
    'startup_handoff = process_held or initial_state == EMU_STATE_READY',
    'startupPauseTimeoutS',
    'startup_handoff and final_state == EMU_STATE_STARTING',
    '"holdMode": "process"',
    '"pauseSettledAtS"',
    '"paused": process_held or is_paused()',
    'def t_wait_cool_paused(a):',
    'silicon <= target',
    '"cooledAtFixedSiliconC": silicon',
    '"the emulator must stay paused while it cools"',
    'def t_slice_loop(a):',
    'stable_samples = max(1, min(int(a.get("stableSamples", 1)), 5))',
    'sample_interval = max(',
    '"requiredStableSamples": stable_samples',
    'max_host_s = max(30.0, min(float(a.get("maxHostS", 420)), 600.0))',
    'resume_stable_samples = max(',
    '"hostDeadlineReached": True',
    '"hostElapsedS"',
    '"includeState": False',
    'for fatal_match in ("Access violation", "Verification failed", "Fatal",',
    '"FATAL", "Out of memory"):',
    '"Thor: SPURS shutdown completion event mask"',
    '("thor_slice",',
    '("thor_slice_loop",',
    '("thor_wait_cool_paused",'
    '"tail", "-n", "4096"',
    'def t_clearprops(_):',
    '("thor_clearprops",'
)) {
    if (-not $server.Contains($required)) {
        throw "The Thor MCP fixed-silicon guard is missing '$required'."
    }
}

if ($server.Contains('cpuss-*|gpuss-*|ddr|socd|xo-therm')) {
    throw "The Thor MCP fixed-silicon guard still treats battery state of charge as temperature."
}

$waitMatch = [regex]::Match(
    $server,
    '(?m)^def t_wait_ready\(a\):[\s\S]*?(?=^def t_press\(a\):)'
)
if (-not $waitMatch.Success -or -not $waitMatch.Value.Contains('fixed_silicon_c()')) {
    throw "thor_wait_ready does not poll fixed silicon."
}

$sampleMatch = [regex]::Match(
    $server,
    '(?m)^def t_sample\(a\):[\s\S]*?(?=^def t_log\(a\):)'
)
if (-not $sampleMatch.Success -or
    -not $sampleMatch.Value.Contains('fixed_silicon_c()') -or
    -not $sampleMatch.Value.Contains('thermalStop')) {
    throw "thor_sample does not enforce the fixed-silicon hard limit."
}

$pressMatch = [regex]::Match(
    $server,
    '(?m)^def t_press\(a\):[\s\S]*?(?=^def is_paused\(\):)'
)
if (-not $pressMatch.Success -or
    -not $pressMatch.Value.Contains('start_ceiling = float(a.get("maxStartC", 70))') -or
    -not $pressMatch.Value.Contains('process_held = bool(p) and held_process_pid() == p') -or
    -not $pressMatch.Value.Contains('continue_process_for_slice(p)') -or
    -not $pressMatch.Value.Contains('wake_display_for_guest()') -or
    -not $pressMatch.Value.Contains('stop_process_for_slice(p)') -or
    -not $pressMatch.Value.Contains('silicon >= hard_limit') -or
    -not $pressMatch.Value.Contains('stop = t_stop({})')) {
    throw "thor_press does not guard its resumed input window."
}

foreach ($required in @(
    'args_text = os.environ.get("THOR_CALL_ARGS")',
    'args = json.loads(args_text)',
    'except subprocess.TimeoutExpired:',
    '"params": {"name": "thor_stop", "arguments": {}}',
    'A verified stop was requested.'
)) {
    if (-not $caller.Contains($required)) {
        throw "The PowerShell-safe Thor caller path is missing '$required'."
    }
}

Write-Output "Thor MCP fixed-silicon guard contract passed."
