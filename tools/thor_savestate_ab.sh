#!/usr/bin/env bash
#
# Interleaved A/B on a RESTORED SAVESTATE.
#
# Why a savestate. Every earlier harness here measured the Eternal Sonata intro
# or a title screen. Both sit at the 30 FPS cap, so a lever that costs frames
# reads as free. A restored save replays the SAME scene for every arm.
#
# MEASURED shape of that workload, 2026-08-22, sampling t+58s to t+108s after the
# load broadcast:
#
#   2.90 cores at 30.00 FPS
#     SPU  1.82 cores  62.5%   (six threads, about 0.30 each)
#     RSX  0.51 cores  17.6%   (rsx::thread, the largest single thread)
#     PPU  0.54 cores  18.4%
#
# It is still CAPPED at 30, and that is the point: frame output is FIXED, so CPU
# and power are the free variables and those are what "more efficient, lower
# power" means. Frames are still read every arm, because an arm below 30 has
# broken something and must not be reported as a CPU win.
#
# Frames come from the emulator's own flip counter, logged by perf_monitor as
# "Frames: N in T (F FPS)". NOT from SurfaceFlinger --latency, which reported a
# frozen layer for a session whose own overlay read 25.74 FPS.
#
# Power comes from the charger input and is only valid while the cell is NOT
# charging. See tools/thor_power_iin.sh for why that path is trusted and the fuel
# gauge is not.
#
# Each arm gets a FRESH PROCESS, because every debug.rpcsx.thor.* property is read
# once into a static or an inline const and cached for the life of the process.
#
# EVERY ARM PRINTS THE PROPERTIES IT ACTUALLY APPLIED, read back off the device.
# The first version of this script set none of them: it fed `printf '%s'` into a
# `while read` loop, and with no trailing newline `read` hit EOF and the body
# never ran. Both arms then measured the SAME configuration and agreed beautifully.
# Only the RSX FIFO counter line, which was absent, showed the lever never ran.
#
# Usage:
#   tools/thor_savestate_ab.sh "<arm A>" "<arm B>" [rounds] [sample_s]
#
# An arm is a semicolon-separated list of prop=value, or the word `default`:
#   tools/thor_savestate_ab.sh default "debug.rpcsx.thor.rsx_fifo_pause_ladder=64"
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

ALL_PROPS=$(printf '%s\n%s\n' "$ARM_A" "$ARM_B" | tr ';' '\n' \
            | grep -oE '^[a-z0-9_.]+=' | tr -d '=' | sort -u)

declare -A ORIGINAL
for p in $ALL_PROPS; do ORIGINAL[$p]="$(sh_ "getprop $p")"; done

restore_props() {
    for p in $ALL_PROPS; do sh_ "setprop $p '${ORIGINAL[$p]}'" >/dev/null 2>&1; done
    sh_ "am force-stop net.rpcsx.easy; svc power stayon false" >/dev/null 2>&1
    echo "restored: $(for p in $ALL_PROPS; do printf '%s=%s ' "$p" "${ORIGINAL[$p]:-<unset>}"; done)"
}
trap restore_props EXIT INT TERM

# No pipeline, so no subshell and no lost last line.
apply_arm() {
    local spec="$1" kv old_ifs
    for p in $ALL_PROPS; do sh_ "setprop $p ''" >/dev/null; done
    [ "$spec" = "default" ] && return 0
    old_ifs="$IFS"; IFS=';'
    for kv in $spec; do
        [ -z "$kv" ] && continue
        sh_ "setprop ${kv%%=*} '${kv#*=}'" >/dev/null
    done
    IFS="$old_ifs"
}

