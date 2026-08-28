#!/usr/bin/env python3
"""Compare bounded Transformers HLE and LLE main-thread call traces."""

from __future__ import annotations

import argparse
import difflib
import re
from dataclasses import dataclass
from pathlib import Path


BEGIN_RE = re.compile(
    r"Thor PPU CALL TRACE BEGIN: mode=(\S+) count=(\d+) index=(\d+) cia=0x([0-9a-fA-F]+)"
)
CALL_RE = re.compile(
    r"Thor PPU CALL TRACE: seq=(\d+) cia=0x([0-9a-fA-F]+) func=(\S+) "
    r"rc=0x([0-9a-fA-F]+) r3=0x([0-9a-fA-F]+) r4=0x([0-9a-fA-F]+) "
    r"r5=0x([0-9a-fA-F]+) r6=0x([0-9a-fA-F]+)"
)
END_RE = re.compile(r"Thor PPU CALL TRACE END")
STACK_BEGIN_RE = re.compile(
    r"Thor PPU CALL TRACE STACK BEGIN: mode=(\S+) count=(\d+)"
)
STACK_ROW_RE = re.compile(
    r"Thor PPU CALL TRACE STACK: frame=(\d+) from=0x([0-9a-fA-F]+) "
    r"sp=0x([0-9a-fA-F]+)"
)
STACK_END_RE = re.compile(r"Thor PPU CALL TRACE STACK END")


@dataclass(frozen=True)
class Call:
    seq: int
    cia: int
    function: str
    result: int
    args: tuple[int, int, int, int]


@dataclass(frozen=True)
class StackFrame:
    index: int
    caller: int
    stack_pointer: int


@dataclass(frozen=True)
class Trace:
    mode: str
    retained_count: int
    total_index: int
    cia: int
    calls: tuple[Call, ...]
    stack: tuple[StackFrame, ...] | None


def parse_trace(text: str, source: str) -> Trace:
    begin = None
    ended = False
    calls: list[Call] = []
    stack_begin = None
    stack_ended = False
    stack: list[StackFrame] = []

    for line in text.splitlines():
        if match := STACK_BEGIN_RE.search(line):
            if stack_begin is not None:
                raise ValueError(f"{source}: more than one stack begins")
            stack_begin = match
            continue

        if STACK_END_RE.search(line):
            if stack_begin is None:
                raise ValueError(f"{source}: stack end marker precedes the begin marker")
            if stack_ended:
                raise ValueError(f"{source}: more than one stack ends")
            stack_ended = True
            continue

        if match := STACK_ROW_RE.search(line):
            if stack_begin is None or stack_ended:
                raise ValueError(f"{source}: stack row is outside the stack markers")
            stack.append(
                StackFrame(
                    index=int(match.group(1)),
                    caller=int(match.group(2), 16),
                    stack_pointer=int(match.group(3), 16),
                )
            )
            continue

        if match := BEGIN_RE.search(line):
            if begin is not None:
                raise ValueError(f"{source}: more than one trace begins")
            begin = match
            continue

        if END_RE.search(line):
            if begin is None:
                raise ValueError(f"{source}: trace end marker precedes the begin marker")
            if ended:
                raise ValueError(f"{source}: more than one trace ends")
            ended = True
            continue

        if match := CALL_RE.search(line):
            if begin is None or ended:
                raise ValueError(f"{source}: call row is outside the trace markers")
            calls.append(
                Call(
                    seq=int(match.group(1)),
                    cia=int(match.group(2), 16),
                    function=match.group(3),
                    result=int(match.group(4), 16),
                    args=tuple(int(match.group(i), 16) for i in range(5, 9)),
                )
            )

    if begin is None:
        raise ValueError(f"{source}: trace begin marker is missing")
    if not ended:
        raise ValueError(f"{source}: trace end marker is missing")

    if stack_begin is not None:
        if not stack_ended:
            raise ValueError(f"{source}: stack end marker is missing")
        declared_stack_count = int(stack_begin.group(2))
        if declared_stack_count != len(stack):
            raise ValueError(
                f"{source}: stack marker says {declared_stack_count} frames, "
                f"but {len(stack)} rows were parsed"
            )
        if any(frame.index != expected for expected, frame in enumerate(stack)):
            raise ValueError(f"{source}: stack frame numbers are not contiguous")
        if stack_begin.group(1) != begin.group(1):
            raise ValueError(
                f"{source}: stack mode {stack_begin.group(1)} does not match "
                f"trace mode {begin.group(1)}"
            )

    trace = Trace(
        mode=begin.group(1),
        retained_count=int(begin.group(2)),
        total_index=int(begin.group(3)),
        cia=int(begin.group(4), 16),
        calls=tuple(calls),
        stack=tuple(stack) if stack_begin is not None else None,
    )

    if trace.retained_count != len(trace.calls):
        raise ValueError(
            f"{source}: begin marker says {trace.retained_count} calls, "
            f"but {len(trace.calls)} rows were parsed"
        )

    if trace.total_index < trace.retained_count:
        raise ValueError(f"{source}: total index is smaller than the retained count")

    expected_first = trace.total_index - trace.retained_count
    expected_sequences = range(expected_first, trace.total_index)
    if any(call.seq != expected for call, expected in zip(trace.calls, expected_sequences)):
        raise ValueError(
            f"{source}: sequence numbers do not cover "
            f"[{expected_first}, {trace.total_index})"
        )

    if any(right.seq != left.seq + 1 for left, right in zip(trace.calls, trace.calls[1:])):
        raise ValueError(f"{source}: sequence numbers are not contiguous")

    return trace


