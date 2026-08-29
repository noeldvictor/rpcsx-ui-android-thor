$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$serverPath = Join-Path $repoRoot "tools/thor_mcp/server.py"
$callerPath = Join-Path $repoRoot "tools/thor_mcp/call.py"
$server = Get-Content -LiteralPath $serverPath -Raw
$caller = Get-Content -LiteralPath $callerPath -Raw

foreach ($required in @(
    'def fixed_silicon_c():',
    'cpuss-*|gpuss-*|ddr|socd|xo-therm',
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
    'r.get("state") in (4, 6)',
    'duration = max(0.1, min(float(a.get("seconds", 1.5)), 5.0))',
    'interval = min(0.25, duration - elapsed)',
    '"the bounded slice could not restore a held state"',
    '"paused": is_paused()',
    'def t_wait_cool_paused(a):',
    '"cooledAtFixedSiliconC": silicon',
    '"the emulator must stay paused while it cools"',
    'def t_slice_loop(a):',
    'max_host_s = max(30.0, min(float(a.get("maxHostS", 420)), 420.0))',
    '"hostDeadlineReached": True',
    '"hostElapsedS"',
    '"includeState": False',
    'for fatal_match in ("Access violation", "Verification failed"):',
    '"Thor: SPURS shutdown completion event mask"',
    '("thor_slice",',
    '("thor_slice_loop",',
    '("thor_wait_cool_paused",'
)) {
    if (-not $server.Contains($required)) {
        throw "The Thor MCP fixed-silicon guard is missing '$required'."
    }
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
