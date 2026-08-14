"""Compare upstream's reduced-loop refusals against this fork's analyzer.

Why
---
Upstream's Reduced Loop is its Cell breakthrough, measured at 5-7% average FPS on
an SPU-heavy title. It is switched off on Android here, because the fork's own
analyzer rewrite corrupted BLUS30161.

`break_reduced_loop_pattern(N, ...)` is upstream's refusal path: the analyzer
declines to transform a loop it cannot prove safe. Upstream calls it at many
sites; this fork's rewrite calls it nowhere. This script lists what upstream
refuses, so each case can be checked against our analyzer **by behaviour rather
than by name** -- two upstream fixes were nearly recorded as missing here because
the identifiers differ.

Usage:
  python tools/compare_reduced_loop_guards.py [path-to-upstream-checkout]
"""
import io
import os
import re
import subprocess
import sys

FORK = 'app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPUCommonRecompiler.cpp'
UPSTREAM_REL = 'rpcs3/Emu/Cell/SPUCommonRecompiler.cpp'
DEFAULT_UPSTREAM = os.path.join('..', 'rpcs3-upstream')

CALL = re.compile(r'break_reduced_loop_pattern\(\s*(\d+)')


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def upstream_text(checkout):
    """Read the file from origin/master without needing a clean worktree."""
    try:
        out = subprocess.run(
            ['git', '-C', checkout, 'show', f'origin/master:{UPSTREAM_REL}'],
            capture_output=True, check=True)
        return out.stdout.decode('utf-8', errors='replace')
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f'cannot read upstream {UPSTREAM_REL} from {checkout}: {exc}')
        return None


def reason_for(text, pos):
    """The nearest preceding comment or condition, as a hint at what is refused."""
    head = text[:pos]
    lines = head.split('\n')
    # Walk back over the call's own line for a comment or an `if`.
    for line in reversed(lines[-6:]):
        s = line.strip()
        if s.startswith('//') and len(s) > 3:
            return s[2:].strip()
    for line in reversed(lines[-6:]):
        s = line.strip()
        if s.startswith('if ') or s.startswith('if('):
            return s[:110]
    return '(no comment or condition found)'


def main():
    checkout = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_UPSTREAM

    up = upstream_text(checkout)
    if up is None:
        return 1

    if not os.path.exists(FORK):
        print(f'missing {FORK}')
        return 1
    fork = read(FORK)

    up_calls = [(m.group(1), m.start()) for m in CALL.finditer(up)]
    fork_calls = [(m.group(1), m.start()) for m in CALL.finditer(fork)]

    print(f'upstream refusals: {len(up_calls)}')
    print(f'fork refusals:     {len(fork_calls)}')
    print()

    seen = {}
    for ident, pos in up_calls:
        seen.setdefault(ident, []).append(reason_for(up, pos))

    print(f'{"id":>4}  {"n":>2}  reason (nearest comment or condition)')
    print('-' * 96)
    for ident in sorted(seen, key=lambda v: int(v)):
        reasons = seen[ident]
        print(f'{ident:>4}  {len(reasons):>2}  {reasons[0][:88]}')

    print()
    if not fork_calls:
        print('This fork refuses NOTHING. Every pattern its analyzer builds is emitted.')
        print('Each id above is a loop shape upstream declines to transform; the fork')
        print('needs an equivalent check, or upstream\'s analyzer, before the emitter')
        print('can be enabled. Check by behaviour: names differ between the two trees.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
