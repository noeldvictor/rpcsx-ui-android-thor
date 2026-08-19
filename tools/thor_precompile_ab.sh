#!/usr/bin/env bash
# A/B a property against PPU precompile, which is the only heavy, reproducible,
# input-free workload on this device.
#
# Why this workload
# -----------------
# Folklore's title screen is 0.3-0.4 cores at a 60 fps cap, and gameplay cannot be
# reached over adb - three input paths were tried and the emulated pad sees none of
# them. Precompile needs no input, saturates several worker threads, and does
# EXACTLY the same work every run, because clearing the cache restores the same
# module set.
#
# The emulator timestamps its own compiles:
#
#   0:00:01.139445 {PPUW.1.3} PPU: LLVM: Compiling module ...obj
#   0:00:06.065596 {PPUW.1.3} PPU: LLVM: Compiled module  ...obj
#
# So the metric is the emulator's clock at the Nth "Compiled module", which is
# fixed work and is immune to how often this script polls.
#
# The cache lives under a drwxr-s--- tree that shell cannot unlink, so the clear
# runs through run-as, and the POSTCONDITION is checked - a file count of 0 - not
# the exit status of the rm. This repo has been burned by an rm that silently did
# nothing.
set -u

PROP="${1:?property}"
VAL_A="${2?value A}"
VAL_B="${3?value B}"
REPEATS="${4:-2}"
MODULES="${THOR_MODULES:-15}"

DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
TEMP_MAX_MC="${THOR_TEMP_MAX_MC:-60000}"

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
CACHE="/sdcard/Android/data/${PKG}/files/cache/cache/${TITLE}"
adb_sh() { adb -s "$DEVICE" shell "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
max_temp_mc() { adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r'; }

cool_down() {
  local t waited=0
  while :; do
    t=$(max_temp_mc); [ -n "$t" ] || return 0
    if [ "$t" -lt "$TEMP_MAX_MC" ] 2>/dev/null; then return 0; fi
    [ "$waited" -ge 1800 ] && return 1
    adb_sh "am force-stop $PKG" >/dev/null 2>&1; sleep 30; waited=$((waited+30))
  done
}

# Seconds from the emulator's own "H:MM:SS.uuuuuu" stamp.
run_arm() {
  local value="$1" label="$2"
  cool_down || { echo "  [$label] too hot" >&2; return 1; }

  adb_sh "am force-stop $PKG; setprop $PROP '$value'; rm -f $LOG" >/dev/null 2>&1
  sleep 2
  [ "$(adb_sh "getprop $PROP" | tr -d '\r')" = "$value" ] || die "property did not take"

  adb_sh "run-as $PKG sh -c 'rm -rf $CACHE'" >/dev/null 2>&1
  local left; left=$(adb_sh "run-as $PKG sh -c 'find $CACHE -type f 2>/dev/null | wc -l'" | tr -d '\r ')
  [ "${left:-1}" = "0" ] || die "cache not cleared: $left files remain"

  adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1

  local waited=0 n=0
  while [ "$waited" -lt 900 ]; do
    sleep 10; waited=$((waited+10))
    n=$(adb_sh "grep -ac 'LLVM: Compiled module' $LOG 2>/dev/null" | tr -d '\r')
    [ "${n:-0}" -ge "$MODULES" ] 2>/dev/null && break
  done
  [ "${n:-0}" -ge "$MODULES" ] 2>/dev/null || { echo "  [$label] only $n modules in ${waited}s" >&2; return 1; }

  # Timestamp of the Nth completion, from the emulator's clock.
  local stamp secs
  stamp=$(adb_sh "grep -a 'LLVM: Compiled module' $LOG | sed -n '${MODULES}p'" | tr -d '\r' | grep -oE '[0-9]+:[0-9]{2}:[0-9]{2}\.[0-9]+' | head -1)
  [ -n "$stamp" ] || { echo "  [$label] no timestamp" >&2; return 1; }
  secs=$(echo "$stamp" | awk -F: '{ printf "%.2f", $1*3600 + $2*60 + $3 }')
  echo "$secs $(max_temp_mc)"
}

echo "$PROP: A='$VAL_A' B='$VAL_B'  metric = emulator seconds to compile $MODULES PPU modules"
echo "Lower is faster. Fixed work: the cache is cleared before every arm."
echo
for i in $(seq 1 "$REPEATS"); do
  r=$(run_arm "$VAL_A" "A-$i") && echo "A[$i] ($VAL_A) t=$(echo $r|awk '{print $1}')s temp=$(echo $r|awk '{print $2}')"
  r=$(run_arm "$VAL_B" "B-$i") && echo "B[$i] ($VAL_B) t=$(echo $r|awk '{print $1}')s temp=$(echo $r|awk '{print $2}')"
done
adb_sh "am force-stop $PKG; setprop $PROP ''" >/dev/null 2>&1
echo
echo "Read the ranges."
