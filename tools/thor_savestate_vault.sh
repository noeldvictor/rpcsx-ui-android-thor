#!/usr/bin/env bash
#
# Keep savestates in the repo, so an experiment can restore the SAME scene.
#
# ## Why this exists
#
# A savestate is the only repeatable gameplay workload on this device. A title
# screen is 0.35 cores behind a frame cap and can show nothing; a restored
# savestate runs real gameplay BELOW the cap, so a lever that costs frames can
# no longer hide.
#
# The device keeps exactly ONE slot per title and a capture OVERWRITES it, with
# no backup. A capture taken here to test the load path destroyed the only
# savestate for a title, and nothing on the device kept a copy. So:
#
#   * `save` ALWAYS pulls the existing slot into the vault first.
#   * the vault keeps every version, stamped, and never overwrites.
#
# The vault lives in `debug-captures/`, which is NOT tracked. A savestate holds
# game memory; it is yours and it does not belong in a public repository.
#
# Usage:
#   tools/thor_savestate_vault.sh list
#   tools/thor_savestate_vault.sh pull    BLUS30161
#   tools/thor_savestate_vault.sh save    BLUS30161      # backup, then capture, then pull
#   tools/thor_savestate_vault.sh push    BLUS30161 [file]
#   tools/thor_savestate_vault.sh restore BLUS30161 [file]  # push, then load
set -u

ADB="${ADB:-/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-192.168.1.3:5555}"
PKG=net.rpcsx.easy
FILES=/storage/emulated/0/Android/data/$PKG/files
CTRL_PORT="${CTRL_PORT:-8099}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VAULT="$REPO/debug-captures/savestates"

sh_() { MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" shell "$1" 2>&1 | tr -d '\r'; }
dev_path() { echo "$FILES/config/savestates/$1/$1_1_0.SAVESTAT.zst"; }
say() { printf '%s\n' "$*"; }

# The control API is the reliable trigger. The broadcast receivers work too, and
# are the fallback when the API is not forwarded or the build is a release one.
api() { curl -s --max-time 10 -X POST "127.0.0.1:${CTRL_PORT}/$1" 2>/dev/null; }
api_up() { curl -s --max-time 4 "127.0.0.1:${CTRL_PORT}/status" >/dev/null 2>&1; }

need_title() { [ -n "${1:-}" ] || { say "REFUSED: a title id is required"; exit 2; }; }

pull_to_vault() {
    local title="$1" tag="$2" src dst
    src="$(dev_path "$title")"
    if [ -z "$(sh_ "ls $src 2>/dev/null")" ]; then
        say "  nothing on the device at $src"
        return 1
    fi
    mkdir -p "$VAULT/$title"
    dst="$VAULT/$title/${title}_${tag}.SAVESTAT.zst"
    MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" exec-out "cat $src" > "$dst" 2>/dev/null
    local n; n=$(stat -c%s "$dst" 2>/dev/null || echo 0)
    if [ "${n:-0}" -lt 1024 ]; then
        rm -f "$dst"
        say "  REFUSED: pulled $n bytes, that is not a savestate"
        return 1
    fi
    say "  vault <- $dst ($n bytes)"
}

cmd="${1:-list}"
title="${2:-}"

case "$cmd" in
list)
    say "=== on the device ==="
    sh_ "ls -l $FILES/config/savestates/*/ 2>/dev/null" | sed 's/^/  /'
    say "=== in the vault ($VAULT) ==="
    if [ -d "$VAULT" ]; then ls -l "$VAULT"/*/ 2>/dev/null | sed 's/^/  /'; else say "  (empty)"; fi
    ;;

pull)
    need_title "$title"
    pull_to_vault "$title" "$(date +%Y%m%d-%H%M%S)"
    ;;

save)
    need_title "$title"
    # ALWAYS back up first. The capture overwrites the only slot.
    say "backing up the existing slot before capture:"
    pull_to_vault "$title" "prev-$(date +%Y%m%d-%H%M%S)" || say "  (no existing slot, nothing to lose)"

    if api_up; then
        say "capture via control API: $(api savestate)"
    else
        say "control API not reachable, using the broadcast receiver"
        sh_ "am broadcast -a net.rpcsx.THOR_DEBUG_SAVESTATE -n $PKG/net.rpcsx.utils.ThorDebugSaveStateReceiver" >/dev/null
    fi

    sh_ "sleep 6" >/dev/null
    say "pulling the new capture:"
    pull_to_vault "$title" "$(date +%Y%m%d-%H%M%S)"
    ;;

push|restore)
    need_title "$title"
    file="${3:-}"
    if [ -z "$file" ]; then
        # Newest in the vault for this title.
        file=$(ls -t "$VAULT/$title"/*.SAVESTAT.zst 2>/dev/null | head -1)
    fi
    [ -n "$file" ] && [ -f "$file" ] || { say "REFUSED: no vault file for $title"; exit 2; }

    dst="$(dev_path "$title")"
    sh_ "mkdir -p $FILES/config/savestates/$title" >/dev/null

    # TWO STEPS, because a direct push into the app's external directory is
    # refused. Measured on this device:
    #
    #   adb push -> .../Android/data/<pkg>/files/...   Permission denied
    #   adb push -> /data/local/tmp                    works
    #   run-as <pkg> cp /data/local/tmp/... -> dest    works
    #
    # Scoped storage lets shell READ that directory and not create in it, so
    # only the app's own uid can put the file there.
    #
    # MSYS_NO_PATHCONV protects the DEVICE path and BREAKS the local one in the
    # same command, so the local side is converted explicitly. Without that the
    # push failed with "cannot stat" while the byte-count check still reported
    # MATCH, because the device already held a good copy from the capture. A
    # postcondition that can pass for the wrong reason is not a postcondition.
    winfile="$file"
    command -v cygpath >/dev/null 2>&1 && winfile="$(cygpath -w "$file")"
    stage="/data/local/tmp/thor_ss_$title.zst"
    MSYS_NO_PATHCONV=1 "$ADB" -s "$SERIAL" push "$winfile" "$stage" 2>&1 | tail -1
    sh_ "run-as $PKG cp $stage $dst"
    sh_ "rm -f $stage" >/dev/null 2>&1
    # Confirm the POSTCONDITION: compare byte counts, never trust the exit code.
    localn=$(stat -c%s "$file" 2>/dev/null)
    # stat and wc both fail on this path for shell; ls -l field 5 works.
    dev_n=$(sh_ "ls -l $dst 2>/dev/null" | awk '{print $5}')
    say "  local=$localn device=$dev_n $([ "$localn" = "$dev_n" ] && echo MATCH || echo MISMATCH)"
    [ "$localn" = "$dev_n" ] || { say "REFUSED: byte counts differ, not loading"; exit 1; }

    if [ "$cmd" = "restore" ]; then
        if api_up; then
            say "load via control API: $(api loadstate)"
        else
            sh_ "am broadcast -a net.rpcsx.THOR_DEBUG_LOADSTATE -n $PKG/net.rpcsx.utils.ThorDebugLoadStateReceiver" >/dev/null
            say "load requested via the broadcast receiver"
        fi
        say "  read liveness from /proc, NOT from SurfaceFlinger: a dialogue box"
        say "  scene reported FROZEN while the game ran at 25.74 FPS."
    fi
    ;;

*)
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
