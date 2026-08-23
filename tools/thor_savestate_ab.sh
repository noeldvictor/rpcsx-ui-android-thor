#!/usr/bin/env bash
#
# Interleaved A/B on a RESTORED SAVESTATE.
#
# Why a savestate. Every earlier harness here measured the Eternal Sonata intro
# or a title screen. Both idle around 3.0 cores and both sit at the 30 FPS cap,
# so a lever that costs frames reads as free and a lever that saves CPU has
# little CPU to save. A restored save replays the SAME cutscene every run.
#
# MEASURED shape of that workload, 2026-08-22, sampling t+58s to t+108s after the
# load broadcast:
#
#   2.90 cores at 30.00 FPS
#     SPU  1.82 cores  62.5%   (six threads, about 0.30 each)
#     RSX  0.51 cores  17.6%   (rsx::thread, the largest single thread)
#     PPU  0.54 cores  18.4%
#
# It is still CAPPED at 30. That is fine and it is the point: frame output is
# FIXED and deterministic at 300 frames per 10 s, so CPU is the free variable and
# CPU is what "more efficient, lower power" means. Frames are still read every
# run, because an arm that drops below 30 has broken something and must not be
# reported as a CPU win.
#
# Frames come from the emulator's own flip counter, logged by perf_monitor as
# "Frames: N in T (F FPS)". NOT from SurfaceFlinger --latency, which reported a
# frozen layer for a session whose own overlay read 25.74 FPS.
#
# Each arm gets a FRESH PROCESS. Every debug.rpcsx.thor.* property is read once
# into an inline/static and cached for the life of the process, so setting one on
# a running emulator changes nothing.
#
# Usage:
#   tools/thor_savestate_ab.sh "<arm A>" "<arm B>" [rounds] [sample_s]
#
# An arm is a semicolon-separated list of prop=value, or the word `default`:
#   tools/thor_savestate_ab.sh default "debug.rpcsx.thor.rsx_fifo_pause_ladder=64"
#   tools/thor_savestate_ab.sh "a.b=0" "a.b=1;a.c=100" 3 50
set -u

ADB="${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-192.168.1.3:5555}"
FILES=/storage/emulated/0/Android/data/net.rpcsx.easy/files
ISO="${ISO:-/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso}"
TITLE="${TITLE:-BLUS30161}"

ARM_A="${1:?arm A}"
ARM_B="${2:?arm B}"
ROUNDS="${3:-2}"
SAMPLE_S="${4:-50}"
SETTLE_S="${SETTLE_S:-58}"

sh_() { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'; }

# Every property either arm mentions, so all of them can be cleared between arms
# and restored at the end. A tool that leaves a lever set poisons the next
# measurement and the user's next session. That has happened here before.
ALL_PROPS=$(printf '%s;%s' "$ARM_A" "$ARM_B" | tr ';' '\n' \
            | grep -oE '^[a-z0-9_.]+=' | tr -d '=' | sort -u)

declare -A ORIGINAL
for p in $ALL_PROPS; do ORIGINAL[$p]="$(sh_ "getprop $p")"; done

restore_props() {
    for p in $ALL_PROPS; do
        sh_ "setprop $p '${ORIGINAL[$p]}'" >/dev/null 2>&1
    done
    sh_ "am force-stop net.rpcsx.easy; svc power stayon false" >/dev/null 2>&1
    echo "restored: $(for p in $ALL_PROPS; do printf '%s=%s ' "$p" "${ORIGINAL[$p]:-<unset>}"; done)"
}
trap restore_props EXIT INT TERM

apply_arm() {
    for p in $ALL_PROPS; do sh_ "setprop $p ''" >/dev/null; done
    [ "$1" = "default" ] && return 0
    printf '%s' "$1" | tr ';' '\n' | while read -r kv; do
        [ -z "$kv" ] && continue
        sh_ "setprop ${kv%%=*} '${kv#*=}'" >/dev/null
    done
}

run_arm() {
    local spec="$1" tag="$2"

    sh_ "am force-stop net.rpcsx.easy" >/dev/null
    apply_arm "$spec"
    sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null

    sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity \
         --es path '$ISO' --es titleId $TITLE --es thorDebugBootRequestId ab$tag \
         --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile false" >/dev/null
    sh_ "sleep 45" >/dev/null

    sh_ "am broadcast -a net.rpcsx.THOR_DEBUG_LOADSTATE \
         -n net.rpcsx.easy/net.rpcsx.utils.ThorDebugLoadStateReceiver \
         --es thorLoadStateRequestId ab$tag" >/dev/null

    # The restore rebuilds the SPU cache and recompiles shaders, and the scene is
    # not active until that finishes. Sampling through it measures compilation.
    sh_ "sleep $SETTLE_S" >/dev/null

    local pid; pid=$(sh_ "pidof net.rpcsx.easy")
    if [ -z "$pid" ]; then echo "  $tag DIED"; return 1; fi

    local c0 mark c1
    c0=$(sh_ "cat /proc/$pid/stat" | awk '{print $14+$15}')
    mark=$(sh_ "grep -ac 'Frames:' $FILES/cache/RPCSX.log")
    sh_ "sleep $SAMPLE_S" >/dev/null
    c1=$(sh_ "cat /proc/$pid/stat" | awk '{print $14+$15}')

    local fps
    fps=$(sh_ "grep -a 'Frames:' $FILES/cache/RPCSX.log | tail -n +$((mark + 1))" \
          | grep -oE '[0-9.]+ FPS' | grep -oE '^[0-9.]+' \
          | awk '{s+=$1; n++} END {if (n) printf "%.2f", s/n; else printf "0"}')

    local cores
    cores=$(awk -v a="$c0" -v b="$c1" -v t="$SAMPLE_S" 'BEGIN{printf "%.3f", (b-a)/100.0/t}')

    printf '  %-6s cores %-7s fps %-7s %s\n' "$tag" "$cores" "$fps" "$spec"
    printf '%s\t%s\t%s\n' "$spec" "$fps" "$cores" >> "$RESULTS"
}

RESULTS=$(mktemp)
echo "A: $ARM_A"
echo "B: $ARM_B"
echo "rounds=$ROUNDS settle=${SETTLE_S}s sample=${SAMPLE_S}s"
echo

for r in $(seq 1 "$ROUNDS"); do
    run_arm "$ARM_A" "r${r}A"
    run_arm "$ARM_B" "r${r}B"
done

echo
echo "=== summary ==="
awk -F'\t' '{f[$1]+=$2; c[$1]+=$3; n[$1]++;
             if (!(($1) in lo) || $3<lo[$1]) lo[$1]=$3;
             if (!(($1) in hi) || $3>hi[$1]) hi[$1]=$3}
     END {for (k in n) printf "%-46s fps %.2f  cores %.3f  [%.3f..%.3f]  n=%d\n",
                       k, f[k]/n[k], c[k]/n[k], lo[k], hi[k], n[k]}' "$RESULTS"
echo
echo "raw:"; cat "$RESULTS"
rm -f "$RESULTS"
