[CmdletBinding()]
param(
    [string]$Device = "",
    [string]$Package = "net.rpcsx.easy",
    [string]$ThreadName = "rsx::thread",
    [int]$Samples = 12,
    [int]$BootWaitSeconds = 60,
    [string]$GamePath = "/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso",
    [string]$TitleId = "BLUS30161",
    [switch]$NoBoot
)

$ErrorActionPreference = "Stop"

# Name the loop that hangs the RSX thread, by symbolizing the syscall PC.
#
# The hang is documented in docs/arm64/rsx-boot-hang.md: rsx::thread pegs at 100%
# about eight and a half seconds into emulation and never recovers, with roughly
# 85% of its time in the kernel. That kernel share means it is a vkGet*Status poll
# rather than one of the userspace rx::pause() loops, and three call sites take
# vk::wait_for_fence's default timeout of zero, which polls with no upper bound:
#
#   VKPresent.cpp:199        resize_fence, the swapchain rebuild
#   commands.cpp:77          m_submit_fence
#   VKGSRenderTypes.hpp:358  cb.wait(), called with no argument
#
# Static reading cannot choose between them. This can.
#
# HOW
#
# /proc/<tid>/syscall reports "nr arg0..arg5 sp pc", where pc is the userspace
# program counter at the point of the syscall. Subtract the load address of the
# library containing it, taken from /proc/<tid>/maps, and llvm-symbolizer turns
# the remainder into a file and line. That is the call site, not an inference
# about it.
#
# REQUIRES A DEBUGGABLE BUILD. On the release variant run-as refuses the package
# and /proc/<tid>/syscall is Permission denied, which is what made this question
# unanswerable in the first place:
#
#   ./gradlew assembleThortest -PrpcsxThorDebuggable=1
#
# That property deliberately does not touch the CMake arguments, so it reuses the
# cached native objects. It also leaves the default off, because thortest is the
# measurement variant and android:debuggable changes ART's behaviour - taking a
# power or spin number from this build would be the wrong footing.

$serial = $Device
if (-not $serial) {
    $rows = @(& adb devices | Select-String -Pattern '^\S+\s+device$')
    if ($rows.Count -eq 0) { throw "No device is attached." }
    $serial = @($rows[0] -split '\s+')[0]
}

function Invoke-Device {
    param([string]$Cmd)
    return (& adb -s $serial shell $Cmd 2>&1 | Out-String)
}

# Fail closed on a non-debuggable build rather than emitting empty samples that
# read like "the thread was not in a syscall".
$probe = Invoke-Device "run-as $Package id"
if ($probe -match 'not debuggable|unknown package|Permission denied') {
    throw "run-as refused $Package ($($probe.Trim())). This needs a debuggable build: ./gradlew assembleThortest -PrpcsxThorDebuggable=1"
}

if (-not $NoBoot) {
    Write-Output "Booting $TitleId and waiting $BootWaitSeconds s for the hang..."
    & adb -s $serial shell am force-stop $Package 2>&1 | Out-Null
    & adb -s $serial shell input keyevent KEYCODE_WAKEUP 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    $rid = "hangdiag-$(Get-Random)"
    & adb -s $serial shell "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $Package/net.rpcsx.MainActivity --es path '$GamePath' --es titleId $TitleId --es thorDebugBootRequestId $rid --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" 2>&1 | Out-Null
    Start-Sleep -Seconds $BootWaitSeconds
}

$appPid = (Invoke-Device "pidof $Package").Trim()
if (-not $appPid) { throw "$Package is not running." }

# Locate the thread by name. top's COMM column truncates, so read comm directly.
$tid = $null
$taskList = (Invoke-Device "ls /proc/$appPid/task").Trim() -split '\s+'
foreach ($t in $taskList) {
    if (-not $t) { continue }
    $comm = (Invoke-Device "cat /proc/$appPid/task/$t/comm").Trim()
    if ($comm -eq $ThreadName) { $tid = $t; break }
}
if (-not $tid) { throw "No thread named '$ThreadName' in pid $appPid." }

Write-Output "pid=$appPid tid=$tid ($ThreadName)"
Write-Output ""

