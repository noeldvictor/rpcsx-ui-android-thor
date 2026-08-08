[CmdletBinding()]
param(
    [string]$Device = "",
    [int[]]$Percent = @(100, 50, 25, 0),
    [int]$SettleSeconds = 175,
    [int]$WindowSeconds = 90,
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [string]$TitleId = "BLUS30161",
    [string]$Package = "net.rpcsx.easy"
)

$ErrorActionPreference = "Stop"

# Sweep `SPU GETLLAR Busy Waiting Percentage` and report spin and power per arm.
#
# WHY THIS IS A SCRIPT AND NOT A CHECKLIST
#
# Three device experiments in this project produced numbers that meant nothing,
# and none failed for lack of care at the keyboard. They failed on methodology
# that has to be identical across arms and is easy to get subtly wrong by hand:
#
#   - two WFE A/Bs compared absolute cores_busy across arms whose scenes differed
#     by a factor of two, and the two readouts disagreed on the sign;
#   - a "running vs stopped" power comparison force-stopped a package name that
#     does not exist, so both arms were the same configuration;
#   - a backoff comparison used measurement windows that did not align with the
#     profiler's own report boundaries.
#
# Everything learned from those is encoded below rather than left to be
# remembered. See docs/arm64/power-and-thermal.md.
#
# WHAT IT MEASURES
#
# The headline is a RATIO, not an absolute. `spu_getllar` spin ticks divided by
# `spu_getllar_retry` calls: the numerator is what the percentage changes, the
# denominator is reservation contention the workload generates, which the change
# does not touch. On control windows differing 59% in absolute spin that ratio
# held to 1.1%. Absolutes are reported too, but as context, not as the result.
#
# PREREQUISITES, both enforced below rather than assumed:
#   - a profiler build: ./gradlew assembleThortest -PrpcsxThorWaitProfiler=1
#   - the device UNPLUGGED, over wireless adb, or the wattage is only a floor
#     because the charger supplies an unknown share.

function Get-ProfilerSample {
    param([string]$Serial)
    $lines = & adb -s $Serial logcat -d -v time -t 4000 2>&1 |
        Select-String -Pattern "Thor wait profiler SPU" | Select-Object -Last 1
    if (-not $lines) { return $null }
    $t = $lines.ToString()
    $m = [regex]::Match($t, '^(\d\d)-(\d\d) (\d\d):(\d\d):([\d.]+)')
    if (-not $m.Success) { return $null }
    $stamp = [double]$m.Groups[3].Value * 3600 + [double]$m.Groups[4].Value * 60 + [double]$m.Groups[5].Value
    $g = [regex]::Match($t, 'getllar=(\d+)/(\d+)')
    $r = [regex]::Match($t, 'getllar_retry=(\d+)/(\d+)')
    if (-not ($g.Success -and $r.Success)) { return $null }
    return [pscustomobject]@{
        t            = $stamp
        g_calls      = [double]$g.Groups[1].Value
        g_ticks      = [double]$g.Groups[2].Value
        r_calls      = [double]$r.Groups[1].Value
    }
}

$serial = $Device
if (-not $serial) {
    $rows = @(& adb devices | Select-String -Pattern '^\S+\s+device$')
    if ($rows.Count -eq 0) { throw "No device is attached." }
    $serial = @($rows[0] -split '\s+')[0]
}

# Refuse to produce floor-only wattage silently. This is the check that would
# have saved the earlier power comparisons.
$usbOnline = (& adb -s $serial shell "cat /sys/class/power_supply/usb/online" 2>&1 | Out-String).Trim()
if ($usbOnline -eq "1") {
    Write-Warning "USB is attached. Battery wattage will be a FLOOR only, because the charger supplies an unknown share of the load. Unplug and use wireless adb for exact system power; the spin ratio below is unaffected either way."
}

$results = @()

