#!/usr/bin/env bash
# Per-thread A/B of one debug.rpcsx.thor.* property, on a booted title.
#
# Why this exists next to thor_phase_gated_ab.sh
# ----------------------------------------------
# The phase-gated runner measures WHOLE-PROCESS CPU. That is the right instrument
# for a change that touches every thread, and the wrong one for a change that
# touches exactly one. Folklore's title screen costs about 1800-2100 ticks per
# 60 s window, and rsx::thread is about 250-320 of them. A change confined to
# rsx::thread can move its own thread by half and move the process total by 8%,
# which is inside the +-50 tick scatter that got two claims retracted here.
#
# So: name the thread the change lives in, and measure that thread.
#
# THREAD is a PREFIX. 'rsx::thread' selects one thread; 'SPU[' selects every SPU
# thread, which is what a change to the SPU recompiler actually touches. Ticks are
# summed over the matching set, and the set size is reported so a boot with a
# different thread count cannot be compared silently.
#
# Frames come from the tex3d_reach probe, which prints "over N frames" through
# rsx_log.error() - the channel this device actually flushes. rsx_log.always()
# does not reach logcat; that cost a build and a boot on 2026-08-17.
#
# A CPU number alone cannot tell a thread that stopped spinning from an emulator
# that stopped working, so an arm is rejected unless its frame count lands in the
# band. That pins the scene too: a title screen has phases.
#
# Usage:
#   tools/thor_thread_ab.sh PROPERTY VALUE_A VALUE_B THREAD_PREFIX [REPEATS]
#   tools/thor_thread_ab.sh debug.rpcsx.thor.rsx_fifo_park 0 1 rsx::thread 3
#   tools/thor_thread_ab.sh debug.rpcsx.thor.spu_selfloop_park 0 200 'SPU[' 3
set -u

PROP="${1:?property name}"
VAL_A="${2?value for arm A}"
VAL_B="${3?value for arm B}"
THREAD="${4:?thread name prefix as it appears in /proc/<pid>/task/*/comm}"
REPEATS="${5:-3}"

DEVICE="${THOR_SERIAL:-c3ca0370}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
WINDOW="${THOR_WINDOW:-60}"
FRAMES_MIN="${THOR_FRAMES_MIN:-6800}"
FRAMES_MAX="${THOR_FRAMES_MAX:-7600}"
BOOT_TIMEOUT="${THOR_BOOT_TIMEOUT:-600}"
MAX_TRIES="${THOR_MAX_TRIES:-3}"
TEMP_MAX_MC="${THOR_TEMP_MAX_MC:-62000}"
COOL_TIMEOUT="${THOR_COOL_TIMEOUT:-900}"

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"

