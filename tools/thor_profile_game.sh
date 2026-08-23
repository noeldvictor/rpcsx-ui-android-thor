#!/usr/bin/env bash
#
# Boot a game, WAIT until it actually renders, then profile it.
#
# The wait matters. Transformers: War for Cybertron reported
# "Frames: 0 in 10.00s (0.00 FPS)" for over three minutes on a cold cache while
# PPU LLVM built modules of four to nine thousand functions each. Profiling then
# measures the compiler, not the game. This polls the emulator's own frame
# counter and only records once frames are actually being produced.
#
# simpleperf needs run-as, because perf_event_paranoid is 1 on this device and
# setprop security.perf_harden 0 does not change it. The APK is debuggable and
# CMAKE_BUILD_TYPE is pinned to RelWithDebInfo regardless of that flag, so the
# profile describes the build that ships.
#
# Usage: tools/thor_profile_game.sh "<iso path>" <titleId> [settle_s] [record_s]
set -u

ADB="${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-192.168.1.3:5555}"
FILES=/storage/emulated/0/Android/data/net.rpcsx.easy/files

ISO="${1:?iso path}"
TITLE="${2:?titleId}"
SETTLE_S="${3:-60}"
RECORD_S="${4:-25}"
MAX_WAIT_S="${MAX_WAIT_S:-1500}"

sh_() { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'; }

cleanup() { sh_ "svc power stayon false" >/dev/null 2>&1; }
trap cleanup EXIT INT TERM

sh_ "am force-stop net.rpcsx.easy" >/dev/null
sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
sh_ "rm -f $FILES/cache/RPCSX.log" >/dev/null

echo "booting $TITLE"
sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity \
     --es path '$ISO' --es titleId $TITLE --es thorDebugBootRequestId prof \
     --ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false" >/dev/null

# Wait for the first non-zero frame report.
waited=0
rendered=0
while [ "$waited" -lt "$MAX_WAIT_S" ]; do
    sh_ "sleep 15" >/dev/null
    waited=$((waited + 15))

    if [ -z "$(sh_ "pidof net.rpcsx.easy")" ]; then
        echo "process died after ${waited}s"
        exit 1
    fi

    last=$(sh_ "grep -aoE 'Frames: [0-9]+ in' $FILES/cache/RPCSX.log | tail -1" \
           | grep -oE '[0-9]+' | head -1)
    last="${last:-0}"
    echo "  t+${waited}s frames_last_report=$last"

    if [ "$last" -gt 0 ] 2>/dev/null; then rendered=1; break; fi
done

if [ "$rendered" != "1" ]; then
    echo "never rendered within ${MAX_WAIT_S}s; still compiling or stuck"
    sh_ "grep -avE 'Performance Sensor|too sleepy' $FILES/cache/RPCSX.log | tail -6" | cut -c1-150
    exit 2
fi

echo "rendering; settling ${SETTLE_S}s"
sh_ "sleep $SETTLE_S" >/dev/null

PID=$(sh_ "pidof net.rpcsx.easy")
echo "recording ${RECORD_S}s on pid $PID"
sh_ "run-as net.rpcsx.easy /system/bin/simpleperf record -p $PID \
     --duration $RECORD_S -f 1000 -g -o /data/data/net.rpcsx.easy/perf.data" 2>&1 | tail -2

echo "=== fps during the window ==="
sh_ "grep -aoE 'Frames: [0-9]+ in [0-9.]+s \([0-9.]+ FPS\)' $FILES/cache/RPCSX.log | tail -4"

echo "=== cores ==="
C0=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
sh_ "sleep 20" >/dev/null
C1=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
awk -v a="$C0" -v b="$C1" 'BEGIN{printf "  %.2f cores\n", (b-a)/100.0/20}'

sh_ "run-as net.rpcsx.easy cat /data/data/net.rpcsx.easy/perf.data > /sdcard/perf.data" >/dev/null
echo "perf.data left at /sdcard/perf.data"
