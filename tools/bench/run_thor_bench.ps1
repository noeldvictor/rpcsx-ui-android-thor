[CmdletBinding()]
param(
    [string]$Device = "c3ca0370",
    [string]$Package = "net.rpcsx.easy",
    [ValidateSet("all", "topology", "hierarchy", "memcpy", "wait", "shufb", "evict", "decide")]
    [string]$Mode = "all",
    # 3 is an A715, 6 an A710, 0 an A510. CPU7 (X3) and CPU5 are reachable too,
    # but only once something has loaded the machine: core_ctl pauses them when
    # idle and an affinity request naming only a paused core is refused. The
    # binary loads the machine itself before it gives up on a pin.
    [int[]]$Cpus = @(3, 6, 0),
    [int]$OtherCpu = 4,
    [double]$MaxPreflightC = 55.0,
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"

# Run the bespoke benchmark on the Thor, outside the emulator.
#
# No APK, no boot, no 27 minute precompile. The thermal bar is looser than an
# emulator arm's because each mode runs for seconds, but it is not absent: a
# throttled core reports a slower kernel and the number looks like a result.
#
# The device is shared with another session. This never force-stops their
# package; it refuses instead.

$remote = "/data/local/tmp/thor_bench"
$local = Join-Path $PSScriptRoot "thor_bench"
if (-not (Test-Path $local)) { throw "no binary at $local; run build_thor_bench.ps1 first" }

function Invoke-Adb {
    param([string[]]$AdbArgs)
    # adb writes ordinary progress to stderr -- "1 file pushed" among it -- and
    # under ErrorActionPreference Stop that merged stream is a terminating error.
    # The first run of this script died on a push that had in fact succeeded.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & adb -s $Device @AdbArgs 2>&1 }
    finally { $ErrorActionPreference = $prev }
}

function Assert-Adb {
    # The USB serial on this device disappears without warning, and an
    # unreachable device returns empty exactly like a quiet one.
    $ok = ((Invoke-Adb @("shell", "echo ok")) -join "") -replace '\s', ''
    if ($ok -ne "ok") {
        throw "device $Device is not answering. It may need `adb reconnect`, a replug, or an Allow USB debugging tap."
    }
}

$ok = ((Invoke-Adb @("shell", "echo ok")) -join "") -replace '\s', ''
if ($ok -ne "ok") { throw "device $Device unreachable or unauthorized: check for a confirmation dialog on the device" }

# Our own emulator must be off: it holds cores and would be measured as noise.
$mine = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()
if ($mine) { throw "$Package is running (pid $mine). Stop it before benchmarking; a running emulator is not a quiet machine." }

$foreign = (Invoke-Adb @("shell", "top -b -n 2 -d 2 | grep xenia | grep -v logcat | grep -v grep")) -join "`n"
$foreignMax = 0.0
foreach ($line in ($foreign -split "`n")) {
    if ($line -match '\s(\d+(?:\.\d+)?)\s+\d+(?:\.\d+)?\s+\d+:\d+\.\d+\s') {
        $v = [double]$matches[1]
        if ($v -gt $foreignMax) { $foreignMax = $v }
    }
}
if ($foreignMax -gt 20.0) {
    throw ("the other session's emulator is at {0:N0}% CPU. Do not force-stop it; run when the device is free." -f $foreignMax)
}

$rawTemps = (Invoke-Adb @("shell", 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done')) -join "`n"
$temps = @()
foreach ($line in ($rawTemps -split "`n")) {
    $t = $line.Trim()
    if ($t -match '^\d+$') { $temps += [double]$t / 1000.0 }
}
if ($temps.Count -eq 0) { throw "no cpu-1-* thermal zones read; do not benchmark blind" }
$maxT = ($temps | Measure-Object -Maximum).Maximum
Write-Host ("preflight: max cpu-1-* {0:N1} C, foreign {1:N0}%" -f $maxT, $foreignMax)
if ($maxT -gt $MaxPreflightC) {
    throw ("device is at {0:N1} C, above {1:N1} C. A throttled core reports a slower kernel and it reads like a result." -f $maxT, $MaxPreflightC)
}

Invoke-Adb @("push", $local, $remote) | Out-Null
Invoke-Adb @("shell", "chmod 755 $remote") | Out-Null

$hash = ((Invoke-Adb @("shell", "sha256sum $remote")) -join "").Trim()
Write-Host "pushed: $hash"

$lines = @()
$lines += "# thor_bench $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "# preflight max_c=$maxT foreign_pct=$foreignMax"
$lines += "# $hash"

function Run-Mode {
    param([string]$M, [int]$Cpu, [int]$Other)
    Write-Host ""
    Write-Host "--- $M cpu=$Cpu other=$Other ---"
    Assert-Adb
    $out = (Invoke-Adb @("shell", "$remote $M $Cpu $Other")) -join "`n"
    Write-Host $out

    # A mode that printed nothing usable is not a quiet result.
    if ($out -notmatch 'mode=') {
        throw "mode '$M' produced no result line. Output was: $out"
    }
    $script:lines += ""
    $script:lines += "## $M cpu=$Cpu other=$Other"
    $script:lines += $out
}

# "decide" is the short run: the two experiments that settle a pending change,
# on the two clusters the SPU threads use. Everything else is background.
#
#   shufb  seq_tbx2_current against seq_tbl2_orr_candidate, which decides
#          debug.rpcsx.thor.shufb_tbl2_or
#   evict  the victim's rate beside memcpy and beside LDNP/STNP, which decides
#          whether debug.rpcsx.thor.dma_nontemporal is worth anything
$decide = $Mode -eq "decide"

if ($Mode -eq "all" -or $Mode -eq "topology") { Run-Mode "topology" 0 0 }

foreach ($cpu in $Cpus) {
    if ($decide -and $cpu -eq 0) { continue }   # the A510s are not where SPU runs

    if ($Mode -eq "all" -or $Mode -eq "shufb" -or $decide) { Run-Mode "shufb" $cpu $OtherCpu }
    if ($Mode -eq "all" -or $Mode -eq "evict" -or $decide) { Run-Mode "evict" $cpu $OtherCpu }
    if ($Mode -eq "all" -or $Mode -eq "hierarchy") { Run-Mode "hierarchy" $cpu $OtherCpu }
    if ($Mode -eq "all" -or $Mode -eq "memcpy") { Run-Mode "memcpy" $cpu $OtherCpu }
    if ($Mode -eq "all" -or $Mode -eq "wait") { Run-Mode "wait" $cpu $OtherCpu }
}

$post = (Invoke-Adb @("shell", 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done')) -join "`n"
$postTemps = @()
foreach ($line in ($post -split "`n")) {
    $t = $line.Trim()
    if ($t -match '^\d+$') { $postTemps += [double]$t / 1000.0 }
}
$maxPost = if ($postTemps.Count) { ($postTemps | Measure-Object -Maximum).Maximum } else { 0 }
Write-Host ""
Write-Host ("post-run max cpu-1-* {0:N1} C" -f $maxPost)
$lines += ""
$lines += "# post max_c=$maxPost"

if ($OutDir) {
    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
    $file = Join-Path $OutDir ("thor_bench-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".txt")
    Set-Content -Path $file -Value $lines -Encoding utf8
    Write-Host "wrote $file"
}
