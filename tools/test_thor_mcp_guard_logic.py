#!/usr/bin/env python
"""Test the Thor MCP thermal state machine without a device."""

import importlib.util
import tempfile
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
        self.timers = []

    def sleep(self, seconds):
        target = self.now + seconds
        while True:
            due = [
                timer for timer in self.timers
                if timer.started and not timer.cancelled and not timer.fired
                and timer.deadline <= target
            ]
            if not due:
                break
            timer = min(due, key=lambda item: item.deadline)
            self.now = timer.deadline
            timer.fire()
        self.now = target

    def monotonic(self):
        return self.now


def use_temperatures(values):
    temperatures = iter(values)
    SERVER.fixed_silicon_c = lambda: next(temperatures)


def prepare_paused_guest():
    SERVER._process_hold_pid = None
    calls = []
    SERVER.pid = lambda: calls.append(("pid", None)) or "123"
    SERVER.emulation_state = lambda: 4
    SERVER.api = lambda path, method="GET", timeout=8: calls.append((path, method)) or {"ok": True}
    SERVER.t_stop = lambda _: {"quiet": True}
    return calls


clock = Clock()
SERVER.time.sleep = clock.sleep
SERVER.time.monotonic = clock.monotonic


class DeadlineTimer:
    """Run the timer callback when the controller waits for the deadline."""

    def __init__(self, interval, function):
        self.interval = interval
        self.function = function
        self.cancelled = False
        self.started = False
        self.fired = False
        self.deadline = 0.0
        self.daemon = False

    def start(self):
        self.started = True
        self.deadline = clock.now + self.interval
        clock.timers.append(self)

    def cancel(self):
        self.cancelled = True

    def join(self, timeout=None):
        if self.started and not self.cancelled and not self.fired:
            wait = max(0.0, self.deadline - clock.now)
            if timeout is None or wait <= timeout:
                clock.sleep(wait)

    def fire(self):
        if self.cancelled or self.fired:
            return
        self.fired = True
        self.function()


SERVER.threading.Timer = DeadlineTimer

SERVER.api = lambda path, method="GET", timeout=8: {"state": 6}
assert SERVER.is_paused() is True, "The start-paused Ready state is not held."

SERVER._process_hold_pid = None
SERVER.pid = lambda: "123"
SERVER._process_state = lambda process_id: "T"
assert SERVER.held_process_pid() == "123", (
    "The controller did not adopt an independent device-watchdog hold."
)
SERVER._process_hold_pid = None
SERVER._process_state = lambda process_id: "R"

original_sh = SERVER.sh
SERVER._process_hold_pid = "123"
SERVER.pid = lambda: "123"
process_states = iter(["T", "T"])
SERVER._process_state = lambda process_id: next(process_states)
SERVER.sh = lambda command, timeout=120: (
    "__THOR_CONTINUED__\n" if "kill -CONT" in command else ""
)
continue_result = SERVER.continue_process_for_slice("123")
assert continue_result["ok"] is True, (
    "A deadline hold raced with SIGCONT and was reported as a resume failure."
)
assert continue_result["deadlineHoldRaced"] is True, (
    "The process continue result lost the deadline-race evidence."
)
SERVER.sh = original_sh
SERVER._process_hold_pid = None
SERVER._process_state = lambda process_id: "R"

original_adb = SERVER.adb
original_hold = SERVER.hold
original_api = SERVER.api
with tempfile.TemporaryDirectory() as screenshot_dir:
    screenshot_calls = []
    SERVER._process_hold_pid = None
    SERVER.pid = lambda: "123"
    SERVER._process_state = lambda process_id: "T"
    SERVER.hold = lambda _: screenshot_calls.append("hold") or False
    SERVER.api = lambda path, method="GET", timeout=8: screenshot_calls.append(path) or {}
    SERVER.adb = lambda args, timeout=300, binary=False: b"x" * 2048
    screenshot_result = SERVER.t_screenshot({
        "path": str(Path(screenshot_dir) / "held.png"),
    })
    assert screenshot_result["holdMode"] == "process", (
        "A process-held screenshot lost its stable-state evidence."
    )
    assert screenshot_calls == [], (
        "A process-held screenshot called the stopped in-process API."
    )
