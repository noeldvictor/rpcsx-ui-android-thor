param(
    [int]$WaitMinutes = 0,
    [string]$Serial = "",
    [string]$TcpTarget = "192.168.1.33:5555",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

# Install the current Thor build, waiting for the device if asked.
#
# Exists because "install after every round" and "the device is plugged in" are
# not the same thing. When the Thor is unplugged or asleep, adb reports no
# device at all and there is nothing to retry against, so the install has to be
# deferred rather than attempted and failed. This makes deferral a single
# command instead of an ad-hoc background loop that dies with the session.
#
#   .\tools\install_thor_when_available.ps1                  install now, or say why not
#   .\tools\install_thor_when_available.ps1 -WaitMinutes 120  wait up to 2h, then install
#   .\tools\install_thor_when_available.ps1 -SkipBuild        use the APK already built
#
# Exit codes: 0 installed and smoke-tested, 1 no device, 2 build or install failed.

$repoRoot = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $repoRoot "app/build/outputs/apk/thortest/rpcsx-thor-experiment-thortest.apk"

function Get-OnlineSerial {
    $rows = (adb devices) -split "`n" | Where-Object { $_ -match "\sdevice$" }
    if (-not $rows) { return $null }
    if ($Serial) {
        foreach ($r in $rows) { if (($r -split "\s+")[0] -eq $Serial) { return $Serial } }
        return $null
    }
    return ($rows[0] -split "\s+")[0]
}

# Build first so a returning device is installed to immediately rather than
# waiting on a compile.
if (-not $SkipBuild) {
    Write-Output "Building thortest..."
    Push-Location $repoRoot
    try {
        $out = & .\gradlew.bat :app:assembleThortest --console=plain 2>&1
        if ($LASTEXITCODE -ne 0) {
            $out | Select-Object -Last 20
            Write-Output "RESULT: build failed"
            exit 2
        }
    } finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath $apk)) {
    Write-Output "RESULT: no APK at $apk (build first, or drop -SkipBuild)"
    exit 2
}

# The ABI contract is cheap and catches the one packaging mistake that has
# actually happened here: shipping libraries this device cannot execute.
& (Join-Path $PSScriptRoot "test_thor_arm64_apk.ps1") -ApkPath $apk | Select-Object -Last 1

$deadline = (Get-Date).AddMinutes($WaitMinutes)
$target = Get-OnlineSerial

while (-not $target -and (Get-Date) -lt $deadline) {
    # Try the wifi endpoint too; a Thor that dropped off USB is often still
    # reachable over TCP, and connect is harmless when it is not.
    if ($TcpTarget) { adb connect $TcpTarget *> $null }
    Start-Sleep -Seconds 20
    $target = Get-OnlineSerial
}

if (-not $target) {
    Write-Output "RESULT: no device. Reconnect the Thor over USB, or bring it back on wifi, then re-run."
    exit 1
}

Write-Output "Device: $target"
adb -s $target install -r $apk | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { Write-Output "RESULT: install failed"; exit 2 }

# firstInstallTime staying put is the evidence that game data, SPU caches and
# cheats survived, rather than this having been a fresh install.
adb -s $target shell "dumpsys package net.rpcsx.easy | grep -E 'lastUpdateTime|firstInstall'"

# Smoke test: the app must reach its activity without a fatal signal. This is
# what catches an ISA baseline that the device cannot actually execute.
adb -s $target logcat -c
adb -s $target shell "am force-stop net.rpcsx.easy; am start -n net.rpcsx.easy/net.rpcsx.MainActivity" | Out-Null
Start-Sleep -Seconds 12

$pidOut = (adb -s $target shell "pidof net.rpcsx.easy").Trim()
$fatal = adb -s $target logcat -d -t 300 2>&1 |
    Select-String -Pattern "Fatal signal|SIGSEGV|SIGILL" |
    Select-Object -First 3

adb -s $target shell "am force-stop net.rpcsx.easy" | Out-Null

if ($fatal) {
    Write-Output "RESULT: installed, but the launch produced fatal signals:"
    $fatal | ForEach-Object { Write-Output "  $_" }
    exit 2
}

if (-not $pidOut) {
    Write-Output "RESULT: installed, but the process was not alive after launch"
    exit 2
}

Write-Output "RESULT: installed and smoke-tested (pid was $pidOut, no fatal signals)"
exit 0
