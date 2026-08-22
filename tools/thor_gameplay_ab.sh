#!/usr/bin/env bash
# A/B one property on a SAVESTATE, so both arms see the same frame.
#
# Why a savestate and not a boot: this fork has never measured a gameplay lever,
# and the reason is in its own notes. A title screen resolves nothing. The Eternal
# Sonata opening is a cutscene which moves, so two boots sample different scenes:
# on 2026-08-22 the same build measured 29.65 FPS at emulator clock 3:19 and 3.4
# FPS at 4:50, and three consistent samples of the wrong scene looked exactly like
# a reproducible regression. A savestate restores the same frame every time.
#
# Make one with the pad: SELECT + right stick DOWN (RPCSXActivity.kt). Injected
# input does not reach the guest on this device, so a person has to do it once.
#
# Usage:
#   tools/thor_gameplay_ab.sh debug.rpcsx.thor.spu_selfloop_park 0 100 3
set -uo pipefail

PROP=${1:?property}
A=${2:?value A}
B=${3:?value B}
ROUNDS=${4:-3}

DEVICE=${THOR_SERIAL:-c3ca0370}
ADB=${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}
PKG=net.rpcsx.easy
TITLE=${TITLE:-BLUS30161}
ROOT=/storage/emulated/0/Android/data/$PKG/files
LOG=$ROOT/cache/RPCSX.log
WINDOW=${WINDOW:-15}
SETTLE=${SETTLE:-20}
OUT=${OUT:-/c/Users/LEANER~1/AppData/Local/Temp/thor_gp}

mkdir -p "$OUT"
sh() { MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" shell "$@" 2>/dev/null | tr -d '\r'; }

# Always hand the device back in its default state, on every exit path.
restore() { sh "setprop $PROP ''" >/dev/null 2>&1 || true; }
trap restore EXIT INT TERM

sh "ls $ROOT/savestates/$TITLE" | grep -q . || {
  echo "No savestate for $TITLE." >&2
  echo "Load your save, reach the scene, then press SELECT + right stick DOWN." >&2
  exit 1
}

arm() {
  local value=$1 label=$2

  sh "am force-stop $PKG; setprop $PROP '$value'; rm -f $LOG" >/dev/null
  local got; got=$(sh "getprop $PROP")
  [ "$got" = "$value" ] || { echo "$label: property did not take (wanted '$value', read '$got')"; return 1; }

  local t0; t0=$(sh "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1")
  sh "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh "am start -a net.rpcsx.THOR_RESUME_SAVESTATE -n $PKG/net.rpcsx.MainActivity --es titleId $TITLE" >/dev/null

  # Wait for frames, not for a clock. A clock does not pin a scene; a savestate does.
  local waited=0
  while [ "$(sh "pidof $PKG")" = "" ] || [ "$(sh "dumpsys SurfaceFlinger --list | grep -c 'RPCSXActivity](BLAST)'")" = "0" ]; do
    sh "sleep 5" >/dev/null; waited=$((waited+5))
    [ $waited -gt 300 ] && { echo "$label: never presented a surface"; return 1; }
  done
  sh "sleep $SETTLE" >/dev/null

  local layer; layer=$(sh "dumpsys SurfaceFlinger --list | grep 'RPCSXActivity](BLAST)'" | head -1)
  sh "dumpsys SurfaceFlinger --latency-clear '$layer'" >/dev/null

  local p; p=$(sh "pidof $PKG")
  local c0; c0=$(sh "awk '{print \$14+\$15}' /proc/$p/stat")
  sh "sleep $WINDOW" >/dev/null
  local c1; c1=$(sh "awk '{print \$14+\$15}' /proc/$p/stat")
  sh "dumpsys SurfaceFlinger --latency '$layer'" > "$OUT/$label.txt"

  local t1; t1=$(sh "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1")
  # An external force-stop voids the arm: it is indistinguishable from a crash.
  local killed; killed=$(MSYS_NO_PATHCONV=1 "$ADB" -s "$DEVICE" logcat -d -t 400 2>/dev/null | grep -c "Force stopping $PKG.*from pid")

  echo "$label $PROP=$value cpu_s=$(( (c1-c0)/100 )) temp=${t0}->${t1} extkills=$killed"
}

for r in $(seq 1 "$ROUNDS"); do
  arm "$A" "r${r}_a"
  arm "$B" "r${r}_b"
done
echo "latency dumps in $OUT -- compare medians, and reject any arm with extkills>0"
