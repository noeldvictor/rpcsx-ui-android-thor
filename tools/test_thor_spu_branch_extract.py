"""Pin the SPU branch lane-extract gate: the property, the default, eight sites,
the sext guard, and the hoist.

Why this test exists
--------------------

Eight SPU branch lowerings -- `BIZ`, `BINZ`, `BIHZ`, `BIHNZ`, `BRZ`, `BRNZ`,
`BRHZ` and `BRHNZ` -- carry a fast path that builds a 16-bit movemask and tests
one bit of it. That is an x86 optimization. It is `PMOVMSKB` plus `TEST` there.
AArch64 has no movemask, so LLVM builds one: 8 instructions for a word and 9 for
a halfword, against 2 for a lane extract. `docs/arm64/x86-tricks-arm64-answers.md`
holds the compiled assembly for both spellings.

Four properties are asserted, and each one is silent when it breaks.

1. **The gate exists and the default is off.** The change ships unmeasured. A
   default that flips to on would change the codegen of every SPU branch on the
   device with no A/B behind it.
2. **All eight sites are gated.** The same failure shape as the lv2 spin sweep:
   a change that reaches seven of eight sites gives a measurement that says the
   change did less than it should. Nothing else reports it.
3. **The sext guard still encloses every gated site.** This is the load-bearing
   one. The two spellings agree only when every lane is all-zeros or all-ones,
   which `match_expr(c, sext<VT>(match<bool[N]>()))` guarantees. Over arbitrary
   bytes the two predicates differ on about half of the inputs. A site that
   reaches the lane extract without the guard is a wrong branch, and a wrong
   branch is worse than a slow one.
4. **The property read is hoisted.** `thor::spu_branch_extract()` holds a
   function-local static, which costs a guard-variable acquire load on every
   call. `spu_llvm_recompiler` reads it once into a member. Calling the function
   from an opcode handler puts that load in the compile loop. This fork already
   made that mistake once, with `get_thor_pause_mode` -- see the comment on
   `pause()` in rx/asm.hpp.

Usage:  python tools/test_thor_spu_branch_extract.py
Exit 1 on any failure.
"""
import io
import os
import re
import sys

TARGET = 'app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp'
HEADER = 'app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/thor_spu_branch_extract.h'

PROPERTY = 'debug.rpcsx.thor.spu_branch_extract'
MEMBER = 'm_thor_spu_branch_extract'
ACCESSOR = 'thor::spu_branch_extract()'

# opcode -> (extract arm, movemask arm)
SITES = {
    'BIZ': ('extract(get_vr(op.rt), 3) == 0',
            'bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) >= 0'),
    'BINZ': ('extract(get_vr(op.rt), 3) != 0',
             'bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) < 0'),
    'BIHZ': ('extract(get_vr<u16[8]>(op.rt), 6) == 0',
             '(bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) & 0x3000) == 0'),
    'BIHNZ': ('extract(get_vr<u16[8]>(op.rt), 6) != 0',
              '(bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) & 0x3000) != 0'),
    'BRZ': ('extract(get_vr(op.rt), 3) == 0',
            'bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) >= 0'),
    'BRNZ': ('extract(get_vr(op.rt), 3) != 0',
             'bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) < 0'),
    'BRHZ': ('extract(get_vr<u16[8]>(op.rt), 6) == 0',
             '(bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) & 0x3000) == 0'),
    'BRHNZ': ('extract(get_vr<u16[8]>(op.rt), 6) != 0',
              '(bitcast<s16>(trunc<bool[16]>(get_vr<s8[16]>(op.rt))) & 0x3000) != 0'),
}

# The gated conditional, and the two arms that must follow it.
GATED = re.compile(
    r'const auto cond = ' + re.escape(MEMBER) + r'\s*\n'
    r'\s*\? eval\((?P<fast>.+?)\);?\s*\n'
    r'\s*: eval\((?P<slow>.+?)\);\s*\n')

# The enclosing opcode handler.
HANDLER = re.compile(r'\bvoid ([A-Z][A-Z0-9]*)\(spu_opcode_t op\)')

# The guard the equivalence rests on.
GUARD = re.compile(
    r'match_expr\(c, sext<VT>\(match<bool\[std::extent_v<VT>\]>\(\)\)\)')

# Any movemask branch predicate. Every one must be the slow arm of a gate.
MOVEMASK = re.compile(r'bitcast<s16>\(trunc<bool\[16\]>')

# How far back the guard may sit. The handlers put it 12 to 16 lines above.
GUARD_WINDOW = 24


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def strip_arm(text):
    """Remove the trailing paren the regex leaves on a nested arm."""
    text = text.strip()
    while text.endswith(')') and text.count(')') > text.count('('):
        text = text[:-1].strip()
    return text


