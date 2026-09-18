$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$macroPath = Join-Path $repo "tools/thor_input_macro.ps1"
$macro = Get-Content -LiteralPath $macroPath -Raw

$required = @(
    'function Save-ThorDiagnosticSnapshot',
    'Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8099/diag"',
    'ConvertTo-Json -Depth 8 -Compress',
    "`$token -match '^diag:(.+)`$'",
    'Save-ThorDiagnosticSnapshot $Matches[1]',
    '`diag:NAME`'
)

foreach ($fragment in $required) {
    if (-not $macro.Contains($fragment)) {
        throw "The Thor input diagnostic token is missing: $fragment"
    }
}

[void][Management.Automation.Language.Parser]::ParseFile(
    $macroPath,
    [ref]$null,
    [ref]$null
)

Write-Host "Thor input diagnostic token contract passed."
