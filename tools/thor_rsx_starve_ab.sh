#!/usr/bin/env bash
# Does rsx_fifo_park pay for itself when the RSX thread STARVES?
#
# Why this experiment exists
# --------------------------
# Folklore's title screen has two steady states, measured 2026-08-18:
#
#   light  ~1845 process ticks / 60 s, 7200 frames, rsx::thread ~256 ticks
#   heavy  ~6876 process ticks / 60 s, 6000 frames, rsx::thread ~5985 ticks
#
# In the heavy state rsx::thread pegs a whole core and delivers FEWER frames. A
# 24,208-sample profile of that state puts 89.13% of cycles on rsx::thread and
# every single sched_yield sample on it. That is the FIFO_EMPTY branch of
# RSXFIFO.cpp spinning on std::this_thread::yield() while the guest fails to feed
# it - the RSX is starving, and it burns a core to do it.
#
# rsx_fifo_park replaces that spin with a bounded event-stream park. An A/B in the
# LIGHT state says the park costs about 26 ticks, because a FIFO that is never
# empty never reaches the branch. The light state cannot answer the question; the
# question is what the park is worth when the branch IS reached.
#
# The heavy state appeared in 3 of ~14 boots and cannot be requested. So induce it:
# load every core with spinners, the guest threads lose CPU, the FIFO drains, and
# the RSX starves. Both arms get the identical stressor, so it is a controlled
# variable rather than a confound.
#
# Reports rsx::thread ticks AND frames. A CPU number alone cannot tell a thread
# that stopped spinning from an emulator that stopped working.
set -u

VAL_A="${1:-0}"
VAL_B="${2:-1}"
REPEATS="${3:-2}"
STRESSORS="${THOR_STRESSORS:-6}"

DEVICE="${THOR_SERIAL:-192.168.1.33:5555}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
PROP="${THOR_PROP:-debug.rpcsx.thor.rsx_fifo_park}"
WINDOW="${THOR_WINDOW:-45}"

export MSYS_NO_PATHCONV=1
LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"
adb_sh() { adb -s "$DEVICE" shell "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(adb_sh 'echo ok' | tr -d '\r')" = "ok" ] || die "device not answering"

# The stressors are the dangerous part of this script. If adb drops mid-arm, or the
# script is killed, the device-side `kill $pids` never runs and the spinners survive
# - on a SHARED device, at full load, invisibly.
#
# That happened on 2026-08-18. Twelve orphaned spinners ran for hours at about 430%
# CPU, held the CPU junction at 86 C, and inflated every absolute measurement taken
# afterwards by roughly 46%. Interleaving is the only reason the comparisons stood.
#
# So sweep before starting, and sweep again on ANY exit.
kill_stressors() { adb_sh "killall yes 2>/dev/null; true" >/dev/null 2>&1; }
trap kill_stressors EXIT INT TERM
kill_stressors

run_arm() {
  local value="$1" label="$2"

  adb_sh "am force-stop $PKG; setprop $PROP '$value'; setprop debug.rpcsx.thor.tex3d_reach 1; rm -f $LOG" >/dev/null 2>&1
  sleep 3
  [ "$(adb_sh "getprop $PROP" | tr -d '\r')" = "$value" ] || die "property did not take"

  adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --ez thorRequireManagedProfile false --es thorDebugBootRequestId $label" >/dev/null 2>&1

  local waited=0 frames=0
  while [ "$waited" -lt 600 ]; do
    sleep 10; waited=$((waited + 10))
    frames=$(adb_sh "grep -o 'over [0-9]* frames' $LOG 2>/dev/null | tail -1 | grep -o '[0-9]*'" | tr -d '\r')
    if [ -n "${frames:-}" ] && [ "${frames:-0}" -gt 3000 ] 2>/dev/null; then break; fi
  done
  [ "${frames:-0}" -gt 3000 ] 2>/dev/null || { echo "  [$label] never booted" >&2; return 1; }

  local pid tid
  pid=$(adb_sh "pidof $PKG" | tr -d '\r')
  tid=$(adb_sh "for t in /proc/$pid/task/*; do n=\$(cat \$t/comm 2>/dev/null); case \"\$n\" in rsx::thread) basename \$t;; esac; done | head -1" | tr -d '\r')
  [ -n "$tid" ] || { echo "  [$label] no rsx::thread" >&2; return 1; }

  # Start the stressors, sample, stop them. All inside one shell so a dropped adb
  # link cannot leave spinners running on a shared device.
  adb_sh "
    pids=''
    i=0
    while [ \$i -lt $STRESSORS ]; do
      ( yes > /dev/null ) & pids=\"\$pids \$!\"
      i=\$((i+1))
    done
    sleep 5
    R1=\$(awk '{print \$14+\$15}' /proc/$pid/task/$tid/stat)
    T1=\$(awk '{print \$14+\$15}' /proc/$pid/stat)
    F1=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
    sleep $WINDOW
    R2=\$(awk '{print \$14+\$15}' /proc/$pid/task/$tid/stat)
    T2=\$(awk '{print \$14+\$15}' /proc/$pid/stat)
    F2=\$(grep -o 'over [0-9]* frames' $LOG | tail -1 | grep -o '[0-9]*')
    kill \$pids 2>/dev/null
    echo \"\$((R2-R1)) \$((T2-T1)) \$((F2-F1))\"" | tr -d '\r'
}

echo "rsx_fifo_park under induced starvation: A='$VAL_A' B='$VAL_B', ${STRESSORS} spinners, ${WINDOW}s window"
echo
for i in $(seq 1 "$REPEATS"); do
  r=$(run_arm "$VAL_A" "A-$i") && echo "A[$i] ($VAL_A) rsx_ticks=$(echo $r|awk '{print $1}') total=$(echo $r|awk '{print $2}') frames=$(echo $r|awk '{print $3}')"
  r=$(run_arm "$VAL_B" "B-$i") && echo "B[$i] ($VAL_B) rsx_ticks=$(echo $r|awk '{print $1}') total=$(echo $r|awk '{print $2}') frames=$(echo $r|awk '{print $3}')"
done

adb_sh "am force-stop $PKG; setprop $PROP ''; setprop debug.rpcsx.thor.tex3d_reach ''" >/dev/null 2>&1
echo
echo "Read the ranges. Frames must be reported beside CPU: a park that stops the"
echo "emulator working also stops it spinning."
