#!/usr/bin/env python3
"""Recover the predicate of every reachable SPU halt by backward slicing.

WHY THIS AND NOT PATTERN MATCHING

tools/spu_cfg.py recognises ONE idiom, the DMA argument assert, and reports the
other 39 reachable halts as "other check". That is not good enough to act on: if
a trap ever fires at one of those addresses, "other check" says nothing about
what the guest refused.

A backward slice answers it generally. Start from the register the halt tests,
walk back through the reachable instructions, and each time an instruction
writes a register the slice still needs, record it and add ITS sources. The
result is the expression the guest computed, rebuilt from the code rather than
guessed from a shape.

The opcode table comes from the emulator itself, Emu/Cell/SPUOpcodes.h.

USAGE

    python tools/spu_slice.py LS.bin --entry 0xf3c4 --entry 0x11e4
    python tools/spu_slice.py LS.bin --entry 0xf3c4 --at 0x13690   # one site
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import spu_cfg  # noqa: E402  the walker, the opcode table and the halt decoder

# Instruction shapes, by which fields are the destination and the sources.
#
# SPU encodings put the destination in different places. RRR ops (four operands)
# use bits 27..21 for RT and bits 6..0 for RC; everything else here uses bits
# 6..0 for RT. Getting this wrong silently slices the wrong register, which is
# the defect that made an earlier pass name a scratch register as the pointer.
RRR = {'SELB', 'SHUFB', 'MPYA', 'FNMS', 'FMA', 'FMS'}

# rt = f(ra)
ONE_SRC = {
    'ANDI', 'ORI', 'XORI', 'SFI', 'AI', 'CEQI', 'CGTI', 'CLGTI', 'ANDHI',
    'ORHI', 'CEQHI', 'CGTHI', 'CLGTHI', 'ANDBI', 'ORBI', 'CEQBI', 'CGTBI',
    'CLGTBI', 'AHI', 'SFHI', 'MPYI', 'MPYUI', 'XORHI', 'XORBI',
    'SHLQBYI', 'ROTQBYI', 'ROTQMBYI', 'SHLQBII', 'ROTQBII', 'ROTQMBII',
    'ROTI', 'ROTMI', 'ROTMAI', 'SHLI', 'ROTHI', 'ROTHMI', 'ROTMAHI', 'SHLHI',
    'XSWD', 'XSHW', 'XSBH', 'CNTB', 'CLZ', 'FSMBI', 'ORX', 'LQD', 'GBB',
    'GBH', 'GB', 'FSMB', 'FSMH', 'FSM', 'CBD', 'CHD', 'CWD', 'CDD',
    'ROTQBYBI', 'FRSQEST', 'FREST', 'ILHU',
}

# rt = f(ra, rb)
TWO_SRC = {
    'A', 'SF', 'AND', 'OR', 'XOR', 'NOR', 'NAND', 'ANDC', 'ORC', 'EQV',
    'CEQ', 'CGT', 'CLGT', 'CEQH', 'CGTH', 'CLGTH', 'CEQB', 'CGTB', 'CLGTB',
    'SHL', 'ROT', 'ROTM', 'ROTMA', 'SHLH', 'ROTH', 'ROTHM', 'ROTMAH',
    'SHLQBY', 'ROTQBY', 'ROTQMBY', 'SHLQBI', 'ROTQBI', 'ROTQMBI',
    'SHLQBYBI', 'ROTQBYBI', 'MPY', 'MPYU', 'MPYH', 'MPYS', 'MPYHH',
    'AVGB', 'ABSDB', 'SUMB', 'LQX', 'CBX', 'CHX', 'CWX', 'CDX',
    'ADDX', 'SFX', 'CG', 'BG', 'CGX', 'BGX', 'FA', 'FS', 'FM', 'DFA', 'DFS',
}

# Writes a register but the value does not come from a register we can follow.
OPAQUE = {'IL', 'ILH', 'ILA', 'LQR', 'LQA', 'RDCH', 'RCHCNT', 'FSCRRD'}

# Writes nothing.
NO_DEST = {
    'STQD', 'STQX', 'STQR', 'STQA', 'WRCH', 'STOP', 'STOPD', 'LNOP', 'NOP',
    'SYNC', 'DSYNC', 'MTSPR', 'FSCRWR', 'HBR', 'HBRA', 'HBRR', 'BR', 'BRA',
    'BRSL', 'BRASL', 'BRZ', 'BRNZ', 'BRHZ', 'BRHNZ', 'BI', 'BISL', 'IRET',
    'HEQ', 'HGT', 'HLGT', 'HEQI', 'HGTI', 'HLGTI',
}


def fields(word):
    return {
        'rt': word & 0x7f,
        'ra': (word >> 7) & 0x7f,
        'rb': (word >> 14) & 0x7f,
        'rt3': (word >> 21) & 0x7f,
        'rc': word & 0x7f,
        'i7': (word >> 14) & 0x7f,
        'i10': spu_cfg.sign((word >> 14) & 0x3ff, 10),
        'i16': spu_cfg.sign((word >> 7) & 0xffff, 16),
    }


def dest_of(name, word):
    if name in NO_DEST:
        return None
    if name in RRR:
        return (word >> 21) & 0x7f
    return word & 0x7f


def srcs_of(name, word):
    f = fields(word)
    if name in RRR:
        return [f['ra'], f['rb'], f['rc']]
    if name in TWO_SRC:
        return [f['ra'], f['rb']]
    if name in ONE_SRC:
        return [f['ra']]
    return []


def render(name, word):
    """One line of readable algebra for the instruction."""
    f = fields(word)
    if name in RRR:
        if name == 'SELB':
            return 'r%d = (r%d & ~r%d) | (r%d & r%d)' % (
                f['rt3'], f['ra'], f['rc'], f['rb'], f['rc'])
        return 'r%d = %s(r%d, r%d, r%d)' % (f['rt3'], name, f['ra'], f['rb'], f['rc'])
    if name in ('ANDI', 'ORI', 'XORI', 'AI', 'CEQI', 'CGTI', 'CLGTI', 'SFI'):
        op = {'ANDI': '&', 'ORI': '|', 'XORI': '^', 'AI': '+'}.get(name)
        if op:
            return 'r%d = r%d %s %d' % (f['rt'], f['ra'], op, f['i10'])
        if name == 'SFI':
            return 'r%d = %d - r%d' % (f['rt'], f['i10'], f['ra'])
        cmp_ = {'CEQI': '==', 'CGTI': '>s', 'CLGTI': '>u'}[name]
        return 'r%d = (r%d %s %d) ? ~0 : 0' % (f['rt'], f['ra'], cmp_, f['i10'])
    if name in ('CEQ', 'CGT', 'CLGT'):
        cmp_ = {'CEQ': '==', 'CGT': '>s', 'CLGT': '>u'}[name]
        return 'r%d = (r%d %s r%d) ? ~0 : 0' % (f['rt'], f['ra'], cmp_, f['rb'])
    if name in ('AND', 'OR', 'XOR', 'A', 'SF', 'NOR'):
        op = {'AND': '&', 'OR': '|', 'XOR': '^', 'A': '+', 'SF': '-', 'NOR': 'nor'}[name]
        if name == 'SF':
            return 'r%d = r%d - r%d' % (f['rt'], f['rb'], f['ra'])
        return 'r%d = r%d %s r%d' % (f['rt'], f['ra'], op, f['rb'])
    if name == 'IL':
        return 'r%d = %d' % (f['rt'], f['i16'])
    if name in ('LQD',):
        return 'r%d = load(r%d + %d)' % (f['rt'], f['ra'], f['i10'] * 16)
    if name in ('LQX',):
        return 'r%d = load(r%d + r%d)' % (f['rt'], f['ra'], f['rb'])
    if name in ('LQR', 'LQA'):
        return 'r%d = load(literal)' % f['rt']
    if name == 'RDCH':
        return 'r%d = channel %d' % (f['rt'], f['ra'])
    if name in ONE_SRC:
        return 'r%d = %s(r%d)' % (f['rt'], name, f['ra'])
    if name in TWO_SRC:
        return 'r%d = %s(r%d, r%d)' % (f['rt'], name, f['ra'], f['rb'])
    return name


def slice_back(store, code, halt_pc, guard, depth=40):
    """Instructions that feed `guard` at `halt_pc`, nearest first."""
    need = {guard}
    out = []
    pc = halt_pc - 4
    seen = 0
    while pc >= 0 and seen < depth and need:
        if pc not in code:
            break
        word = store.word(pc)
        name = store.name(pc)
        if name is None:
            break
        # Stop at a flow boundary. Past a BI, IRET, BR or BRA the code belongs
        # to another block, and a register live there is an INPUT to this one,
        # not something this block computed. Without this the slice walks into
        # the previous function and reports its r3 as the provenance of this
        # function's r3 parameter, which is simply a different value.
        if name in spu_cfg.ENDS or name in spu_cfg.UNCOND:
            break
        dest = dest_of(name, word)
        if dest is not None and dest in need:
            out.append((pc, name, render(name, word)))
            need.discard(dest)
            if name not in OPAQUE:
                need.update(srcs_of(name, word))
        pc -= 4
        seen += 1
    return out, need


def classify(lines, imm, op):
    """Name the class of assert from the recovered slice."""
    text = ' ; '.join(t for _, _, t in lines)
    masks = [n for _, nm, t in lines if nm == 'ANDI' for n in [t.rsplit('&', 1)[-1].strip()]]
    if '& 127' in text and any(m in ('3', '7', '15') for m in masks):
        return 'DMA argument assert: address 128-byte aligned AND size a multiple'
    if op == 'HEQI' and imm == -1:
        # Factual. -1 is the usual error return, but this tool has not proved
        # that is what the value is, so the label does not assert it.
        return 'halts when the value is -1 (often an error return)'
    if op == 'HEQI' and imm == 0 and any(nm == 'SELB' for _, nm, _ in lines):
        return 'compound boolean assert: halts unless every condition holds'
    if op == 'HEQI' and imm == 0 and any(nm in ('SFI', 'CEQI') for _, nm, _ in lines):
        return 'boolean assert: halts unless the tested condition holds'
    if op == 'HEQI' and imm == 0:
        return 'halts when the value is zero'
    if op in ('HGTI', 'HLGTI'):
        return 'range assert: halts when the value exceeds %d' % imm
    return 'unclassified'


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('image')
    ap.add_argument('--entry', action='append', default=[])
    ap.add_argument('--at', help='slice only this halt address')
    ap.add_argument('--depth', type=int, default=40)
    ap.add_argument('--opcodes', default=spu_cfg.OPCODES)
    ap.add_argument('--verbose', action='store_true', help='print each slice')
    args = ap.parse_args()

    entries = [int(e, 0) for e in args.entry] or [0]
    store = spu_cfg.Store(open(args.image, 'rb').read(),
                          spu_cfg.load_opcodes(args.opcodes))
    code, _calls = spu_cfg.walk(store, entries)

    halts = [pc for pc in sorted(code) if spu_cfg.halt_at(store, pc)]
    if args.at:
        want = int(args.at, 0)
        halts = [pc for pc in halts if pc == want]
        if not halts:
            sys.exit('0x%05x is not a reachable halt' % want)

    tally = {}
    for pc in halts:
        op, guard, imm = spu_cfg.halt_at(store, pc)
        lines, unresolved = slice_back(store, code, pc, guard, args.depth)
        kind = classify(lines, imm, op)
        tally[kind] = tally.get(kind, 0) + 1
        print('0x%05x  %-6s r%-3d imm=%-4s  %s'
              % (pc, op, guard, '-' if imm is None else imm, kind))
        if args.verbose or args.at:
            for spc, _nm, text in lines:
                print('           0x%05x  %s' % (spc, text))
            if unresolved:
                print('           inputs not produced in this slice: %s'
                      % ', '.join('r%d' % r for r in sorted(unresolved)))
            print()

    print()
    print('%d reachable halts:' % len(halts))
    for kind, n in sorted(tally.items(), key=lambda kv: -kv[1]):
        print('  %3d  %s' % (n, kind))
    left = tally.get('unclassified', 0)
    print()
    print('unclassified: %d' % left)


if __name__ == '__main__':
    main()
