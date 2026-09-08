#!/usr/bin/env bash
# Transformers (BLUS30357) 3D-combat DIAGNOSTIC round, 2026-09-07.
#
# One cool device round that answers the questions docs/arm64/transformers-30fps.md
# left open, each as ONE boot on the restored combat savestate:
#
#   * frame INTERVAL distribution (FT on the "Frames:" line), so 20 FPS can be
#     read as "locked to every third vblank" or as "a real throughput gap"
#   * where every PPU thread is parked between frames (ppu_pc_census)
#   * cluster frequencies during the scene, so 95 C can be read as throttling
#     or not
#   * levers never measured on this title: lv2_spin=50, Relaxed ZCULL Sync,
#     reduced loops with the SPU profiler proving whether chunk-0x0f3c4 matched
#
# Every rule below comes from a measurement that was wrong here before. See
# .agents/skills/thor-measurement-validity/SKILL.md and tools/thor_spu_speed_arms.sh,
# which this script follows: properties not config, savestate pushed while the
# app is STOPPED, loadstate must return ok:true, the scene is gated on
# coresBusy>4.5 AND no video decoding, a screenshot is taken and SCORED, and the
# lever is read back off the device and printed with every arm.
#
# Usage:
#   tools/thor_transformers_diag_round.sh "name|prop=value;prop=value" ...
#   A name starting with "warm:" runs one discarded warm-up boot first (use it
#   for anything that changes SPU codegen: spu_prof, spu_reduced_loop_emit).
#   An empty spec ("control|") sets nothing.
#
# Environment: W (adb serial), PLAY (measured seconds, default 60), COOL (start
# temperature ceiling, default 55), OUTDIR (capture directory).
set -u

ADB=${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}
W=${W:-c3ca0370}
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
ISO="/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
PLAY=${PLAY:-60}
COOL=${COOL:-55}
# Scene gate on coresBusy. 4.5 separates combat from the movies; an arm that
# removes work (disabled occlusion queries ran at 4.0) needs a lower gate and a
# screenshot check instead.
GATE_CORES=${GATE_CORES:-4.5}
OUTDIR=${OUTDIR:-$REPO/debug-captures/$(date +%Y%m%d-%H%M%S)-transformers-diag-round}
mkdir -p "$OUTDIR"

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s "$W" shell "$1" 2>&1 | tr -d '\r'; }
t_(){ sh_ "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/temp 2>/dev/null); n=\$(cat \$z/type 2>/dev/null); case \$n in cpu*) [ -n \"\$t\" ] && echo \$((t/1000));; esac; done" | sort -rn | head -1; }
freq_(){ sh_ "for p in /sys/devices/system/cpu/cpufreq/policy*; do f=\$(cat \$p/scaling_cur_freq 2>/dev/null); echo -n \"\$(basename \$p)=\$((f/1000)) \"; done"; }
# GPU busy time. /sys/class/kgsl/kgsl-3d0/gpubusy is a cumulative "busy total"
# pair that resets on read, so read once to zero it at the window start and once
# at the end. Nothing had measured this on Transformers before 2026-09-07; the
# "GPU is idle" claim rested on the driver's CPU share and the guest's RSX%.
gpu_zero_(){ sh_ "cat /sys/class/kgsl/kgsl-3d0/gpubusy" >/dev/null 2>&1; }
gpu_busy_(){ sh_ "b=\$(cat /sys/class/kgsl/kgsl-3d0/gpubusy 2>/dev/null); set -- \$b; [ -n \"\$2\" ] && [ \"\$2\" -gt 0 ] && echo \"gpu_busy=\$((100*\$1/\$2))% gpu_clk=\$(( \$(cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null || echo 0) / 1000000 ))MHz\" || echo gpu_busy=na"; }
fan_(){ sh_ "settings get system fan_mode"; }
# Core residency of the chain threads: field 39 of /proc/PID/task/T/stat, ten
# samples 200 ms apart, printed as a per-thread core histogram. A placement arm
# whose pinned thread is not 100 percent inside its mask is void.
resid_(){
  local pid="$1"
  sh_ "for i in 1 2 3 4 5 6 7 8 9 10; do for t in /proc/$pid/task/*; do n=\$(cat \$t/comm 2>/dev/null); case \"\$n\" in rsx::thread|PPU\[0x100000b\]*|PPU\[0x1000000\]*|SPU\[0x0000100\]*|SPU\[0x1000100\]*) echo \"\$n \$(sed 's/^.*) //' \$t/stat 2>/dev/null | awk '{print \$37}')\";; esac; done; sleep 0.2; done"   | awk '{k=$1; c=$2; h[k" cpu"c]++; n[k]++} END {for (x in h) {split(x, a, " "); printf "%s %s=%d%% ", a[1], a[2], 100*h[x]/n[a[1]]}; print ""}' | tr -s ' '
}
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

