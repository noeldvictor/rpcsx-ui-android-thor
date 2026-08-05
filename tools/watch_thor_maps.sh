#!/usr/bin/env bash
# Watch RPCSX's mapping count and thread count during game boot/compile.
#
# The Scudo "internal map failure (NO MEMORY) requesting 4KB" abort seen on
# 2026-08-05 happened with vm.overcommit_memory=1, where the kernel does not
# refuse a mapping for lack of RAM. That points at vm.max_map_count (65530)
# rather than physical memory. This samples both counts so the theory can be
# confirmed or killed.
#
# Usage: tools/watch_thor_maps.sh [serial] [seconds]

SERIAL="${1:-c3ca0370}"
DURATION="${2:-180}"
PKG="net.rpcsx.easy"
LIMIT=$(adb -s "$SERIAL" shell cat /proc/sys/vm/max_map_count 2>/dev/null | tr -d '\r')

echo "waiting for $PKG to start (max_map_count=$LIMIT)..."
PID=""
for _ in $(seq 1 120); do
    PID=$(adb -s "$SERIAL" shell pidof "$PKG" 2>/dev/null | tr -d '\r' | awk '{print $1}')
    [ -n "$PID" ] && break
    sleep 1
done

if [ -z "$PID" ]; then
    echo "timed out waiting for the app to start"
    exit 1
fi

echo "pid=$PID  sampling for ${DURATION}s"
printf "%7s %9s %8s %7s %10s\n" "TIME" "MAPS" "PCT" "THREADS" "RSS_MB"

peak_maps=0
for i in $(seq 1 "$DURATION"); do
    read -r maps threads rss <<<"$(adb -s "$SERIAL" shell "
        m=\$(wc -l < /proc/$PID/maps 2>/dev/null);
        t=\$(ls /proc/$PID/task 2>/dev/null | wc -l);
        r=\$(awk '/VmRSS/{print \$2}' /proc/$PID/status 2>/dev/null);
        echo \$m \$t \$r" 2>/dev/null | tr -d '\r')"

    if [ -z "$maps" ]; then
        echo "process gone at t=${i}s (peak maps=$peak_maps)"
        break
    fi

    [ "$maps" -gt "$peak_maps" ] 2>/dev/null && peak_maps=$maps
    pct=$(( maps * 100 / LIMIT ))
    printf "%6ss %9s %7s%% %7s %10s\n" "$i" "$maps" "$pct" "$threads" "$(( ${rss:-0} / 1024 ))"

    sleep 1
done

echo
echo "peak mappings: $peak_maps of $LIMIT ($(( peak_maps * 100 / LIMIT ))%)"
if [ "$peak_maps" -gt $(( LIMIT * 80 / 100 )) ]; then
    echo "VERDICT: near the map limit. Mapping exhaustion is the likely abort cause."
else
    echo "VERDICT: not close to the map limit. Look elsewhere for the abort cause."
fi
