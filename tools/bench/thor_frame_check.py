#!/usr/bin/env python3
"""Decide whether the Thor is actually DRAWING, not just presenting.

Exists because on 2026-08-26 an HLE SPURS run reported 29.27 fps over a
completely black framebuffer, and the number was believed for days. The frame
counter counts presents, not content: a path that renders nothing still hits
the 30 cap and still reports a frame rate, so an fps sample is meaningless
until the frame behind it is known to contain a scene.

Usage:
    python thor_frame_check.py [--serial 192.168.1.3:5555] [--save out.png]

Exit status is the contract, so a harness can gate on it:
    0  frame is DRAWN         - the fps sample beside it may be reported
    1  frame is BLANK/BLACK   - discard the sample, nothing is being drawn
    2  could not decide    - no device, capture failed, missing Pillow

Thresholds come from measured captures on this device at 1920x1080:

    black frame (HLE SPURS)   98.5% near-black    162 distinct colours   29 KB
    combat gameplay           38.9%              16724                  2.2 MB
    menu / drawn UI           25.9%              29334                  1.9 MB

The two populations are three orders of magnitude apart in colour count, so the
cutoff does not need to be delicate. DISTINCT COLOUR COUNT IS THE PRIMARY
SIGNAL - not darkness. A legitimately dark scene (a night level, a fade) is
still full of distinct near-black values, while a blank framebuffer with an
overlay drawn on it has only the overlay's antialiasing ramp.
"""

import argparse
import collections
import os
import subprocess
import sys
import tempfile

# A drawn frame has thousands of distinct colours. The blank-plus-overlay case
# measured 162, and the lowest drawn frame measured 16724, so 1500 sits two
# orders of magnitude clear of the black population and ten times under the
# drawn one.
MIN_DISTINCT_COLOURS = 1500

# Secondary, and deliberately loose: a real scene CAN be very dark. This only
# fires together with a low colour count, never on its own.
MAX_NEAR_BLACK_FRACTION = 0.97
NEAR_BLACK_SUM = 40

# Sample a grid rather than every pixel - 300x300 is ~90k samples, plenty to
# separate 162 from 16724, and it keeps the check under a second.
GRID = 300


def capture(adb, serial, out_path):
    cmd = [adb]
    if serial:
        cmd += ["-s", serial]
    cmd += ["exec-out", "screencap", "-p"]
    try:
        png = subprocess.run(cmd, capture_output=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired) as exc:
        print("frame-check: capture failed: %s" % exc, file=sys.stderr)
        return None
    # exec-out avoids the CRLF mangling that plain `shell screencap` suffers on
    # some Windows adb builds; verify the magic rather than trusting it.
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        print("frame-check: capture is not a PNG (%d bytes)" % len(png), file=sys.stderr)
        return None
    with open(out_path, "wb") as handle:
        handle.write(png)
    return out_path


def score(path):
    from PIL import Image

    image = Image.open(path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    colours = collections.Counter()
    near_black = 0
    total = 0
    for y in range(0, height, max(1, height // GRID)):
        for x in range(0, width, max(1, width // GRID)):
            pixel = pixels[x, y]
            colours[pixel] += 1
            total += 1
            if sum(pixel) < NEAR_BLACK_SUM:
                near_black += 1
    return {
        "width": width,
        "height": height,
        "distinct": len(colours),
        "near_black": float(near_black) / total if total else 1.0,
        "bytes": os.path.getsize(path),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"))
    parser.add_argument("--serial", default=os.environ.get("THOR_SERIAL"))
    parser.add_argument("--save", help="keep the capture at this path")
    parser.add_argument("--image", help="score an existing PNG instead of capturing")
    args = parser.parse_args()

    try:
        import PIL  # noqa: F401
    except ImportError:
        print("frame-check: Pillow is required (pip install pillow)", file=sys.stderr)
        return 2

    if args.image:
        path, temporary = args.image, None
    else:
        path = args.save or os.path.join(tempfile.gettempdir(), "thor_frame_check.png")
        temporary = None if args.save else path
        if capture(args.adb, args.serial, path) is None:
            return 2

    try:
        result = score(path)
    except Exception as exc:                      # noqa: BLE001 - report, don't crash a harness
        print("frame-check: could not score %s: %s" % (path, exc), file=sys.stderr)
        return 2
    finally:
        if temporary and os.path.exists(temporary) and not args.save:
            pass  # leave it; a failed run is exactly when the image is wanted

    # DARKNESS IS NOT THE TEST - FLATNESS IS.
    #
    # This originally required a LOW colour count AND a high near-black
    # fraction, and that let a flat GREEN frame through as DRAWN: the emulator
    # was clearing the framebuffer and submitting no geometry, at 29 fps over
    # 2,945 frames, with distinct=148 and near_black=0.0%. The clear colour is
    # not always black, so keying on black was the wrong axis.
    #
    # A frame is UNDRAWN when it carries almost no distinct colours, whatever
    # those colours are. Darkness is kept only as a label, to say WHICH kind of
    # blank it is.
    blank = result["distinct"] < MIN_DISTINCT_COLOURS
    black = blank and result["near_black"] > MAX_NEAR_BLACK_FRACTION
    verdict = "BLACK" if black else ("BLANK" if blank else "DRAWN")
    print("frame-check: %s  %dx%d  distinct=%d  near-black=%.1f%%  %dKB  %s"
          % (verdict, result["width"], result["height"], result["distinct"],
             100.0 * result["near_black"], result["bytes"] // 1024, path))
    if blank:
        print("frame-check: DISCARD any fps sample taken with this frame - "
              "the path is presenting empty frames (%d distinct colours)."
              % result["distinct"], file=sys.stderr)
    return 1 if blank else 0


if __name__ == "__main__":
    sys.exit(main())
