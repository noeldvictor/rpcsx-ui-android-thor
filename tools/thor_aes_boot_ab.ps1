[CmdletBinding()]
param(
    [string]$Device = "",
    [string]$Package = "net.rpcsx.easy",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Odin Sphere - Leifthrasir (USA).iso",
    [string]$TitleId = "BLUS31601",
    [string]$Marker = "Cubeb: Stream started",
    [int]$Reps = 4,
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

# Does hardware AES actually shorten a boot?
#
# docs/arm64/aes.md measures the primitive at 18.9x-21.8x on the big cores. That
# is throughput of the block function on an L2-resident buffer, and it says
# nothing about what share of a boot is AES. Boot also does PPU analysis, LLVM
# linking, shader cache work and file I/O, any of which can dwarf it.
#
# So this is written to be able to come back NO DIFFERENCE, and that result would
# be worth as much as a positive one: it would mean the 20x is real and
# irrelevant to boot, and that the win lives somewhere else (PKG install, or
# nowhere the user notices). The failure mode to avoid is quoting the 20x as
# though it were a boot speedup.
#
# METHOD
#
#   - One build, two arms, toggled by debug.rpcsx.thor.aes_arm64. A compile-time
#     switch would need a full native rebuild per arm, and two binaries differ in
#     more than the thing under test.
#   - Arms ALTERNATE rather than running in blocks, so thermal drift and cache
#     warming spread across both instead of loading onto whichever ran second.
#     This project has already had one A/B that was really measuring which
#     cluster an arm landed on.
#   - The measurement is wall-clock from launch to a fixed emulator log line,
#     read from the emulator's own log rather than from a screenshot.
#   - The property readback is verified. A setprop that silently did not take
#     would produce two identical arms and a confident "no difference".

$serial = $Device
if (-not $serial) {
    $rows = @(& adb devices | Select-String -Pattern '^\S+\s+device$')
    if ($rows.Count -eq 0) { throw "No device is attached." }
    $serial = @($rows[0] -split '\s+')[0]
}

$logPath = "/storage/emulated/0/Android/data/$Package/files/cache/RPCSX.log"

function Invoke-Boot {
    param([string]$Arm)

    & adb -s $serial shell am force-stop $Package 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    if ($Arm -eq "off") {
        & adb -s $serial shell "setprop debug.rpcsx.thor.aes_arm64 0" 2>&1 | Out-Null
    } else {
        & adb -s $serial shell "setprop debug.rpcsx.thor.aes_arm64 1" 2>&1 | Out-Null
    }

    $want = if ($Arm -eq "off") { "0" } else { "1" }
    $got = (& adb -s $serial shell getprop debug.rpcsx.thor.aes_arm64 2>&1 | Out-String).Trim()
    if ($got -ne $want) {
        throw "Property readback is '$got', expected '$want'. Refusing to attribute a timing to a setting that did not take."
    }

    # Truncate the log so the marker search cannot match a previous run.
    & adb -s $serial shell "rm -f '$logPath'" 2>&1 | Out-Null
    & adb -s $serial shell input keyevent KEYCODE_WAKEUP 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    $rid = "aesab-$Arm-$(Get-Random)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & adb -s $serial shell "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path '$GamePath' --es titleId $TitleId --es thorDebugBootRequestId $rid --ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false" 2>&1 | Out-Null

    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 900
        $hit = (& adb -s $serial shell "grep -c '$Marker' '$logPath' 2>/dev/null" 2>&1 | Out-String).Trim()
        if ($hit -match '^[1-9]') {
            $sw.Stop()
            return $sw.Elapsed.TotalSeconds
        }
        $alive = (& adb -s $serial shell pidof $Package 2>&1 | Out-String).Trim()
        if (-not $alive) { throw "Process died during arm '$Arm'." }
    }

    throw "Marker '$Marker' not seen within $TimeoutSeconds s on arm '$Arm'."
}

$on = @()
$off = @()

for ($i = 1; $i -le $Reps; $i++) {
    foreach ($arm in @("on", "off")) {
        $t = Invoke-Boot -Arm $arm
        if ($arm -eq "on") { $on += $t } else { $off += $t }
        Write-Output ("  rep {0}  aes={1,-3}  {2,7:N2} s" -f $i, $arm, $t)
    }
}

& adb -s $serial shell am force-stop $Package 2>&1 | Out-Null
& adb -s $serial shell "setprop debug.rpcsx.thor.aes_arm64 ''" 2>&1 | Out-Null

function Stat { param([double[]]$v)
    $m = ($v | Measure-Object -Average -Minimum -Maximum)
    return [pscustomobject]@{ mean = $m.Average; min = $m.Minimum; max = $m.Maximum }
}

$sOn = Stat $on
$sOff = Stat $off

Write-Output ""
Write-Output "=== boot to '$Marker' ==="
Write-Output ("  hardware AES : mean {0,6:N2} s   min {1,6:N2}   max {2,6:N2}" -f $sOn.mean, $sOn.min, $sOn.max)
Write-Output ("  software AES : mean {0,6:N2} s   min {1,6:N2}   max {2,6:N2}" -f $sOff.mean, $sOff.min, $sOff.max)

$delta = $sOff.mean - $sOn.mean
$spread = [Math]::Max($sOn.max - $sOn.min, $sOff.max - $sOff.min)

Write-Output ("  delta        : {0,6:N2} s  ({1:N1}%)" -f $delta, (100.0 * $delta / $sOff.mean))
Write-Output ("  worst within-arm spread : {0,6:N2} s" -f $spread)
Write-Output ""

if ([Math]::Abs($delta) -lt $spread) {
    Write-Output "The difference is smaller than the noise within a single arm."
    Write-Output "Read that as: AES is not a measurable share of this boot. The 20x on"
    Write-Output "the primitive is still real - it just is not where boot time goes."
} else {
    Write-Output "The difference exceeds the within-arm spread, so it is worth taking"
    Write-Output "seriously - but confirm with more reps before quoting it."
}
