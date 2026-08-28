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


@dataclass(frozen=True)
class Call:
    seq: int
    cia: int
    function: str
    result: int
    args: tuple[int, int, int, int]


@dataclass(frozen=True)
class Trace:
    mode: str
    retained_count: int
    total_index: int
    cia: int
    calls: tuple[Call, ...]


def parse_trace(text: str, source: str) -> Trace:
    begin = None
    ended = False
    calls: list[Call] = []

    for line in text.splitlines():
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

    trace = Trace(
        mode=begin.group(1),
        retained_count=int(begin.group(2)),
        total_index=int(begin.group(3)),
        cia=int(begin.group(4), 16),
        calls=tuple(calls),
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


def compare(hle: Trace, lle: Trace, context: int) -> str:
    valid_pairs = {("HLE_FLIP", "LLE_FLIP"), ("HLE_STALL", "LLE_VOICE")}
    if (hle.mode, lle.mode) not in valid_pairs:
        raise ValueError(
            f"trace modes are {hle.mode} and {lle.mode}; expected "
            "HLE_FLIP/LLE_FLIP or HLE_STALL/LLE_VOICE"
        )

    matcher = difflib.SequenceMatcher(
        None,
        [call.function for call in hle.calls],
        [call.function for call in lle.calls],
        autojunk=False,
    )
    blocks = [block for block in matcher.get_matching_blocks() if block.size]
    useful = [block for block in blocks if block.size >= 4]
    candidates = useful or blocks

    if not candidates:
        return "No common function-call block was found.\n"

    anchor = max(candidates, key=lambda block: (block.a + block.size, block.size))
    hle_after = anchor.a + anchor.size
    lle_after = anchor.b + anchor.size
    last_hle = hle.calls[hle_after - 1]
    last_lle = lle.calls[lle_after - 1]

    changed_rows = 0
    for offset in range(anchor.size):
        left = hle.calls[anchor.a + offset]
        right = lle.calls[anchor.b + offset]
        if (left.cia, left.result, left.args) != (right.cia, right.result, right.args):
            changed_rows += 1

    lines = [
        f"HLE: retained={len(hle.calls)} total_index={hle.total_index} cia=0x{hle.cia:08x}",
        f"LLE: retained={len(lle.calls)} total_index={lle.total_index} cia=0x{lle.cia:08x}",
        (
            f"Latest shared function block: length={anchor.size} "
            f"HLE[{anchor.a}:{hle_after}] LLE[{anchor.b}:{lle_after}]"
        ),
        f"Rows with changed address, result, or arguments inside that block: {changed_rows}",
        "Last aligned HLE call: " + format_call(last_hle),
        "Last aligned LLE call: " + format_call(last_lle),
        "HLE calls after the shared block:",
    ]

    for call in hle.calls[hle_after : hle_after + context]:
        lines.append("  " + format_call(call))
    if hle_after == len(hle.calls):
        lines.append("  <none>")

    lines.append("LLE calls after the shared block:")
    for call in lle.calls[lle_after : lle_after + context]:
        lines.append("  " + format_call(call))
    if lle_after == len(lle.calls):
        lines.append("  <none>")

    return "\n".join(lines) + "\n"


def self_test() -> None:
    def make(mode: str, names: list[str]) -> str:
        lines = [
            f"Thor PPU CALL TRACE BEGIN: mode={mode} count={len(names)} index={len(names)} cia=0x1"
        ]
        for seq, name in enumerate(names):
            lines.append(
                f"Thor PPU CALL TRACE: seq={seq} cia=0x{seq + 1:08x} func={name} "
                "rc=0x0 r3=0x1 r4=0x2 r5=0x3 r6=0x4"
            )
        lines.append("Thor PPU CALL TRACE END")
        return "\n".join(lines)

    hle = parse_trace(make("HLE_FLIP", ["a", "b", "c", "d", "e", "h"]), "self-hle")
    lle = parse_trace(make("LLE_FLIP", ["a", "b", "c", "d", "e", "l"]), "self-lle")
    report = compare(hle, lle, 2)
    assert "length=5" in report
    assert "Last aligned HLE call: seq=4 cia=0x00000005 e " in report
    assert "HLE calls after the shared block:\n  seq=5 cia=0x00000006 h " in report
    assert "LLE calls after the shared block:\n  seq=5 cia=0x00000006 l " in report

    hle_boundary = parse_trace(
        make("HLE_STALL", ["a", "b", "c", "d"]), "self-hle-boundary"
    )
    lle_boundary = parse_trace(
        make("LLE_VOICE", ["a", "b", "c", "d"]), "self-lle-boundary"
    )
    assert "length=4" in compare(hle_boundary, lle_boundary, 2)

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