foreach ($p in $Percent) {
    Write-Output ""
    Write-Output "=== arm: GETLLAR busy-waiting percentage = $p ==="

    & adb -s $serial shell am force-stop $Package 2>&1 | Out-Null
    & adb -s $serial shell setprop debug.rpcsx.thor.getllar_busy_percent $p 2>&1 | Out-Null
    & adb -s $serial shell setprop debug.rpcsx.thor.wait_profiler v 2>&1 | Out-Null

    $readback = (& adb -s $serial shell getprop debug.rpcsx.thor.getllar_busy_percent 2>&1 | Out-String).Trim()
    if ($readback -ne "$p") {
        throw "Property readback is '$readback', expected '$p'. Refusing to attribute a measurement to a setting that did not take."
    }

    & adb -s $serial logcat -c 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    $rid = "sweep$p-$(Get-Random)"
    & adb -s $serial shell "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path '$GamePath' --es titleId $TitleId --es thorDebugBootRequestId $rid --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" 2>&1 | Select-Object -Last 1

    Write-Output "  settling $SettleSeconds s..."
    Start-Sleep -Seconds $SettleSeconds

    $pid0 = (& adb -s $serial shell pidof $Package 2>&1 | Out-String).Trim()
    if (-not $pid0) { throw "Emulator is not running for arm $p; the boot failed." }

    $before = Get-ProfilerSample -Serial $serial
    if (-not $before) {
        throw "No profiler output. Build with -PrpcsxThorWaitProfiler=1; without it this sweep measures nothing."
    }

    $probe = & (Join-Path $PSScriptRoot "thor_power_probe.ps1") -Device $serial -DurationSeconds $WindowSeconds -Label "getllar-pct-$p" 2>&1 | Out-String
    $after = Get-ProfilerSample -Serial $serial

    if (-not $after -or $after.t -le $before.t) {
        throw "Profiler produced no new report across the window for arm $p; cannot difference the counters."
    }

    $dt = $after.t - $before.t
    $dGTicks = $after.g_ticks - $before.g_ticks
    $dRCalls = $after.r_calls - $before.r_calls
    if ($dRCalls -le 0) { throw "No retry activity in arm $p; the denominator is zero." }

    # Frame pacing. The risk of sleeping instead of spinning is latency, not
    # throughput, and this sweep would otherwise be structurally blind to it:
    # mean FPS stays pinned at the 30 fps cap even if pacing degrades badly.
    # p95 frame time is what moves. Reuses measure_thor_fps.ps1, which reads
    # SurfaceFlinger presentation timestamps rather than the emulator's own
    # overlay, so it does not depend on reading a screenshot.
    $fpsP95 = [double]::NaN
    $fpsMean = [double]::NaN
    try
    {
        $fpsOut = & (Join-Path $PSScriptRoot "measure_thor_fps.ps1") -Serial $serial -Package $Package -Seconds 12 -Label "getllar-pct-$p" 2>&1 | Out-String
        if ($fpsOut -match 'frame_ms_p95\s*:\s*([0-9.]+)') { $fpsP95 = [double]$Matches[1] }
        if ($fpsOut -match 'fps_mean\s*:\s*([0-9.]+)') { $fpsMean = [double]$Matches[1] }
    }
    catch
    {
        Write-Warning "Frame pacing sample failed for arm $p ($_). Spin and power figures below are unaffected, but a latency regression would go unseen."
    }

    $cores = if ($probe -match 'cores busy \(avg\)\s*:\s*([0-9.]+)') { [double]$Matches[1] } else { [double]::NaN }
    $watts = if ($probe -match 'system power\s*:\s*([0-9.]+) W') { [double]$Matches[1] } else { [double]::NaN }
    $isFloor = $probe -match 'FLOOR'

    $results += [pscustomobject]@{
        percent        = $p
        ticks_per_retry = [math]::Round($dGTicks / $dRCalls, 1)
        spin_cores     = [math]::Round($dGTicks / 19200000.0 / $dt, 3)
        cores_busy     = $cores
        watts          = $watts
        watts_is_floor = $isFloor
        fps_mean       = $fpsMean
        frame_ms_p95   = $fpsP95
    }

    Write-Output ("  ticks/retry {0}   spin cores {1}   cores busy {2}   watts {3}{4}   fps {5}   p95 {6} ms" -f `
        $results[-1].ticks_per_retry, $results[-1].spin_cores, $cores, $watts, $(if ($isFloor) { " (FLOOR)" } else { "" }), $fpsMean, $fpsP95)
}

# Restore the shipped default rather than leaving the device on a swept value.
& adb -s $serial shell setprop debug.rpcsx.thor.getllar_busy_percent "" 2>&1 | Out-Null
& adb -s $serial shell setprop debug.rpcsx.thor.wait_profiler 0 2>&1 | Out-Null

Write-Output ""
Write-Output "=== sweep result ==="
$results | Format-Table -AutoSize

$base = $results | Where-Object { $_.percent -eq 100 } | Select-Object -First 1
if ($base) {
    Write-Output "Relative to 100% (always spin):"
    foreach ($r in $results | Where-Object { $_.percent -ne 100 }) {
        $dRatio = 100 * ($r.ticks_per_retry / $base.ticks_per_retry - 1)
        $dW = if ([double]::IsNaN($r.watts) -or [double]::IsNaN($base.watts)) { "n/a" } else { "{0:+0.000;-0.000} W" -f ($r.watts - $base.watts) }
        $dP = if ([double]::IsNaN($r.frame_ms_p95) -or [double]::IsNaN($base.frame_ms_p95)) { "n/a" } else { "{0:+0.00;-0.00} ms" -f ($r.frame_ms_p95 - $base.frame_ms_p95) }
        Write-Output ("  {0,3}%  spin/retry {1,7:+0.0;-0.0}%   watts {2,12}   p95 {3}" -f $r.percent, $dRatio, $dW, $dP)
    }
    Write-Output ""
    Write-Output "The spin ratio is the robust number; it held to 1.1% across control"
    Write-Output "windows that differed 59% in absolute spin. Treat a watts delta as"
    Write-Output "meaningful only if the device was unplugged. p95 frame time is the"
    Write-Output "regression to watch: mean FPS stays at the 30 cap even when pacing"
    Write-Output "degrades, so a rising p95 with flat FPS is the failure mode here."
}
