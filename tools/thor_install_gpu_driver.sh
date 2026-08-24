#!/usr/bin/env bash
# Download an AdrenoTools GPU driver from a GitHub release and install it.
#
# WHY A SCRIPT AND NOT THE APP. The in-app channel list can fetch these too, and
# Balemuni's Aurora is now in CuratedGpuDriverChannels. This exists for A/B
# testing from the command line, where a driver has to be installed, selected
# and measured without touching the screen.
#
# HOW THE INSTALL WORKS. `adb push` into the app data directory is REFUSED, and
# pushing into the app's external files directory gives EACCES. The proven
# pattern in this repo, the same one tools/thor_savestate_vault.sh uses, is to
# push to /data/local/tmp and then `run-as` a copy into place. run-as executes
# as the app uid and CAN read /data/local/tmp.
#
# USAGE
#   tools/thor_install_gpu_driver.sh --aurora            # download and install
#   tools/thor_install_gpu_driver.sh --aurora --select   # ...and make it active
#   tools/thor_install_gpu_driver.sh --url <zip-url>
#   tools/thor_install_gpu_driver.sh --list              # what is installed
set -u
ADB=${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}
W=${W:-192.168.1.3:5555}
PKG=${PKG:-net.rpcsx.easy}
DRIVERS=/data/data/$PKG/files/gpu_drivers

# The SD8Gen2 asset. As of the Balemuni tag this file is BYTE IDENTICAL to the
# AllAdreno asset, sha256 dbd1971dd93eecc789ea20913fac68876f0f112c697bce6e6b16025c1d49cd8f,
# so the device-specific name is packaging rather than a separate build. Verify
# again when the release changes rather than trusting the file name.
AURORA_URL="https://github.com/Balemuni/Balemunis-Aurora/releases/download/Balemuni/Balemuni_Apex_Ultimate_SD8Gen2.zip"

URL=""
SELECT=0
LIST=0
USE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --aurora) URL="$AURORA_URL";;
    --url) shift; URL="${1:-}";;
    --select) SELECT=1;;
    --list) LIST=1;;
    --use) shift; USE="${1:-}";;
    *) echo "unknown argument: $1"; exit 2;;
  esac
  shift
done

sh_(){ MSYS_NO_PATHCONV=1 "$ADB" -s "$W" shell "$1" 2>&1 | tr -d '\r'; }

# Point the app at a driver by rewriting three shared preferences.
#
# Done here in bash rather than through tools/set_thor_gpu_driver.ps1, which
# aborts in this environment: PowerShell 5.1 turns adb's progress output on
# stderr into a NativeCommandError, and with $ErrorActionPreference = "Stop"
# the script dies AFTER the push but BEFORE the run-as copy, leaving the
# preferences unchanged while reporting failure. Verified: it reported an error
# and the selected driver was still the old one.
select_driver() {
  local dname="$1" dlib="$2"
  local xml="$TMPSEL/app_prefs.xml"
  mkdir -p "$TMPSEL"
  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" exec-out run-as "$PKG" cat shared_prefs/app_prefs.xml > "$xml" 2>/dev/null
  if [ ! -s "$xml" ]; then echo "ABORT: could not read app_prefs.xml"; return 1; fi

  python - "$(cygpath -m "$xml" 2>/dev/null || echo "$xml")" "$dname" "$dlib" "$PKG" <<'SELPY'
import re,sys
path,name,lib,pkg = sys.argv[1:5]
s=open(path,encoding='utf-8').read()
vals={'selected_gpu_driver':name,
      'gpu_driver_path':'/data/data/%s/files/gpu_drivers/%s'%(pkg,name),
      'gpu_driver_name':lib}
def esc(v): return v.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;')
for k,v in vals.items():
    pat=re.compile(r'(<string name="%s">)(.*?)(</string>)'%re.escape(k), re.S)
    if pat.search(s):
        s=pat.sub(lambda m: m.group(1)+esc(v)+m.group(3), s, count=1)
    else:
        s=s.replace('</map>','    <string name="%s">%s</string>%s</map>'%(k,esc(v),chr(10)),1)
open(path,'w',encoding='utf-8').write(s)
print('prefs rewritten')
SELPY
  [ $? -eq 0 ] || { echo "ABORT: prefs rewrite failed"; return 1; }

  MSYS_NO_PATHCONV=1 "$ADB" -s "$W" push "$(cygpath -m "$xml" 2>/dev/null || echo "$xml")" /data/local/tmp/app_prefs.xml >/dev/null || return 1
  sh_ "chmod 644 /data/local/tmp/app_prefs.xml" >/dev/null
  sh_ "run-as $PKG cp /data/local/tmp/app_prefs.xml shared_prefs/app_prefs.xml" >/dev/null
  sh_ "rm -f /data/local/tmp/app_prefs.xml" >/dev/null

  # Read it back. A selection that did not stick looks exactly like one that did.
  local got
  got=$(MSYS_NO_PATHCONV=1 "$ADB" -s "$W" exec-out run-as "$PKG" cat shared_prefs/app_prefs.xml 2>/dev/null | tr -d '\r' | grep -o '<string name="selected_gpu_driver">[^<]*' | sed 's/.*>//')
  echo "  selected_gpu_driver is now: $got"
  if [ "$got" != "$dname" ]; then echo "ABORT: selection did not stick"; return 1; fi
  sh_ "am force-stop $PKG" >/dev/null
  echo "  app stopped so the next launch picks it up"
}

