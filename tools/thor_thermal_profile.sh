#!/usr/bin/env bash
# Track CPU junction temperature through a whole boot: precompile, then sustained run.
#
# The target this exists to check is a USER requirement, not a guess: junction should
# stay under 70 C long term. Compile concurrency is the one thing on this device that
# converts straight into heat, so the PPU precompile stage and the steady-state run
# have to be looked at separately - one is a burst, the other is what "long term" means.
#
# Reports temperature beside frames, because a cool device that renders nothing is not
# a result.
set -u

BUDGET="${1:-}"          # value for debug.rpcsx.thor.ppu_budget_mb, empty = shipped default
MINUTES="${2:-8}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG=net.rpcsx.easy

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
CACHE="/sdcard/Android/data/${PKG}/files/cache/cache/${TITLE}"
adb_sh() { adb -s "$DEVICE" shell "$@"; }
temp() { adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r'; }

adb_sh "am force-stop $PKG; setprop debug.rpcsx.thor.ppu_budget_mb '$BUDGET'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG; svc power stayon true" >/dev/null 2>&1
adb_sh "run-as $PKG sh -c 'rm -rf $CACHE'" >/dev/null 2>&1

# Start from a common floor so one run does not inherit the previous run's heat.
while :; do t=$(temp); [ "${t:-0}" -lt 45000 ] 2>/dev/null && break; sleep 30; done
echo "budget='${BUDGET:-default}'  starting at $(temp) mC"
echo "min:sec  temp_mC  frames  phase"

adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId thermal" >/dev/null 2>&1

END=$((MINUTES * 4))   # 15 s ticks
i=0
while [ "$i" -lt "$END" ]; do
  sleep 15; i=$((i + 1))
  t=$(temp)
  f=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
  n=$(adb_sh "grep -ac 'LLVM: Compiled module' $LOG 2>/dev/null" | tr -d '\r')
  alive=$(adb_sh "pidof $PKG" | tr -d '\r')
  [ -z "$alive" ] && { echo "  process gone at $((i*15))s"; break; }
  phase="compiling($n)"
  [ "${f:-0}" -gt 0 ] 2>/dev/null && phase="rendering"
  printf "%d:%02d  %s  %s  %s\n" $((i*15/60)) $((i*15%60)) "$t" "${f:-0}" "$phase"
done

adb_sh "am force-stop $PKG; setprop debug.rpcsx.thor.ppu_budget_mb ''; setprop debug.rpcsx.thor.tex3d_reach ''; svc power stayon false" >/dev/null 2>&1
