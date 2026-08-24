#!/usr/bin/env python3
"""Find and classify the halt sites in a captured SPU local store.

WHY THIS EXISTS

A halt instruction is how a PS3 guest refuses a value. When one fires, the
emulator raises 0xffdeadXX and the title stops. To fix that, you must know WHICH
check refused, and WHAT it refused.

A linear scan cannot tell you. The SPU opcode space is dense, so almost every
word decodes as a valid instruction. A scan of a 256 KB local store reports 146
halt sites, and most of them are data. Recursive descent from an address that
really executed answers both questions at once.

The opcode table is read from the decode table of the emulator itself, in
Emu/Cell/SPUOpcodes.h. This tool therefore cannot disagree with the recompiler.

HOW TO GET A LOCAL STORE

    adb shell setprop debug.rpcsx.thor.spu_ls_dump CellSpursKernel0

The dump goes beside the log. See AGENTS.md.

USAGE

    python tools/spu_cfg.py LS.bin --entry 0xf3c4 --entry 0x11e4

Give every program counter that you saw, from /diag, from a trap message, or
from the dump header. Entry points are necessary. With none, the walk starts at
address 0, and address 0 is usually not code in a thread that runs.
"""
import argparse
import collections
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OPCODES = os.path.join(HERE, os.pardir, 'app', 'src', 'main', 'cpp', 'rpcsx',
                       'rpcs3', 'Emu', 'Cell', 'SPUOpcodes.h')

# Branches that end or divert a straight run of instructions.
REL = {'BR', 'BRSL', 'BRZ', 'BRNZ', 'BRHZ', 'BRHNZ'}
ABS = {'BRA', 'BRASL'}
CALL = {'BRSL', 'BRASL'}
UNCOND = {'BR', 'BRA'}
ENDS = {'BI', 'IRET', 'STOP', 'STOPD'}

# Halt forms. RI10 compares RA against an immediate. RR compares RA against RB.
HALT_RI = {0x4f: 'HGTI', 0x5f: 'HLGTI', 0x7f: 'HEQI'}
HALT_RR = {0x258: 'HGT', 0x2d8: 'HLGT', 0x3d8: 'HEQ'}

ANDI_OP = 0x14  # RI10 form, inst >> 24


def load_opcodes(path):
    """Build an index to mnemonic map from the decode table of the emulator."""
    text = open(path, 'rb').read().decode('utf-8', 'replace')
    table = {}
    for magn, val, name in re.findall(
            r'\{\s*(\d+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*GET\((\w+)\)', text):
        magn, val = int(magn), int(val, 16)
        for i in range(1 << magn):
            table[(val << magn) | i] = name
    if not table:
        sys.exit('no opcodes parsed from %s' % path)
    return table


def sign(value, bits):
    top = 1 << (bits - 1)
    return value - (1 << bits) if value & top else value


class Store(object):
    def __init__(self, blob, table):
        self.blob = blob
        self.size = len(blob)
        self.table = table

    def word(self, pc):
        return struct.unpack_from('>I', self.blob, pc)[0]

    def name(self, pc):
        return self.table.get(self.word(pc) >> 21)

    def target(self, pc):
        """The branch target, or None if this is not a static branch."""
        name = self.name(pc)
        inst = self.word(pc)
        if name in REL:
            return (pc + sign((inst >> 7) & 0xffff, 16) * 4) & (self.size - 1)
        if name in ABS:
            return ((inst >> 7) & 0xffff) * 4
        return None


def walk(store, entries):
    """Recursive descent. Gives the reachable addresses and the call targets."""
    seen = set()
    calls = collections.defaultdict(list)
    work = list(entries)
    while work:
        pc = work.pop()
        while 0 <= pc < store.size - 3 and pc not in seen:
            seen.add(pc)
            name = store.name(pc)
            if name is None:
                break  # Not an instruction, so this run was not code.
            if name in REL or name in ABS:
                tgt = store.target(pc)
                if name in CALL:
                    calls[tgt].append(pc)
                if tgt is not None and 0 <= tgt < store.size - 3 and tgt not in seen:
                    work.append(tgt)
                if name in UNCOND:
                    break
            elif name in ENDS:
                break
            pc += 4
    return seen, calls


