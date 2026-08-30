#!/usr/bin/env python3
"""Check whether a Transformers startup frame can accept START.

The game shows a large block of neutral white legal text before it enters the
long black loading sequence. The loading screen has only a small symbol in the
lower-right corner. A controller can use this difference to send START before
the later zero-frame loading stall.

Exit status is the controller contract:

    0  the startup frame can accept START
    1  the startup frame is not ready
    2  the image could not be scored
"""

import argparse
import json
import sys


MIN_NEUTRAL_BRIGHT_FRACTION = 0.10
REGION_LEFT = 0.08
REGION_TOP = 0.52
REGION_RIGHT = 0.92
REGION_BOTTOM = 0.94


def score(path):
    """Return the measured legal-text fraction for one saved screenshot."""
    from PIL import Image

    image = Image.open(path).convert("RGB")
    width, height = image.size
    if width < 320 or height < 180:
        raise ValueError("the image is too small")

    region = image.crop(
        (
            int(REGION_LEFT * width),
            int(REGION_TOP * height),
            int(REGION_RIGHT * width),
            int(REGION_BOTTOM * height),
        )
    )
    pixels = list(region.getdata())
    neutral_bright = sum(
        1
        for red, green, blue in pixels
        if max(red, green, blue) >= 190 and min(red, green, blue) >= 150
    )
    fraction = float(neutral_bright) / len(pixels) if pixels else 0.0
    return {
        "path": path,
        "width": width,
        "height": height,
        "neutralBrightFraction": round(fraction, 6),
        "minimumFraction": MIN_NEUTRAL_BRIGHT_FRACTION,
        "startReady": fraction >= MIN_NEUTRAL_BRIGHT_FRACTION,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True)
    args = parser.parse_args()

    try:
        result = score(args.image)
    except Exception as exc:  # noqa: BLE001 - return a closed gate to the caller
        print(json.dumps({"error": str(exc), "startReady": False}, sort_keys=True))
        return 2

    print(json.dumps(result, sort_keys=True))
    return 0 if result["startReady"] else 1


if __name__ == "__main__":
    sys.exit(main())