def format_call(call: Call) -> str:
    args = ",".join(f"0x{value:x}" for value in call.args)
    return (
        f"seq={call.seq} cia=0x{call.cia:08x} {call.function} "
        f"rc=0x{call.result:x} args=[{args}]"
    )


def select_anchor(
    hle: Trace,
    lle: Trace,
    key,
    useful_size: int,
) -> difflib.Match | None:
    matcher = difflib.SequenceMatcher(
        None,
        [key(call) for call in hle.calls],
        [key(call) for call in lle.calls],
        autojunk=False,
    )
    blocks = [block for block in matcher.get_matching_blocks() if block.size]
    useful = [block for block in blocks if block.size >= useful_size]
    candidates = useful or blocks

    if not candidates:
        return None

    return max(
        candidates,
        key=lambda block: (
            min(block.a + block.size, block.b + block.size),
            block.a + block.b + (2 * block.size),
            block.size,
        ),
    )


def describe_anchor(
    label: str,
    hle: Trace,
    lle: Trace,
    anchor: difflib.Match | None,
) -> str:
    if anchor is None:
        return f"Latest shared {label} block: <none>"

    changed_rows = 0
    for offset in range(anchor.size):
        left = hle.calls[anchor.a + offset]
        right = lle.calls[anchor.b + offset]
        if (left.cia, left.result, left.args) != (right.cia, right.result, right.args):
            changed_rows += 1

    return (
        f"Latest shared {label} block: length={anchor.size} "
        f"HLE[{anchor.a}:{anchor.a + anchor.size}] "
        f"LLE[{anchor.b}:{anchor.b + anchor.size}] "
        f"changed_rows={changed_rows}"
    )


def describe_stack(hle: Trace, lle: Trace) -> list[str]:
    if hle.stack is None or lle.stack is None:
        missing = []
        if hle.stack is None:
            missing.append("HLE")
        if lle.stack is None:
            missing.append("LLE")
        return [f"Guest stack comparison: unavailable ({' and '.join(missing)} stack missing)"]

    shared = 0
    for left, right in zip(hle.stack, lle.stack):
        if left.caller != right.caller:
            break
        shared += 1

    lines = [
        f"Guest stacks: HLE={len(hle.stack)} LLE={len(lle.stack)} "
        f"shared_prefix={shared}"
    ]
    for index in range(max(len(hle.stack), len(lle.stack))):
        left = hle.stack[index] if index < len(hle.stack) else None
        right = lle.stack[index] if index < len(lle.stack) else None
        left_text = "<none>" if left is None else f"0x{left.caller:08x} sp=0x{left.stack_pointer:x}"
        right_text = "<none>" if right is None else f"0x{right.caller:08x} sp=0x{right.stack_pointer:x}"
        marker = "=" if left is not None and right is not None and left.caller == right.caller else "!"
        lines.append(f"  frame={index} HLE={left_text} {marker} LLE={right_text}")
    return lines


