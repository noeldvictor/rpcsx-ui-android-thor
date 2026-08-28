#!/usr/bin/env python3
"""Compare bounded Transformers HLE and LLE counter-poll probes."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


MARKER = "Thor Transformers COUNTER:"
EVENT_ORDER = {
    "ENTRY": 0,
    "GLOBAL_WAIT": 1,
    "GLOBAL_EQUAL": 2,
    "OBJECT_WAIT": 3,
    "OBJECT_EQUAL": 4,
}


@dataclass(frozen=True)
class Pair:
    address: int
    value: int


@dataclass(frozen=True)
class Event:
    mode: str
    emulation_id: int
    invocation: int
    event: str
    cia: int
    waits: int | None
    first: Pair | None
    second: Pair | None


@dataclass(frozen=True)
class Invocation:
    index: int
    events: tuple[Event, ...]
    global_waits: int | None
    object_waits: int | None

    @property
    def complete(self) -> bool:
        return bool(self.events) and self.events[-1].event == "OBJECT_EQUAL"


def parse_int(value: str) -> int:
    return int(value, 16 if value.lower().startswith("0x") else 10)


def parse_pair(value: str) -> Pair:
    address, item = value.split(":", 1)
    return Pair(parse_int(address), parse_int(item))


def parse_event(line: str, source: str, line_number: int) -> Event | None:
    marker_index = line.find(MARKER)
    if marker_index < 0:
        return None

    fields = {}
    for token in line[marker_index + len(MARKER) :].split():
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value

    required = {"mode", "emulation_id", "invocation", "event", "cia"}
    missing = sorted(required - fields.keys())
    if missing:
        raise ValueError(
            f"{source}:{line_number}: counter row misses {', '.join(missing)}"
        )

    event_name = fields["event"]
    if event_name not in EVENT_ORDER:
        raise ValueError(f"{source}:{line_number}: unknown event {event_name}")

    if event_name == "ENTRY":
        waits = None
        first = None
        second = None
    else:
        detail_required = {"waits", "first", "second"}
        detail_missing = sorted(detail_required - fields.keys())
        if detail_missing:
            raise ValueError(
                f"{source}:{line_number}: counter detail misses "
                f"{', '.join(detail_missing)}"
            )
        waits = parse_int(fields["waits"])
        first = parse_pair(fields["first"])
        second = parse_pair(fields["second"])

    return Event(
        mode=fields["mode"],
        emulation_id=parse_int(fields["emulation_id"]),
        invocation=parse_int(fields["invocation"]),
        event=event_name,
        cia=parse_int(fields["cia"]),
        waits=waits,
        first=first,
        second=second,
    )


def parse_probe(text: str, source: str, expected_mode: str) -> tuple[Invocation, ...]:
    events = tuple(
        event
        for line_number, line in enumerate(text.splitlines(), 1)
        if (event := parse_event(line, source, line_number)) is not None
    )
    if not events:
        raise ValueError(f"{source}: no counter probe rows were found")

    modes = {event.mode for event in events}
    if modes != {expected_mode}:
        raise ValueError(
            f"{source}: expected mode {expected_mode}, found {', '.join(sorted(modes))}"
        )
    emulation_ids = {event.emulation_id for event in events}
    if len(emulation_ids) != 1:
        raise ValueError(f"{source}: rows contain more than one emulation ID")

    groups: dict[int, list[Event]] = {}
    for event in events:
        groups.setdefault(event.invocation, []).append(event)

    expected_invocations = list(range(min(groups), max(groups) + 1))
    if sorted(groups) != expected_invocations or expected_invocations[0] != 0:
        raise ValueError(f"{source}: invocation numbers are not contiguous from zero")

    invocations = []
    for index in expected_invocations:
        rows = groups[index]
        if rows[0].event != "ENTRY":
            raise ValueError(f"{source}: invocation {index} does not start with ENTRY")
        if any(
            EVENT_ORDER[right.event] < EVENT_ORDER[left.event]
            for left, right in zip(rows, rows[1:])
        ):
            raise ValueError(f"{source}: invocation {index} has reversed event order")
        for terminal in ("GLOBAL_EQUAL", "OBJECT_EQUAL"):
            if sum(row.event == terminal for row in rows) > 1:
                raise ValueError(
                    f"{source}: invocation {index} has more than one {terminal} row"
                )

        wait_totals = {}
        for prefix in ("GLOBAL", "OBJECT"):
            wait_rows = [row for row in rows if row.event == f"{prefix}_WAIT"]
            observed = [row.waits for row in wait_rows]
            if any(
                right is None or left is None or right <= left
                for left, right in zip(observed, observed[1:])
            ):
                raise ValueError(
                    f"{source}: invocation {index} has non-increasing {prefix} waits"
                )
            equal_rows = [row for row in rows if row.event == f"{prefix}_EQUAL"]
            total = equal_rows[0].waits if equal_rows else None
            if total is not None and observed and total < observed[-1]:
                raise ValueError(
                    f"{source}: invocation {index} has an invalid {prefix} total"
                )
            wait_totals[prefix] = total

        invocations.append(
            Invocation(
                index=index,
                events=tuple(rows),
                global_waits=wait_totals["GLOBAL"],
                object_waits=wait_totals["OBJECT"],
            )
        )

    return tuple(invocations)


def pair_changes(invocation: Invocation, prefix: str) -> int:
    pairs = {
        (event.first.value, event.second.value)
        for event in invocation.events
        if event.event == f"{prefix}_WAIT"
        and event.first is not None
        and event.second is not None
    }
    return len(pairs)


def describe_mode(label: str, invocations: tuple[Invocation, ...]) -> str:
    complete = sum(invocation.complete for invocation in invocations)
    events = sum(len(invocation.events) for invocation in invocations)
    return f"{label}: invocations={len(invocations)} complete={complete} events={events}"


def format_waits(value: int | None) -> str:
    return "-" if value is None else str(value)


def compare(
    hle: tuple[Invocation, ...],
    lle: tuple[Invocation, ...],
    limit: int,
) -> str:
    lines = [describe_mode("HLE", hle), describe_mode("LLE", lle)]
    shared = min(len(hle), len(lle), limit)
    lines.append(
        "invocation HLE(global,object,changes,complete) "
        "LLE(global,object,changes,complete)"
    )
    first_difference = None
    for index in range(shared):
        left = hle[index]
        right = lle[index]
        left_shape = (
            left.global_waits,
            left.object_waits,
            pair_changes(left, "GLOBAL") + pair_changes(left, "OBJECT"),
            left.complete,
        )
        right_shape = (
            right.global_waits,
            right.object_waits,
            pair_changes(right, "GLOBAL") + pair_changes(right, "OBJECT"),
            right.complete,
        )
        if first_difference is None and left_shape != right_shape:
            first_difference = index
        lines.append(
            f"{index:>10} "
            f"HLE({format_waits(left.global_waits)},{format_waits(left.object_waits)},"
            f"{left_shape[2]},{'yes' if left.complete else 'no'}) "
            f"LLE({format_waits(right.global_waits)},{format_waits(right.object_waits)},"
            f"{right_shape[2]},{'yes' if right.complete else 'no'})"
        )

    if first_difference is None:
        lines.append(f"First summary difference: none in {shared} shared invocations")
    else:
        lines.append(f"First summary difference: invocation {first_difference}")
    return "\n".join(lines)


def self_test() -> None:
    hle_text = """
