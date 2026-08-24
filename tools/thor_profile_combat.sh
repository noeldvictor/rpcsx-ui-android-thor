#!/usr/bin/env bash
# Profile the 3D COMBAT scene to find the missing 12 frames.
#
# The scene runs 18 to 19 FPS against its own 30 FPS cap with about 5 cores
# busy, so it is CPU bound and the frames are lost inside the emulator. This
# says WHERE.
#
# simpleperf must go through run-as: perf_event_paranoid is 1, so `-p <pid>`
# from the shell fails with Permission denied. AGENTS.md records this.
#
# Symbols: librpcsx-android.so on the device is stripped, so simpleperf reports
# raw offsets. Those are resolved afterwards against the UNSTRIPPED library in
# the build tree, which is why the offsets are printed rather than discarded.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
DUR=${DUR:-25}
COOL=${COOL:-50}

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
api(){ curl -s --max-time 8 "127.0.0.1:8099/$1" 2>/dev/null; }
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; P=$(sh_ "pidof $PKG"); [ -n "$P" ] && sh_ "kill -9 $P" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }
cleanup(){ hardstop; sh_ "svc power stayon false; setprop debug.rpcsx.thor.thermal_abort_c ''" >/dev/null 2>&1; echo "cleanup temp=$(t_)C"; }
trap cleanup EXIT INT TERM

echo "battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")% temp=$(t_)C"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null
hardstop
T=$(t_); w=0
while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 300 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

sh_ "rm -f $R/cache/RPCSX.log; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
     --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId prof \
     --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

w=0
while [ "$w" -lt 300 ]; do
  sh_ "sleep 10" >/dev/null; w=$((w+10))
  F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
  case "${F:-0}" in ''|0|0.0*) ;; *) break;; esac
done

bash "$REPO/tools/thor_savestate_vault.sh" restore BLUS30357 >/dev/null 2>&1

CORES=0; w=0
while [ "$w" -lt 90 ]; do
  sh_ "sleep 15" >/dev/null; w=$((w+15))
  CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
  [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" = "1" ] && break
done
if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ]; then
  echo "ABORT: gate failed, not in combat (cores=$CORES). Nothing profiled."; exit 1
fi
echo "in combat: cores=$CORES fps=$(api device | grep -oE '\"fps\":[0-9.]+' | cut -d: -f2) temp=$(t_)C"

PID=$(sh_ "pidof $PKG")
echo "profiling pid=$PID for ${DUR}s"
sh_ "run-as $PKG /system/bin/simpleperf record -p $PID -g -f 1000 --duration $DUR -o /data/data/$PKG/combat.data" 2>&1 | tail -2

echo
echo "===== BY SYMBOL ====="
sh_ "run-as $PKG /system/bin/simpleperf report -i /data/data/$PKG/combat.data --sort symbol -n 2>/dev/null | head -40"
echo
echo "===== BY DSO ====="
sh_ "run-as $PKG /system/bin/simpleperf report -i /data/data/$PKG/combat.data --sort dso -n 2>/dev/null | head -14"
echo
echo "===== BY THREAD ====="
sh_ "run-as $PKG /system/bin/simpleperf report -i /data/data/$PKG/combat.data --sort thread -n 2>/dev/null | head -16"
echo
echo "final: fps=$(api device | grep -oE '\"fps\":[0-9.]+' | cut -d: -f2) cores=$(api device | grep -oE '\"coresBusy\":[0-9.]+' | cut -d: -f2) temp=$(t_)C"
