#!/usr/bin/env bash
# A/B a property on Eternal Sonata's opening, measuring POWER, CPU and frames.
#
# Why this title and this scene: it is the heaviest workload reachable without a
# controller - the opening plays unattended - and gameplay cannot be driven over adb.
# It is also where the gameplay levers actually have reach: spu_selfloop_park reads
# entries=0 on Folklore's title screen and 9904 here, at pc=0x00cc4, which is the hot
# state-poll loop this repo already identified.
#
# The scene varies a lot - 5.33, 8.91 and 7.37 W across three samples of one setting,
# and 1.1 to 5.2 cores in an earlier run - so arms MUST be interleaved and ranges read
# rather than means. Power comes from the charger input (see thor_power_iin.sh).
set -u
PROP="${1:?property}"; VAL_A="${2?}"; VAL_B="${3?}"; REPEATS="${4:-3}"
DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG=net.rpcsx.easy
GAME='/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso'
export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
adb_sh() { adb -s "$DEVICE" shell "$@"; }

arm() {
  local v="$1" label="$2"
  adb_sh "am force-stop $PKG; setprop $PROP '$v'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG; svc power stayon true" >/dev/null 2>&1
  sleep 2
  [ "$(adb_sh "getprop $PROP" | tr -d '\r')" = "$v" ] || { echo "  property did not take" >&2; return 1; }
  # common thermal floor
  while :; do t=$(adb_sh 'for z in /sys/class/thermal/thermal_zone*; do ty=$(cat $z/type 2>/dev/null); vv=$(cat $z/temp 2>/dev/null); case "$ty" in cpu-1-*) echo "$vv";; esac; done | sort -rn | head -1' | tr -d '\r'); [ "${t:-0}" -lt 55000 ] 2>/dev/null && break; sleep 20; done
  adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId BLUS30161 --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1
  local w=0 f=0
  while [ $w -lt 400 ]; do
    sleep 15; w=$((w+15))
    f=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
    [ "${f:-0}" -gt 900 ] 2>/dev/null && break
  done
  [ "${f:-0}" -gt 900 ] 2>/dev/null || { echo "  [$label] never rendered" >&2; return 1; }
  sleep 20   # let the scene settle past the boot transient
  local pid; pid=$(adb_sh "pidof $PKG" | tr -d '\r')
  adb_sh "
    s=0; n=0; f1=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
    c1=\$(awk '{print \$14+\$15}' /proc/$pid/stat)
    e=\$(( \$(date +%s) + 60 ))
    while [ \$(date +%s) -lt \$e ]; do
      v=\$(cat /sys/class/power_supply/usb/voltage_now); i=\$(cat /sys/class/power_supply/usb/current_now)
      [ -n \"\$v\" ] && [ -n \"\$i\" ] && { s=\$(( s + (v/1000)*(i/1000)/1000 )); n=\$((n+1)); }
      sleep 1
    done
    c2=\$(awk '{print \$14+\$15}' /proc/$pid/stat); f2=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
    p=\$(grep -o 'entries=[0-9]*' $LOG | tail -1)
    echo \"mW=\$((s/n)) cpu=\$((c2-c1)) frames=\$((f2-f1)) \$p\"
  " | tr -d '\r'
}

echo "$PROP on Eternal Sonata: A='$VAL_A' B='$VAL_B', $REPEATS interleaved repeats"
echo "Read RANGES - this scene spans 5.3 to 8.9 W for one setting."
echo
for i in $(seq 1 "$REPEATS"); do
  r=$(arm "$VAL_A" "A$i") && echo "A[$i] ($VAL_A) $r"
  r=$(arm "$VAL_B" "B$i") && echo "B[$i] ($VAL_B) $r"
done
adb_sh "am force-stop $PKG; setprop $PROP ''; setprop debug.rpcsx.thor.tex3d_reach ''; svc power stayon false" >/dev/null 2>&1