# Every property any arm names, plus the abort guard, so cleanup can clear them all.
ALLPROPS="debug.rpcsx.thor.thermal_abort_c"
for a in "$@"; do
  spec="${a#*|}"
  for kv in $(printf '%s' "$spec" | tr ';' ' '); do
    [ -n "$kv" ] && ALLPROPS="$ALLPROPS ${kv%%=*}"
  done
done
ALLPROPS=$(printf '%s\n' $ALLPROPS | sort -u | tr '\n' ' ')

clear_props(){ for p in $ALLPROPS; do sh_ "setprop $p ''" >/dev/null 2>&1; done; }
readback(){ local o="" p v; for p in $ALLPROPS; do v=$(sh_ "getprop $p"); [ -n "$v" ] && o="$o${p##*.}=$v "; done; printf '%s' "${o:-<none set>}"; }

cleanup(){
  hardstop
  clear_props
  sh_ "svc power stayon false" >/dev/null 2>&1
  echo "cleanup: props cleared [$(readback)] temp=$(t_)C fan_mode=$(fan_) pid='$(sh_ "pidof $PKG")'"
}
trap cleanup EXIT INT TERM

score_shot(){
  # Distinct colours and byte size. A black frame is ~29 KB with ~160 colours; a
  # drawn combat frame is ~2 MB with 16,000+ colours.
  python - "$1" <<'PY'
import sys, os
p=sys.argv[1]
try:
    size=os.path.getsize(p)
except OSError:
    print("shot=MISSING"); sys.exit(0)
colours="n/a"
try:
    from PIL import Image
    im=Image.open(p).convert("RGB")
    im=im.resize((im.width//4, im.height//4))
    colours=len(set(im.getdata()))
except Exception:
    pass
verdict = "DRAWN" if (size>300000 or (isinstance(colours,int) and colours>4000)) else "BLANK?"
print(f"shot={verdict} bytes={size} colours={colours}")
PY
}

summarize_log(){
  # $1 = pulled RPCSX.log, $2 = tag
  python - "$1" "$2" <<'PY'
import sys, re, collections
path, tag = sys.argv[1], sys.argv[2]
try:
    txt=open(path, encoding='utf-8', errors='replace').read()
except OSError:
    print("   log: MISSING"); sys.exit(0)
lines=txt.splitlines()
fatal=[l for l in lines if re.search(r'fatal error|Dead FIFO|Access violation|SPU trap|ENGAGED|thermal abort', l, re.I)]
print(f"   log lines={len(lines)} fatal/guard hits={len(fatal)}")
for l in fatal[:6]: print("     !", l[-160:])
forced=[l for l in lines if 'Thor:' in l and ('forced' in l or 'set to' in l or 'ignoring' in l or 'applied' in l)]
for l in forced[:12]: print("     lever:", l.split('Thor:',1)[1].strip()[:140])
frames=[l for l in lines if 'Frames:' in l]
audit=[l for l in lines if 'Thor RSX Auditor: frames=' in l]
if audit:
    print(f"   RSX auditor lines={len(audit)}; last 2 (per report interval):")
    for l in audit[-2:]:
        m=re.search(r'frames=(\d+) submits=(\d+).*?rp_begin=(\d+) rp_end=(\d+) rp_break=(\d+) rp_break\(g/b/i/t\)=(\S+) barriers\(g/b/i/t/all\)=(\S+)', l)
        if m:
            f=int(m.group(1)) or 1
            print(f"     frames={f} rp/frame={int(m.group(3))/f:.1f} submits/frame={int(m.group(2))/f:.2f} breaks/frame={int(m.group(5))/f:.1f} break(g/b/i/t)={m.group(6)} barriers(g/b/i/t/all)={m.group(7)}")
        else: print('     ', l[-200:])
print(f"   Frames lines={len(frames)}; last 6:")
for l in frames[-6:]:
    m=re.search(r'Frames:.*', l); print("     ", m.group(0)[:230] if m else l[-200:])
# PPU census summary, combat window only: from the first Frames line whose
# interval median is 44 ms or more (the menu before the restore runs at 33 ms).
def tsec(l):
    mm=re.search(r' (\d+):(\d\d):(\d\d)\.(\d+) ',l)
    return int(mm.group(1))*3600+int(mm.group(2))*60+int(mm.group(3))+int(mm.group(4)[:3])/1000 if mm else None
start=None
for l in lines:
    if 'Frames:' in l and 'FT(ms) p50=' in l and float(re.search(r'p50=([0-9.]+)',l).group(1))>=44:
        start=(tsec(l) or 10)-10; break
cen=collections.defaultdict(lambda: {'n':0,'cia':collections.Counter(),'state':collections.Counter()})
for l in lines:
    if start is not None and (tsec(l) or 0) < start: continue
    # Thread names carry spaces ("PPU[0x1000000] main_thread"), so match lazily
    # up to " cia=". `func=` names the syscall or HLE function; older cores omit it.
    m=re.search(r'Thor PPU PC: id=0x([0-9a-f]+) (.*?) cia=0x([0-9a-f]+) lr=0x([0-9a-f]+) sp=0x[0-9a-f]+ r3=0x[0-9a-f]+ state=0x([0-9a-f]+)(?: func=(\S+))?', l)
    if m:
        k=m.group(2); d=cen[k]; d['n']+=1; d['cia'][(m.group(3),m.group(4),m.group(6) or '-')]+=1; d['state'][m.group(5)]+=1
if cen:
    print(f"   PPU census: {sum(d['n'] for d in cen.values())} samples over {len(cen)} threads")
    for k,d in sorted(cen.items(), key=lambda kv:-kv[1]['n'])[:14]:
        top=' '.join(f"cia={c}/lr={lr}/{f}:{n}" for (c,lr,f),n in d['cia'].most_common(3))
        st=' '.join(f"{s}:{n}" for s,n in d['state'].most_common(3))
        print(f"     {k:<34} n={d['n']:<4} {top}  state {st}")
# SPU profiler chart for SPU0
blk=None
for i,l in enumerate(lines):
    if 'Thread "SPU[0x0000100]' in l and 'samples' in l:
        blk=i
if blk is not None:
    print("   SPU0 profiler (last print):", lines[blk].split(']:',1)[-1].strip()[:120])
    for l in lines[blk+1:blk+8]:
        if 'chunk-' in l or 'key-' in l: print("     ", l.strip()[:120])
        else: break
PY
}

pull_log(){
  local tag="$1"
  # exec-out, not adb pull: with MSYS path conversion off, adb.exe receives the
  # /c/... local path literally and writes nothing (the first round lost every
  # log and screenshot this way).
  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" exec-out "cat $R/cache/RPCSX.log" > "$OUTDIR/RPCSX_$tag.log" 2>/dev/null
  sh_ "logcat -d" > "$OUTDIR/logcat_$tag.txt" 2>/dev/null
  sh_ "logcat -b crash -d" > "$OUTDIR/logcat_crash_$tag.txt" 2>/dev/null
  summarize_log "$OUTDIR/RPCSX_$tag.log" "$tag"
}

one_run(){
  local name="$1" spec="$2" tag="$3"
  hardstop
  clear_props

  # Savestate pushed while STOPPED (a running app truncates the copy).
  SERIAL="$W" bash "$REPO/tools/thor_savestate_vault.sh" push BLUS30357 2>&1 | grep -E "MATCH|MISMATCH|REFUSED" | sed 's/^/   vault: /'

  local T w=0
  T=$(t_)
  while [ -n "$T" ] && [ "$T" -ge "$COOL" ] && [ "$w" -lt 480 ]; do sh_ "sleep 15" >/dev/null; w=$((w+15)); T=$(t_); done
  local TSTART; TSTART=$(t_)

  sh_ "setprop debug.rpcsx.thor.thermal_abort_c 97" >/dev/null
  local old_ifs="$IFS" kv; IFS=';'
  for kv in $spec; do [ -n "$kv" ] && sh_ "setprop ${kv%%=*} '${kv#*=}'" >/dev/null; done
  IFS="$old_ifs"
  echo "   props: [$(readback)] Tstart=${TSTART}C fan_mode=$(fan_) battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")%"

  sh_ "rm -f $R/cache/RPCSX.log; logcat -c; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh_ "am start -a net.rpcsx.THOR_DEBUG_BOOT -n $PKG/net.rpcsx.MainActivity \
       --es path '$ISO' --es titleId BLUS30357 --es thorDebugBootRequestId diag$tag \
       --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true" >/dev/null
  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" forward tcp:8099 tcp:8099 >/dev/null 2>&1

  w=0; local ok=0 F
  while [ "$w" -lt 420 ]; do
    sh_ "sleep 10" >/dev/null; w=$((w+10))
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2)
    case "${F:-0}" in ''|0|0.0*) ;; *) ok=1; break;; esac
  done
  if [ "$ok" = "0" ]; then echo "   $tag SKIP (never rendered in ${w}s) temp=$(t_)C"; pull_log "$tag"; return; fi
  echo "   first frame after ${w}s"

  # REQUIRE ok:true. A failed load measures a lighter scene at ~29 FPS.
  # Five attempts, 12 s apart. The first round needed the THIRD attempt on two
  # of three arms and saw empty replies while a load was still in flight.
  local LOADED=0 LS _l
  for _l in 1 2 3 4 5; do
    LS=$(api loadstate)
    echo "   loadstate: $(printf '%s' "$LS" | head -c 60)"
    case "$LS" in *'"ok":true'*) LOADED=1; break;; esac
    sh_ "sleep 12" >/dev/null
  done
  if [ "$LOADED" != "1" ]; then echo "   $tag INVALID (savestate never loaded)"; pull_log "$tag"; return; fi

  local CORES=0 VID="" OPEN="" ST
  w=0
  while [ "$w" -lt 150 ]; do
    sh_ "sleep 15" >/dev/null; w=$((w+15))
    CORES=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); CORES=${CORES:-0}
    ST=$(api status)
    VID=$(printf '%s' "$ST" | grep -oE '"videoDecoding":[a-z]+' | cut -d: -f2)
    OPEN=$(printf '%s' "$ST" | grep -oE '"videoFilesOpen":[0-9]+' | cut -d: -f2)
    if [ "$(awk -v c="$CORES" -v g="$GATE_CORES" 'BEGIN{print (c>g)?1:0}')" = "1" ] && [ "${VID:-true}" = "false" ] && [ "${OPEN:-1}" = "0" ]; then break; fi
  done
  if [ "$(awk -v c="$CORES" -v g="$GATE_CORES" 'BEGIN{print (c>g)?1:0}')" != "1" ] || [ "${VID:-true}" != "false" ] || [ "${OPEN:-1}" != "0" ]; then
    echo "   $tag INVALID (not 3D combat: cores=$CORES videoDecoding=${VID:-?} videoFilesOpen=${OPEN:-?})"; pull_log "$tag"; return
  fi
  echo "   in 3D combat after ${w}s: cores=$CORES temp=$(t_)C"

  sh_ "screencap -p /data/local/tmp/scene_$tag.png" >/dev/null 2>&1
  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" exec-out "cat /data/local/tmp/scene_$tag.png" > "$OUTDIR/scene_$tag.png" 2>/dev/null
  echo "   $(score_shot "$OUTDIR/scene_$tag.png")"

  local fs=0 cs=0 n=0 s C
  local PIDNOW; PIDNOW=$(sh_ "pidof $PKG"); [ -n "$PIDNOW" ] && echo "   residency: $(resid_ "$PIDNOW")"
  gpu_zero_
  for s in 1 2 3; do
    sh_ "sleep $((PLAY/3))" >/dev/null
    F=$(api device | grep -oE '"fps":[0-9.]+' | cut -d: -f2); F=${F:-0}
    C=$(api device | grep -oE '"coresBusy":[0-9.]+' | cut -d: -f2); C=${C:-0}
    echo "   sample $s: fps=$F cores=$C temp=$(t_)C $(gpu_busy_) freq(MHz) $(freq_)"
    fs=$(awk -v a="$fs" -v b="$F" 'BEGIN{print a+b}'); cs=$(awk -v a="$cs" -v b="$C" 'BEGIN{print a+b}'); n=$((n+1))
  done
  local CPU; CPU=$(sh_ "grep -a 'PERF: CPU Usage' $R/cache/RPCSX.log | tail -1 | grep -o 'Total: [0-9.]*%'")
  local PID; PID=$(sh_ "pidof $PKG")
  if [ -z "$PID" ]; then
    echo "   PROCESS DIED during the window. crash buffer:"
    sh_ "logcat -b crash -d 2>/dev/null | grep -a -E 'Fatal signal|Abort message|backtrace|pid:' | head -6" | sed 's/^/     /'
    sh_ "logcat -d 2>/dev/null | grep -a -E 'lowmemorykiller|am_kill|Killing.*rpcsx|has died' | tail -3" | sed 's/^/     /'
  fi
  local FPS_AVG CORES_AVG
  FPS_AVG=$(awk -v s="$fs" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  CORES_AVG=$(awk -v s="$cs" -v n="$n" 'BEGIN{printf "%.3f", s/n}')
  echo "   RESULT $tag [$name] fps=$FPS_AVG cores=$CORES_AVG cpu=${CPU:-?} Tstart=${TSTART}C Tend=$(t_)C pid_alive=${PID:+yes}${PID:-NO}"
  printf '%s\t%s\t%s\t%s\n' "$name" "$FPS_AVG" "$CORES_AVG" "$(t_)" >> "$OUTDIR/results.tsv"

  # For a profiler arm, give cpu_prof time to print its chart before the stop.
  case "$spec" in *spu_prof=1*) sh_ "sleep 12" >/dev/null;; esac
  pull_log "$tag"
}

echo "round: $(date) device=$W battery=$(sh_ "cat /sys/class/power_supply/battery/capacity")% temp=$(t_)C fan_mode=$(fan_) play=${PLAY}s cool<${COOL}C out=$OUTDIR"
echo "props in play: $ALLPROPS"
i=0
for a in "$@"; do
  name="${a%%|*}"; spec="${a#*|}"; i=$((i+1))
  echo
  echo "########## $name ##########"
  echo "   spec: '${spec:-<none>}'"
  case "$name" in
    warm:*) name="${name#warm:}"; one_run "$name (WARM-UP, discarded)" "$spec" "w$i";;
  esac
  one_run "$name" "$spec" "a$i"
done
echo
echo "=== results ($OUTDIR/results.tsv) ==="
[ -f "$OUTDIR/results.tsv" ] && cat "$OUTDIR/results.tsv"
