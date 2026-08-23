#!/usr/bin/env bash
#
# Interleaved A/B against a game's TITLE SCREEN, gated on actually being there.
#
# Why the title screen. Transformers has no savestate, and advancing by pressing
# A and START measures whatever cutscene the run happens to land in: one
# configuration gave 3.78 and 5.89 cores on consecutive rounds. The title screen
# needs no input at all and, for this title, is already heavy: 70.7% CPU with SPU
# at 56.1%. One configuration measured there repeats to about +/-0.2%.
#
# WHY THE GATE. A fixed sleep is NOT enough. Boot time varies by tens of seconds,
# so a fixed wait lands mid-logo on one run and mid-cutscene on another. Two arms
# of a previous A/B came back at 0.00 and 20.00 FPS while the other two were at
# 30, and averaging those four numbers would have been meaningless. This waits
# until the frame rate is actually at the title screen's rate for two consecutive
# reports, and reports an arm INVALID rather than contributing a wrong number.
#
# Arms are config keys, applied to the title's custom config, because the
# interesting levers here are config settings and not debug.rpcsx.thor properties.
# The config is written through run-as so it belongs to the app; writing it as
# shell leaves a file the app cannot rewrite, which this project has been bitten
# by before.
#
# Usage:
#   tools/thor_title_ab.sh <titleId> "<iso>" "<key: valA>" "<key: valB>" [rounds]
#
#   tools/thor_title_ab.sh BLUS30357 "/path/game.iso" \
#       "SPU loop detection: false" "SPU loop detection: true" 2
set -u

ADB="${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-192.168.1.3:5555}"
FILES=/storage/emulated/0/Android/data/net.rpcsx.easy/files

TITLE="${1:?titleId}"
ISO="${2:?iso}"
ARM_A="${3:?arm A config line}"
ARM_B="${4:?arm B config line}"
ROUNDS="${5:-2}"
SAMPLE_S="${SAMPLE_S:-40}"
TARGET_FPS="${TARGET_FPS:-29}"

CFG="$FILES/config/custom_configs/config_${TITLE}.yml"
sh_() { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'; }
temp_() { sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }

BACKUP="$(sh_ "cat $CFG 2>/dev/null")"
restore() {
    if [ -n "$BACKUP" ]; then
        printf '%s' "$BACKUP" | while IFS= read -r l; do printf '%s\n' "$l"; done > /tmp/_cfgrestore 2>/dev/null || true
    fi
    sh_ "am force-stop net.rpcsx.easy; svc power stayon false" >/dev/null 2>&1
    echo "note: config left as the last arm wrote it; reinstall or re-apply the profile to reset"
}
trap restore EXIT INT TERM

write_cfg() {
    sh_ "run-as net.rpcsx.easy sh -c 'printf \"%s\n\" \
        \"# RPCSX_THOR_PROFILE_OVERRIDE (A/B in progress)\" \
        \"Core:\" \
        \"  RSX FIFO Accuracy: Atomic\" \
        \"  Accurate SPU Reservations: false\" \
        \"  $1\" \
        \"Video:\" \
        \"  Frame limit: 30\" \
        \"  Shader Mode: Async with Shader Interpreter\" \
        \"  Performance Overlay:\" \
        \"    Enabled: true\" > $CFG'" >/dev/null
}

last_fps() {
    sh_ "grep -aoE '\\([0-9.]+ FPS\\)' $FILES/cache/RPCSX.log | tail -1" | grep -oE '[0-9.]+'
}

run_arm() {
    local cfgline="$1" tag="$2"

    sh_ "am force-stop net.rpcsx.easy" >/dev/null
    write_cfg "$cfgline"
    until [ "$(temp_)" -lt 58 ]; do sh_ "sleep 20" >/dev/null; done
    sh_ "rm -f $FILES/cache/RPCSX.log; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
    sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity \
         --es path '$ISO' --es titleId $TITLE --es thorDebugBootRequestId $tag \
         --ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false" >/dev/null

    # Gate: two consecutive reports at the title screen's rate.
    local hits=0 waited=0 f
    while [ "$waited" -lt 240 ]; do
        sh_ "sleep 10" >/dev/null; waited=$((waited + 10))
        f="$(last_fps)"; f="${f:-0}"
        if [ "$(awk -v a="$f" -v t="$TARGET_FPS" 'BEGIN{print (a>=t)?1:0}')" = "1" ]; then
            hits=$((hits + 1))
        else
            hits=0
        fi
        [ "$hits" -ge 2 ] && break
    done

    if [ "$hits" -lt 2 ]; then
        echo "  $tag INVALID (never settled at the title screen; last fps=${f:-0})"
        return 0
    fi

    local PID M C0 C1 FPS
    PID=$(sh_ "pidof net.rpcsx.easy")
    M=$(sh_ "grep -ac 'Frames:' $FILES/cache/RPCSX.log")
    C0=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
    sh_ "sleep $SAMPLE_S" >/dev/null
    C1=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
    FPS=$(sh_ "grep -a 'Frames:' $FILES/cache/RPCSX.log | tail -n +$((M+1))" \
          | grep -oE '[0-9.]+ FPS' | grep -oE '^[0-9.]+' \
          | awk '{s+=$1;n++} END{if(n)printf "%.2f",s/n; else printf "0"}')

    if [ "$(awk -v a="$FPS" -v t="$TARGET_FPS" 'BEGIN{print (a>=t)?1:0}')" != "1" ]; then
        echo "  $tag INVALID (left the title screen mid-sample, fps=$FPS)"
        return 0
    fi

    local CORES; CORES=$(awk -v a="$C0" -v b="$C1" -v t="$SAMPLE_S" 'BEGIN{printf "%.3f",(b-a)/100.0/t}')
    echo "  $tag  cores $CORES  fps $FPS  temp $(temp_)C  fatal $(sh_ "grep -acE 'Dead FIFO|fatal error' $FILES/cache/RPCSX.log")   [$cfgline]"
    printf '%s\t%s\t%s\n' "$cfgline" "$FPS" "$CORES" >> "$RESULTS"
}

RESULTS=$(mktemp)
echo "A: $ARM_A"; echo "B: $ARM_B"; echo "rounds=$ROUNDS sample=${SAMPLE_S}s gate>=${TARGET_FPS}fps"; echo
for r in $(seq 1 "$ROUNDS"); do run_arm "$ARM_A" "r${r}A"; run_arm "$ARM_B" "r${r}B"; done
echo; echo "=== summary (valid arms only) ==="
awk -F'\t' '{c[$1]+=$3; f[$1]+=$2; n[$1]++
             if(!(($1) in lo)||$3<lo[$1])lo[$1]=$3
             if(!(($1) in hi)||$3>hi[$1])hi[$1]=$3}
     END{for(k in n) printf "%-34s fps %.2f  cores %.3f [%.3f..%.3f]  n=%d\n",k,f[k]/n[k],c[k]/n[k],lo[k],hi[k],n[k]}' "$RESULTS"
rm -f "$RESULTS"
