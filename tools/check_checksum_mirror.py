#!/usr/bin/env python3
"""Fail when the SPU block checksum IR and its host mirror disagree.

The SPU block verifier computes a checksum twice: once as LLVM IR the JIT emits,
and once in C++ on the host. The two MUST produce the same number. If they
differ by so much as a weight, every block fails verification and the runtime
recompiles for ever -- which is far slower than any checksum, and which reports
itself nowhere.

The two live about 100 lines apart in one file and nothing tied them together.
On 2026-08-22 the ARM fold changed from a + b to a + 2b and both sides had to
move. This check exists so the next person cannot move one and not the other.

Run: python tools/check_checksum_mirror.py
"""
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp"


def fail(message):
    print("FAIL: " + message)
    sys.exit(1)


def main():
    if not SRC.is_file():
        fail("source not found: %s. Fix the path in this check before trusting it." % SRC)

    text = SRC.read_text(encoding="utf-8", errors="replace")

    # IR side: next_acc[N] = add(next_acc[N], add(vls[a], shl(vls[b], k)))  -- k absent means weight 1.
    ir = {}
    for m in re.finditer(
        r"next_acc\[(\d)\]\s*=\s*m_ir->CreateAdd\(next_acc\[\1\],\s*m_ir->CreateAdd\("
        r"vls\[\d\],\s*(?:m_ir->CreateShl\(vls\[\d\],\s*(\d+)\)|vls\[\d\])\s*\)\s*\)",
        text):
        ir[int(m.group(1))] = 1 << int(m.group(2)) if m.group(2) else 1

    # Host side: checksum[N + i] += words[..] + W * words[..]  -- W absent means 1.
    host = {}
    for m in re.finditer(
        r"checksum\[(\d+) \+ i\]\s*\+=\s*words\[\d+ \+ i\]\s*\+\s*(?:(\d+)\s*\*\s*)?words\[\d+ \+ i\]",
        text):
        host[int(m.group(1)) // 4] = int(m.group(2)) if m.group(2) else 1

    if not ir:
        fail("found no folded IR accumulate. This check searched nothing, which is not a pass.")
    if not host:
        fail("found no folded host accumulate. This check searched nothing, which is not a pass.")

    for lane, weight in sorted(ir.items()):
        if lane not in host:
            fail("IR folds lane %d but the host mirror has no matching lane." % lane)
        if host[lane] != weight:
            fail("lane %d: IR weights the second word by %d, the host mirror by %d. "
                 "Every block would fail verification." % (lane, weight, host[lane]))

    for lane in host:
        if lane not in ir:
            fail("host mirror folds lane %d but the IR does not." % lane)

    for lane, weight in sorted(ir.items()):
        if weight == 1:
            fail("lane %d folds two words with equal weight. Addition commutes, so that fold "
                 "cannot see the two words swap, which is ordinary code motion in a streamed "
                 "job binary. Use a different weight." % lane)

    print("OK: %d folded lane(s), IR and host mirror agree, no lane uses a commutative fold."
          % len(ir))
    for lane, weight in sorted(ir.items()):
        print("  lane %d: second word weighted x%d" % (lane, weight))


if __name__ == "__main__":
    main()
