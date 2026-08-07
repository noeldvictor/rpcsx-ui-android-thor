[CmdletBinding()]
param(
    [string]$Device = "",
    [int]$DurationSeconds = 60,
    [string]$Label = "unlabeled",
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

# Power-proxy probe built on cumulative kernel counters.
#
# Why this exists. Every performance question this fork actually cares about is
# a power question: the device is passively cooled, the emulator already hits
# its 30 fps cap on the title that matters, and the SPU reservation spin burns
# full-clock cores producing nothing. FPS cannot see any of that. Temperature
# can, but slowly and with enormous lag.
#
# Two properties make this instrument different from thor_input_macro.ps1.
#
# 1. It reads *cumulative* counters, so a measurement of any length costs
#    exactly two adb round trips. The FPS harness spawns a shell per sample and
#    walks ~50 thermal_zone entries each time, which CLAUDE.md records as being
#    hot enough to trip the thermal guard on its own. A probe whose cost does
#    not scale with the window can measure a five-minute run for the price of a
#    five-second one.
#
# 2. It does not depend on the battery, so it works with USB attached. adb over
#    USB charges the device, which makes power_supply/battery/current_now report
#    charge current rather than system draw. Clock residency is unaffected.
#
# The metrics, and the distinction that took a bad first reading to find:
#
#   residency_mcycles  sum over frequency steps of (time_at_step * step_khz).
#                      This is NOT work. time_in_state accounts for all wall
#                      time including idle, so this is cycles the core was
#                      *clocked* for. Reading it as work overstated an idle
#                      device by more than 10x on the first run of this probe.
#   busy_ratio         fraction of wall time outside cpuidle, from cpuidle.
#                      A spinning core produces this directly; a parked one
#                      does not. This is the cleanest WFE signal.
#   work_mcycles       residency * busy_ratio. The honest estimate of retired
#                      cycles, approximate because the two counters are not
#                      jointly binned.
#   mean_mhz           frequency residency. Says *where* time sat, which
#                      matters because dynamic power rises faster than
#                      linearly with frequency.
#
# Absolute watts are deliberately not claimed. These are proxies, and their
# value is in A/B deltas between two arms measured the same way.

function Get-ThorPowerSnapshot {
    param([string]$Serial)

    $adbArgs = @()
    if ($Serial) { $adbArgs += @("-s", $Serial) }

    # One shell invocation. Everything the probe needs, in a single round trip,
    # so the observer cost does not grow with the measurement window.
    $script = @'
echo "T_NS=$(date +%s%N)"
for c in 0 1 2 3 4 5 6 7; do
  b=/sys/devices/system/cpu/cpu$c
  while read f t; do echo "F=$c $f $t"; done < $b/cpufreq/stats/time_in_state 2>/dev/null
  for s in $b/cpuidle/state*/; do
    echo "I=$c $(cat $s/name 2>/dev/null) $(cat $s/time 2>/dev/null) $(cat $s/usage 2>/dev/null)"
  done
done
echo "BATT_UA=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
echo "BATT_UV=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)"
echo "BATT_ST=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
echo "BATT_CC=$(cat /sys/class/power_supply/battery/charge_counter 2>/dev/null)"
'@ -replace "`r`n", "`n"

    $raw = & adb @adbArgs shell $script 2>&1
    if ($LASTEXITCODE -ne 0) { throw "adb shell failed while snapshotting: $raw" }

    $snapshot = [ordered]@{
        timestamp_ns = 0L
        freq         = @{}   # "cpu" -> @{ khz -> jiffies }
        idle         = @{}   # "cpu" -> @{ name -> @{time,usage} }
        battery      = [ordered]@{}
    }

    foreach ($line in $raw) {
        $text = "$line".Trim()
        if (-not $text) { continue }

        if ($text -match '^T_NS=(\d+)$') { $snapshot.timestamp_ns = [int64]$Matches[1]; continue }
        if ($text -match '^BATT_UA=(-?\d+)$') { $snapshot.battery.current_ua = [int64]$Matches[1]; continue }
        if ($text -match '^BATT_UV=(\d+)$') { $snapshot.battery.voltage_uv = [int64]$Matches[1]; continue }
        if ($text -match '^BATT_ST=(.+)$') { $snapshot.battery.status = $Matches[1].Trim(); continue }
        if ($text -match '^BATT_CC=(-?\d+)$') { $snapshot.battery.charge_counter = [int64]$Matches[1]; continue }

        if ($text -match '^F=(\d+)\s+(\d+)\s+(\d+)$') {
            $cpu = $Matches[1]
            if (-not $snapshot.freq.ContainsKey($cpu)) { $snapshot.freq[$cpu] = @{} }
            $snapshot.freq[$cpu][[int64]$Matches[2]] = [int64]$Matches[3]
            continue
        }

        if ($text -match '^I=(\d+)\s+(\S+)\s+(\d+)\s+(\d+)$') {
            $cpu = $Matches[1]
            if (-not $snapshot.idle.ContainsKey($cpu)) { $snapshot.idle[$cpu] = @{} }
            $snapshot.idle[$cpu][$Matches[2]] = @{ time = [int64]$Matches[3]; usage = [int64]$Matches[4] }
            continue
        }
    }

    if ($snapshot.timestamp_ns -eq 0) { throw "Snapshot did not return a timestamp; the device shell may be unavailable." }
    if ($snapshot.freq.Keys.Count -eq 0) { throw "No cpufreq time_in_state data was read. This probe needs readable cpufreq stats." }

    return $snapshot
}

# Cluster map for this SoC, keyed by the max frequency each policy reports.
# Kept as a function so a different part does not silently mislabel cores.
function Get-ThorClusterName {
    param([int]$Cpu)
    switch ($Cpu) {
        { $_ -le 2 } { return "A510" }
        { $_ -le 6 } { return "A710/A715" }
        default      { return "X3" }
    }
}

function Get-ThorPowerDelta {
    param($Before, $After)

    $wallNs = $After.timestamp_ns - $Before.timestamp_ns
    if ($wallNs -le 0) { throw "Non-positive wall time between snapshots; counters cannot be differenced." }
    $wallUs = $wallNs / 1000.0

    $perCpu = @()
    foreach ($cpuKey in ($Before.freq.Keys | Sort-Object { [int]$_ })) {
        $cpu = [int]$cpuKey
        if (-not $After.freq.ContainsKey($cpuKey)) { continue }

        # time_in_state is in 10ms jiffies, verified on device rather than
        # assumed: the per-step deltas sum to 1001 over a 10 s window, and the
        # running total matches uptime in seconds times 100.
        #
        # The trap is what it counts. time_in_state accounts for *all* wall
        # time, including time the core sat idle at whatever frequency the
        # policy had parked it at. So it is frequency *residency*, not work
        # done, and multiplying it out gives cycles the core was clocked for
        # rather than cycles it retired anything in. Treating it as work
        # overstates a mostly-idle device by more than an order of magnitude.
        #
        # Residency is still the number wanted for the frequency question,
        # because leakage and clock power are paid whether or not the core is
        # retiring instructions. Work is recovered by combining it with the
        # cpuidle busy ratio below.
        $residencyUs = 0.0
        $residencyCycles = 0.0
        foreach ($khz in $Before.freq[$cpuKey].Keys) {
            if (-not $After.freq[$cpuKey].ContainsKey($khz)) { continue }
            $dJiffies = $After.freq[$cpuKey][$khz] - $Before.freq[$cpuKey][$khz]
            if ($dJiffies -le 0) { continue }
            $dUs = $dJiffies * 10000.0
            $residencyUs += $dUs
            # us * kHz = millicycles, so 1e9 converts to megacycles.
            $residencyCycles += ($dUs * $khz) / 1e9
        }

        $idleUs = 0.0
        $idleDetail = @{}
        if ($Before.idle.ContainsKey($cpuKey) -and $After.idle.ContainsKey($cpuKey)) {
            foreach ($state in $Before.idle[$cpuKey].Keys) {
                if (-not $After.idle[$cpuKey].ContainsKey($state)) { continue }
                $d = $After.idle[$cpuKey][$state].time - $Before.idle[$cpuKey][$state].time
                if ($d -lt 0) { $d = 0 }
                $idleUs += $d
                $idleDetail[$state] = $d
            }
        }

        $busyUs = $wallUs - $idleUs
        if ($busyUs -lt 0) { $busyUs = 0 }

        $meanMhz = 0.0
        # megacycles per microsecond is 1e12 cycles/s, so 1e6 converts to MHz.
        if ($residencyUs -gt 0) { $meanMhz = ($residencyCycles / $residencyUs) * 1e6 }

        $busyRatio = $busyUs / $wallUs

        # Work estimate. cpuidle says what fraction of the window the core was
        # outside an idle state; time_in_state says what frequency it was
        # clocked at. Their product is the honest approximation to retired
        # cycles, and it is an approximation because the two counters are not
        # jointly binned: a core that is busy only while boosted and idle only
        # while parked low reads the same as one with the reverse pattern.
        # Good enough to compare two arms of an A/B, not a cycle counter.
        $workCycles = $residencyCycles * $busyRatio

        $perCpu += [pscustomobject]@{
            cpu               = $cpu
            cluster           = Get-ThorClusterName -Cpu $cpu
            residency_mcycles = [math]::Round($residencyCycles, 1)
            work_mcycles      = [math]::Round($workCycles, 1)
            busy_ratio        = [math]::Round($busyRatio, 4)
            idle_us           = [int64]$idleUs
            idle_states       = $idleDetail
            mean_mhz          = [math]::Round($meanMhz, 1)
        }
    }

    $clusters = @()
    foreach ($group in ($perCpu | Group-Object cluster)) {
        $work = ($group.Group | Measure-Object work_mcycles -Sum).Sum
        $res = ($group.Group | Measure-Object residency_mcycles -Sum).Sum
        $busy = ($group.Group | Measure-Object busy_ratio -Average).Average
        $mhz = ($group.Group | Measure-Object mean_mhz -Average).Average
        $clusters += [pscustomobject]@{
            cluster           = $group.Name
            cores             = $group.Count
            work_mcycles      = [math]::Round($work, 1)
            residency_mcycles = [math]::Round($res, 1)
            mean_busy         = [math]::Round($busy, 4)
            cores_busy        = [math]::Round(($busy * $group.Count), 3)
            mean_mhz          = [math]::Round($mhz, 1)
        }
    }

    $totalCycles = ($perCpu | Measure-Object work_mcycles -Sum).Sum
    $totalBusy = ($perCpu | Measure-Object busy_ratio -Sum).Sum

    # Battery is reported but never used as the headline, because adb over USB
    # charges the device and turns current_now into charge current. It is
    # meaningful only when status is Discharging.
    $battery = [ordered]@{
        status_before  = $Before.battery.status
        status_after   = $After.battery.status
        current_ua     = $After.battery.current_ua
        voltage_uv     = $After.battery.voltage_uv
        usable         = ($After.battery.status -eq "Discharging" -and $Before.battery.status -eq "Discharging")
    }
    if ($battery.usable -and $After.battery.voltage_uv -and $After.battery.current_ua) {
        $watts = [math]::Abs($After.battery.current_ua / 1e6 * $After.battery.voltage_uv / 1e6)
        $battery.watts = [math]::Round($watts, 3)
    }

    return [pscustomobject]@{
        wall_seconds     = [math]::Round(($wallNs / 1e9), 3)
        total_work_mcycles = [math]::Round($totalCycles, 1)
        total_cores_busy = [math]::Round($totalBusy, 3)
        clusters         = $clusters
        per_cpu          = $perCpu
        battery          = $battery
    }
}

# Running as a script rather than being dot-sourced for the helpers.
if ($MyInvocation.InvocationName -ne '.') {
    $serial = $Device
    if (-not $serial) {
        $rows = @(& adb devices | Select-String -Pattern '^\S+\s+device$')
        if ($rows.Count -eq 0) { throw "No device is attached." }
        # Wrap the whole pipeline. Indexing a bare single match yields a char.
        $serial = @($rows[0] -split '\s+')[0]
    }

    Write-Output "Probing '$Label' on $serial for $DurationSeconds s (2 adb round trips, cost independent of duration)."

    $before = Get-ThorPowerSnapshot -Serial $serial
    Start-Sleep -Seconds $DurationSeconds
    $after = Get-ThorPowerSnapshot -Serial $serial

    $delta = Get-ThorPowerDelta -Before $before -After $after

    Write-Output ""
    Write-Output "window            : $($delta.wall_seconds) s"
    Write-Output "work (estimate)   : $($delta.total_work_mcycles) megacycles"
    Write-Output "cores busy (avg)  : $($delta.total_cores_busy) of 8"
    Write-Output ""
    foreach ($c in $delta.clusters) {
        $line = "  {0,-10} {1} cores  {2,9} Mcyc work  {3,6} cores busy  {4,7} MHz mean" -f $c.cluster, $c.cores, $c.work_mcycles, $c.cores_busy, $c.mean_mhz
        Write-Output $line
    }
    Write-Output ""
    if ($delta.battery.usable) {
        Write-Output "battery           : $($delta.battery.watts) W (discharging, usable)"
    } else {
        Write-Output "battery           : not usable, status=$($delta.battery.status_after). Unplug USB and use wireless adb for absolute watts."
    }

    $outDir = $OutputDirectory
    if (-not $outDir) {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $outDir = Join-Path $repoRoot "debug-captures"
    }
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

    $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $safeLabel = ($Label -replace '[^A-Za-z0-9_.-]', '_')
    $path = Join-Path $outDir "power-$stamp-$safeLabel.json"
    $payload = [ordered]@{
        label   = $Label
        device  = $serial
        stamp   = $stamp
        delta   = $delta
    }
    $payload | ConvertTo-Json -Depth 8 | Out-File -FilePath $path -Encoding utf8
    Write-Output ""
    Write-Output "Wrote $path"
}
