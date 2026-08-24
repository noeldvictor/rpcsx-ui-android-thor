#!/usr/bin/env bash
# Measure the SPURS TEAR, not the halt.
#
# WHY NOT THE HALT. About 92 controlled sessions produced no reproduction, so an
# arm that counts halts returns zero everywhere and says nothing. The tear that
# is believed to cause the halt is countable at a far higher rate.
#
# WHAT EACH ARM MEANS
#   control : shipped profile. How often a plain GET overlaps a line that is
#             being written with no exclusion.
#   narrow  : spurs_store_exclusive=1. writer_lock now excludes the range lock
#             that the DMA takes, so the count should fall to zero.
#   wide    : Accurate SPU Reservations true. Closes the same hole and several
#             others, so it bounds the narrow arm.
#
# NO BUTTON PRESSES. The savestate restores 3D combat directly.
# THERMAL. Combat is 92 to 95 C. Cool before every run, abort armed.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
PLAY=${PLAY:-90}
COOL=${COOL:-52}

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
api(){ curl -s --max-time 6 "127.0.0.1:8099/$1" 2>/dev/null; }
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; P=$(sh_ "pidof $PKG"); [ -n "$P" ] && sh_ "kill -9 $P" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }

cleanup(){
  hardstop
  sh_ "setprop debug.rpcsx.thor.spurs_tear_probe ''; setprop debug.rpcsx.thor.spurs_store_exclusive ''; setprop debug.rpcsx.thor.spu_accurate_reservations ''; setprop debug.rpcsx.thor.thermal_abort_c ''; svc power stayon false" >/dev/null 2>&1
  echo "cleanup: temp=$(t_)C rpcsx_in_top=$(sh_ "top -b -n 2 -d 2 -o %CPU 2>/dev/null | grep -ci rpcsx")"
}
trap cleanup EXIT INT TERM

BATT=$(sh_ "cat /sys/class/power_supply/battery/capacity")
case "$BATT" in ''|*[!0-9]*) echo "ABORT: no battery read"; exit 1;; esac
[ "$BATT" -lt 25 ] && { echo "ABORT: battery ${BATT}%"; exit 1; }
echo "battery=${BATT}% temp=$(t_)C play=${PLAY}s per arm"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null

run_arm(){
  NAME=$1; EXCL=$2; ACC=$3
  hardstop
  T=$(t_); w=0
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 300 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

  sh_ "rm -f $R/cache/RPCSX.log" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spurs_tear_probe 1" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spurs_store_exclusive $EXCL" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations $ACC" >/dev/null
  sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null

  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId tear$NAME \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

  rendered=0; w=0
  while [ "$w" -lt 200 ]; do
    sh_ "sleep 10" >/dev/null; w=$((w+10))
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
    case "${F:-0}" in ''|0|0.0*) ;; *) rendered=1; break;; esac
  done
  [ "$rendered" = "0" ] && { echo "arm=$NAME SKIP (never rendered) temp=$(t_)C"; return; }

  bash "$REPO/tools/thor_savestate_vault.sh" restore BLUS30357 >/dev/null 2>&1
  sh_ "sleep 25" >/dev/null

  CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
  FPS0=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2); FPS0=${FPS0:-0}
  if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ]; then
    echo "arm=$NAME INVALID (not combat: cores=$CORES fps=$FPS0) temp=$(t_)C"; return
  fi

  sh_ "sleep $PLAY" >/dev/null

  FPS1=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2); FPS1=${FPS1:-0}
  C1=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); C1=${C1:-0}

  # The one way this experiment can lie: the narrow arm deadlocks on the new
  # writer_lock and a stalled title looks like a fixed one.
  STALL=no
  case "$FPS1" in ''|0|0.0*) STALL=YES;; esac

  ALIVE=$(sh_ "grep -a 'tear probe alive' $R/cache/RPCSX.log | tail -1")
  HIT=$(sh_ "grep -a 'SPURS tear probe:' $R/cache/RPCSX.log | tail -1")
  TRAP=$(sh_ "grep -ac 'SPU trap' $R/cache/RPCSX.log")
  DEAD=$(sh_ "grep -ac 'ffdead' $R/cache/RPCSX.log")

  echo "arm=$NAME excl=$EXCL acc=$ACC temp=$(t_)C fps=$FPS1 cores=$C1 stall=$STALL trap=$TRAP dead=$DEAD"
  echo "    alive: ${ALIVE:-NONE - probe never logged a heartbeat}"
  echo "    hits : ${HIT:-none}"
  if [ "${TRAP:-0}" != "0" ] || [ "${DEAD:-0}" != "0" ]; then
    echo "    ################ HALT REPRODUCED in arm $NAME ################"
    sh_ "grep -a -A22 'SPU trap' $R/cache/RPCSX.log | tail -50"
    sh_ "cp $R/cache/RPCSX.log $R/cache/tear_${NAME}_fault.log" >/dev/null
  fi
}

run_arm control 0 ''
run_arm narrow  1 ''
run_arm wide    0 1
echo "=== done ==="
