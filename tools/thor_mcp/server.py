#!/usr/bin/env python3
"""Thor MCP server: typed tools for driving RPCSX experiments on the device.

WHY THIS EXISTS
---------------
The primitives already exist: pad injection, scene detection, device telemetry,
compile progress, config readback, per-thread CPU, the log tail, savestates.
What kept going wrong was the loop AROUND them, hand-written in bash each time.

Real failures from one day of that, all mine and none of them emulator bugs:

  * a cooldown gate placed BEFORE the force-stop, so the harness waited for a
    temperature its own running emulator prevented, and held the device at 95 C;
  * a cache count using a path relative to the app's private directory when the
    cache is on external storage, reporting 0 objects while 3149 existed;
  * `printf | while read`, which drops a line with no trailing newline, so every
    arm ran with its lever unset and the two arms agreed perfectly.

Those disappear when the loop lives in one tested place. That is this file.

WHAT IT REFUSES
---------------
Refusals are the point. Each one below has already produced a wrong number here.

  * measuring while a MOVIE plays;
  * measuring while the THERMAL GUARD is engaged;
  * booting a device that is too hot, or whose screen is asleep;
  * trusting a savestate push whose byte count does not match.

It never writes a game profile. Propose only.
"""

import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

def _resolve_adb():
    """Find an adb THIS process can execute.

    The repo's shell tools use an MSYS path like /c/Users/.../adb. Windows
    Python cannot spawn that: it fails with WinError 2, "cannot find the
    file specified", which reads like adb is missing when it is not. So the
    MSYS shape is converted, the usual SDK location is tried, and PATH is the
    fallback.
    """
    import shutil

    candidates = []
    env = os.environ.get("ADB")
    if env:
        candidates.append(env)
        if len(env) > 3 and env[0] == "/" and env[2] == "/":
            drive = env[1].upper() + ":"
            candidates.append(drive + env[2:].replace("/", os.sep))

    local = os.environ.get("LOCALAPPDATA")
    if local:
        candidates.append(os.path.join(local, "Android", "Sdk", "platform-tools", "adb.exe"))

    for c in candidates:
        for cand in (c, c + ".exe"):
            if os.path.isfile(cand):
                return cand

    return shutil.which("adb") or "adb"


ADB = _resolve_adb()
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def adb_devices():
    """The rows of `adb devices -l`, one dict per device."""
    try:
        out = subprocess.run([ADB, "devices", "-l"], capture_output=True, timeout=20,
                             stdin=subprocess.DEVNULL)
        text = out.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return []
    rows = []
    for line in text.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            rows.append({"serial": parts[0], "state": parts[1],
                         "thor": "model:AYN_Thor" in parts,
                         "usb": ":" not in parts[0] and not parts[0].startswith(("adb-", "emulator-"))})
    return rows


def _resolve_serial(current=None):
    """Find the serial of the AYN Thor that adb can use now, or None.

    A fixed serial was wrong more often than right. The sessions used four:
    USB c3ca0370, and 192.168.1.3, .33 and .5 over Wi-Fi. Wireless debugging
    also takes a new port each time it is turned on.

    The rules:
      * THOR_SERIAL, then ANDROID_SERIAL, wins when set.
      * Keep the current serial while adb still lists it as a ready Thor.
      * Otherwise take a ready Thor, USB first. The Thor is often on USB and
        Wi-Fi at the same time.
      * Select only a device whose model is AYN_Thor. The tools force-stop
        apps and set properties, and another phone or an AVD must not get
        those commands.
      * Never return a serial that adb does not list.
    """
    env = os.environ.get("THOR_SERIAL") or os.environ.get("ANDROID_SERIAL")
    if env:
        return env
    thors = [r for r in adb_devices() if r["state"] == "device" and r["thor"]]
    if not thors and _connect_wireless():
        thors = [r for r in adb_devices() if r["state"] == "device" and r["thor"]]
    serials = [r["serial"] for r in thors]
    if current in serials:
        return current
    usb = [r["serial"] for r in thors if r["usb"]]
    if usb:
        return usb[0]
    return serials[0] if serials else None


def _connect_wireless():
    """Connect to each paired wireless-debugging service that mDNS announces.

    Wireless debugging takes a new port each time it is turned on, so no
    address can be written down. On 2026-09-22 adb listed nothing while the
    Thor announced itself as adb-c3ca0370-X4FreV at 192.168.1.5:36587. Only
    TLS connect services are tried: they belong to devices that this PC has
    paired. The caller still selects only a device whose model is AYN_Thor.
    """
    try:
        out = subprocess.run([ADB, "mdns", "services"], capture_output=True, timeout=20,
                             stdin=subprocess.DEVNULL)
        text = out.stdout.decode("utf-8", "replace")
    except (OSError, subprocess.TimeoutExpired):
        return False
    connected = False
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1].startswith("_adb-tls-connect._tcp"):
            try:
                r = subprocess.run([ADB, "connect", parts[2]], capture_output=True,
                                   timeout=20, stdin=subprocess.DEVNULL)
            except (OSError, subprocess.TimeoutExpired):
                continue
            if b"connected to" in r.stdout:
                connected = True
    return connected


# Found before each tool call, not at import: an import must not start adb.
SERIAL = None


def ensure_serial():
    """Check the serial before each tool call. The device moves between USB
    and Wi-Fi during a session, and a stale serial makes every adb command
    answer empty. An empty answer looks like a stopped emulator."""
    global SERIAL
    SERIAL = _resolve_serial(SERIAL)
    return SERIAL
PORT = int(os.environ.get("THOR_CTRL_PORT", "8099"))
PKG = "net.rpcsx.easy"
FILES = f"/storage/emulated/0/Android/data/{PKG}/files"
EMU_STATE_STOPPED = 0
EMU_STATE_LOADING = 1
EMU_STATE_STOPPING = 2
EMU_STATE_RUNNING = 3
EMU_STATE_PAUSED = 4
EMU_STATE_FROZEN = 5
EMU_STATE_READY = 6
EMU_STATE_STARTING = 7
_process_hold_pid = None


# --------------------------------------------------------------------------
# device plumbing
# --------------------------------------------------------------------------
def sh(cmd, timeout=120):
    """Run one adb shell command. MSYS_NO_PATHCONV stops Git Bash rewriting
    DEVICE paths into local ones, which fails with a confusing error."""
    if not SERIAL:
        return ""
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    try:
        out = subprocess.run([ADB, "-s", SERIAL, "shell", cmd],
                             capture_output=True, timeout=timeout, env=env)
        return out.stdout.decode("utf-8", "replace").replace("\r", "")
    except subprocess.TimeoutExpired:
        return ""


def adb(args, timeout=300, binary=False):
    if not SERIAL:
        return b"" if binary else ""
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    out = subprocess.run([ADB, "-s", SERIAL] + args, capture_output=True,
                         timeout=timeout, env=env)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace").replace("\r", "")


def reachable():
    """An unreachable device answers empty exactly like a dead process, so this
    is checked separately before any liveness claim."""
    if not SERIAL and not ensure_serial():
        return False
    return sh("echo ok", timeout=20).strip() == "ok"


def temp_c():
    """Read the cpu-1-* junction zones. A bare max over every thermal_zone reads
    a different sensor: all zones gave 63400 in the same minute cpu-1-* gave
    84300."""
    raw = sh(r"""for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/temp 2>/dev/null); n=$(cat $z/type 2>/dev/null); case $n in cpu*) [ -n "$t" ] && echo $((t/1000));; esac; done""")
    vals = [int(x) for x in raw.split() if x.strip().isdigit()]
    return max(vals) if vals else -1


def fixed_silicon_c():
    """Read the fixed silicon domain used by the PS3 thermal guard.

    Per-core cpu-* sensors are junction readings. They can exceed 70 C during
    normal work and must not decide the cold-start gate. The cpuss, gpuss, DDR,
    SoC and XO temperature sensors are the fixed domain used by the repository
    guard. The socd zone is battery state of charge, not SoC temperature.
    """
    raw = sh(r"""for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/temp 2>/dev/null); n=$(cat $z/type 2>/dev/null); case $n in cpuss-*|gpuss-*|ddr|xo-therm) [ -n "$t" ] && echo "$t";; esac; done""")
    vals = []
    for token in raw.split():
        if not token.strip().isdigit():
            continue
        value = int(token)
        vals.append(value / 1000.0 if value >= 1000 else float(value))
    return round(max(vals), 1) if vals else -1


def api(path, method="GET", timeout=8):
    """Call the in-emulator control API through the adb forward."""
    url = f"http://127.0.0.1:{PORT}/{path.lstrip('/')}"
    req = urllib.request.Request(url, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        return {"error": f"control API unreachable: {e}. {_api_down_cause()}"}
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"raw": body}


def _api_down_cause():
    """Say why the control API did not answer. The old text always said to run
    adb forward, which is the wrong fix for a stopped or held process."""
    p = pid()
    if not p:
        return f"The emulator process is not running (pidof {PKG} is empty)."
    if _process_state(p) in ("T", "t"):
        return "The emulator process is held with SIGSTOP, so the API cannot answer."
    return f"Run: adb forward tcp:{PORT} tcp:{PORT}"


def ensure_forward():
    try:
        adb(["forward", f"tcp:{PORT}", f"tcp:{PORT}"], timeout=30)
    except Exception:
        pass


def pid():
    return sh("pidof " + PKG).strip()


def proc_jiffies(p):
    line = sh(f"cat /proc/{p}/stat").split()
    if len(line) < 15:
        return None
    try:
        return int(line[13]) + int(line[14])
    except ValueError:
        return None


# --------------------------------------------------------------------------
# tools
# --------------------------------------------------------------------------
def t_state(a):
    """Everything at once, so a caller does not stitch three calls together."""
    if not reachable():
        return {"error": "device unreachable; an empty answer here is NOT a dead emulator",
                "serial": SERIAL, "adbDevices": adb_devices()}
    ensure_forward()
    p = pid()
    result = {
        "reachable": True,
        "serial": SERIAL,
        "pid": p or None,
        "cpuJunctionC": temp_c(),
        "fixedSiliconC": fixed_silicon_c(),
        "battery": sh("cat /sys/class/power_supply/battery/capacity").strip(),
    }
    if not p:
        # pidof can read empty while the app runs, during a respawn or after a
        # timeout. So ask the control API before "not running" is said.
        status = api("/status", timeout=3)
        if isinstance(status, dict) and "error" not in status:
            result["pidNote"] = "pidof read empty, but the control API answered"
        else:
            result["paused"] = False
            result["emulator"] = "not running: pidof is empty and the control API does not answer"
            return result
    elif held_process_pid() == p:
        # A SIGSTOP-held process cannot answer the API. A /pause sent now can
        # run after the next continue and pause the next slice.
        result["paused"] = True
        result["holdMode"] = "process"
        result["emulator"] = "held with SIGSTOP; the control API answers after the process continues"
        return result
    result["paused"] = hold(a, default=a.get("pause", True))
    result["status"] = api("/status")
    result["device"] = api("/device")
    result["diag"] = api("/diag")
    return result


def t_cooldown(a):
    """Force-stop FIRST, then cool. The reverse order once held this device at
    95 C waiting for a temperature its own emulator made impossible."""
    target = int(a.get("targetC", 62))
    limit = int(a.get("timeoutS", 300))
    sh(f"am force-stop {PKG}")
    sh("killall yes")
    waited = 0
    t = temp_c()
    while t > target and waited < limit:
        time.sleep(15)
        waited += 15
        t = temp_c()
    return {"cpuJunctionC": t, "target": target, "waitedS": waited,
            "cooled": t <= target,
            "note": "not cooled means something else loads the device" if t > target else ""}