adb_sh() { adb -s "$DEVICE" shell "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
reachable() { [ "$(adb_sh 'echo ok' 2>/dev/null | tr -d '\r')" = "ok" ]; }
# Read the CPU junction zones only. A bare max over every thermal_zone picks up
# non-CPU sensors, and this repo already compared a junction reading against a
# package-shaped limit once. cpu-1-* is the big cluster, which is what throttles.
max_temp_mc() { adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -rn | head -1' | tr -d '\r'; }

# Refuse to start an arm on a hot device. Back-to-back boots took this device from
# 62 C to 84 C in one session on 2026-08-18, and the ledger measures 12% drift for
# identical work between 30 C and 68 C. An arm started hot measures the throttle.
cool_down() {
  local t waited=0
  while :; do
    t=$(max_temp_mc)
    [ -n "$t" ] || return 0
    if [ "$t" -lt "$TEMP_MAX_MC" ] 2>/dev/null; then return 0; fi
    if [ "$waited" -ge "$COOL_TIMEOUT" ]; then
      echo "  still ${t} mC after ${waited}s; an arm started here measures the throttle" >&2
      return 1
    fi
    if [ "$waited" = 0 ]; then echo "  cooling: ${t} mC, want < ${TEMP_MAX_MC} mC" >&2; fi
    adb_sh "am force-stop $PKG" >/dev/null 2>&1
    sleep 30; waited=$((waited + 30))
  done
}

# A property absent from the shipped .so reads back fine from getprop and changes
# nothing, which yields two identical arms and a confident wrong number.
assert_property_shipped() {
  local dir hits
  dir=$(adb_sh "pm path $PKG" | tr -d '\r' | sed 's/package://;s/base\.apk//')
  [ -n "$dir" ] || die "cannot resolve installed path for $PKG"
  hits=$(adb_sh "grep -ac '$PROP' ${dir}lib/arm64/librpcsx-android.so" | tr -d '\r')
  [ "${hits:-0}" != "0" ] || die "'$PROP' is not in the shipped .so; both arms would be identical"
  echo "property present in the shipped .so ($hits match(es))"
}

# An adb install proves the APK arrived. Only /proc/<pid>/maps proves which core runs.
assert_bundled_core() {
  local line
  line=$(adb_sh "run-as $PKG cat /proc/$1/maps 2>/dev/null | grep -m1 librpcsx-android" | tr -d '\r')
  case "$line" in
    */data/app/*) ;;
    *) die "running core is not the bundled one: $line" ;;
  esac
}

run_arm() {
  local value="$1" label="$2" try=0
  while [ "$try" -lt "$MAX_TRIES" ]; do
    try=$((try + 1))
    reachable || die "device stopped answering"
    cool_down || return 1

    # tex3d_reach is this runner's frame counter: it prints "over N frames" every
    # 300 frames through rsx_log.error(). Set it here rather than relying on it
    # being left on from an earlier session, and clear it at the end - a diagnostic
    # left running is how this project ended up with permanent verbose logging once.
    adb_sh "am force-stop $PKG; setprop $PROP '$value'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG" >/dev/null 2>&1
    sleep 3
    local rb; rb=$(adb_sh "getprop $PROP" | tr -d '\r')
    [ "$rb" = "$value" ] || die "property did not take: wanted '$value', read '$rb'"

    adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1

    local waited=0 frames=0
    while [ "$waited" -lt "$BOOT_TIMEOUT" ]; do
      sleep 10; waited=$((waited + 10))
      frames=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
      if [ -n "${frames:-}" ] && [ "${frames:-0}" -gt 3000 ] 2>/dev/null; then break; fi
    done
    if [ -z "${frames:-}" ] || [ "${frames:-0}" -le 3000 ] 2>/dev/null; then
      echo "  [$label] never reached 3000 frames in ${BOOT_TIMEOUT}s" >&2
      continue
    fi

    local pid; pid=$(adb_sh "pidof $PKG" | tr -d '\r')
    [ -n "$pid" ] || { echo "  [$label] no pid" >&2; continue; }
    assert_bundled_core "$pid"

    local tids ntids
    tids=$(adb_sh "for t in /proc/$pid/task/*; do n=\$(cat \$t/comm 2>/dev/null); case \"\$n\" in '$THREAD'*) basename \$t;; esac; done" | tr -d '\r' | tr '\n' ' ')
    ntids=$(echo $tids | wc -w | tr -d ' ')
    [ "${ntids:-0}" -gt 0 ] 2>/dev/null || { echo "  [$label] no thread matching '$THREAD*'" >&2; continue; }

    local out
    out=$(adb_sh "
      sum() { s=0; for t in $tids; do v=\$(awk '{print \$14+\$15}' /proc/$pid/task/\$t/stat 2>/dev/null); s=\$((s + \${v:-0})); done; echo \$s; }
      R1=\$(sum); T1=\$(awk '{print \$14+\$15}' /proc/$pid/stat)
      F1=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
      sleep $WINDOW
      R2=\$(sum); T2=\$(awk '{print \$14+\$15}' /proc/$pid/stat)
      F2=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
      echo \"\$((R2-R1)) \$((T2-T1)) \$((F2-F1))\"" | tr -d '\r')

    local rt tt fr
    rt=$(echo "$out" | awk '{print $1}'); tt=$(echo "$out" | awk '{print $2}'); fr=$(echo "$out" | awk '{print $3}')

    if [ -n "${fr:-}" ] && [ "$fr" -ge "$FRAMES_MIN" ] && [ "$fr" -le "$FRAMES_MAX" ] 2>/dev/null; then
      echo "$rt $tt $fr $(max_temp_mc) $ntids"
      return 0
    fi
    echo "  [$label] rejected: frames=${fr:-none} outside ${FRAMES_MIN}-${FRAMES_MAX}" >&2
  done
  return 1
}

reachable || die "device $DEVICE not answering"
assert_property_shipped
adb_sh "svc power stayon true" >/dev/null 2>&1

echo "$PROP: A='$VAL_A' B='$VAL_B'  thread='$THREAD*'  window=${WINDOW}s  repeats=$REPEATS"
echo "temperature before: $(max_temp_mc) mC"
echo

report() { echo "$1[$2] ($3) thread_ticks=$(echo $4|awk '{print $1}') total=$(echo $4|awk '{print $2}') frames=$(echo $4|awk '{print $3}') temp=$(echo $4|awk '{print $4}') threads=$(echo $4|awk '{print $5}')"; }

for i in $(seq 1 "$REPEATS"); do
  if r=$(run_arm "$VAL_A" "A-$i"); then report A "$i" "$VAL_A" "$r"; fi
  if r=$(run_arm "$VAL_B" "B-$i"); then report B "$i" "$VAL_B" "$r"; fi
done

adb_sh "am force-stop $PKG; setprop $PROP ''; setprop debug.rpcsx.thor.tex3d_reach ''" >/dev/null 2>&1
echo
echo "temperature after: $(max_temp_mc) mC"
echo "Read the RANGES, not the means. If the arms overlap, there is no result."