def compare(hle: Trace, lle: Trace, context: int) -> str:
    valid_pairs = {
        ("HLE_FLIP", "LLE_FLIP"),
        ("HLE_STALL", "LLE_VOICE"),
        ("HLE_NET", "LLE_NET"),
        ("HLE_WAIT", "LLE_WAIT"),
    }
    if (hle.mode, lle.mode) not in valid_pairs:
        raise ValueError(
            f"trace modes are {hle.mode} and {lle.mode}; expected "
            "HLE_FLIP/LLE_FLIP, HLE_STALL/LLE_VOICE, HLE_NET/LLE_NET, "
            "or HLE_WAIT/LLE_WAIT"
        )

    function_anchor = select_anchor(
        hle, lle, lambda call: call.function, useful_size=4
    )
    site_anchor = select_anchor(
        hle, lle, lambda call: (call.function, call.cia), useful_size=4
    )
    exact_anchor = select_anchor(
        hle,
        lle,
        lambda call: (call.function, call.cia, call.result, call.args),
        useful_size=2,
    )

    anchor = exact_anchor or site_anchor or function_anchor
    if anchor is None:
        return "No common call was found.\n"

    hle_after = anchor.a + anchor.size
    lle_after = anchor.b + anchor.size
    last_hle = hle.calls[hle_after - 1]
    last_lle = lle.calls[lle_after - 1]

    lines = [
        f"HLE: retained={len(hle.calls)} total_index={hle.total_index} cia=0x{hle.cia:08x}",
        f"LLE: retained={len(lle.calls)} total_index={lle.total_index} cia=0x{lle.cia:08x}",
        *describe_stack(hle, lle),
        describe_anchor("function-name", hle, lle, function_anchor),
        describe_anchor("call-site", hle, lle, site_anchor),
        describe_anchor("exact-call", hle, lle, exact_anchor),
        "Context uses the exact-call block, then the call-site block, when available.",
        "Last aligned HLE call: " + format_call(last_hle),
        "Last aligned LLE call: " + format_call(last_lle),
        "HLE calls after the context block:",
    ]

    for call in hle.calls[hle_after : hle_after + context]:
        lines.append("  " + format_call(call))
    if hle_after == len(hle.calls):
        lines.append("  <none>")

    lines.append("LLE calls after the context block:")
    for call in lle.calls[lle_after : lle_after + context]:
        lines.append("  " + format_call(call))
    if lle_after == len(lle.calls):
        lines.append("  <none>")

    return "\n".join(lines) + "\n"


