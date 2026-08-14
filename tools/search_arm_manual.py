"""Search the vendored hardware manuals and print the surrounding text.

CLAUDE.md says to use the manuals and not to reason from memory about what the
chip does. They are also 17,145 pages for the Arm ARM alone, which is why they get
quoted second-hand instead of read. This makes them greppable.

Usage:
  python tools/search_arm_manual.py TERM [--doc arm|x3|a715|a710|a510|adreno|opencl]
                                        [--context N] [--max N]

  python tools/search_arm_manual.py "non-temporal" --doc arm --max 6
  python tools/search_arm_manual.py LDNP --doc arm

Extracted text is cached beside the PDF as .txt, because the Arm ARM takes a while
to convert. Requires pdftotext (poppler), which is on PATH here.
"""
import argparse
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HW = os.path.join(os.path.dirname(HERE), 'docs', 'hardware')

DOCS = {
    'arm': 'arm_architecture_reference_manual_DDI0487M_c.pdf',
    'x3': 'arm_cortex_x3_software_optimization_guide.pdf',
    'a715': 'arm_cortex_a715_software_optimization_guide.pdf',
    'a710': 'arm_cortex_a710_software_optimization_guide.pdf',
    'a510': 'arm_cortex_a510_software_optimization_guide.pdf',
    'adreno': 'qualcomm_adreno_game_developer_guide.pdf',
    'opencl': 'qualcomm_snapdragon_opencl_optimization_guide.pdf',
    'qclinux': 'qualcomm_linux_kernel_guide.pdf',
}


def text_for(key):
    pdf = os.path.join(HW, DOCS[key])
    if not os.path.exists(pdf):
        raise SystemExit(f'missing {pdf}. The Arm ARM is vendored in three parts; '
                         'run `sh docs/hardware/assemble_arm_arm.sh` first.')

    cache = pdf + '.txt'
    if not os.path.exists(cache) or os.path.getmtime(cache) < os.path.getmtime(pdf):
        sys.stderr.write(f'extracting {os.path.basename(pdf)} (once)...\n')
        sys.stderr.flush()
        r = subprocess.run(['pdftotext', '-layout', pdf, cache],
                           capture_output=True)
        if r.returncode != 0 or not os.path.exists(cache):
            raise SystemExit('pdftotext failed: ' + r.stderr.decode('utf-8', 'replace')[:300])

    return io.open(cache, encoding='utf-8', errors='replace').read()


def main():
    # The manuals carry glyphs cp1252 cannot encode, and the default Windows
    # console codec turns a successful search into a traceback halfway through
    # printing it.
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except AttributeError:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument('term')
    ap.add_argument('--doc', default='arm', choices=sorted(DOCS))
    ap.add_argument('--context', type=int, default=6, help='lines either side')
    ap.add_argument('--max', type=int, default=8, help='matches to print')
    ap.add_argument('--regex', action='store_true')
    args = ap.parse_args()

    text = text_for(args.doc)
    lines = text.split('\n')

    pat = re.compile(args.term if args.regex else re.escape(args.term), re.I)

    hits = [i for i, l in enumerate(lines) if pat.search(l)]
    print(f'{len(hits)} line(s) match {args.term!r} in {DOCS[args.doc]}')
    if not hits:
        # A zero from a search that searched nothing looks the same as a real zero.
        print(f'(the extracted text is {len(lines)} lines, so the search did run)')
        return 0

    shown = 0
    last_end = -1
    for i in hits:
        if shown >= args.max:
            print(f'... {len(hits) - shown} more match(es) not shown')
            break
        lo, hi = max(0, i - args.context), min(len(lines), i + args.context + 1)
        if lo <= last_end:
            continue
        print('\n' + '=' * 90)
        for j in range(lo, hi):
            mark = '>>' if j == i else '  '
            print(f'{mark} {lines[j].rstrip()}')
        last_end = hi
        shown += 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
