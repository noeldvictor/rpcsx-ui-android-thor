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
    [int]$CooldownSeconds = 420,
    [double]$MaxForeignCpu = 20.0
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

function Get-ForeignEmulatorCpu {
    # The Thor is shared with another session that tests Xbox 360 emulation. Never
    # force-stop that package. Do measure whether it is running, because an arm
    # that shares the machine with a process holding two cores measures contention
    # and thermal throttling, not the change under test.
    $rows = (Invoke-Adb @("shell", "top -b -n 2 -d 2 | grep xenia | grep -v logcat | grep -v grep")) -join "`n"
    $max = 0.0
    foreach ($line in ($rows -split "`n")) {
        # %CPU is the column before %MEM in this build's top output.
        if ($line -match '\s(\d+(?:\.\d+)?)\s+\d+(?:\.\d+)?\s+\d+:\d+\.\d+\s') {
            $v = [double]$matches[1]
            if ($v -gt $max) { $max = $v }
        }
    }
    return $max
}

function Assert-Uncontended {
    param([string]$When)
    $foreign = Get-ForeignEmulatorCpu
    if ($foreign -gt $MaxForeignCpu) {
        throw ("arm is void: the other session's emulator is at {0:N0}% CPU $When. Do not force-stop it; re-run when the device is free." -f $foreign)
    }
    Write-Host ("foreign emulator CPU $When : {0:N0}%" -f $foreign)
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

Assert-Uncontended "before the run"

# Wait for the device to cool, and read it more than once.
#
# Installing an APK heats this device: 38.5 C before an install read 50.2 C right
# after it. thermal.md records the same shape at launch, where t=4s reads 56.6 C
# and t=10s reads 46.6 C. A single hot reading is a transient, not a state, so
# poll instead of refusing at once. Refuse only if it never cools.
# Require several consecutive cool readings, not one.
#
# A single cool sample is not a cool device. The other session cycles its
# emulator, so the temperature oscillates: one run here read 43.7 C, then 49.8 C
# fifteen seconds later, with the foreign process reading 0% in the gap between
# its own launches. Three readings in a row under the limit is the cheapest test
# that tells a settled device from a trough.
$stableNeeded = 3
$stable = 0
$pre = Get-MaxCpuTempC
Write-Host ("preflight max cpu-1-* = {0:N1} C, want {1} readings under {2:N1} C" -f $pre, $stableNeeded, $MaxPreflightC)

$coolBy = (Get-Date).AddSeconds($CooldownSeconds)
while ($true) {
    if ($pre -le $MaxPreflightC) {
        $stable++
        Write-Host ("  {0:N1} C  ({1}/{2})" -f $pre, $stable, $stableNeeded)
    } else {
        if ($stable -gt 0) { Write-Host ("  {0:N1} C  (warmed again, restarting the count)" -f $pre) }
        else { Write-Host ("  {0:N1} C" -f $pre) }
        $stable = 0
    }

    if ($stable -ge $stableNeeded) { break }
    if ((Get-Date) -ge $coolBy) {
        throw ("device never held below {0:N1} C for {1} readings within {2}s; last read {3:N1} C" -f $MaxPreflightC, $stableNeeded, $CooldownSeconds, $pre)
    }

    Start-Sleep -Seconds 15
    $pre = Get-MaxCpuTempC
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

# The other session can start at any point during the settle, so check again.
Assert-Uncontended "after the run"

# Prove the title actually started, because a live process is not a booted game.
#
# This check exists because its absence produced a confident wrong number on
# 2026-08-13. An arm reported "ok" with 14.6 CPU-seconds over a 254 second
# window, which is 5.7% of one core for what was supposed to be a cold-cache
# boot with a full PPU precompile. PPU workers read 0 and the log had no SPU
# Runtime line. The process was alive, nothing was paused, and the device was
# uncontended, so every check the harness had came back clean. The emulator had
# not booted the title at all, which AGENTS.md already records as
# launcher-ui-instead-of-title.
#
# Read the line count first. A log that is missing or nearly empty means the
# instrument failed, and that is a different fault from a title that did not
# start. Reporting them as one is how a search that searches nothing reads as a
# search that finds nothing.
$logLines = ((Invoke-Adb @("shell", "wc -l < $log 2>/dev/null")) -join "").Trim()
if (-not $logLines -or $logLines -eq "0") {
    throw "arm is void, and the instrument is at fault: $log is missing or empty, so nothing can be said about the boot"
}

$ppuThreads = ((Invoke-Adb @("shell", "grep -c 'PPU\[0x' $log")) -join "").Trim()
if ($ppuThreads -eq "0" -or -not $ppuThreads) {
    Write-Host "--- last 25 log lines, for the diagnosis ---"
    Write-Host (((Invoke-Adb @("shell", "tail -25 $log")) -join "`n"))
    throw "arm is void: no PPU thread lines in a $logLines line log, so the title never started. The process being alive is not the same as the game running."
}

Write-Host "boot confirmed: $ppuThreads PPU thread lines in a $logLines line log"

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
