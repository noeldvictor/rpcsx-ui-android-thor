#!/usr/bin/env bash
# Hunt FPS and heat on the RESTORED 3D COMBAT scene via SPU codegen settings.
#
# WHY THESE LEVERS. The combat profile is 54% JIT-generated GUEST code, 28.7%
# emulator, and only 2.3% GPU driver. The settings that change what the SPU
# recompiler EMITS are the only ones with a budget large enough to move frames.
#
# WHY PROPERTIES AND NOT THE CONFIG FILE. The debug-boot path applies a managed
# profile that REWRITES the per-title config, so an edit between arms does not
# survive the boot. Measured: it produced a 6.24 FPS "control" against a true
# 18.7, because dropping thorRequireManagedProfile to avoid the rewrite also
# means no profile is applied at all. The properties are read after the profile
# is applied and cannot be clobbered by it.
#
# WARM-UP BOOT PER ARM. Changing SPU codegen invalidates the SPU cache, so the
# first boot on a new setting recompiles and is not comparable.
#
# 3D COMBAT ONLY, gated on coresBusy>4.5. Intro runs measure Bink playback.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
PLAY=${PLAY:-90}
SHOTDIR=${SHOTDIR:-/c/Users/LEANER~1/AppData/Local/Temp/claude/C--Users-leanerdesigner-Documents-ps3-thor/a465ad58-bbf5-40bb-8b42-e185135b6729/scratchpad/shots}
mkdir -p "$SHOTDIR"
ARMTAG=arm
COOL=${COOL:-50}
XF=""
VF=""

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
# Retry, and re-establish the forward. A single curl returns EMPTY transiently -
# observed repeatedly - and an empty read parsed as cores=0 makes the combat gate
# reject a run that was in combat. That is how an earlier arm reported
# "gate failed: cores=0.000" while the game was actually running at 18.34 FPS.
api(){
  local out i
  for i in 1 2 3; do
    out=$(curl -s --max-time 8 "127.0.0.1:8099/$1" 2>/dev/null)
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    MSYS_NO_PATHCONV=1 "$ADB" -s "$W" forward tcp:8099 tcp:8099 >/dev/null 2>&1
    sleep 2
  done
  printf ''
}
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; P=$(sh_ "pidof $PKG"); [ -n "$P" ] && sh_ "kill -9 $P" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }

cleanup(){
  hardstop
  sh_ "setprop debug.rpcsx.thor.spu_xfloat ''; setprop debug.rpcsx.thor.spu_verification ''; setprop debug.rpcsx.thor.thermal_abort_c ''; svc power stayon false" >/dev/null 2>&1
  echo "cleanup: props cleared, temp=$(t_)C"
}
trap cleanup EXIT INT TERM

one_run(){
  local tag="$1"
  hardstop

  # Push the savestate while the app is STOPPED.
  #
  # Pushing it into a RUNNING emulator truncates: the app holds the slot open
  # and the copy lands short. Measured as local=123821207 against
  # device=28180480, three attempts in a row, and the vault correctly refuses to
  # load a short file. With the app stopped the same copy completes every time.
  bash "$REPO/tools/thor_savestate_vault.sh" push BLUS30357 2>&1 | grep -E "MATCH|MISMATCH|REFUSED" | sed 's/^/   /'

  T=$(t_); w=0
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 360 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done
  TSTART=$(t_)

  sh_ "setprop debug.rpcsx.thor.spu_xfloat '$XF'" >/dev/null
  sh_ "setprop debug.rpcsx.thor.spu_verification '$VF'" >/dev/null
  sh_ "rm -f $R/cache/RPCSX.log; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId sp \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

  w=0; ok=0
  while [ "$w" -lt 360 ]; do
    sh_ "sleep 10" >/dev/null; w=$((w+10))
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
    case "${F:-0}" in ''|0|0.0*) ;; *) ok=1; break;; esac
  done
  [ "$ok" = "0" ] && { echo "   $tag SKIP (never rendered)"; return; }

  # Load only - the file is already in place from before the boot.
  echo "   loadstate: $(api loadstate | head -c 60)"

  # THE GATE, and it now proves the scene rather than inferring it.
  #
  # cores>4.5 alone does separate combat from a movie - movies run 1.2 to 2.6
  # cores - but it is an inference. The scene probe says outright whether a
  # video file is open, so require BOTH: busy cores AND no video decoding.
  CORES=0; VID=""; OPEN=""; w=0
  while [ "$w" -lt 120 ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
    ST=$(api status)
    VID=$(printf '%s' "$ST" | grep -oE '"videoDecoding":[a-z]+' | cut -d: -f2)
    OPEN=$(printf '%s' "$ST" | grep -oE '"videoFilesOpen":[0-9]+' | cut -d: -f2)
    if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" = "1" ] && [ "${VID:-true}" = "false" ] && [ "${OPEN:-1}" = "0" ]; then
      break
    fi
  done
  if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ] || [ "${VID:-true}" != "false" ] || [ "${OPEN:-1}" != "0" ]; then
    echo "   $tag INVALID (not a 3D scene: cores=$CORES videoDecoding=${VID:-?} videoFilesOpen=${OPEN:-?})"; return
  fi

  # Screenshot the thing being measured, so the claim is auditable.
  sh_ "screencap -p /data/local/tmp/scene_$tag.png" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" pull "/data/local/tmp/scene_$tag.png" "$SHOTDIR/scene_${ARMTAG}_$tag.png" >/dev/null 2>&1

  local fs=0 cs=0 n=0
  for s in 1 2 3; do
    sh_ "sleep $((PLAY/3))" >/dev/null
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2); F=${F:-0}
    C=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); C=${C:-0}
    fs=$(awk -v a="$fs" -v b="$F" 'BEGIN{print a+b}')
    cs=$(awk -v a="$cs" -v b="$C" 'BEGIN{print a+b}')
    n=$((n+1))
  done
  CPU=$(sh_ "grep -a 'PERF: CPU Usage' $R/cache/RPCSX.log | tail -1 | grep -o 'Total: [0-9.]*%'")
  echo "   $tag scene=3D(video=$VID,open=$OPEN) fps=$(awk -v s="$fs" -v n="$n" 'BEGIN{printf "%.2f", s/n}') cores=$(awk -v s="$cs" -v n="$n" 'BEGIN{printf "%.3f", s/n}') cpu=${CPU:-?} Tstart=${TSTART}C Tend=$(t_)C"
}

arm(){
  ARMTAG=$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')
  echo
  echo "########## $1 ##########"
  echo "   spu_xfloat='${XF:-unset}' spu_verification='${VF:-unset}'"
  one_run "warmup(discarded)"
  one_run "MEASURED"
}

echo "battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")% temp=$(t_)C play=${PLAY}s"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null

XF=""  VF=""  arm "CONTROL (config default, approximate)"
XF="2" VF=""  arm "xfloat = relaxed"
XF="3" VF=""  arm "xfloat = inaccurate"
XF=""  VF="0" arm "SPU verification OFF"
echo
echo "=== done ==="