Thor Transformers COUNTER: mode=HLE emulation_id=1 invocation=0 event=ENTRY cia=0x00fdcf20 r3=0x1 r30=0x2
Thor Transformers COUNTER: mode=HLE emulation_id=1 invocation=0 event=GLOBAL_EQUAL cia=0x00fdcf74 waits=0 first=0x10:0x3 second=0x14:0x3 r0=0x3 r9=0x3 r29=0x0 r30=0x2 r31=0x0
Thor Transformers COUNTER: mode=HLE emulation_id=1 invocation=0 event=OBJECT_WAIT cia=0x00fdcf90 waits=1 first=0x24:0x4 second=0x20:0x5 r0=0x4 r9=0x5 r29=0x0 r30=0x2 r31=0x20
Thor Transformers COUNTER: mode=HLE emulation_id=1 invocation=0 event=OBJECT_EQUAL cia=0x00fdcfa4 waits=1 first=0x24:0x5 second=0x20:0x5 r0=0x5 r9=0x5 r29=0x5 r30=0x2 r31=0x20
"""
    lle_text = """
Thor Transformers COUNTER: mode=LLE emulation_id=2 invocation=0 event=ENTRY cia=0x00fdcf20 r3=0x1 r30=0x2
Thor Transformers COUNTER: mode=LLE emulation_id=2 invocation=0 event=GLOBAL_WAIT cia=0x00fdcf60 waits=1 first=0x10:0x3 second=0x14:0x4 r0=0x3 r9=0x4 r29=0x0 r30=0x2 r31=0x0
Thor Transformers COUNTER: mode=LLE emulation_id=2 invocation=0 event=GLOBAL_EQUAL cia=0x00fdcf74 waits=1 first=0x10:0x4 second=0x14:0x4 r0=0x4 r9=0x4 r29=0x4 r30=0x2 r31=0x0
Thor Transformers COUNTER: mode=LLE emulation_id=2 invocation=0 event=OBJECT_EQUAL cia=0x00fdcfa4 waits=0 first=0x24:0x5 second=0x20:0x5 r0=0x5 r9=0x5 r29=0x0 r30=0x2 r31=0x20
"""
    hle = parse_probe(hle_text, "HLE self-test", "HLE")
    lle = parse_probe(lle_text, "LLE self-test", "LLE")
    output = compare(hle, lle, 8)
    assert hle[0].global_waits == 0
    assert hle[0].object_waits == 1
    assert lle[0].global_waits == 1
    assert lle[0].object_waits == 0
    assert "First summary difference: invocation 0" in output
    print("self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hle_log", nargs="?", type=Path)
    parser.add_argument("lle_log", nargs="?", type=Path)
    parser.add_argument("--limit", type=int, default=16)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return
    if args.hle_log is None or args.lle_log is None:
        parser.error("hle_log and lle_log are required unless --self-test is used")
    if args.limit <= 0:
        parser.error("--limit must be positive")

    hle = parse_probe(
        args.hle_log.read_text(encoding="utf-8", errors="replace"),
        str(args.hle_log),
        "HLE",
    )
    lle = parse_probe(
        args.lle_log.read_text(encoding="utf-8", errors="replace"),
        str(args.lle_log),
        "LLE",
    )
    print(compare(hle, lle, args.limit))


if __name__ == "__main__":
    main()
