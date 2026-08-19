#!/usr/bin/env bash
# Power A/B by steady-state temperature, because the battery gauge reports nothing.
#
# Why temperature and not the cpufreq proxy
# -----------------------------------------
# On this device current_now, voltage_now, charge_counter and power_now are all
# CONSTANT even with USB detached and status Discharging, so wattage is not
# readable. tools/thor_energy_proxy_ab.sh was written next and FAILED validation:
# a 2.4x change in CPU moved it 0.2%.
#
# Temperature does respond. Raising PPU compile concurrency moved the junction
# 6-7 C in a measured pair, so this sensor sees power where the others do not.
#
# The physics is the justification: at thermal equilibrium the junction rise over
# ambient is proportional to the power being dissipated. So for the SAME workload
# held long enough to settle, a lower steady-state temperature is lower power.
#
# The conditions that make it valid, all enforced below:
#   - identical workload in both arms, checked by frame count
#   - long enough to SETTLE - a 60 s window measures the ramp, not the plateau
#   - the same starting temperature, so one arm does not inherit the other's heat
#   - arms interleaved, because ambient drifts over a session
#
# It cannot produce watts. It can rank two arms, which is what a default needs.
set -u

PROP="${1:?property}"
VAL_A="${2?value A}"
VAL_B="${3?value B}"
REPEATS="${4:-2}"
SETTLE="${THOR_SETTLE:-300}"
SAMPLE="${THOR_SAMPLE:-60}"
START_MAX_MC="${THOR_START_MAX_MC:-50000}"

DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
adb_sh() { adb -s "$DEVICE" shell "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
temp_mc() { adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r'; }

# Both arms must start from the same thermal floor or the second inherits heat.
cool_to_floor() {
  local t waited=0
  adb_sh "am force-stop $PKG" >/dev/null 2>&1
  while :; do
    t=$(temp_mc)
    [ "${t:-0}" -lt "$START_MAX_MC" ] 2>/dev/null && { echo "$t"; return 0; }
    [ "$waited" -ge 2400 ] && { echo "$t"; return 1; }
    sleep 30; waited=$((waited+30))
  done
}

run_arm() {
  local value="$1" label="$2" floor
  floor=$(cool_to_floor) || { echo "  [$label] would not cool to ${START_MAX_MC}, got $floor" >&2; return 1; }

  adb_sh "setprop $PROP '$value'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG" >/dev/null 2>&1
  sleep 2
  [ "$(adb_sh "getprop $PROP" | tr -d '\r')" = "$value" ] || die "property did not take"
  adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1

  local waited=0 frames=0
  while [ "$waited" -lt 600 ]; do
    sleep 10; waited=$((waited+10))
    frames=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
    [ "${frames:-0}" -gt 3000 ] 2>/dev/null && break
  done
  [ "${frames:-0}" -gt 3000 ] 2>/dev/null || { echo "  [$label] no boot" >&2; return 1; }

  sleep "$SETTLE"   # reach the plateau, not the ramp

  local pid f1 f2 t sum=0 n=0
  pid=$(adb_sh "pidof $PKG" | tr -d '\r')
  f1=$(adb_sh "grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
  local i=0
  while [ "$i" -lt 6 ]; do
    t=$(temp_mc); sum=$((sum + t)); n=$((n+1)); i=$((i+1)); sleep $((SAMPLE/6))
  done
  f2=$(adb_sh "grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*'" | tr -d '\r')

  echo "$((sum/n)) $((f2-f1)) $floor"
}

echo "$PROP: A='$VAL_A' B='$VAL_B'   settle=${SETTLE}s, then ${SAMPLE}s of sampling"
echo "Steady-state junction temperature. Lower = less power, IF the frame count matches."
echo
for i in $(seq 1 "$REPEATS"); do
  r=$(run_arm "$VAL_A" "A-$i") && echo "A[$i] ($VAL_A) steady=$(echo $r|awk '{print $1}') mC  frames=$(echo $r|awk '{print $2}')  from=$(echo $r|awk '{print $3}') mC"
  r=$(run_arm "$VAL_B" "B-$i") && echo "B[$i] ($VAL_B) steady=$(echo $r|awk '{print $1}') mC  frames=$(echo $r|awk '{print $2}')  from=$(echo $r|awk '{print $3}') mC"
done
adb_sh "am force-stop $PKG; setprop $PROP ''; setprop debug.rpcsx.thor.tex3d_reach ''" >/dev/null 2>&1
echo
echo "A lower temperature at FEWER frames is not a power saving."
