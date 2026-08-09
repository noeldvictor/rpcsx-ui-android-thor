[CmdletBinding()]
param(
    [string]$Device = "192.168.1.33:5555",
    [string]$Package = "net.rpcsx.easy",
    [string]$TitleId = "BCUS98147",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso",
    [string[]]$Modes = @("yield", "isb", "nop"),
    [int]$SettleSeconds = 150,
    [int]$ProbeSeconds = 60
)

$ErrorActionPreference = "Stop"

# A/B the AArch64 spin instruction.
#
# rx::pause() emitted YIELD, which is an SMT hint and retires as a nop on an SMP
# core with no sibling thread -- so as an x86 PAUSE substitute it does nothing
# but occupy an issue slot. Upstream RPCS3 uses ISB. The comment at the site
# asked for this to be "measured on its own, not bundled with other changes",
# because this fork's spin counts were hand-tuned around YIELD.
#
# Three arms, because two would not be conclusive:
#
#   yield  the tuned baseline, unchanged
#   isb    upstream's choice: actually stalls the pipeline
#   nop    control. If isb and nop match, the spin is insensitive to the
#          instruction and the question is moot. If yield and nop match, that
#          is direct evidence YIELD is retiring as a nop on this core rather
#          than merely being suspected of it.
#
# Power, not frame time, is the measurement. Folklore holds 60 fps either way;
# the cost of a useless spin instruction shows up as watts. thor_power_probe.ps1
# reads cumulative counters, so its own cost does not scale with the window.
#
# The property is read once into a function-local static, so every arm needs a
# fresh process -- do not try to switch modes on a running emulator.

function Invoke-Adb {
    param([string[]]$AdbArgs)
    & adb -s $Device @AdbArgs 2>&1
}

function Assert-Reachable {
    $ok = (Invoke-Adb @("shell", "echo ok")) -join "" -replace '\s', ''
    if ($ok -ne "ok") { throw "device $Device unreachable" }
}

Assert-Reachable

$probe = Join-Path $PSScriptRoot "thor_power_probe.ps1"
if (-not (Test-Path $probe)) { throw "missing $probe" }

$results = @()

foreach ($mode in $Modes) {
    Write-Host ""
    Write-Host "=== pause_mode = $mode ==="

    Invoke-Adb @("shell", "am force-stop $Package") | Out-Null
    Invoke-Adb @("shell", "setprop debug.rpcsx.thor.pause_mode $mode") | Out-Null

    $readback = ((Invoke-Adb @("shell", "getprop debug.rpcsx.thor.pause_mode")) -join "").Trim()
    if ($readback -ne $mode) { throw "property did not take: wanted '$mode', read '$readback'" }

    $intent = "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity " +
              "--es path '$GamePath' --es titleId $TitleId " +
              "--es thorDebugBootRequestId pausemode-$mode " +
              "--ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true"
    Invoke-Adb @("shell", $intent) | Out-Null

    Start-Sleep -Seconds 2
    $pid_ = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()
    if (-not $pid_) { throw "emulator did not launch for mode '$mode'" }
    Write-Host "  pid $pid_, settling ${SettleSeconds}s to reach a steady workload"

    Start-Sleep -Seconds $SettleSeconds

    # An unreachable device returns empty from pidof exactly like a dead process,
    # so prove the link before believing the liveness check.
    Assert-Reachable
    $still = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()
    if (-not $still) { throw "emulator died during settle for mode '$mode'" }

    # The probe reports through Write-Host, so nothing reaches the pipeline --
    # read the JSON it writes instead. Note it is UTF-8 *with BOM*, which
    # ConvertFrom-Json and python's plain utf-8 both choke on.
    & $probe -Device $Device -DurationSeconds $ProbeSeconds -Label "pause-$mode" | Out-Host

    $json = Get-ChildItem (Join-Path $PSScriptRoot "..\debug-captures") -Filter "power-*-pause-$mode.json" |
            Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $json) { throw "no probe output for mode '$mode'" }
    $d = (Get-Content $json.FullName -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json

    $cores = [double]$d.delta.total_cores_busy
    $work  = [double]$d.delta.total_work_mcycles
    $secs  = [double]$d.delta.wall_seconds

    # Watts only when the charger is not covering the load. Clock residency is
    # unaffected by USB, so work/cores stay valid either way -- and for "is this
    # spin instruction wasting cycles" they are the more direct measure anyway.
    $watts = if ($d.delta.battery.usable) { [double]$d.delta.battery.system_power_w } else { [double]::NaN }
    if ([double]::IsNaN($watts)) {
        Write-Host "  $mode : $cores cores busy, $work Mcyc over ${secs}s (battery not usable: charging)"
    } else {
        Write-Host "  $mode : $watts W, $cores cores busy, $work Mcyc"
    }

    $results += [pscustomobject]@{ mode = $mode; watts = $watts; cores = $cores; mcyc_per_s = [math]::Round($work / $secs, 1) }
}

Invoke-Adb @("shell", "am force-stop $Package") | Out-Null

Write-Host ""
Write-Host "=== summary ==="
$results | Format-Table -AutoSize
$base = ($results | Where-Object { $_.mode -eq "yield" }).mcyc_per_s
if ($base) {
    foreach ($r in $results) {
        $pct = 100.0 * ($r.mcyc_per_s - $base) / $base
        # watts may be NaN when the charger covered the load; never format it blind
        Write-Host ("  {0,-6} {1,9:N1} Mcyc/s  {2,6:N3} cores  ({3,6:N1}% vs yield)" -f $r.mode, $r.mcyc_per_s, $r.cores, $pct)
    }
}
Write-Host ""
Write-Host "Emulator stopped. Interpretation guide is at the top of this file."
