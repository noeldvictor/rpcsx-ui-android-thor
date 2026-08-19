#!/usr/bin/env bash
# Energy to compile a FIXED number of PPU modules, for a given ppu_budget_mb.
#
# "Modules compiled in a fixed 55 s window" is NOT a usable metric: module sizes
# vary widely, so the same setting returned 18 and then 10 across runs, and an
# energy-per-module figure derived from it is noise. Fixed WORK is the comparable
# unit - compile the same N modules and integrate power over however long that takes.
#
#   energy_J = mean_power_W * seconds_to_N_modules
#
# Reports both halves, because they move in opposite directions: more concurrency
# raises power and lowers time, and which wins is the whole question.
set -u
BUDGET="${1:-}"
N="${2:-15}"
DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG=net.rpcsx.easy
TITLE=BCUS98147
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
adb_sh() { adb -s "$DEVICE" shell "$@"; }

adb_sh "am force-stop $PKG; setprop debug.rpcsx.thor.ppu_budget_mb '$BUDGET'; rm -f $LOG; svc power stayon true" >/dev/null 2>&1
adb_sh "run-as $PKG sh -c 'rm -rf /sdcard/Android/data/$PKG/files/cache/cache/$TITLE'" >/dev/null 2>&1
# common thermal floor, or a hot arm throttles and both numbers move
while :; do
  t=$(adb_sh 'for z in /sys/class/thermal/thermal_zone*; do ty=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$ty" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r')
  [ "${t:-0}" -lt 52000 ] 2>/dev/null && break
  sleep 20
done

adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId en" >/dev/null 2>&1

# Sample power on-device until N modules are done, then report elapsed and mean.
adb_sh "
start=\$(date +%s); sum=0; n=0
while :; do
  m=\$(grep -ac 'LLVM: Compiled module' $LOG 2>/dev/null)
  [ \"\${m:-0}\" -ge $N ] && break
  [ \$(( \$(date +%s) - start )) -gt 400 ] && break
  v=\$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null)
  i=\$(cat /sys/class/power_supply/usb/current_now 2>/dev/null)
  [ -n \"\$v\" ] && [ -n \"\$i\" ] && { sum=\$(( sum + (v/1000)*(i/1000)/1000 )); n=\$((n+1)); }
  sleep 1
done
el=\$(( \$(date +%s) - start ))
[ \$n -gt 0 ] && echo \"budget=${BUDGET:-4096default}  seconds=\$el  mean_mW=\$((sum/n))  energy_J=\$(( (sum/n) * el / 1000 ))  modules=\$(grep -ac 'LLVM: Compiled module' $LOG)\"
" | tr -d '\r'
adb_sh "am force-stop $PKG; setprop debug.rpcsx.thor.ppu_budget_mb ''; svc power stayon false" >/dev/null 2>&1
