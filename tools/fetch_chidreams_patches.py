#!/usr/bin/env python3
"""Fetch the Chidreams RPCS3 patch collection into the bundled cheat assets.

Why this matters: Artemis/Aldos codes carry no PPU hash, so RPCSX cannot write a
patch file for them until it has run the game once and learned the hash. Until
then the entries stay unselectable. Chidreams publishes the same code data
already converted to RPCS3 patch format *with* PPU hashes, so those entries are
usable immediately, with no hash-learning step.

Files land in app/src/main/assets/cheats/chidreams/<slug>/imported_patch.yml,
which is the layout add_chidreams() in build_cheat_db.py already walks. No
parser changes are needed; the upstream files are already in the expected
`PPU-<40 hex>:` block format with an `Anchors:` section.

After fetching, rebuild the database:

    python tools/build_chidreams_patches.py       # this script
    python tools/build_cheat_db.py

Usage:
    python tools/fetch_chidreams_patches.py
    python tools/fetch_chidreams_patches.py --dry-run
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = "chidreams/Artemis-Patch-Collection-RPCS3"
BRANCH = "main"
TREE_API = f"https://api.github.com/repos/{REPO}/git/trees/{BRANCH}?recursive=1"
RAW_BASE = f"https://raw.githubusercontent.com/{REPO}/{BRANCH}/"

REPO_ROOT = Path(__file__).resolve().parent.parent
DEST = REPO_ROOT / "app/src/main/assets/cheats/chidreams"

TITLE_ID_RE = re.compile(r"\b([A-Z]{4}\d{5})\b")
UA = {"User-Agent": "rpcsx-thor-cheat-fetch"}


def get(url, binary=False):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = resp.read()
    return data if binary else data.decode("utf-8", errors="replace")


def slug_for(path):
    """Stable directory name derived from title id where possible."""
    m = TITLE_ID_RE.search(path)
    stem = re.sub(r"[^A-Za-z0-9]+", "_", path).strip("_").lower()[:60]
    return f"{m.group(1)}_{stem}" if m else stem


def looks_like_patch(text):
    """Only keep files that actually carry a PPU hash block."""
    return re.search(r"^PPU-[0-9A-Fa-f]{40}:", text, re.MULTILINE) is not None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would be fetched without writing")
    ap.add_argument("--dest", type=Path, default=DEST)
    args = ap.parse_args()

    print(f"listing {REPO}@{BRANCH} ...")
    try:
        tree = json.loads(get(TREE_API))
    except urllib.error.URLError as exc:
        raise SystemExit(f"could not reach the GitHub API: {exc}")

    if tree.get("truncated"):
        print("warning: GitHub truncated the tree listing; some files may be missed")

    blobs = [e["path"] for e in tree.get("tree", []) if e.get("type") == "blob"]
    # Skip repo furniture; patch files are named "Game [TITLEID] vX.YZ".
    blobs = [p for p in blobs
             if not p.lower().endswith((".md", ".png", ".jpg", ".gitignore", ".txt"))]

    print(f"{len(blobs)} candidate files")
    if args.dry_run:
        for p in blobs[:15]:
            print("  ", p)
        if len(blobs) > 15:
            print(f"   ... and {len(blobs) - 15} more")
        return 0

    args.dest.mkdir(parents=True, exist_ok=True)

    written = skipped = failed = 0
    title_ids = set()

    for path in blobs:
        url = RAW_BASE + urllib.parse.quote(path)
        try:
            text = get(url)
        except Exception as exc:
            print(f"  FAIL {path[:60]}: {exc}")
            failed += 1
            continue

        if not looks_like_patch(text):
            skipped += 1
            continue

        out_dir = args.dest / slug_for(path)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "imported_patch.yml"

        # Skip rewrites so repeated runs stay quiet and git-clean.
        if out_file.exists() and out_file.read_text(encoding="utf-8", errors="replace") == text:
            continue

        out_file.write_text(text, encoding="utf-8")
        written += 1
        title_ids.update(TITLE_ID_RE.findall(text))

    print()
    print(f"written {written}, skipped {skipped} without a PPU hash, {failed} failed")
    print(f"distinct title ids seen in fetched files: {len(title_ids)}")
    print()
    print("Next: python tools/build_cheat_db.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