SERVER.adb = original_adb
SERVER.hold = original_hold
SERVER.api = original_api
SERVER._process_hold_pid = None
SERVER._process_state = lambda process_id: "R"

calls = prepare_paused_guest()
use_temperatures([42.0, 45.0, 50.0, 55.0, 60.0])
result = SERVER.t_slice({"seconds": 1.0})
assert result["completed"] is True, "The safe slice did not complete."
assert result["requestedS"] == 1.0, "The safe slice lost its requested time."
assert result["pauseRequestedAtS"] == 1.0, "The deadline pause did not use the requested guest window."
assert result["paused"] is True, "The safe slice did not end paused."
assert result["maxFixedSiliconC"] == 60.0, "The safe slice lost its maximum temperature."
assert ("/resume", "POST") in calls and ("/pause", "POST") in calls, "The safe slice did not resume and pause."
assert calls.index(("/pause", "POST")) < len(calls) - 1 - calls[::-1].index(("pid", None)), (
    "The safe slice checked the pid before it paused."
)

clock.now = 0.0
calls = prepare_paused_guest()
slow_values = iter([42.0, 50.0])


def slow_temperature():
    value = next(slow_values)
    if value == 50.0:
        clock.sleep(2.0)
        calls.append(("slow-temperature-returned", None))
    return value


SERVER.fixed_silicon_c = slow_temperature
result = SERVER.t_slice({"seconds": 1.0, "includeState": False})
assert result["completed"] is True, "The telemetry-blocked slice did not complete."
assert result["elapsedS"] > 2.0, "The test did not model a slow telemetry read."
assert result["pauseRequestedAtS"] == 1.0, "Slow telemetry delayed the independent pause."
assert calls.index(("/pause", "POST")) < calls.index(("slow-temperature-returned", None)), (
    "The deadline pause waited for the slow telemetry read."
)

clock.now = 0.0
calls = prepare_paused_guest()
paused_states = iter([4, 3, 3, 4])
SERVER.emulation_state = lambda: next(paused_states)
use_temperatures([42.0, 45.0, 46.0, 47.0])
result = SERVER.t_slice({"seconds": 0.1, "includeState": False})
assert result["completed"] is True, "The raced pause did not recover."
assert calls.count(("/pause", "POST")) == 2, "The raced pause was not retried."
assert ("/device", "GET") not in calls, "The compact slice fetched device state."
assert ("/diag", "GET") not in calls, "The compact slice fetched diagnostics."

clock.now = 0.0
calls = prepare_paused_guest()
startup_states = iter([6, 7, 7, 4])
SERVER.emulation_state = lambda: next(startup_states)
use_temperatures([42.0, 55.0])
process_holds = []


def hold_startup_process(process_id):
    process_holds.append(process_id)
    SERVER._process_hold_pid = process_id
    return {"ok": True, "pid": process_id, "processState": "T"}


SERVER.stop_process_for_slice = hold_startup_process
result = SERVER.t_slice({
    "seconds": 0.1,
    "startupPauseTimeoutS": 20.0,
    "includeState": False,
})
assert result["completed"] is True, "The startup handoff did not reach its held state."
assert result["startupHandoff"] is True, "The Ready-to-starting handoff was not recorded."
assert result["initialState"] == 6 and result["finalState"] == 7, (
    "The startup handoff lost its state evidence."
)
assert result["holdMode"] == "process" and process_holds == ["123"], (
    "The startup handoff did not stop the process at its deadline."
)
assert calls.count(("/pause", "POST")) == 0, (
    "The startup deadline called the pause API before it stopped the process."
)
SERVER._process_hold_pid = None

clock.now = 0.0
calls = []
SERVER.pid = lambda: calls.append(("pid", None)) or "123"
SERVER.api = lambda path, method="GET", timeout=8: calls.append((path, method)) or {"ok": True}
SERVER.t_stop = lambda _: {"quiet": True}
SERVER._process_hold_pid = "123"
SERVER._process_state = lambda process_id: "T"
SERVER.emulation_state = lambda: 7
continued_processes = []


