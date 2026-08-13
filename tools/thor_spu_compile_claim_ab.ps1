[CmdletBinding()]
param(
    [string]$Device = "c3ca0370",
    [string]$Package = "net.rpcsx.easy",
    [string]$TitleId = "BCUS98147",
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso",
    [ValidateSet("0", "1")]
    [string]$Claim = "1",
    [int]$SettleSeconds = 240,
    [double]$MaxPreflightC = 45.0,
    [int]$CooldownSeconds = 420
)

$ErrorActionPreference = "Stop"

# One arm of the SPU compile-claim A/B.
#
# spu_runtime::add_empty() gives back an existing item for an identical program
# and does not say that it did not insert, so each thread that reaches the same
# uncached program compiles it again with its own LLVM instance. ARMSX3 measured
# about two thirds of all cold compilation work as duplicates, and cold-boot SPU
# compilation falling from about 12,900 blocks to 3,900 when one thread claims
# the item. See docs/arm64/armsx3-comparison.md and thor_spu_compile_claim.h.
#
#   -Claim 1   the fixed behaviour, and the default in the binary
#   -Claim 0   the old behaviour, where every thread compiles the same item
#
# The metric is `SPU Runtime: Built N functions.` in RPCSX.log.
#
# **This needs a cold cache.** A warm boot compiles cached programs before SPU
# execution starts, one presentation for each program, so both arms agree and the
# run proves nothing. This script parks the title cache itself and proves the
# postcondition, because this fork has recorded four separate occasions where a
# search that searched nothing read as a search that found nothing.

$cacheRoot = "/sdcard/Android/data/$Package/files/cache/cache"
$log = "/sdcard/Android/data/$Package/files/cache/RPCSX.log"

function Invoke-Adb {
    param([string[]]$AdbArgs)
    & adb -s $Device @AdbArgs 2>&1
}

function Assert-Reachable {
    $ok = ((Invoke-Adb @("shell", "echo ok")) -join "") -replace '\s', ''
    if ($ok -ne "ok") { throw "device $Device unreachable" }
}

function Get-MaxCpuTempC {
    # Read the per-core sensors, not the package one. thermal.md records a guard
    # that compared a junction reading against a package-shaped limit.
    $raw = (Invoke-Adb @("shell", "for z in /sys/class/thermal/thermal_zone*; do t=`$(cat `$z/type 2>/dev/null); v=`$(cat `$z/temp 2>/dev/null); case `$t in cpu-1-*) echo `$v;; esac; done")) -join "`n"
    $vals = @()
    foreach ($line in ($raw -split "`n")) {
        $t = $line.Trim()
        if ($t -match '^\d+$') { $vals += [double]$t / 1000.0 }
    }
    if ($vals.Count -eq 0) { throw "no cpu-1-* thermal zones read; do not proceed blind" }
    return ($vals | Measure-Object -Maximum).Maximum
}

Assert-Reachable

# The property must exist in the shipped .so. A property that is not in the
# binary reads back fine from getprop and changes nothing, which is how this
# project produced two identical arms from one build before.
$apkDir = ((Invoke-Adb @("shell", "pm path $Package")) -join "") -replace 'package:', '' -replace 'base\.apk', '' -replace '\s', ''
$hits = ((Invoke-Adb @("shell", "grep -ac 'debug.rpcsx.thor.spu_compile_claim' ${apkDir}lib/arm64/librpcsx-android.so")) -join "").Trim()
if ($hits -eq "0" -or -not $hits) {
    throw "the installed .so does not contain debug.rpcsx.thor.spu_compile_claim, so this A/B would run two identical arms"
}
Write-Host "property present in installed .so ($hits match(es))"

Invoke-Adb @("shell", "am force-stop $Package") | Out-Null

# Wait for the device to cool, and read it more than once.
#
# Installing an APK heats this device: 38.5 C before an install read 50.2 C right
# after it. thermal.md records the same shape at launch, where t=4s reads 56.6 C
# and t=10s reads 46.6 C. A single hot reading is a transient, not a state, so
# poll instead of refusing at once. Refuse only if it never cools.
$pre = Get-MaxCpuTempC
Write-Host ("preflight max cpu-1-* = {0:N1} C" -f $pre)

if ($pre -gt $MaxPreflightC) {
    Write-Host ("waiting for cooldown to {0:N1} C, up to {1}s" -f $MaxPreflightC, $CooldownSeconds)
    $coolBy = (Get-Date).AddSeconds($CooldownSeconds)
    while ((Get-Date) -lt $coolBy) {
        Start-Sleep -Seconds 15
        $pre = Get-MaxCpuTempC
        Write-Host ("  {0:N1} C" -f $pre)
        if ($pre -le $MaxPreflightC) { break }
    }
}

if ($pre -gt $MaxPreflightC) {
    throw ("device did not cool below {0:N1} C within {1}s; last read {2:N1} C" -f $MaxPreflightC, $CooldownSeconds, $pre)
}

