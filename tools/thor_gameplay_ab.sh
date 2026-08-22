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
# The savestate is made over adb, by this script. No pad, no hands.
#
# ThorDebugSaveStateReceiver already exists and is exported in debug builds, where
# THOR_DEBUG_TOOLS is true. It is a BROADCAST on purpose: an activity intent would
# bring MainActivity forward and push the emulator out of the foreground, which
# changes the very workload being captured.
#
# It was asked for by hand for hours before anyone looked for it. Look first.
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

SAVEDIR=$ROOT/config/savestates/$TITLE

# Capture one now, from whatever is running, unless the caller already has one.
if ! sh "ls $SAVEDIR" | grep -q .; then
  [ -n "$(sh "pidof $PKG")" ] || {
    echo "Nothing is running, so there is no scene to capture." >&2
    echo "Boot the title to the scene you want measured, then re-run." >&2
    exit 1
  }
  echo "No savestate for $TITLE. Capturing the running scene."
  sh "am broadcast -a net.rpcsx.THOR_DEBUG_SAVESTATE -n $PKG/net.rpcsx.utils.ThorDebugSaveStateReceiver --es thorSaveStateRequestId abcapture" >/dev/null
  waited=0
  while ! sh "ls $SAVEDIR" | grep -q .; do
    sh "sleep 3" >/dev/null; waited=$((waited+3))
    [ $waited -gt 90 ] && { echo "savestate never appeared in $SAVEDIR" >&2; exit 1; }
  done
fi

STATE=$(sh "ls -t $SAVEDIR | head -1")
echo "using savestate: $STATE"

arm() {
  local value=$1 label=$2

  sh "am force-stop $PKG; setprop $PROP '$value'; rm -f $LOG" >/dev/null
  local got; got=$(sh "getprop $PROP")
  [ "$got" = "$value" ] || { echo "$label: property did not take (wanted '$value', read '$got')"; return 1; }

  local t0; t0=$(sh "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1")
  sh "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  # THOR_DEBUG_BOOT takes any absolute path, and a savestate is bootable like a disc.
  # The title must already be in games.yml, which booting the disc once achieves.
  sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$SAVEDIR/$STATE' --es titleId $TITLE --es thorDebugBootRequestId $label --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile false" >/dev/null

  # Wait for frames, not for a clock. A clock does not pin a scene; a savestate does.
  waited=0
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
