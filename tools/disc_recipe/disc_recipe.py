"""Make a smaller PS3 disc image by removing data the owner does not use (a "recipe").

A recipe is a JSON file in recipes/, one per title. It names the source dump by its data
SHA-1 and lists operations on the ISO 9660 file system:

  redirect  For each file that matches "from", point the file named by "to" at the same
            data. The old data of the "to" file becomes zeros. Use it for an undub: the
            English voice file then plays the Japanese voice data.
  blank     Write zeros over the data of each matching file. The directory entry stays,
            so a game that opens the file still finds it.

The directory structure and every file offset stay the same. CHD stores a hunk of zeros
once, so zeros cost almost nothing in the output CHD. The core reads the Joliet tree when
the disc has one, else the primary tree (rpcs3/dev/iso.cpp); this tool changes both. It
does not change the UDF tree.

Usage:
  python disc_recipe.py list IMAGE [GLOB]           files, sector and size (ISO or CHD)
  python disc_recipe.py apply RECIPE IMAGE [OUT]     [--skip ID,ID] [--keep-iso]

OUT is a .chd path or a folder. Without OUT, the output goes next to IMAGE. In a folder, the
file takes the recipe's "outputName", which says what the image holds, for example
"(Ja voice, En text)".

The language rule for recipes is in AGENTS.md, section "Compile heat and CHD images".
"""
import argparse
import fnmatch
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

SECTOR = 2048
CHDMAN = os.environ.get("CHDMAN", r"F:\Projects\ps3-thor\_tools\mame0289\chdman.exe")


