"""Fail if any architecture #if/#elif branch contains only comments.

This exists because of one bug that cost several sessions. `mov_rdata` in
SPUThread.cpp -- the 128-byte copy every SPU reservation is validated against --
looked like this after an LDP/STP experiment was reverted:

    #elif defined(ARCH_ARM64) && defined(__clang__)
        // 22 lines of comment explaining the revert
    #else
        std::memcpy(_dst, _src, 128);
    #endif

The body was removed and the #elif was left standing, so on every ARM64 + clang
build the function copied nothing. rdata was never refreshed, cmp_rdata could
never match, and any SPU whose reservation line changed under it spun forever:
10,093,915 failed retries in a single Folklore boot. Two titles could not boot.

The revert was made *precautionarily*, to protect a correctness-sensitive copy
from an unproven change, and produced a far worse defect than the one it guarded
against. Removing a function body is a code change like any other.

The compiler did report it, on every build:

    SPUThread.cpp:1301:25: warning: unused parameter '_dst'
    SPUThread.cpp:1301:50: warning: unused parameter '_src'

Nobody read it, because the build prints hundreds of warnings. This check is the
cheap mechanical backstop for the case where nobody reads them again.

Usage:  python tools/check_empty_arch_branches.py [root]
Exit 1 if any empty branch is found.
"""
import io
import os
import re
import sys

SKIP_DIRS = ('3rdparty', 'llvm', '.git', 'build', '.cxx')
EXTENSIONS = ('.cpp', '.h', '.hpp', '.cc', '.c')
ARCH_RE = re.compile(r'\s*#(el)?if\b.*(ARCH_ARM64|__aarch64__|ARCH_X64|__x86_64__)')


def is_comment(line):
    s = line.strip()
    return s.startswith(('//', '*', '/*'))


def scan(path):
    """Yield (line_number, directive) for arch branches holding no code."""
    try:
        lines = io.open(path, encoding='utf-8', errors='replace').readlines()
    except OSError:
        return

    i = 0
    while i < len(lines):
        if not ARCH_RE.match(lines[i]):
            i += 1
            continue

        # Collect this branch's body, skipping over any nested conditionals so a
        # nested #else is not mistaken for the end of this branch.
        j = i + 1
        body = []
        depth = 0
        while j < len(lines):
            if re.match(r'\s*#if', lines[j]):
                depth += 1
            elif re.match(r'\s*#endif', lines[j]):
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and re.match(r'\s*#(elif|else)\b', lines[j]):
                break
            body.append(lines[j])
            j += 1

        if body and not any(b.strip() and not is_comment(b) for b in body):
            yield i + 1, lines[i].strip()

        i = j


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else 'app/src/main/cpp/rpcsx'
    findings = []
    scanned = 0

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(EXTENSIONS):
                continue
            path = os.path.join(dirpath, name)
            scanned += 1
            for line_no, directive in scan(path):
                findings.append((path, line_no, directive))

    for path, line_no, directive in findings:
        print(f'{path}:{line_no}: architecture branch contains no code')
        print(f'    {directive}')

    print(f'scanned {scanned} files, {len(findings)} empty architecture branch(es)')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
