#!/usr/bin/env bash
# Energy proxy A/B, for when the battery gauge will not report.
#
# Why a proxy
# -----------
# On this device, with USB detached and status Discharging, current_now reads 0
# and voltage_now, charge_counter and power_now are all CONSTANT - over 60 s idle
# and over 120 s of rendering alike. A zero delta there is no reading, not a low
# one. The second screen is the only true wattage instrument and it needs a human.
#
# cpufreq residency does work, on all three clusters. Energy rises faster than
# linearly with frequency, so residency-weighted frequency is a defensible stand-in:
# the same work done at lower frequencies costs less energy. Reported per cluster,
# because this is a 1+2+2+3 big.LITTLE and a shift BETWEEN clusters matters as much
# as a shift between frequencies.
#
#   policy0  3x Cortex-A510    policy3  2x A715 + 2x A710    policy7  1x Cortex-X3
#
# Reported alongside frames and CPU ticks. Lower frequency at fewer frames is not a
# saving, it is the emulator failing to keep up.
#
# This is a PROXY. Do not convert its output into watts.
set -u

PROP="${1:?property}"
VAL_A="${2?value A}"
VAL_B="${3?value B}"
REPEATS="${4:-3}"

DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
WINDOW="${THOR_WINDOW:-60}"
FRAMES_MIN="${THOR_FRAMES_MIN:-6800}"
FRAMES_MAX="${THOR_FRAMES_MAX:-7600}"
TEMP_MAX_MC="${THOR_TEMP_MAX_MC:-60000}"

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
adb_sh() { adb -s "$DEVICE" shell "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
max_temp_mc() { adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r'; }

cool_down() {
  local t waited=0
  while :; do
    t=$(max_temp_mc); [ -n "$t" ] || return 0
    if [ "$t" -lt "$TEMP_MAX_MC" ] 2>/dev/null; then return 0; fi
    [ "$waited" -ge 1200 ] && return 1
    adb_sh "am force-stop $PKG" >/dev/null 2>&1; sleep 30; waited=$((waited+30))
  done
}

# Sum of (jiffies at f) * f over a policy, which is the residency-weighted work
# term. Printed per policy so a shift between clusters is visible.
snapshot() {
  adb_sh 'for p in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy3 /sys/devices/system/cpu/cpufreq/policy7; do
    awk "{ s += \$1 * \$2; t += \$2 } END { printf \"%.0f %.0f \", s, t }" $p/stats/time_in_state 2>/dev/null
  done; echo' | tr -d '\r'
}

run_arm() {
  local value="$1" label="$2" try=0
  while [ "$try" -lt 3 ]; do
    try=$((try+1))
    cool_down || { echo "  [$label] too hot" >&2; return 1; }
    adb_sh "am force-stop $PKG; setprop $PROP '$value'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG" >/dev/null 2>&1
    sleep 3
    [ "$(adb_sh "getprop $PROP" | tr -d '\r')" = "$value" ] || die "property did not take"
    adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1

    local waited=0 frames=0
    while [ "$waited" -lt 600 ]; do
      sleep 10; waited=$((waited+10))
      frames=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
      if [ -n "${frames:-}" ] && [ "${frames:-0}" -gt 3000 ] 2>/dev/null; then break; fi
    done
    [ "${frames:-0}" -gt 3000 ] 2>/dev/null || { echo "  [$label] no boot" >&2; continue; }

    local pid; pid=$(adb_sh "pidof $PKG" | tr -d '\r')
    local s1 f1 t1 s2 f2 t2
    s1=$(snapshot); t1=$(adb_sh "awk '{print \$14+\$15}' /proc/$pid/stat" | tr -d '\r')
    f1=$(adb_sh "grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
    sleep "$WINDOW"
    s2=$(snapshot); t2=$(adb_sh "awk '{print \$14+\$15}' /proc/$pid/stat" | tr -d '\r')
    f2=$(adb_sh "grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*'" | tr -d '\r')

    local fr=$((f2-f1)) ticks=$((t2-t1))
    if [ "$fr" -lt "$FRAMES_MIN" ] || [ "$fr" -gt "$FRAMES_MAX" ] 2>/dev/null; then
      echo "  [$label] rejected: frames=$fr" >&2; continue
    fi
    echo "$s1|$s2|$ticks|$fr|$(max_temp_mc)"
    return 0
  done
  return 1
}

report() {
  echo "$2" | awk -F'|' -v lab="$1" '{
    split($1,a," "); split($2,b," ");
    # a/b hold: p0_sum p0_time p3_sum p3_time p7_sum p7_time
    p0=(b[1]-a[1])/1e6; p3=(b[3]-a[3])/1e6; p7=(b[5]-a[5])/1e6;
    printf "%s  energy_proxy(GHz*jiffies/1e6): little=%.1f mid=%.1f prime=%.1f total=%.1f | ticks=%s frames=%s temp=%s\n",
      lab, p0, p3, p7, p0+p3+p7, $3, $4, $5 }'
}

echo "$PROP: A='$VAL_A' B='$VAL_B'  window=${WINDOW}s  repeats=$REPEATS"
echo "PROXY, not watts. The gauge on this device does not report."
echo
for i in $(seq 1 "$REPEATS"); do
  r=$(run_arm "$VAL_A" "A-$i") && report "A[$i] ($VAL_A)" "$r"
  r=$(run_arm "$VAL_B" "B-$i") && report "B[$i] ($VAL_B)" "$r"
done
adb_sh "am force-stop $PKG; setprop $PROP ''; setprop debug.rpcsx.thor.tex3d_reach ''" >/dev/null 2>&1
echo
echo "Read ranges. Lower proxy at FEWER frames is not a saving."
