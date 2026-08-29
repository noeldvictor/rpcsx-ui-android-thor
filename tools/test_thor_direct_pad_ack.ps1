$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$receiverPath = Join-Path $repoRoot "app/src/debug/java/net/rpcsx/ThorDebugPadReceiver.kt"
$macroPath = Join-Path $PSScriptRoot "thor_input_macro.ps1"
$receiver = Get-Content -LiteralPath $receiverPath -Raw
$macro = Get-Content -LiteralPath $macroPath -Raw

$requiredReceiverFragments = @(
    'setResultCode(if (ok) Activity.RESULT_OK else Activity.RESULT_CANCELED)',
    'setResultData(if (ok) "accepted" else "no-active-activity")'
)
foreach ($fragment in $requiredReceiverFragments) {
    if (-not $receiver.Contains($fragment)) {
        throw "The direct pad receiver does not report acceptance: $fragment"
    }
}

$requiredMacroFragments = @(
    'Out-File -LiteralPath (Join-Path $captureDir "direct-pad.log")',
    "`$broadcastText -notmatch 'Broadcast completed: result=-1'",
    'throw "The app did not accept the direct pad input ''$Key'': $broadcastText"',
    '$token -match ''^direct:([^:]+)(?::(\d+))?$''',
    'Direct pad duration must be from 20 through 5000 ms.'
)
foreach ($fragment in $requiredMacroFragments) {
    if (-not $macro.Contains($fragment)) {
        throw "The direct pad macro does not fail closed: $fragment"
    }
}

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile($macroPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
    throw "The input macro has a PowerShell syntax error: $($errors[0].Message)"
}

Write-Output "Thor direct pad acceptance contract passed."
