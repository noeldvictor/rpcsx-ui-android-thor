$ErrorActionPreference = "Stop"

$routePath = Join-Path $PSScriptRoot "invoke_thor_transformers_hle_render_probe.ps1"
$timerPath = Join-Path $PSScriptRoot "..\app\src\main\cpp\rpcsx\kernel\cellos\src\sys_timer.cpp"
$routeSource = Get-Content -LiteralPath $routePath -Raw
$timerSource = Get-Content -LiteralPath $timerPath -Raw

$requiredRouteFragments = @(
    '[ValidateSet(10, 25, 50, 100, 200, 400)]',
    '[int]$RenderPollUs = 400',
    '"debug.rpcsx.thor.tf_render_poll_us" = "$RenderPollUs"',
    'Set-ThorRenderProbeProperty -Name "debug.rpcsx.thor.tf_render_poll_us" -Value "400"'
)

foreach ($fragment in $requiredRouteFragments) {
    if (-not $routeSource.Contains($fragment)) {
        throw "The Transformers render-poll route is missing: $fragment"
    }
}

$requiredTimerFragments = @(
    'constexpr u32 thor_transformers_render_poll_cia = 0x0152efc0;',
    'constexpr u64 thor_transformers_render_poll_requested_us = 400;',
    '"debug.rpcsx.thor.tf_render_poll_us"',
    'Emu.GetTitleID() != "BLUS30357"',
    'apply_thor_transformers_render_poll(ppu, sleep_time);',
    '"Thor Transformers render poll: hit=%llu'
)

foreach ($fragment in $requiredTimerFragments) {
    if (-not $timerSource.Contains($fragment)) {
        throw "The Transformers render-poll implementation is missing: $fragment"
    }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($routePath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "The Transformers render-poll route has a PowerShell syntax error: $($errors[0].Message)"
}

Write-Output "Transformers render-poll route contract passed."
