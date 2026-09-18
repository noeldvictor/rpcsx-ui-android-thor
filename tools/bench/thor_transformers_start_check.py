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
MAX_HIGH_FREQUENCY_FRACTION = 0.20
HIGH_FREQUENCY_DELTA = 96
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

    # A broken RSX frame can contain a dense black-and-white noise band. Its
    # neutral-bright fraction is larger than the real legal text, so the first
    # gate alone can accept corruption. Count large changes between adjacent
    # pixels and reject that high-frequency pattern.
    region_width, region_height = region.size
    luminance = list(region.convert("L").getdata())
    high_frequency = 0
    adjacent_pairs = 0
    for row in range(region_height):
        offset = row * region_width
        for column in range(1, region_width):
            adjacent_pairs += 1
            if abs(luminance[offset + column] - luminance[offset + column - 1]) >= HIGH_FREQUENCY_DELTA:
                high_frequency += 1
    for row in range(1, region_height):
        offset = row * region_width
        previous = offset - region_width
        for column in range(region_width):
            adjacent_pairs += 1
            if abs(luminance[offset + column] - luminance[previous + column]) >= HIGH_FREQUENCY_DELTA:
                high_frequency += 1
    high_frequency_fraction = (
        float(high_frequency) / adjacent_pairs if adjacent_pairs else 0.0
    )
    start_ready = (
        fraction >= MIN_NEUTRAL_BRIGHT_FRACTION
        and high_frequency_fraction <= MAX_HIGH_FREQUENCY_FRACTION
    )
    return {
        "path": path,
        "width": width,
        "height": height,
        "neutralBrightFraction": round(fraction, 6),
        "minimumFraction": MIN_NEUTRAL_BRIGHT_FRACTION,
        "highFrequencyFraction": round(high_frequency_fraction, 6),
        "maximumHighFrequencyFraction": MAX_HIGH_FREQUENCY_FRACTION,
        "startReady": start_ready,
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