def continue_startup_process(process_id):
    continued_processes.append(process_id)
    SERVER._process_hold_pid = None
    return {"ok": True, "pid": process_id, "processState": "R"}


SERVER.continue_process_for_slice = continue_startup_process
use_temperatures([42.0, 45.0])
result = SERVER.t_slice({"seconds": 0.1, "includeState": False})
assert result["completed"] is True and result["holdMode"] == "process", (
    "A process-held startup slice did not stop again at its deadline."
)
assert result["initialState"] == 7 and continued_processes == ["123"], (
    "The process-held startup slice did not continue the recorded process."
)
assert ("/resume", "POST") in calls, (
    "The process-held slice did not advance a completed startup pause."
)
SERVER._process_hold_pid = None

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
use_temperatures([59.0, 61.0, 59.0, 58.0, 57.0])
result = SERVER.t_wait_cool_paused({
    "targetC": 60, "timeoutS": 10,
    "stableSamples": 3, "sampleIntervalS": 1,
})
assert result["cooled"] is True, "The stable cool wait did not complete."
assert result["waitedS"] == 4.0, (
    "A transient cool sample satisfied the stable resume gate."
)
assert result["stableSamples"] == 3, (
    "The stable resume gate lost its consecutive-sample evidence."
)

clock.now = 0.0
startup_process_state = {"value": "R"}
SERVER._process_hold_pid = None
SERVER.pid = lambda: "123"
SERVER._process_state = lambda process_id: startup_process_state["value"]
SERVER.emulation_state = lambda: SERVER.EMU_STATE_LOADING
SERVER.t_stop = lambda _: {"quiet": True}
result = SERVER.t_slice_loop({"seconds": 0.5, "maxSlices": 1})
assert result["refused"] is True, (
    "The slice loop accepted a loading process without explicit permission."
)
assert result["initialState"] == SERVER.EMU_STATE_LOADING, (
    "The startup refusal lost the exact emulator state."
)

startup_holds = []


def hold_initial_startup_process(process_id):
    startup_holds.append(process_id)
    startup_process_state["value"] = "T"
    SERVER._process_hold_pid = process_id
    return {"ok": True, "pid": process_id, "processState": "T"}


SERVER.stop_process_for_slice = hold_initial_startup_process
SERVER.t_wait_cool_paused = lambda _: {
    "cooled": True,
    "cooledAtFixedSiliconC": 45.0,
    "waitedS": 0,
    "paused": True,
}
SERVER.t_slice = lambda arguments: {
    "completed": True,
    "requestedS": arguments["seconds"],
    "elapsedS": arguments["seconds"],
    "pauseRequestedAtS": arguments["seconds"],
    "startFixedSiliconC": 45.0,
    "endFixedSiliconC": 50.0,
    "maxFixedSiliconC": 50.0,
    "paused": True,
    "holdMode": "process",
}
SERVER._matching_log_lines = lambda match, count=1: (
    ["startup marker"] if "shutdown completion event mask" in match else []
)
result = SERVER.t_slice_loop({
    "seconds": 0.5, "maxSlices": 1, "allowStarting": True,
})
assert result["markerReached"] is True, (
    "The explicitly allowed startup slice did not reach its marker."
)
assert startup_holds == ["123"], (
    "The startup slice loop did not hold the process before its first cooldown."
)
assert result["initialProcessHold"]["processState"] == "T", (
    "The startup slice loop lost its initial process-hold evidence."
)
SERVER._process_hold_pid = None
SERVER._process_state = lambda process_id: "R"

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
        "pauseRequestedAtS": arguments["seconds"],
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
assert all(item["pauseRequestedAtS"] == 1.0 for item in result["slices"]), (
    "The slice loop lost the deadline-pause timing evidence."
)
assert result["maxFixedSiliconC"] == 69.9, "The slice loop lost its maximum temperature."
assert all(item["includeState"] is False for item in loop_slices), "The slice loop used full slice state."
assert all(item["startupPauseTimeoutS"] <= 120 for item in loop_slices), (
    "The slice loop lost its bounded startup handoff."
)
assert [item["targetC"] for item in loop_cool_requests] == [70, 70], (
    "The default slice loop changed its 70 C resume target."
)

