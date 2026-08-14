#!/usr/bin/env bash
# Phase-gated A/B of one debug.rpcsx.thor.* property, on a booted title.
#
# Why the phase gate exists
# -------------------------
# Folklore's title screen is not one workload. It has an attract movie and a menu,
# and a boot lands in whichever. The same configuration, launched twice, gave
# 185 ticks over 1,750 frames and 1,720 ticks over 3,500. Normalising to ticks per
# frame does not rescue it either: 0.106 against 0.491.
#
# So an arm is only accepted when its frame count falls in a band, which pins the
# scene. Runs outside the band are discarded and retried, never averaged in.
#
# What it still cannot do
# -----------------------
# **The gate fixes the scene and not the scatter.** Inside the 3,500-frame band the
# spread for one fixed setting is about +-50 ticks, which is several percent. Two
# results were claimed and retracted on 2026-08-13 and 2026-08-14 because arms
# separated by less than that were read as real. Anything under about 5% needs many
# more samples per arm than the default here, or a normaliser the change provably
# cannot touch, in the shape of the spu_getllar_retry denominator in
# lv2-ppu-spin.md.
#
# Usage:
#   tools/thor_phase_gated_ab.sh PROPERTY VALUE_A VALUE_B [REPEATS]
#
#   tools/thor_phase_gated_ab.sh debug.rpcsx.thor.spu_branch_extract 0 1 3
#
# An empty value clears the property, which is how the shipped default is tested.
# Arms are interleaved, never grouped, because the device warms over a session:
# runs an hour apart differed by 12% for identical work as it went from 30 C to
# 68 C. Comparisons are only valid within one interleaved batch.
set -u

PROP="${1:?property name, e.g. debug.rpcsx.thor.spu_branch_extract}"
VAL_A="${2?value for arm A, may be empty}"
VAL_B="${3?value for arm B, may be empty}"
REPEATS="${4:-2}"

DEVICE="${THOR_SERIAL:-c3ca0370}"
PKG="${THOR_PACKAGE:-net.rpcsx.easy}"
TITLE="${THOR_TITLE:-BCUS98147}"
GAME="${THOR_GAME:-/storage/2664-21DE/Roms/ps3/Folklore (USA) (En,Fr,De,Es,It).iso}"
FRAMES_MIN="${THOR_FRAMES_MIN:-3450}"
FRAMES_MAX="${THOR_FRAMES_MAX:-3550}"
SETTLE="${THOR_SETTLE:-20}"
WINDOW="${THOR_WINDOW:-60}"
MAX_TRIES="${THOR_MAX_TRIES:-4}"

# Git Bash rewrites device paths into C:/Program Files/... and the failure names a
# local path, which reads like a missing file on the device.
export MSYS_NO_PATHCONV=1

LOG="/sdcard/Android/data/${PKG}/files/cache/RPCSX.log"