def t_boot(a):
    t = fixed_silicon_c()
    ceiling = float(a.get("maxStartC", 70))
    if t < 0:
        return {"refused": True, "fixedSiliconC": t,
                "reason": "the fixed-silicon sensor domain is unavailable"}
    if t >= ceiling:
        return {"refused": True, "fixedSiliconC": t,
                "reason": f"device is {t} C, at or above the {ceiling} C start ceiling. "
                          "Booting now measures the throttle and cooks the device. "
                          "Call thor_cooldown first."}

    title, iso = a["titleId"], a["isoPath"]
    if a.get("freshCompile", True):
        # Diagnose against a fresh compile. A cached SPU object replaces a
        # compile, so a fault could be an artifact of a stale object.
        sh("setprop debug.rpcsx.thor.spu_native_object_cache 0")
    same_process = bool(a.get("sameProcess", False))
    previous_pid = pid() or None
    if same_process:
        # Boot into the process that is already running, with the game list
        # on top. This is the path a user takes after Exit Game, and the one
        # that failed until 2026-09-21. A force-stop here would hide that.
        if not previous_pid:
            return {"refused": True, "reason": "sameProcess needs a running emulator process"}
        if emulation_state() != EMU_STATE_STOPPED:
            return {"refused": True, "reason": "sameProcess needs the core Stopped; call thor_exit_game first",
                    "state": emulation_state()}
        if resumed_activity() != "net.rpcsx.easy/net.rpcsx.MainActivity":
            sh("input keyevent KEYCODE_BACK")
            time.sleep(1.5)
            if resumed_activity() != "net.rpcsx.easy/net.rpcsx.MainActivity":
                return {"refused": True, "reason": "the game list is not on top",
                        "activity": resumed_activity()}
    else:
        sh(f"am force-stop {PKG}; rm -f {FILES}/cache/RPCSX.log")
    # A Thor with its screen off cannot boot a title: a SurfaceView measured 0x0
    # never creates a surface and the renderer waits forever.
    sh("input keyevent KEYCODE_WAKEUP; svc power stayon true")
    sh(f"am start -a net.rpcsx.THOR_DEBUG_BOOT -n {PKG}/net.rpcsx.MainActivity "
       f"--es path '{iso}' --es titleId {title} --es thorDebugBootRequestId mcp "
       f"--ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false")
    ensure_forward()
    result = {"booted": True, "titleId": title,
              "freshCompile": a.get("freshCompile", True),
              "startFixedSiliconC": t}
    if same_process:
        time.sleep(2.0)
        now = pid() or None
        result.update({"sameProcess": True, "pid": previous_pid, "pidNow": now,
                       "samePid": now == previous_pid})
    return result


def resumed_activity():
    """The activity Android reports as resumed for this package, or None."""
    raw = sh("dumpsys activity activities", timeout=30)
    m = re.search(r"(?m)^\s*ResumedActivity:.*?(net\.rpcsx\.easy/net\.rpcsx\.\w+)", raw)
    return m.group(1) if m else None


def t_exit_game(a):
    """Exit the running game the way the home menu's Exit Game does, and
    report when the core reached Stopped and when the game activity closed.

    This exists because the menu could only be reached blind: a PS press in
    the pad data, ten DOWN presses with a screenshot between, then CROSS. And
    a held process cannot stop, so the hold is released first. The
    2026-09-21 self-join at exit was found by hand this way; this tool makes
    the check one call."""
    p = pid()
    if not p:
        return {"error": "no emulator process"}
    if held_process_pid() == p:
        continue_process_for_slice(p)
    state = emulation_state()
    if state == EMU_STATE_STOPPED:
        return {"exited": True, "alreadyStopped": True, "pid": p,
                "activity": resumed_activity()}
    if is_paused():
        api("/resume", "POST", timeout=1.0)
    started = time.monotonic()
    r = api("/exit", "POST", timeout=3.0)
    if isinstance(r, dict) and r.get("error"):
        return {"error": "the exit request was not acknowledged", "exit": r}
    timeout_s = float(a.get("timeoutS", 30))
    stopped_ms = None
    while time.monotonic() - started < timeout_s:
        if emulation_state() == EMU_STATE_STOPPED:
            stopped_ms = int((time.monotonic() - started) * 1000)
            break
        time.sleep(0.2)
    activity_closed_ms = None
    while time.monotonic() - started < timeout_s + 10:
        if resumed_activity() == "net.rpcsx.easy/net.rpcsx.MainActivity":
            activity_closed_ms = int((time.monotonic() - started) * 1000)
            break
        time.sleep(0.5)
    sleepy = api("/log?match=too%20sleepy&n=3")
    return {"exited": stopped_ms is not None,
            "stoppedAfterMs": stopped_ms,
            "activityClosedAfterMs": activity_closed_ms,
            "activity": resumed_activity(),
            "pid": p, "pidNow": pid() or None,
            "selfJoinLines": sleepy,
            "exit": r}


def t_wait_ready(a):
    """Wait for real frames, not a fixed sleep. A fixed sleep is not a
    deterministic workload: boot varies by tens of seconds and a cold precompile
    can take ten minutes."""
    limit = int(a.get("timeoutS", 300))
    want = float(a.get("minFps", 10))
    hard_limit = float(a.get("maxSiliconC", 72))
    waited, last = 0, {}
    while waited < limit:
        interval = min(2, limit - waited)
        time.sleep(interval)
        waited += interval

        silicon = fixed_silicon_c()
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            return {"ready": False, "waitedS": waited,
                    "thermalStop": True, "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit,
                    "reason": ("the fixed-silicon sensor domain became unavailable"
                               if silicon < 0 else
                               f"fixed silicon reached the {hard_limit} C hard limit"),
                    "stop": stop}

        dev = api("/device")
        last = dev
        if isinstance(dev, dict) and float(dev.get("device", {}).get("fps", 0) or 0) >= want:
            return {"ready": True, "waitedS": waited, "device": dev,
                    "fixedSiliconC": silicon}
        if not pid():
            return {"ready": False, "waitedS": waited, "error": "process gone",
                    "log": api("/log?match=Fatal&n=10")}
    return {"ready": False, "waitedS": waited, "device": last,
            "hint": "check /diag progress; a cold precompile can take ten minutes"}


