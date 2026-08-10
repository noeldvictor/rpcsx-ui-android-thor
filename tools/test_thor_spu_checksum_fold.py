"""Fail if the SPU checksum folds vector pairs with an absolute difference.

Why this test exists
--------------------

The SPU recompiler verifies a cached compiled block against the guest code. It
does this with a checksum. The ARM64 path folded pairs of vectors with
`aarch64_neon_uabd`, which computes `|a - b|`.

An absolute difference is not injective. `|a - b|` does not change when you add
the same constant to both words. It also does not change when you swap the two
words. Two different job binaries can therefore produce the same checksum. When
they do, verification passes and the emulator runs one job's compiled block
against another job's code.

The defect is in upstream RPCS3. Our fork inherited it. ARMSX3 fixed it first.
We fixed it on 2026-08-10 and confirmed the fix on device: `uaba` went from 4,503
to 0 and `uabd` went from 910 to 0 in the compiled cache for Eternal Sonata.

Why a test and not a comment
----------------------------

**Upstream is still broken.** Any future merge from upstream can put the
absolute difference back. Nothing would fail. The emulator would still boot, and
the collision needs a specific pair of job binaries to appear. This is the same
shape as the `mov_rdata` defect, where a revert left an empty branch and two
titles stopped booting for several sessions.

The audit that examined this code called it exemplary. It read the instruction
selection, and the instruction selection was good. `UABA` is one instruction
where a sum needs two. The audit asked whether the code was fast. It did not ask
whether the algorithm was correct. A grep is a cheap second question.

Usage:  python tools/test_thor_spu_checksum_fold.py
Exit 1 on any failure.
"""
import io
import os
import re
import sys

TARGET = 'app/src/main/cpp/rpcsx/rpcs3/Emu/Cell/SPULLVMRecompiler.cpp'

# The host side computes the expected value. Both pair lanes must add.
HOST_PAIRS = (
    re.compile(r'checksum\[4 \+ i\]\s*\+=\s*words\[4 \+ i\]\s*\+\s*words\[8 \+ i\]'),
    re.compile(r'checksum\[12 \+ i\]\s*\+=\s*words\[16 \+ i\]\s*\+\s*words\[20 \+ i\]'),
)

# The emitted IR must add the same pairs. A nested CreateAdd is the sum form.
EMITTED_PAIRS = (
    re.compile(r'CreateAdd\(\s*next_acc\[1\]\s*,\s*m_ir->CreateAdd\(vls\[1\]\s*,\s*vls\[2\]\)'),
    re.compile(r'CreateAdd\(\s*next_acc\[3\]\s*,\s*m_ir->CreateAdd\(vls\[4\]\s*,\s*vls\[5\]\)'),
)

# The instruction that must never come back in this file.
FORBIDDEN = re.compile(r'aarch64_neon_uabd')


def main():
    if not os.path.exists(TARGET):
        print(f'FAIL missing {TARGET}')
        return 1

    text = io.open(TARGET, encoding='utf-8', errors='replace').read()
    failures = []

    hits = FORBIDDEN.findall(text)
    if hits:
        failures.append(
            f'{len(hits)} use(s) of aarch64_neon_uabd. The checksum must sum '
            'its pairs. An absolute difference is not injective.')

    for pattern in HOST_PAIRS:
        if not pattern.search(text):
            failures.append(f'host pair lane does not add: {pattern.pattern}')

    for pattern in EMITTED_PAIRS:
        if not pattern.search(text):
            failures.append(f'emitted pair lane does not add: {pattern.pattern}')

    for line in failures:
        print(f'FAIL {line}')

    print(f'checked {TARGET}, {len(failures)} failure(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