# Read back what the device actually holds, so a silent no-op cannot pass as a
# measurement again.
readback() {
    local out="" p v
    for p in $ALL_PROPS; do
        v="$(sh_ "getprop $p")"
        out="$out${p##*.}=${v:-unset} "
    done
    printf '%s' "$out"
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

    # The restore rebuilds the SPU cache and recompiles shaders; the scene is not
    # active until that finishes. Sampling through it measures compilation.
    sh_ "sleep $SETTLE_S" >/dev/null

    local pid; pid=$(sh_ "pidof net.rpcsx.easy")
    if [ -z "$pid" ]; then echo "  $tag INVALID (process gone)"; return 0; fi

    local c0 mark c1 mw fps cores pid2 r0 r1 rsxc

    # Per-thread CPU as well as whole-process.
    #
    # A null A/B measured this harness's own noise at +/-5% on whole-process cores
    # (3.097 to 3.259 over three samples of one configuration). rsx::thread is only
    # 0.51 of 2.90 cores, so a lever that saves 30% OF THAT THREAD moves the process
    # total by 5% and disappears into the noise. Measured on the thread it targets,
    # the same saving is 30% and is unmissable.
    THREAD_MATCH="${THREAD_MATCH:-rsx::thread}"
    tcpu() {
        sh_ "for t in \$(ls /proc/$pid/task 2>/dev/null); do
               n=\$(cat /proc/$pid/task/\$t/comm 2>/dev/null);
               case \"\$n\" in *${THREAD_MATCH}*)
                 awk '{print \$14+\$15}' /proc/$pid/task/\$t/stat 2>/dev/null;; esac;
             done" | awk '{s+=$1} END {print s+0}'
    }

    c0=$(sh_ "cat /proc/$pid/stat" | awk '{print $14+$15}')
    r0=$(tcpu)
    mark=$(sh_ "grep -ac 'Frames:' $FILES/cache/RPCSX.log")

    mw=$(sh_ "for i in \$(seq 1 $((SAMPLE_S / 5))); do
                v=\$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null);
                c=\$(cat /sys/class/power_supply/usb/current_now 2>/dev/null);
                g=\$(cat /sys/bus/iio/devices/iio:device0/in_current_pm8550b_ichg_fb_input 2>/dev/null);
                echo \"\$v \$c \$g\"; sleep 5; done" \
         | awk '$1+0>0 && $2+0>0 {if ($3+0>20000) chg=1; s+=($1/1e6)*($2/1e6)*1000; n++}
                END {if (chg) printf "charging"; else if (n) printf "%.0f", s/n; else printf "na"}')

    c1=$(sh_ "cat /proc/$pid/stat" | awk '{print $14+$15}')
    r1=$(tcpu)
    pid2=$(sh_ "pidof net.rpcsx.easy")

    if [ "$pid" != "$pid2" ]; then echo "  $tag INVALID (process restarted)"; return 0; fi

    fps=$(sh_ "grep -a 'Frames:' $FILES/cache/RPCSX.log | tail -n +$((mark + 1))" \
          | grep -oE '[0-9.]+ FPS' | grep -oE '^[0-9.]+' \
          | awk '{s+=$1; n++} END {if (n) printf "%.2f", s/n; else printf "0"}')

    cores=$(awk -v a="${c0:-0}" -v b="${c1:-0}" -v t="$SAMPLE_S" \
            'BEGIN{printf "%.3f", (b-a)/100.0/t}')

    # An arm which produced no frames or no CPU measured nothing. Say so rather
    # than averaging a zero into the result.
    if [ "$fps" = "0" ] || [ "${cores%%.*}" = "0" -a "${cores#0.}" = "000" ]; then
        echo "  $tag INVALID (fps=$fps cores=$cores) [$(readback)]"
        return 0
    fi

    rsxc=$(awk -v a="${r0:-0}" -v b="${r1:-0}" -v t="$SAMPLE_S" \
            'BEGIN{printf "%.3f", (b-a)/100.0/t}')

    printf '  %-6s cores %-7s %s %-7s fps %-7s power %-9s [%s]\n' \
        "$tag" "$cores" "$THREAD_MATCH" "$rsxc" "$fps" "$mw" "$(readback)"
    printf '%s\t%s\t%s\t%s\t%s\n' "$spec" "$fps" "$cores" "$mw" "$rsxc" >> "$RESULTS"
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
awk -F'\t' '
    { f[$1]+=$2; c[$1]+=$3; n[$1]++
      if ($4+0>0) { p[$1]+=$4; pn[$1]++ }
      th[$1]+=$5
      if (!((($1) in lo)) || $3<lo[$1]) lo[$1]=$3
      if (!((($1) in hi)) || $3>hi[$1]) hi[$1]=$3 }
    END { for (k in n)
            printf "%-46s fps %.2f  cores %.3f [%.3f..%.3f]  thread %.3f  power %s  n=%d\n",
                   k, f[k]/n[k], c[k]/n[k], lo[k], hi[k], th[k]/n[k],
                   (pn[k] ? sprintf("%.0fmW", p[k]/pn[k]) : "na"), n[k] }' "$RESULTS"
echo
echo "raw:"; cat "$RESULTS"
rm -f "$RESULTS"
