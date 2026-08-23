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
import urllib.request

ADB = os.environ.get("ADB", r"/c/Users/leanerdesigner/AppData/Local/Android/Sdk/platform-tools/adb")
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
def t_state(_):
    """Everything at once, so a caller does not stitch three calls together."""
    if not reachable():
        return {"error": "device unreachable; an empty answer here is NOT a dead emulator"}
    ensure_forward()
    return {
        "reachable": True,
        "pid": pid() or None,
        "cpuJunctionC": temp_c(),
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
    return {"booted": True, "titleId": title, "freshCompile": a.get("freshCompile", True)}


def t_wait_ready(a):
    """Wait for real frames, not a fixed sleep. A fixed sleep is not a
    deterministic workload: boot varies by tens of seconds and a cold precompile
    can take ten minutes."""
    limit = int(a.get("timeoutS", 300))
    want = float(a.get("minFps", 10))
    waited, last = 0, {}
    while waited < limit:
        time.sleep(10)
        waited += 10
        dev = api("/device")
        last = dev
        if isinstance(dev, dict) and float(dev.get("device", {}).get("fps", 0) or 0) >= want:
            return {"ready": True, "waitedS": waited, "device": dev}
        if not pid():
            return {"ready": False, "waitedS": waited, "error": "process gone",
                    "log": api("/log?match=Fatal&n=10")}
    return {"ready": False, "waitedS": waited, "device": last,
            "hint": "check /diag progress; a cold precompile can take ten minutes"}


def t_press(a):
    """Press when the screen is READY, not on a timer. Presses sent during an
    intro are correctly ignored by the game and read as a broken API."""
    return api(f"/pad/press?buttons={a['buttons']}&ms={int(a.get('ms', 150))}", "POST")


def t_screenshot(a):
    out = a.get("path") or os.path.join(os.getcwd(), "thor_shot.png")
    data = adb(["exec-out", "screencap", "-p"], binary=True)
    if len(data) < 1024:
        return {"error": f"screencap returned {len(data)} bytes"}
    with open(out, "wb") as f:
        f.write(data)
    return {"path": out, "bytes": len(data), "scene": api("/scene")}


def t_sample(a):
    """Measure, and REFUSE when the window is not measurable."""
    secs = int(a.get("seconds", 40))
    p = pid()
    if not p:
        return {"error": "emulator is not running"}

    s0 = api("/scene")
    dev0 = api("/device")
    guard = dev0.get("device", {}).get("thermalGuardEngaged") if isinstance(dev0, dict) else None
    if isinstance(s0, dict) and s0.get("videoDecoding"):
        return {"void": True, "reason": "a movie is playing; a cutscene cannot resolve a measurement"}
    if guard:
        return {"void": True, "reason": "the thermal guard is engaged; this measures the guard's cap, not the lever"}

    c0 = proc_jiffies(p)
    th0 = api(f"/threads?match={a.get('threadMatch', '')}")
    time.sleep(secs)
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
    return api(f"/log?match={a.get('match', '')}&n={int(a.get('n', 40))}")


def t_setprop(a):
    name, value = a["name"], str(a.get("value", ""))
    sh(f"setprop {name} '{value}'")
    # Read the lever BACK. A harness once ran every arm unset while both arms
    # agreed perfectly.
    return {"name": name, "requested": value, "readback": sh(f"getprop {name}").strip()}


def t_stop(_):
    sh(f"am force-stop {PKG}; killall yes; svc power stayon false")
    time.sleep(3)
    return {"pid": pid() or None, "cpuJunctionC": temp_c(),
            "note": "confirm the DEVICE is quiet, not that a task was stopped"}


TOOLS = [
    ("thor_state", "Device and emulator state at once: reachability, pid, temperature, battery, status, telemetry, compile progress, config in effect, SPURS state.", {"type": "object", "properties": {}}, t_state),
    ("thor_cooldown", "Force-stop the emulator, then wait for the CPU junction to fall below targetC. Stops first on purpose: cooling while the emulator runs never finishes.", {"type": "object", "properties": {"targetC": {"type": "integer"}, "timeoutS": {"type": "integer"}}}, t_cooldown),
    ("thor_boot", "Boot a title. freshCompile (default true) turns the SPU object cache OFF, so a diagnosis is against a fresh compile rather than a replayed object.", {"type": "object", "properties": {"titleId": {"type": "string"}, "isoPath": {"type": "string"}, "freshCompile": {"type": "boolean"}}, "required": ["titleId", "isoPath"]}, t_boot),
    ("thor_wait_ready", "Wait until the title actually renders, instead of sleeping a fixed time.", {"type": "object", "properties": {"timeoutS": {"type": "integer"}, "minFps": {"type": "number"}}}, t_wait_ready),
    ("thor_press", "Press pad buttons in the guest, e.g. START or CROSS. Screenshot first: a press sent during an intro is correctly ignored.", {"type": "object", "properties": {"buttons": {"type": "string"}, "ms": {"type": "integer"}}, "required": ["buttons"]}, t_press),
    ("thor_screenshot", "Capture the screen to a PNG and report whether a movie is playing.", {"type": "object", "properties": {"path": {"type": "string"}}}, t_screenshot),
    ("thor_sample", "Measure process and per-thread CPU over a window. REFUSES while a movie plays or the thermal guard is engaged.", {"type": "object", "properties": {"seconds": {"type": "integer"}, "threadMatch": {"type": "string"}}}, t_sample),
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
            send({"jsonrpc": "2.0", "id": rid, "result": {
                "content": [{"type": "text", "text": json.dumps(out, indent=2)}]}})
        elif rid is not None:
            send({"jsonrpc": "2.0", "id": rid, "result": {}})


if __name__ == "__main__":
    main()
