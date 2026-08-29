#!/usr/bin/env python
"""Test the Thor MCP thermal state machine without a device."""

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "thor_mcp_server", ROOT / "tools" / "thor_mcp" / "server.py"
)
SERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVER)


class Clock:
    def __init__(self):
        self.now = 0.0

    def sleep(self, seconds):
        self.now += seconds

    def monotonic(self):
        return self.now


def use_temperatures(values):
    temperatures = iter(values)
    SERVER.fixed_silicon_c = lambda: next(temperatures)


def prepare_paused_guest():
    calls = []
    SERVER.pid = lambda: calls.append(("pid", None)) or "123"
    SERVER.is_paused = lambda: True
    SERVER.api = lambda path, method="GET", timeout=8: calls.append((path, method)) or {"ok": True}
    SERVER.t_stop = lambda _: {"quiet": True}
    return calls


clock = Clock()
SERVER.time.sleep = clock.sleep
SERVER.time.monotonic = clock.monotonic

SERVER.api = lambda path, method="GET", timeout=8: {"state": 6}
assert SERVER.is_paused() is True, "The start-paused Ready state is not held."

calls = prepare_paused_guest()
use_temperatures([42.0, 45.0, 50.0, 55.0, 60.0])
result = SERVER.t_slice({"seconds": 1.0})
assert result["completed"] is True, "The safe slice did not complete."
assert result["requestedS"] == 1.0, "The safe slice lost its requested time."
assert result["paused"] is True, "The safe slice did not end paused."
assert result["maxFixedSiliconC"] == 60.0, "The safe slice lost its maximum temperature."
assert ("/resume", "POST") in calls and ("/pause", "POST") in calls, "The safe slice did not resume and pause."
assert calls.index(("/pause", "POST")) < len(calls) - 1 - calls[::-1].index(("pid", None)), (
    "The safe slice checked the pid before it paused."
)

clock.now = 0.0
calls = prepare_paused_guest()
paused_states = iter([True, False, True])
SERVER.is_paused = lambda: next(paused_states)
use_temperatures([42.0, 45.0, 46.0])
result = SERVER.t_slice({"seconds": 0.1, "includeState": False})
assert result["completed"] is True, "The raced pause did not recover."
assert calls.count(("/pause", "POST")) == 2, "The raced pause was not retried."
assert ("/device", "GET") not in calls, "The compact slice fetched device state."
assert ("/diag", "GET") not in calls, "The compact slice fetched diagnostics."

clock.now = 0.0
prepare_paused_guest()
use_temperatures([42.0, 73.0])
result = SERVER.t_slice({"seconds": 1.0})
assert result["thermalStop"] is True, "The hot slice did not stop."
assert result["triggerFixedSiliconC"] == 73.0, "The hot slice lost its trigger temperature."
assert result["stop"]["quiet"] is True, "The hot slice did not use the verified stop path."

clock.now = 0.0
prepare_paused_guest()
use_temperatures([71.0, 69.0])
result = SERVER.t_wait_cool_paused({"targetC": 70, "timeoutS": 10})
assert result["cooled"] is True, "The paused cool wait did not cross below 70 C."
assert result["fixedSiliconC"] == 69.0, "The paused cool wait reported the wrong temperature."
assert result["cooledAtFixedSiliconC"] == 69.0, "The cool wait lost its decisive sample."

clock.now = 0.0
prepare_paused_guest()
loop_slices = []
loop_cool_requests = []
SERVER.t_wait_cool_paused = lambda arguments: (
    loop_cool_requests.append(arguments)
    or {
        "cooled": True,
        "cooledAtFixedSiliconC": 69.9,
        "waitedS": 0,
        "paused": True,
    }
)


def loop_slice(arguments):
    loop_slices.append(arguments)
    return {
        "completed": True,
        "requestedS": arguments["seconds"],
        "elapsedS": arguments["seconds"],
        "startFixedSiliconC": 45.0,
        "endFixedSiliconC": 50.0,
        "maxFixedSiliconC": 52.0,
        "paused": True,
    }


SERVER.t_slice = loop_slice
SERVER._matching_log_lines = lambda match, count=1: (
    ["shutdown marker"]
    if "shutdown completion event mask" in match and len(loop_slices) == 2
    else []
)
SERVER.api = lambda path, method="GET", timeout=8: {"ok": True}
result = SERVER.t_slice_loop({"seconds": 1.0, "maxSlices": 4})
assert result["markerReached"] is True, "The slice loop did not find the marker."
assert result["completedSlices"] == 2, "The slice loop ran past the marker."
assert result["maxFixedSiliconC"] == 69.9, "The slice loop lost its maximum temperature."
assert all(item["includeState"] is False for item in loop_slices), "The slice loop used full slice state."
assert all(item["targetC"] == 70 for item in loop_cool_requests), (
    "The slice loop imposed a cooldown target below the 70 C start ceiling."
)

stops = []
loop_slices.clear()
SERVER._matching_log_lines = lambda match, count=1: (
    ["verification failure"] if match == "Verification failed" else []
)
SERVER.t_stop = lambda _: stops.append(True) or {"quiet": True}
result = SERVER.t_slice_loop({"seconds": 0.5, "maxSlices": 2})
assert result["fatal"] == "Verification failed", "The slice loop missed a fatal log."
assert stops == [True], "The slice loop did not use the verified fatal stop."

clock.now = 0.0
calls = prepare_paused_guest()
use_temperatures([42.0, 45.0, 50.0])
result = SERVER.t_press({"buttons": "START", "settleS": 0.5})
assert result["rePaused"] is True, "The guarded press did not restore the paused state."
assert ("/pad/press?buttons=START&ms=150", "POST") in calls, "The guarded press did not send the input."

clock.now = 0.0
prepare_paused_guest()
use_temperatures([73.0])
result = SERVER.t_press({"buttons": "START"})
assert result["thermalStop"] is True, "The guarded press did not stop at the hard limit."

print("Thor MCP guarded slice logic passed.")
