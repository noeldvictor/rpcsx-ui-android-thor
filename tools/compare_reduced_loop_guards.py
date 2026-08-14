"""Compare upstream's reduced-loop refusals against this fork's analyzer.

Why
---
Upstream's Reduced Loop is its Cell breakthrough, measured at 5-7% average FPS on
an SPU-heavy title. It is switched off on Android here, because the fork's own
analyzer rewrite corrupted BLUS30161 at a fixed SPU PC.

The two trees refuse differently. Upstream calls `break_reduced_loop_pattern(N, ...)`
when the analyzer declines to transform a loop it cannot prove safe. This fork
rewrote the analyzer and refuses by returning an empty `std::optional` instead.

**So the comparison has to be made by behaviour, not by identifier.** Two upstream
fixes were nearly recorded as missing from this tree purely because the names
differ (`needs_runtime_verify` against `is_cond_need_runtime_verify`). This script
prints both sets of conditions so they can be mapped one to one.

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
NEWLINE = chr(10)
TAB = chr(9)


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def upstream_text(checkout):
    try:
        out = subprocess.run(
            ['git', '-C', checkout, 'show', 'origin/master:' + UPSTREAM_REL],
            capture_output=True, check=True)
        return out.stdout.decode('utf-8', errors='replace')
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print('cannot read upstream ' + UPSTREAM_REL + ' from ' + checkout + ': ' + str(exc))
        return None


def reason_near(lines, idx, back=7):
    """Nearest preceding comment or `if`, as a hint at what is refused."""
    for j in range(idx - 1, max(-1, idx - back), -1):
        t = lines[j].strip()
        if t.startswith('//') and len(t) > 3:
            return t[2:].strip()
        if t.startswith('if ') or t.startswith('if('):
            return t[:100]
    return '(no comment or condition found)'


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

    checkout = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_UPSTREAM

    up = upstream_text(checkout)
    if up is None:
        return 1
    if not os.path.exists(FORK):
        print('missing ' + FORK)
        return 1
    fork = read(FORK)

    up_lines = up.split(NEWLINE)
    up_calls = [(m.group(1), up[:m.start()].count(NEWLINE)) for m in CALL.finditer(up)]
    fork_named = len(CALL.findall(fork))

    print('upstream named refusals: %d' % len(up_calls))
    print('fork named refusals:     %d' % fork_named)
    print()
    print('UPSTREAM refuses on these, by id:')
    print('-' * 96)

    seen = {}
    for ident, line_no in up_calls:
        seen.setdefault(ident, []).append(reason_near(up_lines, line_no))

    for ident in sorted(seen, key=lambda v: int(v)):
        print('%4s  x%-2d  %s' % (ident, len(seen[ident]), seen[ident][0][:82]))

    # The fork's refusals are `return {}` inside make_reduced_loop_pattern.
    print()
    print('THIS FORK refuses by `return {}` in make_reduced_loop_pattern:')
    print('-' * 96)

    marker = 'make_reduced_loop_pattern'
    end_marker = NEWLINE + TAB + '};'
    if marker not in fork:
        print('  (could not locate ' + marker + ')')
    else:
        start = fork.index(marker)
        end = fork.find(end_marker, start)
        if end == -1:
            end = start + 40000
        body = fork[start:end]
        base = fork[:start].count(NEWLINE) + 1
        lines = body.split(NEWLINE)
        n = 0
        for idx, line in enumerate(lines):
            if 'return {};' not in line:
                continue
            n += 1
            print('%6d  %s' % (base + idx, reason_near(lines, idx)[:82]))
        print()
        print('  %d refusal path(s) in %s' % (n, marker))

    print()
    print('Map the two lists by behaviour. Upstream ids with no counterpart above')
    print('are loop shapes this fork would transform and upstream would not, which')
    print('is the likely source of the BLUS30161 corruption that disabled the')
    print('emitter on Android. Identifiers differ between the trees; do not match')
    print('on names.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