adb_sh() { adb -s "$DEVICE" shell "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

reachable() {
  # An unreachable device returns empty exactly like a quiet one.
  [ "$(adb_sh 'echo ok' 2>/dev/null | tr -d '\r')" = "ok" ]
}

max_cpu_temp_c() {
  adb_sh 'for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/type 2>/dev/null); v=$(cat $z/temp 2>/dev/null); case "$t" in cpu-1-*) echo "$v";; esac; done | sort -n | tail -1' 2>/dev/null | tr -d '\r'
}

foreign_busy() {
  # The device is shared with another session. Never force-stop their package.
  adb_sh "top -b -n 2 -d 2 | grep xenia | grep -v logcat | grep -v grep" 2>/dev/null |
    awk '{ for (i=1;i<=NF;i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+2) ~ /^[0-9]+:[0-9]+/) { if ($i+0 > m) m = $i+0 } } END { print (m+0) }'
}

# Prove the property reaches the shipped binary. A property that is not in the .so
# reads back from getprop and changes nothing, which yields two identical arms.
assert_property_shipped() {
  local dir
  dir=$(adb_sh "pm path $PKG" 2>/dev/null | tr -d '\r' | sed 's/package://;s/base\.apk//')
  [ -n "$dir" ] || die "cannot resolve the installed path for $PKG"
  local hits
  hits=$(adb_sh "grep -ac '$PROP' ${dir}lib/arm64/librpcsx-android.so" 2>/dev/null | tr -d '\r')
  [ "${hits:-0}" != "0" ] || die "'$PROP' is not in the installed .so, so both arms would be identical"
  echo "property present in the installed .so ($hits match(es))"
}

# One accepted arm, or nothing.
run_arm() {
  local value="$1" label="$2" try=0 ticks frames result

  while [ "$try" -lt "$MAX_TRIES" ]; do
    try=$((try + 1))

    reachable || die "device $DEVICE stopped answering"

    local busy; busy=$(foreign_busy)
    if [ "${busy%%.*}" -gt 20 ] 2>/dev/null; then
      echo "  [$label] other session at ${busy}% CPU; waiting" >&2
      sleep 60
      continue
    fi

    adb_sh "am force-stop $PKG; setprop $PROP '$value'; rm -f $LOG" >/dev/null 2>&1

    local readback; readback=$(adb_sh "getprop $PROP" 2>/dev/null | tr -d '\r')
    [ "$readback" = "$value" ] || die "property did not take: wanted '$value', read '$readback'"

    adb_sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity --es path '$GAME' --es titleId $TITLE --es thorDebugBootRequestId $label" >/dev/null 2>&1

    # Wait for frames rather than for a fixed time: a cold PPU cache spends about
    # 27 minutes before the first PPU thread exists, and a warm one about 10s.
    local waited=0
    while [ "$(adb_sh "grep -c on_frame_end $LOG" 2>/dev/null | tr -d '\r')" -le 1 ] 2>/dev/null; do
      sleep 8
      waited=$((waited + 8))
      [ "$waited" -gt 1800 ] && { echo "  [$label] no frames after 30 min" >&2; break; }
    done

    # Frames come from the emulator's own on_frame_end counter, and CPU from
    # /proc/<pid>/stat. A CPU number alone cannot tell a thread that stopped
    # spinning from an emulator that stopped working.
    result=$(adb_sh "P=\$(pidof $PKG); sleep $SETTLE; F1=\$(grep -o 'on_frame_end call #[0-9]*' $LOG | tail -1 | grep -o '[0-9]*\$'); A=\$(awk '{print \$14+\$15}' /proc/\$P/stat); sleep $WINDOW; F2=\$(grep -o 'on_frame_end call #[0-9]*' $LOG | tail -1 | grep -o '[0-9]*\$'); B=\$(awk '{print \$14+\$15}' /proc/\$P/stat); echo \"\$((B-A)) \$((F2-F1))\"" 2>/dev/null | tr -d '\r')

    ticks=$(echo "$result" | cut -d' ' -f1)
    frames=$(echo "$result" | cut -d' ' -f2)

    if [ -n "${frames:-}" ] && [ "$frames" -ge "$FRAMES_MIN" ] && [ "$frames" -le "$FRAMES_MAX" ] 2>/dev/null; then
      echo "$ticks"
      return 0
    fi

    echo "  [$label] rejected: frames=${frames:-none}, outside ${FRAMES_MIN}-${FRAMES_MAX}" >&2
  done

  return 1
}

reachable || die "device $DEVICE is not answering; try 'adb reconnect' or a replug"
assert_property_shipped

echo "temperature before: $(max_cpu_temp_c) mC"
echo "$PROP: A='$VAL_A' B='$VAL_B', $REPEATS repeat(s), interleaved"
echo

a_results=""
b_results=""

for i in $(seq 1 "$REPEATS"); do
  if t=$(run_arm "$VAL_A" "A-$i"); then a_results="$a_results $t"; echo "A[$i] ($VAL_A) ticks=$t"; fi
  if t=$(run_arm "$VAL_B" "B-$i"); then b_results="$b_results $t"; echo "B[$i] ($VAL_B) ticks=$t"; fi
done

adb_sh "am force-stop $PKG; setprop $PROP ''" >/dev/null 2>&1

echo
echo "temperature after: $(max_cpu_temp_c) mC"
echo "A ($VAL_A):$a_results"
echo "B ($VAL_B):$b_results"
echo
echo "Read the ranges, not the means. If they overlap, there is no result."
echo "The spread for one fixed setting here is about 50 ticks; two claims were"
echo "retracted for being read below that. Re-run reversed before believing any."
