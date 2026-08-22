#!/usr/bin/env bash
set -uo pipefail
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
R=/storage/emulated/0/Android/data/net.rpcsx.easy/files
ISO="/storage/2664-21DE/Roms/ps3/Eternal Sonata (USA) (En,Fr).iso"
SP="/c/Users/LEANER~1/AppData/Local/Temp/claude/C--Users-leanerdesigner-Documents-ps3-thor/a465ad58-bbf5-40bb-8b42-e185135b6729/scratchpad"
sh() { MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$@" 2>/dev/null | tr -d '\r'; }
cleanup() { sh "killall yes 2>/dev/null" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
cleanup
arm() {
  local apk=$1 label=$2
  sh "am force-stop net.rpcsx.easy; killall yes 2>/dev/null" >/dev/null
  "$ADB" -s $W install -r "$apk" >/dev/null 2>&1 || { echo "$label: install failed"; return 1; }
  sh "rm -f $R/cache/RPCSX.log; input keyevent KEYCODE_WAKEUP; svc power stayon true" >/dev/null
  sh "am start -a net.rpcsx.THOR_DEBUG_BOOT -n net.rpcsx.easy/net.rpcsx.MainActivity --es path '$ISO' --es titleId BLUS30161 --es thorDebugBootRequestId $label --ez thorRequireManagedProfile true --ez thorReplaceCustomProfile false" >/dev/null
  local w=0
  while ! sh "grep -c '0:02:' $R/cache/RPCSX.log 2>/dev/null" | grep -qv '^0$'; do
    sh "sleep 5" >/dev/null; w=$((w+5)); [ $w -gt 400 ] && { echo "$label: no 0:02:"; return 1; }
  done
  for k in 1 2 3 4 5 6; do sh "nohup yes >/dev/null 2>&1 &" >/dev/null; done
  sh "sleep 8" >/dev/null
  local L; L=$(sh "dumpsys SurfaceFlinger --list | grep 'RPCSXActivity](BLAST)'" | head -1)
  sh "dumpsys SurfaceFlinger --latency-clear '$L'" >/dev/null
  sh "sleep 15; dumpsys SurfaceFlinger --latency '$L'" > "$SP/ab_$label.txt"
  sh "killall yes 2>/dev/null" >/dev/null
  echo "$label done"
}
B='C:\Users\LEANER~1\AppData\Local\Temp\baseline.apk'
H='C:\Users\LEANER~1\AppData\Local\Temp\head.apk'
arm "$B" base1; arm "$H" head1; arm "$B" base2; arm "$H" head2