def t_press(a):
    """Press when the screen is READY, not on a timer. Presses sent during an
    intro are correctly ignored by the game and read as a broken API.

    A PAUSED guest cannot see a button, so this resumes first, presses, and then
    puts the emulator back the way it found it. That keeps the pause-look-decide
    -press loop working without the caller tracking the state by hand."""
    p = pid()
    process_held = bool(p) and held_process_pid() == p
    was_paused = process_held or is_paused()
    start_ceiling = float(a.get("maxStartC", 70))
    hard_limit = float(a.get("maxSiliconC", 72))
    start_silicon = fixed_silicon_c()
    if start_silicon < 0 or start_silicon >= hard_limit:
        stop = t_stop({})
        return {"thermalStop": True, "triggerFixedSiliconC": start_silicon,
                "maxSiliconC": hard_limit, "stop": stop}
    if was_paused and start_silicon >= start_ceiling:
        return {"refused": True, "fixedSiliconC": start_silicon,
                "reason": f"fixed silicon is not below {start_ceiling} C"}

    display = prepare_display_for_guest(p)
    if not display.get("ready"):
        stop = t_stop({})
        return {"error": "the guarded press could not foreground RPCSX",
                "display": display, "stop": stop}
    resume = None
    if process_held:
        resume = continue_process_for_slice(p)
        if not resume.get("ok"):
            stop = t_stop({})
            return {"error": "the guarded press could not resume its process hold",
                    "wasPaused": was_paused, "resume": resume, "stop": stop}
        resume["emulatorResume"] = api("/resume", "POST", timeout=1.0)
    elif was_paused:
        resume = api("/resume", "POST", timeout=1.0)

    if was_paused:
        time.sleep(0.3)

    r = api(f"/pad/press?buttons={a['buttons']}&ms={int(a.get('ms', 150))}",
            "POST", timeout=1.0)
    if isinstance(r, dict) and r.get("error"):
        # Put the process back the way it was found. Hold it only when it was
        # paused before and the caller did not ask for rePause=false.
        process_hold = (stop_process_for_slice(p)
                        if p and was_paused and a.get("rePause", True) else None)
        return {"error": "the guarded pad press was not acknowledged",
                "press": r, "wasPaused": was_paused, "resume": resume,
                "processHold": process_hold,
                "rePaused": bool(process_hold and process_hold.get("ok")),
                "holdMode": "process" if process_hold and process_hold.get("ok") else None}

    settle = float(a.get("settleS", 1.0))
    started = time.monotonic()
    max_silicon = start_silicon
    while True:
        elapsed = time.monotonic() - started
        if elapsed >= settle:
            break
        interval = min(0.25, settle - elapsed)
        time.sleep(interval)
        silicon = fixed_silicon_c()
        max_silicon = max(max_silicon, silicon)
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            return {"press": r, "wasPaused": was_paused,
                    "thermalStop": True, "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "stop": stop}
    pause = None
    process_hold = None
    re_paused = False
    hold_mode = None
    state_after = emulation_state()
    if was_paused and a.get("rePause", True) and state_after in (EMU_STATE_STOPPED, 2):
        # The press started a stop (Exit Game), or the core is already
        # stopped. A pause is refused now, and the fallback below is a
        # process SIGSTOP, which froze the core in the middle of its stop on
        # 2026-09-21 and read like a hang. Leave it running.
        hold_mode = "none: core is stopping or stopped"
    elif was_paused and a.get("rePause", True):
        current = pid()
        if current == p and held_process_pid() == p:
            re_paused = True
            hold_mode = "process"
        else:
            pause = api("/pause", "POST", timeout=1.0)
            pause_acknowledged = (
                isinstance(pause, dict) and not pause.get("error") and
                (pause.get("paused") or is_paused())
            )
            if pause_acknowledged:
                re_paused = True
                hold_mode = "emulator"
            elif current == p:
                process_hold = stop_process_for_slice(p)
                re_paused = bool(process_hold.get("ok"))
                hold_mode = "process" if re_paused else None

    return {"press": r, "wasPaused": was_paused,
            "resume": resume, "pause": pause, "processHold": process_hold,
            "rePaused": re_paused, "holdMode": hold_mode,
            "display": display,
            "maxFixedSiliconC": max_silicon}


def emulation_state():
    r = api("/status")
    state = r.get("state") if isinstance(r, dict) else None
    return state if isinstance(state, int) else None


def _process_state(p):
    raw = sh(f"run-as {PKG} cat /proc/{p}/status")
    match = re.search(r"^State:\s+([A-Za-z])", raw, re.MULTILINE)
    return match.group(1) if match else None


def held_process_pid():
    global _process_hold_pid
    current = pid()
    if not current:
        _process_hold_pid = None
        return None
    state = _process_state(current)
    if state in ("T", "t"):
        _process_hold_pid = current
        return current
    if current != _process_hold_pid or state not in ("T", "t"):
        _process_hold_pid = None
    return None


def stop_process_for_slice(p):
    """Stop every app thread while RPCSX is still in startup compilation."""
    global _process_hold_pid
    current = pid()
    if current != p:
        return {"ok": False, "pid": p, "currentPid": current or None,
                "error": "the target process is no longer live"}
    sh(f"run-as {PKG} kill -STOP {p}")
    current = pid()
    if current != p:
        return {"ok": False, "pid": p, "currentPid": current or None,
                "error": "the target process exited during the hold"}
    state = _process_state(p)
    if state not in ("T", "t"):
        return {"ok": False, "pid": p, "processState": state}
    _process_hold_pid = p
    return {"ok": True, "pid": p, "processState": state}


def continue_process_for_slice(p):
    """Continue a process-level startup hold before the next bounded slice."""
    global _process_hold_pid
    if held_process_pid() != p:
        return {"ok": False, "pid": p,
                "error": "the recorded process hold is not active"}
    acknowledgement = sh(
        f"run-as {PKG} kill -CONT {p} && echo __THOR_CONTINUED__")
    if "__THOR_CONTINUED__" not in acknowledgement:
        return {"ok": False, "pid": p,
                "error": "the process continue signal was not acknowledged"}
    # Clear the old hold before the status read. The independent deadline can
    # set it again while this ADB read is in flight.
    _process_hold_pid = None
    state = _process_state(p)
    return {"ok": True, "pid": p, "processState": state,
            "deadlineHoldRaced": state in ("T", "t")}


def prepare_display_for_guest(p):
    """Make the existing RPCSX task visible before a guarded guest resume.

    AYN Reblue can take the foreground during a long start-paused handoff.
    Android then destroys the RPCSX Surface even while the display stays awake.
    Wake the display, and bring the existing task forward if that happened.
    Do not launch another activity or another guest.
    """
    sh("input keyevent KEYCODE_WAKEUP")
    activity_command = "dumpsys activity activities"
    activities = sh(activity_command, timeout=20)
    foreground_pattern = (
        r"(?m)^\s*(?:topResumedActivity=.*|ResumedActivity:.*)"
        r"net\.rpcsx\.easy/net\.rpcsx\.RPCSXActivity"
    )
    if re.search(foreground_pattern, activities):
        return {"ready": True, "moved": False}

    task_pattern = re.compile(
        r"(?m)^\s*\* Task\{[^\n]* #(\d+) [^\n]* "
        r"A=(?:\d+:)?net\.rpcsx\.easy\b"
    )
    task_matches = list(task_pattern.finditer(activities))
    task_id = None
    process_pattern = re.compile(
        rf"\b{re.escape(str(p))}:net\.rpcsx\.easy/"
    )
    for index, match in enumerate(task_matches):
        end = (task_matches[index + 1].start()
               if index + 1 < len(task_matches) else len(activities))
        task_text = activities[match.start():end]
        if ("net.rpcsx.easy/net.rpcsx.RPCSXActivity" in task_text and
                process_pattern.search(task_text)):
            task_id = match.group(1)
            break

    if task_id is None:
        return {"ready": False, "moved": False,
                "error": "the live RPCSX task could not be identified"}

    # Android 13 has no move-to-front task command. `task lock` brings the task
    # forward before this retail build rejects lock-task mode. Stop lock mode
    # immediately as well, so the command stays safe if a later build permits it.
    sh(f"am task lock {task_id}; am task lock stop", timeout=20)
    after = sh(activity_command, timeout=20)
    ready = re.search(foreground_pattern, after) is not None
    return {"ready": ready, "moved": True, "taskId": int(task_id),
            "error": None if ready else
            "the existing RPCSX task did not reach the foreground"}


def is_paused():
    # system_state: 4 Paused, 6 Ready. A start-paused debug boot is Ready and
    # has no guest threads until the first resume. Treat it as a valid held
    # state so thor_slice guards that first resume too.
    return emulation_state() in (EMU_STATE_PAUSED, EMU_STATE_READY)


def hold(a, default=True):
    """PAUSE BY DEFAULT for anything that inspects.

    If the emulator is not paused while a tool looks at it, the game runs on
    while the caller thinks, and the state reasoned about is already stale by
    the time a button is pressed. Pausing is not a convenience here, it is what
    makes an observation mean anything.

    Pass pause=false when you deliberately want a live reading.

    Return the paused state that /pause reports, not True for a pause that was
    only sent. A pause can fail, for example with the core stopped at the game
    list.
    """
    if a.get("pause", default):
        r = api("/pause", "POST")
        return bool(isinstance(r, dict) and r.get("paused"))
    return False


def t_pause(a):
    """Stop the world. Without it every screenshot races the scene: the picture
    is taken, the game runs on, and the button lands somewhere else."""
    return api("/pause", "POST")


def t_resume(a):
    return api("/resume", "POST")


def t_slice(a):
    """Run one bounded guest slice from a paused state, then pause again."""
    p = pid()
    if not p:
        return {"error": "emulator is not running"}
    process_held = held_process_pid() == p
    initial_state = EMU_STATE_STARTING if process_held else emulation_state()
    if not process_held and initial_state not in (EMU_STATE_PAUSED, EMU_STATE_READY):
        return {"refused": True,
                "reason": "the emulator must be paused before a bounded slice"}

    # Keep the normal slice limit at 15 seconds. An exact startup handoff can
    # request a longer continuous window. The fixed-silicon poll and hard stop
    # stay active for the complete window.
    duration_limit = max(
        15.0, min(float(a.get("maxDurationS", 15.0)), 300.0))
    duration = max(
        0.1, min(float(a.get("seconds", 1.5)), duration_limit))
    start_ceiling = float(a.get("maxStartC", 70))
    hard_limit = float(a.get("maxSiliconC", 72))
    pause_timeout = max(1.0, min(float(a.get("pauseTimeoutS", 8.0)), 30.0))
    startup_pause_timeout = max(
        pause_timeout,
        min(float(a.get("startupPauseTimeoutS", 120.0)), 300.0),
    )
    startup_handoff = process_held or initial_state == EMU_STATE_READY
    start_silicon = fixed_silicon_c()
    if start_silicon < 0 or start_silicon >= start_ceiling:
        return {"refused": True, "fixedSiliconC": start_silicon,
                "reason": ("the fixed-silicon sensor domain is unavailable"
                           if start_silicon < 0 else
                           f"fixed silicon is not below {start_ceiling} C")}

    display = prepare_display_for_guest(p)
    if not display.get("ready"):
        stop = t_stop({})
        return {"error": "the bounded slice could not foreground RPCSX",
                "display": display, "stop": stop,
                "initialState": initial_state,
                "startupHandoff": startup_handoff}
    started = time.monotonic()
    deadline_pause = {}

    # A fixed-silicon ADB read can take longer than the requested guest slice.
    # Do not let slow telemetry or the control API extend the active guest
    # window. During startup, stop the process before any API request. The
    # starting state cannot accept a normal emulator pause, and an API request
    # can block while compilation saturates the device.
    def pause_at_deadline():
        deadline_pause["requestedAtS"] = time.monotonic() - started
        if startup_handoff:
            deadline_pause["processHold"] = stop_process_for_slice(p)
            if deadline_pause["processHold"].get("ok"):
                deadline_pause["result"] = {
                    "ok": True, "paused": False, "processHeld": True,
                }
                deadline_pause["state"] = EMU_STATE_STARTING
                deadline_pause["settledAtS"] = time.monotonic() - started
                return
        # A saturated guest can accept the pause but fail to return its HTTP
        # response. Bound that request, then hold the same live PID. This keeps
        # one slow control request from extending a short guest slice.
        deadline_pause["result"] = api(
            "/pause", "POST", timeout=min(pause_timeout, 1.0))
        if (isinstance(deadline_pause["result"], dict) and
                deadline_pause["result"].get("error")):
            deadline_pause["processHold"] = stop_process_for_slice(p)
            if deadline_pause["processHold"].get("ok"):
                deadline_pause["state"] = None
                deadline_pause["settledAtS"] = time.monotonic() - started

    deadline_timer = threading.Timer(duration, pause_at_deadline)
    deadline_timer.daemon = True
    deadline_timer.start()

    resume = (continue_process_for_slice(p) if process_held
              else api("/resume", "POST"))
    if process_held and resume.get("ok"):
        # Startup requests an emulator pause when initialization ends. A
        # process-held slice can therefore resume into Paused instead of
        # Starting. This bounded request advances either state without putting
        # the deadline after a potentially blocked control call.
        resume["emulatorResume"] = api("/resume", "POST", timeout=0.5)
    if not resume.get("ok"):
        deadline_timer.cancel()
        stop = t_stop({})
        return {"error": "the bounded slice could not resume its held state",
                "resume": resume, "stop": stop,
                "initialState": initial_state,
                "startupHandoff": startup_handoff}
    elapsed = 0.0
    silicon = start_silicon
    max_silicon = start_silicon
    while True:
        elapsed = time.monotonic() - started
        if elapsed >= duration:
            break
        interval = min(0.25, duration - elapsed)
        time.sleep(interval)
        silicon = fixed_silicon_c()
        max_silicon = max(max_silicon, silicon)
        elapsed = time.monotonic() - started
        if silicon < 0 or silicon >= hard_limit:
            deadline_timer.cancel()
            stop = t_stop({})
            return {"thermalStop": True, "elapsedS": round(elapsed, 3),
                    "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "resume": resume, "stop": stop}

        # The independent device guard can stop the process at 68 C before
        # this slice reaches its deadline. Once the same sensor domain has
        # approached the slice ceiling, adopt that hold and end the slice.
        # Do not count the stopped interval as active guest time, and cancel
        # the old deadline so it cannot stop a later slice.
        if (max_silicon >= start_ceiling - 2.0 and
                "requestedAtS" not in deadline_pause and
                held_process_pid() == p):
            deadline_timer.cancel()
            held_at = time.monotonic() - started
            process_hold = {
                "ok": True, "pid": p, "processState": "T",
                "source": "device-thermal-guard",
            }
            return {
                "completed": True, "requestedS": duration,
                "elapsedS": round(held_at, 3),
                "hostElapsedS": round(held_at, 3),
                "activeElapsedS": round(held_at, 3),
                "pauseRequestedAtS": None,
                "pauseSettledAtS": round(held_at, 3),
                "startFixedSiliconC": start_silicon,
                "endFixedSiliconC": silicon,
                "maxFixedSiliconC": max_silicon,
                "resume": resume, "display": display,
                "processHold": process_hold,
                "externalProcessHold": True,
                "paused": True, "holdMode": "process",
                "initialState": initial_state,
                "finalState": None,
                "startupHandoff": startup_handoff,
            }

    # Wait for the deadline request, not for another telemetry or liveness
    # command. If the timer did not run, send the pause here as a fail-safe.
    deadline_timer.join(timeout=8.0)
    pause = deadline_pause.get("result")
    if pause is None:
        if "requestedAtS" in deadline_pause:
            # The deadline callback is already inside its bounded request or
            # process fallback. Do not submit a second pause to the same
            # single-threaded control path while that callback still owns it.
            pause = {"pending": True, "source": "deadline"}
        else:
            deadline_timer.cancel()
            pause = api("/pause", "POST")

    def deadline_control_pending():
        result = deadline_pause.get("result")
        return ("requestedAtS" in deadline_pause and
                (result is None or
                 (isinstance(result, dict) and result.get("error") and
                  "processHold" not in deadline_pause)))

    def completed_deadline_hold():
        # The deadline thread can finish the process fallback after the first
        # join returns. Read its shared result at each control boundary. A
        # stopped process cannot answer the in-process API, so a single early
        # snapshot can otherwise turn a valid hold into repeated API timeouts.
        process_hold = deadline_pause.get("processHold")
        if not process_hold or not process_hold.get("ok"):
            return None
        settled = float(deadline_pause.get("settledAtS", elapsed))
        host_elapsed = time.monotonic() - started
        return {"completed": True, "requestedS": duration,
                "elapsedS": round(settled, 3),
                "hostElapsedS": round(host_elapsed, 3),
                "activeElapsedS": round(settled, 3),
                "pauseRequestedAtS": round(float(
                    deadline_pause.get("requestedAtS", elapsed)), 3),
                "pauseSettledAtS": round(settled, 3),
                "startFixedSiliconC": start_silicon,
                "endFixedSiliconC": silicon,
                "maxFixedSiliconC": max_silicon,
                "resume": resume,
                "pause": deadline_pause.get("result", pause),
                "display": display,
                "processHold": process_hold,
                "paused": True, "holdMode": "process",
                "initialState": initial_state,
                "finalState": deadline_pause.get("state"),
                "startupHandoff": startup_handoff}

    held_result = completed_deadline_hold()
    if held_result:
        return held_result

    # Check liveness only after the independent deadline pause. A pid read can
    # take more than one second on this device.
    if not pid():
        return {"error": "process gone during the bounded slice",
                "elapsedS": round(elapsed, 3),
                "maxFixedSiliconC": max_silicon, "pause": pause}

    held_result = completed_deadline_hold()
    if held_result:
        return held_result

    final_state = emulation_state()
    held_result = completed_deadline_hold()
    if held_result:
        return held_result
    paused = final_state in (EMU_STATE_PAUSED, EMU_STATE_READY)
    pause_started = time.monotonic()
    hold_timeout = startup_pause_timeout if startup_handoff else pause_timeout
    while not paused and time.monotonic() - pause_started < hold_timeout:
        held_result = completed_deadline_hold()
        if held_result:
            return held_result
        silicon = fixed_silicon_c()
        max_silicon = max(max_silicon, silicon)
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            active_elapsed = time.monotonic() - started
            return {"thermalStop": True,
                    "elapsedS": round(active_elapsed, 3),
                    "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "resume": resume,
                    "pause": pause, "stop": stop,
                    "initialState": initial_state,
                    "finalState": final_state,
                    "startupHandoff": startup_handoff}
        time.sleep(0.25)
        final_state = emulation_state()
        paused = final_state in (EMU_STATE_PAUSED, EMU_STATE_READY)
        # The first resume from Ready already requests pause-after-startup.
        # system_state::starting cannot accept a normal pause. Wait for that
        # one startup handoff while the fixed-silicon hard guard stays active.
        startup_is_starting = (
            startup_handoff and final_state == EMU_STATE_STARTING)
        if (not paused and not deadline_control_pending() and
                not startup_is_starting):
            pause = api("/pause", "POST")
            final_state = emulation_state()
            paused = final_state in (EMU_STATE_PAUSED, EMU_STATE_READY)

        held_result = completed_deadline_hold()
        if held_result:
            return held_result

    held_result = completed_deadline_hold()
    if held_result:
        return held_result

    if not paused:
        stop = t_stop({})
        active_elapsed = time.monotonic() - started
        return {"error": "the bounded slice could not restore a held state",
                "elapsedS": round(active_elapsed, 3),
                "pauseRequestedAtS": round(
                    float(deadline_pause.get("requestedAtS", elapsed)), 3),
                "startFixedSiliconC": start_silicon,
                "endFixedSiliconC": silicon,
                "maxFixedSiliconC": max_silicon,
                "resume": resume, "pause": pause, "stop": stop,
                "initialState": initial_state,
                "finalState": final_state,
                "startupHandoff": startup_handoff,
                "pauseTimeoutS": hold_timeout}

    active_elapsed = time.monotonic() - started
    result = {"completed": True, "requestedS": duration,
              "elapsedS": round(active_elapsed, 3),
              "hostElapsedS": round(active_elapsed, 3),
              "activeElapsedS": round(active_elapsed, 3),
              "pauseRequestedAtS": round(
                  float(deadline_pause.get("requestedAtS", elapsed)), 3),
              "pauseSettledAtS": round(active_elapsed, 3),
              "startFixedSiliconC": start_silicon,
              "endFixedSiliconC": silicon,
              "maxFixedSiliconC": max_silicon,
              "resume": resume, "pause": pause,
              "display": display,
              "paused": paused,
              "holdMode": "emulator",
              "initialState": initial_state,
              "finalState": final_state,
              "startupHandoff": startup_handoff}
    if a.get("includeState", True):
        result["device"] = api("/device")
        result["diag"] = api("/diag")
    return result


def t_wait_cool_paused(a):
    """Keep a paused guest still until fixed silicon reaches the resume target."""
    p = pid()
    if not p:
        return {"error": "emulator is not running"}
    process_held = held_process_pid() == p
    if not process_held and not is_paused():
        return {"refused": True,
                "reason": "the emulator must stay paused while it cools"}

    target = float(a.get("targetC", 70))
    hard_limit = float(a.get("maxSiliconC", 72))
    limit = int(a.get("timeoutS", 120))
    stable_samples = max(1, min(int(a.get("stableSamples", 1)), 5))
    sample_interval = max(
        0.25, min(float(a.get("sampleIntervalS", 2.0)), 5.0))
    waited = 0.0
    stable_count = 0

    while True:
        silicon = fixed_silicon_c()
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            return {"cooled": False, "thermalStop": True,
                    "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "stop": stop}

        stable_count = stable_count + 1 if silicon <= target else 0
        if stable_count >= stable_samples:
            break
        if waited >= limit:
            break

        interval = min(sample_interval, limit - waited)
        time.sleep(interval)
        waited += interval

    return {"cooled": stable_count >= stable_samples, "targetC": target,
            "fixedSiliconC": silicon,
            "cooledAtFixedSiliconC": silicon, "waitedS": waited,
            "stableSamples": stable_count,
            "requiredStableSamples": stable_samples,
            "sampleIntervalS": sample_interval,
            "paused": process_held or is_paused(),
            "holdMode": "process" if process_held else "emulator"}


def _matching_log_lines(match, count=1):
    if held_process_pid():
        raw = adb(["exec-out", "run-as", PKG, "tail", "-n", "4096",
                   f"{FILES}/cache/RPCSX.log"], timeout=30)
        return [line for line in raw.splitlines() if str(match) in line][-count:]
    encoded = urllib.parse.quote(str(match), safe="")
    result = api(f"/log?match={encoded}&n={int(count)}")
    if not isinstance(result, dict):
        return []
    lines = result.get("lines", [])
    return lines if isinstance(lines, list) else []


def t_slice_loop(a):
    """Own one slice and cool sequence until a log boundary or hard stop."""
    p = pid()
    if not p:
        return {"error": "emulator is not running"}
    # This tool can run in a new server.py process. Do not depend on a forward
    # that an earlier controller call happened to leave behind.
    ensure_forward()
    process_held = held_process_pid() == p
    initial_state = EMU_STATE_STARTING if process_held else emulation_state()
    allow_starting = bool(a.get("allowStarting", False))
    paused_state = initial_state in (EMU_STATE_PAUSED, EMU_STATE_READY)
    invalid_startup_state = initial_state in (
        EMU_STATE_STOPPED, EMU_STATE_STOPPING, EMU_STATE_FROZEN)
    if (not process_held and
            not paused_state and
            (not allow_starting or invalid_startup_state)):
        return {"refused": True,
                "reason": "the emulator must be paused before a slice loop",
                "initialState": initial_state,
                "processHeld": process_held,
                "allowStarting": allow_starting}

    duration_limit = max(
        15.0, min(float(a.get("maxDurationS", 15.0)), 300.0))
    duration = max(
        0.1, min(float(a.get("seconds", 1.0)), duration_limit))
    max_slices = max(1, min(int(a.get("maxSlices", 64)), 256))
    max_host_s = max(30.0, min(float(a.get("maxHostS", 420)), 600.0))
    max_active_s = max(
        0.0, min(float(a.get("maxActiveS", 0.0)), 300.0))
    start_ceiling = float(a.get("maxStartC", 70))
    resume_target = float(a.get("resumeTargetC", start_ceiling))
    resume_stable_samples = max(
        1, min(int(a.get("resumeStableSamples", 1)), 5))
    resume_sample_interval = max(
        0.25, min(float(a.get("resumeSampleIntervalS", 2.0)), 5.0))
    hard_limit = float(a.get("maxSiliconC", 72))
    cool_timeout = max(2, min(int(a.get("coolTimeoutS", 120)), 300))
    marker_every = max(1, min(int(a.get("markerEvery", 1)), 16))
    stop_match = str(a.get(
        "stopMatch", "Thor: SPURS shutdown completion event mask"))
    requested_stop_matches = a.get("stopMatches")
    stop_matches = []
    if isinstance(requested_stop_matches, list):
        for item in requested_stop_matches[:8]:
            value = str(item).strip()
            if value and value not in stop_matches:
                stop_matches.append(value)
    if not stop_matches:
        stop_matches = [stop_match]
    stop_match = stop_matches[0]
    arm_match = str(a.get("armMatch", ""))
    post_arm_slices = max(0, min(int(a.get("postArmSlices", 0)), 64))

    if (hard_limit <= start_ceiling or resume_target < 0 or
            resume_target >= hard_limit):
        return {"refused": True,
                "reason": ("maxSiliconC must be above maxStartC, and "
                           "resumeTargetC must be below maxSiliconC")}

    initial_pause_probe = None
    initial_pause_status = None
    initial_pause_state = initial_state
    initial_pause_attempts = 0
    initial_control_reachable = False
    if not process_held and not paused_state and allow_starting:
        # The status request can race the native start-paused Ready gate. Ask
        # the live control endpoint to confirm that gate before SIGSTOP. A
        # process hold taken first prevents the endpoint from releasing the
        # gate on the first bounded slice.
        for attempt in range(1, 9):
            initial_pause_attempts = attempt
            initial_pause_probe = api("/pause", "POST", timeout=0.5)
            initial_pause_status = api("/status", timeout=0.5)
            initial_pause_state = (
                initial_pause_status.get("state")
                if isinstance(initial_pause_status, dict) and
                isinstance(initial_pause_status.get("state"), int)
                else None
            )
            initial_control_reachable = initial_control_reachable or any(
                isinstance(result, dict) and "error" not in result
                for result in (initial_pause_probe, initial_pause_status)
            )
            if ((isinstance(initial_pause_probe, dict) and
                 initial_pause_probe.get("paused")) or
                    initial_pause_state in (
                        EMU_STATE_PAUSED, EMU_STATE_READY)):
                paused_state = True
                break
            if initial_pause_state in (
                    EMU_STATE_STOPPED, EMU_STATE_STOPPING, EMU_STATE_FROZEN):
                return {
                    "refused": True,
                    "reason": "the emulator left its startup handoff",
                    "initialState": initial_state,
                    "initialPauseProbe": initial_pause_probe,
                    "initialPauseStatus": initial_pause_status,
                    "initialPauseState": initial_pause_state,
                    "initialPauseAttempts": initial_pause_attempts,
                    "processHeld": False,
                    "allowStarting": allow_starting,
                }
            time.sleep(0.1)

    if (initial_pause_attempts and not initial_control_reachable):
        stop = t_stop({})
        return {
            "error": "the startup control API did not become reachable",
            "initialState": initial_state,
            "initialPauseProbe": initial_pause_probe,
            "initialPauseStatus": initial_pause_status,
            "initialPauseState": initial_pause_state,
            "initialPauseAttempts": initial_pause_attempts,
            "processHeld": False,
            "allowStarting": allow_starting,
            "stop": stop,
        }

    initial_process_hold = None
    if not process_held and not paused_state:
        initial_process_hold = stop_process_for_slice(p)
        if not initial_process_hold.get("ok"):
            stop = t_stop({})
            return {"error": "the startup process could not enter its initial hold",
                    "initialState": initial_state,
                    "initialPauseProbe": initial_pause_probe,
                    "initialPauseStatus": initial_pause_status,
                    "initialPauseState": initial_pause_state,
                    "initialPauseAttempts": initial_pause_attempts,
                    "initialProcessHold": initial_process_hold,
                    "stop": stop}

    records = []
    max_silicon = -1.0
    active_elapsed = 0.0
    loop_started = time.monotonic()
    armed_at_slice = None
    arm_lines = []

    def finish(fields):
        if len(stop_matches) > 1:
            fields["stopMatches"] = stop_matches
        if initial_pause_attempts:
            fields["initialPauseProbe"] = initial_pause_probe
            fields["initialPauseStatus"] = initial_pause_status
            fields["initialPauseState"] = initial_pause_state
            fields["initialPauseAttempts"] = initial_pause_attempts
        if initial_process_hold is not None:
            fields["initialProcessHold"] = initial_process_hold
        fields["completedSlices"] = len(records)
        fields["slices"] = records
        fields["maxFixedSiliconC"] = max_silicon
        fields["activeElapsedS"] = round(active_elapsed, 3)
        fields["hostElapsedS"] = round(time.monotonic() - loop_started, 3)
        fields["maxHostS"] = max_host_s
        if max_active_s > 0.0:
            fields["maxActiveS"] = max_active_s
        if armed_at_slice is not None:
            fields["armMatch"] = arm_match
            fields["armLines"] = arm_lines
            fields["armedAtSlice"] = armed_at_slice
            fields["postArmSlices"] = post_arm_slices
            fields["postArmSlicesCompleted"] = max(
                0, len(records) - armed_at_slice)
        if pid():
            process_held = held_process_pid()
            fields["paused"] = bool(process_held) or is_paused()
            fields["holdMode"] = "process" if process_held else "emulator"
            if not process_held:
                fields["device"] = api("/device")
                fields["diag"] = api("/diag")
        else:
            fields["paused"] = False
        return fields

    for index in range(1, max_slices + 1):
        remaining_host_s = max_host_s - (time.monotonic() - loop_started)
        if remaining_host_s <= 2.0:
            return finish({"markerReached": False,
                           "hostDeadlineReached": True,
                           "stopMatch": stop_match})

        cool_target = start_ceiling if index == 1 else resume_target
        cool = t_wait_cool_paused({
            "targetC": cool_target,
            "maxSiliconC": hard_limit,
            "timeoutS": min(cool_timeout, max(2, int(remaining_host_s))),
            "stableSamples": 1 if index == 1 else resume_stable_samples,
            "sampleIntervalS": resume_sample_interval,
        })
        cool_silicon = cool.get(
            "cooledAtFixedSiliconC",
            cool.get("triggerFixedSiliconC", cool.get("fixedSiliconC", -1)))
        if isinstance(cool_silicon, (int, float)):
            max_silicon = max(max_silicon, float(cool_silicon))

        if cool.get("thermalStop"):
            return finish({"markerReached": False, "thermalStop": True,
                           "cooldown": cool})
        if cool.get("error") or cool.get("refused"):
            return finish({"markerReached": False, "error":
                           cool.get("error") or cool.get("reason"),
                           "cooldown": cool})
        if not cool.get("cooled"):
            return finish({"markerReached": False, "cooled": False,
                           "reason": "the paused cooldown timed out",
                           "cooldown": cool})
        if not cool.get("paused"):
            stop = t_stop({})
            return finish({"markerReached": False,
                           "error": "the guest resumed during cooldown",
                           "stop": stop})

        part = t_slice({
            "seconds": duration,
            "maxDurationS": duration_limit,
            "maxStartC": start_ceiling,
            "maxSiliconC": hard_limit,
            "startupPauseTimeoutS": min(
                float(cool_timeout), max(8.0, remaining_host_s - 1.0)),
            "includeState": False,
        })
        part_max = part.get("maxFixedSiliconC",
                            part.get("triggerFixedSiliconC", -1))
        if isinstance(part_max, (int, float)):
            max_silicon = max(max_silicon, float(part_max))
        part_active = part.get("activeElapsedS", part.get("elapsedS", 0.0))
        if isinstance(part_active, (int, float)):
            active_elapsed += max(0.0, float(part_active))
        record = {
            "index": index,
            "coolTargetC": cool_target,
            "cooledAtFixedSiliconC": cool_silicon,
            "waitedS": cool.get("waitedS"),
            "coolStableSamples": cool.get("stableSamples"),
            "coolRequiredStableSamples": cool.get("requiredStableSamples"),
            "coolSampleIntervalS": cool.get("sampleIntervalS"),
            "requestedS": part.get("requestedS", duration),
            "elapsedS": part.get("elapsedS"),
            "pauseRequestedAtS": part.get("pauseRequestedAtS"),
            "pauseSettledAtS": part.get("pauseSettledAtS"),
            "activeElapsedS": part.get("activeElapsedS"),
            "hostElapsedS": part.get("hostElapsedS"),
            "startFixedSiliconC": part.get("startFixedSiliconC"),
            "endFixedSiliconC": part.get("endFixedSiliconC"),
            "maxFixedSiliconC": part.get("maxFixedSiliconC"),
            "initialState": part.get("initialState"),
            "finalState": part.get("finalState"),
            "startupHandoff": part.get("startupHandoff"),
            "holdMode": part.get("holdMode"),
        }
        records.append(record)

        if time.monotonic() - loop_started >= max_host_s:
            return finish({"markerReached": False,
                           "hostDeadlineReached": True,
                           "stopMatch": stop_match})

        if part.get("thermalStop"):
            return finish({"markerReached": False, "thermalStop": True,
                           "slice": part})
        if (part.get("error") or part.get("refused") or
                not part.get("completed") or not part.get("paused")):
            return finish({"markerReached": False,
                           "error": (part.get("error") or part.get("reason") or
                                     "the bounded slice did not end paused"),
                           "slice": part})

        for fatal_match in ("Access violation", "Verification failed", "Fatal",
                            "FATAL", "Out of memory"):
            fatal_lines = _matching_log_lines(fatal_match)
            if fatal_lines:
                stop = t_stop({})
                return finish({"markerReached": False, "fatal": fatal_match,
                               "fatalLines": fatal_lines, "stop": stop})

        if index % marker_every == 0:
            for candidate in stop_matches:
                marker_lines = _matching_log_lines(candidate)
                if marker_lines:
                    return finish({"markerReached": True,
                                   "markerKind": "stop-match",
                                   "stopMatch": candidate,
                                   "matchedStopMatch": candidate,
                                   "markerLines": marker_lines})

            if arm_match and armed_at_slice is None:
                matched_arm_lines = _matching_log_lines(arm_match)
                if matched_arm_lines:
                    armed_at_slice = index
                    arm_lines = matched_arm_lines

            if (armed_at_slice is not None and
                    index - armed_at_slice >= post_arm_slices):
                return finish({"markerReached": True,
                               "markerKind": "post-arm",
                               "stopMatch": stop_match})

        if max_active_s > 0.0 and active_elapsed >= max_active_s:
            return finish({"markerReached": False,
                           "activeBudgetReached": True,
                           "stopMatch": stop_match})

    return finish({"markerReached": False, "limitReached": True,
                   "stopMatch": stop_match})


def t_screenshot(a):
    """Pause, capture, and STAY paused so the picture is still true when you act."""
    p = pid()
    process_held = bool(p) and held_process_pid() == p
    paused = True if process_held else hold(a)
    # Resolve against the repository root, not the current directory. The
    # server starts from the workspace root or from the repository, and the
    # same argument must give the same file.
    out = os.path.join(REPO_ROOT, a.get("path") or "thor_shot.png")
    data = adb(["exec-out", "screencap", "-p"], binary=True)
    if len(data) < 1024:
        return {"error": f"screencap returned {len(data)} bytes"}
    with open(out, "wb") as f:
        f.write(data)
    if paused:
        hold_mode = "process" if process_held else "emulator"
        note = ("still PAUSED; the picture stays true until you resume. "
                "thor_press resumes for you and re-pauses after.")
    else:
        hold_mode = None
        note = "LIVE capture; the emulator runs on, so the scene may have changed."
    result = {"path": out, "bytes": len(data), "paused": paused,
              "holdMode": hold_mode, "note": note}
    if not process_held:
        result["scene"] = api("/scene")
    return result


def t_sample(a):
    """Measure, and REFUSE when the window is not measurable."""
    secs = int(a.get("seconds", 40))
    hard_limit = float(a.get("maxSiliconC", 72))
    p = pid()
    if not p:
        return {"error": "emulator is not running"}

    if is_paused():
        return {"void": True, "reason": "the emulator is PAUSED; a paused sample measures "
                                        "about 0.3 cores and means nothing. Resume first."}

    s0 = api("/scene")
    dev0 = api("/device")
    guard = dev0.get("device", {}).get("thermalGuardEngaged") if isinstance(dev0, dict) else None
    if isinstance(s0, dict) and s0.get("videoDecoding"):
        return {"void": True, "reason": "a movie is playing; a cutscene cannot resolve a measurement"}
    if guard:
        return {"void": True, "reason": "the thermal guard is engaged; this measures the guard's cap, not the lever"}

    c0 = proc_jiffies(p)
    th0 = api(f"/threads?match={a.get('threadMatch', '')}")
    elapsed = 0
    while elapsed < secs:
        interval = min(2, secs - elapsed)
        time.sleep(interval)
        elapsed += interval
        silicon = fixed_silicon_c()
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            return {"void": True, "thermalStop": True,
                    "triggerFixedSiliconC": silicon, "maxSiliconC": hard_limit,
                    "reason": ("the fixed-silicon sensor domain became unavailable"
                               if silicon < 0 else
                               f"fixed silicon reached the {hard_limit} C hard limit"),
                    "stop": stop}
    c1 = proc_jiffies(p)
    th1 = api(f"/threads?match={a.get('threadMatch', '')}")
    s1 = api("/scene")
    dev1 = api("/device")

    if isinstance(s1, dict) and s1.get("videoDecoding"):
        return {"void": True, "reason": "a movie started during the sample"}
    if c0 is None or c1 is None:
        return {"void": True, "reason": "process vanished during the sample"}

    def by_tid(t):
        return {r["tid"]: r for r in t.get("threads", [])} if isinstance(t, dict) else {}

    a0, a1 = by_tid(th0), by_tid(th1)
    threads = []
    for tid, row in a1.items():
        if tid in a0:
            d = row["jiffies"] - a0[tid]["jiffies"]
            if d > 0:
                threads.append({"name": row["name"], "cores": round(d / 100.0 / secs, 3)})
    threads.sort(key=lambda x: -x["cores"])

    return {
        "void": False,
        "seconds": secs,
        "coresBusy": round((c1 - c0) / 100.0 / secs, 3),
        "fpsBefore": dev0.get("device", {}).get("fps") if isinstance(dev0, dict) else None,
        "fpsAfter": dev1.get("device", {}).get("fps") if isinstance(dev1, dict) else None,
        "topThreads": threads[:8],
        "note": "frames go with CPU on purpose: CPU alone cannot tell a thread that "
                "stopped spinning from an emulator that stopped working",
    }


def t_log(a):
    # URL-ENCODE the match. It was interpolated raw, so any pattern containing a
    # space - which is most useful ones, e.g. "Thor DRAW CENSUS" - died with
    # InvalidURL before reaching the device.
    return api(f"/log?match={urllib.parse.quote(str(a.get('match', '')), safe='')}"
               f"&n={int(a.get('n', 40))}")


def t_setprop(a):
    name, value = a["name"], str(a.get("value", ""))
    sh(f"setprop {name} '{value}'")
    # Read the lever BACK. A harness once ran every arm unset while both arms
    # agreed perfectly.
    return {"name": name, "requested": value, "readback": sh(f"getprop {name}").strip()}


def _nonempty_thor_properties():
    rows = []
    pattern = re.compile(r"^\[(debug\.rpcsx\.thor\.[A-Za-z0-9_.-]+)\]: \[(.*)\]$")
    for line in sh("getprop").splitlines():
        match = pattern.match(line.strip())
        if match and match.group(2):
            rows.append({"name": match.group(1), "value": match.group(2)})
    return rows


def t_clearprops(_):
    """Clear all nonempty Thor experiment properties after a stopped run."""
    running_pid = pid()
    if running_pid:
        return {"refused": True,
                "reason": "stop the emulator before property cleanup",
                "pid": running_pid}

    before = _nonempty_thor_properties()
    for row in before:
        sh(f"setprop {row['name']} ''")
    remaining = _nonempty_thor_properties()
    remaining_names = {row["name"] for row in remaining}
    cleared = [row["name"] for row in before
               if row["name"] not in remaining_names]
    return {"beforeCount": len(before), "clearedCount": len(cleared),
            "cleared": cleared, "remainingCount": len(remaining),
            "remaining": remaining}


def t_stop(_):
    """Stop, and KEEP stopping. One force-stop loses to the app's respawn: the
    device once climbed 56 -> 79 -> 95 C after a stop that reported success,
    with the app back at 542% CPU while pidof had read empty."""
    global _process_hold_pid
    _process_hold_pid = None
    # An unreachable device answers empty, and an empty pidof and an empty top
    # read as quiet. Never report quiet for a device this call cannot reach.
    if not reachable():
        return {"quiet": False, "serial": SERIAL, "adbDevices": adb_devices(),
                "error": "device unreachable; nothing was stopped, and the emulator may still run"}
    for _ in range(5):
        sh(f"am force-stop {PKG}")
        p = pid()
        if p:
            sh(f"kill -9 {p}")
        time.sleep(2)
    sh("killall yes; svc power stayon false")
    time.sleep(2)

    # Confirm with top, not pidof. An unreachable device and a dead process both
    # answer empty, and a respawn refills the pid a second later.
    busy = sh("top -b -n 2 -d 2 -o %CPU 2>/dev/null | grep -ci rpcsx").strip()
    still_reachable = reachable()
    return {"pid": pid() or None, "rpcsxRowsInTop": busy,
            # grep -c prints 0 when nothing matches. Empty means top failed.
            "quiet": still_reachable and (not pid()) and busy == "0",
            "reachable": still_reachable,
            "note": "quiet means top agrees, not just pidof"}


# --------------------------------------------------------------------------
# A/B arms
# --------------------------------------------------------------------------
# thor_arm is the loop of tools/thor_transformers_diag_round.sh, which gave
# rounds K to S, moved into one tested place. Each step below is there because
# a number was wrong without it:
#
#   * a FRESH PROCESS per arm: each debug.rpcsx.thor.* property is read once
#     into a static for the life of the process;
#   * levers are PROPERTIES, not config: the managed profile rewrites the
#     per-title config at boot, and a boot without the managed profile applies
#     no profile at all (a 6.24 FPS "control" against a true 18.4);
#   * the savestate is pushed while the app is STOPPED (a running app held the
#     slot open: 123821207 bytes sent, 28180480 on the device);
#   * loadstate must answer ok:true: a failed load measures a lighter scene at
#     about 29 FPS;
#   * the scene gate is coresBusy above 4.5 with no movie: pressing through
#     cutscenes gave 3.78 and 5.89 cores for one configuration;
#   * the lever is read back off the device before the boot;
#   * the log is read for fatal lines before a number is believed.
#
# FPS is the frame counter's change over the window, not a point reading.
TITLE_ISOS = {
    "BLUS30357": "/storage/2664-21DE/Roms/ps3/Transformers War for Cybertron.iso",
}
VAULT = os.path.join(REPO_ROOT, "debug-captures", "savestates")
FATAL_RE = re.compile(r"fatal error|Dead FIFO|Access violation|SPU trap|thermal abort", re.I)
# The in-app guard's ENGAGED line is counted apart. It caps FPS at 30 on
# 2026-09-22, above restored combat at about 21 FPS, and each combat boot
# engages it. The windows check whether the cap binds.
GUARD_RE = re.compile(r"Thermal guard ENGAGED", re.I)
PROP_NAME_RE = re.compile(r"debug\.rpcsx\.thor\.[A-Za-z0-9_.]+")
PROP_VALUE_RE = re.compile(r"[A-Za-z0-9_.:,+-]*")


class _ArmStop(Exception):
    """End an arm early. The fields say why. The arm is then not valid."""

    def __init__(self, reason, **fields):
        super().__init__(reason)
        self.fields = dict(reason=reason, **fields)


def _clamp(value, low, high):
    return max(low, min(value, high))


def _device():
    d = api("/device")
    return d.get("device", {}) if isinstance(d, dict) else {}


def _scene():
    s = api("/scene")
    return s if isinstance(s, dict) else {}


def _vault_file(title, name=None):
    """The newest vault savestate for a title, as tools/thor_savestate_vault.sh
    picks it, or the named file."""
    folder = os.path.join(VAULT, title)
    if name:
        path = name if os.path.isabs(name) else os.path.join(folder, name)
        return path if os.path.isfile(path) else None
    try:
        files = [os.path.join(folder, f) for f in os.listdir(folder)
                 if f.endswith(".SAVESTAT.zst")]
    except OSError:
        return None
    return max(files, key=os.path.getmtime) if files else None


def _push_savestate(title, local):
    """Push a vault savestate into the app's slot. The app must be STOPPED.

    Shell cannot create files in the app's directory, so the file goes to
    /data/local/tmp and the app's own uid copies it. The old slot is removed
    first: a failed push once passed the byte check because the device still
    held a good copy."""
    folder = f"{FILES}/config/savestates/{title}"
    dst = f"{folder}/{title}_1_0.SAVESTAT.zst"
    stage = f"/data/local/tmp/thor_ss_{title}.zst"
    sh(f"mkdir -p {folder}; run-as {PKG} rm -f {dst}")
    adb(["push", local, stage], timeout=600)
    sh(f"run-as {PKG} cp {stage} {dst}; rm -f {stage}", timeout=180)
    local_n = os.path.getsize(local)
    # stat and wc fail on this path for shell; field 5 of ls -l works.
    fields = sh(f"ls -l {dst} 2>/dev/null").split()
    dev_n = int(fields[4]) if len(fields) > 4 and fields[4].isdigit() else -1
    return {"file": os.path.basename(local), "localBytes": local_n,
            "deviceBytes": dev_n, "match": local_n == dev_n}


def _score_shot(path):
    """A black frame is about 29 KB with about 160 colours. A drawn combat frame
    is about 2 MB with more than 16,000."""
    size = os.path.getsize(path) if os.path.isfile(path) else 0
    colours = None
    try:
        from PIL import Image
        im = Image.open(path).convert("RGB")
        im = im.resize((max(1, im.width // 4), max(1, im.height // 4)))
        colours = len(set(im.getdata()))
    except Exception:
        pass
    drawn = size > 300000 or (colours or 0) > 4000
    return {"bytes": size, "colours": colours, "verdict": "DRAWN" if drawn else "BLANK?"}


def _summarize_log(path, match=None):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return {"missing": True}
    fatal = [line[-200:] for line in lines if FATAL_RE.search(line)]
    guard = [line[-160:] for line in lines if GUARD_RE.search(line)]
    levers = [line.split("Thor:", 1)[1].strip()[:160] for line in lines
              if "Thor:" in line and any(k in line for k in ("forced", "set to", "ignoring", "applied"))]
    frames = [line[line.index("Frames:"):][:300] for line in lines if "Frames:" in line]
    out = {"path": path, "lines": len(lines), "fatalCount": len(fatal), "fatal": fatal[:6],
           "guardCount": len(guard), "guard": guard[-2:],
           "levers": levers[:12], "framesLines": len(frames), "lastFrames": frames[-3:]}
    if match:
        rx = re.compile(match)
        hits = [line[-200:] for line in lines if rx.search(line)]
        out["match"] = {"pattern": match, "count": len(hits), "last": hits[-3:]}
    return out


def _stats(values):
    values = [v for v in values if isinstance(v, (int, float))]
    if not values:
        return None
    return {"mean": round(sum(values) / len(values), 2), "min": round(min(values), 2),
            "max": round(max(values), 2), "n": len(values)}


def t_arm(a):
    """Run ONE A/B arm from a clean start, and return its numbers and evidence."""
    started = time.time()
    name = str(a.get("name") or "arm")
    props = {str(k): str(v) for k, v in (a.get("props") or {}).items()}
    title = str(a.get("titleId", "BLUS30357"))
    iso = a.get("isoPath") or TITLE_ISOS.get(title)
    if not iso:
        return {"refused": True, "reason": f"no isoPath given, and no default for {title}"}
    for k, v in props.items():
        if not PROP_NAME_RE.fullmatch(k):
            return {"refused": True, "reason": f"{k} is not a debug.rpcsx.thor property. "
                    "Arms are properties: the managed profile rewrites the config at boot."}
        if not PROP_VALUE_RE.fullmatch(v):
            return {"refused": True, "reason": f"value {v!r} for {k} has characters a shell would change"}
    use_state = bool(a.get("savestate", True))
    play_s = _clamp(float(a.get("playS", 60)), 10.0, 300.0)
    samples = int(_clamp(int(a.get("samples", 3)), 1, 10))
    gate_cores = float(a.get("gateCores", 4.5))
    ready_timeout = _clamp(int(a.get("readyTimeoutS", 420)), 30, 900)
    gate_timeout = _clamp(int(a.get("gateTimeoutS", 150)), 15, 600)
    start_ceiling = float(a.get("maxStartC", 70))
    start_junction = float(a.get("maxStartJunctionC", 55))
    # The owner chose a junction limit for arms on 2026-09-22. A Transformers
    # boot took fixed silicon from 45.8 C to 81.5 C in seconds, so no arm can
    # reach combat under the 72 C fixed-silicon stop. 95 C is the runtime
    # junction limit. Restored combat reached 96 C in its first window, so a
    # combat arm stops there. Rounds K to S ran to the app's abort at 97 C
    # (thermal_abort_c). The limit for combat arms is not decided.
    junction_limit = float(a.get("maxJunctionC", 95))
    silicon_limit = a.get("maxSiliconC")
    silicon_limit = float(silicon_limit) if silicon_limit is not None else None
    cool_timeout = _clamp(int(a.get("coolTimeoutS", 480)), 0, 900)
    host_limit = _clamp(float(a.get("maxHostS", 900)), 120.0, 1800.0)
    # Relative to the repository root, as for thor_screenshot.
    run_dir = os.path.join(REPO_ROOT, a.get("runDir") or os.path.join(
        "debug-captures", time.strftime("%Y%m%d-%H%M%S") + "-mcp-ab"))
    os.makedirs(run_dir, exist_ok=True)
    tag = time.strftime("%H%M%S") + "-" + re.sub(r"[^A-Za-z0-9_.-]", "_", name)[:40]

    out = {"arm": name, "props": props, "titleId": title, "tag": tag,
           "runDir": run_dir, "valid": False}
    peak = {"junction": -1, "silicon": -1.0}
    booted = False

    def budget(phase):
        if time.time() - started > host_limit:
            raise _ArmStop(f"the {host_limit:.0f} s host limit ended the arm before {phase}")

    def thermal(phase):
        j, s = temp_c(), fixed_silicon_c()
        peak["junction"] = max(peak["junction"], j)
        peak["silicon"] = max(peak["silicon"], s)
        if j < 0:
            raise _ArmStop("the CPU-junction sensors are unavailable", thermalStop=True)
        if j >= junction_limit:
            raise _ArmStop(f"CPU junction reached {j} C, at or above the {junction_limit} C "
                           f"limit, during {phase}", thermalStop=True, triggerJunctionC=j)
        if silicon_limit is not None and (s < 0 or s >= silicon_limit):
            raise _ArmStop(f"fixed silicon reached {s} C, at or above the {silicon_limit} C "
                           f"limit, during {phase}", thermalStop=True, triggerFixedSiliconC=s)

    def watch(seconds, phase):
        """Wait, and read the temperatures every second while the guest runs."""
        end = time.time() + seconds
        while True:
            thermal(phase)
            left = end - time.time()
            if left <= 0:
                return
            time.sleep(min(1.0, left))

    try:
        if not reachable():
            raise _ArmStop("device unreachable")

        stop = t_stop({})
        if not stop.get("quiet"):
            raise _ArmStop("the emulator did not stop before the arm", stop=stop)
        leftovers = _nonempty_thor_properties()
        for row in leftovers:
            sh(f"setprop {row['name']} ''")
        out["clearedBefore"] = leftovers

        if use_state:
            local = _vault_file(title, a.get("savestateFile"))
            if not local:
                raise _ArmStop(f"no savestate for {title} in {VAULT}")
            push = _push_savestate(title, local)
            out["savestate"] = push
            if not push["match"]:
                raise _ArmStop("the savestate byte counts differ; a short file loads another scene")

        budget("the cooldown")

        def too_warm():
            s, j = fixed_silicon_c(), temp_c()
            return (s < 0 or s >= start_ceiling or j < 0 or j >= start_junction), s, j

        waited = 0
        warm, s, j = too_warm()
        while warm and waited < cool_timeout:
            time.sleep(5)
            waited += 5
            warm, s, j = too_warm()
        if warm:
            raise _ArmStop(f"not below {start_ceiling} C fixed silicon and {start_junction} C "
                           f"junction after {cool_timeout} s", fixedSiliconC=s, junctionC=j)
        # Equal starts keep the arms comparable. The round script started below
        # 55 C junction.
        out.update(startFixedSiliconC=s, startJunctionC=j, cooledS=waited,
                   battery=sh("cat /sys/class/power_supply/battery/capacity").strip())

        sh("setprop debug.rpcsx.thor.thermal_abort_c 97")
        for k, v in props.items():
            sh(f"setprop {k} '{v}'")
        readback = {k: sh(f"getprop {k}").strip() for k in props}
        out["readback"] = readback
        if any(readback[k] != props[k] for k in props):
            raise _ArmStop("a property did not read back as set", expected=props)

        budget("the boot")
        sh(f"rm -f {FILES}/cache/RPCSX.log; logcat -c; input keyevent KEYCODE_WAKEUP; "
           "svc power stayon true")
        sh(f"am start -a net.rpcsx.THOR_DEBUG_BOOT -n {PKG}/net.rpcsx.MainActivity "
           f"--es path '{iso}' --es titleId {title} --es thorDebugBootRequestId mcp-arm "
           f"--ez thorRequireManagedProfile true --ez thorReplaceCustomProfile true")
        booted = True
        ensure_forward()
        boot_t = time.time()
        while True:
            budget("the first frame")
            watch(5, "the boot")
            if time.time() - boot_t > 15 and not pid():
                raise _ArmStop("the process ended during the boot")
            if float(_device().get("fps") or 0) > 0:
                break
            if time.time() - boot_t > ready_timeout:
                raise _ArmStop(f"no frame in {ready_timeout} s")
        out["firstFrameS"] = round(time.time() - boot_t, 1)

        if use_state:
            # One request at a time. The load call can block while the reload
            # runs, and a second request during a load is refused with "no
            # compatible savestate" (2026-09-22). So a lost answer is checked
            # against the core's own log line before another request is sent.
            loaded, responses = None, []
            for attempt in range(1, 4):
                budget("the savestate load")
                r = api("/loadstate", "POST", timeout=60)
                responses.append(r)
                if isinstance(r, dict) and r.get("ok") is True:
                    loaded = "ok:true"
                    break
                if isinstance(r, dict) and r.get("ok") is False:
                    watch(12, "the savestate load")
                    continue
                seen = api("/log?match=" + urllib.parse.quote(
                    "Booting the most recent savestate", safe="") + "&n=1")
                # Count the lines. The answer echoes the match text, so a
                # text search of the whole answer always finds it.
                if isinstance(seen, dict) and seen.get("lines"):
                    loaded = "the core logged the reload; the answer was lost"
                    break
                watch(12, "the savestate load")
            out["loadResponses"] = responses
            if not loaded:
                raise _ArmStop("the savestate did not load; a failed load measures a lighter scene")
            out["load"] = loaded

        gate_t = time.time()
        while True:
            budget("the scene gate")
            watch(5, "the scene gate")
            cores = float(_device().get("coresBusy") or 0)
            scene = _scene()
            no_movie = scene.get("videoDecoding") is False and scene.get("videoFilesOpen") == 0
            if cores > gate_cores and no_movie:
                break
            if not pid():
                raise _ArmStop("the process ended before the scene gate")
            if time.time() - gate_t > gate_timeout:
                raise _ArmStop(f"not in the measured scene after {gate_timeout} s: coresBusy "
                               f"{cores}, gate {gate_cores}", scene=scene)
        out.update(gateS=round(time.time() - gate_t, 1), gateCoresBusy=cores,
                   drawsLastFrame=scene.get("drawsLastFrame"))

        shot = os.path.join(run_dir, f"scene_{tag}.png")
        with open(shot, "wb") as f:
            f.write(adb(["exec-out", "screencap", "-p"], binary=True, timeout=60))
        out["shot"] = dict(path=shot, **_score_shot(shot))

        windows = []
        for i in range(samples):
            budget("a sample window")
            p = pid()
            d0, j0, t0 = _device(), proc_jiffies(p) if p else None, time.time()
            watch(play_s / samples, "a sample window")
            d1, j1, t1 = _device(), proc_jiffies(p) if p else None, time.time()
            scene = _scene()
            dt = t1 - t0
            w = {"i": i + 1, "seconds": round(dt, 1), "fpsPoint": d1.get("fps"),
                 "junctionC": d1.get("cpuJunctionC"), "fixedSiliconC": fixed_silicon_c()}
            try:
                w["fps"] = round((int(d1["frames"]) - int(d0["frames"])) / dt, 2)
            except (KeyError, TypeError, ValueError):
                w["fps"] = None
            w["cores"] = round((j1 - j0) / 100.0 / dt, 3) if j0 is not None and j1 is not None else None
            void = []
            # The in-app guard caps FPS while it is engaged (87 C, 30 FPS on
            # 2026-09-22). Two arms once read exactly 20.00 FPS at an older
            # cap. A window at the cap measures the guard. Below the cap, the
            # guard limits nothing, and restored combat runs at about 94 C.
            guard = bool(d0.get("thermalGuardEngaged") or d1.get("thermalGuardEngaged"))
            cap = float(d1.get("thermalGuardCapFps") or d0.get("thermalGuardCapFps") or 0)
            w["guardEngaged"] = guard
            if guard and (not cap or (w["fps"] is not None and w["fps"] >= cap - 0.5)):
                void.append(f"the thermal guard was engaged and FPS is at its {cap:g} FPS cap")
            if scene.get("videoDecoding"):
                void.append("a movie was playing")
            if w["fps"] is None or w["cores"] is None:
                void.append("a counter was missing")
            alive = pid() == p and bool(p)
            if not alive:
                void.append("the process ended")
            w["void"] = "; ".join(void) or None
            windows.append(w)
            if not alive:
                out["windows"] = windows
                raise _ArmStop("the process ended during a sample window")
        out["windows"] = windows
    except _ArmStop as e:
        out.update(e.fields)
    except Exception as e:  # the stop below must still run
        out["reason"] = f"{type(e).__name__}: {e}"
    finally:
        if booted:
            log_path = os.path.join(run_dir, f"RPCSX_{tag}.log")
            try:
                data = adb(["exec-out", f"cat {FILES}/cache/RPCSX.log"], binary=True, timeout=300)
                with open(log_path, "wb") as f:
                    f.write(data)
                out["log"] = _summarize_log(log_path, a.get("logMatch"))
            except Exception as e:
                out["log"] = {"error": f"{type(e).__name__}: {e}"}
        out["stop"] = t_stop({})
        for row in _nonempty_thor_properties():
            sh(f"setprop {row['name']} ''")
        out["propsLeft"] = _nonempty_thor_properties()
        out["peakJunctionC"] = peak["junction"]
        out["peakFixedSiliconC"] = peak["silicon"]
        out["endFixedSiliconC"] = fixed_silicon_c()
        out["hostS"] = round(time.time() - started, 1)

    good = [w for w in out.get("windows", []) if not w["void"]]
    out["fps"] = _stats([w["fps"] for w in good])
    out["cores"] = _stats([w["cores"] for w in good])
    problems = []
    if "reason" in out:
        problems.append(out["reason"])
    if len(good) != samples:
        problems.append(f"{len(good)} of {samples} windows are valid")
    if (out.get("log") or {}).get("fatalCount"):
        problems.append("the log has fatal lines")
    if (out.get("shot") or {}).get("verdict") not in (None, "DRAWN"):
        problems.append("the screenshot is not drawn")
    out["valid"] = not problems
    out["problems"] = problems
    try:
        with open(os.path.join(run_dir, "results.jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(out) + "\n")
    except OSError as e:
        out["resultsWriteError"] = str(e)
    return out


def t_ab_table(a):
    """Build the A/B table for a run directory from its results.jsonl."""
    if not a.get("runDir"):
        return {"refused": True, "reason": "runDir is required"}
    run_dir = os.path.join(REPO_ROOT, a["runDir"])
    try:
        with open(os.path.join(run_dir, "results.jsonl"), encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
    except OSError as e:
        return {"error": f"no results in {run_dir}: {e}"}
    order, arms = [], {}
    for r in rows:
        if r["arm"] not in arms:
            order.append(r["arm"])
            arms[r["arm"]] = {"fps": [], "cores": [], "invalid": []}
        if r.get("valid") and r.get("fps"):
            arms[r["arm"]]["fps"].append(r["fps"]["mean"])
            arms[r["arm"]]["cores"].append((r.get("cores") or {}).get("mean"))
        else:
            arms[r["arm"]]["invalid"].append({"tag": r.get("tag"), "problems": r.get("problems")})
    control = a.get("control") or order[0]
    if control not in arms:
        return {"error": f"no arm named {control}", "arms": order}
    c = _stats(arms[control]["fps"])
    table = []
    for name in order:
        fps = _stats(arms[name]["fps"])
        row = {"arm": name, "fps": fps, "cores": _stats(arms[name]["cores"]),
               "runs": arms[name]["fps"], "invalid": arms[name]["invalid"]}
        if name != control and fps and c:
            row["fpsVsControlPct"] = round(100.0 * (fps["mean"] - c["mean"]) / c["mean"], 1)
            overlap = not (fps["min"] > c["max"] or fps["max"] < c["min"])
            if fps["n"] < 2 or c["n"] < 2:
                row["verdict"] = "not shown: n=1. Never quote n=1."
            elif overlap:
                row["verdict"] = "not shown: the ranges overlap"
            else:
                row["verdict"] = "shown: the ranges do not overlap"
        table.append(row)
    return {"runDir": run_dir, "control": control, "table": table,
            "note": "a restored savestate varies about +/-5 percent in one configuration; "
                    "a smaller difference is not a result"}


TOOLS = [
    ("thor_state", "PAUSES BY DEFAULT, then reports device and emulator state at once: reachability, pid, temperature, battery, status, telemetry, compile progress, config in effect, SPURS state. pause=false for a live reading that does not pause.", {"type": "object", "properties": {"pause": {"type": "boolean", "description": "Default true. false reads the state without a pause."}}}, t_state),
    ("thor_cooldown", "Force-stop the emulator, then wait for the CPU junction to fall below targetC. Stops first on purpose: cooling while the emulator runs never finishes.", {"type": "object", "properties": {"targetC": {"type": "integer"}, "timeoutS": {"type": "integer"}}}, t_cooldown),
    ("thor_boot", "Boot a title below the fixed-silicon start ceiling. freshCompile (default true) turns the SPU object cache OFF. sameProcess (default false) boots into the running process after thor_exit_game, with no force-stop: the path a user takes after Exit Game.", {"type": "object", "properties": {"sameProcess": {"type": "boolean"}, "titleId": {"type": "string"}, "isoPath": {"type": "string"}, "freshCompile": {"type": "boolean"}, "maxStartC": {"type": "number"}}, "required": ["titleId", "isoPath"]}, t_boot),
    ("thor_wait_ready", "Wait until the title renders. Poll fixed silicon every two seconds and stop at the hard limit.", {"type": "object", "properties": {"timeoutS": {"type": "integer"}, "minFps": {"type": "number"}, "maxSiliconC": {"type": "number"}}}, t_wait_ready),
    ("thor_press", "Press pad buttons. If paused, require a below-ceiling start, resume, monitor fixed silicon, and re-pause.", {"type": "object", "properties": {"buttons": {"type": "string"}, "ms": {"type": "integer"}, "settleS": {"type": "number"}, "maxStartC": {"type": "number"}, "maxSiliconC": {"type": "number"}, "rePause": {"type": "boolean", "description": "Default true. false leaves the emulator running after the press."}}, "required": ["buttons"]}, t_press),
    ("thor_pause", "Pause emulation, so a screenshot and a decision do not race the scene. Pause, look, decide, resume, press.", {"type": "object", "properties": {}}, t_pause),
    ("thor_resume", "Resume emulation after thor_pause.", {"type": "object", "properties": {}}, t_resume),
    ("thor_slice", "Run a paused guest for 0.1 to 15 seconds by default. An explicit maxDurationS can extend an exact handoff window to 300 seconds. Monitor fixed silicon every 0.25 seconds, and pause again.", {"type": "object", "properties": {"seconds": {"type": "number"}, "maxDurationS": {"type": "number"}, "maxStartC": {"type": "number"}, "maxSiliconC": {"type": "number"}, "pauseTimeoutS": {"type": "number", "description": "Wait for the pause after the slice, 1 to 30 s. Default 8."}, "startupPauseTimeoutS": {"type": "number", "description": "The same wait during a startup handoff, up to 300 s. Default 120."}, "includeState": {"type": "boolean", "description": "Default true. false leaves /device and /diag out of the answer."}}}, t_slice),
    ("thor_slice_loop", "Run the first slice below the cold-start ceiling, then cool to or below the runtime resume target between slices. Return within the host and active-time limits, and keep log-boundary checks and hard stops in one controller. An explicit maxDurationS can extend an exact handoff window to 300 seconds.", {"type": "object", "properties": {"seconds": {"type": "number"}, "maxDurationS": {"type": "number"}, "maxSlices": {"type": "integer"}, "maxHostS": {"type": "number"}, "maxActiveS": {"type": "number"}, "coolTimeoutS": {"type": "integer"}, "maxStartC": {"type": "number"}, "resumeTargetC": {"type": "number"}, "resumeStableSamples": {"type": "integer"}, "resumeSampleIntervalS": {"type": "number"}, "maxSiliconC": {"type": "number"}, "stopMatch": {"type": "string"}, "stopMatches": {"type": "array", "items": {"type": "string"}}, "armMatch": {"type": "string"}, "postArmSlices": {"type": "integer"}, "markerEvery": {"type": "integer"}, "allowStarting": {"type": "boolean"}}}, t_slice_loop),
    ("thor_wait_cool_paused", "Wait with the guest paused until fixed silicon stays at or below targetC for the requested stable sample count. Stop if it reaches the hard limit.", {"type": "object", "properties": {"targetC": {"type": "number"}, "maxSiliconC": {"type": "number"}, "timeoutS": {"type": "integer"}, "stableSamples": {"type": "integer"}, "sampleIntervalS": {"type": "number"}}}, t_wait_cool_paused),
    ("thor_screenshot", "PAUSES BY DEFAULT, captures a PNG, and STAYS PAUSED so the picture is still true when you act. pause=false for a live capture.", {"type": "object", "properties": {"path": {"type": "string"}, "pause": {"type": "boolean", "description": "Default true. false captures without a pause."}}}, t_screenshot),
    ("thor_sample", "Measure process and per-thread CPU. Refuse invalid states and stop at the fixed-silicon hard limit.", {"type": "object", "properties": {"seconds": {"type": "integer"}, "threadMatch": {"type": "string"}, "maxSiliconC": {"type": "number"}}}, t_sample),
    ("thor_log", "Tail the emulator log, filtered. Read this for a fatal error BEFORE believing any measurement.", {"type": "object", "properties": {"match": {"type": "string"}, "n": {"type": "integer"}}}, t_log),
    ("thor_setprop", "Set a debug property and read it back, so an arm cannot silently run unset.", {"type": "object", "properties": {"name": {"type": "string"}, "value": {"type": "string"}}, "required": ["name"]}, t_setprop),
    ("thor_clearprops", "Clear all nonempty debug.rpcsx.thor properties after the emulator has stopped, then audit the result.", {"type": "object", "properties": {}}, t_clearprops),
    ("thor_exit_game", "Exit the running game the way the home menu Exit Game does, releasing any process hold first. Reports when the core reached Stopped, when the game activity closed, and any self-join log lines. Follow with thor_boot sameProcess=true to test the next game in the same process.", {"type": "object", "properties": {"timeoutS": {"type": "integer"}}}, t_exit_game),
    ("thor_stop", "Force-stop the emulator, kill stressors, release the screen lock, and report the device is quiet.", {"type": "object", "properties": {}}, t_stop),
    ("thor_arm", "Run ONE A/B arm from a clean start: stop, clear properties, push the vault savestate, cool below maxStartC fixed silicon and maxStartJunctionC junction, set and read back the arm's debug.rpcsx.thor properties, boot with the managed profile, wait for a frame, load the savestate (ok:true required), gate on coresBusy above gateCores with no movie, score a screenshot, sample FPS (frame counter) and cores in windows, pull and check the log, stop, and clear the properties. Stops at the CPU-junction limit maxJunctionC (95 C), not at the 72 C fixed-silicon limit of the other tools. Appends the result to runDir/results.jsonl. Call it once per arm in ABBA order, then call thor_ab_table.", {"type": "object", "properties": {
        "name": {"type": "string", "description": "Arm name. Runs with the same name are grouped in the table."},
        "props": {"type": "object", "additionalProperties": {"type": "string"}, "description": "debug.rpcsx.thor.* property to value. Empty for a control arm."},
        "titleId": {"type": "string", "description": "Default BLUS30357."},
        "isoPath": {"type": "string", "description": "Device path of the disc image. Known for BLUS30357."},
        "savestate": {"type": "boolean", "description": "Default true: push and load the newest vault savestate."},
        "savestateFile": {"type": "string", "description": "A vault file name, instead of the newest."},
        "playS": {"type": "number", "description": "Measured seconds, 10 to 300. Default 60."},
        "samples": {"type": "integer", "description": "Windows in playS, 1 to 10. Default 3."},
        "gateCores": {"type": "number", "description": "Scene gate on coresBusy. Default 4.5 (restored combat)."},
        "readyTimeoutS": {"type": "integer", "description": "Wait for the first frame. Default 420."},
        "gateTimeoutS": {"type": "integer", "description": "Wait for the scene gate. Default 150."},
        "maxStartC": {"type": "number", "description": "Start ceiling, fixed silicon. Default 70."},
        "maxStartJunctionC": {"type": "number", "description": "Start ceiling, CPU junction. Default 55, as the round script used."},
        "maxJunctionC": {"type": "number", "description": "Hard stop, CPU junction. Default 95 (chosen by the owner on 2026-09-22)."},
        "maxSiliconC": {"type": "number", "description": "Optional second hard stop, fixed silicon. No default: a Transformers boot passes 72 C."},
        "coolTimeoutS": {"type": "integer", "description": "Wait to cool below maxStartC. Default 480."},
        "maxHostS": {"type": "number", "description": "Host time limit for the arm, 120 to 1800 s. Default 900."},
        "runDir": {"type": "string", "description": "Directory for results. Default: a new debug-captures/<time>-mcp-ab."},
        "logMatch": {"type": "string", "description": "A regular expression to count in the log, for example a lever's counter line."}}}, t_arm),
    ("thor_ab_table", "Build the A/B table from runDir/results.jsonl: per arm the FPS and cores over its valid runs, the change against the control, and a verdict. Overlapping ranges, or n=1, is 'not shown'.", {"type": "object", "properties": {
        "runDir": {"type": "string"},
        "control": {"type": "string", "description": "Control arm name. Default: the first arm run."}}, "required": ["runDir"]}, t_ab_table),
]
HANDLERS = {name: fn for name, _, _, fn in TOOLS}


# --------------------------------------------------------------------------
# MCP stdio loop
# --------------------------------------------------------------------------
def send(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue

        method, rid = req.get("method"), req.get("id")

        if method == "initialize":
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "thor", "version": "1.0.0"}}})
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": rid, "result": {"tools": [
                {"name": n, "description": d, "inputSchema": s} for n, d, s, _ in TOOLS]}})
        elif method == "tools/call":
            params = req.get("params", {})
            fn = HANDLERS.get(params.get("name"))
            if fn is None:
                send({"jsonrpc": "2.0", "id": rid,
                      "error": {"code": -32601, "message": f"no tool {params.get('name')}"}})
                continue
            ensure_serial()
            try:
                out = fn(params.get("arguments") or {})
            except Exception as e:  # a crash here must not kill the server
                out = {"error": f"{type(e).__name__}: {e}"}

            # TEMPERATURE ON EVERY RESPONSE, no exceptions.
            #
            # This device was roasted more than once because the temperature was
            # something to remember to check. It reached 95 C while the caller
            # believed nothing was running, because `am force-stop` loses to the
            # app's respawn and `pidof` read empty a moment earlier by timing.
            #
            # So every tool answers with the temperature and, when it is high,
            # says what to do about it. A number nobody asked for is the only
            # kind that gets seen in time.
            if isinstance(out, dict) and not SERIAL:
                out["NO_DEVICE"] = ("adb lists no ready AYN Thor, so nothing was read or "
                                    "stopped. Connect it, then call again.")
                out["adbDevices"] = adb_devices()
            elif isinstance(out, dict):
                junction = temp_c()
                silicon = fixed_silicon_c()
                out["cpuJunctionC"] = junction
                out["fixedSiliconC"] = silicon
                if silicon < 0:
                    out["THERMAL"] = "The fixed-silicon sensor domain is unavailable. Stop the run."
                elif silicon >= 72:
                    out["THERMAL"] = ("HARD LIMIT %.1f C fixed silicon. Stop the run and verify "
                                      "with top, not pidof." % silicon)
                elif silicon >= 70:
                    out["THERMAL"] = "WARM %.1f C fixed silicon. Do not start another arm." % silicon
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": json.dumps(out, indent=2)}]}})
        elif rid is not None:
            send({"jsonrpc": "2.0", "id": rid, "result": {}})


if __name__ == "__main__":
    main()