TMPSEL=${TMPSEL:-$(mktemp -d)}

# Select an already-installed driver by directory name. The library name is read
# from that driver's own meta.json rather than assumed: the two drivers on this
# device disagree about it - Aurora ships vulkan.freedreno.so and the older
# Turnip ships libvulkan_freedreno.so - and pointing the app at the wrong file
# name leaves it silently on the system driver.
if [ -n "$USE" ]; then
  ULIB=$(sh_ "run-as $PKG cat '$DRIVERS/$USE/meta.json' 2>/dev/null" | python -c "import json,sys
try:
    print(json.load(sys.stdin).get('libraryName',''))
except Exception:
    print('')")
  if [ -z "$ULIB" ]; then
    ULIB=$(sh_ "run-as $PKG ls '$DRIVERS/$USE' 2>/dev/null" | grep -E '\.so$' | head -1)
  fi
  if [ -z "$ULIB" ]; then echo "ABORT: no library found for '$USE'"; exit 1; fi
  echo "selecting: $USE  (library $ULIB)"
  select_driver "$USE" "$ULIB" || exit 1
  exit 0
fi

if [ "$LIST" = "1" ]; then
  echo "installed drivers:"
  sh_ "run-as $PKG ls $DRIVERS"
  echo "selected:"
  sh_ "run-as $PKG cat /data/data/$PKG/shared_prefs/*.xml 2>/dev/null | grep -i 'driver' | head -5"
  exit 0
fi

[ -z "$URL" ] && { echo "give --aurora or --url <zip>"; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ZIP="$TMP/driver.zip"

# Windows paths at the boundary. python and adb.exe here are WINDOWS programs,
# so an MSYS path like /tmp/tmp.XXXX means nothing to them: python silently
# writes somewhere else and adb reports "cannot stat". curl, wc and sha256sum
# are MSYS and want the MSYS form, so both forms are kept.
#
# cygpath -m, not -w. The -m form is C:/Users/... with FORWARD slashes, which
# both adb.exe and python accept, and which survives shell quoting. The -w form
# is C:\Users\... and every backslash then has to survive two levels of escaping
# to reach the program intact - it did not, and produced a literal "$LIB".
if command -v cygpath >/dev/null 2>&1; then
  TMPW=$(cygpath -m "$TMP"); ZIPW=$(cygpath -m "$ZIP")
else
  TMPW="$TMP"; ZIPW="$ZIP"
fi

echo "downloading $URL"
curl -sL -o "$ZIP" "$URL" || { echo "download failed"; exit 1; }
SIZE=$(wc -c < "$ZIP")
[ "$SIZE" -lt 100000 ] && { echo "ABORT: file is only $SIZE bytes, that is not a driver"; exit 1; }
echo "  $SIZE bytes, sha256 $(sha256sum "$ZIP" | cut -d' ' -f1)"

# Read meta.json BEFORE touching the device. An AdrenoTools package must carry
# meta.json with a libraryName, and installing something else leaves the app
# with a driver directory it cannot load.
# Two separate lines, not one. The driver NAME contains spaces - "Balemuni Apex
# Ultimate (Mesa 26.3.0-devel - SD8 Gen 2 / Adreno 740)" - so `read NAME LIB`
# splits the name across both variables and the library path comes out garbage.
META="$TMP/meta.txt"
python - "$ZIPW" > "$META" <<'METAPY'
import json,sys,zipfile
z=zipfile.ZipFile(sys.argv[1])
names=[n for n in z.namelist() if n.endswith('meta.json')]
if not names:
    sys.stderr.write('no meta.json: not an AdrenoTools package'); sys.exit(1)
m=json.loads(z.read(names[0]).decode())
lib=m.get('libraryName')
if not lib or lib not in z.namelist():
    sys.stderr.write('meta.json libraryName %r missing from the zip' % lib); sys.exit(1)
print(m.get('name','UnnamedDriver'))
print(lib)
METAPY
[ $? -eq 0 ] || { echo "ABORT: package validation failed"; exit 1; }
NAME=$(sed -n '1p' "$META")
LIB=$(sed -n '2p' "$META")
if [ -z "$NAME" ] || [ -z "$LIB" ]; then echo "ABORT: could not read meta.json"; exit 1; fi

echo "  name    : $NAME"
echo "  library : $LIB"

python - "$ZIPW" "$TMPW" <<'PY'
import sys,zipfile
z=zipfile.ZipFile(sys.argv[1]); z.extractall(sys.argv[2])
PY

DEST="$DRIVERS/$NAME"
echo "installing to $DEST"
sh_ "rm -f /data/local/tmp/drv_lib.so /data/local/tmp/drv_meta.json" >/dev/null
if [ ! -f "$TMP/$LIB" ]; then echo "ABORT: extract produced no $LIB"; exit 1; fi
MSYS_NO_PATHCONV=1 "$ADB" -s "$W" push "$TMPW/$LIB" /data/local/tmp/drv_lib.so >/dev/null || { echo "push failed"; exit 1; }
MSYS_NO_PATHCONV=1 "$ADB" -s "$W" push "$TMPW/meta.json" /data/local/tmp/drv_meta.json >/dev/null || { echo "push failed"; exit 1; }

sh_ "run-as $PKG mkdir -p '$DEST'" >/dev/null
sh_ "run-as $PKG cp /data/local/tmp/drv_lib.so '$DEST/$LIB'" >/dev/null
sh_ "run-as $PKG cp /data/local/tmp/drv_meta.json '$DEST/meta.json'" >/dev/null
sh_ "rm -f /data/local/tmp/drv_lib.so /data/local/tmp/drv_meta.json" >/dev/null

# Verify the bytes landed. A copy that silently did nothing looks exactly like a
# successful install until the driver fails to load hours later.
WANT=$(wc -c < "$TMP/$LIB")
GOT=$(sh_ "run-as $PKG stat -c %s '$DEST/$LIB' 2>/dev/null")
echo "  library on device: ${GOT:-0} bytes, expected $WANT"
if [ "${GOT:-0}" != "$WANT" ]; then echo "ABORT: size mismatch, install failed"; exit 1; fi
sh_ "run-as $PKG ls -la '$DEST'"

if [ "$SELECT" = "1" ]; then
  select_driver "$NAME" "$LIB"
fi
echo "installed OK"
