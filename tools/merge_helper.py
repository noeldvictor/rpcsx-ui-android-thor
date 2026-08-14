"""Inspect and resolve conflicts in a merge-file output.

Built for the reduced-loop re-sync: our SPU analyzer is a partial back-port of
upstream's reduced loop onto a 2026-02-24 base, and finishing it means a
three-way merge with 37 conflicts across two files.

  python tools/merge_helper.py list   MERGED
  python tools/merge_helper.py show   MERGED N
  python tools/merge_helper.py resolve MERGED N ours|theirs|both
  python tools/merge_helper.py check  MERGED

`both` keeps ours then theirs, which is right when each side added something
independent and neither supersedes the other.

Resolutions are applied in place, so keep the file in a scratch directory until
it compiles. Never resolve by picking a side wholesale without reading it: two of
these conflicts are independent redesigns of the same interface, where either
choice alone silently breaks the other side's callers.
"""
import io
import sys

NL = chr(10)


def load(path):
    return io.open(path, encoding='utf-8', errors='replace').read().split(NL)


def save(path, lines):
    io.open(path, 'w', encoding='utf-8', errors='replace', newline=NL).write(NL.join(lines))


def conflicts(lines):
    """[(start, mid, end)] indices of <<<<<<< , ======= , >>>>>>>."""
    out = []
    start = mid = None
    for i, l in enumerate(lines):
        if l.startswith('<<<<<<<'):
            start, mid = i, None
        elif l.startswith('=======') and start is not None and mid is None:
            mid = i
        elif l.startswith('>>>>>>>') and start is not None and mid is not None:
            out.append((start, mid, i))
            start = mid = None
    return out


def first_code(block):
    for l in block:
        t = l.strip()
        if t and not t.startswith('//'):
            return t[:76]
    return '(comments or blank only)'


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

    if len(sys.argv) < 3:
        raise SystemExit(__doc__)

    cmd, path = sys.argv[1], sys.argv[2]
    lines = load(path)
    cs = conflicts(lines)

    if cmd == 'list':
        print('%d conflict(s) in %s' % (len(cs), path))
        for n, (a, m, b) in enumerate(cs, 1):
            ours, theirs = lines[a + 1:m], lines[m + 1:b]
            print('%3d  line %-6d ours %-4d theirs %-4d' % (n, a + 1, len(ours), len(theirs)))
            print('       ours  : ' + first_code(ours))
            print('       theirs: ' + first_code(theirs))
        return 0

    if cmd == 'check':
        print('%d unresolved conflict(s)' % len(cs))
        return 1 if cs else 0

    n = int(sys.argv[3])
    if not 1 <= n <= len(cs):
        raise SystemExit('conflict %d out of range (1..%d)' % (n, len(cs)))
    a, m, b = cs[n - 1]

    if cmd == 'show':
        print('=== conflict %d, line %d ===' % (n, a + 1))
        print('--- OURS (%d lines) ---' % (m - a - 1))
        for l in lines[a + 1:m]:
            print('  ' + l)
        print('--- THEIRS (%d lines) ---' % (b - m - 1))
        for l in lines[m + 1:b]:
            print('  ' + l)
        return 0

    if cmd == 'resolve':
        which = sys.argv[4]
        ours, theirs = lines[a + 1:m], lines[m + 1:b]
        if which == 'ours':
            repl = ours
        elif which == 'theirs':
            repl = theirs
        elif which == 'both':
            repl = ours + theirs
        else:
            raise SystemExit('resolve with ours, theirs or both')
        save(path, lines[:a] + repl + lines[b + 1:])
        print('conflict %d resolved as %s; %d left' %
              (n, which, len(conflicts(load(path)))))
        return 0

    raise SystemExit(__doc__)


if __name__ == '__main__':
    sys.exit(main())
