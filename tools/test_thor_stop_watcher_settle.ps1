$ErrorActionPreference = "Stop"

# The game activity must close only on a stop that stays.
#
# A savestate load uses the Reload path. The core is Stopped for about 0.25 s,
# then Emulator::Load moves it to Loading. On 2026-09-22 the stop watcher
# finished the activity on that Stopping. The surface was destroyed, and the
# reloaded game waited for a surface until it was killed.

$repoRoot = Split-Path -Parent $PSScriptRoot
$activityPath = Join-Path $repoRoot "app/src/main/java/net/rpcsx/RPCSXActivity.kt"
$activity = Get-Content -LiteralPath $activityPath -Raw

$start = $activity.IndexOf('private fun watchForNativeStopAndFinish(')
if ($start -lt 0) {
    throw "The stop watcher is missing from RPCSXActivity.kt."
}
$end = $activity.IndexOf("`n    private fun ", $start + 10)
if ($end -lt 0) {
    $end = $activity.Length
}
$watcher = $activity.Substring($start, $end - $start)

if ($watcher -match 'state\s*==\s*EmulatorState\.Stopping') {
    throw "The stop watcher acts on Stopping. A savestate reload passes through Stopping."
}

$required = @(
    'if (state == EmulatorState.Stopped) {',
    'now - stoppedSinceMs >= STOP_SETTLE_MS',
    'stoppedSinceMs = 0L'
)
foreach ($fragment in $required) {
    if (-not $watcher.Contains($fragment)) {
        throw "The stop watcher does not wait for a settled stop: $fragment"
    }
}

$match = [regex]::Match($activity, 'const val STOP_SETTLE_MS = (\d+)L')
if (-not $match.Success) {
    throw "STOP_SETTLE_MS is missing."
}
$settleMs = [int]$match.Groups[1].Value
if ($settleMs -lt 1000) {
    throw "STOP_SETTLE_MS is $settleMs ms. A reload is Stopped for about 250 ms, so keep at least 1000 ms."
}

Write-Output "Thor stop watcher settle contract passed."
