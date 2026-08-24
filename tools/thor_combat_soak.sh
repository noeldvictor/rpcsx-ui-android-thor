#!/usr/bin/env bash
# Soak the RESTORED 3D COMBAT scene. Never the intro.
#
# A cold-boot soak lands in the Activision and Hasbro logos and the FMV, where
# the SPU workload is Bink playback and nothing like combat. The frame count is
# the tell: intro-phase faults appear at a few hundred frames, while a healthy
# combat run passes about 4200. Any "reproduction" at frame 189 or 518 happened
# during the logos and says nothing about the 3D case.
#
# So every run here RESTORES the combat savestate and is GATED on coresBusy>4.5
# before a single number is counted. A run that fails the gate is reported
# INVALID, not quietly averaged in.
#
# Liveness comes from the cumulative `frames` counter. fps cannot be used: the
# title is capped at 30 and a healthy run reports exactly 30.00 for ever.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
RUNS=${RUNS:-6}
PLAY=${PLAY:-180}
COOL=${COOL:-50}
ACC=${ACC:-0}
HONOUR=${HONOUR:-0}

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

BATT=$(sh_ "cat /sys/class/power_supply/battery/capacity")
[ "${BATT:-0}" -lt 20 ] && { echo "ABORT: battery ${BATT}%"; exit 1; }
echo "battery=${BATT}% temp=$(t_)C runs=$RUNS play=${PLAY}s accurate=$ACC honour_maxrun=$HONOUR  RESTORED 3D COMBAT"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null

frozen_runs=0; valid=0
for i in $(seq 1 "$RUNS"); do
  hardstop
  T=$(t_); w=0
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 300 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

  sh_ "rm -f $R/cache/RPCSX.log" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spu_accurate_reservations $ACC" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spurs_wait_honour_maxrun $HONOUR" >/dev/null
  sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId cs$i \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

  rendered=0; w=0
  while [ "$w" -lt 200 ]; do
    sh_ "sleep 10" >/dev/null; w=$((w+10))
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
    case "${F:-0}" in ''|0|0.0*) ;; *) rendered=1; break;; esac
  done
  [ "$rendered" = "0" ] && { echo "run$i SKIP (never rendered)"; continue; }

  bash "$REPO/tools/thor_savestate_vault.sh" restore BLUS30357 >/dev/null 2>&1

  # THE GATE. Nothing counts until this passes.
  CORES=0; w=0
  while [ "$w" -lt 75 ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
    [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" = "1" ] && break
  done
  if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ]; then
    echo "run$i INVALID (gate failed, not in combat: cores=$CORES)"; continue
  fi
  valid=$((valid+1))

  # Watch for a freeze IN COMBAT.
  w=0; lastf=-1; stuck=0; froze=0
  while [ "$w" -lt "$PLAY" ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    F=$(api device | grep -oE '"frames":[0-9]+' | cut -d: -f2); F=${F:-0}
    if [ "$F" = "$lastf" ]; then stuck=$((stuck+1)); else stuck=0; fi
    lastf=$F
    [ "$stuck" -ge 4 ] && { froze=1; break; }
  done

  FPS=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
  SR=$(api diag | grep -o '"spursRunning":[0-9]*' | head -1 | cut -d: -f2)
  EW=$(api diag | grep -o '"enteredWait":true' | grep -c true)
  TRAP=$(sh_ "grep -ac 'SPU trap' $R/cache/RPCSX.log")
  DEAD=$(sh_ "grep -ac 'ffdead' $R/cache/RPCSX.log")

  if [ "$froze" = "1" ]; then
    frozen_runs=$((frozen_runs+1))
    echo "run$i COMBAT FROZE at frames=$lastf temp=$(t_)C spursRunning=${SR:-?} enteredWait=${EW:-?} trap=$TRAP dead=$DEAD"
    sh_ "cp $R/cache/RPCSX.log $R/cache/combat_freeze_$i.log" >/dev/null
  else
    echo "run$i ok  frames=$lastf fps=${FPS:-?} cores=$CORES temp=$(t_)C spursRunning=${SR:-?} enteredWait=${EW:-?} trap=$TRAP dead=$DEAD"
  fi
done
echo "=== $frozen_runs freezes in $valid VALID combat runs (accurate=$ACC honour_maxrun=$HONOUR) ==="
