param(
    [string]$Package = "net.rpcsx.easy",
    [string]$Label = "wait",
    [int]$Samples = 3,
    [int]$IntervalMs = 1000,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

function ConvertTo-ThorShellSingleQuoted {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'\''") + "'"
}

$RepoRoot = Get-ThorRepoRoot
$Adb = Resolve-ThorAdb
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = New-ThorSafeLabel $Label

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $captureDir = Join-Path $RepoRoot "debug-captures\android-speed-sprint\$stamp-thread-wait-$safeLabel"
} else {
    $captureDir = Join-Path $OutputRoot "thread-wait-$safeLabel"
}

New-Item -ItemType Directory -Force -Path $captureDir | Out-Null

@(
    "# Thor Thread Wait Snapshot",
    "",
    "- Created: $(Get-Date -Format o)",
    "- Package: $Package",
    "- Label: $Label",
    "- Samples: $Samples",
    "- Interval ms: $IntervalMs",
    "",
    "Captures per-thread `/proc` state while RPCSX is alive. Use this at Eternal Sonata loading hangs to separate CPU-bound hot loops from scheduler/progress stalls."
) | Set-Content -LiteralPath (Join-Path $captureDir "README.md") -Encoding UTF8

$remoteScript = @'
pkg="$1"
samples="$2"
interval_ms="$3"

case "$samples" in
    ''|*[!0-9]*) samples=1 ;;
esac

case "$interval_ms" in
    ''|*[!0-9]*) interval_ms=1000 ;;
esac

if [ "$samples" -lt 1 ]; then
    samples=1
fi

interval_s=$(( (interval_ms + 999) / 1000 ))
if [ "$interval_s" -lt 1 ]; then
    interval_s=1
fi

pid="$(pidof "$pkg" 2>/dev/null)"
pid="${pid%% *}"

echo "timestamp=$(date 2>/dev/null)"
echo "package=$pkg"
echo "pid=$pid"
echo "samples=$samples"
echo "interval_ms=$interval_ms"
echo ""

if [ -z "$pid" ] || [ ! -d "/proc/$pid/task" ]; then
    echo "no-process"
    exit 2
fi

i=1
while [ "$i" -le "$samples" ]; do
    echo "===== sample $i $(date 2>/dev/null) ====="
    echo "process_state:"
    grep -E '^(Name|State|Threads|VmRSS|VmHWM|voluntary_ctxt_switches|nonvoluntary_ctxt_switches):' "/proc/$pid/status" 2>/dev/null
    echo ""

    for task in "/proc/$pid/task"/*; do
        [ -d "$task" ] || continue
        tid="${task##*/}"
        comm="$(cat "$task/comm" 2>/dev/null)"
        state_line="$(grep '^State:' "$task/status" 2>/dev/null)"
        state="${state_line#State:}"
        wchan="$(cat "$task/wchan" 2>/dev/null)"
        ctxt="$(grep -E '^(voluntary_ctxt_switches|nonvoluntary_ctxt_switches):' "$task/status" 2>/dev/null | tr '\n' ' ')"
        schedstat="$(cat "$task/schedstat" 2>/dev/null)"
        stat="$(cat "$task/stat" 2>/dev/null)"
        echo "THREAD tid=$tid comm=$comm state=$state wchan=$wchan $ctxt"
        echo "SCHEDSTAT tid=$tid $schedstat"
        echo "STAT tid=$tid $stat"
    done

    if [ "$i" -lt "$samples" ]; then
        sleep "$interval_s"
    fi
    i=$((i + 1))
done
'@

$quotedRemoteScript = ConvertTo-ThorShellSingleQuoted $remoteScript
Invoke-ThorAdbText $Adb $captureDir "thread-wait.txt" @("shell", "run-as $Package sh -c $quotedRemoteScript -- $Package $Samples $IntervalMs") -AllowFailure | Out-Null
Write-ThorStandardSnapshot -Adb $Adb -CaptureDir $captureDir -Package $Package -Prefix "snapshot"

Write-Host "Thor thread wait snapshot: $captureDir"
