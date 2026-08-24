#!/usr/bin/env bash
# Which emulator threads are BUSY during 3D combat, and which are idle.
#
# Everything so far says the frame is serialised rather than compute bound: CPU
# total sits at 63 to 70% with about 5 of 8 cores busy, and removing an 18% spin
# cost changed nothing. That is an inference. This measures it: per-thread CPU
# from /proc/PID/task/*/stat, which needs no server and cannot return empty the
# way the control API does.
#
# If a few SPU threads are hot and the rest idle, the constraint is dispatch or
# the SPURS limiter. If all six are evenly busy, the constraint is SPU
# throughput and the recompiler is the only lever left.
set -u
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
OUT="$(dirname "$0")"
SEC=${SEC:-10}

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
api(){ local o i; for i in 1 2 3; do o=$(curl -s --max-time 8 "127.0.0.1:8099/$1" 2>/dev/null); [ -n "$o" ] && { printf '%s' "$o"; return; }; MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1; sleep 2; done; printf ''; }
hardstop(){ for _h in 1 2 3 4 5; do sh_ "am force-stop $PKG" >/dev/null 2>&1; sh_ "sleep 2" >/dev/null; done; }
cleanup(){ hardstop; sh_ "svc power stayon false; setprop debug.rpcsx.thor.thermal_abort_c ''" >/dev/null 2>&1; echo "cleanup temp=$(t_)C"; }
trap cleanup EXIT INT TERM

echo "battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")% temp=$(t_)C"
sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null
hardstop
T=$(t_); w=0
while [ -n "$T" ] && [ "$T" -ge 60 ] && [ "$w" -lt 200 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done

bash "$REPO/tools/thor_savestate_vault.sh" push BLUS30357 2>&1 | grep -E "MATCH|MISMATCH" | sed 's/^/  /'
sh_ "rm -f $R/cache/RPCSX.log; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
     --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId census \
     --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
MSYS_NO_PATHCONV=1 "$ADB" -s $W forward tcp:8099 tcp:8099 >/dev/null 2>&1

w=0
while [ "$w" -lt 300 ]; do
  sh_ "sleep 10" >/dev/null; w=$((w+10))
  F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
  case "${F:-0}" in ''|0|0.0*) ;; *) break;; esac
done

LOADED=0
for l in 1 2 3; do
  LS=$(api loadstate); echo "  loadstate: $(printf '%s' "$LS" | head -c 30)"
  case "$LS" in *'"ok":true'*) LOADED=1; break;; esac
  sh_ "sleep 8" >/dev/null
done
[ "$LOADED" = "1" ] || { echo "ABORT: savestate never loaded"; exit 1; }

CORES=0; w=0
while [ "$w" -lt 120 ]; do
  sh_ "sleep 15" >/dev/null; w=$((w+15))
  CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
  ST=$(api status)
  VID=$(printf '%s' "$ST" | grep -oE '"videoDecoding":[a-z]+' | cut -d: -f2)
  [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" = "1" ] && [ "${VID:-true}" = "false" ] && break
done
if [ "$(awk -v c="$CORES" 'BEGIN{print (c>4.5)?1:0}')" != "1" ]; then
  echo "ABORT: not in 3D combat (cores=$CORES video=${VID:-?})"; exit 1
fi
echo "in 3D combat: cores=$CORES fps=$(api device | grep -oE '\"fps\":[0-9.]+' | cut -d: -f2) temp=$(t_)C"

PID=$(sh_ "pidof $PKG")
snap(){ sh_ "for t in /proc/$PID/task/*; do n=\$(cat \$t/comm 2>/dev/null); j=\$(awk '{print \$14+\$15}' \$t/stat 2>/dev/null); echo \"\$j \$n\"; done"; }
snap > "$OUT/tk1.txt"
sh_ "sleep $SEC" >/dev/null
snap > "$OUT/tk2.txt"

echo
echo "=== per-thread CPU over ${SEC}s (jiffies; 100 = one full core-second) ==="
python - "$(cygpath -m "$OUT/tk1.txt")" "$(cygpath -m "$OUT/tk2.txt")" "$SEC" <<'PY'
import sys
def load(p):
    d={}
    for ln in open(p, encoding='utf-8', errors='replace'):
        parts=ln.split(None,1)
        if len(parts)==2:
            try: d[parts[1].strip()]=int(parts[0])
            except ValueError: pass
    return d
a=load(sys.argv[1]); b=load(sys.argv[2]); sec=float(sys.argv[3])
rows=sorted(((b[k]-a.get(k,b[k]),k) for k in b), reverse=True)
tot=sum(d for d,_ in rows if d>0)
print('  %-28s %8s %8s' % ('thread','jiffies','%core'))
for d,k in rows[:18]:
    if d<=0: break
    print('  %-28s %8d %7.1f%%' % (k,d,100.0*d/(sec*100)))
print('  %-28s %8d  = %.2f cores busy' % ('TOTAL',tot,tot/(sec*100)))
PY
