"""Find the upstream commit a vendored file most closely descends from.

Why
---
The vendored core has no merge base with `RPCS3/rpcs3`: it came through RPCSX and
was then edited here, so `git merge-base` has nothing to say. A three-way merge
still needs a base, and the best available one is the upstream revision whose copy
of the file is closest to ours.

Dating it by `rpcs3_version.cpp` does not work either -- that constant says 0.0.36,
bumped in March 2025, while the tree demonstrably carries upstream work from July
2026. Content is the only reliable signal.

Usage:
  python tools/find_upstream_base.py rpcs3/Emu/Cell/SPUCommonRecompiler.cpp
  python tools/find_upstream_base.py rpcs3/Emu/Cell/SPURecompiler.h --since 2026-01-01

Prints the candidates ranked by diff size, smallest first. The winner is the base
to hand to `git merge-file`.
"""
import argparse
import io
import os
import subprocess
import sys
import tempfile

DEFAULT_UPSTREAM = os.path.join('..', 'rpcs3-upstream')
FORK_PREFIX = 'app/src/main/cpp/rpcsx/'
NL = chr(10)


def run(args, **kw):
    return subprocess.run(args, capture_output=True, **kw)


def upstream_commits(checkout, path, since, limit):
    out = run(['git', '-C', checkout, 'log', '--format=%H %ad %s', '--date=short',
               '--since', since, 'origin/master', '--', path])
    lines = out.stdout.decode('utf-8', 'replace').strip().split(NL)
    return [l for l in lines if l][:limit]


def blob(checkout, sha, path):
    out = run(['git', '-C', checkout, 'show', sha + ':' + path])
    return out.stdout if out.returncode == 0 else None


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument('path', help='path as upstream spells it, e.g. rpcs3/Emu/Cell/SPURecompiler.h')
    ap.add_argument('--upstream', default=DEFAULT_UPSTREAM)
    ap.add_argument('--since', default='2026-01-01')
    ap.add_argument('--limit', type=int, default=60)
    ap.add_argument('--top', type=int, default=8)
    args = ap.parse_args()

    fork_path = FORK_PREFIX + args.path
    if not os.path.exists(fork_path):
        raise SystemExit('missing ' + fork_path)
    ours = io.open(fork_path, 'rb').read()

    commits = upstream_commits(args.upstream, args.path, args.since, args.limit)
    if not commits:
        raise SystemExit('no upstream commits touch ' + args.path + ' since ' + args.since)

    print('fork file: %s (%d lines)' % (fork_path, ours.count(b'\n')))
    print('candidates: %d upstream revisions since %s' % (len(commits), args.since))
    print()

    scored = []
    with tempfile.TemporaryDirectory() as tmp:
        ours_f = os.path.join(tmp, 'ours')
        io.open(ours_f, 'wb').write(ours)

        for entry in commits:
            sha = entry.split()[0]
            data = blob(args.upstream, sha, args.path)
            if data is None:
                continue
            theirs_f = os.path.join(tmp, 'theirs')
            io.open(theirs_f, 'wb').write(data)
            d = run(['git', 'diff', '--no-index', '--numstat', ours_f, theirs_f])
            text = d.stdout.decode('utf-8', 'replace').strip()
            if not text:
                added = removed = 0
            else:
                parts = text.split(NL)[0].split()
                try:
                    added, removed = int(parts[0]), int(parts[1])
                except (ValueError, IndexError):
                    continue
            scored.append((added + removed, added, removed, entry))

    scored.sort(key=lambda r: r[0])

    print('%9s %8s %8s  commit' % ('total', 'added', 'removed'))
    print('-' * 92)
    for total, a, r, entry in scored[:args.top]:
        print('%9d %8d %8d  %s' % (total, a, r, entry[:78]))

    if scored:
        best = scored[0]
        print()
        print('closest upstream revision: ' + best[3].split()[0])
        print('hand that to git merge-file as the base:')
        print('  git show BASE:%s > /tmp/base' % args.path)
        print('  git -C %s show origin/master:%s > /tmp/theirs' % (args.upstream, args.path))
        print('  git merge-file %s /tmp/base /tmp/theirs' % fork_path)
        print()
        print('A large "total" for every candidate means the fork has diverged past')
        print('the point where a merge is the right tool; read the number before')
        print('trusting the merge.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
