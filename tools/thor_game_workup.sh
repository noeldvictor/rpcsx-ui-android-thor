#!/usr/bin/env bash
#
# One command that triages a title on the Thor and, if it is healthy, measures
# it. Triage and speed are one pipeline here on purpose: this project spent a
# week treating Transformers as a slow title when it was a HANGING title, and
# every speed number taken in that week was a number for a dead emulator.
#
#   tools/thor_game_workup.sh BLUS30357 "/storage/.../game.iso"
#   tools/thor_game_workup.sh --repeats 3 --profile BLUS30161 "/storage/.../es.iso"
#
# It refuses rather than guesses. Every refusal below is a failure this repo
# has already paid for at least once; see docs/arm64/ and CLAUDE.md.
#
# It NEVER writes a shipped profile. It prints what it would suggest.
set -u

ADB="${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-192.168.1.3:5555}"
PKG=net.rpcsx.easy
FILES=/storage/emulated/0/Android/data/$PKG/files

WINDOW=150
REPEATS=0
DO_PROFILE=0
COOL_C=62
EXTRA_CFG=""

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    echo
    echo "options: --window N  --repeats N  --profile  --cool C  --config 'Key: Val;Key: Val'"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
    --window)  WINDOW="$2"; shift 2 ;;
    --repeats) REPEATS="$2"; shift 2 ;;
    --profile) DO_PROFILE=1; shift ;;
    --cool)    COOL_C="$2"; shift 2 ;;
    --config)  EXTRA_CFG="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) break ;;
    esac
done

TITLE="${1:-}"; ISO="${2:-}"
[ -z "$TITLE" ] || [ -z "$ISO" ] && usage

CFG="$FILES/config/custom_configs/config_${TITLE}.yml"
LOG="$FILES/cache/RPCSX.log"

sh_()   { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'; }
# Read the cpu-1-* junction zones. A bare max over every thermal_zone reads a
# different sensor: all zones gave 63400 in the same minute cpu-1-* gave 84300.
temp_() { sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
lgrep() { sh_ "grep -ac '$1' $LOG"; }

# Is a MOVIE playing? Ask the emulator, do not read the frame rate.
#
# The frame rate is actively misleading: Transformers renders its cutscene at
# 120 to 133 FPS uncapped and its title screen at 30, so the HIGH number means a
# movie and not speed. A cutscene also cannot resolve a measurement -- one
# configuration here measured 3.78 and 5.89 cores on consecutive rounds because
# each run landed in a different scene.
#
# Needs the control API, which is debug builds only. If it is not reachable this
# returns "unknown", and an unknown is NOT treated as "no movie".
CTRL_PORT="${CTRL_PORT:-8099}"
scene_() {
    command -v curl >/dev/null 2>&1 || { echo unknown; return; }
    local r
    r=$(curl -s --max-time 4 "127.0.0.1:${CTRL_PORT}/scene" 2>/dev/null)
    case "$r" in
    *'"videoDecoding":true'*)  echo movie ;;
    *'"videoDecoding":false'*) echo not-movie ;;
    *)                          echo unknown ;;
    esac
}

BAK="$CFG.workup.bak"
HAD_CFG=0
cleanup() {
    sh_ "am force-stop $PKG; svc power stayon false" >/dev/null 2>&1
    if [ -n "$EXTRA_CFG" ]; then
        # Restore by moving the file back, never by rebuilding its text. A
        # previous harness rebuilt a config with printf into `while read` and
        # silently dropped the only line, so every arm ran unset.
        if [ "$HAD_CFG" = "1" ]; then
            sh_ "run-as $PKG sh -c 'mv $BAK $CFG'" >/dev/null 2>&1
            echo "cleanup: restored the original config from the on-device backup"
        else
            sh_ "run-as $PKG rm -f $CFG $BAK" >/dev/null 2>&1
            echo "cleanup: removed the temporary config, app regenerates the shipped profile"
        fi
    fi
    # A harness that leaves properties set poisons the NEXT measurement.
    for p in thermal_guard_c spu_accurate_reservations rsx_fifo_pause_ladder guest_preflight; do
        sh_ "setprop debug.rpcsx.thor.$p ''" >/dev/null 2>&1
    done
}
trap cleanup EXIT INT TERM

say() { printf '%s\n' "$*"; }
hr()  { printf '%s\n' "------------------------------------------------------------"; }

############################################################################
# 1. Preflight. A negative result from a rig you have not proved is working
#    is not a negative result.
############################################################################
hr; say "PREFLIGHT"

