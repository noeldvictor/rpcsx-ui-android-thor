#!/usr/bin/env bash
# Reproduce the Transformers SPU halt under Accurate SPU Reservations OFF.
#
# WHY COLD BOOT AND NOT THE COMBAT SAVESTATE. The recorded halt is at
# 0:00:37.42, thirty-seven seconds into a boot, followed by a dead RSX FIFO 1.3 s
# later. That is the logo and intro phase. Restoring the 3D combat savestate
# jumps over exactly the window in which the fault was seen, which is very
# likely why about 92 combat sessions produced nothing.
#
# WHY accurate=off. The profile comment for this title says it halts its own SPU
# with the setting off, which is why it was reverted on 2026-08-23. The shipped
# configuration is therefore the one in which the fault CANNOT be studied.
#
# NO BUTTON PRESSES. The run only boots and watches. It never presses anything,
# so nothing here depends on guessing what is on screen.
#
# The trap decoder now names the class of assert and prints the refused pointer,
# so one reproduction is enough to identify the check.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
RUNS=${RUNS:-6}
WATCH=${WATCH:-180}
COOL=${COOL:-50}

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
api(){ curl -s --max-time 6 "127.0.0.1:8099/$1" 2>/dev/null; }
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; P=$(sh_ "pidof $PKG"); [ -n "$P" ] && sh_ "kill -9 $P" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }

cleanup(){
  hardstop
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations ''; setprop debug.rpcsx.thor.spurs_always_notify ''; setprop debug.rpcsx.thor.thermal_abort_c ''; svc power stayon false" >/dev/null 2>&1
  echo "cleanup: temp=$(t_)C rpcsx_in_top=$(sh_ "top -b -n 2 -d 2 -o %CPU 2>/dev/null | grep -ci rpcsx")"
}
trap cleanup EXIT INT TERM

BATT=$(sh_ "cat /sys/class/power_supply/battery/capacity")
case "$BATT" in ''|*[!0-9]*) echo "ABORT: no battery read"; exit 1;; esac
[ "$BATT" -lt 20 ] && { echo "ABORT: battery ${BATT}%"; exit 1; }
echo "battery=${BATT}% temp=$(t_)C runs=$RUNS watch=${WATCH}s  accurate=OFF always_notify=${NOTIFY:-0} COLD BOOT"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null

hits=0
for i in $(seq 1 "$RUNS"); do
  hardstop
  T=$(t_); w=0
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 300 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

  sh_ "rm -f $R/cache/RPCSX.log" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations 0" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spurs_always_notify ${NOTIFY:-0}" >/dev/null
  sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId hr$i \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

  w=0; hit=0; lastf=-1; frozen=0
  while [ "$w" -lt "$WATCH" ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    TRAP=$(sh_ "grep -ac 'SPU trap' $R/cache/RPCSX.log")
    DEAD=$(sh_ "grep -ac 'ffdead' $R/cache/RPCSX.log")
    FIFO=$(sh_ "grep -ac 'Dead FIFO' $R/cache/RPCSX.log")
    # Liveness must come from the CUMULATIVE frame count, not from fps.
    #
    # This title is capped at 30, so a healthy run reports exactly 30.00
    # forever. An earlier version of this script treated an unchanging fps as a
    # freeze and declared a reproduction on a run that was working perfectly.
    # `frames` is guest flips since boot and only ever increases.
    F=$(api device | grep -oE '"frames":[0-9]+' | cut -d: -f2); F=${F:-0}
    FPS=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2); FPS=${FPS:-0}
    if [ "${TRAP:-0}" != "0" ] || [ "${DEAD:-0}" != "0" ] || [ "${FIFO:-0}" != "0" ]; then hit=1; break; fi
    if [ "$F" = "$lastf" ] && [ "$w" -gt 60 ]; then frozen=$((frozen+1)); else frozen=0; fi
    lastf=$F
    [ "$frozen" -ge 4 ] && { echo "run$i FROZEN: frame count stuck at $F for 60s (fps reads $FPS)"; hit=2; break; }
  done

  echo "run$i t=${w}s temp=$(t_)C frames=$lastf fps=${FPS:-?} trap=${TRAP:-0} dead=${DEAD:-0} fifo=${FIFO:-0}"
  if [ "$hit" != "0" ]; then
    hits=$((hits+1))
    echo "############ HALT OR FREEZE REPRODUCED, run $i ############"

    # Capture the live state BEFORE stopping anything. The freeze is a
    # live-lock: frames stop while the process still burns about 28% CPU and
    # the stale128 reservation counter drops from ~12600 per 10 s to 10. So the
    # question is which threads are spending that CPU, and /threads answers it
    # by sampling /proc jiffies twice and differencing.
    echo "---- /threads sample 1 ----"; api "threads" | head -c 3000; echo
    sh_ "sleep 3" >/dev/null
    echo "---- /threads sample 2 ----"; api "threads" | head -c 3000; echo
    echo "---- /diag ----";   api diag   | head -c 2000; echo
    echo "---- /status ----"; api status | head -c 1200; echo
    echo "---- top ----"
    sh_ "top -b -n 1 -H -o %CPU 2>/dev/null | head -22"

    sh_ "grep -a -A26 'SPU trap' $R/cache/RPCSX.log | head -70"
    sh_ "grep -a 'ALIGNMENT ASSERT\|SPU trap arg\|SPU trap decoded\|Dead FIFO' $R/cache/RPCSX.log | head -20"
    sh_ "cp $R/cache/RPCSX.log $R/cache/halt_repro_$i.log" >/dev/null
    echo "############ saved halt_repro_$i.log ############"
  fi
done
echo "=== $hits reproductions in $RUNS runs, accurate=off, cold boot ==="
