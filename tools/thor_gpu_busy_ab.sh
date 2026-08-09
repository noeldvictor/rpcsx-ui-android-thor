#!/bin/sh
# A/B a GPU-side change by GPU busy time, not frame time.
#
# Frame time cannot see a tiler optimization on a title that holds its cap:
# Folklore sits at 60.01 fps with the RSX thread at ~1.4% either way. The saving
# from folding a clear into a load op is avoided GMEM/system-memory traffic,
# which shows up as the GPU being busy for less of the window.
#
# /sys/class/kgsl/kgsl-3d0/gpubusy reports a cumulative "busy total" pair and
# resets on read, so read once to zero it, wait, and read again for the window.
# clock_mhz is sampled alongside because busy% at a lower clock is not the same
# saving -- devfreq may respond to reduced load by dropping frequency instead.
#
# Usage: sh tools/thor_gpu_busy_ab.sh <serial> <title-id> <iso-path> <settle> <window>
set -e

S="$1"; TID="$2"; GP="$3"; SETTLE="${4:-140}"; WINDOW="${5:-40}"
PKG=net.rpcsx.easy
K=/sys/class/kgsl/kgsl-3d0

[ -n "$S" ] && [ -n "$TID" ] && [ -n "$GP" ] || { echo "usage: $0 serial titleid isopath [settle] [window]" >&2; exit 1; }

for mode in 0 1; do
    adb -s "$S" shell "am force-stop $PKG" >/dev/null 2>&1
    adb -s "$S" shell "setprop debug.rpcsx.thor.loadop_clear $mode" >/dev/null 2>&1
    got=$(adb -s "$S" shell "getprop debug.rpcsx.thor.loadop_clear" | tr -d '\r ')
    [ "$got" = "$mode" ] || { echo "property did not take: wanted $mode got $got" >&2; exit 1; }

    adb -s "$S" shell "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
        --es path '$GP' --es titleId $TID --es thorDebugBootRequestId gpuab-$mode \
        --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null 2>&1

    sleep "$SETTLE"

    # An unreachable device returns empty exactly like a dead process.
    ok=$(adb -s "$S" shell "echo ok" 2>/dev/null | tr -d '\r ')
    [ "$ok" = "ok" ] || { echo "device unreachable" >&2; exit 1; }
    alive=$(adb -s "$S" shell "pidof $PKG" | tr -d '\r ')
    [ -n "$alive" ] || { echo "emulator died in arm $mode" >&2; exit 1; }

    adb -s "$S" shell "cat $K/gpubusy" >/dev/null 2>&1   # read to reset
    c0=$(adb -s "$S" shell "cat $K/clock_mhz" | tr -d '\r ')
    sleep "$WINDOW"
    read_out=$(adb -s "$S" shell "cat $K/gpubusy" | tr -d '\r')
    c1=$(adb -s "$S" shell "cat $K/clock_mhz" | tr -d '\r ')

    busy=$(echo "$read_out" | awk '{print $1}')
    total=$(echo "$read_out" | awk '{print $2}')
    pct=$(awk -v b="$busy" -v t="$total" 'BEGIN{ if (t>0) printf "%.2f", 100*b/t; else print "n/a" }')

    echo "  loadop_clear=$mode  gpu_busy=${pct}%  (busy=$busy total=$total)  clock ${c0}->${c1} MHz"
done

adb -s "$S" shell "am force-stop $PKG; setprop debug.rpcsx.thor.loadop_clear 0" >/dev/null 2>&1
echo "  emulator stopped, property reset"