def check_header(failures):
    if not os.path.exists(HEADER):
        failures.append(f'missing {HEADER}')
        return

    header = read(HEADER)

    if PROPERTY not in header:
        failures.append(f'{HEADER}: the property name {PROPERTY} is missing')

    if '__system_property_get' not in header:
        failures.append(f'{HEADER}: the header never reads an Android property')

    # The default must be off. Both the property path and the non-AArch64 stub
    # return false, and no path may return true without a value.
    if 'if (!v) {\n      return false;\n    }' not in header:
        failures.append(f'{HEADER}: an absent property does not default to off')

    if 'inline bool spu_branch_extract() { return false; }' not in header:
        failures.append(f'{HEADER}: the non-AArch64 stub is not a constant false')

    if re.search(r'return\s+true\s*;', header):
        failures.append(f'{HEADER}: a path returns true unconditionally')


def check_hoist(text, failures):
    calls = [m.start() for m in re.finditer(re.escape(ACCESSOR), text)]

    if len(calls) != 1:
        failures.append(
            f'{TARGET}: {len(calls)} call(s) to {ACCESSOR}, expected 1 -- '
            'the property must be read once into a member, never per opcode')
        return

    line = text[:calls[0]].count('\n') + 1
    declaration = f'const bool {MEMBER} = {ACCESSOR};'

    if declaration not in text:
        failures.append(
            f'{TARGET}: the single call is not the member initializer '
            f'`{declaration}`')
        return

    # The member must be declared before any handler, so the read cannot sit
    # inside the compile loop.
    first_handler = HANDLER.search(text)
    if first_handler and calls[0] > first_handler.start():
        failures.append(
            f'{TARGET}:{line}: the property read sits inside an opcode '
            'handler; hoist it into the class member')


def check_sites(text, failures):
    lines = text.split('\n')
    seen = {}

    for m in GATED.finditer(text):
        line = text[:m.start()].count('\n') + 1

        handlers = HANDLER.findall(text[:m.start()])
        name = handlers[-1] if handlers else '<none>'

        fast = strip_arm(m.group('fast'))
        slow = strip_arm(m.group('slow'))

        if name not in SITES:
            failures.append(
                f'{TARGET}:{line}: a gate sits in {name}(), which is not one '
                'of the eight verified branch lowerings')
            continue

        seen.setdefault(name, []).append(line)

        want_fast, want_slow = SITES[name]
        if fast != want_fast:
            failures.append(
                f'{TARGET}:{line}: {name} extract arm is `{fast}`, '
                f'expected `{want_fast}`')
        if slow != want_slow:
            failures.append(
                f'{TARGET}:{line}: {name} movemask arm is `{slow}`, '
                f'expected `{want_slow}`')

        # The guard is load-bearing. It must enclose this gate.
        window = '\n'.join(lines[max(0, line - 1 - GUARD_WINDOW):line - 1])
        if not GUARD.search(window):
            failures.append(
                f'{TARGET}:{line}: {name} reaches the lane extract with no '
                'sext guard above it -- the two spellings are not equivalent '
                'for an unguarded lane')

    for name in SITES:
        count = len(seen.get(name, []))
        if count != 1:
            failures.append(
                f'{TARGET}: {name} has {count} gated branch lowering(s), '
                'expected 1')

    return sum(len(v) for v in seen.values())


def check_no_ungated_movemask(text, failures):
    gated_lines = set()
    for m in GATED.finditer(text):
        start = text[:m.start()].count('\n') + 1
        for offset in range(0, m.group(0).count('\n') + 1):
            gated_lines.add(start + offset)

    lines = text.split('\n')
    for index, line in enumerate(lines, start=1):
        if not MOVEMASK.search(line):
            continue
        if index in gated_lines:
            continue
        failures.append(
            f'{TARGET}:{index}: a movemask branch predicate is not behind the '
            f'{MEMBER} gate')


def main():
    failures = []

    check_header(failures)

    if not os.path.exists(TARGET):
        print(f'FAIL missing {TARGET}')
        return 1

    text = read(TARGET)

    if 'thor_spu_branch_extract.h' not in text:
        failures.append(f'{TARGET}: missing #include "thor_spu_branch_extract.h"')

    check_hoist(text, failures)
    total = check_sites(text, failures)
    check_no_ungated_movemask(text, failures)

    for line in failures:
        print(f'FAIL {line}')

    print(f'{len(SITES)} branch lowerings, {total} gated site(s), '
          f'{len(failures)} failure(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
