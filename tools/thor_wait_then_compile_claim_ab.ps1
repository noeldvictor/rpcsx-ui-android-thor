[CmdletBinding()]
param(
    [string]$Device = "c3ca0370",
    [int]$MaxWaitMinutes = 240,
    [double]$MaxForeignCpu = 20.0,
    [double]$MaxPreflightC = 45.0,
    [int]$SettleSeconds = 240,
    [int]$BetweenArmsSeconds = 300,
    [int]$MaxAttemptsPerArm = 4
)

$ErrorActionPreference = "Stop"

# Wait for the Thor to be free, then run both arms of the SPU compile-claim A/B.
#
# The Thor is shared with another session that tests Xbox 360 emulation. That
# session took the device in the middle of the first attempt: the cores went from
# 47 C to 95 C while this harness was waiting to start, with Xenia at 174-211%
# CPU. Never force-stop that package. Wait for it.
#
# The two arms run back to back so the machine state is as close as it can be.
# Each arm parks the title cache itself, so both boots are cold.
#
# Read the result with this fork's rule in mind: a difference seen once, in one
# order, is not a result. If the two arms differ, re-run in the opposite order
# before believing it.

$armScript = Join-Path $PSScriptRoot "thor_spu_compile_claim_ab.ps1"
if (-not (Test-Path $armScript)) { throw "missing $armScript" }

function Invoke-Adb {
    param([string[]]$AdbArgs)
    & adb -s $Device @AdbArgs 2>&1
}

function Get-ForeignEmulatorCpu {
    $rows = (Invoke-Adb @("shell", "top -b -n 2 -d 2 | grep xenia | grep -v logcat | grep -v grep")) -join "`n"
    $max = 0.0
    foreach ($line in ($rows -split "`n")) {
        if ($line -match '\s(\d+(?:\.\d+)?)\s+\d+(?:\.\d+)?\s+\d+:\d+\.\d+\s') {
            $v = [double]$matches[1]
            if ($v -gt $max) { $max = $v }
        }
    }
    return $max
}

function Get-MaxCpuTempC {
    $raw = (Invoke-Adb @("shell", 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done')) -join "`n"
    $vals = @()
    foreach ($line in ($raw -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^\d+$') { $vals += [double]$t / 1000.0 }
    }
    if ($vals.Count -eq 0) { throw "no cpu-1-* thermal zones read; do not proceed blind" }
    return ($vals | Measure-Object -Maximum).Maximum
}

$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
$wasBusy = $false

Write-Host "waiting for the device to be free (up to $MaxWaitMinutes minutes)"

# Count consecutive free samples. One free sample is a trough between the other
# session's runs, not an idle device: a reading of 43.7 C was followed by 49.8 C
# fifteen seconds later, with the foreign process reading 0% in the gap.
$freeNeeded = 3
$freeRun = 0

while ($true) {
    $foreign = Get-ForeignEmulatorCpu
    $temp = Get-MaxCpuTempC
    $stamp = Get-Date -Format "HH:mm:ss"

    if ($foreign -le $MaxForeignCpu -and $temp -le $MaxPreflightC) {
        $freeRun++
        Write-Host ("{0}  free: foreign {1:N0}%, {2:N1} C  ({3}/{4})" -f $stamp, $foreign, $temp, $freeRun, $freeNeeded)
        if ($freeRun -ge $freeNeeded) { break }
        Start-Sleep -Seconds 30
        continue
    }

    $freeRun = 0
    $wasBusy = $true
    Write-Host ("{0}  busy: foreign {1:N0}%, {2:N1} C" -f $stamp, $foreign, $temp)

    if ((Get-Date) -ge $deadline) {
        throw ("the device was still busy after $MaxWaitMinutes minutes: foreign {0:N0}% CPU, {1:N1} C" -f $foreign, $temp)
    }

    Start-Sleep -Seconds 60
}

if ($wasBusy) {
    # The other session just stopped. Give the silicon a moment to settle rather
    # than starting on the tail of its heat.
    Write-Host "device just came free; settling 120s before the first arm"
    Start-Sleep -Seconds 120
}

$results = @()

foreach ($claim in @("1", "0")) {
    $attempt = 0
    $text = ""
    $ok = $false

    while ($attempt -lt $MaxAttemptsPerArm) {
        $attempt++
        Write-Host ""
        Write-Host "########## arm claim=$claim, attempt $attempt ##########"

        # The child writes its refusals to stderr, and a refusal is an expected
        # outcome on a shared device, not a reason to abandon the whole run.
        $prev = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & powershell -NoProfile -File $armScript -Device $Device -Claim $claim `
            -SettleSeconds $SettleSeconds -MaxPreflightC $MaxPreflightC -MaxForeignCpu $MaxForeignCpu 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev

        $text = ($output | Out-String)
        Write-Host $text

        if ($code -eq 0) { $ok = $true; break }

        if ($attempt -lt $MaxAttemptsPerArm) {
            Write-Host "arm refused; waiting for the device again before retrying"
            if ((Get-Date) -ge $deadline) { break }
            Start-Sleep -Seconds 120
        }
    }

    $results += [pscustomobject]@{
        Claim    = $claim
        Failed   = (-not $ok)
        Attempts = $attempt
        Text     = $text
    }

    if ($claim -eq "1" -and $ok) {
        Write-Host "cooling ${BetweenArmsSeconds}s between arms"
        Start-Sleep -Seconds $BetweenArmsSeconds
    }
}

Write-Host ""
Write-Host "########## summary ##########"
foreach ($r in $results) {
    $cpu = if ($r.Text -match 'process CPU\s+:\s+([\d.]+)s') { $matches[1] } else { "n/a" }
    $workers = if ($r.Text -match 'PPU workers max:\s+(\d+)') { $matches[1] } else { "n/a" }
    $built = if ($r.Text -match 'SPU Runtime: Built (\d+)') { $matches[1] } else { "n/a" }
    $state = if ($r.Failed) { "FAILED/VOID" } else { "ok" }
    Write-Host ("claim={0}  {1}  cpu={2}s  ppu_workers={3}  spu_built={4}" -f $r.Claim, $state, $cpu, $workers, $built)
}
Write-Host ""
Write-Host "A difference in one order is not a result. Re-run with the arms reversed before believing it."