OK=$(sh_ "echo ok")
[ "$OK" != "ok" ] && { say "REFUSED: device unreachable at $SERIAL. An unreachable device"; say "         answers empty exactly like a dead process."; exit 2; }

BATT=$(sh_ "cat /sys/class/power_supply/battery/capacity")
case "$BATT" in ''|*[!0-9]*) say "REFUSED: cannot read battery"; exit 2 ;; esac
[ "$BATT" -lt 20 ] && { say "REFUSED: battery ${BATT}%. The device is shared; leave it usable."; exit 2; }

# The Thor is shared with a Xenia session. Do not force-stop their package;
# do notice when they are loading the device, because a hot contended device
# measures throttling.
XEN=$(sh_ "pidof jp.xenia.emulator.github.debug")
[ -n "$XEN" ] && say "WARNING: the other session's emulator is running (pid $XEN). Numbers"
[ -n "$XEN" ] && say "         taken now measure contention. Do NOT force-stop their package."

# The dev-core override makes an adb install change nothing that runs.
OVR=$(sh_ "run-as $PKG ls files/dev-core/active-core.json 2>/dev/null")
[ -n "$OVR" ] && { say "REFUSED: a dev-core override is active. The APK you installed is not"; say "         the core that runs. Rename active-core.json first."; exit 2; }

say "battery=${BATT}%  temp=$(temp_)C  title=$TITLE"

# A Thor with its screen off cannot boot a title: a SurfaceView measured 0x0
# never creates a surface, and the renderer waits forever.
sh_ "input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null

if [ -n "$EXTRA_CFG" ]; then
    if [ -n "$(sh_ "run-as $PKG ls $CFG 2>/dev/null")" ]; then
        sh_ "run-as $PKG sh -c 'cp $CFG $BAK'" >/dev/null
        HAD_CFG=1
        say "backed up the existing config on device"
    fi
    say "applying --config: $EXTRA_CFG"
    # Build the config through run-as so the file belongs to the app. A file
    # written as shell is one the app cannot rewrite.
    LINES=""
    OLDIFS=$IFS; IFS=';'
    for kv in $EXTRA_CFG; do
        kv=$(printf '%s' "$kv" | sed 's/^ *//;s/ *$//')
        [ -n "$kv" ] && LINES="$LINES \\\"  $kv\\\""
    done
    IFS=$OLDIFS
    sh_ "run-as $PKG sh -c 'printf \"%s\n\" \
        \"# RPCSX_THOR_WORKUP_OVERRIDE\" \"Core:\" $LINES \
        \"Video:\" \"  Performance Overlay:\" \"    Enabled: true\" > $CFG'" >/dev/null
    say "readback:"; sh_ "run-as $PKG cat $CFG" | sed 's/^/  /'
fi

############################################################################
# 2. Boot and classify. Named causes, not "it did not work".
############################################################################
boot_once() {
    local tag="$1"
    local t0
    while :; do
        t0=$(temp_)
        case "$t0" in ''|*[!0-9]*) break ;; esac
        [ "$t0" -lt "$COOL_C" ] && break
        say "  cooling: ${t0}C >= ${COOL_C}C"
        sh_ "sleep 20" >/dev/null
    done

    sh_ "am force-stop $PKG; rm -f $LOG" >/dev/null
    LOGCAT_MARK=$(sh_ "date +%s")
    sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
         --es path '$ISO' --es titleId $TITLE --es thorDebugBootRequestId $tag \
         --ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false" >/dev/null
    sh_ "sleep $WINDOW" >/dev/null
}

