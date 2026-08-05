#!/usr/bin/env python3
"""Match the games installed on a Thor against the bundled cheat database.

Answers one question per game: can I actually turn cheats on for this, and if
not, what is blocking it?

Three states are possible:

  READY       RPCS3-style patches with real PPU hashes exist. Selectable now.
  NEEDS-HASH  Cheats exist but carry no PPU hash. RPCSX learns the hash by
              running the game once; until then the app cannot write a patch
              file and the entries stay unselectable. Artemis/Aldos codes are
              always in this state until converted.
  NO-CHEATS   Nothing in the database for this title id.

"ACTIVE" in the last column means a generated patch file already exists on the
device for that title, i.e. the hash step completed at some point.

Usage:
    python tools/match_thor_cheats.py                  # read games from device
    python tools/match_thor_cheats.py --titles BLUS30161 BCUS98147
    python tools/match_thor_cheats.py --missing-only   # only what needs work
"""

import argparse
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO / "app/src/main/assets/cheats/cheats.db"
DEVICE_ROOT = "/sdcard/Android/data/net.rpcsx.easy/files"
TITLE_ID_RE = re.compile(r"^[A-Z]{4}\d{5}$")


def adb(serial, *args):
    cmd = ["adb"] + (["-s", serial] if serial else []) + list(args)
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        raise SystemExit(f"adb failed: {exc}")
    return out.stdout.replace("\r", "")


def device_title_ids(serial):
    """Title ids that have a compiled-cache directory, i.e. have been booted."""
    listing = adb(serial, "shell", f"ls {DEVICE_ROOT}/cache/cache/ 2>/dev/null")
    ids = sorted({ln.strip() for ln in listing.splitlines() if TITLE_ID_RE.match(ln.strip())})
    if not ids:
        raise SystemExit(
            "No title ids found on device. Pass --titles explicitly, or check "
            "that the device is connected and games have been launched once."
        )
    return ids


def device_patch_files(serial):
    listing = adb(serial, "shell", f"ls {DEVICE_ROOT}/config/patches/ 2>/dev/null")
    out = set()
    for line in listing.splitlines():
        m = re.match(r"^([A-Z]{4}\d{5})_patch\.yml$", line.strip())
        if m:
            out.add(m.group(1))
    return out


def inspect(conn, title_id):
    q = lambda sql, args=(): conn.execute(sql, args).fetchall()

    name_row = q("SELECT name FROM games WHERE title_id=? LIMIT 1", (title_id,))
    name = name_row[0][0] if name_row else ""

    gids = [r[0] for r in q(
        "SELECT group_id FROM cheat_group_title_ids WHERE title_id=?", (title_id,))]
    if not gids:
        return {"title_id": title_id, "name": name, "state": "NO-CHEATS",
                "groups": 0, "codes": 0, "hashed": 0, "sources": ""}

    ph = ",".join("?" * len(gids))

    codes = q(f"SELECT COALESCE(SUM(convertible_count),0) FROM cheat_groups "
              f"WHERE id IN ({ph})", gids)[0][0]

    hashed = q(f"SELECT COUNT(*) FROM patches WHERE hash IS NOT NULL AND hash!='' "
               f"AND cheat_id IN (SELECT id FROM cheats WHERE group_id IN ({ph}))",
               gids)[0][0]

    sources = ", ".join(sorted({
        r[0] for r in q(f"SELECT s.name FROM cheat_groups g "
                        f"JOIN sources s ON s.id=g.source_id WHERE g.id IN ({ph})", gids)
    }))

    state = "READY" if hashed else "NEEDS-HASH"
    return {"title_id": title_id, "name": name, "state": state, "groups": len(gids),
            "codes": codes, "hashed": hashed, "sources": sources}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--serial", default="", help="adb serial (needed if several devices)")
    ap.add_argument("--db", type=Path, default=DEFAULT_DB, help="path to cheats.db")
    ap.add_argument("--titles", nargs="*", metavar="TITLEID",
                    help="check these title ids instead of reading the device")
    ap.add_argument("--missing-only", action="store_true",
                    help="hide games that are already READY")
    args = ap.parse_args()

    if not args.db.is_file():
        raise SystemExit(f"cheat database not found: {args.db}\n"
                         f"Build it with: python tools/build_cheat_db.py")

    if args.titles:
        titles, active = sorted(set(args.titles)), set()
    else:
        titles = device_title_ids(args.serial)
        active = device_patch_files(args.serial)

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    rows = [inspect(conn, t) for t in titles]
    if args.missing_only:
        rows = [r for r in rows if r["state"] != "READY"]

    if not rows:
        print("Nothing to report.")
        return 0

    print(f"{'TITLE ID':<11}{'STATE':<12}{'CODES':>6}{'HASHED':>7}  {'ON':<3} GAME")
    print("-" * 78)
    for r in rows:
        flag = "yes" if r["title_id"] in active else "-"
        print(f"{r['title_id']:<11}{r['state']:<12}{r['codes']:>6}{r['hashed']:>7}"
              f"  {flag:<3} {r['name'][:34]}")

    need = [r for r in rows if r["state"] == "NEEDS-HASH" and r["title_id"] not in active]
    none = [r for r in rows if r["state"] == "NO-CHEATS"]
    ready = [r for r in rows if r["state"] == "READY"]

    print()
    print(f"Summary: {len(ready)} ready, {len(need)} awaiting a PPU hash, "
          f"{len(none)} with no cheats in the database.")

    if need:
        print()
        print("To unlock these, launch each game once, close it, then reopen the")
        print("Cheats page so RPCSX can record the PPU hash:")
        for r in need:
            print(f"  {r['title_id']}  {r['name'][:40]}")

    if none:
        print()
        print("No database entries at all. These need importing, ideally from an")
        print("RPCS3 patch source since those ship with PPU hashes already:")
        for r in none:
            print(f"  {r['title_id']}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