def self_test() -> None:
    def make(
        mode: str,
        names: list[str],
        cia_bias: int = 0,
        stack_callers: list[int] | None = None,
    ) -> str:
        lines = []
        if stack_callers is not None:
            lines.append(
                f"Thor PPU CALL TRACE STACK BEGIN: mode={mode} count={len(stack_callers)}"
            )
            for index, caller in enumerate(stack_callers):
                lines.append(
                    f"Thor PPU CALL TRACE STACK: frame={index} "
                    f"from=0x{caller:08x} sp=0x{0x1000 + (index * 0x80):x}"
                )
            lines.append("Thor PPU CALL TRACE STACK END")
        lines.append(
            f"Thor PPU CALL TRACE BEGIN: mode={mode} count={len(names)} index={len(names)} cia=0x1"
        )
        for seq, name in enumerate(names):
            lines.append(
                f"Thor PPU CALL TRACE: seq={seq} cia=0x{cia_bias + seq + 1:08x} func={name} "
                "rc=0x0 r3=0x1 r4=0x2 r5=0x3 r6=0x4"
            )
        lines.append("Thor PPU CALL TRACE END")
        return "\n".join(lines)

    hle = parse_trace(make("HLE_FLIP", ["a", "b", "c", "d", "e", "h"]), "self-hle")
    lle = parse_trace(make("LLE_FLIP", ["a", "b", "c", "d", "e", "l"]), "self-lle")
    report = compare(hle, lle, 2)
    assert "Latest shared exact-call block: length=5" in report
    assert "Last aligned HLE call: seq=4 cia=0x00000005 e " in report
    assert "HLE calls after the context block:\n  seq=5 cia=0x00000006 h " in report
    assert "LLE calls after the context block:\n  seq=5 cia=0x00000006 l " in report
    assert "Guest stack comparison: unavailable (HLE and LLE stack missing)" in report

    hle_stack = parse_trace(
        make("HLE_WAIT", ["a"], stack_callers=[0x10, 0x20, 0x30]),
        "self-hle-stack",
    )
    lle_stack = parse_trace(
        make("LLE_WAIT", ["a"], stack_callers=[0x10, 0x20, 0x40]),
        "self-lle-stack",
    )
    stack_report = compare(hle_stack, lle_stack, 1)
    assert "Guest stacks: HLE=3 LLE=3 shared_prefix=2" in stack_report
    assert "frame=1 HLE=0x00000020 sp=0x1080 = LLE=0x00000020" in stack_report
    assert "frame=2 HLE=0x00000030 sp=0x1100 ! LLE=0x00000040" in stack_report

    shifted = parse_trace(
        make("LLE_FLIP", ["a", "b", "c", "d", "e", "l"], cia_bias=0x100),
        "self-shifted",
    )
    shifted_report = compare(hle, shifted, 2)
    assert "Latest shared function-name block: length=5" in shifted_report
    assert "Latest shared call-site block: <none>" in shifted_report
    assert "Latest shared exact-call block: <none>" in shifted_report

    hle_boundary = parse_trace(
        make("HLE_STALL", ["a", "b", "c", "d"]), "self-hle-boundary"
    )
    lle_boundary = parse_trace(
        make("LLE_VOICE", ["a", "b", "c", "d"]), "self-lle-boundary"
    )
    assert "Latest shared exact-call block: length=4" in compare(
        hle_boundary, lle_boundary, 2
    )

    hle_net = parse_trace(make("HLE_NET", ["a", "b", "c", "d"]), "self-hle-net")
    lle_net = parse_trace(make("LLE_NET", ["a", "b", "c", "d"]), "self-lle-net")
    assert "Latest shared exact-call block: length=4" in compare(hle_net, lle_net, 2)

    hle_wait = parse_trace(
        make("HLE_WAIT", ["a", "b", "c", "d"]), "self-hle-wait"
    )
    lle_wait = parse_trace(
        make("LLE_WAIT", ["a", "b", "c", "d"]), "self-lle-wait"
    )
    assert "Latest shared exact-call block: length=4" in compare(
        hle_wait, lle_wait, 2
    )

    try:
        parse_trace(make("HLE_FLIP", ["a"]).replace("\nThor PPU CALL TRACE END", ""), "cut")
    except ValueError as error:
        assert "end marker is missing" in str(error)
    else:
        raise AssertionError("a trace without its end marker was accepted")

    try:
        parse_trace(make("HLE_FLIP", ["a"]).replace("index=1", "index=2"), "gap")
    except ValueError as error:
        assert "sequence numbers do not cover [1, 2)" in str(error)
    else:
        raise AssertionError("a trace with the wrong sequence range was accepted")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hle_log", nargs="?", type=Path)
    parser.add_argument("lle_log", nargs="?", type=Path)
    parser.add_argument("--context", type=int, default=12)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        print("PPU call trace comparator self-test passed.")
        return 0

    if args.hle_log is None or args.lle_log is None:
        parser.error("hle_log and lle_log are required unless --self-test is used")
    if args.context < 1:
        parser.error("--context must be positive")

    hle = parse_trace(args.hle_log.read_text(encoding="utf-8", errors="replace"), str(args.hle_log))
    lle = parse_trace(args.lle_log.read_text(encoding="utf-8", errors="replace"), str(args.lle_log))
    print(compare(hle, lle, args.context), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