classify() {
    local verdict="" fix="" sev="FAIL"

    local no_log; no_log=$(sh_ "ls $LOG 2>/dev/null")
    if [ -z "$no_log" ]; then
        say "VERDICT: INSTRUMENT-FAULT - no log was written at all."
        say "  This is not a statement about the game. The boot intent may have"
        say "  been rejected, or the app never started."
        return 1
    fi

    # An external force-stop leaves NO crash signature and is indistinguishable
    # from a clean exit. Check it before blaming any change.
    local ext; ext=$(sh_ "logcat -d -t 600 | grep -c 'Force stopping $PKG'")
    if [ "${ext:-0}" -gt 1 ]; then
        say "VERDICT: EXTERNAL-KILL - $PKG was force-stopped $ext times by"
        say "  ActivityManager. Another session is killing our package on a timer."
        say "  Stop debugging your own change. Any measurement here is void."
        return 1
    fi

    local spu_trap dead_fifo scudo surface fatal frames shader llvm
    spu_trap=$(lgrep 'ffdead')
    dead_fifo=$(lgrep 'Dead FIFO')
    scudo=$(lgrep 'Scudo')
    surface=$(lgrep 'Still waiting for a Surface')
    fatal=$(lgrep 'Fatal signal')
    shader=$(lgrep 'Compiling shaders')
    llvm=$(lgrep 'LLVM: Compiling module')
    frames=$(sh_ "grep -aoE '\([0-9.]+ FPS\)' $LOG | tail -1" | grep -oE '[0-9.]+')
    frames="${frames:-0}"

    say "signals: spu_trap=$spu_trap dead_fifo=$dead_fifo scudo=$scudo surface=$surface"
    say "         fatal=$fatal shader_compile=$shader ppu_compile=$llvm last_fps=$frames"

    if [ "${spu_trap:-0}" != "0" ]; then
        say "VERDICT: SPU-TRAP - the guest halted its own SPU."
        sh_ "grep -a 'SPU trap' $LOG | tail -4" | sed 's/^/  /'
        say "  0xffdeadXX is an emulator trap, not a wild pointer. +00 HALT means"
        say "  the guest ran HGT/HLGT/HEQ and stopped itself, so the emulator gave"
        say "  SPURS something it did not expect. A Dead FIFO after it is downstream."
        say "  NOT a settings problem. Do not sweep settings for it."
        return 1
    fi
    if [ "${dead_fifo:-0}" != "0" ]; then
        say "VERDICT: DEAD-FIFO - the RSX command queue died."
        say "  SUGGEST: 'RSX FIFO Accuracy: Atomic' and 'Driver Wake-Up Delay: 50'."
        say "  Check for an SPU trap first: if the SPU faulted before the RSX, the"
        say "  FIFO death is the symptom and Atomic only delays it."
        return 1
    fi
    if [ "${scudo:-0}" != "0" ]; then
        say "VERDICT: PRECOMPILE-OOM - Scudo aborted during PPU compile."
        say "  SUGGEST: adb shell setprop debug.rpcsx.thor.ppu_budget_mb 1536"
        say "  Scudo caps each size class at 256 MB regardless of free RAM, so this"
        say "  is concurrency, not footprint."
        return 1
    fi
    if [ "${surface:-0}" != "0" ]; then
        say "VERDICT: NO-SURFACE - the renderer never got a window."
        say "  SUGGEST: the screen was asleep. 'svc power stayon true' before the run."
        return 1
    fi
    if [ "${fatal:-0}" != "0" ]; then
        say "VERDICT: NATIVE-CRASH - a fatal signal was logged."
        sh_ "grep -a 'Fatal signal' $LOG | tail -3" | sed 's/^/  /'
        return 1
    fi

    local alive; alive=$(sh_ "pidof $PKG")
    if [ -z "$alive" ]; then
        say "VERDICT: DIED-SILENTLY - no crash signature and the process is gone."
        say "  A guard-page death inside SPU execution leaves no tombstone: the"
        say "  handler declines it, and ART kills the process reading guest"
        say "  registers as an ArtMethod*. Check the SPU gateway scratchpad size."
        return 1
    fi

    if [ "$(awk -v f="$frames" 'BEGIN{print (f<1)?1:0}')" = "1" ]; then
        if [ "${llvm:-0}" != "0" ]; then
            say "VERDICT: STILL-COMPILING - PPU precompile has not finished."
            say "  Not a fault. A cold first load can take ten minutes on a large"
            say "  EBOOT. Re-run with a warm cache or a longer --window."
        else
            local cores; cores=$(sh_ "cat /proc/$alive/stat" | awk '{print $14+$15}')
            say "VERDICT: HUNG - alive, zero frames, no fatal error logged."
            say "  cpu_jiffies=$cores. If CPU is high with no frames, SPU threads are"
            say "  spinning after something died. This is the Transformers shape and"
            say "  it reads as 'slow' until you check the frame counter."
        fi
        return 1
    fi

    if [ "${shader:-0}" != "0" ] && [ "$(awk -v f="$frames" 'BEGIN{print (f<15)?1:0}')" = "1" ]; then
        say "VERDICT: SHADER-STALL - rendering, but stalling on shader compiles."
        say "  SUGGEST: 'Shader Mode: Async with Shader Interpreter'. The default"
        say "  Async recompiler stalls the frame until a shader is ready."
        return 1
    fi

    local sc; sc=$(scene_)
    if [ "$sc" = "movie" ]; then
        say "VERDICT: HEALTHY, BUT A MOVIE IS PLAYING - ${frames} FPS, $(temp_)C."
        say "  The guest is decoding video. Do NOT measure this window: a cutscene"
        say "  cannot resolve an A/B, and its frame rate says nothing about speed."
        say "  Skip it with: curl -X POST 127.0.0.1:$CTRL_PORT/pad/press?buttons=START"
        return 0
    fi

    say "VERDICT: HEALTHY - ${frames} FPS, $(temp_)C. (scene: $sc)"
    return 0
}

