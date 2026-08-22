#!/usr/bin/env bash
# A/B debug.rpcsx.thor.vk_dynamic_state_off on one title, interleaved.
#
# Extended dynamic state (d91dba53f, 2026-08-21) shipped with no frame rate ever
# measured: the device run that day recorded "No FPS. No frame counter was read".
# Its own comment in device.cpp predicts the failure this looks for -- a driver
# that emulates topology/cull/front-face/depth can be SLOWER than one that gets
# them baked into the pipeline object.
#
# Frames come from SurfaceFlinger present timestamps on the BLAST layer, which
# needs no build flag. Each arm is rejected if another process force-stopped the
# emulator during it, because that is indistinguishable from a crash and it has
# already voided runs here.
set -uo pipefail

DEVICE=${THOR_SERIAL:-c3ca0370}
ADB=${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}
PKG=net.rpcsx.easy
PROP=debug.rpcsx.thor.vk_dynamic_state_off
TITLE=${TITLE:-BLUS30161}
ISO=${ISO:-/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso}
ROOT=/storage/emulated/0/Android/data/$PKG/files
LOG=$ROOT/cache/RPCSX.log
CLOCK=${CLOCK:-0:01:3}      # scene point: emulator clock prefix to wait for
WINDOW=${WINDOW:-12}        # seconds of frames to collect
ROUNDS=${ROUNDS:-2}
OUT=${OUT:-/c/Users/LEANER~1/AppData/Local/Temp/thor_ab}

mkdir -p "$OUT"
sh() { MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" shell "$@" 2>/dev/null | tr -d '\r'; }

temp() { sh "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1"; }

arm() {
  local value=$1 label=$2
  sh "am force-stop $PKG; setprop $PROP $value; rm -f $LOG" >/dev/null
  local got; got=$(sh "getprop $PROP")
  [ "$got" = "$value" ] || { echo "$label: property did not take (wanted $value, read '$got')"; return 1; }

  local t0; t0=$(temp)
  local mark; mark=$(sh "date +%s")
  sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$ISO' --es titleId $TITLE --es thorDebugBootRequestId $label --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null

  # wait for the fixed scene point
  local waited=0
  while ! sh "grep -v 'Performance Sensor' $LOG 2>/dev/null | tail -1" | grep -q "$CLOCK"; do
    waited=$((waited+5)); [ $waited -gt 420 ] && { echo "$label: never reached $CLOCK"; return 1; }
    sh "sleep 5" >/dev/null
  done

  local layer; layer=$(sh "dumpsys SurfaceFlinger --list | grep 'RPCSXActivity](BLAST)'" | head -1)
  [ -n "$layer" ] || { echo "$label: no BLAST layer"; return 1; }

  sh "dumpsys SurfaceFlinger --latency-clear '$layer'" >/dev/null
  sh "sleep $WINDOW" >/dev/null
  sh "dumpsys SurfaceFlinger --latency '$layer'" > "$OUT/$label.txt"

  local t1; t1=$(temp)
  # an external force-stop during the arm voids it
  local killed; killed=$(MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" logcat -d -t 400 2>/dev/null | grep -c "Force stopping $PKG.*from pid")
  echo "$label value=$value temp=${t0}->${t1} extkills=$killed"
}

for r in $(seq 1 "$ROUNDS"); do
  for v in 0 1; do arm "$v" "r${r}_dyn${v}"; done
done
echo "raw latency dumps in $OUT"
