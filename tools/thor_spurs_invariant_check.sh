#!/usr/bin/env bash
# Test the limiter fix on its INVARIANT, not on the rare freeze it causes.
#
# WHY NOT SOAK FOR FREEZES. The combat freeze rate is about 1 in 6 runs, so
# separating 1-in-6 from 0-in-6 needs dozens of boots. The fix makes a much
# sharper claim that can be checked continuously.
#
# THE CLAIM. spurs_entered_wait is sticky: it is set when a thread goes
# not-idle -> idle and cleared only on the reverse transition. While set, the
# thread re-enters the limiter wait WITHOUT re-testing `max_run < max_num`, the
# condition the entry path itself applies. So threads sit in enteredWait while
# max_run == max_num == 6, which means the limiter is throttling nobody and they
# are asleep for no reason it can state. That is the state the freeze was caught
# in: spursRunning=4, enteredWait=5, maxRun=6, maxNum=6.
#
# debug.rpcsx.thor.spurs_wait_honour_maxrun=1 makes re-entry honour the same
# condition as entry. If it works, enteredWait must be 0 whenever
# maxRun >= maxNum - continuously, on every sample, not just when a freeze
# happens to occur.
#
# 3D COMBAT ONLY. Restores the savestate and gates on coresBusy>4.5.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
RUNS=${RUNS:-2}
PLAY=${PLAY:-120}
HONOUR=${HONOUR:-0}
COOL=${COOL:-52}

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
api(){ curl -s --max-time 8 "127.0.0.1:8099/$1" 2>/dev/null; }
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; P=$(sh_ "pidof $PKG"); [ -n "$P" ] && sh_ "kill -9 $P" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }

cleanup(){
  hardstop
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations ''; setprop debug.rpcsx.thor.spurs_wait_honour_maxrun ''; setprop debug.rpcsx.thor.thermal_abort_c ''; svc power stayon false" >/dev/null 2>&1
  echo "cleanup: temp=$(t_)C"
}
trap cleanup EXIT INT TERM

echo "battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")% temp=$(t_)C honour_maxrun=$HONOUR runs=$RUNS play=${PLAY}s"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null

for i in $(seq 1 "$RUNS"); do
  hardstop
  T=$(t_); w=0
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 300 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

  sh_ "rm -f $R/cache/RPCSX.log" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations 0" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spurs_wait_honour_maxrun $HONOUR" >/dev/null
  sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId iv$i \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

  # 300 s, not 200. After a GPU driver switch the Vulkan pipeline cache is
  # invalid and the next boot recompiles every shader, which took longer than
  # 200 s here and was misreported as "never rendered" on a run that was fine.
  rendered=0; w=0
  while [ "$w" -lt 300 ]; do
    sh_ "sleep 10" >/dev/null; w=$((w+10))
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
    case "${F:-0}" in ''|0|0.0*) ;; *) rendered=1; break;; esac
  done
  [ "$rendered" = "0" ] && { echo "run$i SKIP (never rendered)"; continue; }

  bash "$REPO/tools/thor_savestate_vault.sh" restore BLUS30357 >/dev/null 2>&1

  CORES=0; w=0
  while [ "$w" -lt 75 ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
    [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" = "1" ] && break
  done
  if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ]; then
    echo "run$i INVALID (gate failed: cores=$CORES)"; continue
  fi

  # Sample the invariant continuously.
  samples=0; violations=0; maxew=0; maxsr=0
  el=0
  while [ "$el" -lt "$PLAY" ]; do
    sh_ "sleep 5" >/dev/null; el=$((el+5))
    D=$(api diag)
    [ -z "$D" ] && continue
    EW=$(printf '%s' "$D" | grep -o '"enteredWait":true' | grep -c true)
    SR=$(printf '%s' "$D" | grep -o '"spursRunning":[0-9]*' | head -1 | cut -d: -f2)
    MR=$(printf '%s' "$D" | grep -o '"maxRun":[0-9]*' | head -1 | cut -d: -f2)
    MN=$(printf '%s' "$D" | grep -o '"maxNum":[0-9]*' | head -1 | cut -d: -f2)
    samples=$((samples+1))
    [ "${EW:-0}" -gt "$maxew" ] && maxew=$EW
    [ "${SR:-0}" -gt "$maxsr" ] && maxsr=$SR
    # A violation is a thread waiting while the limiter throttles nobody.
    if [ "${MR:-0}" -ge "${MN:-99}" ] && [ "${EW:-0}" -gt 0 ]; then
      violations=$((violations+1))
    fi
  done

  FPS=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
  echo "run$i honour=$HONOUR samples=$samples VIOLATIONS=$violations maxEnteredWait=$maxew maxSpursRunning=$maxsr fps=${FPS:-?} temp=$(t_)C"
done
echo "=== honour_maxrun=$HONOUR done ==="