hr; say "TRIAGE"
boot_once "workup"
if ! classify; then
    hr; say "Triage did not pass. Speed measurement skipped on purpose:"
    say "a number taken from a broken emulator is not a number."
    exit 1
fi

############################################################################
# 3. Steady state, repeated. A single sample is not a measurement.
############################################################################
[ "$REPEATS" -lt 1 ] && { hr; say "Done (triage only; pass --repeats N to measure)."; exit 0; }

hr; say "STEADY STATE  (repeats=$REPEATS, ${WINDOW}s each)"
say "Repeats measure THIS rig's noise floor. Any later claim must beat it."

RES=$(mktemp)
r=1
while [ "$r" -le "$REPEATS" ]; do
    [ "$r" -gt 1 ] && { boot_once "workup$r"; classify >/dev/null || { say "  r$r INVALID (triage regressed)"; r=$((r+1)); continue; }; }
    PID=$(sh_ "pidof $PKG")
    M=$(sh_ "grep -ac 'Frames:' $LOG")
    C0=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
    if [ "$DO_PROFILE" = "1" ] && [ "$r" = "1" ]; then
        say "  capturing a 25 s profile (run-as; perf_event_paranoid blocks the direct form)"
        sh_ "run-as $PKG /system/bin/simpleperf record -p $PID --duration 25 -g -f 1000 -o /data/data/$PKG/perf.data" >/dev/null 2>&1
    fi
    SC0=$(scene_)
    sh_ "sleep 40" >/dev/null
    SC1=$(scene_)
    # A sample that touched a movie is void. Say so and drop it, rather than
    # letting it average with the rest.
    if [ "$SC0" = "movie" ] || [ "$SC1" = "movie" ]; then
        say "  r$r VOID (a movie played during the sample; scene $SC0 -> $SC1)"
        r=$((r + 1))
        continue
    fi
    C1=$(sh_ "cat /proc/$PID/stat" | awk '{print $14+$15}')
    FPS=$(sh_ "grep -a 'Frames:' $LOG | tail -n +$((M+1))" | grep -oE '[0-9.]+ FPS' | grep -oE '^[0-9.]+' \
          | awk '{s+=$1;n++} END{if(n)printf "%.2f",s/n; else printf "0"}')
    CORES=$(awk -v a="$C0" -v b="$C1" 'BEGIN{printf "%.3f",(b-a)/100.0/40}')
    T=$(temp_)
    say "  r$r  fps $FPS  cores $CORES  temp ${T}C"
    printf '%s\t%s\n' "$FPS" "$CORES" >> "$RES"
    r=$((r+1))
done

hr; say "RESULT"
awk -F'\t' '{f+=$1; c+=$2; n++
     if(!lo||$2<lo)lo=$2; if(!hi||$2>hi)hi=$2
     if(!flo||$1<flo)flo=$1; if(!fhi||$1>fhi)fhi=$1}
     END{if(!n){print "  no valid samples"; exit}
         printf "  fps   %.2f [%.2f..%.2f]\n  cores %.3f [%.3f..%.3f]  n=%d\n",f/n,flo,fhi,c/n,lo,hi,n
         if(c/n>0) printf "  noise floor on cores: %.1f%%\n", (hi-lo)/(c/n)*100}' "$RES"
rm -f "$RES"

if [ "$DO_PROFILE" = "1" ]; then
    say
    say "  profile captured on device at /data/data/$PKG/perf.data"
    say "  pull with exec-out (adb shell cat corrupts it):"
    say "    adb -s $SERIAL exec-out run-as $PKG cat /data/data/$PKG/perf.data > perf.data"
    say "  then read docs/arm64/ 'profile-to-lever' in the thor-game-workup skill."
fi

hr
say "This tool proposes, it does not ship. Nothing was written to a game profile."