# Confirm it is actually spinning before attributing anything to the samples. A
# thread that is blocked, or one that is making progress, produces the same
# syscall readings and a completely different conclusion.
$s1 = ((Invoke-Device "cat /proc/$appPid/task/$tid/stat").Trim() -split '\s+')
Start-Sleep -Seconds 5
$s2 = ((Invoke-Device "cat /proc/$appPid/task/$tid/stat").Trim() -split '\s+')
$dUser = [int]$s2[13] - [int]$s1[13]
$dSys = [int]$s2[14] - [int]$s1[14]
$ratio = if ($dUser -gt 0) { [math]::Round($dSys / $dUser, 2) } else { [double]::PositiveInfinity }
Write-Output "over 5 s: dUser=$dUser dSys=$dSys jiffies  sys/user=$ratio  state=$($s2[2])"
if (($dUser + $dSys) -lt 100) {
    Write-Warning "This thread is not busy. Whatever the samples below show, it is not the spin described in docs/arm64/rsx-boot-hang.md."
}
Write-Output ""

# Map the address space once. Sampling it per iteration would be pure overhead;
# the library is not going to move.
$mapsRaw = (Invoke-Device "run-as $Package cat /proc/$tid/maps")
$maps = @()
foreach ($line in ($mapsRaw -split "`n")) {
    if ($line -match '^([0-9a-f]+)-([0-9a-f]+)\s+(\S+)\s+([0-9a-f]+)\s+\S+\s+\d+\s+(\S+)') {
        $maps += [pscustomobject]@{
            Start  = [Convert]::ToUInt64($Matches[1], 16)
            End    = [Convert]::ToUInt64($Matches[2], 16)
            Perms  = $Matches[3]
            Offset = [Convert]::ToUInt64($Matches[4], 16)
            Path   = $Matches[5]
        }
    }
}

$syscallNames = @{
    29  = "ioctl"; 98 = "futex"; 73 = "ppoll"; 101 = "nanosleep"; 124 = "sched_yield"
    63  = "read";  64 = "write"; 71 = "sendmsg"; 72 = "recvmsg"; 22 = "close"
    226 = "mprotect"; 215 = "munmap"; 222 = "mmap"
}

Write-Output "--- syscall samples ---"
$hits = @{}
for ($i = 1; $i -le $Samples; $i++) {
    $raw = (Invoke-Device "run-as $Package cat /proc/$tid/syscall").Trim()
    if ($raw -match 'Permission denied|No such') { throw "Cannot read /proc/$tid/syscall: $raw" }
    if ($raw -eq 'running') {
        Write-Output ("  [{0,2}] running (not in a syscall at the instant sampled)" -f $i)
        continue
    }

    $parts = $raw -split '\s+'
    $nr = $parts[0]
    $nrName = if ($syscallNames.ContainsKey([int]$nr)) { $syscallNames[[int]$nr] } else { "nr=$nr" }
    $pcHex = $parts[$parts.Count - 1]
    $pc = [Convert]::ToUInt64($pcHex.TrimStart('0', 'x').PadLeft(1, '0'), 16)

    $owner = $maps | Where-Object { $pc -ge $_.Start -and $pc -lt $_.End } | Select-Object -First 1
    if ($owner) {
        $off = $pc - $owner.Start + $owner.Offset
        $key = "$($owner.Path)+0x{0:x}" -f $off
        $hits[$key] = 1 + ($hits[$key] | ForEach-Object { $_ })
        Write-Output ("  [{0,2}] {1,-12} pc={2} -> {3}" -f $i, $nrName, $pcHex, $key)
    }
    else {
        Write-Output ("  [{0,2}] {1,-12} pc={2} -> (unmapped)" -f $i, $nrName, $pcHex)
    }
}

Write-Output ""
Write-Output "--- distinct call sites ---"
foreach ($k in ($hits.Keys | Sort-Object { -$hits[$_] })) {
    Write-Output ("  {0,4}x  {1}" -f $hits[$k], $k)
}

Write-Output ""
Write-Output "To turn a librpcsx offset into a file and line, symbolize against the"
Write-Output "UNSTRIPPED library from the build that is installed - the packaged one is"
Write-Output "stripped and will silently give you nothing useful:"
Write-Output ""
Write-Output '  $sym = "$env:ANDROID_NDK_HOME/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-symbolizer.exe"'
Write-Output '  $lib = (Get-ChildItem app/build/intermediates/cxx -Recurse -Filter librpcsx-android.so |'
Write-Output '          Where-Object FullName -match "arm64-v8a" | Select-Object -First 1).FullName'
Write-Output '  & $sym --obj=$lib --functions=linkage --demangle <offset>'
Write-Output ""
Write-Output "Expect one of the three zero-timeout vk::wait_for_fence call sites."
