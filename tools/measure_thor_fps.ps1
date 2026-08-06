<#
Samples presented frame rate on Thor from SurfaceFlinger, independent of the
emulator's own overlay.

RPCS3 only draws FPS into `overlay_perf_metrics.cpp`; it never logs it. That
makes an FPS claim depend on reading a screenshot, which is not something a
route can gate on. SurfaceFlinger already timestamps every presented frame, so
this reads the real presentation cadence of whatever RPCSX is showing.

Usage:
  # validate the sampler against any running surface
  .\tools\measure_thor_fps.ps1 -Seconds 5

  # sample while a route is running in another shell
  .\tools\measure_thor_fps.ps1 -Seconds 20 -Label field-route-fps

`--latency` returns up to 128 recent frames as three timestamps per line, in
nanoseconds. The middle column is the presentation timestamp, which is the one
that describes what the panel actually showed. Rows with the sentinel
`9223372036854775807` are frames still in flight and are dropped.
#>
param(
    [string]$Serial = "c3ca0370",
    [string]$Package = "net.rpcsx.easy",
    [ValidateRange(2, 300)]
    [int]$Seconds = 10,
    [ValidateRange(1, 30)]
    [int]$SampleIntervalSeconds = 2,
    # A route spends its preflight and boot handshake before the emulator has a
    # surface, so sampling alongside one has to wait for the layer to appear
    # rather than assume it is already there.
    [ValidateRange(0, 300)]
    [int]$WaitForLayerSeconds = 0,
    [string]$Label = "thor-fps"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\thor_debug_common.ps1"

$adb = Resolve-ThorAdb

function Find-RpcsxLayerName {
    $rows = @(& $adb -s $Serial shell "dumpsys SurfaceFlinger --list" 2>&1)
    # The emulator draws from RPCSXActivity, and its SurfaceView carries its own
    # layer, so match the package or the fork name rather than one activity.
    return $rows |
        Where-Object { $_ -match [regex]::Escape($Package) -or $_ -match '(?i)rpcsx' } |
        Where-Object { $_ -notmatch 'Background|Dim|ScreenDecor|InputMethod|Wallpaper' } |
        Select-Object -Last 1
}

function Get-RpcsxLayerName {
    $deadline = (Get-Date).AddSeconds($WaitForLayerSeconds)
    do {
        $match = Find-RpcsxLayerName
        if ($match) { return $match.ToString().Trim() }
        if ($WaitForLayerSeconds -gt 0) { Start-Sleep -Seconds 1 }
    } while ((Get-Date) -lt $deadline)

    throw "No SurfaceFlinger layer for $Package after ${WaitForLayerSeconds}s. Is it running and in the foreground?"
}

function Get-FrameTimestamps {
    param([string]$Layer)

    $quoted = "'" + $Layer.Replace("'", "'\''") + "'"
    $rows = @(& $adb -s $Serial shell "dumpsys SurfaceFlinger --latency $quoted" 2>&1)
    $stamps = New-Object System.Collections.Generic.List[double]
    foreach ($row in $rows) {
        $parts = $row.ToString().Trim() -split '\s+'
        if ($parts.Count -ne 3) { continue }
        $present = 0.0
        if (-not [double]::TryParse($parts[1], [ref]$present)) { continue }
        # Frames still queued carry INT64_MAX; a zero row is padding.
        if ($present -le 0 -or $present -ge 9.2e18) { continue }
        $stamps.Add($present)
    }
    return $stamps
}

$layer = Get-RpcsxLayerName
Write-Output "layer=$layer"

$seen = New-Object System.Collections.Generic.HashSet[double]
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    foreach ($t in (Get-FrameTimestamps -Layer $layer)) { [void]$seen.Add($t) }
    Start-Sleep -Seconds $SampleIntervalSeconds
}

$ordered = @($seen) | Sort-Object
if ($ordered.Count -lt 3) {
    throw "Only $($ordered.Count) presented frames observed; nothing is being drawn."
}

$deltasMs = for ($i = 1; $i -lt $ordered.Count; $i++) { ($ordered[$i] - $ordered[$i - 1]) / 1e6 }
# A gap far past any real frame interval means the surface stalled or the
# 128-frame ring wrapped between samples; those gaps are not frame times.
$frameDeltas = @($deltasMs | Where-Object { $_ -gt 0.5 -and $_ -lt 250 })
if ($frameDeltas.Count -lt 3) {
    throw "No contiguous frame intervals survived filtering."
}

$sorted = @($frameDeltas | Sort-Object)
$median = $sorted[[int]($sorted.Count / 2)]
$mean = ($frameDeltas | Measure-Object -Average).Average
$p95 = $sorted[[int]([Math]::Floor($sorted.Count * 0.95))]
$spanSeconds = ($ordered[-1] - $ordered[0]) / 1e9

[pscustomobject]@{
    label            = $Label
    presented_frames = $ordered.Count
    window_seconds   = [Math]::Round($spanSeconds, 2)
    fps_mean         = [Math]::Round(1000.0 / $mean, 2)
    fps_median       = [Math]::Round(1000.0 / $median, 2)
    frame_ms_mean    = [Math]::Round($mean, 3)
    frame_ms_median  = [Math]::Round($median, 3)
    frame_ms_p95     = [Math]::Round($p95, 3)
} | Format-List
