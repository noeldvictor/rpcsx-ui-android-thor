#!/usr/bin/env bash
# A/B one property while the CPU is deliberately scarce.
#
# A frame-capped scene cannot show a latency cost: both arms sit at 29.67 and only
# CPU moves. Parking trades CPU for wake latency, so the capped scene flatters it.
# Taking the cores away uncaps the frame rate and lets latency show as frames.
#
# Spinners are killed from the HOST on every exit path. This repo has already had
# twelve orphaned `yes` processes run for hours at ~430% CPU after a dropped link,
# which contaminated a whole session.
set -uo pipefail
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
R=/storage/emulated/0/Android/data/net.rpcsx.easy/files
ISO="/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso"
SP="/c/Users/LEANER~1/AppData/Local/Temp/claude/C--Users-leanerdesigner-Documents-ps3-thor/a465ad58-bbf5-40bb-8b42-e185135b6729/scratchpad"
PROP=$1; A=$2; B=$3; SPINNERS=${4:-6}
sh() { MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$@" 2>/dev/null | tr -d '\r'; }
cleanup() { sh "killall yes 2>/dev/null; setprop $PROP ''" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
cleanup   # sweep any survivor from a previous run

arm() {
  local v=$1 label=$2
  sh "am force-stop net.rpcsx.easy; killall yes 2>/dev/null; setprop $PROP $v; rm -f $R/cache/RPCSX.log" >/dev/null
  [ "$(sh "getprop $PROP")" = "$v" ] || { echo "$label: prop did not take"; return 1; }
  sh "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity --es path '$ISO' --es titleId BLUS30161 --es thorDebugBootRequestId $label --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile false" >/dev/null
  local w=0
  while ! sh "grep -c '0:02:' $R/cache/RPCSX.log 2>/dev/null" | grep -qv '^0$'; do
    sh "sleep 5" >/dev/null; w=$((w+5)); [ $w -gt 400 ] && { echo "$label: no 0:02:"; return 1; }
  done
  # take the cores away, identically in both arms
  for i in $(seq 1 "$SPINNERS"); do sh "nohup yes >/dev/null 2>&1 &" >/dev/null; done
  sh "sleep 8" >/dev/null
  local spin; spin=$(sh "pgrep -c yes")
  local L; L=$(sh "dumpsys SurfaceFlinger --list | grep 'RPCSXActivity](BLAST)'" | head -1)
  sh "dumpsys SurfaceFlinger --latency-clear '$L'" >/dev/null
  sh "sleep 15; dumpsys SurfaceFlinger --latency '$L'" > "$SP/starve_$label.txt"
  sh "killall yes 2>/dev/null" >/dev/null
  echo "$label $PROP=$v spinners=$spin"
}
arm "$A" a1; arm "$B" b1; arm "$A" a2; arm "$B" b2