def halt_at(store, pc):
    """Gives (mnemonic, guard register, immediate or None) if pc holds a halt."""
    word = store.word(pc)
    if (word >> 21) in HALT_RR:
        return HALT_RR[word >> 21], (word >> 7) & 0x7f, None
    if (word >> 24) in HALT_RI:
        return HALT_RI[word >> 24], (word >> 7) & 0x7f, sign((word >> 14) & 0x3ff, 10)
    return None


def classify(store, pc):
    """Recognise the SPURS DMA argument assert.

    Seven of the 46 reachable halts in the captured SPURS kernel share this
    idiom. They are one cluster of DMA helpers at 0x133c0 to 0x137d0. The
    other 39 reachable halts are different checks:

        ANDI  rX, rEA, 127          effective address aligned to 128 bytes
        SHLQBYI rY, rSIZE, 4
        ANDI  rZ, rY, 3 | 7 | 15    size a multiple of 4, 8 or 16
        CEQI / SFI / SELB
        HEQI  rR, 0                 halt unless BOTH conditions hold

    Gives (ea_register, size_mask), or (None, 0) for a different check.
    """
    ea_reg, size_mask = None, 0
    for back in range(4, 68, 4):
        if pc < back:
            break
        word = store.word(pc - back)
        if (word >> 24) != ANDI_OP:
            continue
        mask = (word >> 14) & 0x3ff
        if mask == 127:
            # Keep looking. A block can hold two masks of 127: the address
            # check, and a later one on a derived value that does not reach the
            # halt. Block 0x133c0 has ANDI r17, r3, 127 and then ANDI r14, r16,
            # 127. The address check is always the earlier of the two, so the
            # last one this backward scan sees is the right one.
            ea_reg = (word >> 7) & 0x7f
        elif mask in (3, 7, 15) and size_mask == 0:
            size_mask = mask
    return ea_reg, size_mask


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('image', help='local store dump, 256 KB')
    ap.add_argument('--entry', action='append', default=[],
                    help='a program counter that really executed. Repeatable.')
    ap.add_argument('--opcodes', default=OPCODES)
    args = ap.parse_args()

    entries = [int(e, 0) for e in args.entry] or [0]
    store = Store(open(args.image, 'rb').read(), load_opcodes(args.opcodes))
    code, calls = walk(store, entries)

    scanned = sum(1 for pc in range(0, store.size, 4) if halt_at(store, pc))
    reached = [pc for pc in sorted(code) if halt_at(store, pc)]

    print('entries      : %s' % ', '.join('0x%05x' % e for e in entries))
    print('reachable    : %d instructions, %d bytes' % (len(code), len(code) * 4))
    print('halt sites   : %d reachable, against %d that a linear scan reports'
          % (len(reached), scanned))
    if not reached:
        print()
        print('No reachable halt. Give a program counter that really executed.')
        return

    print()
    print(' addr     op     guard  assert')
    asserts = 0
    for pc in reached:
        op, guard, _imm = halt_at(store, pc)
        ea_reg, size_mask = classify(store, pc)
        if ea_reg is not None:
            asserts += 1
            what = ('DMA argument assert: (r%d & 127) == 0, size mask %d'
                    % (ea_reg, size_mask))
        else:
            what = 'other check'
        entry = ('entry, %d caller(s)' % len(calls[pc])) if pc in calls else ''
        print(' 0x%05x %-6s r%-4d %s %s' % (pc, op, guard, what, entry))

    print()
    print('%d of %d reachable halts are DMA argument asserts.'
          % (asserts, len(reached)))
    print('An assert on alignment refuses a POINTER, not a schedule. To hunt')
    print('one of these, perturb data. Do not perturb timing.')


if __name__ == '__main__':
    main()