# Two readings under the limit, because the guard that force-stopped fifteen runs
# confirmed on an immediate re-read and still caught a spike.
Start-Sleep -Seconds 5
$pre2 = Get-MaxCpuTempC
Write-Host ("confirmed {0:N1} C" -f $pre2)
if ($pre2 -gt $MaxPreflightC) {
    throw ("device warmed again on re-read: {0:N1} C" -f $pre2)
}

# Park the title cache so the boot is genuinely cold, and prove it is gone.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (((Invoke-Adb @("shell", "ls -d $cacheRoot/$TitleId 2>/dev/null")) -join "").Trim()) {
    Invoke-Adb @("shell", "mv $cacheRoot/$TitleId $cacheRoot/$TitleId.parked-$stamp") | Out-Null
}
$still = ((Invoke-Adb @("shell", "ls -d $cacheRoot/$TitleId 2>/dev/null")) -join "").Trim()
if ($still) { throw "the cache for $TitleId is still present, so this boot would be warm and would measure nothing" }
Write-Host "cache parked; boot is cold"

Invoke-Adb @("shell", "setprop debug.rpcsx.thor.spu_compile_claim $Claim") | Out-Null
$readback = ((Invoke-Adb @("shell", "getprop debug.rpcsx.thor.spu_compile_claim")) -join "").Trim()
if ($readback -ne $Claim) { throw "property did not take: wanted '$Claim', read '$readback'" }

Invoke-Adb @("shell", "rm -f $log") | Out-Null

$intent = "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity " +
          "--es path '$GamePath' --es titleId $TitleId " +
          "--es thorDebugBootRequestId claim-$Claim " +
          "--ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true"
$launchedAt = Get-Date
Invoke-Adb @("shell", $intent) | Out-Null

Start-Sleep -Seconds 3
$pid_ = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()
if (-not $pid_) { throw "emulator did not launch" }
Write-Host "pid $pid_, settling ${SettleSeconds}s"

# Sample the PPU compile workers while precompilation runs. The worker count is
# now budgeted against MemAvailable, so it is a prediction to check, not a
# constant. See docs/arm64/ppu-compile-oom.md.
$maxWorkers = 0
$deadline = (Get-Date).AddSeconds($SettleSeconds)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $comms = (Invoke-Adb @("shell", "cat /proc/$pid_/task/*/comm 2>/dev/null")) -join "`n"
    $n = ([regex]::Matches($comms, 'PPUW')).Count
    if ($n -gt $maxWorkers) { $maxWorkers = $n }
}

Assert-Reachable
$still = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()
if (-not $still) { throw "emulator died during settle" }

# Void the arm if emulation was paused. A stray input opens the home menu, which
# pauses emulation and makes an arm look spectacular.
$paused = ((Invoke-Adb @("shell", "grep -c 'Emulation is being paused' $log")) -join "").Trim()
if ($paused -ne "0") { throw "arm is void: emulation was paused ($paused). Re-run without touching the device." }

$built = ((Invoke-Adb @("shell", "grep 'SPU Runtime: Built' $log")) -join "`n").Trim()

# Process CPU time since launch, which is the metric that can actually see this.
#
# `SPU Runtime: Built N functions.` reports what the boot loaded from the SPU
# cache. On a cold cache that number is about the programs found, not about how
# many times each one was compiled, so it need not move at all. A duplicate
# compilation is real work on a real core, so it shows up as CPU seconds burned
# over a fixed window from launch. utime and stime are in clock ticks for the
# whole process, so they cover every worker thread.
$stat = ((Invoke-Adb @("shell", "cat /proc/$pid_/stat 2>/dev/null")) -join " ").Trim()
$cpuSeconds = 0.0
if ($stat) {
    # Fields 14 and 15 are utime and stime, counted after the comm field, which
    # can itself contain spaces inside parentheses.
    $tail = $stat.Substring($stat.LastIndexOf(')') + 1).Trim() -split '\s+'
    if ($tail.Count -ge 13) {
        $ticks = [double]$tail[11] + [double]$tail[12]
        $cpuSeconds = $ticks / 100.0
    }
}

# Anything the log says about compilation, so the next run does not have to guess
# which counter exists.
$compileLines = ((Invoke-Adb @("shell", "grep -iE 'compil|SPU Runtime|LLVM:' $log | tail -20")) -join "`n").Trim()

$post = Get-MaxCpuTempC

Invoke-Adb @("shell", "am force-stop $Package") | Out-Null
Start-Sleep -Seconds 2
$dead = ((Invoke-Adb @("shell", "pidof $Package")) -join "").Trim()

Write-Host ""
Write-Host "=== claim=$Claim, $TitleId ==="
Write-Host ("elapsed        : {0:N0}s" -f ((Get-Date) - $launchedAt).TotalSeconds)
Write-Host "PPU workers max: $maxWorkers"
Write-Host ("process CPU    : {0:N1}s since launch" -f $cpuSeconds)
Write-Host "SPU built      : $(if ($built) { $built } else { '(no SPU Runtime line in the log)' })"
Write-Host "--- compile lines ---"
Write-Host "$(if ($compileLines) { $compileLines } else { '(none)' })"
Write-Host "---------------------"
Write-Host ("post temp      : {0:N1} C" -f $post)
Write-Host "pid after stop : $(if ($dead) { $dead } else { 'absent' })"
