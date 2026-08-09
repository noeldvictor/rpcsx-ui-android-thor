"""Pin the lv2 PPU wait spin budget: all eight sites, the default, and the hoist.

A symbolized profile put 73.9% of all CPU cycles in two of these loops
(docs/arm64/lv2-ppu-spin.md). The loop is duplicated across every blocking lv2
primitive, so the failure mode is not "the change was wrong" but "the change
reached seven of eight sites and the eighth kept spinning". A grep is enough to
catch that, and it costs nothing next to a 14-minute build and a device run.

Four things are asserted, each because getting it wrong is silent:

1. **Every site reads the budget.** Eight loops, one missed, no symptom except a
   measurement that says the change did less than it should.
2. **No site still hardcodes any literal bound.** Matched by shape, not by the
   number: the first pass grepped for `i < 50`, fixed the eight sites that used
   it, and missed `sys_mutex.cpp`, which spelled the same loop `i < 40`.
3. **The default is 0.** It was 50 while the change was an experiment. It is 0
   now that four alternating gameplay arms showed p50/p95/p99 frame time within
   0.02 ms of the spinning build -- so this assertion pins the shipped decision,
   not the experimental one.
4. **The read is hoisted out of the loop.** `ppu_spin_iters()` holds a
   function-local static, which costs a guard-variable acquire load on every
   call. Putting one *inside* a spin is a mistake this fork already made once,
   with `get_thor_pause_mode` -- see the comment on `pause()` in rx/asm.hpp.

Usage:  python tools/test_thor_lv2_spin_sites.py
Exit 1 on any failure.
"""
import io
import os
import re
import sys

SRC = 'app/src/main/cpp/rpcsx/kernel/cellos/src'
HEADER = 'app/src/main/cpp/rpcsx/kernel/cellos/include/cellos/thor_ppu_wait.h'

# file -> number of wait loops it contains
SITES = {
    'sys_cond.cpp': 1,
    'sys_event.cpp': 1,
    'sys_event_flag.cpp': 1,
    'sys_lwcond.cpp': 1,
    'sys_lwmutex.cpp': 1,
    'sys_mutex.cpp': 1,
    'sys_rwlock.cpp': 2,
    'sys_semaphore.cpp': 1,
}

LOOP = re.compile(
    r'for \(usz i = 0; cpu_flag::signal - ppu\.state && i < thor_spin_iters; i\+\+\)')
# Match the SHAPE, with any literal -- not `i < 50`. The first version of this
# check hardcoded 50, and the sweep that fed it grepped for 50 too. Eight sites
# matched and were fixed; `sys_mutex.cpp` used `i < 40` and was silently missed,
# in the single most fundamental guest mutex. Same failure this repo keeps
# recording: a search for the wrong literal and a search that finds nothing look
# identical. The constant was never the invariant; the loop is.
HARDCODED = re.compile(
    r'for \(usz i = 0; cpu_flag::signal - ppu\.state && i < \d+; i\+\+\)')
HOIST = re.compile(r'const usz thor_spin_iters = thor::ppu_spin_iters\(\);')


def read(path):
    return io.open(path, encoding='utf-8', errors='replace').read()


def main():
    failures = []

    if not os.path.exists(HEADER):
        print(f'FAIL missing {HEADER}')
        return 1

    header = read(HEADER)
    if 'return 0;' not in header:
        failures.append(f'{HEADER}: default spin budget is not 0')
    if 'debug.rpcsx.thor.lv2_spin' not in header:
        failures.append(f'{HEADER}: property name missing')

    total = 0
    for name, expected in SITES.items():
        path = os.path.join(SRC, name)
        if not os.path.exists(path):
            failures.append(f'{path}: does not exist')
            continue

        text = read(path)
        loops = len(LOOP.findall(text))
        hoists = len(HOIST.findall(text))
        stale = len(HARDCODED.findall(text))
        total += loops

        if loops != expected:
            failures.append(
                f'{name}: {loops} gated loop(s), expected {expected}')
        if stale:
            failures.append(
                f'{name}: {stale} loop(s) still hardcode a literal bound')
        if hoists != expected:
            failures.append(
                f'{name}: {hoists} hoisted read(s), expected {expected} '
                '-- the static must be read once per wait, not per iteration')
        if 'cellos/thor_ppu_wait.h' not in text:
            failures.append(f'{name}: missing #include "cellos/thor_ppu_wait.h"')

        # The hoist must precede the loop it feeds, in every occurrence.
        for m in LOOP.finditer(text):
            before = text[:m.start()]
            if not HOIST.search(before):
                failures.append(
                    f'{name}: a gated loop appears before any hoisted read')
                break

    for f in failures:
        print(f'FAIL {f}')

    print(f'{len(SITES)} files, {total} gated wait loop(s), '
          f'{len(failures)} failure(s)')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
