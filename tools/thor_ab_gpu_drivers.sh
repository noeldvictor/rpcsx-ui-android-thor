#!/usr/bin/env bash
# A/B two GPU drivers on the RESTORED 3D COMBAT scene.
#
# WHY A WARM-UP BOOT PER DRIVER. Switching driver invalidates the Vulkan
# pipeline cache - the log says "Ignoring Vulkan driver pipeline cache that does
# not match the current GPU/driver" - so the FIRST boot on a new driver
# recompiles shaders and is not comparable with anything. One boot is thrown
# away per driver before any number is kept.
#
# WHY THE MSAA LINE IS REPORTED. Aurora logs "Your GPU driver does not support
# some required MSAA features. MSAA will be disabled." If one driver disables
# MSAA and the other does not, they are not rendering the same frame, and a
# speed difference is not evidence that one driver is faster.
#
# 3D COMBAT ONLY. Every run restores the savestate and is gated on
# coresBusy>4.5. Intro-movie runs measure Bink playback, not the engine.
set -u
S="$(dirname "$0")"
REPO=/c/Users/leanerdesigner/Documents/ps3-thor/rpcsx-ui-android
ADB=/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb
W=192.168.1.3:5555
PKG=net.rpcsx.easy
R=/storage/emulated/0/Android/data/$PKG/files
sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s $W shell "$1" 2>&1 | tr -d '\r'; }

BASE="Turnip v26.3.0-R3-v1"
AURORA="Balemuni Apex Ultimate (Mesa 26.3.0-devel - SD8 Gen 2 / Adreno 740)"
RUNS=${RUNS:-3}
PLAY=${PLAY:-120}

arm() {
  local label="$1" drv="$2"
  echo
  echo "################ $label ################"
  bash "$REPO/tools/thor_install_gpu_driver.sh" --use "$drv" 2>&1 | grep -E "selecting|now:|ABORT" || return 1

  echo "-- warm-up boot, discarded (rebuilds the pipeline cache) --"
  sh_ "logcat -c" >/dev/null
  ACC='' HONOUR=0 RUNS=1 PLAY=45 bash "$S/combat_soak.sh" 2>&1 | grep -E "^run|^===" | sed 's/^/   /'

  echo "-- driver facts from the warm-up log --"
  sh_ "logcat -d | grep -c 'MSAA will be disabled'" | sed 's/^/   MSAA-disabled lines: /'
  sh_ "logcat -d | grep -o 'loading custom driver: [^ ]*' | tail -1" | sed 's/^/   /'

  echo "-- measured runs --"
  ACC='' HONOUR=0 RUNS=$RUNS PLAY=$PLAY bash "$S/combat_soak.sh" 2>&1 | grep -E "^run|^===" | sed 's/^/   /'
}

arm "BASELINE: $BASE" "$BASE"
arm "AURORA:   $AURORA" "$AURORA"
echo
echo "=== A/B complete ==="
