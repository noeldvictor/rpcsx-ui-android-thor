#!/usr/bin/env python3
"""Prove that validate_patch_op() rejects what it claims to reject.

A check that has never been shown to catch anything is not worth trusting, and
"0 failures" from a validator that validates nothing reads exactly like a clean
bill of health. This file is the reconstruction step: every negative case below
is a defect the bundled collection could plausibly ship.

    python tools/test_cheat_patch_validation.py

Exits non-zero if any case behaves differently from the expectation.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_cheat_db import validate_patch_op  # noqa: E402

CASES = [
    # (op, expected_ok, label)
    (("be32", "0x00100000", "0x60000000"), True, "valid be32"),
    (("byte", "0x10", "0xFF"), True, "byte at unsigned max"),
    (("byte", "0x10", "-128"), True, "byte at signed min"),
    (("be64", "0x10", "0x1122334455667788"), True, "valid be64"),
    (("bef32", "0x10", "1.5"), True, "valid float"),
    (("utf8", "0x10", '"text"'), True, "quoted string"),
    (("bpex", "0x10", "anything"), True, "bpex passes through"),
    (("move_file", "some/path", ""), True, "file type"),
    (("jump", "0x100", "0x200"), True, "jump"),

    (("byte", "0x10", "0x1FF"), False, "byte value out of range"),
    (("be16", "0x10", "0x10000"), False, "be16 value out of range"),
    (("byte", "0x10", "-129"), False, "byte below signed min"),
    (("be32", "nothex", "0x1"), False, "address not parseable"),
    (("be32", "-0x1", "0x1"), False, "negative address"),
    (("be32", "0x10", "alsonothex"), False, "value not parseable"),
    (("utf8", "0x10", "notquoted"), False, "unquoted string value"),
    (("bef32", "0x10", "notafloat"), False, "value not a float"),
    (("be322", "0x10", "0x1"), False, "UNKNOWN TYPE - upstream format drift"),
    (("load", "notananchor", ""), False, "load without *anchor"),
]


def main():
    failures = 0
    for op, expected_ok, label in CASES:
        ok, reason = validate_patch_op(op)
        good = ok == expected_ok
        if not good:
            failures += 1
        mark = "ok  " if good else "FAIL"
        print(f"  [{mark}] {label:34} got ok={str(ok):5} {reason}")

    print()
    if failures:
        print(f"SELF-TEST FAILED: {failures} of {len(CASES)} cases behaved unexpectedly")
        return 1
    print(f"All {len(CASES)} cases behaved as expected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
