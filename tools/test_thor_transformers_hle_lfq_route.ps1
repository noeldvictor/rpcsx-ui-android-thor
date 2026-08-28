$ErrorActionPreference = "Stop"

$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$macro = Get-Content -LiteralPath $macroPath -Raw

$requiredFragments = @(
    '[string]$LfqAny2Any = "off"',
    '"- SPURS ANY2ANY LFQueue: $LfqAny2Any"',
    '"debug.rpcsx.thor.lfq_any2any"',
    '"setprop debug.rpcsx.thor.lfq_any2any $LfqAny2Any"',
    '"getprop debug.rpcsx.thor.lfq_any2any"',
    '"setprop debug.rpcsx.thor.lfq_any2any off"',
    '"lfq-any2any-prelaunch-reset.txt"',
    '"lfq-any2any-failure-reset.txt"',
    '"lfq-any2any-reset.txt"'
)

foreach ($fragment in $requiredFragments) {
    if (-not $macro.Contains($fragment)) {
        throw "The Transformers HLE LFQueue route is missing: $fragment"
    }
}

Write-Output "Transformers HLE LFQueue route contract passed."
