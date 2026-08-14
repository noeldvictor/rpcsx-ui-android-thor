"""Diff this fork's reg_state_t against upstream's.

Upstream's reduced-loop analyzer refuses on properties of its register-origin
model: is_predictable_loop_dictator, is_non_predictable_loop_dictator,
is_reg_null, mod1_type, modified. This fork's analyzer is a rewrite that refuses
only on parse failures, and the emitter is switched off on Android because it
corrupted BLUS30161.

Restoring upstream's refusals means restoring whatever part of the model they
read. This prints both structs so the gap is exact rather than estimated.

Usage:
  python tools/diff_reg_state.py [path-to-upstream-checkout]
"""
import difflib
import io
import os
import subprocess
import sys

HEADER_REL = 'rpcs3/Emu/Cell/SPURecompiler.h'
FORK = 'app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPURecompiler.h'
DEFAULT_UPSTREAM = os.path.join('..', 'rpcs3-upstream')
NL = chr(10)


def upstream_header(checkout):
    out = subprocess.run(['git', '-C', checkout, 'show', 'origin/master:' + HEADER_REL],
                         capture_output=True)
    if out.returncode != 0:
        raise SystemExit('cannot read upstream header: ' + out.stderr.decode('utf-8', 'replace')[:200])
    return out.stdout.decode('utf-8', 'replace')


def extract(text, marker):
    """The struct body, from its declaration to the closing brace at tab depth 1."""
    i = text.find(marker)
    if i < 0:
        return None
    end = text.find(NL + chr(9) + '};', i)
    return text[i:end] if end > i else text[i:i + 6000]


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

    checkout = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_UPSTREAM
    up = extract(upstream_header(checkout), 'struct reg_state_t')
    ours = extract(io.open(FORK, encoding='utf-8', errors='replace').read(), 'struct reg_state_t')

    if up is None or ours is None:
        raise SystemExit('reg_state_t not found in one of the trees')

    print('upstream reg_state_t: %d lines' % up.count(NL))
    print('fork     reg_state_t: %d lines' % ours.count(NL))
    print()

    # Members and methods on each side, so the gap is nameable.
    def names(body):
        out = set()
        for line in body.split(NL):
            t = line.strip()
            if t.startswith('//') or not t:
                continue
            if '(' in t and (' ' in t.split('(')[0]):
                out.add(t.split('(')[0].split()[-1].lstrip('*&'))
            elif t.endswith(';') and ' ' in t:
                out.add(t.rstrip(';').split()[-1].split('{')[0].lstrip('*&'))
        return out

    up_n, our_n = names(up), names(ours)
    missing = sorted(up_n - our_n)
    extra = sorted(our_n - up_n)

    print('in upstream and NOT here (%d):' % len(missing))
    for n in missing:
        print('  - ' + n)
    print()
    print('here and not upstream (%d):' % len(extra))
    for n in extra:
        print('  + ' + n)
    print()

    print('unified diff:')
    print('-' * 90)
    for line in difflib.unified_diff(ours.split(NL), up.split(NL),
                                     'fork', 'upstream', lineterm='', n=2):
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
