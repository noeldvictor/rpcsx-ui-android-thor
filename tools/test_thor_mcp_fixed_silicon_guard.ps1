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
    'elif silicon >= 72:'
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

foreach ($required in @(
    'args_text = os.environ.get("THOR_CALL_ARGS")',
    'args = json.loads(args_text)'
)) {
    if (-not $caller.Contains($required)) {
        throw "The PowerShell-safe Thor caller path is missing '$required'."
    }
}

Write-Output "Thor MCP fixed-silicon guard contract passed."