loop_slices.clear()
loop_cool_requests.clear()
SERVER._matching_log_lines = lambda match, count=1: (
    ["marker"] if "shutdown completion event mask" in match and len(loop_slices) == 3
    else []
)
result = SERVER.t_slice_loop({
    "seconds": 1.0, "maxSlices": 4, "resumeTargetC": 60,
    "resumeStableSamples": 3, "resumeSampleIntervalS": 1,
})
assert result["markerReached"] is True, "The cooled slice loop missed the marker."
assert [item["targetC"] for item in loop_cool_requests] == [70, 60, 60], (
    "The slice loop did not keep 70 C for launch and 60 C for later resumes."
)
assert [item["stableSamples"] for item in loop_cool_requests] == [1, 3, 3], (
    "The slice loop did not keep the cold start immediate and stabilize later resumes."
)
assert all(item["sampleIntervalS"] == 1 for item in loop_cool_requests), (
    "The slice loop did not pass the requested stable-sample interval."
)

stops = []
loop_slices.clear()
SERVER._matching_log_lines = lambda match, count=1: (
    ["out-of-memory failure"] if match == "Out of memory" else []
)
SERVER.t_stop = lambda _: stops.append(True) or {"quiet": True}
result = SERVER.t_slice_loop({"seconds": 0.5, "maxSlices": 2})
assert result["fatal"] == "Out of memory", "The slice loop missed an out-of-memory log."
assert stops == [True], "The slice loop did not use the verified fatal stop."

property_rows = [
    "[debug.rpcsx.thor.alpha]: [on]",
    "[debug.rpcsx.thor.empty]: []",
    "[debug.other.value]: [keep]",
    "[debug.rpcsx.thor.beta]: [7]",
]
cleared_properties = []


def property_shell(command, timeout=120):
    if command == "getprop":
        return "\n".join(
            row for row in property_rows
            if not any(row.startswith(f"[{name}]") for name in cleared_properties)
        )
    match = __import__("re").match(r"setprop (debug\.rpcsx\.thor\.[A-Za-z0-9_.-]+) ''$", command)
    assert match, f"Property cleanup used an unsafe command: {command}"
    cleared_properties.append(match.group(1))
    return ""


SERVER.sh = property_shell
SERVER.pid = lambda: None
result = SERVER.t_clearprops({})
assert result["beforeCount"] == 2, "Property cleanup included empty or unrelated values."
assert result["clearedCount"] == 2 and result["remainingCount"] == 0, (
    "Property cleanup did not clear and audit the Thor property namespace."
)
SERVER.pid = lambda: "123"
result = SERVER.t_clearprops({})
assert result["refused"] is True, "Property cleanup changed a running experiment."

clock.now = 0.0
prepare_paused_guest()
SERVER._matching_log_lines = lambda match, count=1: []
SERVER.t_wait_cool_paused = lambda _: {
    "cooled": True,
    "cooledAtFixedSiliconC": 69.9,
    "waitedS": 0,
    "paused": True,
}


def deadline_slice(arguments):
    clock.sleep(8.0)
    return {
        "completed": True,
        "requestedS": arguments["seconds"],
        "elapsedS": arguments["seconds"],
        "pauseRequestedAtS": arguments["seconds"],
        "startFixedSiliconC": 69.9,
        "endFixedSiliconC": 69.9,
        "maxFixedSiliconC": 69.9,
        "paused": True,
    }


SERVER.t_slice = deadline_slice
result = SERVER.t_slice_loop({"seconds": 0.5, "maxSlices": 10, "maxHostS": 30})
assert result["hostDeadlineReached"] is True, "The slice loop overran its host deadline."
assert result["completedSlices"] == 4, "The host deadline lost completed slice records."
assert result["hostElapsedS"] == 32.0, "The host deadline reported the wrong elapsed time."

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