class Record:
    """One directory record of one file in one tree."""

    def __init__(self, tree, offset, path, lba, size, flags):
        self.tree = tree
        self.offset = offset  # byte offset of the record in the image
        self.path = path
        self.lba = lba
        self.size = size
        self.flags = flags

    def sectors(self):
        return range(self.lba, self.lba + (self.size + SECTOR - 1) // SECTOR)


def le32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def read_at(f, offset, size):
    f.seek(offset)
    return f.read(size)


def decode_name(raw, joliet):
    name = raw.decode("utf-16-be", "replace") if joliet else raw.decode("ascii", "replace")
    name = name.split(";", 1)[0]
    return name[:-1] if name.endswith(".") else name


def walk(f, tree, joliet, lba, size, prefix, files, seen):
    if lba in seen:
        return
    seen.add(lba)
    data = read_at(f, lba * SECTOR, size)
    pos = 0
    while pos < len(data):
        length = data[pos]
        if length == 0:
            pos = (pos // SECTOR + 1) * SECTOR  # records do not cross a sector end
            continue
        rec = data[pos:pos + length]
        name_len = rec[32]
        raw = rec[33:33 + name_len]
        if raw not in (b"\x00", b"\x01"):
            name = decode_name(raw, joliet)
            path = f"{prefix}{name}"
            rlba, rsize, flags = le32(rec, 2), le32(rec, 10), rec[25]
            if flags & 0x02:
                walk(f, tree, joliet, rlba, rsize, path + "/", files, seen)
            else:
                files.setdefault(path.upper(), []).append(
                    Record(tree, lba * SECTOR + pos, path, rlba, rsize, flags))
        pos += length


def read_trees(f):
    """Return {tree name: {UPPER PATH: [Record, ...]}}; more than one record is a multi-extent file."""
    trees = {}
    for sector in range(16, 64):
        vd = read_at(f, sector * SECTOR, SECTOR)
        if vd[1:6] != b"CD001" or vd[0] == 255:
            break
        joliet = vd[0] == 2 and vd[88:91] in (b"%/@", b"%/C", b"%/E")
        if vd[0] == 1 or joliet:
            name = "joliet" if joliet else "primary"
            root = vd[156:156 + 34]
            files = {}
            walk(f, name, joliet, le32(root, 2), le32(root, 10), "", files, set())
            trees[name] = files
    if not trees:
        sys.exit("not an ISO 9660 image")
    return trees


def core_tree(trees):
    return trees.get("joliet") or trees["primary"]


def run(cmd):
    print("+", " ".join(f'"{c}"' if " " in c else c for c in cmd), flush=True)
    subprocess.run(cmd, check=True, stdin=subprocess.DEVNULL)


def chd_info(path):
    out = subprocess.run([CHDMAN, "info", "-i", path], capture_output=True, text=True, check=True).stdout
    info = dict(re.findall(r"^([A-Za-z0-9 ]+):\s+(.*)$", out, re.M))
    return info["Data SHA1"].strip(), int(info["Logical size"].replace(",", "").split()[0])


def iso_sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 24):
            h.update(chunk)
    return h.hexdigest()


def to_iso(image, workdir):
    """Return a writable ISO copy of IMAGE in WORKDIR, and the source data SHA-1 and size."""
    out = os.path.join(workdir, "work.iso")
    if image.lower().endswith(".chd"):
        sha1, size = chd_info(image)
        run([CHDMAN, "extractdvd", "-i", image, "-o", out, "-f"])
    else:
        sha1, size = iso_sha1(image), os.path.getsize(image)
        shutil.copyfile(image, out)
    return out, sha1, size


def cmd_list(args):
    with tempfile.TemporaryDirectory(dir=args.workdir) as tmp:
        iso = args.image
        if iso.lower().endswith(".chd"):
            iso = os.path.join(tmp, "list.iso")
            run([CHDMAN, "extractdvd", "-i", args.image, "-o", iso, "-f"])
        with open(iso, "rb") as f:
            files = core_tree(read_trees(f))
    pattern = (args.glob or "*").upper()
    for key in sorted(files):
        if fnmatch.fnmatchcase(key, pattern):
            recs = files[key]
            print(f"{recs[0].lba:10d} {sum(r.size for r in recs):12d}  {recs[0].path}")


def match(files, pattern):
    """Paths that match PATTERN; each "/"-part matches one folder level, so "*" stays in its folder."""
    parts = pattern.upper().split("/")
    return sorted(k for k in files
                  if len(k.split("/")) == len(parts)
                  and all(fnmatch.fnmatchcase(a, b) for a, b in zip(k.split("/"), parts)))


def plan(recipe, trees, skip):
    """Return (record patches, zero ranges, report lines). Nothing is written here."""
    ref = core_tree(trees)
    # The trees can name a file differently (the primary tree can hold shortened names), so
    # the records of one file are found by their first data sector.
    by_lba = {}
    for files in trees.values():
        for recs in files.values():
            for rec in recs:
                by_lba.setdefault(rec.lba, []).append(rec)
    patches = []  # (Record, new lba, new size)
    zero = []  # (lba, size)
    blanked = set()  # first sectors of files whose records keep pointing at zeroed data
    report = []
    for op in recipe["ops"]:
        if op["id"] in skip:
            report.append(f"{op['id']}: skipped")
            continue
        count = total = 0
        if op["op"] == "redirect":
            for src_key in match(ref, op["from"]):
                src = ref[src_key]
                name = src[0].path.rsplit("/", 1)[1]
                dst_key = op["to"].format(name=name).upper()
                if dst_key not in ref:
                    report.append(f"{op['id']}: no target for {src[0].path}, kept as is")
                    continue
                dst = ref[dst_key]
                if len(src) != 1 or len(dst) != 1:
                    sys.exit(f"{op['id']}: multi-extent file, not supported: {src[0].path}")
                for rec in by_lba[dst[0].lba]:
                    patches.append((rec, src[0].lba, src[0].size))
                zero.append((dst[0].lba, dst[0].size))
                count += 1
                total += dst[0].size
        elif op["op"] == "blank":
            for pattern in op["paths"]:
                for key in match(ref, pattern):
                    for rec in ref[key]:
                        zero.append((rec.lba, rec.size))
                        total += rec.size
                        blanked.add(rec.lba)
                    count += 1
        else:
            sys.exit(f"unknown op {op['op']}")
        report.append(f"{op['id']}: {op['op']} {count} files, {total / 1e6:.1f} MB to zeros")

    # No zero range may hold data that a record still reads after the patches.
    patched = {id(rec): (lba, size) for rec, lba, size in patches}
    zero_sectors = set()
    for lba, size in zero:
        zero_sectors.update(range(lba, lba + (size + SECTOR - 1) // SECTOR))
    for files in trees.values():
        for recs in files.values():
            for rec in recs:
                if rec.lba in blanked and id(rec) not in patched:
                    continue
                lba, size = patched.get(id(rec), (rec.lba, rec.size))
                live = range(lba, lba + (size + SECTOR - 1) // SECTOR)
                if any(s in zero_sectors for s in live):
                    sys.exit(f"refused: {rec.path} ({rec.tree}) still reads data that would become zeros")
    return patches, zero, report


def write_plan(iso, patches, zero):
    with open(iso, "r+b") as f:
        for rec, lba, size in patches:
            f.seek(rec.offset + 2)
            f.write(struct.pack("<I", lba) + struct.pack(">I", lba) + struct.pack("<I", size) + struct.pack(">I", size))
        block = bytes(1 << 20)
        for lba, size in zero:
            f.seek(lba * SECTOR)
            left = (size + SECTOR - 1) // SECTOR * SECTOR
            while left:
                n = min(left, len(block))
                f.write(block[:n])
                left -= n


def check_result(iso, patches):
    """Read the trees again: each patched file must now read its new data."""
    with open(iso, "rb") as f:
        trees = read_trees(f)
    by_offset = {r.offset: r for files in trees.values() for recs in files.values() for r in recs}
    for rec, lba, size in patches:
        now = by_offset[rec.offset]
        if (now.lba, now.size) != (lba, size):
            sys.exit(f"check failed: {rec.path} ({rec.tree}) reads {now.lba}/{now.size}, want {lba}/{size}")


def cmd_apply(args):
    recipe = json.load(open(args.recipe, encoding="utf-8"))
    skip = set(filter(None, (args.skip or "").split(",")))
    unknown = skip - {op["id"] for op in recipe["ops"]}
    if unknown:
        sys.exit(f"unknown op id: {', '.join(sorted(unknown))}")
    out = args.out or os.path.dirname(os.path.abspath(args.image))
    if os.path.isdir(out):
        out = os.path.join(out, recipe["outputName"])
    if os.path.abspath(out) == os.path.abspath(args.image):
        sys.exit("refused: the output would overwrite the source")
    os.makedirs(args.workdir, exist_ok=True)
    tmp = tempfile.mkdtemp(dir=args.workdir)
    iso, sha1, size = to_iso(args.image, tmp)
    want = recipe["source"]
    if (sha1, size) != (want["dataSha1"], want["bytes"]):
        sys.exit(f"refused: source is {sha1} / {size} bytes, the recipe is for {want['dataSha1']} / {want['bytes']}")

    with open(iso, "rb") as f:
        trees = read_trees(f)
    patches, zero, report = plan(recipe, trees, skip)
    for line in report:
        print(line)
    write_plan(iso, patches, zero)
    check_result(iso, patches)

    run([CHDMAN, "createdvd", "-i", iso, "-o", out, "-c", "zstd", "-f"])
    run([CHDMAN, "verify", "-i", out])
    result_sha1, _ = chd_info(out)
    before = os.path.getsize(args.image)
    after = os.path.getsize(out)
    print(out)
    print(f"source {before / 1e9:.2f} GB, output {after / 1e9:.2f} GB, "
          f"saved {(before - after) / 1e9:.2f} GB; output data SHA-1 {result_sha1}")
    if args.keep_iso:
        print(f"kept {iso}")
    else:
        shutil.rmtree(tmp)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument("--workdir", default=r"F:\Projects\ps3-thor\_chd_work\recipe", help="temporary ISO copies go here")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("list")
    a.add_argument("image")
    a.add_argument("glob", nargs="?")
    b = sub.add_parser("apply")
    b.add_argument("recipe")
    b.add_argument("image")
    b.add_argument("out", nargs="?", help="output .chd path or folder (default: next to the source)")
    b.add_argument("--skip", help="comma-separated op ids to leave out")
    b.add_argument("--keep-iso", action="store_true")
    args = p.parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    {"list": cmd_list, "apply": cmd_apply}[args.cmd](args)


if __name__ == "__main__":
    main()
