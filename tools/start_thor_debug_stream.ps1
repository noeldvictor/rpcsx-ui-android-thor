param(
    [string]$Label = "live",
    [string]$Package = "net.rpcsx.easy",
    [string]$OutRoot = "debug-captures",
    [int]$PollSeconds = 3,
    [switch]$ClearLogcat,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb
$safeLabel = New-ThorSafeLabel $Label
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SessionDir = Join-Path $RepoRoot (Join-Path $OutRoot "$timestamp-$safeLabel-stream")
$SnapshotDir = Join-Path $SessionDir "snapshots"

New-Item -ItemType Directory -Force -Path $SessionDir | Out-Null
New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null

if ($ClearLogcat) {
    Invoke-ThorAdbText $Adb $SessionDir "prepare-logcat-clear.txt" @("logcat", "-c") | Out-Null
}

if ($Launch) {
    Invoke-ThorAdbText $Adb $SessionDir "prepare-launch.txt" @("shell", "monkey -p $Package 1") -AllowFailure | Out-Null
}

Invoke-ThorAdbText $Adb $SessionDir "adb-devices.txt" @("devices", "-l") | Out-Null
Invoke-ThorAdbText $Adb $SessionDir "package-version.txt" @("shell", "dumpsys package $Package | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime|installerPackageName'") -AllowFailure | Out-Null
Write-ThorStandardSnapshot $Adb $SnapshotDir $Package "start"

$remoteRoot = "/storage/emulated/0/Android/data/$Package/files"
$tailCommand = "while true; do echo '--- RPCSX.log tail '`$(date '+%Y-%m-%dT%H:%M:%S%z')' ---'; tail -n 120 $remoteRoot/cache/RPCSX.log 2>/dev/null; sleep $PollSeconds; done"
$memoryCommand = "while true; do ts=`$(date '+%Y-%m-%dT%H:%M:%S%z'); app_pid=`$(pidof $Package); if [ -n ""`$app_pid"" ]; then echo ""--- memory `$ts pid=`$app_pid ---""; grep -E 'VmSize|VmRSS|VmSwap|RssAnon|RssFile|RssShmem|Threads' /proc/`$app_pid/status 2>/dev/null; dumpsys meminfo $Package 2>/dev/null | grep -E 'TOTAL|Native Heap|Dalvik Heap|Graphics|GL|Other dev|Unknown'; else echo ""--- memory `$ts pid=none ---""; fi; sleep $PollSeconds; done"

$streams = @()
$streams += Start-ThorAdbStream $Adb $SessionDir "logcat-live" @("logcat", "-v", "threadtime")
$streams += Start-ThorAdbStream $Adb $SessionDir "rpcsx-live-tail" @("shell", $tailCommand)
$streams += Start-ThorAdbStream $Adb $SessionDir "memory-live" @("shell", $memoryCommand)

$streams | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $SessionDir "stream-processes.json") -Encoding UTF8
Write-ThorLatestStream $RepoRoot $SessionDir

@(
    "# Thor Live Debug Stream",
    "",
    "- Started: $(Get-Date -Format o)",
    "- Label: $safeLabel",
    "- Package: $Package",
    "- Poll seconds: $PollSeconds",
    "",
    "## Live Files",
    "",
    '- `logcat-live.txt`: Android logcat stream',
    '- `rpcsx-live-tail.txt`: repeated tail of RPCSX.log',
    '- `memory-live.txt`: live RPCSX RSS/swap/thread snapshots',
    '- `snapshots/`: current process, activity, memory, thermal, cache, and game-install state',
    '- `stream-processes.json`: ADB stream process IDs',
    "",
    "## Agent Loop",
    "",
    '```powershell',
    ".\tools\summarize_thor_debug_stream.ps1 -Latest",
    ".\tools\stop_thor_debug_stream.ps1 -Latest",
    '```',
    "",
    "Use this while playing. The agent can repeatedly run the summary command, inspect the newest logs, patch code, rebuild, and ask for another repro only when needed."
) | Set-Content -LiteralPath (Join-Path $SessionDir "README.md") -Encoding UTF8

Write-Host "Thor debug stream started:"
Write-Host $SessionDir
Write-Host "Summarize with: .\tools\summarize_thor_debug_stream.ps1 -Latest"
Write-Host "Stop with:      .\tools\stop_thor_debug_stream.ps1 -Latest"
