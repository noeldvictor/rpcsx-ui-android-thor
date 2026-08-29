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
import subprocess
import sys
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
SERIAL = os.environ.get("THOR_SERIAL", "192.168.1.3:5555")
PORT = int(os.environ.get("THOR_CTRL_PORT", "8099"))
PKG = "net.rpcsx.easy"
FILES = f"/storage/emulated/0/Android/data/{PKG}/files"


# --------------------------------------------------------------------------
# device plumbing
# --------------------------------------------------------------------------
def sh(cmd, timeout=120):
    """Run one adb shell command. MSYS_NO_PATHCONV stops Git Bash rewriting
    DEVICE paths into local ones, which fails with a confusing error."""
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    try:
        out = subprocess.run([ADB, "-s", SERIAL, "shell", cmd],
                             capture_output=True, timeout=timeout, env=env)
        return out.stdout.decode("utf-8", "replace").replace("\r", "")
    except subprocess.TimeoutExpired:
        return ""


def adb(args, timeout=300, binary=False):
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    out = subprocess.run([ADB, "-s", SERIAL] + args, capture_output=True,
                         timeout=timeout, env=env)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace").replace("\r", "")


def reachable():
    """An unreachable device answers empty exactly like a dead process, so this
    is checked separately before any liveness claim."""
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
    SoC and XO sensors are the fixed domain used by the repository guard.
    """
    raw = sh(r"""for z in /sys/class/thermal/thermal_zone*; do t=$(cat $z/temp 2>/dev/null); n=$(cat $z/type 2>/dev/null); case $n in cpuss-*|gpuss-*|ddr|socd|xo-therm) [ -n "$t" ] && echo "$t";; esac; done""")
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
        return {"error": f"control API unreachable: {e}. Run: adb forward tcp:{PORT} tcp:{PORT}"}
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"raw": body}


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
        return {"error": "device unreachable; an empty answer here is NOT a dead emulator"}
    ensure_forward()
    paused = hold(a, default=a.get("pause", True))
    return {
        "reachable": True,
        "paused": paused,
        "pid": pid() or None,
        "cpuJunctionC": temp_c(),
        "fixedSiliconC": fixed_silicon_c(),
        "battery": sh("cat /sys/class/power_supply/battery/capacity").strip(),
        "status": api("/status"),
        "device": api("/device"),
        "diag": api("/diag"),
    }


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
    sh(f"am force-stop {PKG}; rm -f {FILES}/cache/RPCSX.log")
    # A Thor with its screen off cannot boot a title: a SurfaceView measured 0x0
    # never creates a surface and the renderer waits forever.
    sh("input keyevent KEYCODE_WAKEUP; svc power stayon true")
    sh(f"am start -a net.rpcsx.THOR_DEBUG_BOOT -n {PKG}/net.rpcsx.MainActivity "
       f"--es path '{iso}' --es titleId {title} --es thorDebugBootRequestId mcp "
       f"--ez thorRequireManagedProfile false --ez thorReplaceCustomProfile false")
    ensure_forward()
    return {"booted": True, "titleId": title,
            "freshCompile": a.get("freshCompile", True),
            "startFixedSiliconC": t}


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
    was_paused = is_paused()
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

    if was_paused:
        api("/resume", "POST")
        time.sleep(0.3)

    r = api(f"/pad/press?buttons={a['buttons']}&ms={int(a.get('ms', 150))}", "POST")

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
    if was_paused and a.get("rePause", True):
        api("/pause", "POST")

    return {"press": r, "wasPaused": was_paused,
            "rePaused": was_paused and a.get("rePause", True),
            "maxFixedSiliconC": max_silicon}


def is_paused():
    r = api("/status")
    # EmulatorState: 0 Stopped 1 Loading 2 Stopping 3 Running 4 Paused
    return isinstance(r, dict) and r.get("state") == 4


def hold(a, default=True):
    """PAUSE BY DEFAULT for anything that inspects.

    If the emulator is not paused while a tool looks at it, the game runs on
    while the caller thinks, and the state reasoned about is already stale by
    the time a button is pressed. Pausing is not a convenience here, it is what
    makes an observation mean anything.

    Pass pause=false when you deliberately want a live reading.
    """
    if a.get("pause", default):
        api("/pause", "POST")
        return True
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
    if not is_paused():
        return {"refused": True,
                "reason": "the emulator must be paused before a bounded slice"}

    duration = max(0.1, min(float(a.get("seconds", 1.5)), 5.0))
    start_ceiling = float(a.get("maxStartC", 70))
    hard_limit = float(a.get("maxSiliconC", 72))
    start_silicon = fixed_silicon_c()
    if start_silicon < 0 or start_silicon >= start_ceiling:
        return {"refused": True, "fixedSiliconC": start_silicon,
                "reason": ("the fixed-silicon sensor domain is unavailable"
                           if start_silicon < 0 else
                           f"fixed silicon is not below {start_ceiling} C")}

    resume = api("/resume", "POST")
    started = time.monotonic()
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
            stop = t_stop({})
            return {"thermalStop": True, "elapsedS": round(elapsed, 3),
                    "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "resume": resume, "stop": stop}

    if not pid():
        return {"error": "process gone during the bounded slice",
                "elapsedS": round(elapsed, 3),
                "maxFixedSiliconC": max_silicon}

    pause = api("/pause", "POST")
    return {"completed": True, "elapsedS": round(elapsed, 3),
            "startFixedSiliconC": start_silicon,
            "endFixedSiliconC": silicon,
            "maxFixedSiliconC": max_silicon,
            "resume": resume, "pause": pause,
            "paused": is_paused(), "device": api("/device"),
            "diag": api("/diag")}


def t_wait_cool_paused(a):
    """Keep a paused guest still until fixed silicon is below the next ceiling."""
    if not pid():
        return {"error": "emulator is not running"}
    if not is_paused():
        return {"refused": True,
                "reason": "the emulator must stay paused while it cools"}

    target = float(a.get("targetC", 70))
    hard_limit = float(a.get("maxSiliconC", 72))
    limit = int(a.get("timeoutS", 120))
    waited = 0
    silicon = fixed_silicon_c()
    if silicon < 0 or silicon >= hard_limit:
        stop = t_stop({})
        return {"cooled": False, "thermalStop": True,
                "triggerFixedSiliconC": silicon,
                "maxSiliconC": hard_limit, "stop": stop}
    while silicon >= target and waited < limit:
        time.sleep(2)
        waited += 2
        silicon = fixed_silicon_c()
        if silicon < 0 or silicon >= hard_limit:
            stop = t_stop({})
            return {"cooled": False, "thermalStop": True,
                    "triggerFixedSiliconC": silicon,
                    "maxSiliconC": hard_limit, "stop": stop}

    return {"cooled": 0 <= silicon < target, "targetC": target,
            "fixedSiliconC": silicon, "waitedS": waited,
            "paused": is_paused()}


def t_screenshot(a):
    """Pause, capture, and STAY paused so the picture is still true when you act."""
    paused = hold(a)
    out = a.get("path") or os.path.join(os.getcwd(), "thor_shot.png")
    data = adb(["exec-out", "screencap", "-p"], binary=True)
    if len(data) < 1024:
        return {"error": f"screencap returned {len(data)} bytes"}
    with open(out, "wb") as f:
        f.write(data)
    return {"path": out, "bytes": len(data), "scene": api("/scene"),
            "paused": paused,
            "note": "still PAUSED; the picture stays true until you resume. "
                    "thor_press resumes for you and re-pauses after."}


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


def t_stop(_):
    """Stop, and KEEP stopping. One force-stop loses to the app's respawn: the
    device once climbed 56 -> 79 -> 95 C after a stop that reported success,
    with the app back at 542% CPU while pidof had read empty."""
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
    return {"pid": pid() or None, "rpcsxRowsInTop": busy,
            "quiet": (not pid()) and busy in ("0", ""),
            "note": "quiet means top agrees, not just pidof"}


TOOLS = [
    ("thor_state", "PAUSES BY DEFAULT, then reports device and emulator state at once: reachability, pid, temperature, battery, status, telemetry, compile progress, config in effect, SPURS state.", {"type": "object", "properties": {}}, t_state),
    ("thor_cooldown", "Force-stop the emulator, then wait for the CPU junction to fall below targetC. Stops first on purpose: cooling while the emulator runs never finishes.", {"type": "object", "properties": {"targetC": {"type": "integer"}, "timeoutS": {"type": "integer"}}}, t_cooldown),
    ("thor_boot", "Boot a title below the fixed-silicon start ceiling. freshCompile (default true) turns the SPU object cache OFF.", {"type": "object", "properties": {"titleId": {"type": "string"}, "isoPath": {"type": "string"}, "freshCompile": {"type": "boolean"}, "maxStartC": {"type": "number"}}, "required": ["titleId", "isoPath"]}, t_boot),
    ("thor_wait_ready", "Wait until the title renders. Poll fixed silicon every two seconds and stop at the hard limit.", {"type": "object", "properties": {"timeoutS": {"type": "integer"}, "minFps": {"type": "number"}, "maxSiliconC": {"type": "number"}}}, t_wait_ready),
    ("thor_press", "Press pad buttons. If paused, require a below-ceiling start, resume, monitor fixed silicon, and re-pause.", {"type": "object", "properties": {"buttons": {"type": "string"}, "ms": {"type": "integer"}, "settleS": {"type": "number"}, "maxStartC": {"type": "number"}, "maxSiliconC": {"type": "number"}}, "required": ["buttons"]}, t_press),
    ("thor_pause", "Pause emulation, so a screenshot and a decision do not race the scene. Pause, look, decide, resume, press.", {"type": "object", "properties": {}}, t_pause),
    ("thor_resume", "Resume emulation after thor_pause.", {"type": "object", "properties": {}}, t_resume),
    ("thor_slice", "Run a paused guest for 0.1 to 5 seconds, monitor fixed silicon every 0.25 seconds, and pause again.", {"type": "object", "properties": {"seconds": {"type": "number"}, "maxStartC": {"type": "number"}, "maxSiliconC": {"type": "number"}}}, t_slice),
    ("thor_wait_cool_paused", "Wait with the guest paused until fixed silicon is below targetC. Stop if it reaches the hard limit.", {"type": "object", "properties": {"targetC": {"type": "number"}, "maxSiliconC": {"type": "number"}, "timeoutS": {"type": "integer"}}}, t_wait_cool_paused),
    ("thor_screenshot", "PAUSES BY DEFAULT, captures a PNG, and STAYS PAUSED so the picture is still true when you act. pause=false for a live capture.", {"type": "object", "properties": {"path": {"type": "string"}}}, t_screenshot),
    ("thor_sample", "Measure process and per-thread CPU. Refuse invalid states and stop at the fixed-silicon hard limit.", {"type": "object", "properties": {"seconds": {"type": "integer"}, "threadMatch": {"type": "string"}, "maxSiliconC": {"type": "number"}}}, t_sample),
    ("thor_log", "Tail the emulator log, filtered. Read this for a fatal error BEFORE believing any measurement.", {"type": "object", "properties": {"match": {"type": "string"}, "n": {"type": "integer"}}}, t_log),
    ("thor_setprop", "Set a debug property and read it back, so an arm cannot silently run unset.", {"type": "object", "properties": {"name": {"type": "string"}, "value": {"type": "string"}}, "required": ["name"]}, t_setprop),
    ("thor_stop", "Force-stop the emulator, kill stressors, release the screen lock, and report the device is quiet.", {"type": "object", "properties": {}}, t_stop),
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
            if isinstance(out, dict):
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
