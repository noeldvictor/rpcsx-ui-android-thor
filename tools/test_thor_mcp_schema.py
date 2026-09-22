#!/usr/bin/env python3
"""Check that each thor MCP tool declares every argument that its code reads.

An MCP client sends only the arguments that a tool's inputSchema declares. On
2026-09-22 `thor_state` read `pause` but did not declare it, so the client
dropped `"pause": false` and the tool paused the emulator anyway. `call.py`
passes raw JSON, so it hid the defect.

This test reads the source of each tool handler, and of the helpers it calls
with the argument dict, and fails when a key read with `a.get("KEY")` is not in
the schema.
"""
import inspect
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "thor_mcp"))
import server  # noqa: E402

KEY = re.compile(r'\ba\.get\(\s*"([A-Za-z_][A-Za-z0-9_]*)"')
CALL_WITH_ARGS = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)\(\s*a\b')


def keys_read(fn, seen=None):
    """Keys read from the argument dict by fn and by the helpers it passes it to."""
    seen = seen if seen is not None else set()
    if fn in seen:
        return set()
    seen.add(fn)
    src = inspect.getsource(fn)
    keys = set(KEY.findall(src))
    for name in CALL_WITH_ARGS.findall(src):
        helper = getattr(server, name, None)
        if inspect.isfunction(helper) and helper is not fn:
            keys |= keys_read(helper, seen)
    return keys


def main():
    failures = []
    for name, _desc, schema, fn in server.TOOLS:
        declared = set((schema.get("properties") or {}).keys())
        missing = sorted(keys_read(fn) - declared)
        if missing:
            failures.append(f"{name}: reads {missing} but the schema does not declare them")
    if failures:
        print("Thor MCP schema check FAILED:")
        for line in failures:
            print("  " + line)
        return 1
    print(f"Thor MCP schema check passed: {len(server.TOOLS)} tools declare every argument they read.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
